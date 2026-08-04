import '../../../shared/utils/responsive_breakpoints.dart';

/// Semantic storefront viewport used by authoring, preview and public render.
///
/// The classification is based on the logical width of the storefront canvas,
/// never on the host window that happens to contain it.
enum WebsiteViewport {
  desktop,
  tablet,
  mobile;

  static WebsiteViewport fromLogicalWidth(double width) {
    if (width < ResponsiveBreakpoints.phoneMaxExclusive) {
      return WebsiteViewport.mobile;
    }
    if (width < ResponsiveBreakpoints.desktopMin) {
      return WebsiteViewport.tablet;
    }
    return WebsiteViewport.desktop;
  }

  String get wireName => name;

  bool get supportsOverride => this != WebsiteViewport.desktop;
}

/// The device class that owns the editing chrome.
enum WebsiteAuthoringHostClass { desktop, phone }

/// Where the next field mutation is attributed.
enum WebsiteWriteScope { shared, viewport }

/// Persistence and authoring policy for one schema property.
enum WebsiteResponsivePropertyPolicy {
  sharedOnly,
  responsiveOptional,
  responsiveVisibility,
  perViewportGeometry,
  responsiveDisplayCopy;

  bool get supportsViewportOverride => this != sharedOnly;
}

enum WebsiteResponsivePropertyFamily {
  content,
  media,
  typography,
  geometry,
  visibility,
  action,
  spacing,
  color,
  collection,
}

enum WebsiteAuthoringSurface { inline, contextSheet, inspector }

/// The three independent axes of a Website Builder authoring session.
class WebsiteAuthoringContext {
  const WebsiteAuthoringContext({
    required this.hostClass,
    required this.previewViewport,
    required this.writeScope,
  });

  final WebsiteAuthoringHostClass hostClass;
  final WebsiteViewport previewViewport;
  final WebsiteWriteScope writeScope;

  /// Desktop is the shared/base value and never owns a separate override.
  /// Shared-only fields likewise ignore a viewport-scoped default.
  WebsiteWriteScope effectiveWriteScope(
    WebsiteResponsivePropertyPolicy policy,
  ) {
    if (!policy.supportsViewportOverride ||
        previewViewport == WebsiteViewport.desktop) {
      return WebsiteWriteScope.shared;
    }
    return writeScope;
  }

  WebsiteAuthoringContext copyWith({
    WebsiteAuthoringHostClass? hostClass,
    WebsiteViewport? previewViewport,
    WebsiteWriteScope? writeScope,
  }) {
    final nextViewport = previewViewport ?? this.previewViewport;
    final nextScope = nextViewport == WebsiteViewport.desktop
        ? WebsiteWriteScope.shared
        : writeScope ?? this.writeScope;
    return WebsiteAuthoringContext(
      hostClass: hostClass ?? this.hostClass,
      previewViewport: nextViewport,
      writeScope: nextScope,
    );
  }
}

/// Distinguishes an absent override from an authored nullable override.
class WebsiteResponsiveEntry<T> {
  const WebsiteResponsiveEntry.absent()
      : exists = false,
        value = null;

  const WebsiteResponsiveEntry.present(this.value) : exists = true;

  final bool exists;
  final T? value;
}

/// Typed result returned to renderers and controls.
class WebsiteResolvedResponsiveValue<T> {
  const WebsiteResolvedResponsiveValue({
    required this.shared,
    required this.value,
    required this.viewport,
    required this.isOverride,
    required this.isLegacyOverride,
  });

  final T? shared;
  final T? value;
  final WebsiteViewport viewport;
  final bool isOverride;
  final bool isLegacyOverride;

  bool get isInherited => viewport != WebsiteViewport.desktop && !isOverride;
}

typedef WebsiteResponsiveDecoder<T> = T? Function(Object? raw);
typedef WebsiteLegacyResponsiveReader<T> = WebsiteResponsiveEntry<T> Function(
  Map<String, dynamic> data,
  String propertyKey,
  WebsiteViewport viewport,
);

