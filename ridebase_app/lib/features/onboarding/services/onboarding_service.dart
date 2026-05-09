// ignore_for_file: use_null_aware_elements
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http_parser/http_parser.dart';
import '../../../core/config.dart';
import '../../../core/services/token_storage.dart';
import '../models/onboarding_profile.dart';

class OnboardingService {
  final Dio _dio;
  final TokenStorage _tokenStorage;
  final Future<bool> Function()? _onRefreshToken;

  OnboardingService({
    required TokenStorage tokenStorage,
    Future<bool> Function()? onRefreshToken,
    Dio? dio,
  })  : _tokenStorage = tokenStorage,
        _onRefreshToken = onRefreshToken,
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: RideBaseConfig.onboardingApiBase,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
            )) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (_onRefreshToken != null && !await _tokenStorage.hasValidToken) {
            await _onRefreshToken();
          }
          final accessToken = await _tokenStorage.accessToken;
          if (accessToken != null) {
            options.headers['Authorization'] = 'Bearer $accessToken';
          }
          return handler.next(options);
        },
      ),
    );
  }

  // ── Profile ────────────────────────────────────────────────────────

  /// Returns null if the profile doesn't exist (404).
  Future<OnboardingProfile?> getMyProfile() async {
    try {
      final response = await _dio.get('/me');
      return OnboardingProfile.fromJson(response.data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      if (kDebugMode) {
        debugPrint('[OnboardingService] getMyProfile error: $e');
      }
      rethrow;
    }
  }

  /// Creates a new profile. Fails (400) if a profile already exists.
  Future<void> createProfile({
    required String fullName,
    required String phoneNumber,
    required String city,
    required String role,
    required String email,
  }) async {
    try {
      final formData = FormData.fromMap({
        'full_name': fullName,
        'phone_number': phoneNumber,
        'city': city,
        'role': role,
        'email': email,
      });
      await _dio.post('/profile', data: formData);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OnboardingService] createProfile error: $e');
      }
      rethrow;
    }
  }

  /// Partially updates the profile. All fields are optional.
  Future<void> updateProfile({
    String? fullName,
    String? phoneNumber,
    String? city,
    String? role,
    XFile? profilePhoto,
  }) async {
    try {
      final formData = FormData.fromMap({
        if (fullName != null) 'full_name': fullName,
        if (phoneNumber != null) 'phone_number': phoneNumber,
        if (city != null) 'city': city,
        if (role != null) 'role': role,
        if (profilePhoto != null)
          'profile_photo': await MultipartFile.fromFile(
            profilePhoto.path,
            filename: profilePhoto.name,
            contentType: MediaType('image', 'jpeg'),
          ),
      });
      await _dio.patch('/me', data: formData);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OnboardingService] updateProfile error: $e');
      }
      rethrow;
    }
  }

  /// Deletes the profile and all associated driver details (cascade).
  Future<void> deleteProfile() async {
    try {
      await _dio.delete('/me');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OnboardingService] deleteProfile error: $e');
      }
      rethrow;
    }
  }

  // ── Email Verification ─────────────────────────────────────────────

  /// Verifies the 6-digit OTP sent to the user's email.
  Future<void> verifyEmail(String code) async {
    try {
      await _dio.post('/verify_email', data: {'code': code});
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OnboardingService] verifyEmail error: $e');
      }
      rethrow;
    }
  }

  /// Resends a new OTP. Replaces the previous code.
  Future<void> resendOtp() async {
    try {
      await _dio.post('/resend_otp');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OnboardingService] resendOtp error: $e');
      }
      rethrow;
    }
  }

  // ── Driver Setup ───────────────────────────────────────────────────

  /// Submits driver and vehicle details. All fields are required.
  /// User must already have a profile with role=DRIVER.
  Future<void> submitDriverSetup({
    required String carMake,
    required String carModel,
    required String carColour,
    required int year,
    required String licensePlate,
    required String nationalId,
    required String driverLicenseNumber,
    required XFile licensePhoto,
    required XFile nationalIdPhoto,
  }) async {
    try {
      final licenseBytes = await licensePhoto.readAsBytes();
      final nationalIdBytes = await nationalIdPhoto.readAsBytes();

      final formData = FormData.fromMap({
        'car_make': carMake,
        'car_model': carModel,
        'car_colour': carColour,
        'year': year,
        'license_plate': licensePlate,
        'national_id': nationalId,
        'driver_license_number': driverLicenseNumber,
        'license_photo': MultipartFile.fromBytes(
          licenseBytes,
          filename: licensePhoto.name,
          contentType: MediaType('image', 'jpeg'),
        ),
        'national_id_photo': MultipartFile.fromBytes(
          nationalIdBytes,
          filename: nationalIdPhoto.name,
          contentType: MediaType('image', 'jpeg'),
        ),
      });

      await _dio.post('/driver_setup', data: formData);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OnboardingService] submitDriverSetup error: $e');
      }
      rethrow;
    }
  }

  /// Partially updates existing driver/vehicle details. All fields are optional.
  Future<void> updateDriverSetup({
    String? carMake,
    String? carModel,
    String? carColour,
    int? year,
    String? licensePlate,
    String? nationalId,
    String? driverLicenseNumber,
    XFile? licensePhoto,
    XFile? nationalIdPhoto,
  }) async {
    try {
      final formData = FormData.fromMap({
        if (carMake != null) 'car_make': carMake,
        if (carModel != null) 'car_model': carModel,
        if (carColour != null) 'car_colour': carColour,
        if (year != null) 'year': year,
        if (licensePlate != null) 'license_plate': licensePlate,
        if (nationalId != null) 'national_id': nationalId,
        if (driverLicenseNumber != null) 'driver_license_number': driverLicenseNumber,
        if (licensePhoto != null)
          'license_photo': MultipartFile.fromBytes(
            await licensePhoto.readAsBytes(),
            filename: licensePhoto.name,
            contentType: MediaType('image', 'jpeg'),
          ),
        if (nationalIdPhoto != null)
          'national_id_photo': MultipartFile.fromBytes(
            await nationalIdPhoto.readAsBytes(),
            filename: nationalIdPhoto.name,
            contentType: MediaType('image', 'jpeg'),
          ),
      });
      await _dio.patch('/driver_setup', data: formData);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OnboardingService] updateDriverSetup error: $e');
      }
      rethrow;
    }
  }

  /// Removes driver/vehicle record while keeping the base profile intact.
  Future<void> deleteDriverSetup() async {
    try {
      await _dio.delete('/driver_setup');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OnboardingService] deleteDriverSetup error: $e');
      }
      rethrow;
    }
  }
}
