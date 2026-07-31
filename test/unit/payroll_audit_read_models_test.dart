import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/hr/models/payroll_audit_read_models.dart';
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

  test('advance ledger preserves totals, identities, actors and allocations',
      () {
    final page = PayrollAdvanceLedgerPage.fromMap(_advancePageResponse());

    expect(page.employeeId, 'employee-1');
    expect(page.totals.deliveredAmount, 150000);
    expect(page.totals.appliedAmount, 40000);
    expect(page.totals.balanceAmount, 110000);
    expect(page.totals.recordCount, 2);
    expect(page.hasMore, isTrue);
    expect(page.nextCursor?.id, 'advance-1');
    expect(
      page.nextCursor?.paidAt,
      DateTime.parse('2026-07-29T15:00:00Z'),
    );

    final advance = page.items.single;
    expect(advance.status, PayrollAdvanceLedgerStatus.partiallyApplied);
    expect(advance.paymentMethod.code, 'transfer');
    expect(advance.paymentAccount?.code, '1102');
    expect(advance.actor.name, 'Claudio Catalán');
    expect(advance.fundingEvidence.source, PayrollAuditEvidenceSource.manual);
    expect(advance.fundingEvidence.operationKey, 'advance-operation-1');
    expect(advance.allocations, hasLength(1));

    final allocation = advance.allocations.single;
    expect(allocation.amount, 40000);
    expect(allocation.voucherNumber, 'NOM-00028');
    expect(allocation.periodEnd, DateTime(2026, 7, 26));
    expect(allocation.voucherLineId, 'line-1');
    expect(
      allocation.evidence.source,
      PayrollAuditEvidenceSource.statementReconciliation,
    );
    expect(allocation.evidence.statementImportId, 'import-1');
  });

  test('advance service sends exact bounded keyset cursor parameters',
      () async {
    final database = _AuditReadDatabaseService()
      ..responses['get_employee_advance_ledger_page_v1'] =
          _advancePageResponse();
    final service = PayrollVoucherService(database);
    addTearDown(() {
      service.dispose();
      database.dispose();
    });

    final page = await service.fetchEmployeeAdvanceLedgerPage(
      employeeId: 'employee-1',
      pageSize: 40,
      cursor: PayrollAdvanceLedgerCursor(
        paidAt: DateTime.parse('2026-07-29T15:00:00-04:00'),
        id: 'advance-cursor',
      ),
    );

    expect(page.items, hasLength(1));
    expect(database.rpcCalls, hasLength(1));
    expect(
      database.rpcCalls.single.functionName,
      'get_employee_advance_ledger_page_v1',
    );
    expect(
      database.rpcCalls.single.params,
      <String, dynamic>{
        'p_employee_id': 'employee-1',
        'p_page_size': 40,
        'p_cursor_paid_at': '2026-07-29T19:00:00.000Z',
        'p_cursor_id': 'advance-cursor',
      },
    );
    expect(database.selectCalls, isEmpty);
  });

  test('advance service rejects an unbounded page before calling the backend',
      () async {
    final database = _AuditReadDatabaseService();
    final service = PayrollVoucherService(database);
    addTearDown(() {
      service.dispose();
      database.dispose();
    });

    await expectLater(
      service.fetchEmployeeAdvanceLedgerPage(
        employeeId: 'employee-1',
        pageSize: 101,
      ),
      throwsRangeError,
    );
    expect(database.rpcCalls, isEmpty);
  });

  test('advance capability reader falls back only when the RPC is absent',
      () async {
    final database = _AuditReadDatabaseService()
      ..errors['get_employee_advance_ledger_page_v1'] =
          const PostgrestException(
        message: 'Could not find the function '
            'public.get_employee_advance_ledger_page_v1',
        code: 'PGRST202',
      );
    final service = PayrollVoucherService(database);
    addTearDown(() {
      service.dispose();
      database.dispose();
    });

    expect(
      await service.tryFetchEmployeeAdvanceLedgerPage(
        employeeId: 'employee-1',
      ),
      isNull,
    );
    expect(database.rpcCalls, hasLength(1));
  });

  test('a signature mismatch never degrades to the legacy reader', () async {
    // L-H4: «no function matches the given name and argument types» nombra la
    // función y dice «does not exist» en el hint típico, pero es deriva de
    // contrato (RPC instalada con OTRA firma), no un backend sin instalar.
    final database = _AuditReadDatabaseService()
      ..errors['get_employee_advance_ledger_page_v1'] =
          const PostgrestException(
        message: 'no function matches the given name and argument types: '
            'public.get_employee_advance_ledger_page_v1(uuid, integer)',
        details: 'function public.get_employee_advance_ledger_page_v1(uuid, '
            'integer) does not exist',
        code: '42883',
      );
    final service = PayrollVoucherService(database);
    addTearDown(() {
      service.dispose();
      database.dispose();
    });

    await expectLater(
      service.tryFetchEmployeeAdvanceLedgerPage(
        employeeId: 'employee-1',
      ),
      throwsA(
        isA<PostgrestException>()
            .having((error) => error.code, 'code', '42883'),
      ),
    );
  });

  test('advance capability reader never hides authorization failures',
      () async {
    final database = _AuditReadDatabaseService()
      ..errors['get_employee_advance_ledger_page_v1'] =
          const PostgrestException(
        message: 'permission denied',
        code: '42501',
      );
    final service = PayrollVoucherService(database);
    addTearDown(() {
      service.dispose();
      database.dispose();
    });

    await expectLater(
      service.tryFetchEmployeeAdvanceLedgerPage(
        employeeId: 'employee-1',
      ),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('history service returns headers only and preserves its date cursor',
      () async {
    final database = _AuditReadDatabaseService()
      ..responses['get_payroll_history_page_v1'] = _historyPageResponse();
    final service = PayrollVoucherService(database);
    addTearDown(() {
      service.dispose();
      database.dispose();
    });

    final page = await service.fetchPayrollHistoryPage(
      pageSize: 15,
      cursor: PayrollHistoryCursor(
        periodEnd: DateTime(2026, 7, 19, 23, 59),
        id: 'voucher-cursor',
      ),
    );

    expect(page.items, hasLength(2));
    expect(page.items.first.status, PayrollHistoryStatus.paid);
    expect(page.items.last.status, PayrollHistoryStatus.voided);
    expect(page.items.first.reconciliationVersion, 8);
    expect(page.items.first.paidBy.name, 'Claudio Catalán');
    expect(page.hasMore, isFalse);
    expect(page.nextCursor, isNull);
    expect(
      database.rpcCalls.single.functionName,
      'get_payroll_history_page_v1',
    );
    expect(
      database.rpcCalls.single.params,
      <String, dynamic>{
        'p_page_size': 15,
        'p_cursor_period_end': '2026-07-19',
        'p_cursor_id': 'voucher-cursor',
      },
    );
    expect(
      database.selectCalls,
      isEmpty,
      reason: 'history pagination must not hydrate voucher lines',
    );
  });

  test('history capability reader falls back only when the RPC is absent',
      () async {
    final database = _AuditReadDatabaseService()
      ..errors['get_payroll_history_page_v1'] = const PostgrestException(
        message:
            'Could not find the function public.get_payroll_history_page_v1',
        code: 'PGRST202',
      );
    final service = PayrollVoucherService(database);
    addTearDown(() {
      service.dispose();
      database.dispose();
    });

    expect(await service.tryFetchPayrollHistoryPage(), isNull);
    expect(database.rpcCalls, hasLength(1));
  });

  test('history capability reader never hides authorization failures',
      () async {
    final database = _AuditReadDatabaseService()
      ..errors['get_payroll_history_page_v1'] = const PostgrestException(
        message: 'permission denied',
        code: '42501',
      );
    final service = PayrollVoucherService(database);
    addTearDown(() {
      service.dispose();
      database.dispose();
    });

    await expectLater(
      service.tryFetchPayrollHistoryPage(),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('versioned parsing rejects an unknown history status', () {
    final response = _historyPageResponse();
    final items = response['items']! as List<Map<String, dynamic>>;
    items.first['status'] = 'partial';

    expect(
      () => PayrollHistoryPage.fromMap(response),
      throwsFormatException,
    );
  });
}

typedef _RpcCall = ({
  String functionName,
  Map<String, dynamic> params,
});

class _AuditReadDatabaseService extends DatabaseService {
  final Map<String, dynamic> responses = <String, dynamic>{};
  final Map<String, Object> errors = <String, Object>{};
  final List<_RpcCall> rpcCalls = <_RpcCall>[];
  final List<String> selectCalls = <String>[];

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
    final error = errors[functionName];
    if (error != null) throw error;
    if (!responses.containsKey(functionName)) {
      throw StateError('Unexpected RPC: $functionName');
    }
    return responses[functionName];
  }

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
    selectCalls.add(table);
    throw StateError('Unexpected table read: $table');
  }
}

Map<String, dynamic> _advancePageResponse() {
  return <String, dynamic>{
    'contract_version': 1,
    'employee_id': 'employee-1',
    'totals': <String, dynamic>{
      'delivered_amount': 150000,
      'applied_amount': 40000,
      'balance_amount': 110000,
      'record_count': 2,
    },
    'items': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'advance-1',
        'employee_id': 'employee-1',
        'amount': 100000,
        'applied_amount': 40000,
        'balance_amount': 60000,
        'paid_at': '2026-07-29T15:00:00Z',
        'status': 'partially_applied',
        'payment_method': <String, dynamic>{
          'id': 'method-transfer',
          'code': 'transfer',
          'name': 'Transferencia',
        },
        'payment_account': <String, dynamic>{
          'id': 'account-bank',
          'code': '1102',
          'name': 'Banco',
        },
        'reference': 'ADV-001',
        'notes': 'Anticipo registrado',
        'actor': <String, dynamic>{
          'id': 'actor-1',
          'name': 'Claudio Catalán',
        },
        'funding_evidence': <String, dynamic>{
          'source': 'manual',
          'operation_id': 'operation-1',
          'operation_key': 'advance-operation-1',
          'recorded_at': '2026-07-29T15:00:01Z',
        },
        'created_at': '2026-07-29T15:00:01Z',
        'updated_at': '2026-07-29T16:00:00Z',
        'allocations': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'allocation-1',
            'amount': 40000,
            'applied_at': '2026-07-30T12:00:00Z',
            'notes': 'Aplicado en conciliación',
            'created_at': '2026-07-30T12:00:01Z',
            'actor': <String, dynamic>{
              'id': 'actor-1',
              'name': 'Claudio Catalán',
            },
            'voucher': <String, dynamic>{
              'id': 'voucher-1',
              'voucher_number': 'NOM-00028',
              'period_start': '2026-07-20',
              'period_end': '2026-07-26',
              'period_label': 'Semana 28',
              'status': 'paid',
            },
            'voucher_line': <String, dynamic>{
              'id': 'line-1',
              'employee_name': 'Lucas Reyes',
              'total_amount': 172875,
            },
            'evidence': <String, dynamic>{
              'source': 'statement_reconciliation',
              'operation_id': 'operation-2',
              'operation_key': 'reconcile-operation-1',
              'statement_allocation_id': 'statement-allocation-1',
              'statement_import_id': 'import-1',
              'statement_decision_id': 'decision-1',
            },
          },
        ],
      },
    ],
    'has_more': true,
    'next_cursor': <String, dynamic>{
      'paid_at': '2026-07-29T15:00:00Z',
      'id': 'advance-1',
    },
  };
}

