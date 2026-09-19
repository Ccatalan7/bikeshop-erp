import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/accounting/bank_reconciliation/models/bank_reconciliation_models.dart';
import 'package:vinabike_erp/modules/accounting/bank_reconciliation/services/bank_reconciliation_service.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';

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

  test('candidate metadata keeps provider and future card instrument separate',
      () async {
    final calls = <_RpcCall>[];
    final service = BankReconciliationService(
      database: _FakeDatabaseService(),
      rpc: (name, params) async {
        calls.add(_RpcCall(name, params));
        return <String, dynamic>{
          'candidates': <Map<String, dynamic>>[
            <String, dynamic>{
              'target_kind': 'sales_payment',
              'target_id': '11111111-1111-4111-8111-111111111111',
              'direction': 'credit',
              'amount': 95000,
              'occurred_on': '2026-08-10',
              'label': 'Venta con tarjeta',
              'payment_method_code': 'card',
              'provider': 'transbank',
              'instrument': 'unknown',
            },
            <String, dynamic>{
              'target_kind': 'expense',
              'target_id': '77777777-7777-4777-8777-777777777777',
              'direction': 'debit',
              'amount': 19980,
              'occurred_on': '2026-07-17',
              'label': 'Gasto GTO-00136 · NIC Chile',
              'payment_method_code': 'card',
              'provider': 'none',
              'instrument': 'unknown',
            },
          ],
        };
      },
    );

    final result = await service.loadCandidates(
      erpAccountId: '22222222-2222-4222-8222-222222222222',
      from: const BankCivilDate(2026, 8, 1),
      to: const BankCivilDate(2026, 8, 15),
    );

    expect(result.first.provider, BankSettlementProvider.transbank);
    expect(result.first.instrument, BankPaymentInstrument.unknown);
    expect(result.last.targetKind, BankReconciliationTargetKind.expense);
    expect(result.last.amountClp, 19980);
    expect(calls.single.name, 'get_bank_reconciliation_candidates_v2');
  });

  test('persistence sends structured evidence only and canonical provider code',
      () async {
    final calls = <_RpcCall>[];
    final service = BankReconciliationService(
      database: _FakeDatabaseService(),
      rpc: (name, params) async {
        calls.add(_RpcCall(name, params));
        if (name == 'save_bank_statement_import_v1') {
          return <String, dynamic>{
            'import_id': '33333333-3333-4333-8333-333333333333',
            'revision': 1,
            'replayed': false,
            'rows': <Map<String, dynamic>>[
              <String, dynamic>{
                'source_row_id': 'row-1',
                'row_id': '44444444-4444-4444-8444-444444444444',
              },
            ],
          };
        }
        return <String, dynamic>{
          'import_id': '33333333-3333-4333-8333-333333333333',
          'revision': 2,
          'status': 'reconciled',
          'allocation_count': 1,
          'replayed': false,
        };
      },
    );
    final movement = BankStatementMovement(
      sourceRowId: 'row-1',
      ordinal: 1,
      bookingDate: const BankCivilDate(2026, 8, 12),
      description: 'Abono Mercado Pago',
      normalizedDescription: 'abono mercado pago',
      direction: BankMovementDirection.credit,
      amountClp: 18000,
      sourcePage: 1,
      sourceLineStart: 4,
      sourceLineEnd: 4,
    );
    final candidate = BankReconciliationCandidate(
      targetKind: BankReconciliationTargetKind.salesPayment,
      targetId: '55555555-5555-4555-8555-555555555555',
      direction: BankMovementDirection.credit,
      amountClp: 18000,
      occurredOn: const BankCivilDate(2026, 8, 11),
      label: 'Venta FV-10',
      provider: BankSettlementProvider.mercadoPago,
    );
    final proposal = BankReconciliationProposal(
      sourceRowId: 'row-1',
      matchKind: BankReconciliationMatchKind.direct,
      confidence: BankReconciliationConfidence.high,
      allocations: <BankReconciliationAllocationDraft>[
        BankReconciliationAllocationDraft(
          candidate: candidate,
          bankAmountClp: 18000,
        ),
      ],
      reasons: const <String>['Monto exacto'],
      isSelectedByDefault: true,
    );
    final draft = BankReconciliationPreparedDraft(
      fileSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      filename: 'cartola-cuenta-12345678.pdf',
      sourceType: 'pdf_text',
      accountFingerprint:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      parserName: 'banco_chile_statement',
      parserVersion: 'v1',
      rows: <BankReconciliationRowDraft>[
        BankReconciliationRowDraft(
          movement: movement,
          proposals: <BankReconciliationProposal>[proposal],
        ),
      ],
    );

    final importReceipt = await service.createImport(
      draft: draft,
      erpAccountId: '66666666-6666-4666-8666-666666666666',
      operationKey: 'create-key',
    );
    await service.apply(
      draft: draft,
      importReceipt: importReceipt,
      operationKey: 'apply-key',
    );

    final create = calls.first.params;
    expect(create.toString(), isNot(contains('12345678')));
    expect(create.toString(), isNot(contains('cartola-cuenta')));
    expect(create['p_source_metadata'], <String, dynamic>{
      'source_type': 'pdf_text',
      'parser_name': 'banco_chile_statement',
      'parser_version': 'v1',
      'filename_extension': 'pdf',
    });
    expect(calls.last.name, 'apply_bank_reconciliation_actions_v3');
    final actions =
        calls.last.params['p_actions'] as List<Map<String, dynamic>>;
    expect(actions.single['action'], 'associate_existing');
    final allocations =
        actions.single['allocations'] as List<Map<String, dynamic>>;
    expect(allocations.single['provider'], 'mercadopago');
    expect(allocations.single['instrument'], 'unknown');
  });

  test('a salary row is sent as pay_payroll with the line it pays', () async {
    final calls = <_RpcCall>[];
    final service = BankReconciliationService(
      database: _FakeDatabaseService(),
      rpc: (name, params) async {
        calls.add(_RpcCall(name, params));
        return <String, dynamic>{
          'import_id': '33333333-3333-4333-8333-333333333333',
          'revision': 2,
          'status': 'reconciled',
          'allocation_count': 1,
          'replayed': false,
          'payroll_payment_count': 1,
        };
      },
    );
    const payroll = BankPayrollPaymentDraft(
      voucherId: 'aaaaaaaa-0000-4000-8000-000000000037',
      voucherNumber: 'NOM-00037',
      periodLabel: 'Semana 35',
      lineId: 'bbbbbbbb-0000-4000-8000-000000000001',
      employeeName: 'Braulio Muñoz',
      expectedAmountClp: 101400,
      amountClp: 71400,
      paymentMethodId: 'cccccccc-0000-4000-8000-000000000001',
      confirmDraft: true,
      advances: <BankPayrollAdvanceUse>[
        BankPayrollAdvanceUse(
          advance: BankOpenAdvance(
            advanceId: 'dddddddd-0000-4000-8000-000000000001',
            employeeId: 'eeeeeeee-0000-4000-8000-000000000001',
            availableClp: 30000,
            paidOn: BankCivilDate(2026, 8, 20),
            paymentMethodCode: 'cash',
          ),
          amountClp: 30000,
        ),
      ],
    );
    BankReconciliationRowDraft salaryRow(String id) =>
        BankReconciliationRowDraft(
          movement: BankStatementMovement(
            sourceRowId: id,
            ordinal: 1,
            bookingDate: const BankCivilDate(2026, 8, 31),
            description: 'App-traspaso A: Braulio Munoz Internet',
            normalizedDescription: 'app traspaso a braulio munoz internet',
            direction: BankMovementDirection.debit,
            amountClp: 71400,
            sourcePage: 1,
            sourceLineStart: 10,
            sourceLineEnd: 10,
          ),
          proposals: const <BankReconciliationProposal>[],
          resolution: const BankReconciliationResolutionDraft(
            action: BankReconciliationActionKind.payPayroll,
            payroll: payroll,
          ),
        );
    BankReconciliationPreparedDraft draftOf(
            List<BankReconciliationRowDraft> rows) =>
        BankReconciliationPreparedDraft(
          fileSha256:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          filename: 'cartola.pdf',
          sourceType: 'pdf_text',
          parserName: 'banco_chile_statement',
          parserVersion: 'v1',
          rows: rows,
        );

    final receipt = await service.apply(
      draft: draftOf([salaryRow('row-1')]),
      importReceipt: BankStatementImportReceipt(
        importId: '33333333-3333-4333-8333-333333333333',
        revision: 1,
        rowIdsBySourceRowId: <String, String>{
          'row-1': '44444444-4444-4444-8444-444444444444',
        },
        replayed: false,
      ),
      operationKey: 'apply-key',
    );

    expect(calls.single.name, 'apply_bank_reconciliation_actions_v3');
    final action =
        (calls.single.params['p_actions'] as List<Map<String, dynamic>>).single;
    expect(action['action'], 'pay_payroll');
    expect(action['payroll'], <String, dynamic>{
      'voucher_id': payroll.voucherId,
      'voucher_line_id': payroll.lineId,
      'expected_amount': 101400,
      'amount': 71400,
      'payment_method_id': payroll.paymentMethodId,
      'confirm_draft': true,
      'advances': <Map<String, dynamic>>[
        <String, dynamic>{
          'advance_id': 'dddddddd-0000-4000-8000-000000000001',
          'amount': 30000,
        },
      ],
    });
    expect(receipt.payrollPaymentCount, 1);

    await expectLater(
      service.apply(
        draft: draftOf([salaryRow('row-1'), salaryRow('row-2')]),
        importReceipt: BankStatementImportReceipt(
          importId: '33333333-3333-4333-8333-333333333333',
          revision: 1,
          rowIdsBySourceRowId: <String, String>{
            'row-1': '44444444-4444-4444-8444-444444444444',
            'row-2': '44444444-4444-4444-8444-444444444445',
          },
          replayed: false,
        ),
        operationKey: 'apply-twice',
      ),
      throwsA(isA<BankReconciliationServiceException>()),
    );
    expect(calls, hasLength(1),
        reason: 'one salary twice never reaches Nómina');
  });

  test('a salary Nómina refused explains that nothing was saved', () async {
    final service = BankReconciliationService(
      database: _FakeDatabaseService(),
      rpc: (name, params) async => throw Exception(
        'PostgrestException(message: bank_reconciliation_payroll_line_changed, code: 40001)',
      ),
    );
    await expectLater(
      service.apply(
        draft: BankReconciliationPreparedDraft(
          fileSha256:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          filename: 'cartola.pdf',
          sourceType: 'pdf_text',
          parserName: 'banco_chile_statement',
          parserVersion: 'v1',
          rows: const <BankReconciliationRowDraft>[],
        ),
        importReceipt: BankStatementImportReceipt(
          importId: '33333333-3333-4333-8333-333333333333',
          revision: 1,
          rowIdsBySourceRowId: <String, String>{},
          replayed: false,
        ),
      ),
      throwsA(
        isA<BankReconciliationServiceException>().having(
          (error) => error.message,
          'message',
          contains('No se guardó nada'),
        ),
      ),
    );
  });

  test('several statements persist each file under its own row ids', () async {
    final calls = <_RpcCall>[];
    final service = BankReconciliationService(
      database: _FakeDatabaseService(),
      rpc: (name, params) async {
        calls.add(_RpcCall(name, params));
        final rows = params['p_rows'] as List<Map<String, dynamic>>;
        return <String, dynamic>{
          'import_id': 'import-${calls.length}',
          'revision': 1,
          'replayed': false,
          'rows': <Map<String, dynamic>>[
            for (final row in rows)
              <String, dynamic>{
                'source_row_id': row['source_row_id'],
                'row_id': 'db-${row['source_row_id']}',
              },
          ],
        };
      },
    );
    BankStatementMovement movement(String fileRowId, String sha) =>
        BankStatementMovement(
          sourceRowId: fileRowId,
          ordinal: 1,
          bookingDate: const BankCivilDate(2026, 7, 1),
          description: 'Traspaso',
          normalizedDescription: 'traspaso',
          direction: BankMovementDirection.credit,
          amountClp: 1000,
          sourcePage: 1,
          sourceLineStart: 1,
          sourceLineEnd: 1,
        ).withSourceRowId('${sha.substring(0, 12)}:$fileRowId');
    final june = 'a' * 64;
    final july = 'b' * 64;
    final draft = BankReconciliationPreparedDraft(
      fileSha256: june,
      filename: '2 cartolas',
      sourceType: 'pdf_text',
      parserName: 'banco_chile_statement',
      parserVersion: 'v1',
      rows: <BankReconciliationRowDraft>[
        BankReconciliationRowDraft(
          movement: movement('row-1', june),
          proposals: const [],
          sourceFileSha256: june,
        ),
        BankReconciliationRowDraft(
          movement: movement('row-1', july),
          proposals: const [],
          sourceFileSha256: july,
        ),
      ],
      sources: <BankStatementSource>[
        BankStatementSource(
          fileSha256: june,
          filename: 'cartola junio.pdf',
          sourceType: 'pdf_text',
        ),
        BankStatementSource(
          fileSha256: july,
          filename: 'cartola julio.pdf',
          sourceType: 'pdf_text',
        ),
      ],
    );

    final receipts = <BankStatementImportReceipt>[
      for (final source in draft.sources)
        await service.createImport(
          draft: draft.forSource(source),
          erpAccountId: '66666666-6666-4666-8666-666666666666',
        ),
    ];

    expect(calls.map((call) => call.params['p_file_sha256']), [june, july]);
    for (final call in calls) {
      final rows = call.params['p_rows'] as List<Map<String, dynamic>>;
      // Importing the same file again later keeps the same row identity.
      expect(rows.single['source_row_id'], 'row-1');
    }
    expect(receipts.first.rowIdsBySourceRowId, {
      '${june.substring(0, 12)}:row-1': 'db-row-1',
    });
    expect(receipts.last.rowIdsBySourceRowId.keys.single,
        '${july.substring(0, 12)}:row-1');
  });

  test('apply serializes expense, journal and dismissal as real actions',
      () async {
    final calls = <_RpcCall>[];
    final service = BankReconciliationService(
      database: _FakeDatabaseService(),
      rpc: (name, params) async {
        calls.add(_RpcCall(name, params));
        return <String, dynamic>{
          'import_id': '33333333-3333-4333-8333-333333333333',
          'revision': 4,
          'status': 'partially_reconciled',
          'allocation_count': 2,
          'created_expense_count': 1,
          'created_journal_count': 1,
          'replayed': false,
        };
      },
    );
    BankStatementMovement movement(
      String id,
      int ordinal,
      BankMovementDirection direction,
      int amount,
    ) =>
        BankStatementMovement(
          sourceRowId: id,
          ordinal: ordinal,
          bookingDate: const BankCivilDate(2026, 7, 17),
          description: 'Movimiento $id',
          normalizedDescription: 'movimiento $id',
          direction: direction,
          amountClp: amount,
          sourcePage: 1,
          sourceLineStart: ordinal,
          sourceLineEnd: ordinal,
        );
    final draft = BankReconciliationPreparedDraft(
      fileSha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      filename: 'cartola.pdf',
      sourceType: 'pdf_text',
      parserName: 'banco_chile_statement',
      parserVersion: 'v1',
      rows: <BankReconciliationRowDraft>[
        BankReconciliationRowDraft(
          movement: movement(
            'expense-row',
            1,
            BankMovementDirection.debit,
            19980,
          ),
          proposals: const [],
          selectDefault: false,
          resolution: const BankReconciliationResolutionDraft(
            action: BankReconciliationActionKind.createExpense,
            accountId: '11111111-1111-4111-8111-111111111111',
            paymentMethodId: '22222222-2222-4222-8222-222222222222',
            description: 'Renovación dominio NIC Chile',
            counterparty: 'NIC Chile',
            reference: '21179232',
          ),
        ),
        BankReconciliationRowDraft(
          movement: movement(
            'journal-row',
            2,
            BankMovementDirection.credit,
            80000,
          ),
          proposals: const [],
          selectDefault: false,
          resolution: const BankReconciliationResolutionDraft(
            action: BankReconciliationActionKind.classifyAccount,
            accountId: '44444444-4444-4444-8444-444444444444',
            description: 'Devolución de préstamo',
          ),
        ),
        BankReconciliationRowDraft(
          movement: movement(
            'dismiss-row',
            3,
            BankMovementDirection.debit,
            1000,
          ),
          proposals: const [],
          selectDefault: false,
          resolution: const BankReconciliationResolutionDraft(
            action: BankReconciliationActionKind.dismiss,
            reason: 'Línea duplicada por el banco',
          ),
        ),
      ],
    );
    final receipt = await service.apply(
      draft: draft,
      importReceipt: BankStatementImportReceipt(
        importId: '33333333-3333-4333-8333-333333333333',
        revision: 3,
        rowIdsBySourceRowId: const <String, String>{
          'expense-row': '55555555-5555-4555-8555-555555555555',
          'journal-row': '66666666-6666-4666-8666-666666666666',
          'dismiss-row': '88888888-8888-4888-8888-888888888888',
        },
        replayed: false,
      ),
      operationKey: 'apply-actions',
    );

    final actions =
        calls.single.params['p_actions'] as List<Map<String, dynamic>>;
    expect(actions.map((action) => action['action']), <String>[
      'create_expense',
      'post_journal',
      'dismiss',
    ]);
    expect(
      (actions[0]['expense'] as Map<String, dynamic>)['description'],
      'Renovación dominio NIC Chile',
    );
    expect(
      (actions[1]['journal'] as Map<String, dynamic>)['counterpart_account_id'],
      '44444444-4444-4444-8444-444444444444',
    );
    expect(actions[2]['reason'], 'Línea duplicada por el banco');
    expect(receipt.createdExpenseCount, 1);
    expect(receipt.createdJournalCount, 1);
  });

  test('a reopened statement sends only its open rows', () async {
    final calls = <_RpcCall>[];
    final service = BankReconciliationService(
      database: _FakeDatabaseService(),
      rpc: (name, params) async {
        calls.add(_RpcCall(name, params));
        return <String, dynamic>{
          'import_id': '33333333-3333-4333-8333-333333333333',
          'revision': 5,
          'status': 'partially_reconciled',
          'allocation_count': 2,
          'replayed': false,
        };
      },
    );
    BankStatementMovement movement(String id, int ordinal, int amount) =>
        BankStatementMovement(
          sourceRowId: id,
          ordinal: ordinal,
          bookingDate: const BankCivilDate(2026, 7, 7),
          description: 'Movimiento $id',
          normalizedDescription: 'movimiento $id',
          direction: BankMovementDirection.debit,
          amountClp: amount,
          sourcePage: 1,
          sourceLineStart: ordinal,
          sourceLineEnd: ordinal,
        );
    BankReconciliationCandidate salary(String id, int amount) =>
        BankReconciliationCandidate(
          targetKind: BankReconciliationTargetKind.expensePayment,
          targetId: id,
          direction: BankMovementDirection.debit,
          amountClp: amount,
          occurredOn: const BankCivilDate(2026, 8, 12),
          label: 'Sueldo $id',
        );
    final repaid = BankReconciliationProposal.manual(
      sourceRowId: 'mother',
      movementAmountClp: 133000,
      candidates: <BankReconciliationCandidate>[
        salary('vicente', 94500),
        salary('lucas', 38500),
      ],
    )!;
    final draft = BankReconciliationPreparedDraft(
      fileSha256: 'a' * 64,
      filename: 'cartola.pdf',
      sourceType: 'pdf_text',
      parserName: 'banco_chile_statement',
      parserVersion: 'v1',
      rows: <BankReconciliationRowDraft>[
        BankReconciliationRowDraft(
          movement: movement('applied', 1, 2690),
          proposals: const [],
          settled: const BankSettledMovement(
            sameStatement: true,
            summary: 'Gasto GTO-00200',
            disposition: BankReconciliationDisposition.reconciled,
          ),
        ),
        BankReconciliationRowDraft(
          movement: movement('overlap', 2, 5000),
          proposals: const [],
          settled: const BankSettledMovement(
            sameStatement: false,
            summary: 'Gasto GTO-00201',
            disposition: BankReconciliationDisposition.reconciled,
          ),
        ),
        BankReconciliationRowDraft(
          movement: movement('mother', 3, 133000),
          proposals: <BankReconciliationProposal>[repaid],
          selectedProposalId:
              BankReconciliationRowDraft.proposalIdentity(repaid),
        ),
      ],
    );
    expect(draft.settledCount, 2);
    expect(draft.resolvedCount, 1);
    expect(draft.pendingCount, 0);

    await service.apply(
      draft: draft,
      importReceipt: BankStatementImportReceipt(
        importId: '33333333-3333-4333-8333-333333333333',
        revision: 4,
        rowIdsBySourceRowId: const <String, String>{
          'applied': 'row-applied',
          'overlap': 'row-overlap',
          'mother': 'row-mother',
        },
        replayed: false,
      ),
      operationKey: 'apply-reopened',
    );

    final actions =
        calls.single.params['p_actions'] as List<Map<String, dynamic>>;
    // The row applied in an earlier sitting is final on the server.
    expect(actions.map((action) => action['row_id']),
        <String>['row-overlap', 'row-mother']);
    expect(actions.first['action'], 'dismiss');
    expect(actions.first['settled_elsewhere'], isTrue);
    expect(
        actions.first['reason'], 'Conciliado en otra cartola: Gasto GTO-00201');
    final allocations =
        actions.last['allocations'] as List<Map<String, dynamic>>;
    expect(allocations.map((item) => item['target_id']),
        <String>['vicente', 'lucas']);
    expect(allocations.map((item) => item['bank_amount']), <int>[94500, 38500]);
    expect(allocations.map((item) => item['match_kind']).toSet(), {'manual'});
  });

  test('settled movements are found by statement row or by running balance',
      () {
    BankStatementMovement movement(
      String id, {
      required int amount,
      required int balance,
      int day = 2,
    }) =>
        BankStatementMovement(
          sourceRowId: id,
          ordinal: 1,
          bookingDate: BankCivilDate(2026, 9, day),
          description: 'Movimiento $id',
          normalizedDescription: 'movimiento $id',
          direction: BankMovementDirection.debit,
          amountClp: amount,
          balanceClp: balance,
          sourcePage: 1,
          sourceLineStart: 1,
          sourceLineEnd: 1,
        );
    BankReconciledRow reconciled(
      String sha,
      String rowId, {
      required int amount,
      required int balance,
      bool elsewhere = false,
      List<String> labels = const <String>[],
    }) =>
        BankReconciledRow(
          importId: 'import-$sha',
          fileSha256: sha,
          sourceRowId: rowId,
          bookingDate: const BankCivilDate(2026, 9, 2),
          direction: BankMovementDirection.debit,
          amountClp: amount,
          balanceClp: balance,
          disposition: elsewhere
              ? BankReconciliationDisposition.ignored
              : BankReconciliationDisposition.reconciled,
          action: elsewhere ? 'dismiss' : 'associate_existing',
          settledElsewhere: elsewhere,
          labels: labels,
        );
    final partial = 'p' * 64;
    final full = 'f' * 64;
    final later = 'l' * 64;
    final settled = BankReconciliationService.settledMovements(
      <(BankStatementMovement, String, int)>[
        (movement('row-1', amount: 7000, balance: 93000), partial, 0),
        (movement('row-9', amount: 7000, balance: 93000), full, 1),
        (movement('row-10', amount: 7000, balance: 86000), full, 1),
        (movement('row-3', amount: 7000, balance: 93000), later, 2),
      ],
      <BankReconciledRow>[
        // A later statement only recorded it; the partial one settled it.
        reconciled(later, 'row-2',
            amount: 7000, balance: 93000, elsewhere: true),
        reconciled(partial, 'row-1',
            amount: 7000, balance: 93000, labels: <String>['Gasto GTO-00201']),
      ],
    );

    expect(settled['row-1']?.sameStatement, isTrue);
    expect(settled['row-9']?.sameStatement, isFalse);
    expect(settled['row-9']?.summary, 'Gasto GTO-00201');
    // Same date and amount but another running balance: another movement.
    expect(settled.containsKey('row-10'), isFalse);
    expect(settled['row-3']?.summary, 'Gasto GTO-00201');
  });

  test('a manual choice counts once its operations add up to the movement', () {
    BankReconciliationCandidate payment(String id, int amount) =>
        BankReconciliationCandidate(
          targetKind: BankReconciliationTargetKind.expensePayment,
          targetId: id,
          direction: BankMovementDirection.debit,
          amountClp: amount,
          occurredOn: const BankCivilDate(2026, 8, 12),
          label: 'Pago $id',
        );
    final movement = BankStatementMovement(
      sourceRowId: 'mother',
      ordinal: 1,
      bookingDate: const BankCivilDate(2026, 7, 7),
      description: 'App-traspaso A: Maria Angelica Sandoval',
      normalizedDescription: 'app traspaso a maria angelica sandoval',
      direction: BankMovementDirection.debit,
      amountClp: 133000,
      sourcePage: 1,
      sourceLineStart: 1,
      sourceLineEnd: 1,
    );
    BankReconciliationRowDraft rowWith(List<BankReconciliationCandidate> c) {
      final proposal = BankReconciliationProposal.manual(
        sourceRowId: 'mother',
        movementAmountClp: 133000,
        candidates: c,
      )!;
      return BankReconciliationRowDraft(
        movement: movement,
        proposals: <BankReconciliationProposal>[proposal],
        selectedProposalId:
            BankReconciliationRowDraft.proposalIdentity(proposal),
      );
    }

    expect(rowWith([payment('vicente', 94500)]).isResolved, isFalse);
    expect(
      rowWith([payment('vicente', 94500), payment('lucas', 38500)]).isResolved,
      isTrue,
    );
    // Within the direct-match tolerance the last operation takes the rest.
    final rounded = BankReconciliationProposal.manual(
      sourceRowId: 'mother',
      movementAmountClp: 133000,
      candidates: [payment('vicente', 94500), payment('lucas', 38200)],
    )!;
    expect(rounded.allocations.last.bankAmountClp, 38500);
    expect(
      BankReconciliationProposal.manual(
        sourceRowId: 'mother',
        movementAmountClp: 133000,
        candidates: [
          payment('vicente', 94500),
          payment('big', 40000),
          payment('lucas', 38500)
        ],
      ),
      isNull,
    );
  });
}

class _FakeDatabaseService extends DatabaseService {}

class _RpcCall {
  const _RpcCall(this.name, this.params);

  final String name;
  final Map<String, dynamic> params;
}
