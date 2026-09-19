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

  /// Pay a salary Nómina owes with this transfer, then associate the row.
  payPayroll,
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
    this.fileRowId,
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

  /// Row id inside its own file when [sourceRowId] was made unique across
  /// several statements. The persisted import always keeps the file's id, so
  /// importing the same file again never duplicates its rows.
  final String? fileRowId;

  String get persistedRowId => fileRowId ?? sourceRowId;

  BankStatementMovement withSourceRowId(String value) => BankStatementMovement(
        sourceRowId: value,
        ordinal: ordinal,
        bookingDate: bookingDate,
        operationDate: operationDate,
        description: description,
        normalizedDescription: normalizedDescription,
        counterpartyObserved: counterpartyObserved,
        documentNumber: documentNumber,
        direction: direction,
        amountClp: amountClp,
        balanceClp: balanceClp,
        warningCodes: warningCodes,
        sourcePage: sourcePage,
        sourceLineStart: sourceLineStart,
        sourceLineEnd: sourceLineEnd,
        fileRowId: persistedRowId,
      );

  bool get isComplete =>
      bookingDate != null &&
      direction != BankMovementDirection.unknown &&
      amountClp != null &&
      description.trim().isNotEmpty &&
      warningCodes.isEmpty;
}

/// Who an ERP operation belongs to, as far as a bank line can tell.
enum BankCounterpartyKind { unknown, customer, supplier, employee, payee }

/// A bank row another module already tied to this ERP operation.
///
/// Nómina reconciles salary transfers against the same statement. Its
/// allocation remembers the observed row (date, amount, beneficiary), which is
/// stronger evidence than any similarity between amounts or dates.
class BankObservedRowEvidence {
  const BankObservedRowEvidence({
    required this.date,
    required this.amountClp,
    this.beneficiary,
  });

