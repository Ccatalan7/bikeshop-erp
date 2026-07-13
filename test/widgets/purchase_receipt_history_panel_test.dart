import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_receipt.dart';
import 'package:vinabike_erp/modules/purchases/widgets/purchase_receipt_history_panel.dart';

void main() {
  testWidgets('surfaces and confirms the audited receipt reversal',
      (tester) async {
    var voidedReceiptId = '';
    var voidReason = '';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PurchaseReceiptHistoryPanel(
            invoiceId: 'invoice-1',
            historyLoader: (_) async => [
              PurchaseReceiptRecord(
                id: 'receipt-1',
                number: 'REC-00001',
                status: 'posted',
                receivedAt: DateTime(2026, 7, 13),
                acceptedQuantity: 2,
                discrepancyQuantity: 0,
                locationLabel: 'Bodega principal',
              ),
            ],
            receiptVoider: ({
              required receiptId,
              required reason,
              required idempotencyKey,
            }) async {
              voidedReceiptId = receiptId;
              voidReason = reason;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('REC-00001 · 2 aceptadas'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Anular'));
    await tester.pumpAndSettle();
    expect(find.text('Anular recepción REC-00001'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'Recepción duplicada de prueba',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Anular con reversión'));
    await tester.pumpAndSettle();

    expect(voidedReceiptId, 'receipt-1');
    expect(voidReason, 'Recepción duplicada de prueba');
    expect(
      find.text('Recepción REC-00001 anulada con trazabilidad completa.'),
      findsOneWidget,
    );
  });
}
