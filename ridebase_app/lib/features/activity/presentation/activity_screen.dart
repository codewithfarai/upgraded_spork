import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme.dart';
import '../../fleet/models/vehicle_model.dart';
import '../../fleet/providers/fleet_provider.dart';

class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final isDriver = user?.isDriver ?? false;

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
          'Activity',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        centerTitle: true,
      ),
      body: isDriver
          ? _DriverActivity(ref: ref)
          : _RiderActivity(),
    );
  }
}

class _DriverActivity extends StatelessWidget {
  const _DriverActivity({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final ridesAsync = ref.watch(driverRidesProvider);

    return ridesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: RideBaseTheme.teal)),
      error: (e, _) => _ErrorState(
        message: 'Could not load activity',
        onRetry: () => ref.invalidate(driverRidesProvider),
      ),
      data: (rides) => rides.isEmpty
          ? const _EmptyState()
          : _RideList(rides: rides),
    );
  }
}

class _RiderActivity extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Rider history endpoint not yet available — show placeholder
    return const _EmptyState(
      message: 'Your ride history will appear here',
    );
  }
}

class _RideList extends StatelessWidget {
  const _RideList({required this.rides});
  final List<RideRecord> rides;

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByDate(rides);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: grouped.length,
      itemBuilder: (context, i) {
        final entry = grouped[i];
        if (entry is String) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
            child: Text(
              entry,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: RideBaseTheme.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          );
        }
        return _RideTile(ride: entry as RideRecord);
      },
    );
  }

  List<dynamic> _groupByDate(List<RideRecord> rides) {
    String? lastDate;
    final items = <dynamic>[];
    for (final ride in rides) {
      final label = _formatDateLabel(ride.createdAt);
      if (label != lastDate) {
        items.add(label);
        lastDate = label;
      }
      items.add(ride);
    }
    return items;
  }

  String _formatDateLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    if (date == today) return 'TODAY';
    if (date == today.subtract(const Duration(days: 1))) return 'YESTERDAY';
    const months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}

class _RideTile extends StatelessWidget {
  const _RideTile({required this.ride});
  final RideRecord ride;

  @override
  Widget build(BuildContext context) {

    Color statusColor;
    IconData statusIcon;
    switch (ride.status.toLowerCase()) {
      case 'completed':
        statusColor = RideBaseTheme.teal;
        statusIcon = Icons.check_circle_outline_rounded;
        break;
      case 'cancelled':
        statusColor = Colors.red.shade400;
        statusIcon = Icons.cancel_outlined;
        break;
      default:
        statusColor = Colors.orange;
        statusIcon = Icons.access_time_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(statusIcon, color: statusColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ride.dropoffAddress,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${ride.pickupAddress} · ${_fmtTime(ride.createdAt)}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: RideBaseTheme.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    ride.rideType,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: RideBaseTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Text(
            'USD ${ride.fare.toStringAsFixed(2)}',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  String _fmtTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final min = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$min $period';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.message = 'No rides yet'});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: RideBaseTheme.teal.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.receipt_long_outlined,
                size: 44,
                color: RideBaseTheme.teal,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              message,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black54,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(message, style: GoogleFonts.inter(color: Colors.black54)),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry', style: TextStyle(color: RideBaseTheme.teal)),
          ),
        ],
      ),
    );
  }
}
