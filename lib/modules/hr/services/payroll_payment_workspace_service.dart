import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/services/database_service.dart';
import '../models/payroll_statement_reconciliation.dart';
import '../payroll/payment_workspace/payroll_payment_workspace_models.dart';
import 'payroll_voucher_service.dart';

typedef PayrollPaymentWorkspaceRpc = Future<dynamic> Function(
  String functionName,
  Map<String, dynamic> params,
);

/// Receipt for the single atomic command owned by the payment workspace.
class PayrollPaymentWorkspaceApplyReceipt {
  PayrollPaymentWorkspaceApplyReceipt({
    required this.workspaceId,
    required this.operationKey,
    required this.version,
    required this.replayed,
    required Map<String, dynamic> raw,
  }) : raw = Map<String, dynamic>.unmodifiable(raw);

  final String workspaceId;
  final String operationKey;
  final int version;
  final bool replayed;
  final Map<String, dynamic> raw;
}

/// Thin client for `apply_payroll_payment_workspace_v2`.
///
/// IDs generated here are UUIDv5 values derived from the immutable operation
/// key and logical editor IDs. Retrying the same acknowledgement-ambiguous
/// command therefore sends the exact same workspace, targets, concepts and
/// legs instead of creating a second financial movement.
class PayrollPaymentWorkspaceService {
  PayrollPaymentWorkspaceService({
    required DatabaseService database,
    PayrollPaymentWorkspaceRpc? sensitiveRpc,
  })  : _database = database,
        _sensitiveRpc = sensitiveRpc ??
            ((functionName, params) =>
                database.supabase.rpc(functionName, params: params));

  static const String _workspaceNamespace =
      '4d2e6c15-827c-4cb7-9455-647de655a0cb';
  static const Uuid _uuid = Uuid();
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _operationKeyPattern = RegExp(r'^[A-Za-z0-9:_-]{8,200}$');

  final DatabaseService _database;
  final PayrollPaymentWorkspaceRpc _sensitiveRpc;

  /// Canonical provider-facing entry point for one worker.
  Future<PayrollPaymentWorkspaceApplyReceipt> applyTarget({
    required PayrollPaymentTargetSaveCommand command,
    PayrollOcrStatementSource? ocrSource,
  }) {
    return applyTargets(
      commands: <PayrollPaymentTargetSaveCommand>[command],
      operationKey: command.operationKey,
      ocrSource: ocrSource,
    );
  }

  /// Batch-capable form of the same RPC contract.
  ///
  /// The current editor saves targets independently, while this entry point
  /// keeps the server's multi-target contract testable and available to a
  /// future explicit "save selected" action. [operationKey] owns the whole
  /// atomic batch; per-target command keys are deliberately not serialized.
  Future<PayrollPaymentWorkspaceApplyReceipt> applyTargets({
    required List<PayrollPaymentTargetSaveCommand> commands,
    required String operationKey,
    PayrollOcrStatementSource? ocrSource,
  }) async {
    final built = await _buildCommand(
      commands: commands,
      operationKey: operationKey,
      ocrSource: ocrSource,
    );

    final dynamic result;
    try {
      result = await _sensitiveRpc(
        'apply_payroll_payment_workspace_v2',
        built.params,
      );
    } on PostgrestException catch (error, stackTrace) {
      debugPrint(
        'Payroll workspace RPC rejected: code=${error.code} '
        'message=${error.message} details=${error.details} hint=${error.hint}\n'
        '$stackTrace',
      );
      if (_isAmbiguousTransportFailure(error)) rethrow;
      throw _deterministicFailure(error);
    }

    try {
      return _validateReceipt(result, built);
    } catch (error, stackTrace) {
      // Reaching this point means the RPC itself completed successfully. The
      // transaction may therefore already be committed even when a stale or
      // malformed response cannot satisfy the stricter client receipt shape.
      // Never collapse that state into a retryable "payment failed" error.
      debugPrint(
        'Payroll workspace committed but receipt validation failed: '
        'operationKey=${built.operationKey} error=$error\n$stackTrace',
      );
      throw PayrollPaymentCommittedUnverifiedException(
        operationKey: built.operationKey,
      );
    }
  }

