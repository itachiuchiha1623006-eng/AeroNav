# AeroNav — Pollution-Based Navigation System

A pollution-aware route planning system for India, with per-segment AQI coloring, standard CPCB pollutant calculations, weather-adjusted scores, and a Node.js backend with Redis caching — delivered as a Flutter mobile app.

---

## User Review Required

> [!IMPORTANT]
> **OSRM Hosting Decision Required**
> For India-specific routing, you have two options:
> - **Option A (Free/Dev):** Use OSRM's public demo server (`router.project-osrm.org`) — already has India road data from OpenStreetMap. Zero setup, but limited rate.
> - **Option B (Production):** Self-host OSRM on a VPS with India OSM data from Geofabrik. Full control, no rate limits.
>
> I'll plan for **Option A during development** and **Option B for production**. Confirm if that works.

> [!IMPORTANT]
> **data.gov.in Dataset Target**
> I'll use the **CPCB Real-Time AQI API** available at `https://api.data.gov.in/resource/` for live station data across Indian cities. This gives PM2.5, PM10, NO₂, SO₂, CO, O₃ readings per station. An **API key from data.gov.in** is needed.
>
> **You'll need two API keys:** (1) data.gov.in API key, (2) OpenWeatherMap API key.

> [!WARNING]
> **Caching Strategy Note**
> Redis will be used for 30-min caching of AQI + weather data per grid cell (~1km resolution). Future improvements (Phase 2) will add intelligent cache invalidation based on weather change alerts and spatial caching buckets. This is planned but not built in Phase 1.

---

## System Architecture

```
Flutter App
    │
    ▼
Node.js Backend (Express + Redis)
    ├── OSRM Service        → route segments (1km each)
    ├── AQI Service         → data.gov.in CPCB station data
    ├── Weather Service     → OpenWeatherMap API
    ├── Score Engine        → CPCB sub-index formula + weather modifier
    ├── Cache Layer         → Redis (30-min TTL per segment cell)
    └── Color Mapper        → AQI value → segment hex color
```

---

## Proposed Changes

### Phase 1: Node.js Backend Setup

#### [NEW] `aeronav-backend/` — Node.js Express Project

**Tech Stack:** Express.js, Axios, Redis (via `ioredis`), dotenv, node-cache fallback

**Directory Structure:**
```
aeronav-backend/
├── src/
│   ├── routes/
│   │   └── navigation.js       # POST /api/route
│   │   └── aqi.js              # GET /api/aqi/:lat/:lng
│   ├── services/
│   │   ├── osrmService.js      # Fetch route from OSRM, split to 1km
│   │   ├── aqiService.js       # Fetch + interpolate CPCB data
│   │   ├── weatherService.js   # OpenWeatherMap fetch
│   │   ├── scoreEngine.js      # CPCB sub-index formula
│   │   ├── colorMapper.js      # AQI → color (6-tier CPCB standard)
│   │   └── cacheService.js     # Redis 30-min TTL wrapper
│   ├── utils/
│   │   ├── geoUtils.js         # Haversine, segment splitting
│   │   └── interpolation.js    # Spatial interpolation from stations
│   └── app.js                  # Express setup
├── .env
└── package.json
```

---

### Phase 2: OSRM Route Segmentation Service

#### [NEW] `src/services/osrmService.js`

**Flow:**
1. Accept `origin {lat,lng}` + `destination {lat,lng}`
2. Call OSRM API: `http://router.project-osrm.org/route/v1/driving/{lng,lat};{lng,lat}?geometries=geojson&overview=full`
3. Extract polyline geometry (GeoJSON LineString)
4. **Split route into 1km segments** using Haversine distance
5. Return array of segments: `[{ startPoint, endPoint, midpoint, distanceKm }]`

**Segment splitting logic:**
- Walk along the GeoJSON coordinates
- Accumulate distance using Haversine
- Every ~1km, close the segment and store its midpoint (used for AQI lookup)

