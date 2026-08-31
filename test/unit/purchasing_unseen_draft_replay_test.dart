import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/services/supply_need_effective_criteria.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'package:vinabike_erp/shared/services/supplier_spec_extraction.dart';

// The requests and template definitions were captured before any change for
// these cases. Only the candidate rows below are synthetic counterexamples.
Map<String, dynamic> _observedCase(String categoryId) {
  final fixture = jsonDecode(File(
    'test/fixtures/purchasing/unseen_need_drafts_20260831.json',
  ).readAsStringSync()) as Map<String, dynamic>;
  return (fixture['cases'] as List)
      .cast<Map<String, dynamic>>()
      .singleWhere((entry) => entry['draft']['categoryId'] == categoryId);
}

SupplierNeedSearchPlan _plan(
  String categoryId, {
  List<Map<String, Object?>> discoveries = const <Map<String, Object?>>[],
}) {
  final observed = _observedCase(categoryId);
  final draft = observed['draft'] as Map<String, dynamic>;
  final fields = <SupplierNeedSearchField>[
    for (final raw in (observed['fields'] as List).cast<Map<String, dynamic>>())
      SupplierNeedSearchField(
        key: raw['field'] as String,
        label: raw['label'] as String,
        dataType: raw['data_type'] as String,
        unit: raw['unit'] as String?,
        description: raw['description'] as String?,
        allowedValues: (raw['allowed_values'] as List).cast<Object>(),
      ),
  ];
  final stored = SupplyNeedCriteria(
    categoryId: categoryId,
    categoryPath: draft['categoryPath'] as String?,
    technicalFamily: draft['technicalFamily'] as String?,
    revisionNo: 1,
    predicates: <SupplyNeedPredicate>[
      for (final raw in (draft['technicalPredicates'] as List)
          .cast<Map<String, dynamic>>())
        SupplyNeedPredicate(
          field: raw['field'] as String,
          operator: raw['operator'] as String,
          values: (raw['values'] as List).cast<Object>(),
        ),
    ],
  );
  final effective = effectiveSupplyNeedCriteria(
    stored: stored,
    texts: <String>[draft['description'] as String],
    fields: fields,
    templateTechnicalFamily: draft['technicalFamily'] as String?,
  );
  final plan = buildSupplierNeedSearchPlan(
    request: SupplierNeedSearchRequest(
      needId: observed['runId'] as String,
      description: draft['description'] as String,
      categoryId: categoryId,
      categoryPath: draft['categoryPath'] as String?,
      technicalFamily: draft['technicalFamily'] as String?,
      fields: fields,
      discoveredRequirements: verifySupplyNeedDiscoveredRequirements(
        requestText: draft['description'] as String,
        response: <String, Object?>{'requirements': discoveries},
      ),
      predicates: <SupplierNeedSearchPredicate>[
        for (final predicate in effective.predicates)
          SupplierNeedSearchPredicate(
            field: predicate.field,
            operator: predicate.operator,
            values: predicate.values,
          ),
      ],
    ),
    adapter: SupplierNeedPortalAdapter.fromJson(<String, dynamic>{
      'version': 1,
      'generic_family_search': true,
      'result_schema': <String, dynamic>{},
    }),
    maxLength: 40,
  );
  expect(plan, isNotNull,
      reason: 'a recognized category must not lose search because it has no '
          'technical template');
  return plan!;
}

SupplierNeedPortalMatch _match(SupplierNeedSearchPlan plan, String text) =>
    matchSupplierNeedCandidates(plan, <SupplierPortalCatalogCandidate>[
      SupplierPortalCatalogCandidate(
        code: 'synthetic-counterexample',
        name: text,
        rowText: text,
        priceNet: 1000,
      ),
    ]).single;

