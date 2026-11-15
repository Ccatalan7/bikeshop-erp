import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_engine.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_entry.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_index.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_query.dart';

/// El buscador encuentra las marcas y lleva a su página.
///
/// El dueño (2026-11-14): «ese buscador también encuentre marcas… seleccionarla
/// y entrar a esa marca y ver todo eso». Antes, «maxxis» contestaba con los
/// neumáticos y ninguna manera de llegar a la marca. Las filas tienen la forma
/// de `brand_directory_v1`; los productos, la del índice.
void main() {
  Map<String, dynamic> brand(
    String id,
    String name, {
    String? logo,
    int products = 0,
    int inStock = 0,
    Map<String, dynamic>? supplier,
    int supplierCount = 0,
    bool active = true,
  }) =>
      <String, dynamic>{
        'id': id,
        'name': name,
        'logo_url': logo,
        'is_active': active,
        'shared': true,
        'products': products,
        'in_stock': inStock,
        'units': inStock,
        'stock_cost': 0,
        'on_web': 0,
        'sold_12m': 0,
        'last_sale': null,
        'images': const <String>[],
        'supplier': supplier,
        'supplier_count': supplierCount,
      };

  Map<String, dynamic> product(String id, String name, {String? brand}) =>
      <String, dynamic>{
        'id': id,
        'name': name,
        'sku': 'SKU-$id',
        'barcode': null,
        'brand': brand,
        'model': null,
        'category_name': 'Neumáticos',
        'stock_quantity': 2,
        'is_service': false,
        'is_active': true,
        'updated_at': '2026-11-10T12:00:00Z',
        'image_url': null,
        'image_url_optimized': null,
        'category_id': 'neumaticos',
        'parent_set_id': null,
      };

  final teknobike = <String, dynamic>{
    'id': 'teknobike',
    'name': 'TeknoBike',
    'official': true,
    'image_url': null,
  };

  final maxxis = globalSearchBrandEntry(
    brand(
      'maxxis',
      'Maxxis',
      logo: 'https://example.invalid/maxxis.png',
      products: 16,
      inStock: 9,
      supplier: teknobike,
      supplierCount: 2,
    ),
  );

  final entries = <GlobalSearchEntry>[
    maxxis,
    globalSearchBrandEntry(brand('fox', 'Fox')),
    globalSearchBrandEntry(
      brand('kenda', 'Kenda',
          products: 3, inStock: 1, supplier: teknobike, supplierCount: 1),
    ),
    globalSearchProductEntry(
        product('p1', 'Neumático Maxxis Ardent 29x2.40 EXO', brand: 'Maxxis')),
    globalSearchProductEntry(
        product('p2', 'Neumático Maxxis Minion DHF 29x2.50', brand: 'Maxxis')),
    globalSearchProductEntry(
        product('p3', 'Cámara Maxxis 29 Presta 48 mm', brand: 'Maxxis')),
    globalSearchSupplierEntry(<String, dynamic>{
      'id': 'teknobike',
      'name': 'TeknoBike',
      'rut': null,
      'trade_name': null,
      'legal_name': null,
      'aliases': null,
      'is_active': true,
      'updated_at': '2026-11-01T12:00:00Z',
      'image_url': null,
      'website': null,
    }),
  ];

  test('«maxxis» pone la marca arriba de sus productos', () {
    final outcome = rankGlobalSearch(
      query: GlobalSearchQuery.parse('maxxis'),
      entries: entries,
    );
    expect(outcome.groups.first.kind, GlobalSearchKind.brand);
    expect(outcome.groups.first.kind.groupTitle, 'Marcas');
    expect(outcome.flattened.first.entry.id, 'brand:maxxis');
    expect(
      outcome.groups.map((group) => group.kind),
      contains(GlobalSearchKind.product),
      reason: 'los neumáticos siguen apareciendo, debajo de la marca',
    );
  });

  test('la marca abre su página y dice lo que guarda y quién la trae', () {
    expect(maxxis.route, '/inventory/brands/maxxis');
    expect(maxxis.subtitle, 'Marca · 16 productos · 9 con stock · '
        'TeknoBike y 1 más');
    expect(maxxis.imageUrl, 'https://example.invalid/maxxis.png');
    expect(maxxis.kind.listRoute, '/inventory/brands');
  });

  test('una marca sin productos lo dice, y la inactiva también', () {
    expect(globalSearchBrandEntry(brand('fox', 'Fox')).subtitle,
        'Marca · sin productos');
    expect(
      globalSearchBrandEntry(brand('old', 'Vieja', active: false)).subtitle,
      'Marca · sin productos · Inactiva',
    );
  });

  test('el proveedor trae sus marcas, detrás de su propia ficha', () {
    final outcome = rankGlobalSearch(
      query: GlobalSearchQuery.parse('teknobike'),
      entries: entries,
    );
    expect(outcome.flattened.first.entry.id, 'supplier:teknobike');
    final brands = outcome.groups
        .firstWhere((group) => group.kind == GlobalSearchKind.brand)
        .results
        .map((result) => result.entry.id);
    expect(brands, containsAll(<String>['brand:maxxis', 'brand:kenda']));
  });

  test('«marca kenda» también llega a la marca', () {
    final outcome = rankGlobalSearch(
      query: GlobalSearchQuery.parse('marca kenda'),
      entries: entries,
    );
    expect(outcome.flattened.first.entry.id, 'brand:kenda');
  });
}