  /// Explicitly confirms every draft week prepared by the batch workspace.
  ///
  /// This is deliberately a separate operation from payment. The operator
  /// first recognizes the salary obligations, then registers the prepared
  /// money batch. The RPC confirms the requested weeks atomically and returns
  /// the new reconciliation versions required by the later payment CAS.
  Future<List<PayrollPaymentWeekApprovalResult>> approveWeeks({
    required List<PayrollPaymentWeekApprovalRequest> requests,
    required String operationKey,
  }) async {
    final normalizedOperationKey = operationKey.trim();
    if (!_operationKeyPattern.hasMatch(normalizedOperationKey) ||
        requests.isEmpty ||
        requests.length > 100) {
      throw const PayrollVoucherPreflightException.rejected(
        'La selección de semanas por aprobar ya no es válida.',
      );
    }

    final expectedVersions = <String, int>{};
    for (final request in requests) {
      final voucherId = request.voucherId.trim();
      _requireUuid(voucherId, 'Una semana por aprobar ya no es válida.');
      if (request.expectedReconciliationVersion < 0 ||
          expectedVersions.containsKey(voucherId)) {
        throw const PayrollVoucherPreflightException.rejected(
          'Las semanas por aprobar tienen versiones inconsistentes.',
        );
      }
      expectedVersions[voucherId] = request.expectedReconciliationVersion;
    }
    final orderedIds = expectedVersions.keys.toList()..sort();

    final dynamic result;
    try {
      result = await _sensitiveRpc(
        'confirm_payroll_vouchers_v1',
        <String, dynamic>{
          'p_operation_key': normalizedOperationKey,
          'p_vouchers': <Map<String, dynamic>>[
            for (final voucherId in orderedIds)
              <String, dynamic>{
                'voucher_id': voucherId,
                'expected_reconciliation_version': expectedVersions[voucherId],
              },
          ],
        },
      );
    } on PostgrestException catch (error) {
      if (_isAmbiguousTransportFailure(error)) rethrow;
      throw _approvalFailure(error);
    }

    final receipt = _asJsonObject(result);
    final operation = receipt['operation']?.toString().trim() ?? '';
    final receivedKey = receipt['operation_key']?.toString().trim() ?? '';
    final payloadHash = receipt['payload_hash']?.toString().trim() ?? '';
    if (operation != 'confirm_drafts_batch' ||
        receivedKey != normalizedOperationKey ||
        receipt['replayed'] is! bool ||
        !_sha256Pattern.hasMatch(payloadHash)) {
      throw StateError(
        'El servidor no confirmó íntegramente las semanas preparadas.',
      );
    }

    final rows = _asJsonObjectList(receipt['confirmed_vouchers']);
    final results = <PayrollPaymentWeekApprovalResult>[];
    final receivedIds = <String>{};
    for (final row in rows) {
      final voucherId = row['voucher_id']?.toString().trim() ?? '';
      final version = _intValue(row['reconciliation_version']);
      final status = row['status']?.toString().trim().toLowerCase() ?? '';
      if (!expectedVersions.containsKey(voucherId) ||
          !receivedIds.add(voucherId) ||
          version == null ||
          version < expectedVersions[voucherId]! ||
          status != 'confirmed') {
        throw StateError(
          'El servidor confirmó una semana distinta a las preparadas.',
        );
      }
      results.add(
        PayrollPaymentWeekApprovalResult(
          voucherId: voucherId,
          reconciliationVersion: version,
        ),
      );
    }
    if (receivedIds.length != expectedVersions.length) {
      throw StateError('El servidor no confirmó todas las semanas preparadas.');
    }
    return List<PayrollPaymentWeekApprovalResult>.unmodifiable(results);
  }

