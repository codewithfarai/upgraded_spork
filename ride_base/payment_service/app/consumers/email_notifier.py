import json
import logging
import aio_pika

logger = logging.getLogger(__name__)

async def process_email_notifications(message: aio_pika.IncomingMessage):
    async with message.process(requeue=True):
        data = json.loads(message.body)
        logger.info(f"Email notification processed event: {data.get('event_type')}")
