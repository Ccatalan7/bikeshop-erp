import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;
import 'package:vinabike_erp/modules/sales/models/sales_models.dart';
import 'package:vinabike_erp/shared/utils/payment_receipt_pdf_generator.dart';

void main() {
  group('PaymentReceiptPdfGenerator', () {
    test('derives a stable payment number and file name from the UUID suffix',
        () {
      final payment = _paymentFixture();

      expect(
        PaymentReceiptPdfGenerator.paymentNumber(payment),
        'COB-34FB00',
      );
      expect(
        PaymentReceiptPdfGenerator.fileName(payment),
        'comprobante_pago_COB-34FB00.pdf',
      );
    });

    test('renders a complete payment-owned, explicitly non-fiscal receipt',
        () async {
      final document = await PaymentReceiptPdfGenerator.generate(
        payment: _paymentFixture(),
        invoice: _invoiceFixture(),
        paymentMethodName: 'Tarjeta de crédito/débito',
        businessName: 'Viñabike',
      );

      final bytes = await document.save();
      final samplePath = Platform.environment['PAYMENT_RECEIPT_SAMPLE_PATH'];
      if (samplePath != null && samplePath.trim().isNotEmpty) {
        final output = File(samplePath);
        await output.parent.create(recursive: true);
        await output.writeAsBytes(bytes, flush: true);
      }
      final text = _extractText(bytes);

      expect(bytes.length, greaterThan(4000));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(text, contains('Comprobante interno de pago'));
      expect(text, contains('No constituye factura ni DTE'));
      expect(text, contains('COB-34FB00'));
      expect(text, contains('154.000'));
      expect(text, contains('14/07/2026'));
      expect(text, contains('Cliente de Prueba'));
      expect(text, contains('12.345.678-5'));
      expect(text, contains('FV-00809'));
      expect(text, contains('Tarjeta de crédito/débito'));
      expect(text, contains('TRANSBANK-7788'));
      expect(text, contains('Pago completo en caja.'));
      expect(text, contains('Neto del pago'));
      expect(text, contains('129.412'));
      expect(text, contains('IVA del pago'));
      expect(text, contains('24.588'));
      expect(text, contains('Total factura'));
      expect(text, contains('Total pagado'));
      expect(text, contains('Saldo actual'));
      expect(text, isNot(contains('FACTURA ELECTRÓNICA')));
    });
  });
}

Payment _paymentFixture() {
  return Payment(
    id: '11111111-2222-4333-8444-55555534fb00',
    tenantId: 'tenant-1',
    invoiceId: 'invoice-1',
    invoiceReference: 'FV-00809',
    paymentMethodId: 'method-1',
    amount: 154000,
    date: DateTime(2026, 7, 14),
    reference: 'TRANSBANK-7788',
    notes: 'Pago completo en caja.',
    taxTreatment: 'tax_included',
    netAmount: 129412,
    ivaAmount: 24588,
  );
}

Invoice _invoiceFixture() {
  return Invoice(
    id: 'invoice-1',
    tenantId: 'tenant-1',
    invoiceNumber: 'FV-00809',
    customerName: 'Cliente de Prueba',
    customerRut: '12.345.678-5',
    date: DateTime(2026, 7, 14),
    subtotal: 129412,
    netAmount: 129412,
    ivaAmount: 24588,
    total: 154000,
    paidAmount: 154000,
    balance: 0,
  );
}

String _extractText(List<int> bytes) {
  final document = syncfusion.PdfDocument(inputBytes: bytes);
  try {
    return syncfusion.PdfTextExtractor(document)
        .extractText()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  } finally {
    document.dispose();
  }
}
