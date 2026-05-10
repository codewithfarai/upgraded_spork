"""Redis service for Onboarding — used to sync driver stats for the Ride service.
"""

import logging
from typing import Optional

import redis.asyncio as redis

from app.config import settings

logger = logging.getLogger(__name__)

_redis: redis.Redis | None = None


async def get_redis() -> redis.Redis:
    """Lazy-initialize the Redis connection."""
    global _redis
    if _redis is None:
        _redis = redis.from_url(
            settings.REDIS_URL,
            decode_responses=True,
            health_check_interval=30,
            retry_on_timeout=True,
        )
    return _redis


async def sync_user_stats_to_redis(user_id: str, role: str, rating: float, rides: int) -> None:
    """Update the user's stats in Redis.

    Stats are stored in a unified user:stats:{id} hash.
    These are used by the Ride service to show ratings during offers/requests.
    """
    try:
        r = await get_redis()
        stats_key = f"user:stats:{user_id}"

        await r.hset(stats_key, mapping={
            f"{role.lower()}_rating": rating,
            f"{role.lower()}_rides": rides
        })
        # 24h TTL for stats cache
        await r.expire(stats_key, 86400)
        logger.info("Synced %s stats to Redis for %s: %s stars, %s rides", role, user_id, rating, rides)

        # If it's a driver, also update their active location hash if it exists
        if role == "DRIVER":
            loc_key = f"driver:loc:{user_id}"
            if await r.exists(loc_key):
                await r.hset(loc_key, mapping={
                    "rating": rating,
                    "rides": rides
                })
    except Exception:
        logger.exception("Failed to sync %s stats to Redis for %s", role, user_id)
