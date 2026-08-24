import 'dart:collection';

import '../../../shared/utils/chilean_utils.dart';
import 'purchase_order_draft.dart';

/// **El pedido ya formateado, una sola vez, para los dos que lo dibujan.**
///
/// La vista previa en pantalla y el PDF que se le manda al proveedor tienen que
/// decir exactamente lo mismo. Si cada uno formatea por su cuenta, el día que
/// alguien cambie un redondeo el operador aprueba una cosa y el proveedor
/// recibe otra — y eso se descubre en la factura, no en la pantalla.
///
/// Por eso acá no hay widgets ni `pw.` de ninguna clase: sólo los textos
/// definitivos. Quien dibuja elige tipografía y color; los números ya están
/// decididos.
class PurchaseOrderDocument {
  PurchaseOrderDocument({
    required this.orderNumber,
    required this.isDraft,
    required this.issuedOn,
    required this.buyerName,
    required this.buyerCity,
    required this.supplierName,
    required this.supplierLegalName,
    required this.supplierRut,
    required this.supplierContact,
    required this.paymentTerms,
    required List<PurchaseOrderDocumentLine> lines,
    required this.netTotal,
    required this.ivaAmount,
    required this.total,
    required this.unitCount,
    required this.unverifiedCostLines,
    required this.note,
  }) : lines = UnmodifiableListView(lines);

  /// «Sin número» mientras es borrador. Inventarle uno antes de guardarlo haría
  /// que el operador cite en un mensaje un folio que no existe en la base.
  final String orderNumber;
  final bool isDraft;
  final String issuedOn;

  final String buyerName;
  final String buyerCity;

  final String supplierName;
  final String? supplierLegalName;
  final String? supplierRut;
  final String? supplierContact;
  final String? paymentTerms;

  final UnmodifiableListView<PurchaseOrderDocumentLine> lines;

  final String netTotal;
  final String ivaAmount;
  final String total;
  final String unitCount;

  /// Cuántas líneas llevan un costo que nadie pagó. Se publica **en el
  /// documento**, no sólo en la pantalla: el operador tiene que verlo en lo
  /// mismo que está por aprobar.
  final int unverifiedCostLines;

  final String? note;

  bool get isEmpty => lines.isEmpty;

  static PurchaseOrderDocument fromDraft(
    PurchaseOrderDraft draft, {
    String? orderNumber,
    DateTime? issuedOn,
    String buyerName = 'Viñabike',
    String buyerCity = 'Valparaíso, Chile',
  }) {
    final fecha = issuedOn ?? DateTime.now();
    final contacto = <String>[
      if (draft.supplier.salesRepName != null) draft.supplier.salesRepName!,
      if (draft.supplier.salesRepPhone != null) draft.supplier.salesRepPhone!,
      if (draft.supplier.salesRepEmail != null) draft.supplier.salesRepEmail!,
    ];
    return PurchaseOrderDocument(
      orderNumber: orderNumber ?? 'Sin número',
      isDraft: orderNumber == null,
      issuedOn: ChileanUtils.formatDate(fecha),
      buyerName: buyerName,
      buyerCity: buyerCity,
      supplierName: draft.supplier.name,
      supplierLegalName:
          draft.supplier.legalName == draft.supplier.name
              ? null
              : draft.supplier.legalName,
      supplierRut: draft.supplier.rut,
      supplierContact: contacto.isEmpty ? null : contacto.join(' · '),
      paymentTerms: draft.supplier.paymentTerms,
      lines: [
        for (final line in draft.orderedLines)
          PurchaseOrderDocumentLine(
            productId: line.productId,
            name: line.name,
            reference: _reference(line),
            quantity: _quantity(line.quantity),
            unitCost: ChileanUtils.formatCurrency(line.unitCostNet),
            netAmount: ChileanUtils.formatCurrency(line.netAmount),
            costIsFromCatalog: line.costIsFromCatalog,
          ),
      ],
      netTotal: ChileanUtils.formatCurrency(draft.netTotal),
      ivaAmount: ChileanUtils.formatCurrency(draft.ivaAmount),
      total: ChileanUtils.formatCurrency(draft.total),
      unitCount: _quantity(draft.unitCount),
      unverifiedCostLines: draft.unverifiedCostLines,
      note: draft.note,
    );
  }

  static String? _reference(PurchaseOrderDraftLine line) {
    final partes = <String>[
      if (line.brand != null) line.brand!,
      if (line.sku != null) 'SKU ${line.sku}',
    ];
    return partes.isEmpty ? null : partes.join(' · ');
  }

  static String _quantity(double value) =>
      value == value.roundToDouble() ? value.round().toString() : '$value';
}

class PurchaseOrderDocumentLine {
  const PurchaseOrderDocumentLine({
    required this.productId,
    required this.name,
    required this.reference,
    required this.quantity,
    required this.unitCost,
    required this.netAmount,
    required this.costIsFromCatalog,
  });

  final String productId;
  final String name;
  final String? reference;
  final String quantity;
  final String unitCost;
  final String netAmount;
  final bool costIsFromCatalog;
}
