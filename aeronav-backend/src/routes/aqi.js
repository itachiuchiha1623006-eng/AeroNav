const express = require('express');
const router = express.Router();
const aqiService = require('../services/aqiService');
const weatherService = require('../services/weatherService');
const { calculateBaseAQI, calculateWeatherModifiers } = require('../services/scoreEngine');
const { getCategoryAndColor } = require('../services/colorMapper');

router.get('/point', async (req, res) => {
  try {
    const { lat, lng } = req.query;

    if (!lat || !lng) {
      return res.status(400).json({ error: 'lat and lng parameters are required.' });
    }

    const pollutants = await aqiService.calculatePollutantsForPoint(parseFloat(lat), parseFloat(lng));
    const baseAqi = calculateBaseAQI(pollutants);
    const weather = await weatherService.getWeatherForCoords(parseFloat(lat), parseFloat(lng));
    const { finalAqi, percentageAdjust } = calculateWeatherModifiers(baseAqi, weather);
    const { category, color } = getCategoryAndColor(finalAqi);

    res.json({
      aqi: finalAqi,
      category,
      color,
      pollutants,
      weather
    });

  } catch (error) {
    console.error('AQI point fetch error:', error);
    res.status(500).json({ error: 'Failed to fetch AQI for point', details: error.message });
  }
});

module.exports = router;
