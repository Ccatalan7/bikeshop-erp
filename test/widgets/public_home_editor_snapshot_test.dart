import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/website/models/website_editor_capability.dart';
import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/public_store/pages/public_home_page.dart';
import 'package:vinabike_erp/public_store/providers/public_store_tenant_provider.dart';
import 'package:vinabike_erp/public_store/services/public_inventory_service.dart';
import 'package:vinabike_erp/public_store/services/public_store_scroll_state.dart';
import 'package:vinabike_erp/shared/models/tenant.dart';
import 'package:vinabike_erp/shared/services/tenant_detection_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

WebsiteEditorCapabilitySnapshot _cap({int epoch = 0}) =>
    WebsiteEditorCapabilitySnapshot(
      identity: 'user-a',
      activeTenantId: 'tenant-1',
      storefrontTenantId: 'tenant-1',
      hasAuthority: true,
      authorityEpoch: epoch,
    );

CachedPageSnapshot _homeSnapshot({String marker = 'v1'}) => CachedPageSnapshot(
      page: WebsitePage(
        id: 'home-page',
        tenantId: 'tenant-1',
        slug: 'inicio',
        title: 'Inicio',
        isPublished: true,
        isHome: true,
        createdAt: DateTime.utc(2026, 7, 30),
        updatedAt: DateTime.utc(2026, 7, 30),
      ),
      blocks: [
        {
          'id': 'home-visible',
          'tenant_id': 'tenant-1',
          'page_id': 'home-page',
          'block_type': 'about',
          'block_data': {'title': 'Visible $marker'},
          'order_index': 0,
          'is_visible': true,
        },
        {
          'id': 'home-hidden',
          'tenant_id': 'tenant-1',
          'page_id': 'home-page',
          'block_type': 'text',
          'block_data': {'text': 'Borrador oculto $marker'},
          'order_index': 1,
          'is_visible': false,
        },
      ],
    );

/// Home fixture: the PUBLIC bootstrap keeps serving `blocks`, while every
/// editor read goes through gated `loadEditorPageWithBlocks('')` requests the
/// test completes manually (success, superseded, or a later fresh grant).
class _HomeEditorWebsiteService extends WebsiteService {
  _HomeEditorWebsiteService()
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
  final List<String> editorLoadSlugs = [];

  @override
  List<Map<String, dynamic>> get blocks => const [
        {
          'id': 'public-1',
          'block_type': 'about',
          'block_data': {'title': 'Público bootstrap'},
          'order_index': 0,
          'is_visible': true,
        },
      ];

  @override
  bool get hasLoadedForTenant => true;

  @override
  Future<CachedPageSnapshot?> loadEditorPageWithBlocks(
    String slug, {
    required String tenantId,
  }) {
    editorLoadSlugs.add(slug);
    final completer = Completer<CachedPageSnapshot?>();
    editorLoads.add(completer);
    return completer.future;
  }

