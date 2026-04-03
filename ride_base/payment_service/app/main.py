import logging
import logging.config
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app import __description__, __version__
from app.api import subscriptions, webhooks
from app.services.rabbitmq import publisher

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
    await publisher.connect()
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
