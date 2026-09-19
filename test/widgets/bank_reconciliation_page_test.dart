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

  testWidgets('a decided charge teaches the rule and decides its twins',
      (tester) async {
    final harness = _Harness()..teaches = true;
    addTearDown(harness.dispose);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(harness.app(initialDraft: _teachDraft()));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('bank-reconciliation-resolve-june')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('bank-reconciliation-teach-june')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey('bank-reconciliation-accept-suggestions')),
    );
    await tester.pumpAndSettle();

    final teach = find.byKey(const ValueKey('bank-reconciliation-teach-june'));
    await tester.ensureVisible(teach);
    await tester.pumpAndSettle();
    expect(find.text('Usar siempre para «google play youtu»'), findsOneWidget);
    await tester.tap(teach);
    await tester.pumpAndSettle();

    final rule = harness.savedRules.single;
    expect(rule.pattern, 'google play youtu');
    expect(rule.direction, BankMovementDirection.debit);
    expect(rule.action, BankReconciliationActionKind.createExpense);
    expect(rule.accountId, 'expense-account');
    expect(rule.description, 'YouTube');
    // July's charge is decided the same way; Google Cloud is another line.
    expect(
      find.text('2 de 3 movimientos resueltos · 1 quedan pendientes'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bank-reconciliation-rule-note')),
      findsOneWidget,
    );
    expect(
      find.textContaining('otro de esta revisión quedó decidido igual'),
      findsOneWidget,
    );
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

  testWidgets('a transfer that paid a sale and more books the difference',
      (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(harness.app(initialDraft: _paidMoreDraft()));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('bank-reconciliation-resolve-carlos')),
    );
    await tester.pumpAndSettle();

    expect(find.text(r'Faltan $11.000'), findsOneWidget);
    expect(find.text(r'Registrar los $11.000 que faltan'), findsOneWidget);
    expect(
      find.text('0 de 1 movimientos resueltos · 1 quedan pendientes'),
      findsOneWidget,
    );

    final account = find.byKey(
      const ValueKey('bank-reconciliation-remainder-account-carlos'),
    );
    await tester.ensureVisible(account);
    await tester.pumpAndSettle();
    await tester.tap(account);
    await tester.pumpAndSettle();
    await tester.tap(find.text('4100 · Otros ingresos').last);
    await tester.pumpAndSettle();
    final description = find.byKey(
      const ValueKey('bank-reconciliation-remainder-description-carlos'),
    );
    await tester.ensureVisible(description);
    await tester.pumpAndSettle();
    await tester.enterText(description, 'Venta no registrada · Carlos Sanchez');
    await tester.pumpAndSettle();

    expect(
      find.text(r'Faltan $11.000: quedan en 4100 · Otros ingresos'),
      findsOneWidget,
    );
    expect(
      find.textContaining(r'genera un asiento contabilizado por los $11.000 '
          'que faltan: Debe banco / Haber 4100 · Otros ingresos'),
      findsOneWidget,
    );
    expect(
      find.text('1 de 1 movimientos resueltos · 0 quedan pendientes'),
      findsOneWidget,
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

  testWidgets('a sale somebody else paid is accepted with the safe ones',
      (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sale = BankReconciliationCandidate(
      targetKind: BankReconciliationTargetKind.salesPayment,
      targetId: 'fv-832',
      direction: BankMovementDirection.credit,
      amountClp: 34000,
      occurredOn: const BankCivilDate(2026, 7, 13),
      label: 'Venta FV-00832',
      counterparty: 'Rosita Bustamante',
      paymentMethodCode: 'transfer',
    );
    final proposal = BankReconciliationProposal(
      sourceRowId: 'osvaldo',
      matchKind: BankReconciliationMatchKind.thirdParty,
      confidence: BankReconciliationConfidence.high,
      allocations: <BankReconciliationAllocationDraft>[
        BankReconciliationAllocationDraft(
            candidate: sale, bankAmountClp: 34000),
      ],
      reasons: const <String>['Mismo monto que Venta FV-00832'],
    );
    final draft = BankReconciliationPreparedDraft(
      fileSha256: 'b' * 64,
      filename: 'cartola julio.pdf',
      sourceType: 'pdf_text',
      parserName: 'banco_chile_statement',
      parserVersion: 'v1',
      rows: <BankReconciliationRowDraft>[
        BankReconciliationRowDraft(
          movement: BankStatementMovement(
            sourceRowId: 'osvaldo',
            ordinal: 1,
            bookingDate: const BankCivilDate(2026, 7, 13),
            description: 'Traspaso De: Quezada Silva Osvaldo Internet Andres',
            normalizedDescription:
                'traspaso de quezada silva osvaldo internet andres',
            direction: BankMovementDirection.credit,
            amountClp: 34000,
            sourcePage: 1,
            sourceLineStart: 1,
            sourceLineEnd: 1,
          ),
          proposals: <BankReconciliationProposal>[proposal],
          suggestion: BankReconciliationSuggestion(
            kind: BankSuggestionKind.otherPayer,
            confidence: BankReconciliationConfidence.high,
            title: 'Venta FV-00832 · la pagó otra persona',
            reasons: proposal.reasons,
            resolution: const BankReconciliationResolutionDraft(
              action: BankReconciliationActionKind.associateExisting,
            ),
            proposalId: BankReconciliationRowDraft.proposalIdentity(proposal),
          ),
        ),
      ],
      candidateCatalog: <BankReconciliationCandidate>[sale],
    );

    await tester.pumpWidget(harness.app(initialDraft: draft));
    await tester.pumpAndSettle();
    expect(find.text('Usar 1 sugerencia segura'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('bank-reconciliation-accept-suggestions')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Asociada'), findsOneWidget);
    expect(find.text('1 de 1 movimientos resueltos · 0 quedan pendientes'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  /// Resuming judges a saved split against today's accounts, which have to
  /// be there before the draft comes back.
  Future<void> resumeWithSplit(
    WidgetTester tester,
    _Harness harness,
    List<Map<String, dynamic>> parts,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final draft = _draft();
    final sha = draft.fileSha256;
    harness.sessions = <BankReconciliationSessionSummary>[
      BankReconciliationSessionSummary(
        sessionId: 'session-1',
        statementCount: 1,
        movementCount: 2,
        decidedCount: 0,
        draftRows: 1,
        draftDecisions: 1,
        updatedAt: DateTime(2026, 9, 19, 10, 30),
        firstDate: const BankCivilDate(2026, 8, 12),
        lastDate: const BankCivilDate(2026, 8, 12),
      ),
    ];
    final split = <String, dynamic>{
      'action': 'split',
      'split_parts': parts,
    };
    harness.resumed = BankReconciliationResumedSession(
      draft: draft,
      session: BankReconciliationSession(
        sessionId: 'session-1',
        revision: 3,
        draft: <String, dynamic>{
          'version': 1,
          'rows': <String, dynamic>{
            '$sha:transbank': <String, dynamic>{
              'resolution': split,
              'ai': <String, dynamic>{
                'explanation': 'Un abono con dos partes.',
                'resolution': split,
              },
            },
          },
        },
      ),
      importReceipts: <String, BankStatementImportReceipt>{
        sha: BankStatementImportReceipt(
          importId: 'import-id',
          revision: 1,
          rowIdsBySourceRowId: const <String, String>{
            'direct': 'row-direct',
            'transbank': 'row-transbank',
          },
          replayed: true,
        ),
      },
    );

    await tester.pumpWidget(harness.app(empty: true));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('bank-reconciliation-resume-session-1')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('resuming keeps a deposit split this ERP still books',
      (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);

    await resumeWithSplit(tester, harness, <Map<String, dynamic>>[
      <String, dynamic>{
        'account_id': 'income-account',
        'amount': 80000,
        'description': 'Venta del día',
        'is_expense': false,
      },
      <String, dynamic>{
        'account_id': 'vat-account',
        'amount': 15000,
        'description': 'IVA débito',
        'is_expense': false,
      },
    ]);

    expect(find.text('2 de 2 movimientos resueltos · 0 quedan pendientes'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resuming does not bring back a deposit split the kernel refuses',
      (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);

    await resumeWithSplit(tester, harness, <Map<String, dynamic>>[
      <String, dynamic>{
        'account_id': 'income-account',
        'amount': 80000,
        'description': 'Venta del día',
        'is_expense': false,
      },
      <String, dynamic>{
        'account_id': 'expense-account',
        'amount': 15000,
        'description': 'Devolución de servicios',
        'is_expense': false,
      },
    ]);

    expect(find.text('1 de 2 movimientos resueltos · 1 quedan pendientes'),
        findsOneWidget);
    expect(
      find.textContaining('1 decisión guardada ya no aplica'),
      findsOneWidget,
    );
    expect(find.textContaining('Dividir: Venta del día'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a saved conciliation is resumed and keeps saving itself',
      (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final draft = _draft();
    final sha = draft.fileSha256;
    harness.sessions = <BankReconciliationSessionSummary>[
      BankReconciliationSessionSummary(
        sessionId: 'session-1',
        statementCount: 1,
        movementCount: 2,
        decidedCount: 0,
        draftRows: 1,
        draftDecisions: 1,
        updatedAt: DateTime(2026, 9, 19, 10, 30),
        firstDate: const BankCivilDate(2026, 8, 12),
        lastDate: const BankCivilDate(2026, 8, 12),
      ),
    ];
    harness.resumed = BankReconciliationResumedSession(
      draft: draft,
      session: BankReconciliationSession(
        sessionId: 'session-1',
        revision: 3,
        draft: <String, dynamic>{
          'version': 1,
          'rows': <String, dynamic>{
            '$sha:transbank': <String, dynamic>{
              'resolution': <String, dynamic>{
                'action': 'dismiss',
                'reason': 'Abono repetido en otra cuenta',
              },
            },
            // Another statement of the same conciliation, not loaded now.
            '${'b' * 64}:p2-l7-r19': <String, dynamic>{
              'resolution': <String, dynamic>{
                'action': 'classifyAccount',
                'account_id': 'expense-account',
                'description': 'Suscripción',
              },
              'ai': <String, dynamic>{'explanation': 'Un cargo mensual.'},
            },
          },
        },
      ),
      importReceipts: <String, BankStatementImportReceipt>{
        sha: BankStatementImportReceipt(
          importId: 'import-id',
          revision: 1,
          rowIdsBySourceRowId: const <String, String>{
            'direct': 'row-direct',
            'transbank': 'row-transbank',
          },
          replayed: true,
        ),
      },
    );

    await tester.pumpWidget(harness.app(empty: true));
    await tester.pumpAndSettle();

    expect(find.text('Conciliaciones guardadas'), findsOneWidget);
    expect(find.text('1 cartola · 2 movimientos · 0 aplicados · 2 pendientes'),
        findsOneWidget);
    expect(find.text('En curso'), findsOneWidget);
    expect(find.text('1 decisión sin aplicar · guardada el 19/09 10:30'),
        findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('bank-reconciliation-resume-session-1')),
    );
    await tester.pumpAndSettle();

    // The dismissal decided in the first sitting is back; the direct match
    // nobody touched is proposed again.
    expect(find.text('Excluida'), findsOneWidget);
    expect(find.text('2 de 2 movimientos resueltos · 0 quedan pendientes'),
        findsOneWidget);
    expect(find.text('Borrador guardado'), findsOneWidget);
    expect(harness.createCalls, 0);

    await tester.tap(
      find.byKey(const ValueKey('bank-reconciliation-resolve-direct')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('bank-reconciliation-action-pending')),
    );
    await tester.pump();
    expect(find.text('Guardando borrador…'), findsOneWidget);
    expect(harness.savedDrafts, isEmpty);

    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();

    final (revision, saved) = harness.savedDrafts.single;
    expect(revision, 3);
    // What the conciliation holds for the statement this sitting did not
    // load is saved as it was.
    expect((saved['rows'] as Map).keys.toSet(), {
      '$sha:transbank',
      '$sha:direct',
      '${'b' * 64}:p2-l7-r19',
    });
    expect(
      (((saved['rows'] as Map)['${'b' * 64}:p2-l7-r19'] as Map)['resolution']
          as Map)['description'],
      'Suscripción',
    );
    expect(
      ((saved['rows'] as Map)['$sha:direct'] as Map)['resolution'],
      {'action': 'pending'},
    );
    expect(find.text('Borrador guardado'), findsOneWidget);

    // Applying what is sure keeps the conciliation open for the rest.
    await tester.tap(find.byKey(const ValueKey('bank-reconciliation-save')));
    await tester.pumpAndSettle();
    expect(harness.applyCalls, 1);
    expect(harness.createCalls, 0);
    expect(find.text('Seguir con el pendiente'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('bank-reconciliation-continue')),
    );
    await tester.pumpAndSettle();
    expect(harness.resumeCalls, 2);
    expect(find.text('Conciliación guardada'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the AI proposes, the owner uses it or answers its question',
      (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final draft = _repaidDraft();
    final salaries = draft.candidateCatalog.take(2).toList();
    final calls = <(Map<String, String>, Set<String>?)>[];
    harness.analyze = ({
      required draft,
      required options,
      Map<String, String> answers = const {},
      Set<String>? rowIds,
      BankAiBatchCallback? onBatch,
    }) async {
      calls.add((Map.of(answers), rowIds));
      if (rowIds == null) {
        return {
          'mother': BankAiAnalysis(
            explanation: 'Tu mamá pagó los sueldos de la semana 29.',
            question: '¿Tu mamá les pagó a Vicente y Lucas?',
            proposal: BankReconciliationProposal.manual(
              sourceRowId: 'mother',
              movementAmountClp: 133000,
              candidates: salaries,
            ),
          ),
          'other': const BankAiAnalysis(
            explanation: 'Una transferencia chica sin nada que la explique.',
            question: '¿Qué fueron estos \$5.000?',
          ),
        };
      }
      return {
        'other': BankAiAnalysis(
          explanation: 'Un reembolso de un repuesto.',
          answer: answers['other'],
          resolution: const BankReconciliationResolutionDraft(
            action: BankReconciliationActionKind.createExpense,
            accountId: 'expense-account',
            paymentMethodId: 'bank-method',
            description: 'Reembolso repuesto',
          ),
        ),
      };
    };

    await tester.pumpWidget(harness.app(initialDraft: draft));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('bank-reconciliation-analyze-ai')),
    );
    await tester.pumpAndSettle();

    expect(calls.single.$2, isNull);
    expect(find.text('IA propone'), findsOneWidget);
    expect(find.text('IA pregunta'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('bank-reconciliation-resolve-mother')),
    );
    await tester.pumpAndSettle();
    expect(
        find.text('Tu mamá pagó los sueldos de la semana 29.'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('bank-reconciliation-ai-use-mother')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('1 de 2 movimientos resueltos · 1 quedan pendientes · '
          '1 ya conciliados'),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('bank-reconciliation-resolve-other')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('bank-reconciliation-ai-answer-other')),
      'Le devolví un repuesto que compró',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('bank-reconciliation-ai-reply-other')),
    );
    await tester.pumpAndSettle();

    expect(calls.last.$2, {'other'});
    expect(calls.last.$1, {'other': 'Le devolví un repuesto que compró'});
    await tester.tap(
      find.byKey(const ValueKey('bank-reconciliation-ai-use-other')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Gasto listo'), findsOneWidget);
    expect(
      find.text('2 de 2 movimientos resueltos · 0 quedan pendientes · '
          '1 ya conciliados'),
      findsOneWidget,
    );
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

/// Carlos Sánchez's $18.000 transfer with his $7.000 sale chosen by hand.
BankReconciliationPreparedDraft _paidMoreDraft() {
  final sale = BankReconciliationCandidate(
    targetKind: BankReconciliationTargetKind.salesPayment,
    targetId: 'fv-836',
    direction: BankMovementDirection.credit,
    amountClp: 7000,
    occurredOn: const BankCivilDate(2026, 7, 7),
    label: 'Venta FV-00836',
    paymentMethodCode: 'transfer',
  );
  final proposal = BankReconciliationProposal.manual(
    sourceRowId: 'carlos',
    movementAmountClp: 18000,
    candidates: <BankReconciliationCandidate>[sale],
  )!;
  return BankReconciliationPreparedDraft(
    fileSha256:
        'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
    filename: 'cartola julio.pdf',
    sourceType: 'pdf_text',
    parserName: 'banco_chile_statement',
    parserVersion: 'v1',
    rows: <BankReconciliationRowDraft>[
      BankReconciliationRowDraft(
        movement: BankStatementMovement(
          sourceRowId: 'carlos',
          ordinal: 1,
          bookingDate: const BankCivilDate(2026, 7, 7),
          description: 'Traspaso De: Carlos Aurelio Sanchez Internet Sanchez',
          normalizedDescription:
              'traspaso de carlos aurelio sanchez internet sanchez',
          direction: BankMovementDirection.credit,
          amountClp: 18000,
          sourcePage: 1,
          sourceLineStart: 1,
          sourceLineEnd: 1,
        ),
        proposals: <BankReconciliationProposal>[proposal],
        selectedProposalId:
            BankReconciliationRowDraft.proposalIdentity(proposal),
        resolution: const BankReconciliationResolutionDraft(
          action: BankReconciliationActionKind.associateExisting,
        ),
      ),
    ],
    candidateCatalog: <BankReconciliationCandidate>[sale],
  );
}

BankReconciliationPreparedDraft _teachDraft() {
  BankStatementMovement charge(String id, int month, String description) =>
      BankStatementMovement(
        sourceRowId: id,
        ordinal: month,
        bookingDate: BankCivilDate(2026, month, 15),
        description: description,
        normalizedDescription: description.toLowerCase(),
        direction: BankMovementDirection.debit,
        amountClp: 2690,
        sourcePage: 1,
        sourceLineStart: month,
        sourceLineEnd: month,
      );
  return BankReconciliationPreparedDraft(
    fileSha256:
        'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
    filename: 'cartola.pdf',
    sourceType: 'pdf_text',
    parserName: 'banco_chile_statement',
    parserVersion: 'v1',
    rows: <BankReconciliationRowDraft>[
      BankReconciliationRowDraft(
        movement: charge('june', 6, 'Pago: Google Play Youtu Renca'),
        proposals: const <BankReconciliationProposal>[],
        suggestion: BankReconciliationSuggestion(
          kind: BankSuggestionKind.createExpense,
          confidence: BankReconciliationConfidence.high,
          title: 'YouTube · Google',
          reasons: const <String>['Cargo con tarjeta en Google'],
          resolution: const BankReconciliationResolutionDraft(
            action: BankReconciliationActionKind.createExpense,
            accountId: 'expense-account',
            paymentMethodId: 'bank-method',
            description: 'YouTube',
            counterparty: 'Google',
          ),
        ),
      ),
      BankReconciliationRowDraft(
        movement: charge('july', 7, 'Pago: Google Play Youtu Renca'),
        proposals: const <BankReconciliationProposal>[],
      ),
      BankReconciliationRowDraft(
        movement: charge('cloud', 8, 'Pago: Google Cloud Jl5r Renca'),
        proposals: const <BankReconciliationProposal>[],
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
  BankAiAnalyzeAction? analyze;
  List<BankReconciliationSessionSummary>? sessions;
  BankReconciliationResumedSession? resumed;
  final savedDrafts = <(int, Map<String, dynamic>)>[];
  int resumeCalls = 0;
  bool teaches = false;
  final savedRules = <BankReconciliationRule>[];

  Widget app({
    BankReconciliationPreparedDraft? initialDraft,
    bool empty = false,
  }) {
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
          initialDraft: empty ? null : initialDraft ?? _draft(),
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
            analyzeWithAi: analyze,
            listSessions: sessions == null
                ? null
                : ({required erpAccountId}) async => sessions!,
            openSession: resumed == null
                ? null
                : ({required erpAccountId, required importIds}) async =>
                    resumed!.session,
            resumeSession: resumed == null
                ? null
                : ({required sessionId, required erpAccountId}) async {
                    resumeCalls++;
                    return resumed!;
                  },
            saveSessionDraft: resumed == null
                ? null
                : ({
                    required sessionId,
                    required revision,
                    required draft,
                  }) async {
                    savedDrafts.add((revision, draft));
                    return revision + 1;
                  },
            saveRule: !teaches
                ? null
                : ({
                    required pattern,
                    required direction,
                    required action,
                    required accountId,
                    required description,
                  }) async {
                    final rule = BankReconciliationRule(
                      ruleId: 'rule-${savedRules.length + 1}',
                      pattern: pattern,
                      direction: direction,
                      action: action,
                      accountId: accountId,
                      description: description,
                    );
                    savedRules.add(rule);
                    return rule;
                  },
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
