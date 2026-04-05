"""Email OTP service.

Generates a 6-digit code, stores it in Redis with TTL,
and sends it via the Resend API.
"""

import logging
import secrets

import httpx
import redis.asyncio as redis

from app.config import settings

logger = logging.getLogger(__name__)

OTP_TTL_SECONDS = 600  # 10 minutes
OTP_LENGTH = 6

_redis: redis.Redis | None = None


async def get_redis() -> redis.Redis:
    """Lazy-initialize the Redis connection."""
    global _redis
    if _redis is None:
        _redis = redis.from_url(settings.REDIS_URL, decode_responses=True)
    return _redis


async def generate_otp(user_id: str) -> str:
    """Generate and store a 6-digit OTP for the given user."""
    code = "".join([str(secrets.randbelow(10)) for _ in range(OTP_LENGTH)])
    r = await get_redis()
    await r.setex(f"otp:{user_id}", OTP_TTL_SECONDS, code)
    return code


async def verify_otp(user_id: str, code: str) -> bool:
    """Verify the OTP code. Consumed on success (single use)."""
    r = await get_redis()
    stored_code = await r.get(f"otp:{user_id}")
    if stored_code is None:
        return False
    if not secrets.compare_digest(stored_code, code):
        return False
    # Consume the OTP
    await r.delete(f"otp:{user_id}")
    return True


async def send_otp_email(to_email: str, code: str) -> bool:
    """Send the OTP code via Resend."""
    if not settings.RESEND_API_KEY:
        logger.warning("RESEND_API_KEY not set. Skipping OTP email send.")
        return False

    try:
        async with httpx.AsyncClient() as client:
            resp = await client.post(
                "https://api.resend.com/emails",
                headers={
                    "Authorization": f"Bearer {settings.RESEND_API_KEY}",
                    "Content-Type": "application/json",
                },
                json={
                    "from": "RideBase <noreply@ridebase.tech>",
                    "to": [to_email],
                    "subject": "Your RideBase verification code",
                    "html": (
                        "<h2>Verify your email</h2>"
                        f"<p>Your verification code is: <strong>{code}</strong></p>"
                        "<p>This code expires in 10 minutes.</p>"
                    ),
                },
            )
            if resp.status_code == 200:
                logger.info("OTP email sent to %s", to_email)
                return True
            else:
                logger.error("Resend API error: %s %s", resp.status_code, resp.text)
                return False
    except httpx.HTTPError as e:
        logger.error("Failed to send OTP email: %s", e)
        return False
