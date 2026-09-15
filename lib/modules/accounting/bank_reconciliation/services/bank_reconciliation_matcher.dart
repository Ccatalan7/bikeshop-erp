import '../models/bank_reconciliation_models.dart';

class TransbankEstimatePolicy {
  const TransbankEstimatePolicy({
    this.maximumLookbackBusinessDays = 7,
    this.preferredDeductionBasisPoints = 700,
    this.maximumDeductionBasisPoints = 1500,
  })  : assert(maximumLookbackBusinessDays >= 4),
        assert(preferredDeductionBasisPoints >= 0),
        assert(maximumDeductionBasisPoints >= preferredDeductionBasisPoints);

  int get preferredLookbackBusinessDays => 4;
  final int maximumLookbackBusinessDays;
  final int preferredDeductionBasisPoints;
  final int maximumDeductionBasisPoints;
}

class BankReconciliationMatcher {
  const BankReconciliationMatcher({
    this.directDateWindowDays = 5,
    this.directAmountToleranceClp = 1000,
    this.transbankPolicy = const TransbankEstimatePolicy(),
  })  : assert(directDateWindowDays >= 0),
        assert(directAmountToleranceClp >= 0);

  final int directDateWindowDays;
  final int directAmountToleranceClp;
  final TransbankEstimatePolicy transbankPolicy;

  Map<String, List<BankReconciliationProposal>> match({
    required List<BankStatementMovement> movements,
    required List<BankReconciliationCandidate> candidates,
    List<BankTerminalMatchPolicy> terminalPolicies = const [],
  }) {
    final result = <String, List<BankReconciliationProposal>>{};
    final directlyClaimedCandidateIds = <String>{};

    for (final movement in movements) {
      final matchingPolicies = _matchingPolicies(
        movement,
        terminalPolicies,
      );
      final configuredProposals = matchingPolicies.isEmpty
          ? const <BankReconciliationProposal>[]
          : _terminalProposals(movement, candidates, matchingPolicies);
      final proposals = configuredProposals.isNotEmpty
          ? configuredProposals
          : _isTransbankMovement(movement)
              ? _transbankProposals(movement, candidates)
              : _directProposals(movement, candidates);

      final available = <BankReconciliationProposal>[];
      for (final proposal in proposals) {
        final candidateIds = proposal.allocations
            .map((allocation) => allocation.candidate.identity)
            .toSet();
        if (proposal.matchKind == BankReconciliationMatchKind.direct &&
            candidateIds.any(directlyClaimedCandidateIds.contains)) {
          continue;
        }
        available.add(proposal);
      }

      if (available.length == 1 &&
          available.single.matchKind == BankReconciliationMatchKind.direct &&
          available.single.confidence == BankReconciliationConfidence.high) {
        final selected = available.single;
        available[0] = BankReconciliationProposal(
          sourceRowId: selected.sourceRowId,
          matchKind: selected.matchKind,
          confidence: selected.confidence,
          allocations: selected.allocations,
          reasons: selected.reasons,
          isSelectedByDefault: true,
          instrument: selected.instrument,
        );
        directlyClaimedCandidateIds.addAll(
          selected.allocations
              .map((allocation) => allocation.candidate.identity),
        );
      }
      result[movement.sourceRowId] = List.unmodifiable(available.take(3));
    }
    return result;
  }

  List<BankTerminalMatchPolicy> _matchingPolicies(
    BankStatementMovement movement,
    List<BankTerminalMatchPolicy> policies,
  ) {
    final evidence = _normalize(movement.normalizedDescription);
    return policies.where((policy) {
      return policy.descriptorPatterns.any((pattern) {
        final normalized = _normalize(pattern);
        return normalized.isNotEmpty && evidence.contains(normalized);
      });
    }).toList(growable: false);
  }

