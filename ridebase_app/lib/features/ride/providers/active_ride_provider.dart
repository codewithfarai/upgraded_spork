import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ride_websocket_models.dart';
import 'ride_websocket_provider.dart';

class ActiveRideState {
  final String? rideId;
  final String? riderId;
  final String status;
  final WsLocation? driverLocation;
  final int etaMinutes;
  final double distanceToPickupKm;
  final WsDriverInfo? driver;
  final double acceptedAmount;
  final double distanceKm;

  const ActiveRideState({
    this.rideId,
    this.riderId,
    this.status = '',
    this.driverLocation,
    this.etaMinutes = 0,
    this.distanceToPickupKm = 0.0,
    this.driver,
    this.acceptedAmount = 0.0,
    this.distanceKm = 0.0,
  });

  bool get isActive =>
      rideId != null && status != 'TripCompleted' && status != 'Cancelled';

  ActiveRideState copyWith({
    String? rideId,
    String? riderId,
    String? status,
    WsLocation? driverLocation,
    int? etaMinutes,
    double? distanceToPickupKm,
    WsDriverInfo? driver,
    double? acceptedAmount,
    double? distanceKm,
  }) {
    return ActiveRideState(
      rideId: rideId ?? this.rideId,
      riderId: riderId ?? this.riderId,
      status: status ?? this.status,
      driverLocation: driverLocation ?? this.driverLocation,
      etaMinutes: etaMinutes ?? this.etaMinutes,
      distanceToPickupKm: distanceToPickupKm ?? this.distanceToPickupKm,
      driver: driver ?? this.driver,
      acceptedAmount: acceptedAmount ?? this.acceptedAmount,
      distanceKm: distanceKm ?? this.distanceKm,
    );
  }
}

class ActiveRideNotifier extends StateNotifier<ActiveRideState> {
  ActiveRideNotifier() : super(const ActiveRideState());

  String? get currentRideId => state.rideId;

  void setActiveRide({
    required String rideId,
    required WsDriverInfo driver,
    String status = 'DriverEnRoute',
    String? riderId,
    double acceptedAmount = 0.0,
    double distanceKm = 0.0,
  }) {
    state = state.copyWith(
      rideId: rideId,
      riderId: riderId,
      driver: driver,
      status: status,
      acceptedAmount: acceptedAmount,
      distanceKm: distanceKm,
    );
  }

  void updateLocation(DriverLocationUpdatedEvent event) {
    if (state.rideId != event.rideId) return;

    state = state.copyWith(
      driverLocation: event.currentLocation,
      etaMinutes: event.etaMinutes,
      distanceToPickupKm: event.distanceToPickupKm,
    );
  }

  void updateStatus(RideStatusUpdatedEvent event) {
    if (state.rideId != event.rideId) return;

    state = state.copyWith(status: event.status, etaMinutes: event.etaMinutes);
  }

  void clear() {
    state = const ActiveRideState();
  }

  void simulateActiveRide() {
    setActiveRide(
      rideId: 'mock-ride-123',
      driver: WsDriverInfo(
        driverId: 'mock-driver',
        name: 'Simulated Driver',
        phoneNumber: '+263770000000',
        rating: 5.0,
        ridesCompleted: 0,
        vehicle: 'Toyota Aqua (Silver)',
      ),
    );

    // Harare coordinates roughly
    double lat = -17.8248;
    double lng = 31.0530;

    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!state.isActive) {
        timer.cancel();
        return;
      }

      // Move car slightly north-east
      lat += 0.0005;
      lng += 0.0005;

      updateLocation(DriverLocationUpdatedEvent(
        rideId: 'mock-ride-123',
        driverId: 'mock-driver',
        currentLocation: WsLocation(latitude: lat, longitude: lng),
        etaMinutes: 5,
        distanceToPickupKm: 1.2,
        updatedAtUtc: DateTime.now().toUtc(),
      ));

      if (lat > -17.8000) {
        updateStatus(RideStatusUpdatedEvent(
          rideId: 'mock-ride-123',
          status: 'DriverArrived',
          statusMessage: 'Driver has arrived at your location',
          etaMinutes: 0,
          updatedAt: DateTime.now().toUtc(),
        ));
        timer.cancel();
      }
    });
  }
}

final activeRideProvider =
    StateNotifierProvider<ActiveRideNotifier, ActiveRideState>((ref) {
      final notifier = ActiveRideNotifier();

      ref.listen<AsyncValue<RideWsEvent>>(rideWebSocketEventsProvider, (
        previous,
        next,
      ) {
        final event = next.value;
        if (event is DriverLocationUpdatedEvent) {
          notifier.updateLocation(event);
        } else if (event is RideStatusUpdatedEvent) {
          notifier.updateStatus(event);
        } else if (event is RideCancelledEvent) {
          if (notifier.currentRideId == event.rideId) {
            notifier.clear();
          }
        }
      });

      return notifier;
    });
