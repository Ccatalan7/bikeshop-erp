import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

const _tenantA = '72000000-0000-4000-8000-000000000001';
const _tenantB = '72000000-0000-4000-8000-000000000002';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    WebsiteService.setSharedPreferences(
      await SharedPreferences.getInstance(),
    );
  });

  test('synchronous cache binds tenant before replacing the projection',
      () async {
    SharedPreferences.setMockInitialValues({
      'website_public_v2_settings_$_tenantA': jsonEncode({
        'store_name': 'Tienda A',
      }),
      'website_public_v2_settings_$_tenantB': jsonEncode({
        'store_name': 'Tienda B',
      }),
    });

    WebsiteService.setSharedPreferences(await SharedPreferences.getInstance());
    final harness = _service((request) async {
      throw StateError('Synchronous cache must not make HTTP requests.');
    });
    addTearDown(harness.dispose);

    expect(
      harness.service.loadSettingsFromSynchronousCache(_tenantA),
      isTrue,
    );
    expect(harness.service.getSetting('store_name'), 'Tienda A');
    expect(harness.service.hasSettingsForTenant(_tenantA), isTrue);
    expect(harness.service.hasSettingsForTenant(_tenantB), isFalse);

    expect(
      harness.service.loadSettingsFromSynchronousCache(_tenantB),
      isTrue,
    );
    expect(harness.service.getSetting('store_name'), 'Tienda B');
    expect(harness.service.hasSettingsForTenant(_tenantA), isFalse);
    expect(harness.service.hasSettingsForTenant(_tenantB), isTrue);
    expect(harness.service.blocks, isEmpty);
    expect(harness.service.pages, isEmpty);
    expect(harness.service.navigation, isEmpty);
  });

  test('late settings response cannot overwrite a newer tenant', () async {
    final delayed = _DelayedTenantResponses();
    final harness = _service((request) => delayed.handle(request));
    addTearDown(harness.dispose);

    final staleLoad = harness.service.loadSettingsForTenant(_tenantA);
    await delayed.requested(_tenantA);
    final currentLoad = harness.service.loadSettingsForTenant(_tenantB);
    await delayed.requested(_tenantB);

    delayed.complete(_tenantB, [
      {'key': 'store_name', 'value': 'Tienda B'},
    ]);
    await currentLoad;
    delayed.complete(_tenantA, [
      {'key': 'store_name', 'value': 'Tienda A tardía'},
    ]);
    await staleLoad;

    expect(harness.service.getSetting('store_name'), 'Tienda B');
  });

  test('late home blocks response cannot overwrite a newer tenant', () async {
    final delayed = _DelayedTenantResponses();
    final harness = _service((request) => delayed.handle(request));
    addTearDown(harness.dispose);

    final staleLoad = harness.service.loadBlocksForTenant(_tenantA);
    await delayed.requested(_tenantA);
    final currentLoad = harness.service.loadBlocksForTenant(_tenantB);
    await delayed.requested(_tenantB);

    delayed.complete(_tenantB, [
      {
        'id': 'home-b',
        'website_blocks': [_block('block-b')],
      },
    ]);
    await currentLoad;
    delayed.complete(_tenantA, [
      {
        'id': 'home-a',
        'website_blocks': [_block('block-a')],
      },
    ]);
    await staleLoad;

    expect(harness.service.blocks.single['id'], 'block-b');
  });

  test('late pages response cannot overwrite a newer tenant', () async {
    final delayed = _DelayedTenantResponses();
    final harness = _service((request) => delayed.handle(request));
    addTearDown(harness.dispose);

    final staleLoad = harness.service.loadPagesForTenant(_tenantA);
    await delayed.requested(_tenantA);
    final currentLoad = harness.service.loadPagesForTenant(_tenantB);
    await delayed.requested(_tenantB);

    delayed.complete(_tenantB, [_page(_tenantB, title: 'Inicio B')]);
    await currentLoad;
    delayed.complete(_tenantA, [_page(_tenantA, title: 'Inicio A tardío')]);
    await staleLoad;

    expect(harness.service.pages.single.tenantId, _tenantB);
    expect(harness.service.pages.single.title, 'Inicio B');
    expect(
      harness.service.hasAuthoritativePagePublicationForTenant(_tenantB),
      isTrue,
    );
  });

  test('late navigation response cannot overwrite a newer tenant', () async {
    final delayed = _DelayedTenantResponses();
    final harness = _service((request) => delayed.handle(request));
    addTearDown(harness.dispose);

    final staleLoad = harness.service.loadNavigationForTenant(
      _tenantA,
      notify: false,
    );
    await delayed.requested(_tenantA);
    final currentLoad = harness.service.loadNavigationForTenant(
      _tenantB,
      notify: false,
    );
    await delayed.requested(_tenantB);

    delayed.complete(_tenantB, _navigation(_tenantB, label: 'Inicio B'));
    await currentLoad;
    delayed.complete(
      _tenantA,
      _navigation(_tenantA, label: 'Inicio A tardío'),
    );
    await staleLoad;

    expect(
      harness.service.navigation.every((item) => item.tenantId == _tenantB),
      isTrue,
    );
    expect(harness.service.headerNavigation.single.label, 'Inicio B');
  });

  test('failed footer seed can retry after a tenant switch', () async {
    final firstSeedResponse = Completer<http.Response>();
    final firstSeedRequested = Completer<void>();
    var seedRequests = 0;

    final harness = _service(
      (request) async {
        if (request.url.path.endsWith('/website_navigation')) {
          return _jsonResponse(request, const <dynamic>[]);
        }
        if (request.url.path.endsWith('/website_settings')) {
          return _jsonResponse(request, const <dynamic>[]);
        }
        if (request.url.path.endsWith(
          '/rpc/ensure_default_footer_navigation',
        )) {
          seedRequests++;
          if (seedRequests == 1) {
            firstSeedRequested.complete();
            return firstSeedResponse.future;
          }
          return _jsonResponse(request, {
            'tenant_id': _tenantA,
            'created': true,
            'items': const <dynamic>[],
          });
        }
        throw StateError(
          'Unexpected Supabase request: ${request.method} ${request.url}',
        );
      },
      tenantService: TenantService.testing(
        currentUserId: () => 'user-a',
        profileLookup: (_) async => [
          {
            'tenant_id': _tenantA,
            'role': 'admin',
            'permissions': <String, dynamic>{},
          },
        ],
      ),
    );
    addTearDown(harness.dispose);
    await _installAuthenticatedSession(harness.supabase, userId: 'user-a');

    final staleLoad = harness.service.loadNavigationForTenant(
      _tenantA,
      notify: false,
    );
    await firstSeedRequested.future;

    // Moving the service projection to B invalidates the in-flight A lease.
    await harness.service.loadSettingsForTenant(_tenantB);
    firstSeedResponse.completeError(StateError('transient seed failure'));
    await staleLoad;

    // Returning to A must not remain blocked by the failed stale attempt.
    await harness.service.loadNavigationForTenant(
      _tenantA,
      notify: false,
    );

    expect(seedRequests, 2);
  });

  test('unified A to B race discards A and keeps the loaded fast path',
      () async {
    final rpcResponses = <String, Completer<http.Response>>{
      _tenantA: Completer<http.Response>(),
      _tenantB: Completer<http.Response>(),
    };
    final rpcRequests = <String, http.Request>{};
    final rpcRequested = <String, Completer<void>>{
      _tenantA: Completer<void>(),
      _tenantB: Completer<void>(),
    };
    var requestCount = 0;

    final harness = _service((request) async {
      requestCount++;
      if (request.url.path.endsWith('/rpc/get_public_store_data')) {
        final tenantId =
            jsonDecode(request.body)['p_tenant_id']?.toString() ?? '';
        rpcRequests[tenantId] = request;
        if (!rpcRequested[tenantId]!.isCompleted) {
          rpcRequested[tenantId]!.complete();
        }
        return rpcResponses[tenantId]!.future;
      }

      final tenantId = _tenantFromRequest(request);
      if (request.url.path.endsWith('/website_pages')) {
        return _jsonResponse(
          request,
          [_page(tenantId, title: 'Inicio ${_suffix(tenantId)}')],
        );
      }
      if (request.url.path.endsWith('/website_navigation')) {
        return _jsonResponse(
          request,
          _navigation(tenantId, label: 'Inicio ${_suffix(tenantId)}'),
        );
      }
      throw StateError('Unexpected request: ${request.method} ${request.url}');
    });
    addTearDown(harness.dispose);

    final staleLoad = harness.service.loadPublicStoreDataUnified(
      _tenantA,
      forceRefresh: true,
    );
    await rpcRequested[_tenantA]!.future;
    final currentLoad = harness.service.loadPublicStoreDataUnified(
      _tenantB,
      forceRefresh: true,
    );
    await rpcRequested[_tenantB]!.future;

    rpcResponses[_tenantB]!.complete(
      _jsonResponse(rpcRequests[_tenantB]!, {
        'tenant_id': _tenantB,
        'settings': {'store_name': 'Tienda B'},
        'blocks': [_block('unified-block-b')],
      }),
    );
    await currentLoad;
    rpcResponses[_tenantA]!.complete(
      _jsonResponse(rpcRequests[_tenantA]!, {
        'tenant_id': _tenantA,
        'settings': {'store_name': 'Tienda A tardía'},
        'blocks': [_block('unified-block-a')],
      }),
    );
    await staleLoad;

    expect(harness.service.getSetting('store_name'), 'Tienda B');
    expect(harness.service.blocks.single['id'], 'unified-block-b');
    expect(harness.service.pages.single.tenantId, _tenantB);
    expect(
      harness.service.navigation.every((item) => item.tenantId == _tenantB),
      isTrue,
    );

    final completedRequestCount = requestCount;
    await harness.service.loadPublicStoreDataUnified(_tenantB);
    expect(
      requestCount,
      completedRequestCount,
      reason: 'The same-tenant loaded happy path must remain zero-I/O.',
    );
  });

  test('tenant-mismatched prefetch is discarded before edge hydration',
      () async {
    var rpcRequests = 0;
    var edgeRequests = 0;
    final harness = _service(
      (request) async {
        if (request.url.path.endsWith('/rpc/get_public_store_data')) {
          rpcRequests++;
          return _jsonResponse(request, {
            'tenant_id': _tenantB,
            'settings': {'store_name': 'Tienda B directa'},
            'blocks': [_block('direct-block-b')],
          });
        }
        final tenantId = _tenantFromRequest(request);
        if (request.url.path.endsWith('/website_pages')) {
          return _jsonResponse(
            request,
            [_page(tenantId, title: 'Inicio ${_suffix(tenantId)}')],
          );
        }
        if (request.url.path.endsWith('/website_navigation')) {
          return _jsonResponse(
            request,
            _navigation(tenantId, label: 'Inicio ${_suffix(tenantId)}'),
          );
        }
        throw StateError(
          'Unexpected Supabase request: ${request.method} ${request.url}',
        );
      },
      preloadedStoreDataLoader: (_) async => {
        'tenant_id': _tenantA,
        'settings': {'store_name': 'Tienda A inyectada'},
        'blocks': [_block('prefetch-block-a')],
      },
      edgeHandler: (request) async {
        edgeRequests++;
        return _jsonResponse(request, {
          'tenant_id': _tenantB,
          'settings': {'store_name': 'Tienda B edge'},
          'blocks': [_block('edge-block-b')],
          '_cache': 'HIT',
        });
      },
    );
    addTearDown(harness.dispose);

    await harness.service.loadPublicStoreDataUnified(_tenantB);

    expect(edgeRequests, 1);
    expect(rpcRequests, 0);
    expect(harness.service.getSetting('store_name'), 'Tienda B edge');
    expect(harness.service.blocks.single['id'], 'edge-block-b');
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('website_public_v2_settings_$_tenantB'),
      isNot(contains('Tienda A inyectada')),
    );
  });

  test('tenant-mismatched edge payload falls through to direct origin',
      () async {
    var rpcRequests = 0;
    final harness = _service(
      (request) async {
        if (request.url.path.endsWith('/rpc/get_public_store_data')) {
          rpcRequests++;
          return _jsonResponse(request, {
            'tenant_id': _tenantB,
            'settings': {'store_name': 'Tienda B directa'},
            'blocks': [_block('direct-block-b')],
          });
        }
        final tenantId = _tenantFromRequest(request);
        if (request.url.path.endsWith('/website_pages')) {
          return _jsonResponse(
            request,
            [_page(tenantId, title: 'Inicio ${_suffix(tenantId)}')],
          );
        }
        if (request.url.path.endsWith('/website_navigation')) {
          return _jsonResponse(
            request,
            _navigation(tenantId, label: 'Inicio ${_suffix(tenantId)}'),
          );
        }
        throw StateError(
          'Unexpected Supabase request: ${request.method} ${request.url}',
        );
      },
      preloadedStoreDataLoader: (_) async => null,
      edgeHandler: (request) async => _jsonResponse(request, {
        'tenant_id': _tenantA,
        'settings': {'store_name': 'Tienda A edge'},
        'blocks': [_block('edge-block-a')],
        '_cache': 'HIT',
      }),
    );
    addTearDown(harness.dispose);

    await harness.service.loadPublicStoreDataUnified(_tenantB);

    expect(rpcRequests, 1);
    expect(harness.service.getSetting('store_name'), 'Tienda B directa');
    expect(harness.service.blocks.single['id'], 'direct-block-b');
  });

  test('tenant-mismatched direct payload falls back without caching it',
      () async {
    final harness = _service(
      (request) async {
        final tenantId = request.url.path.endsWith('/rpc/get_public_store_data')
            ? jsonDecode(request.body)['p_tenant_id']?.toString() ?? ''
            : _tenantFromRequest(request);
        if (request.url.path.endsWith('/rpc/get_public_store_data')) {
          return _jsonResponse(request, {
            'tenant_id': _tenantA,
            'settings': {'store_name': 'Tienda A directa'},
            'blocks': [_block('direct-block-a')],
          });
        }
        if (request.url.path.endsWith('/website_settings')) {
          return _jsonResponse(request, [
            {'key': 'store_name', 'value': 'Tienda B fallback'},
          ]);
        }
        if (request.url.path.endsWith('/website_pages')) {
          final select = request.url.queryParameters['select'] ?? '';
          if (select.contains('website_blocks')) {
            return _jsonResponse(request, [
              {
                'id': 'home-b',
                'website_blocks': [_block('fallback-block-b')],
              },
            ]);
          }
          return _jsonResponse(
            request,
            [_page(tenantId, title: 'Inicio ${_suffix(tenantId)}')],
          );
        }
        if (request.url.path.endsWith('/website_navigation')) {
          return _jsonResponse(
            request,
            _navigation(tenantId, label: 'Inicio ${_suffix(tenantId)}'),
          );
        }
        throw StateError(
          'Unexpected Supabase request: ${request.method} ${request.url}',
        );
      },
      preloadedStoreDataLoader: (_) async => null,
    );
    addTearDown(harness.dispose);

    await harness.service.loadPublicStoreDataUnified(
      _tenantB,
      forceRefresh: true,
    );

    expect(harness.service.getSetting('store_name'), 'Tienda B fallback');
    expect(harness.service.blocks.single['id'], 'fallback-block-b');
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('website_public_v2_settings_$_tenantB'),
      isNot(contains('Tienda A directa')),
    );
  });

  test('late banners response cannot resurrect a previous auth tenant',
      () async {
    final tenantContext = _MutableTenantContext();
    final delayed = _DelayedResourceResponses('website_banners');
    final harness = _service(
      delayed.handle,
      tenantService: tenantContext.service,
    );
    addTearDown(harness.dispose);

    // ignore: deprecated_member_use_from_same_package
    final staleLoad = harness.service.loadBanners();
    await delayed.requested(_tenantA);
    tenantContext.switchToTenantB();
    // ignore: deprecated_member_use_from_same_package
    final currentLoad = harness.service.loadBanners();
    await delayed.requested(_tenantB);

    delayed.complete(_tenantB, [_banner(_tenantB, title: 'Banner B')]);
    await currentLoad;
    delayed.complete(_tenantA, [_banner(_tenantA, title: 'Banner A tardío')]);
    await staleLoad;

    expect(harness.service.banners.single.tenantId, _tenantB);
    expect(harness.service.banners.single.title, 'Banner B');
  });

  test('late featured-product response cannot resurrect a previous auth tenant',
      () async {
    final tenantContext = _MutableTenantContext();
    final delayed = _DelayedResourceResponses('featured_products');
    final harness = _service(
      delayed.handle,
      tenantService: tenantContext.service,
    );
    addTearDown(harness.dispose);

    final staleLoad = harness.service.loadFeaturedProducts();
    await delayed.requested(_tenantA);
    tenantContext.switchToTenantB();
    final currentLoad = harness.service.loadFeaturedProducts();
    await delayed.requested(_tenantB);

    delayed.complete(_tenantB, [_featuredProduct(_tenantB)]);
    await currentLoad;
    delayed.complete(_tenantA, [_featuredProduct(_tenantA)]);
    await staleLoad;

    expect(harness.service.featuredProducts.single.tenantId, _tenantB);
  });

  test('late content response cannot resurrect a previous auth tenant',
      () async {
    final tenantContext = _MutableTenantContext();
    final delayed = _DelayedResourceResponses('website_content');
    final harness = _service(
      delayed.handle,
      tenantService: tenantContext.service,
    );
    addTearDown(harness.dispose);

    final staleLoad = harness.service.loadContents();
    await delayed.requested(_tenantA);
    tenantContext.switchToTenantB();
    final currentLoad = harness.service.loadContents();
    await delayed.requested(_tenantB);

    delayed.complete(_tenantB, [_content(_tenantB, title: 'Contenido B')]);
    await currentLoad;
    delayed.complete(
      _tenantA,
      [_content(_tenantA, title: 'Contenido A tardío')],
    );
    await staleLoad;

    expect(harness.service.contents.single.tenantId, _tenantB);
    expect(harness.service.contents.single.title, 'Contenido B');
  });

  test('late online-order response cannot resurrect a previous auth tenant',
      () async {
    final tenantContext = _MutableTenantContext();
    final delayed = _DelayedResourceResponses('online_orders');
    final harness = _service(
      (request) {
        if (request.url.path
            .endsWith('/online_order_payment_processing_status_view')) {
          return Future.value(_jsonResponse(request, const []));
        }
        return delayed.handle(request);
      },
      tenantService: tenantContext.service,
    );
    addTearDown(harness.dispose);

    final staleLoad = harness.service.loadOrders();
    await delayed.requested(_tenantA);
    tenantContext.switchToTenantB();
    final currentLoad = harness.service.loadOrders();
    await delayed.requested(_tenantB);

    delayed.complete(_tenantB, [_order(_tenantB)]);
    await currentLoad;
    delayed.complete(_tenantA, [_order(_tenantA)]);
    await staleLoad;

    expect(harness.service.orders.single.tenantId, _tenantB);
    expect(harness.service.orders.single.orderNumber, 'WEB-B');
  });
}

