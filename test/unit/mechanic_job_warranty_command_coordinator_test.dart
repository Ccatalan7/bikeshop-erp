import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/services/mechanic_job_warranty_command_coordinator.dart';

void main() {
  Map<String, dynamic> decisionEvent({
    String operationKey = 'operation-1',
    String outcome = 'covered',
    String? reason,
  }) =>
      {
        'warranty_job_id': 'warranty-1',
        'source_job_id': 'source-1',
        'event_type': 'decision',
        'outcome': outcome,
        'reason': reason,
        'operation_key': operationKey,
      };

  test('lost acknowledgement is reconciled from the exact event receipt',
      () async {
    var sends = 0;
    final receipt = decisionEvent(reason: 'Excepción técnica');
    final coordinator = MechanicJobWarrantyCommandCoordinator(
      send: (_, __) async {
        sends++;
        throw const _AmbiguousNetworkError();
      },
      readback: (_) async => receipt,
      isOutcomeAmbiguous: (error) => error is _AmbiguousNetworkError,
    );
    final request = MechanicJobWarrantyCommandRequest.decision(
      warrantyJobId: 'warranty-1',
      outcome: 'covered',
      reason: 'Excepción técnica',
      operationKey: 'operation-1',
    );

    final result = await coordinator.execute(request);

    expect(result.reconciledFromReadback, isTrue);
    expect(result.replayAttempted, isFalse);
    expect(result.event, receipt);
    expect(sends, 1);
  });

  test('replay reuses the identical semantic request and operation key',
      () async {
    final sentParams = <Map<String, dynamic>>[];
    var reads = 0;
    final coordinator = MechanicJobWarrantyCommandCoordinator(
      send: (_, params) async {
        sentParams.add(Map<String, dynamic>.from(params));
        if (sentParams.length == 1) {
          throw const _AmbiguousNetworkError();
        }
        return decisionEvent();
      },
      readback: (_) async {
        reads++;
        return null;
      },
      isOutcomeAmbiguous: (error) => error is _AmbiguousNetworkError,
    );
    final request = MechanicJobWarrantyCommandRequest.decision(
      warrantyJobId: 'warranty-1',
      outcome: 'covered',
      operationKey: 'operation-1',
    );

    final result = await coordinator.execute(request);

    expect(result.replayAttempted, isTrue);
    expect(sentParams, hasLength(2));
    expect(sentParams[1], sentParams[0]);
    expect(sentParams[0]['p_operation_key'], 'operation-1');
    expect(reads, 1);
  });

  test('deterministic rejection is never replayed', () async {
    var sends = 0;
    final coordinator = MechanicJobWarrantyCommandCoordinator(
      send: (_, __) async {
        sends++;
        throw const _DeterministicCommandError();
      },
      readback: (_) async => null,
      isOutcomeAmbiguous: (error) => error is _AmbiguousNetworkError,
    );

    await expectLater(
      coordinator.execute(
        MechanicJobWarrantyCommandRequest.registration(
          warrantyJobId: 'warranty-1',
          sourceJobId: 'source-1',
          operationKey: 'operation-1',
        ),
      ),
      throwsA(isA<_DeterministicCommandError>()),
    );
    expect(sends, 1);
  });

  test('registration accepts exact pre-existing source invariant replay',
      () async {
    var sends = 0;
    final coordinator = MechanicJobWarrantyCommandCoordinator(
      send: (_, __) async {
        sends++;
        return {
          'warranty_job_id': 'warranty-1',
          'source_job_id': 'source-1',
          'event_type': 'registration',
          'operation_key': 'older-registration-key',
          'replay': true,
        };
      },
      readback: (_) async => null,
      isOutcomeAmbiguous: (_) => false,
    );

    final result = await coordinator.execute(
      MechanicJobWarrantyCommandRequest.registration(
        warrantyJobId: 'warranty-1',
        sourceJobId: 'source-1',
        operationKey: 'new-recovery-key',
      ),
    );

    expect(result.confirmation,
        MechanicJobWarrantyCommandConfirmation.acknowledged);
    expect(result.event['operation_key'], 'older-registration-key');
    expect(sends, 1);
  });

  test('registration never accepts a replay for a different source', () async {
    var sends = 0;
    final coordinator = MechanicJobWarrantyCommandCoordinator(
      send: (_, __) async {
        sends++;
        return {
          'warranty_job_id': 'warranty-1',
          'source_job_id': 'different-source',
          'event_type': 'registration',
          'operation_key': 'older-registration-key',
          'replay': true,
        };
      },
      readback: (_) async => null,
      isOutcomeAmbiguous: (_) => false,
    );

    await expectLater(
      coordinator.execute(
        MechanicJobWarrantyCommandRequest.registration(
          warrantyJobId: 'warranty-1',
          sourceJobId: 'source-1',
          operationKey: 'new-recovery-key',
        ),
      ),
      throwsA(isA<MechanicJobWarrantyCommandOutcomeUnknown>()),
    );
    expect(sends, 2);
  });

  test('mismatched receipt remains explicitly outcome unknown', () async {
    var sends = 0;
    final coordinator = MechanicJobWarrantyCommandCoordinator(
      send: (_, __) async {
        sends++;
        return decisionEvent(outcome: 'not_covered');
      },
      readback: (_) async => decisionEvent(outcome: 'not_covered'),
      isOutcomeAmbiguous: (_) => true,
    );

    await expectLater(
      coordinator.execute(
        MechanicJobWarrantyCommandRequest.decision(
          warrantyJobId: 'warranty-1',
          outcome: 'covered',
          operationKey: 'operation-1',
        ),
      ),
      throwsA(isA<MechanicJobWarrantyCommandOutcomeUnknown>()),
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
