# RideBase — Security Review

**Date:** 2026-05-07 (revised after live OIDC discovery + Terraform inspection)
**Scope:** `ridebase_app/` Flutter client + its interaction with backend services (Authentik, Onboarding API, Fleet API, Tile/Routing, Google Places).
**Reviewer:** Claude (Opus 4.7)

---

## 1. Executive Summary

The app gets the auth fundamentals right — OIDC + PKCE via `flutter_appauth`, encrypted token storage, no client secret, no hardcoded credentials in source. The primary concerns are **operational rather than cryptographic**: token-refresh logic is partial and inconsistent across services, and platform hardening (manifest flags, certificate pinning, log scrubbing) has not been done.

**Severity counts**

| Severity | Count |
|---|---|
| Critical | 1 |
| High | 5 |
| Medium | 5 |
| Low | 4 |
| Informational | 3 |

---

## 2. Token Refresh — Will the App Work After 24 hours?

### Short answer

**Yes, after the C-1, H-1 and H-2 fixes are applied.** Confirmed against the live Authentik configuration.

### Confirmed token lifetimes (`terraform_authentik/authentik.tf:612-620`)

| Token | Lifetime |
|---|---|
| Authorization code | 1 minute |
| Access token | 15 minutes |
| Refresh token | **90 days** |
| Refresh-token rotation threshold | 7 days |

A user opening the app 24 hours after their last session has an expired access token but a valid refresh token (88+ days remaining). The proactive refresh interceptor exchanges it for a new access token before the first request goes out. They never see a 401.

The 7-day rotation threshold is specifically why **H-2 (single-flight refresh mutex)** is load-bearing: a refresh token older than 7 days is rotated on use (Authentik issues a new refresh token, invalidates the old one). Two parallel calls hitting that threshold simultaneously without the mutex would race and brick the session.

### The flow today (post-fix)

`AuthService.tryRefresh()` (`lib/core/services/auth_service.dart`) is now single-flight and invoked from:

1. **App launch** — `AuthNotifier.initialize()` calls it once on cold start; on failure it now forces logout and clears tokens (C-1 fix).
2. **Per-request, all services** — `OnboardingService` and `FleetService` request interceptors check `hasValidToken` and call the refresh callback proactively before the request goes out (H-1 fix).
3. **Manual** — `AuthNotifier.refreshUser()` after server-side claim updates (e.g. driver approval, email verification).

Concurrent callers share the same in-flight `Future` via `_inflightRefresh`, so refresh-token rotation never invalidates a parallel call (H-2 fix).

### Failure modes covered

| Scenario | Behaviour |
|---|---|
| Cold open after 24h with valid refresh token | Refresh succeeds, user proceeds. |
| Cold open after >90 days (refresh token expired) | C-1 fix: `initialize()` forces full logout, user re-authenticates. |
| Two parallel API calls hit rotation threshold | H-2 fix: both share one refresh, rotation token applied atomically. |
| Network blip during refresh | Refresh fails, error propagates to caller; UI shows snackbar; next attempt retries. |

---

## 3. Findings

Severity uses Critical / High / Medium / Low / Informational. Each has a fix sketch.

### Critical

#### C-1 — Silent half-authenticated state after refresh failure

- **Where:** `lib/core/providers/auth_provider.dart:55-66`
- **Issue:** `initialize()` sets `isAuthenticated = true` from the stored ID token *before* attempting refresh, and the catch block on line 64 swallows refresh failures. If `tryRefresh` returns `null` (no stored refresh token, or Authentik rejects it), the state is never downgraded to `unauthenticated`. The user lands on the map, every API call 401s, the proactive refresh interceptor on `OnboardingService` keeps trying and failing.
- **Fix:**
  ```dart
  if (storedUser != null) {
    state = AuthState(isLoading: false, isAuthenticated: true, user: storedUser);
    final refreshResult = await _authService.tryRefresh();
    if (refreshResult == null || !refreshResult.success) {
      // Refresh token is dead — force re-login.
      await _authService.logout();
      state = AuthState.unauthenticated;
      return;
    }
    state = AuthState(
      isLoading: false,
      isAuthenticated: true,
      user: refreshResult.user ?? storedUser,
    );
    return;
  }
  ```

### High

#### H-1 — `FleetService` has no refresh logic

