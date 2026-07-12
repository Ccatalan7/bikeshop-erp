import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/widgets/credit_balance_refund_dialog.dart';

void main() {
  testWidgets('refund dialog requires bounded CLP and audit evidence',
      (tester) async {
    CreditBalanceRefundInput? submitted;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () async {
              submitted = await showCreditBalanceRefundDialog(
                context: context,
                title: 'Registrar reembolso',
                counterpartyLabel: 'devuelto al cliente',
                availableAmount: 2500,
                paymentMethods: const [
                  CreditRefundMethodOption(
                    id: 'bank',
                    name: 'Transferencia',
                    requiresReference: true,
                  ),
                ],
              );
            },
            child: const Text('Abrir'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(find.textContaining('no ejecuta la transferencia bancaria'),
        findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Monto CLP *'), '2501');
    await tester.tap(find.text('Registrar movimiento'));
    await tester.pump();
    expect(find.text('Supera el saldo disponible.'), findsOneWidget);
    expect(submitted, isNull);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Monto CLP *'), '2500');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Comprobante / referencia *'),
        'BANK-OUT-99');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Motivo *'), 'Pago verificado');
    await tester.tap(find.text('Registrar movimiento'));
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
    expect(submitted!.amount, 2500);
    expect(submitted!.paymentMethodId, 'bank');
    expect(submitted!.reference, 'BANK-OUT-99');
  });
}
