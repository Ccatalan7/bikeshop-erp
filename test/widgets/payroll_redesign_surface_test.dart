import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/hr/models/payroll_audit_read_models.dart';
import 'package:vinabike_erp/modules/hr/models/payroll_voucher.dart';
import 'package:vinabike_erp/modules/hr/payroll/payment_workspace/payroll_payment_workspace.dart';
import 'package:vinabike_erp/modules/hr/payroll/payroll_redesign_page.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_advances_and_cash_surfaces.dart';
import 'package:vinabike_erp/modules/hr/payroll/theme/payroll_tokens.dart';
import 'package:vinabike_erp/modules/hr/services/payroll_voucher_service.dart';
import 'package:vinabike_erp/modules/hr/widgets/payroll_advance_entry.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/utils/responsive_viewport.dart';
import 'package:vinabike_erp/shared/widgets/vb_money_text.dart';

/// Conductual de la superficie nueva (handoff 2a/2b/2e + 3a/3c).
/// Fixtures sintéticas; ningún dato real.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  const transferAccountId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const cashAccountId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

  const activatedReleaseCapabilities = PayrollReleaseCapabilities(
    employeePaymentMethodCommand: true,
    structuredAdvanceAudit: true,
    auditedSettlementReversal: true,
  );

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
    List<Map<String, dynamic>> corrected,
    List<String> confirmed,
    List<String> registeredAdvanceEmployees,
    int Function() loadCalls,
    int Function() historyHydrationCalls,
  }) harness({
    List<PayrollVoucher>? vouchers,
    List<EmployeeAdvance> openAdvances = const [],
    List<Map<String, dynamic>> employees = const [],
    bool versionedMutationsAvailable = true,
    PayrollReleaseCapabilities releaseCapabilities =
        activatedReleaseCapabilities,
    Future<PayrollRedesignData> Function(int call)? onLoad,
    Future<PayrollVoucher> Function(PayrollVoucher voucher)? onHydrateHistory,
    Future<PayrollAdvanceLedgerPage?> Function({
      required String employeeId,
      PayrollAdvanceLedgerCursor? cursor,
    })? loadAdvanceLedgerPage,
    Future<DateTime> Function(DateTime instant)? tenantCivilDateOf,
    Future<void> Function()? beforePayLine,
    Future<void> Function(PayrollVoucher voucher, String operationKey)?
        onUpdateDraft,
  }) {
    final paid = <Map<String, dynamic>>[];
    final corrected = <Map<String, dynamic>>[];
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
          if (custom != null) {
            return (await custom(loadCalls)).copyWith(
              releaseCapabilities: releaseCapabilities,
            );
          }
          return PayrollRedesignData(
            vouchers: resolvedVouchers,
            paymentMethods: paymentMethods,
            openAdvances: openAdvances,
            employees: employees,
            versionedMutationsAvailable: versionedMutationsAvailable,
            releaseCapabilities: releaseCapabilities,
          );
        },
        hydrateHistoryVoucher: (voucher) async {
          historyHydrationCalls += 1;
          final hydrate = onHydrateHistory;
          return hydrate == null ? voucher : await hydrate(voucher);
        },
        commitWeek: (id) async => confirmed.add(id),
        updateDraft: onUpdateDraft == null
            ? null
            : ({required voucher, required operationKey}) =>
                onUpdateDraft(voucher, operationKey),
        payLine: ({
          required voucherId,
          required lineId,
          required splits,
          required operationKey,
          required expectedReconciliationVersion,
        }) async {
          await beforePayLine?.call();
          paid.add({
            'voucherId': voucherId,
            'lineId': lineId,
            'splits': splits,
            'operationKey': operationKey,
            'version': expectedReconciliationVersion,
          });
        },
        reverseSettlement: ({
          required voucherId,
          required settlementKind,
          required settlementId,
          required reason,
          required operationKey,
          required expectedReconciliationVersion,
        }) async {
          corrected.add(<String, dynamic>{
            'voucherId': voucherId,
            'settlementKind': settlementKind,
            'settlementId': settlementId,
            'reason': reason,
            'operationKey': operationKey,
            'version': expectedReconciliationVersion,
          });
        },
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
        }) async {
          registeredAdvanceEmployees.add(employeeId);
        },
        loadAdvanceLedgerPage: loadAdvanceLedgerPage,
        tenantCivilDateOf: tenantCivilDateOf,
      ),
      paid: paid,
      corrected: corrected,
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
    String? initialScope,
    String? initialAdvanceEmployeeId,
    Future<void> Function(String employeeId)? onConfigureEmployeePaymentMethod,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        // Este arnés montaba `MaterialApp` **sin tema**, así que ejercitaba
        // Nóminas contra el default de Flutter y no contra el de la app: sin
        // `VinabikeThemeRoles`, ningún componente compartido podía usarse acá.
        // Se monta el tema real (2026-08-01).
        theme: AppTheme.resolve(
          preset: AppearancePresets.all.first,
          brightness: Brightness.light,
        ),
        home: Scaffold(
          body: PayrollRedesignPage(
            actions: actions,
            initialVoucherId: initialVoucherId,
            initialScope: initialScope,
            initialAdvanceEmployeeId: initialAdvanceEmployeeId,
            onConfigureEmployeePaymentMethod: onConfigureEmployeePaymentMethod,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openPaymentWorkspace(
    WidgetTester tester, {
    Finder? action,
  }) async {
    await tester.tap(action ?? find.text('Pagar').first);
    await tester.pumpAndSettle();
    expect(find.byType(PayrollPaymentWorkspace), findsOneWidget);
  }

  Future<void> addSalaryPart(
    WidgetTester tester, {
    String? amount,
  }) async {
    await tester.tap(find.text('Agregar parte'));
    await tester.pumpAndSettle();

    if (amount != null) {
      final amountField = find.widgetWithText(TextField, 'Monto');
      await tester.enterText(amountField, amount);
    }
    await tester.tap(find.text('Guardar parte'));
    await tester.pumpAndSettle();
  }

  Future<void> savePayment(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('payroll-payment-save-target')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
  }

  Finder paymentWorkspaceClose() => find.descendant(
        of: find.byType(PayrollPaymentWorkspace),
        matching: find.byTooltip('Cerrar'),
      );

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
    expect(find.text('CONFIRMADA'), findsWidgets);
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
    expect(find.text('Continuar pagos'), findsOneWidget);
    expect(find.textContaining('Pagar a '), findsNothing);
    // Asistencias entrega la fuente; el borrador sigue siendo editable.
    expect(
        find.textContaining('Puedes ajustar horas y tarifa'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('borrador guardado vuelve a abrir el editor y persiste cambios',
      (tester) async {
    PayrollVoucher? updated;
    String? operationKey;
    final draft = voucher(
      status: PayrollVoucherStatus.draft,
      lines: <PayrollVoucherLine>[
        line(id: 'line-edit', name: 'Lucas Pacheco', settled: 0),
      ],
    );
    final h = harness(
      vouchers: <PayrollVoucher>[draft],
      onUpdateDraft: (voucher, key) async {
        updated = voucher;
        operationKey = key;
      },
    );

    await pump(tester, h.actions, size: const Size(1440, 900));
    await tester.tap(find.byKey(const ValueKey('payroll-edit-draft')));
    await tester.pumpAndSettle();

    expect(find.text('Editar borrador de nómina'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('payroll-generation-hours-employee-line-edit')),
      '40',
    );
    await tester.enterText(
      find.byKey(const ValueKey('payroll-generation-rate-employee-line-edit')),
      '5000',
    );
    await tester.tap(
      find.byKey(const ValueKey('payroll-generation-primary-action')),
    );
    await tester.pumpAndSettle();

    expect(updated?.lines.single.workedHours, 40);
    expect(updated?.lines.single.hourlyRate, 5000);
    expect(updated?.lines.single.totalAmount, 200000);
    expect(operationKey, isNotEmpty);
    expect(find.text('Cerrar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'editor visible guarda aunque la página de origen haya sido reemplazada',
      (tester) async {
    PayrollVoucher? updated;
    final draft = voucher(
      status: PayrollVoucherStatus.draft,
      lines: <PayrollVoucherLine>[
        line(id: 'line-detached-editor', name: 'Lucas Pacheco', settled: 0),
      ],
    );
    final h = harness(
      vouchers: <PayrollVoucher>[draft],
      onUpdateDraft: (voucher, _) async => updated = voucher,
    );
    late StateSetter rebuildHost;
    var showPayrollPage = true;
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.all.first,
          brightness: Brightness.light,
        ),
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuildHost = setState;
            return Scaffold(
              body: showPayrollPage
                  ? PayrollRedesignPage(actions: h.actions)
                  : const SizedBox.expand(),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('payroll-edit-draft')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(
        const ValueKey(
          'payroll-generation-hours-employee-line-detached-editor',
        ),
      ),
      '40',
    );

    rebuildHost(() => showPayrollPage = false);
    await tester.pumpAndSettle();
    expect(find.text('Editar borrador de nómina'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('payroll-generation-primary-action')),
    );
    await tester.pumpAndSettle();

    expect(updated?.lines.single.workedHours, 40);
    expect(find.text('Cerrar'), findsOneWidget);
    expect(find.textContaining('No pudimos guardar el borrador'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('update confirmado no se presenta como fallo si el reload falla',
      (tester) async {
    late PayrollRedesignData initialData;
    var updates = 0;
    final draft = voucher(
      status: PayrollVoucherStatus.draft,
      lines: <PayrollVoucherLine>[
        line(id: 'line-refresh-failure', name: 'Lucas Pacheco', settled: 0),
      ],
    );
    final h = harness(
      onLoad: (call) async {
        if (call > 1) throw StateError('refresh unavailable');
        return initialData;
      },
      onUpdateDraft: (_, __) async => updates += 1,
    );
    initialData = PayrollRedesignData(
      vouchers: <PayrollVoucher>[draft],
      paymentMethods: paymentMethods,
      versionedMutationsAvailable: true,
    );

    await pump(tester, h.actions, size: const Size(1440, 900));
    await tester.tap(find.byKey(const ValueKey('payroll-edit-draft')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('payroll-generation-primary-action')),
    );
    await tester.pumpAndSettle();

    expect(updates, 1);
    expect(find.text('Cerrar'), findsOneWidget);
    expect(find.textContaining('No pudimos guardar el borrador'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('payroll-stale-projection-banner')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final surface in const <(String, Size, String)>[
    ('tablet 834', Size(834, 900), 'payroll-edit-draft'),
    ('teléfono 390', Size(390, 844), 'payroll-mobile-edit-draft'),
  ]) {
    testWidgets('borrador abre el editor desde ${surface.$1}', (tester) async {
      final draft = voucher(
        status: PayrollVoucherStatus.draft,
        lines: <PayrollVoucherLine>[
          line(id: 'line-${surface.$1}', name: 'Lucas Pacheco', settled: 0),
        ],
      );
      final h = harness(
        vouchers: <PayrollVoucher>[draft],
        onUpdateDraft: (_, __) async {},
      );

      await pump(tester, h.actions, size: surface.$2);
      final edit = find.byKey(ValueKey<String>(surface.$3));
      expect(edit, findsOneWidget);
      await tester.tap(edit);
      await tester.pumpAndSettle();

      expect(find.text('Editar borrador de nómina'), findsOneWidget);
      expect(
        find.byKey(
          ValueKey<String>(
            'payroll-generation-hours-employee-line-${surface.$1}',
          ),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('2b: Pagar abre el workspace canónico y registra sus partes',
      (tester) async {
    final h = harness();
    await pump(tester, h.actions, size: const Size(1440, 900));

    await openPaymentWorkspace(tester);
    expect(find.text('Cómo se paga el sueldo'), findsOneWidget);
    await addSalaryPart(tester);
    await savePayment(tester);

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

    await openPaymentWorkspace(tester);

    expect(find.text('PAGO DE NÓMINA'), findsOneWidget);
    expect(find.text('Una semana · un trabajador'), findsOneWidget);
    expect(find.textContaining('Semana 29'), findsWidgets);
  });

  testWidgets(
      '2b permite una transferencia parcial y conserva el saldo pendiente',
      (tester) async {
    final h = harness();
    await pump(tester, h.actions, size: const Size(1440, 900));

    await openPaymentWorkspace(tester);
    await addSalaryPart(tester, amount: '30000');

    expect(find.text('QUEDARÁ PENDIENTE'), findsOneWidget);
    expect(find.text(r'$142.875'), findsWidgets);
    expect(find.text(r'Quedarán $142.875 pendientes del pago'), findsOneWidget);

    await savePayment(tester);

    final splits = h.paid.single['splits'] as List<Map<String, dynamic>>;
    expect(splits.single['kind'], 'payment');
    expect(splits.single['amount'], 30000);
  });

  testWidgets('2b rechaza un monto mayor al saldo disponible', (tester) async {
    final h = harness();
    await pump(tester, h.actions, size: const Size(1440, 900));

    await openPaymentWorkspace(tester);
    await addSalaryPart(tester, amount: '200000');

    expect(
      find.text(
        'El sueldo y los conceptos incluidos superan el saldo pendiente de la nómina.',
      ),
      findsOneWidget,
    );
    await savePayment(tester);
    expect(h.paid, isEmpty);
  });

  testWidgets('2e: efectivo y transferencia usan el mismo workspace',
      (tester) async {
    final h = harness();
    await pump(tester, h.actions, size: const Size(1440, 900));

    // Efectivo y transferencia comparten el verbo `Pagar`: la fila de efectivo
    // se identifica por su persona, no por un rótulo distinto.
    await openPaymentWorkspace(
      tester,
      action: find.byKey(
        const ValueKey<String>('payroll-row-action-Guillermo Pinto'),
      ),
    );
    expect(find.text('Cómo se paga el sueldo'), findsOneWidget);
    await addSalaryPart(tester);
    expect(find.text('Efectivo'), findsWidgets);
    await savePayment(tester);

    expect(h.paid, hasLength(1));
    final splits = h.paid.single['splits'] as List<Map<String, dynamic>>;
    expect(splits.single['kind'], 'payment');
    expect(splits.single['payment_method_id'], 'method-cash');
    expect(find.byType(PayrollPaymentWorkspace), findsOneWidget);
    expect(find.text('Guardado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cerrar el workspace descarta sólo tras confirmación',
      (tester) async {
    final h = harness();
    await pump(tester, h.actions, size: const Size(1440, 900));

    await openPaymentWorkspace(tester);
    await addSalaryPart(tester, amount: '30000');
    await tester.tap(paymentWorkspaceClose());
    await tester.pumpAndSettle();

    expect(find.text('¿Cerrar el panel de pago?'), findsOneWidget);
    await tester.tap(find.text('Seguir editando'));
    await tester.pumpAndSettle();
    expect(find.byType(PayrollPaymentWorkspace), findsOneWidget);

    await tester.tap(paymentWorkspaceClose());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descartar cambios'));
    await tester.pumpAndSettle();

    expect(find.byType(PayrollPaymentWorkspace), findsNothing);
    expect(h.paid, isEmpty);
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
    expect(find.text('Configurar método'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey('payroll-method-menu-Persona Sin Método'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Configurar método'), findsNWidgets(2));
    await tester.tap(
      find.widgetWithText(MenuItemButton, 'Configurar método'),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PayrollPaymentWorkspace), findsNothing);
    expect(h.paid, isEmpty);
    expect(configuredEmployees, ['employee-line-missing']);
    expect(h.loadCalls(), 2);
  });

  testWidgets(
      '5n: al cerrar configuración de método el foco vuelve al control de origen',
      (tester) async {
    final h = harness(
      vouchers: [
        voucher(lines: [
          line(
            id: 'line-focus-method',
            name: 'Persona Foco Método',
            total: 100000,
            methodId: null,
          ),
        ]),
      ],
    );
    await pump(
      tester,
      h.actions,
      size: const Size(1440, 900),
      onConfigureEmployeePaymentMethod: (_) async {},
    );

    final trigger = find.byKey(
      const ValueKey<String>('payroll-method-menu-Persona Foco Método'),
    );
    final triggerInk = find.descendant(
      of: trigger,
      matching: find.byType(InkWell),
    );
    final triggerFocus = tester.widget<InkWell>(triggerInk).focusNode!;
    triggerFocus.requestFocus();
    await tester.pump();
    expect(triggerFocus.hasFocus, isTrue);

    await tester.tap(trigger);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(MenuItemButton, 'Configurar método'),
    );
    await tester.pumpAndSettle();

    expect(
      triggerFocus.hasFocus,
      isTrue,
      reason: 'el menú temporal no debe tragarse el foco al cerrarse',
    );
    expect(h.loadCalls(), 2);
  });

  test('las capacidades pendientes nacen fail-closed', () {
    const data = PayrollRedesignData(vouchers: <PayrollVoucher>[]);

    expect(data.releaseCapabilities.employeePaymentMethodCommand, isFalse);
    expect(data.releaseCapabilities.structuredAdvanceAudit, isFalse);
  });

  testWidgets('release gate deja Sin método pasivo y no expone la ruta 5g',
      (tester) async {
    final h = harness(
      releaseCapabilities: const PayrollReleaseCapabilities(),
      vouchers: [
        voucher(lines: [
          line(
            id: 'line-dormant-method',
            name: 'Persona Método Dormante',
            total: 100000,
            methodId: null,
          ),
        ]),
      ],
    );
    var configureCalls = 0;
    await pump(
      tester,
      h.actions,
      size: const Size(1440, 900),
      onConfigureEmployeePaymentMethod: (_) async => configureCalls++,
    );

    expect(find.text('Sin método'), findsOneWidget);
    expect(find.text('Configurar método'), findsNothing);
    expect(find.textContaining('Cambiar método de pago'), findsNothing);
    expect(
      find.byKey(
        const ValueKey<String>(
          'payroll-method-menu-Persona Método Dormante',
        ),
      ),
      findsNothing,
    );
    final passive = tester.widget<Semantics>(
      find.byKey(
        const ValueKey<String>(
          'payroll-row-blocked-Persona Método Dormante',
        ),
      ),
    );
    expect(passive.properties.enabled, isFalse);
    expect(
      passive.properties.label,
      contains('El contrato activo del servidor no permite cambiarlo'),
    );
    final disclosure = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label ==
              'Mostrar detalle de Persona Método Dormante',
    );
    await tester.tap(
      find.descendant(of: disclosure, matching: find.byType(IconButton)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cambiar método de pago'), findsNothing);
    expect(find.text('Nuevo anticipo'), findsNothing);
    expect(configureCalls, 0);
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
    await tester.tap(
      find.widgetWithText(MenuItemButton, 'Configurar método'),
    );
    await tester.pumpAndSettle();

    expect(configured, 1);
    // Lo que 5g exige: el workspace queda abierto en la MISMA fila.
    expect(find.byType(PayrollPaymentWorkspace), findsOneWidget);
    expect(find.textContaining('Persona Sin Método'), findsWidgets);
    expect(h.paid, isEmpty, reason: 'abrir el composer no paga nada');
  });

  testWidgets(
      'la preferencia del trabajador manda aunque otro método venga primero',
      (tester) async {
    const chequeFirstMethods = [
      {
        'id': 'method-cheque',
        'name': 'Cheque',
        'code': 'check',
        'account_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        'is_active': true,
        'requires_reference': false,
      },
      {
        'id': 'method-transfer',
        'name': 'Transferencia',
        'code': 'transfer',
        'account_id': transferAccountId,
        'is_active': true,
        'requires_reference': false,
      },
    ];
    final h = harness(
      onLoad: (_) async => PayrollRedesignData(
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
        paymentMethods: chequeFirstMethods,
        employees: const [
          {
            'id': 'employee-line-preferred',
            'first_name': 'Persona',
            'last_name': 'Preferente',
            'preferred_payment_method_id': 'method-transfer',
          },
        ],
        versionedMutationsAvailable: true,
      ),
    );
    await pump(tester, h.actions, size: const Size(1440, 900));

    expect(find.text('Transferencia'), findsOneWidget);
    await openPaymentWorkspace(tester);
    await tester.tap(find.text('Agregar parte'));
    await tester.pumpAndSettle();

    final editor = find.byKey(
      const ValueKey<String>('payroll-payment-inline-leg-editor'),
    );
    expect(
      find.descendant(of: editor, matching: find.text('Transferencia')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: editor, matching: find.text('Cheque')),
      findsNothing,
      reason: 'el primer método del catálogo no reemplaza la preferencia',
    );
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
    await openPaymentWorkspace(tester);
    await addSalaryPart(tester);
    expect(find.text(r'$100.000'), findsWidgets);

    await savePayment(tester);
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

    await openPaymentWorkspace(tester);
    expect(find.text('Anticipos disponibles'), findsOneWidget);
    await tester.tap(find.byType(Checkbox).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pumpAndSettle();
    expect(find.text(r'$80.000'), findsWidgets);
    expect(find.text(r'$20.000'), findsWidgets);
    await savePayment(tester);

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

  testWidgets('una confirmación con refresh fallido queda guardada una vez',
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

    await openPaymentWorkspace(tester);
    await addSalaryPart(tester);
    await savePayment(tester);

    expect(h.paid, hasLength(1));
    expect(find.textContaining('El servidor confirmó el movimiento'),
        findsOneWidget);
    expect(find.text('Guardado'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await savePayment(tester);
    expect(h.paid, hasLength(1));
    expect(find.textContaining('vista no pudo recargarse'), findsOneWidget);

    // L-H2: mientras la proyección siga vieja el aviso es PERSISTENTE (no un
    // snackbar que expira) y su Reintentar ejecuta la recarga real.
    final banner =
        find.byKey(const ValueKey<String>('payroll-stale-projection-banner'));
    expect(banner, findsOneWidget);
    await tester.tap(paymentWorkspaceClose());
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
    await openPaymentWorkspace(tester);
    await addSalaryPart(tester);
    await savePayment(tester);
    expect(h.paid, hasLength(2));
  });

  testWidgets('un comando que revienta NO afirma que el servidor confirmó',
      (tester) async {
    // **Medido contra producción el 2026-08-10.** El dueño tenía este cartel en
    // pantalla diciendo «El servidor confirmó el último movimiento» mientras la
    // base de datos tenía CERO filas en `payroll_statement_imports` y CERO en
    // `payroll_money_operations`: no se había confirmado nada. Una pantalla de
    // dinero que afirma un movimiento inexistente manda a buscar plata que
    // nadie movió.
    late PayrollRedesignData firstData;
    final h = harness(
      beforePayLine: () async => throw Exception('caída de transporte'),
      onLoad: (call) async {
        // La recarga autoritativa tampoco llega: sin ella nadie puede resolver
        // la ambigüedad, y es justo cuando el cartel se queda en pantalla.
        if (call > 1) throw StateError('refresh unavailable');
        return firstData;
      },
    );
    firstData = PayrollRedesignData(
      vouchers: [voucher()],
      paymentMethods: paymentMethods,
    );
    await pump(tester, h.actions, size: const Size(1440, 900));

    await openPaymentWorkspace(tester);
    await addSalaryPart(tester);
    await savePayment(tester);

    expect(h.paid, isEmpty);
    final banner =
        find.byKey(const ValueKey<String>('payroll-stale-projection-banner'));
    expect(
      banner,
      findsOneWidget,
      reason: 'sin recibo no se sabe si alcanzó a escribirse: la valla queda',
    );
    expect(
      find.descendant(
        of: banner,
        matching: find.textContaining('No pudimos verificar'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: banner,
        matching: find.textContaining('El servidor confirmó'),
      ),
      findsNothing,
      reason: 'no hubo recibo: afirmar una confirmación sería inventarla',
    );
  });

  testWidgets('una precondición sin write no levanta la valla ambigua',
      (tester) async {
    var attempts = 0;
    final h = harness(
      beforePayLine: () async {
        attempts += 1;
        if (attempts == 1) {
          throw const PayrollVoucherPreflightException.rejected(
            'La semana cambió antes de enviar el pago. Revisa e intenta otra vez.',
          );
        }
      },
    );
    await pump(tester, h.actions, size: const Size(1440, 900));

    await openPaymentWorkspace(tester);
    await addSalaryPart(tester);
    await savePayment(tester);

    expect(attempts, 1);
    expect(h.paid, isEmpty);
    expect(
      find.textContaining('antes de enviar el pago'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('payroll-stale-projection-banner')),
      findsNothing,
      reason: 'el servicio garantiza que el RPC no salió',
    );
    expect(find.textContaining('No pudimos verificar'), findsNothing);

    // El mismo panel puede reintentar de inmediato: no quedó una valla falsa.
    await savePayment(tester);
    expect(attempts, 2);
    expect(h.paid, hasLength(1));
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
    await tester.pumpWidget(
      MaterialApp.router(
        // Mismo motivo que el arnés de arriba: sin el tema del resolver no
        // existe `VinabikeThemeRoles`, y ningún componente compartido puede
        // montarse — el esqueleto `X-01` de la carga se niega a pintar. El
        // arnés sin tema no representaba a la app (2026-08-01).
        theme: AppTheme.resolve(
          preset: AppearancePresets.all.first,
          brightness: Brightness.light,
        ),
        routerConfig: router,
      ),
    );
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

    await openPaymentWorkspace(tester);
    await tester.tap(find.text('Agregar parte'));
    await tester.pumpAndSettle();

    // Registered contract: duplicate names identify their accounting
    // account, never a positional/numeric suffix.
    final secondAccount = find.text('Transferencia · Banco secundario');
    expect(
      find.text('Transferencia · Banco principal'),
      findsOneWidget,
    );
    expect(find.text('Transferencia (2)'), findsNothing);

    await tester.tap(
      find.text('Transferencia · Banco principal'),
    );
    await tester.pumpAndSettle();
    expect(secondAccount, findsOneWidget);
    await tester.ensureVisible(secondAccount);
    await tester.tap(secondAccount);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar parte'));
    await tester.pumpAndSettle();
    await savePayment(tester);

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
    await tester.pumpWidget(
      MaterialApp.router(
        // Mismo motivo que el arnés de arriba: sin el tema del resolver no
        // existe `VinabikeThemeRoles`, y ningún componente compartido puede
        // montarse — el esqueleto `X-01` de la carga se niega a pintar. El
        // arnés sin tema no representaba a la app (2026-08-01).
        theme: AppTheme.resolve(
          preset: AppearancePresets.all.first,
          brightness: Brightness.light,
        ),
        routerConfig: router,
      ),
    );
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
    //
    // `5c` · la palabra nombra QUÉ falta confirmar y usa el mismo vocabulario
    // que la tarjeta de la semana (`SIN CONFIRMAR`). «Falta confirmar», en
    // Design, es el efectivo entregado y pendiente —una fila que SÍ se puede
    // resolver—, así que no puede significar también «la semana es borrador».
    expect(find.text('Semana sin confirmar'), findsWidgets);
    expect(find.text('Falta confirmar'), findsNothing);
    expect(find.text('Pagar'), findsNothing);
    expect(h.paid, isEmpty);

    // `5c`: la forma pasiva es texto, no una píldora. Con producción en
    // borrador casi todas las filas caen acá, así que una píldora hacía que la
    // tabla entera pareciera accionable sin serlo.
    //
    // La fila es la de **Lucas Reyes**, no la de Vicente: Vicente entra al
    // fixture ya saldado, y `_statusOf` sólo bloquea por borrador cuando queda
    // saldo — a quien ya se le pagó le corresponde el chip `Pagado`, que sí es
    // un control. Afirmarlo sobre Vicente medía la forma equivocada.
    //
    // Se afirma sobre el ESTILO del texto, no sobre la ausencia de `InkWell`:
    // la píldora anterior tampoco tenía uno —era un `Container` pintado—, así
    // que esa aserción pasaba con y sin el defecto. Se comprobó devolviendo la
    // píldora: sólo el estilo la caza.
    final blocked = tester.widget<Text>(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('payroll-row-actions-Lucas Reyes'),
        ),
        matching: find.text('Semana sin confirmar'),
      ),
    );
    expect(blocked.style?.fontSize, 11);
    expect(blocked.style?.fontWeight, FontWeight.w400);

    // Una sola acción primaria: el lenguaje distingue obligación de pago.
    expect(find.text('Confirmar semana'), findsOneWidget);
    await tester.tap(find.text('Confirmar semana'));
    await tester.pumpAndSettle();
    // 5d titula la acción, no la pregunta: el diálogo ya es la pregunta.
    expect(find.text('Confirmar esta semana'), findsOneWidget);
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

  testWidgets(
      '5c · la franja del pie sólo habla cuando todas las filas comparten '
      'motivo', (tester) async {
    // Compartido: la semana en borrador bloquea a todos por lo mismo, así que
    // el motivo se dice UNA vez y se ve sin pasar el puntero por ningún lado.
    final iguales = harness(
      vouchers: [voucher(status: PayrollVoucherStatus.draft, day: 6)],
    );
    await pump(tester, iguales.actions, size: const Size(1440, 900));
    expect(
      find.byKey(const ValueKey<String>('payroll-blocked-note')),
      findsOneWidget,
    );
    expect(find.text('Esta semana todavía no se puede pagar'), findsOneWidget);
    expect(find.textContaining('está en borrador'), findsOneWidget);

    // Mezclados: Rocío no tiene horas cerradas —motivo suyo— y el resto está
    // bloqueado por la semana. Una sola franja tendría que elegir una de las
    // dos razones y le mentiría a la otra, así que calla.
    final mezclados = harness(
      vouchers: [
        voucher(
          status: PayrollVoucherStatus.draft,
          day: 6,
          lines: [
            line(id: 'l-1', name: 'Lucas Reyes'),
            line(id: 'l-2', name: 'Rocío Álvarez', hours: 0, total: 0),
          ],
        ),
      ],
    );
    await pump(tester, mezclados.actions, size: const Size(1440, 900));
    expect(
      find.byKey(const ValueKey<String>('payroll-blocked-note')),
      findsNothing,
      reason: 'dos razones distintas no caben en una sola franja',
    );
    expect(find.text('Semana sin confirmar'), findsWidgets);
    expect(find.text('Horas sin cerrar'), findsWidgets);
  });

  testWidgets(
      '5c · a 430 el motivo de la SEMANA no se repite por tarjeta; el de la '
      'persona sí', (tester) async {
    // El motivo del borrador es idéntico en las cuatro tarjetas y la barra ya
    // ofrece `Confirmar semana`: repetirlo se comía los cuatro registros del
    // primer viewport que pide `5l`, para no decir nada nuevo.
    final semana = harness(
      vouchers: [voucher(status: PayrollVoucherStatus.draft, day: 6)],
    );
    await pump(tester, semana.actions, size: const Size(430, 932));

    expect(find.text('Semana sin confirmar'), findsWidgets);
    expect(
      find.textContaining('hasta confirmarla las horas'),
      findsNothing,
      reason: 'el marco ya explica el estado de la semana',
    );

    // Pero cuando el bloqueo es de ESTA persona —Asistencias no cerró SUS
    // horas—, la tarjeta lo dice: no hay otro lugar en el teléfono que lo diga.
    final persona = harness(
      vouchers: [
        voucher(
          lines: [
            line(
                id: 'line-sin-horas',
                name: 'Rocío Álvarez',
                hours: 0,
                total: 0),
          ],
        ),
      ],
    );
    await pump(tester, persona.actions, size: const Size(430, 932));

    expect(find.text('Horas sin cerrar'), findsWidgets);
    expect(
      find.textContaining('Asistencias todavía no cierra las horas'),
      findsOneWidget,
    );
  });

  // ---- 5d · confirmación de semana (turno 5, `handoff-t5/frames/5d.png`) ----
  //
  // Design dibuja 5d como el CIERRE de una semana ya pagada («todos los saldos
  // en cero», la tarjeta pasa a PAGADA). Acá la acción confirma un BORRADOR y
  // crea los sueldos por pagar, así que el resumen dice lo que esta acción
  // hace. Estas tres pruebas fijan esa adaptación para que nadie la deshaga
  // copiando el frame literal más adelante.

  testWidgets(
      '5d · el diálogo declara su alcance y no promete pagos que no existen',
      (tester) async {
    final h = harness(
      vouchers: [voucher(status: PayrollVoucherStatus.draft, day: 6)],
    );
    await pump(tester, h.actions, size: const Size(1440, 900));
    await tester.tap(find.text('Confirmar semana'));
    await tester.pumpAndSettle();

    final dialog = find.byType(Dialog);
    expect(dialog, findsOneWidget);

    // El ancho que publica el spec del turno 5: «diálogo 460 · CTA 34».
    expect(
      find.descendant(
        of: dialog,
        matching: find.byWidgetPredicate(
          (w) => w is ConstrainedBox && w.constraints.maxWidth == 460,
        ),
      ),
      findsOneWidget,
      reason: '5d publica el diálogo a 460',
    );

    // El resumen numérico rotulado que 5d aporta sobre el diálogo anterior.
    expect(
      find.descendant(
        of: dialog,
        matching: find.text('QUEDARÁ CONFIRMADA CON'),
      ),
      findsOneWidget,
    );
    // El total, escrito por `F-03 VbMoneyText`: 3 × $172.875. No hay una
    // segunda fila repitiendo el mismo monto — con una sola categoría, el
    // desglose decía dos veces lo que la frase de encabezado ya dice.
    expect(
      find.descendant(of: dialog, matching: find.byType(VbMoneyText)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text(r'$518.625')),
      findsOneWidget,
    );

    // Lo DESCARTADO del frame. Al confirmar un borrador no hay ni un pago
    // registrado: prometer transferencias, efectivo o una diferencia bajo
    // tolerancia sería una pantalla mintiendo sobre dinero.
    // `inmutable` va en esta lista por una razón distinta a las demás: no es
    // una capacidad que falte, es una afirmación **falsa** del frame.
    // `revertToDraft` → `revert_payroll_to_draft` devuelve una semana
    // confirmada a borrador **mientras no haya pagos**; los pagos, mientras
    // existen, bloquean ese retorno, y se deshacen con `revert_payroll_payment`
    // —nunca editándolos en sitio—. Y tampoco se
    // promete «reabrir»: el servicio lo permite, pero ninguna superficie lo
    // expone hoy.
    for (final promesa in const <String>[
      'transferencias',
      'entrega en efectivo',
      'diferencia bajo tolerancia',
      'saldos en cero',
      'Deshacer',
      'Contabilidad',
      'Mensajería',
      'inmutable',
      'reabr',
    ]) {
      expect(
        find.descendant(of: dialog, matching: find.textContaining(promesa)),
        findsNothing,
        reason: 'confirmar un borrador no promete «$promesa»',
      );
    }

    // Los dos checkboxes de efecto lateral de 5d son capacidad nueva —el
    // asiento contable ya se crea por pago y no hay canal a empleados—, así
    // que no se dibujan como si funcionaran.
    expect(
      find.descendant(of: dialog, matching: find.byType(Checkbox)),
      findsNothing,
    );
  });

  testWidgets(
      '5d · a quien queda en \$0 se le nombra, no se le resta en silencio',
      (tester) async {
    final h = harness(
      vouchers: [
        voucher(
          status: PayrollVoucherStatus.draft,
          lines: [
            line(id: 'line-1', name: 'Vicente Soto'),
            line(id: 'line-2', name: 'Lucas Reyes'),
            line(id: 'line-3', name: 'Guillermo Pinto', total: 0),
          ],
        ),
      ],
    );
    await pump(tester, h.actions, size: const Size(1440, 900));
    await tester.tap(find.text('Confirmar semana'));
    await tester.pumpAndSettle();

    final dialog = find.byType(Dialog);
    // El alcance cuenta 2 de 3: una línea en $0 no genera sueldo por pagar.
    expect(
      find.descendant(of: dialog, matching: find.textContaining('2 personas')),
      findsOneWidget,
    );
    // Y la exclusión se declara, en vez de desaparecer dentro del número.
    expect(
      find.descendant(
        of: dialog,
        matching: find.textContaining('1 persona queda'),
      ),
      findsOneWidget,
      reason:
          'el frame no contempla el caso; callarlo deja el total sin explicar',
    );
  });

  testWidgets('5d · a 390 el pie se apila y «Esc cancela» no se dibuja',
      (tester) async {
    final h = harness(
      vouchers: [voucher(status: PayrollVoucherStatus.draft, day: 6)],
    );
    await pump(tester, h.actions, size: const Size(390, 844));
    await tester.tap(
      find.byKey(const ValueKey('payroll-mobile-primary-action')),
    );
    await tester.pumpAndSettle();

    final dialog = find.byType(Dialog);
    expect(dialog, findsOneWidget);

    final submit =
        find.byKey(const ValueKey('payroll-confirm-week-dialog-submit'));
    expect(submit, findsOneWidget);

    // En un teléfono no hay tecla Esc: anunciar un atajo inexistente es ruido,
    // y además desarmaba el pie en tres pedazos a 390.
    expect(
      find.descendant(of: dialog, matching: find.text('Esc cancela')),
      findsNothing,
    );

    // Una decisión por pantalla: el primario a ancho completo, con el target
    // táctil que publica `F-06 VbDensity` (`Control/botón · TOUCH 48`). El
    // frame 5l dice «CTA 50» y **no se sigue**: el dueño canónico de densidad
    // manda sobre un frame de módulo, y `touchMobile` ya vale 48.
    final button = tester.getSize(submit);
    final sheet = tester.getSize(
      find.descendant(of: dialog, matching: find.byType(Column)).first,
    );
    expect(button.height, PayrollTokens.touchMobile);
    expect(button.width, greaterThan(sheet.width * 0.9),
        reason:
            'el CTA compacto va a ancho completo, no encajonado a la derecha');

    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '5d · el pie cambia en el umbral que publica ResponsiveViewport, no en un 600 escrito a mano',
      (tester) async {
    // Se prueba contra la constante, no contra su valor: si el owner mueve el
    // breakpoint, este test lo sigue en vez de contradecirlo.
    const boundary = ResponsiveViewport.phoneMaxExclusive;

    for (final probe in <({double width, bool compact})>[
      (width: boundary - 1, compact: true),
      (width: boundary, compact: false),
    ]) {
      final h = harness(
        vouchers: [voucher(status: PayrollVoucherStatus.draft, day: 6)],
      );
      await pump(tester, h.actions, size: Size(probe.width, 900));
      // El CTA que abre el diálogo NO cambia de dueño en este mismo umbral: la
      // barra compacta llega hasta tablet, así que se toma el que exista en vez
      // de suponer cuál. Lo que este test fija es el pie del DIÁLOGO.
      final mobileCta =
          find.byKey(const ValueKey('payroll-mobile-primary-action'));
      await tester.tap(
        mobileCta.evaluate().isNotEmpty
            ? mobileCta
            : find.byKey(const ValueKey('payroll-confirm-week')),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Esc cancela'),
        ),
        probe.compact ? findsNothing : findsOneWidget,
        reason: 'a ${probe.width}px el pie debería ser '
            '${probe.compact ? 'compacto' : 'ancho'}',
      );
      await tester.tap(find.text('Volver a revisar'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
      '5l · el CTA de la tarjeta de persona mide TOUCH 48, el valor del owner de densidad',
      (tester) async {
    // Este contrato existe porque el valor **no es verificable en runtime sin
    // escribir en producción**: la acción de pago sólo aparece en una semana
    // ya confirmada, y confirmar una es un write real. Antes medía `50`
    // literal, copiado del frame 5l; el dueño canónico es `F-06 VbDensity`
    // (`Control/botón · TOUCH 48`) y un frame de módulo no lo sobrescribe.
    final h = harness(
      vouchers: [voucher(status: PayrollVoucherStatus.confirmed, day: 6)],
    );
    await pump(tester, h.actions, size: const Size(390, 900));

    final action = find.byKey(
      const ValueKey('payroll-mobile-person-action-Lucas Reyes'),
    );
    expect(action, findsOneWidget,
        reason: 'una semana confirmada con saldo ofrece la acción de pago');
    expect(
      tester.getSize(action).height,
      PayrollTokens.touchMobile,
      reason: 'el frame 5l dibuja 50; manda F-06 · TOUCH 48',
    );
  });

  testWidgets(
      '5d · el rótulo dice «Confirmar semana 27», no «Semana» a media frase',
      (tester) async {
    final h = harness(
      vouchers: [
        voucher(status: PayrollVoucherStatus.draft, day: 6)
            .copyWith(periodLabel: 'Semana 27: 29 jun - 05 jul'),
      ],
    );
    await pump(tester, h.actions, size: const Size(1440, 900));
    await tester.tap(find.text('Confirmar semana'));
    await tester.pumpAndSettle();

    // En español el sustantivo va en minúscula dentro de la frase; la mayúscula
    // a media oración es calco del inglés.
    expect(find.text('Confirmar semana 27: 29 jun - 05 jul'), findsOneWidget);
    expect(find.text('Confirmar Semana 27: 29 jun - 05 jul'), findsNothing);
  });

  testWidgets(
      '5d · en escritorio el pie conserva «Esc cancela» y los dos botones en línea',
      (tester) async {
    final h = harness(
      vouchers: [voucher(status: PayrollVoucherStatus.draft, day: 6)],
    );
    await pump(tester, h.actions, size: const Size(1440, 900));
    await tester.tap(find.text('Confirmar semana'));
    await tester.pumpAndSettle();

    final dialog = find.byType(Dialog);
    expect(
      find.descendant(of: dialog, matching: find.text('Esc cancela')),
      findsOneWidget,
      reason: 'con teclado sí existe el atajo, y decirlo ahorra un clic',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin semanas ofrece una salida real a Asistencias en ambos modos',
      (tester) async {
    // El fixture declara un trabajador contratado a propósito: **sin nadie
    // contratado el vacío correcto ya no es éste**, sino el que manda a
    // Trabajadores — mandar a cerrar horas de gente que no existe era el
    // defecto (5k, 2026-08-01). Ver `payroll_loading_skeleton_test.dart`.
    final h = harness(
      vouchers: const [],
      employees: const <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'employee-line-1',
          'first_name': 'Vicente',
          'last_name': 'Soto',
          'status': 'active',
        },
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
    await tester.pumpWidget(
      MaterialApp.router(
        // Mismo motivo que el arnés de arriba: sin el tema del resolver no
        // existe `VinabikeThemeRoles`, y ningún componente compartido puede
        // montarse — el esqueleto `X-01` de la carga se niega a pintar. El
        // arnés sin tema no representaba a la app (2026-08-01).
        theme: AppTheme.resolve(
          preset: AppearancePresets.all.first,
          brightness: Brightness.light,
        ),
        routerConfig: router,
      ),
    );
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
    await tester.pumpWidget(
      MaterialApp.router(
        // Mismo motivo que el arnés de arriba: sin el tema del resolver no
        // existe `VinabikeThemeRoles`, y ningún componente compartido puede
        // montarse — el esqueleto `X-01` de la carga se niega a pintar. El
        // arnés sin tema no representaba a la app (2026-08-01).
        theme: AppTheme.resolve(
          preset: AppearancePresets.all.first,
          brightness: Brightness.light,
        ),
        routerConfig: router,
      ),
    );
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
      'release gate de anticipos deja revisión honesta sin abrir formulario',
      (tester) async {
    final h = harness(
      releaseCapabilities: const PayrollReleaseCapabilities(
        employeePaymentMethodCommand: true,
      ),
    );
    await pump(tester, h.actions, size: const Size(1440, 900));

    await tester.tap(find.text('Anticipos'));
    await tester.pumpAndSettle();

    expect(find.text('No hay anticipos vigentes'), findsOneWidget);
    expect(find.text('Registrar anticipo'), findsNothing);
    expect(
      find.byKey(
        const ValueKey<String>('payroll-empty-advance-blocked-reason'),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('motivo y respaldo auditables'),
      findsOneWidget,
    );
    expect(find.byType(PayrollAdvanceEntry), findsNothing);
    expect(h.registeredAdvanceEmployees, isEmpty);
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
    // La explicación es obligatoria desde el contrato `v3`: sin ella el
    // formulario no devuelve intención, que es exactamente lo que queremos.
    await tester.enterText(
      find.byKey(const Key('payroll-advance-reason')),
      'Adelanto pedido por Beto',
    );
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

    await openPaymentWorkspace(tester);

    expect(find.text('Anticipos disponibles'), findsNothing);
    expect(find.byType(PayrollPaymentWorkspace), findsOneWidget);
    expect(find.text('Cómo se paga el sueldo'), findsOneWidget);
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

  testWidgets(
      'respaldo corrige un pago con motivo obligatorio y versión exacta',
      (tester) async {
    final payment = PayrollSettlementEvidence(
      id: 'payment-to-correct',
      voucherId: 'voucher-1',
      lineId: 'line-to-correct',
      kind: PayrollSettlementEvidenceKind.payment,
      source: PayrollSettlementEvidenceSource.manual,
      amount: 100000,
      effectiveDate: DateTime(2026, 8, 1),
      paymentMethodLabel: 'Transferencia',
      actorName: 'Claudio Catalán',
    );
    final week = voucher(
      lines: [
        line(
          id: 'line-to-correct',
          name: 'Persona a corregir',
          total: 100000,
          settled: 100000,
          cashPaid: 100000,
          balance: 0,
          settlementEvidence: [payment],
        ),
      ],
    );
    final h = harness(vouchers: [week]);
    await pump(tester, h.actions, size: const Size(1440, 900));

    await tester.tap(
      find.byKey(
        const ValueKey<String>('payroll-paid-status-Persona a corregir'),
      ),
    );
    await tester.pumpAndSettle();
    final correction = find.byKey(
      const ValueKey<String>(
        'payroll-payment-evidence-correct-payment-to-correct',
      ),
    );
    expect(correction, findsOneWidget);
    await tester.tap(correction);
    await tester.pumpAndSettle();

    final confirm = find.byKey(
      const ValueKey<String>('payroll-settlement-correction-confirm'),
    );
    expect(find.text('Corregir pago'), findsOneWidget);
    expect(
      find.textContaining('El movimiento original y su respaldo no se borran'),
      findsOneWidget,
    );
    await tester.tap(confirm);
    await tester.pump();
    expect(
      find.text('Explica el motivo con al menos 3 caracteres.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(
        const ValueKey<String>('payroll-settlement-correction-reason'),
      ),
      'Cuenta bancaria seleccionada incorrectamente',
    );
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(h.corrected, hasLength(1));
    expect(h.corrected.single['voucherId'], 'voucher-1');
    expect(h.corrected.single['settlementId'], 'payment-to-correct');
    expect(
      h.corrected.single['settlementKind'],
      PayrollSettlementEvidenceKind.payment,
    );
    expect(
      h.corrected.single['reason'],
      'Cuenta bancaria seleccionada incorrectamente',
    );
    expect(h.corrected.single['version'], 7);
    expect(
      h.corrected.single['operationKey'],
      startsWith('payroll_settlement_reversal_'),
    );
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
    // **5n fila 18 · el PANEL DERECHO tiene que haber cambiado, no sólo la
    // hidratación.** Antes esto afirmaba que la palabra `ANULADA` aparecía en
    // algún lado —lo cual también es cierto con el chip de la lista y el
    // detalle todavía mostrando la semana anterior—. Se ancla al ledger: las
    // cifras de la semana PAGADA (efectivo $100.000, anticipo −$25.000) tienen
    // que haberse ido, y el total de la ANULADA tiene que estar.
    final ledger = find.byKey(const ValueKey('payroll-history-ledger'));
    expect(ledger, findsOneWidget);
    expect(
      find.descendant(of: ledger, matching: find.text(r'$100.000')),
      findsNothing,
      reason: 'el detalle sigue mostrando la semana pagada',
    );
    expect(
      find.descendant(of: ledger, matching: find.text(r'−$25.000')),
      findsNothing,
      reason: 'el anticipo de la semana pagada quedó en el panel',
    );
    expect(
      find.descendant(of: ledger, matching: find.text(r'$50.000')),
      findsWidgets,
      reason: 'el detalle no trajo el total de la semana anulada',
    );
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
    // 5i compacto: el primer paso es elegir semana en la lista, no desplegar
    // un select de treinta opciones paginadas.
    expect(
      find.byKey(const ValueKey('payroll-history-index-compact')),
      findsOneWidget,
    );
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('payroll-history-week-history-paid')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('payroll-history-compact-ledger')),
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
  // ── Deep link `/hr/payroll?scope=advances&employee=<id>` ─────────────────
  //
  // F4: un anticipo con motivo estructurado y comprobante original, que es lo
  // que `v3` entrega y el modelo descartaba.
  const advanceEmployees = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'worker-ana',
      'first_name': 'Ana',
      'last_name': 'Torres',
      'status': 'active',
      'preferred_payment_method_id': 'method-transfer',
    },
  ];

  const advancePaymentMethods = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'method-transfer',
      'name': 'Transferencia',
      'code': 'transfer',
      'account_id': 'account-transfer',
      'is_active': true,
    },
  ];

  List<EmployeeAdvance> advancesF4() => <EmployeeAdvance>[
        EmployeeAdvance(
          id: 'advance-rg',
          employeeId: 'worker-ana',
          amount: 36000,
          amountApplied: 0,
          paidAt: DateTime(2026, 7, 30, 12),
          status: 'open',
          reference: 'TRF-99887',
          notes: 'Registrado desde el centro de nóminas.',
          reasonCode: PayrollAdvanceReasonCode.shortWorkweek,
          reasonExplanation: 'Se fue el miércoles',
          workEndedOn: DateTime(2026, 7, 29),
        ),
      ];

  testWidgets(
      '5h · el ledger muestra la EXPLICACIÓN, no la referencia ni el origen',
      (tester) async {
    final h = harness(
      onLoad: (_) async => PayrollRedesignData(
        vouchers: <PayrollVoucher>[voucher()],
        paymentMethods: advancePaymentMethods,
        employees: advanceEmployees,
        openAdvances: advancesF4(),
      ),
    );
    await pump(
      tester,
      h.actions,
      size: const Size(1440, 900),
      initialScope: 'advances',
    );

    // La razón visible es lo que escribió el operador.
    expect(find.text('Se fue el miércoles'), findsWidgets);
    // La referencia bancaria NO es un motivo y no puede ocupar su lugar.
    expect(find.text('TRF-99887'), findsNothing);
    // El código se lee en castellano y la fecha condicional acompaña.
    expect(find.textContaining('Semana corta'), findsWidgets);
    expect(find.textContaining('Último día trabajado'), findsWidgets);
  });

  testWidgets(
      '5h · un employee que NO existe se DICE, no se sustituye en silencio',
      (tester) async {
    final h = harness(
      onLoad: (_) async => PayrollRedesignData(
        vouchers: <PayrollVoucher>[voucher()],
        paymentMethods: advancePaymentMethods,
        employees: advanceEmployees,
        openAdvances: advancesF4(),
      ),
    );
    await pump(
      tester,
      h.actions,
      size: const Size(1440, 900),
      initialScope: 'advances',
      initialAdvanceEmployeeId: 'nadie-con-este-id',
    );
    // Caer en la primera persona haría que el operador leyera el saldo de
    // otro creyendo que es el de quien pidió el enlace.
    expect(
      find.byKey(const ValueKey<String>('payroll-advance-target-missing')),
      findsOneWidget,
    );
    expect(find.text('No encontramos a esa persona'), findsOneWidget);
    expect(
      find.text('Se fue el miércoles'),
      findsNothing,
      reason: 'un enlace roto no puede pintar el ledger de Ana',
    );
    expect(find.text('Registrar anticipo'), findsNothing);

    await tester.tap(
      find.byKey(
        const ValueKey<String>('payroll-advance-target-missing-reset'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('payroll-advance-target-missing')),
      findsNothing,
    );
    expect(find.text('Se fue el miércoles'), findsWidgets);
  });

  testWidgets('5h · el enlace roto también se dice cuando no hay personas',
      (tester) async {
    final h = harness(
      onLoad: (_) async => PayrollRedesignData(
        vouchers: <PayrollVoucher>[voucher()],
        paymentMethods: advancePaymentMethods,
        employees: const <Map<String, dynamic>>[],
        openAdvances: const <EmployeeAdvance>[],
      ),
    );
    await pump(
      tester,
      h.actions,
      size: const Size(430, 900),
      initialScope: 'advances',
      initialAdvanceEmployeeId: 'nadie-con-este-id',
    );

    expect(
      find.byKey(const ValueKey<String>('payroll-advance-target-missing')),
      findsOneWidget,
    );
    expect(find.text('No hay anticipos vigentes'), findsNothing);
    expect(find.text('Registrar anticipo'), findsNothing);
  });

  testWidgets('5h · didUpdateWidget atiende un cambio de URL', (tester) async {
    final h = harness(
      onLoad: (_) async => PayrollRedesignData(
        vouchers: <PayrollVoucher>[voucher()],
        paymentMethods: advancePaymentMethods,
        employees: advanceEmployees,
        openAdvances: advancesF4(),
      ),
    );
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final employeeId = ValueNotifier<String?>('nadie-con-este-id');
    addTearDown(employeeId.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.all.first,
          brightness: Brightness.light,
        ),
        home: Scaffold(
          body: ValueListenableBuilder<String?>(
            valueListenable: employeeId,
            builder: (context, value, _) => PayrollRedesignPage(
              key: const ValueKey<String>('same-payroll-page'),
              actions: h.actions,
              initialScope: 'advances',
              initialAdvanceEmployeeId: value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('payroll-advance-target-missing')),
      findsOneWidget,
    );

    // Misma instancia de State, otra URL: esto sí ejecuta didUpdateWidget.
    employeeId.value = 'worker-ana';
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('payroll-advance-target-missing')),
      findsNothing,
      reason: 'el aviso no se queda pegado cuando el enlace sí se cumple',
    );
    expect(find.text('Se fue el miércoles'), findsWidgets);

    // Al retirar `?employee=`, tampoco queda pegado el target anterior.
    employeeId.value = null;
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('payroll-advance-target-missing')),
      findsNothing,
    );
  });
  // ── `5n` · matriz de cierre · notas Flutter ──────────────────────────────
  testWidgets(
      '5n · el ESTADO DE TRABAJO sobrevive al cambio de banda (la fila abierta '
      'sigue abierta)', (tester) async {
    // `5n` escribe «`LayoutBuilder` recompone, **nunca desmonta**». Esa
    // afirmación, tal cual, **no se cumple ni tiene por qué**: a 1440 el host
    // monta la rama de escritorio y bajo el breakpoint el host monta OTRA
    // rama: a 834 `_buildMobile` monta `PayrollQueueSurface` en su tier de
    // tablet —la tabla, no tarjetas; las tarjetas son de 430—, y aun así es
    // otro subárbol, así que SÍ se desmonta. Adaptado con razón: **el requisito de producto no es la
    // identidad del subárbol, es que el trabajo del operador no se pierda**, y
    // eso se cumple porque el estado vive en el `State` del host, no en la
    // superficie.
    //
    // **Lo que esta prueba cubre y lo que NO:** cubre la fila abierta. El
    // borrador del composer y el paso del OCR que la nota también nombra
    // **no** están cubiertos acá; el del OCR está además medido y documentado
    // como que NO sobrevive a salir del módulo (§2, fila `5j-p3`).
    final h = harness();
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.all.first,
          brightness: Brightness.light,
        ),
        home: Scaffold(body: PayrollRedesignPage(actions: h.actions)),
      ),
    );
    await tester.pumpAndSettle();

    // Por semántica, no por tooltip: `5c` le quitó el `Tooltip` al caret
    // porque un `OverlayPortal` visible dentro del `LayoutBuilder` de esta
    // tabla tumbaba el módulo al cambiar de banda (§4.24). La etiqueta
    // accesible se conservó entera, y es por donde se toca.
    final handle = tester.ensureSemantics();
    await tester.tap(
      find.bySemanticsLabel(RegExp('^Mostrar detalle de ')).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('CÓMO SE CALCULÓ'), findsOneWidget);

    // Mismo `State` padre, otro ancho — NO el mismo subárbol: bajo el
    // breakpoint el host monta otra rama. Es lo que hace la ventana al
    // redimensionarse, y lo que debe sobrevivir es el estado, no los widgets.
    tester.view.physicalSize = const Size(834, 1112);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.text('CÓMO SE CALCULÓ'),
      findsOneWidget,
      reason: 'la fila abierta se perdió al cambiar de banda',
    );
    expect(tester.takeException(), isNull);
    handle.dispose();
  });
}
