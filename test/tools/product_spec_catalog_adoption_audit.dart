// Offline population audit using the same exact decoder/validator as the editor.
// Run explicitly with flutter test and SPEC_ADOPTION_{MANIFEST,CATALOG,OUTPUT}.
// This tool neither assigns templates nor authorizes publication or filling.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_contract.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';

Map<String, dynamic> object(Object? value) =>
    Map<String, dynamic>.from(value as Map);
Map<String, dynamic> readJson(String path) =>
    object(jsonDecode(File(path).readAsStringSync()));
String fileHash(String path) =>
    sha256.convert(File(path).readAsBytesSync()).toString();

Object? exactNumberText(Object? value) {
  if (value is int) return value.toString();
  if (value is num) {
    throw const FormatException(
        'Catalogue decimal operands must be text before the Dart audit.');
  }
  if (value is List) return value.map(exactNumberText).toList();
  if (value is Map) {
    return value.map((key, child) => MapEntry(key, exactNumberText(child)));
  }
  return value;
}

// Project raw metadata exactly like the v2 RPC's
// spec_editor_rule_numbers_as_text_internal_v1. Preserve versions and tokens.
Object? ruleWire(Object? value) {
  if (value is List) return value.map(ruleWire).toList();
  if (value is Map) {
    return value.map((key, child) => MapEntry(
        key,
        const {'min', 'max', 'value', 'allow'}.contains(key)
            ? exactNumberText(child)
            : ruleWire(child)));
  }
  return value;
}

Map<String, dynamic> issueJson(ProductSpecIssue issue) => {
      'code': issue.code,
      'field': issue.fieldKey,
      'blocking': issue.blocking,
      'message': issue.message,
      if (issue.rowId != null) 'row_id': issue.rowId,
      if (issue.columnKey != null) 'column': issue.columnKey,
      if (issue.collectionFieldKey != null)
        'collection_field': issue.collectionFieldKey,
    };

SpecTemplate proposedTemplate(Map<String, dynamic> template,
    Map<String, dynamic> definitions, Map<String, dynamic> editor) {
  // Reuse the real exact-transport parser, including its metadata checks.
  final raw = <String, dynamic>{
    ...template,
    'contract_version': (editor['contract_version'] as int) + 1,
    'form_contract': ruleWire(template['form_contract']),
    'fields': [
      for (final field in template['fields'] as List)
        {
          ...object(field),
          'spec_definition_id': definitions[field['key']]['id'],
          'visibility_rules': ruleWire(field['visibility_rules']),
          'option_rules': ruleWire(field['option_rules']),
          'constraint_rules': ruleWire(field['constraint_rules']),
          'spec_definitions': {
            ...object(definitions[field['key']]),
            'validation_rules':
                ruleWire(definitions[field['key']]['validation_rules']),
          },
        }
    ]
  };
  return SpecEngineService.decodeProductSpecEditorContext({
    ...editor,
    'template': raw,
    'contract_version': raw['contract_version'],
  }).template!;
}

