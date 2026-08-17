import 'dart:collection';

import '../../../shared/models/product.dart';
import 'purchase_invoice.dart';

class PurchaseInvoiceDraftLineSeed {
  const PurchaseInvoiceDraftLineSeed({
    required this.productId,
    required this.productName,
    required this.quantity,
    this.sourceNeedId,
    this.productSku,
    this.purchaseTreatment = PurchaseTreatment.inventory,
  });

  final String productId;
  final String productName;
  final String? sourceNeedId;
  final String? productSku;
  final PurchaseTreatment purchaseTreatment;
  final double quantity;

  Map<String, dynamic> toFormJson() => {
        'product_id': productId,
        'product_name': productName,
        if (sourceNeedId != null) 'source_need_id': sourceNeedId,
        'product_sku': productSku,
        'purchase_treatment': purchaseTreatment.dbValue,
        'suggested_quantity': quantity,
      };
}

class PurchaseInvoiceDraftSeed {
  PurchaseInvoiceDraftSeed({
    this.supplierId,
    this.sourceDocumentKind = PurchaseSourceDocumentKind.defaultCode,
    List<PurchaseInvoiceDraftLineSeed> lines = const [],
  }) : lines = UnmodifiableListView(lines);

  final String? supplierId;
  final String sourceDocumentKind;
  final UnmodifiableListView<PurchaseInvoiceDraftLineSeed> lines;
}
