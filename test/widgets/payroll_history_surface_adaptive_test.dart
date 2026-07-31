import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_history_surface.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  const weeks = <PayrollHistoryWeekVM>[
    PayrollHistoryWeekVM(
      id: 'week-28',
      title: 'Semana 28',
      range: '07 – 13 jul',
      amount: r'$235.000',
      status: 'PAGADA',
      voided: false,
      selected: true,
    ),
    PayrollHistoryWeekVM(
      id: 'week-27',
      title: 'Semana 27',
      range: '29 jun – 05 jul',
      amount: r'$225.000',
      status: 'PAGADA',
      voided: false,
      selected: false,
    ),
  ];

  const detail = PayrollHistoryDetailVM(
    id: 'week-28',
    title: 'Semana 28',
    range: '07 – 13 jul',
    voucherNumber: 'NOM-00028',
    status: 'PAGADA',
    voided: false,
    weekTotal: r'$235.000',
    payable: r'$199.000',
    paid: r'$199.000',
    advances: r'−$36.000',
    pending: r'$0',
    settled: true,
    lines: <PayrollHistoryLineVM>[
      PayrollHistoryLineVM(
        name: 'Vicente Díaz',
        weekTotal: r'$129.500',
        paid: r'$129.500',
        advances: r'$0',
        pending: r'$0',
      ),
    ],
  );

  Future<void> pumpHistory(
    WidgetTester tester,
    double width, {
    bool hasMore = false,
    bool isLoadingMore = false,
    String? paginationError,
    VoidCallback? onLoadMore,
  }) async {
    tester.view.physicalSize = Size(width, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PayrollHistorySurface(
            weeks: weeks,
            detail: detail,
            compact: false,
            isHydrating: false,
            authoritativeReady: true,
            error: null,
            onSelect: (_) {},
            onRetry: () {},
            hasMore: hasMore,
            isLoadingMore: isLoadingMore,
            paginationError: paginationError,
            onLoadMore: onLoadMore,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('uses its own available width instead of the shell breakpoint',
      (tester) async {
    await pumpHistory(tester, 700);

    expect(
      find.byKey(const ValueKey('payroll-history-selector')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('payroll-history-ledger')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('payroll-history-compact-ledger')),
      findsOneWidget,
    );
    expect(
      find.text(r'$129.500 total − $129.500 pagos − $0 anticipos'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide history is one continuous index and ledger',
      (tester) async {
    await pumpHistory(tester, 1000);

    expect(
      find.byKey(const ValueKey('payroll-history-selector')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('payroll-history-ledger')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('payroll-history-week-week-28')),
      findsOneWidget,
    );
    // 5i: la banda es la aritmética completa en orden.
    for (final label in const [
      'TOTAL',
      'ANTICIPOS',
      'A PAGAR',
      'PAGADO',
      'SALDO'
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('GANADO'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop exposes one explicit incremental history action',
      (tester) async {
    var loads = 0;
    await pumpHistory(
      tester,
      1000,
      hasMore: true,
      onLoadMore: () => loads += 1,
    );

    expect(
      find.byKey(const ValueKey('payroll-history-load-more')),
      findsOneWidget,
    );
    expect(find.text('2+'), findsOneWidget);
    await tester.tap(find.text('Cargar semanas anteriores'));
    expect(loads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pagination failure is visible and retry remains explicit',
      (tester) async {
    var retries = 0;
    await pumpHistory(
      tester,
      1000,
      paginationError: 'No pudimos cargar más semanas. Reintenta.',
      onLoadMore: () => retries += 1,
    );

    expect(
      find.byKey(const ValueKey('payroll-history-pagination-error')),
      findsOneWidget,
    );
    expect(
      find.text('No pudimos cargar más semanas. Reintenta.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Reintentar cargar historial'));
    expect(retries, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact keeps pagination outside the week selector',
      (tester) async {
    await pumpHistory(
      tester,
      390,
      hasMore: true,
      onLoadMore: () {},
    );

    expect(
      find.byKey(const ValueKey('payroll-history-load-more-compact')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('payroll-history-selector')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