  final BankCivilDate date;
  final int amountClp;
  final String? beneficiary;
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
    this.occurredAt,
    this.counterpartyKind = BankCounterpartyKind.unknown,
    this.counterpartyId,
    List<String> counterpartyNames = const <String>[],
    this.documentNumber,
    List<BankObservedRowEvidence> bankEvidence =
        const <BankObservedRowEvidence>[],
  })  : assert(targetId != ''),
        assert(amountClp > 0),
        counterpartyNames = List.unmodifiable(counterpartyNames),
        bankEvidence = List.unmodifiable(bankEvidence);

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

  /// Operation timestamp, when the source keeps one. Card sales settle in the
  /// order they were taken, so the time orders two sales of the same day.
  final DateTime? occurredAt;
  final BankCounterpartyKind counterpartyKind;
  final String? counterpartyId;

  /// Every name a bank line may show for this counterparty: customer name,
  /// supplier legal/trade names and aliases, employee and payroll aliases.
  final List<String> counterpartyNames;
  final String? documentNumber;
  final List<BankObservedRowEvidence> bankEvidence;

  String get identity => '${targetKind.name}:$targetId';

  /// Names to compare with a bank line, falling back to the display name.
  List<String> get identityNames => counterpartyNames.isNotEmpty
      ? counterpartyNames
      : <String>[if (counterparty != null) counterparty!];

  /// Card sale settled by an acquirer deposit, never by a direct transfer.
  bool get isAcquirerSale =>
      targetKind == BankReconciliationTargetKind.salesPayment &&
      provider == BankSettlementProvider.transbank;
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

  /// What the chosen ERP operations add up to.
  int get targetTotalClp => allocations.fold<int>(
        0,
        (sum, allocation) => sum + allocation.candidate.amountClp,
      );

  /// A difference up to this is rounding or a bank fee, as for a direct
  /// match; beyond it the chosen operations do not explain the movement.
  static const manualToleranceClp = 1000;

  /// The operations the operator chose for one movement: one transfer can
  /// pay several (two salaries a relative paid and was repaid in one
  /// transfer). Each takes its own amount and the last takes what is left,
  /// so the allocations add up to the movement. Null when the operations
  /// exceed the movement.
  static BankReconciliationProposal? manual({
    required String sourceRowId,
    required int movementAmountClp,
    required List<BankReconciliationCandidate> candidates,
  }) {
    if (candidates.isEmpty) return null;
    var remaining = movementAmountClp;
    final allocations = <BankReconciliationAllocationDraft>[];
    for (var index = 0; index < candidates.length; index++) {
      final candidate = candidates[index];
      final last = index == candidates.length - 1;
      final amount = last ? remaining : candidate.amountClp;
      if (amount <= 0 || (!last && amount >= remaining)) return null;
      allocations.add(BankReconciliationAllocationDraft(
        candidate: candidate,
        bankAmountClp: amount,
      ));
      remaining -= amount;
    }
    return BankReconciliationProposal(
      sourceRowId: sourceRowId,
      matchKind: BankReconciliationMatchKind.manual,
      confidence: BankReconciliationConfidence.medium,
      allocations: allocations,
      reasons: <String>[
        candidates.length == 1
            ? 'Operación elegida manualmente'
            : '${candidates.length} operaciones elegidas manualmente',
      ],
    );
  }
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
    this.payroll,
  });

  final BankReconciliationActionKind action;
  final String? accountId;
  final String? paymentMethodId;
  final String? description;
  final String? counterparty;
  final String? reference;
  final String? reason;

  /// The salary a [BankReconciliationActionKind.payPayroll] row pays.
  final BankPayrollPaymentDraft? payroll;

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
    BankPayrollPaymentDraft? payroll,
    bool clearPayroll = false,
  }) {
    return BankReconciliationResolutionDraft(
      action: action ?? this.action,
      payroll: clearPayroll ? null : payroll ?? this.payroll,
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
    this.suggestion,
    this.sourceFileSha256,
    this.settled,
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

  /// What the ERP proposes when no existing operation explains the movement:
  /// a prefilled expense or journal, a dismissal, or a task in another module.
  final BankReconciliationSuggestion? suggestion;

  /// File this movement was read from when several statements are reviewed
  /// together; null for a single statement.
  final String? sourceFileSha256;

  /// Set when a review already settled this movement, in this statement or
  /// in another one that overlaps it. It is shown, never decided again.
  final BankSettledMovement? settled;

  bool get isSettled => settled != null;

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
      suggestion: suggestion,
      sourceFileSha256: sourceFileSha256,
      settled: settled,
    );
  }

  bool get isResolved =>
      !isSettled &&
      switch (effectiveResolution.action) {
        BankReconciliationActionKind.associateExisting =>
          _explainsMovement(selectedProposal),
        BankReconciliationActionKind.createExpense =>
          (effectiveResolution.accountId?.trim().isNotEmpty ?? false) &&
              (effectiveResolution.paymentMethodId?.trim().isNotEmpty ??
                  false) &&
              (effectiveResolution.description?.trim().isNotEmpty ?? false),
        BankReconciliationActionKind.classifyAccount =>
          (effectiveResolution.accountId?.trim().isNotEmpty ?? false) &&
              (effectiveResolution.description?.trim().isNotEmpty ?? false),
        BankReconciliationActionKind.dismiss => reasonText.trim().isNotEmpty,
        BankReconciliationActionKind.payPayroll =>
          effectiveResolution.payroll != null,
        BankReconciliationActionKind.pending => false,
      };

  String get reasonText => effectiveResolution.reason ?? '';

  /// A manual choice counts once its operations add up to the movement; the
  /// matcher's own proposals already carry their checked difference.
  bool _explainsMovement(BankReconciliationProposal? proposal) {
    if (proposal == null) return false;
    if (proposal.matchKind != BankReconciliationMatchKind.manual) return true;
    final amount = movement.amountClp;
    return amount != null &&
        (proposal.targetTotalClp - amount).abs() <=
            BankReconciliationProposal.manualToleranceClp;
  }
}

