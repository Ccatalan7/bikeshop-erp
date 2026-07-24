import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../modules/purchases/models/purchase_invoice.dart';
import '../../modules/purchases/models/purchase_payment.dart';

const _ink = PdfColor.fromInt(0xFF17242C);
const _muted = PdfColor.fromInt(0xFF66747D);
const _line = PdfColor.fromInt(0xFFDDE4E8);
const _softSurface = PdfColor.fromInt(0xFFF4F7F8);
const _brand = PdfColor.fromInt(0xFF174A68);
const _success = PdfColor.fromInt(0xFF237A4B);
const _warning = PdfColor.fromInt(0xFF7A5A20);
const _warningSurface = PdfColor.fromInt(0xFFFFF8E8);

/// Builds the internal evidence document for a recorded supplier payment.
///
/// The purchase invoice remains the owner of the supplier obligation,
/// recoverable IVA and inventory value. This document only describes the
/// accounts-payable settlement recorded by the ERP and is never presented as
/// bank confirmation, a supplier receipt, an invoice or a DTE.
class PurchasePaymentReceiptPdfGenerator {
  const PurchasePaymentReceiptPdfGenerator._();

  static String paymentNumber(PurchasePayment payment) {
    final compactId = (payment.id ?? '')
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toUpperCase();
    if (compactId.isEmpty) return 'PAG-PENDIENTE';

    final suffix = compactId.length <= 6
        ? compactId
        : compactId.substring(compactId.length - 6);
    return 'PAG-$suffix';
  }

  static String fileName(PurchasePayment payment) {
    return 'comprobante_pago_proveedor_${paymentNumber(payment)}.pdf';
  }

