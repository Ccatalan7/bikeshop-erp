import 'dart:collection';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../shared/utils/chilean_utils.dart';
import 'store_document_style.dart';

/// **El pedido que se le manda a un proveedor, ya formateado, una sola vez.**
///
/// Lo dibujan dos: el asistente de compras del ERP (la vista previa y el PDF
/// que adjunta al chat del proveedor) y el servidor de la tienda, que dibuja
/// el del pedido abierto que sale solo en la mañana (20261122030000) con la
/// lectura de la base ([PurchaseOrderDocument.fromProjection]). Vive en el
/// núcleo para que los dos digan lo mismo: si cada uno formateara por su
/// cuenta, el día que alguien cambie un redondeo el operador aprueba una cosa
/// y el proveedor recibe otra, y eso se descubre en la factura.
///
/// No es la factura de compra: ésa la emite el proveedor cuando despacha.
/// Acá no hay widgets: sólo los textos definitivos; quien dibuja elige
/// tipografía y color.
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
    this.logoUrl,
  }) : lines = UnmodifiableListView(lines);

  /// Arma el documento desde los valores crudos: el único lugar donde se
  /// formatean los números, la fecha, la cantidad y las condiciones de pago.
  ///
  /// Sin [orderNumber] es un borrador «sin número»: inventarle uno antes de
  /// guardarlo haría que el operador cite un folio que no existe en la base.
  factory PurchaseOrderDocument.compose({
    required String? orderNumber,
    required DateTime issuedOn,
    required String buyerName,
    String? buyerCity,
    required String supplierName,
    String? supplierLegalName,
    String? supplierRut,
    String? supplierContact,
    String? paymentTerms,
    required List<PurchaseOrderDocumentSource> lines,
    String? note,
    String? logoUrl,
  }) {
    final net = lines.fold<double>(0, (sum, line) => sum + line.netAmount);
    final iva = net * ivaRate;
    final units = lines.fold<double>(0, (sum, line) => sum + line.quantity);
    final legal = _text(supplierLegalName);
    return PurchaseOrderDocument(
      orderNumber: orderNumber ?? 'Sin número',
      isDraft: orderNumber == null,
      issuedOn: storeDocumentDate(issuedOn),
      buyerName: buyerName,
      buyerCity: _text(buyerCity),
      supplierName: supplierName,
      supplierLegalName:
          legal == null || legal.toLowerCase() == supplierName.toLowerCase()
          ? null
          : legal,
      supplierRut: _text(supplierRut),
      supplierContact: _text(supplierContact),
      paymentTerms: paymentTermsLabel(paymentTerms),
      lines: [
        for (final line in lines)
          PurchaseOrderDocumentLine(
            productId: line.productId,
            name: line.name,
            reference: line.reference,
            quantity: quantityLabel(line.quantity),
            unitCost: ChileanUtils.formatCurrency(line.unitCostNet),
            netAmount: ChileanUtils.formatCurrency(line.netAmount),
            costIsFromCatalog: line.costIsFromCatalog,
          ),
      ],
      netTotal: ChileanUtils.formatCurrency(net),
      ivaAmount: ChileanUtils.formatCurrency(iva),
      total: ChileanUtils.formatCurrency(net + iva),
      unitCount: quantityLabel(units),
      unverifiedCostLines: lines.where((line) => line.costIsFromCatalog).length,
      note: _text(note),
      logoUrl: _text(logoUrl),
    );
  }

  /// El pedido que lee el servidor de la tienda con el código de un solo uso
  /// del envío de la mañana (`purchase_order_document_projection_internal`).
  /// Null si no trae folio, proveedor o una sola línea: un pedido vacío no
  /// se dibuja.
  static PurchaseOrderDocument? fromProjection(Object? value) {
    if (value is! Map) return null;
    final number = _text(value['order_number']);
    final supplier = value['supplier'];
    final rawLines = value['lines'];
    if (number == null || supplier is! Map || rawLines is! List) return null;
    final supplierName = _text(supplier['name']);
    if (supplierName == null) return null;
    final storefront = value['storefront'];
    String? identity(String key) {
      if (storefront is! Map || storefront['schemaVersion'] != 1) return null;
      return _text(storefront[key]);
    }

    final buyer = value['buyer'];
    final lines = [
      for (final line in rawLines.whereType<Map>())
        if (_text(line['name']) case final name?)
          PurchaseOrderDocumentSource(
            productId: _text(line['product_id']) ?? '',
            name: name,
            reference: _reference(
              brand: _text(line['brand']),
              sku: _text(line['sku']),
            ),
            quantity: _amount(line['quantity']),
            unitCostNet: _amount(line['unit_cost']),
            costIsFromCatalog: false,
          ),
    ];
    if (lines.isEmpty) return null;
    return PurchaseOrderDocument.compose(
      orderNumber: number,
      issuedOn: DateTime.tryParse('${value['issued_at']}') ?? DateTime.now(),
      buyerName:
          identity('displayName') ??
          (buyer is Map ? _text(buyer['name']) : null) ??
          'Tienda',
      buyerCity: buyer is Map ? _text(buyer['city']) : null,
      supplierName: supplierName,
      supplierLegalName: _text(supplier['legal_name']),
      supplierRut: _text(supplier['rut']),
      supplierContact: _text(supplier['contact']),
      paymentTerms: _text(supplier['payment_terms']),
      lines: lines,
      note: _text(value['note']),
      logoUrl: identity('logoUrl'),
    );
  }

  /// El IVA del pedido: 19 % sobre el neto, como el documento de compra en
  /// que se convierte.
  static const double ivaRate = 0.19;

  final String orderNumber;
  final bool isDraft;
  final String issuedOn;

  final String buyerName;
  final String? buyerCity;

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

  /// El logo del membrete: el del sitio (la identidad de la tienda), que el
  /// ERP y el servidor resuelven con la misma regla
  /// ([storeDocumentLogoSource]). Sin logo, el membrete escribe [buyerName].
  final String? logoUrl;

  bool get isEmpty => lines.isEmpty;

  /// El nombre del archivo que ve el proveedor en el chat.
  String get fileName =>
      'pedido_${(isDraft ? 'borrador' : orderNumber).replaceAll(RegExp(r'[^0-9A-Za-z_-]'), '_')}.pdf';

  /// «2» o «1.5»: una cantidad entera se escribe sin decimales.
  static String quantityLabel(double value) =>
      value == value.roundToDouble() ? value.round().toString() : '$value';

  /// Las condiciones de pago como las lee una persona («30 días», «Prepago»).
  /// Hasta el 2026-11-22 el PDF imprimía el código de la ficha («net30»).
  /// Un texto que no es un código conocido va tal cual.
  static String? paymentTermsLabel(String? raw) {
    final value = _text(raw);
    if (value == null) return null;
    return switch (value.toLowerCase()) {
      'immediate' => 'Contado',
      'net15' => '15 días',
      'net30' => '30 días',
      'net45' => '45 días',
      'net60' => '60 días',
      'prepaid' => 'Prepago',
      _ => value,
    };
  }

  /// «Marca · SKU 123»; null si no hay ninguno de los dos.
  static String? referenceFor({String? brand, String? sku}) =>
      _reference(brand: _text(brand), sku: _text(sku));
}

