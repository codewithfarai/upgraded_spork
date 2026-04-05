# Onboarding Service API Reference

Base URL: `https://onboarding.ridebase.tech`

All endpoints require an Authentik-issued RS256 token:

```
Authorization: Bearer <token>
```

---

## Table of Contents

**Auth**
- [Register](#register)
- [Login](#login)
- [Refresh Token](#refresh-token)
- [Logout](#logout)
- [Google OAuth Login](#google-oauth-login)

**Onboarding**
1. [Get My Profile](#1-get-my-profile)
2. [Create Profile](#2-create-profile)
3. [Update My Profile](#3-update-my-profile)
4. [Delete My Profile](#4-delete-my-profile)
5. [Setup Driver](#5-setup-driver)
6. [Update Driver Details](#6-update-driver-details)
7. [Delete Driver Setup](#7-delete-driver-setup)
8. [Verify Email OTP](#8-verify-email-otp)
9. [Resend OTP](#9-resend-otp)

---

---

### 1. Get My Profile

Fetches the authenticated user's onboarding profile.

```bash
curl -X GET https://onboarding.ridebase.tech/api/v1/onboarding/me \
  -H "Authorization: Bearer <token>"
```

**Response `200 OK`**

```json
{
  "full_name": "Farai Moyo",
  "phone_number": "+263771234567",
  "city": "Harare",
  "role": "DRIVER"
}
```

**Error Responses**

| Status | Description |
|--------|-------------|
| `401`  | Invalid or missing token |
| `404`  | Profile not found — user has not onboarded yet |

---

### 2. Create Profile

Creates a new user profile. Fails if a profile already exists for this user.

```bash
curl -X POST https://onboarding.ridebase.tech/api/v1/onboarding/profile \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "full_name=Farai Moyo" \
  --data-urlencode "phone_number=+263771234567" \
  --data-urlencode "city=Harare" \
  --data-urlencode "role=DRIVER"
```

**Request Fields**

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `full_name` | string | Yes | |
| `phone_number` | string | Yes | |
| `city` | string | Yes | |
| `role` | string | Yes | `RIDER` or `DRIVER` (case-insensitive) |

**Response `200 OK` — RIDER**

```json
{
  "message": "Profile created successfully",
  "role": "RIDER",
  "email_otp_sent": true
}
```

**Response `200 OK` — DRIVER (RabbitMQ sync successful)**

```json
{
  "message": "Profile created successfully",
  "role": "DRIVER",
  "email_otp_sent": true
}
```

**Response `200 OK` — DRIVER (RabbitMQ sync delayed)**

```json
{
  "message": "Profile created successfully, but backend sync is delayed.",
  "role": "DRIVER",
  "email_otp_sent": true,
  "warning": "sync_delayed"
}
```

**Error Responses**

| Status | Description |
|--------|-------------|
| `400`  | Profile already exists, or invalid role value |
| `401`  | Invalid or missing token |

---

### 3. Update My Profile

Partially updates the authenticated user's profile. All fields are optional.

```bash
curl -X PATCH https://onboarding.ridebase.tech/api/v1/onboarding/me \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "city=Bulawayo" \
  --data-urlencode "role=DRIVER"
```

**Request Fields (all optional)**

| Field | Type | Notes |
|-------|------|-------|
| `full_name` | string | |
| `phone_number` | string | |
| `city` | string | |
| `role` | string | `RIDER` or `DRIVER` (case-insensitive) |

**Response `200 OK`**

```json
{
  "message": "Profile updated.",
  "full_name": "Farai Moyo",
  "phone_number": "+263771234567",
  "city": "Bulawayo",
  "role": "DRIVER"
}
```

**Response `200 OK` — role changed to DRIVER (RabbitMQ sync delayed)**

```json
{
  "message": "Profile updated, but backend sync is delayed.",
  "full_name": "Farai Moyo",
  "phone_number": "+263771234567",
  "city": "Bulawayo",
  "role": "DRIVER",
  "warning": "sync_delayed"
}
```

**Error Responses**

| Status | Description |
|--------|-------------|
| `400`  | Invalid role value |
| `401`  | Invalid or missing token |
| `404`  | Profile not found |

---

### 4. Delete My Profile

Deletes the authenticated user's profile and all associated driver details (cascade).

```bash
curl -X DELETE https://onboarding.ridebase.tech/api/v1/onboarding/me \
  -H "Authorization: Bearer <token>"
```

**Response `204 No Content`**

_(empty body)_

**Error Responses**

| Status | Description |
|--------|-------------|
| `401`  | Invalid or missing token |
| `404`  | Profile not found |

---

### 5. Setup Driver

Submits driver vehicle and document details. User must already have a profile with `role=DRIVER`.

```bash
curl -X POST https://onboarding.ridebase.tech/api/v1/onboarding/driver_setup \
  -H "Authorization: Bearer <token>" \
  -F "car_make=Toyota" \
  -F "car_model=Camry" \
  -F "car_colour=Silver" \
  -F "year=2020" \
  -F "license_plate=ABC1234" \
  -F "national_id=12-345678-A-00" \
  -F "driver_license_number=DL987654" \
  -F "license_photo=@/path/to/license.jpg" \
  -F "national_id_photo=@/path/to/national_id.jpg"
```

**Request Fields**

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `car_make` | string | Yes | e.g. `Toyota` |
| `car_model` | string | Yes | e.g. `Camry` |
| `car_colour` | string | Yes | e.g. `Silver` |
| `year` | integer | Yes | e.g. `2020` |
| `license_plate` | string | Yes | Must be unique |
| `national_id` | string | Yes | Must be unique |
| `driver_license_number` | string | Yes | Must be unique |
| `license_photo` | file | Yes | JPEG, PNG, or PDF |
| `national_id_photo` | file | Yes | JPEG, PNG, or PDF |

**Response `200 OK`**

```json
{
  "message": "Driver setup complete!",
  "vehicle_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

**Error Responses**

| Status | Description |
|--------|-------------|
| `400`  | Driver details already submitted, or invalid file type |
| `401`  | Invalid or missing token |
| `403`  | User role is not DRIVER |
| `404`  | User profile not found — create a profile first |
| `500`  | S3 upload failed |

---

### 6. Update Driver Details

Partially updates existing driver/vehicle details. All fields are optional.

```bash
curl -X PATCH https://onboarding.ridebase.tech/api/v1/onboarding/driver_setup \
  -H "Authorization: Bearer <token>" \
  -F "car_colour=White" \
  -F "year=2022" \
  -F "license_photo=@/path/to/new_license.pdf"
```

**Request Fields (all optional)**

| Field | Type | Notes |
|-------|------|-------|
| `car_make` | string | |
| `car_model` | string | |
| `car_colour` | string | |
| `year` | integer | |
| `license_plate` | string | Must be unique |
| `national_id` | string | Must be unique |
| `driver_license_number` | string | Must be unique |
| `license_photo` | file | JPEG, PNG, or PDF — replaces existing |
| `national_id_photo` | file | JPEG, PNG, or PDF — replaces existing |

**Response `200 OK`**

```json
{
  "message": "Driver details updated.",
  "vehicle_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

**Error Responses**

| Status | Description |
|--------|-------------|
| `400`  | Invalid file type |
| `401`  | Invalid or missing token |
| `404`  | Driver details not found — complete driver setup first |
| `500`  | S3 upload failed |

---

### 7. Delete Driver Setup

Removes driver/vehicle record while keeping the base user profile intact.

```bash
curl -X DELETE https://onboarding.ridebase.tech/api/v1/onboarding/driver_setup \
  -H "Authorization: Bearer <token>"
```

**Response `204 No Content`**

_(empty body)_

**Error Responses**

| Status | Description |
|--------|-------------|
| `401`  | Invalid or missing token |
| `404`  | Driver details not found |

---

### 8. Verify Email OTP

Verifies the 6-digit OTP code sent to the user's email during profile creation. On success, sets `email_verified=true` on the profile and syncs the attribute to Authentik.

```bash
curl -X POST https://onboarding.ridebase.tech/api/v1/onboarding/verify-email \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"code": "482301"}'
```

**Request Body**

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `code` | string | Yes | 6-digit OTP from email |

**Response `200 OK`**

```json
{
  "message": "Email verified successfully."
}
```

**Response `200 OK` — already verified**

```json
{
  "message": "Email already verified."
}
```

**Error Responses**

| Status | Description |
|--------|-------------|
| `400`  | Invalid or expired code |
| `401`  | Invalid or missing token |
| `404`  | Profile not found — complete onboarding first |

---

### 9. Resend OTP

Resends a new 6-digit OTP code to the user's email. The previous code is replaced.

```bash
curl -X POST https://onboarding.ridebase.tech/api/v1/onboarding/resend-otp \
  -H "Authorization: Bearer <token>"
```

**Response `200 OK`**

```json
{
  "message": "Verification code resent."
}
```

**Response `200 OK` — already verified**

```json
{
  "message": "Email already verified."
}
```

**Error Responses**

| Status | Description |
|--------|-------------|
| `401`  | Invalid or missing token |
| `404`  | Profile not found |

---

## Authentication

Base URL: `https://auth.ridebase.tech` (dev: `https://auth.dev.ridebase.tech`)

All auth endpoints are standard OIDC. The `client_id` is always `ridebase`.

---

### Register

Creates a new account. On success Authentik sends a confirmation email — the account is inactive until the email link is clicked.

```bash
curl -X POST https://auth.ridebase.tech/api/v3/flows/executor/ridebase-enrollment/ \
  -H "Content-Type: application/json" \
  -d '{
    "username": "farai",
    "email": "farai@ridebase.tech",
    "password": "<password>",
    "password_repeat": "<password>"
  }'
```

**Request Fields**

| Field | Type | Required |
|-------|------|----------|
| `username` | string | Yes |
| `email` | string | Yes |
| `password` | string | Yes |
| `password_repeat` | string | Yes |

**Response `200 OK`**

```json
{ "component": "xak-flow-redirect", "to": "/" }
```

A confirmation email is sent. The user must click the link to activate the account before they can log in.

---

### Login

Exchanges username/email + password for an access token, refresh token, and ID token.

```bash
curl -X POST https://auth.ridebase.tech/application/o/token/ \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=password" \
  --data-urlencode "client_id=ridebase" \
  --data-urlencode "username=farai@ridebase.tech" \
  --data-urlencode "password=<password>" \
  --data-urlencode "scope=openid profile email offline_access"
```

**Request Fields**

| Field | Value |
|-------|-------|
| `grant_type` | `password` |
| `client_id` | `ridebase` |
| `username` | username or email |
| `password` | user password |
| `scope` | `openid profile email offline_access` |

**Response `200 OK`**

```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "refresh_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "id_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "scope": "openid profile email offline_access"
}
```

**JWT claims included in `access_token`:**

| Claim | Description |
|-------|-------------|
| `sub` | User ID |
| `email` | User email |
| `preferred_username` | Username |
| `authentik_pk` | Numeric user PK (for Authentik API calls) |
| `is_subscribed` | `true` if driver subscription is active |

**Error Responses**

| Status | Description |
|--------|-------------|
| `401`  | Invalid credentials or unverified account |

---

### Refresh Token

Obtains a new access token using a refresh token (without requiring the user's password).

```bash
curl -X POST https://auth.ridebase.tech/application/o/token/ \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=refresh_token" \
  --data-urlencode "client_id=ridebase" \
  --data-urlencode "refresh_token=<refresh_token>"
```

**Response `200 OK`**

```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "refresh_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "scope": "openid profile email offline_access"
}
```

**Error Responses**

| Status | Description |
|--------|-------------|
| `400`  | Invalid or expired refresh token |

---

### Logout

Revokes the token and invalidates the session.

```bash
curl -X POST https://auth.ridebase.tech/application/o/revoke/ \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "client_id=ridebase" \
  --data-urlencode "token=<refresh_token>"
```

**Response `200 OK`**

_(empty body)_

---

### Google OAuth Login

Redirects the user to Google for authentication. Used for mobile/web flows via a browser.

```bash
curl -X GET "https://auth.ridebase.tech/source/oauth/login/google/"
```

Or construct the authorization URL directly:

```bash
curl -X GET "https://auth.ridebase.tech/application/o/authorize/?client_id=ridebase&response_type=code&scope=openid+profile+email+offline_access&redirect_uri=ridebase://callback"
```

The browser will redirect through Google and back to `ridebase://callback?code=<code>`. Exchange the code for tokens:

```bash
curl -X POST https://auth.ridebase.tech/application/o/token/ \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=authorization_code" \
  --data-urlencode "client_id=ridebase" \
  --data-urlencode "code=<code>" \
  --data-urlencode "redirect_uri=ridebase://callback"
```

**Response `200 OK`** — same shape as [Login](#login).

---

### OIDC Discovery

Machine-readable endpoint listing all auth URLs (useful for SDK configuration).

```bash
curl https://auth.ridebase.tech/application/o/ridebase/.well-known/openid-configuration
```

Key fields returned:

| Field | Value |
|-------|-------|
| `authorization_endpoint` | `https://auth.ridebase.tech/application/o/authorize/` |
| `token_endpoint` | `https://auth.ridebase.tech/application/o/token/` |
| `jwks_uri` | `https://auth.ridebase.tech/application/o/ridebase/.well-known/jwks.json` |
| `revocation_endpoint` | `https://auth.ridebase.tech/application/o/revoke/` |
| `userinfo_endpoint` | `https://auth.ridebase.tech/application/o/userinfo/` |
