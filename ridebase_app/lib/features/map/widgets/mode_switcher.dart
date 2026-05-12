import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';
import '../../../core/providers/app_role_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../features/onboarding/providers/onboarding_provider.dart';

class ModeSwitcher extends ConsumerWidget {
  const ModeSwitcher({super.key});

  void _onDriverTap(BuildContext context, WidgetRef ref) {
    final profile = ref.read(onboardingProvider).profile;
    if (profile == null || !profile.isDriver) {
      context.push('/onboarding/driver_setup');
      return;
    }
    ref.read(appRoleProvider.notifier).setRole(AppRole.driver);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentRole = ref.watch(appRoleProvider);
    final user = ref.watch(currentUserProvider);

    if (user == null) return const SizedBox.shrink();

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            height: 54,
            width: 240,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1.5,
              ),
            ),
            child: Stack(
              children: [
                // Animated Indicator
                AnimatedAlign(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOutBack,
                  alignment: currentRole == AppRole.rider
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: Container(
                    width: 114,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                  ),
                ),
                // Toggle Buttons
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => ref.read(appRoleProvider.notifier).setRole(AppRole.rider),
                        behavior: HitTestBehavior.opaque,
                        child: Center(
                          child: Text(
                            'RIDER',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: currentRole == AppRole.rider
                                  ? RideBaseTheme.tealDark
                                  : Colors.white.withValues(alpha: 0.7),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _onDriverTap(context, ref),
                        behavior: HitTestBehavior.opaque,
                        child: Center(
                          child: Text(
                            'DRIVER',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: currentRole == AppRole.driver
                                  ? RideBaseTheme.tealDark
                                  : Colors.white.withValues(alpha: 0.7),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
