import logging
import logging.config
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app import __description__, __version__
from app.api import subscriptions, webhooks
from app.services.rabbitmq import publisher
from app.consumers.authentik_sync import process_authentik_sync
from app.consumers.db_tracker import process_db_tracking
from app.consumers.email_notifier import process_email_notifications

LOGGING_CONFIG = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "json": {
            "()": "app.logging_config.JSONFormatter",
        },
    },
    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "formatter": "json",
            "stream": "ext://sys.stderr",
        },
    },
    "root": {
        "level": "INFO",
        "handlers": ["console"],
    },
    "loggers": {
        "uvicorn": {"level": "INFO", "handlers": ["console"], "propagate": False},
        "uvicorn.access": {"level": "INFO", "handlers": ["console"], "propagate": False},
    },
}

logging.config.dictConfig(LOGGING_CONFIG)

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage startup/shutdown: connect and disconnect RabbitMQ."""
    # 1. Connect RabbitMQ
    await publisher.connect()

    # Check if the connection succeeded!
    if not publisher._connection:
        logger.error("Failed to connect to RabbitMQ on startup. Exiting...")
        raise RuntimeError("RabbitMQ connection required to start service.")

    channel = await publisher._connection.channel()
    exchange = publisher._exchange

    # 2. Setup Authentik Queue
    auth_queue = await channel.declare_queue("payment_service.authentik_sync", durable=True)
    await auth_queue.bind(exchange, routing_key="subscription.*")
    await auth_queue.consume(process_authentik_sync)

    # 3. Setup DB Tracking Queue (Listens to both subs and payments)
    db_queue = await channel.declare_queue("payment_service.db_tracking", durable=True)
    await db_queue.bind(exchange, routing_key="subscription.*")
    await db_queue.bind(exchange, routing_key="payment.*")
    await db_queue.consume(process_db_tracking)

    # 4. Setup Email Queue (Listens only to payments)
    email_queue = await channel.declare_queue("payment_service.email_notifications", durable=True)
    await email_queue.bind(exchange, routing_key="payment.*")
    await email_queue.consume(process_email_notifications)

    logger.info("Payment service started")
    yield
    await publisher.disconnect()
    logger.info("Payment service stopped")


app = FastAPI(
    title="RideBase Payment Service",
    description=__description__,
    version=__version__,
    lifespan=lifespan,
)

app.include_router(subscriptions.router, prefix="/api/v1")
app.include_router(webhooks.router, prefix="/api/v1")


@app.get("/health")
async def health():
    return {"status": "ok", "service": "payment_service", "version": __version__}
