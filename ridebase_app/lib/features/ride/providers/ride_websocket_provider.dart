import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/auth_provider.dart';
import '../services/ride_websocket_service.dart';
import '../models/ride_websocket_models.dart';

/// Provides the singleton instance of the RideWebSocketService.
final rideWebSocketServiceProvider = Provider<RideWebSocketService>((ref) {
  final authService = ref.watch(authServiceProvider);

  final service = RideWebSocketService(
    tokenStorage: authService.tokenStorage,
  );

  // Clean up the websocket connection when the provider is disposed
  ref.onDispose(() {
    service.disconnect();
  });

  return service;
});

/// A StreamProvider that exposes the stream of all incoming WebSocket events.
/// UI and other providers can listen to this to react to live ride updates.
final rideWebSocketEventsProvider = StreamProvider<RideWsEvent>((ref) {
  final service = ref.watch(rideWebSocketServiceProvider);
  return service.events;
});
