import 'package:flutter/material.dart';

import 'website_block_type.dart';
import 'website_responsive_authoring.dart';

/// Supported input widget types for generic block editors.
/// Complex blocks can opt out and implement a bespoke editor UI.
enum WebsiteBlockFieldType {
  text,
  textarea,
  richtext,
  link,
  color,
  image,
  video,
  number,
  toggle,
  select,
  chips,
  repeater,
}

enum WebsiteTextRole {
  plain,
  heading,
  paragraph,
  caption,
  buttonLabel,
  quote,
  statValue,
  navigationLabel,
}

enum WebsiteMediaRole {
  cover,
  inline,
  avatar,
  logo,
  galleryItem,
  poster,
}

enum WebsiteActionRole {
  primary,
  secondary,
  card,
  navigation,
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
    this.textRole = WebsiteTextRole.plain,
    this.supportsFormatting = false,
    this.formattingKey,
    this.mediaRole,
    this.supportsFocalPoint = false,
    this.supportsAltText = false,
    this.focalPointXKey = 'focalPointX',
    this.focalPointYKey = 'focalPointY',
    this.mobileFocalPointXKey = 'mobileFocalPointX',
    this.mobileFocalPointYKey = 'mobileFocalPointY',
    this.altTextKey = 'altText',
    this.actionRole,
    this.actionLabelKey,
    this.actionVariantKey,
    this.migrationAliases = const [],
    this.responsivePolicy = WebsiteResponsivePropertyPolicy.sharedOnly,
    this.propertyFamily,
    this.authoringSurfaces = const {WebsiteAuthoringSurface.inspector},
    this.supportsResponsiveReset = true,
    this.legacyResponsiveAliases = const [],
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
  final WebsiteTextRole textRole;
  final bool supportsFormatting;
  final String? formattingKey;
  final WebsiteMediaRole? mediaRole;
  final bool supportsFocalPoint;
  final bool supportsAltText;
  final String focalPointXKey;
  final String focalPointYKey;
  final String mobileFocalPointXKey;
  final String mobileFocalPointYKey;
  final String altTextKey;
  final WebsiteActionRole? actionRole;

  /// When set on a link field, the generic editor renders this destination and
  /// its label as one [WebsiteActionEditor] instead of two unrelated inputs.
  final String? actionLabelKey;

  /// Optional legacy field that stores filled/outline/text presentation.
  final String? actionVariantKey;
  final List<String> migrationAliases;
  final WebsiteResponsivePropertyPolicy responsivePolicy;
  final WebsiteResponsivePropertyFamily? propertyFamily;
  final Set<WebsiteAuthoringSurface> authoringSurfaces;
  final bool supportsResponsiveReset;
  final List<String> legacyResponsiveAliases;

  bool get allowsViewportOverride => responsivePolicy.supportsViewportOverride;

  bool get canResetResponsiveOverride =>
      allowsViewportOverride && supportsResponsiveReset;

  /// Canonical policy projection for the accessibility copy paired with a
  /// media field.
  ///
  /// The asset and focal point may vary by viewport; its description may not.
  /// Keeping that rule here prevents each inspector surface from inventing a
  /// local pseudo-field merely to explain where the alt text writes.
  WebsiteBlockFieldSchema? get altTextField {
    if (!supportsAltText) return null;
    return WebsiteBlockFieldSchema(
      key: altTextKey,
      label: 'Texto alternativo',
      type: WebsiteBlockFieldType.text,
      helpText: 'Describe la imagen para accesibilidad.',
      group: group,
      textRole: WebsiteTextRole.plain,
      responsivePolicy: WebsiteResponsivePropertyPolicy.sharedOnly,
      propertyFamily: WebsiteResponsivePropertyFamily.content,
      authoringSurfaces: authoringSurfaces,
    );
  }

  WebsiteResponsivePropertyFamily get resolvedPropertyFamily {
    if (propertyFamily != null) return propertyFamily!;
    if (resolvedMediaRole != null) return WebsiteResponsivePropertyFamily.media;
    if (resolvedActionRole != null) {
      return WebsiteResponsivePropertyFamily.action;
    }
    if (type == WebsiteBlockFieldType.color) {
      return WebsiteResponsivePropertyFamily.color;
    }
    if (type == WebsiteBlockFieldType.repeater ||
        type == WebsiteBlockFieldType.chips) {
      return WebsiteResponsivePropertyFamily.collection;
    }
    if (supportsFormatting) {
      return WebsiteResponsivePropertyFamily.typography;
    }
    return WebsiteResponsivePropertyFamily.content;
  }

