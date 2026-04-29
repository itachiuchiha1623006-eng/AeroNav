import 'package:dio/dio.dart';
import '../config/app_config.dart';

class NavigationService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 60),
    headers: {
      'ngrok-skip-browser-warning': 'true',
    },
  ));

  final String _baseUrl = AppConfig.backendUrl;

  Future<Map<String, dynamic>?> getPollutionRoute({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) async {
    // Let all exceptions propagate so the caller can show a real error message
    // instead of silently returning null and leaving the user on a loading spinner.
    final response = await _dio.post('$_baseUrl/navigation/route', data: {
      'start': {'lat': startLat, 'lng': startLng},
      'end': {'lat': endLat, 'lng': endLng},
    });
    if (response.statusCode == 200) return response.data as Map<String, dynamic>;
    throw Exception('Server returned status ${response.statusCode}');
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
      if (response.statusCode == 200) return response.data as Map<String, dynamic>;
      return null;
    } catch (_) {
      // Steps are non-fatal — navigation still works without turn-by-turn
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
