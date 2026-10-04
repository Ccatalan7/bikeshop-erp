/// Transitional aliases for the global website SEO settings.
///
/// `seo_*` is the canonical family consumed by the public store and build
/// tooling. The unprefixed keys remain mirrored while older deployments and
/// saved records still exist, but they must never become an independent
/// writer.
abstract final class WebsiteSeoSettingsAliases {
  static const Map<String, String> canonicalToLegacy = {
    'seo_meta_title': 'meta_title',
    'seo_meta_description': 'meta_description',
    'seo_meta_keywords': 'meta_keywords',
  };

  /// Returns the canonical HTTPS origin accepted by every SEO consumer.
  ///
  /// `store_url` owns an origin, not an arbitrary page URL. Rejecting
  /// credentials, paths, queries and fragments here prevents the editor,
  /// runtime canonical tags and Google integrations from interpreting the
  /// same saved value differently.
  static String normalizeHttpsOrigin(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      return '';
    }
    return uri.replace(path: '', query: null, fragment: null).toString();
  }

  /// Mirrors only aliases explicitly changed by [updates].
  ///
  /// This preserves the user's intent, including clearing a value. A legacy
  /// update is promoted to the canonical key, while a simultaneous canonical
  /// update wins deterministically.
  static Map<String, String> normalize(
    Map<String, dynamic> updates,
  ) {
    final normalized = <String, String>{
      for (final entry in updates.entries)
        entry.key: entry.value?.toString() ?? '',
    };

    for (final entry in canonicalToLegacy.entries) {
      final canonical = entry.key;
      final legacy = entry.value;
      if (!normalized.containsKey(canonical) &&
          !normalized.containsKey(legacy)) {
        continue;
      }

      final value = normalized.containsKey(canonical)
          ? normalized[canonical]!
          : normalized[legacy]!;
      normalized[canonical] = value;
      normalized[legacy] = value;
    }

    // `store_url` is the unique base-domain owner. Keep the historical
    // canonical setting synchronized only as a compatibility projection.
    if (normalized.containsKey('store_url') ||
        normalized.containsKey('seo_canonical_url')) {
      final rawValue = normalized.containsKey('store_url')
          ? normalized['store_url']!
          : normalized['seo_canonical_url']!;
      final normalizedOrigin = normalizeHttpsOrigin(rawValue);
      final value =
          normalizedOrigin.isEmpty ? rawValue.trim() : normalizedOrigin;
      normalized['store_url'] = value;
      normalized['seo_canonical_url'] = value;
    }

    return normalized;
  }
}
