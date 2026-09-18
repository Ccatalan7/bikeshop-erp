import 'dart:math' as math;

import '../models/bank_reconciliation_models.dart';
import 'bank_business_calendar.dart';
import 'bank_counterparty_identity.dart';

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

class BankReconciliationMatchResult {
  BankReconciliationMatchResult({
    required Map<String, List<BankReconciliationProposal>> proposals,
    List<BankReconciliationInsight> insights =
        const <BankReconciliationInsight>[],
  })  : proposals = Map.unmodifiable(proposals),
        insights = List.unmodifiable(insights);

  final Map<String, List<BankReconciliationProposal>> proposals;
  final List<BankReconciliationInsight> insights;
}

/// Ties statement movements to the ERP operations that explain them.
///
/// Direct movements are assigned globally, not row by row: every movement
/// ranks its options by amount, the name the bank prints, the date and any
/// bank row another module already tied to the operation, and the most
/// certain pair is fixed first so it stops competing for the rest. Only a
/// pair with a clear margin over every alternative starts selected.
///
/// Acquirer deposits (Transbank) are explained by the card sales they pay:
/// each sale nets its commission and VAT with the rate the statement itself
/// proves (learned from deposits that match one sale to the peso), within its
/// configured banking-day window. A deposit that one combination explains to
/// the peso starts selected; anything looser stays a reviewable estimate.
class BankReconciliationMatcher {
  const BankReconciliationMatcher({
    this.directDateWindowDays = 5,
    this.directAmountToleranceClp = 1000,
    this.transbankPolicy = const TransbankEstimatePolicy(),
    this.calendar = const BankBusinessCalendar(),
  })  : assert(directDateWindowDays >= 0),
        assert(directAmountToleranceClp >= 0);

  final int directDateWindowDays;
  final int directAmountToleranceClp;
  final TransbankEstimatePolicy transbankPolicy;
  final BankBusinessCalendar calendar;

  /// Score gap below which two options are treated as a real doubt.
  static const int _decisiveMargin = 20;

  /// A card deposit is preselected only when a coincidental combination of
  /// sales hitting it to the peso is this unlikely.
  static const double _coincidenceLimit = 0.05;

  /// Window for a strong name match on a supplier or customer operation.
  static const int _identityWindowDays = 12;

  /// Salaries and recurring payees are often registered weeks after the
  /// transfer (a payroll paid on 12 August for July weeks), so a strong name
  /// match may reach further back.
  static const int _personWindowDays = 40;

  Map<String, List<BankReconciliationProposal>> match({
    required List<BankStatementMovement> movements,
    required List<BankReconciliationCandidate> candidates,
    List<BankTerminalMatchPolicy> terminalPolicies = const [],
  }) {
    return analyze(
      movements: movements,
      candidates: candidates,
      terminalPolicies: terminalPolicies,
    ).proposals;
  }

  BankReconciliationMatchResult analyze({
    required List<BankStatementMovement> movements,
    required List<BankReconciliationCandidate> candidates,
    List<BankTerminalMatchPolicy> terminalPolicies = const [],
  }) {
    final deposits = <BankStatementMovement>[];
    final direct = <BankStatementMovement>[];
    for (final movement in movements) {
      final isDeposit = movement.direction == BankMovementDirection.credit &&
          (_matchingPolicies(movement, terminalPolicies).isNotEmpty ||
              _isTransbankMovement(movement));
      (isDeposit ? deposits : direct).add(movement);
    }
    final acquirerSales =
        candidates.where(_isAcquirerSale).toList(growable: false);
    final directCandidates = candidates
        .where((candidate) => !_isAcquirerSale(candidate))
        .toList(growable: false);

    final settlement = _settleDeposits(
      deposits: deposits,
      sales: acquirerSales,
      policies: terminalPolicies,
    );
    final assigned = _assignDirect(direct, directCandidates);
    return BankReconciliationMatchResult(
      proposals: <String, List<BankReconciliationProposal>>{
        for (final movement in movements)
          movement.sourceRowId: List.unmodifiable(
            settlement.proposals[movement.sourceRowId] ??
                assigned[movement.sourceRowId] ??
                const <BankReconciliationProposal>[],
          ),
      },
      insights: settlement.insights,
    );
  }

  bool _isAcquirerSale(BankReconciliationCandidate candidate) =>
      candidate.targetKind == BankReconciliationTargetKind.salesPayment &&
      (candidate.provider != BankSettlementProvider.none ||
          candidate.paymentMethodCode == 'card' ||
          (candidate.paymentMethodCode?.startsWith('card_') ?? false));

  // ---------------------------------------------------------------------
  // Direct movements: transfers, card charges, salaries, suppliers.
  // ---------------------------------------------------------------------

