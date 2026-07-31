import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/website/models/website_editor_capability.dart';
import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/modules/website/services/website_save_coordinator.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

const _editorRpcTenantId = '7e290100-0000-4000-8000-000000000001';

class _MutableUser {
  String? id;
}

/// Grants tenant admin for whichever user is active, with the real
/// auth-notification path (epoch source) available to tests.
class _SwitchableTenantService extends TenantService {
  _SwitchableTenantService(this._user)
      : super.testing(
          currentUserId: () => _user.id,
          profileLookup: (_) async => const [
            {
              'tenant_id': _editorRpcTenantId,
              'role': 'admin',
              'permissions': null,
            },
          ],
        );

  final _MutableUser _user;

  void emitAuthChange() {
    clearCache();
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'replacePageBlocks uses one canonical RPC and returns normalized ordered rows',
    () async {
      const tenantId = '7e290100-0000-4000-8000-000000000001';
      const pageId = '7e290100-0000-4000-8000-000000000010';
      const firstBlockId = '7e290100-0000-4000-8000-000000000030';
      const secondBlockId = '7e290100-0000-4000-8000-000000000031';
      final requests = <http.Request>[];

      final supabase = SupabaseClient(
        'https://example.supabase.co',
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request);

          expect(request.method, 'POST');
          expect(
            request.url.path,
            '/rest/v1/rpc/replace_page_blocks',
          );

          final params =
              Map<String, dynamic>.from(jsonDecode(request.body) as Map);
          expect(
            params.keys,
            unorderedEquals([
              'p_tenant_id',
              'p_page_id',
              'p_blocks',
            ]),
          );
          expect(params['p_tenant_id'], tenantId);
          expect(params['p_page_id'], pageId);

          final canonicalBlocks = (params['p_blocks'] as List)
              .map((block) => Map<String, dynamic>.from(block as Map))
              .toList(growable: false);
          expect(canonicalBlocks, hasLength(2));
          expect(
            canonicalBlocks.first.keys,
            unorderedEquals([
              'id',
              'block_type',
              'block_data',
              'is_visible',
            ]),
          );
          expect(canonicalBlocks.first['id'], firstBlockId);
          expect(canonicalBlocks.first['block_type'], 'text');
          expect(canonicalBlocks.first['is_visible'], isFalse);
          expect(canonicalBlocks.first, isNot(contains('order_index')));
          expect(
            canonicalBlocks.first['block_data'],
            containsPair('text', 'Texto enviado'),
          );
          expect(
            canonicalBlocks.first['block_data'],
            containsPair('preset', 'paragraph'),
          );
          expect(
            canonicalBlocks.first['block_data'],
            containsPair('schemaVersion', 1),
          );

          expect(
            canonicalBlocks.last.keys,
            unorderedEquals([
              'block_type',
              'block_data',
              'is_visible',
            ]),
          );
          expect(canonicalBlocks.last['block_type'], 'about');
          expect(canonicalBlocks.last['is_visible'], isTrue);
          expect(
            canonicalBlocks.last['block_data'],
            containsPair('description', 'Descripción heredada'),
          );
          expect(
            canonicalBlocks.last['block_data'],
            containsPair('content', 'Descripción heredada'),
          );

          // Deliberately return the database rows out of order. The client
          // projection must be deterministic even when an HTTP fixture or
          // compatible backend does not preserve the JSON aggregate ordering.
          return http.Response(
            jsonEncode([
              {
                'id': secondBlockId,
                'tenant_id': tenantId,
                'page_id': pageId,
                'block_type': 'about',
                'block_data': {
                  'content': '',
                  'description': 'Respuesta heredada',
                },
                'is_visible': true,
                'order_index': 1,
              },
              {
                'id': firstBlockId,
                'tenant_id': tenantId,
                'page_id': pageId,
                'block_type': 'text',
                'block_data': {
                  'text': 'Respuesta normalizada',
                },
                'is_visible': false,
                'order_index': 0,
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      final service = WebsiteService(
        supabase: supabase,
        tenantService: TenantService.testing(
          currentUserId: () => null,
          profileLookup: (_) async => const [],
        ),
        httpClient: MockClient(
          (request) async => throw StateError(
            'replacePageBlocks must not use the WebsiteService edge client.',
          ),
        ),
      );
      addTearDown(() {
        service.dispose();
        supabase.dispose();
      });

      final result = await service.replacePageBlocks(
        tenantId: tenantId,
        pageId: pageId,
        blocks: const [
          {
            'id': firstBlockId,
            'type': ' text ',
            'data': {
              'text': 'Texto enviado',
            },
            'isVisible': false,
            'order_index': 99,
          },
          {
            'id': ' ',
            'block_type': 'about',
            'block_data': {
              'content': '',
              'description': 'Descripción heredada',
            },
          },
        ],
      );

      expect(requests, hasLength(1));
      expect(
        requests.where(
          (request) => request.url.path.contains('/website_blocks'),
        ),
        isEmpty,
        reason: 'The atomic RPC must replace DELETE + INSERT client calls.',
      );
      expect(
        result.map((block) => block['order_index']),
        [0, 1],
      );
      expect(
        result.map((block) => block['id']),
        [firstBlockId, secondBlockId],
      );
      expect(
        result.first['block_data'],
        containsPair('text', 'Respuesta normalizada'),
      );
      expect(
        result.first['block_data'],
        containsPair('schemaVersion', 1),
      );
      expect(
        result.last['block_data'],
        containsPair('content', 'Respuesta heredada'),
      );
    },
  );

  test(
    'replacePageBlocks strips transient Canvas selection from p_blocks and '
    'sanitizes a legacy RPC response',
    () async {
      const tenantId = '7e290100-0000-4000-8000-000000000001';
      const pageId = '7e290100-0000-4000-8000-000000000010';
      const canvasBlockId = '7e290100-0000-4000-8000-000000000040';
      const carouselBlockId = '7e290100-0000-4000-8000-000000000041';
      final requests = <http.Request>[];

      final supabase = SupabaseClient(
        'https://example.supabase.co',
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request);
          expect(request.url.path, '/rest/v1/rpc/replace_page_blocks');

          final params =
              Map<String, dynamic>.from(jsonDecode(request.body) as Map);
          final payloadBlocks = (params['p_blocks'] as List)
              .map((block) => Map<String, dynamic>.from(block as Map))
              .toList(growable: false);
          expect(payloadBlocks, hasLength(2));

          final canvasData = Map<String, dynamic>.from(
            payloadBlocks.first['block_data'] as Map,
          );
          expect(
            canvasData,
            isNot(contains('activeElementId')),
            reason: 'Canvas root selection is editor-only transient state and '
                'must never reach p_blocks.',
          );
          final canvasElements = (canvasData['elements'] as List)
              .map((element) => Map<String, dynamic>.from(element as Map))
              .toList(growable: false);
          expect(
            canvasElements.single,
            containsPair('activeElementId', 'legit-element-field'),
            reason: 'A homonymous key inside a nested element is authored '
                'content and must be preserved.',
          );

          final carouselData = Map<String, dynamic>.from(
            payloadBlocks.last['block_data'] as Map,
          );
          expect(
            carouselData,
            containsPair('activeElementId', 'legit-root-field'),
            reason: 'Carousel root has no transient selection semantics; the '
                'sanitizer is type-aware, not a recursive key scrub.',
          );
          final payloadSlides = (carouselData['slides'] as List)
              .map((slide) => Map<String, dynamic>.from(slide as Map))
              .toList(growable: false);
          expect(payloadSlides.single, containsPair('title', 'Slide uno'));
          expect(
            payloadSlides.single,
            isNot(contains('activeElementId')),
            reason: 'Carousel slide selection is editor-only transient state '
                'and must never reach p_blocks.',
          );

          // A legacy backend/fixture may still return persisted selection.
          // The client boundary must sanitize the response too.
          return http.Response(
            jsonEncode([
              {
                'id': canvasBlockId,
                'tenant_id': tenantId,
                'page_id': pageId,
                'block_type': 'canvas',
                'block_data': {
                  'elements': [
                    {
                      'id': 'element-1',
                      'type': 'text',
                      'activeElementId': 'legit-element-field',
                    },
                  ],
                  'activeElementId': 'element-1',
                },
                'is_visible': true,
                'order_index': 0,
              },
              {
                'id': carouselBlockId,
                'tenant_id': tenantId,
                'page_id': pageId,
                'block_type': 'carousel',
                'block_data': {
                  'activeElementId': 'legit-root-field',
                  'slides': [
                    {
                      'title': 'Slide uno',
                      'activeElementId': 'element-9',
                    },
                  ],
                },
                'is_visible': true,
                'order_index': 1,
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      final service = WebsiteService(
        supabase: supabase,
        tenantService: TenantService.testing(
          currentUserId: () => null,
          profileLookup: (_) async => const [],
        ),
        httpClient: MockClient(
          (request) async => throw StateError(
            'replacePageBlocks must not use the WebsiteService edge client.',
          ),
        ),
      );
      addTearDown(() {
        service.dispose();
        supabase.dispose();
      });

      final result = await service.replacePageBlocks(
        tenantId: tenantId,
        pageId: pageId,
        blocks: const [
          {
            'id': canvasBlockId,
            'type': 'canvas',
            'data': {
              'elements': [
                {
                  'id': 'element-1',
                  'type': 'text',
                  'activeElementId': 'legit-element-field',
                },
              ],
              'activeElementId': 'element-1',
            },
          },
          {
            'id': carouselBlockId,
            'type': 'carousel',
            'data': {
              'activeElementId': 'legit-root-field',
              'slides': [
                {
                  'title': 'Slide uno',
                  'activeElementId': 'element-9',
                },
              ],
            },
          },
        ],
      );

      expect(requests, hasLength(1));

      final canvasRow = result.first;
      final canvasRowData =
          Map<String, dynamic>.from(canvasRow['block_data'] as Map);
      expect(canvasRowData, isNot(contains('activeElementId')));
      final canvasRowElements = (canvasRowData['elements'] as List)
          .map((element) => Map<String, dynamic>.from(element as Map))
          .toList(growable: false);
      expect(
        canvasRowElements.single,
        containsPair('activeElementId', 'legit-element-field'),
      );

      final carouselRow = result.last;
      final carouselRowData =
          Map<String, dynamic>.from(carouselRow['block_data'] as Map);
      expect(
        carouselRowData,
        containsPair('activeElementId', 'legit-root-field'),
      );
      final carouselRowSlides = (carouselRowData['slides'] as List)
          .map((slide) => Map<String, dynamic>.from(slide as Map))
          .toList(growable: false);
      expect(carouselRowSlides.single, containsPair('title', 'Slide uno'));
      expect(
        carouselRowSlides.single,
        isNot(contains('activeElementId')),
      );
    },
  );

  group('loadEditorPageWithBlocks (authority-bound editor RPC client)', () {
    const tenantId = '7e290100-0000-4000-8000-000000000001';
    const pageId = '7e290100-0000-4000-8000-000000000010';

    WebsiteService serviceWith(MockClient client) => WebsiteService(
          supabase: SupabaseClient(
            'https://example.supabase.co',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
            httpClient: client,
          ),
          tenantService: TenantService.testing(
            currentUserId: () => 'editor-user',
            profileLookup: (_) async => const [
              {'tenant_id': tenantId, 'role': 'admin', 'permissions': null},
            ],
          ),
          httpClient: MockClient(
            (request) async => throw StateError('no edge calls'),
          ),
        );

    Map<String, dynamic> pageRow(List<Map<String, dynamic>> blocks) => {
          'id': pageId,
          'tenant_id': tenantId,
          'slug': 'terminos',
          'title': 'Términos privados',
          'meta_description': null,
          'is_published': false,
          'is_home': false,
          'created_at': '2026-07-30T00:00:00Z',
          'updated_at': '2026-07-30T00:00:00Z',
          'website_blocks': blocks,
        };

    test(
        'the editor read uses ONLY the RPC (zero private REST) and orders '
        'blocks deterministically by (order_index, id)', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        expect(request.method, 'POST');
        expect(request.url.path, '/rest/v1/rpc/load_editor_page_with_blocks');
        final params =
            Map<String, dynamic>.from(jsonDecode(request.body) as Map);
        expect(params.keys, unorderedEquals(['p_tenant_id', 'p_slug']));
        expect(params['p_tenant_id'], tenantId);
        expect(params['p_slug'], 'terminos');
        // Out-of-order rows with an order_index TIE: the client projection
        // must break the tie by id.
        return http.Response(
          jsonEncode(pageRow([
            {
              'id': 'bbb',
              'tenant_id': tenantId,
              'page_id': pageId,
              'block_type': 'text',
              'block_data': {'text': 'Segundo'},
              'is_visible': false,
              'order_index': 1,
            },
            {
              'id': 'aaa',
              'tenant_id': tenantId,
              'page_id': pageId,
              'block_type': 'text',
              'block_data': {'text': 'Primero'},
              'is_visible': true,
              'order_index': 1,
            },
            {
              'id': 'zzz',
              'tenant_id': tenantId,
              'page_id': pageId,
              'block_type': 'text',
              'block_data': {'text': 'Cero'},
              'is_visible': true,
              'order_index': 0,
            },
          ])),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      });
      final service = serviceWith(client);

      final snapshot = await service.loadEditorPageWithBlocks(
        'terminos',
        tenantId: tenantId,
      );
      expect(snapshot, isNotNull);
      expect(snapshot!.page.isPublished, isFalse,
          reason: 'Private drafts arrive only through the RPC.');
      expect(
        snapshot.blocks.map((block) => block['id']).toList(),
        ['zzz', 'aaa', 'bbb'],
      );
      expect(requests, hasLength(1));
      expect(
        requests.where(
          (request) => request.url.path.startsWith('/rest/v1/website_'),
        ),
        isEmpty,
        reason: 'ZERO direct REST reads on private tables.',
      );
    });

    test(
        'a non-Map RPC payload, an empty page id and a malformed page row '
        'are typed CONTRACT violations (fail closed)', () async {
      Future<void> expectContract(Object body) async {
        final client = MockClient(
          (request) async => http.Response(
            body is String ? body : jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          ),
        );
        final service = serviceWith(client);
        addTearDown(service.dispose);
        await expectLater(
          service.loadEditorPageWithBlocks('terminos', tenantId: tenantId),
          throwsA(isA<WebsiteCmsReadContractException>()),
        );
      }

      await expectContract(const <int>[1, 2]); // List payload.
      await expectContract({
        ...pageRow(const []),
        'id': '', // Empty page id.
      });
      await expectContract({
        ...pageRow(const []),
        'created_at': 'no-es-fecha', // Malformed row -> typed, with cause.
      });
    });

    test('a null RPC result is a valid missing page', () async {
      final client = MockClient(
        (request) async => http.Response('null', 200,
            headers: {'content-type': 'application/json'},
            request: request),
      );
      final service = serviceWith(client);
      expect(
        await service.loadEditorPageWithBlocks('nada', tenantId: tenantId),
        isNull,
      );
    });

    test(
        'a 42501 rejection is typed authority loss and latches the durable '
        'denial', () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'message': 'website_editor_page_read_forbidden',
            'code': '42501',
          }),
          403,
          headers: {'content-type': 'application/json'},
          request: request,
        ),
      );
      final service = serviceWith(client);
      expect(await service.canOpenEditorForTenant(tenantId), isTrue);

      await expectLater(
        service.loadEditorPageWithBlocks('terminos', tenantId: tenantId),
        throwsA(isA<WebsiteEditorAuthorityException>()),
      );
      expect(await service.canOpenEditorForTenant(tenantId), isFalse,
          reason: 'The server-evidenced denial holds until new identity '
              'evidence — no revoke -> re-grant loop.');
    });

    test(
        'a transient server failure stays UNCLASSIFIED: no authority loss, '
        'no denial latch, capability preserved', () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({'message': 'boom', 'code': '500'}),
          500,
          headers: {'content-type': 'application/json'},
          request: request,
        ),
      );
      final service = serviceWith(client);

      await expectLater(
        service.loadEditorPageWithBlocks('terminos', tenantId: tenantId),
        throwsA(
          allOf(
            isA<PostgrestException>(),
            isNot(isA<WebsiteEditorAuthorityException>()),
          ),
        ),
      );
      expect(await service.canOpenEditorForTenant(tenantId), isTrue,
          reason: 'A transient failure never converts into a denial; the '
              'consumer keeps its session and drafts.');
    });

