import 'package:dio/dio.dart';

class GeocodingService {
  final Dio _dio = Dio();

  Future<List<Map<String, dynamic>>> searchPlaces(String query) async {
    if (query.trim().isEmpty) return [];

    try {
      final response = await _dio.get(
        'https://photon.komoot.io/api/',
        options: Options(
          headers: {
            'User-Agent': 'AeroNavApp/1.0 (contact@aeronav.app)',
            'Accept-Language': 'en'
          },
        ),
        queryParameters: {
          'q': query,
          'limit': 15, // Ask for more to filter later if needed
          'bbox': '68.1,6.5,97.4,35.5' // Bounding box for India
        },
      );

      if (response.statusCode == 200) {
        final List features = response.data['features'] ?? [];
        
        return features.map<Map<String, dynamic>>((feature) {
          final props = feature['properties'];
          final coords = feature['geometry']['coordinates'];
  
          final components = <String>[];
          if (props['name'] != null) components.add(props['name'].toString());
          if (props['street'] != null) components.add(props['street'].toString());
          if (props['district'] != null) components.add(props['district'].toString());
          if (props['city'] != null) components.add(props['city'].toString());
          if (props['state'] != null) components.add(props['state'].toString());
          
          final displayName = components.toSet().join(', '); // toSet makes it unique

          return {
            'name': displayName.isNotEmpty ? displayName : 'Unknown Location',
            'latitude': coords[1].toDouble(),
            'longitude': coords[0].toDouble(),
            'type': props['type'] ?? props['osm_value'] ?? 'place',
          };
        }).where((place) => place['name'] != 'Unknown Location').toList();
      }
      return [];
    } catch (e) {
      if (e is DioException) {
        // Fallback to nominatim if photon returns a 403 or blocks us again
        return _fallbackSearch(query);
      }
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fallbackSearch(String query) async {
    try {
      final response = await _dio.get(
        'https://nominatim.openstreetmap.org/search',
        options: Options(headers: {'User-Agent': 'AeroNavApp/1.0 (contact@aeronav.app)'}),
        queryParameters: {'q': query, 'format': 'json', 'countrycodes': 'in', 'limit': 8},
      );
      if (response.statusCode == 200) {
        return (response.data as List).map((place) {
          return {
            'name': place['display_name'] ?? 'Unknown Location',
            'latitude': double.parse(place['lat'].toString()),
            'longitude': double.parse(place['lon'].toString()),
            'type': place['type'] ?? 'place',
          };
        }).toList();
      }
    } catch (_) {}
    return [];
  }
}
