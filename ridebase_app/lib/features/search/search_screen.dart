import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers/search_provider.dart';
import 'models/search_models.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _originController =
      TextEditingController(text: '-17.82629, 31.05037');
  final TextEditingController _destinationController = TextEditingController();

  // Track which field is currently active
  String _activeType = 'destination';

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _onSelection(AutocompleteSuggestion suggestion) async {
    // 1. Update text field immediately
    if (_activeType == 'origin') {
      _originController.text = suggestion.description;
    } else {
      _destinationController.text = suggestion.description;
    }

    // 2. Fetch coordinates
    // We show a simple overlay or just wait (since it's fast)
    final service = ref.read(searchServiceProvider);
    final coords = await service.getPlaceCoordinates(suggestion.placeId);

    if (coords != null && mounted) {
      // 3. Return result to MapScreen
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

            // Input Fields area
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Row(
                children: [
                  // Vertical Tracking Line
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
                      Container(
                        width: 2,
                        height: 48,
                        color: Colors.grey.shade300,
                      ),
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.teal.shade900,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),

                  // Text Fields
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
                    icon: Icons.my_location,
                    label: 'Use current location',
                    onTap: () {},
                  ),
                  const SizedBox(width: 12),
                  _ActionChip(
                    icon: Icons.location_on,
                    label: 'Choose on map',
                    onTap: () {},
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
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.teal.shade50,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.teal.shade800),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.teal.shade800,
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
