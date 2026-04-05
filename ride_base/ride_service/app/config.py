from pathlib import Path

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

_secrets_dir = Path("/run/secrets")


def _env_domain(target_env: str, domain_name: str) -> str:
    if target_env and target_env != "prod":
        return f"{target_env}.{domain_name}"
    return domain_name


class Settings(BaseSettings):
    SERVICE_NAME: str = "ride_service"

    DOMAIN_NAME: str = "ridebase.tech"
    TARGET_ENV: str = "dev"

    DATABASE_URL: str = ""

    AUTHENTIK_JWKS_URL: str = ""
    AUTHENTIK_ISSUER: str = ""
    AUTHENTIK_AUDIENCE: str = "ridebase"

    RABBITMQ_URL: str = "amqp://guest:guest@localhost:5672/"
    RABBITMQ_EXCHANGE: str = "ridebase.events"

    # Redis
    REDIS_URL: str = "redis://localhost:6379/0"

    # H3 spatial indexing
    # Resolution 9 ≈ 174m edge for driver location tracking
    # Resolution 7 ≈ 1.2km edge for broadcast radius (grid_disk k=2 ≈ 10km coverage)
    H3_TRACKING_RESOLUTION: int = 9
    H3_BROADCAST_RESOLUTION: int = 7
    H3_SEARCH_RINGS: int = 2

    # GPS flush interval from Redis → Postgres (seconds)
    GPS_FLUSH_INTERVAL_S: int = 15

    @model_validator(mode="before")
    @classmethod
    def derive_defaults(cls, values: dict) -> dict:
        domain = values.get("DOMAIN_NAME", "ridebase.tech")
        env = values.get("TARGET_ENV", "dev")
        base = _env_domain(env, domain)
        auth_domain = f"auth.{base}"

        defaults = {
            "AUTHENTIK_JWKS_URL": f"https://{auth_domain}/application/o/ridebase/.well-known/jwks.json",
            "AUTHENTIK_ISSUER": f"https://{auth_domain}/application/o/ridebase/",
        }

        for key, default_value in defaults.items():
            if not values.get(key):
                values[key] = default_value

        return values

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        secrets_dir=str(_secrets_dir) if _secrets_dir.is_dir() else None,
    )


settings = Settings()
