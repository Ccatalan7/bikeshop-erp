import '../../modules/inventory/models/inventory_models.dart';
import '../models/supplier_variant_resolution.dart';
import 'invoice_parser_service.dart';

/// An operator's explicit conversion from supplier purchases to catalog units.
/// A catalog unit may itself be a pair or a complete package. The supplier's
/// piece count is therefore never used as an implicit conversion.
final class OcrCatalogUnitConversion {
  const OcrCatalogUnitConversion({
    required this.unitsPerPurchase,
    required this.sourceQuantity,
    required this.sourceTotal,
  });

  final int unitsPerPurchase;
  final double sourceQuantity;
  final double sourceTotal;

  bool get isValid =>
      unitsPerPurchase > 0 &&
      unitsPerPurchase <= 1000000 &&
      sourceQuantity.isFinite &&
      sourceQuantity > 0 &&
      sourceTotal.isFinite &&
      sourceTotal >= 0 &&
      (sourceQuantity * unitsPerPurchase).isFinite;

  double get inventoryQuantity {
    if (!isValid) {
      throw const FormatException('Conversión de unidades inválida.');
    }
    return sourceQuantity * unitsPerPurchase;
  }

  double get unitCost => sourceTotal / inventoryQuantity;

  /// Reconciles a created product with its source line. A verified supplier
  /// graph owns expansion downstream; a local conversion expands exactly once.
  ParsedLineItem applyToLine(ParsedLineItem source,
      {required Product product, SupplierVariantResolution? resolution}) {
    if (!isValid || product.id == null) {
      throw const FormatException('Producto o conversión inválidos.');
    }
    if (resolution != null &&
        (!resolution.isResolved ||
            resolution.edges.length != 1 ||
            resolution.edges.single.productId != product.id ||
            resolution.edges.single.catalogUnitsPerPurchase !=
                unitsPerPurchase)) {
      throw const FormatException(
          'La regla no coincide con la unidad confirmada.');
    }
    return source.copyWith(
        description: product.name,
        sku: product.sku,
        existsInDatabase: true,
        matchedProductId: product.id,
        matchedProductName: product.name,
        currentStock: product.inventoryQty,
        quantity: resolution == null ? inventoryQuantity : sourceQuantity,
        unitPrice: resolution == null ? unitCost : sourceTotal / sourceQuantity,
        total: sourceTotal,
        sourcePurchaseQuantity: sourceQuantity,
        sourcePurchaseUnitPrice:
            source.sourcePurchaseUnitPrice ?? source.unitPrice,
        supplierResolution: resolution,
        clearSupplierResolution: resolution == null);
  }
}
