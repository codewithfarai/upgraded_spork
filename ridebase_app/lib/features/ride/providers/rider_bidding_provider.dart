import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ride_websocket_models.dart';
import 'ride_websocket_provider.dart';

/// State object holding all current offers for the active ride request.
class RiderBiddingState {
  final String? activeRideId;
  final List<RiderOfferReceivedEvent> offers;
  final bool isSearching;

  RiderBiddingState({
    this.activeRideId,
    this.offers = const [],
    this.isSearching = false,
  });

  RiderBiddingState copyWith({
    String? activeRideId,
    List<RiderOfferReceivedEvent>? offers,
    bool? isSearching,
  }) {
    return RiderBiddingState(
      activeRideId: activeRideId ?? this.activeRideId,
      offers: offers ?? this.offers,
      isSearching: isSearching ?? this.isSearching,
    );
  }
}

class RiderBiddingNotifier extends StateNotifier<RiderBiddingState> {
  RiderBiddingNotifier() : super(RiderBiddingState());

  void startSearching(String rideId) {
    state = state.copyWith(
      activeRideId: rideId,
      isSearching: true,
      offers: [], // clear old offers
    );
  }

  void addOffer(RiderOfferReceivedEvent offer) {
    if (state.activeRideId != offer.rideId) return;

    // Replace if it's a counter-offer from the same driver, otherwise add new
    final existingIndex = state.offers.indexWhere((o) => o.driver.driverId == offer.driver.driverId);

    final newOffers = List<RiderOfferReceivedEvent>.from(state.offers);
    if (existingIndex >= 0) {
      newOffers[existingIndex] = offer;
    } else {
      newOffers.add(offer);
    }

    // Sort by offer amount (lowest first)
    newOffers.sort((a, b) => a.offerAmount.compareTo(b.offerAmount));

    state = state.copyWith(offers: newOffers);
  }

  void stopSearching() {
    state = state.copyWith(isSearching: false);
  }

  void clear() {
    state = RiderBiddingState();
  }
}

final riderBiddingProvider = StateNotifierProvider<RiderBiddingNotifier, RiderBiddingState>((ref) {
  final notifier = RiderBiddingNotifier();

  // Listen to WebSocket stream and dispatch to notifier
  ref.listen<AsyncValue<RideWsEvent>>(rideWebSocketEventsProvider, (previous, next) {
    final event = next.value;
    if (event is RiderOfferReceivedEvent) {
      notifier.addOffer(event);
    }
  });

  return notifier;
});
