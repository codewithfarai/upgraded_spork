# Payment Service API Reference

**Base URL:** `https://pay.ridebase.tech`

All endpoints under `/api/v1/subscriptions` require a valid Authentik JWT in the `Authorization: Bearer <token>` header.

---

## Health Check

| Method | URL | Auth |
|--------|-----|------|
| GET | `https://pay.ridebase.tech/health` | None |

```bash
curl https://pay.ridebase.tech/health
```

**Response:**

```json
{ "status": "ok", "service": "payment_service", "version": "0.1.0" }
```

---

## Check Subscription Status

| Method | URL | Auth |
|--------|-----|------|
| GET | `https://pay.ridebase.tech/api/v1/subscriptions/status` | Bearer JWT |

```bash
curl -H "Authorization: Bearer <Bearer>" \
  https://pay.ridebase.tech/api/v1/subscriptions/status
```

**Response:**

```json
{
  "is_subscribed": false,
  "subscription_id": null,
  "status": null
}
```

---

## Create Checkout Session

| Method | URL | Auth |
|--------|-----|------|
| POST | `https://pay.ridebase.tech/api/v1/subscriptions/checkout` | Bearer JWT |

**Request Body:**

```json
{
  "success_url": "https://ridebase.tech/subscription/success",
  "cancel_url": "https://ridebase.tech/subscription/cancel"
}
```

Both fields are optional (nullable).

```bash
curl -X POST \
  -H "Authorization: Bearer <Bearer>" \
  -H "Content-Type: application/json" \
  -d '{"success_url":"https://ridebase.tech/subscription/success","cancel_url":"https://ridebase.tech/subscription/cancel"}' \
  https://pay.ridebase.tech/api/v1/subscriptions/checkout
```

**Response:**

```json
{
  "checkout_url": "https://checkout.stripe.com/c/pay/...",
  "session_id": "cs_test_..."
}
```

Redirect the user to `checkout_url` to complete payment.

---

## List Subscriptions

| Method | URL | Auth |
|--------|-----|------|
| GET | `https://pay.ridebase.tech/api/v1/subscriptions/` | Bearer JWT |

```bash
curl -H "Authorization: Bearer <Bearer>" \
  https://pay.ridebase.tech/api/v1/subscriptions/
```

**Response:**

```json
[
  {
    "subscription_id": "sub_...",
    "customer_id": "cus_...",
    "status": "active",
    "is_subscribed": true,
    "current_period_start": 1775253000,
    "current_period_end": 1777845000,
    "cancel_at_period_end": false
  }
]
```

---

## Get Single Subscription

| Method | URL | Auth |
|--------|-----|------|
| GET | `https://pay.ridebase.tech/api/v1/subscriptions/{subscription_id}` | Bearer JWT |

```bash
curl -H "Authorization: Bearer <Bearer>" \
  https://pay.ridebase.tech/api/v1/subscriptions/sub_1234567890
```

**Response:**

```json
{
  "subscription_id": "sub_...",
  "customer_id": "cus_...",
  "status": "active",
  "is_subscribed": true,
  "current_period_start": 1775253000,
  "current_period_end": 1777845000,
  "cancel_at_period_end": false
}
```

---

## Cancel Subscription

| Method | URL | Auth |
|--------|-----|------|
| POST | `https://pay.ridebase.tech/api/v1/subscriptions/{subscription_id}/cancel` | Bearer JWT |

**Request Body:**

```json
{
  "cancel_at_period_end": true
}
```

Set `cancel_at_period_end` to `true` to cancel at end of billing period, or `false` to cancel immediately.

```bash
curl -X POST \
  -H "Authorization: Bearer <Bearer>" \
  -H "Content-Type: application/json" \
  -d '{"cancel_at_period_end":true}' \
  https://pay.ridebase.tech/api/v1/subscriptions/sub_1234567890/cancel
```

**Response:**

```json
{
  "subscription_id": "sub_...",
  "customer_id": "cus_...",
  "status": "canceled",
  "is_subscribed": false,
  "current_period_start": 1775253000,
  "current_period_end": 1777845000,
  "cancel_at_period_end": true
}
```

---

## Customer Portal

| Method | URL | Auth |
|--------|-----|------|
| POST | `https://pay.ridebase.tech/api/v1/subscriptions/portal` | Bearer JWT |

```bash
curl -X POST \
  -H "Authorization: Bearer <Bearer>" \
  https://pay.ridebase.tech/api/v1/subscriptions/portal
```

**Response:**

```json
{
  "portal_url": "https://billing.stripe.com/p/session/..."
}
```

Redirect the user to `portal_url` for self-service billing management.

---

## Stripe Webhook (backend only)

| Method | URL | Auth |
|--------|-----|------|
| POST | `https://pay.ridebase.tech/api/v1/webhooks/stripe` | Stripe-Signature header |

Not called by the frontend. Configure this URL in the Stripe Dashboard under Webhooks.

---

## Subscription Status Values

| Status | Counts as subscribed |
|--------|---------------------|
| `active` | Yes |
| `trialing` | Yes |
| `canceled` | No |
| `past_due` | No |
| `incomplete` | No |

---

## Typical Frontend Flow

1. **Check status** — `GET /api/v1/subscriptions/status` — if `is_subscribed` is `false`, show subscribe button
2. **Start checkout** — `POST /api/v1/subscriptions/checkout` with `success_url` / `cancel_url` — redirect user to `checkout_url`
3. **After redirect** — user lands on `success_url`, poll status again to confirm subscription is active
4. **Manage billing** — `POST /api/v1/subscriptions/portal` — redirect to `portal_url` (Stripe Customer Portal)
5. **Cancel** — `POST /api/v1/subscriptions/{subscription_id}/cancel`
