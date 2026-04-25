import 'package:dio/dio.dart';

class NavigationService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 180), // OSRM public demo can be slow (up to 2min)
  ));
  // 10.0.2.2 = Android emulator loopback to host machine
  // 192.168.1.43 = Physical device on the same WiFi as the dev machine
  // For USB: run `adb reverse tcp:3000 tcp:3000` then use http://127.0.0.1:3000/api
  final String _baseUrl = 'http://192.168.1.43:3000/api'; // ← physical device (LAN)

  Future<Map<String, dynamic>?> getPollutionRoute({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) async {
    try {
      final response = await _dio.post('$_baseUrl/navigation/route', data: {
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
    } on DioException catch (e) {
      // Rethrow with useful context so the caller can display the real error
      throw Exception('AQI fetch failed [${e.response?.statusCode ?? 'no response'}]: ${e.message}');
    } catch (e) {
      rethrow;
    }
  }
}
