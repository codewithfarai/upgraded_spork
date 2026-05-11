import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../features/onboarding/providers/onboarding_provider.dart';
import '../providers/ride_rest_provider.dart';
import '../providers/ride_websocket_provider.dart';
import '../providers/rider_bidding_provider.dart';
import '../providers/active_ride_provider.dart';
import '../models/ride_websocket_models.dart';

class RiderBiddingSheet extends ConsumerStatefulWidget {
  final double startLat;
  final double startLng;
  final String startAddress;
  final double destLat;
  final double destLng;
  final String destAddress;
  final double estimatedDistanceKm;
  final int estimatedMinutes;
  final double recommendedAmount;
  final double offerAmount;
  final String? comments;

  const RiderBiddingSheet({
    super.key,
    required this.startLat,
    required this.startLng,
    required this.startAddress,
    required this.destLat,
    required this.destLng,
    required this.destAddress,
    required this.estimatedDistanceKm,
    required this.estimatedMinutes,
    required this.recommendedAmount,
    required this.offerAmount,
    this.comments,
  });

  @override
  ConsumerState<RiderBiddingSheet> createState() => _RiderBiddingSheetState();
}

class _RiderBiddingSheetState extends ConsumerState<RiderBiddingSheet> {
  String? _rideId;
  bool _isLoading = true;
  bool _isAccepting = false;

  @override
  void initState() {
    super.initState();
    _initRideRequest();
  }

  Future<void> _initRideRequest() async {
    try {
      final user = ref.read(currentUserProvider);
      if (user == null) throw Exception('Not logged in');

      final rideGuid = const Uuid().v4();
      final restService = ref.read(rideRestServiceProvider);

      final rideId = await restService.requestRide(
        rideGuid: rideGuid,
        riderId: user.sub,
        riderName: user.displayName,
        riderPhoneNumber: ref.read(onboardingProvider).profile?.phoneNumber ?? '',
        startLat: widget.startLat,
        startLng: widget.startLng,
        startAddress: widget.startAddress,
        destLat: widget.destLat,
        destLng: widget.destLng,
        destAddress: widget.destAddress,
        offerAmount: widget.offerAmount,
        recommendedAmount: widget.recommendedAmount,
        estimatedDistanceKm: widget.estimatedDistanceKm,
        estimatedMinutes: widget.estimatedMinutes,
        comments: widget.comments,
      );

      setState(() {
        _rideId = rideId;
        _isLoading = false;
      });

      // Start the matching session
      ref.read(riderBiddingProvider.notifier).startSearching(rideId);
      ref.read(rideWebSocketServiceProvider).startRiderMatching(rideId, user.sub);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to request ride: $e')),
        );
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _acceptOffer(RiderOfferReceivedEvent offer) async {
    if (_isAccepting) return;
    setState(() => _isAccepting = true);

    try {
      final user = ref.read(currentUserProvider)!;
      final restService = ref.read(rideRestServiceProvider);
      final wsService = ref.read(rideWebSocketServiceProvider);

      // REST Call
      await restService.selectOffer(
        rideId: offer.rideId,
        rideOfferId: offer.rideOfferId,
        riderId: user.sub,
        driverId: offer.driver.driverId,
        offerAmount: offer.offerAmount,
        recommendedAmount: offer.recommendedAmount,
        pickupAddress: offer.pickupAddress,
        destinationAddress: offer.destinationAddress,
        startLat: offer.pickupLocation.latitude,
        startLng: offer.pickupLocation.longitude,
        destLat: offer.destinationLocation.latitude,
        destLng: offer.destinationLocation.longitude,
      );

      // WebSocket Call
      wsService.acceptOffer(
        rideId: offer.rideId,
        rideOfferId: offer.rideOfferId,
        driverId: offer.driver.driverId,
        riderId: user.sub,
        acceptedAmount: offer.offerAmount,
      );

      // Stop searching
      ref.read(riderBiddingProvider.notifier).stopSearching();
      // Keep listening to the ride channel for location updates! We don't stop listening here anymore.

      // Set the active ride so the map takes over tracking
      ref.read(activeRideProvider.notifier).setActiveRide(
        rideId: offer.rideId,
        driver: offer.driver,
        status: 'DriverEnRoute',
        riderId: user.sub,
        acceptedAmount: offer.offerAmount,
        distanceKm: widget.estimatedDistanceKm,
      );

      if (mounted) {
        // Pop the sheet
        Navigator.of(context).pop(offer.rideId);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAccepting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to accept offer: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    if (_rideId != null) {
      final user = ref.read(currentUserProvider);
      if (user != null) {
        ref.read(rideWebSocketServiceProvider).stopRiderListening(_rideId!, user.sub);
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 300,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: RideBaseTheme.teal),
              SizedBox(height: 16),
              Text('Creating Ride Request...'),
            ],
          ),
        ),
      );
    }

    final biddingState = ref.watch(riderBiddingProvider);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: RideBaseTheme.teal),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    biddingState.offers.isEmpty ? 'Finding drivers nearby...' : 'Driver offers — tap to accept',
                    style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel', style: TextStyle(color: Colors.red)),
                )
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),

          // List of Offers
          if (biddingState.offers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  'Waiting for drivers to bid...',
                  style: GoogleFonts.inter(color: Colors.grey, fontSize: 15),
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(20),
                itemCount: biddingState.offers.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final offer = biddingState.offers[index];
                  final isCounter = offer.isCounterOffer;
                  final priceHigher = offer.offerAmount > offer.riderOfferAmount;

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(
                        color: isCounter
                            ? Colors.orange.withValues(alpha: 0.5)
                            : RideBaseTheme.teal.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isCounter)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.orange.shade200),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.swap_horiz_rounded, size: 14, color: Colors.orange.shade700),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Counter Offer',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.orange.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Your offer: \$${offer.riderOfferAmount.toStringAsFixed(2)}',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Row(
                          children: [
                            // Driver Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        offer.driver.name,
                                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                      const SizedBox(width: 6),
                                      Icon(Icons.star_rounded, size: 16, color: Colors.amber[700]),
                                      Text(
                                        (offer.driver.rating ?? 5.0).toStringAsFixed(2),
                                        style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    offer.driver.vehicle,
                                    style: GoogleFonts.inter(color: Colors.grey[700], fontSize: 13),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${offer.etaToPickupMinutes} min away',
                                    style: GoogleFonts.inter(color: RideBaseTheme.teal, fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                            // Price & Accept
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '\$${offer.offerAmount.toStringAsFixed(2)}',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 20,
                                    color: isCounter && priceHigher ? Colors.orange.shade700 : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton(
                                  onPressed: _isAccepting ? null : () => _acceptOffer(offer),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: RideBaseTheme.teal,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                  ),
                                  child: _isAccepting
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                      : const Text('Accept', style: TextStyle(fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
