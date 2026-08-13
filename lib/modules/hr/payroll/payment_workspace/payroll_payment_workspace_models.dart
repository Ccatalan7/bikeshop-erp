import '../../models/payroll_statement_reconciliation.dart';

enum PayrollPaymentWorkspaceMode { single, batch }

enum PayrollPaymentLegKind { payment, advance }

enum PayrollAdditionalConceptType {
  expenseReimbursement,
  workCompensation,
  otherEmployeePayable,
}

/// Defines whether a separate accounting concept redistributes the payroll
/// amount already owed or increases what will be paid to the worker.
enum PayrollAdditionalConceptDisposition {
  includedInPayrollTotal,
  additional,
}

enum PayrollPaymentValidationCode {
  noSettlement,
  amountNotPositive,
  missingPaymentMethod,
  missingPaymentAccount,
  missingPaymentDate,
  paymentReferenceRequired,
  paymentMethodUnavailable,
  paymentAccountMismatch,
  statementEvidenceRequiresTransfer,
  statementEvidenceAccountMismatch,
  missingAdvance,
  advanceUnavailable,
  advanceAmountExceeded,
  duplicateLegId,
  salaryBalanceExceeded,
  evidenceAmountExceeded,
  conceptAmountNotPositive,
  conceptDescriptionMissing,
  conceptAccountMissing,
  conceptFundingMismatch,
  unsupportedAdditionalConcepts,
}

enum PayrollPaymentSaveRetryPolicy { sameOperation, newOperation }

class PayrollPaymentWeekApprovalRequest {
  const PayrollPaymentWeekApprovalRequest({
    required this.voucherId,
    required this.expectedReconciliationVersion,
  });

  final String voucherId;
  final int expectedReconciliationVersion;
}

class PayrollPaymentWeekApprovalResult {
  const PayrollPaymentWeekApprovalResult({
    required this.voucherId,
    required this.reconciliationVersion,
  });

  final String voucherId;
  final int reconciliationVersion;
}

typedef PayrollPaymentWorkspaceHandoff = Future<void> Function(
  PayrollPaymentWorkspaceRequest request,
);

class PayrollPaymentMethodOption {
  const PayrollPaymentMethodOption({
    required this.methodId,
    required this.label,
    required this.code,
    required this.accountId,
    this.accountLabel,
    this.requiresReference = false,
    this.isActive = true,
  });

  factory PayrollPaymentMethodOption.fromMap(Map<String, dynamic> map) {
    final methodId = map['id']?.toString().trim() ?? '';
    final label = map['name']?.toString().trim();
    final code = map['code']?.toString().trim() ?? '';
    final accountId = map['account_id']?.toString().trim() ?? '';
    return PayrollPaymentMethodOption(
      methodId: methodId,
      label: label == null || label.isEmpty ? code : label,
      code: code,
      accountId: accountId,
      accountLabel: map['account_name']?.toString().trim(),
      requiresReference: map['requires_reference'] == true,
      isActive: map['is_active'] != false,
    );
  }

  final String methodId;
  final String label;
  final String code;
  final String accountId;
  final String? accountLabel;
  final bool requiresReference;
  final bool isActive;
}

class PayrollExpenseAccountOption {
  const PayrollExpenseAccountOption({
    required this.accountId,
    required this.label,
  });

  factory PayrollExpenseAccountOption.fromMap(Map<String, dynamic> map) {
    final code = map['code']?.toString().trim() ?? '';
    final name = map['name']?.toString().trim() ?? '';
    return PayrollExpenseAccountOption(
      accountId: map['id']?.toString().trim() ?? '',
      label: <String>[
        if (code.isNotEmpty) code,
        if (name.isNotEmpty) name,
      ].join(' · '),
    );
  }

  final String accountId;
  final String label;
}

class PayrollAdvanceOption {
  const PayrollAdvanceOption({
    required this.advanceId,
    required this.label,
    required this.availableAmountClp,
    this.employeeId,
    this.paidDate,
    this.reference,
    this.isAvailable = true,
  });

