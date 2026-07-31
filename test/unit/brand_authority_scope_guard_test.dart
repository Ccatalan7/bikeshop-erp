import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/inventory/services/brand_service.dart';
import 'package:vinabike_erp/shared/services/authority_scoped_cache.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

const _userA = '00000000-0000-4000-8000-000000000001';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
      httpClient: MockClient(
        (request) async => http.Response(
          '[]',
          200,
          headers: const {'content-type': 'application/json'},
          request: request,
        ),
      ),
    );
    await _installAuthenticatedTestSession();
  });

  test(
    'reinstalled same-user tenant authority rejects consecutive disagreements',
    () async {
      final database = _RecordingDatabaseService();
      final tenantService = TenantService.testing(
        currentUserId: () => _userA,
        profileLookup: (userId) async {
          expect(userId, _userA);
          return const [
            {
              'tenant_id': 'tenant-a',
              'role': 'admin',
              'permissions': <String, dynamic>{},
            },
          ];
        },
      );
      final service = BrandService(
        database,
        tenantService: tenantService,
      );
      addTearDown(() {
        service.dispose();
        tenantService.dispose();
        database.dispose();
      });

      for (var attempt = 0; attempt < 2; attempt++) {
        service.bindAuthorityScope(
          userId: _userA,
          tenantId: 'tenant-b',
        );
        await expectLater(
          service.getBrands(forceRefresh: true),
          throwsA(isA<AuthorityScopeChangedException>()),
        );
      }

      expect(database.selectCalls, 0);
      expect(service.cachedBrands, isEmpty);
      expect(service.hasBrandsCache, isFalse);
    },
  );
}

Future<void> _installAuthenticatedTestSession() async {
  final header = base64Url
      .encode(utf8.encode(jsonEncode({'alg': 'none', 'typ': 'JWT'})))
      .replaceAll('=', '');
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'exp': 4102444800,
            'sub': _userA,
            'role': 'authenticated',
          }),
        ),
      )
      .replaceAll('=', '');
  final session = jsonEncode({
    'access_token': '$header.$payload.signature',
    'expires_in': 3600,
    'refresh_token': 'test-refresh-token',
    'token_type': 'bearer',
    'user': {
      'id': _userA,
      'app_metadata': const <String, dynamic>{},
      'user_metadata': const <String, dynamic>{},
      'aud': 'authenticated',
      'created_at': '2026-07-28T00:00:00.000Z',
    },
  });
  await Supabase.instance.client.auth.recoverSession(session);
}

class _RecordingDatabaseService extends DatabaseService {
  int selectCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> select(
    String table, {
    String? selectColumns,
    String? where,
    List<String>? whereIn,
    String? orderBy,
    bool descending = false,
    int? limit,
    int? offset,
    bool fetchAll = false,
  }) async {
    selectCalls++;
    return const [];
  }
}
