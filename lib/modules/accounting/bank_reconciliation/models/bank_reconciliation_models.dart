import 'dart:collection';

enum BankMovementDirection { debit, credit, unknown }

/// Instrument observed or inferred for a card settlement.
///
/// A sale records its rail explicitly. A mixed bank deposit remains `unknown`
/// because the statement line itself represents a cohort, not one card type.
enum BankPaymentInstrument { unknown, debit, credit, prepaid }

enum BankSettlementProvider { none, transbank, mercadoPago, other }

enum BankReconciliationTargetKind {
  salesPayment,
  purchasePayment,
  expensePayment,
  expense,
  journalEntry,
}

enum BankReconciliationMatchKind {
  direct,
  processorEstimate,
  transbankEstimate,
  manual,
}

enum BankReconciliationConfidence { low, medium, high }

enum BankReconciliationDisposition { pending, reconciled, ignored, held }

/// Versioned acquiring rule used to estimate one terminal deposit.
///
/// The statement description identifies the terminal profile; the payment
/// method identifies the debit/credit rail. This keeps future providers and
/// terminals out of matcher constants.
class BankTerminalMatchPolicy {
  BankTerminalMatchPolicy({
    required this.profileId,
    required this.providerCode,
    required this.providerName,
    required this.terminalName,
    required List<String> descriptorPatterns,
    required this.paymentMethodCode,
    required this.instrument,
    required this.commissionRateBps,
    required this.commissionVatBps,
    required this.settlementBusinessDays,
    required this.bookingGraceBusinessDays,
    required this.amountToleranceClp,
    required this.effectiveFrom,
    this.effectiveTo,
  })  : assert(profileId != ''),
        assert(paymentMethodCode != ''),
        descriptorPatterns = List.unmodifiable(descriptorPatterns);

  final String profileId;
  final String providerCode;
  final String providerName;
  final String terminalName;
  final List<String> descriptorPatterns;
  final String paymentMethodCode;
  final BankPaymentInstrument instrument;
  final int commissionRateBps;
  final int commissionVatBps;
  final int settlementBusinessDays;
  final int bookingGraceBusinessDays;
  final int amountToleranceClp;
  final BankCivilDate effectiveFrom;
  final BankCivilDate? effectiveTo;

  int expectedNetClp(int grossClp) {
    final commission = (grossClp * commissionRateBps / 10000).round();
    final vat = (commission * commissionVatBps / 10000).round();
    return grossClp - commission - vat;
  }

  bool appliesOn(BankCivilDate date) =>
      date.compareTo(effectiveFrom) >= 0 &&
      (effectiveTo == null || date.compareTo(effectiveTo!) <= 0);
}

/// Operator intent for one statement movement.
///
/// A movement is only [associateExisting], [createExpense] or
/// [classifyAccount] when it will be backed by an accounting operation. A
/// dismissed movement is deliberately excluded with a reason; it is never
/// presented as reconciled.
enum BankReconciliationActionKind {
  pending,
  associateExisting,
  createExpense,
  classifyAccount,
  dismiss,
}

class BankReconciliationAccountOption {
  const BankReconciliationAccountOption({
    required this.accountId,
    required this.code,
    required this.name,
  });

  final String accountId;
  final String code;
  final String name;

  String get label => '$code · $name';
}

class BankReconciliationLedgerAccountOption {
  const BankReconciliationLedgerAccountOption({
    required this.accountId,
    required this.code,
    required this.name,
    required this.type,
    this.category,
  });

  final String accountId;
  final String code;
  final String name;
  final String type;
  final String? category;

  String get label => '$code · $name';
  bool get canReceiveExpense => type == 'expense';
}

class BankReconciliationPaymentMethodOption {
  const BankReconciliationPaymentMethodOption({
    required this.paymentMethodId,
    required this.code,
    required this.name,
    required this.accountId,
  });

  final String paymentMethodId;
  final String code;
  final String name;
  final String accountId;
}

class BankReconciliationWorkspaceOptions {
  BankReconciliationWorkspaceOptions({
    required List<BankReconciliationLedgerAccountOption> accounts,
    required List<BankReconciliationPaymentMethodOption> paymentMethods,
  })  : accounts = List.unmodifiable(accounts),
        paymentMethods = List.unmodifiable(paymentMethods);

