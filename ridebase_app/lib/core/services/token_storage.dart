import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure persistent storage for OAuth2 tokens.
///
/// Uses the platform Keychain (iOS) / EncryptedSharedPreferences (Android)
/// so tokens are encrypted at rest and never stored in plain text.
class TokenStorage {
  static const _keyAccessToken = 'ridebase_access_token';
  static const _keyRefreshToken = 'ridebase_refresh_token';
  static const _keyIdToken = 'ridebase_id_token';
  static const _keyTokenExpiry = 'ridebase_token_expiry';

  final FlutterSecureStorage _storage;

  TokenStorage()
      : _storage = const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
          // first_unlock_this_device: tokens are readable after the first
          // unlock following boot, but never sync to iCloud Keychain. This
          // is the right tradeoff for session credentials — they are
          // device-bound and shouldn't follow the user across devices.
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.first_unlock_this_device,
          ),
        );

  // ── Write ──────────────────────────────────────────────────────────

  Future<void> saveTokens({
    required String accessToken,
    required String? refreshToken,
    required String? idToken,
    required DateTime expiresAt,
  }) async {
    await Future.wait([
      _storage.write(key: _keyAccessToken, value: accessToken),
      if (refreshToken != null)
        _storage.write(key: _keyRefreshToken, value: refreshToken),
      if (idToken != null)
        _storage.write(key: _keyIdToken, value: idToken),
      _storage.write(
        key: _keyTokenExpiry,
        value: expiresAt.toIso8601String(),
      ),
    ]);
  }

  // ── Read ───────────────────────────────────────────────────────────

  Future<String?> get accessToken =>
      _storage.read(key: _keyAccessToken);

  Future<String?> get refreshToken =>
      _storage.read(key: _keyRefreshToken);

  Future<String?> get idToken =>
      _storage.read(key: _keyIdToken);

  Future<DateTime?> get tokenExpiry async {
    final raw = await _storage.read(key: _keyTokenExpiry);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  /// Returns true if we have a stored access token that hasn't expired yet.
  Future<bool> get hasValidToken async {
    final token = await accessToken;
    final expiry = await tokenExpiry;
    if (token == null || expiry == null) return false;
    return DateTime.now().isBefore(expiry);
  }

  /// Returns true if we have a refresh token (regardless of access token expiry).
  Future<bool> get hasRefreshToken async {
    final token = await refreshToken;
    return token != null && token.isNotEmpty;
  }

  // ── Delete ─────────────────────────────────────────────────────────

  Future<void> clearAll() async {
    await Future.wait([
      _storage.delete(key: _keyAccessToken),
      _storage.delete(key: _keyRefreshToken),
      _storage.delete(key: _keyIdToken),
      _storage.delete(key: _keyTokenExpiry),
    ]);
  }
}