/// A movement a review already settled.
class BankSettledMovement {
  const BankSettledMovement({
    required this.sameStatement,
    required this.summary,
    required this.disposition,
    this.excluded = false,
    this.decidedOn,
  });

  /// Settled in this very statement, in an earlier sitting. Otherwise it was
  /// settled in an overlapping statement and is recorded here as such.
  final bool sameStatement;

  /// What it was settled as: the operations it explains, or why it was
  /// excluded.
  final String summary;
  final BankReconciliationDisposition disposition;

  /// Excluded by the operator (a returned transfer, a fee checked apart),
  /// not explained by an operation.
  final bool excluded;
  final BankCivilDate? decidedOn;
}

/// One statement file inside a review. Each file is persisted as its own
/// import, so its evidence and idempotency stay tied to that exact file.
class BankStatementSource {
  const BankStatementSource({
    required this.fileSha256,
    required this.filename,
    required this.sourceType,
    this.accountFingerprint,
    this.firstDate,
    this.lastDate,
    this.movementCount = 0,
  });

  final String fileSha256;
  final String filename;
  final String sourceType;
  final String? accountFingerprint;
  final BankCivilDate? firstDate;
  final BankCivilDate? lastDate;
  final int movementCount;
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
    List<BankStatementSource>? sources,
    List<BankReconciliationInsight> insights =
        const <BankReconciliationInsight>[],
  })  : rows = List.unmodifiable(rows),
        candidateCatalog = List.unmodifiable(candidateCatalog),
        extractionWarnings = List.unmodifiable(extractionWarnings),
        insights = List.unmodifiable(insights),
        sources = List.unmodifiable(
          sources ??
              <BankStatementSource>[
                BankStatementSource(
                  fileSha256: fileSha256,
                  filename: filename,
                  sourceType: sourceType,
                  accountFingerprint: accountFingerprint,
                  movementCount: rows.length,
                ),
              ],
        );

  final String fileSha256;
  final String filename;
  final String sourceType;
  final String? accountFingerprint;
  final String parserName;
  final String parserVersion;
  final List<BankReconciliationRowDraft> rows;
  final List<BankReconciliationCandidate> candidateCatalog;
  final List<String> extractionWarnings;
  final List<BankStatementSource> sources;
  final List<BankReconciliationInsight> insights;

  int get movementCount => rows.length;
  int get proposedCount => rows.where((row) => row.proposals.isNotEmpty).length;
  int get selectedCount =>
      rows.where((row) => row.selectedProposal != null).length;
  int get resolvedCount => rows.where((row) => row.isResolved).length;

  /// Movements an earlier review settled; they are not decided again.
  int get settledCount => rows.where((row) => row.isSettled).length;
  int get openCount => movementCount - settledCount;
  int get pendingCount => openCount - resolvedCount;

  /// Rows whose suggestion can be accepted without another decision.
  List<BankReconciliationRowDraft> get acceptableSuggestionRows => rows
      .where((row) =>
          !row.isSettled &&
          !row.isResolved &&
          row.suggestion?.resolution != null &&
          row.suggestion!.confidence == BankReconciliationConfidence.high)
      .toList(growable: false);

  Map<String, BankReconciliationRowDraft> get rowsBySourceId =>
      UnmodifiableMapView(<String, BankReconciliationRowDraft>{
        for (final row in rows) row.movement.sourceRowId: row,
      });

  BankReconciliationPreparedDraft replaceRow(
    BankReconciliationRowDraft replacement,
  ) {
    return replaceRows(<BankReconciliationRowDraft>[replacement]);
  }

  BankReconciliationPreparedDraft replaceRows(
    List<BankReconciliationRowDraft> replacements,
  ) {
    final bySource = <String, BankReconciliationRowDraft>{
      for (final row in replacements) row.movement.sourceRowId: row,
    };
    return BankReconciliationPreparedDraft(
      fileSha256: fileSha256,
      filename: filename,
      sourceType: sourceType,
      accountFingerprint: accountFingerprint,
      parserName: parserName,
      parserVersion: parserVersion,
      rows: <BankReconciliationRowDraft>[
        for (final row in rows) bySource[row.movement.sourceRowId] ?? row,
      ],
      candidateCatalog: candidateCatalog,
      extractionWarnings: extractionWarnings,
      sources: sources,
      insights: insights,
    );
  }

  /// The part of this review that belongs to one statement file.
  BankReconciliationPreparedDraft forSource(BankStatementSource source) {
    if (sources.length == 1) return this;
    return BankReconciliationPreparedDraft(
      fileSha256: source.fileSha256,
      filename: source.filename,
      sourceType: source.sourceType,
      accountFingerprint: source.accountFingerprint,
      parserName: parserName,
      parserVersion: parserVersion,
      rows: rows
          .where((row) => row.sourceFileSha256 == source.fileSha256)
          .toList(growable: false),
      candidateCatalog: candidateCatalog,
      extractionWarnings: extractionWarnings,
      sources: <BankStatementSource>[source],
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
    this.payrollPaymentCount = 0,
  });

  final String importId;
  final int revision;
  final String status;
  final int allocationCount;
  final bool replayed;
  final int createdExpenseCount;
  final int createdJournalCount;

  /// Salaries paid in Nómina by this apply.
  final int payrollPaymentCount;
}

