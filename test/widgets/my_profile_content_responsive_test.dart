import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:vinabike_erp/shared/models/current_user_profile.dart';
import 'package:vinabike_erp/shared/pages/my_profile_page.dart';
import 'package:vinabike_erp/shared/services/current_user_profile_service.dart';
import 'package:vinabike_erp/shared/services/employee_self_service_service.dart';
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

        final semantics = tester.ensureSemantics();
        final scroll = find.byKey(const ValueKey('erp-profile-scroll'));
        expect(scroll, findsOneWidget);
        expect(
          find.byKey(const ValueKey('erp-profile-display-name')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('erp-profile-identity-header')),
          findsOneWidget,
        );
        expect(
          find.byKey(
            const ValueKey('erp-profile-section-body-personal'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(
            const ValueKey('erp-profile-section-body-employment'),
          ),
          findsNothing,
        );

        final profileContext = tester.element(
          find.byKey(const ValueKey('erp-profile-display-name')),
        );
        expect(
          MediaQuery.textScalerOf(profileContext).scale(10),
          closeTo(13, 0.001),
        );

        final sectionContext = find.byKey(
          const ValueKey('erp-profile-section-context'),
        );
        final sectionContent = find.byKey(
          const ValueKey('erp-profile-section-content'),
        );
        // Every width renders the section header above its own body. The
        // navigator is what recomposes: a persistent rail beside the body on
        // desktop, and a scrollable strip above it on tablet and phone.
        expect(
          tester.getTopLeft(sectionContent).dy,
          greaterThan(tester.getTopLeft(sectionContext).dy),
          reason: 'The section body follows its own labelled header.',
        );
        expect(
          tester.getTopLeft(sectionContent).dx,
          closeTo(tester.getTopLeft(sectionContext).dx, 0.01),
          reason: 'Header and body share one content column.',
        );
        if (size.width >= 900) {
          expect(
            tester.getTopLeft(sectionContent).dx,
            greaterThan(tester.getTopRight(_sectionNav('personal')).dx),
            reason: 'Desktop pairs a persistent navigator with the body.',
          );
          expect(
            tester.getTopLeft(_sectionNav('security')).dy,
            greaterThan(tester.getTopLeft(_sectionNav('personal')).dy),
            reason: 'The desktop navigator stacks its sections vertically.',
          );
        } else {
          expect(
            tester.getTopLeft(sectionContext).dy,
            greaterThan(tester.getBottomLeft(_sectionNav('personal')).dy),
            reason: 'Compact keeps one canonical content column below the '
                'section navigator.',
          );
        }

        for (final section in const [
          'personal',
          'employment',
          'access',
          'security',
        ]) {
          final target = _sectionNav(section);
          expect(target, findsOneWidget);
          final targetSize = tester.getSize(target);
          expect(targetSize.width, greaterThanOrEqualTo(48));
          expect(targetSize.height, greaterThanOrEqualTo(48));
        }
        expect(
          tester.getBottomRight(_sectionNav('security')).dy,
          lessThanOrEqualTo(size.height),
          reason:
              'Every labelled profile section must be reachable in the first viewport.',
        );
        expect(
          tester
              .getSemantics(
                find.bySemanticsLabel('Sección Datos personales'),
              )
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );
        expect(
          tester
              .getSemantics(
                find.byKey(
                  const ValueKey('erp-profile-section-body-personal'),
                ),
              )
              .label,
          contains('Sección Datos personales seleccionada'),
        );

        await _tapProfileSection(tester, 'employment');
        expect(
          find.byKey(const ValueKey('erp-profile-linked-employee')),
          findsOneWidget,
        );
        await _tapProfileSection(tester, 'access');
        expect(
          find.byKey(
            const ValueKey('erp-profile-permissions-disclosure'),
          ),
          findsOneWidget,
        );
        await _tapProfileSection(tester, 'security');
        expect(
          find.byKey(const ValueKey('erp-profile-change-password')),
          findsOneWidget,
        );

        expect(
          tester.getTopLeft(scroll).dx,
          closeTo(0, 0.01),
          reason: 'No viewport reserves a permanent profile rail.',
        );
        try {
          expect(
            tester.takeException(),
            isNull,
          );
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets('permissions are grouped behind progressive disclosure',
      (tester) async {
    _configureView(tester, const Size(384, 824));
    final service = await _loadedService(_ProfileWidgetGateway());
    addTearDown(service.dispose);

    await _pumpProfile(tester, service: service);
    await _tapProfileSection(tester, 'access');

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

      await _tapProfileSection(tester, 'access');
      expect(phoneField, findsNothing);
      expect(
        find.byKey(const ValueKey('erp-profile-section-body-access')),
        findsOneWidget,
      );

      for (final resized in const [
        Size(600, 824),
        Size(899, 824),
        Size(900, 900),
      ]) {
        tester.view.physicalSize = resized;
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('erp-profile-section-body-access')),
          findsOneWidget,
          reason: 'Responsive recomposition must preserve active section.',
        );
        expect(navigationBlocked.last, isTrue);
        expect(tester.takeException(), isNull);
      }

      await _tapProfileSection(tester, 'personal');
      expect(_textFieldValue(tester, phoneField), draftPhone);

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

  testWidgets('phone contact edit remains reachable above the virtual keyboard',
      (tester) async {
    _configureView(tester, const Size(384, 824));
    addTearDown(() => tester.view.viewInsets = FakeViewPadding.zero);
    final service = await _loadedService(_ProfileWidgetGateway());
    addTearDown(service.dispose);

    await _pumpProfile(tester, service: service);
    final edit = find.byKey(const ValueKey('erp-profile-edit-contact'));
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();

    final emergencyPhone =
        find.byKey(const ValueKey('erp-profile-emergency-phone'));
    await tester.ensureVisible(emergencyPhone);
    await tester.tap(emergencyPhone);
    await tester.enterText(emergencyPhone, '+56 9 8765 4321');

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('erp-profile-save-contact'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();

    expect(save.hitTestable(), findsOneWidget);
    expect(tester.getSize(save).height, greaterThanOrEqualTo(48));
    expect(
      tester.getBottomRight(save).dy,
      lessThanOrEqualTo(524),
      reason: 'The save action must remain above the 300px keyboard inset.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed contact save keeps the inline draft and error',
      (tester) async {
    _configureView(tester, const Size(384, 824));
    final gateway = _ProfileWidgetGateway()
      ..contactUpdateError = StateError('network unavailable');
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
    await tester.tap(edit);
    await tester.pumpAndSettle();

    const draftPhone = '+56 9 2468 1357';
    final phoneField = find.byKey(const ValueKey('erp-profile-contact-phone'));
    await tester.enterText(phoneField, draftPhone);
    final save = find.byKey(const ValueKey('erp-profile-save-contact'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('erp-profile-contact-save-error')),
      findsOneWidget,
    );
    expect(_textFieldValue(tester, phoneField), draftPhone);
    expect(navigationBlocked.last, isTrue);
    expect(gateway.contactUpdateCalls, 1);
    expect(tester.takeException(), isNull);
  });

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

    await _tapProfileSection(tester, 'employment');
    expect(
      find.byKey(const ValueKey('erp-profile-unlinked-employee')),
      findsOneWidget,
    );
    await _tapProfileSection(tester, 'personal');
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
      await _tapProfileSection(tester, 'security');

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

  for (final size in const [Size(384, 824), Size(1440, 900)]) {
    testWidgets(
      'linked identity reaches its own labor sections at '
      '${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        _configureView(tester, size);
        final service = await _loadedService(_ProfileWidgetGateway());
        addTearDown(service.dispose);

        await _pumpProfile(tester, service: service);

        await _tapProfileSection(tester, 'shifts');
        expect(
          find.byKey(const ValueKey('erp-profile-work-shifts')),
          findsOneWidget,
        );
        // Own assignment and published team coverage stay separate.
        expect(find.textContaining('Turno taller'), findsOneWidget);
        expect(find.text('Mis turnos'), findsOneWidget);
        expect(find.text('Cobertura del equipo esta semana'), findsOneWidget);
        expect(
          find.textContaining('Katherine Johnson'),
          findsNothing,
          reason: 'Team coverage stays behind its labelled disclosure.',
        );
        expect(find.text('Horario base'), findsOneWidget);
        expect(find.text('Solicitudes de cambio'), findsOneWidget);

        await _tapProfileSection(tester, 'attendance');
        expect(
          find.byKey(const ValueKey('erp-profile-work-attendance')),
          findsOneWidget,
        );
        expect(find.text('Planificado'), findsOneWidget);
        expect(find.text('Trabajado'), findsOneWidget);
        expect(find.text('Diferencia'), findsOneWidget);

        await _tapProfileSection(tester, 'payroll');
        expect(
          find.byKey(const ValueKey('erp-profile-work-payroll')),
          findsOneWidget,
        );
        expect(find.text('Junio 2026'), findsOneWidget);
        expect(find.text('Pagada'), findsOneWidget);

        for (final section in const ['shifts', 'attendance', 'payroll']) {
          final targetSize = tester.getSize(_sectionNav(section));
          expect(targetSize.width, greaterThanOrEqualTo(48));
          expect(targetSize.height, greaterThanOrEqualTo(48));
        }

        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('unlinked identity never exposes labor sections', (tester) async {
    _configureView(tester, const Size(1440, 900));
    final service = await _loadedService(
      _ProfileWidgetGateway(linkedEmployee: false),
    );
    addTearDown(service.dispose);

    await _pumpProfile(tester, service: service);

    for (final section in const ['shifts', 'attendance', 'payroll']) {
      expect(
        _sectionNav(section),
        findsNothing,
        reason: 'An identity without an employee record has no labor data.',
      );
    }
    expect(_sectionNav('personal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed labor read stays explicit and retryable', (tester) async {
    _configureView(tester, const Size(1440, 900));
    final service = await _loadedService(_ProfileWidgetGateway());
    addTearDown(service.dispose);

    final work = EmployeeSelfServiceService(
      gateway: _SelfServiceWidgetGateway(failing: true),
    );
    await _pumpProfile(tester, service: service, selfService: work);

    await _tapProfileSection(tester, 'shifts');
    expect(
      find.byKey(const ValueKey('erp-profile-work-unavailable')),
      findsOneWidget,
    );
    expect(find.text('Reintentar'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('erp-profile-work-shifts')),
      findsNothing,
      reason: 'A failed labor read is never rendered as an empty week.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty week renders an explicit state, not a blank panel',
      (tester) async {
    _configureView(tester, const Size(384, 824));
    final service = await _loadedService(_ProfileWidgetGateway());
    addTearDown(service.dispose);

    final work = EmployeeSelfServiceService(
      gateway: _SelfServiceWidgetGateway(empty: true),
    );
    await _pumpProfile(tester, service: service, selfService: work);

    await _tapProfileSection(tester, 'shifts');
    expect(find.text('Semana sin turnos'), findsOneWidget);

    await _tapProfileSection(tester, 'payroll');
    expect(find.text('Sin liquidaciones emitidas'), findsOneWidget);
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
  EmployeeSelfServiceService? selfService,
  bool settle = true,
}) async {
  final work = selfService ??
      EmployeeSelfServiceService(gateway: _SelfServiceWidgetGateway());
  addTearDown(work.dispose);
  await work.synchronize(profile: service.profile);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: service),
        ChangeNotifierProvider.value(value: work),
      ],
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

Finder _sectionNav(String section) {
  return find.byKey(ValueKey('erp-profile-section-nav-$section'));
}

Future<void> _tapProfileSection(
  WidgetTester tester,
  String section,
) async {
  final target = _sectionNav(section);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
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

/// Deterministic labor payload: one shift, one attendance and one settled
/// payroll line inside the week the profile renders by default.
class _SelfServiceWidgetGateway implements EmployeeSelfServiceGateway {
  _SelfServiceWidgetGateway({this.empty = false, this.failing = false});

  final bool empty;
  final bool failing;

  @override
  Future<Map<String, dynamic>> getSnapshot({
    required DateTime? weekAnchor,
  }) async {
    if (failing) throw StateError('self-service unavailable');
    final weekStart = EmployeeSelfServiceService.startOfWeek(
      weekAnchor ?? DateTime.now(),
    );
    final weekEnd = weekStart.add(const Duration(days: 7));
    tzdata.initializeTimeZones();
    final location = tz.getLocation('America/Santiago');
    final weekStartAt = tz.TZDateTime(
      location,
      weekStart.year,
      weekStart.month,
      weekStart.day,
    ).toUtc();
    final weekEndAt = tz.TZDateTime(
      location,
      weekEnd.year,
      weekEnd.month,
      weekEnd.day,
    ).toUtc();
    final day = weekStart.add(const Duration(days: 1));
    final dayStart = tz.TZDateTime(
      location,
      day.year,
      day.month,
      day.day,
      9,
    ).toUtc();

    return {
      'user_id': 'user-a',
      'tenant_id': 'tenant-a',
      'employee_id': 'employee-a',
      'timezone': 'America/Santiago',
      'week_start': _dateOnly(weekStart),
      'week_end': _dateOnly(weekEnd),
      'week_start_at': weekStartAt.toIso8601String(),
      'week_end_at': weekEndAt.toIso8601String(),
      'is_current_week': weekAnchor == null,
      'my_shifts': empty
          ? const <dynamic>[]
          : [
              {
                'id': 'shift-a',
                'employee_id': 'employee-a',
                'title': 'Turno taller',
                'start_at': dayStart.toIso8601String(),
                'end_at':
                    dayStart.add(const Duration(hours: 9)).toIso8601String(),
                'status': 'published',
                'source': 'manual',
                'store_hours_validated': true,
                'role_name': 'Mecánico',
                'planned_minutes_in_week': 540,
              },
            ],
      'team_shifts': empty
          ? const <dynamic>[]
          : [
              {
                'id': 'shift-b',
                'employee_id': 'employee-z',
                'start_at':
                    dayStart.add(const Duration(hours: 1)).toIso8601String(),
                'end_at':
                    dayStart.add(const Duration(hours: 10)).toIso8601String(),
                'status': 'published',
                'source': 'manual',
                'store_hours_validated': true,
                'employee_name': 'Katherine Johnson',
                'employee_job_title': 'Vendedora',
                'planned_minutes_in_week': 540,
              },
            ],
      'attendances': empty
          ? const <dynamic>[]
          : [
              {
                'id': 'attendance-a',
                'employee_id': 'employee-a',
                'check_in': dayStart.toIso8601String(),
                'check_out': dayStart
                    .add(const Duration(hours: 8, minutes: 30))
                    .toIso8601String(),
                'worked_hours': 8.0,
                'worked_minutes_in_week': 480,
                'overtime_hours': 0.0,
                'break_minutes': 30,
                'status': 'approved',
              },
            ],
      'payroll_lines': empty
          ? const <dynamic>[]
          : [
              {
                'id': 'line-a',
                'employee_id': 'employee-a',
                'voucher_id': 'voucher-a',
                'worked_hours': 176.0,
                'overtime_hours': 4.0,
                'regular_amount': 900000.0,
                'overtime_amount': 40000.0,
                'total_amount': 940000.0,
                'payment_method': 'transfer',
                'voucher': {
                  'id': 'voucher-a',
                  'voucher_number': 'LIQ-0001',
                  'period_start': '2026-06-01',
                  'period_end': '2026-06-30',
                  'period_label': 'Junio 2026',
                  'status': 'paid',
                  'paid_at': '2026-07-05T12:00:00Z',
                },
              },
            ],
      'change_requests': empty
          ? const <dynamic>[]
          : [
              {
                'id': 'request-a',
                'employee_id': 'employee-a',
                'request_type': 'update',
                'status': 'pending',
                'worker_note': 'Necesito cambiar el turno del martes',
                'created_at': '2026-07-20T12:00:00Z',
              },
            ],
      'default_shift_blocks': empty
          ? const <dynamic>[]
          : [
              {
                'id': 'block-a',
                'employee_id': 'employee-a',
                'day_of_week': 2,
                'start_time': '09:00:00',
                'end_time': '18:00:00',
                'role_name': 'Mecánico',
              },
            ],
    };
  }

  String _dateOnly(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}

class _ProfileWidgetGateway implements CurrentUserProfileGateway {
  _ProfileWidgetGateway({
    this.linkedEmployee = true,
    this.pendingProfile,
  });

  final bool linkedEmployee;
  final Completer<Map<String, dynamic>>? pendingProfile;
  Object? profileError;
  Object? contactUpdateError;
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
    final error = contactUpdateError;
    if (error != null) throw error;
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
