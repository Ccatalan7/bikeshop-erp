import 'dart:convert';

const browserCredentialCaptureHandlerName =
    'VinabikeBrowserCredentialSubmitted';

/// Annotates login fields and captures only an HTTPS login form submission.
///
/// The submitted credential is handed directly to Flutter so it can be placed
/// in the operating system's secure vault. It is never written to page storage
/// or ordinary application preferences.
const browserCredentialCaptureUserScript = r'''
(() => {
  const captureHandler = 'VinabikeBrowserCredentialSubmitted';

  const findLoginFields = (form) => {
    const destination = `${location.pathname} ${form.action || ''}`
      .toLowerCase();
    const createsCredential = [
      'register', 'signup', 'sign-up', 'create-account', 'crear-cuenta',
      'registro', 'reset-password', 'password-reset', 'recover-password',
      'forgot-password', 'recuperar-clave', 'recuperar-contrasena',
    ].some((token) => destination.includes(token));
    if (createsCredential) return null;

    const passwordFields = Array.from(
      form.querySelectorAll('input[type="password"]'),
    ).filter((field) =>
      !field.disabled &&
      field.getAttribute('autocomplete') !== 'new-password'
    );
    if (passwordFields.length !== 1) return null;

    const usernameField = form.querySelector(
      'input[type="email"], '
      + 'input[autocomplete="username"], '
      + 'input[name*="mail" i], '
      + 'input[name*="user" i], '
      + 'input[type="text"]',
    );
    if (!usernameField || usernameField.disabled) return null;
    return {usernameField, passwordField: passwordFields[0]};
  };

  for (const form of document.querySelectorAll('form')) {
    const fields = findLoginFields(form);
    if (!fields) continue;
    if (!fields.usernameField.hasAttribute('autocomplete')) {
      fields.usernameField.setAttribute('autocomplete', 'username');
    }
    if (!fields.passwordField.hasAttribute('autocomplete')) {
      fields.passwordField.setAttribute('autocomplete', 'current-password');
    }
  }

  if (window.__vinabikeCredentialCaptureInstalled) return;
  window.__vinabikeCredentialCaptureInstalled = true;

  document.addEventListener('submit', (event) => {
    if (location.protocol !== 'https:') return;
    const form = event.target;
    if (!(form instanceof HTMLFormElement)) return;
    const fields = findLoginFields(form);
    if (!fields) return;

    let action;
    try {
      action = new URL(form.action || location.href, location.href);
    } catch (_) {
      return;
    }
    if (action.protocol !== 'https:') return;

    const username = fields.usernameField.value.trim();
    const password = fields.passwordField.value;
    if (!username || !password ||
        !window.flutter_inappwebview ||
        !window.flutter_inappwebview.callHandler) {
      return;
    }

    window.flutter_inappwebview.callHandler(captureHandler, {
      origin: location.origin,
      username,
      password,
    });
  }, true);
})();
''';

/// Checks for a real login form before any credential is loaded from storage.
const browserLoginFormDetectionScript = r'''
(() => {
  for (const form of document.querySelectorAll('form')) {
    const destination = `${location.pathname} ${form.action || ''}`
      .toLowerCase();
    const createsCredential = [
      'register', 'signup', 'sign-up', 'create-account', 'crear-cuenta',
      'registro', 'reset-password', 'password-reset', 'recover-password',
      'forgot-password', 'recuperar-clave', 'recuperar-contrasena',
    ].some((token) => destination.includes(token));
    if (createsCredential) continue;

    const passwordFields = Array.from(
      form.querySelectorAll('input[type="password"]'),
    ).filter((field) =>
      !field.disabled &&
      field.getAttribute('autocomplete') !== 'new-password'
    );
    if (passwordFields.length !== 1) continue;
    const usernameField = form.querySelector(
      'input[type="email"], '
      + 'input[autocomplete="username"], '
      + 'input[name*="mail" i], '
      + 'input[name*="user" i], '
      + 'input[type="text"]',
    );
    if (usernameField && !usernameField.disabled) return true;
  }
  return false;
})();
''';

