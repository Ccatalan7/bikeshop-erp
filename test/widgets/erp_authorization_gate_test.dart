import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:vinabike_erp/shared/models/current_user_profile.dart';
import 'package:vinabike_erp/shared/services/current_user_profile_service.dart';
import 'package:vinabike_erp/shared/widgets/erp_authorization_gate.dart';

const _identity = CurrentUserIdentity(
  id: 'user-a',
  email: 'user@example.com',
  emailVerified: true,
  metadata: {},
);

void main() {
  test('authorization policy matches the HR and payroll matrix', () {
    final cases = <({
      ErpAuthorizationArea area,
      String role,
      Map<String, bool> permissions,
      ErpAuthorizationDecision expected,
    })>[
      (
        area: ErpAuthorizationArea.hrManagement,
        role: 'manager',
        permissions: const {},
        expected: ErpAuthorizationDecision.allowed,
      ),
      (
        area: ErpAuthorizationArea.hrManagement,
        role: 'mechanic',
        permissions: const {'manage_users': true},
        expected: ErpAuthorizationDecision.allowed,
      ),
      (
        area: ErpAuthorizationArea.hrManagement,
        role: 'accountant',
        permissions: const {'access_accounting': true},
        expected: ErpAuthorizationDecision.denied,
      ),
      (
        area: ErpAuthorizationArea.payroll,
        role: 'accountant',
        permissions: const {},
        expected: ErpAuthorizationDecision.allowed,
      ),
      (
        area: ErpAuthorizationArea.payroll,
        role: 'mechanic',
        permissions: const {'access_accounting': true},
        expected: ErpAuthorizationDecision.allowed,
      ),
      (
        area: ErpAuthorizationArea.payroll,
        role: 'cashier',
        permissions: const {},
        expected: ErpAuthorizationDecision.denied,
      ),
    ];

    for (final testCase in cases) {
      expect(
        evaluateErpAuthorization(
          area: testCase.area,
          profile: _profile(
            role: testCase.role,
            permissions: testCase.permissions,
          ),
          isLoading: false,
          loadIssue: null,
        ),
        testCase.expected,
        reason: '${testCase.area.name}/${testCase.role}',
      );
    }
    expect(
      evaluateErpAuthorization(
        area: ErpAuthorizationArea.hrManagement,
        profile: _profile(
          role: 'manager',
          permissions: const {'manage_users': true},
        ),
        isLoading: true,
        loadIssue: null,
      ),
      ErpAuthorizationDecision.resolving,
    );
    expect(
      evaluateErpAuthorization(
        area: ErpAuthorizationArea.payroll,
        profile: _profile(
          role: 'accountant',
          permissions: const {'access_accounting': true},
        ),
        isLoading: false,
        loadIssue: CurrentUserProfileLoadIssue.unavailable,
      ),
      ErpAuthorizationDecision.unavailable,
    );
  });

  testWidgets(
    'a direct HR link never constructs its body while resolving or denied',
    (tester) async {
      final profileResponse = Completer<Map<String, dynamic>>();
      final gateway = _GateProfileGateway(
        getProfile: () => profileResponse.future,
      );
      final service = CurrentUserProfileService(gateway: gateway);
      addTearDown(service.dispose);
      final synchronize = service.synchronize(
        identity: _identity,
        resolveTenantId: () async => 'tenant-a',
      );
      var protectedBuilds = 0;

      await _pumpDirectLink(
        tester,
        service: service,
        area: ErpAuthorizationArea.hrManagement,
        onProtectedBuild: () => protectedBuilds++,
      );
      expect(find.text('resolving'), findsOneWidget);
      expect(protectedBuilds, 0);

      profileResponse.complete(
        _profileResponse(role: 'mechanic', permissions: const {}),
      );
      await synchronize;
      await tester.pump();

      expect(find.text('denied'), findsOneWidget);
      expect(protectedBuilds, 0);
    },
  );

  testWidgets('a direct link constructs its body only after authority resolves',
      (tester) async {
    final gateway = _GateProfileGateway(
      getProfile: () async => _profileResponse(
        role: 'mechanic',
        permissions: const {'manage_users': true},
      ),
    );
    final service = CurrentUserProfileService(gateway: gateway);
    addTearDown(service.dispose);
    await service.synchronize(
      identity: _identity,
      resolveTenantId: () async => 'tenant-a',
    );
    var protectedBuilds = 0;

    await _pumpDirectLink(
      tester,
      service: service,
      area: ErpAuthorizationArea.hrManagement,
      onProtectedBuild: () => protectedBuilds++,
    );

    expect(find.text('protected HR body'), findsOneWidget);
    expect(protectedBuilds, 1);
  });

  testWidgets('an unavailable profile fails closed on a direct payroll link',
      (tester) async {
    final gateway = _GateProfileGateway(
      getProfile: () async => throw StateError('offline'),
    );
    final service = CurrentUserProfileService(gateway: gateway);
    addTearDown(service.dispose);
    await service.synchronize(
      identity: _identity,
      resolveTenantId: () async => 'tenant-a',
    );
    var protectedBuilds = 0;

    await _pumpDirectLink(
      tester,
      service: service,
      area: ErpAuthorizationArea.payroll,
      onProtectedBuild: () => protectedBuilds++,
    );

    expect(find.text('unavailable'), findsOneWidget);
    expect(protectedBuilds, 0);
  });
}

Future<void> _pumpDirectLink(
  WidgetTester tester, {
  required CurrentUserProfileService service,
  required ErpAuthorizationArea area,
  required VoidCallback onProtectedBuild,
}) async {
  final router = GoRouter(
    initialLocation: '/hr/protected',
    routes: [
      GoRoute(
        path: '/hr/protected',
        builder: (context, state) => ErpAuthorizationGate(
          area: area,
          authorizedBuilder: (_) {
            onProtectedBuild();
            return const Text('protected HR body');
          },
          blockedBuilder: (_, decision) => Text(decision.name),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: service,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
}

CurrentUserProfile _profile({
  required String role,
  required Map<String, bool> permissions,
}) {
  return CurrentUserProfile(
    userId: 'user-a',
    email: 'user@example.com',
    emailVerified: true,
    displayName: 'Usuario',
    tenantId: 'tenant-a',
    tenantName: 'Vinabike',
    tenantSubdomain: 'vinabike',
    role: role,
    permissions: permissions,
    employeeLinkState: EmployeeLinkState.unlinked,
    employee: null,
  );
}

Map<String, dynamic> _profileResponse({
  required String role,
  required Map<String, bool> permissions,
}) {
  return {
    'userId': 'user-a',
    'tenantId': 'tenant-a',
    'profileId': 'profile-a',
    'role': role,
    'permissions': permissions,
    'employee': null,
  };
}

class _GateProfileGateway implements CurrentUserProfileGateway {
  _GateProfileGateway({required this.getProfile});

  final Future<Map<String, dynamic>> Function() getProfile;

  @override
  Future<Map<String, dynamic>> getMyErpProfile() => getProfile();

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
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> updateMyEmployeeContact(
    Map<String, dynamic> patch,
  ) {
    throw UnimplementedError();
  }
}
