import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_receipt_resolution.dart';
import 'package:vinabike_erp/modules/purchases/widgets/purchase_receipt_resolution_register.dart';

void main() {
  testWidgets('keeps open cases visible and opens their source record',
      (tester) async {
    PurchaseReceiptResolutionCase? opened;
    final resolutionCase = PurchaseReceiptResolutionCase(
      id: 'case-1',
      number: 'CR-00001',
      purchaseInvoiceId: 'invoice-1',
      purchaseReceiptId: 'receipt-1',
      purchaseReceiptNumber: 'REC-00001',
      purchaseReceiptLineId: 'line-1',
      sourceLineIndex: 0,
      sourceLineKey: 'source-1',
      productName: 'Cadena KMC X9',
      purchaseTreatment: 'inventory',
      kind: PurchaseReceiptDiscrepancyKind.shortage,
      reportedQuantity: 2,
      resolvedQuantity: 0,
      openQuantity: 2,
      effectiveStatus: 'open',
      createdAt: DateTime.utc(2026, 7, 24),
      allocations: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 980,
            child: PurchaseReceiptResolutionRegister(
              cases: [resolutionCase],
              onCaseTap: (value) => opened = value,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Diferencias y resoluciones'), findsOneWidget);
    expect(find.text('1 pendiente'), findsOneWidget);
    expect(find.text('CR-00001 · Cadena KMC X9'), findsOneWidget);
    expect(find.text('2 de 2 pendientes'), findsOneWidget);
    expect(find.text('Sin resolución registrada'), findsOneWidget);

    await tester.tap(find.text('Abrir caso'));
    expect(opened?.id, 'case-1');
  });

  testWidgets('links the exact resolution documents from the invoice register',
      (tester) async {
    final opened = <PurchaseReceiptResolutionDocumentReference>[];
    final allocation = PurchaseReceiptResolutionAllocation(
      id: 'allocation-1',
      caseId: 'case-1',
      resolutionGroupId: 'group-1',
      outcome: PurchaseReceiptResolutionOutcome.creditNote,
      quantity: 1,
      effectiveStatus: 'posted',
      isEffective: true,
      createdAt: DateTime.utc(2026, 7, 24),
      purchaseCreditNoteId: 'credit-1',
      purchaseCreditNoteNumber: 'NC-00012',
      supplierReturnId: 'return-1',
      supplierReturnNumber: 'DEV-00004',
      supplierRefunds: const [
        PurchaseReceiptSupplierRefundReference(
          id: 'refund-1',
          number: 'REF-00003',
          status: 'posted',
          amount: 10000,
        ),
      ],
    );
    final resolutionCase = PurchaseReceiptResolutionCase(
      id: 'case-1',
      number: 'CR-00001',
      purchaseInvoiceId: 'invoice-1',
      purchaseReceiptId: 'receipt-1',
      purchaseReceiptNumber: 'REC-00001',
      purchaseReceiptLineId: 'line-1',
      sourceLineIndex: 0,
      sourceLineKey: 'source-1',
      productName: 'Piñón',
      purchaseTreatment: 'inventory',
      kind: PurchaseReceiptDiscrepancyKind.damaged,
      reportedQuantity: 1,
      resolvedQuantity: 1,
      openQuantity: 0,
      effectiveStatus: 'resolved',
      createdAt: DateTime.utc(2026, 7, 24),
      allocations: [allocation],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 980,
            child: PurchaseReceiptResolutionRegister(
              cases: [resolutionCase],
              onDocumentTap: (_, __, document) => opened.add(document),
            ),
          ),
        ),
      ),
    );

    expect(find.text('NC-00012'), findsOneWidget);
    expect(find.text('Dev. DEV-00004'), findsOneWidget);
    expect(find.text('Reembolso REF-00003'), findsOneWidget);
    expect(find.text('Aplicada'), findsOneWidget);

    await tester.tap(find.text('NC-00012'));
    await tester.tap(find.text('Dev. DEV-00004'));
    await tester.tap(find.text('Reembolso REF-00003'));

    expect(
      opened.map((document) => document.kind),
      [
        PurchaseReceiptResolutionDocumentKind.creditNote,
        PurchaseReceiptResolutionDocumentKind.supplierReturn,
        PurchaseReceiptResolutionDocumentKind.supplierRefund,
      ],
    );
    expect(opened.map((document) => document.id), [
      'credit-1',
      'return-1',
      'refund-1',
    ]);
  });

  testWidgets('keeps voided document evidence visible and labels it honestly',
      (tester) async {
    final allocation = PurchaseReceiptResolutionAllocation(
      id: 'allocation-void',
      caseId: 'case-1',
      resolutionGroupId: 'group-1',
      outcome: PurchaseReceiptResolutionOutcome.creditNote,
      quantity: 1,
      effectiveStatus: 'voided',
      isEffective: false,
      createdAt: DateTime.utc(2026, 7, 24),
      purchaseCreditNoteId: 'credit-void',
      purchaseCreditNoteNumber: 'NC-ANULADA',
    );
    final resolutionCase = PurchaseReceiptResolutionCase(
      id: 'case-1',
      number: 'CR-00001',
      purchaseInvoiceId: 'invoice-1',
      purchaseReceiptId: 'receipt-1',
      purchaseReceiptLineId: 'line-1',
      sourceLineIndex: 0,
      sourceLineKey: 'source-1',
      productName: 'Cadena',
      purchaseTreatment: 'inventory',
      kind: PurchaseReceiptDiscrepancyKind.shortage,
      reportedQuantity: 1,
      resolvedQuantity: 0,
      openQuantity: 1,
      effectiveStatus: 'open',
      createdAt: DateTime.utc(2026, 7, 24),
      allocations: [allocation],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 980,
            child: PurchaseReceiptResolutionRegister(
              cases: [resolutionCase],
            ),
          ),
        ),
      ),
    );

    expect(find.text('NC-ANULADA'), findsOneWidget);
    expect(find.text('Anulada'), findsOneWidget);
    expect(find.text('1 de 1 pendientes'), findsOneWidget);
  });

  testWidgets('marks history without effect when the source receipt is voided',
      (tester) async {
    final allocation = PurchaseReceiptResolutionAllocation(
      id: 'allocation-source-void',
      caseId: 'case-void',
      resolutionGroupId: 'group-void',
      outcome: PurchaseReceiptResolutionOutcome.creditNote,
      quantity: 1,
      effectiveStatus: 'posted',
      isEffective: false,
      createdAt: DateTime.utc(2026, 7, 24),
      purchaseCreditNoteId: 'credit-voided-source',
      purchaseCreditNoteNumber: 'NC-00018',
    );
    final resolutionCase = PurchaseReceiptResolutionCase(
      id: 'case-void',
      number: 'CR-00004',
      purchaseInvoiceId: 'invoice-1',
      purchaseReceiptId: 'receipt-void',
      purchaseReceiptNumber: 'REC-ANULADA',
      purchaseReceiptLineId: 'line-void',
      sourceLineIndex: 0,
      sourceLineKey: 'source-void',
      productName: 'Cambio Sensah',
      purchaseTreatment: 'inventory',
      kind: PurchaseReceiptDiscrepancyKind.rejected,
      reportedQuantity: 1,
      resolvedQuantity: 0,
      openQuantity: 1,
      effectiveStatus: 'voided',
      createdAt: DateTime.utc(2026, 7, 24),
      allocations: [allocation],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 980,
            child: PurchaseReceiptResolutionRegister(
              cases: [resolutionCase],
            ),
          ),
        ),
      ),
    );

    expect(find.text('1 sin efecto'), findsOneWidget);
    expect(find.text('Recepción anulada'), findsOneWidget);
    expect(find.text('NC-00018'), findsOneWidget);
    expect(
      find.text('Sin efecto por recepción anulada'),
      findsOneWidget,
    );
    expect(find.text('Ver recepción'), findsOneWidget);
  });

  testWidgets(
      'shows loss and reversal history without presenting fake journal links',
      (tester) async {
    final opened = <PurchaseReceiptResolutionDocumentReference>[];
    final loss = PurchaseReceiptResolutionAllocation(
      id: 'allocation-loss',
      caseId: 'case-loss',
      resolutionGroupId: 'group-loss',
      outcome: PurchaseReceiptResolutionOutcome.documentedLoss,
      quantity: 1,
      effectiveStatus: 'voided',
      isEffective: false,
      createdAt: DateTime.utc(2026, 7, 24),
      lossJournalEntryId: 'journal-loss',
      lossJournalEntryNumber: 'ASI-00021',
    );
    final reversal = PurchaseReceiptResolutionAllocation(
      id: 'allocation-reversal',
      caseId: 'case-loss',
      resolutionGroupId: 'group-reversal',
      outcome: PurchaseReceiptResolutionOutcome.documentedLossReversal,
      quantity: 1,
      effectiveStatus: 'reversal',
      isEffective: false,
      createdAt: DateTime.utc(2026, 7, 25),
      lossJournalEntryId: 'journal-reversal',
      lossJournalEntryNumber: 'ASI-00022',
    );
    final resolutionCase = PurchaseReceiptResolutionCase(
      id: 'case-loss',
      number: 'CR-00005',
      purchaseInvoiceId: 'invoice-1',
      purchaseReceiptId: 'receipt-1',
      purchaseReceiptNumber: 'REC-00001',
      purchaseReceiptLineId: 'line-loss',
      sourceLineIndex: 0,
      sourceLineKey: 'source-loss',
      productName: 'Piñón Sunshine',
      purchaseTreatment: 'inventory',
      kind: PurchaseReceiptDiscrepancyKind.damaged,
      reportedQuantity: 1,
      resolvedQuantity: 0,
      openQuantity: 1,
      effectiveStatus: 'open',
      createdAt: DateTime.utc(2026, 7, 24),
      allocations: [loss, reversal],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 980,
            child: PurchaseReceiptResolutionRegister(
              cases: [resolutionCase],
              onDocumentTap: (_, __, document) => opened.add(document),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Asiento ASI-00021'), findsOneWidget);
    expect(find.text('Revertida'), findsOneWidget);
    expect(find.text('Reversa ASI-00022'), findsOneWidget);
    expect(find.text('Reversa registrada'), findsOneWidget);

    await tester.tap(find.text('Asiento ASI-00021'));
    await tester.tap(find.text('Reversa ASI-00022'));
    expect(opened, isEmpty);
  });

  testWidgets('uses a compact, actionable layout at narrow split widths',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(340, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    PurchaseReceiptResolutionCase? opened;
    final resolutionCase = PurchaseReceiptResolutionCase(
      id: 'case-narrow',
      number: 'CR-00006',
      purchaseInvoiceId: 'invoice-1',
      purchaseReceiptId: 'receipt-1',
      purchaseReceiptLineId: 'line-narrow',
      sourceLineIndex: 0,
      sourceLineKey: 'source-narrow',
      productName: 'Cámara de bicicleta con nombre extenso',
      purchaseTreatment: 'inventory',
      kind: PurchaseReceiptDiscrepancyKind.shortage,
      reportedQuantity: 2,
      resolvedQuantity: 0,
      openQuantity: 2,
      effectiveStatus: 'open',
      createdAt: DateTime.utc(2026, 7, 24),
      allocations: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PurchaseReceiptResolutionRegister(
            cases: [resolutionCase],
            onCaseTap: (value) => opened = value,
          ),
        ),
      ),
    );

    expect(
      find.byKey(
        const ValueKey('purchase-receipt-resolution-compact-list'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Abrir caso'));
    expect(opened?.id, 'case-narrow');
  });
}
