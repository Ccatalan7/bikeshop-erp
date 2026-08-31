import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';

import 'purchasing_independent_review_test.dart' as qa;

void main() {
  test('removing a criterion releases its old technical conflict', () {
    final plan = qa.planFor('Pastillas Shimano');
    final matches = matchSupplierNeedCandidates(plan, const [
      SupplierPortalCatalogCandidate(code: 'tektro-row',
        name: 'PASTILLA TEKTRO', rowText: 'PASTILLA TEKTRO', priceNet: 1000,
        technicalFacts: {'brake_system': 'Tektro', 'supplier_object_head': 'PASTILLA'}),
    ]);
    expect(matches.single.conflictingFields, contains('brake_system'));
    final cleared = judgeSupplierNeedMatchesUnder(
      matches: matches, predicates: [], fields: qa.fields,
    );
    expect(cleared, hasLength(1),
      reason: 'borrar Sistema de Freno sí elimina su contradicción; no cambia el objeto');
    expect(cleared.single.isConfirmed, isFalse);
  });

  test('local preview cannot turn incompatible into confirmed', () {
    const request = 'Pastillas para Shimano MT200';
    final match = qa.judge(request,
        'PASTILLA SHIMANO NO COMPATIBLE CON MT200', head: 'PASTILLA');
    expect(match.state, SupplierNeedMatchState.conflict);

    final preview = judgeSupplierNeedMatchesUnder(
      matches: [match],
      predicates: qa.planFor(request).request.predicates,
      fields: qa.fields,
    );
    expect(preview, isEmpty,
        reason: 'la compatibilidad negada no cambia al editar otras specs');
  });
}
