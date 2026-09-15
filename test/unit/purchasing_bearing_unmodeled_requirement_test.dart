import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'package:vinabike_erp/shared/services/supplier_spec_extraction.dart';

import 'purchasing_independent_review_test.dart' as qa;

void main() {
  test('a requirement missing from the template is not automatically met', () {
    final plan = buildSupplierNeedSearchPlan(
      request: const SupplierNeedSearchRequest(
        needId: 'bearing-holdout-draft-not-saved',
        description: 'Rodamientos sellados 15 × 28 × 7 mm para mazas con sello de goma a ambos lados (6902 2RS)',
        categoryId: '407c429d-4e24-4744-8189-441cf865dc05',
        categoryPath: 'Componentes / Ruedas / Rodamientos',
        technicalFamily: 'bearing',
        fields: [
          SupplierNeedSearchField(key: 'bearing_application',
            label: 'Aplicación del Rodamiento', dataType: 'single_select',
            allowedValues: ['Maza', 'Dirección', 'Pedalier', 'Otro'],
            isRequired: true),
          SupplierNeedSearchField(key: 'bearing_size_code',
            label: 'Código rodamiento', dataType: 'text', isRequired: true),
        ],
        predicates: [
          SupplierNeedSearchPredicate(field: 'bearing_application',
            operator: 'eq', values: ['Maza']),
          SupplierNeedSearchPredicate(field: 'bearing_size_code',
            operator: 'eq', values: ['6902']),
        ],
      ),
      adapter: qa.planFor('Pastillas').adapter,
      maxLength: 20,
    )!;
    const name = 'RODAMIENTO PARA MAZA 6902 15 X 28 X 7 MM ABIERTO SIN SELLOS';
    final match = matchSupplierNeedCandidates(plan, [
      const SupplierPortalCatalogCandidate(code: 'synthetic-open-bearing',
        name: name, rowText: name, priceNet: 1000,
        technicalFacts: {
          'bearing_application': 'Maza', 'bearing_size_code': '6902',
          kSupplierObjectHeadFact: 'RODAMIENTO',
        }),
    ]).single;
    expect(match.state, isNot(SupplierNeedMatchState.exact),
      reason: 'el pedido exige sellos de goma a ambos lados aunque la ficha no tenga ese campo');
  });
}
