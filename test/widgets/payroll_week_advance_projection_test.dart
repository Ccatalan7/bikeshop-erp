import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/hr/models/payroll_voucher.dart';
import 'package:vinabike_erp/modules/hr/payroll/payroll_redesign_page.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_queue_surface.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// El caso del dueño, 2026-11-08: registró un anticipo de $20.000 para
/// Braulio el viernes de la S45, una hora después de crear el borrador, y la
/// semana lo ignoraba: `ANTICIPOS —`, `A PAGAR $77.700`, pie con
/// `anticipos $0` y `$265.900` por pagar. Pagar esa cifra desde el banco le
/// pagaba el anticipo dos veces.
///
/// Los montos y las fechas son los de producción; los nombres son los de las
/// fichas de trabajadores del taller, que ya viven en otras pruebas de
/// Nóminas.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  PayrollVoucherLine line(
    String id,
    String name, {
    required double hours,
    required double total,
    required String methodId,
  }) =>
      PayrollVoucherLine(
        id: id,
        voucherId: 'voucher-s45',
        employeeId: 'employee-$id',
        employeeName: name,
        workedHours: hours,
        hourlyRate: total / hours,
        totalAmount: total,
        paymentMethodId: methodId,
        balance: total,
      );

  final s45 = PayrollVoucher(
    id: 'voucher-s45',
    tenantId: 'tenant-test',
    voucherNumber: 'NOM-S45',
    periodStart: DateTime(2026, 11, 2),
    periodEnd: DateTime(2026, 11, 8),
    totalHours: 67.7,
    totalAmount: 265900,
    employeeCount: 3,
    createdAt: DateTime(2026, 11, 8, 23, 53),
    updatedAt: DateTime(2026, 11, 8, 23, 53),
    reconciliationVersion: 7,
    lines: [
      line('braulio', 'Braulio Muñoz',
          hours: 22.2, total: 77700, methodId: 'method-transfer'),
      line('rodrigo', 'Rodrigo Guillermo Nieto',
          hours: 14.5, total: 58000, methodId: 'method-cash'),
      line('vicente', 'Vicente Díaz',
          hours: 31, total: 130200, methodId: 'method-transfer'),
    ],
  );

  final braulioAdvance = EmployeeAdvance(
    id: 'advance-braulio',
    employeeId: 'employee-braulio',
    amount: 20000,
    amountApplied: 0,
    paidAt: DateTime.utc(2026, 11, 7, 3),
    paidCivilDate: DateTime(2026, 11, 7),
    status: 'open',
    reasonExplanation: 'Acuerdo con Braulio',
  );

  PayrollRedesignActions actionsFor(PayrollRedesignData data) =>
      PayrollRedesignActions(
        load: () async => data,
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
          required employeeName,
          required amount,
          required paymentMethodId,
          required paymentAccountId,
          required paidAt,
          reference,
          notes,
          required reasonCode,
          required reasonExplanation,
          workEndedOn,
          originalReceipt,
          required operationKey,
        }) async {},
      );

  const paymentMethods = <Map<String, dynamic>>[
    {
      'id': 'method-transfer',
      'name': 'Transferencia',
      'code': 'transfer',
      'account_id': 'account-bank',
      'is_active': true,
    },
    {
      'id': 'method-cash',
      'name': 'Efectivo',
      'code': 'cash',
      'account_id': 'account-cash',
      'is_active': true,
    },
  ];

  Future<void> pumpPage(
    WidgetTester tester, {
    required Size size,
    required List<EmployeeAdvance> advances,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.all.first,
          brightness: Brightness.light,
        ),
        home: Scaffold(
          body: PayrollRedesignPage(
            actions: actionsFor(
              PayrollRedesignData(
                vouchers: [s45],
                paymentMethods: paymentMethods,
                openAdvances: advances,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'el anticipo vigente de la semana resta en la fila, la tarjeta y el pie',
      (tester) async {
    await pumpPage(
      tester,
      size: const Size(1440, 900),
      advances: [braulioAdvance],
    );

    // La fila de Braulio: el anticipo en su columna y `A PAGAR` neto.
    expect(find.text('−\$20.000'), findsOneWidget);
    expect(find.text(r'$57.700'), findsOneWidget);
    expect(find.text(r'$77.700'), findsOneWidget, reason: 'TOTAL no cambia');

    // El pie hace la misma resta y dice la plata que de verdad falta mover.
    final moneyBar = find.byKey(const ValueKey<String>('payroll-money-bar'));
    expect(
      find.descendant(
        of: moneyBar,
        matching:
            find.text('total \$265.900 − anticipos \$20.000 − pagado \$0'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: moneyBar, matching: find.text(r'$245.900')),
      findsOneWidget,
    );
    // La tarjeta de la semana, también.
    expect(find.text(r'$245.900'), findsNWidgets(2));
    expect(find.text(r'$265.900'), findsNothing);

    // La fila abierta explica de dónde sale la cifra y cuándo se aplica.
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Mostrar detalle de Braulio Muñoz',
      ),
    );
    await tester.pumpAndSettle();
    final toDiscount = find.byKey(
      const ValueKey<String>(
        'payroll-disclosure-advance-to-discount-Braulio Muñoz',
      ),
    );
    expect(toDiscount, findsOneWidget);
    expect(
      find.descendant(
          of: toDiscount, matching: find.text('Anticipo del 07/11')),
      findsOneWidget,
    );
    expect(find.text(payrollAdvanceToDiscountNote), findsOneWidget);
    // «Aplicados —» junto al anticipo por descontar sería la misma resta dos
    // veces.
    expect(find.text('Anticipos aplicados'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('un anticipo del lunes siguiente no toca la semana cerrada',
      (tester) async {
    await pumpPage(
      tester,
      size: const Size(1440, 900),
      advances: [
        EmployeeAdvance(
          id: 'advance-next-week',
          employeeId: 'employee-braulio',
          amount: 20000,
          amountApplied: 0,
          paidAt: DateTime.utc(2026, 11, 10, 3),
          paidCivilDate: DateTime(2026, 11, 10),
          status: 'open',
        ),
      ],
    );

    expect(find.text('−\$20.000'), findsNothing);
    final moneyBar = find.byKey(const ValueKey<String>('payroll-money-bar'));
    expect(
      find.descendant(
        of: moneyBar,
        matching: find.text('total \$265.900 − anticipos \$0 − pagado \$0'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: moneyBar, matching: find.text(r'$265.900')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  // Visto al verificar el arreglo en la app (2026-11-08): la tarjeta del
  // teléfono rotulaba «Ver respaldo del pago» todo lo que no fuera «Pagar»,
  // también a Braulio, que no tiene método de pago ni ningún pago, y cuyo
  // toque abre «Configurar método».
  testWidgets('en el teléfono, sin método el botón dice Configurar método',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final withoutMethod = PayrollVoucher(
      id: s45.id,
      tenantId: s45.tenantId,
      voucherNumber: s45.voucherNumber,
      periodStart: s45.periodStart,
      periodEnd: s45.periodEnd,
      // Como en producción: la S45 sigue en borrador.
      status: PayrollVoucherStatus.draft,
      createdAt: s45.createdAt,
      updatedAt: s45.updatedAt,
      reconciliationVersion: s45.reconciliationVersion,
      lines: const [
        PayrollVoucherLine(
          id: 'braulio',
          voucherId: 'voucher-s45',
          employeeId: 'employee-braulio',
          employeeName: 'Braulio Muñoz',
          workedHours: 22.2,
          hourlyRate: 3500,
          totalAmount: 77700,
          balance: 77700,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.all.first,
          brightness: Brightness.light,
        ),
        home: Scaffold(
          body: PayrollRedesignPage(
            actions: actionsFor(
              PayrollRedesignData(
                vouchers: [withoutMethod],
                paymentMethods: paymentMethods,
                releaseCapabilities: const PayrollReleaseCapabilities(
                  employeePaymentMethodCommand: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final action = find.byKey(
      const ValueKey<String>('payroll-mobile-person-action-Braulio Muñoz'),
    );
    expect(action, findsOneWidget);
    expect(
      find.descendant(of: action, matching: find.text('Configurar método')),
      findsOneWidget,
    );
    expect(find.text('Ver respaldo del pago'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'en el teléfono la tarjeta muestra el neto y el detalle lo explica',
      (tester) async {
    await pumpPage(
      tester,
      size: const Size(390, 844),
      advances: [braulioAdvance],
    );

    expect(find.text(r'$57.700'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'payroll-mobile-person-disclosure-Braulio Muñoz',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final detail = find.byKey(
      const ValueKey<String>('payroll-mobile-person-detail-Braulio Muñoz'),
    );
    expect(
      find.descendant(of: detail, matching: find.text('Anticipo del 07/11')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: detail, matching: find.text('−\$20.000')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: detail,
        matching: find.text(payrollAdvanceToDiscountNote),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
