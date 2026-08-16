import '../../models/payroll_statement_reconciliation.dart';
import '../../models/payroll_voucher.dart';
import '../../services/payroll_reconciliation_service.dart';
import '../../services/payroll_statement_extraction_service.dart';
import '../../widgets/payroll_reconciliation_row.dart';
import 'payroll_payment_workspace_models.dart';

PayrollPaymentWorkspaceRequest payrollPaymentWorkspaceRequestForLine({
  required PayrollVoucher voucher,
  required PayrollVoucherLine line,
  required List<Map<String, dynamic>> paymentMethods,
  required List<EmployeeAdvance> openAdvances,
}) {
  return PayrollPaymentWorkspaceRequest.single(
    target: _targetForVoucherLine(
      voucher: voucher,
      line: line,
      openAdvances: openAdvances,
    ),
    paymentMethods: _paymentMethods(paymentMethods),
  );
}

/// Builds the all-visible payment table for one selected payroll week.
///
/// Paid/excluded/zero-balance workers never enter the command. Every remaining
/// line keeps its persisted employee/method identity and is independently
/// editable in the shared batch workspace before the atomic save.
PayrollPaymentWorkspaceRequest payrollPaymentWorkspaceRequestForWeek({
  required PayrollVoucher voucher,
  required List<PayrollVoucherLine> lines,
  required List<Map<String, dynamic>> paymentMethods,
  required List<EmployeeAdvance> openAdvances,
}) {
  final targets = lines
      .where((line) => line.isIncluded && line.balance > 0.01)
      .map(
        (line) => _targetForVoucherLine(
          voucher: voucher,
          line: line,
          openAdvances: openAdvances,
        ),
      )
      .toList(growable: false);
  if (targets.isEmpty) {
    throw ArgumentError('The payroll week has no pending payment targets.');
  }
  return PayrollPaymentWorkspaceRequest.batch(
    targets: targets,
    paymentMethods: _paymentMethods(paymentMethods),
  );
}

PayrollPaymentTarget _targetForVoucherLine({
  required PayrollVoucher voucher,
  required PayrollVoucherLine line,
  required List<EmployeeAdvance> openAdvances,
}) {
  final voucherId = voucher.id?.trim() ?? '';
  final lineId = line.id?.trim() ?? '';
  if (voucherId.isEmpty || lineId.isEmpty) {
    throw ArgumentError('The payment target must already be persisted.');
  }
  final start = PayrollCivilDate(
    voucher.periodStart.year,
    voucher.periodStart.month,
    voucher.periodStart.day,
  );
  final end = PayrollCivilDate(
    voucher.periodEnd.year,
    voucher.periodEnd.month,
    voucher.periodEnd.day,
  );
  return PayrollPaymentTarget(
    targetId: lineId,
    voucherId: voucherId,
    voucherLineId: lineId,
    employeeId: line.employeeId,
    employeeName: line.employeeName,
    periodStart: start,
    periodEnd: end,
    salaryBalanceClp: line.balance.round(),
    salaryTotalClp: line.totalAmount.round(),
    reconciliationVersion: voucher.reconciliationVersion,
    voucherStatus: voucher.status.name,
    preferredPaymentMethodId: line.paymentMethodId,
    availableAdvances: _advancesForTarget(
      openAdvances,
      employeeId: line.employeeId,
      periodEnd: end,
    ),
  );
}

List<PayrollPaymentMethodOption> _paymentMethods(
  List<Map<String, dynamic>> paymentMethods,
) {
  return paymentMethods
      .map(PayrollPaymentMethodOption.fromMap)
      .where((method) =>
          method.isActive &&
          method.methodId.isNotEmpty &&
          method.accountId.isNotEmpty)
      .toList(growable: false);
}

