import 'package:flutter/foundation.dart';

/// Why the signed-in ERP identity cannot render its own labor self-service.
enum EmployeeSelfServiceIssue {
  /// The Auth identity has no consistently linked, active employee record.
  notLinked,

  /// The server projection disagreed with the already proven profile scope.
  inconsistent,

  /// The scoped read failed and no authoritative snapshot could be produced.
  unavailable,
}

/// One planned shift visible to the signed-in employee.
///
/// [isMine] separates the employee's own assignment from the published team
/// coverage that gives it context. Times are stored as instants and every
/// labor surface renders them through the authoritative store [timezone].
@immutable
class SelfPlannedShift {
  const SelfPlannedShift({
    required this.id,
    required this.startAt,
    required this.endAt,
    required this.timezone,
    required this.status,
    required this.source,
    required this.isMine,
    required this.plannedMinutesInWeek,
    this.title,
    this.roleName,
    this.employeeName,
    this.employeeJobTitle,
    this.storeHoursValidated = true,
    this.outsideStoreHoursReason,
  });

  final String id;
  final DateTime startAt;
  final DateTime endAt;
  final String timezone;
  final String status;
  final String source;
  final bool isMine;
  final double plannedMinutesInWeek;
  final String? title;
  final String? roleName;
  final String? employeeName;
  final String? employeeJobTitle;
  final bool storeHoursValidated;
  final String? outsideStoreHoursReason;

  Duration get plannedDuration => endAt.difference(startAt);

  Duration get plannedDurationInWeek =>
      Duration(minutes: plannedMinutesInWeek.round());

  bool get isCancelled => status == 'cancelled';
}

/// One attendance record belonging to the signed-in employee.
@immutable
class SelfAttendance {
  const SelfAttendance({
    required this.id,
    required this.checkIn,
    required this.status,
    required this.timezone,
    required this.workedMinutesInWeek,
    this.checkOut,
    this.workedHours,
    this.overtimeHours,
    this.breakMinutes = 0,
    this.notes,
  });

  final String id;
  final DateTime checkIn;
  final String status;
  final String timezone;
  final double workedMinutesInWeek;
  final DateTime? checkOut;
  final double? workedHours;
  final double? overtimeHours;
  final int breakMinutes;
  final String? notes;

  bool get isOngoing => checkOut == null;

  bool get contributesToWorkedDuration =>
      status == 'completed' || status == 'approved';

  /// Worked time as recorded by payroll, falling back to elapsed clock time.
  Duration get effectiveDuration {
    final hours = workedHours;
    if (hours != null && hours > 0) {
      return Duration(minutes: (hours * 60).round());
    }
    final end = checkOut;
    if (end == null) return Duration.zero;
    return end.difference(checkIn);
  }

  Duration get workedDurationInWeek => contributesToWorkedDuration
      ? Duration(minutes: workedMinutesInWeek.round())
      : Duration.zero;
}

/// One payroll voucher line belonging to the signed-in employee.
@immutable
class SelfPayrollLine {
  const SelfPayrollLine({
    required this.id,
    required this.voucherId,
    required this.periodStart,
    required this.periodEnd,
    required this.status,
    required this.workedHours,
    required this.overtimeHours,
    required this.regularAmount,
    required this.overtimeAmount,
    required this.totalAmount,
    this.voucherNumber,
    this.periodLabel,
    this.paidAt,
    this.paymentMethodName,
  });

  final String id;
  final String voucherId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String status;
  final double workedHours;
  final double overtimeHours;
  final double regularAmount;
  final double overtimeAmount;
  final double totalAmount;
  final String? voucherNumber;
  final String? periodLabel;
  final DateTime? paidAt;
  final String? paymentMethodName;

  bool get isSettled => status == 'paid';
}

/// One shift change request raised by the signed-in employee.
@immutable
class SelfShiftChangeRequest {
  const SelfShiftChangeRequest({
    required this.id,
    required this.requestType,
    required this.status,
    required this.createdAt,
    required this.timezone,
    this.requestedStartAt,
    this.requestedEndAt,
    this.workerNote,
    this.managerNote,
    this.decidedAt,
  });

  final String id;
  final String requestType;
  final String status;
  final DateTime createdAt;
  final String timezone;
  final DateTime? requestedStartAt;
  final DateTime? requestedEndAt;
  final String? workerNote;
  final String? managerNote;
  final DateTime? decidedAt;

  bool get isPending => status == 'pending';
}

/// One recurring block of the employee's base weekly schedule.
@immutable
class SelfDefaultShiftBlock {
  const SelfDefaultShiftBlock({
    required this.id,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    this.roleName,
  });

  /// ISO weekday, `1` = Monday through `7` = Sunday.
  final int dayOfWeek;
  final String id;
  final String startTime;
  final String endTime;
  final String? roleName;
}

/// The authoritative labor self-service snapshot for one employee and week.
@immutable
class EmployeeSelfServiceSnapshot {
  const EmployeeSelfServiceSnapshot({
    required this.userId,
    required this.employeeId,
    required this.tenantId,
    required this.timezone,
    required this.weekStart,
    required this.weekStartAt,
    required this.weekEndAt,
    required this.isCurrentWeek,
    required this.myShifts,
    required this.teamShifts,
    required this.attendances,
    required this.payrollLines,
    required this.changeRequests,
    required this.defaultShiftBlocks,
  });

  final String userId;
  final String employeeId;
  final String tenantId;
  final String timezone;

  /// Calendar date for the Monday that opens the rendered shop-local week.
  final DateTime weekStart;
  final DateTime weekStartAt;
  final DateTime weekEndAt;
  final bool isCurrentWeek;
  final List<SelfPlannedShift> myShifts;
  final List<SelfPlannedShift> teamShifts;
  final List<SelfAttendance> attendances;
  final List<SelfPayrollLine> payrollLines;
  final List<SelfShiftChangeRequest> changeRequests;
  final List<SelfDefaultShiftBlock> defaultShiftBlocks;

  DateTime get weekEnd =>
      DateTime.utc(weekStart.year, weekStart.month, weekStart.day + 7);

  Duration get plannedDuration =>
      myShifts.where((shift) => !shift.isCancelled).fold(
            Duration.zero,
            (total, shift) => total + shift.plannedDurationInWeek,
          );

  Duration get workedDuration => attendances.fold(
        Duration.zero,
        (total, attendance) => total + attendance.workedDurationInWeek,
      );

  /// Positive when more time was worked than planned.
  Duration get varianceDuration => workedDuration - plannedDuration;

  int get plannedShiftCount =>
      myShifts.where((shift) => !shift.isCancelled).length;

  int get pendingRequestCount =>
      changeRequests.where((request) => request.isPending).length;

  SelfAttendance? get ongoingAttendance {
    for (final attendance in attendances) {
      if (attendance.isOngoing) return attendance;
    }
    return null;
  }

  SelfPlannedShift? get nextShift {
    final now = DateTime.now().toUtc();
    SelfPlannedShift? next;
    for (final shift in myShifts) {
      if (shift.isCancelled || !shift.endAt.isAfter(now)) continue;
      if (next == null || shift.startAt.isBefore(next.startAt)) next = shift;
    }
    return next;
  }

  SelfPayrollLine? get latestPayrollLine =>
      payrollLines.isEmpty ? null : payrollLines.first;

  bool get isEmpty =>
      myShifts.isEmpty &&
      teamShifts.isEmpty &&
      attendances.isEmpty &&
      payrollLines.isEmpty &&
      changeRequests.isEmpty &&
      defaultShiftBlocks.isEmpty;
}
