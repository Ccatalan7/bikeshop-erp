import 'dart:collection';

/// Bounded, tenant-scoped snapshots used only to seed a product detail route.
///
/// A detail page always revalidates against the origin. These snapshots avoid
/// replacing a product card the visitor just clicked with a blank loading
/// screen while that revalidation is in flight.
class PublicProductSnapshotCache<T> {
  PublicProductSnapshotCache({
    this.maxAge = const Duration(minutes: 10),
    this.maxEntries = 160,
    DateTime Function()? now,
  })  : assert(maxEntries > 0),
        _now = now ?? DateTime.now;

  final Duration maxAge;
  final int maxEntries;
  final DateTime Function() _now;
  final LinkedHashMap<String, _PublicProductSnapshot<T>> _entries =
      LinkedHashMap<String, _PublicProductSnapshot<T>>();
  final Map<String, String> _skuAliases = <String, String>{};

  int get length => _entries.length;

  void put({
    required String tenantId,
    required String id,
    required String? sku,
    required T value,
    bool originValidated = false,
  }) {
    final normalizedTenant = tenantId.trim();
    final normalizedId = id.trim();
    if (normalizedTenant.isEmpty || normalizedId.isEmpty) return;

    final primaryKey = _idKey(normalizedTenant, normalizedId);
    final validatedAt = originValidated ? _now() : null;
    _removePrimary(primaryKey);
    final skuKey = _normalizedSkuKey(normalizedTenant, sku);
    final aliases = <String>{
      if (skuKey != null) skuKey,
    };
    _entries[primaryKey] = _PublicProductSnapshot<T>(
      tenantId: normalizedTenant,
      value: value,
      storedAt: _now(),
      originValidatedAt: validatedAt,
      aliases: aliases,
    );
    for (final alias in aliases) {
      _skuAliases[alias] = primaryKey;
    }

    while (_entries.length > maxEntries) {
      _removePrimary(_entries.keys.first);
    }
  }

  T? peekById({
    required String tenantId,
    required String id,
  }) {
    final normalizedTenant = tenantId.trim();
    final normalizedId = id.trim();
    if (normalizedTenant.isEmpty || normalizedId.isEmpty) return null;
    return _readPrimary(_idKey(normalizedTenant, normalizedId))?.value;
  }

  T? peekBySku({
    required String tenantId,
    required String sku,
  }) {
    final alias = _normalizedSkuKey(tenantId.trim(), sku);
    if (alias == null) return null;
    final primaryKey = _skuAliases[alias];
    if (primaryKey == null) return null;
    return _readPrimary(primaryKey)?.value;
  }

  PublicProductSnapshotValue<T>? peekSnapshotById({
    required String tenantId,
    required String id,
  }) {
    final normalizedTenant = tenantId.trim();
    final normalizedId = id.trim();
    if (normalizedTenant.isEmpty || normalizedId.isEmpty) return null;
    return _readPrimary(_idKey(normalizedTenant, normalizedId));
  }

  PublicProductSnapshotValue<T>? peekSnapshotBySku({
    required String tenantId,
    required String sku,
  }) {
    final alias = _normalizedSkuKey(tenantId.trim(), sku);
    if (alias == null) return null;
    final primaryKey = _skuAliases[alias];
    if (primaryKey == null) return null;
    return _readPrimary(primaryKey);
  }

  void clear({String? tenantId}) {
    final normalizedTenant = tenantId?.trim();
    if (normalizedTenant == null || normalizedTenant.isEmpty) {
      _entries.clear();
      _skuAliases.clear();
      return;
    }

    final keys = _entries.entries
        .where((entry) => entry.value.tenantId == normalizedTenant)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final key in keys) {
      _removePrimary(key);
    }
  }

  /// Revokes short-lived authority without removing useful paint snapshots.
  void markOriginStale({String? tenantId}) {
    final normalizedTenant = tenantId?.trim();
    for (final entry in _entries.values) {
      if (normalizedTenant == null ||
          normalizedTenant.isEmpty ||
          entry.tenantId == normalizedTenant) {
        entry.originValidatedAt = null;
      }
    }
  }

  PublicProductSnapshotValue<T>? _readPrimary(String primaryKey) {
    final entry = _entries.remove(primaryKey);
    if (entry == null) return null;
    if (_now().difference(entry.storedAt) >= maxAge) {
      for (final alias in entry.aliases) {
        if (_skuAliases[alias] == primaryKey) {
          _skuAliases.remove(alias);
        }
      }
      return null;
    }

    _entries[primaryKey] = entry;
    return PublicProductSnapshotValue<T>(
      value: entry.value,
      storedAt: entry.storedAt,
      originValidatedAt: entry.originValidatedAt,
    );
  }

  void _removePrimary(String primaryKey) {
    final entry = _entries.remove(primaryKey);
    if (entry == null) return;
    for (final alias in entry.aliases) {
      if (_skuAliases[alias] == primaryKey) {
        _skuAliases.remove(alias);
      }
    }
  }

  String _idKey(String tenantId, String id) => '$tenantId\u0000id\u0000$id';

  String? _normalizedSkuKey(String tenantId, String? sku) {
    final normalizedSku = sku?.trim().toUpperCase() ?? '';
    if (tenantId.isEmpty || normalizedSku.isEmpty) return null;
    return '$tenantId\u0000sku\u0000$normalizedSku';
  }
}

class _PublicProductSnapshot<T> {
  _PublicProductSnapshot({
    required this.tenantId,
    required this.value,
    required this.storedAt,
    required this.originValidatedAt,
    required this.aliases,
  });

  final String tenantId;
  final T value;
  final DateTime storedAt;
  DateTime? originValidatedAt;
  final Set<String> aliases;
}

class PublicProductSnapshotValue<T> {
  const PublicProductSnapshotValue({
    required this.value,
    required this.storedAt,
    required this.originValidatedAt,
  });

  final T value;
  final DateTime storedAt;
  final DateTime? originValidatedAt;

  bool isOriginFresh(
    Duration freshness, {
    DateTime Function()? now,
  }) {
    final validatedAt = originValidatedAt;
    if (validatedAt == null) return false;
    final age = (now ?? DateTime.now)().difference(validatedAt);
    return age >= Duration.zero && age < freshness;
  }
}