  List<BankReconciliationProposal> _terminalProposals(
    BankStatementMovement movement,
    List<BankReconciliationCandidate> candidates,
    List<BankTerminalMatchPolicy> policies,
  ) {
    final bookingDate = movement.bookingDate;
    final movementAmount = movement.amountClp;
    if (movement.direction != BankMovementDirection.credit ||
        bookingDate == null ||
        movementAmount == null) {
      return const [];
    }

    final grouped = <String, List<BankTerminalMatchPolicy>>{};
    for (final policy in policies) {
      grouped.putIfAbsent(policy.profileId, () => []).add(policy);
    }
    final proposals = <_DirectRank>[];
    for (final profilePolicies in grouped.values) {
      final eligible = <_TerminalRailCandidate>[];
      for (final policy in profilePolicies) {
        for (final candidate in candidates) {
          if (candidate.targetKind !=
                  BankReconciliationTargetKind.salesPayment ||
              candidate.direction != BankMovementDirection.credit ||
              candidate.paymentMethodCode != policy.paymentMethodCode ||
              !policy.appliesOn(candidate.occurredOn)) {
            continue;
          }
          final expectedBooking = _addBusinessDays(
            candidate.occurredOn,
            policy.settlementBusinessDays,
          );
          final latestBooking = _addBusinessDays(
            expectedBooking,
            policy.bookingGraceBusinessDays,
          );
          if (bookingDate.compareTo(expectedBooking) < 0 ||
              bookingDate.compareTo(latestBooking) > 0) {
            continue;
          }
          eligible.add(
            _TerminalRailCandidate(
              candidate: candidate,
              policy: policy,
              expectedNetClp: policy.expectedNetClp(candidate.amountClp),
            ),
          );
        }
      }
      eligible.sort((left, right) {
        final byDate =
            left.candidate.occurredOn.compareTo(right.candidate.occurredOn);
        return byDate != 0
            ? byDate
            : left.candidate.identity.compareTo(right.candidate.identity);
      });
      if (eligible.isEmpty) continue;
      final tolerance = profilePolicies
          .map((policy) => policy.amountToleranceClp)
          .reduce((left, right) => left > right ? left : right);
      final states = <int, List<_TerminalRailCandidate>>{
        0: const <_TerminalRailCandidate>[],
      };
      for (final railCandidate in eligible) {
        if (railCandidate.expectedNetClp <= 0 ||
            railCandidate.expectedNetClp > movementAmount + tolerance) {
          continue;
        }
        final prior = states.entries.toList(growable: false);
        for (final state in prior) {
          final net = state.key + railCandidate.expectedNetClp;
          if (net > movementAmount + tolerance) continue;
          final cohort = <_TerminalRailCandidate>[
            ...state.value,
            railCandidate,
          ];
          final current = states[net];
          if (current == null ||
              _terminalLagScore(cohort, bookingDate) <
                  _terminalLagScore(current, bookingDate)) {
            states[net] = cohort;
          }
        }
        _pruneTerminalStates(states, targetAmountClp: movementAmount);
      }
      final viable = states.entries
          .where((entry) =>
              entry.value.isNotEmpty &&
              (entry.key - movementAmount).abs() <= tolerance)
          .toList(growable: false)
        ..sort((left, right) {
          final difference = (left.key - movementAmount)
              .abs()
              .compareTo((right.key - movementAmount).abs());
          if (difference != 0) return difference;
          return _terminalLagScore(left.value, bookingDate)
              .compareTo(_terminalLagScore(right.value, bookingDate));
        });
      for (final entry in viable.take(3)) {
        final cohort = entry.value;
        final expectedNet = entry.key;
        final gross = cohort.fold<int>(
          0,
          (sum, item) => sum + item.candidate.amountClp,
        );
        final ruleDifference = (expectedNet - movementAmount).abs();
        final instruments =
            cohort.map((item) => item.policy.instrument).toSet();
        final profile = profilePolicies.first;
        proposals.add(
          _DirectRank(
            score: 100000 -
                ruleDifference * 100 -
                _terminalLagScore(cohort, bookingDate),
            proposal: BankReconciliationProposal(
              sourceRowId: movement.sourceRowId,
              matchKind: BankReconciliationMatchKind.processorEstimate,
              confidence: ruleDifference == 0
                  ? BankReconciliationConfidence.medium
                  : BankReconciliationConfidence.low,
              allocations: _proportionalTerminalAllocations(
                cohort: cohort,
                bankAmountClp: movementAmount,
                expectedNetClp: expectedNet,
              ),
              reasons: <String>[
                '${cohort.length} venta(s) · ${profile.providerName} / '
                    '${profile.terminalName}',
                _railBreakdown(cohort),
                'Plazos aplicados por tipo de tarjeta y margen de fecha '
                    'contable bancaria',
                'Bruto \$${_group(gross)} · abono esperado '
                    '\$${_group(expectedNet)} · cartola '
                    '\$${_group(movementAmount)}',
                if (ruleDifference > 0)
                  'Diferencia de \$${_group(ruleDifference)} dentro de la '
                      'tolerancia configurada',
              ],
              estimatedGrossClp: gross,
              estimatedDifferenceClp: gross - movementAmount,
              instrument: instruments.length == 1
                  ? instruments.single
                  : BankPaymentInstrument.unknown,
            ),
          ),
        );
      }
    }
    proposals.sort((left, right) => right.score.compareTo(left.score));
    return proposals
        .map((rank) => rank.proposal)
        .take(3)
        .toList(growable: false);
  }