---

### Phase 3: AQI Calculation Engine

#### [NEW] `src/services/aqiService.js`

**Data Source:** `data.gov.in` CPCB AQI API
- Endpoint: `https://api.data.gov.in/resource/{resource_id}?api-key={KEY}&format=json&limit=500`
- Pollutants: **PM2.5, PM10, NO₂, SO₂, CO, O₃** (CPCB standard 6)

**Spatial Interpolation:**
- For each segment midpoint, find the **3 nearest AQI monitoring stations** (within 50km)
- Apply **Inverse Distance Weighting (IDW)** interpolation to estimate pollutant concentrations at that point

#### [NEW] `src/services/scoreEngine.js`

**CPCB Sub-Index Formula (official):**

Each pollutant gets a sub-index using the piecewise linear formula:
```
Ip = [(IHi - ILo) / (BPHi - BPLo)] × (Cp - BPLo) + ILo
```
Where:
- `Cp` = measured concentration
- `BPHi/BPLo` = breakpoint concentration (CPCB table)
- `IHi/ILo` = AQI index values for that breakpoint range

Final AQI = **maximum of all sub-indices** (CPCB standard)

**Weather Modifier (additive adjustment):**
| Condition | Effect |
|-----------|--------|
| Wind speed > 20 km/h | −10% AQI (dispersion) |
| Wind speed < 5 km/h | +15% AQI (stagnation/accumulation) |
| Rainfall > 2.5mm/hr | −20% AQI (washout) |
| Heavy rain > 7.5mm/hr | −35% AQI |
| Humidity > 85% | +5% AQI (hygroscopic growth) |

Final score = `AQI × weatherMultiplier`, clamped to `[0, 500]`

#### [NEW] CPCB Breakpoint Table

| AQI Range | Category | Hex Color |
|-----------|----------|-----------|
| 0–50 | Good | `#00E400` |
| 51–100 | Satisfactory | `#92D14F` |
| 101–200 | Moderate | `#FFFF00` |
| 201–300 | Poor | `#FF7E00` |
| 301–400 | Very Poor | `#FF0000` |
| 401–500 | Severe | `#7E0023` |

---

### Phase 4: Weather Service

#### [NEW] `src/services/weatherService.js`

**API:** OpenWeatherMap Current Weather
- Endpoint: `https://api.openweathermap.org/data/2.5/weather?lat={lat}&lon={lon}&appid={KEY}`
- Extract: `wind.speed`, `wind.deg`, `rain.1h` (or `rain.3h`), `main.humidity`

Cached per `~5km grid cell` for 30 minutes in Redis.

---

### Phase 5: Caching Layer

#### [NEW] `src/services/cacheService.js`

**Strategy:**
- Key format: `aqi:{gridLat}:{gridLng}` where grid = round to 0.01° (~1km cells)
- Weather key: `weather:{gridLat}:{gridLng}`
- TTL: **1800 seconds (30 min)** for AQI, **900 seconds (15 min)** for weather
- Fallback: `node-cache` (in-memory) if Redis is unavailable

**Phase 2 Caching Improvements (planned, not built yet):**
- Spatial buckets (H3 hexagonal grid)
- Predictive pre-warming based on popular routes
- Webhook from OpenWeatherMap alerts to invalidate stale cache on sudden weather change

---

### Phase 6: API Response Contract

#### `POST /api/route`
**Request:**
```json
{
  "origin": { "lat": 28.6139, "lng": 77.2090 },
  "destination": { "lat": 28.5355, "lng": 77.3910 }
}
```
**Response:**
```json
{
  "totalDistanceKm": 18.4,
  "estimatedTimeMin": 42,
  "overallAqi": 187,
  "overallCategory": "Moderate",
  "overallColor": "#FFFF00",
  "segments": [
    {
      "id": 1,
      "startPoint": { "lat": 28.6139, "lng": 77.2090 },
      "endPoint": { "lat": 28.6050, "lng": 77.2180 },
      "distanceKm": 1.02,
      "aqi": 143,
      "category": "Moderate",
      "color": "#FFFF00",
      "pollutants": {
        "pm25": 61.2,
        "pm10": 98.4,
        "no2": 42.1,
        "so2": 15.3,
        "co": 1.2,
        "o3": 88.5
      },
      "weather": {
        "windSpeed": 12.4,
        "windDeg": 210,
        "rainfall": 0.0,
        "humidity": 68
      },
      "weatherAdjustment": -5
    }
  ]
}
```

