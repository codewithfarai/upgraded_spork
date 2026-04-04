"""RabbitMQ publisher for subscription and payment events.

Uses aio-pika (async) so publishing never blocks FastAPI's event loop.
Publishes to a topic exchange so other RideBase services can bind
to the routing keys they care about, e.g.:
    subscription.created
    subscription.canceled
    payment.succeeded
    payment.failed
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
        self._exchange: aio_pika.Exchange | None = None

    async def connect(self) -> None:
        """Establish a robust async connection to RabbitMQ and declare the exchange."""
        try:
            # RobustConnection auto-reconnects on transient failures
            self._connection = await aio_pika.connect_robust(settings.RABBITMQ_URL)
            channel = await self._connection.channel()

            # Durable topic exchange — survives broker restarts
            self._exchange = await channel.declare_exchange(
                settings.RABBITMQ_EXCHANGE,
                aio_pika.ExchangeType.TOPIC,
                durable=True,
            )
            logger.info("Connected to RabbitMQ exchange '%s'", settings.RABBITMQ_EXCHANGE)
        except AMQPConnectionError:
            logger.error("Failed to connect to RabbitMQ at %s", settings.RABBITMQ_URL)
            self._connection = None
            self._channel = None

    async def disconnect(self) -> None:
        """Cleanly close the connection."""
        if self._connection and not self._connection.is_closed:
            await self._connection.close()
            logger.info("Disconnected from RabbitMQ")
        self._connection = None
        self._exchange = None

    async def publish(self, routing_key: str, message: dict) -> bool:
        """Publish a JSON message to the exchange without blocking the event loop.

        Args:
            routing_key: Dot-separated key, e.g. "subscription.created"
            message: Dict payload to serialise as JSON

        Returns:
            True if published successfully, False otherwise.
        """
        if self._exchange is None:
            logger.error("RabbitMQ exchange not available — was connect() called?")
            return False

        try:
            await self._exchange.publish(
                aio_pika.Message(
                    body=json.dumps(message).encode(),
                    content_type="application/json",
                    delivery_mode=aio_pika.DeliveryMode.PERSISTENT,
                ),
                routing_key=routing_key,
            )
            logger.info("Published to '%s' key '%s'", settings.RABBITMQ_EXCHANGE, routing_key)
            return True
        except Exception:
            logger.exception("Failed to publish message to RabbitMQ")
            return False


# Module-level singleton
publisher = RabbitMQPublisher()
