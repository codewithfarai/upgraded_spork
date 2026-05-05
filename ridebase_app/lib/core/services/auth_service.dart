import 'package:flutter/foundation.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import '../config.dart';
import '../models/user_model.dart';
import 'token_storage.dart';

/// Result of a login or signup attempt.
class AuthResult {
  final bool success;
  final RideBaseUser? user;
  final String? error;

  const AuthResult({required this.success, this.user, this.error});
}

/// Handles OAuth2/OIDC authentication against Authentik via PKCE.
///
/// Uses [FlutterAppAuth] to open a secure browser for login/signup,
/// and manages token lifecycle (exchange, refresh, revoke).
class AuthService {
  final FlutterAppAuth _appAuth = const FlutterAppAuth();
  final TokenStorage _tokenStorage = TokenStorage();

  // ── Authentik OIDC Discovery ─────────────────────────────────────
  // flutter_appauth will auto-discover endpoints from the issuer's
  // .well-known/openid-configuration, but we can also specify them
  // explicitly for faster startup.
  static const String _discoveryUrl =
      '${RideBaseConfig.authBase}/application/o/ridebase/.well-known/openid-configuration';

  // ── Login ────────────────────────────────────────────────────────

  /// Opens the Authentik login page in a secure browser tab.
  /// Returns [AuthResult] with the decoded user on success.
  Future<AuthResult> login() async {
    try {
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          RideBaseConfig.oidcClientId,
          RideBaseConfig.oidcRedirectUri,
          discoveryUrl: _discoveryUrl,
          scopes: RideBaseConfig.oidcScopes,
          promptValues: ['login'], // Force login screen
        ),
      );

      if (result == null) {
        return const AuthResult(success: false, error: 'Login was cancelled.');
      }

      return await _handleTokenResponse(result);
    } catch (e) {
      debugPrint('[AuthService] Login error: $e');
      return AuthResult(success: false, error: _friendlyError(e));
    }
  }

  // ── Sign Up ──────────────────────────────────────────────────────
  // Sign-up is handled via the "Need an account? Sign up." link on the
  // Authentik login page. This preserves the OAuth PKCE context server-side.
  // After enrollment, Authentik auto-logs the user in, issues the auth code,
  // and redirects to ridebase://callback — same as a normal login.

  // ── Silent Refresh ───────────────────────────────────────────────

  /// Attempt to silently refresh the access token using a stored refresh token.
  /// Returns null if no refresh token is available or if the refresh fails.
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

      if (result == null) {
        debugPrint('[AuthService] Token refresh returned null.');
        return null;
      }

      return await _handleTokenResponse(result);
    } catch (e) {
      debugPrint('[AuthService] Token refresh failed: $e');
      // Don't clear tokens here - if it's just a network error,
      // we want to keep the current tokens and try again later.
      return null;
    }
  }

  // ── Logout ───────────────────────────────────────────────────────

  /// Clear only the browser session. Local tokens should be cleared by the caller.
  Future<void> logoutBrowserOnly(String idToken) async {
    try {
      await _appAuth.endSession(
        EndSessionRequest(
          idTokenHint: idToken,
          postLogoutRedirectUrl: RideBaseConfig.oidcLogoutRedirectUri,
          discoveryUrl: _discoveryUrl,
        ),
      );
    } catch (e) {
      debugPrint('[AuthService] Browser session clear error: $e');
    }
  }

  // ── Get Current User ─────────────────────────────────────────────

  /// Try to get the current user from stored tokens without any network call.
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

    // Calculate expiry
    final expiresAt = response.accessTokenExpirationDateTime ??
        DateTime.now().add(const Duration(minutes: 15));

    // Persist tokens
    await _tokenStorage.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      idToken: idToken,
      expiresAt: expiresAt,
    );

    // Decode user from ID token
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

  /// Expose token storage for provider-level access.
  TokenStorage get tokenStorage => _tokenStorage;
}
