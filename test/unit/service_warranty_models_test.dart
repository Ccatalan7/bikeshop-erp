import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';

void main() {
  test('service warranty projection parses immutable delivery window', () {
    final projection = MechanicJobServiceWarranty.fromJson({
      'job_id': 'job-1',
      'job_number': 'PG-00100',
      'customer_id': 'customer-1',
      'bike_id': 'bike-1',
      'job_type': 'service',
      'first_delivered_at': '2026-07-15T12:00:00Z',
      'last_delivered_at': '2026-07-16T12:00:00Z',
      'delivery_count': 2,
      'has_ambiguous_legacy_history': true,
      'warranty_event_id': 'event-1',
      'warranty_started_at': '2026-07-15T12:00:00Z',
      'warranty_expires_at': '2026-07-29T12:00:00Z',
      'warranty_days_snapshot': 14,
      'warranty_state': 'active',
      'warranty_days_remaining': 12,
    });

    expect(projection.jobId, 'job-1');
    expect(projection.deliveryCount, 2);
    expect(projection.hasAmbiguousLegacyHistory, isTrue);
    expect(projection.state, ServiceWarrantyState.active);
    expect(projection.daysRemaining, 12);
    expect(
      projection.warrantyExpiresAt?.toUtc(),
      DateTime.utc(2026, 7, 29, 12),
    );
  });

  test(
    'warranty claim projection keeps source eligibility and decision reason',
    () {
      final claim = MechanicJobWarrantyClaim.fromJson({
        'warranty_job_id': 'warranty-job',
        'warranty_job_number': 'PG-00101',
        'source_job_id': 'source-job',
        'source_job_number': 'PG-00100',
        'source_subject_name': 'Rueda trasera',
        'eligibility': 'outside_window',
        'warranty_expires_at_snapshot': '2026-07-01T12:00:00Z',
        'outcome': 'covered',
        'reason': 'Excepción autorizada por diagnóstico técnico',
        'registered_at': '2026-07-15T12:00:00Z',
        'decided_at': '2026-07-15T12:05:00Z',
        'decided_by': 'employee-1',
      });

      expect(claim.sourceJobId, 'source-job');
      expect(claim.sourceSubjectName, 'Rueda trasera');
      expect(claim.eligibility, WarrantyEligibility.outsideWindow);
      expect(claim.outcome, WarrantyOutcome.covered);
      expect(claim.reason, contains('Excepción'));
    },
  );

  test(
    'derived service warranty is never written to mechanic_jobs payload',
    () {
      const warranty = MechanicJobServiceWarranty(
        jobId: 'job-1',
        customerId: 'customer-1',
        jobType: JobType.service,
        state: ServiceWarrantyState.active,
        daysRemaining: 8,
      );
      final job = MechanicJob(
        tenantId: 'tenant-1',
        customerId: 'customer-1',
      ).copyWith(serviceWarranty: warranty);

      expect(job.serviceWarranty, same(warranty));
      expect(
        job.toJson(forUpdate: true).containsKey('service_warranty'),
        isFalse,
      );
      expect(
        job.toJson(forUpdate: true).containsKey('warranty_expires_at'),
        isFalse,
      );
    },
  );

  test('warranty source object replaces bike with component exactly', () {
    const bikeSource = MechanicJobServiceWarranty(
      jobId: 'source-bike',
      customerId: 'customer-1',
      bikeId: 'bike-1',
      jobType: JobType.service,
      intakeKind: JobIntakeKind.bike,
    );
    const componentSource = MechanicJobServiceWarranty(
      jobId: 'source-component',
      customerId: 'customer-1',
      subjectId: 'subject-wheel',
      jobType: JobType.itemService,
      intakeKind: JobIntakeKind.component,
    );

    var selection = bikeSource.physicalObject;
    expect(selection.isBike, isTrue);
    expect(
      selection.matchesSelection(
        selectedBikeIds: const ['bike-1'],
      ),
      isTrue,
    );

    selection = componentSource.physicalObject;
    expect(selection.bikeId, isNull);
    expect(selection.subjectId, 'subject-wheel');
    expect(
      selection.matchesSelection(
        selectedBikeIds: const [],
        selectedSubjectId: 'subject-wheel',
      ),
      isTrue,
    );
    expect(
      selection.matchesSelection(
        selectedBikeIds: const ['bike-1'],
        selectedSubjectId: 'subject-wheel',
      ),
      isFalse,
      reason: 'a previous bicycle must never survive a component source',
    );
  });

  test('warranty source object follows canonical intake over provenance ids',
      () {
    const missingSource = MechanicJobServiceWarranty(
      jobId: 'source-missing',
      customerId: 'customer-1',
      jobType: JobType.service,
    );
    const mixedSource = MechanicJobServiceWarranty(
      jobId: 'source-mixed',
      customerId: 'customer-1',
      bikeId: 'bike-1',
      subjectId: 'subject-wheel',
      jobType: JobType.itemService,
      intakeKind: JobIntakeKind.component,
    );

    expect(missingSource.physicalObject.isValid, isFalse);
    expect(mixedSource.physicalObject.isComponent, isTrue);
    expect(mixedSource.physicalObject.bikeId, isNull);
    expect(mixedSource.physicalObject.subjectId, 'subject-wheel');
    expect(
      mixedSource.physicalObject.matchesSelection(
        selectedBikeIds: const [],
        selectedSubjectId: 'subject-wheel',
      ),
      isTrue,
    );
  });
}
