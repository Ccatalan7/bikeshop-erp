import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/crm/models/crm_models.dart';
import 'package:vinabike_erp/modules/sales/models/sales_models.dart';
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
    expect(
      DateTime.parse(payload['arrival_date'] as String),
      arrival.toUtc(),
    );
  });

  test('legacy fractional diagnosis wear is normalized to percent', () {
    final drivetrain = DrivetrainDiagnosisSheet.fromJson(
      const {'chain_wear_percent': 0.8},
    );
    final brake = BrakeDiagnosisSheet.fromJson(
      const {'pad_wear_percent': 0.75},
    );

    expect(drivetrain.chainWearPercent, 80);
    expect(brake.padWearPercent, 75);
  });

  test('new loyalty rows omit their database-generated id', () {
    const loyalty = Loyalty(
      tenantId: 'tenant-1',
      customerId: 'customer-1',
    );

    expect(loyalty.toJson().containsKey('id'), isFalse);
  });

  test('empty invoice product ids are treated as ad-hoc lines', () {
    final item = InvoiceItem.fromJson(const {
      'product_id': '',
      'description': 'Diagnostico general',
      'quantity': 1,
      'unit_price': 1000,
    });

    expect(item.productId, isNull);
    expect(item.isCatalogProduct, isFalse);
  });

  test('invoice lines round-trip workshop service metadata', () {
    final original = InvoiceItem.fromJson(const {
      'id': 'item-1',
      'product_id': 'service-1',
      'product_name': 'Ajuste de dirección',
      'item_type': 'service',
      'unit_price': 3000,
      'quantity': 1,
      'service_configuration_data': {
        '_notes': 'Verificar torque después del ajuste',
      },
      'system_key': 'cockpit',
      'component_slot_key': 'headset',
      'location_key': 'none',
      'intervention_type': 'adjusted',
      'creates_lifecycle': true,
    });

    final payload = original.toFirestoreMap();
    expect(payload['item_type'], 'service');
    expect(payload['service_configuration_data'], {
      '_notes': 'Verificar torque después del ajuste',
    });
    expect(payload['system_key'], 'cockpit');
    expect(payload['component_slot_key'], 'headset');
    expect(payload['location_key'], 'none');
    expect(payload['intervention_type'], 'adjusted');
    expect(payload['creates_lifecycle'], isTrue);
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
