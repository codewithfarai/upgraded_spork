import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

// ── Auth State ───────────────────────────────────────────────────────

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

  static const initial = AuthState(isLoading: true);
  static const unauthenticated = AuthState(isLoading: false);
}

// ── Auth Notifier ────────────────────────────────────────────────────

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;

  AuthNotifier(this._authService) : super(AuthState.initial);

  Future<void> initialize() async {
    if (state.isAuthenticated) return;

    try {
      final storedUser = await _authService.getCurrentUser();
      if (storedUser != null) {
        debugPrint('[AuthNotifier] initialize: Found stored user: ${storedUser.displayName}');
        state = AuthState(isLoading: false, isAuthenticated: true, user: storedUser);

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
          debugPrint('[AuthNotifier] Silent refresh failed during init: $e');
        }
        return;
      }

      final refreshResult = await _authService.tryRefresh();
      if (refreshResult != null && refreshResult.success) {
        state = AuthState(isLoading: false, isAuthenticated: true, user: refreshResult.user);
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

  Future<void> login() async {
    state = state.copyWith(isLoading: true, error: null);

    final result = await _authService.login();

    if (result.success) {
      debugPrint('[AuthNotifier] login: Success');
      state = AuthState(isLoading: false, isAuthenticated: true, user: result.user);
    } else {
      debugPrint('[AuthNotifier] login: Failed: ${result.error}');
      state = state.copyWith(isLoading: false, error: result.error);
    }
  }

  // logout() blocks until the browser tab closes (ridebase://logout-callback
  // received). Tokens are only cleared after endSession completes, so there
  // is no gap where a new login AMA can race a stale logout AMA.
  Future<void> logout() async {
    state = state.copyWith(isLoading: true);
    await _authService.logout();
    state = AuthState.unauthenticated;
  }

  // Called after server-side changes (e.g. driver verification) to pull
  // updated claims from a fresh ID token without a full sign-out/in cycle.
  Future<void> refreshUser() async {
    final result = await _authService.tryRefresh();
    if (result != null && result.success) {
      state = state.copyWith(user: result.user);
    }
  }
}

// ── Providers ────────────────────────────────────────────────────────

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(authServiceProvider));
});

final currentUserProvider = Provider<RideBaseUser?>((ref) {
  return ref.watch(authProvider).user;
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isAuthenticated;
});
