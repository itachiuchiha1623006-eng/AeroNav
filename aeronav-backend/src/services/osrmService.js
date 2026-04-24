const axios = require('axios');
const cacheService = require('./cacheService');

class OSRMService {
  constructor() {
    // using public demo for MVP, configure custom for prod
    this.baseUrl = process.env.OSRM_BASE_URL || 'http://router.project-osrm.org/route/v1/driving'; 
  }

  async getRoute(startCoords, endCoords) {
    const { lng: slng, lat: slat } = startCoords;
    const { lng: elng, lat: elat } = endCoords;

    const cacheKey = `osrm_${slng},${slat}_${elng},${elat}`;
    const cachedData = await cacheService.get(cacheKey);

    if (cachedData) {
      return cachedData;
    }

    try {
      const url = `${this.baseUrl}/${slng},${slat};${elng},${elat}?overview=full&geometries=geojson&steps=true&annotations=true`;
      const response = await axios.get(url, { timeout: 10000 });
      
      const routeData = response.data;
      if (!routeData.routes || routeData.routes.length === 0) {
        throw new Error('No routes found');
      }

      await cacheService.set(cacheKey, routeData.routes[0], 3600); // cache route mostly static, 1 hr
      return routeData.routes[0];
    } catch (error) {
      console.error('OSRM fetch error:', error.message);
      throw error;
    }
  }
}

module.exports = new OSRMService();
