import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/purchases/models/purchase_invoice.dart';
import 'package:vinabike_erp/modules/purchases/pages/purchase_invoice_form_page.dart';
import 'package:vinabike_erp/shared/models/product.dart';
import 'package:vinabike_erp/shared/models/supplier_variant_resolution.dart';
import 'package:vinabike_erp/shared/models/tax_treatment.dart';

void main() {
  group('prepared supplier resolution purchase lines', () {
    test('expands components with exact allocation and complete provenance',
        () {
      final prepared = _preparedSource(
        sourceQuantity: 3,
        sourceTotalMinor: 10001,
        components: const <_ComponentFixture>[
          _ComponentFixture(
            id: _componentOneId,
            edgeId: _edgeOneId,
            productId: _productOneId,
            position: 1,
            units: 2,
            quantity: 6,
            ratio: 0.4,
            allocatedMinor: 4000,
            role: 'front',
          ),
          _ComponentFixture(
            id: _componentTwoId,
            edgeId: _edgeTwoId,
            productId: _productTwoId,
            position: 2,
            units: 1,
            quantity: 3,
            ratio: 0.6,
            allocatedMinor: 6001,
            role: 'rear',
          ),
        ],
      );

      final lines = buildPreparedSupplierPurchaseLines(
        prepared: prepared,
        productsById: <String, Product>{
          _productOneId: _product(_productOneId, 'Delantero', 'AE0009'),
          _productTwoId: _product(_productTwoId, 'Trasero', 'AE0010'),
        },
      );

      expect(lines, hasLength(2));
      expect(lines.map((line) => line.quantity), <double>[6, 3]);
      expect(
        lines.map((line) => (line.quantity * line.unitCost).round()),
        <int>[4000, 6001],
      );
      expect(
        lines.map((line) => line.allocatedLineTotalMinor).reduce(
              (left, right) => left! + right!,
            ),
        10001,
      );

      for (final line in lines) {
        expect(line.resolutionApplicationId, _applicationId);
        expect(line.resolutionRevisionId, _revisionId);
        expect(line.sourceLineKey, _sourceLineKey);
        expect(line.sourcePurchaseQuantity, 3);
        expect(line.sourceLineTotalMinor, 10001);
        expect(line.sourceOrderNumbers, const <String>['order-1']);
        expect(line.supplierListingId, 'listing-1');
        expect(line.supplierVariantKey, 'sku:variant-1');
        expect(line.optionEvidenceHash, isNotNull);
        expect(line.sourceTitle, 'Kit delantero y trasero');
        expect(line.selectedOption, '2PCS');
        expect(line.rawPackCount, 2);
        expect(line.rawUnitToken, 'pcs');
        expect(line.rawPackEvidenceConflict, isFalse);
        expect(line.sourceEvidenceSnapshot, prepared.sourceSnapshot);
        expect(line.discount, 0);
        expect(line.hasCompleteSupplierResolutionProvenance, isTrue);
        expect(isPurchaseSupplierResolutionLineLocked(line), isTrue);
      }
      expect(hasPurchaseSupplierResolutionLines(lines), isTrue);
    });

    test('keeps a resolved set parent as one invoice line', () {
      final prepared = _preparedSource(
        sourceQuantity: 2,
        sourceTotalMinor: 9000,
        components: const <_ComponentFixture>[
          _ComponentFixture(
            id: _componentOneId,
            edgeId: _edgeOneId,
            productId: _productOneId,
            position: 1,
            units: 1,
            quantity: 2,
            ratio: 1,
            allocatedMinor: 9000,
            role: 'catalog_set',
          ),
        ],
      );
      final setProduct = _product(
        _productOneId,
        'Juego mazas',
        'AE0100',
        isSet: true,
      );

      final lines = buildPreparedSupplierPurchaseLines(
        prepared: prepared,
        productsById: <String, Product>{_productOneId: setProduct},
      );

      expect(lines, hasLength(1));
      expect(lines.single.productId, setProduct.id);
      expect(lines.single.quantity, 2);
      expect(lines.single.unitCost, 4500);
    });

    test('rejects an inactive graph edge and preserves decimal text', () {
      final prepared = _preparedSource(
        sourceQuantity: 1,
        sourceTotalMinor: 5833625,
        components: const <_ComponentFixture>[
          _ComponentFixture(
            id: _componentOneId,
            edgeId: _edgeOneId,
            productId: _productOneId,
            position: 1,
            units: 1,
            quantity: 1,
            ratio: 1,
            allocatedMinor: 5833625,
            role: 'catalog_product',
          ),
        ],
      );

      expect(
        () => buildPreparedSupplierPurchaseLines(
          prepared: prepared,
          productsById: <String, Product>{
            _productOneId: _product(
              _productOneId,
              'Inactivo',
              'AE9999',
              isActive: false,
            ),
          },
        ),
        throwsStateError,
      );
      expect(purchaseLineDecimalText(5833.625), '5833.625');
      expect(purchaseLineDecimalText(5833), '5833');
      expect(
        isPurchaseSupplierResolutionLineLocked(
          PurchaseInvoiceItem(productId: _productOneId, unitCost: 1),
        ),
        isFalse,
      );
      expect(
        hasPurchaseSupplierResolutionLines(<PurchaseInvoiceItem>[
          PurchaseInvoiceItem(productId: _productOneId, unitCost: 1),
        ]),
        isFalse,
      );
    });

    test('preflight accepts only an empty zero-discount no-tax draft', () {
      final placeholder = PurchaseInvoiceItem(
        productId: '',
        productName: '',
        quantity: 1,
        unitCost: 0,
      );

      expect(
        purchaseSupplierResolutionApplyBlockReason(
          hasAuthoritativeGraph: true,
          existingLines: <PurchaseInvoiceItem>[placeholder],
          globalDiscountText: '0',
          currentTaxTreatment: TaxTreatment.noTax,
          targetTaxTreatment: TaxTreatment.noTax,
        ),
        isNull,
      );
      expect(
        purchaseSupplierResolutionApplyBlockReason(
          hasAuthoritativeGraph: true,
          existingLines: <PurchaseInvoiceItem>[
            PurchaseInvoiceItem(
              productId: _productOneId,
              productName: 'Producto previo',
              unitCost: 100,
            ),
          ],
          globalDiscountText: '0',
          currentTaxTreatment: TaxTreatment.noTax,
          targetTaxTreatment: TaxTreatment.noTax,
        ),
        contains('borrador vacío'),
      );
      expect(
        purchaseSupplierResolutionApplyBlockReason(
          hasAuthoritativeGraph: true,
          existingLines: <PurchaseInvoiceItem>[placeholder],
          globalDiscountText: '2,5',
          currentTaxTreatment: TaxTreatment.noTax,
          targetTaxTreatment: TaxTreatment.noTax,
        ),
        contains('descuento global en cero'),
      );
      expect(
        purchaseSupplierResolutionApplyBlockReason(
          hasAuthoritativeGraph: true,
          existingLines: <PurchaseInvoiceItem>[placeholder],
          globalDiscountText: '0',
          currentTaxTreatment: TaxTreatment.taxIncluded,
          targetTaxTreatment: TaxTreatment.noTax,
        ),
        contains('sin IVA'),
      );
      expect(
        purchaseSupplierResolutionApplyBlockReason(
          hasAuthoritativeGraph: false,
          existingLines: <PurchaseInvoiceItem>[
            PurchaseInvoiceItem(
              productId: _productOneId,
              productName: 'Flujo OCR legado',
              unitCost: 100,
            ),
          ],
          globalDiscountText: '10',
          currentTaxTreatment: TaxTreatment.taxIncluded,
          targetTaxTreatment: TaxTreatment.taxIncluded,
        ),
        isNull,
      );
    });
  });
}

