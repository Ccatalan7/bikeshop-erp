import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/browser_supplier_credential_resolver.dart';
import 'package:vinabike_erp/shared/services/supplier_portal_session_recovery.dart';

void main() {
  _decisionDelBuscador();
  const supplierId = 'supplier-rbx';
  const loginUrl = 'https://supplier.example/login';
  const origin = 'https://supplier.example';

  BrowserSupplierCredential credential({
    String resolvedSupplierId = supplierId,
    String resolvedOrigin = origin,
  }) =>
      BrowserSupplierCredential(
        tenantId: 'tenant-1',
        supplierId: resolvedSupplierId,
        credentialKey: 'default',
        origin: resolvedOrigin,
        username: 'buyer@example.com',
        password: 'secret-value',
        updatedAt: DateTime.utc(2026, 8, 28),
      );

  test('preflights exact HTTPS login before revealing and submitting',
      () async {
    final events = <String>[];
    var current = loginUrl;

    final result = await recoverSupplierPortalSession(
      supplierId: supplierId,
      loginUrl: loginUrl,
      resolveCredential: ({required supplierId, required origin}) async {
        events.add('resolve:$supplierId:$origin');
        return credential();
      },
      loadLoginPage: (url) async {
        events.add('load:$url');
        current = url;
      },
      currentUrl: () async => current,
      evaluateJavascript: (source) async {
        events.add('preflight');
        expect(source, contains(origin));
        expect(source, isNot(contains('secret-value')));
        return 'safe-to-submit';
      },
      submitLogin: (source) async {
        events.add('submit');
        expect(source, contains('buyer@example.com'));
        expect(source, contains('secret-value'));
        return 'filled-and-submitted';
      },
    );

    expect(result.status, SupplierPortalSessionRecoveryStatus.submitted);
    expect(
      events,
      <String>[
        'load:$loginUrl',
        'preflight',
        'resolve:$supplierId:$origin',
        'submit',
      ],
    );
  });

  test('never reveals a credential for an insecure or challenged form',
      () async {
    var resolved = false;
    var submitted = false;

    final result = await recoverSupplierPortalSession(
      supplierId: supplierId,
      loginUrl: loginUrl,
      resolveCredential: ({required supplierId, required origin}) async {
        resolved = true;
        return credential();
      },
      loadLoginPage: (_) async {},
      currentUrl: () async => loginUrl,
      evaluateJavascript: (_) async => 'insecure-action',
      submitLogin: (_) async {
        submitted = true;
        return 'filled-and-submitted';
      },
    );

    expect(
      result.status,
      SupplierPortalSessionRecoveryStatus.interactionRequired,
    );
    expect(resolved, isFalse);
    expect(submitted, isFalse);
  });

  test('rejects a credential whose supplier binding changed', () async {
    var submitted = false;

    final result = await recoverSupplierPortalSession(
      supplierId: supplierId,
      loginUrl: loginUrl,
      resolveCredential: ({required supplierId, required origin}) async =>
          credential(resolvedSupplierId: 'another-supplier'),
      loadLoginPage: (_) async {},
      currentUrl: () async => loginUrl,
      evaluateJavascript: (_) async => 'safe-to-submit',
      submitLogin: (_) async {
        submitted = true;
        return 'filled-and-submitted';
      },
    );

    expect(result.status, SupplierPortalSessionRecoveryStatus.rejected);
    expect(submitted, isFalse);
  });

  test('requires a configured HTTPS login URL and resolver', () async {
    Future<SupplierPortalSessionRecoveryResult> recover(String? url) =>
        recoverSupplierPortalSession(
          supplierId: supplierId,
          loginUrl: url,
          resolveCredential: ({required supplierId, required origin}) async =>
              credential(),
          loadLoginPage: (_) async => fail('must not load'),
          currentUrl: () async => fail('must not read URL'),
          evaluateJavascript: (_) async => fail('must not evaluate'),
          submitLogin: (_) async => fail('must not submit'),
        );

    expect(
      (await recover(null)).status,
      SupplierPortalSessionRecoveryStatus.notConfigured,
    );
    expect(
      (await recover('http://supplier.example/login')).status,
      SupplierPortalSessionRecoveryStatus.notConfigured,
    );
  });
}

/// Qué hace el buscador con cada desenlace de la recuperación.
///
/// **El defecto que fija.** El runner sólo miraba `result.submitted`, así que
/// `interactionRequired` era indistinguible de un fallo transitorio: seguía
/// enumerando el catálogo y terminaba intentando guardar un recibo vacío. Con
/// el gateway degradado eso costó **125 s de spinner** —medido el
/// 2026-08-30— para acabar en sesión vencida igual.
///
/// Para RBX ese desenlace es **permanente**, no un «todavía no»: su ingreso se
/// publica por HTTPS pero el formulario legacy envía por HTTP, y el preflight
/// se niega por contrato a mandar el secreto en claro. Confirmado en la
/// ventana real: al abrir el formulario la barra pasa a `http://` con el
/// candado tachado.
void _decisionDelBuscador() {
  group('el desenlace de la sesión decide si la corrida sigue', () {
    test('interactionRequired NO enumera y NO escribe recibo', () {
      const outcome = SupplierPortalSessionOutcome.needsPerson;

      expect(
        supplierPortalSessionOutcome(
          SupplierPortalSessionRecoveryStatus.interactionRequired,
        ),
        outcome,
      );
      // Las dos consecuencias, dichas por separado porque son dos costos
      // distintos: seguir recorriendo el portal, y pagar el guardado.
      expect(
        supplierPortalRunMayContinue(outcome),
        isFalse,
        reason: 'enumerar un catálogo sin sesión no puede traer nada',
      );
      expect(
        supplierPortalRunShouldRecord(outcome),
        isFalse,
        reason: 'un recibo vacío cuesta y no dice nada',
      );
    });

    test('una sesión enviada sí reintenta la búsqueda', () {
      final outcome = supplierPortalSessionOutcome(
        SupplierPortalSessionRecoveryStatus.submitted,
      );
      expect(outcome, SupplierPortalSessionOutcome.retryAfterLogin);
      expect(supplierPortalRunMayContinue(outcome), isTrue);
      expect(supplierPortalRunShouldRecord(outcome), isTrue);
    });

    test('cualquier otro desenlace deja seguir la corrida', () {
      // Un portal que no necesitaba recuperación, o un intento que no llegó a
      // pedir interacción: la corrida continúa y su resultado se guarda.
      for (final status in SupplierPortalSessionRecoveryStatus.values.where(
        (value) =>
            value != SupplierPortalSessionRecoveryStatus.interactionRequired &&
            value != SupplierPortalSessionRecoveryStatus.submitted,
      )) {
        final outcome = supplierPortalSessionOutcome(status);
        expect(
          outcome,
          SupplierPortalSessionOutcome.continueRun,
          reason: 'el desenlace $status no puede cortar la corrida',
        );
        expect(supplierPortalRunMayContinue(outcome), isTrue);
        expect(supplierPortalRunShouldRecord(outcome), isTrue);
      }
    });
  });
}
