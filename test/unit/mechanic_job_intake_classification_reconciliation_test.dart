import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/mechanic_job_intake_classification_coordinator.dart';

void main() {
  const operationKey = '11111111-1111-4111-8111-111111111111';

  MechanicJob bikeJob({
    bool modeNeedsReview = false,
    JobIntakeKind intakeKind = JobIntakeKind.bike,
    String? bikeId = 'bike-1',
  }) {
    return MechanicJob(
      id: 'job-1',
      tenantId: 'tenant-1',
      customerId: 'customer-1',
      bikeId: bikeId,
      jobType: JobType.service,
      workflowKind: JobWorkflowKind.service,
      intakeKind: intakeKind,
      modeNeedsReview: modeNeedsReview,
    );
  }

  final request = MechanicJobIntakeClassificationRequest(
    jobId: 'job-1',
    intakeKind: JobIntakeKind.bike,
    bikeId: 'bike-1',
    operationKey: operationKey,
  );

  test('acknowledgement remains success when the follow-up GET is uncertain',
      () async {
    final coordinator = MechanicJobIntakeClassificationCoordinator(
      send: (_) async => {
        'job_id': 'job-1',
        'replayed': false,
      },
      readback: (_) async => throw const _NetworkError('GET lost'),
      isOutcomeAmbiguous: (error) => error is _NetworkError,
    );

    final result = await coordinator.execute(request);

    expect(result.commandAcknowledged, isTrue);
    expect(result.readbackConfirmed, isFalse);
    expect(result.needsRefresh, isTrue);
    expect(result.readbackError, isA<_NetworkError>());
  });

  test('lost acknowledgement is reconciled from matching job readback',
      () async {
    var sends = 0;
    final coordinator = MechanicJobIntakeClassificationCoordinator(
      send: (_) async {
        sends++;
        throw const _NetworkError('ACK lost');
      },
      readback: (_) async => bikeJob(),
      isOutcomeAmbiguous: (error) => error is _NetworkError,
    );

    final result = await coordinator.execute(request);

    expect(sends, 1);
    expect(
      result.confirmation,
      MechanicJobIntakeClassificationConfirmation.reconciledFromReadback,
    );
    expect(result.readbackConfirmed, isTrue);
    expect(result.job?.bikeId, 'bike-1');
  });

  test('uncertain command replays the identical semantic request and key',
      () async {
    final sentParams = <Map<String, dynamic>>[];
    var reads = 0;
    final coordinator = MechanicJobIntakeClassificationCoordinator(
      send: (params) async {
        sentParams.add(Map<String, dynamic>.from(params));
        if (sentParams.length == 1) {
          throw const _NetworkError('ACK lost');
        }
        return {
          'job_id': 'job-1',
          'replayed': true,
        };
      },
      readback: (_) async {
        reads++;
        return reads == 1
            ? bikeJob(
                modeNeedsReview: true,
                intakeKind: JobIntakeKind.unspecified,
                bikeId: null,
              )
            : bikeJob();
      },
      isOutcomeAmbiguous: (error) => error is _NetworkError,
    );

    final result = await coordinator.execute(request);

    expect(sentParams, hasLength(2));
    expect(sentParams[1], sentParams[0]);
    expect(sentParams[0]['p_operation_key'], operationKey);
    expect(result.commandAcknowledged, isTrue);
    expect(result.rpcReplayed, isTrue);
    expect(result.readbackConfirmed, isTrue);
  });

  test('double ambiguity exposes outcome unknown with the same operation key',
      () async {
    var sends = 0;
    var reads = 0;
    final coordinator = MechanicJobIntakeClassificationCoordinator(
      send: (_) async {
        sends++;
        throw const _NetworkError('offline');
      },
      readback: (_) async {
        reads++;
        throw const _NetworkError('readback offline');
      },
      isOutcomeAmbiguous: (error) => error is _NetworkError,
    );

    await expectLater(
      coordinator.execute(request),
      throwsA(
        isA<MechanicJobIntakeClassificationOutcomeUnknown>().having(
          (error) => error.request.operationKey,
          'operation key',
          operationKey,
        ),
      ),
    );
    expect(sends, 2);
    expect(reads, 2);
  });

  test('definitive first rejection is not retried as an uncertain commit',
      () async {
    const rejection = _ServerRejection('invalid tenant graph');
    var reads = 0;
    final coordinator = MechanicJobIntakeClassificationCoordinator(
      send: (_) async => throw rejection,
      readback: (_) async {
        reads++;
        return null;
      },
      isOutcomeAmbiguous: (error) => error is _NetworkError,
    );

    await expectLater(coordinator.execute(request), throwsA(same(rejection)));
    expect(reads, 0);
  });

  test('manual component reconciliation requires the exact saved description',
      () {
    final componentRequest = MechanicJobIntakeClassificationRequest(
      jobId: 'job-1',
      intakeKind: JobIntakeKind.component,
      subjectNotes: 'Rueda trasera 29',
      operationKey: operationKey,
    );
    final componentJob = MechanicJob(
      id: 'job-1',
      tenantId: 'tenant-1',
      customerId: 'customer-1',
      jobType: JobType.itemService,
      workflowKind: JobWorkflowKind.service,
      intakeKind: JobIntakeKind.component,
      modeNeedsReview: false,
      subjectNotes: 'Rueda trasera 29',
    );

    expect(componentRequest.matches(componentJob), isTrue);
    expect(
      componentRequest.matches(
        componentJob.copyWith(subjectNotes: 'Otra rueda'),
      ),
      isFalse,
    );
  });
}

class _NetworkError implements Exception {
  const _NetworkError(this.message);

  final String message;

  @override
  String toString() => message;
}

class _ServerRejection implements Exception {
  const _ServerRejection(this.message);

  final String message;

  @override
  String toString() => message;
}