/// Translates the in-memory OCR/read model into the only object the payment
/// workspace accepts. No payment decision is made here: selected rows remain
/// evidence/prefill and every monetary leg is still editable downstream.
PayrollPaymentWorkspaceRequest payrollPaymentWorkspaceRequestFromStatement({
  required PayrollStatementPreparedDraft draft,
  required Set<String> selectedTargetIds,
  required Map<String, Set<String>> selectedEvidenceIdsByTargetId,
  String? suggestedErpAccountId,
}) {
  final methods = draft.paymentMethods
      .map(PayrollPaymentMethodOption.fromMap)
      .where((method) =>
          method.isActive &&
          method.methodId.isNotEmpty &&
          method.accountId.isNotEmpty)
      .toList(growable: false);
  final statementAccountId = _statementAccountId(
    methods,
    suggestedErpAccountId: suggestedErpAccountId,
  );
  final evidenceBySourceId = _statementEvidence(
    draft,
    suggestedErpAccountId: statementAccountId,
  );
  final targets = <PayrollPaymentTarget>[];

  for (final result in draft.reconciliation.lineResults) {
    final line = result.voucherLine;
    if (!line.isPending || line.pendingAmountClp <= 0) {
      continue;
    }
    final voucher = draft.vouchersById[line.voucherId];
    if (voucher == null) continue;
    final voucherLine = _voucherLine(voucher, line.lineId);
    final employeeName = result.employee?.displayName ??
        voucherLine?.employeeName.trim() ??
        'Persona sin ficha';
    final selectedEvidence = selectedTargetIds.contains(line.lineId)
        ? selectedEvidenceIdsByTargetId[line.lineId] ?? const <String>{}
        : const <String>{};
    final statementMethod = _statementPaymentMethod(
      line: line,
      methods: methods,
      suggestedErpAccountId: statementAccountId,
    );
    final candidatesBySourceId = <String, PayrollOcrPaymentCandidate>{};
    for (final candidate in result.evaluatedCandidates) {
      final row = candidate.statementRow;
      final evidence = evidenceBySourceId[row.sourceRowId];
      if (evidence == null ||
          !row.isOutgoingCandidate ||
          !row.hasCompleteStructuredEvidence ||
          draft.priorDecisionIdsBySourceRowId.containsKey(row.sourceRowId) ||
          candidate.reasons
              .contains(PayrollCandidateReason.dateOutsideWindow)) {
        continue;
      }
      final safeExact = candidate.isEligible &&
          candidate.amountVarianceClp == 0 &&
          candidate.confidence == PayrollMatchConfidence.high &&
          evidence.warningCodes.isEmpty;
      candidatesBySourceId.putIfAbsent(
        row.sourceRowId,
        () => PayrollOcrPaymentCandidate(
          candidateId: row.sourceRowId,
          evidence: evidence,
          reasons: candidate.reasons
              .map(payrollCandidateReasonLabel)
              .toList(growable: false),
          safeUniqueExactMatch: safeExact,
          selectedForPrefill: selectedEvidence.contains(row.sourceRowId),
          suggestedPaymentMethodId: statementMethod?.methodId,
          suggestedPaymentAccountId: statementMethod?.accountId,
        ),
      );
    }

    targets.add(
      PayrollPaymentTarget(
        targetId: line.lineId,
        voucherId: line.voucherId,
        voucherLineId: line.lineId,
        employeeId: line.employeeId,
        employeeName: employeeName,
        periodStart: line.periodStart,
        periodEnd: line.periodEnd,
        salaryBalanceClp: line.pendingAmountClp,
        salaryTotalClp:
            (voucherLine?.totalAmount ?? line.pendingAmountClp).round(),
        reconciliationVersion:
            draft.expectedVoucherVersionsById[line.voucherId] ??
                voucher.reconciliationVersion,
        voucherStatus: voucher.status.name,
        preferredPaymentMethodId: line.paymentMethodId,
        ocrCandidates: candidatesBySourceId.values.toList(growable: false),
        availableAdvances: _advancesForTarget(
          draft.openAdvances,
          employeeId: line.employeeId,
          periodEnd: line.periodEnd,
        ),
      ),
    );
  }

  return PayrollPaymentWorkspaceRequest.batch(
    targets: targets,
    paymentMethods: methods,
    ocrSource: PayrollOcrStatementSource(
      filename: draft.filename,
      fileSha256: draft.extraction.fileSha256,
      operationKey: draft.operationKey,
      pageCount: draft.extraction.pages.length,
      extractionKind: draft.extraction.method.name,
      sourceType: _statementSourceType(draft),
      accountFingerprint: draft.accountFingerprint,
      statementStartDate: _statementDates(draft).firstOrNull,
      statementEndDate: draft.documentDate ?? _statementDates(draft).lastOrNull,
      documentDate: draft.documentDate,
      suggestedErpAccountId: statementAccountId,
      evidenceRows: evidenceBySourceId.values.toList(growable: false),
    ),
  );
}

PayrollPaymentMethodOption? _statementPaymentMethod({
  required PayrollReconciliationVoucherLine line,
  required List<PayrollPaymentMethodOption> methods,
  required String? suggestedErpAccountId,
}) {
  final transferMethods = methods
      .where((method) => method.code.trim().toLowerCase() == 'transfer')
      .toList(growable: false);
  final lineMethodId = line.paymentMethodId?.trim() ?? '';
  for (final method in transferMethods) {
    if (lineMethodId.isNotEmpty && method.methodId == lineMethodId) {
      return method;
    }
  }
  final accountId = suggestedErpAccountId?.trim() ?? '';
  if (accountId.isNotEmpty) {
    final matching = transferMethods
        .where((method) => method.accountId == accountId)
        .toList(growable: false);
    if (matching.length == 1) return matching.single;
  }
  return transferMethods.length == 1 ? transferMethods.single : null;
}