    WebsiteService switchableService(
      _SwitchableTenantService tenant,
      Completer<http.Response> gate,
      Completer<void> requestStarted,
    ) =>
        WebsiteService(
          supabase: SupabaseClient(
            'https://example.supabase.co',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
            httpClient: MockClient(
              (request) {
                // Signals that the identity context was already captured and
                // the RPC is in flight — the test switches identity ONLY
                // inside that window.
                if (!requestStarted.isCompleted) requestStarted.complete();
                return gate.future.then(
                  (raw) => http.Response(
                    raw.body,
                    raw.statusCode,
                    headers: raw.headers,
                    request: request,
                  ),
                );
              },
            ),
          ),
          tenantService: tenant,
          httpClient: MockClient(
            (request) async => throw StateError('no edge calls'),
          ),
        );

    test(
        'a LATE 42501 completing after an identity switch is SUPERSEDED: '
        'typed discard, no denial latch for the new identity', () async {
      final user = _MutableUser()..id = 'user-a';
      final tenant = _SwitchableTenantService(user);
      final gate = Completer<http.Response>();
      final requestStarted = Completer<void>();
      final service = switchableService(tenant, gate, requestStarted);
      await tenant.getTenantId();

      final pending = service.loadEditorPageWithBlocks(
        'terminos',
        tenantId: tenantId,
      );
      await requestStarted.future; // Context captured; RPC in flight.
      user.id = 'user-b';
      tenant.emitAuthChange();
      gate.complete(http.Response(
        jsonEncode({'message': 'forbidden', 'code': '42501'}),
        403,
        headers: {'content-type': 'application/json'},
      ));

      await expectLater(
        pending,
        throwsA(isA<WebsiteEditorReadSupersededException>()),
      );
      await tenant.getTenantId(); // Warm B.
      expect(await service.canOpenEditorForTenant(tenantId), isTrue,
          reason: 'A\'s late rejection cannot latch a denial for B.');
    });

