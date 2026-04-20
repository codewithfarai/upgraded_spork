# RideBase Platform — User Flows Overview

A complete guide to how riders, drivers, and fleet owners interact with the platform from sign-up to ride completion.

---

## Architecture at a Glance

```
┌──────────────────────────────────────────────────────────────────┐
│                        Mobile App (MAUI)                         │
│  Rider UI  ·  Driver UI  ·  Fleet Owner UI  ·  Admin Dashboard  │
└──────────┬───────────────────────────────────────────────────────┘
           │ HTTPS + WebSocket
┌──────────▼───────────────────────────────────────────────────────┐
│                     Traefik (Reverse Proxy)                       │
├──────────────────┬───────────────┬──────────────┬────────────────┤
│ auth.ridebase    │ onboarding.   │ pay.ridebase │ fleet.ridebase │
│ .tech            │ ridebase.tech │ .tech        │ .tech          │
│                  │               │              │                │
│ ┌──────────────┐ │ ┌───────────┐│ ┌──────────┐ │ ┌────────────┐ │
│ │  Authentik   │ │ │Onboarding ││ │ Payment  │ │ │   Admin    │ │
│ │  (OIDC SSO)  │ │ │ Service   ││ │ Service  │ │ │  Service   │ │
│ └──────────────┘ │ └───────────┘│ └──────────┘ │ └────────────┘ │
│                  │              │              │                │
│                  │    Ride Service (internal)   │                │
│                  │    ┌────────────────────┐    │                │
│                  │    │  Rides · Reporting │    │                │
│                  │    └────────────────────┘    │                │
├──────────────────┴──────────────┴──────────────┴────────────────┤
│ PostgreSQL (HA) · RabbitMQ · Redis · S3 (Hetzner Object Store)  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Service Responsibilities

| Service | Domain | Base URL |
|---------|--------|----------|
| **Authentik** | Identity, SSO, JWT issuance | `auth.ridebase.tech` |
| **Onboarding Service** | User profiles, driver verification, email OTP | `onboarding.ridebase.tech` |
| **Payment Service** | Stripe subscriptions ($14.99/mo driver fee) | `pay.ridebase.tech` |
| **Admin/Fleet Service** | Vehicle registration, driver assignment, invites | `fleet.ridebase.tech` |
| **Ride Service** | Ride lifecycle, WebSocket matching, driver reporting | Internal |

---

## Flow 1: Rider Sign-Up & First Ride

```mermaid
sequenceDiagram
    actor R as Rider
    participant Auth as Authentik
    participant Onb as Onboarding
    participant Ride as Ride Service

    Note over R,Auth: 1. Registration
    R->>Auth: POST /api/v3/flows/executor/ridebase-enrollment/
    Auth-->>R: Confirmation email sent
    R->>Auth: Clicks email link → account activated

    Note over R,Auth: 2. Login
    R->>Auth: POST /application/o/token/ (PKCE or password)
    Auth-->>R: access_token + refresh_token

    Note over R,Onb: 3. Onboarding
    R->>Onb: POST /api/v1/onboarding/profile {role: RIDER}
    Onb-->>R: Profile created, OTP sent
    R->>Onb: POST /api/v1/onboarding/verify-email {code: 482301}
    Onb-->>R: Email verified ✅

    Note over R,Ride: 4. Request a Ride
    R->>Ride: POST /api/rides/request {pickup, destination, offer}
    Ride-->>R: ride_guid + RIDE_REQUESTED status
    Note right of Ride: WebSocket broadcasts to all<br/>online drivers

    Note over R,Ride: 5. Driver Accepts
    Ride-->>R: WebSocket: RideAccepted {driver, amount}
    R->>Ride: GET /api/rides/{id}/track (poll driver location)

    Note over R,Ride: 6. Trip Completes
    Ride-->>R: WebSocket: TripCompleted
    R->>Ride: POST /api/rides/{id}/rate {stars, comment}
