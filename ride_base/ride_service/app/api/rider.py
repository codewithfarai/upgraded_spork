from datetime import datetime, timezone
import logging

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.database import get_db
from app.middleware.auth import get_current_user
from app.models.schemas import (
    CancelRideRequest,
    RatingRequest,
    RideRequestCreate,
    RiderSosRequest,
    SelectOfferRequest,
)
from app.services import redis_service, ride_service
from app.services.rabbitmq import publisher
from app.websocket.manager import manager

logger = logging.getLogger(__name__)

router = APIRouter()


def _user_id(user: dict) -> str:
    uid = user.get("authentik_pk") or user.get("sub")
    if not uid:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="unauthorized")
    return str(uid)


def _ride_to_session_dict(ride) -> dict:
    return {
        "rideId": ride.ride_guid,
        "riderId": ride.rider_id,
        "driverId": ride.driver_id,
        "riderName": ride.rider_name,
        "riderPhoneNumber": ride.rider_phone_number,
        "driverName": ride.driver_name,
        "driverPhoneNumber": ride.driver_phone_number,
        "vehicleInfo": ride.vehicle_info,
        "startLocation": {"latitude": ride.start_latitude, "longitude": ride.start_longitude},
        "startAddress": ride.start_address,
        "destinationLocation": {"latitude": ride.destination_latitude, "longitude": ride.destination_longitude},
        "destinationAddress": ride.destination_address,
        "riderOfferAmount": float(ride.rider_offer_amount),
        "recommendedAmount": float(ride.recommended_amount),
        "acceptedAmount": float(ride.accepted_amount) if ride.accepted_amount is not None else None,
        "selectedOfferId": str(ride.selected_offer_id) if ride.selected_offer_id else None,
        "distanceKm": ride.distance_km,
        "estimatedMinutes": ride.estimated_minutes,
        "driverEtaMinutes": ride.driver_eta_minutes,
        "driverCurrentLocation": {
            "latitude": ride.driver_current_latitude,
            "longitude": ride.driver_current_longitude,
        } if ride.driver_current_latitude is not None else None,
        "driverStatusNote": ride.driver_status_note,
        "riderRating": ride.rider_rating,
        "riderFeedback": ride.rider_feedback,
        "requestedAtUtc": ride.requested_at_utc,
        "acceptedAtUtc": ride.accepted_at_utc,
        "completedAtUtc": ride.completed_at_utc,
        "status": ride.status,
    }


