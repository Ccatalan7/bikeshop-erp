import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../shared/utils/chilean_utils.dart';
import '../models/online_order_labels.dart';
import '../models/storefront_tax_summary.dart';

/// One product line of the summary.
class OrderSummaryLine {
  const OrderSummaryLine({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
    required this.taxRate,
  });

  final String name;
  final int quantity;
  final double unitPrice;
  final double subtotal;
  final double? taxRate;
}

/// What the order summary states: the order as the customer may see it
/// (the public access answer carries no customer data; the ERP's order
/// does) and the store's identity frozen with the order.
class OrderSummaryPdfInput {
  const OrderSummaryPdfInput({
    required this.storeName,
    required this.tagline,
    required this.orderNumber,
    required this.createdAt,
    required this.statusLabel,
    required this.paymentStatusLabel,
    required this.deliveryLabel,
    required this.customerRows,
    required this.lines,
    required this.subtotal,
    required this.taxAmount,
    required this.shippingCost,
    required this.discountAmount,
    required this.total,
  });

  /// `get_public_online_order_by_access_token`'s answer, as Flutter's
  /// `onlineOrderFromPublicAccessResponse` reads it; null when it is not
  /// that order or not an order.
  static OrderSummaryPdfInput? fromPublicAccess(
    Object? value, {
    required String expectedOrderId,
  }) {
    if (value is! Map) return null;
    final order = value['order'];
    if (order is! Map || order['id']?.toString() != expectedOrderId) {
      return null;
    }
    final createdAt = DateTime.tryParse(order['createdAt']?.toString() ?? '');
    if (createdAt == null) return null;
    double amount(Object? raw) => raw is num ? raw.toDouble() : 0.0;
    final storefront = value['storefront'];
    String? identity(String key) {
      if (storefront is! Map || storefront['schemaVersion'] != 1) return null;
      final text = storefront[key]?.toString().trim() ?? '';
      return text.isEmpty ? null : text;
    }

    final rawItems = value['items'];
    return OrderSummaryPdfInput(
      storeName: identity('displayName') ?? 'Tienda',
      tagline: identity('tagline'),
      orderNumber: order['number']?.toString() ?? 'N/A',
      createdAt: createdAt,
      statusLabel: onlineOrderStatusLabel(
        order['status']?.toString() ?? 'pending',
      ),
      paymentStatusLabel: onlineOrderPaymentStatusLabel(
        order['paymentStatus']?.toString() ?? 'pending',
      ),
      deliveryLabel: onlineOrderDeliveryLabel(
        order['deliveryType']?.toString() ?? 'shipping',
      ),
      customerRows: const [],
      lines: [
        if (rawItems is List)
          for (final item in rawItems.whereType<Map>())
            OrderSummaryLine(
              name: item['name']?.toString() ?? 'Producto',
              quantity: (item['quantity'] as num?)?.toInt() ?? 0,
              unitPrice: amount(item['unitPrice']),
              subtotal: amount(item['subtotal']),
              taxRate: (item['taxRate'] as num?)?.toDouble(),
            ),
      ],
      subtotal: amount(order['subtotal']),
      taxAmount: amount(order['taxAmount']),
      shippingCost: amount(order['shippingCost']),
      discountAmount: amount(order['discountAmount']),
      total: amount(order['total']),
    );
  }

  final String storeName;
  final String? tagline;
  final String orderNumber;
  final DateTime createdAt;
  final String statusLabel;
  final String paymentStatusLabel;
  final String deliveryLabel;

  /// «Datos entregados en el checkout»: label and value, only those given.
  final List<MapEntry<String, String>> customerRows;
  final List<OrderSummaryLine> lines;
  final double subtotal;
  final double taxAmount;
  final double shippingCost;
  final double discountAmount;
  final double total;

  /// The file name both stores offer.
  String get fileName => 'pedido_$orderNumber.pdf';
}

const _ink = PdfColor.fromInt(0xFF17242C);
const _muted = PdfColor.fromInt(0xFF66747D);
const _line = PdfColor.fromInt(0xFFDDE4E8);
const _softSurface = PdfColor.fromInt(0xFFF4F7F8);
const _brand = PdfColor.fromInt(0xFF174A68);
const _warning = PdfColor.fromInt(0xFF7A5A20);
const _warningSurface = PdfColor.fromInt(0xFFFFF8E8);
tz.Location? _santiagoLocation;

