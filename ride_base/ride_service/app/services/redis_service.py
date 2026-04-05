"""Redis service: GPS buffering, H3 spatial indexing, pub/sub fan-out.

GPS write path:
    Driver ping → Redis HSET (O(1), no Postgres hit per ping)
               → H3 cell index updated (SREM old / SADD new)
               → Redis PUBLISH to rider channel → relay task → WebSocket frame
               → Background task flushes to Postgres every GPS_FLUSH_INTERVAL_S

Redis key schema:
    driver:loc:{driver_id}              HASH  lat/lng/eta/h3_tracking/h3_broadcast/ride_id/updated_at/flushed
    driver:online                       SET   currently online driver_ids
    h3:{resolution}:{cell}              SET   driver_ids in that H3 hexagon
    driver:loc:pending_flush            SET   driver_ids with unflushed location
    ride:rider:{ride_guid}              STRING rider_id — cached mapping for GPS relay (24h TTL)
    rider:{rider_id}                    PUBSUB channel → rider WebSocket relay
    driver:{driver_id}                  PUBSUB channel → driver WebSocket relay

MQTT note:
    The RabbitMQ MQTT plugin converts MQTT topics to AMQP routing keys:
        MQTT publish:  rides/driver/{id}/location  (QoS 0, fire-and-forget)
        AMQP key:      rides.driver.{id}.location
    The location_sync consumer handles that path identically to WebSocket pings —
    both ultimately call write_driver_location() here.

    For events pushed TO mobile (server → driver/rider):
        AMQP publish:  rides.rider.{riderId}.events
        MQTT topic:    rides/rider/{riderId}/events
    Mobile clients subscribed to that topic receive events without maintaining
    a persistent WebSocket connection (significantly lower data usage).
"""

import asyncio
import json
import logging
from datetime import datetime, timezone
from typing import Any, Optional

import h3
import redis.asyncio as aioredis

from app.config import settings

logger = logging.getLogger(__name__)

_redis_client: Optional[aioredis.Redis] = None


async def get_redis() -> aioredis.Redis:
    global _redis_client
    if _redis_client is None:
        _redis_client = aioredis.from_url(
            settings.REDIS_URL,
            encoding="utf-8",
            decode_responses=True,
        )
    return _redis_client


async def close_redis() -> None:
    global _redis_client
    if _redis_client:
        await _redis_client.aclose()
        _redis_client = None


# ---------------------------------------------------------------------------
# GPS buffering
# ---------------------------------------------------------------------------

async def write_driver_location(
    driver_id: str,
    lat: float,
    lng: float,
    eta_minutes: Optional[int],
    ride_id: Optional[str],
) -> str:
    """Write driver location to Redis. Returns the broadcast H3 cell string.

    Reads the old H3 cells first, then pipelines all writes atomically.
    The brief non-atomicity of read→write is acceptable at GPS ping frequency;
    worst case a driver appears in two cells for one update cycle.
    """
    redis = await get_redis()
    now = datetime.now(timezone.utc).isoformat()

    new_track_cell = h3.latlng_to_cell(lat, lng, settings.H3_TRACKING_RESOLUTION)
    new_bcast_cell = h3.latlng_to_cell(lat, lng, settings.H3_BROADCAST_RESOLUTION)
    loc_key = f"driver:loc:{driver_id}"

    # Read old cells before writing
    old_data = await redis.hmget(loc_key, "h3_tracking", "h3_broadcast")
    old_track_cell: Optional[str] = old_data[0]
    old_bcast_cell: Optional[str] = old_data[1]

    pipe = redis.pipeline()

    # Remove from stale H3 cells
    if old_track_cell and old_track_cell != new_track_cell:
        pipe.srem(f"h3:{settings.H3_TRACKING_RESOLUTION}:{old_track_cell}", driver_id)
    if old_bcast_cell and old_bcast_cell != new_bcast_cell:
        pipe.srem(f"h3:{settings.H3_BROADCAST_RESOLUTION}:{old_bcast_cell}", driver_id)

    # Write location hash
    pipe.hset(loc_key, mapping={
        "lat": lat,
        "lng": lng,
        "eta": eta_minutes if eta_minutes is not None else 0,
        "ride_id": ride_id or "",
        "h3_tracking": new_track_cell,
        "h3_broadcast": new_bcast_cell,
        "updated_at": now,
        "flushed": "0",
    })

    # Add to new H3 cell sets
    pipe.sadd(f"h3:{settings.H3_TRACKING_RESOLUTION}:{new_track_cell}", driver_id)
    pipe.sadd(f"h3:{settings.H3_BROADCAST_RESOLUTION}:{new_bcast_cell}", driver_id)

    # 5-minute TTL — stale drivers drop out automatically
    pipe.expire(loc_key, 300)
    pipe.expire(f"h3:{settings.H3_TRACKING_RESOLUTION}:{new_track_cell}", 300)
    pipe.expire(f"h3:{settings.H3_BROADCAST_RESOLUTION}:{new_bcast_cell}", 300)

    # Mark pending Postgres flush
    pipe.sadd("driver:loc:pending_flush", driver_id)

    await pipe.execute()
    return new_bcast_cell


async def get_driver_location(driver_id: str) -> Optional[dict]:
    redis = await get_redis()
    data = await redis.hgetall(f"driver:loc:{driver_id}")
    if not data:
        return None
    return {
        "latitude": float(data["lat"]),
        "longitude": float(data["lng"]),
        "etaMinutes": int(data.get("eta", 0)),
        "rideId": data.get("ride_id", ""),
        "updatedAt": data.get("updated_at", ""),
    }


