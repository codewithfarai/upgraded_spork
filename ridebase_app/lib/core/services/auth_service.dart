import 'package:flutter/foundation.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import '../config.dart';
import '../models/user_model.dart';
import 'token_storage.dart';

class AuthResult {
  final bool success;
  final RideBaseUser? user;
  final String? error;

  const AuthResult({required this.success, this.user, this.error});
}

class AuthService {
  final FlutterAppAuth _appAuth = const FlutterAppAuth();
  final TokenStorage _tokenStorage = TokenStorage();

  static const String _discoveryUrl = RideBaseConfig.oidcDiscoveryUrl;

  // ── Login ────────────────────────────────────────────────────────

  Future<AuthResult> login() async {
    try {
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          RideBaseConfig.oidcClientId,
          RideBaseConfig.oidcRedirectUri,
          discoveryUrl: _discoveryUrl,
          scopes: RideBaseConfig.oidcScopes,
        ),
      );

      return await _handleTokenResponse(result);
    } catch (e) {
      debugPrint('[AuthService] Login error: $e');
      return AuthResult(success: false, error: _friendlyError(e));
    }
  }

  // ── Silent Refresh ───────────────────────────────────────────────

  Future<AuthResult?> tryRefresh() async {
    final storedRefreshToken = await _tokenStorage.refreshToken;
    if (storedRefreshToken == null || storedRefreshToken.isEmpty) {
      debugPrint('[AuthService] No refresh token available.');
      return null;
    }

    try {
      final result = await _appAuth.token(
        TokenRequest(
          RideBaseConfig.oidcClientId,
          RideBaseConfig.oidcRedirectUri,
          discoveryUrl: _discoveryUrl,
          refreshToken: storedRefreshToken,
          scopes: RideBaseConfig.oidcScopes,
        ),
      );

      return await _handleTokenResponse(result);
    } catch (e) {
      debugPrint('[AuthService] Token refresh failed: $e');
      return null;
    }
  }

  // ── Logout ───────────────────────────────────────────────────────

  // Opens the Authentik invalidation flow in a browser (user_logout stage
  // destroys the session cookie, redirect stage returns to the app).
  // This call BLOCKS until ridebase://logout-callback is received — tokens
  // are only cleared after the browser session is gone, so there is no
  // window where a new login AMA can race against a stale logout AMA.
  Future<void> logout() async {
    final idToken = await _tokenStorage.idToken;

    if (idToken != null) {
      try {
        await _appAuth.endSession(
          EndSessionRequest(
            idTokenHint: idToken,
            postLogoutRedirectUrl: RideBaseConfig.oidcLogoutRedirectUri,
            discoveryUrl: _discoveryUrl,
          ),
        );
      } catch (e) {
        // If the user closes the browser tab early, endSession throws.
        // We still clear local tokens so the app is logged out locally.
        debugPrint('[AuthService] Browser logout error (non-fatal): $e');
      }
    }

    await _tokenStorage.clearAll();
  }

  // ── Get Current User ─────────────────────────────────────────────

  Future<RideBaseUser?> getCurrentUser() async {
    final idToken = await _tokenStorage.idToken;
    if (idToken == null) return null;

    try {
      return RideBaseUser.fromJwt(idToken);
    } catch (e) {
      debugPrint('[AuthService] Failed to decode stored ID token: $e');
      return null;
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────

  Future<AuthResult> _handleTokenResponse(TokenResponse response) async {
    final accessToken = response.accessToken;
    final refreshToken = response.refreshToken;
    final idToken = response.idToken;

    if (accessToken == null) {
      return const AuthResult(success: false, error: 'No access token received.');
    }

    final expiresAt = response.accessTokenExpirationDateTime ??
        DateTime.now().add(const Duration(minutes: 15));

    await _tokenStorage.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      idToken: idToken,
      expiresAt: expiresAt,
    );

    RideBaseUser? user;
    if (idToken != null) {
      try {
        user = RideBaseUser.fromJwt(idToken);
      } catch (e) {
        debugPrint('[AuthService] Failed to decode ID token: $e');
      }
    }

    debugPrint('[AuthService] Login successful: ${user?.displayName}');
    return AuthResult(success: true, user: user);
  }

  String _friendlyError(dynamic error) {
    final msg = error.toString();
    if (msg.contains('CANCELED') || msg.contains('cancelled')) {
      return 'Authentication was cancelled.';
    }
    if (msg.contains('network') || msg.contains('SocketException')) {
      return 'Network error. Please check your connection.';
    }
    return 'Authentication failed. Please try again.';
  }

  TokenStorage get tokenStorage => _tokenStorage;
}
