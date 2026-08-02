import 'payroll_audit_read_models.dart';

enum PayrollVoucherStatus { draft, confirmed, partial, paid, voided }

enum PayrollSettlementEvidenceKind { payment, advance }

enum PayrollSettlementEvidenceSource {
  manual,
  bankStatement,
  cashReconciliation,
  statementReconciliation,
  legacy,
}

/// Auditable evidence for one movement that settled a payroll obligation.
///
/// A line may have several entries because a wage can be paid partially and
/// can combine new money with one or more advance allocations.
class PayrollSettlementEvidence {
  const PayrollSettlementEvidence({
    required this.id,
    required this.voucherId,
    required this.lineId,
    required this.kind,
    required this.source,
    required this.amount,
    this.effectiveDate,
    this.cashMovementDate,
    this.recordedAt,
    this.paymentMethodId,
    this.paymentMethodLabel,
    this.paymentAccountId,
    this.paymentAccountLabel,
    this.reference,
    this.notes,
    this.actorId,
    this.actorName,
    this.fundingActorId,
    this.fundingActorName,
    this.operationId,
    this.operationKey,
    this.statementImportId,
    this.statementRowId,
    this.advanceId,
    this.bankAmount,
    this.variance,
    this.varianceDisposition,
    this.statementTransactionDate,
    this.statementDescriptionObserved,
    this.statementDocumentObserved,
    this.statementPageNumber,
    this.statementSourceLineStart,
    this.statementSourceLineEnd,
    this.statementRowOrdinal,
  });

  final String id;
  final String voucherId;
  final String lineId;
  final PayrollSettlementEvidenceKind kind;
  final PayrollSettlementEvidenceSource source;
  final double amount;
  final DateTime? effectiveDate;
  final DateTime? cashMovementDate;
  final DateTime? recordedAt;
  final String? paymentMethodId;
  final String? paymentMethodLabel;
  final String? paymentAccountId;
  final String? paymentAccountLabel;
  final String? reference;
  final String? notes;
  final String? actorId;
  final String? actorName;
  final String? fundingActorId;
  final String? fundingActorName;
  final String? operationId;
  final String? operationKey;
  final String? statementImportId;
  final String? statementRowId;
  final String? advanceId;
  final double? bankAmount;
  final double? variance;
  final String? varianceDisposition;
  final DateTime? statementTransactionDate;
  final String? statementDescriptionObserved;
  final String? statementDocumentObserved;
  final int? statementPageNumber;
  final int? statementSourceLineStart;
  final int? statementSourceLineEnd;
  final int? statementRowOrdinal;

  bool get isAdvance => kind == PayrollSettlementEvidenceKind.advance;
  bool get isFromStatement =>
      source == PayrollSettlementEvidenceSource.bankStatement ||
      source == PayrollSettlementEvidenceSource.cashReconciliation ||
      source == PayrollSettlementEvidenceSource.statementReconciliation;
  bool get hasObservedStatementMetadata =>
      source == PayrollSettlementEvidenceSource.bankStatement &&
      statementRowId?.trim().isNotEmpty == true &&
      (statementTransactionDate != null ||
          statementDescriptionObserved?.trim().isNotEmpty == true ||
          statementDocumentObserved?.trim().isNotEmpty == true ||
          statementPageNumber != null ||
          statementSourceLineStart != null ||
          statementSourceLineEnd != null ||
          statementRowOrdinal != null);

  factory PayrollSettlementEvidence.fromMap(Map<String, dynamic> map) {
    DateTime? date(String key) {
      final value = map[key]?.toString();
      return value == null ? null : DateTime.tryParse(value);
    }

    final kindValue = map['evidence_kind']?.toString();
    final sourceValue = map['source']?.toString();
    return PayrollSettlementEvidence(
      id: map['evidence_id'].toString(),
      voucherId: map['voucher_id'].toString(),
      lineId: map['line_id'].toString(),
      kind: kindValue == 'advance'
          ? PayrollSettlementEvidenceKind.advance
          : PayrollSettlementEvidenceKind.payment,
      source: switch (sourceValue) {
        'bank_statement' => PayrollSettlementEvidenceSource.bankStatement,
        'cash_reconciliation' =>
          PayrollSettlementEvidenceSource.cashReconciliation,
        'statement_reconciliation' =>
          PayrollSettlementEvidenceSource.statementReconciliation,
        'manual' => PayrollSettlementEvidenceSource.manual,
        _ => PayrollSettlementEvidenceSource.legacy,
      },
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      effectiveDate: date('effective_date'),
      cashMovementDate: date('cash_movement_date'),
      recordedAt: date('recorded_at'),
      paymentMethodId: map['payment_method_id']?.toString(),
      paymentMethodLabel: map['payment_method_label']?.toString(),
      paymentAccountId: map['payment_account_id']?.toString(),
      paymentAccountLabel: map['payment_account_label']?.toString(),
      reference: map['reference']?.toString(),
      notes: map['notes']?.toString(),
      actorId: map['actor_id']?.toString(),
      actorName: map['actor_name']?.toString(),
      fundingActorId: map['funding_actor_id']?.toString(),
      fundingActorName: map['funding_actor_name']?.toString(),
      operationId: map['operation_id']?.toString(),
      operationKey: map['operation_key']?.toString(),
      statementImportId: map['statement_import_id']?.toString(),
      statementRowId: map['statement_row_id']?.toString(),
      advanceId: map['advance_id']?.toString(),
      bankAmount: (map['bank_amount'] as num?)?.toDouble(),
      variance: (map['variance'] as num?)?.toDouble(),
      varianceDisposition: map['variance_disposition']?.toString(),
      statementTransactionDate: date('statement_transaction_date'),
      statementDescriptionObserved:
          map['statement_description_observed']?.toString(),
      statementDocumentObserved: map['statement_document_observed']?.toString(),
      statementPageNumber: (map['statement_page_number'] as num?)?.toInt(),
      statementSourceLineStart:
          (map['statement_source_line_start'] as num?)?.toInt(),
      statementSourceLineEnd:
          (map['statement_source_line_end'] as num?)?.toInt(),
      statementRowOrdinal: (map['statement_row_ordinal'] as num?)?.toInt(),
    );
  }
}

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
  final int reconciliationVersion;
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
    this.reconciliationVersion = 0,
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
    int? reconciliationVersion,
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
      reconciliationVersion:
          reconciliationVersion ?? this.reconciliationVersion,
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
      reconciliationVersion:
          (map['reconciliation_version'] as num?)?.toInt() ?? 0,
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
      'reconciliation_version': reconciliationVersion,
    };
  }
}

