import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../modules/website/models/website_models.dart';
import '../../shared/utils/chilean_utils.dart';
import '../models/storefront_tax_summary.dart';

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
Future<Uint8List> buildOrderPdfBytes(OnlineOrder order) async {
  final regularFont = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Barlow-Regular.ttf'),
  );
  final boldFont = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Barlow-Bold.ttf'),
  );
  final pdf = pw.Document(
    theme: pw.ThemeData.withFont(
      base: regularFont,
      bold: boldFont,
      italic: regularFont,
      boldItalic: boldFont,
    ),
    title: 'Resumen de pedido ${order.orderNumber}',
    author: order.storefrontIdentity.displayName,
    subject: 'Resumen informativo de pedido',
  );
  final customerRows = _customerRows(order);

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
                  _brandWordmark(
                    order.storefrontIdentity,
                    compact: true,
                  ),
                  pw.Text(
                    order.orderNumber,
                    style: const pw.TextStyle(
                      color: _muted,
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
            _summaryCell('Estado del pedido', order.statusDisplayName),
            _summaryCell('Estado del pago', order.paymentStatusDisplayName),
            _summaryCell('Entrega', order.deliveryDisplayName),
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
          'Gracias por comprar en ${order.storefrontIdentity.displayName}.',
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

Future<void> downloadOrderPdf(OnlineOrder order) async {
  final bytes = await buildOrderPdfBytes(order);
  final fileName = 'pedido_${order.orderNumber}.pdf';

  if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    final outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Guardar resumen del pedido',
      fileName: fileName,
      allowedExtensions: const ['pdf'],
      type: FileType.custom,
    );

    if (outputFile != null) {
      await File(outputFile).writeAsBytes(bytes);
    }
    return;
  }

  await Printing.sharePdf(bytes: bytes, filename: fileName);
}

pw.Widget _documentHeader(OnlineOrder order) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      _brandWordmark(order.storefrontIdentity),
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

pw.Widget _brandWordmark(
  StorefrontIdentitySnapshot identity, {
  bool compact = false,
}) {
  final tagline = identity.tagline;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        identity.displayName.toUpperCase(),
        style: pw.TextStyle(
          color: _brand,
          fontSize: compact ? 12 : 23,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
      if (!compact && tagline != null) ...[
        pw.SizedBox(height: 4),
        pw.Text(
          tagline,
          style: const pw.TextStyle(color: _muted, fontSize: 9),
        ),
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
          style: const pw.TextStyle(
            color: _ink,
            fontSize: 9,
            lineSpacing: 2,
          ),
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

pw.Widget _itemsTable(OnlineOrder order) {
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
      for (final item in order.items)
        pw.TableRow(
          children: [
            _tableValue(item.productName, bold: true),
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

pw.Widget _totalBlock(OnlineOrder order) {
  final taxSummary = StorefrontTaxSummary.calculate(
    order.items.map(
      (item) => StorefrontTaxLineInput(
        label: item.productName,
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
            _totalRow(
              netLabel,
              ChileanUtils.formatCurrency(order.subtotal),
            ),
            if (order.taxAmount > 0)
              _totalRow(
                ivaLabel,
                ChileanUtils.formatCurrency(order.taxAmount),
              ),
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

List<MapEntry<String, String>> _customerRows(OnlineOrder order) {
  final rows = <MapEntry<String, String>>[];
  void add(String label, String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isNotEmpty) rows.add(MapEntry(label, normalized));
  }

  add('Nombre', order.customerName);
  add('Email', order.customerEmail);
  add('Teléfono', order.customerPhone);
  final hasAddress = [
    order.customerAddress,
    order.shippingAddressLine1,
    order.shippingAddressLine2,
    order.shippingCity,
    order.shippingState,
    order.shippingPostalCode,
  ].any((part) => part?.trim().isNotEmpty == true);
  if (hasAddress) add('Dirección', order.shippingAddressDisplay);
  return rows;
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
