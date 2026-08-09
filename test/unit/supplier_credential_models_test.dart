// ignore_for_file: prefer_const_literals_to_create_immutables

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/services/supplier_credential_service.dart';
import 'package:vinabike_erp/shared/models/current_user_profile.dart';
import 'package:vinabike_erp/shared/services/current_user_profile_service.dart';

void main() {
  const tenantId = '10000000-0000-0000-0000-000000000001';
  const supplierId = '20000000-0000-0000-0000-000000000002';
  const operationId = '40000000-0000-0000-0000-000000000004';

  test('credential DTO redacts secret and username from diagnostics', () {
    final credential = SupplierCredential.fromJson({
      'tenant_id': tenantId,
      'supplier_id': supplierId,
      'credential_kind': 'portal_password',
      'credential_key': 'retail_portal',
      'engagement_id': '30000000-0000-0000-0000-000000000003',
      'origin_url': 'https://portal.example.com',
      'label': 'Portal principal',
      'username': 'buyer@example.com',
      'secret': 'do-not-log-this',
      'updated_at': '2026-08-08T12:00:00Z',
    });

    expect(credential.secret, 'do-not-log-this');
    expect(credential.username, 'buyer@example.com');
    expect(credential.toString(), isNot(contains('do-not-log-this')));
    expect(credential.toString(), isNot(contains('buyer@example.com')));
    expect(
        credential.metadata.toString(), isNot(contains('buyer@example.com')));
  });

  test('credential reveal preserves secret bytes including whitespace', () {
    final credential = SupplierCredential.fromJson({
      'tenant_id': tenantId,
      'supplier_id': supplierId,
      'credential_kind': 'api_token',
      'credential_key': 'whitespace_token',
      'secret': '  token with spaces  ',
    });
    final whitespaceOnly = SupplierCredential.fromJson({
      'tenant_id': tenantId,
      'supplier_id': supplierId,
      'credential_kind': 'other',
      'credential_key': 'whitespace_only',
      'secret': '   ',
    });

    expect(credential.secret, '  token with spaces  ');
    expect(whitespaceOnly.secret, '   ');
  });

  test('metadata-only status has no secret surface', () {
    final status = SupplierCredentialStatus.fromJson({
      'tenant_id': tenantId,
      'supplier_id': supplierId,
      'has_portal_credential': true,
      'credentials': [
        {
          'credential_kind': 'portal_password',
          'credential_key': 'retail_portal',
          'origin_url': 'https://portal.example.com',
          'label': 'Portal principal',
          'username': 'buyer@example.com',
          'updated_at': '2026-08-08T12:00:00Z',
        },
      ],
    });

    expect(status.hasPortalCredential, isTrue);
    expect(
        status.credentials.single.kind, SupplierCredentialKind.portalPassword);
    expect(status.credentials.single.tenantId, tenantId);
    expect(status.credentials.single.supplierId, supplierId);
    expect(status.credentials.single.credentialKey, 'retail_portal');
    expect(status.credentials.single.secretAvailable, isTrue);
    expect(
      status.forHttpsOrigin(
        'HTTPS://PORTAL.EXAMPLE.COM:443',
        kind: SupplierCredentialKind.portalPassword,
      ),
      hasLength(1),
    );
  });

  test('metadata parses canonical availability, alias, and legacy default', () {
    Map<String, dynamic> metadata([Map<String, dynamic> extra = const {}]) => {
          'tenant_id': tenantId,
          'supplier_id': supplierId,
          'credential_kind': 'portal_password',
          'credential_key': 'retail_portal',
          ...extra,
        };

    expect(
      SupplierCredentialMetadata.fromJson(
        metadata({'has_secret': false}),
      ).secretAvailable,
      isFalse,
    );
    expect(
      SupplierCredentialMetadata.fromJson(
        metadata({'secret_available': false}),
      ).secretAvailable,
      isFalse,
    );
    expect(
      SupplierCredentialMetadata.fromJson(metadata()).secretAvailable,
      isTrue,
    );
    expect(
      () => SupplierCredentialMetadata.fromJson(
        metadata({'has_secret': false, 'secret_available': true}),
      ),
      throwsFormatException,
    );
    expect(
      () => SupplierCredentialMetadata.fromJson(
        metadata({'has_secret': 'false'}),
      ),
      throwsFormatException,
    );
  });

  test('secret-bearing DTOs reject unavailable applied metadata', () {
    expect(
      () => SupplierCredential.fromJson({
        'tenant_id': tenantId,
        'supplier_id': supplierId,
        'credential_kind': 'portal_password',
        'credential_key': 'retail_portal',
        'has_secret': false,
        'secret': 'must-not-be-accepted',
      }),
      throwsFormatException,
    );

    final applied = {
      ..._credentialMetadataResponse(
        tenantId: tenantId,
        supplierId: supplierId,
      ),
      'has_secret': false,
    };
    expect(
      () => SupplierCredentialUpsertResult.fromJson(
        _upsertReceipt(operationId: operationId, metadata: applied),
      ),
      throwsFormatException,
    );
  });

  test('upsert replay may report a newer metadata-only current row', () {
    final applied = {
      ..._credentialMetadataResponse(
        tenantId: tenantId,
        supplierId: supplierId,
      ),
      'has_secret': true,
    };
    final result = SupplierCredentialUpsertResult.fromJson(
      _upsertReceipt(
        operationId: operationId,
        metadata: applied,
        currentCredential: {...applied, 'has_secret': false},
      ),
    );

    expect(result.appliedCredential.secretAvailable, isTrue);
    expect(result.currentCredential?.secretAvailable, isFalse);
  });

  test('exact-origin discovery DTO validates a unique secret-free match', () {
    final lookup = SupplierCredentialOriginLookup.fromJson(
      _originLookupResponse(
        tenantId: tenantId,
        supplierId: supplierId,
      ),
    );

    expect(lookup.status, SupplierCredentialOriginMatchStatus.unique);
    expect(lookup.matchCount, 1);
    expect(lookup.match?.supplierId, supplierId);
    expect(lookup.match?.credentialKey, 'retail_portal');
    expect(lookup.match?.username, isNull);
    expect(lookup.canonicalOrigin, 'https://portal.example.com');
  });

  test('credential origins reject paths and normalize the default port', () {
    expect(
      canonicalSupplierCredentialOrigin('HTTPS://Portal.Example.com:443'),
      'https://portal.example.com',
    );
    expect(
      canonicalSupplierCredentialOrigin('https://portal.example.com/login'),
      isNull,
    );
    expect(
      () => SupplierCredentialInput(
        operationId: operationId,
        supplierId: supplierId,
        kind: SupplierCredentialKind.portalPassword,
        credentialKey: 'retail_portal',
        secret: 'secret',
        originUrl: 'https://portal.example.com/login',
      ),
      throwsArgumentError,
    );
  });

  test('credential authority comes only from canonical profile permission', () {
    expect(_profile(tenantId, const {}).canManageSupplierCredentials, isFalse);
    expect(
      _profile(tenantId, const {'can_manage_supplier_credentials': true})
          .canManageSupplierCredentials,
      isTrue,
    );
  });

  test('metadata status also requires the dedicated credential permission',
      () async {
    final service = SupplierCredentialService(
      profileService: _MutableProfileService(_profile(tenantId, const {})),
      gateway: _RecordingCredentialGateway(const {}),
      currentAuthUserId: () => 'user-a',
    );

    await expectLater(
      service.getStatus(supplierId: supplierId),
      throwsA(isA<SupplierCredentialAccessDenied>()),
    );
  });

  test('upsert uses v2 key, engagement, exact origin, and clear semantics',
      () async {
    const engagementId = '30000000-0000-0000-0000-000000000003';
    final expectedUpdatedAt = DateTime.utc(2026, 8, 8, 12);
    final applied = _credentialMetadataResponse(
      tenantId: tenantId,
      supplierId: supplierId,
      engagementId: engagementId,
      originUrl: 'https://portal.example.com',
      updatedAt: '2026-08-08T12:01:00Z',
    );
    final gateway = _RecordingCredentialGateway(
      _upsertReceipt(
        operationId: operationId,
        metadata: applied,
        action: 'rotate',
      ),
    );
    final service = SupplierCredentialService(
      profileService: _MutableProfileService(
        _profile(
          tenantId,
          const {'can_manage_supplier_credentials': true},
        ),
      ),
      gateway: gateway,
      currentAuthUserId: () => 'user-a',
    );

    final result = await service.upsert(
      SupplierCredentialInput(
        operationId: operationId,
        supplierId: supplierId,
        kind: SupplierCredentialKind.portalPassword,
        credentialKey: 'retail_portal',
        secret: 'replacement',
        expectedUpdatedAt: expectedUpdatedAt,
        engagementId: engagementId,
        originUrl: 'HTTPS://PORTAL.EXAMPLE.COM:443',
        username: 'buyer@example.com',
      ),
    );

    expect(gateway.functionName, 'upsert_supplier_credential_v2');
    expect(gateway.params?['p_credential_key'], 'retail_portal');
    expect(gateway.params?['p_operation_id'], operationId);
    expect(
      gateway.params?['p_expected_updated_at'],
      expectedUpdatedAt.toIso8601String(),
    );
    expect(gateway.params?['p_engagement_id'], engagementId);
    expect(gateway.params?['p_origin_url'], 'https://portal.example.com');
    expect(gateway.params?['p_clear_engagement'], isFalse);
    expect(gateway.params?['p_clear_origin'], isFalse);
    expect(result.operationId, operationId);
    expect(result.action, SupplierCredentialUpsertAction.rotate);
    expect(result.appliedCredential.credentialKey, 'retail_portal');
    expect(result.currentCredential?.originUrl, 'https://portal.example.com');
  });

  test('delete uses operation/version and maps a durable tombstone receipt',
      () async {
    final expectedUpdatedAt = DateTime.utc(2026, 8, 8, 12, 1);
    final gateway = _RecordingCredentialGateway(
      _deleteReceipt(
        operationId: operationId,
        tenantId: tenantId,
        supplierId: supplierId,
      ),
    );
    final service = SupplierCredentialService(
      profileService: _MutableProfileService(
        _profile(
          tenantId,
          const {'can_manage_supplier_credentials': true},
        ),
      ),
      gateway: gateway,
      currentAuthUserId: () => 'user-a',
    );

    final result = await service.delete(
      supplierId: supplierId,
      kind: SupplierCredentialKind.portalPassword,
      credentialKey: 'retail_portal',
      operationId: operationId,
      expectedUpdatedAt: expectedUpdatedAt,
    );

    expect(gateway.functionName, 'delete_supplier_credential_v2');
    expect(gateway.params?['p_operation_id'], operationId);
    expect(
      gateway.params?['p_expected_updated_at'],
      expectedUpdatedAt.toIso8601String(),
    );
    expect(result.tombstone.credentialKey, 'retail_portal');
    expect(result.currentCredential, isNull);
    expect(result.toString(), isNot(contains('buyer@example.com')));
  });

  test('portal reveal discovers and revalidates one exact origin binding',
      () async {
    final lookup = _originLookupResponse(
      tenantId: tenantId,
      supplierId: supplierId,
    );
    final gateway = _QueueCredentialGateway([
      lookup,
      {
        'tenant_id': tenantId,
        'supplier_id': supplierId,
        'credential_kind': 'portal_password',
        'credential_key': 'retail_portal',
        'origin_url': 'https://portal.example.com',
        'username': 'buyer@example.com',
        'secret': 'revealed-on-demand',
        'updated_at': '2026-08-08T12:00:00Z',
      },
      lookup,
    ]);
    final service = SupplierCredentialService(
      profileService: _MutableProfileService(
        _profile(
          tenantId,
          const {'can_manage_supplier_credentials': true},
        ),
      ),
      gateway: gateway,
      currentAuthUserId: () => 'user-a',
    );

    final resolution = await service.revealPortalCredentialForOrigin(
      origin: 'HTTPS://PORTAL.EXAMPLE.COM:443',
    );

    expect(resolution?.credential.secret, 'revealed-on-demand');
    expect(resolution?.credential.metadata.supplierId, supplierId);
    expect(
      gateway.functionNames,
      [
        'find_supplier_credential_for_origin',
        'get_supplier_credential_v2',
        'find_supplier_credential_for_origin',
      ],
    );
    expect(gateway.params[0]['p_origin_url'], 'https://portal.example.com');
    expect(gateway.params[0]['p_credential_kind'], 'portal_password');
    expect(gateway.params[1]['p_credential_key'], 'retail_portal');
  });

  test('ambiguous exact-origin discovery never reveals a credential', () async {
    final gateway = _QueueCredentialGateway([
      _originLookupResponse(
        tenantId: tenantId,
        supplierId: supplierId,
        ambiguousSupplierId: '40000000-0000-0000-0000-000000000004',
      ),
    ]);
    final service = SupplierCredentialService(
      profileService: _MutableProfileService(
        _profile(
          tenantId,
          const {'can_manage_supplier_credentials': true},
        ),
      ),
      gateway: gateway,
      currentAuthUserId: () => 'user-a',
    );

    final resolution = await service.revealPortalCredentialForOrigin(
      origin: 'https://portal.example.com',
    );

    expect(resolution, isNull);
    expect(gateway.functionNames, ['find_supplier_credential_for_origin']);
  });

  test('metadata-only exact-origin match never calls the reveal RPC', () async {
    final gateway = _QueueCredentialGateway([
      _originLookupResponse(
        tenantId: tenantId,
        supplierId: supplierId,
        hasSecret: false,
      ),
    ]);
    final service = SupplierCredentialService(
      profileService: _MutableProfileService(
        _profile(
          tenantId,
          const {'can_manage_supplier_credentials': true},
        ),
      ),
      gateway: gateway,
      currentAuthUserId: () => 'user-a',
    );

    final resolution = await service.revealPortalCredentialForOrigin(
      origin: 'https://portal.example.com',
    );

    expect(resolution, isNull);
    expect(gateway.functionNames, ['find_supplier_credential_for_origin']);
  });

  test('post-reveal ambiguity prevents the secret leaving the service',
      () async {
    final unique = _originLookupResponse(
      tenantId: tenantId,
      supplierId: supplierId,
    );
    final gateway = _QueueCredentialGateway([
      unique,
      {
        'tenant_id': tenantId,
        'supplier_id': supplierId,
        'credential_kind': 'portal_password',
        'credential_key': 'retail_portal',
        'origin_url': 'https://portal.example.com',
        'secret': 'must-not-leave',
        'updated_at': '2026-08-08T12:00:00Z',
      },
      _originLookupResponse(
        tenantId: tenantId,
        supplierId: supplierId,
        ambiguousSupplierId: '40000000-0000-0000-0000-000000000004',
      ),
    ]);
    final service = SupplierCredentialService(
      profileService: _MutableProfileService(
        _profile(
          tenantId,
          const {'can_manage_supplier_credentials': true},
        ),
      ),
      gateway: gateway,
      currentAuthUserId: () => 'user-a',
    );

    final resolution = await service.revealPortalCredentialForOrigin(
      origin: 'https://portal.example.com',
    );

    expect(resolution, isNull);
  });

  test('delayed confirmation rejects rotation of the same origin and key',
      () async {
    final selected = _originLookupResponse(
      tenantId: tenantId,
      supplierId: supplierId,
    );
    final rotated = _originLookupResponse(
      tenantId: tenantId,
      supplierId: supplierId,
      updatedAt: '2026-08-08T12:01:00Z',
    );
    final confirmation = Completer<dynamic>();
    final gateway = _QueueCredentialGateway([
      selected,
      {
        'tenant_id': tenantId,
        'supplier_id': supplierId,
        'credential_kind': 'portal_password',
        'credential_key': 'retail_portal',
        'origin_url': 'https://portal.example.com',
        'secret': 'stale-after-rotation',
        'updated_at': '2026-08-08T12:00:00Z',
      },
      confirmation.future,
    ]);
    final service = SupplierCredentialService(
      profileService: _MutableProfileService(
        _profile(
          tenantId,
          const {'can_manage_supplier_credentials': true},
        ),
      ),
      gateway: gateway,
      currentAuthUserId: () => 'user-a',
    );

    final pending = service.revealPortalCredentialForOrigin(
      origin: 'https://portal.example.com',
    );
    await gateway.waitForCall(2);
    confirmation.complete(rotated);

    expect(await pending, isNull);
  });

  test('delayed reveal rejects delete and recreate of the same key and origin',
      () async {
    final selected = _originLookupResponse(
      tenantId: tenantId,
      supplierId: supplierId,
    );
    final recreatedReveal = Completer<dynamic>();
    final gateway = _QueueCredentialGateway([
      selected,
      recreatedReveal.future,
    ]);
    final service = SupplierCredentialService(
      profileService: _MutableProfileService(
        _profile(
          tenantId,
          const {'can_manage_supplier_credentials': true},
        ),
      ),
      gateway: gateway,
      currentAuthUserId: () => 'user-a',
    );

    final pending = service.revealPortalCredentialForOrigin(
      origin: 'https://portal.example.com',
    );
    await gateway.waitForCall(1);
    recreatedReveal.complete({
      'tenant_id': tenantId,
      'supplier_id': supplierId,
      'credential_kind': 'portal_password',
      'credential_key': 'retail_portal',
      'origin_url': 'https://portal.example.com',
      'secret': 'new-credential-secret',
      'updated_at': '2026-08-08T12:01:00Z',
    });

    expect(await pending, isNull);
    expect(gateway.functionNames, [
      'find_supplier_credential_for_origin',
      'get_supplier_credential_v2',
    ]);
  });

  for (final operation in _delayedOperations(
    tenantId: tenantId,
    supplierId: supplierId,
  )) {
    test('${operation.name} rejects a response completed after logout',
        () async {
      final profileService = _MutableProfileService(
        _profile(
          tenantId,
          const {'can_manage_supplier_credentials': true},
        ),
      );
      final gateway = _DelayedCredentialGateway();
      final service = SupplierCredentialService(
        profileService: profileService,
        gateway: gateway,
        currentAuthUserId: () => profileService.current?.userId,
      );

      final pending = operation.start(service);
      profileService.current = null;
      gateway.completer.complete(operation.response);

      await expectLater(
        pending,
        throwsA(isA<SupplierCredentialAccessDenied>()),
      );
    });
  }

  test('credential reveal rejects an A to B to A authority race', () async {
    final firstA = _profile(
      tenantId,
      const {'can_manage_supplier_credentials': true},
    );
    final profileService = _MutableProfileService(firstA);
    final gateway = _DelayedCredentialGateway();
    final service = SupplierCredentialService(
      profileService: profileService,
      gateway: gateway,
      currentAuthUserId: () => profileService.current?.userId,
    );

    final pending = service.get(
      supplierId: supplierId,
      kind: SupplierCredentialKind.portalPassword,
      credentialKey: 'retail_portal',
    );
    profileService.current = _profile(
      '90000000-0000-0000-0000-000000000009',
      const {'can_manage_supplier_credentials': true},
      userId: 'user-b',
    );
    profileService.current = _profile(
      tenantId,
      const {'can_manage_supplier_credentials': true},
    );
    gateway.completer.complete({
      'tenant_id': tenantId,
      'supplier_id': supplierId,
      'credential_kind': 'portal_password',
      'credential_key': 'retail_portal',
      'username': 'buyer@example.com',
      'secret': 'old-scope-secret',
    });

    await expectLater(
      pending,
      throwsA(isA<SupplierCredentialAccessDenied>()),
    );
  });

  test('credential reveal rejects auth logout before profile rebuild',
      () async {
    final profileService = _MutableProfileService(
      _profile(
        tenantId,
        const {'can_manage_supplier_credentials': true},
      ),
    );
    final gateway = _DelayedCredentialGateway();
    String? authUserId = 'user-a';
    final service = SupplierCredentialService(
      profileService: profileService,
      gateway: gateway,
      currentAuthUserId: () => authUserId,
    );

    final pending = service.get(
      supplierId: supplierId,
      kind: SupplierCredentialKind.portalPassword,
      credentialKey: 'retail_portal',
    );
    authUserId = null;
    gateway.completer.complete({
      'tenant_id': tenantId,
      'supplier_id': supplierId,
      'credential_kind': 'portal_password',
      'credential_key': 'retail_portal',
      'secret': 'old-scope-secret',
    });

    await expectLater(
      pending,
      throwsA(isA<SupplierCredentialAccessDenied>()),
    );
    expect(profileService.current?.userId, 'user-a');
  });
}