void main() {
  const manifestPath = String.fromEnvironment('SPEC_ADOPTION_MANIFEST');
  const catalogPath = String.fromEnvironment('SPEC_ADOPTION_CATALOG');
  const outputPath = String.fromEnvironment('SPEC_ADOPTION_OUTPUT');
  if ([manifestPath, catalogPath, outputPath].any((path) => path.isEmpty)) {
    test('catalogue adoption audit requires explicit inputs', () {},
        skip: 'Diagnostic tool: pass all three SPEC_ADOPTION paths.');
    return;
  }
  test('evaluate every captured product against proposed metadata', () {
    expect(File(outputPath).existsSync(), isFalse,
        reason: 'Keep earlier audit evidence immutable.');
    final manifest = readJson(manifestPath);
    final catalog = readJson(catalogPath);
    final definitions = object(catalog['definitions']);
    final templates = {
      for (final template in catalog['templates'] as List)
        template['id'] as String: object(template)
    };
    expect(manifest['errors'], isEmpty);
    expect(manifest['writes'], 0);
    final snapshots = manifest['snapshots'] as List;
    expect(snapshots.length, manifest['expected_products']);
    expect(
        snapshots.map((s) => s['product_id']).toSet().length, snapshots.length);
    final families = <String, Map<String, dynamic>>{
      for (final template in templates.values)
        template['key']: {
          'template_id': template['id'],
          'origin': template['origin'],
          'products_evaluated': 0,
          'products_with_blocking_issues': 0,
          'products_with_pending_issues': 0,
          'legacy_observations': 0,
          'unprojected_active_observations': 0,
        }
    };
    final products = <Map<String, dynamic>>[];
    final directory = File(manifestPath).parent.path;
    for (final rawEntry in snapshots) {
      final entry = object(rawEntry);
      final path = '$directory/${entry['file']}';
      expect(fileHash(path), entry['file_sha256']);
      final capture = readJson(path);
      final snapshot = object(capture['snapshot']);
      final snapshotBefore = jsonEncode(snapshot);
      expect(snapshot['snapshot_sha256'], entry['snapshot_sha256']);
      expect(snapshot['actor_id'], manifest['actor_id']);
      expect(capture['project'], manifest['project']);
      final product = object(snapshot['product']);
      final editor = object(snapshot['editor']);
      expect(product['id'], entry['product_id']);
      expect(editor['product_id'], product['id']);
      expect(editor['revision'], product['spec_revision']);
      final current =
          SpecEngineService.decodeProductSpecEditorContext(editor).template;
      final result = <String, dynamic>{
        'id': product['id'],
        'name': product['name'],
        'sku': product['sku'],
        'product_type': product['product_type'],
        'is_active': product['is_active'],
        'snapshot_sha256': snapshot['snapshot_sha256'],
        'captured_at': capture['captured_at'],
        'template_key': current?.key,
        'template_id': current?.id,
        'spec_revision': product['spec_revision'],
        'existing_observations': (snapshot['observations'] as List).length,
      };
      if (current == null) {
        result['status'] = 'assignment_review_required';
        products.add(result);
        continue;
      }
      final proposal = templates[current.id];
      expect(proposal, isNotNull,
          reason:
              'A currently bound template cannot disappear from the proposal.');
      expect(proposal!['key'], current.key);
      expect(proposal['technical_family'], current.technicalFamily);
      final target = proposedTemplate(proposal, definitions, editor);
      final values = object(editor['values']);
      ProductSpecReference? reference;
      if (editor['reference_id'] != null) {
        final matches = (snapshot['references'] as List)
            .where((r) => r['id'] == editor['reference_id'])
            .toList();
        expect(matches, hasLength(1));
        reference = ProductSpecReference.fromJson(object(matches.single));
      }
      List<ProductSpecIssue> evaluate(SpecTemplate template) =>
          validateProductSpecDraft(
              template: template,
              values: values,
              reference: reference,
              brand: product['brand'] as String? ?? '',
              model: product['model'] as String? ?? '',
              manufacturerSku: product['manufacturer_sku'] as String? ?? '');
      final beforeIssues = evaluate(current);
      final afterIssues = evaluate(target);
      final retainedLegacy = <Map<String, dynamic>>[];
      final unprojected = <Map<String, dynamic>>[];
      final activeKeys = target.fields
          .map((f) => f.definition!.key)
          .where((key) => target.roleFor(key) != 'legacy')
          .toSet();
      for (final observation in snapshot['observations'] as List) {
        final key = observation['definition']['key'] as String;
        final fact = object(observation['fact']);
        final summary = {
          'fact_id': fact['id'],
          'key': key,
          'scope': fact['subject_scope'],
          'fact_sha256': observation['fact_sha256'],
        };
        if (!activeKeys.contains(key)) {
          retainedLegacy.add(summary);
        } else if (fact['subject_scope'] != null || !values.containsKey(key)) {
          // Never manufacture a value by guessing a label for an old option ID.
          unprojected.add(summary);
        }
      }
      final blocking = afterIssues.where((issue) => issue.blocking).length;
      final pending = afterIssues.length - blocking;
      result.addAll({
        'status': blocking > 0 || unprojected.isNotEmpty
            ? 'population_review_required'
            : 'no_population_conflict_detected',
        'current_issues': beforeIssues.map(issueJson).toList(),
        'proposed_issues': afterIssues.map(issueJson).toList(),
        'retained_legacy_observations': retainedLegacy,
        'unprojected_active_observations': unprojected,
      });
      final family = families[current.key]!;
      family['products_evaluated'] += 1;
      family['products_with_blocking_issues'] += blocking > 0 ? 1 : 0;
      family['products_with_pending_issues'] += pending > 0 ? 1 : 0;
      family['legacy_observations'] += retainedLegacy.length;
      family['unprojected_active_observations'] += unprojected.length;
      expect(jsonEncode(snapshot), snapshotBefore,
          reason:
              'Audit cannot rewrite current observations or their sources.');
      products.add(result);
    }
    final report = {
      'schema_version': 1,
      'catalog_sha256': fileHash(catalogPath),
      'manifest_sha256': fileHash(manifestPath),
      'project': manifest['project'],
      'actor_id': manifest['actor_id'],
      'products': products,
      'families': families,
      'writes': 0,
      'publication_authorized': false,
      'fill_authorized': false,
      'limitations': [
        'Tests current assignments only; nominal candidates are not assigned.',
        'Each product has its own MVCC preimage; publication needs fresh drift guards.',
        'Source assertions and actual mechanical compatibility are not certified.',
        'No legacy value is converted or deleted; retained history needs consumer review.',
        'Simulated contract version is only a decoder input, not a publication revision.',
      ],
    };
    File(outputPath).writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n');
    // Print only aggregate findings; full per-product evidence stays in the artifact.
    print(jsonEncode({
      'products': products.length,
      'evaluated': products.where((p) => p['template_id'] != null).length,
      'population_review_required': products
          .where((p) => p['status'] == 'population_review_required')
          .length,
      'assignment_review_required': products
          .where((p) => p['status'] == 'assignment_review_required')
          .length,
      'output': outputPath,
      'writes': 0,
    }));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
