import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_invoice.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_receipt.dart';
import 'package:vinabike_erp/modules/purchases/pages/purchase_receiving_page.dart';

void main() {
  Finder reasonDropdown(int lineIndex) => find.descendant(
        of: find.byKey(ValueKey('reason-$lineIndex')),
        matching: find.byWidgetPredicate(
          (widget) => widget is DropdownButtonFormField,
          description: 'reason dropdown for receipt line $lineIndex',
        ),
      );

  PurchaseInvoice invoice() => PurchaseInvoice(
        id: 'invoice-51611',
        tenantId: 'tenant-1',
        invoiceNumber: '51611',
        supplierId: 'supplier-1',
        supplierName: 'Comercial Ciclo',
        date: DateTime(2026, 7, 22),
        status: PurchaseInvoiceStatus.paid,
        total: 59958,
        paidAmount: 59958,
        balance: 0,
        prepaymentModel: true,
        items: [
          PurchaseInvoiceItem(
            productId: 'product-1',
            productName: 'Cámara Ride 26x1,95/2,125 VA 35mm',
            productSku: '10371',
            quantity: 10,
            unitCost: 2090,
          ),
          PurchaseInvoiceItem(
            productId: 'product-2',
            productName: 'Cadena KMC X9 9 Vel',
            productSku: '19007',
            unitCost: 13990,
          ),
        ],
      );

  Future<void> pumpWorkspace(
    WidgetTester tester, {
    required Future<Map<int, int>> Function(String invoiceId) previousLoader,
    Future<Map<int, int>> Function(String invoiceId)? resolutionLoader,
    Future<Map<String, String>> Function(Iterable<String> productIds)?
        productImageLoader,
    Future<PurchaseReceiptResult> Function({
      required String invoiceId,
      required List<PurchaseReceiptLineDraft> lines,
      required DateTime receivedAt,
      required String idempotencyKey,
      String? deliveryReference,
      String? locationLabel,
      String? notes,
    })? receiptCreator,
    Future<void> Function(PurchaseReceiptResult result)? onCompleted,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PurchaseReceivingWorkspace(
            invoice: invoice(),
            onCancel: () {},
            onCompleted: onCompleted ?? (_) async {},
            previousLoader: previousLoader,
            resolutionLoader: resolutionLoader,
            productImageLoader:
                productImageLoader ?? (_) async => const <String, String>{},
            receiptCreator: receiptCreator,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('is an inline dense table without top-level route chrome',
      (tester) async {
    await pumpWorkspace(
      tester,
      previousLoader: (_) async => const {0: 10, 1: 1},
    );

    final workspace = find.byType(PurchaseReceivingWorkspace);
    expect(
      find.descendant(of: workspace, matching: find.byType(Scaffold)),
      findsNothing,
    );
    expect(
      find.descendant(of: workspace, matching: find.byType(AppBar)),
      findsNothing,
    );
    expect(find.text('Detalle de recepción'), findsOneWidget);
    expect(find.text('PRODUCTO'), findsOneWidget);
    expect(find.text('PEDIDO'), findsOneWidget);
    expect(find.text('RECIBIDO AHORA'), findsOneWidget);
    expect(find.text('DIFERENCIA'), findsOneWidget);
    expect(find.text('MOTIVO / EVIDENCIA'), findsOneWidget);
    expect(find.text('RECIBIDO'), findsNothing);
    expect(find.text('RESUELTO'), findsNothing);
    expect(find.text('DAÑADO'), findsNothing);
    expect(find.text('RECHAZADO'), findsNothing);
    expect(find.text('FALTANTE'), findsNothing);
    expect(find.text('PENDIENTE'), findsNothing);
    expect(find.textContaining('Recibido antes:'), findsNWidgets(2));
    expect(
      find.text('Todas las líneas ya tienen recepción completa.'),
      findsOneWidget,
    );
    expect(find.text('Registrar recepción'), findsNothing);
    expect(find.text('Volver a factura'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.text('Recepción de productos')))
          .colorScheme
          .primary,
      const Color(0xFF235466),
    );
  });

  testWidgets('renders product thumbnails supplied by the canonical loader',
      (tester) async {
    await pumpWorkspace(
      tester,
      previousLoader: (_) async => const {},
      productImageLoader: (ids) async => {
        'product-1': 'asset:assets/images/chain_icon.png',
      },
    );

    final firstThumbnail = find.byKey(const ValueKey('product-thumbnail-0'));
    final secondThumbnail = find.byKey(const ValueKey('product-thumbnail-1'));
    expect(firstThumbnail, findsOneWidget);
    expect(secondThumbnail, findsOneWidget);
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
  });

  testWidgets('maps the calculated difference to the selected shortage reason',
      (tester) async {
    List<PurchaseReceiptLineDraft>? submitted;
    PurchaseReceiptResult? completed;

    await pumpWorkspace(
      tester,
      previousLoader: (_) async => const {},
      receiptCreator: ({
        required invoiceId,
        required lines,
        required receivedAt,
        required idempotencyKey,
        deliveryReference,
        locationLabel,
        notes,
      }) async {
        submitted = lines;
        return const PurchaseReceiptResult(
          receiptId: 'receipt-1',
          operationId: 'operation-1',
          receiptNumber: 'REC-00001',
          replayed: false,
        );
      },
      onCompleted: (result) async => completed = result,
    );

    await tester.enterText(find.byKey(const ValueKey('accepted-0')), '7');
    await tester.pump();
    final difference = find.byKey(const ValueKey('difference-0'));
    expect(
      find.descendant(of: difference, matching: find.text('3')),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Registrar recepción'));
    await tester.pump();
    expect(find.text('Selecciona el motivo.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);

    final shortageReasonField = reasonDropdown(0);
    await tester.ensureVisible(shortageReasonField);
    await tester.tap(shortageReasonField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Faltante / no llegó').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('evidence-field-0')),
      'Caja abierta; proveedor avisado',
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Registrar recepción'));
    await tester.pumpAndSettle();
    expect(find.text('Registrar recepción'), findsWidgets);
    expect(
      find.textContaining('no genera notas de crédito'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Registrar').last);
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
    expect(submitted!.first.acceptedQuantity, 7);
    expect(submitted!.first.shortageQuantity, 3);
    expect(
      submitted!.first.discrepancyReason,
      'Faltante / no llegó · Caja abierta; proveedor avisado',
    );
    expect(completed?.receiptNumber, 'REC-00001');
  });

  for (final scenario in const [
    (
      label: 'Dañado',
      damaged: 3,
      rejected: 0,
    ),
    (
      label: 'Rechazado / no conforme',
      damaged: 0,
      rejected: 3,
    ),
  ]) {
    testWidgets(
      'maps the full calculated difference to ${scenario.label}',
      (tester) async {
        List<PurchaseReceiptLineDraft>? submitted;
        await pumpWorkspace(
          tester,
          previousLoader: (_) async => const {},
          receiptCreator: ({
            required invoiceId,
            required lines,
            required receivedAt,
            required idempotencyKey,
            deliveryReference,
            locationLabel,
            notes,
          }) async {
            submitted = lines;
            return const PurchaseReceiptResult(
              receiptId: 'receipt-1',
              operationId: 'operation-1',
              receiptNumber: 'REC-00001',
              replayed: false,
            );
          },
        );

        await tester.enterText(find.byKey(const ValueKey('accepted-0')), '7');
        await tester.pump();
        final reasonField = reasonDropdown(0);
        await tester.ensureVisible(reasonField);
        await tester.tap(reasonField);
        await tester.pumpAndSettle();
        await tester.tap(find.text(scenario.label).last);
        await tester.pumpAndSettle();
        await tester
            .tap(find.widgetWithText(FilledButton, 'Registrar recepción'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Registrar').last);
        await tester.pumpAndSettle();

        expect(submitted, isNotNull);
        expect(submitted!.first.acceptedQuantity, 7);
        expect(submitted!.first.damagedQuantity, scenario.damaged);
        expect(submitted!.first.rejectedQuantity, scenario.rejected);
        expect(submitted!.first.shortageQuantity, 0);
        expect(submitted!.first.discrepancyReason, scenario.label);
      },
    );
  }

  testWidgets('caps a later receipt after a partial financial resolution',
      (tester) async {
    List<PurchaseReceiptLineDraft>? submitted;
    await pumpWorkspace(
      tester,
      previousLoader: (_) async => const {0: 7, 1: 1},
      resolutionLoader: (_) async => const {0: 2},
      receiptCreator: ({
        required invoiceId,
        required lines,
        required receivedAt,
        required idempotencyKey,
        deliveryReference,
        locationLabel,
        notes,
      }) async {
        submitted = lines;
        return const PurchaseReceiptResult(
          receiptId: 'receipt-later',
          operationId: 'operation-later',
          receiptNumber: 'REC-00002',
          replayed: false,
        );
      },
    );

    expect(find.text('RESUELTO'), findsNothing);
    expect(
      find.text('Recibido antes: 7 · Resuelto: 2 · Saldo previo: 1'),
      findsOneWidget,
    );
    final accepted =
        tester.widget<TextFormField>(find.byKey(const ValueKey('accepted-0')));
    expect(accepted.initialValue, '1');

    await tester.tap(find.widgetWithText(FilledButton, 'Registrar recepción'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Registrar').last);
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
    expect(submitted!.single.acceptedQuantity, 1);
    expect(submitted!.single.previouslyReceivedQuantity, 7);
    expect(submitted!.single.previouslyResolvedQuantity, 2);
  });
}
