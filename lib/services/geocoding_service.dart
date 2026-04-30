import 'package:dio/dio.dart';

/// Regex that matches a 6-digit Indian PIN code anywhere in the query.
final _pincodeRegex = RegExp(r'\b([1-9][0-9]{5})\b');

class GeocodingService {
  final Dio _dio = Dio();

  // ─── Public entry point ──────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> searchPlaces(String query) async {
    if (query.trim().isEmpty) return [];

    // Strategy 1 – Photon with the full query (fast, good for known OSM places)
    final photonResults = await _photonSearch(query);
    if (photonResults.isNotEmpty) return photonResults;

    // Strategy 2 – Nominatim with full query
    final nomFull = await _nominatimSearch(query: query);
    if (nomFull.isNotEmpty) return nomFull;

    // Strategy 3 – If the query contains an Indian PIN code, try targeted
    // sub-searches that OSM *does* know (pincode area + locality name).
    final pinMatch = _pincodeRegex.firstMatch(query);
    if (pinMatch != null) {
      final pincode = pinMatch.group(1)!;

      // Build a simplified locality string by stripping the pincode and
      // typical noise words, then take the last meaningful token.
      final locality = _extractLocality(query, pincode);

      // 3a – locality + pincode (e.g. "Rahatani 411017")
      if (locality.isNotEmpty) {
        final r = await _nominatimSearch(query: '$locality $pincode');
        if (r.isNotEmpty) return r;
      }

      // 3b – structured: just postalcode
      final r2 = await _nominatimStructuredSearch(pincode: pincode, locality: locality);
      if (r2.isNotEmpty) {
        // Prepend the user's original query label so the pin shows the right
        // name even though the coordinates are the area centroid.
        return r2.map((p) {
          final prettyName = _buildPrettyName(query, p['name'] as String);
          return {...p, 'name': prettyName};
        }).toList();
      }

      // 3c – bare pincode fallback
      final r3 = await _nominatimStructuredSearch(pincode: pincode, locality: '');
      if (r3.isNotEmpty) {
        return r3.map((p) {
          final prettyName = _buildPrettyName(query, p['name'] as String);
          return {...p, 'name': prettyName};
        }).toList();
      }
    }

    // Strategy 4 – progressively trim the query from the front (drop first segment)
    final segments = query.split(RegExp(r'[,،]+'));
    for (int i = 1; i < segments.length; i++) {
      final trimmed = segments.skip(i).join(', ').trim();
      if (trimmed.length < 4) continue;
      final r = await _nominatimSearch(query: trimmed);
      if (r.isNotEmpty) return r;
    }

