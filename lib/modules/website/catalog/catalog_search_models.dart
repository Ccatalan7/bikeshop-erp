/// «Búsquedas» of the store catalog (2026-10-24, 20261024070000): what
/// visitors search and do not find, and the words the store's search
/// understands.
library;

/// Where a search without results stands.
enum CatalogSearchMissState { open, word, ignored }

/// A search the store listed nothing for (`catalog_search_misses_v1`).
class CatalogSearchMiss {
  const CatalogSearchMiss({
    required this.term,
    required this.typed,
    required this.searches,
    required this.outOfStock,
    required this.firstSeenAt,
    required this.lastSeenAt,
    required this.state,
    this.concept,
  });

  factory CatalogSearchMiss.fromRow(Map<String, dynamic> row) {
    int count(String key) => int.tryParse('${row[key] ?? ''}') ?? 0;
    DateTime when(String key) =>
        DateTime.tryParse('${row[key] ?? ''}')?.toLocal() ?? DateTime(2026);
    return CatalogSearchMiss(
      term: '${row['term'] ?? ''}',
      typed: '${row['typed'] ?? row['term'] ?? ''}',
      searches: count('searches'),
      outOfStock: count('out_of_stock'),
      firstSeenAt: when('first_seen_at'),
      lastSeenAt: when('last_seen_at'),
      state: switch ('${row['state'] ?? ''}') {
        'word' => CatalogSearchMissState.word,
        'ignored' => CatalogSearchMissState.ignored,
        _ => CatalogSearchMissState.open,
      },
      concept: (row['concept'] as String?)?.trim().isEmpty ?? true
          ? null
          : row['concept'] as String,
    );
  }

  /// What the search compares (`catalog_search_normalize_v1`).
  final String term;

  /// As a visitor last wrote it.
  final String typed;
  final int searches;

  /// Products it finds that are out of stock today: then the store does
  /// understand it, and what is missing is stock.
  final int outOfStock;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final CatalogSearchMissState state;

  /// The concept a word was added to.
  final String? concept;

  bool get onlyOutOfStock => outOfStock > 0;
}

/// A concept of the search's vocabulary (`catalog_search_vocabulary_v1`):
/// the shared words and the store's own.
class CatalogSearchConcept {
  const CatalogSearchConcept({
    required this.concept,
    this.name,
    required this.kind,
    required this.terms,
    required this.ownTerms,
    required this.broader,
    required this.phrases,
    required this.ownPhrases,
    required this.shared,
  });

  factory CatalogSearchConcept.fromRow(Map<String, dynamic> row) {
    List<String> words(String key) => [
          for (final word in (row[key] as List?) ?? const []) '$word',
        ];
    return CatalogSearchConcept(
      concept: '${row['concept'] ?? ''}',
      name: (row['label'] as String?)?.trim(),
      kind: '${row['kind'] ?? 'part'}',
      terms: words('terms'),
      ownTerms: words('own_terms'),
      broader: words('broader'),
      phrases: words('phrases'),
      ownPhrases: words('own_phrases'),
      shared: row['shared'] == true,
    );
  }

  /// The key the search reads, without accents (`cinta_llanta`).
  final String concept;

  /// The group's name as the shop writes it (`label`, 20261024080000).
  final String? name;

  /// `part` (a product's name or category says it) or `attribute` (its
  /// technical sheet may say it too).
  final String kind;
  final List<String> terms;
  final List<String> ownTerms;
  final List<String> broader;
  final List<String> phrases;
  final List<String> ownPhrases;

  /// One every store shares; false is the store's own.
  final bool shared;

  /// The group's name as the shop writes it; a group without one shows its
  /// key, capitalized.
  String get label {
    final named = name;
    if (named != null && named.isNotEmpty) return named;
    final key = concept.replaceAll('_', ' ');
    return key.isEmpty ? key : '${key[0].toUpperCase()}${key.substring(1)}';
  }

  List<String> get sharedWords => [...terms, ...phrases];
  List<String> get ownWords => [...ownTerms, ...ownPhrases];
  List<String> get allWords => [...sharedWords, ...ownWords];

  /// Whether [query] (as the search folds it) names this group.
  bool matches(String query) {
    final folded = foldCatalogSearchText(query);
    if (folded.isEmpty) return true;
    return foldCatalogSearchText(concept).contains(folded) ||
        foldCatalogSearchText(label).contains(folded) ||
        allWords.any((word) => word.contains(folded));
  }
}

/// What `catalog_search_add_words_v1` did.
class CatalogSearchWordsResult {
  const CatalogSearchWordsResult({
    required this.concept,
    required this.added,
    required this.already,
    required this.created,
    this.finds,
    this.listed,
  });

  factory CatalogSearchWordsResult.fromJson(Map<String, dynamic> json) {
    List<String> words(String key) => [
          for (final word in (json[key] as List?) ?? const []) '$word',
        ];
    int? count(String key) =>
        json[key] == null ? null : int.tryParse('${json[key]}');
    return CatalogSearchWordsResult(
      concept: '${json['concept'] ?? ''}',
      added: [...words('added_terms'), ...words('added_phrases')],
      already: words('already'),
      created: json['created'] == true,
      finds: count('finds'),
      listed: count('listed'),
    );
  }

  final String concept;
  final List<String> added;
  final List<String> already;
  final bool created;

  /// For the search it answers: the products it finds now (any stock), and
  /// those the store lists.
  final int? finds;
  final int? listed;

  /// One sentence for the operator.
  String describe({String? search}) {
    final parts = <String>[
      if (added.isEmpty)
        'Esas palabras ya estaban en el buscador.'
      else
        '${added.length == 1 ? 'Palabra agregada' : 'Palabras agregadas'}: '
            '${added.map((w) => '«$w»').join(', ')}.',
    ];
    final found = finds;
    if (search != null && found != null) {
      final products = found == 1 ? '1 producto' : '$found productos';
      parts.add(
        found == 0
            ? '«$search» todavía no encuentra productos.'
            : listed == 0
                ? '«$search» ahora encuentra $products, ${found == 1 ? 'agotado' : 'todos agotados'}.'
                : listed == null || listed == found
                    ? '«$search» ahora encuentra $products.'
                    : '«$search» ahora encuentra $products: $listed a la venta.',
      );
    }
    return parts.join(' ');
  }
}

/// The text as the search compares it: lower case, no accents, letters and
/// digits (`catalog_search_normalize_v1` without its measures).
String foldCatalogSearchText(String text) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuunc';
  final buffer = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final at = from.indexOf(char);
    buffer.write(at >= 0 ? to[at] : char);
  }
  return buffer.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}
