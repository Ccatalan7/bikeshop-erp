import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_history_surface.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_payment_composer.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_queue_surface.dart';
import 'package:vinabike_erp/modules/hr/payroll/theme/payroll_tokens.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/themes/vinabike_theme_roles.dart';

/// F5.1 — the three formerly conflated meanings must stay distinguishable:
/// selection (History/selected week) keeps the `selectionContainer` fill,
/// an expanded disclosure is a depth change (`surfaceContainerLow`), and an
/// applied advance is a bordered committed control on plain surface.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  const configs = <(AppearancePreset, Brightness)>[
    (AppearancePresets.vinabike, Brightness.light),
    (AppearancePresets.pacific, Brightness.dark),
  ];

  Future<void> host(
    WidgetTester tester,
    ThemeData theme,
    Widget body,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        theme: theme,
        home: Scaffold(body: body),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('expanded disclosure is a sunken depth step, not selection',
      (tester) async {
    for (final config in configs) {
      final theme = AppTheme.resolve(
        preset: config.$1,
        brightness: config.$2,
      );
      await host(
        tester,
        theme,
        PayrollQueueSurface(
          weeks: <PayrollWeekCardVM>[
            PayrollWeekCardVM(
              name: 'Semana 28',
              range: '07 – 13 jul',
              amountLabel: r'$267.875',
              amountCaption: 'por pagar',
              statusLabel: 'ABIERTA',
              tone: PayrollStateTone(
                theme.colorScheme.onTertiaryContainer,
                theme.colorScheme.tertiaryContainer,
                theme.colorScheme.outline,
              ),
              selected: true,
              onTap: () {},
            ),
          ],
          rows: <PayrollPersonRowVM>[
            PayrollPersonRowVM(
              name: 'Persona Expandida',
              initials: 'PE',
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
              expanded: true,
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
      );

      final disclosure = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('CÓMO SE CALCULÓ'),
              matching: find.byType(Container),
            )
            .first,
      );
      final disclosureColor = (disclosure.decoration! as BoxDecoration).color;
      expect(
        disclosureColor,
        theme.colorScheme.surfaceContainerLow,
        reason: 'la disclosure expandida usa el paso hundido del ladder '
            '(${config.$1.code}/${config.$2.name})',
      );
      expect(
        disclosureColor,
        isNot(theme.extension<VinabikeThemeRoles>()!.selectionContainer),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the selected History week owns the selection fill',
      (tester) async {
    for (final config in configs) {
      final theme = AppTheme.resolve(
        preset: config.$1,
        brightness: config.$2,
      );
      await host(
        tester,
        theme,
        PayrollHistorySurface(
          weeks: const <PayrollHistoryWeekVM>[
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
          ],
          detail: const PayrollHistoryDetailVM(
            id: 'week-28',
            title: 'Semana 28',
            range: '07 – 13 jul',
            voucherNumber: 'NOM-00028',
            status: 'PAGADA',
            voided: false,
            weekTotal: r'$235.000',
            payable: r'$235.000',
            paid: r'$235.000',
            advances: '—',
            pending: r'$0',
            settled: true,
            lines: <PayrollHistoryLineVM>[],
          ),
          compact: false,
          isHydrating: false,
          authoritativeReady: true,
          error: null,
          onSelect: (_) {},
          onRetry: () {},
        ),
      );

      final selectedWeek = tester.widget<Material>(
        find.byKey(const ValueKey('payroll-history-week-week-28')),
      );
      final unselectedWeek = tester.widget<Material>(
        find.byKey(const ValueKey('payroll-history-week-week-27')),
      );
      expect(
        selectedWeek.color,
        theme.extension<VinabikeThemeRoles>()!.selectionContainer,
        reason: 'la semana seleccionada usa selectionContainer '
            '(${config.$1.code}/${config.$2.name})',
      );
      expect(unselectedWeek.color, theme.colorScheme.surface);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('an applied advance is a bordered control, never a selection',
      (tester) async {
    for (final config in configs) {
      final theme = AppTheme.resolve(
        preset: config.$1,
        brightness: config.$2,
      );
      final reference = TextEditingController();
      addTearDown(reference.dispose);
      await host(
        tester,
        theme,
        Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: 540,
            height: 800,
            child: PayrollPaymentComposer(
              personName: 'Lucas Reyes Bravo',
              initials: 'LR',
              avatarColor: theme.colorScheme.secondary,
              weekLabel: 'PAGAR SEMANA 28 · 07 – 13 JUL',
              hoursAndEarned: r'38,5 h · ganado $172.875',
              earnedLabel: r'$172.875',
              advances: <PayrollAdvanceVM>[
                PayrollAdvanceVM(
                  reason: 'Adelanto de quincena',
                  meta: '05/07 · transferencia',
                  amountLabel: r'$15.000',
                  applied: true,
                  onToggle: () {},
                ),
              ],
              appliedLabel: r'−$15.000',
              newMoneyLabel: r'$157.875',
              advancesBalanceLabel: r'vigente $15.000',
              contextNote: 'La referencia respalda este pago.',
              methods: const <String>['Transferencia'],
              selectedMethod: 'Transferencia',
              dateLabel: '29/07/2026',
              referenceValue: '',
              referenceController: reference,
              onSelectMethod: (_) {},
              maximumNewMoneyLabel: r'$172.875',
              remainingAfterLabel: r'$0',
              registerEnabled: true,
              onClose: () {},
              onRegister: () {},
            ),
          ),
        ),
      );

      final row = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('Adelanto de quincena'),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = row.decoration! as BoxDecoration;
      expect(decoration.color, theme.colorScheme.surface);
      final border = decoration.border! as Border;
      expect(
        border.top.color,
        theme.extension<VinabikeThemeRoles>()!.info.border,
        reason: 'el anticipo aplicado se marca con borde accent '
            '(${config.$1.code}/${config.$2.name})',
      );
      expect(
        decoration.color,
        isNot(theme.extension<VinabikeThemeRoles>()!.selectionContainer),
      );
      expect(tester.takeException(), isNull);
    }
  });
}
