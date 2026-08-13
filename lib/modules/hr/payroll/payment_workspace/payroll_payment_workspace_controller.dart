import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../models/payroll_statement_reconciliation.dart';
import 'payroll_payment_workspace_models.dart';

typedef PayrollPaymentTargetSaver = Future<void> Function(
  PayrollPaymentTargetSaveCommand command,
);

typedef PayrollPaymentBatchSaver = Future<void> Function(
  List<PayrollPaymentTargetSaveCommand> commands,
  String operationKey,
);

typedef PayrollPaymentWeekApprover
    = Future<List<PayrollPaymentWeekApprovalResult>> Function(
  List<PayrollPaymentWeekApprovalRequest> requests,
  String operationKey,
);

typedef PayrollPaymentOperationKeyFactory = String Function();

class PayrollPaymentWorkspaceValidationException implements Exception {
  PayrollPaymentWorkspaceValidationException(this.validation);

  final PayrollPaymentTargetValidation validation;

  @override
  String toString() => validation.issues.isEmpty
      ? 'El pago no está listo para guardar.'
      : validation.issues.first.message;
}

class PayrollPaymentWeeksApprovalRequiredException implements Exception {
  const PayrollPaymentWeeksApprovalRequiredException();

  @override
  String toString() =>
      'Aprueba las semanas pendientes antes de registrar los pagos.';
}

/// State owner shared by the single-person side sheet and the OCR batch host.
///
/// OCR can only seed payment legs. Every later edit, validation and save is
/// owned here, so the importer never becomes a second payment writer.
class PayrollPaymentWorkspaceController extends ChangeNotifier {
  PayrollPaymentWorkspaceController({
    required this.request,
    PayrollPaymentTargetSaver? onSaveTarget,
    PayrollPaymentBatchSaver? onSaveBatch,
    PayrollPaymentWeekApprover? onApproveWeeks,
    PayrollPaymentOperationKeyFactory? operationKeyFactory,
    this.additionalConceptsSupported = false,
  })  : _onSaveTarget = onSaveTarget,
        _onSaveBatch = onSaveBatch,
        _onApproveWeeks = onApproveWeeks,
        _operationKeyFactory = operationKeyFactory ?? _defaultOperationKey {
    for (final target in request.targets) {
      _states[target.targetId] = _TargetState(
        operationKey: _operationKeyFactory(),
        salaryLegs: _prefilledSalaryLegs(target),
      );
    }
    _selectedTargetId = request.groups.first.targets.first.targetId;
    _batchOperationKey = request.mode == PayrollPaymentWorkspaceMode.batch
        ? request.ocrSource?.operationKey.trim().isNotEmpty == true
            ? request.ocrSource!.operationKey.trim()
            : _operationKeyFactory()
        : '';
    _approvalOperationKey = request.mode == PayrollPaymentWorkspaceMode.batch
        ? _operationKeyFactory()
        : '';
  }

  final PayrollPaymentWorkspaceRequest request;
  final bool additionalConceptsSupported;
  final PayrollPaymentTargetSaver? _onSaveTarget;
  final PayrollPaymentBatchSaver? _onSaveBatch;
  final PayrollPaymentWeekApprover? _onApproveWeeks;
  final PayrollPaymentOperationKeyFactory _operationKeyFactory;
  final Map<String, _TargetState> _states = <String, _TargetState>{};
  final Map<String, PayrollPaymentTarget> _approvedTargets =
      <String, PayrollPaymentTarget>{};
  String? _selectedTargetId;
  late String _batchOperationKey;
  late String _approvalOperationKey;
  bool _isSavingBatch = false;
  bool _isApprovingWeeks = false;

  String get selectedTargetId => _selectedTargetId!;

  PayrollPaymentTarget get selectedTarget => targetById(selectedTargetId);

  PayrollPaymentTarget targetById(String targetId) {
    final target = _approvedTargets[targetId] ?? request.targetById(targetId);
    if (target == null) {
      throw ArgumentError.value(targetId, 'targetId', 'Unknown payment target');
    }
    return target;
  }

  void selectTarget(String targetId) {
    targetById(targetId);
    if (_selectedTargetId == targetId) return;
    _selectedTargetId = targetId;
    notifyListeners();
  }

  PayrollPaymentTargetDraft draftFor(String targetId) {
    final target = targetById(targetId);
    final state = _stateFor(targetId);
    return PayrollPaymentTargetDraft(
      target: target,
      salaryLegs: state.salaryLegs,
      additionalConcepts: state.additionalConcepts,
      operationKey: state.operationKey,
      isDirty: state.isDirty,
      isSaved: state.isSaved,
      additionalConceptsSupported: additionalConceptsSupported,
    );
  }

  bool isSaving(String targetId) =>
      _isSavingBatch || _stateFor(targetId).isSaving;

  bool isDirty(String targetId) => _stateFor(targetId).isDirty;

  /// Whether the operator changed this row after the workspace prepared it.
  ///
  /// Default methods and OCR-prefilled legs are part of the initial draft and
  /// do not count as manual adjustments.
  bool hasManualAdjustments(String targetId) =>
      _stateFor(targetId).hasManualAdjustments;

  bool isSaved(String targetId) => _stateFor(targetId).isSaved;

