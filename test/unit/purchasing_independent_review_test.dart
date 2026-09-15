import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'package:vinabike_erp/shared/services/supplier_spec_extraction.dart';

const fields = <SupplierNeedSearchField>[
  SupplierNeedSearchField(
    key: 'brake_system',
    label: 'Sistema de Freno',
    dataType: 'single_select',
    allowedValues: <Object>['Shimano', 'SRAM', 'Tektro', 'Magura'],
  ),
];

SupplierNeedSearchPlan planFor(String description) =>
    buildSupplierNeedSearchPlan(
      request: SupplierNeedSearchRequest(
        needId: 'independent-review',
        description: description,
        categoryId: 'brake-pads',
        categoryPath: 'Componentes / Frenos / Pastillas',
        technicalFamily: 'brake_pad',
        fields: fields,
        predicates: const <SupplierNeedSearchPredicate>[
          SupplierNeedSearchPredicate(
            field: 'brake_system',
            operator: 'eq',
            values: <Object>['Shimano'],
          ),
        ],
      ),
      adapter: SupplierNeedPortalAdapter.fromJson(<String, dynamic>{
        'version': 1,
        'generic_family_search': true,
        'result_schema': <String, dynamic>{
          'columns': <String, dynamic>{
            'code': <String>['c'],
            'name': <String>['n'],
            'price': <String>['p'],
          },
        },
        'catalog_route': <String, dynamic>{
          'url_template': 'http://example.invalid/{node}{page}{page_size}',
          'page_size': 50,
        },
      }),
      maxLength: 20,
    )!;

SupplierNeedPortalMatch judge(String description, String name,
        {String? head}) =>
    matchSupplierNeedCandidates(planFor(description), [
      SupplierPortalCatalogCandidate(
        code: 'independent-row',
        name: name,
        priceNet: 1000,
        rowText: name,
        technicalFacts: <String, Object?>{
          'brake_system': 'Shimano',
          if (head != null) kSupplierObjectHeadFact: head,
        },
      ),
    ]).single;

void main() {
  test('missing compatibility stays pending without a hyphen in model', () {
    final match = judge('Pastillas para Shimano MT200',
        'PASTILLA FRENO DISCO SHIMANO RESINA',
        head: 'PASTILLA FRENO DISCO');
    expect(match.state, isNot(SupplierNeedMatchState.exact));
    expect(match.missingFields, contains(kCompatibilityRequirementField));
  });

  test('missing compatibility stays pending with a spaced model', () {
    final match = judge('Pastillas para Shimano BR MT200',
        'PASTILLA FRENO DISCO SHIMANO RESINA',
        head: 'PASTILLA FRENO DISCO');
    expect(match.state, isNot(SupplierNeedMatchState.exact));
    expect(match.missingFields, contains(kCompatibilityRequirementField));
  });

  test('negative compatibility evidence never proves a requirement', () {
    final match = judge('Pastillas para Shimano BR-MT200',
        'PASTILLA FRENO DISCO SHIMANO NO COMPATIBLE CON BR-MT200',
        head: 'PASTILLA FRENO DISCO');
    expect(match.state, isNot(SupplierNeedMatchState.exact));
    expect(match.provenFields, isNot(contains(kCompatibilityRequirementField)));
  });

  test('an accessory mentioning the wanted part is not the wanted part', () {
    final match = judge('Pastillas Shimano',
        'SEPARADOR PARA PASTILLAS SHIMANO',
        head: 'SEPARADOR PARA PASTILLAS');
    expect(match.state, isNot(SupplierNeedMatchState.exact));
    expect(match.provenFields, isNot(contains('product_family')));
  });
}
