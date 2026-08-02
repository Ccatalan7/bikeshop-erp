import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_method_sheet.dart';
import 'package:vinabike_erp/shared/models/current_user_profile.dart';
import 'package:vinabike_erp/shared/services/current_user_profile_service.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// **5k · el estado de SÓLO LECTURA, que sí tiene owner canónico.**
///
/// El estado de *permiso* que dibuja `5k` («Tu rol: Asistente») sigue abierto y
/// no se inventa acá: no hay rótulo de rol que leer. Lo que sí es canónico —y
/// lo que esta prueba fija— es la **capacidad booleana**: la base separa
/// `can_manage_tenant_hr` (escribir la ficha) de `can_manage_tenant_payroll`
/// (operar Nóminas y leerla). Traducido al negocio: un contador abre esta hoja
/// y **no puede guardarla**.
///
/// La rama `readOnly` existía sin una sola prueba —el único aserto del
/// repositorio pasaba `editable`—, así que un refactor podía volver editable la
/// hoja de quien no puede escribir y toda la batería seguía verde. Se asienta
/// por **conducta**, no leyendo el código de la superficie.
/// El control canónico `S-05` del tipo de cuenta, por su identidad estable.
final Finder _accountTypeSelect =
    find.byKey(const ValueKey<String>('payroll-method-account-type'));