/// What the ERP proposes for a movement no existing operation explains.
enum BankSuggestionKind {
  /// A paid expense, prefilled from how this counterparty was booked before.
  createExpense,

  /// A journal against a counterpart account (bank fees, owner funds…).
  postJournal,

  /// Two movements that cancel each other, or a row that is not accounting.
  dismiss,

  /// A salary owed in Nómina: pay it there, not here.
  payroll,

  /// A supplier payment whose purchase lives in Compras.
  purchase,

  /// A customer payment whose sale lives in Ventas.
  sale,
}

class BankReconciliationSuggestion {
  BankReconciliationSuggestion({
    required this.kind,
    required this.confidence,
    required this.title,
    List<String> reasons = const <String>[],
    this.resolution,
    this.followUp,
    this.relatedSourceRowId,
  }) : reasons = List.unmodifiable(reasons);

  final BankSuggestionKind kind;
  final BankReconciliationConfidence confidence;

  /// Short, operator-facing name of the proposal ("Arriendo · Darinka L.").
  final String title;
  final List<String> reasons;

  /// Prefilled decision for kinds this workspace can apply by itself.
  final BankReconciliationResolutionDraft? resolution;

  /// What to do in another module when this workspace must not book it.
  final String? followUp;

  /// The other half of a pair of movements that cancel each other.
  final String? relatedSourceRowId;
}

enum BankInsightTone { info, warning }

/// A finding about the whole review, e.g. acquirer terms that do not match
/// what the bank actually paid.
class BankReconciliationInsight {
  const BankReconciliationInsight({
    required this.title,
    required this.body,
    this.tone = BankInsightTone.info,
  });

  final String title;
  final String body;
  final BankInsightTone tone;
}

/// A payroll line Nómina still owes; a bank transfer may already have paid it.
class BankPayrollExpectation {
  BankPayrollExpectation({
    required this.voucherId,
    required this.voucherNumber,
    required this.periodLabel,
    required this.periodEnd,
    required this.lineId,
    required this.employeeName,
    required List<String> names,
    required this.amountClp,
    this.paymentMethod,
    this.paymentMethodId,
    this.status = 'draft',
    this.reconciliationVersion,
    this.payableFrom,
    this.employeeId,
  }) : names = List.unmodifiable(names);

  final String voucherId;
  final String voucherNumber;
  final String periodLabel;
  final BankCivilDate periodEnd;
  final String lineId;
  final String employeeName;
  final List<String> names;

