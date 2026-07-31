enum PayrollStatementMovementDirection {
  outgoing,
  incoming,
  unknown,
}

enum PayrollReconciliationPaymentMethod {
  transfer,
  cash,
  other,
}

enum PayrollBeneficiaryMatchKind {
  primaryName,
  configuredAlias,
}

enum PayrollMatchConfidence {
  none,
  low,
  medium,
  high,
}

enum PayrollLineMatchStatus {
  suggested,
  needsReview,
  unmatched,
  ineligible,
}

enum PayrollCandidateReason {
  outgoingMovement,
  primaryNameMatched,
  configuredAliasMatched,
  paymentMethodIsTransfer,
  dateWithinWindow,
  dateMissing,
  dateOutsideWindow,
  amountExact,
  amountWithinTolerance,
  amountBelowPendingBalance,
  amountOutsideTolerance,
  nonZeroVariance,
  multipleTransactionsForLine,
  transactionMatchesMultipleLines,
}

enum PayrollLineMatchReason {
  uniqueCandidate,
  missingEmployee,
  paymentMethodIsCash,
  paymentMethodIsNotTransfer,
  lineIsNotPending,
  pendingAmountIsNotPositive,
  noBeneficiaryMatch,
  noEligibleTransaction,
  multipleTransactionsForLine,
  transactionMatchesMultipleLines,
}

/// A calendar date with no time zone or time-of-day semantics.
///
/// Bank statement dates and payroll periods are Chilean civil dates. Keeping
/// their components explicit prevents an OCR date from shifting when a device
/// happens to run in another time zone.
class PayrollCivilDate implements Comparable<PayrollCivilDate> {
  final int year;
  final int month;
  final int day;

  const PayrollCivilDate(this.year, this.month, this.day)
      : assert(year > 0),
        assert(month >= DateTime.january && month <= DateTime.december),
        assert(day >= 1 && day <= 31);

  static bool isValid(int year, int month, int day) {
    if (year <= 0 ||
        month < DateTime.january ||
        month > DateTime.december ||
        day < 1) {
      return false;
    }

    return day <= _daysInMonth(year, month);
  }

  int daysUntil(PayrollCivilDate other) {
    return _daysFromCivil(other.year, other.month, other.day) -
        _daysFromCivil(year, month, day);
  }

  @override
  int compareTo(PayrollCivilDate other) {
    final yearComparison = year.compareTo(other.year);
    if (yearComparison != 0) return yearComparison;

    final monthComparison = month.compareTo(other.month);
    if (monthComparison != 0) return monthComparison;

    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) {
    return other is PayrollCivilDate &&
        other.year == year &&
        other.month == month &&
        other.day == day;
  }

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() {
    final monthText = month.toString().padLeft(2, '0');
    final dayText = day.toString().padLeft(2, '0');
    return '$year-$monthText-$dayText';
  }

  static int _daysInMonth(int year, int month) {
    const monthLengths = <int>[
      31,
      28,
      31,
      30,
      31,
      30,
      31,
      31,
      30,
      31,
      30,
      31,
    ];
    if (month == DateTime.february && _isLeapYear(year)) return 29;
    return monthLengths[month - 1];
  }

  static bool _isLeapYear(int year) {
    return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
  }

  // Gregorian calendar day number. This is integer civil-date arithmetic, not
  // a conversion through UTC or the device time zone.
  static int _daysFromCivil(int year, int month, int day) {
    var adjustedYear = year;
    if (month <= DateTime.february) adjustedYear -= 1;
    final era = adjustedYear ~/ 400;
    final yearOfEra = adjustedYear - era * 400;
    final adjustedMonth = month > DateTime.february ? month - 3 : month + 9;
    final dayOfYear = (153 * adjustedMonth + 2) ~/ 5 + day - 1;
    final dayOfEra =
        yearOfEra * 365 + yearOfEra ~/ 4 - yearOfEra ~/ 100 + dayOfYear;
    return era * 146097 + dayOfEra;
  }
}

class PayrollStatementRowEvidence {
  final int sourceRowNumber;
  final int startPageNumber;
  final int startLineNumber;
  final int endPageNumber;
  final int endLineNumber;

  const PayrollStatementRowEvidence({
    required this.sourceRowNumber,
    required this.startPageNumber,
    required this.startLineNumber,
    required this.endPageNumber,
    required this.endLineNumber,
  })  : assert(sourceRowNumber > 0),
        assert(startPageNumber > 0),
        assert(startLineNumber > 0),
        assert(endPageNumber >= startPageNumber),
        assert(endLineNumber > 0);

  String get sourceRowId {
    return 'p$startPageNumber-l$startLineNumber-r$sourceRowNumber';
  }
}

class PayrollStatementParseWarning {
  final String code;
  final String message;
  final PayrollStatementRowEvidence? evidence;

  const PayrollStatementParseWarning({
    required this.code,
    required this.message,
    this.evidence,
  });
}

