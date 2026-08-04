import 'website_block_definition.dart';
import 'website_block_registry.dart';
import 'website_block_type.dart';
import 'website_responsive_authoring.dart';

/// Projects one persisted Website Builder block into the values rendered by a
/// concrete storefront viewport.
///
/// Persistence remains untouched: the returned map is a deep copy. Desktop
/// reads the shared/base values; tablet and mobile read only their own explicit
/// override and otherwise inherit directly from shared. Repeater items own
/// their own `responsive` container and are projected recursively, so one
/// carousel slide can never leak an override into another.
abstract final class WebsiteResponsiveBlockProjection {
  static Map<String, dynamic> project({
    required WebsiteBlockType type,
    required Map<String, dynamic> data,
    required WebsiteViewport viewport,
    Set<String> displayCopyWhitelist = const <String>{},
  }) {
    return _projectFields(
      source: data,
      fields: WebsiteBlockRegistry.definitionFor(type).fields,
      viewport: viewport,
      displayCopyWhitelist: displayCopyWhitelist,
    );
  }

  static Map<String, dynamic> _projectFields({
    required Map<String, dynamic> source,
    required Iterable<WebsiteBlockFieldSchema> fields,
    required WebsiteViewport viewport,
    required Set<String> displayCopyWhitelist,
    String pathPrefix = '',
  }) {
    final projected = _deepCopyMap(source);

    for (final field in fields) {
      final fieldPath =
          pathPrefix.isEmpty ? field.key : '$pathPrefix.${field.key}';
      final value = _resolvedFieldValue(
        source: source,
        field: field,
        fieldPath: fieldPath,
        viewport: viewport,
        displayCopyWhitelist: displayCopyWhitelist,
      );

      if (value.exists) {
        projected[field.key] = _deepCopy(value.value);
        // A renderer that still reads a migration alias must see the same
        // projected value as the canonical key. Aliases absent from the source
        // are not invented.
        for (final alias in field.migrationAliases) {
          if (source.containsKey(alias)) {
            projected[alias] = _deepCopy(value.value);
          }
        }
      }

      if (field.type == WebsiteBlockFieldType.repeater) {
        final rawItems = projected[field.key];
        if (rawItems is List) {
          projected[field.key] = rawItems
              .map(
                (item) => item is Map
                    ? _projectFields(
                        source: item.map(
                          (key, nested) => MapEntry(key.toString(), nested),
                        ),
                        fields: field.itemFields,
                        viewport: viewport,
                        displayCopyWhitelist: displayCopyWhitelist,
                        pathPrefix: fieldPath,
                      )
                    : _deepCopy(item),
              )
              .toList(growable: false);
        }
      }

      if (field.supportsFocalPoint) {
        _projectSyntheticProperty(
          projected: projected,
          source: source,
          propertyKey: field.focalPointXKey,
          legacyMobileKey: field.mobileFocalPointXKey,
          viewport: viewport,
        );
        _projectSyntheticProperty(
          projected: projected,
          source: source,
          propertyKey: field.focalPointYKey,
          legacyMobileKey: field.mobileFocalPointYKey,
          viewport: viewport,
        );
      }
    }

    return projected;
  }

  static WebsiteResponsiveEntry<Object?> _resolvedFieldValue({
    required Map<String, dynamic> source,
    required WebsiteBlockFieldSchema field,
    required String fieldPath,
    required WebsiteViewport viewport,
    required Set<String> displayCopyWhitelist,
  }) {
    final resolutionSource = _deepCopyMap(source);
    var hasSharedValue = source.containsKey(field.key);
    if (!hasSharedValue) {
      for (final alias in field.migrationAliases) {
        if (source.containsKey(alias)) {
          resolutionSource[field.key] = _deepCopy(source[alias]);
          hasSharedValue = true;
          break;
        }
      }
    }

    final policy = field.responsivePolicy;
    final overrideAllowed = policy.supportsViewportOverride &&
        (policy != WebsiteResponsivePropertyPolicy.responsiveDisplayCopy ||
            displayCopyWhitelist.contains(fieldPath));
    final hasCanonicalOverride = overrideAllowed &&
        WebsiteResponsiveDataCodec.hasOverride(
          resolutionSource,
          field.key,
          viewport,
        );
    final hasLegacyOverride = overrideAllowed &&
        viewport == WebsiteViewport.mobile &&
        field.legacyResponsiveAliases.any(source.containsKey);

    if (!hasSharedValue && !hasCanonicalOverride && !hasLegacyOverride) {
      return const WebsiteResponsiveEntry<Object?>.absent();
    }

    if (!overrideAllowed || viewport == WebsiteViewport.desktop) {
      return WebsiteResponsiveEntry<Object?>.present(
        _deepCopy(resolutionSource[field.key]),
      );
    }

    final resolved = WebsiteResponsiveDataCodec.resolve<Object?>(
      data: resolutionSource,
      propertyKey: field.key,
      viewport: viewport,
      decode: _deepCopy,
      readLegacyOverride: field.legacyResponsiveAliases.isEmpty
          ? null
          : WebsiteLegacyResponsiveAdapters.mobileAliases<Object?>(
              field.legacyResponsiveAliases,
              _deepCopy,
            ),
    );
    return WebsiteResponsiveEntry<Object?>.present(resolved.value);
  }

  static void _projectSyntheticProperty({
    required Map<String, dynamic> projected,
    required Map<String, dynamic> source,
    required String propertyKey,
    required String legacyMobileKey,
    required WebsiteViewport viewport,
  }) {
    final hasShared = source.containsKey(propertyKey);
    final hasOverride = WebsiteResponsiveDataCodec.hasOverride(
      source,
      propertyKey,
      viewport,
    );
    final hasLegacy = viewport == WebsiteViewport.mobile &&
        source.containsKey(legacyMobileKey);
    if (!hasShared && !hasOverride && !hasLegacy) return;

    final resolved = WebsiteResponsiveDataCodec.resolve<Object?>(
      data: source,
      propertyKey: propertyKey,
      viewport: viewport,
      decode: _deepCopy,
      readLegacyOverride: WebsiteLegacyResponsiveAdapters.mobileAlias<Object?>(
        legacyMobileKey,
        _deepCopy,
      ),
    );
    projected[propertyKey] = _deepCopy(resolved.value);
  }
}

Map<String, dynamic> _deepCopyMap(Map<String, dynamic> source) =>
    source.map((key, value) => MapEntry(key, _deepCopy(value)));

Object? _deepCopy(Object? value) {
  if (value is Map) {
    return value.map(
      (key, nested) => MapEntry(key.toString(), _deepCopy(nested)),
    );
  }
  if (value is List) {
    return value.map(_deepCopy).toList(growable: false);
  }
  if (value is Set) return value.map(_deepCopy).toSet();
  return value;
}
