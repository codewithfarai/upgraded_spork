from datetime import datetime, timezone
import logging

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.database import get_db
from app.middleware.auth import get_current_user
from app.models.schemas import (
    DriverAcceptRequest,
    DriverAvailabilityUpdate,
    DriverCompleteRequest,
    DriverCounterOfferRequest,
    DriverLocationUpdateRequest,
    DriverSosRequest,
    DriverStatusUpdate,
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


@router.post("/drivers/availability")
async def set_availability(
    data: DriverAvailabilityUpdate,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    driver_id = _user_id(current_user)
    if data.driverId != driver_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="forbidden")

    await ride_service.upsert_driver_availability(db, driver_id, data.isOnline, data.updatedAtUtc)

    if data.isOnline:
        await redis_service.set_driver_online(driver_id)
    else:
        await redis_service.set_driver_offline(driver_id)

    return {"driverId": driver_id, "isOnline": data.isOnline}


@router.post("/rides/driver/accept")
async def driver_accept(
    data: DriverAcceptRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    driver_id = _user_id(current_user)
    if data.driverId != driver_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="forbidden")

    ride = await ride_service.driver_accept_offer(db, data)
    return {"rideId": ride.ride_guid, "status": ride.status}


@router.post("/rides/driver-counter-offer")
async def driver_counter_offer(
    data: DriverCounterOfferRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    driver_id = _user_id(current_user)
    if data.driverId != driver_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="forbidden")

    offer = await ride_service.create_driver_counter_offer(db, data)
    ride = await ride_service.get_ride(db, data.rideId)

    # Notify rider of new offer in realtime
    await manager.send_to_rider(ride.rider_id, {
        "type": "RiderOfferReceived",
        "data": {
            "rideOfferId": str(offer.id),
            "rideId": ride.ride_guid,
            "offerAmount": float(offer.offer_amount),
            "riderOfferAmount": float(offer.rider_offer_amount),
            "recommendedAmount": float(offer.recommended_amount),
            "isCounterOffer": offer.is_counter_offer,
            "etaToPickupMinutes": offer.eta_to_pickup_minutes,
            "distance": offer.distance_km,
            "pickupAddress": offer.pickup_address,
            "destinationAddress": offer.destination_address,
            "pickupLocation": {"latitude": offer.pickup_latitude, "longitude": offer.pickup_longitude},
            "destinationLocation": {"latitude": offer.destination_latitude, "longitude": offer.destination_longitude},
            "offerTime": offer.offer_time_utc.isoformat(),
            "driver": {
                "driverId": driver_id,
                "name": offer.driver_name,
                "phoneNumber": offer.driver_phone_number,
                "rating": offer.driver_rating,
                "ridesCompleted": offer.driver_rides_completed,
                "vehicle": offer.driver_vehicle,
            },
        },
    })

    return {"rideOfferId": str(offer.id), "status": "OfferCountered"}


@router.post("/rides/{ride_id}/status")
async def update_ride_status(
    ride_id: str,
    data: DriverStatusUpdate,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    driver_id = _user_id(current_user)
    if data.driverId != driver_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="forbidden")

    ride = await ride_service.update_driver_ride_status(db, ride_id, driver_id, data)

    await manager.send_to_rider(ride.rider_id, {
        "type": "RideStatusUpdated",
        "data": {
            "rideId": ride.ride_guid,
            "status": ride.status,
            "statusMessage": data.statusMessage or f"Ride status: {ride.status}",
            "etaMinutes": data.etaMinutes,
            "updatedAt": data.updatedAtUtc.isoformat(),
        },
    })

    await publisher.publish("ride.status_updated", {
        "event_type": "ride.status_updated",
        "rideId": ride.ride_guid,
        "status": ride.status,
        "driverId": driver_id,
    })

    return {"rideId": ride.ride_guid, "status": ride.status}


@router.post("/rides/{ride_id}/driver-location")
async def update_driver_location(
    ride_id: str,
    data: DriverLocationUpdateRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Fast-path GPS ping: writes to Redis only.

    No Postgres hit per ping — the background flush loop handles persistence.
    H3 cell index is updated atomically in Redis.
    """
    driver_id = _user_id(current_user)
    if data.driverId != driver_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="forbidden")

    await redis_service.write_driver_location(
        driver_id,
        data.currentLocation.latitude,
        data.currentLocation.longitude,
        data.etaMinutes,
        ride_id,
    )

    # Look up rider_id from the cached Redis mapping (avoids Postgres SELECT per ping)
    rider_id = await redis_service.get_rider_id_for_ride(ride_id)
    if rider_id:
        await manager.send_to_rider(rider_id, {
            "type": "DriverLocationUpdated",
            "data": {
                "rideId": ride_id,
                "driverId": driver_id,
                "currentLocation": {
                    "latitude": data.currentLocation.latitude,
                    "longitude": data.currentLocation.longitude,
                },
                "etaMinutes": data.etaMinutes,
                "distanceToPickupKm": data.distanceToPickupKm,
                "updatedAtUtc": data.updatedAtUtc.isoformat(),
            },
        })

    return {"rideId": ride_id, "accepted": True}


@router.post("/rides/{ride_id}/complete")
async def complete_ride(
    ride_id: str,
    data: DriverCompleteRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    driver_id = _user_id(current_user)
    if data.driverId != driver_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="forbidden")

    ride = await ride_service.complete_ride(db, ride_id, driver_id, data)

    await manager.send_to_rider(ride.rider_id, {
        "type": "RideStatusUpdated",
        "data": {
            "rideId": ride.ride_guid,
            "status": ride.status,
            "statusMessage": "Your trip has been completed.",
            "etaMinutes": 0,
            "updatedAt": data.completedAtUtc.isoformat(),
        },
    })

    # Clear ride_id from driver's H3 location entry — driver stays online/indexed
    await redis_service.clear_driver_ride_state(driver_id)

    await publisher.publish("ride.completed", {
        "event_type": "ride.completed",
        "rideId": ride.ride_guid,
        "driverId": driver_id,
        "riderId": ride.rider_id,
        "completedAtUtc": data.completedAtUtc.isoformat(),
    })

    return {"rideId": ride.ride_guid, "status": ride.status}


@router.post("/rides/driver-sos")
async def driver_sos(
    data: DriverSosRequest,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    driver_id = _user_id(current_user)
    if data.driverId != driver_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="forbidden")

    incident = await ride_service.create_driver_sos(db, data)
    now = datetime.now(timezone.utc)

    await manager.send_to_driver(driver_id, {
        "type": "SosAcknowledged",
        "data": {
            "incidentId": incident.incident_id,
            "rideId": data.rideId,
            "status": incident.status,
            "message": "Emergency alert received. Support is being notified.",
            "updatedAtUtc": now.isoformat(),
        },
    })

    await publisher.publish("ride.sos_triggered", {
        "event_type": "ride.sos_triggered",
        "incidentId": incident.incident_id,
        "rideId": data.rideId,
        "triggeredBy": "Driver",
        "driverId": driver_id,
        "riderId": data.riderId,
    })

    return {"incidentId": incident.incident_id, "status": incident.status, "receivedAtUtc": now}


@router.get("/drivers/{driver_id}/open-requests")
async def get_open_requests(
    driver_id: str,
    current_user: dict = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    auth_id = _user_id(current_user)
    if driver_id != auth_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="forbidden")

    rides = await ride_service.get_open_requests_for_driver(db)
    return [
        {
            "rideId": r.ride_guid,
            "driverId": r.driver_id,
            "riderId": r.rider_id,
            "riderName": r.rider_name,
            "riderPhoneNumber": r.rider_phone_number,
            "offerAmount": float(r.rider_offer_amount),
            "recommendedAmount": float(r.recommended_amount),
            "pickupAddress": r.start_address,
            "destinationAddress": r.destination_address,
            "etaToPickupMinutes": None,
            "distanceToPickupKm": None,
            "status": r.status,
            "startLocation": {"latitude": r.start_latitude, "longitude": r.start_longitude},
            "destinationLocation": {"latitude": r.destination_latitude, "longitude": r.destination_longitude},
        }
        for r in rides
    ]