String? _statementAccountId(
  List<PayrollPaymentMethodOption> methods, {
  required String? suggestedErpAccountId,
}) {
  final transferMethods = methods
      .where((method) => method.code.trim().toLowerCase() == 'transfer')
      .toList(growable: false);
  final suggested = suggestedErpAccountId?.trim() ?? '';
  if (suggested.isNotEmpty &&
      transferMethods.any((method) => method.accountId == suggested)) {
    return suggested;
  }
  final accountIds = transferMethods.map((method) => method.accountId).toSet();
  return accountIds.length == 1 ? accountIds.single : null;
}

String _statementSourceType(PayrollStatementPreparedDraft draft) {
  if (draft.extraction.inputKind == PayrollStatementInputKind.image) {
    return 'image_ocr';
  }
  return draft.extraction.method ==
          PayrollStatementExtractionMethod.embeddedPdfText
      ? 'pdf_text'
      : 'pdf_ocr';
}

Map<String, PayrollOcrStatementEvidence> _statementEvidence(
  PayrollStatementPreparedDraft draft, {
  String? suggestedErpAccountId,
}) {
  final occurrenceByBase = <String, int>{};
  final result = <String, PayrollOcrStatementEvidence>{};
  for (final row in draft.parseResult.rows) {
    final amount = switch (row.direction) {
      PayrollStatementMovementDirection.outgoing => row.debitAmountClp,
      PayrollStatementMovementDirection.incoming => row.creditAmountClp,
      PayrollStatementMovementDirection.unknown => null,
    };
    if (amount == null ||
        amount <= 0 ||
        row.bookingDate == null ||
        row.direction == PayrollStatementMovementDirection.unknown ||
        row.description.trim().isEmpty) {
      continue;
    }
    final occurrenceBase = <String>[
      row.bookingDate?.toString() ?? '',
      row.direction.name,
      amount.toString(),
      row.normalizedDescription,
      normalizePayrollReconciliationText(row.beneficiaryObserved ?? ''),
      normalizePayrollReconciliationText(row.documentNumber ?? ''),
    ].join('|');
    final occurrence = occurrenceByBase.update(
      occurrenceBase,
      (current) => current + 1,
      ifAbsent: () => 1,
    );
    result[row.sourceRowId] = PayrollOcrStatementEvidence(
      sourceRowId: row.sourceRowId,
      fingerprint: draft.rowFingerprintsBySourceRowId[row.sourceRowId] ?? '',
      ordinal: row.evidence.sourceRowNumber,
      pageNumber: row.evidence.startPageNumber,
      lineStart: row.evidence.startLineNumber,
      lineEnd: row.evidence.endLineNumber,
      occurrence: occurrence,
      bookingDate: row.bookingDate,
      direction: row.direction,
      amountClp: amount,
      description: row.description,
      beneficiaryObserved: row.beneficiaryObserved,
      documentReference: row.documentNumber,
      warningCodes: <String>[
        ...row.parseWarningCodes.where(
          (code) => code != 'out_of_statement_range',
        ),
        if (!row.hasCompleteStructuredEvidence) 'incomplete_evidence',
      ],
      suggestedErpAccountId: suggestedErpAccountId,
    );
  }
  return result;
}

PayrollVoucherLine? _voucherLine(PayrollVoucher voucher, String lineId) {
  for (final line in voucher.lines) {
    if (line.id == lineId) return line;
  }
  return null;
}

List<PayrollAdvanceOption> _advancesForTarget(
  List<EmployeeAdvance> advances, {
  required String employeeId,
  required PayrollCivilDate periodEnd,
}) {
  final end = DateTime(periodEnd.year, periodEnd.month, periodEnd.day, 23, 59);
  return <PayrollAdvanceOption>[
    for (final advance in advances)
      if (advance.employeeId == employeeId &&
          advance.availableAmount > 0.01 &&
          !advance.paidCivilDate.isAfter(end))
        PayrollAdvanceOption(
          advanceId: advance.id,
          label: advance.displayReason ?? 'Anticipo',
          availableAmountClp: advance.availableAmount.round(),
          paidDate: PayrollCivilDate(
            advance.paidCivilDate.year,
            advance.paidCivilDate.month,
            advance.paidCivilDate.day,
          ),
          reference: advance.reference,
        ),
  ];
}

List<PayrollCivilDate> _statementDates(PayrollStatementPreparedDraft draft) {
  final dates = draft.parseResult.rows
      .map((row) => row.bookingDate)
      .whereType<PayrollCivilDate>()
      .toList(growable: false)
    ..sort();
  return dates;
}
