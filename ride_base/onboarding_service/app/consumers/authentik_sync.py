"""Consumers that sync onboarding state to Authentik in the background.

- process_driver_role_sync: adds user to ridebase_drivers group
- process_email_verified_sync: sets email_verified=true attribute on user
- process_send_otp_email: sends OTP verification email via Resend
"""

import json
import logging
import aio_pika

from app.services.authentik import add_user_to_driver_group, set_email_verified
from app.services.otp import send_otp_email

logger = logging.getLogger(__name__)


async def process_driver_role_sync(message: aio_pika.IncomingMessage):
    async with message.process(requeue=True):
        data = json.loads(message.body)
        authentik_user_id = data.get("authentik_user_id")

        if not authentik_user_id:
            logger.warning("Missing authentik_user_id in driver role event, skipping.")
            return

        success = await add_user_to_driver_group(authentik_user_id)
        if success:
            logger.info("Driver role synced to Authentik for user %s", authentik_user_id)
        else:
            logger.error("Failed to sync driver role for user %s", authentik_user_id)
            raise RuntimeError(f"Failed to sync Authentik driver group for {authentik_user_id}")


async def process_email_verified_sync(message: aio_pika.IncomingMessage):
    async with message.process(requeue=True):
        data = json.loads(message.body)
        authentik_user_id = data.get("authentik_user_id")

        if not authentik_user_id:
            logger.warning("Missing authentik_user_id in email_verified event, skipping.")
            return

        success = await set_email_verified(authentik_user_id, verified=True)
        if success:
            logger.info("email_verified synced to Authentik for user %s", authentik_user_id)
        else:
            logger.error("Failed to sync email_verified for user %s", authentik_user_id)
            raise RuntimeError(f"Failed to sync email_verified for {authentik_user_id}")


async def process_send_otp_email(message: aio_pika.IncomingMessage):
    async with message.process(requeue=True):
        data = json.loads(message.body)
        email = data.get("email")
        code = data.get("code")

        if not email or not code:
            logger.warning("Missing email or code in send_otp_email event, skipping.")
            return

        success = await send_otp_email(email, code)
        if success:
            logger.info("OTP email sent to %s", email)
        else:
            logger.error("Failed to send OTP email to %s", email)
            raise RuntimeError(f"Failed to send OTP email to {email}")
