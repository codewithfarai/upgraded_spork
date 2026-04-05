from __future__ import annotations

from datetime import datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, field_validator


# ---------------------------------------------------------------------------
# Shared building blocks
# ---------------------------------------------------------------------------

class GeoLocation(BaseModel):
    latitude: float
    longitude: float


class DriverInfo(BaseModel):
    driverId: str
    name: str
    phoneNumber: str
    rating: Optional[float] = None
    ridesCompleted: Optional[int] = None
    vehicle: Optional[str] = None


# ---------------------------------------------------------------------------
# Error shape
# ---------------------------------------------------------------------------

class ErrorResponse(BaseModel):
    code: str
    message: str
    details: Optional[str] = None


# ---------------------------------------------------------------------------
# Rider REST — requests
# ---------------------------------------------------------------------------

class RideRequestCreate(BaseModel):
    rideGuid: str
    riderId: str
    riderName: str
    riderPhoneNumber: str
    startLocation: GeoLocation
    startAddress: str
    destinationLocation: GeoLocation
    destinationAddress: str
    offerAmount: float
    recommendedAmount: float
    estimatedDistanceKm: float
    estimatedMinutes: int
    isOrderingForSomeoneElse: bool = False
    requestedForName: Optional[str] = None
    requestedAtUtc: datetime
    comments: Optional[str] = None

    @field_validator("offerAmount", "recommendedAmount")
    @classmethod
    def amount_must_be_positive(cls, v: float) -> float:
        if v <= 0:
            raise ValueError("Amount must be greater than zero")
        return v


class SelectOfferRequest(BaseModel):
    rideId: str
    rideOfferId: str
    riderId: str
    driverId: str
    offerAmount: float
    recommendedAmount: float
    status: str
    pickupAddress: str
    destinationAddress: str
    startLocation: GeoLocation
    destinationLocation: GeoLocation


class CancelRideRequest(BaseModel):
    cancelledBy: str  # "Rider" | "Driver" | "Backend"
    reasonCode: str
    reasonText: Optional[str] = None
    cancelledAtUtc: datetime


class RiderSosRequest(BaseModel):
    rideId: str
    triggeredBy: str = "Rider"
    riderId: str
    driverId: Optional[str] = None
    tripStatus: Optional[str] = None
    currentLocation: Optional[GeoLocation] = None
    timestampUtc: datetime
    message: Optional[str] = None


class RatingRequest(BaseModel):
    rideId: str
    riderId: str
    driverId: str
    rating: int
    feedback: Optional[str] = None
    submittedAtUtc: datetime

    @field_validator("rating")
    @classmethod
    def rating_in_range(cls, v: int) -> int:
        if not 1 <= v <= 5:
            raise ValueError("Rating must be between 1 and 5")
        return v


# ---------------------------------------------------------------------------
# Rider REST — responses
# ---------------------------------------------------------------------------

class RideRequestResponse(BaseModel):
    rideRequestId: str
    rideStatus: str
    rideDistance: float
    estimatedWaitTime: int


class SelectOfferResponse(BaseModel):
    rideId: str
    status: str
    selectedOfferId: str
    driverId: str
    acceptedAmount: float
    acceptedAtUtc: datetime


class CancelRideResponse(BaseModel):
    rideId: str
    status: str


class RideSessionResponse(BaseModel):
    rideId: str
    riderId: str
    driverId: Optional[str]
    riderName: str
    riderPhoneNumber: str
    driverName: Optional[str]
    driverPhoneNumber: Optional[str]
    vehicleInfo: Optional[str]
    startLocation: GeoLocation
    startAddress: str
    destinationLocation: GeoLocation
    destinationAddress: str
    riderOfferAmount: float
    recommendedAmount: float
    acceptedAmount: Optional[float]
    selectedOfferId: Optional[str]
    distanceKm: float
    estimatedMinutes: int
    driverEtaMinutes: Optional[int]
    driverCurrentLocation: Optional[GeoLocation]
    driverStatusNote: Optional[str]
    riderRating: Optional[int]
    riderFeedback: Optional[str]
    requestedAtUtc: datetime
    acceptedAtUtc: Optional[datetime]
    completedAtUtc: Optional[datetime]
    status: str


class RideStatusResponse(BaseModel):
    rideId: str
    status: str
    updatedAtUtc: Optional[datetime] = None


class RideTrackResponse(BaseModel):
    rideId: str
    driverId: str
    currentLocation: GeoLocation
    etaMinutes: Optional[int]
    distanceToPickupKm: Optional[float]
    updatedAtUtc: datetime


class SosResponse(BaseModel):
    incidentId: str
    status: str
    receivedAtUtc: datetime


class RatingResponse(BaseModel):
    rideId: str
    ratingSaved: bool


# ---------------------------------------------------------------------------
# Driver REST — requests
# ---------------------------------------------------------------------------

class DriverAvailabilityUpdate(BaseModel):
    driverId: str
    isOnline: bool
    updatedAtUtc: datetime


class DriverAcceptRequest(BaseModel):
    rideId: str
    driverId: str
    offerAmount: float
    acceptedAtUtc: datetime


class DriverCounterOfferRequest(BaseModel):
    rideOfferId: str
    rideId: str
    driverId: str
    offerAmount: float
    riderOfferAmount: float
    recommendedAmount: float
    pickupAddress: str
    destinationAddress: str
    offerTimeUtc: datetime

    @field_validator("offerAmount")
    @classmethod
    def offer_must_be_positive(cls, v: float) -> float:
        if v <= 0:
            raise ValueError("Offer amount must be greater than zero")
        return v


class DriverStatusUpdate(BaseModel):
    driverId: str
    status: str
    statusMessage: Optional[str] = None
    etaMinutes: Optional[int] = None
    updatedAtUtc: datetime


class DriverLocationUpdateRequest(BaseModel):
    rideId: str
    driverId: str
    currentLocation: GeoLocation
    etaMinutes: Optional[int] = None
    distanceToPickupKm: Optional[float] = None
    updatedAtUtc: datetime


class DriverCompleteRequest(BaseModel):
    driverId: str
    completedAtUtc: datetime


class DriverSosRequest(BaseModel):
    rideId: str
    driverId: str
    driverName: str
    riderId: str
    riderName: str
    tripStatus: Optional[str] = None
    reasonCode: str
    message: Optional[str] = None
    currentLocation: Optional[GeoLocation] = None
    triggeredAtUtc: datetime


# ---------------------------------------------------------------------------
# Driver REST — responses
# ---------------------------------------------------------------------------

class DriverAvailabilityResponse(BaseModel):
    driverId: str
    isOnline: bool


class DriverAcceptResponse(BaseModel):
    rideId: str
    status: str


class DriverCounterOfferResponse(BaseModel):
    rideOfferId: str
    status: str


class DriverStatusUpdateResponse(BaseModel):
    rideId: str
    status: str


class DriverLocationResponse(BaseModel):
    rideId: str
    accepted: bool


class DriverCompleteResponse(BaseModel):
    rideId: str
    status: str


class OpenRideRequestItem(BaseModel):
    rideId: str
    driverId: Optional[str]
    riderId: str
    riderName: str
    riderPhoneNumber: str
    offerAmount: float
    recommendedAmount: float
    pickupAddress: str
    destinationAddress: str
    etaToPickupMinutes: Optional[int]
    distanceToPickupKm: Optional[float]
    status: str
    startLocation: GeoLocation
    destinationLocation: GeoLocation
