import 'dart:collection';

/// Small session cache for adjacent catalog pages.
///
/// The cache is intentionally bounded and short-lived because public stock
/// includes active reservations. A signature represents every query input
/// except the page number; changing it invalidates cached and in-flight pages.
class CatalogPagePrefetchCache<T> {
  CatalogPagePrefetchCache({
    this.maxAge = const Duration(seconds: 45),
    this.maxEntries = 6,
    bool Function(T value)? shouldCache,
    DateTime Function()? now,
  })  : assert(maxEntries > 0),
        _shouldCache = shouldCache ?? _alwaysCache,
        _now = now ?? DateTime.now;

  final Duration maxAge;
  final int maxEntries;
  final bool Function(T value) _shouldCache;
  final DateTime Function() _now;
  final LinkedHashMap<int, _CatalogPageCacheEntry<T>> _entries =
      LinkedHashMap<int, _CatalogPageCacheEntry<T>>();
  final Map<int, Future<T>> _inFlight = <int, Future<T>>{};

  String? _activeSignature;
  int _generation = 0;

  bool isActive(String signature) => _activeSignature == signature;

  int get cachedPageCount => _entries.length;

  int get inFlightCount => _inFlight.length;

  T? peek({
    required String signature,
    required int pageNumber,
  }) {
    if (_activeSignature != signature) return null;
    final entry = _entries.remove(pageNumber);
    if (entry == null) return null;
    if (_now().difference(entry.storedAt) >= maxAge) {
      return null;
    }

    // Reinsert on access so the map remains least-recently-used ordered.
    _entries[pageNumber] = entry;
    return entry.value;
  }

  Future<T> load({
    required String signature,
    required int pageNumber,
    required Future<T> Function() loader,
  }) {
    _activate(signature);

    final cached = peek(signature: signature, pageNumber: pageNumber);
    if (cached != null) return Future<T>.value(cached);

    final pending = _inFlight[pageNumber];
    if (pending != null) return pending;

    final generation = _generation;
    late final Future<T> future;
    future = loader().then((value) {
      if (_generation == generation &&
          _activeSignature == signature &&
          _shouldCache(value)) {
        _entries.remove(pageNumber);
        _entries[pageNumber] = _CatalogPageCacheEntry<T>(
          value: value,
          storedAt: _now(),
        );
        while (_entries.length > maxEntries) {
          _entries.remove(_entries.keys.first);
        }
      }
      return value;
    }).whenComplete(() {
      if (identical(_inFlight[pageNumber], future)) {
        _inFlight.remove(pageNumber);
      }
    });
    _inFlight[pageNumber] = future;
    return future;
  }

  void clear() {
    _generation++;
    _activeSignature = null;
    _entries.clear();
    _inFlight.clear();
  }

  static bool _alwaysCache<T>(T _) => true;

  void _activate(String signature) {
    if (_activeSignature == signature) return;
    _generation++;
    _activeSignature = signature;
    _entries.clear();
    _inFlight.clear();
  }
}

class _CatalogPageCacheEntry<T> {
  const _CatalogPageCacheEntry({
    required this.value,
    required this.storedAt,
  });

  final T value;
  final DateTime storedAt;
}