CurrentUserProfile _profile(
  String tenantId,
  Map<String, bool> permissions, {
  String userId = 'user-a',
}) {
  return CurrentUserProfile(
    userId: userId,
    email: '$userId@example.com',
    emailVerified: true,
    displayName: userId,
    tenantId: tenantId,
    tenantName: 'Tenant',
    tenantSubdomain: null,
    role: 'owner',
    permissions: permissions,
    employeeLinkState: EmployeeLinkState.unlinked,
    employee: null,
  );
}

Map<String, dynamic> _originLookupResponse({
  required String tenantId,
  required String supplierId,
  String? ambiguousSupplierId,
  String updatedAt = '2026-08-08T12:00:00Z',
  bool? hasSecret,
}) {
  Map<String, dynamic> candidate(String id, String key) => {
        'supplier_id': id,
        'credential_kind': 'portal_password',
        'credential_key': key,
        'engagement_id': null,
        'origin_url': 'https://portal.example.com',
        'label': 'Portal',
        'updated_at': updatedAt,
        if (hasSecret != null) 'has_secret': hasSecret,
      };
  final candidates = [
    candidate(supplierId, 'retail_portal'),
    if (ambiguousSupplierId != null)
      candidate(ambiguousSupplierId, 'secondary_portal'),
  ];
  return {
    'tenant_id': tenantId,
    'canonical_origin': 'https://portal.example.com',
    'credential_kind': 'portal_password',
    'match_status': ambiguousSupplierId == null ? 'unique' : 'ambiguous',
    'match_count': candidates.length,
    'match': ambiguousSupplierId == null ? candidates.single : null,
    'candidates': candidates,
  };
}