  List<BankReconciliationProposal> _directProposals(
    BankStatementMovement movement,
    List<BankReconciliationCandidate> candidates,
  ) {
    final bookingDate = movement.bookingDate;
    final movementAmount = movement.amountClp;
    if (bookingDate == null || movementAmount == null) return const [];
    final ranked = <_DirectRank>[];
    for (final candidate in candidates) {
      if (candidate.direction != movement.direction) continue;
      final difference = (candidate.amountClp - movementAmount).abs();
      if (difference > directAmountToleranceClp) continue;
      final dateDistance = candidate.occurredOn.daysUntil(bookingDate).abs();
      if (dateDistance > directDateWindowDays) continue;

      final evidenceText = _normalize(<String>[
        movement.normalizedDescription,
        movement.counterpartyObserved ?? '',
        movement.documentNumber ?? '',
      ].join(' '));
      final candidateText = _normalize(<String>[
        candidate.label,
        candidate.counterparty ?? '',
        candidate.reference ?? '',
      ].join(' '));
      final overlap = _tokenOverlap(evidenceText, candidateText);
      final referenceExact = candidate.reference?.trim().isNotEmpty == true &&
          evidenceText.contains(_normalize(candidate.reference!));
      final amountExact = difference == 0;
      final high =
          amountExact && dateDistance <= 3 && (overlap >= 1 || referenceExact);
      final confidence = high
          ? BankReconciliationConfidence.high
          : BankReconciliationConfidence.medium;
      final score = (amountExact ? 100 : 70) +
          (referenceExact ? 45 : 0) +
          overlap * 12 -
          dateDistance * 5 -
          (difference ~/ 100);
      ranked.add(
        _DirectRank(
          score: score,
          proposal: BankReconciliationProposal(
            sourceRowId: movement.sourceRowId,
            matchKind: BankReconciliationMatchKind.direct,
            confidence: confidence,
            allocations: <BankReconciliationAllocationDraft>[
              BankReconciliationAllocationDraft(
                candidate: candidate,
                bankAmountClp: movementAmount,
              ),
            ],
            reasons: <String>[
              amountExact
                  ? 'Monto exacto'
                  : 'Diferencia de \$${_group(difference)}',
              'Fecha contable a $dateDistance días de la operación',
              if (referenceExact) 'Referencia exacta',
              if (overlap > 0) 'Coinciden datos de la contraparte',
            ],
            instrument: candidate.instrument,
          ),
        ),
      );
    }
    ranked.sort((left, right) => right.score.compareTo(left.score));
    if (ranked.length > 1 && ranked[0].score == ranked[1].score) {
      return ranked
          .take(3)
          .map(
            (rank) => BankReconciliationProposal(
              sourceRowId: rank.proposal.sourceRowId,
              matchKind: rank.proposal.matchKind,
              confidence: BankReconciliationConfidence.medium,
              allocations: rank.proposal.allocations,
              reasons: <String>[
                ...rank.proposal.reasons,
                'Hay más de una operación posible',
              ],
              instrument: rank.proposal.instrument,
            ),
          )
          .toList(growable: false);
    }
    return ranked.map((rank) => rank.proposal).take(3).toList(growable: false);
  }

