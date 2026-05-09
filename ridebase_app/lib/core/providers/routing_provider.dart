import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/routing_service.dart';

final routingServiceProvider = Provider<RoutingService>((ref) {
  return RoutingService();
});