class _ServiceHarness {
  _ServiceHarness({
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
  Future<http.Response> Function(http.Request request) handler, {
  TenantService? tenantService,
  WebsitePreloadedStoreDataLoader? preloadedStoreDataLoader,
  Future<http.Response> Function(http.Request request)? edgeHandler,
}) {
  final supabase = SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient(handler),
  );
  final service = WebsiteService(
    supabase: supabase,
    tenantService: tenantService ??
        TenantService.testing(
          currentUserId: () => null,
          profileLookup: (_) async => const [],
        ),
    preloadedStoreDataLoader: preloadedStoreDataLoader,
    httpClient: MockClient(
      edgeHandler ??
          (request) async => throw StateError(
                'The edge client is not expected in force-refresh tests.',
              ),
    ),
  );
  return _ServiceHarness(service: service, supabase: supabase);
}

class _MutableTenantContext {
  _MutableTenantContext() {
    service = TenantService.testing(
      currentUserId: () => _currentUserId,
      profileLookup: (userId) async => [
        {
          'tenant_id': userId == 'user-a' ? _tenantA : _tenantB,
          'role': 'admin',
          'permissions': <String, dynamic>{},
        },
      ],
    );
  }

  String _currentUserId = 'user-a';
  late final TenantService service;

  void switchToTenantB() {
    _currentUserId = 'user-b';
  }
}

class _DelayedTenantResponses {
  final Map<String, Completer<http.Response>> _responses = {
    _tenantA: Completer<http.Response>(),
    _tenantB: Completer<http.Response>(),
  };
  final Map<String, Completer<void>> _requested = {
    _tenantA: Completer<void>(),
    _tenantB: Completer<void>(),
  };
  final Map<String, http.Request> _requests = {};