/// Una línea ya formateada.
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

/// Una línea con sus valores crudos, antes de formatear.
class PurchaseOrderDocumentSource {
  const PurchaseOrderDocumentSource({
    required this.productId,
    required this.name,
    required this.reference,
    required this.quantity,
    required this.unitCostNet,
    required this.costIsFromCatalog,
  });

  final String productId;
  final String name;
  final String? reference;
  final double quantity;
  final double unitCostNet;

  /// El costo salió de la ficha del producto, no de una factura.
  final bool costIsFromCatalog;

  double get netAmount => quantity * unitCostNet;
}

String? _reference({String? brand, String? sku}) {
  final parts = <String>[?brand, if (sku != null) 'SKU $sku'];
  return parts.isEmpty ? null : parts.join(' · ');
}

String? _text(Object? raw) {
  final text = raw?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

double _amount(Object? raw) =>
    raw is num ? raw.toDouble() : double.tryParse(raw?.toString() ?? '') ?? 0;

/// Dibuja el pedido a proveedor con el membrete de la tienda.
///
/// [regularFont] y [boldFont] son las Barlow de la tienda (TrueType): la app
/// las lee de su paquete, el servidor de la tienda de Hosting. [logo] es el
/// logo de la tienda ([storeDocumentLogoSource]); sin él, el membrete
/// escribe el nombre.
Future<Uint8List> buildPurchaseOrderPdf(
  PurchaseOrderDocument document, {
  required ByteData regularFont,
  required ByteData boldFont,
  Uint8List? logo,
}) async {
  final logoImage = storeDocumentLogoImage(logo);
  final regular = pw.Font.ttf(regularFont);
  final bold = pw.Font.ttf(boldFont);
  final pdf = pw.Document(
    theme: pw.ThemeData.withFont(
      base: regular,
      bold: bold,
      italic: regular,
      boldItalic: bold,
    ),
    title: document.isDraft
        ? 'Pedido (borrador)'
        : 'Pedido ${document.orderNumber}',
    author: document.buyerName,
    subject: 'Pedido a ${document.supplierName}',
  );
  final folio = document.isDraft ? 'Borrador' : document.orderNumber;

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(42, 38, 42, 34),
      header: (context) => context.pageNumber == 1
          ? pw.SizedBox()
          : pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 10),
              margin: const pw.EdgeInsets.only(bottom: 18),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: storeDocumentLine),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  storeDocumentWordmark(
                    document.buyerName,
                    null,
                    compact: true,
                    logo: logoImage,
                  ),
                  pw.Text(
                    folio,
                    style: const pw.TextStyle(
                      color: storeDocumentMuted,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
      footer: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 10),
        margin: const pw.EdgeInsets.only(top: 18),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: storeDocumentLine)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Text(
                '${document.buyerName} · Pedido a proveedor: no es factura.',
                style: const pw.TextStyle(
                  color: storeDocumentMuted,
                  fontSize: 8,
                ),
              ),
            ),
            pw.SizedBox(width: 16),
            pw.Text(
              'Página ${context.pageNumber} de ${context.pagesCount}',
              style: const pw.TextStyle(color: storeDocumentMuted, fontSize: 8),
            ),
          ],
        ),
      ),
      build: (context) => [
        _orderHeader(document, logoImage),
        pw.SizedBox(height: 22),
        _parties(document),
        pw.SizedBox(height: 22),
        _orderLines(document),
        pw.SizedBox(height: 14),
        _orderTotals(document),
        if (document.paymentTerms != null || document.note != null) ...[
          pw.SizedBox(height: 18),
          _orderTerms(document),
        ],
        // La salvedad viaja en el papel, no sólo en la pantalla: quien
        // aprueba tiene que verla en lo mismo que va a mandar.
        if (document.unverifiedCostLines > 0) ...[
          pw.SizedBox(height: 14),
          _unverifiedCosts(document.unverifiedCostLines),
        ],
      ],
    ),
  );
  return pdf.save();
}

