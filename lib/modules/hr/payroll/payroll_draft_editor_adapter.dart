import '../models/payroll_voucher.dart';
import 'surfaces/payroll_generation_surface.dart';

/// Projects the persisted/generated voucher snapshot into the shared draft
/// editor model.
///
/// The week is derived from the voucher and then checked exactly. This keeps a
/// host from presenting one payroll period while saving another one.
PayrollGenerationPreview payrollGenerationPreviewFromVoucher({
  required PayrollVoucher voucher,
  required String sourceSnapshotLabel,
}) {
  final week = PayrollGenerationWeek.containing(voucher.periodStart);
  _validateWeek(voucher, week);
  _validateUniqueVoucherEmployeeIds(voucher.lines);

  return PayrollGenerationPreview(
    week: week,
    workers: <PayrollGenerationWorkerLine>[
      for (final line in voucher.lines)
        PayrollGenerationWorkerLine(
          workerId: line.employeeId,
          name: line.employeeName,
          initials: _initialsOf(line.employeeName),
          hours: line.workedHours,
          overtimeHours: line.overtimeHours,
          rateAmount: line.hourlyRate.round(),
          overtimeRateAmount: line.overtimeRate.round(),
          totalAmount: line.totalAmount.round(),
          isIncluded: line.isIncluded,
        ),
    ],
    totalAmount: voucher.totalAmount.round(),
    sourceSnapshotLabel: sourceSnapshotLabel,
  );
}

/// Applies one edited preview to its original voucher snapshot.
///
/// Only the draft values owned by this editor change: regular hours, regular
/// rate, overtime values and inclusion. Every persisted identity, payment,
/// account, audit and reconciliation field remains on its original line. The
/// server still repeats these calculations when the snapshot is written.
PayrollVoucher applyPayrollGenerationPreviewToVoucher({
  required PayrollVoucher voucher,
  required PayrollGenerationPreview preview,
}) {
  if (voucher.status != PayrollVoucherStatus.draft) {
    throw StateError('Only payroll drafts can be edited.');
  }
  _validateWeek(voucher, preview.week);

  final voucherLinesByEmployee = _voucherLinesByEmployee(voucher.lines);
  final workersByEmployee = _workersByEmployee(preview.workers);
  _validateSameEmployees(
    voucherLinesByEmployee.keys.toSet(),
    workersByEmployee.keys.toSet(),
  );

  final updatedLines = <PayrollVoucherLine>[
    for (final original in voucher.lines)
      _applyWorkerToLine(
        original,
        workersByEmployee[original.employeeId.trim()]!,
      ),
  ];

  var totalHours = 0.0;
  var totalAmount = 0.0;
  var employeeCount = 0;
  for (final line in updatedLines) {
    if (!line.isIncluded) continue;
    totalHours += line.totalHours;
    totalAmount += line.totalAmount;
    employeeCount++;
  }

  return voucher.copyWith(
    lines: updatedLines,
    totalHours: _roundMoney(totalHours),
    totalAmount: _roundMoney(totalAmount),
    employeeCount: employeeCount,
  );
}

PayrollVoucherLine _applyWorkerToLine(
  PayrollVoucherLine original,
  PayrollGenerationWorkerLine worker,
) {
  final hourlyRate = worker.rateAmount == original.hourlyRate.round()
      ? original.hourlyRate
      : worker.rateAmount.toDouble();
  final overtimeRate =
      worker.resolvedOvertimeRateAmount == original.overtimeRate.round()
          ? original.overtimeRate
          : worker.resolvedOvertimeRateAmount.toDouble();
  final regularAmount = _roundMoney(worker.hours * hourlyRate);
  final overtimeAmount = _roundMoney(worker.overtimeHours * overtimeRate);
  final totalAmount = _roundMoney(regularAmount + overtimeAmount);
  final residual = _roundMoney(totalAmount - original.settledAmount);
  final balance = residual > 0 ? residual : 0.0;

  return original.copyWith(
    workedHours: worker.hours,
    overtimeHours: worker.overtimeHours,
    hourlyRate: hourlyRate,
    overtimeRate: overtimeRate,
    regularAmount: regularAmount,
    overtimeAmount: overtimeAmount,
    totalAmount: totalAmount,
    isIncluded: worker.isIncluded,
    balance: balance,
  );
}

Map<String, PayrollVoucherLine> _voucherLinesByEmployee(
  List<PayrollVoucherLine> lines,
) {
  _validateUniqueVoucherEmployeeIds(lines);
  return <String, PayrollVoucherLine>{
    for (final line in lines) line.employeeId.trim(): line,
  };
}

void _validateUniqueVoucherEmployeeIds(List<PayrollVoucherLine> lines) {
  final ids = <String>{};
  for (final line in lines) {
    final employeeId = line.employeeId.trim();
    if (employeeId.isEmpty) {
      throw StateError('Payroll voucher contains an empty employee ID.');
    }
    if (!ids.add(employeeId)) {
      throw StateError(
        'Payroll voucher contains duplicate employee ID $employeeId.',
      );
    }
  }
}

Map<String, PayrollGenerationWorkerLine> _workersByEmployee(
  List<PayrollGenerationWorkerLine> workers,
) {
  final result = <String, PayrollGenerationWorkerLine>{};
  for (final worker in workers) {
    final workerId = worker.workerId.trim();
    if (workerId.isEmpty) {
      throw StateError('Payroll preview contains an empty employee ID.');
    }
    if (result.containsKey(workerId)) {
      throw StateError(
        'Payroll preview contains duplicate employee ID $workerId.',
      );
    }
    result[workerId] = worker;
  }
  return result;
}

void _validateSameEmployees(Set<String> voucherIds, Set<String> previewIds) {
  if (voucherIds.length == previewIds.length &&
      voucherIds.containsAll(previewIds)) {
    return;
  }

  final missing = voucherIds.difference(previewIds).toList()..sort();
  final unexpected = previewIds.difference(voucherIds).toList()..sort();
  throw StateError(
    'Payroll preview employees do not match the voucher '
    '(missing: ${missing.join(', ')}; unexpected: ${unexpected.join(', ')}).',
  );
}

void _validateWeek(PayrollVoucher voucher, PayrollGenerationWeek week) {
  if (_civilDate(voucher.periodStart) == week.start &&
      _civilDate(voucher.periodEnd) == week.end) {
    return;
  }
  throw StateError(
    'Payroll voucher period does not match preview week ${week.id}.',
  );
}

DateTime _civilDate(DateTime value) =>
    DateTime(value.year, value.month, value.day);

double _roundMoney(double value) => (value * 100).roundToDouble() / 100;

String _initialsOf(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return '·';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts[1][0]).toUpperCase();
}