SupplierInvoiceSourceResolution _preparedSource({
  required double sourceQuantity,
  required int sourceTotalMinor,
  required List<_ComponentFixture> components,
}) {
  final evidence = SupplierOptionEvidence(
    variantKey: 'sku:variant-1',
    packCount: 2,
    rawUnitToken: 'pcs',
  );
  final snapshot = <String, dynamic>{
    'listing_id': 'listing-1',
    'variant_key': 'sku:variant-1',
    'option_evidence_hash': evidence.sha256Hex,
    'source_row_index': 0,
    'source_line_key': _sourceLineKey,
    'source_document_date': '2025-10-20',
    'source_order_numbers': const <String>['order-1'],
    'source_title': 'Kit delantero y trasero',
    'selected_option': '2PCS',
    'raw_pack_count': 2,
    'raw_unit_code': 'pcs',
    'option_unit_class': 'piece',
    'pack_evidence_conflict': false,
    'source_purchase_quantity': sourceQuantity,
    'source_line_total_minor': sourceTotalMinor,
    'currency_code': 'CLP',
  };
  return SupplierInvoiceSourceResolution.fromJson(<String, dynamic>{
    'id': _applicationId,
    'source_line_key': _sourceLineKey,
    'source_row_index': 0,
    'supplier_resolution_revision_id': _revisionId,
    'supplier_listing_id': 'listing-1',
    'supplier_variant_key': 'sku:variant-1',
    'option_evidence_hash': evidence.sha256Hex,
    'source_order_numbers': const <String>['order-1'],
    'source_title': 'Kit delantero y trasero',
    'selected_option': '2PCS',
    'raw_pack_count': 2,
    'raw_unit_token': 'pcs',
    'option_unit_class': 'piece',
    'pack_evidence_conflict': false,
    'source_snapshot': snapshot,
    'source_snapshot_hash': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'source_purchase_quantity': sourceQuantity,
    'source_line_total_minor': sourceTotalMinor,
    'currency_code': 'CLP',
    'operation_id': _operationId,
    'replayed': false,
    'components': components
        .map((component) => component.toJson())
        .toList(growable: false),
  });
}