  bool isCommittedUnverified(String targetId) =>
      _stateFor(targetId).isCommittedUnverified;

  bool get isSavingBatch => _isSavingBatch;

  bool get isApprovingWeeks => _isApprovingWeeks;

  String get approvalOperationKey => _approvalOperationKey;

  int get unapprovedWeekCount => _unapprovedWeekRequests().length;

  bool get canSaveBatch =>
      request.mode == PayrollPaymentWorkspaceMode.batch &&
      unapprovedWeekCount == 0 &&
      request.targets.every(
        (target) => validationFor(target.targetId).isValid,
      );

  bool get isBatchSaved =>
      request.mode == PayrollPaymentWorkspaceMode.batch &&
      request.targets.every((target) => isSaved(target.targetId));

  bool get isBatchCommittedUnverified =>
      request.mode == PayrollPaymentWorkspaceMode.batch &&
      request.targets.any(
        (target) => isCommittedUnverified(target.targetId),
      );

  bool get hasDirtyTargets =>
      request.targets.any((target) => isDirty(target.targetId));

  String get batchOperationKey => _batchOperationKey;

  /// Applies the simple, common case directly from a batch row.
  ///
  /// Split payments, advances and concepts keep using the expanded canonical
  /// editor. This helper never collapses those richer drafts into one leg.
  void setSimplePaymentMethod(String targetId, String? methodId) {
    final target = targetById(targetId);
    final state = _stateFor(targetId);
    final paymentLegs = state.salaryLegs
        .where((leg) => leg.kind == PayrollPaymentLegKind.payment)
        .toList(growable: false);
    final hasAdvance = state.salaryLegs.any(
      (leg) => leg.kind == PayrollPaymentLegKind.advance,
    );
    if (hasAdvance || paymentLegs.length > 1) {
      throw StateError(
        'Este pago usa varias formas. Edítalo desde su detalle.',
      );
    }
    final normalized = methodId?.trim() ?? '';
    final method = normalized.isEmpty ? null : _methodOption(normalized);
    _mutate(targetId, (mutable) {
      if (method == null || !method.isActive) {
        mutable.salaryLegs.clear();
        return;
      }
      final current = paymentLegs.firstOrNull;
      final now = DateTime.now();
      final includedConcepts = state.additionalConcepts
          .where(
            (concept) =>
                concept.disposition ==
                PayrollAdditionalConceptDisposition.includedInPayrollTotal,
          )
          .fold<int>(0, (sum, concept) => sum + concept.amountClp);
      final availableForSalary = target.salaryBalanceClp - includedConcepts;
      final amount = current?.amountClp ??
          (availableForSalary > 0 ? availableForSalary : 0);
      final replacement = PayrollPaymentLeg.payment(
        legId: current?.legId ?? 'simple:$targetId',
        amountClp: amount,
        paymentMethodId: method.methodId,
        paymentAccountId: method.accountId,
        paymentDate: current?.paymentDate ??
            PayrollCivilDate(now.year, now.month, now.day),
        reference: current?.reference,
        notes: current?.notes,
        ocrEvidence: current?.ocrEvidence,
      );
      mutable.salaryLegs
        ..clear()
        ..add(replacement);
    });
  }

  /// Confirms every draft week explicitly selected by this batch.
  ///
  /// The operation is separate from payment: approval recognizes the salary
  /// obligations, while [saveBatch] is the later money movement. The server
  /// confirms all listed weeks atomically and returns the live CAS versions
  /// that the prepared payment drafts must use.
  Future<void> approveRemainingWeeks() async {
    if (request.mode != PayrollPaymentWorkspaceMode.batch) {
      throw StateError('Week approval is only available in batch mode.');
    }
    if (_isApprovingWeeks || _isSavingBatch) return;
    final requests = _unapprovedWeekRequests();
    if (requests.isEmpty) return;
    final approver = _onApproveWeeks;
    if (approver == null) {
      throw StateError('No batch week approver was configured.');
    }

    _isApprovingWeeks = true;
    notifyListeners();
    try {
      final results = await approver(requests, _approvalOperationKey);
      final expectedIds = requests.map((item) => item.voucherId).toSet();
      final byVoucherId = <String, PayrollPaymentWeekApprovalResult>{};
      for (final result in results) {
        if (!expectedIds.contains(result.voucherId) ||
            result.reconciliationVersion < 0 ||
            byVoucherId.putIfAbsent(result.voucherId, () => result) != result) {
          throw StateError(
            'El servidor confirmó semanas distintas a las preparadas.',
          );
        }
      }
      if (byVoucherId.length != expectedIds.length) {
        throw StateError('El servidor no confirmó todas las semanas.');
      }
      for (final original in request.targets) {
        final result = byVoucherId[original.voucherId];
        if (result == null) continue;
        final live = targetById(original.targetId);
        _approvedTargets[original.targetId] = live.copyWith(
          voucherStatus: 'confirmed',
          reconciliationVersion: result.reconciliationVersion,
        );
      }
    } finally {
      _isApprovingWeeks = false;
      notifyListeners();
    }
  }

