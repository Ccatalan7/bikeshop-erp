import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vinabike_erp/shared/models/current_user_profile.dart';
import 'package:vinabike_erp/shared/pages/my_profile_page.dart';
import 'package:vinabike_erp/shared/services/current_user_profile_service.dart';
import 'package:vinabike_erp/shared/services/self_password_service.dart';

const _identity = CurrentUserIdentity(
  id: 'user-a',
  email: 'auth@example.com',
  emailVerified: true,
  metadata: {'display_name': 'Grace Hopper'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const responsiveMatrix = <Size>[
    Size(1440, 900),
    Size(900, 900),
    Size(899, 824),
    Size(600, 824),
    Size(599, 824),
    Size(384, 824),
  ];

  for (final size in responsiveMatrix) {
    testWidgets(
      'linked profile composes at ${size.width.toInt()}x'
      '${size.height.toInt()} with 1.3 text scale',
      (tester) async {
        _configureView(tester, size);
        final service = await _loadedService(_ProfileWidgetGateway());
        addTearDown(service.dispose);

        await _pumpProfile(tester, service: service);

        final scroll = find.byKey(const ValueKey('erp-profile-scroll'));
        expect(scroll, findsOneWidget);
        expect(
          find.byKey(const ValueKey('erp-profile-display-name')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('erp-profile-linked-employee')),
          findsOneWidget,
        );
        expect(
          find.byKey(
            const ValueKey('erp-profile-permissions-disclosure'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('erp-profile-change-password')),
          findsOneWidget,
        );

        final profileContext = tester.element(
          find.byKey(const ValueKey('erp-profile-display-name')),
        );
        expect(
          MediaQuery.textScalerOf(profileContext).scale(10),
          closeTo(13, 0.001),
        );

        final scrollLeft = tester.getTopLeft(scroll).dx;
        if (size.width >= 900) {
          expect(
            scrollLeft,
            greaterThanOrEqualTo(224),
            reason: 'Desktop widths reserve space for the section navigator.',
          );
        } else {
          expect(
            scrollLeft,
            closeTo(0, 0.01),
            reason: 'Compact widths use the full content canvas.',
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('permissions are grouped behind progressive disclosure',
      (tester) async {
    _configureView(tester, const Size(384, 824));
    final service = await _loadedService(_ProfileWidgetGateway());
    addTearDown(service.dispose);

    await _pumpProfile(tester, service: service);

    final disclosure = find.byKey(
      const ValueKey('erp-profile-permissions-disclosure'),
    );
    await tester.ensureVisible(disclosure);
    await tester.pumpAndSettle();
    await tester.tap(disclosure);
    await tester.pumpAndSettle();

    final operationGroup = find.text('Operación');
    final administrationGroup = find.text('Administración');
    await tester.ensureVisible(operationGroup);
    await tester.pumpAndSettle();

    expect(operationGroup.hitTestable(), findsOneWidget);
    expect(administrationGroup, findsOneWidget);
    expect(find.text('•  Acceder al POS'), findsOneWidget);
    expect(find.text('•  Gestionar usuarios'), findsOneWidget);
    expect(find.byType(Chip), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'linked contact draft survives 599/600 and 899/900 then cancel restores it',
    (tester) async {
      _configureView(tester, const Size(599, 824));
      final gateway = _ProfileWidgetGateway();
      final service = await _loadedService(gateway);
      addTearDown(service.dispose);
      final navigationBlocked = <bool>[];

      await _pumpProfile(
        tester,
        service: service,
        onNavigationStateChanged: navigationBlocked.add,
      );

      final edit = find.byKey(const ValueKey('erp-profile-edit-contact'));
      await tester.ensureVisible(edit);
      await tester.pumpAndSettle();
      await tester.tap(edit);
      await tester.pumpAndSettle();

      const draftPhone = '+56 9 1111 2222';
      final phoneField =
          find.byKey(const ValueKey('erp-profile-contact-phone'));
      await tester.ensureVisible(phoneField);
      await tester.enterText(phoneField, draftPhone);
      await tester.pump();
      expect(_textFieldValue(tester, phoneField), draftPhone);
      expect(navigationBlocked.last, isTrue);

      for (final resized in const [
        Size(600, 824),
        Size(899, 824),
        Size(900, 900),
      ]) {
        tester.view.physicalSize = resized;
        await tester.pumpAndSettle();
        expect(
          _textFieldValue(tester, phoneField),
          draftPhone,
          reason: 'Responsive recomposition must not replace editor state.',
        );
        expect(navigationBlocked.last, isTrue);
        expect(tester.takeException(), isNull);
      }

      final cancel = find.byKey(const ValueKey('erp-profile-cancel-contact'));
      await tester.ensureVisible(cancel);
      await tester.pumpAndSettle();
      await tester.tap(cancel);
      await tester.pumpAndSettle();

      expect(phoneField, findsNothing);
      expect(
        find.byKey(const ValueKey('erp-profile-edit-contact')),
        findsOneWidget,
      );
      expect(navigationBlocked.last, isFalse);
      expect(gateway.contactUpdateCalls, 0);

      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(_textFieldValue(tester, phoneField), '+56 9 0000 0000');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unlinked identity edit is protected by the dirty discard guard',
      (tester) async {
    _configureView(tester, const Size(384, 824));
    final service = await _loadedService(
      _ProfileWidgetGateway(linkedEmployee: false),
    );
    addTearDown(service.dispose);
    final contentKey = GlobalKey<MyProfileContentState>();
    final navigationBlocked = <bool>[];

    await _pumpProfile(
      tester,
      service: service,
      contentKey: contentKey,
      onNavigationStateChanged: navigationBlocked.add,
    );

    expect(
      find.byKey(const ValueKey('erp-profile-unlinked-employee')),
      findsOneWidget,
    );
    final edit = find.byKey(const ValueKey('erp-profile-edit-display-name'));
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();

    final nameField =
        find.byKey(const ValueKey('erp-profile-display-name-field'));
    await tester.enterText(nameField, 'Grace M. Hopper');
    await tester.pump();
    expect(navigationBlocked.last, isTrue);

    final keepEditing = contentKey.currentState!.confirmDiscardIfNeeded();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('erp-profile-discard-dialog')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('erp-profile-discard-cancel')),
    );
    await tester.pumpAndSettle();
    expect(await keepEditing, isFalse);
    expect(_textFieldValue(tester, nameField), 'Grace M. Hopper');
    expect(navigationBlocked.last, isTrue);

    final discard = contentKey.currentState!.confirmDiscardIfNeeded();
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('erp-profile-discard-confirm')),
    );
    await tester.pumpAndSettle();
    expect(await discard, isTrue);
    expect(nameField, findsNothing);
    expect(
      find.byKey(const ValueKey('erp-profile-edit-display-name')),
      findsOneWidget,
    );
    expect(navigationBlocked.last, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'password partial outcome retries only session revocation in ERP dialog',
    (tester) async {
      _configureView(tester, const Size(900, 900));
      var passwordUpdates = 0;
      var revocations = 0;
      final service = CurrentUserProfileService(
        gateway: _ProfileWidgetGateway(),
        passwordService: SelfPasswordService.withCommands(
          updatePassword: (newPassword, nonce) async {
            passwordUpdates++;
            return true;
          },
          revokeOtherSessions: () async {
            revocations++;
            if (revocations == 1) {
              throw TimeoutException('session revocation unavailable');
            }
          },
        ),
      );
      addTearDown(service.dispose);
      await service.synchronize(
        identity: _identity,
        resolveTenantId: () async => 'tenant-a',
      );
      await _pumpProfile(tester, service: service);

      final passwordAction = find.byKey(
        const ValueKey('erp-profile-change-password'),
      );
      await tester.ensureVisible(passwordAction);
      await tester.pumpAndSettle();
      await tester.tap(passwordAction);
      await tester.pumpAndSettle();

      const strongPassword = 'CambioSeguro-2026!';
      await tester.enterText(
        _textFormFieldWithLabel('Nueva contraseña'),
        strongPassword,
      );
      await tester.enterText(
        _textFormFieldWithLabel('Confirmar contraseña'),
        strongPassword,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Cambiar'));
      await tester.pumpAndSettle();

      expect(passwordUpdates, 1);
      expect(revocations, 1);
      expect(service.hasPendingOtherSessionsRevocation, isTrue);
      expect(
        find.byKey(
          const ValueKey('erp-password-session-revocation-step'),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.widgetWithText(FilledButton, 'Reintentar cierre'),
      );
      await tester.pumpAndSettle();

      expect(passwordUpdates, 1);
      expect(revocations, 2);
      expect(service.hasPendingOtherSessionsRevocation, isFalse);
      expect(
        find.byKey(
          const ValueKey('erp-password-session-revocation-step'),
        ),
        findsNothing,
      );
      expect(
        find.text('Contraseña actualizada y demás sesiones cerradas'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('loading state is announced and resolves into the workspace',
      (tester) async {
    _configureView(tester, const Size(384, 824));
    final semantics = tester.ensureSemantics();
    final pendingProfile = Completer<Map<String, dynamic>>();
    final gateway = _ProfileWidgetGateway(pendingProfile: pendingProfile);
    final service = CurrentUserProfileService(gateway: gateway);
    addTearDown(service.dispose);

    final load = service.synchronize(
      identity: _identity,
      resolveTenantId: () async => 'tenant-a',
    );
    await _pumpProfile(tester, service: service, settle: false);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('erp-profile-loading')),
      findsOneWidget,
    );
    try {
      expect(
        find.bySemanticsLabel(RegExp(r'^Cargando tu perfil')),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }

    pendingProfile.complete(gateway.profileResponse);
    await load;
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('erp-profile-scroll')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable refresh preserves profile and marks it stale',
      (tester) async {
    _configureView(tester, const Size(900, 900));
    final gateway = _ProfileWidgetGateway();
    final service = await _loadedService(gateway);
    addTearDown(service.dispose);

    gateway.profileError = StateError('network unavailable');
    await service.synchronize(
      identity: _identity,
      resolveTenantId: () async => 'tenant-a',
      force: true,
    );
    await _pumpProfile(tester, service: service);

    expect(service.profile, isNotNull);
    expect(
      service.loadIssue,
      CurrentUserProfileLoadIssue.unavailable,
    );
    expect(
      find.byKey(const ValueKey('erp-profile-stale-notice')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('erp-profile-scroll')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('inconsistent employee authority renders a safe failure state',
      (tester) async {
    _configureView(tester, const Size(384, 824));
    final gateway = _ProfileWidgetGateway()
      ..profileError = StateError('ERP_EMPLOYEE_LINK_INCONSISTENT');
    final service = await _loadedService(gateway);
    addTearDown(service.dispose);

    await _pumpProfile(tester, service: service);

    expect(service.profile, isNull);
    expect(
      service.loadIssue,
      CurrentUserProfileLoadIssue.inconsistentEmployeeLink,
    );
    expect(
      find.byKey(const ValueKey('erp-profile-load-failure')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('erp-profile-scroll')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<CurrentUserProfileService> _loadedService(
  _ProfileWidgetGateway gateway,
) async {
  final service = CurrentUserProfileService(gateway: gateway);
  await service.synchronize(
    identity: _identity,
    resolveTenantId: () async => 'tenant-a',
  );
  return service;
}

void _configureView(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpProfile(
  WidgetTester tester, {
  required CurrentUserProfileService service,
  GlobalKey<MyProfileContentState>? contentKey,
  ValueChanged<bool>? onNavigationStateChanged,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: service,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(
              textScaler: const TextScaler.linear(1.3),
            ),
            child: child!,
          );
        },
        home: Scaffold(
          body: MyProfileContent(
            key: contentKey,
            onRefresh: () async {},
            onNavigationStateChanged: onNavigationStateChanged,
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

String _textFieldValue(WidgetTester tester, Finder finder) {
  return tester.widget<TextFormField>(finder).controller!.text;
}

Finder _textFormFieldWithLabel(String label) {
  return find.ancestor(
    of: find.text(label),
    matching: find.byType(TextFormField),
  );
}

class _ProfileWidgetGateway implements CurrentUserProfileGateway {
  _ProfileWidgetGateway({
    this.linkedEmployee = true,
    this.pendingProfile,
  });

  final bool linkedEmployee;
  final Completer<Map<String, dynamic>>? pendingProfile;
  Object? profileError;
  int contactUpdateCalls = 0;

  Map<String, dynamic> get profileResponse => {
        'userId': 'user-a',
        'tenantId': 'tenant-a',
        'profileId': 'profile-a',
        'role': 'manager',
        'permissions': {
          'access_pos': true,
          'manage_users': true,
        },
        'employee': linkedEmployee ? _employeeResponse() : null,
      };

  @override
  Future<Map<String, dynamic>> getMyErpProfile() async {
    final error = profileError;
    if (error != null) throw error;
    final pending = pendingProfile;
    if (pending != null) return pending.future;
    return profileResponse;
  }

  @override
  Future<List<Map<String, dynamic>>> getTenantRows(String tenantId) async {
    return [
      {
        'id': tenantId,
        'shop_name': 'Vinabike',
        'subdomain': 'vinabike',
        'is_active': true,
      },
    ];
  }

  @override
  Future<void> updateAuthDisplayName({
    required String userId,
    required String displayName,
  }) async {}

  @override
  Future<Map<String, dynamic>> updateMyEmployeeContact(
    Map<String, dynamic> patch,
  ) async {
    contactUpdateCalls++;
    final employee = _employeeResponse();
    for (final entry in patch.entries) {
      final responseKey = switch (entry.key) {
        'emergency_contact_name' => 'emergencyContactName',
        'emergency_contact_phone' => 'emergencyContactPhone',
        _ => entry.key,
      };
      employee[responseKey] = entry.value;
    }
    employee['updatedAt'] = '2026-07-27T00:00:00.000Z';
    return employee;
  }

  Map<String, dynamic> _employeeResponse() {
    return {
      'id': 'employee-a',
      'employeeNumber': 'EMP-001',
      'firstName': 'Ada',
      'lastName': 'Lovelace',
      'email': 'laboral@example.com',
      'phone': '+56 9 0000 0000',
      'rut': '12.345.678-5',
      'address': 'Uno Norte 100',
      'city': 'Viña del Mar',
      'emergencyContactName': 'Charles',
      'emergencyContactPhone': '+56 9 9999 9999',
      'jobTitle': 'Administradora',
      'departmentName': 'Operaciones',
      'status': 'active',
      'photoUrl': null,
      'updatedAt': '2026-07-26T23:30:00.000Z',
    };
  }
}
