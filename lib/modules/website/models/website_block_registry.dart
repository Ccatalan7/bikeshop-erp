import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_base_definitions.dart';

import '../block_marketplace/block_marketplace_loader.dart';
import 'website_block_capabilities.dart';
import 'website_block_definition.dart';
import 'website_block_type.dart';
import 'website_responsive_authoring.dart';

export 'package:vinabike_public_core/modules/website/models/website_block_base_definitions.dart';

class WebsiteBlockRegistry {
  WebsiteBlockRegistry._();

  static final Map<WebsiteBlockType, WebsiteBlockDefinition> _definitions = {};

  /// The baked-in definitions now live in the shared core
  /// (`website_block_base_definitions.dart`).
  static final Map<WebsiteBlockType, WebsiteBlockDefinition>
      _fallbackDefinitions = websiteBaseBlockDefinitions;

  static bool _marketplaceLoaded = false;

  static Future<void> ensureInitialized({AssetBundle? bundle}) async {
    debugPrint(
        '[WebsiteBlockRegistry] ensureInitialized called, _marketplaceLoaded=$_marketplaceLoaded');
    if (_marketplaceLoaded) {
      debugPrint('[WebsiteBlockRegistry] Already initialized, returning');
      return;
    }

    // Set loaded immediately to prevent multiple attempts
    _marketplaceLoaded = true;
    debugPrint('[WebsiteBlockRegistry] Starting marketplace load...');

    try {
      // Add timeout to prevent hanging
      final definitions =
          await BlockMarketplaceLoader.loadDefinitions(bundle: bundle)
              .timeout(const Duration(seconds: 3), onTimeout: () {
        debugPrint(
            '[WebsiteBlockRegistry] Marketplace load timed out, using fallback');
        return <WebsiteBlockDefinition>[];
      });

      debugPrint(
          '[WebsiteBlockRegistry] Loaded ${definitions.length} definitions');
      if (definitions.isNotEmpty) {
        _definitions
          ..clear()
          ..addEntries(
            definitions.map(
              (definition) => MapEntry(definition.type, definition),
            ),
          );
      }
    } catch (error, stackTrace) {
      debugPrint('[WebsiteBlockRegistry] Marketplace load failed: $error');
      debugPrint('$stackTrace');
    } finally {
      if (_definitions.isEmpty) {
        debugPrint(
          '[WebsiteBlockRegistry] Falling back to baked-in block definitions.',
        );
        _definitions.addAll(_fallbackDefinitions);
      }
      debugPrint('[WebsiteBlockRegistry] ensureInitialized complete');
    }
  }

  static List<WebsiteBlockDefinition> all() {
    return WebsiteBlockType.values.map(definitionFor).toList()
      ..sort((a, b) => a.title.compareTo(b.title));
  }

  static WebsiteBlockDefinition definitionFor(WebsiteBlockType type) {
    final marketplace = _definitions[type];
    final fallback = _fallbackDefinitions[type];

    if (marketplace == null && fallback != null) return fallback;
    if (fallback == null && marketplace != null) return marketplace;
    if (marketplace != null && fallback != null) {
      return WebsiteBlockDefinition(
        type: type,
        title: marketplace.title,
        description: marketplace.description,
        defaultData: {
          ...marketplace.defaultData,
          ...fallback.defaultData,
        },
        // The baked-in schema is the canonical capability contract. Marketplace
        // metadata may enrich labels/discovery, but cannot remove editor controls.
        fields:
            fallback.fields.isNotEmpty ? fallback.fields : marketplace.fields,
        usesCustomEditor:
            fallback.usesCustomEditor || marketplace.usesCustomEditor,
        previewBadge: marketplace.previewBadge ?? fallback.previewBadge,
        category: marketplace.category,
        tags: {...fallback.tags, ...marketplace.tags}.toList(),
        version: marketplace.version > fallback.version
            ? marketplace.version
            : fallback.version,
        supportsResponsive:
            fallback.supportsResponsive && marketplace.supportsResponsive,
        controlSections: fallback.controlSections.isNotEmpty
            ? fallback.controlSections
            : marketplace.controlSections,
      );
    }

    return WebsiteBlockDefinition(
      type: type,
      title: type.name,
      description: 'Bloque sin definición registrada',
      defaultData: const {},
      usesCustomEditor: true,
    );
  }

  static WebsiteBlockCapabilityProfile capabilitiesFor(WebsiteBlockType type) =>
      WebsiteBlockCapabilityRegistry.profileFor(type);

  /// Resolves one schema field by its owner path.
  ///
  /// Custom editors use the same registry metadata as generic controls instead
  /// of recreating a local field contract. Repeater items are addressed with a
  /// dotted path such as `slides.imageUrl`; collection indexes and persisted
  /// item identities deliberately do not belong to the schema path.
  static WebsiteBlockFieldSchema? fieldForPath(
    WebsiteBlockType type,
    String path,
  ) {
    final segments = path
        .split('.')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) return null;

    Iterable<WebsiteBlockFieldSchema> candidates = definitionFor(type).fields;
    WebsiteBlockFieldSchema? resolved;
    for (final segment in segments) {
      resolved = null;
      for (final field in candidates) {
        if (field.key == segment) {
          resolved = field;
          break;
        }
      }
      if (resolved == null) return null;
      candidates = resolved.itemFields;
    }
    return resolved;
  }

  /// Registry-derived responsive capability matrix.
  ///
  /// Nested repeater fields use dotted schema paths. Custom editors still
  /// receive an entry (possibly empty), so the matrix remains total across the
  /// complete block catalogue instead of becoming a second hand-maintained
  /// list that can drift from [WebsiteBlockType.values].
  static Map<WebsiteBlockType, Map<String, WebsiteResponsivePropertyPolicy>>
      responsivePolicyMatrix() {
    return Map<WebsiteBlockType,
        Map<String, WebsiteResponsivePropertyPolicy>>.unmodifiable({
      for (final type in WebsiteBlockType.values)
        type: Map<String, WebsiteResponsivePropertyPolicy>.unmodifiable(
          _responsivePoliciesFor(definitionFor(type).fields),
        ),
    });
  }

  static Map<String, WebsiteResponsivePropertyPolicy> _responsivePoliciesFor(
    Iterable<WebsiteBlockFieldSchema> fields, {
    String prefix = '',
  }) {
    final result = <String, WebsiteResponsivePropertyPolicy>{};
    for (final field in fields) {
      final path = prefix.isEmpty ? field.key : '$prefix.${field.key}';
      result[path] = field.responsivePolicy;
      if (field.supportsFocalPoint) {
        result[prefix.isEmpty
                ? field.focalPointXKey
                : '$prefix.${field.focalPointXKey}'] =
            WebsiteResponsivePropertyPolicy.perViewportGeometry;
        result[prefix.isEmpty
                ? field.focalPointYKey
                : '$prefix.${field.focalPointYKey}'] =
            WebsiteResponsivePropertyPolicy.perViewportGeometry;
      }
      if (field.supportsAltText) {
        result[prefix.isEmpty
                ? field.altTextKey
                : '$prefix.${field.altTextKey}'] =
            WebsiteResponsivePropertyPolicy.sharedOnly;
      }
      result.addAll(
        _responsivePoliciesFor(field.itemFields, prefix: path),
      );
    }
    return result;
  }
}