  /// Amount from [evidence] that is still free across the whole workspace.
  ///
  /// The same bank movement may fund both salary and a separate reimbursement,
  /// or more than one salary target. Availability therefore cannot be computed
  /// from the selected worker alone. While editing a leg, that leg is excluded
  /// so its current allocation remains available to itself.
  int availableEvidenceAmount(
    String targetId,
    PayrollOcrStatementEvidence evidence, {
    String? excludingLegId,
  }) {
    targetById(targetId);
    var allocated = 0;
    for (final entry in _states.entries) {
      for (final leg in <PayrollPaymentLeg>[
        ...entry.value.salaryLegs,
        for (final concept in entry.value.additionalConcepts)
          ...concept.paymentLegs,
      ]) {
        if (entry.key == targetId &&
            excludingLegId != null &&
            leg.legId == excludingLegId) {
          continue;
        }
        if (leg.ocrEvidence?.allocationKey == evidence.allocationKey &&
            leg.amountClp > 0) {
          allocated += leg.amountClp;
        }
      }
    }
    final remaining = evidence.availableAmountClp - allocated;
    return remaining > 0 ? remaining : 0;
  }

  void replaceSalaryLegs(String targetId, List<PayrollPaymentLeg> legs) {
    _mutate(targetId, (state) {
      state.salaryLegs
        ..clear()
        ..addAll(legs);
    });
  }

  void addPaymentLeg(String targetId, PayrollPaymentLeg leg) {
    if (leg.kind != PayrollPaymentLegKind.payment) {
      throw ArgumentError('addPaymentLeg requires a payment leg.');
    }
    addSalaryLeg(targetId, leg);
  }

  void addSalaryLeg(String targetId, PayrollPaymentLeg leg) {
    _mutate(targetId, (state) => state.salaryLegs.add(leg));
  }

  void updatePaymentLeg(String targetId, PayrollPaymentLeg leg) {
    updateSalaryLeg(targetId, leg);
  }

  void updateSalaryLeg(String targetId, PayrollPaymentLeg leg) {
    _mutate(targetId, (state) {
      final index = state.salaryLegs.indexWhere(
        (current) => current.legId == leg.legId,
      );
      if (index < 0) {
        throw ArgumentError.value(leg.legId, 'leg.legId', 'Unknown salary leg');
      }
      state.salaryLegs[index] = leg;
    });
  }

  void removePaymentLeg(String targetId, String legId) {
    removeSalaryLeg(targetId, legId);
  }

  void removeSalaryLeg(String targetId, String legId) {
    _mutate(targetId, (state) {
      final before = state.salaryLegs.length;
      state.salaryLegs.removeWhere((leg) => leg.legId == legId);
      final removed = before - state.salaryLegs.length;
      if (removed == 0) {
        throw ArgumentError.value(legId, 'legId', 'Unknown salary leg');
      }
    });
  }

  void toggleAdvance(
    String targetId,
    String advanceId, {
    int? amountClp,
  }) {
    final target = targetById(targetId);
    final option = _advanceOption(target, advanceId);
    if (option == null) {
      throw ArgumentError.value(advanceId, 'advanceId', 'Unknown advance');
    }
    final legId = 'advance:$advanceId';
    _mutate(targetId, (state) {
      final before = state.salaryLegs.length;
      state.salaryLegs.removeWhere((leg) => leg.legId == legId);
      final removed = before - state.salaryLegs.length;
      if (removed > 0) return;
      state.salaryLegs.add(
        PayrollPaymentLeg.advance(
          legId: legId,
          advanceId: advanceId,
          amountClp: amountClp ?? option.availableAmountClp,
        ),
      );
    });
  }

  void setOcrCandidateSelected(
    String targetId,
    String candidateId,
    bool selected,
  ) {
    final target = targetById(targetId);
    final candidate = _candidate(target, candidateId);
    if (candidate == null) {
      throw ArgumentError.value(
          candidateId, 'candidateId', 'Unknown OCR candidate');
    }
    final legId = 'ocr:$candidateId';
    _mutate(targetId, (state) {
      state.salaryLegs.removeWhere((leg) => leg.legId == legId);
      if (!selected) return;
      final alreadyApplied = state.salaryLegs.fold<int>(
        0,
        (sum, leg) => sum + (leg.amountClp > 0 ? leg.amountClp : 0),
      );
      final includedConcepts = state.additionalConcepts
          .where(
            (concept) =>
                concept.disposition ==
                PayrollAdditionalConceptDisposition.includedInPayrollTotal,
          )
          .fold<int>(0, (sum, concept) => sum + concept.amountClp);
      final remaining =
          target.salaryBalanceClp - alreadyApplied - includedConcepts;
      if (remaining <= 0) return;
      final available = candidate.evidence.availableAmountClp;
      state.salaryLegs.add(
        _paymentLegFromCandidate(
          candidate,
          amountClp: available < remaining ? available : remaining,
        ),
      );
    });
  }

  void replaceAdditionalConcepts(
    String targetId,
    List<PayrollAdditionalConcept> concepts,
  ) {
    _mutate(targetId, (state) {
      state.additionalConcepts
        ..clear()
        ..addAll(concepts);
    });
  }

  void addConcept(String targetId, PayrollAdditionalConcept concept) {
    _mutate(targetId, (state) => state.additionalConcepts.add(concept));
  }

