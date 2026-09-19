import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/accounting/bank_reconciliation/models/bank_reconciliation_models.dart';
import 'package:vinabike_erp/modules/accounting/pages/bank_reconciliation_page.dart';
import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/modules/settings/services/appearance_service.dart';
import 'package:vinabike_erp/shared/services/navigation_service.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
      httpClient: MockClient(
        (request) async => http.Response('{}', 200),
      ),
    );
  });

  for (final width in <double>[390, 834, 1440]) {
    testWidgets(
      'resolver is contextual and overflow-free at ${width.toInt()} px',
      (tester) async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(harness.app());
        await tester.pumpAndSettle();
        final baselineBarrierCount =
            find.byType(ModalBarrier).evaluate().length;

        expect(
          find.byKey(const ValueKey('bank-reconciliation-row-direct')),
          findsOneWidget,
        );
        expect(find.text('Directo incluido'), findsOneWidget);
        expect(find.text('Asociada'), findsOneWidget);
        expect(
          find.text('1 de 2 movimientos resueltos · 1 quedan pendientes'),
          findsOneWidget,
        );
        final transbankRow =
            find.byKey(const ValueKey('bank-reconciliation-row-transbank'));
        if (transbankRow.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            transbankRow,
            180,
            scrollable: find.descendant(
              of: find.byKey(
                const PageStorageKey('bank-reconciliation-rows'),
              ),
              matching: find.byType(Scrollable),
            ),
          );
          await tester.pump();
        }
        expect(transbankRow, findsOneWidget);
        expect(find.text('Estimado · revisar'), findsOneWidget);
        expect(find.text('Pendiente'), findsOneWidget);
        expect(
          find.text('FECHA'),
          width >= 900 ? findsOneWidget : findsNothing,
        );
        await tester.tap(
          find.byKey(
            const ValueKey('bank-reconciliation-resolve-transbank'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Vincular operación'));
        await tester.pump();
        await tester.tap(find.text('Vincular operación'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(
            const ValueKey('bank-reconciliation-resolution-workspace'),
          ),
          findsOneWidget,
        );
        expect(find.text('Vincular operación'), findsOneWidget);
        expect(find.text('Clasificar cuenta'), findsOneWidget);
        expect(find.text('Excluir'), findsOneWidget);
        expect(find.text('Dejar pendiente'), findsOneWidget);
        expect(
          find.text('2 ventas del recaudador estimadas'),
          findsOneWidget,
        );
        expect(find.textContaining('Bruto'), findsOneWidget);
        expect(
          find.byType(ModalBarrier).evaluate().length,
          baselineBarrierCount,
        );
        expect(
          find.byKey(const ValueKey('bank-reconciliation-row-direct')),
          width >= 900 ? findsOneWidget : findsNothing,
        );
        expect(find.byType(ErrorWidget), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('one ERP operation cannot be assigned to two bank movements',
      (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      harness.app(initialDraft: _draft(conflictingTransbankTarget: true)),
    );
    await tester.pumpAndSettle();

    final transbankRow =
        find.byKey(const ValueKey('bank-reconciliation-row-transbank'));
    await tester.scrollUntilVisible(
      transbankRow,
      180,
      scrollable: find.descendant(
        of: find.byKey(const PageStorageKey('bank-reconciliation-rows')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('bank-reconciliation-resolve-transbank')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vincular operación'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 ventas del recaudador estimadas'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'La misma operación ERP no puede asociarse a dos movimientos de la cartola.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('1 de 2 movimientos resueltos · 1 quedan pendientes'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('resolver exposes expense, classification and dismissal effects',
      (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('bank-reconciliation-resolve-direct')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('bank-reconciliation-action-createExpense'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Registrar un gasto pagado'), findsOneWidget);
    expect(find.text('Cuenta de gasto o costo'), findsOneWidget);
    expect(find.text('Medio de pago bancario'), findsOneWidget);
    expect(find.textContaining('Debe gasto o costo / Haber banco'),
        findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey('bank-reconciliation-action-classifyAccount'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Clasificar en el libro contable'), findsOneWidget);
    expect(find.text('Cuenta de contrapartida'), findsOneWidget);
    expect(
        find.textContaining('Genera un asiento contabilizado'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('bank-reconciliation-action-dismiss')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Motivo obligatorio'), findsOneWidget);
    expect(find.text('No se contabiliza ni se concilia'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('partial apply reports the accounting effects it committed',
      (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bank-reconciliation-save')));
    await tester.pumpAndSettle();

    expect(harness.createCalls, 1);
    expect(harness.applyCalls, 1);
    expect(find.text('Conciliación guardada'), findsOneWidget);
    expect(find.textContaining('1 vínculo(s)'), findsOneWidget);
    expect(find.textContaining('No se creó'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('a safe suggestion resolves an unregistered charge in one tap',
      (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(harness.app(initialDraft: _suggestedDraft()));
    await tester.pumpAndSettle();

    expect(find.text('Sugerencia'), findsOneWidget);
    expect(find.text('Google Cloud · Google'), findsOneWidget);
    expect(
      find.text('0 de 1 movimientos resueltos · 1 quedan pendientes'),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('bank-reconciliation-resolve-cloud')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sugerencia: Google Cloud · Google'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('bank-reconciliation-accept-suggestions')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('1 de 1 movimientos resueltos · 0 quedan pendientes'),
      findsOneWidget,
    );
    expect(find.text('Gasto listo'), findsOneWidget);
    expect(find.text('Sugerencia aplicada'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a salary Nómina owes is paid from the review', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(harness.app(initialDraft: _salaryDraft()));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('bank-reconciliation-resolve-braulio')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('bank-reconciliation-action-payPayroll')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('bank-reconciliation-use-suggestion')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('bank-reconciliation-payroll-summary')),
      findsOneWidget,
    );
    expect(
      find.textContaining('La semana está en borrador: se confirma'),
      findsOneWidget,
    );
    expect(find.text('Sueldo listo'), findsOneWidget);
    expect(
      find.text('1 de 1 movimientos resueltos · 0 quedan pendientes'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('a transfer that paid two operations is linked to both',
      (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(harness.app(initialDraft: _repaidDraft()));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('bank-reconciliation-resolve-mother')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vincular operación'));
    await tester.pumpAndSettle();

    Future<void> choose(String label) async {
      final search = find.byKey(
        const ValueKey('bank-reconciliation-existing-search-mother'),
      );
      await tester.ensureVisible(search);
      await tester.pumpAndSettle();
      await tester.tap(search);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    await choose('Sueldo Vicente · Semana 29');
    expect(find.text('Faltan \$38.500'), findsOneWidget);
    expect(
      find.text('0 de 2 movimientos resueltos · 2 quedan pendientes · '
          '1 ya conciliados'),
      findsOneWidget,
    );

    await choose('Sueldo Lucas · Semana 29');
    expect(find.text('Suman lo mismo que el movimiento'), findsOneWidget);
    expect(
      find.text('1 de 2 movimientos resueltos · 1 quedan pendientes · '
          '1 ya conciliados'),
      findsOneWidget,
    );

    final remove = find.byKey(
      const ValueKey('bank-reconciliation-manual-remove-expensePayment:lucas'),
    );
    await tester.ensureVisible(remove);
    await tester.pumpAndSettle();
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(find.text('Faltan \$38.500'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a repayment is split into a paid expense and the rest',
      (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(harness.app(initialDraft: _repaidDraft()));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('bank-reconciliation-resolve-other')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('bank-reconciliation-action-split')),
    );
    await tester.pumpAndSettle();

    Future<void> pick(String key, String label) async {
      final field = find.byKey(ValueKey(key));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    Future<void> type(String key, String text) async {
      final field = find.byKey(ValueKey(key));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, text);
      await tester.pumpAndSettle();
    }

    expect(find.text('Lo que queda: \$5.000'), findsOneWidget);
    await pick('bank-reconciliation-split-account-other-0',
        '6201 · Servicios digitales');
    await pick('bank-reconciliation-split-supplier-other-0', 'Pedro Madrid');
    await type('bank-reconciliation-split-description-other-0-2',
        'Honorarios contador');
    await type('bank-reconciliation-split-amount-other-0-2', '3000');
    expect(find.text('Lo que queda: \$2.000'), findsOneWidget);

    await pick('bank-reconciliation-split-account-other-1',
        '2150 · IVA Débito Fiscal');
    await type('bank-reconciliation-split-description-other-1-2', 'F29');
    expect(find.text('División lista'), findsOneWidget);
    expect(
      find.text('1 de 2 movimientos resueltos · 1 quedan pendientes · '
          '1 ya conciliados'),
      findsOneWidget,
    );
    // The supplier is asked only where an expense is created.
    expect(
      find.byKey(const ValueKey('bank-reconciliation-split-supplier-other-1')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the split editor fits a phone', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(harness.app(initialDraft: _repaidDraft()));
    await tester.pumpAndSettle();
    final resolve =
        find.byKey(const ValueKey('bank-reconciliation-resolve-other'));
    // The phone list builds rows lazily.
    await tester.scrollUntilVisible(
      resolve,
      180,
      scrollable: find.descendant(
        of: find.byKey(const PageStorageKey('bank-reconciliation-rows')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(resolve);
    await tester.pumpAndSettle();
    final split =
        find.byKey(const ValueKey('bank-reconciliation-action-split'));
    await tester.ensureVisible(split);
    await tester.pumpAndSettle();
    await tester.tap(split);
    await tester.pumpAndSettle();
    final add =
        find.byKey(const ValueKey('bank-reconciliation-split-add-other'));
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();

    expect(find.text('Parte 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a movement settled before is shown, not decided again',
      (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(harness.app(initialDraft: _repaidDraft()));
    await tester.pumpAndSettle();

    expect(find.text('Ya conciliado'), findsOneWidget);
    expect(find.text('1 ya conciliados'), findsOneWidget);
    expect(
      find.text('0 de 2 movimientos resueltos · 2 quedan pendientes · '
          '1 ya conciliados'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('bank-reconciliation-resolve-google')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ya se aplicó en esta cartola'), findsOneWidget);
    expect(find.text('¿Qué corresponde hacer?'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

/// The owner's mother paid two salaries and was repaid in one transfer; an
/// earlier sitting already applied the subscription.
BankReconciliationPreparedDraft _repaidDraft() {
  BankStatementMovement movement(String id, int ordinal, int amount,
          String description, int balance) =>
      BankStatementMovement(
        sourceRowId: id,
        ordinal: ordinal,
        bookingDate: const BankCivilDate(2026, 7, 7),
        description: description,
        normalizedDescription: description.toLowerCase(),
        direction: BankMovementDirection.debit,
        amountClp: amount,
        balanceClp: balance,
        sourcePage: 1,
        sourceLineStart: ordinal,
        sourceLineEnd: ordinal,
      );
  BankReconciliationCandidate salary(String id, String label, int amount) =>
      BankReconciliationCandidate(
        targetKind: BankReconciliationTargetKind.expensePayment,
        targetId: id,
        direction: BankMovementDirection.debit,
        amountClp: amount,
        occurredOn: const BankCivilDate(2026, 8, 12),
        label: label,
      );
  return BankReconciliationPreparedDraft(
    fileSha256:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    filename: 'cartola julio.pdf',
    sourceType: 'pdf_text',
    parserName: 'banco_chile_statement',
    parserVersion: 'v1',
    rows: <BankReconciliationRowDraft>[
      BankReconciliationRowDraft(
        movement: movement('google', 1, 2690, 'Pago: Google Play', 500000),
        proposals: const <BankReconciliationProposal>[],
        settled: const BankSettledMovement(
          sameStatement: true,
          summary: 'Gasto GTO-00200',
          disposition: BankReconciliationDisposition.reconciled,
          decidedOn: BankCivilDate(2026, 9, 19),
        ),
      ),
      BankReconciliationRowDraft(
        movement: movement(
          'mother',
          2,
          133000,
          'App-traspaso A: Maria Angelica Sandoval',
          367000,
        ),
        proposals: const <BankReconciliationProposal>[],
      ),
      BankReconciliationRowDraft(
        movement: movement('other', 3, 5000, 'App-traspaso A: Otro', 362000),
        proposals: const <BankReconciliationProposal>[],
      ),
    ],
    candidateCatalog: <BankReconciliationCandidate>[
      salary('vicente', 'Sueldo Vicente · Semana 29', 94500),
      salary('lucas', 'Sueldo Lucas · Semana 29', 38500),
      salary('decoy', 'Sueldo Fernando · Semana 29', 72000),
    ],
  );
}

BankReconciliationPreparedDraft _salaryDraft() {
  final movement = BankStatementMovement(
    sourceRowId: 'braulio',
    ordinal: 1,
    bookingDate: const BankCivilDate(2026, 8, 31),
    description: 'App-traspaso A: Braulio Munoz Internet',
    normalizedDescription: 'app traspaso a braulio munoz internet',
    counterpartyObserved: 'Braulio Munoz Internet',
    direction: BankMovementDirection.debit,
    amountClp: 71400,
    sourcePage: 1,
    sourceLineStart: 1,
    sourceLineEnd: 1,
  );
  const payroll = BankPayrollPaymentDraft(
    voucherId: 'voucher-37',
    voucherNumber: 'NOM-00037',
    periodLabel: 'Semana 35',
    lineId: 'line-braulio',
    employeeName: 'Braulio Muñoz',
    expectedAmountClp: 71400,
    amountClp: 71400,
    paymentMethodId: 'bank-method',
    confirmDraft: true,
  );
  return BankReconciliationPreparedDraft(
    fileSha256:
        'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
    filename: 'cartola agosto.pdf',
    sourceType: 'pdf_text',
    parserName: 'banco_chile_statement',
    parserVersion: 'v1',
    rows: <BankReconciliationRowDraft>[
      BankReconciliationRowDraft(
        movement: movement,
        proposals: const <BankReconciliationProposal>[],
        suggestion: BankReconciliationSuggestion(
          kind: BankSuggestionKind.payroll,
          confidence: BankReconciliationConfidence.high,
          title: 'Sueldo de Braulio Muñoz · Semana 35',
          reasons: const <String>[
            'Nómina NOM-00037 le debe \$71.400 y aún no registra el pago',
          ],
          resolution: const BankReconciliationResolutionDraft(
            action: BankReconciliationActionKind.payPayroll,
            payroll: payroll,
          ),
        ),
      ),
    ],
  );
}

BankReconciliationPreparedDraft _suggestedDraft() {
  final movement = BankStatementMovement(
    sourceRowId: 'cloud',
    ordinal: 1,
    bookingDate: const BankCivilDate(2026, 9, 2),
    description: 'Pago: Google Cloud Jl5r Renca',
    normalizedDescription: 'pago google cloud jl5r renca',
    direction: BankMovementDirection.debit,
    amountClp: 9928,
    sourcePage: 1,
    sourceLineStart: 1,
    sourceLineEnd: 1,
  );
  return BankReconciliationPreparedDraft(
    fileSha256:
        'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
    filename: 'cartola septiembre.pdf',
    sourceType: 'pdf_text',
    parserName: 'banco_chile_statement',
    parserVersion: 'v1',
    rows: <BankReconciliationRowDraft>[
      BankReconciliationRowDraft(
        movement: movement,
        proposals: const <BankReconciliationProposal>[],
        suggestion: BankReconciliationSuggestion(
          kind: BankSuggestionKind.createExpense,
          confidence: BankReconciliationConfidence.high,
          title: 'Google Cloud · Google',
          reasons: const <String>['Cargo con tarjeta en Google'],
          resolution: const BankReconciliationResolutionDraft(
            action: BankReconciliationActionKind.createExpense,
            accountId: 'expense-account',
            paymentMethodId: 'bank-method',
            description: 'Google Cloud',
            counterparty: 'Google',
          ),
        ),
      ),
    ],
  );
}

class _Harness {
  _Harness()
      : navigation = NavigationService(),
        workspaces = WorkspaceManager(
          sessionIdentity: 'bank-reconciliation-widget-test',
        ),
        appearance = AppearanceService(),
        chat = ChatProvider() {
    workspace = workspaces.activeWorkspace!
      ..isPinned = true
      ..pinnedRouteRoot = '/accounting';
  }

  final NavigationService navigation;
  final WorkspaceManager workspaces;
  final AppearanceService appearance;
  final ChatProvider chat;
  late final Workspace workspace;
  int createCalls = 0;
  int applyCalls = 0;

  Widget app({BankReconciliationPreparedDraft? initialDraft}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<NavigationService>.value(value: navigation),
        ChangeNotifierProvider<WorkspaceManager>.value(value: workspaces),
        ChangeNotifierProvider<AppearanceService>.value(value: appearance),
        ChangeNotifierProvider<ChatProvider>.value(value: chat),
        Provider<Workspace>.value(value: workspace),
      ],
      child: MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.pacific,
          brightness: Brightness.light,
        ),
        home: BankReconciliationPage(
          initialDraft: initialDraft ?? _draft(),
          actions: BankReconciliationActions(
            loadBankAccounts: () async =>
                const <BankReconciliationAccountOption>[
              BankReconciliationAccountOption(
                accountId: 'bank-account',
                code: '1101',
                name: 'Banco de Chile',
              ),
            ],
            loadWorkspaceOptions: ({required erpAccountId}) async =>
                BankReconciliationWorkspaceOptions(
              accounts: const <BankReconciliationLedgerAccountOption>[
                BankReconciliationLedgerAccountOption(
                  accountId: 'expense-account',
                  code: '6201',
                  name: 'Servicios digitales',
                  type: 'expense',
                ),
                BankReconciliationLedgerAccountOption(
                  accountId: 'income-account',
                  code: '4100',
                  name: 'Otros ingresos',
                  type: 'income',
                ),
                BankReconciliationLedgerAccountOption(
                  accountId: 'vat-account',
                  code: '2150',
                  name: 'IVA Débito Fiscal',
                  type: 'liability',
                ),
              ],
              suppliers: const <BankReconciliationSupplierOption>[
                BankReconciliationSupplierOption(
                  supplierId: 'pedro',
                  name: 'Pedro Madrid',
                ),
              ],
              paymentMethods: const <BankReconciliationPaymentMethodOption>[
                BankReconciliationPaymentMethodOption(
                  paymentMethodId: 'bank-method',
                  code: 'bank_transfer',
                  name: 'Cuenta corriente',
                  accountId: 'bank-account',
                ),
              ],
            ),
            prepare: ({
              required files,
              required erpAccountId,
            }) async =>
                _draft(),
            createImport: ({
              required draft,
              required erpAccountId,
              operationKey,
            }) async {
              createCalls++;
              return BankStatementImportReceipt(
                importId: 'import-id',
                revision: 1,
                rowIdsBySourceRowId: const <String, String>{
                  'direct': 'row-direct',
                  'transbank': 'row-transbank',
                },
                replayed: false,
              );
            },
            apply: ({
              required draft,
              required importReceipt,
              operationKey,
            }) async {
              applyCalls++;
              return const BankReconciliationApplyReceipt(
                importId: 'import-id',
                revision: 2,
                status: 'partially_reconciled',
                allocationCount: 1,
                replayed: false,
              );
            },
          ),
        ),
      ),
    );
  }

  void dispose() {
    navigation.dispose();
    workspaces.dispose();
    appearance.dispose();
    chat.dispose();
  }
}

BankReconciliationPreparedDraft _draft({
  bool conflictingTransbankTarget = false,
}) {
  final directMovement = BankStatementMovement(
    sourceRowId: 'direct',
    ordinal: 1,
    bookingDate: const BankCivilDate(2026, 8, 12),
    description: 'Transferencia a proveedor Taller Uno',
    normalizedDescription: 'transferencia a proveedor taller uno',
    direction: BankMovementDirection.debit,
    amountClp: 42000,
    sourcePage: 1,
    sourceLineStart: 1,
    sourceLineEnd: 1,
  );
  final directCandidate = BankReconciliationCandidate(
    targetKind: BankReconciliationTargetKind.purchasePayment,
    targetId: 'purchase-payment',
    direction: BankMovementDirection.debit,
    amountClp: 42000,
    occurredOn: const BankCivilDate(2026, 8, 11),
    label: 'Compra FC-88 · Taller Uno',
  );
  final directProposal = BankReconciliationProposal(
    sourceRowId: 'direct',
    matchKind: BankReconciliationMatchKind.direct,
    confidence: BankReconciliationConfidence.high,
    allocations: <BankReconciliationAllocationDraft>[
      BankReconciliationAllocationDraft(
        candidate: directCandidate,
        bankAmountClp: 42000,
      ),
    ],
    reasons: const <String>['Monto exacto', 'Coincide la contraparte'],
    isSelectedByDefault: true,
  );
  final transbankMovement = BankStatementMovement(
    sourceRowId: 'transbank',
    ordinal: 2,
    bookingDate: const BankCivilDate(2026, 8, 12),
    description: 'Pago: Abonos Débito y Crédito Transbank',
    normalizedDescription: 'pago abonos debito y credito transbank',
    direction: BankMovementDirection.credit,
    amountClp: 95000,
    sourcePage: 1,
    sourceLineStart: 2,
    sourceLineEnd: 2,
  );
  final cardSales = <BankReconciliationAllocationDraft>[
    for (final item in <(String, int)>[('sale-a', 57000), ('sale-b', 38000)])
      BankReconciliationAllocationDraft(
        candidate: BankReconciliationCandidate(
          targetKind: conflictingTransbankTarget && item.$1 == 'sale-a'
              ? BankReconciliationTargetKind.purchasePayment
              : BankReconciliationTargetKind.salesPayment,
          targetId: conflictingTransbankTarget && item.$1 == 'sale-a'
              ? 'purchase-payment'
              : item.$1,
          direction: BankMovementDirection.credit,
          amountClp: item.$2 == 57000 ? 60000 : 40000,
          occurredOn: const BankCivilDate(2026, 8, 11),
          label: 'Venta ${item.$1}',
          provider: BankSettlementProvider.transbank,
        ),
        bankAmountClp: item.$2,
      ),
  ];
  final transbankProposal = BankReconciliationProposal(
    sourceRowId: 'transbank',
    matchKind: BankReconciliationMatchKind.transbankEstimate,
    confidence: BankReconciliationConfidence.medium,
    allocations: cardSales,
    reasons: const <String>[
      '2 ventas con tarjeta',
      'Instrumento aún no separado: débito, crédito o prepago',
    ],
    estimatedGrossClp: 100000,
    estimatedDifferenceClp: 5000,
  );
  return BankReconciliationPreparedDraft(
    fileSha256:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    filename: 'cartola.pdf',
    sourceType: 'pdf_text',
    parserName: 'banco_chile_statement',
    parserVersion: 'v1',
    rows: <BankReconciliationRowDraft>[
      BankReconciliationRowDraft(
        movement: directMovement,
        proposals: <BankReconciliationProposal>[directProposal],
      ),
      BankReconciliationRowDraft(
        movement: transbankMovement,
        proposals: <BankReconciliationProposal>[transbankProposal],
      ),
    ],
  );
}
