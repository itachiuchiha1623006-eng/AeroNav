import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:location/location.dart' as loc;

import '../services/auth_service.dart';
import '../services/navigation_service.dart';

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
  double _currentHeading = 0.0;

  // Example coordinates for India (Delhi to Agra)
  LatLng _startPoint = const LatLng(28.6139, 77.2090); // New Delhi
  LatLng? _endPoint; // Unset until search
  String? _destinationName;

  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(_checkLocationAndCenter);
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkLocationAndCenter() async {
    loc.Location location = loc.Location();

    bool serviceEnabled;
    loc.PermissionStatus permissionGranted;
    loc.LocationData locationData;

    // 1. Auto-turn on Location Services
    serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) {
        return;
      }
    }

    // 2. Request App Permissions
    permissionGranted = await location.hasPermission();
    if (permissionGranted == loc.PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
      if (permissionGranted != loc.PermissionStatus.granted) {
        return;
      }
    }

    // 3. Get exact location and center map
    try {
      locationData = await location.getLocation();
      if (mounted) {
        setState(() {
          if (locationData.latitude != null && locationData.longitude != null) {
            _startPoint = LatLng(locationData.latitude!, locationData.longitude!);
            _mapController.move(_startPoint, 13.0);
          }
        });
      }
    } catch (e) {
      // Ignored
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
              strokeWidth: 5.0,
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
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load route: $e')),
        );
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
    loc.Location location = loc.Location();

    bool serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) return;
    }

    loc.PermissionStatus permissionGranted = await location.hasPermission();
    if (permissionGranted == loc.PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
      if (permissionGranted != loc.PermissionStatus.granted) return;
    }

    setState(() {
      _isNavigating = true;
      _isLoading = false;
    });

    _locationSubscription = location.onLocationChanged.listen((locData) {
      if (!mounted) return;
      if (locData.latitude != null && locData.longitude != null) {
        setState(() {
          _startPoint = LatLng(locData.latitude!, locData.longitude!);
          _currentHeading = locData.heading ?? 0.0;
        });
        
        _mapController.move(_startPoint, 18.0);
        _mapController.rotate(_currentHeading);
      }
    });
  }

  void _exitNavigationMode() {
    _locationSubscription?.cancel();
    setState(() {
      _isNavigating = false;
      _isExploring = true;
      _routeSummary = null;
      _destinationName = null;
      _polylines = [];
      _endPoint = null;
      _currentHeading = 0.0;
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
      
      setState(() {
        _endPoint = LatLng(result['latitude'], result['longitude']);
        _destinationName = result['name'];
      });
      _fetchRoute();
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
              const SizedBox(height: 16),
              _buildLocationCard(Icons.home, 'Home', '24 min • Eco-route'),
              const SizedBox(height: 12),
              _buildLocationCard(Icons.work, 'Work', '45 min • Traffic light'),
              const SizedBox(height: 12),
              _buildLocationCard(Icons.history, 'Recent', 'Central Park West'),
              const SizedBox(height: 24),
              _buildAQICard(),
              const SizedBox(height: 100), // padding for bottom nav
            ],
          ),
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF009E60),
        borderRadius: BorderRadius.circular(24)
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Air Quality is Great', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                SizedBox(height: 4),
                Text('Today is a perfect day for the scenic route.', style: TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF2DB87A),
              shape: BoxShape.circle
            ),
            child: const Column(
              children: [
                Text('AQI', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                Text('12', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
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

  Widget _buildNavigationHeader() {
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
            const Icon(Icons.turn_slight_right, color: Colors.white, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Follow the route', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text('Navigating to ${_destinationName ?? 'Destination'}', style: const TextStyle(fontSize: 13, color: Colors.white70)),
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
                      child: _isNavigating 
                        ? Transform.rotate(
                            angle: _currentHeading * (3.14159 / 180),
                            child: const Icon(Icons.navigation, color: Colors.blueAccent, size: 40),
                          )
                        : Container(
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
                          color: _isNavigating ? const Color(0xFF009E60) : Colors.black87,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3)
                        ),
                        child: Icon(Icons.flag, color: Colors.white, size: _isNavigating ? 16 : 20),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          
          if (_isExploring) _buildSearchBar(),
          
          if (_isExploring) _buildExploreSheet(),

          if (_isLoading)
            const Center(
              child: Card(
                color: Colors.black87,
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF2DB87A)),
                      SizedBox(height: 16),
                      Text('Calculating pollution route...', style: TextStyle(color: Colors.white)),
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
                      _endPoint = centerMap;
                      _destinationName = 'Map Selection';
                      _isPickingOnMap = false;
                    });
                    _fetchRoute();
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
