import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/models/current_user_profile.dart';
import 'package:vinabike_erp/shared/models/employee_self_service.dart';
import 'package:vinabike_erp/shared/services/employee_self_service_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('inactive and on-leave employees fail closed before the RPC', () async {
    for (final status in const ['inactive', 'on_leave']) {
      final gateway = _StaticGateway(_snapshotPayload());
      final service = EmployeeSelfServiceService(gateway: gateway);
      addTearDown(service.dispose);

      await service.synchronize(profile: _profile(status: status));

      expect(gateway.calls, 0, reason: 'status=$status');
      expect(service.snapshot, isNull, reason: 'status=$status');
      expect(
        service.issue,
        EmployeeSelfServiceIssue.notLinked,
        reason: 'status=$status',
      );
    }
  });

  test(
    'weekly totals clip crossing shifts and exclude rejected or ongoing marks',
    () async {
      final service = EmployeeSelfServiceService(
        gateway: _StaticGateway(_snapshotPayload()),
      );
      addTearDown(service.dispose);

      await service.synchronize(profile: _profile());

      final snapshot = service.snapshot!;
      expect(snapshot.timezone, 'Pacific/Auckland');
      expect(snapshot.myShifts.single.plannedDurationInWeek.inMinutes, 120);
      expect(snapshot.plannedDuration.inMinutes, 120);
      expect(snapshot.attendances, hasLength(4));
      final crossingAttendance = snapshot.attendances.singleWhere(
        (attendance) => attendance.id == 'attendance-completed-crossing',
      );
      expect(crossingAttendance.effectiveDuration.inMinutes, 120);
      expect(crossingAttendance.workedDurationInWeek.inMinutes, 60);
      expect(
        snapshot.attendances
            .singleWhere((attendance) => attendance.status == 'rejected')
            .effectiveDuration
            .inMinutes,
        450,
        reason: 'Rejected evidence stays visible with its recorded duration.',
      );
      expect(snapshot.workedDuration.inMinutes, 510);
      expect(snapshot.varianceDuration.inMinutes, 390);
    },
  );

  test('store timezone, not the device timezone, owns labor timestamps', () {
    final local = employeeSelfServiceLocalTime(
      DateTime.parse('2026-07-05T12:30:00Z'),
      'Pacific/Auckland',
    );

    expect(local.year, 2026);
    expect(local.month, DateTime.july);
    expect(local.day, 6);
    expect(local.hour, 0);
    expect(local.minute, 30);
  });

  test('calendar-only weeks stay in UTC across device DST boundaries', () {
    final start = EmployeeSelfServiceService.startOfWeek(
      DateTime(2026, DateTime.march, 11),
    );

    expect(start, DateTime.utc(2026, DateTime.march, 9));
    expect(start.isUtc, isTrue);
    expect(
      DateTime.utc(start.year, start.month, start.day + 7),
      DateTime.utc(2026, DateTime.march, 16),
    );
  });

  test('device/store week skew preserves next anchor and resets explicitly',
      () async {
    final currentWeek = _emptyWeekPayload(
      timezone: 'Pacific/Honolulu',
      weekStart: '2026-07-20',
      weekEnd: '2026-07-27',
      weekStartAt: '2026-07-20T10:00:00Z',
      weekEndAt: '2026-07-27T10:00:00Z',
      isCurrentWeek: true,
    );
    final nextWeek = _emptyWeekPayload(
      timezone: 'Pacific/Honolulu',
      weekStart: '2026-07-27',
      weekEnd: '2026-08-03',
      weekStartAt: '2026-07-27T10:00:00Z',
      weekEndAt: '2026-08-03T10:00:00Z',
      isCurrentWeek: false,
    );
    final gateway = _QueuedGateway([
      currentWeek,
      nextWeek,
      currentWeek,
    ]);
    final service = EmployeeSelfServiceService(gateway: gateway);
    addTearDown(service.dispose);
    final profile = _profile();

    await service.synchronize(profile: profile);
    await service.shiftWeek(1, profile: profile);
    await service.selectCurrentWeek(profile: profile);

    expect(gateway.anchors, [
      isNull,
      DateTime.utc(2026, 7, 27),
      isNull,
    ]);
    expect(service.snapshot?.weekStart, DateTime.utc(2026, 7, 20));
    expect(service.isCurrentWeek, isTrue);
  });

  test('a widened payroll or team projection is rejected as inconsistent',
      () async {
    final widenedPayroll = _snapshotPayload(
      payrollEmployeeId: 'employee-other',
    );
    final payrollService = EmployeeSelfServiceService(
      gateway: _StaticGateway(widenedPayroll),
    );
    addTearDown(payrollService.dispose);

    await payrollService.synchronize(profile: _profile());

    expect(payrollService.snapshot, isNull);
    expect(payrollService.issue, EmployeeSelfServiceIssue.inconsistent);

    final widenedTeam = _snapshotPayload(teamStatus: 'draft');
    final teamService = EmployeeSelfServiceService(
      gateway: _StaticGateway(widenedTeam),
    );
    addTearDown(teamService.dispose);

    await teamService.synchronize(profile: _profile());

    expect(teamService.snapshot, isNull);
    expect(teamService.issue, EmployeeSelfServiceIssue.inconsistent);

    final widenedWeek = _snapshotPayload();
    (widenedWeek['my_shifts'] as List).single['planned_minutes_in_week'] = 240;
    final weekService = EmployeeSelfServiceService(
      gateway: _StaticGateway(widenedWeek),
    );
    addTearDown(weekService.dispose);

    await weekService.synchronize(profile: _profile());

    expect(weekService.snapshot, isNull);
    expect(weekService.issue, EmployeeSelfServiceIssue.inconsistent);
  });

  test('temporally widened rows and mismatched week anchors fail closed',
      () async {
    Future<void> expectRejected(Map<String, dynamic> payload) async {
      final service = EmployeeSelfServiceService(
        gateway: _StaticGateway(payload),
      );
      addTearDown(service.dispose);

      await service.synchronize(profile: _profile());

      expect(service.snapshot, isNull);
      expect(service.issue, EmployeeSelfServiceIssue.inconsistent);
    }

    final reversedShift = _snapshotPayload();
    final reversedShiftRow = (reversedShift['my_shifts'] as List).single as Map;
    reversedShiftRow['end_at'] = reversedShiftRow['start_at'];
    await expectRejected(reversedShift);

    final outsideWeek = _snapshotPayload();
    final outsideWeekRow = (outsideWeek['my_shifts'] as List).single as Map;
    outsideWeekRow
      ..['start_at'] = '2026-07-01T00:00:00Z'
      ..['end_at'] = '2026-07-01T01:00:00Z'
      ..['planned_minutes_in_week'] = 60;
    await expectRejected(outsideWeek);

    final widenedAttendance = _snapshotPayload();
    final crossingAttendance =
        (widenedAttendance['attendances'] as List).first as Map;
    crossingAttendance['worked_minutes_in_week'] = 61;
    await expectRejected(widenedAttendance);

    final gateway = _QueuedGateway([
      _emptyWeekPayload(isCurrentWeek: true),
      _emptyWeekPayload(isCurrentWeek: true),
    ]);
    final service = EmployeeSelfServiceService(gateway: gateway);
    addTearDown(service.dispose);
    await service.synchronize(profile: _profile());

    await service.selectWeek(DateTime(2026, 7, 15), profile: _profile());

    expect(service.snapshot, isNull);
    expect(service.issue, EmployeeSelfServiceIssue.inconsistent);
  });

  test('RPC authority must match the current profile exactly', () async {
    final service = EmployeeSelfServiceService(
      gateway: _StaticGateway(
        _snapshotPayload(tenantId: 'tenant-other'),
      ),
    );
    addTearDown(service.dispose);

    await service.synchronize(profile: _profile());

    expect(service.snapshot, isNull);
    expect(service.issue, EmployeeSelfServiceIssue.inconsistent);
  });

  test('late response from the previous session scope is discarded', () async {
    final gateway = _PendingGateway();
    final service = EmployeeSelfServiceService(gateway: gateway);
    addTearDown(service.dispose);

    final oldLoad = service.synchronize(profile: _profile());
    final newLoad = service.synchronize(
      profile: _profile(
        userId: 'user-b',
        tenantId: 'tenant-b',
        employeeId: 'employee-b',
      ),
    );

    expect(gateway.requests, hasLength(2));
    gateway.requests[1].complete(
      _snapshotPayload(
        userId: 'user-b',
        tenantId: 'tenant-b',
        employeeId: 'employee-b',
      ),
    );
    await newLoad;
    gateway.requests[0].complete(_snapshotPayload());
    await oldLoad;

    expect(service.snapshot?.userId, 'user-b');
    expect(service.snapshot?.tenantId, 'tenant-b');
    expect(service.snapshot?.employeeId, 'employee-b');
    expect(service.issue, isNull);
  });
}

