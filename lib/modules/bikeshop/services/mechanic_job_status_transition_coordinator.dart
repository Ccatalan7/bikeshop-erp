typedef MechanicJobStatusTransitionSender = Future<Object?> Function(
  Map<String, dynamic> params,
);
typedef MechanicJobStatusTransitionReadback = Future<Map<String, dynamic>?>
    Function(String operationKey, String jobId);
typedef MechanicJobStatusTransitionAmbiguityTest = bool Function(Object error);

enum MechanicJobStatusTransitionConfirmation {
  acknowledged,
  reconciledFromReadback,
}

class MechanicJobStatusTransitionRequest {
  MechanicJobStatusTransitionRequest({
    required String jobId,
    required String statusId,
    required String operationKey,
  })  : jobId = _required(jobId, 'jobId'),
        statusId = _required(statusId, 'statusId'),
        operationKey = _required(operationKey, 'operationKey');

  final String jobId;
  final String statusId;
  final String operationKey;

  Map<String, dynamic> toRpcParams() => {
        'p_job_id': jobId,
        'p_status_id': statusId,
        'p_operation_key': operationKey,
      };

  bool matchesReceipt(Object? raw) {
    if (raw is! Map) return false;
    final receipt = Map<String, dynamic>.from(raw);
    if (receipt['job_id']?.toString() != jobId ||
        receipt['to_status_id']?.toString() != statusId ||
        receipt['operation_key']?.toString() != operationKey ||
        receipt['id']?.toString().trim().isEmpty != false) {
      return false;
    }

    final request = receipt['request_snapshot'];
    if (request is! Map) return false;
    final stored = Map<String, dynamic>.from(request);
    if (stored['job_id']?.toString() != jobId ||
        stored['status_id']?.toString() != statusId) {
      return false;
    }

    final response = _responseSnapshot(receipt);
    if (response == null ||
        response['job_id']?.toString() != jobId ||
        response['status_id']?.toString() != statusId ||
        response['changed'] is! bool ||
        response['job'] is! Map) {
      return false;
    }
    final job = Map<String, dynamic>.from(response['job'] as Map);
    return job['id']?.toString() == jobId &&
        job['status_id']?.toString() == statusId &&
        job['status']?.toString() == response['status']?.toString();
  }

  static Map<String, dynamic>? _responseSnapshot(
    Map<String, dynamic> receipt,
  ) {
    final nested = receipt['response_snapshot'];
    if (nested is Map) return Map<String, dynamic>.from(nested);
    if (receipt['job'] is Map) return receipt;
    return null;
  }

  static String _required(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, 'Must not be empty');
    }
    return normalized;
  }
}

class MechanicJobStatusTransitionResult {
  const MechanicJobStatusTransitionResult({
    required this.request,
    required this.receipt,
    required this.confirmation,
    required this.replayAttempted,
  });

  final MechanicJobStatusTransitionRequest request;
  final Map<String, dynamic> receipt;
  final MechanicJobStatusTransitionConfirmation confirmation;
  final bool replayAttempted;

  bool get reconciledFromReadback =>
      confirmation ==
      MechanicJobStatusTransitionConfirmation.reconciledFromReadback;

  Map<String, dynamic> get authoritativeJobSnapshot {
    final nested = receipt['response_snapshot'];
    final response = nested is Map
        ? Map<String, dynamic>.from(nested)
        : Map<String, dynamic>.from(receipt);
    return Map<String, dynamic>.from(response['job'] as Map);
  }

  bool get changed {
    final nested = receipt['response_snapshot'];
    final response = nested is Map
        ? Map<String, dynamic>.from(nested)
        : Map<String, dynamic>.from(receipt);
    return response['changed'] as bool;
  }
}

class MechanicJobStatusTransitionReceiptMismatch implements Exception {
  const MechanicJobStatusTransitionReceiptMismatch(this.request);

  final MechanicJobStatusTransitionRequest request;

  @override
  String toString() =>
      'La clave de operación ya tiene un comprobante de estado distinto. '
      'No se reintentó para evitar otra transición.';
}

class MechanicJobStatusTransitionOutcomeUnknown implements Exception {
  const MechanicJobStatusTransitionOutcomeUnknown({
    required this.request,
    required this.firstError,
    required this.replayError,
    required this.readbackError,
  });

  final MechanicJobStatusTransitionRequest request;
  final Object firstError;
  final Object replayError;
  final Object readbackError;

