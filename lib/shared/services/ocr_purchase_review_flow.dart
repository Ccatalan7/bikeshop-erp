import '../../modules/inventory/models/inventory_models.dart';
import '../models/supplier_variant_resolution.dart';
import 'invoice_parser_service.dart';
import 'ocr_catalog_unit_conversion.dart';

enum OcrPurchaseReviewStep { identify, amounts, newProducts }

enum OcrProductIdentityDecision { undecided, existing, newProduct }

/// Identity is a local operator decision. It neither applies supplier rules
/// nor implies that amounts have been reviewed or a product has been created.
class OcrPurchaseReviewDecision {
  const OcrPurchaseReviewDecision({
    required this.identity,
    required this.selected,
    this.productId,
    this.amountsConfirmed = false,
    this.rulePending = false,
  });

  final OcrProductIdentityDecision identity;
  final bool selected;
  final String? productId;
  final bool amountsConfirmed;

  /// A rule from an earlier purchase of this listing variant exists and the
  /// operator has neither applied it nor changed it. The batch cannot confirm
  /// amounts over a decision it is silently overriding.
  final bool rulePending;

  bool get identified => switch (identity) {
        OcrProductIdentityDecision.existing => productId?.isNotEmpty == true,
        OcrProductIdentityDecision.newProduct => true,
        OcrProductIdentityDecision.undecided => false,
      };
}

class OcrPurchaseReviewFlow {
  const OcrPurchaseReviewFlow._();

  static bool identitiesComplete(Iterable<OcrPurchaseReviewDecision> lines) {
    final selected = lines.where((line) => line.selected).toList();
    return selected.isNotEmpty && selected.every((line) => line.identified);
  }

  static bool amountsComplete(Iterable<OcrPurchaseReviewDecision> lines) =>
      identitiesComplete(lines) &&
      lines.where((line) => line.selected).every((line) =>
          line.identity != OcrProductIdentityDecision.existing ||
          line.amountsConfirmed);

  /// Rows linked to an existing product whose earlier-purchase rule is still
  /// waiting for the operator to apply or change it.
  static int pendingRuleCount(Iterable<OcrPurchaseReviewDecision> lines) =>
      lines
          .where((line) =>
              line.selected &&
              line.identity == OcrProductIdentityDecision.existing &&
              line.rulePending)
          .length;

  /// The earlier decision is visible and either kept or changed on purpose;
  /// only then may the batch confirm amounts. This is what makes «la regla de
  /// compras anteriores» a decision the operator can see and revise, never one
  /// the batch button skips.
  static bool rulesSettled(Iterable<OcrPurchaseReviewDecision> lines) =>
      pendingRuleCount(lines) == 0;
}

/// Purchase economics reviewed after selecting a real catalog product.
/// The supplier quantity and landed line total are independent of catalog
/// pack units. A verified graph is expanded only by the invoice kernel.
class OcrPurchaseAmounts {
  const OcrPurchaseAmounts({
    required this.purchasedQuantity,
    required this.lineTotal,
    required this.unitsPerPurchase,
  });

  final double purchasedQuantity;
  final double lineTotal;
  final int unitsPerPurchase;

  OcrCatalogUnitConversion get conversion => OcrCatalogUnitConversion(
        unitsPerPurchase: unitsPerPurchase,
        sourceQuantity: purchasedQuantity,
        sourceTotal: lineTotal,
      );

  bool get isValid => conversion.isValid;

  ParsedLineItem apply(ParsedLineItem source,
      {required Product product, SupplierVariantResolution? resolution}) {
    if (!isValid ||
        product.id?.isNotEmpty != true ||
        !product.isActive ||
        product.isService) {
      throw const FormatException(
          'Revisa el producto, la cantidad y el costo.');
    }
    // The line total is the landed, discounted amount. Its displayed unit cost
    // already contains that discount, so it must not be deducted a second time.
    final reviewed = source.copyWith(
      quantity: purchasedQuantity,
      unitPrice: lineTotal / purchasedQuantity,
      total: lineTotal,
      discount: 0,
      discountRate: 0,
      discountInferred: false,
      sourcePurchaseQuantity: purchasedQuantity,
      wasAutoAdjusted: false,
    );
    if (resolution == null) {
      return conversion.applyToLine(reviewed, product: product);
    }
    if (!resolution.isResolved ||
        !resolution.edges.any((edge) => edge.productId == product.id)) {
      throw const FormatException('La regla no pertenece al producto elegido.');
    }
    return reviewed.copyWith(
      description: product.name,
      sku: product.sku,
      existsInDatabase: true,
      matchedProductId: product.id,
      matchedProductName: product.name,
      currentStock: product.inventoryQty,
      supplierResolution: resolution,
    );
  }
}
