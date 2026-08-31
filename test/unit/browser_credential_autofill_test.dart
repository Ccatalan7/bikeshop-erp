import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/utils/browser_credential_autofill.dart';

void main() {
  test('capture script is limited to submitted HTTPS login forms', () {
    expect(
      browserCredentialCaptureUserScript,
      contains("location.protocol !== 'https:'"),
    );
    expect(
      browserCredentialCaptureUserScript,
      contains('passwordFields.length !== 1'),
    );
    expect(
      browserCredentialCaptureUserScript,
      contains("document.addEventListener('submit'"),
    );
    expect(
      browserCredentialCaptureUserScript,
      contains(browserCredentialCaptureHandlerName),
    );
    expect(
      browserCredentialCaptureUserScript,
      contains("'current-password'"),
    );
    expect(browserCredentialCaptureUserScript, contains("'create-account'"));
    expect(browserLoginFormDetectionScript, contains('return true'));
    expect(browserLoginFormDetectionScript, contains("'password-reset'"));
    expect(
      browserLoginFormDetectionScript,
      isNot(contains("location.protocol !== 'https:'")),
    );

    for (final forbidden in [
      'localStorage',
      'sessionStorage',
      'SharedPreferences',
      'fetch(',
      'XMLHttpRequest',
      'console.',
    ]) {
      expect(browserCredentialCaptureUserScript, isNot(contains(forbidden)));
    }
  });

  test('fill script safely encodes values and bounds automatic submission', () {
    const username = 'user+supplier@example.com';
    const password = 'quote" newline\n and \\ slash';

    final automatic = browserCredentialFillScript(
      expectedOrigin: 'https://supplier.example',
      username: username,
      password: password,
      autoSubmit: true,
      allowInsecureSupplierOrigin: false,
    );
    final fillOnly = browserCredentialFillScript(
      expectedOrigin: 'http://legacy-supplier.example',
      username: username,
      password: password,
      autoSubmit: false,
      allowInsecureSupplierOrigin: true,
    );
    final declarado = browserCredentialFillScript(
      expectedOrigin: 'https://legacy-supplier.example',
      username: username,
      password: password,
      autoSubmit: true,
      allowInsecureSupplierOrigin: true,
      expectedInsecureAction: 'http://otro-host.example/valida.asp',
      expectedDeclaredPageUrls: const <String>[
        'https://legacy-supplier.example/login/',
        'http://legacy-supplier.example/login/',
      ],
    );

    expect(automatic, contains(jsonEncode(username)));
    expect(automatic, contains(jsonEncode(password)));
    expect(automatic, contains(jsonEncode('https://supplier.example')));
    expect(fillOnly, contains(jsonEncode('http://legacy-supplier.example')));
    // **El envío automático usa la misma condición que autorizó el relleno.**
    // Antes miraba `securePage && secureAction`, así que en una página legacy
    // declarada rellenaba y no enviaba: dejaba la credencial escrita en un
    // formulario que nunca se manda, y la sesión a medias.
    expect(automatic, contains('if (true && trustedAction'));
    expect(fillOnly, contains('if (false && trustedAction'));

    // **Cada página tiene UN destino aceptable, no dos.** Con declaración, ése
    // es el único; sin ella rige la regla genérica. Elegir la regla por el
    // esquema de la PÁGINA —`securePage ? secureAction : declaredAction`—
    // dejaba fuera el caso real: el formulario legacy de RBX se sirve también
    // por HTTPS y manda igual a un `action` HTTP, así que la declaración nunca
    // se aplicaba en el camino normal.
    expect(
      automatic,
      contains(
        'expectedAction !== null ? declaredAction : (securePage && '
        'secureAction)',
      ),
    );
    expect(automatic, isNot(contains('secureAction || declaredAction')));
    expect(
      automatic,
      isNot(contains('securePage ? secureAction : declaredAction')),
    );

    // La identidad de una página declarada se comprueba por URL completa, no
    // por origen: si bastara el origen, cualquier otra página del mismo portal
    // habría podido mandar la credencial al destino legacy.
    expect(declarado, contains("return 'page-not-declared'"));
    expect(
      declarado,
      contains(jsonEncode(const <String>[
        'https://legacy-supplier.example/login/',
        'http://legacy-supplier.example/login/',
      ])),
    );
    expect(
        declarado, contains(jsonEncode('http://otro-host.example/valida.asp')));
    // Sin declaración se sigue exigiendo el origen canónico de siempre.
    expect(automatic, contains("return 'origin-mismatch'"));
    expect(automatic, contains('const expectedPages = null;'));

    // Y nada se escribe antes de validar el destino: la comparación va en el
    // loop, con `continue`, no después de `setFieldValue`.
    final antesDeEscribir = automatic.indexOf('if (!trustedAction) continue;');
    expect(antesDeEscribir, greaterThan(-1));
    expect(
      antesDeEscribir,
      lessThan(automatic.indexOf('setFieldValue(usernameField')),
      reason: 'el destino se valida antes de escribir la credencial',
    );

    // Un destino inseguro sólo vale si es EXACTAMENTE el declarado.
    expect(automatic, contains('action.toString() === expectedAction'));

    // Y no quedan returns muertos después del `continue`.
    expect(automatic, isNot(contains("return 'filled-insecure'")));

    // Sin declaración, una página insegura no llega ni a mirar formularios.
    expect(automatic, contains("return 'insecure-action-undeclared'"));
    expect(automatic, contains('filled-and-submitted'));
    // `filled-insecure` ya no existe: un formulario que no calificó no llega a
    // escribirse. Lo que se distingue ahora es que el relleno viajó por el
    // transporte legacy declarado.
    expect(automatic, contains('filled-declared-legacy'));
    // Y quién decide que el relleno viajó por el transporte legacy es la
    // declaración, no el esquema de la página: la página puede ser HTTPS y el
    // destino declarado seguir siendo HTTP.
    expect(
      automatic,
      contains("if (expectedAction !== null) return 'filled-declared-legacy';"),
    );
    expect(automatic, isNot(contains("if (!securePage) return 'filled")));
    expect(automatic, contains("action.protocol === 'https:'"));
    expect(automatic, contains('one-time-code'));
    expect(automatic, contains('captcha'));
    expect(automatic, contains('missingExtraRequiredField'));
  });

  test('automatic login capability probe fails closed before credentials', () {
    final script = browserAutomaticLoginCapabilityScript(
      expectedOrigin: 'https://supplier.example',
    );

    expect(script, contains(jsonEncode('https://supplier.example')));
    expect(script, contains("return 'safe-to-submit'"));
    expect(script, contains("return 'insecure-action'"));
    expect(script, contains("return 'interaction-required'"));
    expect(script, contains('one-time-code'));
    expect(script, contains('captcha'));
    expect(script, contains('input[name*="rut" i]'));
    expect(script, contains('win.frames'));
    expect(script, isNot(contains('filled-and-submitted')));
    expect(script, isNot(contains('fetch(')));
  });
}
