import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_navigation_guard.dart';
import 'package:vinabike_erp/public_store/services/checkout_exit_guard.dart';
import 'package:vinabike_erp/public_store/widgets/public_store_layout.dart';
import 'package:vinabike_erp/public_store/widgets/storefront_navigation_guard_scope.dart';

void main() {
  test('a new tab never replaces the current editor document', () {
    expect(
      WebsiteEditorNavigationGuard.classifyIntent(
        openInNewTab: true,
        launchesExternalWindow: true,
        keepsCurrentPage: true,
      ),
      WebsiteEditorNavigationIntent.newTab,
    );
  });

  testWidgets(
    'a CTA respects the editor draft guard before changing routes',
    (tester) async {
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          const [
            {
              'id': 'block-1',
              'block_type': 'about',
              'block_data': {'title': 'Original'},
            },
          ],
          const <String, dynamic>{},
        )
        ..updateBlockData('block-1', 'title', 'Draft');

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: Center(
                child: FilledButton(
                  key: const ValueKey('draft-cta'),
                  onPressed: () =>
                      PublicStoreLayout.navigateToHref(context, '/destino'),
                  child: const Text('Ir al destino'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/destino',
            builder: (context, state) => const Scaffold(
              body: Text('Destino'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('draft-cta')));
      await tester.pumpAndSettle();

      expect(find.text('Cambios sin guardar'), findsOneWidget);
      expect(provider.hasUnsavedChanges, isTrue);
      expect(router.routeInformationProvider.value.uri.path, '/');

      await tester.tap(
        find.byKey(const ValueKey('website-draft-navigation-cancel')),
      );
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(provider.hasUnsavedChanges, isTrue);

      await tester.tap(find.byKey(const ValueKey('draft-cta')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('website-draft-navigation-confirm')),
      );
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, '/destino');
      expect(find.text('Destino'), findsOneWidget);
      expect(provider.hasPageDraftChanges, isFalse);
      expect(
        provider.blocks.single['block_data'],
        {'title': 'Original'},
      );
    },
  );

  testWidgets(
    'sitewide-only drafts survive a page navigation without a page guard',
    (tester) async {
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          const [
            {
              'id': 'block-1',
              'block_type': 'about',
              'block_data': {'title': 'Original'},
            },
          ],
          const <String, dynamic>{},
          pageId: 'page-a',
          pageSlug: 'page-a',
        )
        ..updateSiteSetting('store_name', 'Sitewide draft');

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: FilledButton(
                key: const ValueKey('sitewide-navigation'),
                onPressed: () =>
                    PublicStoreLayout.navigateToHref(context, '/destino'),
                child: const Text('Navegar'),
              ),
            ),
          ),
          GoRoute(
            path: '/destino',
            builder: (context, state) => const Scaffold(
              body: Text('Destino sitewide'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('sitewide-navigation')));
      await tester.pumpAndSettle();

      expect(find.text('Cambios sin guardar'), findsNothing);
      expect(find.text('Destino sitewide'), findsOneWidget);
      expect(provider.pendingSiteSettings, {
        'store_name': 'Sitewide draft',
      });
      expect(provider.hasUnsavedChanges, isTrue);
      expect(provider.hasPageDraftChanges, isFalse);
    },
  );

  testWidgets(
    'same-tab external CTA keeps every draft scope when launch fails',
    (tester) async {
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          const [
            {
              'id': 'block-1',
              'block_type': 'about',
              'block_data': {'title': 'Original'},
            },
          ],
          const <String, dynamic>{},
          pageId: 'page-a',
          pageSlug: 'page-a',
        )
        ..updateSiteSetting('store_name', 'Sitewide draft');
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  key: const ValueKey('external-navigation'),
                  onPressed: () => PublicStoreLayout.navigateToHref(
                    context,
                    'https://example.com/otra-tienda',
                  ),
                  child: const Text('Salir'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('external-navigation')));
      await tester.pumpAndSettle();

      expect(find.text('Cambios sin guardar'), findsOneWidget);
      expect(provider.hasUnsavedChanges, isTrue);

      await tester.tap(
        find.byKey(const ValueKey('website-draft-navigation-cancel')),
      );
      await tester.pumpAndSettle();
      expect(provider.hasUnsavedChanges, isTrue);

      await tester.tap(find.byKey(const ValueKey('external-navigation')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('website-draft-navigation-confirm')),
      );
      await tester.pump();

      expect(provider.hasUnsavedChanges, isTrue);
      expect(provider.pendingSiteSettings, {
        'store_name': 'Sitewide draft',
      });
    },
  );

  testWidgets(
    'a slow clean CTA aborts when a page draft appears before navigation',
    (tester) async {
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          const [
            {
              'id': 'block-1',
              'block_type': 'about',
              'block_data': {'title': 'Original'},
            },
          ],
          const <String, dynamic>{},
          pageId: 'page-a',
          pageSlug: 'page-a',
        );
      final resolutionGate = Completer<void>();
      final authorizationStarted = Completer<void>();
      addTearDown(provider.dispose);

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: FilledButton(
                key: const ValueKey('slow-clean-navigation'),
                onPressed: () async {
                  final decision = await WebsiteEditorNavigationGuard.authorize(
                    context,
                    intent: WebsiteEditorNavigationIntent.switchPage,
                  );
                  authorizationStarted.complete();
                  await resolutionGate.future;
                  if (!context.mounted || !decision.commit()) return;
                  context.go('/destino');
                },
                child: const Text('Resolver destino'),
              ),
            ),
          ),
          GoRoute(
            path: '/destino',
            builder: (context, state) => const Scaffold(
              body: Text('Destino lento'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('slow-clean-navigation')));
      await authorizationStarted.future;
      provider.updateBlockData('block-1', 'title', 'Late draft');
      resolutionGate.complete();
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(provider.hasPageDraftChanges, isTrue);
      expect(
        provider.blocks.single['block_data'],
        {'title': 'Late draft'},
      );
      expect(find.text('Destino lento'), findsNothing);
    },
  );

  testWidgets(
    'same-page browser replacement in Preview guards every draft scope',
    (tester) async {
      final provider = WebsiteEditModeProvider()
        ..enterPreviewMode(
          const [
            {
              'id': 'block-1',
              'block_type': 'about',
              'block_data': {'title': 'Original'},
            },
          ],
          const <String, dynamic>{},
          pageId: 'page-a',
          pageSlug: 'page-a',
        )
        ..updateBlockData('block-1', 'title', 'Page draft')
        ..updateSiteSetting('store_name', 'Sitewide draft')
        ..updatePageSeo(
          routeKey: '/page-a',
          metaTitle: 'SEO draft',
          metaDescription: 'Draft description',
        );
      addTearDown(provider.dispose);
      var replacedDocument = false;

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  key: const ValueKey('replace-browser-document'),
                  onPressed: () async {
                    final decision =
                        await WebsiteEditorNavigationGuard.authorize(
                      context,
                      intent: WebsiteEditorNavigationGuard.classifyIntent(
                        openInNewTab: false,
                        launchesExternalWindow: false,
                        keepsCurrentPage: true,
                        replacesBrowserDocument: true,
                      ),
                    );
                    if (!decision.commit()) return;
                    replacedDocument = true;
                  },
                  child: const Text('Recargar'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('replace-browser-document')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cambios sin guardar'), findsOneWidget);
      expect(provider.hasPageDraftChanges, isTrue);
      expect(provider.hasSitewideDraftChanges, isTrue);
      expect(provider.hasSeoDraftChanges, isTrue);

      await tester.tap(
        find.byKey(const ValueKey('website-draft-navigation-cancel')),
      );
      await tester.pumpAndSettle();
      expect(replacedDocument, isFalse);
      expect(provider.hasUnsavedChanges, isTrue);

      await tester.tap(
        find.byKey(const ValueKey('replace-browser-document')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('website-draft-navigation-confirm')),
      );
      await tester.pumpAndSettle();

      // leaveEditor commit closes the WHOLE session: no draft bucket, page
      // document or editor mode may survive an authorized exit.
      expect(replacedDocument, isTrue);
      expect(provider.hasUnsavedChanges, isFalse);
      expect(provider.mode, WebsiteEditorMode.public);
      expect(provider.isInEditorContext, isFalse);
      expect(provider.blocks, isEmpty);
      expect(provider.currentPageId, isNull);
      expect(provider.pendingSiteSettings, isEmpty);
      expect(provider.pendingThemeSettings, isEmpty);
      expect(provider.pendingPageSeo, isEmpty);
    },
  );

  testWidgets(
    'Back keeps the editor draft when checkout cancels after editor approval',
    (tester) async {
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          const [
            {
              'id': 'block-1',
              'block_type': 'about',
              'block_data': {'title': 'Original'},
            },
          ],
          const <String, dynamic>{},
          pageId: 'page-a',
          pageSlug: 'page-a',
        )
        ..updateBlockData('block-1', 'title', 'Draft');
      final checkoutGuard = CheckoutExitGuard();
      final lease = checkoutGuard.acquire(
        owner: Object(),
        phase: CheckoutExitPhase.recoveringOrder,
      );
      final navigatorKey = GlobalKey<NavigatorState>();
      addTearDown(() {
        lease.release();
        checkoutGuard.dispose();
        provider.dispose();
      });

      Future<bool> authorizeCheckout(
        BuildContext context, {
        required bool permitNextNavigation,
      }) {
        return checkoutGuard.requestExitAuthorization(
          (_) async =>
              await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Checkout en curso'),
                  actions: [
                    TextButton(
                      key: const ValueKey('test-checkout-cancel'),
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      key: const ValueKey('test-checkout-confirm'),
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('Salir'),
                    ),
                  ],
                ),
              ) ??
              false,
          permitNextNavigation: permitNextNavigation,
        );
      }

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: provider),
            ChangeNotifierProvider.value(value: checkoutGuard),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  key: const ValueKey('open-guarded-checkout'),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => StorefrontNavigationGuardScope(
                        guardCheckout: true,
                        authorizeCheckoutExit: authorizeCheckout,
                        child: const Scaffold(
                          body: Text('Checkout protegido'),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Abrir checkout'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('open-guarded-checkout')));
      await tester.pumpAndSettle();

      unawaited(navigatorKey.currentState!.maybePop());
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('website-draft-navigation-confirm')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('test-checkout-cancel')));
      await tester.pumpAndSettle();

      expect(find.text('Checkout protegido'), findsOneWidget);
      expect(provider.hasUnsavedChanges, isTrue);
      expect(
        provider.blocks.single['block_data'],
        {'title': 'Draft'},
      );

      unawaited(navigatorKey.currentState!.maybePop());
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('website-draft-navigation-confirm')),
      );
      await tester.pumpAndSettle();
      provider.updateBlockData('block-1', 'title', 'Newer draft');
      await tester.tap(find.byKey(const ValueKey('test-checkout-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Checkout protegido'), findsOneWidget);
      expect(provider.hasUnsavedChanges, isTrue);
      expect(
        provider.blocks.single['block_data'],
        {'title': 'Newer draft'},
      );

      unawaited(navigatorKey.currentState!.maybePop());
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('website-draft-navigation-confirm')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('test-checkout-confirm')));
      await tester.pumpAndSettle();

      // The authorized leaveEditor exit closes the whole session.
      expect(find.text('Checkout protegido'), findsNothing);
      expect(find.byKey(const ValueKey('open-guarded-checkout')), findsOne);
      expect(provider.hasUnsavedChanges, isFalse);
      expect(provider.mode, WebsiteEditorMode.public);
      expect(provider.blocks, isEmpty);
      expect(provider.currentPageId, isNull);
    },
  );

  testWidgets(
    'Back captures a clean editor revision before awaiting checkout',
    (tester) async {
      final provider = WebsiteEditModeProvider();
      final checkoutGuard = CheckoutExitGuard();
      final lease = checkoutGuard.acquire(
        owner: Object(),
        phase: CheckoutExitPhase.recoveringOrder,
      );
      final navigatorKey = GlobalKey<NavigatorState>();
      addTearDown(() {
        lease.release();
        checkoutGuard.dispose();
        provider.dispose();
      });

      Future<bool> authorizeCheckout(
        BuildContext context, {
        required bool permitNextNavigation,
      }) {
        return checkoutGuard.requestExitAuthorization(
          (_) async =>
              await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Checkout limpio'),
                  actions: [
                    FilledButton(
                      key: const ValueKey('late-draft-checkout-confirm'),
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('Salir'),
                    ),
                  ],
                ),
              ) ??
              false,
          permitNextNavigation: permitNextNavigation,
        );
      }

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: provider),
            ChangeNotifierProvider.value(value: checkoutGuard),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  key: const ValueKey('open-clean-checkout'),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => StorefrontNavigationGuardScope(
                        guardCheckout: true,
                        authorizeCheckoutExit: authorizeCheckout,
                        child: const Scaffold(
                          body: Text('Checkout inicialmente limpio'),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Abrir checkout limpio'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('open-clean-checkout')));
      await tester.pumpAndSettle();
      unawaited(navigatorKey.currentState!.maybePop());
      await tester.pumpAndSettle();

      provider
        ..enterEditMode(
          const [
            {
              'id': 'block-1',
              'block_type': 'about',
              'block_data': {'title': 'Original'},
            },
          ],
          const <String, dynamic>{},
          pageId: 'page-a',
          pageSlug: 'page-a',
        )
        ..updateBlockData('block-1', 'title', 'Late draft');
      await tester.tap(
        find.byKey(const ValueKey('late-draft-checkout-confirm')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Checkout inicialmente limpio'), findsOneWidget);
      expect(provider.hasUnsavedChanges, isTrue);
      expect(
        provider.blocks.single['block_data'],
        {'title': 'Late draft'},
      );
      expect(checkoutGuard.hasNavigationPermit, isFalse);
    },
  );

  testWidgets(
    'Back consumes local route history without discarding an editor draft',
    (tester) async {
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          const [
            {
              'id': 'block-1',
              'block_type': 'about',
              'block_data': {'title': 'Original'},
            },
          ],
          const <String, dynamic>{},
          pageId: 'page-a',
          pageSlug: 'page-a',
        )
        ..updateBlockData('block-1', 'title', 'Draft');
      final navigatorKey = GlobalKey<NavigatorState>();
      var localHistoryRemoved = false;
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  key: const ValueKey('open-local-history-route'),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => StorefrontNavigationGuardScope.pageSwitch(
                        child: Scaffold(
                          body: Builder(
                            builder: (routeContext) => FilledButton(
                              key: const ValueKey('add-local-history'),
                              onPressed: () {
                                ModalRoute.of(routeContext)!
                                    .addLocalHistoryEntry(
                                  LocalHistoryEntry(
                                    onRemove: () => localHistoryRemoved = true,
                                  ),
                                );
                              },
                              child: const Text('Abrir panel local'),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Abrir ruta'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('open-local-history-route')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-local-history')));
      await tester.pump();

      await navigatorKey.currentState!.maybePop();
      await tester.pumpAndSettle();

      expect(localHistoryRemoved, isTrue);
      expect(find.byKey(const ValueKey('add-local-history')), findsOneWidget);
      expect(find.text('Cambios sin guardar'), findsNothing);
      expect(provider.hasPageDraftChanges, isTrue);
      expect(
        provider.blocks.single['block_data'],
        {'title': 'Draft'},
      );
    },
  );

  testWidgets(
    'Stateful shell Back discards only the page draft',
    (tester) async {
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          const [
            {
              'id': 'block-1',
              'block_type': 'about',
              'block_data': {'title': 'Original'},
            },
          ],
          const <String, dynamic>{},
          pageId: 'page-a',
          pageSlug: 'page-a',
        )
        ..updateBlockData('block-1', 'title', 'Page draft')
        ..updateSiteSetting('store_name', 'Sitewide draft')
        ..updatePageSeo(
          routeKey: '/page-a',
          metaTitle: 'SEO draft',
          metaDescription: 'Description draft',
        );
      addTearDown(provider.dispose);

      Page<void> guardedPage(GoRouterState state, Widget child) {
        return NoTransitionPage<void>(
          key: state.pageKey,
          child: StorefrontNavigationGuardScope.pageSwitch(child: child),
        );
      }

      final router = GoRouter(
        initialLocation: '/store/detail',
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) => navigationShell,
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/store',
                    pageBuilder: (context, state) => guardedPage(
                      state,
                      const Scaffold(body: Text('Shell root')),
                    ),
                    routes: [
                      GoRoute(
                        path: 'detail',
                        pageBuilder: (context, state) => guardedPage(
                          state,
                          const Scaffold(body: Text('Shell detail')),
                        ),
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

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      unawaited(tester.binding.handlePopRoute());
      await tester.pumpAndSettle();
      expect(find.text('Cambios sin guardar'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('website-draft-navigation-confirm')),
      );
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, '/store');
      expect(find.text('Shell root'), findsOneWidget);
      expect(provider.hasPageDraftChanges, isFalse);
      expect(provider.hasSitewideDraftChanges, isTrue);
      expect(provider.hasSeoDraftChanges, isTrue);
      expect(provider.pendingSiteSettings, {
        'store_name': 'Sitewide draft',
      });
    },
  );

  testWidgets(
    'first-route Back exits only after the editor draft is authorized',
    (tester) async {
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          const [
            {
              'id': 'block-1',
              'block_type': 'about',
              'block_data': {'title': 'Original'},
            },
          ],
          const <String, dynamic>{},
          pageId: 'page-a',
          pageSlug: 'page-a',
        )
        ..updateBlockData('block-1', 'title', 'Draft');
      var platformExitCount = 0;
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            home: StorefrontNavigationGuardScope(
              exitPlatform: () async => platformExitCount++,
              child: const Scaffold(body: Text('Primera ruta protegida')),
            ),
          ),
        ),
      );

      unawaited(tester.binding.handlePopRoute());
      await tester.pumpAndSettle();

      expect(find.text('Cambios sin guardar'), findsOneWidget);
      expect(platformExitCount, 0);
      expect(provider.hasPageDraftChanges, isTrue);

      await tester.tap(
        find.byKey(const ValueKey('website-draft-navigation-confirm')),
      );
      await tester.pumpAndSettle();

      // The authorized leaveEditor exit closes the whole session.
      expect(platformExitCount, 1);
      expect(provider.hasPageDraftChanges, isFalse);
      expect(provider.mode, WebsiteEditorMode.public);
      expect(provider.blocks, isEmpty);
      expect(provider.currentPageId, isNull);
    },
  );

  testWidgets(
    'a clean Edit session Back (handlePopRoute) closes the FSM without a '
    'dialog and a later flag-less rebuild stays public',
    (tester) async {
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          const [
            {
              'id': 'block-1',
              'block_type': 'about',
              'block_data': {'title': 'Original'},
            },
          ],
          const <String, dynamic>{},
          pageId: 'page-a',
          pageSlug: 'page-a',
        );
      final navigatorKey = GlobalKey<NavigatorState>();
      addTearDown(provider.dispose);
      expect(provider.hasUnsavedChanges, isFalse, reason: 'clean session');

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  key: const ValueKey('open-clean-editor-route'),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => const StorefrontNavigationGuardScope(
                        child: Scaffold(body: Text('Editor limpio')),
                      ),
                    ),
                  ),
                  child: const Text('Abrir editor'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('open-clean-editor-route')));
      await tester.pumpAndSettle();
      expect(find.text('Editor limpio'), findsOneWidget);
      expect(provider.isInEditorContext, isTrue);

      // The real platform Back path, not a synthetic navigator call.
      unawaited(tester.binding.handlePopRoute());
      await tester.pumpAndSettle();

      // No confirmation dialog for a clean session; the pop completed and
      // the leaveEditor owner closed the FSM anyway.
      expect(find.text('Cambios sin guardar'), findsNothing);
      expect(find.text('Editor limpio'), findsNothing);
      expect(
        find.byKey(const ValueKey('open-clean-editor-route')),
        findsOneWidget,
      );
      expect(provider.mode, WebsiteEditorMode.public);
      expect(provider.isInEditorContext, isFalse);
      expect(provider.blocks, isEmpty);
      expect(provider.currentPageId, isNull);

      // A later rebuild of the same flag-less UI must not re-project editor
      // context: without a new entry command the FSM stays public.
      await tester.pump();
      expect(provider.mode, WebsiteEditorMode.public);
    },
  );

  testWidgets(
    'Back keeps the draft and surfaces an authorizer failure',
    (tester) async {
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          const [
            {
              'id': 'block-1',
              'block_type': 'about',
              'block_data': {'title': 'Original'},
            },
          ],
          const <String, dynamic>{},
          pageId: 'page-a',
          pageSlug: 'page-a',
        )
        ..updateBlockData('block-1', 'title', 'Draft');
      final checkoutGuard = CheckoutExitGuard();
      final lease = checkoutGuard.acquire(
        owner: Object(),
        phase: CheckoutExitPhase.recoveringOrder,
      );
      final navigatorKey = GlobalKey<NavigatorState>();
      addTearDown(() {
        lease.release();
        checkoutGuard.dispose();
        provider.dispose();
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: provider),
            ChangeNotifierProvider.value(value: checkoutGuard),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  key: const ValueKey('open-failing-checkout-guard'),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => StorefrontNavigationGuardScope(
                        guardCheckout: true,
                        authorizeCheckoutExit: (
                          context, {
                          required permitNextNavigation,
                        }) async {
                          throw StateError('authorization unavailable');
                        },
                        child: const Scaffold(
                          body: Text('Checkout con guard fallido'),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Abrir checkout fallido'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('open-failing-checkout-guard')),
      );
      await tester.pumpAndSettle();
      unawaited(navigatorKey.currentState!.maybePop());
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('website-draft-navigation-confirm')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Checkout con guard fallido'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey<String>('storefront-navigation-guard-error'),
        ),
        findsOneWidget,
      );
      expect(provider.hasPageDraftChanges, isTrue);
      expect(
        provider.blocks.single['block_data'],
        {'title': 'Draft'},
      );
      expect(checkoutGuard.hasNavigationPermit, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
