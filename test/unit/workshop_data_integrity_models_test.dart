import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/shared/models/tax_treatment.dart';

void main() {
  test('mechanic job persists duration and leaves tax mirrors read-only', () {
    final arrival = DateTime(2026, 7, 15, 9, 30);
    final payload = MechanicJob(
      tenantId: 'tenant-1',
      customerId: 'customer-1',
      arrivalDate: arrival,
      estimatedDurationHours: 2.5,
      actualLaborHours: 3.25,
      taxAmount: 1900,
      taxTreatment: TaxTreatment.taxIncluded,
    ).toJson();

    expect(payload['estimated_duration_hours'], 2.5);
    expect(payload['actual_labor_hours'], 3.25);
    expect(payload.containsKey('tax_amount'), isFalse);
    expect(payload.containsKey('tax_treatment'), isFalse);
    expect(DateTime.parse(payload['arrival_date'] as String), arrival.toUtc());
  });

  test('job time evidence is parsed but never written back to the job row', () {
    final job = MechanicJob.fromJson({
      'id': 'job-1',
      'tenant_id': 'tenant-1',
      'customer_id': 'customer-1',
      'arrival_date': '2026-07-01T13:00:00Z',
      'created_at': '2026-07-01T13:00:00Z',
      'updated_at': '2026-07-03T18:00:00Z',
      'time_metrics': {
        'job_id': 'job-1',
        'started_at': '2026-07-01T15:00:00Z',
        'start_source': 'legacy_timeline',
        'completed_at': '2026-07-02T18:00:00Z',
        'completion_source': 'recorded_timestamp',
        'first_delivered_at': '2026-07-03T18:00:00Z',
        'delivery_source': 'legacy_timeline',
        'current_is_completed': true,
        'current_is_delivered': true,
        'reopened_after_delivery': false,
        'quality_flags': ['start_reconstructed_from_timeline'],
      },
    });

    expect(job.timeMetrics?.startedAt, DateTime.parse('2026-07-01T15:00:00Z'));
    expect(job.timeMetrics?.hasReconstructedEvidence, isTrue);
    expect(job.timeMetrics?.qualityFlags,
        contains('start_reconstructed_from_timeline'));
    expect(job.toJson().containsKey('time_metrics'), isFalse);
  });

  test('job archive evidence is readable but only the audited RPC can write it',
      () {
    final job = MechanicJob.fromJson({
      'id': 'job-archived',
      'tenant_id': 'tenant-1',
      'customer_id': 'customer-1',
      'arrival_date': '2026-07-21T13:00:00Z',
      'created_at': '2026-07-21T13:00:00Z',
      'updated_at': '2026-07-21T14:00:00Z',
      'deleted_at': '2026-07-21T14:00:00Z',
      'deleted_by': 'worker-1',
      'archive_reason': 'Trabajo creado para una prueba',
      'archive_operation_id': 'operation-1',
    });

    expect(job.deletedAt, DateTime.parse('2026-07-21T14:00:00Z'));
    expect(job.deletedBy, 'worker-1');
    expect(job.archiveReason, 'Trabajo creado para una prueba');
    expect(job.archiveOperationId, 'operation-1');

    final payload = job.toJson(forUpdate: true);
    expect(payload.containsKey('deleted_at'), isFalse);
    expect(payload.containsKey('archive_reason'), isFalse);
    expect(payload.containsKey('archive_operation_id'), isFalse);
  });

  test('legacy fractional diagnosis wear is normalized to percent', () {
    final drivetrain = DrivetrainDiagnosisSheet.fromJson(const {
      'chain_wear_percent': 0.8,
    });
    final brake = BrakeDiagnosisSheet.fromJson(const {
      'pad_wear_percent': 0.75,
    });

    expect(drivetrain.chainWearPercent, 80);
    expect(brake.padWearPercent, 75);
  });

  test('job item updates can explicitly clear their bike relation', () {
    final payload = MechanicJobItem(
      id: 'item-1',
      tenantId: 'tenant-1',
      jobId: 'job-1',
      productName: 'Servicio general',
    ).toJson();

    expect(payload.containsKey('job_bike_id'), isTrue);
    expect(payload['job_bike_id'], isNull);
  });

  test('structured diagnosis timestamps are persisted as UTC instants', () {
    final confirmedAt = DateTime.parse('2026-07-15T09:23:27-07:00');
    final payload = MechanicJobBike(
      tenantId: 'tenant-1',
      jobId: 'job-1',
      bikeId: 'bike-1',
      diagnosisSheet: const MechanicJobDiagnosisSheet(
        cockpit: CockpitDiagnosisSheet(
          overallStatus: BikeSystemOverallStatus.attention,
        ),
      ),
      diagnosisSheetUpdatedAt: confirmedAt,
    ).toJson();

    final serialized = payload['diagnosis_sheet_updated_at'] as String;
    expect(serialized, endsWith('Z'));
    expect(DateTime.parse(serialized), confirmedAt.toUtc());
  });
}
