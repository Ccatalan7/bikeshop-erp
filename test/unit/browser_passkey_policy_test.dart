import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/utils/browser_passkey_policy.dart';

/// The embedded browser cannot show a passkey prompt; a site that detects
/// WebAuthn support hangs on it (Google via AliExpress, 2026-09-03). The
/// capability is hidden before any page script runs, everywhere the browser
/// creates a web view.
void main() {
  test('the script hides WebAuthn before page scripts can probe it', () {
    final script = browserPasskeyUnavailableUserScript();
    expect(script.injectionTime, UserScriptInjectionTime.AT_DOCUMENT_START);
    expect(script.forMainFrameOnly, isFalse,
        reason: 'sign-in flows run in frames and popups too');
    expect(browserPasskeyUnavailableUserScriptSource,
        contains("hide(window, 'PublicKeyCredential')"));
    expect(browserPasskeyUnavailableUserScriptSource,
        contains("hide(navigator, 'credentials')"));
    expect(browserPasskeyUnavailableUserScriptSource,
        contains('configurable: true'));
  });

  test('tabs and popups both inject it', () {
    for (final path in [
      'lib/shared/widgets/webview_module_page.dart',
      'lib/shared/widgets/browser_popup_window.dart',
    ]) {
      final source = File(path).readAsStringSync();
      final popupCapture =
          source.indexOf('    browserPopupOpenCaptureUserScript(),\n');
      final passkey =
          source.indexOf('    browserPasskeyUnavailableUserScript(),\n');
      expect(popupCapture, greaterThan(-1), reason: path);
      expect(passkey, greaterThan(popupCapture),
          reason: '$path lists the passkey script with the initial scripts');
    }
  });
}