void main() {
  const transfer = PayrollMethodOption(
      id: 'm-transfer', code: 'transfer', name: 'Transferencia');
  const cash =
      PayrollMethodOption(id: 'm-cash', code: 'cash', name: 'Efectivo');

  Widget host(PayrollMethodAuthority authority, {String? selected}) {
    return MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.light,
      ),
      home: Scaffold(
        body: Center(
          child: PayrollMethodSheet(
            employeeName: 'Vicente Díaz',
            options: const <PayrollMethodOption>[transfer, cash],
            authority: authority,
            returnLabel: 'Vuelves a la lista de la semana',
            confirmLabel: 'Guardar método',
            selectedMethodId: selected ?? cash.id,
          ),
        ),
      ),
    );
  }

  group('5k · sólo lectura de la hoja de método', () {
    testWidgets('sin capacidad no hay guardar, y la salida se llama Cerrar',
        (tester) async {
      await tester.pumpWidget(host(PayrollMethodAuthority.readOnly));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('payroll-method-save')),
        findsNothing,
        reason: 'sin capacidad de escritura la hoja no ofrece guardar',
      );
      expect(find.text('Cerrar'), findsOneWidget);
      expect(find.text('Cancelar'), findsNothing);
    });

    testWidgets('el motivo se dice una vez, con el owner compartido',
        (tester) async {
      await tester.pumpWidget(host(PayrollMethodAuthority.readOnly));
      await tester.pumpAndSettle();

      // El aviso es `E-04 · VbNotice` bajo su key estable: se comprueba que
      // está y que **explica**, no que el texto sea una cadena concreta.
      expect(
        find.byKey(const ValueKey<String>('payroll-method-read-only')),
        findsOneWidget,
      );
      expect(find.text('Puedes ver esta ficha, no cambiarla'), findsOneWidget);
    });

    // `Efectivo` entra seleccionado y NO dibuja campos de cuenta;
    // `Transferencia` sí. Esa diferencia es el detector: si el toque mueve la
    // selección, aparecen los campos. Se afirma por los DOS lados —el control
    // positivo de abajo comprueba que el detector de verdad dispara—, porque
    // «no hay campos» se cumple solo también cuando no hay nada montado.
    testWidgets('tocar otra opción NO cambia la selección', (tester) async {
      await tester.pumpWidget(host(PayrollMethodAuthority.readOnly));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text('Transferencia'));
      await tester.pumpAndSettle();

      expect(
        find.byType(TextField),
        findsNothing,
        reason: 'la selección no se movió: Transferencia no abrió sus campos',
      );
      expect(
        find.byKey(const ValueKey<String>('payroll-method-save')),
        findsNothing,
        reason: 'la hoja sigue sin guardar después del toque',
      );
    });

    testWidgets('control positivo: con capacidad el mismo toque SÍ mueve',
        (tester) async {
      await tester.pumpWidget(host(PayrollMethodAuthority.editable));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text('Transferencia'));
      await tester.pumpAndSettle();

      expect(
        find.byType(TextField),
        findsWidgets,
        reason: 'el detector dispara: sin la valla, el toque abre los campos',
      );
    });

    testWidgets('con capacidad sí se puede guardar, y el aviso calla',
        (tester) async {
      await tester.pumpWidget(host(PayrollMethodAuthority.editable));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('payroll-method-save')),
        findsOneWidget,
      );
      expect(find.text('Cancelar'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('payroll-method-read-only')),
        findsNothing,
      );
    });

    // Con `Transferencia` ya elegida la hoja SÍ dibuja banco/tipo/número. Es el
    // caso que de verdad importa —los tres campos que escriben el dato con el
    // que se gira el sueldo— y el que el resto de las pruebas no tocaba,
    // porque entraban con `Efectivo`.
    testWidgets(
        'readOnly con Transferencia: banco, tipo y número inhabilitados',
        (tester) async {
      await tester.pumpWidget(
        host(PayrollMethodAuthority.readOnly, selected: transfer.id),
      );
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2),
          reason: 'banco y número están dibujados');
      for (final element in fields.evaluate()) {
        expect((element.widget as TextField).enabled, isFalse);
      }

      // El TIPO no es un `TextField`: es `S-05` bajo su key estable. Se toca
      // **el control**, no el rótulo, y se comprueba que **no abre su lista** —
      // `Cuenta de Ahorro` sólo existe dentro del desplegable, nunca en el
      // campo cerrado, así que su ausencia es prueba de que no se abrió.
      await tester.tap(_accountTypeSelect);
      await tester.pumpAndSettle();
      expect(
        find.text('Cuenta de Ahorro'),
        findsNothing,
        reason: 'el selector de tipo abrió su lista estando en sólo lectura',
      );
      expect(
        find.byKey(const ValueKey<String>('payroll-method-save')),
        findsNothing,
        reason: 'la hoja sigue sin ofrecer guardar',
      );
    });

    testWidgets('control positivo: editable, el mismo toque SÍ abre el TIPO',
        (tester) async {
      await tester.pumpWidget(
        host(PayrollMethodAuthority.editable, selected: transfer.id),
      );
      await tester.pumpAndSettle();

      await tester.tap(_accountTypeSelect);
      await tester.pumpAndSettle();

      expect(
        find.text('Cuenta de Ahorro'),
        findsOneWidget,
        reason: 'el detector dispara: sin la valla el selector despliega',
      );
    });

    testWidgets('control positivo: editable con Transferencia SÍ deja escribir',
        (tester) async {
      await tester.pumpWidget(
        host(PayrollMethodAuthority.editable, selected: transfer.id),
      );
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      for (final element in fields.evaluate()) {
        expect(
          (element.widget as TextField).enabled,
          isTrue,
          reason: 'sin la valla los tres campos son escribibles',
        );
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // La UNIÓN: perfil de sesión → capacidad → autoridad.
  //
  // Inyectar el enum prueba la hoja, no la decisión. Esto recorre la misma
  // función que llama `payroll_redesign_page.dart`, con un servicio de perfil
  // real puesto en cada estado.
  // ─────────────────────────────────────────────────────────────────────────
  group('5k · la autoridad se deriva del perfil, no se asume', () {
    // `payrollMethodAuthorityFor` es **la misma función** que llama
    // `payroll_redesign_page.dart`, y recibe el servicio entero: acá no se
    // reescribe ningún mapeo, que era el hueco de la versión anterior.
    const authorityFor = payrollMethodAuthorityFor;

    test('admin cargado → editable', () {
      expect(
        authorityFor(_FakeProfileService(profile: _profileWithRole('admin'))),
        PayrollMethodAuthority.editable,
      );
    });

    test('contador (payroll sí, ficha no) → readOnly', () {
      final accountant = _profileWithRole('accountant');
      // La separación real de la base, en dos asertos para que se vea por qué
      // este caso existe: opera Nóminas, no escribe la ficha.
      expect(accountant.canAccessAccounting, isTrue);
      expect(accountant.canManageUsers, isFalse);
      expect(
        authorityFor(_FakeProfileService(profile: accountant)),
        PayrollMethodAuthority.readOnly,
      );
    });

    test('servicio ausente → readOnly', () {
      expect(authorityFor(null), PayrollMethodAuthority.readOnly);
    });

    test('cargando → readOnly aunque el perfil ya sea admin', () {
      expect(
        authorityFor(
          _FakeProfileService(
            profile: _profileWithRole('admin'),
            isLoading: true,
          ),
        ),
        PayrollMethodAuthority.readOnly,
        reason: 'un permiso que aún no se sabe no es un permiso',
      );
    });

    test('con problema de carga → readOnly aunque el perfil ya sea admin', () {
      expect(
        authorityFor(
          _FakeProfileService(
            profile: _profileWithRole('admin'),
            loadIssue: CurrentUserProfileLoadIssue.unavailable,
          ),
        ),
        PayrollMethodAuthority.readOnly,
      );
    });
  });
}

CurrentUserProfile _profileWithRole(String role) => CurrentUserProfile(
      userId: 'user-1',
      email: 'persona@vinabike.cl',
      emailVerified: true,
      displayName: 'Persona',
      tenantId: 'tenant-1',
      tenantName: 'Viñabike',
      tenantSubdomain: 'vinabike',
      role: role,
      permissions: const <String, bool>{},
      employeeLinkState: EmployeeLinkState.unlinked,
      employee: null,
    );

/// **El servicio REAL, no una interfaz paralela.** Sus tres estados no se
/// pueden alcanzar sin Supabase, así que se subclasea y se sobreescriben los
/// getters; el gateway falso sólo evita que el constructor toque la red. Con
/// esto la prueba consume el mismo tipo que `payroll_redesign_page.dart` lee
/// del `context`, y no una forma inventada que podría divergir de él.
class _FakeProfileService extends CurrentUserProfileService {
  _FakeProfileService({
    CurrentUserProfile? profile,
    bool isLoading = false,
    CurrentUserProfileLoadIssue? loadIssue,
  })  : _profile = profile,
        _isLoading = isLoading,
        _loadIssue = loadIssue,
        super(gateway: _UnusedGateway());

  final CurrentUserProfile? _profile;
  final bool _isLoading;
  final CurrentUserProfileLoadIssue? _loadIssue;

  @override
  CurrentUserProfile? get profile => _profile;
  @override
  bool get isLoading => _isLoading;
  @override
  CurrentUserProfileLoadIssue? get loadIssue => _loadIssue;
}

/// Nunca se llama: la derivación sólo lee estado, no carga nada.
class _UnusedGateway implements CurrentUserProfileGateway {
  @override
  Future<Map<String, dynamic>> getMyErpProfile() async =>
      throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> getTenantRows(String tenantId) async =>
      throw UnimplementedError();

  @override
  Future<void> updateAuthDisplayName({
    required String userId,
    required String displayName,
  }) async =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> updateMyEmployeeContact(
    Map<String, dynamic> patch,
  ) async =>
      throw UnimplementedError();
}
