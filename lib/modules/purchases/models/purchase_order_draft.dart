import 'dart:collection';

import 'supplier_catalog.dart';

/// **El pedido que se le va a mandar al proveedor, mientras se arma.**
///
/// Vive en memoria hasta que el operador lo guarda: apretar «Agregar» en un
/// producto no puede escribir en la base, porque mirar no es comprometerse.
///
/// El nombre importa. Lo que se le envía a un proveedor es un **pedido**, no su
/// factura: la factura la emite él cuando despacha. Adentro se convierte en un
/// documento de compra en borrador —el objeto que el ERP ya sabe recibir—, pero
/// la palabra que ve el proveedor es la correcta.
class PurchaseOrderDraft {
  PurchaseOrderDraft({
    required this.supplier,
    required Map<String, PurchaseOrderDraftLine> lines,
    this.note,
  }) : lines = UnmodifiableMapView(lines);

  final SupplierProfile supplier;
  final UnmodifiableMapView<String, PurchaseOrderDraftLine> lines;
  final String? note;

  /// El IVA del pedido. Chile: 19% sobre el neto. Un pedido a un proveedor
  /// extranjero no lo lleva, y por eso sale del tratamiento y no de una
  /// constante escrita en la pantalla.
  static const double ivaRate = 0.19;

  bool get isEmpty => lines.isEmpty;

  List<PurchaseOrderDraftLine> get orderedLines {
    final list = lines.values.toList()
      ..sort((a, b) => a.addedAt.compareTo(b.addedAt));
    return List.unmodifiable(list);
  }

  double get netTotal => lines.values
      .fold<double>(0, (total, line) => total + line.netAmount);

  double get ivaAmount => netTotal * ivaRate;

  double get total => netTotal + ivaAmount;

  double get unitCount =>
      lines.values.fold<double>(0, (total, line) => total + line.quantity);

  /// Cuántas líneas llevan un costo que **nadie pagó** —viene de la ficha del
  /// producto, no de una factura—. El operador tiene que verlo antes de mandar
  /// el pedido: pedir a un precio que el proveedor nunca cobró es cómo se
  /// llega a una factura que no cuadra.
  int get unverifiedCostLines =>
      lines.values.where((line) => line.costIsFromCatalog).length;

  PurchaseOrderDraft copyWith({
    Map<String, PurchaseOrderDraftLine>? lines,
    String? note,
  }) {
    return PurchaseOrderDraft(
      supplier: supplier,
      lines: lines ?? Map<String, PurchaseOrderDraftLine>.from(this.lines),
      note: note ?? this.note,
    );
  }
}

class PurchaseOrderDraftLine {
  PurchaseOrderDraftLine({
    required this.productId,
    required this.name,
    required this.sku,
    required this.brand,
    required this.quantity,
    required this.unitCostNet,
    required this.costIsFromCatalog,
    required this.addedAt,
  });

  /// Nace desde el catálogo del proveedor, con la cantidad en 1 y el costo
  /// propuesto: lo último pagado si existe, y si no el de ficha —marcado.
  /// **El pedido se arma sobre el eje elegido.** Proponerle al proveedor un
  /// precio que incluye nuestro flete es pedirle que cobre por algo que él no
  /// despacha; por eso el estado normal es sin flete.
  factory PurchaseOrderDraftLine.fromCatalog(
    SupplierCatalogItem item, {
    bool withFreight = false,
  }) {
    return PurchaseOrderDraftLine(
      productId: item.productId,
      name: item.name,
      sku: item.sku,
      brand: item.brand,
      quantity: 1,
      unitCostNet: item.suggestedUnitCostNet(withFreight: withFreight) ?? 0,
      costIsFromCatalog:
          item.suggestedCostIsCatalog(withFreight: withFreight),
      addedAt: DateTime.now(),
    );
  }

  final String productId;
  final String name;
  final String? sku;
  final String? brand;
  final double quantity;
  final double unitCostNet;

  /// El costo no salió de una factura. La pantalla lo rotula distinto y el
  /// pedido lo cuenta aparte.
  final bool costIsFromCatalog;

  /// Para conservar el orden en que se fueron agregando: el documento se lee
  /// como se armó, no alfabéticamente.
  final DateTime addedAt;

  double get netAmount => quantity * unitCostNet;

  PurchaseOrderDraftLine copyWith({double? quantity, double? unitCostNet}) {
    return PurchaseOrderDraftLine(
      productId: productId,
      name: name,
      sku: sku,
      brand: brand,
      quantity: quantity ?? this.quantity,
      unitCostNet: unitCostNet ?? this.unitCostNet,
      // Editar el costo a mano lo convierte en una decisión del operador, que
      // ya no es «de ficha»: la marca deja de aplicar.
      costIsFromCatalog:
          unitCostNet == null ? costIsFromCatalog : false,
      addedAt: addedAt,
    );
  }
}