  Future<_BuiltWorkspaceCommand> _buildCommand({
    required List<PayrollPaymentTargetSaveCommand> commands,
    required String operationKey,
    required PayrollOcrStatementSource? ocrSource,
  }) async {
    final normalizedOperationKey = operationKey.trim();
    if (!_operationKeyPattern.hasMatch(normalizedOperationKey)) {
      throw const PayrollVoucherPreflightException.rejected(
        'La operación de pago perdió su identidad. Cierra el panel y vuelve a '
        'abrirlo antes de intentar registrar dinero.',
      );
    }
    if (commands.isEmpty || commands.length > 200) {
      throw const PayrollVoucherPreflightException.rejected(
        'El panel no contiene una selección válida de trabajadores.',
      );
    }

    final workspaceId = _uuid.v5(
      _workspaceNamespace,
      'payroll-payment-workspace-v1:$normalizedOperationKey',
    );
    final methodIds = <String>{};
    final logicalTargetIds = <String>{};
    final expectedVersionByVoucher = <String, int>{};
    var conceptCount = 0;

    for (final command in commands) {
      final target = command.target;
      _requireUuid(target.voucherId, 'La semana de nómina ya no es válida.');
      _requireUuid(
        target.voucherLineId,
        'La obligación del trabajador ya no es válida.',
      );
      _requireUuid(
        target.employeeId,
        'El trabajador del pago ya no es válido.',
      );
      if (!logicalTargetIds.add(target.targetId.trim())) {
        throw const PayrollVoucherPreflightException.rejected(
          'El mismo trabajador aparece dos veces en la operación.',
        );
      }
      if (target.reconciliationVersion < 0) {
        throw const PayrollVoucherPreflightException.rejected(
          'La semana no tiene una versión verificable. Recarga Nóminas.',
        );
      }
      final previousVersion = expectedVersionByVoucher[target.voucherId];
      if (previousVersion != null &&
          previousVersion != target.reconciliationVersion) {
        throw const PayrollVoucherPreflightException.rejected(
          'La misma semana aparece con versiones distintas. Recarga Nóminas.',
        );
      }
      expectedVersionByVoucher[target.voucherId] = target.reconciliationVersion;

      if (command.salaryLegs.length > 100) {
        throw const PayrollVoucherPreflightException.rejected(
          'Un trabajador tiene demasiadas partes de pago.',
        );
      }
      conceptCount += command.additionalConcepts.length;
      if (command.salaryLegs.isEmpty && command.additionalConcepts.isEmpty) {
        throw const PayrollVoucherPreflightException.rejected(
          'Agrega al menos una parte del pago antes de guardar.',
        );
      }
      for (final leg in <PayrollPaymentLeg>[
        ...command.salaryLegs,
        for (final concept in command.additionalConcepts)
          ...concept.paymentLegs,
      ]) {
        if (leg.kind == PayrollPaymentLegKind.payment) {
          final methodId = leg.paymentMethodId?.trim() ?? '';
          final accountId = leg.paymentAccountId?.trim() ?? '';
          _requireUuid(methodId, 'Una parte no tiene método de pago válido.');
          _requireUuid(accountId, 'Una parte no tiene cuenta de pago válida.');
          methodIds.add(methodId);
        }
      }
    }
    if (conceptCount > 500 || commands.length + conceptCount > 500) {
      throw const PayrollVoucherPreflightException.rejected(
        'La operación contiene demasiados conceptos adicionales.',
      );
    }

    final methods = await _loadPaymentMethods(methodIds);
    final evidenceAccountIds = <String>{};
    final evidenceAllocatedBySourceRowId = <String, int>{};
    final expectedTargetIds = <String>{};
    final expectedSalaryLegIdsByTarget = <String, Set<String>>{};
    final expectedVoucherIdsByTarget = <String, String>{};
    final expectedConceptLegIds = <String, Set<String>>{};
    final expectedConceptDispositions = <String, String>{};
    final expectedConceptVoucherIds = <String, String?>{};
    final expectedConceptLineIds = <String, String?>{};
    final expectedConceptTargetIds = <String, String?>{};
    final expectedEvidenceLegIds = <String>{};
    final salaryTargets = <Map<String, dynamic>>[];
    final additionalConcepts = <Map<String, dynamic>>[];

    for (final command in commands) {
      final target = command.target;
      final targetId = _uuid.v5(
        workspaceId,
        'salary-target-v1:${target.targetId.trim()}',
      );
      final salaryLegs = <Map<String, dynamic>>[];
      final expectedSalaryLegIds = <String>{};
      for (final leg in command.salaryLegs) {
        final legId = _uuid.v5(
          workspaceId,
          'salary-leg-v1:$targetId:${leg.legId.trim()}',
        );
        salaryLegs.add(
          _serializeSalaryLeg(
            target: target,
            leg: leg,
            legId: legId,
            methods: methods,
            ocrSource: ocrSource,
            evidenceAccountIds: evidenceAccountIds,
            evidenceAllocatedBySourceRowId: evidenceAllocatedBySourceRowId,
            expectedEvidenceLegIds: expectedEvidenceLegIds,
          ),
        );
        if (!expectedSalaryLegIds.add(legId)) {
          throw const PayrollVoucherPreflightException.rejected(
            'Dos partes del sueldo tienen la misma identidad.',
          );
        }
      }
      final hasIncludedConcepts = command.additionalConcepts.any(
        (concept) =>
            concept.disposition ==
            PayrollAdditionalConceptDisposition.includedInPayrollTotal,
      );
      if (salaryLegs.isNotEmpty || hasIncludedConcepts) {
        expectedTargetIds.add(targetId);
        expectedVoucherIdsByTarget[targetId] = target.voucherId;
        expectedSalaryLegIdsByTarget[targetId] = expectedSalaryLegIds;
        salaryTargets.add(<String, dynamic>{
          'target_id': targetId,
          'voucher_id': target.voucherId,
          'expected_reconciliation_version': target.reconciliationVersion,
          'legs': salaryLegs,
        });
      }

      for (final concept in command.additionalConcepts) {
        final conceptId = _uuid.v5(
          workspaceId,
          'additional-concept-v1:$targetId:${concept.conceptId.trim()}',
        );
        _requireUuid(
          concept.expenseAccountId,
          'El concepto adicional no tiene una cuenta de gasto válida.',
        );
        if (concept.amountClp <= 0 || concept.description.trim().isEmpty) {
          throw const PayrollVoucherPreflightException.rejected(
            'Completa la descripción y el monto del concepto adicional.',
          );
        }
        if (concept.paymentLegs.isEmpty || concept.paymentLegs.length > 100) {
          throw const PayrollVoucherPreflightException.rejected(
            'El concepto adicional necesita entre una y cien partes de pago.',
          );
        }
        final funded = concept.paymentLegs.fold<int>(
          0,
          (sum, leg) => sum + leg.amountClp,
        );
        if (funded != concept.amountClp) {
          throw const PayrollVoucherPreflightException.rejected(
            'Las partes del pago no cubren exactamente el concepto adicional.',
          );
        }

        final conceptLegs = <Map<String, dynamic>>[];
        final expectedLegIds = <String>{};
        for (final leg in concept.paymentLegs) {
          if (leg.kind != PayrollPaymentLegKind.payment) {
            throw const PayrollVoucherPreflightException.rejected(
              'Un concepto adicional no puede usar un anticipo salarial.',
            );
          }
          final legId = _uuid.v5(
            workspaceId,
            'additional-concept-leg-v1:$conceptId:${leg.legId.trim()}',
          );
          conceptLegs.add(
            _serializePaymentLeg(
              leg: leg,
              legId: legId,
              methods: methods,
              allowPayrollReferenceFallback: false,
              ocrSource: ocrSource,
              evidenceAccountIds: evidenceAccountIds,
              evidenceAllocatedBySourceRowId: evidenceAllocatedBySourceRowId,
              expectedEvidenceLegIds: expectedEvidenceLegIds,
            ),
          );
          if (!expectedLegIds.add(legId)) {
            throw const PayrollVoucherPreflightException.rejected(
              'Dos partes del concepto tienen la misma identidad.',
            );
          }
        }
        if (expectedConceptLegIds.containsKey(conceptId)) {
          throw const PayrollVoucherPreflightException.rejected(
            'Dos conceptos adicionales tienen la misma identidad.',
          );
        }
        expectedConceptLegIds[conceptId] = expectedLegIds;
        expectedConceptDispositions[conceptId] = switch (concept.disposition) {
          PayrollAdditionalConceptDisposition.includedInPayrollTotal =>
            'included_in_payroll_total',
          PayrollAdditionalConceptDisposition.additional => 'additional',
        };
        expectedConceptVoucherIds[conceptId] = concept.disposition ==
                PayrollAdditionalConceptDisposition.includedInPayrollTotal
            ? target.voucherId
            : null;
        expectedConceptLineIds[conceptId] = concept.disposition ==
                PayrollAdditionalConceptDisposition.includedInPayrollTotal
            ? target.voucherLineId
            : null;
        expectedConceptTargetIds[conceptId] = concept.disposition ==
                PayrollAdditionalConceptDisposition.includedInPayrollTotal
            ? targetId
            : null;
        additionalConcepts.add(<String, dynamic>{
          'concept_id': conceptId,
          'beneficiary_employee_id': target.employeeId,
          'disposition': switch (concept.disposition) {
            PayrollAdditionalConceptDisposition.includedInPayrollTotal =>
              'included_in_payroll_total',
            PayrollAdditionalConceptDisposition.additional => 'additional',
          },
          if (concept.disposition ==
              PayrollAdditionalConceptDisposition.includedInPayrollTotal) ...{
            'target_id': targetId,
            'voucher_id': target.voucherId,
            'voucher_line_id': target.voucherLineId,
            'expected_reconciliation_version': target.reconciliationVersion,
          },
          'expense_account_id': concept.expenseAccountId.trim(),
          'amount': concept.amountClp,
          'description': _boundedRequiredText(
            concept.description,
            maxLength: 500,
            message:
                'La descripción del concepto adicional es demasiado larga.',
          ),
          if (concept.evidenceReference?.trim().isNotEmpty == true)
            'notes': _boundedRequiredText(
              concept.evidenceReference!,
              maxLength: 2000,
              message: 'El respaldo del concepto adicional es demasiado largo.',
            ),
          'payment_legs': conceptLegs,
        });
      }
    }

    Map<String, dynamic>? statement;
    List<Map<String, dynamic>>? rows;
    if (expectedEvidenceLegIds.isNotEmpty) {
      if (ocrSource == null) {
        throw const PayrollVoucherPreflightException.rejected(
          'El pago conserva evidencia bancaria, pero la cartola ya no está '
          'disponible. Vuelve a importarla.',
        );
      }
      if (evidenceAccountIds.length != 1) {
        throw const PayrollVoucherPreflightException.rejected(
          'Toda la evidencia de una cartola debe usar la misma cuenta bancaria.',
        );
      }
      final serializedStatement = _serializeStatement(
        ocrSource,
        accountId: evidenceAccountIds.single,
      );
      statement = serializedStatement.statement;
      rows = serializedStatement.rows;

      final availableBySourceRowId = <String, int>{
        for (final row in ocrSource.evidenceRows)
          row.sourceRowId: row.availableAmountClp,
      };
      for (final allocation in evidenceAllocatedBySourceRowId.entries) {
        final available = availableBySourceRowId[allocation.key];
        if (available == null || allocation.value > available) {
          throw const PayrollVoucherPreflightException.rejected(
            'La cartola está asignada por más dinero del que muestra.',
          );
        }
      }
    }

    final payload = <String, dynamic>{
      if (statement != null) 'statement': statement,
      if (rows != null) 'rows': rows,
      'salary_targets': salaryTargets,
      'additional_concepts': additionalConcepts,
    };
    final params = <String, dynamic>{
      'p_workspace_id': workspaceId,
      'p_operation_key': normalizedOperationKey,
      'p_expected_workspace_version': 0,
      'p_payload': payload,
    };
    return _BuiltWorkspaceCommand(
      params: params,
      workspaceId: workspaceId,
      operationKey: normalizedOperationKey,
      expectedTargetIds: expectedTargetIds,
      expectedSalaryLegIdsByTarget: expectedSalaryLegIdsByTarget,
      expectedVoucherIdsByTarget: expectedVoucherIdsByTarget,
      expectedConceptLegIds: expectedConceptLegIds,
      expectedConceptDispositions: expectedConceptDispositions,
      expectedConceptVoucherIds: expectedConceptVoucherIds,
      expectedConceptLineIds: expectedConceptLineIds,
      expectedConceptTargetIds: expectedConceptTargetIds,
      expectedEvidenceLegIds: expectedEvidenceLegIds,
      statementFileDigest: statement?['file_digest']?.toString(),
      statementAccountId: statement?['account_id']?.toString(),
    );
  }

