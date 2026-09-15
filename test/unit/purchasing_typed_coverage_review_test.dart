import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'package:vinabike_erp/shared/services/supplier_spec_extraction.dart';
import 'purchasing_independent_review_test.dart' as qa;

void main() {
  test('requirements already expressed by typed criteria are not invented again', () {
    const fields = [
      SupplierNeedSearchField(key: 'brake_system', label: 'Sistema de Freno',
        dataType: 'single_select', allowedValues: ['Shimano', 'Tektro']),
      SupplierNeedSearchField(key: 'compound_type', label: 'Compuesto',
        dataType: 'single_select', allowedValues: ['Orgánico', 'Metálico', 'Semi-Metálico']),
      SupplierNeedSearchField(key: 'pad_finned', label: 'Con Aletas de Calor',
        dataType: 'boolean'),
    ];
    const predicates = [
      SupplierNeedSearchPredicate(field: 'brake_system', operator: 'eq', values: ['Shimano']),
      SupplierNeedSearchPredicate(field: 'compound_type', operator: 'eq', values: ['Orgánico']),
      SupplierNeedSearchPredicate(field: 'pad_finned', operator: 'eq', values: [false]),
    ];
    final plan = buildSupplierNeedSearchPlan(
      request: const SupplierNeedSearchRequest(needId: 'typed-semantic-coverage',
        description: 'Pastillas para frenos Shimano BR-MT200, de resina y sin aletas de refrigeración',
        categoryId: 'brake-pads', categoryPath: 'Componentes / Frenos / Pastillas',
        technicalFamily: 'brake_pad', fields: fields, predicates: predicates),
      adapter: qa.planFor('Pastillas').adapter, maxLength: 20,
    )!;
    final match = matchSupplierNeedCandidates(plan, [
      const SupplierPortalCatalogCandidate(code: 'synthetic-full-fit',
        name: 'PASTILLA ORGANICA PARA FRENOS SHIMANO BR-MT200 SIN ALETAS',
        rowText: 'PASTILLA ORGANICA PARA FRENOS SHIMANO BR-MT200 SIN ALETAS',
        priceNet: 1000,
        technicalFacts: {
          'brake_system': 'Shimano', 'compound_type': 'Orgánico', 'pad_finned': false,
          kSupplierObjectHeadFact: 'PASTILLA',
          kSupplierFactQuotesFact: {'brake_system': 'PARA FRENOS SHIMANO',
            'compound_type': 'ORGANICA', 'pad_finned': 'SIN ALETAS'},
        }),
    ]).single;
    expect(match.provenFields, containsAll([
      'brake_system', 'compound_type', 'pad_finned', kCompatibilityRequirementField,
    ]));
    expect(match.state, SupplierNeedMatchState.exact,
      reason: 'resina/Orgánico y sin aletas de refrigeración ya están expresados por la ficha; no son exigencias extra');
  });
}
