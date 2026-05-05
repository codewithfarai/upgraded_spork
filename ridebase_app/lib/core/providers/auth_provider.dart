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
    try {
      // First, try to get the user from stored ID token (instant, no network)
      final storedUser = await _authService.getCurrentUser();
      if (storedUser != null) {
        // We have a stored session — show the user immediately
        state = AuthState(
          isLoading: false,
          isAuthenticated: true,
          user: storedUser,
        );

        // Then try a silent refresh in the background to get fresh tokens
        final refreshResult = await _authService.tryRefresh();
        if (refreshResult != null && refreshResult.success) {
          state = AuthState(
            isLoading: false,
            isAuthenticated: true,
            user: refreshResult.user ?? storedUser,
          );
        }
        // If refresh fails, we still keep the user logged in with the cached data
        // until the access token is needed and fails server-side.
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

      // No valid session
      state = AuthState.unauthenticated;
    } catch (e) {
      debugPrint('[AuthNotifier] Initialization error: $e');
      state = AuthState.unauthenticated;
    }
  }

  /// Open Authentik login page in browser.
  Future<void> login() async {
    state = state.copyWith(isLoading: true, error: null);

    final result = await _authService.login();

    if (result.success) {
      state = AuthState(
        isLoading: false,
        isAuthenticated: true,
        user: result.user,
      );
    } else {
      state = state.copyWith(
        isLoading: false,
        error: result.error,
      );
    }
  }

  // signup() removed — sign-up is handled via the "Sign up" link on
  // the Authentik login page, which preserves the OAuth PKCE context.
  // After enrollment, login() handles the resulting tokens identically.

  /// Log out: clear tokens and open Authentik logout page.
  Future<void> logout() async {
    state = state.copyWith(isLoading: true);

    await _authService.logout();

    state = AuthState.unauthenticated;
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
