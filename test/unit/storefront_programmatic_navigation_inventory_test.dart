import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/public_store/widgets/public_store_layout.dart';

void main() {
  const guardedTargets = <String>[
    '/cuenta',
    '/checkout',
    '/cuenta/bicicletas',
    '/pedido/order-1',
  ];

  for (final target in guardedTargets) {
    testWidgets(
      'programmatic navigation to $target preserves or discards the page '
      'draft only after the canonical decision',
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
        addTearDown(provider.dispose);

        final router = GoRouter(
          initialLocation: '/origen',
          routes: [
            GoRoute(
              path: '/origen',
              builder: (context, state) => Scaffold(
                body: FilledButton(
                  key: const ValueKey('programmatic-navigation'),
                  onPressed: () =>
                      PublicStoreLayout.navigateToHref(context, target),
                  child: const Text('Navegar'),
                ),
              ),
            ),
            GoRoute(
              path: '/cuenta',
              builder: (context, state) =>
                  const Scaffold(body: Text('Cuenta')),
            ),
            GoRoute(
              path: '/checkout',
              builder: (context, state) =>
                  const Scaffold(body: Text('Checkout')),
            ),
            GoRoute(
              path: '/cuenta/bicicletas',
              builder: (context, state) =>
                  const Scaffold(body: Text('Bicicletas')),
            ),
            GoRoute(
              path: '/pedido/:id',
              builder: (context, state) =>
                  const Scaffold(body: Text('Confirmación')),
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

        await tester.tap(
          find.byKey(const ValueKey('programmatic-navigation')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Cambios sin guardar'), findsOneWidget);
        expect(router.routeInformationProvider.value.uri.path, '/origen');
        expect(provider.hasPageDraftChanges, isTrue);

        await tester.tap(
          find.byKey(const ValueKey('website-draft-navigation-cancel')),
        );
        await tester.pumpAndSettle();

        expect(router.routeInformationProvider.value.uri.path, '/origen');
        expect(provider.hasPageDraftChanges, isTrue);

        await tester.tap(
          find.byKey(const ValueKey('programmatic-navigation')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('website-draft-navigation-confirm')),
        );
        await tester.pumpAndSettle();

        expect(router.routeInformationProvider.value.uri.path, target);
        expect(provider.hasPageDraftChanges, isFalse);
        expect(
          provider.blocks.single['block_data'],
          {'title': 'Original'},
        );
      },
    );
  }

  test(
    'storefront consumers route programmatic document changes through the '
    'canonical navigation boundary',
    () {
      final root = Directory('lib/public_store');
      final directGo = RegExp(r'\b[A-Za-z_][A-Za-z0-9_]*\.go\s*\(');
      final bypasses = <String>[];

      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('/widgets/public_store_layout.dart')) {
          // This file implements the canonical boundary and owns its final
          // guarded GoRouter operation.
          continue;
        }

        final source = entity.readAsStringSync();
        if (directGo.hasMatch(source)) {
          bypasses.add(entity.path);
        }
      }

      expect(
        bypasses,
        isEmpty,
        reason:
            'Storefront pages/widgets must call the shared guarded navigation '
            'entry-point instead of invoking GoRouter.go directly.',
      );
    },
  );
}
