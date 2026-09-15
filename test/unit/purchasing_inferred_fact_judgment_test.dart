import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'package:vinabike_erp/shared/services/supplier_spec_extraction.dart';

import 'purchasing_independent_review_test.dart' as qa;

void main() {
  SupplierNeedPortalMatch judgeInferred(String value) =>
    matchSupplierNeedCandidates(qa.planFor('Pastillas Shimano'), [
      SupplierPortalCatalogCandidate(code: 'unverified-model-reading',
        name: 'PASTILLA FRENO DISCO', rowText: 'PASTILLA FRENO DISCO',
        priceNet: 1000,
        technicalFacts: {
          kSupplierObjectHeadFact: 'PASTILLA',
          'brake_system': value,
          kSupplierInferredFactsFact: ['brake_system'],
        }),
    ]).single;

  test('inferred facts cannot prove an exact main-list match', () {
    final match = judgeInferred('Shimano');
    expect(match.state, isNot(SupplierNeedMatchState.exact));
    expect(match.provenFields, isNot(contains('brake_system')));
  });

  test('inferred facts cannot exclude an otherwise unknown candidate', () {
    final match = judgeInferred('Tektro');
    expect(match.state, isNot(SupplierNeedMatchState.conflict));
    final preview = judgeSupplierNeedMatchesUnder(matches: [match],
      predicates: qa.planFor('Pastillas Shimano').request.predicates,
      fields: qa.fields);
    expect(preview, hasLength(1));
    expect(preview.single.isConfirmed, isFalse);
  });
}
