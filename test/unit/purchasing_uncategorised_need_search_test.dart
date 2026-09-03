import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';

/// **Una necesidad sin categoría todavía se puede buscar.**
///
/// Medido en producción el 2026-08-31: «Motor Sellado 73x118mm», «Puños con
/// gel» y «Sellante tubeless» quedaron con `identity_unresolved`, sin categoría
/// y sin familia técnica, y con eso el plan del proveedor no se podía armar
/// —la necesidad ni siquiera permitía preguntar—. El extractor canónico sí
/// reconoce la familia en esas mismas palabras: la categoría aporta su
/// sustantivo cuando existe, no es una precondición para buscar.
SupplierNeedSearchPlan? _plan(String description, {String? categoryId}) =>
    buildSupplierNeedSearchPlan(
      request: SupplierNeedSearchRequest(
        needId: 'sin-categoria',
        description: description,
        categoryId: categoryId,
        fields: const <SupplierNeedSearchField>[],
        predicates: const <SupplierNeedSearchPredicate>[],
      ),
      adapter: SupplierNeedPortalAdapter.fromJson(const <String, dynamic>{
        'version': 1,
        'generic_family_search': true,
        'result_schema': <String, dynamic>{},
      }),
      maxLength: 30,
    );

void main() {
  for (final caso in <String, String>{
    'Motor Sellado 73x118mm': 'bottom_bracket',
    'Puños con gel': 'grip',
    'Sellante tubeless': 'sealant',
  }.entries) {
    test('«${caso.key}» se puede buscar sin categoría', () {
      final plan = _plan(caso.key);
      expect(plan, isNotNull,
          reason: 'sin plan no hay ni siquiera una pregunta que hacerle al '
              'proveedor');
      expect(plan!.family.identityFamily, caso.value);
      expect(plan.query, isNotEmpty);
    });
  }

  test('sin ficha no se inventan criterios: se busca y se prueba identidad',
      () {
    final plan = _plan('Motor Sellado 73x118mm')!;
    expect(plan.request.predicates, isEmpty);
    final match = matchSupplierNeedCandidates(
      plan,
      const <SupplierPortalCatalogCandidate>[
        SupplierPortalCatalogCandidate(
          code: 'a',
          name: 'MOTOR SELLADO 73 X 118 MM',
          rowText: 'MOTOR SELLADO 73 X 118 MM',
          priceNet: 1000,
        ),
        SupplierPortalCatalogCandidate(
          code: 'b',
          name: 'CAMARA 29 X 1.75 VALVULA AUTO',
          rowText: 'CAMARA 29 X 1.75 VALVULA AUTO',
          priceNet: 1000,
        ),
      ],
    );
    final motor = match.singleWhere((m) => m.candidate.code == 'a');
    final camara = match.singleWhere((m) => m.candidate.code == 'b');
    expect(motor.provenFields, contains('product_family'),
        reason: 'la identidad se prueba con el vocabulario de la familia');
    expect(camara.state, SupplierNeedMatchState.conflict,
        reason: 'y otra pieza sigue quedando fuera por identidad');
  });

  test('una necesidad que ni siquiera nombra una familia no arma plan', () {
    expect(_plan('lo de siempre para el taller'), isNull,
        reason: 'sin objeto reconocible no hay palabra que preguntar');
  });
}