    test(
        'a LATE SUCCESS completing after an identity switch is equally '
        'SUPERSEDED: the data is never adopted', () async {
      final user = _MutableUser()..id = 'user-a';
      final tenant = _SwitchableTenantService(user);
      final gate = Completer<http.Response>();
      final requestStarted = Completer<void>();
      final service = switchableService(tenant, gate, requestStarted);
      await tenant.getTenantId();

      final pending = service.loadEditorPageWithBlocks(
        'terminos',
        tenantId: tenantId,
      );
      await requestStarted.future; // Context captured; RPC in flight.
      user.id = 'user-b';
      tenant.emitAuthChange();
      gate.complete(http.Response(
        jsonEncode(pageRow(const [])),
        200,
        headers: {'content-type': 'application/json'},
      ));

      await expectLater(
        pending,
        throwsA(isA<WebsiteEditorReadSupersededException>()),
      );
    });

    test(
        'reorderNavigationIdsForTenant re-validates before EACH internal '
        'update: a guard rejection stops every remaining write', () async {
      var updates = 0;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/website_navigation') &&
            request.method == 'PATCH') {
          updates++;
          return http.Response(
            jsonEncode({'id': 'nav-$updates'}),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        throw StateError(
          'unexpected request: ${request.method} ${request.url.path}',
        );
      });
      final service = WebsiteService(
        supabase: SupabaseClient(
          'https://example.supabase.co',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: client,
        ),
        tenantService: TenantService.testing(
          currentUserId: () => 'editor-user',
          profileLookup: (_) async => const [],
        ),
        httpClient: MockClient(
          (request) async => throw StateError('no edge calls'),
        ),
      );
      addTearDown(service.dispose);

      var guardCalls = 0;
      await expectLater(
        service.reorderNavigationIdsForTenant(
          _editorRpcTenantId,
          const ['nav-1', 'nav-2', 'nav-3'],
          writeGuard: () {
            guardCalls++;
            if (guardCalls == 2) {
              throw const WebsiteEditorAuthorityException(
                'La autoridad del editor cambió durante el guardado.',
              );
            }
          },
        ),
        throwsA(isA<WebsiteEditorAuthorityException>()),
      );
      expect(updates, 1,
          reason: 'Exactly one write happened before the rejection; the '
              'remaining N-1 updates were never issued.');
      expect(guardCalls, 2);
    });

    test(
        '_upsertSettings: a guard rejection AFTER the baseline read issues '
        'ZERO writes', () async {
      var gets = 0;
      var posts = 0;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/website_settings')) {
          if (request.method == 'GET') {
            gets++;
            return http.Response(jsonEncode([]), 200,
                headers: {'content-type': 'application/json'},
                request: request);
          }
          if (request.method == 'POST') {
            posts++;
            return http.Response(jsonEncode([]), 201,
                headers: {'content-type': 'application/json'},
                request: request);
          }
        }
        throw StateError(
          'unexpected request: ${request.method} ${request.url.path}',
        );
      });
      final service = WebsiteService(
        supabase: SupabaseClient(
          'https://example.supabase.co',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: client,
        ),
        tenantService: TenantService.testing(
          currentUserId: () => 'editor-user',
          profileLookup: (_) async => const [],
        ),
        httpClient: MockClient(
          (request) async => throw StateError('no edge calls'),
        ),
      );
      addTearDown(service.dispose);

      await expectLater(
        service.saveSettingsForTenant(
          _editorRpcTenantId,
          {'store_name': 'Cambio tardío'},
          writeGuard: () => throw const WebsiteEditorWriteSupersededException(
            'La autoridad del editor cambió durante el guardado.',
          ),
        ),
        throwsA(isA<WebsiteEditorWriteSupersededException>()),
      );
      expect(gets, 1, reason: 'The baseline read ran.');
      expect(posts, 0,
          reason: 'The mutation was blocked AFTER the read, BEFORE any '
              'write.');
    });

    test(
        'savePageSeo: an identity switch during the page READ blocks the '
        'following page write', () async {
      final service = _SeoGuardProbeService();
      addTearDown(service.dispose);
      final gateway = WebsiteServiceSaveGateway(service);
      var superseded = false;
      gateway.writeGuard = () {
        if (service.identitySwitched) {
          superseded = true;
          throw const WebsiteEditorWriteSupersededException(
            'La autoridad del editor cambió durante el guardado.',
          );
        }
      };

      await expectLater(
        gateway.savePageSeo(
          tenantId: _editorRpcTenantId,
          routeKey: 'inicio',
          values: const {
            'meta_title': 'Título',
            'meta_description': 'Descripción',
          },
        ),
        throwsA(isA<WebsiteEditorWriteSupersededException>()),
      );
      expect(superseded, isTrue);
      expect(service.settingsWrites, 1,
          reason: 'The pre-read settings write completed under the old '
              'identity window.');
      expect(service.pageUpdates, 0,
          reason: 'The write AFTER the read was blocked.');
    });

    test(
        'POST-AWAIT isolation: an identity switch while ANY mutable request '
        'is in flight leaves the local projection and listeners of the new '
        'session untouched (typed superseded outcome)', () async {
      const tenantId = _editorRpcTenantId;
      Map<String, String> jsonHeaders() =>
          {'content-type': 'application/json'};
      Map<String, dynamic> navRow() => {
            'id': '7e290100-0000-4000-8000-0000000000aa',
            'tenant_id': tenantId,
            'menu_location': 'footer',
            'label': 'Enlace',
            'link_type': 'external',
            'link_value': '/x',
            'order_index': 0,
            'created_at': '2026-07-30T00:00:00Z',
            'updated_at': '2026-07-30T00:00:00Z',
          };
      Map<String, dynamic> pageRowFull() => {
            'id': '7e290100-0000-4000-8000-0000000000bb',
            'tenant_id': tenantId,
            'slug': 'seo-page',
            'title': 'SEO',
            'is_published': true,
            'created_at': '2026-07-30T00:00:00Z',
            'updated_at': '2026-07-30T00:00:00Z',
          };

      var armed = false;
      var mutableRequests = 0;
      final client = MockClient((request) async {
        final path = request.url.path;
        if (request.method == 'GET' && path.endsWith('/website_settings')) {
          return http.Response(
            jsonEncode([
              {'tenant_id': tenantId, 'key': 'store_name', 'value': 'Original'}
            ]),
            200,
            headers: jsonHeaders(),
            request: request,
          );
        }
        // EVERY mutable request arms the switch (it lands mid-flight) and
        // still succeeds server-side: the write may be durable, but the new
        // session's local projection must stay untouched.
        mutableRequests++;
        armed = true;
        if (path.endsWith('/rpc/delete_website_navigation')) {
          return http.Response('"deleted"', 200,
              headers: jsonHeaders(), request: request);
        }
        if (path.endsWith('/website_settings')) {
          return http.Response(jsonEncode([]), 201,
              headers: jsonHeaders(), request: request);
        }
        if (path.endsWith('/website_pages')) {
          // `.single()` expects an OBJECT body.
          return http.Response(jsonEncode(pageRowFull()), 200,
              headers: jsonHeaders(), request: request);
        }
        if (path.endsWith('/website_navigation')) {
          // reorder uses `.select('id').maybeSingle()`; update/upsert use
          // `.select().single()` — both expect OBJECT bodies.
          return http.Response(
            request.url.query.contains('select=id')
                ? jsonEncode({'id': navRow()['id']})
                : jsonEncode(navRow()),
            200,
            headers: jsonHeaders(),
            request: request,
          );
        }
        throw StateError('unexpected ${request.method} $path');
      });
      final service = WebsiteService(
        supabase: SupabaseClient(
          'https://example.supabase.co',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: client,
        ),
        tenantService: TenantService.testing(
          currentUserId: () => 'editor-user',
          profileLookup: (_) async => const [],
        ),
        httpClient: MockClient(
          (request) async => throw StateError('no edge calls'),
        ),
      );
      addTearDown(service.dispose);
      void guard() {
        if (armed) {
          throw const WebsiteEditorWriteSupersededException(
            'La autoridad del editor cambió durante el guardado.',
          );
        }
      }

      await service.loadSettingsForTenant(tenantId, rethrowErrors: true);
      expect(service.settings['store_name'], 'Original');
      var notifies = 0;
      service.addListener(() => notifies++);

      // 1) Settings: durable POST, zero local projection.
      await expectLater(
        service.saveSettingsForTenant(
          tenantId,
          {'store_name': 'Robada por A'},
          writeGuard: guard,
        ),
        throwsA(isA<WebsiteEditorWriteSupersededException>()),
      );
      expect(service.settings['store_name'], 'Original',
          reason: 'A\'s late response never mutates B\'s settings.');

      // 2) Page (SEO) update.
      armed = false;
      await expectLater(
        service.updatePage(
          WebsitePage(
            id: pageRowFull()['id'] as String,
            tenantId: tenantId,
            slug: 'seo-page',
            title: 'SEO',
            isPublished: true,
            createdAt: DateTime.utc(2026, 7, 30),
            updatedAt: DateTime.utc(2026, 7, 30),
          ),
          writeGuard: guard,
        ),
        throwsA(isA<WebsiteEditorWriteSupersededException>()),
      );

      // 3) Navigation update.
      armed = false;
      await expectLater(
        service.updateNavigationForTenant(
          WebsiteNavigation(
            id: navRow()['id'] as String,
            tenantId: tenantId,
            menuLocation: MenuLocation.footer,
            label: 'Enlace',
            linkType: NavLinkType.external,
            linkValue: '/x',
            createdAt: DateTime.utc(2026, 7, 30),
            updatedAt: DateTime.utc(2026, 7, 30),
          ),
          tenantId,
          writeGuard: guard,
        ),
        throwsA(isA<WebsiteEditorWriteSupersededException>()),
      );

      // 4) Navigation idempotent create.
      armed = false;
      await expectLater(
        service.upsertNavigationForTenant(
          tenantId: tenantId,
          persistedId: navRow()['id'] as String,
          navigation: WebsiteNavigation(
            id: navRow()['id'] as String,
            tenantId: tenantId,
            menuLocation: MenuLocation.footer,
            label: 'Enlace',
            linkType: NavLinkType.external,
            linkValue: '/x',
            createdAt: DateTime.utc(2026, 7, 30),
            updatedAt: DateTime.utc(2026, 7, 30),
          ),
          writeGuard: guard,
        ),
        throwsA(isA<WebsiteEditorWriteSupersededException>()),
      );

      // 5) Navigation delete (authority-bound RPC).
      armed = false;
      await expectLater(
        service.deleteNavigationForTenant(
          navRow()['id'] as String,
          tenantId,
          writeGuard: guard,
        ),
        throwsA(isA<WebsiteEditorWriteSupersededException>()),
      );

      // 6) Reorder: first response arms, no second update runs.
      armed = false;
      mutableRequests = 0;
      await expectLater(
        service.reorderNavigationIdsForTenant(
          tenantId,
          [navRow()['id'] as String, '7e290100-0000-4000-8000-0000000000ab'],
          writeGuard: guard,
        ),
        throwsA(isA<WebsiteEditorWriteSupersededException>()),
      );
      expect(mutableRequests, 1,
          reason: 'The switch after the first response stops the rest.');

      expect(notifies, 0,
          reason: 'ZERO local notifications for the new session across all '
              'six mutable operations.');
    });

    test(
        'ERROR MATRIX: a late FAILURE (5xx) after the identity switch also '
        'reclassifies as SUPERSEDED — no error publication, no notify',
        () async {
      const tenantId = _editorRpcTenantId;
      var armed = false;
      final client = MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path.endsWith('/website_settings')) {
          return http.Response(
            jsonEncode([
              {'tenant_id': tenantId, 'key': 'store_name', 'value': 'Original'}
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        armed = true; // The switch lands while the request is in flight...
        return http.Response(
          jsonEncode({'message': 'boom', 'code': '500'}),
          500, // ...and the request itself FAILS late.
          headers: {'content-type': 'application/json'},
          request: request,
        );
      });
      final service = WebsiteService(
        supabase: SupabaseClient(
          'https://example.supabase.co',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: client,
        ),
        tenantService: TenantService.testing(
          currentUserId: () => 'editor-user',
          profileLookup: (_) async => const [],
        ),
        httpClient: MockClient(
          (request) async => throw StateError('no edge calls'),
        ),
      );
      addTearDown(service.dispose);
      void guard() {
        if (armed) {
          throw const WebsiteEditorWriteSupersededException(
            'La autoridad del editor cambió durante el guardado.',
          );
        }
      }

      await service.loadSettingsForTenant(tenantId, rethrowErrors: true);
      var notifies = 0;
      service.addListener(() => notifies++);

      // Settings: late 500 -> superseded, error NEVER published.
      await expectLater(
        service.saveSettingsForTenant(
          tenantId,
          {'store_name': 'X'},
          writeGuard: guard,
        ),
        throwsA(isA<WebsiteEditorWriteSupersededException>()),
      );
      expect(service.error, isNull,
          reason: 'A superseded late failure never publishes an error.');

      // replacePageBlocks: late 500 -> superseded too.
      armed = false;
      await expectLater(
        service.replacePageBlocks(
          tenantId: tenantId,
          pageId: '7e290100-0000-4000-8000-0000000000bb',
          blocks: const [
            {
              'id': '7e290100-0000-4000-8000-0000000000cc',
              'block_type': 'text',
              'block_data': {'text': 'x'},
              'is_visible': true,
            },
          ],
          writeGuard: guard,
        ),
        throwsA(isA<WebsiteEditorWriteSupersededException>()),
      );

      // Reorder: a late NULL row after the switch is superseded, never the
      // new session's missing-row error.
      armed = false;
      await expectLater(
        service.deleteNavigationForTenant(
          '7e290100-0000-4000-8000-0000000000aa',
          tenantId,
          writeGuard: guard,
        ),
        throwsA(isA<WebsiteEditorWriteSupersededException>()),
      );

      expect(notifies, 0);
    });

    test(
        'replacePageBlocks late SUCCESS after the switch is SUPERSEDED: no '
        'cache clear side effects for the new session', () async {
      const tenantId = _editorRpcTenantId;
      var armed = false;
      final client = MockClient((request) async {
        armed = true;
        return http.Response(
          jsonEncode([
            {
              'id': '7e290100-0000-4000-8000-0000000000cc',
              'tenant_id': tenantId,
              'page_id': '7e290100-0000-4000-8000-0000000000bb',
              'block_type': 'text',
              'block_data': {'text': 'x'},
              'is_visible': true,
              'order_index': 0,
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      });
      final service = WebsiteService(
        supabase: SupabaseClient(
          'https://example.supabase.co',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: client,
        ),
        tenantService: TenantService.testing(
          currentUserId: () => 'editor-user',
          profileLookup: (_) async => const [],
        ),
        httpClient: MockClient(
          (request) async => throw StateError('no edge calls'),
        ),
      );
      addTearDown(service.dispose);
      var notifies = 0;
      service.addListener(() => notifies++);

      await expectLater(
        service.replacePageBlocks(
          tenantId: tenantId,
          pageId: '7e290100-0000-4000-8000-0000000000bb',
          blocks: const [
            {
              'id': '7e290100-0000-4000-8000-0000000000cc',
              'block_type': 'text',
              'block_data': {'text': 'x'},
              'is_visible': true,
            },
          ],
          writeGuard: () {
            if (armed) {
              throw const WebsiteEditorWriteSupersededException(
                'La autoridad del editor cambió durante el guardado.',
              );
            }
          },
        ),
        throwsA(isA<WebsiteEditorWriteSupersededException>()),
      );
      expect(notifies, 0);
      expect(service.error, isNull);
    });

    test(
        'PARSER regressions: malformed order_index, corrupt block_data and a '
        'non-map block are typed CONTRACT violations', () async {
      Future<void> expectContract(List<dynamic> blocks) async {
        final client = MockClient(
          (request) async => http.Response(
            jsonEncode({
              ...pageRow(const []),
              'website_blocks': blocks,
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          ),
        );
        final service = serviceWith(client);
        addTearDown(service.dispose);
        await expectLater(
          service.loadEditorPageWithBlocks('terminos', tenantId: tenantId),
          throwsA(isA<WebsiteCmsReadContractException>()),
        );
      }

      // order_index as a String breaks the deterministic sort contract
      // (two rows so the comparator actually runs).
      await expectContract([
        {
          'id': 'aaa',
          'tenant_id': tenantId,
          'page_id': pageId,
          'block_type': 'text',
          'block_data': {'text': 'x'},
          'is_visible': true,
          'order_index': 'no-numérico',
        },
        {
          'id': 'bbb',
          'tenant_id': tenantId,
          'page_id': pageId,
          'block_type': 'text',
          'block_data': {'text': 'y'},
          'is_visible': true,
          'order_index': 1,
        },
      ]);
      // Corrupt block_data (non-map) breaks normalization.
      await expectContract([
        {
          'id': 'aaa',
          'tenant_id': tenantId,
          'page_id': pageId,
          'block_type': 'text',
          'block_data': 'corrupto',
          'is_visible': true,
          'order_index': 0,
        },
      ]);
      // A non-map block row is rejected typed, never a cast error.
      await expectContract(['no-un-mapa']);
    });
  });
}

/// The identity "switches" INSIDE the page read window; the gateway's guard
/// must catch it before the following write.
class _SeoGuardProbeService extends WebsiteService {
  _SeoGuardProbeService()
      : super(
          supabase: SupabaseClient(
            'https://example.supabase.co',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
            httpClient: MockClient(
              (request) async => http.Response(jsonEncode([]), 200,
                  headers: {'content-type': 'application/json'}),
            ),
          ),
          tenantService: TenantService.testing(
            currentUserId: () => 'editor-user',
            profileLookup: (_) async => const [],
          ),
          httpClient: MockClient(
            (request) async => throw StateError('no edge calls'),
          ),
        );

  int settingsWrites = 0;
  int pageUpdates = 0;
  bool identitySwitched = false;

  @override
  Future<void> saveSettingsForTenant(
    String tenantId,
    Map<String, String> settings, {
    WebsiteEditorWriteGuard? writeGuard,
  }) async {
    writeGuard?.call();
    settingsWrites++;
  }

  @override
  Future<WebsitePage?> getPageBySlug(
    String slug, {
    String? tenantId,
    bool rethrowErrors = false,
  }) async {
    identitySwitched = true; // The switch lands inside the read window.
    return WebsitePage(
      id: 'page-seo',
      tenantId: _editorRpcTenantId,
      slug: slug,
      title: 'SEO',
      isPublished: true,
      createdAt: DateTime.utc(2026, 7, 30),
      updatedAt: DateTime.utc(2026, 7, 30),
    );
  }

  @override
  Future<WebsitePage> updatePage(
    WebsitePage page, {
    WebsiteEditorWriteGuard? writeGuard,
  }) async {
    writeGuard?.call();
    pageUpdates++;
    return page;
  }
}
