import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/spec_rule_evaluator.dart';
import '../models/product_spec_number.dart';
import '../models/product_spec_rows.dart';
import '../models/product_spec_template_rules.dart';
import '../models/product_spec_coherence.dart';
import '../models/product_spec_row_conditions.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class SpecDefinition {
  final String id;
  final String key;
  final String label;
  final String dataType; // text | number | boolean | single/multi_select | json
  final List<String> options;
  final String? unit;
  final String? helpText;
  final Map<String, dynamic> validationRules;
  final int sortOrder;
  final Map<String, String>? _optionIds;
  Map<String, String> get optionIds => _optionIds ?? const {};

  ProductSpecRowSchema? get rowSchema => validationRules['rows_schema'] is Map
      ? ProductSpecRowSchema.fromJson(
          Map<String, dynamic>.from(validationRules['rows_schema'] as Map))
      : null;

  const SpecDefinition({
    required this.id,
    required this.key,
    required this.label,
    required this.dataType,
    required this.options,
    Map<String, String> optionIds = const {},
    this.unit,
    this.helpText,
    this.validationRules = const <String, dynamic>{},
    required this.sortOrder,
  }) : _optionIds = optionIds;

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
      optionIds: {
        for (final value
            in (j['spec_definition_values'] as List? ?? []).whereType<Map>())
          value['label'] as String: value['id'] as String
      },
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

  /// Enforced rules have a reviewed scope and source. Legacy option_rules are
  /// suggestions, and must not become mechanical prohibitions by accident.
  final List<Map<String, dynamic>>? _constraintRules;
  List<Map<String, dynamic>> get constraintRules =>
      _constraintRules ?? const [];

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
    List<Map<String, dynamic>> constraintRules = const [],
    this.definition,
  }) : _constraintRules = constraintRules;

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
      constraintRules: _ruleList(j['constraint_rules']),
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
    return applicability(currentValues) == SpecTruth.yes;
  }

  SpecTruth applicability(Map<String, dynamic> currentValues) =>
      evaluateSpecConditions(visibilityRules, currentValues);

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
    return intersectSpecOptionRules(optionRules, currentValues);
  }

  Set<String>? constrainedOptionsFor(Map<String, dynamic> values) =>
      intersectSpecOptionRules(constraintRules, values);

  static String normalizeRuleValue(dynamic value) =>
      normalizeSpecRuleValue(value);
}

class SpecTemplate {
  final String id;
  final String? tenantId;
  final String key;
  final String name;
  final String technicalFamily;
  final List<SpecTemplateField> fields;
  // A live debug editor can retain an older model across hot reload. Until
  // refreshed it remains version 1, which the server cannot accept as v2.
  final Map<String, dynamic>? _formContract;
  final int? _contractVersion;
  Map<String, dynamic> get formContract => _formContract ?? const {};
  int get contractVersion => _contractVersion ?? 1;

  const SpecTemplate({
    required this.id,
    this.tenantId,
    required this.key,
    required this.name,
    required this.technicalFamily,
    required this.fields,
    Map<String, dynamic> formContract = const {},
    int contractVersion = 1,
  })  : _formContract = formContract,
        _contractVersion = contractVersion;

  List<String> prerequisitesFor(String key) => List<String>.from(
      (formContract['prerequisites'] as Map?)?[key] as List? ?? []);

  ProductSpecRowConditions get rowConditions =>
      ProductSpecRowConditions.fromContract(formContract, {
        for (final field in fields)
          if (field.definition != null &&
              roleFor(field.definition!.key) != 'legacy' &&
              field.definition!.rowSchema != null)
            field.definition!.key: field.definition!.rowSchema!
      });

  ProductSpecCoherence get coherence {
    final active = fields.where(
        (f) => f.definition != null && roleFor(f.definition!.key) != 'legacy');
    return ProductSpecCoherence.fromContract(formContract, {
      for (final f in active) f.definition!.key: f.definition!.dataType
    }, {
      for (final f in active)
        if (f.definition!.rowSchema != null)
          f.definition!.key: f.definition!.rowSchema!
    }, {
      for (final f in active)
        f.definition!.key: {
          ...prerequisitesFor(f.definition!.key),
          ...applicabilityDependencies(f)
        }
    }, units: {
      for (final f in active) f.definition!.key: f.definition!.unit
    }, numberRules: {
      for (final f in active)
        if (f.definition!.dataType == 'number')
          f.definition!.key: f.definition!.validationRules
    });
  }

  SpecTruth applicabilityFor(
      SpecTemplateField field, Map<String, dynamic> values) {
    final expression =
        (formContract['allowed_when'] as Map?)?[field.definition?.key];
    final legacy = field.applicability(values);
    if (expression == null) return legacy;
    final declared = evaluateProductSpecTemplateCondition(expression, values);
    if (legacy == SpecTruth.no || declared == SpecTruth.no) return SpecTruth.no;
    if (legacy == SpecTruth.unknown || declared == SpecTruth.unknown) {
      return SpecTruth.unknown;
    }
    return SpecTruth.yes;
  }

