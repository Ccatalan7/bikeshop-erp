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
      monthLabel: 'julio 2026',
      people: '4 personas',
      balance: r'$0',
    ),
    PayrollHistoryWeekVM(
      id: 'week-26',
      title: 'Semana 26',
      range: '22 – 28 jun',
      amount: r'$225.000',
      status: 'PAGADA',
      voided: false,
      selected: false,
      monthLabel: 'junio 2026',
      people: '4 personas',
      balance: r'$18.000',
      settled: false,
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
    peopleLabel: '2 personas',
    closedNote: 'registró Claudio Catalán · 29 jun 17:00',
    lines: <PayrollHistoryLineVM>[
      PayrollHistoryLineVM(
        name: 'Vicente Díaz',
        weekTotal: r'$129.500',
        paid: r'$129.500',
        advances: '—',
        pending: r'$0',
        methodAndDate: 'Transferencia · 07/07',
        hasEvidence: true,
      ),
      PayrollHistoryLineVM(
        name: 'Lucas Pacheco',
        weekTotal: r'$105.500',
        paid: r'$69.500',
        advances: r'−$36.000',
        pending: r'$18.000',
        settled: false,
        methodAndDate: 'Efectivo · 08/07',
        hasEvidence: true,
      ),
    ],
  );

  Future<void> pumpHistory(
    WidgetTester tester,
    double width, {
    bool compact = false,
    bool hasMore = false,
    bool isLoadingMore = false,
    String? paginationError,
    ValueChanged<String>? onSelect,
    VoidCallback? onLoadMore,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PayrollHistorySurface(
            weeks: weeks,
            detail: detail,
            compact: compact,
            isHydrating: false,
            authoritativeReady: true,
            error: null,
            onSelect: onSelect ?? (_) {},
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

  testWidgets('7b · la banda es la aritmética completa en orden',
      (tester) async {
    await pumpHistory(tester, 1400);

    for (final label in const [
      'TOTAL',
      'ANTICIPOS',
      'A PAGAR',
      'PAGADO',
      'SALDO',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('GANADO'), findsNothing);
    // La cifra dominante del encabezado, no una repetición de la banda.
    expect(
      find.byKey(const ValueKey<String>('payroll-history-week-total')),
      findsOneWidget,
    );
    expect(find.text('Semana 28 · 07 – 13 jul'), findsOneWidget);
    expect(
      find.text('2 personas · registró Claudio Catalán · 29 jun 17:00'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '7b · la tabla declara MÉTODO Y FECHA cuando las seis pistas caben',
      (tester) async {
    await pumpHistory(tester, 1400);

    expect(find.text('PERSONA'), findsOneWidget);
    expect(find.text('MÉTODO Y FECHA'), findsOneWidget);
    expect(find.text('Transferencia · 07/07'), findsOneWidget);
    expect(find.text('Efectivo · 08/07'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('payroll-history-ledger')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'bajo el ancho de las seis pistas el método baja a subtítulo, no desaparece',
      (tester) async {
    // 1000 de ventana deja el libro por debajo de methodColumnMinWidth: es el
    // caso real de una ventana de 1360 con el rail puesto.
    await pumpHistory(tester, 1000);

    expect(find.text('MÉTODO Y FECHA'), findsNothing);
    expect(find.text('PERSONA'), findsOneWidget);
    // El dato sigue en pantalla: el escalón mueve la columna, no la borra.
    expect(find.text('Transferencia · 07/07'), findsOneWidget);
    expect(find.text('Efectivo · 08/07'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('un saldo abierto por persona se declara; uno en cero no grita',
      (tester) async {
    await pumpHistory(tester, 1400);

    expect(
      find.byKey(
        const ValueKey<String>('payroll-history-open-balance-Lucas Pacheco'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('payroll-history-open-balance-Vicente Díaz'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'el estado de la semana se lee por punto y rótulo, no por píldora',
      (tester) async {
    await pumpHistory(tester, 1400);

    // Dos filas de lista + el encabezado del detalle.
    expect(find.text('PAGADA'), findsNWidgets(3));
    // La lista es un panel de 300 pegado al borde, no una tarjeta con margen.
    final list = tester.getRect(
      find.byKey(const ValueKey('payroll-history-week-week-28')),
    );
    expect(list.left, 0);
    expect(list.width, 300);
    expect(list.height, greaterThanOrEqualTo(62));
    expect(tester.takeException(), isNull);
  });

  testWidgets('la lista agrupa por mes, que es lo que el backend sí sabe',
      (tester) async {
    await pumpHistory(tester, 1400);

    expect(
      find.byKey(const ValueKey<String>('payroll-history-month-julio 2026')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('payroll-history-month-junio 2026')),
      findsOneWidget,
    );
    expect(find.text('JULIO 2026'), findsOneWidget);
    // El selector de mes de 5i no se maqueta: el RPC no acepta un mes.
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no se ofrece reabrir la semana ni una bitácora que no existe',
      (tester) async {
    await pumpHistory(tester, 1400);

    expect(find.text('Reabrir semana'), findsNothing);
    expect(find.text('Ver bitácora'), findsNothing);
    expect(find.textContaining('solo lectura'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop expone una sola acción incremental explícita',
      (tester) async {
    var loads = 0;
    await pumpHistory(
      tester,
      1400,
      hasMore: true,
      onLoadMore: () => loads += 1,
    );

    expect(
      find.byKey(const ValueKey('payroll-history-load-more')),
      findsOneWidget,
    );
    await tester.tap(find.text('Cargar semanas anteriores'));
    expect(loads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la falla de paginación es visible y el reintento explícito',
      (tester) async {
    var retries = 0;
    await pumpHistory(
      tester,
      1400,
      paginationError: 'No pudimos cargar más semanas. Reintenta.',
      onLoadMore: () => retries += 1,
    );

    expect(
      find.byKey(const ValueKey('payroll-history-pagination-error')),
      findsOneWidget,
    );
    await tester.tap(find.text('Reintentar cargar historial'));
    expect(retries, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compacto: la lista es el control, y no un select de 30 semanas',
      (tester) async {
    await pumpHistory(tester, 430,
        compact: true, hasMore: true, onLoadMore: () {});

    // S-05 topa en ~7 opciones y S-06 no existe en el repositorio: el select
    // desaparece y la lista queda como el control.
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(
      find.byKey(const ValueKey('payroll-history-index-compact')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('payroll-history-load-more-compact')),
      findsOneWidget,
    );
    // Primer paso: elegir semana. El detalle todavía no está en pantalla.
    expect(find.byKey(const ValueKey('payroll-history-ledger')), findsNothing);
    expect(
      find.byKey(const ValueKey('payroll-history-compact-ledger')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compacto: elegir una semana abre su detalle y el retorno vuelve',
      (tester) async {
    final picked = <String>[];
    await pumpHistory(
      tester,
      430,
      compact: true,
      onSelect: picked.add,
    );

    await tester
        .tap(find.byKey(const ValueKey('payroll-history-week-week-28')));
    await tester.pumpAndSettle();

    expect(picked, <String>['week-28']);
    expect(
      find.byKey(const ValueKey('payroll-history-compact-ledger')),
      findsOneWidget,
    );
    expect(find.text('Transferencia · 07/07'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('payroll-history-back-to-index')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('payroll-history-index-compact')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('payroll-history-compact-ledger')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('el historial vacío no dibuja ni lista ni detalle',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PayrollHistorySurface(
            weeks: const <PayrollHistoryWeekVM>[],
            detail: null,
            compact: false,
            isHydrating: false,
            authoritativeReady: true,
            error: null,
            onSelect: (_) {},
            onRetry: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Todavía no hay semanas pagadas o anuladas.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
