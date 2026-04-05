"""Core ride business logic — all database interactions live here.

Each function receives an AsyncSession and operates within a single
transaction; the caller is responsible for commit/rollback boundaries.
"""

import logging
import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.ride import (
    DRIVER_STATUS_TRANSITIONS,
    OPEN_RIDE_STATUSES,
    DriverAvailability,
    OfferStatus,
    Ride,
    RideOffer,
    RideRating,
    RideStatus,
    SosIncident,
)
from app.models.schemas import (
    CancelRideRequest,
    DriverAcceptRequest,
    DriverCompleteRequest,
    DriverCounterOfferRequest,
    DriverLocationUpdateRequest,
    DriverSosRequest,
    DriverStatusUpdate,
    RatingRequest,
    RideRequestCreate,
    RiderSosRequest,
    SelectOfferRequest,
)

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _short_id(uid: uuid.UUID) -> str:
    """Return the first 8 hex chars of a UUID for human-readable reference IDs."""
    return uid.hex[:8]


async def _get_ride_by_guid(db: AsyncSession, ride_id: str) -> Ride:
    """Look up a ride by ride_guid. Raises 404 if not found."""
    result = await db.execute(select(Ride).where(Ride.ride_guid == ride_id))
    ride = result.scalar_one_or_none()
    if not ride:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="ride_not_found")
    return ride


# ---------------------------------------------------------------------------
# Rider operations
# ---------------------------------------------------------------------------

async def create_ride(db: AsyncSession, data: RideRequestCreate) -> Ride:
    """Persist a new ride request. Idempotent on rideGuid."""
    # Idempotency: if a ride with this guid already exists, return it
    result = await db.execute(select(Ride).where(Ride.ride_guid == data.rideGuid))
    existing = result.scalar_one_or_none()
    if existing:
        return existing

    ride = Ride(
        ride_guid=data.rideGuid,
        rider_id=data.riderId,
        rider_name=data.riderName,
        rider_phone_number=data.riderPhoneNumber,
        start_latitude=data.startLocation.latitude,
        start_longitude=data.startLocation.longitude,
        start_address=data.startAddress,
        destination_latitude=data.destinationLocation.latitude,
        destination_longitude=data.destinationLocation.longitude,
        destination_address=data.destinationAddress,
        rider_offer_amount=data.offerAmount,
        recommended_amount=data.recommendedAmount,
        distance_km=data.estimatedDistanceKm,
        estimated_minutes=data.estimatedMinutes,
        is_ordering_for_someone_else=data.isOrderingForSomeoneElse,
        requested_for_name=data.requestedForName,
        comments=data.comments,
        status=RideStatus.REQUESTED.value,
        requested_at_utc=data.requestedAtUtc,
    )
    db.add(ride)
    await db.flush()  # assigns ride.id before commit
    await db.commit()
    await db.refresh(ride)
    return ride


async def select_offer(db: AsyncSession, data: SelectOfferRequest) -> Ride:
    """Rider selects a driver offer — transitions ride to DriverEnRoute."""
    ride = await _get_ride_by_guid(db, data.rideId)

    if ride.status in (RideStatus.TRIP_COMPLETED.value, RideStatus.CANCELLED.value):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="ride_already_completed" if ride.status == RideStatus.TRIP_COMPLETED.value else "ride_already_cancelled",
        )
    if ride.status == RideStatus.DRIVER_EN_ROUTE.value:
        # Idempotent: already accepted
        return ride

    # Validate the offer exists and belongs to this ride
    offer_uuid = _parse_uuid_or_400(data.rideOfferId)
    result = await db.execute(
        select(RideOffer).where(
            RideOffer.id == offer_uuid,
            RideOffer.ride_id == ride.id,
            RideOffer.status == OfferStatus.PENDING.value,
        )
    )
    offer = result.scalar_one_or_none()
    if not offer:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="offer_not_found",
        )

    now = _utcnow()

    # Accept the selected offer
    offer.status = OfferStatus.ACCEPTED.value

    # Reject all other pending offers for this ride
    other_offers_result = await db.execute(
        select(RideOffer).where(
            RideOffer.ride_id == ride.id,
            RideOffer.id != offer_uuid,
            RideOffer.status == OfferStatus.PENDING.value,
        )
    )
    for other in other_offers_result.scalars().all():
        other.status = OfferStatus.REJECTED.value

    # Update ride
    ride.driver_id = data.driverId
    ride.driver_name = offer.driver_name
    ride.driver_phone_number = offer.driver_phone_number
    ride.vehicle_info = offer.driver_vehicle
    ride.accepted_amount = data.offerAmount
    ride.selected_offer_id = offer_uuid
    ride.status = RideStatus.DRIVER_EN_ROUTE.value
    ride.accepted_at_utc = now

    await db.commit()
    await db.refresh(ride)
    return ride


