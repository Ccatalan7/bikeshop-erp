import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/document_accounting_context_service.dart';
import 'package:vinabike_erp/shared/widgets/document_accounting_preview.dart';

void main() {
  testWidgets('document accounting preview fits narrow split panes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final payments = [
      DocumentPaymentRecord(
        id: 'payment-1',
        number: 'COB-000001',
        date: DateTime(2026, 5, 15),
        status: 'Pagada',
        methodName: 'Tarjeta de credito',
        amount: 65000,
        reference: 'POS-123',
      ),
    ];
    DocumentPaymentRecord? tappedPayment;

    final journalEntries = [
      DocumentJournalEntryRecord(
        id: 'journal-1',
        entryNumber: 'JE-000001',
        date: DateTime(2026, 5, 15),
        description: 'Factura FV-00650',
        status: 'posted',
        sourceModule: 'sales_invoices',
        sourceReference: 'FV-00650',
        totalDebit: 65000,
        totalCredit: 65000,
        lines: const [
          DocumentJournalLineRecord(
            accountCode: '1105',
            accountName: 'Cuentas por cobrar',
            description: '',
            debitAmount: 65000,
            creditAmount: 0,
          ),
          DocumentJournalLineRecord(
            accountCode: '4101',
            accountName: 'Ventas',
            description: '',
            debitAmount: 0,
            creditAmount: 65000,
          ),
        ],
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const DocumentPaperShell(
                    width: 260,
                    status: DocumentPaperStatus(
                      label: 'PAGO PARCIAL',
                      foreground: Color(0xFFB45309),
                      background: Color(0xFFFFFBEB),
                      border: Color(0xFFFDE68A),
                    ),
                    child: SizedBox(height: 140),
                  ),
                  DocumentPaymentsDropdown(
                    title: 'Pagos recibidos',
                    payments: payments,
                    onPaymentTap: (payment) => tappedPayment = payment,
                  ),
                  DocumentJournalEntriesSection(
                    entries: journalEntries,
                    documentLabel: 'Factura',
                    emptyReference: 'FV-00650',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Pagos recibidos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('COB-000001'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(tappedPayment?.id, 'payment-1');
  });
}