  void updateConcept(String targetId, PayrollAdditionalConcept concept) {
    _mutate(targetId, (state) {
      final index = state.additionalConcepts.indexWhere(
        (current) => current.conceptId == concept.conceptId,
      );
      if (index < 0) {
        throw ArgumentError.value(
          concept.conceptId,
          'concept.conceptId',
          'Unknown additional concept',
        );
      }
      state.additionalConcepts[index] = concept;
    });
  }

  void removeConcept(String targetId, String conceptId) {
    _mutate(targetId, (state) {
      final before = state.additionalConcepts.length;
      state.additionalConcepts.removeWhere(
        (concept) => concept.conceptId == conceptId,
      );
      final removed = before - state.additionalConcepts.length;
      if (removed == 0) {
        throw ArgumentError.value(conceptId, 'conceptId', 'Unknown concept');
      }
    });
  }

  void addConceptPaymentLeg(
    String targetId,
    String conceptId,
    PayrollPaymentLeg leg,
  ) {
    if (leg.kind != PayrollPaymentLegKind.payment) {
      throw ArgumentError('Additional concepts accept payment legs only.');
    }
    _mutateConcept(targetId, conceptId, (concept) {
      return concept.copyWith(paymentLegs: <PayrollPaymentLeg>[
        ...concept.paymentLegs,
        leg,
      ]);
    });
  }

  void updateConceptPaymentLeg(
    String targetId,
    String conceptId,
    PayrollPaymentLeg leg,
  ) {
    _mutateConcept(targetId, conceptId, (concept) {
      final legs = [...concept.paymentLegs];
      final index = legs.indexWhere((current) => current.legId == leg.legId);
      if (index < 0) {
        throw ArgumentError.value(
            leg.legId, 'leg.legId', 'Unknown concept leg');
      }
      legs[index] = leg;
      return concept.copyWith(paymentLegs: legs);
    });
  }

  void removeConceptPaymentLeg(
    String targetId,
    String conceptId,
    String legId,
  ) {
    _mutateConcept(targetId, conceptId, (concept) {
      final legs = [...concept.paymentLegs];
      final before = legs.length;
      legs.removeWhere((leg) => leg.legId == legId);
      final removed = before - legs.length;
      if (removed == 0) {
        throw ArgumentError.value(legId, 'legId', 'Unknown concept leg');
      }
      return concept.copyWith(paymentLegs: legs);
    });
  }

