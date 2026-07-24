import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_receipt.dart';
import 'package:vinabike_erp/modules/purchases/widgets/purchase_receipt_history_panel.dart';

void main() {
  testWidgets('surfaces and confirms the audited receipt reversal',
      (tester) async {
    var voidedReceiptId = '';
    var voidReason = '';
    PurchaseReceiptRecord? openedReceipt;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PurchaseReceiptHistoryPanel(
            invoiceId: 'invoice-1',
            onReceiptTap: (receipt) => openedReceipt = receipt,
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
            resolutionLoader: (_) async => const [],
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

    expect(find.text('REC-00001'), findsOneWidget);
    expect(find.text(' · 2 aceptadas'), findsOneWidget);
    await tester.tap(find.text('REC-00001'));
    expect(openedReceipt?.id, 'receipt-1');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Anular'));
    await tester.pumpAndSettle();
    expect(find.text('Anular recepción REC-00001'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'Recepción duplicada de prueba',
    );
    await tester.pump();
    expect(
      find.textContaining('retirará del inventario las unidades aceptadas'),
      findsOneWidget,
    );
    expect(
      find.textContaining('primero debes anular esas operaciones dependientes'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Crear reversa'));
    await tester.pumpAndSettle();

    expect(voidedReceiptId, 'receipt-1');
    expect(voidReason, 'Recepción duplicada de prueba');
    expect(
      find.text('Recepción REC-00001 anulada con trazabilidad completa.'),
      findsOneWidget,
    );
  });
}
