import 'dart:convert';

import 'package:collection/collection.dart';

import 'inventory_models.dart';
import '../services/spec_engine_service.dart';
import '../utils/spec_rule_evaluator.dart';
import '../services/product_identity/product_identity_extractor.dart';
import 'product_spec_relation.dart';
import 'product_spec_rows.dart';
import 'product_spec_number.dart';

/// Suggestions reuse the identity/fitment split. Confirming a model is a
/// separate operator action; neither a name nor a suggestion binds a variant.
List<String> suggestProductSpecModels({
  required String name,
  required String brand,
  required String family,
  required List<ProductSpecReference> references,
}) {
  if (family != 'chain' && family != 'chain_link') return const [];
  final identity = ProductIdentityExtractor.extract(ProductIdentityInput(
      name: name, brandHint: brand, brandIsAsserted: true));
  final models = <String>{};
  for (final reference in references) {
    if (reference.family != family ||
        reference.brand.toLowerCase() != brand.trim().toLowerCase()) continue;
    final candidate = ProductIdentityExtractor.extract(ProductIdentityInput(
        name: family == 'chain_link'
            ? 'Conector de cadena ${reference.brand} ${reference.model}'
            : 'Cadena ${reference.brand} ${reference.model}',
        modelHint: reference.model));
    if (candidate.modelCodes.isNotEmpty &&
        identity.modelCodes.containsAll(candidate.modelCodes)) {
      models.add(reference.model);
    }
  }
  return models.toList()..sort();
}

String productSpecClaimSummary(Map<String, dynamic> claim) {
  if (claim['schema_version'] == 2) {
    final relation = ProductSpecRelation.fromJson(claim);
    final alternatives =
        relation.alternatives.map((row) => row.label).join(' o ');
    final exclusions = relation.exclusions.map((row) => row.label).join('; ');
    return '${relation.label}: $alternatives${exclusions.isEmpty ? '' : '. Excluye: $exclusions'}';
  }
  if (claim['interface'] == 'connector_chain') {
    final targets = (claim['targets'] as List? ?? []).join(', ');
    final excluded = (claim['excludes'] as List? ?? []).join(', ');
    return 'Cadenas admitidas: $targets${excluded.isEmpty ? '' : '. Excluye: $excluded'}';
  }
  final system = claim['coverage'] ??
      claim['platform'] ??
      (claim['systems'] as List? ?? []).join(', ');
  final speeds = (claim['rear_speeds'] as List? ?? []).join('/');
  return '$system${speeds.isEmpty ? '' : ' · $speeds velocidades'}';
}

class ProductSpecIssue {
  const ProductSpecIssue(this.code, this.fieldKey, this.message,
      {this.blocking = true, this.rowId, this.columnKey});

  final String code;
  final String fieldKey;
  final String message;
  final bool blocking;
  final String? rowId;
  final String? columnKey;
}

List<ProductSpecIssue> productSpecServerIssues(Object? details) {
  if (details is String) {
    try {
      details = jsonDecode(details);
    } on FormatException {
      return const [];
    }
  }
  if (details is! List) return const [];
  return [
    for (final issue in details)
      if (issue is Map &&
          issue['code'] is String &&
          issue['field'] is String &&
          issue['message'] is String)
        ProductSpecIssue(issue['code'] as String, issue['field'] as String,
            issue['message'] as String,
            blocking: issue['blocking'] != false,
            rowId: issue['row_id'] is String ? issue['row_id'] as String : null,
            columnKey:
                issue['column'] is String ? issue['column'] as String : null),
  ];
}

String productSpecIssueMessage(ProductSpecIssue issue, SpecTemplate? template,
    Map<String, dynamic> values) {
  final label = template?.labelFor(issue.fieldKey) ?? issue.fieldKey;
  var location = '';
  final rows = values[issue.fieldKey];
  if (issue.rowId != null && rows is Map && rows['rows'] is List) {
    final index = (rows['rows'] as List)
        .indexWhere((row) => row is Map && row['id'] == issue.rowId);
    if (index >= 0) location = ' · configuración ${index + 1}';
  }
  return label.isEmpty ? issue.message : '$label$location: ${issue.message}';
}