```

### Key Details

- **Auth method**: PKCE (mobile) or password grant (testing)
- **Role**: `RIDER` — no subscription required, no vehicle setup
- **OTP**: 6-digit code sent via Resend to the user's email
- The rider can also sign up via **Google OAuth** (redirect through Authentik)

---

## Flow 2: Independent Driver (Owns Their Car)

```mermaid
sequenceDiagram
    actor D as Driver
    participant Auth as Authentik
    participant Onb as Onboarding
    participant Pay as Payment
    participant Fleet as Admin/Fleet
    participant Ride as Ride Service

    Note over D,Auth: 1. Registration & Login
    D->>Auth: Register + Login (same as rider)
    Auth-->>D: access_token

    Note over D,Onb: 2. Onboarding — Identity
    D->>Onb: POST /api/v1/onboarding/profile {role: DRIVER}
    Onb-->>D: Profile created, OTP sent
    D->>Onb: POST /api/v1/onboarding/verify-email
    Onb-->>D: Email verified ✅
    D->>Onb: POST /api/v1/onboarding/driver_setup
    Note right of Onb: Uploads: national_id_photo,<br/>license_photo

    Note over D,Pay: 3. Subscription — $14.99/month
    D->>Pay: POST /api/v1/subscriptions/checkout
    Pay-->>D: checkout_url (Stripe hosted)
    D->>D: Completes Stripe payment
    Note right of Pay: Stripe webhook →<br/>payment.processed event →<br/>Authentik is_subscribed=true

    Note over D,Fleet: 4. Vehicle Registration — Self-Assign
    D->>Fleet: POST /api/v1/fleet/vehicles/self_assign
    Note right of Fleet: Registers car AND assigns<br/>driver in one call
    Fleet-->>D: vehicle_id ✅

    Note over D,Ride: 5. Go Online & Accept Rides
    D->>Ride: WebSocket connect /ws/driver/{id}
    Ride-->>D: DriverRideRequestReceived
    D->>Ride: POST /api/rides/{id}/accept {amount}
    Ride-->>D: RideAccepted

    Note over D,Ride: 6. Complete Trip
    D->>Ride: POST /api/rides/{id}/arrived
    D->>Ride: POST /api/rides/{id}/start
    D->>Ride: POST /api/rides/{id}/complete
    Ride-->>D: TripCompleted ✅

    Note over D,Ride: 7. View Earnings
    D->>Ride: GET /api/v1/reporting/driver/stats
    D->>Ride: GET /api/v1/reporting/driver/earnings?period=month
    D->>Ride: GET /api/v1/reporting/driver/earnings/daily?days=7
```

### Key Details

- **Subscription gate**: The mobile app checks `is_subscribed` from the JWT. If `false`, the driver is prompted to subscribe before going online.
- **Self-assign endpoint**: `POST /vehicles/self_assign` is the simplest path — it creates the vehicle record AND the assignment in a single transaction.
- **Identity vs vehicle**: Onboarding handles identity documents (national ID, license). Fleet Service handles the vehicle asset.

---

## Flow 3: Fleet Owner with Hired Drivers

```mermaid
sequenceDiagram
    actor FO as Fleet Owner
    actor HD as Hired Driver
    participant Auth as Authentik
    participant Fleet as Admin/Fleet
    participant Pay as Payment

    Note over FO,Auth: 1. Fleet Owner onboards as DRIVER
    FO->>Auth: Register + Login
    FO->>FO: Complete onboarding + subscription

    Note over FO,Fleet: 2. Register Fleet Vehicles
    FO->>Fleet: POST /api/v1/fleet/vehicles {car_make, plate...}
    Fleet-->>FO: vehicle_id (Vehicle 1)
    FO->>Fleet: POST /api/v1/fleet/vehicles
    Fleet-->>FO: vehicle_id (Vehicle 2)

    Note over FO,Fleet: 3. Invite a Hired Driver
    FO->>Fleet: POST /api/v1/fleet/vehicles/{id}/invite
    Fleet-->>FO: invite_token (valid 7 days)
    FO->>HD: Shares token via WhatsApp/SMS

    Note over HD,Auth: 4. Hired Driver onboards separately
    HD->>Auth: Register + Login
    HD->>HD: Complete onboarding + subscription

    Note over HD,Fleet: 5. Driver Accepts Invite
    HD->>Fleet: POST /api/v1/fleet/vehicles/accept_invite {token}
    Fleet-->>HD: "Assigned to vehicle!" ✅
    Note right of Fleet: Token burned (single-use)

    Note over FO,Fleet: 6. Fleet Management
    FO->>Fleet: GET /api/v1/fleet/vehicles (list all vehicles)
    FO->>Fleet: DELETE /api/v1/fleet/vehicles/{id}/assign
    Note right of Fleet: Revokes driver from vehicle
