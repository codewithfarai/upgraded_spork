import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/active_ride_provider.dart';
import '../providers/ride_rest_provider.dart';
import '../../../core/providers/auth_provider.dart';

class RideRatingScreen extends ConsumerStatefulWidget {
  const RideRatingScreen({super.key});

  @override
  ConsumerState<RideRatingScreen> createState() => _RideRatingScreenState();
}

class _RideRatingScreenState extends ConsumerState<RideRatingScreen> {
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
    if (ride.rideId == null || user == null) {
      _dismiss();
      return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(rideRestServiceProvider).rateDriver(
            rideId: ride.rideId!,
            riderId: user.sub,
            driverId: ride.driver?.driverId ?? '',
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

    return Scaffold(
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, size: 80, color: Colors.green),
                const SizedBox(height: 24),
                const Text(
                  'Trip Completed!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (ride.driver != null) ...[
                  Text(
                    'Driver: ${ride.driver!.name}',
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                ],
                if (ride.acceptedAmount > 0 || ride.distanceKm > 0)
                  Text(
                    '\$${ride.acceptedAmount.toStringAsFixed(2)}  •  ${ride.distanceKm.toStringAsFixed(1)} km',
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                const SizedBox(height: 48),
                const Text(
                  'How was your ride?',
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
                    hintText: 'Share your experience...',
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
                    child: _loading
                        ? const CircularProgressIndicator(strokeWidth: 2)
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
