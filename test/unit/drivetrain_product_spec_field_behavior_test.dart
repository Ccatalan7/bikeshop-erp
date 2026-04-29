import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/config/drivetrain_canonical_data.dart';

void main() {
  test(
      'does not canonicalize broad ecosystem text as an exact drivetrain platform label',
      () {
    expect(canonicalDrivetrainProductPlatformLabel('Shimano'), isNull);
    expect(canonicalDrivetrainProductPlatformLabel('Compatible SRAM'), isNull);
  });

  test('hides drivetrain platform for generic KMC 3/32 chain coverage', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'chain',
      fieldKey: 'drivetrain_platform',
      currentValues: const <String, dynamic>{
        'chain_width_family': '3/32',
        'chain_speeds': ['6', '7', '8'],
      },
    );

    expect(behavior.hidden, isTrue);
    expect(behavior.allowedOptions, isNull);
  });

  test('hides drivetrain mode when 1/8 chain width already proves single speed',
      () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'chain',
      fieldKey: 'drivetrain_mode',
      currentValues: const <String, dynamic>{
        'chain_width_family': '1/8',
      },
    );

    expect(behavior.hidden, isTrue);
    expect(behavior.enabled, isFalse);
    expect(
      behavior.allowedOptions,
      const [kDrivetrainModeSingleSpeedBmxIgh],
    );
  });

  test(
      'hides drivetrain mode when chain speeds already prove derailleur branch',
      () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'chain',
      fieldKey: 'drivetrain_mode',
      currentValues: const <String, dynamic>{
        'chain_width_family': '3/32',
        'chain_speeds': ['6', '7', '8'],
      },
    );

    expect(behavior.hidden, isTrue);
    expect(behavior.enabled, isFalse);
    expect(behavior.allowedOptions, const [kDrivetrainModeDerailleur]);
  });

  test('locks chain speeds to 1v for 1/8 chain width', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'chain',
      fieldKey: 'chain_speeds',
      currentValues: const <String, dynamic>{
        'chain_width_family': '1/8',
        'chain_speeds': ['6', '7', '8'],
      },
    );

    expect(behavior.hidden, isFalse);
    expect(behavior.enabled, isFalse);
    expect(behavior.allowedOptions, const ['1']);
  });

  test('narrows chain speeds to 5-8v for 3/32 chain width', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'chain',
      fieldKey: 'chain_speeds',
      currentValues: const <String, dynamic>{
        'chain_width_family': '3/32',
      },
    );

    expect(behavior.hidden, isFalse);
    expect(behavior.enabled, isTrue);
    expect(
      behavior.allowedOptions,
      const ['5', '6', '7', '8'],
    );
  });

  test('shows outer width options for narrow derailleur chains', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'chain',
      fieldKey: 'chain_outer_width_mm',
      currentValues: const <String, dynamic>{
        'chain_width_family': '11/128',
      },
    );

    expect(behavior.hidden, isFalse);
    expect(
      behavior.allowedOptions,
      unorderedEquals(
          const ['6.6', '6.7', '5.88', '5.95', '5.62', '5.25', '5.3']),
    );
  });

  test('hides outer width field for 1/8 single speed chains', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'chain',
      fieldKey: 'chain_outer_width_mm',
      currentValues: const <String, dynamic>{
        'chain_width_family': '1/8',
      },
    );

    expect(behavior.hidden, isTrue);
  });

  test('does not use commercial brand as an ecosystem hint in ficha behavior',
      () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'chain',
      fieldKey: 'drivetrain_primary_ecosystem',
      currentValues: const <String, dynamic>{
        'chain_width_family': '3/32',
        'chain_speeds': ['6', '7', '8'],
      },
    );

    expect(behavior.hidden, isFalse);
    expect(behavior.allowedOptions, isNull);
    expect(behavior.helperText, isNull);
  });

  test(
      'keeps primary ecosystem manual when generic chain profile gives no anchor',
      () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'chain',
      fieldKey: 'drivetrain_primary_ecosystem',
      currentValues: const <String, dynamic>{
        'chain_width_family': '3/32',
        'chain_speeds': ['6', '7', '8'],
        'chain_profile_family': ['Universal 5-8v'],
      },
    );

    expect(behavior.enabled, isTrue);
    expect(behavior.allowedOptions, isNull);
    expect(behavior.helperText, isNull);
  });

  test('filters chain profile options when legacy KMC family is confirmed', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'chain',
      fieldKey: 'chain_profile_family',
      currentValues: const <String, dynamic>{
        'chain_width_family': '3/32',
        'chain_speeds': ['6', '7', '8'],
        'drivetrain_compatibility_family': [
          kDrivetrainCompatibilityFamilyKmc,
        ],
      },
    );

    expect(behavior.hidden, isFalse);
    expect(behavior.enabled, isTrue);
    expect(
      behavior.allowedOptions,
      unorderedEquals(const ['Universal 5-8v', 'KMC compatible']),
    );
  });

  test('hides legacy drivetrain compatibility family field', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'chain',
      fieldKey: 'drivetrain_compatibility_family',
      currentValues: const <String, dynamic>{
        'chain_width_family': '3/32',
      },
    );

    expect(behavior.hidden, isTrue);
    expect(behavior.helperText, contains('Campo legado/interino'));
  });

  test(
      'narrows 12v SRAM chain platform options from confirmed primary ecosystem',
      () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'chain',
      fieldKey: 'drivetrain_platform',
      currentValues: const <String, dynamic>{
        'chain_width_family': '11/128',
        'chain_speeds': ['12'],
        'drivetrain_primary_ecosystem': kDrivetrainCompatibilityFamilySram,
      },
    );

    expect(behavior.hidden, isFalse);
    expect(
      behavior.allowedOptions,
      unorderedEquals(const [
        'SRAM Eagle',
        'SRAM FlatTop / AXS road',
        'SRAM T-Type Transmission',
      ]),
    );
  });

  test(
      'does not offer universal 9-11 profile when outer width already fixes 10v',
      () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'chain',
      fieldKey: 'chain_profile_family',
      currentValues: const <String, dynamic>{
        'chain_width_family': '11/128',
        'chain_outer_width_mm': 5.88,
        'chain_speeds': ['10'],
      },
    );

    expect(behavior.hidden, isFalse);
    expect(behavior.allowedOptions, isNull);
  });

  test('explicit platform suggests primary ecosystem without locking it', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'chain_link',
      fieldKey: 'drivetrain_primary_ecosystem',
      currentValues: const <String, dynamic>{
        'drivetrain_platform': 'Shimano Hyperglide+',
      },
    );

    expect(behavior.enabled, isTrue);
    expect(behavior.allowedOptions, isNull);
    expect(behavior.helperText, contains('Ecosistema Shimano'));
  });

  test('narrows cassette freehub choices to cassette body families', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'cassette',
      fieldKey: 'freehub_type',
      currentValues: const <String, dynamic>{
        'drivetrain_speeds': 12,
      },
    );

    expect(behavior.hidden, isFalse);
    expect(behavior.enabled, isTrue);
    expect(
      behavior.allowedOptions,
      unorderedEquals(const [
        'Shimano HG',
        'Shimano HG Road 11',
        'Micro Spline',
        'SRAM XD',
        'SRAM XDR',
        'Campagnolo',
        'Campagnolo N3W',
      ]),
    );
    expect(behavior.helperText, contains('Velocidad sola'));
  });

  test('keeps freewheel mount explicit in the ficha', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'freewheel',
      fieldKey: 'freehub_type',
      currentValues: const <String, dynamic>{
        'drivetrain_speeds': 7,
      },
    );

    expect(behavior.hidden, isFalse);
    expect(behavior.enabled, isTrue);
    expect(behavior.allowedOptions, const ['Rueda libre roscada']);
    expect(behavior.helperText, contains('categoria comercial'));
  });

  test('hides rear-cog ecosystem and platform semantics from ficha behavior',
      () {
    for (final technicalFamily in const [
      'cassette',
      'freewheel',
      'fixed_cog'
    ]) {
      for (final fieldKey in const [
        'drivetrain_primary_ecosystem',
        'drivetrain_declared_compatible_ecosystems',
        'drivetrain_platform',
      ]) {
        final behavior = resolveDrivetrainProductSpecFieldBehavior(
          technicalFamily: technicalFamily,
          fieldKey: fieldKey,
          currentValues: const <String, dynamic>{},
        );

        expect(
          behavior.hidden,
          isTrue,
          reason: '$technicalFamily should hide $fieldKey',
        );
      }
    }
  });

  test('highlights cassette largest cog as a required range seam', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'cassette',
      fieldKey: 'largest_cog_teeth',
      currentValues: const <String, dynamic>{
        'drivetrain_speeds': 12,
        'freehub_type': 'Micro Spline',
      },
    );

    expect(behavior.hidden, isFalse);
    expect(behavior.helperText, contains('pinon mayor real'));
    expect(behavior.helperText, contains('capacidad del cambio'));
  });

  test('narrows cassette spacer freehub choices to cassette body families', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'cassette_spacer',
      fieldKey: 'freehub_type',
      currentValues: const <String, dynamic>{},
    );

    expect(behavior.hidden, isFalse);
    expect(behavior.enabled, isTrue);
    expect(
      behavior.allowedOptions,
      unorderedEquals(const [
        'Shimano HG',
        'Shimano HG Road 11',
        'Micro Spline',
        'SRAM XD',
        'SRAM XDR',
        'Campagnolo',
        'Campagnolo N3W',
      ]),
    );
    expect(behavior.helperText, contains('largo, generacion y montaje'));
  });

  test('treats cassette spacer thickness as explicit measured data', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'cassette_spacer',
      fieldKey: 'spacer_thickness_mm',
      currentValues: const <String, dynamic>{},
    );

    expect(behavior.hidden, isFalse);
    expect(behavior.allowedOptions, isNull);
    expect(behavior.helperText, contains('espesor real en mm'));
    expect(behavior.helperText, contains('pieza universal'));
  });

  test('supports finer cassette body families for cassette freehub choices',
      () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'cassette',
      fieldKey: 'freehub_type',
      currentValues: const <String, dynamic>{
        'drivetrain_speeds': 12,
      },
    );

    expect(
      behavior.allowedOptions,
      unorderedEquals(const [
        'Shimano HG',
        'Shimano HG Road 11',
        'Micro Spline',
        'SRAM XD',
        'SRAM XDR',
        'Campagnolo',
        'Campagnolo N3W',
      ]),
    );
    expect(behavior.helperText, contains('HG Road 11'));
    expect(behavior.helperText, contains('XD vs XDR'));
  });

  test('hides freehub field for front hub templates', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'front_hub',
      fieldKey: 'freehub_type',
      currentValues: const <String, dynamic>{},
    );

    expect(behavior.hidden, isTrue);
    expect(behavior.helperText, contains('delantera'));
  });

  test('offers expanded rear body families for rear hub templates', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'rear_hub',
      fieldKey: 'freehub_type',
      currentValues: const <String, dynamic>{
        'wheel_position': 'rear',
      },
    );

    expect(
      behavior.allowedOptions,
      unorderedEquals(const [
        'Shimano HG',
        'Shimano HG Road 11',
        'Micro Spline',
        'SRAM XD',
        'SRAM XDR',
        'Campagnolo',
        'Campagnolo N3W',
        'Rueda libre roscada',
        'Driver BMX',
        'Rosca fija / contratuerca',
        'Maza contrapedal',
      ]),
    );
    expect(behavior.helperText, contains('HG Road 11'));
    expect(behavior.helperText, contains('Campagnolo/N3W'));
  });

  test('guides generic hub position before rear-body filtering', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'hub',
      fieldKey: 'wheel_position',
      currentValues: const <String, dynamic>{},
    );

    expect(behavior.hidden, isFalse);
    expect(behavior.helperText, contains('delantera o trasera'));
    expect(behavior.helperText, contains('driver/freehub trasero'));
  });

  test(
      'narrows generic hub spacing options to front OLD when position is front',
      () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'hub',
      fieldKey: 'hub_spacing_mm',
      currentValues: const <String, dynamic>{
        'wheel_position': 'front',
      },
    );

    expect(behavior.allowedOptions, const ['100', '110']);
    expect(behavior.helperText, contains('100 o 110 mm'));
  });

  test('narrows generic hub spacing options to rear OLD when position is rear',
      () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'hub',
      fieldKey: 'hub_spacing_mm',
      currentValues: const <String, dynamic>{
        'wheel_position': 'rear',
      },
    );

    expect(behavior.allowedOptions, const ['130', '135', '142', '148']);
    expect(behavior.helperText, contains('130, 135, 142 o 148 mm'));
  });

  test('hides generic hub freehub field when wheel position is front', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'hub',
      fieldKey: 'freehub_type',
      currentValues: const <String, dynamic>{
        'wheel_position': 'front',
      },
    );

    expect(behavior.hidden, isTrue);
    expect(behavior.helperText, contains('delantera'));
  });

  test('hides broad ecosystem semantics for chainring and crankset templates',
      () {
    for (final technicalFamily in const ['chainring', 'crankset']) {
      for (final fieldKey in const [
        'drivetrain_primary_ecosystem',
        'drivetrain_declared_compatible_ecosystems',
      ]) {
        final behavior = resolveDrivetrainProductSpecFieldBehavior(
          technicalFamily: technicalFamily,
          fieldKey: fieldKey,
          currentValues: const <String, dynamic>{},
        );

        expect(
          behavior.hidden,
          isTrue,
          reason: '$technicalFamily should hide $fieldKey',
        );
      }
    }
  });

  test('hides bb thread standard for pressfit families', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'bottom_bracket',
      fieldKey: 'bb_thread_standard',
      currentValues: const <String, dynamic>{
        'bottom_bracket_family': 'Pressfit',
      },
    );

    expect(behavior.hidden, isTrue);
    expect(behavior.helperText, contains('bore'));
  });

  test(
      'locks spindle interface to square variants for square cartridge families',
      () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'bottom_bracket',
      fieldKey: 'spindle_interface',
      currentValues: const <String, dynamic>{
        'bottom_bracket_family': 'Cuadrado cartucho',
      },
    );

    expect(behavior.hidden, isFalse);
    expect(behavior.allowedOptions, const ['Cuadrado JIS', 'Cuadrado ISO']);
    expect(behavior.helperText, contains('JIS o ISO'));
  });

  test('locks spindle interface for hollowtech external families', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'bottom_bracket',
      fieldKey: 'spindle_interface',
      currentValues: const <String, dynamic>{
        'bottom_bracket_family': 'Hollowtech / 24mm externo',
      },
    );

    expect(behavior.hidden, isFalse);
    expect(behavior.enabled, isFalse);
    expect(behavior.allowedOptions, const ['Hollowtech / 24mm']);
  });

  test('keeps shell diameter visible for pressfit families', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'bottom_bracket',
      fieldKey: 'bb_shell_diameter_mm',
      currentValues: const <String, dynamic>{
        'bottom_bracket_family': 'BB30 / PF30',
      },
    );

    expect(behavior.hidden, isFalse);
    expect(behavior.helperText, contains('diámetro real del bore/caja'));
  });

  test('hides shell diameter for threaded bottom bracket families', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'bottom_bracket',
      fieldKey: 'bb_shell_diameter_mm',
      currentValues: const <String, dynamic>{
        'bottom_bracket_family': 'BSA roscado',
      },
    );

    expect(behavior.hidden, isTrue);
    expect(behavior.helperText, contains('estándar de rosca'));
  });

  test('hides loose spindle length for hollowtech external families', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'bottom_bracket',
      fieldKey: 'spindle_length_mm',
      currentValues: const <String, dynamic>{
        'bottom_bracket_family': 'Hollowtech / 24mm externo',
      },
    );

    expect(behavior.hidden, isTrue);
    expect(behavior.helperText, contains('Hollowtech / 24mm'));
  });

  test('hides broad ecosystem and platform semantics for chain guide templates',
      () {
    for (final fieldKey in const [
      'drivetrain_primary_ecosystem',
      'drivetrain_declared_compatible_ecosystems',
      'drivetrain_platform',
    ]) {
      final behavior = resolveDrivetrainProductSpecFieldBehavior(
        technicalFamily: 'chain_guide',
        fieldKey: fieldKey,
        currentValues: const <String, dynamic>{},
      );

      expect(
        behavior.hidden,
        isTrue,
        reason: 'chain_guide should hide $fieldKey',
      );
    }
  });

  test('hides rear-speed field for left/front shifters', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'shifter',
      fieldKey: 'drivetrain_speeds',
      currentValues: const <String, dynamic>{
        'shifter_position': 'Izquierdo / delantero',
      },
    );

    expect(behavior.hidden, isTrue);
    expect(behavior.helperText, contains('platos'));
  });

  test('hides shift actuation family for left/front shifters', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'shifter',
      fieldKey: 'shift_actuation_family',
      currentValues: const <String, dynamic>{
        'shifter_position': 'Izquierdo / delantero',
      },
    );

    expect(behavior.hidden, isTrue);
    expect(behavior.helperText, contains('indexado/plataforma trasera'));
  });

  test('hides drivetrain platform for left/front shifters', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'shifter',
      fieldKey: 'drivetrain_platform',
      currentValues: const <String, dynamic>{
        'shifter_position': 'Izquierdo / delantero',
      },
    );

    expect(behavior.hidden, isTrue);
    expect(behavior.helperText, contains('indexado/plataforma trasera'));
  });

  test('keeps drivetrain platform visible for pair shifters', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'shifter',
      fieldKey: 'drivetrain_platform',
      currentValues: const <String, dynamic>{
        'shifter_position': 'Par',
      },
    );

    expect(behavior.hidden, isFalse);
  });

  test('hides front-chainring count for right/rear shifters', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'shifter',
      fieldKey: 'front_chainring_count',
      currentValues: const <String, dynamic>{
        'shifter_position': 'Derecho / trasero',
      },
    );

    expect(behavior.hidden, isTrue);
    expect(behavior.helperText, contains('velocidades traseras'));
  });

  test('hides front derailleur clamp size for braze-on mounts', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'front_derailleur',
      fieldKey: 'front_derailleur_clamp_mm',
      currentValues: const <String, dynamic>{
        'front_derailleur_mount_type': 'Braze-on',
      },
    );

    expect(behavior.hidden, isTrue);
    expect(behavior.helperText, contains('Braze-on'));
  });

  test('narrows front derailleur chainring count to 2x or 3x', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'front_derailleur',
      fieldKey: 'front_chainring_count',
      currentValues: const <String, dynamic>{},
    );

    expect(behavior.hidden, isFalse);
    expect(behavior.allowedOptions, const ['2', '3']);
    expect(behavior.helperText, contains('2x o 3x'));
  });

  test('removes single-speed ecosystem anchor from front derailleur ficha', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'front_derailleur',
      fieldKey: 'drivetrain_primary_ecosystem',
      currentValues: const <String, dynamic>{},
    );

    expect(behavior.hidden, isFalse);
    expect(
      behavior.allowedOptions,
      isNot(contains('Single speed / BMX')),
    );
    expect(behavior.helperText, contains('varios platos'));
  });

  test('removes 1x-only platforms from front derailleur ficha', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'front_derailleur',
      fieldKey: 'drivetrain_platform',
      currentValues: const <String, dynamic>{},
    );

    expect(behavior.hidden, isFalse);
    expect(behavior.allowedOptions, isNot(contains('Single speed / BMX')));
    expect(
      behavior.allowedOptions,
      isNot(contains('SRAM Eagle')),
    );
    expect(
      behavior.allowedOptions,
      isNot(contains('SRAM T-Type Transmission')),
    );
    expect(behavior.allowedOptions, contains('SRAM FlatTop / AXS road'));
    expect(behavior.helperText, contains('1x-only'));
  });

  test('keeps front derailleur clamp size visible for clamp mounts', () {
    final behavior = resolveDrivetrainProductSpecFieldBehavior(
      technicalFamily: 'front_derailleur',
      fieldKey: 'front_derailleur_clamp_mm',
      currentValues: const <String, dynamic>{
        'front_derailleur_mount_type': 'Abrazadera',
      },
    );

    expect(behavior.hidden, isFalse);
    expect(behavior.helperText, contains('abrazadera'));
  });
}
