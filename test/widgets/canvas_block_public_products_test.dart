import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/modules/website/widgets/canvas_block.dart';
import 'package:vinabike_erp/public_store/services/public_inventory_service.dart';
import 'package:vinabike_erp/shared/models/product.dart';
import 'package:vinabike_erp/shared/models/public_product_visibility_policy.dart';

/// The catalog the canvas asks for, and how.
class _Inventory extends PublicInventoryService {
  _Inventory(this.catalog);

  final List<Product> catalog;
  final List<({List<String>? ids, String sortBy, bool inStock, int limit})>
      asked = [];

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
    Map<String, Iterable<String>>? specFilters,
    double? minPrice,
    double? maxPrice,
    String sortBy = 'name',
    int limit = 20,
    int offset = 0,
  }) async {
    asked.add(
      (ids: productIds, sortBy: sortBy, inStock: onlyInStock, limit: limit),
    );
    final products = productIds == null
        ? catalog.take(limit).toList()
        : [
            for (final product in catalog)
              if (productIds.contains(product.id)) product,
          ];
    return PublicProductPage(products: products, totalCount: products.length);
  }
}

Product _product(String id, String name) => Product(
      id: id,
      name: name,
      sku: id.toUpperCase(),
      price: 12990,
      cost: 0,
      stockQuantity: 4,
      category: ProductCategory.other,
      imageUrl: 'https://example.invalid/$id.jpg',
      createdAt: DateTime.utc(2026, 10, 7),
      updatedAt: DateTime.utc(2026, 10, 7),
    );

/// The canvas reads its product layers as the visitor's store does (the
/// public read, in stock, by SKU), as the products block and the HTML
/// storefront: until 2026-10-07 it read `products` directly, without stock,
/// and its cards linked by id.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    WebsiteService.setSharedPreferences(await SharedPreferences.getInstance());
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'canvas-products-test-key',
    );
  });

  testWidgets(
      'cards, the newest and a product photo come from the public '
      'read', (tester) async {
    final inventory = _Inventory([
      _product('p3', 'Luz'),
      _product('p1', 'Casco'),
      _product('p2', 'Rueda'),
    ]);
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PublicInventoryService>.value(
            value: inventory,
          ),
          ChangeNotifierProvider<WebsiteService>(
            create: (_) => WebsiteService(),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CanvasBlock(
                tenantId: 'tenant-canvas-products',
                editable: false,
                accentColor: Colors.teal,
                data: {
                  'canvasResponsiveVersion': 2,
                  'blockHeight': 1400.0,
                  'heightMode': 'fixed',
                  'elements': [
                    {
                      'id': 'c1',
                      'type': 'product',
                      'productId': 'p1',
                      'x': 0,
                      'y': 0,
                      'w': 300,
                      'h': 400,
                    },
                    {
                      'id': 'g1',
                      'type': 'productsGallery',
                      'maxProducts': 2,
                      'columns': 2,
                      'x': 0,
                      'y': 420,
                      'w': 620,
                      'h': 100,
                    },
                    {
                      'id': 'i1',
                      'type': 'image',
                      'productId': 'p2',
                      'imageUrl': 'https://example.invalid/own.jpg',
                      'x': 640,
                      'y': 0,
                      'w': 200,
                      'h': 200,
                    },
                  ],
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final byIds = inventory.asked.where((ask) => ask.ids != null).toList();
    expect(byIds, isNotEmpty);
    expect(byIds.every((ask) => ask.inStock), isTrue);
    expect(byIds.expand((ask) => ask.ids!).toSet(), {'p1', 'p2'});
    final newest = inventory.asked.singleWhere((ask) => ask.ids == null);
    expect(newest.sortBy, 'newest');
    expect(newest.inStock, isTrue);
    expect(newest.limit, 2);

    // The card and the gallery's two newest (Luz and Casco).
    expect(find.text('CASCO'), findsNWidgets(2));
    expect(find.text('LUZ'), findsOneWidget);
    // The photo is the product's public one, not the layer's own.
    final photos = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .whereType<NetworkImage>()
        .map((image) => image.url);
    expect(photos, contains('https://example.invalid/p2.jpg'));
    expect(photos, isNot(contains('https://example.invalid/own.jpg')));
  });
}
