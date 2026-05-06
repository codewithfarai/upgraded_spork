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
      make: json['make'] ?? '',
      model: json['model'] ?? '',
      year: json['year'] as int? ?? 0,
      plateNumber: json['plate_number'] ?? json['plateNumber'] ?? '',
      color: json['color'] ?? '',
      vehicleType: json['vehicle_type'] ?? json['vehicleType'] ?? 'STANDARD',
      isActive: json['is_active'] ?? json['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'make': make,
        'model': model,
        'year': year,
        'plate_number': plateNumber,
        'color': color,
        'vehicle_type': vehicleType,
      };
}

class DriverStats {
  final int totalTrips;
  final int tripsToday;
  final double totalEarnings;
  final double earningsToday;
  final double rating;
  final bool isOnline;

  const DriverStats({
    required this.totalTrips,
    required this.tripsToday,
    required this.totalEarnings,
    required this.earningsToday,
    required this.rating,
    required this.isOnline,
  });

  factory DriverStats.fromJson(Map<String, dynamic> json) {
    return DriverStats(
      totalTrips: json['total_trips'] as int? ?? 0,
      tripsToday: json['trips_today'] as int? ?? 0,
      totalEarnings: (json['total_earnings'] as num?)?.toDouble() ?? 0.0,
      earningsToday: (json['earnings_today'] as num?)?.toDouble() ?? 0.0,
      rating: (json['rating'] as num?)?.toDouble() ?? 5.0,
      isOnline: json['is_online'] as bool? ?? false,
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
    return RideRecord(
      id: json['id']?.toString() ?? '',
      pickupAddress: json['pickup_address'] ?? json['origin'] ?? 'Unknown',
      dropoffAddress: json['dropoff_address'] ?? json['destination'] ?? 'Unknown',
      fare: (json['fare'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] ?? 'completed',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      rideType: json['ride_type'] ?? json['vehicle_type'] ?? 'STANDARD',
    );
  }
}
