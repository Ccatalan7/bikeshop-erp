import 'package:flutter/foundation.dart';

/// Catalog entry for a compatibility component type (e.g., wheel_hub_rear).
class CompatComponentType {
  final String id;
  final String tenantId;
  final String code;
  final String displayName;
  final String? parentId;
  final List<String> disciplineScope;
  final String? description;
  final String? iconName;
  final bool isActive;

  CompatComponentType({
    required this.id,
    required this.tenantId,
    required this.code,
    required this.displayName,
    required this.parentId,
    required this.disciplineScope,
    required this.description,
    required this.iconName,
    required this.isActive,
  });

  factory CompatComponentType.fromJson(Map<String, dynamic> json) {
    return CompatComponentType(
      id: json['id']?.toString() ?? '',
      tenantId: json['tenant_id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? '',
      parentId: json['parent_id']?.toString(),
      disciplineScope: (json['discipline_scope'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      description: json['description']?.toString(),
      iconName: json['icon_name']?.toString(),
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  /// Create from product_category JSON (new pattern - uses category as component type)
  factory CompatComponentType.fromCategoryJson(Map<String, dynamic> json) {
    final metadata = json['compatibility_metadata'] as Map? ?? {};
    final code = metadata['component_code']?.toString() ?? json['name']?.toString() ?? '';
    
    return CompatComponentType(
      id: json['id']?.toString() ?? '',
      tenantId: json['tenant_id']?.toString() ?? '',
      code: code,
      displayName: json['name']?.toString() ?? '',
      parentId: json['parent_id']?.toString(),
      disciplineScope: (json['discipline_scope'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      description: json['description']?.toString(),
      iconName: json['icon_name']?.toString(),
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

/// Option for enum-type compatibility attributes.
class CompatAttributeOption {
  final String id;
  final String attributeId;
  final String valueKey;
  final String displayName;
  final String? description;
  final int sortOrder;

  const CompatAttributeOption({
    required this.id,
    required this.attributeId,
    required this.valueKey,
    required this.displayName,
    required this.description,
    required this.sortOrder,
  });

  factory CompatAttributeOption.fromJson(Map<String, dynamic> json) {
    return CompatAttributeOption(
      id: json['id']?.toString() ?? '',
      attributeId: json['attribute_id']?.toString() ?? '',
      valueKey: json['value_key']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? '',
      description: json['description']?.toString(),
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}

/// Attribute definition with metadata from compat_attributes.
class CompatAttributeDefinition {
  final String id;
  final String tenantId;
  final String key;
  final String label;
  final String attributeType; // enum, numeric, boolean, text, json, range
  final String? unitCode;
  final String? description;
  final double? minValue;
  final double? maxValue;
  final int? precisionScale;
  final bool isGlobal;

  const CompatAttributeDefinition({
    required this.id,
    required this.tenantId,
    required this.key,
    required this.label,
    required this.attributeType,
    required this.unitCode,
    required this.description,
    required this.minValue,
    required this.maxValue,
    required this.precisionScale,
    required this.isGlobal,
  });

  factory CompatAttributeDefinition.fromJson(Map<String, dynamic> json) {
    double? parseDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString());
    }

    return CompatAttributeDefinition(
      id: json['id']?.toString() ?? '',
      tenantId: json['tenant_id']?.toString() ?? '',
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      attributeType: json['attribute_type']?.toString() ?? 'text',
      unitCode: json['unit_code']?.toString(),
      description: json['description']?.toString(),
      minValue: parseDouble(json['min_value']),
      maxValue: parseDouble(json['max_value']),
      precisionScale: json['precision_scale'] as int?,
      isGlobal: json['is_global'] as bool? ?? false,
    );
  }
}

/// Schema row that maps an attribute definition to a component type plus UI hints.
class CompatAttributeField {
  final String id;
  final String componentTypeId;
  final CompatAttributeDefinition attribute;
  final bool isRequired;
  final bool isPrimary;
  final double matchWeight;
  final String? uiGroup;
  final int uiOrder;
  final Map<String, dynamic> validation;
  final List<CompatAttributeOption> options;

  const CompatAttributeField({
    required this.id,
    required this.componentTypeId,
    required this.attribute,
    required this.isRequired,
    required this.isPrimary,
    required this.matchWeight,
    required this.uiGroup,
    required this.uiOrder,
    required this.validation,
    required this.options,
  });

  factory CompatAttributeField.fromJson(
    Map<String, dynamic> schema,
    CompatAttributeDefinition attribute,
    List<CompatAttributeOption> options,
  ) {
    double? parseDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString());
    }

    final rawWeight = parseDouble(schema['match_weight']) ?? 1;

    return CompatAttributeField(
      id: schema['id']?.toString() ?? '',
      componentTypeId: schema['component_type_id']?.toString() ?? '',
      attribute: attribute,
      isRequired: schema['is_required'] as bool? ?? false,
      isPrimary: schema['is_primary'] as bool? ?? false,
      matchWeight: rawWeight,
      uiGroup: schema['ui_group']?.toString(),
      uiOrder: schema['ui_order'] as int? ?? 0,
      validation: Map<String, dynamic>.from(schema['validation'] as Map? ?? {}),
      options: options,
    );
  }

  bool get isEnum => attribute.attributeType == 'enum';
  bool get isNumeric => attribute.attributeType == 'numeric';
  bool get isBoolean => attribute.attributeType == 'boolean';
  bool get isText => attribute.attributeType == 'text' || attribute.attributeType == 'json';
}

/// Simple helper to group fields for UI rendering.
@immutable
class CompatFieldGroup {
  final String name;
  final List<CompatAttributeField> fields;

  const CompatFieldGroup({required this.name, required this.fields});
}
