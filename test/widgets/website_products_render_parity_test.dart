import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/website/models/website_block_type.dart';
import 'package:vinabike_erp/modules/website/models/website_page_composition.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_projection.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/modules/website/widgets/deferred_editable_block_renderer.dart';
import 'package:vinabike_erp/modules/website/widgets/premium_product_card.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_content_presenters.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_renderer.dart';
import 'package:vinabike_erp/public_store/services/public_inventory_service.dart';
import 'package:vinabike_erp/public_store/widgets/page_composition.dart';
import 'package:vinabike_erp/shared/models/product.dart';
import 'package:vinabike_erp/shared/models/public_product_visibility_policy.dart';
import 'package:vinabike_erp/shared/utils/chilean_utils.dart';

enum _ProductsSurface { edit, preview, public }

class _PolicyPublicInventoryService extends PublicInventoryService {
  _PolicyPublicInventoryService({required this.eligibleProduct});

  final Product eligibleProduct;
  final List<List<String>?> requestedProductIds = <List<String>?>[];
  final List<bool> requestedOnlyInStock = <bool>[];

  @override
  Future<PublicProductPage> getProductPageForTenant({
    required String tenantId,
    List<String>? categoryIds,
    List<String>? productIds,
    String? sku,
    String? searchQuery,
    ProductType? productType,
    PublicProductVisibilityPolicy? policy,
    bool onlyInStock = true,
    bool applyAvailabilityFacet = false,
    List<String>? brandIds,
    double? minPrice,
    double? maxPrice,
    String sortBy = 'name',
    int limit = 20,
    int offset = 0,
  }) async {
    requestedProductIds.add(
      productIds == null ? null : List<String>.unmodifiable(productIds),
    );
    requestedOnlyInStock.add(onlyInStock);
    return PublicProductPage(
      products: <Product>[eligibleProduct],
      totalCount: 1,
    );
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    WebsiteService.setSharedPreferences(await SharedPreferences.getInstance());
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'products-contract-test-key',
    );
  });

  final product = Product(
    id: 'product-contract-1',
    name: 'Manubrio Turbine',
    sku: 'RF-01',
    brand: 'RaceFace',
    price: 12990,
    cost: 0,
    stockQuantity: 4,
    category: ProductCategory.other,
    createdAt: DateTime.utc(2026, 8, 9),
    updatedAt: DateTime.utc(2026, 8, 9),
  );

  const document = <String, dynamic>{
    'title': 'Elegidos para ti',
    'subtitle': 'Componentes listos para tu próxima salida',
    'productSource': 'featured',
    'layout': 'carousel',
    'itemsPerRow': 4,
    'maxProducts': 8,
    'showPrice': true,
    'showSku': false,
    'showBrand': false,
    'showViewAll': false,
    'responsive': <String, dynamic>{
      'mobile': <String, dynamic>{
        'layout': 'grid',
        'showPrice': false,
        'showSku': true,
        'showBrand': true,
      },
      'tablet': <String, dynamic>{'showBrand': true},
    },
  };

  Map<String, dynamic> reloadedProjection(WebsiteViewport viewport) {
    final reloaded = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(document)) as Map,
    );
    return WebsiteResponsiveBlockProjection.project(
      type: WebsiteBlockType.products,
      data: reloaded,
      viewport: viewport,
    );
  }

  Widget host({
    required Map<String, dynamic> data,
    required double width,
    required _ProductsSurface surface,
    required Product product,
    void Function(String route)? onNavigate,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<PublicInventoryService>(
          create: (_) => PublicInventoryService(),
        ),
        ChangeNotifierProvider<WebsiteService>(
          create: (_) => WebsiteService(),
        ),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 1200),
            disableAnimations: true,
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Builder(
                builder: (context) => WebsiteBlockRenderer.build(
                  context: context,
                  blockType: 'products',
                  data: data,
                  effectiveViewport:
                      WebsiteResponsiveDataCodec.viewportForDocumentWidth(
                    data,
                    width,
                  ),
                  primaryColor: Colors.blue,
                  accentColor: Colors.teal,
                  featuredProducts: <Product>[product],
                  previewMode: surface != _ProductsSurface.public,
                  contentPresenters: surface == _ProductsSurface.edit
                      ? const WebsiteBlockContentPresenters()
                      : null,
                  onNavigate: onNavigate ?? (_) {},
                  isNavigationEligible: (_) => true,
                  tenantId: 'tenant-products-contract',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget compositionHost({
    required Map<String, dynamic> data,
    required double width,
    required _ProductsSurface surface,
    required PublicInventoryService inventoryService,
  }) {
    final block = <String, dynamic>{
      'id': 'products-policy-block',
      'block_type': 'products',
      'order_index': 0,
      'is_visible': true,
      'block_data': data,
    };
    final mode = switch (surface) {
      _ProductsSurface.edit => WebsitePageCompositionMode.edit,
      _ProductsSurface.preview => WebsitePageCompositionMode.preview,
      _ProductsSurface.public => WebsitePageCompositionMode.public,
    };
    final composition = WebsitePageComposition.project(
      blocks: <Map<String, dynamic>>[block],
      mode: mode,
      breakpoint: WebsiteViewport.fromLogicalWidth(width).wireName,
      logicalWidth: width,
    );
    Widget app = MultiProvider(
      providers: [
        ChangeNotifierProvider<PublicInventoryService>.value(
          value: inventoryService,
        ),
        ChangeNotifierProvider<WebsiteService>(
          create: (_) => WebsiteService(),
        ),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 1200),
            disableAnimations: true,
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: width,
                child: PageComposition(
                  composition: composition,
                  primaryColor: Colors.blue,
                  accentColor: Colors.teal,
                  textColor: Colors.black,
                  containerPadding: 24,
                  tenantId: 'tenant-products-contract',
                  onNavigate: (_) {},
                  isNavigationEligible: (_) => true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (surface == _ProductsSurface.edit) {
      app = ChangeNotifierProvider<WebsiteEditModeProvider>(
        create: (_) => WebsiteEditModeProvider()
          ..enterEditMode(
            <Map<String, dynamic>>[block],
            const <String, dynamic>{},
          )
          ..selectBlock('products-policy-block'),
        child: app,
      );
    }
    return app;
  }

  Future<PremiumProductCard> settleProduct(
    WidgetTester tester,
    String productId,
  ) async {
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.pump(const Duration(milliseconds: 30));
      final finder = find.byType(PremiumProductCard);
      if (finder.evaluate().isEmpty) continue;
      final card = tester.widget<PremiumProductCard>(finder.first);
      if (card.productId == productId) return card;
    }
    fail('Products renderer never replaced its loading card with real data.');
  }

  testWidgets(
      'Edit, Preview, save/reload and Public keep Products parity at 390/834/1440',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final (
          viewport,
          width,
          expectedLayout,
          expectedPrice,
          expectedSku,
          expectedBrand
        ) in const <(
      WebsiteViewport,
      double,
      String,
      bool,
      bool,
      bool,
    )>[
      (WebsiteViewport.mobile, 390, 'grid', false, true, true),
      (WebsiteViewport.tablet, 834, 'carousel', true, false, true),
      (WebsiteViewport.desktop, 1440, 'carousel', true, false, false),
    ]) {
      await tester.binding.setSurfaceSize(Size(width, 1200));
      final projected = reloadedProjection(viewport);

      for (final surface in _ProductsSurface.values) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          host(
            data: projected,
            width: width,
            surface: surface,
            product: product,
          ),
        );
        final card = await settleProduct(tester, product.id);

        expect(
          find.text('COMPONENTES LISTOS PARA TU PRÓXIMA SALIDA'),
          findsNothing,
          reason: 'subtitle keeps authored case; $surface @ $width',
        );
        expect(
          find.text('Componentes listos para tu próxima salida'),
          findsOneWidget,
          reason: '$surface @ $width',
        );
        expect(card.showPrice, expectedPrice, reason: '$surface @ $width');
        expect(card.showSku, expectedSku, reason: '$surface @ $width');
        expect(card.showBrand, expectedBrand, reason: '$surface @ $width');
        expect(
          card.interactionsEnabled,
          surface != _ProductsSurface.edit,
          reason: '$surface @ $width',
        );

        if (expectedLayout == 'grid') {
          expect(find.byType(GridView), findsOneWidget,
              reason: '$surface @ $width');
          expect(find.byType(PageView), findsNothing,
              reason: 'mobile grid must not be forced to carousel');
        } else {
          expect(find.byType(GridView), findsNothing,
              reason: '$surface @ $width');
          expect(find.byType(PageView), findsNothing,
              reason: 'tablet/desktop use the wide carousel consumer');
        }

        expect(
          find.text('RACEFACE'),
          expectedBrand ? findsOneWidget : findsNothing,
          reason: '$surface @ $width',
        );
        expect(
          find.text('SKU: RF-01'),
          expectedSku ? findsOneWidget : findsNothing,
          reason: '$surface @ $width',
        );
        expect(
          find.text(ChileanUtils.formatCurrency(product.price)),
          expectedPrice ? findsOneWidget : findsNothing,
          reason: '$surface @ $width',
        );
        expect(tester.takeException(), isNull, reason: '$surface @ $width');
      }
    }
  });

  testWidgets('grid density follows the canonical viewport at 451/599/600',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const data = <String, dynamic>{
      'title': 'Productos',
      'productSource': 'featured',
      'layout': 'grid',
      'itemsPerRow': 4,
      'maxProducts': 4,
      'showPrice': true,
      'showViewAll': false,
      'responsive': <String, dynamic>{'version': 2},
    };

    for (final (width, expectedColumns) in const <(double, int)>[
      (451, 1),
      (599, 1),
      (600, 2),
    ]) {
      await tester.binding.setSurfaceSize(Size(width, 1200));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        host(
          data: data,
          width: width,
          surface: _ProductsSurface.preview,
          product: product,
        ),
      );
      await settleProduct(tester, product.id);

      final grid = tester.widget<GridView>(find.byType(GridView));
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, expectedColumns, reason: 'width=$width');
      expect(tester.takeException(), isNull, reason: 'width=$width');
    }
  });

  testWidgets(
      'Edit Preview save/reload and Public share public policy for manual IDs',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    final inventory = _PolicyPublicInventoryService(eligibleProduct: product);
    final selectedIds = <String>[
      product.id,
      'unpublished-product',
      'hidden-product',
      'out-of-stock-product',
      'rule-blocked-product',
    ];
    final reloaded = Map<String, dynamic>.from(
      jsonDecode(
        jsonEncode(<String, dynamic>{
          'title': 'Selección manual',
          'productSource': 'manual',
          'productIds': selectedIds,
          'selectedProducts': selectedIds,
          'layout': 'grid',
          'itemsPerRow': 3,
          'maxProducts': 8,
          'showPrice': true,
          'showViewAll': false,
          'responsive': <String, dynamic>{'version': 2},
        }),
      ) as Map,
    );

    for (final surface in _ProductsSurface.values) {
      if (surface == _ProductsSurface.edit) {
        await tester.runAsync(DeferredEditableBlockRenderer.preload);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        compositionHost(
          data: reloaded,
          width: 390,
          surface: surface,
          inventoryService: inventory,
        ),
      );
      final card = await settleProduct(tester, product.id);
      expect(card.productId, product.id, reason: '$surface');
      expect(find.byType(PremiumProductCard), findsOneWidget,
          reason: '$surface');
      expect(tester.takeException(), isNull, reason: '$surface');
    }

    expect(inventory.requestedProductIds, hasLength(3));
    for (final request in inventory.requestedProductIds) {
      expect(request, selectedIds);
    }
    expect(inventory.requestedOnlyInStock, everyElement(isTrue));
  });

  testWidgets('PremiumProductCard exposes one full touch/semantic action',
      (tester) async {
    final routes = <String>[];
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            height: 320,
            child: PremiumProductCard(
              productId: product.id,
              productSku: product.sku,
              productBrand: product.brand,
              name: product.name,
              price: product.price,
              showPrice: true,
              showSku: true,
              showBrand: true,
              interactionsEnabled: true,
              onNavigate: routes.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final cardFinder = find.byType(PremiumProductCard);
    final size = tester.getSize(cardFinder);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));

    final semantics = tester.getSemantics(cardFinder);
    expect(semantics.label, contains('Manubrio Turbine'));
    expect(semantics.label, contains('Marca RaceFace'));
    expect(semantics.label, contains('SKU RF-01'));
    expect(
        semantics.label, contains(ChileanUtils.formatCurrency(product.price)));
    expect(semantics.flagsCollection.isButton, isTrue);

    await tester.tap(cardFinder);
    expect(routes, hasLength(1));
    expect(routes.single, contains('manubrio-turbine'));
  });
}
