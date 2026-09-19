import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/accounting/bank_reconciliation/models/bank_reconciliation_models.dart';
import 'package:vinabike_erp/modules/accounting/bank_reconciliation/services/bank_reconciliation_third_party.dart';

BankStatementMovement _movement(
  String id,
  BankCivilDate date,
  BankMovementDirection direction,
  int amount,
  String description,
) =>
    BankStatementMovement(
      sourceRowId: id,
      ordinal: 1,
      bookingDate: date,
      description: description,
      normalizedDescription: description.toLowerCase(),
      direction: direction,
      amountClp: amount,
      sourcePage: 1,
      sourceLineStart: 1,
      sourceLineEnd: 1,
    );

BankReconciliationCandidate _operation(
  String id,
  BankReconciliationTargetKind kind,
  BankMovementDirection direction,
  int amount,
  BankCivilDate date,
  String counterparty,
) =>
    BankReconciliationCandidate(
      targetKind: kind,
      targetId: id,
      direction: direction,
      amountClp: amount,
      occurredOn: date,
      label: '$id · $counterparty',
      counterparty: counterparty,
    );

void main() {
  const finder = BankThirdPartyFinder();

  test('a repayment to somebody else is the batch it settled', () {
    // Week 29: the owner's mother paid Vicente and Lucas; Nómina registered
    // both on 12 August; he repaid her $133.000 on 7 July.
    final found = finder.find(
      movements: [
        _movement(
            'mother',
            const BankCivilDate(2026, 7, 7),
            BankMovementDirection.debit,
            133000,
            'App-traspaso A: Maria Angelica Sandoval'),
      ],
      proposals: const {},
      candidates: [
        _operation(
            'vicente',
            BankReconciliationTargetKind.expensePayment,
            BankMovementDirection.debit,
            94500,
            const BankCivilDate(2026, 8, 12),
            'Vicente Díaz'),
        _operation(
            'lucas',
            BankReconciliationTargetKind.expensePayment,
            BankMovementDirection.debit,
            38500,
            const BankCivilDate(2026, 8, 12),
            'Lucas Pacheco'),
        _operation(
            'rent',
            BankReconciliationTargetKind.expensePayment,
            BankMovementDirection.debit,
            499467,
            const BankCivilDate(2026, 7, 10),
            'Darinka Lagomarsino'),
      ],
    );

    final proposal = found['mother']!;
    expect(proposal.matchKind, BankReconciliationMatchKind.thirdParty);
    expect(proposal.isSelectedByDefault, isFalse);
    expect(proposal.confidence, BankReconciliationConfidence.medium);
    expect(proposal.allocations.map((item) => item.candidate.targetId).toSet(),
        {'vicente', 'lucas'});
    expect(proposal.allocatedBankAmountClp, 133000);
  });

  test('a sum that coincides is never proposed', () {
    BankReconciliationCandidate sale(
            String id, int amount, BankCivilDate date, String customer) =>
        _operation(id, BankReconciliationTargetKind.salesPayment,
            BankMovementDirection.credit, amount, date, customer);
    final found = finder.find(
      movements: [
        // Three customers' sales weeks apart that add up to one deposit.
        _movement('scattered', const BankCivilDate(2026, 6, 25),
            BankMovementDirection.credit, 20000, 'Traspaso De: Gregorio'),
        // Two customers' sales the same week: somebody paying for both is
        // not a sale of one customer.
        _movement('two-customers', const BankCivilDate(2026, 6, 30),
            BankMovementDirection.credit, 76000, 'Traspaso De: Patricio'),
      ],
      proposals: const {},
      candidates: [
        sale('a', 8000, const BankCivilDate(2026, 5, 26), 'Roldán Molina'),
        sale('b', 6000, const BankCivilDate(2026, 5, 20), 'Mostrador'),
        sale('c', 6000, const BankCivilDate(2026, 7, 9), 'Luis Hidalgo'),
        sale('d', 68000, const BankCivilDate(2026, 5, 25), 'Joaquín Silva'),
      ],
    );

    expect(found, isEmpty);
  });

  test('two combinations that both fit leave the question to the owner', () {
    BankReconciliationCandidate salary(String id, int amount) => _operation(
        id,
        BankReconciliationTargetKind.expensePayment,
        BankMovementDirection.debit,
        amount,
        const BankCivilDate(2026, 8, 12),
        id);
    final found = finder.find(
      movements: [
        _movement('ambiguous', const BankCivilDate(2026, 8, 13),
            BankMovementDirection.debit, 100000, 'App-traspaso A: Otra'),
      ],
      proposals: const {},
      candidates: [
        salary('a', 60000),
        salary('b', 40000),
        salary('c', 70000),
        salary('d', 30000),
      ],
    );

    expect(found, isEmpty);
  });
}
