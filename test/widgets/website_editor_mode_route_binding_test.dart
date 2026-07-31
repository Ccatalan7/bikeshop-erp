import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/models/website_editor_capability.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/public_store/providers/cart_provider.dart';
import 'package:vinabike_erp/public_store/providers/public_store_tenant_provider.dart';
import 'package:vinabike_erp/public_store/services/public_inventory_service.dart';
import 'package:vinabike_erp/public_store/services/public_store_scroll_state.dart';
import 'package:vinabike_erp/public_store/widgets/public_store_layout.dart';
import 'package:vinabike_erp/shared/services/tenant_detection_service.dart';

/// Exercises the deterministic route/FSM adapter that PublicStoreLayout
/// installs: a CHANGED URI is a mode entry command, an unchanged URI never
/// competes with the provider, and there are no timers, pending flags or
/// remount paths involved.

/// Grants the editor-entry capability unconditionally so mode/adapter tests
/// exercise the FSM without the authority seam (covered by
/// website_editor_entry_authority_test.dart).
class _GrantingWebsiteService extends WebsiteService {
  static const _lease = WebsiteEditorCapabilitySnapshot(
    identity: 'test-user',
      activeTenantId: 'test-tenant',
      storefrontTenantId: 'test-tenant',
      hasAuthority: true,
  );

  @override
  WebsiteEditorCapabilitySnapshot? editorCapabilitySync(
    String? storefrontTenantId,
  ) =>
      _lease;

  @override
  Future<WebsiteEditorCapabilitySnapshot> resolveEditorCapability(
    String? storefrontTenantId,
  ) async =>
      _lease;
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
        GoRouter router,
        WebsiteEditModeProvider editMode,
      })> pumpStorefront(
    WidgetTester tester, {
    required String initialLocation,
  }) async {
    await tester.binding.setSurfaceSize(const Size(2400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    PublicStoreRuntimeConfig.isErpMounted = true;
    addTearDown(() => PublicStoreRuntimeConfig.isErpMounted = false);

    final editMode = WebsiteEditModeProvider();
    addTearDown(editMode.dispose);
    final website = _GrantingWebsiteService();
    final tenant = PublicStoreTenantProvider(TenantDetectionService());
    final cart = CartProvider();
    final inventory = PublicInventoryService();
    final scrollState = PublicStoreScrollState();

    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                size: const Size(700, 1200),
              ),
              child: MultiProvider(
                providers: [
                  ChangeNotifierProvider.value(value: editMode),
                  // Typed registration: the layout resolves the base
                  // WebsiteService, not the test subtype.
                  ChangeNotifierProvider<WebsiteService>.value(value: website),
                  ChangeNotifierProvider.value(value: tenant),
                  ChangeNotifierProvider.value(value: cart),
                  ChangeNotifierProvider.value(value: inventory),
                  Provider.value(value: scrollState),
                ],
                child: PublicStoreLayout(child: navigationShell),
              ),
            );
          },
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/tienda',
                  builder: (context, state) => const SizedBox.shrink(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/tienda/productos',
                  builder: (context, state) => const SizedBox.shrink(),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    return (router: router, editMode: editMode);
  }

  testWidgets(
    'an initial deep link enters the requested mode without any page-side '
    'synchronizer',
    (tester) async {
      final harness = await pumpStorefront(
        tester,
        initialLocation: '/tienda?edit=true',
      );
      expect(harness.editMode.mode, WebsiteEditorMode.edit);

      // The deferred FSM notification settles within one frame.
      await tester.pump();
      expect(harness.editMode.mode, WebsiteEditorMode.edit);
      expect(harness.editMode.isInEditorContext, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'a deep link with both flags enters Edit deterministically',
    (tester) async {
      final harness = await pumpStorefront(
        tester,
        initialLocation: '/tienda?edit=true&preview=true',
      );
      expect(harness.editMode.mode, WebsiteEditorMode.edit);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'URI changes replay mode commands (browser Back/forward) while a '
    'flag-less URI never exits the open session',
    (tester) async {
      final harness = await pumpStorefront(
        tester,
        initialLocation: '/tienda?edit=true',
      );
      final editMode = harness.editMode;
      final router = harness.router;
      expect(editMode.mode, WebsiteEditorMode.edit);

      // Forward navigation into Preview (as the write-through projection
      // would record it in browser history).
      router.go('/tienda?preview=true');
      await tester.pump();
      expect(editMode.mode, WebsiteEditorMode.preview);

      // "Back" to the edit entry replays Edit.
      router.go('/tienda?edit=true');
      await tester.pump();
      expect(editMode.mode, WebsiteEditorMode.edit);

      // "Back" past the editor entry (flag-less URI) is NOT an exit command:
      // exits belong to the guarded close flow.
      router.go('/tienda');
      await tester.pump();
      expect(editMode.mode, WebsiteEditorMode.edit);
      expect(editMode.isInEditorContext, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'a provider-side transition wins over the unchanged stale URI and a '
    'pending draft survives the mode change',
    (tester) async {
      final harness = await pumpStorefront(
        tester,
        initialLocation: '/tienda?preview=true',
      );
      final editMode = harness.editMode;
      expect(editMode.mode, WebsiteEditorMode.preview);
      await tester.pump();

      // Attach a document and switch to Edit from the provider side while
      // the URI still says ?preview=true (projection in flight).
      editMode.openEditorDocument(
        const [
          {
            'id': 'block-1',
            'block_type': 'about',
            'block_data': {'title': 'Original'},
            'order_index': 0,
          },
        ],
        const {},
        mode: WebsiteEditorMode.edit,
      );
      editMode.updateBlockData('block-1', 'title', 'Draft');
      expect(editMode.hasUnsavedChanges, isTrue);

      // Rebuilds with the unchanged URI must not bounce the FSM back.
      await tester.pump();
      await tester.pump();
      expect(editMode.mode, WebsiteEditorMode.edit);

      // A rapid provider-side toggle settles on the last revision and the
      // draft survives.
      editMode.setMode(WebsiteEditorMode.preview);
      editMode.setMode(WebsiteEditorMode.edit);
      editMode.setMode(WebsiteEditorMode.preview);
      await tester.pump();
      expect(editMode.mode, WebsiteEditorMode.preview);
      expect(editMode.hasUnsavedChanges, isTrue);
      expect(
        editMode.blocks.single['block_data']['title'],
        'Draft',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
