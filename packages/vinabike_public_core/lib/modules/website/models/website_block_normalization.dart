import 'website_action.dart';
import 'website_block_base_definitions.dart';
import 'website_block_document_sanitizer.dart';
import 'website_block_type.dart';

/// Moved from `WebsiteService` (2026-10-05) so the HTML storefront reads a
/// block exactly as the Flutter store does; the service calls it.
const currentWebsiteBlockSchemaVersion = 1;

Map<String, dynamic> _deepMergeMaps(
  Map<String, dynamic> base,
  Map<String, dynamic> override,
) {
  final result = <String, dynamic>{...base};
  override.forEach((key, value) {
    final baseValue = result[key];
    if (value is Map && baseValue is Map) {
      result[key] = _deepMergeMaps(
        Map<String, dynamic>.from(baseValue),
        Map<String, dynamic>.from(value),
      );
    } else {
      result[key] = value;
    }
  });
  return result;
}

/// A block's data as the store and the editor read it (`WebsiteService` on
/// load): the type's default data under the saved values, legacy keys and
/// their aliases synchronized, every visible action in the same contract,
/// and editor-only values removed. [defaultsFor] is the registry's default
/// data for a type; the base definitions unless the caller has others.
Map<String, dynamic> normalizeWebsiteBlockData({
  required String blockTypeRaw,
  required Object? rawBlockData,
  Map<String, dynamic> Function(WebsiteBlockType type)? defaultsFor,
}) {
  final rawMap = rawBlockData is Map
      ? Map<String, dynamic>.from(rawBlockData)
      : <String, dynamic>{};

  final parsedType = parseWebsiteBlockType(
    blockTypeRaw,
    fallback: WebsiteBlockType.hero,
  );
  final defaults =
      defaultsFor?.call(parsedType) ??
      websiteBaseBlockDefinitions[parsedType]?.defaultData ??
      const <String, dynamic>{};

  final normalized = _deepMergeMaps(
    Map<String, dynamic>.from(defaults),
    rawMap,
  );

  dynamic cloneValue(dynamic value) {
    if (value is Map) {
      return value.map(
        (key, nested) => MapEntry(key.toString(), cloneValue(nested)),
      );
    }
    if (value is List) return value.map(cloneValue).toList();
    return value;
  }

  void syncCollectionAliases(String canonicalKey, List<String> aliases) {
    Object? source;
    if (rawMap.containsKey(canonicalKey)) {
      source = rawMap[canonicalKey];
    } else {
      for (final alias in aliases) {
        if (rawMap.containsKey(alias)) {
          source = rawMap[alias];
          break;
        }
      }
    }
    if (source is! List) return;
    final next = cloneValue(source);
    normalized[canonicalKey] = next;
    for (final alias in aliases) {
      normalized[alias] = cloneValue(next);
    }
  }

  void syncScalarAliases(String canonicalKey, List<String> aliases) {
    Object? source;
    var found = false;
    if (rawMap.containsKey(canonicalKey)) {
      source = rawMap[canonicalKey];
      found = true;
    } else {
      for (final alias in aliases) {
        if (rawMap.containsKey(alias)) {
          source = rawMap[alias];
          found = true;
          break;
        }
      }
    }
    if (!found) return;
    normalized[canonicalKey] = cloneValue(source);
    for (final alias in aliases) {
      normalized[alias] = cloneValue(source);
    }
  }

  void syncCollectionItemAliases(
    String collectionKey,
    Map<String, List<String>> fieldAliases, {
    List<String> collectionAliases = const [],
  }) {
    final rawItems = normalized[collectionKey];
    if (rawItems is! List) return;
    final next = <dynamic>[];
    for (final rawItem in rawItems) {
      if (rawItem is! Map) {
        next.add(cloneValue(rawItem));
        continue;
      }
      final item = Map<String, dynamic>.from(rawItem);
      for (final entry in fieldAliases.entries) {
        Object? source;
        var found = false;
        if (item.containsKey(entry.key)) {
          source = item[entry.key];
          found = true;
        } else {
          for (final alias in entry.value) {
            if (item.containsKey(alias)) {
              source = item[alias];
              found = true;
              break;
            }
          }
        }
        if (!found) continue;
        item[entry.key] = cloneValue(source);
        for (final alias in entry.value) {
          item[alias] = cloneValue(source);
        }
      }
      next.add(item);
    }
    normalized[collectionKey] = next;
    for (final alias in collectionAliases) {
      normalized[alias] = cloneValue(next);
    }
  }

  // Canonical collection presence wins even when it is intentionally empty.
  // This must happen before defaults can hide a legacy-only persisted list.
  final collectionType = blockTypeRaw.trim().toLowerCase();
  if (collectionType == 'features') {
    syncCollectionAliases('features', const ['items']);
  } else if (collectionType == 'services') {
    syncCollectionAliases('services', const ['items']);
  } else if (collectionType == 'testimonials') {
    syncCollectionAliases('testimonials', const ['items']);
    syncCollectionItemAliases(
      'testimonials',
      const {
        'comment': ['quote', 'text'],
      },
      collectionAliases: const ['items'],
    );
  } else if (collectionType == 'pricing') {
    syncCollectionAliases('plans', const ['items']);
    syncCollectionItemAliases(
      'plans',
      const {
        'ctaText': ['buttonText'],
        'ctaLink': ['buttonLink'],
        'highlighted': ['isFeatured'],
      },
      collectionAliases: const ['items'],
    );
  } else if (collectionType == 'team') {
    syncScalarAliases('description', const ['subtitle']);
    syncCollectionAliases('members', const ['team', 'items']);
    syncCollectionItemAliases(
      'members',
      const {
        'avatarUrl': ['image'],
      },
      collectionAliases: const ['team', 'items'],
    );
  } else if (collectionType == 'stats') {
    syncCollectionAliases('metrics', const ['stats', 'items']);
  }

  // Schema version convention (noop-first; enables safe future migrations)
  normalized['schemaVersion'] =
      (normalized['schemaVersion'] as int?) ?? currentWebsiteBlockSchemaVersion;

  void syncPrimaryAction(
    Map<String, dynamic> target, {
    Map<String, dynamic>? rawSource,
    required List<String> labelKeys,
    required List<String> hrefKeys,
    String defaultLabel = 'Ver más',
    String defaultHref = '',
    WebsiteActionVariant defaultVariant = WebsiteActionVariant.filled,
    bool enabled = true,
    String? variantKey,
  }) {
    final source = rawSource ?? target;
    final hasExplicitHref = hrefKeys.any(
      (key) =>
          source.containsKey(key) &&
          (source[key]?.toString().trim().isNotEmpty ?? false),
    );
    final hasStructuredAction =
        source['actions'] is List &&
        (source['actions'] as List).whereType<Map>().isNotEmpty;
    final resolutionData = Map<String, dynamic>.from(target);
    if (!hasExplicitHref && hasStructuredAction) {
      for (final key in hrefKeys) {
        resolutionData.remove(key);
      }
      for (final key in labelKeys) {
        resolutionData.remove(key);
      }
      resolutionData['actions'] = source['actions'];
    }

    final action = WebsiteActionValue.resolvePrimary(
      resolutionData,
      labelKeys: labelKeys,
      hrefKeys: hrefKeys,
      variantKeys: variantKey == null ? const ['actionVariant'] : [variantKey],
      defaultLabel: defaultLabel,
      defaultHref: defaultHref,
      defaultVariant: variantKey == null
          ? defaultVariant
          : WebsiteActionVariant.fromStorage(
              target[variantKey]?.toString(),
              fallback: defaultVariant,
            ),
      enabled: enabled,
    );
    final effective =
        action ??
        WebsiteActionValue(
          label: defaultLabel,
          href: '',
          variant: defaultVariant,
        );
    target['actions'] = WebsiteActionValue.mergePrimary(
      target['actions'],
      effective,
    );
    if (action == null) return;
    for (final key in labelKeys) {
      target[key] = action.label;
    }
    for (final key in hrefKeys) {
      target[key] = action.href;
    }
    if (variantKey != null) {
      target[variantKey] = action.variant.storageValue;
    }
  }

  // --- Targeted legacy migrations (keep minimal, safe) ---
  final rawTypeLower = blockTypeRaw.trim().toLowerCase();
  if (rawTypeLower == 'about') {
    final content = (normalized['content'] ?? '').toString().trim();
    final legacyDescription = (normalized['description'] ?? '')
        .toString()
        .trim();
    if (content.isEmpty && legacyDescription.isNotEmpty) {
      normalized['content'] = legacyDescription;
    }

    if ((normalized['imageUrl'] == null ||
            normalized['imageUrl'].toString().trim().isEmpty) &&
        normalized['image'] != null) {
      normalized['imageUrl'] = normalized['image'];
    }
  }

  if (rawTypeLower == 'button') {
    final label = (normalized['label'] ?? '').toString().trim();
    final legacyText = (normalized['text'] ?? '').toString().trim();
    if (label.isEmpty && legacyText.isNotEmpty) {
      normalized['label'] = legacyText;
    }

    if (normalized['style'] == null && normalized['variant'] != null) {
      final variant = normalized['variant'].toString();
      normalized['style'] = switch (variant) {
        'outline' => 'outline',
        'text' => 'text',
        'secondary' => 'filled',
        _ => 'filled',
      };
    }
  }

  if (rawTypeLower == 'cta') {
    final subtitle = (normalized['subtitle'] ?? '').toString().trim();
    final description = (normalized['description'] ?? '').toString().trim();
    if (subtitle.isEmpty && description.isNotEmpty) {
      normalized['subtitle'] = description;
    }

    // Formatting legacy alias
    if (normalized['subtitleFormatting'] == null &&
        normalized['descriptionFormatting'] != null) {
      normalized['subtitleFormatting'] = normalized['descriptionFormatting'];
    }
  }

  if (rawTypeLower == 'categorygrid') {
    final rawCategories = normalized['categories'];
    if (rawCategories is List) {
      final next = <Map<String, dynamic>>[];
      for (final item in rawCategories) {
        if (item is! Map) continue;
        final normalizedItem = Map<String, dynamic>.from(item);

        final ctaLink = (normalizedItem['ctaLink'] ?? '').toString().trim();
        final link = (normalizedItem['link'] ?? '').toString().trim();
        if (ctaLink.isEmpty && link.isNotEmpty) {
          normalizedItem['ctaLink'] = link;
        }
        if (link.isEmpty && ctaLink.isNotEmpty) {
          normalizedItem['link'] = ctaLink;
        }

        final ctaText = (normalizedItem['ctaText'] ?? '').toString().trim();
        final legacyButtonText = (normalizedItem['buttonText'] ?? '')
            .toString()
            .trim();
        if (ctaText.isEmpty && legacyButtonText.isNotEmpty) {
          normalizedItem['ctaText'] = legacyButtonText;
        }
        if (legacyButtonText.isEmpty && ctaText.isNotEmpty) {
          normalizedItem['buttonText'] = ctaText;
        }

        next.add(normalizedItem);
      }
      normalized['categories'] = next;
    }
  }

  if (rawTypeLower == 'videobanner') {
    if ((normalized['imageUrl'] == null ||
            normalized['imageUrl'].toString().trim().isEmpty) &&
        normalized['posterImage'] != null) {
      normalized['imageUrl'] = normalized['posterImage'];
    }

    final ctaText = (normalized['ctaText'] ?? '').toString().trim();
    final legacyButtonText = (normalized['buttonText'] ?? '').toString().trim();
    if (ctaText.isEmpty && legacyButtonText.isNotEmpty) {
      normalized['ctaText'] = legacyButtonText;
    }

    final ctaLink = (normalized['ctaLink'] ?? '').toString().trim();
    final legacyButtonLink = (normalized['buttonLink'] ?? '').toString().trim();
    if (ctaLink.isEmpty && legacyButtonLink.isNotEmpty) {
      normalized['ctaLink'] = legacyButtonLink;
    }

    if (normalized['showCta'] == null) {
      normalized['showCta'] = true;
    }
  }

  if (rawTypeLower == 'hero') {
    // Background image: legacy key was backgroundImage.
    if ((normalized['imageUrl'] == null ||
            normalized['imageUrl'].toString().trim().isEmpty) &&
        normalized['backgroundImage'] != null) {
      normalized['imageUrl'] = normalized['backgroundImage'];
    }
    if ((normalized['backgroundImage'] == null ||
            normalized['backgroundImage'].toString().trim().isEmpty) &&
        normalized['imageUrl'] != null) {
      normalized['backgroundImage'] = normalized['imageUrl'];
    }

    // CTA: legacy keys were buttonText/buttonLink.
    final ctaText = (normalized['ctaText'] ?? '').toString().trim();
    final legacyButtonText = (normalized['buttonText'] ?? '').toString().trim();
    if (ctaText.isEmpty && legacyButtonText.isNotEmpty) {
      normalized['ctaText'] = legacyButtonText;
    }
    if (legacyButtonText.isEmpty && ctaText.isNotEmpty) {
      normalized['buttonText'] = ctaText;
    }

    final ctaLink = (normalized['ctaLink'] ?? '').toString().trim();
    final legacyButtonLink = (normalized['buttonLink'] ?? '').toString().trim();
    if (ctaLink.isEmpty && legacyButtonLink.isNotEmpty) {
      normalized['ctaLink'] = legacyButtonLink;
    }
    if (legacyButtonLink.isEmpty && ctaLink.isNotEmpty) {
      normalized['buttonLink'] = ctaLink;
    }
  }

  // Every visible CTA is normalized into the same action contract. Legacy
  // aliases remain synchronized so old saved pages and newer editor controls
  // cannot disagree about what the visitor clicks.
  if (rawTypeLower == 'hero' ||
      rawTypeLower == 'cta' ||
      rawTypeLower == 'videobanner') {
    syncPrimaryAction(
      normalized,
      rawSource: rawMap,
      labelKeys: const ['ctaText', 'buttonText'],
      hrefKeys: const ['ctaLink', 'buttonLink'],
      defaultHref: rawTypeLower == 'cta' ? '/contacto' : '/productos',
      defaultVariant: WebsiteActionVariant.outline,
      enabled: rawTypeLower != 'videobanner' || normalized['showCta'] != false,
      variantKey: 'actionVariant',
    );
  } else if (rawTypeLower == 'button') {
    syncPrimaryAction(
      normalized,
      rawSource: rawMap,
      labelKeys: const ['label', 'text'],
      hrefKeys: const ['link'],
      defaultLabel: 'Botón',
      defaultHref: '/productos',
      variantKey: 'style',
    );
  } else if (rawTypeLower == 'products') {
    syncPrimaryAction(
      normalized,
      rawSource: rawMap,
      labelKeys: const ['viewAllText'],
      hrefKeys: const ['viewAllLink'],
      defaultLabel: 'Ver todos los productos',
      defaultHref: '/productos',
      defaultVariant: WebsiteActionVariant.outline,
      enabled: normalized['showViewAll'] != false,
      variantKey: 'actionVariant',
    );
  }

  void syncNestedActions(
    String collectionKey, {
    required List<String> labelKeys,
    required List<String> hrefKeys,
    String defaultLabel = 'Ver más',
    String defaultHref = '/productos',
    WebsiteActionVariant defaultVariant = WebsiteActionVariant.filled,
    String? variantKey,
  }) {
    final items = normalized[collectionKey];
    if (items is! List) return;
    final rawItems = rawMap[collectionKey] is List
        ? rawMap[collectionKey] as List
        : const <dynamic>[];
    normalized[collectionKey] = <Map<String, dynamic>>[
      for (var index = 0; index < items.length; index++)
        if (items[index] is Map)
          (() {
            final item = Map<String, dynamic>.from(items[index] as Map);
            final rawItem = index < rawItems.length && rawItems[index] is Map
                ? Map<String, dynamic>.from(rawItems[index] as Map)
                : item;
            syncPrimaryAction(
              item,
              rawSource: rawItem,
              labelKeys: labelKeys,
              hrefKeys: hrefKeys,
              defaultLabel: defaultLabel,
              defaultHref: defaultHref,
              defaultVariant: defaultVariant,
              variantKey: variantKey,
            );
            return item;
          })(),
    ];
  }

  if (rawTypeLower == 'carousel') {
    syncNestedActions(
      'slides',
      labelKeys: const ['ctaText', 'buttonText'],
      hrefKeys: const ['ctaLink', 'buttonLink'],
      defaultVariant: WebsiteActionVariant.outline,
      variantKey: 'actionVariant',
    );
  } else if (rawTypeLower == 'pricing') {
    syncNestedActions(
      'plans',
      labelKeys: const ['ctaText', 'buttonText'],
      hrefKeys: const ['ctaLink', 'buttonLink'],
      defaultLabel: 'Seleccionar',
      variantKey: 'actionVariant',
    );
    if (normalized['plans'] is List) {
      normalized['items'] = cloneValue(normalized['plans']);
    }
  }

  return sanitizeWebsiteBlockDataForPersistence(
    blockType: rawTypeLower,
    data: normalized,
  );
}

/// Every row's `block_data` (or `data`) through [normalizeWebsiteBlockData].
List<Map<String, dynamic>> normalizeWebsiteBlockRows(
  List<Map<String, dynamic>> blocks, {
  Map<String, dynamic> Function(WebsiteBlockType type)? defaultsFor,
}) {
  return blocks.map((block) {
    final next = Map<String, dynamic>.from(block);
    final blockType = (next['block_type'] ?? next['type'] ?? '')
        .toString()
        .trim();
    final rawData = next['block_data'] ?? next['data'];

    if (blockType.isEmpty) return next;

    final normalized = normalizeWebsiteBlockData(
      blockTypeRaw: blockType,
      rawBlockData: rawData,
      defaultsFor: defaultsFor,
    );

    // Keep both key styles in sync when present.
    if (next.containsKey('block_data') || !next.containsKey('data')) {
      next['block_data'] = normalized;
    }
    if (next.containsKey('data')) {
      next['data'] = normalized;
    }

    return next;
  }).toList();
}