/// Builds the customer-facing order summary.
///
/// This file intentionally never claims fiscal validity. An official Mercado
/// Pago voucher or Chilean DTE is delivered through its own verified artifact
/// flow and must not be reconstructed from order/payment fields here.
///
/// [regularFont] and [boldFont] are the store's Barlow faces (TrueType): the
/// app reads them from its bundle, the HTML store from Hosting.
Future<Uint8List> buildOrderSummaryPdf(
  OrderSummaryPdfInput order, {
  required ByteData regularFont,
  required ByteData boldFont,
}) async {
  final regular = pw.Font.ttf(regularFont);
  final bold = pw.Font.ttf(boldFont);
  final pdf = pw.Document(
    theme: pw.ThemeData.withFont(
      base: regular,
      bold: bold,
      italic: regular,
      boldItalic: bold,
    ),
    title: 'Resumen de pedido ${order.orderNumber}',
    author: order.storeName,
    subject: 'Resumen informativo de pedido',
  );
  final customerRows = order.customerRows;

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
                border: pw.Border(bottom: pw.BorderSide(color: _line)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _brandWordmark(order, compact: true),
                  pw.Text(
                    order.orderNumber,
                    style: const pw.TextStyle(color: _muted, fontSize: 9),
                  ),
                ],
              ),
            ),
      footer: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 10),
        margin: const pw.EdgeInsets.only(top: 18),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _line)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Text(
                'Resumen de pedido - No acredita pago ni constituye un documento tributario.',
                style: const pw.TextStyle(color: _muted, fontSize: 8),
              ),
            ),
            pw.SizedBox(width: 16),
            pw.Text(
              'Página ${context.pageNumber} de ${context.pagesCount}',
              style: const pw.TextStyle(color: _muted, fontSize: 8),
            ),
          ],
        ),
      ),
      build: (context) => [
        _documentHeader(order),
        pw.SizedBox(height: 22),
        _nonTaxNotice(),
        pw.SizedBox(height: 24),
        pw.Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _summaryCell('Fecha del pedido', _formatDate(order.createdAt)),
            _summaryCell('Estado del pedido', order.statusLabel),
            _summaryCell('Estado del pago', order.paymentStatusLabel),
            _summaryCell('Entrega', order.deliveryLabel),
          ],
        ),
        if (customerRows.isNotEmpty) ...[
          pw.SizedBox(height: 28),
          _sectionTitle('Datos entregados en el checkout'),
          pw.SizedBox(height: 10),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(14),
            color: _softSurface,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (final row in customerRows)
                  _keyValueRow(row.key, row.value),
              ],
            ),
          ),
        ],
        pw.SizedBox(height: 28),
        _sectionTitle('Detalle del pedido'),
        pw.SizedBox(height: 10),
        _itemsTable(order),
        pw.SizedBox(height: 18),
        _totalBlock(order),
        pw.SizedBox(height: 30),
        pw.Text(
          'Gracias por comprar en ${order.storeName}.',
          style: pw.TextStyle(
            color: _ink,
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Conserva el número de pedido para cualquier consulta. El documento tributario oficial se entrega por separado cuando corresponda.',
          style: const pw.TextStyle(
            color: _muted,
            fontSize: 10,
            lineSpacing: 2,
          ),
        ),
      ],
    ),
  );

  return pdf.save();
}

pw.Widget _documentHeader(OrderSummaryPdfInput order) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      _brandWordmark(order),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: pw.BoxDecoration(
              color: _softSurface,
              borderRadius: pw.BorderRadius.circular(2),
            ),
            child: pw.Text(
              'RESUMEN INFORMATIVO',
              style: pw.TextStyle(
                color: _brand,
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
          ),
          pw.SizedBox(height: 9),
          pw.Text(
            'Resumen del pedido',
            style: pw.TextStyle(
              color: _ink,
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            order.orderNumber,
            style: pw.TextStyle(
              color: _brand,
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    ],
  );
}

pw.Widget _brandWordmark(OrderSummaryPdfInput order, {bool compact = false}) {
  final tagline = order.tagline;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        order.storeName.toUpperCase(),
        style: pw.TextStyle(
          color: _brand,
          fontSize: compact ? 12 : 23,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
      if (!compact && tagline != null) ...[
        pw.SizedBox(height: 4),
        pw.Text(tagline, style: const pw.TextStyle(color: _muted, fontSize: 9)),
      ],
    ],
  );
}

pw.Widget _nonTaxNotice() {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(14),
    decoration: const pw.BoxDecoration(
      color: _warningSurface,
      border: pw.Border(left: pw.BorderSide(color: _warning, width: 3)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Este documento resume el pedido',
          style: pw.TextStyle(
            color: _warning,
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'No acredita pago ni constituye boleta, factura u otro documento tributario. El voucher oficial de Mercado Pago o la boleta electrónica se entrega mediante su flujo verificado y no se reemplaza con este PDF.',
          style: const pw.TextStyle(color: _ink, fontSize: 9, lineSpacing: 2),
        ),
      ],
    ),
  );
}