```

### Key Details

- **Invite tokens**: Cryptographically secure (`secrets.token_urlsafe(32)`), single-use, expire in 7 days
- **One active driver per vehicle**: A vehicle can only have one `ACTIVE` assignment at a time. The fleet owner must revoke the current driver before assigning a new one.
- **Both pay**: Both the fleet owner and the hired driver need their own $14.99/month subscription to use the platform. The subscription is per-user, not per-vehicle.

---

## Flow 4: Ride Lifecycle (Real-Time)

```mermaid
stateDiagram-v2
    [*] --> RIDE_REQUESTED: Rider requests ride
    RIDE_REQUESTED --> DRIVER_ACCEPTED: Driver accepts & sets price
    DRIVER_ACCEPTED --> DRIVER_ARRIVED: Driver arrives at pickup
    DRIVER_ARRIVED --> TRIP_STARTED: Rider gets in, trip begins
    TRIP_STARTED --> TRIP_COMPLETED: Driver marks trip done

    RIDE_REQUESTED --> CANCELLED: Rider or driver cancels
    DRIVER_ACCEPTED --> CANCELLED: Rider or driver cancels

    TRIP_STARTED --> SOS_TRIGGERED: Emergency button pressed
    SOS_TRIGGERED --> TRIP_STARTED: SOS resolved
```

### Ride Status Transitions

| Status | Who Triggers | What Happens |
|--------|-------------|--------------|
| `RIDE_REQUESTED` | Rider | Broadcasted to all online drivers via WebSocket |
| `DRIVER_ACCEPTED` | Driver | Rider notified, driver location tracking begins |
| `DRIVER_ARRIVED` | Driver | Rider gets "driver has arrived" notification |
| `TRIP_STARTED` | Driver | Trip distance tracking begins |
| `TRIP_COMPLETED` | Driver | Fare finalized, rating prompt shown |
| `CANCELLED` | Either | Cancellation reason recorded |
| `SOS_TRIGGERED` | Either | Emergency contacts notified |

### RabbitMQ Events (Ride Service)

Every status change publishes an event to the `ridebase.events` exchange:

```
ride.requested    → {ride_id, rider_id, pickup, destination}
ride.accepted     → {ride_id, driver_id, accepted_amount}
ride.completed    → {ride_id, driver_id, final_amount, distance_km}
ride.cancelled    → {ride_id, cancelled_by, reason}
ride.sos          → {ride_id, triggered_by, location}
```

---

## Flow 5: Subscription & Billing

```mermaid
sequenceDiagram
    actor D as Driver
    participant Pay as Payment Service
    participant Stripe as Stripe
    participant Auth as Authentik

    D->>Pay: GET /api/v1/subscriptions/status
    Pay-->>D: {is_subscribed: false}

    D->>Pay: POST /api/v1/subscriptions/checkout
    Pay-->>D: {checkout_url: "https://checkout.stripe.com/..."}
    D->>Stripe: Completes payment on Stripe hosted page

    Stripe->>Pay: POST /api/v1/webhooks/stripe (checkout.session.completed)
    Pay->>Auth: PATCH user attributes {is_subscribed: true}
    Pay->>Pay: Publish payment.processed event

    Note over D,Auth: Next token refresh includes is_subscribed=true

    Note over D,Pay: Monthly renewal (automatic)
    Stripe->>Pay: invoice.payment_succeeded webhook
    Pay->>Pay: Subscription stays active

    Note over D,Pay: Failed payment
    Stripe->>Pay: invoice.payment_failed webhook
    Pay->>Auth: PATCH {is_subscribed: false}
    Note right of D: Driver can't go online until resolved

    Note over D,Pay: Self-service billing
    D->>Pay: POST /api/v1/subscriptions/portal
    Pay-->>D: {portal_url: "https://billing.stripe.com/..."}
    Note right of D: Update card, view invoices, cancel
