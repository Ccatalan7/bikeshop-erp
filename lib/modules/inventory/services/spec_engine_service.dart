import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class SpecDefinition {
  final String id;
  final String key;
  final String label;
  final String dataType; // text | number | boolean | select | multiselect
  final List<String> options;
  final String? unit;
  final String? helpText;
  final int sortOrder;

  const SpecDefinition({
    required this.id,
    required this.key,
    required this.label,
    required this.dataType,
    required this.options,
    this.unit,
    this.helpText,
    required this.sortOrder,
  });

  factory SpecDefinition.fromJson(Map<String, dynamic> j) {
    final raw = j['allowed_values'];
    List<String> opts = [];
    if (raw is List) {
      opts = raw.map((e) => e.toString()).toList();
    }
    return SpecDefinition(
      id: j['id'] as String,
      key: j['key'] as String,
      label: j['label'] as String,
      dataType: j['data_type'] as String? ?? 'text',
      options: opts,
      unit: j['unit'] as String?,
      helpText: j['description'] as String?,
      sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

class SpecTemplateField {
  final String specDefinitionId;
  final String sectionKey;
  final int sortOrder;
  final bool isRequired;
  final dynamic defaultValue;
  final List<Map<String, dynamic>> visibilityRules;

  // Resolved after join
  SpecDefinition? definition;

  SpecTemplateField({
    required this.specDefinitionId,
    required this.sectionKey,
    required this.sortOrder,
    required this.isRequired,
    this.defaultValue,
    required this.visibilityRules,
    this.definition,
  });

  factory SpecTemplateField.fromJson(Map<String, dynamic> j) {
    final raw = j['visibility_rules'];
    List<Map<String, dynamic>> rules = [];
    if (raw is List) {
      rules = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return SpecTemplateField(
      specDefinitionId: j['spec_definition_id'] as String,
      sectionKey: j['section_key'] as String? ?? 'general',
      sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      isRequired: j['is_required'] as bool? ?? false,
      defaultValue: j['default_value_json'],
      visibilityRules: rules,
    );
  }

  /// Evaluate visibility rules against current spec values.
  /// Empty rules → always visible.
  bool isVisible(Map<String, dynamic> currentValues) {
    if (visibilityRules.isEmpty) return true;
    // All rules must pass (AND semantics)
    for (final rule in visibilityRules) {
      final field = rule['field'] as String?;
      final op = rule['operator'] as String? ?? 'eq';
      final expected = rule['value'];
      if (field == null) continue;
      final actual = currentValues[field];
      bool passes;
      switch (op) {
        case 'eq':
          passes = actual?.toString() == expected?.toString();
          break;
        case 'neq':
          passes = actual?.toString() != expected?.toString();
          break;
        case 'in':
          final list = expected is List ? expected : [expected];
          passes = list.map((e) => e?.toString()).contains(actual?.toString());
          break;
        case 'not_in':
          final list = expected is List ? expected : [expected];
          passes = !list.map((e) => e?.toString()).contains(actual?.toString());
          break;
        default:
          passes = true;
      }
      if (!passes) return false;
    }
    return true;
  }
}

class SpecTemplate {
  final String id;
  final String? tenantId;
  final String key;
  final String name;
  final String technicalFamily;
  final List<SpecTemplateField> fields;

  const SpecTemplate({
    required this.id,
    this.tenantId,
    required this.key,
    required this.name,
    required this.technicalFamily,
    required this.fields,
  });

  /// Return unique section keys in display order.
  List<String> get sections {
    final seen = <String>{};
    return fields
        .where((f) => seen.add(f.sectionKey))
        .map((f) => f.sectionKey)
        .toList();
  }

  /// Fields for a given section, sorted by sort_order.
  List<SpecTemplateField> fieldsForSection(String section) {
    final result = fields.where((f) => f.sectionKey == section).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return result;
  }
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class SpecEngineService {
  SpecEngineService._();
  static final SpecEngineService instance = SpecEngineService._();

  final _client = Supabase.instance.client;

  // Cache: template_id → SpecTemplate
  final _templateCache = <String, SpecTemplate>{};
  // Cache: category_id → template_id (null means no mapping)
  final _categoryMappingCache = <String, String?>{};

  // ---------------------------------------------------------------------------
  // Template resolution
  // ---------------------------------------------------------------------------

  /// Return the resolved [SpecTemplate] for [categoryId], or null if no
  /// mapping exists for that category.
  Future<SpecTemplate?> getTemplateForCategory(String categoryId) async {
    // Check category mapping cache
    if (_categoryMappingCache.containsKey(categoryId)) {
      final templateId = _categoryMappingCache[categoryId];
      if (templateId == null) return null;
      return _loadTemplate(templateId);
    }

    try {
      final rows = await _client
          .from('category_tech_mappings')
          .select('template_id')
          .eq('category_id', categoryId)
          .limit(1);

      if (rows.isEmpty) {
        _categoryMappingCache[categoryId] = null;
        return null;
      }

      final templateId = rows.first['template_id'] as String;
      _categoryMappingCache[categoryId] = templateId;
      return _loadTemplate(templateId);
    } catch (e) {
      debugPrint('⚠️ [SpecEngine] getTemplateForCategory error: $e');
      return null;
    }
  }

  /// Load a [SpecTemplate] by id, using the in-memory cache.
  Future<SpecTemplate?> _loadTemplate(String templateId) async {
    if (_templateCache.containsKey(templateId)) {
      return _templateCache[templateId];
    }

    try {
      // 1. Fetch template header
      final tRows = await _client
          .from('spec_templates')
          .select('id, key, name, technical_family, tenant_id')
          .eq('id', templateId)
          .limit(1);

      if (tRows.isEmpty) return null;
      final t = tRows.first;

      // 2. Fetch template fields with their spec definitions
      final fRows = await _client.from('spec_template_fields').select('''
            spec_definition_id,
            section_key,
            sort_order,
            is_required,
            default_value_json,
            visibility_rules,
            spec_definitions!inner(
              id, key, label, data_type, allowed_values, unit, description, sort_order
            )
          ''').eq('template_id', templateId).order('sort_order');

      final fields = fRows.map((row) {
        final field = SpecTemplateField.fromJson(row);
        final defJson = row['spec_definitions'] as Map<String, dynamic>? ?? {};
        field.definition = SpecDefinition.fromJson(defJson);
        return field;
      }).toList();

      final template = SpecTemplate(
        id: t['id'] as String,
        tenantId: t['tenant_id'] as String?,
        key: t['key'] as String,
        name: t['name'] as String,
        technicalFamily: t['technical_family'] as String,
        fields: fields,
      );

      _templateCache[templateId] = template;
      return template;
    } catch (e) {
      debugPrint('⚠️ [SpecEngine] _loadTemplate error: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Spec values
  // ---------------------------------------------------------------------------

  /// Load saved spec values for a product. Returns map of key → value.
  Future<Map<String, dynamic>> getProductSpecValues(String productId) async {
    try {
      final rows = await _client
          .from('product_spec_values')
          .select(
              'spec_definition_id, value_text, value_number, value_boolean, value_option, value_json, spec_definitions!inner(key, data_type)')
          .eq('product_id', productId);

      final result = <String, dynamic>{};
      for (final row in rows) {
        final defJson = row['spec_definitions'] as Map<String, dynamic>?;
        final key = defJson?['key'] as String?;
        final dataType = defJson?['data_type'] as String?;
        if (key == null) continue;

        dynamic value;
        switch (dataType) {
          case 'boolean':
            value = row['value_boolean'];
          case 'number':
            value = row['value_number'];
          case 'single_select':
            value = row['value_option'];
          case 'multi_select':
            final json = row['value_json'];
            value = json is List ? json : (json != null ? [json] : null);
          default:
            value = row['value_text'];
        }

        if (value != null) result[key] = value;
      }
      return result;
    } catch (e) {
      debugPrint('⚠️ [SpecEngine] getProductSpecValues error: $e');
      return {};
    }
  }

  /// Save spec values for a product.
  /// [values] is a map of spec_key → value (only fields belonging to
  /// [template] are written; others are ignored).
  Future<void> saveProductSpecValues({
    required String productId,
    required String tenantId,
    required SpecTemplate template,
    required Map<String, dynamic> values,
  }) async {
    try {
      // Build map: spec_definition_id → value
      final toUpsert = <Map<String, dynamic>>[];
      for (final field in template.fields) {
        final def = field.definition;
        if (def == null) continue;
        final value = values[def.key];
        // Skip null/empty unless we're explicitly clearing
        final isEmpty = value == null ||
            (value is String && value.trim().isEmpty) ||
            (value is List && value.isEmpty);
        if (isEmpty) continue;

        // Map to the correct typed column
        final row = <String, dynamic>{
          'product_id': productId,
          'tenant_id': tenantId,
          'spec_definition_id': def.id,
          'updated_at': DateTime.now().toIso8601String(),
        };

        switch (def.dataType) {
          case 'boolean':
            row['value_boolean'] =
                value == true || value.toString().toLowerCase() == 'true';
            row['display_value'] = row['value_boolean'] == true ? 'Sí' : 'No';
          case 'number':
            final num =
                value is double ? value : double.tryParse(value.toString());
            row['value_number'] = num;
            row['display_value'] = num != null
                ? num.toStringAsFixed(num % 1 == 0 ? 0 : 2)
                : value.toString();
          case 'single_select':
            row['value_option'] = value.toString();
            row['display_value'] = value.toString();
          case 'multi_select':
            final list = value is List ? value : [value];
            row['value_json'] = list;
            row['display_value'] = list.join(', ');
          default: // text, range, json
            row['value_text'] = value.toString();
            row['display_value'] = value.toString();
        }

        toUpsert.add(row);
      }

      if (toUpsert.isEmpty) return;

      await _client.from('product_spec_values').upsert(
            toUpsert,
            onConflict: 'tenant_id,product_id,spec_definition_id',
          );

      debugPrint(
          '✅ [SpecEngine] Saved ${toUpsert.length} spec values for product $productId');
    } catch (e) {
      debugPrint('🔴 [SpecEngine] saveProductSpecValues error: $e');
      rethrow;
    }
  }

  /// Delete all spec values for a product. Useful when changing category.
  Future<void> clearProductSpecValues(String productId) async {
    try {
      await _client
          .from('product_spec_values')
          .delete()
          .eq('product_id', productId);
    } catch (e) {
      debugPrint('⚠️ [SpecEngine] clearProductSpecValues error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Cache management
  // ---------------------------------------------------------------------------

  void clearCache() {
    _templateCache.clear();
    _categoryMappingCache.clear();
  }
}