- **Where:** `lib/features/fleet/services/fleet_service.dart:19-28`
- **Issue:** The interceptor only attaches `Bearer ${accessToken}`. There is no `hasValidToken` check, no proactive refresh, no 401 retry. After the access token expires (≈1 h), every fleet endpoint (vehicles, availability, stats, ride history) fails until the app cold-starts and `initialize()` triggers a refresh. Drivers in mid-shift would lose all functionality.
- **Fix:** Mirror the `OnboardingService` pattern: accept an `onRefreshToken` callback in the constructor and call it from the request interceptor when `hasValidToken` is false. Update `fleetServiceProvider` to pass `authService.tryRefresh`.

#### H-2 — No mutex around token refresh; race condition with rotated refresh tokens

- **Where:** `OnboardingService` interceptor and (post-fix) `FleetService`.
- **Issue:** If two requests fire while the access token is expired, both call `_onRefreshToken()` in parallel. Authentik (with refresh-token rotation enabled) invalidates the original refresh token after first use, so the second call fails — and that failure is swallowed in `AuthService.tryRefresh:62`. The user ends up with **no usable refresh token** and falls into C-1.
- **Fix:** Single-flight the refresh. A simple pattern:
  ```dart
  Future<bool>? _inflightRefresh;
  Future<bool> _refresh() async {
    return _inflightRefresh ??= () async {
      try {
        return (await authService.tryRefresh())?.success == true;
      } finally {
        _inflightRefresh = null;
      }
    }();
  }
  ```
  Both Onboarding and Fleet services should share this same mutex (lift it onto `AuthService` or a dedicated `TokenManager`).

#### H-3 — `debugPrint` runs in release builds and leaks PII

- **Where:** Every service. Examples:
  - `auth_service.dart:141` — logs `user.displayName` on every login.
  - `auth_provider.dart:52, 76, 79, 92, 95` — logs auth-state transitions plus display name.
  - `google_places_service.dart:23, 33, 40, 47` — logs query strings and search status.
- **Issue:** `debugPrint` is **not** stripped from release builds; it writes to the platform log (logcat / OSLog). Anyone with adb access (or another app holding `READ_LOGS` on rooted Android, or any developer tool on a connected device) can read user names, search queries, and onboarding state. This is OWASP M9 / Mobile-Top-10 *Insufficient Cryptography* + M2 *Insecure Data Storage* territory.
- **Fix:** Wrap user-data prints in `if (kDebugMode)`, or replace `debugPrint` with a logger (e.g. `package:logger`) that respects build mode. Search queries in `google_places_service.dart` should not be logged at all in release.

#### H-4 — No `android:allowBackup="false"` on the Android manifest

- **Where:** `android/app/src/main/AndroidManifest.xml`.
- **Issue:** `<application>` has no `android:allowBackup` attribute, so it defaults to `true`. Although `flutter_secure_storage` uses `EncryptedSharedPreferences`, the encrypted blob is included in `adb backup` exports and Auto Backup uploads to the user's Google Drive. An attacker with USB debugging access (or a compromised Google account) can lift the file even if they cannot decrypt it locally. Best practice for any app holding tokens / PII is to disable backup.
- **Fix:**
  ```xml
  <application
      android:allowBackup="false"
      android:fullBackupContent="false"
      android:dataExtractionRules="@xml/data_extraction_rules"
      ...>
  ```
  Add a `data_extraction_rules.xml` that excludes the secure-storage prefs file.

#### H-5 — ROPC and implicit grants enabled on the public OIDC provider

- **Where:** Authentik OIDC provider for `client_id=ridebase`. Confirmed via the live discovery doc (`https://auth.ridebase.tech/application/o/ridebase/.well-known/openid-configuration` on 2026-05-07):

  ```
  grant_types_supported: [
    "authorization_code", "refresh_token", "implicit",
    "client_credentials", "password", "device_code"
  ]
  ```

