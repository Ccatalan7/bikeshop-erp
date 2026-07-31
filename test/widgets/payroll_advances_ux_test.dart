import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/hr/models/payroll_voucher.dart';
import 'package:vinabike_erp/modules/hr/widgets/payroll_advance_entry.dart';
import 'package:vinabike_erp/modules/hr/widgets/payroll_advances_view.dart';

void main() {
  Future<void> pumpSurface(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('empty advances explains the state and starts the first entry',
      (tester) async {
    var registrations = 0;
    await pumpSurface(
      tester,
      PayrollAdvancesView(
        advances: const [],
        employees: const [],
        onRegister: () => registrations++,
      ),
    );

    expect(find.text('No hay anticipos abiertos.'), findsOneWidget);
    expect(
      find.textContaining('libro del trabajador'),
      findsOneWidget,
    );
    final action = find.byKey(
      const Key('payroll-advances-empty-register'),
    );
    expect(action, findsOneWidget);
    expect(tester.getSize(action).height, greaterThanOrEqualTo(48));

    await tester.tap(action);
    expect(registrations, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a growing worker list becomes searchable', (tester) async {
    final employees = <Map<String, dynamic>>[
      for (var index = 1; index <= 8; index++)
        <String, dynamic>{
          'id': 'worker-$index',
          'first_name': 'Trabajador',
          'last_name': '$index',
          'rut': '11.111.111-$index',
          'status': 'active',
          'preferred_payment_method_id': 'method-transfer',
        },
    ];

    await pumpSurface(
      tester,
      PayrollAdvanceEntry(
        employees: employees,
        paymentMethods: const [
          {
            'id': 'method-transfer',
            'name': 'Transferencia',
            'is_active': true,
            'account_id': 'account-transfer',
          },
        ],
      ),
    );

    final search = find.byKey(
      const Key('payroll-advance-employee-search'),
    );
    expect(search, findsOneWidget);
    expect(
      find.byKey(const Key('payroll-advance-employee-select')),
      findsNothing,
    );
    expect(tester.getSize(search).height, greaterThanOrEqualTo(48));

    await tester.tap(search);
    await tester.pumpAndSettle();
    final searchField = find.descendant(
      of: search,
      matching: find.byType(TextField),
    );
    await tester.enterText(searchField, 'Trabajador 8');
    await tester.pumpAndSettle();

    expect(
      find.text('Trabajador 8 · 11.111.111-8').hitTestable(),
      findsWidgets,
    );
    expect(
      find.text('Trabajador 1 · 11.111.111-1').hitTestable(),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the locked compact sheet does not advertise dragging',
      (tester) async {
    await pumpSurface(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showPayrollAdvanceEntry(
            context: context,
            employees: const [
              {
                'id': 'worker-1',
                'first_name': 'Trabajador',
                'last_name': 'Uno',
                'status': 'active',
              },
            ],
            paymentMethods: const [
              {
                'id': 'method-transfer',
                'name': 'Transferencia',
                'is_active': true,
                'account_id': 'account-transfer',
              },
            ],
          ),
          child: const Text('Abrir anticipo'),
        ),
      ),
    );

    await tester.tap(find.text('Abrir anticipo'));
    await tester.pumpAndSettle();
    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(sheet.enableDrag, isFalse);
    expect(sheet.showDragHandle, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a person-scoped entry starts with that worker selected',
      (tester) async {
    await pumpSurface(
      tester,
      const PayrollAdvanceEntry(
        initialEmployeeId: 'worker-2',
        employees: [
          {
            'id': 'worker-1',
            'first_name': 'Ana',
            'last_name': 'Alarcón',
            'status': 'active',
          },
          {
            'id': 'worker-2',
            'first_name': 'Beto',
            'last_name': 'Bravo',
            'status': 'active',
            'preferred_payment_method_id': 'method-transfer',
          },
        ],
        paymentMethods: [
          {
            'id': 'method-transfer',
            'name': 'Transferencia',
            'is_active': true,
            'account_id': 'account-transfer',
          },
        ],
      ),
    );

    final employeeSelector = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('payroll-advance-employee-select')),
    );
    expect(employeeSelector.initialValue, 'worker-2');
    expect(
      find.textContaining('Registra dinero entregado a Beto Bravo'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(
              const ValueKey<String>(
                'payroll-advance-method-method-transfer',
              ),
            ),
          )
          .initialValue,
      'method-transfer',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated method names identify their accounting account',
      (tester) async {
    await pumpSurface(
      tester,
      const PayrollAdvanceEntry(
        line: PayrollVoucherLine(
          voucherId: 'voucher-1',
          employeeId: 'worker-1',
          employeeName: 'Trabajador Uno',
        ),
        paymentMethods: [
          {
            'id': 'transfer-bank',
            'name': 'Transferencia',
            'is_active': true,
            'account_id': 'account-bank',
            'account_code': '110101',
            'account_name': 'Banco principal',
          },
          {
            'id': 'transfer-wallet',
            'name': 'Transferencia',
            'is_active': true,
            'account_id': 'account-wallet',
            'account_code': '110102',
            'account_name': 'Billetera digital',
          },
        ],
      ),
    );

    final methodField = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    final labels = methodField.items!
        .map((item) => (item.child as Text).data)
        .toList(growable: false);
    expect(
      labels,
      orderedEquals(const [
        'Transferencia · 110101 · Banco principal',
        'Transferencia · 110102 · Billetera digital',
      ]),
    );
    expect(find.text('Método y cuenta de entrega'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('advance entry exposes only active methods with an account',
      (tester) async {
    await pumpSurface(
      tester,
      const PayrollAdvanceEntry(
        line: PayrollVoucherLine(
          voucherId: 'voucher-1',
          employeeId: 'worker-1',
          employeeName: 'Trabajador Uno',
          paymentMethodId: 'inactive',
        ),
        paymentMethods: [
          {
            'id': 'valid',
            'name': 'Transferencia válida',
            'is_active': true,
            'account_id': 'account-valid',
          },
          {
            'id': 'inactive',
            'name': 'Transferencia inactiva',
            'is_active': false,
            'account_id': 'account-inactive',
          },
          {
            'id': 'without-account',
            'name': 'Método sin cuenta',
            'is_active': true,
          },
        ],
      ),
    );

    final methodField = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(
      methodField.items!.map((item) => item.value),
      orderedEquals(const ['valid']),
    );
    expect(
      find.byKey(
        const Key('payroll-advance-no-valid-payment-method'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('entry blocks registration when every method is invalid',
      (tester) async {
    await pumpSurface(
      tester,
      const PayrollAdvanceEntry(
        line: PayrollVoucherLine(
          voucherId: 'voucher-1',
          employeeId: 'worker-1',
          employeeName: 'Trabajador Uno',
        ),
        paymentMethods: [
          {
            'id': 'inactive',
            'name': 'Transferencia inactiva',
            'is_active': false,
            'account_id': 'account-inactive',
          },
        ],
      ),
    );

    expect(
      find.byKey(
        const Key('payroll-advance-no-valid-payment-method'),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is FilledButton && widget.onPressed == null,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
