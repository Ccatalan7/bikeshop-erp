part of 'website_service.dart';

/// Public snapshot of cached page data (safe to expose).
class CachedPageSnapshot {
  final WebsitePage page;
  final List<Map<String, dynamic>> blocks;
  final String fingerprint;

  CachedPageSnapshot({
    required this.page,
    required this.blocks,
  }) : fingerprint = jsonEncode(<Object?>[
          page.toJson(),
          blocks,
        ]);
}

enum PageSnapshotLoadProvenance {
  origin,
  originMissing,
  staleFallback,
}

/// Signals that an editor save or explicit cache clear superseded an
/// in-flight request before it could establish origin truth.
class PageSnapshotInvalidatedException implements Exception {
  const PageSnapshotInvalidatedException();
}

class PageSnapshotLoadResult {
  const PageSnapshotLoadResult._({
    required this.provenance,
    required this.snapshot,
  });

  const PageSnapshotLoadResult.originMissing()
      : this._(
          provenance: PageSnapshotLoadProvenance.originMissing,
          snapshot: null,
        );

  factory PageSnapshotLoadResult.origin(CachedPageSnapshot snapshot) =>
      PageSnapshotLoadResult._(
        provenance: PageSnapshotLoadProvenance.origin,
        snapshot: snapshot,
      );

  factory PageSnapshotLoadResult.staleFallback(
    CachedPageSnapshot? snapshot,
  ) =>
      PageSnapshotLoadResult._(
        provenance: PageSnapshotLoadProvenance.staleFallback,
        snapshot: snapshot,
      );

  final PageSnapshotLoadProvenance provenance;
  final CachedPageSnapshot? snapshot;

  bool get isOriginConfirmed => provenance == PageSnapshotLoadProvenance.origin;
  bool get isAuthoritativelyMissing =>
      provenance == PageSnapshotLoadProvenance.originMissing;
  bool get isStaleFallback =>
      provenance == PageSnapshotLoadProvenance.staleFallback;
}

/// Tenant/slug page snapshot cache used by public CMS routes.
///
/// It owns bounded LRU retention, concurrent request de-duplication, and
/// generation isolation so an invalidated in-flight response cannot restore
/// stale content after an editor save.
@visibleForTesting
class WebsitePageSnapshotCache {
  final Duration ttl;
  final Duration retainFor;
  final int capacity;

  final LinkedHashMap<String, _CachedPage> _entries =
      LinkedHashMap<String, _CachedPage>();
  final Map<String, Future<CachedPageSnapshot?>> _inFlight =
      <String, Future<CachedPageSnapshot?>>{};
  final Map<String, int> _keyGenerations = <String, int>{};
  int _generation = 0;

  WebsitePageSnapshotCache({
    this.ttl = const Duration(minutes: 5),
    Duration? retainFor,
    this.capacity = 96,
  })  : assert(capacity > 0),
        assert((retainFor ?? ttl) >= ttl),
        retainFor = retainFor ?? ttl;

  @visibleForTesting
  int get length => _entries.length;

  CachedPageSnapshot? peek(String key) {
    final cached = _entries.remove(key);
    if (cached == null) return null;
    if (cached.isExpired(retainFor)) return null;

    // Reinsert to mark this key as the most recently used.
    _entries[key] = cached;
    return _copySnapshot(cached.snapshot);
  }

  bool isFresh(String key) {
    final cached = _entries[key];
    return cached != null && !cached.isExpired(ttl);
  }

  Future<CachedPageSnapshot?> revalidate(
    String key,
    Future<CachedPageSnapshot?> Function() loader,
  ) {
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final generation = _generation;
    final keyGeneration = _keyGenerations[key] ?? 0;
    final completer = Completer<CachedPageSnapshot?>();
    final future = completer.future;
    _inFlight[key] = future;

    unawaited(() async {
      try {
        final loaded = await loader();
        final isCurrent = generation == _generation &&
            keyGeneration == (_keyGenerations[key] ?? 0);
        if (!isCurrent) {
          final replacement = peek(key);
          if (replacement != null) {
            completer.complete(replacement);
          } else {
            completer.completeError(
              const PageSnapshotInvalidatedException(),
            );
          }
          return;
        }

        if (loaded == null) {
          _entries.remove(key);
          completer.complete(null);
          return;
        }

        _put(key, loaded);
        completer.complete(peek(key));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        if (identical(_inFlight[key], future)) {
          _inFlight.remove(key);
        }
      }
    }());

    return future;
  }

  void invalidateKey(String key) {
    _entries.remove(key);
    _inFlight.remove(key);
    _keyGenerations[key] = (_keyGenerations[key] ?? 0) + 1;
  }

  void invalidateWhere(bool Function(String key) predicate) {
    final keys = <String>{..._entries.keys, ..._inFlight.keys};
    for (final key in keys) {
      if (predicate(key)) invalidateKey(key);
    }
  }

  void clear() {
    _generation += 1;
    _entries.clear();
    _inFlight.clear();
    _keyGenerations.clear();
  }

  void _put(String key, CachedPageSnapshot snapshot) {
    final previous = _entries.remove(key);
    final retainedSnapshot =
        previous?.snapshot.fingerprint == snapshot.fingerprint
            ? previous!.snapshot
            : _copySnapshot(snapshot);
    _entries[key] = _CachedPage(
      snapshot: retainedSnapshot,
      cachedAt: DateTime.now(),
    );
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  CachedPageSnapshot _copySnapshot(CachedPageSnapshot snapshot) {
    return CachedPageSnapshot(
      page: snapshot.page,
      blocks: <Map<String, dynamic>>[
        for (final block in snapshot.blocks) _copyBlock(block),
      ],
    );
  }

  Map<String, dynamic> _copyBlock(Map<String, dynamic> block) {
    return Map<String, dynamic>.from(
      _deepCopyJson(block) as Map,
    );
  }

  Object? _deepCopyJson(Object? value) {
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key.toString(): _deepCopyJson(entry.value),
      };
    }
    if (value is List) {
      return <Object?>[
        for (final item in value) _deepCopyJson(item),
      ];
    }
    return value;
  }
}

class _CachedPage {
  final CachedPageSnapshot snapshot;
  final DateTime cachedAt;

  _CachedPage({
    required this.snapshot,
    required this.cachedAt,
  });

  bool isExpired(Duration ttl) => DateTime.now().difference(cachedAt) > ttl;
}
