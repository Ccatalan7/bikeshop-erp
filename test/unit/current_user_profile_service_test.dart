import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/models/current_user_profile.dart';
import 'package:vinabike_erp/shared/services/current_user_profile_service.dart';
import 'package:vinabike_erp/shared/services/self_password_service.dart';

void main() {
  const identity = CurrentUserIdentity(
    id: 'user-a',
    email: 'claudio@example.com',
    emailVerified: true,
    metadata: {'display_name': 'Nombre Auth'},
  );

  group('CurrentUserProfileService scoped read model', () {
    test('loads one exact active tenant and canonical linked employee',
        () async {
      final gateway = _FakeGateway(
        profileResponse: _profileJson(userId: identity.id, linked: true),
      );
      final service = CurrentUserProfileService(gateway: gateway);

      await service.synchronize(
        identity: identity,
        resolveTenantId: () async => 'tenant-a',
      );

      expect(service.loadIssue, isNull);
      expect(service.profile?.userId, identity.id);
      expect(service.profile?.tenantId, 'tenant-a');
      expect(service.profile?.displayName, 'Ada Lovelace');
      expect(service.profile?.employeeLinkState, EmployeeLinkState.linked);
      expect(service.profile?.employee?.rut, '12.345.678-5');
      expect(service.profile?.employee?.email, 'claudio@example.com');
      expect(service.profile?.canEditDisplayName, isFalse);
      expect(service.profile?.canEditEmployeeContact, isTrue);
    });

    test('fails closed when resolved tenant disagrees with server authority',
        () async {
      final gateway = _FakeGateway(
        profileResponse: _profileJson(userId: identity.id),
      );
      final service = CurrentUserProfileService(gateway: gateway);

      await service.synchronize(
        identity: identity,
        resolveTenantId: () async => 'tenant-b',
      );

      expect(service.profile, isNull);
      expect(
        service.loadIssue,
        CurrentUserProfileLoadIssue.invalidAccessContext,
      );
    });

    test('same Auth user rebinds when the resolved tenant changes', () async {
      var serverTenantId = 'tenant-a';
      final gateway = _FakeGateway(
        getProfile: () async => _profileJson(
          userId: identity.id,
          tenantId: serverTenantId,
        ),
      );
      final service = CurrentUserProfileService(gateway: gateway);

      await service.synchronize(
        identity: identity,
        resolveTenantId: () async => 'tenant-a',
      );
      serverTenantId = 'tenant-b';
      await service.synchronize(
        identity: identity,
        resolveTenantId: () async => 'tenant-b',
      );

      expect(gateway.profileCalls, 2);
      expect(service.loadIssue, isNull);
      expect(service.profile?.tenantId, 'tenant-b');
    });

    test('late tenant resolution cannot restore the previous tenant scope',
        () async {
      var serverTenantId = 'tenant-a';
      final staleTenantResolution = Completer<String?>();
      final gateway = _FakeGateway(
        getProfile: () async => _profileJson(
          userId: identity.id,
          tenantId: serverTenantId,
        ),
      );
      final service = CurrentUserProfileService(gateway: gateway);
      await service.synchronize(
        identity: identity,
        resolveTenantId: () async => 'tenant-a',
      );

      final staleRefresh = service.synchronize(
        identity: identity,
        resolveTenantId: () => staleTenantResolution.future,
        force: true,
      );
      serverTenantId = 'tenant-b';
      await service.synchronize(
        identity: identity,
        resolveTenantId: () async => 'tenant-b',
        force: true,
      );
      staleTenantResolution.complete('tenant-a');
      await staleRefresh;

      expect(gateway.profileCalls, 2);
      expect(service.loadIssue, isNull);
      expect(service.profile?.tenantId, 'tenant-b');
    });

    test('null tenant resolution after a successful RPC is unavailable',
        () async {
      final gateway = _FakeGateway(
        profileResponse: _profileJson(userId: identity.id),
      );
      final service = CurrentUserProfileService(gateway: gateway);

      await service.synchronize(
        identity: identity,
        resolveTenantId: () async => null,
      );

      expect(gateway.profileCalls, 1);
      expect(service.profile, isNull);
      expect(
        service.loadIssue,
        CurrentUserProfileLoadIssue.unavailable,
      );
    });

    test('null tenant refresh preserves only matching last-valid authority',
        () async {
      var serverTenantId = 'tenant-a';
      final gateway = _FakeGateway(
        getProfile: () async => _profileJson(
          userId: identity.id,
          tenantId: serverTenantId,
        ),
      );
      final service = CurrentUserProfileService(gateway: gateway);
      await service.synchronize(
        identity: identity,
        resolveTenantId: () async => 'tenant-a',
      );
      final validProfile = service.profile;

      await service.synchronize(
        identity: identity,
        resolveTenantId: () async => null,
        force: true,
      );
      expect(service.profile, same(validProfile));
      expect(
        service.loadIssue,
        CurrentUserProfileLoadIssue.unavailable,
      );

      serverTenantId = 'tenant-b';
      await service.synchronize(
        identity: identity,
        resolveTenantId: () async => null,
        force: true,
      );
      expect(service.profile, isNull);
      expect(
        service.loadIssue,
        CurrentUserProfileLoadIssue.unavailable,
      );
    });

    test('transient unavailable refresh preserves the last valid profile',
        () async {
      var calls = 0;
      final gateway = _FakeGateway(
        getProfile: () async {
          if (calls++ == 0) return _profileJson(userId: identity.id);
          throw TimeoutException('network refresh timed out');
        },
      );
      final service = CurrentUserProfileService(gateway: gateway);
      await service.synchronize(
        identity: identity,
        resolveTenantId: () async => 'tenant-a',
      );
      final validProfile = service.profile;

      await service.synchronize(
        identity: identity,
        resolveTenantId: () async => 'tenant-a',
        force: true,
      );

      expect(service.profile, same(validProfile));
      expect(
        service.loadIssue,
        CurrentUserProfileLoadIssue.unavailable,
      );
    });

    test('invalid authority refresh clears the last valid profile', () async {
      var calls = 0;
      final gateway = _FakeGateway(
        getProfile: () async => _profileJson(
          userId: identity.id,
          tenantId: calls++ == 0 ? 'tenant-a' : 'tenant-b',
        ),
      );
      final service = CurrentUserProfileService(gateway: gateway);
      await service.synchronize(
        identity: identity,
        resolveTenantId: () async => 'tenant-a',
      );

      await service.synchronize(
        identity: identity,
        resolveTenantId: () async => 'tenant-a',
        force: true,
      );

      expect(service.profile, isNull);
      expect(
        service.loadIssue,
        CurrentUserProfileLoadIssue.invalidAccessContext,
      );
    });

    test('inconsistent employee refresh clears the last valid profile',
        () async {
      var calls = 0;
      final gateway = _FakeGateway(
        getProfile: () async {
          if (calls++ == 0) return _profileJson(userId: identity.id);
          throw Exception('erp_employee_link_inconsistent');
        },
      );
      final service = CurrentUserProfileService(gateway: gateway);
      await service.synchronize(
        identity: identity,
        resolveTenantId: () async => 'tenant-a',
      );

      await service.synchronize(
        identity: identity,
        resolveTenantId: () async => 'tenant-a',
        force: true,
      );

      expect(service.profile, isNull);
      expect(
        service.loadIssue,
        CurrentUserProfileLoadIssue.inconsistentEmployeeLink,
      );
    });

    test('discards a late response from the previous Auth identity', () async {
      final first = Completer<Map<String, dynamic>>();
      final second = Completer<Map<String, dynamic>>();
      final firstStarted = Completer<void>();
      final secondStarted = Completer<void>();
      var calls = 0;
      final gateway = _FakeGateway(
        getProfile: () {
          if (calls++ == 0) {
            firstStarted.complete();
            return first.future;
          }
          secondStarted.complete();
          return second.future;
        },
      );
      final service = CurrentUserProfileService(gateway: gateway);
      const identityB = CurrentUserIdentity(
        id: 'user-b',
        email: 'grace@example.com',
        emailVerified: true,
        metadata: {},
      );

      final oldLoad = service.synchronize(
        identity: identity,
        resolveTenantId: () async => 'tenant-a',
      );
      await firstStarted.future;
      final newLoad = service.synchronize(
        identity: identityB,
        resolveTenantId: () async => 'tenant-a',
        force: true,
      );

      await secondStarted.future;
      second.complete(_profileJson(userId: identityB.id));
      await newLoad;
      first.complete(_profileJson(userId: identity.id));
      await oldLoad;

      expect(service.profile?.userId, identityB.id);
      expect(service.profile?.email, identityB.email);
    });

    test('late display-name write cannot mutate a newly resolved tenant',
        () async {
      var serverTenantId = 'tenant-a';
      final updateCompleter = Completer<void>();
      final gateway = _FakeGateway(
        getProfile: () async => _profileJson(
          userId: identity.id,
          tenantId: serverTenantId,
        ),
        updateDisplayName: (_, __) => updateCompleter.future,
      );
      final service = CurrentUserProfileService(gateway: gateway);
      await service.synchronize(
        identity: identity,
        resolveTenantId: () async => 'tenant-a',
      );

      final staleUpdate = service.updateDisplayName('Nombre en vuelo');
      serverTenantId = 'tenant-b';
      await service.synchronize(
        identity: identity,
        resolveTenantId: () async => 'tenant-b',
        force: true,
      );
      updateCompleter.complete();
      await staleUpdate;

      expect(service.profile?.tenantId, 'tenant-b');
      expect(service.profile?.displayName, 'Nombre Auth');
    });

    test('unlinked identity edits only Auth display name', () async {
      final gateway = _FakeGateway(
        profileResponse: _profileJson(userId: identity.id),
      );
      final service = CurrentUserProfileService(gateway: gateway);
      await service.synchronize(
        identity: identity,
        resolveTenantId: () async => 'tenant-a',
      );

      await service.updateDisplayName('  Nuevo   Nombre  ');

      expect(gateway.displayNameUserId, identity.id);
      expect(gateway.displayNameValue, 'Nuevo Nombre');
      expect(service.profile?.displayName, 'Nuevo Nombre');
      expect(service.profile?.canEditEmployeeContact, isFalse);
    });

    test('on-leave linked employee contact remains read-only', () async {
      final context = _profileJson(userId: identity.id, linked: true);
      (context['employee'] as Map<String, dynamic>)['status'] = 'on_leave';
      final service = CurrentUserProfileService(
        gateway: _FakeGateway(profileResponse: context),
      );

      await service.synchronize(
        identity: identity,
        resolveTenantId: () async => 'tenant-a',
      );

      expect(service.profile?.employeeLinkState, EmployeeLinkState.linked);
      expect(service.profile?.canEditEmployeeContact, isFalse);
    });

    test('linked identity sends only the five safe employee contact keys',
        () async {
      final gateway = _FakeGateway(
        profileResponse: _profileJson(userId: identity.id, linked: true),
      );
      final service = CurrentUserProfileService(gateway: gateway);
      await service.synchronize(
        identity: identity,
        resolveTenantId: () async => 'tenant-a',
      );

      gateway.employeeUpdateResponse = {
        ..._employeeJson(),
        'phone': '+56 9 1111 2222',
        'address': null,
      };
      await service.updateEmployeePersonalContact(
        const EmployeePersonalContactUpdate(
          phone: ' +56 9 1111 2222 ',
          address: ' ',
          city: 'Valparaíso',
          emergencyContactName: 'Grace',
          emergencyContactPhone: '+56 9 3333 4444',
        ),
      );

      expect(
        gateway.lastEmployeePatch?.keys.toSet(),
        {
          'phone',
          'address',
          'city',
          'emergency_contact_name',
          'emergency_contact_phone',
        },
      );
      expect(gateway.lastEmployeePatch?['address'], isNull);
      expect(gateway.lastEmployeePatch, isNot(contains('rut')));
      expect(gateway.lastEmployeePatch, isNot(contains('job_title')));
      expect(service.profile?.employee?.phone, '+56 9 1111 2222');
    });
  });

  group('CurrentUserProfileService password cleanup state', () {
    const strongPassword = 'CambioSeguro-2026!';

    test(
      'partial outcome stays pending until a revocation-only retry succeeds',
      () async {
        var passwordUpdates = 0;
        var revocations = 0;
        final passwordService = SelfPasswordService.withCommands(
          updatePassword: (newPassword, nonce) async {
            passwordUpdates++;
            return true;
          },
          revokeOtherSessions: () async {
            revocations++;
            if (revocations <= 2) {
              throw TimeoutException('session revocation unavailable');
            }
          },
        );
        final service = CurrentUserProfileService(
          gateway: _FakeGateway(
            profileResponse: _profileJson(userId: identity.id),
          ),
          passwordService: passwordService,
        );
        await service.synchronize(
          identity: identity,
          resolveTenantId: () async => 'tenant-a',
        );

        final result = await service.updatePassword(strongPassword);

        expect(result.passwordUpdated, isTrue);
        expect(result.otherSessionsRevoked, isFalse);
        expect(service.hasPendingOtherSessionsRevocation, isTrue);
        expect(passwordUpdates, 1);
        expect(revocations, 1);

        final failedRetry = await service.retryOtherSessionRevocation();

        expect(
          failedRetry,
          SelfPasswordOtherSessionsRevocationOutcome.failed,
        );
        expect(service.hasPendingOtherSessionsRevocation, isTrue);
        expect(passwordUpdates, 1);
        expect(revocations, 2);

        final successfulRetry = await service.retryOtherSessionRevocation();

        expect(
          successfulRetry,
          SelfPasswordOtherSessionsRevocationOutcome.revoked,
        );
        expect(service.hasPendingOtherSessionsRevocation, isFalse);
        expect(passwordUpdates, 1);
        expect(revocations, 3);
      },
    );

    test('retry is rejected when no cleanup is pending', () async {
      var revocations = 0;
      final service = CurrentUserProfileService(
        gateway: _FakeGateway(
          profileResponse: _profileJson(userId: identity.id),
        ),
        passwordService: SelfPasswordService.withCommands(
          updatePassword: (newPassword, nonce) async => true,
          revokeOtherSessions: () async {
            revocations++;
          },
        ),
      );
      await service.synchronize(
        identity: identity,
        resolveTenantId: () async => 'tenant-a',
      );

      await expectLater(
        service.retryOtherSessionRevocation(),
        throwsA(isA<StateError>()),
      );

      expect(service.hasPendingOtherSessionsRevocation, isFalse);
      expect(revocations, 0);
    });

    test('late partial outcome cannot contaminate a new Auth identity',
        () async {
      final passwordUpdate = Completer<bool>();
      var serverUserId = identity.id;
      var passwordUpdates = 0;
      var revocations = 0;
      final service = CurrentUserProfileService(
        gateway: _FakeGateway(
          getProfile: () async => _profileJson(userId: serverUserId),
        ),
        passwordService: SelfPasswordService.withCommands(
          updatePassword: (newPassword, nonce) {
            passwordUpdates++;
            return passwordUpdate.future;
          },
          revokeOtherSessions: () async {
            revocations++;
            throw TimeoutException('session revocation unavailable');
          },
        ),
      );
      await service.synchronize(
        identity: identity,
        resolveTenantId: () async => 'tenant-a',
      );

      final lateResult = service.updatePassword(strongPassword);
      const nextIdentity = CurrentUserIdentity(
        id: 'user-b',
        email: 'grace@example.com',
        emailVerified: true,
        metadata: {'display_name': 'Grace'},
      );
      serverUserId = nextIdentity.id;
      await service.synchronize(
        identity: nextIdentity,
        resolveTenantId: () async => 'tenant-a',
        force: true,
      );
      passwordUpdate.complete(true);
      final result = await lateResult;

      expect(result.needsOtherSessionsRevocationRetry, isTrue);
      expect(service.profile?.userId, nextIdentity.id);
      expect(service.hasPendingOtherSessionsRevocation, isFalse);
      expect(passwordUpdates, 1);
      expect(revocations, 1);
    });
  });
}

