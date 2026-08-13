import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/hr/models/payroll_voucher.dart';
import 'package:vinabike_erp/modules/hr/payroll/payment_workspace/payroll_payment_workspace.dart';
import 'package:vinabike_erp/modules/hr/payroll/payroll_redesign_page.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// F6.2/F6.3 — the routed Payroll host renders every scope from the mounted
/// theme in the full preset × brightness matrix. The dark cells additionally
/// prove the historical regression is dead: no surface anywhere paints the
/// legacy light canvas literal and nothing collapses to pure black.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  const paymentMethods = [
    {
      'id': 'method-transfer',
      'name': 'Transferencia',
      'code': 'transfer',
      'account_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'is_active': true,
      'requires_reference': false,
    },
    {
      'id': 'method-cash',
      'name': 'Efectivo',
      'code': 'cash',
      'account_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      'is_active': true,
      'requires_reference': false,
    },
  ];

  PayrollVoucher voucher() => PayrollVoucher(
        id: 'voucher-1',
        tenantId: 'tenant-1',
        voucherNumber: 'NOM-01',
        periodStart: DateTime(2026, 7, 6),
        periodEnd: DateTime(2026, 7, 12),
        totalHours: 58.5,
        totalAmount: 262875,
        employeeCount: 2,
        status: PayrollVoucherStatus.confirmed,
        createdAt: DateTime(2026, 7, 6),
        updatedAt: DateTime(2026, 7, 6),
        reconciliationVersion: 3,
        lines: const [
          PayrollVoucherLine(
            id: 'line-1',
            voucherId: 'voucher-1',
            employeeId: 'employee-1',
            employeeName: 'Persona Pagada',
            workedHours: 20,
            hourlyRate: 4500,
            totalAmount: 90000,
            paymentMethodId: 'method-transfer',
            settledAmount: 90000,
            balance: 0,
          ),
          PayrollVoucherLine(
            id: 'line-2',
            voucherId: 'voucher-1',
            employeeId: 'employee-2',
            employeeName: 'Persona Pendiente',
            workedHours: 38.5,
            hourlyRate: 4490,
            totalAmount: 172875,
            paymentMethodId: 'method-transfer',
            balance: 172875,
          ),
          PayrollVoucherLine(
            id: 'line-3',
            voucherId: 'voucher-1',
            employeeId: 'employee-3',
            employeeName: 'Persona Efectivo',
            workedHours: 10,
            hourlyRate: 4000,
            totalAmount: 40000,
            paymentMethodId: 'method-cash',
            balance: 40000,
          ),
        ],
      );

  PayrollRedesignActions actions() => PayrollRedesignActions(
        load: () async => PayrollRedesignData(
          vouchers: [voucher()],
          paymentMethods: paymentMethods,
          openAdvances: [
            EmployeeAdvance(
              id: 'advance-1',
              employeeId: 'employee-2',
              amount: 20000,
              amountApplied: 0,
              paidAt: DateTime(2026, 7, 8),
              status: 'open',
              paymentMethodId: 'method-cash',
              paymentAccountId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
              reference: 'ANT-01',
            ),
          ],
          employees: const [
            {
              'id': 'employee-1',
              'first_name': 'Persona',
              'last_name': 'Pagada',
              'status': 'active',
            },
            {
              'id': 'employee-2',
              'first_name': 'Persona',
              'last_name': 'Pendiente',
              'status': 'active',
            },
          ],
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

  void collectDecoration(Decoration? decoration, List<Color> fills) {
    if (decoration is BoxDecoration && decoration.color != null) {
      fills.add(decoration.color!);
    }
    if (decoration is ShapeDecoration && decoration.color != null) {
      fills.add(decoration.color!);
    }
  }

  List<Color> paintedFills(WidgetTester tester) {
    final fills = <Color>[];
    for (final widget in tester.allWidgets) {
      if (widget is ColoredBox) fills.add(widget.color);
      if (widget is Material && widget.color != null) fills.add(widget.color!);
      if (widget is Ink) {
        // Ink(color:) is folded into its decoration at construction.
        collectDecoration(widget.decoration, fills);
      }
      if (widget is DecoratedBox) collectDecoration(widget.decoration, fills);
      if (widget is Container) {
        collectDecoration(widget.decoration, fills);
        collectDecoration(widget.foregroundDecoration, fills);
        if (widget.color != null) fills.add(widget.color!);
      }
    }
    return fills;
  }

  // The frozen legacy light literals plus the two collapse extremes: none may
  // appear as a fill in any dark cell.
  const darkProhibitedFills = <Color>[
    Color(0xFFEEF1F5), // legacy light canvas
    Color(0xFFF7F8FA), // legacy sunken
    Color(0xFFF7FBFF), // legacy selected whisper
    Color(0xFFE8F2FC), // legacy accentSoft
    Color(0xFFFFFFFF), // pure white surface
    Color(0xFF000000), // pure black collapse
  ];

  testWidgets('every preset renders the three scopes from the mounted theme',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final preset in AppearancePresets.all) {
      for (final brightness in Brightness.values) {
        final theme = AppTheme.resolve(preset: preset, brightness: brightness);
        final cell = '${preset.code}/${brightness.name}';

        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            theme: theme,
            home: Scaffold(body: PayrollRedesignPage(actions: actions())),
          ),
        );
        await tester.pumpAndSettle();

        void assertNoDarkRegression(String stage) {
          if (brightness != Brightness.dark) return;
          final fills = paintedFills(tester);
          for (final prohibited in darkProhibitedFills) {
            expect(
              fills.contains(prohibited),
              isFalse,
              reason: '$cell $stage pinta el literal claro heredado o un '
                  'extremo de colapso ($prohibited) en dark',
            );
          }
        }

        expect(tester.takeException(), isNull, reason: '$cell Semanas');
        assertNoDarkRegression('Semanas');
        expect(find.text('Persona Pendiente'), findsWidgets,
            reason: '$cell fila pendiente visible');
        expect(find.textContaining('Pagar'), findsWidgets,
            reason: '$cell alguna acción Pagar visible');
        // Overlays are part of the dark-completeness gate: transfer and cash
        // must open the exact same canonical payment workspace.
        await tester.tap(find.text('Pagar').first);
        await tester.pumpAndSettle();
        expect(find.byType(PayrollPaymentWorkspace), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '$cell workspace');
        assertNoDarkRegression('workspace');
        await tester.tap(
          find.descendant(
            of: find.byType(PayrollPaymentWorkspace),
            matching: find.byTooltip('Cerrar'),
          ),
        );
        await tester.pumpAndSettle();

        // Efectivo y transferencia comparten el verbo `Pagar`: la fila de
        // efectivo se identifica por su persona.
        await tester.tap(
          find.byKey(
            const ValueKey<String>('payroll-row-action-Persona Efectivo'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(PayrollPaymentWorkspace), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '$cell efectivo');
        assertNoDarkRegression('efectivo');
        await tester.tap(
          find.descendant(
            of: find.byType(PayrollPaymentWorkspace),
            matching: find.byTooltip('Cerrar'),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(
            const ValueKey<String>('payroll-paid-status-Persona Pagada'),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$cell evidencia');
        assertNoDarkRegression('evidencia');
        await tester.tap(
          find.byKey(const ValueKey<String>('payroll-payment-evidence-close')),
        );
        await tester.pumpAndSettle();

        for (final scope in const ['Historial', 'Anticipos']) {
          await tester.tap(find.text(scope).first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$cell $scope');
          assertNoDarkRegression(scope);
        }
      }
    }
  });

  testWidgets('compact host and the error state stay dark-correct',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final config in const <(AppearancePreset, Brightness)>[
      (AppearancePresets.vinabike, Brightness.light),
      (AppearancePresets.pacific, Brightness.dark),
      (AppearancePresets.midnight, Brightness.dark),
    ]) {
      final theme = AppTheme.resolve(preset: config.$1, brightness: config.$2);
      final cell = '${config.$1.code}/${config.$2.name} 390';

      void assertNoDarkRegression(String stage) {
        if (config.$2 != Brightness.dark) return;
        final fills = paintedFills(tester);
        for (final prohibited in darkProhibitedFills) {
          expect(
            fills.contains(prohibited),
            isFalse,
            reason: '$cell $stage pinta un literal prohibido en dark',
          );
        }
      }

      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          theme: theme,
          home: Scaffold(body: PayrollRedesignPage(actions: actions())),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$cell Semanas');
      assertNoDarkRegression('Semanas');

      for (final scope in const ['Historial', 'Anticipos']) {
        await tester.tap(find.text(scope).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$cell $scope');
        assertNoDarkRegression(scope);
      }

      // The authoritative-load error state renders its retry CTA from the
      // same owner and stays inside the dark palette.
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          theme: theme,
          home: Scaffold(
            body: PayrollRedesignPage(
              actions: PayrollRedesignActions(
                load: () async => throw StateError('carga fallida sintética'),
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
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Reintentar'), findsOneWidget, reason: '$cell error');
      expect(tester.takeException(), isNull, reason: '$cell error');
      assertNoDarkRegression('error');
    }
  });
}
