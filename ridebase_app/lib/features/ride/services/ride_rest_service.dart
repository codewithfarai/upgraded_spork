import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../core/config.dart';
import '../../../core/services/token_storage.dart';

class RideRestService {
  final Dio _dio;
  final TokenStorage _tokenStorage;
  final Future<bool> Function()? _onRefreshToken;

  RideRestService({
    required TokenStorage tokenStorage,
    Future<bool> Function()? onRefreshToken,
    Dio? dio,
  })  : _tokenStorage = tokenStorage,
        _onRefreshToken = onRefreshToken,
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: RideBaseConfig.rideApiBase,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
            )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        if (_onRefreshToken != null && !await _tokenStorage.hasValidToken) {
          await _onRefreshToken();
        }
        final token = await _tokenStorage.accessToken;
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
    ));
  }

  /// Rider requests a new ride. Returns the `rideRequestId`.
  Future<String> requestRide({
    required String rideGuid,
    required String riderId,
    required String riderName,
    required String riderPhoneNumber,
    required double startLat,
    required double startLng,
    required String startAddress,
    required double destLat,
    required double destLng,
    required String destAddress,
    required double offerAmount,
    required double recommendedAmount,
    required double estimatedDistanceKm,
    required int estimatedMinutes,
  }) async {
    try {
      final response = await _dio.post('rides/request', data: {
        'rideGuid': rideGuid,
        'riderId': riderId,
        'riderName': riderName,
        'riderPhoneNumber': riderPhoneNumber,
        'startLocation': {'latitude': startLat, 'longitude': startLng},
        'startAddress': startAddress,
        'destinationLocation': {'latitude': destLat, 'longitude': destLng},
        'destinationAddress': destAddress,
        'offerAmount': offerAmount,
        'recommendedAmount': recommendedAmount,
        'estimatedDistanceKm': estimatedDistanceKm,
        'estimatedMinutes': estimatedMinutes,
        'isOrderingForSomeoneElse': false,
        'requestedForName': '',
        'requestedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'comments': '',
      });
      return response.data['rideRequestId'] as String;
    } catch (e) {
      if (kDebugMode) debugPrint('[RideRestService] requestRide error: $e');
      rethrow;
    }
  }

  /// Rider confirms a driver's offer over REST.
  Future<void> selectOffer({
    required String rideId,
    required String rideOfferId,
    required String riderId,
    required String driverId,
    required double offerAmount,
    required double recommendedAmount,
    required String pickupAddress,
    required String destinationAddress,
    required double startLat,
    required double startLng,
    required double destLat,
    required double destLng,
  }) async {
    try {
      await _dio.post('rides/select-offer', data: {
        'rideId': rideId,
        'rideOfferId': rideOfferId,
        'riderId': riderId,
        'driverId': driverId,
        'offerAmount': offerAmount,
        'recommendedAmount': recommendedAmount,
        'status': 'OfferAccepted',
        'pickupAddress': pickupAddress,
        'destinationAddress': destinationAddress,
        'startLocation': {'latitude': startLat, 'longitude': startLng},
        'destinationLocation': {'latitude': destLat, 'longitude': destLng},
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[RideRestService] selectOffer error: $e');
      rethrow;
    }
  }

  /// Driver optionally confirms they accepted an offer directly.
  Future<void> driverAccept({
    required String rideId,
    required String driverId,
    required double offerAmount,
  }) async {
    try {
      await _dio.post('rides/driver/accept', data: {
        'rideId': rideId,
        'driverId': driverId,
        'offerAmount': offerAmount,
        'acceptedAtUtc': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[RideRestService] driverAccept error: $e');
      rethrow;
    }
  }

  Future<void> cancelRide({
    required String rideId,
    required String cancelledBy,
    required String reasonCode,
    String? reasonText,
  }) async {
    try {
      await _dio.post('rides/$rideId/cancel', data: {
        'cancelledBy': cancelledBy,
        'reasonCode': reasonCode,
        'reasonText': reasonText,
        'cancelledAtUtc': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[RideRestService] cancelRide error: $e');
      rethrow;
    }
  }

  Future<void> riderSos({
    required String rideId,
    required String riderId,
    String? driverId,
    String? tripStatus,
    double? lat,
    double? lng,
    String? message,
  }) async {
    try {
      await _dio.post('rides/$rideId/sos', data: {
        'rideId': rideId,
        'triggeredBy': 'Rider',
        'riderId': riderId,
        'driverId': ?driverId,
        'tripStatus': ?tripStatus,
        if (lat != null && lng != null)
          'currentLocation': {'latitude': lat, 'longitude': lng},
        'timestampUtc': DateTime.now().toUtc().toIso8601String(),
        'message': ?message,
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[RideRestService] riderSos error: $e');
      rethrow;
    }
  }

  Future<void> rateDriver({
    required String rideId,
    required String riderId,
    required String driverId,
    required int rating,
    String? feedback,
  }) async {
    try {
      await _dio.post('rides/rider/rating', data: {
        'rideId': rideId,
        'riderId': riderId,
        'driverId': driverId,
        'rating': rating,
        'feedback': feedback,
        'submittedAtUtc': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[RideRestService] rateDriver error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getRideHistory({
    required String role,
    int page = 1,
    int pageSize = 10,
  }) async {
    try {
      final endpoint = role.toLowerCase() == 'driver'
          ? 'reporting/driver/rides'
          : 'reporting/rider/rides';

      final response = await _dio.get(
        endpoint,
        queryParameters: {
          'page': page,
          'page_size': pageSize,
        },
      );
      return response.data as Map<String, dynamic>;
    } catch (e) {
      if (kDebugMode) debugPrint('[RideRestService] getRideHistory error: $e');
      rethrow;
    }
  }
}
