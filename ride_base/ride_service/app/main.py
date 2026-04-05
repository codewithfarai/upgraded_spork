import logging
import logging.config
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app import __description__, __version__
from app.api import driver, rider
from app.config import settings
from app.services.rabbitmq import publisher
from app.services.redis_service import close_redis
from app.consumers.location_sync import process_mqtt_driver_location
from app.websocket import ws

LOGGING_CONFIG = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "json": {"()": "app.logging_config.JSONFormatter"},
    },
    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "formatter": "json",
            "stream": "ext://sys.stderr",
        },
    },
    "root": {"level": "INFO", "handlers": ["console"]},
    "loggers": {
        "uvicorn": {"level": "INFO", "handlers": ["console"], "propagate": False},
        "uvicorn.access": {"level": "INFO", "handlers": ["console"], "propagate": False},
    },
}

logging.config.dictConfig(LOGGING_CONFIG)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # ── RabbitMQ ──────────────────────────────────────────────────────
    await publisher.connect()
    if not publisher._connection:
        raise RuntimeError("RabbitMQ connection required to start service.")

    channel = await publisher._connection.channel()
    exchange = publisher._exchange

    # ── MQTT GPS consumer ─────────────────────────────────────────────
    # Binds to the AMQP routing key pattern that the RabbitMQ MQTT plugin
    # generates from MQTT topic rides/driver/+/location (QoS 0).
    # Enable with: rabbitmq-plugins enable rabbitmq_mqtt
    mqtt_loc_queue = await channel.declare_queue(
        "ride_service.mqtt_driver_location", durable=True
    )
    await mqtt_loc_queue.bind(exchange, routing_key="rides.driver.*.location")
    await mqtt_loc_queue.consume(process_mqtt_driver_location)

    logger.info("Ride service started (env=%s, domain=%s)", settings.TARGET_ENV, settings.DOMAIN_NAME)
    yield

    await publisher.disconnect()
    await close_redis()
    logger.info("Ride service stopped")


app = FastAPI(
    title="RideBase Ride Service",
    description=__description__,
    version=__version__,
    lifespan=lifespan,
)

app.include_router(rider.router, prefix="/api", tags=["rider"])
app.include_router(driver.router, prefix="/api", tags=["driver"])
app.include_router(ws.router, tags=["realtime"])


@app.get("/health", tags=["health"])
async def health():
    return {"status": "ok", "service": settings.SERVICE_NAME}
