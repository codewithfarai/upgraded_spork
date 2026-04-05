import logging
from datetime import timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.database import get_db
from app.middleware.auth import get_current_user
from app.models.ride import RideStatus
from app.models.schemas import (
    CancelRideRequest,
    CancelRideResponse,
    GeoLocation,
    RatingRequest,
    RatingResponse,
    RideRequestCreate,
    RideRequestResponse,
    RideSessionResponse,
    RideStatusResponse,
    RideTrackResponse,
    RiderSosRequest,
    SelectOfferRequest,
    SelectOfferResponse,
    SosResponse,
)
from app.services import ride_service
from app.services.rabbitmq import publisher
from app.websocket.manager import manager

logger = logging.getLogger(__name__)

router = APIRouter()


def _get_caller_id(current_user: dict) -> str:
    caller_id = current_user.get("authentik_pk") or current_user.get("sub")
    if not caller_id:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="unauthorized")
    return str(caller_id)


# ---------------------------------------------------------------------------
# POST /api/rides/request
# ---------------------------------------------------------------------------

@router.post("/request", response_model=RideRequestResponse, status_code=status.HTTP_201_CREATED)
async def create_ride_request(
    data: RideRequestCreate,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Create a ride request and begin the driver matching session."""
    caller_id = _get_caller_id(current_user)

    # Enforce that the token's user matches the request's riderId
    if data.riderId != caller_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="forbidden")

    ride = await ride_service.create_ride(db, data)

    # Broadcast to all connected online drivers via WebSocket
    ws_event = {
        "type": "DriverRideRequestReceived",
        "data": {
            "rideId": ride.ride_guid,
            "driverId": None,
            "riderId": ride.rider_id,
            "riderName": ride.rider_name,
            "riderPhoneNumber": ride.rider_phone_number,
            "offerAmount": float(ride.rider_offer_amount),
            "recommendedAmount": float(ride.recommended_amount),
            "pickupAddress": ride.start_address,
            "destinationAddress": ride.destination_address,
            "etaToPickupMinutes": None,
            "distanceToPickupKm": None,
            "status": ride.status,
            "startLocation": {"latitude": ride.start_latitude, "longitude": ride.start_longitude},
            "destinationLocation": {"latitude": ride.destination_latitude, "longitude": ride.destination_longitude},
        },
    }
    await manager.broadcast_ride_request_to_drivers(ws_event)

    # Publish to RabbitMQ for cross-service visibility
    await publisher.publish(
        "ride.requested",
        {
            "event_type": "ride.requested",
            "rideId": ride.ride_guid,
            "riderId": ride.rider_id,
            "offerAmount": float(ride.rider_offer_amount),
        },
    )

    return RideRequestResponse(
        rideRequestId=f"ride_{ride.id.hex[:8]}",
        rideStatus=ride.status,
        rideDistance=ride.distance_km,
        estimatedWaitTime=5,
    )


# ---------------------------------------------------------------------------
# POST /api/rides/select-offer
# ---------------------------------------------------------------------------

@router.post("/select-offer", response_model=SelectOfferResponse)
async def select_offer(
    data: SelectOfferRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Rider selects a driver offer. Marks the ride as DriverEnRoute."""
    caller_id = _get_caller_id(current_user)

    if data.riderId != caller_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="forbidden")

    ride = await ride_service.select_offer(db, data)

    # Notify the selected driver via WebSocket
    ws_event = {
        "type": "RideAssignedToDriver",
        "data": {
            "rideId": ride.ride_guid,
            "selectedOfferId": data.rideOfferId,
            "acceptedAmount": float(ride.accepted_amount),
            "status": RideStatus.DRIVER_EN_ROUTE.value,
            "acceptedAtUtc": ride.accepted_at_utc.isoformat() if ride.accepted_at_utc else None,
        },
    }
    await manager.send_to_driver(ride.driver_id, ws_event)

    await publisher.publish(
        "ride.accepted",
        {
            "event_type": "ride.accepted",
            "rideId": ride.ride_guid,
            "riderId": ride.rider_id,
            "driverId": ride.driver_id,
            "acceptedAmount": float(ride.accepted_amount),
        },
    )

    return SelectOfferResponse(
        rideId=ride.ride_guid,
        status=ride.status,
        selectedOfferId=data.rideOfferId,
        driverId=ride.driver_id,
        acceptedAmount=float(ride.accepted_amount),
        acceptedAtUtc=ride.accepted_at_utc,
    )


# ---------------------------------------------------------------------------
# POST /api/rides/{rideId}/cancel
# ---------------------------------------------------------------------------

