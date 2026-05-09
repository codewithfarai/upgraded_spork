class WsLocation {
  final double latitude;
  final double longitude;

  WsLocation({required this.latitude, required this.longitude});

  factory WsLocation.fromJson(Map<String, dynamic> json) {
    return WsLocation(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
      };
}

class WsDriverInfo {
  final String driverId;
  final String name;
  final String phoneNumber;
  final double rating;
  final int ridesCompleted;
  final String vehicle;

  WsDriverInfo({
    required this.driverId,
    required this.name,
    required this.phoneNumber,
    required this.rating,
    required this.ridesCompleted,
    required this.vehicle,
  });

  factory WsDriverInfo.fromJson(Map<String, dynamic> json) {
    return WsDriverInfo(
      driverId: json['driverId'] as String,
      name: json['name'] as String,
      phoneNumber: json['phoneNumber'] as String,
      rating: (json['rating'] as num).toDouble(),
      ridesCompleted: json['ridesCompleted'] as int,
      vehicle: json['vehicle'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'driverId': driverId,
        'name': name,
        'phoneNumber': phoneNumber,
        'rating': rating,
        'ridesCompleted': ridesCompleted,
        'vehicle': vehicle,
      };
}

// ── Base Event ─────────────────────────────────────────────────────────────

abstract class RideWsEvent {
  final String type;
  RideWsEvent(this.type);

  factory RideWsEvent.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    final data = json['data'] as Map<String, dynamic>? ?? json; // Sometimes data is nested, sometimes top-level

    switch (type) {
      case 'RiderOfferReceived':
        return RiderOfferReceivedEvent.fromJson(data);
      case 'RideStatusUpdated':
        return RideStatusUpdatedEvent.fromJson(data);
      case 'DriverLocationUpdated':
        return DriverLocationUpdatedEvent.fromJson(data);
      case 'SosAcknowledged':
        return SosAcknowledgedEvent.fromJson(data);
      case 'DriverRideRequestReceived':
        return DriverRideRequestReceivedEvent.fromJson(data);
      case 'RideAssignedToDriver':
        return RideAssignedToDriverEvent.fromJson(data);
      case 'RideCancelled':
        return RideCancelledEvent.fromJson(data);
      default:
        return UnknownWsEvent(type, data);
    }
  }
}

class UnknownWsEvent extends RideWsEvent {
  final Map<String, dynamic> data;
  UnknownWsEvent(super.type, this.data);
}

// ── Shared Events ──────────────────────────────────────────────────────────

class RideStatusUpdatedEvent extends RideWsEvent {
  final String rideId;
  final String status;
  final String statusMessage;
  final int etaMinutes;
  final DateTime updatedAt;

  RideStatusUpdatedEvent({
    required this.rideId,
    required this.status,
    required this.statusMessage,
    required this.etaMinutes,
    required this.updatedAt,
  }) : super('RideStatusUpdated');

  factory RideStatusUpdatedEvent.fromJson(Map<String, dynamic> json) {
    return RideStatusUpdatedEvent(
      rideId: json['rideId'] as String,
      status: json['status'] as String,
      statusMessage: json['statusMessage'] as String? ?? '',
      etaMinutes: json['etaMinutes'] as int? ?? 0,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}

class SosAcknowledgedEvent extends RideWsEvent {
  final String incidentId;
  final String rideId;
  final String status;
  final String message;
  final DateTime updatedAtUtc;

  SosAcknowledgedEvent({
    required this.incidentId,
    required this.rideId,
    required this.status,
    required this.message,
    required this.updatedAtUtc,
  }) : super('SosAcknowledged');

  factory SosAcknowledgedEvent.fromJson(Map<String, dynamic> json) {
    return SosAcknowledgedEvent(
      incidentId: json['incidentId'] as String,
      rideId: json['rideId'] as String,
      status: json['status'] as String,
      message: json['message'] as String? ?? '',
      updatedAtUtc: DateTime.parse(json['updatedAtUtc'] as String),
    );
  }
}

// ── Rider Events ───────────────────────────────────────────────────────────

class RiderOfferReceivedEvent extends RideWsEvent {
  final String rideOfferId;
  final String rideId;
  final double offerAmount;
  final double riderOfferAmount;
  final double recommendedAmount;
  final bool isCounterOffer;
  final int etaToPickupMinutes;
  final double distance;
  final String pickupAddress;
  final String destinationAddress;
  final WsLocation pickupLocation;
  final WsLocation destinationLocation;
  final DateTime offerTime;
  final WsDriverInfo driver;

  RiderOfferReceivedEvent({
    required this.rideOfferId,
    required this.rideId,
    required this.offerAmount,
    required this.riderOfferAmount,
    required this.recommendedAmount,
    required this.isCounterOffer,
    required this.etaToPickupMinutes,
    required this.distance,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.pickupLocation,
    required this.destinationLocation,
    required this.offerTime,
    required this.driver,
  }) : super('RiderOfferReceived');

  factory RiderOfferReceivedEvent.fromJson(Map<String, dynamic> json) {
    return RiderOfferReceivedEvent(
      rideOfferId: json['rideOfferId'] as String,
      rideId: json['rideId'] as String,
      offerAmount: (json['offerAmount'] as num).toDouble(),
      riderOfferAmount: (json['riderOfferAmount'] as num).toDouble(),
      recommendedAmount: (json['recommendedAmount'] as num).toDouble(),
      isCounterOffer: json['isCounterOffer'] as bool? ?? false,
      etaToPickupMinutes: json['etaToPickupMinutes'] as int? ?? 0,
      distance: (json['distance'] as num).toDouble(),
      pickupAddress: json['pickupAddress'] as String,
      destinationAddress: json['destinationAddress'] as String,
      pickupLocation: WsLocation.fromJson(json['pickupLocation'] as Map<String, dynamic>),
      destinationLocation: WsLocation.fromJson(json['destinationLocation'] as Map<String, dynamic>),
      offerTime: DateTime.parse(json['offerTime'] as String),
      driver: WsDriverInfo.fromJson(json['driver'] as Map<String, dynamic>),
    );
  }
}

class DriverLocationUpdatedEvent extends RideWsEvent {
  final String rideId;
  final String driverId;
  final WsLocation currentLocation;
  final int etaMinutes;
  final double distanceToPickupKm;
  final DateTime updatedAtUtc;

  DriverLocationUpdatedEvent({
    required this.rideId,
    required this.driverId,
    required this.currentLocation,
    required this.etaMinutes,
    required this.distanceToPickupKm,
    required this.updatedAtUtc,
  }) : super('DriverLocationUpdated');

  factory DriverLocationUpdatedEvent.fromJson(Map<String, dynamic> json) {
    return DriverLocationUpdatedEvent(
      rideId: json['rideId'] as String,
      driverId: json['driverId'] as String,
      currentLocation: WsLocation.fromJson(json['currentLocation'] as Map<String, dynamic>),
      etaMinutes: json['etaMinutes'] as int? ?? 0,
      distanceToPickupKm: (json['distanceToPickupKm'] as num?)?.toDouble() ?? 0.0,
      updatedAtUtc: DateTime.parse(json['updatedAtUtc'] as String),
    );
  }
}

// ── Driver Events ──────────────────────────────────────────────────────────

class DriverRideRequestReceivedEvent extends RideWsEvent {
  final String rideId;
  final String? driverId; // Can be null if broadcast to all nearby
  final String riderId;
  final String riderName;
  final String riderPhoneNumber;
  final double offerAmount;
  final double recommendedAmount;
  final String pickupAddress;
  final String destinationAddress;
  final int? etaToPickupMinutes;
  final double? distanceToPickupKm;
  final String status;
  final WsLocation startLocation;
  final WsLocation destinationLocation;

  DriverRideRequestReceivedEvent({
    required this.rideId,
    this.driverId,
    required this.riderId,
    required this.riderName,
    required this.riderPhoneNumber,
    required this.offerAmount,
    required this.recommendedAmount,
    required this.pickupAddress,
    required this.destinationAddress,
    this.etaToPickupMinutes,
    this.distanceToPickupKm,
    required this.status,
    required this.startLocation,
    required this.destinationLocation,
  }) : super('DriverRideRequestReceived');

  factory DriverRideRequestReceivedEvent.fromJson(Map<String, dynamic> json) {
    return DriverRideRequestReceivedEvent(
      rideId: json['rideId'] as String,
      driverId: json['driverId'] as String?,
      riderId: json['riderId'] as String,
      riderName: json['riderName'] as String,
      riderPhoneNumber: json['riderPhoneNumber'] as String,
      offerAmount: (json['offerAmount'] as num).toDouble(),
      recommendedAmount: (json['recommendedAmount'] as num).toDouble(),
      pickupAddress: json['pickupAddress'] as String,
      destinationAddress: json['destinationAddress'] as String,
      etaToPickupMinutes: json['etaToPickupMinutes'] as int?,
      distanceToPickupKm: (json['distanceToPickupKm'] as num?)?.toDouble(),
      status: json['status'] as String,
      startLocation: WsLocation.fromJson(json['startLocation'] as Map<String, dynamic>),
      destinationLocation: WsLocation.fromJson(json['destinationLocation'] as Map<String, dynamic>),
    );
  }
}

class RideAssignedToDriverEvent extends RideWsEvent {
  final String rideId;
  final String selectedOfferId;
  final double acceptedAmount;
  final String status;
  final DateTime acceptedAtUtc;

  RideAssignedToDriverEvent({
    required this.rideId,
    required this.selectedOfferId,
    required this.acceptedAmount,
    required this.status,
    required this.acceptedAtUtc,
  }) : super('RideAssignedToDriver');

  factory RideAssignedToDriverEvent.fromJson(Map<String, dynamic> json) {
    return RideAssignedToDriverEvent(
      rideId: json['rideId'] as String,
      selectedOfferId: json['selectedOfferId'] as String,
      acceptedAmount: (json['acceptedAmount'] as num).toDouble(),
      status: json['status'] as String,
      acceptedAtUtc: DateTime.parse(json['acceptedAtUtc'] as String),
    );
  }
}

class RideCancelledEvent extends RideWsEvent {
  final String rideId;
  final String status;
  final String cancelledBy;
  final String reasonCode;
  final DateTime updatedAtUtc;

  RideCancelledEvent({
    required this.rideId,
    required this.status,
    required this.cancelledBy,
    required this.reasonCode,
    required this.updatedAtUtc,
  }) : super('RideCancelled');

  factory RideCancelledEvent.fromJson(Map<String, dynamic> json) {
    return RideCancelledEvent(
      rideId: json['rideId'] as String,
      status: json['status'] as String,
      cancelledBy: json['cancelledBy'] as String,
      reasonCode: json['reasonCode'] as String? ?? 'unknown',
      updatedAtUtc: DateTime.parse(json['updatedAtUtc'] as String),
    );
  }
}
