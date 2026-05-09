class Vehicle {
  final String id;
  final String make;
  final String model;
  final int year;
  final String plateNumber;
  final String color;
  final String vehicleType;
  final bool isActive;

  const Vehicle({
    required this.id,
    required this.make,
    required this.model,
    required this.year,
    required this.plateNumber,
    required this.color,
    required this.vehicleType,
    required this.isActive,
  });

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    return Vehicle(
      id: json['id']?.toString() ?? '',
      make: json['make'] ?? json['car_make'] ?? '',
      model: json['model'] ?? json['car_model'] ?? '',
      year: json['year'] as int? ?? 0,
      // Backend returns 'plate' (admin service shorthand)
      plateNumber: json['plate_number'] ?? json['plateNumber'] ?? json['plate'] ?? json['license_plate'] ?? '',
      color: json['color'] ?? json['car_colour'] ?? '',
      vehicleType: json['vehicle_type'] ?? json['vehicleType'] ?? 'STANDARD',
      isActive: json['is_active'] ?? json['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'car_make': make,
        'car_model': model,
        'year': year,
        'license_plate': plateNumber,
        'car_colour': color,
      };
}

class DriverStats {
  final int totalTrips;
  final int tripsToday;
  final double totalEarnings;
  final double earningsToday;
  final double rating;
  /// Managed locally by DriverAvailabilityNotifier; not returned by stats endpoint.
  final bool isOnline;

  const DriverStats({
    required this.totalTrips,
    required this.tripsToday,
    required this.totalEarnings,
    required this.earningsToday,
    required this.rating,
    required this.isOnline,
  });

  /// [stats] is from GET /driver/stats.
  /// [today] is from GET /driver/earnings?period=today.
  factory DriverStats.fromJson(
    Map<String, dynamic> stats, {
    Map<String, dynamic>? today,
  }) {
    return DriverStats(
      totalTrips: stats['total_rides_completed'] as int? ?? 0,
      tripsToday: today != null ? (today['rides_completed'] as int? ?? 0) : 0,
      totalEarnings: (stats['total_earnings'] as num?)?.toDouble() ?? 0.0,
      earningsToday: today != null ? (today['total_earnings'] as num?)?.toDouble() ?? 0.0 : 0.0,
      rating: (stats['average_rating'] as num?)?.toDouble() ?? 5.0,
      isOnline: false,
    );
  }
}

class RideRecord {
  final String id;
  final String pickupAddress;
  final String dropoffAddress;
  final double fare;
  final String status;
  final DateTime createdAt;
  final String rideType;

  const RideRecord({
    required this.id,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.fare,
    required this.status,
    required this.createdAt,
    required this.rideType,
  });

  factory RideRecord.fromJson(Map<String, dynamic> json) {
    // Accepted amount may be null if ride was cancelled before offer accepted
    final fare = (json['accepted_amount'] as num?)?.toDouble() ??
        (json['rider_offer_amount'] as num?)?.toDouble() ??
        0.0;

    return RideRecord(
      id: json['ride_id']?.toString() ?? json['id']?.toString() ?? '',
      pickupAddress: json['pickup_address'] ?? json['startAddress'] ?? 'Unknown',
      dropoffAddress: json['destination_address'] ?? json['dropoff_address'] ?? 'Unknown',
      fare: fare,
      status: json['status'] ?? 'completed',
      createdAt: json['requested_at'] != null
          ? DateTime.tryParse(json['requested_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      rideType: json['ride_type'] ?? json['vehicle_type'] ?? 'STANDARD',
    );
  }
}
