import '../models/bank_reconciliation_models.dart';
import 'bank_business_calendar.dart';
import 'bank_counterparty_identity.dart';

/// A bank movement that settles, in one transfer, several operations the ERP
/// recorded with other people: the owner's mother paid two salaries of week
/// 29 (Vicente $94.500, Lucas $38.500) and he repaid her $133.000 on 7 July.
/// The name the bank prints is nobody the operations name, so the matcher
/// never pairs them.
///
/// It is proposed only when exactly one combination of operations nothing
/// else explains adds up to the movement to the peso, and never selected: a
/// sum can coincide, and only the owner knows who paid what for him.
///
/// The same happens one to one: Rosita Bustamante's $34.000 sale by transfer
/// arrived from Osvaldo Quezada the same day, Gabriel Sanabria's $37.000 from
/// Sabrina Gutiérrez the next banking day. The matcher leaves a payment whose
/// name contradicts the bank's as an alternative, because between a card
/// charge and a person that contradiction is real; between two people it is
/// a relative or a borrowed account. When the amount is exact, the ERP
/// recorded it as a transfer, the bank booked it within the banking days a
/// transfer takes, and neither side has another candidate, it is proposed
/// with high confidence and offered as a safe suggestion.
class BankThirdPartyFinder {
  const BankThirdPartyFinder({
    this.windowDays = 45,
    this.maxParts = 3,
    this.maxPool = 40,
    this.batchSpanDays = 7,
    this.calendar = const BankBusinessCalendar(),
  });

  final BankBusinessCalendar calendar;

  /// Banking days from the ERP date to the bank's that still read as the
  /// same transfer: the sale registered the morning after it arrived, to a
  /// bank that books it three days later.
  static const int _earliestLag = -1;
  static const int _latestLag = 3;

