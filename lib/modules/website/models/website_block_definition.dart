import 'package:flutter/material.dart';

import 'website_block_type.dart';

/// Supported input widget types for generic block editors.
/// Complex blocks can opt out and implement a bespoke editor UI.
enum WebsiteBlockFieldType {
  text,
  textarea,
  richtext,
  color,
  image,
  number,
  toggle,
  select,
  chips,
  repeater,
}

class WebsiteBlockFieldOption {
  const WebsiteBlockFieldOption({required this.value, required this.label});

  final String value;
  final String label;
}

class WebsiteBlockFieldSchema {
  const WebsiteBlockFieldSchema({
    required this.key,
    required this.label,
    required this.type,
    this.helpText,
    this.options = const [],
    this.min,
    this.max,
    this.step,
    this.defaultValue,
    this.group,
    this.itemLabel,
    this.itemFields = const [],
    this.minItems,
    this.maxItems,
  });

  final String key;
  final String label;
  final WebsiteBlockFieldType type;
  final String? helpText;
  final List<WebsiteBlockFieldOption> options;
  final num? min;
  final num? max;
  final num? step;
  final dynamic defaultValue;
  final String? group;
  final String? itemLabel;
  final List<WebsiteBlockFieldSchema> itemFields;
  final int? minItems;
  final int? maxItems;
}

class WebsiteBlockControlSection {
  const WebsiteBlockControlSection({
    required this.id,
    required this.label,
    this.description,
    this.fieldKeys = const [],
  });

  final String id;
  final String label;
  final String? description;
  final List<String> fieldKeys;
}

class WebsiteBlockDefinition {
  const WebsiteBlockDefinition({
    required this.type,
    required this.title,
    required this.description,
    required this.defaultData,
    this.fields = const [],
    this.usesCustomEditor = false,
    this.previewBadge,
    this.category = 'General',
    this.tags = const [],
    this.version = 1,
    this.supportsResponsive = true,
    this.controlSections = const [],
  });

  final WebsiteBlockType type;
  final String title;
  final String description;
  final Map<String, dynamic> defaultData;
  final List<WebsiteBlockFieldSchema> fields;
  final bool usesCustomEditor;
  final String? previewBadge;
  final String category;
  final List<String> tags;
  final int version;
  final bool supportsResponsive;
  final List<WebsiteBlockControlSection> controlSections;

  IconData get icon => type.icon;
}
