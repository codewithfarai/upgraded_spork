"""Stripe webhook handler.

This endpoint does NOT require JWT auth — Stripe authenticates
via webhook signature verification instead.

On subscription state changes, syncs `is_subscribed` boolean
back to the driver's Authentik user profile.

Handles these Stripe events:
  - checkout.session.completed   → new subscription created → is_subscribed=True
  - customer.subscription.updated → status change (renewal, past_due, etc.)
  - customer.subscription.deleted → subscription ended → is_subscribed=False
  - invoice.payment_succeeded    → payment confirmed
  - invoice.payment_failed       → payment failed
"""

import asyncio
import logging

from fastapi import APIRouter, Header, HTTPException, Request, status

from app.services.rabbitmq import publisher
from app.services.stripe import verify_webhook

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/webhooks", tags=["webhooks"])


@router.post("/stripe")
async def stripe_webhook(
    request: Request,
    stripe_signature: str = Header(alias="Stripe-Signature"),
):
    """Receive and process Stripe webhook events."""
    payload = await request.body()

    if not stripe_signature:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Missing Stripe-Signature header",
        )

    event = verify_webhook(payload, stripe_signature)
    event_type = event["type"]
    data = event["data"]["object"]

    logger.info("Received Stripe webhook: %s", event_type)

    if event_type == "checkout.session.completed":
        await _handle_checkout_completed(data)
    elif event_type == "customer.subscription.updated":
        await _handle_subscription_updated(data)
    elif event_type == "customer.subscription.deleted":
        await _handle_subscription_deleted(data)
    elif event_type == "invoice.payment_succeeded":
        await _handle_payment_succeeded(data)
    elif event_type == "invoice.payment_failed":
        await _handle_payment_failed(data)
    else:
        logger.debug("Unhandled Stripe event type: %s", event_type)

    return {"status": "ok"}


# ── Event handlers ─────────────────────────────────────────────


async def _handle_checkout_completed(data) -> None:
    """A checkout session completed — driver subscribed."""
    customer_id = getattr(data, "customer", "")
    subscription_id = getattr(data, "subscription", "")

    success = await publisher.publish(
        routing_key="subscription.created",
        message={
            "event_type": "subscription.created",
            "customer_id": customer_id,
            "subscription_id": subscription_id,
            "is_subscribed": True,
        },
    )
    if not success:
        logger.error("Failed to enqueue subscription.created for %s", subscription_id)
        raise HTTPException(status_code=500, detail="Failed to enqueue event")
    logger.info("Driver subscription created: %s", subscription_id)


async def _handle_subscription_updated(data) -> None:
    """A subscription was updated (renewal, past_due, etc.)."""
    sub_status = getattr(data, "status", "")
    customer_id = getattr(data, "customer", "")
    is_subscribed = sub_status in ("active", "trialing")

    success = await publisher.publish(
        routing_key="subscription.updated",
        message={
            "event_type": "subscription.updated",
            "subscription_id": getattr(data, "id", ""),
            "customer_id": customer_id,
            "status": sub_status,
            "is_subscribed": is_subscribed,
            "cancel_at_period_end": getattr(data, "cancel_at_period_end", False),
        },
    )
    if not success:
        logger.error("Failed to enqueue subscription.updated for %s", getattr(data, "id", ""))
        raise HTTPException(status_code=500, detail="Failed to enqueue event")


async def _handle_subscription_deleted(data) -> None:
    """A subscription was fully canceled/deleted — driver no longer subscribed."""
    customer_id = getattr(data, "customer", "")

    success = await publisher.publish(
        routing_key="subscription.deleted",
        message={
            "event_type": "subscription.deleted",
            "subscription_id": getattr(data, "id", ""),
            "customer_id": customer_id,
            "is_subscribed": False,
        },
    )
    if not success:
        logger.error("Failed to enqueue subscription.deleted for %s", getattr(data, "id", ""))
        raise HTTPException(status_code=500, detail="Failed to enqueue event")
    logger.info("Driver subscription deleted: %s", getattr(data, "id", ""))


async def _handle_payment_succeeded(data) -> None:
    """An invoice payment succeeded."""
    success = await publisher.publish(
        routing_key="payment.succeeded",
        message={
            "event_type": "payment.succeeded",
            "invoice_id": getattr(data, "id", ""),
            "customer_id": getattr(data, "customer", ""),
            "customer_email": getattr(data, "customer_email", ""),
            "subscription_id": getattr(data, "subscription", ""),
            "amount_paid": getattr(data, "amount_paid", 0),
            "currency": getattr(data, "currency", "usd"),
        },
    )
    if not success:
        logger.error("Failed to enqueue payment.succeeded for %s", getattr(data, "id", ""))
        raise HTTPException(status_code=500, detail="Failed to enqueue event")


async def _handle_payment_failed(data) -> None:
    """An invoice payment failed."""
    success = await publisher.publish(
        routing_key="payment.failed",
        message={
            "event_type": "payment.failed",
            "invoice_id": getattr(data, "id", ""),
            "customer_id": getattr(data, "customer", ""),
            "customer_email": getattr(data, "customer_email", ""),
            "subscription_id": getattr(data, "subscription", ""),
            "amount_due": getattr(data, "amount_due", 0),
            "currency": getattr(data, "currency", "usd"),
        },
    )
    if not success:
        logger.error("Failed to enqueue payment.failed for %s", getattr(data, "id", ""))
        raise HTTPException(status_code=500, detail="Failed to enqueue event")
    logger.warning("Payment failed for invoice %s", getattr(data, "id", ""))