class _StaticGateway implements EmployeeSelfServiceGateway {
  _StaticGateway(this.payload);

  final Map<String, dynamic> payload;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> getSnapshot({
    required DateTime? weekAnchor,
  }) async {
    calls++;
    return payload;
  }
}

class _PendingGateway implements EmployeeSelfServiceGateway {
  final requests = <Completer<Map<String, dynamic>>>[];

  @override
  Future<Map<String, dynamic>> getSnapshot({
    required DateTime? weekAnchor,
  }) {
    final request = Completer<Map<String, dynamic>>();
    requests.add(request);
    return request.future;
  }
}

class _QueuedGateway implements EmployeeSelfServiceGateway {
  _QueuedGateway(this.payloads);

  final List<Map<String, dynamic>> payloads;
  final anchors = <DateTime?>[];

  @override
  Future<Map<String, dynamic>> getSnapshot({
    required DateTime? weekAnchor,
  }) async {
    anchors.add(weekAnchor);
    return payloads.removeAt(0);
  }
}

CurrentUserProfile _profile({
  String userId = 'user-a',
  String tenantId = 'tenant-a',
  String employeeId = 'employee-a',
  String status = 'active',
}) {
  return CurrentUserProfile(
    userId: userId,
    email: '$userId@example.invalid',
    emailVerified: true,
    displayName: 'Employee $userId',
    tenantId: tenantId,
    tenantName: 'Tenant $tenantId',
    tenantSubdomain: null,
    role: 'mechanic',
    permissions: const {},
    employeeLinkState: EmployeeLinkState.linked,
    employee: CurrentEmployeeProfile(
      id: employeeId,
      fullName: 'Employee $employeeId',
      employeeNumber: employeeId,
      email: null,
      rut: null,
      jobTitle: 'Mechanic',
      departmentName: null,
      status: status,
      photoUrl: null,
      phone: null,
      address: null,
      city: null,
      emergencyContactName: null,
      emergencyContactPhone: null,
      updatedAt: DateTime.utc(2026, 7, 1),
    ),
  );
}

