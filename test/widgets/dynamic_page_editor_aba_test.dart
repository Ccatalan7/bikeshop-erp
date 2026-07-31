import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/website/models/website_editor_capability.dart';
import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/modules/website/widgets/deferred_editable_block_renderer.dart';
import 'package:vinabike_erp/public_store/pages/dynamic_website_page.dart';
import 'package:vinabike_erp/public_store/providers/public_store_tenant_provider.dart';
import 'package:vinabike_erp/shared/models/tenant.dart';
import 'package:vinabike_erp/shared/services/tenant_detection_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

const _tenantId = 'tenant-aba';
const _pageId = 'page-oferta';

WebsiteEditorCapabilitySnapshot _cap({int epoch = 0}) =>
    WebsiteEditorCapabilitySnapshot(
      identity: 'user-a',
      activeTenantId: _tenantId,
      storefrontTenantId: _tenantId,
      hasAuthority: true,
      authorityEpoch: epoch,
    );

CachedPageSnapshot _snapshot({required bool published, String marker = 'v1'}) {
  return CachedPageSnapshot(
    page: WebsitePage(
      id: _pageId,
      tenantId: _tenantId,
      slug: 'oferta',
      title: 'Oferta',
      isPublished: published,
      createdAt: DateTime.utc(2026, 7, 30),
      updatedAt: DateTime.utc(2026, 7, 30),
    ),
    blocks: [
      {
        'id': 'blk-1',
        'tenant_id': _tenantId,
        'page_id': _pageId,
        'block_type': 'about',
        'block_data': {'title': 'Contenido $marker'},
        'order_index': 0,
        'is_visible': true,
      },
    ],
  );
}

class _AbaWebsiteService extends WebsiteService {
  _AbaWebsiteService()
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
            currentUserId: () => 'user-a',
            profileLookup: (_) async => const [],
          ),
          httpClient: MockClient(
            (request) async => throw StateError('no edge calls'),
          ),
        );

  final List<Completer<CachedPageSnapshot?>> editorLoads = [];

  @override
  bool hasSettingsForTenant(String tenantId) => true;

  @override
  CachedPageSnapshot? peekPageWithBlocks(
    String slug, {
    required String tenantId,
  }) =>
      null;

  @override
  Future<PageSnapshotLoadResult> loadPageWithBlocksResult(
    String slug, {
    required String tenantId,
  }) async =>
      PageSnapshotLoadResult.origin(_snapshot(published: true));

  @override
  Future<CachedPageSnapshot?> loadEditorPageWithBlocks(
    String slug, {
    required String tenantId,
  }) {
    final completer = Completer<CachedPageSnapshot?>();
    editorLoads.add(completer);
    return completer.future;
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets(
    'MOUNTED Dynamic ABA: a late completion for the SAME fingerprint at the '
    'OLD authorityEpoch is never adopted, never paints an error, never '
    'blocks the loader, and the epoch-1 session stays intact',
    (tester) async {
      await tester.runAsync(DeferredEditableBlockRenderer.preload);
      await tester.binding.setSurfaceSize(const Size(1400, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final editMode = WebsiteEditModeProvider();
      addTearDown(editMode.dispose);
      editMode.adoptEditorEntryLease(0, _cap());
      editMode.applyRouteModeCommand(WebsiteEditorMode.edit);

      final service = _AbaWebsiteService();
      addTearDown(service.dispose);
      final tenant = PublicStoreTenantProvider(TenantDetectionService())
        ..setTenant(
          Tenant(
            id: _tenantId,
            shopName: 'ABA test',
            subdomain: 'aba',
            createdAt: DateTime.utc(2026, 7, 30),
            updatedAt: DateTime.utc(2026, 7, 30),
          ),
        );

      final router = GoRouter(
        initialLocation: '/pagina/oferta',
        routes: [
          GoRoute(
            path: '/pagina/oferta',
            builder: (context, state) => MultiProvider(
              providers: [
                ChangeNotifierProvider<WebsiteService>.value(value: service),
                ChangeNotifierProvider.value(value: editMode),
                ChangeNotifierProvider.value(value: tenant),
              ],
              child: const Scaffold(
                body: DynamicWebsitePage(slug: 'oferta'),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();
      expect(service.editorLoads, hasLength(1),
          reason: 'The epoch-0 session requested its editor read.');

      // Coalesced A -> B -> A churn: the fingerprint reproduces at epoch 1.
      // The provider takeover clears the epoch-0 session and the layout's
      // single CMS transition (modeled here) triggers the fresh reload.
      editMode.adoptEditorEntryLease(
        editMode.editorEntryLeaseGeneration,
        _cap(epoch: 1),
      );
      editMode.applyRouteModeCommand(WebsiteEditorMode.edit);
      await tester.pump();
      service.requestActiveCmsPageOriginRevalidation();
      await tester.pump();
      await tester.pump();
      expect(service.editorLoads, hasLength(2),
          reason: 'The epoch-1 session issues its OWN read.');

      // LATE SUCCESS of the epoch-0 request: the captured lease context no
      // longer matches -> dropped silently.
      service.editorLoads.first.complete(_snapshot(published: false));
      await tester.pump();
      await tester.pump();
      expect(editMode.ownsPageDocument(pageId: _pageId), isFalse,
          reason: 'The stale epoch-0 snapshot never binds under epoch 1.');
      expect(find.textContaining('Error'), findsNothing,
          reason: 'A dropped stale completion paints nothing.');
      expect(editMode.editorEntryLease?.authorityEpoch, 1,
          reason: 'The epoch-1 session is untouched.');

      // A LATE typed-superseded REJECTION behaves identically.
      final third = Completer<CachedPageSnapshot?>();
      service.editorLoads.add(third); // placeholder ordering guard
      service.editorLoads[1].completeError(
        const WebsiteEditorReadSupersededException('obsoleta'),
      );
      await tester.pump();
      expect(find.textContaining('Error'), findsNothing);
      expect(editMode.editorEntryLease?.authorityEpoch, 1);

      // The loader is NOT blocked: the central signal triggers a fresh read
      // and ONLY that epoch-1 completion binds.
      service.requestActiveCmsPageOriginRevalidation();
      await tester.pump();
      await tester.pump();
      expect(service.editorLoads.length, greaterThanOrEqualTo(4),
          reason: 'A new read was issued after the superseded rejection.');
      service.editorLoads.last.complete(_snapshot(
        published: false,
        marker: 'epoch1',
      ));
      await tester.pump();
      await tester.pump();
      expect(
        editMode.ownsPageDocument(pageId: _pageId, pageSlug: 'oferta'),
        isTrue,
        reason: 'ONLY the epoch-1 RPC result binds the document.',
      );
      expect(
        editMode.blocks.single['block_data']['title'],
        'Contenido epoch1',
      );
      await tester.pump(const Duration(seconds: 5)); // Drain retry timers.
    },
  );
}
