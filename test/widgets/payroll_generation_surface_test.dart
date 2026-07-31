import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_generation_surface.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  final initialWeek = PayrollGenerationWeek.containing(
    DateTime(2026, 7, 29),
  );

  PayrollGenerationPreview previewFor(PayrollGenerationWeek week) {
    return PayrollGenerationPreview(
      week: week,
      totalAmount: 266000,
      sourceSnapshotLabel: 'Asistencias cerradas · actualización 29/07 10:42',
      workers: const <PayrollGenerationWorkerLine>[
        PayrollGenerationWorkerLine(
          workerId: 'lucas',
          name: 'Lucas Pacheco',
          initials: 'LP',
          hours: 36.5,
          overtimeHours: 2,
          rateAmount: 3500,
          overtimeRateAmount: 5250,
          totalAmount: 138250,
        ),
        PayrollGenerationWorkerLine(
          workerId: 'guillermo',
          name: 'Rodrigo Guillermo Nieto',
          initials: 'RG',
          hours: 0,
          rateAmount: 4000,
          totalAmount: 0,
        ),
        PayrollGenerationWorkerLine(
          workerId: 'vicente',
          name: 'Vicente Díaz',
          initials: 'VD',
          hours: 36.5,
          rateAmount: 3500,
          totalAmount: 127750,
        ),
      ],
    );
  }

  Future<void> pumpSurface(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
    PayrollGenerationPreviewLoader? onGeneratePreview,
    PayrollGenerationDraftSaver? onSaveDraft,
    String Function()? createOperationKey,
    FutureOr<void> Function()? onClose,
    ValueChanged<PayrollGenerationWeek>? onWeekChanged,
    ValueChanged<PayrollGenerationSaveResult>? onOpenSavedDraft,
    PayrollGenerationDesktopPresentation desktopPresentation =
        PayrollGenerationDesktopPresentation.sideSheet,
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: Scaffold(
          body: PayrollGenerationSurface(
            key: ValueKey<double>(size.width),
            initialWeek: initialWeek,
            now: () => DateTime(2026, 7, 29),
            desktopPresentation: desktopPresentation,
            onGeneratePreview:
                onGeneratePreview ?? (week) async => previewFor(week),
            createOperationKey: createOperationKey ?? () => 'op-payroll-1',
            onSaveDraft: onSaveDraft ??
                (request) async => const PayrollGenerationSaveResult(
                      draftId: 'draft-1',
                    ),
            onClose: onClose ?? () {},
            onWeekChanged: onWeekChanged,
            onOpenSavedDraft: onOpenSavedDraft,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
      'desktop genera una lectura de Asistencias con cero horas, total y personas',
      (tester) async {
    PayrollGenerationWeek? requestedWeek;
    await pumpSurface(
      tester,
      onGeneratePreview: (week) async {
        requestedWeek = week;
        return previewFor(week);
      },
    );

    final sideSheet = find.byKey(
      const ValueKey('payroll-generation-side-sheet-host'),
    );
    expect(sideSheet, findsOneWidget);
    expect(tester.getSize(sideSheet).width, 760);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('payroll-generation-primary-action')),
    );
    await tester.pumpAndSettle();

    expect(requestedWeek, initialWeek);
    expect(
      find.byKey(const ValueKey('payroll-generation-desktop-table')),
      findsOneWidget,
    );
    expect(find.text('3 trabajadores · 2 con monto'), findsOneWidget);
    expect(find.text(r'$266.000'), findsOneWidget);
    expect(find.text('36,5 h + 2 h HE'), findsOneWidget);
    expect(find.text(r'$3.500/h + $5.250/HE'), findsOneWidget);
    expect(find.text('Rodrigo Guillermo Nieto'), findsOneWidget);
    expect(find.text('Sin horas cerradas'), findsOneWidget);
    expect(find.text('0 h'), findsOneWidget);
    expect(find.text(r'$4.000/h'), findsOneWidget);
    expect(find.text(r'$0'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '390px ocupa alto completo, conserva targets de 48px y loading visible',
      (tester) async {
    final completion = Completer<PayrollGenerationPreview>();
    PayrollGenerationWeek? changedWeek;
    PayrollGenerationWeek? requestedWeek;
    await pumpSurface(
      tester,
      size: const Size(390, 844),
      onWeekChanged: (week) => changedWeek = week,
      onGeneratePreview: (week) {
        requestedWeek = week;
        return completion.future;
      },
    );

    final panel = find.byKey(const ValueKey('payroll-generation-panel'));
    final previous = find.byKey(
      const ValueKey('payroll-generation-previous-week'),
    );
    final next = find.byKey(
      const ValueKey('payroll-generation-next-week'),
    );
    final close = find.byKey(const ValueKey('payroll-generation-close'));
    final primary = find.byKey(
      const ValueKey('payroll-generation-primary-action'),
    );

    expect(tester.getSize(panel), const Size(390, 844));
    for (final target in <Finder>[previous, next, close, primary]) {
      expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(target).width, greaterThanOrEqualTo(48));
    }

    await tester.tap(previous);
    await tester.pumpAndSettle();
    expect(changedWeek, initialWeek.shifted(-1));

    await tester.tap(
      find.byKey(const ValueKey('payroll-generation-current-week')),
    );
    await tester.pumpAndSettle();
    expect(changedWeek, initialWeek);

    await tester.tap(primary);
    await tester.pump();

    expect(requestedWeek, initialWeek);
    expect(
      find.byKey(const ValueKey('payroll-generation-loading')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('payroll-generation-source')),
      findsOneWidget,
    );

    completion.complete(previewFor(initialWeek));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('payroll-generation-compact-list')),
      findsOneWidget,
    );
    expect(
      find.text('Sin horas cerradas · se incluye como \$0'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('error, vacío y éxito son estados distintos y recuperables',
      (tester) async {
    var attempts = 0;
    await pumpSurface(
      tester,
      size: const Size(600, 900),
      onGeneratePreview: (week) async {
        attempts += 1;
        if (attempts == 1) throw StateError('detalle técnico no visible');
        if (attempts == 2) {
          return PayrollGenerationPreview(
            week: week,
            workers: const <PayrollGenerationWorkerLine>[],
            totalAmount: 0,
            sourceSnapshotLabel: 'Sin cierre',
          );
        }
        return previewFor(week);
      },
    );

    final primary = find.byKey(
      const ValueKey('payroll-generation-primary-action'),
    );

    await tester.tap(primary);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('payroll-generation-error')),
      findsOneWidget,
    );
    expect(find.textContaining('detalle técnico'), findsNothing);
    expect(tester.takeException(), isNull, reason: 'error state must fit');

    await tester.tap(primary);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('payroll-generation-empty')),
      findsOneWidget,
    );
    expect(find.textContaining('No hay un cierre disponible'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'empty state must fit');

    await tester.tap(primary);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('payroll-generation-success')),
      findsOneWidget,
    );
    expect(attempts, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reintento de guardado conserva una sola clave idempotente',
      (tester) async {
    var keyCreations = 0;
    final requests = <PayrollGenerationSaveRequest>[];
    final firstSave = Completer<PayrollGenerationSaveResult>();
    var saves = 0;
    await pumpSurface(
      tester,
      createOperationKey: () {
        keyCreations += 1;
        return 'operation-stable';
      },
      onSaveDraft: (request) {
        requests.add(request);
        saves += 1;
        if (saves == 1) return firstSave.future;
        return Future<PayrollGenerationSaveResult>.value(
          const PayrollGenerationSaveResult(
            draftId: 'draft-1',
            replayed: true,
          ),
        );
      },
    );

    final primary = find.byKey(
      const ValueKey('payroll-generation-primary-action'),
    );
    await tester.tap(primary);
    await tester.pumpAndSettle();

    await tester.tap(primary);
    await tester.tap(primary, warnIfMissed: false);
    await tester.pump();
    expect(saves, 1, reason: 'Un guardado en vuelo no acepta doble envío.');

    firstSave.completeError(StateError('fallo transitorio'));
    await tester.pumpAndSettle();
    expect(find.textContaining('misma operación'), findsOneWidget);

    await tester.tap(primary);
    await tester.pumpAndSettle();

    expect(saves, 2);
    expect(keyCreations, 1);
    expect(
      requests.map((request) => request.operationKey),
      everyElement('operation-stable'),
    );
    expect(find.textContaining('sin duplicarlo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('un borrador guardado ofrece handoff explícito a Nóminas',
      (tester) async {
    PayrollGenerationSaveResult? opened;
    await pumpSurface(
      tester,
      onOpenSavedDraft: (result) => opened = result,
    );

    final primary = find.byKey(
      const ValueKey('payroll-generation-primary-action'),
    );
    await tester.tap(primary);
    await tester.pumpAndSettle();
    await tester.tap(primary);
    await tester.pumpAndSettle();

    expect(find.text('Revisar en Nóminas'), findsOneWidget);
    await tester.tap(primary);
    await tester.pumpAndSettle();
    expect(opened?.draftId, 'draft-1');
  });

  testWidgets('cerrar con preview exige descarte; sin confirmar conserva tarea',
      (tester) async {
    var closes = 0;
    await pumpSurface(
      tester,
      onClose: () => closes += 1,
    );

    await tester.tap(
      find.byKey(const ValueKey('payroll-generation-primary-action')),
    );
    await tester.pumpAndSettle();

    final close = find.byKey(const ValueKey('payroll-generation-close'));
    await tester.tap(close);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('payroll-generation-discard-dialog')),
      findsOneWidget,
    );
    expect(closes, 0);

    await tester.tap(
      find.byKey(const ValueKey('payroll-generation-keep-reviewing')),
    );
    await tester.pumpAndSettle();
    expect(closes, 0);
    expect(
      find.byKey(const ValueKey('payroll-generation-success')),
      findsOneWidget,
    );

    await tester.tap(close);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('payroll-generation-confirm-discard')),
    );
    await tester.pumpAndSettle();

    expect(closes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop dialog queda acotado sin cambiar el contrato',
      (tester) async {
    await pumpSurface(
      tester,
      desktopPresentation: PayrollGenerationDesktopPresentation.dialog,
    );

    final host = find.byKey(
      const ValueKey('payroll-generation-dialog-host'),
    );
    expect(tester.getSize(host), const Size(720, 820));
    expect(
      find.byKey(const ValueKey('payroll-generation-side-sheet-host')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('599/600 y 899/900 recomponen sin overflow a texto 1.3',
      (tester) async {
    for (final width in <double>[599, 600, 899, 900]) {
      await pumpSurface(
        tester,
        size: Size(width, 900),
        textScaler: const TextScaler.linear(1.3),
      );
      await tester.tap(
        find.byKey(const ValueKey('payroll-generation-primary-action')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('payroll-generation-success')),
        findsOneWidget,
        reason: 'El preview debe seguir visible a ${width}px.',
      );
      expect(
        find.byKey(const ValueKey('payroll-generation-side-sheet-host')),
        width >= 900 ? findsOneWidget : findsNothing,
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'La superficie no debe desbordar a ${width}px.',
      );
    }
  });
}
