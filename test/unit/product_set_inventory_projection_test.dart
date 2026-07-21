import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/inventory/models/inventory_models.dart';
import 'package:vinabike_erp/modules/inventory/utils/product_set_inventory_projection.dart';

void main() {
  test('set availability honors quantity per set and partial leftovers', () {
    final parent = _product(id: 'set', stock: 0, isSet: true);
    final first = _product(id: 'first', stock: 3, parentSetId: 'set');
    final second = _product(id: 'second', stock: 2, parentSetId: 'set');

    final projection = projectProductSetAvailability(
      setProduct: parent,
      allProducts: [parent, first, second],
      quantityInSetByComponentId: const {'first': 2, 'second': 1},
    );

    expect(projection.isConfigured, isTrue);
    expect(projection.completeSetsAvailable, 1);
    expect(projection.hasPartialStock, isTrue);
    expect(projection.hasNegativeComponentStock, isFalse);
  });

  test('summary counts physical children once and never the virtual parent',
      () {
    final parent = _product(id: 'set', stock: 0, isSet: true, cost: 999);
    final first =
        _product(id: 'first', stock: -1, parentSetId: 'set', cost: 10);
    final second =
        _product(id: 'second', stock: -1, parentSetId: 'set', cost: 20);
    final standalone = _product(id: 'normal', stock: 1, cost: 100);

    final summary = summarizePhysicalInventory(
      visibleProducts: [parent, standalone],
      allProducts: [parent, first, second, standalone],
    );

    expect(summary.outOfStockCount, 2);
    expect(summary.lowStockCount, 1);
    expect(summary.inventoryCost, 70);
  });
}

Product _product({
  required String id,
  required int stock,
  bool isSet = false,
  String? parentSetId,
  double cost = 0,
}) {
  return Product(
    id: id,
    tenantId: 'tenant',
    name: id,
    sku: id.toUpperCase(),
    price: 100,
    cost: cost,
    inventoryQty: stock,
    minStockLevel: 1,
    isSet: isSet,
    parentSetId: parentSetId,
  );
}