  /// The bank books a transfer the same day or, made in the evening or on a
  /// holiday, the next banking day: that is certain; more is only likely.
  static const int _certainLag = 1;

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
      // Only a person pays for somebody else: a card charge or a merchant
      // named otherwise is a real contradiction.
      return movement.amountClp != null &&
          movement.bookingDate != null &&
          movement.direction != BankMovementDirection.unknown &&
          _isPersonTransfer(movement) &&
          !skipSourceRowIds.contains(movement.sourceRowId) &&
          !rowProposals.any((proposal) => proposal.isSelectedByDefault);
    }).toList(growable: false)
      ..sort((left, right) => left.bookingDate!.compareTo(right.bookingDate!));

    _otherPayers(
      open: open,
      candidates: candidates,
      claimed: claimed,
      used: used,
      found: found,
    );

    for (final movement in open) {
      if (found.containsKey(movement.sourceRowId)) continue;
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
      // One operation with the exact amount of two movements belongs to
      // neither by the sum alone.
      if (chosen.length == 1 &&
          open.any((other) =>
              other.sourceRowId != movement.sourceRowId &&
              other.direction == movement.direction &&
              other.amountClp == amount &&
              chosen.single.occurredOn.daysUntil(other.bookingDate!).abs() <=
                  windowDays)) {
        continue;
      }
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

  /// One transfer, one operation, another name: exact amount, recorded as a
  /// transfer, booked within the transfer's banking days, and the only
  /// candidate on both sides.
  void _otherPayers({
    required List<BankStatementMovement> open,
    required List<BankReconciliationCandidate> candidates,
    required Set<String> claimed,
    required Set<String> used,
    required Map<String, BankReconciliationProposal> found,
  }) {
    final transfers = open.where(_isPersonTransfer).toList(growable: false);
    final pool = candidates
        .where((candidate) =>
            candidate.provider == BankSettlementProvider.none &&
            candidate.targetKind != BankReconciliationTargetKind.journalEntry &&
            _isTransferMethod(candidate) &&
            !claimed.contains(candidate.identity))
        .toList(growable: false);
    int lagOf(BankStatementMovement movement, BankReconciliationCandidate c) =>
        calendar.businessDaysBetween(c.occurredOn, movement.bookingDate!);
    bool fits(BankStatementMovement movement, BankReconciliationCandidate c) {
      if (c.direction != movement.direction ||
          c.amountClp != movement.amountClp) {
        return false;
      }
      final lag = lagOf(movement, c);
      return lag >= _earliestLag && lag <= _latestLag;
    }

    for (final movement in transfers) {
      final options = pool
          .where((candidate) =>
              !used.contains(candidate.identity) && fits(movement, candidate))
          .toList(growable: false);
      if (options.length != 1) continue;
      final candidate = options.single;
      if (transfers.where((other) => fits(other, candidate)).length != 1) {
        continue;
      }
      used.add(candidate.identity);
      final lag = lagOf(movement, candidate);
      found[movement.sourceRowId] = BankReconciliationProposal(
        sourceRowId: movement.sourceRowId,
        matchKind: BankReconciliationMatchKind.thirdParty,
        confidence: lag >= 0 && lag <= _certainLag
            ? BankReconciliationConfidence.high
            : BankReconciliationConfidence.medium,
        allocations: <BankReconciliationAllocationDraft>[
          BankReconciliationAllocationDraft(
            candidate: candidate,
            bankAmountClp: candidate.amountClp,
          ),
        ],
        reasons: _otherPayerReasons(movement, candidate, lag),
      );
    }
  }

  List<String> _otherPayerReasons(
    BankStatementMovement movement,
    BankReconciliationCandidate candidate,
    int lag,
  ) {
    final incoming = movement.direction == BankMovementDirection.credit;
    final names = candidate.counterpartyNames.isNotEmpty
        ? candidate.counterpartyNames
        : <String>[if (candidate.counterparty != null) candidate.counterparty!];
    final who = names.where((name) =>
        name.trim().isNotEmpty &&
        !BankCounterpartyIdentity.isPlaceholder(name));
    final party = bankParty(movement);
    final shared = who.isEmpty
        ? null
        : BankCounterpartyIdentity.tokens(party)
            .where((token) =>
                token.length >= 4 &&
                who.any((name) =>
                    BankCounterpartyIdentity.tokens(name).contains(token)))
            .firstOrNull;
    final verb = incoming ? 'La pagó' : 'La recibió';
    return <String>[
      'Mismo monto que ${candidate.label}'
          '${who.isEmpty ? '' : ' de ${who.first}'}, registrada como '
          'transferencia: ${_when(candidate.occurredOn, movement.bookingDate!, lag)}',
      if (who.isEmpty)
        'La operación no tiene el nombre de la persona; la transferencia es '
            '${incoming ? 'de' : 'a'} $party'
      else if (shared != null)
        '$verb $party, que comparte «${_capitalized(shared)}» con '
            '${who.first}: probablemente un familiar'
      else
        '$verb $party y no ${who.first}: puede ser un familiar o una cuenta '
            'prestada',
      'Es la única transferencia de ese monto sin explicar en esas fechas, y '
          'la única operación del ERP por transferencia que calza con ella',
    ];
  }

  /// When the ERP recorded it and when the bank booked it, in words.
  String _when(BankCivilDate recorded, BankCivilDate booked, int lag) {
    if (recorded == booked) return 'el mismo día';
    if (booked.compareTo(recorded) < 0) {
      return 'el banco la anotó el ${_day(booked)} y se registró el '
          '${_day(recorded)}';
    }
    final holidays = <BankCivilDate>[
      for (var date = recorded.addDays(1);
          date.compareTo(booked) < 0;
          date = date.addDays(1))
        if (!calendar.isBusinessDay(date) &&
            date.utcDate.weekday != DateTime.saturday &&
            date.utcDate.weekday != DateTime.sunday)
          date,
    ];
    final atRest = !calendar.isBusinessDay(recorded);
    if (lag == 1) {
      final why = atRest || holidays.isNotEmpty
          ? ', el primer día hábil después'
              '${holidays.isEmpty ? '' : ' (el ${holidays.map(_day).join(' y el ')} fue feriado)'}'
          : ', el día hábil siguiente, como toda transferencia hecha de tarde';
      return 'registrada el ${_weekday(recorded)} ${_day(recorded)} y anotada '
          'por el banco el ${_weekday(booked)} ${_day(booked)}$why';
    }
    return 'registrada el ${_day(recorded)} y anotada por el banco $lag días '
        'hábiles después';
  }

  /// Who the bank says sent or received the transfer, as printed.
  static String bankParty(BankStatementMovement movement) {
    final observed = movement.counterpartyObserved?.trim();
    if (observed != null && observed.isNotEmpty) return observed;
    final text = movement.description;
    final colon = text.indexOf(':');
    final name = (colon >= 0 ? text.substring(colon + 1) : text)
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty && word.toLowerCase() != 'internet')
        .join(' ');
    return name.isEmpty ? 'otra persona' : name;
  }

  static bool _isPersonTransfer(BankStatementMovement movement) {
    final text = movement.normalizedDescription;
    return !movement.isTransbankDeposit &&
        (text.contains('traspaso') || text.contains('transferencia'));
  }

  static bool _isTransferMethod(BankReconciliationCandidate candidate) =>
      candidate.paymentMethodCode?.contains('transf') ?? false;

  static const _weekdays = <String>[
    'lunes',
    'martes',
    'miércoles',
    'jueves',
    'viernes',
    'sábado',
    'domingo',
  ];

  static String _weekday(BankCivilDate date) =>
      _weekdays[date.utcDate.weekday - 1];

  static String _day(BankCivilDate date) =>
      '${date.day.toString().padLeft(2, '0')}-'
      '${date.month.toString().padLeft(2, '0')}';

  static String _capitalized(String token) =>
      token.isEmpty ? token : token[0].toUpperCase() + token.substring(1);

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
