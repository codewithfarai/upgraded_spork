enum RideStatus {
  searching('Searching'),
  accepted('Accepted'),
  arriving('Arriving'),
  inProgress('In Progress'),
  completed('Completed'),
  cancelled('Cancelled');

  const RideStatus(this.value);
  final String value;
}

class RideSession {
  RideSession({
    required this.rideId,
    required this.riderId,
    this.driverId,
    this.driverName,
    required this.acceptedAmount,
    required this.distanceKm,
  });

  final String rideId;
  final String riderId;
  final String? driverId;
  final String? driverName;
  final double acceptedAmount;
  final double distanceKm;

  factory RideSession.mock() => RideSession(
    rideId: 'ride_123',
    riderId: 'rider_456',
    driverId: 'driver_789',
    driverName: 'Blessing Musona',
    acceptedAmount: 6.78,
    distanceKm: 3.4,
  );
}