pw.Widget _summaryCell(String label, String value) {
  return pw.Container(
    width: 245,
    padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 11),
    decoration: pw.BoxDecoration(
      color: _softSurface,
      border: pw.Border.all(color: _line),
      borderRadius: pw.BorderRadius.circular(2),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label.toUpperCase(),
          style: const pw.TextStyle(
            color: _muted,
            fontSize: 7.5,
            letterSpacing: 0.5,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          style: pw.TextStyle(
            color: _ink,
            fontSize: 10.5,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}

pw.Widget _sectionTitle(String text) {
  return pw.Text(
    text,
    style: pw.TextStyle(
      color: _ink,
      fontSize: 12,
      fontWeight: pw.FontWeight.bold,
    ),
  );
}

pw.Widget _keyValueRow(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 5),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 90,
          child: pw.Text(
            label,
            style: const pw.TextStyle(color: _muted, fontSize: 9),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            style: pw.TextStyle(
              color: _ink,
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _itemsTable(OrderSummaryPdfInput order) {
  return pw.Table(
    columnWidths: const {
      0: pw.FlexColumnWidth(4.4),
      1: pw.FlexColumnWidth(0.8),
      2: pw.FlexColumnWidth(1.5),
      3: pw.FlexColumnWidth(1.6),
    },
    border: const pw.TableBorder(
      horizontalInside: pw.BorderSide(color: _line),
      bottom: pw.BorderSide(color: _line),
    ),
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _brand),
        children: [
          _tableHeader('Producto'),
          _tableHeader('Cant.', alignRight: true),
          _tableHeader('Precio', alignRight: true),
          _tableHeader('Subtotal', alignRight: true),
        ],
      ),
      for (final item in order.lines)
        pw.TableRow(
          children: [
            _tableValue(item.name, bold: true),
            _tableValue('${item.quantity}', alignRight: true),
            _tableValue(
              ChileanUtils.formatCurrency(item.unitPrice),
              alignRight: true,
            ),
            _tableValue(
              ChileanUtils.formatCurrency(item.subtotal),
              alignRight: true,
              bold: true,
            ),
          ],
        ),
    ],
  );
}

pw.Widget _tableHeader(String text, {bool alignRight = false}) {
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

pw.Widget _tableValue(
  String text, {
  bool alignRight = false,
  bool bold = false,
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 11),
    child: pw.Text(
      text,
      textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
      style: pw.TextStyle(
        color: _ink,
        fontSize: 9,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
}

pw.Widget _totalBlock(OrderSummaryPdfInput order) {
  final taxSummary = StorefrontTaxSummary.calculate(
    order.lines.map(
      (item) => StorefrontTaxLineInput(
        label: item.name,
        grossUnitPrice: item.unitPrice,
        quantity: item.quantity,
        taxRate: item.taxRate,
      ),
    ),
  );
  final netLabel = taxSummary.isValid
      ? taxSummary.netLabel
      : order.taxAmount > 0
      ? 'Neto'
      : 'Subtotal';
  final ivaLabel = taxSummary.isValid ? taxSummary.ivaLabel : 'IVA incluido';

  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.end,
    children: [
      pw.Container(
        width: 235,
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(
          color: _softSurface,
          border: pw.Border.all(color: _line),
          borderRadius: pw.BorderRadius.circular(2),
        ),
        child: pw.Column(
          children: [
            _totalRow(netLabel, ChileanUtils.formatCurrency(order.subtotal)),
            if (order.taxAmount > 0)
              _totalRow(ivaLabel, ChileanUtils.formatCurrency(order.taxAmount)),
            if (order.shippingCost > 0)
              _totalRow(
                'Despacho',
                ChileanUtils.formatCurrency(order.shippingCost),
              ),
            if (order.discountAmount > 0)
              _totalRow(
                'Descuento',
                '-${ChileanUtils.formatCurrency(order.discountAmount)}',
              ),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'TOTAL DEL PEDIDO',
                  style: pw.TextStyle(
                    color: _ink,
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  ChileanUtils.formatCurrency(order.total),
                  style: pw.TextStyle(
                    color: _brand,
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}

pw.Widget _totalRow(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 8),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: const pw.TextStyle(color: _muted, fontSize: 9)),
        pw.Text(value, style: const pw.TextStyle(color: _ink, fontSize: 9)),
      ],
    ),
  );
}

String _formatDate(DateTime value) {
  if (_santiagoLocation == null) {
    tzdata.initializeTimeZones();
    _santiagoLocation = tz.getLocation('America/Santiago');
  }
  final local = tz.TZDateTime.from(value.toUtc(), _santiagoLocation!);
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
}
