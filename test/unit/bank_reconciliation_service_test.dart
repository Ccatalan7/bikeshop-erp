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
    expect(calls.single.name, 'get_bank_reconciliation_candidates_v1');
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
    expect(calls.last.name, 'apply_bank_reconciliation_actions_v2');
    final actions =
        calls.last.params['p_actions'] as List<Map<String, dynamic>>;
    expect(actions.single['action'], 'associate_existing');
    final allocations =
        actions.single['allocations'] as List<Map<String, dynamic>>;
    expect(allocations.single['provider'], 'mercadopago');
    expect(allocations.single['instrument'], 'unknown');
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
}

class _FakeDatabaseService extends DatabaseService {}

class _RpcCall {
  const _RpcCall(this.name, this.params);

  final String name;
  final Map<String, dynamic> params;
}
