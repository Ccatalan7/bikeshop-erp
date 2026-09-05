import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/inventory_models.dart';
import 'package:vinabike_erp/shared/models/supplier_variant_resolution.dart';
import 'package:vinabike_erp/shared/services/invoice_parser_service.dart';
import 'package:vinabike_erp/shared/services/ocr_catalog_unit_conversion.dart';

void main() {
  final product = Product(
      id: '20000000-0000-4000-8000-000000000001',
      tenantId: '10000000-0000-4000-8000-000000000001',
      name: 'Rotor',
      sku: 'AE0001',
      price: 5000,
      cost: 2500);
  final source = ParsedLineItem(
      description: 'Paquete de 2 rotores',
      quantity: 3,
      unitPrice: 10000,
      total: 30000,
      sourcePurchaseQuantity: 3,
      sourcePurchaseUnitPrice: 10000);

  test(
      'three purchased pairs become six individual catalog units without changing total',
      () {
    const conversion = OcrCatalogUnitConversion(
        unitsPerPurchase: 2, sourceQuantity: 3, sourceTotal: 30000);
    final line = conversion.applyToLine(source, product: product);
    expect(line.quantity, 6);
    expect(line.unitPrice, 5000);
    expect(line.quantity! * line.unitPrice!, line.total);
    expect(line.total, 30000);
    expect(line.sourcePurchaseQuantity, 3);
    expect(line.sourcePurchaseUnitPrice, 10000);
    expect(line.matchedProductId, product.id);
  });

  test('a catalog package stays three packages, not six pairs', () {
    const conversion = OcrCatalogUnitConversion(
        unitsPerPurchase: 1, sourceQuantity: 3, sourceTotal: 30000);
    final line = conversion.applyToLine(source, product: product);
    expect(line.quantity, 3);
    expect(line.unitPrice, 10000);
  });

  test('invalid quantity and money cannot enter a draft', () {
    for (final conversion in [
      const OcrCatalogUnitConversion(
          unitsPerPurchase: 0, sourceQuantity: 3, sourceTotal: 10),
      const OcrCatalogUnitConversion(
          unitsPerPurchase: -1, sourceQuantity: 3, sourceTotal: 10),
      const OcrCatalogUnitConversion(
          unitsPerPurchase: 2, sourceQuantity: double.nan, sourceTotal: 10),
      const OcrCatalogUnitConversion(
          unitsPerPurchase: 2, sourceQuantity: 3, sourceTotal: double.infinity),
      const OcrCatalogUnitConversion(
          unitsPerPurchase: 2, sourceQuantity: 3, sourceTotal: -1),
    ]) {
      expect(conversion.isValid, isFalse);
      expect(() => conversion.applyToLine(source, product: product),
          throwsFormatException);
    }
  });

  test('an unverified supplier rule cannot stand in for an explicit conversion',
      () {
    const conversion = OcrCatalogUnitConversion(
        unitsPerPurchase: 2, sourceQuantity: 3, sourceTotal: 30000);
    expect(
        () => conversion.applyToLine(source,
            product: product, resolution: SupplierVariantResolution.notFound()),
        throwsFormatException);
  });

  test(
      'a verified graph expands downstream once and retains the purchased quantity',
      () {
    const conversion = OcrCatalogUnitConversion(
        unitsPerPurchase: 2, sourceQuantity: 3, sourceTotal: 30000);
    final rule = _rule(product.id!, units: 2);
    expect(rule.isResolved, isTrue);
    final line =
        conversion.applyToLine(source, product: product, resolution: rule);
    expect(line.quantity, 3);
    expect(
        line.sourcePurchaseQuantity! *
            line.supplierResolution!.edges.single.catalogUnitsPerPurchase,
        6);
    expect(line.total, 30000);
    expect(
        () => conversion.applyToLine(source,
            product: product, resolution: _rule(product.id!, units: 4)),
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