/// Canonical codec for responsive values stored inside a block/slide/item.
///
/// Desktop is always the top-level shared value. Tablet and mobile overrides
/// live under `responsive`; they inherit directly from shared and never from
/// each other.
abstract final class WebsiteResponsiveDataCodec {
  static const String containerKey = 'responsive';
  static const String versionKey = 'version';
  static const int schemaVersion = 2;

  static WebsiteResolvedResponsiveValue<T> resolve<T>({
    required Map<String, dynamic> data,
    required String propertyKey,
    required WebsiteViewport viewport,
    required WebsiteResponsiveDecoder<T> decode,
    T? fallback,
    WebsiteLegacyResponsiveReader<T>? readLegacyOverride,
  }) {
    final shared =
        data.containsKey(propertyKey) ? decode(data[propertyKey]) : fallback;

    if (viewport == WebsiteViewport.desktop) {
      return WebsiteResolvedResponsiveValue<T>(
        shared: shared,
        value: shared,
        viewport: viewport,
        isOverride: false,
        isLegacyOverride: false,
      );
    }

    final override = overrideEntry<T>(
      data: data,
      propertyKey: propertyKey,
      viewport: viewport,
      decode: decode,
    );
    if (override.exists) {
      return WebsiteResolvedResponsiveValue<T>(
        shared: shared,
        value: override.value,
        viewport: viewport,
        isOverride: true,
        isLegacyOverride: false,
      );
    }

    final legacy = readLegacyOverride?.call(data, propertyKey, viewport) ??
        WebsiteResponsiveEntry<T>.absent();
    if (legacy.exists) {
      return WebsiteResolvedResponsiveValue<T>(
        shared: shared,
        value: legacy.value,
        viewport: viewport,
        isOverride: true,
        isLegacyOverride: true,
      );
    }

    return WebsiteResolvedResponsiveValue<T>(
      shared: shared,
      value: shared,
      viewport: viewport,
      isOverride: false,
      isLegacyOverride: false,
    );
  }

  static WebsiteResponsiveEntry<T> overrideEntry<T>({
    required Map<String, dynamic> data,
    required String propertyKey,
    required WebsiteViewport viewport,
    required WebsiteResponsiveDecoder<T> decode,
  }) {
    if (!viewport.supportsOverride) {
      return WebsiteResponsiveEntry<T>.absent();
    }
    final container = _stringKeyedMap(data[containerKey]);
    final values = _stringKeyedMap(container?[viewport.wireName]);
    if (values == null || !values.containsKey(propertyKey)) {
      return WebsiteResponsiveEntry<T>.absent();
    }
    return WebsiteResponsiveEntry<T>.present(decode(values[propertyKey]));
  }

  static bool hasOverride(
    Map<String, dynamic> data,
    String propertyKey,
    WebsiteViewport viewport,
  ) {
    if (!viewport.supportsOverride) return false;
    final container = _stringKeyedMap(data[containerKey]);
    final values = _stringKeyedMap(container?[viewport.wireName]);
    return values?.containsKey(propertyKey) ?? false;
  }

  static Map<String, dynamic> setShared({
    required Map<String, dynamic> data,
    required String propertyKey,
    required Object? value,
    Map<String, WebsiteResponsivePropertyPolicy> policies = const {},
    Set<String> displayCopyWhitelist = const {},
  }) {
    final next = _deepCopyMap(data)..[propertyKey] = _deepCopy(value);
    return normalize(
      next,
      policies: policies,
      displayCopyWhitelist: displayCopyWhitelist,
    );
  }

