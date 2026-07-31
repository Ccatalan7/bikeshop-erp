import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/stock_adjustment.dart';
import 'package:vinabike_erp/modules/inventory/models/stock_movement.dart';
import 'package:vinabike_erp/modules/inventory/widgets/movement_inspector.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_invoice.dart';
import 'package:vinabike_erp/modules/sales/models/sales_models.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';

/// Paints the inspector for real in each of its states.
///
/// Same discipline as the ledger's render test: the failures that took this
/// module down today were runtime assertions the analyzer cannot see, so the
/// gate is a painted frame, not a compiled file.
void main() {
  final movement = _movement();

  Widget host(Widget child) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: SizedBox(width: 380, height: 800, child: child)),
    );
  }

  testWidgets('inspector paints movement, evidence and document sections',
      (tester) async {
    final invoice = Invoice(
      id: 'inv-1',
      tenantId: 't',
      invoiceNumber: 'FV-00843',
      customerName: 'Gabriel Sanabria',
      date: DateTime(2026, 7, 9),
      status: InvoiceStatus.paid,
      subtotal: 31092,
      ivaAmount: 5908,
      total: 37000,
      items: [
        InvoiceItem(
          productId: 'p-1',
          productName: 'Cadena KMC Hv408',
          quantity: 1,
          unitPrice: 8000,
          lineTotal: 8000,
        ),
      ],
    );

    await tester.pumpWidget(host(MovementInspector(
      movement: movement,
      salesInvoice: invoice,
      onClose: () {},
      onOpenDocument: () {},
    )));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The three questions, in order: what happened, can I trust it, and what
    // justifies it.
    expect(find.text('MOVIMIENTO'), findsOneWidget);
    expect(find.text('EVIDENCIA'), findsOneWidget);
    expect(find.text('DOCUMENTO'), findsOneWidget);
    // The transition and the one line that touched this product.
    expect(find.textContaining('7'), findsWidgets);
    expect(find.text('Factura FV-00843'), findsOneWidget);
    expect(find.text('Pagada'), findsOneWidget);
    expect(find.text('Gabriel Sanabria'), findsOneWidget);
    expect(find.textContaining('8.000'), findsWidgets);
    expect(find.text('Abrir factura'), findsOneWidget);
  });

  testWidgets('a movement with no document says so instead of hiding it',
      (tester) async {
    await tester.pumpWidget(host(MovementInspector(
      movement: movement,
      onClose: () {},
    )));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.text('Este movimiento no tiene un documento asociado.'),
      findsOneWidget,
    );
    expect(find.text('Abrir factura'), findsNothing);
  });

  testWidgets('typed source stays owned by its module', (tester) async {
    final sourceMovement = movement.copyWith(
      sourceDocumentType: 'sales_return',
      sourceDocumentId: 'return-1',
    );

    await tester.pumpWidget(host(MovementInspector(
      movement: sourceMovement,
      onClose: () {},
    )));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('devolución de venta'),
      findsOneWidget,
    );
    expect(
      find.text('Este movimiento no tiene un documento asociado.'),
      findsNothing,
    );
  });

  testWidgets('a directly routed source still opens through the inspector',
      (tester) async {
    var opened = false;
    final sourceMovement = movement.copyWith(
      sourceDocumentType: 'mechanic_job',
      sourceDocumentId: 'job-1',
    );

    await tester.pumpWidget(host(MovementInspector(
      movement: sourceMovement,
      onOpenDocument: () => opened = true,
      onClose: () {},
    )));
    await tester.pumpAndSettle();

    expect(find.text('EVIDENCIA'), findsOneWidget);
    expect(find.text('Abrir trabajo de taller'), findsOneWidget);
    await tester.ensureVisible(find.text('Abrir trabajo de taller'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abrir trabajo de taller'));
    expect(opened, isTrue);
  });

  testWidgets('movement instants use the store timezone', (tester) async {
    final timezoneMovement = movement.copyWith(
      createdAt: DateTime.utc(2026, 7, 28, 2, 30),
      transactionDate: DateTime.utc(2026, 7, 28, 1, 30),
    );

    await tester.pumpWidget(host(MovementInspector(
      movement: timezoneMovement,
      storeTimezone: 'America/Santiago',
      onClose: () {},
    )));
    await tester.pumpAndSettle();

    expect(find.text('27/07/2026 22:30'), findsOneWidget);
    expect(find.text('27/07/2026 21:30'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed document load keeps the movement and offers retry',
      (tester) async {
    var retried = false;
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(MovementInspector(
      movement: movement,
      documentError: 'timeout',
      onRetryDocument: () => retried = true,
      onClose: () {},
    )));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The movement and its evidence never depend on the document loading.
    expect(find.text('MOVIMIENTO'), findsOneWidget);
    expect(find.text('EVIDENCIA'), findsOneWidget);
    await tester.ensureVisible(find.text('Reintentar'));
    await tester.tap(find.text('Reintentar'));
    expect(retried, isTrue);
  });

  testWidgets('the evidence disclosure reveals the technical detail',
      (tester) async {
    await tester.pumpWidget(host(MovementInspector(
      movement: movement,
      onClose: () {},
    )));
    await tester.pumpAndSettle();

    // Closed by default: the sentence carries the verdict, the fields wait.
    expect(find.text('Reconstruido desde el stock actual'), findsNothing);
    await tester.tap(find.text('Detalle técnico'));
    await tester.pumpAndSettle();
    expect(find.text('Reconstruido desde el stock actual'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('verified describes arithmetic without claiming document proof',
      (tester) async {
    final verified = movement.copyWith(
      integrityStatus: 'verified',
      balanceProvenance: 'persisted_movement',
      evidenceBalanceProvenance: 'reconstructed',
    );

    await tester.pumpWidget(host(MovementInspector(
      movement: verified,
      onClose: () {},
    )));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('La aritmética de los saldos registrados'),
      findsOneWidget,
    );
    expect(find.textContaining('documento coinciden'), findsNothing);
    await tester.tap(find.text('Detalle técnico'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Saldo de origen no registrado'), findsOneWidget);
  });

  testWidgets('operation trace exposes command, transition, actor and reason',
      (tester) async {
    final traced = movement.copyWith(
      operationId: 'stock-operation',
      triggerAction: 'void',
    );
    await tester.pumpWidget(host(MovementInspector(
      movement: traced,
      operationTrace: const {
        'operation_id': 'stock-operation',
        'action': 'update',
        'old_status': 'confirmed',
        'new_status': 'cancelled',
        'actor_id': 'stock-actor',
        'parent_operation_id': 'void-command',
        'parent_action': 'void',
        'parent_actor_id': 'command-actor',
        'parent_source_channel': 'invoice_detail',
        'parent_context': {'reason': 'La venta no ocurrió'},
        'parent_outcome': 'completed',
      },
      onClose: () {},
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Detalle técnico'));
    await tester.pumpAndSettle();

    expect(find.text('Descartar factura'), findsOneWidget);
    expect(find.text('confirmed → cancelled'), findsOneWidget);
    expect(find.text('La venta no ocurrió'), findsOneWidget);
    expect(find.text('command-actor'), findsOneWidget);
    expect(find.text('void-command'), findsOneWidget);
    expect(find.text('stock-operation'), findsOneWidget);
  });

  testWidgets('operation trace failure is explicit and retryable',
      (tester) async {
    var retried = false;
    final traced = movement.copyWith(operationId: 'stock-operation');
    await tester.pumpWidget(host(MovementInspector(
      movement: traced,
      operationTraceError: 'No se pudo cargar la traza de la operación.',
      onRetryOperationTrace: () => retried = true,
      onClose: () {},
    )));
    await tester.pumpAndSettle();

    expect(
      find.text('No se pudo cargar la traza de la operación.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Reintentar traza'));
    expect(retried, isTrue);
  });

  testWidgets('operation trace loading is visible before disclosure',
      (tester) async {
    final traced = movement.copyWith(operationId: 'stock-operation');
    await tester.pumpWidget(host(MovementInspector(
      movement: traced,
      loadingOperationTrace: true,
      onClose: () {},
    )));
    await tester.pump();

    expect(find.text('Cargando traza de la operación…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adjustment preserves its posted accounting evidence',
      (tester) async {
    final adjustment = StockAdjustmentDetail(
      id: 'adjustment-1',
      operationId: 'operation-1',
      productId: 'p-1',
      productName: 'Cadena KMC Hv408',
      adjustmentType: 'loss',
      referenceNumber: 'AJ-0007',
      quantity: -2,
      stockBefore: 7,
      stockAfter: 5,
      reason: 'Merma: unidad dañada',
      adjustmentOrigin: 'product_form',
      adjustmentDate: DateTime(2026, 7, 27, 10),
      createdAt: DateTime(2026, 7, 27, 10),
      createdByEmail: 'auditoria@vinabike.cl',
      unitCost: 5000,
      inventoryValue: 10000,
      journalEntryId: 'journal-1',
      journalEntryNumber: 'JE-0007',
      journalEntryDescription: 'Merma AJ-0007',
      counterpartAccountCode: '6195',
      counterpartAccountName: 'Mermas de Inventario',
      counterpartDebit: 10000,
      counterpartCredit: 0,
    );

    await tester.pumpWidget(host(MovementInspector(
      movement: movement,
      adjustment: adjustment,
      onClose: () {},
    )));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('JE-0007'));

    expect(find.text('Impacto contable'), findsOneWidget);
    expect(find.text('JE-0007'), findsOneWidget);
    expect(find.text('6195 · Mermas de Inventario'), findsOneWidget);
    expect(find.text('Débito contraparte'), findsOneWidget);
    expect(find.textContaining('10.000'), findsWidgets);
  });

  testWidgets('purchase keeps payment and physical receipt as separate axes',
      (tester) async {
    final purchase = PurchaseInvoice(
      id: 'purchase-1',
      tenantId: 't',
      invoiceNumber: 'FC-0042',
      supplierId: 'supplier-1',
      supplierName: 'Proveedor Uno',
      date: DateTime(2026, 7, 27),
      status: PurchaseInvoiceStatus.paid,
      total: 20000,
      paidAmount: 20000,
      balance: 0,
      items: [
        PurchaseInvoiceItem(
          productId: 'p-1',
          productName: 'Cadena KMC Hv408',
          quantity: 2,
          unitCost: 10000,
        ),
      ],
    );

    await tester.pumpWidget(host(MovementInspector(
      movement: movement,
      purchaseInvoice: purchase,
      onClose: () {},
    )));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.textContaining('Estado físico no incluido'));

    expect(find.text('Financiero'), findsOneWidget);
    expect(find.textContaining('Pagada'), findsOneWidget);
    expect(find.text('Recepción física'), findsOneWidget);
    expect(find.textContaining('Estado físico no incluido'), findsOneWidget);
    expect(find.textContaining('Recibida ·'), findsNothing);
  });
}

StockMovement _movement() {
  return StockMovement(
    id: 'm-1',
    productId: 'p-1',
    productName: 'Cadena KMC Hv408',
    productSku: '4715575883212',
    transactionDate: DateTime(2026, 7, 9, 18, 32),
    movementType: 'sale',
    source: 'Taller',
    referenceId: 'FV-00843',
    referenceNumber: 'FV-00843',
    stockBefore: 7,
    quantity: -1,
    stockAfter: 6,
    rawQuantity: -1,
    actualStockDelta: -1,
    reconciledQuantity: -1,
    balanceProvenance: 'reconstructed_chain',
    integrityStatus: 'legacy_reconstructed',
    isSummaryExcluded: false,
    evidenceStockBefore: 7,
    evidenceStockAfter: 6,
    evidenceBalanceProvenance: 'reconstructed',
    evidenceIntegrityStatus: 'legacy_reconstructed',
    createdAt: DateTime(2026, 7, 9, 22, 37),
  );
}
