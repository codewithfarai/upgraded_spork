from enum import Enum

from pydantic import BaseModel, Field


class SubscriptionStatus(str, Enum):
    ACTIVE = "active"
    CANCELED = "canceled"
    PAST_DUE = "past_due"
    INCOMPLETE = "incomplete"
    TRIALING = "trialing"


# ── Request models ──────────────────────────────────────────────


class CreateCheckoutRequest(BaseModel):
    success_url: str | None = None
    cancel_url: str | None = None


class CancelSubscriptionRequest(BaseModel):
    cancel_at_period_end: bool = True


# ── Response models ─────────────────────────────────────────────


class CheckoutSessionResponse(BaseModel):
    checkout_url: str
    session_id: str


class SubscriptionResponse(BaseModel):
    subscription_id: str
    customer_id: str
    status: SubscriptionStatus
    is_subscribed: bool
    current_period_start: int
    current_period_end: int
    cancel_at_period_end: bool = False


class SubscriptionStatusResponse(BaseModel):
    is_subscribed: bool
    subscription_id: str | None = None
    status: SubscriptionStatus | None = None


class CustomerPortalResponse(BaseModel):
    portal_url: str


# ── RabbitMQ event models ──────────────────────────────────────


class SubscriptionEvent(BaseModel):
    event_type: str
    user_id: str
    subscription_id: str
    is_subscribed: bool
    status: SubscriptionStatus
    timestamp: str = Field(default_factory=lambda: __import__("datetime").datetime.now(
        __import__("datetime").timezone.utc
    ).isoformat())


class PaymentEvent(BaseModel):
    event_type: str
    user_id: str
    amount: int
    currency: str = "usd"
    status: str
    invoice_id: str | None = None
    timestamp: str = Field(default_factory=lambda: __import__("datetime").datetime.now(
        __import__("datetime").timezone.utc
    ).isoformat())