  Map<String, List<BankReconciliationProposal>> _assignDirect(
    List<BankStatementMovement> movements,
    List<BankReconciliationCandidate> candidates,
  ) {
    // A bank row Nómina already tied to an operation owns that operation.
    final reservedFor = <String, String>{};
    for (final movement in movements) {
      for (final candidate in candidates) {
        if (candidate.direction == movement.direction &&
            _pointsTo(candidate, movement)) {
          reservedFor.putIfAbsent(
              candidate.identity, () => movement.sourceRowId);
        }
      }
    }
    final analyses = <String, _RowAnalysis>{
      for (final movement in movements)
        movement.sourceRowId: _analyzeRow(
          movement,
          candidates.where((candidate) {
            final owner = reservedFor[candidate.identity];
            return owner == null || owner == movement.sourceRowId;
          }).toList(growable: false),
        ),
    };
    final byRow = <String, BankStatementMovement>{
      for (final movement in movements) movement.sourceRowId: movement,
    };
    final chosen = <String, _DirectChoice>{};
    final taken = <String>{};

    // 1. Rows fully explained by operations Nómina tied to them.
    for (final movement in movements) {
      final analysis = analyses[movement.sourceRowId]!;
      final pointed = analysis.related.where((item) => item.evidence).toList();
      if (pointed.isEmpty) continue;
      final option = _evidenceOnlyOption(movement, pointed);
      if (option == null) continue;
      chosen[movement.sourceRowId] =
          _DirectChoice(option: option, decisive: true, contested: false);
      taken.addAll(option.candidateIds);
    }

    // 2. One operation per row, the best total over all rows at once.
    final open = movements
        .where((movement) => !chosen.containsKey(movement.sourceRowId))
        .toList(growable: false);
    final singleOptions = <String, List<_DirectOption>>{
      for (final movement in open)
        movement.sourceRowId: analyses[movement.sourceRowId]!
            .singles
            .where((option) =>
                option.candidateIds.every((id) => !taken.contains(id)))
            .toList(growable: false),
    };
    final assignment = _optimalSingles(singleOptions);
    for (final entry in assignment.entries) {
      taken.addAll(entry.value.candidateIds);
    }

    // 3. A transfer that pays several operations of the same party.
    for (final movement in open) {
      final rowId = movement.sourceRowId;
      if (assignment.containsKey(rowId)) continue;
      final amount = movement.amountClp;
      if (amount == null) continue;
      final free = analyses[rowId]!
          .related
          .where((item) => !taken.contains(item.candidate.identity))
          .toList(growable: false);
      final groups = <_DirectOption>[
        ..._groupOptions(movement, amount, free),
      ]..sort((left, right) => right.score.compareTo(left.score));
      if (groups.isEmpty) continue;
      final best = groups.first;
      final runnerUp = groups.length > 1 ? groups[1].score : null;
      final clear =
          runnerUp == null || best.score - runnerUp >= _decisiveMargin;
      chosen[rowId] = _DirectChoice(
        option: best,
        decisive: best.intrinsicallyDecisive && clear,
        contested: !clear,
      );
      taken.addAll(best.candidateIds);
      analyses[rowId] = analyses[rowId]!.withGroups(groups);
    }

    // Doubt is measured against the final arrangement, groups included: an
    // operation another row already explains is not a real alternative.
    final ownerOf = <String, (String, int)>{};
    for (final entry in chosen.entries) {
      for (final id in entry.value.option.candidateIds) {
        ownerOf[id] = (entry.key, entry.value.option.score);
      }
    }
    for (final entry in assignment.entries) {
      ownerOf[entry.value.candidates.single.identity] =
          (entry.key, entry.value.score);
    }
    for (final entry in assignment.entries) {
      final option = entry.value;
      final gap = _assignmentGap(
        entry.key,
        option,
        singleOptions,
        ownerOf,
        assignment,
      );
      final decisive = option.hasEvidence ||
          ((option.intrinsicallyDecisive || option.decisiveIfUnique) &&
              gap >= _decisiveMargin);
      chosen[entry.key] = _DirectChoice(
        option: option,
        decisive: decisive,
        contested: gap < _decisiveMargin,
      );
    }

    final decisivelyTaken = <String>{
      for (final choice in chosen.values)
        if (choice.decisive) ...choice.option.candidateIds,
    };
    final result = <String, List<BankReconciliationProposal>>{};
    for (final movement in movements) {
      final rowId = movement.sourceRowId;
      final choice = chosen[rowId];
      final analysis = analyses[rowId]!;
      final proposals = <BankReconciliationProposal>[];
      if (choice != null) {
        proposals.add(
          _directProposal(
            choice.option,
            selected: choice.decisive,
            confidence: choice.decisive
                ? BankReconciliationConfidence.high
                : BankReconciliationConfidence.medium,
            contested: choice.contested,
          ),
        );
      }
      if (choice == null || !choice.decisive) {
        for (final option in <_DirectOption>[
          ...analysis.singles,
          ...analysis.groups,
        ]) {
          if (proposals.length >= 3) break;
          if (choice != null && option.key == choice.option.key) continue;
          if (option.candidateIds.any(decisivelyTaken.contains)) continue;
          proposals.add(
            _directProposal(
              option,
              selected: false,
              confidence: option.identity == BankIdentityStrength.conflict
                  ? BankReconciliationConfidence.low
                  : BankReconciliationConfidence.medium,
              contested: true,
            ),
          );
        }
      }
      result[rowId] = proposals;
    }
    assert(byRow.length == movements.length);
    return result;
  }

  /// Operations Nómina tied to this bank row that add up to it by themselves.
  _DirectOption? _evidenceOnlyOption(
    BankStatementMovement movement,
    List<_RelatedCandidate> pointed,
  ) {
    final amount = movement.amountClp;
    if (amount == null) return null;
    final total =
        pointed.fold<int>(0, (sum, item) => sum + item.candidate.amountClp);
    final rounding = math.min<int>(directAmountToleranceClp, amount ~/ 100);
    if ((total - amount).abs() > rounding) return null;
    if (pointed.length == 1) {
      final item = pointed.single;
      final difference = (item.candidate.amountClp - amount).abs();
      return _DirectOption(
        movement: movement,
        candidates: <BankReconciliationCandidate>[item.candidate],
        score: _singleScore(
          difference: difference,
          dateDelta: item.dateDelta,
          identity: item.identity.strength,
          evidence: true,
          referenceExact: false,
        ),
        identity: item.identity.strength,
        hasEvidence: true,
        intrinsicallyDecisive: true,
        decisiveIfUnique: false,
        reasons: <String>[
          difference == 0
              ? 'Monto exacto'
              : 'Diferencia de \$${_group(difference)}',
          _dateReason(item.dateDelta),
          'Nómina ya asoció esta transferencia a este pago',
          ..._identityReasons(item.identity),
        ],
      );
    }
    final groups = _groupOptions(movement, amount, pointed);
    return groups.isEmpty ? null : groups.first;
  }

  /// Maximum-weight assignment of one operation per row (Hungarian method on
  /// each group of rows that compete for the same operations).
  Map<String, _DirectOption> _optimalSingles(
    Map<String, List<_DirectOption>> optionsByRow,
  ) {
    final rows = optionsByRow.keys
        .where((row) => optionsByRow[row]!.isNotEmpty)
        .toList(growable: false)
      ..sort();
    // Rows sharing an operation belong to one component.
    final parent = <String, String>{for (final row in rows) row: row};
    String find(String row) {
      var current = row;
      while (parent[current] != current) {
        parent[current] = parent[parent[current]!]!;
        current = parent[current]!;
      }
      return current;
    }

    final firstRowOf = <String, String>{};
    for (final row in rows) {
      for (final option in optionsByRow[row]!) {
        final id = option.candidates.single.identity;
        final other = firstRowOf.putIfAbsent(id, () => row);
        final left = find(row);
        final right = find(other);
        if (left != right) parent[left] = right;
      }
    }
    final components = <String, List<String>>{};
    for (final row in rows) {
      components.putIfAbsent(find(row), () => <String>[]).add(row);
    }

    final result = <String, _DirectOption>{};
    for (final componentRows in components.values) {
      final columns = <String>[];
      final columnIndex = <String, int>{};
      for (final row in componentRows) {
        for (final option in optionsByRow[row]!) {
          final id = option.candidates.single.identity;
          columnIndex.putIfAbsent(id, () {
            columns.add(id);
            return columns.length - 1;
          });
        }
      }
      final weights = List<List<_DirectOption?>>.generate(
        componentRows.length,
        (_) => List<_DirectOption?>.filled(columns.length, null),
      );
      for (var r = 0; r < componentRows.length; r++) {
        for (final option in optionsByRow[componentRows[r]]!) {
          final column = columnIndex[option.candidates.single.identity]!;
          final current = weights[r][column];
          if (current == null || option.score > current.score) {
            weights[r][column] = option;
          }
        }
      }
      final picks = _hungarian(
        <List<int?>>[
          for (final row in weights)
            <int?>[for (final option in row) option?.score],
        ],
      );
      for (var r = 0; r < componentRows.length; r++) {
        final column = picks[r];
        if (column < 0) continue;
        final option = weights[r][column];
        if (option != null) result[componentRows[r]] = option;
      }
    }
    return result;
  }

