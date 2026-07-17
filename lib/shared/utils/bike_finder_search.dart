/// A searchable value that belongs to a bicycle or one of its related records.
class BikeFinderSearchField {
  const BikeFinderSearchField(this.value, {this.weight = 100});

  final String? value;
  final int weight;
}

/// Scores an AND-style relational search.
///
/// Every query token must match at least one field, but the matches may come
/// from different records. This lets `oxford felipe 5497` combine bicycle,
/// customer, and telephone data. Small spelling mistakes are tolerated only
/// for alphabetic/alphanumeric tokens of four or more characters; numeric
/// identifiers and telephone fragments remain exact.
int bikeFinderRelationalSearchScore({
  required String query,
  required List<BikeFinderSearchField> fields,
}) {
  final normalizedQuery = normalizeBikeFinderSearch(query);
  if (normalizedQuery.isEmpty) return 0;

  final queryTokens = normalizedQuery
      .split(RegExp(r'[^a-z0-9]+'))
      .where((token) => token.isNotEmpty)
      .toSet()
      .toList(growable: false);
  if (queryTokens.isEmpty) return 0;

  final candidates = fields
      .map(
        (field) => _NormalizedBikeFinderField(
          value: normalizeBikeFinderSearch(field.value),
          weight: field.weight.clamp(1, 200),
        ),
      )
      .where((field) => field.value.isNotEmpty)
      .toList(growable: false);
  if (candidates.isEmpty) return 0;

  var score = 0;
  for (final token in queryTokens) {
    var bestTokenScore = 0;
    for (final field in candidates) {
      final quality = _tokenMatchQuality(token, field);
      final weighted = quality * field.weight ~/ 100;
      if (weighted > bestTokenScore) bestTokenScore = weighted;
    }
    if (bestTokenScore == 0) return 0;
    score += bestTokenScore;
  }

  for (final field in candidates) {
    if (field.value == normalizedQuery) {
      score += 70 * field.weight ~/ 100;
      break;
    }
    if (field.value.startsWith(normalizedQuery)) {
      score += 45 * field.weight ~/ 100;
      break;
    }
    if (normalizedQuery.length >= 3 && field.value.contains(normalizedQuery)) {
      score += 24 * field.weight ~/ 100;
      break;
    }
  }

  if (queryTokens.length > 1) score += queryTokens.length * 12;
  return score;
}

String normalizeBikeFinderSearch(String? value) {
  return (value ?? '')
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n');
}

int _tokenMatchQuality(String queryToken, _NormalizedBikeFinderField field) {
  final value = field.value;
  final words =
      value.split(RegExp(r'[^a-z0-9]+')).where((word) => word.isNotEmpty);
  final compactValue = value.replaceAll(RegExp(r'[^a-z0-9]+'), '');

  if (value == queryToken || compactValue == queryToken) return 100;
  if (value.startsWith(queryToken) || compactValue.startsWith(queryToken)) {
    return 88;
  }
  if (queryToken.length >= 3 &&
      (value.contains(queryToken) || compactValue.contains(queryToken))) {
    return 68;
  }

  var best = 0;
  for (final word in words) {
    if (word == queryToken) return 96;
    if (queryToken.length >= 2 && word.startsWith(queryToken)) {
      best = best < 84 ? 84 : best;
      continue;
    }
    if (queryToken.length >= 3 && word.contains(queryToken)) {
      best = best < 64 ? 64 : best;
      continue;
    }
    final fuzzyQuality = _fuzzyWordQuality(queryToken, word);
    if (fuzzyQuality > best) best = fuzzyQuality;
  }
  return best;
}

int _fuzzyWordQuality(String queryToken, String candidate) {
  if (queryToken.length < 4 || candidate.length < 4) return 0;
  if (!RegExp('[a-z]').hasMatch(queryToken) ||
      !RegExp('[a-z]').hasMatch(candidate)) {
    return 0;
  }

  final maxDistance = queryToken.length >= 8 ? 2 : 1;
  if ((queryToken.length - candidate.length).abs() > maxDistance) return 0;
  final distance = _boundedDamerauLevenshtein(
    queryToken,
    candidate,
    maxDistance: maxDistance,
  );
  if (distance > maxDistance) return 0;
  return switch (distance) {
    0 => 96,
    1 => 58,
    2 => 42,
    _ => 0,
  };
}

int _boundedDamerauLevenshtein(
  String left,
  String right, {
  required int maxDistance,
}) {
  if (left == right) return 0;
  if ((left.length - right.length).abs() > maxDistance) {
    return maxDistance + 1;
  }

  final rows = List.generate(
    left.length + 1,
    (_) => List<int>.filled(right.length + 1, 0),
  );
  for (var i = 0; i <= left.length; i++) {
    rows[i][0] = i;
  }
  for (var j = 0; j <= right.length; j++) {
    rows[0][j] = j;
  }

  for (var i = 1; i <= left.length; i++) {
    var rowMinimum = maxDistance + 1;
    for (var j = 1; j <= right.length; j++) {
      final substitutionCost =
          left.codeUnitAt(i - 1) == right.codeUnitAt(j - 1) ? 0 : 1;
      var distance = _min3(
        rows[i - 1][j] + 1,
        rows[i][j - 1] + 1,
        rows[i - 1][j - 1] + substitutionCost,
      );
      if (i > 1 &&
          j > 1 &&
          left.codeUnitAt(i - 1) == right.codeUnitAt(j - 2) &&
          left.codeUnitAt(i - 2) == right.codeUnitAt(j - 1)) {
        final transposed = rows[i - 2][j - 2] + 1;
        if (transposed < distance) distance = transposed;
      }
      rows[i][j] = distance;
      if (distance < rowMinimum) rowMinimum = distance;
    }
    if (rowMinimum > maxDistance) return maxDistance + 1;
  }
  return rows[left.length][right.length];
}

int _min3(int first, int second, int third) {
  var result = first < second ? first : second;
  if (third < result) result = third;
  return result;
}

class _NormalizedBikeFinderField {
  const _NormalizedBikeFinderField({
    required this.value,
    required this.weight,
  });

  final String value;
  final int weight;
}
