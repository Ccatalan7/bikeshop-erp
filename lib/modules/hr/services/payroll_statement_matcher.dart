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
    final employeeIdsByRowId = <String, Set<String>>{};
    for (final line in voucherLines) {
      final evaluations = evaluationsByLineId[line.lineId];
      if (evaluations == null) continue;
      for (final candidate in evaluations.where((value) => value.isEligible)) {
        final rowId = candidate.statementRow.sourceRowId;
        eligibleUseCountByRowId.update(
          rowId,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        employeeIdsByRowId
            .putIfAbsent(rowId, () => <String>{})
            .add(line.employeeId);
      }
    }

    // **Un movimiento que podría ser de dos PERSONAS distintas no se asigna
    // jamás.** Ninguna regla de orden puede decidir de quién es un pago; eso lo
    // decide un humano mirando la evidencia.
    final contestedRowIds = <String>{
      for (final entry in employeeIdsByRowId.entries)
        if (entry.value.length > 1) entry.key,
    };

    // **Asignación cronológica entre semanas de la MISMA persona.**
    //
    // La ventana normal (cierre a cierre +5) separa semanas consecutivas. Este
    // orden sigue protegiendo periodos duplicados o excepcionalmente
    // solapados: una misma fila bancaria nunca puede proponerse dos veces.
    //
    // La regla es la que usaría cualquiera: **la semana más antigua se queda
    // con el pago más antiguo que le sirve**, y lo que queda libre pasa a la
    // siguiente. No adivina cuando queda duda de verdad: si a una semana le
    // siguen quedando dos pagos libres en su turno, sigue siendo pregunta
    // humana, porque dos pagos iguales para una sola deuda pueden ser un pago
    // partido o un pago que no era de nómina.
    final orderedLines = [...voucherLines]..sort(_compareLinesByPeriod);
    final assignedRowIdByLineId = <String, String>{};
    final contendedLineIds = <String>{};
    final takenRowIds = <String>{};
    for (final line in orderedLines) {
      final evaluations = evaluationsByLineId[line.lineId];
      if (evaluations == null) continue;
      final free = evaluations
          .where(
            (candidate) =>
                candidate.isEligible &&
                !contestedRowIds.contains(candidate.statementRow.sourceRowId) &&
                !takenRowIds.contains(candidate.statementRow.sourceRowId),
          )
          .toList()
        ..sort(_compareCandidatesByDate);
      if (free.length == 1) {
        final rowId = free.single.statementRow.sourceRowId;
        assignedRowIdByLineId[line.lineId] = rowId;
        takenRowIds.add(rowId);
      } else if (free.length > 1) {
        contendedLineIds.add(line.lineId);
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
      final assignedRowId = assignedRowIdByLineId[line.lineId];
      final resolvedByOrder =
          assignedRowId != null && eligibleForLine.length > 1;
      final hasMultipleTransactions = eligibleForLine.length > 1;
      final finalEvaluations = originalEvaluations.map((candidate) {
        if (!candidate.isEligible) return candidate;

        final rowId = candidate.statementRow.sourceRowId;
        final reasons = <PayrollCandidateReason>[...candidate.reasons];
        if (hasMultipleTransactions) {
          reasons.add(PayrollCandidateReason.multipleTransactionsForLine);
        }
        if ((eligibleUseCountByRowId[rowId] ?? 0) > 1) {
          reasons.add(
            PayrollCandidateReason.transactionMatchesMultipleLines,
          );
        }
        if (contestedRowIds.contains(rowId)) {
          reasons.add(
            PayrollCandidateReason.transactionMatchesMultipleEmployees,
          );
        }
        if (resolvedByOrder && rowId == assignedRowId) {
          reasons.add(PayrollCandidateReason.assignedByWeekOrder);
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

      // Ambigüedad de PERSONA: no se resuelve sola, nunca.
      final touchesContestedRow = finalEligible.any(
        (candidate) =>
            contestedRowIds.contains(candidate.statementRow.sourceRowId),
      );
      if (touchesContestedRow) {
        lineResults.add(
          PayrollReconciliationLineResult(
            voucherLine: line,
            employee: employee,
            status: PayrollLineMatchStatus.needsReview,
            evaluatedCandidates: finalEvaluations,
            proposedMatch: null,
            reasons: const [
              PayrollLineMatchReason.transactionMatchesMultipleEmployees,
            ],
          ),
        );
        continue;
      }

      // A esta semana le seguían quedando dos pagos libres en su turno: dos
      // pagos iguales para una sola deuda pueden ser un pago partido o uno que
      // no era de nómina, así que sigue siendo pregunta humana.
      if (contendedLineIds.contains(line.lineId)) {
        lineResults.add(
          PayrollReconciliationLineResult(
            voucherLine: line,
            employee: employee,
            status: PayrollLineMatchStatus.needsReview,
            evaluatedCandidates: finalEvaluations,
            proposedMatch: null,
            reasons: const [
              PayrollLineMatchReason.multipleTransactionsForLine,
            ],
          ),
        );
        continue;
      }

      if (assignedRowId == null) {
        // Había pagos que calzaban, pero se los llevaron semanas anteriores de
        // la misma persona. Decirlo así es distinto —y más útil— que «no hay
        // movimiento elegible».
        lineResults.add(
          PayrollReconciliationLineResult(
            voucherLine: line,
            employee: employee,
            status: PayrollLineMatchStatus.unmatched,
            evaluatedCandidates: finalEvaluations,
            proposedMatch: null,
            reasons: const [
              PayrollLineMatchReason.transactionsTakenByOlderWeeks,
            ],
          ),
        );
        continue;
      }

      final assigned = finalEligible.firstWhere(
        (candidate) => candidate.statementRow.sourceRowId == assignedRowId,
      );
      lineResults.add(
        PayrollReconciliationLineResult(
          voucherLine: line,
          employee: employee,
          status: PayrollLineMatchStatus.suggested,
          evaluatedCandidates: finalEvaluations,
          // **Una asignación por orden nunca llega a confianza alta.** El monto
          // y la fecha pueden ser perfectos; a qué semana pertenece el pago lo
          // dedujo una regla, no lo dijo el banco.
          proposedMatch: resolvedByOrder
              ? assigned.copyWith(
                  confidence: switch (assigned.confidence) {
                    PayrollMatchConfidence.high =>
                      PayrollMatchConfidence.medium,
                    final other => other,
                  },
                )
              : assigned,
          reasons: resolvedByOrder
              ? const [PayrollLineMatchReason.assignedByWeekOrder]
              : const [PayrollLineMatchReason.uniqueCandidate],
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
    final dateIsEligible = daysAfterPeriodEnd != null &&
        daysAfterPeriodEnd >= 0 &&
        daysAfterPeriodEnd <= config.paymentWindowDays;
    // The amount rule is symmetric: a bank movement may be proposed when its
    // absolute difference is at most CLP 1,000. A non-zero difference is only
    // a review proposal; it never posts or confirms a payment by itself.
    final amountIsWithinTolerance = absoluteVariance <= tolerance;
    final amountIsEligible = amountIsWithinTolerance;
    final isEligible = dateIsEligible && amountIsEligible;

    final reasons = <PayrollCandidateReason>[
      PayrollCandidateReason.outgoingMovement,
      switch (beneficiaryMatch.kind) {
        PayrollBeneficiaryMatchKind.primaryName =>
          PayrollCandidateReason.primaryNameMatched,
        PayrollBeneficiaryMatchKind.configuredAlias =>
          PayrollCandidateReason.configuredAliasMatched,
        PayrollBeneficiaryMatchKind.shortName =>
          PayrollCandidateReason.shortNameMatched,
      },
      if (line.paymentMethod == PayrollReconciliationPaymentMethod.transfer)
        PayrollCandidateReason.paymentMethodIsTransfer
      else
        // El método de la ficha es una preferencia, no una prueba de cómo se
        // resolvió esta semana. La cartola puede mostrar una transferencia
        // aunque normalmente la persona cobre en efectivo; se conserva como
        // candidato y el workspace decide la composición final.
        PayrollCandidateReason.paymentMethodDiffersFromPreference,
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
    } else {
      if (variance < 0) {
        reasons.add(PayrollCandidateReason.amountBelowPendingBalance);
      }
      reasons.add(
        amountIsWithinTolerance
            ? PayrollCandidateReason.amountWithinTolerance
            : PayrollCandidateReason.amountOutsideTolerance,
      );
      reasons.add(PayrollCandidateReason.nonZeroVariance);
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
        beneficiaryMatchKind: beneficiaryMatch.kind,
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
  if (employee.bankBeneficiaryAliases
      .map(normalizePayrollReconciliationText)
      .any((alias) => _containsWholePhrase(haystack, alias))) {
    return true;
  }
  // La forma corta cuenta también acá, y en la dirección segura: reconocer que
  // el cargo nombra a alguien de la nómina sólo puede sacarlo de la
  // clasificación automática «no es nómina» y devolverlo a una decisión
  // explícita. Nunca crea un pago por sí sola.
  return payrollShortNameForms(employee.displayName)
      .any((form) => _containsWholePhrase(haystack, form));
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

  // Último recurso, y el más débil de los tres: la forma corta que el banco
  // imprime cuando el titular guardó al destinatario como `nombre apellido`.
  // Se prueban de la más larga a la más corta para que la evidencia que quede
  // registrada sea la más específica que calzó.
  final shortForms = payrollShortNameForms(employee.displayName).toList()
    ..sort((left, right) {
      final byLength = right.length.compareTo(left.length);
      return byLength != 0 ? byLength : left.compareTo(right);
    });
  for (final form in shortForms) {
    if (_containsWholePhrase(row.normalizedDescription, form)) {
      return _BeneficiaryMatch(
        kind: PayrollBeneficiaryMatchKind.shortName,
        normalizedValue: form,
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
  // La evidencia del nombre puntúa por lo específica que es: el nombre
  // registrado completo, después un alias que una persona configuró a mano, y
  // al final la forma corta que el propio ERP dedujo del nombre.
  var score = switch (beneficiaryMatchKind) {
    PayrollBeneficiaryMatchKind.primaryName => 25,
    PayrollBeneficiaryMatchKind.configuredAlias => 22,
    PayrollBeneficiaryMatchKind.shortName => 18,
  };
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
  required PayrollBeneficiaryMatchKind beneficiaryMatchKind,
  required int? daysAfterPeriodEnd,
  required int absoluteVarianceClp,
}) {
  if (!isEligible || daysAfterPeriodEnd == null) {
    return PayrollMatchConfidence.none;
  }
  // **Una forma corta nunca llega a `CALZA`.** El nombre que el banco imprimió
  // no es el que alguien registró: es una deducción del ERP, y decir «alta»
  // sobre una deducción propia es afirmar una certeza que nadie tomó. El monto
  // y la fecha pueden ser perfectos; la identidad sigue siendo lo que hay que
  // mirar, y por eso el operador la ve como `REVISA`.
  if (beneficiaryMatchKind == PayrollBeneficiaryMatchKind.shortName) {
    return daysAfterPeriodEnd.abs() <= 4
        ? PayrollMatchConfidence.medium
        : PayrollMatchConfidence.low;
  }
  if (daysAfterPeriodEnd.abs() <= 4 && absoluteVarianceClp <= 250) {
    return PayrollMatchConfidence.high;
  }
  if (daysAfterPeriodEnd.abs() <= 4) {
    return PayrollMatchConfidence.medium;
  }
  return PayrollMatchConfidence.low;
}

/// Semana más antigua primero. Es el orden en que se paga una deuda.
int _compareLinesByPeriod(
  PayrollReconciliationVoucherLine left,
  PayrollReconciliationVoucherLine right,
) {
  final byEnd = left.periodEnd.compareTo(right.periodEnd);
  if (byEnd != 0) return byEnd;
  final byStart = left.periodStart.compareTo(right.periodStart);
  if (byStart != 0) return byStart;
  return left.lineId.compareTo(right.lineId);
}

/// Pago más antiguo primero; a igual fecha, el de mejor puntaje. El orden es
/// total y estable: la misma cartola produce siempre la misma asignación.
int _compareCandidatesByDate(
  PayrollReconciliationCandidate left,
  PayrollReconciliationCandidate right,
) {
  final byDate = _compareNullableDates(
    left.statementRow.bookingDate,
    right.statementRow.bookingDate,
  );
  if (byDate != 0) return byDate;
  final byScore = right.score.compareTo(left.score);
  if (byScore != 0) return byScore;
  return left.statementRow.sourceRowId.compareTo(
    right.statementRow.sourceRowId,
  );
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
