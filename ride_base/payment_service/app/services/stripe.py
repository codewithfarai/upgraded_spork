"""Stripe integration for driver subscription management.

Single plan: $14.99/month driver subscription.

Handles:
  - Customer creation (mapped to Authentik user ID)
  - Checkout session creation
  - Subscription retrieval, cancellation
  - Customer portal sessions
  - Webhook signature verification
"""

import logging

import stripe
from fastapi import HTTPException, status

from app.config import settings

logger = logging.getLogger(__name__)

# Initialise Stripe with the secret key
stripe.api_key = settings.STRIPE_SECRET_KEY


# ── Customer management ─────────────────────────────────────────


def get_or_create_customer(
    user_id: str, email: str, name: str | None = None, authentik_pk: int | None = None,
) -> stripe.Customer:
    """Find an existing Stripe customer by Authentik user_id metadata, or create one."""
    existing = stripe.Customer.search(
        query=f"metadata['authentik_user_id']:'{user_id}'",
    )
    if existing.data:
        customer = existing.data[0]
        # Backfill authentik_pk if missing
        if authentik_pk and not getattr(getattr(customer, "metadata", None), "authentik_pk", None):
            stripe.Customer.modify(customer.id, metadata={"authentik_pk": str(authentik_pk)})
        return customer

    metadata = {"authentik_user_id": user_id}
    if authentik_pk:
        metadata["authentik_pk"] = str(authentik_pk)

    customer = stripe.Customer.create(
        email=email,
        name=name,
        metadata=metadata,
    )
    logger.info("Created Stripe customer %s for user %s (pk=%s)", customer.id, user_id, authentik_pk)
    return customer


# ── Checkout ────────────────────────────────────────────────────


def create_checkout_session(
    customer_id: str,
    success_url: str | None = None,
    cancel_url: str | None = None,
) -> stripe.checkout.Session:
    """Create a Stripe Checkout Session for the driver subscription ($14.99/month)."""
    session = stripe.checkout.Session.create(
        customer=customer_id,
        mode="subscription",
        payment_method_types=["card"],
        line_items=[
            {
                "price": settings.STRIPE_PRICE_ID_DRIVER,
                "quantity": 1,
            }
        ],
        success_url=success_url or settings.FRONTEND_SUCCESS_URL,
        cancel_url=cancel_url or settings.FRONTEND_CANCEL_URL,
    )
    return session


# ── Subscription operations ────────────────────────────────────


def get_subscription(subscription_id: str) -> stripe.Subscription:
    """Retrieve a subscription from Stripe."""
    return stripe.Subscription.retrieve(subscription_id)


def get_customer_subscriptions(customer_id: str) -> list[stripe.Subscription]:
    """List all active/trialing subscriptions for a customer."""
    subs = stripe.Subscription.list(
        customer=customer_id,
        status="all",
        limit=10,
    )
    return [s for s in subs.data if s.status in ("active", "trialing", "past_due")]


def cancel_subscription(subscription_id: str, at_period_end: bool = True) -> stripe.Subscription:
    """Cancel a subscription immediately or at the end of the billing period."""
    if at_period_end:
        return stripe.Subscription.modify(
            subscription_id,
            cancel_at_period_end=True,
        )
    return stripe.Subscription.cancel(subscription_id)


# ── Customer portal ────────────────────────────────────────────


def create_portal_session(customer_id: str, return_url: str | None = None) -> stripe.billing_portal.Session:
    """Create a Stripe Customer Portal session for self-service billing."""
    return stripe.billing_portal.Session.create(
        customer=customer_id,
        return_url=return_url or settings.FRONTEND_SUCCESS_URL,
    )


# ── Webhook verification ──────────────────────────────────────


def verify_webhook(payload: bytes, sig_header: str) -> dict:
    """Verify a Stripe webhook signature and return the parsed event."""
    try:
        event = stripe.Webhook.construct_event(
            payload,
            sig_header,
            settings.STRIPE_WEBHOOK_SECRET,
        )
        return event
    except stripe.SignatureVerificationError:
        logger.warning("Invalid Stripe webhook signature")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid webhook signature",
        )