  Future<http.Response> handle(http.Request request) {
    final tenantId = _tenantFromRequest(request);
    _requests[tenantId] = request;
    if (!_requested[tenantId]!.isCompleted) {
      _requested[tenantId]!.complete();
    }
    return _responses[tenantId]!.future;
  }

  Future<void> requested(String tenantId) => _requested[tenantId]!.future;

  void complete(String tenantId, Object body) {
    _responses[tenantId]!.complete(
      _jsonResponse(_requests[tenantId]!, body),
    );
  }
}

class _DelayedResourceResponses {
  _DelayedResourceResponses(this.resource);

  final String resource;
  final Map<String, Completer<http.Response>> _responses = {
    _tenantA: Completer<http.Response>(),
    _tenantB: Completer<http.Response>(),
  };
  final Map<String, Completer<void>> _requested = {
    _tenantA: Completer<void>(),
    _tenantB: Completer<void>(),
  };
  final Map<String, http.Request> _requests = {};

  Future<http.Response> handle(http.Request request) {
    if (!request.url.path.endsWith('/$resource')) {
      throw StateError(
        'Expected $resource, got ${request.method} ${request.url}',
      );
    }
    final tenantId = _tenantFromRequest(request);
    _requests[tenantId] = request;
    if (!_requested[tenantId]!.isCompleted) {
      _requested[tenantId]!.complete();
    }
    return _responses[tenantId]!.future;
  }

