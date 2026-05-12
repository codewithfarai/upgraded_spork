import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
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
  String _sessionToken = const Uuid().v4();

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

  Future<void> _onSelection(AutocompleteSuggestion suggestion) async {
    if (_activeType == 'origin') {
      _originController.text = suggestion.description;
    } else {
      _destinationController.text = suggestion.description;
    }

    // Capture current token before resetting — Place Details must send the
    // same token that was used for autocomplete to close the session ($0.005).
    final closingToken = _sessionToken;
    setState(() => _sessionToken = const Uuid().v4());

    final service = ref.read(searchServiceProvider);
    final coords = await service.getPlaceCoordinates(
      suggestion.placeId,
      sessionToken: closingToken,
    );

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
                          onTap: () => setState(() => _activeType = 'origin'),
                          onChanged: (val) {
                            setState(() => _activeType = 'origin');
                            ref.read(locationSearchProvider('origin').notifier).onQueryChanged(val, sessionToken: _sessionToken);
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
                          onTap: () => setState(() => _activeType = 'destination'),
                          onChanged: (val) {
                            setState(() => _activeType = 'destination');
                            ref.read(locationSearchProvider('destination').notifier).onQueryChanged(val, sessionToken: _sessionToken);
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

            const SizedBox(height: 8),
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
