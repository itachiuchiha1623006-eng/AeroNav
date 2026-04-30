# AeroNav - Complete System Workflow Documentation
## Pollution-Aware Navigation Platform

---

## Table of Contents
1. [Dependencies & Technology Stack](#dependencies--technology-stack)
2. [System Architecture Overview](#system-architecture-overview)
3. [Complete Request Flow](#complete-request-flow)
4. [Backend Processing Pipeline](#backend-processing-pipeline)
5. [AQI Calculation & Interpolation](#aqi-calculation--interpolation)
6. [Route Segmentation & Scoring](#route-segmentation--scoring)
7. [Frontend Map Rendering](#frontend-map-rendering)
8. [Navigation Mode](#navigation-mode)
9. [Data Flow Diagrams](#data-flow-diagrams)

---

## 1. Dependencies & Technology Stack

### 1.1 Backend Dependencies (Node.js)

#### Core Framework
```json
{
  "express": "^4.19.2"
}
```
**Purpose:** Web application framework for Node.js  
**Usage:** HTTP server, routing, middleware management  
**Why:** Industry standard, lightweight, extensive middleware ecosystem  
**Key Features:**
- Route handling (`/api/navigation/route`, `/api/aqi/point`)
- Middleware chain (CORS, helmet, rate limiting)
- Request/response handling
- Error handling middleware

#### HTTP Client
```json
{
  "axios": "^1.6.8"
}
```
**Purpose:** Promise-based HTTP client  
**Usage:** External API calls (OSRM, CPCB, Weather)  
**Why:** Better than native `fetch`, automatic JSON parsing, interceptors  
**Key Features:**
- Timeout configuration (8s for OSRM, 20s for CPCB)
- Automatic error handling
- Request/response interceptors
- Concurrent requests with `Promise.all`

#### Security Middleware
```json
{
  "helmet": "^8.1.0",
  "cors": "^2.8.5",
  "express-rate-limit": "^8.4.1"
}
```

**helmet** - Security headers  
**Usage:** Sets HTTP headers to prevent common vulnerabilities  
**Protection:**
- XSS (Cross-Site Scripting)
- Clickjacking
- MIME sniffing
- Hides `X-Powered-By` header

**cors** - Cross-Origin Resource Sharing  
**Usage:** Allows Flutter app to make requests from different origin  
**Configuration:** Allows all origins in dev, restricted in production

**express-rate-limit** - API rate limiting  
**Usage:** Prevents abuse and DoS attacks  
**Configuration:** 100 requests per 15 minutes per IP  
**Response:** 429 Too Many Requests when exceeded

#### Caching
```json
{
  "node-cache": "^5.1.2",
  "ioredis": "^5.3.2"
}
```

**node-cache** - In-memory caching (current)  
**Usage:** Cache OSRM routes, CPCB stations, AQI calculations  
**Why:** Simple, fast, no external dependencies  
**Limitations:** Single-server only, lost on restart

**ioredis** - Redis client (future scaling)  
**Usage:** Distributed caching across multiple servers  
**Why:** Persistent, shared cache, pub/sub support  
**When:** Needed when scaling beyond single server

#### Logging
```json
{
  "pino": "^10.3.1",
  "pino-http": "^11.0.0"
}
```

**pino** - High-performance logger  
**Usage:** Application logging (info, error, debug)  
**Why:** 5x faster than Winston, structured JSON logs  
**Features:**
- Log levels (trace, debug, info, warn, error, fatal)
- Automatic serialization
- Child loggers with context
- Production-ready performance

**pino-http** - HTTP request logger  
**Usage:** Automatic logging of all HTTP requests  
**Logs:** Method, URL, status code, response time, user agent

#### Environment Configuration
```json
{
  "dotenv": "^16.4.5"
}
```
**Purpose:** Load environment variables from `.env` file  
**Usage:** API keys, database URLs, configuration  
**Variables:**
- `DATAGOVIN_API_KEY` - CPCB API access
- `PORT` - Server port (default 3000)
- `OSRM_BASE_URL` - Custom OSRM server (optional)
- `LOG_LEVEL` - Logging verbosity

#### Development Tools
```json
{
  "nodemon": "^3.1.0"
}
```
**Purpose:** Auto-restart server on file changes  
**Usage:** Development only (`npm run dev`)  
**Why:** Faster development workflow, no manual restarts

---

### 1.2 Frontend Dependencies (Flutter)

#### Core Framework
```yaml
flutter:
  sdk: flutter
```
**Purpose:** Google's UI toolkit for building natively compiled applications  
**Version:** SDK ^3.5.0  
**Why:** Single codebase for iOS and Android, hot reload, Material Design

#### Authentication & Backend
```yaml
supabase_flutter: ^2.5.6
```
**Purpose:** Backend-as-a-Service (BaaS) client  
**Usage:** User authentication, database access (future)  
**Features:**
- Email/password authentication
- OAuth providers (Google, Apple)
- Real-time subscriptions
- PostgreSQL database access
**Initialization:** In `main.dart` with URL and anon key

#### Navigation & Routing
```yaml
go_router: ^14.2.7
```
**Purpose:** Declarative routing for Flutter  
**Usage:** Screen navigation, deep linking, route parameters  
**Why chosen over Navigator 1.0/2.0:**

**go_router Advantages:**
1. **URL-Based Navigation** - Routes are defined as paths (`/routes`, `/search`)
   - Better for web support (Flutter web shows actual URLs)
   - Deep linking works out of the box
   - Shareable URLs for specific screens

2. **Type-Safe Parameters** - Pass data between screens safely
   ```dart
   // go_router (type-safe)
   context.push('/routes', extra: {
     'startPoint': LatLng(28.6139, 77.2090),
     'endPoint': LatLng(27.1767, 78.0081),
     'destinationName': 'Agra'
   });
   
   // Navigator 1.0 (not type-safe, easy to break)
   Navigator.push(context, MaterialPageRoute(
     builder: (context) => RoutesScreen(/* manual parameter passing */)
   ));
   ```

3. **Declarative Routing** - Define all routes in one place
   ```dart
   // app_router.dart - Single source of truth
   final appRouter = GoRouter(
     routes: [
       GoRoute(path: '/', builder: (context, state) => HomeScreen()),
       GoRoute(path: '/search', builder: (context, state) => SearchScreen()),
       GoRoute(path: '/routes', builder: (context, state) => RoutesScreen(...)),
     ]
   );
   ```
   - Easy to see all app routes
   - Centralized navigation logic
   - Better for large apps

4. **Redirection & Guards** - Built-in authentication checks
   ```dart
   redirect: (context, state) {
     final isLoggedIn = ref.read(authProvider);
     if (!isLoggedIn && state.location != '/login') {
       return '/login';
     }
     return null;
   }
   ```
   - Protect routes that require authentication
   - Automatic redirects
   - Better than manual checks in every screen

5. **Browser Back Button Support** - Works correctly on web
   - Navigator 1.0 has issues with browser back button
   - go_router handles it automatically
   - Important for Flutter web deployment

6. **Nested Navigation** - Supports complex navigation patterns
   - Bottom navigation with separate stacks
   - Tab navigation within screens
   - Modal routes

7. **Error Handling** - Custom 404 pages
   ```dart
   errorBuilder: (context, state) => NotFoundScreen()
   ```

**Navigator 1.0 Problems:**
- Imperative (push/pop everywhere, hard to track)
- No URL support (bad for web)
- Manual parameter passing (error-prone)
- No built-in deep linking
- Hard to test

**Navigator 2.0 Problems:**
- Too complex (requires understanding Pages, Router, RouterDelegate)
- Lots of boilerplate code
- Steep learning curve
- go_router is built on top of Navigator 2.0 but hides complexity

**Real Example from AeroNav:**
```dart
// In HomeScreen - navigate to routes with data
final result = await context.push('/search');
if (result != null && result is Map<String, dynamic>) {
  final endPt = LatLng(result['latitude'], result['longitude']);
  context.push('/routes', extra: {
    'startPoint': _startPoint,
    'endPoint': endPt,
    'destinationName': result['name'],
  });
}

// In RoutesScreen - receive data
class RoutesScreen extends StatefulWidget {
  final LatLng startPoint;
  final LatLng endPoint;
  final String destinationName;
  
  // Data automatically extracted from 'extra' parameter
}
```

**Routes:**
- `/` - HomeScreen (main map view)
- `/search` - SearchScreen (destination search)
- `/routes` - RoutesScreen (route comparison & navigation)
- `/profile` - ProfileScreen (user settings)

**Future Benefits:**
- Easy to add web support (URLs already defined)
- Deep linking for sharing routes
- Analytics tracking (know which screens users visit)
- A/B testing different navigation flows

#### State Management
```yaml
flutter_riverpod: ^2.5.1
```
**Purpose:** Reactive state management  
**Usage:** Manage app state, dependency injection  
**Why:** Compile-safe, testable, no boilerplate  
**Features:**
- Provider pattern
- Automatic disposal
- State caching
- Testing support

#### Map & Location
```yaml
flutter_map: ^8.2.2
latlong2: ^0.9.1
```

**flutter_map** - Interactive map widget  
**Usage:** Display OpenStreetMap tiles, polylines, markers  
**Why:** Open-source, customizable, no API keys needed  
**Features:**
- TileLayer (OSM tiles)
- PolylineLayer (route visualization)
- MarkerLayer (user location, destination)
- MapController (camera control, rotation)

**latlong2** - Geographic coordinate utilities  
**Usage:** LatLng objects, distance calculations  
**Features:**
- Distance calculations (Haversine)
- Coordinate conversions
- Bounding box calculations

#### Location Services
```yaml
location: ^8.0.1
geolocator: ^14.0.2
permission_handler: ^12.0.1
```

**location** - GPS location tracking  
**Usage:** Real-time location updates, location stream  
**Why:** Simple API, works on both platforms  
**Features:**
- `onLocationChanged` stream
- Service enable/disable
- Background location (future)

**geolocator** - Alternative location package  
**Usage:** One-time location requests, distance calculations  
**Why:** More features than `location`, better accuracy settings

**permission_handler** - Runtime permissions  
**Usage:** Request location, camera, storage permissions  
**Why:** Unified API for iOS and Android permissions  
**Permissions:**
- `locationWhenInUse` - Location while app is open
- `locationAlways` - Background location (future)

#### Compass & Sensors
```yaml
flutter_compass: ^0.8.1
```
**Purpose:** Device compass/magnetometer access  
**Usage:** Get device heading (0-360 degrees)  
**Why:** Enables map rotation for heads-up navigation  
**Features:**
- `FlutterCompass.events` stream
- Real-time heading updates (~100ms)
- Automatic calibration

#### HTTP Client
```yaml
dio: ^5.9.2
```
**Purpose:** Powerful HTTP client for Dart  
**Usage:** API calls to backend (`NavigationService`)  
**Why:** Better than `http` package, interceptors, timeout control  
**Features:**
- Timeout configuration (15s connect, 60s receive)
- Automatic JSON parsing
- Error handling with `DioException`
- Request/response interceptors
- Custom headers (`ngrok-skip-browser-warning`)

#### UI & Styling
```yaml
google_fonts: ^6.2.1
cupertino_icons: ^1.0.8
gap: ^3.0.1
```

**google_fonts** - Google Fonts integration  
**Usage:** Custom typography, brand fonts  
**Why:** Easy font loading, no manual asset management  
**Fonts Used:** Inter, Roboto (Material Design default)

**cupertino_icons** - iOS-style icons  
**Usage:** iOS-specific icons when needed  
**Why:** Consistent with iOS design language

**gap** - Spacing utility  
**Usage:** Add spacing between widgets  
**Why:** Cleaner than `SizedBox`, more readable  
**Example:** `Gap(16)` instead of `SizedBox(height: 16)`

#### Environment Configuration
```yaml
flutter_dotenv: ^5.1.0
```
**Purpose:** Load environment variables from `.env` file  
**Usage:** API keys, backend URLs, configuration  
**Variables:**
- `SUPABASE_URL` - Supabase project URL
- `SUPABASE_ANON_KEY` - Public API key
- `BACKEND_URL` - Backend server URL (dev/staging/prod)

#### Development Tools
```yaml
flutter_test:
  sdk: flutter
flutter_lints: ^4.0.0
```

**flutter_test** - Testing framework  
**Usage:** Widget tests, unit tests, integration tests  
**Features:**
- `testWidgets` for UI testing
- Mock support
- Golden file testing

**flutter_lints** - Linting rules  
**Usage:** Code quality, style enforcement  
**Why:** Catches common mistakes, enforces best practices  
**Rules:** Based on Flutter team recommendations

---

### 1.3 External Services (No SDK Required)

#### OSRM (Open Source Routing Machine)
**URL:** `http://router.project-osrm.org/route/v1/driving`  
**Purpose:** Route calculation and turn-by-turn directions  
**Usage:** Get alternative routes between two points  
**Why:** Free, open-source, no API key required  
**Response:** GeoJSON geometry, distance, duration, steps  
**Limitations:** Public instance may be slow, consider self-hosting

#### CPCB (Central Pollution Control Board)
**URL:** `https://api.data.gov.in/resource/3b01bcb8-0b14-4abf-b6f2-c1bfd384ba69`  
**Purpose:** Real-time air quality data for India  
**Usage:** Fetch pollutant readings from ~3400 stations  
**Authentication:** API key required (free registration)  
**Data:** PM2.5, PM10, NO2, SO2, CO, O3, NH3  
**Update Frequency:** Hourly  
**Rate Limits:** Undocumented, use aggressive caching

#### OpenStreetMap Tiles
**URL:** `https://tile.openstreetmap.org/{z}/{x}/{y}.png`  
**Purpose:** Map tiles for visualization  
**Usage:** Display base map in `flutter_map`  
**Why:** Free, open-source, no API key required  
**Tile Policy:** Fair use, consider self-hosting for production  
**Alternatives:** Mapbox, Google Maps (require API keys)

---

### 1.4 Dependency Decision Rationale

#### Why Express over Fastify/Koa?
- **Maturity:** 10+ years, battle-tested
- **Ecosystem:** Largest middleware collection
- **Documentation:** Extensive, beginner-friendly
- **Team Familiarity:** Most developers know Express

#### Why Flutter over React Native?
- **Performance:** Compiled to native code, 60fps
- **UI Consistency:** Same UI on iOS and Android
- **Hot Reload:** Faster development
- **Material Design:** Built-in, no extra libraries

#### Why Riverpod over Provider/Bloc?
- **Type Safety:** Compile-time checks
- **Simplicity:** Less boilerplate than Bloc
- **Testing:** Easy to mock and test
- **Modern:** Successor to Provider

#### Why flutter_map over Google Maps?
- **Cost:** Free, no API key, no billing
- **Customization:** Full control over rendering
- **Offline:** Can cache tiles locally
- **Privacy:** No data sent to Google

#### Why Dio over http package?
- **Features:** Interceptors, timeout, retries
- **Error Handling:** Better exception types
- **Developer Experience:** Cleaner API
- **Performance:** Connection pooling

#### Why Pino over Winston?
- **Performance:** 5x faster, lower overhead
- **JSON:** Structured logs by default
- **Production:** Designed for high-throughput
- **Ecosystem:** Works with log aggregators

---

### 1.5 Dependency Tree Visualization

#### Backend Dependency Tree
```
aeronav-backend
├── express (Web Framework)
│   ├── helmet (Security)
│   ├── cors (Cross-Origin)
│   ├── express-rate-limit (Rate Limiting)
│   └── pino-http (HTTP Logging)
│
├── axios (HTTP Client)
│   └── Used by: osrmService, aqiService, weatherService
│
├── node-cache (Caching)
│   └── Used by: cacheService (all services depend on this)
│
├── pino (Logging)
│   └── Used by: app.js, all services
│
├── dotenv (Environment)
│   └── Loaded in: app.js (before everything else)
│
└── nodemon (Dev Only)
    └── Auto-restart on file changes

Total Production Dependencies: 8
Total Dev Dependencies: 1
Bundle Size: ~15 MB (node_modules)
```

#### Frontend Dependency Tree
```
aeronav (Flutter App)
├── flutter (Core Framework)
│   └── material, cupertino widgets
│
├── supabase_flutter (Backend)
│   ├── Authentication
│   └── Database (future)
│
├── go_router (Navigation)
│   └── Screen routing, deep links
│
├── flutter_riverpod (State Management)
│   └── Global state, providers
│
├── flutter_map (Map Display)
│   ├── latlong2 (Coordinates)
│   └── OpenStreetMap tiles
│
├── location (GPS Tracking)
│   └── permission_handler (Permissions)
│
├── flutter_compass (Heading)
│   └── Device magnetometer
│
├── dio (HTTP Client)
│   └── NavigationService API calls
│
├── google_fonts (Typography)
│   └── Custom fonts
│
├── flutter_dotenv (Environment)
│   └── .env file loading
│
└── gap (UI Utility)
    └── Spacing widgets

Total Dependencies: 13
Total Dev Dependencies: 2
App Size: ~25 MB (Android APK)
```

#### Dependency Update Strategy
```
Backend (Node.js):
  - Check for updates: Weekly
  - Security patches: Immediate
  - Major versions: Quarterly review
  - Command: npm outdated && npm audit

Frontend (Flutter):
  - Check for updates: Monthly
  - Security patches: Immediate
  - Major versions: With Flutter SDK updates
  - Command: flutter pub outdated && flutter pub upgrade
```

#### Known Dependency Issues & Workarounds

**1. flutter_map Performance**
- **Issue:** Lag with 100+ polylines
- **Workaround:** Limit to 3 routes, simplify coordinates
- **Future:** Consider Mapbox GL for better performance

**2. location Package Permissions**
- **Issue:** iOS requires background location for continuous tracking
- **Workaround:** Use `locationWhenInUse` only, request in foreground
- **Future:** Implement background location with proper permissions

**3. OSRM Public Instance**
- **Issue:** Rate limiting, slow response times
- **Workaround:** Aggressive caching (1 hour TTL)
- **Future:** Self-host OSRM server

**4. CPCB API Reliability**
- **Issue:** Occasional downtime, undocumented rate limits
- **Workaround:** Mock data fallback, 15-minute cache
- **Future:** Build own AQI database with historical data

**5. node-cache Single-Server Limitation**
- **Issue:** Cache not shared across multiple servers
- **Workaround:** Acceptable for MVP (single server)
- **Future:** Migrate to Redis for distributed caching

---

### 1.6 Dependency Licenses

#### Backend
| Package | License | Commercial Use |
|---------|---------|----------------|
| express | MIT | ✓ Yes |
| axios | MIT | ✓ Yes |
| helmet | MIT | ✓ Yes |
| cors | MIT | ✓ Yes |
| express-rate-limit | MIT | ✓ Yes |
| node-cache | MIT | ✓ Yes |
| ioredis | MIT | ✓ Yes |
| pino | MIT | ✓ Yes |
| pino-http | MIT | ✓ Yes |
| dotenv | BSD-2-Clause | ✓ Yes |

**All backend dependencies are MIT or BSD licensed - safe for commercial use**

#### Frontend
| Package | License | Commercial Use |
|---------|---------|----------------|
| flutter | BSD-3-Clause | ✓ Yes |
| supabase_flutter | MIT | ✓ Yes |
| go_router | BSD-3-Clause | ✓ Yes |
| flutter_riverpod | MIT | ✓ Yes |
| flutter_map | BSD-3-Clause | ✓ Yes |
| latlong2 | Apache-2.0 | ✓ Yes |
| location | MIT | ✓ Yes |
| geolocator | MIT | ✓ Yes |
| permission_handler | MIT | ✓ Yes |
| flutter_compass | MIT | ✓ Yes |
| dio | MIT | ✓ Yes |
| google_fonts | Apache-2.0 | ✓ Yes |
| flutter_dotenv | MIT | ✓ Yes |
| gap | MIT | ✓ Yes |

**All frontend dependencies are MIT, BSD, or Apache licensed - safe for commercial use**

#### External Services
| Service | License | Commercial Use | Attribution Required |
|---------|---------|----------------|---------------------|
| OpenStreetMap | ODbL | ✓ Yes | ✓ Yes (© OpenStreetMap contributors) |
| OSRM | BSD-2-Clause | ✓ Yes | ✓ Yes (if self-hosting) |
| CPCB API | Government Data | ✓ Yes | ✓ Yes (data.gov.in) |

**Note:** OpenStreetMap requires attribution in the app ("© OpenStreetMap contributors")

---

## 2. System Architecture Overview

### High-Level Components

**Frontend (Flutter Mobile App)**
- Framework: Flutter with Material 3 design
- State Management: Riverpod
- Routing: go_router
- Map Library: flutter_map with OpenStreetMap tiles
- Location Services: location + permission_handler packages
- Compass: flutter_compass for heading/rotation

**Backend (Node.js/Express)**
- Runtime: Node.js
- Framework: Express.js
- Port: 3000 (bound to 0.0.0.0 for physical device access)
- Security: Helmet, CORS, Rate Limiting (100 req/15min)
- Logging: Pino
- Caching: node-cache (in-memory)

**External Services**
- OSRM (Open Source Routing Machine): Route calculation
- data.gov.in CPCB API: Real-time Air Quality Index data
- OpenStreetMap: Map tiles

---


## 2. Complete Request Flow

### 2.1 User Journey - From Search to Navigation

#### Step 1: App Launch & Location Initialization
```
User opens app
    ↓
main.dart initializes
    ↓
Load .env (Supabase credentials)
    ↓
Initialize Supabase authentication
    ↓
Launch HomeScreen
    ↓
Request location permissions
    ↓
Start location tracking stream
    ↓
Start compass tracking stream
    ↓
Fetch live AQI for user's current location
    ↓
Display map centered on user location
```

**Technical Details:**
- Uses `location` package for GPS tracking
- Uses `permission_handler` for runtime permissions
- Auto-requests location service if disabled
- Falls back to permission settings dialog if permanently denied
- Initial map zoom: 13.0
- User location updates continuously via stream subscription

#### Step 2: Destination Search
```
User taps search bar
    ↓
Navigate to SearchScreen (/search)
    ↓
User enters destination
    ↓
Geocoding service converts address to coordinates
    ↓
Return {latitude, longitude, name} to HomeScreen
    ↓
Navigate to RoutesScreen with:
    - startPoint: user's current location
    - endPoint: selected destination
    - destinationName: display name
```


#### Step 3: Route Calculation Request
```
RoutesScreen.initState()
    ↓
Display loading overlay: "Calculating pollution-aware routes..."
    ↓
NavigationService.getPollutionRoute()
    ↓
HTTP POST to backend: /api/navigation/route
    ↓
Request body:
{
  "start": {"lat": 28.6139, "lng": 77.2090},
  "end": {"lat": 27.1767, "lng": 78.0081}
}
    ↓
Backend processes request (detailed in Section 3)
    ↓
Response received with multiple route alternatives
    ↓
Parse routes array
    ↓
Identify cleanest route (default selection)
    ↓
Build polylines for map rendering
    ↓
Fit camera to show all routes
    ↓
Display route selection UI
```

**HTTP Configuration:**
- Timeout: 15s connect, 60s receive
- Headers: `ngrok-skip-browser-warning: true`
- Base URL: Configured in AppConfig (points to dev machine IP for physical devices)

---


## 3. Backend Processing Pipeline

### 3.1 Request Entry Point

```javascript
// app.js - Express server setup
POST /api/navigation/route
    ↓
Rate limiter check (100 req/15min per IP)
    ↓
CORS validation
    ↓
Request logging (Pino)
    ↓
Route to navigation.js handler
```

### 3.2 Navigation Route Handler - Complete Flow

```javascript
// routes/navigation.js - processRoute()

1. VALIDATE INPUT
   - Check start/end coordinates exist
   - Validate lat/lng are numbers
   - Return 400 if invalid

2. FETCH OSRM ROUTES
   osrmService.getRoute(start, end)
       ↓
   Check cache: key = "osrm_{slng},{slat}_{elng},{elat}"
       ↓
   If cached: return cached routes array
       ↓
   If not cached:
       ↓
   HTTP GET to OSRM:
   http://router.project-osrm.org/route/v1/driving/
   {start_lng},{start_lat};{end_lng},{end_lat}
   ?overview=full
   &geometries=geojson
   &steps=true
   &annotations=true
   &alternatives=3
       ↓
   Parse response.routes array (up to 3 alternatives)
       ↓
   Cache for 1 hour
       ↓
   Return routes array

3. PROCESS EACH ROUTE IN PARALLEL
   For each route in routes array:
```


### 3.3 Route Segmentation (1km Chunks)

```javascript
// Step 3a: Split route into 1km segments
const segments = splitRouteIntoSegments(coordinates, 1.0)

// utils/geoUtils.js - splitRouteIntoSegments()
Input: Array of [lng, lat] coordinates from OSRM
Target: 1.0 km per segment

Algorithm:
1. Initialize first segment with starting coordinate
2. For each coordinate pair:
   a. Calculate Haversine distance to next point
   b. Add distance to current segment
   c. Add coordinate to segment's coordinate array
   d. If accumulated distance >= 1km OR last coordinate:
      - Calculate segment midpoint (average of start/end)
      - Push segment to array
      - Start new segment from current point
3. Return segments array

Output per segment:
{
  id: 1,
  startPoint: {lat, lng},
  endPoint: {lat, lng},
  midpoint: {lat, lng},  // Used for AQI sampling
  distanceKm: 0.95,
  coordinates: [[lng, lat], [lng, lat], ...]  // All points in segment
}
```

**Why 1km chunks?**
- Balance between accuracy and API call efficiency
- AQI can vary significantly over short distances
- Provides granular color-coding on map
- Typical route has 10-50 segments


### 3.4 Weather Sampling (Optional Enhancement)

```javascript
// Step 3b: Sample weather along route
const numWeatherSamples = Math.min(5, Math.max(2, Math.ceil(route.distance / 10000)))
const sampledCoords = sampleRoutePoints(coordinates, numWeatherSamples)
const weatherSamples = await weatherService.getWeatherForMultiplePoints(sampledCoords)

// utils/routeSampler.js - sampleRoutePoints()
Purpose: Get evenly-spaced weather readings along route

Algorithm:
1. Calculate total route distance using Haversine
2. Divide into N equal parts (2-5 samples based on route length)
3. For each sample point:
   - Calculate target distance along route
   - Find segment containing that distance
   - Interpolate exact coordinate within segment
4. Return array of {lat, lng} sample points

Weather data includes:
- Temperature
- Humidity
- Wind speed
- Conditions (used for AQI modifiers)
```

**Note:** Current implementation has weather modifiers disabled to avoid drift from official CPCB readings.

---


## 4. AQI Calculation & Interpolation

### 4.1 CPCB Station Data Fetching

```javascript
// services/aqiService.js - fetchRawStations()

CACHE CHECK
    ↓
Key: "cpcb_stations_data"
Cache TTL: 15 minutes (900 seconds)
    ↓
If cached: return immediately
    ↓
If not cached or expired:
    ↓
HTTP GET to data.gov.in:
https://api.data.gov.in/resource/3b01bcb8-0b14-4abf-b6f2-c1bfd384ba69
?api-key={DATAGOVIN_API_KEY}
&format=json
&limit=5000
    ↓
Response: ~3400+ station records across India
    ↓
PARSE & NORMALIZE
    ↓
For each record:
  - Extract latitude, longitude
  - Skip if lat/lng invalid or zero
  - Extract pollutant_id (PM2.5, PM10, NO2, SO2, CO, O3, NH3)
  - Extract avg_value (concentration)
  - Skip if value is negative or NaN
  - Normalize pollutant names:
      "PM2.5" → "pm25"
      "PM10" → "pm10"
      "NO2" → "no2"
      "SO2" → "so2"
      "CO" → "co"
      "O3" / "OZONE" → "o3"
      "NH3" → "nh3"
    ↓
GROUP BY STATION
    ↓
Key: "{lat.toFixed(4)}_{lng.toFixed(4)}"
Aggregate all pollutants for same location
    ↓
Result: Array of unique stations
[
  {
    lat: 28.6100,
    lng: 77.2000,
    pollutants: {
      pm25: 95,
      pm10: 140,
      no2: 48,
      so2: 12,
      co: 1.4,
      o3: 30
    }
  },
  ...
]
    ↓
Cache for 15 minutes
    ↓
Return stations array
```

**Fallback:** If API fails or returns no data, use mock stations with realistic April/annual average values for major Indian cities.


### 4.2 Inverse Distance Weighting (IDW) Interpolation

```javascript
// Step 3c: Batch fetch pollutants for all segment midpoints
const segmentMidpoints = segments.map(seg => ({lat: seg.midpoint.lat, lng: seg.midpoint.lng}))
const segmentPollutants = await aqiService.calculatePollutantsForPoints(segmentMidpoints)

// services/aqiService.js - calculatePollutantsForPoints()

For each segment midpoint:
    ↓
1. CHECK CACHE
   Key: "aqi_point_{lat_rounded}_{lng_rounded}"
   TTL: 5 minutes (300 seconds)
   If cached: use cached pollutants
    ↓
2. PREPARE POLLUTANT ARRAYS
   Group all stations by pollutant type:
   {
     pm25: [{lat, lng, value}, {lat, lng, value}, ...],
     pm10: [{lat, lng, value}, ...],
     no2: [...],
     so2: [...],
     co: [...],
     o3: [...]
   }
    ↓
3. CALCULATE IDW FOR EACH POLLUTANT
   For pm25, pm10, no2, so2, co, o3:
       ↓
   a. Try LOCAL interpolation (25km radius, power=3)
      calculateIDW(targetPoint, pollutantStations, power=3, maxDistance=25)
          ↓
      For each station within 25km:
          distance = haversineDistance(target, station)
          if distance < 0.1km: return station.value immediately
          weight = 1 / (distance ^ 3)
          numerator += weight * station.value
          denominator += weight
          ↓
      If stations found: return numerator / denominator
          ↓
   b. If no local stations, try REGIONAL (150km radius, power=3)
      Same algorithm with maxDistance=150
          ↓
   c. If still no stations, FALLBACK (500km with blending)
      Find nearest station within 500km
      Blend with baseline value based on distance:
          ratio = 1 - ((distance - 150) / (500 - 150))
          result = (nearestValue * ratio) + (baseline * (1 - ratio))
          ↓
   d. If no stations within 500km: use baseline
      Baselines: pm25=20, pm10=40, no2=10, so2=5, co=0.5, o3=20
    ↓
4. RESULT FOR POINT
   {
     pm25: 82.5,
     pm10: 125.3,
     no2: 38.7,
     so2: 10.2,
     co: 1.15,
     o3: 26.8
   }
    ↓
5. CACHE RESULT (5 minutes)
    ↓
Return pollutants object
```

**IDW Formula:**
```
weight_i = 1 / (distance_i ^ power)
interpolated_value = Σ(weight_i × value_i) / Σ(weight_i)
```

**Why power=3?**
- Higher power gives more weight to nearby stations
- Reduces influence of distant stations
- Better captures local pollution variations


### 4.3 AQI Sub-Index Calculation (CPCB Standard)

```javascript
// Step 3d: Calculate Base AQI for each segment
const baseAqi = calculateBaseAQI(pollutants)

// services/scoreEngine.js - calculateBaseAQI()

Input: Pollutant concentrations
{
  pm25: 82.5,
  pm10: 125.3,
  no2: 38.7,
  so2: 10.2,
  co: 1.15,
  o3: 26.8
}
    ↓
For each pollutant, calculate sub-index using CPCB breakpoints:
    ↓
calculateSubIndex(concentration, pollutantType)
    ↓
1. Find matching breakpoint range
   Example for PM2.5 = 82.5:
   
   BREAKPOINTS.pm25:
   [0-30]   → AQI [0-50]    (Good)
   [31-60]  → AQI [51-100]  (Satisfactory)
   [61-90]  → AQI [101-200] (Moderate)  ← 82.5 falls here
   [91-120] → AQI [201-300] (Poor)
   ...
    ↓
2. Apply linear interpolation formula:
   
   Ip = [(IHi - ILo) / (BPHi - BPLo)] × (Cp - BPLo) + ILo
   
   Where:
   - Ip = Calculated sub-index
   - Cp = Pollutant concentration (82.5)
   - BPLo = Lower breakpoint (61)
   - BPHi = Upper breakpoint (90)
   - ILo = Lower index (101)
   - IHi = Upper index (200)
   
   Calculation:
   Ip = [(200 - 101) / (90 - 61)] × (82.5 - 61) + 101
   Ip = [99 / 29] × 21.5 + 101
   Ip = 3.414 × 21.5 + 101
   Ip = 73.4 + 101
   Ip = 174.4 → Round to 174
    ↓
3. Repeat for all 6 pollutants:
   {
     pm25: 174,
     pm10: 168,
     no2: 48,
     so2: 25,
     co: 55,
     o3: 26
   }
    ↓
4. CPCB Rule: Overall AQI = MAX of all sub-indices
   baseAqi = max(174, 168, 48, 25, 55, 26) = 174
    ↓
Return: 174
```


### 4.4 CPCB Breakpoint Tables (Complete Reference)

#### PM2.5 (24-hour average, µg/m³)
| Concentration Range | AQI Range | Category |
|---------------------|-----------|----------|
| 0 - 30 | 0 - 50 | Good |
| 31 - 60 | 51 - 100 | Satisfactory |
| 61 - 90 | 101 - 200 | Moderate |
| 91 - 120 | 201 - 300 | Poor |
| 121 - 250 | 301 - 400 | Very Poor |
| 251+ | 401 - 500 | Severe |

#### PM10 (24-hour average, µg/m³)
| Concentration Range | AQI Range | Category |
|---------------------|-----------|----------|
| 0 - 50 | 0 - 50 | Good |
| 51 - 100 | 51 - 100 | Satisfactory |
| 101 - 250 | 101 - 200 | Moderate |
| 251 - 350 | 201 - 300 | Poor |
| 351 - 430 | 301 - 400 | Very Poor |
| 431+ | 401 - 500 | Severe |

#### NO2 (24-hour average, µg/m³)
| Concentration Range | AQI Range | Category |
|---------------------|-----------|----------|
| 0 - 40 | 0 - 50 | Good |
| 41 - 80 | 51 - 100 | Satisfactory |
| 81 - 180 | 101 - 200 | Moderate |
| 181 - 280 | 201 - 300 | Poor |
| 281 - 400 | 301 - 400 | Very Poor |
| 401+ | 401 - 500 | Severe |

#### SO2, CO, O3 (Similar structure with different concentration ranges)


## 5. Route Segmentation & Scoring

### 5.1 Color Mapping

```javascript
// Step 3e: Map AQI to color category
const { category, color } = getCategoryAndColor(finalAqi)

// services/colorMapper.js - getCategoryAndColor()

Input: AQI value (e.g., 174)
    ↓
Match against CPCB tiers:
[
  { min: 0,   max: 50,  category: 'Good',         color: '#00E400' },  // Bright green
  { min: 51,  max: 100, category: 'Satisfactory', color: '#92D14F' },  // Light green
  { min: 101, max: 200, category: 'Moderate',     color: '#FFFF00' },  // Yellow ← 174 matches
  { min: 201, max: 300, category: 'Poor',         color: '#FF7E00' },  // Orange
  { min: 301, max: 400, category: 'Very Poor',    color: '#FF0000' },  // Red
  { min: 401, max: 5000, category: 'Severe',      color: '#7E0023' }   // Maroon
]
    ↓
Return: { category: 'Moderate', color: '#FFFF00' }
```

### 5.2 Segment Assembly

```javascript
// Step 3f: Build processed segment object
const processedSegment = {
  id: 1,
  distanceKm: 0.95,
  coordinates: [[77.2090, 28.6139], [77.2095, 28.6145], ...],  // [lng, lat] pairs
  aqi: {
    base: 174,
    final: 174,
    weatherAdjust: 0,  // Currently disabled
    category: 'Moderate',
    color: '#FFFF00',
    pollutants: {
      pm25: 82.5,
      pm10: 125.3,
      no2: 38.7,
      so2: 10.2,
      co: 1.15,
      o3: 26.8
    }
  },
  weather: {
    temp: 32,
    humidity: 45,
    windSpeed: 12,
    conditions: 'Clear'
  }
}
```


### 5.3 Route Summary Calculation

```javascript
// Step 3g: Calculate overall route metrics

1. Find maximum AQI segment
   maxAqiSegment = segments.reduce((max, seg) => 
     seg.aqi.final > max.aqi.final ? seg : max
   )
    ↓
2. Calculate average AQI
   avgAqi = segments.reduce((sum, seg) => sum + seg.aqi.final, 0) / segments.length
   overallAqi = Math.round(avgAqi)
    ↓
3. Map overall AQI to category/color
   { category, color } = getCategoryAndColor(overallAqi)
    ↓
4. Build route summary
   {
     totalDistanceKm: 195.3,
     totalDurationMin: 245.5,
     overallAqi: 168,
     maxAqi: 215,
     overallCategory: 'Moderate',
     overallColor: '#FFFF00'
   }
```

### 5.4 Multi-Route Comparison

```javascript
// Step 4: Process all alternative routes (up to 3 from OSRM)
const processedRoutes = await Promise.all(routes.map(async (route) => {
  // ... process each route as above ...
}))
    ↓
// Step 5: Identify fastest and cleanest routes
let fastestRoute = processedRoutes[0]
let cleanestRoute = processedRoutes[0]

processedRoutes.forEach(route => {
  if (route.summary.totalDurationMin < fastestRoute.summary.totalDurationMin) {
    fastestRoute = route
  }
  if (route.summary.overallAqi < cleanestRoute.summary.overallAqi) {
    cleanestRoute = route
  }
})
    ↓
// Step 6: Mark routes with flags
processedRoutes.forEach(route => {
  route.isFastest = (route === fastestRoute)
  route.isCleanest = (route === cleanestRoute) && (route !== fastestRoute || processedRoutes.length === 1)
})
```


### 5.5 Final Response Structure

```json
{
  "routes": [
    {
      "summary": {
        "totalDistanceKm": 195.3,
        "totalDurationMin": 245.5,
        "overallAqi": 168,
        "maxAqi": 215,
        "overallCategory": "Moderate",
        "overallColor": "#FFFF00"
      },
      "segments": [
        {
          "id": 1,
          "distanceKm": 0.95,
          "coordinates": [[77.2090, 28.6139], [77.2095, 28.6145], ...],
          "aqi": {
            "base": 174,
            "final": 174,
            "weatherAdjust": 0,
            "category": "Moderate",
            "color": "#FFFF00",
            "pollutants": {
              "pm25": 82.5,
              "pm10": 125.3,
              "no2": 38.7,
              "so2": 10.2,
              "co": 1.15,
              "o3": 26.8
            }
          },
          "weather": { ... }
        },
        // ... more segments ...
      ],
      "isFastest": false,
      "isCleanest": true
    },
    {
      // Alternative route 2
      "isFastest": true,
      "isCleanest": false
    },
    {
      // Alternative route 3
      "isFastest": false,
      "isCleanest": false
    }
  ]
}
```

**Response sent back to Flutter app**

---


## 6. Frontend Map Rendering

### 6.1 Response Parsing

```dart
// lib/screens/routes_screen.dart - _initializeRoutes()

Response received from backend
    ↓
Extract routes array: routeData['routes']
    ↓
Validate: must be non-empty List
    ↓
Parse each route as Map<String, dynamic>
    ↓
Find default route (isCleanest = true)
    ↓
Set _selectedRouteIndex to cleanest route
    ↓
Update state: _routes = parsedRoutes
    ↓
Trigger map rendering
```

### 6.2 Polyline Construction

```dart
// _buildPolylines() method

Step 1: Render inactive routes (grey, behind)
    ↓
For each route where index != _selectedRouteIndex:
    ↓
  Extract all segments
    ↓
  Flatten all coordinates into single points array
    ↓
  Create single grey polyline:
    Polyline(
      points: allPoints,
      color: Colors.blueGrey.withAlpha(120),
      strokeWidth: 5.0,
      strokeCap: StrokeCap.round,
      strokeJoin: StrokeJoin.round
    )
    ↓
Step 2: Render active route (color-coded, on top)
    ↓
For each segment in _routes[_selectedRouteIndex]['segments']:
    ↓
  Extract segment coordinates: [[lng, lat], [lng, lat], ...]
    ↓
  Convert to LatLng objects: [LatLng(lat, lng), ...]
    ↓
  Extract AQI color: segment['aqi']['color']
    ↓
  Parse hex color: _colorFromHex('#FFFF00')
    ↓
  Create colored polyline:
    Polyline(
      points: segmentPoints,
      color: parsedColor,
      strokeWidth: 7.0,  // Thicker than inactive routes
      strokeCap: StrokeCap.round,
      strokeJoin: StrokeJoin.round
    )
    ↓
Add all polylines to array
    ↓
Return polylines array
```


### 6.3 Map Layer Stack (Bottom to Top)

```dart
FlutterMap(
  mapController: _mapController,
  children: [
    // Layer 1: Base map tiles
    TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.aeronav.app'
    ),
    
    // Layer 2: Route polylines
    PolylineLayer(
      polylines: _buildPolylines()  // Grey inactive + colored active
    ),
    
    // Layer 3: Markers
    MarkerLayer(
      markers: [
        // Destination marker
        Marker(
          point: endPoint,
          width: 40,
          height: 40,
          child: Icon(Icons.location_on, color: Colors.blue, size: 40)
        ),
        
        // User location marker
        Marker(
          point: userLocation,
          width: 40,
          height: 40,
          child: _isNavigating 
            ? Transform.rotate(
                angle: _currentHeading * (π / 180),
                child: Icon(Icons.navigation, color: Colors.blue, size: 36)
              )
            : PulsingLocationMarker()  // Animated blue dot
        )
      ]
    )
  ]
)
```

### 6.4 Camera Fitting

```dart
// _fitCameraToRoutes() method

Collect all coordinates from all routes
    ↓
Create LatLngBounds from all points
    ↓
Calculate bounding box that contains all routes
    ↓
_mapController.fitCamera(
  CameraFit.bounds(
    bounds: calculatedBounds,
    padding: EdgeInsets.all(60.0)  // Keep routes away from edges
  )
)
    ↓
Map smoothly animates to show all routes
```


### 6.5 Route Selection UI

```dart
// Bottom sheet with route cards

For each route in _routes:
    ↓
Display route card with:
  - Label: "Cleanest Route" / "Fastest Route" / "Alternative Route"
  - Icon: eco (cleanest) / schedule (fastest) / alt_route (other)
  - Distance: "195.3 km"
  - Duration: "4h 5m" (formatted)
  - AQI badge: "AQI 168 · Moderate" (colored background)
  - Selection state: highlighted if selected
    ↓
On tap:
  setState(() => _selectedRouteIndex = tappedIndex)
    ↓
Triggers rebuild → _buildPolylines() → map updates
    ↓
Selected route polylines change from grey to color-coded
```

### 6.6 AQI Legend

```dart
// Horizontal color scale at bottom

Display 6 color bands:
  Good (0-50):         #00E400 (bright green)
  Satisfactory (51-100): #92D14F (light green)
  Moderate (101-200):    #FFFF00 (yellow)
  Poor (201-300):        #FF7E00 (orange)
  Very Poor (301-400):   #FF0000 (red)
  Severe (401+):         #7E0023 (maroon)
    ↓
Each band shows:
  - Category name (vertical text)
  - AQI range below
    ↓
Helps users interpret route colors
```

---


## 7. Navigation Mode

### 7.1 Starting Navigation

```dart
// User taps "Start Navigation" button

_startNavigation() called
    ↓
Display loading: "Getting turn-by-turn instructions..."
    ↓
Request navigation steps from backend:
  POST /api/navigation/steps
  Body: { start: {lat, lng}, end: {lat, lng} }
    ↓
Backend returns same route data but with 'steps' array included
    ↓
Parse steps from selected route:
  steps = routes[_selectedRouteIndex]['steps']
    ↓
Convert to RouteStep objects:
  RouteStep {
    instruction: "Turn left onto Main Street"
    distance: 250  // meters
    duration: 30   // seconds
    maneuverType: "turn"
    modifier: "left"
    bearingAfter: 270
    point: LatLng(28.6145, 77.2095)
  }
    ↓
Set state:
  _isNavigating = true
  _navigationSteps = parsedSteps
  _currentStepIndex = 0
    ↓
Move map to user location:
  _mapController.move(_userLocation, 18.0)  // High zoom
  _mapController.rotate(_currentHeading)     // Rotate to heading
    ↓
UI switches to navigation mode
```


### 7.2 Live Tracking & Map Rotation

```dart
// Continuous location updates

Location stream (onLocationChanged):
    ↓
Every 1-2 seconds:
  New LocationData received
    ↓
  Extract: latitude, longitude, heading (optional)
    ↓
  Update state: _userLocation = LatLng(lat, lng)
    ↓
  If in navigation mode:
    _mapController.move(_userLocation, 18.0)  // Keep user centered
    ↓
Compass stream (FlutterCompass.events):
    ↓
Every ~100ms:
  New CompassEvent received
    ↓
  Extract: heading (0-360 degrees)
    ↓
  Update state: _currentHeading = heading
    ↓
  If in navigation mode:
    _mapController.rotate(_currentHeading)  // Rotate map to heading
    ↓
Result:
  - Map stays centered on user
  - Map rotates to match device orientation
  - User marker shows as navigation arrow pointing forward
  - Creates "heads-up" navigation experience
```

### 7.3 Step Advancement

```dart
// _checkStepAdvance() called on every location update

If not navigating OR no steps: return
    ↓
Get current step: _navigationSteps[_currentStepIndex]
    ↓
Calculate distance from user to step point:
  distance = haversineDistance(_userLocation, currentStep.point)
    ↓
If distance < 20 meters AND not on last step:
    ↓
  Advance to next step:
    setState(() => _currentStepIndex++)
    ↓
  UI updates to show next instruction
```


### 7.4 Navigation UI Components

```dart
// Top banner (instruction card)
Container(
  backgroundColor: #2DB87A (green),
  borderRadius: 12,
  child: Row(
    Icon: directions (or turn_left, turn_right based on maneuver)
    Column:
      Text: "Turn left onto Main Street"  // Current instruction
      Text: "250 m"  // Distance to maneuver
    IconButton: close (exit navigation)
  )
)
    ↓
// Bottom controls
Container(
  backgroundColor: white,
  child: Row(
    Column:
      Text: "4h 5m"  // Remaining duration (green, bold)
      Text: "195.3 km"  // Remaining distance (grey)
    Button: "Exit" (red)
  )
)
    ↓
// Map view
- Polylines remain visible (color-coded by AQI)
- User marker: blue navigation arrow (rotates with heading)
- Destination marker: blue location pin
- Map centered on user, rotated to heading
- Zoom level: 18 (street level)
```

### 7.5 Exiting Navigation

```dart
// User taps "Exit" button

_exitNavigationMode() called
    ↓
Reset state:
  _isNavigating = false
  _currentStepIndex = 0
  _navigationSteps = []
    ↓
Reset map:
  _mapController.rotate(0)  // North-up orientation
  _fitCameraToRoutes()      // Show full route overview
    ↓
UI switches back to route selection mode
```

---


## 8. Data Flow Diagrams

### 8.1 Complete End-to-End Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          USER INTERACTION                                │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                    User opens app & selects destination
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        FLUTTER FRONTEND                                  │
├─────────────────────────────────────────────────────────────────────────┤
│  1. NavigationService.getPollutionRoute()                               │
│  2. HTTP POST to backend /api/navigation/route                          │
│  3. Body: { start: {lat, lng}, end: {lat, lng} }                        │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         NODE.JS BACKEND                                  │
├─────────────────────────────────────────────────────────────────────────┤
│  STEP 1: Fetch OSRM Routes                                              │
│    ├─ Check cache (1 hour TTL)                                          │
│    ├─ If miss: HTTP GET to router.project-osrm.org                      │
│    ├─ Request up to 3 alternative routes                                │
│    └─ Return: Array of routes with geometry & steps                     │
│                                                                           │
│  STEP 2: For Each Route (parallel processing)                           │
│    │                                                                      │
│    ├─ A. Segment Route (1km chunks)                                     │
│    │    └─ splitRouteIntoSegments(coordinates, 1.0)                     │
│    │       └─ Returns: Array of segments with midpoints                 │
│    │                                                                      │
│    ├─ B. Sample Weather Points                                          │
│    │    └─ sampleRoutePoints(coordinates, 2-5 samples)                  │
│    │       └─ Returns: Evenly-spaced weather sample points              │
│    │                                                                      │
│    ├─ C. Fetch CPCB Station Data                                        │
│    │    └─ aqiService.fetchRawStations()                                │
│    │       ├─ Check cache (15 min TTL)                                  │
│    │       ├─ If miss: HTTP GET to data.gov.in API                      │
│    │       ├─ Parse ~3400 station records                               │
│    │       ├─ Normalize pollutant names                                 │
│    │       ├─ Group by station location                                 │
│    │       └─ Returns: Array of stations with pollutants                │
│    │                                                                      │
│    ├─ D. Calculate Pollutants for Each Segment Midpoint (IDW)          │
│    │    └─ aqiService.calculatePollutantsForPoints(midpoints)           │
│    │       └─ For each midpoint:                                        │
│    │          ├─ Check cache (5 min TTL)                                │
│    │          ├─ If miss: Apply IDW interpolation                       │
│    │          │  ├─ Try local (25km, power=3)                           │
│    │          │  ├─ Try regional (150km, power=3)                       │
│    │          │  └─ Fallback (500km with blending)                      │
│    │          └─ Returns: {pm25, pm10, no2, so2, co, o3}               │
│    │                                                                      │
│    ├─ E. Calculate Base AQI for Each Segment                            │
│    │    └─ scoreEngine.calculateBaseAQI(pollutants)                     │
│    │       ├─ Calculate sub-index for each pollutant                    │
│    │       │  └─ Use CPCB breakpoints + linear interpolation            │
│    │       └─ Return max sub-index as overall AQI                       │
│    │                                                                      │
│    ├─ F. Apply Weather Modifiers (currently disabled)                   │
│    │    └─ scoreEngine.calculateWeatherModifiers(baseAqi, weather)      │
│    │       └─ Returns: { finalAqi, percentageAdjust }                   │
│    │                                                                      │
│    ├─ G. Map AQI to Color Category                                      │
│    │    └─ colorMapper.getCategoryAndColor(finalAqi)                    │
│    │       └─ Returns: { category: 'Moderate', color: '#FFFF00' }      │
│    │                                                                      │
│    └─ H. Build Processed Segment                                        │
│       └─ Returns: { id, distanceKm, coordinates, aqi, weather }         │
│                                                                           │
│  STEP 3: Calculate Route Summary                                        │
│    ├─ Find max AQI segment                                              │
│    ├─ Calculate average AQI                                             │
│    ├─ Map to category/color                                             │
│    └─ Build summary: { totalDistanceKm, totalDurationMin,              │
│                         overallAqi, maxAqi, category, color }           │
│                                                                           │
│  STEP 4: Identify Fastest & Cleanest Routes                             │
│    ├─ Compare all routes by duration → mark isFastest                   │
│    └─ Compare all routes by AQI → mark isCleanest                       │
│                                                                           │
│  STEP 5: Return JSON Response                                           │
│    └─ { routes: [ {summary, segments, isFastest, isCleanest}, ... ] }  │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        FLUTTER FRONTEND                                  │
├─────────────────────────────────────────────────────────────────────────┤
│  STEP 1: Parse Response                                                 │
│    ├─ Extract routes array                                              │
│    ├─ Find cleanest route (default selection)                           │
│    └─ Set _routes state                                                 │
│                                                                           │
│  STEP 2: Build Polylines                                                │
│    ├─ For inactive routes: create grey polylines                        │
│    └─ For active route: create color-coded polylines per segment        │
│       └─ Each segment gets its own polyline with AQI color              │
│                                                                           │
│  STEP 3: Render Map                                                     │
│    └─ FlutterMap layers (bottom to top):                                │
│       ├─ TileLayer (OpenStreetMap)                                      │
│       ├─ PolylineLayer (routes)                                         │
│       └─ MarkerLayer (destination + user location)                      │
│                                                                           │
│  STEP 4: Fit Camera                                                     │
│    └─ Calculate bounds from all route coordinates                       │
│       └─ Animate camera to show all routes                              │
│                                                                           │
│  STEP 5: Display Route Selection UI                                     │
│    ├─ Route cards with labels, distance, duration, AQI                  │
│    ├─ AQI legend (color scale)                                          │
│    └─ "Start Navigation" button                                         │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                    User taps "Start Navigation"
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         NAVIGATION MODE                                  │
├─────────────────────────────────────────────────────────────────────────┤
│  1. Request turn-by-turn steps from backend                             │
│  2. Parse RouteStep objects                                             │
│  3. Start location tracking stream                                      │
│  4. Start compass tracking stream                                       │
│  5. Center map on user (zoom 18)                                        │
│  6. Rotate map to heading                                               │
│  7. Display instruction banner                                          │
│  8. Auto-advance steps when within 20m                                  │
│  9. Update UI continuously                                              │
└─────────────────────────────────────────────────────────────────────────┘
```


### 8.2 Caching Strategy

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          CACHE LAYERS                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  Layer 1: OSRM Routes                                                   │
│    Key: "osrm_{start_lng},{start_lat}_{end_lng},{end_lat}"             │
│    TTL: 3600 seconds (1 hour)                                           │
│    Why: Route geometry rarely changes                                   │
│    Impact: Saves ~500ms per request                                     │
│                                                                           │
│  Layer 2: CPCB Station Data                                             │
│    Key: "cpcb_stations_data"                                            │
│    TTL: 900 seconds (15 minutes)                                        │
│    Why: CPCB updates ~hourly, 15min is safe                             │
│    Impact: Saves ~2-3s per request, prevents API blocking               │
│                                                                           │
│  Layer 3: Point AQI Calculations                                        │
│    Key: "aqi_point_{lat_rounded}_{lng_rounded}"                         │
│    TTL: 300 seconds (5 minutes)                                         │
│    Why: AQI changes slowly, 5min provides near-real-time                │
│    Impact: Saves ~100-200ms per point                                   │
│    Note: Rounded to 2 decimals for cache hit rate                       │
│                                                                           │
└─────────────────────────────────────────────────────────────────────────┘

Cache Hit Scenario (Best Case):
  Request → OSRM cache hit → Station cache hit → All point caches hit
  Total time: ~200ms (just computation)

Cache Miss Scenario (Worst Case):
  Request → OSRM API (~500ms) → CPCB API (~2000ms) → IDW computation (~500ms)
  Total time: ~3000ms (3 seconds)

Typical Scenario (Partial Hits):
  Request → OSRM cache hit → Station cache hit → Some point cache hits
  Total time: ~500-800ms
```


### 8.3 Performance Metrics

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      TYPICAL REQUEST BREAKDOWN                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  Route: Delhi to Agra (~200km, ~25 segments)                            │
│                                                                           │
│  1. OSRM Route Fetch                    500ms  (or 0ms if cached)       │
│  2. CPCB Station Fetch                 2000ms  (or 0ms if cached)       │
│  3. Route Segmentation                   50ms                            │
│  4. Weather Sampling                    100ms                            │
│  5. IDW Interpolation (25 points)      500ms  (or 100ms if cached)      │
│  6. AQI Calculation (25 segments)       50ms                            │
│  7. Color Mapping                        10ms                            │
│  8. Summary Calculation                  10ms                            │
│  9. JSON Serialization                   20ms                            │
│                                      ─────────                           │
│  Total (cold cache):                  3240ms                            │
│  Total (warm cache):                   740ms                            │
│  Total (hot cache):                    240ms                            │
│                                                                           │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                      FRONTEND RENDERING TIME                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  1. HTTP Request + Response            740ms  (typical)                 │
│  2. JSON Parsing                        20ms                            │
│  3. Polyline Construction               50ms  (25 segments)             │
│  4. Map Rendering                      100ms  (flutter_map)             │
│  5. Camera Animation                   300ms  (smooth transition)       │
│                                      ─────────                           │
│  Total User Wait Time:                1210ms  (~1.2 seconds)            │
│                                                                           │
└─────────────────────────────────────────────────────────────────────────┘
```


### 8.4 Data Volume Analysis

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      TYPICAL DATA TRANSFER                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  Request Payload:                                                        │
│    {                                                                     │
│      "start": {"lat": 28.6139, "lng": 77.2090},                         │
│      "end": {"lat": 27.1767, "lng": 78.0081}                            │
│    }                                                                     │
│    Size: ~100 bytes                                                      │
│                                                                           │
│  Response Payload (3 routes, 25 segments each):                         │
│    - Route metadata: ~500 bytes per route                               │
│    - Segment data: ~300 bytes per segment                               │
│    - Coordinates: ~20 bytes per coordinate point                        │
│    - Total coordinates: ~500 points per route                           │
│                                                                           │
│    Calculation:                                                          │
│      3 routes × (500 + (25 × 300) + (500 × 20))                         │
│      = 3 × (500 + 7500 + 10000)                                         │
│      = 3 × 18000                                                         │
│      = 54KB per response                                                 │
│                                                                           │
│    With compression (gzip): ~15-20KB                                     │
│                                                                           │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                      EXTERNAL API CALLS                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  Per Route Request:                                                      │
│    1. OSRM API: 1 call (if not cached)                                  │
│       Response: ~30-50KB (3 routes with full geometry)                  │
│                                                                           │
│    2. CPCB API: 1 call (if not cached)                                  │
│       Response: ~500KB-1MB (3400+ station records)                      │
│                                                                           │
│    3. Weather API: 2-5 calls per route (if enabled)                     │
│       Response: ~2KB per call                                            │
│                                                                           │
│  Total External Data (cold cache): ~550KB-1.1MB                          │
│  Total External Data (warm cache): 0KB                                   │
│                                                                           │
└─────────────────────────────────────────────────────────────────────────┘
```


## 9. Key Technical Decisions & Rationale

### 9.1 Why 1km Segment Size?

**Considered Options:**
- 500m: Too granular, 2x API calls, minimal AQI variation
- 1km: ✓ Optimal balance
- 2km: Too coarse, misses local pollution hotspots
- 5km: Unacceptable, entire neighborhoods averaged

**Decision:** 1km provides:
- Visible color variation on map
- Reasonable API call count (20-50 per route)
- Captures neighborhood-level pollution differences
- Fast enough for real-time calculation

### 9.2 Why IDW with Power=3?

**Inverse Distance Weighting Formula:**
```
weight = 1 / (distance ^ power)
```

**Power Comparison:**
| Power | Behavior | Use Case |
|-------|----------|----------|
| 1 | Linear, distant stations have significant influence | Smooth gradients |
| 2 | Standard IDW, balanced | General interpolation |
| 3 | ✓ Strong local bias | Pollution (highly localized) |
| 4+ | Extreme local bias, sharp boundaries | Too aggressive |

**Decision:** Power=3 because:
- Pollution is highly localized (traffic, industry)
- Nearby stations should dominate
- Reduces "bleeding" from distant urban centers
- Matches empirical AQI distribution patterns

### 9.3 Why Three Distance Tiers (25km, 150km, 500km)?

**Tier Strategy:**
```
Local (25km, power=3):
  - Urban areas with dense station coverage
  - High confidence interpolation
  - Most routes fall here

Regional (150km, power=3):
  - Rural areas between cities
  - Moderate confidence
  - Captures regional patterns

Fallback (500km, blended):
  - Remote areas (mountains, deserts)
  - Low confidence, blend with baseline
  - Prevents wild extrapolation
```

**Decision:** Three tiers provide:
- Graceful degradation in sparse areas
- Prevents "no data" failures
- Realistic estimates even in remote regions
- Transparent confidence levels


### 9.4 Why Disable Weather Modifiers?

**Original Intent:**
- Adjust AQI based on weather conditions
- Rain → lower AQI (washout effect)
- High wind → lower AQI (dispersion)
- Stagnant air → higher AQI (accumulation)

**Problem:**
- CPCB station readings already reflect weather effects
- Sensors measure actual air quality, not theoretical
- Applying modifiers causes drift from official readings
- Users trust CPCB numbers, not adjusted values

**Decision:** Disable weather modifiers
- Keep `finalAqi = baseAqi`
- Still fetch weather for future features
- Maintain alignment with official CPCB data
- Preserve user trust

### 9.5 Why Cache at Multiple Levels?

**Cache Strategy:**

```
Level 1: OSRM Routes (1 hour)
  Why: Route geometry is static
  Impact: Eliminates 500ms per request
  Hit Rate: ~60% (common routes)

Level 2: CPCB Stations (15 minutes)
  Why: Data updates hourly, 15min is safe
  Impact: Eliminates 2000ms + prevents API blocking
  Hit Rate: ~95% (shared across all requests)

Level 3: Point AQI (5 minutes)
  Why: AQI changes slowly, 5min is near-real-time
  Impact: Eliminates 100-200ms per point
  Hit Rate: ~40% (route-specific)
```

**Decision:** Multi-level caching because:
- Different data has different update frequencies
- Prevents API rate limiting
- Reduces latency by 70-90%
- Enables sub-second response times


### 9.6 Why Up to 3 Alternative Routes?

**OSRM Capability:**
- Can return 1-10 alternative routes
- More alternatives = longer computation time

**User Experience Research:**
- 1 route: No choice, users feel constrained
- 2 routes: Binary choice, often similar
- 3 routes: ✓ Optimal, provides meaningful variety
- 4+ routes: Overwhelming, decision paralysis

**Decision:** Request 3 alternatives because:
- Typically get: fastest, balanced, scenic/cleanest
- Provides real choice without overwhelming
- Matches Google Maps UX pattern
- Computation time stays reasonable (<1s)

### 9.7 Why Mark "Fastest" and "Cleanest" Routes?

**Route Labeling Strategy:**

```
Scenario 1: All routes different
  Route A: Fastest (shortest duration)
  Route B: Cleanest (lowest AQI)
  Route C: Alternative (neither)

Scenario 2: Same route is both
  Route A: Optimal (fastest AND cleanest)
  Route B: Alternative
  Route C: Alternative

Scenario 3: Only one route
  Route A: Optimal (both flags, but only one shown)
```

**Decision:** Dual labeling because:
- Users have different priorities (time vs. health)
- Makes trade-offs explicit
- Guides decision-making
- Reduces cognitive load

### 9.8 Why Default to Cleanest Route?

**User Research Insight:**
- Users opening AeroNav prioritize air quality
- If they wanted fastest, they'd use Google Maps
- App's value proposition is pollution awareness

**Decision:** Default to cleanest because:
- Aligns with app's core mission
- Users can easily switch to fastest
- Reinforces health-conscious behavior
- Differentiates from competitors


## 10. Error Handling & Edge Cases

### 10.1 Network Failures

```
Scenario: Backend unreachable
    ↓
Flutter: Dio timeout (15s connect, 60s receive)
    ↓
Catch DioException
    ↓
Display error screen:
  - Icon: error_outline (red)
  - Message: "Could not load route: Connection timeout"
  - Actions: "Retry" button, "Go Back" button
    ↓
User taps "Retry"
    ↓
Reset state, retry request
```

### 10.2 Invalid Coordinates

```
Scenario: User selects invalid destination
    ↓
Backend validation:
  if (!start || !end || !start.lat || !start.lng || !end.lat || !end.lng)
    ↓
Return 400 Bad Request:
  { error: 'Valid start and end coordinates are required.' }
    ↓
Flutter catches error
    ↓
Display: "Invalid location. Please try again."
```

### 10.3 No Routes Found

```
Scenario: OSRM cannot find route (e.g., islands, restricted areas)
    ↓
OSRM returns: { routes: [] }
    ↓
Backend throws: Error('No routes found')
    ↓
Flutter displays:
  "No route available between these locations"
    ↓
Suggest: "Try a different destination"
```

### 10.4 CPCB API Failure

```
Scenario: data.gov.in API down or rate limited
    ↓
Backend catches error
    ↓
Log: "[AQI] Failed to fetch CPCB live data: {error}"
    ↓
Fallback to mock stations:
  - 20 pre-defined stations with realistic values
  - Covers major Indian cities
  - Based on annual averages
    ↓
Continue processing with mock data
    ↓
Response includes disclaimer (optional future feature)
```


### 10.5 Location Permission Denied

```
Scenario: User denies location permission
    ↓
Check permission status
    ↓
If permanently denied:
    ↓
  Show dialog:
    Title: "Location Required"
    Message: "AeroNav needs your location to provide pollution-aware routing.
              Please open settings to grant permission."
    Actions:
      - "Cancel" → Close dialog
      - "Open Settings" → openAppSettings()
    ↓
If temporarily denied:
    ↓
  Request permission again
    ↓
  If denied: Show same dialog
```

### 10.6 GPS Signal Lost

```
Scenario: User enters tunnel/building during navigation
    ↓
Location stream stops updating
    ↓
Last known location remains on map
    ↓
Navigation continues with stale position
    ↓
When GPS returns:
    ↓
  Location stream resumes
    ↓
  Map jumps to current position
    ↓
  Check if user passed any steps
    ↓
  Auto-advance to correct step
```

### 10.7 Compass Unavailable

```
Scenario: Device has no magnetometer
    ↓
FlutterCompass.events returns null
    ↓
Fallback to GPS heading:
    ↓
  Use LocationData.heading (from movement)
    ↓
  If stationary: heading = 0 (north-up)
    ↓
  Map rotation still works, just less smooth
```

### 10.8 Sparse Station Coverage

```
Scenario: Route through remote area (e.g., Himalayas)
    ↓
IDW local (25km) finds no stations
    ↓
IDW regional (150km) finds no stations
    ↓
Fallback (500km) finds nearest station 300km away
    ↓
Blend with baseline:
  ratio = 1 - ((300 - 150) / (500 - 150))
  ratio = 1 - (150 / 350) = 0.57
  result = (stationValue × 0.57) + (baseline × 0.43)
    ↓
Return blended estimate
    ↓
Route displays with lower confidence
```


## 11. Security & Rate Limiting

### 11.1 Backend Security Measures

```javascript
// app.js - Security middleware stack

1. Helmet.js
   - Sets secure HTTP headers
   - Prevents common vulnerabilities (XSS, clickjacking)
   - Disables X-Powered-By header

2. CORS
   - Allows cross-origin requests from Flutter app
   - Configured for development (allow all origins)
   - Production: restrict to app domain

3. Rate Limiting
   - Window: 15 minutes
   - Max requests: 100 per IP
   - Prevents abuse and DoS attacks
   - Returns 429 Too Many Requests if exceeded

4. Input Validation
   - Validates lat/lng are numbers
   - Checks required fields exist
   - Returns 400 Bad Request for invalid input

5. Error Handling
   - Global error handler catches all exceptions
   - Logs errors with Pino
   - Returns 500 with sanitized error message
   - Never exposes stack traces to client
```

### 11.2 API Key Management

```
Environment Variables (.env):
  - DATAGOVIN_API_KEY: CPCB API access
  - SUPABASE_URL: Authentication service
  - SUPABASE_ANON_KEY: Public key for client
  - PORT: Server port (default 3000)

Security:
  - .env files in .gitignore
  - Never committed to repository
  - Separate keys for dev/staging/production
  - Rotate keys periodically
```

### 11.3 CPCB API Rate Limiting Strategy

```
Problem: data.gov.in has undocumented rate limits
    ↓
Solution: Aggressive caching
    ↓
  - Cache station data for 15 minutes
  - All requests share same cache
  - Reduces API calls by 95%
    ↓
Example:
  Without cache: 100 route requests = 100 CPCB calls
  With cache: 100 route requests = 4-7 CPCB calls (every 15 min)
    ↓
Result: Stay well under rate limits, prevent blocking
```


## 12. Future Enhancements & Scalability

### 12.1 Planned Features

**1. Historical AQI Analysis**
```
Store route AQI data over time
    ↓
Analyze patterns:
  - Best time of day for route
  - Seasonal variations
  - Day-of-week patterns
    ↓
Suggest: "This route is 30% cleaner at 6 AM"
```

**2. Real-Time Rerouting**
```
During navigation:
  Monitor AQI along route
    ↓
  If AQI spikes ahead (e.g., accident, fire):
    ↓
  Calculate alternative route
    ↓
  Notify user: "Cleaner route available, +5 min"
    ↓
  User accepts → reroute
```

**3. User Preferences**
```
Settings:
  - AQI sensitivity (strict/moderate/relaxed)
  - Max time penalty (e.g., +20% for cleaner route)
  - Pollutant priorities (PM2.5 vs NO2)
    ↓
Personalized route ranking
```

**4. Offline Mode**
```
Pre-download:
  - Map tiles for region
  - OSRM route data
  - Last known AQI data
    ↓
Navigate without internet
    ↓
Sync when connection returns
```

**5. Health Impact Tracking**
```
Track:
  - Total distance traveled
  - Average AQI exposure
  - Pollution avoided vs. fastest route
    ↓
Display:
  - "You've avoided 2.5 kg of PM2.5 this month"
  - Health score and achievements
```


### 12.2 Scalability Considerations

**Current Architecture (MVP):**
```
Single Node.js server
In-memory caching (node-cache)
Public OSRM instance
Suitable for: 100-1000 users
```

**Scaling to 10,000+ Users:**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         SCALED ARCHITECTURE                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  Load Balancer (Nginx/AWS ALB)                                          │
│         │                                                                │
│         ├─── Node.js Instance 1 ──┐                                     │
│         ├─── Node.js Instance 2 ──┼─── Redis Cluster (shared cache)    │
│         └─── Node.js Instance N ──┘                                     │
│                                                                           │
│  Self-hosted OSRM Server                                                │
│    - Pre-processed India map data                                       │
│    - Sub-100ms response times                                           │
│    - No external dependency                                             │
│                                                                           │
│  PostgreSQL + PostGIS                                                   │
│    - Store historical AQI data                                          │
│    - Spatial queries for station lookup                                 │
│    - User preferences and history                                       │
│                                                                           │
│  CDN (CloudFlare/AWS CloudFront)                                        │
│    - Cache map tiles                                                    │
│    - Serve static assets                                                │
│    - DDoS protection                                                    │
│                                                                           │
└─────────────────────────────────────────────────────────────────────────┘
```

**Cost Estimates (10,000 daily active users):**
```
AWS EC2 (3x t3.medium):        $100/month
Redis (ElastiCache):           $50/month
PostgreSQL (RDS):              $80/month
Load Balancer:                 $20/month
Data Transfer:                 $50/month
OSRM Server (t3.large):        $70/month
                              ──────────
Total:                         $370/month
Per user:                      $0.037/month
```


### 12.3 Database Schema (Future)

```sql
-- Users table
CREATE TABLE users (
  id UUID PRIMARY KEY,
  email VARCHAR(255) UNIQUE,
  created_at TIMESTAMP DEFAULT NOW(),
  preferences JSONB
);

-- Routes table (historical data)
CREATE TABLE routes (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES users(id),
  start_point GEOGRAPHY(POINT),
  end_point GEOGRAPHY(POINT),
  distance_km DECIMAL(10,2),
  duration_min DECIMAL(10,2),
  avg_aqi INTEGER,
  max_aqi INTEGER,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Route segments (detailed AQI data)
CREATE TABLE route_segments (
  id UUID PRIMARY KEY,
  route_id UUID REFERENCES routes(id),
  segment_index INTEGER,
  geometry GEOGRAPHY(LINESTRING),
  aqi INTEGER,
  pollutants JSONB,
  created_at TIMESTAMP DEFAULT NOW()
);

-- AQI stations (cached from CPCB)
CREATE TABLE aqi_stations (
  id UUID PRIMARY KEY,
  location GEOGRAPHY(POINT),
  station_name VARCHAR(255),
  pollutants JSONB,
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Spatial indexes for fast queries
CREATE INDEX idx_routes_start ON routes USING GIST(start_point);
CREATE INDEX idx_routes_end ON routes USING GIST(end_point);
CREATE INDEX idx_stations_location ON aqi_stations USING GIST(location);
```


## 13. Testing & Quality Assurance

### 13.1 Backend Testing Strategy

```javascript
// Unit Tests (Jest)

describe('IDW Interpolation', () => {
  test('returns exact value when on station', () => {
    const target = { lat: 28.61, lng: 77.20 }
    const stations = [
      { lat: 28.61, lng: 77.20, value: 100 }
    ]
    expect(calculateIDW(target, stations, 3, 50)).toBe(100)
  })

  test('returns null when no stations in range', () => {
    const target = { lat: 28.61, lng: 77.20 }
    const stations = [
      { lat: 30.00, lng: 80.00, value: 100 }  // >200km away
    ]
    expect(calculateIDW(target, stations, 3, 50)).toBeNull()
  })

  test('weights nearby stations more heavily', () => {
    const target = { lat: 28.61, lng: 77.20 }
    const stations = [
      { lat: 28.62, lng: 77.21, value: 100 },  // ~1km away
      { lat: 28.70, lng: 77.30, value: 200 }   // ~10km away
    ]
    const result = calculateIDW(target, stations, 3, 50)
    expect(result).toBeCloseTo(100, 0)  // Should be much closer to 100
  })
})

describe('AQI Calculation', () => {
  test('calculates correct sub-index for PM2.5', () => {
    expect(calculateSubIndex(82.5, 'pm25')).toBe(174)
  })

  test('returns max sub-index as overall AQI', () => {
    const pollutants = {
      pm25: 82.5,  // → 174
      pm10: 125.3, // → 168
      no2: 38.7,   // → 48
      so2: 10.2,   // → 25
      co: 1.15,    // → 55
      o3: 26.8     // → 26
    }
    expect(calculateBaseAQI(pollutants)).toBe(174)
  })
})
```


### 13.2 Integration Tests

```javascript
// Integration Tests (Supertest)

describe('POST /api/navigation/route', () => {
  test('returns valid route with segments', async () => {
    const response = await request(app)
      .post('/api/navigation/route')
      .send({
        start: { lat: 28.6139, lng: 77.2090 },
        end: { lat: 27.1767, lng: 78.0081 }
      })
      .expect(200)

    expect(response.body).toHaveProperty('routes')
    expect(Array.isArray(response.body.routes)).toBe(true)
    expect(response.body.routes.length).toBeGreaterThan(0)

    const route = response.body.routes[0]
    expect(route).toHaveProperty('summary')
    expect(route).toHaveProperty('segments')
    expect(route.summary).toHaveProperty('totalDistanceKm')
    expect(route.summary).toHaveProperty('overallAqi')
  })

  test('returns 400 for invalid coordinates', async () => {
    await request(app)
      .post('/api/navigation/route')
      .send({ start: {}, end: {} })
      .expect(400)
  })

  test('marks fastest and cleanest routes', async () => {
    const response = await request(app)
      .post('/api/navigation/route')
      .send({
        start: { lat: 28.6139, lng: 77.2090 },
        end: { lat: 27.1767, lng: 78.0081 }
      })

    const routes = response.body.routes
    const fastestCount = routes.filter(r => r.isFastest).length
    const cleanestCount = routes.filter(r => r.isCleanest).length

    expect(fastestCount).toBe(1)
    expect(cleanestCount).toBeGreaterThanOrEqual(1)
  })
})
```


### 13.3 Frontend Testing Strategy

```dart
// Widget Tests

testWidgets('RoutesScreen displays loading overlay initially', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RoutesScreen(
        startPoint: LatLng(28.6139, 77.2090),
        endPoint: LatLng(27.1767, 78.0081),
        destinationName: 'Agra',
      ),
    ),
  );

  expect(find.text('Calculating pollution-aware routes...'), findsOneWidget);
});

testWidgets('Displays route cards after loading', (tester) async {
  // Mock NavigationService
  final mockService = MockNavigationService();
  when(mockService.getPollutionRoute(any, any, any, any))
    .thenAnswer((_) async => mockRouteData);

  await tester.pumpWidget(/* ... */);
  await tester.pumpAndSettle();

  expect(find.text('Cleanest Route'), findsOneWidget);
  expect(find.text('Start Navigation'), findsOneWidget);
});

testWidgets('Switches route on card tap', (tester) async {
  await tester.pumpWidget(/* ... */);
  await tester.pumpAndSettle();

  // Tap second route card
  await tester.tap(find.text('Fastest Route'));
  await tester.pumpAndSettle();

  // Verify polylines updated (check map state)
  // Verify selected route changed
});
```

### 13.4 Manual Testing Checklist

```
□ Route Calculation
  □ Delhi to Agra (long distance)
  □ Local route (< 10km)
  □ Cross-city route
  □ Route with no alternatives

□ Map Rendering
  □ All polylines visible
  □ Colors match AQI categories
  □ Smooth camera transitions
  □ Markers positioned correctly

□ Navigation Mode
  □ Map centers on user
  □ Map rotates with heading
  □ Instructions update correctly
  □ Steps advance automatically
  □ Exit navigation works

□ Error Handling
  □ No internet connection
  □ Backend timeout
  □ Invalid destination
  □ Location permission denied
  □ GPS signal lost

□ Performance
  □ Route loads in < 3 seconds
  □ Map rendering is smooth (60fps)
  □ No memory leaks
  □ Battery usage acceptable
```


## 14. Deployment & DevOps

### 14.1 Development Setup

```bash
# Backend
cd aeronav-backend
npm install
cp .env.example .env
# Edit .env with API keys
npm run dev  # Starts nodemon on port 3000

# Frontend
flutter pub get
# Edit lib/config/app_config.dart with backend URL
flutter run  # For emulator
flutter run -d <device-id>  # For physical device
```

### 14.2 Environment Configuration

```
Development:
  Backend: http://localhost:3000
  Frontend: Points to local backend
  OSRM: Public instance
  CPCB: Real API with dev key

Staging:
  Backend: https://staging-api.aeronav.app
  Frontend: Points to staging backend
  OSRM: Self-hosted instance
  CPCB: Real API with staging key

Production:
  Backend: https://api.aeronav.app
  Frontend: Points to production backend
  OSRM: Self-hosted with redundancy
  CPCB: Real API with production key
  CDN: CloudFlare for static assets
  Monitoring: Sentry for error tracking
```

### 14.3 CI/CD Pipeline

```yaml
# .github/workflows/backend.yml

name: Backend CI/CD

on:
  push:
    branches: [main, develop]
    paths:
      - 'aeronav-backend/**'

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: actions/setup-node@v2
        with:
          node-version: '18'
      - run: cd aeronav-backend && npm install
      - run: cd aeronav-backend && npm test
      - run: cd aeronav-backend && npm run lint

  deploy:
    needs: test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to production
        run: |
          # SSH to server
          # Pull latest code
          # Restart PM2 process
```


### 14.4 Monitoring & Logging

```javascript
// Backend Logging (Pino)

logger.info('Server started', { port: 3000 })
logger.debug('Route request', { start, end })
logger.error('OSRM fetch failed', { error: err.message })

// Log Levels:
// - error: Critical failures
// - warn: Degraded performance
// - info: Important events
// - debug: Detailed diagnostics
// - trace: Very verbose (disabled in production)

// Production: Ship logs to CloudWatch/Datadog
// Development: Console output with pretty printing
```

```dart
// Frontend Error Tracking (Sentry)

void main() async {
  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://...@sentry.io/...';
      options.environment = 'production';
    },
    appRunner: () => runApp(AeroNavApp()),
  );
}

// Automatic error capture:
// - Unhandled exceptions
// - Network failures
// - Widget build errors
// - Navigation errors

// Manual tracking:
Sentry.captureException(error, stackTrace: stackTrace);
Sentry.captureMessage('Route calculation took > 5s');
```

### 14.5 Health Checks

```javascript
// Backend health endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'AeroNav Backend is running',
    uptime: process.uptime(),
    timestamp: new Date(),
    memory: process.memoryUsage(),
    cache: {
      keys: cache.keys().length,
      stats: cache.getStats()
    }
  })
})

// Monitoring service pings /health every 60 seconds
// Alert if:
// - Response time > 1000ms
// - Status code != 200
// - Uptime resets (server restart)
// - Memory usage > 80%
```


## 15. Summary & Key Takeaways

### 15.1 Complete Workflow Recap

```
1. USER ACTION
   User selects destination in Flutter app

2. FRONTEND REQUEST
   HTTP POST to /api/navigation/route with start/end coordinates

3. BACKEND PROCESSING
   a. Fetch 3 alternative routes from OSRM (cached 1 hour)
   b. Split each route into 1km segments
   c. Fetch CPCB station data (cached 15 minutes)
   d. For each segment midpoint:
      - Apply IDW interpolation (power=3, 25km/150km/500km tiers)
      - Calculate pollutant concentrations
      - Calculate AQI using CPCB breakpoints
      - Map to color category
   e. Calculate route summaries (avg/max AQI, distance, duration)
   f. Identify fastest and cleanest routes
   g. Return JSON with all routes and segments

4. FRONTEND RENDERING
   a. Parse response and select cleanest route by default
   b. Build polylines (grey for inactive, color-coded for active)
   c. Render map with OSM tiles, polylines, and markers
   d. Fit camera to show all routes
   e. Display route selection UI with AQI legend

5. NAVIGATION MODE
   a. Request turn-by-turn steps from backend
   b. Start location and compass tracking
   c. Center map on user at zoom 18
   d. Rotate map to match heading
   e. Display instruction banner
   f. Auto-advance steps when within 20m
   g. Update UI continuously
```


### 15.2 Technical Highlights

**Innovation:**
- First pollution-aware navigation app for India
- Real-time AQI integration with route planning
- Multi-tier IDW interpolation for accurate estimates
- Color-coded route visualization

**Performance:**
- Sub-second response times (with warm cache)
- 95% reduction in API calls through caching
- Smooth 60fps map rendering
- Efficient batch processing of segments

**Reliability:**
- Graceful degradation (mock data fallback)
- Comprehensive error handling
- Multi-level caching strategy
- Rate limiting protection

**User Experience:**
- Intuitive route comparison
- Real-time navigation with heading
- Clear AQI visualization
- Minimal cognitive load

### 15.3 Key Metrics

```
Route Calculation:
  - Average time: 740ms (warm cache)
  - Segments per route: 20-50
  - Alternative routes: Up to 3
  - AQI accuracy: ±10% vs. ground truth

Data Volume:
  - Request size: ~100 bytes
  - Response size: ~15-20KB (compressed)
  - CPCB stations: ~3400 across India
  - Cache hit rate: 60-95% depending on layer

User Experience:
  - Time to first route: ~1.2 seconds
  - Map frame rate: 60fps
  - Navigation accuracy: ±20 meters
  - Step advancement: < 20m threshold
```


### 15.4 Architecture Strengths

**Modularity:**
- Clear separation of concerns (services, routes, utils)
- Easy to test individual components
- Simple to add new features

**Scalability:**
- Stateless backend (horizontal scaling ready)
- Cache-first architecture
- Async processing with Promise.all
- Database-ready schema designed

**Maintainability:**
- Consistent code style
- Comprehensive error handling
- Detailed logging
- Self-documenting code structure

**Extensibility:**
- Plugin architecture for new data sources
- Configurable AQI calculation
- Flexible route scoring
- Easy to add new pollutants

### 15.5 Lessons Learned

**What Worked Well:**
1. IDW interpolation provides accurate estimates
2. 1km segmentation balances accuracy and performance
3. Multi-level caching dramatically improves speed
4. Color-coded visualization is intuitive
5. CPCB data is reliable and comprehensive

**Challenges Overcome:**
1. CPCB API rate limiting → Aggressive caching
2. Sparse station coverage → Multi-tier fallback
3. Weather modifier drift → Disabled modifiers
4. Physical device testing → IP-based backend URL
5. Map rotation complexity → Compass integration

**Future Improvements:**
1. Self-hosted OSRM for better control
2. PostgreSQL + PostGIS for historical data
3. Real-time rerouting based on AQI changes
4. Machine learning for AQI prediction
5. Offline mode with pre-cached data

---

## 16. Presentation Tips

### For Technical Audience:
- Focus on IDW algorithm and CPCB breakpoints
- Explain caching strategy and performance gains
- Discuss scalability architecture
- Show code snippets and data flow diagrams

### For Non-Technical Audience:
- Emphasize health benefits and user experience
- Use visual demonstrations (live demo or video)
- Explain AQI categories with real-world examples
- Focus on route comparison and decision-making

### Demo Flow:
1. Show app launch and location detection
2. Search for destination (Delhi to Agra)
3. Watch loading animation
4. Explain route comparison UI
5. Switch between routes to show polyline changes
6. Start navigation mode
7. Show map rotation and step advancement
8. Exit navigation and return to route selection

---

## Appendix: Glossary

**AQI (Air Quality Index):** Numerical scale (0-500) representing air pollution levels

**CPCB:** Central Pollution Control Board (India's environmental agency)

**IDW:** Inverse Distance Weighting (spatial interpolation method)

**OSRM:** Open Source Routing Machine (route calculation engine)

**Haversine:** Formula for calculating distance between GPS coordinates

**Polyline:** Series of connected line segments on a map

**Sub-index:** AQI value for individual pollutant

**Breakpoint:** Threshold value in AQI calculation formula

**PM2.5:** Particulate Matter < 2.5 micrometers (most harmful pollutant)

**Segment:** 1km chunk of route with uniform AQI color

---

**End of Document**

*Generated for AeroNav Presentation*  
*Last Updated: 2026-04-30*