Map<String, dynamic> _snapshotPayload({
  String userId = 'user-a',
  String tenantId = 'tenant-a',
  String employeeId = 'employee-a',
  String? payrollEmployeeId,
  String teamStatus = 'published',
}) {
  return {
    'user_id': userId,
    'tenant_id': tenantId,
    'employee_id': employeeId,
    'timezone': 'Pacific/Auckland',
    'week_start': '2026-07-06',
    'week_end': '2026-07-13',
    'week_start_at': '2026-07-05T12:00:00Z',
    'week_end_at': '2026-07-12T12:00:00Z',
    'is_current_week': false,
    'my_shifts': [
      {
        'id': 'shift-crossing',
        'employee_id': employeeId,
        'title': 'Crossing shift',
        'start_at': '2026-07-05T11:30:00Z',
        'end_at': '2026-07-05T14:00:00Z',
        'status': 'published',
        'source': 'manual',
        'store_hours_validated': true,
        'planned_minutes_in_week': 120,
      },
    ],
    'team_shifts': [
      {
        'id': 'shift-team',
        'employee_id': 'employee-team',
        'start_at': '2026-07-06T00:00:00Z',
        'end_at': '2026-07-06T08:00:00Z',
        'status': teamStatus,
        'source': 'manual',
        'store_hours_validated': true,
        'employee_name': 'Team Member',
        'planned_minutes_in_week': 480,
      },
    ],
    'attendances': [
      {
        'id': 'attendance-completed-crossing',
        'employee_id': employeeId,
        'check_in': '2026-07-05T11:00:00Z',
        'check_out': '2026-07-05T13:00:00Z',
        'worked_hours': 2,
        'worked_minutes_in_week': 60,
        'overtime_hours': 0,
        'break_minutes': 0,
        'status': 'completed',
      },
      {
        'id': 'attendance-approved',
        'employee_id': employeeId,
        'check_in': '2026-07-06T21:00:00Z',
        'check_out': '2026-07-07T05:00:00Z',
        'worked_hours': 7.5,
        'worked_minutes_in_week': 450,
        'overtime_hours': 0,
        'break_minutes': 30,
        'status': 'approved',
      },
      {
        'id': 'attendance-rejected',
        'employee_id': employeeId,
        'check_in': '2026-07-07T21:00:00Z',
        'check_out': '2026-07-08T05:00:00Z',
        'worked_hours': 7.5,
        'worked_minutes_in_week': 0,
        'overtime_hours': 0,
        'break_minutes': 30,
        'status': 'rejected',
      },
      {
        'id': 'attendance-ongoing',
        'employee_id': employeeId,
        'check_in': '2026-07-08T21:00:00Z',
        'check_out': null,
        'worked_hours': null,
        'worked_minutes_in_week': 0,
        'overtime_hours': 0,
        'break_minutes': 0,
        'status': 'ongoing',
      },
    ],
    'payroll_lines': [
      {
        'id': 'payroll-line',
        'employee_id': payrollEmployeeId ?? employeeId,
        'voucher_id': 'voucher-a',
        'worked_hours': 160,
        'overtime_hours': 0,
        'regular_amount': 800000,
        'overtime_amount': 0,
        'total_amount': 800000,
        'payment_method': 'transfer',
        'voucher': {
          'id': 'voucher-a',
          'voucher_number': 'PAY-1',
          'period_start': '2026-06-01',
          'period_end': '2026-06-30',
          'status': 'paid',
        },
      },
    ],
    'change_requests': <dynamic>[],
    'default_shift_blocks': <dynamic>[],
  };
}

Map<String, dynamic> _emptyWeekPayload({
  String timezone = 'Pacific/Auckland',
  String weekStart = '2026-07-06',
  String weekEnd = '2026-07-13',
  String weekStartAt = '2026-07-05T12:00:00Z',
  String weekEndAt = '2026-07-12T12:00:00Z',
  required bool isCurrentWeek,
}) {
  final payload = _snapshotPayload();
  payload
    ..['timezone'] = timezone
    ..['week_start'] = weekStart
    ..['week_end'] = weekEnd
    ..['week_start_at'] = weekStartAt
    ..['week_end_at'] = weekEndAt
    ..['is_current_week'] = isCurrentWeek
    ..['my_shifts'] = <dynamic>[]
    ..['team_shifts'] = <dynamic>[]
    ..['attendances'] = <dynamic>[];
  return payload;
}
