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

  /// El banco imprimió una **forma corta** del nombre registrado — el
  /// `nombre + apellido` con que el titular guardó al destinatario en su
  /// libreta de transferencias.
  ///
  /// Es evidencia más débil que el nombre completo o un alias que alguien
  /// configuró a mano, así que puntúa por debajo de ambos y su confianza
  /// nunca llega a alta: la propuesta sigue exigiendo confirmación humana.
  shortName,
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
  shortNameMatched,
  paymentMethodIsTransfer,
  paymentMethodDiffersFromPreference,
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

  /// El movimiento podría pagar semanas de **personas distintas**. Es la única
  /// ambigüedad que ninguna regla de orden puede resolver: no se sabe de quién
  /// es el pago, y eso lo decide un humano.
  transactionMatchesMultipleEmployees,

  /// Varias semanas de la MISMA persona competían por los mismos pagos iguales,
  /// y se resolvió por antigüedad: el pago más antiguo a la semana más antigua.
  assignedByWeekOrder,
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
  transactionMatchesMultipleEmployees,
  assignedByWeekOrder,

  /// Había pagos que calzaban, pero se asignaron a semanas anteriores de la
  /// misma persona. La semana queda sin pago, y eso es una afirmación distinta
  /// de «nadie la nombra».
  transactionsTakenByOlderWeeks,
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
  /// Hard business limit for a statement-to-payroll proposal.
  ///
  /// A caller may configure a stricter tolerance, but the matcher must never
  /// propose a movement whose absolute difference exceeds CLP 1,000.
  static const int maximumProposableDifferenceClp = 1000;

  /// Last eligible calendar day after the payroll period closes.
  ///
  /// The default window is inclusive: close day (0) through close day +5.
  final int paymentWindowDays;
  final int minimumToleranceClp;
  final int maximumToleranceClp;

  /// Optional stricter relative tolerance in basis points. Zero keeps the
  /// default flat CLP 1,000 tolerance.
  final int relativeToleranceBasisPoints;

  const PayrollReconciliationConfig({
    this.paymentWindowDays = 5,
    this.minimumToleranceClp = maximumProposableDifferenceClp,
    this.maximumToleranceClp = maximumProposableDifferenceClp,
    this.relativeToleranceBasisPoints = 0,
  })  : assert(paymentWindowDays >= 0),
        assert(minimumToleranceClp >= 0),
        assert(maximumToleranceClp >= minimumToleranceClp),
        assert(relativeToleranceBasisPoints >= 0);

  int toleranceFor(int pendingAmountClp) {
    final relativeTolerance =
        (pendingAmountClp.abs() * relativeToleranceBasisPoints + 9999) ~/ 10000;
    final configuredTolerance = relativeTolerance.clamp(
      minimumToleranceClp,
      maximumToleranceClp,
    );
    return configuredTolerance.clamp(0, maximumProposableDifferenceClp);
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
    PayrollMatchConfidence? confidence,
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
      confidence: confidence ?? this.confidence,
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

/// Las formas cortas con que un banco chileno puede imprimir a [displayName].
///
/// **Por qué existe** (medido en producción el 2026-08-10, con una cartola real
/// del taller): el banco no imprime el nombre legal completo del destinatario,
/// sino el rótulo con que el titular lo guardó en su libreta de transferencias
/// —`App-traspaso A: Fernando Tapia`—, mientras la ficha del ERP dice
/// `Fernando José Tapia Carrillo`. Sin esto, **ninguna persona con más de dos
/// palabras en su nombre calza nunca**: su sueldo aparece como un cargo suelto
/// «sin persona asignada» y su semana como una obligación «que nadie nombra»,
/// las dos mitades del mismo pago en dos filas que no se juntan.
///
/// **La regla, y su límite.** Una forma vale cuando empieza por el primer
/// nombre, conserva el orden y termina en uno de los **dos últimos** tokens —la
/// zona de los apellidos—. Eso admite `Fernando Tapia`, `Fernando Tapia
/// Carrillo` y `Fernando José Tapia`, y deja fuera `Fernando José`: dos nombres
/// de pila sin apellido no identifican a nadie, y es justo la forma que
/// chocaría con otro Fernando del taller.
///
/// No inventa personas: cada forma es un subconjunto ordenado del nombre que
/// alguien registró. Y no decide sola — quien la use sigue pasando por ventana
/// de fecha, tolerancia de monto, unicidad y confirmación humana.
Set<String> payrollShortNameForms(String displayName) {
  final tokens = normalizePayrollReconciliationText(displayName)
      .split(' ')
      .where((token) => token.isNotEmpty)
      .toList(growable: false);
  // Con dos palabras la única forma es el nombre completo, que ya se compara
  // aparte. Se acota a seis tokens para que un nombre larguísimo no genere una
  // combinatoria que nadie va a imprimir.
  if (tokens.length < 3 || tokens.length > 6) return const <String>{};

  final first = tokens.first;
  // With three tokens, token 2 is ambiguous: it can be either a second given
  // name (`Juan Pablo Soto`) or the first surname (`Juan Soto Pérez`). The
  // final token is the only safe surname in both shapes, so never derive
  // `first + token 2` from a three-token name. Four or more tokens retain the
  // measured Chilean two-surname zone used by the real Fernando case.
  final surnameZone = tokens.length == 3 ? 2 : tokens.length - 2;
  final forms = <String>{};

  for (var end = surnameZone; end < tokens.length; end++) {
    // `primer nombre + un apellido`.
    forms.add('$first ${tokens[end]}');
    // `primer nombre + un token intermedio + un apellido`: cubre tanto
    // `Fernando José Tapia` como `Fernando Tapia Carrillo`.
    for (var middle = 1; middle < end; middle++) {
      forms.add('$first ${tokens[middle]} ${tokens[end]}');
    }
  }
  // El nombre completo no es una forma corta: lo compara `_matchBeneficiary`
  // por su propio camino, y con más puntaje.
  forms.remove(tokens.join(' '));
  return Set<String>.unmodifiable(forms);
}
