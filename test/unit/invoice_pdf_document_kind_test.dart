import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;
import 'package:vinabike_erp/modules/sales/models/sales_models.dart';
import 'package:vinabike_erp/shared/utils/invoice_pdf_generator.dart';

void main() {
  group('Invoice PDF commercial document kind', () {
    test('uses different names for invoice, quotation and service budget', () {
      expect(
        InvoicePdfDocumentKind.invoice.fileNameFor('FV-00809'),
        'factura_FV-00809.pdf',
      );
      expect(
        InvoicePdfGenerator.quotationFileNameFor('PG-00468'),
        'cotizacion_PG-00468.pdf',
      );
      expect(
        InvoicePdfGenerator.quotationDocumentNameFor('PG-00468'),
        'cotizacion_PG-00468',
      );
      expect(
        InvoicePdfGenerator.serviceBudgetFileNameFor('PG-00465'),
        'presupuesto_PG-00465.pdf',
      );
      expect(
        InvoicePdfGenerator.serviceBudgetDocumentNameFor('PG-00465'),
        'presupuesto_PG-00465',
      );
    });

    test(
      'standalone quotation has no received object, invoice or balance',
      () async {
        final quotation = _documentFixture().copyWith(
          subtotal: 100000,
          total: 90000,
          workDescription: 'Instalación de horquilla Fox 34',
          items: <InvoiceItem>[
            InvoiceItem(
              productName: 'Transmisión',
              unitPrice: 60000,
              jobBikeId: 'stale-job-bike-1',
              bikeName: 'Oxford Merak 1',
            ),
            InvoiceItem(
              productName: 'Frenos',
              unitPrice: 40000,
              jobBikeId: 'stale-job-bike-2',
              bikeName: 'Trek Marlin 5',
            ),
          ],
        );
        final pdf = InvoicePdfGenerator.buildDocumentPDF(
          quotation,
          const <String, String>{
            'single': 'Oxford Merak 1',
            'stale-job-bike-1': 'Oxford Merak 1',
            'stale-job-bike-2': 'Trek Marlin 5',
          },
          documentKind: InvoicePdfDocumentKind.quotation,
          validUntil: DateTime(2026, 7, 30),
          discountAmount: 10000,
        );

        final bytes = await pdf.save();
        final extracted = _extractText(bytes);

        expect(extracted, contains('COTIZACIÓN'));
        expect(extracted, contains('Cotización para'));
        expect(extracted, contains('Fecha de la cotización'));
        expect(extracted, contains('Válido hasta'));
        expect(extracted, contains('Total cotización'));
        expect(extracted, contains('Descuento'));
        expect(
          extracted,
          contains('Esta cotización no constituye una factura'),
        );
        expect(
          extracted,
          contains('ni acredita recepción de bicicleta o componente'),
        );
        expect(extracted, contains('Descripción de la cotización'));
        expect(extracted, contains('Instalación de horquilla Fox 34'));
        expect(extracted, isNot(contains('PRESUPUESTO')));
        expect(extracted, isNot(contains('Bicicleta recibida')));
        expect(extracted, isNot(contains('Oxford Merak 1')));
        expect(extracted, isNot(contains('Trek Marlin 5')));
        expect(extracted, isNot(contains('Facturar a')));
        expect(extracted, isNot(contains('Fecha de la factura')));
        expect(extracted, isNot(contains('Saldo adeudado')));
        expect(extracted, isNot(contains('Pago realizado')));
      },
    );

    test('quotation without catalog lines still explains what was requested',
        () async {
      final quotation = _documentFixture().copyWith(
        items: const <InvoiceItem>[],
        subtotal: 0,
        total: 0,
        workDescription: 'Limpieza completa de transmisión',
      );
      final pdf = InvoicePdfGenerator.buildDocumentPDF(
        quotation,
        const <String, String>{},
        documentKind: InvoicePdfDocumentKind.quotation,
      );

      final extracted = _extractText(await pdf.save());
      expect(extracted, contains('Descripción de la cotización'));
      expect(extracted, contains('Limpieza completa de transmisión'));
      expect(extracted, contains('COTIZACIÓN'));
      expect(extracted, isNot(contains('Bicicleta recibida')));
    });

    test(
      'service budget names every received bike and remains non-posting',
      () async {
        final budget = _documentFixture().copyWith(
          subtotal: 120000,
          total: 110000,
          items: <InvoiceItem>[
            InvoiceItem(
              productName: 'Transmisión',
              unitPrice: 70000,
              lineTotal: 70000,
              jobBikeId: 'job-bike-1',
            ),
            InvoiceItem(
              productName: 'Frenos',
              unitPrice: 50000,
              lineTotal: 50000,
              jobBikeId: 'job-bike-2',
            ),
          ],
        );
        final pdf = InvoicePdfGenerator.buildDocumentPDF(
          budget,
          const <String, String>{
            'job-bike-1': 'Oxford Merak 1',
            'job-bike-2': 'Trek Marlin 5',
          },
          documentKind: InvoicePdfDocumentKind.serviceBudget,
          validUntil: DateTime(2026, 7, 30),
          discountAmount: 10000,
        );

        final bytes = await pdf.save();
        final extracted = _extractText(bytes);

        expect(extracted, contains('PRESUPUESTO'));
        expect(extracted, contains('Presupuesto para'));
        expect(extracted, contains('Fecha del presupuesto'));
        expect(extracted, contains('Total presupuesto'));
        expect(extracted, contains('Bicicletas recibidas'));
        expect(extracted, contains('Oxford Merak 1'));
        expect(extracted, contains('Trek Marlin 5'));
        expect(
          extracted,
          contains('Este presupuesto no constituye una factura'),
        );
        expect(extracted, isNot(contains('COTIZACIÓN')));
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
        expect(extracted, isNot(contains('COTIZACIÓN')));
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
