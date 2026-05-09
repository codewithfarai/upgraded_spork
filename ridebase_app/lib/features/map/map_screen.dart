import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:maplibre/maplibre.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:typed_data';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../../core/services/tile_service.dart';
import '../drawer/app_drawer.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:go_router/go_router.dart';
import 'widgets/location_button.dart';
import '../ride/presentation/rider_bidding_sheet.dart' as import_bidding;
import 'widgets/mode_switcher.dart';
import '../ride/presentation/active_ride_panel.dart';
import '../../core/providers/app_role_provider.dart';
import '../ride/providers/active_ride_provider.dart';
import '../../core/providers/routing_provider.dart';
import '../search/providers/search_provider.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  MapController? _mapController;
  bool _isMapLoading = true;
  bool _hasMapError = false;
  bool _driverSymbolAdded = false;
  geo.Position? _currentPosition;
  String _centerAddress = 'Resolving location...';

  // Route preview state
  Map<String, dynamic>? _routeDestination;
  bool _isLoadingRoute = false;

  @override
  void initState() {
    super.initState();
    // Set Harare as default immediately so the map has a starting position
    _currentPosition = geo.Position(
      latitude: RideBaseConfig.defaultLat,
      longitude: RideBaseConfig.defaultLng,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );
    _initializeTileService();
    _tryGetRealLocation();
  }

  Future<void> _tryGetRealLocation() async {
    try {
      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
      }
      if (permission == geo.LocationPermission.denied ||
          permission == geo.LocationPermission.deniedForever) {
        return;
      }

      final pos = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 10));

      if (!mounted) { return; }
      setState(() => _currentPosition = pos);
      _mapController?.animateCamera(
        center: Geographic(lat: pos.latitude, lon: pos.longitude),
        zoom: 15,
        nativeDuration: const Duration(milliseconds: 1000),
      );
    } catch (_) {
      // Keep Harare default
    }
  }

  Future<void> _updateCenterAddress() async {
    if (_mapController == null) return;
    try {
      final camera = _mapController!.camera;
      if (camera != null) {
        final address = await ref.read(searchServiceProvider).reverseGeocode(
          camera.center.lat,
          camera.center.lon,
        );
        if (mounted) {
          setState(() {
            _centerAddress = address ?? 'Unknown location';
            _currentPosition = geo.Position(
              latitude: camera.center.lat,
              longitude: camera.center.lon,
              timestamp: DateTime.now(),
              accuracy: 0,
              altitude: 0,
              heading: 0,
              speed: 0,
              speedAccuracy: 0,
              altitudeAccuracy: 0,
              headingAccuracy: 0,
            );
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _initializeTileService() async {
    try {
      final tileService = TileService();
      tileService.initialize();
      await tileService.checkHealth();
    } catch (_) {}
  }

  Future<void> _loadCarImage() async {
    if (_mapController == null) return;
    try {
      final ByteData bytes = await rootBundle.load('assets/images/car_marker.png');
      final Uint8List list = bytes.buffer.asUint8List();
      if (_mapController?.style != null) {
        await _mapController!.style!.addImage('car-icon', list);
      }
    } catch (_) {}
  }

  Future<void> _drawRoute(
    List<List<double>> geometry,
    double startLat,
    double startLng,
    double destLat,
    double destLng,
  ) async {
    if (_mapController?.style == null) return;

    await _clearRoute();

    final coordPairs = geometry.map((p) => '[${p[0]},${p[1]}]').join(',');
    final lineGeoJson =
        '{"type":"Feature","geometry":{"type":"LineString","coordinates":[$coordPairs]},"properties":{}}';
    final destGeoJson =
        '{"type":"Feature","geometry":{"type":"Point","coordinates":[$destLng,$destLat]},"properties":{}}';
    final startGeoJson =
        '{"type":"Feature","geometry":{"type":"Point","coordinates":[$startLng,$startLat]},"properties":{}}';

    await _mapController!.style!.addSource(GeoJsonSource(id: 'route-source', data: lineGeoJson));
    await _mapController!.style!.addLayer(LineStyleLayer(
      id: 'route-layer',
      sourceId: 'route-source',
      paint: {
        'line-color': '#00C9A7',
        'line-width': 5.0,
        'line-opacity': 0.9,
      },
    ));

    await _mapController!.style!.addSource(GeoJsonSource(id: 'dest-source', data: destGeoJson));
    await _mapController!.style!.addLayer(CircleStyleLayer(
      id: 'dest-layer',
      sourceId: 'dest-source',
      paint: {
        'circle-radius': 10.0,
        'circle-color': '#FF4B55',
        'circle-stroke-width': 3.0,
        'circle-stroke-color': '#FFFFFF',
      },
    ));

    await _mapController!.style!.addSource(GeoJsonSource(id: 'start-source', data: startGeoJson));
    await _mapController!.style!.addLayer(CircleStyleLayer(
      id: 'start-layer',
      sourceId: 'start-source',
      paint: {
        'circle-radius': 8.0,
        'circle-color': '#00C9A7',
        'circle-stroke-width': 3.0,
        'circle-stroke-color': '#FFFFFF',
      },
    ));

    // Fit camera to show the full route
    final midLat = (startLat + destLat) / 2;
    final midLng = (startLng + destLng) / 2;
    final maxDiff = ((startLat - destLat).abs()).clamp(
      (startLng - destLng).abs(),
      double.infinity,
    );
    double zoom = 13;
    if (maxDiff < 0.01) {
      zoom = 15;
    } else if (maxDiff < 0.05) {
      zoom = 13;
    } else if (maxDiff < 0.1) {
      zoom = 12;
    } else if (maxDiff < 0.2) {
      zoom = 11;
    } else {
      zoom = 10;
    }

    _mapController!.animateCamera(
      center: Geographic(lat: midLat, lon: midLng),
      zoom: zoom,
      nativeDuration: const Duration(milliseconds: 1200),
    );
  }

  Future<void> _clearRoute() async {
    if (_mapController?.style == null) return;
    for (final id in ['route-layer', 'dest-layer', 'start-layer']) {
      try { await _mapController!.style!.removeLayer(id); } catch (_) {}
    }
    for (final id in ['route-source', 'dest-source', 'start-source']) {
      try { await _mapController!.style!.removeSource(id); } catch (_) {}
    }
  }

  Future<void> _cancelRoute() async {
    await _clearRoute();
    if (mounted) setState(() => _routeDestination = null);
  }

  Future<void> _handleSearchResults(Map<String, dynamic> result) async {
    if (_mapController == null) return;

    final destLat = (result['lat'] as num).toDouble();
    final destLng = (result['lng'] as num).toDouble();
    final destAddress = result['address'] as String;
    final destName = (result['name'] as String?) ?? destAddress;

    setState(() => _isLoadingRoute = true);

    // Pan toward destination while route loads
    _mapController!.animateCamera(
      center: Geographic(lat: destLat, lon: destLng),
      zoom: 14,
      nativeDuration: const Duration(milliseconds: 700),
    );

    final startLat = _currentPosition?.latitude ?? RideBaseConfig.defaultLat;
    final startLng = _currentPosition?.longitude ?? RideBaseConfig.defaultLng;

    final routeData = await ref.read(routingServiceProvider).getRouteData(
      startLat, startLng, destLat, destLng,
    );

    if (!mounted) return;

    final distanceKm = routeData?.distanceKm ?? 5.5;
    final durationMinutes = routeData?.durationMinutes ?? 12;
    // $2 base + $0.80/km + $0.20/min
    final fare = 2.0 + (distanceKm * 0.8) + (durationMinutes * 0.2);

    if (routeData != null && routeData.geometry.isNotEmpty) {
      await _drawRoute(routeData.geometry, startLat, startLng, destLat, destLng);
    }

    if (!mounted) return;
    setState(() {
      _isLoadingRoute = false;
      _routeDestination = {
        'lat': destLat,
        'lng': destLng,
        'address': destAddress,
        'name': destName,
        'distanceKm': distanceKm,
        'durationMinutes': durationMinutes,
        'fare': fare,
      };
    });
  }

  Future<void> _onRequestRide() async {
    if (_routeDestination == null) return;

    final dest = _routeDestination!;
    final startLat = _currentPosition?.latitude ?? RideBaseConfig.defaultLat;
    final startLng = _currentPosition?.longitude ?? RideBaseConfig.defaultLng;

    final tierId = await context.push('/ride_options', extra: {
      'destination': dest['address'],
      'distanceKm': dest['distanceKm'],
    });

    if (tierId != null && mounted) {
      await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        isDismissible: false,
        enableDrag: false,
        builder: (ctx) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: import_bidding.RiderBiddingSheet(
            startLat: startLat,
            startLng: startLng,
            startAddress: _centerAddress,
            destLat: dest['lat'] as double,
            destLng: dest['lng'] as double,
            destAddress: dest['address'] as String,
            estimatedDistanceKm: dest['distanceKm'] as double,
            estimatedMinutes: dest['durationMinutes'] as int,
            recommendedAmount: dest['fare'] as double,
          ),
        ),
      );
    }
  }

  Future<void> _goToUserLocation() async {
    if (_mapController == null) return;
    try {
      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
      }
      if (permission == geo.LocationPermission.denied ||
          permission == geo.LocationPermission.deniedForever) {
        return;
      }

      final pos = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(accuracy: geo.LocationAccuracy.high),
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;
      setState(() => _currentPosition = pos);
      _mapController!.animateCamera(
        center: Geographic(lat: pos.latitude, lon: pos.longitude),
        zoom: 15,
        nativeDuration: const Duration(milliseconds: 1200),
      );
    } catch (_) {
      if (!mounted) return;
      _mapController!.animateCamera(
        center: Geographic(
          lat: RideBaseConfig.defaultLat,
          lon: RideBaseConfig.defaultLng,
        ),
        zoom: 15,
        nativeDuration: const Duration(milliseconds: 1200),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeRideState = ref.watch(activeRideProvider);
    final currentRole = ref.watch(appRoleProvider);

    ref.listen<ActiveRideState>(activeRideProvider, (previous, next) async {
      if (_mapController?.style == null) return;

      // Clear route when a ride becomes active
      if (next.isActive && (previous == null || !previous.isActive)) {
        await _clearRoute();
        if (mounted) setState(() => _routeDestination = null);
      }

      if (!next.isActive) {
        if (_driverSymbolAdded) {
          try { await _mapController!.style!.removeLayer('driver-layer'); } catch (_) {}
          try { await _mapController!.style!.removeSource('driver-source'); } catch (_) {}
          _driverSymbolAdded = false;
        }
        return;
      }

      if (next.driverLocation != null) {
        final loc = next.driverLocation!;
        final geoJsonData = '''{
          "type": "Feature",
          "geometry": {
            "type": "Point",
            "coordinates": [${loc.longitude}, ${loc.latitude}]
          },
          "properties": {"bearing": 0}
        }''';

        if (!_driverSymbolAdded) {
          _driverSymbolAdded = true;
          await _mapController!.style!.addSource(GeoJsonSource(
            id: 'driver-source',
            data: geoJsonData,
          ));
          await _mapController!.style!.addLayer(SymbolStyleLayer(
            id: 'driver-layer',
            sourceId: 'driver-source',
            layout: {
              'icon-image': 'car-icon',
              'icon-size': 0.5,
              'icon-rotate': ['get', 'bearing'],
              'icon-rotation-alignment': 'map',
              'icon-allow-overlap': true,
            },
          ));
        } else {
          await _mapController!.style!.updateGeoJsonSource(
            id: 'driver-source',
            data: geoJsonData,
          );
        }

        _mapController!.animateCamera(
          center: Geographic(lat: loc.latitude, lon: loc.longitude),
          zoom: 16,
          nativeDuration: const Duration(milliseconds: 1000),
        );
      }
    });

    final bool showCenterPin = !activeRideState.isActive &&
        !_isLoadingRoute &&
        _routeDestination == null;

    return Scaffold(
      key: _scaffoldKey,
      drawer: const AppDrawer(),
      body: Stack(
        children: [
          // ── Full-Screen Map ──────────────────────────────────────
          MapLibreMap(
            options: MapOptions(
              initStyle: RideBaseConfig.mapStyleAsset,
              initCenter: const Geographic(lon: 31.0530, lat: -17.8248),
              initZoom: 13.0,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              _updateCenterAddress();
            },
            onStyleLoaded: (_) async {
              await _loadCarImage();
              setState(() {
                _isMapLoading = false;
                _hasMapError = false;
              });
            },
            onEvent: (event) {
              if (event is MapEventCameraIdle && _routeDestination == null) {
                _updateCenterAddress();
              }
            },
            children: const [MapCompass()],
          ),

          // ── Fixed Center Pin (only when idle) ────────────────────
          if (showCenterPin)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black87.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _centerAddress,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Icon(Icons.location_on, size: 40, color: Colors.redAccent),
                  ],
                ),
              ),
            ),

          // ── Loading Overlay ───────────────────────────────────────
          if (_isMapLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(child: CircularProgressIndicator(color: Colors.white)),
            ),

          // ── Error Overlay ─────────────────────────────────────────
          if (_hasMapError)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: Center(
                child: Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      const Text('Map Loading Failed',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => setState(() {
                          _isMapLoading = true;
                          _hasMapError = false;
                        }),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Hamburger Menu ────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            child: _HamburgerButton(
              onTap: () => _scaffoldKey.currentState?.openDrawer(),
            ),
          ),

          // ── Mode Switcher Header ──────────────────────────────────
          if (!activeRideState.isActive)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 0,
              right: 0,
              child: const ModeSwitcher(),
            ),

          // ── Map Controls (zoom + location) ────────────────────────
          if (!activeRideState.isActive)
            Positioned(
              bottom: 320,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MapControlButton(
                    icon: Icons.add,
                    onTap: () async {
                      try {
                        await _mapController?.animateCamera(
                          zoom: (_mapController!.getCamera().zoom + 1),
                          nativeDuration: const Duration(milliseconds: 200),
                        );
                      } catch (_) {}
                    },
                  ),
                  const SizedBox(height: 2),
                  _MapControlButton(
                    icon: Icons.remove,
                    onTap: () async {
                      try {
                        await _mapController?.animateCamera(
                          zoom: (_mapController!.getCamera().zoom - 1),
                          nativeDuration: const Duration(milliseconds: 200),
                        );
                      } catch (_) {}
                    },
                  ),
                  const SizedBox(height: 16),
                  LocationButton(onPressed: _goToUserLocation),
                ],
              ),
            ),

          // ── Bottom Sheet ──────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: currentRole == AppRole.driver
                ? _buildDriverModeCard()
                : activeRideState.isActive
                    ? const ActiveRidePanel()
                    : _routeDestination != null
                        ? _buildRoutePreviewCard()
                        : _buildWhereToCard(),
          ),
        ],
      ),
    );
  }

  Widget _buildWhereToCard() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, -4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          if (_isLoadingRoute)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  const CircularProgressIndicator(strokeWidth: 3),
                  const SizedBox(height: 12),
                  Text('Finding best route...', style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
            )
          else ...[
            // Search bar tap target
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: InkWell(
                onTap: () async {
                  final result = await context.push('/search', extra: {
                    'originAddress': _centerAddress,
                    'originLat': _currentPosition?.latitude ?? RideBaseConfig.defaultLat,
                    'originLng': _currentPosition?.longitude ?? RideBaseConfig.defaultLng,
                  });
                  if (result != null && result is Map<String, dynamic>) {
                    _handleSearchResults(result);
                  }
                },
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      Icon(Icons.search, color: RideBaseTheme.primaryContainer, size: 28),
                      const SizedBox(width: 12),
                      const Text(
                        'Where to?',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _buildSuggestedLocation(
              icon: Icons.history,
              title: 'Avondale Shopping Centre',
              subtitle: 'King George Rd, Harare',
              lat: -17.7885,
              lng: 31.0365,
            ),
            _buildSuggestedLocation(
              icon: Icons.flight_takeoff,
              title: 'RG Mugabe Intl Airport',
              subtitle: 'Airport Rd, Harare',
              lat: -17.9318,
              lng: 31.0963,
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildDriverModeCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, -4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: RideBaseTheme.teal.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.directions_car_rounded, color: RideBaseTheme.teal, size: 32),
          ),
          const SizedBox(height: 16),
          Text(
            'Driver Mode Active',
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Open your dashboard to start earning',
            style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => context.push('/driver_dashboard'),
            style: ElevatedButton.styleFrom(
              backgroundColor: RideBaseTheme.teal,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: Text(
              'GO TO DASHBOARD',
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoutePreviewCard() {
    final dest = _routeDestination!;
    final distanceKm = dest['distanceKm'] as double;
    final durationMinutes = dest['durationMinutes'] as int;
    final fare = dest['fare'] as double;
    final destName = dest['name'] as String;
    final destAddress = dest['address'] as String;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, -4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Destination + fare summary
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        destName,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        destAddress,
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Icons.access_time_rounded, size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            '$durationMinutes min',
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 16),
                          Icon(Icons.route_rounded, size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            '${distanceKm.toStringAsFixed(1)} km',
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: RideBaseTheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'est. fare',
                        style: TextStyle(fontSize: 11, color: RideBaseTheme.teal, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '\$${fare.toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: RideBaseTheme.primaryContainer),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Action buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                OutlinedButton(
                  onPressed: _cancelRoute,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    side: BorderSide(color: Colors.grey.shade300, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    foregroundColor: Colors.black87,
                  ),
                  child: const Text('Cancel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _onRequestRide,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: RideBaseTheme.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Request Ride',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSuggestedLocation({
    required IconData icon,
    required String title,
    required String subtitle,
    required double lat,
    required double lng,
  }) {
    return InkWell(
      onTap: () => _handleSearchResults({
        'lat': lat,
        'lng': lng,
        'address': subtitle,
        'name': title,
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: RideBaseTheme.secondaryContainer,
              radius: 20,
              child: Icon(icon, color: RideBaseTheme.primaryContainer, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black87),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HamburgerButton extends StatelessWidget {
  const _HamburgerButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shadowColor: Colors.black45,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: 48,
          height: 48,
          child: Icon(Icons.menu, color: RideBaseTheme.textPrimary, size: 24),
        ),
      ),
    );
  }
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 4,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: RideBaseTheme.teal, size: 22),
        ),
      ),
    );
  }
}
