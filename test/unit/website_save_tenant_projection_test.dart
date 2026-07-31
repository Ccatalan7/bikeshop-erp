import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

const _tenantA = '7e290200-0000-4000-8000-000000000001';
const _tenantB = '7e290200-0000-4000-8000-000000000002';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    WebsiteService.setSharedPreferences(
      await SharedPreferences.getInstance(),
    );
  });

  test(
    'late explicit settings write for A cannot replace the loaded B projection',
    () async {
      final writeRequested = Completer<void>();
      final writeResponse = Completer<http.Response>();
      late http.Request capturedWrite;
      final requests = <http.Request>[];

      final harness = _service((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/website_settings') &&
            request.method == 'GET') {
          final tenantId = _tenantFromRequest(request);
          return _jsonResponse(request, [
            {
              'tenant_id': tenantId,
              'key': 'store_name',
              'value': tenantId == _tenantA ? 'Tienda A' : 'Tienda B',
            },
          ]);
        }
        if (request.url.path.endsWith('/website_settings') &&
            request.method == 'POST') {
          capturedWrite = request;
          writeRequested.complete();
          return writeResponse.future;
        }
        throw StateError(
          'Unexpected Supabase request: ${request.method} ${request.url}',
        );
      });
      addTearDown(harness.dispose);

      await harness.service.loadSettingsForTenant(
        _tenantA,
        rethrowErrors: true,
      );
      expect(harness.service.getSetting('store_name'), 'Tienda A');

      final staleWrite = harness.service.saveSettingsForTenant(
        _tenantA,
        const {'store_name': 'Tienda A guardada tarde'},
      );
      await writeRequested.future;

      await harness.service.loadSettingsForTenant(
        _tenantB,
        rethrowErrors: true,
      );
      expect(harness.service.getSetting('store_name'), 'Tienda B');
      expect(harness.service.hasSettingsForTenant(_tenantB), isTrue);

      writeResponse.complete(
        _jsonResponse(capturedWrite, const [], statusCode: 201),
      );
      await staleWrite;

      expect(harness.service.isTenantProjectionActive(_tenantB), isTrue);
      expect(harness.service.hasSettingsForTenant(_tenantB), isTrue);
      expect(harness.service.hasSettingsForTenant(_tenantA), isFalse);
      expect(harness.service.getSetting('store_name'), 'Tienda B');
      expect(
        harness.service.settings.values,
        isNot(contains('Tienda A guardada tarde')),
      );

      final rows = (jsonDecode(capturedWrite.body) as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(growable: false);
      expect(capturedWrite.url.queryParameters['on_conflict'], 'tenant_id,key');
      expect(rows, isNotEmpty);
      expect(rows.every((row) => row['tenant_id'] == _tenantA), isTrue);
      expect(
        rows.singleWhere((row) => row['key'] == 'store_name')['value'],
        'Tienda A guardada tarde',
      );
      expect(
        requests.where(
          (request) =>
              request.method == 'GET' &&
              _tenantFromRequest(request) == _tenantA,
        ),
        hasLength(1),
        reason: 'The stale write must not rebind or reload tenant A.',
      );
    },
  );

  test(
    'late tenant-scoped navigation update for A cannot contaminate B',
    () async {
      final writeRequested = Completer<void>();
      final writeResponse = Completer<http.Response>();
      late http.Request capturedWrite;

      final harness = _service((request) async {
        if (request.url.path.endsWith('/website_navigation') &&
            request.method == 'GET') {
          final tenantId = _tenantFromRequest(request);
          return _jsonResponse(
            request,
            _navigation(
              tenantId,
              headerLabel: tenantId == _tenantA ? 'Inicio A' : 'Inicio B',
            ),
          );
        }
        if (request.url.path.endsWith('/website_navigation') &&
            request.method == 'PATCH') {
          capturedWrite = request;
          writeRequested.complete();
          return writeResponse.future;
        }
        throw StateError(
          'Unexpected Supabase request: ${request.method} ${request.url}',
        );
      });
      addTearDown(harness.dispose);

      await harness.service.loadNavigationForTenant(
        _tenantA,
        notify: false,
      );
      final tenantANavigation = harness.service.headerNavigation.single;
      expect(tenantANavigation.label, 'Inicio A');

      final staleWrite = harness.service.updateNavigationForTenant(
        tenantANavigation.copyWith(label: 'Inicio A guardado tarde'),
        _tenantA,
      );
      await writeRequested.future;

      await harness.service.loadNavigationForTenant(
        _tenantB,
        notify: false,
      );
      expect(harness.service.headerNavigation.single.label, 'Inicio B');

      writeResponse.complete(
        _jsonResponse(
          capturedWrite,
          _navigationRow(
            _tenantA,
            id: 'header-a',
            label: 'Inicio A guardado tarde',
            menuLocation: 'header',
          ),
        ),
      );
      await staleWrite;

      expect(harness.service.isTenantProjectionActive(_tenantB), isTrue);
      expect(
        harness.service.navigation.every((item) => item.tenantId == _tenantB),
        isTrue,
      );
      expect(harness.service.headerNavigation.single.label, 'Inicio B');
      expect(
        harness.service.navigation.map((item) => item.label),
        isNot(contains('Inicio A guardado tarde')),
      );

      expect(capturedWrite.url.queryParameters['tenant_id'], 'eq.$_tenantA');
      expect(capturedWrite.url.queryParameters['id'], 'eq.header-a');
      expect(
        Map<String, dynamic>.from(
            jsonDecode(capturedWrite.body) as Map)['label'],
        'Inicio A guardado tarde',
      );
    },
  );
}

