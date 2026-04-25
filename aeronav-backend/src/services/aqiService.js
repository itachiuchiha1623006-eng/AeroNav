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
      const response = await axios.get(url, { timeout: 15000 });
      
      const stationsData = response.data.records || [];
      
      const parsedStations = stationsData.map(record => {
        // Find coordinates for the station using the local JSON file
        const stationKey = record.station ? `${record.station}, ${record.city}` : record.city;
        const coords = this.stationCoords[stationKey] || this.stationCoords[`${record.station}, ${record.city} - CPCB`] || this.stationCoords[`${record.station}, ${record.city} - DPCC`] || this.mockLatLng(record.city);

        // API returns latitude/longitude strings; fall back to station_coords.json
        const lat = parseFloat(record.latitude) || coords.lat;
        const lng = parseFloat(record.longitude) || coords.lng;

        // Normalize pollutant_id: 'PM2.5' -> 'pm25', 'PM10' -> 'pm10', 'NO2' -> 'no2', etc.
        const rawPollutant = (record.pollutant_id || '').toUpperCase().replace('.', '').replace('-', '');
        const pollutantMap = { 'PM25': 'pm25', 'PM10': 'pm10', 'NO2': 'no2', 'SO2': 'so2', 'CO': 'co', 'O3': 'o3', 'OZONE': 'o3', 'NH3': 'nh3' };
        const pollutant = pollutantMap[rawPollutant] || rawPollutant.toLowerCase();

        // API returns avg_value (not pollutant_avg)
        const avg = parseFloat(record.avg_value) || null;

        return {
          id: record.station || stationKey,
          city: record.city,
          station: record.station,
          lat,
          lng,
          pollutant,
          avg
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

  /**
   * Fetch real-time pollutants for an exact point using data.gov.in (CPCB).
   * Calculates using Inverse Distance Weighting (IDW) interpolation from nearby stations.
   */
  async calculatePollutantsForPoint(lat, lng) {
    const cacheKey = `aqi_point_${Math.round(lat * 100) / 100}_${Math.round(lng * 100) / 100}`;
    const cachedData = await cacheService.get(cacheKey);

    if (cachedData) {
      return cachedData;
    }

    // Use only data.gov.in (CPCB) data via IDW
    return this._calculateFromCPCB(lat, lng, cacheKey);
  }

  /** IDW-based calculation from CPCB station data. */
  async _calculateFromCPCB(lat, lng, cacheKey) {
    const stations = await this.fetchRawStations();

    const polls = { pm25: [], pm10: [], no2: [], so2: [], co: [], o3: [] };
    stations.forEach(st => {
      Object.keys(polls).forEach(p => {
        if (st.pollutants[p] !== undefined) {
          polls[p].push({ lat: st.lat, lng: st.lng, value: st.pollutants[p] });
        }
      });
    });

    const targetPoint = { lat, lng };
    const IDW_POWER = 3;

    const nearestValue = (pollArr) => {
      if (!pollArr.length) return null;
      const idwVal = calculateIDW(targetPoint, pollArr, IDW_POWER, 25);
      if (idwVal !== null) return idwVal;
      return calculateIDW(targetPoint, pollArr, IDW_POWER, Infinity);
    };

    const resultPollutants = {
      pm25: nearestValue(polls.pm25),
      pm10: nearestValue(polls.pm10),
      no2:  nearestValue(polls.no2),
      so2:  nearestValue(polls.so2),
      co:   nearestValue(polls.co),
      o3:   nearestValue(polls.o3)
    };

    console.log('[AQI] CPCB IDW pollutants:', JSON.stringify(resultPollutants));
    await cacheService.set(cacheKey, resultPollutants, 300);
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
    // Expanded mock stations for better IDW coverage across India
    return [
      // Delhi / NCR
      { lat: 28.61, lng: 77.20, pollutants: { pm25: 180, pm10: 250, no2: 60, so2: 18, co: 2.1, o3: 32 } },
      { lat: 28.52, lng: 77.25, pollutants: { pm25: 220, pm10: 300, no2: 80, so2: 22, co: 2.5, o3: 28 } },
      { lat: 28.70, lng: 77.10, pollutants: { pm25: 110, pm10: 160, no2: 40, so2: 12, co: 1.5, o3: 35 } },
      { lat: 28.45, lng: 77.03, pollutants: { pm25: 160, pm10: 210, no2: 55, so2: 16, co: 1.8, o3: 30 } },
      // Mumbai
      { lat: 19.07, lng: 72.87, pollutants: { pm25: 60, pm10: 90, no2: 30, so2: 8, co: 1.0, o3: 25 } },
      { lat: 19.18, lng: 72.98, pollutants: { pm25: 75, pm10: 105, no2: 35, so2: 10, co: 1.2, o3: 22 } },
      // Bangalore
      { lat: 12.97, lng: 77.59, pollutants: { pm25: 45, pm10: 60, no2: 25, so2: 6, co: 0.8, o3: 20 } },
      { lat: 13.03, lng: 77.53, pollutants: { pm25: 50, pm10: 70, no2: 28, so2: 7, co: 0.9, o3: 22 } },
      // Chennai
      { lat: 13.08, lng: 80.27, pollutants: { pm25: 55, pm10: 80, no2: 32, so2: 9, co: 1.1, o3: 28 } },
      // Kolkata
      { lat: 22.57, lng: 88.36, pollutants: { pm25: 130, pm10: 190, no2: 50, so2: 15, co: 1.7, o3: 26 } },
      // Hyderabad
      { lat: 17.39, lng: 78.49, pollutants: { pm25: 70, pm10: 100, no2: 38, so2: 11, co: 1.3, o3: 24 } },
      // Pune
      { lat: 18.52, lng: 73.86, pollutants: { pm25: 65, pm10: 95, no2: 34, so2: 9, co: 1.1, o3: 23 } },
      // Ahmedabad
      { lat: 23.03, lng: 72.58, pollutants: { pm25: 95, pm10: 135, no2: 42, so2: 13, co: 1.4, o3: 29 } },
      // Jaipur
      { lat: 26.91, lng: 75.79, pollutants: { pm25: 105, pm10: 150, no2: 45, so2: 14, co: 1.6, o3: 31 } },
      // Lucknow
      { lat: 26.85, lng: 80.95, pollutants: { pm25: 145, pm10: 205, no2: 52, so2: 17, co: 1.9, o3: 29 } },
    ];
  }
}

module.exports = new AQIService();
