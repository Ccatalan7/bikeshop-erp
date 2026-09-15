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
              required bytes,
              required filename,
              required erpAccountId,
              sourcePath,
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
