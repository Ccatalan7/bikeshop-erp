import '../models/bikeshop_models.dart';

typedef MechanicJobSaleClassificationSender = Future<Object?> Function(
  Map<String, dynamic> params,
);
typedef MechanicJobSaleClassificationReadback = Future<MechanicJob?> Function(
  String jobId,
);
typedef MechanicJobSaleClassificationAmbiguityTest = bool Function(
    Object error);

enum MechanicJobSaleClassificationConfirmation {
  acknowledged,
  reconciledFromReadback,
}

class MechanicJobSaleClassificationRequest {
  MechanicJobSaleClassificationRequest({
    required String jobId,
    required String operationKey,
    String? reason,
  })  : jobId = _requiredValue(jobId, 'jobId'),
        operationKey = _requiredValue(operationKey, 'operationKey'),
        reason = _optionalValue(reason);

  final String jobId;
  final String operationKey;
  final String? reason;

  Map<String, dynamic> toRpcParams() => {
        'p_job_id': jobId,
        'p_reason': reason,
        'p_operation_key': operationKey,
      };

  bool matches(MechanicJob? job) {
    return job != null &&
        job.id == jobId &&
        !job.modeNeedsReview &&
        job.jobType == JobType.sale &&
        job.workflowKind == JobWorkflowKind.sale &&
        job.intakeKind == JobIntakeKind.none &&
        job.bikeId == null &&
        job.subjectId == null;
  }

  static String _requiredValue(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, 'Must not be empty');
    }
    return normalized;
  }

  static String? _optionalValue(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

class MechanicJobSaleClassificationResult {
  const MechanicJobSaleClassificationResult({
    required this.request,
    required this.confirmation,
    required this.readbackConfirmed,
    required this.rpcReplayed,
    this.job,
    this.readbackError,
  });

  final MechanicJobSaleClassificationRequest request;
  final MechanicJobSaleClassificationConfirmation confirmation;
  final bool readbackConfirmed;
  final bool rpcReplayed;
  final MechanicJob? job;
  final Object? readbackError;

  bool get commandAcknowledged =>
      confirmation == MechanicJobSaleClassificationConfirmation.acknowledged;
  bool get needsRefresh => !readbackConfirmed;
}

class MechanicJobSaleClassificationOutcomeUnknown implements Exception {
  const MechanicJobSaleClassificationOutcomeUnknown({
    required this.request,
    required this.commandError,
    required this.readbackError,
  });

  final MechanicJobSaleClassificationRequest request;
  final Object commandError;
  final Object readbackError;

  @override
  String toString() =>
      'No se pudo confirmar el resultado de la clasificación de venta del '
      'trabajo ${request.jobId}. La misma clave de operación debe reutilizarse.';
}

class MechanicJobSaleClassificationCoordinator {
  const MechanicJobSaleClassificationCoordinator({
    required this.send,
    required this.readback,
    required this.isOutcomeAmbiguous,
  });

  final MechanicJobSaleClassificationSender send;
  final MechanicJobSaleClassificationReadback readback;
  final MechanicJobSaleClassificationAmbiguityTest isOutcomeAmbiguous;

  Future<MechanicJobSaleClassificationResult> execute(
    MechanicJobSaleClassificationRequest request,
  ) async {
    Object? firstCommandError;
    Object? firstResponse;
    try {
      firstResponse = await send(request.toRpcParams());
    } catch (error) {
      if (!isOutcomeAmbiguous(error)) rethrow;
      firstCommandError = error;
    }

    final firstAcknowledgement = _acknowledgement(request, firstResponse);
    if (firstAcknowledgement != null) {
      return _acknowledgedResult(
        request,
        firstAcknowledgement,
        replayAttempted: false,
      );
    }
    firstCommandError ??= const FormatException(
      'Sale classification command returned an invalid response',
    );

    final firstReadback = await _read(request);
    if (request.matches(firstReadback.job)) {
      return MechanicJobSaleClassificationResult(
        request: request,
        confirmation:
            MechanicJobSaleClassificationConfirmation.reconciledFromReadback,
        readbackConfirmed: true,
        rpcReplayed: false,
        job: firstReadback.job,
      );
    }

    // The first request may have committed after its acknowledgement was lost.
    // Replaying the exact payload and operation key is the only safe retry.
    Object? replayError;
    Object? replayResponse;
    try {
      replayResponse = await send(request.toRpcParams());
    } catch (error) {
      replayError = error;
    }

    final replayAcknowledgement = _acknowledgement(request, replayResponse);
    if (replayAcknowledgement != null) {
      return _acknowledgedResult(
        request,
        replayAcknowledgement,
        replayAttempted: true,
      );
    }
    replayError ??= const FormatException(
      'Sale classification replay returned an invalid response',
    );

    final finalReadback = await _read(request);
    if (request.matches(finalReadback.job)) {
      return MechanicJobSaleClassificationResult(
        request: request,
        confirmation:
            MechanicJobSaleClassificationConfirmation.reconciledFromReadback,
        readbackConfirmed: true,
        rpcReplayed: true,
        job: finalReadback.job,
      );
    }

    throw MechanicJobSaleClassificationOutcomeUnknown(
      request: request,
      commandError: _SaleClassificationCommandErrors(
        first: firstCommandError,
        replay: replayError,
      ),
      readbackError: finalReadback.error ??
          firstReadback.error ??
          StateError(
              'The job readback did not confirm the sale classification.'),
    );
  }

  Future<MechanicJobSaleClassificationResult> _acknowledgedResult(
    MechanicJobSaleClassificationRequest request,
    _SaleClassificationAcknowledgement acknowledgement, {
    required bool replayAttempted,
  }) async {
    final readbackResult = await _read(request);
    final readbackConfirmed = request.matches(readbackResult.job);
    return MechanicJobSaleClassificationResult(
      request: request,
      confirmation: MechanicJobSaleClassificationConfirmation.acknowledged,
      readbackConfirmed: readbackConfirmed,
      rpcReplayed: replayAttempted || acknowledgement.replayed,
      job: readbackResult.job,
      readbackError: readbackConfirmed
          ? null
          : readbackResult.error ??
              StateError(
                'The command was acknowledged but readback did not yet match.',
              ),
    );
  }

  Future<_SaleClassificationReadback> _read(
    MechanicJobSaleClassificationRequest request,
  ) async {
    try {
      return _SaleClassificationReadback(job: await readback(request.jobId));
    } catch (error) {
      return _SaleClassificationReadback(error: error);
    }
  }

  _SaleClassificationAcknowledgement? _acknowledgement(
    MechanicJobSaleClassificationRequest request,
    Object? response,
  ) {
    if (response is! Map) return null;
    final result = Map<String, dynamic>.from(response);
    if (result['job_id']?.toString() != request.jobId) return null;
    return _SaleClassificationAcknowledgement(
      replayed: result['replayed'] == true,
    );
  }
}

class _SaleClassificationAcknowledgement {
  const _SaleClassificationAcknowledgement({required this.replayed});

  final bool replayed;
}

class _SaleClassificationReadback {
  const _SaleClassificationReadback({this.job, this.error});

  final MechanicJob? job;
  final Object? error;
}

class _SaleClassificationCommandErrors {
  const _SaleClassificationCommandErrors({
    required this.first,
    required this.replay,
  });

  final Object first;
  final Object replay;

  @override
  String toString() => 'first=$first; replay=$replay';
}