  PayrollPaymentTargetValidation validationFor(String targetId) {
    final draft = draftFor(targetId);
    final issues = <PayrollPaymentValidationIssue>[];
    final allLegs = <PayrollPaymentLeg>[
      ...draft.salaryLegs,
      for (final concept in draft.additionalConcepts) ...concept.paymentLegs,
    ];

    if (allLegs.isEmpty) {
      issues.add(
        const PayrollPaymentValidationIssue(
          code: PayrollPaymentValidationCode.noSettlement,
          message: 'Agrega al menos una parte del pago.',
        ),
      );
    }

    final seenLegIds = <String>{};
    for (final leg in draft.salaryLegs) {
      if (!seenLegIds.add(leg.legId)) {
        issues.add(
          PayrollPaymentValidationIssue(
            code: PayrollPaymentValidationCode.duplicateLegId,
            message: 'Dos partes del pago tienen la misma identidad.',
            legId: leg.legId,
          ),
        );
      }
      _validateLeg(
        draft.target,
        leg,
        issues,
        allowPayrollReferenceFallback: true,
      );
    }
    for (final concept in draft.additionalConcepts) {
      for (final leg in concept.paymentLegs) {
        if (!seenLegIds.add(leg.legId)) {
          issues.add(
            PayrollPaymentValidationIssue(
              code: PayrollPaymentValidationCode.duplicateLegId,
              message: 'Dos partes del pago tienen la misma identidad.',
              legId: leg.legId,
            ),
          );
        }
        _validateLeg(draft.target, leg, issues);
      }
    }

    if (draft.payrollCoverageClp > draft.target.salaryBalanceClp) {
      issues.add(
        const PayrollPaymentValidationIssue(
          code: PayrollPaymentValidationCode.salaryBalanceExceeded,
          message: 'El sueldo y los conceptos incluidos superan el saldo '
              'pendiente de la nómina.',
        ),
      );
    }

    final conceptIds = <String>{};
    for (final concept in draft.additionalConcepts) {
      if (!conceptIds.add(concept.conceptId)) {
        issues.add(
          PayrollPaymentValidationIssue(
            code: PayrollPaymentValidationCode.duplicateLegId,
            message: 'Dos conceptos adicionales tienen la misma identidad.',
            conceptId: concept.conceptId,
          ),
        );
      }
      if (concept.amountClp <= 0) {
        issues.add(
          PayrollPaymentValidationIssue(
            code: PayrollPaymentValidationCode.conceptAmountNotPositive,
            message: 'El monto del concepto debe ser mayor a cero.',
            conceptId: concept.conceptId,
          ),
        );
      }
      if (concept.description.trim().isEmpty) {
        issues.add(
          PayrollPaymentValidationIssue(
            code: PayrollPaymentValidationCode.conceptDescriptionMissing,
            message: 'Describe el concepto adicional.',
            conceptId: concept.conceptId,
          ),
        );
      }
      if (concept.expenseAccountId.trim().isEmpty) {
        issues.add(
          PayrollPaymentValidationIssue(
            code: PayrollPaymentValidationCode.conceptAccountMissing,
            message: 'El concepto adicional necesita su cuenta contable.',
            conceptId: concept.conceptId,
          ),
        );
      }
      final funded = concept.paymentLegs.fold<int>(
        0,
        (sum, leg) => sum + leg.amountClp,
      );
      if (funded != concept.amountClp) {
        issues.add(
          PayrollPaymentValidationIssue(
            code: PayrollPaymentValidationCode.conceptFundingMismatch,
            message: 'Las partes del pago no cubren exactamente el concepto.',
            conceptId: concept.conceptId,
          ),
        );
      }
    }

    if (draft.hasUnsupportedConcepts) {
      issues.add(
        const PayrollPaymentValidationIssue(
          code: PayrollPaymentValidationCode.unsupportedAdditionalConcepts,
          message: 'Los conceptos están listos, pero el escritor contable aún '
              'no está disponible.',
        ),
      );
    }

    final exceededEvidence = _exceededEvidenceKeys();
    final evidenceAccountIds = _evidenceAccountIds();
    if (evidenceAccountIds.length > 1) {
      issues.add(
        const PayrollPaymentValidationIssue(
          code: PayrollPaymentValidationCode.statementEvidenceAccountMismatch,
          message: 'Todos los movimientos de esta cartola deben usar la misma '
              'cuenta bancaria.',
        ),
      );
    }
    for (final leg in allLegs) {
      final evidence = leg.ocrEvidence;
      if (evidence == null ||
          !exceededEvidence.contains(evidence.allocationKey)) {
        continue;
      }
      issues.add(
        PayrollPaymentValidationIssue(
          code: PayrollPaymentValidationCode.evidenceAmountExceeded,
          message: 'La cartola está asignada por más dinero del que muestra.',
          legId: leg.legId,
          evidenceKey: evidence.allocationKey,
        ),
      );
    }

    return PayrollPaymentTargetValidation(
      targetId: targetId,
      salaryAppliedClp: draft.salaryAppliedClp,
      includedConceptsTotalClp: draft.includedConceptsTotalClp,
      payrollCoverageClp: draft.payrollCoverageClp,
      payrollRemainingClp: draft.payrollRemainingClp,
      remainingClp: draft.remainingClp,
      paymentTotalClp: draft.paymentTotalClp,
      advancesTotalClp: draft.advancesTotalClp,
      additionalConceptsTotalClp: draft.additionalConceptsTotalClp,
      additionalConceptsFundedClp: draft.additionalConceptsFundedClp,
      additionalConceptsAdditiveTotalClp:
          draft.additionalConceptsAdditiveTotalClp,
      totalObligationClp: draft.totalObligationClp,
      appliedTotalClp: draft.appliedTotalClp,
      issues: issues,
    );
  }

  List<Map<String, dynamic>> serializeSalarySplits(String targetId) {
    final draft = draftFor(targetId);
    return List<Map<String, dynamic>>.unmodifiable(
      draft.salaryLegs.map(_serializeSalaryLeg),
    );
  }

  Map<String, List<Map<String, dynamic>>> serializeSalarySplitsByLine(
    String targetId,
  ) {
    final target = targetById(targetId);
    return <String, List<Map<String, dynamic>>>{
      target.voucherLineId: serializeSalarySplits(targetId),
    };
  }

  Future<void> saveTarget(String targetId) async {
    final state = _stateFor(targetId);
    if (state.isSaved) {
      throw StateError(
        'Este pago ya fue registrado. Reabre Nóminas para iniciar otro pago.',
      );
    }
    if (state.isSaving) return;
    final validation = validationFor(targetId);
    if (!validation.isValid) {
      throw PayrollPaymentWorkspaceValidationException(validation);
    }
    final saver = _onSaveTarget;
    if (saver == null) {
      throw StateError('No payment target saver was configured.');
    }

    state.isSaving = true;
    notifyListeners();
    final command = _commandFor(targetId);
    try {
      await saver(command);
      state
        ..isDirty = false
        ..isSaved = true
        ..isCommittedUnverified = false;
    } on PayrollPaymentCommittedUnverifiedException {
      // The writer returned before receipt validation failed. Fence this
      // operation exactly like a success: offering a retry would lie about
      // the server result and risks duplicate operator intent.
      state
        ..isDirty = false
        ..isSaved = true
        ..isCommittedUnverified = true;
      rethrow;
    } on PayrollPaymentWorkspaceSaveException catch (error) {
      state
        ..isDirty = true
        ..isSaved = false
        ..isCommittedUnverified = false;
      if (error.retryPolicy == PayrollPaymentSaveRetryPolicy.newOperation) {
        state.operationKey = _operationKeyFactory();
      }
      rethrow;
    } catch (_) {
      // Unknown transport failures are ambiguous. Keep the same operation key
      // so a retry can recover the idempotent receipt instead of duplicating.
      state
        ..isDirty = true
        ..isSaved = false
        ..isCommittedUnverified = false;
      rethrow;
    } finally {
      state.isSaving = false;
      notifyListeners();
    }
  }

