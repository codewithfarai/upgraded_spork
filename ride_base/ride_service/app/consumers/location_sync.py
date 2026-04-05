"""AMQP consumer for driver GPS pings relayed via the RabbitMQ MQTT plugin.

RabbitMQ MQTT plugin converts MQTT topics ↔ AMQP routing keys by
replacing '/' with '.'.  This consumer binds to the wildcard pattern
that covers all driver location topics:

    MQTT topic (driver app):   rides/driver/{driverId}/location
    AMQP routing key:          rides.driver.{driverId}.location
    Queue bound to pattern:    rides.driver.*.location

Expected JSON payload (QoS 0, fire-and-forget):
{
    "driverId": "...",
    "rideId":   "...",
    "latitude":  -17.8284,
    "longitude":  31.0490,
    "etaMinutes": 3,
    "distanceToPickupKm": 1.1,
    "updatedAtUtc": "2026-04-04T14:06:59Z"
}

On receipt:
  1. Write to Redis H3 index + location hash (write_driver_location)
  2. Publish DriverLocationUpdated event to rider's Redis pub/sub channel
     so any connected worker can relay it to the rider's WebSocket/MQTT session
"""

import json
import logging
from datetime import datetime, timezone

import aio_pika

from app.services import redis_service
from app.websocket.manager import manager

logger = logging.getLogger(__name__)


async def process_mqtt_driver_location(message: aio_pika.IncomingMessage) -> None:
    # QoS 0 pings: don't requeue on failure — stale location is worthless
    async with message.process(requeue=False):
        try:
            data = json.loads(message.body)
        except (json.JSONDecodeError, ValueError):
            logger.warning("Malformed GPS ping payload — skipping")
            return

        driver_id: str = data.get("driverId", "")
        ride_id: str = data.get("rideId", "")
        lat = data.get("latitude") or data.get("lat")
        lng = data.get("longitude") or data.get("lng")
        eta = data.get("etaMinutes", 0)

        if not driver_id or lat is None or lng is None:
            logger.warning("Incomplete MQTT GPS ping — missing driverId/lat/lng")
            return

        # Fast write to Redis + H3 index
        await redis_service.write_driver_location(driver_id, float(lat), float(lng), eta, ride_id)

        # Relay to rider if in an active ride
        if ride_id:
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

        logger.debug("MQTT GPS ping: driver %s @ (%.5f, %.5f)", driver_id, float(lat), float(lng))
