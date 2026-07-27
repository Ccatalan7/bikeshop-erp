import 'dart:collection';

/// Small session cache for adjacent catalog pages.
///
/// The cache is intentionally bounded and short-lived because public stock
/// includes active reservations. A signature represents every query input
/// except the page number; changing it invalidates cached and in-flight pages.
class CatalogPagePrefetchCache<T> {
  CatalogPagePrefetchCache({
    this.maxAge = const Duration(seconds: 45),
    Duration? retainFor,
    this.maxEntries = 6,
    bool Function(T value)? shouldCache,
    DateTime Function()? now,
  })  : assert(maxEntries > 0),
        assert((retainFor ?? maxAge) >= maxAge),
        retainFor = retainFor ?? maxAge,
        _shouldCache = shouldCache ?? _alwaysCache,
        _now = now ?? DateTime.now;

  /// Time during which a completed value may satisfy a request without
  /// touching the origin.
  final Duration maxAge;

  /// Longer visual-retention window used by stale-while-revalidate.
  ///
  /// After [maxAge], [peek] still returns the stable value so the UI never
  /// collapses to a spinner, while [load] starts one deduplicated origin
  /// refresh. Once [retainFor] elapses the value is removed completely.
  final Duration retainFor;
  final int maxEntries;
  final bool Function(T value) _shouldCache;
  final DateTime Function() _now;
  final LinkedHashMap<String, _CatalogPageCacheEntry<T>> _entries =
      LinkedHashMap<String, _CatalogPageCacheEntry<T>>();
  final Map<String, Future<T>> _inFlight = <String, Future<T>>{};
  final Map<String, int> _keyGenerations = <String, int>{};

  String? _activeSignature;
  int _generation = 0;

  bool isActive(String signature) => _activeSignature == signature;

  int get cachedPageCount => _entries.length;

  int get inFlightCount => _inFlight.length;

  T? peek({
    required String signature,
    required int pageNumber,
  }) {
    final key = _cacheKey(signature, pageNumber);
    final entry = _entries.remove(key);
    if (entry == null) return null;
    if (_now().difference(entry.storedAt) >= retainFor) {
      return null;
    }

    // Reinsert on access so the map remains least-recently-used ordered.
    _entries[key] = entry;
    return entry.value;
  }

  bool isFresh({
    required String signature,
    required int pageNumber,
  }) {
    final key = _cacheKey(signature, pageNumber);
    final entry = _entries[key];
    if (entry == null || entry.dirty) return false;
    return _now().difference(entry.storedAt) < maxAge;
  }

  Future<T> load({
    required String signature,
    required int pageNumber,
    required Future<T> Function() loader,
  }) {
    _activate(signature);

    final cached = peek(signature: signature, pageNumber: pageNumber);
    if (cached != null &&
        isFresh(signature: signature, pageNumber: pageNumber)) {
      return Future<T>.value(cached);
    }

    final key = _cacheKey(signature, pageNumber);
    final pending = _inFlight[key];
    if (pending != null) return pending;

    final generation = _generation;
    final keyGeneration = _keyGenerations[key] ?? 0;
    late final Future<T> future;
    future = loader().then((value) {
      if (_generation == generation &&
          (_keyGenerations[key] ?? 0) == keyGeneration &&
          _shouldCache(value)) {
        _entries.remove(key);
        _entries[key] = _CatalogPageCacheEntry<T>(
          value: value,
          storedAt: _now(),
        );
        while (_entries.length > maxEntries) {
          _entries.remove(_entries.keys.first);
        }
      }
      return value;
    }).whenComplete(() {
      if (identical(_inFlight[key], future)) {
        _inFlight.remove(key);
      }
    });
    _inFlight[key] = future;
    return future;
  }

  /// Forces matching values to revalidate while retaining them for paint.
  void markStale({String? signature}) {
    final keys = <String>{
      ..._entries.keys,
      ..._inFlight.keys,
    }
        .where(
          (key) => signature == null || _signatureFromKey(key) == signature,
        )
        .toList(growable: false);
    for (final key in keys) {
      final entry = _entries[key];
      if (entry != null) entry.dirty = true;
      _keyGenerations[key] = (_keyGenerations[key] ?? 0) + 1;
      _inFlight.remove(key);
    }
  }

  void clear() {
    _generation++;
    _activeSignature = null;
    _entries.clear();
    _inFlight.clear();
    _keyGenerations.clear();
  }

  static bool _alwaysCache<T>(T _) => true;

  void _activate(String signature) {
    _activeSignature = signature;
  }

  String _cacheKey(String signature, int pageNumber) =>
      '$signature\u0000$pageNumber';

  String _signatureFromKey(String key) {
    final separator = key.lastIndexOf('\u0000');
    return separator < 0 ? key : key.substring(0, separator);
  }
}

class _CatalogPageCacheEntry<T> {
  _CatalogPageCacheEntry({
    required this.value,
    required this.storedAt,
    this.dirty = false,
  });

  final T value;
  final DateTime storedAt;
  bool dirty;
}
