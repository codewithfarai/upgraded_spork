"""WebSocket endpoint for real-time rider and driver communication.

Authentication: pass JWT as query param ?token=<jwt>

The first message from the client determines its role:
    {"type": "StartRiderMatching", ...}      → rider session
    {"type": "StartDriverRequestStream", ...} → driver session

GPS location pings (PublishDriverLocation) are written directly to
Redis without a Postgres round-trip; the background flush loop in
redis_service handles Postgres persistence every GPS_FLUSH_INTERVAL_S.

MQTT alternative
----------------
For mobile clients on constrained networks (expensive data), enable
the RabbitMQ MQTT plugin instead of WebSocket:

    rabbitmq-plugins enable rabbitmq_mqtt

Mobile apps connect on mqtt://host:1883 or mqtts://host:8883.
The same Redis pub/sub channels are used for event delivery in both paths.
See app/consumers/location_sync.py for the AMQP consumer that handles
MQTT-originated GPS pings.
"""

import logging
from datetime import datetime, timezone

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, status

from app.db.database import _get_session_factory
from app.middleware.auth import authenticate_websocket
from app.models.schemas import DriverCompleteRequest, DriverStatusUpdate
from app.services import redis_service, ride_service
from app.services.rabbitmq import publisher
from app.websocket.manager import manager

logger = logging.getLogger(__name__)

router = APIRouter()

_STATUS_MESSAGES: dict[str, str] = {
    "DriverEnRoute": "Driver is on the way.",
    "DriverArrived": "Your driver has arrived at pickup.",
    "TripStarted": "Your trip has started.",
    "TripCompleted": "Your trip has been completed.",
    "Cancelled": "Ride has been cancelled.",
}


def _db():
    """Return a new async session context manager."""
    return _get_session_factory()()


@router.websocket("/ws/rides")
async def rides_ws(ws: WebSocket):
    token = ws.query_params.get("token")
    if not token:
        await ws.close(code=status.WS_1008_POLICY_VIOLATION)
        return

    payload = await authenticate_websocket(token)
    if not payload:
        await ws.close(code=status.WS_1008_POLICY_VIOLATION)
        return

    user_id = str(payload.get("authentik_pk") or payload.get("sub", ""))
    if not user_id:
        await ws.close(code=status.WS_1008_POLICY_VIOLATION)
        return

    await ws.accept()

    try:
        first = await ws.receive_json()
        msg_type = first.get("type", "")

        if msg_type == "StartRiderMatching":
            await _rider_session(ws, user_id)
        elif msg_type == "StartDriverRequestStream":
            await _driver_session(ws, user_id)
        else:
            await ws.send_json({"type": "Error", "code": "unknown_message_type"})
            await ws.close()
    except WebSocketDisconnect:
        pass
    except Exception:
        logger.exception("WebSocket error for user %s", user_id)


# ---------------------------------------------------------------------------
# Rider session
# ---------------------------------------------------------------------------

async def _rider_session(ws: WebSocket, rider_id: str) -> None:
    await manager.connect_rider(rider_id, ws)
    try:
        while True:
            msg = await ws.receive_json()
            t = msg.get("type", "")

            if t == "AcceptOffer":
                await _ws_accept_offer(rider_id, msg)
            elif t == "Stop":
                break
            else:
                await ws.send_json({"type": "Error", "code": "unknown_message_type"})

    except WebSocketDisconnect:
        pass
    finally:
        manager.disconnect_rider(rider_id)