---

### Phase 7: Flutter Frontend Integration

#### [MODIFY] Existing AeroNav Flutter App

**Changes required in Flutter:**

1. **`lib/services/navigation_service.dart`** — New API service
   - Call `POST /api/route` with origin + destination
   - Parse segments response

2. **`lib/models/route_segment.dart`** — New model
   - Fields: `startPoint, endPoint, aqi, color, pollutants, weather`

3. **`lib/screens/navigation_screen.dart`** — Map with colored polylines
   - Render each segment as a separate `Polyline` with segment's `color`
   - Use `flutter_map` (Leaflet) or `google_maps_flutter`

4. **`lib/widgets/aqi_legend_widget.dart`** — Color legend strip
   - Horizontal legend showing 6 CPCB tiers

5. **`lib/widgets/route_info_panel.dart`** — Bottom sheet
   - Shows overall AQI, category, weather info
   - Per-segment tap → shows pollutant breakdown popup

6. **`lib/widgets/segment_detail_popup.dart`** — Tap on segment
   - Pollutant bars (PM2.5, PM10, NO₂, SO₂, CO, O₃)
   - Weather conditions at that segment
   - Weather adjustment indicator (+/- %)

---

## Open Questions

> [!IMPORTANT]
> **Do you already have API keys for:**
> - `data.gov.in` (free registration at https://data.gov.in/user/register)?
> - `OpenWeatherMap` (free tier: 1000 calls/day)?
>
> If not, I'll add API key setup instructions to the plan.

> [!WARNING]
> **Map Library for Flutter**
> The existing AeroNav app — does it use `google_maps_flutter` or `flutter_map`? Segment coloring (multiple colored polylines) works on both, but implementation differs. I'll check the existing code when I start.

> [!NOTE]
> **Backend Hosting**
> For MVP, I'll assume we run Node.js locally (or Railway.app/Render free tier). No Kubernetes or complex infra needed at this stage.

---

## Implementation Phases & Milestones

| Phase | Task | Est. Time |
|-------|------|-----------|
| 1 | Node.js project scaffold, .env, Redis setup | 1 hr |
| 2 | OSRM integration + 1km segment splitting | 2 hrs |
| 3 | data.gov.in AQI fetch + IDW interpolation | 2 hrs |
| 4 | CPCB sub-index formula + weather modifier | 2 hrs |
| 5 | Redis caching layer (30 min TTL) | 1 hr |
| 6 | `/api/route` endpoint assembly + testing | 1 hr |
| 7 | Flutter: route segment color rendering | 2 hrs |
| 8 | Flutter: AQI legend + segment detail popup | 1.5 hrs |
| 9 | End-to-end integration test | 1 hr |

**Total: ~13-14 hours of implementation**

---

## Verification Plan

### Automated Tests
- Unit test `scoreEngine.js` with known CPCB breakpoint values
- Unit test `geoUtils.js` segment splitting against known distances
- Integration test `/api/route` with `Delhi → Noida` and verify ≥5 segments returned

### Manual Verification
- Render Flutter app on emulator → draw route Delhi to Noida
- Confirm route polyline has multiple colored segments (not one flat color)
- Tap a segment → confirm pollutant breakdown popup appears
- Wait 31 minutes and re-request same route → confirm fresh API calls (cache miss)
- Compare segment AQI color with CPCB live dashboard for sanity check