class _ServiceHarness {
  const _ServiceHarness({
    required this.service,
    required this.supabase,
  });

  final WebsiteService service;
  final SupabaseClient supabase;

  void dispose() {
    service.dispose();
    supabase.dispose();
  }
}

_ServiceHarness _service(
  Future<http.Response> Function(http.Request request) handler,
) {
  final supabase = SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient(handler),
  );
  final service = WebsiteService(
    supabase: supabase,
    tenantService: TenantService.testing(
      currentUserId: () => null,
      profileLookup: (_) async => const [],
    ),
    httpClient: MockClient(
      (request) async => throw StateError(
        'Tenant projection tests must not use the WebsiteService edge client.',
      ),
    ),
  );
  return _ServiceHarness(service: service, supabase: supabase);
}

String _tenantFromRequest(http.Request request) {
  final filter = request.url.queryParameters['tenant_id'];
  if (filter == null || !filter.startsWith('eq.')) {
    throw StateError('Missing tenant filter: ${request.url}');
  }
  return filter.substring(3);
}

List<Map<String, dynamic>> _navigation(
  String tenantId, {
  required String headerLabel,
}) {
  final suffix = tenantId == _tenantA ? 'a' : 'b';
  return [
    _navigationRow(
      tenantId,
      id: 'header-$suffix',
      label: headerLabel,
      menuLocation: 'header',
    ),
    _navigationRow(
      tenantId,
      id: 'footer-$suffix',
      label: 'Footer ${suffix.toUpperCase()}',
      menuLocation: 'footer',
    ),
  ];
}

Map<String, dynamic> _navigationRow(
  String tenantId, {
  required String id,
  required String label,
  required String menuLocation,
}) {
  return {
    'id': id,
    'tenant_id': tenantId,
    'menu_location': menuLocation,
    'label': label,
    'link_type': 'action',
    'link_value': '',
    'parent_id': null,
    'order_index': 0,
    'is_visible': true,
    'show_on_desktop': true,
    'show_on_mobile': true,
    'created_at': '2026-07-29T12:00:00.000Z',
    'updated_at': '2026-07-29T12:00:00.000Z',
  };
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
