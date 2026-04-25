import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:location/location.dart' as loc;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_compass/flutter_compass.dart';

import '../services/auth_service.dart';
import '../services/navigation_service.dart';
import '../widgets/pulsing_location_marker.dart';
import '../models/route_step.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final MapController _mapController = MapController();
  final NavigationService _navService = NavigationService();

  List<Polyline> _polylines = [];
  bool _isLoading = false;
  Map<String, dynamic>? _routeSummary;

  bool _isExploring = true;
  bool _isPickingOnMap = false;
  bool _isNavigating = false;
  StreamSubscription<loc.LocationData>? _locationSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;
  double _currentHeading = 0.0;

  // Example coordinates for India (Delhi to Agra)
  LatLng _startPoint = const LatLng(28.6139, 77.2090); // New Delhi
  LatLng? _userLocation;
  LatLng? _endPoint; // Unset until search
  String? _destinationName;

  List<RouteStep> _navigationSteps = [];
  int _currentStepIndex = 0;

  int? _liveAqi;
  String? _liveAqiCategory;
  String? _liveAqiColorHex;

  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(_checkLocationAndCenter);
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _compassSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkLocationAndCenter() async {
    loc.Location location = loc.Location();

    bool serviceEnabled;

    // 1. Auto-turn on Location Services
    serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) {
        return;
      }
    }

    // 2. Request App Permissions using permission_handler
    final pStatus = await Permission.locationWhenInUse.status;
    if (pStatus.isDenied) {
      final result = await Permission.locationWhenInUse.request();
      if (!result.isGranted) return;
    } else if (pStatus.isPermanentlyDenied) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Location Required'),
            content: const Text('AeroNav needs your location to provide pollution-aware routing. Please open settings to grant permission.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  openAppSettings();
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
      }
      return;
    }

    // 3. Track location and center map
    _locationSubscription ??= location.onLocationChanged.listen((locData) {
      if (!mounted) return;
      if (locData.latitude != null && locData.longitude != null) {
        setState(() {
          _userLocation = LatLng(locData.latitude!, locData.longitude!);
          if (!_isNavigating && _endPoint == null) {
            _startPoint = _userLocation!;
          }
        });
        
        if (_liveAqi == null) {
          _fetchLiveAqi();
        }

        if (_isNavigating) {
          _mapController.move(_userLocation!, 18.0);
          if (_currentHeading == 0.0 && locData.heading != null) {
             _mapController.rotate(locData.heading!);
          }
        }
      }
    });

    _compassSubscription ??= FlutterCompass.events?.listen((event) {
      if (!mounted) return;
      if (event.heading != null) {
        setState(() {
          _currentHeading = event.heading!;
        });
        if (_isNavigating) {
          _mapController.rotate(_currentHeading);
          if (_isNavigating && _userLocation != null &&
              _navigationSteps.isNotEmpty &&
              _currentStepIndex < _navigationSteps.length) {
            final Distance distanceLib = const Distance();
            final int meters = distanceLib.as(LengthUnit.Meter, _userLocation!,
                _navigationSteps[_currentStepIndex].point).toInt();

            if (meters < 20 &&
                _currentStepIndex < _navigationSteps.length - 1) {
              setState(() {
                _currentStepIndex++;
              });
            }
          }
        }
      }});

    try {
      final initialLoc = await location.getLocation();
      if (mounted && initialLoc.latitude != null && initialLoc.longitude != null) {
        setState(() {
          _userLocation = LatLng(initialLoc.latitude!, initialLoc.longitude!);
          _startPoint = _userLocation!;
        });
        _mapController.move(_userLocation!, 13.0);
        _fetchLiveAqi();
      }
    } catch (e) {
      // Ignored
    }
  }

  Future<void> _fetchLiveAqi() async {
    if (_userLocation == null) return;
    
    try {
      final data = await _navService.getPointAQI(
        lat: _userLocation!.latitude,
        lng: _userLocation!.longitude,
      );

      if (data != null && mounted) {
        setState(() {
          _liveAqi = data['aqi'];
          _liveAqiCategory = data['category'];
          _liveAqiColorHex = data['color'];
        });
      } else if (mounted) {
        // Log to screen if the data fetch failed
        ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Could not fetch AQI. Check API backend or network.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('AQI Error: $e')),
        );
      }
    }
  }

  Color _colorFromHex(String hexColor) {
    hexColor = hexColor.replaceAll('#', '');
    if (hexColor.length == 6) {
      hexColor = 'FF$hexColor';
    }
    return Color(int.parse(hexColor, radix: 16));
  }

  Future<void> _fetchRoute() async {
    if (_endPoint == null) return;

    setState(() {
      _isLoading = true;
      _isExploring = false;
    });

    try {
      final routeData = await _navService.getPollutionRoute(
        startLat: _startPoint.latitude,
        startLng: _startPoint.longitude,
        endLat: _endPoint!.latitude,
        endLng: _endPoint!.longitude,
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

        setState(() {
          _polylines = newPolylines;
          _routeSummary = summary;
        });

        if (newPolylines.isNotEmpty) {
          final bounds = LatLngBounds.fromPoints(
            newPolylines.expand((p) => p.points).toList(),
          );
          _mapController.fitCamera(
            CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50.0)),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to load route. Please check your connection or IP configuration.')),
          );
          setState(() {
            _isExploring = true;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load route: $e')),
        );
        setState(() {
          _isExploring = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _enterNavigationMode() async {
    setState(() {
      _isLoading = true;
    });

    if (_userLocation != null && _endPoint != null) {
      final navData = await _navService.getNavigationSteps(
        startLat: _userLocation!.latitude,
        startLng: _userLocation!.longitude,
        endLat: _endPoint!.latitude,
        endLng: _endPoint!.longitude,
      );

      if (navData != null) {
        final summary = navData['summary'] as Map<String, dynamic>;
        final stepsJson = summary['steps'] as List<dynamic>? ?? [];
        _navigationSteps = stepsJson.map((s) => RouteStep.fromJson(s)).toList();
        _currentStepIndex = 0;
      }
    }

    setState(() {
      _isNavigating = true;
      _isLoading = false;
    });

    if (_userLocation != null) {
      _mapController.move(_userLocation!, 18.0);
      _mapController.rotate(_currentHeading);
    }
  }

  void _exitNavigationMode() {
    setState(() {
      _isNavigating = false;
      _isExploring = true;
      _routeSummary = null;
      _destinationName = null;
      _polylines = [];
      _endPoint = null;
      _navigationSteps = [];
      _currentStepIndex = 0;
    });
    _mapController.rotate(0.0);
    _mapController.move(_startPoint, 13.0);
  }

  Future<void> _openSearch() async {
    final result = await context.push('/search');
    if (result != null && result is Map<String, dynamic>) {
      if (result['action'] == 'pick_on_map') {
        setState(() {
          _isPickingOnMap = true;
          _isExploring = false;
          _mapController.move(_startPoint, 15.0);
        });
        return;
      }
      
      final endPt = LatLng(result['latitude'], result['longitude']);
      context.push('/routes', extra: {
        'startPoint': _startPoint,
        'endPoint': endPt,
        'destinationName': result['name'],
      });
    }
  }

  Widget _buildSearchBar() {
    return Positioned(
      top: 50,
      left: 16,
      right: 16,
      child: Column(
        
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.search, color: Color(0xFF2DB87A)),
                  SizedBox(width: 8),
                  Text('AeroNav', style: TextStyle(color: Color(0xFF2DB87A), fontSize: 20, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
                ],
              ),
              CircleAvatar(
                radius: 16,
                backgroundImage: NetworkImage('https://i.pravatar.cc/100'),
              )
            ],
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _openSearch,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))
                ]
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: Color(0xFF2DB87A)),
                  const SizedBox(width: 12),
                  Text('Where do you want to go', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                  const Spacer(),
                  const Icon(Icons.mic, color: Colors.grey),
                ],
              ),
            ),
          )
        ],
      )
    );
  }

  Widget _buildExploreSheet() {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.1,
      maxChildSize: 0.55,
      builder: (context, scrollController) {
        // StatefulBuilder ensures this subtree rebuilds when parent calls setState
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                boxShadow: [
                  BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))
                ]
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 16),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2)
                      ),
                    ),
                  ),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Explore nearby', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
                      Text('View all', style: TextStyle(color: Color(0xFF2DB87A), fontWeight: FontWeight.w600)),
                    ],
                  ),

                  const SizedBox(height: 24),
                  _buildAQICard(),
                  const SizedBox(height: 100), // padding for bottom nav
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLocationCard(IconData icon, String title, String subtitle) {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Setup in Settings coming soon.')));
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F9F4),
          borderRadius: BorderRadius.circular(24)
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFFE8F5E9),
              child: Icon(icon, color: const Color(0xFF2DB87A)),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildAQICard() {
    if (_liveAqi == null) {
      // Show a loading placeholder while AQI is being fetched
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F3F1),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Air Quality', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold, fontSize: 18)),
                  SizedBox(height: 4),
                  Text('Fetching live reading...', style: TextStyle(color: Colors.black38, fontSize: 14)),
                ],
              ),
            ),
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF2DB87A)),
            ),
          ],
        ),
      );
    }

    final Color bgColor = _colorFromHex(_liveAqiColorHex ?? '#009E60');
    final bool isDark = bgColor.computeLuminance() < 0.5;
    final Color textColor = isDark ? Colors.white : Colors.black87;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(24)
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Air Quality: ${_liveAqiCategory ?? 'Unknown'}', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 4),
                Text('Current live reading at your location.', style: TextStyle(color: textColor.withValues(alpha: 0.8), fontSize: 14)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              shape: BoxShape.circle
            ),
            child: Column(
              children: [
                Text('AQI', style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.bold)),
                Text('$_liveAqi', style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
          )
        ],
      )
    );
  }

  Widget _buildDestinationHeader() {
    return Positioned(
      top: 60,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9F8),
          borderRadius: BorderRadius.circular(32),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))
          ]
        ),
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle)),
                Container(width: 1, height: 20, color: Colors.grey[300]),
                const Icon(Icons.location_on, color: Color(0xFF009E60), size: 16),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('DESTINATION', style: TextStyle(color: Colors.black54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  const SizedBox(height: 2),
                  Text(_destinationName ?? 'Selected on Map', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            GestureDetector(
              onTap: () {
                setState(() {
                  _isExploring = true;
                  _routeSummary = null;
                  _destinationName = null;
                  _endPoint = null;
                  _polylines = [];
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8EFEA),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('EDIT', style: TextStyle(color: Color(0xFF4A5550), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.0)),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildRouteCards() {
    return Positioned(
      bottom: 100, // Above bottom nav
      left: 16,
      right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Primary Route (Cleanest)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(0, 8))
              ]
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2F0EA),
                            borderRadius: BorderRadius.circular(12)
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.eco, color: Color(0xFF009E60), size: 12),
                              SizedBox(width: 4),
                              Text('RECOMMENDED', style: TextStyle(color: Color(0xFF009E60), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text('Cleanest Route', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(text: '${_routeSummary!['totalDurationMin']} ', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF009E60))),
                              const TextSpan(text: 'min', style: TextStyle(fontSize: 14, color: Colors.black54)),
                            ]
                          )
                        ),
                        Text('${_routeSummary!['totalDistanceKm']} km', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                    )
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F9F4),
                    borderRadius: BorderRadius.circular(24)
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF8CD4AB), width: 1.5)
                        ),
                        child: const Icon(Icons.air, color: Color(0xFF009E60)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_routeSummary!['overallCategory'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                            const SizedBox(height: 2),
                            Text('AQI: ${_routeSummary!['overallAqi']} • Minimal exposure', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                          ],
                        )
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF009E60),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                      elevation: 0,
                    ),
                    onPressed: () {
                      _enterNavigationMode();
                    },
                    child: const Text('START NAVIGATION', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  ),
                )
              ],
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Secondary Route (Balanced)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F3F1),
              borderRadius: BorderRadius.circular(32),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Balanced Route', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                        SizedBox(height: 4),
                        Text('Mixed traffic area', style: TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(text: '${(_routeSummary!['totalDurationMin'] * 0.8).round()} ', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)),
                              const TextSpan(text: 'min', style: TextStyle(fontSize: 12, color: Colors.black54)),
                            ]
                          )
                        ),
                        Text('${(_routeSummary!['totalDistanceKm'] * 0.9).toStringAsFixed(1)} km', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                      ],
                    )
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                   padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                   decoration: BoxDecoration(
                     color: const Color(0xFFE6ECE8),
                     borderRadius: BorderRadius.circular(20)
                   ),
                   child: Row(
                     children: [
                       const Icon(Icons.cloud, color: Colors.blue, size: 20),
                       const SizedBox(width: 12),
                       Expanded(
                         child: Column(
                           crossAxisAlignment: CrossAxisAlignment.start,
                           children: [
                             Text('Moderate AQI: ${(_routeSummary!['overallAqi'] * 1.5).round()}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
                             const Text('Slightly higher exposure', style: TextStyle(fontSize: 10, color: Colors.black54)),
                           ],
                         )
                       )
                     ],
                   )
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.black26),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32))
                    ),
                    onPressed: () {},
                    child: const Text('SELECT', style: TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  )
                )
              ],
            )
          )
        ],
      ),
    );
  }

  IconData _getManeuverIcon(String type, String modifier) {
    if (type == 'arrive') return Icons.flag;
    if (type == 'depart') return Icons.straight;
    if (type == 'turn') {
      if (modifier.contains('left')) return Icons.turn_left;
      if (modifier.contains('right')) return Icons.turn_right;
    }
    return Icons.straight;
  }

  Widget _buildNavigationHeader() {
    RouteStep? currentStep;
    int distanceToNext = 0;
    
    if (_navigationSteps.isNotEmpty && _currentStepIndex < _navigationSteps.length) {
      currentStep = _navigationSteps[_currentStepIndex];
      if (_userLocation != null) {
        final Distance distanceLib = const Distance();
        distanceToNext = distanceLib.as(LengthUnit.Meter, _userLocation!, currentStep.point).toInt();
      }
    }

    return Positioned(
      top: 50,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF009E60),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 15, offset: Offset(0, 8))
          ]
        ),
        child: Row(
          children: [
            Icon(
              currentStep != null ? _getManeuverIcon(currentStep.maneuverType, currentStep.modifier) : Icons.navigation, 
              color: Colors.white, size: 32
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    currentStep?.instruction ?? 'Follow the route', 
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)
                  ),
                  const SizedBox(height: 2),
                  Text(currentStep != null ? 'In $distanceToNext meters' : 'Navigating to ${_destinationName ?? 'Destination'}', style: const TextStyle(fontSize: 13, color: Colors.white70)),
                ],
              ),
            ),
            GestureDetector(
              onTap: _exitNavigationMode,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.white24,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 20),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildAQILegend() {
    return Positioned(
      top: 140,
      right: 16,
      child: Container(
        width: 14,
        height: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF7E0023), // Hazardous
              Color(0xFF8F3F97), // Very Unhealthy
              Color(0xFFFF0000), // Unhealthy
              Color(0xFFFF7E00), // Unhealthy for Sensitive Groups
              Color(0xFFFFFF00), // Moderate
              Color(0xFF00E400), // Good
            ],
            stops: [0.1, 0.3, 0.5, 0.7, 0.9, 1.0],
          ),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(2, 2))
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _startPoint,
              initialZoom: 13.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.aeronav.app',
              ),
              if (!_isExploring)
                PolylineLayer(
                  polylines: _polylines,
                ),
              if (!_isExploring && _endPoint != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _startPoint,
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blueAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3)
                        ),
                      ),
                    ),
                    Marker(
                      point: _endPoint!,
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3)
                        ),
                        child: const Icon(Icons.flag, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              if (_userLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _userLocation!,
                      width: 40,
                      height: 40,
                      child: _isNavigating 
                        ? Transform.rotate(
                            angle: _currentHeading * (3.14159 / 180),
                            child: const Icon(Icons.navigation, color: Colors.blueAccent, size: 40),
                          )
                        : const PulsingLocationMarker()
                    ),
                  ],
                ),
            ],
          ),
          
          if (_isExploring) _buildSearchBar(),
          
          if (_isExploring && _polylines.isNotEmpty) _buildAQILegend(),
          
          if (_isExploring) _buildExploreSheet(),

          if (_isLoading)
            const Center(
              child: Card(
                color: Colors.black87,
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF2DB87A)),
                      SizedBox(height: 16),
                      Text('Calculating pollution route...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      SizedBox(height: 6),
                      Text('This may take up to a minute.\nFetching live AQI & weather data.', style: TextStyle(color: Colors.white60, fontSize: 12), textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            ),
            
            
          if (!_isExploring && _routeSummary != null && !_isLoading && !_isPickingOnMap && !_isNavigating)
            _buildDestinationHeader(),

          if (!_isExploring && _routeSummary != null && !_isLoading && !_isPickingOnMap && !_isNavigating)
            _buildRouteCards(),
            
          if (_isNavigating)
            _buildNavigationHeader(),

          if (_isPickingOnMap)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 40.0), // Adjust to make tip point to exact center
                child: Icon(Icons.location_on, color: Colors.blueAccent, size: 48),
              ),
            ),
            
          if (_isPickingOnMap)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: EdgeInsets.only(
                  left: 24, 
                  right: 24, 
                  bottom: MediaQuery.of(context).padding.bottom + 24
                ),
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2DB87A),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    final centerMap = _mapController.camera.center;
                    setState(() {
                      _isPickingOnMap = false;
                      _isExploring = true;
                    });
                    context.push('/routes', extra: {
                      'startPoint': _startPoint,
                      'endPoint': centerMap,
                      'destinationName': 'Map Selection',
                    });
                  },
                  child: const Text('Confirm Destination', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ),


          if (!_isExploring && !_isNavigating)
             Positioned(
               top: 50,
               left: 16,
               child: CircleAvatar(
                 backgroundColor: Colors.white,
                 child: IconButton(
                   icon: const Icon(Icons.arrow_back, color: Colors.black87),
                   onPressed: () {
                     setState(() {
                       _isExploring = true;
                       _isPickingOnMap = false;
                       _routeSummary = null;
                       _destinationName = null;
                       _polylines = [];
                       _endPoint = null;
                     });
                   },
                 ),
               ),
             ),
             
          if (_isExploring)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 16, left: 16, right: 16),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(40),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))
                  ]
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildNavItem(0, Icons.explore, 'EXPLORE'),
                    _buildNavItem(1, Icons.directions_walk, 'ROUTES'),
                    _buildNavItem(2, Icons.bookmark, 'SAVED'),
                    _buildNavItem(3, Icons.person, 'PROFILE'),
                  ],
                ),
              ),
            )
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    bool isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () {
        if (index == 3) {
          ref.read(authServiceProvider).signOut();
          context.go('/auth/login');
        } else {
          setState(() {
            _currentIndex = index;
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF009E60) : Colors.transparent,
          borderRadius: BorderRadius.circular(24)
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? Colors.white : Colors.grey, size: 24),
            if (isSelected) const SizedBox(height: 2),
            if (isSelected) Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            if (!isSelected) Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