  Future<void> requested(String tenantId) => _requested[tenantId]!.future;

  void complete(String tenantId, Object body) {
    _responses[tenantId]!.complete(
      _jsonResponse(_requests[tenantId]!, body),
    );
  }
}

String _tenantFromRequest(http.Request request) {
  final filter = request.url.queryParameters['tenant_id'] ?? '';
  return filter.startsWith('eq.') ? filter.substring(3) : filter;
}

Future<void> _installAuthenticatedSession(
  SupabaseClient client, {
  required String userId,
}) async {
  final header = base64Url
      .encode(utf8.encode(jsonEncode({'alg': 'none', 'typ': 'JWT'})))
      .replaceAll('=', '');
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'exp': 4102444800,
            'sub': userId,
            'role': 'authenticated',
          }),
        ),
      )
      .replaceAll('=', '');
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': '$header.$payload.signature',
      'expires_in': 3600,
      'refresh_token': 'test-refresh-token',
      'token_type': 'bearer',
      'user': {
        'id': userId,
        'app_metadata': const <String, dynamic>{},
        'user_metadata': const <String, dynamic>{},
        'aud': 'authenticated',
        'created_at': '2026-07-28T00:00:00.000Z',
      },
    }),
  );
}

String _suffix(String tenantId) => tenantId == _tenantA ? 'A' : 'B';

