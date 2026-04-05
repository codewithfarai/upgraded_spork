import enum
import uuid
from datetime import datetime, timezone

from sqlalchemy import Boolean, Column, DateTime, Float, ForeignKey, Integer, Numeric, String, Text
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import relationship

from app.db.database import Base


class RideStatus(str, enum.Enum):
    REQUESTED = "Requested"
    SEARCHING_DRIVERS = "SearchingDrivers"
    OFFER_COUNTERED = "OfferCountered"
    OFFER_ACCEPTED = "OfferAccepted"
    DRIVER_EN_ROUTE = "DriverEnRoute"
    DRIVER_ARRIVED = "DriverArrived"
    TRIP_STARTED = "TripStarted"
    TRIP_COMPLETED = "TripCompleted"
    CANCELLED = "Cancelled"
    OFFER_REJECTED = "OfferRejected"


# States from which a driver-initiated status update is allowed
DRIVER_STATUS_TRANSITIONS: dict[str, set[str]] = {
    RideStatus.OFFER_ACCEPTED.value: {RideStatus.DRIVER_EN_ROUTE.value},
    RideStatus.DRIVER_EN_ROUTE.value: {RideStatus.DRIVER_ARRIVED.value},
    RideStatus.DRIVER_ARRIVED.value: {RideStatus.TRIP_STARTED.value},
    RideStatus.TRIP_STARTED.value: {RideStatus.TRIP_COMPLETED.value},
}

OPEN_RIDE_STATUSES = {
    RideStatus.REQUESTED.value,
    RideStatus.SEARCHING_DRIVERS.value,
    RideStatus.OFFER_COUNTERED.value,
}


class OfferStatus(str, enum.Enum):
    PENDING = "Pending"
    ACCEPTED = "Accepted"
    REJECTED = "Rejected"
    EXPIRED = "Expired"


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Ride(Base):
    __tablename__ = "rides"

    id = Column(PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    # Client-generated correlation UUID (stored as string to preserve exact client format)
    ride_guid = Column(String, unique=True, nullable=False, index=True)

    rider_id = Column(String, nullable=False, index=True)
    driver_id = Column(String, nullable=True, index=True)
    rider_name = Column(String, nullable=False)
    rider_phone_number = Column(String, nullable=False)
    driver_name = Column(String, nullable=True)
    driver_phone_number = Column(String, nullable=True)
    vehicle_info = Column(String, nullable=True)

    # Locations
    start_latitude = Column(Float, nullable=False)
    start_longitude = Column(Float, nullable=False)
    start_address = Column(String, nullable=False)
    destination_latitude = Column(Float, nullable=False)
    destination_longitude = Column(Float, nullable=False)
    destination_address = Column(String, nullable=False)

    # Financials
    rider_offer_amount = Column(Numeric(10, 2), nullable=False)
    recommended_amount = Column(Numeric(10, 2), nullable=False)
    accepted_amount = Column(Numeric(10, 2), nullable=True)
    selected_offer_id = Column(PGUUID(as_uuid=True), nullable=True)

    # Trip metadata
    distance_km = Column(Float, nullable=False)
    estimated_minutes = Column(Integer, nullable=False)

    # Driver progress (updated in realtime during active trip)
    driver_eta_minutes = Column(Integer, nullable=True)
    driver_current_latitude = Column(Float, nullable=True)
    driver_current_longitude = Column(Float, nullable=True)
    driver_status_note = Column(String, nullable=True)

    # Post-trip
    rider_rating = Column(Integer, nullable=True)
    rider_feedback = Column(Text, nullable=True)

    status = Column(String, nullable=False, default=RideStatus.REQUESTED.value)

    # Request extras
    comments = Column(Text, nullable=True)
    is_ordering_for_someone_else = Column(Boolean, nullable=False, default=False)
    requested_for_name = Column(String, nullable=True)

    # Timestamps
    requested_at_utc = Column(DateTime(timezone=True), nullable=False)
    accepted_at_utc = Column(DateTime(timezone=True), nullable=True)
    completed_at_utc = Column(DateTime(timezone=True), nullable=True)
    cancelled_at_utc = Column(DateTime(timezone=True), nullable=True)
    cancelled_by = Column(String, nullable=True)
    cancel_reason_code = Column(String, nullable=True)
    cancel_reason_text = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), default=_utcnow)

    offers = relationship("RideOffer", back_populates="ride", lazy="select")
    rating = relationship("RideRating", back_populates="ride", uselist=False, lazy="select")


