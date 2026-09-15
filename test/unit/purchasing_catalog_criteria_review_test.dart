import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/supplier_catalog.dart';
import 'package:vinabike_erp/modules/purchases/services/supply_need_effective_criteria.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'purchasing_independent_review_test.dart' as qa;

SupplierCatalogItem item(String id, String name) => SupplierCatalogItem(
  productId: id, name: name, sku: null, brand: null,
  categoryPath: 'Componentes / Frenos / Pastillas',
  origin: SupplierCatalogOrigin.catalogued, timesPurchased: 0,
  totalQuantity: null, lastPurchaseAt: null, lastInvoiceNumber: null,
  lastLandedUnitCostNet: null, lastBaseUnitCostNet: null,
  catalogCostNet: 1000, available: null, imageUrl: null, matchesNeed: true,
);

void main() {
  test('catalog highlight must respect fitment, not merely proven family', () {
    final plan = qa.planFor('Pastillas para frenos Shimano');
    final items = [
      item('fits', 'PASTILLA PARA FRENOS SHIMANO'),
      item('wrong-system', 'PASTILLA PARA FRENOS TEKTRO'),
      item('unknown-system', 'PASTILLA SIN DATOS DE COMPATIBILIDAD'),
    ];
    final judgments = matchSupplierNeedCandidates(plan, [
      for (final row in items)
        SupplierPortalCatalogCandidate(code: row.productId, name: row.name,
          rowText: row.name, priceNet: 1000),
    ]);
    expect(judgments.singleWhere((row) => row.candidate.code == 'wrong-system').state,
      SupplierNeedMatchState.conflict,
      reason: 'the main matcher already knows that this row contradicts the specification');
    expect(judgments.singleWhere((row) => row.candidate.code == 'unknown-system').missingFields,
      contains('brake_system'));
    expect(supplierCatalogHighlightedProductIds(items: items, plan: plan),
      {'fits'}, reason: 'COINCIDE CON the need must not promote conflicts or unproven fitment');
  });
}
