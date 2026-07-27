import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/settings/pages/user_management_page.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';
import 'package:vinabike_erp/shared/services/user_management_service.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets(
    'compact invitation keeps explicit selection and preserves edited email',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(384, 824));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tenantService = TenantService.testing(
        currentUserId: () => null,
        profileLookup: (_) async => const [],
      );
      final userService = _FakeUserManagementService(
        tenantService,
        overview: _overview(
          employeeStates: [
            _employeeState(
              id: 'available',
              name: 'Ana Mecánica',
              email: 'ana@example.com',
              linkState: 'available',
            ),
            _employeeState(
              id: 'worker-active',
              name: 'Bruno Taller',
              email: 'bruno@example.com',
              linkState: 'worker_active',
              workerAccessExists: true,
              workerAccessActive: true,
              workerUsername: 'bruno.taller',
            ),
            _employeeState(
              id: 'worker-suspended',
              name: 'Carla Servicio',
              email: 'carla@example.com',
              linkState: 'worker_suspended',
              workerAccessExists: true,
              workerUsername: 'carla.servicio',
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TenantService>.value(value: tenantService),
            Provider<UserManagementService>.value(value: userService),
          ],
          child: const MaterialApp(home: UserManagementPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Invitar equipo'));
      await tester.pumpAndSettle();

      expect(find.text('Invitar usuario interno'), findsOneWidget);
      expect(find.text('Sin vincular a trabajador'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final employeeFieldFinder =
          find.byKey(const ValueKey('user-invite-employee-field'));
      await tester.tap(employeeFieldFinder);
      await tester.pumpAndSettle();
      final workerActiveFinder = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownMenuItem<String> &&
            widget.value == 'worker-active',
      );
      final workerActiveItem =
          tester.widget<DropdownMenuItem<String>>(workerActiveFinder.last);
      expect(workerActiveItem.enabled, isFalse);

      await tester.tap(
        find.text('Ana Mecánica — Disponible para vincular').last,
      );
      await tester.pumpAndSettle();

      final emailFinder = find.byKey(const ValueKey('user-invite-email-field'));
      final nameFinder = find.byKey(const ValueKey('user-invite-name-field'));
      expect(
        tester.widget<TextFormField>(emailFinder).controller!.text,
        'ana@example.com',
      );
      expect(
        tester.widget<TextFormField>(nameFinder).controller!.text,
        'Ana Mecánica',
      );

      await tester.enterText(emailFinder, 'correo.editado@example.com');
      await tester.tap(find.text('Ana Mecánica — Disponible para vincular'));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .text(
              'Carla Servicio — App de trabajadores suspendida · puede migrarse',
            )
            .last,
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextFormField>(emailFinder).controller!.text,
        'correo.editado@example.com',
      );
      expect(
        tester.widget<TextFormField>(nameFinder).controller!.text,
        'Carla Servicio',
      );
      expect(find.textContaining('migrarlo explícitamente'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a suspended ERP profile can still unlink its exact employee',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final tenantService = TenantService.testing(
        currentUserId: () => null,
        profileLookup: (_) async => const [],
      );
      final userService = _FakeUserManagementService(
        tenantService,
        overview: _overview(
          staffUsers: [
            {
              'id': 'user-linked',
              'email': 'staff@example.com',
              'displayName': 'Staff Suspendido',
              'role': 'mechanic',
              'permissions': <String, bool>{},
              'isActive': false,
              'profileActive': false,
              'emailConfirmed': true,
              'employeeId': 'linked',
            },
          ],
          employeeStates: [
            _employeeState(
              id: 'linked',
              name: 'Daniel Taller',
              email: 'daniel@example.com',
              linkState: 'erp_linked',
              erpUserId: 'user-linked',
              erpProfileActive: false,
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TenantService>.value(value: tenantService),
            Provider<UserManagementService>.value(value: userService),
          ],
          child: const MaterialApp(home: UserManagementPage()),
        ),
      );
      await tester.pumpAndSettle();

      final unlinkFinder = find.widgetWithText(
        OutlinedButton,
        'Desvincular trabajador',
      );
      expect(unlinkFinder, findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(unlinkFinder).onPressed,
        isNotNull,
      );

      await tester.ensureVisible(unlinkFinder);
      await tester.pumpAndSettle();
      await tester.tap(unlinkFinder);
      await tester.pumpAndSettle();
      expect(find.text('Desvincular trabajador'), findsNWidgets(2));
      expect(
        find.textContaining(
          'La cuenta ERP conservará su acceso y la ficha del trabajador conservará su historial',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

class _FakeUserManagementService extends UserManagementService {
  _FakeUserManagementService(
    super.tenantService, {
    required this.overview,
  });

  final Map<String, dynamic> overview;

  @override
  Future<Map<String, dynamic>> getIdentityOverview({
    String search = '',
    String? customerId,
  }) async {
    return overview;
  }
}

Map<String, dynamic> _overview({
  List<Map<String, dynamic>> staffUsers = const [],
  List<Map<String, dynamic>> employeeStates = const [],
}) {
  return {
    'staffUsers': staffUsers,
    'customerAccounts': <Map<String, dynamic>>[],
    'invitations': <Map<String, dynamic>>[],
    'employeeAccessStates': employeeStates,
    'summary': <String, dynamic>{},
  };
}

Map<String, dynamic> _employeeState({
  required String id,
  required String name,
  required String email,
  required String linkState,
  String? erpUserId,
  bool erpProfileActive = false,
  bool pendingInvitation = false,
  bool workerAccessExists = false,
  bool workerAccessActive = false,
  String? workerUsername,
}) {
  return {
    'employeeId': id,
    'employeeName': name,
    'email': email,
    'status': 'active',
    'erpUserId': erpUserId,
    'erpProfileActive': erpProfileActive,
    'pendingInvitation': pendingInvitation,
    'workerAccessExists': workerAccessExists,
    'workerAccessActive': workerAccessActive,
    'workerUsername': workerUsername,
    'linkState': linkState,
  };
}
