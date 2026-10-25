import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/catalog/catalog_web_models.dart';

/// «Incluir agotados» in the store's search (2026-10-24, 20261024050000): the
/// rule the database reads lives in «Reglas de la tienda».
void main() {
  test('a store without the setting offers it, as the database reads it', () {
    expect(CatalogRules.fromSettings(const {}).searchOutOfStock, 'offer');
    expect(
      CatalogRules.fromSettings(const {
        CatalogRules.searchOutOfStockKey: 'cualquier cosa',
      }).searchOutOfStock,
      'offer',
    );
  });

  test('«no aparecen» is kept and saved back with the other rules', () {
    final rules = CatalogRules.fromSettings(const {
      CatalogRules.searchOutOfStockKey: ' HIDE ',
    });
    expect(rules.searchOutOfStock, 'hide');
    expect(
      rules.toSettings()[CatalogRules.searchOutOfStockKey],
      'hide',
    );
    expect(CatalogRules.keys, contains(CatalogRules.searchOutOfStockKey));
    expect(
      rules.copyWith(searchOutOfStock: 'offer').searchOutOfStock,
      'offer',
    );
    expect(rules.copyWith(stockPolicy: 'all').searchOutOfStock, 'hide');
  });
}