Map<String, dynamic> _historyPageResponse() {
  return <String, dynamic>{
    'contract_version': 1,
    'items': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'voucher-paid',
        'voucher_number': 'NOM-00028',
        'period_start': '2026-07-20',
        'period_end': '2026-07-26',
        'period_label': 'Semana 28',
        'total_hours': 61,
        'total_amount': 267875,
        'employee_count': 3,
        'status': 'paid',
        'paid_at': '2026-07-29T15:00:00Z',
        'paid_by': <String, dynamic>{
          'id': 'actor-1',
          'name': 'Claudio Catalán',
        },
        'notes': null,
        'created_by': <String, dynamic>{
          'id': 'actor-1',
          'name': 'Claudio Catalán',
        },
        'created_at': '2026-07-27T12:00:00Z',
        'updated_at': '2026-07-29T15:00:00Z',
        'reconciliation_version': 8,
      },
      <String, dynamic>{
        'id': 'voucher-voided',
        'voucher_number': 'NOM-00027',
        'period_start': '2026-07-13',
        'period_end': '2026-07-19',
        'period_label': 'Semana 27',
        'total_hours': 55,
        'total_amount': 240000,
        'employee_count': 3,
        'status': 'voided',
        'paid_at': null,
        'paid_by': <String, dynamic>{'id': null, 'name': null},
        'notes': 'Anulada',
        'created_by': <String, dynamic>{
          'id': 'actor-1',
          'name': 'Claudio Catalán',
        },
        'created_at': '2026-07-20T12:00:00Z',
        'updated_at': '2026-07-21T12:00:00Z',
        'reconciliation_version': 3,
      },
    ],
    'has_more': false,
    'next_cursor': null,
  };
}
