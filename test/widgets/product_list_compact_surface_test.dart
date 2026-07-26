import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/widgets/product_list_compact_surface.dart';
import 'package:vinabike_erp/shared/utils/responsive_viewport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpCompactSurface(
    WidgetTester tester, {
    required double width,
    double height = 824,
    double textScale = 1.3,
    VoidCallback? onOpen,
    ValueChanged<String>? onActionSelected,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, height));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final searchController = TextEditingController(text: 'cadena');
    addTearDown(searchController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, height),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: CompactInventoryCommandHeader(
                    title: 'Productos',
                    countLabel: '128 productos',
                    onMore: () {},
                    onNew: () {},
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: CompactInventorySearchToolbar(
                    controller: searchController,
                    hintText: 'Buscar productos...',
                    hasActiveFilters: true,
                    onChanged: (_) {},
                    onClear: () {},
                    onOpenFilters: () {},
                  ),
                ),
                CompactInventoryProductRow(
                  name:
                      'Cadena profesional de once velocidades con nombre largo',
                  sku: 'SKU-MOBILE-001',
                  secondaryLabel: 'Shimano · Transmisión',
                  stockLabel: '12 + parcial',
                  stockColor: const Color(0xFFC65D08),
                  priceLabel: r'$124.990',
                  costLabel: r'$87.450',
                  isSet: true,
                  leading: const ColoredBox(
                    color: Color(0xFFE7EEF7),
                    child: Icon(Icons.inventory_2_outlined),
                  ),
                  onOpen: onOpen ?? () {},
                  onActionSelected: onActionSelected ?? (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  for (final width in [384.0, 599.0, 600.0, 899.0]) {
    testWidgets(
      'compact inventory surface reflows without overflow at ${width}px',
      (tester) async {
        await pumpCompactSurface(tester, width: width);

        expect(find.byType(TextField), findsOneWidget);
        expect(
          tester
              .getSize(
                find.byKey(
                  const ValueKey('inventory-compact-search'),
                ),
              )
              .height,
          greaterThanOrEqualTo(48),
        );
        for (final key in const [
          'inventory-compact-more-actions',
          'inventory-compact-new',
          'inventory-compact-filters',
          'inventory-compact-edit',
          'inventory-compact-more',
        ]) {
          final size = tester.getSize(find.byKey(ValueKey(key)));
          expect(
            size.width,
            greaterThanOrEqualTo(48),
            reason: '$key must remain at least 48px wide at $width',
          );
          expect(
            size.height,
            greaterThanOrEqualTo(48),
            reason: '$key must remain at least 48px tall at $width',
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final entry in const [
    (width: 599.0, expected: 'compact'),
    (width: 600.0, expected: 'compact'),
    (width: 899.0, expected: 'compact'),
    (width: 900.0, expected: 'desktop'),
    (width: 1440.0, expected: 'desktop'),
  ]) {
    testWidgets(
      'inventory breakpoint is ${entry.expected} at ${entry.width}px',
      (tester) async {
        await tester.binding.setSurfaceSize(
          Size(entry.width, entry.width == 1440 ? 900 : 824),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(
                  entry.width,
                  entry.width == 1440 ? 900 : 824,
                ),
              ),
              child: Builder(
                builder: (context) => Text(
                  ResponsiveViewport.usesCompactShell(context)
                      ? 'compact'
                      : 'desktop',
                ),
              ),
            ),
          ),
        );

        expect(find.text(entry.expected), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('row tap, edit, and More expose the canonical callbacks',
      (tester) async {
    var openCount = 0;
    String? selectedAction;
    await pumpCompactSurface(
      tester,
      width: 384,
      onOpen: () => openCount += 1,
      onActionSelected: (action) => selectedAction = action,
    );

    await tester.tap(
      find.byKey(const ValueKey('inventory-compact-row-open')),
    );
    await tester.pump();
    expect(openCount, 1);

    await tester.tap(
      find.byKey(const ValueKey('inventory-compact-edit')),
    );
    await tester.pump();
    expect(openCount, 2);

    await tester.tap(
      find.byKey(const ValueKey('inventory-compact-more')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Abrir ficha'), findsOneWidget);
    expect(find.text('Eliminar'), findsOneWidget);

    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    expect(selectedAction, 'delete');
    expect(tester.takeException(), isNull);
  });

  test(
    'mobile row opens ProductForm and preserves query and scroll on return',
    () {
      final pageSource = File(
        'lib/modules/inventory/pages/product_list_page.dart',
      ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
      final routerSource = File(
        'lib/shared/routes/app_router.dart',
      ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');

      expect(
        pageSource,
        contains(
          "onOpen: () => _handleProductAction('edit', product)",
        ),
      );
      expect(
        pageSource,
        contains(
          'controller: _tableScrollController, '
          'keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag',
        ),
      );

      final saveIndex = pageSource.indexOf('_saveCurrentState();');
      final pushIndex = pageSource.indexOf(
        "context.push('\$_catalogBaseRoute/\${product.id}/edit')",
        saveIndex,
      );
      final restoreIndex =
          pageSource.indexOf('_restoreSavedState();', pushIndex);
      final preserveIndex =
          pageSource.indexOf('preserveState: true', restoreIndex);
      expect(saveIndex, greaterThanOrEqualTo(0));
      expect(pushIndex, greaterThan(saveIndex));
      expect(restoreIndex, greaterThan(pushIndex));
      expect(preserveIndex, greaterThan(restoreIndex));

      expect(
        routerSource,
        contains(
          "path: ':id/edit', pageBuilder: (context, state) { "
          "final id = state.pathParameters['id']!;",
        ),
      );
      expect(
        routerSource,
        contains('erp.ProductFormPage( productId: id, lockProductType: true'),
      );
    },
  );
}
