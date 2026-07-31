import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  test(
    'prepareDraftFromAttendance sends only the weekly command and preserves '
    'the external operation key',
    () async {
      final database = _PrepareDatabaseService()
        ..prepareReceipt = <String, dynamic>{
          'operation_key': 'attendance-command-0001',
          'voucher_id': 'voucher-server-owned',
          'status': 'draft',
          'reconciliation_version': 1,
          'total_hours': 10,
          'total_amount': 38500,
          'origin': const <String, dynamic>{
            'kind': 'attendance',
            'projection': 'server_derived',
          },
        };
      final service = PayrollVoucherService(database);
      addTearDown(() {
        service.dispose();
        database.dispose();
      });

      final voucherId = await service.prepareDraftFromAttendance(
        DateTime(2026, 7, 20, 14, 30),
        DateTime(2026, 7, 26, 23, 59),
        periodLabel: 'Semana 30',
        operationKey: 'attendance-command-0001',
      );

      expect(voucherId, 'voucher-server-owned');
      expect(database.selectCalls, isEmpty);
      expect(database.rpcCalls, hasLength(1));
      final call = database.rpcCalls.single;
      expect(call.functionName, 'prepare_payroll_voucher_draft_v2');
      expect(
        call.params,
        <String, dynamic>{
          'p_start_date': '2026-07-20',
          'p_end_date': '2026-07-26',
          'p_period_label': 'Semana 30',
          'p_operation_key': 'attendance-command-0001',
        },
      );
    },
  );

  test(
    'prepareDraftFromAttendance surfaces rejection without fallback or a '
    'second writer attempt',
    () async {
      const rejection = PostgrestException(
        message: 'payroll_voucher_period_already_exists',
        code: '23505',
      );
      final database = _PrepareDatabaseService()..rpcError = rejection;
      final service = PayrollVoucherService(database);
      addTearDown(() {
        service.dispose();
        database.dispose();
      });

      await expectLater(
        service.prepareDraftFromAttendance(
          DateTime(2026, 7, 20),
          DateTime(2026, 7, 26),
          operationKey: 'attendance-command-0002',
        ),
        throwsA(same(rejection)),
      );

      expect(database.rpcCalls, hasLength(1));
      expect(
        database.rpcCalls.single.functionName,
        'prepare_payroll_voucher_draft_v2',
      );
      expect(service.error, contains('payroll_voucher_period_already_exists'));
    },
  );

  test(
    'generatePreview preserves overtime and mirrors server draft arithmetic',
    () async {
      final database = _PrepareDatabaseService()
        ..employeeRows.add(
          <String, dynamic>{
            'id': 'employee-overtime',
            'first_name': 'Lucas',
            'last_name': 'Pacheco',
            'hourly_rate': 3500,
            'preferred_payment_method': 'transfer',
            'preferred_payment_method_id': 'method-transfer',
            'salary_account_id': 'salary-account',
          },
        )
        ..attendanceRows.add(
          <String, dynamic>{
            'employee_id': 'employee-overtime',
            'employee_name': 'Lucas Pacheco',
            'total_hours': 8,
            'overtime_hours': 2,
            'total_days': 1,
          },
        );
      final service = PayrollVoucherService(database);
      addTearDown(() {
        service.dispose();
        database.dispose();
      });

      final preview = await service.generatePreview(
        DateTime(2026, 7, 20),
        DateTime(2026, 7, 26),
      );
      final line = preview.lines.single;

      expect(
        database.rpcCalls.single.functionName,
        'get_payroll_attendance_summary_for_period_v2',
      );
      expect(line.workedHours, 8);
      expect(line.overtimeHours, 2);
      expect(line.hourlyRate, 3500);
      expect(line.overtimeRate, 5250);
      expect(line.regularAmount, 28000);
      expect(line.overtimeAmount, 10500);
      expect(line.totalAmount, 38500);
      expect(preview.totalHours, 10);
      expect(preview.totalAmount, 38500);
    },
  );

  test('commitVoucher is the canonical lifecycle command API', () async {
    final database = _PrepareDatabaseService();
    final service = PayrollVoucherService(database);
    addTearDown(() {
      service.dispose();
      database.dispose();
    });

    await service.commitVoucher(
      'voucher-to-commit',
      operationKey: 'commit-command-0001',
      expectedReconciliationVersion: 7,
    );

    expect(database.rpcCalls, hasLength(1));
    final call = database.rpcCalls.single;
    expect(call.functionName, 'confirm_payroll_voucher_v2');
    expect(
      call.params,
      <String, dynamic>{
        'p_voucher_id': 'voucher-to-commit',
        'p_operation_key': 'commit-command-0001',
        'p_expected_reconciliation_version': 7,
      },
    );
  });
}

typedef _RpcCall = ({
  String functionName,
  Map<String, dynamic> params,
});

class _PrepareDatabaseService extends DatabaseService {
  final List<_RpcCall> rpcCalls = <_RpcCall>[];
  final List<String> selectCalls = <String>[];
  final List<Map<String, dynamic>> employeeRows = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> attendanceRows = <Map<String, dynamic>>[];
  Map<String, dynamic>? prepareReceipt;
  Object? rpcError;

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
    if (table == 'employees') {
      return employeeRows
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    }
    throw StateError('Unexpected table: $table');
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
    final error = rpcError;
    if (error != null) throw error;
    if (functionName == 'prepare_payroll_voucher_draft_v2') {
      return prepareReceipt ??
          <String, dynamic>{
            'operation_key': params?['p_operation_key'],
            'voucher_id': 'voucher-prepared',
            'status': 'draft',
          };
    }
    if (functionName == 'get_payroll_attendance_summary_for_period_v2') {
      return attendanceRows
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    }
    if (functionName == 'confirm_payroll_voucher_v2') {
      return <String, dynamic>{
        'operation': 'confirm_draft',
        'operation_key': params?['p_operation_key'],
        'voucher_id': params?['p_voucher_id'],
      };
    }
    throw StateError('Unexpected RPC: $functionName');
  }
}
