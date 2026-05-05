import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/ride_provider.dart';
import '../data/ride_api_service.dart';
import '../domain/ride_actions.dart';

/// Post-trip rating screen.
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
    final rideState = ref.read(rideProvider);
    final session = rideState.session;
    if (session == null) return;

    setState(() => _loading = true);
    try {
      await RideApiService.submitRating(
        RideRatingRequest(
          rideId: session.rideId,
          riderId: session.riderId,
          driverId: session.driverId ?? '',
          rating: _rating,
          feedback: _feedbackCtrl.text.trim(),
          submittedAtUtc: DateTime.now().toUtc().toIso8601String(),
        ),
      );
      ref.read(rideProvider.notifier).reset();
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(rideProvider).session;

    return Scaffold(
      body: Stack(
        children: [
          // Content
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
                if (session != null) ...[
                  Text(
                    'Driver: ${session.driverName ?? "Driver"}',
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '\$${session.acceptedAmount.toStringAsFixed(2)}  •  ${session.distanceKm.toStringAsFixed(1)} km',
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
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
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),

          // Floating Close Button
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
                onPressed: () {
                  ref.read(rideProvider.notifier).reset();
                  context.go('/home');
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
