class SosRequest {
  SosRequest({
    required this.rideId,
    required this.triggeredBy,
    required this.riderId,
    required this.driverId,
    required this.tripStatus,
    required this.currentLocation,
    required this.timestampUtc,
    required this.message,
  });

  final String rideId;
  final String triggeredBy;
  final String riderId;
  final String driverId;
  final String tripStatus;
  final dynamic currentLocation; // Expects a LatLng object
  final String timestampUtc;
  final String message;

  Map<String, dynamic> toJson() => {
    'ride_id': rideId,
    'triggered_by': triggeredBy,
    'rider_id': riderId,
    'driver_id': driverId,
    'trip_status': tripStatus,
    'current_location': currentLocation.toJson(),
    'timestamp_utc': timestampUtc,
    'message': message,
  };
}

class RideRatingRequest {
  RideRatingRequest({
    required this.rideId,
    required this.riderId,
    required this.driverId,
    required this.rating,
    required this.feedback,
    required this.submittedAtUtc,
  });

  final String rideId;
  final String riderId;
  final String driverId;
  final int rating;
  final String feedback;
  final String submittedAtUtc;

  Map<String, dynamic> toJson() => {
    'ride_id': rideId,
    'rider_id': riderId,
    'driver_id': driverId,
    'rating': rating,
    'feedback': feedback,
    'submitted_at_utc': submittedAtUtc,
  };
}
