import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/config/drivetrain_canonical_data.dart';
import 'package:vinabike_erp/modules/inventory/utils/product_spec_inference_utils.dart';

void main() {
  test(
      'prunes stale single speed auto values before re-inferring 3/32 chain coverage',
      () {
    final prunedValues = pruneStaleAutoDerivedProductSpecValues(
      baseValues: const <String, dynamic>{
        'chain_width_family': '3/32',
        'chain_speeds': ['1'],
        'drivetrain_mode': kDrivetrainModeSingleSpeedBmxIgh,
        'drivetrain_primary_ecosystem':
            kDrivetrainCompatibilityFamilySingleSpeed,
        'chain_profile_family': ['Single speed / BMX'],
      },
      manualKeys: const {'chain_width_family'},
      previousAutoValues: const <String, dynamic>{
        'chain_speeds': ['1'],
        'drivetrain_mode': kDrivetrainModeSingleSpeedBmxIgh,
        'drivetrain_primary_ecosystem':
            kDrivetrainCompatibilityFamilySingleSpeed,
        'chain_profile_family': ['Single speed / BMX'],
      },
    );

    expect(
      prunedValues,
      const <String, dynamic>{
        'chain_width_family': '3/32',
      },
    );

    final inference = inferDrivetrainProductSpecValues(
      technicalFamily: 'chain',
      currentValues: prunedValues,
    );

    expect(inference.derivedValues['chain_speeds'], const ['5', '6', '7', '8']);
    expect(
      inference.derivedValues['chain_profile_family'],
      const ['Universal 5-8v'],
    );
    expect(
      inference.derivedValues['drivetrain_mode'],
      kDrivetrainModeDerailleur,
    );
    expect(
      inference.derivedValues.containsKey('drivetrain_primary_ecosystem'),
      isFalse,
    );
  });

  test('omits auto-derived values from persistence payload', () {
    final persistedValues = omitAutoDerivedProductSpecValues(
      values: const <String, dynamic>{
        'chain_width_family': '3/32',
        'chain_speeds': ['5', '6', '7', '8'],
        'drivetrain_mode': kDrivetrainModeDerailleur,
        'chain_profile_family': ['Universal 5-8v'],
      },
      autoDerivedValues: const <String, dynamic>{
        'chain_speeds': ['5', '6', '7', '8'],
        'drivetrain_mode': kDrivetrainModeDerailleur,
        'chain_profile_family': ['Universal 5-8v'],
      },
    );

    expect(
      persistedValues,
      const <String, dynamic>{
        'chain_width_family': '3/32',
      },
    );
  });

  test('keeps manual overrides even when an auto-derived value existed before',
      () {
    final persistedValues = omitAutoDerivedProductSpecValues(
      values: const <String, dynamic>{
        'chain_width_family': '11/128',
        'chain_speeds': ['9'],
      },
      autoDerivedValues: const <String, dynamic>{
        'chain_speeds': ['5', '6', '7', '8'],
      },
    );

    expect(
      persistedValues,
      const <String, dynamic>{
        'chain_width_family': '11/128',
        'chain_speeds': ['9'],
      },
    );
  });
}