/// "6101-01 · Sueldos" a partir del join de la cuenta. Devuelve null cuando la
/// línea no tiene cuenta asignada, para que el respaldo lo diga en vez de
/// mostrar un vacío ambiguo.
String? _accountLabel(dynamic raw) {
  if (raw is! Map) return null;
  final code = raw['code']?.toString().trim() ?? '';
  final name = raw['name']?.toString().trim() ?? '';
  if (code.isEmpty && name.isEmpty) return null;
  if (code.isEmpty) return name;
  if (name.isEmpty) return code;
  return '$code · $name';
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

  /// Nombre legible de la cuenta de gasto ("6101-01 Sueldos"), resuelto en la
  /// misma consulta que la línea. Sin esto el respaldo sólo podía mostrar un
  /// UUID, que no le sirve a nadie para cuadrar con Contabilidad.
  final String? salaryAccountLabel;
  // New Strict Payment Fields
  final String? paymentMethodId;
  final String? paymentAccountId;
  final double cashPaid;
  final double advancesApplied;
  final double settledAmount;
  final double balance;
  final List<PayrollSettlementEvidence> settlementEvidence;

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
    this.salaryAccountLabel,
    this.paymentMethodId,
    this.paymentAccountId,
    this.cashPaid = 0,
    this.advancesApplied = 0,
    this.settledAmount = 0,
    double? balance,
    this.settlementEvidence = const [],
  }) : balance = balance ?? totalAmount;

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
    String? salaryAccountLabel,
    String? paymentMethodId,
    String? paymentAccountId,
    double? cashPaid,
    double? advancesApplied,
    double? settledAmount,
    double? balance,
    List<PayrollSettlementEvidence>? settlementEvidence,
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
      salaryAccountLabel: salaryAccountLabel ?? this.salaryAccountLabel,
      paymentMethodId: paymentMethodId ?? this.paymentMethodId,
      paymentAccountId: paymentAccountId ?? this.paymentAccountId,
      cashPaid: cashPaid ?? this.cashPaid,
      advancesApplied: advancesApplied ?? this.advancesApplied,
      settledAmount: settledAmount ?? this.settledAmount,
      balance: balance ?? this.balance,
      settlementEvidence: settlementEvidence ?? this.settlementEvidence,
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
      salaryAccountLabel: _accountLabel(map['salary_account']),
      paymentMethodId: map['payment_method_id'],
      paymentAccountId: map['payment_account_id'],
      cashPaid: (map['cash_paid'] as num?)?.toDouble() ?? 0,
      advancesApplied: (map['advances_applied'] as num?)?.toDouble() ?? 0,
      settledAmount: (map['settled_amount'] as num?)?.toDouble() ?? 0,
      balance: (map['balance'] as num?)?.toDouble(),
      settlementEvidence: (map['settlement_evidence'] as List<dynamic>?)
              ?.whereType<Map>()
              .map(
                (row) => PayrollSettlementEvidence.fromMap(
                  Map<String, dynamic>.from(row),
                ),
              )
              .toList(growable: false) ??
          const [],
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

class EmployeeAdvance {
  const EmployeeAdvance({
    required this.id,
    required this.employeeId,
    required this.amount,
    required this.amountApplied,
    required this.paidAt,
    DateTime? paidCivilDate,
    required this.status,
    this.paymentMethodId,
    this.paymentAccountId,
    this.reference,
    this.notes,
    this.reasonCode,
    this.reasonExplanation,
    this.workEndedOn,
  }) : paidCivilDate = paidCivilDate ?? paidAt;

