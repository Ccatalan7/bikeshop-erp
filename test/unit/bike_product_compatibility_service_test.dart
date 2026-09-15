import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bike_product_compatibility_service.dart';
import 'package:vinabike_erp/shared/models/product.dart';
import 'package:vinabike_erp/shared/models/product_compatibility.dart';

void main() {
  group('BikeProductCompatibilityService', () {
    test('HY/RD mineral circuit cannot imply hydraulic lever input', () async {
      final result = await _assessProduct(
        technicalFamily: 'brake_caliper',
        bikeTechnicalValues: {'brakeType': 'mechanical_disc'},
        productSpecs: {
          'braking_surface': 'Disco',
          'brake_actuation': 'Híbrido (cable a hidráulico)',
          'fluid_type': 'Mineral',
        },
      );
      expect(result.level, ProductCompatibilityLevel.caution);
    });

    test('HS33 mineral circuit cannot imply a disc braking surface', () async {
      final result = await _assessProduct(
        technicalFamily: 'rim_brake',
        bikeTechnicalValues: {'brakeType': 'rim'},
        productSpecs: {
          'braking_surface': 'Llanta',
          'brake_actuation': 'Hidráulico',
          'fluid_type': 'Mineral',
        },
      );
      expect(result.level, ProductCompatibilityLevel.caution);
    });

    for (final specs in [
      <String, dynamic>{},
      <String, dynamic>{
        'braking_surface': 'Llanta',
        'brake_actuation': 'Hidráulico',
        'fluid_type': 'Mineral',
      },
    ]) {
      test('generic caliper family does not imply a disc $specs', () async {
        final result = await _assessProduct(
          technicalFamily: 'brake_caliper',
          bikeTechnicalValues: {'brakeType': 'rim'},
          productSpecs: specs,
        );
        expect(result.level, ProductCompatibilityLevel.caution);
      });
    }

    for (final bikeType in ['rim', 'mechanical_disc', 'hydraulic_disc']) {
      test('fluid alone cannot establish fitment against $bikeType', () async {
        final result = await _assessProduct(
          technicalFamily: 'brake_fluid',
          bikeTechnicalValues: {'brakeType': bikeType},
          productSpecs: {'fluid_type': 'Mineral'},
        );
        expect(result.level, ProductCompatibilityLevel.caution);
      });
    }

    for (final (productSurface, bikeType) in [
      ('Llanta', 'mechanical_disc'),
      ('Disco', 'rim'),
    ]) {
      test(
          'aggregate $bikeType cannot refute the target wheel for $productSurface',
          () async {
        final result = await _assessProduct(
          technicalFamily: 'brake',
          bikeTechnicalValues: {'brakeType': bikeType},
          productSpecs: {'braking_surface': productSurface},
        );
        expect(result.level, ProductCompatibilityLevel.caution);
        expect(result.detail, contains('rueda'));
      });
    }

    for (final (family, surface) in [
      ('brake_pad', 'Llanta'),
      ('brake_pad', 'Disco'),
      ('brake_pad', 'Maza'),
      ('brake_lever', 'Llanta'),
      ('rim_brake', 'Llanta'),
      ('hydraulic_disc_brake', 'Disco'),
      ('mechanical_disc_brake', 'Disco'),
      ('disc_brake', 'Disco'),
    ]) {
      test('$family cannot reject a front brake from rear coaster context',
          () async {
        final result = await _assessProduct(
          technicalFamily: family,
          bikeTechnicalValues: {'brakeType': 'coaster_brake'},
          productSpecs: {'braking_surface': surface, 'brake_position': 'front'},
        );
        expect(result.level, ProductCompatibilityLevel.caution);
        expect(result.detail, contains('rueda'));
      });
    }

    test('rotor retains its scoped size check with aggregate rim brake type',
        () async {
      final result = await _assessProduct(
        technicalFamily: 'rotor',
        bikeTechnicalValues: {'brakeType': 'rim', 'frontRotorSizeMm': 180},
        productSpecs: {'rotor_diameter_mm': 180, 'brake_position': 'front'},
      );
      expect(result.level, ProductCompatibilityLevel.caution);
      expect(result.detail, contains('180'));
      expect(result.detail, contains('espesor'));
    });

    test('shared brake field cannot bypass the hub width conflict', () async {
      final result = await _assessProduct(
        technicalFamily: 'front_hub',
        bikeFrontHubSpacingMm: 100,
        bikeTechnicalValues: {'brakeType': 'disc'},
        productSpecs: {
          'wheel_position': 'front',
          'hub_spacing_mm': 110,
          'rotor_mount_type': '6 pernos',
        },
      );
      expect(result.level, ProductCompatibilityLevel.incompatible);
      expect(result.detail, contains('110'));
    });

    for (final system in ['Hollowtech / 24mm externo', 'Cuadrado cartucho']) {
      test('crank $system is not compared as a frame shell', () async {
        final result = await _assessProduct(
          technicalFamily: 'crankset',
          bikeTechnicalValues: {
            'bottomBracketFamily': 'BSA roscado',
            'drivetrainConfig': '2x10'
          },
          productSpecs: {
            'bottom_bracket_family': system,
            'front_chainring_count': ['2']
          },
        );
        expect(result.level, ProductCompatibilityLevel.caution);
        expect(result.detail, contains('línea de cadena'));
      });
    }

    for (final (shell, frameWidth, productWidth) in [
      ('BSA roscado', 68, 73),
      ('Pressfit', 89.5, 92),
    ]) {
      test('$shell scalar width is not a model coverage envelope', () async {
        final result = await _assessProduct(
          technicalFamily: 'bottom_bracket',
          bikeTechnicalValues: {
            'bottomBracketFamily': shell,
            'bbShellWidthMm': frameWidth
          },
          productSpecs: {
            'bb_shell_standard': shell,
            'bb_shell_width_mm': productWidth
          },
        );
        expect(result.level, ProductCompatibilityLevel.caution);
        expect(result.detail, contains('configuraciones admitidas'));
        expect(result.detail, contains('No se autoriza un adaptador'));
      });
    }

    test('known Mid versus BSA conflict survives an unresolved width',
        () async {
      final result = await _assessProduct(
        technicalFamily: 'bottom_bracket',
        bikeTechnicalValues: {
          'bottomBracketFamily': 'BSA roscado',
          'bbShellWidthMm': 68
        },
        productSpecs: {
          'bb_shell_standard': 'Mid BMX 41,2 mm',
          'bb_shell_width_mm': 73
        },
      );
      expect(result.level, ProductCompatibilityLevel.incompatible);
      expect(result.detail, contains('montaje directo'));
    });

    test(
        'accepted spindle alternatives do not turn into a joined unknown token',
        () async {
      final result = await _assessProduct(
        technicalFamily: 'bottom_bracket',
        bikeTechnicalValues: {'spindleInterface': 'Hollowtech / 24mm'},
        productSpecs: {
          'spindle_interface_accepted': ['SRAM GXP 24/22', 'Hollowtech / 24mm']
        },
      );
      expect(result.level, ProductCompatibilityLevel.caution);
      expect(result.detail, contains('24 mm'));
      expect(result.detail, contains('combinación completa'));
    });

    test('GXP does not become a Shimano 24 mm match', () async {
      final result = await _assessProduct(
        technicalFamily: 'bottom_bracket',
        bikeTechnicalValues: {'spindleInterface': 'Hollowtech / 24mm'},
        productSpecs: {
          'spindle_interface_accepted': ['SRAM GXP 24/22']
        },
      );
      expect(result.level, ProductCompatibilityLevel.caution);
      expect(result.detail, contains('fuera de la cobertura'));
    });

    test('unknown shifter side cannot create a rear speed rejection', () async {
      final result = await _assessProduct(
        technicalFamily: 'shifter',
        bikeTechnicalValues: {
          'drivetrainSpeeds': 12,
          'drivetrainConfig': '2x12',
          'shiftActuationFamily': 'Shimano Dynasys 11/12'
        },
        productSpecs: {
          'drivetrain_speeds': ['8'],
          'front_chainring_count': ['2'],
          'shift_actuation_family': 'SRAM X-Actuation'
        },
      );
      expect(result.level, ProductCompatibilityLevel.caution);
      expect(result.detail, contains('lado de instalación'));
    });

    test('left shifter does not compare with rear actuation family', () async {
      final result = await _assessProduct(
        technicalFamily: 'shifter',
        bikeTechnicalValues: {
          'drivetrainSpeeds': 12,
          'drivetrainConfig': '2x12',
          'shiftActuationFamily': 'Shimano Dynasys 11/12'
        },
        productSpecs: {
          'shifter_position': 'Izquierdo / delantero',
          'front_chainring_count': ['2'],
          'shift_actuation_family': 'SRAM X-Actuation'
        },
      );
      expect(result.level, ProductCompatibilityLevel.caution);
      expect(result.detail, contains('tiro/indexado delantero'));
      expect(result.detail, isNot(contains('coincide 2x · SRAM')));
    });

    test('front count change never recommends leaving a position unused',
        () async {
      final result = await _assessProduct(
        technicalFamily: 'shifter',
        bikeTechnicalValues: {'drivetrainConfig': '2x10'},
        productSpecs: {
          'shifter_position': 'Par',
          'front_chainring_count': ['3'],
          'drivetrain_speeds': ['10']
        },
      );
      expect(result.level, ProductCompatibilityLevel.caution);
      expect(result.detail, contains('cobertura explícita'));
      expect(result.detail, contains('No se presume'));
    });

    test(
        'known rear conflict in a pair is not suppressed by front count change',
        () async {
      final result = await _assessProduct(
        technicalFamily: 'shifter',
        bikeTechnicalValues: {
          'drivetrainSpeeds': 12,
          'drivetrainConfig': '2x12'
        },
        productSpecs: {
          'shifter_position': 'Par',
          'front_chainring_count': ['3'],
          'drivetrain_speeds': ['10']
        },
      );
      expect(result.level, ProductCompatibilityLevel.incompatible);
      expect(result.detail, contains('12v'));
    });

    for (final family in ['front_derailleur', 'crankset']) {
      test('$family requires a scoped conversion from current 1x', () async {
        final result = await _assessProduct(
          technicalFamily: family,
          bikeTechnicalValues: {'drivetrainConfig': '1x12'},
          productSpecs: {
            'front_chainring_count': ['2']
          },
        );
        expect(result.level, ProductCompatibilityLevel.caution);
        expect(result.detail, contains('conversión'));
      });
    }

    test('front derailleur reads canonical supported counts', () async {
      final result = await _assessProduct(
        technicalFamily: 'front_derailleur',
        bikeTechnicalValues: {'drivetrainConfig': '2x10'},
        productSpecs: {
          'compatible_chainring_counts': ['2']
        },
      );
      expect(result.level, ProductCompatibilityLevel.caution);
      expect(result.detail, contains('coincide 2x'));
    });

    test('a numeric fragment in a front count note is not a count match',
        () async {
      final result = await _assessProduct(
        technicalFamily: 'front_derailleur',
        bikeTechnicalValues: {'drivetrainConfig': '2x10'},
        productSpecs: {
          'compatible_chainring_counts': ['modelo 2026']
        },
      );
      expect(result.level, ProductCompatibilityLevel.caution);
      expect(result.detail, isNot(contains('coincide 2x')));
    });

    test('products in the same category keep distinct resolved families',
        () async {
      final chain = _buildProduct();
      final connector = chain.copyWith(id: 'product-2');
      final service = BikeProductCompatibilityService();
      service.primeCompatibilityCaches(productSpecsByProductId: {
        chain.id: {
          '__technical_family': 'chain',
          'chain_speeds': ['8'],
        },
        connector.id: {
          '__technical_family': 'chain_link',
          'chain_speeds': ['11'],
          '__reference_claims': [
            {
              'interface': 'connector_chain',
              'targets': ['Shimano HG 11']
            }
          ],
        },
      });
      final results = await service.buildAutocompleteAssessments(
        bike: _buildBike(),
        profile: _buildProfile({'drivetrainSpeeds': 9}),
        products: [chain, connector],
      );
      expect(chain.categoryId, connector.categoryId);
      expect(results[chain.id]?.level, ProductCompatibilityLevel.caution);
      expect(results[chain.id]?.detail, contains('fuera de la cobertura'));
      expect(results[connector.id]?.level, ProductCompatibilityLevel.caution);
      expect(results[connector.id]?.detail, contains('cadena instalada'));
    });

    test('an unavailable assigned template cannot regain category authority',
        () async {
      final result = await _assessProduct(
        technicalFamily: 'chain',
        bikeTechnicalValues: {'drivetrainSpeeds': 8},
        productSpecs: {
          '__technical_family': null,
          '__binding_source': 'explicit_unavailable',
          '__spec_issues': [
            {'code': 'template_unavailable'}
          ],
          'chain_speeds': ['8'],
        },
      );
      expect(result.level, ProductCompatibilityLevel.caution);
      expect(result.detail, contains('pendientes de revisión'));
    });

    test('connector chain class is never compared with bicycle rear speeds',
        () async {
      final assessment = await _assessProduct(
          technicalFamily: 'chain_link',
          bikeTechnicalValues: {
            'drivetrainSpeeds': 9,
            'drivetrainPlatform': 'Shimano LINKGLIDE'
          },
          productSpecs: {
            'chain_speeds': ['11'],
            'chain_link_reusable': false,
            '__reference_claims': [
              {
                'interface': 'connector_chain',
                'targets': ['Shimano HG 11', 'Shimano LINKGLIDE']
              }
            ]
          });
      expect(assessment.level, ProductCompatibilityLevel.caution);
      expect(assessment.detail, contains('cadena instalada'));
      expect(assessment.detail, contains('LINKGLIDE'));
      expect(assessment.detail, isNot(contains('fuera de la cobertura')));
      expect(assessment.detail, contains('un solo uso'));
    });
    test(
        'connector exclusions survive presentation while installed chain is unknown',
        () async {
      final assessment = await _assessProduct(
          technicalFamily: 'chain_link',
          bikeTechnicalValues: {
            'drivetrainSpeeds': 12
          },
          productSpecs: {
            'chain_speeds': ['12'],
            '__reference_claims': [
              {
                'interface': 'connector_chain',
                'targets': ['KMC 12', 'Shimano 12', 'SRAM MTB 12'],
                'excludes': ['Cualquier cadena Flattop']
              }
            ]
          });
      expect(assessment.level, ProductCompatibilityLevel.caution);
      expect(assessment.detail, contains('excluye: Cualquier cadena Flattop'));
    });
    test(
      'does not turn broad bike drivetrain platform text into an exact chain mismatch',
      () async {
        final assessment = await _assessProduct(
          technicalFamily: 'chain',
          bikeTechnicalValues: const <String, dynamic>{
            'drivetrainSpeeds': 12,
            'drivetrainPlatform': 'Shimano',
            'chainWidthFamily': '11/128',
          },
          productSpecs: const <String, dynamic>{
            'chain_speeds': ['12'],
            'chain_width_family': '11/128',
            'chain_outer_width_mm': 5.25,
            'drivetrain_platform': 'SRAM Eagle',
          },
        );

        expect(assessment.level, ProductCompatibilityLevel.caution);
        expect(assessment.detail, contains('12v'));
        expect(assessment.detail, isNot(contains('no coincide')));
      },
    );

    test('a 5.4 mm pin width cannot manufacture speed coverage', () async {
      final assessment = await _assessProduct(
          technicalFamily: 'chain',
          bikeTechnicalValues: {'drivetrainSpeeds': 12},
          productSpecs: {'chain_outer_width_mm': 5.4});
      expect(assessment.level, ProductCompatibilityLevel.caution);
      expect(assessment.detail, contains('por sí solo'));
    });
    test('retired brand/profile fields cannot reject a KMC chain', () async {
      final assessment =
          await _assessProduct(technicalFamily: 'chain', bikeTechnicalValues: {
        'drivetrainSpeeds': 11,
        'drivetrainPlatform': 'Shimano Hyperglide'
      }, productSpecs: {
        'chain_speeds': ['11'],
        'chain_profile_family': 'Campagnolo',
        'drivetrain_primary_ecosystem': 'Ecosistema SRAM'
      });
      expect(assessment.level, ProductCompatibilityLevel.caution);
      expect(assessment.detail, contains('Coinciden 11v'));
    });
    test('a conflicted catalogue entry cannot produce a green fitment verdict',
        () async {
      final assessment =
          await _assessProduct(technicalFamily: 'chain', bikeTechnicalValues: {
        'drivetrainSpeeds': 11
      }, productSpecs: {
        'chain_speeds': ['11'],
        '__spec_issues': [
          {'code': 'reference_conflict'}
        ]
      });
      expect(assessment.level, ProductCompatibilityLevel.caution);
      expect(assessment.detail, contains('revisión'));
    });

    test('exclusive reference names its missing platform requirement',
        () async {
      final assessment =
          await _assessProduct(technicalFamily: 'chain', bikeTechnicalValues: {
        'drivetrainSpeeds': 11
      }, productSpecs: {
        'chain_speeds': ['9', '10', '11'],
        '__reference_claims': [
          {'exclusive': true, 'platform': 'Shimano LINKGLIDE'}
        ]
      });
      expect(assessment.level, ProductCompatibilityLevel.caution);
      expect(assessment.detail, contains('exclusiva'));
      expect(assessment.detail, contains('Linkglide'));
      expect(assessment.sortPriority, greaterThan(8));
    });
    test('rejects a scoped exclusive manufacturer declaration at service level',
        () async {
      final assessment = await _assessProduct(
        technicalFamily: 'chain',
        bikeTechnicalValues: const <String, dynamic>{
          'drivetrainSpeeds': 12,
          'drivetrainPlatform': 'Shimano Hyperglide+',
          'chainWidthFamily': '11/128',
        },
        productSpecs: const <String, dynamic>{
          'chain_speeds': ['12'],
          'chain_width_family': '11/128',
          'chain_outer_width_mm': 5.25,
          'drivetrain_platform': 'Shimano LINKGLIDE',
          '__reference_claims': [
            {
              'platform': 'Shimano LINKGLIDE',
              'exclusive': true,
              'rear_speeds': [9, 10, 11]
            }
          ],
        },
      );

      expect(assessment.level, ProductCompatibilityLevel.incompatible);
      expect(assessment.detail, contains('Linkglide'));
      expect(assessment.detail, contains('Shimano HG+'));
    });

    test(
      'does not promote broad bike shift actuation text into an exact shifter mismatch',
      () async {
        final assessment = await _assessProduct(
          technicalFamily: 'shifter',
          bikeTechnicalValues: const <String, dynamic>{
            'drivetrainConfig': '1x12',
            'drivetrainSpeeds': 12,
            'shiftActuationFamily': 'Shimano',
          },
          productSpecs: const <String, dynamic>{
            'shifter_position': 'right',
            'drivetrain_speeds': ['12'],
            'shift_actuation_family': 'SRAM X-Actuation',
          },
        );

        expect(assessment.level, ProductCompatibilityLevel.caution);
        expect(assessment.detail, contains('12v'));
        expect(assessment.detail, isNot(contains('no coincide')));
      },
    );

    test('matching shifter count and actuation family still needs exact models',
        () async {
      final assessment = await _assessProduct(
        technicalFamily: 'shifter',
        bikeTechnicalValues: const <String, dynamic>{
          'drivetrainConfig': '1x12',
          'drivetrainSpeeds': 12,
          'shiftActuationFamily': 'Shimano Dynasys 11/12',
        },
        productSpecs: const <String, dynamic>{
          'shifter_position': 'right',
          'drivetrain_speeds': ['12'],
          'shift_actuation_family': 'Shimano Dynasys 11/12',
        },
      );

      expect(assessment.level, ProductCompatibilityLevel.caution);
      expect(assessment.detail, contains('12v'));
      expect(assessment.detail, contains('Shimano Dynasys 11/12v'));
    });

    test(
        'keeps front shifter matches in caution while pull semantics stay unresolved',
        () async {
      final assessment = await _assessProduct(
        technicalFamily: 'shifter',
        bikeTechnicalValues: const <String, dynamic>{
          'drivetrainConfig': '2x10',
          'drivetrainSpeeds': 10,
        },
        productSpecs: const <String, dynamic>{
          'shifter_position': 'left',
          'front_chainring_count': ['2'],
        },
      );

      expect(assessment.level, ProductCompatibilityLevel.caution);
      expect(assessment.detail, contains('2x'));
      expect(assessment.detail, contains('tiro/indexado delantero'));
    });

    test('keeps pair shifter matches in caution even when both sides line up',
        () async {
      final assessment = await _assessProduct(
        technicalFamily: 'shifter',
        bikeTechnicalValues: const <String, dynamic>{
          'drivetrainConfig': '2x10',
          'drivetrainSpeeds': 10,
          'shiftActuationFamily': 'Shimano MTB 10-12v',
        },
        productSpecs: const <String, dynamic>{
          'shifter_position': 'pair',
          'drivetrain_speeds': ['10'],
          'front_chainring_count': ['2'],
          'shift_actuation_family': 'Shimano MTB 10-12v',
        },
      );

      expect(assessment.level, ProductCompatibilityLevel.caution);
      expect(assessment.detail, contains('10v'));
      expect(assessment.detail, contains('2x'));
      expect(assessment.detail, contains('tiro/indexado delantero'));
    });

    test('universal shifter requires a side and cannot be expanded to a pair',
        () async {
      final assessment = await _assessProduct(
        technicalFamily: 'shifter',
        bikeTechnicalValues: const <String, dynamic>{
          'drivetrainConfig': '2x10',
          'drivetrainSpeeds': 10,
          'shiftActuationFamily': 'Shimano MTB 10-12v',
        },
        productSpecs: const <String, dynamic>{
          'shifter_position': 'Universal',
          'drivetrain_speeds': ['10'],
          'front_chainring_count': ['2'],
          'shift_actuation_family': 'Shimano MTB 10-12v',
        },
      );

      expect(assessment.level, ProductCompatibilityLevel.caution);
      expect(assessment.detail, contains('lado de instalación'));
      expect(assessment.detail, isNot(contains('coincide')));
      expect(assessment.detail, contains('tiro/indexado delantero'));
    });

    test(
        'keeps rear derailleur matches in caution while range semantics stay unresolved',
        () async {
      final assessment = await _assessProduct(
        technicalFamily: 'rear_derailleur',
        bikeTechnicalValues: const <String, dynamic>{
          'drivetrainConfig': '1x12',
          'drivetrainSpeeds': 12,
          'shiftActuationFamily': 'Shimano Dynasys 11/12',
          'largestCogTeeth': 51,
        },
        productSpecs: const <String, dynamic>{
          'drivetrain_speeds': ['12'],
          'shift_actuation_family': 'Shimano Dynasys 11/12',
          'rear_derailleur_max_teeth': 51,
          'derailleur_cage_length': 'sgs_long',
          'rear_derailleur_total_capacity_teeth': 41,
        },
      );

      expect(assessment.level, ProductCompatibilityLevel.caution);
      expect(assessment.detail, contains('12v'));
      expect(assessment.detail, contains('max 51T'));
      expect(assessment.detail, contains('capacidad real (41T)'));
    });

    test(
        'keeps front derailleur matches in caution while mount and big-ring semantics stay unresolved',
        () async {
      final assessment = await _assessProduct(
        technicalFamily: 'front_derailleur',
        bikeTechnicalValues: const <String, dynamic>{
          'drivetrainConfig': '2x10',
        },
        productSpecs: const <String, dynamic>{
          'front_chainring_count': ['2'],
        },
      );

      expect(assessment.level, ProductCompatibilityLevel.caution);
      expect(assessment.detail, contains('2x'));
      expect(
        assessment.detail,
        contains('abrazadera/montaje, tiro y tamaño del plato grande'),
      );
    });

    test(
        'keeps drivetrain kit matches in caution while rear-side kit content stays unresolved',
        () async {
      final assessment = await _assessProduct(
        technicalFamily: 'drivetrain_kit',
        bikeTechnicalValues: const <String, dynamic>{
          'drivetrainConfig': '1x1',
          'bottomBracketFamily': 'Mid / BMX',
        },
        productSpecs: const <String, dynamic>{
          'front_chainring_count': ['1'],
          'bottom_bracket_family': 'Mid / BMX',
        },
      );

      expect(assessment.level, ProductCompatibilityLevel.caution);
      expect(assessment.detail, contains('1x'));
      expect(assessment.detail, contains('Mid / BMX'));
      expect(assessment.detail, contains('parte trasera'));
    });

    test(
        'keeps bottom bracket matches in caution while shell-standard seams stay unresolved',
        () async {
      final assessment = await _assessProduct(
        technicalFamily: 'bottom_bracket',
        bikeTechnicalValues: const <String, dynamic>{
          'bottomBracketFamily': 'BSA roscado',
          'bbShellWidthMm': 68,
          'bbShellDiameterMm': 33.7,
          'spindleInterface': '24 mm integrado',
        },
        productSpecs: const <String, dynamic>{
          'bottom_bracket_family': 'BSA roscado',
          'bb_shell_width_mm': 68,
          'bb_shell_diameter_mm': 33.7,
          'spindle_interface': '24 mm integrado',
        },
      );

      expect(assessment.level, ProductCompatibilityLevel.caution);
      expect(assessment.detail, contains('BSA roscado'));
      expect(assessment.detail, contains('68 mm'));
      expect(assessment.detail, contains('24 mm'));
      expect(assessment.detail, contains('estándar real del shell'));
    });

    test(
        'scores a motor against the deployed shell vocabulary, not the retired key',
        () async {
      // La ficha del motor dejó de tener `bottom_bracket_family` el 2026-08-20
      // y pasó a `bb_shell_standard` con el vocabulario chileno. Mientras el
      // scorer siguió leyendo la clave vieja no puntuó ni uno de los 34 motores
      // del catálogo: veía null y caía a «sin datos».
      final assessment = await _assessProduct(
        technicalFamily: 'bottom_bracket',
        bikeTechnicalValues: const <String, dynamic>{
          'bottomBracketFamily': 'BSA roscado',
          'bbShellWidthMm': 68,
        },
        productSpecs: const <String, dynamic>{
          'bb_shell_standard': 'BSA / Caja inglesa 34,8 mm (1.37") x 24',
          'bb_construction': 'Rodamiento sellado',
          'bb_shell_width_mm': 68,
          'spindle_length_mm': 118,
        },
      );

      expect(assessment.level, ProductCompatibilityLevel.caution,
          reason:
              'el motor tiene que puntuar con la clave nueva, no quedar mudo');
      expect(assessment.detail, contains('68 mm'),
          reason: 'y el detalle tiene que nombrar el ancho que si calzo');
    });

    test('blocks a motor whose shell cannot go in that frame', () async {
      final assessment = await _assessProduct(
        technicalFamily: 'bottom_bracket',
        bikeTechnicalValues: const <String, dynamic>{
          'bottomBracketFamily': 'BSA roscado',
          'bbShellWidthMm': 68,
        },
        productSpecs: const <String, dynamic>{
          'bb_shell_standard': 'Mid BMX 41,2 mm',
          'bb_shell_width_mm': 68,
        },
      );

      expect(assessment.level, ProductCompatibilityLevel.incompatible,
          reason: 'un Mid BMX no entra en una caja inglesa');
    });

    test('reads a modern press-fit shell named by its code', () async {
      // El vocabulario chileno nombra estas cajas por su codigo — `BB86 / BB92
      // 41 mm`, `BB386EVO 46 mm` — y nunca con la palabra «pressfit», que era
      // lo unico que el canonicalizador sabia buscar.
      final assessment = await _assessProduct(
        technicalFamily: 'bottom_bracket',
        bikeTechnicalValues: const <String, dynamic>{
          'bottomBracketFamily': 'Pressfit',
          'bbShellWidthMm': 92,
        },
        productSpecs: const <String, dynamic>{
          'bb_shell_standard': 'BB86 / BB92 41 mm',
          'bb_shell_width_mm': 92,
        },
      );

      expect(assessment.level, isNot(ProductCompatibilityLevel.incompatible),
          reason: 'BB92 es una caja a presión y la bici tambien');
    });

    test(
        'keeps crankset matches in caution while chainline and mounting seams stay unresolved',
        () async {
      final assessment = await _assessProduct(
        technicalFamily: 'crankset',
        bikeTechnicalValues: const <String, dynamic>{
          'drivetrainConfig': '1x1',
          'bottomBracketFamily': 'Mid / BMX',
          'bbShellWidthMm': 68,
          'spindleInterface': 'BMX 19 mm',
        },
        productSpecs: const <String, dynamic>{
          'bottom_bracket_family': 'Mid / BMX',
          'bb_shell_width_mm': 68,
          'spindle_interface': 'BMX 19 mm',
          'front_chainring_count': ['1'],
        },
      );

      expect(assessment.level, ProductCompatibilityLevel.caution);
      expect(assessment.detail, contains('Mid / BMX'));
      expect(assessment.detail, contains('1x'));
      expect(assessment.detail, contains('línea de cadena'));
      expect(assessment.detail, contains('estándar real del crankset'));
    });

    test('still rejects exact shifter actuation mismatch at service level',
        () async {
      final assessment = await _assessProduct(
        technicalFamily: 'shifter',
        bikeTechnicalValues: const <String, dynamic>{
          'drivetrainConfig': '1x12',
          'drivetrainSpeeds': 12,
          'shiftActuationFamily': 'Shimano Dynasys 11/12',
        },
        productSpecs: const <String, dynamic>{
          'shifter_position': 'right',
          'drivetrain_speeds': ['12'],
          'shift_actuation_family': 'SRAM X-Actuation',
        },
      );

      expect(assessment.level, ProductCompatibilityLevel.incompatible);
      expect(assessment.detail, contains('SRAM X-Actuation/Eagle'));
      expect(assessment.detail, contains('Shimano Dynasys 11/12v'));
    });

    test(
        'keeps cassette matches in caution while body and range seams remain unresolved',
        () async {
      final assessment = await _assessProduct(
        technicalFamily: 'cassette',
        bikeTechnicalValues: const <String, dynamic>{
          'drivetrainConfig': '1x12',
          'drivetrainSpeeds': 12,
          'freehubType': 'Microspline',
        },
        productSpecs: const <String, dynamic>{
          'drivetrain_speeds': ['12'],
          'freehub_type': 'Microspline',
        },
      );

      expect(assessment.level, ProductCompatibilityLevel.caution);
      expect(assessment.detail, contains('12v'));
      expect(assessment.detail, contains('Micro Spline'));
      expect(assessment.detail, contains('rango/piñón mayor'));
    });

    test('still rejects cassette/freehub mismatch at service level', () async {
      final assessment = await _assessProduct(
        technicalFamily: 'cassette',
        bikeTechnicalValues: const <String, dynamic>{
          'drivetrainConfig': '1x12',
          'drivetrainSpeeds': 12,
          'freehubType': 'Microspline',
        },
        productSpecs: const <String, dynamic>{
          'drivetrain_speeds': ['12'],
          'freehub_type': 'Shimano HG',
        },
      );

      expect(assessment.level, ProductCompatibilityLevel.incompatible);
      expect(assessment.detail, contains('Shimano HG'));
      expect(assessment.detail, contains('Micro Spline'));
    });

    test(
        'keeps threaded freewheel matches in caution while range details stay unresolved',
        () async {
      final assessment = await _assessProduct(
        technicalFamily: 'freewheel',
        bikeTechnicalValues: const <String, dynamic>{
          'drivetrainConfig': '1x7',
          'drivetrainSpeeds': 7,
          'freehubType': 'Roscada / rueda libre',
        },
        productSpecs: const <String, dynamic>{
          'drivetrain_speeds': ['7'],
          'freehub_type': 'Roscada / rueda libre',
        },
      );

      expect(assessment.level, ProductCompatibilityLevel.caution);
      expect(assessment.detail, contains('7v'));
      expect(assessment.detail, contains('roscada'));
    });

    test(
        'keeps cassette spacer guidance in caution with body-generation review',
        () async {
      final assessment = await _assessProduct(
        technicalFamily: 'cassette_spacer',
        bikeTechnicalValues: const <String, dynamic>{
          'drivetrainConfig': '1x11',
          'drivetrainSpeeds': 11,
          'freehubType': 'Shimano HG',
        },
        productSpecs: const <String, dynamic>{
          'freehub_type': 'Shimano HG',
          'spacer_thickness_mm': 1.85,
        },
      );

      expect(assessment.level, ProductCompatibilityLevel.caution);
      expect(assessment.detail, contains('generacion del cuerpo'));
      expect(assessment.detail, contains('espesor'));
    });

    test(
        'keeps rear hub matches in caution while rear body semantics stay unresolved',
        () async {
      final assessment = await _assessProduct(
        technicalFamily: 'rear_hub',
        bikeTechnicalValues: const <String, dynamic>{
          'rearSpokeHoles': 32,
          'freehubType': 'Shimano HG Road 11',
        },
        productSpecs: const <String, dynamic>{
          'wheel_position': 'rear',
          'hub_spacing_mm': 148,
          'spoke_holes': 32,
          'freehub_type': 'Shimano HG Road 11',
        },
        bikeRearHubSpacingMm: 148,
      );

      expect(assessment.level, ProductCompatibilityLevel.caution);
      expect(assessment.detail, contains('Shimano HG Road 11'));
      expect(assessment.detail, contains('generacion/largo real del cuerpo'));
    });

    test(
        'matching front hub width and hole count cannot approve an unknown axle',
        () async {
      final assessment = await _assessProduct(
        technicalFamily: 'front_hub',
        bikeTechnicalValues: const <String, dynamic>{
          'frontSpokeHoles': 32,
        },
        productSpecs: const <String, dynamic>{
          'wheel_position': 'front',
          'hub_spacing_mm': 100,
          'spoke_holes': 32,
        },
        bikeFrontHubSpacingMm: 100,
      );

      expect(assessment.level, ProductCompatibilityLevel.caution);
      expect(assessment.detail, contains('100 mm'));
      expect(assessment.detail, contains('32H'));
      expect(assessment.detail, contains('eje'));
    });

    test('hub hole mismatch describes the unselected assembly counterpart',
        () async {
      final assessment = await _assessProduct(
        technicalFamily: 'rear_hub',
        bikeTechnicalValues: {'rearSpokeHoles': 36},
        productSpecs: {'wheel_position': 'rear', 'spoke_holes': 32},
      );
      expect(assessment.level, ProductCompatibilityLevel.caution);
      expect(assessment.detail, contains('32H frente a 36H'));
      expect(assessment.detail, contains('confirmar el aro'));
      expect(assessment.detail, contains('eje, retención'));
      expect(assessment.detail, isNot(contains('sirve')));
    });

    test('rim count and label differences retain valve and assembly conditions',
        () async {
      final assessment = await _assessProduct(
        technicalFamily: 'rim',
        bikeTechnicalValues: {'frontSpokeHoles': 32, 'valveType': 'Presta'},
        productSpecs: {
          'spoke_holes': 36,
          'wheel_size': '26"',
          'valve_type': 'Schrader',
        },
      );
      expect(assessment.level, ProductCompatibilityLevel.caution);
      expect(assessment.detail, contains('36H frente a delantera 32H'));
      expect(assessment.detail, contains('confirmar la maza'));
      expect(assessment.detail, contains('BSD'));
      expect(assessment.detail, contains('taladro de válvula'));
      expect(assessment.detail, contains('presión y sistema de freno'));
    });

    for (final family in ['rear_hub', 'rim']) {
      test('$family cannot assign an aggregate count to a wheel', () async {
        final assessment = await _assessProduct(
          technicalFamily: family,
          bikeTechnicalValues: {},
          bikeSpokeCount: 32,
          productSpecs: {'wheel_position': 'rear', 'spoke_holes': 32},
        );
        expect(assessment.level, ProductCompatibilityLevel.caution);
        expect(assessment.detail, contains('32H sin distinguir rueda'));
        expect(assessment.detail, contains('perforaciones de la rueda'));
        expect(assessment.detail, isNot(contains('coincide')));
      });
    }

    test('explicit rear count stays separate from the legacy aggregate',
        () async {
      final assessment = await _assessProduct(
        technicalFamily: 'rear_hub',
        bikeTechnicalValues: {'rearSpokeHoles': 36},
        bikeSpokeCount: 32,
        productSpecs: {'wheel_position': 'rear', 'spoke_holes': 36},
      );
      expect(assessment.level, ProductCompatibilityLevel.caution);
      expect(assessment.detail, contains('coincide 36H'));
      expect(assessment.detail, isNot(contains('32H')));
    });

    test('spoke length and a bicycle count cannot approve an unknown recipe',
        () async {
      final assessment = await _assessProduct(
        technicalFamily: 'spoke',
        bikeTechnicalValues: {'frontSpokeHoles': 32},
        productSpecs: {'spoke_length_mm': 263, 'spoke_gauge': '14G'},
      );
      expect(assessment.level, ProductCompatibilityLevel.caution);
      expect(assessment.detail, contains('ERD y offset'));
      expect(assessment.detail, contains('bridas por lado'));
      expect(assessment.detail, contains('patrón y niple'));
      expect(assessment.detail, contains('delantera 32H'));
    });

    test('hub count caution does not hide a known spacing conflict', () async {
      final assessment = await _assessProduct(
        technicalFamily: 'rear_hub',
        bikeTechnicalValues: {'rearSpokeHoles': 36},
        bikeRearHubSpacingMm: 135,
        productSpecs: {
          'wheel_position': 'rear',
          'spoke_holes': 32,
          'hub_spacing_mm': 148,
        },
      );
      expect(assessment.level, ProductCompatibilityLevel.incompatible);
      expect(assessment.detail, contains('148 mm'));
      expect(assessment.detail, contains('135 mm'));
    });

    test('hub count caution does not hide a known driver conflict', () async {
      final assessment = await _assessProduct(
        technicalFamily: 'rear_hub',
        bikeTechnicalValues: {'rearSpokeHoles': 36, 'freehubType': 'SRAM XD'},
        productSpecs: {
          'wheel_position': 'rear',
          'spoke_holes': 32,
          'freehub_type': 'Shimano HG',
        },
      );
      expect(assessment.level, ProductCompatibilityLevel.incompatible);
      expect(assessment.detail, contains('driver'));
    });

    for (final family in ['rim', 'tube', 'rim_strip', 'tubeless_valve']) {
      test('$family shared wheel or valve labels cannot certify a complete fit',
          () async {
        final assessment = await _assessProduct(
          technicalFamily: family,
          bikeTechnicalValues: {
            'wheelSize': '29"',
            'valveType': 'Presta',
            'frontSpokeHoles': 32,
          },
          productSpecs: {
            'wheel_size': '29"',
            'valve_type': 'Presta',
            'spoke_holes': 32,
          },
        );
        expect(assessment.level, ProductCompatibilityLevel.caution);
        expect(assessment.detail?.toLowerCase(), isNot(contains('compatible')));
      });
    }

    for (final family in ['rim', 'tube', 'rim_strip']) {
      test('$family cannot reject 700C against a 29 inch label alone',
          () async {
        final assessment = await _assessProduct(
          technicalFamily: family,
          productSpecs: {'wheel_size': '700c'},
          bikeTechnicalValues: {},
        );
        expect(assessment.level, ProductCompatibilityLevel.caution);
      });
    }
    test('a different rotor diameter requires configuration review', () async {
      final assessment = await _assessProduct(
        technicalFamily: 'rotor',
        bikeTechnicalValues: {
          'brakeType': 'hydraulic_disc',
          'frontRotorSizeMm': 180,
          'rearRotorSizeMm': 160
        },
        productSpecs: {'rotor_diameter_mm': 203, 'brake_position': 'front'},
      );
      expect(assessment.level, ProductCompatibilityLevel.caution);
      expect(assessment.detail, contains('adaptador'));
    });
    test('installed valve type cannot substitute for rim hole measurements',
        () async {
      final assessment = await _assessProduct(
        technicalFamily: 'tube',
        bikeTechnicalValues: {'valveType': 'Schrader'},
        productSpecs: {'valve_type': 'Presta'},
      );
      expect(assessment.level, ProductCompatibilityLevel.caution);
      expect(assessment.detail, contains('agujero'));
    });

    test('equal rotor diameter cannot approve an unknown mounting interface',
        () async {
      final assessment = await _assessProduct(
        technicalFamily: 'rotor',
        bikeTechnicalValues: {
          'brakeType': 'hydraulic_disc',
          'frontRotorSizeMm': 180,
        },
        productSpecs: {
          'rotor_diameter_mm': 180,
          'brake_position': 'front',
        },
      );
      expect(assessment.level, ProductCompatibilityLevel.caution);
      expect(assessment.detail, contains('montaje'));
      expect(assessment.detail, contains('espesor'));
    });
  });
}