void main() {
  test('discovery and deterministic union retain a complete freewheel match',
      () {
    final plan = _plan('4ddce44d-f508-41de-9325-b92b39f8eb64', discoveries: [
      {'quote': '3/32', 'required': true, 'scope': <String>[]},
      {'quote': 'no cassette', 'required': false, 'scope': <String>[]},
    ]);
    final match = _match(
        plan, 'PIÑON ROSCADO 7 VELOCIDADES PARA CADENA 3/32 (NO CASSETTE)');
    expect(match.state, SupplierNeedMatchState.exact);
    final readerPrompt = buildSupplierRequirementReadingPrompt(
      rows: const <SupplierSpecExtractionRow>[
        SupplierSpecExtractionRow(id: 'fraction', text: 'PIÑON SIN MEDIDA'),
      ],
      requirements: supplyNeedUnmodelledRequirements(plan),
    );
    expect(readerPrompt, contains('3/32'),
        reason: 'the supplier reader must receive the whole dimension, not 3');
  });

  test('discovery and deterministic union retain complete grip evidence', () {
    final plan = _plan('c5c50c6d-6fb0-4e29-a0ec-3cfb026cb487', discoveries: [
      {
        'quote': 'fijación por doble abrazadera',
        'required': true,
        'scope': <String>['doble'],
      },
      {'quote': 'de goma', 'required': true, 'scope': <String>[]},
      {'quote': 'sin tapones', 'required': false, 'scope': <String>[]},
    ]);
    final match = _match(
        plan, 'PUÑOS CON FIJACIÓN POR DOBLE ABRAZADERA, DE GOMA Y SIN TAPONES');
    expect(match.requirementFindings, isNotEmpty);
    expect(match.requirementFindings.map((finding) => finding.status),
        everyElement(SupplyRequirementStatus.proven));
  });

  test('discovery and deterministic union retain complete rotor evidence', () {
    final plan = _plan('5bbe2944-5355-40a5-a581-70790a525579', discoveries: [
      {
        'quote': 'de una sola pieza',
        'required': true,
        'scope': <String>['una', 'sola'],
      },
      {'quote': 'no Center Lock', 'required': false, 'scope': <String>[]},
    ]);
    final match = _match(plan,
        'DISCO DE FRENO 180 MM 6 PERNOS DE UNA SOLA PIEZA (NO CENTER LOCK)');
    expect(match.state, SupplierNeedMatchState.exact);
  });

  test('complete literal freewheel evidence still has a positive path', () {
    final plan = _plan('4ddce44d-f508-41de-9325-b92b39f8eb64');
    final match = _match(
        plan, 'PIÑON ROSCADO 7 VELOCIDADES PARA CADENA 3/32 (NO CASSETTE)');
    expect(match.state, SupplierNeedMatchState.exact,
        reason: 'preserving a requirement must not reject its direct proof');
  });

  test('complete literal rotor evidence still has a positive path', () {
    final plan = _plan('5bbe2944-5355-40a5-a581-70790a525579');
    final match = _match(plan,
        'DISCO DE FRENO 180 MM 6 PERNOS DE UNA SOLA PIEZA (NO CENTER LOCK)');
    expect(match.state, SupplierNeedMatchState.exact,
        reason:
            'this is the requested object and explicitly states every condition');
  });

  test('a no-template request can acknowledge its own complete literal proof',
      () {
    final plan = _plan('c5c50c6d-6fb0-4e29-a0ec-3cfb026cb487');
    final match = _match(
        plan, 'PUÑOS CON FIJACIÓN POR DOBLE ABRAZADERA, DE GOMA Y SIN TAPONES');
    expect(match.state, isNot(SupplierNeedMatchState.conflict));
    expect(match.requirementFindings, isNotEmpty);
    expect(match.requirementFindings.map((finding) => finding.status),
        everyElement(SupplyRequirementStatus.proven),
        reason: 'every requirement is repeated verbatim; none is inferred');
  });

  final observedRows = (jsonDecode(File(
    'test/fixtures/purchasing/unseen_freewheel_catalog_samples_20260831.json',
  ).readAsStringSync()) as Map<String, dynamic>)['rows'] as List;
  for (final row in observedRows.cast<Map<String, dynamic>>()) {
    if (!<String>{'S61433', '21525'}.contains(row['sku'])) continue;
    test('real catalog cassette ${row['sku']} cannot satisfy no cassette', () {
      final plan = _plan('4ddce44d-f508-41de-9325-b92b39f8eb64');
      final match = _match(plan, row['name'] as String);
      expect(match.state, SupplierNeedMatchState.conflict,
          reason: '${row['name']} explicitly names the excluded mechanism');
    });
  }

  test('the real grip draft sends rubber and double-clamp scope to the reader',
      () {
    final plan = _plan('c5c50c6d-6fb0-4e29-a0ec-3cfb026cb487');
    final prompt = buildSupplierRequirementReadingPrompt(
      rows: const <SupplierSpecExtractionRow>[
        SupplierSpecExtractionRow(id: 'test', text: 'PUÑOS CON ABRAZADERA'),
      ],
      requirements: supplyNeedUnmodelledRequirements(plan),
    );
    expect(prompt.toLowerCase(), contains('goma'),
        reason: 'a missing template must not remove a four-letter material');
    expect(prompt.toLowerCase(), contains('doble'),
        reason: 'one clamp and a double clamp do not satisfy the same need');
  });

  test('an explicitly excluded cassette cannot survive the freewheel request',
      () {
    final plan = _plan('4ddce44d-f508-41de-9325-b92b39f8eb64');
    final match = _match(plan, 'CASSETTE 7 VELOCIDADES PARA CADENA 3/32');
    expect(match.state, SupplierNeedMatchState.conflict,
        reason: 'the real request explicitly says no cassette');
  });

  test('a freewheel cannot confirm an incompatible chain width', () {
    final plan = _plan('4ddce44d-f508-41de-9325-b92b39f8eb64');
    final match = _match(plan, 'PIÑON ROSCADO 7 VELOCIDADES PARA CADENA 1/8');
    expect(match.state, isNot(SupplierNeedMatchState.exact),
        reason: 'seven speeds alone cannot prove the requested 3/32 width');
  });

  test('a two-piece rotor is not proven by diameter and mounting alone', () {
    final plan = _plan('5bbe2944-5355-40a5-a581-70790a525579');
    final match = _match(plan, 'DISCO DE FRENO 180 MM 6 PERNOS DE DOS PIEZAS');
    expect(match.state, isNot(SupplierNeedMatchState.exact),
        reason: 'the original one-piece requirement is still part of the need');
  });
}
