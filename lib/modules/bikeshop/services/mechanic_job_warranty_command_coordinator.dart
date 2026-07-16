typedef MechanicJobWarrantyCommandSender = Future<Object?> Function(
  String functionName,
  Map<String, dynamic> params,
);
typedef MechanicJobWarrantyCommandReadback = Future<Map<String, dynamic>?>
    Function(String operationKey);
typedef MechanicJobWarrantyCommandAmbiguityTest = bool Function(Object error);

enum MechanicJobWarrantyCommandKind { registration, decision }

enum MechanicJobWarrantyCommandConfirmation {
  acknowledged,
  reconciledFromReadback,
}

class MechanicJobWarrantyCommandRequest {
  MechanicJobWarrantyCommandRequest.registration({
    required String warrantyJobId,
    required String sourceJobId,
    required String operationKey,
  })  : kind = MechanicJobWarrantyCommandKind.registration,
        warrantyJobId = _required(warrantyJobId, 'warrantyJobId'),
        sourceJobId = _required(sourceJobId, 'sourceJobId'),
        outcome = null,
        reason = null,
        operationKey = _required(operationKey, 'operationKey');

  MechanicJobWarrantyCommandRequest.decision({
    required String warrantyJobId,
    required String outcome,
    required String operationKey,
    String? reason,
  })  : kind = MechanicJobWarrantyCommandKind.decision,
        warrantyJobId = _required(warrantyJobId, 'warrantyJobId'),
        sourceJobId = null,
        outcome = _required(outcome, 'outcome'),
        reason = _optional(reason),
        operationKey = _required(operationKey, 'operationKey');

  final MechanicJobWarrantyCommandKind kind;
  final String warrantyJobId;
  final String? sourceJobId;
  final String? outcome;
  final String? reason;
  final String operationKey;

  String get functionName => switch (kind) {
        MechanicJobWarrantyCommandKind.registration =>
          'register_mechanic_job_warranty_claim',
        MechanicJobWarrantyCommandKind.decision =>
          'decide_mechanic_job_warranty_claim',
      };

  Map<String, dynamic> toRpcParams() => switch (kind) {
        MechanicJobWarrantyCommandKind.registration => {
            'p_warranty_job_id': warrantyJobId,
            'p_source_job_id': sourceJobId,
            'p_operation_key': operationKey,
          },
        MechanicJobWarrantyCommandKind.decision => {
            'p_warranty_job_id': warrantyJobId,
            'p_outcome': outcome,
            'p_reason': reason,
            'p_operation_key': operationKey,
          },
      };

  bool matchesEvent(Object? raw) {
    if (raw is! Map) return false;
    final event = Map<String, dynamic>.from(raw);
    if (event['warranty_job_id']?.toString() != warrantyJobId ||
        event['operation_key']?.toString() != operationKey) {
      return false;
    }

    switch (kind) {
      case MechanicJobWarrantyCommandKind.registration:
        return event['event_type']?.toString() == 'registration' &&
            event['source_job_id']?.toString() == sourceJobId;
      case MechanicJobWarrantyCommandKind.decision:
        return event['event_type']?.toString() == 'decision' &&
            event['outcome']?.toString() == outcome &&
            _optional(event['reason']?.toString()) == reason;
    }
  }

