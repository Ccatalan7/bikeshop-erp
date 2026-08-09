import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/services/supplier_credential_service.dart';
import 'package:vinabike_erp/shared/models/current_user_profile.dart';
import 'package:vinabike_erp/shared/services/browser_supplier_credential_resolver.dart';
import 'package:vinabike_erp/shared/services/current_user_profile_service.dart';

void main() {
  group('exact-origin supplier credential resolution', () {
    test('reveals the exact server-selected supplier, origin, and key',
        () async {
      final requestedOrigins = <String>[];

      final credential = await resolveSupplierCredentialForOrigin(
        origin: 'https://portal.supplier.example/login?next=%2Forders',
        revealCredential: (origin) async {
          requestedOrigins.add(origin);
          return _resolution(origin: origin);
        },
      );

      expect(requestedOrigins, ['https://portal.supplier.example']);
      expect(credential?.tenantId, tenantA);
      expect(credential?.supplierId, supplierA);
      expect(credential?.credentialKey, 'retail_portal');
      expect(credential?.engagementId, engagementA);
      expect(credential?.origin, 'https://portal.supplier.example');
      expect(credential?.username, 'buyer@example.com');
      expect(credential?.password, 'revealed-secret');
      expect(credential.toString(), isNot(contains('revealed-secret')));
      expect(credential.toString(), isNot(contains('buyer@example.com')));
    });

    test('www is a distinct origin and no alias is inferred', () async {
      final requestedOrigins = <String>[];

      final credential = await resolveSupplierCredentialForOrigin(
        origin: 'https://www.portal.supplier.example/login',
        revealCredential: (origin) async {
          requestedOrigins.add(origin);
          return null;
        },
      );

      expect(credential, isNull);
      expect(requestedOrigins, ['https://www.portal.supplier.example']);
    });

    test('non-default ports remain distinct and port 443 canonicalizes',
        () async {
      final requestedOrigins = <String>[];

      final portCredential = await resolveSupplierCredentialForOrigin(
        origin: 'https://portal.supplier.example:8443/login',
        revealCredential: (origin) async {
          requestedOrigins.add(origin);
          return _resolution(origin: origin);
        },
      );
      final defaultPortCredential = await resolveSupplierCredentialForOrigin(
        origin: 'https://portal.supplier.example:443/login',
        revealCredential: (origin) async {
          requestedOrigins.add(origin);
          return _resolution(origin: origin);
        },
      );

      expect(portCredential?.origin, 'https://portal.supplier.example:8443');
      expect(defaultPortCredential?.origin, 'https://portal.supplier.example');
      expect(requestedOrigins, [
        'https://portal.supplier.example:8443',
        'https://portal.supplier.example',
      ]);
    });

    test('HTTP is rejected before protected discovery or reveal', () async {
      var revealCalls = 0;

      final credential = await resolveSupplierCredentialForOrigin(
        origin: 'http://portal.supplier.example/login',
        revealCredential: (_) async {
          revealCalls++;
          return _resolution();
        },
      );

      expect(credential, isNull);
      expect(revealCalls, 0);
      expect(
        normalizeSupplierBrowserOrigin(
          'http://portal.supplier.example/login',
        ),
        isNull,
      );
    });

    test('no match and ambiguity never produce a browser credential', () async {
      expect(
        await resolveSupplierCredentialForOrigin(
          origin: 'https://none.example/login',
          revealCredential: (_) async => null,
        ),
        isNull,
      );
      expect(
        await resolveSupplierCredentialForOrigin(
          origin: 'https://ambiguous.example/login',
          revealCredential: (origin) async => _resolution(
            origin: origin,
            lookupStatus: SupplierCredentialOriginMatchStatus.ambiguous,
          ),
        ),
        isNull,
      );
    });

    test('submission lookup distinguishes no match from protected failure',
        () async {
      var revealCalls = 0;
      final noMatch = await resolveBrowserSupplierCredentialLookup(
        origin: 'https://none.example/login',
        findCredential: (origin) async => SupplierCredentialOriginLookup(
          tenantId: tenantA,
          canonicalOrigin: origin,
          requestedKind: SupplierCredentialKind.portalPassword,
          status: SupplierCredentialOriginMatchStatus.noMatch,
          matchCount: 0,
          candidates: const [],
        ),
        revealCredential: (_) async {
          revealCalls++;
          return null;
        },
      );
      final failed = await resolveBrowserSupplierCredentialLookup(
        origin: 'https://portal.supplier.example/login',
        findCredential: (_) async => throw StateError('vault unavailable'),
        revealCredential: (_) async {
          revealCalls++;
          return _resolution();
        },
      );

      expect(
        noMatch.status,
        BrowserSupplierCredentialLookupStatus.noMatch,
      );
      expect(
        failed.status,
        BrowserSupplierCredentialLookupStatus.unavailable,
      );
      expect(revealCalls, 0);
    });

    test('submission lookup publishes only the same discovered binding',
        () async {
      final resolution = _resolution();
      final matched = await resolveBrowserSupplierCredentialLookup(
        origin: 'https://portal.supplier.example/login',
        findCredential: (_) async => resolution.lookup,
        revealCredential: (_) async => resolution,
      );
      final changed = await resolveBrowserSupplierCredentialLookup(
        origin: 'https://portal.supplier.example/login',
        findCredential: (_) async => resolution.lookup,
        revealCredential: (_) async => _resolution(
          credentialKey: 'rotated_key',
        ),
      );

      expect(matched.isMatched, isTrue);
      expect(matched.credential?.credentialKey, 'retail_portal');
      expect(
        changed.status,
        BrowserSupplierCredentialLookupStatus.unavailable,
      );
    });

    test('informational lookup performs discovery only and never reveals',
        () async {
      final profileService = _MutableProfileService(
        _profile(tenantId: tenantA),
      );
      final gateway = _RecordingOriginLookupGateway();
      final service = SupplierCredentialService(
        profileService: profileService,
        gateway: gateway,
        currentAuthUserId: () => userA,
      );

      final lookup = await resolveSupplierCredentialReferenceForOrigin(
        origin: 'https://portal.supplier.example/account',
        findCredential: (origin) => service.findForOrigin(
          origin: origin,
          kind: SupplierCredentialKind.portalPassword,
        ),
      );

      expect(lookup?.match?.credentialKey, 'retail_portal');
      expect(gateway.functionNames, ['find_supplier_credential_for_origin']);
      expect(
        gateway.functionNames,
        isNot(contains('get_supplier_credential_v2')),
      );
    });

    test('mismatched key, origin, tenant, or engagement fails closed',
        () async {
      Future<BrowserSupplierCredential?> resolve(
        SupplierCredentialOriginResolution resolution,
      ) {
        return resolveSupplierCredentialForOrigin(
          origin: 'https://portal.supplier.example/login',
          revealCredential: (_) async => resolution,
        );
      }

      expect(
        await resolve(_resolution(credentialKey: 'wrong_key')),
        isNull,
      );
      expect(
        await resolve(
          _resolution(credentialOrigin: 'https://other.example'),
        ),
        isNull,
      );
      expect(
        await resolve(_resolution(credentialTenantId: tenantB)),
        isNull,
      );
      expect(
        await resolve(_resolution(credentialEngagementId: 'other-engagement')),
        isNull,
      );
    });

    test('empty username or secret is discarded', () async {
      expect(
        await resolveSupplierCredentialForOrigin(
          origin: 'https://portal.supplier.example',
          revealCredential: (_) async => _resolution(username: '   '),
        ),
        isNull,
      );
      expect(
        await resolveSupplierCredentialForOrigin(
          origin: 'https://portal.supplier.example',
          revealCredential: (_) async => _resolution(secret: ''),
        ),
        isNull,
      );
    });
  });

  group('browser credential authority lease', () {
    test('requires the exact Auth user, browser identity, profile, and tenant',
        () {
      final profile = _profile(tenantId: tenantA);
      final lease = BrowserCredentialAuthorityLease.capture(
        profile: profile,
        authUserId: userA,
        browserProfileIdentity: userA,
      );

      expect(lease, isNotNull);
      expect(
        lease!.isCurrent(
          profile: profile,
          authUserId: userA,
          browserProfileIdentity: userA,
          requireSupplierCredentialPermission: true,
        ),
        isTrue,
      );
      expect(
        BrowserCredentialAuthorityLease.capture(
          profile: profile,
          authUserId: userA,
          browserProfileIdentity: 'other-browser-user',
        ),
        isNull,
      );
    });

    test('logout, permission revoke, scope change, and ABA invalidate it', () {
      final original = _profile(tenantId: tenantA);
      final lease = BrowserCredentialAuthorityLease.capture(
        profile: original,
        authUserId: userA,
        browserProfileIdentity: userA,
      )!;

      bool owns(CurrentUserProfile? profile, String? authUserId) {
        return lease.isCurrent(
          profile: profile,
          authUserId: authUserId,
          browserProfileIdentity: userA,
          requireSupplierCredentialPermission: true,
        );
      }

      expect(owns(original, null), isFalse, reason: 'logout');
      expect(
        owns(_profile(tenantId: tenantA, canManage: false), userA),
        isFalse,
        reason: 'permission revoke',
      );
      expect(
        owns(_profile(tenantId: tenantB), userA),
        isFalse,
        reason: 'tenant change',
      );
      expect(
        owns(_profile(tenantId: tenantA), userA),
        isFalse,
        reason: 'same-value profile after ABA is a new generation',
      );
    });
  });

  group('delayed protected reveal', () {
    for (final transition in <String, void Function(_AuthorityHarness)>{
      'logout': (harness) => harness.authUserId = null,
      'permission revoke': (harness) => harness.profileService.current =
          _profile(tenantId: tenantA, canManage: false),
      'tenant scope change': (harness) =>
          harness.profileService.current = _profile(tenantId: tenantB),
      'ABA back to the same user and tenant': (harness) {
        harness.profileService.current = _profile(tenantId: tenantB);
        harness.profileService.current = _profile(tenantId: tenantA);
      },
    }.entries) {
      test('${transition.key} cannot publish a delayed secret', () async {
        final harness = _AuthorityHarness();
        BrowserSupplierCredential? published;
        final pending = resolveSupplierCredentialForOrigin(
          origin: 'https://portal.supplier.example/login',
          revealCredential: (origin) =>
              harness.service.revealPortalCredentialForOrigin(origin: origin),
        ).then((credential) {
          published = credential;
          return credential;
        });

        await harness.gateway.revealRequested.future;
        transition.value(harness);
        harness.gateway.completeReveal();

        await expectLater(
          pending,
          throwsA(isA<SupplierCredentialAccessDenied>()),
        );
        expect(published, isNull);
      });
    }
  });
}

