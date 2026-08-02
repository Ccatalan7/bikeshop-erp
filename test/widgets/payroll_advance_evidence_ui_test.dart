import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_advances_and_cash_surfaces.dart';
import 'package:vinabike_erp/modules/hr/payroll/theme/payroll_tokens.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// `5h` · el comprobante original y la razón real en el ledger.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final people = <AdvancePersonVM>[
    AdvancePersonVM(
      id: 'rg',
      name: 'Rodrigo Guillermo Nieto',
      initials: 'RG',
      avatarColor: PayrollTokens.avatarSky,
      balanceLabel: r'$36.000',
      caption: 'aplicable ahora',
      selected: true,
      onTap: () {},
    ),
  ];

  AdvanceLedgerRowVM rowVM({
    String reason = 'Se fue el miércoles',
    String? detail = 'Semana corta · Último día trabajado 29/07/2026',
    String? fileName,
    VoidCallback? onOpen,
  }) =>
      AdvanceLedgerRowVM(
        date: '30/07',
        reason: reason,
        detail: detail,
        amount: r'$36.000',
        applied: r'$0',
        balance: r'$36.000',
        statusLabel: 'VIGENTE',
        tone: PayrollStateTone.info,
        evidenceFileName: fileName,
        onOpenEvidence: onOpen,
      );

  Future<void> pumpLedger(
    WidgetTester tester, {
    required double width,
    required AdvanceLedgerRowVM vm,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.vinabike,
          brightness: Brightness.light,
        ),
        home: Scaffold(
          body: PayrollAdvancesSurface(
            people: people,
            selectedName: 'Rodrigo Guillermo Nieto',
            selectedInitials: 'RG',
            selectedAvatar: PayrollTokens.avatarSky,
            selectedBalance: r'$36.000',
            selectedCount: '1 movimiento',
            ledger: <AdvanceLedgerRowVM>[vm],
            onNewAdvanceForSelectedPerson: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in <double>[1360, 834, 430]) {
    testWidgets('5h · el comprobante se ofrece UNA vez a ${width.toInt()}',
        (tester) async {
      var opened = 0;
      await pumpLedger(
        tester,
        width: width,
        vm: rowVM(fileName: 'vale-firmado.pdf', onOpen: () => opened++),
      );

      final cta = find.text('Ver comprobante');
      expect(cta, findsOneWidget, reason: 'una sola vez, no una por fila');

      // La razón que se lee es la explicación, jamás la referencia bancaria.
      expect(find.text('Se fue el miércoles'), findsOneWidget);
      expect(
        find.textContaining('Último día trabajado 29/07/2026'),
        findsOneWidget,
      );

      if (width < PayrollTokens.bpDesktop) {
        final size = tester.getSize(
          find.byKey(const ValueKey<String>(
            'payroll-advance-evidence-vale-firmado.pdf',
          )),
        );
        expect(
          size.height,
          greaterThanOrEqualTo(PayrollTokens.touchMin),
          reason: 'en compacto el objetivo táctil es 48',
        );
      }

      await tester.tap(cta);
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('5h · sin comprobante NO se ofrece la acción', (tester) async {
    await pumpLedger(tester, width: 1360, vm: rowVM());
    expect(find.text('Ver comprobante'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
