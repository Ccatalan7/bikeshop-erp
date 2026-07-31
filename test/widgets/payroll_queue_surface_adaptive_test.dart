import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_queue_surface.dart';
import 'package:vinabike_erp/modules/hr/payroll/theme/payroll_tokens.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  PayrollWeekCardVM week() => PayrollWeekCardVM(
        name: 'Semana 28',
        range: '07 – 13 jul',
        amountLabel: r'$267.875',
        amountCaption: 'por pagar',
        statusLabel: 'ABIERTA',
        tone: PayrollStateTone.warning,
        selected: true,
        onTap: () {},
      );

  PayrollPersonRowVM row(
    int index, {
    PayrollRowStatus status = PayrollRowStatus.pendingTransfer,
    String statusLabel = 'Por pagar',
    String actionLabel = 'Pagar',
    PayrollRowActionMode actionMode = PayrollRowActionMode.direct,
    VoidCallback? onAction,
  }) =>
      PayrollPersonRowVM(
        name: 'Persona de prueba $index',
        initials: 'P$index',
        avatarColor: PayrollTokens.avatarSky,
        method: status == PayrollRowStatus.pendingCash
            ? 'Efectivo'
            : 'Transferencia bancaria',
        methodIsCash: status == PayrollRowStatus.pendingCash,
        earned: r'$172.875',
        advances: '—',
        newMoney: r'$172.875',
        paid: '—',
        status: status,
        statusLabel: statusLabel,
        statusMeta: '',
        actionLabel: actionLabel,
        actionMode: actionMode,
        hours: '38,5 h',
        rate: r'$4.490 / h',
        paymentsSummary: 'Sin pagos registrados',
        expanded: false,
        onToggle: () {},
        onAction: onAction ?? () {},
      );

  const totals = PayrollWeekTotalsVM(
    title: 'Semana 28 · 07 – 13 jul',
    equation: r'total $487.250 − anticipos $40.000 − pagado $179.375',
    remaining: r'$267.875',
    showCommitAction: false,
    canConfirm: false,
    blockedReason:
        'S28 pasa a Pagada automáticamente cuando sus saldos lleguen a \$0.',
    nextActionLabel: 'Pagar a Lucas',
  );

  Future<void> pumpQueue(
    WidgetTester tester, {
    required double width,
    required double height,
    required List<PayrollPersonRowVM> rows,
    required bool dense,
    PayrollWeekTotalsVM value = totals,
    VoidCallback? onOpenAttendance,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PayrollQueueSurface(
            weeks: <PayrollWeekCardVM>[week()],
            rows: rows,
            totals: value,
            dense: dense,
            onOpenAttendance: onOpenAttendance ?? () {},
            onConfirmWeek: () {},
            onNextAction: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('semana confirmada nunca ofrece un segundo cierre manual',
      (tester) async {
    await pumpQueue(
      tester,
      width: 1040,
      height: 620,
      rows: <PayrollPersonRowVM>[
        row(
          1,
          status: PayrollRowStatus.paid,
          statusLabel: 'Pagado',
          actionLabel: 'Ver pago',
          actionMode: PayrollRowActionMode.paidDetails,
        ),
      ],
      dense: false,
      value: const PayrollWeekTotalsVM(
        title: 'Semana 28 · 07 – 13 jul',
        equation: r'total $172.875 − anticipos $0 − pagado $172.875',
        remaining: r'$0',
        showCommitAction: false,
        canConfirm: false,
        blockedReason:
            r'Todos los saldos están en $0; la semana pasa a Pagada automáticamente.',
        nextActionLabel: '',
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('payroll-confirm-week')),
      findsNothing,
    );
    expect(find.textContaining('automáticamente'), findsOneWidget);
  });

  testWidgets('dense queue keeps one intrinsic decision without scaling',
      (tester) async {
    await pumpQueue(
      tester,
      width: 680,
      height: 620,
      dense: true,
      rows: <PayrollPersonRowVM>[
        row(
          1,
          status: PayrollRowStatus.pendingCash,
          statusLabel: 'Efectivo pendiente',
          actionLabel: 'Confirmar efectivo',
        ),
      ],
    );

    final actionGroup =
        find.byKey(const ValueKey('payroll-row-actions-Persona de prueba 1'));
    expect(actionGroup, findsOneWidget);
    expect(
      find.descendant(of: actionGroup, matching: find.byType(FittedBox)),
      findsNothing,
    );

    expect(
      find.descendant(
        of: actionGroup,
        matching: find.text('Efectivo pendiente'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: actionGroup,
        matching: find.text('Confirmar efectivo'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('payroll-queue-last-resort-scroll')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('payroll-attendance-strip')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing method is one anchored status menu', (tester) async {
    var configureCount = 0;
    await pumpQueue(
      tester,
      width: 1116,
      height: 620,
      dense: true,
      rows: <PayrollPersonRowVM>[
        row(
          1,
          status: PayrollRowStatus.pendingTransfer,
          statusLabel: 'Sin método',
          actionLabel: 'Configurar método',
          actionMode: PayrollRowActionMode.menu,
          onAction: () => configureCount++,
        ),
      ],
    );

    final status = find.text('Sin método');
    final menu = find.byKey(
      const ValueKey('payroll-method-menu-Persona de prueba 1'),
    );

    expect(status, findsOneWidget);
    expect(find.text('Configurar método'), findsNothing);
    expect(menu, findsOneWidget);

    await tester.tap(menu);
    await tester.pumpAndSettle();

    expect(find.text('Configurar método'), findsOneWidget);
    await tester.tap(find.text('Configurar método'));
    await tester.pumpAndSettle();

    expect(configureCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paid status itself opens payment details', (tester) async {
    var paymentCount = 0;
    await pumpQueue(
      tester,
      width: 1116,
      height: 620,
      dense: true,
      rows: <PayrollPersonRowVM>[
        row(
          1,
          status: PayrollRowStatus.paid,
          statusLabel: 'Pagado',
          actionLabel: 'Ver pago',
          actionMode: PayrollRowActionMode.paidDetails,
          onAction: () => paymentCount++,
        ),
      ],
    );

    final paid = find.byKey(
      const ValueKey('payroll-paid-status-Persona de prueba 1'),
    );
    expect(paid, findsOneWidget);
    expect(find.text('Pagado'), findsOneWidget);
    expect(find.text('Ver pago'), findsNothing);

    await tester.tap(paid);
    await tester.pump();

    expect(paymentCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('queue exposes one real attendance action', (tester) async {
    var openCount = 0;
    await pumpQueue(
      tester,
      width: 1116,
      height: 620,
      dense: true,
      rows: <PayrollPersonRowVM>[row(1)],
      onOpenAttendance: () => openCount++,
    );

    expect(find.text('Abrir Asistencias ↗'), findsOneWidget);
    expect(find.text('Ver asistencia ↗'), findsNothing);
    expect(find.text('Ver asistencia de la semana ↗'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('payroll-open-attendance-action')),
    );
    await tester.pump();

    expect(openCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('week card is one semantic InkWell action', (tester) async {
    await pumpQueue(
      tester,
      width: 1116,
      height: 620,
      dense: true,
      rows: <PayrollPersonRowVM>[row(1)],
    );

    final card = find.byKey(const ValueKey('payroll-week-card-Semana 28'));
    expect(card, findsOneWidget);
    final inkWell = tester.widget<InkWell>(card);
    expect(inkWell.mouseCursor, SystemMouseCursors.click);
    expect(inkWell.hoverColor, isNotNull);
    expect(inkWell.focusColor, isNotNull);
  });

  testWidgets('many workers use one bounded vertical scroll without overflow',
      (tester) async {
    await pumpQueue(
      tester,
      width: 1116,
      height: 560,
      dense: true,
      rows: <PayrollPersonRowVM>[
        for (var index = 1; index <= 24; index++) row(index),
      ],
    );

    final queue = find.byKey(const ValueKey('payroll-queue-vertical-scroll'));
    expect(queue, findsOneWidget);
    await tester.drag(queue, const Offset(0, -2400));
    await tester.pumpAndSettle();

    expect(find.text('Persona de prueba 24'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('payroll-attendance-strip')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('horizontal scroll appears only below the readable table floor',
      (tester) async {
    await pumpQueue(
      tester,
      width: 576,
      height: 620,
      dense: true,
      rows: <PayrollPersonRowVM>[
        row(
          1,
          status: PayrollRowStatus.pendingCash,
          statusLabel: 'Efectivo pendiente',
          actionLabel: 'Confirmar efectivo',
        ),
      ],
    );

    expect(
      find.byKey(const ValueKey('payroll-queue-last-resort-scroll')),
      findsOneWidget,
    );
    expect(find.text('Confirmar efectivo'), findsWidgets);
    expect(find.text('Efectivo pendiente'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
