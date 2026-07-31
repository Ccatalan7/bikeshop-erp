import '../models/payroll_statement_reconciliation.dart';

/// Produces deterministic, review-only matches between statement debits and
/// pending payroll voucher lines.
///
/// A suggested match is never an instruction to post a payment. Callers must
/// keep the proposal and any non-zero variance visible until a human confirms
/// its disposition.
class PayrollStatementMatcher {
  final PayrollReconciliationConfig config;

  const PayrollStatementMatcher({
    this.config = const PayrollReconciliationConfig(),
  });

  PayrollStatementReconciliationResult match({
    required List<PayrollStatementRow> statementRows,
    required List<PayrollReconciliationEmployee> employees,
    required List<PayrollReconciliationVoucherLine> voucherLines,
  }) {
    final employeesById = _uniqueEmployeesById(employees);
    _validateUniqueLineIds(voucherLines);
    _validateUniqueRowIds(statementRows);

    final evaluationsByLineId =
        <String, List<PayrollReconciliationCandidate>>{};
    final ineligibleReasonsByLineId = <String, List<PayrollLineMatchReason>>{};

    for (final line in voucherLines) {
      final employee = employeesById[line.employeeId];
      final ineligibleReasons = _ineligibleReasons(line, employee);
      if (ineligibleReasons.isNotEmpty) {
        ineligibleReasonsByLineId[line.lineId] = ineligibleReasons;
        evaluationsByLineId[line.lineId] =
            const <PayrollReconciliationCandidate>[];
        continue;
      }

      final evaluations = <PayrollReconciliationCandidate>[];
      for (final row in statementRows) {
        if (!row.isOutgoingCandidate) continue;
        final beneficiaryMatch = _matchBeneficiary(row, employee!);
        if (beneficiaryMatch == null) continue;
        evaluations.add(
          _evaluateCandidate(
            row: row,
            line: line,
            beneficiaryMatch: beneficiaryMatch,
          ),
        );
      }
      evaluations.sort(_compareCandidates);
      evaluationsByLineId[line.lineId] = evaluations;
    }

    final eligibleUseCountByRowId = <String, int>{};
    for (final evaluations in evaluationsByLineId.values) {
      for (final candidate in evaluations.where((value) => value.isEligible)) {
        eligibleUseCountByRowId.update(
          candidate.statementRow.sourceRowId,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }

    final lineResults = <PayrollReconciliationLineResult>[];
    for (final line in voucherLines) {
      final employee = employeesById[line.employeeId];
      final ineligibleReasons = ineligibleReasonsByLineId[line.lineId];
      if (ineligibleReasons != null) {
        lineResults.add(
          PayrollReconciliationLineResult(
            voucherLine: line,
            employee: employee,
            status: PayrollLineMatchStatus.ineligible,
            evaluatedCandidates: const [],
            proposedMatch: null,
            reasons: ineligibleReasons,
          ),
        );
        continue;
      }

      final originalEvaluations = evaluationsByLineId[line.lineId]!;
      final eligibleForLine = originalEvaluations
          .where((candidate) => candidate.isEligible)
          .toList();
      final hasMultipleTransactions = eligibleForLine.length > 1;
      final finalEvaluations = originalEvaluations.map((candidate) {
        if (!candidate.isEligible) return candidate;

        final reasons = <PayrollCandidateReason>[...candidate.reasons];
        if (hasMultipleTransactions) {
          reasons.add(PayrollCandidateReason.multipleTransactionsForLine);
        }
        if ((eligibleUseCountByRowId[candidate.statementRow.sourceRowId] ?? 0) >
            1) {
          reasons.add(
            PayrollCandidateReason.transactionMatchesMultipleLines,
          );
        }
        return candidate.copyWith(reasons: reasons);
      }).toList(growable: false)
        ..sort(_compareCandidates);

      final finalEligible =
          finalEvaluations.where((candidate) => candidate.isEligible).toList();
      if (finalEligible.isEmpty) {
        lineResults.add(
          PayrollReconciliationLineResult(
            voucherLine: line,
            employee: employee,
            status: PayrollLineMatchStatus.unmatched,
            evaluatedCandidates: finalEvaluations,
            proposedMatch: null,
            reasons: [
              originalEvaluations.isEmpty
                  ? PayrollLineMatchReason.noBeneficiaryMatch
                  : PayrollLineMatchReason.noEligibleTransaction,
            ],
          ),
        );
        continue;
      }

      final lineReasons = <PayrollLineMatchReason>[];
      if (finalEligible.length > 1) {
        lineReasons.add(
          PayrollLineMatchReason.multipleTransactionsForLine,
        );
      }
      final rowIsShared = finalEligible.any(
        (candidate) =>
            (eligibleUseCountByRowId[candidate.statementRow.sourceRowId] ?? 0) >
            1,
      );
      if (rowIsShared) {
        lineReasons.add(
          PayrollLineMatchReason.transactionMatchesMultipleLines,
        );
      }

      if (lineReasons.isNotEmpty) {
        lineResults.add(
          PayrollReconciliationLineResult(
            voucherLine: line,
            employee: employee,
            status: PayrollLineMatchStatus.needsReview,
            evaluatedCandidates: finalEvaluations,
            proposedMatch: null,
            reasons: lineReasons,
          ),
        );
        continue;
      }

      lineResults.add(
        PayrollReconciliationLineResult(
          voucherLine: line,
          employee: employee,
          status: PayrollLineMatchStatus.suggested,
          evaluatedCandidates: finalEvaluations,
          proposedMatch: finalEligible.single,
          reasons: const [PayrollLineMatchReason.uniqueCandidate],
        ),
      );
    }

    // Foreign proof: an outgoing row is foreign only when NO tenant employee
    // is named in its description or observed beneficiary, by primary name or
    // configured alias. Line eligibility is irrelevant here on purpose: a
    // movement naming a worker whose obligation is settled, cash-paid or
    // absent from this batch is still worker-named and must stay under human
    // review instead of being absorbed automatically.
    final foreignOutgoingSourceRowIds = <String>{
      for (final row in statementRows)
        if (row.isOutgoingCandidate &&
            !employeesById.values
                .any((employee) => _namesEmployee(row, employee)))
          row.sourceRowId,
    };

    return PayrollStatementReconciliationResult(
      statementRows: statementRows,
      lineResults: lineResults,
      foreignOutgoingSourceRowIds: foreignOutgoingSourceRowIds,
    );
  }

  PayrollReconciliationCandidate _evaluateCandidate({
    required PayrollStatementRow row,
    required PayrollReconciliationVoucherLine line,
    required _BeneficiaryMatch beneficiaryMatch,
  }) {
    final transactionAmount = row.outgoingAmountClp!;
    final variance = transactionAmount - line.pendingAmountClp;
    final absoluteVariance = variance.abs();
    final tolerance = config.toleranceFor(line.pendingAmountClp);
    final daysAfterPeriodEnd = row.bookingDate == null
        ? null
        : line.periodEnd.daysUntil(row.bookingDate!);
    final daysAfterPeriodStart = row.bookingDate == null
        ? null
        : line.periodStart.daysUntil(row.bookingDate!);
    final dateIsEligible = daysAfterPeriodStart != null &&
        daysAfterPeriodStart >= 0 &&
        daysAfterPeriodEnd != null &&
        daysAfterPeriodEnd <= config.paymentWindowDays;
    // Tolerance is intentionally asymmetric. A small positive variance may be
    // the shop's usual bank rounding and can be suggested for explicit review.
    // Any smaller debit is a possible partial payment, never a rounding match;
    // it must stay unmatched until an operator links it manually.
    final amountIsWithinTolerance = absoluteVariance <= tolerance;
    final amountIsEligible = variance >= 0 && amountIsWithinTolerance;
    final isEligible = dateIsEligible && amountIsEligible;

    final reasons = <PayrollCandidateReason>[
      PayrollCandidateReason.outgoingMovement,
      beneficiaryMatch.kind == PayrollBeneficiaryMatchKind.primaryName
          ? PayrollCandidateReason.primaryNameMatched
          : PayrollCandidateReason.configuredAliasMatched,
      PayrollCandidateReason.paymentMethodIsTransfer,
    ];
    if (daysAfterPeriodEnd == null) {
      reasons.add(PayrollCandidateReason.dateMissing);
    } else if (dateIsEligible) {
      reasons.add(PayrollCandidateReason.dateWithinWindow);
    } else {
      reasons.add(PayrollCandidateReason.dateOutsideWindow);
    }

    if (absoluteVariance == 0) {
      reasons.add(PayrollCandidateReason.amountExact);
    } else if (variance < 0) {
      reasons.add(PayrollCandidateReason.amountBelowPendingBalance);
      if (!amountIsWithinTolerance) {
        reasons.add(PayrollCandidateReason.amountOutsideTolerance);
      }
      reasons.add(PayrollCandidateReason.nonZeroVariance);
    } else if (amountIsWithinTolerance) {
      reasons.add(PayrollCandidateReason.amountWithinTolerance);
      reasons.add(PayrollCandidateReason.nonZeroVariance);
    } else {
      reasons.add(PayrollCandidateReason.amountOutsideTolerance);
    }

    return PayrollReconciliationCandidate(
      statementRow: row,
      voucherLine: line,
      beneficiaryMatchKind: beneficiaryMatch.kind,
      normalizedMatchedBeneficiary: beneficiaryMatch.normalizedValue,
      isEligible: isEligible,
      amountVarianceClp: variance,
      allowedToleranceClp: tolerance,
      daysAfterPeriodEnd: daysAfterPeriodEnd,
      score: _candidateScore(
        beneficiaryMatchKind: beneficiaryMatch.kind,
        daysAfterPeriodEnd: daysAfterPeriodEnd,
        absoluteVarianceClp: absoluteVariance,
        toleranceClp: tolerance,
      ),
      confidence: _candidateConfidence(
        isEligible: isEligible,
        daysAfterPeriodEnd: daysAfterPeriodEnd,
        absoluteVarianceClp: absoluteVariance,
      ),
      reasons: reasons,
    );
  }

  List<PayrollLineMatchReason> _ineligibleReasons(
    PayrollReconciliationVoucherLine line,
    PayrollReconciliationEmployee? employee,
  ) {
    if (employee == null) {
      return const [PayrollLineMatchReason.missingEmployee];
    }
    if (!line.isPending) {
      return const [PayrollLineMatchReason.lineIsNotPending];
    }
    if (line.pendingAmountClp <= 0) {
      return const [PayrollLineMatchReason.pendingAmountIsNotPositive];
    }
    if (line.paymentMethod == PayrollReconciliationPaymentMethod.cash) {
      return const [PayrollLineMatchReason.paymentMethodIsCash];
    }
    if (line.paymentMethod != PayrollReconciliationPaymentMethod.transfer) {
      return const [PayrollLineMatchReason.paymentMethodIsNotTransfer];
    }
    return const [];
  }
}

Map<String, PayrollReconciliationEmployee> _uniqueEmployeesById(
  List<PayrollReconciliationEmployee> employees,
) {
  final byId = <String, PayrollReconciliationEmployee>{};
  for (final employee in employees) {
    if (employee.employeeId.trim().isEmpty) {
      throw ArgumentError('Employee IDs must not be empty.');
    }
    if (byId.containsKey(employee.employeeId)) {
      throw ArgumentError(
        'Duplicate payroll reconciliation employee ID.',
      );
    }
    byId[employee.employeeId] = employee;
  }
  return byId;
}

void _validateUniqueLineIds(
  List<PayrollReconciliationVoucherLine> voucherLines,
) {
  final ids = <String>{};
  for (final line in voucherLines) {
    if (line.lineId.trim().isEmpty || !ids.add(line.lineId)) {
      throw ArgumentError(
        'Payroll reconciliation line IDs must be non-empty and unique.',
      );
    }
  }
}

void _validateUniqueRowIds(List<PayrollStatementRow> statementRows) {
  final ids = <String>{};
  for (final row in statementRows) {
    if (!ids.add(row.sourceRowId)) {
      throw ArgumentError(
        'Statement row evidence must identify each row uniquely.',
      );
    }
  }
}

/// Whether the row names [employee] anywhere the bank prints a beneficiary:
/// the movement description (what `_matchBeneficiary` reads) or the observed
/// beneficiary column, which some statements populate instead.
bool _namesEmployee(
  PayrollStatementRow row,
  PayrollReconciliationEmployee employee,
) {
  if (_matchBeneficiary(row, employee) != null) return true;
  final observed = row.beneficiaryObserved?.trim() ?? '';
  if (observed.isEmpty) return false;
  final haystack = normalizePayrollReconciliationText(observed);
  final primaryName = normalizePayrollReconciliationText(employee.displayName);
  if (_containsWholePhrase(haystack, primaryName)) return true;
  return employee.bankBeneficiaryAliases
      .map(normalizePayrollReconciliationText)
      .any((alias) => _containsWholePhrase(haystack, alias));
}

_BeneficiaryMatch? _matchBeneficiary(
  PayrollStatementRow row,
  PayrollReconciliationEmployee employee,
) {
  final primaryName = normalizePayrollReconciliationText(employee.displayName);
  if (_containsWholePhrase(row.normalizedDescription, primaryName)) {
    return _BeneficiaryMatch(
      kind: PayrollBeneficiaryMatchKind.primaryName,
      normalizedValue: primaryName,
    );
  }

  final normalizedAliases = employee.bankBeneficiaryAliases
      .map(normalizePayrollReconciliationText)
      .where((alias) => alias.isNotEmpty)
      .toSet()
      .toList()
    ..sort((left, right) {
      final lengthComparison = right.length.compareTo(left.length);
      return lengthComparison != 0 ? lengthComparison : left.compareTo(right);
    });
  for (final alias in normalizedAliases) {
    if (_containsWholePhrase(row.normalizedDescription, alias)) {
      return _BeneficiaryMatch(
        kind: PayrollBeneficiaryMatchKind.configuredAlias,
        normalizedValue: alias,
      );
    }
  }
  return null;
}

bool _containsWholePhrase(String normalizedHaystack, String normalizedNeedle) {
  if (normalizedNeedle.isEmpty) return false;
  return ' $normalizedHaystack '.contains(' $normalizedNeedle ');
}

int _candidateScore({
  required PayrollBeneficiaryMatchKind beneficiaryMatchKind,
  required int? daysAfterPeriodEnd,
  required int absoluteVarianceClp,
  required int toleranceClp,
}) {
  var score =
      beneficiaryMatchKind == PayrollBeneficiaryMatchKind.primaryName ? 25 : 22;
  score += 10;

  if (daysAfterPeriodEnd != null) {
    final dateScore = 25 - daysAfterPeriodEnd.abs() * 2;
    score += dateScore.clamp(0, 25);
  }

  if (absoluteVarianceClp == 0) {
    score += 40;
  } else if (absoluteVarianceClp <= toleranceClp && toleranceClp > 0) {
    score += (40 * (toleranceClp - absoluteVarianceClp) / toleranceClp).round();
  }
  return score.clamp(0, 100);
}

PayrollMatchConfidence _candidateConfidence({
  required bool isEligible,
  required int? daysAfterPeriodEnd,
  required int absoluteVarianceClp,
}) {
  if (!isEligible || daysAfterPeriodEnd == null) {
    return PayrollMatchConfidence.none;
  }
  if (daysAfterPeriodEnd.abs() <= 4 && absoluteVarianceClp <= 250) {
    return PayrollMatchConfidence.high;
  }
  if (daysAfterPeriodEnd.abs() <= 4) {
    return PayrollMatchConfidence.medium;
  }
  return PayrollMatchConfidence.low;
}

int _compareCandidates(
  PayrollReconciliationCandidate left,
  PayrollReconciliationCandidate right,
) {
  if (left.isEligible != right.isEligible) {
    return left.isEligible ? -1 : 1;
  }
  final scoreComparison = right.score.compareTo(left.score);
  if (scoreComparison != 0) return scoreComparison;

  final dateComparison = _compareNullableDates(
    left.statementRow.bookingDate,
    right.statementRow.bookingDate,
  );
  if (dateComparison != 0) return dateComparison;

  return left.statementRow.sourceRowId.compareTo(
    right.statementRow.sourceRowId,
  );
}

int _compareNullableDates(PayrollCivilDate? left, PayrollCivilDate? right) {
  if (left == null && right == null) return 0;
  if (left == null) return 1;
  if (right == null) return -1;
  return left.compareTo(right);
}

class _BeneficiaryMatch {
  final PayrollBeneficiaryMatchKind kind;
  final String normalizedValue;

  const _BeneficiaryMatch({
    required this.kind,
    required this.normalizedValue,
  });
}
