import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/hr/models/payroll_voucher.dart';
import 'package:vinabike_erp/modules/hr/payroll/payroll_redesign_page.dart';
import 'package:vinabike_erp/modules/hr/payroll/theme/payroll_tokens.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/vb_skeleton.dart';

/// **5k · esqueleto de carga con la silueta real.**
///
/// El defecto que cierra no es estético: con un spinner centrado la pantalla
/// **no reserva nada**, así que al llegar los datos aparecen de golpe el módulo
/// de comando, la banda de semanas, la tabla y la barra de dinero, y el control
/// de decisión aterriza en un sitio distinto del que el operador estaba
/// mirando. Por eso lo que se prueba acá es la **posición**, no el adorno.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  PayrollVoucher voucher() {
    final lines = <PayrollVoucherLine>[
      for (var i = 1; i <= 3; i++)
        PayrollVoucherLine(
          id: 'line-$i',
          voucherId: 'voucher-1',
          employeeId: 'employee-$i',
          employeeName: 'Persona $i',
          workedHours: 38.5,
          hourlyRate: 4490,
          totalAmount: 172875,
          paymentMethodId: 'method-transfer',
          cashPaid: 0,
          advancesApplied: 0,
          settledAmount: 0,
          balance: 172875,
        ),
    ];
    return PayrollVoucher(
      id: 'voucher-1',
      tenantId: 'tenant-1',
      voucherNumber: 'NOM-06',
      periodStart: DateTime(2026, 7, 6),
      periodEnd: DateTime(2026, 7, 12),
      totalHours: lines.fold(0, (s, l) => s + l.totalHours),
      totalAmount: lines.fold(0, (s, l) => s + l.totalAmount),
      employeeCount: lines.length,
      status: PayrollVoucherStatus.confirmed,
      createdAt: DateTime(2026, 7, 6),
      updatedAt: DateTime(2026, 7, 6),
      reconciliationVersion: 7,
      lines: lines,
    );
  }

  /// La misma semana, ya pagada: `_load` la manda a Historial.
  PayrollVoucher paidVoucher() {
    final base = voucher();
    return PayrollVoucher(
      id: base.id,
      tenantId: base.tenantId,
      voucherNumber: base.voucherNumber,
      periodStart: base.periodStart,
      periodEnd: base.periodEnd,
      totalHours: base.totalHours,
      totalAmount: base.totalAmount,
      employeeCount: base.employeeCount,
      status: PayrollVoucherStatus.paid,
      createdAt: base.createdAt,
      updatedAt: base.updatedAt,
      reconciliationVersion: base.reconciliationVersion,
      lines: base.lines,
    );
  }

  PayrollRedesignActions actionsHeldBy(Completer<PayrollRedesignData> gate) {
    return PayrollRedesignActions(
      // Esta suite mide continuidad geométrica, no disponibilidad de
      // contratos de release. Opta explícitamente por las dos capacidades para
      // que el CTA real que compara con el esqueleto exista por una razón
      // declarada, sin depender del default de producción (fail-closed).
      load: () async => (await gate.future).copyWith(
        releaseCapabilities: const PayrollReleaseCapabilities(
          employeePaymentMethodCommand: true,
          structuredAdvanceAudit: true,
        ),
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
  }

  Future<void> pump(
    WidgetTester tester,
    PayrollRedesignActions actions, {
    required Size size,
    Brightness brightness = Brightness.light,
    AppearancePreset? preset,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        theme: AppTheme.resolve(
          preset: preset ?? AppearancePresets.all.first,
          brightness: brightness,
        ),
        home: Builder(
          // `MediaQueryData(disableAnimations: true)` a secas **borra el
          // tamaño**, así que la página se creía compacta a 1440 y la prueba
          // medía otra composición sin decirlo. Se copia la data ambiente.
          builder: (context) => MediaQuery(
            // Sin esto, el barrido de `X-01` deja un ticker vivo y
            // `pumpAndSettle` no volvería nunca con el esqueleto en pantalla.
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: Scaffold(body: PayrollRedesignPage(actions: actions)),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  final skeleton = find.byKey(const ValueKey('payroll-loading-skeleton'));
  final skeletonMoneyBar =
      find.byKey(const ValueKey('payroll-loading-money-bar'));
  final skeletonAction =
      find.byKey(const ValueKey('payroll-loading-primary-action'));

  testWidgets('la carga dibuja la silueta, no un spinner', (tester) async {
    final gate = Completer<PayrollRedesignData>();
    await pump(tester, actionsHeldBy(gate), size: const Size(1440, 900));

    expect(skeleton, findsOneWidget);
    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: '5k: el spinner es justo lo que hace saltar el control',
    );
    expect(find.byType(VbSkeleton), findsWidgets,
        reason: 'el relleno sale de X-01, no de un widget local');
    // Las bandas de la superficie real están reservadas, incluidas LAS DOS
    // franjas de cabecera de la tabla: título y rótulos de columna son dos
    // owners distintos con dos tokens distintos.
    for (final key in const <String>[
      'payroll-loading-command-band',
      'payroll-loading-week-strip',
      'payroll-loading-table',
      'payroll-loading-table-title',
      'payroll-loading-table-columns',
      'payroll-loading-money-bar',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }

    gate.complete(PayrollRedesignData(vouchers: <PayrollVoucher>[voucher()]));
    await tester.pumpAndSettle();
    expect(skeleton, findsNothing,
        reason: 'la silueta desaparece cuando llegan los datos');
  });

  testWidgets(
      'escritorio · el control de decisión NO salta al llegar los datos',
      (tester) async {
    final gate = Completer<PayrollRedesignData>();
    await pump(tester, actionsHeldBy(gate), size: const Size(1440, 900));

    final ghostBar = tester.getRect(skeletonMoneyBar);
    final ghostAction = tester.getRect(skeletonAction);
    // `moneyBarH` es el alto del CONTENIDO; el borde superior de 1 se le suma,
    // igual que en la barra real y que en las bandas de Design (`6a` declara
    // `height:56px` **más** `border-bottom:1px`, y su suma `47 + 56 + 48` no
    // cuenta bordes). El 1 es el ancho por defecto de `BorderSide`, no una
    // holgura: sigue siendo igualdad exacta, y con el `moneyBarH` a la vista
    // para que un cambio del token siga rompiendo esto.
    const barTopBorder = 1.0;
    expect(ghostBar.height, PayrollTokens.moneyBarH + barTopBorder);

    gate.complete(PayrollRedesignData(vouchers: <PayrollVoucher>[voucher()]));
    await tester.pumpAndSettle();

    final realBar = tester.getRect(
      find.byKey(const ValueKey<String>('payroll-money-bar')),
    );
    // La barra muestra `Confirmar semana` o la acción-siguiente según el estado
    // de la semana; para «no saltar» da igual cuál sea, importa dónde cae.
    final confirm = find.byKey(const ValueKey<String>('payroll-confirm-week'));
    final next = find.byKey(const ValueKey<String>('payroll-next-week-action'));
    expect(confirm.evaluate().isNotEmpty || next.evaluate().isNotEmpty, isTrue,
        reason: 'la barra de dinero siempre lleva una acción primaria');
    final realAction =
        tester.getRect(confirm.evaluate().isNotEmpty ? confirm : next);

    expect(realBar.top, ghostBar.top,
        reason: 'la barra de dinero cambia de altura entre carga y datos');
    expect(realBar.height, ghostBar.height);
    expect(
      realAction.center.dy,
      ghostAction.center.dy,
      reason: 'el CTA aterriza a otra altura de la que ocupaba la silueta',
    );
  });

  testWidgets('compacto · el CTA reservado mide TOUCH y cae en su sitio',
      (tester) async {
    final gate = Completer<PayrollRedesignData>();
    await pump(tester, actionsHeldBy(gate), size: const Size(390, 844));

    expect(skeleton, findsOneWidget);
    final ghostAction = tester.getRect(skeletonAction);
    expect(
      ghostAction.height,
      PayrollTokens.touchMobile,
      reason: 'el control táctil se reserva con su token, no con un plausible',
    );
    final ghostBar = tester.getRect(skeletonMoneyBar);

    gate.complete(PayrollRedesignData(vouchers: <PayrollVoucher>[voucher()]));
    await tester.pumpAndSettle();

    final realAction = tester.getRect(
      find.byKey(const ValueKey('payroll-mobile-primary-action')),
    );
    final realBar = tester.getRect(
      find.byKey(const ValueKey<String>('payroll-mobile-money-bar')),
    );
    expect(realBar.top, ghostBar.top);
    expect(realAction.height, ghostAction.height);
    expect(realAction.center.dy, ghostAction.center.dy);
  });

  testWidgets(
      'la tabla reserva SUS DOS franjas, y la primera fila cae donde caerá',
      (tester) async {
    // La tabla real tiene título (`tableHeaderH`) y rótulos de columna
    // (`tableColsH`), dos owners con dos tokens. Reservando sólo el primero, la
    // primera fila quedaba 30 px más arriba de donde iba a aterrizar.
    final gate = Completer<PayrollRedesignData>();
    await pump(tester, actionsHeldBy(gate), size: const Size(1440, 900));

    final title = tester
        .getRect(find.byKey(const ValueKey('payroll-loading-table-title')));
    final columns = tester
        .getRect(find.byKey(const ValueKey('payroll-loading-table-columns')));
    expect(title.height, PayrollTokens.tableHeaderH);
    expect(columns.height, PayrollTokens.tableColsH);
    expect(columns.top, title.bottom,
        reason: 'las dos franjas van pegadas, en ese orden');
    gate.complete(PayrollRedesignData(vouchers: <PayrollVoucher>[voucher()]));
    await tester.pumpAndSettle();

    final realTitle = tester
        .getRect(find.byKey(const ValueKey<String>('payroll-table-title')));
    final realColumns = tester
        .getRect(find.byKey(const ValueKey<String>('payroll-table-columns')));

    // Los dos owners existen y miden lo suyo en la tabla real: es lo que el
    // esqueleto tiene que reservar, y reservar sólo el primero dejaba la
    // primera fila 30 px arriba.
    expect(realTitle.height, PayrollTokens.tableHeaderH);
    expect(realColumns.height, PayrollTokens.tableColsH);
    expect(realColumns.top, realTitle.bottom);
    expect(realTitle.left, title.left);
    expect(realTitle.right, title.right);

    // **Lo que NO se puede prometer, y se declara:** la tira de semanas de
    // arriba es de alto variable —la tarjeta crece con la barra de avance y la
    // nota al pie, que dependen del dato— así que la tabla no puede aterrizar
    // en el píxel exacto que insinuó la silueta. `PayrollTokens.queueStripH`
    // dice 76 y la tira real mide más con datos con avance. Ver §4.15 del
    // handoff: la corrección nace en 5a (acotar la tira), no acá.
    final drift = (realTitle.top - title.top).abs();
    expect(
      drift,
      lessThan(PayrollTokens.queueStripH),
      reason: 'la deriva de la tabla no puede llegar a una tira entera',
    );
  });

  test('las filas insinuadas salen del alto disponible, sin techo inventado',
      () {
    // `5k` dibuja dos filas de forma ilustrativa y el panel `X-01` de la guía
    // se corta: **no hay número publicado**. Y un techo sacado de las semanas
    // que había hoy en producción tampoco sirve — la plantilla del taller
    // cambia y el número queda congelado sin dueño (corrección de Codex,
    // 2026-08-01, que deroga el `maxGhostRows = 6`).
    const bands = PayrollTokens.tableHeaderH + PayrollTokens.tableColsH;

    // Sólo filas completas: media fila se leería como una fila cortada.
    expect(PayrollLoadingSkeletonMetrics.ghostRowsFor(bands + 48 * 5), 5);
    expect(PayrollLoadingSkeletonMetrics.ghostRowsFor(bands + 48 * 5 + 47), 5,
        reason: 'una fila a medias no se insinúa');

    // Una ventana alta ESCALA, no deja un hueco artificial.
    for (final rows in const <int>[8, 12, 20, 40]) {
      expect(
        PayrollLoadingSkeletonMetrics.ghostRowsFor(bands + 48.0 * rows),
        rows,
        reason: 'con sitio para $rows filas se insinúan $rows: un esqueleto no '
            'promete una cantidad, ocupa el sitio que hay',
      );
    }

    // El piso estructural: sin filas, lo dibujado no se lee como tabla.
    expect(PayrollLoadingSkeletonMetrics.ghostRowsFor(10), 1);
    expect(PayrollLoadingSkeletonMetrics.ghostRowsFor(bands), 1);
  });

  testWidgets(
      'limitación declarada: si la carga aterriza en Historial, la silueta era la de Semanas',
      (tester) async {
    // `initialVoucherId` puede venir de Asistencias apuntando a una semana ya
    // pagada; `_load` la manda a Historial. El scope de llegada lo decide el
    // dato, así que la silueta no puede acertarlo antes de cargar. Se prueba el
    // caso para que nadie lo lea como un acierto garantizado.
    final gate = Completer<PayrollRedesignData>();
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        theme: AppTheme.resolve(
          preset: AppearancePresets.all.first,
          brightness: Brightness.light,
        ),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: Scaffold(
              body: PayrollRedesignPage(
                actions: actionsHeldBy(gate),
                initialVoucherId: 'voucher-1',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Mientras carga, la silueta insinúa la cola: tabla y barra de dinero.
    expect(find.byKey(const ValueKey('payroll-loading-table')), findsOneWidget);

    // Y el dato manda a Historial, porque esa semana ya está pagada.
    gate.complete(
      PayrollRedesignData(
        vouchers: <PayrollVoucher>[paidVoucher()],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('payroll-loading-table')), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('payroll-money-bar')),
      findsNothing,
      reason:
          'Historial no tiene barra de dinero: la silueta anticipó otra cosa, '
          'y eso es una limitación declarada, no un acierto',
    );
  });

  testWidgets(
      'el control insinuado se ve sobre el lienzo en 6 presets × 2 brillos',
      (tester) async {
    // Hallazgo de la captura en vivo a 834 en OSCURO: el fantasma pintaba sólo
    // `neutralSoft` y desaparecía sobre el lienzo — la tira de semanas salía
    // vacía donde debía haber tres pastillas. Un esqueleto invisible es un
    // esqueleto que no reserva nada, que es el defecto entero de 5k.
    for (final preset in AppearancePresets.all) {
      for (final brightness in Brightness.values) {
        final cell = '${preset.code}/${brightness.name}';
        final gate = Completer<PayrollRedesignData>();
        await pump(
          tester,
          actionsHeldBy(gate),
          size: const Size(390, 844),
          preset: preset,
          brightness: brightness,
        );
        final box = tester.widget<DecoratedBox>(
          find.byKey(const ValueKey('payroll-loading-ghost-surface')),
        );
        final decoration = box.decoration as BoxDecoration;
        expect(decoration.border, isNotNull,
            reason: '$cell: sin borde el fantasma se pierde en el lienzo');
        expect(
          decoration.color,
          isNot(Theme.of(tester.element(skeleton)).scaffoldBackgroundColor),
          reason: '$cell: el relleno del fantasma no puede ser el lienzo',
        );
        gate.complete(
          PayrollRedesignData(vouchers: <PayrollVoucher>[voucher()]),
        );
        await tester.pumpAndSettle();
      }
    }
  });

  testWidgets(
      'el vacío distingue la ÚNICA causa que el modelo garantiza, y no inventa las otras',
      (tester) async {
    // Sin señal canónica del período en curso, «todo pagado» y «semana sin
    // horas cerradas» **no son derivables**: un comprobante histórico pagado no
    // dice nada del ciclo actual, y que no haya voucher abierto no prueba que
    // Asistencias no cerrara nada. Lo que sí garantiza el esquema
    // (verificado contra producción el 2026-08-01: `employees.status` es
    // NOT NULL, default `active`, CHECK
    // `active|inactive|on_leave|terminated`) es si hay alguien contratado.
    Future<void> mount(List<Map<String, dynamic>> employees) async {
      final gate = Completer<PayrollRedesignData>();
      await pump(tester, actionsHeldBy(gate), size: const Size(1440, 900));
      gate.complete(
        PayrollRedesignData(
          vouchers: const <PayrollVoucher>[],
          employees: employees,
        ),
      );
      await tester.pumpAndSettle();
    }

    // Nadie contratado: el CTA a Asistencias mandaba a cerrar horas de gente
    // que no existe. La salida correcta es Trabajadores.
    await mount(const <Map<String, dynamic>>[
      <String, dynamic>{'id': 'e1', 'status': 'terminated'},
      <String, dynamic>{'id': 'e2', 'status': 'inactive'},
    ]);
    expect(
        find.byKey(const ValueKey('payroll-empty-no-workers')), findsOneWidget);
    expect(find.text('Aún no hay nadie contratado'), findsOneWidget);
    expect(find.byKey(const ValueKey('payroll-empty-open-employees')),
        findsOneWidget);

    // Con licencia SIGUE contratado: no es el vacío de primera vez, aunque
    // tampoco pueda recibir un anticipo. Son dos preguntas distintas.
    await mount(const <Map<String, dynamic>>[
      <String, dynamic>{'id': 'e1', 'status': 'on_leave'},
    ]);
    expect(find.byKey(const ValueKey('payroll-empty-no-open-weeks')),
        findsOneWidget);

    // Y el vacío general describe el mecanismo sin afirmar la causa.
    await mount(const <Map<String, dynamic>>[
      <String, dynamic>{'id': 'e1', 'status': 'active'},
    ]);
    expect(find.text('No hay semanas por resolver'), findsOneWidget);
    expect(
      find.textContaining('Cuando cierres horas'),
      findsNothing,
      reason: 'afirmaba que el operador no cerró horas, y eso no se sabe',
    );
    expect(find.textContaining('Todo pagado'), findsNothing,
        reason: 'no hay señal del período actual que lo respalde');
  });

  testWidgets('la carga se anuncia una vez, y la silueta no habla',
      (tester) async {
    final handle = tester.ensureSemantics();
    final gate = Completer<PayrollRedesignData>();
    await pump(tester, actionsHeldBy(gate), size: const Size(1440, 900));

    expect(
      find.bySemanticsLabel('Cargando las semanas de nómina'),
      findsOneWidget,
      reason: 'sin anuncio, un lector de pantalla no dice nada mientras carga',
    );
    final node = tester.getSemantics(
      find.bySemanticsLabel('Cargando las semanas de nómina'),
    );
    expect(node.childrenCount, 0,
        reason: 'el relleno del esqueleto es mudo: no aporta nodos');

    gate.complete(PayrollRedesignData(vouchers: <PayrollVoucher>[voucher()]));
    await tester.pumpAndSettle();
    expect(
        find.bySemanticsLabel('Cargando las semanas de nómina'), findsNothing);
    handle.dispose();
  });

  testWidgets('la silueta se sostiene en 6 presets × 2 brillos, sin overflow',
      (tester) async {
    for (final preset in AppearancePresets.all) {
      for (final brightness in Brightness.values) {
        for (final size in const <Size>[
          Size(1440, 900),
          Size(834, 1112),
          Size(390, 844),
        ]) {
          final gate = Completer<PayrollRedesignData>();
          await pump(
            tester,
            actionsHeldBy(gate),
            size: size,
            preset: preset,
            brightness: brightness,
          );
          expect(
            skeleton,
            findsOneWidget,
            reason: '${preset.code}/${brightness.name}/${size.width}',
          );
          expect(
            tester.takeException(),
            isNull,
            reason:
                'overflow en ${preset.code}/${brightness.name}/${size.width}',
          );
          gate.complete(
            PayrollRedesignData(vouchers: <PayrollVoucher>[voucher()]),
          );
          await tester.pumpAndSettle();
        }
      }
    }
  });
}