  final List<BankReconciliationLedgerAccountOption> accounts;
  final List<BankReconciliationPaymentMethodOption> paymentMethods;

  List<BankReconciliationLedgerAccountOption> get expenseAccounts => accounts
      .where((account) => account.canReceiveExpense)
      .toList(growable: false);
}

class BankCivilDate implements Comparable<BankCivilDate> {
  const BankCivilDate(this.year, this.month, this.day)
      : assert(year > 0),
        assert(month >= 1 && month <= 12),
        assert(day >= 1 && day <= 31);

  final int year;
  final int month;
  final int day;

  factory BankCivilDate.fromDateTime(DateTime value) =>
      BankCivilDate(value.year, value.month, value.day);

  DateTime get utcDate => DateTime.utc(year, month, day);

  int daysUntil(BankCivilDate other) =>
      other.utcDate.difference(utcDate).inDays;

  BankCivilDate addDays(int days) =>
      BankCivilDate.fromDateTime(utcDate.add(Duration(days: days)));

  @override
  int compareTo(BankCivilDate other) => utcDate.compareTo(other.utcDate);

  @override
  bool operator ==(Object other) =>
      other is BankCivilDate &&
      year == other.year &&
      month == other.month &&
      day == other.day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}

class BankStatementMovement {
  BankStatementMovement({
    required this.sourceRowId,
    required this.ordinal,
    required this.bookingDate,
    this.operationDate,
    required this.description,
    required this.normalizedDescription,
    this.counterpartyObserved,
    this.documentNumber,
    required this.direction,
    required this.amountClp,
    this.balanceClp,
    List<String> warningCodes = const <String>[],
    required this.sourcePage,
    required this.sourceLineStart,
    required this.sourceLineEnd,
  })  : assert(sourceRowId != ''),
        assert(ordinal > 0),
        assert(amountClp == null || amountClp > 0),
        warningCodes = List.unmodifiable(warningCodes);

  final String sourceRowId;
  final int ordinal;
  final BankCivilDate? bookingDate;
  final BankCivilDate? operationDate;
  final String description;
  final String normalizedDescription;
  final String? counterpartyObserved;
  final String? documentNumber;
  final BankMovementDirection direction;
  final int? amountClp;
  final int? balanceClp;
  final List<String> warningCodes;
  final int sourcePage;
  final int sourceLineStart;
  final int sourceLineEnd;

  bool get isComplete =>
      bookingDate != null &&
      direction != BankMovementDirection.unknown &&
      amountClp != null &&
      description.trim().isNotEmpty &&
      warningCodes.isEmpty;
}

class BankReconciliationCandidate {
  BankReconciliationCandidate({
    required this.targetKind,
    required this.targetId,
    required this.direction,
    required this.amountClp,
    required this.occurredOn,
    required this.label,
    this.counterparty,
    this.reference,
    this.paymentMethodCode,
    this.provider = BankSettlementProvider.none,
    this.instrument = BankPaymentInstrument.unknown,
  })  : assert(targetId != ''),
        assert(amountClp > 0);

  final BankReconciliationTargetKind targetKind;
  final String targetId;
  final BankMovementDirection direction;
  final int amountClp;
  final BankCivilDate occurredOn;
  final String label;
  final String? counterparty;
  final String? reference;
  final String? paymentMethodCode;
  final BankSettlementProvider provider;
  final BankPaymentInstrument instrument;

  String get identity => '${targetKind.name}:$targetId';
}

class BankReconciliationAllocationDraft {
  const BankReconciliationAllocationDraft({
    required this.candidate,
    required this.bankAmountClp,
  }) : assert(bankAmountClp > 0);

  final BankReconciliationCandidate candidate;
  final int bankAmountClp;
}

class BankReconciliationProposal {
  BankReconciliationProposal({
    required this.sourceRowId,
    required this.matchKind,
    required this.confidence,
    required List<BankReconciliationAllocationDraft> allocations,
    required List<String> reasons,
    this.isSelectedByDefault = false,
    this.estimatedGrossClp,
    this.estimatedDifferenceClp,
    this.instrument = BankPaymentInstrument.unknown,
  })  : assert(sourceRowId != ''),
        assert(allocations.isNotEmpty),
        allocations = List.unmodifiable(allocations),
        reasons = List.unmodifiable(reasons);

