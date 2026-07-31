import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/accounting/models/journal_entry.dart';
import 'package:vinabike_erp/modules/accounting/services/accounting_service.dart';
import 'package:vinabike_erp/modules/accounting/services/financial_projection_refresh_coordinator.dart';
import 'package:vinabike_erp/modules/hr/services/payroll_voucher_service.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/rest/v1/user_profiles')) {
          return http.Response(
            '[{"tenant_id":"tenant-1","role":"admin","permissions":{}}]',
            200,
            headers: const {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response(
          '[]',
          200,
          headers: const {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await _installAuthenticatedTestSession();
  });

  test(
    'journal post, reverse and delete each publish one hint after ACK',
    () async {
      final database = _WriterHintDatabaseService();
      final coordinator = _RecordingRefreshCoordinator();
      final accounting = AccountingService(
        database,
        financialProjectionRefresh: coordinator,
      );
      addTearDown(() {
        accounting.dispose();
        accounting.journalEntries.dispose();
        accounting.chartOfAccounts.dispose();
        database.dispose();
        coordinator.dispose();
      });

      await accounting.chartOfAccounts.initializeChartOfAccounts();
      await accounting.journalEntries.postJournalEntry(_balancedEntry());

      expect(
        coordinator.changes,
        containsOnce(
          FinancialProjectionChangeKind.journalEntry,
          entityId: 'journal-1',
        ),
      );

      coordinator.changes.clear();
      await accounting.journalEntries.reverseEntry('journal-1');

      expect(
        coordinator.changes,
        containsOnce(
          FinancialProjectionChangeKind.journalEntry,
          entityId: 'journal-2',
        ),
      );

      coordinator.changes.clear();
      await accounting.journalEntries.deleteEntry('journal-2');

      expect(
        coordinator.changes,
        containsOnce(
          FinancialProjectionChangeKind.journalEntry,
          entityId: 'journal-2',
        ),
      );
    },
  );

  test(
    'journal mutations publish no hint when their final write fails',
    () async {
      final database = _WriterHintDatabaseService()..failJournalCreate = true;
      final coordinator = _RecordingRefreshCoordinator();
      final accounting = AccountingService(
        database,
        financialProjectionRefresh: coordinator,
      );
      addTearDown(() {
        accounting.dispose();
        accounting.journalEntries.dispose();
        accounting.chartOfAccounts.dispose();
        database.dispose();
        coordinator.dispose();
      });

      await accounting.chartOfAccounts.initializeChartOfAccounts();
      await expectLater(
        accounting.journalEntries.postJournalEntry(_balancedEntry()),
        throwsStateError,
      );
      expect(coordinator.changes, isEmpty);

      database.failJournalCreate = false;
      await accounting.journalEntries.postJournalEntry(_balancedEntry());
      coordinator.changes.clear();

      database.failJournalCreate = true;
      await expectLater(
        accounting.journalEntries.reverseEntry('journal-1'),
        throwsStateError,
      );
      expect(coordinator.changes, isEmpty);

      database
        ..failJournalCreate = false
        ..failJournalHeaderDelete = true;
      await expectLater(
        accounting.journalEntries.deleteEntry('journal-1'),
        throwsStateError,
      );
      expect(coordinator.changes, isEmpty);
    },
  );

  test(
    'employee advance and payroll draft revert publish only after RPC ACK',
    () async {
      final database = _WriterHintDatabaseService();
      final coordinator = _RecordingRefreshCoordinator();
      final payroll = PayrollVoucherService(
        database,
        financialProjectionRefresh: coordinator,
      );
      addTearDown(() {
        payroll.dispose();
        database.dispose();
        coordinator.dispose();
      });

      final advanceId = await payroll.registerEmployeeAdvance(
        employeeId: 'employee-1',
        amount: 45000,
        paymentMethodId: 'method-1',
        paidAt: DateTime.utc(2026, 7, 26),
      );

      expect(advanceId, 'advance-1');
      expect(
        coordinator.changes,
        containsOnce(
          FinancialProjectionChangeKind.payroll,
          entityId: 'advance-1',
        ),
      );

      coordinator.changes.clear();
      await payroll.revertToDraft('voucher-1');

      expect(
        coordinator.changes,
        containsOnce(
          FinancialProjectionChangeKind.payroll,
          entityId: 'voucher-1',
        ),
      );

      coordinator.changes.clear();
      database.failRpc = true;
      await expectLater(
        payroll.registerEmployeeAdvance(
          employeeId: 'employee-1',
          amount: 20000,
          paymentMethodId: 'method-1',
          paidAt: DateTime.utc(2026, 7, 26),
        ),
        throwsStateError,
      );
      expect(coordinator.changes, isEmpty);

      await expectLater(
        payroll.revertToDraft('voucher-1'),
        throwsStateError,
      );
      expect(coordinator.changes, isEmpty);
    },
  );
}

Matcher containsOnce(
  FinancialProjectionChangeKind kind, {
  required String entityId,
}) {
  return predicate<List<FinancialProjectionChange>>(
    (changes) =>
        changes.length == 1 &&
        changes.single.kind == kind &&
        changes.single.origin == FinancialProjectionChangeOrigin.localCommit &&
        changes.single.entityId == entityId,
    'one $kind local-commit hint for $entityId',
  );
}

JournalEntry _balancedEntry() {
  final now = DateTime.utc(2026, 7, 26, 12);
  return JournalEntry(
    tenantId: 'tenant-1',
    entryNumber: 'MAN-001',
    date: now,
    description: 'Asiento de prueba',
    type: JournalEntryType.manual,
    lines: [
      JournalLine(
        accountId: 'cash',
        accountCode: '1101',
        accountName: 'Caja',
        description: 'Débito',
        debitAmount: 100,
        creditAmount: 0,
        createdAt: now,
      ),
      JournalLine(
        accountId: 'revenue',
        accountCode: '4100',
        accountName: 'Ingresos',
        description: 'Crédito',
        debitAmount: 0,
        creditAmount: 100,
        createdAt: now,
      ),
    ],
    totalDebit: 100,
    totalCredit: 100,
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _installAuthenticatedTestSession() async {
  const userId = '00000000-0000-4000-8000-000000000001';
  final header = base64Url
      .encode(utf8.encode(jsonEncode({'alg': 'none', 'typ': 'JWT'})))
      .replaceAll('=', '');
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'exp': 4102444800,
            'sub': userId,
            'role': 'authenticated',
          }),
        ),
      )
      .replaceAll('=', '');
  final session = jsonEncode({
    'access_token': '$header.$payload.signature',
    'expires_in': 3600,
    'refresh_token': 'test-refresh-token',
    'token_type': 'bearer',
    'user': {
      'id': userId,
      'app_metadata': const <String, dynamic>{},
      'user_metadata': const <String, dynamic>{},
      'aud': 'authenticated',
      'created_at': '2026-07-26T00:00:00.000Z',
    },
  });
  await Supabase.instance.client.auth.recoverSession(session);
}

