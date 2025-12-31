enum PayrollVoucherStatus { draft, pending, paid, voided }

class PayrollVoucher {
  final String? id;
  final String tenantId;
  final String voucherNumber;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String? periodLabel;
  final double totalHours;
  final double totalAmount;
  final int employeeCount;
  final PayrollVoucherStatus status;
  final DateTime? paidAt;
  final String? paidBy;
  final String? notes;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<PayrollVoucherLine> lines;

  const PayrollVoucher({
    this.id,
    required this.tenantId,
    required this.voucherNumber,
    required this.periodStart,
    required this.periodEnd,
    this.periodLabel,
    this.totalHours = 0,
    this.totalAmount = 0,
    this.employeeCount = 0,
    this.status = PayrollVoucherStatus.draft,
    this.paidAt,
    this.paidBy,
    this.notes,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.lines = const [],
  });

  PayrollVoucher copyWith({
    String? id,
    String? tenantId,
    String? voucherNumber,
    DateTime? periodStart,
    DateTime? periodEnd,
    String? periodLabel,
    double? totalHours,
    double? totalAmount,
    int? employeeCount,
    PayrollVoucherStatus? status,
    DateTime? paidAt,
    String? paidBy,
    String? notes,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<PayrollVoucherLine>? lines,
  }) {
    return PayrollVoucher(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      voucherNumber: voucherNumber ?? this.voucherNumber,
      periodStart: periodStart ?? this.periodStart,
      periodEnd: periodEnd ?? this.periodEnd,
      periodLabel: periodLabel ?? this.periodLabel,
      totalHours: totalHours ?? this.totalHours,
      totalAmount: totalAmount ?? this.totalAmount,
      employeeCount: employeeCount ?? this.employeeCount,
      status: status ?? this.status,
      paidAt: paidAt ?? this.paidAt,
      paidBy: paidBy ?? this.paidBy,
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lines: lines ?? this.lines,
    );
  }

  factory PayrollVoucher.fromMap(Map<String, dynamic> map) {
    return PayrollVoucher(
      id: map['id'],
      tenantId: map['tenant_id'],
      voucherNumber: map['voucher_number'],
      periodStart: DateTime.parse(map['period_start']),
      periodEnd: DateTime.parse(map['period_end']),
      periodLabel: map['period_label'],
      totalHours: (map['total_hours'] as num?)?.toDouble() ?? 0,
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0,
      employeeCount: map['employee_count'] ?? 0,
      status: PayrollVoucherStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => PayrollVoucherStatus.draft,
      ),
      paidAt: map['paid_at'] != null ? DateTime.parse(map['paid_at']) : null,
      paidBy: map['paid_by'],
      notes: map['notes'],
      createdBy: map['created_by'],
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
      lines: (map['lines'] as List<dynamic>?)
              ?.map((x) => PayrollVoucherLine.fromMap(x))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'voucher_number': voucherNumber,
      'period_start': periodStart.toIso8601String(),
      'period_end': periodEnd.toIso8601String(),
      'period_label': periodLabel,
      'total_hours': totalHours,
      'total_amount': totalAmount,
      'employee_count': employeeCount,
      'status': status.name,
      'paid_at': paidAt?.toIso8601String(),
      'paid_by': paidBy,
      'notes': notes,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class PayrollVoucherLine {
  final String? id;
  final String voucherId;
  final String employeeId;
  final String employeeName;
  final double workedHours;
  final double overtimeHours;
  final double hourlyRate;
  final double overtimeRate;
  final double regularAmount;
  final double overtimeAmount;
  final double totalAmount;
  final String paymentMethod;
  final bool isIncluded;
  final String? expenseId;
  final String? salaryAccountId;
  // New Strict Payment Fields
  final String? paymentMethodId;
  final String? paymentAccountId;

  const PayrollVoucherLine({
    this.id,
    required this.voucherId,
    required this.employeeId,
    required this.employeeName,
    this.workedHours = 0,
    this.overtimeHours = 0,
    this.hourlyRate = 0,
    this.overtimeRate = 0,
    this.regularAmount = 0,
    this.overtimeAmount = 0,
    this.totalAmount = 0,
    this.paymentMethod = 'transfer',
    this.isIncluded = true,
    this.expenseId,
    this.salaryAccountId,
    this.paymentMethodId,
    this.paymentAccountId,
  });

  double get totalHours => workedHours + overtimeHours;

  PayrollVoucherLine copyWith({
    String? id,
    String? voucherId,
    String? employeeId,
    String? employeeName,
    double? workedHours,
    double? overtimeHours,
    double? hourlyRate,
    double? overtimeRate,
    double? regularAmount,
    double? overtimeAmount,
    double? totalAmount,
    String? paymentMethod,
    bool? isIncluded,
    String? expenseId,
    String? salaryAccountId,
    String? paymentMethodId,
    String? paymentAccountId,
  }) {
    return PayrollVoucherLine(
      id: id ?? this.id,
      voucherId: voucherId ?? this.voucherId,
      employeeId: employeeId ?? this.employeeId,
      employeeName: employeeName ?? this.employeeName,
      workedHours: workedHours ?? this.workedHours,
      overtimeHours: overtimeHours ?? this.overtimeHours,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      overtimeRate: overtimeRate ?? this.overtimeRate,
      regularAmount: regularAmount ?? this.regularAmount,
      overtimeAmount: overtimeAmount ?? this.overtimeAmount,
      totalAmount: totalAmount ?? this.totalAmount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      isIncluded: isIncluded ?? this.isIncluded,
      expenseId: expenseId ?? this.expenseId,
      salaryAccountId: salaryAccountId ?? this.salaryAccountId,
      paymentMethodId: paymentMethodId ?? this.paymentMethodId,
      paymentAccountId: paymentAccountId ?? this.paymentAccountId,
    );
  }

  factory PayrollVoucherLine.fromMap(Map<String, dynamic> map) {
    return PayrollVoucherLine(
      id: map['id'],
      voucherId: map['voucher_id'],
      employeeId: map['employee_id'],
      employeeName: map['employee_name'],
      workedHours: (map['worked_hours'] as num?)?.toDouble() ?? 0,
      overtimeHours: (map['overtime_hours'] as num?)?.toDouble() ?? 0,
      hourlyRate: (map['hourly_rate'] as num?)?.toDouble() ?? 0,
      overtimeRate: (map['overtime_rate'] as num?)?.toDouble() ?? 0,
      regularAmount: (map['regular_amount'] as num?)?.toDouble() ?? 0,
      overtimeAmount: (map['overtime_amount'] as num?)?.toDouble() ?? 0,
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0,
      paymentMethod: map['payment_method'] ?? 'transfer',
      isIncluded: map['is_included'] ?? true,
      expenseId: map['expense_id'],
      salaryAccountId: map['salary_account_id'],
      paymentMethodId: map['payment_method_id'],
      paymentAccountId: map['payment_account_id'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'voucher_id': voucherId,
      'employee_id': employeeId,
      'employee_name': employeeName,
      'worked_hours': workedHours,
      'overtime_hours': overtimeHours,
      'hourly_rate': hourlyRate,
      'overtime_rate': overtimeRate,
      'regular_amount': regularAmount,
      'overtime_amount': overtimeAmount,
      'total_amount': totalAmount,
      'payment_method': paymentMethod, // Legacy buffer
      'is_included': isIncluded,
      'expense_id': expenseId,
      'salary_account_id': salaryAccountId,
      'payment_method_id': paymentMethodId,
      'payment_account_id': paymentAccountId,
    };
  }
}
