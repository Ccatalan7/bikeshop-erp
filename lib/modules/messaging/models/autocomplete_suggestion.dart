enum SuggestionType { job, invoice, product }

class AutocompleteSuggestion {
  final String id;
  final String title;
  final String? subtitle;
  final SuggestionType type;

  const AutocompleteSuggestion({
    required this.id,
    required this.title,
    this.subtitle,
    required this.type,
  });
}
