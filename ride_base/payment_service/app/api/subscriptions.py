"""Driver subscription endpoints.

All routes require a valid Authentik JWT (Bearer token).
Single plan: $14.99/month driver subscription.
"""

import logging

from fastapi import APIRouter, Depends, HTTPException

from app.middleware.auth import get_current_user
from app.models.schemas import (
    CancelSubscriptionRequest,
    CheckoutSessionResponse,
    CreateCheckoutRequest,
    CustomerPortalResponse,
    SubscriptionResponse,
    SubscriptionStatus,
    SubscriptionStatusResponse,
)
from app.services.authentik import set_subscription_status
from app.services.rabbitmq import publisher
from app.services.stripe import (
    cancel_subscription,
    create_checkout_session,
    create_portal_session,
    get_customer_subscriptions,
    get_or_create_customer,
    get_subscription,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/subscriptions", tags=["subscriptions"])


def _is_active(status: str) -> bool:
    """Check if a subscription status counts as 'subscribed'."""
    return status in ("active", "trialing")


def _period(sub) -> tuple[int, int]:
    """Extract current_period_start/end from a subscription's first item.

    Stripe API 2025+ moved these fields from the Subscription to each
    SubscriptionItem.
    """
    item = sub.items.data[0] if sub.items and sub.items.data else None
    start = getattr(item, "current_period_start", 0) if item else 0
    end = getattr(item, "current_period_end", 0) if item else 0
    return start, end


# ── Create checkout session ────────────────────────────────────


@router.post("/checkout", response_model=CheckoutSessionResponse)
async def create_checkout(
    body: CreateCheckoutRequest,
    user: dict = Depends(get_current_user),
):
    """Start a Stripe Checkout flow for the driver subscription ($14.99/month)."""
    customer = get_or_create_customer(
        user_id=user["sub"],
        email=user.get("email", ""),
        name=user.get("preferred_username"),
        authentik_pk=user.get("authentik_pk"),
    )

    # Block checkout if user already has an active subscription
    existing = get_customer_subscriptions(customer.id)
    if any(_is_active(s.status) for s in existing):
        raise HTTPException(status_code=409, detail="Active subscription already exists")

    session = create_checkout_session(
        customer_id=customer.id,
        success_url=body.success_url,
        cancel_url=body.cancel_url,
    )

    return CheckoutSessionResponse(
        checkout_url=session.url,
        session_id=session.id,
    )


# ── Subscription status (simple boolean check) ────────────────


@router.get("/status", response_model=SubscriptionStatusResponse)
async def subscription_status(user: dict = Depends(get_current_user)):
    """Check if the current driver is subscribed. Returns a simple boolean."""
    customer = get_or_create_customer(
        user_id=user["sub"],
        email=user.get("email", ""),
    )
    subs = get_customer_subscriptions(customer.id)
    active_sub = next((s for s in subs if _is_active(s.status)), None)

    if active_sub:
        return SubscriptionStatusResponse(
            is_subscribed=True,
            subscription_id=active_sub.id,
            status=SubscriptionStatus(active_sub.status),
        )
    return SubscriptionStatusResponse(is_subscribed=False)


# ── List current subscriptions ─────────────────────────────────


@router.get("/", response_model=list[SubscriptionResponse])
async def list_subscriptions(user: dict = Depends(get_current_user)):
    """List the current driver's subscriptions."""
    customer = get_or_create_customer(
        user_id=user["sub"],
        email=user.get("email", ""),
    )
    subs = get_customer_subscriptions(customer.id)
    return [
        SubscriptionResponse(
            subscription_id=s.id,
            customer_id=s.customer if isinstance(s.customer, str) else s.customer.id,
            status=SubscriptionStatus(s.status),
            is_subscribed=_is_active(s.status),
            current_period_start=_period(s)[0],
            current_period_end=_period(s)[1],
            cancel_at_period_end=s.cancel_at_period_end,
        )
        for s in subs
    ]


# ── Get single subscription ───────────────────────────────────


@router.get("/{subscription_id}", response_model=SubscriptionResponse)
async def get_subscription_detail(
    subscription_id: str,
    user: dict = Depends(get_current_user),
):
    """Get details of a specific subscription."""
    sub = get_subscription(subscription_id)
    period_start, period_end = _period(sub)
    return SubscriptionResponse(
        subscription_id=sub.id,
        customer_id=sub.customer if isinstance(sub.customer, str) else sub.customer.id,
        status=SubscriptionStatus(sub.status),
        is_subscribed=_is_active(sub.status),
        current_period_start=period_start,
        current_period_end=period_end,
        cancel_at_period_end=sub.cancel_at_period_end,
    )


# ── Cancel ─────────────────────────────────────────────────────


@router.post("/{subscription_id}/cancel", response_model=SubscriptionResponse)
async def cancel(
    subscription_id: str,
    body: CancelSubscriptionRequest,
    user: dict = Depends(get_current_user),
):
    """Cancel a subscription."""
    sub = cancel_subscription(subscription_id, at_period_end=body.cancel_at_period_end)

    # If canceling immediately, sync Authentik now
    if not body.cancel_at_period_end and user.get("authentik_pk"):
        await set_subscription_status(str(user["authentik_pk"]), is_subscribed=False)

    await publisher.publish(
        routing_key="subscription.canceled",
        message={
            "event_type": "subscription.canceled",
            "user_id": user["sub"],
            "subscription_id": sub.id,
            "cancel_at_period_end": body.cancel_at_period_end,
        },
    )

    return SubscriptionResponse(
        subscription_id=sub.id,
        customer_id=sub.customer if isinstance(sub.customer, str) else sub.customer.id,
        status=SubscriptionStatus(sub.status),
        is_subscribed=_is_active(sub.status),
        current_period_start=_period(sub)[0],
        current_period_end=_period(sub)[1],
        cancel_at_period_end=sub.cancel_at_period_end,
    )


# ── Customer Portal ────────────────────────────────────────────


@router.post("/portal", response_model=CustomerPortalResponse)
async def customer_portal(user: dict = Depends(get_current_user)):
    """Generate a Stripe Customer Portal link for self-service billing."""
    customer = get_or_create_customer(
        user_id=user["sub"],
        email=user.get("email", ""),
    )
    session = create_portal_session(customer.id)
    return CustomerPortalResponse(portal_url=session.url)
