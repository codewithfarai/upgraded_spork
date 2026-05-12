import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

class GooglePlacesService {
  GooglePlacesService(this._dio);
  final Dio _dio;

  static const String _apiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');
  static const String _placesBase = 'https://places.googleapis.com/v1/places';
  static const String _geocodeUrl = 'https://maps.googleapis.com/maps/api/geocode/json';

  Options get _headers => Options(headers: {'X-Goog-Api-Key': _apiKey});

  /// Autocomplete using Places API (New) — POST, billed per session not per request.
  Future<List<Map<String, dynamic>>> getAutocompletePredictions(
    String query, {
    String? sessionToken,
  }) async {
    if (query.isEmpty) return [];
    if (_apiKey.isEmpty) {
      debugPrint('[Places] WARNING: GOOGLE_MAPS_API_KEY is empty.');
      return [];
    }

    try {
      final response = await _dio.post(
        '$_placesBase:autocomplete',
        data: {
          'input': query,
          if (sessionToken != null) 'sessionToken': sessionToken,
          'includedRegionCodes': ['zw', 'gb'],
          'locationBias': {
            'circle': {
              'center': {'latitude': -17.8248, 'longitude': 31.0530},
              'radius': 50000.0,
            },
          },
        },
        options: _headers,
      );

      if (response.statusCode == 200) {
        final suggestions = response.data['suggestions'] as List? ?? [];
        return suggestions
            .where((s) => s['placePrediction'] != null)
            .map((s) => Map<String, dynamic>.from(s['placePrediction'] as Map))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('[Places] autocomplete error: $e');
      return [];
    }
  }

  /// Fetch coordinates for a place — closes the autocomplete session token,
  /// triggering the flat $0.005 Basic session billing instead of per-request.
  Future<Map<String, dynamic>?> getPlaceCoordinates(
    String placeId, {
    String? sessionToken,
  }) async {
    try {
      final response = await _dio.get(
        '$_placesBase/$placeId',
        options: Options(headers: {
          'X-Goog-Api-Key': _apiKey,
          'X-Goog-FieldMask': 'location,formattedAddress,displayName',
          if (sessionToken != null) 'X-Goog-SessionToken': sessionToken,
        }),
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final loc = data['location'] as Map<String, dynamic>?;
        if (loc != null) {
          return {
            'lat': loc['latitude'],
            'lng': loc['longitude'],
            'formatted_address': data['formattedAddress'] ?? '',
          };
        }
      }
      return null;
    } catch (e) {
      debugPrint('[Places] place details error: $e');
      return null;
    }
  }

  /// Reverse geocode — uses Geocoding API (same price, simpler for lat/lng lookup).
  Future<String?> reverseGeocode(double lat, double lng) async {
    try {
      final response = await _dio.get(_geocodeUrl, queryParameters: {
        'latlng': '$lat,$lng',
        'key': _apiKey,
      });

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['status'] == 'OK' && (data['results'] as List).isNotEmpty) {
          return data['results'][0]['formatted_address'] as String?;
        }
      }
      return null;
    } catch (e) {
      debugPrint('[Places] reverseGeocode error: $e');
      return null;
    }
  }
}