Product _product(
  String id,
  String name,
  String sku, {
  bool isSet = false,
  bool isActive = true,
}) {
  return Product(
    id: id,
    name: name,
    sku: sku,
    price: 0,
    cost: 0,
    stockQuantity: 0,
    category: ProductCategory.other,
    tags: const <String>[],
    unit: ProductUnit.unit,
    weight: 0,
    trackStock: true,
    isActive: isActive,
    isSet: isSet,
    createdAt: DateTime.utc(2026, 8, 12),
    updatedAt: DateTime.utc(2026, 8, 12),
  );
}

class _ComponentFixture {
  const _ComponentFixture({
    required this.id,
    required this.edgeId,
    required this.productId,
    required this.position,
    required this.units,
    required this.quantity,
    required this.ratio,
    required this.allocatedMinor,
    required this.role,
  });

  final String id;
  final String edgeId;
  final String productId;
  final int position;
  final int units;
  final double quantity;
  final double ratio;
  final int allocatedMinor;
  final String role;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'revision_edge_id': edgeId,
        'edge_ordinal': position,
        'product_id': productId,
        'catalog_units_per_purchase': units,
        'resolved_quantity': quantity,
        'allocation_ratio': ratio,
        'allocated_line_total_minor': allocatedMinor,
        'component_role': role,
      };
}

const _applicationId = '10000000-0000-4000-8000-000000000001';
const _revisionId = '10000000-0000-4000-8000-000000000002';
const _operationId = '10000000-0000-4000-8000-000000000003';
const _componentOneId = '10000000-0000-4000-8000-000000000004';
const _componentTwoId = '10000000-0000-4000-8000-000000000005';
const _edgeOneId = '10000000-0000-4000-8000-000000000006';
const _edgeTwoId = '10000000-0000-4000-8000-000000000007';
const _productOneId = '10000000-0000-4000-8000-000000000008';
const _productTwoId = '10000000-0000-4000-8000-000000000009';
const _sourceLineKey =
    'supplier-line-v1:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
