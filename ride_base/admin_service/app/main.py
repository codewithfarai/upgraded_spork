import logging
import logging.config
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app import __description__, __version__
from app.api import endpoints
from app.config import settings

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


from app.services.rabbitmq import publisher

@asynccontextmanager
async def lifespan(app: FastAPI):
    # 1. Connect RabbitMQ
    await publisher.connect()

    if not publisher._connection:
        logger.error("Failed to connect to RabbitMQ on startup. Service will start, but background tasks may fail until connection is established.")

    logger.info("Admin service started")
    yield
    await publisher.disconnect()
    logger.info("Admin service stopped")


app = FastAPI(
    title="RideBase Admin/Fleet Service",
    description=__description__,
    version=__version__,
    lifespan=lifespan,
)

app.include_router(endpoints.router, prefix="/api/v1/fleet", tags=["fleet"])


@app.get("/health")
async def health():
    return {"status": "ok", "service": settings.SERVICE_NAME, "version": __version__}