- **Issue:** Two of those grants don't belong on a public mobile client and represent active attack surface:

  - **`password` (Resource Owner Password Credentials)** — lets any client with the public `client_id` exchange a username/password directly for tokens via `POST /application/o/token/`, bypassing the OIDC redirect flow, MFA prompts, brand consent, and rate limits that the browser flow enforces. With a public client and ROPC enabled, anyone who phishes (or credential-sprays) a username/password gets a full session — the OIDC handshake provides no defence. The Onboarding API documentation even includes the curl example for this grant, so the technique is publicly documented.
  - **`implicit`** — returns access tokens in the URL fragment (`#access_token=...`). Vulnerable to leakage via browser history, referer headers, server logs along the redirect chain, and shoulder-surfing. Deprecated in OAuth 2.1; only kept enabled for legacy SPAs that pre-date PKCE.

  PKCE on `authorization_code` is supported (`code_challenge_methods_supported: ["plain", "S256"]`) and is what `flutter_appauth` uses, so the legitimate flow is fine. The risk is purely from the **other grants existing as alternatives**.

- **Fix:** In `terraform_authentik/authentik.tf`, restrict the `ridebase` OAuth provider to the two grants the mobile client actually uses. The exact attribute name in the `goauthentik/authentik` provider is `allowed_grant_types` (or `grant_types` depending on schema version — check `terraform-provider-authentik` 2025.12 docs):

  ```hcl
  resource "authentik_provider_oauth2" "ridebase" {
    # ... existing fields ...
    allowed_grant_types = ["authorization_code", "refresh_token"]
  }
  ```

  Also recommended: disable `plain` PKCE method (only `S256` is secure):

  ```hcl
  pkce_required           = true
  pkce_code_challenge_methods = ["S256"]
  ```

  After applying, re-fetch the discovery doc and confirm `grant_types_supported` only lists the two allowed grants.

### Medium

#### M-1 — Certificate pinning (closed — approach changed)

- **Where:** All Dio instances (`OnboardingService`, `FleetService`, `TileService`).
- **Original issue:** The app trusted the device CA store; a user with a custom root CA (Charles, Burp, MDM) could intercept tokens.
- **Resolution (2026-05-07):** Certificate pinning scaffolding (`cert_pinning.dart`) has been **removed**. OWASP MASVS 2025, Apple, and Google all recommend against pinning for non-regulated consumer apps: empty pin lists silently disable enforcement, and any populated list is a guaranteed outage on cert rotation with no server-side kill switch. Instead:
  1. **CAA records** added to `terraform/main.tf` — restrict issuance for `*.ridebase.tech` to Let's Encrypt only. Violation reports route to `ops@ridebase.tech` via `iodef`. This blocks rogue certs at the CA level, before any cert exists.
  2. **Certificate Transparency** — Let's Encrypt logs every issued cert publicly within ~60 seconds. Monitor via `crt.sh` or a CT log watcher (e.g. Certspotter, Facebook CT Monitor) for unexpected SANs.
  3. Existing controls remain: HSTS, TLS 1.2+ enforced at the Hetzner LB, short access-token TTL (15 min), and OIDC + PKCE so tokens are useless without the PKCE verifier.

#### M-2 — iOS Keychain accessibility not declared

- **Where:** `lib/core/services/token_storage.dart:15-18`.
- **Issue:** `FlutterSecureStorage` is constructed with `aOptions` (Android EncryptedSharedPreferences — good) but no `iOptions`. The default iOS accessibility class is `kSecAttrAccessibleWhenUnlocked`, which is reasonable but is **synced to iCloud Keychain** if the user enables it. Tokens for driver accounts shouldn't follow the user across devices.
- **Fix:**
  ```dart
  TokenStorage()
    : _storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      );
  ```

#### M-3 — Custom-scheme OIDC redirect is hijackable by other apps

- **Where:** `android/app/src/main/AndroidManifest.xml` + `ios/Runner/Info.plist` (current state) and the `ridebase://callback` redirect URI on the Authentik OAuth provider.
- **Issue:** Custom URL schemes (`ridebase://`) have no ownership verification — any app installed on the device can register the same scheme. On Android, the OS may show a chooser, pick the most recently installed handler, or silently route to whichever app wins the lottery. A malicious app that registers `ridebase://` can intercept the OIDC `code` parameter and exchange it for tokens (the OAuth client is public, no client secret blocks the swap). On iOS the picture is similar pre-iOS 11; later iOS versions deterministically pick one but offer no verification of which one.
- **Fix:** Migrate to App Links (Android) + Universal Links (iOS) on a separate subdomain — `app.ridebase.tech`. The OS verifies domain ownership via signed `.well-known/` files, and no other app can claim a domain it doesn't control.

  Why a separate subdomain rather than reusing `auth.ridebase.tech`: Authentik itself serves a hardcoded `apple-app-site-association` at `https://auth.ridebase.tech/.well-known/apple-app-site-association` for its own iOS Platform-SSO apps (verified live on 2026-05-07 — body is `{"authsrv": {"apps": ["232G855Y8N.io.goauthentik.platform", ...]}}`). Hosting our own AASA on the same domain would either require modifying Authentik's response (fork) or intercepting the path in Traefik before Authentik sees it. Using `app.ridebase.tech` instead avoids the conflict entirely; Authentik does not validate which domain the redirect URI lives on, only that the URI string matches the allow-list.

  Full migration playbook: `docs/applink_migration.md`. Client-side scaffolding (entitlements file, intent-filter block, HTTPS constants in `config.dart`) is already in place — all changes are inert until activated.

