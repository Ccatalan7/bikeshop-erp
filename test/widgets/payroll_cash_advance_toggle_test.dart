import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_advances_and_cash_surfaces.dart';
import 'package:vinabike_erp/modules/hr/payroll/theme/payroll_tokens.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// **`5n` fila 12 · aplicar el anticipo en la entrega de efectivo.**
///
/// La fila pide «checkbox 48». Dos cosas estaban mal y se corrigieron el
/// 2026-08-02:
///
/// * el control medía `touchMobile - 4` = **44**, bajo el 48 de `F-06`;
/// * y **no mostraba su estado**: el texto de la hoja promete que
///   «desmarcarlo» devuelve el anticipo, el host ya alternaba el estado, pero
///   el rótulo decía siempre «Aplicar». Ahora es una casilla con
///   `Semantics.checked`, marca visible y rótulo que dice qué pasa al tocarla.
///
/// **Nada de esto escribe.** La hoja se monta con un host falso que sólo
/// alterna un `bool`, y `Confirmar` **no se pulsa** en ninguna prueba: la
/// entrega real de efectivo es una escritura de producción.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  final toggle =
      find.byKey(const ValueKey<String>('payroll-cash-apply-advance'));

  /// Réplica del cálculo del host (`payroll_redesign_page.dart`):
  /// `coverable = applyAdvance ? min(available, balance) : 0`.
  Future<void> pumpCash(
    WidgetTester tester, {
    required double balance,
    required double available,
  }) async {
    var applied = false;
    String clp(double v) => '\$${v.round()}';

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.vinabike,
          brightness: Brightness.light,
        ),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              final coverable =
                  !applied ? 0.0 : (available > balance ? balance : available);
              final deliver = balance - coverable;
              // Sin envoltorio con scroll: la hoja tiene hijos con `flex` y
              // una altura no acotada la revienta en layout.
              return SizedBox.expand(
                child: PayrollCashSurface(
                  weekLabel: 'Semana 28',
                  personName: 'Rodrigo Guillermo Nieto',
                  initials: 'RG',
                  avatarColor: PayrollTokens.avatarSky,
                  hoursAndMethod: '5,0 h · efectivo',
                  earnedLabel: clp(balance),
                  advancesLabel: clp(coverable),
                  deliverLabel: clp(deliver),
                  availableAdvanceLabel: clp(available),
                  dateLabel: '02/08/2026',
                  deliveredBy: 'Usuario actual',
                  onClose: () {},
                  onApplyAdvance: available <= 0.01
                      ? null
                      : () => setState(() => applied = !applied),
                  advanceApplied: applied,
                  onConfirm: () =>
                      fail('Confirmar NO se pulsa: sería una escritura real'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('5n f12 · el objetivo táctil es el canónico 48', (tester) async {
    tester.view.physicalSize = const Size(480, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpCash(tester, balance: 20000, available: 8000);

    expect(
      tester.getRect(toggle).height,
      PayrollTokens.touchMobile,
      reason: 'F-06 pide 48 exactos, y 44 no es 48',
    );
  });

  testWidgets('5n f12 · un segundo toque restaura: la casilla es reversible',
      (tester) async {
    tester.view.physicalSize = const Size(480, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpCash(tester, balance: 20000, available: 8000);

    // Sin marcar: no se descuenta nada y se entrega el saldo completo.
    expect(find.text('Aplicar anticipo de \$8000'), findsOneWidget);
    expect(find.text('\$20000'), findsWidgets);

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    // Marcado: el rótulo cambia y la entrega baja por el anticipo.
    expect(find.text('Anticipo aplicado · \$8000'), findsOneWidget);
    expect(find.text('\$12000'), findsWidgets,
        reason: 'entrega = saldo 20000 − anticipo 8000');

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    // **Restaurado.** Ésta es la promesa que el texto de la hoja hace
    // («desmarcarlo entrega el total completo y el anticipo queda vigente»).
    expect(find.text('Aplicar anticipo de \$8000'), findsOneWidget);
    expect(find.text('\$20000'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('5n f12 · aplica COMO MÁXIMO el saldo, nunca de más',
      (tester) async {
    tester.view.physicalSize = const Size(480, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Anticipo vigente MAYOR que lo que se le debe: el clamp es lo que impide
    // una entrega negativa, que es el defecto que esta fila persigue.
    await pumpCash(tester, balance: 20000, available: 50000);

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    // Se descuenta 20.000 —el saldo—, no 50.000, y la entrega queda en cero.
    expect(find.text('\$0'), findsWidgets,
        reason: 'la entrega queda en cero, jamás negativa');
    expect(find.textContaining('-\$'), findsNothing);
    expect(find.textContaining('−\$3'), findsNothing,
        reason: 'un −\$30000 sería el anticipo desbordando el saldo');
    expect(tester.takeException(), isNull);
  });
}