Map<String, dynamic> _block(String id) {
  return {
    'id': id,
    'block_type': 'divider',
    'block_data': <String, dynamic>{},
    'order_index': 0,
  };
}

Map<String, dynamic> _banner(
  String tenantId, {
  required String title,
}) {
  return {
    'id': 'banner-${_suffix(tenantId).toLowerCase()}',
    'tenant_id': tenantId,
    'title': title,
    'active': true,
    'order_index': 0,
    'created_at': '2026-07-28T12:00:00.000Z',
    'updated_at': '2026-07-28T12:00:00.000Z',
  };
}

Map<String, dynamic> _featuredProduct(String tenantId) {
  return {
    'id': 'featured-${_suffix(tenantId).toLowerCase()}',
    'tenant_id': tenantId,
    'product_id': 'product-${_suffix(tenantId).toLowerCase()}',
    'active': true,
    'order_index': 0,
    'created_at': '2026-07-28T12:00:00.000Z',
  };
}

Map<String, dynamic> _content(
  String tenantId, {
  required String title,
}) {
  return {
    'id': 'content-${_suffix(tenantId).toLowerCase()}',
    'tenant_id': tenantId,
    'title': title,
    'content': title,
    'updated_at': '2026-07-28T12:00:00.000Z',
  };
}