  final String sourceRowId;
  final BankReconciliationMatchKind matchKind;
  final BankReconciliationConfidence confidence;
  final List<BankReconciliationAllocationDraft> allocations;
  final List<String> reasons;
  final bool isSelectedByDefault;
  final int? estimatedGrossClp;
  final int? estimatedDifferenceClp;
  final BankPaymentInstrument instrument;

  int get allocatedBankAmountClp => allocations.fold<int>(
        0,
        (sum, allocation) => sum + allocation.bankAmountClp,
      );
}

class BankReconciliationResolutionDraft {
  const BankReconciliationResolutionDraft({
    this.action = BankReconciliationActionKind.pending,
    this.accountId,
    this.paymentMethodId,
    this.description,
    this.counterparty,
    this.reference,
    this.reason,
  });

  final BankReconciliationActionKind action;
  final String? accountId;
  final String? paymentMethodId;
  final String? description;
  final String? counterparty;
  final String? reference;
  final String? reason;

  BankReconciliationResolutionDraft copyWith({
    BankReconciliationActionKind? action,
    String? accountId,
    bool clearAccount = false,
    String? paymentMethodId,
    bool clearPaymentMethod = false,
    String? description,
    bool clearDescription = false,
    String? counterparty,
    bool clearCounterparty = false,
    String? reference,
    bool clearReference = false,
    String? reason,
    bool clearReason = false,
  }) {
    return BankReconciliationResolutionDraft(
      action: action ?? this.action,
      accountId: clearAccount ? null : accountId ?? this.accountId,
      paymentMethodId:
          clearPaymentMethod ? null : paymentMethodId ?? this.paymentMethodId,
      description: clearDescription ? null : description ?? this.description,
      counterparty:
          clearCounterparty ? null : counterparty ?? this.counterparty,
      reference: clearReference ? null : reference ?? this.reference,
      reason: clearReason ? null : reason ?? this.reason,
    );
  }
}

class BankReconciliationRowDraft {
  BankReconciliationRowDraft({
    required this.movement,
    required List<BankReconciliationProposal> proposals,
    String? selectedProposalId,
    bool selectDefault = true,
    this.disposition = BankReconciliationDisposition.pending,
    BankReconciliationResolutionDraft? resolution,
  })  : proposals = List.unmodifiable(proposals),
        selectedProposalId = selectedProposalId ??
            (selectDefault
                ? proposals
                    .where((proposal) => proposal.isSelectedByDefault)
                    .map(proposalIdentity)
                    .firstOrNull
                : null),
        resolution = resolution ??
            BankReconciliationResolutionDraft(
              action: (selectedProposalId ??
                          (selectDefault
                              ? proposals
                                  .where((proposal) =>
                                      proposal.isSelectedByDefault)
                                  .map(proposalIdentity)
                                  .firstOrNull
                              : null)) !=
                      null
                  ? BankReconciliationActionKind.associateExisting
                  : BankReconciliationActionKind.pending,
            );

  final BankStatementMovement movement;
  final List<BankReconciliationProposal> proposals;
  final String? selectedProposalId;
  final BankReconciliationDisposition disposition;
  final BankReconciliationResolutionDraft? resolution;

  BankReconciliationResolutionDraft get effectiveResolution =>
      resolution ??
      BankReconciliationResolutionDraft(
        action: selectedProposal == null
            ? BankReconciliationActionKind.pending
            : BankReconciliationActionKind.associateExisting,
      );

  static String proposalIdentity(BankReconciliationProposal proposal) =>
      '${proposal.matchKind.name}:'
      '${proposal.allocations.map((item) => item.candidate.identity).join(',')}';

  BankReconciliationProposal? get selectedProposal {
    final selected = selectedProposalId;
    if (selected == null) return null;
    return proposals
        .where((proposal) => proposalIdentity(proposal) == selected)
        .firstOrNull;
  }

