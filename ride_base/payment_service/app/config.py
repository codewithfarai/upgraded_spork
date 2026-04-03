from pathlib import Path

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# Docker Swarm mounts secrets at /run/secrets/
_secrets_dir = Path("/run/secrets")


def _env_domain(target_env: str, domain_name: str) -> str:
    """Build environment-aware base domain: dev.ridebase.tech or ridebase.tech (prod)."""
    if target_env and target_env != "prod":
        return f"{target_env}.{domain_name}"
    return domain_name


class Settings(BaseSettings):
    # Base domain config (mirrors Ansible's target_env / domain_name)
    DOMAIN_NAME: str = "ridebase.tech"
    TARGET_ENV: str = "dev"

    # Authentik OIDC
    AUTHENTIK_JWKS_URL: str = ""
    AUTHENTIK_ISSUER: str = ""
    AUTHENTIK_AUDIENCE: str = "ridebase"

    # RabbitMQ
    RABBITMQ_URL: str = "amqp://guest:guest@localhost:5672/"
    RABBITMQ_EXCHANGE: str = "ridebase.events"

    # Stripe
    STRIPE_SECRET_KEY: str = ""
    STRIPE_WEBHOOK_SECRET: str = ""
    STRIPE_PRICE_ID_DRIVER: str = ""  # Single $14.99/month driver plan

    # Authentik API (for syncing is_subscribed attribute)
    AUTHENTIK_API_URL: str = ""
    AUTHENTIK_API_TOKEN: str = ""

    # Service
    SERVICE_NAME: str = "payment-service"
    FRONTEND_SUCCESS_URL: str = ""
    FRONTEND_CANCEL_URL: str = ""

    @model_validator(mode="before")
    @classmethod
    def derive_defaults(cls, values: dict) -> dict:
        """Fill in URLs from DOMAIN_NAME + TARGET_ENV when not explicitly set."""
        domain = values.get("DOMAIN_NAME", "ridebase.tech")
        env = values.get("TARGET_ENV", "dev")
        base = _env_domain(env, domain)
        auth_domain = f"auth.{base}"

        defaults = {
            "AUTHENTIK_JWKS_URL": f"https://{auth_domain}/application/o/ridebase/.well-known/jwks.json",
            "AUTHENTIK_ISSUER": f"https://{auth_domain}/application/o/ridebase/",
            "AUTHENTIK_API_URL": f"https://{auth_domain}",
            "FRONTEND_SUCCESS_URL": f"https://{base}/subscription/success",
            "FRONTEND_CANCEL_URL": f"https://{base}/subscription/cancel",
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
