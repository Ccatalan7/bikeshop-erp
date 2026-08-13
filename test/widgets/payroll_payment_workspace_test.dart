import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/hr/models/payroll_statement_reconciliation.dart';
import 'package:vinabike_erp/modules/hr/payroll/payment_workspace/payroll_payment_workspace.dart';
import 'package:vinabike_erp/modules/hr/payroll/payment_workspace/payroll_payment_workspace_controller.dart';
import 'package:vinabike_erp/modules/hr/payroll/payment_workspace/payroll_payment_workspace_models.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/vb_short_select.dart';
import 'package:vinabike_erp/shared/widgets/vb_status_badge.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpWorkspace(
    WidgetTester tester, {
    required PayrollPaymentWorkspaceController controller,
    Size size = const Size(560, 900),
    double? workspaceWidth,
    List<PayrollExpenseAccountOption> expenseAccounts = const [],
    VoidCallback? onClose,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.all.first,
          brightness: Brightness.light,
        ),
        home: Scaffold(
          body: workspaceWidth == null
              ? PayrollPaymentWorkspace(
                  controller: controller,
                  onClose: onClose ?? () {},
                  expenseAccounts: expenseAccounts,
                )
              : Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: workspaceWidth,
                    child: PayrollPaymentWorkspace(
                      controller: controller,
                      onClose: onClose ?? () {},
                      expenseAccounts: expenseAccounts,
                    ),
                  ),
                ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> bringIntoViewport(WidgetTester tester, Finder finder) async {
    await Scrollable.ensureVisible(
      tester.element(finder),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'single conserva el editor canónico y batch lo expande sin ocultar la lista',
      (tester) async {
    final sharedTarget = _target(
      id: 'shared',
      voucherId: 'voucher-new',
      name: 'Fernando Tapia',
      periodStart: const PayrollCivilDate(2026, 8, 3),
      periodEnd: const PayrollCivilDate(2026, 8, 9),
    );
    final singleController = PayrollPaymentWorkspaceController(
      request: PayrollPaymentWorkspaceRequest.single(
        target: sharedTarget,
        paymentMethods: _paymentMethods,
      ),
    );
    addTearDown(singleController.dispose);

    await pumpWorkspace(tester, controller: singleController);

    final singleEditor = find.byKey(
      const ValueKey<String>('payroll-payment-editor-shared'),
    );
    expect(singleEditor, findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>('payroll-payment-week-navigator'),
      ),
      findsNothing,
    );
    expect(find.text('Cómo se paga el sueldo'), findsOneWidget);
    expect(find.text('Conceptos del pago'), findsOneWidget);

    final batchController = PayrollPaymentWorkspaceController(
      request: PayrollPaymentWorkspaceRequest.batch(
        targets: <PayrollPaymentTarget>[
          _target(
            id: 'older',
            voucherId: 'voucher-old',
            name: 'Vicente Díaz',
          ),
          sharedTarget,
        ],
        paymentMethods: _paymentMethods,
      ),
    );
    addTearDown(batchController.dispose);

    await pumpWorkspace(
      tester,
      controller: batchController,
      size: const Size(1440, 900),
    );

    expect(
      find.byKey(
        const ValueKey<String>('payroll-payment-batch-workspace'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('payroll-payment-batch-list')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('payroll-payment-row-shared')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('payroll-payment-row-older')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('payroll-payment-week-navigator'),
      ),
      findsNothing,
    );

    await tester.tap(
      find.byKey(
        const ValueKey<String>('payroll-payment-details-shared'),
      ),
    );
    await tester.pumpAndSettle();

    final batchEditor = find.byKey(
      const ValueKey<String>('payroll-payment-editor-shared'),
    );
    expect(batchEditor, findsOneWidget);
    expect(find.text('Cómo se paga el sueldo'), findsOneWidget);
    expect(find.text('Conceptos del pago'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('payroll-payment-row-older')),
      findsOneWidget,
      reason: 'abrir un detalle nunca reemplaza la lista completa del batch',
    );
    expect(tester.takeException(), isNull);
  });

  for (final width in <double>[600, 834, 1440]) {
    testWidgets(
        'a ${width.toInt()} px parte y concepto se editan inline sin scrim',
        (tester) async {
      final target = _target(
        id: 'inline-$width',
        voucherId: 'voucher-inline',
        name: 'Fernando Tapia',
      );
      final controller = PayrollPaymentWorkspaceController(
        request: PayrollPaymentWorkspaceRequest.single(
          target: target,
          paymentMethods: _paymentMethods,
        ),
        additionalConceptsSupported: true,
      );
      addTearDown(controller.dispose);

      await pumpWorkspace(
        tester,
        controller: controller,
        size: Size(width, 900),
        workspaceWidth: width == 1440 ? 560 : null,
        expenseAccounts: const <PayrollExpenseAccountOption>[
          PayrollExpenseAccountOption(
            accountId: 'workshop-supplies',
            label: '5108 · Insumos del taller',
          ),
        ],
      );

      final workspaceEditor = find.byKey(
        ValueKey<String>('payroll-payment-editor-${target.targetId}'),
      );
      final modalScrim = find.byWidgetPredicate(
        (widget) => widget is ModalBarrier || widget is AnimatedModalBarrier,
      );
      final baselineScrimCount = modalScrim.evaluate().length;

      await tester.ensureVisible(find.text('Agregar parte'));
      await tester.tap(find.text('Agregar parte'));
      await tester.pumpAndSettle();

      final legEditor = find.byKey(
        const ValueKey<String>('payroll-payment-inline-leg-editor'),
      );
      expect(legEditor, findsOneWidget);
      expect(
        find.descendant(of: workspaceEditor, matching: legEditor),
        findsOneWidget,
      );
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(modalScrim, findsNWidgets(baselineScrimCount));
      await tester.tap(
        find.descendant(
          of: legEditor,
          matching: find.widgetWithText(TextButton, 'Cancelar'),
        ),
      );
      await tester.pumpAndSettle();
      expect(legEditor, findsNothing);

      await tester.ensureVisible(find.text('Agregar concepto'));
      await tester.tap(find.text('Agregar concepto'));
      await tester.pumpAndSettle();

      final conceptEditor = find.byKey(
        const ValueKey<String>('payroll-payment-inline-concept-editor'),
      );
      expect(conceptEditor, findsOneWidget);
      expect(
        find.descendant(of: workspaceEditor, matching: conceptEditor),
        findsOneWidget,
      );
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(modalScrim, findsNWidgets(baselineScrimCount));
      expect(
        find.text('¿Este monto ya está dentro del total de la nómina?'),
        findsOneWidget,
      );
      expect(find.text('Sí, ya está incluido'), findsOneWidget);
      expect(find.text('No, se suma aparte'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: conceptEditor,
          matching: find.widgetWithText(TextButton, 'Cancelar'),
        ),
      );
      await tester.pumpAndSettle();
      expect(conceptEditor, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in <double>[390, 599]) {
    testWidgets('a ${width.toInt()} px conserva los formularios en diálogo',
        (tester) async {
      final target = _target(
        id: 'mobile-dialog-$width',
        voucherId: 'voucher-mobile',
        name: 'Fernando Tapia',
      );
      final controller = PayrollPaymentWorkspaceController(
        request: PayrollPaymentWorkspaceRequest.single(
          target: target,
          paymentMethods: _paymentMethods,
        ),
        additionalConceptsSupported: true,
      );
      addTearDown(controller.dispose);

      await pumpWorkspace(
        tester,
        controller: controller,
        size: Size(width, 844),
        expenseAccounts: const <PayrollExpenseAccountOption>[
          PayrollExpenseAccountOption(
            accountId: 'workshop-supplies',
            label: '5108 · Insumos del taller',
          ),
        ],
      );

      final modalScrim = find.byWidgetPredicate(
        (widget) => widget is ModalBarrier || widget is AnimatedModalBarrier,
      );

      await tester.ensureVisible(find.text('Agregar parte'));
      await tester.tap(find.text('Agregar parte'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(modalScrim, findsWidgets);
      expect(
        find.byKey(
          const ValueKey<String>('payroll-payment-inline-leg-editor'),
        ),
        findsNothing,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Agregar concepto'));
      await tester.tap(find.text('Agregar concepto'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(modalScrim, findsWidgets);
      expect(
        find.text('¿Este monto ya está dentro del total de la nómina?'),
        findsOneWidget,
      );
      expect(find.text('Sí, ya está incluido'), findsOneWidget);
      expect(find.text('No, se suma aparte'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey<String>('payroll-payment-inline-concept-editor'),
        ),
        findsNothing,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('cerrar con editor inline abierto exige decidir los cambios',
      (tester) async {
    final target = _target(
      id: 'inline-dirty-close',
      voucherId: 'voucher-inline-dirty-close',
      name: 'Fernando Tapia',
    );
    final controller = PayrollPaymentWorkspaceController(
      request: PayrollPaymentWorkspaceRequest.single(
        target: target,
        paymentMethods: _paymentMethods,
      ),
    );
    addTearDown(controller.dispose);
    var closed = false;

    await pumpWorkspace(
      tester,
      controller: controller,
      size: const Size(834, 900),
      onClose: () => closed = true,
    );

    await tester.ensureVisible(find.text('Agregar parte'));
    await tester.tap(find.text('Agregar parte'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey<String>('payroll-payment-inline-leg-editor'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();

    expect(closed, isFalse);
    expect(
      find.text('Hay cambios de pago que todavía no se han registrado.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Seguir editando'));
    await tester.pumpAndSettle();
    expect(closed, isFalse);
    expect(
      find.byKey(
        const ValueKey<String>('payroll-payment-inline-leg-editor'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Descartar cambios'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final width in <double>[1440, 834]) {
    testWidgets(
        'batch a ${width.toInt()} separa semanas y muestra todas las filas con su método',
        (tester) async {
      final older = _target(
        id: 'older-worker',
        voucherId: 'voucher-old',
        name: 'Rodrigo Nieto',
        balanceClp: 20000,
      );
      final newerB = _target(
        id: 'newer-worker-b',
        voucherId: 'voucher-new',
        name: 'Vicente Díaz',
        balanceClp: 94500,
        periodStart: const PayrollCivilDate(2026, 8, 3),
        periodEnd: const PayrollCivilDate(2026, 8, 9),
      );
      final newerA = _target(
        id: 'newer-worker-a',
        voucherId: 'voucher-new',
        name: 'Fernando Tapia',
        balanceClp: 38500,
        periodStart: const PayrollCivilDate(2026, 8, 3),
        periodEnd: const PayrollCivilDate(2026, 8, 9),
      );
      final controller = PayrollPaymentWorkspaceController(
        request: PayrollPaymentWorkspaceRequest.batch(
          targets: <PayrollPaymentTarget>[older, newerB, newerA],
          paymentMethods: _paymentMethods,
        ),
      );
      addTearDown(controller.dispose);
      controller
        ..setSimplePaymentMethod(older.targetId, 'method-cash')
        ..setSimplePaymentMethod(newerA.targetId, 'method-transfer')
        ..setSimplePaymentMethod(newerB.targetId, 'method-transfer');

      await pumpWorkspace(
        tester,
        controller: controller,
        size: Size(width, 900),
      );

      final newerWeek = find.byKey(
        const ValueKey<String>('payroll-payment-week-voucher-new'),
      );
      final olderWeek = find.byKey(
        const ValueKey<String>('payroll-payment-week-voucher-old'),
      );
      final newerARow = find.byKey(
        const ValueKey<String>('payroll-payment-row-newer-worker-a'),
      );
      final newerBRow = find.byKey(
        const ValueKey<String>('payroll-payment-row-newer-worker-b'),
      );
      final olderRow = find.byKey(
        const ValueKey<String>('payroll-payment-row-older-worker'),
      );

      expect(
        find.byKey(
          const ValueKey<String>('payroll-payment-batch-workspace'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('payroll-payment-batch-list')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('payroll-payment-week-navigator'),
        ),
        findsNothing,
      );
      expect(newerWeek, findsOneWidget);
      expect(olderWeek, findsOneWidget);
      expect(
        tester.getTopLeft(newerWeek).dy,
        lessThan(tester.getTopLeft(olderWeek).dy),
      );
      expect(
        find.descendant(of: newerWeek, matching: newerARow),
        findsOneWidget,
      );
      expect(
        find.descendant(of: newerWeek, matching: newerBRow),
        findsOneWidget,
      );
      expect(
        find.descendant(of: olderWeek, matching: olderRow),
        findsOneWidget,
      );

      expect(
        tester.getTopLeft(newerARow).dy,
        lessThan(tester.getTopLeft(newerBRow).dy),
        reason: 'las personas se ordenan dentro de su semana, no como chips',
      );

      for (final entry in <(String, String, String)>[
        ('newer-worker-a', 'method-transfer', r'$38.500'),
        ('newer-worker-b', 'method-transfer', r'$94.500'),
        ('older-worker', 'method-cash', r'$20.000'),
      ]) {
        final row = find.byKey(
          ValueKey<String>('payroll-payment-row-${entry.$1}'),
        );
        final method = find.descendant(
          of: row,
          matching: find.byKey(
            ValueKey<String>('payroll-payment-method-${entry.$1}'),
          ),
        );
        expect(method, findsOneWidget);
        expect(
          tester.widget<VbShortSelect<String?>>(method).value,
          entry.$2,
        );
        expect(
          find.descendant(of: row, matching: find.text(entry.$3)),
          findsWidgets,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'batch conserva todas las filas mientras un detalle se edita inline',
      (tester) async {
    final first = _target(
      id: 'locked-first',
      voucherId: 'voucher-locked',
      name: 'Fernando Tapia',
    );
    final second = _target(
      id: 'locked-second',
      voucherId: 'voucher-locked',
      name: 'Vicente Díaz',
    );
    final controller = PayrollPaymentWorkspaceController(
      request: PayrollPaymentWorkspaceRequest.batch(
        targets: <PayrollPaymentTarget>[second, first],
        paymentMethods: _paymentMethods,
      ),
      additionalConceptsSupported: true,
    );
    addTearDown(controller.dispose);
    controller.addPaymentLeg(
      first.targetId,
      const PayrollPaymentLeg.payment(
        legId: 'complete-salary',
        amountClp: 100000,
        paymentMethodId: 'method-transfer',
        paymentAccountId: 'account-bank',
        paymentDate: PayrollCivilDate(2026, 8, 11),
      ),
    );

    await pumpWorkspace(
      tester,
      controller: controller,
      size: const Size(834, 900),
      expenseAccounts: const <PayrollExpenseAccountOption>[
        PayrollExpenseAccountOption(
          accountId: 'workshop-supplies',
          label: '5108 · Insumos del taller',
        ),
      ],
    );

    final batchSave = find.byKey(
      const ValueKey<String>('payroll-payment-save-batch'),
    );
    final firstDetails = find.byKey(
      const ValueKey<String>('payroll-payment-details-locked-first'),
    );
    final secondDetails = find.byKey(
      const ValueKey<String>('payroll-payment-details-locked-second'),
    );
    final firstRow = find.byKey(
      const ValueKey<String>('payroll-payment-row-locked-first'),
    );
    final secondRow = find.byKey(
      const ValueKey<String>('payroll-payment-row-locked-second'),
    );
    expect(batchSave, findsOneWidget);
    expect(firstRow, findsOneWidget);
    expect(secondRow, findsOneWidget);

    await tester.tap(firstDetails);
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey<String>('payroll-payment-editor-locked-first'),
      ),
      findsOneWidget,
    );
    expect(firstRow, findsOneWidget);
    expect(secondRow, findsOneWidget);

    await tester.ensureVisible(find.text('Agregar parte'));
    await tester.tap(find.text('Agregar parte'));
    await tester.pumpAndSettle();

    final legEditor = find.byKey(
      const ValueKey<String>('payroll-payment-inline-leg-editor'),
    );
    expect(legEditor, findsOneWidget);
    expect(firstRow, findsOneWidget);
    expect(secondRow, findsOneWidget);
    expect(legEditor, findsOneWidget);
    expect(tester.widget<TextButton>(firstDetails).onPressed, isNull);
    expect(tester.widget<TextButton>(secondDetails).onPressed, isNull);

    final cancelLeg = find.descendant(
      of: legEditor,
      matching: find.widgetWithText(TextButton, 'Cancelar'),
    );
    await bringIntoViewport(tester, cancelLeg);
    await tester.tap(cancelLeg);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Agregar concepto'));
    await tester.tap(find.text('Agregar concepto'));
    await tester.pumpAndSettle();

    final conceptEditor = find.byKey(
      const ValueKey<String>('payroll-payment-inline-concept-editor'),
    );
    expect(conceptEditor, findsOneWidget);
    expect(firstRow, findsOneWidget);
    expect(secondRow, findsOneWidget);
    expect(conceptEditor, findsOneWidget);

    final cancelConcept = find.descendant(
      of: conceptEditor,
      matching: find.widgetWithText(TextButton, 'Cancelar'),
    );
    await bringIntoViewport(tester, cancelConcept);
    await tester.tap(cancelConcept);
    await tester.pumpAndSettle();
    expect(firstRow, findsOneWidget);
    expect(secondRow, findsOneWidget);
    expect(tester.widget<TextButton>(firstDetails).onPressed, isNotNull);
    expect(tester.widget<TextButton>(secondDetails).onPressed, isNotNull);

    await tester.tap(firstDetails);
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey<String>('payroll-payment-editor-locked-first'),
      ),
      findsNothing,
    );
    await tester.tap(secondDetails);
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey<String>('payroll-payment-editor-locked-second'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'batch combina formas y guarda todos los trabajadores en una llamada atómica',
      (tester) async {
    final first = _target(
      id: 'first',
      voucherId: 'voucher-new',
      name: 'Fernando Tapia',
      balanceClp: 50000,
      periodStart: const PayrollCivilDate(2026, 8, 3),
      periodEnd: const PayrollCivilDate(2026, 8, 9),
    );
    final second = _target(
      id: 'second',
      voucherId: 'voucher-new',
      name: 'Vicente Díaz',
      balanceClp: 50000,
      periodStart: const PayrollCivilDate(2026, 8, 3),
      periodEnd: const PayrollCivilDate(2026, 8, 9),
    );
    final savedBatches = <List<PayrollPaymentTargetSaveCommand>>[];
    final savedOperationKeys = <String>[];
    final controller = PayrollPaymentWorkspaceController(
      request: PayrollPaymentWorkspaceRequest.batch(
        targets: <PayrollPaymentTarget>[second, first],
        paymentMethods: _paymentMethods,
      ),
      onSaveBatch: (commands, operationKey) async {
        savedBatches.add(commands);
        savedOperationKeys.add(operationKey);
      },
      operationKeyFactory: () => 'stable-operation-key',
    );
    addTearDown(controller.dispose);
    controller
      ..replaceSalaryLegs(
        first.targetId,
        const <PayrollPaymentLeg>[
          PayrollPaymentLeg.payment(
            legId: 'first-transfer',
            amountClp: 30000,
            paymentMethodId: 'method-transfer',
            paymentAccountId: 'account-bank',
            paymentDate: PayrollCivilDate(2026, 8, 11),
            reference: 'statement-row-1',
          ),
          PayrollPaymentLeg.payment(
            legId: 'first-cash',
            amountClp: 20000,
            paymentMethodId: 'method-cash',
            paymentAccountId: 'account-cash',
            paymentDate: PayrollCivilDate(2026, 8, 11),
          ),
        ],
      )
      ..replaceSalaryLegs(
        second.targetId,
        const <PayrollPaymentLeg>[
          PayrollPaymentLeg.payment(
            legId: 'second-transfer',
            amountClp: 50000,
            paymentMethodId: 'method-transfer',
            paymentAccountId: 'account-bank',
            paymentDate: PayrollCivilDate(2026, 8, 11),
            reference: 'statement-row-2',
          ),
        ],
      );

    await pumpWorkspace(
      tester,
      controller: controller,
      size: const Size(1440, 900),
    );

    expect(
      find.byKey(const ValueKey<String>('payroll-payment-row-first')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('payroll-payment-row-second')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
        const ValueKey<String>('payroll-payment-save-batch'),
      ),
    );
    await tester.pumpAndSettle();

    expect(savedBatches, hasLength(1));
    expect(savedOperationKeys, <String>['stable-operation-key']);
    expect(
      savedBatches.single.map((command) => command.target.targetId).toSet(),
      <String>{first.targetId, second.targetId},
    );
    final firstCommand = savedBatches.single.singleWhere(
      (command) => command.target.targetId == first.targetId,
    );
    final secondCommand = savedBatches.single.singleWhere(
      (command) => command.target.targetId == second.targetId,
    );
    expect(firstCommand.salaryLegs, hasLength(2));
    expect(secondCommand.salaryLegs, hasLength(1));
    expect(controller.isSaved(first.targetId), isTrue);
    expect(controller.isSaved(second.targetId), isTrue);
    expect(
      find.byKey(const ValueKey<String>('payroll-payment-row-first')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('payroll-payment-row-second')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'batch habilita Registrar con la transferencia completa aunque la referencia bancaria quede vacía',
      (tester) async {
    final savedBatches = <List<PayrollPaymentTargetSaveCommand>>[];
    final controller = PayrollPaymentWorkspaceController(
      request: PayrollPaymentWorkspaceRequest.batch(
        targets: <PayrollPaymentTarget>[
          _target(
            id: 'default-without-bank-reference',
            voucherId: 'voucher-confirmed',
            name: 'Fernando Tapia',
            balanceClp: 72000,
          ),
        ],
        paymentMethods: const <PayrollPaymentMethodOption>[
          PayrollPaymentMethodOption(
            methodId: 'method-transfer',
            label: 'Transferencia',
            code: 'transfer',
            accountId: 'account-bank',
            requiresReference: true,
          ),
        ],
      ),
      onSaveBatch: (commands, _) async => savedBatches.add(commands),
    );
    addTearDown(controller.dispose);

    await pumpWorkspace(
      tester,
      controller: controller,
      size: const Size(1440, 900),
    );

    final save = find.byKey(
      const ValueKey<String>('payroll-payment-save-batch'),
    );
    expect(save, findsOneWidget);
    expect(tester.widget<InkWell>(save).onTap, isNotNull);
    expect(find.text('1 pagos listos · \$72.000'), findsOneWidget);
    expect(find.text('Este método exige una referencia.'), findsNothing);

    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(savedBatches, hasLength(1));
    expect(
      savedBatches.single.single.salarySplits.single,
      isNot(contains('reference')),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'fila precargada muestra Desde cartola y conserva Dividir o ajustar',
      (tester) async {
    const evidence = PayrollOcrStatementEvidence(
      sourceRowId: 'statement-row-prefilled',
      fingerprint: 'statement-fingerprint-prefilled',
      ordinal: 1,
      bookingDate: PayrollCivilDate(2026, 8, 11),
      direction: PayrollStatementMovementDirection.outgoing,
      amountClp: 71750,
      description: 'App-traspaso A: Vicente Díaz Internet',
      suggestedErpAccountId: 'account-bank',
    );
    final target = _target(
      id: 'ocr-prefilled',
      voucherId: 'voucher-confirmed',
      name: 'Vicente Díaz',
      balanceClp: 71750,
      candidates: const <PayrollOcrPaymentCandidate>[
        PayrollOcrPaymentCandidate(
          candidateId: 'ocr-candidate-prefilled',
          evidence: evidence,
          selectedForPrefill: true,
          suggestedPaymentMethodId: 'method-transfer',
          suggestedPaymentAccountId: 'account-bank',
        ),
      ],
    );
    final controller = PayrollPaymentWorkspaceController(
      request: PayrollPaymentWorkspaceRequest.batch(
        targets: <PayrollPaymentTarget>[target],
        paymentMethods: _paymentMethods,
      ),
    );
    addTearDown(controller.dispose);

    await pumpWorkspace(
      tester,
      controller: controller,
      size: const Size(1440, 900),
    );

    final row = find.byKey(
      const ValueKey<String>('payroll-payment-row-ocr-prefilled'),
    );
    final badge = find.descendant(
      of: row,
      matching: find.byKey(
        const ValueKey<String>('payroll-payment-ocr-prefill-ocr-prefilled'),
      ),
    );
    expect(badge, findsOneWidget);
    expect(
      find.descendant(of: badge, matching: find.byType(VbStatusBadge)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('Desde cartola')),
      findsOneWidget,
    );

    final details = find.byKey(
      const ValueKey<String>('payroll-payment-details-ocr-prefilled'),
    );
    expect(find.descendant(of: row, matching: details), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('Dividir o ajustar')),
        findsOneWidget);
    await tester.tap(details);
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey<String>('payroll-payment-editor-ocr-prefilled'),
      ),
      findsOneWidget,
    );
    expect(find.text('Cómo se paga el sueldo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'batch cambia sólo la acción de la fila modificada a Editar ajuste',
      (tester) async {
    final adjusted = _target(
      id: 'manually-adjusted',
      voucherId: 'voucher-adjusted',
      name: 'Vicente Díaz',
      balanceClp: 135000,
    );
    final untouched = _target(
      id: 'untouched-default',
      voucherId: 'voucher-adjusted',
      name: 'Lucas Pacheco',
      balanceClp: 36400,
    );
    final controller = PayrollPaymentWorkspaceController(
      request: PayrollPaymentWorkspaceRequest.batch(
        targets: <PayrollPaymentTarget>[adjusted, untouched],
        paymentMethods: _paymentMethods,
      ),
    );
    addTearDown(controller.dispose);

    controller.updatePaymentLeg(
      adjusted.targetId,
      const PayrollPaymentLeg.payment(
        legId: 'simple:manually-adjusted',
        amountClp: 135000,
        paymentMethodId: 'method-transfer',
        paymentAccountId: 'account-bank',
        paymentDate: PayrollCivilDate(2026, 8, 10),
        reference: 'Referencia corregida',
      ),
    );

    await pumpWorkspace(
      tester,
      controller: controller,
      size: const Size(1440, 900),
    );

    final adjustedRow = find.byKey(
      const ValueKey<String>('payroll-payment-row-manually-adjusted'),
    );
    final untouchedRow = find.byKey(
      const ValueKey<String>('payroll-payment-row-untouched-default'),
    );
    expect(
      find.descendant(of: adjustedRow, matching: find.text('Editar ajuste')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: adjustedRow,
        matching: find.text('Dividir o ajustar'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: untouchedRow,
        matching: find.text('Dividir o ajustar'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: untouchedRow, matching: find.text('Editar ajuste')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'batch bloquea pagos de semanas sin aprobar y permite aprobarlas sin perder filas',
      (tester) async {
    final approvalCalls =
        <({List<PayrollPaymentWeekApprovalRequest> requests, String key})>[];
    final controller = PayrollPaymentWorkspaceController(
      request: PayrollPaymentWorkspaceRequest.batch(
        targets: <PayrollPaymentTarget>[
          _target(
            id: 'draft-worker',
            voucherId: 'voucher-draft',
            name: 'Vicente Díaz',
            voucherStatus: 'draft',
            reconciliationVersion: 7,
          ),
          _target(
            id: 'confirmed-worker',
            voucherId: 'voucher-confirmed',
            name: 'Lucas Pacheco',
            voucherStatus: 'confirmed',
            reconciliationVersion: 4,
          ),
        ],
        paymentMethods: _paymentMethods,
      ),
      onApproveWeeks: (requests, operationKey) async {
        approvalCalls.add((requests: requests, key: operationKey));
        return const <PayrollPaymentWeekApprovalResult>[
          PayrollPaymentWeekApprovalResult(
            voucherId: 'voucher-draft',
            reconciliationVersion: 8,
          ),
        ];
      },
    );
    addTearDown(controller.dispose);

    await pumpWorkspace(
      tester,
      controller: controller,
      size: const Size(1440, 900),
    );

    final draftWeek = find.byKey(
      const ValueKey<String>('payroll-payment-week-voucher-draft'),
    );
    final approval = find.byKey(
      const ValueKey<String>('payroll-payment-approve-weeks'),
    );
    final save = find.byKey(
      const ValueKey<String>('payroll-payment-save-batch'),
    );
    expect(
      find.descendant(of: draftWeek, matching: find.text('Sin aprobar')),
      findsOneWidget,
    );
    expect(approval, findsOneWidget);
    expect(find.text('Aprobar 1 semana'), findsOneWidget);
    expect(tester.widget<InkWell>(save).onTap, isNull);
    expect(
      find.byKey(const ValueKey<String>('payroll-payment-row-draft-worker')),
      findsOneWidget,
    );
    expect(
      find.byKey(
          const ValueKey<String>('payroll-payment-row-confirmed-worker')),
      findsOneWidget,
    );

    await tester.tap(approval);
    await tester.pumpAndSettle();

    expect(approvalCalls, hasLength(1));
    expect(approvalCalls.single.requests, hasLength(1));
    expect(
      approvalCalls.single.requests.single.voucherId,
      'voucher-draft',
    );
    expect(
      approvalCalls.single.requests.single.expectedReconciliationVersion,
      7,
    );
    expect(find.text('Sin aprobar'), findsNothing);
    expect(approval, findsNothing);
    expect(tester.widget<InkWell>(save).onTap, isNotNull);
    expect(find.text('2 pagos listos · \$200.000'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('payroll-payment-row-draft-worker')),
      findsOneWidget,
    );
    expect(
      find.byKey(
          const ValueKey<String>('payroll-payment-row-confirmed-worker')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'reparte un movimiento de 80 mil entre sueldo y concepto sin perder evidencia',
      (tester) async {
    const evidence = PayrollOcrStatementEvidence(
      sourceRowId: 'statement-row-80',
      fingerprint: 'statement-fingerprint-80',
      ordinal: 1,
      bookingDate: PayrollCivilDate(2026, 8, 11),
      direction: PayrollStatementMovementDirection.outgoing,
      amountClp: 80000,
      description: 'Transferencia a Fernando',
      suggestedErpAccountId: 'account-bank',
    );
    final target = _target(
      id: 'salary-plus-supplies',
      voucherId: 'voucher-new',
      name: 'Fernando Tapia',
      balanceClp: 70000,
      candidates: const <PayrollOcrPaymentCandidate>[
        PayrollOcrPaymentCandidate(
          candidateId: 'salary-plus-supplies-candidate',
          evidence: evidence,
          selectedForPrefill: true,
          suggestedPaymentMethodId: 'method-transfer',
          suggestedPaymentAccountId: 'account-bank',
        ),
      ],
    );
    final savedBatches = <List<PayrollPaymentTargetSaveCommand>>[];
    final controller = PayrollPaymentWorkspaceController(
      request: PayrollPaymentWorkspaceRequest.batch(
        targets: <PayrollPaymentTarget>[target],
        paymentMethods: _paymentMethods,
      ),
      additionalConceptsSupported: true,
      onSaveBatch: (commands, _) async => savedBatches.add(commands),
    );
    addTearDown(controller.dispose);

    await pumpWorkspace(
      tester,
      controller: controller,
      size: const Size(834, 900),
      expenseAccounts: List<PayrollExpenseAccountOption>.generate(
        32,
        (index) => PayrollExpenseAccountOption(
          accountId: index == 0 ? 'workshop-supplies' : 'expense-$index',
          label: index == 0
              ? '5108 · Insumos del taller'
              : '51${index.toString().padLeft(2, '0')} · Gasto $index',
        ),
      ),
    );

    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'payroll-payment-details-salary-plus-supplies',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.draftFor(target.targetId).salaryAppliedClp, 70000);
    expect(
        controller.availableEvidenceAmount(target.targetId, evidence), 10000);
    final baselineModalBarrierCount =
        find.byType(ModalBarrier).evaluate().length;

    await tester.ensureVisible(find.text('Agregar concepto'));
    await tester.tap(find.text('Agregar concepto'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey<String>('payroll-payment-inline-concept-editor'),
      ),
      findsOneWidget,
    );
    expect(find.byType(Dialog), findsNothing);
    expect(
      find.byType(ModalBarrier),
      findsNWidgets(baselineModalBarrierCount),
    );
    final conceptFields = find.byType(TextField);
    expect(conceptFields, findsNWidgets(2));
    await tester.enterText(conceptFields.at(0), 'Cajas para el taller');
    await tester.enterText(conceptFields.at(1), '10000');
    await tester.tap(find.text('No, se suma aparte'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Agregar'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey<String>('payroll-payment-inline-leg-editor'),
      ),
      findsOneWidget,
    );
    expect(find.byType(Dialog), findsNothing);
    expect(
      find.byType(ModalBarrier),
      findsNWidgets(baselineModalBarrierCount),
    );

    final evidenceSelect = find.byKey(
      const ValueKey<String>('payroll-payment-evidence-select'),
    );
    expect(evidenceSelect, findsOneWidget);
    await tester.tap(evidenceSelect);
    await tester.pumpAndSettle();
    expect(find.text(r'$10.000 disponibles'), findsWidgets);
    await tester.tap(find.text(r'$10.000 disponibles').last);
    await tester.pumpAndSettle();
    final savePart = find.widgetWithText(FilledButton, 'Guardar parte');
    await bringIntoViewport(tester, savePart);
    await tester.tap(savePart);
    await tester.pumpAndSettle();

    final concept =
        controller.draftFor(target.targetId).additionalConcepts.single;
    expect(
      concept.disposition,
      PayrollAdditionalConceptDisposition.additional,
    );
    expect(concept.paymentLegs.single.amountClp, 10000);
    expect(concept.paymentLegs.single.ocrEvidence, same(evidence));
    expect(controller.availableEvidenceAmount(target.targetId, evidence), 0);
    expect(controller.validationFor(target.targetId).isValid, isTrue);

    await tester.tap(
      find.byKey(
        const ValueKey<String>('payroll-payment-save-batch'),
      ),
    );
    await tester.pumpAndSettle();
    expect(savedBatches, hasLength(1));
    expect(savedBatches.single, hasLength(1));
    expect(
      savedBatches.single.single.additionalConcepts.single.paymentLegs.single
          .ocrEvidence,
      same(evidence),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'guardar concepto con referencia enfocada desacopla el editor antes de cerrarlo',
      (tester) async {
    final target = _target(
      id: 'focused-concept-reference',
      voucherId: 'voucher-focused-concept',
      name: 'Fernando Tapia',
      balanceClp: 72000,
    );
    final controller = PayrollPaymentWorkspaceController(
      request: PayrollPaymentWorkspaceRequest.single(
        target: target,
        paymentMethods: _paymentMethods,
      ),
      additionalConceptsSupported: true,
    );
    addTearDown(controller.dispose);

    await pumpWorkspace(
      tester,
      controller: controller,
      size: const Size(834, 900),
      expenseAccounts: const <PayrollExpenseAccountOption>[
        PayrollExpenseAccountOption(
          accountId: 'workshop-supplies',
          label: '5108 · Insumos del taller',
        ),
      ],
    );

    await tester.tap(find.text('Agregar concepto'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(
        const ValueKey<String>('payroll-concept-description-input'),
      ),
      'Cajas para el taller',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('payroll-concept-amount-input')),
      '10000',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Agregar'));
    await tester.pumpAndSettle();

    final reference = find.byKey(
      const ValueKey<String>('payroll-payment-leg-reference-input'),
    );
    await tester.enterText(reference, 'APP-TRASPASO-TEST');
    final editable = find.descendant(
      of: reference,
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);

    final savePart = find.widgetWithText(FilledButton, 'Guardar parte');
    final button = tester.widget<FilledButton>(savePart);
    button.onPressed!.call();

    // The focused macOS EditableText remains mounted through its detach frame.
    expect(
      find.byKey(
        const ValueKey<String>('payroll-payment-inline-leg-editor'),
      ),
      findsOneWidget,
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(
        const ValueKey<String>('payroll-payment-inline-leg-editor'),
      ),
      findsNothing,
    );
    expect(
      controller
          .draftFor(target.targetId)
          .additionalConcepts
          .single
          .paymentLegs
          .single
          .reference,
      'APP-TRASPASO-TEST',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '72 mil cubiertos como 62 mil de sueldo y 10 mil incluidos dejan cero pendiente',
      (tester) async {
    final target = _target(
      id: 'fernando-included-expense',
      voucherId: 'voucher-week-27',
      name: 'Fernando Tapia',
      balanceClp: 72000,
    );
    final controller = PayrollPaymentWorkspaceController(
      request: PayrollPaymentWorkspaceRequest.batch(
        targets: <PayrollPaymentTarget>[target],
        paymentMethods: _paymentMethods,
      ),
      additionalConceptsSupported: true,
    );
    addTearDown(controller.dispose);
    controller
      ..replaceSalaryLegs(
        target.targetId,
        const <PayrollPaymentLeg>[
          PayrollPaymentLeg.payment(
            legId: 'salary-cash-50',
            amountClp: 50000,
            paymentMethodId: 'method-cash',
            paymentAccountId: 'account-cash',
            paymentDate: PayrollCivilDate(2026, 8, 11),
          ),
          PayrollPaymentLeg.payment(
            legId: 'salary-transfer-12',
            amountClp: 12000,
            paymentMethodId: 'method-transfer',
            paymentAccountId: 'account-bank',
            paymentDate: PayrollCivilDate(2026, 8, 11),
            reference: 'App-traspaso A: Fernando Tapia Internet',
          ),
        ],
      )
      ..addConcept(
        target.targetId,
        PayrollAdditionalConcept(
          conceptId: 'plastic-boxes',
          type: PayrollAdditionalConceptType.expenseReimbursement,
          description: 'Reembolso por cajas plásticas',
          amountClp: 10000,
          expenseAccountId: 'account-workshop-supplies',
          disposition:
              PayrollAdditionalConceptDisposition.includedInPayrollTotal,
          paymentLegs: const <PayrollPaymentLeg>[
            PayrollPaymentLeg.payment(
              legId: 'boxes-transfer-10',
              amountClp: 10000,
              paymentMethodId: 'method-transfer',
              paymentAccountId: 'account-bank',
              paymentDate: PayrollCivilDate(2026, 8, 11),
              reference: 'App-traspaso A: Fernando Tapia Internet',
            ),
          ],
        ),
      );

    final validation = controller.validationFor(target.targetId);
    expect(validation.salaryAppliedClp, 62000);
    expect(validation.includedConceptsTotalClp, 10000);
    expect(validation.totalObligationClp, 72000);
    expect(validation.appliedTotalClp, 72000);
    expect(validation.payrollRemainingClp, 0);
    expect(validation.remainingClp, 0);
    expect(validation.isValid, isTrue);

    await pumpWorkspace(
      tester,
      controller: controller,
      size: const Size(1440, 900),
    );

    final row = find.byKey(
      const ValueKey<String>(
        'payroll-payment-row-fernando-included-expense',
      ),
    );
    expect(
        find.descendant(of: row, matching: find.text(r'$0')), findsOneWidget);
    expect(find.text(r'1 pagos listos · $72.000'), findsOneWidget);

    final details = find.byKey(
      const ValueKey<String>(
        'payroll-payment-details-fernando-included-expense',
      ),
    );
    await bringIntoViewport(tester, details);
    await tester.tap(details);
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey<String>(
          'payroll-payment-editor-fernando-included-expense',
        ),
      ),
      findsOneWidget,
    );
    await tester.drag(
      find.byKey(const ValueKey<String>('payroll-payment-batch-list')),
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.text('TOTAL A ENTREGAR', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('CUBIERTO AHORA', skipOffstage: false), findsOneWidget);
    expect(
      find.text('QUEDARÁ PENDIENTE', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text('INCLUIDO COMO GASTO', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Incluido en el total de la nómina',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final width in <double>[1440, 834]) {
    testWidgets('batch renderiza sin overflow a ${width.toInt()} px',
        (tester) async {
      final first = _target(
        id: 'responsive-first',
        voucherId: 'voucher-new',
        name: 'Fernando José Tapia Carrillo',
        balanceClp: 125000,
        periodStart: const PayrollCivilDate(2026, 8, 3),
        periodEnd: const PayrollCivilDate(2026, 8, 9),
      );
      final controller = PayrollPaymentWorkspaceController(
        request: PayrollPaymentWorkspaceRequest.batch(
          targets: <PayrollPaymentTarget>[
            _target(
              id: 'responsive-older',
              voucherId: 'voucher-old',
              name: 'Rodrigo Guillermo Nieto',
            ),
            _target(
              id: 'responsive-second',
              voucherId: 'voucher-new',
              name: 'Vicente Díaz',
              periodStart: const PayrollCivilDate(2026, 8, 3),
              periodEnd: const PayrollCivilDate(2026, 8, 9),
            ),
            first,
          ],
          paymentMethods: _paymentMethods,
        ),
      );
      addTearDown(controller.dispose);
      controller
        ..addPaymentLeg(
          first.targetId,
          const PayrollPaymentLeg.payment(
            legId: 'responsive-transfer',
            amountClp: 75000,
            paymentMethodId: 'method-transfer',
            paymentAccountId: 'account-bank',
            paymentDate: PayrollCivilDate(2026, 8, 11),
            reference: 'statement-row-responsive',
          ),
        )
        ..addPaymentLeg(
          first.targetId,
          const PayrollPaymentLeg.payment(
            legId: 'responsive-cash',
            amountClp: 50000,
            paymentMethodId: 'method-cash',
            paymentAccountId: 'account-cash',
            paymentDate: PayrollCivilDate(2026, 8, 11),
          ),
        );

      await pumpWorkspace(
        tester,
        controller: controller,
        size: Size(width, 900),
      );

      expect(
        find.byKey(
          const ValueKey<String>('payroll-payment-batch-list'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('payroll-payment-week-navigator'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey<String>('payroll-payment-row-responsive-first'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('payroll-payment-row-responsive-second'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('payroll-payment-row-responsive-older'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'batch a 390 recompone todas las filas en una lista vertical sin paneo',
      (tester) async {
    final controller = PayrollPaymentWorkspaceController(
      request: PayrollPaymentWorkspaceRequest.batch(
        targets: <PayrollPaymentTarget>[
          _target(
            id: 'phone-older',
            voucherId: 'voucher-old',
            name: 'Rodrigo Guillermo Nieto',
            balanceClp: 20000,
          ),
          _target(
            id: 'phone-vicente',
            voucherId: 'voucher-new',
            name: 'Vicente Díaz',
            balanceClp: 94500,
            periodStart: const PayrollCivilDate(2026, 8, 3),
            periodEnd: const PayrollCivilDate(2026, 8, 9),
          ),
          _target(
            id: 'phone-fernando',
            voucherId: 'voucher-new',
            name: 'Fernando José Tapia Carrillo',
            balanceClp: 125000,
            periodStart: const PayrollCivilDate(2026, 8, 3),
            periodEnd: const PayrollCivilDate(2026, 8, 9),
          ),
        ],
        paymentMethods: _paymentMethods,
      ),
    );
    addTearDown(controller.dispose);
    controller
      ..setSimplePaymentMethod('phone-older', 'method-cash')
      ..setSimplePaymentMethod('phone-vicente', 'method-transfer')
      ..setSimplePaymentMethod('phone-fernando', 'method-transfer');

    await pumpWorkspace(
      tester,
      controller: controller,
      size: const Size(390, 844),
    );

    final list = find.byKey(
      const ValueKey<String>('payroll-payment-batch-list'),
    );
    final listScroll = find.descendant(
      of: list,
      matching: find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.axis == Axis.vertical,
      ),
    );
    expect(list, findsOneWidget);
    expect(listScroll, findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>('payroll-payment-week-navigator'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: list,
        matching: find.byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
        ),
      ),
      findsNothing,
    );

    for (final entry in <(String, String, String)>[
      ('phone-fernando', 'Fernando José Tapia Carrillo', r'$125.000'),
      ('phone-vicente', 'Vicente Díaz', r'$94.500'),
      ('phone-older', 'Rodrigo Guillermo Nieto', r'$20.000'),
    ]) {
      final row = find.byKey(
        ValueKey<String>('payroll-payment-row-${entry.$1}'),
      );
      await tester.scrollUntilVisible(
        row,
        250,
        scrollable: listScroll,
      );
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text(entry.$2)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text(entry.$3)),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.byKey(
            ValueKey<String>('payroll-payment-method-${entry.$1}'),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.byKey(
            ValueKey<String>('payroll-payment-details-${entry.$1}'),
          ),
        ),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(const ValueKey<String>('payroll-payment-save-batch')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'un lote comprometido con recibo inválido avisa y no ofrece reintento',
      (tester) async {
    var saveCalls = 0;
    final controller = PayrollPaymentWorkspaceController(
      request: PayrollPaymentWorkspaceRequest.batch(
        targets: <PayrollPaymentTarget>[
          _target(
            id: 'committed-worker',
            voucherId: 'committed-voucher',
            name: 'Fernando Tapia',
          ),
        ],
        paymentMethods: _paymentMethods,
      ),
      operationKeyFactory: () => 'stable-operation-key',
      onSaveBatch: (_, operationKey) async {
        saveCalls += 1;
        throw PayrollPaymentCommittedUnverifiedException(
          operationKey: operationKey,
        );
      },
    );
    addTearDown(controller.dispose);

    await pumpWorkspace(
      tester,
      controller: controller,
      size: const Size(1440, 900),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('payroll-payment-save-batch')),
    );
    await tester.pumpAndSettle();

    expect(saveCalls, 1);
    expect(controller.isBatchSaved, isTrue);
    expect(controller.isBatchCommittedUnverified, isTrue);
    expect(find.textContaining('El servidor registró los pagos'), findsOne);
    expect(find.textContaining('No vuelvas a registrarlos'), findsOne);
    expect(find.text('Registrar 1 pagos'), findsNothing);
    expect(find.text('Volver a Nóminas'), findsOne);

    await tester.tap(find.text('Volver a Nóminas'));
    await tester.pump();
    expect(saveCalls, 1);
  });
}

const List<PayrollPaymentMethodOption> _paymentMethods =
    <PayrollPaymentMethodOption>[
  PayrollPaymentMethodOption(
    methodId: 'method-transfer',
    label: 'Transferencia',
    code: 'transfer',
    accountId: 'account-bank',
    accountLabel: 'Banco principal',
  ),
  PayrollPaymentMethodOption(
    methodId: 'method-cash',
    label: 'Efectivo',
    code: 'cash',
    accountId: 'account-cash',
    accountLabel: 'Caja',
  ),
];

PayrollPaymentTarget _target({
  required String id,
  required String voucherId,
  required String name,
  int balanceClp = 100000,
  PayrollCivilDate periodStart = const PayrollCivilDate(2026, 7, 27),
  PayrollCivilDate periodEnd = const PayrollCivilDate(2026, 8, 2),
  List<PayrollOcrPaymentCandidate> candidates = const [],
  String voucherStatus = 'confirmed',
  int reconciliationVersion = 1,
}) {
  return PayrollPaymentTarget(
    targetId: id,
    voucherId: voucherId,
    voucherLineId: 'line-$id',
    employeeId: 'employee-$id',
    employeeName: name,
    periodStart: periodStart,
    periodEnd: periodEnd,
    salaryBalanceClp: balanceClp,
    reconciliationVersion: reconciliationVersion,
    voucherStatus: voucherStatus,
    ocrCandidates: candidates,
  );
}
