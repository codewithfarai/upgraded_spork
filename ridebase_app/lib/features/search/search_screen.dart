import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart' as geo;
import '../../core/theme.dart';
import 'providers/search_provider.dart';
import 'models/search_models.dart';

class SearchScreen extends ConsumerStatefulWidget {
  final String? initialOriginAddress;
  final double? initialOriginLat;
  final double? initialOriginLng;

  const SearchScreen({
    super.key,
    this.initialOriginAddress,
    this.initialOriginLat,
    this.initialOriginLng,
  });

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _originController;
  final TextEditingController _destinationController = TextEditingController();
  String _activeType = 'destination';
  bool _isLocatingOrigin = false;

  @override
  void initState() {
    super.initState();
    _originController = TextEditingController(
      text: widget.initialOriginAddress ?? 'Current Location',
    );
  }

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isLocatingOrigin = true);
    try {
      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
      }
      if (permission == geo.LocationPermission.deniedForever ||
          permission == geo.LocationPermission.denied) {
        if (mounted) setState(() => _isLocatingOrigin = false);
        return;
      }
      final pos = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 8));

      if (!mounted) return;
      final address = await ref
          .read(searchServiceProvider)
          .reverseGeocode(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        _originController.text = address ?? 'Current Location';
        _isLocatingOrigin = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLocatingOrigin = false);
    }
  }

  Future<void> _onSelection(AutocompleteSuggestion suggestion) async {
    if (_activeType == 'origin') {
      _originController.text = suggestion.description;
    } else {
      _destinationController.text = suggestion.description;
    }

    final service = ref.read(searchServiceProvider);
    final coords = await service.getPlaceCoordinates(suggestion.placeId);

    if (coords != null && mounted) {
      context.pop({
        'type': _activeType,
        'lat': coords['lat'],
        'lng': coords['lng'],
        'address': suggestion.description,
        'name': suggestion.mainText,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(locationSearchProvider(_activeType));

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.pop(),
                ),
                const Text(
                  'Plan your trip',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),

            // Input Fields
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Row(
                children: [
                  Column(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Container(width: 2, height: 48, color: Colors.grey.shade300),
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: RideBaseTheme.teal,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      children: [
                        TextField(
                          controller: _originController,
                          onChanged: (val) {
                            setState(() => _activeType = 'origin');
                            ref.read(locationSearchProvider('origin').notifier).onQueryChanged(val);
                          },
                          decoration: InputDecoration(
                            hintText: 'Current Location',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            border: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _destinationController,
                          autofocus: true,
                          onChanged: (val) {
                            setState(() => _activeType = 'destination');
                            ref.read(locationSearchProvider('destination').notifier).onQueryChanged(val);
                          },
                          decoration: InputDecoration(
                            hintText: 'Where to?',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            border: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Action Chips
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Row(
                children: [
                  _ActionChip(
                    icon: _isLocatingOrigin ? Icons.hourglass_empty : Icons.my_location,
                    label: _isLocatingOrigin ? 'Locating...' : 'Use current location',
                    onTap: _isLocatingOrigin ? null : _useCurrentLocation,
                  ),
                  const SizedBox(width: 12),
                  _ActionChip(
                    icon: Icons.location_on,
                    label: 'Choose on map',
                    onTap: () => context.pop(), // Return to map for pin-based selection
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            Divider(height: 1, color: Colors.grey.shade200),

            // Result List
            Expanded(
              child: searchState.isLoading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : searchState.suggestions.isEmpty
                      ? _buildEmptyState(searchState.error)
                      : ListView.separated(
                          itemCount: searchState.suggestions.length,
                          separatorBuilder: (context, index) => const Divider(indent: 72, height: 1),
                          itemBuilder: (context, index) {
                            final suggestion = searchState.suggestions[index];
                            return ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.location_on_outlined, size: 20),
                              ),
                              title: Text(
                                suggestion.mainText,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                suggestion.secondaryText,
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                              ),
                              onTap: () => _onSelection(suggestion),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String? error) {
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(error, textAlign: TextAlign.center, style: TextStyle(color: Colors.red.shade300)),
        ),
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.search, size: 48, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        Text(
          'Type to search for a place',
          style: TextStyle(color: Colors.grey.shade500),
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: onTap != null ? RideBaseTheme.secondaryContainer : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: onTap != null ? RideBaseTheme.teal : Colors.grey),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: onTap != null ? RideBaseTheme.teal : Colors.grey,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
