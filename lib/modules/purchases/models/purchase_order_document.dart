import 'package:vinabike_public_core/public_store/documents/purchase_order_pdf.dart';

import 'purchase_order_draft.dart';

/// **El pedido ya formateado, una sola vez, para los que lo dibujan.**
///
/// Vive en el núcleo compartido desde el 2026-11-22: lo dibujan la vista
/// previa y el PDF del asistente de compras, y también el servidor de la
/// tienda cuando el pedido abierto sale solo en la mañana (20261122030000).
export 'package:vinabike_public_core/public_store/documents/purchase_order_pdf.dart'
    show
        PurchaseOrderDocument,
        PurchaseOrderDocumentLine,
        PurchaseOrderDocumentSource;

/// El pedido que se está armando, como documento. Lo usan la vista previa en
/// pantalla y el PDF que se adjunta al chat del proveedor, para que lo
/// aprobado y lo enviado sean el mismo papel.
///
/// [buyerCity] es la ciudad del local (Álvarez 32, Viña del Mar), la misma
/// que lee el servidor de la ubicación de la tienda para el envío de la
/// mañana. Hasta el 2026-11-22 decía «Valparaíso, Chile».
PurchaseOrderDocument purchaseOrderDocumentFromDraft(
  PurchaseOrderDraft draft, {
  String? orderNumber,
  DateTime? issuedOn,
  String buyerName = 'Viñabike',
  String buyerCity = 'Viña del Mar',
}) {
  final contacto = <String>[
    if (draft.supplier.salesRepName != null) draft.supplier.salesRepName!,
    if (draft.supplier.salesRepPhone != null) draft.supplier.salesRepPhone!,
    if (draft.supplier.salesRepEmail != null) draft.supplier.salesRepEmail!,
  ];
  return PurchaseOrderDocument.compose(
    orderNumber: orderNumber,
    issuedOn: issuedOn ?? DateTime.now(),
    buyerName: buyerName,
    buyerCity: buyerCity,
    supplierName: draft.supplier.name,
    supplierLegalName: draft.supplier.legalName,
    supplierRut: draft.supplier.rut,
    supplierContact: contacto.isEmpty ? null : contacto.join(' · '),
    paymentTerms: draft.supplier.paymentTerms,
    lines: [
      for (final line in draft.orderedLines)
        PurchaseOrderDocumentSource(
          productId: line.productId,
          name: line.name,
          reference: PurchaseOrderDocument.referenceFor(
            brand: line.brand,
            sku: line.sku,
          ),
          quantity: line.quantity,
          unitCostNet: line.unitCostNet,
          costIsFromCatalog: line.costIsFromCatalog,
        ),
    ],
    note: draft.note,
  );
}
