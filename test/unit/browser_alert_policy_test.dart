import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/utils/browser_alert_policy.dart';

void main() {
  test('RBX empty-result alert is acknowledged inside the browser workspace',
      () {
    expect(
      shouldAutoConfirmBrowserAlert(
        pageUrl: 'http://www.rburgos.cl/catalogo.asp',
        message: 'No hay ningún producto que mostrar en su búsqueda',
      ),
      isTrue,
    );
  });

  test('other sites and other RBX alerts keep the platform default', () {
    expect(
      shouldAutoConfirmBrowserAlert(
        pageUrl: 'https://example.com/catalogo',
        message: 'No hay ningún producto que mostrar en su búsqueda',
      ),
      isFalse,
    );
    expect(
      shouldAutoConfirmBrowserAlert(
        pageUrl: 'https://portal.rburgos.cl/',
        message: 'Su sesión expiró',
      ),
      isFalse,
    );
  });
}
