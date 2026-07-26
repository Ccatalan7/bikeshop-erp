import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MercadoPago credentials use the guarded atomic settings RPC', () {
    final source = File(
      'lib/modules/website/services/mercadopago_service.dart',
    ).readAsStringSync();

    expect(source, contains("'save_mercadopago_settings'"));
    expect(source, contains("'p_public_key': publicKey"));
    expect(source, contains("'p_access_token': accessToken"));
    expect(source, contains("'p_test_mode': testMode"));
    expect(
      source,
      isNot(contains(".from('website_settings').upsert")),
    );
  });
}