  factory PayrollAdvanceOption.fromMap(Map<String, dynamic> map) {
    final rawAmount = map['available_amount'] ??
        map['availableAmount'] ??
        map['amount_available'] ??
        map['amount'];
    return PayrollAdvanceOption(
      advanceId: map['id']?.toString().trim() ?? '',
      employeeId: (map['employee_id'] ?? map['employeeId'])?.toString().trim(),
      label: map['reason_explanation']?.toString().trim().isNotEmpty == true
          ? map['reason_explanation'].toString().trim()
          : map['reason']?.toString().trim().isNotEmpty == true
              ? map['reason'].toString().trim()
              : 'Anticipo',
      availableAmountClp: _clpInt(rawAmount),
      paidDate: _civilDateFromDynamic(map['paid_at'] ?? map['paid_date']),
      reference: map['reference']?.toString().trim(),
      isAvailable: map['status'] == null ||
          const <String>{'open', 'partially_applied'}
              .contains(map['status'].toString().trim().toLowerCase()),
    );
  }

  final String advanceId;
  final String? employeeId;
  final String label;
  final int availableAmountClp;
  final PayrollCivilDate? paidDate;
  final String? reference;
  final bool isAvailable;
}

/// Structured evidence retained from the statement. It deliberately contains
/// no source bytes and no raw page OCR text.
class PayrollOcrStatementEvidence {
  const PayrollOcrStatementEvidence({
    required this.sourceRowId,
    required this.fingerprint,
    required this.ordinal,
    required this.direction,
    required this.amountClp,
    required this.description,
    this.pageNumber,
    this.lineStart,
    this.lineEnd,
    this.occurrence,
    this.bookingDate,
    this.beneficiaryObserved,
    this.documentReference,
    this.warningCodes = const <String>[],
    this.suggestedErpAccountId,
    int? availableAmountClp,
  }) : availableAmountClp = availableAmountClp ?? amountClp;

  final String sourceRowId;
  final String fingerprint;
  final int ordinal;
  final int? pageNumber;
  final int? lineStart;
  final int? lineEnd;
  final int? occurrence;
  final PayrollCivilDate? bookingDate;
  final PayrollStatementMovementDirection direction;
  final int amountClp;
  final int availableAmountClp;
  final String description;
  final String? beneficiaryObserved;
  final String? documentReference;
  final List<String> warningCodes;
  final String? suggestedErpAccountId;

  String get allocationKey =>
      fingerprint.trim().isNotEmpty ? fingerprint.trim() : sourceRowId.trim();
}

class PayrollOcrStatementSource {
  PayrollOcrStatementSource({
    required this.filename,
    required this.fileSha256,
    required this.operationKey,
    required this.pageCount,
    required this.extractionKind,
    required this.sourceType,
    required this.accountFingerprint,
    required List<PayrollOcrStatementEvidence> evidenceRows,
    this.statementStartDate,
    this.statementEndDate,
    this.documentDate,
    this.suggestedErpAccountId,
  }) : evidenceRows = List<PayrollOcrStatementEvidence>.unmodifiable(
          evidenceRows,
        );

  final String filename;
  final String fileSha256;
  final String operationKey;
  final int pageCount;
  final String extractionKind;
  final String sourceType;
  final String accountFingerprint;
  final PayrollCivilDate? statementStartDate;
  final PayrollCivilDate? statementEndDate;
  final PayrollCivilDate? documentDate;
  final String? suggestedErpAccountId;
  final List<PayrollOcrStatementEvidence> evidenceRows;

  PayrollOcrStatementEvidence? evidenceBySourceRowId(String sourceRowId) {
    for (final evidence in evidenceRows) {
      if (evidence.sourceRowId == sourceRowId) return evidence;
    }
    return null;
  }
}

class PayrollOcrPaymentCandidate {
  const PayrollOcrPaymentCandidate({
    required this.candidateId,
    required this.evidence,
    this.reasons = const <String>[],
    this.safeUniqueExactMatch = false,
    this.selectedForPrefill = false,
    this.suggestedPaymentMethodId,
    this.suggestedPaymentAccountId,
  });

  final String candidateId;
  final PayrollOcrStatementEvidence evidence;
  final List<String> reasons;
  final bool safeUniqueExactMatch;
  final bool selectedForPrefill;
  final String? suggestedPaymentMethodId;
  final String? suggestedPaymentAccountId;
}

