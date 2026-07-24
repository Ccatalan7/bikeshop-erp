import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_invoice.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_receipt.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_receipt_resolution.dart';
import 'package:vinabike_erp/modules/purchases/widgets/purchase_receipt_detail_view.dart';
import 'package:vinabike_erp/modules/purchases/widgets/purchase_receipt_resolution_register.dart';

void main() {
  testWidgets(
    'renders a flat receipt record with compact facts and complete evidence',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      PurchaseReceiptResolutionCase? openedCase;
      PurchaseReceiptResolutionAllocation? legacyAllocation;
      PurchaseReceiptResolutionAllocation? voidedLoss;
      final openedDocuments = <PurchaseReceiptResolutionDocumentReference>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PurchaseReceiptDetailView(
              receipt: _receipt(),
              invoice: _invoice(),
              resolutionCases: _resolutionCases(),
              productImageUrls: const {
                'product-1': 'asset:assets/images/chain_icon.png',
              },
              onOpenInvoice: () {},
              onRefresh: () async {},
              onResolveCase: (value) => openedCase = value,
              onOpenAllocation: (value) => legacyAllocation = value,
              onResolutionDocumentTap: (_, __, document) {
                openedDocuments.add(document);
              },
              onVoidLoss: (value) => voidedLoss = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final detail = find.byType(PurchaseReceiptDetailView);
      expect(
        find.descendant(of: detail, matching: find.byType(Scaffold)),
        findsNothing,
      );
      expect(find.text('Recepción REC-00042'), findsOneWidget);
      expect(find.text('Factura 51611 · Comercial Ciclo'), findsOneWidget);
      expect(find.text('PRODUCTO'), findsOneWidget);
      expect(find.text('PEDIDO'), findsOneWidget);
      expect(find.text('RECIBIDO'), findsOneWidget);
      expect(find.text('DIFERENCIA'), findsNWidgets(2));
      expect(find.text('SALDO'), findsNothing);
      expect(find.text('MOTIVO / EVIDENCIA'), findsOneWidget);
      expect(find.text('ANTERIOR'), findsNothing);
      expect(find.text('DAÑADO'), findsNothing);
      expect(find.text('RECHAZADO'), findsNothing);
      expect(find.text('FALTANTE'), findsNothing);
      expect(find.text('Dañado 1 · Faltante 1'), findsOneWidget);
      expect(find.textContaining('Recibido antes: 1'), findsOneWidget);
      expect(find.textContaining('Saldo pendiente: 2'), findsOneWidget);
      expect(find.text('1 diferencia pendiente'), findsOneWidget);
      expect(find.text('1 de 2 pendientes'), findsOneWidget);
      expect(find.text('1 de 1 resueltas'), findsNWidgets(2));
      expect(find.text('Revertida'), findsOneWidget);

      final firstThumbnail = find.byKey(
        const ValueKey('purchase-receipt-thumbnail-line-1'),
      );
      final secondThumbnail = find.byKey(
        const ValueKey('purchase-receipt-thumbnail-line-2'),
      );
      expect(
        find.descendant(of: firstThumbnail, matching: find.byType(Image)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: secondThumbnail,
          matching: find.byIcon(Icons.inventory_2_outlined),
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Resolver'));
      await tester.tap(find.widgetWithText(FilledButton, 'Resolver'));
      expect(openedCase?.id, 'case-open');

      for (final label in [
        'NC-00012',
        'REC-00043',
        'Devolución DEV-00004',
        'Reembolso REF-00003',
      ]) {
        final link = find.text(label);
        await tester.ensureVisible(link);
        await tester.tap(link);
      }
      expect(
        openedDocuments.map((document) => document.kind),
        [
          PurchaseReceiptResolutionDocumentKind.creditNote,
          PurchaseReceiptResolutionDocumentKind.laterReceipt,
          PurchaseReceiptResolutionDocumentKind.supplierReturn,
          PurchaseReceiptResolutionDocumentKind.supplierRefund,
        ],
      );
      expect(legacyAllocation, isNull);

      final journal = find.text('Ajuste JE-00007');
      expect(journal, findsOneWidget);
      expect(
        find.ancestor(of: journal, matching: find.byType(InkWell)),
        findsNothing,
      );

      final revert = find.widgetWithText(TextButton, 'Revertir');
      await tester.ensureVisible(revert);
      await tester.tap(revert);
      expect(voidedLoss?.id, 'allocation-loss');

      expect(find.text('operation-receipt-1'), findsNothing);
      final trace = find.byKey(
        const ValueKey('purchase-receipt-trace-disclosure'),
      );
      await tester.ensureVisible(trace);
      await tester.tap(trace);
      await tester.pumpAndSettle();
      expect(find.text('operation-receipt-1'), findsOneWidget);
      expect(find.textContaining('movement-component-1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
      'keeps the compact header and horizontal table usable when narrow',
      (tester) async {
    tester.view.physicalSize = const Size(700, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PurchaseReceiptDetailView(
            receipt: _receipt(),
            invoice: _invoice(),
            onOpenInvoice: () {},
            onRefresh: () async {},
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recepción REC-00042'), findsOneWidget);
    expect(find.text('Abrir factura'), findsOneWidget);
    expect(find.text('PRODUCTO'), findsOneWidget);
    expect(find.byType(Scrollbar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

PurchaseInvoice _invoice() {
  return PurchaseInvoice(
    id: 'invoice-1',
    tenantId: 'tenant-1',
    invoiceNumber: '51611',
    supplierId: 'supplier-1',
    supplierName: 'Comercial Ciclo',
    date: DateTime(2026, 7, 22),
    status: PurchaseInvoiceStatus.paid,
    total: 59958,
    paidAmount: 59958,
    balance: 0,
  );
}

PurchaseReceiptDetailRecord _receipt() {
  return PurchaseReceiptDetailRecord(
    id: 'receipt-1',
    purchaseInvoiceId: 'invoice-1',
    number: 'REC-00042',
    status: 'posted',
    receivedAt: DateTime.utc(2026, 7, 24, 18, 30),
    operationId: 'operation-receipt-1',
    createdAt: DateTime.utc(2026, 7, 24, 18, 31),
    locationLabel: 'Bodega principal',
    deliveryReference: 'GD-1234',
    notes: 'Recepción revisada junto al transportista.',
    createdBy: 'worker-1',
    lines: [
      const PurchaseReceiptLineRecord(
        id: 'line-1',
        lineIndex: 0,
        productId: 'product-1',
        productName: 'Cámara Ride 26x1,95/2,125 VA 35mm',
        productSku: '10371',
        purchaseTreatment: 'inventory',
        expectedQuantity: 6,
        previouslyReceivedQuantity: 1,
        acceptedQuantity: 2,
        damagedQuantity: 1,
        rejectedQuantity: 0,
        shortageQuantity: 1,
        remainingQuantity: 2,
        unitCost: 2090,
        stockMovementId: 'movement-main-1',
        discrepancyReason: 'Una caja golpeada y una unidad no llegó.',
        movements: [
          PurchaseReceiptMovementRecord(
            productId: 'product-1',
            stockMovementId: 'movement-component-1',
            role: 'accepted',
            quantity: 2,
          ),
        ],
      ),
      const PurchaseReceiptLineRecord(
        id: 'line-2',
        lineIndex: 1,
        productId: 'product-2',
        productName: 'Cadena KMC X9 9 velocidades',
        productSku: '19007',
        purchaseTreatment: 'inventory',
        expectedQuantity: 1,
        previouslyReceivedQuantity: 0,
        acceptedQuantity: 1,
        damagedQuantity: 0,
        rejectedQuantity: 0,
        shortageQuantity: 0,
        remainingQuantity: 0,
        unitCost: 13990,
        movements: [],
      ),
    ],
  );
}

List<PurchaseReceiptResolutionCase> _resolutionCases() {
  final creditAllocation = PurchaseReceiptResolutionAllocation(
    id: 'allocation-credit',
    caseId: 'case-resolved',
    resolutionGroupId: 'group-credit',
    outcome: PurchaseReceiptResolutionOutcome.creditNote,
    quantity: 1,
    effectiveStatus: 'posted',
    isEffective: true,
    createdAt: DateTime.utc(2026, 7, 24),
    purchaseCreditNoteId: 'credit-note-1',
    purchaseCreditNoteNumber: 'NC-00012',
    supplierReturnId: 'supplier-return-1',
    supplierReturnNumber: 'DEV-00004',
    supplierReturnStatus: 'posted',
    supplierRefunds: const [
      PurchaseReceiptSupplierRefundReference(
        id: 'refund-1',
        number: 'REF-00003',
        status: 'posted',
        amount: 2090,
      ),
    ],
  );
  final laterReceiptAllocation = PurchaseReceiptResolutionAllocation(
    id: 'allocation-later',
    caseId: 'case-resolved',
    resolutionGroupId: 'group-later',
    outcome: PurchaseReceiptResolutionOutcome.laterDelivery,
    quantity: 1,
    effectiveStatus: 'voided',
    isEffective: false,
    createdAt: DateTime.utc(2026, 7, 24),
    laterPurchaseReceiptId: 'receipt-later',
    laterPurchaseReceiptNumber: 'REC-00043',
    voidReason: 'Entrega posterior anulada y reemplazada.',
  );
  final lossAllocation = PurchaseReceiptResolutionAllocation(
    id: 'allocation-loss',
    caseId: 'case-loss',
    resolutionGroupId: 'group-loss',
    outcome: PurchaseReceiptResolutionOutcome.documentedLoss,
    quantity: 1,
    effectiveStatus: 'posted',
    isEffective: true,
    createdAt: DateTime.utc(2026, 7, 24),
    lossJournalEntryId: 'journal-1',
    lossJournalEntryNumber: 'JE-00007',
    lossOperationId: 'loss-operation-1',
    reason: 'Proveedor no respondió al reclamo.',
  );

  return [
    PurchaseReceiptResolutionCase(
      id: 'case-open',
      number: 'CR-00001',
      purchaseInvoiceId: 'invoice-1',
      purchaseReceiptId: 'receipt-1',
      purchaseReceiptNumber: 'REC-00042',
      purchaseReceiptLineId: 'line-1',
      sourceLineIndex: 0,
      sourceLineKey: 'source-1',
      productId: 'product-1',
      productName: 'Cámara Ride 26',
      productSku: '10371',
      purchaseTreatment: 'inventory',
      kind: PurchaseReceiptDiscrepancyKind.shortage,
      reportedQuantity: 2,
      resolvedQuantity: 1,
      openQuantity: 1,
      effectiveStatus: 'partially_resolved',
      discrepancyReason: 'Una unidad sigue pendiente.',
      createdAt: DateTime.utc(2026, 7, 24),
      allocations: const [],
    ),
    PurchaseReceiptResolutionCase(
      id: 'case-resolved',
      number: 'CR-00002',
      purchaseInvoiceId: 'invoice-1',
      purchaseReceiptId: 'receipt-1',
      purchaseReceiptNumber: 'REC-00042',
      purchaseReceiptLineId: 'line-1',
      sourceLineIndex: 0,
      sourceLineKey: 'source-2',
      productId: 'product-1',
      productName: 'Cámara Ride 26',
      productSku: '10371',
      purchaseTreatment: 'inventory',
      kind: PurchaseReceiptDiscrepancyKind.damaged,
      reportedQuantity: 1,
      resolvedQuantity: 1,
      openQuantity: 0,
      effectiveStatus: 'resolved',
      createdAt: DateTime.utc(2026, 7, 24),
      allocations: [creditAllocation, laterReceiptAllocation],
    ),
    PurchaseReceiptResolutionCase(
      id: 'case-loss',
      number: 'CR-00003',
      purchaseInvoiceId: 'invoice-1',
      purchaseReceiptId: 'receipt-1',
      purchaseReceiptNumber: 'REC-00042',
      purchaseReceiptLineId: 'line-1',
      sourceLineIndex: 0,
      sourceLineKey: 'source-3',
      productId: 'product-1',
      productName: 'Cámara Ride 26',
      productSku: '10371',
      purchaseTreatment: 'inventory',
      kind: PurchaseReceiptDiscrepancyKind.rejected,
      reportedQuantity: 1,
      resolvedQuantity: 1,
      openQuantity: 0,
      effectiveStatus: 'resolved',
      createdAt: DateTime.utc(2026, 7, 24),
      allocations: [lossAllocation],
    ),
  ];
}