Map<String, dynamic> _credentialMetadataResponse({
  required String tenantId,
  required String supplierId,
  String? engagementId,
  String? originUrl,
  String updatedAt = '2026-08-08T12:00:00Z',
}) {
  return {
    'tenant_id': tenantId,
    'supplier_id': supplierId,
    'credential_kind': 'portal_password',
    'credential_key': 'retail_portal',
    'engagement_id': engagementId,
    'origin_url': originUrl,
    'label': 'Portal',
    'username': 'buyer@example.com',
    'updated_at': updatedAt,
  };
}

Map<String, dynamic> _upsertReceipt({
  required String operationId,
  required Map<String, dynamic> metadata,
  String action = 'create',
  bool idempotentReplay = false,
  Map<String, dynamic>? currentCredential,
}) {
  return {
    'operation_id': operationId,
    'idempotent_replay': idempotentReplay,
    'action': action,
    'credential_stored': true,
    'tenant_id': metadata['tenant_id'],
    'supplier_id': metadata['supplier_id'],
    'credential_kind': metadata['credential_kind'],
    'credential_key': metadata['credential_key'],
    'engagement_id': metadata['engagement_id'],
    'origin_url': metadata['origin_url'],
    'label': metadata['label'],
    'username': metadata['username'],
    'updated_at': metadata['updated_at'],
    'applied_credential': metadata,
    'current_credential': currentCredential ?? metadata,
  };
}

