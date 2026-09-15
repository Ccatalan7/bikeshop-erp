import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/hr/models/payroll_statement_reconciliation.dart';
import 'package:vinabike_erp/modules/hr/services/payroll_statement_matcher.dart';

void main() {
  const matcher = PayrollStatementMatcher();

  group('PayrollStatementMatcher', () {
    test('suggests a unique near-exact transfer and exposes its variance', () {
      final statementRow = _outgoingRow(
        rowNumber: 1,
        date: const PayrollCivilDate(2026, 7, 27),
        description: 'App-traspaso A: PERSONA ÚNO',
        amountClp: 128000,
      );
      final result = matcher.match(
        statementRows: [statementRow],
        employees: [
          _employee(
            id: 'employee-transfer',
            name: 'Persona Uno',
          ),
        ],
        voucherLines: [
          _line(
            id: 'line-week-30',
            employeeId: 'employee-transfer',
            periodEnd: const PayrollCivilDate(2026, 7, 26),
            pendingAmountClp: 127750,
          ),
        ],
      );

      final lineResult = result.lineResults.single;
      expect(lineResult.status, PayrollLineMatchStatus.suggested);
      expect(lineResult.requiresHumanConfirmation, isTrue);
      expect(result.proposedMatches, hasLength(1));
      expect(result.unmatchedOutgoingRows, isEmpty);

      final proposal = lineResult.proposedMatch!;
      expect(proposal.amountVarianceClp, 250);
      expect(proposal.allowedToleranceClp, 1000);
      expect(proposal.confidence, PayrollMatchConfidence.high);
      expect(proposal.requiresHumanConfirmation, isTrue);
      expect(
        proposal.reasons,
        contains(PayrollCandidateReason.nonZeroVariance),
      );
    });

    test('week 13–19 proposes a 23/07 transfer of 72,000 against 71,750', () {
      final statementRow = _outgoingRow(
        rowNumber: 1,
        date: const PayrollCivilDate(2026, 7, 23),
        description: 'App-traspaso A: Persona Taller',
        amountClp: 72000,
      );
      final result = matcher.match(
        statementRows: [statementRow],
        employees: [
          _employee(id: 'employee-shop', name: 'Persona Taller'),
        ],
        voucherLines: [
          _line(
            id: 'line-week-29',
            employeeId: 'employee-shop',
            periodEnd: const PayrollCivilDate(2026, 7, 19),
            pendingAmountClp: 71750,
          ),
          _line(
            id: 'line-week-30',
            employeeId: 'employee-shop',
            periodEnd: const PayrollCivilDate(2026, 7, 26),
            pendingAmountClp: 71750,
          ),
        ],
      );

      final week29 = result.lineResults.singleWhere(
        (line) => line.voucherLine.lineId == 'line-week-29',
      );
      final week30 = result.lineResults.singleWhere(
        (line) => line.voucherLine.lineId == 'line-week-30',
      );
      final proposal = week29.proposedMatch;
      expect(proposal, isNotNull);
      expect(proposal!.daysAfterPeriodEnd, 4);
      expect(proposal.amountVarianceClp, 250);
      expect(proposal.requiresHumanConfirmation, isTrue);
      expect(week30.status, PayrollLineMatchStatus.unmatched);
      expect(week30.evaluatedCandidates.single.daysAfterPeriodEnd, -3);
      expect(result.proposedMatches, hasLength(1));
    });

    test('suggests an underpayment within CLP 1,000 for human confirmation',
        () {
      final partialDebit = _outgoingRow(
        rowNumber: 1,
        date: const PayrollCivilDate(2026, 7, 27),
        description: 'Transferencia a Persona Parcial',
        amountClp: 127500,
      );
      final result = matcher.match(
        statementRows: [partialDebit],
        employees: [
          _employee(
            id: 'employee-partial',
            name: 'Persona Parcial',
          ),
        ],
        voucherLines: [
          _line(
            id: 'line-partial',
            employeeId: 'employee-partial',
            periodEnd: const PayrollCivilDate(2026, 7, 26),
            pendingAmountClp: 127750,
          ),
        ],
      );

      final lineResult = result.lineResults.single;
      expect(lineResult.status, PayrollLineMatchStatus.suggested);
      expect(lineResult.proposedMatch, isNotNull);
      expect(lineResult.requiresHumanConfirmation, isTrue);
      expect(result.proposedMatches, hasLength(1));
      expect(result.unmatchedOutgoingRows, isEmpty);

      final evaluated = lineResult.evaluatedCandidates.single;
      expect(evaluated.amountVarianceClp, -250);
      expect(evaluated.allowedToleranceClp, 1000);
      expect(
        evaluated.isEligible,
        isTrue,
        reason: 'The CLP 1,000 rule is symmetric; a smaller movement may be '
            'proposed but still requires explicit human confirmation.',
      );
      expect(evaluated.requiresHumanConfirmation, isTrue);
      expect(
        evaluated.reasons,
        contains(PayrollCandidateReason.amountBelowPendingBalance),
      );
      expect(
        evaluated.reasons,
        contains(PayrollCandidateReason.nonZeroVariance),
      );
    });

    test('keeps an overpayment beyond CLP 1,000 ineligible', () {
      final excessiveDebit = _outgoingRow(
        rowNumber: 1,
        date: const PayrollCivilDate(2026, 7, 27),
        description: 'Transferencia a Persona Exceso',
        amountClp: 128751,
      );
      final result = matcher.match(
        statementRows: [excessiveDebit],
        employees: [
          _employee(
            id: 'employee-over',
            name: 'Persona Exceso',
          ),
        ],
        voucherLines: [
          _line(
            id: 'line-over',
            employeeId: 'employee-over',
            periodEnd: const PayrollCivilDate(2026, 7, 26),
            pendingAmountClp: 127750,
          ),
        ],
      );

      final lineResult = result.lineResults.single;
      final evaluated = lineResult.evaluatedCandidates.single;
      expect(lineResult.status, PayrollLineMatchStatus.unmatched);
      expect(lineResult.proposedMatch, isNull);
      expect(result.proposedMatches, isEmpty);
      expect(result.unmatchedOutgoingRows, [excessiveDebit]);
      expect(evaluated.amountVarianceClp, 1001);
      expect(evaluated.allowedToleranceClp, 1000);
      expect(evaluated.isEligible, isFalse);
      expect(
        evaluated.reasons,
        contains(PayrollCandidateReason.amountOutsideTolerance),
      );
    });

    test('keeps an underpayment beyond CLP 1,000 ineligible', () {
      final excessiveDifference = _outgoingRow(
        rowNumber: 1,
        date: const PayrollCivilDate(2026, 7, 27),
        description: 'Transferencia a Persona Bajo Limite',
        amountClp: 126749,
      );
      final result = matcher.match(
        statementRows: [excessiveDifference],
        employees: [
          _employee(
            id: 'employee-under-limit',
            name: 'Persona Bajo Limite',
          ),
        ],
        voucherLines: [
          _line(
            id: 'line-under-limit',
            employeeId: 'employee-under-limit',
            periodEnd: const PayrollCivilDate(2026, 7, 26),
            pendingAmountClp: 127750,
          ),
        ],
      );

      final lineResult = result.lineResults.single;
      final evaluated = lineResult.evaluatedCandidates.single;
      expect(lineResult.status, PayrollLineMatchStatus.unmatched);
      expect(lineResult.proposedMatch, isNull);
      expect(evaluated.amountVarianceClp, -1001);
      expect(evaluated.allowedToleranceClp, 1000);
      expect(evaluated.isEligible, isFalse);
      expect(
        evaluated.reasons,
        containsAll(<PayrollCandidateReason>[
          PayrollCandidateReason.amountBelowPendingBalance,
          PayrollCandidateReason.amountOutsideTolerance,
        ]),
      );
    });

    test('does not match a manager transfer far below either payroll amount',
        () {
      final unrelatedTransfer = _outgoingRow(
        rowNumber: 1,
        date: const PayrollCivilDate(2026, 7, 13),
        description: 'App-traspaso A: Persona Uno',
        amountClp: 22000,
      );
      final result = matcher.match(
        statementRows: [unrelatedTransfer],
        employees: [
          _employee(
            id: 'employee-transfer',
            name: 'Persona Uno',
          ),
        ],
        voucherLines: [
          _line(
            id: 'line-smaller-payroll',
            employeeId: 'employee-transfer',
            periodEnd: const PayrollCivilDate(2026, 7, 12),
            pendingAmountClp: 71750,
          ),
          _line(
            id: 'line-larger-payroll',
            employeeId: 'employee-transfer',
            periodEnd: const PayrollCivilDate(2026, 7, 12),
            pendingAmountClp: 127750,
          ),
        ],
      );

      expect(result.proposedMatches, isEmpty);
      expect(result.unmatchedOutgoingRows, [unrelatedTransfer]);
      for (final lineResult in result.lineResults) {
        expect(lineResult.status, PayrollLineMatchStatus.unmatched);
        expect(lineResult.proposedMatch, isNull);
        expect(lineResult.evaluatedCandidates, hasLength(1));
        expect(lineResult.evaluatedCandidates.single.isEligible, isFalse);
        expect(
          lineResult.evaluatedCandidates.single.reasons,
          contains(PayrollCandidateReason.amountOutsideTolerance),
        );
      }
    });

    test('keeps a bank candidate even when the habitual method is cash', () {
      final result = matcher.match(
        statementRows: [
          _outgoingRow(
            rowNumber: 1,
            date: const PayrollCivilDate(2026, 7, 21),
            description: 'Transferencia a Persona Caja',
            amountClp: 38000,
          ),
        ],
        employees: [
          _employee(
            id: 'employee-cash',
            name: 'Persona Caja',
            paymentMethod: PayrollReconciliationPaymentMethod.cash,
          ),
        ],
        voucherLines: [
          _line(
            id: 'line-cash',
            employeeId: 'employee-cash',
            periodEnd: const PayrollCivilDate(2026, 7, 19),
            pendingAmountClp: 38000,
            paymentMethod: PayrollReconciliationPaymentMethod.cash,
          ),
        ],
      );

      final lineResult = result.lineResults.single;
      expect(lineResult.status, PayrollLineMatchStatus.suggested);
      expect(lineResult.proposedMatch, isNotNull);
      expect(lineResult.evaluatedCandidates, hasLength(1));
      expect(
        lineResult.proposedMatch!.reasons,
        contains(PayrollCandidateReason.paymentMethodDiffersFromPreference),
      );
    });

    test('uses a flat inclusive CLP 1,000 tolerance for small payrolls', () {
      final result = matcher.match(
        statementRows: [
          _outgoingRow(
            rowNumber: 1,
            date: const PayrollCivilDate(2026, 7, 21),
            description: 'Transferencia a Persona Cinco',
            amountClp: 11000,
          ),
        ],
        employees: [
          _employee(id: 'employee-five', name: 'Persona Cinco'),
        ],
        voucherLines: [
          _line(
            id: 'line-low-amount',
            employeeId: 'employee-five',
            periodEnd: const PayrollCivilDate(2026, 7, 19),
            pendingAmountClp: 10000,
          ),
        ],
      );

      final evaluated = result.lineResults.single.evaluatedCandidates.single;
      expect(evaluated.allowedToleranceClp, 1000);
      expect(evaluated.amountVarianceClp, 1000);
      expect(evaluated.isEligible, isTrue);
      expect(evaluated.requiresHumanConfirmation, isTrue);
      expect(result.proposedMatches, hasLength(1));
    });

    test('requires review when two transactions fit the same line', () {
      final result = matcher.match(
        statementRows: [
          _outgoingRow(
            rowNumber: 1,
            date: const PayrollCivilDate(2026, 7, 20),
            description: 'Transferencia a Persona Dos',
            amountClp: 35000,
          ),
          _outgoingRow(
            rowNumber: 2,
            date: const PayrollCivilDate(2026, 7, 21),
            description: 'Transferencia a Persona Dos',
            amountClp: 35200,
          ),
        ],
        employees: [
          _employee(
            id: 'employee-two',
            name: 'Persona Dos',
          ),
        ],
        voucherLines: [
          _line(
            id: 'line-ambiguous',
            employeeId: 'employee-two',
            periodEnd: const PayrollCivilDate(2026, 7, 19),
            pendingAmountClp: 35000,
          ),
        ],
      );

      final lineResult = result.lineResults.single;
      expect(lineResult.status, PayrollLineMatchStatus.needsReview);
      expect(lineResult.proposedMatch, isNull);
      expect(result.proposedMatches, isEmpty);
      expect(result.unmatchedOutgoingRows, hasLength(2));
      expect(
        lineResult.reasons,
        contains(PayrollLineMatchReason.multipleTransactionsForLine),
      );
    });

    test('does not select a row whose beneficiary alias maps to two workers',
        () {
      final sharedRow = _outgoingRow(
        rowNumber: 1,
        date: const PayrollCivilDate(2026, 7, 20),
        description: 'Transferencia a Beneficiario Compartido',
        amountClp: 50000,
      );
      final result = matcher.match(
        statementRows: [sharedRow],
        employees: [
          _employee(
            id: 'employee-a',
            name: 'Persona A',
            aliases: const ['Beneficiario Compartido'],
          ),
          _employee(
            id: 'employee-b',
            name: 'Persona B',
            aliases: const ['Beneficiario Compartido'],
          ),
        ],
        voucherLines: [
          _line(
            id: 'line-a',
            employeeId: 'employee-a',
            periodEnd: const PayrollCivilDate(2026, 7, 19),
            pendingAmountClp: 50000,
          ),
          _line(
            id: 'line-b',
            employeeId: 'employee-b',
            periodEnd: const PayrollCivilDate(2026, 7, 19),
            pendingAmountClp: 50000,
          ),
        ],
      );

      expect(result.proposedMatches, isEmpty);
      expect(result.unmatchedOutgoingRows, [sharedRow]);
      for (final lineResult in result.lineResults) {
        expect(lineResult.status, PayrollLineMatchStatus.needsReview);
        expect(lineResult.proposedMatch, isNull);
        // **De quién es el pago no lo resuelve ninguna regla de orden.** Es la
        // única ambigüedad que se queda siempre en manos de un humano, y el
        // motivo lo dice con esas palabras.
        expect(
          lineResult.reasons,
          contains(
            PayrollLineMatchReason.transactionMatchesMultipleEmployees,
          ),
        );
      }
    });

    test('uses an inclusive civil-date window from close through day five', () {
      final result = matcher.match(
        statementRows: [
          _outgoingRow(
            rowNumber: 1,
            date: const PayrollCivilDate(2026, 7, 24),
            description: 'Transferencia a Persona Cinco',
            amountClp: 60000,
          ),
          _outgoingRow(
            rowNumber: 2,
            date: const PayrollCivilDate(2026, 7, 25),
            description: 'Transferencia a Persona Seis',
            amountClp: 60000,
          ),
        ],
        employees: [
          _employee(id: 'employee-five', name: 'Persona Cinco'),
          _employee(id: 'employee-six', name: 'Persona Seis'),
        ],
        voucherLines: [
          _line(
            id: 'line-day-five',
            employeeId: 'employee-five',
            periodEnd: const PayrollCivilDate(2026, 7, 19),
            pendingAmountClp: 60000,
          ),
          _line(
            id: 'line-day-six',
            employeeId: 'employee-six',
            periodEnd: const PayrollCivilDate(2026, 7, 19),
            pendingAmountClp: 60000,
          ),
        ],
      );

      expect(
        result.lineResults.first.status,
        PayrollLineMatchStatus.suggested,
      );
      expect(
        result.lineResults.last.status,
        PayrollLineMatchStatus.unmatched,
      );
      expect(
        result.lineResults.last.evaluatedCandidates.single.reasons,
        contains(PayrollCandidateReason.dateOutsideWindow),
      );
    });

    test('week 6–12 accepts day 12 but rejects a salary payment on day 8', () {
      final result = matcher.match(
        statementRows: [
          _outgoingRow(
            rowNumber: 1,
            date: const PayrollCivilDate(2026, 7, 12),
            description: 'Transferencia a Persona Cierre',
            amountClp: 94500,
          ),
          _outgoingRow(
            rowNumber: 2,
            date: const PayrollCivilDate(2026, 7, 8),
            description: 'Transferencia a Persona Temprana',
            amountClp: 38000,
          ),
        ],
        employees: [
          _employee(id: 'employee-close', name: 'Persona Cierre'),
          _employee(id: 'employee-early', name: 'Persona Temprana'),
        ],
        voucherLines: [
          _line(
            id: 'line-close',
            employeeId: 'employee-close',
            periodEnd: const PayrollCivilDate(2026, 7, 12),
            pendingAmountClp: 94500,
          ),
          _line(
            id: 'line-before-close',
            employeeId: 'employee-early',
            periodEnd: const PayrollCivilDate(2026, 7, 12),
            pendingAmountClp: 38000,
          ),
        ],
      );

      final onClose = result.lineResults.singleWhere(
        (line) => line.voucherLine.lineId == 'line-close',
      );
      final beforeClose = result.lineResults.singleWhere(
        (line) => line.voucherLine.lineId == 'line-before-close',
      );
      expect(
        onClose.status,
        PayrollLineMatchStatus.suggested,
      );
      expect(
        onClose.proposedMatch!.reasons,
        contains(PayrollCandidateReason.dateWithinWindow),
      );
      expect(
        beforeClose.status,
        PayrollLineMatchStatus.unmatched,
      );
      expect(beforeClose.evaluatedCandidates, hasLength(1));
      expect(beforeClose.evaluatedCandidates.single.daysAfterPeriodEnd, -4);
      expect(
        beforeClose.evaluatedCandidates.single.reasons,
        contains(PayrollCandidateReason.dateOutsideWindow),
      );
    });

    test(
      'reconciles four adjacent weeks without confusing payroll, cash, or manager transfers',
      () {
        const vicenteId = 'employee-vicente';
        const lucasId = 'employee-lucas';
        const guillermoId = 'employee-guillermo';

        final vicenteWeek27 = _outgoingRow(
          rowNumber: 1,
          date: const PayrollCivilDate(2026, 7, 10),
          description: 'App-traspaso A: Vicente Díaz',
          amountClp: 120000,
        );
        final lucasWeek27 = _outgoingRow(
          rowNumber: 2,
          date: const PayrollCivilDate(2026, 7, 6),
          description: 'App-traspaso A: Lucas Pacheco',
          amountClp: 35000,
        );
        final vicenteWeek27OneDayLate = _outgoingRow(
          rowNumber: 3,
          date: const PayrollCivilDate(2026, 7, 11),
          description: 'App-traspaso A: Vicente Díaz',
          amountClp: 120000,
        );
        final vicenteWeek28 = _outgoingRow(
          rowNumber: 4,
          date: const PayrollCivilDate(2026, 7, 13),
          description: 'App-traspaso A: Vicente Díaz',
          amountClp: 126000,
        );
        final lucasWeek28 = _outgoingRow(
          rowNumber: 5,
          date: const PayrollCivilDate(2026, 7, 13),
          description: 'App-traspaso A: Lucas Pacheco',
          amountClp: 42000,
        );
        final vicenteManagerTransfer = _outgoingRow(
          rowNumber: 6,
          date: const PayrollCivilDate(2026, 7, 14),
          description: 'App-traspaso A: Vicente Díaz',
          amountClp: 22000,
        );
        final vicenteWeek29 = _outgoingRow(
          rowNumber: 7,
          date: const PayrollCivilDate(2026, 7, 20),
          description: 'App-traspaso A: Vicente Díaz',
          amountClp: 124250,
        );
        final lucasWeek29 = _outgoingRow(
          rowNumber: 8,
          date: const PayrollCivilDate(2026, 7, 20),
          description: 'App-traspaso A: Lucas Pacheco',
          amountClp: 38500,
        );
        final guillermoBankMovement = _outgoingRow(
          rowNumber: 9,
          date: const PayrollCivilDate(2026, 7, 22),
          description: 'Transferencia a Rodrigo Guillermo Nieto',
          amountClp: 38000,
        );
        final vicenteWeek30Rounded = _outgoingRow(
          rowNumber: 10,
          date: const PayrollCivilDate(2026, 7, 27),
          description: 'App-traspaso A: Vicente Díaz',
          amountClp: 128000,
        );
        final lucasWeek30 = _outgoingRow(
          rowNumber: 11,
          date: const PayrollCivilDate(2026, 7, 27),
          description: 'App-traspaso A: Lucas Pacheco',
          amountClp: 35000,
        );

        final voucherLines = <PayrollReconciliationVoucherLine>[
          _line(
            id: 'line-week-27-vicente',
            employeeId: vicenteId,
            periodEnd: const PayrollCivilDate(2026, 7, 5),
            pendingAmountClp: 120000,
          ),
          _line(
            id: 'line-week-27-lucas',
            employeeId: lucasId,
            periodEnd: const PayrollCivilDate(2026, 7, 5),
            pendingAmountClp: 35000,
          ),
          _line(
            id: 'line-week-27-guillermo',
            employeeId: guillermoId,
            periodEnd: const PayrollCivilDate(2026, 7, 5),
            pendingAmountClp: 38000,
            paymentMethod: PayrollReconciliationPaymentMethod.cash,
          ),
          _line(
            id: 'line-week-28-vicente',
            employeeId: vicenteId,
            periodEnd: const PayrollCivilDate(2026, 7, 12),
            pendingAmountClp: 126000,
          ),
          _line(
            id: 'line-week-28-lucas',
            employeeId: lucasId,
            periodEnd: const PayrollCivilDate(2026, 7, 12),
            pendingAmountClp: 42000,
          ),
          _line(
            id: 'line-week-28-guillermo',
            employeeId: guillermoId,
            periodEnd: const PayrollCivilDate(2026, 7, 12),
            pendingAmountClp: 40000,
            paymentMethod: PayrollReconciliationPaymentMethod.cash,
          ),
          _line(
            id: 'line-week-29-vicente',
            employeeId: vicenteId,
            periodEnd: const PayrollCivilDate(2026, 7, 19),
            pendingAmountClp: 124250,
          ),
          _line(
            id: 'line-week-29-lucas',
            employeeId: lucasId,
            periodEnd: const PayrollCivilDate(2026, 7, 19),
            pendingAmountClp: 38500,
          ),
          _line(
            id: 'line-week-29-guillermo',
            employeeId: guillermoId,
            periodEnd: const PayrollCivilDate(2026, 7, 19),
            pendingAmountClp: 38000,
            paymentMethod: PayrollReconciliationPaymentMethod.cash,
          ),
          _line(
            id: 'line-week-30-vicente',
            employeeId: vicenteId,
            periodEnd: const PayrollCivilDate(2026, 7, 26),
            pendingAmountClp: 127750,
          ),
          _line(
            id: 'line-week-30-lucas',
            employeeId: lucasId,
            periodEnd: const PayrollCivilDate(2026, 7, 26),
            pendingAmountClp: 35000,
          ),
          _line(
            id: 'line-week-30-guillermo',
            employeeId: guillermoId,
            periodEnd: const PayrollCivilDate(2026, 7, 26),
            pendingAmountClp: 38000,
            paymentMethod: PayrollReconciliationPaymentMethod.cash,
          ),
        ];

        final result = matcher.match(
          statementRows: <PayrollStatementRow>[
            vicenteWeek27,
            lucasWeek27,
            vicenteWeek27OneDayLate,
            vicenteWeek28,
            lucasWeek28,
            vicenteManagerTransfer,
            vicenteWeek29,
            lucasWeek29,
            guillermoBankMovement,
            vicenteWeek30Rounded,
            lucasWeek30,
          ],
          employees: <PayrollReconciliationEmployee>[
            _employee(id: vicenteId, name: 'Vicente Díaz'),
            _employee(id: lucasId, name: 'Lucas Pacheco'),
            _employee(
              id: guillermoId,
              name: 'Rodrigo Guillermo Nieto',
              paymentMethod: PayrollReconciliationPaymentMethod.cash,
            ),
          ],
          voucherLines: voucherLines,
        );

        final proposalsByLineId = <String, PayrollReconciliationCandidate>{
          for (final proposal in result.proposedMatches)
            proposal.voucherLine.lineId: proposal,
        };
        expect(
          proposalsByLineId.map(
            (lineId, proposal) =>
                MapEntry(lineId, proposal.statementRow.sourceRowId),
          ),
          <String, String>{
            'line-week-27-vicente': vicenteWeek27.sourceRowId,
            'line-week-27-lucas': lucasWeek27.sourceRowId,
            'line-week-28-vicente': vicenteWeek28.sourceRowId,
            'line-week-28-lucas': lucasWeek28.sourceRowId,
            'line-week-29-vicente': vicenteWeek29.sourceRowId,
            'line-week-29-lucas': lucasWeek29.sourceRowId,
            'line-week-29-guillermo': guillermoBankMovement.sourceRowId,
            'line-week-30-vicente': vicenteWeek30Rounded.sourceRowId,
            'line-week-30-lucas': lucasWeek30.sourceRowId,
          },
        );
        expect(
          result.proposedMatches
              .map((proposal) => proposal.statementRow.sourceRowId)
              .toSet(),
          hasLength(9),
          reason: 'a bank row must be allocated to only one week and person',
        );
        expect(
          result.lineResults
              .where(
                (line) =>
                    line.voucherLine.paymentMethod ==
                    PayrollReconciliationPaymentMethod.transfer,
              )
              .map((line) => line.status),
          everyElement(PayrollLineMatchStatus.suggested),
        );
        expect(
          result.lineResults.map((line) => line.status),
          isNot(contains(PayrollLineMatchStatus.needsReview)),
        );

        final roundedProposal = proposalsByLineId['line-week-30-vicente']!;
        expect(roundedProposal.amountVarianceClp, 250);
        expect(roundedProposal.allowedToleranceClp, 1000);
        expect(
          roundedProposal.reasons,
          contains(PayrollCandidateReason.amountWithinTolerance),
        );

        final week27Vicente = result.lineResults.singleWhere(
          (line) => line.voucherLine.lineId == 'line-week-27-vicente',
        );
        expect(week27Vicente.status, PayrollLineMatchStatus.suggested);
        final boundaryCandidate = week27Vicente.evaluatedCandidates.singleWhere(
          (candidate) =>
              candidate.statementRow.sourceRowId == vicenteWeek27.sourceRowId,
        );
        expect(boundaryCandidate.daysAfterPeriodEnd, 5);
        expect(boundaryCandidate.isEligible, isTrue);
        expect(
          week27Vicente.proposedMatch!.statementRow.sourceRowId,
          vicenteWeek27.sourceRowId,
        );
        final lateCandidate = week27Vicente.evaluatedCandidates.singleWhere(
          (candidate) =>
              candidate.statementRow.sourceRowId ==
              vicenteWeek27OneDayLate.sourceRowId,
        );
        expect(lateCandidate.daysAfterPeriodEnd, 6);
        expect(lateCandidate.isEligible, isFalse);
        expect(
          lateCandidate.reasons,
          contains(PayrollCandidateReason.dateOutsideWindow),
        );

        final managerCandidates = result.lineResults
            .where((line) => line.voucherLine.employeeId == vicenteId)
            .expand((line) => line.evaluatedCandidates)
            .where(
              (candidate) =>
                  candidate.statementRow.sourceRowId ==
                  vicenteManagerTransfer.sourceRowId,
            )
            .toList(growable: false);
        expect(managerCandidates, hasLength(4));
        expect(
          managerCandidates.map((candidate) => candidate.isEligible),
          everyElement(isFalse),
        );
        expect(
          managerCandidates.map((candidate) => candidate.reasons),
          everyElement(
            contains(PayrollCandidateReason.amountOutsideTolerance),
          ),
        );

        final guillermoLines = result.lineResults
            .where((line) => line.voucherLine.employeeId == guillermoId)
            .toList(growable: false);
        expect(guillermoLines, hasLength(4));
        final guillermoByLineId = <String, PayrollReconciliationLineResult>{
          for (final line in guillermoLines) line.voucherLine.lineId: line,
        };
        expect(
          guillermoByLineId['line-week-29-guillermo']!.status,
          PayrollLineMatchStatus.suggested,
        );
        expect(
          guillermoLines
              .where(
                (line) => line.voucherLine.lineId != 'line-week-29-guillermo',
              )
              .map((line) => line.status),
          everyElement(PayrollLineMatchStatus.unmatched),
        );
        expect(
          result.proposedMatches.map(
            (proposal) => proposal.voucherLine.employeeId,
          ),
          contains(guillermoId),
        );

        expect(
          result.unmatchedOutgoingRows,
          <PayrollStatementRow>[
            vicenteWeek27OneDayLate,
            vicenteManagerTransfer,
          ],
        );
      },
    );
  });

  group('foreign outgoing proof', () {
    const week = PayrollCivilDate(2026, 7, 27);

    test('marks foreign only the outgoing rows that name no employee anywhere',
        () {
      final supplier = _outgoingRow(
        rowNumber: 1,
        date: week,
        description: 'PAGO PROVEEDOR SODIMAC',
        amountClp: 89990,
        beneficiaryObserved: 'Sodimac SA',
      );
      final namedInDescription = _outgoingRow(
        rowNumber: 2,
        date: week,
        description: 'Transferencia a Persona Uno',
        amountClp: 22000,
      );
      final namedInObservedOnly = _outgoingRow(
        rowNumber: 3,
        date: week,
        description: 'TEF 991284',
        amountClp: 15000,
        beneficiaryObserved: 'Persona Uno',
      );
      final namedByAlias = _outgoingRow(
        rowNumber: 4,
        date: week,
        description: 'Abono cta PUNO SPA',
        amountClp: 30000,
      );
      final incoming = PayrollStatementRow(
        bookingDate: week,
        description: 'DEPOSITO CLIENTE MAYORISTA',
        documentNumber: 'doc-5',
        debitAmountClp: null,
        creditAmountClp: 500000,
        balanceAmountClp: 1500000,
        direction: PayrollStatementMovementDirection.incoming,
        evidence: const PayrollStatementRowEvidence(
          sourceRowNumber: 5,
          startPageNumber: 1,
          startLineNumber: 5,
          endPageNumber: 1,
          endLineNumber: 5,
        ),
      );

      final result = matcher.match(
        statementRows: [
          supplier,
          namedInDescription,
          namedInObservedOnly,
          namedByAlias,
          incoming,
        ],
        employees: [
          _employee(
            id: 'employee-one',
            name: 'Persona Uno',
            aliases: const ['PUNO SPA'],
          ),
        ],
        voucherLines: [
          _line(
            id: 'line-one',
            employeeId: 'employee-one',
            periodEnd: week,
            pendingAmountClp: 128000,
          ),
        ],
      );

      // Only the supplier row is provably foreign. Worker-named rows stay
      // out of the set no matter where the bank printed the name, and an
      // incoming credit is never part of the outgoing proof.
      expect(
        result.foreignOutgoingSourceRowIds,
        {supplier.sourceRowId},
      );
    });

    test(
        'a row naming a worker whose line is ineligible or absent is never '
        'foreign', () {
      final cashWorkerRow = _outgoingRow(
        rowNumber: 1,
        date: week,
        description: 'Transferencia a Persona Efectivo',
        amountClp: 40000,
      );
      final linelessWorkerRow = _outgoingRow(
        rowNumber: 2,
        date: week,
        description: 'Transferencia a Persona Retirada',
        amountClp: 22000,
      );

      final result = matcher.match(
        statementRows: [cashWorkerRow, linelessWorkerRow],
        employees: [
          _employee(
            id: 'employee-cash',
            name: 'Persona Efectivo',
            paymentMethod: PayrollReconciliationPaymentMethod.cash,
          ),
          _employee(id: 'employee-retired', name: 'Persona Retirada'),
        ],
        voucherLines: [
          _line(
            id: 'line-cash',
            employeeId: 'employee-cash',
            periodEnd: week,
            pendingAmountClp: 40000,
            paymentMethod: PayrollReconciliationPaymentMethod.cash,
          ),
        ],
      );

      // The cash worker normally prefers cash and the retired worker has no
      // line at all: neither row may be absorbed as foreign, because both
      // still name a real worker and require an explicit payroll decision.
      expect(result.foreignOutgoingSourceRowIds, isEmpty);
    });

    group('sueldo semanal plano: varias semanas iguales (caso real)', () {
      // Cartola real del taller, 2026-08-10. Lucas Pacheco tiene TRES semanas
      // seguidas de exactamente $35.000 y el banco muestra DOS traspasos de
      // $35.000 (29/07 y 04/08). La ventana estricta cierre..cierre+5 hace que
      // el primero sólo pueda pagar la semana 30 y el segundo sólo la 31; una
      // fecha anterior al cierre de la semana siguiente nunca se repite allí.
      PayrollStatementRow pago(int rowNumber, int month, int day) =>
          _outgoingRow(
            rowNumber: rowNumber,
            date: PayrollCivilDate(2026, month, day),
            description: 'App-traspaso A: Lucas Pacheco',
            amountClp: 35000,
          );

      PayrollReconciliationVoucherLine semana(
        String id,
        int startMonth,
        int startDay,
        int endMonth,
        int endDay,
      ) =>
          PayrollReconciliationVoucherLine(
            lineId: id,
            voucherId: 'v-$id',
            employeeId: 'employee-lucas',
            periodStart: PayrollCivilDate(2026, startMonth, startDay),
            periodEnd: PayrollCivilDate(2026, endMonth, endDay),
            pendingAmountClp: 35000,
            paymentMethod: PayrollReconciliationPaymentMethod.transfer,
          );

      test('cada pago queda sólo en la semana cuyo cierre ya ocurrió', () {
        final result = matcher.match(
          statementRows: [pago(1, 7, 29), pago(2, 8, 4)],
          employees: [_employee(id: 'employee-lucas', name: 'Lucas Pacheco')],
          voucherLines: [
            semana('semana-30', 7, 20, 7, 26),
            semana('semana-31', 7, 27, 8, 2),
            semana('semana-32', 8, 3, 8, 9),
          ],
        );

        final byLine = <String, PayrollReconciliationLineResult>{
          for (final lineResult in result.lineResults)
            lineResult.voucherLine.lineId: lineResult,
        };

        expect(byLine['semana-30']!.status, PayrollLineMatchStatus.suggested);
        expect(
          byLine['semana-30']!.proposedMatch!.statementRow.bookingDate,
          const PayrollCivilDate(2026, 7, 29),
        );

        expect(byLine['semana-31']!.status, PayrollLineMatchStatus.suggested);
        expect(
          byLine['semana-31']!.proposedMatch!.statementRow.bookingDate,
          const PayrollCivilDate(2026, 8, 4),
        );
        expect(
          byLine['semana-31']!.reasons,
          contains(PayrollLineMatchReason.uniqueCandidate),
        );

        // La tercera semana aún no cerraba en ninguna de las dos fechas.
        expect(byLine['semana-32']!.status, PayrollLineMatchStatus.unmatched);
        expect(
          byLine['semana-32']!.reasons,
          contains(PayrollLineMatchReason.noEligibleTransaction),
        );

        // Los dos pagos quedan usados: ninguno vuelve a aparecer como cargo
        // suelto «sin persona asignada».
        expect(result.unmatchedOutgoingRows, isEmpty);
      });

      test('las ventanas semanales no reutilizan un movimiento', () {
        final result = matcher.match(
          statementRows: [pago(1, 7, 29), pago(2, 8, 4)],
          employees: [_employee(id: 'employee-lucas', name: 'Lucas Pacheco')],
          voucherLines: [
            semana('semana-30', 7, 20, 7, 26),
            semana('semana-31', 7, 27, 8, 2),
          ],
        );
        expect(
          result.proposedMatches
              .map((proposal) => proposal.statementRow.sourceRowId)
              .toSet(),
          hasLength(2),
        );
        for (final line in result.lineResults) {
          expect(line.reasons, [PayrollLineMatchReason.uniqueCandidate]);
          expect(line.proposedMatch!.confidence, PayrollMatchConfidence.high);
        }
      });

      test('dos pagos iguales para UNA sola semana siguen siendo pregunta', () {
        // Acá no hay orden que resuelva nada: pueden ser un pago partido, un
        // duplicado o un pago que no era de nómina. Se queda con el humano.
        final result = matcher.match(
          statementRows: [pago(1, 7, 28), pago(2, 7, 29)],
          employees: [_employee(id: 'employee-lucas', name: 'Lucas Pacheco')],
          voucherLines: [semana('semana-30', 7, 20, 7, 26)],
        );
        final lineResult = result.lineResults.single;
        expect(lineResult.status, PayrollLineMatchStatus.needsReview);
        expect(lineResult.proposedMatch, isNull);
        expect(
          lineResult.reasons,
          contains(PayrollLineMatchReason.multipleTransactionsForLine),
        );
      });

      test('la asignación es estable: el orden de entrada no la cambia', () {
        List<String?> assign(List<PayrollStatementRow> rows) {
          final result = matcher.match(
            statementRows: rows,
            employees: [_employee(id: 'employee-lucas', name: 'Lucas Pacheco')],
            voucherLines: [
              semana('semana-30', 7, 20, 7, 26),
              semana('semana-31', 7, 27, 8, 2),
            ],
          );
          return [
            for (final line in result.lineResults)
              line.proposedMatch?.statementRow.sourceRowId,
          ];
        }

        expect(
          assign([pago(1, 7, 29), pago(2, 8, 4)]),
          assign([pago(2, 8, 4), pago(1, 7, 29)]),
        );
      });
    });

    group('el banco imprime el nombre corto (caso real, 2026-08-10)', () {
      // Cartola real del taller, verificada contra producción el 2026-08-10:
      // el banco imprime `App-traspaso A: Fernando Tapia` —el rótulo de la
      // libreta de transferencias— mientras la ficha del ERP dice
      // `Fernando José Tapia Carrillo`. Sin esto, su sueldo aparecía como un
      // cargo suelto «sin persona asignada» y su semana como una obligación
      // «que nadie nombra»: las dos mitades del mismo pago, sin juntarse.
      const week28End = PayrollCivilDate(2026, 7, 12);

      PayrollStatementRow fernandoTransfer({int amountClp = 52000}) =>
          _outgoingRow(
            rowNumber: 1,
            date: const PayrollCivilDate(2026, 7, 14),
            description: 'App-traspaso A: Fernando Tapia',
            beneficiaryObserved: 'Fernando Tapia',
            amountClp: amountClp,
          );

      test('propone el pago, y lo dice con la razón correcta', () {
        final result = matcher.match(
          statementRows: [fernandoTransfer()],
          employees: [
            _employee(
              id: 'employee-fernando',
              name: 'Fernando José Tapia Carrillo',
            ),
          ],
          voucherLines: [
            _line(
              id: 'line-week-28',
              employeeId: 'employee-fernando',
              periodEnd: week28End,
              pendingAmountClp: 52000,
            ),
          ],
        );

        final lineResult = result.lineResults.single;
        expect(lineResult.status, PayrollLineMatchStatus.suggested);
        final proposal = lineResult.proposedMatch!;
        expect(
          proposal.beneficiaryMatchKind,
          PayrollBeneficiaryMatchKind.shortName,
        );
        expect(proposal.normalizedMatchedBeneficiary, 'fernando tapia');
        expect(
          proposal.reasons,
          contains(PayrollCandidateReason.shortNameMatched),
        );
        expect(
          proposal.reasons,
          isNot(contains(PayrollCandidateReason.primaryNameMatched)),
        );
      });

      test('una forma corta NUNCA llega a confianza alta', () {
        // Monto exacto y fecha dentro de la ventana: con el nombre registrado
        // esto sería `high`. Con una deducción del propio ERP no puede serlo —
        // la identidad es justo lo que queda por mirar.
        final derived = matcher.match(
          statementRows: [fernandoTransfer()],
          employees: [
            _employee(
              id: 'employee-fernando',
              name: 'Fernando José Tapia Carrillo',
            ),
          ],
          voucherLines: [
            _line(
              id: 'line-week-28',
              employeeId: 'employee-fernando',
              periodEnd: week28End,
              pendingAmountClp: 52000,
            ),
          ],
        );
        expect(
          derived.lineResults.single.proposedMatch!.confidence,
          PayrollMatchConfidence.medium,
        );

        final registered = matcher.match(
          statementRows: [
            _outgoingRow(
              rowNumber: 1,
              date: const PayrollCivilDate(2026, 7, 14),
              description: 'App-traspaso A: Fernando José Tapia Carrillo',
              amountClp: 52000,
            ),
          ],
          employees: [
            _employee(
              id: 'employee-fernando',
              name: 'Fernando José Tapia Carrillo',
            ),
          ],
          voucherLines: [
            _line(
              id: 'line-week-28',
              employeeId: 'employee-fernando',
              periodEnd: week28End,
              pendingAmountClp: 52000,
            ),
          ],
        );
        expect(
          registered.lineResults.single.proposedMatch!.confidence,
          PayrollMatchConfidence.high,
          reason: 'el nombre completo sí puede ser alta; la deducción no',
        );
      });

      test('dos nombres de pila sin apellido no identifican a nadie', () {
        // `Fernando José` es la forma que chocaría con cualquier otro Fernando
        // del taller, así que no se genera.
        expect(
          payrollShortNameForms('Fernando José Tapia Carrillo'),
          isNot(contains('fernando jose')),
        );
        expect(
          payrollShortNameForms('Fernando José Tapia Carrillo'),
          containsAll(<String>[
            'fernando tapia',
            'fernando carrillo',
            'fernando jose tapia',
            'fernando tapia carrillo',
          ]),
        );
        // Un nombre de dos palabras ya se compara completo: no deriva nada.
        expect(payrollShortNameForms('Lucas Pacheco'), isEmpty);

        // Con tres tokens no se puede asumir que los dos últimos sean
        // apellidos. `Pablo` puede ser un segundo nombre; sólo el token final
        // es apellido en ambas formas chilenas posibles.
        expect(
          payrollShortNameForms('Juan Pablo Soto'),
          <String>{'juan soto'},
        );
      });

      test('otro apellido con el mismo nombre de pila no calza', () {
        final result = matcher.match(
          statementRows: [
            _outgoingRow(
              rowNumber: 1,
              date: const PayrollCivilDate(2026, 7, 14),
              description: 'App-traspaso A: Fernando Soto',
              amountClp: 52000,
            ),
          ],
          employees: [
            _employee(
              id: 'employee-fernando',
              name: 'Fernando José Tapia Carrillo',
            ),
          ],
          voucherLines: [
            _line(
              id: 'line-week-28',
              employeeId: 'employee-fernando',
              periodEnd: week28End,
              pendingAmountClp: 52000,
            ),
          ],
        );
        expect(
          result.lineResults.single.status,
          PayrollLineMatchStatus.unmatched,
        );
        expect(
          result.lineResults.single.reasons,
          contains(PayrollLineMatchReason.noBeneficiaryMatch),
        );
      });

      test('si la forma corta calza con dos personas, decide un humano', () {
        final result = matcher.match(
          statementRows: [fernandoTransfer()],
          employees: [
            _employee(
              id: 'employee-uno',
              name: 'Fernando José Tapia Carrillo',
            ),
            _employee(
              id: 'employee-dos',
              name: 'Fernando Andrés Tapia Soto',
            ),
          ],
          voucherLines: [
            _line(
              id: 'line-uno',
              employeeId: 'employee-uno',
              periodEnd: week28End,
              pendingAmountClp: 52000,
            ),
            _line(
              id: 'line-dos',
              employeeId: 'employee-dos',
              periodEnd: week28End,
              pendingAmountClp: 52000,
            ),
          ],
        );

        expect(result.proposedMatches, isEmpty);
        for (final lineResult in result.lineResults) {
          expect(lineResult.status, PayrollLineMatchStatus.needsReview);
          expect(
            lineResult.reasons,
            contains(
              PayrollLineMatchReason.transactionMatchesMultipleEmployees,
            ),
          );
        }
      });

      test('una ficha duplicada sin líneas no le quita el calce al que trabaja',
          () {
        // Producción tiene DOS fichas de la misma persona: `Fernando Tapia`
        // (creada 2025-10-27, sin ninguna línea de nómina) y `Fernando José
        // Tapia Carrillo`, que es quien tiene las 31 semanas. La ambigüedad se
        // mide entre OBLIGACIONES, no entre fichas: una ficha sin líneas no
        // compite por el movimiento.
        final result = matcher.match(
          statementRows: [fernandoTransfer()],
          employees: [
            _employee(
              id: 'employee-fernando',
              name: 'Fernando José Tapia Carrillo',
            ),
            _employee(id: 'employee-duplicado', name: 'Fernando Tapia'),
          ],
          voucherLines: [
            _line(
              id: 'line-week-28',
              employeeId: 'employee-fernando',
              periodEnd: week28End,
              pendingAmountClp: 52000,
            ),
          ],
        );

        expect(
          result.lineResults.single.status,
          PayrollLineMatchStatus.suggested,
        );
        expect(result.unmatchedOutgoingRows, isEmpty);
      });

      test('un cargo con el nombre corto no se archiva solo como ajeno', () {
        // Sin la ficha duplicada que hoy lo salva por accidente, el sueldo se
        // clasificaba solo como «no es nómina». La prueba de ajenidad también
        // reconoce la forma corta, y esa dirección sólo puede devolver filas a
        // una decisión explícita.
        final result = matcher.match(
          statementRows: [fernandoTransfer(amountClp: 99000)],
          employees: [
            _employee(
              id: 'employee-fernando',
              name: 'Fernando José Tapia Carrillo',
            ),
          ],
          voucherLines: [
            _line(
              id: 'line-week-28',
              employeeId: 'employee-fernando',
              periodEnd: week28End,
              pendingAmountClp: 52000,
            ),
          ],
        );
        expect(result.foreignOutgoingSourceRowIds, isEmpty);
      });
    });

    test('a legacy result without the proof classifies nothing as foreign', () {
      final result = PayrollStatementReconciliationResult(
        statementRows: const [],
        lineResults: const [],
      );
      expect(result.foreignOutgoingSourceRowIds, isEmpty);
    });
  });
}