  static Map<String, dynamic> setForViewport({
    required Map<String, dynamic> data,
    required String propertyKey,
    required Object? value,
    required WebsiteViewport viewport,
    required WebsiteResponsivePropertyPolicy policy,
    Set<String> displayCopyWhitelist = const {},
  }) {
    if (!policy.supportsViewportOverride ||
        viewport == WebsiteViewport.desktop) {
      return setShared(
        data: data,
        propertyKey: propertyKey,
        value: value,
        policies: {propertyKey: policy},
        displayCopyWhitelist: displayCopyWhitelist,
      );
    }
    _assertDisplayCopyAllowed(
      propertyKey,
      policy,
      displayCopyWhitelist,
    );

    final next = _deepCopyMap(data);
    final container =
        _stringKeyedMap(next[containerKey]) ?? <String, dynamic>{};
    final values =
        _stringKeyedMap(container[viewport.wireName]) ?? <String, dynamic>{};
    values[propertyKey] = _deepCopy(value);
    container[versionKey] = schemaVersion;
    container[viewport.wireName] = values;
    next[containerKey] = container;
    return normalize(
      next,
      policies: {propertyKey: policy},
      displayCopyWhitelist: displayCopyWhitelist,
    );
  }

  static Map<String, dynamic> clearOverride({
    required Map<String, dynamic> data,
    required String propertyKey,
    required WebsiteViewport viewport,
    Map<String, WebsiteResponsivePropertyPolicy> policies = const {},
    Set<String> displayCopyWhitelist = const {},
  }) {
    if (!viewport.supportsOverride) return _deepCopyMap(data);
    final next = _deepCopyMap(data);
    final container = _stringKeyedMap(next[containerKey]);
    final values = _stringKeyedMap(container?[viewport.wireName]);
    if (container == null || values == null) return next;
    values.remove(propertyKey);
    if (values.isEmpty) {
      container.remove(viewport.wireName);
    } else {
      container[viewport.wireName] = values;
    }
    next[containerKey] = container;
    return normalize(
      next,
      policies: policies,
      displayCopyWhitelist: displayCopyWhitelist,
    );
  }

  /// Produces the only accepted persisted shape.
  ///
  /// Unknown branches, desktop override maps, empty maps, disallowed policy
  /// entries and values equal to shared are removed. Business data outside
  /// the owned `responsive` container is preserved byte-for-byte by value.
  static Map<String, dynamic> normalize(
    Map<String, dynamic> data, {
    Map<String, WebsiteResponsivePropertyPolicy> policies = const {},
    Set<String> displayCopyWhitelist = const {},
    Set<String> transientPropertyKeys = const {},
  }) {
    final next = _deepCopyMap(data);
    final rawContainer = _stringKeyedMap(next[containerKey]);
    if (rawContainer == null) {
      next.remove(containerKey);
      return next;
    }

    final normalized = <String, dynamic>{versionKey: schemaVersion};
    for (final viewport in const [
      WebsiteViewport.tablet,
      WebsiteViewport.mobile,
    ]) {
      final rawValues = _stringKeyedMap(rawContainer[viewport.wireName]);
      if (rawValues == null) continue;
      final values = <String, dynamic>{};
      for (final entry in rawValues.entries) {
        final key = entry.key;
        if (transientPropertyKeys.contains(key)) continue;
        final policy = policies[key];
        if (policy == WebsiteResponsivePropertyPolicy.sharedOnly) continue;
        if (policy == WebsiteResponsivePropertyPolicy.responsiveDisplayCopy &&
            !displayCopyWhitelist.contains(key)) {
          continue;
        }
        if (next.containsKey(key) &&
            websiteResponsiveDeepEquals(next[key], entry.value)) {
          continue;
        }
        values[key] = _deepCopy(entry.value);
      }
      if (values.isNotEmpty) normalized[viewport.wireName] = values;
    }

    if (normalized.length == 1) {
      next.remove(containerKey);
    } else {
      next[containerKey] = normalized;
    }
    return next;
  }

  /// Canonical documents use 600/900. Documents without a canonical
  /// responsive container retain the old 640/1024 visibility bands until an
  /// explicit migration writes version 2.
  static bool usesCanonicalSchema(Map<String, dynamic> data) {
    return _containsCanonicalSchema(data);
  }

