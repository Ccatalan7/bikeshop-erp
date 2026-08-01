import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/hr/models/payroll_audit_read_models.dart';
import 'package:vinabike_erp/modules/hr/models/payroll_voucher.dart';
import 'package:vinabike_erp/modules/hr/payroll/payroll_redesign_page.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_advances_and_cash_surfaces.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_payment_composer.dart';
import 'package:vinabike_erp/modules/hr/payroll/theme/payroll_tokens.dart';

/// Conductual de la superficie nueva (handoff 2a/2b/2e + 3a/3c).
/// Fixtures sintéticas; ningún dato real.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  const transferAccountId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const cashAccountId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

  const paymentMethods = [
    {
      'id': 'method-transfer',
      'name': 'Transferencia',
      'code': 'transfer',
      'account_id': transferAccountId,
      'is_active': true,
      'requires_reference': false,
    },
    {
      'id': 'method-cash',
      'name': 'Efectivo',
      'code': 'cash',
      'account_id': cashAccountId,
      'is_active': true,
      'requires_reference': false,
    },
  ];

  PayrollVoucherLine line({
    required String id,
    required String name,
    double hours = 38.5,
    double total = 172875,
    double settled = 0,
    double cashPaid = 0,
    double advancesApplied = 0,
    double? balance,
    String? methodId = 'method-transfer',
    List<PayrollSettlementEvidence> settlementEvidence = const [],
  }) {
    return PayrollVoucherLine(
      id: id,
      voucherId: 'voucher-1',
      employeeId: 'employee-$id',
      employeeName: name,
      workedHours: hours,
      hourlyRate: 4490,
      totalAmount: total,
      paymentMethodId: methodId,
      cashPaid: cashPaid,
      advancesApplied: advancesApplied,
      settledAmount: settled,
      balance: balance ?? total - settled,
      settlementEvidence: settlementEvidence,
    );
  }

  PayrollVoucher voucher({
    String id = 'voucher-1',
    PayrollVoucherStatus status = PayrollVoucherStatus.confirmed,
    List<PayrollVoucherLine>? lines,
    int day = 6,
  }) {
    final resolved = lines ??
        [
          line(id: 'line-1', name: 'Vicente Soto', settled: 172875),
          line(id: 'line-2', name: 'Lucas Reyes'),
          line(id: 'line-3', name: 'Guillermo Pinto', methodId: 'method-cash'),
        ];
    return PayrollVoucher(
      id: id,
      tenantId: 'tenant-1',
      voucherNumber: 'NOM-0$day',
      periodStart: DateTime(2026, 7, day),
      periodEnd: DateTime(2026, 7, day + 6),
      totalHours: resolved.fold(0, (s, l) => s + l.totalHours),
      totalAmount: resolved.fold(0, (s, l) => s + l.totalAmount),
      employeeCount: resolved.length,
      status: status,
      createdAt: DateTime(2026, 7, day),
      updatedAt: DateTime(2026, 7, day),
      reconciliationVersion: 7,
      lines: resolved,
    );
  }

  ({
    PayrollRedesignActions actions,
    List<Map<String, dynamic>> paid,
    List<String> confirmed,
    List<String> registeredAdvanceEmployees,
    int Function() loadCalls,
    int Function() historyHydrationCalls,
  }) harness({
    List<PayrollVoucher>? vouchers,
    List<EmployeeAdvance> openAdvances = const [],
    List<Map<String, dynamic>> employees = const [],
    bool versionedMutationsAvailable = true,
    Future<PayrollRedesignData> Function(int call)? onLoad,
    Future<PayrollVoucher> Function(PayrollVoucher voucher)? onHydrateHistory,
    Future<PayrollAdvanceLedgerPage?> Function({
      required String employeeId,
      PayrollAdvanceLedgerCursor? cursor,
    })? loadAdvanceLedgerPage,
    Future<DateTime> Function(DateTime instant)? tenantCivilDateOf,
  }) {
    final paid = <Map<String, dynamic>>[];
    final confirmed = <String>[];
    final registeredAdvanceEmployees = <String>[];
    var loadCalls = 0;
    var historyHydrationCalls = 0;
    final resolvedVouchers = vouchers ?? [voucher()];
    return (
      actions: PayrollRedesignActions(
        load: () async {
          loadCalls += 1;
          final custom = onLoad;
          if (custom != null) return custom(loadCalls);
          return PayrollRedesignData(
            vouchers: resolvedVouchers,
            paymentMethods: paymentMethods,
            openAdvances: openAdvances,
            employees: employees,
            versionedMutationsAvailable: versionedMutationsAvailable,
          );
        },
        hydrateHistoryVoucher: (voucher) async {
          historyHydrationCalls += 1;
          final hydrate = onHydrateHistory;
          return hydrate == null ? voucher : await hydrate(voucher);
        },
        commitWeek: (id) async => confirmed.add(id),
        payLine: ({
          required voucherId,
          required lineId,
          required splits,
          required operationKey,
          required expectedReconciliationVersion,
        }) async {
          paid.add({
            'voucherId': voucherId,
            'lineId': lineId,
            'splits': splits,
            'operationKey': operationKey,
            'version': expectedReconciliationVersion,
          });
        },
        registerAdvance: ({
          required employeeId,
          required amount,
          required paymentMethodId,
          required paymentAccountId,
          required paidAt,
          reference,
          notes,
          required operationKey,
        }) async {
          registeredAdvanceEmployees.add(employeeId);
        },
        loadAdvanceLedgerPage: loadAdvanceLedgerPage,
        tenantCivilDateOf: tenantCivilDateOf,
      ),
      paid: paid,
      confirmed: confirmed,
      registeredAdvanceEmployees: registeredAdvanceEmployees,
      loadCalls: () => loadCalls,
      historyHydrationCalls: () => historyHydrationCalls,
    );
  }

  Future<void> pump(
    WidgetTester tester,
    PayrollRedesignActions actions, {
    required Size size,
    String? initialVoucherId,
    Future<void> Function(String employeeId)? onConfigureEmployeePaymentMethod,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        home: Scaffold(
          body: PayrollRedesignPage(
            actions: actions,
            initialVoucherId: initialVoucherId,
            onConfigureEmployeePaymentMethod: onConfigureEmployeePaymentMethod,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('handoff de Asistencias selecciona el borrador exacto',
      (tester) async {
    final first = voucher(id: 'voucher-first', day: 6);
    final selected = voucher(
      id: 'voucher-selected',
      day: 13,
      lines: <PayrollVoucherLine>[
        line(id: 'selected-line', name: 'Borrador recién preparado'),
      ],
    );
    final h = harness(vouchers: <PayrollVoucher>[first, selected]);

    await pump(
      tester,
      h.actions,
      size: const Size(1440, 900),
      initialVoucherId: 'voucher-selected',
    );

    expect(find.text('Borrador recién preparado'), findsOneWidget);
    expect(find.text('Vicente Soto'), findsNothing);
  });

  testWidgets('3a: cola horizontal + tabla de decisión + barra monetaria',
      (tester) async {
    final h = harness();
    await pump(tester, h.actions, size: const Size(1440, 900));

    // moduleCommand propio (una fila navy, sin segundo título).
    expect(find.text('Nóminas'), findsOneWidget);
    expect(find.text('Importar cartola'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Importar cartola'),
        matching: find.byType(OutlinedButton),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text('Importar cartola'),
        matching: find.byType(FilledButton),
      ),
      findsNothing,
    );
    expect(
      tester.widget<Text>(find.text('Importar cartola')).style?.color,
      PayrollTokens.onShell,
      reason: 'la utilidad OCR debe conservar contraste sobre el chrome navy',
    );
    // Cola de semanas con numeración ISO correcta (6–12 jul 2026 = semana 28),
    // estable frente a huso horario y cambios de hora.
    expect(find.textContaining('Semana 28'), findsWidgets);
    // Tabla de decisión (headers exactos del frame).
    for (final label in const [
      'PERSONA',
      'MÉTODO',
      'TOTAL',
      'ANTICIPOS',
      'A PAGAR',
      'DECISIÓN',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // Barra monetaria con la ecuación y el cierre automático explicado.
    expect(find.text('FALTA PAGAR'), findsOneWidget);
    expect(
        find.textContaining('pasa a Pagada automáticamente'), findsOneWidget);
    // Franja de asistencia: payroll no edita horas.
    expect(find.textContaining('Las horas se editan en'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('2b: Pagar abre el composer y registra el pago con splits',
      (tester) async {
    final h = harness();
    await pump(tester, h.actions, size: const Size(1440, 900));

    await tester.tap(find.text('Pagar').first);
    await tester.pumpAndSettle();

    expect(find.byType(PayrollPaymentComposer), findsOneWidget);
    expect(find.textContaining('Cómo se pagó'), findsOneWidget);
    await tester.tap(find.textContaining('Registrar \$'));
    await tester.pumpAndSettle();

    expect(h.paid, hasLength(1));
    expect(h.paid.single['voucherId'], 'voucher-1');
    expect(h.paid.single['lineId'], 'line-2');
    expect(h.paid.single['version'], 7);
    final splits = h.paid.single['splits'] as List<Map<String, dynamic>>;
    expect(splits.single['kind'], 'payment');
    expect(splits.single['payment_method_id'], 'method-transfer');
    expect(splits.single['payment_account_id'], transferAccountId);
    // Sin autoavance: la cola sigue montada con la misma semana.
    expect(find.text('FALTA PAGAR'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('2b usa la semana seleccionada y copy honesto de conciliación',
      (tester) async {
    final h = harness(vouchers: [voucher(day: 13)]);
    await pump(tester, h.actions, size: const Size(1440, 900));

    await tester.tap(find.text('Pagar').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Se guarda como pago de SEMANA 29'),
        findsOneWidget);
    expect(find.textContaining('La referencia queda como respaldo'),
        findsOneWidget);
    expect(find.textContaining('persona, fecha y monto'), findsOneWidget);
  });

  testWidgets(
      '2b permite una transferencia parcial y conserva el saldo pendiente',
      (tester) async {
    final h = harness();
    await pump(tester, h.actions, size: const Size(1440, 900));

    await tester.tap(find.text('Pagar').first);
    await tester.pumpAndSettle();

    final amountField =
        find.byKey(const ValueKey<String>('payroll-composer-amount-field'));
    await tester.enterText(amountField, '30000');
    await tester.pumpAndSettle();

    expect(find.text('Registrar \$30.000'), findsOneWidget);
    expect(find.text('Quedará pendiente \$142.875'), findsOneWidget);
    expect(find.textContaining('seguirá parcialmente pagada'), findsOneWidget);

    await tester.tap(find.text('Registrar \$30.000'));
    await tester.pumpAndSettle();

    final splits = h.paid.single['splits'] as List<Map<String, dynamic>>;
    expect(splits.single['kind'], 'payment');
    expect(splits.single['amount'], 30000);
  });

  testWidgets('2b rechaza un monto mayor al saldo disponible', (tester) async {
    final h = harness();
    await pump(tester, h.actions, size: const Size(1440, 900));

    await tester.tap(find.text('Pagar').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('payroll-composer-amount-field')),
      '200000',
    );
    await tester.pumpAndSettle();

    expect(
      find.text('El monto no puede superar \$172.875.'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('payroll-composer-register')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(h.paid, isEmpty);
  });

  testWidgets('2e: efectivo confirma entrega y nunca autoavanza',
      (tester) async {
    final h = harness();
    await pump(tester, h.actions, size: const Size(1440, 900));

    // Efectivo y transferencia comparten el verbo `Pagar`: la fila de efectivo
    // se identifica por su persona, no por un rótulo distinto.
    await tester.tap(
      find.byKey(const ValueKey<String>('payroll-row-action-Guillermo Pinto')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Confirmar entrega'), findsOneWidget);

    await tester.tap(find.textContaining('Confirmar entrega'));
    await tester.pumpAndSettle();

    expect(h.paid, hasLength(1));
    final splits = h.paid.single['splits'] as List<Map<String, dynamic>>;
    expect(splits.single['kind'], 'payment');
    expect(splits.single['payment_method_id'], 'method-cash');
    // Estado post-confirmación con elecciones explícitas.
    expect(find.text('¿QUÉ SIGUE?'), findsOneWidget);
    expect(find.text('Volver a Nóminas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'un método ausente no se infiere como transferencia y bloquea el pago',
      (tester) async {
    final h = harness(
      vouchers: [
        voucher(lines: [
          line(
            id: 'line-missing',
            name: 'Persona Sin Método',
            total: 100000,
            methodId: null,
          ),
        ]),
      ],
    );
    final configuredEmployees = <String>[];
    await pump(
      tester,
      h.actions,
      size: const Size(1440, 900),
      onConfigureEmployeePaymentMethod: (employeeId) async {
        configuredEmployees.add(employeeId);
      },
    );

    expect(find.text('Configuración requerida'), findsOneWidget);
    expect(find.text('Sin método'), findsOneWidget);
    expect(find.text('Configurar método'), findsNothing);
    await tester.tap(
      find.byKey(
        const ValueKey('payroll-method-menu-Persona Sin Método'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Configurar método'), findsOneWidget);
    await tester.tap(find.text('Configurar método'));
    await tester.pumpAndSettle();

    expect(find.byType(PayrollPaymentComposer), findsNothing);
    expect(h.paid, isEmpty);
    expect(configuredEmployees, ['employee-line-missing']);
    expect(h.loadCalls(), 2);
  });

  testWidgets('5g: configurar el método vuelve al pago, no a la tabla',
      (tester) async {
    // «El retorno es el punto del flujo». Antes esto era un viaje de ida: se
    // salía a la ficha y se volvía a la tabla con la fila perdida entre las
    // demás y el pago sin empezar.
    var configured = 0;
    final h = harness(
      vouchers: [
        voucher(lines: [
          line(
            id: 'line-missing',
            name: 'Persona Sin Método',
            total: 100000,
            methodId: null,
          ),
        ]),
      ],
      // La segunda carga ya trae el método resuelto, que es lo que ocurre
      // cuando el operador efectivamente lo configuró.
      onLoad: (call) async => PayrollRedesignData(
        vouchers: [
          voucher(lines: [
            line(
              id: 'line-missing',
              name: 'Persona Sin Método',
              total: 100000,
              methodId: call == 1 ? null : 'method-transfer',
            ),
          ]),
        ],
        paymentMethods: paymentMethods,
        employees: const [],
        openAdvances: const [],
        versionedMutationsAvailable: true,
      ),
    );
    await pump(
      tester,
      h.actions,
      size: const Size(1440, 900),
      onConfigureEmployeePaymentMethod: (_) async => configured++,
    );

    await tester.tap(
      find.byKey(const ValueKey('payroll-method-menu-Persona Sin Método')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Configurar método'));
    await tester.pumpAndSettle();

    expect(configured, 1);
    // Lo que 5g exige: el composer queda abierto en la MISMA fila.
    expect(find.byType(PayrollPaymentComposer), findsOneWidget);
    expect(find.textContaining('Persona Sin Método'), findsWidgets);
    expect(h.paid, isEmpty, reason: 'abrir el composer no paga nada');
  });

  testWidgets('la preferencia canónica del trabajador resuelve una línea nula',
      (tester) async {
    final h = harness(
      vouchers: [
        voucher(lines: [
          line(
            id: 'line-preferred',
            name: 'Persona Preferente',
            total: 100000,
            methodId: null,
          ),
        ]),
      ],
      employees: const [
        {
          'id': 'employee-line-preferred',
          'first_name': 'Persona',
          'last_name': 'Preferente',
          'preferred_payment_method_id': 'method-transfer',
        },
      ],
    );
    await pump(tester, h.actions, size: const Size(1440, 900));

    expect(find.text('Transferencia'), findsOneWidget);
    await tester.tap(find.text('Pagar').first);
    await tester.pumpAndSettle();
    expect(find.byType(PayrollPaymentComposer), findsOneWidget);
  });

  testWidgets(
      'un anticipo vigente empieza sin aplicar y no reduce dinero nuevo',
      (tester) async {
    final h = harness(
      vouchers: [
        voucher(lines: [
          line(
            id: 'line-advance',
            name: 'Persona Con Anticipo',
            total: 100000,
          ),
        ]),
      ],
      openAdvances: [
        EmployeeAdvance(
          id: 'advance-1',
          employeeId: 'employee-line-advance',
          amount: 40000,
          amountApplied: 0,
          paidAt: DateTime(2026, 7, 8, 12),
          status: 'open',
        ),
      ],
    );
    await pump(tester, h.actions, size: const Size(1440, 900));

    expect(find.textContaining('anticipos \$0'), findsOneWidget);
    await tester.tap(find.text('Pagar').first);
    await tester.pumpAndSettle();
    expect(find.text('Registrar \$100.000'), findsOneWidget);

    await tester.tap(find.text('Registrar \$100.000'));
    await tester.pumpAndSettle();
    final splits = h.paid.single['splits'] as List<Map<String, dynamic>>;
    expect(splits, hasLength(1));
    expect(splits.single['kind'], 'payment');
    expect(splits.single['amount'], 100000);
  });

  testWidgets('el efectivo reparte anticipos con saldo decreciente',
      (tester) async {
    final cashLine = line(
      id: 'line-cash-cap',
      name: 'Persona Efectivo',
      total: 100000,
      methodId: 'method-cash',
    );
    final h = harness(
      vouchers: [
        voucher(lines: [cashLine])
      ],
      openAdvances: [
        EmployeeAdvance(
          id: 'advance-a',
          employeeId: cashLine.employeeId,
          amount: 80000,
          amountApplied: 0,
          paidAt: DateTime(2026, 7, 7, 12),
          status: 'open',
        ),
        EmployeeAdvance(
          id: 'advance-b',
          employeeId: cashLine.employeeId,
          amount: 80000,
          amountApplied: 0,
          paidAt: DateTime(2026, 7, 8, 12),
          status: 'open',
        ),
      ],
    );
    await pump(tester, h.actions, size: const Size(1440, 900));

    await tester.tap(find.text('Confirmar efectivo').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar anticipo de \$160.000'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar entrega \$0'));
    await tester.pumpAndSettle();

    final splits = h.paid.single['splits'] as List<Map<String, dynamic>>;
    final advances =
        splits.where((split) => split['kind'] == 'advance').toList();
    expect(advances, hasLength(2));
    expect(advances[0]['amount'], 80000);
    expect(advances[1]['amount'], 20000);
    expect(
      advances.fold<num>(0, (sum, split) => sum + split['amount']),
      100000,
    );
    expect(splits.where((split) => split['kind'] == 'payment'), isEmpty);
  });

  testWidgets('un saldo parcial muestra sólo la proyección hidratada',
      (tester) async {
    final h = harness(
      vouchers: [
        voucher(lines: [
          line(
            id: 'line-partial',
            name: 'Persona Parcial',
            total: 100000,
            cashPaid: 30000,
            advancesApplied: 20000,
            settled: 50000,
            balance: 50000,
          ),
        ]),
      ],
    );
    await pump(tester, h.actions, size: const Size(1440, 900));

    expect(find.textContaining('anticipos \$20.000'), findsOneWidget);
    expect(find.textContaining('pagado \$30.000'), findsOneWidget);
    expect(find.text('\$50.000'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('una confirmación con refresh fallido bloquea la repetición',
      (tester) async {
    late PayrollRedesignData firstData;
    var refreshFails = true;
    final h = harness(
      onLoad: (call) async {
        if (call > 1 && refreshFails) throw StateError('refresh unavailable');
        return firstData;
      },
    );
    firstData = PayrollRedesignData(
      vouchers: [voucher()],
      paymentMethods: paymentMethods,
    );
    await pump(tester, h.actions, size: const Size(1440, 900));

    await tester.tap(find.text('Pagar').first);
    await tester.pumpAndSettle();
    final register = find.textContaining('Registrar \$').first;
    await tester.tap(register);
    await tester.pumpAndSettle();

    expect(h.paid, hasLength(1));
    expect(find.textContaining('El servidor confirmó el movimiento'),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Registrar \$').first);
    await tester.pumpAndSettle();
    expect(h.paid, hasLength(1));
    expect(find.textContaining('recarga autoritativa'), findsOneWidget);

    // L-H2: mientras la proyección siga vieja el aviso es PERSISTENTE (no un
    // snackbar que expira) y su Reintentar ejecuta la recarga real.
    final banner =
        find.byKey(const ValueKey<String>('payroll-stale-projection-banner'));
    expect(banner, findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('payroll-composer-close')),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(banner, findsOneWidget,
        reason: 'el aviso de proyección vieja no expira con los snackbars');

    refreshFails = false;
    await tester.tap(
      find.descendant(of: banner, matching: find.text('Reintentar')),
    );
    await tester.pumpAndSettle();
    expect(banner, findsNothing,
        reason: 'una recarga autoritativa exitosa retira el aviso');

    // Con la proyección fresca la operación vuelve a aceptarse.
    await tester.tap(find.text('Pagar').first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Registrar \$').first);
    await tester.pumpAndSettle();
    expect(h.paid, hasLength(2));
  });

  testWidgets('volver de Asistencias y OCR recarga la proyección',
      (tester) async {
    final h = harness();
    late final GoRouter router;
    router = GoRouter(
      initialLocation: '/hr/payroll',
      routes: [
        GoRoute(
          path: '/hr/payroll',
          builder: (context, state) =>
              Scaffold(body: PayrollRedesignPage(actions: h.actions)),
        ),
        for (final path in const ['/hr/attendances', '/hr/payroll/reconcile'])
          GoRoute(
            path: path,
            builder: (context, state) => Scaffold(
              body: TextButton(
                key: const ValueKey('return-to-payroll'),
                onPressed: context.pop,
                child: const Text('Volver'),
              ),
            ),
          ),
      ],
    );
    addTearDown(router.dispose);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(h.loadCalls(), 1);

    await tester.tap(find.text('Abrir Asistencias ↗'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('return-to-payroll')));
    await tester.pumpAndSettle();
    expect(h.loadCalls(), 2);

    await tester.tap(find.text('Importar cartola'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('return-to-payroll')));
    await tester.pumpAndSettle();
    expect(h.loadCalls(), 3);
  });

  testWidgets('métodos duplicados se identifican por su cuenta contable',
      (tester) async {
    const duplicateMethods = [
      {
        'id': 'method-transfer-a',
        'name': 'Transferencia',
        'code': 'transfer',
        'account_id': transferAccountId,
        'account_code': '110101',
        'account_name': 'Banco principal',
        'is_active': true,
        'requires_reference': false,
      },
      {
        'id': 'method-transfer-b',
        'name': 'Transferencia',
        'code': 'transfer',
        'account_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        'account_code': '110102',
        'account_name': 'Banco secundario',
        'is_active': true,
        'requires_reference': false,
      },
    ];
    final h = harness(
      onLoad: (_) async => PayrollRedesignData(
        vouchers: [
          voucher(lines: [
            line(
              id: 'line-dup',
              name: 'Ana Duplicada',
              methodId: 'method-transfer-a',
            ),
          ]),
        ],
        paymentMethods: duplicateMethods,
      ),
    );
    await pump(tester, h.actions, size: const Size(1440, 900));

    await tester.tap(find.text('Pagar').first);
    await tester.pumpAndSettle();

    // Registered contract: duplicate names identify their accounting
    // account, never a positional/numeric suffix.
    final secondAccount =
        find.text('Transferencia · 110102 · Banco secundario');
    expect(
      find.text('Transferencia · 110101 · Banco principal'),
      findsOneWidget,
    );
    expect(secondAccount, findsOneWidget);
    expect(find.text('Transferencia (2)'), findsNothing);

    await tester.ensureVisible(secondAccount);
    await tester.tap(secondAccount);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Registrar \$').first);
    await tester.pumpAndSettle();

    expect(h.paid, hasLength(1));
    final splits = h.paid.single['splits'].toString();
    expect(splits, contains('method-transfer-b'));
    expect(splits, contains('cccccccc-cccc-4ccc-8ccc-cccccccccccc'));
  });

  testWidgets('backend legacy: Importar cartola abre el preview igualmente',
      (tester) async {
    final h = harness(versionedMutationsAvailable: false);
    late final GoRouter router;
    router = GoRouter(
      initialLocation: '/hr/payroll',
      routes: [
        GoRoute(
          path: '/hr/payroll',
          builder: (context, state) =>
              Scaffold(body: PayrollRedesignPage(actions: h.actions)),
        ),
        GoRoute(
          path: '/hr/payroll/reconcile',
          builder: (context, state) => Scaffold(
            body: TextButton(
              key: const ValueKey('return-to-payroll'),
              onPressed: context.pop,
              child: const Text('Preview de conciliación'),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Importar cartola'));
    await tester.pumpAndSettle();
    expect(find.text('Preview de conciliación'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('return-to-payroll')));
    await tester.pumpAndSettle();
    expect(find.text('Importar cartola'), findsOneWidget);
  });

  testWidgets('backend legacy deja la superficie en lectura explícita',
      (tester) async {
    final h = harness(
      versionedMutationsAvailable: false,
      vouchers: [
        voucher(lines: [
          line(
            id: 'line-read-only',
            name: 'Persona Solo Lectura',
            total: 100000,
            methodId: 'method-transfer',
          ),
        ]),
      ],
    );
    await pump(tester, h.actions, size: const Size(1440, 900));

    expect(find.textContaining('Actualización de nóminas pendiente'),
        findsOneWidget);
    expect(find.text('Actualización pendiente'), findsOneWidget);
    expect(find.text('Pagar'), findsNothing);
    expect(h.paid, isEmpty);
  });

  testWidgets(
      'borrador: la fila explica el bloqueo y Confirmar cierra la semana',
      (tester) async {
    final h = harness(
      vouchers: [voucher(status: PayrollVoucherStatus.draft, day: 6)],
    );
    await pump(tester, h.actions, size: const Size(1440, 900));

    // La fila no ofrece un botón que en realidad abre otra cosa: dice por qué
    // no se puede pagar todavía y deja la única acción real en el pie.
    expect(find.text('Falta confirmar'), findsWidgets);
    expect(find.text('Pagar'), findsNothing);
    expect(h.paid, isEmpty);

    // Una sola acción primaria: el lenguaje distingue obligación de pago.
    expect(find.text('Confirmar semana'), findsOneWidget);
    await tester.tap(find.text('Confirmar semana'));
    await tester.pumpAndSettle();
    expect(find.text('¿Confirmar esta semana?'), findsOneWidget);
    // El resumen del header también dice «N personas»: el alcance se busca
    // dentro del diálogo, no en toda la pantalla.
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.textContaining('3 personas'),
      ),
      findsOneWidget,
    );
    expect(h.confirmed, isEmpty);
    await tester.tap(
      find.byKey(
        const ValueKey('payroll-confirm-week-dialog-submit'),
      ),
    );
    await tester.pumpAndSettle();
    expect(h.confirmed, ['voucher-1']);
  });

  testWidgets('sin semanas ofrece una salida real a Asistencias en ambos modos',
      (tester) async {
    final h = harness(vouchers: const []);
    late final GoRouter router;
    router = GoRouter(
      initialLocation: '/hr/payroll',
      routes: [
        GoRoute(
          path: '/hr/payroll',
          builder: (context, state) =>
              Scaffold(body: PayrollRedesignPage(actions: h.actions)),
        ),
        GoRoute(
          path: '/hr/attendances',
          builder: (context, state) => const Scaffold(
            body: Text('Asistencias canónicas'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('No hay semanas por resolver'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('payroll-empty-weeks-open-attendance')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('payroll-empty-weeks-open-attendance')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Asistencias canónicas'), findsOneWidget);
  });

  testWidgets(
      '3c: móvil usa scopes compactos y una cola semanal horizontal intencional',
      (tester) async {
    final h = harness();
    await pump(tester, h.actions, size: const Size(390, 844));

    for (final key in const <ValueKey<String>>[
      ValueKey<String>('payroll-mobile-weeks'),
      ValueKey<String>('payroll-mobile-history'),
      ValueKey<String>('payroll-mobile-advances'),
    ]) {
      final command = find.byKey(key);
      expect(command, findsOneWidget);
    }
    final utilities = find.byKey(
      const ValueKey<String>('payroll-mobile-utilities'),
    );
    expect(utilities, findsOneWidget);
    expect(tester.getSize(utilities).height, greaterThanOrEqualTo(48));
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('payroll-mobile-scope-bar')),
          )
          .height,
      48,
    );
    for (final target in const <(ValueKey<String>, String)>[
      (ValueKey<String>('payroll-mobile-weeks'), 'Semanas'),
      (ValueKey<String>('payroll-mobile-history'), 'Historial'),
      (ValueKey<String>('payroll-mobile-advances'), 'Anticipos'),
    ]) {
      expect(
        find.descendant(
          of: find.byKey(target.$1),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                (widget.properties.label ?? '').startsWith(target.$2),
          ),
        ),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(const ValueKey<String>('payroll-mobile-reconcile')),
      findsNothing,
    );
    expect(find.text('Importar cartola'), findsNothing);
    expect(find.textContaining('Pagar'), findsWidgets);
    expect(find.text('FALTA'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('payroll-mobile-open-week-selector'),
        ),
        matching: find.byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('payroll-mobile-week-picker')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('3c: Anticipos e Importar cartola conservan alcance y ruta a 390',
      (tester) async {
    final h = harness(
      employees: const [
        {
          'id': 'employee-line-2',
          'first_name': 'Lucas',
          'last_name': 'Reyes',
          'preferred_payment_method_id': 'method-transfer',
        },
      ],
      openAdvances: [
        EmployeeAdvance(
          id: 'advance-mobile',
          employeeId: 'employee-line-2',
          amount: 40000,
          amountApplied: 0,
          paidAt: DateTime(2026, 7, 20, 12),
          status: 'open',
          notes: 'Anticipo móvil',
        ),
      ],
    );
    late final GoRouter router;
    router = GoRouter(
      initialLocation: '/hr/payroll',
      routes: [
        GoRoute(
          path: '/hr/payroll',
          builder: (context, state) =>
              Scaffold(body: PayrollRedesignPage(actions: h.actions)),
        ),
        GoRoute(
          path: '/hr/payroll/reconcile',
          builder: (context, state) => Scaffold(
            body: TextButton(
              key: const ValueKey('return-from-mobile-reconcile'),
              onPressed: context.pop,
              child: const Text('Volver'),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    final scopeScroll = find.descendant(
      of: find.byKey(const ValueKey<String>('payroll-mobile-scope-bar')),
      matching: find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
      ),
    );
    expect(scopeScroll, findsOneWidget);
    await tester.drag(scopeScroll, const Offset(-120, 0));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('payroll-mobile-advances')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PayrollAdvancesSurface), findsOneWidget);
    expect(find.text('Lucas Reyes'), findsWidgets);
    expect(find.text(r'$40.000'), findsWidgets);
    expect(find.text('FALTA'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey<String>('payroll-mobile-utilities')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Utilidades de Nóminas'), findsOneWidget);
    expect(find.text('Importar cartola'), findsOneWidget);
    await tester.tap(find.text('Importar cartola'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Actualización de nóminas pendiente'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('return-from-mobile-reconcile')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('return-from-mobile-reconcile')),
    );
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/hr/payroll');
    expect(find.byType(PayrollAdvancesSurface), findsOneWidget);
    expect(find.text(r'$40.000'), findsWidgets);
    expect(h.loadCalls(), 2);
    expect(
      find.byKey(
        const ValueKey<String>('payroll-mobile-open-week-selector'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Anticipos ordena por nombre y conserva la persona al recomponer',
      (tester) async {
    final h = harness(
      employees: const [
        {
          'id': 'zzzz-worker',
          'first_name': 'Ana',
          'last_name': 'Torres',
          'status': 'active',
          'preferred_payment_method_id': 'method-transfer',
        },
        {
          'id': 'aaaa-worker',
          'first_name': 'Zoila',
          'last_name': 'Pérez',
          'status': 'active',
          'preferred_payment_method_id': 'method-transfer',
        },
      ],
      openAdvances: [
        EmployeeAdvance(
          id: 'advance-ana',
          employeeId: 'zzzz-worker',
          amount: 10000,
          amountApplied: 0,
          paidAt: DateTime(2026, 7, 20, 12),
          status: 'open',
          notes: 'Movimiento Ana',
        ),
        EmployeeAdvance(
          id: 'advance-zoila',
          employeeId: 'aaaa-worker',
          amount: 20000,
          amountApplied: 0,
          paidAt: DateTime(2026, 7, 21, 12),
          status: 'open',
          notes: 'Movimiento Zoila',
        ),
      ],
    );
    await pump(tester, h.actions, size: const Size(390, 844));

    final scopeScroll = find.descendant(
      of: find.byKey(const ValueKey<String>('payroll-mobile-scope-bar')),
      matching: find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
      ),
    );
    await tester.drag(scopeScroll, const Offset(-120, 0));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('payroll-mobile-advances')),
    );
    await tester.pumpAndSettle();

    final compactSelector = find.byType(DropdownMenu<String>);
    expect(compactSelector, findsOneWidget);
    expect(
      tester.widget<DropdownMenu<String>>(compactSelector).initialSelection,
      'zzzz-worker',
    );
    expect(find.text('Movimiento Ana'), findsOneWidget);
    expect(find.text('Movimiento Zoila'), findsNothing);
    expect(
      find.byKey(
        const ValueKey<String>('payroll-advance-person-card-zzzz-worker'),
      ),
      findsNothing,
    );

    await tester.tap(compactSelector);
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(r'Zoila Pérez · $20.000 aplicable ahora').last,
    );
    await tester.pumpAndSettle();
    expect(find.text('Movimiento Zoila'), findsOneWidget);
    expect(find.text('Movimiento Ana'), findsNothing);

    tester.view.physicalSize = const Size(899, 900);
    await tester.pumpAndSettle();
    expect(find.text('Movimiento Zoila'), findsOneWidget);
    expect(find.byType(DropdownMenu<String>), findsOneWidget);

    tester.view.physicalSize = const Size(900, 900);
    await tester.pumpAndSettle();
    expect(find.text('Movimiento Zoila'), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(
            find.byKey(
              const ValueKey<String>(
                'payroll-advance-person-card-aaaa-worker',
              ),
            ),
          )
          .properties
          .selected,
      isTrue,
    );

    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();

    final anaCard = find.byKey(
      const ValueKey<String>('payroll-advance-person-card-zzzz-worker'),
    );
    final zoilaCard = find.byKey(
      const ValueKey<String>('payroll-advance-person-card-aaaa-worker'),
    );
    expect(anaCard, findsOneWidget);
    expect(zoilaCard, findsOneWidget);
    // 5h pone a las personas en columna: el orden por nombre se lee de arriba
    // hacia abajo, no de izquierda a derecha, y todas comparten el borde.
    expect(tester.getTopLeft(anaCard).dy,
        lessThan(tester.getTopLeft(zoilaCard).dy));
    expect(tester.getTopLeft(anaCard).dx, tester.getTopLeft(zoilaCard).dx);
    expect(
      tester.widget<Semantics>(zoilaCard).properties.selected,
      isTrue,
    );
    expect(find.text('Movimiento Zoila'), findsOneWidget);

    expect(
      find.bySemanticsLabel('Registrar anticipo para Zoila Pérez'),
      findsOneWidget,
    );
    await tester.tap(find.text('Nuevo para esta persona').hitTestable());
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Registra dinero entregado a Zoila Pérez'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const Key('payroll-advance-employee-select')),
          )
          .initialValue,
      'aaaa-worker',
    );
    await tester.tap(find.text('Cancelar').hitTestable());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('el selector de personas no comprime tarjetas ni las apila',
      (tester) async {
    final people = <AdvancePersonVM>[
      for (var index = 0; index < 8; index++)
        AdvancePersonVM(
          id: 'worker-$index',
          name: 'Persona $index',
          initials: 'P$index',
          avatarColor: PayrollTokens.avatarSky,
          balanceLabel: '\$${index + 1}.000',
          caption: 'aplicable ahora',
          selected: index == 0,
          onTap: () {},
        ),
    ];
    tester.view.physicalSize = const Size(1000, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PayrollAdvancesSurface(
            people: people,
            selectedName: 'Persona 0',
            selectedInitials: 'P0',
            selectedAvatar: PayrollTokens.avatarSky,
            selectedBalance: r'$1.000',
            selectedCount: '1 movimiento',
            ledger: const [
              AdvanceLedgerRowVM(
                date: '20/07',
                reason: 'Anticipo',
                amount: r'$1.000',
                applied: r'$0',
                balance: r'$1.000',
                statusLabel: 'VIGENTE',
                tone: PayrollStateTone.info,
              ),
            ],
            onNewAdvanceForSelectedPerson: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var index = 0; index < people.length; index++) {
      final card = find.byKey(
        ValueKey<String>('payroll-advance-person-card-worker-$index'),
      );
      expect(card, findsOneWidget);
      expect(tester.getSize(card).width, greaterThanOrEqualTo(210));
    }

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey<String>('payroll-advance-person-card-worker-0'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('payroll-advance-person-picker')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('el ledger largo queda acotado y desplazable en desktop',
      (tester) async {
    final ledger = <AdvanceLedgerRowVM>[
      for (var index = 0; index < 30; index++)
        AdvanceLedgerRowVM(
          date: '${(index + 1).toString().padLeft(2, '0')}/07',
          reason: 'Movimiento $index',
          amount: r'$1.000',
          applied: r'$0',
          balance: r'$1.000',
          statusLabel: 'VIGENTE',
          tone: PayrollStateTone.info,
        ),
    ];
    tester.view.physicalSize = const Size(1000, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PayrollAdvancesSurface(
            people: [
              AdvancePersonVM(
                id: 'worker-long-ledger',
                name: 'Persona con historial',
                initials: 'PH',
                avatarColor: PayrollTokens.avatarSky,
                balanceLabel: r'$30.000',
                caption: 'aplicable ahora',
                selected: true,
                onTap: () {},
              ),
            ],
            selectedName: 'Persona con historial',
            selectedInitials: 'PH',
            selectedAvatar: PayrollTokens.avatarSky,
            selectedBalance: r'$30.000',
            selectedCount: '30 movimientos',
            ledger: ledger,
            onNewAdvanceForSelectedPerson: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scroll = find.byKey(
      const ValueKey<String>('payroll-advance-ledger-scroll'),
    );
    expect(scroll, findsOneWidget);
    expect(find.text('Movimiento 0'), findsOneWidget);
    expect(find.text('Movimiento 29'), findsNothing);
    await tester.drag(scroll, const Offset(0, -1400));
    await tester.pumpAndSettle();
    expect(find.text('Movimiento 29'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('un trabajador inactivo conserva ledger y bloquea otro anticipo',
      (tester) async {
    final h = harness(
      employees: const [
        {
          'id': 'worker-inactive',
          'first_name': 'Antonia',
          'last_name': 'Inactiva',
          'status': 'inactive',
        },
      ],
      openAdvances: [
        EmployeeAdvance(
          id: 'advance-inactive',
          employeeId: 'worker-inactive',
          amount: 18000,
          amountApplied: 0,
          paidAt: DateTime(2026, 7, 18, 12),
          status: 'open',
          notes: 'Movimiento histórico inactivo',
        ),
      ],
    );
    await pump(tester, h.actions, size: const Size(1440, 900));
    await tester.tap(find.text('Anticipos'));
    await tester.pumpAndSettle();

    expect(find.text('Movimiento histórico inactivo'), findsOneWidget);
    expect(
      find.textContaining('ya no está disponible como trabajador activo'),
      findsOneWidget,
    );
    // La etiqueta visible es la de 5h y no repite el nombre; quien la nombra
    // es la semántica, que es lo que anuncia un lector de pantalla.
    expect(
      find.bySemanticsLabel('Registrar anticipo para Antonia Inactiva'),
      findsOneWidget,
    );
    final action = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Nuevo para esta persona'),
    );
    expect(action.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Anticipos entra por la persona que SÍ tiene saldo, no por la primera '
      'del alfabeto', (tester) async {
    // En producción esto abría el submódulo en una pantalla vacía: el orden es
    // alfabético y la primera persona casi nunca es la que debe plata.
    final h = harness(
      employees: const [
        {
          'id': 'worker-a',
          'first_name': 'Aaron',
          'last_name': 'Sin Saldo',
          'status': 'active',
        },
        {
          'id': 'worker-z',
          'first_name': 'Zulema',
          'last_name': 'Con Saldo',
          'status': 'active',
        },
      ],
      openAdvances: [
        EmployeeAdvance(
          id: 'advance-consumido',
          employeeId: 'worker-a',
          amount: 10000,
          amountApplied: 10000,
          paidAt: DateTime(2026, 7, 10, 12),
          status: 'applied',
          notes: 'Movimiento ya aplicado',
        ),
        EmployeeAdvance(
          id: 'advance-vigente',
          employeeId: 'worker-z',
          amount: 40000,
          amountApplied: 0,
          paidAt: DateTime(2026, 7, 18, 12),
          status: 'open',
          notes: 'Movimiento vigente',
        ),
      ],
    );
    await pump(tester, h.actions, size: const Size(1440, 900));
    await tester.tap(find.text('Anticipos'));
    await tester.pumpAndSettle();

    // Aaron va primero en la columna, pero el foco entra en Zulema.
    final aaron = find.byKey(
      const ValueKey<String>('payroll-advance-person-card-worker-a'),
    );
    final zulema = find.byKey(
      const ValueKey<String>('payroll-advance-person-card-worker-z'),
    );
    expect(
      tester.getTopLeft(aaron).dy,
      lessThan(tester.getTopLeft(zulema).dy),
    );
    expect(tester.widget<Semantics>(zulema).properties.selected, isTrue);
    expect(tester.widget<Semantics>(aaron).properties.selected, isFalse);
    expect(find.text('Movimiento vigente'), findsOneWidget);
    expect(find.text('Movimiento ya aplicado'), findsNothing);

    // El pie explica de qué se está hablando, y la acción vive junto a la
    // persona sobre la que actúa.
    expect(
      find.textContaining('es la palabra que manda'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Registrar anticipo para Zulema Con Saldo'),
      findsOneWidget,
    );

    // Elegir a mano manda sobre el default y sobrevive al recompose.
    await tester.tap(aaron);
    await tester.pumpAndSettle();
    expect(tester.widget<Semantics>(aaron).properties.selected, isTrue);
    expect(find.text('Movimiento ya aplicado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('una ficha ausente conserva ledger y bloquea otro anticipo',
      (tester) async {
    final h = harness(
      openAdvances: [
        EmployeeAdvance(
          id: 'advance-missing-worker',
          employeeId: 'worker-missing',
          amount: 9000,
          amountApplied: 0,
          paidAt: DateTime(2026, 7, 17, 12),
          status: 'open',
          notes: 'Movimiento de ficha ausente',
        ),
      ],
    );
    await pump(tester, h.actions, size: const Size(1440, 900));
    await tester.tap(find.text('Anticipos'));
    await tester.pumpAndSettle();

    expect(find.text('Movimiento de ficha ausente'), findsOneWidget);
    expect(find.text('Persona sin ficha'), findsWidgets);
    expect(
      find.textContaining('ya no está disponible como trabajador activo'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Registrar anticipo para Persona sin ficha'),
      findsOneWidget,
    );
    final action = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Nuevo para esta persona'),
    );
    expect(action.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la referencia visible precede la nota de origen del anticipo',
      (tester) async {
    final h = harness(
      employees: const [
        {
          'id': 'worker-reference',
          'first_name': 'Persona',
          'last_name': 'Referencia',
          'status': 'active',
        },
      ],
      openAdvances: [
        EmployeeAdvance(
          id: 'advance-reference',
          employeeId: 'worker-reference',
          amount: 25000,
          amountApplied: 0,
          paidAt: DateTime(2026, 7, 19, 12),
          status: 'open',
          reference: 'TRX-ANT-991',
          notes: 'Anticipo registrado desde el centro de nóminas.',
        ),
      ],
    );
    await pump(tester, h.actions, size: const Size(1440, 900));
    await tester.tap(find.text('Anticipos'));
    await tester.pumpAndSettle();

    final reference = find.text('TRX-ANT-991');
    final sourceNote =
        find.text('Anticipo registrado desde el centro de nóminas.');
    expect(reference, findsOneWidget);
    expect(sourceNote, findsOneWidget);
    expect(
      tester.getTopLeft(reference).dy,
      lessThan(tester.getTopLeft(sourceNote).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Anticipos permite iniciar el primer registro desde vacío',
      (tester) async {
    final h = harness(
      employees: const [
        {
          'id': 'employee-line-2',
          'first_name': 'Lucas',
          'last_name': 'Reyes',
          'status': 'active',
          'preferred_payment_method_id': 'method-transfer',
        },
      ],
    );
    await pump(tester, h.actions, size: const Size(1440, 900));

    await tester.tap(find.text('Anticipos'));
    await tester.pumpAndSettle();

    expect(find.text('No hay anticipos vigentes'), findsOneWidget);
    final action = find.byKey(
      const ValueKey<String>('payroll-empty-advance-register'),
    );
    expect(action, findsOneWidget);
    expect(
      tester.getSize(action).height,
      greaterThanOrEqualTo(PayrollTokens.touchMobile),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'un anticipo global conserva la persona elegida después del refresh',
      (tester) async {
    const employees = [
      {
        'id': 'worker-ana',
        'first_name': 'Ana',
        'last_name': 'Torres',
        'status': 'active',
        'preferred_payment_method_id': 'method-transfer',
      },
      {
        'id': 'worker-beto',
        'first_name': 'Beto',
        'last_name': 'Bravo',
        'status': 'active',
        'preferred_payment_method_id': 'method-transfer',
      },
    ];
    final advancesAfterSave = [
      EmployeeAdvance(
        id: 'advance-ana',
        employeeId: 'worker-ana',
        amount: 12000,
        amountApplied: 0,
        paidAt: DateTime(2026, 7, 20, 12),
        status: 'open',
        notes: 'Movimiento Ana',
      ),
      EmployeeAdvance(
        id: 'advance-beto',
        employeeId: 'worker-beto',
        amount: 15000,
        amountApplied: 0,
        paidAt: DateTime(2026, 7, 21, 12),
        status: 'open',
        notes: 'Movimiento Beto',
      ),
    ];
    final h = harness(
      onLoad: (call) async => PayrollRedesignData(
        vouchers: [voucher()],
        paymentMethods: paymentMethods,
        employees: employees,
        openAdvances: call == 1 ? const <EmployeeAdvance>[] : advancesAfterSave,
      ),
    );
    await pump(tester, h.actions, size: const Size(1440, 900));

    await tester.tap(find.text('Anticipos'));
    await tester.pumpAndSettle();
    expect(find.text('Registrar primer anticipo'), findsNothing);
    await tester.tap(
      find
          .byKey(
            const ValueKey<String>('payroll-empty-advance-register'),
          )
          .hitTestable(),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('payroll-advance-employee-select')).hitTestable(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beto Bravo').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '15000');
    await tester.pump();
    await tester.tap(find.text('Registrar anticipo').hitTestable().last);
    await tester.pumpAndSettle();

    expect(h.registeredAdvanceEmployees, ['worker-beto']);
    expect(h.loadCalls(), 2);
    expect(find.text('Movimiento Beto'), findsOneWidget);
    expect(find.text('Movimiento Ana'), findsNothing);
    expect(
      tester
          .widget<Semantics>(
            find.byKey(
              const ValueKey<String>(
                'payroll-advance-person-card-worker-beto',
              ),
            ),
          )
          .properties
          .selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('efectivo sin anticipos no muestra una acción no-op',
      (tester) async {
    final h = harness(
      vouchers: [
        voucher(
          lines: [
            line(
              id: 'cash-without-advance',
              name: 'Persona Efectivo',
              total: 95000,
              methodId: 'method-cash',
            ),
          ],
        ),
      ],
    );
    await pump(tester, h.actions, size: const Size(1440, 900));

    await tester.tap(find.text('Confirmar efectivo').first);
    await tester.pumpAndSettle();

    expect(find.text('Aplicar anticipo de \$0'), findsNothing);
    // 5f: sin cartola, quien puso el billete en la mano es la única traza.
    expect(find.text('Entregado por'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('payroll-cash-close')),
      findsOneWidget,
    );
    expect(find.text('Ir →'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Pagado abre respaldo real en desktop y mobile', (tester) async {
    final evidence = [
      PayrollSettlementEvidence(
        id: 'payment-evidence',
        voucherId: 'voucher-1',
        lineId: 'paid-evidence-line',
        kind: PayrollSettlementEvidenceKind.payment,
        source: PayrollSettlementEvidenceSource.bankStatement,
        amount: 80000,
        effectiveDate: DateTime(2026, 7, 29),
        paymentMethodLabel: 'Transferencia',
        paymentAccountLabel: 'Banco Estado',
        reference: 'TRF-88421',
        actorName: 'Claudio Catalán',
        statementRowId: 'statement-row-payment-evidence',
        bankAmount: 80250,
        variance: 250,
        statementTransactionDate: DateTime(2026, 7, 27),
        statementDescriptionObserved: 'App-traspaso A: Persona con respaldo',
        statementDocumentObserved: 'DOC-80000',
        statementPageNumber: 5,
        statementSourceLineStart: 44,
        statementSourceLineEnd: 45,
        statementRowOrdinal: 1,
      ),
      PayrollSettlementEvidence(
        id: 'advance-evidence',
        voucherId: 'voucher-1',
        lineId: 'paid-evidence-line',
        kind: PayrollSettlementEvidenceKind.advance,
        source: PayrollSettlementEvidenceSource.manual,
        amount: 20000,
        effectiveDate: DateTime(2026, 7, 29, 12),
        reference: 'Anticipo semana corta',
        actorName: 'Claudio Catalán',
      ),
    ];
    final paidVoucher = voucher(
      lines: [
        line(
          id: 'paid-evidence-line',
          name: 'Persona con respaldo',
          total: 100000,
          settled: 100000,
          cashPaid: 80000,
          advancesApplied: 20000,
          balance: 0,
          settlementEvidence: evidence,
        ),
      ],
    );

    final desktop = harness(vouchers: [paidVoucher]);
    await pump(tester, desktop.actions, size: const Size(1440, 900));
    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'payroll-paid-status-Persona con respaldo',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey<String>('payroll-payment-evidence-surface'),
      ),
      findsOneWidget,
    );
    expect(find.text('TRF-88421'), findsOneWidget);
    expect(find.text('Claudio Catalán'), findsNWidgets(2));
    expect(find.text('Cartola bancaria conciliada'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>(
          'payroll-payment-statement-observation-payment-evidence',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.text('App-traspaso A: Persona con respaldo'),
      findsOneWidget,
    );
    expect(find.text('DOC-80000'), findsOneWidget);
    expect(find.text('27/07/2026'), findsOneWidget);
    expect(find.text('Página 5 · líneas 44–45 · fila OCR 1'), findsOneWidget);
    expect(find.textContaining(r'+$250'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey<String>('payroll-payment-evidence-close'),
      ),
    );
    await tester.pumpAndSettle();

    final mobile = harness(vouchers: [paidVoucher]);
    await pump(tester, mobile.actions, size: const Size(390, 844));
    final mobileAction = find.byKey(
      const ValueKey<String>(
        'payroll-mobile-person-action-Persona con respaldo',
      ),
    );
    expect(mobileAction, findsOneWidget);
    await tester.tap(mobileAction);
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey<String>('payroll-payment-evidence-surface'),
      ),
      findsOneWidget,
    );
    expect(find.text('MOVIMIENTOS REGISTRADOS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cola cardinalmente segura mantiene 5 y 12 semanas alcanzables',
      (tester) async {
    List<PayrollVoucher> weeks(int count) => List<PayrollVoucher>.generate(
          count,
          (index) => voucher(
            id: 'voucher-cardinality-${index + 1}',
            day: 6 + index * 7,
            lines: [
              line(
                id: 'cardinality-${index + 1}',
                name: 'Persona ${index + 1}',
                total: 100000.0 + index,
              ),
            ],
          ),
        );

    final desktop = harness(vouchers: weeks(5));
    await pump(tester, desktop.actions, size: const Size(1440, 900));
    expect(
      find.byKey(const ValueKey('payroll-desktop-week-strip-scroll')),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Semana 32'));
    await tester.tap(find.text('Semana 32'));
    await tester.pumpAndSettle();
    expect(find.text('Persona 5'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final mobile = harness(vouchers: weeks(12));
    await pump(tester, mobile.actions, size: const Size(390, 844));
    expect(
      find.byKey(const ValueKey('payroll-mobile-week-picker')),
      findsNothing,
    );
    final weekStrip = find.descendant(
      of: find.byKey(
        const ValueKey('payroll-mobile-open-week-selector'),
      ),
      matching: find.byType(Scrollable),
    );
    expect(
      weekStrip,
      findsOneWidget,
    );
    final lastWeek = find.byKey(
      const ValueKey('payroll-mobile-week-Semana 39'),
    );
    await tester.scrollUntilVisible(
      lastWeek,
      280,
      scrollable: weekStrip,
    );
    await tester.tap(lastWeek);
    await tester.pumpAndSettle();
    expect(find.text('Persona 12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'historial pagado/anulado hidrata lazy, ordena newest-first y es lectura',
      (tester) async {
    final paid = voucher(
      id: 'history-paid',
      status: PayrollVoucherStatus.paid,
      day: 20,
      lines: [
        line(
          id: 'history-paid-line',
          name: 'Persona Pagada',
          total: 125000,
          balance: 125000,
        ),
      ],
    );
    final voided = voucher(
      id: 'history-voided',
      status: PayrollVoucherStatus.voided,
      day: 6,
      lines: [
        line(
          id: 'history-voided-line',
          name: 'Persona Anulada',
          total: 50000,
          balance: 50000,
        ),
      ],
    );
    Future<PayrollVoucher> hydrate(PayrollVoucher source) async {
      if (source.id != paid.id) return source;
      return source.copyWith(
        lines: [
          line(
            id: 'history-paid-line',
            name: 'Persona Pagada',
            total: 125000,
            settled: 125000,
            cashPaid: 100000,
            advancesApplied: 25000,
            balance: 0,
          ),
        ],
      );
    }

    final desktop = harness(
      vouchers: [voucher(id: 'history-open', day: 27), voided, paid],
      onHydrateHistory: hydrate,
    );
    await pump(tester, desktop.actions, size: const Size(1440, 900));
    expect(desktop.historyHydrationCalls(), 0);
    final historyControl = tester.widget<InkWell>(
      find.ancestor(
        of: find.text('Historial'),
        matching: find.byType(InkWell),
      ),
    );
    expect(historyControl.mouseCursor, SystemMouseCursors.click);
    expect(historyControl.hoverColor, isNot(Colors.transparent));
    expect(historyControl.focusColor, isNot(Colors.transparent));
    await tester.tap(find.text('Historial'));
    await tester.pumpAndSettle();

    expect(desktop.historyHydrationCalls(), 1);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('payroll-module-meta')),
          )
          .data,
      contains('2 semanas cerradas'),
    );
    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey('payroll-history-week-history-paid')),
          )
          .dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(
                const ValueKey('payroll-history-week-history-voided'),
              ),
            )
            .dy,
      ),
    );
    expect(find.text(r'$100.000'), findsWidgets);
    // Los anticipos se leen con signo: son plata que ya salió antes.
    expect(find.text(r'−$25.000'), findsWidgets);
    expect(
      find.byKey(const ValueKey('payroll-history-ledger')),
      findsOneWidget,
    );
    // 5i: la banda es la aritmética completa en orden.
    for (final label in const [
      'TOTAL',
      'ANTICIPOS',
      'A PAGAR',
      'PAGADO',
      'SALDO'
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('GANADO'), findsNothing);
    expect(find.text('Pagar'), findsNothing);
    expect(find.text('Confirmar semana'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('payroll-history-week-history-voided')),
    );
    await tester.pumpAndSettle();
    expect(desktop.historyHydrationCalls(), 2);
    expect(find.text('ANULADA'), findsWidgets);
    expect(tester.takeException(), isNull);

    final mobile = harness(
      vouchers: [voucher(id: 'history-open-mobile', day: 27), voided, paid],
      onHydrateHistory: hydrate,
    );
    await pump(tester, mobile.actions, size: const Size(390, 844));
    expect(mobile.historyHydrationCalls(), 0);
    await tester.tap(
      find.byKey(const ValueKey('payroll-mobile-history')),
    );
    await tester.pumpAndSettle();
    expect(mobile.historyHydrationCalls(), 1);
    expect(
      find.byKey(const ValueKey('payroll-history-selector')),
      findsOneWidget,
    );
    expect(find.text(r'$100.000'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cruza los anchos declarados sin overflow', (tester) async {
    for (final size in const [
      Size(384, 824),
      Size(599, 900),
      Size(600, 900),
      Size(834, 1112),
      Size(899, 900),
      Size(900, 900),
      Size(1116, 900),
      Size(1440, 900),
    ]) {
      final h = harness();
      await pump(tester, h.actions, size: size);
      expect(
        tester.takeException(),
        isNull,
        reason: 'overflow en ${size.width}x${size.height}',
      );
    }
  });

  group('Anticipos con read model paginado (F4)', () {
    PayrollAdvanceLedgerEntry entry({
      required String id,
      required String employeeId,
      required double amount,
      required double applied,
      required PayrollAdvanceLedgerStatus status,
      List<PayrollAdvanceAllocation> allocations = const [],
      String? reference,
      DateTime? paidAt,
    }) {
      return PayrollAdvanceLedgerEntry(
        id: id,
        employeeId: employeeId,
        amount: amount,
        appliedAmount: applied,
        balanceAmount: amount - applied,
        paidAt: paidAt ?? DateTime(2026, 7, 11, 12),
        status: status,
        paymentMethod: const PayrollPaymentMethodIdentity(
          id: 'method-cash',
          code: 'cash',
          name: 'Efectivo',
        ),
        actor: const PayrollAuditActor(name: 'Admin Sintética'),
        fundingEvidence: const PayrollAuditEvidence(
          source: PayrollAuditEvidenceSource.manual,
        ),
        createdAt: DateTime(2026, 7, 11, 12),
        updatedAt: DateTime(2026, 7, 12, 12),
        allocations: allocations,
        reference: reference,
      );
    }

    PayrollAdvanceAllocation allocation() => PayrollAdvanceAllocation(
          id: 'alloc-1',
          amount: 36000,
          appliedAt: DateTime(2026, 7, 13),
          createdAt: DateTime(2026, 7, 13),
          actor: const PayrollAuditActor(name: 'Admin Sintética'),
          voucherId: 'voucher-1',
          voucherNumber: 'NOM-00031',
          periodStart: DateTime(2026, 7, 6),
          periodEnd: DateTime(2026, 7, 12),
          voucherStatus: 'paid',
          voucherLineId: 'line-2',
          voucherLineTotal: 172875,
          evidence: const PayrollAuditEvidence(
            source: PayrollAuditEvidenceSource.manual,
          ),
        );

    EmployeeAdvance openAdvance() => EmployeeAdvance(
          id: 'advance-open',
          employeeId: 'employee-line-2',
          amount: 20000,
          amountApplied: 0,
          paidAt: DateTime(2026, 7, 20),
          status: 'open',
          paymentMethodId: 'method-cash',
          paymentAccountId: cashAccountId,
          reference: 'ANT-OPEN',
        );

    const ledgerEmployees = [
      {
        'id': 'employee-line-2',
        'first_name': 'Lucas',
        'last_name': 'Reyes',
        'status': 'active',
      },
      {
        'id': 'employee-old',
        'first_name': 'Persona',
        'last_name': 'Retirada',
        'status': 'inactive',
      },
    ];

    testWidgets(
        'consume el ledger paginado, agrega páginas y descubre a la persona '
        'inactiva con historial sin CTA', (tester) async {
      final requests = <String>[];
      final h = harness(
        openAdvances: [openAdvance()],
        employees: ledgerEmployees,
        loadAdvanceLedgerPage: ({required employeeId, cursor}) async {
          requests.add('$employeeId:${cursor?.id ?? 'first'}');
          if (employeeId == 'employee-old') {
            return PayrollAdvanceLedgerPage(
              employeeId: employeeId,
              totals: const PayrollAdvanceLedgerTotals(
                deliveredAmount: 15000,
                appliedAmount: 15000,
                balanceAmount: 0,
                recordCount: 1,
              ),
              items: [
                entry(
                  id: 'old-1',
                  employeeId: employeeId,
                  amount: 15000,
                  applied: 15000,
                  status: PayrollAdvanceLedgerStatus.applied,
                ),
              ],
              hasMore: false,
            );
          }
          if (cursor == null) {
            return PayrollAdvanceLedgerPage(
              employeeId: employeeId,
              totals: const PayrollAdvanceLedgerTotals(
                deliveredAmount: 61000,
                appliedAmount: 41000,
                balanceAmount: 20000,
                recordCount: 3,
              ),
              items: [
                entry(
                  id: 'adv-open',
                  employeeId: employeeId,
                  amount: 20000,
                  applied: 0,
                  status: PayrollAdvanceLedgerStatus.open,
                  reference: 'ANT-OPEN',
                ),
                entry(
                  id: 'adv-applied',
                  employeeId: employeeId,
                  amount: 36000,
                  applied: 36000,
                  status: PayrollAdvanceLedgerStatus.applied,
                  allocations: [allocation()],
                ),
              ],
              hasMore: true,
              nextCursor: PayrollAdvanceLedgerCursor(
                paidAt: DateTime(2026, 7, 11, 12),
                id: 'adv-applied',
              ),
            );
          }
          return PayrollAdvanceLedgerPage(
            employeeId: employeeId,
            totals: const PayrollAdvanceLedgerTotals(
              deliveredAmount: 66000,
              appliedAmount: 41000,
              balanceAmount: 20000,
              recordCount: 3,
            ),
            items: [
              entry(
                id: 'adv-voided',
                employeeId: employeeId,
                amount: 5000,
                applied: 0,
                status: PayrollAdvanceLedgerStatus.voided,
              ),
            ],
            hasMore: false,
          );
        },
      );
      await pump(tester, h.actions, size: const Size(1440, 900));
      await tester.tap(find.text('Anticipos'));
      await tester.pumpAndSettle();

      // El read model manda: la fila imputada (que el lector de saldos
      // abiertos no conoce) es visible con su imputación por semana.
      expect(requests.first, 'employee-line-2:first');
      expect(find.text('APLICADO'), findsWidgets);
      expect(find.textContaining('Aplicado en NOM-00031'), findsOneWidget);
      expect(find.text('VIGENTE'), findsWidgets);
      expect(find.text('ANULADO'), findsNothing);
      expect(find.textContaining('3 movimientos'), findsWidgets);

      await tester.tap(find.text('Cargar movimientos anteriores'));
      await tester.pumpAndSettle();
      expect(requests, contains('employee-line-2:adv-applied'));
      expect(find.text('ANULADO'), findsWidgets);
      expect(find.text('APLICADO'), findsWidgets);
      expect(find.text('Cargar movimientos anteriores'), findsNothing);

      // Persona inactiva con historial: descubrible, con ledger y sin CTA.
      await tester.tap(find.text('Persona Retirada'));
      await tester.pumpAndSettle();
      expect(requests.last, 'employee-old:first');
      expect(find.text('APLICADO'), findsWidgets);
      expect(find.textContaining('ya no está disponible'), findsOneWidget);
    });

    testWidgets(
        'backend sin paginación: fallback honesto al lector de saldos '
        'abiertos', (tester) async {
      final h = harness(
        openAdvances: [openAdvance()],
        employees: ledgerEmployees,
        loadAdvanceLedgerPage: ({required employeeId, cursor}) async => null,
      );
      await pump(tester, h.actions, size: const Size(1440, 900));
      await tester.tap(find.text('Anticipos'));
      await tester.pumpAndSettle();

      expect(find.text('VIGENTE'), findsWidgets);
      expect(find.text('Cargar movimientos anteriores'), findsNothing);
      // Sin el read model no hay índice histórico autoritativo, así que la
      // persona sin saldo abierto no se ofrece como si tuviera datos.
      expect(find.text('Persona Retirada'), findsNothing);
    });

    testWidgets('un error de página es reintentable sin perder el contexto',
        (tester) async {
      var attempts = 0;
      final h = harness(
        openAdvances: [openAdvance()],
        employees: ledgerEmployees,
        loadAdvanceLedgerPage: ({required employeeId, cursor}) async {
          attempts++;
          if (attempts == 1) throw StateError('red caída');
          return PayrollAdvanceLedgerPage(
            employeeId: employeeId,
            totals: const PayrollAdvanceLedgerTotals(
              deliveredAmount: 20000,
              appliedAmount: 0,
              balanceAmount: 20000,
              recordCount: 1,
            ),
            items: [
              entry(
                id: 'adv-open',
                employeeId: employeeId,
                amount: 20000,
                applied: 0,
                status: PayrollAdvanceLedgerStatus.open,
                reference: 'ANT-OPEN',
              ),
            ],
            hasMore: false,
          );
        },
      );
      await pump(tester, h.actions, size: const Size(1440, 900));
      await tester.tap(find.text('Anticipos'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('payroll-advance-pagination-error')),
        findsOneWidget,
      );
      // Las filas del fallback siguen visibles mientras el error persiste.
      expect(find.text('VIGENTE'), findsWidgets);

      await tester.tap(find.text('Reintentar cargar movimientos'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(
        find.byKey(const ValueKey<String>('payroll-advance-pagination-error')),
        findsNothing,
      );
      expect(find.text('VIGENTE'), findsWidgets);
    });

    testWidgets('el ledger muestra el día civil del tenant, no el del equipo',
        (tester) async {
      // L-H3: el instante UTC se resuelve con la zona del TENANT. El día
      // centinela 24/06 no puede salir de ninguna conversión local de julio,
      // así que el assert no depende de la zona del equipo que corre el test.
      final fallbackInstant = DateTime.utc(2026, 7, 20, 3);
      final resolved = <DateTime>[];
      final h = harness(
        openAdvances: [openAdvance()],
        employees: ledgerEmployees,
        tenantCivilDateOf: (instant) async {
          resolved.add(instant);
          if (instant == fallbackInstant) {
            throw StateError('timezone del tenant no disponible');
          }
          return DateTime(2026, 6, 24);
        },
        loadAdvanceLedgerPage: ({required employeeId, cursor}) async {
          return PayrollAdvanceLedgerPage(
            employeeId: employeeId,
            totals: const PayrollAdvanceLedgerTotals(
              deliveredAmount: 27000,
              appliedAmount: 0,
              balanceAmount: 27000,
              recordCount: 2,
            ),
            items: [
              entry(
                id: 'adv-civil',
                employeeId: employeeId,
                amount: 20000,
                applied: 0,
                status: PayrollAdvanceLedgerStatus.open,
                reference: 'ANT-CIVIL',
                paidAt: DateTime.utc(2026, 7, 11, 12),
              ),
              entry(
                id: 'adv-fallback',
                employeeId: employeeId,
                amount: 7000,
                applied: 0,
                status: PayrollAdvanceLedgerStatus.open,
                reference: 'ANT-FALLBACK',
                paidAt: fallbackInstant,
              ),
            ],
            hasMore: false,
          );
        },
      );
      await pump(tester, h.actions, size: const Size(1440, 900));
      await tester.tap(find.text('Anticipos'));
      await tester.pumpAndSettle();

      expect(find.text('24/06'), findsOneWidget,
          reason: 'la fila usa el día civil del tenant');
      // La resolución fallida degrada SÓLO esa fila al día local del equipo;
      // el ledger nunca se bloquea por metadatos de zona horaria.
      expect(find.textContaining('ANT-FALLBACK'), findsOneWidget);
      expect(
        resolved,
        containsAll([DateTime.utc(2026, 7, 11, 12), fallbackInstant]),
      );
    });

    testWidgets('una página tardía de otra persona no pisa el ledger vigente',
        (tester) async {
      // Regresión del fence _advanceLedgerEpoch. La carrera real: con la
      // página 2 de Lucas EN VUELO se cambia la selección a Persona
      // Retirada; el guard de empleado ya apunta a la persona nueva, así que
      // si la respuesta tardía no se descarta por época, sus filas se
      // inyectarían dentro del ledger recién reseteado de la otra persona.
      final pending = <String, Completer<PayrollAdvanceLedgerPage?>>{};
      PayrollAdvanceLedgerPage pageFor(
        String employeeId,
        String reference, {
        bool hasMore = false,
      }) {
        return PayrollAdvanceLedgerPage(
          employeeId: employeeId,
          totals: const PayrollAdvanceLedgerTotals(
            deliveredAmount: 15000,
            appliedAmount: 0,
            balanceAmount: 15000,
            recordCount: 2,
          ),
          items: [
            entry(
              id: 'entry-$reference',
              employeeId: employeeId,
              amount: 15000,
              applied: 0,
              status: PayrollAdvanceLedgerStatus.open,
              reference: reference,
            ),
          ],
          hasMore: hasMore,
          nextCursor: hasMore
              ? PayrollAdvanceLedgerCursor(
                  paidAt: DateTime(2026, 7, 11, 12),
                  id: 'entry-$reference',
                )
              : null,
        );
      }

      final h = harness(
        openAdvances: [openAdvance()],
        employees: ledgerEmployees,
        loadAdvanceLedgerPage: ({required employeeId, cursor}) {
          if (employeeId == 'employee-line-2' && cursor == null) {
            return Future.value(
              pageFor(employeeId, 'ANT-LUCAS-P1', hasMore: true),
            );
          }
          final key = cursor == null ? employeeId : '$employeeId:more';
          final completer = Completer<PayrollAdvanceLedgerPage?>();
          pending[key] = completer;
          return completer.future;
        },
      );
      await pump(tester, h.actions, size: const Size(1440, 900));
      await tester.tap(find.text('Anticipos'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ANT-LUCAS-P1'), findsOneWidget);

      // Página 2 de Lucas queda pendiente…
      await tester.tap(find.text('Cargar movimientos anteriores'));
      await tester.pump();
      expect(pending.keys, contains('employee-line-2:more'));

      // …y con esa solicitud en vuelo cambia la selección.
      await tester.tap(find.text('Persona Retirada'));
      await tester.pump();
      await tester.pump();
      expect(pending.keys, contains('employee-old'));

      // La página tardía de Lucas llega con el ledger de la otra persona ya
      // reseteado: la época la descarta completa.
      pending['employee-line-2:more']!
          .complete(pageFor('employee-line-2', 'ANT-LUCAS-P2'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('ANT-LUCAS-P2'), findsNothing,
          reason: 'la página tardía de la persona anterior no puede '
              'inyectarse en el ledger de la selección vigente');

      pending['employee-old']!.complete(pageFor('employee-old', 'ANT-OLD'));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.textContaining('ANT-OLD'), findsOneWidget);
      expect(find.textContaining('ANT-LUCAS-P2'), findsNothing);
      expect(find.textContaining('ANT-LUCAS-P1'), findsNothing,
          reason: 'el reset por selección no conserva filas de otra persona');
    });
  });
}
