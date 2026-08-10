import 'package:flutter/foundation.dart';

import '../../../ai_assistant/services/ai_service.dart';
import 'bike_part_taxonomy.dart';
import 'product_identity_extractor.dart';

/// What the photo of one invoice line shows.
///
/// This replaces the per-candidate visual comparison. Comparing the invoice
/// image against each catalog image meant one model call and one image
/// download per candidate per line — for a seven-line AliExpress invoice that
/// was up to twenty-one vision calls and well over a hundred downloads, all on
/// the path between the operator and their first decision.
///
/// Reading the photo **once**, into typed evidence that then matches by text,
/// costs one call per distinct image and is cacheable across invoices, because
/// the same listing photo produces the same reading forever.
class ProductVisualReading {
  const ProductVisualReading({
    required this.familyId,
    required this.terms,
    required this.excludedTerms,
    required this.confidence,
    this.summary,
  });

  /// Family recognized from the photo, resolved through the same taxonomy the
  /// text uses so the two kinds of evidence are directly comparable.
  final String? familyId;

  /// Catalog words the photo supports.
  final Set<String> terms;

  /// Families the photo rules out.
  final Set<String> excludedTerms;

  final double confidence;

  final String? summary;

  static const empty = ProductVisualReading(
    familyId: null,
    terms: <String>{},
    excludedTerms: <String>{},
    confidence: 0,
  );

  bool get isUseful => familyId != null || terms.isNotEmpty;
}

typedef ProductImageAnalyzer = Future<AIProductImageAnalysis?> Function(
  Uint8List bytes, {
  String? fileName,
  String? typedName,
});

/// Reads product photos once and remembers the result.
class ProductVisualReadingService {
  ProductVisualReadingService({
    AIAssistantService? aiAssistantService,
    ProductImageAnalyzer? analyzer,
    this.maxCacheEntries = 64,
  })  : _aiAssistantService = aiAssistantService,
        _analyzer = analyzer;

  final AIAssistantService? _aiAssistantService;
  final ProductImageAnalyzer? _analyzer;
  final int maxCacheEntries;

  final Map<String, ProductVisualReading> _cache =
      <String, ProductVisualReading>{};
  final Map<String, Future<ProductVisualReading>> _inFlight =
      <String, Future<ProductVisualReading>>{};

  int _calls = 0;
  int _primed = 0;

  /// How many model calls this service has actually made. The metrics gate
  /// asserts it stays at one per distinct line image.
  int get modelCalls => _calls;

  /// Readings that arrived free, carried by a call someone else already paid
  /// for. Every one of these is a Gemini call not made.
  int get primedReadings => _primed;

  bool get isAvailable => _analyzer != null || _aiAssistantService != null;

  /// Accepts a reading obtained by another call on the same bytes.
  ///
  /// The title cleaner already sends the photo to the model. Asking a second
  /// time for the object it shows doubled latency and quota for an answer the
  /// first call could have returned. It does now, and lands here.
  void prime({
    required String cacheKey,
    required ProductVisualReading reading,
  }) {
    if (cacheKey.isEmpty || !reading.isUseful) return;
    if (_cache.containsKey(cacheKey)) return;
    _primed++;
    _remember(cacheKey, reading);
  }

  /// Reads [bytes], reusing a previous reading for the same [cacheKey].
  Future<ProductVisualReading> read({
    required String cacheKey,
    required Uint8List? bytes,
    String? fileName,
    String? typedName,
  }) {
    if (bytes == null || bytes.isEmpty || !isAvailable) {
      return Future<ProductVisualReading>.value(ProductVisualReading.empty);
    }
    final cached = _cache[cacheKey];
    if (cached != null) return Future<ProductVisualReading>.value(cached);
    final pending = _inFlight[cacheKey];
    if (pending != null) return pending;

    late final Future<ProductVisualReading> tracked;
    tracked = _read(bytes, fileName, typedName).then((reading) {
      _remember(cacheKey, reading);
      return reading;
    }).whenComplete(() {
      if (identical(_inFlight[cacheKey], tracked)) _inFlight.remove(cacheKey);
    });
    _inFlight[cacheKey] = tracked;
    return tracked;
  }

  Future<ProductVisualReading> _read(
    Uint8List bytes,
    String? fileName,
    String? typedName,
  ) async {
    _calls++;
    try {
      final analysis = _analyzer != null
          ? await _analyzer(bytes, fileName: fileName, typedName: typedName)
          : await _aiAssistantService!.analyzeProductImage(
              bytes,
              fileName: fileName,
              typedName: typedName,
            );
      if (analysis == null) return ProductVisualReading.empty;
      return fromAnalysis(analysis);
    } catch (error) {
      debugPrint('Visual product reading failed: $error');
      return ProductVisualReading.empty;
    }
  }

  void _remember(String key, ProductVisualReading reading) {
    if (maxCacheEntries <= 0) return;
    if (_cache.length >= maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = reading;
  }

  /// Maps a raw model answer onto the canonical taxonomy.
  ///
  /// Public because the answer no longer arrives only from this service's own
  /// call: the title cleaner returns the same structured block, and both paths
  /// must land on one taxonomy family, not two interpretations.
  static ProductVisualReading fromAnalysis(AIProductImageAnalysis analysis) {
    final terms = <String>{
      if (analysis.primaryType.trim().isNotEmpty) analysis.primaryType.trim(),
      ...analysis.catalogTerms,
    };
    final familyId = familyForTerms(
      <String>[analysis.primaryType, ...analysis.catalogTerms],
    );
    return ProductVisualReading(
      familyId: familyId,
      terms: Set<String>.unmodifiable(terms),
      excludedTerms: Set<String>.unmodifiable(analysis.excludedTerms.toSet()),
      confidence: analysis.confidence,
      summary: analysis.visualSummary,
    );
  }

  /// Resolves free-text visual terms to one taxonomy family.
  ///
  /// The primary type is checked first and alone, because a photo caption
  /// legitimately lists neighbouring parts (`cassette`, `rayos`) that are
  /// visible in the same picture but are not the product being bought.
  @visibleForTesting
  static String? familyForTerms(Iterable<String> terms) {
    final ordered = terms
        .map((term) => term.trim())
        .where((term) => term.isNotEmpty)
        .toList(growable: false);
    for (final term in ordered) {
      final family = _familyForSingleTerm(term);
      if (family != null) return family;
    }
    return null;
  }

  static String? _familyForSingleTerm(String term) {
    final profile = ProductIdentityExtractor.extract(
      ProductIdentityInput(name: term),
    );
    final familyId = profile.familyId;
    if (familyId == null) return null;
    return BikePartTaxonomy.byId(familyId) == null ? null : familyId;
  }
}
