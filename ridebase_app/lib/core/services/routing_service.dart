import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config.dart';

class RouteResult {
  final double distanceKm;
  final int durationMinutes;
  /// GeoJSON-ready coordinate pairs [lng, lat] decoded from the OSRM polyline.
  final List<List<double>> geometry;

  const RouteResult({
    required this.distanceKm,
    required this.durationMinutes,
    this.geometry = const [],
  });
}

class RoutingService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: RideBaseConfig.routingBase,
    connectTimeout: Duration(seconds: RideBaseConfig.routingTimeout),
  ));

  /// Fetches distance, duration, and encoded route geometry from OSRM.
  Future<RouteResult?> getRouteData(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) async {
    try {
      final response = await _dio.get(
        '/route/v1/driving/$startLng,$startLat;$endLng,$endLat',
        queryParameters: {
          'overview': 'full',    // full encoded polyline for drawing
          'alternatives': 'false',
          'steps': 'false',
        },
      );

      if (response.statusCode == 200 && response.data['routes'].isNotEmpty) {
        final route = response.data['routes'][0];
        final double distanceMeters = (route['distance'] as num).toDouble();
        final double durationSeconds = (route['duration'] as num).toDouble();
        final String encodedPolyline = route['geometry'] as String;

        return RouteResult(
          distanceKm: distanceMeters / 1000.0,
          durationMinutes: (durationSeconds / 60.0).round(),
          geometry: _decodePolyline(encodedPolyline),
        );
      }
    } catch (e) {
      debugPrint('[OSRM] routing error: $e');
      return null;
    }
    return null;
  }

  /// Decodes a Google-format encoded polyline into GeoJSON [lng, lat] pairs.
  static List<List<double>> _decodePolyline(String encoded) {
    final points = <List<double>>[];
    int index = 0;
    final len = encoded.length;
    int lat = 0;
    int lng = 0;

    while (index < len) {
      int shift = 0;
      int result = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      // GeoJSON order: [longitude, latitude]
      points.add([lng / 1e5, lat / 1e5]);
    }
    return points;
  }
}