#### M-4 — Google Maps API key embedded in client

- **Where:** `lib/features/search/services/google_places_service.dart:8` (`String.fromEnvironment('GOOGLE_MAPS_API_KEY')`).
- **Issue:** Build-time injection still ends up as a literal string in the compiled `.so` / Dart snapshot. Anyone running `strings` on an APK extracts it in seconds.
- **Mitigation:** Confirm Google Cloud Console restrictions are configured: **Application restriction = Android apps + iOS apps** (with package name + SHA1), **API restrictions = Places API + Geocoding API only**. Without these, an attacker with the key can run up your bill.
- **Fix:** Verify the key is restricted in GCP. For high-volume usage, proxy autocomplete/geocode through your backend so the key never ships to clients.

#### M-5 — Profile fetch failure leaves user in `complete` state with stale step

- **Where:** `lib/features/onboarding/providers/onboarding_provider.dart:91-101`.
- **Issue:** When `_fetchProfile()` throws (network error, 5xx), the comment says "fall through to 'complete' so the user lands on the home map and can retry by signing out". This is intentional, but it means a user whose profile was deleted server-side, or whose session is partially valid, sits on the map with no indication that anything is wrong. Fleet/onboarding calls will silently fail.
- **Fix:** Surface the `error` field on `OnboardingState` to the UI and show a toast / banner. At minimum, on persistent fetch failure prompt the user to sign in again.

### Low

#### L-1 — `debugPrint` of API key presence

- **Where:** `google_places_service.dart:23`.
- **Issue:** Logs `"SET" / "EMPTY"` not the key itself, but still gives an attacker watching logs confirmation that the build has the key wired up. Marginal but pointless.
- **Fix:** Drop the line.

#### L-2 — No clock-skew tolerance on `hasValidToken`

- **Where:** `lib/core/services/token_storage.dart:59-64`.
- **Issue:** If the device clock is 30 seconds ahead of the server, a token may appear expired locally before it's actually expired (causing extra refreshes — minor) or the inverse (using a token that the server will 401 — annoying). Standard practice is a 30 s skew.
- **Fix:** `return DateTime.now().isBefore(expiry.subtract(const Duration(seconds: 30)));`

#### L-3 — No root / jailbreak detection

- **Where:** Global.
- **Issue:** Tokens in EncryptedSharedPreferences / Keychain are recoverable on rooted/jailbroken devices. For a ride-sharing app with real-money flows this is worth a soft warning.
- **Fix:** Add `flutter_jailbreak_detection` and on detection either refuse to run, warn the user, or refuse just the financially-sensitive flows (driver earnings, payments).

#### L-4 — No code obfuscation flag

- **Where:** Build configuration.
- **Issue:** Builds without `--obfuscate --split-debug-info=...` ship with readable Dart class names, making reverse engineering trivial.
- **Fix:** Add `--obfuscate --split-debug-info=build/symbols` to release build commands and store the symbol files securely for crash deobfuscation.

### Informational

#### I-1 — Authentik state-mismatch on logout (cosmetic)

- **Where:** `lib/core/services/auth_service.dart:87-91`.
- **Issue:** AppAuth logs a non-fatal `state mismatch` warning during `endSession` because Authentik does not echo the `state` parameter on the post-logout redirect. Already caught and tokens are still cleared. Documented in `MEMORY.md` under the auth flow architecture.
- **Action:** None required, but a future Authentik upgrade may fix this server-side.

#### I-2 — Tile and routing services are unauthenticated

