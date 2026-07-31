import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/hr/models/payroll_voucher.dart';
import 'package:vinabike_erp/modules/hr/payroll/payroll_redesign_page.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
    'la tarjeta móvil expone un disclosure accesible sin overflow a 390 px',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const line = PayrollVoucherLine(
        id: 'line-disclosure',
        voucherId: 'voucher-disclosure',
        employeeId: 'employee-disclosure',
        employeeName: 'Alejandra del Carmen Soto',
        workedHours: 37.5,
        hourlyRate: 4000,
        totalAmount: 150000,
        paymentMethodId: 'method-transfer',
        settledAmount: 25000,
        balance: 125000,
      );
      final voucher = PayrollVoucher(
        id: 'voucher-disclosure',
        tenantId: 'tenant-test',
        voucherNumber: 'NOM-TEST',
        periodStart: DateTime(2026, 7, 6),
        periodEnd: DateTime(2026, 7, 12),
        totalHours: line.totalHours,
        totalAmount: line.totalAmount,
        employeeCount: 1,
        status: PayrollVoucherStatus.confirmed,
        createdAt: DateTime(2026, 7, 12),
        updatedAt: DateTime(2026, 7, 12),
        reconciliationVersion: 1,
        lines: [line],
      );
      final actions = PayrollRedesignActions(
        load: () async => PayrollRedesignData(
          vouchers: [voucher],
          paymentMethods: const [
            {
              'id': 'method-transfer',
              'name': 'Transferencia',
              'code': 'transfer',
              'account_id': 'account-transfer',
              'is_active': true,
            },
          ],
        ),
        hydrateHistoryVoucher: (voucher) async => voucher,
        commitWeek: (_) async {},
        payLine: ({
          required voucherId,
          required lineId,
          required splits,
          required operationKey,
          required expectedReconciliationVersion,
        }) async {},
        registerAdvance: ({
          required employeeId,
          required amount,
          required paymentMethodId,
          required paymentAccountId,
          required paidAt,
          reference,
          notes,
          required operationKey,
        }) async {},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PayrollRedesignPage(actions: actions),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final disclosure = find.byKey(
        const ValueKey<String>(
          'payroll-mobile-person-disclosure-Alejandra del Carmen Soto',
        ),
      );
      expect(disclosure, findsOneWidget);
      expect(
        tester.getSize(disclosure).height,
        greaterThanOrEqualTo(48),
      );
      // 5l pone el disclosure como su propio control bajo la fila, para que
      // la cifra y la acción no compitan con él por el ancho táctil.
      final toggle = find.byKey(
        const ValueKey<String>(
          'payroll-mobile-person-detail-toggle-Alejandra del Carmen Soto',
        ),
      );
      expect(find.text('Ver detalle'), findsOneWidget);
      expect(
        find.descendant(of: toggle, matching: find.byIcon(Icons.expand_more)),
        findsOneWidget,
      );
      // Las horas viajan con el nombre en la tarjeta plegada (5l): son la base
      // del monto. Lo que se guarda para el detalle es la tarifa y los pagos.
      expect(find.textContaining('37,5 h'), findsWidgets);
      expect(find.textContaining(r'\$4.000 / h'), findsNothing);
      expect(find.text('Pago registrado \$25.000'), findsNothing);

      var semantics = tester.widget<Semantics>(toggle);
      expect(semantics.properties.button, isTrue);
      expect(semantics.properties.expanded, isFalse);
      expect(
        semantics.properties.label,
        'Ver detalle de nómina de Alejandra del Carmen Soto',
      );

      await tester.tap(disclosure);
      await tester.pump();

      expect(find.text('Ocultar detalle'), findsOneWidget);
      expect(
        find.descendant(of: toggle, matching: find.byIcon(Icons.expand_less)),
        findsOneWidget,
      );
      // Ahora aparece dos veces: en la glosa de la tarjeta y en el detalle.
      expect(find.textContaining('37,5 h'), findsWidgets);
      expect(find.textContaining(r'$4.000 / h'), findsOneWidget);
      expect(find.text('Pago registrado \$25.000'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey<String>(
            'payroll-mobile-person-detail-Alejandra del Carmen Soto',
          ),
        ),
        findsOneWidget,
      );
      semantics = tester.widget<Semantics>(toggle);
      expect(semantics.properties.expanded, isTrue);
      expect(
        semantics.properties.label,
        'Ocultar detalle de nómina de Alejandra del Carmen Soto',
      );
      expect(tester.takeException(), isNull);

      await tester.tap(disclosure);
      await tester.pump();
      expect(find.textContaining(r'\$4.000 / h'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