async def cancel_ride(db: AsyncSession, ride_id: str, data: CancelRideRequest, requester_id: str) -> Ride:
    """Cancel a ride. Validates the requester owns the ride (for rider-side cancellations)."""
    ride = await _get_ride_by_guid(db, ride_id)

    if ride.rider_id != requester_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="forbidden")

    if ride.status == RideStatus.TRIP_COMPLETED.value:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="ride_already_completed")
    if ride.status == RideStatus.CANCELLED.value:
        return ride  # idempotent

    ride.status = RideStatus.CANCELLED.value
    ride.cancelled_by = data.cancelledBy
    ride.cancel_reason_code = data.reasonCode
    ride.cancel_reason_text = data.reasonText
    ride.cancelled_at_utc = data.cancelledAtUtc

    await db.commit()
    await db.refresh(ride)
    return ride


async def get_ride(db: AsyncSession, ride_id: str) -> Ride:
    return await _get_ride_by_guid(db, ride_id)


async def create_rider_sos(db: AsyncSession, ride_id: str, data: RiderSosRequest, requester_id: str) -> SosIncident:
    """Create a rider-side SOS incident."""
    ride = await _get_ride_by_guid(db, ride_id)

    if ride.rider_id != requester_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="forbidden")

    incident = _build_sos_incident(
        ride_id=ride.id,
        triggered_by="Rider",
        rider_id=data.riderId,
        driver_id=data.driverId,
        rider_name=ride.rider_name,
        driver_name=ride.driver_name,
        trip_status=data.tripStatus or ride.status,
        reason_code="sos",
        message=data.message,
        lat=data.currentLocation.latitude if data.currentLocation else None,
        lng=data.currentLocation.longitude if data.currentLocation else None,
        triggered_at=data.timestampUtc,
    )
    db.add(incident)
    await db.commit()
    await db.refresh(incident)
    return incident


async def submit_rating(db: AsyncSession, data: RatingRequest, requester_id: str) -> RideRating:
    """Persist a rider rating. Idempotent: second save updates the existing rating."""
    ride = await _get_ride_by_guid(db, data.rideId)

    if ride.rider_id != requester_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="forbidden")

    if ride.status != RideStatus.TRIP_COMPLETED.value:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="invalid_status_transition",
        )

    result = await db.execute(select(RideRating).where(RideRating.ride_id == ride.id))
    existing = result.scalar_one_or_none()
    if existing:
        existing.rating = data.rating
        existing.feedback = data.feedback
        existing.submitted_at_utc = data.submittedAtUtc
        await db.commit()
        await db.refresh(existing)
        return existing

    rating = RideRating(
        ride_id=ride.id,
        rider_id=data.riderId,
        driver_id=data.driverId,
        rating=data.rating,
        feedback=data.feedback,
        submitted_at_utc=data.submittedAtUtc,
    )
    ride.rider_rating = data.rating
    ride.rider_feedback = data.feedback
    db.add(rating)
    await db.commit()
    await db.refresh(rating)
    return rating


# ---------------------------------------------------------------------------
# Driver operations
# ---------------------------------------------------------------------------

async def upsert_driver_availability(db: AsyncSession, driver_id: str, is_online: bool, updated_at: datetime) -> DriverAvailability:
    result = await db.execute(select(DriverAvailability).where(DriverAvailability.driver_id == driver_id))
    rec = result.scalar_one_or_none()
    if rec:
        rec.is_online = is_online
        rec.updated_at_utc = updated_at
    else:
        rec = DriverAvailability(driver_id=driver_id, is_online=is_online, updated_at_utc=updated_at)
        db.add(rec)
    await db.commit()
    return rec


