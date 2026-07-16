import '../models/bikeshop_models.dart';

typedef MechanicJobIntakeClassificationSender = Future<Object?> Function(
  Map<String, dynamic> params,
);
typedef MechanicJobIntakeClassificationReadback = Future<MechanicJob?> Function(
    String jobId);
typedef MechanicJobIntakeClassificationAmbiguityTest = bool Function(
  Object error,
);

enum MechanicJobIntakeClassificationConfirmation {
  acknowledged,
  reconciledFromReadback,
}

class MechanicJobIntakeClassificationRequest {
  MechanicJobIntakeClassificationRequest({
    required String jobId,
    required this.intakeKind,
    required String operationKey,
    String? bikeId,
    String? subjectId,
    String? subjectNotes,
    String? reason,
  })  : jobId = _requiredValue(jobId, 'jobId'),
        operationKey = _requiredValue(operationKey, 'operationKey'),
        bikeId = _optionalValue(bikeId),
        subjectId = _optionalValue(subjectId),
        subjectNotes = _optionalValue(subjectNotes),
        reason = _optionalValue(reason) {
    if (intakeKind == JobIntakeKind.unspecified) {
      throw ArgumentError.value(
        intakeKind,
        'intakeKind',
        'Classification must resolve to bike or component',
      );
    }
    if (intakeKind == JobIntakeKind.bike && this.bikeId == null) {
      throw ArgumentError.value(
        bikeId,
        'bikeId',
        'A bicycle intake requires a bike',
      );
    }
    if (intakeKind == JobIntakeKind.component &&
        this.subjectId == null &&
        this.subjectNotes == null) {
      throw ArgumentError.value(
        subjectNotes,
        'subjectNotes',
        'A component intake requires a subject or clear description',
      );
    }
  }

  final String jobId;
  final JobIntakeKind intakeKind;
  final String operationKey;
  final String? bikeId;
  final String? subjectId;
  final String? subjectNotes;
  final String? reason;

  Map<String, dynamic> toRpcParams() => {
        'p_job_id': jobId,
        'p_intake_kind': intakeKind.dbValue,
        'p_bike_id': intakeKind == JobIntakeKind.bike ? bikeId : null,
        'p_subject_id':
            intakeKind == JobIntakeKind.component ? subjectId : null,
        'p_subject_notes':
            intakeKind == JobIntakeKind.component ? subjectNotes : null,
        'p_reason': reason,
        'p_operation_key': operationKey,
      };

