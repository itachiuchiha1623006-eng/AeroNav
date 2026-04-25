import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart' as loc;
import 'package:go_router/go_router.dart';
import 'package:flutter_compass/flutter_compass.dart';

import '../services/navigation_service.dart';
import '../widgets/pulsing_location_marker.dart';
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
  String _loadingMessage = 'Calculating optimal pollution-aware route...';
  
  List<Polyline> _polylines = [];
  Map<String, dynamic>? _routeSummary;
  List<RouteStep> _navigationSteps = [];
  int _currentStepIndex = 0;

  LatLng? _userLocation;
  double _currentHeading = 0.0;
  
  StreamSubscription<loc.LocationData>? _locationSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;
  
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    _userLocation = widget.startPoint;
    _initializeRoute();
    _startTracking();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _compassSubscription?.cancel();
    super.dispose();
  }

  void _startTracking() {
    loc.Location location = loc.Location();
    _locationSubscription = location.onLocationChanged.listen((locData) {
      if (!mounted) return;
      if (locData.latitude != null && locData.longitude != null) {
        setState(() {
          _userLocation = LatLng(locData.latitude!, locData.longitude!);
        });
        
        if (_isNavigating) {
          _mapController.move(_userLocation!, 18.0);
          if (_currentHeading == 0.0 && locData.heading != null) {
             _mapController.rotate(locData.heading!);
          }
          
          if (_navigationSteps.isNotEmpty && _currentStepIndex < _navigationSteps.length) {
            final Distance distanceLib = const Distance();
            final int meters = distanceLib.as(
              LengthUnit.Meter, 
              _userLocation!,
              _navigationSteps[_currentStepIndex].point
            ).toInt();

            if (meters < 20 && _currentStepIndex < _navigationSteps.length - 1) {
              setState(() {
                _currentStepIndex++;
              });
            }
          }
        }
      }
    });

    _compassSubscription = FlutterCompass.events?.listen((event) {
      if (!mounted) return;
      if (event.heading != null) {
        setState(() {
          _currentHeading = event.heading!;
        });
        if (_isNavigating) {
          _mapController.rotate(_currentHeading);
        }
      }
    });
  }

  Color _colorFromHex(String hexColor) {
    hexColor = hexColor.toUpperCase().replaceAll("#", "");
    if (hexColor.length == 6) {
      hexColor = "FF" + hexColor;
    }
    return Color(int.parse(hexColor, radix: 16));
  }

  Future<void> _initializeRoute() async {
    try {
      // Fetch Route
      final routeData = await _navService.getPollutionRoute(
        startLat: widget.startPoint.latitude,
        startLng: widget.startPoint.longitude,
        endLat: widget.endPoint.latitude,
        endLng: widget.endPoint.longitude,
      );

      if (routeData != null) {
        final segments = routeData['segments'] as List<dynamic>;
        final summary = routeData['summary'] as Map<String, dynamic>;

        List<Polyline> newPolylines = [];
        for (var segment in segments) {
          final colorHex = segment['aqi']['color'] as String;
          final coords = segment['coordinates'] as List<dynamic>;
          List<LatLng> points = coords.map((c) => LatLng(c[1], c[0])).toList();
          newPolylines.add(
            Polyline(
              points: points,
              color: _colorFromHex(colorHex),
              strokeWidth: 6.0,
              strokeCap: StrokeCap.round,
              strokeJoin: StrokeJoin.round,
            )
          );
        }

        // Fetch Nav Steps
        setState(() {
          _loadingMessage = 'Getting navigation instructions...';
        });
        
        final navData = await _navService.getNavigationSteps(
          startLat: widget.startPoint.latitude,
          startLng: widget.startPoint.longitude,
          endLat: widget.endPoint.latitude,
          endLng: widget.endPoint.longitude,
        );

        if (navData != null) {
          final navSummary = navData['summary'] as Map<String, dynamic>;
          final stepsJson = navSummary['steps'] as List<dynamic>? ?? [];
          _navigationSteps = stepsJson.map((s) => RouteStep.fromJson(s)).toList();
        }

        setState(() {
          _polylines = newPolylines;
          _routeSummary = summary;
          _isLoading = false;
        });
        
        // Fit camera to bounds
        if (newPolylines.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 300), () {
            final bounds = LatLngBounds.fromPoints(
              newPolylines.expand((p) => p.points).toList(),
            );
            _mapController.fitCamera(
              CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50.0)),
            );
          });
        }
      } else {
        _handleError('Failed to calculate route.');
      }
    } catch (e) {
      _handleError('Error: $e');
    }
  }

  void _handleError(String message) {
    if (mounted) {
      setState(() {
         _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      context.pop();
    }
  }
  
  void _startNavigation() {
    setState(() {
      _isNavigating = true;
    });
    if (_userLocation != null) {
      _mapController.move(_userLocation!, 18.0);
      _mapController.rotate(_currentHeading);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Color(0xFF2DB87A)),
              const SizedBox(height: 24),
              Text(
                _loadingMessage,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
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
              PolylineLayer(
                polylines: _polylines,
              ),
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
                      width: 30,
                      height: 30,
                      child: const PulsingLocationMarker(),
                    ),
                ],
              ),
            ],
          ),
          
          // Back button area
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

          // Top Nav Banner (When Navigating)
          if (_isNavigating && _navigationSteps.isNotEmpty)
            Positioned(
              top: 50,
              left: 70,
              right: 16,
              child: _buildTopNavBanner(),
            ),

          // Bottom Sheet (Route Summary or Nav Control)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _isNavigating ? _buildNavControls() : _buildRouteSummary(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopNavBanner() {
    if (_currentStepIndex >= _navigationSteps.length) return const SizedBox();
    final step = _navigationSteps[_currentStepIndex];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
         color: const Color(0xFF2DB87A),
         borderRadius: BorderRadius.circular(12),
         boxShadow: [
           BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4))
         ],
      ),
      child: Row(
        children: [
          Icon(Icons.directions, color: Colors.white, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.instruction,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                 '${(step.distance / 1000).toStringAsFixed(1)} km',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
  
  Widget _buildNavControls() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(top: 20, left: 20, right: 20, bottom: 0),
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
                    Text(
                      '${(_routeSummary?['totalDurationMin'] ?? 0).round()} min',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                    Text(
                      '${(_routeSummary?['totalDistanceKm'] ?? 0).toStringAsFixed(1)} km',
                      style: const TextStyle(color: Colors.grey),
                    ),
                 ],
               ),
               ElevatedButton.icon(
                 onPressed: () {
                    setState(() {
                      _isNavigating = false;
                      _mapController.rotate(0);
                      // Refit bounds
                      if (_polylines.isNotEmpty) {
                        final bounds = LatLngBounds.fromPoints(
                          _polylines.expand((p) => p.points).toList(),
                        );
                        _mapController.fitCamera(
                          CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50.0)),
                        );
                      }
                    });
                 },
                 icon: const Icon(Icons.close),
                 label: const Text('Exit'),
                 style: ElevatedButton.styleFrom(
                   backgroundColor: Colors.red[50],
                   foregroundColor: Colors.red,
                   elevation: 0,
                 ),
               )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRouteSummary() {
    if (_routeSummary == null) return const SizedBox();
    
    final distKm = (_routeSummary!['totalDistanceKm'] ?? 0.0);
    final durMin = (_routeSummary!['totalDurationMin'] ?? 0.0);
    final avgAqi = _routeSummary!['overallAqi']?.round() ?? 0;
    
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))
        ]
      ),
      padding: const EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 0),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${durMin.round()} min',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2DB87A)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${distKm.toStringAsFixed(1)} km • Fastest Route',
                        style: TextStyle(color: Colors.grey[600], fontSize: 15),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text('Avg AQI', style: TextStyle(fontSize: 12, color: Colors.blue[800])),
                        Text('$avgAqi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue[800])),
                      ],
                    ),
                  )
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _startNavigation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2DB87A),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.navigation, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Start Navigation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  } }