const userA = 'user-a';
const tenantA = '10000000-0000-0000-0000-000000000001';
const tenantB = '10000000-0000-0000-0000-000000000002';
const supplierA = '20000000-0000-0000-0000-000000000001';
const engagementA = '30000000-0000-0000-0000-000000000001';

SupplierCredentialOriginResolution _resolution({
  String origin = 'https://portal.supplier.example',
  SupplierCredentialOriginMatchStatus lookupStatus =
      SupplierCredentialOriginMatchStatus.unique,
  String lookupKey = 'retail_portal',
  String? credentialKey,
  String lookupTenantId = tenantA,
  String? credentialTenantId,
  String lookupEngagementId = engagementA,
  String? credentialEngagementId,
  String? credentialOrigin,
  String username = 'buyer@example.com',
  String secret = 'revealed-secret',
}) {
  final selected = SupplierCredentialMetadata(
    tenantId: lookupTenantId,
    supplierId: supplierA,
    kind: SupplierCredentialKind.portalPassword,
    credentialKey: lookupKey,
    engagementId: lookupEngagementId,
    originUrl: origin,
    label: 'Portal retail',
    updatedAt: DateTime.utc(2026, 8, 8),
  );
  final candidates = lookupStatus == SupplierCredentialOriginMatchStatus.unique
      ? [selected]
      : lookupStatus == SupplierCredentialOriginMatchStatus.ambiguous
          ? [
              selected,
              SupplierCredentialMetadata(
                tenantId: lookupTenantId,
                supplierId: 'another-supplier',
                kind: SupplierCredentialKind.portalPassword,
                credentialKey: 'other_portal',
                originUrl: origin,
              ),
            ]
          : const <SupplierCredentialMetadata>[];
  final lookup = SupplierCredentialOriginLookup(
    tenantId: lookupTenantId,
    canonicalOrigin: origin,
    requestedKind: SupplierCredentialKind.portalPassword,
    status: lookupStatus,
    matchCount: candidates.length,
    match: lookupStatus == SupplierCredentialOriginMatchStatus.unique
        ? selected
        : null,
    candidates: candidates,
  );
  final metadata = SupplierCredentialMetadata(
    tenantId: credentialTenantId ?? lookupTenantId,
    supplierId: supplierA,
    kind: SupplierCredentialKind.portalPassword,
    credentialKey: credentialKey ?? lookupKey,
    engagementId: credentialEngagementId ?? lookupEngagementId,
    originUrl: credentialOrigin ?? origin,
    label: 'Portal retail',
    username: username,
    updatedAt: DateTime.utc(2026, 8, 8),
  );
  return SupplierCredentialOriginResolution(
    lookup: lookup,
    credential: SupplierCredential(metadata: metadata, secret: secret),
  );
}

