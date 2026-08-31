import 'dart:collection';

import 'purchase_invoice.dart';
import 'purchase_order_draft.dart';

/// Un pedido ya guardado, como se lista en la ficha del proveedor.
///
/// **Es una vista de un documento de compra real**, no de otra tabla. El pedido
/// vive en `purchase_invoices` con estado `draft` desde el primer guardado: la
/// misma fila que después va a llevar el folio y la factura del proveedor.
/// Esta clase existe sólo para que la tira de la ficha no tenga que conocer el
/// modelo completo.
class PurchaseOrderSummary {
  const PurchaseOrderSummary({
    required this.orderId,
    required this.orderNumber,
    required this.status,
    required this.supplierId,
    required this.supplierName,
    required this.orderDate,
    required this.netTotal,
    required this.ivaAmount,
    required this.total,
    required this.lineCount,
    required this.unitCount,
  });

  final String orderId;
  final String orderNumber;
  final String status;
  final String? supplierId;
  final String supplierName;
  final DateTime? orderDate;
  final double netTotal;
  final double ivaAmount;
  final double total;
  final int lineCount;
  final double unitCount;

  bool get isDraft => status == 'draft';
  bool get wasSent => status == 'sent';

  /// La palabra que ve el operador. «ordered» no dice nada en una lista; lo que
  /// necesita saber es si el proveedor ya lo tiene.
  String get statusLabel {
    switch (status) {
      case 'draft':
        return 'Borrador';
      case 'sent':
        return 'Enviado';
      case 'confirmed':
        return 'Confirmado';
      case 'received':
        return 'Recibido';
      case 'paid':
        return 'Pagado';
      case 'cancelled':
        return 'Anulado';
      default:
        return status;
    }
  }

  /// Desde el documento de compra real. El estado se traduce a lo que el
  /// operador necesita saber: si el proveedor ya lo tiene.
  factory PurchaseOrderSummary.fromInvoice(PurchaseInvoice invoice) {
    return PurchaseOrderSummary(
      orderId: invoice.id ?? '',
      orderNumber: invoice.invoiceNumber,
      status: invoice.status.name,
      supplierId: invoice.supplierId,
      supplierName: invoice.supplierName ?? 'Proveedor',
      orderDate: invoice.date,
      netTotal: invoice.subtotal,
      ivaAmount: invoice.ivaAmount,
      total: invoice.total,
      lineCount: invoice.items.length,
      unitCount:
          invoice.items.fold<double>(0, (total, item) => total + item.quantity),
    );
  }

  factory PurchaseOrderSummary.fromJson(Map<String, dynamic> json) {
    return PurchaseOrderSummary(
      orderId: json['orderId']?.toString() ?? '',
      orderNumber: json['orderNumber']?.toString() ?? 'Sin número',
      status: json['status']?.toString() ?? 'draft',
      supplierId: json['supplierId']?.toString(),
      supplierName: json['supplierName']?.toString() ?? 'Proveedor',
      orderDate: DateTime.tryParse(json['orderDate']?.toString() ?? ''),
      netTotal: (json['netTotal'] as num?)?.toDouble() ?? 0,
      ivaAmount: (json['ivaAmount'] as num?)?.toDouble() ?? 0,
      total: (json['total'] as num?)?.toDouble() ?? 0,
      lineCount: (json['lineCount'] as num?)?.toInt() ?? 0,
      unitCount: (json['unitCount'] as num?)?.toDouble() ?? 0,
    );
  }
}

class PurchaseOrderPage {
  PurchaseOrderPage({
    required List<PurchaseOrderSummary> items,
    required this.total,
    required this.offset,
  }) : items = UnmodifiableListView(items);

  final UnmodifiableListView<PurchaseOrderSummary> items;
  final int total;
  final int offset;

  bool get isEmpty => items.isEmpty;
  bool get hasMore => offset + items.length < total;

  List<PurchaseOrderSummary> get drafts =>
      items.where((order) => order.isDraft).toList(growable: false);

  factory PurchaseOrderPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    return PurchaseOrderPage(
      items: raw is List
          ? raw
              .whereType<Map>()
              .map((item) =>
                  PurchaseOrderSummary.fromJson(item.cast<String, dynamic>()))
              .toList(growable: false)
          : const <PurchaseOrderSummary>[],
      total: (json['total'] as num?)?.toInt() ?? 0,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Las líneas de un pedido guardado, listas para volver al borrador en pantalla.
class PurchaseOrderStoredLine {
  const PurchaseOrderStoredLine({
    required this.productId,
    required this.name,
    required this.sku,
    required this.brand,
    required this.quantity,
    required this.unitCostNet,
  });

  final String? productId;
  final String name;
  final String? sku;
  final String? brand;
  final double quantity;
  final double unitCostNet;

  /// Vuelve a ser una línea editable. El costo guardado manda: es el que el
  /// operador ya decidió, no el que el catálogo propondría de nuevo hoy.
  PurchaseOrderDraftLine toDraftLine(DateTime addedAt) {
    return PurchaseOrderDraftLine(
      productId: productId ?? name,
      name: name,
      sku: sku,
      brand: brand,
      quantity: quantity,
      unitCostNet: unitCostNet,
      costIsFromCatalog: false,
      addedAt: addedAt,
    );
  }

  factory PurchaseOrderStoredLine.fromJson(Map<String, dynamic> json) {
    return PurchaseOrderStoredLine(
      productId: json['productId']?.toString(),
      name: json['name']?.toString() ?? 'Producto',
      sku: json['sku']?.toString(),
      brand: json['brand']?.toString(),
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      unitCostNet: (json['unitCostNet'] as num?)?.toDouble() ?? 0,
    );
  }
}
