import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'purchasing_independent_review_test.dart' as qa;

void main() {
  SupplierNeedPortalMatch row({required String name, required String brand}) =>
    matchSupplierNeedCandidates(qa.planFor('Pastillas para frenos Shimano'), [
      SupplierPortalCatalogCandidate(code: 'synthetic-brand-vs-fitment',
        name: name, rowText: '$name MARCA $brand', brand: brand, priceNet: 1000,
        technicalFacts: {'supplier_object_head': 'PASTILLA', 'brake_system': brand}),
    ]).single;

  test('a different maker does not contradict explicit Shimano fitment', () {
    final match = row(name: 'PASTILLA RESINA MARCA TEKTRO PARA FRENOS SHIMANO', brand: 'Tektro');
    expect(match.state, isNot(SupplierNeedMatchState.conflict),
      reason: 'fabricante Tektro no niega el para frenos Shimano del texto');
  });

  test('a maker alone does not prove or disprove the compatible brake system', () {
    for (final maker in ['Shimano', 'Tektro']) {
      final match = row(name: 'PASTILLA FRENO DISCO MARCA $maker', brand: maker);
      expect(match.provenFields, isNot(contains('brake_system')),
        reason: 'marca de la pastilla no es evidencia del sistema de destino');
      expect(match.conflictingFields, isNot(contains('brake_system')),
        reason: 'no hay evidencia del sistema compatible, sólo del fabricante');
    }
  });
}
