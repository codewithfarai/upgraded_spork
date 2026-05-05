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
  final AuthState _authState;

  OnboardingNotifier(this._onboardingService, this._authState)
      : super(const OnboardingState(step: OnboardingStep.loading)) {
    _init();
  }

  Future<void> _init() async {
    if (!_authState.isAuthenticated) {
      state = const OnboardingState(step: OnboardingStep.unauthenticated);
      return;
    }

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
    await _init();
  }
}

final onboardingServiceProvider = Provider<OnboardingService>((ref) {
  final authService = ref.watch(authServiceProvider);
  return OnboardingService(tokenStorage: authService.tokenStorage);
});

final onboardingProvider = StateNotifierProvider<OnboardingNotifier, OnboardingState>((ref) {
  final onboardingService = ref.watch(onboardingServiceProvider);
  final authState = ref.watch(authProvider);
  return OnboardingNotifier(onboardingService, authState);
});