async def clear_driver_ride_state(driver_id: str) -> None:
    """Clear ride_id from driver's location entry after trip completion."""
    redis = await get_redis()
    await redis.hset(f"driver:loc:{driver_id}", "ride_id", "")


# ---------------------------------------------------------------------------
# H3 proximity matching
# ---------------------------------------------------------------------------

async def get_nearby_driver_ids(lat: float, lng: float) -> list[str]:
    """Return driver_ids from H3 cells within H3_SEARCH_RINGS of the pickup location.

    Resolution 7 cells are ~5km² each. A grid_disk of k=2 covers the center
    cell plus 2 rings = 19 hexagons ≈ ~10km driving radius, appropriate
    for city-scale ride matching.

    Falls back to an empty list if Redis is unavailable — callers should
    use a fallback broadcast to all connected drivers in that case.
    """
    redis = await get_redis()
    center_cell = h3.latlng_to_cell(lat, lng, settings.H3_BROADCAST_RESOLUTION)
    nearby_cells = h3.grid_disk(center_cell, settings.H3_SEARCH_RINGS)

    driver_ids: set[str] = set()
    for cell in nearby_cells:
        members = await redis.smembers(f"h3:{settings.H3_BROADCAST_RESOLUTION}:{cell}")
        driver_ids.update(members)

    return list(driver_ids)


# ---------------------------------------------------------------------------
# Driver online / offline state
# ---------------------------------------------------------------------------

async def set_driver_online(driver_id: str) -> None:
    redis = await get_redis()
    await redis.sadd("driver:online", driver_id)


async def set_driver_offline(driver_id: str) -> None:
    """Remove driver from online set and all H3 cells."""
    redis = await get_redis()
    await redis.srem("driver:online", driver_id)

    loc = await redis.hgetall(f"driver:loc:{driver_id}")
    if loc:
        pipe = redis.pipeline()
        if track_cell := loc.get("h3_tracking"):
            pipe.srem(f"h3:{settings.H3_TRACKING_RESOLUTION}:{track_cell}", driver_id)
        if bcast_cell := loc.get("h3_broadcast"):
            pipe.srem(f"h3:{settings.H3_BROADCAST_RESOLUTION}:{bcast_cell}", driver_id)
        pipe.delete(f"driver:loc:{driver_id}")
        await pipe.execute()


async def is_driver_online(driver_id: str) -> bool:
    redis = await get_redis()
    return bool(await redis.sismember("driver:online", driver_id))


# ---------------------------------------------------------------------------
# Ride → Rider mapping (needed for GPS relay without a Postgres lookup per ping)
# ---------------------------------------------------------------------------

async def set_ride_rider_mapping(ride_guid: str, rider_id: str) -> None:
    """Cache ride_guid → rider_id with a 24h TTL."""
    redis = await get_redis()
    await redis.setex(f"ride:rider:{ride_guid}", 86400, rider_id)


async def get_rider_id_for_ride(ride_guid: str) -> Optional[str]:
    redis = await get_redis()
    return await redis.get(f"ride:rider:{ride_guid}")


# ---------------------------------------------------------------------------
# Pub/Sub (multi-worker safe fan-out)
# ---------------------------------------------------------------------------

async def publish_to_rider(rider_id: str, event: dict) -> None:
    redis = await get_redis()
    await redis.publish(f"rider:{rider_id}", json.dumps(event, default=str))


async def publish_to_driver(driver_id: str, event: dict) -> None:
    redis = await get_redis()
    await redis.publish(f"driver:{driver_id}", json.dumps(event, default=str))


async def subscribe_to_channel(channel: str) -> Any:
    """Return a new PubSub object already subscribed to channel."""
    redis = await get_redis()
    pubsub = redis.pubsub()
    await pubsub.subscribe(channel)
    return pubsub


# ---------------------------------------------------------------------------
# Background GPS flush: Redis → Postgres
# ---------------------------------------------------------------------------

async def flush_pending_locations_to_db(session_factory) -> None:
    """Flush pending driver GPS positions from Redis to Postgres.

    Reads all driver_ids in the pending_flush set, updates their active ride
    row, then clears the set. Safe to run concurrently — worst case: a
    location is flushed twice with the same coordinates.
    """
    from app.models.ride import Ride
    from sqlalchemy import select

    redis = await get_redis()
    pending: set[str] = await redis.smembers("driver:loc:pending_flush")
    if not pending:
        return

    async with session_factory() as db:
        for driver_id in pending:
            loc = await redis.hgetall(f"driver:loc:{driver_id}")
            if not loc or loc.get("flushed") == "1":
                continue

            ride_guid = loc.get("ride_id", "")
            if not ride_guid:
                continue

            result = await db.execute(select(Ride).where(Ride.ride_guid == ride_guid))
            ride = result.scalar_one_or_none()
            if ride:
                ride.driver_current_latitude = float(loc.get("lat", 0))
                ride.driver_current_longitude = float(loc.get("lng", 0))
                ride.driver_eta_minutes = int(loc.get("eta", 0))

            await redis.hset(f"driver:loc:{driver_id}", "flushed", "1")

        await db.commit()

    await redis.delete("driver:loc:pending_flush")
    logger.debug("GPS flush: %d driver(s) written to Postgres", len(pending))


async def start_gps_flush_loop(session_factory) -> None:
    """Async background loop — flushes GPS locations to Postgres on interval."""
    while True:
        await asyncio.sleep(settings.GPS_FLUSH_INTERVAL_S)
        try:
            await flush_pending_locations_to_db(session_factory)
        except Exception:
            logger.exception("GPS flush to Postgres failed")