  /// Rows × columns weights (null = not allowed); every row may stay
  /// unassigned. Returns the column per row, or -1.
  List<int> _hungarian(List<List<int?>> weights) {
    final n = weights.length;
    if (n == 0) return const <int>[];
    final realColumns = weights.first.length;
    var maximum = 0;
    for (final row in weights) {
      for (final weight in row) {
        if (weight != null && weight > maximum) maximum = weight;
      }
    }
    // Shift so every allowed pair is worth more than leaving the row empty.
    final big = maximum + 1000;
    const forbidden = 1 << 40;
    final m = realColumns + n;
    int cost(int row, int column) {
      if (column >= realColumns) return big;
      final weight = weights[row][column];
      return weight == null ? forbidden : big - (weight + 500);
    }

    final u = List<int>.filled(n + 1, 0);
    final v = List<int>.filled(m + 1, 0);
    final p = List<int>.filled(m + 1, 0);
    final way = List<int>.filled(m + 1, 0);
    for (var i = 1; i <= n; i++) {
      p[0] = i;
      var j0 = 0;
      final minv = List<int>.filled(m + 1, 1 << 62);
      final used = List<bool>.filled(m + 1, false);
      do {
        used[j0] = true;
        final i0 = p[j0];
        var delta = 1 << 62;
        var j1 = 0;
        for (var j = 1; j <= m; j++) {
          if (used[j]) continue;
          final current = cost(i0 - 1, j - 1) - u[i0] - v[j];
          if (current < minv[j]) {
            minv[j] = current;
            way[j] = j0;
          }
          if (minv[j] < delta) {
            delta = minv[j];
            j1 = j;
          }
        }
        for (var j = 0; j <= m; j++) {
          if (used[j]) {
            u[p[j]] += delta;
            v[j] -= delta;
          } else {
            minv[j] -= delta;
          }
        }
        j0 = j1;
      } while (p[j0] != 0);
      do {
        final j1 = way[j0];
        p[j0] = p[j1];
        j0 = j1;
      } while (j0 != 0);
    }
    final result = List<int>.filled(n, -1);
    for (var j = 1; j <= m; j++) {
      final row = p[j];
      if (row == 0 || j - 1 >= realColumns) continue;
      if (weights[row - 1][j - 1] != null) result[row - 1] = j - 1;
    }
    return result;
  }

  /// How much worse the best alternative arrangement is. Below the decisive
  /// margin the pair is a proposal, not a preselection.
  int _assignmentGap(
    String rowId,
    _DirectOption option,
    Map<String, List<_DirectOption>> optionsByRow,
    Map<String, (String, int)> ownerOf,
    Map<String, _DirectOption> singles,
  ) {
    final candidateId = option.candidates.single.identity;
    int? scoreOf(String row, String id) {
      int? best;
      for (final item in optionsByRow[row] ?? const <_DirectOption>[]) {
        if (item.candidates.single.identity == id &&
            (best == null || item.score > best)) {
          best = item.score;
        }
      }
      return best;
    }

    var gap = 1 << 30;
    // This row taking another operation instead.
    for (final other in optionsByRow[rowId]!) {
      final otherId = other.candidates.single.identity;
      if (otherId == candidateId) continue;
      final owner = ownerOf[otherId];
      if (owner == null) {
        gap = math.min<int>(gap, option.score - other.score);
      } else {
        final swapped = scoreOf(owner.$1, candidateId) ?? 0;
        gap = math.min<int>(
          gap,
          option.score + owner.$2 - other.score - swapped,
        );
      }
    }
    // Another row taking this operation instead.
    for (final entry in optionsByRow.entries) {
      if (entry.key == rowId) continue;
      final rival = scoreOf(entry.key, candidateId);
      if (rival == null) continue;
      final rivalSingle = singles[entry.key];
      int? rivalCurrent;
      for (final owned in ownerOf.values) {
        if (owned.$1 == entry.key) rivalCurrent = owned.$2;
      }
      if (rivalCurrent == null) {
        gap = math.min<int>(gap, option.score - rival);
      } else {
        final back = rivalSingle == null
            ? 0
            : scoreOf(rowId, rivalSingle.candidates.single.identity) ?? 0;
        gap = math.min<int>(
          gap,
          option.score + rivalCurrent - rival - back,
        );
      }
    }
    return gap;
  }

  _RowAnalysis _analyzeRow(
    BankStatementMovement movement,
    List<BankReconciliationCandidate> candidates,
  ) {
    final bookingDate = movement.bookingDate;
    final amount = movement.amountClp;
    if (bookingDate == null ||
        amount == null ||
        movement.direction == BankMovementDirection.unknown) {
      return const _RowAnalysis();
    }
    final bankText = _identityText(movement);
    final evidenceText = _normalize(<String>[
      movement.normalizedDescription,
      movement.counterpartyObserved ?? '',
      movement.documentNumber ?? '',
    ].join(' '));
    final singles = <_DirectOption>[];
    final related = <_RelatedCandidate>[];
    for (final candidate in candidates) {
      if (candidate.direction != movement.direction) continue;
      final identity =
          BankCounterpartyIdentity.compare(bankText, candidate.identityNames);
      final evidence = _pointsTo(candidate, movement);
      final dateDelta = candidate.occurredOn.daysUntil(bookingDate);
      final window = evidence
          ? 400
          : identity.isStrong
              ? (_isPersonLike(candidate)
                  ? _personWindowDays
                  : _identityWindowDays)
              : directDateWindowDays;
      if (dateDelta.abs() > window) continue;
      if (evidence || identity.isStrong) {
        related
            .add(_RelatedCandidate(candidate, identity, dateDelta, evidence));
      }
      final difference = (candidate.amountClp - amount).abs();
      if (difference > directAmountToleranceClp) continue;
      final referenceExact = candidate.reference?.trim().isNotEmpty == true &&
          _normalize(candidate.reference!).length >= 4 &&
          evidenceText.contains(_normalize(candidate.reference!));
      final rounding = math.min<int>(directAmountToleranceClp, amount ~/ 100);
      singles.add(
        _DirectOption(
          movement: movement,
          candidates: <BankReconciliationCandidate>[candidate],
          score: _singleScore(
            difference: difference,
            dateDelta: dateDelta,
            identity: identity.strength,
            evidence: evidence,
            referenceExact: referenceExact,
          ),
          identity: identity.strength,
          hasEvidence: evidence,
          intrinsicallyDecisive: identity.isStrong && difference <= rounding,
          decisiveIfUnique:
              difference == 0 && dateDelta.abs() <= 3 && !identity.isConflict,
          reasons: <String>[
            difference == 0
                ? 'Monto exacto'
                : 'Diferencia de \$${_group(difference)}',
            _dateReason(dateDelta),
            if (evidence) 'Nómina ya asoció esta transferencia a este pago',
            ..._identityReasons(identity),
            if (referenceExact) 'Referencia exacta',
          ],
        ),
      );
    }
    singles.sort((left, right) {
      final byScore = right.score.compareTo(left.score);
      return byScore != 0 ? byScore : left.key.compareTo(right.key);
    });
    return _RowAnalysis(singles: singles, related: related);
  }

