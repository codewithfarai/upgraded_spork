import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../core/providers/auth_provider.dart';

/// Navigation drawer matching the MAUI app design:
///   • Teal header with circular avatar
///   • Authenticated: shows user info + Sign Out
///   • Unauthenticated: shows "Welcome to Ridebase" + Sign In / Sign Up
///   • Menu items: Home, Support
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    return Drawer(
      child: Column(
        children: [
          // ── Teal Header ─────────────────────────────────────────
          authState.isAuthenticated
              ? _buildAuthenticatedHeader(context, ref, authState)
              : _buildUnauthenticatedHeader(context, ref, authState),

          // ── Menu Items ──────────────────────────────────────────
          _buildMenuSection(context),
        ],
      ),
    );
  }

  // ── Authenticated Header ──────────────────────────────────────────

  Widget _buildAuthenticatedHeader(
    BuildContext context,
    WidgetRef ref,
    AuthState authState,
  ) {
    final topPadding = MediaQuery.of(context).padding.top;
    final user = authState.user;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, topPadding + 32, 24, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            RideBaseTheme.teal,
            RideBaseTheme.tealDark,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar circle with user initial
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: RideBaseTheme.tealLight.withValues(alpha: 0.4),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                (user?.displayName ?? 'U')[0].toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Username
          Text(
            user?.displayName ?? 'User',
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),

          const SizedBox(height: 6),

          // Email
          if (user?.email != null)
            Text(
              user!.email!,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),

          // Role badge
          if (user != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                user.isDriver ? '🚗 Driver' : '🧑 Rider',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Sign Out button
          SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              onPressed: authState.isLoading
                  ? null
                  : () async {
                      Navigator.of(context).pop();
                      await ref.read(authProvider.notifier).logout();
                    },
              icon: authState.isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: RideBaseTheme.tealDark,
                      ),
                    )
                  : const Icon(Icons.logout, size: 20),
              label: Text(
                'Sign Out',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: RideBaseTheme.tealDark,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Unauthenticated Header ────────────────────────────────────────

  Widget _buildUnauthenticatedHeader(
    BuildContext context,
    WidgetRef ref,
    AuthState authState,
  ) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, topPadding + 32, 24, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            RideBaseTheme.teal,
            RideBaseTheme.tealDark,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar circle
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: RideBaseTheme.tealLight.withValues(alpha: 0.4),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.person,
              size: 40,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 20),

          // Title
          Text(
            'Welcome to Ridebase',
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),

          const SizedBox(height: 6),

          // Subtitle
          Text(
            'Sign in to get started',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),

          const SizedBox(height: 20),

          // Sign In button (Authentik login page also has "Sign up" link)
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: authState.isLoading
                  ? null
                  : () async {
                      Navigator.of(context).pop();
                      await ref.read(authProvider.notifier).login();
                    },
              icon: authState.isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: RideBaseTheme.tealDark,
                      ),
                    )
                  : const Icon(Icons.login, size: 20),
              label: Text(
                'Sign In',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: RideBaseTheme.tealDark,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Menu Section ──────────────────────────────────────────────────

  Widget _buildMenuSection(BuildContext context) {
    return Expanded(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // MENU label
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Text(
              'MENU',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: RideBaseTheme.textSecondary,
                letterSpacing: 1.2,
              ),
            ),
          ),

          // Home
          _DrawerMenuItem(
            icon: Icons.home_rounded,
            label: 'Home',
            isSelected: true,
            onTap: () => Navigator.of(context).pop(),
          ),

          // Support
          _DrawerMenuItem(
            icon: Icons.help_outline_rounded,
            label: 'Support',
            onTap: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Support page coming soon'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Individual menu item in the drawer.
class _DrawerMenuItem extends StatelessWidget {
  const _DrawerMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isSelected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ListTile(
        leading: Icon(
          icon,
          color: isSelected
              ? RideBaseTheme.teal
              : RideBaseTheme.textSecondary,
          size: 26,
        ),
        title: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected
                ? RideBaseTheme.textPrimary
                : RideBaseTheme.textSecondary,
          ),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        selectedTileColor: RideBaseTheme.teal.withValues(alpha: 0.08),
        selected: isSelected,
        onTap: onTap,
      ),
    );
  }
}