class PayrollPaymentTarget {
  PayrollPaymentTarget({
    String? targetId,
    required this.voucherId,
    required this.voucherLineId,
    required this.employeeId,
    required this.employeeName,
    required this.periodStart,
    required this.periodEnd,
    required this.salaryBalanceClp,
    int? salaryTotalClp,
    required this.reconciliationVersion,
    this.voucherStatus = 'confirmed',
    this.preferredPaymentMethodId,
    List<PayrollOcrPaymentCandidate> ocrCandidates = const [],
    List<PayrollAdvanceOption> availableAdvances = const [],
  })  : targetId = targetId ?? '$voucherId:$voucherLineId',
        salaryTotalClp = salaryTotalClp ?? salaryBalanceClp,
        ocrCandidates = List<PayrollOcrPaymentCandidate>.unmodifiable(
          ocrCandidates,
        ),
        availableAdvances = List<PayrollAdvanceOption>.unmodifiable(
          availableAdvances,
        ) {
    if (this.targetId.trim().isEmpty ||
        voucherId.trim().isEmpty ||
        voucherLineId.trim().isEmpty ||
        employeeId.trim().isEmpty) {
      throw ArgumentError('Payroll payment target identities cannot be empty.');
    }
    if (salaryBalanceClp < 0 || this.salaryTotalClp < salaryBalanceClp) {
      throw ArgumentError('Payroll salary totals are inconsistent.');
    }
  }

  final String targetId;
  final String voucherId;
  final String voucherLineId;
  final String employeeId;
  final String employeeName;
  final PayrollCivilDate periodStart;
  final PayrollCivilDate periodEnd;
  final int salaryTotalClp;
  final int salaryBalanceClp;
  final int reconciliationVersion;
  final String voucherStatus;
  final String? preferredPaymentMethodId;
  final List<PayrollOcrPaymentCandidate> ocrCandidates;
  final List<PayrollAdvanceOption> availableAdvances;

  PayrollPaymentTarget copyWith({
    int? salaryBalanceClp,
    int? reconciliationVersion,
    String? voucherStatus,
  }) {
    return PayrollPaymentTarget(
      targetId: targetId,
      voucherId: voucherId,
      voucherLineId: voucherLineId,
      employeeId: employeeId,
      employeeName: employeeName,
      periodStart: periodStart,
      periodEnd: periodEnd,
      salaryBalanceClp: salaryBalanceClp ?? this.salaryBalanceClp,
      salaryTotalClp: salaryTotalClp,
      reconciliationVersion:
          reconciliationVersion ?? this.reconciliationVersion,
      voucherStatus: voucherStatus ?? this.voucherStatus,
      preferredPaymentMethodId: preferredPaymentMethodId,
      ocrCandidates: ocrCandidates,
      availableAdvances: availableAdvances,
    );
  }
}

class PayrollPaymentWeekGroup {
  PayrollPaymentWeekGroup({
    required this.voucherId,
    required this.periodStart,
    required this.periodEnd,
    required List<PayrollPaymentTarget> targets,
  }) : targets = List<PayrollPaymentTarget>.unmodifiable(targets);

  final String voucherId;
  final PayrollCivilDate periodStart;
  final PayrollCivilDate periodEnd;
  final List<PayrollPaymentTarget> targets;
}

class PayrollPaymentWorkspaceRequest {
  PayrollPaymentWorkspaceRequest._({
    required this.mode,
    required List<PayrollPaymentTarget> targets,
    required List<PayrollPaymentMethodOption> paymentMethods,
    this.ocrSource,
  })  : targets = List<PayrollPaymentTarget>.unmodifiable(targets),
        paymentMethods = List<PayrollPaymentMethodOption>.unmodifiable(
          paymentMethods,
        ) {
    if (targets.isEmpty ||
        (mode == PayrollPaymentWorkspaceMode.single && targets.length != 1)) {
      throw ArgumentError('Payment workspace target count is invalid.');
    }
    final targetIds = targets.map((target) => target.targetId).toSet();
    if (targetIds.length != targets.length) {
      throw ArgumentError('Payment workspace target IDs must be unique.');
    }
    if (mode == PayrollPaymentWorkspaceMode.single && ocrSource != null) {
      throw ArgumentError(
          'The individual payment workspace has no OCR source.');
    }
  }

  factory PayrollPaymentWorkspaceRequest.single({
    required PayrollPaymentTarget target,
    List<PayrollPaymentMethodOption> paymentMethods = const [],
  }) {
    return PayrollPaymentWorkspaceRequest._(
      mode: PayrollPaymentWorkspaceMode.single,
      targets: <PayrollPaymentTarget>[target],
      paymentMethods: paymentMethods,
    );
  }

