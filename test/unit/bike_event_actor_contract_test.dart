import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';

void main() {
  BikeEvent event({String? createdBy}) => BikeEvent(
        tenantId: 'tenant-1',
        bikeId: 'bike-1',
        jobId: 'job-1',
        eventType: BikeEventType.jobCreated,
        eventCategory: BikeEventCategory.visit,
        title: 'Trabajo creado',
        createdBy: createdBy,
      );

  test('a new bike event leaves actor derivation to the database', () {
    expect(event().toJson(), isNot(contains('created_by')));
  });

  test('an explicitly restored bike-event actor is preserved', () {
    expect(event(createdBy: 'user-1').toJson()['created_by'], 'user-1');
  });
}
