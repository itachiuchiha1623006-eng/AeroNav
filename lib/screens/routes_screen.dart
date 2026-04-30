import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart' as loc;
import 'package:go_router/go_router.dart';
import 'package:flutter_compass/flutter_compass.dart';

import '../services/navigation_service.dart';
import '../widgets/pulsing_location_marker.dart';
import '../widgets/route_loading_overlay.dart';
import '../models/route_step.dart';

class RoutesScreen extends StatefulWidget {
  final LatLng startPoint;
  final LatLng endPoint;
  final String destinationName;

  const RoutesScreen({
    super.key,
    required this.startPoint,
    required this.endPoint,
    required this.destinationName,
  });

  @override
  State<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends State<RoutesScreen> {
  final MapController _mapController = MapController();
  final NavigationService _navService = NavigationService();

  bool _isLoading = true;
  String _loadingMessage = 'Calculating pollution-aware routes...';
  String? _errorMessage;

  // Multi-route state
  List<Map<String, dynamic>> _routes = [];
  int _selectedRouteIndex = 0;

  // Navigation state
  List<RouteStep> _navigationSteps = [];
  int _currentStepIndex = 0;
  bool _isNavigating = false;

  LatLng? _userLocation;
  double _currentHeading = 0.0;

  StreamSubscription<loc.LocationData>? _locationSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;

  @override
  void initState() {
    super.initState();
    _userLocation = widget.startPoint;
    _initializeRoutes();
    _startTracking();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _compassSubscription?.cancel();
    super.dispose();
  }

  // ─── Location & Compass ───────────────────────────────────────────────────

  void _startTracking() {
    final location = loc.Location();
    _locationSubscription = location.onLocationChanged.listen((locData) {
      if (!mounted) return;
      final lat = locData.latitude;
      final lng = locData.longitude;
      if (lat == null || lng == null) return;

      setState(() => _userLocation = LatLng(lat, lng));

      if (_isNavigating) {
        _mapController.move(_userLocation!, 18.0);
        if (_currentHeading == 0.0 && locData.heading != null) {
          _mapController.rotate(locData.heading!);
        }
        _checkStepAdvance();
      }
    });

    _compassSubscription = FlutterCompass.events?.listen((event) {
      if (!mounted || event.heading == null) return;
      setState(() => _currentHeading = event.heading!);
      if (_isNavigating) _mapController.rotate(_currentHeading);
    });
  }

  void _checkStepAdvance() {
    if (_navigationSteps.isEmpty || _currentStepIndex >= _navigationSteps.length) return;
    const distLib = Distance();
    final meters = distLib.as(LengthUnit.Meter, _userLocation!, _navigationSteps[_currentStepIndex].point).toInt();
    if (meters < 20 && _currentStepIndex < _navigationSteps.length - 1) {
      setState(() => _currentStepIndex++);
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  Color _colorFromHex(String? hexColor) {
    if (hexColor == null || hexColor.isEmpty) return Colors.grey;
    final cleaned = hexColor.toUpperCase().replaceAll('#', '');
    final full = cleaned.length == 6 ? 'FF$cleaned' : cleaned;
    try {
      return Color(int.parse(full, radix: 16));
    } catch (_) {
      return Colors.grey;
    }
  }

  String _formatDuration(double durationMin) {
    final h = durationMin ~/ 60;
    final m = (durationMin % 60).round();
    if (h > 0) return '${h}h ${m}m';
    return '$m min';
  }

  // ─── Route Initialisation ─────────────────────────────────────────────────

  Future<void> _initializeRoutes() async {
    try {
      final routeData = await _navService.getPollutionRoute(
        startLat: widget.startPoint.latitude,
        startLng: widget.startPoint.longitude,
        endLat: widget.endPoint.latitude,
        endLng: widget.endPoint.longitude,
      );

      // Safely extract the routes array
      final rawRoutes = routeData?['routes'];
      if (rawRoutes == null || rawRoutes is! List || rawRoutes.isEmpty) {
        _handleError('Server returned no routes. Try again.');
        return;
      }

      final parsedRoutes = <Map<String, dynamic>>[];
      for (final r in rawRoutes) {
        if (r is Map<String, dynamic>) parsedRoutes.add(r);
      }

      if (parsedRoutes.isEmpty) {
        _handleError('Could not parse route data.');
        return;
      }

      // Default to cleanest route
      int defaultIdx = 0;
      for (int i = 0; i < parsedRoutes.length; i++) {
        if (parsedRoutes[i]['isCleanest'] == true) {
          defaultIdx = i;
          break;
        }
      }

      if (!mounted) return;
      setState(() {
        _routes = parsedRoutes;
        _selectedRouteIndex = defaultIdx;
        _isLoading = false;
      });

      _fitCameraToRoutes();
    } on Exception catch (e) {
      // Surface the real error (timeout, no network, server error, etc.)
      final msg = e.toString().replaceFirst('Exception: ', '');
      _handleError('Could not load route: $msg');
    } catch (e) {
      _handleError('Unexpected error: $e');
    }
  }

  void _fitCameraToRoutes() {
    if (_routes.isEmpty) return;
    final allPoints = <LatLng>[];
    for (final route in _routes) {
      final segments = route['segments'];
      if (segments is! List) continue;
      for (final segment in segments) {
        final coords = segment['coordinates'];
        if (coords is! List) continue;
        for (final c in coords) {
          if (c is List && c.length >= 2) {
            allPoints.add(LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()));
          }
        }
      }
    }

    if (allPoints.isEmpty) return;
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final bounds = LatLngBounds.fromPoints(allPoints);
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60.0)),
      );
    });
  }

  void _handleError(String message) {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _errorMessage = message;
    });
  }

  // ─── Navigation Start ─────────────────────────────────────────────────────

  Future<void> _startNavigation() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Getting turn-by-turn instructions...';
    });

    try {
      final navData = await _navService.getNavigationSteps(
        startLat: widget.startPoint.latitude,
        startLng: widget.startPoint.longitude,
        endLat: widget.endPoint.latitude,
        endLng: widget.endPoint.longitude,
      );

      if (navData != null) {
        final rawRoutes = navData['routes'];
        if (rawRoutes is List && rawRoutes.length > _selectedRouteIndex) {
          final selectedRoute = rawRoutes[_selectedRouteIndex];
          if (selectedRoute is Map) {
            final stepsJson = selectedRoute['steps'];
            if (stepsJson is List) {
              _navigationSteps = stepsJson
                  .whereType<Map<String, dynamic>>()
                  .map((s) => RouteStep.fromJson(s))
                  .toList();
            }
          }
        }
      }
    } catch (e) {
      // Non-fatal: start navigation without steps
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _isNavigating = true;
    });

    if (_userLocation != null) {
      _mapController.move(_userLocation!, 18.0);
      _mapController.rotate(_currentHeading);
    }
  }

  // ─── Polyline Builder ─────────────────────────────────────────────────────

  List<Polyline> _buildPolylines() {
    final polylines = <Polyline>[];

    // Draw inactive routes first (grey, behind)
    for (int i = 0; i < _routes.length; i++) {
      if (i == _selectedRouteIndex) continue;
      final segments = _routes[i]['segments'];
      if (segments is! List) continue;
      final points = <LatLng>[];
      for (final seg in segments) {
        final coords = seg['coordinates'];
        if (coords is! List) continue;
        for (final c in coords) {
          if (c is List && c.length >= 2) {
            points.add(LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()));
          }
        }
      }
      if (points.isNotEmpty) {
        polylines.add(Polyline(
          points: points,
          color: Colors.blueGrey.withAlpha(120),
          strokeWidth: 5.0,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ));
      }
    }

    // Draw active route on top with AQI colours
    if (_routes.isNotEmpty) {
      final segments = _routes[_selectedRouteIndex]['segments'];
      if (segments is List) {
        for (final segment in segments) {
          final coords = segment['coordinates'];
          final aqiColor = segment['aqi']?['color'] as String?;
          if (coords is! List) continue;
          final points = <LatLng>[];
          for (final c in coords) {
            if (c is List && c.length >= 2) {
              points.add(LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()));
            }
          }
          if (points.isNotEmpty) {
            polylines.add(Polyline(
              points: points,
              color: _colorFromHex(aqiColor),
              strokeWidth: 7.0,
              strokeCap: StrokeCap.round,
              strokeJoin: StrokeJoin.round,
            ));
          }
        }
      }
    }

    return polylines;
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return RouteLoadingOverlay(message: _loadingMessage);
    }

    // ── Error state ──────────────────────────────────────────────────────────
    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 20),
                  const Text(
                    'Route Unavailable',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _isLoading = true;
                        _errorMessage = null;
                        _loadingMessage = 'Calculating pollution-aware routes...';
                      });
                      _initializeRoutes();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2DB87A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => context.pop(),
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // ── Map ──────────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.startPoint,
              initialZoom: 13.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.aeronav.app',
              ),
              PolylineLayer(polylines: _buildPolylines()),
              MarkerLayer(
                markers: [
                  Marker(
                    point: widget.endPoint,
                    width: 40,
                    height: 40,
                    child: const Icon(Icons.location_on, color: Colors.blue, size: 40),
                  ),
                  if (_userLocation != null)
                    Marker(
                      point: _userLocation!,
                      width: 40,
                      height: 40,
                      child: _isNavigating
                          ? Transform.rotate(
                              angle: _currentHeading * (math.pi / 180),
                              child: const Icon(Icons.navigation, color: Colors.blue, size: 36),
                            )
                          : const PulsingLocationMarker(),
                    ),
                ],
              ),
            ],
          ),

          // ── Back button (hidden during navigation) ────────────────────────
          if (!_isNavigating)
            Positioned(
              top: 50,
              left: 16,
              child: CircleAvatar(
                backgroundColor: Colors.white,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black87),
                  onPressed: () => context.pop(),
                ),
              ),
            ),

          // ── Nav banner ───────────────────────────────────────────────────
          if (_isNavigating && _navigationSteps.isNotEmpty)
            Positioned(
              top: 50,
              left: 16,
              right: 16,
              child: _buildTopNavBanner(),
            ),

          // ── Bottom sheet ─────────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _isNavigating ? _buildNavControls() : _buildRouteChoices(),
          ),
        ],
      ),
    );
  }

  // ─── Widgets ──────────────────────────────────────────────────────────────

  Widget _buildTopNavBanner() {
    if (_currentStepIndex >= _navigationSteps.length) return const SizedBox();
    final step = _navigationSteps[_currentStepIndex];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2DB87A),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(50), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.directions, color: Colors.white, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.instruction,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('${(step.distance / 1000).toStringAsFixed(1)} km',
                    style: const TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavControls() {
    final summary = _routes.isNotEmpty ? _routes[_selectedRouteIndex]['summary'] as Map? : null;
    final durMin = (summary?['totalDurationMin'] as num?)?.toDouble() ?? 0.0;
    final distKm = (summary?['totalDistanceKm'] as num?)?.toDouble() ?? 0.0;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(top: 20, left: 20, right: 20),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_formatDuration(durMin),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green)),
                  Text('${distKm.toStringAsFixed(1)} km',
                      style: const TextStyle(color: Colors.grey)),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _isNavigating = false;
                    _currentStepIndex = 0;
                    _mapController.rotate(0);
                    _fitCameraToRoutes();
                  });
                },
                icon: const Icon(Icons.close),
                label: const Text('Exit'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[50],
                  foregroundColor: Colors.red,
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRouteChoices() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
      ),
      padding: const EdgeInsets.only(left: 20, right: 20, top: 20),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              // Route cards
              ..._routes.asMap().entries.map((entry) {
                final index = entry.key;
                final route = entry.value;
                final summary = route['summary'] as Map? ?? {};
                final isSelected = (_selectedRouteIndex == index);
                final isCleanest = route['isCleanest'] == true;
                final isFastest = route['isFastest'] == true;

                final durMin = (summary['totalDurationMin'] as num?)?.toDouble() ?? 0.0;
                final distKm = (summary['totalDistanceKm'] as num?)?.toDouble() ?? 0.0;
                final overallAqi = summary['overallAqi']?.toString() ?? '--';
                final overallCategory = summary['overallCategory'] as String? ?? '';
                final overallColor = summary['overallColor'] as String? ?? '#808080';

                String label;
                IconData iconData;
                Color labelColor;

                if (isCleanest && isFastest) {
                  label = 'Optimal Route';
                  iconData = Icons.star_rounded;
                  labelColor = Colors.blue[800]!;
                } else if (isCleanest) {
                  label = 'Cleanest Route';
                  iconData = Icons.eco_rounded;
                  labelColor = Colors.green[800]!;
                } else if (isFastest) {
                  label = 'Fastest Route';
                  iconData = Icons.schedule_rounded;
                  labelColor = Colors.deepOrange[800]!;
                } else {
                  label = 'Alternative Route';
                  iconData = Icons.alt_route;
                  labelColor = Colors.grey[700]!;
                }

                final aqiColor = _colorFromHex(overallColor);

                return GestureDetector(
                  onTap: () => setState(() => _selectedRouteIndex = index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFF0FDF4) : Colors.white,
                      border: Border.all(
                        color: isSelected ? Colors.green[300]! : Colors.grey[200]!,
                        width: isSelected ? 1.5 : 1.0,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Label + distance
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(iconData, color: labelColor, size: 18),
                              const SizedBox(width: 6),
                              Text(label,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
                            ]),
                            const SizedBox(height: 3),
                            Text('${distKm.toStringAsFixed(1)} km',
                                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                            if (summary['weather'] != null) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(Icons.water_drop, size: 12, color: Colors.blue[400]),
                                  const SizedBox(width: 2),
                                  Text('${summary['weather']['humidity']}%',
                                      style: TextStyle(fontSize: 11, color: Colors.grey[700])),
                                  const SizedBox(width: 8),
                                  Icon(Icons.air, size: 12, color: Colors.grey[500]),
                                  const SizedBox(width: 2),
                                  Text('${summary['weather']['windSpeed']} km/h',
                                      style: TextStyle(fontSize: 11, color: Colors.grey[700])),
                                ],
                              ),
                            ],
                          ],
                        ),
                        // Duration + AQI badge
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _formatDuration(durMin),
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: isFastest ? Colors.black87 : Colors.green[800]),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: aqiColor.withAlpha(40),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'AQI $overallAqi${overallCategory.isNotEmpty ? ' · $overallCategory' : ''}',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: aqiColor),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 8),

              // AQI Legend
              _buildAqiLegend(),

              const SizedBox(height: 10),

              // Start Navigation
              ElevatedButton(
                onPressed: _startNavigation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF65C440),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  elevation: 0,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.navigation_rounded, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Start Navigation',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── AQI Legend ───────────────────────────────────────────────────────────

  Widget _buildAqiLegend() {
    // CPCB tiers — mirrors colorMapper.js on the backend
    const tiers = [
      (label: 'Good',         range: '0–50',   hex: 0xFF00E400),
      (label: 'Satisfactory', range: '51–100',  hex: 0xFF92D14F),
      (label: 'Moderate',     range: '101–200', hex: 0xFFFFFF00),
      (label: 'Poor',         range: '201–300', hex: 0xFFFF7E00),
      (label: 'Very Poor',    range: '301–400', hex: 0xFFFF0000),
      (label: 'Severe',       range: '401+',    hex: 0xFF7E0023),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'AQI Scale',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey),
        ),
        const SizedBox(height: 6),
        Row(
          children: tiers.map((tier) {
            final color = Color(tier.hex);
            // Dark text for light backgrounds (Good / Satisfactory / Moderate)
            final textColor = tier.hex == 0xFFFFFF00 ? Colors.black87 : Colors.white;
            return Expanded(
              child: Tooltip(
                message: '${tier.label}\n${tier.range}',
                child: Container(
                  height: 28,
                  decoration: BoxDecoration(
                    color: color,
                    border: Border.all(color: Colors.black.withAlpha(20), width: 0.5),
                  ),
                  child: Center(
                    child: Text(
                      tier.label.replaceAll(' ', '\n'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 7.5,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: tiers.map((t) => Expanded(
            child: Text(
              t.range,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 7, color: Colors.grey),
            ),
          )).toList(),
        ),
      ],
    );
  }
}
