import 'package:dio/dio.dart';

class NavigationService {
  final Dio _dio = Dio();
  // Using 10.0.2.2 for Android emulator to access localhost backend, or localhost for web/desktop.
  // Ideally this comes from an env variable.
  final String _baseUrl = 'http://10.0.2.2:3000/api';

  Future<Map<String, dynamic>?> getPollutionRoute({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) async {
    try {
      final response = await _dio.post('$_baseUrl/route', data: {
        'start': {'lat': startLat, 'lng': startLng},
        'end': {'lat': endLat, 'lng': endLng},
      });

      if (response.statusCode == 200) {
        return response.data;
      }
      return null;
    } catch (e) {
      
      return null;
    }
  }
}
