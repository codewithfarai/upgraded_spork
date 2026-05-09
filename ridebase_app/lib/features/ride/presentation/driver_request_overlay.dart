import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../features/onboarding/providers/onboarding_provider.dart';
import '../../../features/fleet/providers/fleet_provider.dart';
import '../models/ride_websocket_models.dart';
import '../providers/ride_rest_provider.dart';
import '../providers/ride_websocket_provider.dart';

class DriverRequestOverlay extends ConsumerStatefulWidget {
  final DriverRideRequestReceivedEvent requestEvent;

  const DriverRequestOverlay({super.key, required this.requestEvent});

  @override
  ConsumerState<DriverRequestOverlay> createState() => _DriverRequestOverlayState();
}

class _DriverRequestOverlayState extends ConsumerState<DriverRequestOverlay> {
  bool _isProcessing = false;

  Future<void> _acceptRequest(double amount) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final user = ref.read(currentUserProvider)!;
      final restService = ref.read(rideRestServiceProvider);
      final wsService = ref.read(rideWebSocketServiceProvider);

      // Gather real driver profile data
      final profile = ref.read(onboardingProvider).profile;
      final statsAsync = ref.read(driverStatsProvider);
      final stats = statsAsync.valueOrNull;
      final vehicles = ref.read(vehiclesProvider).valueOrNull ?? [];
      final vehicleDesc = vehicles.isNotEmpty
          ? '${vehicles.first.make} ${vehicles.first.model}'
          : user.displayName;

      // REST confirmation
      await restService.driverAccept(
        rideId: widget.requestEvent.rideId,
        driverId: user.sub,
        offerAmount: amount,
      );

      wsService.submitDriverOffer(
        rideOfferId: const Uuid().v4(),
        rideId: widget.requestEvent.rideId,
        offerAmount: amount,
        riderOfferAmount: widget.requestEvent.offerAmount,
        recommendedAmount: widget.requestEvent.recommendedAmount,
        isCounterOffer: amount != widget.requestEvent.offerAmount,
        etaToPickupMinutes: widget.requestEvent.etaToPickupMinutes ?? 5,
        distance: widget.requestEvent.distanceToPickupKm ?? 2.5,
        pickupAddress: widget.requestEvent.pickupAddress,
        destinationAddress: widget.requestEvent.destinationAddress,
        pickupLat: widget.requestEvent.startLocation.latitude,
        pickupLng: widget.requestEvent.startLocation.longitude,
        destLat: widget.requestEvent.destinationLocation.latitude,
        destLng: widget.requestEvent.destinationLocation.longitude,
        offerTime: DateTime.now(),
        driver: WsDriverInfo(
          driverId: user.sub,
          name: profile?.fullName ?? user.displayName,
          phoneNumber: profile?.phoneNumber ?? '',
          rating: stats?.rating ?? 5.0,
          ridesCompleted: stats?.totalTrips ?? 0,
          vehicle: vehicleDesc,
        ),
      );

      if (mounted) {
        Navigator.of(context).pop(true); // Close overlay returning success
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to accept: $e')),
        );
      }
    }
  }

  void _showCounterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CounterOfferSheet(
        initialAmount: widget.requestEvent.offerAmount,
        onSubmit: (newAmount) {
          Navigator.of(ctx).pop(); // pop sheet
          _acceptRequest(newAmount); // submit as counter
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.requestEvent;

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.9),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),

              // Animated Pulse Icon
              Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.8, end: 1.2),
                  duration: const Duration(milliseconds: 800),
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: RideBaseTheme.teal.withValues(alpha: 0.2),
                        ),
                        child: const Icon(Icons.directions_car, size: 64, color: RideBaseTheme.teal),
                      ),
                    );
                  },
                  onEnd: () {},
                ),
              ),

              const SizedBox(height: 32),

              Text(
                'Incoming Ride Request',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                '${req.etaToPickupMinutes ?? 5} min away · ${req.distanceToPickupKm?.toStringAsFixed(1) ?? '2.5'} km',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 16, color: Colors.white70),
              ),

              const SizedBox(height: 48),

              // Route Info
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.circle, size: 12, color: RideBaseTheme.teal),
                        const SizedBox(width: 16),
                        Expanded(child: Text(req.pickupAddress, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600))),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 5, top: 8, bottom: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(width: 2, height: 24, color: Colors.grey.shade300),
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 16, color: RideBaseTheme.primaryContainer),
                        const SizedBox(width: 12),
                        Expanded(child: Text(req.destinationAddress, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600))),
                      ],
                    ),
                    const Divider(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Rider Offer', style: GoogleFonts.inter(fontSize: 16, color: Colors.grey.shade600)),
                        Text('\$${req.offerAmount.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Actions
              if (_isProcessing)
                const Center(child: CircularProgressIndicator(color: RideBaseTheme.teal))
              else
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(false), // Decline
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white24,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('Decline', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _showCounterSheet,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('Counter', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 16),

              if (!_isProcessing)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _acceptRequest(req.offerAmount),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: RideBaseTheme.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Accept Ride', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CounterOfferSheet extends StatefulWidget {
  final double initialAmount;
  final ValueChanged<double> onSubmit;

  const _CounterOfferSheet({required this.initialAmount, required this.onSubmit});

  @override
  State<_CounterOfferSheet> createState() => _CounterOfferSheetState();
}

class _CounterOfferSheetState extends State<_CounterOfferSheet> {
  late double _amount;

  @override
  void initState() {
    super.initState();
    _amount = widget.initialAmount + 1.0; // Default counter is slightly higher
  }

  void _adjust(double delta) {
    setState(() {
      _amount += delta;
      if (_amount < 1) _amount = 1; // Min 1 dollar
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 24),
          Text('Enter Counter Offer', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () => _adjust(-0.5),
                icon: const Icon(Icons.remove_circle_outline, size: 48, color: Colors.grey),
              ),
              const SizedBox(width: 24),
              Text(
                '\$${_amount.toStringAsFixed(2)}',
                style: GoogleFonts.inter(fontSize: 48, fontWeight: FontWeight.w900, color: RideBaseTheme.teal),
              ),
              const SizedBox(width: 24),
              IconButton(
                onPressed: () => _adjust(0.5),
                icon: const Icon(Icons.add_circle_outline, size: 48, color: RideBaseTheme.teal),
              ),
            ],
          ),
          const SizedBox(height: 48),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () => widget.onSubmit(_amount),
                style: ElevatedButton.styleFrom(
                  backgroundColor: RideBaseTheme.primaryContainer,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Send Counter Offer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
