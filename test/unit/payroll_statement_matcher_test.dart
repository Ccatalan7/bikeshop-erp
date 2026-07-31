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
      expect(proposal.allowedToleranceClp, 500);
      expect(proposal.confidence, PayrollMatchConfidence.high);
      expect(proposal.requiresHumanConfirmation, isTrue);
      expect(
        proposal.reasons,
        contains(PayrollCandidateReason.nonZeroVariance),
      );
    });

    test('never auto-suggests an underpayment, even inside rounding tolerance',
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
      expect(lineResult.status, PayrollLineMatchStatus.unmatched);
      expect(lineResult.proposedMatch, isNull);
      expect(result.proposedMatches, isEmpty);
      expect(result.unmatchedOutgoingRows, [partialDebit]);

      final evaluated = lineResult.evaluatedCandidates.single;
      expect(evaluated.amountVarianceClp, -250);
      expect(evaluated.allowedToleranceClp, 500);
      expect(
        evaluated.isEligible,
        isFalse,
        reason: 'A smaller bank debit is a possible partial payment that '
            'requires an explicit manual link, never a rounding suggestion.',
      );
      expect(
        evaluated.reasons,
        contains(PayrollCandidateReason.amountBelowPendingBalance),
      );
    });

    test('keeps an overpayment beyond rounding tolerance ineligible', () {
      final excessiveDebit = _outgoingRow(
        rowNumber: 1,
        date: const PayrollCivilDate(2026, 7, 27),
        description: 'Transferencia a Persona Exceso',
        amountClp: 128251,
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
      expect(evaluated.amountVarianceClp, 501);
      expect(evaluated.allowedToleranceClp, 500);
      expect(evaluated.isEligible, isFalse);
      expect(
        evaluated.reasons,
        contains(PayrollCandidateReason.amountOutsideTolerance),
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

    test('never evaluates a cash worker as a transfer match', () {
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
      expect(lineResult.status, PayrollLineMatchStatus.ineligible);
      expect(lineResult.proposedMatch, isNull);
      expect(lineResult.evaluatedCandidates, isEmpty);
      expect(
        lineResult.reasons,
        [PayrollLineMatchReason.paymentMethodIsCash],
      );
    });

    test('requires both the 500 CLP cap and the one-percent tolerance', () {
      final result = matcher.match(
        statementRows: [
          _outgoingRow(
            rowNumber: 1,
            date: const PayrollCivilDate(2026, 7, 21),
            description: 'Transferencia a Persona Cinco',
            amountClp: 10400,
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
      expect(evaluated.allowedToleranceClp, 100);
      expect(evaluated.amountVarianceClp, 400);
      expect(evaluated.isEligible, isFalse);
      expect(result.proposedMatches, isEmpty);
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
        expect(
          lineResult.reasons,
          contains(
            PayrollLineMatchReason.transactionMatchesMultipleLines,
          ),
        );
      }
    });

    test('uses an inclusive civil-date window ending five days after close',
        () {
      final result = matcher.match(
        statementRows: [
          _outgoingRow(
            rowNumber: 1,
            date: const PayrollCivilDate(2026, 7, 24),
            description: 'Transferencia a Persona Tres',
            amountClp: 60000,
          ),
          _outgoingRow(
            rowNumber: 2,
            date: const PayrollCivilDate(2026, 7, 25),
            description: 'Transferencia a Persona Cuatro',
            amountClp: 60000,
          ),
        ],
        employees: [
          _employee(id: 'employee-three', name: 'Persona Tres'),
          _employee(id: 'employee-four', name: 'Persona Cuatro'),
        ],
        voucherLines: [
          _line(
            id: 'line-day-five',
            employeeId: 'employee-three',
            periodEnd: const PayrollCivilDate(2026, 7, 19),
            pendingAmountClp: 60000,
          ),
          _line(
            id: 'line-day-six',
            employeeId: 'employee-four',
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

    test('accepts a salary paid during the work week but not before it', () {
      final result = matcher.match(
        statementRows: [
          _outgoingRow(
            rowNumber: 1,
            date: const PayrollCivilDate(2026, 6, 30),
            description: 'Transferencia a Persona Semana',
            amountClp: 94500,
          ),
          _outgoingRow(
            rowNumber: 2,
            date: const PayrollCivilDate(2026, 6, 28),
            description: 'Transferencia a Persona Temprana',
            amountClp: 38000,
          ),
        ],
        employees: [
          _employee(id: 'employee-week', name: 'Persona Semana'),
          _employee(id: 'employee-early', name: 'Persona Temprana'),
        ],
        voucherLines: [
          _line(
            id: 'line-week',
            employeeId: 'employee-week',
            periodEnd: const PayrollCivilDate(2026, 7, 5),
            pendingAmountClp: 94500,
          ),
          _line(
            id: 'line-too-early',
            employeeId: 'employee-early',
            periodEnd: const PayrollCivilDate(2026, 7, 5),
            pendingAmountClp: 38000,
          ),
        ],
      );

      final duringWeek = result.lineResults.singleWhere(
        (line) => line.voucherLine.lineId == 'line-week',
      );
      final beforeStart = result.lineResults.singleWhere(
        (line) => line.voucherLine.lineId == 'line-too-early',
      );
      expect(
        duringWeek.status,
        PayrollLineMatchStatus.suggested,
      );
      expect(
        duringWeek.proposedMatch!.reasons,
        contains(PayrollCandidateReason.dateWithinWindow),
      );
      expect(
        beforeStart.status,
        PayrollLineMatchStatus.unmatched,
      );
      expect(beforeStart.evaluatedCandidates, hasLength(1));
      expect(beforeStart.evaluatedCandidates.single.daysAfterPeriodEnd, -7);
      expect(
        beforeStart.evaluatedCandidates.single.reasons,
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
            'line-week-30-vicente': vicenteWeek30Rounded.sourceRowId,
            'line-week-30-lucas': lucasWeek30.sourceRowId,
          },
        );
        expect(
          result.proposedMatches
              .map((proposal) => proposal.statementRow.sourceRowId)
              .toSet(),
          hasLength(8),
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
        expect(roundedProposal.allowedToleranceClp, 500);
        expect(
          roundedProposal.reasons,
          contains(PayrollCandidateReason.amountWithinTolerance),
        );

        final week27Vicente = result.lineResults.singleWhere(
          (line) => line.voucherLine.lineId == 'line-week-27-vicente',
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
        expect(
          proposalsByLineId['line-week-27-vicente']!.daysAfterPeriodEnd,
          5,
          reason: 'the configured payment window includes its fifth day',
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
        expect(
          guillermoLines.map((line) => line.status),
          everyElement(PayrollLineMatchStatus.ineligible),
        );
        expect(
          guillermoLines.map((line) => line.evaluatedCandidates),
          everyElement(isEmpty),
        );
        expect(
          result.proposedMatches.map(
            (proposal) => proposal.voucherLine.employeeId,
          ),
          isNot(contains(guillermoId)),
        );

        expect(
          result.unmatchedOutgoingRows,
          <PayrollStatementRow>[
            vicenteWeek27OneDayLate,
            vicenteManagerTransfer,
            guillermoBankMovement,
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

      // The cash worker's line is ineligible for transfers and the retired
      // worker has no line at all: neither row may be absorbed as foreign,
      // because both plausibly pay a real worker outside the expected flow.
      expect(result.foreignOutgoingSourceRowIds, isEmpty);
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