Map<String, dynamic> _order(String tenantId) {
  return {
    'id': 'order-${_suffix(tenantId).toLowerCase()}',
    'tenant_id': tenantId,
    'order_number': 'WEB-${_suffix(tenantId)}',
    'customer_email': 'customer@example.invalid',
    'customer_name': 'Cliente ${_suffix(tenantId)}',
    'subtotal': 1000,
    'tax_amount': 190,
    'shipping_cost': 0,
    'discount_amount': 0,
    'total': 1190,
    'status': 'confirmed',
    'payment_status': 'pending',
    'created_at': '2026-07-28T12:00:00.000Z',
    'updated_at': '2026-07-28T12:00:00.000Z',
    'online_order_items': <Map<String, dynamic>>[],
  };
}

Map<String, dynamic> _page(
  String tenantId, {
  required String title,
}) {
  return {
    'id': 'page-${_suffix(tenantId).toLowerCase()}',
    'tenant_id': tenantId,
    'slug': 'inicio',
    'title': title,
    'is_published': true,
    'is_home': true,
    'is_system': true,
    'template': 'default',
    'created_at': '2026-07-28T12:00:00.000Z',
    'updated_at': '2026-07-28T12:00:00.000Z',
  };
}

List<Map<String, dynamic>> _navigation(
  String tenantId, {
  required String label,
}) {
  final suffix = _suffix(tenantId).toLowerCase();
  return [
    {
      'id': 'header-$suffix',
      'tenant_id': tenantId,
      'menu_location': 'header',
      'label': label,
      'link_type': 'action',
      'link_value': 'open_search',
      'parent_id': null,
      'order_index': 0,
      'is_visible': true,
      'show_on_desktop': true,
      'show_on_mobile': true,
      'created_at': '2026-07-28T12:00:00.000Z',
      'updated_at': '2026-07-28T12:00:00.000Z',
    },
    {
      'id': 'footer-$suffix',
      'tenant_id': tenantId,
      'menu_location': 'footer',
      'label': 'Footer $suffix',
      'link_type': 'action',
      'link_value': '',
      'parent_id': null,
      'order_index': 0,
      'is_visible': true,
      'show_on_desktop': true,
      'show_on_mobile': true,
      'created_at': '2026-07-28T12:00:00.000Z',
      'updated_at': '2026-07-28T12:00:00.000Z',
    },
  ];
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
