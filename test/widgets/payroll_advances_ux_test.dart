import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/hr/models/payroll_voucher.dart';
import 'package:vinabike_erp/modules/hr/models/payroll_audit_read_models.dart';
import 'package:vinabike_erp/modules/hr/widgets/payroll_advance_entry.dart';
import 'package:vinabike_erp/modules/hr/widgets/payroll_money_bar.dart';
import 'package:vinabike_erp/shared/widgets/vb_notice.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/modules/hr/widgets/payroll_advances_view.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_advances_and_cash_surfaces.dart';
import 'package:vinabike_erp/modules/hr/payroll/theme/payroll_tokens.dart';

void main() {
  // ── Helpers de `5h` · contrato v3 ────────────────────────────────────────
  Uint8List validPdfBytes([int length = 64]) {
    final bytes = Uint8List(length);
    bytes.setRange(0, 5, const <int>[0x25, 0x50, 0x44, 0x46, 0x2D]);
    return bytes;
  }

  Future<void> pumpEntry(
    WidgetTester tester, {
    required void Function(PayrollAdvanceIntent?) onResult,
    PayrollAdvanceReceiptPicker? pickReceipt,
    Size size = const Size(430, 900),
  }) async {
    tester.view.physicalSize = size;
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
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                onResult(
                  await Navigator.of(context).push<PayrollAdvanceIntent>(
                    MaterialPageRoute<PayrollAdvanceIntent>(
                      builder: (_) => Scaffold(
                        body: PayrollAdvanceEntry(
                          initialEmployeeId: 'rg',
                          pickReceipt: pickReceipt,
                          employees: const <Map<String, dynamic>>[
                            <String, dynamic>{
                              'id': 'rg',
                              'first_name': 'Rodrigo',
                              'last_name': 'Guillermo Nieto',
                              'status': 'active',
                              'preferred_payment_method_id': 'method-cash',
                            },
                          ],
                          paymentMethods: const <Map<String, dynamic>>[
                            <String, dynamic>{
                              'id': 'method-cash',
                              'name': 'Efectivo',
                              'is_active': true,
                              'account_id': 'account-cash',
                            },
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> selectReason(WidgetTester tester, String label) async {
    await tester.tap(
      find.byKey(const Key('payroll-advance-reason-code')).hitTestable(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  /// El formulario tiene scroll: un `tap` a ciegas aterriza en otro widget.
  Future<void> tapIn(WidgetTester tester, Key key) async {
    final finder = find.byKey(key);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(
      find
          .descendant(
            of: find.byType(PayrollMoneyBar),
            matching: find.text('Registrar anticipo'),
          )
          .hitTestable()
          .last,
    );
    await tester.pumpAndSettle();
  }

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
        // `E-04 · VbNotice` exige los roles canónicos: sin `AppTheme` no hay
        // `VinabikeThemeRoles` y el widget se niega a pintar. En la app real
        // siempre están; en el arnés hay que montarlos igual.
        theme: AppTheme.resolve(
          preset: AppearancePresets.vinabike,
          brightness: Brightness.light,
        ),
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

  testWidgets('§4.6 · el campo del selector compacto no corta la glosa en seco',
      (tester) async {
    // El `DropdownMenu` escribe `label` en su campo de texto, y ahí no hay
    // elipsis: lo que no cabe se corta en seco («Rodrigo … · $36.000 aplica»).
    // La glosa viaja en `labelWidget`, que sólo se dibuja dentro del menú.
    await pumpSurface(
      tester,
      PayrollAdvancesSurface(
        people: <AdvancePersonVM>[
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
          AdvancePersonVM(
            id: 'vd',
            name: 'Vicente Díaz',
            initials: 'VD',
            avatarColor: PayrollTokens.avatarSky,
            balanceLabel: r'$0',
            caption: 'todo aplicado',
            selected: false,
            onTap: () {},
          ),
        ],
        selectedName: 'Rodrigo Guillermo Nieto',
        selectedInitials: 'RG',
        selectedAvatar: PayrollTokens.avatarSky,
        selectedBalance: r'$36.000',
        selectedCount: '2 movimientos',
        ledger: const <AdvanceLedgerRowVM>[],
        onNewAdvanceForSelectedPerson: () {},
      ),
      size: const Size(430, 900),
    );

    final entries = tester
        .widget<DropdownMenu<String>>(find.byType(DropdownMenu<String>))
        .dropdownMenuEntries;
    expect(entries, hasLength(2));
    for (final entry in entries) {
      expect(
        entry.label.contains('aplicable') || entry.label.contains('aplicado'),
        isFalse,
        reason: 'el campo no lleva la glosa: ${entry.label}',
      );
      final label = entry.labelWidget as Text?;
      expect(label, isNotNull, reason: entry.label);
      expect(label!.overflow, TextOverflow.ellipsis);
      expect(label.maxLines, 1);
      expect(label.data, contains('aplic'));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '5h · la intención completa del contrato v3 viaja tipada: motivo, '
      'explicación y origen SEPARADOS', (tester) async {
    // 5h: «El motivo sale en el historial y en el detalle del pago». La columna
    // MOTIVO del ledger ya existía; faltaba dónde escribirla — el formulario
    // mandaba siempre la misma frase de relleno.
    //
    // Esta prueba **completa el formulario y pulsa el primario**, y lo que mide
    // es el `PayrollAdvanceIntent` que el widget devuelve por `Navigator.pop`.
    // No hay servicio ni base de datos de por medio: el intent es el borde del
    // widget, y ahí es donde `notes` se decide.
    PayrollAdvanceIntent? captured;
    tester.view.physicalSize = const Size(430, 900);
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
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                captured =
                    await Navigator.of(context).push<PayrollAdvanceIntent>(
                  MaterialPageRoute<PayrollAdvanceIntent>(
                    builder: (_) => Scaffold(
                      body: PayrollAdvanceEntry(
                        initialEmployeeId: 'rg',
                        employees: const <Map<String, dynamic>>[
                          <String, dynamic>{
                            'id': 'rg',
                            'first_name': 'Rodrigo',
                            'last_name': 'Guillermo Nieto',
                            'status': 'active',
                            'preferred_payment_method_id': 'method-cash',
                          },
                        ],
                        paymentMethods: const <Map<String, dynamic>>[
                          <String, dynamic>{
                            'id': 'method-cash',
                            'name': 'Efectivo',
                            'is_active': true,
                            'account_id': 'account-cash',
                          },
                        ],
                      ),
                    ),
                  ),
                );
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('payroll-advance-amount')),
      '40000',
    );
    await tester.enterText(
      find.byKey(const Key('payroll-advance-reason')),
      'Locomoción',
    );
    await tester.pump();

    // El rótulo aparece en el título y en el primario: se pulsa el BOTÓN.
    await tester.tap(
      find.descendant(
        of: find.byType(PayrollMoneyBar),
        matching: find.text('Registrar anticipo'),
      ),
    );
    await tester.pumpAndSettle();

    expect(captured, isNotNull, reason: 'el formulario devolvió su intent');
    expect(captured!.amount, 40000);
    // La explicación viaja TIPADA, no concatenada: `v3` la guarda en su propia
    // columna. Mezclarla en `notes` —como hacía `v2`— volvía imposible
    // separarla después, que es justo lo que la auditoría necesita.
    expect(captured!.reasonExplanation, 'Locomoción');
    // Y `notes` conserva SÓLO el origen.
    expect(captured!.notes, 'Registrado desde el centro de nóminas.');
    // El motivo por defecto es el caso corriente, y sin semana corta no se
    // inventa una fecha de término.
    expect(captured!.reasonCode, PayrollAdvanceReasonCode.requestedAdvance);
    expect(captured!.workEndedOn, isNull);
    expect(captured!.originalReceipt, isNull);
    expect(captured!.operationKey, isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('5h · sin explicación el formulario NO devuelve intención',
      (tester) async {
    PayrollAdvanceIntent? captured;
    tester.view.physicalSize = const Size(430, 900);
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
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                captured =
                    await Navigator.of(context).push<PayrollAdvanceIntent>(
                  MaterialPageRoute<PayrollAdvanceIntent>(
                    builder: (_) => Scaffold(
                      body: PayrollAdvanceEntry(
                        initialEmployeeId: 'rg',
                        employees: const <Map<String, dynamic>>[
                          <String, dynamic>{
                            'id': 'rg',
                            'first_name': 'Rodrigo',
                            'last_name': 'Guillermo Nieto',
                            'status': 'active',
                            'preferred_payment_method_id': 'method-cash',
                          },
                        ],
                        paymentMethods: const <Map<String, dynamic>>[
                          <String, dynamic>{
                            'id': 'method-cash',
                            'name': 'Efectivo',
                            'is_active': true,
                            'account_id': 'account-cash',
                          },
                        ],
                      ),
                    ),
                  ),
                );
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('payroll-advance-amount')),
      '40000',
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(PayrollMoneyBar),
        matching: find.text('Registrar anticipo'),
      ),
    );
    await tester.pumpAndSettle();

    // La explicación es obligatoria: antes era opcional porque el backend no
    // tenía dónde ponerla. Con `v3` sí la tiene, y un anticipo sin motivo
    // escrito es exactamente lo que la auditoría no puede reconstruir.
    expect(
      captured,
      isNull,
      reason: 'sin explicación no hay intención que enviar',
    );
    expect(
      find.textContaining('Explica en una línea'),
      findsOneWidget,
      reason: 'y se dice qué falta, en vez de no pasar nada',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('5h · la ayuda del motivo envuelve en compacto, no se elide',
      (tester) async {
    await pumpSurface(
      tester,
      const PayrollAdvanceEntry(
        initialEmployeeId: 'rg',
        employees: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'rg',
            'first_name': 'Rodrigo',
            'last_name': 'Guillermo Nieto',
            'status': 'active',
            'preferred_payment_method_id': 'method-cash',
          },
        ],
        paymentMethods: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'method-cash',
            'name': 'Efectivo',
            'is_active': true,
            'account_id': 'account-cash',
          },
        ],
      ),
      size: const Size(430, 900),
    );

    final field = tester.widget<TextField>(
      find.byKey(const Key('payroll-advance-reason')),
    );
    expect(field.decoration!.helperText, contains('historial'));
    // `helperText` dibuja UNA línea por defecto y a 430 se cortaba justo donde
    // explicaba para qué sirve el campo.
    expect(field.decoration!.helperMaxLines, greaterThanOrEqualTo(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '5h · el formulario usa el vocabulario montado de Nóminas, no Material '
      'crudo, y su aviso es `E-04 · VbNotice`', (tester) async {
    await pumpSurface(
      tester,
      const PayrollAdvanceEntry(
        initialEmployeeId: 'rg',
        employees: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'rg',
            'first_name': 'Rodrigo',
            'last_name': 'Guillermo Nieto',
            'status': 'active',
            'preferred_payment_method_id': 'method-cash',
          },
        ],
        paymentMethods: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'method-cash',
            'name': 'Efectivo',
            'is_active': true,
            'account_id': 'account-cash',
          },
        ],
      ),
      size: const Size(430, 900),
    );

    // El aviso viene del owner compartido bajo su id, no de un `Container`
    // con `surfaceContainerHighest` y radio a mano.
    expect(find.byType(VbNotice), findsOneWidget);
    expect(
      find.text('El anticipo queda en el registro de la persona'),
      findsOneWidget,
    );

    // Y el título se pinta con el vocabulario montado del módulo.
    final context = tester.element(find.byType(PayrollAdvanceEntry));
    final visual = PayrollVisualTokens.of(context);
    final title = tester.widget<Text>(find.text('Registrar anticipo').first);
    expect(title.style?.fontSize, visual.sectionTitle.fontSize);
    expect(title.style?.fontWeight, visual.sectionTitle.fontWeight);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      '5h · Semana corta exige el último día trabajado, y los otros motivos no '
      'lo inventan', (tester) async {
    PayrollAdvanceIntent? captured;
    await pumpEntry(tester, onResult: (value) => captured = value);

    await tester.enterText(
      find.byKey(const Key('payroll-advance-amount')),
      '30000',
    );
    await tester.enterText(
      find.byKey(const Key('payroll-advance-reason')),
      'Se fue el miércoles',
    );
    await tester.pump();

    // Con el motivo corriente el campo NO existe: pedir una fecha de término
    // donde la semana no terminó sería inventar un dato.
    expect(
      find.byKey(const Key('payroll-advance-work-ended-on')),
      findsNothing,
    );

    await selectReason(tester, 'Semana corta');
    expect(
      find.byKey(const Key('payroll-advance-work-ended-on')),
      findsOneWidget,
      reason: 'la semana corta se define por el último día trabajado',
    );

    // Y sin ese día no sale nada.
    await submit(tester);
    expect(captured, isNull);
    expect(find.textContaining('último día trabajado'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '5h · el comprobante viaja en BYTES y se puede quitar antes de '
      'enviar', (tester) async {
    PayrollAdvanceIntent? captured;
    final bytes = validPdfBytes();
    await pumpEntry(
      tester,
      onResult: (value) => captured = value,
      pickReceipt: () async => PayrollAdvanceReceiptDraft(
        bytes: bytes,
        fileName: 'vale-firmado.pdf',
        mimeType: 'application/pdf',
      ),
    );

    await tester.enterText(
      find.byKey(const Key('payroll-advance-amount')),
      '25000',
    );
    await tester.enterText(
      find.byKey(const Key('payroll-advance-reason')),
      'Vale firmado en papel',
    );
    await tester.pump();

    await tapIn(tester, const Key('payroll-advance-pick-receipt'));
    expect(
      find.byKey(const Key('payroll-advance-receipt-chip')),
      findsOneWidget,
    );
    expect(find.text('vale-firmado.pdf'), findsOneWidget);
    expect(
      tester
          .getSize(
            find.byKey(const Key('payroll-advance-remove-receipt')),
          )
          .height,
      greaterThanOrEqualTo(PayrollTokens.touchMin),
      reason: 'quitar comprobante conserva el objetivo táctil mínimo de 48',
    );

    // Se puede quitar antes de enviar…
    await tapIn(tester, const Key('payroll-advance-remove-receipt'));
    expect(
      find.byKey(const Key('payroll-advance-receipt-chip')),
      findsNothing,
    );

    // …y volver a adjuntarlo.
    await tapIn(tester, const Key('payroll-advance-pick-receipt'));

    await submit(tester);
    expect(captured, isNotNull);
    // Lo que viaja son los BYTES, no una ruta ni un identificador de Storage:
    // en este punto todavía no se subió nada, y ésa es la garantía.
    expect(captured!.originalReceipt, isNotNull);
    expect(captured!.originalReceipt!.bytes, bytes);
    expect(captured!.originalReceipt!.fileName, 'vale-firmado.pdf');
    expect(captured!.originalReceipt!.mimeType, 'application/pdf');
    expect(tester.takeException(), isNull);
  });

  testWidgets('5h · un comprobante inválido no crea chip ni intent',
      (tester) async {
    PayrollAdvanceIntent? captured;
    await pumpEntry(
      tester,
      onResult: (value) => captured = value,
      pickReceipt: () async => PayrollAdvanceReceiptDraft(
        bytes: Uint8List.fromList(const <int>[1, 2, 3, 4, 5]),
        fileName: 'falso.pdf',
        mimeType: 'application/pdf',
      ),
    );

    await tapIn(tester, const Key('payroll-advance-pick-receipt'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('payroll-advance-receipt-chip')),
      findsNothing,
    );
    expect(find.textContaining('PDF, JPG, PNG o WEBP'), findsOneWidget);
    expect(captured, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('5h · la operationKey es estable entre reconstrucciones',
      (tester) async {
    PayrollAdvanceIntent? captured;
    await pumpEntry(tester, onResult: (value) => captured = value);

    await tester.enterText(
      find.byKey(const Key('payroll-advance-amount')),
      '10000',
    );
    await tester.pump();
    // Cada uno de estos toques reconstruye el formulario. Si la clave se
    // recalculara en `build`, un reintento del MISMO anticipo se registraría
    // dos veces.
    await selectReason(tester, 'Otro');
    await selectReason(tester, 'Solicitud de anticipo');
    await tester.enterText(
      find.byKey(const Key('payroll-advance-reason')),
      'Un motivo cualquiera',
    );
    await tester.pump();
    final entryState = tester.state(find.byType(PayrollAdvanceEntry));
    // ignore: avoid_dynamic_calls
    final keyBeforeSubmit =
        (entryState as dynamic).operationKeyForTest as String;

    await submit(tester);
    expect(captured, isNotNull);
    expect(captured!.operationKey, keyBeforeSubmit);
    expect(captured!.operationKey, isNotEmpty);
    expect(tester.takeException(), isNull);
  });
}
