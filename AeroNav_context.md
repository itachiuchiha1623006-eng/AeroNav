# AeroNav Project Context

## Project Overview
AeroNav is a pollution-aware navigation platform consisting of a Flutter-based mobile app and a Node.js/Express backend. Its main premise is mapping and calculating routes while taking real-time Air Quality Index (AQI) into consideration to generate "pollution-aware polylines" rendering optimal travel paths.

## Backend Architecture (`aeronav-backend/`)
- **Server:** Node.js, Express (`app.js`). Runs on `PORT 3000`.
- **Environment:** Relies on `.env` containing `DATAGOVIN_API_KEY` for fetching live AQI from CPCB's APIs. Currently bound to `0.0.0.0:3000` for physical device access.
- **Data Source:** Exclusively `data.gov.in` (CPCB). 
- **Core Logic:**
  - `aqiService.js`: Employs Inverse Distance Weighting (IDW) interpolation to calculate AQI at any specific geometric point based on coordinates from nearest pre-defined stations (`station_coords.json`). It heavily caches this to avoid being blocked.
  - `scoreEngine.js`: Contains breakpoints for calculating final AQI and generating category data (e.g. "Good", "Moderate").
  - `navigation.js`: Exposes `/api/navigation/route` & `/api/navigation/steps`. When requested, it queries OSRM for raw route data, partitions the coordinate line into 1km chunks, samples each chunk's AQI via `aqiService` and returns color-categorized segment geometries.

## Frontend Architecture (`lib/`)
- **Framework:** Flutter.
- **Routing:** Uses `go_router` (`lib/router/app_router.dart`).
- **Map Subsystem:** Relies heavily on `flutter_map` using OSM tiles for cartography.
- **Core Screens:**
  1. `HomeScreen` (`home_screen.dart`): Serves as the primary exploration layer. A user manages search bars, queries surrounding locations, and gets live AQI bubbles. 
     - When a destination is selected, the application transitions over to the `RoutesScreen`.
  2. `RoutesScreen` (`routes_screen.dart`): Handles the primary Google Maps-style navigation UI.
     - Automatically connects out to the backend `getPollutionRoute` service through `NavigationService` (`navigation_service.dart`).
     - Shows a detailed loading splash `Calculating optimal pollution-aware route...` and drops in polyline layers mapped per AQI segment color.
     - Offers an interactive Start Navigation mode utilizing device sensors (`location` and `flutter_compass`) to rotate map rendering live while moving. Includes standard safe-area padding for OS navigation buttons.

## Important Notes for Agents
- The backend relies on a physical network loopback config. When testing with physical devices, `navigation_service.dart`'s `_baseUrl` must explicitly point to the dev machine's active IP instance (e.g., `192.168.1.x:3000`), rather than `localhost`.
- JSON keys exchanged between frontend and backend route APIs are nested inside a `routes` array. Each route contains `summary` (`totalDistanceKm`, `totalDurationMin`, `overallAqi`), `segments`, and boolean markers `isFastest`/`isCleanest`. avoids using typical raw OSRM syntax on the UI.
- `PulsingLocationMarker` does not feature `heading` inputs. Rotation is directly controlled through the `MapController` from `flutter_map`.
