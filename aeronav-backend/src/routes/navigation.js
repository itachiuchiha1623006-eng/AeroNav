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

    // 1. Get OSRM route
    const route = await osrmService.getRoute(start, end);
    const coordinates = route.geometry.coordinates; // [lng, lat] pairs

    // 2. Segment route (1km chunks)
    const segments = splitRouteIntoSegments(coordinates, 1.0);

    // 3. Batch fetch weather for N sampled points along the route
    const numWeatherSamples = Math.min(5, Math.max(2, Math.ceil(route.distance / 10000))); // 1 sample per 10km, max 5, min 2
    const sampledCoords = sampleRoutePoints(coordinates, numWeatherSamples);
    const weatherSamples = await weatherService.getWeatherForMultiplePoints(sampledCoords);

    // Helper to find closest weather sample
    const getClosestWeather = (lat, lng) => {
      let closest = weatherSamples[0];
      let minDist = Infinity;
      for (const w of weatherSamples) {
        const dist = Math.pow(w.lat - lat, 2) + Math.pow(w.lng - lng, 2);
        if (dist < minDist) {
          minDist = dist;
          closest = w;
        }
      }
      return closest;
    };

    // 4. Process each segment
    const processedSegments = await Promise.all(segments.map(async (segment) => {
      // Fetch Pollutants at Segment Midpoint via IDW
      const pollutants = await aqiService.calculatePollutantsForPoint(segment.midpoint.lat, segment.midpoint.lng);
      
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
    }));

    // Overall route summary
    const maxAqiSegment = processedSegments.reduce((max, seg) => 
      (seg.aqi.final > (max ? max.aqi.final : -1)) ? seg : max, null);

    const responseJSON = {
      summary: {
        totalDistanceKm: Number((route.distance / 1000).toFixed(2)),
        totalDurationMin: Number((route.duration / 60).toFixed(1)),
        overallAqi: maxAqiSegment ? maxAqiSegment.aqi.final : 0,
        overallCategory: maxAqiSegment ? maxAqiSegment.aqi.category : 'Unknown',
        overallColor: maxAqiSegment ? maxAqiSegment.aqi.color : '#808080'
      },
      segments: processedSegments
    };

    if (includeSteps && route.legs && route.legs.length > 0) {
      // OSRM returns steps in legs[0]
      responseJSON.steps = route.legs[0].steps.map(step => ({
        instruction: step.maneuver.instruction || `${step.maneuver.type} ${step.maneuver.modifier || ''}`.trim(),
        distanceM: step.distance,
        durationS: step.duration,
        maneuver: step.maneuver.type,
        modifier: step.maneuver.modifier,
        bearingAfter: step.maneuver.bearing_after,
        exitCoordinate: { lat: step.maneuver.location[1], lng: step.maneuver.location[0] }
      }));
    }

    res.json(responseJSON);

  } catch (error) {
    console.error('Route evaluation error:', error);
    res.status(500).json({ error: 'Failed to process pollution route', details: error.message });
  }
};

router.post('/route', (req, res) => processRoute(req, res, false));
router.post('/steps', (req, res) => processRoute(req, res, true));

module.exports = router;
