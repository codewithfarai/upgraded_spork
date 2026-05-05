import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/ride_session.dart';

class RideState {
  RideState({
    this.session,
    this.status = RideStatus.searching,
  });

  final RideSession? session;
  final RideStatus status;

  RideState copyWith({
    RideSession? session,
    RideStatus? status,
  }) {
    return RideState(
      session: session ?? this.session,
      status: status ?? this.status,
    );
  }
}

class RideNotifier extends StateNotifier<RideState> {
  RideNotifier() : super(RideState(
    // Initializing with a mock session for UI integration testing
    session: RideSession.mock(),
    status: RideStatus.inProgress,
  ));

  void setSession(RideSession session) {
    state = state.copyWith(session: session, status: RideStatus.accepted);
  }

  void updateStatus(RideStatus status) {
    state = state.copyWith(status: status);
  }

  void reset() {
    state = RideState();
  }
}

final rideProvider = StateNotifierProvider<RideNotifier, RideState>((ref) {
  return RideNotifier();
});
