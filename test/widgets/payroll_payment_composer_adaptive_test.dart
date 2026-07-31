import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_payment_composer.dart';
import 'package:vinabike_erp/modules/hr/payroll/theme/payroll_tokens.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpComposer(
    WidgetTester tester, {
    required Size size,
    required TextEditingController referenceController,
    FutureOr<void> Function()? onClose,
    FutureOr<void> Function()? onRegister,
    ValueChanged<String>? onSelectMethod,
    List<String> methods = const <String>[
      'Transferencia',
      'Efectivo',
    ],
    String selectedMethod = 'Transferencia',
    bool? lockSelectedMethod,
    TextEditingController? amountController,
    ValueChanged<String>? onAmountChanged,
    String? amountError,
    bool registerEnabled = true,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.view.viewInsets = FakeViewPadding.zero);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final media = MediaQuery.of(context);
            final desktop = media.size.width >= 900;
            // Replica el ownership del route real: el host, no el compositor,
            // aplica SafeArea y teclado exactamente una vez.
            return Material(
              child: SafeArea(
                child: AnimatedPadding(
                  duration: PayrollTokens.fast,
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
                  child: Align(
                    alignment: desktop
                        ? Alignment.centerRight
                        : Alignment.bottomCenter,
                    child: SizedBox(
                      width: desktop ? 540 : double.infinity,
                      height: double.infinity,
                      child: PayrollPaymentComposer(
                        personName: 'Lucas Reyes Bravo',
                        initials: 'LR',
                        avatarColor: const Color(0xFFBDEAF5),
                        weekLabel: 'PAGAR SEMANA 28 · 07 – 13 JUL',
                        hoursAndEarned: '38,5 h · ganado \$172.875',
                        earnedLabel: '\$172.875',
                        advances: <PayrollAdvanceVM>[
                          PayrollAdvanceVM(
                            reason: 'Adelanto de quincena',
                            meta: '05/07 · transferencia',
                            amountLabel: '\$15.000',
                            applied: false,
                            onToggle: () {},
                          ),
                        ],
                        appliedLabel: '\$0',
                        newMoneyLabel: '\$172.875',
                        advancesBalanceLabel: 'vigente \$15.000',
                        contextNote:
                            'La referencia respalda este pago en la conciliación.',
                        methods: methods,
                        selectedMethod: selectedMethod,
                        dateLabel: '29/07/2026',
                        referenceValue: referenceController.text,
                        referenceController: referenceController,
                        onSelectMethod: onSelectMethod,
                        lockSelectedMethod: lockSelectedMethod,
                        amountController: amountController,
                        onAmountChanged: onAmountChanged,
                        maximumNewMoneyLabel: '\$172.875',
                        remainingAfterLabel: '\$122.875',
                        amountError: amountError,
                        registerEnabled: registerEnabled,
                        onClose: onClose ?? () {},
                        onRegister: onRegister ?? () {},
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      '390px apila fecha y referencia, conserva targets y sube el CTA con teclado',
      (tester) async {
    final controller = TextEditingController();
    await pumpComposer(
      tester,
      size: const Size(390, 844),
      referenceController: controller,
    );

    final close = find.byKey(const ValueKey<String>('payroll-composer-close'));
    final transfer = find.byKey(
      const ValueKey<String>('payroll-payment-method-Transferencia'),
    );
    final date =
        find.byKey(const ValueKey<String>('payroll-composer-date-field'));
    final reference =
        find.byKey(const ValueKey<String>('payroll-composer-reference-field'));

    expect(tester.getSize(close).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(transfer).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(reference).height, greaterThanOrEqualTo(48));
    expect(
      tester.getTopLeft(reference).dy,
      greaterThan(tester.getBottomLeft(date).dy),
      reason: 'En teléfono los campos deben apilarse, no comprimirse en fila.',
    );

    final input = find.byType(TextField);
    await tester.ensureVisible(input);
    await tester.tap(input);
    await tester.enterText(input, 'TRF-88421');

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    final footer =
        find.byKey(const ValueKey<String>('payroll-composer-footer'));
    final register =
        find.byKey(const ValueKey<String>('payroll-composer-register'));
    expect(register.hitTestable(), findsOneWidget);
    expect(tester.getSize(register).height, greaterThanOrEqualTo(48));
    expect(
      tester.getBottomRight(footer).dy,
      lessThanOrEqualTo(544),
      reason: 'El footer persistente debe quedar sobre el teclado de 300px.',
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      ),
      findsNothing,
      reason:
          'El scroll horizontal interno del EditableText no es scroll de layout.',
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    controller.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('600px cambia entre cuentas de transferencia y bloquea efectivo',
      (tester) async {
    final controller = TextEditingController();
    final selections = <String>[];
    await pumpComposer(
      tester,
      size: const Size(600, 900),
      referenceController: controller,
      onSelectMethod: selections.add,
      methods: const <String>[
        'Transferencia · Banco Estado',
        'Transferencia · Banco de Chile',
        'Efectivo',
      ],
      selectedMethod: 'Transferencia · Banco Estado',
    );

    final date =
        find.byKey(const ValueKey<String>('payroll-composer-date-field'));
    final reference =
        find.byKey(const ValueKey<String>('payroll-composer-reference-field'));
    final secondTransfer = find.byKey(
      const ValueKey<String>(
        'payroll-payment-method-Transferencia · Banco de Chile',
      ),
    );
    final cash = find.byKey(
      const ValueKey<String>('payroll-payment-method-Efectivo'),
    );

    expect(
      tester.getTopLeft(reference).dy,
      closeTo(tester.getTopLeft(date).dy, 0.01),
      reason:
          'A 600px los dos campos tienen ancho útil y deben compartir fila.',
    );
    expect(tester.getSize(secondTransfer).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(cash).height, greaterThanOrEqualTo(48));

    await tester.tap(secondTransfer);
    await tester.pump();
    expect(selections, const <String>['Transferencia · Banco de Chile']);

    await tester.tap(cash);
    await tester.pump();
    expect(
      selections,
      const <String>['Transferencia · Banco de Chile'],
      reason:
          'El compositor de transferencia no puede saltar al flujo efectivo.',
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    controller.dispose();
  });

  testWidgets('cerrar delega al host sin abrir una segunda confirmación',
      (tester) async {
    final controller = TextEditingController();
    var closeCalls = 0;
    await pumpComposer(
      tester,
      size: const Size(390, 844),
      referenceController: controller,
      onClose: () async {
        closeCalls += 1;
      },
    );

    final input = find.byType(TextField);
    await tester.ensureVisible(input);
    await tester.enterText(input, 'BORRADOR');
    await tester.tap(
      find.byKey(const ValueKey<String>('payroll-composer-close')),
    );
    await tester.pumpAndSettle();

    expect(closeCalls, 1);
    expect(find.textContaining('Descartar cambios'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    controller.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('registro async bloquea doble envío hasta que termina el host',
      (tester) async {
    final controller = TextEditingController();
    final completion = Completer<void>();
    var registerCalls = 0;
    await pumpComposer(
      tester,
      size: const Size(1440, 900),
      referenceController: controller,
      onRegister: () {
        registerCalls += 1;
        return completion.future;
      },
    );

    final register =
        find.byKey(const ValueKey<String>('payroll-composer-register'));
    await tester.tap(register);
    await tester.pump();
    expect(registerCalls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(register, warnIfMissed: false);
    await tester.pump();
    expect(registerCalls, 1);

    completion.complete();
    await tester.pumpAndSettle();
    expect(find.text('Registrar \$172.875'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    controller.dispose();
  });

  testWidgets('monto CLP se formatea y un valor inválido bloquea el registro',
      (tester) async {
    final referenceController = TextEditingController();
    final amountController = TextEditingController(text: '172.875');
    final changes = <String>[];
    var registerCalls = 0;
    await pumpComposer(
      tester,
      size: const Size(390, 844),
      referenceController: referenceController,
      amountController: amountController,
      onAmountChanged: changes.add,
      amountError: 'El monto no puede superar \$172.875.',
      registerEnabled: false,
      onRegister: () => registerCalls += 1,
    );

    final amountField =
        find.byKey(const ValueKey<String>('payroll-composer-amount-field'));
    await tester.ensureVisible(amountField);
    await tester.enterText(amountField, '200000');
    await tester.pump();

    expect(amountController.text, '200.000');
    expect(changes.last, '200.000');
    expect(find.text('El monto no puede superar \$172.875.'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('payroll-composer-register')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(registerCalls, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    amountController.dispose();
    referenceController.dispose();
  });
}