  Future<Map<String, PayrollPaymentMethodOption>> _loadPaymentMethods(
    Set<String> methodIds,
  ) async {
    if (methodIds.isEmpty) return const <String, PayrollPaymentMethodOption>{};
    final List<Map<String, dynamic>> rows;
    try {
      rows = await _database.select(
        'payment_methods',
        selectColumns: 'id,name,code,account_id,is_active,requires_reference',
        where: 'id',
        whereIn: methodIds.toList(growable: false),
      );
    } catch (_) {
      throw const PayrollVoucherPreflightException.unavailable(
        'No pudimos validar los métodos de pago. Intenta nuevamente.',
      );
    }
    final result = <String, PayrollPaymentMethodOption>{};
    for (final row in rows) {
      final option = PayrollPaymentMethodOption.fromMap(row);
      if (option.methodId.isNotEmpty) result[option.methodId] = option;
    }
    for (final methodId in methodIds) {
      final method = result[methodId];
      if (method == null || !method.isActive || method.code.trim().isEmpty) {
        throw const PayrollVoucherPreflightException.rejected(
          'Un método de pago ya no está disponible. Recarga Nóminas.',
        );
      }
    }
    return Map<String, PayrollPaymentMethodOption>.unmodifiable(result);
  }

  Map<String, dynamic> _serializeSalaryLeg({
    required PayrollPaymentTarget target,
    required PayrollPaymentLeg leg,
    required String legId,
    required Map<String, PayrollPaymentMethodOption> methods,
    required PayrollOcrStatementSource? ocrSource,
    required Set<String> evidenceAccountIds,
    required Map<String, int> evidenceAllocatedBySourceRowId,
    required Set<String> expectedEvidenceLegIds,
  }) {
    if (leg.amountClp <= 0) {
      throw const PayrollVoucherPreflightException.rejected(
        'Cada parte del sueldo debe ser mayor a cero.',
      );
    }
    if (leg.kind == PayrollPaymentLegKind.advance) {
      final advanceId = leg.advanceId?.trim() ?? '';
      _requireUuid(advanceId, 'El anticipo seleccionado ya no es válido.');
      if (leg.ocrEvidence != null) {
        throw const PayrollVoucherPreflightException.rejected(
          'Un anticipo no puede usar una transferencia como evidencia.',
        );
      }
      return <String, dynamic>{
        'leg_id': legId,
        'voucher_line_id': target.voucherLineId,
        'kind': 'advance',
        'amount': leg.amountClp,
        'advance_id': advanceId,
      };
    }
    return <String, dynamic>{
      'voucher_line_id': target.voucherLineId,
      ..._serializePaymentLeg(
        leg: leg,
        legId: legId,
        methods: methods,
        allowPayrollReferenceFallback: true,
        ocrSource: ocrSource,
        evidenceAccountIds: evidenceAccountIds,
        evidenceAllocatedBySourceRowId: evidenceAllocatedBySourceRowId,
        expectedEvidenceLegIds: expectedEvidenceLegIds,
      ),
      'kind': 'payment',
    };
  }

