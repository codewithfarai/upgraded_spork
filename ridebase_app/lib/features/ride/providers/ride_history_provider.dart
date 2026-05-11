import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_role_provider.dart';
import '../models/ride_history.dart';
import 'ride_rest_provider.dart';

final rideHistoryProvider = FutureProvider<List<RideHistoryItem>>((ref) async {
  final role = ref.watch(appRoleProvider);
  final restService = ref.read(rideRestServiceProvider);

  final data = await restService.getRideHistory(
    role: role,
    pageSize: 10,
  );

  final response = RideHistoryResponse.fromJson(data);
  return response.rides;
});
