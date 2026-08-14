import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/accounting/bank_reconciliation/models/bank_reconciliation_models.dart';
import 'package:vinabike_erp/modules/accounting/bank_reconciliation/services/bank_reconciliation_matcher.dart';

void main() {
  const matcher = BankReconciliationMatcher();

  test('unique exact direct match starts selected and stays editable', () {
    final movement = _movement(
      id: 'row-1',
      date: const BankCivilDate(2026, 8, 12),
      direction: BankMovementDirection.debit,
      amount: 42000,
      description: 'Transferencia a Proveedor Bicicletas Uno',
    );
    final candidate = _candidate(
      id: 'payment-1',
      kind: BankReconciliationTargetKind.purchasePayment,
      date: const BankCivilDate(2026, 8, 10),
      direction: BankMovementDirection.debit,
      amount: 42000,
      label: 'Compra FC-88',
      counterparty: 'Proveedor Bicicletas Uno',
    );

    final proposals = matcher.match(
      movements: [movement],
      candidates: [candidate],
    )['row-1']!;

    expect(proposals, hasLength(1));
    expect(proposals.single.confidence, BankReconciliationConfidence.high);
    expect(proposals.single.isSelectedByDefault, isTrue);

    final row = BankReconciliationRowDraft(
      movement: movement,
      proposals: proposals,
    );
    expect(row.selectedProposal, isNotNull);
    expect(row.copyWith(clearSelection: true).selectedProposal, isNull);
  });

  test('same-score candidates require an explicit human choice', () {
    final movement = _movement(
      id: 'row-ambiguous',
      date: const BankCivilDate(2026, 8, 12),
      direction: BankMovementDirection.debit,
      amount: 35000,
      description: 'Transferencia proveedor',
    );
    final candidates = [
      _candidate(
        id: 'expense-1',
        kind: BankReconciliationTargetKind.expensePayment,
        date: const BankCivilDate(2026, 8, 11),
        direction: BankMovementDirection.debit,
        amount: 35000,
        label: 'Gasto GTO-1',
        counterparty: 'Proveedor',
      ),
      _candidate(
        id: 'expense-2',
        kind: BankReconciliationTargetKind.expensePayment,
        date: const BankCivilDate(2026, 8, 11),
        direction: BankMovementDirection.debit,
        amount: 35000,
        label: 'Gasto GTO-2',
        counterparty: 'Proveedor',
      ),
    ];

    final proposals = matcher.match(
      movements: [movement],
      candidates: candidates,
    )['row-ambiguous']!;

    expect(proposals, hasLength(2));
    expect(
      proposals.every((proposal) => !proposal.isSelectedByDefault),
      isTrue,
    );
    expect(
      proposals.every(
        (proposal) =>
            proposal.confidence == BankReconciliationConfidence.medium,
      ),
      isTrue,
    );
  });

  test('booking date ranks nearby operations but is not exact-event truth', () {
    final movement = _movement(
      id: 'row-date',
      date: const BankCivilDate(2026, 8, 12),
      direction: BankMovementDirection.credit,
      amount: 18000,
      description: 'Transferencia cliente Ana',
    );
    final withinWindow = _candidate(
      id: 'sale-1',
      kind: BankReconciliationTargetKind.salesPayment,
      date: const BankCivilDate(2026, 8, 8),
      direction: BankMovementDirection.credit,
      amount: 18000,
      label: 'Venta FV-1',
      counterparty: 'Ana',
    );
    final outsideWindow = _candidate(
      id: 'sale-2',
      kind: BankReconciliationTargetKind.salesPayment,
      date: const BankCivilDate(2026, 8, 6),
      direction: BankMovementDirection.credit,
      amount: 18000,
      label: 'Venta FV-2',
      counterparty: 'Ana',
    );

    final proposals = matcher.match(
      movements: [movement],
      candidates: [withinWindow, outsideWindow],
    )['row-date']!;

    expect(proposals, hasLength(1));
    expect(proposals.single.allocations.single.candidate.targetId, 'sale-1');
    expect(proposals.single.isSelectedByDefault, isFalse);
  });

  test('direct amount tolerance is inclusive at 1000 and closed at 1001', () {
    final candidate = _candidate(
      id: 'expense-tolerance',
      kind: BankReconciliationTargetKind.expensePayment,
      date: const BankCivilDate(2026, 8, 11),
      direction: BankMovementDirection.debit,
      amount: 50000,
      label: 'Gasto proveedor exacto',
      counterparty: 'Proveedor exacto',
    );
    final allowed = _movement(
      id: 'row-allowed',
      date: const BankCivilDate(2026, 8, 12),
      direction: BankMovementDirection.debit,
      amount: 51000,
      description: 'Transferencia proveedor exacto',
    );
    final rejected = _movement(
      id: 'row-rejected',
      date: const BankCivilDate(2026, 8, 12),
      direction: BankMovementDirection.debit,
      amount: 51001,
      description: 'Transferencia proveedor exacto',
    );

    final proposals = matcher.match(
      movements: <BankStatementMovement>[allowed, rejected],
      candidates: <BankReconciliationCandidate>[candidate],
    );

    expect(proposals['row-allowed'], hasLength(1));
    expect(proposals['row-allowed']!.single.isSelectedByDefault, isFalse);
    expect(proposals['row-rejected'], isEmpty);
  });

  test('Transbank builds a many-to-one estimate and never auto-selects it', () {
    final movement = _movement(
      id: 'row-transbank',
      date: const BankCivilDate(2026, 8, 12),
      direction: BankMovementDirection.credit,
      amount: 95000,
      description: 'Pago: Abonos Debito Y Credito Transbank 0966893109',
    );
    final candidates = [
      _cardSale('sale-a', const BankCivilDate(2026, 8, 10), 60000),
      _cardSale('sale-b', const BankCivilDate(2026, 8, 11), 40000),
    ];

    final proposals = matcher.match(
      movements: [movement],
      candidates: candidates,
    )['row-transbank']!;

    expect(proposals, isNotEmpty);
    final proposal = proposals.first;
    expect(
      proposal.matchKind,
      BankReconciliationMatchKind.transbankEstimate,
    );
    expect(proposal.isSelectedByDefault, isFalse);
    expect(proposal.allocations, hasLength(2));
    expect(proposal.allocatedBankAmountClp, 95000);
    expect(proposal.estimatedGrossClp, 100000);
    expect(proposal.estimatedDifferenceClp, 5000);
    expect(proposal.instrument, BankPaymentInstrument.unknown);
    expect(proposal.reasons.join(' '), contains('débito, crédito o prepago'));
  });

  test('Transbank can estimate one rail without swallowing the whole window',
      () {
    final movement = _movement(
      id: 'row-transbank-split-rail',
      date: const BankCivilDate(2026, 8, 7),
      direction: BankMovementDirection.credit,
      amount: 39034,
      description: 'Pago: Abonos Debito Y Credito Transbank 0966893109',
    );
    final candidates = [
      _cardSale('sale-04', const BankCivilDate(2026, 8, 4), 28000),
      _cardSale('sale-05', const BankCivilDate(2026, 8, 5), 41000),
      _cardSale('sale-06', const BankCivilDate(2026, 8, 6), 88000),
    ];

    final proposals = matcher.match(
      movements: [movement],
      candidates: candidates,
    )['row-transbank-split-rail']!;

    expect(proposals, isNotEmpty);
    expect(proposals.first.estimatedGrossClp, 41000);
    expect(proposals.first.estimatedDifferenceClp, 1966);
    expect(
      proposals.first.allocations.single.candidate.targetId,
      'sale-05',
    );
    expect(proposals.first.isSelectedByDefault, isFalse);
    expect(proposals.first.instrument, BankPaymentInstrument.unknown);
  });

  test('Transbank rejects an implausible deduction instead of forcing a link',
      () {
    final movement = _movement(
      id: 'row-transbank-bad',
      date: const BankCivilDate(2026, 8, 12),
      direction: BankMovementDirection.credit,
      amount: 50000,
      description: 'Abonos Debito y Credito Transbank',
    );

    final proposals = matcher.match(
      movements: [movement],
      candidates: [_cardSale('sale', const BankCivilDate(2026, 8, 11), 100000)],
    )['row-transbank-bad']!;

    expect(proposals, isEmpty);
  });

  test('20 Jul Transbank 80.609 gets an editable accounting-date estimate', () {
    final movement = _movement(
      id: 'transbank-20-jul',
      date: const BankCivilDate(2026, 7, 20),
      direction: BankMovementDirection.credit,
      amount: 80609,
      description: 'Pago Abonos Debito Y Credito Transbank 0966893109',
    );
    final candidates = <BankReconciliationCandidate>[
      _cardSale('13-a', const BankCivilDate(2026, 7, 13), 13000),
      _cardSale('13-b', const BankCivilDate(2026, 7, 13), 46000),
      _cardSale('13-c', const BankCivilDate(2026, 7, 13), 115000),
      _cardSale('14-a', const BankCivilDate(2026, 7, 14), 9000),
      _cardSale('14-b', const BankCivilDate(2026, 7, 14), 154000),
      _cardSale('15-a', const BankCivilDate(2026, 7, 15), 7000),
      _cardSale('15-b', const BankCivilDate(2026, 7, 15), 24000),
      _cardSale('20-a', const BankCivilDate(2026, 7, 20), 2000),
      _cardSale('20-b', const BankCivilDate(2026, 7, 20), 24000),
      _cardSale('20-c', const BankCivilDate(2026, 7, 20), 27000),
    ];

    final proposals = matcher.match(
      movements: <BankStatementMovement>[movement],
      candidates: candidates,
    )['transbank-20-jul']!;

    expect(proposals, isNotEmpty);
    expect(
        proposals.every((proposal) => !proposal.isSelectedByDefault), isTrue);
    expect(
      proposals.every((proposal) =>
          proposal.matchKind == BankReconciliationMatchKind.transbankEstimate),
      isTrue,
    );
    expect(proposals.first.estimatedGrossClp, greaterThanOrEqualTo(80609));
    expect(proposals.first.reasons.join(' '), contains('fecha de la cartola'));
  });

  test('22 Jul Transbank 62.156 can include same-day card sales', () {
    final movement = _movement(
      id: 'transbank-22-jul',
      date: const BankCivilDate(2026, 7, 22),
      direction: BankMovementDirection.credit,
      amount: 62156,
      description: 'Pago Abonos Debito Y Credito Transbank 0966893109',
    );
    final candidates = <BankReconciliationCandidate>[
      _cardSale('15-a', const BankCivilDate(2026, 7, 15), 7000),
      _cardSale('15-b', const BankCivilDate(2026, 7, 15), 24000),
      _cardSale('20-a', const BankCivilDate(2026, 7, 20), 2000),
      _cardSale('20-b', const BankCivilDate(2026, 7, 20), 24000),
      _cardSale('20-c', const BankCivilDate(2026, 7, 20), 27000),
      _cardSale('22-a', const BankCivilDate(2026, 7, 22), 20000),
    ];

    final proposals = matcher.match(
      movements: <BankStatementMovement>[movement],
      candidates: candidates,
    )['transbank-22-jul']!;

    expect(proposals, isNotEmpty);
    expect(
        proposals.every((proposal) => !proposal.isSelectedByDefault), isTrue);
    expect(
      proposals.expand((proposal) => proposal.allocations).any(
            (allocation) => allocation.candidate.targetId == '22-a',
          ),
      isTrue,
    );
  });
}

BankStatementMovement _movement({
  required String id,
  required BankCivilDate date,
  required BankMovementDirection direction,
  required int amount,
  required String description,
}) {
  return BankStatementMovement(
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
}

BankReconciliationCandidate _candidate({
  required String id,
  required BankReconciliationTargetKind kind,
  required BankCivilDate date,
  required BankMovementDirection direction,
  required int amount,
  required String label,
  String? counterparty,
}) {
  return BankReconciliationCandidate(
    targetKind: kind,
    targetId: id,
    direction: direction,
    amountClp: amount,
    occurredOn: date,
    label: label,
    counterparty: counterparty,
  );
}

BankReconciliationCandidate _cardSale(
  String id,
  BankCivilDate date,
  int amount,
) {
  return BankReconciliationCandidate(
    targetKind: BankReconciliationTargetKind.salesPayment,
    targetId: id,
    direction: BankMovementDirection.credit,
    amountClp: amount,
    occurredOn: date,
    label: 'Venta $id',
    paymentMethodCode: 'card',
    provider: BankSettlementProvider.transbank,
    instrument: BankPaymentInstrument.unknown,
  );
}