  List<BankReconciliationProposal> _transbankProposals(
    BankStatementMovement movement,
    List<BankReconciliationCandidate> candidates,
  ) {
    final bookingDate = movement.bookingDate;
    final movementAmount = movement.amountClp;
    if (movement.direction != BankMovementDirection.credit ||
        bookingDate == null ||
        movementAmount == null) {
      return const [];
    }
    final firstDate = _subtractBusinessDays(
      bookingDate,
      transbankPolicy.maximumLookbackBusinessDays,
    );
    final preferredFirstDate = _subtractBusinessDays(
      bookingDate,
      transbankPolicy.preferredLookbackBusinessDays,
    );
    final sales = candidates
        .where(
          (candidate) =>
              candidate.targetKind ==
                  BankReconciliationTargetKind.salesPayment &&
              candidate.direction == BankMovementDirection.credit &&
              (candidate.paymentMethodCode == 'card' ||
                  (candidate.provider == BankSettlementProvider.transbank &&
                      candidate.instrument == BankPaymentInstrument.unknown)) &&
              candidate.occurredOn.compareTo(firstDate) >= 0 &&
              candidate.occurredOn.compareTo(bookingDate) <= 0,
        )
        .toList(growable: false)
      ..sort((left, right) {
        final byDate = left.occurredOn.compareTo(right.occurredOn);
        return byDate != 0 ? byDate : left.identity.compareTo(right.identity);
      });
    if (sales.isEmpty) return const [];

    final denominator = 10000 - transbankPolicy.maximumDeductionBasisPoints;
    final maximumGross = denominator <= 0
        ? movementAmount * 2
        : movementAmount * 10000 ~/ denominator;
    final subsetsByGross = <int, List<BankReconciliationCandidate>>{
      0: const <BankReconciliationCandidate>[],
    };
    for (final candidate in sales) {
      if (candidate.amountClp > maximumGross) continue;
      final priorStates = subsetsByGross.entries.toList(growable: false);
      for (final state in priorStates) {
        final gross = state.key + candidate.amountClp;
        if (gross > maximumGross) continue;
        final subset = <BankReconciliationCandidate>[
          ...state.value,
          candidate,
        ];
        final current = subsetsByGross[gross];
        if (current == null ||
            _subsetLagScore(subset, bookingDate) <
                _subsetLagScore(current, bookingDate)) {
          subsetsByGross[gross] = subset;
        }
      }
      _pruneTransbankStates(
        subsetsByGross,
        targetAmountClp: movementAmount,
      );
    }

    final viable = subsetsByGross.entries
        .where((entry) => entry.key >= movementAmount && entry.value.isNotEmpty)
        .toList(growable: false)
      ..sort((left, right) {
        final byDifference =
            (left.key - movementAmount).compareTo(right.key - movementAmount);
        if (byDifference != 0) return byDifference;
        final byLag = _subsetLagScore(left.value, bookingDate)
            .compareTo(_subsetLagScore(right.value, bookingDate));
        if (byLag != 0) return byLag;
        return left.value.length.compareTo(right.value.length);
      });

    return viable.take(3).map((entry) {
      final cohort = entry.value;
      final gross = entry.key;
      final difference = gross - movementAmount;
      final deductionBps = gross == 0 ? 0 : (difference * 10000 ~/ gross);
      final usesExtendedWindow = cohort.any(
        (candidate) => candidate.occurredOn.compareTo(preferredFirstDate) < 0,
      );
      final allocations = _proportionalAllocations(
        candidates: cohort,
        bankAmountClp: movementAmount,
        grossClp: gross,
      );
      return BankReconciliationProposal(
        sourceRowId: movement.sourceRowId,
        matchKind: BankReconciliationMatchKind.transbankEstimate,
        confidence: !usesExtendedWindow &&
                deductionBps <= transbankPolicy.preferredDeductionBasisPoints
            ? BankReconciliationConfidence.medium
            : BankReconciliationConfidence.low,
        allocations: allocations,
        reasons: <String>[
          '${cohort.length} venta(s) con tarjeta entre $firstDate y '
              '$bookingDate',
          if (usesExtendedWindow)
            'Ventana extendida: la fecha de la cartola es contable y puede '
                'quedar varios días después de la venta',
          'Bruto \$${_group(gross)} − depósito '
              '\$${_group(movementAmount)} = '
              '\$${_group(difference)} estimados en comisiones, IVA y ajustes',
          'Instrumento aún no separado: débito, crédito o prepago',
        ],
        isSelectedByDefault: false,
        estimatedGrossClp: gross,
        estimatedDifferenceClp: difference,
        instrument: BankPaymentInstrument.unknown,
      );
    }).toList(growable: false);
  }

