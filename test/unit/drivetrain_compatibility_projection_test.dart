import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/utils/drivetrain_compatibility_projection.dart';

void main() {
  test('keeps broad ecosystem claims out of exact platform projection', () {
    final platforms = drivetrainPlatformsFromCompatibilitySpecs(
      const <String, dynamic>{
        'drivetrain_primary_ecosystem': 'Ecosistema Shimano',
        'drivetrain_declared_compatible_ecosystems': ['Ecosistema SRAM'],
      },
    );

    expect(platforms, isEmpty);
  });

  test(
      'does not treat broad ecosystem labels stranded in platform field as exact platforms',
      () {
    final platforms = drivetrainPlatformsFromCompatibilitySpecs(
      const <String, dynamic>{
        'drivetrain_platform': 'Shimano',
        'chain_profile_family': ['Compatible SRAM'],
      },
    );

    expect(platforms, isEmpty);
  });

  test('still projects exact platform labels from the platform field', () {
    final platforms = drivetrainPlatformsFromCompatibilitySpecs(
      const <String, dynamic>{
        'drivetrain_platform': 'Shimano HG/SIS',
      },
    );

    expect(platforms, contains('shimano_hg_sis'));
  });

  test('projects exact platforms only from exact platform/profile signals', () {
    final platforms = drivetrainPlatformsFromCompatibilitySpecs(
      const <String, dynamic>{
        'drivetrain_platform': 'Shimano Hyperglide+',
        'chain_profile_family': ['KMC compatible'],
      },
    );

    expect(platforms, contains('shimano_hg_plus'));
    expect(platforms, contains('kmc_compatible'));
    expect(platforms, isNot(contains('shimano_linkglide')));
  });

  test('keeps split ecosystem fields as broad family evidence', () {
    final families = drivetrainCompatibilityFamiliesFromCompatibilitySpecs(
      const <String, dynamic>{
        'drivetrain_primary_ecosystem': 'Ecosistema Shimano',
        'drivetrain_declared_compatible_ecosystems': ['Ecosistema SRAM'],
      },
    );

    expect(
      families,
      containsAll(const ['shimano_ecosystem', 'sram_ecosystem']),
    );
  });

  test(
      'flags explicit ecosystem conflict without treating broad claims as exact matches',
      () {
    expect(
      hasExplicitDrivetrainFamilyConflict(
        bikePlatform: 'shimano_hg_plus',
        productFamilies: const {'sram_ecosystem'},
      ),
      isTrue,
    );
    expect(
      hasExplicitDrivetrainFamilyConflict(
        bikePlatform: 'shimano_hg_plus',
        productFamilies: const {'kmc_multi_compatible'},
      ),
      isFalse,
    );
  });
}
