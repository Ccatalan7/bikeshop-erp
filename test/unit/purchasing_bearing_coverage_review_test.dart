import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'package:vinabike_erp/shared/services/supplier_spec_extraction.dart';
import 'purchasing_independent_review_test.dart' as qa;

void main() {
  final plan = buildSupplierNeedSearchPlan(
    request: const SupplierNeedSearchRequest(
      needId: 'bearing-requirement-coverage',
      description: 'Rodamientos sellados 15 × 28 × 7 mm para mazas con sello de goma a ambos lados (6902 2RS)',
      categoryId: '407c429d-4e24-4744-8189-441cf865dc05',
      categoryPath: 'Componentes / Ruedas / Rodamientos', technicalFamily: 'bearing',
      fields: [
        SupplierNeedSearchField(key: 'bearing_application', label: 'Aplicación del Rodamiento',
          dataType: 'single_select', allowedValues: ['Maza', 'Dirección', 'Pedalier', 'Otro'], isRequired: true),
        SupplierNeedSearchField(key: 'bearing_size_code', label: 'Código rodamiento',
          dataType: 'text', isRequired: true),
      ],
      predicates: [
        SupplierNeedSearchPredicate(field: 'bearing_application', operator: 'eq', values: ['Maza']),
        SupplierNeedSearchPredicate(field: 'bearing_size_code', operator: 'eq', values: ['6902']),
      ],
    ),
    adapter: qa.planFor('Pastillas').adapter, maxLength: 20,
  )!;

  for (final entry in <String, Map<String, Object>>{
    'a missing sealing claim stays pending': {
      'row': 'RODAMIENTO PARA MAZA 6902 15 X 28 X 7 MM', 'exact': false,
    },
    'one-sided sealing does not meet both sides': {
      'row': 'RODAMIENTO PARA MAZA 6902 15 X 28 X 7 MM SELLO DE GOMA EN UN SOLO LADO', 'exact': false,
    },
    'literal proof of every requirement can be confirmed': {
      'row': 'RODAMIENTO SELLADO PARA MAZA 6902 15 X 28 X 7 MM CON SELLOS DE GOMA EN AMBOS LADOS', 'exact': true,
    },
  }.entries) {
    test(entry.key, () {
      final match = matchSupplierNeedCandidates(plan, [
        SupplierPortalCatalogCandidate(code: 'synthetic-coverage-control',
          name: entry.value['row'] as String, rowText: entry.value['row'] as String, priceNet: 1000,
          technicalFacts: const {
            'bearing_application': 'Maza', 'bearing_size_code': '6902',
            kSupplierObjectHeadFact: 'RODAMIENTO',
            // Isolate the unrepresented requirement: the two known fields
            // have positive source evidence, not an old unsupported scalar.
            kSupplierFactQuotesFact: {'bearing_application': 'MAZA', 'bearing_size_code': '6902'},
          }),
      ]).single;
      expect(match.provenFields, containsAll(['bearing_application', 'bearing_size_code']));
      expect(match.state, entry.value['exact'] == true
          ? SupplierNeedMatchState.exact : isNot(SupplierNeedMatchState.exact),
        reason: 'no alcanza con detectar SIN SELLOS: hay que comprobar todo el requisito');
      final preview = judgeSupplierNeedMatchesUnder(matches: [match],
        predicates: plan.request.predicates, fields: plan.request.fields);
      expect(preview.where((row) => row.isConfirmed),
        entry.value['exact'] == true ? hasLength(1) : isEmpty);
    });
  }

  test('an additional criterion cannot consume an unrelated requirement', () {
    // The operator can select Maza in Criterios without rewriting the need.
    // Its absence from the original wording is not evidence that "sellados"
    // means Maza, and cannot erase the sealing requirement.
    final withSelectedApplication = buildSupplierNeedSearchPlan(
      request: SupplierNeedSearchRequest(needId: 'criterion-does-not-consume-seal',
        description: 'Rodamientos 6902 sellados',
        categoryId: plan.request.categoryId, categoryPath: plan.request.categoryPath,
        technicalFamily: plan.request.technicalFamily,
        // A display label need not repeat the object name. Changing that
        // label cannot establish a semantic link between Maza and sellados.
        fields: [
          const SupplierNeedSearchField(key: 'bearing_application', label: 'Aplicación',
            dataType: 'single_select', allowedValues: ['Maza', 'Dirección', 'Pedalier', 'Otro']),
          plan.request.fields.singleWhere((field) => field.key == 'bearing_size_code'),
        ], predicates: plan.request.predicates),
      adapter: plan.adapter, maxLength: 20,
    )!;
    final row = matchSupplierNeedCandidates(withSelectedApplication, [
      const SupplierPortalCatalogCandidate(code: 'synthetic-open-bearing',
        name: 'RODAMIENTO PARA MAZA 6902 ABIERTO SIN SELLOS',
        rowText: 'RODAMIENTO PARA MAZA 6902 ABIERTO SIN SELLOS', priceNet: 1000,
        technicalFacts: {'bearing_application': 'Maza', 'bearing_size_code': '6902',
          kSupplierObjectHeadFact: 'RODAMIENTO',
          kSupplierFactQuotesFact: {'bearing_application': 'MAZA', 'bearing_size_code': '6902'}},
      ),
    ]).single;
    expect(row.state, isNot(SupplierNeedMatchState.exact),
      reason: 'un criterio agregado no autoriza borrar una exigencia de sellado sin relación');
  });
}