async def driver_accept_offer(db: AsyncSession, data: DriverAcceptRequest) -> Ride:
    """REST endpoint for direct offer acceptance (no counteroffer)."""
    ride = await _get_ride_by_guid(db, data.rideId)

    if ride.status in (RideStatus.TRIP_COMPLETED.value, RideStatus.CANCELLED.value):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="ride_already_completed" if ride.status == RideStatus.TRIP_COMPLETED.value else "ride_already_cancelled",
        )
    if ride.driver_id and ride.driver_id != data.driverId:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="ride_already_accepted")
    if ride.status == RideStatus.DRIVER_EN_ROUTE.value:
        return ride  # idempotent

    # Create or update an offer row for this driver
    result = await db.execute(
        select(RideOffer).where(
            RideOffer.ride_id == ride.id,
            RideOffer.driver_id == data.driverId,
            RideOffer.status == OfferStatus.PENDING.value,
        )
    )
    offer = result.scalar_one_or_none()
    if not offer:
        offer = RideOffer(
            ride_id=ride.id,
            driver_id=data.driverId,
            offer_amount=data.offerAmount,
            rider_offer_amount=ride.rider_offer_amount,
            recommended_amount=ride.recommended_amount,
            is_counter_offer=False,
            eta_to_pickup_minutes=0,
            distance_km=ride.distance_km,
            pickup_address=ride.start_address,
            destination_address=ride.destination_address,
            pickup_latitude=ride.start_latitude,
            pickup_longitude=ride.start_longitude,
            destination_latitude=ride.destination_latitude,
            destination_longitude=ride.destination_longitude,
            driver_name="",
            driver_phone_number="",
            offer_time_utc=data.acceptedAtUtc,
        )
        db.add(offer)
        await db.flush()

    offer.status = OfferStatus.ACCEPTED.value
    ride.status = RideStatus.OFFER_ACCEPTED.value
    await db.commit()
    await db.refresh(ride)
    return ride


async def create_driver_counter_offer(db: AsyncSession, data: DriverCounterOfferRequest) -> RideOffer:
    """REST persistence of a driver counteroffer."""
    ride = await _get_ride_by_guid(db, data.rideId)

    if ride.status not in OPEN_RIDE_STATUSES:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="offer_expired",
        )

    if data.offerAmount <= 0:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="invalid_counter_offer",
        )

    offer_uuid = _parse_uuid_or_400(data.rideOfferId)

    # Upsert: update if same driver already has a pending offer
    result = await db.execute(
        select(RideOffer).where(
            RideOffer.id == offer_uuid,
        )
    )
    existing = result.scalar_one_or_none()
    if existing:
        existing.offer_amount = data.offerAmount
        existing.offer_time_utc = data.offerTimeUtc
        existing.status = OfferStatus.PENDING.value
        await db.commit()
        await db.refresh(existing)
        return existing

    offer = RideOffer(
        id=offer_uuid,
        ride_id=ride.id,
        driver_id=data.driverId,
        offer_amount=data.offerAmount,
        rider_offer_amount=data.riderOfferAmount,
        recommended_amount=data.recommendedAmount,
        is_counter_offer=True,
        eta_to_pickup_minutes=0,
        distance_km=ride.distance_km,
        pickup_address=data.pickupAddress,
        destination_address=data.destinationAddress,
        pickup_latitude=ride.start_latitude,
        pickup_longitude=ride.start_longitude,
        destination_latitude=ride.destination_latitude,
        destination_longitude=ride.destination_longitude,
        driver_name="",
        driver_phone_number="",
        offer_time_utc=data.offerTimeUtc,
    )
    if ride.status == RideStatus.REQUESTED.value:
        ride.status = RideStatus.OFFER_COUNTERED.value

    db.add(offer)
    await db.commit()
    await db.refresh(offer)
    return offer


async def update_driver_ride_status(
    db: AsyncSession,
    ride_id: str,
    driver_id: str,
    data: DriverStatusUpdate,
) -> Ride:
    """Driver-originated ride status update. Enforces valid transitions and idempotency."""
    ride = await _get_ride_by_guid(db, ride_id)

    if ride.driver_id != driver_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="forbidden")

    new_status = data.status

    # Idempotent: same status is a no-op
    if ride.status == new_status:
        return ride

    allowed = DRIVER_STATUS_TRANSITIONS.get(ride.status, set())
    if new_status not in allowed:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="invalid_status_transition",
        )

    ride.status = new_status
    if data.statusMessage:
        ride.driver_status_note = data.statusMessage
    if data.etaMinutes is not None:
        ride.driver_eta_minutes = data.etaMinutes

    if new_status == RideStatus.TRIP_COMPLETED.value:
        ride.completed_at_utc = data.updatedAtUtc

    await db.commit()
    await db.refresh(ride)
    return ride


