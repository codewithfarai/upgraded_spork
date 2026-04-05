"""WebSocket connection registry with Redis pub/sub fan-out.

Each worker only tracks which WebSocket connections are local to it.
All event delivery is routed through Redis PUBLISH so that any worker
(or future replica) can push events to any connected client.

Scaling note
------------
Supports horizontal scaling: multiple uvicorn workers or Docker Swarm
replicas with a shared Redis instance.  Scale via additional Swarm
replicas rather than multiple uvicorn workers per container (asyncio
event loop is not fork-safe with open WebSocket connections).

MQTT / mobile data note (Zimbabwe context)
------------------------------------------
Enable the RabbitMQ MQTT plugin for low-data mobile clients:

    rabbitmq-plugins enable rabbitmq_mqtt

Mobile clients connect via lightweight MQTT instead of WebSocket:
- QoS 0 for GPS pings (fire-and-forget, no ACK overhead)
- QoS 1 for status events (persistent session, guaranteed delivery)

AMQP ↔ MQTT topic mapping:
    rides/driver/{id}/location  ↔  rides.driver.{id}.location  (driver → server)
    rides/rider/{id}/events     ↔  rides.rider.{id}.events     (server → rider)
    rides/driver/{id}/events    ↔  rides.driver.{id}.events    (server → driver)

Server-side logic is unchanged — send_to_rider / send_to_driver still
publish to Redis channels; the MQTT plugin picks them up from bound
AMQP queues and forwards to mobile MQTT subscribers.
"""

import asyncio
import logging

from fastapi import WebSocket

from app.services import redis_service

logger = logging.getLogger(__name__)


class ConnectionManager:

    def __init__(self) -> None:
        self._rider_sockets: dict[str, WebSocket] = {}
        self._driver_sockets: dict[str, WebSocket] = {}
        self._relay_tasks: dict[str, asyncio.Task] = {}

    # ------------------------------------------------------------------
    # Connect / disconnect
    # ------------------------------------------------------------------

    async def connect_rider(self, rider_id: str, ws: WebSocket) -> None:
        self._rider_sockets[rider_id] = ws
        self._relay_tasks[f"rider:{rider_id}"] = asyncio.create_task(
            self._relay_channel(f"rider:{rider_id}", ws, rider_id, "rider")
        )
        logger.info("Rider %s connected via WebSocket", rider_id)

    async def connect_driver(self, driver_id: str, ws: WebSocket) -> None:
        self._driver_sockets[driver_id] = ws
        self._relay_tasks[f"driver:{driver_id}"] = asyncio.create_task(
            self._relay_channel(f"driver:{driver_id}", ws, driver_id, "driver")
        )
        logger.info("Driver %s connected via WebSocket", driver_id)

    def disconnect_rider(self, rider_id: str) -> None:
        self._rider_sockets.pop(rider_id, None)
        task = self._relay_tasks.pop(f"rider:{rider_id}", None)
        if task:
            task.cancel()
        logger.info("Rider %s disconnected", rider_id)

    def disconnect_driver(self, driver_id: str) -> None:
        self._driver_sockets.pop(driver_id, None)
        task = self._relay_tasks.pop(f"driver:{driver_id}", None)
        if task:
            task.cancel()
        logger.info("Driver %s disconnected", driver_id)

    # ------------------------------------------------------------------
    # Redis pub/sub → WebSocket relay
    # ------------------------------------------------------------------

    async def _relay_channel(
        self, channel: str, ws: WebSocket, user_id: str, role: str
    ) -> None:
        """Subscribe to a Redis channel and forward every message to the WebSocket.

        The subscription is per-connection; when the WebSocket disconnects
        (or the task is cancelled), we unsubscribe and close the pubsub object.
        """
        pubsub = await redis_service.subscribe_to_channel(channel)
        try:
            async for message in pubsub.listen():
                if message["type"] == "message":
                    await ws.send_text(message["data"])
        except Exception:
            logger.debug("Relay ended for %s %s", role, user_id)
        finally:
            try:
                await pubsub.unsubscribe(channel)
                await pubsub.aclose()
            except Exception:
                pass

    # ------------------------------------------------------------------
    # Event delivery — works regardless of which worker holds the socket
    # ------------------------------------------------------------------

    async def send_to_rider(self, rider_id: str, event: dict) -> None:
        await redis_service.publish_to_rider(rider_id, event)

    async def send_to_driver(self, driver_id: str, event: dict) -> None:
        await redis_service.publish_to_driver(driver_id, event)

    async def broadcast_to_nearby_drivers(
        self, pickup_lat: float, pickup_lng: float, event: dict
    ) -> None:
        """Broadcast only to drivers within H3 proximity of the pickup.

        Resolution 7 grid_disk k=2 ≈ 19 hexagons ≈ 10km radius.
        Falls back to all locally connected drivers when H3 index is empty
        (cold start, or drivers that haven't published a GPS ping yet).
        """
        driver_ids = await redis_service.get_nearby_driver_ids(pickup_lat, pickup_lng)

        if not driver_ids:
            for driver_id in list(self._driver_sockets.keys()):
                await redis_service.publish_to_driver(driver_id, event)
            return

        for driver_id in driver_ids:
            await redis_service.publish_to_driver(driver_id, event)

    # ------------------------------------------------------------------
    # Queries (local worker only)
    # ------------------------------------------------------------------

    def is_driver_connected_locally(self, driver_id: str) -> bool:
        return driver_id in self._driver_sockets

    def is_rider_connected_locally(self, rider_id: str) -> bool:
        return rider_id in self._rider_sockets


# Module-level singleton
manager = ConnectionManager()
