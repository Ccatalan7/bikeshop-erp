enum PayrollAdvanceLedgerStatus {
  open,
  partiallyApplied,
  applied,
  voided;

  static PayrollAdvanceLedgerStatus parse(Object? value) {
    return switch (value?.toString()) {
      'open' => PayrollAdvanceLedgerStatus.open,
      'partially_applied' => PayrollAdvanceLedgerStatus.partiallyApplied,
      'applied' => PayrollAdvanceLedgerStatus.applied,
      'voided' => PayrollAdvanceLedgerStatus.voided,
      final value => throw FormatException(
          'Unknown employee advance status: $value',
        ),
    };
  }
}

enum PayrollAdvanceReasonCode {
  requestedAdvance,
  shortWorkweek,
  other;

  static PayrollAdvanceReasonCode parse(Object? value) {
    return switch (value?.toString()) {
      'requested_advance' => PayrollAdvanceReasonCode.requestedAdvance,
      'short_workweek' => PayrollAdvanceReasonCode.shortWorkweek,
      'other' => PayrollAdvanceReasonCode.other,
      final value => throw FormatException(
          'Unknown employee advance reason: $value',
        ),
    };
  }

  String get wireValue => switch (this) {
        PayrollAdvanceReasonCode.requestedAdvance => 'requested_advance',
        PayrollAdvanceReasonCode.shortWorkweek => 'short_workweek',
        PayrollAdvanceReasonCode.other => 'other',
      };
}

class PayrollAdvanceReason {
  const PayrollAdvanceReason({
    required this.code,
    required this.explanation,
    this.workEndedOn,
  });

  final PayrollAdvanceReasonCode code;
  final String explanation;
  final DateTime? workEndedOn;

  factory PayrollAdvanceReason.fromMap(Object? value) {
    final map = _object(value, 'employee advance reason');
    final code = PayrollAdvanceReasonCode.parse(map['code']);
    final explanation = _requiredText(map, 'explanation');
    final workEndedOn = _optionalDateTime(map['work_ended_on']);
    if ((code == PayrollAdvanceReasonCode.shortWorkweek) !=
        (workEndedOn != null)) {
      throw const FormatException(
        'Employee advance work-ended date does not match its reason',
      );
    }
    return PayrollAdvanceReason(
      code: code,
      explanation: explanation,
      workEndedOn: workEndedOn,
    );
  }
}

class PayrollAdvanceOriginalEvidence {
  const PayrollAdvanceOriginalEvidence({
    required this.id,
    required this.appFileId,
    required this.fileName,
    required this.sizeBytes,
    required this.sha256,
    required this.storageObjectId,
    required this.storageObjectVersion,
    required this.storageObjectEtag,
    required this.createdAt,
    required this.createdBy,
    this.mimeType,
  });

  final String id;
  final String appFileId;
  final String fileName;
  final String? mimeType;
  final int sizeBytes;
  final String sha256;
  final String storageObjectId;
  final String storageObjectVersion;
  final String storageObjectEtag;
  final DateTime createdAt;
  final String createdBy;

  factory PayrollAdvanceOriginalEvidence.fromMap(Object? value) {
    final map = _object(value, 'employee advance original evidence');
    final sizeBytes = _requiredInt(map, 'size_bytes');
    final sha256 = _requiredText(map, 'sha256').toLowerCase();
    final storageObjectId = _requiredText(map, 'storage_object_id');
    final storageObjectVersion = _requiredText(map, 'storage_object_version');
    final storageObjectEtag = _requiredText(map, 'storage_object_etag');
    if (sizeBytes <= 0 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256) ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
        ).hasMatch(storageObjectId)) {
      throw const FormatException(
        'Invalid employee advance original evidence integrity metadata',
      );
    }
    return PayrollAdvanceOriginalEvidence(
      id: _requiredText(map, 'id'),
      appFileId: _requiredText(map, 'app_file_id'),
      fileName: _requiredText(map, 'file_name'),
      mimeType: _optionalText(map['mime_type']),
      sizeBytes: sizeBytes,
      sha256: sha256,
      storageObjectId: storageObjectId,
      storageObjectVersion: storageObjectVersion,
      storageObjectEtag: storageObjectEtag,
      createdAt: _requiredDateTime(map, 'created_at'),
      createdBy: _requiredText(map, 'created_by'),
    );
  }
}

