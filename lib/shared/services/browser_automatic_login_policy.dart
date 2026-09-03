import 'package:flutter/foundation.dart';

/// Qué hace el navegador del ERP cuando vuelve a ver el formulario de ingreso
/// de un portal cuya credencial ya conoce.
enum BrowserAutomaticLoginDecision {
  /// Rellenar y enviar solo.
  submit,

  /// Rellenar y dejar el envío al operador.
  fillOnly,
}

/// Lo que una carga de página le enseñó a la política, para que el host pueda
/// reaccionar (por ejemplo, mantener viva una sesión recién probada).
enum BrowserAutomaticLoginObservation {
  /// Nada que aprender: página sin formulario y sin envío pendiente.
  none,

  /// Un envío (automático o manual) terminó en una página sin formulario de
  /// ingreso: la sesión está abierta.
  loginSucceeded,

  /// El formulario volvió a aparecer justo después de un envío: el portal lo
  /// rechazó, o pide algo más. Se deja de insistir por un rato.
  loginFailed,

  /// Hay formulario y se puede volver a intentar.
  loginFormSeen,
}

/// Decide cuándo el navegador embebido inicia sesión solo en un portal de
/// proveedor, cuándo se limita a rellenar, y qué página mantener viva después.
///
/// **El defecto que reemplaza.** La regla anterior era «un envío automático
/// por origen y por pestaña»: la primera vez el portal entraba solo, y cuando
/// la sesión vencía —por inactividad del servidor, o porque el portal usa
/// cookies de sesión que WebKit no conserva al cerrar la app— el formulario
/// volvía a aparecer sólo rellenado y el clic quedaba para el operador. Una
/// pestaña de portal vive toda la jornada, así que en la práctica el ingreso
/// automático servía una vez al día.
///
/// **La regla nueva.** Cada vez que el formulario aparece se envía solo,
/// salvo que el envío anterior haya fallado: si tras enviar (automático o
/// manual) el formulario vuelve dentro de [failureWindow], el portal rechazó
/// el ingreso o pide algo más —CAPTCHA, OTP, clave vencida— y se deja de
/// insistir durante [failureCooldown]. Un ingreso que sí entró (una carga
/// sin formulario en el sitio del proveedor) vuelve a habilitar el envío
/// automático para la próxima vez que la sesión venza. Así se conserva el
/// freno que exige el contrato del navegador —«must stop at … a failed
/// repeated login»— sin pedirle al operador un clic por cada sesión vencida.
///
/// **Qué página se mantiene viva.** La primera carga tras el envío suele ser
/// la respuesta al POST del formulario (RBX: `valida_ingreso.asp`). Repetirla
/// por GET sin campos podría cerrar la sesión en vez de mantenerla, así que
/// [keepAliveTargetAfterLoad] la salta y espera la primera página real del
/// sitio que la siga.
///
/// Es una clase pura: sin reloj propio, sin WebView, sin secretos. El host
/// (la pestaña del navegador) le cuenta lo que ve y ella responde.
class BrowserAutomaticLoginPolicy {
  BrowserAutomaticLoginPolicy({
    DateTime Function()? now,
    this.failureWindow = const Duration(seconds: 90),
    this.failureCooldown = const Duration(minutes: 10),
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// Si el formulario vuelve dentro de este plazo tras un envío, fue rechazo.
  final Duration failureWindow;

  /// Cuánto se deja de enviar solo después de un rechazo.
  final Duration failureCooldown;

  final Map<String, _OriginLoginState> _states = <String, _OriginLoginState>{};

  _OriginLoginState _state(String origin) =>
      _states.putIfAbsent(origin, _OriginLoginState.new);

  /// Registra una carga terminada en [origin] y devuelve qué se aprendió.
  ///
  /// Se llama en cada carga del origen, con o sin formulario: la ausencia de
  /// formulario después de un envío es justamente la prueba de que entró.
  BrowserAutomaticLoginObservation observeLoad(
    String origin, {
    required bool hasLoginForm,
  }) {
    final state = _state(origin);
    final now = _now();
    final pendingSubmit = state.lastSubmitAt;

    if (!hasLoginForm) {
      if (pendingSubmit == null) return BrowserAutomaticLoginObservation.none;
      state
        ..lastSubmitAt = null
        ..blockedUntil = null
        ..keepAliveWanted = true;
      return BrowserAutomaticLoginObservation.loginSucceeded;
    }

    if (pendingSubmit != null) {
      state.lastSubmitAt = null;
      if (now.difference(pendingSubmit) <= failureWindow) {
        state.blockedUntil = now.add(failureCooldown);
        return BrowserAutomaticLoginObservation.loginFailed;
      }
      // Un formulario que vuelve mucho después del envío no es un rechazo:
      // la sesión duró y venció. Se puede volver a entrar.
    }
    return BrowserAutomaticLoginObservation.loginFormSeen;
  }

  /// Qué hacer con el formulario que acaba de verse en [origin].
  BrowserAutomaticLoginDecision decide(String origin) {
    final blockedUntil = _state(origin).blockedUntil;
    if (blockedUntil != null && _now().isBefore(blockedUntil)) {
      return BrowserAutomaticLoginDecision.fillOnly;
    }
    return BrowserAutomaticLoginDecision.submit;
  }

  /// El navegador envió el formulario solo. [actionUrl] es el destino exacto
  /// del formulario, si se conoce: la página que responde a ese POST no se
  /// usará para mantener viva la sesión.
  void recordAutomaticSubmit(String origin, {String? actionUrl}) {
    _state(origin)
      ..lastSubmitAt = _now()
      ..submittedActionUrl = _cleanUrl(actionUrl);
  }

  /// El operador envió el formulario a mano. Cuenta igual que un envío
  /// automático: si el portal lo devuelve, tampoco se insiste solo.
  void recordManualSubmit(String origin, {String? actionUrl}) {
    _state(origin)
      ..lastSubmitAt = _now()
      ..blockedUntil = null
      ..submittedActionUrl = _cleanUrl(actionUrl);
  }

  /// Tras una carga sin formulario en el sitio del portal: la URL que se debe
  /// mantener viva, o `null` si todavía no corresponde (no hay sesión recién
  /// abierta, o la carga es la respuesta al POST del ingreso y hay que esperar
  /// la página siguiente). Devuelve la URL una sola vez por ingreso.
  String? keepAliveTargetAfterLoad(String origin, String loadedUrl) {
    final state = _state(origin);
    if (!state.keepAliveWanted) return null;
    final loaded = _cleanUrl(loadedUrl);
    if (loaded == null || loaded == state.submittedActionUrl) return null;
    state.keepAliveWanted = false;
    return loaded;
  }

  String? _intendedDestination;

  /// La página que esta pestaña venía a abrir (por ejemplo, la ficha de un
  /// producto en el portal). Si el portal la desvía a su formulario de ingreso
  /// y el navegador entra solo, después vuelve a ella una sola vez.
  void setIntendedDestination(String? url) {
    _intendedDestination = _cleanUrl(url);
  }

  @visibleForTesting
  String? get intendedDestination => _intendedDestination;

  /// Se llama en cada carga sin formulario dentro del sitio del portal.
  ///
  /// Devuelve el destino que hay que cargar ahora, o `null`: cuando no había
  /// destino, cuando la carga ya es el destino (se da por cumplido), cuando
  /// no hubo ingreso de por medio, o cuando la carga es de otro sitio.
  String? consumeIntendedDestination({
    required String origin,
    required String loadedUrl,
    required bool afterLogin,
  }) {
    final destination = _intendedDestination;
    if (destination == null) return null;
    if (_cleanUrl(loadedUrl) == destination) {
      _intendedDestination = null;
      return null;
    }
    if (!afterLogin) return null;
    if (!browserAddressesShareSupplierSite(origin, destination) &&
        !browserAddressesShareSupplierSite(loadedUrl, destination)) {
      return null;
    }
    _intendedDestination = null;
    return destination;
  }

  /// Orígenes con un envío del que todavía no se sabe el desenlace.
  ///
  /// Un portal legacy puede aterrizar tras el ingreso en otro host (RBX entra
  /// por `portal.rburgos.cl` y sigue en `www.rburgos.cl`): el host mira esa
  /// carga ajena y, si no trae formulario, se la reporta a estos orígenes.
  Iterable<String> get originsAwaitingOutcome => _states.entries
      .where((entry) => entry.value.lastSubmitAt != null)
      .map((entry) => entry.key);

  /// Orígenes que ya entraron y todavía esperan una página que mantener viva.
  Iterable<String> get originsWantingKeepAlive => _states.entries
      .where((entry) => entry.value.keepAliveWanted)
      .map((entry) => entry.key);

  /// Se olvidó la credencial del origen o se limpiaron sus datos.
  void forget(String origin) => _states.remove(origin);

  @visibleForTesting
  bool isBlocked(String origin) {
    final blockedUntil = _states[origin]?.blockedUntil;
    return blockedUntil != null && _now().isBefore(blockedUntil);
  }

  static String? _cleanUrl(String? url) {
    final trimmed = url?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _OriginLoginState {
  DateTime? lastSubmitAt;
  DateTime? blockedUntil;
  String? submittedActionUrl;
  bool keepAliveWanted = false;
}

/// Si dos direcciones pertenecen al mismo sitio de proveedor.
///
/// Compara las dos últimas etiquetas del host (`rburgos.cl`), que es lo que
/// comparten `portal.rburgos.cl` y `www.rburgos.cl`. Sirve para atribuir la
/// página que sigue a un ingreso al portal que lo pidió, y no a otro sitio al
/// que el operador haya saltado justo después. No es un resolutor de sufijos
/// públicos: para los portales de este ERP (`.cl`, `.com`) basta, y ante un
/// host raro falla cerrado.
bool browserAddressesShareSupplierSite(String a, String b) {
  final hostA = Uri.tryParse(a.trim())?.host.toLowerCase() ?? '';
  final hostB = Uri.tryParse(b.trim())?.host.toLowerCase() ?? '';
  if (hostA.isEmpty || hostB.isEmpty) return false;
  final labelsA = hostA.split('.');
  final labelsB = hostB.split('.');
  if (labelsA.length < 2 || labelsB.length < 2) return false;
  return labelsA.sublist(labelsA.length - 2).join('.') ==
      labelsB.sublist(labelsB.length - 2).join('.');
}