  SpecTruth requiredFor(SpecTemplateField field, Map<String, dynamic> values) {
    final expression =
        (formContract['required_when'] as Map?)?[field.definition?.key];
    return expression == null
        ? SpecTruth.no
        : evaluateProductSpecTemplateCondition(expression, values);
  }

  Set<String> applicabilityDependencies(SpecTemplateField field) {
    final expression =
        (formContract['allowed_when'] as Map?)?[field.definition?.key];
    return {
      ...specConditionDependencies(field.visibilityRules),
      if (expression != null)
        ...productSpecTemplateConditionDependencies(expression),
    };
  }

  Set<String>? constrainedOptionsFor(
      SpecTemplateField field, Map<String, dynamic> values) {
    final local = (formContract['allowed_options']
        as Map?)?[field.definition?.key] as List?;
    Set<String>? constrained;
    if (formContract['rules_version'] == 2) {
      for (final rule in field.constraintRules) {
        if (evaluateSpecCondition(rule, values) != SpecTruth.yes) continue;
        final raw = rule['allow'];
        if (raw is! List ||
            raw.any((v) =>
                v is! String &&
                !(field.definition?.dataType == 'boolean' && v is bool))) {
          throw const FormatException('Opciones de requisito inválidas.');
        }
        final allowed = raw.map((v) => v.toString()).toSet();
        constrained = constrained?.intersection(allowed) ?? allowed;
      }
    } else {
      constrained = field.constrainedOptionsFor(values);
    }
    if (local == null) return constrained;
    final subset = Set<String>.from(local);
    return constrained == null ? subset : subset.intersection(constrained);
  }

  String roleFor(String key) =>
      (formContract['roles'] as Map?)?[key] as String? ?? 'primary';

  String labelFor(String key) =>
      displayLabelFor(key) ??
      fields
          .where((field) => field.definition?.key == key)
          .firstOrNull
          ?.definition
          ?.label ??
      key;

  String sectionFor(SpecTemplateField field) => formContract.isEmpty
      ? field.sectionKey
      : roleFor(field.definition?.key ?? '');

  String? helperFor(String key) =>
      (formContract['helpers'] as Map?)?[key] as String?;
  String? displayLabelFor(String key) =>
      (formContract['labels'] as Map?)?[key] as String?;

  /// Return unique section keys in display order.
  List<String> get sections {
    if (formContract.isNotEmpty) {
      final used = fields.map(sectionFor).toSet();
      return ['primary', 'measurement', 'contents', 'declaration', 'legacy']
          .where(used.contains)
          .toList(growable: false);
    }
    final seen = <String>{};
    return fields
        .where((f) => seen.add(f.sectionKey))
        .map((f) => f.sectionKey)
        .toList();
  }

