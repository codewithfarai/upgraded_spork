# OIDC Redirect via App Links / Universal Links

**Status:** Implemented. The OIDC redirect URI is `https://app.ridebase.tech/mobile/callback` (App Link on Android, Universal Link on iOS). The legacy `ridebase://` custom scheme has been removed everywhere.

## Why HTTPS deep links instead of a custom scheme

Custom URL schemes (`ridebase://...`) have no ownership verification — any other app installed on the device can register the same scheme and intercept the OIDC `code` parameter. App Links (Android) and Universal Links (iOS) are domain-verified: the OS confirms ownership of `app.ridebase.tech` via a signed JSON file we host, so no other app can hijack the redirect.

## Why `app.ridebase.tech` and not `auth.ridebase.tech`

Authentik itself serves a hardcoded `apple-app-site-association` at `https://auth.ridebase.tech/.well-known/apple-app-site-association` for its own iOS Platform-SSO apps. Verified live on 2026-05-07:

```bash
$ curl -s https://auth.ridebase.tech/.well-known/apple-app-site-association
{"authsrv":{"apps":["232G855Y8N.io.goauthentik.platform", ...]}}
```

The path is owned by Authentik's request handler, so dropping our own AASA file there would require either intercepting the path in Traefik or merging Authentik's `authsrv` block with our `applinks` block on every change. Using a separate subdomain that Authentik never touches avoids the conflict entirely.

## Architecture

```
Hetzner LB (TLS termination, *.ridebase.tech wildcard cert)
        │
        ▼
   Traefik (port 80, label-based routing)
        │
        ├─ Host(`auth.ridebase.tech`)  → Authentik
        │
        └─ Host(`app.ridebase.tech`)   → applinks (Caddy)
                                          serves:
                                          /.well-known/assetlinks.json
                                          /.well-known/apple-app-site-association
                                          /mobile/callback        → fallback HTML
                                          /mobile/logout-callback → fallback HTML
```

`*.ridebase.tech` is wildcard-covered by the Hetzner-managed cert (`terraform/certificates.tf`) and the wildcard A record in Hetzner DNS already points at the load balancer, so no new TLS or DNS work is needed for `app.ridebase.tech`.

## What's where

### Server side

| Path | Source | Notes |
|---|---|---|
| `ansible/roles/applinks/` | New role | Caddy stack + four file templates |
| `ansible/inventory/group_vars/all/applinks.yml` | New | Domain prefix, Caddy image, env vars for Apple Team ID + Android signing SHA-256 |
| `ansible/playbooks/swarm.yml` | Play 12b added | Calls the role |
| `terraform_authentik/authentik.tf` | Updated | `allowed_redirect_uris` is HTTPS-only; logout redirect target hardcoded to env-aware HTTPS URL |

### Client side

| Path | Change |
|---|---|
| `ridebase_app/lib/core/config.dart` | `oidcRedirectUri` and `oidcLogoutRedirectUri` point at `https://app.ridebase.tech/mobile/{callback,logout-callback}` |
| `ridebase_app/android/app/src/main/AndroidManifest.xml` | `RedirectUriReceiverActivity` with `tools:node="replace"` claims `https://app.ridebase.tech/mobile/*` and `android:autoVerify="true"` |
| `ridebase_app/android/app/build.gradle.kts` | `appAuthRedirectScheme` placeholder set to a dummy value (manifest-merge requirement only — the activity is replaced) |
| `ridebase_app/ios/Runner/Runner.entitlements` | `applinks:app.ridebase.tech`. **Must be wired into the Xcode build via Signing & Capabilities → Associated Domains** |
| `ridebase_app/ios/Runner/Info.plist` | `CFBundleURLTypes` block removed (no more custom scheme) |
| `ridebase_app/ios/Runner.xcodeproj/project.pbxproj` | `PRODUCT_BUNDLE_IDENTIFIER = tech.ridebase.app` |

## Required env vars before running Ansible

The `applinks` role **soft-skips** with a clear warning if either env var is missing — it won't break a fresh-cluster bootstrap. Set both and re-run when you have the values:

```bash
export APPLE_TEAM_ID="ABCDE12345"                      # 10-char Team ID, App Store Connect → Membership
export APPLE_BUNDLE_ID="tech.ridebase.app"             # optional, defaults right
export ANDROID_PACKAGE="tech.ridebase.app"             # optional, defaults right
export ANDROID_RELEASE_SIGNING_SHA256="AA:BB:CC:..."   # Play Console → App Integrity → App Signing
```

Apple Team ID is available the moment you join the Developer Program. **Android SHA-256 is only available after the first AAB upload to Play Console** — Google generates the App Signing Key on first upload, then exposes its SHA-256 in App Integrity. Until then, set `applinks_enabled: false` in `group_vars/all/applinks.yml` and skip the role.

## Deployment

```bash
# 1. Deploy applinks stack (Caddy + Traefik routing)
make swarm ENV=<env>     # or: ansible-playbook playbooks/swarm.yml

# 2. Apply Authentik OAuth provider config (HTTPS redirect URIs)
cd terraform_authentik && terraform apply
```

The Ansible role runs smoke tests against `https://app.<env>.ridebase.tech/.well-known/{assetlinks.json,apple-app-site-association}` at the end of the play. Both must return 200 with `Content-Type: application/json`.

## Verifying the deep links work

### Server side

```bash
# Both must return 200, application/json, with no redirects
curl -v https://app.ridebase.tech/.well-known/assetlinks.json
curl -v https://app.ridebase.tech/.well-known/apple-app-site-association

# Apple's CDN cached AASA (returns content if Apple has fetched and accepted it)
curl -v "https://app-site-association.cdn-apple.com/a/v1/app.ridebase.tech"
```

### Android

After installing a release build signed with the production key:

```bash
adb shell pm get-app-links tech.ridebase.app
```

Expected: `verified` for `app.ridebase.tech`. If `none` or `failed`, the SHA-256 in `assetlinks.json` doesn't match the actual signing cert.

### iOS

After installing the build on a real device (Universal Links don't verify in the simulator on first launch):

```bash
xcrun simctl openurl booted "https://app.ridebase.tech/mobile/callback?code=test&state=test"
```

App should open. If Safari opens instead, the AASA file isn't being fetched — check `Console.app` filtered to `swcd` for the actual error.

## What still requires the Xcode UI

The iOS Associated Domains capability has to be enabled in Xcode (it writes to `project.pbxproj` in a way that's hostile to programmatic editing). Steps:

1. Open `ios/Runner.xcworkspace` in Xcode.
2. Select **Runner** target → **Signing & Capabilities**.
3. Click **+ Capability** → **Associated Domains**.
4. Confirm `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements` appears in the build settings for both Debug and Release.
5. The entitlements file at `ios/Runner/Runner.entitlements` already declares `applinks:app.ridebase.tech` — Xcode just needs to know to use it.

## Things that break this

- **Wrong SHA-256 in assetlinks.json.** The most common cause of "App Links not verifying". Play App Signing rotates between the **upload key** (your local keystore) and the **app signing key** (Google-managed). `assetlinks.json` must contain the **app signing key** SHA-256, not the upload key, not debug.
- **Bundle ID mismatch on iOS.** The bundle ID in `project.pbxproj` must equal `APPLE_BUNDLE_ID` used in the AASA template. The Team ID in the AASA file must equal the actual signing team. A mismatch → iOS fetches the AASA, sees the entry doesn't apply to the installed app, falls back to opening the URL in Safari.
- **HTTP redirects on `.well-known/` files.** Apple's CDN follows them but logs the original URL as the AASA owner; Google won't accept any redirect. Caddy doesn't redirect by default, but check that the Hetzner LB isn't doing HTTP→HTTPS redirects on the asset paths.
- **Forgetting Associated Domains capability in Xcode.** Adding `applinks:` to `Runner.entitlements` but not enabling the capability → the entitlements file is silently ignored at build time.
- **Hosting AASA at `auth.ridebase.tech`.** Authentik intercepts that path with its own AASA file. Use `app.ridebase.tech`.
- **Apple CDN cache.** Apple caches AASA per device for ~7 days. If you change the file and an installed build still misbehaves, reinstall the app to force a fresh fetch.