@router.post("/rides/request", status_code=status.HTTP_201_CREATED)
async def request_ride(
    data: RideRequestCreate,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    rider_id = _user_id(current_user)
    if data.riderId != rider_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="forbidden")

    ride = await ride_service.create_ride(db, data)

    # Cache ride → rider mapping for GPS relay (no Postgres lookup per ping)
    await redis_service.set_ride_rider_mapping(ride.ride_guid, ride.rider_id)

    # Broadcast to nearby drivers via H3 proximity (fallback: all connected)
    event = {
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
    await manager.broadcast_to_nearby_drivers(ride.start_latitude, ride.start_longitude, event)

    await publisher.publish("ride.requested", {
        "event_type": "ride.requested",
        "rideId": ride.ride_guid,
        "riderId": ride.rider_id,
        "offerAmount": float(ride.rider_offer_amount),
    })

    return {
        "rideRequestId": ride.ride_guid,
        "rideStatus": ride.status,
        "rideDistance": ride.distance_km,
        "estimatedWaitTime": 5,
    }


@router.post("/rides/select-offer")
async def select_offer(
    data: SelectOfferRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    rider_id = _user_id(current_user)
    if data.riderId != rider_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="forbidden")

    ride = await ride_service.select_offer(db, data)
    now = datetime.now(timezone.utc)

    # Notify the chosen driver they've been assigned
    await manager.send_to_driver(ride.driver_id, {
        "type": "RideAssignedToDriver",
        "data": {
            "rideId": ride.ride_guid,
            "selectedOfferId": data.rideOfferId,
            "acceptedAmount": float(ride.accepted_amount),
            "status": ride.status,
            "acceptedAtUtc": ride.accepted_at_utc.isoformat() if ride.accepted_at_utc else now.isoformat(),
        },
    })

    # Confirm status to rider
    await manager.send_to_rider(rider_id, {
        "type": "RideStatusUpdated",
        "data": {
            "rideId": ride.ride_guid,
            "status": ride.status,
            "statusMessage": "Driver selected. Heading to pickup now.",
            "etaMinutes": ride.driver_eta_minutes,
            "updatedAt": now.isoformat(),
        },
    })

    await publisher.publish("ride.accepted", {
        "event_type": "ride.accepted",
        "rideId": ride.ride_guid,
        "riderId": ride.rider_id,
        "driverId": ride.driver_id,
        "acceptedAmount": float(ride.accepted_amount),
    })

    return {
        "rideId": ride.ride_guid,
        "status": ride.status,
        "selectedOfferId": data.rideOfferId,
        "driverId": ride.driver_id,
        "acceptedAmount": float(ride.accepted_amount),
        "acceptedAtUtc": ride.accepted_at_utc or now,
    }


@router.post("/rides/{ride_id}/cancel")
async def cancel_ride(
    ride_id: str,
    data: CancelRideRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    rider_id = _user_id(current_user)
    ride = await ride_service.cancel_ride(db, ride_id, data, rider_id)

    if ride.driver_id:
        await manager.send_to_driver(ride.driver_id, {
            "type": "RideCancelled",
            "data": {
                "rideId": ride.ride_guid,
                "status": ride.status,
                "cancelledBy": data.cancelledBy,
                "reasonCode": data.reasonCode,
                "updatedAtUtc": data.cancelledAtUtc.isoformat(),
            },
        })

    await publisher.publish("ride.cancelled", {
        "event_type": "ride.cancelled",
        "rideId": ride.ride_guid,
        "riderId": rider_id,
        "cancelledBy": data.cancelledBy,
    })

    return {"rideId": ride.ride_guid, "status": ride.status}


@router.get("/rides/{ride_id}")
async def get_ride(
    ride_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    rider_id = _user_id(current_user)
    ride = await ride_service.get_ride(db, ride_id)
    if ride.rider_id != rider_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="forbidden")

    session = _ride_to_session_dict(ride)

    # Enrich with live Redis location (fresher than Postgres)
    if ride.driver_id:
        live = await redis_service.get_driver_location(ride.driver_id)
        if live:
            session["driverCurrentLocation"] = {"latitude": live["latitude"], "longitude": live["longitude"]}
            session["driverEtaMinutes"] = live["etaMinutes"]

    return session


@router.get("/rides/{ride_id}/status")
async def get_ride_status(
    ride_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    _user_id(current_user)
    ride = await ride_service.get_ride(db, ride_id)
    return {
        "rideId": ride.ride_guid,
        "status": ride.status,
        "updatedAtUtc": ride.accepted_at_utc or ride.requested_at_utc,
    }


@router.get("/rides/{ride_id}/track")
async def track_driver(
    ride_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    rider_id = _user_id(current_user)
    ride = await ride_service.get_ride(db, ride_id)
    if ride.rider_id != rider_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="forbidden")
    if not ride.driver_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="ride_not_found")

    # Serve from Redis (freshest data, no Postgres round-trip per poll)
    live = await redis_service.get_driver_location(ride.driver_id)
    if live:
        return {
            "rideId": ride.ride_guid,
            "driverId": ride.driver_id,
            "currentLocation": {"latitude": live["latitude"], "longitude": live["longitude"]},
            "etaMinutes": live["etaMinutes"],
            "distanceToPickupKm": None,
            "updatedAtUtc": live["updatedAt"],
        }

    # Fallback to Postgres
    if ride.driver_current_latitude is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="ride_not_found")
    return {
        "rideId": ride.ride_guid,
        "driverId": ride.driver_id,
        "currentLocation": {"latitude": ride.driver_current_latitude, "longitude": ride.driver_current_longitude},
        "etaMinutes": ride.driver_eta_minutes,
        "distanceToPickupKm": None,
        "updatedAtUtc": ride.accepted_at_utc,
    }


@router.post("/rides/{ride_id}/sos")
async def rider_sos(
    ride_id: str,
    data: RiderSosRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    rider_id = _user_id(current_user)
    incident = await ride_service.create_rider_sos(db, ride_id, data, rider_id)
    now = datetime.now(timezone.utc)

    await manager.send_to_rider(rider_id, {
        "type": "SosAcknowledged",
        "data": {
            "incidentId": incident.incident_id,
            "rideId": ride_id,
            "status": incident.status,
            "message": "Emergency alert received. Support is being notified.",
            "updatedAtUtc": now.isoformat(),
        },
    })

    await publisher.publish("ride.sos_triggered", {
        "event_type": "ride.sos_triggered",
        "incidentId": incident.incident_id,
        "rideId": ride_id,
        "triggeredBy": "Rider",
        "riderId": rider_id,
    })

    return {"incidentId": incident.incident_id, "status": incident.status, "receivedAtUtc": now}


@router.post("/rides/rating")
async def rate_driver(
    data: RatingRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    rider_id = _user_id(current_user)
    if data.riderId != rider_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="forbidden")
    await ride_service.submit_rating(db, data, rider_id)
    return {"rideId": data.rideId, "ratingSaved": True}
