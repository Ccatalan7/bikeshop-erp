import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;
import 'package:vinabike_erp/modules/purchases/models/purchase_invoice.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_payment.dart';
import 'package:vinabike_erp/shared/utils/purchase_payment_receipt_pdf_generator.dart';

void main() {
  group('PurchasePaymentReceiptPdfGenerator', () {
    test('derives a stable payment number and file name from the UUID suffix',
        () {
      final payment = _paymentFixture();

      expect(
        PurchasePaymentReceiptPdfGenerator.paymentNumber(payment),
        'PAG-34FB00',
      );
      expect(
        PurchasePaymentReceiptPdfGenerator.fileName(payment),
        'comprobante_pago_proveedor_PAG-34FB00.pdf',
      );
    });

    test('renders a supplier-payment receipt with honest ownership copy',
        () async {
      final document = await PurchasePaymentReceiptPdfGenerator.generate(
        payment: _paymentFixture(),
        invoice: _invoiceFixture(),
        paymentMethodName: 'Transferencia bancaria',
        businessName: 'Viñabike',
      );

      final bytes = await document.save();
      final samplePath =
          Platform.environment['PURCHASE_PAYMENT_RECEIPT_SAMPLE_PATH'];
      if (samplePath != null && samplePath.trim().isNotEmpty) {
        final output = File(samplePath);
        await output.parent.create(recursive: true);
        await output.writeAsBytes(bytes, flush: true);
      }
      final text = _extractText(bytes);

      expect(bytes.length, greaterThan(4000));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(text, contains('Comprobante interno de pago a proveedor'));
      expect(text, contains('No constituye factura ni DTE'));
      expect(text, contains('PAG-34FB00'));
      expect(text, contains('154.000'));
      expect(text, contains('14/07/2026'));
      expect(text, contains('Proveedor de Prueba'));
      expect(text, contains('76.123.456-7'));
      expect(text, contains('FC-00152'));
      expect(text, contains('PROV-7788'));
      expect(text, contains('Transferencia bancaria'));
      expect(text, contains('TRANSFER-7788'));
      expect(text, contains('Pago confirmado por tesorería.'));
      expect(text, contains('Total factura'));
      expect(text, contains('Total pagado'));
      expect(text, contains('Saldo actual'));
      expect(text, contains('IVA recuperable'));
      expect(text, contains('cuentas por pagar'));
      expect(text, contains('no mueve stock'));
      expect(text, contains('No acredita por sí solo'));
      expect(text, isNot(contains('Monto recibido')));
      expect(text, isNot(contains('Cliente de Prueba')));
      expect(text, isNot(contains('FACTURA ELECTRÓNICA')));
    });
  });
}

PurchasePayment _paymentFixture() {
  return PurchasePayment(
    id: '11111111-2222-4333-8444-55555534fb00',
    tenantId: 'tenant-1',
    invoiceId: 'invoice-1',
    invoiceNumber: 'FC-00152',
    supplierName: 'Proveedor de Prueba',
    paymentMethodId: 'method-1',
    amount: 154000,
    date: DateTime(2026, 7, 14),
    reference: 'TRANSFER-7788',
    notes: 'Pago confirmado por tesorería.',
  );
}

PurchaseInvoice _invoiceFixture() {
  return PurchaseInvoice(
    id: 'invoice-1',
    tenantId: 'tenant-1',
    invoiceNumber: 'FC-00152',
    supplierId: 'supplier-1',
    supplierName: 'Proveedor de Prueba',
    supplierRut: '76.123.456-7',
    date: DateTime(2026, 7, 13),
    supplierInvoiceNumber: 'PROV-7788',
    supplierInvoiceDate: DateTime(2026, 7, 12),
    status: PurchaseInvoiceStatus.received,
    total: 200000,
    paidAmount: 154000,
    balance: 46000,
    prepaymentModel: false,
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
