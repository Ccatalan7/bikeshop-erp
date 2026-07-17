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

    expect(automatic, contains(jsonEncode(username)));
    expect(automatic, contains(jsonEncode(password)));
    expect(automatic, contains(jsonEncode('https://supplier.example')));
    expect(fillOnly, contains(jsonEncode('http://legacy-supplier.example')));
    expect(automatic, contains('if (true && securePage && secureAction'));
    expect(fillOnly, contains('if (false && securePage && secureAction'));
    expect(automatic, contains('filled-and-submitted'));
    expect(automatic, contains('filled-insecure'));
    expect(automatic, contains("action.protocol === 'https:'"));
    expect(automatic, contains('one-time-code'));
    expect(automatic, contains('captcha'));
    expect(automatic, contains('missingExtraRequiredField'));
  });
}
