import '../domain/ride_actions.dart';

class RideApiService {

  static Future<void> triggerSos(String rideId, SosRequest request) async {
    // In a real app, this would hit your backend endpoint
    // await _dio.post('/rides/$rideId/sos', data: request.toJson());
    await Future.delayed(const Duration(seconds: 1)); // Mock network delay
  }

  static Future<void> submitRating(RideRatingRequest request) async {
    // await _dio.post('/rides/rating', data: request.toJson());
    await Future.delayed(const Duration(seconds: 1)); // Mock network delay
  }
}

class LocationService {
  // Simple wrapper for Geolocator as expected by the SOS screen
  static Future<Map<String, double>> getCurrentPosition() async {
    // Placeholder to satisfy the legacy screen's logic
    return {
      'latitude': -17.82629,
      'longitude': 31.05037,
    };
  }
}