  bool matches(MechanicJob? job) {
    if (job == null ||
        job.id != jobId ||
        job.modeNeedsReview ||
        job.intakeKind != intakeKind) {
      return false;
    }

    if (intakeKind == JobIntakeKind.bike) {
      return job.bikeId == bikeId && job.subjectId == null;
    }

    if (job.bikeId != null) return false;
    if (subjectId != null) return job.subjectId == subjectId;
    return job.subjectId == null &&
        _optionalValue(job.subjectNotes) == subjectNotes;
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

class MechanicJobIntakeClassificationResult {
  const MechanicJobIntakeClassificationResult({
    required this.request,
    required this.confirmation,
    required this.readbackConfirmed,
    required this.rpcReplayed,
    this.job,
    this.readbackError,
  });

  final MechanicJobIntakeClassificationRequest request;
  final MechanicJobIntakeClassificationConfirmation confirmation;
  final bool readbackConfirmed;
  final bool rpcReplayed;
  final MechanicJob? job;
  final Object? readbackError;

  bool get commandAcknowledged =>
      confirmation == MechanicJobIntakeClassificationConfirmation.acknowledged;
  bool get needsRefresh => !readbackConfirmed;
}

class MechanicJobIntakeClassificationOutcomeUnknown implements Exception {
  const MechanicJobIntakeClassificationOutcomeUnknown({
    required this.request,
    required this.commandError,
    required this.readbackError,
  });

  final MechanicJobIntakeClassificationRequest request;
  final Object commandError;
  final Object readbackError;

  @override
  String toString() =>
      'No se pudo confirmar el resultado de la clasificación del trabajo '
      '${request.jobId}. La misma clave de operación debe reutilizarse.';
}

class MechanicJobIntakeClassificationCoordinator {
  const MechanicJobIntakeClassificationCoordinator({
    required this.send,
    required this.readback,
    required this.isOutcomeAmbiguous,
  });

  final MechanicJobIntakeClassificationSender send;
  final MechanicJobIntakeClassificationReadback readback;
  final MechanicJobIntakeClassificationAmbiguityTest isOutcomeAmbiguous;

  Future<MechanicJobIntakeClassificationResult> execute(
    MechanicJobIntakeClassificationRequest request,
  ) async {
    Object? firstCommandError;
    Object? firstResponse;
    try {
      firstResponse = await send(request.toRpcParams());
    } catch (error) {
      if (!isOutcomeAmbiguous(error)) rethrow;
      firstCommandError = error;
    }

    final firstAcknowledgement = _acknowledgement(
      request,
      firstResponse,
    );
    if (firstAcknowledgement != null) {
      return _acknowledgedResult(
        request,
        firstAcknowledgement,
        replayAttempted: false,
      );
    }
    firstCommandError ??= const FormatException(
      'Intake classification command returned an invalid response',
    );

    final firstReadback = await _read(request);
    if (request.matches(firstReadback.job)) {
      return MechanicJobIntakeClassificationResult(
        request: request,
        confirmation:
            MechanicJobIntakeClassificationConfirmation.reconciledFromReadback,
        readbackConfirmed: true,
        rpcReplayed: false,
        job: firstReadback.job,
      );
    }

    // The first request may have committed after its response was lost. A
    // replay with the exact same operation key and payload is the only safe
    // retry; a fresh key would create a second semantic attempt.
    Object? replayError;
    Object? replayResponse;
    try {
      replayResponse = await send(request.toRpcParams());
    } catch (error) {
      replayError = error;
    }

    final replayAcknowledgement = _acknowledgement(
      request,
      replayResponse,
    );
    if (replayAcknowledgement != null) {
      return _acknowledgedResult(
        request,
        replayAcknowledgement,
        replayAttempted: true,
      );
    }
    replayError ??= const FormatException(
      'Intake classification replay returned an invalid response',
    );

    final finalReadback = await _read(request);
    if (request.matches(finalReadback.job)) {
      return MechanicJobIntakeClassificationResult(
        request: request,
        confirmation:
            MechanicJobIntakeClassificationConfirmation.reconciledFromReadback,
        readbackConfirmed: true,
        rpcReplayed: true,
        job: finalReadback.job,
      );
    }

    throw MechanicJobIntakeClassificationOutcomeUnknown(
      request: request,
      commandError: _ClassificationCommandErrors(
        first: firstCommandError,
        replay: replayError,
      ),
      readbackError: finalReadback.error ??
          firstReadback.error ??
          StateError('The job readback did not confirm the classification.'),
    );
  }

  Future<MechanicJobIntakeClassificationResult> _acknowledgedResult(
    MechanicJobIntakeClassificationRequest request,
    _ClassificationAcknowledgement acknowledgement, {
    required bool replayAttempted,
  }) async {
    final readbackResult = await _read(request);
    final readbackConfirmed = request.matches(readbackResult.job);
    return MechanicJobIntakeClassificationResult(
      request: request,
      confirmation: MechanicJobIntakeClassificationConfirmation.acknowledged,
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

  Future<_ClassificationReadback> _read(
    MechanicJobIntakeClassificationRequest request,
  ) async {
    try {
      return _ClassificationReadback(job: await readback(request.jobId));
    } catch (error) {
      return _ClassificationReadback(error: error);
    }
  }

  _ClassificationAcknowledgement? _acknowledgement(
    MechanicJobIntakeClassificationRequest request,
    Object? response,
  ) {
    if (response is! Map) return null;
    final result = Map<String, dynamic>.from(response);
    if (result['job_id']?.toString() != request.jobId) return null;
    return _ClassificationAcknowledgement(
      replayed: result['replayed'] == true,
    );
  }
}

class _ClassificationAcknowledgement {
  const _ClassificationAcknowledgement({required this.replayed});

  final bool replayed;
}

class _ClassificationReadback {
  const _ClassificationReadback({this.job, this.error});

  final MechanicJob? job;
  final Object? error;
}

class _ClassificationCommandErrors {
  const _ClassificationCommandErrors({
    required this.first,
    required this.replay,
  });

  final Object first;
  final Object replay;

  @override
  String toString() => 'first=$first; replay=$replay';
}
