"""RabbitMQ publisher for ride service events.

Routing keys published by this service:
    ride.requested          — new ride request created
    ride.offer_received     — driver submitted an offer
    ride.accepted           — rider accepted a driver offer
    ride.status_updated     — ride status changed
    ride.completed          — trip completed
    ride.cancelled          — ride cancelled
    ride.sos_triggered      — SOS incident created
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
        try:
            self._connection = await aio_pika.connect_robust(settings.RABBITMQ_URL)
            channel = await self._connection.channel()
            self._exchange = await channel.declare_exchange(
                settings.RABBITMQ_EXCHANGE,
                aio_pika.ExchangeType.TOPIC,
                durable=True,
            )
            logger.info("Connected to RabbitMQ exchange '%s'", settings.RABBITMQ_EXCHANGE)
        except AMQPConnectionError:
            logger.error("Failed to connect to RabbitMQ at %s", settings.RABBITMQ_URL)
            self._connection = None
            self._exchange = None

    async def disconnect(self) -> None:
        if self._connection and not self._connection.is_closed:
            await self._connection.close()
            logger.info("Disconnected from RabbitMQ")
        self._connection = None
        self._exchange = None

    async def publish(self, routing_key: str, message: dict) -> bool:
        if self._exchange is None:
            logger.error("RabbitMQ exchange not available — was connect() called?")
            return False
        try:
            await self._exchange.publish(
                aio_pika.Message(
                    body=json.dumps(message, default=str).encode(),
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


publisher = RabbitMQPublisher()
