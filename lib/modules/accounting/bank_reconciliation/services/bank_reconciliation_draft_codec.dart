import '../models/bank_reconciliation_models.dart';
import 'bank_reconciliation_ai_analyst.dart';

/// What a restored draft brought back.
class BankDraftRestore {
  const BankDraftRestore({
    required this.draft,
    required this.restoredRowIds,
    required this.droppedCount,
  });

  final BankReconciliationPreparedDraft draft;

  /// Review ids of the movements whose saved decision came back.
  final Set<String> restoredRowIds;

  /// Saved decisions today's ERP no longer allows: an operation another
  /// movement took, a salary Nómina paid meanwhile.
  final int droppedCount;
}

/// The conciliation's saved draft: what the operator decided on each
/// movement he touched and has not applied, and what the AI read in it.
///
/// Only touched movements are saved. The rest are reviewed again against
/// today's ERP on reopening, so a sale registered since then can still be
/// proposed. A saved decision is restored only while it still holds: its
/// operations exist and are free, its salary is still owed.
class BankReconciliationDraftCodec {
  const BankReconciliationDraftCodec();

  static const version = 1;

  /// Stable across sittings and statement groupings: the file and its own
  /// row id, never the id the review made unique.
  static String rowKey(
    BankReconciliationPreparedDraft draft,
    BankReconciliationRowDraft row,
  ) =>
      '${row.sourceFileSha256 ?? draft.fileSha256}:'
      '${row.movement.persistedRowId}';

  /// [saved] is the draft the conciliation had when this sitting opened it:
  /// what it holds for statements this review did not load (July imported
  /// again alone, in a conciliation of four) is kept as it was, never
  /// dropped by the next save.
  Map<String, dynamic> encode(
    BankReconciliationPreparedDraft draft,
    Set<String> touchedRowIds, {
    Map<String, dynamic>? saved,
  }) {
    final loaded = <String>{
      draft.fileSha256,
      for (final source in draft.sources) source.fileSha256,
      for (final row in draft.rows)
        if (row.sourceFileSha256 != null) row.sourceFileSha256!,
    };
    final savedRows = saved?['version'] == version ? saved!['rows'] : null;
    return <String, dynamic>{
      'version': version,
      'rows': <String, dynamic>{
        if (savedRows is Map)
          for (final entry in savedRows.entries)
            if (!loaded.contains(entry.key.toString().split(':').first))
              entry.key.toString(): entry.value,
        for (final row in draft.rows)
          if (!row.isSettled &&
              touchedRowIds.contains(row.movement.sourceRowId))
            rowKey(draft, row): _row(row),
      },
    };
  }

  Map<String, dynamic> _row(BankReconciliationRowDraft row) {
    final selected = row.selectedProposal;
    return <String, dynamic>{
      if (selected != null &&
          selected.matchKind == BankReconciliationMatchKind.manual)
        'manual': <String>[
          for (final allocation in selected.allocations)
            allocation.candidate.identity,
        ]
      else if (selected != null)
        'selected': BankReconciliationRowDraft.proposalIdentity(selected),
      'resolution': _resolution(row.effectiveResolution),
      if (row.aiAnalysis != null) 'ai': _ai(row.aiAnalysis!),
    };
  }

  Map<String, dynamic> _resolution(BankReconciliationResolutionDraft value) {
    return <String, dynamic>{
      'action': value.action.name,
      if (value.accountId != null) 'account_id': value.accountId,
      if (value.paymentMethodId != null)
        'payment_method_id': value.paymentMethodId,
      if (value.description != null) 'description': value.description,
      if (value.counterparty != null) 'counterparty': value.counterparty,
      if (value.reference != null) 'reference': value.reference,
      if (value.reason != null) 'reason': value.reason,
      if (value.payroll != null) 'payroll_line_id': value.payroll!.lineId,
      if (value.splitParts.isNotEmpty)
        'split_parts': <Map<String, dynamic>>[
          for (final part in value.splitParts)
            <String, dynamic>{
              if (part.accountId != null) 'account_id': part.accountId,
              if (part.amountClp != null) 'amount': part.amountClp,
              'description': part.description,
              if (part.supplierId != null) 'supplier_id': part.supplierId,
              'is_expense': part.isExpense,
            },
        ],
    };
  }

  Map<String, dynamic> _ai(BankAiAnalysis analysis) {
    return <String, dynamic>{
      'explanation': analysis.explanation,
      if (analysis.question != null) 'question': analysis.question,
      if (analysis.missing != null) 'missing': analysis.missing,
      if (analysis.answer != null) 'answer': analysis.answer,
      if (analysis.proposal != null)
        'link': <String>[
          for (final allocation in analysis.proposal!.allocations)
            allocation.candidate.identity,
        ],
      if (analysis.resolution != null)
        'resolution': _resolution(analysis.resolution!),
    };
  }