async def update_driver_location(db: AsyncSession, ride_id: str, driver_id: str, data: DriverLocationUpdateRequest) -> Ride:
    """Persist the driver's latest location on the active ride."""
    ride = await _get_ride_by_guid(db, ride_id)

    if ride.driver_id != driver_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="forbidden")

    ride.driver_current_latitude = data.currentLocation.latitude
    ride.driver_current_longitude = data.currentLocation.longitude
    if data.etaMinutes is not None:
        ride.driver_eta_minutes = data.etaMinutes

    await db.commit()
    return ride


async def complete_ride(db: AsyncSession, ride_id: str, driver_id: str, data: DriverCompleteRequest) -> Ride:
    """Mark ride as TripCompleted from the driver side. Idempotent."""
    ride = await _get_ride_by_guid(db, ride_id)

    if ride.driver_id != driver_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="forbidden")

    if ride.status == RideStatus.TRIP_COMPLETED.value:
        return ride  # idempotent

    if ride.status == RideStatus.CANCELLED.value:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="ride_already_cancelled")

    ride.status = RideStatus.TRIP_COMPLETED.value
    ride.completed_at_utc = data.completedAtUtc

    await db.commit()
    await db.refresh(ride)
    return ride


async def create_driver_sos(db: AsyncSession, data: DriverSosRequest) -> SosIncident:
    """Create a driver-side SOS incident."""
    # Attempt to link to the ride, but proceed even if not found (post-trip SOS)
    ride_uuid: Optional[uuid.UUID] = None
    result = await db.execute(select(Ride).where(Ride.ride_guid == data.rideId))
    ride = result.scalar_one_or_none()
    if ride:
        ride_uuid = ride.id

    incident = _build_sos_incident(
        ride_id=ride_uuid,
        triggered_by="Driver",
        rider_id=data.riderId,
        driver_id=data.driverId,
        rider_name=data.riderName,
        driver_name=data.driverName,
        trip_status=data.tripStatus,
        reason_code=data.reasonCode,
        message=data.message,
        lat=data.currentLocation.latitude if data.currentLocation else None,
        lng=data.currentLocation.longitude if data.currentLocation else None,
        triggered_at=data.triggeredAtUtc,
    )
    db.add(incident)
    await db.commit()
    await db.refresh(incident)
    return incident


async def get_open_requests_for_driver(db: AsyncSession) -> list[Ride]:
    """Return all rides currently open for driver offers."""
    result = await db.execute(
        select(Ride).where(Ride.status.in_(list(OPEN_RIDE_STATUSES)))
    )
    return list(result.scalars().all())


# ---------------------------------------------------------------------------
# WebSocket helpers (called from ws.py)
# ---------------------------------------------------------------------------

async def create_offer_from_ws(
    db: AsyncSession,
    ride: Ride,
    offer_id: str,
    driver_id: str,
    offer_data: dict,
) -> RideOffer:
    """Upsert a driver offer from a WebSocket SubmitDriverOffer message."""
    offer_uuid = uuid.UUID(offer_id) if _is_valid_uuid(offer_id) else uuid.uuid4()
    driver = offer_data.get("driver", {})
    pickup_loc = offer_data.get("pickupLocation", {})
    dest_loc = offer_data.get("destinationLocation", {})
    offer_amount = float(offer_data.get("offerAmount", 0))

    if offer_amount <= 0:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="invalid_counter_offer",
        )

    result = await db.execute(
        select(RideOffer).where(
            RideOffer.ride_id == ride.id,
            RideOffer.driver_id == driver_id,
            RideOffer.status == OfferStatus.PENDING.value,
        )
    )
    existing = result.scalar_one_or_none()

    now = _utcnow()

    if existing:
        existing.offer_amount = offer_amount
        existing.is_counter_offer = offer_data.get("isCounterOffer", False)
        existing.eta_to_pickup_minutes = offer_data.get("etaToPickupMinutes", 0)
        existing.offer_time_utc = now
        offer_uuid = existing.id
    else:
        new_offer = RideOffer(
            id=offer_uuid,
            ride_id=ride.id,
            driver_id=driver_id,
            offer_amount=offer_amount,
            rider_offer_amount=float(offer_data.get("riderOfferAmount", 0)),
            recommended_amount=float(offer_data.get("recommendedAmount", 0)),
            is_counter_offer=offer_data.get("isCounterOffer", False),
            eta_to_pickup_minutes=offer_data.get("etaToPickupMinutes", 0),
            distance_km=float(offer_data.get("distance", 0)),
            pickup_address=offer_data.get("pickupAddress", ""),
            destination_address=offer_data.get("destinationAddress", ""),
            pickup_latitude=float(pickup_loc.get("latitude", 0)),
            pickup_longitude=float(pickup_loc.get("longitude", 0)),
            destination_latitude=float(dest_loc.get("latitude", 0)),
            destination_longitude=float(dest_loc.get("longitude", 0)),
            driver_name=driver.get("name", ""),
            driver_phone_number=driver.get("phoneNumber", ""),
            driver_rating=driver.get("rating"),
            driver_rides_completed=driver.get("ridesCompleted"),
            driver_vehicle=driver.get("vehicle"),
            offer_time_utc=now,
        )
        db.add(new_offer)
        await db.flush()
        offer_uuid = new_offer.id

    if ride.status == RideStatus.REQUESTED.value:
        ride.status = RideStatus.SEARCHING_DRIVERS.value

    await db.commit()
    return existing or new_offer