class PayrollStatementRow {
  final PayrollCivilDate? bookingDate;
  final String description;
  final String normalizedDescription;
  final String? beneficiaryObserved;
  final String? documentNumber;
  final int? debitAmountClp;
  final int? creditAmountClp;
  final int? balanceAmountClp;
  final PayrollStatementMovementDirection direction;
  final PayrollStatementRowEvidence evidence;
  final List<String> parseWarningCodes;

  PayrollStatementRow({
    required this.bookingDate,
    required this.description,
    String? normalizedDescription,
    this.beneficiaryObserved,
    required this.documentNumber,
    required this.debitAmountClp,
    required this.creditAmountClp,
    required this.balanceAmountClp,
    required this.direction,
    required this.evidence,
    List<String> parseWarningCodes = const [],
  })  : normalizedDescription = normalizedDescription ??
            normalizePayrollReconciliationText(description),
        parseWarningCodes = List.unmodifiable(parseWarningCodes);

  String get sourceRowId => evidence.sourceRowId;

  bool get isOutgoingCandidate {
    return direction == PayrollStatementMovementDirection.outgoing &&
        debitAmountClp != null &&
        debitAmountClp! > 0;
  }

  int? get outgoingAmountClp {
    return isOutgoingCandidate ? debitAmountClp : null;
  }

  bool get hasCompleteStructuredEvidence {
    final amount = switch (direction) {
      PayrollStatementMovementDirection.outgoing => debitAmountClp,
      PayrollStatementMovementDirection.incoming => creditAmountClp,
      PayrollStatementMovementDirection.unknown => null,
    };
    return bookingDate != null &&
        direction != PayrollStatementMovementDirection.unknown &&
        amount != null &&
        amount > 0 &&
        description.trim().isNotEmpty;
  }
}

class PayrollBankStatementParseResult {
  final List<PayrollStatementRow> rows;
  final List<PayrollStatementParseWarning> warnings;

  PayrollBankStatementParseResult({
    required List<PayrollStatementRow> rows,
    List<PayrollStatementParseWarning> warnings = const [],
  })  : rows = List.unmodifiable(rows),
        warnings = List.unmodifiable(warnings);

  List<PayrollStatementRow> get outgoingCandidates {
    return List.unmodifiable(rows.where((row) => row.isOutgoingCandidate));
  }
}

class PayrollReconciliationEmployee {
  final String employeeId;
  final String displayName;
  final PayrollReconciliationPaymentMethod paymentMethod;
  final List<String> bankBeneficiaryAliases;

  PayrollReconciliationEmployee({
    required this.employeeId,
    required this.displayName,
    required this.paymentMethod,
    List<String> bankBeneficiaryAliases = const [],
  }) : bankBeneficiaryAliases = List.unmodifiable(bankBeneficiaryAliases);
}

class PayrollReconciliationVoucherLine {
  final String lineId;
  final String voucherId;
  final String employeeId;
  final PayrollCivilDate periodStart;
  final PayrollCivilDate periodEnd;
  final int pendingAmountClp;
  final PayrollReconciliationPaymentMethod paymentMethod;
  final String? paymentMethodId;
  final String? paymentAccountId;
  final bool isPending;

  const PayrollReconciliationVoucherLine({
    required this.lineId,
    required this.voucherId,
    required this.employeeId,
    required this.periodStart,
    required this.periodEnd,
    required this.pendingAmountClp,
    required this.paymentMethod,
    this.paymentMethodId,
    this.paymentAccountId,
    this.isPending = true,
  });
}

class PayrollReconciliationConfig {
  final int paymentWindowDays;
  final int minimumToleranceClp;
  final int maximumToleranceClp;

  /// Relative tolerance in basis points. One hundred basis points equals 1%.
  final int relativeToleranceBasisPoints;

  const PayrollReconciliationConfig({
    this.paymentWindowDays = 5,
    this.minimumToleranceClp = 1,
    this.maximumToleranceClp = 500,
    this.relativeToleranceBasisPoints = 100,
  })  : assert(paymentWindowDays >= 0),
        assert(minimumToleranceClp >= 0),
        assert(maximumToleranceClp >= minimumToleranceClp),
        assert(relativeToleranceBasisPoints >= 0);

  int toleranceFor(int pendingAmountClp) {
    final relativeTolerance =
        (pendingAmountClp.abs() * relativeToleranceBasisPoints + 9999) ~/ 10000;
    return relativeTolerance.clamp(
      minimumToleranceClp,
      maximumToleranceClp,
    );
  }
}

class PayrollReconciliationCandidate {
  final PayrollStatementRow statementRow;
  final PayrollReconciliationVoucherLine voucherLine;
  final PayrollBeneficiaryMatchKind beneficiaryMatchKind;
  final String normalizedMatchedBeneficiary;
  final bool isEligible;

  /// Bank debit minus the pending payroll amount. A positive value is an
  /// overpayment; a negative value is a possible partial payment. Both remain
  /// visible for an explicit human disposition.
  final int amountVarianceClp;
  final int allowedToleranceClp;
  final int? daysAfterPeriodEnd;
  final int score;
  final PayrollMatchConfidence confidence;
  final List<PayrollCandidateReason> reasons;