  BankDraftRestore restore(
    BankReconciliationPreparedDraft draft,
    Map<String, dynamic> saved,
  ) {
    final rows = saved['rows'];
    if (saved['version'] != version || rows is! Map || rows.isEmpty) {
      return BankDraftRestore(
        draft: draft,
        restoredRowIds: const <String>{},
        droppedCount: 0,
      );
    }
    final catalog = <String, BankReconciliationCandidate>{
      for (final candidate in draft.candidateCatalog)
        candidate.identity: candidate,
    };
    // An operation is restored on one movement only, and never over one
    // today's review already gives to a movement nobody touched.
    final taken = <String>{
      for (final row in draft.rows)
        if (row.isSettled || rows[rowKey(draft, row)] is! Map)
          for (final allocation in row.selectedProposal?.allocations ??
              const <BankReconciliationAllocationDraft>[])
            allocation.candidate.identity,
    };
    final replacements = <BankReconciliationRowDraft>[];
    final restored = <String>{};
    var dropped = 0;
    for (final row in draft.rows) {
      if (row.isSettled) continue;
      final entry = rows[rowKey(draft, row)];
      if (entry is! Map) continue;
      final amount = row.movement.amountClp;
      var proposals = row.proposals;
      String? selectedId;
      var holds = true;

      final manual = entry['manual'];
      final selected = entry['selected'];
      if (manual is List && amount != null) {
        final candidates = <BankReconciliationCandidate>[
          for (final id in manual)
            if (catalog[id.toString()] case final candidate?) candidate,
        ];
        final proposal = candidates.length == manual.length &&
                !candidates.any((item) => taken.contains(item.identity))
            ? BankReconciliationProposal.manual(
                sourceRowId: row.movement.sourceRowId,
                movementAmountClp: amount,
                candidates: candidates,
              )
            : null;
        if (proposal == null) {
          holds = false;
        } else {
          proposals = <BankReconciliationProposal>[
            ...proposals.where(
                (item) => item.matchKind != BankReconciliationMatchKind.manual),
            proposal,
          ];
          selectedId = BankReconciliationRowDraft.proposalIdentity(proposal);
        }
      } else if (selected is String) {
        final proposal = proposals
            .where((item) =>
                BankReconciliationRowDraft.proposalIdentity(item) == selected)
            .firstOrNull;
        if (proposal == null ||
            proposal.allocations
                .any((item) => taken.contains(item.candidate.identity))) {
          holds = false;
        } else {
          selectedId = selected;
        }
      }

      var resolution = _decodeResolution(entry['resolution']);
      if (resolution?.action == BankReconciliationActionKind.payPayroll) {
        // The salary is taken as Nómina owes it today, never as saved.
        final current = row.suggestion?.resolution;
        final savedLine = entry['resolution'] is Map
            ? (entry['resolution'] as Map)['payroll_line_id']?.toString()
            : null;
        if (current?.action == BankReconciliationActionKind.payPayroll &&
            current?.payroll?.lineId == savedLine) {
          resolution = current;
        } else {
          resolution = null;
          holds = false;
        }
      }
      if (resolution?.action ==
              BankReconciliationActionKind.associateExisting &&
          selectedId == null) {
        holds = false;
      }

      final analysis = _decodeAi(entry['ai'], row, catalog);
      if (!holds) {
        dropped++;
        if (analysis != null) {
          replacements.add(row.copyWith(aiAnalysis: analysis));
          restored.add(row.movement.sourceRowId);
        }
        continue;
      }
      final replacement = BankReconciliationRowDraft(
        movement: row.movement,
        proposals: proposals,
        selectedProposalId: selectedId,
        selectDefault: false,
        disposition: row.disposition,
        resolution: resolution ??
            const BankReconciliationResolutionDraft(
              action: BankReconciliationActionKind.pending,
            ),
        suggestion: row.suggestion,
        sourceFileSha256: row.sourceFileSha256,
        settled: row.settled,
        aiAnalysis: analysis,
      );
      for (final allocation in replacement.selectedProposal?.allocations ??
          const <BankReconciliationAllocationDraft>[]) {
        taken.add(allocation.candidate.identity);
      }
      replacements.add(replacement);
      restored.add(row.movement.sourceRowId);
    }
    return BankDraftRestore(
      draft: replacements.isEmpty ? draft : draft.replaceRows(replacements),
      restoredRowIds: restored,
      droppedCount: dropped,
    );
  }

  BankReconciliationResolutionDraft? _decodeResolution(Object? raw) {
    if (raw is! Map) return null;
    final action = BankReconciliationActionKind.values
        .where((value) => value.name == raw['action'])
        .firstOrNull;
    if (action == null) return null;
    String? text(String key) {
      final value = raw[key]?.toString();
      return value == null || value.isEmpty ? null : value;
    }

    final parts = raw['split_parts'];
    return BankReconciliationResolutionDraft(
      action: action,
      accountId: text('account_id'),
      paymentMethodId: text('payment_method_id'),
      description: text('description'),
      counterparty: text('counterparty'),
      reference: text('reference'),
      reason: text('reason'),
      splitParts: <BankSplitPartDraft>[
        if (parts is List)
          for (final part in parts.whereType<Map>())
            BankSplitPartDraft(
              accountId: part['account_id']?.toString(),
              amountClp: part['amount'] is num
                  ? (part['amount'] as num).toInt()
                  : null,
              description: part['description']?.toString() ?? '',
              supplierId: part['supplier_id']?.toString(),
              isExpense: part['is_expense'] == true,
            ),
      ],
    );
  }

  BankAiAnalysis? _decodeAi(
    Object? raw,
    BankReconciliationRowDraft row,
    Map<String, BankReconciliationCandidate> catalog,
  ) {
    if (raw is! Map) return null;
    final explanation = raw['explanation']?.toString();
    if (explanation == null || explanation.isEmpty) return null;
    final link = raw['link'];
    BankReconciliationProposal? proposal;
    final amount = row.movement.amountClp;
    if (link is List && amount != null) {
      final candidates = <BankReconciliationCandidate>[
        for (final id in link)
          if (catalog[id.toString()] case final candidate?) candidate,
      ];
      if (candidates.length == link.length) {
        proposal = BankReconciliationAiAnalyst.linkProposal(
          sourceRowId: row.movement.sourceRowId,
          movementAmountClp: amount,
          candidates: candidates,
        );
      }
    }
    return BankAiAnalysis(
      explanation: explanation,
      question: raw['question']?.toString(),
      missing: raw['missing']?.toString(),
      answer: raw['answer']?.toString(),
      proposal: proposal,
      resolution: _decodeResolution(raw['resolution']),
    );
  }
}