class _RecordingRefreshCoordinator
    extends FinancialProjectionRefreshCoordinator {
  final List<FinancialProjectionChange> changes = [];

  @override
  void recordCommitted(FinancialProjectionChange change) {
    changes.add(change);
  }
}

class _WriterHintDatabaseService extends DatabaseService {
  bool failJournalCreate = false;
  bool failJournalHeaderDelete = false;
  bool failRpc = false;
  int _nextJournalId = 1;

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
    if (table == 'payment_methods') {
      return const [
        {
          'id': 'method-1',
          'tenant_id': 'tenant-1',
          'name': 'Transferencia',
          'account_id': 'cash',
          'is_active': true,
        },
      ];
    }
    if (table == 'accounts') {
      return const [
        {
          'id': 'cash',
          'tenant_id': 'tenant-1',
          'code': '1101',
          'name': 'Caja',
          'type': 'asset',
          'category': 'currentAsset',
          'is_active': true,
        },
        {
          'id': 'revenue',
          'tenant_id': 'tenant-1',
          'code': '4100',
          'name': 'Ingresos',
          'type': 'income',
          'category': 'operatingIncome',
          'is_active': true,
        },
      ];
    }
    return const [];
  }

  @override
  Future<String> createJournalEntry(
    Map<String, dynamic> entry,
    List<Map<String, dynamic>> lines,
  ) async {
    if (failJournalCreate) {
      throw StateError('journal write rejected');
    }
    return 'journal-${_nextJournalId++}';
  }

  @override
  Future<Map<String, dynamic>> update(
    String table,
    String id,
    Map<String, dynamic> data, {
    bool applyTimestamps = true,
  }) async {
    return {'id': id, ...data};
  }

  @override
  Future<void> delete(String table, String id) async {
    if (table == 'journal_entries' && failJournalHeaderDelete) {
      throw StateError('journal delete rejected');
    }
  }

  @override
  Future<dynamic> rpc(
    String functionName, {
    Map<String, dynamic>? params,
  }) async {
    if (failRpc) {
      throw StateError('$functionName rejected');
    }
    if (functionName == 'register_employee_advance_v2') {
      return {'advance_id': 'advance-1'};
    }
    if (functionName == 'revert_payroll_to_draft') {
      return null;
    }
    throw StateError('Unexpected RPC: $functionName');
  }
}