/// Produces a one-shot login fill. [autoSubmit] is disabled after the first
/// attempt in a tab, and is also skipped when a CAPTCHA/OTP/extra required
/// field makes an automatic login unsafe.
String browserCredentialFillScript({
  required String expectedOrigin,
  required String username,
  required String password,
  required bool autoSubmit,
  required bool allowInsecureSupplierOrigin,
}) {
  final encodedOrigin = jsonEncode(expectedOrigin);
  final encodedUsername = jsonEncode(username);
  final encodedPassword = jsonEncode(password);
  return '''
(() => {
  const expectedOrigin = $encodedOrigin;
  if (location.origin !== expectedOrigin) return 'origin-mismatch';
  const securePage = location.protocol === 'https:';
  if (!securePage && !$allowInsecureSupplierOrigin) return 'insecure';

  const usernameValue = $encodedUsername;
  const passwordValue = $encodedPassword;
  const forms = Array.from(document.querySelectorAll('form'));

  for (const form of forms) {
    const destination = `\${location.pathname} \${form.action || ''}`
      .toLowerCase();
    const createsCredential = [
      'register', 'signup', 'sign-up', 'create-account', 'crear-cuenta',
      'registro', 'reset-password', 'password-reset', 'recover-password',
      'forgot-password', 'recuperar-clave', 'recuperar-contrasena',
    ].some((token) => destination.includes(token));
    if (createsCredential) continue;

    const passwordFields = Array.from(
      form.querySelectorAll('input[type="password"]'),
    ).filter((field) =>
      !field.disabled &&
      field.getAttribute('autocomplete') !== 'new-password'
    );
    if (passwordFields.length !== 1) continue;

    const usernameField = form.querySelector(
      'input[type="email"], '
      + 'input[autocomplete="username"], '
      + 'input[name*="mail" i], '
      + 'input[name*="user" i], '
      + 'input[type="text"]',
    );
    if (!usernameField || usernameField.disabled) continue;
    const passwordField = passwordFields[0];

    let action;
    try {
      action = new URL(form.action || location.href, location.href);
    } catch (_) {
      continue;
    }
    const secureAction = action.protocol === 'https:';

    const setFieldValue = (field, value) => {
      const prototype = Object.getPrototypeOf(field);
      const descriptor = Object.getOwnPropertyDescriptor(prototype, 'value');
      if (descriptor && descriptor.set) {
        descriptor.set.call(field, value);
      } else {
        field.value = value;
      }
      field.dispatchEvent(new Event('input', {bubbles: true}));
      field.dispatchEvent(new Event('change', {bubbles: true}));
    };

    setFieldValue(usernameField, usernameValue);
    setFieldValue(passwordField, passwordValue);

    const hasChallenge = Boolean(form.querySelector(
      'input[autocomplete="one-time-code"], '
      + 'input[name*="otp" i], input[name*="code" i], '
      + '[id*="captcha" i], [class*="captcha" i], '
      + 'iframe[src*="captcha" i], iframe[src*="recaptcha" i]',
    ));
    const missingExtraRequiredField = Array.from(form.querySelectorAll(
      'input[required], select[required], textarea[required]',
    )).some((field) =>
      field !== usernameField &&
      field !== passwordField &&
      !field.disabled &&
      field.type !== 'hidden' &&
      !field.value
    );

    if ($autoSubmit && securePage && secureAction &&
        !hasChallenge && !missingExtraRequiredField) {
      window.setTimeout(() => {
        if (!form.isConnected) return;
        if (typeof form.requestSubmit === 'function') {
          form.requestSubmit();
          return;
        }
        const submit = form.querySelector(
          'button[type="submit"], input[type="submit"]',
        );
        if (submit) submit.click();
      }, 80);
      return 'filled-and-submitted';
    }

    if (!securePage || !secureAction) return 'filled-insecure';
    return 'filled';
  }

  return 'no-login-form';
})();
''';
}