Map<String, dynamic> _deleteReceipt({
  required String operationId,
  required String tenantId,
  required String supplierId,
  bool idempotentReplay = false,
}) {
  return {
    'operation_id': operationId,
    'idempotent_replay': idempotentReplay,
    'action': 'delete',
    'deleted': true,
    'tenant_id': tenantId,
    'supplier_id': supplierId,
    'credential_kind': 'portal_password',
    'credential_key': 'retail_portal',
    'tombstone': {
      'credential_id': '60000000-0000-0000-0000-000000000006',
      'tenant_id': tenantId,
      'supplier_id': supplierId,
      'credential_kind': 'portal_password',
      'credential_key': 'retail_portal',
      'engagement_id': null,
      'origin_url': 'https://portal.example.com',
      'label': 'Portal',
      'username': 'buyer@example.com',
      'previous_updated_at': '2026-08-08T12:01:00Z',
      'deleted_at': '2026-08-08T12:02:00Z',
    },
    'current_credential': null,
  };
}

class _MutableProfileService extends CurrentUserProfileService {
  _MutableProfileService(this.current)
      : super(gateway: _UnusedProfileGateway());

  CurrentUserProfile? current;

  @override
  CurrentUserProfile? get profile => current;
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
  }) {
    return completer.future;
  }
}

