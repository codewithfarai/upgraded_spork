import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../../core/services/tile_service.dart';
import '../drawer/app_drawer.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:go_router/go_router.dart';
import 'widgets/location_button.dart';
import '../search/search_screen.dart';

/// The home screen — a full-screen MapLibre map with drawer navigation.
///
/// Map loads immediately on launch centered on Harare. If location
/// permission is granted, the camera animates to the user's position.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  MapController? _mapController;
  bool _isLocating = false;
  bool _isMapLoading = true;
  bool _hasMapError = false;
  String _mapErrorMessage = '';
  Map<String, dynamic>? _selectedDestination;

  @override
  void initState() {
    super.initState();
    _initializeTileService();
  }

  Future<void> _initializeTileService() async {
    try {
      final tileService = TileService();
      tileService.initialize();
      await tileService.checkHealth();
      debugPrint(
        'Tile service initialized. Status: ${tileService.isHealthy ? "healthy" : "unhealthy"}',
      );
      debugPrint('Active tile source: ${tileService.activeTileSource}');
    } catch (e) {
      debugPrint('Error initializing tile service: $e');
    }
  }

  void _handleSearchResults(Map<String, dynamic> result) {
    setState(() {
      _selectedDestination = result;
    });

    if (_mapController != null) {
      _mapController!.animateCamera(
        center: Geographic(lat: result['lat'], lon: result['lng']),
        zoom: 15,
        nativeDuration: const Duration(milliseconds: 1000),
      );
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: const AppDrawer(),
      body: Stack(
        children: [
          // ── Full-Screen Map ──────────────────────────────────────
          MapLibreMap(
            options: MapOptions(
              initStyle: RideBaseConfig.mapStyleAsset,
              initCenter: const Geographic(
                lon: 31.0530,
                lat: -17.8248,
              ),
              initZoom: 13.0,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              debugPrint('MapLibre controller created');
            },
            onStyleLoaded: (_) {
              debugPrint('Map Style Loaded Successfully');
              setState(() {
                _isMapLoading = false;
                _hasMapError = false;
              });
            },

            children: const [MapCompass()],
          ),

          // ── Loading Indicator ────────────────────────────────────
          if (_isMapLoading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),

          // ── Error Overlay ────────────────────────────────────────
          if (_hasMapError)
            Container(
              color: Colors.black.withOpacity(0.3),
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
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      const Text(
                        'Map Loading Failed',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _mapErrorMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _isMapLoading = true;
                            _hasMapError = false;
                          });
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Hamburger Menu Button ────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            child: _HamburgerButton(
              onTap: () => _scaffoldKey.currentState?.openDrawer(),
            ),
          ),

          // ── Zoom & Location Controls ─────────────────────────────
          Positioned(
            bottom: 320, // Pushed up above the search bottom sheet
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

          // ── 'Where to?' Bottom Sheet ─────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 16,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  // Drag Handle
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Fake Search Bar that opens the real search screen
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: InkWell(
                      onTap: () async {
                        final result = await context.push('/search');
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
                            Icon(
                              Icons.search,
                              color: Colors.teal.shade700,
                              size: 28,
                            ),
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
                  // Recent/Suggested Locations
                  _buildSuggestedLocation(
                    icon: Icons.history,
                    title: 'Avondale Shopping Centre',
                    subtitle: 'King George Rd, Harare',
                  ),
                  _buildSuggestedLocation(
                    icon: Icons.flight_takeoff,
                    title: 'RG Mugabe Intl Airport',
                    subtitle: 'Airport Rd, Harare',
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestedLocation({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.teal.shade50,
              radius: 20,
              child: Icon(icon, color: Colors.teal.shade700, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Request location permission and start tracking if granted.
  Future<void> _requestLocationAndTrack() async {
    try {
      final permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        final requested = await geo.Geolocator.requestPermission();
        if (requested == geo.LocationPermission.denied ||
            requested == geo.LocationPermission.deniedForever) {
          return;
        }
      }

      if (_mapController != null) {
        await _mapController!.enableLocation();
        // Commented out to prevent the map from flying away to the UK during testing
        // await _mapController!.trackLocation();
      }
    } catch (e) {
      debugPrint('Initial tracking error: $e');
    }
  }

  /// Animate the camera to the user's current location with robust error handling.
  Future<void> _goToUserLocation() async {
    if (_isLocating) return;
    _isLocating = true;

    debugPrint('[_goToUserLocation] Start');
    try {
      // 1. Check if services are enabled
      final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled.');
      }

      // 2. Check/Request permissions
      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
        if (permission == geo.LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }

      if (permission == geo.LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied.');
      }

      if (_mapController == null) return;

      // Ensure MapLibre is ready to show location
      await _mapController!.enableLocation();

      // Use the native MapLibre tracking engine, but explicitly reset its state first.
      // This forces it to re-snap the camera even if it was previously cancelled by manual panning.
      try {
        await _mapController!.trackLocation(trackLocation: false);
        await Future.delayed(
          const Duration(milliseconds: 50),
        ); // Tiny yield for native thread
        await _mapController!.trackLocation(trackLocation: true);
      } catch (e) {
        // We silence trackLocation cancelled exceptions since it frequently throws
        // if the user's finger happens to be touching the map while it clicks.
        debugPrint('[_goToUserLocation] Track location reset error: $e');
      }
    } catch (e) {
      debugPrint('[_goToUserLocation] error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      _isLocating = false;
    }
  }
}

/// Floating hamburger (☰) button overlaid on the map.
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

/// Compact zoom control button for the map overlay.
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
