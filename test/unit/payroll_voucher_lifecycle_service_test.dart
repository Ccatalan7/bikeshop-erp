import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/accounting/services/financial_projection_refresh_coordinator.dart';
import 'package:vinabike_erp/modules/hr/models/payroll_voucher.dart';
import 'package:vinabike_erp/modules/hr/services/payroll_voucher_service.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
      httpClient: MockClient(
        (request) async => http.Response(
          '[]',
          200,
          headers: const <String, String>{
            'content-type': 'application/json',
          },
          request: request,
        ),
      ),
    );
  });

  test('commitVoucher sends one exact versioned idempotent command', () async {
    final database = _LifecycleDatabaseService();
    final refresh = _RecordingRefreshCoordinator();
    final service = PayrollVoucherService(
      database,
      financialProjectionRefresh: refresh,
    );
    addTearDown(() {
      service.dispose();
      database.dispose();
      refresh.dispose();
    });

    await service.commitVoucher(
      'voucher-confirm',
      operationKey: 'confirm-operation-0001',
      expectedReconciliationVersion: 17,
    );

    expect(database.selectByIdCalls, isEmpty);
    expect(database.rpcCalls, hasLength(1));
    final call = database.rpcCalls.single;
    expect(call.functionName, 'confirm_payroll_voucher_v2');
    expect(
      call.params,
      <String, dynamic>{
        'p_voucher_id': 'voucher-confirm',
        'p_operation_key': 'confirm-operation-0001',
        'p_expected_reconciliation_version': 17,
      },
    );
    expect(
      refresh.changes.single.entityId,
      'voucher-confirm',
    );
  });

  test('commitVoucher uses the version the user actually loaded', () async {
    final database = _LifecycleDatabaseService()
      ..voucherListRows.add(
        <String, dynamic>{
          'id': 'voucher-observed',
          'tenant_id': 'tenant-1',
          'voucher_number': 'NOM-00001',
          'period_start': '2026-07-20',
          'period_end': '2026-07-26',
          'period_label': 'Semana 30',
          'total_hours': 1,
          'total_amount': 3500,
          'employee_count': 1,
          'status': 'draft',
          'created_at': '2026-07-27T00:00:00.000Z',
          'updated_at': '2026-07-27T00:00:00.000Z',
          'reconciliation_version': 17,
        },
      )
      ..voucherVersions['voucher-observed'] = 18;
    final refresh = _RecordingRefreshCoordinator();
    final service = PayrollVoucherService(
      database,
      financialProjectionRefresh: refresh,
    );
    addTearDown(() {
      service.dispose();
      database.dispose();
      refresh.dispose();
    });

    await service.fetchVouchers(forceRefresh: true);
    database
      ..rpcCalls.clear()
      ..selectByIdCalls.clear();

    await service.commitVoucher(
      'voucher-observed',
      operationKey: 'confirm-observed-0001',
    );

    expect(database.selectByIdCalls, isEmpty);
    expect(
      database.rpcCalls.single.params['p_expected_reconciliation_version'],
      17,
      reason: 'the RPC must reject a concurrent version 18 instead of '
          'silently adopting it',
    );
  });

  test(
      'fetchVouchers falls back to legacy headers when only the reconciliation '
      'version column is missing', () async {
    final database = _LifecycleDatabaseService()
      ..rejectReconciliationVersionColumn = true
      ..voucherListRows.add(
        <String, dynamic>{
          'id': 'legacy-voucher',
          'tenant_id': 'tenant-1',
          'voucher_number': 'NOM-00001',
          'period_start': '2026-07-20',
          'period_end': '2026-07-26',
          'period_label': 'Semana 30',
          'total_hours': 36.5,
          'total_amount': 127750,
          'employee_count': 1,
          'status': 'draft',
          'created_at': '2026-07-27T00:00:00.000Z',
          'updated_at': '2026-07-27T00:00:00.000Z',
        },
      );
    final refresh = _RecordingRefreshCoordinator();
    final service = PayrollVoucherService(
      database,
      financialProjectionRefresh: refresh,
    );
    addTearDown(() {
      service.dispose();
      database.dispose();
      refresh.dispose();
    });

    final vouchers = await service.fetchVouchers(forceRefresh: true);

    expect(database.voucherSelectColumns, hasLength(2));
    expect(
      database.voucherSelectColumns.first,
      contains('reconciliation_version'),
    );
    expect(
      database.voucherSelectColumns.last,
      isNot(contains('reconciliation_version')),
    );
    expect(vouchers.single.id, 'legacy-voucher');
    expect(vouchers.single.reconciliationVersion, 0);
    expect(service.supportsVersionedPayrollCommands, isFalse);
  });

  test('current headers prove the versioned command bundle is available',
      () async {
    final database = _LifecycleDatabaseService();
    final service = PayrollVoucherService(database);
    addTearDown(() {
      service.dispose();
      database.dispose();
    });

    await service.fetchVouchers(forceRefresh: true);

    expect(service.supportsVersionedPayrollCommands, isTrue);
  });

  test('open-week reader filters archive states at the database boundary',
      () async {
    final database = _LifecycleDatabaseService()
      ..voucherListRows.addAll(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'voucher-open',
            'tenant_id': 'tenant-1',
            'voucher_number': 'NOM-OPEN',
            'period_start': '2026-07-20',
            'period_end': '2026-07-26',
            'period_label': 'Semana 30',
            'total_hours': 10,
            'total_amount': 35000,
            'employee_count': 1,
            'status': 'partial',
            'created_at': '2026-07-27T00:00:00.000Z',
            'updated_at': '2026-07-27T00:00:00.000Z',
            'reconciliation_version': 4,
          },
          <String, dynamic>{
            'id': 'voucher-paid',
            'tenant_id': 'tenant-1',
            'voucher_number': 'NOM-PAID',
            'period_start': '2026-07-13',
            'period_end': '2026-07-19',
            'period_label': 'Semana 29',
            'total_hours': 8,
            'total_amount': 28000,
            'employee_count': 1,
            'status': 'paid',
            'created_at': '2026-07-20T00:00:00.000Z',
            'updated_at': '2026-07-20T00:00:00.000Z',
            'reconciliation_version': 8,
          },
        ],
      );
    final service = PayrollVoucherService(database);
    addTearDown(() {
      service.dispose();
      database.dispose();
    });

    final vouchers = await service.fetchOpenVouchers();

    expect(vouchers.map((voucher) => voucher.id), ['voucher-open']);
    expect(database.lastVoucherWhere, 'status');
    expect(
      database.lastVoucherWhereIn,
      const <String>['draft', 'confirmed', 'partial'],
    );
  });

  test('legacy history compatibility stays bounded and header-only', () async {
    final database = _LifecycleDatabaseService()
      ..voucherListRows.addAll(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'voucher-paid',
            'tenant_id': 'tenant-1',
            'voucher_number': 'NOM-PAID',
            'period_start': '2026-07-13',
            'period_end': '2026-07-19',
            'period_label': 'Semana 29',
            'total_hours': 8,
            'total_amount': 28000,
            'employee_count': 1,
            'status': 'paid',
            'created_at': '2026-07-20T00:00:00.000Z',
            'updated_at': '2026-07-20T00:00:00.000Z',
            'reconciliation_version': 8,
          },
          <String, dynamic>{
            'id': 'voucher-draft',
            'tenant_id': 'tenant-1',
            'voucher_number': 'NOM-DRAFT',
            'period_start': '2026-07-20',
            'period_end': '2026-07-26',
            'period_label': 'Semana 30',
            'total_hours': 10,
            'total_amount': 35000,
            'employee_count': 1,
            'status': 'draft',
            'created_at': '2026-07-27T00:00:00.000Z',
            'updated_at': '2026-07-27T00:00:00.000Z',
            'reconciliation_version': 1,
          },
        ],
      );
    final service = PayrollVoucherService(database);
    addTearDown(() {
      service.dispose();
      database.dispose();
    });

    final vouchers = await service.fetchLegacyHistoryVoucherHeaders(limit: 12);

    expect(vouchers.map((voucher) => voucher.id), ['voucher-paid']);
    expect(vouchers.single.lines, isEmpty);
    expect(database.lastVoucherWhere, 'status');
    expect(
      database.lastVoucherWhereIn,
      const <String>['paid', 'voided'],
    );
    expect(database.lastVoucherLimit, 12);
    expect(database.lineSelectCalls, isEmpty);
  });

  test('exact history detail never hides a backend failure as absence',
      () async {
    final database = _LifecycleDatabaseService()
      ..selectByIdError = StateError('network unavailable');
    final service = PayrollVoucherService(database);
    addTearDown(() {
      service.dispose();
      database.dispose();
    });

    await expectLater(
      service.fetchVoucherDetail('voucher-paid'),
      throwsA(isA<StateError>()),
    );
    expect(
      await service.getVoucher('voucher-paid'),
      isNull,
      reason: 'only the explicitly legacy wrapper keeps nullable semantics',
    );
  });

  test('open advances are filtered at the database boundary', () async {
    final database = _LifecycleDatabaseService()
      ..employeeAdvanceRows.addAll(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'advance-open',
            'employee_id': 'employee-1',
            'amount': 40000,
            'amount_applied': 0,
            'paid_at': '2026-07-29T15:00:00.000Z',
            'status': 'open',
          },
          <String, dynamic>{
            'id': 'advance-applied',
            'employee_id': 'employee-1',
            'amount': 10000,
            'amount_applied': 10000,
            'paid_at': '2026-07-20T15:00:00.000Z',
            'status': 'applied',
          },
        ],
      );
    final service = PayrollVoucherService(database);
    addTearDown(() {
      service.dispose();
      database.dispose();
    });

    final advances = await service.getOpenEmployeeAdvances();

    expect(advances.map((advance) => advance.id), ['advance-open']);
    expect(database.lastAdvanceWhere, 'status');
    expect(
      database.lastAdvanceWhereIn,
      const <String>['open', 'partially_applied'],
    );
  });

  test('settlement hydration exposes the authoritative partial balance',
      () async {
    final database = _LifecycleDatabaseService()
      ..expensePaymentRows.add(
        <String, dynamic>{
          'expense_id': 'expense-partial',
          'amount': 30000,
        },
      )
      ..advanceAllocationRows.add(
        <String, dynamic>{
          'voucher_line_id': 'line-partial',
          'amount': 20000,
        },
      );
    final service = PayrollVoucherService(database);
    addTearDown(() {
      service.dispose();
      database.dispose();
    });
    final now = DateTime(2026, 7, 29);
    final voucher = PayrollVoucher(
      id: 'voucher-partial',
      tenantId: 'tenant-1',
      voucherNumber: 'NOM-PARTIAL',
      periodStart: DateTime(2026, 7, 6),
      periodEnd: DateTime(2026, 7, 12),
      status: PayrollVoucherStatus.partial,
      createdAt: now,
      updatedAt: now,
      lines: const [
        PayrollVoucherLine(
          id: 'line-partial',
          voucherId: 'voucher-partial',
          employeeId: 'employee-partial',
          employeeName: 'Persona Parcial',
          totalAmount: 100000,
          expenseId: 'expense-partial',
        ),
      ],
    );

    final hydrated = await service.hydrateVoucherSettlements(voucher);
    final line = hydrated.lines.single;

    expect(line.cashPaid, 30000);
    expect(line.advancesApplied, 20000);
    expect(line.settledAmount, 50000);
    expect(line.balance, 50000);
  });

  test('versioned open weeks hydrate detailed evidence in one batch', () async {
    final database = _LifecycleDatabaseService()
      ..settlementEvidenceRows.addAll(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'voucher_id': 'voucher-evidence-a',
            'line_id': 'line-evidence-a',
            'evidence_id': 'payment-evidence-a',
            'evidence_kind': 'payment',
            'source': 'bank_statement',
            'amount': 72000,
            'effective_date': '2026-07-29',
            'recorded_at': '2026-07-29T18:00:00.000Z',
            'payment_method_id': 'method-transfer',
            'payment_method_label': 'Transferencia',
            'payment_account_id': 'account-bank',
            'payment_account_label': 'Banco Estado',
            'reference': 'TRF-88421',
            'actor_id': 'actor-1',
            'actor_name': 'Claudio Catalán',
            'statement_import_id': 'import-july',
            'statement_row_id': 'statement-row-a',
            'bank_amount': 72250,
            'variance': 250,
            'variance_disposition': 'unresolved',
            'statement_transaction_date': '2026-07-27',
            'statement_description_observed': 'App-traspaso A: Persona A',
            'statement_document_observed': 'DOC-72000',
            'statement_page_number': 5,
            'statement_source_line_start': 44,
            'statement_source_line_end': 45,
            'statement_row_ordinal': 1,
          },
          <String, dynamic>{
            'voucher_id': 'voucher-evidence-a',
            'line_id': 'line-evidence-a',
            'evidence_id': 'advance-evidence-a',
            'evidence_kind': 'advance',
            'source': 'manual',
            'amount': 20000,
            'effective_date': '2026-07-29T18:01:00.000Z',
            'recorded_at': '2026-07-29T18:01:00.000Z',
            'advance_id': 'advance-a',
          },
        ],
      );
    final service = PayrollVoucherService(database);
    addTearDown(() {
      service.dispose();
      database.dispose();
    });
    await service.fetchVouchers(forceRefresh: true);
    database.rpcCalls.clear();
    final now = DateTime(2026, 7, 29);
    final vouchers = [
      PayrollVoucher(
        id: 'voucher-evidence-a',
        tenantId: 'tenant-1',
        voucherNumber: 'NOM-EVIDENCE-A',
        periodStart: DateTime(2026, 7, 6),
        periodEnd: DateTime(2026, 7, 12),
        status: PayrollVoucherStatus.partial,
        createdAt: now,
        updatedAt: now,
        lines: const [
          PayrollVoucherLine(
            id: 'line-evidence-a',
            voucherId: 'voucher-evidence-a',
            employeeId: 'employee-a',
            employeeName: 'Persona A',
            totalAmount: 100000,
            expenseId: 'expense-a',
          ),
        ],
      ),
      PayrollVoucher(
        id: 'voucher-evidence-b',
        tenantId: 'tenant-1',
        voucherNumber: 'NOM-EVIDENCE-B',
        periodStart: DateTime(2026, 7, 13),
        periodEnd: DateTime(2026, 7, 19),
        status: PayrollVoucherStatus.confirmed,
        createdAt: now,
        updatedAt: now,
        lines: const [
          PayrollVoucherLine(
            id: 'line-evidence-b',
            voucherId: 'voucher-evidence-b',
            employeeId: 'employee-b',
            employeeName: 'Persona B',
            totalAmount: 50000,
            expenseId: 'expense-b',
          ),
        ],
      ),
    ];

    final hydrated = await service.hydrateOpenVoucherSettlements(vouchers);

    expect(database.rpcCalls, hasLength(1));
    expect(
      database.rpcCalls.single.functionName,
      'get_payroll_voucher_settlement_evidence_v2',
    );
    expect(
      database.rpcCalls.single.params['p_voucher_ids'],
      ['voucher-evidence-a', 'voucher-evidence-b'],
    );
    final lineA = hydrated.first.lines.single;
    expect(lineA.cashPaid, 72000);
    expect(lineA.advancesApplied, 20000);
    expect(lineA.balance, 8000);
    expect(lineA.settlementEvidence, hasLength(2));
    expect(
      lineA.settlementEvidence.first.source,
      PayrollSettlementEvidenceSource.bankStatement,
    );
    expect(
      lineA.settlementEvidence.first.paymentMethodLabel,
      'Transferencia',
    );
    expect(lineA.settlementEvidence.first.actorName, 'Claudio Catalán');
    expect(
      lineA.settlementEvidence.first.statementTransactionDate,
      DateTime(2026, 7, 27),
    );
    expect(
      lineA.settlementEvidence.first.statementDescriptionObserved,
      'App-traspaso A: Persona A',
    );
    expect(
      lineA.settlementEvidence.first.statementDocumentObserved,
      'DOC-72000',
    );
    expect(lineA.settlementEvidence.first.statementPageNumber, 5);
    expect(lineA.settlementEvidence.first.statementSourceLineStart, 44);
    expect(lineA.settlementEvidence.first.statementSourceLineEnd, 45);
    expect(lineA.settlementEvidence.first.statementRowOrdinal, 1);
    expect(
      lineA.settlementEvidence.first.hasObservedStatementMetadata,
      isTrue,
    );
    expect(
      lineA.settlementEvidence.last.hasObservedStatementMetadata,
      isFalse,
    );
    expect(hydrated.last.lines.single.balance, 50000);
  });

  test('v2 evidence preserves the append-only correction relationship', () {
    final evidence = PayrollSettlementEvidence.fromMap(
      <String, dynamic>{
        'evidence_id': 'payment-original',
        'voucher_id': 'voucher-1',
        'line_id': 'line-1',
        'evidence_kind': 'payment',
        'source': 'bank_statement',
        'amount': 72000,
        'is_reversal': false,
        'reversal_evidence_id': 'payment-reversal',
        'reversal_reason': 'Cuenta incorrecta',
        'reversal_operation_id': 'operation-1',
        'reversal_operation_key': 'reverse-payment-0001',
        'reversed_at': '2026-08-02T12:00:00.000Z',
        'reversed_by_id': 'user-1',
        'reversed_by_name': 'Claudio Catalán',
      },
    );

    expect(evidence.isReversal, isFalse);
    expect(evidence.isReversed, isTrue);
    expect(evidence.isActiveSettlement, isFalse);
    expect(evidence.reversalEvidenceId, 'payment-reversal');
    expect(evidence.reversalReason, 'Cuenta incorrecta');
    expect(evidence.reversedByName, 'Claudio Catalán');
  });

  test('refinement capabilities come from the exact server contract', () async {
    final database = _LifecycleDatabaseService();
    final service = PayrollVoucherService(database);
    addTearDown(() {
      service.dispose();
      database.dispose();
    });

    final capabilities = await service.getRefinementCapabilities();

    expect(capabilities.employeePaymentMethodCommand, isTrue);
    expect(capabilities.structuredAdvanceAudit, isTrue);
    expect(capabilities.auditedSettlementReversal, isTrue);
    expect(capabilities.settlementEvidenceContractVersion, 2);
    expect(
      database.rpcCalls.single.functionName,
      'get_payroll_refinement_capabilities_v1',
    );
  });

  test('reverseSettlement sends one versioned correction and publishes refresh',
      () async {
    final database = _LifecycleDatabaseService();
    final refresh = _RecordingRefreshCoordinator();
    final service = PayrollVoucherService(
      database,
      financialProjectionRefresh: refresh,
    );
    addTearDown(() {
      service.dispose();
      database.dispose();
      refresh.dispose();
    });

    final receipt = await service.reverseSettlement(
      voucherId: 'voucher-reversal',
      settlementKind: PayrollSettlementEvidenceKind.payment,
      settlementId: 'payment-original',
      reason: 'Cuenta contable incorrecta',
      operationKey: 'reverse-payment-0001',
      expectedReconciliationVersion: 17,
    );

    expect(receipt.reversalSettlementId, 'settlement-reversal');
    expect(database.rpcCalls, hasLength(1));
    expect(
      database.rpcCalls.single.functionName,
      'reverse_payroll_settlement_v1',
    );
    expect(
      database.rpcCalls.single.params,
      <String, dynamic>{
        'p_voucher_id': 'voucher-reversal',
        'p_settlement_kind': 'payment',
        'p_settlement_id': 'payment-original',
        'p_reason': 'Cuenta contable incorrecta',
        'p_operation_key': 'reverse-payment-0001',
        'p_expected_reconciliation_version': 17,
      },
    );
    expect(refresh.changes.single.entityId, 'voucher-reversal');
  });

  test('deleteVoucher loads a version and generates a command key once',
      () async {
    final database = _LifecycleDatabaseService()
      ..voucherVersions['voucher-delete'] = 23;
    final refresh = _RecordingRefreshCoordinator();
    final service = PayrollVoucherService(
      database,
      financialProjectionRefresh: refresh,
    );
    addTearDown(() {
      service.dispose();
      database.dispose();
      refresh.dispose();
    });

    await service.deleteVoucher('voucher-delete');

    expect(database.selectByIdCalls, ['voucher-delete']);
    expect(database.rpcCalls, hasLength(1));
    final call = database.rpcCalls.single;
    expect(call.functionName, 'delete_payroll_voucher_draft_v2');
    expect(call.params['p_voucher_id'], 'voucher-delete');
    expect(call.params['p_expected_reconciliation_version'], 23);
    expect(
      call.params['p_operation_key'],
      matches(
        RegExp(
          r'^payroll_draft_delete_'
          r'[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
          r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(refresh.changes.single.entityId, 'voucher-delete');
  });

  test('empty payment is rejected before any write can be sent', () async {
    final database = _LifecycleDatabaseService();
    final service = PayrollVoucherService(database);
    addTearDown(() {
      service.dispose();
      database.dispose();
    });

    await expectLater(
      service.payVoucher('voucher-pay', paymentSplits: const {}),
      throwsA(
        isA<PayrollVoucherPreflightException>()
            .having(
              (error) => error.kind,
              'kind',
              PayrollVoucherPreflightFailureKind.rejected,
            )
            .having((error) => error.mayHaveCommitted, 'commit', isFalse),
      ),
    );

    expect(database.selectByIdCalls, isEmpty);
    expect(database.rpcCalls, isEmpty);
  });

  test('missing voucher is a typed no-write preflight rejection', () async {
    final database = _LifecycleDatabaseService();
    final service = PayrollVoucherService(database);
    addTearDown(() {
      service.dispose();
      database.dispose();
    });

    await expectLater(
      service.deleteVoucher('voucher-missing'),
      throwsA(
        isA<PayrollVoucherPreflightException>()
            .having(
              (error) => error.kind,
              'kind',
              PayrollVoucherPreflightFailureKind.rejected,
            )
            .having((error) => error.mayHaveCommitted, 'commit', isFalse),
      ),
    );

    expect(database.selectByIdCalls, ['voucher-missing']);
    expect(database.rpcCalls, isEmpty);
  });

  test('failed version read is unavailable before write, without raw error',
      () async {
    final database = _LifecycleDatabaseService()
      ..selectByIdError = StateError('secret transport detail');
    final service = PayrollVoucherService(database);
    addTearDown(() {
      service.dispose();
      database.dispose();
    });

    await expectLater(
      service.commitVoucher('voucher-unreadable'),
      throwsA(
        isA<PayrollVoucherPreflightException>()
            .having(
              (error) => error.kind,
              'kind',
              PayrollVoucherPreflightFailureKind.unavailable,
            )
            .having(
              (error) => error.userMessage,
              'safe message',
              isNot(contains('secret transport detail')),
            ),
      ),
    );

    expect(database.rpcCalls, isEmpty);
  });

  test('a version row with no version never becomes an implicit zero write',
      () async {
    final database = _LifecycleDatabaseService()
      ..voucherVersions['voucher-no-version'] = 9
      ..omitReconciliationVersion = true;
    final service = PayrollVoucherService(database);
    addTearDown(() {
      service.dispose();
      database.dispose();
    });

    await expectLater(
      service.commitVoucher('voucher-no-version'),
      throwsA(
        isA<PayrollVoucherPreflightException>().having(
          (error) => error.kind,
          'kind',
          PayrollVoucherPreflightFailureKind.unavailable,
        ),
      ),
    );

    expect(database.rpcCalls, isEmpty);
  });

  test('a malformed lifecycle RPC result publishes no committed refresh',
      () async {
    final database = _LifecycleDatabaseService()..returnMalformedResult = true;
    final refresh = _RecordingRefreshCoordinator();
    final service = PayrollVoucherService(
      database,
      financialProjectionRefresh: refresh,
    );
    addTearDown(() {
      service.dispose();
      database.dispose();
      refresh.dispose();
    });

    await expectLater(
      service.deleteVoucher(
        'voucher-delete',
        operationKey: 'delete-operation-0001',
        expectedReconciliationVersion: 23,
      ),
      throwsStateError,
    );

    expect(refresh.changes, isEmpty);
  });
}

typedef _RpcCall = ({
  String functionName,
  Map<String, dynamic> params,
});

class _LifecycleDatabaseService extends DatabaseService {
  final List<Map<String, dynamic>> voucherListRows = <Map<String, dynamic>>[];
  final Map<String, int> voucherVersions = <String, int>{};
  final List<String> selectByIdCalls = <String>[];
  final List<String?> voucherSelectColumns = <String?>[];
  String? lastVoucherWhere;
  List<String>? lastVoucherWhereIn;
  int? lastVoucherLimit;
  final List<String> lineSelectCalls = <String>[];
  final List<_RpcCall> rpcCalls = <_RpcCall>[];
  final List<Map<String, dynamic>> expensePaymentRows =
      <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> advanceAllocationRows =
      <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> settlementEvidenceRows =
      <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> employeeAdvanceRows =
      <Map<String, dynamic>>[];
  bool returnMalformedResult = false;
  bool rejectReconciliationVersionColumn = false;
  bool omitReconciliationVersion = false;
  Object? selectByIdError;
  String? lastAdvanceWhere;
  List<String>? lastAdvanceWhereIn;

  @override
  Future<List<Map<String, dynamic>>> select(
    String table, {
    String? selectColumns,
    String? where,
    List<String>? whereIn,
    String? orderBy,
    bool descending = false,
    int? limit,
    int? offset,
    bool fetchAll = false,
  }) async {
    if (table == 'payroll_vouchers') {
      voucherSelectColumns.add(selectColumns);
      lastVoucherWhere = where;
      lastVoucherWhereIn = whereIn == null ? null : List<String>.from(whereIn);
      lastVoucherLimit = limit;
      if (rejectReconciliationVersionColumn &&
          (selectColumns?.contains('reconciliation_version') ?? false)) {
        throw const PostgrestException(
          message:
              'column payroll_vouchers.reconciliation_version does not exist',
          code: '42703',
        );
      }
      final rows = where == 'status' && whereIn != null
          ? voucherListRows.where(
              (row) => whereIn.contains(row['status']?.toString()),
            )
          : voucherListRows;
      final selected = rows
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
      return limit == null
          ? selected
          : selected.take(limit).toList(growable: false);
    }
    if (table == 'payroll_voucher_lines') {
      lineSelectCalls.add(table);
      return const <Map<String, dynamic>>[];
    }
    if (table == 'expense_payments') {
      return expensePaymentRows
          .where(
              (row) => whereIn?.contains(row['expense_id']?.toString()) ?? true)
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    }
    if (table == 'employee_advance_allocations') {
      return advanceAllocationRows
          .where((row) =>
              whereIn?.contains(row['voucher_line_id']?.toString()) ?? true)
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    }
    if (table == 'employee_advances') {
      lastAdvanceWhere = where;
      lastAdvanceWhereIn = whereIn == null ? null : List<String>.from(whereIn);
      final rows = where == 'status' && whereIn != null
          ? employeeAdvanceRows.where(
              (row) => whereIn.contains(row['status']?.toString()),
            )
          : employeeAdvanceRows;
      return rows
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    }
    throw StateError('Unexpected table: $table');
  }

  @override
  Future<Map<String, dynamic>?> selectById(
    String table,
    String id, {
    String? selectColumns,
  }) async {
    expect(table, 'payroll_vouchers');
    selectByIdCalls.add(id);
    final failure = selectByIdError;
    if (failure != null) throw failure;
    final version = voucherVersions[id];
    if (version == null) return null;
    return <String, dynamic>{
      'id': id,
      if (!omitReconciliationVersion) 'reconciliation_version': version,
    };
  }

  @override
  Future<dynamic> rpc(
    String functionName, {
    Map<String, dynamic>? params,
  }) async {
    rpcCalls.add(
      (
        functionName: functionName,
        params: Map<String, dynamic>.from(
          params ?? const <String, dynamic>{},
        ),
      ),
    );
    if (functionName == 'get_payroll_voucher_settlement_evidence' ||
        functionName == 'get_payroll_voucher_settlement_evidence_v2') {
      final voucherIds =
          (params?['p_voucher_ids'] as List<dynamic>? ?? const [])
              .map((value) => value.toString())
              .toSet();
      return settlementEvidenceRows
          .where((row) => voucherIds.contains(row['voucher_id']?.toString()))
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    }
    if (functionName == 'get_payroll_refinement_capabilities_v1') {
      return <String, dynamic>{
        'contract_version': 1,
        'employee_payment_method_command': true,
        'structured_advance_audit': true,
        'audited_settlement_reversal': true,
        'settlement_evidence_contract_version': 2,
      };
    }
    if (functionName == 'reverse_payroll_settlement_v1') {
      return <String, dynamic>{
        'operation_id': 'operation-reversal',
        'operation_key': params?['p_operation_key'],
        'voucher_id': params?['p_voucher_id'],
        'original_settlement_id': params?['p_settlement_id'],
        'reversal_settlement_id': 'settlement-reversal',
        'reconciliation_version': 18,
        'replayed': false,
      };
    }
    if (returnMalformedResult) return true;
    return <String, dynamic>{
      'operation':
          functionName.contains('confirm') ? 'confirm_draft' : 'delete_draft',
      'operation_key': params?['p_operation_key'],
      'voucher_id': params?['p_voucher_id'],
    };
  }
}

class _RecordingRefreshCoordinator
    extends FinancialProjectionRefreshCoordinator {
  final List<FinancialProjectionChange> changes = <FinancialProjectionChange>[];

  @override
  void recordCommitted(FinancialProjectionChange change) {
    changes.add(change);
  }
}
