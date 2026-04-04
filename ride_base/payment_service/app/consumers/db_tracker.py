import json
import logging
import aio_pika

logger = logging.getLogger(__name__)

async def process_db_tracking(message: aio_pika.IncomingMessage):
    async with message.process(requeue=True):
        data = json.loads(message.body)
        logger.info(f"DB tracking processed event: {data.get('event_type')}")
