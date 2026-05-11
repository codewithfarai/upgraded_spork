import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/theme.dart';
import 'core/providers/auth_provider.dart';
import 'features/map/map_screen.dart';
import 'features/search/search_screen.dart';
import 'features/ride/presentation/sos_screen.dart';
import 'features/ride/presentation/ride_rating_screen.dart';
import 'features/ride/presentation/driver_rating_screen.dart';
import 'features/onboarding/providers/onboarding_provider.dart';
import 'features/onboarding/presentation/basic_profile_screen.dart';
import 'features/onboarding/presentation/email_verification_screen.dart';
import 'features/onboarding/presentation/driver_setup_screen.dart';
import 'features/auth/presentation/auth_loading_screen.dart';
import 'features/profile/presentation/profile_screen.dart';
import 'features/activity/presentation/activity_screen.dart';
import 'features/driver/presentation/driver_dashboard_screen.dart';
import 'features/driver/presentation/earnings_screen.dart';
import 'features/fleet/presentation/fleet_screen.dart';
import 'features/ride_options/presentation/ride_options_screen.dart';

import 'features/ride/models/ride_websocket_models.dart' as import_models;
import 'features/ride/providers/ride_websocket_provider.dart' as import_ws_provider;
import 'features/ride/presentation/driver_request_overlay.dart' as import_driver_overlay;

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
    ref.listen(authProvider, (_, _) => notifyListeners());
    ref.listen(onboardingProvider, (_, _) => notifyListeners());
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
          return null; // Handled above

        case OnboardingStep.unauthenticated:
          // Auth is authenticated but the profile fetch failed (network error,
          // 401, etc.). Don't trap the user on /loading — fall back to the map
          // so they can use the app and retry by signing out and back in.
          if (state.matchedLocation == '/loading') return '/home';
          return null;

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
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return SearchScreen(
            initialOriginAddress: extra?['originAddress'] as String?,
            initialOriginLat: extra?['originLat'] as double?,
            initialOriginLng: extra?['originLng'] as double?,
          );
        },
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
        path: '/driver-rating',
        builder: (context, state) => const DriverRatingScreen(),
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
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/activity',
        builder: (context, state) => const ActivityScreen(),
      ),
      GoRoute(
        path: '/driver_dashboard',
        builder: (context, state) => const DriverDashboardScreen(),
      ),
      GoRoute(
        path: '/earnings',
        builder: (context, state) => const EarningsScreen(),
      ),
      GoRoute(
        path: '/fleet',
        builder: (context, state) => const FleetScreen(),
      ),
      GoRoute(
        path: '/ride_options',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return RideOptionsScreen(
            pickup: extra?['pickup'] as String?,
            destination: extra?['destination'] as String?,
            distanceKm: extra?['distanceKm'] as double?,
          );
        },
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

    // Global listener for incoming driver requests
    ref.listen<AsyncValue<import_models.RideWsEvent>>(
      import_ws_provider.rideWebSocketEventsProvider,
      (previous, next) {
        final event = next.value;
        if (event is import_models.DriverRideRequestReceivedEvent) {
          // Show the incoming request overlay
          final navContext = router.routerDelegate.navigatorKey.currentContext;
          if (navContext != null) {
            showGeneralDialog(
              context: navContext,
              barrierDismissible: false,
              barrierColor: Colors.black87,
              transitionDuration: const Duration(milliseconds: 300),
              pageBuilder: (ctx, anim1, anim2) => import_driver_overlay.DriverRequestOverlay(requestEvent: event),
            );
          }
        }
      },
    );

    return MaterialApp.router(
      title: 'RideBase',
      debugShowCheckedModeBanner: false,
      theme: RideBaseTheme.lightTheme,
      routerConfig: router,
    );
  }
}
