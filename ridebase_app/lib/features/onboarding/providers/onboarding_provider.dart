import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/auth_provider.dart';
import '../models/onboarding_profile.dart';
import '../services/onboarding_service.dart';

enum OnboardingStep {
  loading,
  unauthenticated,
  needsProfile,
  needsEmailVerification,
  needsDriverSetup,
  complete,
}

class OnboardingState {
  final OnboardingStep step;
  final OnboardingProfile? profile;
  final String? error;

  const OnboardingState({
    required this.step,
    this.profile,
    this.error,
  });
}

class OnboardingNotifier extends StateNotifier<OnboardingState> {
  final OnboardingService _onboardingService;

  OnboardingNotifier(this._onboardingService, AuthState initialAuthState)
      : super(const OnboardingState(step: OnboardingStep.loading)) {
    // We must process the initial auth state if it's already finished loading
    // when this provider is first created, because ref.listen won't fire
    // for the initial state.
    if (!initialAuthState.isLoading) {
      onAuthChanged(initialAuthState);
    }
  }

  /// Called when auth state changes (login/logout) without recreating the notifier.
  Future<void> onAuthChanged(AuthState authState) async {
    if (!authState.isAuthenticated) {
      state = const OnboardingState(step: OnboardingStep.unauthenticated);
      return;
    }

    // Guard: If we are already authenticated and have a finished profile,
    // don't reset to loading (prevents map flicker).
    if (state.step == OnboardingStep.complete) {
      return;
    }

    // Authenticated — fetch profile
    state = const OnboardingState(step: OnboardingStep.loading);
    await _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    try {
      final profile = await _onboardingService.getMyProfile();

      if (profile == null) {
        state = const OnboardingState(step: OnboardingStep.needsProfile);
        return;
      }

      // Check email verification from the onboarding profile (the source of truth).
      // The backend sets email_verified=true in its database immediately when the
      // OTP is verified, so there's no race condition with RabbitMQ/Authentik sync.
      if (!profile.emailVerified) {
        state = OnboardingState(
          step: OnboardingStep.needsEmailVerification,
          profile: profile,
        );
        return;
      }

      if (profile.roleIntent == 'DRIVER' && !profile.isDriver) {
        state = OnboardingState(
          step: OnboardingStep.needsDriverSetup,
          profile: profile,
        );
        return;
      }

      state = OnboardingState(
        step: OnboardingStep.complete,
        profile: profile,
      );
    } catch (e) {
      state = OnboardingState(
        step: OnboardingStep.unauthenticated, // Fallback if error occurs
        error: e.toString(),
      );
    }
  }

  /// Reload onboarding state (e.g. after a step is completed)
  Future<void> refresh() async {
    state = const OnboardingState(step: OnboardingStep.loading);
    await _fetchProfile();
  }
}

final onboardingServiceProvider = Provider<OnboardingService>((ref) {
  final authService = ref.watch(authServiceProvider);
  return OnboardingService(tokenStorage: authService.tokenStorage);
});

final onboardingProvider = StateNotifierProvider<OnboardingNotifier, OnboardingState>((ref) {
  final onboardingService = ref.watch(onboardingServiceProvider);
  // Read auth state once at creation — do NOT watch it (that would recreate
  // the notifier on every auth change, causing the map to reload).
  final initialAuthState = ref.read(authProvider);
  final notifier = OnboardingNotifier(onboardingService, initialAuthState);

  // Listen for auth changes and forward them to the *existing* notifier
  // without recreating it. This is the key fix — the notifier is never
  // destroyed and rebuilt, so the router doesn't get spurious refresh signals.
  ref.listen<AuthState>(authProvider, (previous, next) {
    // Only react once auth finishes loading (ignore intermediate loading ticks).
    if (next.isLoading) return;

    final wasAuthenticated = previous?.isAuthenticated ?? false;
    final wasLoading = previous?.isLoading ?? true;

    // Fire on: initial settle after startup, and on auth status flip (login/logout)
    if (wasLoading || wasAuthenticated != next.isAuthenticated) {
      notifier.onAuthChanged(next);
    }
  });

  return notifier;
});
