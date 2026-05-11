import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/active_ride_provider.dart';
import '../providers/ride_rest_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme.dart';

class DriverRatingScreen extends ConsumerStatefulWidget {
  const DriverRatingScreen({super.key});

  @override
  ConsumerState<DriverRatingScreen> createState() => _DriverRatingScreenState();
}

class _DriverRatingScreenState extends ConsumerState<DriverRatingScreen> {
  int _rating = 5;
  final _feedbackCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _feedbackCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ride = ref.read(activeRideProvider);
    final user = ref.read(currentUserProvider);
    if (ride.rideId == null || ride.riderId == null || user == null) {
      _dismiss();
      return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(rideRestServiceProvider).rateRider(
            rideId: ride.rideId!,
            riderId: ride.riderId!,
            driverId: user.sub,
            rating: _rating,
            feedback: _feedbackCtrl.text.trim().isEmpty ? null : _feedbackCtrl.text.trim(),
          );
      _dismiss();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _dismiss() {
    ref.read(activeRideProvider.notifier).clear();
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final ride = ref.watch(activeRideProvider);
    final riderName = ride.riderName;

    return Scaffold(
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, size: 80, color: RideBaseTheme.teal),
                const SizedBox(height: 24),
                const Text(
                  'Trip Completed!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (riderName != null)
                  Text(
                    'Rider: $riderName',
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                if (ride.acceptedAmount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '\$${ride.acceptedAmount.toStringAsFixed(2)}  •  ${ride.distanceKm.toStringAsFixed(1)} km',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ),
                const SizedBox(height: 48),
                const Text(
                  'How was your rider?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    return IconButton(
                      icon: Icon(
                        i < _rating ? Icons.star : Icons.star_border,
                        size: 42,
                        color: Colors.amber,
                      ),
                      onPressed: () => setState(() => _rating = i + 1),
                    );
                  }),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _feedbackCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Any comments about your rider?',
                    fillColor: Colors.white,
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: RideBaseTheme.teal,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _loading
                        ? const CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
                        : const Text(
                            'Submit Rating',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: Material(
              elevation: 8,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              color: Theme.of(context).cardColor,
              child: IconButton(
                icon: const Icon(Icons.close, size: 28),
                onPressed: _dismiss,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
