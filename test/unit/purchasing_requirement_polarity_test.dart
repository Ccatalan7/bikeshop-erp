import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'purchasing_independent_review_test.dart' as qa;

void main() {
  test('request and product agreeing on absence do not contradict', () {
    final match = qa.judge('Pastillas para frenos Shimano MT200 sin aletas',
      'PASTILLA PARA FRENOS SHIMANO MT200 SIN ALETAS', head: 'PASTILLA');
    expect(match.state, isNot(SupplierNeedMatchState.conflict),
      reason: 'sin aletas cumple sin aletas, no lo contradice');
  });

  test('a requested absence is not met by the property being present', () {
    final match = qa.judge('Pastillas para frenos Shimano MT200 sin aletas',
      'PASTILLA PARA FRENOS SHIMANO MT200 CON ALETAS', head: 'PASTILLA');
    expect(match.state, SupplierNeedMatchState.conflict,
      reason: 'la polaridad del pedido importa aunque no exista campo de aletas en esta ficha');
  });
}