CurrentUserProfile _profile({
  required String tenantId,
  bool canManage = true,
}) {
  return CurrentUserProfile(
    userId: userA,
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

class _AuthorityHarness {
  _AuthorityHarness()
      : profileService = _MutableProfileService(
          _profile(tenantId: tenantA),
        ),
        gateway = _DelayedOriginRevealGateway() {
    service = SupplierCredentialService(
      profileService: profileService,
      gateway: gateway,
      currentAuthUserId: () => authUserId,
    );
  }

  String? authUserId = userA;
  final _MutableProfileService profileService;
  final _DelayedOriginRevealGateway gateway;
  late final SupplierCredentialService service;
}

class _MutableProfileService extends CurrentUserProfileService {
  _MutableProfileService(this._current)
      : super(gateway: _UnusedProfileGateway());

  CurrentUserProfile? _current;

  set current(CurrentUserProfile? value) {
    _current = value;
    notifyListeners();
  }

  @override
  CurrentUserProfile? get profile => _current;
}

class _DelayedOriginRevealGateway implements SupplierCredentialGateway {
  final Completer<void> revealRequested = Completer<void>();
  final Completer<dynamic> _revealResponse = Completer<dynamic>();
  var _originLookups = 0;

  void completeReveal() {
    _revealResponse.complete({
      'tenant_id': tenantA,
      'supplier_id': supplierA,
      'credential_kind': 'portal_password',
      'credential_key': 'retail_portal',
      'engagement_id': engagementA,
      'origin_url': 'https://portal.supplier.example',
      'label': 'Portal retail',
      'username': 'buyer@example.com',
      'secret': 'delayed-secret',
      'updated_at': '2026-08-08T12:00:00Z',
    });
  }

  @override
  Future<dynamic> rpc(
    String functionName, {
    required Map<String, dynamic> params,
  }) async {
    if (functionName == 'find_supplier_credential_for_origin') {
      _originLookups++;
      return _originLookupResponse();
    }
    if (functionName == 'get_supplier_credential_v2') {
      if (!revealRequested.isCompleted) revealRequested.complete();
      return _revealResponse.future;
    }
    throw StateError('Unexpected RPC $functionName ($_originLookups lookups)');
  }
}

class _RecordingOriginLookupGateway implements SupplierCredentialGateway {
  final List<String> functionNames = [];

  @override
  Future<dynamic> rpc(
    String functionName, {
    required Map<String, dynamic> params,
  }) async {
    functionNames.add(functionName);
    if (functionName != 'find_supplier_credential_for_origin') {
      throw StateError('Informational lookup attempted $functionName');
    }
    return _originLookupResponse();
  }
}

Map<String, dynamic> _originLookupResponse() {
  final candidate = {
    'supplier_id': supplierA,
    'credential_kind': 'portal_password',
    'credential_key': 'retail_portal',
    'engagement_id': engagementA,
    'origin_url': 'https://portal.supplier.example',
    'label': 'Portal retail',
    'updated_at': '2026-08-08T12:00:00Z',
  };
  return {
    'tenant_id': tenantA,
    'canonical_origin': 'https://portal.supplier.example',
    'credential_kind': 'portal_password',
    'match_status': 'unique',
    'match_count': 1,
    'match': candidate,
    'candidates': [candidate],
  };
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