async def accept_offer_from_ws(
    db: AsyncSession,
    ride: Ride,
    offer_id: str,
    driver_id: str,
    accepted_amount: float,
) -> Optional[RideOffer]:
    """Rider selects a driver via WebSocket AcceptOffer. Mirrors select_offer() logic."""
    offer_uuid = _parse_uuid_optional(offer_id)
    if not offer_uuid:
        return None

    result = await db.execute(
        select(RideOffer).where(
            RideOffer.id == offer_uuid,
            RideOffer.ride_id == ride.id,
            RideOffer.status == OfferStatus.PENDING.value,
        )
    )
    offer = result.scalar_one_or_none()
    if not offer:
        return None

    now = _utcnow()
    offer.status = OfferStatus.ACCEPTED.value

    # Reject other pending offers
    other_result = await db.execute(
        select(RideOffer).where(
            RideOffer.ride_id == ride.id,
            RideOffer.id != offer_uuid,
            RideOffer.status == OfferStatus.PENDING.value,
        )
    )
    for other in other_result.scalars().all():
        other.status = OfferStatus.REJECTED.value

    ride.driver_id = driver_id
    ride.driver_name = offer.driver_name
    ride.driver_phone_number = offer.driver_phone_number
    ride.vehicle_info = offer.driver_vehicle
    ride.accepted_amount = accepted_amount or offer.offer_amount
    ride.selected_offer_id = offer_uuid
    ride.status = RideStatus.DRIVER_EN_ROUTE.value
    ride.accepted_at_utc = now

    await db.commit()
    return offer


# ---------------------------------------------------------------------------
# Private utilities
# ---------------------------------------------------------------------------

def _build_sos_incident(
    *,
    ride_id: Optional[uuid.UUID],
    triggered_by: str,
    rider_id: str,
    driver_id: Optional[str],
    rider_name: Optional[str],
    driver_name: Optional[str],
    trip_status: Optional[str],
    reason_code: str,
    message: Optional[str],
    lat: Optional[float],
    lng: Optional[float],
    triggered_at: datetime,
) -> SosIncident:
    prefix = "driver_sos_" if triggered_by == "Driver" else "sos_"
    short = uuid.uuid4().hex[:8]
    return SosIncident(
        incident_id=f"{prefix}{short}",
        ride_id=ride_id,
        triggered_by=triggered_by,
        rider_id=rider_id,
        driver_id=driver_id,
        rider_name=rider_name,
        driver_name=driver_name,
        trip_status=trip_status,
        reason_code=reason_code,
        message=message,
        latitude=lat,
        longitude=lng,
        triggered_at_utc=triggered_at,
        status="Received",
    )


def _is_valid_uuid(val: str) -> bool:
    try:
        uuid.UUID(val)
        return True
    except (ValueError, AttributeError):
        return False


def _parse_uuid_or_400(val: str) -> uuid.UUID:
    try:
        return uuid.UUID(val)
    except (ValueError, AttributeError):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="invalid_request")


def _parse_uuid_optional(val: str) -> Optional[uuid.UUID]:
    try:
        return uuid.UUID(val)
    except (ValueError, AttributeError):
        return None