class _RecordingCredentialGateway implements SupplierCredentialGateway {
  _RecordingCredentialGateway(this.response);

  final dynamic response;
  String? functionName;
  Map<String, dynamic>? params;

  @override
  Future<dynamic> rpc(
    String functionName, {
    required Map<String, dynamic> params,
  }) async {
    this.functionName = functionName;
    this.params = params;
    return response;
  }
}

class _QueueCredentialGateway implements SupplierCredentialGateway {
  _QueueCredentialGateway(this.responses);

  final List<dynamic> responses;
  final List<String> functionNames = [];
  final List<Map<String, dynamic>> params = [];
  final Map<int, Completer<void>> _started = {};

  Future<void> waitForCall(int index) =>
      (_started[index] ??= Completer<void>()).future;

  @override
  Future<dynamic> rpc(
    String functionName, {
    required Map<String, dynamic> params,
  }) async {
    final index = functionNames.length;
    functionNames.add(functionName);
    this.params.add(params);
    final started = _started[index] ??= Completer<void>();
    if (!started.isCompleted) started.complete();
    return responses[index];
  }
}

class _DelayedOperation {
  const _DelayedOperation({
    required this.name,
    required this.start,
    required this.response,
  });

  final String name;
  final Future<dynamic> Function(SupplierCredentialService service) start;
  final dynamic response;
}

