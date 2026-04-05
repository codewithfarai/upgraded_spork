import logging
import logging.config
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app import __description__, __version__
from app.api import endpoints
from app.config import settings
from app.services.rabbitmq import publisher
from app.consumers.authentik_sync import process_driver_role_sync, process_email_verified_sync, process_send_otp_email

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

    # Fail fast if S3 credentials are missing
    if not settings.S3_ACCESS_KEY or not settings.S3_ENDPOINT_URL:
        logger.error("S3_ACCESS_KEY or S3_ENDPOINT_URL missing in environment. Exiting...")
        raise RuntimeError("S3 credentials required to start service.")

    # Fail fast if RabbitMQ is unreachable
    if not publisher._connection:
        logger.error("Failed to connect to RabbitMQ on startup. Exiting...")
        raise RuntimeError("RabbitMQ connection required to start service.")

    channel = await publisher._connection.channel()
    exchange = publisher._exchange

    # 2. Setup Authentik Sync Queue (driver role assignment)
    auth_queue = await channel.declare_queue("onboarding_service.authentik_sync", durable=True)
    await auth_queue.bind(exchange, routing_key="onboarding.driver_role_assigned")
    await auth_queue.consume(process_driver_role_sync)

    # 3. Setup Email Verified Sync Queue
    email_queue = await channel.declare_queue("onboarding_service.email_verified_sync", durable=True)
    await email_queue.bind(exchange, routing_key="onboarding.email_verified")
    await email_queue.consume(process_email_verified_sync)

    # 4. Setup OTP Email Send Queue
    otp_queue = await channel.declare_queue("onboarding_service.send_otp_email", durable=True)
    await otp_queue.bind(exchange, routing_key="onboarding.send_otp_email")
    await otp_queue.consume(process_send_otp_email)

    logger.info("Onboarding service started")
    yield
    await publisher.disconnect()
    logger.info("Onboarding service stopped")


app = FastAPI(
    title="RideBase Onboarding Service",
    description=__description__,
    version=__version__,
    lifespan=lifespan,
)

app.include_router(endpoints.router, prefix="/api/v1/onboarding", tags=["onboarding"])


@app.get("/health")
async def health():
    return {"status": "ok", "service": settings.SERVICE_NAME, "version": __version__}