enum PayrollAuditEvidenceSource {
  manual,
  statementReconciliation,
  legacy;

  static PayrollAuditEvidenceSource parse(Object? value) {
    return switch (value?.toString()) {
      'manual' => PayrollAuditEvidenceSource.manual,
      'statement_reconciliation' =>
        PayrollAuditEvidenceSource.statementReconciliation,
      'legacy' => PayrollAuditEvidenceSource.legacy,
      final value => throw FormatException(
          'Unknown payroll audit evidence source: $value',
        ),
    };
  }
}

enum PayrollHistoryStatus {
  paid,
  voided;

  static PayrollHistoryStatus parse(Object? value) {
    return switch (value?.toString()) {
      'paid' => PayrollHistoryStatus.paid,
      'voided' => PayrollHistoryStatus.voided,
      final value => throw FormatException(
          'Unknown payroll history status: $value',
        ),
    };
  }
}

class PayrollAuditActor {
  const PayrollAuditActor({this.id, this.name});

  final String? id;
  final String? name;

  factory PayrollAuditActor.fromMap(Object? value) {
    final map = _object(value, 'payroll audit actor');
    return PayrollAuditActor(
      id: _optionalText(map['id']),
      name: _optionalText(map['name']),
    );
  }
}

class PayrollPaymentMethodIdentity {
  const PayrollPaymentMethodIdentity({
    this.id,
    this.code,
    this.name,
  });

  final String? id;
  final String? code;
  final String? name;

  factory PayrollPaymentMethodIdentity.fromMap(Object? value) {
    final map = _object(value, 'payroll payment method identity');
    return PayrollPaymentMethodIdentity(
      id: _optionalText(map['id']),
      code: _optionalText(map['code']),
      name: _optionalText(map['name']),
    );
  }
}

class PayrollAccountIdentity {
  const PayrollAccountIdentity({
    required this.id,
    this.code,
    this.name,
  });

  final String id;
  final String? code;
  final String? name;

  factory PayrollAccountIdentity.fromMap(Object? value) {
    final map = _object(value, 'payroll account identity');
    return PayrollAccountIdentity(
      id: _requiredText(map, 'id'),
      code: _optionalText(map['code']),
      name: _optionalText(map['name']),
    );
  }
}

class PayrollAuditEvidence {
  const PayrollAuditEvidence({
    required this.source,
    this.operationId,
    this.operationKey,
    this.recordedAt,
    this.statementAllocationId,
    this.statementImportId,
    this.statementDecisionId,
  });

  final PayrollAuditEvidenceSource source;
  final String? operationId;
  final String? operationKey;
  final DateTime? recordedAt;
  final String? statementAllocationId;
  final String? statementImportId;
  final String? statementDecisionId;

  factory PayrollAuditEvidence.fromMap(Object? value) {
    final map = _object(value, 'payroll audit evidence');
    return PayrollAuditEvidence(
      source: PayrollAuditEvidenceSource.parse(map['source']),
      operationId: _optionalText(map['operation_id']),
      operationKey: _optionalText(map['operation_key']),
      recordedAt: _optionalDateTime(map['recorded_at']),
      statementAllocationId: _optionalText(map['statement_allocation_id']),
      statementImportId: _optionalText(map['statement_import_id']),
      statementDecisionId: _optionalText(map['statement_decision_id']),
    );
  }
}

class PayrollAdvanceAllocation {
  const PayrollAdvanceAllocation({
    required this.id,
    required this.amount,
    required this.appliedAt,
    required this.createdAt,
    required this.actor,
    required this.voucherId,
    required this.voucherNumber,
    required this.periodStart,
    required this.periodEnd,
    required this.voucherStatus,
    required this.voucherLineId,
    required this.voucherLineTotal,
    required this.evidence,
    this.periodLabel,
    this.employeeName,
    this.notes,
  });