Future<ProductCompatibilityAssessment> _assessProduct({
  required String technicalFamily,
  required Map<String, dynamic> bikeTechnicalValues,
  required Map<String, dynamic> productSpecs,
  double? bikeFrontHubSpacingMm,
  double? bikeRearHubSpacingMm,
  int? bikeSpokeCount,
}) async {
  final product = _buildProduct();
  final service = BikeProductCompatibilityService();
  service.primeCompatibilityCaches(
    productSpecsByProductId: <String, Map<String, dynamic>>{
      product.id: {'__technical_family': technicalFamily, ...productSpecs},
    },
  );

  final assessments = await service.buildAutocompleteAssessments(
    bike: _buildBike(
      frontHubSpacingMm: bikeFrontHubSpacingMm,
      rearHubSpacingMm: bikeRearHubSpacingMm,
      spokeCount: bikeSpokeCount,
    ),
    profile: _buildProfile(bikeTechnicalValues),
    products: <Product>[product],
  );

  expect(assessments, contains(product.id));
  return assessments[product.id]!;
}

Bike _buildBike({
  double? frontHubSpacingMm,
  double? rearHubSpacingMm,
  int? spokeCount,
}) {
  final now = DateTime(2026, 4, 26);
  return Bike(
    id: 'bike-1',
    tenantId: 'tenant-1',
    customerId: 'customer-1',
    brand: 'Trek',
    model: 'Marlin 5',
    wheelSize: '29"',
    bikeType: BikeType.mountainHardtail,
    frontHubSpacingMm: frontHubSpacingMm,
    rearHubSpacingMm: rearHubSpacingMm,
    spokeCount: spokeCount,
    createdAt: now,
    updatedAt: now,
  );
}

BikeProfile _buildProfile(Map<String, dynamic> technicalValues) {
  final now = DateTime(2026, 4, 26);
  return BikeProfile(
    id: 'profile-1',
    tenantId: 'tenant-1',
    bikeId: 'bike-1',
    technicalProfile: <String, dynamic>{
      'values': technicalValues,
    },
    createdAt: now,
    updatedAt: now,
  );
}

Product _buildProduct() {
  final now = DateTime(2026, 4, 26);
  return Product(
    id: 'product-1',
    name: 'Test Product',
    sku: 'TEST-1',
    price: 10000,
    cost: 5000,
    stockQuantity: 3,
    category: ProductCategory.parts,
    categoryId: 'cat-1',
    createdAt: now,
    updatedAt: now,
  );
}
