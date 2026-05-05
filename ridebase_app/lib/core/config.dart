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

  // ── Auth (Authentik) — Phase 2 ────────────────────────────────────
  static const String authBase = 'https://auth.ridebase.tech';

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