  /// Registers every worker in a batch as one atomic financial operation.
  ///
  /// Rows remain independently editable, but OCR batch completion has one
  /// acknowledgement and one idempotency key. This avoids turning the final
  /// import step into a sequence of unrelated individual payments.
  Future<void> saveBatch() async {
    if (request.mode != PayrollPaymentWorkspaceMode.batch) {
      throw StateError('Batch save is only available in batch mode.');
    }
    if (isBatchSaved) {
      throw StateError(
        'Estos pagos ya fueron registrados. Vuelve a Nóminas para iniciar '
        'otra operación.',
      );
    }
    if (_isSavingBatch) return;
    if (unapprovedWeekCount > 0) {
      throw const PayrollPaymentWeeksApprovalRequiredException();
    }

    final invalid = request.targets
        .map((target) => validationFor(target.targetId))
        .where((validation) => !validation.isValid)
        .toList(growable: false);
    if (invalid.isNotEmpty) {
      throw PayrollPaymentWorkspaceValidationException(invalid.first);
    }
    final saver = _onSaveBatch;
    if (saver == null) {
      throw StateError('No batch payment saver was configured.');
    }

    final commands = request.targets
        .map((target) => _commandFor(target.targetId))
        .toList(growable: false);
    _isSavingBatch = true;
    notifyListeners();
    try {
      await saver(commands, _batchOperationKey);
      for (final state in _states.values) {
        state
          ..isDirty = false
          ..isSaved = true
          ..isCommittedUnverified = false;
      }
    } on PayrollPaymentCommittedUnverifiedException {
      for (final state in _states.values) {
        state
          ..isDirty = false
          ..isSaved = true
          ..isCommittedUnverified = true;
      }
      rethrow;
    } on PayrollPaymentWorkspaceSaveException catch (error) {
      for (final state in _states.values) {
        state
          ..isDirty = true
          ..isSaved = false
          ..isCommittedUnverified = false;
      }
      if (error.retryPolicy == PayrollPaymentSaveRetryPolicy.newOperation) {
        _batchOperationKey = _operationKeyFactory();
      }
      rethrow;
    } catch (_) {
      // Unknown transport failures are acknowledgement-ambiguous. Reuse the
      // exact operation key so retrying cannot duplicate the batch.
      for (final state in _states.values) {
        state
          ..isDirty = true
          ..isSaved = false
          ..isCommittedUnverified = false;
      }
      rethrow;
    } finally {
      _isSavingBatch = false;
      notifyListeners();
    }
  }

  PayrollPaymentTargetSaveCommand _commandFor(String targetId) {
    final draft = draftFor(targetId);
    return PayrollPaymentTargetSaveCommand(
      target: draft.target,
      operationKey: draft.operationKey,
      salaryLegs: draft.salaryLegs,
      salarySplits: serializeSalarySplits(targetId),
      additionalConcepts: draft.additionalConcepts,
    );
  }

  void _validateLeg(
    PayrollPaymentTarget target,
    PayrollPaymentLeg leg,
    List<PayrollPaymentValidationIssue> issues, {
    bool allowPayrollReferenceFallback = false,
  }) {
    if (leg.amountClp <= 0) {
      issues.add(
        PayrollPaymentValidationIssue(
          code: PayrollPaymentValidationCode.amountNotPositive,
          message: 'Cada parte del pago debe ser mayor a cero.',
          legId: leg.legId,
        ),
      );
    }
    if (leg.kind == PayrollPaymentLegKind.payment) {
      final methodId = leg.paymentMethodId?.trim() ?? '';
      final accountId = leg.paymentAccountId?.trim() ?? '';
      if (methodId.isEmpty) {
        issues.add(
          PayrollPaymentValidationIssue(
            code: PayrollPaymentValidationCode.missingPaymentMethod,
            message: 'Elige el método de esta parte del pago.',
            legId: leg.legId,
          ),
        );
      }
      if (accountId.isEmpty) {
        issues.add(
          PayrollPaymentValidationIssue(
            code: PayrollPaymentValidationCode.missingPaymentAccount,
            message: 'Elige la cuenta de esta parte del pago.',
            legId: leg.legId,
          ),
        );
      }
      if (leg.paymentDate == null) {
        issues.add(
          PayrollPaymentValidationIssue(
            code: PayrollPaymentValidationCode.missingPaymentDate,
            message: 'Elige la fecha de esta parte del pago.',
            legId: leg.legId,
          ),
        );
      }
      final method = _methodOption(methodId);
      if (methodId.isNotEmpty && request.paymentMethods.isNotEmpty) {
        if (method == null || !method.isActive) {
          issues.add(
            PayrollPaymentValidationIssue(
              code: PayrollPaymentValidationCode.paymentMethodUnavailable,
              message: 'El método de pago ya no está disponible.',
              legId: leg.legId,
            ),
          );
        } else {
          if (method.accountId.isNotEmpty && method.accountId != accountId) {
            issues.add(
              PayrollPaymentValidationIssue(
                code: PayrollPaymentValidationCode.paymentAccountMismatch,
                message: 'La cuenta no corresponde al método elegido.',
                legId: leg.legId,
              ),
            );
          }
          if (leg.ocrEvidence != null &&
              method.code.trim().toLowerCase() != 'transfer') {
            issues.add(
              PayrollPaymentValidationIssue(
                code: PayrollPaymentValidationCode
                    .statementEvidenceRequiresTransfer,
                message: 'Una fila de cartola debe usar un método de '
                    'transferencia bancaria.',
                legId: leg.legId,
              ),
            );
          }
          if (!allowPayrollReferenceFallback &&
              method.requiresReference &&
              (leg.reference?.trim().isEmpty ?? true)) {
            issues.add(
              PayrollPaymentValidationIssue(
                code: PayrollPaymentValidationCode.paymentReferenceRequired,
                message: 'Este método exige una referencia.',
                legId: leg.legId,
              ),
            );
          }
        }
      }
      return;
    }

    final advanceId = leg.advanceId?.trim() ?? '';
    if (advanceId.isEmpty) {
      issues.add(
        PayrollPaymentValidationIssue(
          code: PayrollPaymentValidationCode.missingAdvance,
          message: 'La parte de anticipo no identifica su anticipo.',
          legId: leg.legId,
        ),
      );
      return;
    }
    final advance = _advanceOption(target, advanceId);
    if (advance == null || !advance.isAvailable) {
      issues.add(
        PayrollPaymentValidationIssue(
          code: PayrollPaymentValidationCode.advanceUnavailable,
          message: 'El anticipo ya no está disponible.',
          legId: leg.legId,
        ),
      );
    } else if (leg.amountClp > advance.availableAmountClp) {
      issues.add(
        PayrollPaymentValidationIssue(
          code: PayrollPaymentValidationCode.advanceAmountExceeded,
          message: 'Lo aplicado supera el saldo del anticipo.',
          legId: leg.legId,
        ),
      );
    }
  }