  factory PayrollPaymentWorkspaceRequest.batch({
    required List<PayrollPaymentTarget> targets,
    List<PayrollPaymentMethodOption> paymentMethods = const [],
    PayrollOcrStatementSource? ocrSource,
  }) {
    return PayrollPaymentWorkspaceRequest._(
      mode: PayrollPaymentWorkspaceMode.batch,
      targets: targets,
      paymentMethods: paymentMethods,
      ocrSource: ocrSource,
    );
  }

  final PayrollPaymentWorkspaceMode mode;
  final List<PayrollPaymentTarget> targets;
  final List<PayrollPaymentMethodOption> paymentMethods;
  final PayrollOcrStatementSource? ocrSource;

  PayrollPaymentTarget? targetById(String targetId) {
    for (final target in targets) {
      if (target.targetId == targetId) return target;
    }
    return null;
  }

  List<PayrollPaymentWeekGroup> get groups {
    final grouped = <String, List<PayrollPaymentTarget>>{};
    for (final target in targets) {
      grouped.putIfAbsent(target.voucherId, () => []).add(target);
    }
    final result = <PayrollPaymentWeekGroup>[
      for (final entry in grouped.entries)
        PayrollPaymentWeekGroup(
          voucherId: entry.key,
          periodStart: entry.value.first.periodStart,
          periodEnd: entry.value.first.periodEnd,
          targets: [...entry.value]..sort((left, right) {
              final name = left.employeeName.compareTo(right.employeeName);
              return name != 0
                  ? name
                  : left.voucherLineId.compareTo(right.voucherLineId);
            }),
        ),
    ];
    result.sort((left, right) {
      final end = right.periodEnd.compareTo(left.periodEnd);
      if (end != 0) return end;
      final start = right.periodStart.compareTo(left.periodStart);
      if (start != 0) return start;
      return right.voucherId.compareTo(left.voucherId);
    });
    return List<PayrollPaymentWeekGroup>.unmodifiable(result);
  }
}

class PayrollPaymentLeg {
  const PayrollPaymentLeg._({
    required this.legId,
    required this.kind,
    required this.amountClp,
    this.paymentMethodId,
    this.paymentAccountId,
    this.paymentDate,
    this.reference,
    this.notes,
    this.advanceId,
    this.ocrEvidence,
  });

  const PayrollPaymentLeg.payment({
    required String legId,
    required int amountClp,
    String? paymentMethodId,
    String? paymentAccountId,
    PayrollCivilDate? paymentDate,
    String? reference,
    String? notes,
    PayrollOcrStatementEvidence? ocrEvidence,
  }) : this._(
          legId: legId,
          kind: PayrollPaymentLegKind.payment,
          amountClp: amountClp,
          paymentMethodId: paymentMethodId,
          paymentAccountId: paymentAccountId,
          paymentDate: paymentDate,
          reference: reference,
          notes: notes,
          ocrEvidence: ocrEvidence,
        );

  const PayrollPaymentLeg.advance({
    required String legId,
    required String advanceId,
    required int amountClp,
  }) : this._(
          legId: legId,
          kind: PayrollPaymentLegKind.advance,
          amountClp: amountClp,
          advanceId: advanceId,
        );

  final String legId;
  final PayrollPaymentLegKind kind;
  final int amountClp;
  final String? paymentMethodId;
  final String? paymentAccountId;
  final PayrollCivilDate? paymentDate;
  final String? reference;
  final String? notes;
  final String? advanceId;
  final PayrollOcrStatementEvidence? ocrEvidence;
}

class PayrollAdditionalConcept {
  PayrollAdditionalConcept({
    required this.conceptId,
    required this.type,
    required this.description,
    required this.amountClp,
    required this.expenseAccountId,
    this.disposition =
        PayrollAdditionalConceptDisposition.includedInPayrollTotal,
    this.evidenceReference,
    List<PayrollPaymentLeg> paymentLegs = const [],
  }) : paymentLegs = List<PayrollPaymentLeg>.unmodifiable(paymentLegs);

  final String conceptId;
  final PayrollAdditionalConceptType type;
  final String description;
  final int amountClp;
  final String expenseAccountId;
  final PayrollAdditionalConceptDisposition disposition;
  final String? evidenceReference;
  final List<PayrollPaymentLeg> paymentLegs;