- **Where:** `lib/core/services/tile_service.dart`, OSRM at `route.ridebase.tech`.
- **Issue:** These are intentionally public (map tiles, route calculation). Worth flagging that anyone can hit them — they should have rate limits at the edge (Traefik `global-ratelimit@file` middleware is already wired for the Onboarding API; same middleware should be applied to tile/route routers) to prevent scraping or amplification.
- **Action:** Confirm rate limits exist server-side.

#### I-3 — `secrets.dart` pattern is solid

- `secrets.dart.template` is committed; `secrets.dart` is `.gitignore`d. Build-time key injection via `String.fromEnvironment`. Standard Flutter pattern, no issues found.

---

## 4. OWASP Mobile Top 10 (2024) — Mapping

| # | Category | Status | Findings |
|---|---|---|---|
| M1 | Improper Credential Usage | OK | OIDC + PKCE, no client secret. |
| M2 | Inadequate Supply Chain Security | OK | Dependencies are mainstream and up to date. Recommend `flutter pub outdated` quarterly. |
| M3 | Insecure Authentication / Authorization | **Issues** | C-1 (silent half-auth), H-2 (refresh race), H-5 (ROPC + implicit grants). |
| M4 | Insufficient Input/Output Validation | Minor | Phone numbers validated (ZW). National ID, license plate not validated — server should be authoritative. |
| M5 | Insecure Communication | **Issues** | M-1 (no certificate pinning). |
| M6 | Inadequate Privacy Controls | **Issues** | H-3 (PII in logs). |
| M7 | Insufficient Binary Protection | **Issues** | L-3, L-4 (no jailbreak detection, no obfuscation). |
| M8 | Security Misconfiguration | **Mostly addressed** | H-4 ✓ (allowBackup), M-2 ✓ (Keychain accessibility), M-3 ✓ (App Links). |
| M9 | Insecure Data Storage | OK | Encrypted at rest. Caveat: H-4 backup. |
| M10 | Insufficient Cryptography | OK | No custom crypto; relies on platform primitives. |

---

## 5. Status

✓ = applied as of 2026-05-07. Numbers in parens reference the file(s) touched.

| | Finding | Status |
|---|---|---|
| 1 | **C-1** — Half-authenticated state | ✓ `auth_provider.dart` |
| 2 | **H-1** — FleetService refresh wiring | ✓ `fleet_service.dart`, `fleet_provider.dart` |
| 3 | **H-2** — Single-flight refresh mutex | ✓ `auth_service.dart` |
| 4 | **H-3** — `debugPrint` guarded + search-query logging removed | ✓ services + providers |
| 5 | **H-4** — `allowBackup="false"` + data-extraction rules | ✓ `AndroidManifest.xml` + `data_extraction_rules.xml` |
| 6 | **M-2** — Keychain accessibility flag | ✓ `token_storage.dart` |
| 7 | **M-1** — Certificate pinning removed; CAA records added | ✓ `cert_pinning.dart` deleted; `terraform/main.tf` CAA rrset |
| 8 | **M-3** — App Links / Universal Links migration | ✓ Implemented. Custom scheme removed. iOS Associated Domains capability still requires Xcode UI step (documented). See `docs/applink_migration.md`. |
| 9 | **H-5** — ROPC + implicit grants disabled | Manual step: Authentik UI → Providers → RideBase Provider → uncheck all grant types except Authorization Code + Refresh Token. Not exposed by the Terraform provider v2025.12.1. |
| 10 | **M-4, M-5, L-1..L-4, I-*** | Open — follow-up hardening sprint. |

Items C-1, H-1, H-2 were the load-bearing fixes for the 24-hour-cold-open question. With them applied, the answer is "yes, cleanly". All critical and high items are now resolved. The remaining open items (M-4, M-5, L-1..L-4, I-*) are follow-up hardening for a post-launch sprint.

---

## 6. Out of Scope / Worth Reviewing Separately

- **Backend code** (Authentik configuration, Onboarding API, Fleet API) — token lifetimes, refresh-token rotation policy, rate limits, RBAC checks on `/me`, S3 bucket policies on driver-document uploads.
- **CI/CD** — secret handling in build pipelines, signing key rotation, App Store / Play Store credentials.
- **Privacy / GDPR-equivalent** — Zimbabwe Data Protection Act 2021 compliance: data retention, user deletion (`deleteProfile` exists, good), driver-ID retention policy.
- **Payment integration** — not yet in client code; will need its own review.
