import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';

import '../providers/active_ride_provider.dart';
import '../providers/ride_rest_provider.dart';
import '../../../core/providers/auth_provider.dart';

class SosScreen extends ConsumerStatefulWidget {
  const SosScreen({super.key});

  @override
  ConsumerState<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends ConsumerState<SosScreen> {
  bool _loading = false;
  bool _sent = false;

  Future<void> _triggerSos() async {
    final rideState = ref.read(activeRideProvider);
    final user = ref.read(currentUserProvider);
    if (!rideState.isActive || user == null) return;

    setState(() => _loading = true);
    try {
      double? lat;
      double? lng;
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (_) {
        // Location permission denied or unavailable — submit SOS without coordinates
      }

      await ref.read(rideRestServiceProvider).riderSos(
            rideId: rideState.rideId!,
            riderId: user.sub,
            driverId: rideState.driver?.driverId,
            tripStatus: rideState.status,
            lat: lat,
            lng: lng,
            message: 'Rider pressed SOS in app.',
          );
      setState(() => _sent = true);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: _sent
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle, size: 80, color: Colors.green),
                        const SizedBox(height: 24),
                        const Text(
                          'Alert Sent Successfully',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Our emergency response team is being notified and will contact you shortly.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        const SizedBox(height: 48),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: () => context.pop(),
                            child: const Text('Back to Ride'),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning_rounded, size: 100, color: Colors.red),
                        const SizedBox(height: 32),
                        const Text(
                          'In an Emergency?',
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Tap the button below to alert our safety team and share your live location for immediate assistance.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 48),
                        SizedBox(
                          width: double.infinity,
                          height: 64,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              elevation: 4,
                            ),
                            onPressed: _loading ? null : _triggerSos,
                            child: _loading
                                ? const CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  )
                                : const Text(
                                    'TRIGGER SOS ALERT',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextButton(
                          onPressed: () => context.pop(),
                          child: Text(
                            'Cancel',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: Material(
              elevation: 8,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              color: Theme.of(context).cardColor,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, size: 28),
                onPressed: () => context.pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
