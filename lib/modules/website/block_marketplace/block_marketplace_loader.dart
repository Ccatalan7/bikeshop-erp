import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/website_block_definition.dart';
import '../models/website_block_type.dart';

/// Loads block definitions declared as JSON files under
/// `assets/block_marketplace/`. The loader is intentionally resilient: if a
/// single block fails to parse the rest of the catalogue continues to load.
class BlockMarketplaceLoader {
  const BlockMarketplaceLoader._();

  static const String _basePath = 'assets/block_marketplace';
  static const String _indexFile = '$_basePath/index.json';

  static Future<List<WebsiteBlockDefinition>> loadDefinitions({
    AssetBundle? bundle,
  }) async {
    final assetBundle = bundle ?? rootBundle;

    Map<String, dynamic> index;
    try {
      final indexRaw = await assetBundle.loadString(_indexFile);
      index = jsonDecode(indexRaw) as Map<String, dynamic>;
    } catch (error, stackTrace) {
      debugPrint('[BlockMarketplaceLoader] Failed to load index: $error');
      debugPrint('$stackTrace');
      return const [];
    }

    final blocks = (index['blocks'] as List?)?.cast<String>() ?? const [];
    if (blocks.isEmpty) {
      return const [];
    }

    final definitions = <WebsiteBlockDefinition>[];

    for (final fileName in blocks) {
      final path = '$_basePath/$fileName';
      try {
        final raw = await assetBundle.loadString(path);
        final jsonMap = jsonDecode(raw) as Map<String, dynamic>;
        final definition = _parseDefinition(jsonMap);
        definitions.add(definition);
      } catch (error, stackTrace) {
        debugPrint('[BlockMarketplaceLoader] Failed to parse "$path": $error');
        debugPrint('$stackTrace');
      }
    }

    return definitions;
  }

  static WebsiteBlockDefinition _parseDefinition(Map<String, dynamic> json) {
    final typeRaw = json['type']?.toString() ?? WebsiteBlockType.hero.name;
    final type = parseWebsiteBlockType(typeRaw);

    final fieldsJson = (json['fields'] as List?) ?? const [];
    final fields = fieldsJson
        .map((field) =>
            field is Map<String, dynamic> ? _parseFieldSchema(field) : null)
        .whereType<WebsiteBlockFieldSchema>()
        .toList();

    final defaultData = _ensureStringMap(json['defaultData']);

    return WebsiteBlockDefinition(
      type: type,
      title: json['title']?.toString() ?? type.name,
      description: json['description']?.toString() ?? '',
      defaultData: defaultData,
      fields: fields,
      usesCustomEditor: json['usesCustomEditor'] == true,
      previewBadge: json['previewBadge']?.toString(),
      category: json['category']?.toString() ?? 'General',
      tags: _parseStringList(json['tags']),
      version: _parseVersion(json['version']),
      supportsResponsive: json['supportsResponsive'] != false,
      controlSections: _parseControlSections(json['controlSections']),
    );
  }

  static WebsiteBlockFieldSchema _parseFieldSchema(
    Map<String, dynamic> json,
  ) {
    final optionsJson = (json['options'] as List?) ?? const [];
    final options = optionsJson
        .map((option) => option is Map<String, dynamic>
            ? WebsiteBlockFieldOption(
                value: option['value']?.toString() ?? '',
                label: option['label']?.toString() ?? '',
              )
            : null)
        .whereType<WebsiteBlockFieldOption>()
        .toList();

    return WebsiteBlockFieldSchema(
      key: json['key']?.toString() ?? 'field',
      label: json['label']?.toString() ?? '',
      type: _parseFieldType(json['type']?.toString()),
      helpText: json['helpText']?.toString(),
      options: options,
      min: _parseNum(json['min']),
      max: _parseNum(json['max']),
      step: _parseNum(json['step']),
      defaultValue: json['defaultValue'],
      group: json['group']?.toString(),
      itemLabel: json['itemLabel']?.toString(),
      itemFields: _parseItemFields(json['itemFields']),
      minItems: _parseNum(json['minItems'])?.toInt(),
      maxItems: _parseNum(json['maxItems'])?.toInt(),
    );
  }

  static WebsiteBlockFieldType _parseFieldType(String? raw) {
    if (raw == null) {
      return WebsiteBlockFieldType.text;
    }

    final normalised = raw.toLowerCase().trim();
    for (final value in WebsiteBlockFieldType.values) {
      if (value.name == normalised) {
        return value;
      }
    }
    return WebsiteBlockFieldType.text;
  }

  static num? _parseNum(dynamic value) {
    if (value is num) {
      return value;
    }
    if (value is String) {
      return num.tryParse(value);
    }
    return null;
  }

  static Map<String, dynamic> _ensureStringMap(dynamic input) {
    if (input is Map<String, dynamic>) {
      return input;
    }

    if (input is Map) {
      return input.map((key, value) => MapEntry(key.toString(), value));
    }

    return <String, dynamic>{};
  }

  static List<String> _parseStringList(dynamic input) {
    if (input is List) {
      return input
          .map((e) => e == null ? '' : e.toString())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static int _parseVersion(dynamic input) {
    if (input is int) {
      return input;
    }
    if (input is String) {
      final parsed = int.tryParse(input);
      if (parsed != null) {
        return parsed;
      }
    }
    return 1;
  }

  static List<WebsiteBlockControlSection> _parseControlSections(dynamic input) {
    if (input is! List) {
      return const [];
    }

    return input
        .map((section) => section is Map<String, dynamic>
            ? WebsiteBlockControlSection(
                id: section['id']?.toString() ?? 'section',
                label: section['label']?.toString() ?? 'Sección',
                description: section['description']?.toString(),
                fieldKeys: _parseStringList(section['fields']),
              )
            : null)
        .whereType<WebsiteBlockControlSection>()
        .toList();
  }

  static List<WebsiteBlockFieldSchema> _parseItemFields(dynamic input) {
    if (input is! List) {
      return const [];
    }

    return input
        .map((field) => field is Map<String, dynamic>
            ? _parseFieldSchema(Map<String, dynamic>.from(field))
            : null)
        .whereType<WebsiteBlockFieldSchema>()
        .toList();
  }
}
