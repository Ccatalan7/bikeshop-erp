import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/services/supplier_credential_reveal_controller.dart';
import 'package:vinabike_erp/modules/purchases/services/supplier_credential_service.dart';
import 'package:vinabike_erp/shared/models/current_user_profile.dart';
import 'package:vinabike_erp/shared/services/current_user_profile_service.dart';

void main() {
  const tenantId = '10000000-0000-0000-0000-000000000001';
  const supplierId = '20000000-0000-0000-0000-000000000002';
  final target = SupplierCredentialRevealTarget(
    supplierId: supplierId,
    kind: SupplierCredentialKind.portalPassword,
    credentialKey: 'retail_portal',
  );

  test('hide invalidates a delayed reveal before it can publish', () async {
    final profileService = _MutableProfileService(_profile(tenantId));
    final gateway = _DelayedCredentialGateway();
    final service = SupplierCredentialService(
      profileService: profileService,
      gateway: gateway,
      currentAuthUserId: () => 'user-a',
    );
    final controller = SupplierCredentialRevealController(
      credentialService: service,
      profileService: profileService,
    );

    final pending = controller.reveal(target);
    expect(controller.isRevealing, isTrue);
    controller.hide();
    gateway.completer.complete(
      _credentialResponse(tenantId: tenantId, supplierId: supplierId),
    );

    expect(await pending, isFalse);
    expect(controller.revealedSecret, isNull);
    expect(controller.isVisible, isFalse);
    controller.dispose();
  });

  test('permission revoke clears secret and restore requires a fresh RPC',
      () async {
    final profileService = _MutableProfileService(_profile(tenantId));
    final gateway = _QueueCredentialGateway([
      _credentialResponse(
        tenantId: tenantId,
        supplierId: supplierId,
        secret: 'first-secret',
      ),
      _credentialResponse(
        tenantId: tenantId,
        supplierId: supplierId,
        secret: 'fresh-secret',
      ),
    ]);
    final service = SupplierCredentialService(
      profileService: profileService,
      gateway: gateway,
      currentAuthUserId: () => 'user-a',
    );
    final controller = SupplierCredentialRevealController(
      credentialService: service,
      profileService: profileService,
    );

    expect(await controller.reveal(target), isTrue);
    expect(controller.revealedSecret, 'first-secret');

    profileService.current = _profile(tenantId, canManage: false);
    expect(controller.revealedSecret, isNull);
    profileService.current = _profile(tenantId);
    expect(controller.revealedSecret, isNull);
    expect(gateway.calls, 1);

    expect(await controller.reveal(target), isTrue);
    expect(controller.revealedSecret, 'fresh-secret');
    expect(gateway.calls, 2);
    controller.dispose();
  });

  test('auth logout clears a revealed secret before profile rebuild', () async {
    final profileService = _MutableProfileService(_profile(tenantId));
    final gateway = _QueueCredentialGateway([
      _credentialResponse(tenantId: tenantId, supplierId: supplierId),
    ]);
    final authorityEvents = StreamController<Object?>.broadcast(sync: true);
    String? authUserId = 'user-a';
    final service = SupplierCredentialService(
      profileService: profileService,
      gateway: gateway,
      currentAuthUserId: () => authUserId,
      authorityEvents: authorityEvents.stream,
    );
    final controller = SupplierCredentialRevealController(
      credentialService: service,
      profileService: profileService,
    );

    expect(await controller.reveal(target), isTrue);
    expect(controller.revealedSecret, isNotNull);
    authUserId = null;
    authorityEvents.add('signed_out');

    expect(controller.revealedSecret, isNull);
    expect(profileService.profile?.userId, 'user-a');
    controller.dispose();
    await authorityEvents.close();
  });

  test('configurable TTL destroys the in-memory secret', () async {
    final profileService = _MutableProfileService(_profile(tenantId));
    final gateway = _QueueCredentialGateway([
      _credentialResponse(tenantId: tenantId, supplierId: supplierId),
    ]);
    void Function()? expire;
    final service = SupplierCredentialService(
      profileService: profileService,
      gateway: gateway,
      currentAuthUserId: () => 'user-a',
    );
    final controller = SupplierCredentialRevealController(
      credentialService: service,
      profileService: profileService,
      ttl: const Duration(seconds: 5),
      timerFactory: (duration, callback) {
        expect(duration, const Duration(seconds: 5));
        expire = callback;
        return _FakeTimer();
      },
    );

    expect(await controller.reveal(target), isTrue);
    expect(controller.revealedSecret, isNotNull);
    expire!();

    expect(controller.revealedSecret, isNull);
    expect(controller.isVisible, isFalse);
    controller.dispose();
  });

  test('dispose destroys the secret and ignores authority events', () async {
    final profileService = _MutableProfileService(_profile(tenantId));
    final gateway = _QueueCredentialGateway([
      _credentialResponse(tenantId: tenantId, supplierId: supplierId),
    ]);
    final service = SupplierCredentialService(
      profileService: profileService,
      gateway: gateway,
      currentAuthUserId: () => 'user-a',
    );
    final controller = SupplierCredentialRevealController(
      credentialService: service,
      profileService: profileService,
    );

    expect(await controller.reveal(target), isTrue);
    controller.dispose();
    expect(controller.revealedSecret, isNull);
    profileService.current = null;
  });
}

