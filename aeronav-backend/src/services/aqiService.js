const axios = require('axios');
const cacheService = require('./cacheService');
const { calculateIDW } = require('../utils/interpolation');
const { haversineDistance } = require('../utils/geoUtils');

class AQIService {
  constructor() {
    this.apiKey = process.env.DATAGOVIN_API_KEY;
    this.baseUrl = 'https://api.data.gov.in/resource/3b01bcb8-0b14-4abf-b6f2-c1bfd384ba69';
  }

  // ─── Station Fetching ──────────────────────────────────────────────────────

  /**
   * Fetches all CPCB stations from data.gov.in with their real-time pollutant readings.
   * The API returns lat/lng directly, so no local coordinate lookup is needed.
   * Results are cached for 15 minutes (CPCB data updates ~hourly).
   */
  async fetchRawStations() {
    const cacheKey = 'cpcb_stations_data';
    const cachedData = await cacheService.get(cacheKey);
    if (cachedData) {
      return cachedData;
    }

    try {
      if (!this.apiKey || this.apiKey === 'your_datagov_api_key_here') {
        console.warn('[AQI] No DATAGOVIN_API_KEY — falling back to mock stations.');
        return this.getMockStations();
      }

      // Fetch all records — API has ~3400+ entries covering India
      const url = `${this.baseUrl}?api-key=${this.apiKey}&format=json&limit=5000`;
      const response = await axios.get(url, { timeout: 20000 });

      const records = response.data.records || [];
      console.log(`[AQI] data.gov.in returned ${records.length} raw records.`);

      // Normalize pollutant_id strings to internal keys
      const pollutantMap = {
        'PM2.5': 'pm25', 'PM10': 'pm10',
        'NO2':   'no2',  'SO2':  'so2',
        'CO':    'co',   'O3':   'o3',   'OZONE': 'o3', 'NH3': 'nh3'
      };

      // Group records by station (keyed by rounded lat_lng)
      const grouped = {};
      for (const record of records) {
        const lat = parseFloat(record.latitude);
        const lng = parseFloat(record.longitude);

        // Skip records with no valid GPS coordinates
        if (isNaN(lat) || isNaN(lng) || lat === 0 || lng === 0) continue;

        const avg = parseFloat(record.avg_value);
        if (isNaN(avg) || avg < 0) continue; // skip missing / bad readings

        const rawId = (record.pollutant_id || '').toUpperCase().trim();
        const pollutant = pollutantMap[rawId] || rawId.toLowerCase();

        const key = `${lat.toFixed(4)}_${lng.toFixed(4)}`;
        if (!grouped[key]) {
          grouped[key] = { lat, lng, pollutants: {} };
        }
        grouped[key].pollutants[pollutant] = avg;
      }

      const result = Object.values(grouped);
      console.log(`[AQI] Parsed ${result.length} unique live CPCB stations.`);

      if (result.length === 0) {
        console.warn('[AQI] No valid stations parsed — falling back to mock data.');
        return this.getMockStations();
      }

      await cacheService.set(cacheKey, result, 900); // 15-min cache
      return result;

    } catch (error) {
      console.error('[AQI] Failed to fetch CPCB live data:', error.message, '— using mock stations.');
      return this.getMockStations();
    }
  }

  async fetchStationsForBoundingBox(swLat, swLng, neLat, neLng) {
    const allStations = await this.fetchRawStations();
    const margin = 0.5;
    return allStations.filter(st =>
      st.lat >= (swLat - margin) && st.lat <= (neLat + margin) &&
      st.lng >= (swLng - margin) && st.lng <= (neLng + margin)
    );
  }

  // ─── Point AQI Calculation ─────────────────────────────────────────────────

  /**
   * Returns pollutant concentrations for a single point via IDW interpolation.
   */
  async calculatePollutantsForPoint(lat, lng) {
    const cacheKey = `aqi_point_${Math.round(lat * 100) / 100}_${Math.round(lng * 100) / 100}`;
    const cachedData = await cacheService.get(cacheKey);
    if (cachedData) return cachedData;

    const results = await this.calculatePollutantsForPoints([{ lat, lng }]);
    return results[0];
  }

  /**
   * Batch version — processes multiple points efficiently by fetching stations once.
   */
  async calculatePollutantsForPoints(points) {
    const stations = await this.fetchRawStations();

    // Build per-pollutant arrays for IDW
    const polls = { pm25: [], pm10: [], no2: [], so2: [], co: [], o3: [] };
    for (const st of stations) {
      for (const p of Object.keys(polls)) {
        if (st.pollutants[p] !== undefined) {
          polls[p].push({ lat: st.lat, lng: st.lng, value: st.pollutants[p] });
        }
      }
    }

    const IDW_POWER = 3;
    const results = [];

    for (const point of points) {
      const { lat, lng } = point;
      const cacheKey = `aqi_point_${Math.round(lat * 100) / 100}_${Math.round(lng * 100) / 100}`;
      const cachedData = await cacheService.get(cacheKey);
      if (cachedData) {
        results.push(cachedData);
        continue;
      }

      const targetPoint = { lat, lng };

      const nearestValue = (pollArr, baseline) => {
        if (!pollArr.length) return baseline;

        const localVal = calculateIDW(targetPoint, pollArr, IDW_POWER, 25);
        if (localVal !== null) return localVal;

        const regionalVal = calculateIDW(targetPoint, pollArr, IDW_POWER, 150);
        if (regionalVal !== null) return regionalVal;

        // Fallback: weighted blend toward nearest station up to 500 km
        let minStation = null;
        let minDist = Infinity;
        for (const st of pollArr) {
          const d = haversineDistance(targetPoint, { lat: st.lat, lng: st.lng });
          if (d < minDist) { minDist = d; minStation = st; }
        }
        if (!minStation || minDist >= 500) return baseline;

        const ratio = 1 - ((minDist - 150) / (500 - 150));
        return (minStation.value * ratio) + (baseline * (1 - ratio));
      };

      const resultPollutants = {
        pm25: nearestValue(polls.pm25, 20),
        pm10: nearestValue(polls.pm10, 40),
        no2:  nearestValue(polls.no2,  10),
        so2:  nearestValue(polls.so2,  5),
        co:   nearestValue(polls.co,   0.5),
        o3:   nearestValue(polls.o3,   20)
      };

      await cacheService.set(cacheKey, resultPollutants, 300); // 5-min per-point cache
      results.push(resultPollutants);
    }

    return results;
  }