PayrollReconciliationEmployee _employee({
  required String id,
  required String name,
  PayrollReconciliationPaymentMethod paymentMethod =
      PayrollReconciliationPaymentMethod.transfer,
  List<String> aliases = const [],
}) {
  return PayrollReconciliationEmployee(
    employeeId: id,
    displayName: name,
    paymentMethod: paymentMethod,
    bankBeneficiaryAliases: aliases,
  );
}

PayrollReconciliationVoucherLine _line({
  required String id,
  required String employeeId,
  required PayrollCivilDate periodEnd,
  required int pendingAmountClp,
  PayrollReconciliationPaymentMethod paymentMethod =
      PayrollReconciliationPaymentMethod.transfer,
}) {
  final periodEndDate =
      DateTime(periodEnd.year, periodEnd.month, periodEnd.day);
  final periodStartDate = periodEndDate.subtract(const Duration(days: 6));
  return PayrollReconciliationVoucherLine(
    lineId: id,
    voucherId: 'voucher-$id',
    employeeId: employeeId,
    periodStart: PayrollCivilDate(
      periodStartDate.year,
      periodStartDate.month,
      periodStartDate.day,
    ),
    periodEnd: periodEnd,
    pendingAmountClp: pendingAmountClp,
    paymentMethod: paymentMethod,
  );
}

PayrollStatementRow _outgoingRow({
  required int rowNumber,
  required PayrollCivilDate date,
  required String description,
  required int amountClp,
  String? beneficiaryObserved,
}) {
  return PayrollStatementRow(
    bookingDate: date,
    description: description,
    beneficiaryObserved: beneficiaryObserved,
    documentNumber: 'doc-$rowNumber',
    debitAmountClp: amountClp,
    creditAmountClp: null,
    balanceAmountClp: 1000000 - amountClp,
    direction: PayrollStatementMovementDirection.outgoing,
    evidence: PayrollStatementRowEvidence(
      sourceRowNumber: rowNumber,
      startPageNumber: 1,
      startLineNumber: rowNumber,
      endPageNumber: 1,
      endLineNumber: rowNumber,
    ),
  );
}