pw.Widget _orderHeader(PurchaseOrderDocument document, pw.ImageProvider? logo) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Expanded(
        child: storeDocumentWordmark(document.buyerName, null, logo: logo),
      ),
      pw.SizedBox(width: 24),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: pw.BoxDecoration(
              color: storeDocumentSoftSurface,
              borderRadius: pw.BorderRadius.circular(2),
            ),
            child: pw.Text(
              'PEDIDO',
              style: pw.TextStyle(
                color: storeDocumentBrand,
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
          ),
          pw.SizedBox(height: 9),
          pw.Text(
            document.isDraft ? 'Borrador · sin número' : document.orderNumber,
            style: pw.TextStyle(
              color: storeDocumentInk,
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            document.issuedOn,
            style: const pw.TextStyle(color: storeDocumentMuted, fontSize: 10),
          ),
        ],
      ),
    ],
  );
}

/// Quién pide y a quién, con lo que el proveedor necesita para despachar y
/// facturar.
pw.Widget _parties(PurchaseOrderDocument document) {
  pw.Widget party(String role, String name, List<String?> details) =>
      pw.Padding(
        padding: const pw.EdgeInsets.fromLTRB(12, 9, 12, 10),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              role.toUpperCase(),
              style: const pw.TextStyle(
                color: storeDocumentMuted,
                fontSize: 7.5,
                letterSpacing: 0.5,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              name,
              style: pw.TextStyle(
                color: storeDocumentInk,
                fontSize: 10.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            for (final detail in details)
              if (detail != null) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  detail,
                  style: const pw.TextStyle(
                    color: storeDocumentMuted,
                    fontSize: 9,
                  ),
                ),
              ],
          ],
        ),
      );
  return pw.Table(
    columnWidths: const {0: pw.FlexColumnWidth(1), 1: pw.FlexColumnWidth(1.3)},
    border: pw.TableBorder.all(color: storeDocumentLine),
    children: [
      pw.TableRow(
        verticalAlignment: pw.TableCellVerticalAlignment.top,
        decoration: const pw.BoxDecoration(color: storeDocumentSoftSurface),
        children: [
          party('De', document.buyerName, [document.buyerCity]),
          party('Para', document.supplierName, [
            document.supplierLegalName,
            document.supplierRut,
            document.supplierContact,
          ]),
        ],
      ),
    ],
  );
}