  PayrollAdditionalConcept copyWith({
    PayrollAdditionalConceptType? type,
    String? description,
    int? amountClp,
    String? expenseAccountId,
    PayrollAdditionalConceptDisposition? disposition,
    String? evidenceReference,
    List<PayrollPaymentLeg>? paymentLegs,
  }) {
    return PayrollAdditionalConcept(
      conceptId: conceptId,
      type: type ?? this.type,
      description: description ?? this.description,
      amountClp: amountClp ?? this.amountClp,
      expenseAccountId: expenseAccountId ?? this.expenseAccountId,
      disposition: disposition ?? this.disposition,
      evidenceReference: evidenceReference ?? this.evidenceReference,
      paymentLegs: paymentLegs ?? this.paymentLegs,
    );
  }
}

class PayrollPaymentValidationIssue {
  const PayrollPaymentValidationIssue({
    required this.code,
    required this.message,
    this.legId,
    this.conceptId,
    this.evidenceKey,
  });

  final PayrollPaymentValidationCode code;
  final String message;
  final String? legId;
  final String? conceptId;
  final String? evidenceKey;
}

class PayrollPaymentTargetValidation {
  PayrollPaymentTargetValidation({
    required this.targetId,
    required this.salaryAppliedClp,
    required this.includedConceptsTotalClp,
    required this.payrollCoverageClp,
    required this.payrollRemainingClp,
    required this.remainingClp,
    required this.paymentTotalClp,
    required this.advancesTotalClp,
    required this.additionalConceptsTotalClp,
    required this.additionalConceptsFundedClp,
    required this.additionalConceptsAdditiveTotalClp,
    required this.totalObligationClp,
    required this.appliedTotalClp,
    required List<PayrollPaymentValidationIssue> issues,
  }) : issues = List<PayrollPaymentValidationIssue>.unmodifiable(issues);

  final String targetId;
  final int salaryAppliedClp;
  final int includedConceptsTotalClp;
  final int payrollCoverageClp;
  final int payrollRemainingClp;
  final int remainingClp;
  final int paymentTotalClp;
  final int advancesTotalClp;
  final int additionalConceptsTotalClp;
  final int additionalConceptsFundedClp;
  final int additionalConceptsAdditiveTotalClp;
  final int totalObligationClp;
  final int appliedTotalClp;
  final List<PayrollPaymentValidationIssue> issues;

  bool get isValid => issues.isEmpty;
}

class PayrollPaymentTargetDraft {
  PayrollPaymentTargetDraft({
    required this.target,
    required List<PayrollPaymentLeg> salaryLegs,
    required List<PayrollAdditionalConcept> additionalConcepts,
    required this.operationKey,
    required this.isDirty,
    required this.isSaved,
    required this.additionalConceptsSupported,
  })  : salaryLegs = List<PayrollPaymentLeg>.unmodifiable(salaryLegs),
        additionalConcepts = List<PayrollAdditionalConcept>.unmodifiable(
          additionalConcepts,
        );

  final PayrollPaymentTarget target;
  final List<PayrollPaymentLeg> salaryLegs;
  final List<PayrollAdditionalConcept> additionalConcepts;
  final String operationKey;
  final bool isDirty;
  final bool isSaved;
  final bool additionalConceptsSupported;

  int get paymentTotalClp => _paymentLegs
      .where((leg) => leg.kind == PayrollPaymentLegKind.payment)
      .fold(0, (sum, leg) => sum + leg.amountClp);

  int get advancesTotalClp => salaryLegs
      .where((leg) => leg.kind == PayrollPaymentLegKind.advance)
      .fold(0, (sum, leg) => sum + leg.amountClp);

  int get salaryAppliedClp =>
      salaryLegs.fold(0, (sum, leg) => sum + leg.amountClp);

  int get additionalConceptsTotalClp => additionalConcepts.fold(
        0,
        (sum, concept) => sum + concept.amountClp,
      );

  int get includedConceptsTotalClp => additionalConcepts
      .where(
        (concept) =>
            concept.disposition ==
            PayrollAdditionalConceptDisposition.includedInPayrollTotal,
      )
      .fold(0, (sum, concept) => sum + concept.amountClp);

