class AutocompleteSuggestion {
  AutocompleteSuggestion({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
  });

  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;

  factory AutocompleteSuggestion.fromJson(Map<String, dynamic> json) {
    final structured = json['structured_formatting'] ?? {};
    return AutocompleteSuggestion(
      placeId: json['place_id'] ?? '',
      description: json['description'] ?? '',
      mainText: structured['main_text'] ?? '',
      secondaryText: structured['secondary_text'] ?? '',
    );
  }
}

class SearchState {
  SearchState({
    this.suggestions = const [],
    this.isLoading = false,
    this.error,
  });

  final List<AutocompleteSuggestion> suggestions;
  final bool isLoading;
  final String? error;

  SearchState copyWith({
    List<AutocompleteSuggestion>? suggestions,
    bool? isLoading,
    String? error,
  }) {
    return SearchState(
      suggestions: suggestions ?? this.suggestions,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}