  int _subsetLagScore(
    List<BankReconciliationCandidate> candidates,
    BankCivilDate bookingDate,
  ) {
    return candidates.fold<int>(
      0,
      (sum, candidate) =>
          sum + candidate.occurredOn.daysUntil(bookingDate).abs(),
    );
  }

  int _terminalLagScore(
    List<_TerminalRailCandidate> candidates,
    BankCivilDate bookingDate,
  ) {
    return candidates.fold<int>(
      0,
      (sum, item) =>
          sum + item.candidate.occurredOn.daysUntil(bookingDate).abs(),
    );
  }

  void _pruneTransbankStates(
    Map<int, List<BankReconciliationCandidate>> states, {
    required int targetAmountClp,
  }) {
    const maximumStateCount = 12000;
    if (states.length <= maximumStateCount) return;
    final ranked = states.entries.toList(growable: false)
      ..sort((left, right) {
        if (left.key == 0) return -1;
        if (right.key == 0) return 1;
        final leftDistance = (left.key - targetAmountClp).abs();
        final rightDistance = (right.key - targetAmountClp).abs();
        return leftDistance.compareTo(rightDistance);
      });
    states
      ..clear()
      ..addEntries(ranked.take(maximumStateCount));
  }

  void _pruneTerminalStates(
    Map<int, List<_TerminalRailCandidate>> states, {
    required int targetAmountClp,
  }) {
    const maximumStateCount = 12000;
    if (states.length <= maximumStateCount) return;
    final ranked = states.entries.toList(growable: false)
      ..sort((left, right) {
        if (left.key == 0) return -1;
        if (right.key == 0) return 1;
        return (left.key - targetAmountClp)
            .abs()
            .compareTo((right.key - targetAmountClp).abs());
      });
    states
      ..clear()
      ..addEntries(ranked.take(maximumStateCount));
  }

  List<BankReconciliationAllocationDraft> _proportionalAllocations({
    required List<BankReconciliationCandidate> candidates,
    required int bankAmountClp,
    required int grossClp,
  }) {
    var assigned = 0;
    final allocations = <BankReconciliationAllocationDraft>[];
    for (var index = 0; index < candidates.length; index++) {
      final candidate = candidates[index];
      final amount = index == candidates.length - 1
          ? bankAmountClp - assigned
          : (bankAmountClp * candidate.amountClp / grossClp).round();
      if (amount <= 0) continue;
      assigned += amount;
      allocations.add(
        BankReconciliationAllocationDraft(
          candidate: candidate,
          bankAmountClp: amount,
        ),
      );
    }
    return allocations;
  }