  /// One transfer that pays several operations of the same party, e.g. a
  /// salary plus a reimbursement in one bank transfer.
  List<_DirectOption> _groupOptions(
    BankStatementMovement movement,
    int amount,
    List<_RelatedCandidate> related,
  ) {
    if (related.isEmpty) return const [];
    final rounding = math.min<int>(directAmountToleranceClp, amount ~/ 100);
    final options = <_DirectOption>[];
    final seen = <String>{};

    void add(List<_RelatedCandidate> members, {required bool evidence}) {
      final total =
          members.fold<int>(0, (sum, item) => sum + item.candidate.amountClp);
      final difference = (total - amount).abs();
      final key = (members.map((item) => item.candidate.identity).toList()
            ..sort())
          .join(',');
      if (!seen.add(key)) return;
      final averageDelta = members.fold<int>(
            0,
            (sum, item) => sum + item.dateDelta.abs(),
          ) ~/
          members.length;
      final score = (difference == 0 ? 100 : 80) +
          60 +
          (evidence ? 150 : 0) -
          math.min<int>(averageDelta, 7) * 3 -
          math.max<int>(0, averageDelta - 7) -
          10 * (members.length - 1);
      options.add(
        _DirectOption(
          movement: movement,
          candidates: [for (final item in members) item.candidate],
          score: score,
          identity: BankIdentityStrength.strong,
          hasEvidence: evidence,
          intrinsicallyDecisive: difference <= rounding,
          decisiveIfUnique: false,
          reasons: <String>[
            '${members.length} operaciones de la misma persona o empresa '
                'suman \$${_group(total)}',
            if (difference > 0) 'Diferencia de \$${_group(difference)}',
            if (evidence) 'Nómina ya asoció esta transferencia a estos pagos',
            ..._identityReasons(members.first.identity),
          ],
        ),
      );
    }

    final pointed = related.where((item) => item.evidence).toList();
    if (pointed.isNotEmpty) {
      final base =
          pointed.fold<int>(0, (sum, item) => sum + item.candidate.amountClp);
      if (pointed.length >= 2 && (base - amount).abs() <= rounding) {
        add(pointed, evidence: true);
      } else if (base < amount) {
        final fillers = related
            .where((item) => !item.evidence && item.identity.isStrong)
            .toList()
          ..sort((left, right) =>
              left.dateDelta.abs().compareTo(right.dateDelta.abs()));
        final pool = fillers.take(10).toList(growable: false);
        for (final subset in _subsets(pool, 1, 3)) {
          final total = base +
              subset.fold<int>(
                  0, (sum, item) => sum + item.candidate.amountClp);
          if ((total - amount).abs() <= rounding) {
            add(<_RelatedCandidate>[...pointed, ...subset], evidence: true);
          }
        }
      }
    }

    final sameParty = related
        .where((item) =>
            item.identity.isStrong &&
            item.candidate.amountClp < amount &&
            item.dateDelta.abs() <= _identityWindowDays)
        .toList()
      ..sort((left, right) =>
          left.dateDelta.abs().compareTo(right.dateDelta.abs()));
    final pool = sameParty.take(12).toList(growable: false);
    for (final subset in _subsets(pool, 2, 3)) {
      final total =
          subset.fold<int>(0, (sum, item) => sum + item.candidate.amountClp);
      if (total == amount) add(subset, evidence: false);
    }
    return options;
  }

  Iterable<List<T>> _subsets<T>(List<T> items, int minSize, int maxSize) sync* {
    final n = items.length;
    final indices = <int>[];
    Iterable<List<T>> walk(int start) sync* {
      if (indices.length >= minSize) {
        yield [for (final index in indices) items[index]];
      }
      if (indices.length == maxSize) return;
      for (var index = start; index < n; index++) {
        indices.add(index);
        yield* walk(index + 1);
        indices.removeLast();
      }
    }

    yield* walk(0);
  }

  int _singleScore({
    required int difference,
    required int dateDelta,
    required BankIdentityStrength identity,
    required bool evidence,
    required bool referenceExact,
  }) {
    final distance = dateDelta.abs();
    return (difference == 0 ? 100 : math.max<int>(20, 60 - difference ~/ 25)) -
        math.min<int>(distance, 7) * 4 -
        math.max<int>(0, distance - 7) +
        switch (identity) {
          BankIdentityStrength.strong => 60,
          BankIdentityStrength.medium => 35,
          BankIdentityStrength.weak => 12,
          BankIdentityStrength.conflict => -30,
          BankIdentityStrength.unknown => 0,
        } +
        (evidence ? 150 : 0) +
        (referenceExact ? 40 : 0);
  }

  bool _pointsTo(
    BankReconciliationCandidate candidate,
    BankStatementMovement movement,
  ) {
    final date = movement.bookingDate;
    final amount = movement.amountClp;
    if (date == null || amount == null) return false;
    return candidate.bankEvidence
        .any((row) => row.date == date && row.amountClp == amount);
  }

  bool _isPersonLike(BankReconciliationCandidate candidate) =>
      candidate.counterpartyKind == BankCounterpartyKind.employee ||
      candidate.counterpartyKind == BankCounterpartyKind.payee;

  String _identityText(BankStatementMovement movement) {
    final observed = movement.counterpartyObserved?.trim() ?? '';
    return observed.isNotEmpty ? observed : movement.description;
  }

  String _dateReason(int dateDelta) {
    final distance = dateDelta.abs();
    if (distance == 0) return 'Mismo día de la operación';
    return 'Fecha contable a $distance días de la operación';
  }

  List<String> _identityReasons(BankIdentityMatch identity) =>
      switch (identity.strength) {
        BankIdentityStrength.strong => <String>[
            'Mismo titular: ${identity.matchedName}',
          ],
        BankIdentityStrength.medium => <String>[
            'Coincide parte del nombre: ${identity.matchedName}',
          ],
        BankIdentityStrength.weak => const <String>[
            'Coinciden datos de la contraparte',
          ],
        BankIdentityStrength.conflict => const <String>[
            'El banco muestra otro titular',
          ],
        BankIdentityStrength.unknown => const <String>[],
      };

