const express = require('express');
const router = express.Router();
const osrmService = require('../services/osrmService');
const aqiService = require('../services/aqiService');
const weatherService = require('../services/weatherService');
const { calculateBaseAQI, calculateWeatherModifiers } = require('../services/scoreEngine');
const { getCategoryAndColor } = require('../services/colorMapper');
const { splitRouteIntoSegments } = require('../utils/geoUtils');

router.post('/route', async (req, res) => {
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

    // 3. Process each segment
    const processedSegments = await Promise.all(segments.map(async (segment) => {
      // Fetch Pollutants at Segment Midpoint via IDW
      const pollutants = await aqiService.calculatePollutantsForPoint(segment.midpoint.lat, segment.midpoint.lng);
      
      // Calculate Base AQI
      const baseAqi = calculateBaseAQI(pollutants);

      // Fetch Weather
      const weather = await weatherService.getWeatherForCoords(segment.midpoint.lat, segment.midpoint.lng);

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

    res.json({
      summary: {
        totalDistanceKm: Number((route.distance / 1000).toFixed(2)),
        totalDurationMin: Number((route.duration / 60).toFixed(1)),
        overallAqi: maxAqiSegment ? maxAqiSegment.aqi.final : 0,
        overallCategory: maxAqiSegment ? maxAqiSegment.aqi.category : 'Unknown',
        overallColor: maxAqiSegment ? maxAqiSegment.aqi.color : '#808080'
      },
      segments: processedSegments
    });

  } catch (error) {
    console.error('Route evaluation error:', error);
    res.status(500).json({ error: 'Failed to process pollution route', details: error.message });
  }
});

module.exports = router;
