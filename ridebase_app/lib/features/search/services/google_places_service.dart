import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

class GooglePlacesService {
  GooglePlacesService(this._dio);
  final Dio _dio;

  static const String _apiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

  static const String _autocompleteUrl =
      'https://maps.googleapis.com/maps/api/place/autocomplete/json';
  static const String _geocodeUrl =
      'https://maps.googleapis.com/maps/api/geocode/json';

  /// Fetch autocomplete predictions from Google Places.
  Future<List<Map<String, dynamic>>> getAutocompletePredictions(
    String query, {
    String? sessionToken,
  }) async {
    if (query.isEmpty) return [];

    try {
      if (_apiKey.isEmpty) {
        debugPrint('[GooglePlacesService] WARNING: GOOGLE_MAPS_API_KEY is empty. Search will not work.');
      }
      final response = await _dio.get(_autocompleteUrl, queryParameters: {
        'input': query,
        'key': _apiKey,
        'components': 'country:zw',
        'location': '-17.8248,31.0530', // Harare center bias
        'radius': '50000',
        'sessiontoken': sessionToken,
      });

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['status'] == 'OK') {
          return List<Map<String, dynamic>>.from(data['predictions']);
        } else if (data['status'] == 'ZERO_RESULTS') {
          return [];
        } else {
          throw Exception(data['error_message'] ?? 'Failed to fetch predictions');
        }
      } else {
        throw Exception('Failed to communicate with Google.');
      }
    } catch (_) {
      return [];
    }
  }

  /// Geocode a Place ID into Lat/Lng coordinates.
  Future<Map<String, dynamic>?> getPlaceCoordinates(String placeId) async {
    try {
      final response = await _dio.get(_geocodeUrl, queryParameters: {
        'place_id': placeId,
        'key': _apiKey,
      });

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          final location = data['results'][0]['geometry']['location'];
          return {
            'lat': location['lat'],
            'lng': location['lng'],
            'formatted_address': data['results'][0]['formatted_address'],
          };
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Reverse geocode Lat/Lng into a human-readable address.
  Future<String?> reverseGeocode(double lat, double lng) async {
    try {
      final response = await _dio.get(_geocodeUrl, queryParameters: {
        'latlng': '$lat,$lng',
        'key': _apiKey,
      });

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          return data['results'][0]['formatted_address'];
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
