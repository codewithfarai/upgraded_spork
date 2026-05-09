import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/auth_provider.dart';
import '../models/vehicle_model.dart';
import '../services/fleet_service.dart';
import '../../../core/models/user_model.dart';

final fleetServiceProvider = Provider<FleetService>((ref) {
  final authService = ref.watch(authServiceProvider);
  return FleetService(
    tokenStorage: authService.tokenStorage,
    onRefreshToken: () async {
      final result = await authService.tryRefresh();
      return result?.success == true;
    },
  );
});

// ── Vehicles ─────────────────────────────────────────────────────────

class VehiclesNotifier extends AsyncNotifier<List<Vehicle>> {
  @override
  Future<List<Vehicle>> build() => ref.read(fleetServiceProvider).getVehicles();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(fleetServiceProvider).getVehicles());
  }

  Future<void> register({
    required String make,
    required String model,
    required int year,
    required String plateNumber,
    required String color,
    String vehicleType = 'STANDARD',
  }) async {
    await ref.read(fleetServiceProvider).registerVehicle(
          make: make,
          model: model,
          year: year,
          plateNumber: plateNumber,
          color: color,
          vehicleType: vehicleType,
        );
    await refresh();
  }
}

final vehiclesProvider = AsyncNotifierProvider<VehiclesNotifier, List<Vehicle>>(
  VehiclesNotifier.new,
);

// ── Driver Stats ──────────────────────────────────────────────────────

final driverStatsProvider = FutureProvider<DriverStats>((ref) {
  return ref.read(fleetServiceProvider).getDriverStats();
});

// ── Driver Availability ───────────────────────────────────────────────

class DriverAvailabilityNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> toggle() async {
    final RideBaseUser? user = ref.read(currentUserProvider);
    if (user == null) return;

    final driverId = user.sub;
    if (driverId.isEmpty) return;

    // SaaS Gate: Driver must be subscribed to go online
    if (!state && !user.isSubscribed) {
      throw Exception('Subscription required. Please renew your plan to go online.');
    }

    final next = !state;
    await ref.read(fleetServiceProvider).setAvailability(
          available: next,
          driverId: driverId,
        );
    state = next;
  }

  void setFromStats(bool isOnline) => state = isOnline;
}

final driverAvailabilityProvider =
    NotifierProvider<DriverAvailabilityNotifier, bool>(
  DriverAvailabilityNotifier.new,
);

// ── Driver Rides ──────────────────────────────────────────────────────

final driverRidesProvider = FutureProvider<List<RideRecord>>((ref) {
  return ref.read(fleetServiceProvider).getDriverRides();
});
