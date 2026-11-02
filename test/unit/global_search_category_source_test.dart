import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_engine.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_entry.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_index.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_query.dart';

/// El buscador encuentra las categorías del inventario.
///
/// El caso lo reportó el dueño (2026-11-02): «neumaticos» traía 124 productos
/// y 5 trabajos, y ninguna categoría. Las filas replican producción: el árbol
/// `Componentes / Ruedas / Neumáticos`, «Ruedas» repetida bajo Servicio, y los
/// productos y servicios que aparecían en su captura.
void main() {
  Map<String, dynamic> category(
    String id,
    String name,
    String fullPath, {
    String? parentId,
    bool active = true,
  }) =>
      <String, dynamic>{
        'id': id,
        'name': name,
        'full_path': fullPath,
        'parent_id': parentId,
        'image_url': null,
        'is_active': active,
        'updated_at': '2026-10-01T12:00:00Z',
      };

  Map<String, dynamic> product(
    String id,
    String name, {
    required String sku,
    required String categoryId,
    required String categoryName,
    bool service = false,
    bool active = true,
    String? parentSetId,
    int stock = 0,
  }) =>
      <String, dynamic>{
        'id': id,
        'name': name,
        'sku': sku,
        'barcode': null,
        'brand': null,
        'model': null,
        'category_name': categoryName,
        'stock_quantity': stock,
        'is_service': service,
        'is_active': active,
        'updated_at': '2026-10-20T12:00:00Z',
        'image_url': null,
        'image_url_optimized': null,
        'category_id': categoryId,
        'parent_set_id': parentSetId,
      };

  final categories = <Map<String, dynamic>>[
    category('componentes', 'Componentes', 'Componentes'),
    category('ruedas', 'Ruedas', 'Componentes / Ruedas',
        parentId: 'componentes'),
    category('neumaticos', 'Neumáticos', 'Componentes / Ruedas / Neumáticos',
        parentId: 'ruedas'),
    category('camaras', 'Cámaras', 'Componentes / Ruedas / Cámaras',
        parentId: 'ruedas'),
    category('cambios', 'Cambios', 'Componentes / Cambios',
        parentId: 'componentes'),
    category('regulador', 'Regulador tensión',
        'Componentes / Cambios / Regulador tensión',
        parentId: 'cambios'),
    category('servicio', 'Servicio', 'Servicio'),
    category('servicio-ruedas', 'Ruedas', 'Servicio / Ruedas',
        parentId: 'servicio'),
    category('retirada', 'Neumáticos viejos', 'Componentes / Neumáticos viejos',
        parentId: 'componentes', active: false),
  ];

  final products = <Map<String, dynamic>>[
    product('p-presion', 'Presión de neumáticos',
        sku: 'NNV137',
        categoryId: 'servicio-ruedas',
        categoryName: 'Ruedas',
        service: true),
    product('p-renovador', 'Aplicación de renovador de neumáticos',
        sku: 'NNV9',
        categoryId: 'servicio-ruedas',
        categoryName: 'Ruedas',
        service: true),
    product('p-cst24', 'Neumatico CST 24x2.10 C1020N',
        sku: '25257', categoryId: 'neumaticos', categoryName: 'Neumáticos'),
    product('p-cst275', 'Neumatico CST AT 27.5x2.10 C1820',
        sku: '25262',
        categoryId: 'neumaticos',
        categoryName: 'Neumáticos',
        stock: 3),
    product('p-arisun',
        'NEUMATICO ARISUN 27.5 X 2.25 30 TPI MOUNT BONA BORDE T030107',
        sku: '6927116102982',
        categoryId: 'neumaticos',
        categoryName: 'Neumáticos'),
    // Lo que la lista no muestra no se cuenta: un archivado y la pieza de un
    // juego, que se ve dentro de su juego y no suelta.
    product('p-archivado', 'Neumatico Kenda 26x1.95',
        sku: '11111',
        categoryId: 'neumaticos',
        categoryName: 'Neumáticos',
        active: false),
    product('p-componente', 'Neumatico del juego',
        sku: '22222',
        categoryId: 'neumaticos',
        categoryName: 'Neumáticos',
        parentSetId: 'set-1'),
    product('p-camara', 'Camara 29x2.1 valvula presta',
        sku: '25300',
        categoryId: 'camaras',
        categoryName: 'Cámaras',
        stock: 10),
  ];

  final categoryEntries = globalSearchCategoryEntries(categories, products);
  GlobalSearchEntry entryFor(String id) =>
      categoryEntries.singleWhere((entry) => entry.id == 'category:$id');

  final everything = <GlobalSearchEntry>[
    for (final row in products) globalSearchProductEntry(row),
    ...categoryEntries,
  ];

  test('«neumaticos» contesta primero con la categoría', () {
    final outcome = rankGlobalSearch(
      query: GlobalSearchQuery.parse('neumaticos'),
      entries: everything,
    );
    expect(outcome.groups.first.kind, GlobalSearchKind.category);
    expect(outcome.groups.first.kind.groupTitle, 'Categorías');
    expect(outcome.flattened.first.entry.id, 'category:neumaticos');
    // Los productos siguen ahí, debajo.
    expect(
      outcome.groups.map((group) => group.kind),
      contains(GlobalSearchKind.product),
    );
  });

  test('dice dónde está y cuánto guarda, como lo mostrará la lista', () {
    // Tres a la venta: el archivado y la pieza del juego no se cuentan.
    expect(
        entryFor('neumaticos').subtitle, 'Componentes / Ruedas · 3 productos');
  });

  test('una madre cuenta lo de sus subcategorías', () {
    // «Ruedas» no tiene productos propios: los suyos están en sus hijas.
    expect(entryFor('ruedas').subtitle, 'Componentes · 4 productos');
    // La raíz no tiene dónde estar; sólo cuánto guarda.
    expect(entryFor('componentes').subtitle, '4 productos');
  });

  test('abre la lista de productos filtrada por ella', () {
    expect(entryFor('neumaticos').route,
        '/inventory/products?category=neumaticos');
    expect(entryFor('ruedas').route, '/inventory/products?category=ruedas');
  });

  test('una categoría de servicios abre la lista de servicios', () {
    final entry = entryFor('servicio-ruedas');
    expect(entry.subtitle, 'Servicio · 2 servicios');
    expect(entry.route, '/inventory/services?category=servicio-ruedas');
  });

  test('una categoría vacía lo dice', () {
    expect(
      entryFor('regulador').subtitle,
      'Componentes / Cambios · Sin productos',
    );
  });

  test('una categoría inactiva no se ofrece', () {
    expect(
      categoryEntries.map((entry) => entry.id),
      isNot(contains('category:retirada')),
    );
  });

  test('«ruedas» trae las dos Ruedas primero y el lugar las distingue', () {
    final outcome = rankGlobalSearch(
      query: GlobalSearchQuery.parse('ruedas'),
      entries: everything,
    );
    final group = outcome.groups.first;
    expect(group.kind, GlobalSearchKind.category);
    expect(
      group.results.take(2).map((result) => result.entry.subtitle),
      unorderedEquals(<String>[
        'Componentes · 4 productos',
        'Servicio · 2 servicios',
      ]),
    );
    // Sus hijas vienen después, por estar dentro de Ruedas.
    expect(
      group.results.skip(2).map((result) => result.entry.id),
      containsAll(<String>['category:neumaticos', 'category:camaras']),
    );
  });

  test('«categoría neumáticos» también la encuentra', () {
    final outcome = rankGlobalSearch(
      query: GlobalSearchQuery.parse('categoría neumáticos'),
      entries: everything,
    );
    expect(outcome.flattened.first.entry.id, 'category:neumaticos');
  });
}
