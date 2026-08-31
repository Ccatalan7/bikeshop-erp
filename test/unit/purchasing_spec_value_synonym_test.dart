import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'package:vinabike_erp/shared/services/supplier_spec_extraction.dart';

import 'purchasing_independent_review_test.dart' as qa;

/// **Una sola normalización para las dos orillas.**
///
/// La ficha rotula el compuesto por su química —`Orgánico`—; el taller y medio
/// catálogo lo nombran por su aglutinante —«de resina»—. Si la equivalencia
/// viviera sólo del lado de la petición, seguiría existiendo el defecto
/// simétrico: una fila que titula `PASTILLA DE RESINA` no demostraría su propio
/// compuesto y quedaría «por revisar» diciéndolo con todas las letras.
SupplierNeedSearchPlan _plan() => buildSupplierNeedSearchPlan(
      request: const SupplierNeedSearchRequest(
        needId: 'spec-value-synonym',
        description: 'Pastillas para frenos Shimano de resina',
        categoryId: 'brake-pads',
        categoryPath: 'Componentes / Frenos / Pastillas',
        technicalFamily: 'brake_pad',
        fields: <SupplierNeedSearchField>[
          SupplierNeedSearchField(
            key: 'compound_type',
            label: 'Compuesto',
            dataType: 'single_select',
            allowedValues: <Object>['Orgánico', 'Metálico', 'Semi-Metálico'],
          ),
        ],
        predicates: <SupplierNeedSearchPredicate>[
          SupplierNeedSearchPredicate(
            field: 'compound_type',
            operator: 'eq',
            values: <Object>['Orgánico'],
          ),
        ],
      ),
      adapter: qa.planFor('Pastillas').adapter,
      maxLength: 20,
    )!;

SupplierNeedPortalMatch _judge(String name, {String head = 'PASTILLA'}) =>
    matchSupplierNeedCandidates(_plan(), <SupplierPortalCatalogCandidate>[
      SupplierPortalCatalogCandidate(
        code: 'synonym-row',
        name: name,
        rowText: name,
        priceNet: 1000,
        technicalFacts: <String, Object?>{kSupplierObjectHeadFact: head},
      ),
    ]).single;

void main() {
  test('el proveedor demuestra el compuesto con la palabra del taller', () {
    final match = _judge('PASTILLA DE RESINA PARA FRENOS SHIMANO');
    expect(match.provenFields, contains('compound_type'));
    expect(match.state, SupplierNeedMatchState.exact);
  });

  test('y la palabra contraria sigue contradiciendo', () {
    final match = _judge('PASTILLA SINTERIZADA PARA FRENOS SHIMANO');
    expect(match.conflictingFields, contains('compound_type'));
  });

  test('una equivalencia de valor nunca decide qué pieza es la fila', () {
    final match = _judge('MANGUERA DE RESINA PARA FRENOS SHIMANO',
        head: 'MANGUERA');
    expect(match.state, isNot(SupplierNeedMatchState.exact));
    expect(match.provenFields, isNot(contains('product_family')));
  });
}
