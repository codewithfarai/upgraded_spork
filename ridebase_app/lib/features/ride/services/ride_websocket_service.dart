import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/config.dart';
import '../../../core/services/token_storage.dart';
import '../models/ride_websocket_models.dart';

class RideWebSocketService {
  final TokenStorage _tokenStorage;
  final String _baseUrl;
  WebSocketChannel? _channel;

  // Expose a broadcast stream of typed events
  final _eventController = StreamController<RideWsEvent>.broadcast();
  Stream<RideWsEvent> get events => _eventController.stream;

  bool _isConnected = false;
  bool _isConnecting = false;
  bool _shouldReconnect = true;
  int _reconnectDelayMs = 1000;
  Timer? _reconnectTimer;

  RideWebSocketService({
    required TokenStorage tokenStorage,
    String? baseUrl,
  })  : _tokenStorage = tokenStorage,
        _baseUrl = baseUrl ?? RideBaseConfig.rideWebSocketBase;

  /// Starts the WebSocket connection
  Future<void> connect() async {
    if (_isConnected || _isConnecting) return;

    _isConnecting = true;
    _shouldReconnect = true;

    try {
      final token = await _tokenStorage.accessToken;
      if (token == null) {
        throw Exception('Cannot connect to WebSocket: No access token found');
      }

      final uri = Uri.parse('$_baseUrl?token=$token');
      _channel = WebSocketChannel.connect(uri);

      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      _isConnected = true;
      _isConnecting = false;
      _reconnectDelayMs = 1000; // Reset backoff
      debugPrint('[RideWebSocketService] Connected to $_baseUrl');
    } catch (e) {
      _isConnecting = false;
      _onError(e);
    }
  }

  void _onMessage(dynamic message) {
    try {
      if (message is String) {
        final json = jsonDecode(message) as Map<String, dynamic>;
        final event = RideWsEvent.fromJson(json);
        _eventController.add(event);
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[RideWebSocketService] Error parsing message: $e\n$st');
      }
    }
  }

  void _onError(dynamic error) {
    if (kDebugMode) {
      debugPrint('[RideWebSocketService] WebSocket Error: $error');
    }
    _handleDisconnect();
  }

  void _onDone() {
    if (kDebugMode) {
      debugPrint('[RideWebSocketService] WebSocket Closed');
    }
    _handleDisconnect();
  }

  void _handleDisconnect() {
    _isConnected = false;
    _isConnecting = false;
    _channel = null;

    if (_shouldReconnect) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: _reconnectDelayMs), () {
      connect();
    });

    // Exponential backoff up to ~30 seconds
    _reconnectDelayMs = (_reconnectDelayMs * 1.5).toInt().clamp(1000, 30000);
  }

  /// Gracefully disconnects and stops auto-reconnecting
  void disconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _isConnecting = false;
  }

  // ── Outbound Methods ───────────────────────────────────────────────────

  void _send(Map<String, dynamic> data) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(jsonEncode(data));
    } else {
      debugPrint('[RideWebSocketService] Cannot send message: Not connected');
    }
  }

  // Rider Flow
  void startRiderMatching(String rideId, String riderId) {
    _send({
      'type': 'StartRiderMatching',
      'rideId': rideId,
      'riderId': riderId,
    });
  }

  void acceptOffer({
    required String rideId,
    required String rideOfferId,
    required String driverId,
    required String riderId,
    required double acceptedAmount,
  }) {
    _send({
      'type': 'AcceptOffer',
      'rideId': rideId,
      'rideOfferId': rideOfferId,
      'driverId': driverId,
      'riderId': riderId,
      'acceptedAmount': acceptedAmount,
    });
  }

  void stopRiderListening(String rideId, String riderId) {
    _send({
      'type': 'Stop',
      'rideId': rideId,
      'riderId': riderId,
    });
  }

  // Driver Flow
  void startDriverRequestStream(String driverId) {
    _send({
      'type': 'StartDriverRequestStream',
      'driverId': driverId,
    });
  }

  void submitDriverOffer({
    required String rideOfferId,
    required String rideId,
    required double offerAmount,
    required double riderOfferAmount,
    required double recommendedAmount,
    required bool isCounterOffer,
    required int etaToPickupMinutes,
    required double distance,
    required String pickupAddress,
    required String destinationAddress,
    required double pickupLat,
    required double pickupLng,
    required double destLat,
    required double destLng,
    required DateTime offerTime,
    required WsDriverInfo driver,
  }) {
    _send({
      'type': 'SubmitDriverOffer',
      'data': {
        'rideOfferId': rideOfferId,
        'rideId': rideId,
        'offerAmount': offerAmount,
        'riderOfferAmount': riderOfferAmount,
        'recommendedAmount': recommendedAmount,
        'isCounterOffer': isCounterOffer,
        'etaToPickupMinutes': etaToPickupMinutes,
        'distance': distance,
        'pickupAddress': pickupAddress,
        'destinationAddress': destinationAddress,
        'pickupLocation': {'latitude': pickupLat, 'longitude': pickupLng},
        'destinationLocation': {'latitude': destLat, 'longitude': destLng},
        'offerTime': offerTime.toUtc().toIso8601String(),
        'driver': driver.toJson(),
      }
    });
  }

  void updateRideStatus(String rideId, String status) {
    _send({
      'type': 'UpdateRideStatus',
      'rideId': rideId,
      'status': status,
    });
  }

  void publishDriverLocation({
    required String rideId,
    required String driverId,
    required double lat,
    required double lng,
    required int etaMinutes,
    required double distanceToPickupKm,
  }) {
    _send({
      'type': 'PublishDriverLocation',
      'data': {
        'rideId': rideId,
        'driverId': driverId,
        'currentLocation': {'latitude': lat, 'longitude': lng},
        'etaMinutes': etaMinutes,
        'distanceToPickupKm': distanceToPickupKm,
        'updatedAtUtc': DateTime.now().toUtc().toIso8601String(),
      }
    });
  }

  void completeRide(String rideId) {
    _send({
      'type': 'CompleteRide',
      'rideId': rideId,
    });
  }

  void stopDriverStream(String driverId) {
    _send({
      'type': 'Stop',
      'driverId': driverId,
    });
  }
}