  Map<String, dynamic> _serializePaymentLeg({
    required PayrollPaymentLeg leg,
    required String legId,
    required Map<String, PayrollPaymentMethodOption> methods,
    required bool allowPayrollReferenceFallback,
    required PayrollOcrStatementSource? ocrSource,
    required Set<String> evidenceAccountIds,
    required Map<String, int> evidenceAllocatedBySourceRowId,
    required Set<String> expectedEvidenceLegIds,
  }) {
    if (leg.kind != PayrollPaymentLegKind.payment || leg.amountClp <= 0) {
      throw const PayrollVoucherPreflightException.rejected(
        'Cada parte del pago debe ser un monto positivo.',
      );
    }
    final methodId = leg.paymentMethodId?.trim() ?? '';
    final accountId = leg.paymentAccountId?.trim() ?? '';
    final paymentDate = leg.paymentDate;
    final method = methods[methodId];
    if (method == null || paymentDate == null) {
      throw const PayrollVoucherPreflightException.rejected(
        'Completa el método, la cuenta y la fecha de cada parte del pago.',
      );
    }
    if (method.accountId.trim().isNotEmpty && method.accountId != accountId) {
      throw const PayrollVoucherPreflightException.rejected(
        'La cuenta elegida no corresponde al método de pago.',
      );
    }
    final fundingKind = switch (method.code.trim().toLowerCase()) {
      'transfer' => 'bank',
      'cash' => 'cash',
      _ => 'other',
    };
    if (!allowPayrollReferenceFallback &&
        method.requiresReference &&
        (leg.reference?.trim().isEmpty ?? true)) {
      throw const PayrollVoucherPreflightException.rejected(
        'El método de pago exige una referencia.',
      );
    }
    Map<String, dynamic>? evidence;
    final ocrEvidence = leg.ocrEvidence;
    if (ocrEvidence != null) {
      if (fundingKind != 'bank') {
        throw const PayrollVoucherPreflightException.rejected(
          'La evidencia de cartola sólo puede respaldar una transferencia. '
          'Cambia el método o quita esa evidencia.',
        );
      }
      if (ocrSource == null) {
        throw const PayrollVoucherPreflightException.rejected(
          'La evidencia bancaria perdió su cartola de origen.',
        );
      }
      final sourceEvidence = ocrSource.evidenceBySourceRowId(
        ocrEvidence.sourceRowId,
      );
      if (sourceEvidence == null ||
          sourceEvidence.fingerprint != ocrEvidence.fingerprint) {
        throw const PayrollVoucherPreflightException.rejected(
          'La evidencia bancaria ya no corresponde a la cartola importada.',
        );
      }
      if (ocrEvidence.direction != PayrollStatementMovementDirection.outgoing ||
          ocrEvidence.bookingDate == null ||
          leg.amountClp > ocrEvidence.availableAmountClp) {
        throw const PayrollVoucherPreflightException.rejected(
          'La transferencia elegida no tiene evidencia bancaria completa.',
        );
      }
      evidenceAccountIds.add(accountId);
      evidenceAllocatedBySourceRowId.update(
        ocrEvidence.sourceRowId,
        (amount) => amount + leg.amountClp,
        ifAbsent: () => leg.amountClp,
      );
      expectedEvidenceLegIds.add(legId);
      evidence = <String, dynamic>{
        'source_row_id': ocrEvidence.sourceRowId,
        'amount': leg.amountClp,
      };
    }

    return <String, dynamic>{
      'leg_id': legId,
      'amount': leg.amountClp,
      'funding_kind': fundingKind,
      'payment_method_id': methodId,
      'payment_account_id': accountId,
      'payment_date': _paymentInstant(paymentDate),
      if (leg.reference?.trim().isNotEmpty == true)
        'reference': _boundedRequiredText(
          leg.reference!,
          maxLength: 500,
          message: 'Una referencia de pago es demasiado larga.',
        ),
      if (leg.notes?.trim().isNotEmpty == true)
        'notes': _boundedRequiredText(
          leg.notes!,
          maxLength: 2000,
          message: 'Una nota de pago es demasiado larga.',
        ),
      if (evidence != null) 'evidence': <Map<String, dynamic>>[evidence],
    };
  }