  List<BankReconciliationAllocationDraft> _proportionalTerminalAllocations({
    required List<_TerminalRailCandidate> cohort,
    required int bankAmountClp,
    required int expectedNetClp,
  }) {
    var assigned = 0;
    final allocations = <BankReconciliationAllocationDraft>[];
    for (var index = 0; index < cohort.length; index++) {
      final item = cohort[index];
      final amount = index == cohort.length - 1
          ? bankAmountClp - assigned
          : (bankAmountClp * item.expectedNetClp / expectedNetClp).round();
      if (amount <= 0) continue;
      assigned += amount;
      allocations.add(
        BankReconciliationAllocationDraft(
          candidate: item.candidate,
          bankAmountClp: amount,
        ),
      );
    }
    return allocations;
  }

  String _railBreakdown(List<_TerminalRailCandidate> cohort) {
    final counts = <BankPaymentInstrument, int>{};
    for (final item in cohort) {
      counts.update(
        item.policy.instrument,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final entries = counts.entries.toList(growable: false)
      ..sort((left, right) =>
          _instrumentOrder(left.key).compareTo(_instrumentOrder(right.key)));
    return entries
        .map((entry) => '${entry.value} ${_instrumentLabel(entry.key)}')
        .join(' + ');
  }

  int _instrumentOrder(BankPaymentInstrument instrument) =>
      switch (instrument) {
        BankPaymentInstrument.debit => 0,
        BankPaymentInstrument.credit => 1,
        BankPaymentInstrument.prepaid => 2,
        BankPaymentInstrument.unknown => 3,
      };

  bool _isTransbankMovement(BankStatementMovement movement) {
    final text = movement.normalizedDescription;
    return text.contains('transbank') ||
        text.contains('abonos debito y credito') ||
        text.contains('abono debito credito');
  }

  BankCivilDate _subtractBusinessDays(BankCivilDate source, int count) {
    var remaining = count;
    var date = source;
    while (remaining > 0) {
      date = date.addDays(-1);
      final weekday = date.utcDate.weekday;
      if (weekday != DateTime.saturday && weekday != DateTime.sunday) {
        remaining--;
      }
    }
    return date;
  }

  BankCivilDate _addBusinessDays(BankCivilDate source, int count) {
    var remaining = count;
    var date = source;
    while (remaining > 0) {
      date = date.addDays(1);
      final weekday = date.utcDate.weekday;
      if (weekday != DateTime.saturday && weekday != DateTime.sunday) {
        remaining--;
      }
    }
    return date;
  }

  String _instrumentLabel(BankPaymentInstrument instrument) =>
      switch (instrument) {
        BankPaymentInstrument.debit => 'débito',
        BankPaymentInstrument.credit => 'crédito',
        BankPaymentInstrument.prepaid => 'prepago',
        BankPaymentInstrument.unknown => 'tarjeta',
      };

  int _tokenOverlap(String left, String right) {
    final leftTokens =
        left.split(' ').where((token) => token.length >= 3).toSet();
    final rightTokens =
        right.split(' ').where((token) => token.length >= 3).toSet();
    return leftTokens.intersection(rightTokens).length;
  }

  String _normalize(String value) {
    const replacements = <String, String>{
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
    };
    var result = value.toLowerCase();
    for (final entry in replacements.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _group(int value) {
    final digits = value.abs().toString();
    return digits.replaceAllMapped(
      RegExp(r'(?<=\d)(?=(\d{3})+$)'),
      (_) => '.',
    );
  }
}

class _DirectRank {
  const _DirectRank({required this.score, required this.proposal});

  final int score;
  final BankReconciliationProposal proposal;
}

class _TerminalRailCandidate {
  const _TerminalRailCandidate({
    required this.candidate,
    required this.policy,
    required this.expectedNetClp,
  });

  final BankReconciliationCandidate candidate;
  final BankTerminalMatchPolicy policy;
  final int expectedNetClp;
}
