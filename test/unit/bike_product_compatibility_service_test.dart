import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bike_product_compatibility_service.dart';
import 'package:vinabike_erp/shared/models/product.dart';
import 'package:vinabike_erp/shared/models/product_compatibility.dart';

void main() {
  group('BikeProductCompatibilityService', () {
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

        expect(assessment.level, ProductCompatibilityLevel.compatible);
        expect(assessment.detail, contains('12v'));
        expect(assessment.detail, isNot(contains('no coincide')));
      },
    );

    test('still rejects an exact mismatched chain platform at service level',
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
          'drivetrain_platform': 'SRAM Eagle',
        },
      );

      expect(assessment.level, ProductCompatibilityLevel.incompatible);
      expect(assessment.detail, contains('SRAM Eagle'));
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

    test('keeps exact right shifter match as compatible', () async {
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

      expect(assessment.level, ProductCompatibilityLevel.compatible);
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

    test('treats universal shifter matches like pair and keeps them in caution',
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
      expect(assessment.detail, contains('10v'));
      expect(assessment.detail, contains('2x'));
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
        'still keeps matched front hubs compatible when the structured hub facts line up',
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

      expect(assessment.level, ProductCompatibilityLevel.compatible);
      expect(assessment.detail, contains('100 mm'));
      expect(assessment.detail, contains('32H'));
    });
  });
}

Future<ProductCompatibilityAssessment> _assessProduct({
  required String technicalFamily,
  required Map<String, dynamic> bikeTechnicalValues,
  required Map<String, dynamic> productSpecs,
  double? bikeFrontHubSpacingMm,
  double? bikeRearHubSpacingMm,
}) async {
  final product = _buildProduct();
  final service = BikeProductCompatibilityService();
  service.primeCompatibilityCaches(
    productSpecsByProductId: <String, Map<String, dynamic>>{
      product.id: productSpecs,
    },
    categoryMappingsByCategoryId: <String,
        BikeProductCompatibilityCategoryMappingSeed?>{
      product.categoryId!: BikeProductCompatibilityCategoryMappingSeed(
        technicalFamily: technicalFamily,
      ),
    },
  );

  final assessments = await service.buildAutocompleteAssessments(
    bike: _buildBike(
      frontHubSpacingMm: bikeFrontHubSpacingMm,
      rearHubSpacingMm: bikeRearHubSpacingMm,
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
