"""RabbitMQ publisher for onboarding events.

Uses aio-pika (async) so publishing never blocks FastAPI's event loop.
Publishes to a topic exchange so other RideBase services can bind
to the routing keys they care about, e.g.:
    onboarding.driver_role_assigned
"""

import json
import logging

import aio_pika
from aio_pika.abc import AbstractRobustConnection
from aio_pika.exceptions import AMQPConnectionError

from app.config import settings

logger = logging.getLogger(__name__)


class RabbitMQPublisher:
    def __init__(self) -> None:
        self._connection: AbstractRobustConnection | None = None
        self._channel: aio_pika.Channel | None = None
        self._exchange: aio_pika.Exchange | None = None

    async def connect(self) -> None:
        """Establish a robust async connection to RabbitMQ and declare the exchange."""
        try:
            self._connection = await aio_pika.connect_robust(settings.RABBITMQ_URL)
            await self._ensure_channel()
            logger.info("Connected to RabbitMQ exchange '%s'", settings.RABBITMQ_EXCHANGE)
        except AMQPConnectionError:
            logger.error("Failed to connect to RabbitMQ at %s", settings.RABBITMQ_URL)
            self._connection = None
            self._channel = None
            self._exchange = None

    async def _ensure_channel(self) -> None:
        """Create or recreate the publish channel and re-declare the exchange."""
        if self._connection is None or self._connection.is_closed:
            raise AMQPConnectionError("RabbitMQ connection is closed")
        if self._channel is None or self._channel.is_closed:
            self._channel = await self._connection.channel()
            self._exchange = await self._channel.declare_exchange(
                settings.RABBITMQ_EXCHANGE,
                aio_pika.ExchangeType.TOPIC,
                durable=True,
            )
            logger.info("Publisher channel (re)created")

    async def disconnect(self) -> None:
        """Cleanly close the connection."""
        if self._connection and not self._connection.is_closed:
            await self._connection.close()
            logger.info("Disconnected from RabbitMQ")
        self._connection = None
        self._channel = None
        self._exchange = None

    async def publish(self, routing_key: str, message: dict) -> bool:
        """Publish a JSON message to the exchange with retries.

        Args:
            routing_key: Dot-separated key, e.g. "onboarding.driver_role_assigned"
            message: Dict payload to serialise as JSON

        Returns:
            True if published successfully, False otherwise.
        """
        max_retries = 3
        retry_delay = 1.0  # seconds

        for attempt in range(max_retries):
            # 1. Ensure connection is active
            if self._connection is None or self._connection.is_closed:
                logger.warning("RabbitMQ connection lost, attempting to reconnect (attempt %d/%d)...", attempt + 1, max_retries)
                try:
                    await self.connect()
                except Exception:
                    logger.error("Failed to establish RabbitMQ connection on attempt %d", attempt + 1)
                    if attempt < max_retries - 1:
                        await asyncio.sleep(retry_delay)
                        continue
                    return False

            if self._connection is None or self._connection.is_closed:
                logger.error("RabbitMQ connection still not available after reconnect attempt")
                if attempt < max_retries - 1:
                    await asyncio.sleep(retry_delay)
                    continue
                return False

            # 2. Try to publish
            try:
                await self._ensure_channel()
                await self._exchange.publish(
                    aio_pika.Message(
                        body=json.dumps(message).encode(),
                        content_type="application/json",
                        delivery_mode=aio_pika.DeliveryMode.PERSISTENT,
                    ),
                    routing_key=routing_key,
                )
                logger.info("Published to '%s' key '%s' on attempt %d", settings.RABBITMQ_EXCHANGE, routing_key, attempt + 1)
                return True
            except Exception:
                logger.warning("Failed to publish message to RabbitMQ (attempt %d/%d)", attempt + 1, max_retries, exc_info=True)
                if attempt < max_retries - 1:
                    await asyncio.sleep(retry_delay)
                    continue
                logger.error("Max retries reached for RabbitMQ publish")
                return False

        return False


# Module-level singleton
publisher = RabbitMQPublisher()
