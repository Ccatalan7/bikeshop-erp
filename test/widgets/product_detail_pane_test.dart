import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/inventory/models/inventory_models.dart';
import 'package:vinabike_erp/modules/inventory/utils/product_margin.dart';
import 'package:vinabike_erp/modules/inventory/utils/product_set_inventory_projection.dart';
import 'package:vinabike_erp/modules/inventory/widgets/product_detail_pane.dart';
import 'package:vinabike_erp/modules/inventory/widgets/product_image_viewer.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/vb_skeleton.dart';
import 'package:vinabike_erp/shared/widgets/vb_status_badge.dart';
import 'package:vinabike_erp/shared/widgets/vb_sub_tabs.dart';

/// Panel de detalle del split pane de Productos.
///
/// Guarda lo que el panel le contesta al operador sin abrir la ficha: los
/// códigos (y que se copian al tocar), el margen sobre el costo con IVA, los
/// canales, el estado
/// de stock derivado del porqué, los filtros por marca/categoría/proveedor, el
/// visor de imagen y la ficha hidratada.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Product product({
    String id = 'p1',
    String name = 'Noodle Para Cable Alumin V-Brake 90°',
    String sku = '2000000113180',
    String? supplierCode = 'MKR-NDL-90',
    String? barcode = '7801234567890',
    double price = 600,
    double cost = 250,
    int inventoryQty = 0,
    int minStockLevel = 1,
    bool isActive = true,
    bool isPublished = true,
    bool isGoogleMerchant = false,
    bool isWhatsappCatalog = true,
    String? whatsappCatalogSyncStatus = 'customer_visible',
    String? imageUrl = 'http://127.0.0.1:1/noodle.png',
    List<String> additionalImages = const [],
    String? description,
    String? color,
    Map<String, String> specifications = const {},
    List<String> tags = const [],
    bool isSet = false,
    String? parentSetId,
    String? brandId = 'b1',
    String? categoryId = 'c1',
    String? supplierId = 's1',
  }) {
    return Product(
      id: id,
      tenantId: 't1',
      name: name,
      sku: sku,
      supplierCode: supplierCode,
      barcode: barcode,
      brand: 'MKR',
      brandId: brandId,
      categoryName: 'Noodles',
      categoryId: categoryId,
      supplierName: 'Andes Industrial',
      supplierId: supplierId,
      price: price,
      cost: cost,
      inventoryQty: inventoryQty,
      minStockLevel: minStockLevel,
      isActive: isActive,
      isPublished: isPublished,
      isGoogleMerchant: isGoogleMerchant,
      isWhatsappCatalog: isWhatsappCatalog,
      whatsappCatalogSyncStatus: whatsappCatalogSyncStatus,
      imageUrl: imageUrl,
      additionalImages: additionalImages,
      description: description,
      color: color,
      specifications: specifications,
      tags: tags,
      isSet: isSet,
      parentSetId: parentSetId,
      updatedAt: DateTime(2026, 8, 12),
    );
  }

  Future<void> pumpPane(
    WidgetTester tester, {
    required Product record,
    Product? fullRecord,
    bool isLoadingFullRecord = false,
    int? effectiveStock,
    ProductSetAvailabilityProjection? setAvailability,
    Map<String, int> quantityInSetByComponentId = const {},
    ValueChanged<String>? onFilterByCategory,
    ValueChanged<String>? onFilterByBrand,
    ValueChanged<String>? onFilterBySupplier,
    Uri? storeProductUri,
    ValueChanged<Uri>? onOpenUri,
    Uri? supplierProductUri,
    ValueChanged<Uri>? onOpenSupplierProduct,
    WidgetBuilder? movementsBuilder,
    VoidCallback? onEdit,
    VoidCallback? onClose,
    Brightness brightness = Brightness.light,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1280, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.pacific,
          brightness: brightness,
        ),
        home: Scaffold(
          body: Row(
            children: [
              const Expanded(child: SizedBox()),
              SizedBox(
                width: 520,
                child: ProductDetailPane(
                  product: record,
                  fullRecord: fullRecord,
                  isLoadingFullRecord: isLoadingFullRecord,
                  isServicesScope: false,
                  effectiveStock: effectiveStock ?? record.inventoryQty,
                  setAvailability: setAvailability,
                  quantityInSetByComponentId: quantityInSetByComponentId,
                  onClose: onClose ?? () {},
                  onEdit: onEdit ?? () {},
                  onFilterByCategory: onFilterByCategory,
                  onFilterByBrand: onFilterByBrand,
                  onFilterBySupplier: onFilterBySupplier,
                  storeProductUri: storeProductUri,
                  onOpenUri: onOpenUri,
                  supplierProductUri: supplierProductUri,
                  onOpenSupplierProduct: onOpenSupplierProduct,
                  movementsBuilder: movementsBuilder,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  String badgeLabel(WidgetTester tester, String label) {
    final badge = tester.widget<VbStatusBadge>(
      find.byWidgetPredicate(
        (widget) => widget is VbStatusBadge && widget.label == label,
      ),
    );
    return badge.label;
  }

  group('ProductMargin', () {
    test('es el precio de venta menos el costo con IVA redondeado a pesos', () {
      final margin = ProductMargin.of(product(price: 600, cost: 250));
      // 250 × 1,19 = 297,5 → $298; 600 − 298 = 302; 302 / 298 = 101,3 %
      expect(margin.costWithIva, 298);
      expect(margin.amount, 302);
      expect(margin.percentOverCost, closeTo(302 / 298 * 100, 0.001));
      expect(margin.hasCost, isTrue);
      expect(margin.isBelowCost, isFalse);
    });

    test('un costo en cero no es un costo: no hay porcentaje', () {
      final margin = ProductMargin.of(product(price: 600, cost: 0));
      expect(margin.hasCost, isFalse);
      expect(margin.percentOverCost, isNull);
      expect(margin.isBelowCost, isFalse);
    });

    test('vender bajo el costo se declara', () {
      final margin = ProductMargin.of(product(price: 200, cost: 300));
      expect(margin.isBelowCost, isTrue);
    });
  });

  group('Códigos', () {
    testWidgets(
        'muestra SKU, código proveedor y código de barras, y copia al tocar',
        (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await pumpPane(tester, record: product());

      expect(find.text('2000000113180'), findsOneWidget);
      expect(find.text('MKR-NDL-90'), findsOneWidget);
      expect(find.text('7801234567890'), findsOneWidget);

      await tester.tap(find.byKey(ProductDetailPane.copyKey('supplier-code')));
      await tester.pump();

      final copied = calls
          .where((call) => call.method == 'Clipboard.setData')
          .map((call) => (call.arguments as Map)['text'])
          .toList();
      expect(copied, ['MKR-NDL-90']);
      expect(find.text('Código proveedor copiado'), findsOneWidget);
    });

    testWidgets(
        'con ficha en el portal, el código abre el navegador del ERP y copiar '
        'queda en su botón', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final portal = Uri.parse(
        'https://mkr.cl/store/category/todos?q=MKR-NDL-90&stock=1',
      );
      Uri? opened;
      await pumpPane(
        tester,
        record: product(),
        supplierProductUri: portal,
        onOpenSupplierProduct: (uri) => opened = uri,
      );

      expect(find.text('MKR-NDL-90 ↗'), findsOneWidget);
      await tester.tap(find.byKey(ProductDetailPane.supplierProductLinkKey));
      await tester.pump();
      expect(opened, portal);
      // Abrir no copia: el portapapeles sólo se toca desde su botón. (El
      // canal de plataforma también recibe el sonido del clic; se mira sólo
      // el portapapeles.)
      expect(
        calls.where((call) => call.method == 'Clipboard.setData'),
        isEmpty,
      );

      await tester.tap(find.byKey(ProductDetailPane.copyKey('supplier-code')));
      await tester.pump();
      final copied = calls
          .where((call) => call.method == 'Clipboard.setData')
          .map((call) => (call.arguments as Map)['text'])
          .toList();
      expect(copied, ['MKR-NDL-90']);
    });

    testWidgets(
        'sin código de proveedor la fila dice que falta, no queda en blanco',
        (tester) async {
      await pumpPane(tester,
          record: product(supplierCode: null, barcode: null));

      expect(find.text('Código proveedor'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(2));
      expect(
          find.byKey(ProductDetailPane.copyKey('supplier-code')), findsNothing);
      expect(find.byKey(ProductDetailPane.copyKey('sku')), findsOneWidget);
    });
  });

  group('Precios', () {
    testWidgets('el margen es precio de venta menos costo con IVA',
        (tester) async {
      await pumpPane(tester, record: product(price: 600, cost: 250));

      // Costo + IVA: 250 × 1,19 = 297,5 → $298. Margen: 600 − 298 = $302,
      // que sobre $298 es 101,3 %. La resta visible cuadra con lo mostrado.
      expect(find.text('Costo + IVA'), findsOneWidget);
      expect(find.text('\$298'), findsOneWidget);
      expect(find.text('Margen'), findsOneWidget);
      expect(find.text('\$302'), findsOneWidget);
      expect(find.textContaining('101,3%'), findsOneWidget);
      expect(find.text('Bajo el costo'), findsNothing);
      // Sin filas de más: el dueño pidió la cuenta corta.
      expect(find.text('Precio sin IVA'), findsNothing);
    });

    testWidgets('sin costo registrado no se inventa un margen', (tester) async {
      await pumpPane(tester, record: product(price: 600, cost: 0));

      expect(find.text('Sin costo registrado'), findsOneWidget);
      expect(find.text('Sin registrar'), findsOneWidget);
      expect(find.text('Costo + IVA'), findsNothing);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('vender bajo el costo se anuncia con palabras', (tester) async {
      await pumpPane(tester, record: product(price: 200, cost: 300));

      expect(badgeLabel(tester, 'Bajo el costo'), 'Bajo el costo');
    });
  });

  group('Estado de stock', () {
    testWidgets('sin stock, stock bajo y en stock salen del porqué',
        (tester) async {
      await pumpPane(tester, record: product(inventoryQty: 0));
      expect(find.text('Sin stock'), findsOneWidget);

      await pumpPane(tester,
          record: product(inventoryQty: 1, minStockLevel: 2));
      expect(find.text('Stock bajo'), findsOneWidget);
      expect(find.text('Stock mínimo'), findsOneWidget);
      expect(find.text('2 un.'), findsOneWidget);

      await pumpPane(tester,
          record: product(inventoryQty: 10, minStockLevel: 2));
      expect(find.text('En stock'), findsOneWidget);
      expect(find.text('10 un.'), findsOneWidget);
      // Valor a costo: 10 × $250.
      expect(find.text('\$2.500'), findsOneWidget);
    });

    testWidgets('un producto inactivo lo dice', (tester) async {
      await pumpPane(tester, record: product(isActive: false));
      expect(find.text('Inactivo'), findsOneWidget);
    });

    testWidgets('un juego lista sus componentes con la cantidad por juego',
        (tester) async {
      final set = product(id: 'set1', name: 'Juego de frenos', isSet: true);
      final pad = product(
        id: 'a',
        name: 'Pastilla',
        sku: 'PAD',
        inventoryQty: 5,
        parentSetId: 'set1',
      );
      final cable = product(
        id: 'b',
        name: 'Cable',
        sku: 'CAB',
        inventoryQty: 3,
        parentSetId: 'set1',
      );
      await pumpPane(
        tester,
        record: set,
        effectiveStock: 2,
        setAvailability: ProductSetAvailabilityProjection(
          isConfigured: true,
          completeSetsAvailable: 2,
          hasPartialStock: true,
          hasNegativeComponentStock: false,
          components: [pad, cable],
        ),
        quantityInSetByComponentId: const {'a': 2},
      );

      expect(find.text('Juegos completos'), findsOneWidget);
      expect(find.text('Componentes del juego'), findsOneWidget);
      expect(find.text('2× Pastilla'), findsOneWidget);
      expect(find.text('Cable'), findsOneWidget);
      expect(find.text('5 un.'), findsOneWidget);
      expect(find.text('3 un.'), findsOneWidget);
      expect(find.text('Con piezas sueltas'), findsOneWidget);
    });
  });

  group('Canales', () {
    testWidgets('tienda web, Google Merchant y WhatsApp con su estado',
        (tester) async {
      Uri? opened;
      final storeUri = Uri.parse(
        'https://www.vinabike.cl/productos/noodle-para-cable/2000000113180',
      );
      await pumpPane(
        tester,
        record: product(),
        storeProductUri: storeUri,
        onOpenUri: (uri) => opened = uri,
      );

      expect(find.text('Publicado'), findsOneWidget);
      expect(find.text('No incluido'), findsOneWidget);
      expect(find.text('Sincronizado'), findsOneWidget);

      await tester.ensureVisible(find.byKey(ProductDetailPane.openStoreKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ProductDetailPane.openStoreKey));
      await tester.pump();
      expect(opened, storeUri);
    });

    testWidgets('sin publicar no hay enlace a la tienda', (tester) async {
      await pumpPane(
        tester,
        record: product(
          isPublished: false,
          isWhatsappCatalog: true,
          whatsappCatalogSyncStatus: 'failed',
        ),
        storeProductUri: Uri.parse('https://www.vinabike.cl/productos/x/y'),
        onOpenUri: (_) {},
      );

      expect(find.text('No publicado'), findsOneWidget);
      expect(find.byKey(ProductDetailPane.openStoreKey), findsNothing);
      expect(find.text('Con error'), findsOneWidget);
    });
  });

  group('Marca, categoría y proveedor', () {
    testWidgets('filtran la lista al tocarlos', (tester) async {
      final filtered = <String>[];
      await pumpPane(
        tester,
        record: product(),
        onFilterByBrand: (id) => filtered.add('brand:$id'),
        onFilterByCategory: (id) => filtered.add('category:$id'),
        onFilterBySupplier: (id) => filtered.add('supplier:$id'),
      );

      expect(find.text('MKR'), findsOneWidget);
      expect(find.text('Noodles'), findsOneWidget);
      expect(find.text('Andes Industrial'), findsOneWidget);

      await tester.tap(find.byKey(ProductDetailPane.filterKey('brand')));
      await tester.tap(find.byKey(ProductDetailPane.filterKey('category')));
      await tester.tap(find.byKey(ProductDetailPane.filterKey('supplier')));
      await tester.pump();

      expect(filtered, ['brand:b1', 'category:c1', 'supplier:s1']);
    });

    testWidgets('sin id no hay filtro, pero el nombre se sigue leyendo',
        (tester) async {
      await pumpPane(
        tester,
        record: product(brandId: null),
        onFilterByBrand: (_) {},
      );

      expect(find.text('MKR'), findsOneWidget);
      expect(find.byKey(ProductDetailPane.filterKey('brand')), findsNothing);
    });
  });

  group('Imagen', () {
    testWidgets('abre el visor grande y se cierra desde su propia salida',
        (tester) async {
      await pumpPane(
        tester,
        record: product(
          additionalImages: const [
            'http://127.0.0.1:1/noodle-2.png',
            'http://127.0.0.1:1/noodle-3.png',
          ],
        ),
      );

      expect(find.byKey(ProductDetailPane.thumbnailKey(0)), findsOneWidget);
      expect(find.byKey(ProductDetailPane.thumbnailKey(2)), findsOneWidget);

      await tester.tap(find.byKey(ProductDetailPane.thumbnailKey(2)));
      await tester.pump();
      await tester.tap(find.byKey(ProductDetailPane.imageKey));
      await tester.pumpAndSettle();

      expect(find.byKey(ProductImageViewer.dialogKey), findsOneWidget);
      expect(find.text('3 de 3'), findsOneWidget);
      expect(find.byKey(ProductImageViewer.thumbnailKey(1)), findsOneWidget);

      await tester.tap(find.byKey(ProductImageViewer.previousKey));
      await tester.pumpAndSettle();
      expect(find.text('2 de 3'), findsOneWidget);

      await tester.tap(find.byKey(ProductImageViewer.closeKey));
      await tester.pumpAndSettle();
      expect(find.byKey(ProductImageViewer.dialogKey), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sin imagen no hay nada que abrir', (tester) async {
      await pumpPane(tester, record: product(imageUrl: null));

      expect(find.text('Sin imagen'), findsOneWidget);
      expect(find.byKey(ProductDetailPane.imageKey), findsNothing);
    });
  });

  group('Ficha', () {
    testWidgets('muestra el esqueleto mientras carga y los datos cuando llegan',
        (tester) async {
      final preview = product(description: 'Guía de cable para freno V-Brake.');
      await pumpPane(tester, record: preview, isLoadingFullRecord: true);

      expect(find.text('Ficha'), findsOneWidget);
      expect(find.text('Guía de cable para freno V-Brake.'), findsOneWidget);
      expect(find.byType(VbSkeleton), findsWidgets);
      expect(find.text('Color'), findsNothing);

      final specs = {
        for (var i = 1; i <= 8; i++) 'Spec $i': 'Valor $i',
      };
      await pumpPane(
        tester,
        record: preview,
        fullRecord: product(
          description: 'Guía de cable para freno V-Brake.',
          color: 'Plateado',
          specifications: specs,
          tags: const ['freno', 'v-brake'],
        ),
      );

      expect(find.byType(VbSkeleton), findsNothing);
      expect(find.text('Color'), findsOneWidget);
      expect(find.text('Plateado'), findsOneWidget);
      expect(find.text('Spec 6'), findsOneWidget);
      expect(find.text('Spec 7'), findsNothing);
      expect(find.text('freno · v-brake'), findsOneWidget);

      await tester.ensureVisible(find.byKey(ProductDetailPane.specsToggleKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ProductDetailPane.specsToggleKey));
      await tester.pump();
      expect(find.text('Spec 8'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('una descripción larga se pliega y se despliega',
        (tester) async {
      final long = List.filled(40, 'palabra').join(' ');
      await pumpPane(tester, record: product(description: long));

      final folded = tester.widget<Text>(find.text(long));
      expect(folded.maxLines, 3);

      await tester.ensureVisible(
        find.byKey(ProductDetailPane.descriptionToggleKey),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ProductDetailPane.descriptionToggleKey));
      await tester.pump();
      final unfolded = tester.widget<Text>(find.text(long));
      expect(unfolded.maxLines, isNull);
      expect(find.text('Ver menos'), findsOneWidget);
    });

    testWidgets('sin descripción ni ficha completa la sección no aparece',
        (tester) async {
      await pumpPane(tester, record: product(), fullRecord: product());
      expect(find.text('Ficha'), findsNothing);
    });
  });

  group('Cabecera y pie', () {
    testWidgets('Movimientos usa el contenido del host y esconde el pie',
        (tester) async {
      var edits = 0;
      var closes = 0;
      await pumpPane(
        tester,
        record: product(),
        onEdit: () => edits++,
        onClose: () => closes++,
        movementsBuilder: (_) => const Text('MOVIMIENTOS DEL HOST'),
      );

      expect(find.byKey(ProductDetailPane.editKey), findsOneWidget);
      await tester.tap(find.byKey(ProductDetailPane.editKey));
      expect(edits, 1);

      await tester.tap(
        find.byKey(VbSubTabs.tabKey(ProductDetailPaneTab.movements)),
      );
      await tester.pump();
      expect(find.text('MOVIMIENTOS DEL HOST'), findsOneWidget);
      expect(find.byKey(ProductDetailPane.editKey), findsNothing);

      await tester.tap(find.byKey(ProductDetailPane.closeKey));
      expect(closes, 1);
    });

    testWidgets('sin builder de movimientos sólo existe Detalles',
        (tester) async {
      await pumpPane(tester, record: product());
      expect(
        find.byKey(VbSubTabs.tabKey(ProductDetailPaneTab.movements)),
        findsNothing,
      );
      expect(
        find.byKey(VbSubTabs.tabKey(ProductDetailPaneTab.details)),
        findsOneWidget,
      );
    });
  });

  group('Modo oscuro', () {
    testWidgets('el panel completo se monta con los roles oscuros sin fallar',
        (tester) async {
      final specs = {for (var i = 1; i <= 8; i++) 'Spec $i': 'Valor $i'};
      await pumpPane(
        tester,
        brightness: Brightness.dark,
        record: product(price: 200, cost: 300, inventoryQty: 1),
        fullRecord: product(
          price: 200,
          cost: 300,
          inventoryQty: 1,
          description: List.filled(40, 'palabra').join(' '),
          color: 'Plateado',
          specifications: specs,
          tags: const ['freno'],
          additionalImages: const ['http://127.0.0.1:1/noodle-2.png'],
        ),
        storeProductUri: Uri.parse('https://www.vinabike.cl/productos/x/y'),
        onOpenUri: (_) {},
        movementsBuilder: (_) => const SizedBox(),
      );

      expect(find.text('Bajo el costo'), findsOneWidget);
      expect(find.text('Stock bajo'), findsOneWidget);
      expect(find.text('Abrir en la tienda ↗'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(ProductDetailPane.imageKey));
      await tester.pumpAndSettle();
      expect(find.byKey(ProductImageViewer.dialogKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