  Set<String> _exceededEvidenceKeys() {
    final totals = <String, int>{};
    final limits = <String, int>{};
    for (final state in _states.values) {
      for (final leg in <PayrollPaymentLeg>[
        ...state.salaryLegs,
        for (final concept in state.additionalConcepts) ...concept.paymentLegs,
      ]) {
        final evidence = leg.ocrEvidence;
        if (evidence == null) continue;
        final key = evidence.allocationKey;
        totals.update(key, (value) => value + leg.amountClp,
            ifAbsent: () => leg.amountClp);
        limits.update(
          key,
          (value) => value < evidence.availableAmountClp
              ? value
              : evidence.availableAmountClp,
          ifAbsent: () => evidence.availableAmountClp,
        );
      }
    }
    return <String>{
      for (final entry in totals.entries)
        if (entry.value > (limits[entry.key] ?? 0)) entry.key,
    };
  }

  Set<String> _evidenceAccountIds() => <String>{
        for (final state in _states.values)
          for (final leg in <PayrollPaymentLeg>[
            ...state.salaryLegs,
            for (final concept in state.additionalConcepts)
              ...concept.paymentLegs,
          ])
            if (leg.ocrEvidence != null &&
                leg.paymentAccountId?.trim().isNotEmpty == true)
              leg.paymentAccountId!.trim(),
      };

  Map<String, dynamic> _serializeSalaryLeg(PayrollPaymentLeg leg) {
    if (leg.amountClp <= 0) {
      throw StateError('Cannot serialize a non-positive salary split.');
    }
    if (leg.kind == PayrollPaymentLegKind.advance) {
      final advanceId = leg.advanceId?.trim() ?? '';
      if (advanceId.isEmpty) {
        throw StateError('Cannot serialize an advance without its ID.');
      }
      return <String, dynamic>{
        'kind': 'advance',
        'advance_id': advanceId,
        'amount': leg.amountClp,
      };
    }
    final methodId = leg.paymentMethodId?.trim() ?? '';
    final accountId = leg.paymentAccountId?.trim() ?? '';
    final paymentDate = leg.paymentDate;
    if (methodId.isEmpty || accountId.isEmpty || paymentDate == null) {
      throw StateError('Cannot serialize an incomplete payment split.');
    }
    return <String, dynamic>{
      'kind': 'payment',
      'payment_method_id': methodId,
      'payment_account_id': accountId,
      'amount': leg.amountClp,
      'payment_date': DateTime.utc(
        paymentDate.year,
        paymentDate.month,
        paymentDate.day,
        12,
      ).toIso8601String(),
      if (leg.reference?.trim().isNotEmpty == true)
        'reference': leg.reference!.trim(),
      if (leg.notes?.trim().isNotEmpty == true) 'notes': leg.notes!.trim(),
    };
  }

  void _mutate(String targetId, void Function(_TargetState state) change) {
    final state = _stateFor(targetId);
    if (state.isSaving || _isSavingBatch) {
      throw StateError('Cannot edit a target while it is being saved.');
    }
    if (state.isSaved) {
      throw StateError(
        'Este pago ya fue registrado. Reabre Nóminas para iniciar otro pago.',
      );
    }
    change(state);
    state
      ..isDirty = true
      ..hasManualAdjustments = true
      ..isSaved = false;
    notifyListeners();
  }