  void poke() => notifyListeners();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  Future<
      ({
        WebsiteEditModeProvider editMode,
        _HomeEditorWebsiteService service,
      })> pumpHome(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final editMode = WebsiteEditModeProvider();
    addTearDown(editMode.dispose);
    editMode.adoptEditorEntryLease(0, _cap());
    editMode.applyRouteModeCommand(WebsiteEditorMode.edit);

    final service = _HomeEditorWebsiteService();
    addTearDown(service.dispose);
    final tenant = PublicStoreTenantProvider(TenantDetectionService())
      ..setTenant(
        Tenant(
          id: 'tenant-1',
          shopName: 'Home editor test',
          subdomain: 'home',
          createdAt: DateTime.utc(2026, 7, 30),
          updatedAt: DateTime.utc(2026, 7, 30),
        ),
      );
    final inventory = PublicInventoryService();
    final scrollState = PublicStoreScrollState();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: editMode),
          ChangeNotifierProvider<WebsiteService>.value(value: service),
          ChangeNotifierProvider.value(value: tenant),
          ChangeNotifierProvider.value(value: inventory),
          Provider.value(value: scrollState),
        ],
        child: const MaterialApp(
          home: Scaffold(body: PublicHomePage()),
        ),
      ),
    );
    await tester.pump();
    return (editMode: editMode, service: service);
  }

  testWidgets(
    'HOME editor content arrives ONLY through the RPC and binds the REAL '
    'home owner (draft + hidden blocks, canonical page id/slug)',
    (tester) async {
      final harness = await pumpHome(tester);
      final editMode = harness.editMode;
      final service = harness.service;

      expect(service.editorLoads, hasLength(1),
          reason: 'The granted lease requests exactly one editor read.');
      expect(service.editorLoadSlugs.single, '',
          reason: 'Home uses the canonical empty-slug RPC branch.');
      expect(editMode.ownsPageDocument(pageId: 'home-page'), isFalse,
          reason: 'The PUBLIC bootstrap never binds the editor document.');

      service.editorLoads.single.complete(_homeSnapshot());
      await tester.pump();
      await tester.pump();

      expect(
        editMode.ownsPageDocument(pageId: 'home-page', pageSlug: 'inicio'),
        isTrue,
        reason: 'The HOME document binds its REAL owner page id/slug.',
      );
      expect(editMode.blocks, hasLength(2),
          reason: 'Draft AND hidden blocks arrive through the RPC.');
      expect(
        editMode.blocks.last['block_data']['text'],
        'Borrador oculto v1',
      );
      await tester.pump(const Duration(seconds: 5)); // Drain retry timers.
    },
  );

  testWidgets(
    'HOME epoch matrix: the same fingerprint at a NEW authorityEpoch never '
    'reuses snapshot A; only the new epoch\'s RPC can bind',
    (tester) async {
      final harness = await pumpHome(tester);
      final editMode = harness.editMode;
      final service = harness.service;
      service.editorLoads.single.complete(_homeSnapshot());
      await tester.pump();
      await tester.pump();
      expect(editMode.ownsPageDocument(pageId: 'home-page'), isTrue);

      // Coalesced churn reproduces the fingerprint at epoch 1: the provider
      // takeover clears the session and the held snapshot is stale.
      editMode.adoptEditorEntryLease(
        editMode.editorEntryLeaseGeneration,
        _cap(epoch: 1),
      );
      editMode.applyRouteModeCommand(WebsiteEditorMode.edit);
      await tester.pump();
      await tester.pump();

      expect(service.editorLoads, hasLength(2),
          reason: 'The new epoch issues its OWN editor read.');
      expect(editMode.ownsPageDocument(pageId: 'home-page'), isFalse,
          reason: 'Epoch-0 snapshot is never reused under epoch 1.');

      service.editorLoads.last.complete(_homeSnapshot(marker: 'v2'));
      await tester.pump();
      await tester.pump();
      expect(
        editMode.ownsPageDocument(pageId: 'home-page', pageSlug: 'inicio'),
        isTrue,
        reason: 'ONLY the new epoch\'s RPC result binds.',
      );
      expect(
        editMode.blocks.last['block_data']['text'],
        'Borrador oculto v2',
      );
      await tester.pump(const Duration(seconds: 5)); // Drain retry timers.
    },
  );

  testWidgets(
    'HOME late SUPERSEDED completion neither blocks the loader nor adopts '
    'the old snapshot',
    (tester) async {
      final harness = await pumpHome(tester);
      final editMode = harness.editMode;
      final service = harness.service;

      service.editorLoads.single.completeError(
        const WebsiteEditorReadSupersededException(
          'lectura obsoleta de una identidad anterior',
        ),
      );
      await tester.pump();
      expect(editMode.ownsPageDocument(pageId: 'home-page'), isFalse);

      // The loader must be free again: a later rebuild issues a NEW read.
      service.poke();
      await tester.pump();
      expect(service.editorLoads, hasLength(2),
          reason: 'The superseded completion released the in-flight state.');

      service.editorLoads.last.complete(_homeSnapshot(marker: 'v3'));
      await tester.pump();
      await tester.pump();
      expect(
        editMode.ownsPageDocument(pageId: 'home-page', pageSlug: 'inicio'),
        isTrue,
      );
      expect(
        editMode.blocks.last['block_data']['text'],
        'Borrador oculto v3',
      );
      await tester.pump(const Duration(seconds: 5)); // Drain retry timers.
    },
  );
}
