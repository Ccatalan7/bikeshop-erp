import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/config/drivetrain_canonical_data.dart';

void main() {
  test('infers single speed chain fields from 1/8 width', () {
    final result = inferDrivetrainProductSpecValues(
      technicalFamily: 'chain',
      currentValues: const <String, dynamic>{
        'chain_width_family': '1/8',
      },
    );

    expect(result.derivedValues['chain_speeds'], const ['1']);
    expect(
      result.derivedValues['drivetrain_mode'],
      kDrivetrainModeSingleSpeedBmxIgh,
    );
    expect(
      result.derivedValues['drivetrain_primary_ecosystem'],
      kDrivetrainCompatibilityFamilySingleSpeed,
    );
    expect(
      result.derivedValues['chain_profile_family'],
      const ['Single speed / BMX'],
    );
    expect(
      result.derivedValues.containsKey('drivetrain_platform'),
      isFalse,
    );
    expect(
      result.guidanceByField['drivetrain_mode'],
      contains('single speed / BMX / IGH'),
    );
    expect(
      result.guidanceByField['drivetrain_primary_ecosystem'],
      contains('single speed / BMX / IGH'),
    );
  });

  test('does not suggest primary ecosystem from commercial brand text', () {
    final result = inferDrivetrainProductSpecValues(
      technicalFamily: 'chain',
      currentValues: const <String, dynamic>{
        'chain_width_family': '11/128',
      },
    );

    expect(result.derivedValues.containsKey('chain_speeds'), isFalse);
    expect(result.derivedValues.containsKey('drivetrain_primary_ecosystem'),
        isFalse);
    expect(result.derivedValues.containsKey('drivetrain_platform'), isFalse);
    expect(
      result.guidanceByField['chain_speeds'],
      contains('11/128 no basta por si solo'),
    );
    expect(result.guidanceByField['drivetrain_primary_ecosystem'], isNull);
  });

  test('infers 10v narrow chain from 11/128 plus outer width', () {
    final result = inferDrivetrainProductSpecValues(
      technicalFamily: 'chain',
      currentValues: const <String, dynamic>{
        'chain_width_family': '11/128',
        'chain_outer_width_mm': 5.88,
      },
    );

    expect(result.derivedValues['chain_speeds'], const ['10']);
    expect(result.derivedValues.containsKey('chain_profile_family'), isFalse);
    expect(
      result.guidanceByField['chain_profile_family'],
      contains('no basta para asumir un perfil universal'),
    );
  });

  test('legacy KMC compatibility family still unlocks KMC chain profile hint',
      () {
    final result = inferDrivetrainProductSpecValues(
      technicalFamily: 'chain',
      currentValues: const <String, dynamic>{
        'chain_width_family': '3/32',
        'drivetrain_compatibility_family': [
          kDrivetrainCompatibilityFamilyKmc,
        ],
      },
    );

    expect(result.derivedValues['chain_speeds'], const ['5', '6', '7', '8']);
    expect(
      result.derivedValues['chain_profile_family'],
      const ['Universal 5-8v', 'KMC compatible'],
    );
  });

  test('does not auto-complete narrow 12v chain profile without platform', () {
    final result = inferDrivetrainProductSpecValues(
      technicalFamily: 'chain',
      currentValues: const <String, dynamic>{
        'chain_width_family': '11/128',
        'chain_speeds': ['12'],
      },
    );

    expect(result.derivedValues.containsKey('chain_profile_family'), isFalse);
    expect(result.derivedValues.containsKey('drivetrain_platform'), isFalse);
    expect(
      result.guidanceByField['chain_profile_family'],
      contains('12/13v angosta sin una plataforma explicita'),
    );
  });

  test('suggests compatibility family from explicit drivetrain platform', () {
    final result = inferDrivetrainProductSpecValues(
      technicalFamily: 'chain_link',
      currentValues: const <String, dynamic>{
        'drivetrain_platform': 'Shimano Hyperglide+',
      },
    );

    expect(
      result.derivedValues['chain_profile_family'],
      const ['Shimano HG+'],
    );
    expect(
      result.derivedValues['drivetrain_mode'],
      kDrivetrainModeDerailleur,
    );
    expect(
      result.derivedValues.containsKey('drivetrain_primary_ecosystem'),
      isFalse,
    );
    expect(result.derivedValues.containsKey('drivetrain_platform'), isFalse);
    expect(
      result.guidanceByField['chain_profile_family'],
      contains('Shimano HG+'),
    );
    expect(
      result.guidanceByField['drivetrain_primary_ecosystem'],
      contains('Ecosistema Shimano'),
    );
  });

  test('does not infer drivetrain platform back from chain profile', () {
    final result = inferDrivetrainProductSpecValues(
      technicalFamily: 'chain',
      currentValues: const <String, dynamic>{
        'chain_profile_family': ['Shimano HG+'],
      },
    );

    expect(result.derivedValues.containsKey('drivetrain_platform'), isFalse);
    expect(
      result.guidanceByField['drivetrain_primary_ecosystem'],
      contains('Ecosistema Shimano'),
    );
  });

  test(
      'does not treat broad ecosystem text stranded in drivetrain platform as exact truth',
      () {
    final result = inferDrivetrainProductSpecValues(
      technicalFamily: 'chain',
      currentValues: const <String, dynamic>{
        'drivetrain_platform': 'Shimano',
      },
    );

    expect(result.derivedValues.containsKey('drivetrain_mode'), isFalse);
    expect(result.derivedValues.containsKey('chain_profile_family'), isFalse);
    expect(result.derivedValues.containsKey('drivetrain_primary_ecosystem'),
        isFalse);
  });

  test('does not promote plain brand text stranded in shift actuation field',
      () {
    final result = inferDrivetrainProductSpecValues(
      technicalFamily: 'chain',
      currentValues: const <String, dynamic>{
        'shift_actuation_family': 'Shimano',
      },
    );

    expect(result.derivedValues.containsKey('drivetrain_mode'), isFalse);
    expect(result.derivedValues.containsKey('drivetrain_primary_ecosystem'),
        isFalse);
  });

  test('still derives ecosystem and mode from explicit actuation-family truth',
      () {
    final result = inferDrivetrainProductSpecValues(
      technicalFamily: 'chain',
      currentValues: const <String, dynamic>{
        'shift_actuation_family': 'Shimano Dynasys 11/12',
      },
    );

    expect(
      result.derivedValues['drivetrain_mode'],
      kDrivetrainModeDerailleur,
    );
    expect(
      result.guidanceByField['drivetrain_primary_ecosystem'],
      contains('Ecosistema Shimano'),
    );
  });

  test('does not infer threaded freewheel mount from template family alone',
      () {
    final result = inferDrivetrainProductSpecValues(
      technicalFamily: 'freewheel',
      currentValues: const <String, dynamic>{
        'drivetrain_speeds': 7,
      },
    );

    expect(result.derivedValues.containsKey('freehub_type'), isFalse);
    expect(result.guidanceByField['freehub_type'], isNull);
  });
}