  void _mutateConcept(
    String targetId,
    String conceptId,
    PayrollAdditionalConcept Function(PayrollAdditionalConcept concept) change,
  ) {
    _mutate(targetId, (state) {
      final index = state.additionalConcepts.indexWhere(
        (concept) => concept.conceptId == conceptId,
      );
      if (index < 0) {
        throw ArgumentError.value(conceptId, 'conceptId', 'Unknown concept');
      }
      state.additionalConcepts[index] = change(state.additionalConcepts[index]);
    });
  }

  _TargetState _stateFor(String targetId) {
    targetById(targetId);
    return _states[targetId]!;
  }

  PayrollPaymentMethodOption? _methodOption(String methodId) {
    for (final method in request.paymentMethods) {
      if (method.methodId == methodId) return method;
    }
    return null;
  }

  List<PayrollPaymentWeekApprovalRequest> _unapprovedWeekRequests() {
    final requests = <PayrollPaymentWeekApprovalRequest>[];
    for (final group in request.groups) {
      final targets = group.targets
          .map((target) => targetById(target.targetId))
          .toList(growable: false);
      if (targets.every((target) => _isPayableStatus(target.voucherStatus))) {
        continue;
      }
      if (targets.any((target) => target.voucherStatus != 'draft')) {
        throw StateError('La semana ya no tiene un estado pagable.');
      }
      final versions =
          targets.map((target) => target.reconciliationVersion).toSet();
      if (versions.length != 1) {
        throw StateError('La semana aparece con versiones distintas.');
      }
      requests.add(
        PayrollPaymentWeekApprovalRequest(
          voucherId: group.voucherId,
          expectedReconciliationVersion: versions.single,
        ),
      );
    }
    return List<PayrollPaymentWeekApprovalRequest>.unmodifiable(requests);
  }

  static bool _isPayableStatus(String value) {
    final status = value.trim().toLowerCase();
    return status == 'confirmed' || status == 'partial';
  }

  PayrollAdvanceOption? _advanceOption(
    PayrollPaymentTarget target,
    String advanceId,
  ) {
    for (final advance in target.availableAdvances) {
      if (advance.advanceId == advanceId) return advance;
    }
    return null;
  }

  PayrollOcrPaymentCandidate? _candidate(
    PayrollPaymentTarget target,
    String candidateId,
  ) {
    for (final candidate in target.ocrCandidates) {
      if (candidate.candidateId == candidateId) return candidate;
    }
    return null;
  }

  List<PayrollPaymentLeg> _prefilledSalaryLegs(PayrollPaymentTarget target) {
    var remaining = target.salaryBalanceClp;
    final result = <PayrollPaymentLeg>[];
    for (final candidate in target.ocrCandidates) {
      if (!candidate.selectedForPrefill || remaining <= 0) continue;
      final available = candidate.evidence.availableAmountClp;
      final amount = available < remaining ? available : remaining;
      if (amount <= 0) continue;
      result.add(_paymentLegFromCandidate(candidate, amountClp: amount));
      remaining -= amount;
    }
    if (result.isNotEmpty ||
        request.mode != PayrollPaymentWorkspaceMode.batch ||
        target.salaryBalanceClp <= 0) {
      return result;
    }

    PayrollPaymentMethodOption? method;
    final preferredId = target.preferredPaymentMethodId?.trim() ?? '';
    if (preferredId.isNotEmpty) {
      final preferred = _methodOption(preferredId);
      if (preferred?.isActive == true) method = preferred;
    }
    method ??=
        request.paymentMethods.where((option) => option.isActive).firstOrNull;
    if (method == null) return result;

    final now = DateTime.now();
    result.add(
      PayrollPaymentLeg.payment(
        legId: 'simple:${target.targetId}',
        amountClp: target.salaryBalanceClp,
        paymentMethodId: method.methodId,
        paymentAccountId: method.accountId,
        paymentDate: PayrollCivilDate(now.year, now.month, now.day),
      ),
    );
    return result;
  }

  PayrollPaymentLeg _paymentLegFromCandidate(
    PayrollOcrPaymentCandidate candidate, {
    required int amountClp,
  }) {
    return PayrollPaymentLeg.payment(
      legId: 'ocr:${candidate.candidateId}',
      amountClp: amountClp,
      paymentMethodId: candidate.suggestedPaymentMethodId,
      paymentAccountId: candidate.suggestedPaymentAccountId ??
          candidate.evidence.suggestedErpAccountId ??
          request.ocrSource?.suggestedErpAccountId,
      paymentDate: candidate.evidence.bookingDate,
      reference: candidate.evidence.documentReference,
      notes: candidate.evidence.description,
      ocrEvidence: candidate.evidence,
    );
  }

  static String _defaultOperationKey() => const Uuid().v4();
}

class _TargetState {
  _TargetState({
    required this.operationKey,
    required List<PayrollPaymentLeg> salaryLegs,
  })  : salaryLegs = [...salaryLegs],
        isDirty = salaryLegs.isNotEmpty;

  String operationKey;
  final List<PayrollPaymentLeg> salaryLegs;
  final List<PayrollAdditionalConcept> additionalConcepts =
      <PayrollAdditionalConcept>[];
  bool isDirty;
  bool hasManualAdjustments = false;
  bool isSaved = false;
  bool isCommittedUnverified = false;
  bool isSaving = false;
}
