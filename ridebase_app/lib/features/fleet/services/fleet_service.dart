import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../core/config.dart';
import '../../../core/services/token_storage.dart';
import '../models/vehicle_model.dart';

class FleetService {
  final Dio _dio;
  final TokenStorage _tokenStorage;

  FleetService({required TokenStorage tokenStorage, Dio? dio})
      : _tokenStorage = tokenStorage,
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: RideBaseConfig.fleetApiBase,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
            )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _tokenStorage.accessToken;
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
    ));
  }

  Future<List<Vehicle>> getVehicles() async {
    try {
      final response = await _dio.get('/vehicles');
      final list = response.data as List<dynamic>;
      return list.map((j) => Vehicle.fromJson(j as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('[FleetService] getVehicles error: $e');
      rethrow;
    }
  }

  Future<Vehicle> registerVehicle({
    required String make,
    required String model,
    required int year,
    required String plateNumber,
    required String color,
    required String vehicleType,
  }) async {
    try {
      final response = await _dio.post('/vehicles', data: {
        'make': make,
        'model': model,
        'year': year,
        'plate_number': plateNumber,
        'color': color,
        'vehicle_type': vehicleType,
      });
      return Vehicle.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[FleetService] registerVehicle error: $e');
      rethrow;
    }
  }

  Future<void> setAvailability({required bool available}) async {
    try {
      await _dio.post('/drivers/availability', data: {'available': available});
    } catch (e) {
      debugPrint('[FleetService] setAvailability error: $e');
      rethrow;
    }
  }

  Future<DriverStats> getDriverStats() async {
    try {
      final response = await _dio.get('/driver/stats');
      return DriverStats.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[FleetService] getDriverStats error: $e');
      rethrow;
    }
  }

  Future<List<RideRecord>> getDriverRides() async {
    try {
      final response = await _dio.get('/reporting/driver/rides');
      final list = response.data as List<dynamic>;
      return list.map((j) => RideRecord.fromJson(j as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('[FleetService] getDriverRides error: $e');
      rethrow;
    }
  }
}