```

### Subscription States

| Stripe Status | `is_subscribed` | Can Drive? |
|---------------|----------------|------------|
| `active` | `true` | ✅ |
| `trialing` | `true` | ✅ |
| `past_due` | `false` | ❌ |
| `canceled` | `false` | ❌ |
| `incomplete` | `false` | ❌ |

---

## Flow 6: Reporting & Analytics

### Driver-Facing (in the app)

| Endpoint | What It Shows |
|----------|--------------|
| `GET /reporting/driver/stats` | Lifetime stats: total rides, earnings, avg rating, SOS count |
| `GET /reporting/driver/earnings?period=month` | Earnings for a time period (today/week/month/year) |
| `GET /reporting/driver/earnings/daily?days=7` | Day-by-day earnings breakdown chart |
| `GET /reporting/driver/rides?page=1&status=TRIP_COMPLETED` | Paginated ride history with filters |

### Platform-Wide (admin dashboard)

| Endpoint | What It Shows |
|----------|--------------|
| `GET /reporting/platform/stats?period=month` | Total rides, revenue, cancellation rate, avg rating, active SOS |

---

## RabbitMQ Event Map

All services publish to the shared `ridebase.events` topic exchange. Any service can bind a queue to consume events it cares about.

```
ridebase.events (topic exchange)
├── onboarding.*
│   ├── onboarding.profile_created
│   ├── onboarding.driver_role_assigned
│   └── onboarding.email_verified
├── payment.*
│   ├── payment.processed
│   ├── payment.subscription_cancelled
│   └── payment.subscription_renewed
├── fleet.*
│   ├── fleet.vehicle_registered
│   ├── fleet.driver_assigned
│   ├── fleet.driver_unassigned
│   ├── fleet.invite_generated
│   └── fleet.invite_accepted
└── ride.*
    ├── ride.requested
    ├── ride.accepted
    ├── ride.completed
    ├── ride.cancelled
    └── ride.sos
```

---

## Pre-Conditions & Gates

The mobile app enforces these checks to ensure a clean user experience:

```mermaid
flowchart TD
    A[App Launch] --> B{Has access_token?}
    B -- No --> C[Login / Register Screen]
    B -- Yes --> D{Profile exists?}
    D -- No --> E[Onboarding Screen]
    D -- Yes --> F{email_verified?}
    F -- No --> G[OTP Verification Screen]
    F -- Yes --> H{role == DRIVER?}
    H -- No --> I[Rider Home Screen]
    H -- Yes --> J{is_subscribed?}
    J -- No --> K[Subscription Screen]
    J -- Yes --> L{Has vehicle assignment?}
    L -- No --> M[Vehicle Setup Screen]
    L -- Yes --> N[Driver Home Screen]
```

| Gate | Service | Check |
|------|---------|-------|
| Authenticated | Authentik | Valid JWT exists |
| Profile exists | Onboarding | `GET /onboarding/me` returns 200 |
| Email verified | Onboarding | `email_verified == true` on profile |
| Subscribed | Payment | `is_subscribed == true` in JWT |
| Vehicle assigned | Fleet | `GET /fleet/vehicles` returns ≥ 1 result |
