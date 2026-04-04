import json
import logging
import httpx
import aio_pika

from app.config import settings

logger = logging.getLogger(__name__)

async def process_email_notifications(message: aio_pika.IncomingMessage):
    async with message.process(requeue=True):
        data = json.loads(message.body)
        event_type = data.get('event_type')
        logger.info(f"Email notification processing event: {event_type}")

        if event_type == "payment.succeeded":
            if not settings.RESEND_API_KEY:
                logger.warning("RESEND_API_KEY not set. Skipping email send.")
                return

            customer_id = data.get("customer_id")
            amount = data.get("amount_paid", 0) / 100


            recipient_email = data.get("customer_email")

            if not recipient_email:
                logger.warning("No customer_email found in payment event for customer %s. Skipping.", customer_id)
                return

            async with httpx.AsyncClient() as client:
                response = await client.post(
                    "https://api.resend.com/emails",
                    headers={
                        "Authorization": f"Bearer {settings.RESEND_API_KEY}",
                        "Content-Type": "application/json"
                    },
                    json={
                        "from": "RideBase Payments <noreply@ridebase.tech>",
                        "to": [recipient_email],
                        "subject": "RideBase Payment Receipt",
                        "html": f"<h2>Thank you!</h2><p>Your payment of <strong>${amount:.2f}</strong> was successful.</p>"
                    }
                )

                if response.status_code == 200:
                    logger.info("Payment success email sent to %s for customer %s", recipient_email, customer_id)
                else:
                    logger.error("Failed to send email via Resend: %s", response.text)
