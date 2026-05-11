class RideHistoryItem {
  final String rideId;
  final String status;
  final String pickupAddress;
  final String destinationAddress;
  final double distanceKm;
  final double? acceptedAmount;
  final double riderOfferAmount;
  final String riderName;
  final String? driverName;
  final String? driverVehicle;
  final DateTime requestedAt;
  final DateTime? completedAt;
  final int? rating;

  double get effectiveFare => acceptedAmount ?? riderOfferAmount;

  RideHistoryItem({
    required this.rideId,
    required this.status,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.distanceKm,
    this.acceptedAmount,
    required this.riderOfferAmount,
    required this.riderName,
    this.driverName,
    this.driverVehicle,
    required this.requestedAt,
    this.completedAt,
    this.rating,
  });

  factory RideHistoryItem.fromJson(Map<String, dynamic> json) {
    return RideHistoryItem(
      rideId: json['ride_id'],
      status: json['status'],
      pickupAddress: json['pickup_address'],
      destinationAddress: json['destination_address'],
      distanceKm: (json['distance_km'] as num).toDouble(),
      acceptedAmount: json['accepted_amount'] != null ? (json['accepted_amount'] as num).toDouble() : null,
      riderOfferAmount: (json['rider_offer_amount'] as num).toDouble(),
      riderName: json['rider_name'],
      driverName: json['driver_name'],
      driverVehicle: json['driver_vehicle'],
      requestedAt: DateTime.parse(json['requested_at']),
      completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at']) : null,
      rating: json['rating'],
    );
  }
}

class RideHistoryResponse {
  final int totalCount;
  final int page;
  final int pageSize;
  final List<RideHistoryItem> rides;

  RideHistoryResponse({
    required this.totalCount,
    required this.page,
    required this.pageSize,
    required this.rides,
  });

  factory RideHistoryResponse.fromJson(Map<String, dynamic> json) {
    return RideHistoryResponse(
      totalCount: json['total_count'],
      page: json['page'],
      pageSize: json['page_size'],
      rides: (json['rides'] as List).map((r) => RideHistoryItem.fromJson(r)).toList(),
    );
  }
}
