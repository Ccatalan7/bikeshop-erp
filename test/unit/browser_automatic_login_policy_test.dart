import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/browser_automatic_login_policy.dart';

/// Cuándo el navegador del ERP entra solo a un portal de proveedor.
///
/// Reemplaza la regla «un envío automático por origen y por pestaña», que
/// dejaba al operador un clic por cada sesión vencida.
void main() {
  const origin = 'https://portal.rburgos.cl';

  late DateTime clock;
  late BrowserAutomaticLoginPolicy policy;

  setUp(() {
    clock = DateTime(2026, 9, 2, 9, 0);
    policy = BrowserAutomaticLoginPolicy(now: () => clock);
  });

  void advance(Duration by) => clock = clock.add(by);

  test('la primera vez que aparece el formulario se envía solo', () {
    expect(
      policy.observeLoad(origin, hasLoginForm: true),
      BrowserAutomaticLoginObservation.loginFormSeen,
    );
    expect(policy.decide(origin), BrowserAutomaticLoginDecision.submit);
  });

  test('una sesión vencida vuelve a entrar sola, no sólo la primera vez', () {
    policy.observeLoad(origin, hasLoginForm: true);
    policy.recordAutomaticSubmit(origin);
    advance(const Duration(seconds: 3));
    expect(
      policy.observeLoad(origin, hasLoginForm: false),
      BrowserAutomaticLoginObservation.loginSucceeded,
    );

    // Media jornada después el portal cierra la sesión.
    advance(const Duration(hours: 4));
    expect(
      policy.observeLoad(origin, hasLoginForm: true),
      BrowserAutomaticLoginObservation.loginFormSeen,
    );
    expect(policy.decide(origin), BrowserAutomaticLoginDecision.submit);
  });

  test('si el portal devuelve el formulario enseguida, se deja de insistir',
      () {
    policy.observeLoad(origin, hasLoginForm: true);
    policy.recordAutomaticSubmit(origin);
    advance(const Duration(seconds: 2));

    expect(
      policy.observeLoad(origin, hasLoginForm: true),
      BrowserAutomaticLoginObservation.loginFailed,
    );
    expect(policy.decide(origin), BrowserAutomaticLoginDecision.fillOnly);
    expect(policy.isBlocked(origin), isTrue);

    // Mientras dure el freno, cada recarga sólo rellena.
    advance(const Duration(minutes: 3));
    policy.observeLoad(origin, hasLoginForm: true);
    expect(policy.decide(origin), BrowserAutomaticLoginDecision.fillOnly);
  });

  test('el freno se levanta solo pasado el tiempo de espera', () {
    policy.observeLoad(origin, hasLoginForm: true);
    policy.recordAutomaticSubmit(origin);
    advance(const Duration(seconds: 2));
    policy.observeLoad(origin, hasLoginForm: true);
    expect(policy.decide(origin), BrowserAutomaticLoginDecision.fillOnly);

    advance(const Duration(minutes: 11));
    policy.observeLoad(origin, hasLoginForm: true);
    expect(policy.decide(origin), BrowserAutomaticLoginDecision.submit);
    expect(policy.isBlocked(origin), isFalse);
  });

  test('un ingreso manual que entra levanta el freno; uno rechazado lo pone',
      () {
    policy.observeLoad(origin, hasLoginForm: true);
    policy.recordAutomaticSubmit(origin);
    advance(const Duration(seconds: 2));
    policy.observeLoad(origin, hasLoginForm: true);
    expect(policy.decide(origin), BrowserAutomaticLoginDecision.fillOnly);

    // El operador corrige y envía a mano: entra.
    policy.recordManualSubmit(origin);
    advance(const Duration(seconds: 3));
    expect(
      policy.observeLoad(origin, hasLoginForm: false),
      BrowserAutomaticLoginObservation.loginSucceeded,
    );
    expect(policy.isBlocked(origin), isFalse);

    // Más tarde vence y el envío automático vuelve a estar disponible.
    advance(const Duration(hours: 1));
    policy.observeLoad(origin, hasLoginForm: true);
    expect(policy.decide(origin), BrowserAutomaticLoginDecision.submit);

    // Un envío manual rechazado tampoco se repite solo.
    policy.recordManualSubmit(origin);
    advance(const Duration(seconds: 2));
    expect(
      policy.observeLoad(origin, hasLoginForm: true),
      BrowserAutomaticLoginObservation.loginFailed,
    );
    expect(policy.decide(origin), BrowserAutomaticLoginDecision.fillOnly);
  });

  test(
      'un formulario que vuelve mucho después del envío no cuenta como rechazo',
      () {
    policy.observeLoad(origin, hasLoginForm: true);
    policy.recordAutomaticSubmit(origin);
    // Nada cargó en el origen durante media hora (por ejemplo, la pestaña
    // quedó en otro sitio) y al volver la sesión ya venció.
    advance(const Duration(minutes: 30));
    expect(
      policy.observeLoad(origin, hasLoginForm: true),
      BrowserAutomaticLoginObservation.loginFormSeen,
    );
    expect(policy.decide(origin), BrowserAutomaticLoginDecision.submit);
  });

  test('cada origen lleva su propia cuenta', () {
    const other = 'https://b2b.comercialciclo.cl';
    policy.observeLoad(origin, hasLoginForm: true);
    policy.recordAutomaticSubmit(origin);
    advance(const Duration(seconds: 1));
    policy.observeLoad(origin, hasLoginForm: true);
    expect(policy.decide(origin), BrowserAutomaticLoginDecision.fillOnly);

    policy.observeLoad(other, hasLoginForm: true);
    expect(policy.decide(other), BrowserAutomaticLoginDecision.submit);
  });

  test('un envío queda pendiente hasta que una carga cuente su desenlace', () {
    expect(policy.originsAwaitingOutcome, isEmpty);
    policy.observeLoad(origin, hasLoginForm: true);
    policy.recordAutomaticSubmit(origin);
    expect(policy.originsAwaitingOutcome, [origin]);

    // La página de éxito puede vivir en otro host; el host la reporta igual.
    advance(const Duration(seconds: 2));
    expect(
      policy.observeLoad(origin, hasLoginForm: false),
      BrowserAutomaticLoginObservation.loginSucceeded,
    );
    expect(policy.originsAwaitingOutcome, isEmpty);
  });

  test('el keep-alive salta la respuesta al POST y toma la página siguiente',
      () {
    const action =
        'http://www.rburgos.cl/sitio/aplicaciones/valida_ingreso.asp';
    const landing =
        'http://www.rburgos.cl/sitio/aplicaciones/index_cliente.asp';
    policy.observeLoad(origin, hasLoginForm: true);
    policy.recordAutomaticSubmit(origin, actionUrl: action);
    expect(policy.originsWantingKeepAlive, isEmpty);

    // La primera carga es la respuesta al POST: entró, pero esa URL no se
    // repite por GET.
    advance(const Duration(seconds: 4));
    expect(
      policy.observeLoad(origin, hasLoginForm: false),
      BrowserAutomaticLoginObservation.loginSucceeded,
    );
    expect(policy.originsWantingKeepAlive, [origin]);
    expect(policy.keepAliveTargetAfterLoad(origin, action), isNull);
    expect(policy.originsWantingKeepAlive, [origin]);

    // La página siguiente sí, y una sola vez por ingreso.
    expect(policy.keepAliveTargetAfterLoad(origin, landing), landing);
    expect(policy.originsWantingKeepAlive, isEmpty);
    expect(policy.keepAliveTargetAfterLoad(origin, landing), isNull);
  });

  test('sin destino conocido, la primera página tras entrar se mantiene viva',
      () {
    const landing = 'https://b2b.comercialciclo.cl/inicio';
    policy.observeLoad('https://b2b.comercialciclo.cl', hasLoginForm: true);
    policy.recordManualSubmit('https://b2b.comercialciclo.cl');
    advance(const Duration(seconds: 2));
    policy.observeLoad('https://b2b.comercialciclo.cl', hasLoginForm: false);
    expect(
      policy.keepAliveTargetAfterLoad('https://b2b.comercialciclo.cl', landing),
      landing,
    );
    // Sin ingreso reciente no hay nada que mantener.
    expect(policy.keepAliveTargetAfterLoad(origin, landing), isNull);
  });

  test('tras entrar solo, la pestaña vuelve a la ficha que venía a abrir', () {
    const product = 'https://mkr.cl/store/category/todos?q=C1530&stock=1';
    policy.setIntendedDestination(product);

    // El portal desvió la ficha al login; el navegador entró y cayó en
    // la portada de la tienda.
    policy.observeLoad('https://mkr.cl', hasLoginForm: true);
    policy.recordAutomaticSubmit('https://mkr.cl');
    advance(const Duration(seconds: 3));
    final observation =
        policy.observeLoad('https://mkr.cl', hasLoginForm: false);
    expect(observation, BrowserAutomaticLoginObservation.loginSucceeded);
    expect(
      policy.consumeIntendedDestination(
        origin: 'https://mkr.cl',
        loadedUrl: 'https://mkr.cl/store',
        afterLogin: true,
      ),
      product,
    );
    // Una sola vez.
    expect(policy.intendedDestination, isNull);
    expect(
      policy.consumeIntendedDestination(
        origin: 'https://mkr.cl',
        loadedUrl: 'https://mkr.cl/store',
        afterLogin: true,
      ),
      isNull,
    );
  });

  test('si la ficha carga directo, o el ingreso es de otro sitio, no se vuelve',
      () {
    const product = 'https://mkr.cl/store/category/todos?q=C1530&stock=1';
    policy.setIntendedDestination(product);
    // Llegó sin login: se da por cumplido.
    expect(
      policy.consumeIntendedDestination(
        origin: 'https://mkr.cl',
        loadedUrl: product,
        afterLogin: false,
      ),
      isNull,
    );
    expect(policy.intendedDestination, isNull);

    policy.setIntendedDestination(product);
    // Un ingreso en otro portal no tiene nada que ver con esta ficha.
    expect(
      policy.consumeIntendedDestination(
        origin: origin,
        loadedUrl: 'http://www.rburgos.cl/sitio/aplicaciones/index_cliente.asp',
        afterLogin: true,
      ),
      isNull,
    );
    expect(policy.intendedDestination, product);
    // Una carga sin ingreso de por medio tampoco la consume.
    expect(
      policy.consumeIntendedDestination(
        origin: 'https://mkr.cl',
        loadedUrl: 'https://mkr.cl/store',
        afterLogin: false,
      ),
      isNull,
    );
    expect(policy.intendedDestination, product);
  });

  test('la página de éxito se atribuye al portal sólo si es el mismo sitio',
      () {
    expect(
      browserAddressesShareSupplierSite(
        'https://portal.rburgos.cl',
        'http://www.rburgos.cl/sitio/aplicaciones/index_cliente.asp',
      ),
      isTrue,
    );
    expect(
      browserAddressesShareSupplierSite(
        'https://portal.rburgos.cl',
        'https://www.google.com/',
      ),
      isFalse,
    );
    expect(browserAddressesShareSupplierSite('nada', 'https://a.cl'), isFalse);
    expect(
      browserAddressesShareSupplierSite(
          'https://localhost', 'https://localhost'),
      isFalse,
    );
  });

  test('olvidar el origen borra el freno y el envío pendiente', () {
    policy.observeLoad(origin, hasLoginForm: true);
    policy.recordAutomaticSubmit(origin);
    advance(const Duration(seconds: 1));
    policy.observeLoad(origin, hasLoginForm: true);
    expect(policy.isBlocked(origin), isTrue);

    policy.forget(origin);
    expect(policy.isBlocked(origin), isFalse);
    expect(
      policy.observeLoad(origin, hasLoginForm: false),
      BrowserAutomaticLoginObservation.none,
    );
    expect(policy.decide(origin), BrowserAutomaticLoginDecision.submit);
  });
}
