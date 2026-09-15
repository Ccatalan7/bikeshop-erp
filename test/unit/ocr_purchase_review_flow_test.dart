import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/inventory_models.dart';
import 'package:vinabike_erp/shared/services/invoice_parser_service.dart';
import 'package:vinabike_erp/shared/models/supplier_variant_resolution.dart';
import 'package:vinabike_erp/shared/services/ocr_purchase_review_flow.dart';

void main() {
  const pending = OcrPurchaseReviewDecision(
      identity: OcrProductIdentityDecision.undecided, selected: true);
  const chosen = OcrPurchaseReviewDecision(
      identity: OcrProductIdentityDecision.existing,
      selected: true,
      productId: '20000000-0000-4000-8000-000000000001');
  const fresh = OcrPurchaseReviewDecision(
      identity: OcrProductIdentityDecision.newProduct, selected: true);
  const confirmed = OcrPurchaseReviewDecision(
      identity: OcrProductIdentityDecision.existing,
      selected: true,
      productId: '20000000-0000-4000-8000-000000000001',
      amountsConfirmed: true);

  test('all identities must be decided before quantity review', () {
    expect(OcrPurchaseReviewFlow.identitiesComplete([chosen, pending, fresh]),
        isFalse);
    expect(OcrPurchaseReviewFlow.identitiesComplete([chosen, fresh]), isTrue);
    expect(OcrPurchaseReviewFlow.identitiesComplete([]), isFalse);
  });
  test('an existing-product label without a primary key is not a decision', () {
    expect(
        OcrPurchaseReviewFlow.identitiesComplete([
          const OcrPurchaseReviewDecision(
              identity: OcrProductIdentityDecision.existing, selected: true),
        ]),
        isFalse);
  });
  test('identity acceptance never also confirms purchase economics', () {
    expect(OcrPurchaseReviewFlow.amountsComplete([chosen, fresh]), isFalse);
    expect(OcrPurchaseReviewFlow.amountsComplete([confirmed, fresh]), isTrue);
    expect(
        OcrPurchaseReviewFlow.amountsComplete([confirmed, pending]), isFalse);
  });
  test('only-new batches can proceed directly to bulk product fields', () {
    expect(OcrPurchaseReviewFlow.identitiesComplete([fresh]), isTrue);
    expect(OcrPurchaseReviewFlow.amountsComplete([fresh]), isTrue);
  });
  test('a remembered rule must be applied or changed before amounts confirm',
      () {
    const ruled = OcrPurchaseReviewDecision(
        identity: OcrProductIdentityDecision.existing,
        selected: true,
        productId: '20000000-0000-4000-8000-000000000001',
        rulePending: true);
    const excludedRuled = OcrPurchaseReviewDecision(
        identity: OcrProductIdentityDecision.existing,
        selected: false,
        productId: '20000000-0000-4000-8000-000000000001',
        rulePending: true);
    expect(OcrPurchaseReviewFlow.pendingRuleCount([ruled, chosen, fresh]), 1);
    expect(OcrPurchaseReviewFlow.rulesSettled([ruled, chosen]), isFalse);
    expect(OcrPurchaseReviewFlow.rulesSettled([chosen, fresh]), isTrue);
    expect(OcrPurchaseReviewFlow.rulesSettled([excludedRuled, chosen]), isTrue,
        reason: 'an excluded row cannot hold the batch');
    expect(OcrPurchaseReviewFlow.rulesSettled(const []), isTrue);
  });
  test('excluded rows do not force an inventory identity or economic decision',
      () {
    const excluded = OcrPurchaseReviewDecision(
        identity: OcrProductIdentityDecision.undecided, selected: false);
    expect(
        OcrPurchaseReviewFlow.amountsComplete([confirmed, excluded]), isTrue);
  });

  final product = Product(
      id: '20000000-0000-4000-8000-000000000001',
      tenantId: 'tenant-test',
      name: 'Rotor individual 160mm',
      sku: 'AE0212',
      price: 9000,
      cost: 5000);
  final source = ParsedLineItem(
      description: 'Paquete de dos rotores',
      lineTitle: 'Paquete de dos rotores',
      quantity: 5,
      unitPrice: 9000,
      total: 40242,
      discount: 4758,
      sourcePurchaseQuantity: 5,
      sourcePurchaseUnitPrice: 9000,
      rawPackCount: 2);

  test('package evidence does not apply before the operator chooses units', () {
    final line = const OcrPurchaseAmounts(
            purchasedQuantity: 5, lineTotal: 40242, unitsPerPurchase: 1)
        .apply(source, product: product);
    expect(line.quantity, 5);
    expect(line.total, 40242);
    expect(line.rawPackCount, 2);
  });
  test('confirmed pack units keep the landed total and do not discount twice',
      () {
    final line = const OcrPurchaseAmounts(
            purchasedQuantity: 5, lineTotal: 40242, unitsPerPurchase: 2)
        .apply(source, product: product);
    expect(line.quantity, 10);
    expect(line.unitPrice, 4024.2);
    expect(line.quantity! * line.unitPrice!, closeTo(line.total!, .0001));
    expect(line.discount, 0);
    expect(line.matchedProductId, product.id);
    expect(line.sourcePurchaseQuantity, 5);
    expect(line.sourcePurchaseUnitPrice, 9000);
    expect(line.lineTitle, source.lineTitle);
  });
  test('edited source quantity and costs become the confirmed invoice values',
      () {
    final line = const OcrPurchaseAmounts(
            purchasedQuantity: 3, lineTotal: 18000, unitsPerPurchase: 2)
        .apply(source, product: product);
    expect(line.quantity, 6);
    expect(line.unitPrice, 3000);
    expect(line.total, 18000);
  });
  test('a supplier graph must include the identity chosen by the operator', () {
    const amounts = OcrPurchaseAmounts(
        purchasedQuantity: 3, lineTotal: 12000, unitsPerPurchase: 1);
    expect(
        () => amounts.apply(source,
            product: product,
            resolution:
                _rule('20000000-0000-4000-8000-000000000002', units: 2)),
        throwsFormatException);
    final result = amounts.apply(source,
        product: product, resolution: _rule(product.id!, units: 2));
    expect(result.quantity, 3);
    expect(result.unitPrice, 4000);
    expect(result.total, 12000);
    expect(result.sourcePurchaseQuantity, 3);
    expect(result.supplierResolution!.edges.single.catalogUnitsPerPurchase, 2);
    expect(result.matchedProductId, product.id);
  });

  test('invalid amounts and a nonexistent catalog identity cannot apply', () {
    for (final amounts in [
      const OcrPurchaseAmounts(
          purchasedQuantity: 0, lineTotal: 100, unitsPerPurchase: 1),
      const OcrPurchaseAmounts(
          purchasedQuantity: 2, lineTotal: -1, unitsPerPurchase: 1),
      const OcrPurchaseAmounts(
          purchasedQuantity: 2,
          lineTotal: double.infinity,
          unitsPerPurchase: 1),
      const OcrPurchaseAmounts(
          purchasedQuantity: 2, lineTotal: 100, unitsPerPurchase: 0),
    ]) {
      expect(
          () => amounts.apply(source, product: product), throwsFormatException);
    }
    final draft = Product(
        tenantId: 'tenant-test',
        name: 'Text without identity',
        sku: 'AE0000',
        price: 100,
        cost: 50);
    expect(
        () => const OcrPurchaseAmounts(
                purchasedQuantity: 1, lineTotal: 100, unitsPerPurchase: 1)
            .apply(source, product: draft),
        throwsFormatException);
  });
}