  static WebsiteViewport viewportForDocumentWidth(
    Map<String, dynamic> data,
    double width,
  ) {
    if (usesCanonicalSchema(data)) {
      return WebsiteViewport.fromLogicalWidth(width);
    }
    if (width < 640) return WebsiteViewport.mobile;
    if (width < 1024) return WebsiteViewport.tablet;
    return WebsiteViewport.desktop;
  }

  static void _assertDisplayCopyAllowed(
    String propertyKey,
    WebsiteResponsivePropertyPolicy policy,
    Set<String> displayCopyWhitelist,
  ) {
    if (policy == WebsiteResponsivePropertyPolicy.responsiveDisplayCopy &&
        !displayCopyWhitelist.contains(propertyKey)) {
      throw StateError(
        'Responsive display copy is not approved for "$propertyKey".',
      );
    }
  }

  static bool _containsCanonicalSchema(Object? value) {
    if (value is Map) {
      final map = value.map(
        (key, nested) => MapEntry(key.toString(), nested),
      );
      final container = map[containerKey];
      if (container is Map) {
        final version = container[versionKey] ?? container['version'];
        if (version is num && version.toInt() >= schemaVersion) return true;
      }
      for (final entry in map.entries) {
        if (entry.key == containerKey) continue;
        if (_containsCanonicalSchema(entry.value)) return true;
      }
      return false;
    }
    if (value is Iterable) {
      for (final item in value) {
        if (_containsCanonicalSchema(item)) return true;
      }
    }
    return false;
  }
}

/// Small, explicit bridge for the currently persisted flat aliases.
abstract final class WebsiteLegacyResponsiveAdapters {
  static WebsiteLegacyResponsiveReader<T> mobileAlias<T>(
    String alias,
    WebsiteResponsiveDecoder<T> decode,
  ) {
    return (data, _, viewport) {
      if (viewport != WebsiteViewport.mobile || !data.containsKey(alias)) {
        return WebsiteResponsiveEntry<T>.absent();
      }
      return WebsiteResponsiveEntry<T>.present(decode(data[alias]));
    };
  }

  static WebsiteLegacyResponsiveReader<T> mobileAliases<T>(
    Iterable<String> aliases,
    WebsiteResponsiveDecoder<T> decode,
  ) {
    final ordered = List<String>.unmodifiable(aliases);
    return (data, _, viewport) {
      if (viewport != WebsiteViewport.mobile) {
        return WebsiteResponsiveEntry<T>.absent();
      }
      for (final alias in ordered) {
        if (data.containsKey(alias)) {
          return WebsiteResponsiveEntry<T>.present(decode(data[alias]));
        }
      }
      return WebsiteResponsiveEntry<T>.absent();
    };
  }

  static bool canvasLayerVisible(
    Map<String, dynamic> layer,
    WebsiteViewport viewport,
  ) {
    if (viewport != WebsiteViewport.mobile) {
      return layer['showOnMobile'] != true;
    }
    if (layer['hideOnMobile'] == true) return false;
    if (layer['showOnMobile'] == true) return true;
    return true;
  }
}

bool websiteResponsiveDeepEquals(Object? left, Object? right) {
  if (identical(left, right)) return true;
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !websiteResponsiveDeepEquals(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!websiteResponsiveDeepEquals(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }
  if (left is Set && right is Set) {
    return left.length == right.length && left.containsAll(right);
  }
  return left == right;
}

Map<String, dynamic>? _stringKeyedMap(Object? value) {
  if (value is! Map) return null;
  return value.map(
    (key, nested) => MapEntry(key.toString(), _deepCopy(nested)),
  );
}

Map<String, dynamic> _deepCopyMap(Map<String, dynamic> source) =>
    source.map((key, value) => MapEntry(key, _deepCopy(value)));

Object? _deepCopy(Object? value) {
  if (value is Map) {
    return value.map(
      (key, nested) => MapEntry(key.toString(), _deepCopy(nested)),
    );
  }
  if (value is List) return value.map(_deepCopy).toList(growable: false);
  if (value is Set) return value.map(_deepCopy).toSet();
  return value;
}
