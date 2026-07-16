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
      taxAmount: 1900,
      taxTreatment: TaxTreatment.taxIncluded,
    ).toJson();

    expect(payload['estimated_duration_hours'], 2.5);
    expect(payload.containsKey('tax_amount'), isFalse);
    expect(payload.containsKey('tax_treatment'), isFalse);
    expect(DateTime.parse(payload['arrival_date'] as String), arrival.toUtc());
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
