import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_payment_composer.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// **`5n` fila 9 · Completo / Con diferencia / Parcial.**
///
/// La fila de la matriz los trata como **modos que se eligen** y que recalculan
/// el monto. En esta app son lo contrario, y así queda adjudicado:
///
/// * **Son estados DERIVADOS del monto tecleado.** `_amountCaseOf(typed,
///   suggested)` los calcula; los chips son `Container` sin gesto. El monto es
///   la única fuente de verdad, y tener dos —el monto y un modo declarado— es
///   exactamente cómo se desincronizan.
/// * **«Con diferencia» NO es registrable, y no se fabrica.** Pagar de más está
///   bloqueado por el host: `amountError` dice «El monto no puede superar X» y
///   `canRegister` exige `<= newMoney`. Implementar un modo de sobrepago
///   exigiría cambiar el backend, y sobrepagar un sueldo no es una función que
///   falte: es una que no debe existir sin reversa.
/// * Por eso lo que esta prueba muerde de ese caso es que **no prometa nada
///   falso**. La nota decía «Al guardar queda registrada la diferencia» — un
///   registro que el sistema no puede hacer.
///
/// No se toca backend, no se escribe, y no se registra ningún pago.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  final amountField =
      find.byKey(const ValueKey<String>('payroll-composer-amount-field'));
  final note =
      find.byKey(const ValueKey<String>('payroll-composer-consequence'));

  Future<void> pumpComposer(WidgetTester tester) async {
    tester.view.physicalSize = const Size(720, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = TextEditingController(text: '100.000');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.vinabike,
          brightness: Brightness.light,
        ),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SizedBox.expand(
              child: PayrollPaymentComposer(
                personName: 'Lucas Pacheco',
                initials: 'LP',
                avatarColor: const Color(0xFF6FD1F6),
                weekLabel: 'PAGAR SEMANA 28 · 07 – 13 JUL',
                hoursAndEarned: r'38,5 h · total $100.000',
                earnedLabel: r'$100.000',
                advances: const <PayrollAdvanceVM>[],
                appliedLabel: r'$0',
                newMoneyLabel: r'$100.000',
                advancesBalanceLabel: r'vigente $0',
                contextNote: '',
                maximumNewMoneyLabel: r'$100.000',
                remainingAfterLabel: r'$0',
                amountController: controller,
                onAmountChanged: (_) => setState(() {}),
                methods: const <String>['Transferencia'],
                selectedMethod: 'Transferencia',
                dateLabel: '02/08/2026',
                referenceValue: 'TRF-88421',
                registerLabel: 'Registrar',
                onRegister: () => fail('esta prueba no registra ningún pago'),
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String value) async {
    await tester.enterText(amountField, value);
    await tester.pumpAndSettle();
  }

  testWidgets('5n f9 · el caso se DERIVA del monto, no se elige',
      (tester) async {
    await pumpComposer(tester);

    // Exacto → Completo, y la consecuencia es la de un pago que cierra.
    await type(tester, '100000');
    expect(
      find.descendant(of: note, matching: find.textContaining('Calza exacto')),
      findsOneWidget,
    );

    // Menos → Parcial. Nadie eligió «Parcial»: lo dijo el monto.
    await type(tester, '40000');
    expect(
      find.descendant(of: note, matching: find.textContaining('pago parcial')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: note, matching: find.textContaining('Calza exacto')),
      findsNothing,
    );
  });

  testWidgets(
      '5n f9 · «Con diferencia» NO promete registrar lo que no se puede',
      (tester) async {
    await pumpComposer(tester);

    await type(tester, '150000');

    // La promesa vieja, textual, no puede volver: era un registro imposible.
    expect(
      find.descendant(
        of: note,
        matching: find.textContaining('queda registrada la diferencia'),
      ),
      findsNothing,
      reason: 'el sobrepago está bloqueado: prometer registrarlo es mentir',
    );
    // Y lo que sí dice es lo único cierto: hay que bajar el monto.
    expect(
      find.descendant(
        of: note,
        matching: find.textContaining('no se puede registrar'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('5n f9 · la tira de casos es informativa, no una botonera',
      (tester) async {
    await pumpComposer(tester);
    await type(tester, '40000');

    // Ninguno de los tres chips es tocable: si alguien los vuelve elegibles,
    // aparecen dos fuentes de verdad para el mismo hecho.
    for (final name in const <String>['exact', 'over', 'partial']) {
      final chip = find.byKey(ValueKey<String>('payroll-composer-case-$name'));
      expect(chip, findsOneWidget, reason: name);
      expect(
        find.descendant(of: chip, matching: find.byType(InkWell)),
        findsNothing,
        reason: '«$name» se volvió tocable',
      );
      expect(
        find.descendant(of: chip, matching: find.byType(GestureDetector)),
        findsNothing,
        reason: '«$name» ganó un gesto',
      );
    }

    // Y se anuncia como estado, no como opciones sueltas.
    expect(
      find.bySemanticsLabel(RegExp('Estado del monto: pago parcial')),
      findsOneWidget,
    );
  });
}