  int get additionalConceptsAdditiveTotalClp => additionalConcepts
      .where(
        (concept) =>
            concept.disposition ==
            PayrollAdditionalConceptDisposition.additional,
      )
      .fold(0, (sum, concept) => sum + concept.amountClp);

  int get additionalConceptsFundedClp => additionalConcepts.fold(
        0,
        (sum, concept) =>
            sum +
            concept.paymentLegs.fold<int>(
              0,
              (conceptSum, leg) => conceptSum + leg.amountClp,
            ),
      );

  /// Portion of the original payroll obligation covered by salary legs and
  /// concepts explicitly included in that same total.
  int get payrollCoverageClp => salaryAppliedClp + includedConceptsTotalClp;

  int get payrollRemainingClp {
    final remaining = target.salaryBalanceClp - payrollCoverageClp;
    return remaining > 0 ? remaining : 0;
  }

  /// Total owed to the worker after concepts that genuinely add money.
  int get totalObligationClp =>
      target.salaryBalanceClp + additionalConceptsAdditiveTotalClp;

  /// Money actually allocated across salary, advances and concept funding.
  int get appliedTotalClp => salaryAppliedClp + additionalConceptsFundedClp;

  int get coverageTotalClp => appliedTotalClp;

  int get remainingClp {
    final remaining = totalObligationClp - appliedTotalClp;
    return remaining > 0 ? remaining : 0;
  }

  bool get hasUnsupportedConcepts =>
      additionalConcepts.isNotEmpty && !additionalConceptsSupported;

  Iterable<PayrollPaymentLeg> get _paymentLegs sync* {
    yield* salaryLegs;
    for (final concept in additionalConcepts) {
      yield* concept.paymentLegs;
    }
  }
}

class PayrollPaymentTargetSaveCommand {
  PayrollPaymentTargetSaveCommand({
    required this.target,
    required this.operationKey,
    required List<PayrollPaymentLeg> salaryLegs,
    required List<Map<String, dynamic>> salarySplits,
    required List<PayrollAdditionalConcept> additionalConcepts,
  })  : salaryLegs = List<PayrollPaymentLeg>.unmodifiable(salaryLegs),
        salarySplits = List<Map<String, dynamic>>.unmodifiable(
          salarySplits.map(Map<String, dynamic>.unmodifiable),
        ),
        additionalConcepts = List<PayrollAdditionalConcept>.unmodifiable(
          additionalConcepts,
        );

  final PayrollPaymentTarget target;
  final String operationKey;
  final List<PayrollPaymentLeg> salaryLegs;
  final List<Map<String, dynamic>> salarySplits;
  final List<PayrollAdditionalConcept> additionalConcepts;

  PayrollPaymentTargetSaveCommand copyWith({
    PayrollPaymentTarget? target,
  }) {
    return PayrollPaymentTargetSaveCommand(
      target: target ?? this.target,
      operationKey: operationKey,
      salaryLegs: salaryLegs,
      salarySplits: salarySplits,
      additionalConcepts: additionalConcepts,
    );
  }
}

class PayrollPaymentWorkspaceSaveException implements Exception {
  const PayrollPaymentWorkspaceSaveException(
    this.message, {
    this.retryPolicy = PayrollPaymentSaveRetryPolicy.sameOperation,
  });

  final String message;
  final PayrollPaymentSaveRetryPolicy retryPolicy;

  @override
  String toString() => message;
}

/// The payment writer returned successfully, so its transaction may already
/// be committed, but the client could not prove the shape of the receipt.
///
/// This is deliberately not a retryable save failure. Callers must fence the
/// operation key and direct the operator to the server-owned payroll state.
class PayrollPaymentCommittedUnverifiedException implements Exception {
  const PayrollPaymentCommittedUnverifiedException({
    required this.operationKey,
  });

  final String operationKey;

  @override
  String toString() =>
      'El servidor registró el pago, pero no pudimos verificar su comprobante.';
}

int _clpInt(dynamic value) {
  if (value is num) return value.round();
  return num.tryParse(value?.toString() ?? '')?.round() ?? 0;
}

PayrollCivilDate? _civilDateFromDynamic(dynamic value) {
  if (value is PayrollCivilDate) return value;
  if (value is DateTime) {
    return PayrollCivilDate(value.year, value.month, value.day);
  }
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  return parsed == null
      ? null
      : PayrollCivilDate(parsed.year, parsed.month, parsed.day);
}
