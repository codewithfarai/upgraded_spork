import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/auth_provider.dart';
import '../models/vehicle_model.dart';
import '../services/fleet_service.dart';

final fleetServiceProvider = Provider<FleetService>((ref) {
  final tokenStorage = ref.watch(authServiceProvider).tokenStorage;
  return FleetService(tokenStorage: tokenStorage);
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
    required String vehicleType,
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

class DriverAvailabilityNotifier extends StateNotifier<bool> {
  final FleetService _service;

  DriverAvailabilityNotifier(this._service) : super(false);

  Future<void> toggle() async {
    final next = !state;
    await _service.setAvailability(available: next);
    state = next;
  }

  void setFromStats(bool isOnline) => state = isOnline;
}

final driverAvailabilityProvider =
    StateNotifierProvider<DriverAvailabilityNotifier, bool>((ref) {
  return DriverAvailabilityNotifier(ref.read(fleetServiceProvider));
});

// ── Driver Rides ──────────────────────────────────────────────────────

final driverRidesProvider = FutureProvider<List<RideRecord>>((ref) {
  return ref.read(fleetServiceProvider).getDriverRides();
});