  @override
  String toString() =>
      'No se pudo confirmar el cambio de estado. La ficha se recargará desde '
      'el servidor; cualquier reintento debe conservar la misma operación.';
}

class MechanicJobStatusTransitionCoordinator {
  const MechanicJobStatusTransitionCoordinator({
    required this.send,
    required this.readback,
    required this.isOutcomeAmbiguous,
  });

  final MechanicJobStatusTransitionSender send;
  final MechanicJobStatusTransitionReadback readback;
  final MechanicJobStatusTransitionAmbiguityTest isOutcomeAmbiguous;

  Future<MechanicJobStatusTransitionResult> execute(
    MechanicJobStatusTransitionRequest request,
  ) async {
    Object? firstError;
    try {
      final raw = await send(request.toRpcParams());
      final receipt = _matchingReceipt(request, raw);
      if (receipt != null) {
        return _acknowledged(request, receipt, replayAttempted: false);
      }
      firstError = const FormatException(
        'Status transition returned a mismatched receipt',
      );
    } catch (error) {
      if (!isOutcomeAmbiguous(error)) rethrow;
      firstError = error;
    }

    final firstReadback = await _read(request);
    if (firstReadback.mismatch) {
      throw MechanicJobStatusTransitionReceiptMismatch(request);
    }
    if (firstReadback.receipt != null) {
      return _reconciled(
        request,
        firstReadback.receipt!,
        replayAttempted: false,
      );
    }

    Object? replayError;
    var replayWasDeterministicRejection = false;
    try {
      final raw = await send(request.toRpcParams());
      final receipt = _matchingReceipt(request, raw);
      if (receipt != null) {
        return _acknowledged(request, receipt, replayAttempted: true);
      }
      replayError = const FormatException(
        'Status transition replay returned a mismatched receipt',
      );
    } catch (error) {
      replayError = error;
      replayWasDeterministicRejection = !isOutcomeAmbiguous(error);
    }

    final finalReadback = await _read(request);
    if (finalReadback.mismatch) {
      throw MechanicJobStatusTransitionReceiptMismatch(request);
    }
    if (finalReadback.receipt != null) {
      return _reconciled(
        request,
        finalReadback.receipt!,
        replayAttempted: true,
      );
    }

    if (replayWasDeterministicRejection &&
        firstReadback.error == null &&
        finalReadback.error == null) {
      throw replayError;
    }

    throw MechanicJobStatusTransitionOutcomeUnknown(
      request: request,
      firstError: firstError,
      replayError: replayError,
      readbackError: finalReadback.error ??
          firstReadback.error ??
          StateError('No exact status transition receipt was readable'),
    );
  }

  Future<_StatusTransitionReadback> _read(
    MechanicJobStatusTransitionRequest request,
  ) async {
    try {
      final raw = await readback(request.operationKey, request.jobId);
      if (raw == null) return const _StatusTransitionReadback();
      final receipt = _matchingReceipt(request, raw);
      if (receipt == null) {
        return const _StatusTransitionReadback(mismatch: true);
      }
      return _StatusTransitionReadback(receipt: receipt);
    } catch (error) {
      return _StatusTransitionReadback(error: error);
    }
  }

  MechanicJobStatusTransitionResult _acknowledged(
    MechanicJobStatusTransitionRequest request,
    Map<String, dynamic> receipt, {
    required bool replayAttempted,
  }) =>
      MechanicJobStatusTransitionResult(
        request: request,
        receipt: receipt,
        confirmation: MechanicJobStatusTransitionConfirmation.acknowledged,
        replayAttempted: replayAttempted,
      );

  MechanicJobStatusTransitionResult _reconciled(
    MechanicJobStatusTransitionRequest request,
    Map<String, dynamic> receipt, {
    required bool replayAttempted,
  }) =>
      MechanicJobStatusTransitionResult(
        request: request,
        receipt: receipt,
        confirmation:
            MechanicJobStatusTransitionConfirmation.reconciledFromReadback,
        replayAttempted: replayAttempted,
      );

  Map<String, dynamic>? _matchingReceipt(
    MechanicJobStatusTransitionRequest request,
    Object? raw,
  ) {
    if (!request.matchesReceipt(raw)) return null;
    return Map<String, dynamic>.from(raw! as Map);
  }
}

class _StatusTransitionReadback {
  const _StatusTransitionReadback({
    this.receipt,
    this.error,
    this.mismatch = false,
  });

  final Map<String, dynamic>? receipt;
  final Object? error;
  final bool mismatch;
}
