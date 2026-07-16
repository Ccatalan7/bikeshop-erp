typedef MechanicJobQuotationCommandSender = Future<Object?> Function(
  String functionName,
  Map<String, dynamic> params,
);
typedef MechanicJobQuotationCommandReadback = Future<Map<String, dynamic>?>
    Function(String operationKey, String jobId);
typedef MechanicJobQuotationInvariantReadback = Future<bool> Function(
  MechanicJobQuotationCommandRequest request,
);
typedef MechanicJobQuotationCommandAmbiguityTest = bool Function(Object error);

enum MechanicJobQuotationCommandKind { transition, conversion }

enum MechanicJobQuotationCommandConfirmation {
  acknowledged,
  reconciledFromReadback,
  reconciledFromInvariant,
}

class MechanicJobQuotationCommandRequest {
  MechanicJobQuotationCommandRequest.transition({
    required String jobId,
    required String status,
    required String operationKey,
    String? reason,
  })  : kind = MechanicJobQuotationCommandKind.transition,
        jobId = _required(jobId, 'jobId'),
        status = _required(status, 'status'),
        targetJobType = null,
        reason = _optional(reason),
        shouldCreateInvoice = null,
        bikeId = null,
        subjectId = null,
        operationKey = _required(operationKey, 'operationKey');

  MechanicJobQuotationCommandRequest.conversion({
    required String jobId,
    required String targetJobType,
    required bool createInvoice,
    required String operationKey,
    String? reason,
    String? bikeId,
    String? subjectId,
  })  : kind = MechanicJobQuotationCommandKind.conversion,
        jobId = _required(jobId, 'jobId'),
        status = null,
        targetJobType = _required(targetJobType, 'targetJobType'),
        reason = _optional(reason),
        shouldCreateInvoice = createInvoice,
        bikeId = _optional(bikeId),
        subjectId = _optional(subjectId),
        operationKey = _required(operationKey, 'operationKey');

  final MechanicJobQuotationCommandKind kind;
  final String jobId;
  final String? status;
  final String? targetJobType;
  final String? reason;
  final bool? shouldCreateInvoice;
  final String? bikeId;
  final String? subjectId;
  final String operationKey;

  String get functionName => switch (kind) {
        MechanicJobQuotationCommandKind.transition =>
          'transition_mechanic_job_quotation',
        MechanicJobQuotationCommandKind.conversion =>
          'convert_mechanic_job_to_billable',
      };

  String get eventType => switch (kind) {
        MechanicJobQuotationCommandKind.transition =>
          'quotation_status_changed',
        MechanicJobQuotationCommandKind.conversion => 'converted_to_billable',
      };

  String? get targetIntakeKind => switch (targetJobType) {
        'service' => 'bike',
        'item_service' => 'component',
        _ => null,
      };

  Map<String, dynamic> toRpcParams() => switch (kind) {
        MechanicJobQuotationCommandKind.transition => {
            'p_job_id': jobId,
            'p_status': status,
            'p_reason': reason,
            'p_operation_key': operationKey,
          },
        MechanicJobQuotationCommandKind.conversion => {
            'p_job_id': jobId,
            'p_target_job_type': targetJobType,
            'p_reason': reason,
            'p_create_invoice': shouldCreateInvoice,
            'p_bike_id': bikeId,
            'p_subject_id': subjectId,
            'p_operation_key': operationKey,
          },
      };

  bool matchesResponse(Object? raw) {
    if (raw is! Map) return false;
    final response = Map<String, dynamic>.from(raw);
    if (response['job_id']?.toString() != jobId) return false;

    switch (kind) {
      case MechanicJobQuotationCommandKind.transition:
        if (response['quotation_status']?.toString() != status) return false;
        final eventId = _optional(response['event_id']?.toString());
        // `event_id = null` is the server's explicit, valid same-state no-op.
        return response['job_type']?.toString() == 'quotation' &&
            response['workflow_kind']?.toString() == 'quotation' &&
            response.containsKey('event_id') &&
            (eventId == null || eventId.isNotEmpty);
      case MechanicJobQuotationCommandKind.conversion:
        final eventId = _optional(response['event_id']?.toString());
        final invoiceId = _optional(response['invoice_id']?.toString());
        return response['job_type']?.toString() == targetJobType &&
            response['workflow_kind']?.toString() == 'service' &&
            response['intake_kind']?.toString() == targetIntakeKind &&
            eventId != null &&
            (shouldCreateInvoice == true
                ? invoiceId != null
                : invoiceId == null);
    }
  }

