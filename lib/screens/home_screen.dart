import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';
import '../services/navigation_service.dart';
import 'package:go_router/go_router.dart';

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

  // Example coordinates for India (Delhi to Agra)
  final LatLng _startPoint = const LatLng(28.6139, 77.2090); // New Delhi
  final LatLng _endPoint = const LatLng(27.1767, 78.0081); // Agra

  @override
  void initState() {
    super.initState();
    // Delay fetching slightly to allow map to init
    Future.delayed(const Duration(milliseconds: 500), _fetchRoute);
  }

  Color _colorFromHex(String hexColor) {
    hexColor = hexColor.replaceAll('#', '');
    if (hexColor.length == 6) {
      hexColor = 'FF$hexColor'; // Add opacity
    }
    return Color(int.parse(hexColor, radix: 16));
  }

  Future<void> _fetchRoute() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final routeData = await _navService.getPollutionRoute(
        startLat: _startPoint.latitude,
        startLng: _startPoint.longitude,
        endLat: _endPoint.latitude,
        endLng: _endPoint.longitude,
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

        // Fit map bounds to show the whole route
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load route: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('AeroNav'),
        backgroundColor: Colors.black54,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchRoute,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authServiceProvider).signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _startPoint,
              initialZoom: 8.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.aeronav.app',
              ),
              PolylineLayer(
                polylines: _polylines,
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _startPoint,
                    width: 40,
                    height: 40,
                    child: const Icon(Icons.location_on, color: Colors.blue, size: 40),
                  ),
                  Marker(
                    point: _endPoint,
                    width: 40,
                    height: 40,
                    child: const Icon(Icons.flag, color: Colors.white, size: 40),
                  ),
                ],
              ),
            ],
          ),
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
          if (_routeSummary != null && !_isLoading)
            Positioned(
              bottom: 24,
              left: 24,
              right: 24,
              child: Card(
                color: const Color(0xFF1A1A1A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Overall Route AQI',
                            style: TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _colorFromHex(_routeSummary!['overallColor']),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _routeSummary!['overallCategory'],
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                            ),
                          )
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Max AQI: ${_routeSummary!['overallAqi']}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('${_routeSummary!['totalDistanceKm']} km', style: const TextStyle(color: Colors.white)),
                              Text('${_routeSummary!['totalDurationMin']} mins', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          )
                        ],
                      )
                    ],
                  ),
                ),
              ),
            )
        ],
      ),
    );
  }
}
