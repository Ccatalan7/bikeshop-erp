import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/utils/mercadopago_reference.dart';

void main() {
  const tenantId = '5443b130-cc28-45af-a420-cd500b288890';
  const orderId = 'e3161092-23f1-48ad-be8d-f83a110e5e79';

  test('extracts order from versioned and legacy provider references', () {
    expect(
      mercadoPagoOrderIdFromExternalReference(
        'vb1:$tenantId:$orderId:7',
      ),
      orderId,
    );
    expect(mercadoPagoOrderIdFromExternalReference(orderId), orderId);
  });

  test('rejects malformed or path-like callback references', () {
    expect(
      mercadoPagoOrderIdFromExternalReference(
        'vb1:$tenantId:$orderId:0',
      ),
      isNull,
    );
    expect(
      mercadoPagoOrderIdFromExternalReference('../pedido/$orderId'),
      isNull,
    );
    expect(mercadoPagoOrderIdFromExternalReference('not-an-order'), isNull);
  });
}
