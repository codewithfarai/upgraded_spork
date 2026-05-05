import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../services/google_places_service.dart';
import '../models/search_models.dart';

/// Provider for the GooglePlacesService instance.
final searchServiceProvider = Provider<GooglePlacesService>((ref) {
  return GooglePlacesService(Dio());
});

/// StateNotifier for location searching with built-in debouncing.
class SearchNotifier extends StateNotifier<SearchState> {
  SearchNotifier(this._searchService) : super(SearchState());

  final GooglePlacesService _searchService;
  Timer? _debounceTimer;

  void onQueryChanged(String query) {
    _debounceTimer?.cancel();

    if (query.isEmpty || query.length < 2) {
      state = state.copyWith(suggestions: [], isLoading: false);
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      state = state.copyWith(isLoading: true, error: null);

      try {
        final rawSuggestions = await _searchService.getAutocompletePredictions(query);
        final suggestions = rawSuggestions
            .map((json) => AutocompleteSuggestion.fromJson(json))
            .toList();

        state = state.copyWith(suggestions: suggestions, isLoading: false);
      } catch (e) {
        state = state.copyWith(
          isLoading: false,
          error: 'Could not fetch suggestions. Check your API key and billing.'
        );
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}

/// The main provider for search logic, segmented by 'origin' or 'destination'.
final locationSearchProvider = StateNotifierProvider.family<SearchNotifier, SearchState, String>((ref, type) {
  final service = ref.watch(searchServiceProvider);
  return SearchNotifier(service);
});
