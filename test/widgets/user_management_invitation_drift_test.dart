import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/settings/pages/user_management_page.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';
import 'package:vinabike_erp/shared/services/user_management_service.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/vb_notice.dart';

/// Una invitación es una credencial dirigida a un buzón concreto y el ERP no la
/// redirige cuando cambia la ficha del trabajador — eso es correcto y es lo que
/// hacen los sistemas de identidad serios. Lo que se prueba acá es que esa
/// divergencia **se vea**: el 2026-08-05 un administrador cambió el correo de
/// un trabajador con una invitación de administrador pendiente, la pantalla no
/// dijo nada, y la invitación siguió viva hacia el buzón descartado.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets(
    'la invitación desalineada avisa con E-04 y nombra el correo de la ficha',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpInvitations(tester);

      await tester.tap(find.byKey(const ValueKey('user-audience-invitations')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('user-row-invitation-drift')));
      await tester.pumpAndSettle();

      final notice = find.byKey(
        const ValueKey('invitation-email-drift-notice'),
      );
      expect(notice, findsOneWidget);
      expect(
        tester.widget<VbNotice>(notice).tone,
        VbNoticeTone.warning,
        reason: 'no está roto nada: hay que decidir, no es un error',
      );

      // La guía E-04 exige el dato real dentro del aviso, no una frase
      // genérica: sin el correo de la ficha no se sabe a dónde reinvitar. El
      // de la invitación no se repite porque ya está en el encabezado.
      final body = tester.widget<VbNotice>(notice).body ?? '';
      expect(body, contains('Vicente Díaz'));
      expect(body, contains('vicente.diaz@gmail.com'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'la invitación alineada no muestra ningún aviso',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpInvitations(tester);

      await tester.tap(find.byKey(const ValueKey('user-audience-invitations')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('user-row-invitation-aligned')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('invitation-email-drift-notice')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'una diferencia de mayúsculas o de espacios no es una divergencia',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpInvitations(tester);

      await tester.tap(find.byKey(const ValueKey('user-audience-invitations')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('user-row-invitation-case')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('invitation-email-drift-notice')),
        findsNothing,
        reason: 'avisar por el case convertiría el aviso en ruido ignorable',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'la lista marca la divergencia sin tener que abrir el detalle',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpInvitations(tester);

      await tester.tap(find.byKey(const ValueKey('user-audience-invitations')));
      await tester.pumpAndSettle();

      // El dueño miró la lista, no el detalle: ahí es donde tiene que verse.
      // Se acota al panel de la colección porque el aviso del detalle usa la
      // misma frase a propósito — un solo vocabulario para una sola condición.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('user-management-list-pane')),
          matching: find.text('Destino distinto al de la ficha'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'los plazos se leen en hora de Chile, no en la del equipo',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpInvitations(tester);

      await tester.tap(find.byKey(const ValueKey('user-audience-invitations')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('user-row-invitation-aligned')),
      );
      await tester.pumpAndSettle();

      // 2026-08-12T16:19:00Z en agosto (Chile sin horario de verano, UTC-4)
      // son las 12:19. Un Mac en horario del Pacífico mostraba 09:19.
      expect(find.text('12/08/2026 12:19'), findsOneWidget);
      expect(find.text('12/08/2026 09:19'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pumpInvitations(WidgetTester tester) async {
  final tenantService = TenantService.testing(
    currentUserId: () => null,
    profileLookup: (_) async => const [],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<TenantService>.value(value: tenantService),
        Provider<UserManagementService>.value(
          value: _DriftUserManagementService(tenantService),
        ),
      ],
      // `VbNotice` lee sus colores de VinabikeThemeRoles, que sólo existe si
      // el tema se construye por AppTheme: un MaterialApp por defecto no los
      // trae y el aviso revienta al pintarse.
      child: MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.all.first,
          brightness: Brightness.light,
        ),
        home: const UserManagementPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _DriftUserManagementService extends UserManagementService {
  _DriftUserManagementService(super.tenantService);

  @override
  Future<Map<String, dynamic>> getIdentityOverview({
    String search = '',
    String? customerId,
  }) async {
    return {
      'staffUsers': <Map<String, dynamic>>[],
      'customerAccounts': <Map<String, dynamic>>[],
      'invitations': <Map<String, dynamic>>[
        {
          'id': 'invitation-drift',
          'email': 'vicente.diazf@usm.cl',
          'role': 'admin',
          'status': 'pending',
          'permissions': <String, bool>{},
          'employee_id': 'employee-vicente',
          'expires_at': '2026-08-12T16:19:00Z',
          'created_at': '2026-08-04T23:22:00Z',
        },
        {
          'id': 'invitation-aligned',
          'email': 'alineada@example.com',
          'role': 'cashier',
          'status': 'pending',
          'permissions': <String, bool>{},
          'employee_id': 'employee-alineada',
          'expires_at': '2026-08-12T16:19:00Z',
          'created_at': '2026-08-04T23:22:00Z',
        },
        {
          'id': 'invitation-case',
          'email': 'Mayus@Example.com',
          'role': 'cashier',
          'status': 'pending',
          'permissions': <String, bool>{},
          'employee_id': 'employee-mayus',
          'expires_at': '2026-08-12T16:19:00Z',
          'created_at': '2026-08-04T23:22:00Z',
        },
      ],
      'employeeAccessStates': <Map<String, dynamic>>[
        _employee(
          'employee-vicente',
          'Vicente Díaz',
          'vicente.diaz@gmail.com',
        ),
        _employee(
          'employee-alineada',
          'Persona Alineada',
          'alineada@example.com',
        ),
        _employee('employee-mayus', 'Persona Mayus', '  mayus@example.com  '),
      ],
      'summary': <String, dynamic>{},
    };
  }

  Map<String, dynamic> _employee(String id, String name, String email) {
    return <String, dynamic>{
      'employeeId': id,
      'employeeName': name,
      'email': email,
      'status': 'active',
      'erpUserId': null,
      'erpProfileActive': false,
      'pendingInvitation': true,
      'workerAccessExists': false,
      'workerAccessActive': false,
      'workerUsername': null,
      'linkState': 'available',
    };
  }
}
