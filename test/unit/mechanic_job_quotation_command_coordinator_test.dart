import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/services/mechanic_job_quotation_command_coordinator.dart';

void main() {
  MechanicJobQuotationCommandRequest transitionRequest({
    String operationKey = 'operation-1',
    String status = 'approved',
    String? reason,
  }) =>
      MechanicJobQuotationCommandRequest.transition(
        jobId: 'job-1',
        status: status,
        reason: reason,
        operationKey: operationKey,
      );

  MechanicJobQuotationCommandRequest conversionRequest({
    String operationKey = 'operation-1',
    String? reason,
  }) =>
      MechanicJobQuotationCommandRequest.conversion(
        jobId: 'job-1',
        targetJobType: 'service',
        createInvoice: true,
        bikeId: 'bike-1',
        reason: reason,
        operationKey: operationKey,
      );

  Map<String, dynamic> transitionEvent({
    String operationKey = 'operation-1',
    String status = 'approved',
    String? reason,
  }) =>
      {
        'id': 'event-1',
        'job_id': 'job-1',
        'event_type': 'quotation_status_changed',
        'operation_key': operationKey,
        'to_quotation_status': status,
        'metadata': {
          'request': {'status': status, 'reason': reason},
        },
      };

  Map<String, dynamic> conversionEvent({
    String operationKey = 'operation-1',
    String? reason,
  }) =>
      {
        'id': 'event-1',
        'job_id': 'job-1',
        'event_type': 'converted_to_billable',
        'operation_key': operationKey,
        'to_job_type': 'service',
        'to_workflow_kind': 'service',
        'to_intake_kind': 'bike',
        'invoice_id': 'invoice-1',
        'metadata': {
          'request': {
            'target_job_type': 'service',
            'reason': reason,
            'create_invoice': true,
            'bike_id': 'bike-1',
            'subject_id': null,
          },
        },
      };

  Map<String, dynamic> conversionResponse() => {
        'job_id': 'job-1',
        'job_type': 'service',
        'workflow_kind': 'service',
        'intake_kind': 'bike',
        'quotation_status': null,
        'invoice_id': 'invoice-1',
        'event_id': 'event-1',
      };

  test('lost acknowledgement is reconciled from the exact event receipt',
      () async {
    var sends = 0;
    final receipt = transitionEvent(reason: 'Aprobación tardía');
    final coordinator = MechanicJobQuotationCommandCoordinator(
      send: (_, __) async {
        sends++;
        throw const _AmbiguousNetworkError();
      },
      readback: (operationKey, jobId) async {
        expect(operationKey, 'operation-1');
        expect(jobId, 'job-1');
        return receipt;
      },
      readInvariant: (_) async => false,
      isOutcomeAmbiguous: (error) => error is _AmbiguousNetworkError,
    );

    final result = await coordinator.execute(
      transitionRequest(reason: 'Aprobación tardía'),
    );

    expect(result.reconciledFromReadback, isTrue);
    expect(result.replayAttempted, isFalse);
    expect(result.receipt, receipt);
    expect(sends, 1);
  });

  test('malformed acknowledgement replays the identical conversion request',
      () async {
    final sent = <Map<String, dynamic>>[];
    var reads = 0;
    final coordinator = MechanicJobQuotationCommandCoordinator(
      send: (_, params) async {
        sent.add(Map<String, dynamic>.from(params));
        return sent.length == 1 ? {'unexpected': true} : conversionResponse();
      },
      readback: (_, __) async {
        reads++;
        return null;
      },
      readInvariant: (_) async => true,
      isOutcomeAmbiguous: (_) => false,
    );

    final result = await coordinator.execute(conversionRequest());

    expect(result.replayAttempted, isTrue);
    expect(result.invoiceId, 'invoice-1');
    expect(sent, hasLength(2));
    expect(sent[1], sent[0]);
    expect(sent[0]['p_operation_key'], 'operation-1');
    expect(reads, 1);
  });

  test('same-state transition survives a lost no-event acknowledgement',
      () async {
    var sends = 0;
    var eventReads = 0;
    var invariantReads = 0;
    final coordinator = MechanicJobQuotationCommandCoordinator(
      send: (_, __) async {
        sends++;
        // The server may have returned its valid `event_id = null` no-op, but
        // the transport lost the whole response.
        throw const _AmbiguousNetworkError();
      },
      readback: (_, __) async {
        eventReads++;
        return null;
      },
      readInvariant: (request) async {
        invariantReads++;
        return request.status == 'approved';
      },
      isOutcomeAmbiguous: (error) => error is _AmbiguousNetworkError,
    );

    final result = await coordinator.execute(transitionRequest());

    expect(
      result.confirmation,
      MechanicJobQuotationCommandConfirmation.reconciledFromInvariant,
    );
    expect(result.receipt, isNull, reason: 'No receipt may be invented.');
    expect(result.replayAttempted, isFalse);
    expect(sends, 1);
    expect(eventReads, 1);
    expect(invariantReads, 1);
  });

  test('direct same-state transition accepts the explicit null event receipt',
      () async {
    var reads = 0;
    final coordinator = MechanicJobQuotationCommandCoordinator(
      send: (_, __) async => {
        'job_id': 'job-1',
        'job_type': 'quotation',
        'workflow_kind': 'quotation',
        'intake_kind': 'none',
        'quotation_status': 'approved',
        'event_id': null,
      },
      readback: (_, __) async {
        reads++;
        return null;
      },
      readInvariant: (_) async => true,
      isOutcomeAmbiguous: (_) => false,
    );

    final result = await coordinator.execute(transitionRequest());

    expect(
      result.confirmation,
      MechanicJobQuotationCommandConfirmation.acknowledged,
    );
    expect(result.receipt?['event_id'], isNull);
    expect(result.replayAttempted, isFalse);
    expect(reads, 0);
  });

  test('conversion never trusts a row invariant without its exact event',
      () async {
    var sends = 0;
    var invariantReads = 0;
    final coordinator = MechanicJobQuotationCommandCoordinator(
      send: (_, __) async {
        sends++;
        throw const _AmbiguousNetworkError();
      },
      readback: (_, __) async => null,
      readInvariant: (_) async {
        invariantReads++;
        return true;
      },
      isOutcomeAmbiguous: (error) => error is _AmbiguousNetworkError,
    );

    await expectLater(
      coordinator.execute(conversionRequest()),
      throwsA(isA<MechanicJobQuotationCommandOutcomeUnknown>()),
    );
    expect(sends, 2);
    expect(invariantReads, 0);
  });

  test('deterministic initial rejection is never replayed', () async {
    var sends = 0;
    final coordinator = MechanicJobQuotationCommandCoordinator(
      send: (_, __) async {
        sends++;
        throw const _DeterministicCommandError();
      },
      readback: (_, __) async => null,
      readInvariant: (_) async => false,
      isOutcomeAmbiguous: (error) => error is _AmbiguousNetworkError,
    );

    await expectLater(
      coordinator.execute(transitionRequest()),
      throwsA(isA<_DeterministicCommandError>()),
    );
    expect(sends, 1);
  });

  test('deterministic replay rejection remains a rejection after empty reads',
      () async {
    var sends = 0;
    final coordinator = MechanicJobQuotationCommandCoordinator(
      send: (_, __) async {
        sends++;
        if (sends == 1) throw const _AmbiguousNetworkError();
        throw const _DeterministicCommandError();
      },
      readback: (_, __) async => null,
      readInvariant: (_) async => false,
      isOutcomeAmbiguous: (error) => error is _AmbiguousNetworkError,
    );

    await expectLater(
      coordinator.execute(transitionRequest()),
      throwsA(isA<_DeterministicCommandError>()),
    );
    expect(sends, 2);
  });

  test('mismatched exact-key event is a deterministic receipt conflict',
      () async {
    var sends = 0;
    final coordinator = MechanicJobQuotationCommandCoordinator(
      send: (_, __) async {
        sends++;
        throw const _AmbiguousNetworkError();
      },
      readback: (_, __) async => conversionEvent(reason: 'Otro motivo'),
      readInvariant: (_) async => false,
      isOutcomeAmbiguous: (error) => error is _AmbiguousNetworkError,
    );

    await expectLater(
      coordinator.execute(conversionRequest(reason: 'Motivo esperado')),
      throwsA(isA<MechanicJobQuotationCommandReceiptMismatch>()),
    );
    expect(sends, 1, reason: 'A conflicting key must never be replayed.');
  });
}

class _AmbiguousNetworkError implements Exception {
  const _AmbiguousNetworkError();
}

class _DeterministicCommandError implements Exception {
  const _DeterministicCommandError();
}
