import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/theme.dart';
import 'core/providers/auth_provider.dart';
import 'features/map/map_screen.dart';
import 'features/search/search_screen.dart';
import 'features/ride/presentation/sos_screen.dart';
import 'features/ride/presentation/ride_rating_screen.dart';
import 'features/onboarding/providers/onboarding_provider.dart';
import 'features/onboarding/presentation/basic_profile_screen.dart';
import 'features/onboarding/presentation/email_verification_screen.dart';
import 'features/onboarding/presentation/driver_setup_screen.dart';
import 'features/auth/presentation/auth_loading_screen.dart';

/// Top-level MaterialApp with GoRouter navigation and RideBase theming.
class RideBaseApp extends ConsumerStatefulWidget {
  const RideBaseApp({super.key});

  @override
  ConsumerState<RideBaseApp> createState() => _RideBaseAppState();
}

/// A custom listenable to trigger GoRouter redirects when state changes.
class RouterNotifier extends ChangeNotifier {
  final Ref ref;

  RouterNotifier(this.ref) {
    ref.listen(authProvider, (_, __) => notifyListeners());
    ref.listen(onboardingProvider, (_, __) => notifyListeners());
  }
}

/// The global router provider to support redirects based on Riverpod state.
final routerProvider = Provider<GoRouter>((ref) {
  final notifier = RouterNotifier(ref);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final onboardingState = ref.read(onboardingProvider);

      debugPrint('[GoRouter] Redirect: path=${state.matchedLocation}, auth=${authState.isAuthenticated}, step=${onboardingState.step}');

      final isGoingToOnboarding = state.matchedLocation.startsWith('/onboarding');
      final isGoingToHome = state.matchedLocation == '/home';

      // While auth is still initializing, stay on the current page (map is
      // guest-accessible so there's no need to block behind a loading screen).
      // Once auth resolves, the redirect below will handle onboarding routing.
      if (authState.isLoading) {
        return null;
      }

      if (!authState.isAuthenticated) {
        // Unauthenticated users can use the app as guests (e.g. Map, Search)
        // But they cannot access onboarding screens or authenticated areas.
        if (isGoingToOnboarding) return '/home';
        if (state.matchedLocation == '/loading') return '/home';
        return null;
      }

      // Auth done but onboarding profile is still being fetched — show loading
      // only once we know the user is authenticated.
      // CRITICAL FIX: If we are already on the home screen (map), don't jump to
      // the loading screen. Let the map stay visible while the profile is
      // fetched in the background to avoid a "reload" flicker.
      if (onboardingState.step == OnboardingStep.loading) {
        if (isGoingToHome) return null;
        if (state.matchedLocation != '/loading') return '/loading';
        return null;
      }

      // User is authenticated. Check onboarding step.
      switch (onboardingState.step) {
        case OnboardingStep.loading:
        case OnboardingStep.unauthenticated:
          return null; // Handled above

        case OnboardingStep.needsProfile:
          if (state.matchedLocation != '/onboarding/profile') return '/onboarding/profile';
          return null;

        case OnboardingStep.needsEmailVerification:
          if (state.matchedLocation != '/onboarding/verify_email') return '/onboarding/verify_email';
          return null;

        case OnboardingStep.needsDriverSetup:
          if (state.matchedLocation != '/onboarding/driver_setup') return '/onboarding/driver_setup';
          return null;

        case OnboardingStep.complete:
          // If they are complete and trying to go to loading or onboarding screens, send to home
          if (state.matchedLocation == '/loading' || isGoingToOnboarding) {
            return '/home';
          }
          return null;
      }
    },
    routes: [
      GoRoute(
        path: '/loading',
        builder: (context, state) => const AuthLoadingScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const MapScreen(),
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) => const SearchScreen(),
      ),
      GoRoute(
        path: '/sos',
        builder: (context, state) => const SosScreen(),
      ),
      GoRoute(
        path: '/rating',
        builder: (context, state) => const RideRatingScreen(),
      ),
      GoRoute(
        path: '/onboarding/profile',
        builder: (context, state) => const BasicProfileScreen(),
      ),
      GoRoute(
        path: '/onboarding/verify_email',
        builder: (context, state) => const EmailVerificationScreen(),
      ),
      GoRoute(
        path: '/onboarding/driver_setup',
        builder: (context, state) => const DriverSetupScreen(),
      ),
    ],
  );
});

class _RideBaseAppState extends ConsumerState<RideBaseApp> {
  @override
  void initState() {
    super.initState();
    // Initialize auth state on app startup (check stored tokens, try refresh)
    // Only call initialize if we haven't already resolved the session
    // (helps with process recreation race conditions).
    Future.microtask(() {
      final currentAuth = ref.read(authProvider);
      if (currentAuth.isLoading && !currentAuth.isAuthenticated) {
        ref.read(authProvider.notifier).initialize();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'RideBase',
      debugShowCheckedModeBanner: false,
      theme: RideBaseTheme.lightTheme,
      routerConfig: router,
    );
  }
}