@router.post("/{rideId}/cancel", response_model=CancelRideResponse)
async def cancel_ride(
    rideId: str,
    data: CancelRideRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Cancel a ride from the rider side."""
    caller_id = _get_caller_id(current_user)
    ride = await ride_service.cancel_ride(db, rideId, data, caller_id)

    # Notify assigned driver if there is one
    if ride.driver_id:
        ws_event = {
            "type": "RideCancelled",
            "data": {
                "rideId": ride.ride_guid,
                "status": RideStatus.CANCELLED.value,
                "cancelledBy": data.cancelledBy,
                "reasonCode": data.reasonCode,
                "updatedAtUtc": data.cancelledAtUtc.isoformat(),
            },
        }
        await manager.send_to_driver(ride.driver_id, ws_event)

    await publisher.publish(
        "ride.cancelled",
        {"event_type": "ride.cancelled", "rideId": ride.ride_guid, "cancelledBy": data.cancelledBy},
    )

    return CancelRideResponse(rideId=ride.ride_guid, status=ride.status)


# ---------------------------------------------------------------------------
# GET /api/rides/{rideId}
# ---------------------------------------------------------------------------

@router.get("/{rideId}", response_model=RideSessionResponse)
async def get_ride(
    rideId: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Return the current ride session."""
    caller_id = _get_caller_id(current_user)
    ride = await ride_service.get_ride(db, rideId)

    # Only the rider or the assigned driver may read the ride session
    if ride.rider_id != caller_id and ride.driver_id != caller_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="forbidden")

    driver_location = None
    if ride.driver_current_latitude is not None and ride.driver_current_longitude is not None:
        driver_location = GeoLocation(
            latitude=ride.driver_current_latitude,
            longitude=ride.driver_current_longitude,
        )

    return RideSessionResponse(
        rideId=ride.ride_guid,
        riderId=ride.rider_id,
        driverId=ride.driver_id,
        riderName=ride.rider_name,
        riderPhoneNumber=ride.rider_phone_number,
        driverName=ride.driver_name,
        driverPhoneNumber=ride.driver_phone_number,
        vehicleInfo=ride.vehicle_info,
        startLocation=GeoLocation(latitude=ride.start_latitude, longitude=ride.start_longitude),
        startAddress=ride.start_address,
        destinationLocation=GeoLocation(latitude=ride.destination_latitude, longitude=ride.destination_longitude),
        destinationAddress=ride.destination_address,
        riderOfferAmount=float(ride.rider_offer_amount),
        recommendedAmount=float(ride.recommended_amount),
        acceptedAmount=float(ride.accepted_amount) if ride.accepted_amount is not None else None,
        selectedOfferId=str(ride.selected_offer_id) if ride.selected_offer_id else None,
        distanceKm=ride.distance_km,
        estimatedMinutes=ride.estimated_minutes,
        driverEtaMinutes=ride.driver_eta_minutes,
        driverCurrentLocation=driver_location,
        driverStatusNote=ride.driver_status_note,
        riderRating=ride.rider_rating,
        riderFeedback=ride.rider_feedback,
        requestedAtUtc=ride.requested_at_utc,
        acceptedAtUtc=ride.accepted_at_utc,
        completedAtUtc=ride.completed_at_utc,
        status=ride.status,
    )


# ---------------------------------------------------------------------------
# GET /api/rides/{rideId}/status
# ---------------------------------------------------------------------------

@router.get("/{rideId}/status", response_model=RideStatusResponse)
async def get_ride_status(
    rideId: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Return current ride state for polling fallback."""
    caller_id = _get_caller_id(current_user)
    ride = await ride_service.get_ride(db, rideId)

    if ride.rider_id != caller_id and ride.driver_id != caller_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="forbidden")

    updated_at = (
        ride.completed_at_utc
        or ride.cancelled_at_utc
        or ride.accepted_at_utc
        or ride.requested_at_utc
    )
    return RideStatusResponse(rideId=ride.ride_guid, status=ride.status, updatedAtUtc=updated_at)


# ---------------------------------------------------------------------------
# GET /api/rides/{rideId}/track
# ---------------------------------------------------------------------------

@router.get("/{rideId}/track", response_model=RideTrackResponse)
async def track_ride(
    rideId: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Return the driver's latest known location for polling fallback."""
    caller_id = _get_caller_id(current_user)
    ride = await ride_service.get_ride(db, rideId)

    if ride.rider_id != caller_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="forbidden")

    if ride.driver_id is None or ride.driver_current_latitude is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Driver location not yet available",
        )

    return RideTrackResponse(
        rideId=ride.ride_guid,
        driverId=ride.driver_id,
        currentLocation=GeoLocation(
            latitude=ride.driver_current_latitude,
            longitude=ride.driver_current_longitude,
        ),
        etaMinutes=ride.driver_eta_minutes,
        distanceToPickupKm=None,
        updatedAtUtc=ride.created_at,
    )


# ---------------------------------------------------------------------------
# POST /api/rides/{rideId}/sos
# ---------------------------------------------------------------------------

@router.post("/{rideId}/sos", response_model=SosResponse, status_code=status.HTTP_201_CREATED)
async def rider_sos(
    rideId: str,
    data: RiderSosRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Create a rider-side emergency/safety incident."""
    caller_id = _get_caller_id(current_user)

    if data.riderId != caller_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="forbidden")

    incident = await ride_service.create_rider_sos(db, rideId, data, caller_id)

    # Acknowledge via WebSocket
    ack_event = {
        "type": "SosAcknowledged",
        "data": {
            "incidentId": incident.incident_id,
            "rideId": rideId,
            "status": "Received",
            "message": "Emergency alert received. Support is being notified.",
            "updatedAtUtc": incident.created_at.isoformat(),
        },
    }
    await manager.send_to_rider(data.riderId, ack_event)

    await publisher.publish(
        "ride.sos_triggered",
        {"event_type": "ride.sos_triggered", "incidentId": incident.incident_id, "triggeredBy": "Rider"},
    )

    return SosResponse(
        incidentId=incident.incident_id,
        status=incident.status,
        receivedAtUtc=incident.created_at,
    )


# ---------------------------------------------------------------------------
# POST /api/rides/rating
# ---------------------------------------------------------------------------

@router.post("/rating", response_model=RatingResponse)
async def submit_rating(
    data: RatingRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Persist rider rating after trip completion."""
    caller_id = _get_caller_id(current_user)

    if data.riderId != caller_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="forbidden")

    await ride_service.submit_rating(db, data, caller_id)

    return RatingResponse(rideId=data.rideId, ratingSaved=True)