  /// A registration command is an "ensure this exact source link" command.
  /// The server may truthfully answer with an older registration receipt when
  /// that invariant was already satisfied before this operation key existed.
  /// Only a direct RPC response explicitly marked as a replay can use that
  /// semantic acknowledgement; operation-key readback remains exact.
  bool matchesResponse(Object? raw) {
    if (matchesEvent(raw)) return true;
    if (kind != MechanicJobWarrantyCommandKind.registration || raw is! Map) {
      return false;
    }
    final event = Map<String, dynamic>.from(raw);
    return event['replay'] == true &&
        event['warranty_job_id']?.toString() == warrantyJobId &&
        event['source_job_id']?.toString() == sourceJobId &&
        event['event_type']?.toString() == 'registration';
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

class MechanicJobWarrantyCommandResult {
  const MechanicJobWarrantyCommandResult({
    required this.request,
    required this.event,
    required this.confirmation,
    required this.replayAttempted,
  });

  final MechanicJobWarrantyCommandRequest request;
  final Map<String, dynamic> event;
  final MechanicJobWarrantyCommandConfirmation confirmation;
  final bool replayAttempted;

  bool get reconciledFromReadback =>
      confirmation ==
      MechanicJobWarrantyCommandConfirmation.reconciledFromReadback;
}

class MechanicJobWarrantyCommandOutcomeUnknown implements Exception {
  const MechanicJobWarrantyCommandOutcomeUnknown({
    required this.request,
    required this.firstError,
    required this.replayError,
    required this.readbackError,
  });

  final MechanicJobWarrantyCommandRequest request;
  final Object firstError;
  final Object replayError;
  final Object readbackError;

  @override
  String toString() =>
      'No se pudo confirmar el resultado de la acción de garantía. '
      'Reintentar debe reutilizar la misma clave de operación.';
}

class MechanicJobWarrantyCommandCoordinator {
  const MechanicJobWarrantyCommandCoordinator({
    required this.send,
    required this.readback,
    required this.isOutcomeAmbiguous,
  });

  final MechanicJobWarrantyCommandSender send;
  final MechanicJobWarrantyCommandReadback readback;
  final MechanicJobWarrantyCommandAmbiguityTest isOutcomeAmbiguous;

  Future<MechanicJobWarrantyCommandResult> execute(
    MechanicJobWarrantyCommandRequest request,
  ) async {
    Object? firstError;
    try {
      final response = await send(request.functionName, request.toRpcParams());
      final event = _matchingResponse(request, response);
      if (event != null) {
        return MechanicJobWarrantyCommandResult(
          request: request,
          event: event,
          confirmation: MechanicJobWarrantyCommandConfirmation.acknowledged,
          replayAttempted: false,
        );
      }
      firstError = const FormatException(
        'Warranty command returned a mismatched response',
      );
    } catch (error) {
      if (!isOutcomeAmbiguous(error)) rethrow;
      firstError = error;
    }

    final firstReadback = await _read(request);
    if (firstReadback.event != null) {
      return MechanicJobWarrantyCommandResult(
        request: request,
        event: firstReadback.event!,
        confirmation:
            MechanicJobWarrantyCommandConfirmation.reconciledFromReadback,
        replayAttempted: false,
      );
    }

    Object? replayError;
    try {
      final response = await send(request.functionName, request.toRpcParams());
      final event = _matchingResponse(request, response);
      if (event != null) {
        return MechanicJobWarrantyCommandResult(
          request: request,
          event: event,
          confirmation: MechanicJobWarrantyCommandConfirmation.acknowledged,
          replayAttempted: true,
        );
      }
      replayError = const FormatException(
        'Warranty command replay returned a mismatched response',
      );
    } catch (error) {
      replayError = error;
    }

    final finalReadback = await _read(request);
    if (finalReadback.event != null) {
      return MechanicJobWarrantyCommandResult(
        request: request,
        event: finalReadback.event!,
        confirmation:
            MechanicJobWarrantyCommandConfirmation.reconciledFromReadback,
        replayAttempted: true,
      );
    }

    throw MechanicJobWarrantyCommandOutcomeUnknown(
      request: request,
      firstError: firstError,
      replayError: replayError,
      readbackError: finalReadback.error ??
          firstReadback.error ??
          StateError('No matching warranty event was readable.'),
    );
  }

  Future<_WarrantyCommandReadback> _read(
    MechanicJobWarrantyCommandRequest request,
  ) async {
    try {
      final raw = await readback(request.operationKey);
      final event = _matchingEvent(request, raw);
      return event == null
          ? const _WarrantyCommandReadback()
          : _WarrantyCommandReadback(event: event);
    } catch (error) {
      return _WarrantyCommandReadback(error: error);
    }
  }

  Map<String, dynamic>? _matchingEvent(
    MechanicJobWarrantyCommandRequest request,
    Object? raw,
  ) {
    if (!request.matchesEvent(raw)) return null;
    return Map<String, dynamic>.from(raw! as Map);
  }

  Map<String, dynamic>? _matchingResponse(
    MechanicJobWarrantyCommandRequest request,
    Object? raw,
  ) {
    if (!request.matchesResponse(raw)) return null;
    return Map<String, dynamic>.from(raw! as Map);
  }
}

class _WarrantyCommandReadback {
  const _WarrantyCommandReadback({this.event, this.error});

  final Map<String, dynamic>? event;
  final Object? error;
}