/// An immutable manufacturer reference, explicitly chosen for this product.
/// Its fact map is decoded from the server's normalized option IDs, not guessed
/// from the product name. A new catalogue edition gets a new ID.
class ProductSpecReference {
  const ProductSpecReference({
    required this.id,
    required this.family,
    required this.brand,
    required this.model,
    required this.label,
    required this.facts,
    required this.sources,
    this.manufacturerSku,
    this.claims = const [],
  });

  final String id;
  final String family;
  final String brand;
  final String model;
  final String label;
  final String? manufacturerSku;
  final Map<String, dynamic> facts;
  final List<String> sources;
  final List<Map<String, dynamic>> claims;

  factory ProductSpecReference.fromJson(Map<String, dynamic> json) =>
      ProductSpecReference(
        id: json['id'] as String,
        family: json['technical_family'] as String,
        brand: json['brand'] as String,
        model: json['model'] as String,
        label: json['label'] as String,
        manufacturerSku: json['manufacturer_sku'] as String?,
        facts: Map<String, dynamic>.from(json['facts'] as Map? ?? {}),
        sources: List<String>.from(json['sources'] as List? ?? []),
        claims: (json['claims'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
      );

  bool matchesIdentity(
          {required String brand,
          required String model,
          String manufacturerSku = ''}) =>
      this.brand.trim().toLowerCase() == brand.trim().toLowerCase() &&
      this.model.trim().toLowerCase() == model.trim().toLowerCase() &&
      (this.manufacturerSku == null ||
          this.manufacturerSku!.trim().toLowerCase() ==
              manufacturerSku.trim().toLowerCase());
}

/// Central validation runs even when a tab/field has never been built. It does
/// not mutate the draft. Completeness is separate from contradictions: an
/// unfinished, non-contradictory catalogue entry can remain a draft.
List<ProductSpecIssue> validateProductSpecDraft({
  required SpecTemplate template,
  required Map<String, dynamic> values,
  ProductSpecReference? reference,
  String brand = '',
  String model = '',
  String manufacturerSku = '',
}) {
  final issues = <ProductSpecIssue>[];
  final activeKeys = template.fields
      .map((field) => field.definition?.key)
      .whereType<String>()
      .where((key) => template.roleFor(key) != 'legacy')
      .toSet();
  values = Map.fromEntries(
      values.entries.where((entry) => activeKeys.contains(entry.key)));
  Set<String> optionValues(Object? value) =>
      template.formContract['rules_version'] == 2
          ? (value is List ? value : [value])
              .where((v) => v is String || v is bool)
              .map((v) => v.toString())
              .toSet()
          : specRuleValueSet(value);
  if (reference != null) {
    if (reference.family != template.technicalFamily ||
        !reference.matchesIdentity(
            brand: brand, model: model, manufacturerSku: manufacturerSku)) {
      issues.add(const ProductSpecIssue('reference_identity', '',
          'La referencia no corresponde a esta marca, modelo, código de fabricante o familia. Revisa la identidad o retira la referencia.'));
    }
    for (final entry in reference.facts.entries) {
      // An operator's evidence note supplements the reference's own sources.
      if (entry.key == 'spec_evidence_source') continue;
      if (!hasKnownSpecValue(values[entry.key])) continue;
      final definition = template.fields
          .firstWhereOrNull((field) => field.definition?.key == entry.key)
          ?.definition;
      final schema = definition?.rowSchema;
      bool matches;
      if (schema != null) {
        try {
          matches = const DeepCollectionEquality().equals(
              schema.parse(values[entry.key]).toJson(),
              schema.parse(entry.value).toJson());
        } on FormatException {
          matches = false;
        }
      } else if (definition?.dataType == 'number') {
        final actual = productSpecNumber(values[entry.key]);
        final expected = productSpecNumber(entry.value);
        matches = actual != null &&
            expected != null &&
            actual.compareTo(expected) == 0;
      } else if (template.formContract['rules_version'] == 2) {
        matches = const DeepCollectionEquality.unordered()
            .equals(values[entry.key], entry.value);
      } else {
        matches = evaluateSpecCondition({
              'field': entry.key,
              'operator': 'eq',
              'value': entry.value,
            }, values) ==
            SpecTruth.yes;
      }
      if (!matches) {
        issues.add(ProductSpecIssue('reference_conflict', entry.key,
            '${template.labelFor(entry.key)} difiere de la referencia ${reference.label}. Usa sus datos documentados o retira esta referencia.'));
      }
    }
  }
  for (final field in template.fields) {
    final def = field.definition;
    if (def == null || template.roleFor(def.key) == 'legacy') continue;
    final value = values[def.key];
    if (!hasKnownSpecValue(value) &&
        template.applicabilityFor(field, values) == SpecTruth.yes &&
        template.requiredFor(field, values) == SpecTruth.yes) {
      issues.add(ProductSpecIssue('required_missing', def.key,
          '${template.labelFor(def.key)}: falta confirmar este dato.',
          blocking: false));
    }
    if (!hasKnownSpecValue(value)) continue;
    void issue(String code, String message, {bool blocking = true}) =>
        issues.add(ProductSpecIssue(
            code, def.key, '${template.labelFor(def.key)}: $message',
            blocking: blocking));
    if (reference != null &&
        template.roleFor(def.key) == 'declaration' &&
        def.key != 'spec_evidence_source' &&
        !reference.facts.containsKey(def.key)) {
      issue('unsupported_declaration',
          'esta declaración manual no está documentada en la referencia elegida. Usa sus declaraciones o retira la referencia.');
    }
    final applicability = template.applicabilityFor(field, values);
    if (applicability != SpecTruth.yes) {
      issue(
          applicability == SpecTruth.no
              ? 'field_applicability'
              : 'prerequisite',
          applicability == SpecTruth.no
              ? 'este valor no corresponde a los requisitos elegidos. Revísalo o retíralo.'
              : 'falta confirmar sus requisitos.',
          blocking: applicability == SpecTruth.no);
    }
    final prerequisites = template.prerequisitesFor(def.key);
    if (prerequisites.any((key) => !hasKnownSpecValue(values[key]))) {
      issue('prerequisite',
          'falta confirmar ${prerequisites.where((key) => !hasKnownSpecValue(values[key])).map((key) => template.labelFor(key)).join(', ')}.',
          blocking: false);
    }
    if (def.dataType == 'boolean' && value is! bool) {
      issue('type', 'elige Sí, No o Sin dato.');
    } else if (def.dataType == 'number') {
      final error = productSpecNumberErrorCode(value, def.validationRules);
      if (error == 'type') {
        issue('type', 'ingresa un número válido.');
      } else if (error == 'invalid_rules') {
        issue('configuration',
            'no se pudieron validar los límites de este campo.');
      } else if (error == 'min' || error == 'max') {
        issue('range',
            'el valor está fuera del rango declarado para este campo.');
      } else if (error == 'positive') {
        issue('range', 'ingresa un valor mayor que cero.');
      } else if (error == 'integer') {
        issue('integer', 'ingresa una cantidad entera.');
      }
    } else if (def.dataType == 'json') {
      try {
        final ProductSpecRowSchema? schema = def.rowSchema;
        if (schema == null) {
          throw const FormatException('falta el esquema de configuraciones.');
        }
        final rows = schema.parse(value);
        final missing = rows.missingRequired(schema);
        if (missing.isNotEmpty) {
          issue('row_incomplete', 'falta confirmar ${missing.join(', ')}.',
              blocking: false);
        }
      } on FormatException catch (error) {
        issue('row_shape', error.message);
      }
    } else if (def.dataType == 'single_select' ||
        def.dataType == 'multi_select') {
      if (def.dataType == 'single_select' && value is! String ||
          def.dataType == 'multi_select' && value is! List) {
        issue('cardinality',
            'la cantidad de respuestas no corresponde al campo.');
      }
      if (template.formContract['rules_version'] == 2 &&
          value is List &&
          value.any((v) => v is! String)) {
        issue('type', 'cada opción debe conservar su código de texto.');
      }
      if (!optionValues(def.options).containsAll(optionValues(value))) {
        issue('option', 'contiene una opción que ya no pertenece al campo.');
      }
    }
    final allowed = template.constrainedOptionsFor(field, values);
    if (allowed != null && !allowed.containsAll(optionValues(value))) {
      issue(
          'constraint',
          allowed.isEmpty
              ? 'los requisitos elegidos no dejan opciones válidas.'
              : 'el valor no corresponde a los requisitos elegidos.');
    }
  }
  if (template.technicalFamily == 'chain' &&
      reference == null &&
      brand.trim().toLowerCase() == 'kmc' &&
      values['chain_width_family'] == '11/128' &&
      specRuleValueSet(values['chain_speeds'])
          .any((speed) => const {'6', '7', '8'}.contains(speed))) {
    issues.add(const ProductSpecIssue('verify_model', 'chain_width_family',
        'Confirma el modelo KMC y su envase: la referencia X8 consultada declara 6/7/8 y 3/32. Esta combinación de ancho y velocidades requiere otra fuente; el ancho solo no demuestra incompatibilidad.',
        blocking: false));
  }
  try {
    for (final issue in template.rowConditions.validate(values)) {
      final entry = ProductSpecIssue(issue.code, issue.field, issue.message,
          blocking: issue.blocking,
          rowId: issue.rowId,
          columnKey: issue.column);
      issues.add(ProductSpecIssue(entry.code, entry.fieldKey,
          productSpecIssueMessage(entry, template, values),
          blocking: entry.blocking,
          rowId: entry.rowId,
          columnKey: entry.columnKey));
    }
    for (final issue in template.coherence.validate(values)) {
      if (issue.code == 'row_cardinality_pending' &&
          template.fields.any((field) =>
              field.definition?.key == issue.field &&
              template.applicabilityFor(field, values) == SpecTruth.no)) {
        // A collection that does not apply cannot require more investigation.
        // Existing observations still retain their applicability/shape errors.
        continue;
      }
      if (issue.code == 'row_cardinality_conflict' &&
          issues.any((existing) =>
              existing.fieldKey == issue.field &&
              existing.code == 'field_applicability' &&
              existing.blocking)) {
        continue;
      }
      if (issue.code == 'row_cardinality_total' &&
          issues.any((existing) =>
              existing.fieldKey == issue.field &&
              existing.blocking &&
              const {'type', 'integer', 'range', 'configuration'}
                  .contains(existing.code))) {
        continue;
      }
      if (issue.rowId == null &&
          issues.any((existing) =>
              existing.code == issue.code &&
              existing.fieldKey == issue.field)) {
        continue;
      }
      final entry = ProductSpecIssue(issue.code, issue.field, issue.message,
          blocking: issue.blocking,
          rowId: issue.rowId,
          columnKey: issue.column);
      issues.add(ProductSpecIssue(entry.code, entry.fieldKey,
          productSpecIssueMessage(entry, template, values),
          blocking: entry.blocking,
          rowId: entry.rowId,
          columnKey: entry.columnKey));
    }
  } on FormatException catch (error) {
    issues.add(ProductSpecIssue('configuration', '', error.message));
  }
  return issues;
}

/// A stock receipt may refresh its server timestamp only when the editable
/// product and specification revision still match the editor's original base.
bool canRefreshProductEditAfterStockAdjustment(Product before, Product after) {
  Map<String, dynamic> editable(Product product) =>
      product.toJson(includeNulls: true)
        ..remove('inventory_qty')
        ..remove('stock_quantity')
        ..remove('updated_at')
        ..remove('created_at');
  return before.specRevision == after.specRevision &&
      const DeepCollectionEquality().equals(editable(before), editable(after));
}
