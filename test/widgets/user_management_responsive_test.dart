import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/settings/pages/user_management_page.dart';
import 'package:vinabike_erp/shared/models/current_user_profile.dart';
import 'package:vinabike_erp/shared/services/current_user_profile_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';
import 'package:vinabike_erp/shared/services/user_management_navigation.dart';
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
    'uses dedicated compact and desktop compositions at canonical breakpoints',
    (tester) async {
      const viewports = <Size>[
        Size(384, 824),
        Size(599, 824),
        Size(600, 900),
        Size(899, 900),
        Size(900, 900),
        Size(1440, 900),
      ];

      for (final viewport in viewports) {
        await tester.binding.setSurfaceSize(viewport);
        await _pumpPage(
          tester,
          textScaler: viewport.width == 384
              ? const TextScaler.linear(1.3)
              : TextScaler.noScaling,
        );

        expect(
          find.byKey(const ValueKey('user-management-list-pane')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('user-management-primary-action')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('user-management-detail-pane')),
          viewport.width >= 900 ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull, reason: '$viewport');
      }

      addTearDown(() => tester.binding.setSurfaceSize(null));
    },
  );

  testWidgets(
    'compact list does not imply a selection before the user opens a detail',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(384, 824));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpPage(tester);

      final row = find.byKey(const ValueKey('user-row-staff-beatriz'));
      final semantics =
          find.ancestor(of: row, matching: find.byType(Semantics)).first;

      expect(tester.widget<Semantics>(semantics).properties.selected, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact list detail and system Back preserve query and selection context',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(384, 824));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpPage(tester);

      final search = find.byKey(const ValueKey('user-management-search'));
      await tester.enterText(search, 'beatriz');
      await tester.pump();

      expect(find.text('Beatriz Taller'), findsOneWidget);
      expect(find.text('Alonso Caja'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('user-row-staff-beatriz')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('user-management-compact-detail')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('user-management-compact-back')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('user-management-primary-action')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('user-management-search')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('user-management-compact-back')),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(search).controller!.text,
        'beatriz',
      );
      expect(find.text('Beatriz Taller'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('user-row-staff-beatriz')),
      );
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('user-management-compact-list')),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(search).controller!.text,
        'beatriz',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'staff and invitation search locally while customer search uses backend',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(899, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final userService = await _pumpPage(tester);
      final search = find.byKey(const ValueKey('user-management-search'));

      expect(userService.searches, ['']);
      await tester.enterText(search, 'beatriz');
      await tester.pump(const Duration(milliseconds: 400));
      expect(userService.searches, ['']);

      await tester.tap(
        find.byKey(const ValueKey('user-audience-invitations')),
      );
      await tester.pump();
      await tester.enterText(search, 'invitada');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('invitada@example.com'), findsOneWidget);
      expect(userService.searches, ['']);

      await tester.tap(
        find.byKey(const ValueKey('user-audience-customers')),
      );
      await tester.pumpAndSettle();
      expect(userService.searches.last, 'invitada');

      await tester.enterText(search, 'maría');
      await tester.pump(const Duration(milliseconds: 349));
      expect(userService.searches.last, 'invitada');
      await tester.pump(const Duration(milliseconds: 2));
      expect(userService.searches.last, 'maría');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'permissions are disclosed as readable rows and touch targets stay usable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpPage(tester);

      final permissions = find.byKey(
        const ValueKey('user-management-permissions-disclosure'),
      );
      expect(permissions, findsOneWidget);
      await tester.ensureVisible(permissions);
      await tester.tap(permissions);
      await tester.pumpAndSettle();

      expect(find.text('Acceso a POS'), findsOneWidget);
      expect(find.text('Permitido'), findsWidgets);
      expect(find.byType(Chip), findsNothing);
      expect(find.byType(ActionChip), findsNothing);

      for (final audience in [
        'staff',
        'customers',
        'invitations',
      ]) {
        final size = tester.getSize(
          find.byKey(ValueKey('user-audience-$audience')),
        );
        expect(size.height, greaterThanOrEqualTo(48));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'filtered empty state offers an in-place way back to the full list',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(384, 824));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpPage(tester);

      final search = find.byKey(const ValueKey('user-management-search'));
      await tester.enterText(search, 'no-existe');
      await tester.pump();

      expect(
        find.byKey(const ValueKey('user-management-clear-search')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('user-management-clear-search')),
      );
      await tester.pump();
      expect(find.text('Beatriz Taller'), findsOneWidget);
      expect(tester.widget<TextField>(search).controller!.text, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'direct entry fails closed before requesting admin identity data',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final tenantService = TenantService.testing(
        currentUserId: () => null,
        profileLookup: (_) async => const [],
      );
      final userService = _RecordingUserManagementService(tenantService);
      final profileService = _StaticProfileService(
        const CurrentUserProfile(
          userId: 'cashier-user',
          email: 'cashier@example.com',
          emailVerified: true,
          displayName: 'Usuario Caja',
          tenantId: 'tenant-one',
          tenantName: 'Tienda',
          tenantSubdomain: 'tienda',
          role: 'cashier',
          permissions: <String, bool>{},
          employeeLinkState: EmployeeLinkState.unlinked,
          employee: null,
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TenantService>.value(value: tenantService),
            ChangeNotifierProvider<CurrentUserProfileService>.value(
              value: profileService,
            ),
            Provider<UserManagementService>.value(value: userService),
          ],
          child: const MaterialApp(home: UserManagementPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('user-management-access-blocked')),
        findsOneWidget,
      );
      expect(find.text('Acceso restringido'), findsOneWidget);
      expect(userService.searches, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a compact contextual request opens the exact customer in place',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(384, 824));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final request = const UserManagementOpenRequest(
        audience: UserManagementAudience.customers,
        target: UserManagementTarget.customer,
        targetId: 'customer-maria',
        requestId: 'customer-request',
      ).encode();

      final userService = await _pumpPage(
        tester,
        initialOpenRequest: request,
      );

      expect(userService.customerIds, ['customer-maria']);
      expect(
        find.byKey(const ValueKey('user-management-compact-detail')),
        findsOneWidget,
      );
      expect(find.text('María Cliente'), findsWidgets);

      await tester.tap(
        find.byKey(const ValueKey('user-management-compact-back')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('user-management-compact-list')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a missing contextual identity never falls back to the first row',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(384, 824));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final request = const UserManagementOpenRequest(
        audience: UserManagementAudience.customers,
        target: UserManagementTarget.customer,
        targetId: 'customer-missing',
        requestId: 'missing-request',
      ).encode();

      final userService = await _pumpPage(
        tester,
        initialOpenRequest: request,
      );

      expect(userService.customerIds, ['customer-missing']);
      expect(
        find.byKey(const ValueKey('user-management-request-unavailable')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('user-management-compact-detail')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'CRM-only customer does not expose portal recovery or restriction actions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(384, 824));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final request = UserManagementOpenRequest(
        audience: UserManagementAudience.customers,
        target: UserManagementTarget.customer,
        targetId: 'customer-solo-crm',
      ).encode();

      await _pumpPage(tester, initialOpenRequest: request);

      expect(find.text('Sin cuenta web'), findsWidgets);
      expect(find.text('Crear cuenta web'), findsOneWidget);
      expect(find.text('Enviar acceso seguro'), findsNothing);
      expect(find.text('Limitar acceso'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'contextual compact Back returns to the originating route',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(384, 824));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final tenantService = TenantService.testing(
        currentUserId: () => null,
        profileLookup: (_) async => const [],
      );
      final userService = _RecordingUserManagementService(tenantService);
      final navigatorKey = GlobalKey<NavigatorState>();
      final request = UserManagementOpenRequest(
        audience: UserManagementAudience.customers,
        target: UserManagementTarget.customer,
        targetId: 'customer-maria',
      ).encode();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TenantService>.value(value: tenantService),
            Provider<UserManagementService>.value(value: userService),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const Scaffold(body: Text('Cliente de origen')),
          ),
        ),
      );
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => UserManagementPage(initialOpenRequest: request),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('user-management-compact-detail')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('user-management-compact-back')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cliente de origen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<_RecordingUserManagementService> _pumpPage(
  WidgetTester tester, {
  TextScaler textScaler = TextScaler.noScaling,
  String? initialOpenRequest,
}) async {
  final tenantService = TenantService.testing(
    currentUserId: () => null,
    profileLookup: (_) async => const [],
  );
  final userService = _RecordingUserManagementService(tenantService);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<TenantService>.value(value: tenantService),
        Provider<UserManagementService>.value(value: userService),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: UserManagementPage(initialOpenRequest: initialOpenRequest),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return userService;
}

class _RecordingUserManagementService extends UserManagementService {
  _RecordingUserManagementService(super.tenantService);

  final searches = <String>[];
  final customerIds = <String?>[];

  @override
  Future<Map<String, dynamic>> getIdentityOverview({
    String search = '',
    String? customerId,
  }) async {
    searches.add(search);
    customerIds.add(customerId);
    final query = search.trim().toLowerCase();
    final customers = <Map<String, dynamic>>[
      {
        'customerId': 'customer-maria',
        'displayName': 'María Cliente',
        'email': 'maria@example.com',
        'phone': '+56 9 1111 2222',
        'hasAuth': true,
        'hasCustomerProfile': true,
        'isActive': true,
        'emailConfirmed': true,
      },
      {
        'customerId': 'customer-solo-crm',
        'displayName': 'Cliente sin portal',
        'email': 'sin-portal@example.com',
        'phone': '+56 9 3333 4444',
        'hasAuth': false,
        'hasCustomerProfile': true,
        'isActive': true,
        'emailConfirmed': false,
      },
    ].where((customer) {
      if (query.isEmpty) return true;
      return customer.values.join(' ').toLowerCase().contains(query);
    }).toList(growable: false);

    return {
      'staffUsers': [
        {
          'id': 'staff-beatriz',
          'displayName': 'Beatriz Taller',
          'email': 'beatriz@example.com',
          'role': 'mechanic',
          'permissions': {
            'access_pos': true,
            'create_invoices': true,
          },
          'isActive': true,
          'profileActive': true,
          'emailConfirmed': true,
        },
        {
          'id': 'staff-alonso',
          'displayName': 'Alonso Caja',
          'email': 'alonso@example.com',
          'role': 'cashier',
          'permissions': <String, bool>{},
          'isActive': true,
          'profileActive': true,
          'emailConfirmed': true,
        },
      ],
      'customerAccounts': customers,
      'invitations': [
        {
          'id': 'invitation-one',
          'email': 'invitada@example.com',
          'role': 'cashier',
          'status': 'pending',
          'permissions': <String, bool>{},
          'expires_at': '2026-08-01T12:00:00Z',
          'created_at': '2026-07-26T12:00:00Z',
        },
      ],
      'employeeAccessStates': <Map<String, dynamic>>[],
      'summary': <String, dynamic>{},
    };
  }
}

class _StaticProfileService extends CurrentUserProfileService {
  _StaticProfileService(this.value);

  final CurrentUserProfile? value;

  @override
  CurrentUserProfile? get profile => value;

  @override
  bool get isLoading => false;
}
