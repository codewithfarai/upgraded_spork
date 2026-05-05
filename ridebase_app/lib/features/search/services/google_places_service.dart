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
      print('GooglePlacesService: Searching for "$query" with key: ${_apiKey.isNotEmpty ? "SET" : "EMPTY"}');
      final response = await _dio.get(_autocompleteUrl, queryParameters: {
        'input': query,
        'key': _apiKey,
        'components': 'country:zw',
        if (sessionToken != null) 'sessiontoken': sessionToken,
      });

      if (response.statusCode == 200) {
        final data = response.data;
        print('GooglePlacesService: Status: ${data['status']}');

        if (data['status'] == 'OK') {
          return List<Map<String, dynamic>>.from(data['predictions']);
        } else if (data['status'] == 'ZERO_RESULTS') {
          return [];
        } else {
          print('GooglePlacesService: Error: ${data['error_message']}');
          throw Exception(data['error_message'] ?? 'Failed to fetch predictions');
        }
      } else {
        throw Exception('Failed to communicate with Google.');
      }
    } catch (e) {
      print('GooglePlacesService: Exception: $e');
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
    } catch (e) {
      return null;
    }
  }
}
