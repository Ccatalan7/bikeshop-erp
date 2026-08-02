import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_queue_surface.dart';
import 'package:vinabike_erp/modules/hr/payroll/theme/payroll_tokens.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/vb_notice.dart';

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
    VoidCallback? onToggle,
    bool expanded = false,
    String blockedReason = '',
    PayrollRowDestinationVM? destination,
    List<PayrollRowShortcutVM> shortcuts = const <PayrollRowShortcutVM>[],
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
        blockedReason: blockedReason,
        hours: '38,5 h',
        rate: r'$4.490 / h',
        paymentsSummary: 'Sin pagos registrados',
        expanded: expanded,
        destination: destination,
        shortcuts: shortcuts,
        onToggle: onToggle ?? () {},
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
    String? excludedNote,
    String? blockedNote,
    VoidCallback? onOpenAttendance,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        // La cola monta `E-04 · VbNotice`, que exige `VinabikeThemeRoles`: un
        // `MaterialApp` pelado la revienta con `roles != null`. El tema se
        // construye por `AppTheme`, igual que en la app.
        theme: AppTheme.resolve(
          preset: AppearancePresets.vinabike,
          brightness: Brightness.light,
        ),
        home: Scaffold(
          body: PayrollQueueSurface(
            weeks: <PayrollWeekCardVM>[week()],
            rows: rows,
            totals: value,
            dense: dense,
            excludedNote: excludedNote,
            blockedNote: blockedNote,
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
      // `5b` retira la franja en la banda comprimida; su presencia se afirma
      // en la banda ancha y su ausencia a 1116 tiene contrato propio.
      find.byKey(const ValueKey('payroll-attendance-strip')),
      findsNothing,
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
    // `5b` oculta la franja a 1116, así que la salida permanente se afirma en
    // la banda ancha; que a 1116 NO esté es su propio contrato, más abajo.
    await pumpQueue(
      tester,
      width: 1440,
      height: 620,
      dense: false,
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
      // `5b` retira la franja en la banda comprimida; su presencia se afirma
      // en la banda ancha y su ausencia a 1116 tiene contrato propio.
      find.byKey(const ValueKey('payroll-attendance-strip')),
      findsNothing,
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

  testWidgets(
      '7a · ↑/↓ mueven el foco de fila y ↵ abre la enfocada, una a la vez',
      (tester) async {
    final toggled = <int>[];
    await pumpQueue(
      tester,
      width: 1360,
      height: 900,
      dense: false,
      rows: <PayrollPersonRowVM>[
        for (var i = 0; i < 3; i++) row(i, onToggle: () => toggled.add(i)),
      ],
    );

    // El foco entra en la tabla por la primera fila.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    Finder rowFinder(int index) => find.ancestor(
          of: find.text('Persona de prueba $index'),
          matching: find.byType(FocusableActionDetector),
        );
    bool focused(int index) => tester
        .widget<FocusableActionDetector>(rowFinder(index).first)
        .focusNode!
        .hasFocus;

    // Puede entrar en cualquier control; se ancla en la fila 0 a mano y desde
    // ahí se mide la conducta, que es lo que el contrato promete.
    tester
        .widget<FocusableActionDetector>(rowFinder(0).first)
        .focusNode!
        .requestFocus();
    await tester.pumpAndSettle();
    expect(focused(0), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focused(1), isTrue, reason: '↓ baja una fila');
    expect(focused(0), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focused(2), isTrue);

    // El borde inferior no envuelve: la última fila se queda donde está.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focused(2), isTrue, reason: 'no hay wrap-around');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(focused(1), isTrue, reason: '↑ sube una fila');

    // ↵ abre exactamente la fila enfocada, y ninguna otra.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(toggled, <int>[1]);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(toggled, <int>[1, 1], reason: '↵ también cierra: es el mismo verbo');
    expect(tester.takeException(), isNull);
  });

  testWidgets('7a · la pista de teclado sólo aparece en la fila abierta',
      (tester) async {
    await pumpQueue(
      tester,
      width: 1360,
      height: 900,
      dense: false,
      rows: <PayrollPersonRowVM>[row(0), row(1)],
    );
    expect(
      find.byKey(const ValueKey<String>('payroll-row-keyboard-hint')),
      findsNothing,
    );

    await pumpQueue(
      tester,
      width: 1360,
      height: 900,
      dense: false,
      rows: <PayrollPersonRowVM>[
        row(
          0,
          expanded: true,
          shortcuts: <PayrollRowShortcutVM>[
            PayrollRowShortcutVM(label: 'Ver historial', onTap: () {}),
          ],
        ),
        row(1),
      ],
    );
    expect(
      find.byKey(const ValueKey<String>('payroll-row-keyboard-hint')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '7a · PAGOS DE ESTA SEMANA nombra la cuenta DESTINO, nunca la contable',
      (tester) async {
    await pumpQueue(
      tester,
      width: 1360,
      height: 900,
      dense: false,
      rows: <PayrollPersonRowVM>[
        row(
          0,
          expanded: true,
          destination: const PayrollRowDestinationVM.known(
            'Banco Estado · Cuenta Vista · •••• 4821',
          ),
        ),
      ],
    );

    expect(
      find.byKey(const ValueKey<String>('payroll-row-destination')),
      findsOneWidget,
    );
    expect(
        find.text('Banco Estado · Cuenta Vista · •••• 4821'), findsOneWidget);
    // El número entero jamás se dibuja.
    expect(find.textContaining('124821'), findsNothing);

    await pumpQueue(
      tester,
      width: 1360,
      height: 900,
      dense: false,
      rows: <PayrollPersonRowVM>[
        row(0,
            expanded: true,
            destination: const PayrollRowDestinationVM.missing()),
      ],
    );
    expect(
      find.byKey(const ValueKey<String>('payroll-row-destination-missing')),
      findsOneWidget,
    );
    expect(find.text('Sin cuenta de destino registrada'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '5m · a 834 la tabla son CUATRO columnas: persona, total, a pagar y '
      'decisión', (tester) async {
    // Fuente: proyecto `ERP Bikeshop UI Mockups`, página `Nóminas - Rediseño`,
    // turno 5, frame `5m-p1`. Su anotación 01 es literal: «Desaparecen
    // ANTICIPOS y PAGADO: la aritmética completa vive en la disclosure y el
    // chip. Quedan persona, total, a pagar y decisión.»
    await pumpQueue(
      tester,
      width: 834,
      height: 1112,
      dense: false,
      rows: <PayrollPersonRowVM>[row(0), row(1)],
    );

    expect(find.text('PERSONA'), findsOneWidget);
    expect(find.text('TOTAL'), findsOneWidget);
    expect(find.text('A PAGAR'), findsOneWidget);
    expect(find.text('DECISIÓN'), findsOneWidget);
    // Las dos que 5m retira, y el método que ya se había ido al bajar de 1200.
    // **Las DOS grafías**: cuando la tabla se estrecha el rótulo se abrevia a
    // `ANTIC.`, así que comprobar sólo `ANTICIPOS` deja pasar la columna
    // entera. El aserto anterior no mordía por exactamente eso.
    expect(find.text('ANTICIPOS'), findsNothing);
    expect(find.text('ANTIC.'), findsNothing);
    expect(find.text('PAGADO'), findsNothing);
    expect(find.text('MÉTODO'), findsNothing);

    // Y a 1000 la columna sí existe, abreviada: el umbral de 5m es 900, no
    // «siempre que la tabla sea estrecha».
    await pumpQueue(
      tester,
      width: 1000,
      height: 900,
      dense: false,
      rows: <PayrollPersonRowVM>[row(0)],
    );
    expect(find.text('ANTIC.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('5m · a 834 la fila mide 60 y el control de decisión 44 × 200',
      (tester) async {
    // Anotación 02 de `5m-p1`: «El mismo control de decisión crece a 44 de alto
    // y 200 de ancho, sin cambiar de forma ni de verbo».
    await pumpQueue(
      tester,
      width: 834,
      height: 1112,
      dense: false,
      rows: <PayrollPersonRowVM>[row(0)],
    );

    // La fila de 60 se afirma sobre la RESTRICCIÓN declarada, no sobre el alto
    // renderizado: el contenido ya empuja la fila por encima de 60 en
    // escritorio, así que medir el pixel no distinguiría el tier.
    final rowBox = tester.widget<Container>(
      find
          .descendant(
            of: find.ancestor(
              of: find.text('Persona de prueba 0'),
              matching: find.byType(FocusableActionDetector),
            ),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      rowBox.constraints?.minHeight,
      tabletRowHeight,
      reason: 'la fila de tablet declara 60',
    );

    final action = tester.getSize(
      find.byKey(const ValueKey<String>(
        'payroll-row-action-tap-Persona de prueba 0',
      )),
    );
    expect(
      action.height,
      greaterThanOrEqualTo(PayrollTokens.touchMin),
      reason: 'el control táctil mide 44',
    );

    // `greaterThanOrEqualTo` es exactamente lo que dejó pasar el defecto: con
    // la regla de columna en 280 el control crecía y la prueba seguía verde.
    // `5n` declara `maxWidth 186/168/200`, así que 200 es TOPE, no piso.
    expect(
      action.width,
      tabletDecisionWidth,
      reason: '`5n`: en táctil el control de decisión mide 200 exactos, '
          'no «al menos 200»',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('5m · el tier de tablet no se filtra a escritorio ni a teléfono',
      (tester) async {
    // 1360 conserva sus columnas y su fila de 48; 430 ya no es tabla.
    await pumpQueue(
      tester,
      width: 1360,
      height: 900,
      dense: false,
      rows: <PayrollPersonRowVM>[row(0)],
    );
    expect(find.text('ANTICIPOS'), findsOneWidget);
    final desktopAction = tester.getSize(
      find.byKey(const ValueKey<String>(
        'payroll-row-action-tap-Persona de prueba 0',
      )),
    );
    // En escritorio el control sigue siendo intrínseco al verbo (5a), no el
    // objetivo táctil de tablet: ésa es la diferencia entre los dos tiers.
    expect(
      desktopAction.width,
      lessThan(tabletDecisionWidth),
      reason: 'escritorio no reserva los 200 de tablet',
    );
    expect(
      desktopAction.height,
      lessThan(PayrollTokens.touchMin),
      reason: 'escritorio conserva el control denso',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '5b · a 1116 la franja de Asistencias se oculta, y la nota de '
      'excluidos ocupa su lugar', (tester) async {
    // Fuente: proyecto `ERP Bikeshop UI Mockups`, página `Nóminas - Rediseño`,
    // turno 5, frame `5b-p2`. Su geometría lo dice literal: «franja Asistencias
    // oculta». Con el sidebar expandido el canvas no sobra y una franja
    // permanente que sólo recuerda una regla es lo primero que se retira.
    await pumpQueue(
      tester,
      width: 1116,
      height: 700,
      dense: true,
      rows: <PayrollPersonRowVM>[row(0)],
      onOpenAttendance: () {},
    );
    expect(
      find.text('Abrir Asistencias ↗'),
      findsNothing,
      reason: '5b oculta la franja a 1116',
    );

    // Pero la salida real nunca desaparece: cuando hay gente fuera del
    // cálculo, la nota la ofrece con su razón.
    await pumpQueue(
      tester,
      width: 1116,
      height: 700,
      dense: true,
      rows: <PayrollPersonRowVM>[row(0)],
      excludedNote: '1 persona queda fuera del cálculo: Rocío · horas sin '
          'cerrar en Asistencias',
      onOpenAttendance: () {},
    );
    expect(
      find.textContaining('fuera del cálculo'),
      findsOneWidget,
      reason: 'la nota de excluidos ocupa el lugar de la franja',
    );

    // Y en la banda ancha la franja sigue existiendo.
    await pumpQueue(
      tester,
      width: 1440,
      height: 700,
      dense: false,
      rows: <PayrollPersonRowVM>[row(0)],
      onOpenAttendance: () {},
    );
    expect(find.text('Abrir Asistencias ↗'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ── `5c` · gramática de decisión ─────────────────────────────────────────
  Finder decisionOf(String name) =>
      find.byKey(ValueKey<String>('payroll-row-actions-$name'));

  PayrollPersonRowVM blockedRow(
    int index, {
    String reason = '',
    bool expanded = false,
    List<PayrollRowShortcutVM> shortcuts = const <PayrollRowShortcutVM>[],
  }) =>
      row(
        index,
        status: PayrollRowStatus.weekNotConfirmed,
        statusLabel: 'Semana sin confirmar',
        actionLabel: '',
        actionMode: PayrollRowActionMode.none,
        blockedReason: reason,
        expanded: expanded,
        shortcuts: shortcuts,
      );

  testWidgets(
      '5c · la forma pasiva es texto, no una píldora: sin control ni cursor de '
      'acción', (tester) async {
    await pumpQueue(
      tester,
      width: 1360,
      height: 620,
      dense: false,
      rows: <PayrollPersonRowVM>[blockedRow(1, reason: 'La semana no cerró.')],
    );

    final cell = decisionOf('Persona de prueba 1');
    expect(cell, findsOneWidget);

    // «texto pasivo, sin falsa acción»: ni Material ni InkWell dentro de la
    // celda. Una píldora tonal usa los dos, así que devolverla rompe acá.
    expect(
      find.descendant(of: cell, matching: find.byType(Material)),
      findsNothing,
      reason: 'la forma pasiva no lleva superficie propia',
    );
    expect(
      find.descendant(of: cell, matching: find.byType(InkWell)),
      findsNothing,
      reason: 'la forma pasiva no es un control',
    );

    final text = tester.widget<Text>(
      find.descendant(of: cell, matching: find.text('Semana sin confirmar')),
    );
    // `7a`, literal del canvas: `font:400 11px … color:#7E8A94` (= inkFaint).
    expect(text.style?.fontSize, decisionLabelSize);
    expect(text.style?.fontWeight, FontWeight.w400);
    expect(
      text.style?.color,
      PayrollVisualTokens.of(tester.element(cell)).inkFaint,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('5c · el bloqueo nunca aparece sin su motivo', (tester) async {
    const reason = 'La semana está en borrador: confirmarla es el paso que '
        'falta.';
    await pumpQueue(
      tester,
      width: 1360,
      height: 620,
      dense: false,
      rows: <PayrollPersonRowVM>[blockedRow(1, reason: reason)],
    );

    final cell = decisionOf('Persona de prueba 1');
    // El motivo NO puede viajar en un `Tooltip`: con la semana en borrador hay
    // uno por fila, y varios `OverlayPortal` reentrantes en el mismo relayout
    // de banda tumbaron el módulo en la app viva
    // (`overlay.dart:1258 · '!_skipMarkNeedsLayout'`).
    expect(
      find.descendant(of: cell, matching: find.byType(Tooltip)),
      findsNothing,
    );

    // Viaja como propiedad semántica: `aria-disabled` + el motivo, en
    // un nodo PROPIO. Si se funde con el de la fila hereda el botón del caret
    // y el lector anuncia la fila entera como deshabilitada, que es falso.
    final node = tester.getSemantics(
      find.byKey(
        const ValueKey<String>('payroll-row-blocked-Persona de prueba 1'),
      ),
    );
    expect(node.label, contains(reason));
    expect(node.tooltip, reason);
    // `aria-disabled` son DOS hechos, no uno: que el control TIENE estado de
    // habilitación y que está apagado. Con el `hasFlag` viejo había que
    // afirmarlos por separado —y afirmar sólo `!isEnabled` no probaba nada,
    // porque un nodo que nunca declaró el estado también da falso—. El
    // `Tristate` los dice juntos: `isFalse` ≠ `none`.
    expect(
      node.flagsCollection.isEnabled,
      Tristate.isFalse,
      reason: 'declara estado de habilitación Y que está apagado',
    );
    expect(
      node.flagsCollection.isButton,
      isFalse,
      reason: 'un bloqueo no se anuncia como botón: no hay nada que pulsar',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('5c · el anillo de foco aparece con teclado y NO con el clic',
      (tester) async {
    await pumpQueue(
      tester,
      width: 1360,
      height: 620,
      dense: false,
      rows: <PayrollPersonRowVM>[row(1)],
    );

    const ring = ValueKey<String>('payroll-decision-focus-ring');
    expect(find.byKey(ring), findsNothing);

    // Un clic de puntero no deja anillo: en Material el `InkWell` no mueve el
    // foco al tocarlo, y el anillo se cuelga de ese foco y de ninguna otra
    // cosa. Si alguien lo ata al hover o al `onTap`, esta línea lo caza.
    await tester.tap(find.byKey(
      const ValueKey<String>('payroll-row-action-tap-Persona de prueba 1'),
    ));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ring),
      findsNothing,
      reason: 'visible con teclado, no con clic',
    );

    // Con el teclado sí: se recorre el orden de tabulación hasta el control.
    var appeared = false;
    for (var i = 0; i < 8 && !appeared; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      appeared = find.byKey(ring).evaluate().isNotEmpty;
    }
    expect(appeared, isTrue, reason: 'el foco de teclado sí dibuja el anillo');
    expect(tester.takeException(), isNull);
  });

  testWidgets('5c · «Sin método» es un bloqueo, y se pinta como tal',
      (tester) async {
    await pumpQueue(
      tester,
      width: 1360,
      height: 620,
      dense: false,
      rows: <PayrollPersonRowVM>[
        row(
          1,
          statusLabel: 'Sin método',
          actionLabel: 'Configurar método',
          actionMode: PayrollRowActionMode.menu,
        ),
      ],
    );

    final chip = find.byKey(
      const ValueKey<String>('payroll-method-menu-Persona de prueba 1'),
    );
    final visual = PayrollVisualTokens.of(tester.element(chip));
    final material = tester.widget<Material>(chip);
    expect(
      material.color,
      visual.danger.soft,
      reason: '`7a` lo dibuja en danger; heredar el tono de la fila lo pintaba '
          'igual que «falta confirmar», que sí se puede pagar',
    );
    expect(material.color, isNot(visual.warning.soft));

    // Envoltura compartida de `7a`: radio 8 y alto 28, no cápsula.
    final shape = material.shape;
    expect(shape, isA<RoundedRectangleBorder>());
    expect(
      (shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(PayrollTokens.rField),
    );
    expect(
      tester.getSize(chip).height,
      greaterThanOrEqualTo(decisionCellHeight),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '5c · ninguna forma de decisión monta un Tooltip dentro de la tabla',
      (tester) async {
    // Causa medida en la app viva, no supuesta: `Tooltip` monta un
    // `OverlayPortal`, y montarlo DENTRO del `LayoutBuilder` de esta tabla
    // revienta al cambiar el ancho de la ventana —
    // `overlay.dart:1258 · '!_skipMarkNeedsLayout'`, con el error apuntando al
    // `Tooltip` por nombre—. Con una fila por trabajador eso es un portal por
    // fila. Lo que decían esos tooltips vive ahora en `Semantics.tooltip`, que
    // no monta nada. La prueba de widget NO reproduce el fallo: hace falta el
    // relayout real de la ventana. Por eso el contrato es estructural.
    await pumpQueue(
      tester,
      width: 1360,
      height: 760,
      dense: false,
      rows: <PayrollPersonRowVM>[
        row(1),
        row(2, status: PayrollRowStatus.pendingCash),
        row(
          3,
          status: PayrollRowStatus.paid,
          statusLabel: 'Pagado',
          actionLabel: 'Ver pago',
          actionMode: PayrollRowActionMode.paidDetails,
        ),
        row(
          4,
          statusLabel: 'Sin método',
          actionLabel: 'Configurar método',
          actionMode: PayrollRowActionMode.menu,
        ),
        blockedRow(5, reason: 'La semana no cerró.'),
      ],
    );

    for (final name in <String>[
      'Persona de prueba 1',
      'Persona de prueba 2',
      'Persona de prueba 3',
      'Persona de prueba 4',
      'Persona de prueba 5',
    ]) {
      expect(
        find.descendant(of: decisionOf(name), matching: find.byType(Tooltip)),
        findsNothing,
        reason: '$name monta un Tooltip en su celda de decisión',
      );
    }
    // Y tampoco el caret, que es donde vivía el defecto ANTES de `5c`.
    expect(
      find.byType(Tooltip),
      findsNothing,
      reason: 'ningún Tooltip en toda la cola, incluido el del caret',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '5c · el motivo del bloqueo se VE, en la franja del pie, cuando todas '
      'las filas lo comparten', (tester) async {
    // Reproducido en proceso limpio (PID 65685, sin hot reload): un `Tooltip`
    // **visible** dentro del `LayoutBuilder` de esta tabla revienta al cambiar
    // de banda. El vehículo seguro es el que dibuja el propio `7a` —«la franja
    // del pie manda a Asistencias»— con el dueño canónico `E-04 · VbNotice`,
    // que es en línea y no monta nada sobre el overlay.
    const reason = 'La semana está en borrador: hasta confirmarla las horas no '
        'quedan fijas.';
    await pumpQueue(
      tester,
      width: 1360,
      height: 760,
      dense: false,
      rows: <PayrollPersonRowVM>[
        blockedRow(1, reason: reason),
        blockedRow(2, reason: reason),
      ],
      blockedNote: reason,
    );

    final note = find.byKey(const ValueKey<String>('payroll-blocked-note'));
    expect(note, findsOneWidget);
    expect(
      find.descendant(of: note, matching: find.byType(VbNotice)),
      findsOneWidget,
      reason: 'el aviso en línea es del dueño canónico E-04, no uno local',
    );
    expect(
      find.descendant(of: note, matching: find.text(reason)),
      findsOneWidget,
      reason: 'el motivo se lee con el ojo, no sólo con lector de pantalla',
    );
    // Y **ninguna parte** de la cola monta un `Tooltip`. No es una regla de la
    // celda de decisión: es de la tabla entera. Se comprobó en proceso limpio
    // que el tooltip del caret —anterior a `5c`— tumba el módulo igual, así
    // que el contrato cubre toda la superficie o no cubre nada.
    expect(find.byType(Tooltip), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '5c · con motivos distintos la franja calla y cada fila abierta lleva el '
      'suyo', (tester) async {
    await pumpQueue(
      tester,
      width: 1360,
      height: 900,
      dense: false,
      rows: <PayrollPersonRowVM>[
        blockedRow(1, reason: 'La semana está en borrador.'),
        blockedRow(2,
            reason: 'Asistencias no cerró sus horas.', expanded: true),
      ],
      // El host devuelve `null` cuando los motivos no coinciden: una sola
      // franja no puede hablar por dos razones sin mentirle a una.
    );

    expect(
      find.byKey(const ValueKey<String>('payroll-blocked-note')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>(
        'payroll-disclosure-blocked-Persona de prueba 2',
      )),
      findsOneWidget,
      reason: 'la fila abierta explica su propio bloqueo',
    );
    expect(find.text('POR QUÉ NO SE PUEDE PAGAR'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '5c · cuando la franja YA dice el motivo, la fila abierta no lo repite',
      (tester) async {
    // `7a` dibuja la fila abierta con TRES paneles. Un cuarto que copia
    // palabra por palabra un aviso visible más abajo no es redundancia
    // inofensiva: aprieta la grilla y le quita jerarquía a los tres que sí
    // aportan.
    const reason = 'La semana está en borrador.';
    await pumpQueue(
      tester,
      width: 1360,
      height: 900,
      dense: false,
      rows: <PayrollPersonRowVM>[
        blockedRow(
          1,
          reason: reason,
          expanded: true,
          shortcuts: <PayrollRowShortcutVM>[
            PayrollRowShortcutVM(label: 'Ver historial', onTap: () {}),
          ],
        ),
      ],
      blockedNote: reason,
    );

    expect(
      find.byKey(const ValueKey<String>('payroll-blocked-note')),
      findsOneWidget,
    );
    expect(
      find.text('POR QUÉ NO SE PUEDE PAGAR'),
      findsNothing,
      reason: 'la franja del pie ya lo dice; el panel sobra',
    );
    // Y los tres paneles de `7a` siguen ahí.
    expect(find.text('CÓMO SE CALCULÓ'), findsOneWidget);
    expect(find.text('PAGOS DE ESTA SEMANA'), findsOneWidget);
    expect(find.text('ATAJOS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('5c · el control trunca con elipsis y nunca se parte en dos',
      (tester) async {
    // `5b`, literal: «las etiquetas largas se truncan con elipsis; el control
    // jamás se parte en dos líneas». Se mide a 1116, que es donde la celda de
    // decisión se estrecha.
    await pumpQueue(
      tester,
      width: 1116,
      height: 620,
      dense: true,
      rows: <PayrollPersonRowVM>[
        row(
          1,
          status: PayrollRowStatus.paid,
          statusLabel: 'Pagado con una glosa deliberadamente larguísima',
          actionLabel: 'Ver pago',
          actionMode: PayrollRowActionMode.paidDetails,
        ),
      ],
    );

    final label = tester.widget<Text>(
      find.text('Pagado con una glosa deliberadamente larguísima'),
    );
    expect(label.maxLines, 1, reason: 'jamás dos líneas');
    expect(label.overflow, TextOverflow.ellipsis);

    final chip = find.byKey(
      const ValueKey<String>('payroll-paid-status-Persona de prueba 1'),
    );
    expect(
      tester.getSize(chip).width,
      lessThanOrEqualTo(decisionCellMaxWidth),
      reason: 'la celda se acota en 186 en vez de empujar la tabla',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('5c · el chip pagado comparte la misma envoltura de 28 y radio 8',
      (tester) async {
    await pumpQueue(
      tester,
      width: 1360,
      height: 620,
      dense: false,
      rows: <PayrollPersonRowVM>[
        row(
          1,
          status: PayrollRowStatus.paid,
          statusLabel: 'Pagado',
          actionLabel: 'Ver pago',
          actionMode: PayrollRowActionMode.paidDetails,
        ),
      ],
    );

    final chip = find.byKey(
      const ValueKey<String>('payroll-paid-status-Persona de prueba 1'),
    );
    final material = tester.widget<Material>(chip);
    expect(material.shape, isA<RoundedRectangleBorder>());
    expect(
      tester.getSize(chip).height,
      greaterThanOrEqualTo(decisionCellHeight),
    );
    expect(
      tester.getSize(chip).width,
      lessThanOrEqualTo(decisionCellMaxWidth),
      reason: '`7a` acota la celda en 186',
    );
    expect(tester.takeException(), isNull);
  });
  // `_totals()` emite DOS estados reales y excluyentes: borrador →
  // `showCommitAction: true` con `nextActionLabel` vacío; confirmada →
  // `showCommitAction: false` con acción-siguiente. Los dos se apilan; la
  // combinación «confirmar + siguiente» que probaba antes **el producto no la
  // puede producir**, así que medía un caso imposible.
  const soloConfirmar = PayrollWeekTotalsVM(
    title: 'Semana 27',
    equation: '',
    remaining: r'$225.000',
    showCommitAction: true,
    canConfirm: false,
    blockedReason: 'La semana está en borrador.',
    nextActionLabel: '',
  );

  const soloSiguiente = PayrollWeekTotalsVM(
    title: 'Semana 27',
    equation: '',
    remaining: r'$225.000',
    showCommitAction: false,
    canConfirm: true,
    blockedReason: '',
    nextActionLabel: 'Pagar a Lucas',
  );

  for (final (nombre, totals, key) in <(String, PayrollWeekTotalsVM, String)>[
    ('borrador · sólo Confirmar', soloConfirmar, 'payroll-confirm-week'),
    (
      'confirmada · sólo la siguiente',
      soloSiguiente,
      'payroll-next-week-action'
    ),
  ]) {
    testWidgets('5m · a 834 se apila la única acción visible — $nombre',
        (tester) async {
      // Nota 04 de `5m`, literal: «A 834 la barra monetaria se apila: cifra y
      // razón arriba, botón de 46 abajo. Nada de un botón de 34 perdido en una
      // esquina táctil.»
      //
      // El apilado ya estaba «implementado» en `PayrollMoneyBar` — que esta
      // superficie **nunca monta**, porque la cola tiene su propia barra. Por
      // eso el contrato mide la barra QUE SE PINTA, y con las combinaciones
      // que el host emite de verdad.
      await pumpQueue(
        tester,
        width: 834,
        height: 1112,
        dense: true,
        rows: <PayrollPersonRowVM>[row(0)],
        value: totals,
      );

      final cta = find.byKey(ValueKey<String>(key));
      expect(cta, findsOneWidget, reason: 'la acción del estado no se dibujó');
      final ctaRect = tester.getRect(cta);
      final figure = tester.getRect(find.text(r'$225.000'));

      expect(
        ctaRect.top,
        greaterThan(figure.bottom),
        reason: 'el botón sigue al lado de la cifra en vez de apilarse',
      );
      // Igualdad EXACTA contra el token, que es lo que impide que esto se
      // deslice: `>= 48` pasaría con 56 y con 80.
      //
      // El valor pasó de 46 a `touchMobile` (48) el 2026-08-02: `5m` dibuja 46,
      // pero `height` dimensiona el `InkWell` entero, así que 46 es un objetivo
      // táctil de 46 y `F-06 · TOUCH` pide 48 — la misma razón por la que `5l`
      // bajó su CTA de 50. La intención de la nota («nada de un botón de 34
      // perdido en una esquina táctil») se cumple mejor con 48, no peor.
      expect(
        ctaRect.height,
        PayrollTokens.touchMobile,
        reason:
            'el alto del CTA apilado dejó de ser el objetivo táctil de F-06',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('5m · a escritorio la barra NO se apila', (tester) async {
    // El apilado es de la banda compacta; a 1360 la fila es correcta.
    await pumpQueue(
      tester,
      width: 1360,
      height: 900,
      dense: false,
      rows: <PayrollPersonRowVM>[row(0)],
      value: soloConfirmar,
    );
    final cta = tester.getRect(
      find.byKey(const ValueKey<String>('payroll-confirm-week')),
    );
    final figure = tester.getRect(find.text(r'$225.000'));
    expect(cta.top, lessThan(figure.bottom));
    expect(tester.takeException(), isNull);
  });

  // `5n` · «Layout por ancho lógico»: ≥1200 ocho columnas · 1000–1199 seis ·
  // 900–999 cinco. Se prueba por el BORDE y desde la superficie real.
  //
  // Entre el ancho exterior y la tabla se pierden DOS descuentos, no uno: el
  // padding lateral de la superficie (32 px, 36 según el tier) y además los
  // 2 px del `Border` de la tarjeta. Si el eje volviera a ser el interior,
  // esos descuentos correrían el tramo y 1200 dejaría de bastar. Eso es
  // exactamente lo que pasaba antes de subir el owner a la superficie.
  testWidgets('5n · la escalera cambia en 1200 y en 1000 exactos',
      (tester) async {
    Future<void> at(double width) => pumpQueue(
          tester,
          width: width,
          height: 1112,
          dense: false,
          rows: <PayrollPersonRowVM>[row(0)],
        );

    await at(1200);
    expect(find.text('MÉTODO'), findsOneWidget,
        reason: '1200 es el piso de las ocho columnas: el padding y el borde '
            'no pueden desplazar el tramo');
    expect(find.text('PAGADO'), findsOneWidget);

    await at(1199);
    expect(find.text('MÉTODO'), findsNothing);
    expect(find.text('PAGADO'), findsNothing);
    expect(find.textContaining('ANTIC'), findsOneWidget,
        reason: '1199 es el tramo de seis columnas y conserva ANTICIPOS');

    await at(1000);
    expect(find.textContaining('ANTIC'), findsOneWidget,
        reason: '1000 es el piso del tramo de seis');

    await at(999);
    expect(find.textContaining('ANTIC'), findsNothing,
        reason: '999 cae al tramo de cinco columnas');
    expect(find.text('A PAGAR'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  // `5n` · `maxWidth 186/168/200`. El tope debe alcanzar TODAS las formas
  // reales del control: directa, pagada, menú y PASIVA.
  //
  // Los rótulos son deliberadamente LARGOS y el aserto es de IGUALDAD. Con
  // rótulos cortos y `<=`, la implementación anterior —que topaba todo en 186—
  // pasaba igual, y por eso el 168 se coló. Un control que no llega al tope no
  // prueba el tope: hay que empujarlo contra él.
  testWidgets('5n · el tope 186/168/200 se alcanza en las cuatro formas',
      (tester) async {
    const largo = 'Registrar pago por transferencia bancaria al día siguiente';

    Future<void> put(double viewport, PayrollPersonRowVM r) => pumpQueue(
          tester,
          width: viewport,
          height: 1112,
          dense: false,
          rows: <PayrollPersonRowVM>[r],
        );

    const tap = ValueKey<String>('payroll-row-action-tap-Persona de prueba 0');
    const paidKey = ValueKey<String>('payroll-paid-status-Persona de prueba 0');
    const menuKey = ValueKey<String>('payroll-method-menu-Persona de prueba 0');
    const passiveKey =
        ValueKey<String>('payroll-row-blocked-Persona de prueba 0');

    final direct = row(0, actionLabel: largo);
    final paid = row(
      0,
      status: PayrollRowStatus.paid,
      statusLabel: largo,
      actionLabel: largo,
      actionMode: PayrollRowActionMode.paidDetails,
    );
    final menu = row(
      0,
      statusLabel: largo,
      actionLabel: largo,
      actionMode: PayrollRowActionMode.menu,
    );
    final passive = row(
      0,
      statusLabel: largo,
      actionLabel: largo,
      actionMode: PayrollRowActionMode.none,
      blockedReason: 'Sus horas de esta semana todavía no están cerradas.',
    );

    // Los topes van como LITERALES, no como las constantes de producción.
    // Comparar contra `decisionCellMaxWidthDense` era una tautología: mutar la
    // constante movía los dos lados del aserto y la prueba seguía verde con
    // 186. Se comprobó por mutación el 2026-08-02.
    for (final tramo in const <List<Object>>[
      <Object>[1400.0, 186.0],
      <Object>[1100.0, 168.0],
    ]) {
      final width = tramo[0] as double;
      final cap = tramo[1] as double;

      await put(width, direct);
      expect(tester.getSize(find.byKey(tap)).width, cap,
          reason: 'directa a $width topa exactamente en $cap');
      await put(width, paid);
      expect(tester.getSize(find.byKey(paidKey)).width, cap,
          reason: 'la forma PAGADA usa el mismo tope, no el ancho de columna');
      await put(width, menu);
      expect(tester.getSize(find.byKey(menuKey)).width, cap,
          reason: 'el menú «Sin método» también topa en $cap');
      await put(width, passive);
      expect(tester.getSize(find.byKey(passiveKey)).width, cap,
          reason: 'la forma PASIVA no lleva píldora, pero lleva el mismo tope: '
              'si su texto se estira más, la columna muestra dos anchos');
    }

    // 834 · táctil → 200 exactos.
    await put(834, direct);
    expect(tester.getSize(find.byKey(tap)).width, 200.0,
        reason: 'en táctil el control mide 200, no «al menos 200»');

    expect(tester.takeException(), isNull);
  });
}
