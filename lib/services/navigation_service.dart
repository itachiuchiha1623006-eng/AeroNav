import 'package:dio/dio.dart';

class NavigationService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
  ));
  // Using 10.0.2.2 for Android emulator to access localhost backend, or localhost for web/desktop.
  // Ideally this comes from an env variable.
  final String _baseUrl = 'http://192.168.1.43:3000/api';

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

  Future<Map<String, dynamic>?> getNavigationSteps({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) async {
    try {
      final response = await _dio.post('$_baseUrl/navigation/steps', data: {
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

  Future<Map<String, dynamic>?> getPointAQI({
    required double lat,
    required double lng,
  }) async {
    try {
      final response = await _dio.get('$_baseUrl/aqi/point', queryParameters: {
        'lat': lat,
        'lng': lng,
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
