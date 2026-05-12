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

  /// Parses a `placePrediction` object from the Places API (New) response.
  factory AutocompleteSuggestion.fromJson(Map<String, dynamic> json) {
    final structured = json['structuredFormat'] as Map<String, dynamic>? ?? {};
    final mainText = (structured['mainText'] as Map?)?['text'] as String? ?? '';
    final secondaryText = (structured['secondaryText'] as Map?)?['text'] as String? ?? '';
    final fullText = (json['text'] as Map?)?['text'] as String? ?? mainText;
    return AutocompleteSuggestion(
      placeId: json['placeId'] as String? ?? '',
      description: fullText,
      mainText: mainText,
      secondaryText: secondaryText,
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
