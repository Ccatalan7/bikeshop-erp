import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/supplier_catalog.dart';
import 'package:vinabike_erp/modules/purchases/services/supply_need_effective_criteria.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';

/// **Una coincidencia amplia del servidor no es un cumplimiento.**
///
/// Los CTA de MKR y AliExpress abren su catálogo interno, y bajo «COINCIDE CON
/// esta petición» aparecían, para un pedido de pastillas, patines V-Brake,
/// frenos completos, discos, mangueras y olivas. El cliente ya tiene el
/// nombre, la marca y la categoría de cada fila, así que puede aplicarles el
/// **mismo juicio** que la lista de proveedores antes de destacar nada.

SupplierCatalogItem _item(String id, String name, {String? brand}) =>
    SupplierCatalogItem(
      productId: id,
      name: name,
      sku: null,
      brand: brand,
      categoryPath: 'Componentes / Frenos',
      origin: SupplierCatalogOrigin.catalogued,
      timesPurchased: 0,
      totalQuantity: null,
      lastPurchaseAt: null,
      lastInvoiceNumber: null,
      lastLandedUnitCostNet: null,
      lastBaseUnitCostNet: null,
      catalogCostNet: 1000,
      available: null,
      imageUrl: null,
      matchesNeed: true,
    );

SupplierNeedSearchPlan _plan() => buildSupplierNeedSearchPlan(
      request: const SupplierNeedSearchRequest(
        needId: 'need-pastillas',
        description: 'Pastillas para frenos Shimano',
        categoryId: 'cat',
        categoryPath: 'Componentes / Frenos / Pastillas',
        technicalFamily: 'brake_pad',
        fields: <SupplierNeedSearchField>[],
        predicates: <SupplierNeedSearchPredicate>[],
      ),
      adapter: SupplierNeedPortalAdapter.fromJson(<String, dynamic>{
        'version': 1,
        'generic_family_search': true,
        'result_schema': <String, dynamic>{
          'columns': <String, dynamic>{
            'code': <String>['c'],
            'name': <String>['n'],
            'price': <String>['p'],
          },
        },
        'catalog_route': <String, dynamic>{
          'url_template': 'http://catalogo/{node}{page}{page_size}',
          'page_size': 50,
        },
      }),
      maxLength: 20,
    )!;

void main() {
  final items = <SupplierCatalogItem>[
    _item('p1', 'PASTILLA FRENO DISCO RESINA SHIMANO'),
    _item('p2', 'FRENO COMPLETO SHIMANO BR-MT200 HIDRAULICO'),
    _item('p3', 'MANGUERA HIDRAULICA SHIMANO'),
    _item('p4', 'DISCO DE FRENO 160MM CENTERLOCK'),
    _item('p5', 'OLIVA Y PIN PARA MANGUERA'),
  ];

  test('sólo se destaca lo que el juicio compartido acepta', () {
    final destacados = supplierCatalogHighlightedProductIds(
      items: items,
      plan: _plan(),
    );
    expect(destacados, <String>{'p1'});
    for (final fuera in const <String>['p2', 'p3', 'p4', 'p5']) {
      expect(destacados, isNot(contains(fuera)), reason: fuera);
    }
  });

  test('sin ficha con que juzgar manda lo que dijo el servidor', () {
    // No se inventa un veredicto propio cuando no hay con qué formarlo.
    expect(
      supplierCatalogHighlightedProductIds(items: items, plan: null),
      items.map((item) => item.productId).toSet(),
    );
  });

  test('lo que no se destaca sigue existiendo: no se esconde el catálogo', () {
    final destacados = supplierCatalogHighlightedProductIds(
      items: items,
      plan: _plan(),
    );
    final resto = items.where((i) => !destacados.contains(i.productId));
    expect(resto.length, items.length - destacados.length);
    expect(
      resto.map((i) => i.productId),
      containsAll(<String>['p2', 'p3', 'p4', 'p5']),
      reason: 'lo que no se pudo demostrar sigue a la vista, sin destacarse',
    );
  });
}