  final String id;
  final double amount;
  final DateTime appliedAt;
  final DateTime createdAt;
  final PayrollAuditActor actor;
  final String voucherId;
  final String voucherNumber;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String? periodLabel;
  final String voucherStatus;
  final String voucherLineId;
  final String? employeeName;
  final double voucherLineTotal;
  final String? notes;
  final PayrollAuditEvidence evidence;

  factory PayrollAdvanceAllocation.fromMap(Object? value) {
    final map = _object(value, 'employee advance allocation');
    final voucher = _object(map['voucher'], 'allocation voucher');
    final line = _object(map['voucher_line'], 'allocation voucher line');
    return PayrollAdvanceAllocation(
      id: _requiredText(map, 'id'),
      amount: _requiredDouble(map, 'amount'),
      appliedAt: _requiredDateTime(map, 'applied_at'),
      createdAt: _requiredDateTime(map, 'created_at'),
      actor: PayrollAuditActor.fromMap(map['actor']),
      voucherId: _requiredText(voucher, 'id'),
      voucherNumber: _requiredText(voucher, 'voucher_number'),
      periodStart: _requiredDateTime(voucher, 'period_start'),
      periodEnd: _requiredDateTime(voucher, 'period_end'),
      periodLabel: _optionalText(voucher['period_label']),
      voucherStatus: _requiredText(voucher, 'status'),
      voucherLineId: _requiredText(line, 'id'),
      employeeName: _optionalText(line['employee_name']),
      voucherLineTotal: _requiredDouble(line, 'total_amount'),
      notes: _optionalText(map['notes']),
      evidence: PayrollAuditEvidence.fromMap(map['evidence']),
    );
  }
}

class PayrollAdvanceLedgerEntry {
  const PayrollAdvanceLedgerEntry({
    required this.id,
    required this.employeeId,
    required this.amount,
    required this.appliedAmount,
    required this.balanceAmount,
    required this.paidAt,
    required this.status,
    required this.paymentMethod,
    required this.actor,
    required this.fundingEvidence,
    required this.createdAt,
    required this.updatedAt,
    required this.allocations,
    this.paymentAccount,
    this.reference,
    this.notes,
    this.reason,
    this.originalEvidence,
  });

  final String id;
  final String employeeId;
  final double amount;
  final double appliedAmount;
  final double balanceAmount;
  final DateTime paidAt;
  final PayrollAdvanceLedgerStatus status;
  final PayrollPaymentMethodIdentity paymentMethod;
  final PayrollAccountIdentity? paymentAccount;
  final String? reference;
  final String? notes;
  final PayrollAdvanceReason? reason;
  final PayrollAdvanceOriginalEvidence? originalEvidence;
  final PayrollAuditActor actor;
  final PayrollAuditEvidence fundingEvidence;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<PayrollAdvanceAllocation> allocations;

  factory PayrollAdvanceLedgerEntry.fromMap(Object? value) {
    final map = _object(value, 'employee advance ledger entry');
    return PayrollAdvanceLedgerEntry(
      id: _requiredText(map, 'id'),
      employeeId: _requiredText(map, 'employee_id'),
      amount: _requiredDouble(map, 'amount'),
      appliedAmount: _requiredDouble(map, 'applied_amount'),
      balanceAmount: _requiredDouble(map, 'balance_amount'),
      paidAt: _requiredDateTime(map, 'paid_at'),
      status: PayrollAdvanceLedgerStatus.parse(map['status']),
      paymentMethod:
          PayrollPaymentMethodIdentity.fromMap(map['payment_method']),
      paymentAccount: map['payment_account'] == null
          ? null
          : PayrollAccountIdentity.fromMap(map['payment_account']),
      reference: _optionalText(map['reference']),
      notes: _optionalText(map['notes']),
      reason: map['reason'] == null
          ? null
          : PayrollAdvanceReason.fromMap(map['reason']),
      originalEvidence: map['original_evidence'] == null
          ? null
          : PayrollAdvanceOriginalEvidence.fromMap(map['original_evidence']),
      actor: PayrollAuditActor.fromMap(map['actor']),
      fundingEvidence: PayrollAuditEvidence.fromMap(map['funding_evidence']),
      createdAt: _requiredDateTime(map, 'created_at'),
      updatedAt: _requiredDateTime(map, 'updated_at'),
      allocations: _array(map['allocations'], 'advance allocations')
          .map(PayrollAdvanceAllocation.fromMap)
          .toList(growable: false),
    );
  }
}