  final String id;
  final String employeeId;
  final double amount;
  final double amountApplied;
  final DateTime paidAt;

  /// Calendar date of the advance in the tenant's authoritative timezone.
  ///
  /// Use this for payroll-period eligibility. [paidAt] remains the underlying
  /// audit instant.
  final DateTime paidCivilDate;
  final String status;
  final String? paymentMethodId;
  final String? paymentAccountId;
  final String? reference;

  /// Sólo el ORIGEN del anticipo. Con `v3` el motivo dejó de viajar acá.
  final String? notes;

  /// Motivo estructurado. **Nulo en asientos legacy** (anteriores a `v3`):
  /// esa nulabilidad es el dato, no un descuido — distingue «no tiene motivo
  /// registrado» de «tiene uno y dice esto».
  final PayrollAdvanceReasonCode? reasonCode;

  /// Lo que el operador escribió al entregar el dinero.
  final String? reasonExplanation;

  /// Último día trabajado; sólo viaja con `shortWorkweek`.
  final DateTime? workEndedOn;

  /// Qué mostrar como motivo, en orden de verdad: la explicación del operador
  /// primero y el respaldo legacy sólo si no hay ninguna. `reference` es la
  /// referencia bancaria y no es un motivo, así que nunca gana.
  String? get displayReason {
    final explanation = reasonExplanation?.trim();
    if (explanation != null && explanation.isNotEmpty) return explanation;
    final legacyNotes = notes?.trim();
    if (legacyNotes != null && legacyNotes.isNotEmpty) return legacyNotes;
    return null;
  }

  double get availableAmount => (amount - amountApplied).clamp(0, amount);

  factory EmployeeAdvance.fromMap(Map<String, dynamic> map) {
    final paidAt = DateTime.parse(map['paid_at'] as String);
    final paidCivilDateText = map['paid_civil_date']?.toString();
    return EmployeeAdvance(
      id: map['id'] as String,
      employeeId: map['employee_id'] as String,
      amount: (map['amount'] as num).toDouble(),
      amountApplied: (map['amount_applied'] as num?)?.toDouble() ?? 0,
      paidAt: paidAt,
      paidCivilDate: paidCivilDateText == null
          ? null
          : DateTime.tryParse(paidCivilDateText),
      status: map['status'] as String? ?? 'open',
      paymentMethodId: map['payment_method_id'] as String?,
      paymentAccountId: map['payment_account_id'] as String?,
      reference: map['reference'] as String?,
      notes: map['notes'] as String?,
      // `getOpenEmployeeAdvances` ya trae estas tres columnas desde `v3`; el
      // modelo las descartaba, así que el composer seguía mostrando `notes`
      // —el origen— bajo el rótulo de motivo. Se parsean tolerando el legacy:
      // un asiento viejo simplemente no las trae.
      reasonCode: _parseAdvanceReasonCode(map['reason_code']),
      reasonExplanation: map['reason_explanation'] as String?,
      workEndedOn: _parseAdvanceDay(map['work_ended_on']),
    );
  }

  static PayrollAdvanceReasonCode? _parseAdvanceReasonCode(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    // Un código desconocido NO revienta la lista: el ledger sigue siendo
    // legible y el motivo cae al respaldo. Reventar acá dejaría al operador
    // sin ver sus anticipos por un valor que ni siquiera necesita.
    try {
      return PayrollAdvanceReasonCode.parse(text);
    } on FormatException {
      return null;
    }
  }

  static DateTime? _parseAdvanceDay(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text);
  }
}

/// Una línea del asiento contable real que dejó un pago de sueldo.
///
/// Se lee de `journal_lines`, NO del campo `payment_account_id` del pago: ese
/// campo está nulo en los 78 pagos de sueldo de producción, mientras que el
/// asiento existe y cuadra en los 78. Presentar el campo como si fuera el
/// asiento hacía que la app declarara "no quedó registrada" sobre una
/// contabilidad sana.
class PayrollJournalLine {
  const PayrollJournalLine({
    required this.accountCode,
    required this.accountName,
    required this.debit,
    required this.credit,
  });

  final String accountCode;
  final String accountName;
  final double debit;
  final double credit;

  bool get isDebit => debit > 0.01;

  factory PayrollJournalLine.fromMap(Map<String, dynamic> map) {
    return PayrollJournalLine(
      accountCode: map['account_code']?.toString() ?? '',
      accountName: map['account_name']?.toString() ?? '',
      debit: (map['debit_amount'] as num?)?.toDouble() ?? 0,
      credit: (map['credit_amount'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// El asiento completo de un pago, con su número para poder ir a buscarlo.
class PayrollJournalEntry {
  const PayrollJournalEntry({
    required this.entryNumber,
    required this.lines,
  });

  final String entryNumber; // "AC-01910"
  final List<PayrollJournalLine> lines;

  bool get balances {
    final debit = lines.fold<double>(0, (s, l) => s + l.debit);
    final credit = lines.fold<double>(0, (s, l) => s + l.credit);
    return (debit - credit).abs() < 0.01;
  }
}
