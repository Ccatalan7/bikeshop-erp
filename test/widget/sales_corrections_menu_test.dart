import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/sales/models/sales_models.dart';
import 'package:vinabike_erp/modules/sales/widgets/sales_corrections_menu.dart';

void main() {
  Invoice invoice(InvoiceStatus status, {String source = 'manual_sale'}) =>
      Invoice(
        id: 'invoice-1',
        tenantId: 'tenant-1',
        invoiceNumber: 'FV-00878',
        date: DateTime(2026, 7, 12),
        status: status,
        source: source,
      );

  testWidgets('shows both correction workflows on a paid invoice',
      (tester) async {
    var openedReturn = false;
    var refreshed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SalesCorrectionsMenu(
            invoice: invoice(InvoiceStatus.paid),
            returnCapabilityLoader: () async => true,
            creditNoteCapabilityLoader: () async => true,
            returnPageOpener: (context, invoice) async {
              openedReturn = true;
            },
            onChanged: () async {
              refreshed = true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Correcciones'), findsOneWidget);
    await tester.tap(find.text('Correcciones'));
    await tester.pumpAndSettle();
    expect(find.text('Devolución física'), findsOneWidget);
    expect(find.text('Nota de crédito'), findsOneWidget);

    await tester.tap(find.text('Devolución física'));
    await tester.pumpAndSettle();
    expect(openedReturn, isTrue);
    expect(refreshed, isTrue);
  });

  testWidgets('confirmed invoice offers financial correction but no return',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SalesCorrectionsMenu(
            invoice: invoice(InvoiceStatus.confirmed),
            returnCapabilityLoader: () async => true,
            creditNoteCapabilityLoader: () async => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Correcciones'));
    await tester.pumpAndSettle();
    expect(find.text('Devolución física'), findsNothing);
    expect(find.text('Nota de crédito'), findsOneWidget);
    expect(find.text('Descartar factura'), findsOneWidget);
  });

  testWidgets('does not offer corrections for a draft invoice', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SalesCorrectionsMenu(
            invoice: invoice(InvoiceStatus.draft),
            returnCapabilityLoader: () async => true,
            creditNoteCapabilityLoader: () async => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Correcciones'), findsNothing);
  });

  testWidgets('sent standalone invoice offers discard but no posted correction',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SalesCorrectionsMenu(
            invoice: invoice(InvoiceStatus.sent),
            returnCapabilityLoader: () async => true,
            creditNoteCapabilityLoader: () async => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Correcciones'), findsOneWidget);
    await tester.tap(find.text('Correcciones'));
    await tester.pumpAndSettle();
    expect(find.text('Descartar factura'), findsOneWidget);
    expect(find.text('Nota de crédito'), findsNothing);
    expect(find.text('Devolución física'), findsNothing);
  });

  testWidgets('discard requires a reason and refreshes after success',
      (tester) async {
    String? discardedInvoiceId;
    String? discardReason;
    var refreshed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SalesCorrectionsMenu(
            invoice: invoice(InvoiceStatus.confirmed),
            returnCapabilityLoader: () async => false,
            creditNoteCapabilityLoader: () async => false,
            voidExecutor: ({
              required invoiceId,
              required reason,
              required idempotencyKey,
            }) async {
              discardedInvoiceId = invoiceId;
              discardReason = reason;
              expect(idempotencyKey, isNotEmpty);
            },
            onChanged: () async => refreshed = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Correcciones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descartar factura'));
    await tester.pumpAndSettle();
    expect(find.text('Descartar factura FV-00878'), findsOneWidget);

    await tester.tap(find.text('Descartar y revertir'));
    await tester.pump();
    expect(find.text('Indica el motivo del descarte.'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'Factura de prueba; la venta no ocurrió',
    );
    await tester.tap(find.text('Descartar y revertir'));
    await tester.pumpAndSettle();

    expect(discardedInvoiceId, 'invoice-1');
    expect(discardReason, 'Factura de prueba; la venta no ocurrió');
    expect(refreshed, isTrue);
  });
}
