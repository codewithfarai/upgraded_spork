import json
import logging
import aio_pika

from app.services.authentik import get_authentik_user_id_from_customer, set_subscription_status

logger = logging.getLogger(__name__)

async def process_authentik_sync(message: aio_pika.IncomingMessage):
    async with message.process(requeue=True):
        data = json.loads(message.body)
        customer_id = data.get("customer_id")
        is_subscribed = data.get("is_subscribed")

        user_id = await get_authentik_user_id_from_customer(customer_id)
        if user_id:
            await set_subscription_status(user_id, is_subscribed)
            logger.info("Synced Authentik status for %s", customer_id)
        else:
            logger.warning("No Authentik user found for customer %s", customer_id)