  /// What Nómina still owes on the line (its balance, not its total).
  final int amountClp;
  final String? paymentMethod;
  final String? paymentMethodId;

  /// `draft`, `confirmed` or `partial`.
  final String status;
  final int? reconciliationVersion;

  /// The first day Nómina takes money as this week's salary (its operational
  /// close, Saturday for a Sunday close). Earlier money is an advance. An
  /// older catalog without it falls back to the period end.
  final BankCivilDate? payableFrom;
  final String? employeeId;

  bool get isDraft => status == 'draft';

  bool acceptsSalaryOn(BankCivilDate date) =>
      date.compareTo(payableFrom ?? periodEnd) >= 0;
}

/// A salary to pay through Nómina from a bank row.
class BankPayrollPaymentDraft {
  const BankPayrollPaymentDraft({
    required this.voucherId,
    required this.voucherNumber,
    required this.periodLabel,
    required this.lineId,
    required this.employeeName,
    required this.expectedAmountClp,
    required this.amountClp,
    required this.paymentMethodId,
    required this.confirmDraft,
    this.advances = const <BankPayrollAdvanceUse>[],
  });

  final String voucherId;
  final String voucherNumber;
  final String periodLabel;
  final String lineId;
  final String employeeName;

  /// The line's balance when the review was built; the server refuses to
  /// pay a line that changed since.
  final int expectedAmountClp;

  /// What this transfer pays of it.
  final int amountClp;
  final String paymentMethodId;

  /// The week is a draft and paying it confirms it first.
  final bool confirmDraft;

  /// Advances Nómina discounts from this salary in the same payment.
  final List<BankPayrollAdvanceUse> advances;

  int get advancesClp =>
      advances.fold<int>(0, (sum, item) => sum + item.amountClp);

  /// What Nómina still owes after this payment.
  int get owedAfterClp => expectedAmountClp - amountClp - advancesClp;
}

enum BankOpenInvoiceKind { sale, purchase }

class BankOpenInvoice {
  BankOpenInvoice({
    required this.kind,
    required this.invoiceId,
    required this.number,
    required this.date,
    required this.totalClp,
    required this.balanceClp,
    required this.status,
    this.counterpartyId,
    List<String> names = const <String>[],
  }) : names = List.unmodifiable(names);

  final BankOpenInvoiceKind kind;
  final String invoiceId;
  final String number;
  final BankCivilDate date;
  final int totalClp;
  final int balanceClp;
  final String status;
  final String? counterpartyId;
  final List<String> names;
}

/// How a counterparty was booked before: account, payment method and text.
class BankUsualBooking {
  const BankUsualBooking({
    required this.accountId,
    this.paymentMethodCode,
    this.uses = 0,
    this.lastDescription,
  });

  final String accountId;
  final String? paymentMethodCode;
  final int uses;
  final String? lastDescription;
}

class BankCounterpartyProfile {
  BankCounterpartyProfile({
    required this.kind,
    required this.displayName,
    this.id,
    List<String> names = const <String>[],
    this.purchaseCount = 0,
    List<BankUsualBooking> usual = const <BankUsualBooking>[],
  })  : names = List.unmodifiable(names),
        usual = List.unmodifiable(usual);

  final BankCounterpartyKind kind;
  final String? id;
  final String displayName;
  final List<String> names;

  /// Purchase invoices in the last 18 months: a goods supplier, whose
  /// transfers belong to Compras rather than to a loose expense.
  final int purchaseCount;
  final List<BankUsualBooking> usual;
}

/// A decision taken on an earlier statement, reused for the same counterparty.
class BankPriorDecision {
  const BankPriorDecision({
    required this.action,
    required this.direction,
    required this.description,
    this.counterparty,
    this.amountClp,
    this.accountId,
    this.paymentMethodId,
    this.supplierName,
    this.text,
  });

  final BankReconciliationActionKind action;
  final BankMovementDirection direction;
  final String description;
  final String? counterparty;
  final int? amountClp;
  final String? accountId;
  final String? paymentMethodId;
  final String? supplierName;
  final String? text;
}