class RideOffer(Base):
    __tablename__ = "ride_offers"

    id = Column(PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    ride_id = Column(PGUUID(as_uuid=True), ForeignKey("rides.id", ondelete="CASCADE"), nullable=False, index=True)
    driver_id = Column(String, nullable=False, index=True)
    offer_amount = Column(Numeric(10, 2), nullable=False)
    rider_offer_amount = Column(Numeric(10, 2), nullable=False)
    recommended_amount = Column(Numeric(10, 2), nullable=False)
    is_counter_offer = Column(Boolean, nullable=False, default=False)
    eta_to_pickup_minutes = Column(Integer, nullable=False)
    distance_km = Column(Float, nullable=False)
    pickup_address = Column(String, nullable=False)
    destination_address = Column(String, nullable=False)
    pickup_latitude = Column(Float, nullable=False)
    pickup_longitude = Column(Float, nullable=False)
    destination_latitude = Column(Float, nullable=False)
    destination_longitude = Column(Float, nullable=False)
    driver_name = Column(String, nullable=False)
    driver_phone_number = Column(String, nullable=False)
    driver_rating = Column(Float, nullable=True)
    driver_rides_completed = Column(Integer, nullable=True)
    driver_vehicle = Column(String, nullable=True)
    status = Column(String, nullable=False, default=OfferStatus.PENDING.value)
    offer_time_utc = Column(DateTime(timezone=True), nullable=False)
    created_at = Column(DateTime(timezone=True), default=_utcnow)

    ride = relationship("Ride", back_populates="offers")


class SosIncident(Base):
    __tablename__ = "sos_incidents"

    id = Column(PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    incident_id = Column(String, unique=True, nullable=False, index=True)
    # Nullable: SOS may arrive slightly after ride completion
    ride_id = Column(PGUUID(as_uuid=True), ForeignKey("rides.id", ondelete="SET NULL"), nullable=True, index=True)
    triggered_by = Column(String, nullable=False)  # "Rider" | "Driver"
    rider_id = Column(String, nullable=False, index=True)
    driver_id = Column(String, nullable=True)
    driver_name = Column(String, nullable=True)
    rider_name = Column(String, nullable=True)
    trip_status = Column(String, nullable=True)
    reason_code = Column(String, nullable=False)
    message = Column(Text, nullable=True)
    latitude = Column(Float, nullable=True)
    longitude = Column(Float, nullable=True)
    triggered_at_utc = Column(DateTime(timezone=True), nullable=False)
    status = Column(String, nullable=False, default="Received")
    created_at = Column(DateTime(timezone=True), default=_utcnow)


class DriverAvailability(Base):
    __tablename__ = "driver_availability"

    driver_id = Column(String, primary_key=True)
    is_online = Column(Boolean, nullable=False, default=False)
    updated_at_utc = Column(DateTime(timezone=True), nullable=False)


class RideRating(Base):
    __tablename__ = "ride_ratings"

    id = Column(PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    ride_id = Column(PGUUID(as_uuid=True), ForeignKey("rides.id", ondelete="CASCADE"), unique=True, nullable=False, index=True)
    rider_id = Column(String, nullable=False)
    driver_id = Column(String, nullable=False)
    rating = Column(Integer, nullable=False)  # 1–5
    feedback = Column(Text, nullable=True)
    submitted_at_utc = Column(DateTime(timezone=True), nullable=False)
    created_at = Column(DateTime(timezone=True), default=_utcnow)

    ride = relationship("Ride", back_populates="rating")