  _SerializedStatement _serializeStatement(
    PayrollOcrStatementSource source, {
    required String accountId,
  }) {
    final filename = source.filename.trim();
    final digest = source.fileSha256.trim().toLowerCase();
    final accountFingerprint = source.accountFingerprint.trim().toLowerCase();
    if (filename.isEmpty ||
        filename.length > 255 ||
        !_sha256Pattern.hasMatch(digest) ||
        !_sha256Pattern.hasMatch(accountFingerprint) ||
        source.evidenceRows.isEmpty ||
        source.evidenceRows.length > 2000) {
      throw const PayrollVoucherPreflightException.rejected(
        'La cartola no conserva una identidad verificable. Vuelve a importarla.',
      );
    }
    _requireUuid(accountId, 'La cuenta bancaria de la cartola no es válida.');

    final dates = source.evidenceRows
        .map((row) => row.bookingDate)
        .whereType<PayrollCivilDate>()
        .toList(growable: false)
      ..sort();
    final start =
        source.statementStartDate ?? (dates.isEmpty ? null : dates.first);
    final end = source.statementEndDate ??
        source.documentDate ??
        (dates.isEmpty ? null : dates.last);
    if (start == null || end == null || end.compareTo(start) < 0) {
      throw const PayrollVoucherPreflightException.rejected(
        'La cartola no trae un rango de fechas verificable.',
      );
    }

    final seenSourceIds = <String>{};
    final seenOrdinals = <int>{};
    final rows = <Map<String, dynamic>>[];
    final sortedRows = [...source.evidenceRows]..sort((left, right) {
        final ordinal = left.ordinal.compareTo(right.ordinal);
        return ordinal != 0
            ? ordinal
            : left.sourceRowId.compareTo(right.sourceRowId);
      });
    for (final row in sortedRows) {
      final sourceRowId = row.sourceRowId.trim();
      final fingerprint = row.fingerprint.trim().toLowerCase();
      final description = row.description.trim();
      final direction = switch (row.direction) {
        PayrollStatementMovementDirection.outgoing => 'debit',
        PayrollStatementMovementDirection.incoming => 'credit',
        PayrollStatementMovementDirection.unknown => null,
      };
      if (sourceRowId.isEmpty ||
          sourceRowId.length > 100 ||
          !seenSourceIds.add(sourceRowId) ||
          row.ordinal < 1 ||
          row.ordinal > 2000 ||
          !seenOrdinals.add(row.ordinal) ||
          (fingerprint.isNotEmpty && !_sha256Pattern.hasMatch(fingerprint)) ||
          row.bookingDate == null ||
          direction == null ||
          row.amountClp <= 0 ||
          description.isEmpty ||
          description.length > 500) {
        throw const PayrollVoucherPreflightException.rejected(
          'La cartola contiene una fila sin evidencia estructurada completa.',
        );
      }
      rows.add(<String, dynamic>{
        'source_row_id': sourceRowId,
        if (fingerprint.isNotEmpty) 'fingerprint': fingerprint,
        'ordinal': row.ordinal,
        'transaction_date': row.bookingDate.toString(),
        'direction': direction,
        'amount': row.amountClp,
        'description_observed': description,
        if (row.beneficiaryObserved?.trim().isNotEmpty == true)
          'beneficiary_observed': row.beneficiaryObserved!.trim(),
        if (row.documentReference?.trim().isNotEmpty == true)
          'document_observed': row.documentReference!.trim(),
        if (row.warningCodes.isNotEmpty)
          'warnings': row.warningCodes
              .map((warning) => warning.trim())
              .where((warning) => warning.isNotEmpty)
              .toList(growable: false),
      });
    }

    return _SerializedStatement(
      statement: <String, dynamic>{
        'filename': filename,
        'file_digest': digest,
        'statement_start': start.toString(),
        'statement_end': end.toString(),
        'account_id': accountId,
        'account_fingerprint': accountFingerprint,
        'parser_name': 'payroll_payment_workspace',
        'parser_version': '1',
        'source_type': _canonicalStatementSourceType(source),
      },
      rows: rows,
    );
  }

  static String _canonicalStatementSourceType(
    PayrollOcrStatementSource source,
  ) {
    final supplied = source.sourceType.trim().toLowerCase();
    if (const <String>{'pdf_text', 'pdf_ocr', 'image_ocr'}.contains(supplied)) {
      return supplied;
    }
    final extraction = source.extractionKind.trim().toLowerCase();
    if (supplied == 'image') return 'image_ocr';
    if (supplied == 'pdf') {
      return extraction == 'embeddedpdftext' ? 'pdf_text' : 'pdf_ocr';
    }
    if (extraction == 'embeddedpdftext') return 'pdf_text';
    if (extraction.contains('imageocr')) return 'image_ocr';
    if (extraction.contains('ocr')) return 'pdf_ocr';
    throw const PayrollVoucherPreflightException.rejected(
      'La cartola no conserva un tipo de extracción compatible. Vuelve a '
      'importarla.',
    );
  }

