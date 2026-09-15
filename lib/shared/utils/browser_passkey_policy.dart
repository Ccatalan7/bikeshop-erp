import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// The embedded browser exposes the WebAuthn surface (WKWebView does), but it
/// cannot show the platform passkey dialog inside an application window.
/// Google's sign-in probes that surface, routes the account to the passkey
/// challenge and then waits forever for a Touch ID prompt that never comes
/// (owner report, 2026-09-03: AliExpress → Google stuck on "Use your passkey").
///
/// Hiding the capability before any page script runs makes those sites offer
/// their password flow instead. It is injected in every frame, in tabs and in
/// popups alike.
const String browserPasskeyUnavailableUserScriptSource = r'''
(() => {
  const hide = (target, name) => {
    try {
      Object.defineProperty(target, name, {
        value: undefined,
        configurable: true,
        writable: true,
        enumerable: false,
      });
    } catch (_) {}
  };
  hide(window, 'PublicKeyCredential');
  hide(window, 'AuthenticatorResponse');
  hide(window, 'AuthenticatorAssertionResponse');
  hide(window, 'AuthenticatorAttestationResponse');
  hide(navigator, 'credentials');
})();
''';

UserScript browserPasskeyUnavailableUserScript() => UserScript(
      groupName: 'VinabikeBrowserPasskeyUnavailable',
      source: browserPasskeyUnavailableUserScriptSource,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      forMainFrameOnly: false,
    );
