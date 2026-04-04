"""Consumer that syncs driver role to Authentik in the background.

Listens to onboarding.driver_role_assigned events and adds the user
to the ridebase_drivers group in Authentik without blocking the API.
"""

import json
import logging
import aio_pika

from app.services.authentik import add_user_to_driver_group

logger = logging.getLogger(__name__)


async def process_driver_role_sync(message: aio_pika.IncomingMessage):
    async with message.process(requeue=True):
        data = json.loads(message.body)
        authentik_user_id = data.get("authentik_user_id")

        if not authentik_user_id:
            logger.warning("Missing authentik_user_id in driver role event, skipping.")
            return

        success = await add_user_to_driver_group(authentik_user_id)
        if success:
            logger.info("Driver role synced to Authentik for user %s", authentik_user_id)
        else:
            logger.error("Failed to sync driver role for user %s", authentik_user_id)
            raise RuntimeError(f"Failed to sync Authentik driver group for {authentik_user_id}")