  BankReconciliationProposal _directProposal(
    _DirectOption option, {
    required bool selected,
    required BankReconciliationConfidence confidence,
    required bool contested,
  }) {
    final amount = option.movement.amountClp!;
    final allocations = <BankReconciliationAllocationDraft>[];
    if (option.candidates.length == 1) {
      allocations.add(
        BankReconciliationAllocationDraft(
          candidate: option.candidates.single,
          bankAmountClp: amount,
        ),
      );
    } else {
      var assigned = 0;
      for (var index = 0; index < option.candidates.length; index++) {
        final candidate = option.candidates[index];
        final share = index == option.candidates.length - 1
            ? amount - assigned
            : candidate.amountClp;
        assigned += share;
        allocations.add(
          BankReconciliationAllocationDraft(
            candidate: candidate,
            bankAmountClp: share,
          ),
        );
      }
    }
    return BankReconciliationProposal(
      sourceRowId: option.movement.sourceRowId,
      matchKind: BankReconciliationMatchKind.direct,
      confidence: confidence,
      allocations: allocations,
      reasons: <String>[
        ...option.reasons,
        if (contested && !selected) 'Hay más de una operación posible',
      ],
      isSelectedByDefault: selected,
      instrument: option.candidates.first.instrument,
    );
  }

  // ---------------------------------------------------------------------
  // Acquirer deposits: Transbank and other configured terminals.
  // ---------------------------------------------------------------------

  _SettlementOutcome _settleDeposits({
    required List<BankStatementMovement> deposits,
    required List<BankReconciliationCandidate> sales,
    required List<BankTerminalMatchPolicy> policies,
  }) {
    if (deposits.isEmpty) return const _SettlementOutcome();
    final calibration = _calibrate(deposits, sales, policies);
    final cardSales = <_CardSale>[
      for (final sale in sales)
        _CardSale(sale, _railsFor(sale, policies, calibration)),
    ];
    final ordered = [...deposits]..sort((left, right) {
        final leftDate = left.bookingDate;
        final rightDate = right.bookingDate;
        if (leftDate == null || rightDate == null) {
          return left.ordinal.compareTo(right.ordinal);
        }
        final byDate = leftDate.compareTo(rightDate);
        return byDate != 0 ? byDate : left.ordinal.compareTo(right.ordinal);
      });
    final settled = <String>{};
    final proposals = <String, List<BankReconciliationProposal>>{};
    var unexplainedCount = 0;
    var unexplainedAmount = 0;
    for (final deposit in ordered) {
      final picks = _exactSettlements(
        deposit,
        cardSales
            .where((sale) => !settled.contains(sale.candidate.identity))
            .toList(growable: false),
      );
      if (picks.isNotEmpty) {
        final best = picks.first;
        final unique = (picks.length == 1 || picks[1].penalty > best.penalty) &&
            best.chance <= _coincidenceLimit;
        proposals[deposit.sourceRowId] = <BankReconciliationProposal>[
          _settlementProposal(deposit, best,
              selected: unique, alternatives: picks.length - 1),
          if (!unique)
            for (final other in picks.skip(1).take(2))
              _settlementProposal(deposit, other,
                  selected: false, alternatives: picks.length - 1),
        ];
        if (unique) {
          settled
              .addAll(best.sales.map((item) => item.sale.candidate.identity));
        }
      }
    }
    for (final deposit in ordered) {
      if (proposals.containsKey(deposit.sourceRowId)) continue;
      final remaining = sales
          .where((sale) => !settled.contains(sale.identity))
          .toList(growable: false);
      final amount = deposit.amountClp ?? 0;
      // Closest combination under the rates this statement proved: a small
      // residue is usually a card with another commission or a sale
      // registered with a slightly different amount.
      final near = _exactSettlements(
        deposit,
        cardSales
            .where((sale) => !settled.contains(sale.candidate.identity))
            .toList(growable: false),
        nearTolerance: math.max<int>(100, amount ~/ 250),
      );
      final matching = _matchingPolicies(deposit, policies);
      var estimates = near.isNotEmpty
          ? <BankReconciliationProposal>[
              for (final pick in near.take(2))
                _settlementProposal(
                  deposit,
                  pick,
                  selected: false,
                  alternatives: near.length - 1,
                ),
            ]
          : matching.isEmpty
              ? const <BankReconciliationProposal>[]
              : _terminalProposals(deposit, remaining, matching);
      if (estimates.isEmpty && _isTransbankMovement(deposit)) {
        estimates = _transbankProposals(deposit, remaining);
      }
      proposals[deposit.sourceRowId] = estimates;
      unexplainedCount++;
      unexplainedAmount += deposit.amountClp ?? 0;
    }
    return _SettlementOutcome(
      proposals: proposals,
      insights: <BankReconciliationInsight>[
        ...calibration.insights,
        if (unexplainedCount > 0 && sales.isNotEmpty)
          BankReconciliationInsight(
            title: '$unexplainedCount abono(s) de tarjeta sin cuadre exacto',
            body: 'Suman \$${_group(unexplainedAmount)} y ninguna combinación '
                'de ventas con tarjeta registradas los explica al peso. Suele '
                'ser una venta con tarjeta sin registrar o registrada con otro '
                'medio de pago; revisa la estimación antes de aceptarla.',
            tone: BankInsightTone.warning,
          ),
      ],
    );
  }

  _Calibration _calibrate(
    List<BankStatementMovement> deposits,
    List<BankReconciliationCandidate> sales,
    List<BankTerminalMatchPolicy> policies,
  ) {
    // Each deposit equal to one sale net of commission + VAT proves a rate.
    final fits = <_RateFit>[];
    for (final deposit in deposits) {
      final date = deposit.bookingDate;
      final amount = deposit.amountClp;
      if (date == null || amount == null) continue;
      for (final sale in sales) {
        final lag = calendar.businessDaysBetween(sale.occurredOn, date);
        if (lag < 1 || lag > 5) continue;
        final rate = _impliedRateBps(sale.amountClp, amount);
        if (rate == null) continue;
        fits.add(_RateFit(_instrumentOf(sale, policies), rate, lag));
      }
    }
    final debit = _dominantRate(
      fits.where((fit) => fit.instrument != BankPaymentInstrument.credit),
      minimumFits: 3,
    );
    final credit = _dominantRate(
      fits.where((fit) =>
          fit.instrument != BankPaymentInstrument.debit &&
          (debit == null || (fit.rateBps - debit.centerBps).abs() > 3)),
      minimumFits: 2,
    );
    final insights = <BankReconciliationInsight>[];
    for (final (instrument, learned)
        in <(BankPaymentInstrument, _LearnedRate?)>[
      (BankPaymentInstrument.debit, debit),
      (BankPaymentInstrument.credit, credit),
    ]) {
      if (learned == null || learned.fits < 3) continue;
      final policy = policies
          .where((item) => item.instrument == instrument)
          .fold<BankTerminalMatchPolicy?>(
              null,
              (latest, item) => latest == null ||
                      item.effectiveFrom.compareTo(latest.effectiveFrom) > 0
                  ? item
                  : latest);
      if (policy == null) continue;
      final rateOff =
          (learned.centerBps - policy.commissionRateBps).abs() >= 10;
      final lagOff = learned.lag != policy.settlementBusinessDays;
      if (!rateOff && !lagOff) continue;
      final label =
          instrument == BankPaymentInstrument.debit ? 'débito' : 'crédito';
      insights.add(
        BankReconciliationInsight(
          title: '${policy.providerName} no cobra lo configurado en $label',
          body: 'Según ${learned.fits} abonos que cuadran al peso con una sola '
              'venta, ${policy.providerName} cobra '
              '${_percent(learned.centerBps)} + IVA y abona a '
              '${learned.lag} día(s) hábil(es). En Terminales POS está '
              '${_percent(policy.commissionRateBps)} a '
              '${policy.settlementBusinessDays} día(s). Esta revisión ya usa '
              'lo observado; corrige la configuración para que la '
              'contabilidad de comisiones calce.',
          tone: BankInsightTone.warning,
        ),
      );
    }
    return _Calibration(debit: debit, credit: credit, insights: insights);
  }

