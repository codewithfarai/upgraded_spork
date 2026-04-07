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
    """Lazy-initialize the Redis connection with health checks and retries."""
    global _redis
    if _redis is None:
        _redis = redis.from_url(
            settings.REDIS_URL,
            decode_responses=True,
            health_check_interval=30,
            retry_on_timeout=True,
        )
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
                    "from": "RideBase <verify@ridebase.tech>",
                    "to": [to_email],
                    "subject": "Your RideBase verification code",
                    "html": (
                        '<!DOCTYPE html>'
                        '<html><head><meta charset="utf-8">'
                        '<meta name="viewport" content="width=device-width,initial-scale=1.0">'
                        '</head><body style="margin:0;padding:0;background-color:#f4f4f4;font-family:Arial,Helvetica,sans-serif;">'
                        '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#f4f4f4;padding:40px 0;">'
                        '<tr><td align="center">'
                        '<table role="presentation" width="480" cellpadding="0" cellspacing="0" style="background-color:#ffffff;border-radius:12px;overflow:hidden;">'
                        '<tr><td style="padding:40px 40px 24px;text-align:center;">'
                        '<div style="width:72px;height:72px;border-radius:50%;background-color:#0D5C63;margin:0 auto 16px;line-height:72px;font-size:36px;color:#ffffff;">&#128663;</div>'
                        '<h1 style="margin:0 0 8px;font-size:22px;color:#1a1a1a;">Verify your email</h1>'
                        '</td></tr>'
                        '<tr><td style="padding:0 40px 16px;text-align:center;">'
                        '<p style="margin:0 0 24px;font-size:15px;color:#555555;">Use the code below to complete your verification.</p>'
                        f'<div style="display:inline-block;padding:14px 36px;background-color:#0D5C63;border-radius:8px;font-size:28px;letter-spacing:8px;font-weight:bold;color:#ffffff;">{code}</div>'
                        '<p style="margin:24px 0 0;font-size:13px;color:#999999;">This code expires in 10 minutes.</p>'
                        '</td></tr>'
                        '<tr><td style="padding:24px 40px;border-top:1px solid #eeeeee;text-align:center;">'
                        '<p style="margin:0;font-size:12px;color:#bbbbbb;">&copy; RideBase</p>'
                        '</td></tr>'
                        '</table></td></tr></table></body></html>'
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