async def _ws_accept_offer(rider_id: str, msg: dict) -> None:
    ride_id = msg.get("rideId", "")
    offer_id = msg.get("rideOfferId", "")
    driver_id = msg.get("driverId", "")
    accepted_amount = float(msg.get("acceptedAmount", 0))

    async with _db() as db:
        try:
            ride = await ride_service.get_ride(db, ride_id)
        except Exception:
            await manager.send_to_rider(rider_id, {"type": "Error", "code": "ride_not_found"})
            return

        if ride.rider_id != rider_id:
            await manager.send_to_rider(rider_id, {"type": "Error", "code": "forbidden"})
            return

        offer = await ride_service.accept_offer_from_ws(db, ride, offer_id, driver_id, accepted_amount)
        if not offer:
            await manager.send_to_rider(rider_id, {"type": "Error", "code": "offer_not_found"})
            return

        now = datetime.now(timezone.utc)

        await manager.send_to_driver(driver_id, {
            "type": "RideAssignedToDriver",
            "data": {
                "rideId": ride.ride_guid,
                "selectedOfferId": offer_id,
                "acceptedAmount": float(ride.accepted_amount),
                "status": ride.status,
                "acceptedAtUtc": ride.accepted_at_utc.isoformat() if ride.accepted_at_utc else now.isoformat(),
            },
        })

        await manager.send_to_rider(rider_id, {
            "type": "RideStatusUpdated",
            "data": {
                "rideId": ride.ride_guid,
                "status": ride.status,
                "statusMessage": "Driver selected. Heading to pickup now.",
                "etaMinutes": None,
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


# ---------------------------------------------------------------------------
# Driver session
# ---------------------------------------------------------------------------

async def _driver_session(ws: WebSocket, driver_id: str) -> None:
    await manager.connect_driver(driver_id, ws)
    await redis_service.set_driver_online(driver_id)
    try:
        while True:
            msg = await ws.receive_json()
            t = msg.get("type", "")

            if t == "SubmitDriverOffer":
                await _ws_submit_offer(driver_id, msg)
            elif t == "UpdateRideStatus":
                await _ws_update_status(driver_id, msg)
            elif t == "PublishDriverLocation":
                await _ws_publish_location(driver_id, msg)
            elif t == "CompleteRide":
                await _ws_complete_ride(driver_id, msg)
            elif t == "Stop":
                break
            else:
                await ws.send_json({"type": "Error", "code": "unknown_message_type"})

    except WebSocketDisconnect:
        pass
    finally:
        await redis_service.set_driver_offline(driver_id)
        manager.disconnect_driver(driver_id)


async def _ws_submit_offer(driver_id: str, msg: dict) -> None:
    data = msg.get("data", {})
    ride_id = data.get("rideId", "")

    async with _db() as db:
        try:
            ride = await ride_service.get_ride(db, ride_id)
        except Exception:
            await manager.send_to_driver(driver_id, {"type": "Error", "code": "ride_not_found"})
            return

        try:
            offer = await ride_service.create_offer_from_ws(
                db, ride, data.get("rideOfferId", ""), driver_id, data
            )
        except Exception:
            await manager.send_to_driver(driver_id, {"type": "Error", "code": "invalid_counter_offer"})
            return

        driver_info = data.get("driver", {})
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
                    "name": driver_info.get("name", offer.driver_name),
                    "phoneNumber": driver_info.get("phoneNumber", offer.driver_phone_number),
                    "rating": offer.driver_rating,
                    "ridesCompleted": offer.driver_rides_completed,
                    "vehicle": offer.driver_vehicle,
                },
            },
        })


async def _ws_update_status(driver_id: str, msg: dict) -> None:
    ride_id = msg.get("rideId", "")
    new_status = msg.get("status", "")
    now = datetime.now(timezone.utc)

    data = DriverStatusUpdate(driverId=driver_id, status=new_status, updatedAtUtc=now)

    async with _db() as db:
        try:
            ride = await ride_service.update_driver_ride_status(db, ride_id, driver_id, data)
        except Exception:
            await manager.send_to_driver(driver_id, {"type": "Error", "code": "invalid_status_transition"})
            return

        await manager.send_to_rider(ride.rider_id, {
            "type": "RideStatusUpdated",
            "data": {
                "rideId": ride.ride_guid,
                "status": ride.status,
                "statusMessage": _STATUS_MESSAGES.get(ride.status, f"Ride status: {ride.status}"),
                "etaMinutes": ride.driver_eta_minutes,
                "updatedAt": now.isoformat(),
            },
        })

        await publisher.publish("ride.status_updated", {
            "event_type": "ride.status_updated",
            "rideId": ride.ride_guid,
            "status": ride.status,
            "driverId": driver_id,
        })


async def _ws_publish_location(driver_id: str, msg: dict) -> None:
    """GPS ping — fast path via Redis only. No Postgres write per ping."""
    data = msg.get("data", {})
    ride_id = data.get("rideId", "")
    loc = data.get("currentLocation", {})
    lat = loc.get("latitude")
    lng = loc.get("longitude")
    eta = data.get("etaMinutes")

    if lat is None or lng is None or not ride_id:
        return

    await redis_service.write_driver_location(driver_id, float(lat), float(lng), eta, ride_id)

    rider_id = await redis_service.get_rider_id_for_ride(ride_id)
    if rider_id:
        await manager.send_to_rider(rider_id, {
            "type": "DriverLocationUpdated",
            "data": {
                "rideId": ride_id,
                "driverId": driver_id,
                "currentLocation": {"latitude": float(lat), "longitude": float(lng)},
                "etaMinutes": eta,
                "distanceToPickupKm": data.get("distanceToPickupKm"),
                "updatedAtUtc": data.get("updatedAtUtc", datetime.now(timezone.utc).isoformat()),
            },
        })


async def _ws_complete_ride(driver_id: str, msg: dict) -> None:
    ride_id = msg.get("rideId", "")
    now = datetime.now(timezone.utc)
    data = DriverCompleteRequest(driverId=driver_id, completedAtUtc=now)

    async with _db() as db:
        try:
            ride = await ride_service.complete_ride(db, ride_id, driver_id, data)
        except Exception:
            await manager.send_to_driver(driver_id, {"type": "Error", "code": "invalid_status_transition"})
            return

        await manager.send_to_rider(ride.rider_id, {
            "type": "RideStatusUpdated",
            "data": {
                "rideId": ride.ride_guid,
                "status": ride.status,
                "statusMessage": "Your trip has been completed.",
                "etaMinutes": 0,
                "updatedAt": now.isoformat(),
            },
        })

        await redis_service.clear_driver_ride_state(driver_id)

        await publisher.publish("ride.completed", {
            "event_type": "ride.completed",
            "rideId": ride.ride_guid,
            "driverId": driver_id,
            "riderId": ride.rider_id,
        })
