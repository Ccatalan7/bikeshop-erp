import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_receipt.dart';
import 'package:vinabike_erp/modules/purchases/widgets/purchase_receipt_records_dropdown.dart';

void main() {
  testWidgets('matches payment evidence styling and starts collapsed',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    PurchaseReceiptRecord? opened;
    final receipt = PurchaseReceiptRecord(
      id: 'receipt-1',
      number: 'REC-00042',
      status: 'posted',
      receivedAt: DateTime(2026, 7, 23),
      acceptedQuantity: 7,
      discrepancyQuantity: 3,
      deliveryReference: 'GD-100',
      locationLabel: 'Bodega principal',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            child: PurchaseReceiptRecordsDropdown(
              receipts: [receipt],
              onReceiptTap: (value) => opened = value,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Recepciones de stock'), findsOneWidget);
    expect(find.text('REC-00042'), findsNothing);

    final count = tester.widget<Text>(find.text('1'));
    expect(count.style?.color, const Color(0xFF2563EB));

    await tester.tap(find.text('Recepciones de stock'));
    await tester.pumpAndSettle();

    expect(find.text('REC-00042'), findsOneWidget);
    expect(find.text('GD-100'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    final link = tester.widget<Text>(find.text('REC-00042'));
    expect(link.style?.color, const Color(0xFF2563EB));
    expect(link.style?.decoration, TextDecoration.underline);

    final status = tester.widget<Text>(find.text('Registrada'));
    expect(status.style?.color, const Color(0xFF16A34A));

    final blockWidth = tester
        .getSize(
          find.byKey(
            const ValueKey('purchase-receipt-records-dropdown'),
          ),
        )
        .width;
    final tableWidth = tester
        .getSize(
          find.byKey(
            const ValueKey('purchase-receipt-records-header'),
          ),
        )
        .width;
    expect(tableWidth, closeTo(blockWidth - 30, 1));

    await tester.tap(find.text('REC-00042'));
    expect(opened?.id, 'receipt-1');
  });

  testWidgets('keeps the evidence table scrollable on narrow panes',
      (tester) async {
    final receipt = PurchaseReceiptRecord(
      id: 'receipt-voided',
      number: 'REC-00043',
      status: 'voided',
      receivedAt: DateTime(2026, 7, 24),
      acceptedQuantity: 0,
      discrepancyQuantity: 4,
      locationLabel: 'Bodega principal',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 340,
            child: PurchaseReceiptRecordsDropdown(receipts: [receipt]),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Recepciones de stock'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey('purchase-receipt-records-header'),
            ),
          )
          .width,
      900,
    );

    final status = tester.widget<Text>(find.text('Anulada'));
    expect(status.style?.color, const Color(0xFFDC2626));
  });
}
