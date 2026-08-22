import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

import '../utils/product_spec_persistence_utils.dart';

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
  final Map<String, dynamic> validationRules;
  final int sortOrder;

  const SpecDefinition({
    required this.id,
    required this.key,
    required this.label,
    required this.dataType,
    required this.options,
    this.unit,
    this.helpText,
    this.validationRules = const <String, dynamic>{},
    required this.sortOrder,
  });

  factory SpecDefinition.fromJson(Map<String, dynamic> j) {
    final raw = j['allowed_values'];
    List<String> opts = [];
    if (raw is List) {
      opts = raw.map((e) => e.toString()).toList();
    }
    final rawValidation = j['validation_rules'];
    final validationRules = rawValidation is Map
        ? Map<String, dynamic>.from(rawValidation)
        : const <String, dynamic>{};
    return SpecDefinition(
      id: j['id'] as String,
      key: j['key'] as String,
      label: j['label'] as String,
      dataType: j['data_type'] as String? ?? 'text',
      options: opts,
      unit: j['unit'] as String?,
      helpText: j['description'] as String?,
      validationRules: validationRules,
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
  final String? helperText;
  final List<Map<String, dynamic>> visibilityRules;

  /// Narrowing rules: which of the definition's allowed_values stay offerable
  /// given the sibling answers. Distinct from [visibilityRules], which decides
  /// whether the field exists at all.
  final List<Map<String, dynamic>> optionRules;

  // Resolved after join
  SpecDefinition? definition;

  SpecTemplateField({
    required this.specDefinitionId,
    required this.sectionKey,
    required this.sortOrder,
    required this.isRequired,
    this.defaultValue,
    this.helperText,
    required this.visibilityRules,
    this.optionRules = const <Map<String, dynamic>>[],
    this.definition,
  });

  factory SpecTemplateField.fromJson(Map<String, dynamic> j) {
    return SpecTemplateField(
      specDefinitionId: j['spec_definition_id'] as String,
      sectionKey: j['section_key'] as String? ?? 'general',
      sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      isRequired: j['is_required'] as bool? ?? false,
      defaultValue: j['default_value_json'],
      helperText: j['helper_text'] as String?,
      visibilityRules: _ruleList(j['visibility_rules']),
      optionRules: _ruleList(j['option_rules']),
    );
  }

  static List<Map<String, dynamic>> _ruleList(dynamic raw) {
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  /// Evaluate visibility rules against current spec values.
  /// Empty rules → always visible.
  bool isVisible(Map<String, dynamic> currentValues) {
    if (visibilityRules.isEmpty) return true;
    // All rules must pass (AND semantics)
    for (final rule in visibilityRules) {
      if (!_conditionMatches(rule, currentValues)) return false;
    }
    return true;
  }

  /// Which of the definition's `allowed_values` stay offerable given the
  /// sibling answers, as normalized strings.
  ///
  /// Returns null when nothing narrows the field — the caller then offers the
  /// definition's full vocabulary. Every matching rule intersects, so two
  /// rules that share no option leave the field with nothing to offer, which
  /// is the honest answer to a contradictory combination.
  ///
  /// This never widens beyond `allowed_values`: `spec_definitions` stays
  /// authoritative for what the value may be, and this only decides what may
  /// be picked here.
  Set<String>? allowedOptionsFor(Map<String, dynamic> currentValues) {
    if (optionRules.isEmpty) return null;
    Set<String>? narrowed;
    for (final rule in optionRules) {
      if (!_conditionMatches(rule, currentValues)) continue;
      final allow = rule['allow'];
      if (allow is! List) continue;
      final offered = allow
          .map(normalizeRuleValue)
          .where((value) => value.isNotEmpty)
          .toSet();
      narrowed =
          narrowed == null ? offered : narrowed.intersection(offered);
    }
    return narrowed;
  }

  bool _conditionMatches(
    Map<String, dynamic> rule,
    Map<String, dynamic> currentValues,
  ) {
    final field = rule['field'] as String?;
    if (field == null) return true;
    final op = rule['operator'] as String? ?? 'eq';
    final expected = rule['value'];
    final actual = normalizeRuleValue(currentValues[field]);

    switch (op) {
      case 'eq':
        return actual == normalizeRuleValue(expected);
      case 'neq':
        return actual != normalizeRuleValue(expected);
      case 'in':
        return _expectedSet(expected).contains(actual);
      case 'not_in':
        return !_expectedSet(expected).contains(actual);
      // "this question has been answered", whatever the answer was. A guided
      // cascade needs it for every step after the first: asking for the
      // construction before the shell is known offers combinations that cannot
      // exist, and a value picked there outlives the correction.
      case 'is_set':
        return actual.isNotEmpty;
      case 'not_set':
        return actual.isEmpty;
      default:
        return true;
    }
  }

  Set<String> _expectedSet(dynamic expected) {
    final list = expected is List ? expected : [expected];
    return list.map(normalizeRuleValue).toSet();
  }

  /// Rule values arrive from JSON, so `73` and `"73.0"` must compare equal to
  /// the `73` a numeric field stores. Mirrors the product form's option
  /// normalization so a rule written against a number keeps matching.
  static String normalizeRuleValue(dynamic value) {
    if (value == null) return '';
    final numeric = value is num
        ? value
        : num.tryParse(value.toString().trim().replaceAll(',', '.'));
    if (numeric != null) {
      final asDouble = numeric.toDouble();
      if (asDouble == asDouble.roundToDouble()) {
        return asDouble.toInt().toString();
      }
      return asDouble.toString();
    }
    return value.toString().trim();
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
            helper_text,
            visibility_rules,
            option_rules,
            spec_definitions!inner(
              id, key, label, data_type, allowed_values, validation_rules, unit, description, sort_order
            )
          ''').eq('template_id', templateId).order('sort_order');

      final fields = fRows.map((row) {
        final field = SpecTemplateField.fromJson(row);
        final defJson = row['spec_definitions'] as Map<String, dynamic>? ?? {};
        field.definition = SpecDefinition.fromJson(defJson);
        return field;
      }).toList()
        // `sort_order` exists on both this table and the embedded
        // `spec_definitions`, so the query's `.order('sort_order')` is
        // ambiguous and does not reliably order the rows. Section order is
        // taken from the first field seen (see `SpecTemplate.sections`), so an
        // unordered list silently decides which section renders first: the
        // pedalier ficha asked for measurements before the standard because
        // the rows came back in physical order.
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

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
  ///
  /// Lee el registro unificado (`spec_facts`), no la tabla vieja: la etiqueta
  /// de un valor de lista se resuelve desde `spec_definition_values` en la
  /// consulta, así que renombrar un valor cambia lo que ve el mecánico sin
  /// reescribir un solo producto. La escritura también va al registro; la
  /// tabla vieja quedó como copia que un trigger mantiene al día mientras
  /// exista algo que la lea.
  Future<Map<String, dynamic>> getProductSpecValues(String productId) async {
    try {
      final rows = await _client
          .from('spec_facts')
          .select('value_text, value_number, value_boolean, '
              'spec_definitions!inner(key, data_type), '
              'spec_fact_values(position, spec_definition_values!inner(label))')
          .eq('subject_type', 'product')
          .eq('subject_id', productId)
          .isFilter('subject_scope', null);

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
            value = _factLabels(row).firstOrNull;
          case 'multi_select':
            final labels = _factLabels(row);
            value = labels.isEmpty ? null : labels;
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

  /// Las etiquetas de un hecho de lista, en el orden en que se eligieron.
  List<String> _factLabels(Map<String, dynamic> row) {
    final raw = row['spec_fact_values'];
    if (raw is! List) return const <String>[];
    final entries = raw.whereType<Map>().toList()
      ..sort((a, b) => ((a['position'] as num?)?.toInt() ?? 0)
          .compareTo((b['position'] as num?)?.toInt() ?? 0));
    return entries
        .map((entry) =>
            (entry['spec_definition_values'] as Map?)?['label'] as String?)
        .whereType<String>()
        .toList(growable: false);
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
      // La ficha se guarda entera en una sola transacción del servidor. El
      // conjunto de la plantilla viaja completo: lo que no venga en el payload
      // se borra allá, así vaciar un campo y llenar otro son el mismo guardado
      // y no existe el estado intermedio en que la ficha quedó a medias.
      //
      // `display_value` ya no se escribe: era una copia congelada de la
      // etiqueta, y es exactamente lo que hacía que renombrar un valor
      // obligara a reescribir productos. Ahora se resuelve al leer.
      final definitionIds = template.fields
          .map((field) => field.definition?.id)
          .whereType<String>()
          .toSet()
          .toList(growable: false);

      final payload = <String, dynamic>{};
      for (final field in template.fields) {
        final def = field.definition;
        if (def == null) continue;
        final value = sanitizeProductSpecValueForPersistence(
          specKey: def.key,
          value: values[def.key],
        );
        final isEmpty = value == null ||
            (value is String && value.trim().isEmpty) ||
            (value is List && value.isEmpty);
        if (isEmpty) continue;

        switch (def.dataType) {
          case 'boolean':
            payload[def.id] = {
              'boolean':
                  value == true || value.toString().toLowerCase() == 'true',
            };
          case 'number':
            final parsed =
                value is num ? value : num.tryParse(value.toString());
            if (parsed == null) continue;
            payload[def.id] = {'number': parsed};
          case 'single_select':
            payload[def.id] = {
              'labels': [value.toString()],
            };
          case 'multi_select':
            final list = value is List ? value : [value];
            payload[def.id] = {
              'labels': list.map((item) => item.toString()).toList(),
            };
          default:
            payload[def.id] = {'text': value.toString()};
        }
      }

      final written = await _client.rpc(
        'save_product_spec_facts_v1',
        params: {
          'p_product_id': productId,
          'p_definition_ids': definitionIds,
          'p_values': payload,
        },
      );

      debugPrint(
          '✅ [SpecEngine] Saved $written spec facts for product $productId');
    } catch (e) {
      debugPrint('🔴 [SpecEngine] saveProductSpecValues error: $e');
      rethrow;
    }
  }

  /// Delete all spec values for a product. Useful when changing category.
  Future<void> clearProductSpecValues(String productId) async {
    try {
      // El trigger inverso limpia la copia en `product_spec_values`.
      await _client
          .from('spec_facts')
          .delete()
          .eq('subject_type', 'product')
          .eq('subject_id', productId);
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
