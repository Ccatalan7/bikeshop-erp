import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/category_models.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_category_resolver.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_identity_extractor.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_identity_profile.dart';

void main() {
  late ProductCategoryResolver resolver;

  setUp(() {
    resolver = ProductCategoryResolver(categories: _catalogTree);
  });

  ProductIdentityProfile aliExpressProfile({
    required String name,
    required String sourceTitle,
    String? selectedOption,
  }) {
    return ProductIdentityExtractor.extract(
      ProductIdentityInput(
        // This mirrors ProductDuplicateMatcherService: the selected variant
        // is placed beside the readable name and the supplier title remains
        // available as provenance-bearing source plus noisy description.
        name: selectedOption == null ? name : '$name ~ $selectedOption',
        description: sourceTitle,
        sourceTitle: sourceTitle,
      ),
    );
  }

  group('2024-12-20 object families', () {
    test('phone holder is a phone mount, never the handlebar it fits', () {
      const sourceTitle =
          'Soporte de teléfono para bicicleta, accesorio de aleación de '
          'aluminio con rotación de 360 °, GPS, para manillar de motocicleta '
          'y Scooter (Black A)';
      final profile = aliExpressProfile(
        name: 'Soporte celular aluminio 360°',
        sourceTitle: sourceTitle,
        selectedOption: 'Black A',
      );

      expect(profile.familyId, 'phone_mount');
      expect(profile.familyCandidates, isNot(contains('handlebar')));
      expect(
        resolver.resolve(profile).category?.fullPath,
        'Accesorios / Soporte Celular',
      );
    });

    test('water-bottle holder is the cage, not the contained bottle', () {
      const sourceTitle =
          'WEST BIKING-soporte de botella de agua para bicicleta, soporte de '
          'botella de agua ultraligero para ciclismo de montaña y carretera, '
          'gradiente de colores (Black)';
      final profile = aliExpressProfile(
        name: 'Portabotella WEST BIKING',
        sourceTitle: sourceTitle,
        selectedOption: 'Black',
      );

      expect(profile.familyId, 'bottle_cage');
      expect(profile.familyCandidates, isNot(contains('bottle')));
      expect(
        resolver.resolve(profile).category?.fullPath,
        'Accesorios / Porta Caramagiola',
      );
    });

    for (final option in const <String>['BLUE', 'RED', 'BLACK']) {
      test('joined plural portabotellas remains a cage ($option)', () {
        const sourceTitle =
            'ZTTO MTB ultraligero de aleación de aluminio portabotellas para '
            'bicicleta de montaña y carretera portabotellas accesorios para '
            'bicicleta';
        final profile = aliExpressProfile(
          name: 'Portabotellas ZTTO aluminio',
          sourceTitle: '$sourceTitle ($option)',
          selectedOption: option,
        );

        expect(profile.familyId, 'bottle_cage');
        expect(profile.familyCandidates, isNot(contains('bottle')));
        expect(
          resolver.resolve(profile).category?.fullPath,
          'Accesorios / Porta Caramagiola',
        );
      });
    }

    test('MT200 is the complete hydraulic assembly and selected rear wins', () {
      const sourceTitle =
          'Shimano MT200 parte de freno de bicicleta, solo trasero, delantero, '
          'lado derecho, lado izquierdo, freno de disco hidráulico para '
          'bicicleta de montaña (MT200 Right Rear)';
      final profile = aliExpressProfile(
        name: 'Freno hidráulico Shimano MT200 trasero',
        sourceTitle: sourceTitle,
        selectedOption: 'MT200 Right Rear',
      );

      expect(profile.familyId, 'hydraulic_brake_assembly');
      expect(profile.familyCandidates, isNot(contains('brake_caliper')));
      expect(profile.specs[PartSpecKind.position], 'rear');
      expect(
        resolver.resolve(profile).category?.fullPath,
        'Componentes / Frenos / Frenos Hidráulicos / '
        'Frenos hidráulicos completos',
      );
    });

    test('an unselected front/rear listing menu remains unknown', () {
      const sourceTitle =
          'Shimano MT200 parte de freno de bicicleta, solo trasero, delantero, '
          'lado derecho, lado izquierdo, freno de disco hidráulico para '
          'bicicleta de montaña (MT200 Right Rear)';
      final profile = aliExpressProfile(
        name: 'Freno hidráulico Shimano MT200',
        sourceTitle: sourceTitle,
      );

      expect(profile.specs[PartSpecKind.position], isNull);
    });
  });

  group('object role beats a related object word', () {
    test('fitment is not promoted when the sold object is unknown', () {
      final profile = ProductIdentityExtractor.extract(
        const ProductIdentityInput(
          name: 'Repuesto universal para caliper de freno',
        ),
      );

      expect(profile.familyId, isNull);
      expect(profile.familyCandidates, isEmpty);
      expect(profile.fitmentText, contains('caliper de freno'));
    });

    test('purge kit does not become the hydraulic brake it services', () {
      final profile = ProductIdentityExtractor.extract(
        const ProductIdentityInput(
          name: 'Kit de purga para freno hidráulico Shimano',
        ),
      );

      expect(profile.familyId, isNull);
      expect(profile.familyCandidates, isEmpty);
    });

    test('an included phone holder does not replace the sold bag', () {
      final profile = ProductIdentityExtractor.extract(
        const ProductIdentityInput(
          name: 'Bolso de manillar con soporte de teléfono de aluminio',
        ),
      );

      expect(profile.familyId, 'bag');
      expect(profile.familyCandidates, isNot(contains('phone_mount')));
    });

    test('hydraulic pads remain pads rather than a complete assembly', () {
      final profile = ProductIdentityExtractor.extract(
        const ProductIdentityInput(
          name: 'Pastillas de freno hidráulico Shimano B05S',
        ),
      );

      expect(profile.familyId, 'brake_pad');
      expect(
        profile.familyCandidates,
        isNot(contains('hydraulic_brake_assembly')),
      );
    });

    test('a hydraulic caliper remains a caliper', () {
      final profile = ProductIdentityExtractor.extract(
        const ProductIdentityInput(
          name: 'Caliper de freno hidráulico Shimano MT200',
        ),
      );

      expect(profile.familyId, 'brake_caliper');
      expect(
        profile.familyCandidates,
        isNot(contains('hydraulic_brake_assembly')),
      );
    });

    for (final example in <String>[
      'Shimano MT200 hydraulic brake caliper',
      'Shimano MT200 hydraulic brake lever',
      'Shimano BH59 hydraulic brake hose',
      'Shimano B05S hydraulic brake pads',
    ]) {
      test('English component is not promoted to a complete brake: $example',
          () {
        final profile = ProductIdentityExtractor.extract(
          ProductIdentityInput(name: example),
        );

        expect(
          profile.familyCandidates,
          isNot(contains('hydraulic_brake_assembly')),
        );
      });
    }
  });
}