  PayrollPaymentWorkspaceApplyReceipt _validateReceipt(
    dynamic value,
    _BuiltWorkspaceCommand built,
  ) {
    final receipt = _asJsonObject(value);
    final workspaceId = receipt['workspace_id']?.toString().trim() ?? '';
    final operationKey = receipt['operation_key']?.toString().trim() ?? '';
    final status = receipt['status']?.toString().trim().toLowerCase() ?? '';
    final version = _intValue(receipt['version']);
    final replayed = receipt['replayed'];
    final payloadHash = receipt['payload_hash']?.toString().trim() ?? '';
    if (workspaceId != built.workspaceId ||
        operationKey != built.operationKey ||
        status != 'applied' ||
        version == null ||
        version < 1 ||
        replayed is! bool ||
        !_sha256Pattern.hasMatch(payloadHash)) {
      throw StateError(
        'El servidor no confirmó íntegramente el workspace de pago.',
      );
    }

    final targetRows = _asJsonObjectList(receipt['targets']);
    if (targetRows.length != built.expectedTargetIds.length) {
      throw StateError('El servidor confirmó otros pagos de sueldo.');
    }
    final receivedTargetIds = <String>{};
    for (final target in targetRows) {
      final targetId = target['target_id']?.toString().trim() ?? '';
      if (!receivedTargetIds.add(targetId) ||
          !built.expectedTargetIds.contains(targetId) ||
          target['voucher_id']?.toString().trim() !=
              built.expectedVoucherIdsByTarget[targetId]) {
        throw StateError('El servidor confirmó otro trabajador o semana.');
      }
      final legs = _asJsonObjectList(target['legs']);
      final expectedLegIds = built.expectedSalaryLegIdsByTarget[targetId]!;
      final receivedLegIds = <String>{
        for (final leg in legs) leg['leg_id']?.toString().trim() ?? '',
      };
      if (legs.length != expectedLegIds.length ||
          receivedLegIds.length != expectedLegIds.length ||
          !receivedLegIds.containsAll(expectedLegIds)) {
        throw StateError(
            'El servidor no confirmó todas las partes del sueldo.');
      }
    }

    final conceptRows = _asJsonObjectList(receipt['additional_concepts']);
    if (conceptRows.length != built.expectedConceptLegIds.length) {
      throw StateError('El servidor confirmó otros conceptos adicionales.');
    }
    final receivedConceptIds = <String>{};
    for (final concept in conceptRows) {
      final conceptId = concept['concept_id']?.toString().trim() ?? '';
      if (!receivedConceptIds.add(conceptId) ||
          !built.expectedConceptLegIds.containsKey(conceptId)) {
        throw StateError('El servidor confirmó otro concepto adicional.');
      }
      final disposition = concept['disposition']?.toString().trim() ?? '';
      final expectedDisposition =
          built.expectedConceptDispositions[conceptId] ?? '';
      if (disposition != expectedDisposition) {
        throw StateError(
          'El servidor confirmó otra clasificación para el concepto.',
        );
      }
      final expectedVoucherId = built.expectedConceptVoucherIds[conceptId];
      final expectedLineId = built.expectedConceptLineIds[conceptId];
      final expectedTargetId = built.expectedConceptTargetIds[conceptId];
      if (expectedDisposition == 'included_in_payroll_total') {
        if (concept['target_id']?.toString().trim() != expectedTargetId ||
            concept['voucher_id']?.toString().trim() != expectedVoucherId ||
            concept['voucher_line_id']?.toString().trim() != expectedLineId ||
            !_looksLikeUuid(concept['reclassification_id']?.toString()) ||
            !_looksLikeUuid(
              concept['reclassification_journal_entry_id']?.toString(),
            )) {
          throw StateError(
            'El servidor no confirmó la reclasificación del concepto.',
          );
        }
      } else if (concept['voucher_id'] != null ||
          concept['target_id'] != null ||
          concept['voucher_line_id'] != null ||
          concept['reclassification_id'] != null ||
          concept['reclassification_journal_entry_id'] != null) {
        throw StateError(
          'El servidor vinculó a nómina un concepto que se sumaba aparte.',
        );
      }
      final legs = _asJsonObjectList(concept['payment_legs']);
      final expectedLegIds = built.expectedConceptLegIds[conceptId]!;
      final receivedLegIds = <String>{
        for (final leg in legs) leg['leg_id']?.toString().trim() ?? '',
      };
      if (legs.length != expectedLegIds.length ||
          receivedLegIds.length != expectedLegIds.length ||
          !receivedLegIds.containsAll(expectedLegIds)) {
        throw StateError(
          'El servidor no confirmó todas las partes del concepto adicional.',
        );
      }
    }

    final allocationRows = _asJsonObjectList(receipt['statement_allocations']);
    final receivedEvidenceLegIds = <String>{
      for (final allocation in allocationRows)
        allocation['leg_id']?.toString().trim() ?? '',
    };
    if (allocationRows.length != built.expectedEvidenceLegIds.length ||
        receivedEvidenceLegIds.length != built.expectedEvidenceLegIds.length ||
        !receivedEvidenceLegIds.containsAll(built.expectedEvidenceLegIds)) {
      throw StateError('El servidor no confirmó toda la evidencia bancaria.');
    }

    if (built.statementFileDigest != null) {
      final statement = _asJsonObject(receipt['statement']);
      if (statement['file_digest']?.toString().trim() !=
              built.statementFileDigest ||
          statement['account_id']?.toString().trim() !=
              built.statementAccountId ||
          !_looksLikeUuid(statement['import_id']?.toString())) {
        throw StateError(
            'El servidor no confirmó la cartola usada como respaldo.');
      }
    } else if (receipt['statement'] != null) {
      throw StateError('El servidor vinculó una cartola que no fue enviada.');
    }

    return PayrollPaymentWorkspaceApplyReceipt(
      workspaceId: workspaceId,
      operationKey: operationKey,
      version: version,
      replayed: replayed,
      raw: receipt,
    );
  }

