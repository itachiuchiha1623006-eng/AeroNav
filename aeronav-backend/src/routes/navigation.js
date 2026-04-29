const express = require('express');
const router = express.Router();
const osrmService = require('../services/osrmService');
const aqiService = require('../services/aqiService');
const weatherService = require('../services/weatherService');
const { calculateBaseAQI, calculateWeatherModifiers } = require('../services/scoreEngine');
const { getCategoryAndColor } = require('../services/colorMapper');
const { splitRouteIntoSegments } = require('../utils/geoUtils');
const { sampleRoutePoints } = require('../utils/routeSampler');

const processRoute = async (req, res, includeSteps = false) => {
  try {
    const { start, end } = req.body;
    
    if (!start || !end || !start.lat || !start.lng || !end.lat || !end.lng) {
      return res.status(400).json({ error: 'Valid start and end coordinates are required.' });
    }

    // 1. Get OSRM routes (now returns an array)
    const routes = await osrmService.getRoute(start, end);
    
    // Process each alternative route
    const processedRoutes = await Promise.all(routes.map(async (route) => {
      const coordinates = route.geometry.coordinates; // [lng, lat] pairs

      // 2. Segment route (1km chunks)
      const segments = splitRouteIntoSegments(coordinates, 1.0);

      // 3. Batch fetch weather for sampled points along the route
      const numWeatherSamples = Math.min(5, Math.max(2, Math.ceil(route.distance / 10000)));
      const sampledCoords = sampleRoutePoints(coordinates, numWeatherSamples);
      const weatherSamples = await weatherService.getWeatherForMultiplePoints(sampledCoords);

      // Helper to find closest weather sample
      const getClosestWeather = (lat, lng) => {
        if (!weatherSamples || weatherSamples.length === 0) return null;
        let closest = weatherSamples[0];
        let minDist = Infinity;
        for (const w of weatherSamples) {
          if (!w) continue;
          const dist = Math.pow(w.lat - lat, 2) + Math.pow(w.lng - lng, 2);
          if (dist < minDist) {
            minDist = dist;
            closest = w;
          }
        }
        return closest;
      };

      // 4. Batch fetch Pollutants at Segment Midpoints via IDW
      const segmentMidpoints = segments.map(seg => ({ lat: seg.midpoint.lat, lng: seg.midpoint.lng }));
      const segmentPollutants = await aqiService.calculatePollutantsForPoints(segmentMidpoints);

      // 5. Process each segment
      const processedSegments = segments.map((segment, index) => {
        const pollutants = segmentPollutants[index];
        
        // Calculate Base AQI
        const baseAqi = calculateBaseAQI(pollutants);

        // Fetch Weather
        const weather = getClosestWeather(segment.midpoint.lat, segment.midpoint.lng);

        // Apply Weather Modifier
        const { finalAqi, percentageAdjust } = calculateWeatherModifiers(baseAqi, weather);

        // Map to Color
        const { category, color } = getCategoryAndColor(finalAqi);

        return {
          id: segment.id,
          distanceKm: Number(segment.distanceKm.toFixed(2)),
          coordinates: segment.coordinates, // array of [lng, lat]
          aqi: {
            base: baseAqi,
            final: finalAqi,
            weatherAdjust: percentageAdjust,
            category,
            color,
            pollutants
          },
          weather
        };
      });

      // Overall route summary
      const maxAqiSegment = processedSegments.reduce((max, seg) => 
        (seg.aqi.final > (max ? max.aqi.final : -1)) ? seg : max, null);
      
      const avgAqi = processedSegments.length > 0 
        ? processedSegments.reduce((sum, seg) => sum + seg.aqi.final, 0) / processedSegments.length
        : 0;

      const overallAqiRounded = Math.round(avgAqi);
      const overallCategoryAndColor = getCategoryAndColor(overallAqiRounded);

      const routeJSON = {
        summary: {
          totalDistanceKm: Number((route.distance / 1000).toFixed(2)),
          totalDurationMin: Number((route.duration / 60).toFixed(1)),
          overallAqi: overallAqiRounded,
          maxAqi: maxAqiSegment ? maxAqiSegment.aqi.final : 0,
          overallCategory: overallCategoryAndColor.category,
          overallColor: overallCategoryAndColor.color
        },
        segments: processedSegments
      };

      if (includeSteps && route.legs && route.legs.length > 0) {
        routeJSON.steps = route.legs[0].steps.map(step => ({
          instruction: step.maneuver.instruction || `${step.maneuver.type} ${step.maneuver.modifier || ''}`.trim(),
          distanceM: step.distance,
          durationS: step.duration,
          maneuver: step.maneuver.type,
          modifier: step.maneuver.modifier,
          bearingAfter: step.maneuver.bearing_after,
          exitCoordinate: { lat: step.maneuver.location[1], lng: step.maneuver.location[0] }
        }));
      }
      
      return routeJSON;
    }));

    // Identify Fastest and Cleanest
    // Fastest = min duration
    // Cleanest = min average AQI
    let fastestRoute = processedRoutes[0];
    let cleanestRoute = processedRoutes[0];

    processedRoutes.forEach(r => {
      if (r.summary.totalDurationMin < fastestRoute.summary.totalDurationMin) fastestRoute = r;
      if (r.summary.overallAqi < cleanestRoute.summary.overallAqi) cleanestRoute = r;
    });

    // Mark them
    processedRoutes.forEach(r => {
      r.isFastest = (r === fastestRoute);
      r.isCleanest = (r === cleanestRoute) && (r !== fastestRoute || processedRoutes.length === 1); // Avoid marking both as true if there's only 1
    });

    const responseJSON = {
      routes: processedRoutes
    };

    res.json(responseJSON);

  } catch (error) {
    console.error('Route evaluation error:', error);
    res.status(500).json({ error: 'Failed to process pollution route', details: error.message });
  }
};

router.post('/route', (req, res) => processRoute(req, res, false));
router.post('/steps', (req, res) => processRoute(req, res, true));

module.exports = router;
