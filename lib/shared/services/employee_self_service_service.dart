import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/current_user_profile.dart';
import '../models/employee_self_service.dart';

/// Server-authoritative read backing the labor sections of `/profile`.
///
/// The client supplies only a calendar anchor. The RPC resolves `auth.uid()` to
/// exactly one active ERP profile and its exact active employee before it reads
/// any labor table. No tenant or employee selector crosses this boundary.
abstract class EmployeeSelfServiceGateway {
  Future<Map<String, dynamic>> getSnapshot({
    required DateTime? weekAnchor,
  });
}

class SupabaseEmployeeSelfServiceGateway implements EmployeeSelfServiceGateway {
  SupabaseEmployeeSelfServiceGateway([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<Map<String, dynamic>> getSnapshot({
    required DateTime? weekAnchor,
  }) async {
    final params = <String, dynamic>{};
    if (weekAnchor != null) {
      params['p_week_anchor'] = _dateString(weekAnchor);
    }
    final response = await _client.rpc(
      'get_my_employee_self_service',
      params: params,
    );
    if (response is! Map) {
      throw const FormatException(
        'Employee self-service RPC returned an invalid payload.',
      );
    }
    return Map<String, dynamic>.from(response);
  }

  String _dateString(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}

/// Week-scoped labor read model for the signed-in ERP employee.
class EmployeeSelfServiceService extends ChangeNotifier {
  EmployeeSelfServiceService({EmployeeSelfServiceGateway? gateway})
      : _gateway = gateway ?? SupabaseEmployeeSelfServiceGateway();

  final EmployeeSelfServiceGateway _gateway;

  EmployeeSelfServiceSnapshot? _snapshot;
  EmployeeSelfServiceIssue? _issue;
  bool _isLoading = false;
  bool _disposed = false;
  int _generation = 0;
  String? _userId;
  String? _employeeId;
  String? _tenantId;
  DateTime? _selectedWeekAnchor;
  DateTime _weekStart = startOfWeek(DateTime.now());

  EmployeeSelfServiceSnapshot? get snapshot => _snapshot;
  EmployeeSelfServiceIssue? get issue => _issue;
  bool get isLoading => _isLoading;
  DateTime get weekStart => _weekStart;

  bool get isCurrentWeek =>
      _snapshot?.isCurrentWeek ?? _selectedWeekAnchor == null;

  /// Monday of the week containing [value], treated as a calendar-only value.
  static DateTime startOfWeek(DateTime value) {
    final date = DateTime.utc(value.year, value.month, value.day);
    return DateTime.utc(
      date.year,
      date.month,
      date.day - (date.weekday - DateTime.monday),
    );
  }

  /// Loads the snapshot for [profile]. The database independently proves the
  /// same scope from `auth.uid()`; the client profile is only a fail-fast gate
  /// and a consistency check for the returned authority.
  Future<void> synchronize({
    required CurrentUserProfile? profile,
    bool force = false,
  }) async {
    if (_disposed) return;

    final employee = profile?.employee;
    if (profile == null ||
        employee == null ||
        employee.status != 'active' ||
        profile.employeeLinkState != EmployeeLinkState.linked) {
      _clearScope(
        issue: profile == null ? null : EmployeeSelfServiceIssue.notLinked,
      );
      return;
    }

    final userId = profile.userId;
    final employeeId = employee.id;
    final tenantId = profile.tenantId;
    final scopeChanged =
        _userId != userId || _employeeId != employeeId || _tenantId != tenantId;
    if (scopeChanged) {
      _snapshot = null;
      _issue = null;
      _selectedWeekAnchor = null;
      _weekStart = startOfWeek(DateTime.now());
    } else if (!force && _snapshot?.weekStart == _weekStart && !_isLoading) {
      return;
    }

    final generation = ++_generation;
    _userId = userId;
    _employeeId = employeeId;
    _tenantId = tenantId;
    _isLoading = true;
    _notify();

    try {
      final next = await _load(
        expectedUserId: userId,
        expectedEmployeeId: employeeId,
        expectedTenantId: tenantId,
        weekAnchor: _selectedWeekAnchor,
      );
      if (!_isCurrent(userId, employeeId, tenantId, generation)) return;
      _snapshot = next;
      _weekStart = next.weekStart;
      _issue = null;
    } on _EmployeeSelfServiceScopeMismatch catch (error) {
      if (!_isCurrent(userId, employeeId, tenantId, generation)) return;
      _snapshot = null;
      _issue = EmployeeSelfServiceIssue.inconsistent;
      debugPrint(
        '⚠️ [MyProfile] Employee self-service scope rejected: $error',
      );
    } catch (error) {
      if (!_isCurrent(userId, employeeId, tenantId, generation)) return;
      _snapshot = null;
      _issue = EmployeeSelfServiceIssue.unavailable;
      debugPrint('⚠️ [MyProfile] Employee self-service load failed: $error');
    } finally {
      if (_isCurrent(userId, employeeId, tenantId, generation)) {
        _isLoading = false;
        _notify();
      }
    }
  }

  /// Moves the rendered week by [weeks] and reloads within the bound scope.
  Future<void> shiftWeek(int weeks, {required CurrentUserProfile? profile}) {
    return selectWeek(
      DateTime.utc(
        _weekStart.year,
        _weekStart.month,
        _weekStart.day + (7 * weeks),
      ),
      profile: profile,
    );
  }

  Future<void> selectWeek(
    DateTime value, {
    required CurrentUserProfile? profile,
  }) {
    final next = startOfWeek(value);
    if (next == _weekStart && _snapshot != null && !_isLoading) {
      return Future<void>.value();
    }
    _selectedWeekAnchor = next;
    _weekStart = next;
    _notify();
    return synchronize(profile: profile, force: true);
  }

  /// Lets the server resolve the current week from the store calendar.
  Future<void> selectCurrentWeek({
    required CurrentUserProfile? profile,
  }) {
    if (_selectedWeekAnchor == null &&
        _snapshot?.isCurrentWeek == true &&
        !_isLoading) {
      return Future<void>.value();
    }
    _selectedWeekAnchor = null;
    return synchronize(profile: profile, force: true);
  }

  Future<EmployeeSelfServiceSnapshot> _load({
    required String expectedUserId,
    required String expectedEmployeeId,
    required String expectedTenantId,
    required DateTime? weekAnchor,
  }) async {
    final payload = await _gateway.getSnapshot(weekAnchor: weekAnchor);
    final userId = _requiredText(payload, 'user_id');
    final employeeId = _requiredText(payload, 'employee_id');
    final tenantId = _requiredText(payload, 'tenant_id');
    if (userId != expectedUserId ||
        employeeId != expectedEmployeeId ||
        tenantId != expectedTenantId) {
      throw const _EmployeeSelfServiceScopeMismatch(
        'RPC authority does not match the current profile.',
      );
    }

    final timezone = _requiredText(payload, 'timezone');
    final location = _strictLocation(timezone);
    final weekStart = _requiredDate(payload, 'week_start');
    final weekEnd = _requiredDate(payload, 'week_end');
    final weekStartAt = _requiredDateTime(payload, 'week_start_at');
    final weekEndAt = _requiredDateTime(payload, 'week_end_at');
    final localStart = tz.TZDateTime.from(weekStartAt, location);
    final localEnd = tz.TZDateTime.from(weekEndAt, location);
    if ((weekAnchor != null && weekStart != startOfWeek(weekAnchor)) ||
        weekStart.weekday != DateTime.monday ||
        !_sameCalendarDate(
          weekEnd,
          DateTime.utc(weekStart.year, weekStart.month, weekStart.day + 7),
        ) ||
        !weekEndAt.isAfter(weekStartAt) ||
        !_sameCalendarDate(localStart, weekStart) ||
        !_sameCalendarDate(localEnd, weekEnd) ||
        localStart.hour != 0 ||
        localStart.minute != 0 ||
        localEnd.hour != 0 ||
        localEnd.minute != 0) {
      throw const _EmployeeSelfServiceScopeMismatch(
        'RPC week boundaries are not shop-calendar boundaries.',
      );
    }

    final myShifts = _parseShifts(
      _requiredRows(payload, 'my_shifts'),
      employeeId: employeeId,
      timezone: timezone,
      isMine: true,
      weekStartAt: weekStartAt,
      weekEndAt: weekEndAt,
    );
    final teamShifts = _parseShifts(
      _requiredRows(payload, 'team_shifts'),
      employeeId: employeeId,
      timezone: timezone,
      isMine: false,
      weekStartAt: weekStartAt,
      weekEndAt: weekEndAt,
    );
    final payrollLines = _parsePayrollLines(
      _requiredRows(payload, 'payroll_lines'),
      employeeId: employeeId,
    )..sort((a, b) => b.periodEnd.compareTo(a.periodEnd));

    return EmployeeSelfServiceSnapshot(
      userId: userId,
      employeeId: employeeId,
      tenantId: tenantId,
      timezone: timezone,
      weekStart: weekStart,
      weekStartAt: weekStartAt,
      weekEndAt: weekEndAt,
      isCurrentWeek: _requiredBool(payload, 'is_current_week'),
      myShifts: myShifts,
      teamShifts: teamShifts,
      attendances: _parseAttendances(
        _requiredRows(payload, 'attendances'),
        employeeId: employeeId,
        timezone: timezone,
        weekStartAt: weekStartAt,
        weekEndAt: weekEndAt,
      ),
      payrollLines: payrollLines,
      changeRequests: _parseChangeRequests(
        _requiredRows(payload, 'change_requests'),
        employeeId: employeeId,
        timezone: timezone,
      ),
      defaultShiftBlocks: _parseDefaultBlocks(
        _requiredRows(payload, 'default_shift_blocks'),
        employeeId: employeeId,
      ),
    );
  }

  List<SelfPlannedShift> _parseShifts(
    List<Map<String, dynamic>> rows, {
    required String employeeId,
    required String timezone,
    required bool isMine,
    required DateTime weekStartAt,
    required DateTime weekEndAt,
  }) {
    return rows.map((row) {
      final rowEmployeeId = _requiredText(row, 'employee_id');
      final status = _requiredText(row, 'status');
      if ((isMine && rowEmployeeId != employeeId) ||
          (!isMine &&
              (rowEmployeeId == employeeId ||
                  (status != 'published' && status != 'completed')))) {
        throw const _EmployeeSelfServiceScopeMismatch(
          'RPC shift projection widened the employee scope.',
        );
      }
      final startAt = _requiredDateTime(row, 'start_at');
      final endAt = _requiredDateTime(row, 'end_at');
      final plannedMinutesInWeek =
          _requiredNumber(row, 'planned_minutes_in_week');
      final clippedStart = startAt.isAfter(weekStartAt) ? startAt : weekStartAt;
      final clippedEnd = endAt.isBefore(weekEndAt) ? endAt : weekEndAt;
      final expectedMinutes =
          clippedEnd.difference(clippedStart).inMicroseconds /
              Duration.microsecondsPerMinute;
      if (!endAt.isAfter(startAt) ||
          !clippedEnd.isAfter(clippedStart) ||
          (plannedMinutesInWeek - expectedMinutes).abs() > 0.02) {
        throw const _EmployeeSelfServiceScopeMismatch(
          'RPC shift projection widened the selected week.',
        );
      }
      return SelfPlannedShift(
        id: _requiredText(row, 'id'),
        startAt: startAt,
        endAt: endAt,
        timezone: timezone,
        status: status,
        source: _requiredText(row, 'source'),
        isMine: isMine,
        plannedMinutesInWeek: plannedMinutesInWeek,
        title: _text(row['title']),
        roleName: _text(row['role_name']),
        employeeName: _text(row['employee_name']),
        employeeJobTitle: _text(row['employee_job_title']),
        storeHoursValidated: row['store_hours_validated'] == true,
        outsideStoreHoursReason: _text(row['outside_store_hours_reason']),
      );
    }).toList(growable: false);
  }

  List<SelfAttendance> _parseAttendances(
    List<Map<String, dynamic>> rows, {
    required String employeeId,
    required String timezone,
    required DateTime weekStartAt,
    required DateTime weekEndAt,
  }) {
    return rows.map((row) {
      if (_requiredText(row, 'employee_id') != employeeId) {
        throw const _EmployeeSelfServiceScopeMismatch(
          'RPC attendance projection widened the employee scope.',
        );
      }
      final checkIn = _requiredDateTime(row, 'check_in');
      final checkOut = _dateTime(row['check_out']);
      final status = _requiredText(row, 'status');
      final workedMinutesInWeek =
          _requiredNumber(row, 'worked_minutes_in_week');
      // A missing checkout is an open interval; cap it at this projection's
      // authoritative store-week boundary for overlap validation.
      final intervalEnd = checkOut ?? weekEndAt;
      final clippedStart = checkIn.isAfter(weekStartAt) ? checkIn : weekStartAt;
      final clippedEnd =
          intervalEnd.isBefore(weekEndAt) ? intervalEnd : weekEndAt;
      final overlapMinutes =
          clippedEnd.difference(clippedStart).inMicroseconds /
              Duration.microsecondsPerMinute;
      if (!intervalEnd.isAfter(checkIn) ||
          !clippedEnd.isAfter(clippedStart) ||
          workedMinutesInWeek < 0 ||
          workedMinutesInWeek - overlapMinutes > 0.02 ||
          ((status != 'completed' && status != 'approved') &&
              workedMinutesInWeek != 0)) {
        throw const _EmployeeSelfServiceScopeMismatch(
          'RPC attendance projection widened the selected week.',
        );
      }
      return SelfAttendance(
        id: _requiredText(row, 'id'),
        checkIn: checkIn,
        status: status,
        timezone: timezone,
        workedMinutesInWeek: workedMinutesInWeek,
        checkOut: checkOut,
        workedHours: _number(row['worked_hours']),
        overtimeHours: _number(row['overtime_hours']),
        breakMinutes: _number(row['break_minutes'])?.round() ?? 0,
        notes: _text(row['notes']),
      );
    }).toList(growable: false);
  }

  List<SelfPayrollLine> _parsePayrollLines(
    List<Map<String, dynamic>> rows, {
    required String employeeId,
  }) {
    return rows.map((row) {
      if (_requiredText(row, 'employee_id') != employeeId) {
        throw const _EmployeeSelfServiceScopeMismatch(
          'RPC payroll projection widened the employee scope.',
        );
      }
      final voucher = _requiredMap(row, 'voucher');
      final voucherId = _requiredText(voucher, 'id');
      final periodStart = _requiredDate(voucher, 'period_start');
      final periodEnd = _requiredDate(voucher, 'period_end');
      if (_requiredText(row, 'voucher_id') != voucherId ||
          periodEnd.isBefore(periodStart)) {
        throw const _EmployeeSelfServiceScopeMismatch(
          'RPC payroll projection returned an inconsistent voucher.',
        );
      }
      return SelfPayrollLine(
        id: _requiredText(row, 'id'),
        voucherId: voucherId,
        periodStart: periodStart,
        periodEnd: periodEnd,
        status: _requiredText(voucher, 'status'),
        workedHours: _requiredNumber(row, 'worked_hours'),
        overtimeHours: _requiredNumber(row, 'overtime_hours'),
        regularAmount: _requiredNumber(row, 'regular_amount'),
        overtimeAmount: _requiredNumber(row, 'overtime_amount'),
        totalAmount: _requiredNumber(row, 'total_amount'),
        voucherNumber: _text(voucher['voucher_number']),
        periodLabel: _text(voucher['period_label']),
        paidAt: _dateTime(voucher['paid_at']),
        paymentMethodName: _text(row['payment_method']),
      );
    }).toList(growable: false);
  }

  List<SelfShiftChangeRequest> _parseChangeRequests(
    List<Map<String, dynamic>> rows, {
    required String employeeId,
    required String timezone,
  }) {
    return rows.map((row) {
      if (_requiredText(row, 'employee_id') != employeeId) {
        throw const _EmployeeSelfServiceScopeMismatch(
          'RPC request projection widened the employee scope.',
        );
      }
      return SelfShiftChangeRequest(
        id: _requiredText(row, 'id'),
        requestType: _requiredText(row, 'request_type'),
        status: _requiredText(row, 'status'),
        createdAt: _requiredDateTime(row, 'created_at'),
        timezone: timezone,
        requestedStartAt: _dateTime(row['requested_start_at']),
        requestedEndAt: _dateTime(row['requested_end_at']),
        workerNote: _text(row['worker_note']),
        managerNote: _text(row['manager_note']),
        decidedAt: _dateTime(row['decided_at']),
      );
    }).toList(growable: false);
  }

  List<SelfDefaultShiftBlock> _parseDefaultBlocks(
    List<Map<String, dynamic>> rows, {
    required String employeeId,
  }) {
    return rows.map((row) {
      if (_requiredText(row, 'employee_id') != employeeId) {
        throw const _EmployeeSelfServiceScopeMismatch(
          'RPC default schedule widened the employee scope.',
        );
      }
      final dayOfWeek = _requiredNumber(row, 'day_of_week').round();
      if (dayOfWeek < 1 || dayOfWeek > 7) {
        throw const FormatException('Invalid default shift weekday.');
      }
      return SelfDefaultShiftBlock(
        id: _requiredText(row, 'id'),
        dayOfWeek: dayOfWeek,
        startTime: _requiredText(row, 'start_time'),
        endTime: _requiredText(row, 'end_time'),
        roleName: _text(row['role_name']),
      );
    }).toList(growable: false);
  }

  void _clearScope({required EmployeeSelfServiceIssue? issue}) {
    _generation++;
    _userId = null;
    _employeeId = null;
    _tenantId = null;
    _selectedWeekAnchor = null;
    _snapshot = null;
    _isLoading = false;
    _issue = issue;
    _notify();
  }

  bool _isCurrent(
    String userId,
    String employeeId,
    String tenantId,
    int generation,
  ) {
    return !_disposed &&
        _userId == userId &&
        _employeeId == employeeId &&
        _tenantId == tenantId &&
        _generation == generation;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  List<Map<String, dynamic>> _requiredRows(
    Map<String, dynamic> source,
    String key,
  ) {
    final value = source[key];
    if (value is! List) {
      throw FormatException('Missing self-service list: $key');
    }
    return value.map((row) {
      if (row is! Map) {
        throw FormatException('Invalid self-service row in $key');
      }
      return Map<String, dynamic>.from(row);
    }).toList(growable: false);
  }

  Map<String, dynamic> _requiredMap(
    Map<String, dynamic> source,
    String key,
  ) {
    final value = source[key];
    if (value is! Map) throw FormatException('Missing map: $key');
    return Map<String, dynamic>.from(value);
  }

  String _requiredText(Map<String, dynamic> source, String key) {
    final value = _text(source[key]);
    if (value == null) throw FormatException('Missing text: $key');
    return value;
  }

  double _requiredNumber(Map<String, dynamic> source, String key) {
    final value = _number(source[key]);
    if (value == null || !value.isFinite) {
      throw FormatException('Missing number: $key');
    }
    return value;
  }

  DateTime _requiredDateTime(Map<String, dynamic> source, String key) {
    final value = _dateTime(source[key]);
    if (value == null) throw FormatException('Missing timestamp: $key');
    return value;
  }

  DateTime _requiredDate(Map<String, dynamic> source, String key) {
    final value = _date(source[key]);
    if (value == null) throw FormatException('Missing date: $key');
    return value;
  }

  bool _requiredBool(Map<String, dynamic> source, String key) {
    final value = source[key];
    if (value is! bool) throw FormatException('Missing boolean: $key');
    return value;
  }

  String? _text(Object? value) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  double? _number(Object? value) {
    if (value is num) return value.toDouble();
    final text = _text(value);
    return text == null ? null : double.tryParse(text);
  }

  DateTime? _dateTime(Object? value) {
    final text = _text(value);
    if (text == null) return null;
    return DateTime.tryParse(text)?.toUtc();
  }

  /// Parses a calendar date without converting it to the device timezone.
  DateTime? _date(Object? value) {
    final text = _text(value);
    if (text == null) return null;
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return null;
    return DateTime.utc(parsed.year, parsed.month, parsed.day);
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}

class _EmployeeSelfServiceScopeMismatch implements Exception {
  const _EmployeeSelfServiceScopeMismatch(this.message);

  final String message;

  @override
  String toString() => message;
}

bool _sameCalendarDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

/// Renders [instant] on the authoritative store calendar [timezone].
DateTime employeeSelfServiceLocalTime(DateTime instant, String? timezone) {
  final location = _resolveLocation(timezone);
  return tz.TZDateTime.from(instant.toUtc(), location);
}

tz.Location _strictLocation(String timezone) {
  _initializeTimeZones();
  try {
    return tz.getLocation(timezone);
  } catch (_) {
    throw const _EmployeeSelfServiceScopeMismatch(
      'RPC returned an unknown store timezone.',
    );
  }
}

tz.Location _resolveLocation(String? timezone) {
  _initializeTimeZones();
  if (timezone != null && timezone.isNotEmpty) {
    try {
      return tz.getLocation(timezone);
    } catch (_) {
      // Server snapshots validate this value before publication. The fallback
      // protects standalone rendering of historical/test model instances.
    }
  }
  return tz.getLocation('America/Santiago');
}

bool _timeZonesInitialized = false;

void _initializeTimeZones() {
  if (_timeZonesInitialized) return;
  tzdata.initializeTimeZones();
  _timeZonesInitialized = true;
}