  PayrollVoucherPreflightException _deterministicFailure(
    PostgrestException error,
  ) {
    final code = error.code?.trim().toLowerCase() ?? '';
    final evidence = <Object?>[
      error.message,
      error.details,
      error.hint,
    ]
        .whereType<Object>()
        .map((item) => item.toString().toLowerCase())
        .join(' ');
    if (code == '42883' ||
        code == 'pgrst202' ||
        evidence.contains('could not find the function') ||
        evidence.contains('schema cache')) {
      return const PayrollVoucherPreflightException.unavailable(
        'El escritor flexible de nóminas todavía no está disponible en el '
        'servidor. No se registró ningún pago.',
      );
    }
    if (code == '40001' || evidence.contains('version_conflict')) {
      return const PayrollVoucherPreflightException.rejected(
        'La nómina o la cartola cambió mientras editabas. Recarga antes de '
        'volver a guardar.',
      );
    }
    if (evidence.contains('idempotency_conflict')) {
      return const PayrollVoucherPreflightException.rejected(
        'La identidad de esta operación ya corresponde a otro intento. Recarga '
        'Nóminas antes de continuar.',
      );
    }
    if (code == '42501') {
      return const PayrollVoucherPreflightException.rejected(
        'No tienes permisos o una cuenta del pago ya no es válida. Recarga y '
        'revisa la configuración.',
      );
    }
    if (code == '22023' || code == '23514' || code == '23505') {
      return const PayrollVoucherPreflightException.rejected(
        'El servidor rechazó la composición del pago. Revisa montos, saldos y '
        'evidencia antes de volver a guardar.',
      );
    }
    return const PayrollVoucherPreflightException.rejected(
      'El servidor rechazó el pago y no registró movimientos. Revisa la nómina '
      'antes de volver a intentarlo.',
    );
  }

  PayrollVoucherPreflightException _approvalFailure(
    PostgrestException error,
  ) {
    final code = error.code?.trim().toLowerCase() ?? '';
    final evidence = <Object?>[error.message, error.details, error.hint]
        .whereType<Object>()
        .map((item) => item.toString().toLowerCase())
        .join(' ');
    if (code == '42883' ||
        code == 'pgrst202' ||
        evidence.contains('could not find the function') ||
        evidence.contains('schema cache')) {
      return const PayrollVoucherPreflightException.unavailable(
        'La aprobación en lote todavía no está disponible en el servidor. '
        'No se confirmó ninguna semana.',
      );
    }
    if (code == '40001' || evidence.contains('version_conflict')) {
      return const PayrollVoucherPreflightException.rejected(
        'Una semana cambió mientras preparabas los pagos. Recarga antes de '
        'aprobarlas.',
      );
    }
    if (evidence.contains('idempotency_conflict')) {
      return const PayrollVoucherPreflightException.rejected(
        'Esta aprobación ya corresponde a otro intento. Recarga Nóminas.',
      );
    }
    if (code == '42501') {
      return const PayrollVoucherPreflightException.rejected(
        'No tienes permiso para aprobar estas semanas.',
      );
    }
    return const PayrollVoucherPreflightException.rejected(
      'El servidor rechazó la aprobación y no cambió ninguna semana.',
    );
  }

  bool _isAmbiguousTransportFailure(PostgrestException error) {
    final code = error.code?.trim().toLowerCase() ?? '';
    final evidence = <Object?>[
      error.message,
      error.details,
      error.hint,
    ]
        .whereType<Object>()
        .map((item) => item.toString().toLowerCase())
        .join(' ');
    return code.startsWith('08') ||
        const <String>{
          '57p01',
          '57p02',
          '57p03',
          '53300',
          '53400',
          'pgrst000',
          'pgrst001',
          'pgrst002',
        }.contains(code) ||
        const <String>{
          'connection',
          'network',
          'socket',
          'timeout',
          'timed out',
          'temporarily unavailable',
          'service unavailable',
          'gateway timeout',
          'failed to fetch',
        }.any(evidence.contains);
  }

  static String _paymentInstant(PayrollCivilDate date) => DateTime.utc(
        date.year,
        date.month,
        date.day,
        12,
      ).toIso8601String();

  static String _boundedRequiredText(
    String value, {
    required int maxLength,
    required String message,
  }) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > maxLength) {
      throw PayrollVoucherPreflightException.rejected(message);
    }
    return trimmed;
  }

  static void _requireUuid(String value, String message) {
    if (!_looksLikeUuid(value)) {
      throw PayrollVoucherPreflightException.rejected(message);
    }
  }

  static bool _looksLikeUuid(String? value) =>
      value != null && _uuidPattern.hasMatch(value.trim());

  static int? _intValue(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static Map<String, dynamic> _asJsonObject(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    throw StateError('El servidor no confirmó el workspace de pago.');
  }

  static List<Map<String, dynamic>> _asJsonObjectList(dynamic value) {
    if (value is! List) {
      throw StateError('El servidor devolvió un recibo de pago incompleto.');
    }
    return value.map(_asJsonObject).toList(growable: false);
  }
}

class _SerializedStatement {
  const _SerializedStatement({
    required this.statement,
    required this.rows,
  });

  final Map<String, dynamic> statement;
  final List<Map<String, dynamic>> rows;
}

class _BuiltWorkspaceCommand {
  _BuiltWorkspaceCommand({
    required this.params,
    required this.workspaceId,
    required this.operationKey,
    required this.expectedTargetIds,
    required this.expectedSalaryLegIdsByTarget,
    required this.expectedVoucherIdsByTarget,
    required this.expectedConceptLegIds,
    required this.expectedConceptDispositions,
    required this.expectedConceptVoucherIds,
    required this.expectedConceptLineIds,
    required this.expectedConceptTargetIds,
    required this.expectedEvidenceLegIds,
    required this.statementFileDigest,
    required this.statementAccountId,
  });

  final Map<String, dynamic> params;
  final String workspaceId;
  final String operationKey;
  final Set<String> expectedTargetIds;
  final Map<String, Set<String>> expectedSalaryLegIdsByTarget;
  final Map<String, String> expectedVoucherIdsByTarget;
  final Map<String, Set<String>> expectedConceptLegIds;
  final Map<String, String> expectedConceptDispositions;
  final Map<String, String?> expectedConceptVoucherIds;
  final Map<String, String?> expectedConceptLineIds;
  final Map<String, String?> expectedConceptTargetIds;
  final Set<String> expectedEvidenceLegIds;
  final String? statementFileDigest;
  final String? statementAccountId;
}
