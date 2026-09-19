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
  String counterparty, {
  String? method,
}) =>
    BankReconciliationCandidate(
      targetKind: kind,
      targetId: id,
      direction: direction,
      amountClp: amount,
      occurredOn: date,
      label: '$id · $counterparty',
      counterparty: counterparty,
      paymentMethodCode: method,
    );

/// A sale the ERP recorded as paid by transfer.
BankReconciliationCandidate _sale(
  String invoice,
  int amount,
  BankCivilDate date,
  String customer, {
  String method = 'transfer',
}) =>
    BankReconciliationCandidate(
      targetKind: BankReconciliationTargetKind.salesPayment,
      targetId: invoice,
      direction: BankMovementDirection.credit,
      amountClp: amount,
      occurredOn: date,
      label: 'Venta $invoice',
      counterparty: customer,
      counterpartyNames: [customer],
      paymentMethodCode: method,
    );

BankStatementMovement _incoming(
        String id, BankCivilDate date, int amount, String who) =>
    _movement(id, date, BankMovementDirection.credit, amount,
        'Traspaso De: $who Internet');

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

  test('a sale somebody else paid by transfer is a safe suggestion', () {
    // The owner's four, June and July 2026.
    final found = finder.find(
      movements: [
        _incoming('patricio', const BankCivilDate(2026, 6, 30), 76000,
            'Patricio Ignacio Basau'),
        _incoming('osvaldo', const BankCivilDate(2026, 7, 13), 34000,
            'Quezada Silva Osvaldo Andres'),
        _incoming('sabrina', const BankCivilDate(2026, 7, 10), 37000,
            'Sabrina Alexandra Gutierrez Bracho'),
        _incoming('fernando', const BankCivilDate(2026, 7, 9), 6000,
            'Tapia Carrillo Fernando Jose'),
      ],
      proposals: const {},
      candidates: [
        // Paid on Saturday 27 June; Monday 29 June was a holiday.
        _sale('FV-00789', 76000, const BankCivilDate(2026, 6, 27),
            'Maximo Gallardo'),
        _sale('FV-00832', 34000, const BankCivilDate(2026, 7, 13),
            'Rosita Bustamante'),
        // Paid at 18:37: the bank booked it the next banking day.
        _sale('FV-00843', 37000, const BankCivilDate(2026, 7, 9),
            'Gabriel Sanabria'),
        _sale(
            'FV-00844', 6000, const BankCivilDate(2026, 7, 9), 'Luis Hidalgo'),
        // The same amount paid in cash is no candidate.
        _sale('FV-00840', 6000, const BankCivilDate(2026, 7, 8),
            'Cliente Mostrador',
            method: 'cash'),
      ],
    );

    expect(found.keys.toSet(), {'patricio', 'osvaldo', 'sabrina', 'fernando'});
    for (final proposal in found.values) {
      expect(proposal.confidence, BankReconciliationConfidence.high);
      expect(proposal.isSelectedByDefault, isFalse);
      expect(proposal.allocations, hasLength(1));
    }
    expect(
        found['fernando']!.allocations.single.candidate.targetId, 'FV-00844');
    final saturday = found['patricio']!.reasons.join(' ');
    expect(saturday, contains('sábado 27-06'));
    expect(saturday, contains('martes 30-06'));
    expect(saturday, contains('el 29-06 fue feriado'));
    expect(
        saturday,
        contains('La pagó Patricio Ignacio Basau y no Maximo '
            'Gallardo'));
    expect(found['sabrina']!.reasons.first, contains('hecha de tarde'));
    expect(found['osvaldo']!.reasons.first, contains('el mismo día'));
  });

  test('another name is only a guess when either side has a rival', () {
    const sameDay = BankCivilDate(2026, 7, 9);
    // Two people sent $6.000 that day and the ERP has one sale.
    expect(
      finder.find(
        movements: [
          _incoming('a', sameDay, 6000, 'Fernando Tapia'),
          _incoming('b', sameDay, 6000, 'Carla Rojas'),
        ],
        proposals: const {},
        candidates: [_sale('FV-1', 6000, sameDay, 'Luis Hidalgo')],
      ),
      isEmpty,
    );
    // One transfer and two sales by transfer of that amount.
    expect(
      finder.find(
        movements: [_incoming('a', sameDay, 6000, 'Fernando Tapia')],
        proposals: const {},
        candidates: [
          _sale('FV-1', 6000, sameDay, 'Luis Hidalgo'),
          _sale('FV-2', 6000, sameDay, 'Ana Pérez'),
        ],
      ),
      isEmpty,
    );
    // A card charge is not a person; a sale recorded with another method is
    // at most a doubt (the method may be wrong), never a safe suggestion.
    final mixed = finder.find(
      movements: [
        _movement('google', sameDay, BankMovementDirection.credit, 6000,
            'Pago: Google Cloud Renca'),
        _incoming('c', sameDay, 8000, 'Fernando Tapia'),
      ],
      proposals: const {},
      candidates: [
        _sale('FV-1', 6000, sameDay, 'Luis Hidalgo'),
        _sale('FV-2', 8000, sameDay, 'Ana Pérez', method: 'cash'),
      ],
    );
    expect(mixed['google'], isNull);
    expect(mixed['c']!.confidence, BankReconciliationConfidence.medium);
  });

  test('three banking days later it is proposed, not a safe suggestion', () {
    final found = finder.find(
      movements: [
        _incoming('late', const BankCivilDate(2026, 7, 14), 37000, 'Sabrina'),
      ],
      proposals: const {},
      candidates: [
        _sale('FV-00843', 37000, const BankCivilDate(2026, 7, 9),
            'Gabriel Sanabria'),
      ],
    );

    expect(found['late']!.confidence, BankReconciliationConfidence.medium);
  });
}