    return [];
  }

  // ─── Photon (komoot) ─────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _photonSearch(String query) async {
    try {
      final response = await _dio.get(
        'https://photon.komoot.io/api/',
        options: Options(headers: {
          'User-Agent': 'AeroNavApp/1.0 (contact@aeronav.app)',
          'Accept-Language': 'en',
        }),
        queryParameters: {
          'q': query,
          'limit': 20,
          'bbox': '68.1,6.5,97.4,35.5',
        },
      );

      if (response.statusCode != 200) return [];

      final List features = response.data['features'] ?? [];
      final results = features
          .map<Map<String, dynamic>?>((feature) {
            final props = feature['properties'];
            final coords = feature['geometry']['coordinates'];
            final display = _buildPhotonDisplay(props);
            if (display.isEmpty) return null;
            return {
              'name': display,
              'latitude': coords[1].toDouble(),
              'longitude': coords[0].toDouble(),
              'type': props['type'] ?? props['osm_value'] ?? 'place',
              '_rank': _photonRank(
                  props['type']?.toString() ?? props['osm_value']?.toString() ?? ''),
            };
          })
          .whereType<Map<String, dynamic>>()
          .toList();

      results.sort((a, b) => (a['_rank'] as int).compareTo(b['_rank'] as int));
      for (final r in results) { r.remove('_rank'); }
      return results;
    } catch (_) {
      return [];
    }
  }

  String _buildPhotonDisplay(Map props) {
    final parts = <String>[];
    if (props['name'] != null) parts.add(props['name'].toString());

    final houseNo = props['housenumber']?.toString();
    final street = props['street']?.toString();
    if (houseNo != null && street != null) {
      parts.add('$houseNo $street');
    } else if (street != null) {
      parts.add(street);
    } else if (houseNo != null) {
      parts.add(houseNo);
    }

    final locality = props['locality']?.toString() ??
        props['suburb']?.toString() ??
        props['neighbourhood']?.toString();
    if (locality != null) parts.add(locality);

    final district =
        props['district']?.toString() ?? props['county']?.toString();
    if (district != null) parts.add(district);
    if (props['city'] != null) parts.add(props['city'].toString());
    if (props['state'] != null) parts.add(props['state'].toString());
    if (props['postcode'] != null) parts.add(props['postcode'].toString());

    // Deduplicate consecutive identical segments
    final unique = <String>[];
    for (final c in parts) {
      if (unique.isEmpty || unique.last != c) { unique.add(c); }
    }
    return unique.join(', ');
  }

  int _photonRank(String type) {
    const r = {
      'house': 0, 'building': 1, 'street': 2,
      'locality': 3, 'suburb': 3, 'neighbourhood': 3,
      'district': 4, 'quarter': 4, 'city': 5,
      'town': 5, 'village': 5, 'county': 6,
      'state': 7, 'country': 8,
    };
    return r[type] ?? 5;
  }

  // ─── Nominatim free-text search ─────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _nominatimSearch({
    required String query,
  }) async {
    try {
      final response = await _dio.get(
        'https://nominatim.openstreetmap.org/search',
        options: Options(
            headers: {'User-Agent': 'AeroNavApp/1.0 (contact@aeronav.app)'}),
        queryParameters: {
          'q': query,
          'format': 'json',
          'countrycodes': 'in',
          'limit': 10,
          'addressdetails': 1,
        },
      );
      if (response.statusCode == 200) {
        return _parseNominatimList(response.data as List);
      }
    } catch (_) {}
    return [];
  }

  // ─── Nominatim structured search (pincode + optional locality) ──────────

  Future<List<Map<String, dynamic>>> _nominatimStructuredSearch({
    required String pincode,
    required String locality,
  }) async {
    try {
      final params = <String, dynamic>{
        'format': 'json',
        'countrycodes': 'in',
        'limit': 5,
        'addressdetails': 1,
        'postalcode': pincode,
      };
      if (locality.isNotEmpty) params['city'] = locality;

      final response = await _dio.get(
        'https://nominatim.openstreetmap.org/search',
        options: Options(
            headers: {'User-Agent': 'AeroNavApp/1.0 (contact@aeronav.app)'}),
        queryParameters: params,
      );
      if (response.statusCode == 200) {
        return _parseNominatimList(response.data as List);
      }
    } catch (_) {}
    return [];
  }

  List<Map<String, dynamic>> _parseNominatimList(List raw) {
    return raw
        .map<Map<String, dynamic>?>((place) {
          final addr = place['address'] as Map<String, dynamic>? ?? {};
          final parts = <String>[];

          final houseNo = addr['house_number']?.toString();
          final road = addr['road']?.toString();
          if (houseNo != null && road != null) {
            parts.add('$houseNo $road');
          } else if (road != null) {
            parts.add(road);
          }

          final neighbourhood = addr['neighbourhood']?.toString() ??
              addr['suburb']?.toString() ??
              addr['locality']?.toString() ??
              addr['hamlet']?.toString();
          if (neighbourhood != null) parts.add(neighbourhood);

          final city = addr['city']?.toString() ??
              addr['town']?.toString() ??
              addr['village']?.toString() ??
              addr['municipality']?.toString();
          if (city != null) parts.add(city);

          final district = addr['district']?.toString() ??
              addr['county']?.toString() ??
              addr['state_district']?.toString();
          if (district != null) parts.add(district);

          if (addr['state'] != null) parts.add(addr['state'].toString());
          if (addr['postcode'] != null) parts.add(addr['postcode'].toString());

          if (parts.isEmpty) {
            final fallback = place['display_name']?.toString();
            if (fallback == null) return null;
            parts.add(fallback);
          }

          return {
            'name': parts.join(', '),
            'latitude': double.parse(place['lat'].toString()),
            'longitude': double.parse(place['lon'].toString()),
            'type': place['type'] ?? 'place',
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }


  String _extractLocality(String query, String pincode) {
    final cleaned = query
        .replaceAll(pincode, '')
        .replaceAll(RegExp(r'no\s*\d+', caseSensitive: false), '')
        .replaceAll(RegExp(r'\bno\b', caseSensitive: false), '');

    final tokens = cleaned
        .split(RegExp(r'[,، ]+'))
        .map((t) => t.trim())
        .where((t) => t.length >= 4)
        .toList();

    return tokens.isNotEmpty ? tokens.last : '';
  }

  String _buildPrettyName(String originalQuery, String areaName) {

    final first = originalQuery
        .split(RegExp(r'[,،]+'))
        .first
        .trim();
    if (first.isEmpty || areaName.startsWith(first)) return areaName;
    return '$first · $areaName';
  }
}