class PayrollAdvanceLedgerTotals {
  const PayrollAdvanceLedgerTotals({
    required this.deliveredAmount,
    required this.appliedAmount,
    required this.balanceAmount,
    required this.recordCount,
  });

  final double deliveredAmount;
  final double appliedAmount;
  final double balanceAmount;
  final int recordCount;

  factory PayrollAdvanceLedgerTotals.fromMap(Object? value) {
    final map = _object(value, 'employee advance ledger totals');
    return PayrollAdvanceLedgerTotals(
      deliveredAmount: _requiredDouble(map, 'delivered_amount'),
      appliedAmount: _requiredDouble(map, 'applied_amount'),
      balanceAmount: _requiredDouble(map, 'balance_amount'),
      recordCount: _requiredInt(map, 'record_count'),
    );
  }
}

class PayrollAdvanceLedgerCursor {
  const PayrollAdvanceLedgerCursor({
    required this.paidAt,
    required this.id,
  });

  final DateTime paidAt;
  final String id;

  factory PayrollAdvanceLedgerCursor.fromMap(Object? value) {
    final map = _object(value, 'employee advance ledger cursor');
    return PayrollAdvanceLedgerCursor(
      paidAt: _requiredDateTime(map, 'paid_at'),
      id: _requiredText(map, 'id'),
    );
  }
}

