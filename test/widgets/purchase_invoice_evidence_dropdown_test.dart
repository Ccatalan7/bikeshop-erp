import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_receipt.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_receipt_resolution.dart';
import 'package:vinabike_erp/modules/purchases/widgets/purchase_invoice_evidence_dropdown.dart';
import 'package:vinabike_erp/shared/services/document_accounting_context_service.dart';

void main() {
  testWidgets(
      'combines payments, receipts and differences in one collapsed register',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    DocumentPaymentRecord? openedPayment;
    PurchaseReceiptRecord? openedReceipt;
    PurchaseReceiptResolutionCase? openedCase;
    final payments = [
      _payment(id: 'payment-1', number: 'PAG-00001'),
      _payment(id: 'payment-2', number: 'PAG-00002'),
    ];
    final receipt = _receipt();
    final resolutionCase = _resolutionCase();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            child: PurchaseInvoiceEvidenceDropdown(
              payments: payments,
              receipts: [receipt],
              resolutionCases: [resolutionCase],
              onPaymentTap: (value) => openedPayment = value,
              onReceiptTap: (value) => openedReceipt = value,
              onResolutionCaseTap: (value) => openedCase = value,
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('purchase-invoice-evidence-dropdown')),
      findsOneWidget,
    );
    expect(find.text('Pagos'), findsOneWidget);
    expect(find.text('Recepciones'), findsOneWidget);
    expect(find.text('Diferencias'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('evidence-count-Pagos realizados'),
        ),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('evidence-count-Recepciones de stock'),
        ),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('evidence-count-Diferencias y resoluciones'),
        ),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('purchase-invoice-evidence-pending-indicator'),
      ),
      findsOneWidget,
    );
    expect(find.text('PAG-00001'), findsNothing);
    expect(find.text('REC-00042'), findsNothing);
    expect(find.text('CR-00001 · Cadena KMC X9'), findsNothing);

    await tester.tap(
      find.byKey(
        const ValueKey('purchase-invoice-evidence-tab-payments'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PAG-00001'), findsOneWidget);
    expect(find.text('REC-00042'), findsNothing);
    await tester.tap(find.text('PAG-00001'));
    expect(openedPayment?.id, 'payment-1');

    await tester.tap(
      find.byKey(
        const ValueKey('purchase-invoice-evidence-tab-receipts'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PAG-00001'), findsNothing);
    expect(find.text('REC-00042'), findsOneWidget);
    await tester.tap(find.text('REC-00042'));
    expect(openedReceipt?.id, 'receipt-1');

    await tester.tap(
      find.byKey(
        const ValueKey('purchase-invoice-evidence-tab-resolutions'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PAG-00001'), findsNothing);
    expect(find.text('REC-00042'), findsNothing);
    expect(find.text('CR-00001 · Cadena KMC X9'), findsOneWidget);
    expect(find.text('Sin resolución registrada'), findsOneWidget);
    await tester.tap(find.text('Abrir caso'));
    expect(openedCase?.id, 'case-1');

    await tester.tap(
      find.byKey(
        const ValueKey('purchase-invoice-evidence-disclosure'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('CR-00001 · Cadena KMC X9'), findsNothing);

    await tester.tap(
      find.byKey(
        const ValueKey('purchase-invoice-evidence-disclosure'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('CR-00001 · Cadena KMC X9'), findsOneWidget);
    expect(find.text('PAG-00001'), findsNothing);
  });

  testWidgets('selects the first non-empty tab and hides an empty register',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PurchaseInvoiceEvidenceDropdown(
            payments: const [],
            receipts: [_receipt()],
          ),
        ),
      ),
    );

    expect(find.text('Pagos'), findsNothing);
    expect(find.text('Recepciones'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey('purchase-invoice-evidence-disclosure'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('REC-00042'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PurchaseInvoiceEvidenceDropdown(
            payments: [],
            receipts: [],
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('purchase-invoice-evidence-dropdown')),
      findsNothing,
    );
  });

  testWidgets('keeps all tabs usable in a narrow split pane', (tester) async {
    await tester.binding.setSurfaceSize(const Size(340, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PurchaseInvoiceEvidenceDropdown(
            payments: [_payment(id: 'payment-1', number: 'PAG-00001')],
            receipts: [_receipt()],
            resolutionCases: [_resolutionCase()],
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(
        const ValueKey('purchase-invoice-evidence-tab-payments'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('PAG-00001'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final receiptTab = find.byKey(
      const ValueKey('purchase-invoice-evidence-tab-receipts'),
    );
    await tester.ensureVisible(receiptTab);
    await tester.pumpAndSettle();
    await tester.tap(receiptTab);
    await tester.pumpAndSettle();

    expect(find.text('REC-00042'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final resolutionTab = find.byKey(
      const ValueKey('purchase-invoice-evidence-tab-resolutions'),
    );
    await tester.ensureVisible(resolutionTab);
    await tester.pumpAndSettle();
    await tester.tap(resolutionTab);
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey('purchase-receipt-resolution-compact-list'),
      ),
      findsOneWidget,
    );
    expect(find.text('CR-00001 · Cadena KMC X9'), findsOneWidget);
    expect(find.text('Abrir caso'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps a resolved-only difference register available',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PurchaseInvoiceEvidenceDropdown(
            payments: const [],
            receipts: const [],
            resolutionCases: [
              _resolutionCase(
                effectiveStatus: 'resolved',
                resolvedQuantity: 2,
                openQuantity: 0,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Diferencias'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('purchase-invoice-evidence-pending-indicator'),
      ),
      findsNothing,
    );
    await tester.tap(
      find.byKey(
        const ValueKey('purchase-invoice-evidence-disclosure'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 de 2 resueltas'), findsOneWidget);
    expect(find.text('Ver registro'), findsOneWidget);
  });
}

DocumentPaymentRecord _payment({
  required String id,
  required String number,
}) {
  return DocumentPaymentRecord(
    id: id,
    number: number,
    date: DateTime(2026, 7, 24),
    status: 'Pagada',
    methodName: 'Transferencia',
    amount: 45399,
    reference: 'MOCK-REC-01',
  );
}

PurchaseReceiptRecord _receipt() {
  return PurchaseReceiptRecord(
    id: 'receipt-1',
    number: 'REC-00042',
    status: 'posted',
    receivedAt: DateTime(2026, 7, 24),
    acceptedQuantity: 5,
    discrepancyQuantity: 0,
    locationLabel: 'Bodega principal',
  );
}

PurchaseReceiptResolutionCase _resolutionCase({
  String effectiveStatus = 'open',
  int resolvedQuantity = 0,
  int openQuantity = 2,
  List<PurchaseReceiptResolutionAllocation> allocations = const [],
}) {
  return PurchaseReceiptResolutionCase(
    id: 'case-1',
    number: 'CR-00001',
    purchaseInvoiceId: 'invoice-1',
    purchaseReceiptId: 'receipt-1',
    purchaseReceiptNumber: 'REC-00042',
    purchaseReceiptLineId: 'line-1',
    sourceLineIndex: 0,
    sourceLineKey: 'source-1',
    productName: 'Cadena KMC X9',
    productSku: '19007',
    purchaseTreatment: 'inventory',
    kind: PurchaseReceiptDiscrepancyKind.shortage,
    reportedQuantity: 2,
    resolvedQuantity: resolvedQuantity,
    openQuantity: openQuantity,
    effectiveStatus: effectiveStatus,
    createdAt: DateTime.utc(2026, 7, 24),
    allocations: allocations,
  );
}