CurrentUserProfile _profile(
  String tenantId, {
  bool canManage = true,
}) {
  return CurrentUserProfile(
    userId: 'user-a',
    email: 'user-a@example.com',
    emailVerified: true,
    displayName: 'User A',
    tenantId: tenantId,
    tenantName: 'Tenant',
    tenantSubdomain: null,
    role: 'owner',
    permissions: {
      'can_manage_supplier_credentials': canManage,
    },
    employeeLinkState: EmployeeLinkState.unlinked,
    employee: null,
  );
}

Map<String, dynamic> _credentialResponse({
  required String tenantId,
  required String supplierId,
  String secret = 'revealed-secret',
}) {
  return {
    'tenant_id': tenantId,
    'supplier_id': supplierId,
    'credential_kind': 'portal_password',
    'credential_key': 'retail_portal',
    'username': 'buyer@example.com',
    'secret': secret,
  };
}

class _MutableProfileService extends CurrentUserProfileService {
  _MutableProfileService(CurrentUserProfile? current)
      : _current = current,
        super(gateway: _UnusedProfileGateway());

  CurrentUserProfile? _current;

  set current(CurrentUserProfile? value) {
    _current = value;
    notifyListeners();
  }

  @override
  CurrentUserProfile? get profile => _current;
}

class _UnusedProfileGateway implements CurrentUserProfileGateway {
  @override
  Future<Map<String, dynamic>> getMyErpProfile() => throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> getTenantRows(String tenantId) =>
      throw UnimplementedError();

  @override
  Future<void> updateAuthDisplayName({
    required String userId,
    required String displayName,
  }) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> updateMyEmployeeContact(
    Map<String, dynamic> patch,
  ) =>
      throw UnimplementedError();
}

class _DelayedCredentialGateway implements SupplierCredentialGateway {
  final Completer<dynamic> completer = Completer<dynamic>();

  @override
  Future<dynamic> rpc(
    String functionName, {
    required Map<String, dynamic> params,
  }) =>
      completer.future;
}

class _QueueCredentialGateway implements SupplierCredentialGateway {
  _QueueCredentialGateway(this.responses);

  final List<dynamic> responses;
  int calls = 0;

  @override
  Future<dynamic> rpc(
    String functionName, {
    required Map<String, dynamic> params,
  }) async {
    final response = responses[calls];
    calls++;
    return response;
  }
}

class _FakeTimer implements Timer {
  bool _active = true;

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}
