import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/settings/models/company_profile.dart';
import 'package:vinabike_erp/modules/settings/services/company_profile_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

const _tenantId = '71000000-0000-4000-8000-000000000001';
const _otherTenantId = '71000000-0000-4000-8000-000000000002';

void main() {
  test('neutral company draft contains no foreign business identity', () {
    final draft = CompanyProfile.neutralDraft(
      tenantId: _tenantId,
      shopName: 'Tienda del tenant',
      ownerEmail: 'owner@tenant.example',
    );

    expect(draft.tenantId, _tenantId);
    expect(draft.name, 'Tienda del tenant');
    expect(draft.email, 'owner@tenant.example');
    expect(draft.displayName, 'Tienda del tenant');
    expect(draft.legalName, isEmpty);
    expect(draft.fantasyName, isEmpty);
    expect(draft.taxId, isEmpty);
    expect(draft.businessActivity, isEmpty);
    expect(draft.phone, isEmpty);
    expect(draft.whatsappPhone, isEmpty);
    expect(draft.whatsappApiPhone, isEmpty);
    expect(draft.billingEmail, isEmpty);
    expect(draft.publicEmail, isEmpty);
    expect(draft.country, isEmpty);
  });

  test('opening company settings returns an unsaved tenant-derived draft',
      () async {
    final requests = <http.BaseRequest>[];
    final client = _client((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/companies')) {
        return _jsonResponse(request, const []);
      }
      if (request.url.path.endsWith('/tenants')) {
        return _jsonResponse(request, const [
          {
            'shop_name': 'Tienda propia',
            'owner_email': 'owner@propia.example',
          },
        ]);
      }
      throw StateError('Unexpected request: ${request.method} ${request.url}');
    });
    addTearDown(client.dispose);

    final service = CompanyProfileService(
      client: client,
      tenantService: _tenantService(),
    );

    final draft = await service.loadInitialCompanyProfile();

    expect(draft.id, isNull);
    expect(draft.tenantId, _tenantId);
    expect(draft.name, 'Tienda propia');
    expect(draft.email, 'owner@propia.example');
    expect(draft.legalName, isEmpty);
    expect(draft.taxId, isEmpty);
    expect(draft.phone, isEmpty);
    expect(
      requests.map((request) => request.method).toSet(),
      equals({'GET'}),
      reason: 'Opening the page must never persist or publish the draft.',
    );
    expect(
      requests.where(
        (request) => request.url.path.endsWith('/website_settings'),
      ),
      isEmpty,
    );
  });

  test('public company projection is one atomic tenant-key upsert', () async {
    final requests = <http.BaseRequest>[];
    final client = _client((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/website_settings')) {
        return _jsonResponse(request, const [], statusCode: 201);
      }
      throw StateError('Unexpected request: ${request.method} ${request.url}');
    });
    addTearDown(client.dispose);

    final service = CompanyProfileService(
      client: client,
      tenantService: _tenantService(),
    );
    final profile = CompanyProfile.neutralDraft(
      tenantId: _tenantId,
      shopName: 'Tienda propia',
      ownerEmail: 'owner@propia.example',
    ).copyWith(
      legalName: 'Empresa Propia SpA',
      taxId: '12.345.678-5',
      phone: '+56 9 1111 2222',
    );

    await service.syncPublicSettings(profile);

    expect(requests, hasLength(1));
    final request = requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, endsWith('/website_settings'));
    expect(request.url.queryParameters['on_conflict'], 'tenant_id,key');
    expect(
      request.headers['prefer'],
      contains('resolution=merge-duplicates'),
    );

    final rows = List<Map<String, dynamic>>.from(
      jsonDecode((request as http.Request).body) as List,
    );
    expect(rows, isNotEmpty);
    expect(rows.every((row) => row['tenant_id'] == _tenantId), isTrue);
    expect(rows.map((row) => row['key']).toSet(), contains('business_tax_id'));
    expect(
      rows.singleWhere((row) => row['key'] == 'business_tax_id')['value'],
      '12.345.678-5',
    );
    expect(
      rows.singleWhere((row) => row['key'] == 'whatsapp_phone')['value'],
      isEmpty,
      reason: 'Cleared owner fields must clear their stale public projection.',
    );
  });

  test('a profile lease rejects every write after the active tenant changes',
      () async {
    final requests = <http.BaseRequest>[];
    var currentUserId = 'user-a';
    final client = _client((request) async {
      requests.add(request);
      throw StateError('A mismatched tenant must fail before HTTP.');
    });
    addTearDown(client.dispose);
    final service = CompanyProfileService(
      client: client,
      tenantService: _switchableTenantService(
        currentUserId: () => currentUserId,
      ),
    );
    final tenantAProfile = CompanyProfile.neutralDraft(
      tenantId: _tenantId,
      shopName: 'Empresa A',
      ownerEmail: 'owner-a@example.invalid',
    );

    currentUserId = 'user-b';

    await expectLater(
      service.saveCompany(tenantAProfile, syncPublicData: false),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      service.syncPublicSettings(tenantAProfile),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      service.saveBankAccounts(
        companyId: '71000000-0000-4000-8000-000000000010',
        accounts: const [],
        expectedTenantId: _tenantId,
      ),
      throwsA(isA<StateError>()),
    );

    expect(
      requests,
      isEmpty,
      reason: 'No table write may be attempted using tenant B for A data.',
    );
  });

  test('tenant change after company insert aborts every later write', () async {
    final requests = <http.BaseRequest>[];
    var currentUserId = 'user-a';
    final client = _client((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/companies') && request.method == 'POST') {
        currentUserId = 'user-b';
        return _jsonResponse(
          request,
          {
            'id': '71000000-0000-4000-8000-000000000010',
            'tenant_id': _tenantId,
            'name': 'Empresa A',
            'legal_name': '',
            'fantasy_name': '',
            'tax_id': '',
            'business_activity': '',
            'address': '',
            'comuna': '',
            'city': '',
            'region': '',
            'postal_code': '',
            'country': 'Chile',
            'phone': '',
            'whatsapp_phone': '',
            'whatsapp_api_phone': '',
            'support_phone': '',
            'email': 'owner-a@example.invalid',
            'billing_email': '',
            'public_email': '',
            'website_url': '',
            'is_default': true,
            'metadata': <String, dynamic>{},
          },
          statusCode: 201,
        );
      }
      throw StateError(
        'The operation must stop before a second database request.',
      );
    });
    addTearDown(client.dispose);
    final service = CompanyProfileService(
      client: client,
      tenantService: _switchableTenantService(
        currentUserId: () => currentUserId,
      ),
    );
    final tenantAProfile = CompanyProfile.neutralDraft(
      tenantId: _tenantId,
      shopName: 'Empresa A',
      ownerEmail: 'owner-a@example.invalid',
    );

    await expectLater(
      service.saveCompany(tenantAProfile),
      throwsA(isA<StateError>()),
    );

    expect(requests, hasLength(1));
    expect(requests.single.url.path, endsWith('/companies'));
    expect(
      requests.where(
        (request) =>
            request.url.path.endsWith('/website_settings') ||
            request.method == 'PATCH',
      ),
      isEmpty,
      reason: 'Default flipping and public projection are later steps.',
    );
  });
}

TenantService _tenantService() {
  return TenantService.testing(
    currentUserId: () => 'test-user',
    profileLookup: (_) async => const [
      {
        'tenant_id': _tenantId,
        'role': 'admin',
        'permissions': <String, dynamic>{},
      },
    ],
  );
}

TenantService _switchableTenantService({
  required String Function() currentUserId,
}) {
  return TenantService.testing(
    currentUserId: currentUserId,
    profileLookup: (userId) async => [
      {
        'tenant_id': userId == 'user-a' ? _tenantId : _otherTenantId,
        'role': 'admin',
        'permissions': <String, dynamic>{},
      },
    ],
  );
}

SupabaseClient _client(
  Future<http.Response> Function(http.Request request) handler,
) {
  return SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient(handler),
  );
}

http.Response _jsonResponse(
  http.BaseRequest request,
  Object body, {
  int statusCode = 200,
}) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: const {'content-type': 'application/json'},
    request: request,
  );
}
