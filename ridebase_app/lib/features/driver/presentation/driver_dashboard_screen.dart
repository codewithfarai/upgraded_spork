import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme.dart';
import '../../fleet/providers/fleet_provider.dart';

class DriverDashboardScreen extends ConsumerStatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  ConsumerState<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends ConsumerState<DriverDashboardScreen> {
  bool _toggling = false;

  Future<void> _toggle() async {
    if (_toggling) return;
    setState(() => _toggling = true);
    try {
      await ref.read(driverAvailabilityProvider.notifier).toggle();
    } catch (e) {
      if (mounted) {
        final isSubError = e.toString().contains('Subscription required');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            behavior: SnackBarBehavior.floating,
            backgroundColor: isSubError ? Colors.red.shade800 : null,
            action: isSubError
                ? SnackBarAction(
                    label: 'RENEW',
                    textColor: Colors.white,
                    onPressed: () => context.push('/subscription'),
                  )
                : null,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final isOnline = ref.watch(driverAvailabilityProvider);
    final statsAsync = ref.watch(driverStatsProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Driver Dashboard',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Greeting ────────────────────────────────────────────
            Text(
              'Hi, ${user?.displayName ?? 'Driver'}',
              style: GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isOnline ? 'You are online and accepting rides' : 'You are currently offline',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: RideBaseTheme.textSecondary,
              ),
            ),

            const SizedBox(height: 24),

            // ── Subscription Status Card ─────────────────────────────
            if (user != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: user.isSubscribed
                      ? RideBaseTheme.teal.withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: user.isSubscribed
                        ? RideBaseTheme.teal.withValues(alpha: 0.2)
                        : Colors.red.withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      user.isSubscribed ? Icons.verified_rounded : Icons.error_outline_rounded,
                      color: user.isSubscribed ? RideBaseTheme.teal : Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        user.isSubscribed
                            ? 'Subscription Active'
                            : 'Subscription Expired',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: user.isSubscribed ? RideBaseTheme.teal : Colors.red,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.push('/subscription'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        user.isSubscribed ? 'VIEW' : 'RENEW',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: user.isSubscribed ? RideBaseTheme.teal : Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 32),

            // ── Online / Offline Toggle ──────────────────────────────
            GestureDetector(
              onTap: _toggling ? null : _toggle,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isOnline
                        ? [RideBaseTheme.teal, RideBaseTheme.primaryContainer]
                        : [Colors.grey.shade400, Colors.grey.shade500],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: (isOnline ? RideBaseTheme.teal : Colors.grey)
                          .withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                      child: _toggling
                          ? const Center(
                              child: SizedBox(
                                width: 32,
                                height: 32,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : Icon(
                              isOnline
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 40,
                              color: Colors.white,
                            ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isOnline ? 'GO OFFLINE' : 'GO ONLINE',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isOnline ? 'Tap to stop accepting rides' : 'Tap to start accepting rides',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 28),

            // ── Stats ────────────────────────────────────────────────
            statsAsync.when(
              loading: () => const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator(color: RideBaseTheme.teal)),
              ),
              error: (_, _) => _StatsRow(trips: 0, earnings: 0.0, rating: 0.0),
              data: (stats) => _StatsRow(
                trips: stats.tripsToday,
                earnings: stats.earningsToday,
                rating: stats.rating,
              ),
            ),

            const SizedBox(height: 28),

            // ── Quick Actions ────────────────────────────────────────
            Text(
              'QUICK ACTIONS',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: RideBaseTheme.textSecondary,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ActionCard(
                    icon: Icons.directions_car_rounded,
                    label: 'My Fleet',
                    onTap: () => context.push('/fleet'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionCard(
                    icon: Icons.receipt_long_outlined,
                    label: 'Activity',
                    onTap: () => context.push('/activity'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionCard(
                    icon: Icons.bar_chart_rounded,
                    label: 'Earnings',
                    onTap: () => context.push('/earnings'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.trips,
    required this.earnings,
    required this.rating,
  });

  final int trips;
  final double earnings;
  final double rating;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _StatCard(label: "Today's Trips", value: '$trips', icon: Icons.directions_car_rounded)),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: "Today's Earnings",
            value: 'USD ${earnings.toStringAsFixed(2)}',
            icon: Icons.attach_money_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: _StatCard(label: 'Rating', value: rating > 0 ? rating.toStringAsFixed(1) : '—', icon: Icons.star_rounded)),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: RideBaseTheme.teal),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: RideBaseTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: RideBaseTheme.teal.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: RideBaseTheme.teal),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: RideBaseTheme.teal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