  BankPaymentInstrument _instrumentOf(
    BankReconciliationCandidate sale,
    List<BankTerminalMatchPolicy> policies,
  ) {
    if (sale.instrument != BankPaymentInstrument.unknown) {
      return sale.instrument;
    }
    for (final policy in policies) {
      if (policy.paymentMethodCode == sale.paymentMethodCode) {
        return policy.instrument;
      }
    }
    return BankPaymentInstrument.unknown;
  }

  /// Commission rate (basis points, VAT on top) that nets [gross] to
  /// [deposit] to the peso, if one exists in a plausible range.
  int? _impliedRateBps(int gross, int deposit) {
    final deduction = gross - deposit;
    if (deduction <= 0) return null;
    final approximate = deduction / 1.19 / gross * 10000;
    if (approximate < 40 || approximate > 350) return null;
    for (var rate = approximate.floor() - 1;
        rate <= approximate.ceil() + 1;
        rate++) {
      if (_net(gross, rate, 1900) == deposit) return rate;
    }
    return null;
  }

  _LearnedRate? _dominantRate(Iterable<_RateFit> fits,
      {required int minimumFits}) {
    final counts = <int, int>{};
    final lags = <int, Map<int, int>>{};
    for (final fit in fits) {
      counts.update(fit.rateBps, (count) => count + 1, ifAbsent: () => 1);
      lags.putIfAbsent(fit.rateBps, () => <int, int>{}).update(
            fit.lag,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
    }
    int cluster(int center) =>
        (counts[center - 1] ?? 0) +
        (counts[center] ?? 0) +
        (counts[center + 1] ?? 0);
    int? bestCenter;
    for (final rate in counts.keys) {
      if (bestCenter == null ||
          cluster(rate) > cluster(bestCenter) ||
          (cluster(rate) == cluster(bestCenter) &&
              (counts[rate] ?? 0) > (counts[bestCenter] ?? 0))) {
        bestCenter = rate;
      }
    }
    if (bestCenter == null || cluster(bestCenter) < minimumFits) return null;
    // Random single-sale coincidences spread over the whole range; the true
    // rate concentrates. Require the cluster to dominate the runner-up.
    final runnerUp = counts.keys
        .where((rate) => (rate - bestCenter!).abs() > 2)
        .map(cluster)
        .fold<int>(0, math.max);
    if (cluster(bestCenter) < runnerUp * 2) return null;
    final members = <int>[
      for (final rate in <int>[bestCenter - 1, bestCenter, bestCenter + 1])
        if ((counts[rate] ?? 0) > 0) rate,
    ];
    final lagCounts = <int, int>{};
    for (final rate in members) {
      for (final entry in (lags[rate] ?? const <int, int>{}).entries) {
        lagCounts.update(entry.key, (count) => count + entry.value,
            ifAbsent: () => entry.value);
      }
    }
    final lag = lagCounts.entries
        .reduce((left, right) => right.value > left.value ? right : left)
        .key;
    return _LearnedRate(
      centerBps: bestCenter,
      ratesBps: members,
      lag: lag,
      fits: cluster(bestCenter),
    );
  }

  List<_Rail> _railsFor(
    BankReconciliationCandidate sale,
    List<BankTerminalMatchPolicy> policies,
    _Calibration calibration,
  ) {
    final rails = <_Rail>[];
    final configured = policies
        .where((policy) =>
            policy.paymentMethodCode == sale.paymentMethodCode &&
            policy.appliesOn(sale.occurredOn))
        .toList(growable: false);
    if (configured.isNotEmpty) {
      for (final policy in configured) {
        final minimumLag = policy.settlementBusinessDays;
        final maximumLag =
            policy.settlementBusinessDays + policy.bookingGraceBusinessDays;
        final learned = policy.instrument == BankPaymentInstrument.credit
            ? calibration.credit
            : policy.instrument == BankPaymentInstrument.debit
                ? calibration.debit
                : null;
        // When the statement proves another rate, the configured one only
        // produces coincidental fits.
        final contradicted = learned != null &&
            learned.fits >= 3 &&
            (learned.centerBps - policy.commissionRateBps).abs() >= 10;
        if (!contradicted) {
          rails.add(_Rail(
            instrument: policy.instrument,
            rateBps: policy.commissionRateBps,
            vatBps: policy.commissionVatBps,
            minimumLag: minimumLag,
            maximumLag: maximumLag,
            policy: policy,
            learned: false,
          ));
        }
        if (learned == null) continue;
        for (final rate in learned.ratesBps) {
          if (rate == policy.commissionRateBps) continue;
          rails.add(_Rail(
            instrument: policy.instrument,
            rateBps: rate,
            vatBps: policy.commissionVatBps,
            minimumLag:
                math.max<int>(1, math.min<int>(minimumLag, learned.lag - 1)),
            maximumLag: math.max<int>(maximumLag, learned.lag + 1),
            policy: policy,
            learned: true,
          ));
        }
      }
      return rails;
    }
    final isLegacyCard = sale.paymentMethodCode == 'card' ||
        (sale.provider == BankSettlementProvider.transbank &&
            sale.instrument == BankPaymentInstrument.unknown);
    if (!isLegacyCard) return rails;
    for (final (instrument, learned)
        in <(BankPaymentInstrument, _LearnedRate?)>[
      (BankPaymentInstrument.debit, calibration.debit),
      (BankPaymentInstrument.credit, calibration.credit),
    ]) {
      if (learned == null) continue;
      for (final rate in learned.ratesBps) {
        rails.add(_Rail(
          instrument: instrument,
          rateBps: rate,
          vatBps: 1900,
          minimumLag: math.max<int>(1, learned.lag - 1),
          maximumLag: learned.lag + 1,
          policy: null,
          learned: true,
        ));
      }
    }
    return rails;
  }

  /// Combinations of card sales whose nets add up to the deposit to the peso.
  /// Terminal-cleared sales and legacy bank-booked sales are never mixed in
  /// one deposit: each posts a different settlement.
  List<_SettlementPick> _exactSettlements(
    BankStatementMovement deposit,
    List<_CardSale> sales, {
    int? nearTolerance,
  }) {
    final date = deposit.bookingDate;
    final amount = deposit.amountClp;
    if (date == null || amount == null) return const [];
    final picks = <_SettlementPick>[];
    for (final terminal in <bool>[true, false]) {
      final eligible = <(_CardSale, List<_Rail>)>[];
      for (final sale in sales) {
        if (sale.isTerminal != terminal) continue;
        final lag =
            calendar.businessDaysBetween(sale.candidate.occurredOn, date);
        final rails = sale.rails
            .where((rail) => lag >= rail.minimumLag && lag <= rail.maximumLag)
            .toList(growable: false);
        if (rails.isNotEmpty) eligible.add((sale, rails));
      }
      if (eligible.isEmpty) continue;
      eligible.sort((left, right) => left.$1.order.compareTo(right.$1.order));
      final pool = eligible.take(22).toList(growable: false);
      final slack = nearTolerance ?? math.max<int>(2, pool.length);
      // sum -> up to four partial picks reaching it.
      var states = <int, List<List<_PickedSale>>>{
        0: <List<_PickedSale>>[<_PickedSale>[]],
      };
      for (final (sale, rails) in pool) {
        final next = <int, List<List<_PickedSale>>>{
          for (final entry in states.entries) entry.key: [...entry.value],
        };
        for (final entry in states.entries) {
          for (final rail in rails) {
            final sum = entry.key + rail.net(sale.candidate.amountClp);
            if (sum > amount + slack) continue;
            final bucket = next.putIfAbsent(sum, () => <List<_PickedSale>>[]);
            for (final partial in entry.value) {
              if (bucket.length >= 4) break;
              bucket.add(<_PickedSale>[...partial, _PickedSale(sale, rail)]);
            }
          }
        }
        states = next;
      }
      // How crowded the reachable sums are just below the deposit: with many
      // sales a combination can hit any amount to the peso by chance.
      const window = 400;
      final nearby = states.keys
          .where((sum) => sum >= amount - window && sum <= amount + slack)
          .length;
      final density = nearby / (window + slack + 1);
      for (final entry in states.entries) {
        for (final pick in entry.value) {
          if (pick.isEmpty) continue;
          final tolerance = nearTolerance ?? math.max<int>(1, pick.length);
          if ((entry.key - amount).abs() > tolerance) continue;
          picks.add(_SettlementPick(
            sales: pick,
            netClp: entry.key,
            chance: density * (2 * tolerance + 1),
            penalty: _settlementPenalty(
                  pick,
                  pool.map((item) => item.$1),
                  date,
                ) +
                (nearTolerance == null ? 0 : (entry.key - amount).abs()),
          ));
        }
      }
    }
    // Two picks that differ only by the rail of the same sales are one answer.
    final unique = <String, _SettlementPick>{};
    for (final pick in picks) {
      if (!_residueFits(pick, amount)) continue;
      final key =
          (pick.sales.map((item) => item.sale.candidate.identity).toList()
                ..sort())
              .join(',');
      final current = unique[key];
      if (current == null || pick.penalty < current.penalty) unique[key] = pick;
    }
    return unique.values.toList()
      ..sort((left, right) => left.penalty.compareTo(right.penalty));
  }

  bool _residueFits(_SettlementPick pick, int amount) {
    var largest = pick.sales.first;
    var total = 0;
    for (final item in pick.sales) {
      total += item.rail.net(item.sale.candidate.amountClp);
      if (item.sale.candidate.amountClp > largest.sale.candidate.amountClp) {
        largest = item;
      }
    }
    final share =
        largest.rail.net(largest.sale.candidate.amountClp) + amount - total;
    return share > 0 && share <= largest.sale.candidate.amountClp;
  }

  /// Lower is likelier: sales settle in order, so leaving an older eligible
  /// sale behind while taking a newer one costs, and so does an unusual lag.
  int _settlementPenalty(
    List<_PickedSale> pick,
    Iterable<_CardSale> pool,
    BankCivilDate date,
  ) {
    final chosen = pick.map((item) => item.sale).toSet();
    final newest = pick
        .map((item) => item.sale.order)
        .reduce((left, right) => left.compareTo(right) >= 0 ? left : right);
    var penalty = 0;
    for (final sale in pool) {
      if (!chosen.contains(sale) && sale.order.compareTo(newest) < 0) {
        penalty += 10;
      }
    }
    for (final item in pick) {
      final lag =
          calendar.businessDaysBetween(item.sale.candidate.occurredOn, date);
      penalty += (lag - item.rail.minimumLag).abs() * 2;
      if (!item.rail.learned && item.rail.policy == null) penalty += 1;
    }
    return penalty;
  }

  BankReconciliationProposal _settlementProposal(
    BankStatementMovement deposit,
    _SettlementPick pick, {
    required bool selected,
    required int alternatives,
  }) {
    final amount = deposit.amountClp!;
    // Each sale receives its own net; the residue goes to the largest sale,
    // so no sale is credited more than its gross (the database rejects that).
    final shares = <int>[
      for (final item in pick.sales)
        item.rail.net(item.sale.candidate.amountClp),
    ];
    var largest = 0;
    for (var index = 1; index < pick.sales.length; index++) {
      if (pick.sales[index].sale.candidate.amountClp >
          pick.sales[largest].sale.candidate.amountClp) {
        largest = index;
      }
    }
    shares[largest] +=
        amount - shares.fold<int>(0, (sum, share) => sum + share);
    final allocations = <BankReconciliationAllocationDraft>[
      for (var index = 0; index < pick.sales.length; index++)
        BankReconciliationAllocationDraft(
          candidate: pick.sales[index].sale.candidate,
          bankAmountClp: shares[index],
        ),
    ];
    final gross = pick.sales
        .fold<int>(0, (sum, item) => sum + item.sale.candidate.amountClp);
    final instruments = pick.sales.map((item) => item.rail.instrument).toSet();
    final terminal = pick.sales.first.sale.isTerminal;
    BankTerminalMatchPolicy? policy;
    for (final item in pick.sales) {
      policy ??= item.rail.policy;
    }
    final learned = pick.sales.any((item) => item.rail.learned);
    final rates = <String>{
      for (final item in pick.sales)
        '${_instrumentLabel(item.rail.instrument)} ${_percent(item.rail.rateBps)}',
    }.join(' · ');
    return BankReconciliationProposal(
      sourceRowId: deposit.sourceRowId,
      matchKind: terminal
          ? BankReconciliationMatchKind.processorEstimate
          : BankReconciliationMatchKind.transbankEstimate,
      confidence: selected
          ? BankReconciliationConfidence.high
          : BankReconciliationConfidence.medium,
      allocations: allocations,
      reasons: <String>[
        policy == null
            ? '${pick.sales.length} venta(s) con tarjeta'
            : '${pick.sales.length} venta(s) · ${policy.providerName} / '
                '${policy.terminalName}',
        _pickBreakdown(pick),
        'Comisión $rates + IVA por venta'
            '${learned ? ' (observada en esta cartola)' : ' (configurada)'}',
        'Bruto \$${_group(gross)} · abono esperado '
            '\$${_group(pick.netClp)} · cartola \$${_group(amount)}',
        if ((pick.netClp - amount).abs() <= math.max<int>(1, pick.sales.length))
          'Cuadra al peso'
        else
          'Diferencia de \$${_group((pick.netClp - amount).abs())} con lo '
              'esperado: puede ser una tarjeta con otra comisión o una venta '
              'registrada por otro monto',
        if (!selected && alternatives > 0)
          'Otra combinación de ventas también cuadra: elige la correcta',
      ],
      isSelectedByDefault: selected,
      estimatedGrossClp: gross,
      estimatedDifferenceClp: gross - amount,
      instrument: instruments.length == 1
          ? instruments.single
          : BankPaymentInstrument.unknown,
    );
  }

  String _pickBreakdown(_SettlementPick pick) {
    final counts = <BankPaymentInstrument, int>{};
    for (final item in pick.sales) {
      counts.update(item.rail.instrument, (count) => count + 1,
          ifAbsent: () => 1);
    }
    final entries = counts.entries.toList(growable: false)
      ..sort((left, right) =>
          _instrumentOrder(left.key).compareTo(_instrumentOrder(right.key)));
    return entries
        .map((entry) => '${entry.value} ${_instrumentLabel(entry.key)}')
        .join(' + ');
  }

  static int _net(int gross, int rateBps, int vatBps) {
    final commission = (gross * rateBps / 10000).round();
    final vat = (commission * vatBps / 10000).round();
    return gross - commission - vat;
  }

  String _percent(int basisPoints) {
    final whole = basisPoints ~/ 100;
    final fraction = (basisPoints % 100).toString().padLeft(2, '0');
    return '$whole,$fraction%';
  }

  // ---------------------------------------------------------------------
  // Fallback estimates for deposits no exact combination explains.
  // ---------------------------------------------------------------------

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

class _DirectOption {
  _DirectOption({
    required this.movement,
    required this.candidates,
    required this.score,
    required this.identity,
    required this.hasEvidence,
    required this.intrinsicallyDecisive,
    required this.decisiveIfUnique,
    required this.reasons,
  })  : candidateIds = candidates.map((item) => item.identity).toSet(),
        key = candidates.map((item) => item.identity).join(',');

  final BankStatementMovement movement;
  final List<BankReconciliationCandidate> candidates;
  final int score;
  final BankIdentityStrength identity;

  /// Another module already tied this bank row to the operation(s).
  final bool hasEvidence;

  /// Strong name and amount: decisive unless something scores close to it.
  final bool intrinsicallyDecisive;

  /// Exact amount within three days and no contradicting name: decisive
  /// only when nothing else competes for either side.
  final bool decisiveIfUnique;
  final List<String> reasons;
  final Set<String> candidateIds;
  final String key;
}

class _RowAnalysis {
  const _RowAnalysis({
    this.singles = const <_DirectOption>[],
    this.related = const <_RelatedCandidate>[],
    this.groups = const <_DirectOption>[],
  });

  /// One-operation options, best first.
  final List<_DirectOption> singles;

  /// Operations of the same party (or tied by Nómina) that a group may use.
  final List<_RelatedCandidate> related;
  final List<_DirectOption> groups;

  _RowAnalysis withGroups(List<_DirectOption> value) =>
      _RowAnalysis(singles: singles, related: related, groups: value);
}

class _DirectChoice {
  const _DirectChoice({
    required this.option,
    required this.decisive,
    required this.contested,
  });

  final _DirectOption option;
  final bool decisive;
  final bool contested;
}

class _RelatedCandidate {
  const _RelatedCandidate(
    this.candidate,
    this.identity,
    this.dateDelta,
    this.evidence,
  );

  final BankReconciliationCandidate candidate;
  final BankIdentityMatch identity;
  final int dateDelta;
  final bool evidence;
}

class _SettlementOutcome {
  const _SettlementOutcome({
    this.proposals = const <String, List<BankReconciliationProposal>>{},
    this.insights = const <BankReconciliationInsight>[],
  });

  final Map<String, List<BankReconciliationProposal>> proposals;
  final List<BankReconciliationInsight> insights;
}

class _RateFit {
  const _RateFit(this.instrument, this.rateBps, this.lag);

  final BankPaymentInstrument instrument;
  final int rateBps;
  final int lag;
}

class _LearnedRate {
  const _LearnedRate({
    required this.centerBps,
    required this.ratesBps,
    required this.lag,
    required this.fits,
  });

  final int centerBps;

  /// Neighbouring rates that also proved exact (card brands differ by 1 bp).
  final List<int> ratesBps;
  final int lag;
  final int fits;
}

class _Calibration {
  const _Calibration({this.debit, this.credit, required this.insights});

  final _LearnedRate? debit;
  final _LearnedRate? credit;
  final List<BankReconciliationInsight> insights;
}

class _Rail {
  const _Rail({
    required this.instrument,
    required this.rateBps,
    required this.vatBps,
    required this.minimumLag,
    required this.maximumLag,
    required this.policy,
    required this.learned,
  });

  final BankPaymentInstrument instrument;
  final int rateBps;
  final int vatBps;
  final int minimumLag;
  final int maximumLag;
  final BankTerminalMatchPolicy? policy;
  final bool learned;

  int net(int gross) => BankReconciliationMatcher._net(gross, rateBps, vatBps);
}

class _CardSale {
  _CardSale(this.candidate, this.rails)
      : order =
            '${(candidate.occurredAt ?? candidate.occurredOn.utcDate).toUtc().toIso8601String()}'
                '|${candidate.identity}';

  final BankReconciliationCandidate candidate;
  final List<_Rail> rails;

  /// Sales settle in the order they were taken.
  final String order;

  /// Cleared through a configured terminal profile (not booked to the bank).
  bool get isTerminal => rails.any((rail) => rail.policy != null);
}

class _PickedSale {
  const _PickedSale(this.sale, this.rail);

  final _CardSale sale;
  final _Rail rail;
}

class _SettlementPick {
  const _SettlementPick({
    required this.sales,
    required this.netClp,
    required this.chance,
    required this.penalty,
  });

  final List<_PickedSale> sales;
  final int netClp;

  /// Expected number of combinations that would hit the deposit by chance.
  final double chance;
  final int penalty;
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