List<_DelayedOperation> _delayedOperations({
  required String tenantId,
  required String supplierId,
}) {
  final metadata = {
    'tenant_id': tenantId,
    'supplier_id': supplierId,
    'credential_kind': 'portal_password',
    'credential_key': 'retail_portal',
    'label': 'Portal',
    'username': 'buyer@example.com',
  };
  return [
    _DelayedOperation(
      name: 'status',
      start: (service) => service.getStatus(supplierId: supplierId),
      response: {
        'tenant_id': tenantId,
        'supplier_id': supplierId,
        'has_portal_credential': true,
        'credentials': [metadata],
      },
    ),
    _DelayedOperation(
      name: 'origin discovery',
      start: (service) => service.findForOrigin(
        origin: 'https://portal.example.com',
        kind: SupplierCredentialKind.portalPassword,
      ),
      response: _originLookupResponse(
        tenantId: tenantId,
        supplierId: supplierId,
      ),
    ),
    _DelayedOperation(
      name: 'reveal',
      start: (service) => service.get(
        supplierId: supplierId,
        kind: SupplierCredentialKind.portalPassword,
        credentialKey: 'retail_portal',
      ),
      response: {...metadata, 'secret': 'old-scope-secret'},
    ),
    _DelayedOperation(
      name: 'upsert',
      start: (service) => service.upsert(
        SupplierCredentialInput(
          operationId: '40000000-0000-0000-0000-000000000004',
          supplierId: supplierId,
          kind: SupplierCredentialKind.portalPassword,
          credentialKey: 'retail_portal',
          secret: 'replacement',
        ),
      ),
      response: {...metadata, 'credential_stored': true},
    ),
    _DelayedOperation(
      name: 'delete',
      start: (service) => service.delete(
        supplierId: supplierId,
        kind: SupplierCredentialKind.portalPassword,
        credentialKey: 'retail_portal',
        operationId: '50000000-0000-0000-0000-000000000005',
        expectedUpdatedAt: DateTime.utc(2026, 8, 8, 12),
      ),
      response: true,
    ),
  ];
}