  /// Fields for a given section, sorted by sort_order.
  List<SpecTemplateField> fieldsForSection(String section) {
    final result = fields.where((f) => sectionFor(f) == section).toList()
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

  // Always read the active contract when opening/retrying an editor. Server
  // versions reject stale saves; no process-wide cache may hide that reload.
  Future<SpecTemplate?> getTemplateForCategory(String categoryId) async =>
      (await getProductEditorContext(categoryId: categoryId)).template;

  /// Identity, facts and definitions share one server snapshot and version.
  Future<({SpecTemplate? template, Map<String, dynamic> snapshot})>
      getProductEditorContext({String? productId, String? categoryId}) async {
    final result = await _client.rpc('get_product_spec_editor_context_v2',
        params: {'p_product_id': productId, 'p_category_id': categoryId});
    final snapshot = Map<String, dynamic>.from(result as Map);
    if (snapshot['product_id'] != productId ||
        snapshot['draft_category_id'] != categoryId) {
      throw const FormatException('La lectura pertenece a otra ficha.');
    }
    return decodeProductSpecEditorContext(snapshot);
  }

  /// The v2 RPC supplies facts, definitions and the version in one PostgreSQL
  /// snapshot. Numeric observations and bounds must already be decimal text:
  /// converting a decoded JSON double back to text cannot recover its digits.
  static ({SpecTemplate? template, Map<String, dynamic> snapshot})
      decodeProductSpecEditorContext(Map<String, dynamic> snapshot) {
    final revision = snapshot['revision'];
    if (snapshot['read_schema_version'] is! int ||
        snapshot['read_schema_version'] != 2 ||
        revision is! int ||
        revision < 0 ||
        revision > 9007199254740991 ||
        snapshot['values'] is! Map) {
      throw const FormatException(
          'Lectura de ficha inválida. Reintenta la carga.');
    }
    final raw = snapshot['template'];
    if (snapshot['template_id'] == null) {
      if (raw != null)
        throw const FormatException('Identidad de ficha inválida.');
      return (template: null, snapshot: Map<String, dynamic>.from(snapshot));
    }
    if (raw is! Map ||
        snapshot['contract_version'] is! int ||
        raw['id'] != snapshot['template_id'] ||
        raw['contract_version'] != snapshot['contract_version'] ||
        raw['key'] != snapshot['template_key'] ||
        raw['technical_family'] != snapshot['technical_family'] ||
        raw['contract_version'] is! int ||
        (raw['contract_version'] as int) < 1 ||
        raw['form_contract'] is! Map ||
        raw['fields'] is! List) {
      throw const FormatException('Identidad o versión de ficha inválida.');
    }
    final ids = <String>{};
    final keys = <String>{};
    final fields = <SpecTemplateField>[];
    for (final item in raw['fields'] as List) {
      if (item is! Map || item['spec_definitions'] is! Map) {
        throw const FormatException('Campo de ficha inválido.');
      }
      final rawDefinition = item['spec_definitions'] as Map;
      if (rawDefinition['validation_rules'] is! Map ||
          !const {
            'text',
            'number',
            'boolean',
            'single_select',
            'multi_select',
            'range',
            'json'
          }.contains(rawDefinition['data_type']) ||
          item['is_required'] is! bool ||
          ['visibility_rules', 'option_rules', 'constraint_rules'].any((key) =>
              item[key] is! List ||
              (item[key] as List).any((rule) => rule is! Map))) {
        throw const FormatException('Reglas de campo inválidas.');
      }
      final field = SpecTemplateField.fromJson(Map<String, dynamic>.from(item));
      final definition = SpecDefinition.fromJson(
          Map<String, dynamic>.from(item['spec_definitions'] as Map));
      if (field.specDefinitionId != definition.id ||
          !ids.add(definition.id) ||
          !keys.add(definition.key)) {
        throw const FormatException('Identidad de campo inválida.');
      }
      if (definition.dataType == 'number') {
        for (final value in [
          (snapshot['values'] as Map)[definition.key],
          field.defaultValue,
          definition.validationRules['min'],
          definition.validationRules['max']
        ]) {
          if (value != null &&
              (value is! String || SpecRuleDecimal.tryParse(value) == null)) {
            throw const FormatException(
                'La medida no tiene un transporte exacto.');
          }
        }
      }
      field.definition = definition;
      fields.add(field);
    }
    fields.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final template = SpecTemplate(
      id: raw['id'] as String,
      tenantId: raw['tenant_id'] as String?,
      key: raw['key'] as String,
      name: raw['name'] as String,
      technicalFamily: raw['technical_family'] as String,
      fields: fields,
      formContract:
          Map<String, dynamic>.from(raw['form_contract'] as Map? ?? {}),
      contractVersion: raw['contract_version'] as int,
    );
    // Do not mount an editor whose field links are unknown or point outside
    // its own template, even if the transport itself was well formed.
    template.coherence.validate(const {});
    template.rowConditions.validate(const {});
    return (template: template, snapshot: Map<String, dynamic>.from(snapshot));
  }

  // ---------------------------------------------------------------------------
  // Spec values
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> getProductSpecSnapshot(String productId) async {
    final result = await _client.rpc('get_product_spec_snapshot_v1',
        params: {'p_product_id': productId});
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> getReferences(String family) async {
    final result = await _client
        .rpc('get_product_spec_references_v2', params: {'p_family': family});
    return (result as List).map((row) {
      final reference = Map<String, dynamic>.from(row as Map);
      if (reference['read_schema_version'] is! int ||
          reference['read_schema_version'] != 2 ||
          reference['facts'] is! Map) {
        throw const FormatException('Lectura de referencia inválida.');
      }
      return reference;
    }).toList(growable: false);
  }

  /// V2 writes normalized option identities. Unknown/invalid values fail before
  /// the product command; they can never disappear through a failed label join.
  static Map<String, dynamic> buildFactPayload(
      SpecTemplate template, Map<String, dynamic> values) {
    final payload = <String, dynamic>{};
    for (final field in template.fields) {
      final def = field.definition;
      if (def == null || template.roleFor(def.key) == 'legacy') continue;
      final value = values[def.key];
      if (!hasKnownSpecValue(value)) continue;
      switch (def.dataType) {
        case 'boolean':
          if (value is! bool)
            throw FormatException('${def.label}: booleano inválido');
          payload[def.id] = {'boolean': value};
        case 'number':
          if (productSpecNumberErrorCode(value, def.validationRules) != null) {
            throw FormatException(
                '${def.label}: número inválido para este campo');
          }
          payload[def.id] = {'number': productSpecNumberWireValue(value)};
        case 'json':
          final schema = def.rowSchema;
          if (schema == null) {
            throw FormatException(
                '${def.label}: falta el esquema de configuraciones');
          }
          payload[def.id] = {'rows': schema.parse(value).toJson()};
        case 'single_select':
        case 'multi_select':
          final labels = value is List ? value : [value];
          final ids = labels.map((label) {
            final id = def.optionIds[label.toString()];
            if (id == null)
              throw FormatException('${def.label}: opción desconocida $label');
            return id;
          }).toList(growable: false);
          payload[def.id] = {'value_ids': ids};
        default:
          payload[def.id] = {'text': value.toString()};
      }
    }
    return payload;
  }

  // ---------------------------------------------------------------------------
  // Cache management
  // ---------------------------------------------------------------------------

  void clearCache() {
    // Compatibility with callers: contracts are now read fresh.
  }
}