  static Future<pw.Document> generate({
    required PurchasePayment payment,
    required PurchaseInvoice invoice,
    required String paymentMethodName,
    String? businessName,
  }) async {
    final receiptNumber = paymentNumber(payment);
    final issuer = _displayValue(businessName, fallback: 'Viñabike ERP');
    final method = _displayValue(paymentMethodName, fallback: 'No informado');
    final invoiceNumber =
        _displayValue(invoice.invoiceNumber, fallback: 'Sin número');
    final document = pw.Document(
      title: 'Comprobante interno de pago a proveedor $receiptNumber',
      author: issuer,
      subject: 'Registro interno de pago asociado a $invoiceNumber',
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(42, 30, 42, 26),
        footer: _footer,
        build: (context) => <pw.Widget>[
          _header(issuer: issuer, receiptNumber: receiptNumber),
          pw.SizedBox(height: 13),
          _nonFiscalNotice(),
          pw.SizedBox(height: 17),
          _amountSummary(payment),
          pw.SizedBox(height: 18),
          _sectionTitle('Datos del pago'),
          pw.SizedBox(height: 7),
          _detailGrid(<_DetailItem>[
            _DetailItem('Fecha de pago', _formatDate(payment.date)),
            _DetailItem('Medio de pago', method),
            _DetailItem(
              'Referencia externa',
              _displayValue(payment.reference, fallback: 'Sin referencia'),
            ),
            _DetailItem('Factura interna vinculada', invoiceNumber),
          ]),
          pw.SizedBox(height: 18),
          _sectionTitle('Proveedor y documento de compra'),
          pw.SizedBox(height: 7),
          _detailGrid(<_DetailItem>[
            _DetailItem(
              'Proveedor',
              _displayValue(invoice.supplierName, fallback: 'No informado'),
            ),
            _DetailItem(
              'RUT',
              _displayValue(invoice.supplierRut, fallback: 'No informado'),
            ),
            _DetailItem(
              'Documento del proveedor',
              _displayValue(
                invoice.supplierInvoiceNumber,
                fallback: 'No informado',
              ),
            ),
            _DetailItem(
              'Fecha documento proveedor',
              invoice.supplierInvoiceDate == null
                  ? 'No informada'
                  : _formatDate(invoice.supplierInvoiceDate!),
            ),
          ]),
          pw.SizedBox(height: 18),
          _sectionTitle('Estado actual de la factura'),
          pw.SizedBox(height: 7),
          _financialTable(<_FinancialItem>[
            _FinancialItem('Total factura', _formatClp(invoice.total)),
            _FinancialItem('Total pagado', _formatClp(invoice.paidAmount)),
            _FinancialItem(
              'Saldo actual',
              _formatClp(invoice.balance.clamp(0, invoice.total)),
              emphasized: true,
            ),
            _FinancialItem('Estado', invoice.status.displayName),
          ]),
          pw.SizedBox(height: 18),
          _sectionTitle('Notas internas'),
          pw.SizedBox(height: 7),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: _softSurface,
              borderRadius: pw.BorderRadius.circular(3),
            ),
            child: pw.Text(
              _displayValue(payment.notes, fallback: 'Sin notas registradas.'),
              style: const pw.TextStyle(
                color: _ink,
                fontSize: 10,
                lineSpacing: 2,
              ),
            ),
          ),
          pw.SizedBox(height: 18),
          _ownershipNotice(),
        ],
      ),
    );

    return document;
  }

  static pw.Widget _header({
    required String issuer,
    required String receiptNumber,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: <pw.Widget>[
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text(
                issuer,
                style: pw.TextStyle(
                  color: _brand,
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Registro de egreso a proveedor',
                style: const pw.TextStyle(color: _muted, fontSize: 9),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 24),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: <pw.Widget>[
            pw.Text(
              'Comprobante interno de pago a proveedor',
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                color: _ink,
                fontSize: 17,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 5),
            pw.Text(
              receiptNumber,
              style: pw.TextStyle(
                color: _brand,
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _nonFiscalNotice() {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: pw.BoxDecoration(
        color: _warningSurface,
        border: pw.Border.all(color: _warning, width: 0.6),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(
            'DOCUMENTO INTERNO',
            style: pw.TextStyle(
              color: _warning,
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.6,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'No constituye factura ni DTE',
            style: pw.TextStyle(
              color: _warning,
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Registra una salida de fondos en el ERP. No acredita por sí solo '
            'que un banco haya ejecutado la transferencia ni que el proveedor '
            'haya recibido el dinero.',
            style: const pw.TextStyle(
              color: _warning,
              fontSize: 9,
              lineSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _amountSummary(PurchasePayment payment) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: pw.BoxDecoration(
        color: _softSurface,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: <pw.Widget>[
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text(
                'MONTO PAGADO',
                style: pw.TextStyle(
                  color: _muted,
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 0.7,
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                _formatClp(payment.amount),
                style: pw.TextStyle(
                  color: _ink,
                  fontSize: 25,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFE6F3EB),
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Text(
              'PAGO REGISTRADO',
              style: pw.TextStyle(
                color: _success,
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _ownershipNotice() {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(11),
      decoration: pw.BoxDecoration(
        color: _warningSurface,
        border: pw.Border.all(color: _warning, width: 0.5),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Text(
        'La factura de compra conserva el reconocimiento de la obligación con '
        'el proveedor, el IVA recuperable y el valor de inventario. La recepción '
        'profesional conserva la propiedad del movimiento físico. Este pago '
        'solo cancela cuentas por pagar contra caja o banco y no mueve stock.',
        style: const pw.TextStyle(
          color: _warning,
          fontSize: 9,
          lineSpacing: 2,
        ),
      ),
    );
  }

  static pw.Widget _sectionTitle(String title) {
    return pw.Text(
      title,
      style: pw.TextStyle(
        color: _ink,
        fontSize: 11,
        fontWeight: pw.FontWeight.bold,
      ),
    );
  }

  static pw.Widget _detailGrid(List<_DetailItem> items) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line, width: 0.6),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Column(
        children: <pw.Widget>[
          for (var index = 0; index < items.length; index += 2)
            pw.Container(
              decoration: index + 2 < items.length
                  ? const pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(color: _line, width: 0.6),
                      ),
                    )
                  : null,
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.Expanded(child: _detailCell(items[index])),
                  pw.Container(width: 0.6, height: 41, color: _line),
                  pw.Expanded(
                    child: index + 1 < items.length
                        ? _detailCell(items[index + 1])
                        : pw.SizedBox(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static pw.Widget _detailCell(_DetailItem item) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(
            item.label.toUpperCase(),
            style: pw.TextStyle(
              color: _muted,
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            item.value,
            style: const pw.TextStyle(color: _ink, fontSize: 10),
          ),
        ],
      ),
    );
  }

  static pw.Widget _financialTable(List<_FinancialItem> items) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line, width: 0.6),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Column(
        children: <pw.Widget>[
          for (var index = 0; index < items.length; index++)
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: index < items.length - 1
                  ? const pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(color: _line, width: 0.6),
                      ),
                    )
                  : null,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: <pw.Widget>[
                  pw.Text(
                    items[index].label,
                    style: pw.TextStyle(
                      color: items[index].emphasized ? _ink : _muted,
                      fontSize: 9,
                      fontWeight: items[index].emphasized
                          ? pw.FontWeight.bold
                          : pw.FontWeight.normal,
                    ),
                  ),
                  pw.Text(
                    items[index].value,
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(
                      color: _ink,
                      fontSize: items[index].emphasized ? 11 : 9,
                      fontWeight: items[index].emphasized
                          ? pw.FontWeight.bold
                          : pw.FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static pw.Widget _footer(pw.Context context) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 10),
      margin: const pw.EdgeInsets.only(top: 18),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _line)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Text(
              'Comprobante interno de pago a proveedor - No constituye '
              'factura ni DTE.',
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
    );
  }

  static String _displayValue(String? value, {required String fallback}) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? fallback : normalized;
  }

  static String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year.toString().padLeft(4, '0')}';
  }

  static String _formatClp(num value) {
    final digits = value.round().abs().toString();
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
      buffer.write(digits[index]);
    }
    final prefix = value < 0 ? r'-$ ' : r'$ ';
    return '$prefix$buffer';
  }
}

class _DetailItem {
  const _DetailItem(this.label, this.value);

  final String label;
  final String value;
}

class _FinancialItem {
  const _FinancialItem(this.label, this.value, {this.emphasized = false});

  final String label;
  final String value;
  final bool emphasized;
}
