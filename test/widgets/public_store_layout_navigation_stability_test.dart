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
import 'package:vinabike_erp/public_store/routes/public_store_router.dart';
import 'package:vinabike_erp/public_store/services/public_inventory_service.dart';
import 'package:vinabike_erp/public_store/services/public_store_scroll_state.dart';
import 'package:vinabike_erp/public_store/widgets/public_store_layout.dart';
import 'package:vinabike_erp/shared/services/tenant_detection_service.dart';

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

  testWidgets(
    'ERP shell reuses branch Navigators across CMS modes and routes',
    (tester) async {
      // Keep desktop layout constraints realistic while the scoped MediaQuery
      // below sends the footer through its asset-backed mobile path. This test
      // exercises shell identity, not remote payment-logo loading.
      await tester.binding.setSurfaceSize(const Size(2400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final navigationErrors = <Object>[];
      final originalErrorHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        final message = details.exceptionAsString();
        if (message.contains('GlobalKey') ||
            message.contains('HeroControllerScope')) {
          navigationErrors.add(details.exception);
          return;
        }

        originalErrorHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalErrorHandler);

      PublicStoreRuntimeConfig.isErpMounted = true;
      addTearDown(() => PublicStoreRuntimeConfig.isErpMounted = false);

      final editMode = WebsiteEditModeProvider()
        ..enterEditMode(const [], const {}, pageSlug: 'productos');
      final website = _GrantingWebsiteService();
      final tenant = PublicStoreTenantProvider(TenantDetectionService());
      final cart = CartProvider();
      final inventory = PublicInventoryService();
      final scrollState = PublicStoreScrollState();

      final router = GoRouter(
        initialLocation: '/tienda/productos',
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
                    ChangeNotifierProvider<WebsiteService>.value(
                      value: website,
                    ),
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
                    routes: [
                      GoRoute(
                        path: 'categoria/:category',
                        builder: (context, state) => const SizedBox.shrink(),
                      ),
                    ],
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

      // The FSM owns the mode: transitions rebuild in place and must keep
      // the same Scaffold element (no remount of the storefront shell).
      final scaffoldBeforeToggle = tester.element(
        find
            .descendant(
              of: find.byType(PublicStoreLayout),
              matching: find.byType(Scaffold),
            )
            .first,
      );

      editMode.setMode(WebsiteEditorMode.preview);
      await tester.pump();

      final scaffoldAfterToggle = tester.element(
        find
            .descendant(
              of: find.byType(PublicStoreLayout),
              matching: find.byType(Scaffold),
            )
            .first,
      );
      expect(
        identical(scaffoldBeforeToggle, scaffoldAfterToggle),
        isTrue,
        reason: 'An Edit→Preview transition must not remount the shell '
            'Scaffold.',
      );
      expect(editMode.mode, WebsiteEditorMode.preview);

      // This is the screenshot path: Preview pushes a clean category route
      // while the same StatefulNavigationShell remains under the ERP layout.
      router.push<void>(
        '/tienda/productos/categoria/camaras?preview=true',
      );
      await tester.pump();
      router.pop();
      await tester.pump();

      // Rapid Preview↔Edit toggles settle synchronously on the last revision
      // without timers or pending flags.
      editMode.setMode(WebsiteEditorMode.edit);
      editMode.setMode(WebsiteEditorMode.preview);
      editMode.setMode(WebsiteEditorMode.edit);
      await tester.pump();
      expect(editMode.mode, WebsiteEditorMode.edit);

      // Normal ERP route changes reuse the same StatefulNavigationShell too;
      // the public content AnimatedSwitcher must not retain it as an outgoing
      // child while mounting the next URI.
      editMode.closeEditor();
      await tester.pump();
      expect(editMode.mode, WebsiteEditorMode.public);
      router.go('/tienda');
      await tester.pump();
      router.go('/tienda/productos');
      await tester.pump();

      expect(navigationErrors, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'mode-flag query changes never remount the routed storefront subtree',
    (tester) async {
      Page<void> buildPage(BuildContext context, GoRouterState state) {
        return NoTransitionPage<void>(
          key: publicStoreRoutePageKey(state),
          child: KeyedSubtree(
            key: publicStoreModeContentKey(state),
            child: Text(state.uri.toString()),
          ),
        );
      }

      final router = GoRouter(
        initialLocation: '/productos',
        routes: [
          GoRoute(
            path: '/productos',
            pageBuilder: (context, state) => buildPage(context, state),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();

      final elementBefore = tester.element(find.byType(Text));

      router.go('/productos?edit=true');
      await tester.pump();
      expect(find.text('/productos?edit=true'), findsOneWidget);
      final elementEdit = tester.element(find.byType(Text));
      expect(
        identical(elementBefore, elementEdit),
        isTrue,
        reason: 'Entering Edit through the URL projection must rebuild the '
            'routed subtree in place, not remount it.',
      );

      router.go('/productos?preview=true');
      await tester.pump();
      final elementPreview = tester.element(find.byType(Text));
      expect(
        identical(elementEdit, elementPreview),
        isTrue,
        reason: 'Edit↔Preview URL changes must not remount the routed '
            'subtree.',
      );
    },
  );

  testWidgets(
    'standalone category to catalog root keeps Navigator page keys distinct',
    (tester) async {
      Page<void> buildPage(BuildContext context, GoRouterState state) {
        return NoTransitionPage<void>(
          key: publicStoreRoutePageKey(state),
          child: KeyedSubtree(
            key: publicStoreModeContentKey(state),
            child: Text(state.uri.toString()),
          ),
        );
      }

      final router = GoRouter(
        initialLocation: '/productos',
        routes: [
          GoRoute(
            path: '/productos',
            pageBuilder: (context, state) => buildPage(context, state),
          ),
          GoRoute(
            path: '/productos/categoria/:category',
            pageBuilder: (context, state) => buildPage(context, state),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();

      // The real catalog pushes a clean category page from the root, then the
      // breadcrumb replaces that category with /productos. Both root pages
      // coexist for one Navigator update and therefore need different keys.
      router.push<void>('/productos/categoria/cadenas');
      await tester.pump();
      router.replace<void>('/productos');
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('/productos'), findsOneWidget);
    },
  );

  _stateRetentionTests();
}

/// Real routed-content probe: text, focus, scroll and State identity must
/// survive every mode/device toggle under the stable content anchor.
class _StateProbePage extends StatefulWidget {
  const _StateProbePage();

  @override
  State<_StateProbePage> createState() => _StateProbePageState();
}

class _StateProbePageState extends State<_StateProbePage>
    with AutomaticKeepAliveClientMixin {
  static int disposeCount = 0;
  final TextEditingController textController = TextEditingController();
  final FocusNode focusNode = FocusNode();
  final ScrollController scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    disposeCount++;
    textController.dispose();
    focusNode.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        TextField(
          key: const ValueKey('probe_text_field'),
          controller: textController,
          focusNode: focusNode,
        ),
        // The storefront shell scrolls the routed content, so the probe
        // shrink-wraps: a fixed-height inner list still proves scroll
        // retention.
        SizedBox(
          height: 400,
          child: ListView.builder(
            controller: scrollController,
            itemCount: 60,
            itemBuilder: (context, index) => SizedBox(
              height: 40,
              child: Text('fila $index'),
            ),
          ),
        ),
      ],
    );
  }
}

/// Standalone routed-content probe with no keep-alive, shell branch, nested
/// Navigator or GlobalKey. Its identity is therefore preserved only when the
/// real PublicStoreLayout wrapper topology remains stable.
class _StandaloneStateProbePage extends StatefulWidget {
  const _StandaloneStateProbePage();

  @override
  State<_StandaloneStateProbePage> createState() =>
      _StandaloneStateProbePageState();
}

class _StandaloneStateProbePageState extends State<_StandaloneStateProbePage> {
  static int disposeCount = 0;
  final TextEditingController textController = TextEditingController();
  final FocusNode focusNode = FocusNode();
  final ScrollController scrollController = ScrollController();
  double mediaWidth = 0;

  @override
  void dispose() {
    disposeCount++;
    textController.dispose();
    focusNode.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    mediaWidth = MediaQuery.sizeOf(context).width;
    return Column(
      children: [
        TextField(
          key: const ValueKey('standalone_probe_text_field'),
          controller: textController,
          focusNode: focusNode,
        ),
        SizedBox(
          height: 400,
          child: ListView.builder(
            controller: scrollController,
            itemCount: 60,
            itemBuilder: (context, index) => SizedBox(
              height: 40,
              child: Text('standalone fila $index'),
            ),
          ),
        ),
      ],
    );
  }
}

void _stateRetentionTests() {
  testWidgets(
    'standalone GoRoute keeps identical State, text, focus and scroll through '
    'Public/Preview/Edit and desktop/tablet/mobile transitions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(2400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final wasErpMounted = PublicStoreRuntimeConfig.isErpMounted;
      PublicStoreRuntimeConfig.isErpMounted = false;
      addTearDown(
        () => PublicStoreRuntimeConfig.isErpMounted = wasErpMounted,
      );
      _StandaloneStateProbePageState.disposeCount = 0;

      final editMode = WebsiteEditModeProvider();
      addTearDown(editMode.dispose);
      final website = _GrantingWebsiteService();
      final tenant = PublicStoreTenantProvider(TenantDetectionService());
      final cart = CartProvider();
      final inventory = PublicInventoryService();
      final scrollState = PublicStoreScrollState();

      final router = GoRouter(
        initialLocation: '/productos',
        routes: [
          GoRoute(
            path: '/productos',
            pageBuilder: (context, state) => NoTransitionPage<void>(
              key: publicStoreRoutePageKey(state),
              child: KeyedSubtree(
                key: publicStoreModeContentKey(state),
                // Public web disables the native content AnimatedSwitcher.
                // Scope that exact production condition directly over the
                // layout so this regression isolates wrapper topology.
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    disableAnimations: true,
                  ),
                  child: MultiProvider(
                    providers: [
                      ChangeNotifierProvider.value(value: editMode),
                      ChangeNotifierProvider<WebsiteService>.value(
                        value: website,
                      ),
                      ChangeNotifierProvider.value(value: tenant),
                      ChangeNotifierProvider.value(value: cart),
                      ChangeNotifierProvider.value(value: inventory),
                      Provider.value(value: scrollState),
                    ],
                    child: const PublicStoreLayout(
                      child: _StandaloneStateProbePage(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();
      await tester.pump();

      final probeBefore = tester.state<_StandaloneStateProbePageState>(
        find.byType(_StandaloneStateProbePage),
      );
      final desktopMediaWidth = probeBefore.mediaWidth;
      await tester.enterText(
        find.byKey(const ValueKey('standalone_probe_text_field')),
        'borrador standalone',
      );
      probeBefore.focusNode.requestFocus();
      await tester.pump();
      probeBefore.scrollController.jumpTo(320);
      await tester.pump();

      Future<void> assertRetained(
        String phase, {
        double? mediaWidth,
      }) async {
        final probe = tester.state<_StandaloneStateProbePageState>(
          find.byType(_StandaloneStateProbePage),
        );
        expect(identical(probe, probeBefore), isTrue,
            reason: '[$phase] the plain GoRoute State must be identical.');
        expect(probe.textController.text, 'borrador standalone',
            reason: '[$phase] text survives.');
        expect(probe.focusNode.hasFocus, isTrue,
            reason: '[$phase] focus survives.');
        expect(probe.scrollController.offset, 320,
            reason: '[$phase] scroll survives.');
        expect(_StandaloneStateProbePageState.disposeCount, 0,
            reason: '[$phase] no routed State disposal is allowed.');
        if (mediaWidth != null) {
          expect(probe.mediaWidth, mediaWidth,
              reason: '[$phase] must exercise the real framed viewport.');
        }
      }

      await assertRetained('public');
      editMode.enterPreviewMode(const [], const {});
      router.go('/productos?preview=true');
      await tester.pump();
      expect(router.routeInformationProvider.value.uri.query, 'preview=true');
      await assertRetained('preview/desktop', mediaWidth: desktopMediaWidth);
      editMode.setMode(WebsiteEditorMode.edit);
      router.go('/productos?edit=true');
      await tester.pump();
      expect(router.routeInformationProvider.value.uri.query, 'edit=true');
      await assertRetained('edit/desktop', mediaWidth: desktopMediaWidth);

      editMode.setDevicePreviewMode(DevicePreviewMode.mobile);
      await tester.pump();
      await assertRetained('edit/mobile', mediaWidth: 390);
      editMode.setDevicePreviewMode(DevicePreviewMode.tablet);
      await tester.pump();
      await assertRetained('edit/tablet', mediaWidth: 820);
      editMode.setDevicePreviewMode(DevicePreviewMode.desktop);
      await tester.pump();
      await assertRetained(
        'edit/desktop-2',
        mediaWidth: desktopMediaWidth,
      );

      editMode.setMode(WebsiteEditorMode.preview);
      router.go('/productos?preview=true');
      await tester.pump();
      expect(router.routeInformationProvider.value.uri.query, 'preview=true');
      await assertRetained('preview-2');
      editMode.closeEditor();
      router.go('/productos');
      await tester.pump();
      await tester.pump();
      expect(router.routeInformationProvider.value.uri.query, isEmpty);
      await assertRetained('public-2');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(_StandaloneStateProbePageState.disposeCount, 1);
    },
  );

  testWidgets(
    'H MATRIX: routed State identity, text, focus and scroll survive '
    'Public→Preview→Edit→Preview→Public plus device-preview changes '
    '(zero remounts, zero disposes)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(2400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      PublicStoreRuntimeConfig.isErpMounted = true;
      addTearDown(() => PublicStoreRuntimeConfig.isErpMounted = false);
      _StateProbePageState.disposeCount = 0;

      final editMode = WebsiteEditModeProvider();
      addTearDown(editMode.dispose);
      final website = _GrantingWebsiteService();
      final tenant = PublicStoreTenantProvider(TenantDetectionService());
      final cart = CartProvider();
      final inventory = PublicInventoryService();
      final scrollState = PublicStoreScrollState();

      final router = GoRouter(
        initialLocation: '/tienda',
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) => MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: editMode),
                ChangeNotifierProvider<WebsiteService>.value(value: website),
                ChangeNotifierProvider.value(value: tenant),
                ChangeNotifierProvider.value(value: cart),
                ChangeNotifierProvider.value(value: inventory),
                Provider.value(value: scrollState),
              ],
              child: PublicStoreLayout(child: navigationShell),
            ),
            branches: [
              StatefulShellBranch(routes: [
                GoRoute(
                  path: '/tienda',
                  builder: (context, state) => const _StateProbePage(),
                ),
              ]),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();

      // Real user state in PUBLIC mode.
      final probeBefore =
          tester.state<_StateProbePageState>(find.byType(_StateProbePage));
      await tester.enterText(
        find.byKey(const ValueKey('probe_text_field')),
        'borrador cliente',
      );
      probeBefore.focusNode.requestFocus();
      await tester.pump();
      probeBefore.scrollController.jumpTo(320);
      await tester.pump();

      Future<void> assertRetained(String phase) async {
        final probe =
            tester.state<_StateProbePageState>(find.byType(_StateProbePage));
        expect(identical(probe, probeBefore), isTrue,
            reason: '[$phase] the routed State object must be THE SAME.');
        expect(probe.textController.text, 'borrador cliente',
            reason: '[$phase] text survives.');
        expect(probe.scrollController.offset, 320,
            reason: '[$phase] scroll survives.');
        expect(_StateProbePageState.disposeCount, 0,
            reason: '[$phase] zero disposes from mode/device toggles.');
      }

      // Public -> Preview -> Edit -> Preview -> Public.
      editMode.enterPreviewMode(const [], const {});
      await tester.pump();
      await assertRetained('preview');
      editMode.setMode(WebsiteEditorMode.edit);
      await tester.pump();
      await assertRetained('edit');
      expect(probeBefore.focusNode.hasFocus, isTrue,
          reason: 'Focus survives entering Edit.');

      // Device preview toggles inside Edit only change constraints.
      editMode.setDevicePreviewMode(DevicePreviewMode.mobile);
      await tester.pump();
      await assertRetained('edit/mobile');
      editMode.setDevicePreviewMode(DevicePreviewMode.tablet);
      await tester.pump();
      await assertRetained('edit/tablet');
      editMode.setDevicePreviewMode(DevicePreviewMode.desktop);
      await tester.pump();
      await assertRetained('edit/desktop');

      editMode.setMode(WebsiteEditorMode.preview);
      await tester.pump();
      await assertRetained('preview-2');
      editMode.closeEditor();
      await tester.pump();
      await tester.pump();
      await assertRetained('public-2');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
