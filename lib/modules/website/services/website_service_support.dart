part of 'website_service.dart';

@visibleForTesting
bool isPublicWebsiteSettingCacheSafe(String key) {
  return !_sensitivePublicWebsiteSettingKey.hasMatch(key.trim());
}

@visibleForTesting
Map<String, dynamic> filterPublicWebsiteSettingsForCache(
  Map<String, dynamic> settings,
) {
  return <String, dynamic>{
    for (final entry in settings.entries)
      if (isPublicWebsiteSettingCacheSafe(entry.key)) entry.key: entry.value,
  };
}

typedef WebsitePreloadedStoreDataLoader = Future<Map<String, dynamic>?>
    Function(
  String expectedTenantId,
);

String _publicStoreCacheKey(String kind, String tenantId) =>
    '${_publicStoreCacheNamespace}_${kind}_$tenantId';

@immutable
class _WebsiteTenantScopeLease {
  const _WebsiteTenantScopeLease({
    required this.tenantId,
    required this.generation,
  });

  final String tenantId;
  final int generation;
}

class _WebsiteScopedLoad<T> {
  const _WebsiteScopedLoad({
    required this.lease,
    required this.future,
  });

  final _WebsiteTenantScopeLease lease;
  final Future<T> future;
}

class _LooseAddressParts {
  final String street;
  final String city;
  final String country;

  const _LooseAddressParts({
    required this.street,
    required this.city,
    required this.country,
  });
}
