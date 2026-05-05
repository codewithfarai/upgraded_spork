import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'core/theme.dart';
import 'features/map/map_screen.dart';
import 'features/search/search_screen.dart';
import 'features/ride/presentation/sos_screen.dart';
import 'features/ride/presentation/ride_rating_screen.dart';

/// Top-level MaterialApp with GoRouter navigation and RideBase theming.
class RideBaseApp extends StatelessWidget {
  const RideBaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'RideBase',
      debugShowCheckedModeBanner: false,
      theme: RideBaseTheme.lightTheme,
      routerConfig: _router,
    );
  }
}

final GoRouter _router = GoRouter(
  initialLocation: '/home',
  routes: [
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
  ],
);
