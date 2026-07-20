/// Shared search semantics for every employee messaging inbox surface.
///
/// Queries are accent-insensitive, punctuation-insensitive and use AND
/// semantics: every non-empty token must be present somewhere in the indexed
/// values. Numeric tokens also match a compact digits-only projection so a
/// formatted Chilean phone can be found with or without spaces and `+`.
abstract final class ConversationSearch {
  static String normalize(String? value) {
    final text = value?.trim().toLowerCase() ?? '';
    return text
        .replaceAll(RegExp(r'[áàäâãåā]'), 'a')
        .replaceAll(RegExp(r'[éèëêē]'), 'e')
        .replaceAll(RegExp(r'[íìïîī]'), 'i')
        .replaceAll(RegExp(r'[óòöôõøō]'), 'o')
        .replaceAll(RegExp(r'[úùüûū]'), 'u')
        .replaceAll('ñ', 'n')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static bool matches(
    String normalizedQuery,
    Iterable<Object?> values,
  ) {
    if (normalizedQuery.isEmpty) return true;

    final rawHaystack = values
        .where((value) => value != null)
        .map((value) => value.toString())
        .join(' ');
    final haystack = normalize(rawHaystack);
    final compactDigits = rawHaystack.replaceAll(RegExp(r'[^0-9]'), '');

    return normalizedQuery.split(' ').where((token) => token.isNotEmpty).every(
          (token) =>
              haystack.contains(token) ||
              (RegExp(r'^\d+$').hasMatch(token) &&
                  compactDigits.contains(token)),
        );
  }
}
