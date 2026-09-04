import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/models/product.dart';
import 'package:vinabike_erp/shared/widgets/smart_product_field.dart';

/// The row menu of a document line.
///
/// A line linked to a catalog product edits or inspects that product. A line
/// that only carries text — OCR wrote its name and «SKU: 23310» in the
/// description, nothing in the catalog matches — used to show the same menu
/// with a stub product whose id was empty, so «Editar artículo» opened
/// «Nuevo producto» over a uuid error. Now it offers the only honest action.
Product _product({required String id, String name = 'Cassette CS-HG200-8V'}) {
  final now = DateTime(2026, 9, 3);
  return Product(
    id: id,
    name: name,
    sku: id.isEmpty ? '' : '23310',
    price: 12990,
    cost: 9290,
    stockQuantity: 3,
    minStockLevel: 0,
    maxStockLevel: 0,
    description: null,
    imageUrl: null,
    imageUrls: const [],
    category: ProductCategory.other,
    specifications: const {},
    tags: const [],
    unit: ProductUnit.unit,
    weight: 0,
    trackStock: true,
    isActive: true,
    purchaseTreatment: PurchaseTreatment.inventory,
    createdAt: now,
    updatedAt: now,
  );
}

Widget _host(SmartProductField field) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 480, child: field),
    ),
  );
}

void main() {
  const menu = Key('smart-product-row-menu');

  testWidgets('a text-only line offers to create the catalog product',
      (tester) async {
    var created = 0;
    Product? edited;
    await tester.pumpWidget(_host(SmartProductField(
      onProductChanged: (_) {},
      initialData: ProductFieldData(
        product: _product(id: ''),
        productName: 'Cassette CS-HG200-8V',
        productSku: null,
        isCatalogProduct: false,
        description: 'SKU: 23310',
      ),
      onEditProduct: (p) => edited = p,
      onShowProductDetails: (_) {},
      onCreateCatalogProduct: () => created++,
    )));

    await tester.tap(find.byKey(menu));
    await tester.pumpAndSettle();
    expect(find.text('Crear en el catálogo'), findsOneWidget);
    expect(find.text('Editar artículo'), findsNothing);
    expect(find.text('Ver detalles del artículo'), findsNothing);

    await tester.tap(find.text('Crear en el catálogo'));
    await tester.pumpAndSettle();
    expect(created, 1);
    expect(edited, isNull);
  });

  testWidgets('a text-only line without a create handler shows no menu',
      (tester) async {
    await tester.pumpWidget(_host(SmartProductField(
      onProductChanged: (_) {},
      initialData: ProductFieldData(
        product: _product(id: ''),
        productName: 'Cassette CS-HG200-8V',
        isCatalogProduct: false,
      ),
      onEditProduct: (_) {},
      onShowProductDetails: (_) {},
    )));
    expect(find.byKey(menu), findsNothing);
  });

  testWidgets('a linked line edits and inspects its product', (tester) async {
    Product? edited;
    Product? inspected;
    var created = 0;
    final product = _product(id: 'p-1');
    await tester.pumpWidget(_host(SmartProductField(
      onProductChanged: (_) {},
      initialData: ProductFieldData(
        product: product,
        productName: product.name,
        productSku: product.sku,
      ),
      onEditProduct: (p) => edited = p,
      onShowProductDetails: (p) => inspected = p,
      onCreateCatalogProduct: () => created++,
    )));

    await tester.tap(find.byKey(menu));
    await tester.pumpAndSettle();
    expect(find.text('Editar artículo'), findsOneWidget);
    expect(find.text('Ver detalles del artículo'), findsOneWidget);
    expect(find.text('Crear en el catálogo'), findsNothing);

    await tester.tap(find.text('Editar artículo'));
    await tester.pumpAndSettle();
    expect(edited?.id, 'p-1');

    await tester.tap(find.byKey(menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver detalles del artículo'));
    await tester.pumpAndSettle();
    expect(inspected?.id, 'p-1');
    expect(created, 0);
  });

  testWidgets('linking the line to a product re-syncs the card',
      (tester) async {
    Widget build(ProductFieldData data) => _host(SmartProductField(
          key: const ValueKey('line'),
          onProductChanged: (_) {},
          initialData: data,
          onEditProduct: (_) {},
          onCreateCatalogProduct: () {},
        ));

    await tester.pumpWidget(build(ProductFieldData(
      product: _product(id: ''),
      productName: 'Cassette CS-HG200-8V',
      isCatalogProduct: false,
    )));
    expect(find.text('Cassette CS-HG200-8V'), findsOneWidget);

    final linked = _product(id: 'p-9', name: 'Cassette Shimano CS-HG200 8v');
    await tester.pumpWidget(build(ProductFieldData(
      product: linked,
      productName: linked.name,
      productSku: linked.sku,
    )));
    await tester.pump();
    expect(find.text('Cassette Shimano CS-HG200 8v'), findsOneWidget);
    expect(find.text('Cassette CS-HG200-8V'), findsNothing);

    await tester.tap(find.byKey(menu));
    await tester.pumpAndSettle();
    expect(find.text('Editar artículo'), findsOneWidget,
        reason: 'The same State must now treat the line as linked.');
  });
}
