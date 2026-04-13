const axios = require('axios');
const cacheService = require('./cacheService');

class WeatherService {
  constructor() {
    this.apiKey = process.env.OPENWEATHERMAP_API_KEY;
    this.baseUrl = 'https://api.openweathermap.org/data/2.5/weather';
  }

  async getWeatherForCoords(lat, lng) {
    const cacheKey = `weather_${Math.round(lat * 10) / 10}_${Math.round(lng * 10) / 10}`;
    const cachedData = await cacheService.get(cacheKey);

    if (cachedData) {
      return cachedData;
    }

    try {
      if (!this.apiKey || this.apiKey === 'your_openweathermap_api_key_here') {
        // Mock data for development
        console.warn('Using mock weather data. Provide OPENWEATHERMAP_API_KEY for real data.');
        return { windSpeed: 12, rainfall: 0, humidity: 60 };
      }

      const url = `${this.baseUrl}?lat=${lat}&lon=${lng}&appid=${this.apiKey}&units=metric`;
      const response = await axios.get(url, { timeout: 4000 });
      const data = response.data;

      const weather = {
        windSpeed: data.wind ? data.wind.speed * 3.6 : 0, // convert m/s to km/h
        rainfall: data.rain ? (data.rain['1h'] || 0) : 0,
        humidity: data.main ? data.main.humidity : 50,
      };

      // Cache weather data for 30 minutes
      await cacheService.set(cacheKey, weather, 1800);
      return weather;
    } catch (error) {
      console.error(`Error fetching weather for ${lat},${lng}:`, error.message);
      // Failover default weather
      return { windSpeed: 5, rainfall: 0, humidity: 50 }; 
    }
  }
}

module.exports = new WeatherService();
