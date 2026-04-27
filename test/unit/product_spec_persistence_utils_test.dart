import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/utils/product_spec_persistence_utils.dart';

void main() {
  test('drops broad ecosystem text from exact drivetrain platform field', () {
    expect(
      sanitizeProductSpecValueForPersistence(
        specKey: 'drivetrain_platform',
        value: 'Shimano',
      ),
      isNull,
    );
    expect(
      sanitizeProductSpecValueForPersistence(
        specKey: 'drivetrain_platform',
        value: 'Compatible SRAM',
      ),
      isNull,
    );
  });

  test('keeps exact drivetrain platform values', () {
    expect(
      sanitizeProductSpecValueForPersistence(
        specKey: 'drivetrain_platform',
        value: 'Shimano Hyperglide+',
      ),
      'Shimano Hyperglide+',
    );
  });

  test('drops broad ecosystem text from exact shift actuation field', () {
    expect(
      sanitizeProductSpecValueForPersistence(
        specKey: 'shift_actuation_family',
        value: 'Shimano',
      ),
      isNull,
    );
    expect(
      sanitizeProductSpecValueForPersistence(
        specKey: 'shift_actuation_family',
        value: 'Ecosistema SRAM',
      ),
      isNull,
    );
  });

  test('keeps exact shift actuation values', () {
    expect(
      sanitizeProductSpecValueForPersistence(
        specKey: 'shift_actuation_family',
        value: 'Shimano Dynasys 11/12v',
      ),
      'Shimano Dynasys 11/12v',
    );
  });

  test('does not touch broad fields that are meant to stay broad', () {
    expect(
      sanitizeProductSpecValueForPersistence(
        specKey: 'drivetrain_primary_ecosystem',
        value: 'Ecosistema Shimano',
      ),
      'Ecosistema Shimano',
    );
  });
}
