import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/website/models/website_action.dart';
import 'package:vinabike_erp/modules/website/models/website_block_registry.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/website_action_editor.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_edit_section.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_chrome_geometry.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_panel.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/vb_segmented.dart';

void main() {
  WebsiteEditModeProvider providerFor(Map<String, dynamic> data) {
    final provider = WebsiteEditModeProvider()
      ..enterEditMode(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'products-block',
            'block_type': 'products',
            'block_data': data,
            'is_visible': true,
            'sort_order': 0,
          },
        ],
        const <String, dynamic>{},
      )
      ..selectBlock('products-block')
      ..setDevicePreviewMode(DevicePreviewMode.mobile)
      ..reportRenderedBlockViewport(
        'products-block',
        WebsiteViewport.mobile,
      );
    addTearDown(provider.dispose);
    return provider;
  }

  Map<String, dynamic> dataOf(WebsiteEditModeProvider provider) =>
      Map<String, dynamic>.from(provider.blocks.single['block_data'] as Map);

  Widget host(WebsiteEditModeProvider provider, {double width = 390}) {
    return MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.pacific,
        brightness: Brightness.dark,
      ),
      home: ChangeNotifierProvider<WebsiteEditModeProvider>.value(
        value: provider,
        child: WebsiteEditorChromeScope(
          editorWidth: width,
          canvasWidth: WebsiteEditorChromeGeometry.canvasWidthFor(width),
          child: Consumer<WebsiteEditModeProvider>(
            builder: (context, watched, _) => Scaffold(
              body: WebsiteBlockEditSurface(
                editProvider: watched,
                section: WebsiteBlockEditSection.content,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> openSection(WidgetTester tester, String title) async {
    final finder = find.text(title);
    expect(finder, findsOneWidget);
    await tester.tap(finder);
    await settle(tester);
  }

  testWidgets('Products custom controls expose 48pt touch targets and labels',
      (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = providerFor(<String, dynamic>{
      'title': 'Productos',
      'productSource': 'manual',
      'layout': 'grid',
      'productIds': <String>[],
      'itemsPerRow': 3,
      'maxProducts': 8,
      'showPrice': true,
      'showSku': false,
      'showBrand': false,
      'showViewAll': false,
    });

    await tester.pumpWidget(host(provider));
    await settle(tester);

    final source = find.byWidgetPredicate((widget) => widget is VbSegmented);
    expect(source, findsOneWidget);
    expect(tester.getSize(source).height, greaterThanOrEqualTo(48));

    final add = find.byKey(const Key('products-add-selection'));
    expect(add, findsOneWidget);
    await tester.ensureVisible(add);
    expect(tester.getSize(add).height, greaterThanOrEqualTo(48));
    expect(
      find.bySemanticsLabel(RegExp('Agregar productos')),
      findsOneWidget,
    );

    await tester.tap(add);
    await settle(tester);
    final stockFilter = find.byKey(const Key('products-stock-filter'));
    expect(stockFilter, findsOneWidget);
    expect(tester.getSize(stockFilter).height, greaterThanOrEqualTo(48));
    expect(
      find.bySemanticsLabel(RegExp('Solo productos con stock')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    semanticsHandle.dispose();
  });

  testWidgets('one maxProducts drag is exactly one undo transaction',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = providerFor(<String, dynamic>{
      'title': 'Productos',
      'productSource': 'featured',
      'layout': 'grid',
      'itemsPerRow': 3,
      'maxProducts': 8,
      'showPrice': true,
      'showViewAll': false,
    });

    await tester.pumpWidget(host(provider));
    await settle(tester);
    await openSection(tester, 'Diseño de productos');

    final sliderHost = find.byKey(const Key('products-max-products-slider'));
    final slider =
        find.descendant(of: sliderHost, matching: find.byType(Slider));
    expect(slider, findsOneWidget);
    await tester.ensureVisible(slider);
    await tester.drag(slider, const Offset(120, 0));
    await settle(tester);

    final changed = dataOf(provider)['maxProducts'];
    expect(changed, isNot(8));
    expect(provider.hasUnsavedChanges, isTrue);

    provider.undo();
    await settle(tester);
    expect(dataOf(provider)['maxProducts'], 8,
        reason: 'one undo must revert the whole slider gesture');

    provider.redo();
    await settle(tester);
    expect(dataOf(provider)['maxProducts'], changed);
    expect(tester.takeException(), isNull);
  });

  testWidgets('maxProducts cancel keeps draft local with zero document writes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = providerFor(<String, dynamic>{
      'title': 'Productos',
      'productSource': 'featured',
      'layout': 'grid',
      'itemsPerRow': 3,
      'maxProducts': 8,
      'showPrice': true,
      'showViewAll': false,
    });

    await tester.pumpWidget(host(provider));
    await settle(tester);
    await openSection(tester, 'Diseño de productos');

    final sliderHost = find.byKey(const Key('products-max-products-slider'));
    final sliderFinder =
        find.descendant(of: sliderHost, matching: find.byType(Slider));
    final slider = tester.widget<Slider>(sliderFinder);
    slider.onChangeStart!(8);
    slider.onChanged!(14);
    await tester.pump();

    final listener = tester.widget<Listener>(
      find.descendant(of: sliderHost, matching: find.byType(Listener)),
    );
    listener.onPointerCancel!(const PointerCancelEvent());
    await tester.pump();

    expect(dataOf(provider)['maxProducts'], 8);
    expect(provider.hasUnsavedChanges, isFalse);
    expect(provider.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale maxProducts end is rejected with zero extra history',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = providerFor(<String, dynamic>{
      'title': 'Productos',
      'productSource': 'featured',
      'layout': 'grid',
      'itemsPerRow': 3,
      'maxProducts': 8,
      'showPrice': true,
      'showViewAll': false,
    });

    await tester.pumpWidget(host(provider));
    await settle(tester);
    await openSection(tester, 'Diseño de productos');

    final slider = tester.widget<Slider>(
      find.descendant(
        of: find.byKey(const Key('products-max-products-slider')),
        matching: find.byType(Slider),
      ),
    );
    slider.onChangeStart!(8);
    slider.onChanged!(14);
    provider.updateBlockData('products-block', 'title', 'Cambio externo');
    slider.onChangeEnd!(14);
    await settle(tester);

    expect(dataOf(provider)['title'], 'Cambio externo');
    expect(dataOf(provider)['maxProducts'], 8,
        reason: 'the drag lease predates the external document epoch');
    provider.undo();
    expect(dataOf(provider)['title'], 'Productos');
    expect(provider.canUndo, isFalse,
        reason: 'the stale slider end created no second history entry');
    expect(tester.takeException(), isNull);
  });

  testWidgets('one rendered source selector accepts only its first callback',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = providerFor(<String, dynamic>{
      'title': 'Productos',
      'productSource': 'featured',
      'layout': 'grid',
      'itemsPerRow': 3,
      'maxProducts': 8,
      'showPrice': true,
      'showViewAll': false,
    });

    await tester.pumpWidget(host(provider));
    await settle(tester);
    final source = tester.widget<VbSegmented<String>>(
      find.byWidgetPredicate(
        (widget) =>
            widget is VbSegmented<String> &&
            widget.groupLabel == 'Fuente de productos',
      ),
    );

    source.onChanged!('manual');
    source.onChanged!('newest');
    await settle(tester);

    expect(dataOf(provider)['productSource'], 'manual');
    provider.undo();
    expect(dataOf(provider)['productSource'], 'featured');
    expect(provider.canUndo, isFalse,
        reason: 'the second pre-rebuild callback consumed no new authority');
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unresolved manual ID stays visible and removable in one undo',
      (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const missingId = 'missing-product-id';
    final provider = providerFor(<String, dynamic>{
      'title': 'Productos',
      'productSource': 'manual',
      'layout': 'grid',
      'productIds': <String>[missingId],
      'selectedProducts': <String>[missingId],
      'itemsPerRow': 3,
      'maxProducts': 8,
      'showPrice': true,
      'showViewAll': false,
    });

    await tester.pumpWidget(host(provider));
    await settle(tester);

    expect(
      find.byKey(const Key('products-missing-selection-$missingId')),
      findsOneWidget,
    );
    expect(find.text('Producto no disponible'), findsOneWidget);
    final remove =
        find.byKey(const Key('products-remove-selection-$missingId'));
    expect(remove, findsOneWidget);
    await tester.ensureVisible(remove);
    expect(tester.getSize(remove).height, greaterThanOrEqualTo(48));
    expect(
      find.bySemanticsLabel(RegExp('Quitar producto no disponible')),
      findsOneWidget,
    );

    await tester.tap(remove);
    await settle(tester);
    expect(dataOf(provider)['productIds'], isEmpty);
    expect(dataOf(provider)['selectedProducts'], isEmpty);

    provider.undo();
    await settle(tester);
    expect(dataOf(provider)['productIds'], <String>[missingId]);
    expect(dataOf(provider)['selectedProducts'], <String>[missingId]);
    expect(tester.takeException(), isNull);
    semanticsHandle.dispose();
  });

  testWidgets('picker result captured before await cannot redirect to new page',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = providerFor(<String, dynamic>{
      'title': 'Página anterior',
      'productSource': 'manual',
      'productIds': <String>['old'],
      'selectedProducts': <String>['old'],
      'layout': 'grid',
      'itemsPerRow': 3,
      'maxProducts': 8,
      'showPrice': true,
      'showViewAll': false,
    });

    await tester.pumpWidget(host(provider));
    await settle(tester);
    final add = find.byKey(const Key('products-add-selection'));
    await tester.ensureVisible(add);
    await tester.tap(add);
    await settle(tester);
    expect(find.byType(Dialog), findsOneWidget);

    provider
      ..enterEditMode(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'products-block',
            'block_type': 'products',
            'block_data': <String, dynamic>{
              'title': 'Página nueva',
              'productSource': 'manual',
              'productIds': <String>['fresh'],
              'selectedProducts': <String>['fresh'],
              'layout': 'grid',
              'itemsPerRow': 3,
              'maxProducts': 8,
              'showPrice': true,
              'showViewAll': false,
            },
            'is_visible': true,
            'sort_order': 0,
          },
        ],
        const <String, dynamic>{},
        pageId: 'page-new',
        pageSlug: 'nueva',
      )
      ..selectBlock('products-block')
      ..setDevicePreviewMode(DevicePreviewMode.mobile)
      ..reportRenderedBlockViewport(
        'products-block',
        WebsiteViewport.mobile,
      );

    Navigator.of(tester.element(find.byType(Dialog))).pop(<String>['late']);
    await settle(tester);

    expect(dataOf(provider)['title'], 'Página nueva');
    expect(dataOf(provider)['productIds'], <String>['fresh']);
    expect(dataOf(provider)['selectedProducts'], <String>['fresh']);
    expect(provider.hasUnsavedChanges, isFalse);
    expect(provider.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('view-all action mirrors commit atomically in one undo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final originalAction = <String, dynamic>{
      'type': 'navigate',
      'label': 'Ver originales',
      'to': '/originales',
      'variant': 'outline',
    };
    final provider = providerFor(<String, dynamic>{
      'title': 'Productos',
      'productSource': 'featured',
      'layout': 'grid',
      'itemsPerRow': 3,
      'maxProducts': 8,
      'showPrice': true,
      'showViewAll': true,
      'viewAllText': 'Ver originales',
      'viewAllLink': '/originales',
      'actionVariant': 'outline',
      'actions': <Map<String, dynamic>>[originalAction],
    });

    await tester.pumpWidget(host(provider, width: 390));
    await settle(tester);
    await openSection(tester, 'Acción “Ver todos”');

    final editor = tester.widget<WebsiteActionEditor>(
      find.byType(WebsiteActionEditor),
    );
    const next = WebsiteActionValue(
      label: 'Explorar todo',
      href: '/catalogo',
      variant: WebsiteActionVariant.filled,
    );
    editor.onChanged(next);
    await settle(tester);

    final changed = dataOf(provider);
    expect(changed['viewAllText'], 'Explorar todo');
    expect(changed['viewAllLink'], '/catalogo');
    expect(changed['actionVariant'], 'filled');
    final resolved = WebsiteActionValue.resolvePrimary(
      changed,
      labelKeys: const <String>['viewAllText'],
      hrefKeys: const <String>['viewAllLink'],
    );
    expect(resolved?.label, next.label);
    expect(resolved?.href, next.href);
    expect(resolved?.variant, next.variant);

    provider.undo();
    final restored = dataOf(provider);
    expect(restored['viewAllText'], 'Ver originales');
    expect(restored['viewAllLink'], '/originales');
    expect(restored['actionVariant'], 'outline');
    expect(restored['actions'], <Map<String, dynamic>>[originalAction]);
    expect(provider.canUndo, isFalse,
        reason: 'all aliases and structured actions shared one command');
    expect(tester.takeException(), isNull);
  });

  test('selection mirror uses one exact lease, command, and undo', () {
    final provider = providerFor(<String, dynamic>{
      'productSource': 'manual',
      'productIds': <String>['old'],
      'selectedProducts': <String>['old'],
    });

    final lease = provider.captureInlineMutationLease(
      WebsiteInlineManipulationTarget(
        blockId: 'products-block',
        owner: const WebsiteInlineBlockOwner(),
        viewport: WebsiteViewport.mobile,
        properties: <WebsiteInlineManipulationProperty>[
          WebsiteInlineManipulationProperty(
            canonicalKey: WebsiteProductsBlockContract.productIdsKey,
            policy: WebsiteResponsivePropertyPolicy.sharedOnly,
            sharedCompanionKeys: const <String>[
              WebsiteProductsBlockContract.legacySelectedProductsKey,
            ],
          ),
        ],
      ),
    );
    expect(lease, isNotNull);
    final normalized = WebsiteProductsBlockContract.selectionWrite(
      <Object?>['new', 'new', 7],
    )[WebsiteProductsBlockContract.productIdsKey] as List<String>;
    expect(
      provider.commitInlineMutation(
        lease!,
        <String, Object?>{
          WebsiteProductsBlockContract.productIdsKey: normalized,
        },
      ),
      WebsiteInlineMutationResult.committed,
    );
    expect(dataOf(provider)['productIds'], <String>['new', '7']);
    expect(dataOf(provider)['selectedProducts'], <String>['new', '7']);

    provider.undo();
    expect(dataOf(provider)['productIds'], <String>['old']);
    expect(dataOf(provider)['selectedProducts'], <String>['old']);
  });
}
