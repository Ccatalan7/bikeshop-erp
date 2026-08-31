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

/// Inspects a login page before the protected credential service is called.
///
/// Unlike the visible-browser fill, a background recovery has no operator who
/// can solve an OTP/CAPTCHA or consciously submit an insecure legacy form.
/// This probe therefore returns `safe-to-submit` only for one ordinary HTTPS
/// login form under the exact registered origin. Same-origin frames are
/// included because several supplier portals still use framesets.
String browserAutomaticLoginCapabilityScript({
  required String expectedOrigin,
}) {
  final encodedOrigin = jsonEncode(expectedOrigin);
  return '''
(() => {
  const expectedOrigin = $encodedOrigin;
  if (location.origin !== expectedOrigin) return 'origin-mismatch';

  const documents = [];
  const visited = new Set();
  const collect = (win) => {
    if (!win || visited.has(win)) return;
    visited.add(win);
    try {
      if (win.location.origin !== expectedOrigin) return;
      documents.push(win.document);
      for (let index = 0; index < win.frames.length; index += 1) {
        collect(win.frames[index]);
      }
    } catch (_) {
      // Cross-origin children are deliberately opaque.
    }
  };
  collect(window);

  let sawInteractiveForm = false;
  for (const doc of documents) {
    for (const form of doc.querySelectorAll('form')) {
      const view = doc.defaultView;
      const destination = `\${view.location.pathname} \${form.action || ''}`
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
        !field.disabled && field.getAttribute('autocomplete') !== 'new-password'
      );
      if (passwordFields.length !== 1) continue;
      const usernameField = form.querySelector(
        'input[type="email"], '
        + 'input[autocomplete="username"], '
        + 'input[name*="mail" i], '
        + 'input[name*="user" i], '
        + 'input[name*="rut" i], '
        + 'input[type="text"]',
      );
      if (!usernameField || usernameField.disabled) continue;
      sawInteractiveForm = true;

      let action;
      try {
        action = new URL(form.action || view.location.href, view.location.href);
      } catch (_) {
        return 'interaction-required';
      }
      if (action.protocol !== 'https:') return 'insecure-action';

      const hasChallenge = Boolean(form.querySelector(
        'input[autocomplete="one-time-code"], '
        + 'input[name*="otp" i], input[name*="code" i], '
        + '[id*="captcha" i], [class*="captcha" i], '
        + 'iframe[src*="captcha" i], iframe[src*="recaptcha" i]',
      ));
      const passwordField = passwordFields[0];
      const missingExtraRequiredField = Array.from(form.querySelectorAll(
        'input[required], select[required], textarea[required]',
      )).some((field) =>
        field !== usernameField &&
        field !== passwordField &&
        !field.disabled &&
        field.type !== 'hidden' &&
        !field.value
      );
      if (hasChallenge || missingExtraRequiredField) {
        return 'interaction-required';
      }
      return 'safe-to-submit';
    }
  }
  return sawInteractiveForm ? 'interaction-required' : 'no-login-form';
})();
''';
}

/// Produces a one-shot login fill. [autoSubmit] is disabled after the first
/// attempt in a tab, and is also skipped when a CAPTCHA/OTP/extra required
/// field makes an automatic login unsafe.
String browserCredentialFillScript({
  required String expectedOrigin,
  required String username,
  required String password,
  required bool autoSubmit,
  required bool allowInsecureSupplierOrigin,

  /// El `action` HTTP declarado para un portal legacy. Cuando viene, **el
  /// formulario tiene que enviar exactamente ahí**: la política autoriza el par
  /// página+destino, pero quien ve el formulario es este script, así que la
  /// comprobación del destino se hace también acá, contra el DOM real, antes de
  /// escribir un solo carácter de la credencial.
  String? expectedInsecureAction,

  /// Las páginas exactas que esa declaración cubre. Cuando vienen, la identidad
  /// de la página se comprueba por **URL completa**, no por origen: el permiso
  /// es de una URL. Comparar el origen no servía en ninguno de los dos sentidos
  /// —la página legacy puede ser HTTP y no calzar con el origen canónico
  /// HTTPS, y cualquier otra página del mismo origen habría calzado igual—.
  List<String>? expectedDeclaredPageUrls,
}) {
  final encodedOrigin = jsonEncode(expectedOrigin);
  final encodedExpectedAction = jsonEncode(expectedInsecureAction);
  final encodedExpectedPages = jsonEncode(expectedDeclaredPageUrls);
  final encodedUsername = jsonEncode(username);
  final encodedPassword = jsonEncode(password);
  return '''
(() => {
  const expectedOrigin = $encodedOrigin;
  const expectedPages = $encodedExpectedPages;
  // Con declaración, la página se identifica por su URL exacta. Sin ella se
  // sigue exigiendo el origen canónico de siempre.
  if (expectedPages !== null) {
    if (!expectedPages.includes(location.href)) return 'page-not-declared';
  } else if (location.origin !== expectedOrigin) {
    return 'origin-mismatch';
  }
  const securePage = location.protocol === 'https:';
  if (!securePage && !$allowInsecureSupplierOrigin) return 'insecure';

  // **Una página insegura sólo se rellena contra su destino declarado.** Sin
  // esto, autorizar la página dejaría libre a dónde viaja el secreto.
  const expectedAction = $encodedExpectedAction;
  if (!securePage && !expectedAction) return 'insecure-action-undeclared';

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
    // **Cada página tiene UN destino aceptable, no dos.** Cuando hay
    // declaración, ése es el único destino: ni siquiera otro `https://` de la
    // misma página vale, porque lo declarado es el par completo. Sin
    // declaración rige la regla genérica de siempre: página segura, destino
    // seguro. Mirar el esquema de la página para elegir la regla —`securePage ?
    // secureAction : declaredAction`— dejaba fuera justo el caso real: el
    // formulario legacy se sirve **también por HTTPS** y manda igual a HTTP.
    const secureAction = action.protocol === 'https:';
    const declaredAction =
      expectedAction !== null && action.toString() === expectedAction;
    const trustedAction =
      expectedAction !== null ? declaredAction : (securePage && secureAction);
    if (!trustedAction) continue;

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

    // El envío automático usa la MISMA variable que autorizó el relleno.
    if ($autoSubmit && trustedAction &&
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

    // Un formulario que no calificó nunca llega acá: el `continue` de arriba lo
    // saca antes de escribir. Lo que sí se distingue es cómo se llenó, para que
    // quien lea el resultado sepa si viajó por el transporte legacy declarado.
    // Lo decide la declaración, no el esquema de la página: la página puede ser
    // HTTPS y el destino declarado seguir siendo HTTP.
    if (expectedAction !== null) return 'filled-declared-legacy';
    return 'filled';
  }

  return 'no-login-form';
})();
''';
}
