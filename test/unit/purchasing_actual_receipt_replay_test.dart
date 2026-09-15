import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';

import 'purchasing_independent_review_test.dart' as qa;

void main() {
  test('the original ten real RBX rows survive a truthful local rejudge', () {
    final fixture = jsonDecode(File(
      'test/fixtures/purchasing/purchasing-holdout-rbx-original-receipt.json',
    ).readAsStringSync()) as Map<String, dynamic>;
    final request = fixture['request'] as Map<String, dynamic>;
    final fields = (fixture['fields'] as List).map((raw) {
      final field = Map<String, dynamic>.from(raw as Map);
      return SupplierNeedSearchField(
        key: field['key'] as String, label: field['label'] as String,
        dataType: field['data_type'] as String, unit: field['unit'] as String?,
        description: field['description'] as String?,
        allowedValues: (field['allowed_values'] as List).cast<Object>(),
        validationRules: Map<String, Object?>.from(field['validation_rules'] as Map),
        isRequired: field['is_required'] == true,
      );
    }).toList();
    final predicates = (request['predicates'] as List).map((raw) =>
      SupplierNeedSearchPredicate(field: raw['field'] as String,
        operator: raw['operator'] as String,
        values: (raw['values'] as List).cast<Object>()),
    ).toList();
    final plan = buildSupplierNeedSearchPlan(
      request: SupplierNeedSearchRequest(
        needId: fixture['source']['needId'] as String,
        description: request['description'] as String,
        categoryId: request['categoryId'] as String,
        categoryPath: request['categoryPath'] as String,
        technicalFamily: request['technicalFamily'] as String,
        fields: fields, predicates: predicates,
      ),
      adapter: qa.planFor('Pastillas').adapter, maxLength: 20,
    )!;
    final candidates = (fixture['matches'] as List).map((raw) =>
        SupplierPortalCatalogCandidate.fromJson(Map<String, dynamic>.from(raw as Map)),
      ).toList();
    final matches = matchSupplierNeedCandidates(plan, candidates);
    expect(matches, hasLength(10));
    expect(matches.where((row) => row.state == SupplierNeedMatchState.exact), isEmpty);
    expect(matches.where((row) => row.conflictingFields.contains('product_family')), isEmpty,
      reason: 'las diez filas reales nombran pastillas, no otra pieza');
    // The inferred scalar may remain for audit; it must not PROVE hydraulic.
    // A simple description isolates that property from the BR-MT200 guard.
    final hydraulicPlan = buildSupplierNeedSearchPlan(
      request: SupplierNeedSearchRequest(needId: 'same-receipt-isolated-property',
        description: 'Pastillas de freno',
        categoryId: request['categoryId'] as String,
        categoryPath: request['categoryPath'] as String,
        technicalFamily: request['technicalFamily'] as String,
        fields: fields, predicates: const [
          SupplierNeedSearchPredicate(field: 'brake_type', operator: 'eq',
            values: ['Disco Hidráulico']),
        ]),
      adapter: plan.adapter, maxLength: 20,
    )!;
    final hydraulicRows = matchSupplierNeedCandidates(hydraulicPlan, candidates);
    expect(hydraulicRows.where((row) => row.provenFields.contains('brake_type')), isEmpty,
      reason: 'ninguno de los textos del recibo demuestra hidráulico');

    List<SupplierNeedMatchVerdict> preview(List<SupplierNeedSearchPredicate> criteria) =>
      judgeSupplierNeedMatchesUnder(matches: matches, predicates: criteria, fields: fields);
    final original = preview(predicates);
    final changed = preview([
      for (final predicate in predicates)
        if (predicate.field == 'brake_system')
          const SupplierNeedSearchPredicate(field: 'brake_system', operator: 'eq', values: ['Tektro'])
        else predicate,
    ]);
    final cleared = preview([]);
    final originalIds = original.map((row) => row.match.candidate.code).toList();
    final changedIds = changed.map((row) => row.match.candidate.code).toList();
    expect(originalIds.toSet(), {
      for (final match in matches)
        if (match.state != SupplierNeedMatchState.conflict) match.candidate.code,
    }, reason: 'la misma ficha y los mismos datos deben dar las mismas filas en lista y preview');
    // Do not turn the row's maker into an independent fitment oracle.
    // The original AI scalars are precisely the assertions under review.
    // Synthetic typed-evidence tests cover the selector's positive/negative
    // transitions; these real sets are recorded and checked against evidence.
    final sourceIds = candidates.map((row) => row.code).toSet();
    expect(sourceIds.containsAll(originalIds), isTrue);
    expect(sourceIds.containsAll(changedIds), isTrue);
    expect(cleared, hasLength(10));
    for (final view in [original, changed, cleared]) {
      expect(view.where((row) => row.isConfirmed), isEmpty,
        reason: 'ninguna fila demuestra BR-MT200, resina y sin aletas');
    }
    // Evidence-only output: names and judgments, never credentials or headers.
    printOnFailure(jsonEncode({
      'originalCodes': originalIds, 'tektroCodes': changedIds,
      'clearedCodes': cleared.map((row) => row.match.candidate.code).toList(),
      'rows': [for (final row in matches) {
        'code': row.candidate.code, 'name': row.candidate.name,
        'state': row.state.name, 'proven': row.provenFields,
        'missing': row.missingFields, 'conflicts': row.conflictingFields,
        'observed': row.observedFacts,
      }],
    }));
  });
}