  WebsiteTextRole get resolvedTextRole {
    if (textRole != WebsiteTextRole.plain) return textRole;

    final normalizedKey = key.toLowerCase();
    if (normalizedKey.contains('title') || normalizedKey == 'heading') {
      return WebsiteTextRole.heading;
    }
    if (normalizedKey.contains('button') ||
        normalizedKey.contains('cta') ||
        normalizedKey == 'label') {
      return WebsiteTextRole.buttonLabel;
    }
    if (normalizedKey.contains('caption')) return WebsiteTextRole.caption;
    if (normalizedKey.contains('quote') || normalizedKey == 'comment') {
      return WebsiteTextRole.quote;
    }
    if (normalizedKey.contains('value') ||
        normalizedKey == 'price' ||
        normalizedKey == 'number') {
      return WebsiteTextRole.statValue;
    }
    if (type == WebsiteBlockFieldType.textarea ||
        type == WebsiteBlockFieldType.richtext ||
        normalizedKey.contains('description') ||
        normalizedKey.contains('content') ||
        normalizedKey.contains('subtitle') ||
        normalizedKey == 'bio') {
      return WebsiteTextRole.paragraph;
    }
    return WebsiteTextRole.plain;
  }

  String get resolvedFormattingKey => formattingKey ?? '${key}Formatting';

  WebsiteMediaRole? get resolvedMediaRole {
    if (mediaRole != null) return mediaRole;
    if (type != WebsiteBlockFieldType.image) return null;

    final normalizedKey = key.toLowerCase();
    if (normalizedKey.contains('background') ||
        normalizedKey == 'imageurl' ||
        normalizedKey.contains('cover') ||
        normalizedKey.contains('poster')) {
      return WebsiteMediaRole.cover;
    }
    if (normalizedKey.contains('avatar') ||
        normalizedKey.contains('portrait')) {
      return WebsiteMediaRole.avatar;
    }
    if (normalizedKey.contains('logo')) return WebsiteMediaRole.logo;
    return WebsiteMediaRole.inline;
  }

  WebsiteActionRole? get resolvedActionRole {
    if (actionRole != null) return actionRole;
    if (type != WebsiteBlockFieldType.link) return null;

    final normalizedKey = key.toLowerCase();
    if (normalizedKey.contains('cta') || normalizedKey.contains('button')) {
      return WebsiteActionRole.primary;
    }
    if (normalizedKey.contains('nav') || normalizedKey.contains('menu')) {
      return WebsiteActionRole.navigation;
    }
    return WebsiteActionRole.card;
  }

  bool get isCoverMedia => resolvedMediaRole == WebsiteMediaRole.cover;
  bool get hasFocalPointControl =>
      supportsFocalPoint ||
      resolvedMediaRole == WebsiteMediaRole.cover ||
      resolvedMediaRole == WebsiteMediaRole.galleryItem;
  bool get hasAltTextControl =>
      supportsAltText || type == WebsiteBlockFieldType.image;
  bool get isAction => resolvedActionRole != null;
}

/// Cross-family page-layout fields owned by page composition.
///
/// These values are not content fields of Hero, FAQ, Canvas, etc. Keeping one
/// schema here prevents every custom inspector from inventing a second policy
/// for height and inter-block spacing while still letting the universal
/// responsive binding describe common/inherited/override truth.
abstract final class WebsiteBlockMetaFields {
  static const WebsiteBlockFieldSchema blockHeight = WebsiteBlockFieldSchema(
    key: 'blockHeight',
    label: 'Altura del bloque',
    type: WebsiteBlockFieldType.number,
    responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
    propertyFamily: WebsiteResponsivePropertyFamily.geometry,
    authoringSurfaces: {
      WebsiteAuthoringSurface.contextSheet,
      WebsiteAuthoringSurface.inspector,
    },
  );

  static const WebsiteBlockFieldSchema spacingAfter = WebsiteBlockFieldSchema(
    key: 'spacingAfter',
    label: 'Espacio después del bloque',
    type: WebsiteBlockFieldType.number,
    responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
    propertyFamily: WebsiteResponsivePropertyFamily.spacing,
    authoringSurfaces: {
      WebsiteAuthoringSurface.contextSheet,
      WebsiteAuthoringSurface.inspector,
    },
  );

  static const List<WebsiteBlockFieldSchema> fields = <WebsiteBlockFieldSchema>[
    blockHeight,
    spacingAfter,
  ];
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
