import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/category_models.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_category_resolver.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_identity_extractor.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_identity_matcher.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_identity_profile.dart';

void main() {
  const matcher = ProductIdentityMatcher();
  final categories = ProductCategoryResolver(categories: _tree);

  ProductIdentityProfile profile({
    required String name,
    String? sourceTitle,
    String? variant,
  }) {
    return ProductIdentityExtractor.extract(
      ProductIdentityInput(
        name: name,
        sourceTitle: sourceTitle,
        variantText: variant,
        knownBrands: const <String>['RISK'],
      ),
    );
  }

  test('ambiguous marketplace keywords cannot silence exact cleaned object',
      () {
    final probe = profile(
      name: 'Terminal de piola aluminio',
      sourceTitle: '100-500pcs MTB Bike Bicycle Brake Shifter Aluminum Inner '
          'Cable Tips Crimps Cycle Cycling Parts Derailleur Shift Cables End '
          'Caps',
      variant: '500pcs',
    ).withVisualReading(
      visualFamilyId: 'cable_housing',
      visualConfidence: 0.92,
    );
    final gold = profile(name: 'Terminal de piola aluminio');
    final shifter = profile(name: 'Shifter Shimano Altus M315 8V');

    expect(probe.supplierTitleFamilyIsAuthoritative, isFalse);
    expect(probe.familyId, 'cable_end_cap');
    expect(probe.effectiveFamilyId, 'cable_end_cap');
    expect(probe.requiresIdentityReview, isFalse);
    expect(
      probe.specs[PartSpecKind.cableEndKind],
      'inner_cable_tip',
    );
    expect(probe.lineSpecs[PartSpecKind.packCount], isNull);
    expect(probe.variantSpecs[PartSpecKind.packCount], '500');
    expect(matcher.evaluate(probe: probe, candidate: gold).isRejected, isFalse);
    expect(
      matcher.evaluate(probe: probe, candidate: shifter).isRejected,
      isTrue,
    );
    expect(
      categories.resolve(probe).category?.fullPath,
      'Componentes / Fundas y piolas / Terminales y topes',
    );
  });

  test('localized cable-end SEO title cannot become a rear derailleur', () {
    const source = 'Marchas de freno para bicicleta de montaña y carretera, '
        'tapas de extremos de Cable exterior, Crimps, desviador de cambio, '
        'carcasa de punta de Cable, 100-500 piezas';
    final probe = profile(
      name: 'Desviador trasero genérico',
      sourceTitle: source,
      variant: '500PCS',
    );
    final gold = profile(name: 'Tope de funda para cambio 500pcs');
    final derailleur = profile(name: 'Desviador trasero Shimano M5100');

    expect(probe.familyId, 'cable_end_cap');
    expect(probe.supplierTitleFamilyIsAuthoritative, isFalse);
    expect(
      probe.specs[PartSpecKind.cableEndKind],
      'housing_ferrule',
    );
    expect(probe.lineSpecs[PartSpecKind.packCount], isNull);
    expect(probe.variantSpecs[PartSpecKind.packCount], '500');
    expect(matcher.evaluate(probe: probe, candidate: gold).isRejected, isFalse);
    expect(
      matcher.evaluate(probe: probe, candidate: derailleur).isRejected,
      isTrue,
    );
    expect(
      categories.resolve(probe).category?.fullPath,
      'Componentes / Fundas y piolas / Terminales y topes',
    );

    final catalogPack = profile(name: 'Tope de funda para cambio 500pcs');
    expect(
      catalogPack.specs[PartSpecKind.cableEndKind],
      'housing_ferrule',
    );
  });

  test('a real derailleur stays a derailleur when it includes a cable', () {
    final profileWithIncludedCable = profile(
      name: 'Desviador trasero Shimano M5100',
      sourceTitle: 'Desviador trasero Shimano M5100 con cable incluido',
    );

    expect(profileWithIncludedCable.familyId, 'derailleur');
    expect(profileWithIncludedCable.supplierTitleFamilyIsAuthoritative, isTrue);
  });

  test('shift and brake ferrules eliminate each other by typed system/spec',
      () {
    final shift = profile(
      name: 'Capuchón piola cambio RISK Basic 4mm',
      sourceTitle: '20/100 pcs Bicycle Basic Cable End Caps 4mm Shift 5mm '
          'Brake Cable Cover',
      variant: 'Shift Cap100pcs',
    );
    final brake = profile(
      name: 'Terminal de piola freno RISK 5mm',
      sourceTitle: '20/100 pcs Bicycle Basic Cable End Caps 4mm Shift 5mm '
          'Brake Cable Cover',
      variant: 'Brake Cap100pcs',
    );

    expect(shift.familyId, 'cable_end_cap');
    expect(shift.specs[PartSpecKind.cableSystem], 'shift');
    expect(shift.specs[PartSpecKind.cableHousingDiameterMm], '4');
    expect(brake.specs[PartSpecKind.cableSystem], 'brake');
    expect(brake.specs[PartSpecKind.cableHousingDiameterMm], '5');
    expect(matcher.evaluate(probe: shift, candidate: brake).isRejected, isTrue);
    expect(matcher.evaluate(probe: brake, candidate: shift).isRejected, isTrue);
  });

  test('specific tool head dominates class catch-alls but not real SEO peers',
      () {
    const source = 'Extractor de núcleo de válvula de varilla de extensión de '
        'bicicleta multifunción, herramienta de desmontaje de llave de válvula '
        'de aire antideslizante para MTB y carretera';
    final sourceSpecific =
        profile(name: 'Producto multiuso', sourceTitle: source);
    final live = profile(name: 'Extractor válvula TOOPRE', sourceTitle: source);
    final genericOnly = profile(name: 'Herramienta multiuso 8 en 1');
    final crossClass = profile(
      name: 'Pedal universal',
      sourceTitle: 'Herramienta multiuso pedal bicicleta',
    );
    final fitment = profile(
      name: 'Alicate para extractor de núcleo de válvula',
    );

    expect(sourceSpecific.familyCandidates, <String>{'valve_core_tool'});
    expect(sourceSpecific.supplierTitleFamilyIsAuthoritative, isTrue);
    expect(sourceSpecific.familyId, 'valve_core_tool');
    expect(live.familyId, 'valve_core_tool');
    expect(genericOnly.familyId, 'tool');
    expect(crossClass.supplierTitleFamilyIsAuthoritative, isFalse);
    expect(crossClass.familyId, 'pedal');
    expect(fitment.familyId, 'tool');
  });

  test('applicator capacity is typed, never a model or sports bottle', () {
    final probe = profile(
      name: 'Botella aplicadora 120ml',
      sourceTitle: '2/5/10pcs 30/60/100/120ML Squeeze Bottle for Sauce '
          'Plastic Squirt Container Refillable Bottle with Cap for Kitchen '
          'Glue Container',
      variant: '10pcs of 120ML',
    );
    final gold = profile(name: 'Botella aplicadora 120ml');
    final otherCapacity = profile(name: 'Botella aplicadora 250ml');
    final sportsBottle = profile(name: 'Botella de agua ThinkRider 750ml');
    final unrelated = profile(name: 'Pedal genérico 120ml');

    expect(probe.familyId, 'applicator_bottle');
    expect(probe.specs[PartSpecKind.capacityMl], '120');
    expect(probe.specs[PartSpecKind.packCount], '10');
    expect(probe.lineSpecs[PartSpecKind.packCount], isNull);
    expect(probe.variantSpecs[PartSpecKind.packCount], '10');
    expect(probe.modelCodes, isNot(contains('120ml')));
    expect(gold.modelCodes, isNot(contains('120ml')));
    expect(sportsBottle.specs[PartSpecKind.capacityMl], '750');
    expect(sportsBottle.modelCodes, isNot(contains('750ml')));
    expect(unrelated.specs[PartSpecKind.capacityMl], isNull);
    expect(matcher.evaluate(probe: probe, candidate: gold).isRejected, isFalse);
    expect(
      matcher.evaluate(probe: probe, candidate: otherCapacity).isRejected,
      isTrue,
    );
    expect(
      matcher.evaluate(probe: probe, candidate: sportsBottle).isRejected,
      isTrue,
    );
    expect(
      categories.resolve(probe).category?.fullPath,
      'Herramientas / Botellas aplicadoras',
    );
  });
}

final _tree = <Category>[
  _category('components', 'Componentes', 'Componentes', 0),
  _category(
    'cables',
    'Fundas y piolas',
    'Componentes / Fundas y piolas',
    1,
    parent: 'components',
  ),
  _category(
    'ends',
    'Terminales y topes',
    'Componentes / Fundas y piolas / Terminales y topes',
    2,
    parent: 'cables',
  ),
  _category('tools', 'Herramientas', 'Herramientas', 0),
  _category(
    'applicators',
    'Botellas aplicadoras',
    'Herramientas / Botellas aplicadoras',
    1,
    parent: 'tools',
  ),
];

Category _category(
  String id,
  String name,
  String fullPath,
  int level, {
  String? parent,
}) {
  return Category(
    id: id,
    tenantId: 'tenant-test',
    name: name,
    fullPath: fullPath,
    parentId: parent,
    level: level,
  );
}
