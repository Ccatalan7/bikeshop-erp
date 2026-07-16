import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;
import 'package:vinabike_erp/modules/sales/models/sales_models.dart';
import 'package:vinabike_erp/shared/utils/invoice_pdf_generator.dart';

void main() {
  group('Invoice PDF commercial document kind', () {
    test('keeps invoice filenames and exposes quotation-specific helpers', () {
      expect(
        InvoicePdfDocumentKind.invoice.fileNameFor('FV-00809'),
        'factura_FV-00809.pdf',
      );
      expect(
        InvoicePdfGenerator.quotationFileNameFor('PG-00468'),
        'presupuesto_PG-00468.pdf',
      );
      expect(
        InvoicePdfGenerator.quotationDocumentNameFor('PG-00468'),
        'presupuesto_PG-00468',
      );
    });

    test(
      'quotation PDF never presents an invoice or payment balance',
      () async {
        final quotation = _documentFixture().copyWith(
          subtotal: 100000,
          total: 90000,
        );
        final pdf = InvoicePdfGenerator.buildDocumentPDF(
          quotation,
          const <String, String>{'single': 'Oxford Merak 1'},
          documentKind: InvoicePdfDocumentKind.quotation,
          validUntil: DateTime(2026, 7, 30),
          discountAmount: 10000,
        );

        final bytes = await pdf.save();
        final extracted = _extractText(bytes);

        expect(extracted, contains('PRESUPUESTO'));
        expect(extracted, contains('Presupuesto para'));
        expect(extracted, contains('Fecha del presupuesto'));
        expect(extracted, contains('Válido hasta'));
        expect(extracted, contains('Total presupuesto'));
        expect(extracted, contains('Descuento'));
        expect(
          extracted,
          contains('Este presupuesto no constituye una factura'),
        );
        expect(extracted, isNot(contains('Facturar a')));
        expect(extracted, isNot(contains('Fecha de la factura')));
        expect(extracted, isNot(contains('Saldo adeudado')));
        expect(extracted, isNot(contains('Pago realizado')));
      },
    );

    test(
      'default PDF remains an invoice with its existing balance wording',
      () async {
        final invoice = _documentFixture();
        final pdf = InvoicePdfGenerator.buildDocumentPDF(
          invoice,
          const <String, String>{'single': 'Oxford Merak 1'},
        );

        final bytes = await pdf.save();
        final extracted = _extractText(bytes);

        expect(extracted, contains('Facturar a'));
        expect(extracted, contains('Fecha de la factura'));
        expect(extracted, contains('Saldo adeudado'));
        expect(extracted, contains('Pago realizado'));
        expect(extracted, isNot(contains('PRESUPUESTO')));
      },
    );
  });
}

Invoice _documentFixture() {
  return Invoice(
    tenantId: 'tenant-1',
    invoiceNumber: 'PG-00468',
    customerName: 'Cliente de Prueba',
    customerRut: '12.345.678-5',
    date: DateTime(2026, 7, 15),
    dueDate: DateTime(2026, 7, 30),
    subtotal: 90000,
    total: 90000,
    paidAmount: 10000,
    balance: 80000,
    bikeId: 'bike-1',
    items: <InvoiceItem>[
      InvoiceItem(
        productName: 'Cambio de transmisión',
        description: 'Repuestos y mano de obra sujetos a aprobación.',
        unitPrice: 90000,
        lineTotal: 90000,
        isService: true,
      ),
    ],
  );
}

String _extractText(List<int> bytes) {
  final document = syncfusion.PdfDocument(inputBytes: bytes);
  try {
    return syncfusion.PdfTextExtractor(
      document,
    ).extractText().replaceAll(RegExp(r'\s+'), ' ').trim();
  } finally {
    document.dispose();
  }
}
