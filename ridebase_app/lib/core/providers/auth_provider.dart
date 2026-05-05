import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

// ── Auth State ───────────────────────────────────────────────────────

/// Represents the current authentication state of the app.
class AuthState {
  final bool isLoading;
  final bool isAuthenticated;
  final RideBaseUser? user;
  final String? error;

  const AuthState({
    this.isLoading = false,
    this.isAuthenticated = false,
    this.user,
    this.error,
  });

  AuthState copyWith({
    bool? isLoading,
    bool? isAuthenticated,
    RideBaseUser? user,
    String? error,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      user: user ?? this.user,
      error: error,
    );
  }

  /// Initial state before any auth check has been performed.
  static const initial = AuthState(isLoading: true);

  /// Unauthenticated state after checking tokens.
  static const unauthenticated = AuthState(isLoading: false);
}

// ── Auth Notifier ────────────────────────────────────────────────────

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;

  AuthNotifier(this._authService) : super(AuthState.initial);

  /// Called once on app startup to check for stored tokens.
  Future<void> initialize() async {
    // If we've already resolved auth (e.g. from a login that just finished
    // before init ran), don't overwrite it.
    if (state.isAuthenticated) return;

    try {
      // First, try to get the user from stored ID token (instant, no network)
      final storedUser = await _authService.getCurrentUser();
      if (storedUser != null) {
        debugPrint('[AuthNotifier] initialize: Found stored user: ${storedUser.displayName}');
        state = AuthState(
          isLoading: false,
          isAuthenticated: true,
          user: storedUser,
        );

        // Then try a silent refresh in the background to get fresh tokens
        try {
          final refreshResult = await _authService.tryRefresh();
          if (refreshResult != null && refreshResult.success) {
            state = AuthState(
              isLoading: false,
              isAuthenticated: true,
              user: refreshResult.user ?? storedUser,
            );
          }
        } catch (e) {
          // If silent refresh fails (e.g. network), we still keep the storedUser session.
          debugPrint('[AuthNotifier] Silent refresh failed during init: $e');
        }
        return;
      }

      // No stored user — try refresh token (might exist without decoded ID token)
      final refreshResult = await _authService.tryRefresh();
      if (refreshResult != null && refreshResult.success) {
        state = AuthState(
          isLoading: false,
          isAuthenticated: true,
          user: refreshResult.user,
        );
        return;
      }

      debugPrint('[AuthNotifier] initialize: No session found');
      state = AuthState.unauthenticated;
    } catch (e) {
      debugPrint('[AuthNotifier] initialize: Error during init: $e');
      if (!state.isAuthenticated) {
        state = AuthState.unauthenticated;
      }
    }
  }

  /// Open Authentik login page in browser.
  Future<void> login() async {
    state = state.copyWith(isLoading: true, error: null);

    final result = await _authService.login();

    if (result.success) {
      debugPrint('[AuthNotifier] login: Success');
      state = AuthState(
        isLoading: false,
        isAuthenticated: true,
        user: result.user,
      );
    } else {
      debugPrint('[AuthNotifier] login: Failed: ${result.error}');
      state = state.copyWith(
        isLoading: false,
        error: result.error,
      );
    }
  }

  // signup() removed — sign-up is handled via the "Sign up" link on
  // the Authentik login page, which preserves the OAuth PKCE context.
  // After enrollment, login() handles the resulting tokens identically.

  /// Log out: clear tokens and update state immediately, then clear browser session.
  Future<void> logout() async {
    state = state.copyWith(isLoading: true);

    // 1. Get the ID token before clearing everything
    final idToken = await _authService.tokenStorage.idToken;

    debugPrint('[AuthNotifier] logout: Clearing tokens and state');
    // 2. Clear local tokens immediately so the app is locally logged out
    await _authService.tokenStorage.clearAll();

    // 3. Update state to unauthenticated IMMEDIATELY.
    state = AuthState.unauthenticated;

    // 4. Try to clear the browser session in the background (fire and forget)
    // so we don't block the app UI on the browser's redirect performance.
    if (idToken != null) {
      _authService.logoutBrowserOnly(idToken).catchError((e) {
        debugPrint('[AuthNotifier] Background browser logout error: $e');
      });
    }
  }
}

// ── Providers ────────────────────────────────────────────────────────

/// The global AuthService instance.
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

/// The global auth state provider.
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  return AuthNotifier(authService);
});

/// Convenient provider for just the current user (or null).
final currentUserProvider = Provider<RideBaseUser?>((ref) {
  return ref.watch(authProvider).user;
});

/// Whether the user is currently authenticated.
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isAuthenticated;
});
