/// RideBase API configuration.
///
/// Centralizes all backend URLs so they're easy to swap between
/// environments (dev / staging / production).
class RideBaseConfig {
  RideBaseConfig._();

  // ── Environment Detection ─────────────────────────────────────────
  /// Detects the current environment from the tile server base URL.
  /// Supports: dev, staging, prod
  static const String environment = 'prod'; // Change this based on build config

  // ── Tile Server (Martin) ──────────────────────────────────────────
  static const String tileServerBase = 'https://tiles.ridebase.tech';
  static const String tileSourceUrl = '$tileServerBase/zimbabwe';

  /// Fallback tile source for offline development (localhost)
  static const String tileSourceUrlLocal = 'http://localhost:3000/zimbabwe';

  // ── Routing (OSRM) ───────────────────────────────────────────────
  static const String routingBase = 'https://route.ridebase.tech';

  /// Fallback routing for offline development (localhost)
  static const String routingBaseLocal = 'http://localhost:5000';

  // ── Auth (Authentik OIDC) ───────────────────────────────────────────
  static const String authBase = 'https://auth.ridebase.tech';
  static const String oidcClientId = 'ridebase';
  static const String oidcRedirectUri = 'ridebase://callback';
  static const String oidcLogoutRedirectUri = 'ridebase://logout-callback';
  static const String oidcRevocationUri = '$authBase/application/o/revoke/';

  // Explicit OIDC endpoints (from .well-known/openid-configuration).
  // Using these directly avoids a discovery round-trip on every auth operation.
  static const String oidcAuthorizationEndpoint = '$authBase/application/o/authorize/';
  static const String oidcTokenEndpoint = '$authBase/application/o/token/';
  static const String oidcEndSessionEndpoint = '$authBase/application/o/ridebase/end-session/';
  static const String oidcDiscoveryUrl = '$authBase/application/o/ridebase/.well-known/openid-configuration';
  static const List<String> oidcScopes = [
    'openid',
    'profile',
    'email',
    'offline_access',
  ];

  // ── Onboarding API ──────────────────────────────────────────────────
  static const String onboardingApiBase = 'https://onboarding.ridebase.tech/api/v1/onboarding';

  /// Fallback onboarding API for offline development
  static const String onboardingApiBaseLocal = 'http://localhost:8080/api/v1/onboarding';

  // ── Fleet API ────────────────────────────────────────────────────────
  static const String fleetApiBase = 'https://fleet.ridebase.tech/api/v1/fleet';

  /// Fallback fleet API for offline development
  static const String fleetApiBaseLocal = 'http://localhost:8081/api/v1/fleet';

  // ── Map Style ─────────────────────────────────────────────────────
  /// Bundled asset path for the MapLibre style JSON.
  static const String mapStyleAsset = 'assets/styles/ridebase_style.json';

  // ── Default Map Position (Harare, Zimbabwe) ───────────────────────
  static const double defaultLat = -17.8248;
  static const double defaultLng = 31.0530;
  static const double defaultZoom = 13.0;

  // ── Network Configuration ─────────────────────────────────────────
  /// Timeout for tile server requests (in seconds)
  static const int tileServerTimeout = 30;

  /// Timeout for routing requests (in seconds)
  static const int routingTimeout = 30;
}
