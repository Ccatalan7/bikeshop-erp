import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_payment_composer.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_accent_action.dart';
import 'package:vinabike_erp/modules/hr/payroll/theme/payroll_tokens.dart';

/// Ancho real de la hoja del composer segun Design `7d` (el `width` 522 del
/// HTML es de contenido: esa pagina no tiene reset `border-box`).
const double composerSheetWidth = 560;

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
    Brightness brightness = Brightness.light,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.view.viewInsets = FakeViewPadding.zero);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
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
                      width: desktop ? composerSheetWidth : double.infinity,
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
    // El CTA compacto mide EXACTAMENTE el token de densidad `F-06 · TOUCH 48`,
    // y se mide **el botón de registrar**, no «el primer PayrollAccentAction
    // que aparezca»: anclar por posición no fija nada. Igualdad y no `>= 48`,
    // porque antes traía un 50 literal del frame y un aserto laxo lo dejaba
    // pasar sin decir nada.
    final registerAction = find.descendant(
      of: register,
      matching: find.byType(PayrollAccentAction),
    );
    expect(registerAction, findsOneWidget);
    expect(tester.getSize(registerAction).height, PayrollTokens.touchMobile);
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

  testWidgets(
      '7d · los tres modos del pago miden 46, el activo va en selectionRow y '
      'el inactivo en sunken — en claro y en oscuro', (tester) async {
    for (final brightness in Brightness.values) {
      final referenceController = TextEditingController();
      final amountController = TextEditingController(text: r'$172.875');
      await pumpComposer(
        tester,
        size: const Size(1360, 900),
        referenceController: referenceController,
        amountController: amountController,
        onAmountChanged: (_) {},
        brightness: brightness,
      );

      Container cardOf(String name) => tester.widget<Container>(
            find.byKey(ValueKey<String>('payroll-composer-case-$name')),
          );
      final context = tester.element(
        find.byKey(const ValueKey<String>('payroll-payment-composer')),
      );
      final visual = PayrollVisualTokens.of(context);

      for (final name in const <String>['exact', 'over', 'partial']) {
        final size = tester.getSize(
          find.byKey(ValueKey<String>('payroll-composer-case-$name')),
        );
        expect(
          size.height,
          paymentModeCardHeight,
          reason: '$name en $brightness',
        );
      }

      // El activo: `selectionRow` + borde de acento. El inactivo: `sunken` +
      // borde `divider`. Ninguno de los dos es `surface`.
      final activeBox = cardOf('exact').decoration! as BoxDecoration;
      final idleBox = cardOf('partial').decoration! as BoxDecoration;
      expect(activeBox.color, visual.surfaceSelected, reason: '$brightness');
      expect(idleBox.color, visual.surfaceSunken, reason: '$brightness');
      expect(activeBox.color, isNot(visual.surface), reason: '$brightness');
      expect(
        (activeBox.border! as Border).top.color,
        visual.accent,
        reason: '$brightness',
      );
      expect(
        (idleBox.border! as Border).top.color,
        visual.border,
        reason: '$brightness',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      amountController.dispose();
      referenceController.dispose();
    }
  });

  testWidgets('7d · la hoja del composer mide 560 en escritorio',
      (tester) async {
    // El ancho REAL del archivo de Design, no el `width` de contenido (522)
    // que esa página declara por no tener reset `border-box`.
    expect(composerSheetWidth, 560);

    final referenceController = TextEditingController();
    await pumpComposer(
      tester,
      size: const Size(1360, 900),
      referenceController: referenceController,
    );
    final width = tester
        .getSize(
          find.byKey(const ValueKey<String>('payroll-payment-composer')),
        )
        .width;
    expect(width, composerSheetWidth);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    referenceController.dispose();
  });
}