SupplierVariantResolution _rule(String productId, {required int units}) {
  final option = SupplierOptionEvidence(
      variantKey: 'sku:unit-proof', packCount: 2, rawUnitToken: 'pcs');
  return SupplierVariantResolution.fromLookupJson({
    'status': 'resolved',
    'authoritative': true,
    'id': '10000000-0000-4000-8000-000000000011',
    'tenant_id': '10000000-0000-4000-8000-000000000001',
    'supplier_id': '10000000-0000-4000-8000-000000000002',
    'listing_id': 'listing-unit-proof',
    'variant_key': option.variantKey.value,
    'revision_number': 1,
    'state': 'active',
    'resolution_kind': 'homogeneous',
    'option_evidence_hash': option.sha256Hex,
    'option_pack_count': 2,
    'option_unit_class': 'piece',
    'pack_evidence_conflict': false,
    'edge_set_hash': 'a' * 64,
    'operation_id': '10000000-0000-4000-8000-000000000003',
    'request_fingerprint': 'b' * 64,
    'decision_source': 'operator_confirmed',
    'decision_evidence_hash': 'b' * 64,
    'decision_evidence': {'confirmation_surface': 'purchase_invoice_ocr'},
    'edges': [
      {
        'edge_id': '40000000-0000-4000-8000-000000000001',
        'edge_ordinal': 1,
        'product_id': productId,
        'catalog_units_per_purchase': units,
        'allocation_ratio': 1.0,
        'component_role': 'homogeneous'
      }
    ],
  });
}
