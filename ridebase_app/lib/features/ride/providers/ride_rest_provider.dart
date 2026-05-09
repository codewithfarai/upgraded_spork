import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/auth_provider.dart';
import '../services/ride_rest_service.dart';

final rideRestServiceProvider = Provider<RideRestService>((ref) {
  final authService = ref.watch(authServiceProvider);
  return RideRestService(
    tokenStorage: authService.tokenStorage,
  );
});
