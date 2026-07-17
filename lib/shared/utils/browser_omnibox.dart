String normalizeBrowserHostForMatch(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized.startsWith('www.') ? normalized.substring(4) : normalized;
}

class BrowserInlineCompletion {
  const BrowserInlineCompletion({
    required this.value,
    required this.selectionStart,
  });

  final String value;
  final int selectionStart;

  int get selectionEnd => value.length;
}

/// Builds the Chrome-style inline host completion for an ordered list of
/// visited domains. The caller owns ranking; this helper only accepts a direct
/// host prefix so a normal search phrase is never rewritten unexpectedly.
BrowserInlineCompletion? browserInlineHostCompletion({
  required String query,
  required Iterable<String> rankedHosts,
}) {
  if (query != query.trim() ||
      query.length < 2 ||
      query.contains(RegExp(r'\s')) ||
      query.contains('://')) {
    return null;
  }

  final lowerQuery = query.toLowerCase();
  final keepsWwwPrefix = lowerQuery.startsWith('www.');
  final hostQuery = keepsWwwPrefix ? lowerQuery.substring(4) : lowerQuery;
  if (hostQuery.isEmpty) return null;

  for (final host in rankedHosts) {
    final normalizedHost = normalizeBrowserHostForMatch(host);
    if (!normalizedHost.startsWith(hostQuery) ||
        normalizedHost.length <= hostQuery.length) {
      continue;
    }

    final completion = keepsWwwPrefix ? 'www.$normalizedHost' : normalizedHost;
    return BrowserInlineCompletion(
      value: completion,
      selectionStart: query.length,
    );
  }

  return null;
}

/// Returns a lower score for a stronger local omnibox match.
/// `-1` means the visited site does not match the current input.
int browserSiteMatchRank({
  required String query,
  required String host,
  required String title,
  required String url,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) return 0;

  final normalizedHost = normalizeBrowserHostForMatch(host);
  final normalizedTitle = title.trim().toLowerCase();
  final normalizedUrl = url.trim().toLowerCase();

  if (normalizedHost == normalizedQuery) return 0;
  if (normalizedHost.startsWith(normalizedQuery)) return 1;
  if (normalizedTitle.startsWith(normalizedQuery)) return 2;
  if (normalizedHost.contains(normalizedQuery)) return 3;
  if (normalizedTitle.contains(normalizedQuery)) return 4;
  if (normalizedUrl.contains(normalizedQuery)) return 5;
  return -1;
}
