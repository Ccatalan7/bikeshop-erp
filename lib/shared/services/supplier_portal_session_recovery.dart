import '../utils/browser_credential_autofill.dart';
import 'browser_supplier_credential_resolver.dart';

typedef SupplierPortalCredentialResolver = Future<BrowserSupplierCredential?>
    Function({
  required String supplierId,
  required String origin,
});

typedef SupplierPortalLoginPageLoader = Future<void> Function(String url);
typedef SupplierPortalJavascriptEvaluator = Future<Object?> Function(
  String source,
);
typedef SupplierPortalLoginSubmitter = Future<Object?> Function(String source);
typedef SupplierPortalCurrentUrlReader = Future<String?> Function();

enum SupplierPortalSessionRecoveryStatus {
  submitted,
  notConfigured,
  loginPageUnavailable,
  interactionRequired,
  credentialUnavailable,
  rejected,
}

class SupplierPortalSessionRecoveryResult {
  const SupplierPortalSessionRecoveryResult(this.status);

  final SupplierPortalSessionRecoveryStatus status;

  bool get submitted => status == SupplierPortalSessionRecoveryStatus.submitted;
}

/// Recupera una sesión vencida usando el mismo límite de seguridad del
/// navegador visible.
///
/// El secreto se pide sólo después de que una página HTTPS, en el origen
/// exacto registrado, demuestra que tiene un formulario que puede enviarse de
/// forma segura y sin CAPTCHA/OTP. La credencial vive únicamente durante este
/// intento; nunca entra en cookies propias, logs, evidencia ni configuración.
Future<SupplierPortalSessionRecoveryResult> recoverSupplierPortalSession({
  required String supplierId,
  required String? loginUrl,
  required SupplierPortalCredentialResolver? resolveCredential,
  required SupplierPortalLoginPageLoader loadLoginPage,
  required SupplierPortalCurrentUrlReader currentUrl,
  required SupplierPortalJavascriptEvaluator evaluateJavascript,
  required SupplierPortalLoginSubmitter submitLogin,
}) async {
  final parsed = Uri.tryParse(loginUrl?.trim() ?? '');
  if (parsed == null ||
      parsed.scheme.toLowerCase() != 'https' ||
      parsed.host.isEmpty ||
      parsed.userInfo.isNotEmpty ||
      resolveCredential == null) {
    return const SupplierPortalSessionRecoveryResult(
      SupplierPortalSessionRecoveryStatus.notConfigured,
    );
  }
  final origin = normalizeSupplierBrowserOrigin(parsed.origin);
  if (origin == null) {
    return const SupplierPortalSessionRecoveryResult(
      SupplierPortalSessionRecoveryStatus.notConfigured,
    );
  }

  try {
    await loadLoginPage(parsed.toString());
    if (normalizeSupplierBrowserOrigin(await currentUrl()) != origin) {
      return const SupplierPortalSessionRecoveryResult(
        SupplierPortalSessionRecoveryStatus.loginPageUnavailable,
      );
    }

    // No se revela el secreto para una acción HTTP, un CAPTCHA/OTP o un
    // formulario ambiguo. El análisis sólo inspecciona estructura pública.
    final capability = await evaluateJavascript(
      browserAutomaticLoginCapabilityScript(expectedOrigin: origin),
    );
    if (!_scriptResultContains(capability, 'safe-to-submit')) {
      return SupplierPortalSessionRecoveryResult(
        _scriptResultContains(capability, 'no-login-form')
            ? SupplierPortalSessionRecoveryStatus.loginPageUnavailable
            : SupplierPortalSessionRecoveryStatus.interactionRequired,
      );
    }

    final credential = await resolveCredential(
      supplierId: supplierId,
      origin: origin,
    );
    if (credential == null) {
      return const SupplierPortalSessionRecoveryResult(
        SupplierPortalSessionRecoveryStatus.credentialUnavailable,
      );
    }
    if (credential.supplierId != supplierId || credential.origin != origin) {
      return const SupplierPortalSessionRecoveryResult(
        SupplierPortalSessionRecoveryStatus.rejected,
      );
    }
    if (normalizeSupplierBrowserOrigin(await currentUrl()) != origin) {
      return const SupplierPortalSessionRecoveryResult(
        SupplierPortalSessionRecoveryStatus.rejected,
      );
    }

    final submitted = await submitLogin(
      browserCredentialFillScript(
        expectedOrigin: origin,
        username: credential.username,
        password: credential.password,
        autoSubmit: true,
        allowInsecureSupplierOrigin: false,
      ),
    );
    return SupplierPortalSessionRecoveryResult(
      _scriptResultContains(submitted, 'filled-and-submitted')
          ? SupplierPortalSessionRecoveryStatus.submitted
          : SupplierPortalSessionRecoveryStatus.interactionRequired,
    );
  } catch (_) {
    return const SupplierPortalSessionRecoveryResult(
      SupplierPortalSessionRecoveryStatus.loginPageUnavailable,
    );
  }
}

bool _scriptResultContains(Object? result, String expected) =>
    result?.toString().contains(expected) == true;

/// Qué hace el buscador cuando la recuperación de sesión termina.
///
/// **Por qué existe como pieza aparte.** La decisión vive dentro de
/// `_runNeedSearch`, que abre un WebView real contra el portal del proveedor:
/// no se puede ejercitar en una prueba sin red ni sin navegador. Sacarla acá la
/// deja demostrable, y el runner queda con una sola forma de decidirlo en vez
/// de tres condiciones sueltas repetidas.
enum SupplierPortalSessionOutcome {
  /// La sesión sirve: se sigue recorriendo el catálogo.
  continueRun,

  /// Se envió el ingreso: se puede reintentar la búsqueda.
  retryAfterLogin,

  /// **Sólo una persona puede resolverlo.** El portal de RBX publica su
  /// ingreso por HTTPS pero su formulario legacy envía por HTTP, y el
  /// preflight se niega por contrato a mandar el secreto en claro. Entonces
  /// esto no es un «todavía no»: no se enumera, no se guarda recibo, y la
  /// superficie ofrece abrir el portal.
  needsPerson,
}

SupplierPortalSessionOutcome supplierPortalSessionOutcome(
  SupplierPortalSessionRecoveryStatus status,
) =>
    switch (status) {
      SupplierPortalSessionRecoveryStatus.submitted =>
        SupplierPortalSessionOutcome.retryAfterLogin,
      SupplierPortalSessionRecoveryStatus.interactionRequired =>
        SupplierPortalSessionOutcome.needsPerson,
      _ => SupplierPortalSessionOutcome.continueRun,
    };

/// Si con este desenlace todavía se puede recorrer el catálogo.
bool supplierPortalRunMayContinue(SupplierPortalSessionOutcome outcome) =>
    outcome != SupplierPortalSessionOutcome.needsPerson;

/// Si con este desenlace tiene sentido escribir un recibo.
///
/// Una corrida que sólo puede terminar con una persona no trae filas y su
/// cobertura no afirma nada: guardarla cuesta —medido el 2026-08-30, dos
/// minutos de gateway— para dejar un recibo vacío.
bool supplierPortalRunShouldRecord(SupplierPortalSessionOutcome outcome) =>
    outcome != SupplierPortalSessionOutcome.needsPerson;
