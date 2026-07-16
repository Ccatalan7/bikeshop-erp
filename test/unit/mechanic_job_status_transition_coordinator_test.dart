import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/services/mechanic_job_status_transition_coordinator.dart';

void main() {
  MechanicJobStatusTransitionRequest request({
    String operationKey = 'operation-1',
    String statusId = 'status-2',
  }) =>
      MechanicJobStatusTransitionRequest(
        jobId: 'job-1',
        statusId: statusId,
        operationKey: operationKey,
      );

  Map<String, dynamic> receipt({
    String operationKey = 'operation-1',
    String statusId = 'status-2',
    bool changed = true,
    bool nested = false,
  }) {
    final response = <String, dynamic>{
      'job_id': 'job-1',
      'status_id': statusId,
      'status': 'FINALIZADO',
      'changed': changed,
      'job': {
        'id': 'job-1',
        'status_id': statusId,
        'status': 'FINALIZADO',
      },
    };
    return {
      'id': 'event-1',
      'job_id': 'job-1',
      'to_status_id': statusId,
      'operation_key': operationKey,
      'request_snapshot': {
        'job_id': 'job-1',
        'status_id': statusId,
      },
      if (nested) 'response_snapshot': response else ...response,
    };
  }

  test('lost acknowledgement reconciles the exact immutable receipt', () async {
    var sends = 0;
    final coordinator = MechanicJobStatusTransitionCoordinator(
      send: (_) async {
        sends++;
        throw const _AmbiguousNetworkError();
      },
      readback: (operationKey, jobId) async {
        expect(operationKey, 'operation-1');
        expect(jobId, 'job-1');
        return receipt(nested: true);
      },
      isOutcomeAmbiguous: (error) => error is _AmbiguousNetworkError,
    );

    final result = await coordinator.execute(request());

    expect(result.reconciledFromReadback, isTrue);
    expect(result.replayAttempted, isFalse);
    expect(result.authoritativeJobSnapshot['status'], 'FINALIZADO');
    expect(sends, 1);
  });

  test('malformed acknowledgement replays the identical operation key',
      () async {
    final sent = <Map<String, dynamic>>[];
    final coordinator = MechanicJobStatusTransitionCoordinator(
      send: (params) async {
        sent.add(Map<String, dynamic>.from(params));
        return sent.length == 1 ? {'unexpected': true} : receipt();
      },
      readback: (_, __) async => null,
      isOutcomeAmbiguous: (_) => false,
    );

    final result = await coordinator.execute(request());

    expect(result.replayAttempted, isTrue);
    expect(sent, hasLength(2));
    expect(sent[1], sent[0]);
    expect(sent.first['p_operation_key'], 'operation-1');
  });

  test('exact same-state no-op is an acknowledged durable receipt', () async {
    final coordinator = MechanicJobStatusTransitionCoordinator(
      send: (_) async => receipt(changed: false),
      readback: (_, __) async => null,
      isOutcomeAmbiguous: (_) => false,
    );

    final result = await coordinator.execute(request());

    expect(result.changed, isFalse);
    expect(result.replayAttempted, isFalse);
  });

  test('deterministic rejection is never replayed', () async {
    var sends = 0;
    final coordinator = MechanicJobStatusTransitionCoordinator(
      send: (_) async {
        sends++;
        throw const _DeterministicCommandError();
      },
      readback: (_, __) async => null,
      isOutcomeAmbiguous: (error) => error is _AmbiguousNetworkError,
    );

    await expectLater(
      coordinator.execute(request()),
      throwsA(isA<_DeterministicCommandError>()),
    );
    expect(sends, 1);
  });

  test('mismatched exact-key receipt is never replayed', () async {
    var sends = 0;
    final coordinator = MechanicJobStatusTransitionCoordinator(
      send: (_) async {
        sends++;
        throw const _AmbiguousNetworkError();
      },
      readback: (_, __) async =>
          receipt(statusId: 'other-status', nested: true),
      isOutcomeAmbiguous: (error) => error is _AmbiguousNetworkError,
    );

    await expectLater(
      coordinator.execute(request()),
      throwsA(isA<MechanicJobStatusTransitionReceiptMismatch>()),
    );
    expect(sends, 1);
  });

  test('unresolved ambiguous result remains explicitly unknown', () async {
    var sends = 0;
    final coordinator = MechanicJobStatusTransitionCoordinator(
      send: (_) async {
        sends++;
        throw const _AmbiguousNetworkError();
      },
      readback: (_, __) async => null,
      isOutcomeAmbiguous: (error) => error is _AmbiguousNetworkError,
    );

    await expectLater(
      coordinator.execute(request()),
      throwsA(isA<MechanicJobStatusTransitionOutcomeUnknown>()),
    );
    expect(sends, 2);
  });
}

class _AmbiguousNetworkError implements Exception {
  const _AmbiguousNetworkError();
}

class _DeterministicCommandError implements Exception {
  const _DeterministicCommandError();
}
