import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/models/public_product_visibility_policy.dart';

import '../../scripts/generate_product_seo_snapshots.dart' as snapshots;

/// Una ficha agotada conserva su snapshot; los listados (catálogo y
/// categorías) siguen el ajuste de stock del sitio, igual que la tienda.
void main() {
  Map<String, dynamic> row({
    String type = 'product',
    bool track = true,
    int quantity = 0,
  }) =>
      {
        'product_type': type,
        'track_stock': track,
        'stock_quantity': quantity,
      };

  test('con «sólo disponibles» un agotado sale de los listados', () {
    const policy = PublicCatalogStockPolicy.availableOnly;
    expect(
        snapshots.isSeoListingStockEligible(row(quantity: 3), policy), isTrue);
    expect(snapshots.isSeoListingStockEligible(row(), policy), isFalse);
    expect(
        snapshots.isSeoListingStockEligible(row(track: false), policy), isTrue,
        reason: 'sin control de stock siempre se lista');
    expect(snapshots.isSeoListingStockEligible(row(type: 'service'), policy),
        isTrue);
  });

  test('con «todos» se lista también el agotado', () {
    expect(
      snapshots.isSeoListingStockEligible(
        row(),
        PublicCatalogStockPolicy.all,
      ),
      isTrue,
    );
  });

  test('con «sólo agotados» se lista sólo lo que no tiene stock', () {
    const policy = PublicCatalogStockPolicy.outOfStockOnly;
    expect(snapshots.isSeoListingStockEligible(row(), policy), isTrue);
    expect(
        snapshots.isSeoListingStockEligible(row(quantity: 2), policy), isFalse);
  });
}
