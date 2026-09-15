import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';

void main() {
  test('labels follow the member resolver tenant override and stable id order',
      () {
    final names = SpecEngineService.decodeFamilyLabels([
      {'id': '2', 'tenant_id': null, 'key': 'light', 'name': 'Otra luz'},
      {'id': '1', 'tenant_id': null, 'key': 'light', 'name': 'Luz'},
      {
        'id': '3',
        'tenant_id': null,
        'key': 'accessory_mount',
        'name': 'Soporte'
      },
      {
        'id': '4',
        'tenant_id': 'tenant-a',
        'key': 'accessory_mount',
        'name': 'Soporte del local'
      },
    ], tenantId: 'tenant-a');
    expect(names, {'light': 'Luz', 'accessory_mount': 'Soporte del local'});
    expect(() => names['light'] = 'Cambiar', throwsUnsupportedError);
  });

  test('a foreign tenant or missing name fails instead of exposing a key', () {
    for (final row in [
      {'id': '1', 'tenant_id': 'tenant-b', 'key': 'light', 'name': 'Privado'},
      {'id': '1', 'tenant_id': null, 'key': 'light', 'name': ' '},
    ]) {
      expect(
          () =>
              SpecEngineService.decodeFamilyLabels([row], tenantId: 'tenant-a'),
          throwsFormatException);
    }
  });
}
