import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../core/config.dart';
import '../../../core/services/token_storage.dart';
import '../models/vehicle_model.dart';

class FleetService {
  late final Dio _fleetDio;    // fleet.ridebase.tech — vehicles
  late final Dio _rideDio;     // ride.ridebase.tech/api — availability
  late final Dio _reportingDio; // ride.ridebase.tech/api/reporting — stats & history

  final TokenStorage _tokenStorage;
  final Future<bool> Function()? _onRefreshToken;

  FleetService({
    required TokenStorage tokenStorage,
    Future<bool> Function()? onRefreshToken,
    Dio? fleetDio,
    Dio? rideDio,
    Dio? reportingDio,
  })  : _tokenStorage = tokenStorage,
        _onRefreshToken = onRefreshToken {
    _fleetDio = fleetDio ?? _buildDio(RideBaseConfig.fleetApiBase);
    _rideDio = rideDio ?? _buildDio(RideBaseConfig.rideApiBase);
    _reportingDio = reportingDio ?? _buildDio(RideBaseConfig.rideReportingBase);
  }

  Dio _buildDio(String baseUrl) {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ));
    dio.interceptors.add(InterceptorsWrapper(
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
    return dio;
  }

  Future<List<Vehicle>> getVehicles() async {
    try {
      final response = await _fleetDio.get('/vehicles');
      final list = response.data as List<dynamic>;
      return list.map((j) => Vehicle.fromJson(j as Map<String, dynamic>)).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[FleetService] getVehicles error: $e');
      rethrow;
    }
  }

  /// Registers a vehicle and immediately self-assigns it to the authenticated driver.
  Future<String> registerVehicle({
    required String make,
    required String model,
    required int year,
    required String plateNumber,
    required String color,
    String vehicleType = 'STANDARD',
  }) async {
    try {
      // POST /vehicles/self_assign — creates vehicle + assignment in one step
      final response = await _fleetDio.post('/vehicles/self_assign', data: {
        'car_make': make,
        'car_model': model,
        'car_colour': color,
        'year': year,
        'license_plate': plateNumber,
      });
      return response.data['vehicle_id']?.toString() ?? '';
    } catch (e) {
      if (kDebugMode) debugPrint('[FleetService] registerVehicle error: $e');
      rethrow;
    }
  }

  /// Toggle driver online/offline. [driverId] must match the authenticated user's sub claim.
  Future<void> setAvailability({
    required bool available,
    required String driverId,
  }) async {
    try {
      await _rideDio.post('/drivers/availability', data: {
        'driverId': driverId,
        'isOnline': available,
        'updatedAtUtc': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[FleetService] setAvailability error: $e');
      rethrow;
    }
  }

  /// Fetches lifetime stats and today's earnings in parallel, merges into DriverStats.
  Future<DriverStats> getDriverStats() async {
    try {
      final results = await Future.wait([
        _reportingDio.get('driver/stats'),
        _reportingDio.get('driver/earnings', queryParameters: {'period': 'today'}),
      ]);
      return DriverStats.fromJson(
        results[0].data as Map<String, dynamic>,
        today: results[1].data as Map<String, dynamic>,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[FleetService] getDriverStats error: $e');
      rethrow;
    }
  }

  Future<List<RideRecord>> getDriverRides({int page = 1, int pageSize = 20}) async {
    try {
      final response = await _reportingDio.get(
        'driver/rides',
        queryParameters: {'page': page, 'page_size': pageSize},
      );
      final body = response.data as Map<String, dynamic>;
      final list = body['rides'] as List<dynamic>;
      return list.map((j) => RideRecord.fromJson(j as Map<String, dynamic>)).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[FleetService] getDriverRides error: $e');
      rethrow;
    }
  }
}