pw.Widget _orderLines(PurchaseOrderDocument document) {
  return pw.Table(
    columnWidths: const {
      0: pw.FlexColumnWidth(4.6),
      1: pw.FlexColumnWidth(0.9),
      2: pw.FlexColumnWidth(1.6),
      3: pw.FlexColumnWidth(1.7),
    },
    border: const pw.TableBorder(
      horizontalInside: pw.BorderSide(color: storeDocumentLine),
      bottom: pw.BorderSide(color: storeDocumentLine),
    ),
    children: [
      // Un pedido largo sigue en otra página: la cabecera se repite.
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: storeDocumentBrand),
        children: [
          _headerCell('Producto'),
          _headerCell('Cant.', alignRight: true),
          _headerCell('Precio unit. neto', alignRight: true),
          _headerCell('Total neto', alignRight: true),
        ],
      ),
      for (final line in document.lines)
        pw.TableRow(
          verticalAlignment: pw.TableCellVerticalAlignment.top,
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    line.name,
                    style: pw.TextStyle(
                      color: storeDocumentInk,
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if (line.reference != null) ...[
                    pw.SizedBox(height: 3),
                    pw.Text(
                      line.reference!,
                      style: const pw.TextStyle(
                        color: storeDocumentMuted,
                        fontSize: 7.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _valueCell(line.quantity, alignRight: true),
            _valueCell(line.unitCost, alignRight: true),
            _valueCell(line.netAmount, alignRight: true, bold: true),
          ],
        ),
    ],
  );
}

pw.Widget _orderTotals(PurchaseOrderDocument document) {
  pw.Widget row(String label, String amount, {bool strong = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              label,
              style: pw.TextStyle(
                color: strong ? storeDocumentInk : storeDocumentMuted,
                fontSize: strong ? 11.5 : 9.5,
                fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
            pw.Text(
              amount,
              style: pw.TextStyle(
                color: storeDocumentInk,
                fontSize: strong ? 11.5 : 9.5,
                fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ],
        ),
      );
  final units = document.unitCount == '1'
      ? '1 unidad'
      : '${document.unitCount} unidades';
  final lines = document.lines.length == 1
      ? '1 producto'
      : '${document.lines.length} productos';
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4),
          child: pw.Text(
            '$lines · $units',
            style: const pw.TextStyle(color: storeDocumentMuted, fontSize: 9),
          ),
        ),
      ),
      pw.SizedBox(
        width: 220,
        child: pw.Column(
          children: [
            row('Neto', document.netTotal),
            row('IVA 19 %', document.ivaAmount),
            pw.Divider(color: storeDocumentLine, height: 10),
            row('Total', document.total, strong: true),
          ],
        ),
      ),
    ],
  );
}

pw.Widget _orderTerms(PurchaseOrderDocument document) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      if (document.paymentTerms != null)
        pw.RichText(
          text: pw.TextSpan(
            children: [
              pw.TextSpan(
                text: 'Condiciones de pago: ',
                style: pw.TextStyle(
                  color: storeDocumentInk,
                  fontSize: 9.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.TextSpan(
                text: document.paymentTerms,
                style: const pw.TextStyle(
                  color: storeDocumentInk,
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
        ),
      if (document.paymentTerms != null && document.note != null)
        pw.SizedBox(height: 6),
      if (document.note != null)
        pw.Text(
          document.note!,
          style: const pw.TextStyle(
            color: storeDocumentInk,
            fontSize: 9.5,
            lineSpacing: 2,
          ),
        ),
    ],
  );
}

pw.Widget _unverifiedCosts(int count) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: pw.BoxDecoration(
      color: storeDocumentWarningSurface,
      borderRadius: pw.BorderRadius.circular(2),
    ),
    child: pw.Text(
      count == 1
          ? '1 línea lleva un precio de referencia interna, no un precio ya '
                'cotizado. Confirmar antes de despachar.'
          : '$count líneas llevan un precio de referencia interna, no uno ya '
                'cotizado. Confirmar antes de despachar.',
      style: const pw.TextStyle(color: storeDocumentWarning, fontSize: 8.5),
    ),
  );
}

pw.Widget _headerCell(String text, {bool alignRight = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    child: pw.Text(
      text,
      textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
      style: pw.TextStyle(
        color: PdfColors.white,
        fontSize: 8.5,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  );
}

pw.Widget _valueCell(
  String text, {
  bool alignRight = false,
  bool bold = false,
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    child: pw.Text(
      text,
      textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
      style: pw.TextStyle(
        color: storeDocumentInk,
        fontSize: 9,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
}
