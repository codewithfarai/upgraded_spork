"""Consumers for ride-related events that affect user statistics.

- process_ride_completed: increments total rides for both rider and driver.
- process_ride_rated: updates average rating for both roles.
"""

import json
import logging
import aio_pika
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.database import _get_session_factory
from app.models.profile import UserProfile
from app.services.redis_service import sync_user_stats_to_redis

logger = logging.getLogger(__name__)

# Minimum rides before we start deviating from the initial 5.0 rating
COLD_START_THRESHOLD = 5

def _db():
    """Return a new async session context manager."""
    return _get_session_factory()()

async def process_ride_completed(message: aio_pika.IncomingMessage):
    async with message.process(requeue=True):
        data = json.loads(message.body)
        driver_id = data.get("driverId")
        rider_id = data.get("riderId")

        async with _db() as db:
            to_sync = []

            if driver_id:
                result = await db.execute(select(UserProfile).where(UserProfile.authentik_user_id == str(driver_id)))
                driver = result.scalar_one_or_none()
                if driver:
                    driver.driver_rides_count += 1
                    logger.info("Incremented driver rides for %s (Total: %s)", driver_id, driver.driver_rides_count)
                    to_sync.append((str(driver_id), "DRIVER", driver.driver_rating_avg, driver.driver_rides_count))

            if rider_id:
                result = await db.execute(select(UserProfile).where(UserProfile.authentik_user_id == str(rider_id)))
                rider = result.scalar_one_or_none()
                if rider:
                    rider.rider_rides_count += 1
                    logger.info("Incremented rider rides for %s (Total: %s)", rider_id, rider.rider_rides_count)
                    to_sync.append((str(rider_id), "RIDER", rider.rider_rating_avg, rider.rider_rides_count))

            await db.commit()

            # Sync to Redis only after successful DB commit
            for user_id, role, rating, rides in to_sync:
                await sync_user_stats_to_redis(user_id, role, rating, rides)

async def process_ride_rated(message: aio_pika.IncomingMessage):
    async with message.process(requeue=True):
        data = json.loads(message.body)
        rated_user_id = data.get("ratedUserId")
        role = data.get("role")  # "DRIVER" or "RIDER"
        rating_value = data.get("rating")

        if not rated_user_id or not role or rating_value is None:
            logger.warning("Invalid ride.rated message data: %s", data)
            return

        async with _db() as db:
            result = await db.execute(select(UserProfile).where(UserProfile.authentik_user_id == str(rated_user_id)))
            profile = result.scalar_one_or_none()

            if not profile:
                logger.warning("Rated user %s not found in onboarding DB", rated_user_id)
                return

            if role == "DRIVER":
                profile.driver_rating_count += 1
                # Only deviate from 5.0 after threshold
                if profile.driver_rides_count >= COLD_START_THRESHOLD:
                    # Rolling average: ((avg * (count-1)) + new) / count
                    old_sum = profile.driver_rating_avg * (profile.driver_rating_count - 1)
                    profile.driver_rating_avg = (old_sum + rating_value) / profile.driver_rating_count

            elif role == "RIDER":
                profile.rider_rating_count += 1
                if profile.rider_rides_count >= COLD_START_THRESHOLD:
                    old_sum = profile.rider_rating_avg * (profile.rider_rating_count - 1)
                    profile.rider_rating_avg = (old_sum + rating_value) / profile.rider_rating_count

            await db.commit()

            # Sync to Redis only after successful DB commit
            final_rating = profile.driver_rating_avg if role == "DRIVER" else profile.rider_rating_avg
            final_rides = profile.driver_rides_count if role == "DRIVER" else profile.rider_rides_count
            await sync_user_stats_to_redis(str(rated_user_id), role, final_rating, final_rides)

            logger.info("Updated %s rating for %s: %s (after %s rated rides)",
                        role, rated_user_id, final_rating,
                        profile.driver_rating_count if role == "DRIVER" else profile.rider_rating_count)
