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
                        "from": "RideBase Payments <payments@ridebase.tech>",
                        "to": [recipient_email],
                        "subject": "RideBase Payment Receipt",
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
                            '<h1 style="margin:0 0 8px;font-size:22px;color:#1a1a1a;">Payment Received</h1>'
                            '</td></tr>'
                            '<tr><td style="padding:0 40px 16px;text-align:center;">'
                            '<p style="margin:0 0 24px;font-size:15px;color:#555555;">Thank you! Your payment was successful.</p>'
                            f'<div style="display:inline-block;padding:14px 36px;background-color:#0D5C63;border-radius:8px;font-size:28px;font-weight:bold;color:#ffffff;">${amount:.2f}</div>'
                            '</td></tr>'
                            '<tr><td style="padding:24px 40px;border-top:1px solid #eeeeee;text-align:center;">'
                            '<p style="margin:0;font-size:12px;color:#bbbbbb;">&copy; RideBase</p>'
                            '</td></tr>'
                            '</table></td></tr></table></body></html>'
                        )
                    }
                )

                if response.status_code == 200:
                    logger.info("Payment success email sent to %s for customer %s", recipient_email, customer_id)
                else:
                    logger.error("Failed to send email via Resend: %s", response.text)
