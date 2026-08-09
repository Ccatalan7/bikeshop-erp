import 'website_block_definition.dart';
import 'website_block_registry.dart';
import 'website_block_type.dart';
import 'website_responsive_authoring.dart';

/// The single compatibility boundary for legacy cover focal-point data.
///
/// New documents persist `focalPointX/Y` plus canonical responsive overrides.
/// Existing documents may still contain a numeric mobile alias or the older
/// alignment preset. Renderers and inspectors must consume this same adapter so
/// they cannot disagree about the frame the author is editing.
enum WebsiteFocalAxis { horizontal, vertical }

abstract final class WebsiteResponsiveFocalProjection {
  static const String _legacyAlignmentKey = 'mobileBgAlignment';

  /// Canonical precedence after the responsive codec has checked an authored
  /// override: numeric mobile alias, then legacy preset, then shared value.
  static WebsiteLegacyResponsiveReader<double> legacyReader({
    required WebsiteBlockFieldSchema field,
    required WebsiteFocalAxis axis,
  }) {
    final legacyAxisKey = switch (axis) {
      WebsiteFocalAxis.horizontal => field.mobileFocalPointXKey,
      WebsiteFocalAxis.vertical => field.mobileFocalPointYKey,
    };
    return (data, _, viewport) {
      if (viewport != WebsiteViewport.mobile) {
        return const WebsiteResponsiveEntry<double>.absent();
      }
      final numeric = _decodeAxis(data[legacyAxisKey]);
      if (numeric != null) {
        return WebsiteResponsiveEntry<double>.present(numeric);
      }
      final preset = _legacyMobileFocalCoordinate(
        data[_legacyAlignmentKey],
        axis,
      );
      return preset == null
          ? const WebsiteResponsiveEntry<double>.absent()
          : WebsiteResponsiveEntry<double>.present(preset);
    };
  }

  /// Every legacy key whose authority is retired when the user resets the
  /// focal override. The preset affects both axes, so either atomic axis group
  /// must remove it together with the numeric aliases.
  static List<String> legacyPropertyKeys({
    required WebsiteBlockFieldSchema field,
    required WebsiteFocalAxis axis,
  }) =>
      <String>[
        switch (axis) {
          WebsiteFocalAxis.horizontal => field.mobileFocalPointXKey,
          WebsiteFocalAxis.vertical => field.mobileFocalPointYKey,
        },
        _legacyAlignmentKey,
      ];

  static double? _decodeAxis(Object? raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw.trim());
    return null;
  }
}

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
    final withMeta = projectMeta(
      data: data,
      viewport: viewport,
      displayCopyWhitelist: displayCopyWhitelist,
    );
    return _projectFields(
      source: withMeta,
      fields: WebsiteBlockRegistry.definitionFor(type).fields,
      viewport: viewport,
      displayCopyWhitelist: displayCopyWhitelist,
    );
  }

  /// Resolves the page-composition fields shared by every block family.
  static Map<String, dynamic> projectMeta({
    required Map<String, dynamic> data,
    required WebsiteViewport viewport,
    Set<String> displayCopyWhitelist = const <String>{},
  }) {
    return _projectFields(
      source: data,
      fields: WebsiteBlockMetaFields.fields,
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
          field: field,
          axis: WebsiteFocalAxis.horizontal,
          viewport: viewport,
        );
        _projectSyntheticProperty(
          projected: projected,
          source: source,
          field: field,
          axis: WebsiteFocalAxis.vertical,
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
    required WebsiteBlockFieldSchema field,
    required WebsiteFocalAxis axis,
    required WebsiteViewport viewport,
  }) {
    final propertyKey = switch (axis) {
      WebsiteFocalAxis.horizontal => field.focalPointXKey,
      WebsiteFocalAxis.vertical => field.focalPointYKey,
    };
    final legacyKeys = WebsiteResponsiveFocalProjection.legacyPropertyKeys(
      field: field,
      axis: axis,
    );
    final hasShared = source.containsKey(propertyKey);
    final hasOverride = WebsiteResponsiveDataCodec.hasOverride(
      source,
      propertyKey,
      viewport,
    );
    final hasLegacy = viewport == WebsiteViewport.mobile &&
        legacyKeys.any(source.containsKey);
    if (!hasShared && !hasOverride && !hasLegacy) {
      return;
    }

    final resolved = WebsiteResponsiveDataCodec.resolve<double>(
      data: source,
      propertyKey: propertyKey,
      viewport: viewport,
      decode: WebsiteResponsiveFocalProjection._decodeAxis,
      readLegacyOverride: WebsiteResponsiveFocalProjection.legacyReader(
        field: field,
        axis: axis,
      ),
    );
    projected[propertyKey] = _deepCopy(resolved.value);
  }
}

double? _legacyMobileFocalCoordinate(Object? raw, WebsiteFocalAxis axis) {
  final coordinates = switch (raw?.toString()) {
    'left' || 'centerLeft' => (x: 0.0, y: 0.5),
    'right' || 'centerRight' => (x: 1.0, y: 0.5),
    'top' || 'topCenter' => (x: 0.5, y: 0.0),
    'bottom' || 'bottomCenter' => (x: 0.5, y: 1.0),
    'center' => (x: 0.5, y: 0.5),
    _ => null,
  };
  if (coordinates == null) return null;
  return axis == WebsiteFocalAxis.horizontal ? coordinates.x : coordinates.y;
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