/// Everything the ERP knows that can explain a statement movement.
class BankReconciliationContext {
  BankReconciliationContext({
    List<BankReconciliationCandidate> candidates =
        const <BankReconciliationCandidate>[],
    List<BankPayrollExpectation> payrollLines =
        const <BankPayrollExpectation>[],
    List<BankOpenInvoice> openInvoices = const <BankOpenInvoice>[],
    List<BankCounterpartyProfile> parties = const <BankCounterpartyProfile>[],
    List<BankPriorDecision> decisions = const <BankPriorDecision>[],
    List<BankOpenAdvance> openAdvances = const <BankOpenAdvance>[],
    List<BankReconciledRow> reconciledRows = const <BankReconciledRow>[],
  })  : candidates = List.unmodifiable(candidates),
        reconciledRows = List.unmodifiable(reconciledRows),
        payrollLines = List.unmodifiable(payrollLines),
        openInvoices = List.unmodifiable(openInvoices),
        parties = List.unmodifiable(parties),
        decisions = List.unmodifiable(decisions),
        openAdvances = List.unmodifiable(openAdvances);

  final List<BankReconciliationCandidate> candidates;
  final List<BankPayrollExpectation> payrollLines;
  final List<BankOpenInvoice> openInvoices;
  final List<BankCounterpartyProfile> parties;
  final List<BankPriorDecision> decisions;

  /// Advances Nómina has not discounted from a salary yet.
  final List<BankOpenAdvance> openAdvances;

  /// Statement rows an earlier review of this account already settled.
  final List<BankReconciledRow> reconciledRows;
}

/// A statement row a review of the account already decided.
class BankReconciledRow {
  BankReconciledRow({
    required this.importId,
    required this.fileSha256,
    required this.sourceRowId,
    required this.bookingDate,
    required this.direction,
    required this.amountClp,
    this.balanceClp,
    required this.disposition,
    required this.action,
    this.settledElsewhere = false,
    this.note,
    this.decidedOn,
    List<String> labels = const <String>[],
  }) : labels = List.unmodifiable(labels);

  final String importId;
  final String fileSha256;
  final String sourceRowId;
  final BankCivilDate? bookingDate;
  final BankMovementDirection direction;
  final int? amountClp;
  final int? balanceClp;
  final BankReconciliationDisposition disposition;
  final String action;

  /// Dismissed because an overlapping statement had settled it.
  final bool settledElsewhere;
  final String? note;
  final BankCivilDate? decidedOn;

  /// The ERP operations the row explains.
  final List<String> labels;

  /// The same movement in two overlapping statements: its date, direction,
  /// amount and running balance, which the bank prints once per movement.
  static String? keyOf({
    required BankCivilDate? bookingDate,
    required BankMovementDirection direction,
    required int? amountClp,
    required int? balanceClp,
  }) {
    if (bookingDate == null || amountClp == null || balanceClp == null) {
      return null;
    }
    return '$bookingDate|${direction.name}|$amountClp|$balanceClp';
  }

  String? get key => keyOf(
        bookingDate: bookingDate,
        direction: direction,
        amountClp: amountClp,
        balanceClp: balanceClp,
      );
}

/// An advance Nómina paid a worker and still has to discount.
class BankOpenAdvance {
  const BankOpenAdvance({
    required this.advanceId,
    required this.employeeId,
    required this.availableClp,
    required this.paidOn,
    this.paymentMethodCode,
  });

  final String advanceId;
  final String employeeId;
  final int availableClp;
  final BankCivilDate paidOn;
  final String? paymentMethodCode;

  bool get isCash => paymentMethodCode == 'cash';
}

/// Part of an advance a salary payment discounts.
class BankPayrollAdvanceUse {
  const BankPayrollAdvanceUse({
    required this.advance,
    required this.amountClp,
  });

  final BankOpenAdvance advance;
  final int amountClp;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
