import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../modules/sales/models/sales_models.dart';

const _ink = PdfColor.fromInt(0xFF17242C);
const _muted = PdfColor.fromInt(0xFF66747D);
const _line = PdfColor.fromInt(0xFFDDE4E8);
const _softSurface = PdfColor.fromInt(0xFFF4F7F8);
const _brand = PdfColor.fromInt(0xFF174A68);
const _success = PdfColor.fromInt(0xFF237A4B);
const _warning = PdfColor.fromInt(0xFF7A5A20);
const _warningSurface = PdfColor.fromInt(0xFFFFF8E8);

/// Builds the internal receipt attached to a recorded sales payment.
///
/// This deliberately stays separate from invoice/DTE generation. It presents
/// the payment and the invoice's current settlement snapshot without claiming
/// that the document has fiscal validity.
class PaymentReceiptPdfGenerator {
  const PaymentReceiptPdfGenerator._();

  static String paymentNumber(Payment payment) {
    final compactId = (payment.id ?? '')
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toUpperCase();
    if (compactId.isEmpty) return 'COB-PENDIENTE';

    final suffix = compactId.length <= 6
        ? compactId
        : compactId.substring(compactId.length - 6);
    return 'COB-$suffix';
  }

  static String fileName(Payment payment) {
    return 'comprobante_pago_${paymentNumber(payment)}.pdf';
  }

  static Future<pw.Document> generate({
    required Payment payment,
    required Invoice invoice,
    required String paymentMethodName,
    String? businessName,
  }) async {
    final receiptNumber = paymentNumber(payment);
    final issuer = _displayValue(businessName, fallback: 'Viñabike ERP');
    final method = _displayValue(paymentMethodName, fallback: 'No informado');
    final invoiceNumber = _displayValue(
      payment.invoiceReference,
      fallback: _displayValue(invoice.invoiceNumber, fallback: 'Sin número'),
    );
    final document = pw.Document(
      title: 'Comprobante interno de pago $receiptNumber',
      author: issuer,
      subject: 'Registro interno de pago asociado a $invoiceNumber',
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(42, 30, 42, 26),
        footer: (context) => _footer(context),
        build: (context) => <pw.Widget>[
          _header(
            issuer: issuer,
            receiptNumber: receiptNumber,
          ),
          pw.SizedBox(height: 13),
          _nonFiscalNotice(),
          pw.SizedBox(height: 17),
          _amountSummary(payment),
          pw.SizedBox(height: 18),
          _sectionTitle('Datos del pago'),
          pw.SizedBox(height: 7),
          _detailGrid(<_DetailItem>[
            _DetailItem('Fecha de recepción', _formatDate(payment.date)),
            _DetailItem('Medio de pago', method),
            _DetailItem(
              'Referencia',
              _displayValue(payment.reference, fallback: 'Sin referencia'),
            ),
            _DetailItem('Factura asociada', invoiceNumber),
          ]),
          pw.SizedBox(height: 18),
          _sectionTitle('Cliente'),
          pw.SizedBox(height: 7),
          _detailGrid(<_DetailItem>[
            _DetailItem(
              'Nombre o razón social',
              _displayValue(invoice.customerName, fallback: 'No informado'),
            ),
            _DetailItem(
              'RUT',
              _displayValue(invoice.customerRut, fallback: 'No informado'),
            ),
          ]),
          pw.SizedBox(height: 18),
          _sectionTitle('Impuestos reflejados en este pago'),
          pw.SizedBox(height: 7),
          _taxSummary(payment),
          pw.SizedBox(height: 18),
          _sectionTitle('Estado actual de la factura'),
          pw.SizedBox(height: 7),
          _invoiceSummary(invoice),
          pw.SizedBox(height: 18),
          _sectionTitle('Notas'),
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
          pw.Text(
            'Este comprobante resume un pago registrado en el ERP y su vinculación con la factura indicada. Los montos de la factura corresponden a su estado actual al momento de generar el documento.',
            style: const pw.TextStyle(
              color: _muted,
              fontSize: 9,
              lineSpacing: 2,
            ),
          ),
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
                'Registro de cobranza',
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
              'Comprobante interno de pago',
              style: pw.TextStyle(
                color: _ink,
                fontSize: 18,
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
            'No reemplaza el documento tributario ni acredita por sí solo su emisión ante el SII.',
            style: const pw.TextStyle(color: _warning, fontSize: 9),
          ),
        ],
      ),
    );
  }

  static pw.Widget _amountSummary(Payment payment) {
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
                'MONTO RECIBIDO',
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

  static pw.Widget _taxSummary(Payment payment) {
    final treatment = switch (payment.taxTreatment) {
      'tax_included' => 'IVA incluido',
      'tax_excluded' => 'IVA agregado',
      _ => 'Sin IVA',
    };

    return _financialTable(<_FinancialItem>[
      _FinancialItem('Tratamiento', treatment),
      _FinancialItem('Neto del pago', _formatClp(payment.netAmount)),
      _FinancialItem('IVA del pago', _formatClp(payment.ivaAmount)),
      _FinancialItem('Total del pago', _formatClp(payment.amount),
          emphasized: true),
    ]);
  }

  static pw.Widget _invoiceSummary(Invoice invoice) {
    return _financialTable(<_FinancialItem>[
      _FinancialItem('Total factura', _formatClp(invoice.total)),
      _FinancialItem('Total pagado', _formatClp(invoice.paidAmount)),
      _FinancialItem('Saldo actual', _formatClp(invoice.balance),
          emphasized: true),
    ]);
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
              'Comprobante interno de pago - No constituye factura ni DTE.',
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
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? fallback : normalized;
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${_twoDigits(local.day)}/${_twoDigits(local.month)}/${local.year}';
  }

  static String _formatClp(double value) {
    final amount = value.round();
    final sign = amount < 0 ? '-' : '';
    final digits = amount.abs().toString();
    final grouped = digits.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    return '$sign\$ $grouped CLP';
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}

class _DetailItem {
  const _DetailItem(this.label, this.value);

  final String label;
  final String value;
}

class _FinancialItem {
  const _FinancialItem(
    this.label,
    this.value, {
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;
}