  bool matchesEvent(Object? raw) {
    if (raw is! Map) return false;
    final event = Map<String, dynamic>.from(raw);
    if (event['job_id']?.toString() != jobId ||
        event['operation_key']?.toString() != operationKey ||
        event['event_type']?.toString() != eventType) {
      return false;
    }
    final metadata = event['metadata'];
    if (metadata is! Map) return false;
    final request = metadata['request'];
    if (request is! Map) return false;
    final stored = Map<String, dynamic>.from(request);

    switch (kind) {
      case MechanicJobQuotationCommandKind.transition:
        return stored['status']?.toString() == status &&
            _optional(stored['reason']?.toString()) == reason &&
            event['to_quotation_status']?.toString() == status;
      case MechanicJobQuotationCommandKind.conversion:
        return stored['target_job_type']?.toString() == targetJobType &&
            _optional(stored['reason']?.toString()) == reason &&
            stored['create_invoice'] == shouldCreateInvoice &&
            _optional(stored['bike_id']?.toString()) == bikeId &&
            _optional(stored['subject_id']?.toString()) == subjectId &&
            event['to_job_type']?.toString() == targetJobType &&
            event['to_workflow_kind']?.toString() == 'service' &&
            event['to_intake_kind']?.toString() == targetIntakeKind &&
            (shouldCreateInvoice == true
                ? _optional(event['invoice_id']?.toString()) != null
                : _optional(event['invoice_id']?.toString()) == null);
    }
  }

