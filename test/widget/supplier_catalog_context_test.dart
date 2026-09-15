import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/purchases/models/supplier_catalog.dart';
import 'package:vinabike_erp/modules/purchases/widgets/purchase_visual_language.dart';
import 'package:vinabike_erp/modules/purchases/widgets/supplier_workspace_view.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// **La ficha del proveedor no olvida lo que se estaba buscando.**
///
/// Se entra desde una necesidad concreta —«Cámaras 29 con válvula Schrader»— y
/// la primera versión abría con una cámara 26: ignoraba el motivo por el que el
/// operador llegó ahí. Lo que coincide va primero y rotulado; el resto sigue
/// abajo, porque a veces se entra justamente a mirar qué más tiene.
SupplierCatalogItem _item({
  required String id,
  required String name,
  required bool matches,
  String? imageUrl,
  double? landed = 2850,
}) {
  return SupplierCatalogItem(
    productId: id,
    name: name,
    sku: 'SKU-$id',
    brand: 'RBX',
    categoryPath: null,
    origin: landed == null
        ? SupplierCatalogOrigin.catalogued
        : SupplierCatalogOrigin.purchased,
    timesPurchased: landed == null ? 0 : 2,
    totalQuantity: landed == null ? null : 4,
    lastPurchaseAt: landed == null
        ? null
        : DateTime.now().subtract(const Duration(days: 60)),
    lastInvoiceNumber: landed == null ? null : '754591',
    lastLandedUnitCostNet: landed,
    catalogCostNet: 1890,
    available: 2,
    lastBaseUnitCostNet: landed == null ? null : landed - 60,
    imageUrl: imageUrl,
    matchesNeed: matches,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required SupplierCatalogPage page,
}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 1000);
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.dark,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SupplierWorkspaceView(
            page: page,
            loadingMore: false,
            searchController: TextEditingController(),
            addedProductIds: const <String>{},
            openOrders: const [],
            activeOrderId: null,
            onResumeOrder: (_) {},
            onBack: () {},
            onSearch: (_) {},
            onLoadMore: () {},
            onToggleLine: (_) {},
            onOpenPortal: () {},
            onAddPhoto: () {},
            basis: PurchaseCostBasis.sinFlete,
            onBasisChanged: (_) {},
          ),
        ),
      ),
    ),
  );
}

SupplierCatalogPage _page({
  String? needPhrase = 'Cámaras 29 con válvula Schrader',
  String? droppedFilters,
  required List<SupplierCatalogItem> items,
}) {
  return SupplierCatalogPage(
    supplier: const SupplierProfile(
      id: 's1',
      name: 'RBX',
      legalName: 'Rafael Burgos S.A.',
      rut: null,
      city: 'Santiago',
      website: null,
      imageUrl: null,
      paymentTerms: null,
      purchaseInstructions: null,
      salesRepName: null,
      salesRepPhone: '+56900000000',
      salesRepEmail: null,
      hasPortalAccount: false,
    ),
    metrics: const SupplierCatalogMetrics(
      purchaseLines: 34,
      purchaseInvoices: 5,
      distinctProducts: 30,
      landedSpendNet: 337657,
      purchasedUnits: 90,
      firstPurchaseAt: null,
      lastPurchaseAt: null,
    ),
    items: items,
    total: items.length,
    offset: 0,
    matched: items.where((item) => item.matchesNeed).length,
    needPhrase: needPhrase,
    droppedFilters: droppedFilters,
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('lo que coincide encabeza y lleva las palabras de la necesidad',
      (tester) async {
    await _pump(
      tester,
      page: _page(items: [
        _item(id: 'a', name: 'CAMARA 29 V/AMERICANA', matches: true),
        _item(id: 'b', name: 'CAMARA 26 V/AUTO', matches: false),
      ]),
    );

    expect(
      find.text('COINCIDE CON «CÁMARAS 29 CON VÁLVULA SCHRADER»'),
      findsOneWidget,
    );
    expect(find.text('EL RESTO DE SU CATÁLOGO'), findsOneWidget);

    // El orden es la mitad del asunto: rotular sin ordenar dejaría la 26
    // arriba igual.
    final coincide = tester.getTopLeft(find.text('CAMARA 29 V/AMERICANA')).dy;
    final resto = tester.getTopLeft(find.text('CAMARA 26 V/AUTO')).dy;
    expect(coincide, lessThan(resto));
  });

  testWidgets('una coincidencia ampliada lo dice', (tester) async {
    // Bajo «válvula Schrader» aparecía una cámara V/FRANCESA —que es justo la
    // otra— porque el resolutor soltó la medida. El rótulo no puede prometer
    // una coincidencia exacta sobre un resultado ampliado.
    await _pump(
      tester,
      page: _page(
        droppedFilters: 'la medida menos determinante',
        items: [_item(id: 'a', name: 'CAMARA 29 V/FRANCESA', matches: true)],
      ),
    );

    expect(
      find.text('Búsqueda ampliada: la medida menos determinante'),
      findsOneWidget,
    );
  });

  testWidgets('sin necesidad, no se inventa un grupo de coincidencias',
      (tester) async {
    await _pump(
      tester,
      page: _page(
        needPhrase: null,
        items: [_item(id: 'a', name: 'CAMARA 26 V/AUTO', matches: false)],
      ),
    );

    expect(find.textContaining('COINCIDE CON'), findsNothing);
    expect(find.text('EL RESTO DE SU CATÁLOGO'), findsNothing);
  });

  testWidgets('sin foto, el monograma ocupa el mismo lugar', (tester) async {
    // 1.365 de 1.612 productos tienen foto: acá la imagen es el caso común y
    // su ausencia la excepción. Lo que no puede pasar es que la fila cambie de
    // alto ni que la columna se corra.
    await _pump(
      tester,
      page: _page(items: [
        _item(id: 'a', name: 'CAMARA 29 V/AMERICANA', matches: true),
      ]),
    );

    // «CAMARA 29 …» → dos palabras, dos iniciales.
    expect(find.text('C2'), findsOneWidget);
  });
}
