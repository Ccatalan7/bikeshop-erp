import '../models/bank_reconciliation_models.dart';

/// A bank movement that settles, in one transfer, several operations the ERP
/// recorded with other people: the owner's mother paid two salaries of week
/// 29 (Vicente $94.500, Lucas $38.500) and he repaid her $133.000 on 7 July.
/// The name the bank prints is nobody the operations name, so the matcher
/// never pairs them.
///
/// It is proposed only when exactly one combination of operations nothing
/// else explains adds up to the movement to the peso, and never selected: a
/// sum can coincide, and only the owner knows who paid what for him.
class BankThirdPartyFinder {
  const BankThirdPartyFinder({
    this.windowDays = 45,
    this.maxParts = 3,
    this.maxPool = 40,
    this.batchSpanDays = 7,
  });

  /// How far from the bank date the operations may be registered: Nómina
  /// registered July's salaries on 12 August.
  final int windowDays;
  final int maxParts;

  /// Beyond this many open operations a combination is likely to coincide.
  final int maxPool;

  /// What one person pays for another is a batch: operations of one kind
  /// registered within a week (both salaries of week 29 on 12 August). Three
  /// sales to three customers weeks apart that add up to a deposit are a
  /// coincidence.
  final int batchSpanDays;

  Map<String, BankReconciliationProposal> find({
    required List<BankStatementMovement> movements,
    required Map<String, List<BankReconciliationProposal>> proposals,
    required List<BankReconciliationCandidate> candidates,
    Set<String> skipSourceRowIds = const <String>{},
  }) {
    final claimed = <String>{
      for (final rowProposals in proposals.values)
        for (final proposal in rowProposals)
          if (proposal.isSelectedByDefault)
            for (final allocation in proposal.allocations)
              allocation.candidate.identity,
    };
    final used = <String>{};
    final found = <String, BankReconciliationProposal>{};
    final open = movements.where((movement) {
      final rowProposals = proposals[movement.sourceRowId] ??
          const <BankReconciliationProposal>[];
      return movement.amountClp != null &&
          movement.bookingDate != null &&
          movement.direction != BankMovementDirection.unknown &&
          !skipSourceRowIds.contains(movement.sourceRowId) &&
          !rowProposals.any((proposal) => proposal.isSelectedByDefault);
    }).toList(growable: false)
      ..sort((left, right) => left.bookingDate!.compareTo(right.bookingDate!));

    for (final movement in open) {
      final amount = movement.amountClp!;
      final date = movement.bookingDate!;
      final alreadyOffered = <String>{
        for (final proposal in proposals[movement.sourceRowId] ??
            const <BankReconciliationProposal>[])
          for (final allocation in proposal.allocations)
            allocation.candidate.identity,
      };
      final pool = candidates
          .where((candidate) =>
              candidate.direction == movement.direction &&
              candidate.provider == BankSettlementProvider.none &&
              candidate.targetKind !=
                  BankReconciliationTargetKind.journalEntry &&
              candidate.amountClp <= amount &&
              !alreadyOffered.contains(candidate.identity) &&
              !claimed.contains(candidate.identity) &&
              !used.contains(candidate.identity) &&
              candidate.occurredOn.daysUntil(date).abs() <= windowDays)
          .toList(growable: false);
      if (pool.isEmpty || pool.length > maxPool) continue;
      final combinations = _combinations(
        pool,
        amount,
        oneCounterparty: movement.direction == BankMovementDirection.credit,
      );
      if (combinations.length != 1) continue;
      final chosen = combinations.single;
      used.addAll(chosen.map((candidate) => candidate.identity));
      final debit = movement.direction == BankMovementDirection.debit;
      found[movement.sourceRowId] = BankReconciliationProposal(
        sourceRowId: movement.sourceRowId,
        matchKind: BankReconciliationMatchKind.thirdParty,
        confidence: BankReconciliationConfidence.medium,
        allocations: <BankReconciliationAllocationDraft>[
          for (final candidate in chosen)
            BankReconciliationAllocationDraft(
              candidate: candidate,
              bankAmountClp: candidate.amountClp,
            ),
        ],
        reasons: <String>[
          chosen.length == 1
              ? 'Monto exacto de una operación del ERP que no aparece en la '
                  'cartola, a nombre de otra persona'
              : 'Suma exacta de ${chosen.length} operaciones del ERP que no '
                  'aparecen en la cartola',
          if (chosen.length == 1)
            debit
                ? '¿La pagó alguien por ti?'
                : '¿La pagó otra persona por el cliente?'
          else if (debit)
            'La transferencia va a otra persona: ¿las pagó alguien por '
                'ti y se lo devolviste?'
          else
            'El abono viene de otra persona: ¿pagó varias cosas de una '
                'vez?',
        ],
      );
    }
    return found;
  }

  /// Every combination of 1 to [maxParts] operations adding up to
  /// [amount]. Stops at two: only a unique one is proposed. Money coming in
  /// for several sales is one customer's (a parent paying his son's two
  /// invoices), never three customers'.
  List<List<BankReconciliationCandidate>> _combinations(
    List<BankReconciliationCandidate> pool,
    int amount, {
    required bool oneCounterparty,
  }) {
    final sorted = [...pool]
      ..sort((left, right) => right.amountClp.compareTo(left.amountClp));
    final result = <List<BankReconciliationCandidate>>[];
    void search(
        int start, int remaining, List<BankReconciliationCandidate> taken) {
      if (result.length > 1) return;
      if (remaining == 0 && taken.isNotEmpty) {
        if (_isBatch(taken, oneCounterparty: oneCounterparty)) {
          result.add(List.of(taken));
        }
        return;
      }
      if (taken.length == maxParts || remaining <= 0) return;
      for (var index = start; index < sorted.length; index++) {
        final candidate = sorted[index];
        if (candidate.amountClp > remaining) continue;
        taken.add(candidate);
        search(index + 1, remaining - candidate.amountClp, taken);
        taken.removeLast();
        if (result.length > 1) return;
      }
    }

    search(0, amount, <BankReconciliationCandidate>[]);
    return result;
  }

  bool _isBatch(
    List<BankReconciliationCandidate> parts, {
    required bool oneCounterparty,
  }) {
    if (parts.length == 1) return true;
    if (parts.map((part) => part.targetKind).toSet().length != 1) return false;
    if (oneCounterparty &&
        parts
                .map((part) => (part.counterparty ?? '').trim().toLowerCase())
                .toSet()
                .length !=
            1) {
      return false;
    }
    final dates = parts.map((part) => part.occurredOn).toList()..sort();
    return dates.first.daysUntil(dates.last) <= batchSpanDays;
  }
}