class PayrollAdvanceLedgerPage {
  const PayrollAdvanceLedgerPage({
    required this.employeeId,
    required this.totals,
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  final String employeeId;
  final PayrollAdvanceLedgerTotals totals;
  final List<PayrollAdvanceLedgerEntry> items;
  final bool hasMore;
  final PayrollAdvanceLedgerCursor? nextCursor;

  factory PayrollAdvanceLedgerPage.fromMap(Map<String, dynamic> map) {
    _requireContractVersion(map, supported: const <int>{1, 2});
    final nextCursorValue = map['next_cursor'];
    final page = PayrollAdvanceLedgerPage(
      employeeId: _requiredText(map, 'employee_id'),
      totals: PayrollAdvanceLedgerTotals.fromMap(map['totals']),
      items: _array(map['items'], 'employee advance ledger items')
          .map(PayrollAdvanceLedgerEntry.fromMap)
          .toList(growable: false),
      hasMore: _requiredBool(map, 'has_more'),
      nextCursor: nextCursorValue == null
          ? null
          : PayrollAdvanceLedgerCursor.fromMap(nextCursorValue),
    );
    if (page.hasMore != (page.nextCursor != null)) {
      throw const FormatException(
        'Employee advance ledger cursor does not match has_more',
      );
    }
    return page;
  }
}

class PayrollHistoryCursor {
  const PayrollHistoryCursor({
    required this.periodEnd,
    required this.id,
  });

  final DateTime periodEnd;
  final String id;

  factory PayrollHistoryCursor.fromMap(Object? value) {
    final map = _object(value, 'payroll history cursor');
    return PayrollHistoryCursor(
      periodEnd: _requiredDateTime(map, 'period_end'),
      id: _requiredText(map, 'id'),
    );
  }
}

class PayrollHistoryHeader {
  const PayrollHistoryHeader({
    required this.id,
    required this.voucherNumber,
    required this.periodStart,
    required this.periodEnd,
    required this.totalHours,
    required this.totalAmount,
    required this.employeeCount,
    required this.status,
    required this.paidBy,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    required this.reconciliationVersion,
    this.periodLabel,
    this.paidAt,
    this.notes,
  });

  final String id;
  final String voucherNumber;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String? periodLabel;
  final double totalHours;
  final double totalAmount;
  final int employeeCount;
  final PayrollHistoryStatus status;
  final DateTime? paidAt;
  final PayrollAuditActor paidBy;
  final String? notes;
  final PayrollAuditActor createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int reconciliationVersion;

  factory PayrollHistoryHeader.fromMap(Object? value) {
    final map = _object(value, 'payroll history header');
    return PayrollHistoryHeader(
      id: _requiredText(map, 'id'),
      voucherNumber: _requiredText(map, 'voucher_number'),
      periodStart: _requiredDateTime(map, 'period_start'),
      periodEnd: _requiredDateTime(map, 'period_end'),
      periodLabel: _optionalText(map['period_label']),
      totalHours: _requiredDouble(map, 'total_hours'),
      totalAmount: _requiredDouble(map, 'total_amount'),
      employeeCount: _requiredInt(map, 'employee_count'),
      status: PayrollHistoryStatus.parse(map['status']),
      paidAt: _optionalDateTime(map['paid_at']),
      paidBy: PayrollAuditActor.fromMap(map['paid_by']),
      notes: _optionalText(map['notes']),
      createdBy: PayrollAuditActor.fromMap(map['created_by']),
      createdAt: _requiredDateTime(map, 'created_at'),
      updatedAt: _requiredDateTime(map, 'updated_at'),
      reconciliationVersion: _requiredInt(map, 'reconciliation_version'),
    );
  }
}

class PayrollHistoryPage {
  const PayrollHistoryPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  final List<PayrollHistoryHeader> items;
  final bool hasMore;
  final PayrollHistoryCursor? nextCursor;

  factory PayrollHistoryPage.fromMap(Map<String, dynamic> map) {
    _requireContractVersion(map);
    final nextCursorValue = map['next_cursor'];
    final page = PayrollHistoryPage(
      items: _array(map['items'], 'payroll history items')
          .map(PayrollHistoryHeader.fromMap)
          .toList(growable: false),
      hasMore: _requiredBool(map, 'has_more'),
      nextCursor: nextCursorValue == null
          ? null
          : PayrollHistoryCursor.fromMap(nextCursorValue),
    );
    if (page.hasMore != (page.nextCursor != null)) {
      throw const FormatException(
        'Payroll history cursor does not match has_more',
      );
    }
    return page;
  }
}

void _requireContractVersion(
  Map<String, dynamic> map, {
  Set<int> supported = const <int>{1},
}) {
  if (!supported.contains(map['contract_version'])) {
    throw FormatException(
      'Unsupported payroll read model version: ${map['contract_version']}',
    );
  }
}

Map<String, dynamic> _object(Object? value, String context) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map(
      (key, item) => MapEntry(key.toString(), item),
    );
  }
  throw FormatException('Expected object for $context');
}

List<Object?> _array(Object? value, String context) {
  if (value is List) return value.cast<Object?>();
  throw FormatException('Expected array for $context');
}

String _requiredText(Map<String, dynamic> map, String key) {
  final value = _optionalText(map[key]);
  if (value == null) throw FormatException('Missing payroll field: $key');
  return value;
}

String? _optionalText(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

double _requiredDouble(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is num) return value.toDouble();
  final parsed = double.tryParse(value?.toString() ?? '');
  if (parsed == null) {
    throw FormatException('Invalid payroll number: $key');
  }
  return parsed;
}

int _requiredInt(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is int) return value;
  if (value is num && value == value.roundToDouble()) {
    return value.toInt();
  }
  final parsed = int.tryParse(value?.toString() ?? '');
  if (parsed == null) {
    throw FormatException('Invalid payroll integer: $key');
  }
  return parsed;
}

bool _requiredBool(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is bool) return value;
  throw FormatException('Invalid payroll boolean: $key');
}

DateTime _requiredDateTime(Map<String, dynamic> map, String key) {
  final value = _optionalDateTime(map[key]);
  if (value == null) throw FormatException('Invalid payroll date: $key');
  return value;
}

DateTime? _optionalDateTime(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}