  static String _required(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, 'Must not be empty');
    }
    return normalized;
  }

  static String? _optional(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

class MechanicJobQuotationCommandResult {
  const MechanicJobQuotationCommandResult({
    required this.request,
    required this.receipt,
    required this.confirmation,
    required this.replayAttempted,
  });

  final MechanicJobQuotationCommandRequest request;

  /// Exact server response/event when one exists. A same-state quotation
  /// transition intentionally creates no event, so invariant reconciliation
  /// confirms success without fabricating a receipt.
  final Map<String, dynamic>? receipt;
  final MechanicJobQuotationCommandConfirmation confirmation;
  final bool replayAttempted;

  bool get reconciledFromReadback =>
      confirmation ==
      MechanicJobQuotationCommandConfirmation.reconciledFromReadback;

  String? get invoiceId {
    final normalized = receipt?['invoice_id']?.toString().trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

class MechanicJobQuotationCommandReceiptMismatch implements Exception {
  const MechanicJobQuotationCommandReceiptMismatch(this.request);

  final MechanicJobQuotationCommandRequest request;

  @override
  String toString() =>
      'La clave de operación ya tiene un comprobante distinto. '
      'No se reintentó para evitar aplicar otra acción.';
}

class MechanicJobQuotationCommandOutcomeUnknown implements Exception {
  const MechanicJobQuotationCommandOutcomeUnknown({
    required this.request,
    required this.firstError,
    required this.replayError,
    required this.readbackError,
  });

  final MechanicJobQuotationCommandRequest request;
  final Object firstError;
  final Object replayError;
  final Object readbackError;

  @override
  String toString() =>
      'No se pudo confirmar el resultado de la acción de presupuesto. '
      'Reintentar debe reutilizar la misma clave de operación.';
}

class MechanicJobQuotationCommandCoordinator {
  const MechanicJobQuotationCommandCoordinator({
    required this.send,
    required this.readback,
    required this.readInvariant,
    required this.isOutcomeAmbiguous,
  });

  final MechanicJobQuotationCommandSender send;
  final MechanicJobQuotationCommandReadback readback;
  final MechanicJobQuotationInvariantReadback readInvariant;
  final MechanicJobQuotationCommandAmbiguityTest isOutcomeAmbiguous;

  Future<MechanicJobQuotationCommandResult> execute(
    MechanicJobQuotationCommandRequest request,
  ) async {
    Object? firstError;
    try {
      final response = await send(request.functionName, request.toRpcParams());
      final receipt = _matchingResponse(request, response);
      if (receipt != null) {
        return MechanicJobQuotationCommandResult(
          request: request,
          receipt: receipt,
          confirmation: MechanicJobQuotationCommandConfirmation.acknowledged,
          replayAttempted: false,
        );
      }
      firstError = const FormatException(
        'Quotation command returned a mismatched response',
      );
    } catch (error) {
      if (!isOutcomeAmbiguous(error)) rethrow;
      firstError = error;
    }

    final firstReadback = await _read(request);
    if (firstReadback.mismatch) {
      throw MechanicJobQuotationCommandReceiptMismatch(request);
    }
    if (firstReadback.receipt != null) {
      return _reconciled(request, firstReadback.receipt!,
          replayAttempted: false);
    }
    final firstInvariant = await _readInvariant(request);
    if (firstInvariant.matches) {
      return _invariantReconciled(request, replayAttempted: false);
    }

    Object? replayError;
    var replayWasDeterministicRejection = false;
    try {
      final response = await send(request.functionName, request.toRpcParams());
      final receipt = _matchingResponse(request, response);
      if (receipt != null) {
        return MechanicJobQuotationCommandResult(
          request: request,
          receipt: receipt,
          confirmation: MechanicJobQuotationCommandConfirmation.acknowledged,
          replayAttempted: true,
        );
      }
      replayError = const FormatException(
        'Quotation command replay returned a mismatched response',
      );
    } catch (error) {
      replayError = error;
      replayWasDeterministicRejection = !isOutcomeAmbiguous(error);
    }

    final finalReadback = await _read(request);
    if (finalReadback.mismatch) {
      throw MechanicJobQuotationCommandReceiptMismatch(request);
    }
    if (finalReadback.receipt != null) {
      return _reconciled(request, finalReadback.receipt!,
          replayAttempted: true);
    }
    final finalInvariant = await _readInvariant(request);
    if (finalInvariant.matches) {
      return _invariantReconciled(request, replayAttempted: true);
    }

    // Two successful, empty exact-key reads plus a deterministic RPC error
    // prove that this semantic operation was rejected rather than merely
    // losing its acknowledgement. The caller must discard this operation key.
    if (replayWasDeterministicRejection &&
        firstReadback.error == null &&
        finalReadback.error == null &&
        firstInvariant.error == null &&
        finalInvariant.error == null) {
      throw replayError;
    }

    throw MechanicJobQuotationCommandOutcomeUnknown(
      request: request,
      firstError: firstError,
      replayError: replayError,
      readbackError: finalReadback.error ??
          firstReadback.error ??
          finalInvariant.error ??
          firstInvariant.error ??
          StateError('No matching quotation event was readable.'),
    );
  }

  Future<_QuotationCommandReadback> _read(
    MechanicJobQuotationCommandRequest request,
  ) async {
    try {
      final raw = await readback(request.operationKey, request.jobId);
      if (raw == null) return const _QuotationCommandReadback();
      if (!request.matchesEvent(raw)) {
        return const _QuotationCommandReadback(mismatch: true);
      }
      return _QuotationCommandReadback(
        receipt: Map<String, dynamic>.from(raw),
      );
    } catch (error) {
      return _QuotationCommandReadback(error: error);
    }
  }

  Future<_QuotationInvariantReadback> _readInvariant(
    MechanicJobQuotationCommandRequest request,
  ) async {
    // Conversion needs the immutable event because a matching current row
    // cannot prove the exact bike/subject/reason request. Only a transition
    // may be a deliberate no-event same-state command.
    if (request.kind != MechanicJobQuotationCommandKind.transition) {
      return const _QuotationInvariantReadback();
    }
    try {
      return _QuotationInvariantReadback(matches: await readInvariant(request));
    } catch (error) {
      return _QuotationInvariantReadback(error: error);
    }
  }

  MechanicJobQuotationCommandResult _reconciled(
    MechanicJobQuotationCommandRequest request,
    Map<String, dynamic> receipt, {
    required bool replayAttempted,
  }) {
    return MechanicJobQuotationCommandResult(
      request: request,
      receipt: receipt,
      confirmation:
          MechanicJobQuotationCommandConfirmation.reconciledFromReadback,
      replayAttempted: replayAttempted,
    );
  }

  MechanicJobQuotationCommandResult _invariantReconciled(
    MechanicJobQuotationCommandRequest request, {
    required bool replayAttempted,
  }) {
    return MechanicJobQuotationCommandResult(
      request: request,
      receipt: null,
      confirmation:
          MechanicJobQuotationCommandConfirmation.reconciledFromInvariant,
      replayAttempted: replayAttempted,
    );
  }

  Map<String, dynamic>? _matchingResponse(
    MechanicJobQuotationCommandRequest request,
    Object? raw,
  ) {
    if (!request.matchesResponse(raw)) return null;
    return Map<String, dynamic>.from(raw! as Map);
  }
}

class _QuotationCommandReadback {
  const _QuotationCommandReadback({
    this.receipt,
    this.error,
    this.mismatch = false,
  });

  final Map<String, dynamic>? receipt;
  final Object? error;
  final bool mismatch;
}

class _QuotationInvariantReadback {
  const _QuotationInvariantReadback({this.matches = false, this.error});

  final bool matches;
  final Object? error;
}
