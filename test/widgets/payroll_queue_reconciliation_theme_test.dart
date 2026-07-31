import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_queue_surface.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_reconciliation_surface.dart';
import 'package:vinabike_erp/modules/hr/payroll/theme/payroll_tokens.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/themes/vinabike_theme_roles.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('queue visuals follow light and dark appearance presets',
      (tester) async {
    final renderedSurfaces = <Color>[];

    for (final config in const <(AppearancePreset, Brightness)>[
      (AppearancePresets.vinabike, Brightness.light),
      (AppearancePresets.pacific, Brightness.dark),
    ]) {
      final theme = AppTheme.resolve(
        preset: config.$1,
        brightness: config.$2,
      );

      await _pumpQueue(tester, theme);

      final cardInk = tester.widget<Ink>(
        find
            .ancestor(
              of: find.byKey(
                const ValueKey<String>('payroll-week-card-Semana 28'),
              ),
              matching: find.byType(Ink),
            )
            .first,
      );
      final cardDecoration = cardInk.decoration! as BoxDecoration;
      final weekStatus = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('ABIERTA'),
              matching: find.byType(Container),
            )
            .first,
      );
      final weekStatusDecoration = weekStatus.decoration! as BoxDecoration;
      // The accent CTA is owned by PayrollAccentAction; its Material is the
      // first descendant under the keyed subtree.
      final paymentAction = tester.widget<Material>(
        find
            .descendant(
              of: find.byKey(
                const ValueKey<String>('payroll-row-action-Persona temática'),
              ),
              matching: find.byType(Material),
            )
            .first,
      );
      final paidStatus = tester.widget<Material>(
        find.byKey(
          const ValueKey<String>('payroll-paid-status-Persona pagada'),
        ),
      );

      expect(cardDecoration.color, theme.colorScheme.surface);
      expect(
        weekStatusDecoration.color,
        theme.extension<VinabikeThemeRoles>()!.warning.container,
      );
      expect(paymentAction.color, theme.colorScheme.primary);
      expect(
        paidStatus.color,
        theme.extension<VinabikeThemeRoles>()!.success.container,
      );
      expect(tester.takeException(), isNull);
      renderedSurfaces.add(cardDecoration.color!);
    }

    expect(renderedSurfaces[0], isNot(renderedSurfaces[1]));
    expect(renderedSurfaces[1], isNot(Colors.black));
  });

  testWidgets(
      'reconciliation inherits the complete app theme without an island',
      (tester) async {
    for (final config in const <(AppearancePreset, Brightness)>[
      (AppearancePresets.vinabike, Brightness.light),
      (AppearancePresets.pacific, Brightness.dark),
    ]) {
      final theme = AppTheme.resolve(
        preset: config.$1,
        brightness: config.$2,
      );
      final roles = theme.extension<VinabikeThemeRoles>()!;

      await _pumpReconciliation(tester, theme);

      final surface = find.byType(PayrollReconciliationSurface);
      final canvas = tester.widget<ColoredBox>(
        find.descendant(of: surface, matching: find.byType(ColoredBox)).first,
      );
      final header = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(
                const ValueKey<String>('reconciliation-workflow-header'),
              ),
              matching: find.byType(Container),
            )
            .first,
      );
      final currentStep = tester.widget<Material>(
        find
            .ancestor(
              of: find.byKey(
                const ValueKey<String>('reconciliation-step-2'),
              ),
              matching: find.byType(Material),
            )
            .first,
      );

      expect(canvas.color, theme.scaffoldBackgroundColor);
      expect(header.color, roles.shell.canvas);
      expect(currentStep.color, theme.colorScheme.primaryContainer);
      expect(tester.takeException(), isNull);
    }
  });
}

Future<void> _pumpQueue(WidgetTester tester, ThemeData theme) async {
  tester.view.physicalSize = const Size(1000, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: PayrollQueueSurface(
          weeks: <PayrollWeekCardVM>[
            PayrollWeekCardVM(
              name: 'Semana 28',
              range: '07 – 13 jul',
              amountLabel: r'$267.875',
              amountCaption: 'por pagar',
              statusLabel: 'ABIERTA',
              tone: PayrollStateTone.warning,
              selected: true,
              onTap: () {},
            ),
          ],
          rows: <PayrollPersonRowVM>[
            PayrollPersonRowVM(
              name: 'Persona temática',
              initials: 'PT',
              avatarColor: theme.colorScheme.secondary,
              method: 'Transferencia',
              methodIsCash: false,
              earned: r'$172.875',
              advances: '—',
              newMoney: r'$172.875',
              paid: '—',
              status: PayrollRowStatus.pendingTransfer,
              statusLabel: 'Por pagar',
              statusMeta: '',
              actionLabel: 'Pagar',
              actionMode: PayrollRowActionMode.direct,
              hours: '38,5 h',
              rate: r'$4.490 / h',
              paymentsSummary: 'Sin pagos registrados',
              expanded: false,
              onToggle: () {},
              onAction: () {},
            ),
            PayrollPersonRowVM(
              name: 'Persona pagada',
              initials: 'PP',
              avatarColor: theme.colorScheme.tertiary,
              method: 'Transferencia',
              methodIsCash: false,
              earned: r'$90.000',
              advances: '—',
              newMoney: r'$0',
              paid: r'$90.000',
              status: PayrollRowStatus.paid,
              statusLabel: 'Pagado',
              statusMeta: '',
              actionLabel: 'Ver pago',
              actionMode: PayrollRowActionMode.paidDetails,
              hours: '20 h',
              rate: r'$4.500 / h',
              paymentsSummary: r'Pago registrado $90.000',
              expanded: false,
              onToggle: () {},
              onAction: () {},
            ),
          ],
          totals: const PayrollWeekTotalsVM(
            title: 'Semana 28 · 07 – 13 jul',
            equation: r'total $172.875 − anticipos $0 − pagado $0',
            remaining: r'$172.875',
            showCommitAction: false,
            canConfirm: false,
            blockedReason: '',
            nextActionLabel: '',
          ),
          onOpenAttendance: () {},
          onConfirmWeek: () {},
          onNextAction: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpReconciliation(
  WidgetTester tester,
  ThemeData theme,
) async {
  tester.view.physicalSize = const Size(1000, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: PayrollReconciliationSurface(
          title: 'Conciliar nóminas',
          metadata: 'cartola.pdf',
          steps: const <ReconStep>[
            ReconStep(
              name: 'Documento',
              compactName: 'Doc.',
              meta: 'Listo',
              state: ReconStepState.done,
            ),
            ReconStep(
              name: 'Revisión',
              compactName: 'Revisar',
              meta: 'Actual',
              state: ReconStepState.current,
            ),
            ReconStep(
              name: 'Efectivo',
              compactName: 'Efectivo',
              meta: '',
              state: ReconStepState.next,
            ),
            ReconStep(
              name: 'Aplicar',
              compactName: 'Aplicar',
              meta: '',
              state: ReconStepState.next,
            ),
          ],
          body: const SizedBox.expand(),
          footer: const SizedBox(height: 56),
          onClose: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
