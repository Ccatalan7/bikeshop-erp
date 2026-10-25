import 'package:flutter/foundation.dart';

import '../../../shared/services/tenant_service.dart';
import 'catalog_search_models.dart';
import 'catalog_web_service.dart';

/// «Búsquedas» of the store catalog: the searches without results and the
/// search's vocabulary, read apart from the catalog's projection (a word
/// added changes no product row, and the catalog does not wait for them).
class CatalogSearchController extends ChangeNotifier {
  CatalogSearchController({
    CatalogWebService? service,
    TenantService? tenantService,
  })  : _serviceOverride = service,
        _tenantServiceOverride = tenantService;

  // Made when first read, inside the guarded load: a host without Supabase
  // (a test of another tab) shows the tab's error instead of failing.
  final CatalogWebService? _serviceOverride;
  final TenantService? _tenantServiceOverride;
  CatalogWebService? _serviceInstance;
  TenantService? _tenantServiceInstance;
  CatalogWebService get _service =>
      _serviceInstance ??= _serviceOverride ?? CatalogWebService();
  TenantService get _tenantService =>
      _tenantServiceInstance ??= _tenantServiceOverride ?? TenantService();

  String? _tenantId;
  List<CatalogSearchMiss> _misses = const [];
  List<CatalogSearchConcept> _vocabulary = const [];
  bool _loading = false;
  bool _busy = false;
  String? _error;
  int _generation = 0;

  List<CatalogSearchMiss> get misses => _misses;
  List<CatalogSearchConcept> get vocabulary => _vocabulary;
  bool get loading => _loading;
  bool get busy => _busy;
  String? get error => _error;
  bool get loaded => _tenantId != null && _error == null;

  List<CatalogSearchMiss> missesIn(CatalogSearchMissState state) => [
        for (final miss in _misses)
          if (miss.state == state) miss,
      ];

  /// What waits for a decision: the tab's count.
  int get openCount => missesIn(CatalogSearchMissState.open).length;

  /// How many words the store added of its own.
  int get ownWordCount =>
      _vocabulary.fold(0, (sum, concept) => sum + concept.ownWords.length);

  CatalogSearchConcept? concept(String name) {
    for (final concept in _vocabulary) {
      if (concept.concept == name) return concept;
    }
    return null;
  }

  Future<void> load({bool quiet = false}) async {
    final generation = ++_generation;
    if (!quiet) {
      _loading = true;
      _error = null;
      notifyListeners();
    }
    try {
      final tenantId = _tenantId ?? await _tenantService.getTenantId();
      if (tenantId == null || tenantId.isEmpty) {
        throw StateError('No se pudo determinar la tienda activa.');
      }
      final results = await Future.wait<Object>([
        _service.loadSearchMisses(tenantId),
        _service.loadSearchVocabulary(tenantId),
      ]);
      if (generation != _generation) return;
      _tenantId = tenantId;
      _misses = results[0] as List<CatalogSearchMiss>;
      _vocabulary = results[1] as List<CatalogSearchConcept>;
      _error = null;
    } catch (error) {
      if (generation != _generation) return;
      _error = '$error';
    } finally {
      if (generation == _generation) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<T> _write<T>(Future<T> Function(String tenantId) write) async {
    final tenantId = _tenantId ?? await _tenantService.getTenantId();
    if (tenantId == null || tenantId.isEmpty) {
      throw StateError('No se pudo determinar la tienda activa.');
    }
    _busy = true;
    notifyListeners();
    try {
      final result = await write(tenantId);
      await load(quiet: true);
      return result;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// «Es una palabra de…»: [words] join [concept] (a new group of the
  /// store's own when no group has that name), and [miss] is answered.
  Future<CatalogSearchWordsResult> addWords({
    required String concept,
    required List<String> words,
    CatalogSearchMiss? miss,
    String? label,
  }) =>
      _write(
        (tenantId) => _service.addSearchWords(
          tenantId: tenantId,
          concept: concept,
          words: words,
          missTerm: miss?.term,
          label: label,
        ),
      );

  Future<bool> removeWord({required String concept, required String word}) =>
      _write(
        (tenantId) => _service.removeSearchWord(
          tenantId: tenantId,
          concept: concept,
          word: word,
        ),
      );

  Future<void> setIgnored(CatalogSearchMiss miss, {required bool ignored}) =>
      _write(
        (tenantId) => _service.closeSearchMiss(
          tenantId: tenantId,
          term: miss.term,
          ignored: ignored,
        ),
      );
}
