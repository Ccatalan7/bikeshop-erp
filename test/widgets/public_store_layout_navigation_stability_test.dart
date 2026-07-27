import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/public_store/providers/cart_provider.dart';
import 'package:vinabike_erp/public_store/providers/public_store_tenant_provider.dart';
import 'package:vinabike_erp/public_store/routes/public_store_router.dart';
import 'package:vinabike_erp/public_store/services/public_store_scroll_state.dart';
import 'package:vinabike_erp/public_store/widgets/public_store_layout.dart';
import 'package:vinabike_erp/shared/services/tenant_detection_service.dart';

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
      final website = WebsiteService();
      final tenant = PublicStoreTenantProvider(TenantDetectionService());
      final cart = CartProvider();
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
                    ChangeNotifierProvider.value(value: website),
                    ChangeNotifierProvider.value(value: tenant),
                    ChangeNotifierProvider.value(value: cart),
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

      editMode.switchToPreviewMode();
      await tester.pump();

      // This is the screenshot path: Preview pushes a clean category route
      // while the same StatefulNavigationShell remains under the ERP layout.
      router.push<void>(
        '/tienda/productos/categoria/camaras?preview=true',
      );
      await tester.pump();
      router.pop();
      await tester.pump();

      editMode.switchToEditMode();
      await tester.pump();

      // Normal ERP route changes reuse the same StatefulNavigationShell too;
      // the public content AnimatedSwitcher must not retain it as an outgoing
      // child while mounting the next URI.
      editMode.exitEditMode();
      await tester.pump();
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
}