  /** Convenience wrapper kept for backward compatibility. */
  async _calculateFromCPCB(lat, lng, cacheKey) {
    const results = await this.calculatePollutantsForPoints([{ lat, lng }]);
    console.log('[AQI] IDW pollutants:', JSON.stringify(results[0]));
    return results[0];
  }

  // ─── Mock Fallback ──────────────────────────────────────────────────────────

  /**
   * Fallback mock stations used ONLY when CPCB API is unavailable.
   * Values represent realistic April / annual-average conditions, NOT peak winter smog.
   */
  getMockStations() {
    return [
      // Delhi / NCR — April avg PM2.5 ~80-100 µg/m³ → AQI ~185-225
      { lat: 28.61, lng: 77.20, pollutants: { pm25: 95,  pm10: 140, no2: 48, so2: 12, co: 1.4, o3: 30 } },
      { lat: 28.52, lng: 77.25, pollutants: { pm25: 105, pm10: 155, no2: 55, so2: 14, co: 1.6, o3: 27 } },
      { lat: 28.70, lng: 77.10, pollutants: { pm25: 75,  pm10: 110, no2: 36, so2: 9,  co: 1.1, o3: 33 } },
      { lat: 28.45, lng: 77.03, pollutants: { pm25: 88,  pm10: 130, no2: 42, so2: 11, co: 1.3, o3: 28 } },
      // UP Corridor (anchors for Delhi → Lucknow route)
      { lat: 28.00, lng: 78.08, pollutants: { pm25: 62,  pm10: 95,  no2: 28, so2: 7,  co: 0.9,  o3: 24 } }, // Aligarh
      { lat: 27.38, lng: 78.48, pollutants: { pm25: 55,  pm10: 85,  no2: 25, so2: 6,  co: 0.8,  o3: 22 } }, // Etah
      { lat: 28.37, lng: 79.43, pollutants: { pm25: 58,  pm10: 88,  no2: 27, so2: 7,  co: 0.85, o3: 23 } }, // Bareilly
      { lat: 26.47, lng: 80.35, pollutants: { pm25: 78,  pm10: 115, no2: 38, so2: 10, co: 1.1,  o3: 25 } }, // Kanpur
      // Lucknow — April avg PM2.5 ~70-90 µg/m³ → AQI ~170-200
      { lat: 26.85, lng: 80.95, pollutants: { pm25: 82,  pm10: 120, no2: 40, so2: 11, co: 1.2, o3: 26 } },
      { lat: 26.90, lng: 80.80, pollutants: { pm25: 70,  pm10: 105, no2: 36, so2: 9,  co: 1.0, o3: 24 } },
      // Other metros
      { lat: 19.07, lng: 72.87, pollutants: { pm25: 48,  pm10: 75,  no2: 30, so2: 8,  co: 0.9, o3: 25 } }, // Mumbai
      { lat: 19.18, lng: 72.98, pollutants: { pm25: 55,  pm10: 88,  no2: 35, so2: 10, co: 1.0, o3: 22 } },
      { lat: 12.97, lng: 77.59, pollutants: { pm25: 38,  pm10: 58,  no2: 25, so2: 6,  co: 0.7, o3: 20 } }, // Bangalore
      { lat: 13.03, lng: 77.53, pollutants: { pm25: 42,  pm10: 65,  no2: 28, so2: 7,  co: 0.8, o3: 22 } },
      { lat: 13.08, lng: 80.27, pollutants: { pm25: 45,  pm10: 70,  no2: 30, so2: 8,  co: 0.8, o3: 25 } }, // Chennai
      { lat: 22.57, lng: 88.36, pollutants: { pm25: 85,  pm10: 130, no2: 45, so2: 13, co: 1.3, o3: 24 } }, // Kolkata
      { lat: 17.39, lng: 78.49, pollutants: { pm25: 52,  pm10: 80,  no2: 32, so2: 9,  co: 1.0, o3: 22 } }, // Hyderabad
      { lat: 18.52, lng: 73.86, pollutants: { pm25: 50,  pm10: 78,  no2: 30, so2: 8,  co: 0.9, o3: 21 } }, // Pune
      { lat: 23.03, lng: 72.58, pollutants: { pm25: 72,  pm10: 108, no2: 38, so2: 11, co: 1.2, o3: 26 } }, // Ahmedabad
      { lat: 26.91, lng: 75.79, pollutants: { pm25: 78,  pm10: 115, no2: 40, so2: 12, co: 1.3, o3: 28 } }, // Jaipur
    ];
  }
}

module.exports = new AQIService();
