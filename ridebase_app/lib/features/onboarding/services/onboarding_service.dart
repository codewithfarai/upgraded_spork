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

  OnboardingService({
    required TokenStorage tokenStorage,
    Dio? dio,
  })  : _tokenStorage = tokenStorage,
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: RideBaseConfig.onboardingApiBase,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
            )) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final accessToken = await _tokenStorage.accessToken;
          if (accessToken != null) {
            options.headers['Authorization'] = 'Bearer $accessToken';
          }
          return handler.next(options);
        },
      ),
    );
  }

  /// Get the current user\'s onboarding profile.
  /// Returns null if the profile doesn\'t exist (404).
  Future<OnboardingProfile?> getMyProfile() async {
    try {
      final response = await _dio.get('/me');
      return OnboardingProfile.fromJson(response.data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      debugPrint('[OnboardingService] getMyProfile error: $e');
      rethrow;
    }
  }

  /// Create a new profile.
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
      debugPrint('[OnboardingService] createProfile error: $e');
      rethrow;
    }
  }

  /// Verify email OTP.
  Future<void> verifyEmail(String code) async {
    try {
      await _dio.post('/verify_email', data: {'code': code});
    } catch (e) {
      debugPrint('[OnboardingService] verifyEmail error: $e');
      rethrow;
    }
  }

  /// Resend OTP.
  Future<void> resendOtp() async {
    try {
      await _dio.post('/resend_otp');
    } catch (e) {
      debugPrint('[OnboardingService] resendOtp error: $e');
      rethrow;
    }
  }

  /// Submit driver details.
  Future<void> submitDriverSetup({
    required String nationalId,
    required String driverLicenseNumber,
    required XFile licensePhoto,
    required XFile nationalIdPhoto,
  }) async {
    try {
      final licenseBytes = await licensePhoto.readAsBytes();
      final nationalIdBytes = await nationalIdPhoto.readAsBytes();

      final formData = FormData.fromMap({
        'national_id': nationalId,
        'driver_license_number': driverLicenseNumber,
        'license_photo': MultipartFile.fromBytes(
          licenseBytes,
          filename: licensePhoto.name,
          contentType: MediaType('image', 'jpeg'), // Simplified for now
        ),
        'national_id_photo': MultipartFile.fromBytes(
          nationalIdBytes,
          filename: nationalIdPhoto.name,
          contentType: MediaType('image', 'jpeg'), // Simplified for now
        ),
      });

      await _dio.post('/driver_setup', data: formData);
    } catch (e) {
      debugPrint('[OnboardingService] submitDriverSetup error: $e');
      rethrow;
    }
  }
}
