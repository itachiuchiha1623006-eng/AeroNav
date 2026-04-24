const axios = require('axios');
const cacheService = require('./cacheService');
const { calculateIDW } = require('../utils/interpolation');

class AQIService {
  constructor() {
    this.apiKey = process.env.DATAGOVIN_API_KEY;
    this.baseUrl = 'https://api.data.gov.in/resource/3b01bcb8-0b14-4abf-b6f2-c1bfd384ba69';
    try {
      this.stationCoords = require('../data/station_coords.json');
    } catch (e) {
      this.stationCoords = {};
    }
  }

  async fetchRawStations() {
    const cacheKey = 'cpcb_stations_data';
    const cachedData = await cacheService.get(cacheKey);

    if (cachedData) {
      return cachedData;
    }

    try {
      if (!this.apiKey || this.apiKey === 'your_datagov_api_key_here') {
        console.warn('Using mock CPCB station data. Provide DATAGOVIN_API_KEY for real data.');
        return this.getMockStations();
      }

      // We typically fetch a large limit, e.g., 500 for India coverage
      const url = `${this.baseUrl}?api-key=${this.apiKey}&format=json&limit=500`;
      const response = await axios.get(url, { timeout: 8000 });
      
      const stationsData = response.data.records || [];
      
      const parsedStations = stationsData.map(record => {
        // Find coordinates for the station using the local JSON file
        const stationKey = record.station ? `${record.station}, ${record.city}` : record.city;
        const coords = this.stationCoords[stationKey] || this.stationCoords[`${record.station}, ${record.city} - CPCB`] || this.stationCoords[`${record.station}, ${record.city} - DPCC`] || this.mockLatLng(record.city);

        return {
          id: record.id,
          city: record.city,
          station: record.station,
          lat: record.lat || coords.lat, 
          lng: record.lng || coords.lng,
          pollutant: record.pollutant_id.toLowerCase(),
          avg: parseFloat(record.pollutant_avg) || null
        };
      }).filter(s => s.avg !== null && !isNaN(s.lat) && !isNaN(s.lng));

      // Group by station
      const grouped = {};
      parsedStations.forEach(s => {
        const key = `${s.lat}_${s.lng}`;
        if (!grouped[key]) {
          grouped[key] = { lat: s.lat, lng: s.lng, pollutants: {} };
        }
        grouped[key].pollutants[s.pollutant] = s.avg;
      });

      const result = Object.values(grouped);

      // Cache the big dictionary for 15 minutes
      await cacheService.set(cacheKey, result, 900);
      return result;

    } catch (error) {
      console.error('Error fetching CPCB data:', error.message);
      return this.getMockStations();
    }
  }

  async fetchStationsForBoundingBox(swLat, swLng, neLat, neLng) {
    const allStations = await this.fetchRawStations();
    // Filter stations within the bounding box plus a small margin (e.g., 0.5 degrees)
    const margin = 0.5;
    return allStations.filter(st => {
      return st.lat >= (swLat - margin) && st.lat <= (neLat + margin) &&
             st.lng >= (swLng - margin) && st.lng <= (neLng + margin);
    });
  }

  async calculatePollutantsForPoint(lat, lng) {
    const cacheKey = `aqi_point_${Math.round(lat * 100) / 100}_${Math.round(lng * 100) / 100}`;
    const cachedData = await cacheService.get(cacheKey);

    if (cachedData) {
      return cachedData;
    }

    const stations = await this.fetchRawStations();

    // Setup arrays for IDW
    const polls = { pm25: [], pm10: [], no2: [], so2: [], co: [], o3: [] };
    
    stations.forEach(st => {
      Object.keys(polls).forEach(p => {
        if (st.pollutants[p] !== undefined) {
          polls[p].push({ lat: st.lat, lng: st.lng, value: st.pollutants[p] });
        }
      });
    });

    const targetPoint = { lat, lng };
    
    const resultPollutants = {
      pm25: calculateIDW(targetPoint, polls.pm25, 2, 80) || 50,
      pm10: calculateIDW(targetPoint, polls.pm10, 2, 80) || 100,
      no2: calculateIDW(targetPoint, polls.no2, 2, 80) || 40,
      so2: calculateIDW(targetPoint, polls.so2, 2, 80) || 10,
      co: calculateIDW(targetPoint, polls.co, 2, 80) || 1,
      o3: calculateIDW(targetPoint, polls.o3, 2, 80) || 30
    };

    await cacheService.set(cacheKey, resultPollutants, 900);
    return resultPollutants;
  }

  // Helper mocks for MVP
  mockLatLng(city) {
    const coords = {
      'Delhi': { lat: 28.6139, lng: 77.2090 },
      'Mumbai': { lat: 19.0760, lng: 72.8777 },
      'Bangalore': { lat: 12.9716, lng: 77.5946 },
    };
    return coords[city] || { lat: 28.6 + Math.random(), lng: 77.2 + Math.random() };
  }

  getMockStations() {
    return [
      { lat: 28.61, lng: 77.20, pollutants: { pm25: 180, pm10: 250, no2: 60 } },
      { lat: 28.52, lng: 77.25, pollutants: { pm25: 220, pm10: 300, no2: 80 } },
      { lat: 28.70, lng: 77.10, pollutants: { pm25: 110, pm10: 160, no2: 40 } },
      { lat: 19.07, lng: 72.87, pollutants: { pm25: 60, pm10: 90, no2: 30 } },
      { lat: 12.97, lng: 77.59, pollutants: { pm25: 45, pm10: 60, no2: 25 } },
    ];
  }
}

module.exports = new AQIService();