final _catalogTree = <Category>[
  _category('components', 'Componentes', 'Componentes', 0),
  _category(
    'brakes',
    'Frenos',
    'Componentes / Frenos',
    1,
    parentId: 'components',
  ),
  _category(
    'hydraulic-brakes',
    'Frenos Hidráulicos',
    'Componentes / Frenos / Frenos Hidráulicos',
    2,
    parentId: 'brakes',
  ),
  _category(
    'complete-hydraulic-brakes',
    'Frenos hidráulicos completos',
    'Componentes / Frenos / Frenos Hidráulicos / '
        'Frenos hidráulicos completos',
    3,
    parentId: 'hydraulic-brakes',
  ),
  _category('accessories', 'Accesorios', 'Accesorios', 0),
  _category(
    'phone-mount',
    'Soporte Celular',
    'Accesorios / Soporte Celular',
    1,
    parentId: 'accessories',
  ),
  _category(
    'bottle-cage',
    'Porta Caramagiola',
    'Accesorios / Porta Caramagiola',
    1,
    parentId: 'accessories',
  ),
];

Category _category(
  String id,
  String name,
  String fullPath,
  int level, {
  String? parentId,
}) {
  return Category(
    id: id,
    tenantId: 'tenant-test',
    name: name,
    fullPath: fullPath,
    parentId: parentId,
    level: level,
  );
}
