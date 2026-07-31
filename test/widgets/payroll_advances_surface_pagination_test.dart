import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_advances_and_cash_surfaces.dart';
import 'package:vinabike_erp/modules/hr/payroll/theme/payroll_tokens.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  const ledger = <AdvanceLedgerRowVM>[
    AdvanceLedgerRowVM(
      date: '29/07',
      reason: 'Anticipo de prueba',
      amount: r'$20.000',
      applied: r'$5.000',
      balance: r'$15.000',
      statusLabel: 'VIGENTE',
      tone: PayrollStateTone.info,
    ),
  ];

  Future<void> pumpAdvances(
    WidgetTester tester, {
    required double width,
    bool hasMore = false,
    bool isLoadingMore = false,
    String? paginationError,
    VoidCallback? onLoadMore,
    bool settle = true,
  }) async {
    tester.view.physicalSize = Size(width, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PayrollAdvancesSurface(
            people: [
              AdvancePersonVM(
                id: 'worker-1',
                name: 'Guillermo Pinto',
                initials: 'GP',
                avatarColor: PayrollTokens.avatarAmber,
                balanceLabel: r'$15.000',
                caption: 'aplicable ahora',
                selected: true,
                onTap: () {},
              ),
            ],
            selectedName: 'Guillermo Pinto',
            selectedInitials: 'GP',
            selectedAvatar: PayrollTokens.avatarAmber,
            selectedBalance: r'$15.000',
            selectedCount: '1 movimiento',
            ledger: ledger,
            onNewAdvanceForSelectedPerson: () {},
            hasMore: hasMore,
            isLoadingMore: isLoadingMore,
            paginationError: paginationError,
            onLoadMore: onLoadMore,
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets('desktop exposes one bounded incremental ledger action',
      (tester) async {
    var loads = 0;
    await pumpAdvances(
      tester,
      width: 1000,
      hasMore: true,
      onLoadMore: () => loads += 1,
    );

    expect(
      find.byKey(const ValueKey<String>('payroll-advance-load-more')),
      findsOneWidget,
    );
    expect(find.text('Cargar movimientos anteriores'), findsOneWidget);

    await tester.tap(find.text('Cargar movimientos anteriores'));
    expect(loads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact pagination keeps a touch-safe loading state',
      (tester) async {
    await pumpAdvances(
      tester,
      width: 390,
      isLoadingMore: true,
      settle: false,
    );

    expect(
      find.byKey(
        const ValueKey<String>('payroll-advance-load-more-compact'),
      ),
      findsOneWidget,
    );
    expect(find.text('Cargando movimientos…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    final action = find.byKey(
      const ValueKey<String>('payroll-advance-pagination-action'),
    );
    expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
    expect(tester.widget<OutlinedButton>(action).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final width in <double>[1000, 390]) {
    testWidgets(
      'pagination failure is visible and retryable at ${width.toInt()} px',
      (tester) async {
        var retries = 0;
        const message = 'No pudimos cargar más anticipos. Reintenta.';
        await pumpAdvances(
          tester,
          width: width,
          paginationError: message,
          onLoadMore: () => retries += 1,
        );

        expect(
          find.byKey(
            const ValueKey<String>('payroll-advance-pagination-error'),
          ),
          findsOneWidget,
        );
        expect(find.text(message), findsOneWidget);
        expect(
          find.bySemanticsLabel(
            'Error al cargar movimientos anteriores: $message',
          ),
          findsOneWidget,
        );

        await tester.tap(find.text('Reintentar cargar movimientos'));
        expect(retries, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('pagination remains absent for backward-compatible defaults',
      (tester) async {
    await pumpAdvances(tester, width: 1000);

    expect(
      find.byKey(const ValueKey<String>('payroll-advance-load-more')),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey<String>('payroll-advance-load-more-compact'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