  PayrollReconciliationCandidate({
    required this.statementRow,
    required this.voucherLine,
    required this.beneficiaryMatchKind,
    required this.normalizedMatchedBeneficiary,
    required this.isEligible,
    required this.amountVarianceClp,
    required this.allowedToleranceClp,
    required this.daysAfterPeriodEnd,
    required this.score,
    required this.confidence,
    required List<PayrollCandidateReason> reasons,
  }) : reasons = List.unmodifiable(reasons);

  bool get requiresHumanConfirmation => true;

  PayrollReconciliationCandidate copyWith({
    List<PayrollCandidateReason>? reasons,
  }) {
    return PayrollReconciliationCandidate(
      statementRow: statementRow,
      voucherLine: voucherLine,
      beneficiaryMatchKind: beneficiaryMatchKind,
      normalizedMatchedBeneficiary: normalizedMatchedBeneficiary,
      isEligible: isEligible,
      amountVarianceClp: amountVarianceClp,
      allowedToleranceClp: allowedToleranceClp,
      daysAfterPeriodEnd: daysAfterPeriodEnd,
      score: score,
      confidence: confidence,
      reasons: reasons ?? this.reasons,
    );
  }
}

class PayrollReconciliationLineResult {
  final PayrollReconciliationVoucherLine voucherLine;
  final PayrollReconciliationEmployee? employee;
  final PayrollLineMatchStatus status;
  final List<PayrollReconciliationCandidate> evaluatedCandidates;
  final PayrollReconciliationCandidate? proposedMatch;
  final List<PayrollLineMatchReason> reasons;

  PayrollReconciliationLineResult({
    required this.voucherLine,
    required this.employee,
    required this.status,
    required List<PayrollReconciliationCandidate> evaluatedCandidates,
    required this.proposedMatch,
    required List<PayrollLineMatchReason> reasons,
  })  : assert(
          status == PayrollLineMatchStatus.suggested
              ? proposedMatch != null
              : proposedMatch == null,
        ),
        evaluatedCandidates = List.unmodifiable(evaluatedCandidates),
        reasons = List.unmodifiable(reasons);

  bool get requiresHumanConfirmation => proposedMatch != null;
}

class PayrollStatementReconciliationResult {
  final List<PayrollStatementRow> statementRows;
  final List<PayrollReconciliationLineResult> lineResults;

  /// Outgoing rows whose description AND observed beneficiary name no tenant
  /// employee — neither by primary name nor by configured alias. This is the
  /// matcher's POSITIVE proof that the movement is foreign to payroll; only
  /// rows in this set may be classified automatically as non-payroll.
  ///
  /// The polarity is deliberate: a row absent from the set is "not proven
  /// foreign" and stays under human review, so a legacy caller that never
  /// populates the set produces zero automatic classifications instead of
  /// silently absorbing worker-named movements.
  final Set<String> foreignOutgoingSourceRowIds;

  PayrollStatementReconciliationResult({
    required List<PayrollStatementRow> statementRows,
    required List<PayrollReconciliationLineResult> lineResults,
    Set<String> foreignOutgoingSourceRowIds = const <String>{},
  })  : statementRows = List.unmodifiable(statementRows),
        lineResults = List.unmodifiable(lineResults),
        foreignOutgoingSourceRowIds =
            Set.unmodifiable(foreignOutgoingSourceRowIds);

  List<PayrollReconciliationCandidate> get proposedMatches {
    return List.unmodifiable(
      lineResults
          .map((result) => result.proposedMatch)
          .whereType<PayrollReconciliationCandidate>(),
    );
  }

  List<PayrollStatementRow> get unmatchedOutgoingRows {
    final proposedRowIds = proposedMatches
        .map((candidate) => candidate.statementRow.sourceRowId)
        .toSet();
    return List.unmodifiable(
      statementRows.where(
        (row) =>
            row.isOutgoingCandidate &&
            !proposedRowIds.contains(row.sourceRowId),
      ),
    );
  }
}

String normalizePayrollReconciliationText(String value) {
  const replacements = <String, String>{
    'á': 'a',
    'à': 'a',
    'ä': 'a',
    'â': 'a',
    'ã': 'a',
    'é': 'e',
    'è': 'e',
    'ë': 'e',
    'ê': 'e',
    'í': 'i',
    'ì': 'i',
    'ï': 'i',
    'î': 'i',
    'ó': 'o',
    'ò': 'o',
    'ö': 'o',
    'ô': 'o',
    'õ': 'o',
    'ú': 'u',
    'ù': 'u',
    'ü': 'u',
    'û': 'u',
    'ñ': 'n',
  };

  var normalized = value.toLowerCase();
  for (final entry in replacements.entries) {
    normalized = normalized.replaceAll(entry.key, entry.value);
  }

  return normalized
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