  BankReconciliationRowDraft copyWith({
    String? selectedProposalId,
    bool clearSelection = false,
    BankReconciliationDisposition? disposition,
    BankReconciliationResolutionDraft? resolution,
    List<BankReconciliationProposal>? proposals,
  }) {
    return BankReconciliationRowDraft(
      movement: movement,
      proposals: proposals ?? this.proposals,
      selectedProposalId:
          clearSelection ? null : selectedProposalId ?? this.selectedProposalId,
      selectDefault: false,
      disposition: disposition ?? this.disposition,
      resolution: resolution ?? effectiveResolution,
    );
  }

  bool get isResolved => switch (effectiveResolution.action) {
        BankReconciliationActionKind.associateExisting =>
          selectedProposal != null,
        BankReconciliationActionKind.createExpense =>
          (effectiveResolution.accountId?.trim().isNotEmpty ?? false) &&
              (effectiveResolution.paymentMethodId?.trim().isNotEmpty ??
                  false) &&
              (effectiveResolution.description?.trim().isNotEmpty ?? false),
        BankReconciliationActionKind.classifyAccount =>
          (effectiveResolution.accountId?.trim().isNotEmpty ?? false) &&
              (effectiveResolution.description?.trim().isNotEmpty ?? false),
        BankReconciliationActionKind.dismiss => reasonText.trim().isNotEmpty,
        BankReconciliationActionKind.pending => false,
      };

  String get reasonText => effectiveResolution.reason ?? '';
}

class BankReconciliationPreparedDraft {
  BankReconciliationPreparedDraft({
    required this.fileSha256,
    required this.filename,
    required this.sourceType,
    this.accountFingerprint,
    required this.parserName,
    required this.parserVersion,
    required List<BankReconciliationRowDraft> rows,
    List<BankReconciliationCandidate> candidateCatalog = const [],
    List<String> extractionWarnings = const <String>[],
  })  : rows = List.unmodifiable(rows),
        candidateCatalog = List.unmodifiable(candidateCatalog),
        extractionWarnings = List.unmodifiable(extractionWarnings);

  final String fileSha256;
  final String filename;
  final String sourceType;
  final String? accountFingerprint;
  final String parserName;
  final String parserVersion;
  final List<BankReconciliationRowDraft> rows;
  final List<BankReconciliationCandidate> candidateCatalog;
  final List<String> extractionWarnings;

  int get movementCount => rows.length;
  int get proposedCount => rows.where((row) => row.proposals.isNotEmpty).length;
  int get selectedCount =>
      rows.where((row) => row.selectedProposal != null).length;
  int get resolvedCount => rows.where((row) => row.isResolved).length;
  int get pendingCount => movementCount - resolvedCount;

  Map<String, BankReconciliationRowDraft> get rowsBySourceId =>
      UnmodifiableMapView(<String, BankReconciliationRowDraft>{
        for (final row in rows) row.movement.sourceRowId: row,
      });

  BankReconciliationPreparedDraft replaceRow(
    BankReconciliationRowDraft replacement,
  ) {
    return BankReconciliationPreparedDraft(
      fileSha256: fileSha256,
      filename: filename,
      sourceType: sourceType,
      accountFingerprint: accountFingerprint,
      parserName: parserName,
      parserVersion: parserVersion,
      rows: <BankReconciliationRowDraft>[
        for (final row in rows)
          if (row.movement.sourceRowId == replacement.movement.sourceRowId)
            replacement
          else
            row,
      ],
      candidateCatalog: candidateCatalog,
      extractionWarnings: extractionWarnings,
    );
  }
}

class BankStatementImportReceipt {
  BankStatementImportReceipt({
    required this.importId,
    required this.revision,
    required Map<String, String> rowIdsBySourceRowId,
    required this.replayed,
  }) : rowIdsBySourceRowId = Map.unmodifiable(rowIdsBySourceRowId);

  final String importId;
  final int revision;
  final Map<String, String> rowIdsBySourceRowId;
  final bool replayed;
}

class BankReconciliationApplyReceipt {
  const BankReconciliationApplyReceipt({
    required this.importId,
    required this.revision,
    required this.status,
    required this.allocationCount,
    required this.replayed,
    this.createdExpenseCount = 0,
    this.createdJournalCount = 0,
  });

  final String importId;
  final int revision;
  final String status;
  final int allocationCount;
  final bool replayed;
  final int createdExpenseCount;
  final int createdJournalCount;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