Map<String, dynamic> _profileJson({
  required String userId,
  String tenantId = 'tenant-a',
  bool linked = false,
}) {
  return {
    'userId': userId,
    'tenantId': tenantId,
    'profileId': 'profile-a',
    'role': 'admin',
    'permissions': {
      'access_pos': true,
      'manage_users': true,
    },
    'employee': linked ? _employeeJson() : null,
  };
}

Map<String, dynamic> _employeeJson() {
  return {
    'id': 'employee-a',
    'employeeNumber': 'EMP-001',
    'firstName': 'Ada',
    'lastName': 'Lovelace',
    'email': 'claudio@example.com',
    'phone': '+56 9 0000 0000',
    'rut': '12.345.678-5',
    'address': 'Uno Norte 100',
    'city': 'Viña del Mar',
    'emergencyContactName': 'Charles',
    'emergencyContactPhone': '+56 9 9999 9999',
    'jobTitle': 'Administradora',
    'departmentId': 'department-a',
    'departmentName': 'Operaciones',
    'status': 'active',
    'photoUrl': null,
    'updatedAt': '2026-07-26T23:30:00.000Z',
  };
}

class _FakeGateway implements CurrentUserProfileGateway {
  _FakeGateway({
    Map<String, dynamic>? profileResponse,
    Future<Map<String, dynamic>> Function()? getProfile,
    Future<void> Function(String userId, String displayName)? updateDisplayName,
  })  : _profileResponse = profileResponse,
        _getProfile = getProfile,
        _updateDisplayName = updateDisplayName;

  final Map<String, dynamic>? _profileResponse;
  final Future<Map<String, dynamic>> Function()? _getProfile;
  final Future<void> Function(String userId, String displayName)?
      _updateDisplayName;

  int profileCalls = 0;
  String? displayNameUserId;
  String? displayNameValue;
  Map<String, dynamic>? lastEmployeePatch;
  Map<String, dynamic>? employeeUpdateResponse;

  @override
  Future<Map<String, dynamic>> getMyErpProfile() async {
    profileCalls++;
    if (_getProfile != null) return _getProfile();
    return Map<String, dynamic>.from(_profileResponse!);
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
  }) async {
    displayNameUserId = userId;
    displayNameValue = displayName;
    await _updateDisplayName?.call(userId, displayName);
  }

  @override
  Future<Map<String, dynamic>> updateMyEmployeeContact(
    Map<String, dynamic> patch,
  ) async {
    lastEmployeePatch = Map<String, dynamic>.from(patch);
    return Map<String, dynamic>.from(
      employeeUpdateResponse ?? _employeeJson(),
    );
  }
}
