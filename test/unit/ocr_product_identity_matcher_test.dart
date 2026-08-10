import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/category_models.dart';
import 'package:vinabike_erp/modules/inventory/models/inventory_models.dart';
import 'package:vinabike_erp/modules/inventory/models/product_duplicate_candidate.dart';
import 'package:vinabike_erp/modules/inventory/services/inventory_service.dart'
    as inv_service;
import 'package:vinabike_erp/modules/inventory/services/product_duplicate_matcher_service.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/bike_part_taxonomy.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_catalog_identity_index.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_identity_extractor.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_identity_matcher.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_identity_profile.dart';

/// Every case here comes from AliExpress invoice `AE160326` and the real
/// production catalog it had to be reconciled against. The expectations are
/// the owner's own verdicts on what the previous matcher did wrong, not a
/// snapshot of what the code currently produces.
void main() {
  late List<Product> catalog;
  late Map<String, List<String>> ancestry;

  setUpAll(() {
    final fixture = jsonDecode(
      File('test/fixtures/ocr/production_catalog_subset.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    catalog = (fixture['products'] as List)
        .cast<Map<String, dynamic>>()
        .map(_product)
        .toList(growable: false);
    ancestry = ProductCatalogIdentityIndex.buildCategoryAncestry(_categories);
  });

  ProductDuplicateMatcherService matcher() => ProductDuplicateMatcherService(
        inventoryService: _FakeInventoryService(),
        knownBrands: _knownBrands,
        categoryAncestry: ancestry,
        enableVisualReading: false,
        persistComputedImageFingerprints: false,
      );

  Future<List<ProductDuplicateCandidate>> resolve(
    ProductDuplicateProbe probe,
  ) =>
      matcher().findCandidates(probe: probe, products: catalog);

  group('lo que la factura AE160326 tiene que encontrar', () {
    test('el buje trasero Novatec resuelve al D042SB y a nada más', () async {
      final candidates = await resolve(_novatecHubProbe);

      expect(candidates.first.product.sku, 'AE0062');
      expect(candidates.first.matchTier, ProductDuplicateMatchTier.strong);
      expect(candidates.first.matchedModelCodes, contains('d042sb'));

      final offered = candidates.map((c) => c.product.sku).toSet();
      // El defecto que reportó el dueño: una maza delantera, espaciadores y
      // mazas de otro estándar ofrecidos como coincidencia fuerte.
      expect(offered, isNot(contains('AE0063')), reason: 'es delantera');
      expect(offered, isNot(contains('AE0313')), reason: 'es MicroSpline');
      expect(offered, isNot(contains('AE0311')), reason: 'es MicroSpline');
      expect(offered, isNot(contains('NNV101')), reason: 'es freewheel');
      expect(offered, isNot(contains('AE0230')), reason: 'es marca ARC');
      expect(offered, isNot(contains('370')), reason: 'es un rodamiento');
      expect(offered, isNot(contains('219')), reason: 'es un eje');
      expect(
        candidates
            .where((c) => c.matchTier == ProductDuplicateMatchTier.strong),
        hasLength(1),
        reason: 'sólo una maza puede ser la comprada',
      );
    });

    test('una maza delantera se descarta diciendo por qué', () async {
      final rejected = _evaluateAgainst(
        probe: _novatecHubProbe,
        candidateSku: 'AE0063',
        catalog: catalog,
        ancestry: ancestry,
      );
      expect(rejected, isNotNull);
      expect(rejected!, contains('delantera'));
    });

    test('el volante IXF aparece aunque IXF no exista como marca', () async {
      final candidates = await resolve(_ixfCranksetProbe);

      expect(candidates.first.product.sku, 'AE0093');
      // La marca explícita del título manda sobre la compatibilidad.
      expect(
        candidates.every((c) => (c.product.brand ?? '') != 'Shimano'),
        isTrue,
        reason: '«Compatible con SHIMANO/SRAM» no es marca Shimano',
      );
      // La diferencia real se dice, no se esconde.
      expect(
        candidates.first.objections.join(' '),
        contains('36T'),
      );
      // Una biela suelta no es un volante.
      final offered = candidates.map((c) => c.product.sku).toSet();
      expect(offered.intersection({'3181', '17363', '6627', '997'}), isEmpty);
    });

    test('RT56 recupera RT56 y no un rotor Shimano cualquiera', () async {
      final candidates = await resolve(_rt56Probe);

      expect(candidates.first.product.sku, 'AE0155');
      expect(candidates.first.matchTier, ProductDuplicateMatchTier.strong);
      expect(candidates.first.matchedModelCodes, contains('rt56'));

      final others = candidates.skip(1).toList();
      expect(
        others.every((c) => c.matchTier != ProductDuplicateMatchTier.strong),
        isTrue,
        reason: 'SM-RT10, RT26 y el rotor genérico son otros modelos',
      );
      final offered = candidates.map((c) => c.product.sku).toSet();
      expect(offered, isNot(contains('AE0160')), reason: 'es de 180mm');
      expect(offered, isNot(contains('AE0008')), reason: 'es SRAM');
      expect(offered, isNot(contains('AE0349')), reason: 'son pernos');
    });

    test('el adaptador F/V a A/V no se confunde con válvula tubeless',
        () async {
      final candidates = await resolve(_valveAdapterProbe);

      expect(candidates, isNotEmpty);
      expect(candidates.first.product.sku, 'AE0001');
      final offered = candidates.map((c) => c.product.sku).toSet();
      expect(
        offered
            .intersection({'AE0046', 'AE0287', 'AE0152', 'AE0234', 'BPS005'}),
        isEmpty,
        reason: 'una válvula tubeless no es un adaptador de válvula',
      );
      expect(offered, isNot(contains('AE0214')), reason: 'es de freno');
    });

    test('WAKE rojo y morado resuelven cada uno a su variante', () async {
      final red = await resolve(_wakeStemProbe('Red', 'rojo'));
      final purple = await resolve(_wakeStemProbe('Purple', 'morada'));

      expect(red.first.product.sku, 'AE0137');
      expect(purple.first.product.sku, 'AE0138');
      expect(red.first.variantMismatch, isFalse);
      expect(purple.first.variantMismatch, isFalse);

      // Las hermanas siguen visibles, pero dicen que son otro color.
      final redSiblings = red.skip(1).where((c) => c.variantMismatch);
      expect(redSiblings, isNotEmpty);
      expect(
        redSiblings.every((c) => c.objections.join(' ').contains('color')),
        isTrue,
      );
    });

    test('«cortacadena» encuentra «corta cadena»', () async {
      final candidates = await resolve(_chainToolProbe);

      expect(candidates.first.product.sku, 'AE0147');
      final offered = candidates.map((c) => c.product.sku).toSet();
      expect(offered, isNot(contains('AE0121')), reason: 'es guía de cadena');
      expect(offered, isNot(contains('AE0210')), reason: 'es una botella');
    });
  });

  group('métricas del lote completo', () {
    test('top-1 en las siete líneas, sin candidato de otra familia', () async {
      final expected = <String, ProductDuplicateProbe>{
        'AE0137': _wakeStemProbe('Red', 'rojo'),
        'AE0138': _wakeStemProbe('Purple', 'morada'),
        'AE0093': _ixfCranksetProbe,
        'AE0155': _rt56Probe,
        'AE0001': _valveAdapterProbe,
        'AE0062': _novatecHubProbe,
        'AE0147': _chainToolProbe,
      };

      final service = matcher();
      final elapsed = <int>[];
      var top1 = 0;
      var top3 = 0;
      var crossFamily = 0;

      for (final entry in expected.entries) {
        final probeProfile = ProductIdentityExtractor.extract(
          ProductIdentityInput(
            name: entry.value.name,
            description: entry.value.description,
            rawText: entry.value.rawText,
            brandHint: entry.value.brandName,
            modelHint: entry.value.model,
            categoryPath: entry.value.categoryName,
            knownBrands: _knownBrands,
          ),
        );
        final watch = Stopwatch()..start();
        final candidates = await service.findCandidates(
          probe: entry.value,
          products: catalog,
        );
        watch.stop();
        elapsed.add(watch.elapsedMicroseconds);

        final rank = candidates.indexWhere((c) => c.product.sku == entry.key);
        if (rank == 0) top1++;
        if (rank >= 0 && rank < 3) top3++;

        final probeClass = probeProfile.effectivePhysicalClass;
        for (final candidate in candidates) {
          final candidateClass = ProductIdentityExtractor.extract(
            ProductIdentityInput(
              name: candidate.product.name,
              description: candidate.product.description,
              brandHint: candidate.product.brand,
              modelHint: candidate.product.model,
              categoryPath: candidate.product.categoryName,
              knownBrands: _knownBrands,
            ),
          ).effectivePhysicalClass;
          if (candidateClass == PartPhysicalClass.unknown ||
              probeClass == PartPhysicalClass.unknown) {
            continue;
          }
          if (candidateClass != probeClass) crossFamily++;
        }
      }

      expect(top1, 7, reason: 'las siete líneas resuelven en primer lugar');
      expect(top3, 7);
      // La compuerta que pidió el dueño: cero basura ofrecida.
      expect(crossFamily, 0);

      elapsed.sort();
      final p95 =
          elapsed[(elapsed.length * 0.95).floor().clamp(0, elapsed.length - 1)];
      expect(
        p95,
        lessThan(150000),
        reason: 'p95 por línea bajo 150 ms sin red; medido ~7 ms',
      );
    });

    test('no gasta una llamada de IA por candidato', () async {
      final service = matcher();
      for (final probe in <ProductDuplicateProbe>[
        _novatecHubProbe,
        _rt56Probe,
        _ixfCranksetProbe,
      ]) {
        await service.findCandidates(probe: probe, products: catalog);
      }
      expect(service.visualReadingCalls, 0);
    });
  });

  group('compartir familia basta para ser ofrecido', () {
    // El piso absoluto existe para dejar fuera lo NO relacionado. Compartir la
    // familia es justo la prueba de que sí lo está, y la compuerta ya corrió:
    // aplicarle el piso plano escondía una repisa entera de «Postiza» tras
    // «Sin coincidencia fiable» con el producto correcto en el catálogo.
    test('una repisa entera de la misma familia no desaparece', () async {
      final candidates = await resolve(
        const ProductDuplicateProbe(
          name: 'Postiza ZTTO 001',
          description: 'ZTTO-percha Universal para bicicleta de montaña y '
              'carretera, pieza de desviador trasero',
          brandName: 'ZTTO',
        ),
      );
      expect(candidates, isNotEmpty,
          reason: 'el dueño tiene postizas; decir que no hay ninguna es falso');
      expect(
        candidates
            .every((c) => c.gates.any((g) => g.id == 'familia' && !g.failed)),
        isTrue,
      );
    });

    test('pero seguir sin familia común sigue sin ofrecerse', () async {
      final candidates = await resolve(
        const ProductDuplicateProbe(name: 'Producto XZ-9 negro'),
      );
      expect(
        candidates.every((c) => c.matchTier != ProductDuplicateMatchTier.exact),
        isTrue,
      );
    });
  });

  group('dos objetos que comparten palabra siguen siendo dos objetos', () {
    ProductIdentityProfile of(String name, {String? description}) =>
        ProductIdentityExtractor.extract(
          ProductIdentityInput(
            name: name,
            description: description,
            knownBrands: const <String>['ZTTO'],
          ),
        );

    test('una postiza no es la extensión de una postiza', () {
      expect(of('Postiza ZTTO 001').familyId, 'derailleur_hanger');
      expect(
        of('Extensión para Postiza ZTTO').familyId,
        'derailleur_hanger_extender',
      );
      expect(
        ProductIdentityMatcher()
            .evaluate(
              probe: of('Postiza ZTTO 001'),
              candidate: of('Extensión para Postiza ZTTO'),
            )
            .isRejected,
        isTrue,
      );
    });

    test('el extensor del proveedor se lee como extensión, no como postiza',
        () {
      final probe = of(
        'Extensor de postiza ZTTO',
        description: 'ZTTO-extensor de suspensión de desviador trasero para '
            'bicicleta de montaña y carretera',
      );
      expect(probe.familyId, 'derailleur_hanger_extender');
    });
  });

  group('un color en plural es el mismo color', () {
    ProductIdentityProfile of(String name, {String? description}) =>
        ProductIdentityExtractor.extract(
          ProductIdentityInput(name: name, description: description),
        );

    test('«Negros» y «Black» son el mismo color', () {
      expect(
        of('Puños ODI-1 Negros 135mm').specs[PartSpecKind.colorVariant],
        'negro',
      );
      expect(
        of('Puños ODI con bloqueo',
                description: 'ODI-empuñadura de manillar (UPGRADE-Black)')
            .specs[PartSpecKind.colorVariant],
        'negro',
      );
    });

    test('y por eso el par morado deja de empatar con el negro', () {
      final matcher = ProductIdentityMatcher();
      final probe = of('Puños ODI con bloqueo',
          description: 'ODI-empuñadura de manillar (UPGRADE-Black)');
      final black = matcher.evaluate(
        probe: probe,
        candidate: of('Puños ODI-1 Negros 135mm'),
      );
      final purple = matcher.evaluate(
        probe: probe,
        candidate: of('Puños ODI-1 Morados 135mm'),
      );
      expect(black.variantMismatch, isFalse);
      expect(purple.variantMismatch, isTrue);
      expect(black.score, greaterThan(purple.score));
    });
  });

  group('un proveedor no es un fabricante', () {
    // La columna `brand` del catálogo dice a veces dónde se compró, no quién lo
    // hizo. `Postiza AE 001` —el producto real de esta línea— quedaba fuera con
    // «Otro fabricante: Ztto ≠ Aliexpress»: un marketplace peleando contra un
    // fabricante de verdad.
    ProductIdentityProfile profileOf(String name, {String? brandHint}) =>
        ProductIdentityExtractor.extract(
          ProductIdentityInput(
            name: name,
            brandHint: brandHint,
            brandIsAsserted: brandHint != null,
            knownBrands: const <String>['ZTTO', 'Aliexpress', 'Genérico'],
          ),
        );

    for (final placeholder in const <String>[
      'Aliexpress',
      'Genérico',
      'Sin marca',
      'OEM',
      'China',
    ]) {
      test('«$placeholder» no se lee como fabricante', () {
        expect(
            profileOf('Postiza AE 001', brandHint: placeholder).assertedBrand,
            isNull);
      });
    }

    test('y por eso ya no contradice a un fabricante real', () {
      final matcher = ProductIdentityMatcher();
      final probe = profileOf('Postiza ZTTO 001', brandHint: 'ZTTO');
      final catalogRow = profileOf('Postiza AE 001', brandHint: 'Aliexpress');
      final match = matcher.evaluate(probe: probe, candidate: catalogRow);
      expect(match.isRejected, isFalse);
      expect(
        match.objections.join(' '),
        isNot(contains('Aliexpress')),
      );
    });

    test('un fabricante real sí sigue contradiciendo a otro', () {
      final matcher = ProductIdentityMatcher();
      final probe = profileOf('Postiza ZTTO 001', brandHint: 'ZTTO');
      final other = ProductIdentityExtractor.extract(
        const ProductIdentityInput(
          name: 'Postiza Giant 001',
          brandHint: 'Giant',
          brandIsAsserted: true,
          knownBrands: <String>['ZTTO', 'Giant'],
        ),
      );
      expect(
          matcher.evaluate(probe: probe, candidate: other).isRejected, isTrue);
    });
  });

  group('la compuerta saca de la recomendación, no de la vista', () {
    // El operador abre el overlay porque la única respuesta de la fila no le
    // sirvió. Ocultarle ahí todo lo que una compuerta descartó deja dos
    // salidas: aceptar el producto equivocado o crear un duplicado de algo que
    // ya existe — que es justo el fallo que este paso existe para evitar.
    Future<List<ProductDuplicateCandidate>> options(
      ProductDuplicateProbe probe,
    ) =>
        matcher().findCandidates(
          probe: probe,
          products: catalog,
          scope: ProductDuplicateShortlistScope.operatorChoice,
        );

    const rotor = ProductDuplicateProbe(
      name: 'Disco freno Shimano Deore RT56 160MM',
      description: 'rotor de freno de disco para bicicleta',
    );

    test('la fila sigue recomendando sólo lo que pasó las compuertas',
        () async {
      final row = await resolve(rotor);
      expect(row, isNotEmpty);
      expect(
        row.every((candidate) => !candidate.isRuledOut),
        isTrue,
        reason: 'un descartado nunca es una recomendación',
      );
    });

    test('el overlay ofrece además los del mismo tipo que se descartaron',
        () async {
      final row = await resolve(rotor);
      final all = await options(rotor);
      expect(all.length, greaterThanOrEqualTo(row.length));
      final ruledOut = all.where((candidate) => candidate.isRuledOut);
      for (final candidate in ruledOut) {
        expect(candidate.ruledOutReason, isNotNull,
            reason: 'un descarte sin motivo es un descarte que no se entiende');
      }
    });

    test('los descartados van al final, después de lo que sí calza', () async {
      final all = await options(rotor);
      final firstRuledOut = all.indexWhere((c) => c.isRuledOut);
      if (firstRuledOut < 0) return;
      expect(
        all.skip(firstRuledOut).every((candidate) => candidate.isRuledOut),
        isTrue,
      );
    });

    test('el overlay tampoco inventa: nada de otra familia entra', () async {
      final all = await options(rotor);
      for (final candidate in all) {
        final profile = ProductIdentityExtractor.extract(
          ProductIdentityInput(
            name: candidate.product.name,
            knownBrands: _knownBrands,
          ),
        );
        final family = profile.familyId;
        if (family == null) continue;
        expect(
          BikePartTaxonomy.byId(family)?.physicalClass,
          BikePartTaxonomy.byId('brake_rotor')?.physicalClass,
          reason: '${candidate.product.name} no es del mismo sistema',
        );
      }
    });
  });

  group('el nombre del producto manda sobre el cuerpo del anuncio', () {
    // Una publicación de AliExpress vende todas las velocidades desde la misma
    // página. El cuerpo ofrece 6/7/8/9/10/11/12; la variante que se compró dice
    // una sola. Dejar que el menú anulara al nombre volvía todas las
    // velocidades igual de posibles, y un eslabón de 12v aparecía primero para
    // una compra de 9v.
    ProductIdentityProfile profileOf(String name, String description) =>
        ProductIdentityExtractor.extract(
          ProductIdentityInput(name: name, description: description),
        );

    test('la variante elegida gana al menú de la publicación', () {
      final profile = profileOf(
        'Eslabón rápido RISK 9v',
        'juntas de conector de enlace rápido para cadena de bicicleta, '
            '6 7 8 9 10 11 12 velocidades',
      );
      expect(profile.familyId, 'chain_link');
      expect(profile.specs[PartSpecKind.speeds], '9');
    });

    test('sin nombre que decida, el menú sí deja la propiedad desconocida', () {
      final profile = profileOf(
        'Eslabón rápido RISK',
        'para cadena de 9v 10v 11v',
      );
      expect(profile.specs.containsKey(PartSpecKind.speeds), isFalse);
    });

    test('dos valores contradictorios en el propio nombre no deciden nada', () {
      final profile = profileOf('Cassette Shimano 9v 10v', 'repuesto');
      expect(profile.specs.containsKey(PartSpecKind.speeds), isFalse);
    });

    test('un eslabón de otra velocidad queda eliminado, no rankeado', () {
      final matcher = ProductIdentityMatcher();
      final probe = profileOf(
        'Eslabón rápido RISK 9v',
        'conector de enlace rápido para cadena, 6 7 8 9 10 11 12 velocidades',
      );
      final wrongSpeed = ProductIdentityExtractor.extract(
        const ProductIdentityInput(
            name: 'Missinglink RISK 12 V Par (2 piezas)'),
      );
      final rightSpeed = ProductIdentityExtractor.extract(
        const ProductIdentityInput(name: 'Missinglink RISK 9 V Par (2 piezas)'),
      );
      expect(matcher.evaluate(probe: probe, candidate: wrongSpeed).isRejected,
          isTrue);
      expect(matcher.evaluate(probe: probe, candidate: rightSpeed).isRejected,
          isFalse);
    });
  });

  group('una familia que falta es una familia que no elimina', () {
    // El sticker protector de cadena salía como el «parecido» de un eslabón
    // rápido porque ninguna de las dos piezas tenía familia: sin familia no hay
    // compuerta, y compartir la marca y la palabra «cadena» bastaba.
    test('un eslabón rápido y un sticker de cadena son cosas distintas', () {
      final matcher = ProductIdentityMatcher();
      final probe = ProductIdentityExtractor.extract(
        const ProductIdentityInput(
          name: 'Eslabón rápido RISK 9v',
          description: 'conector de enlace rápido para cadena de bicicleta',
        ),
      );
      final sticker = ProductIdentityExtractor.extract(
        const ProductIdentityInput(
          name: 'Risk Sticker protector para cadena de bicicleta',
        ),
      );
      expect(probe.familyId, 'chain_link');
      expect(sticker.familyId, 'surface_protector');
      expect(
        matcher.evaluate(probe: probe, candidate: sticker).isRejected,
        isTrue,
      );
    });

    test('un protector de plato no cae en el cajón de los stickers', () {
      final profile = ProductIdentityExtractor.extract(
        const ProductIdentityInput(name: 'Protector de plato 104BCD aluminio'),
      );
      expect(profile.familyId, 'chainring_guard');
    });
  });

  group('reglas de identidad que no dependen del catálogo', () {
    test('RT56, RT-56 y RT 56 son el mismo modelo', () {
      for (final spelling in const ['RT56', 'RT-56', 'RT 56']) {
        final profile = ProductIdentityExtractor.extract(
          ProductIdentityInput(name: 'Rotor de freno $spelling 160mm'),
        );
        expect(profile.modelCodes, contains('rt56'), reason: spelling);
      }
    });

    test('104BCD y 32H son medidas, nunca modelos', () {
      final crankset = ProductIdentityExtractor.extract(
        const ProductIdentityInput(
          name: 'Volante 104BCD 170mm 36T',
          modelHint: '104BCD',
        ),
      );
      expect(crankset.modelCodes, isEmpty);
      expect(crankset.specs[PartSpecKind.boltCircleMm], '104');
      expect(crankset.specs[PartSpecKind.teeth], '36');

      final hub = ProductIdentityExtractor.extract(
        const ProductIdentityInput(name: 'Maza trasera 32H HG'),
      );
      expect(hub.modelCodes, isEmpty);
      expect(hub.specs[PartSpecKind.spokeCount], '32');
    });

    test('lo que va después de «compatible con» no es la marca', () {
      final profile = ProductIdentityExtractor.extract(
        const ProductIdentityInput(
          name: 'IXF platos y bielas 104BCD compatible con SHIMANO/SRAM',
          brandHint: 'Shimano',
          knownBrands: <String>['Shimano', 'SRAM'],
        ),
      );
      expect(profile.assertedBrand, 'ixf');
      expect(profile.compatibilityBrands, contains('shimano'));
    });

    test('lo que va después de «+» es un accesorio incluido, no la pieza', () {
      final profile = ProductIdentityExtractor.extract(
        const ProductIdentityInput(
          name: 'Volante IXF Integrado Black 170Mm + Motor BSA + Corona 34T',
        ),
      );
      expect(profile.familyId, 'crankset');
    });

    test('un listado de opciones deja la medida en desconocida', () {
      final profile = ProductIdentityExtractor.extract(
        const ProductIdentityInput(
          name: 'Maza Novatec',
          description: 'disponible en 28/32/36 agujeros',
        ),
      );
      expect(profile.specs.containsKey(PartSpecKind.spokeCount), isFalse);
    });

    test('una categoría hoja ambigua no inventa un ancestro', () {
      final map =
          ProductCatalogIdentityIndex.buildCategoryAncestry(_categories);
      expect(map.containsKey('adaptadores'), isFalse);
      expect(map['corta cadena'], ['herramientas', 'corta cadena']);
    });
  });
}

// ── Sondas: las siete líneas reales de la factura AE160326 ────────────────

const _novatecHubProbe = ProductDuplicateProbe(
  name: 'Maza trasera Novatec D042SB 32H HG',
  description:
      'Novatec bujes de bicicleta D041SB D042SB buje libre de acero MTB buje '
      'de bicicleta freno de disco buje de Cassette 28/32/36 agujeros HG SX '
      '8-12 velocidades (Black rear 32H)',
  model: 'D042SB',
  rawText: 'item id 10050084210422',
  categoryName: 'Mazas',
  brandName: 'Novatec',
  supplierName: 'AliExpress',
  cost: 32527,
);

const _ixfCranksetProbe = ProductDuplicateProbe(
  name: 'IXF-platos y bielas para bicicleta 104BCD 170mm 36T compatible con '
      'SHIMANO/SRAM',
  description:
      'IXF-platos y bielas para bicicleta 104BCD, 170mm, manivela ancha y '
      'estrecha, rueda de cadena de disco ovalada/redonda, Compatible con '
      'SHIMANO/SRAM (Black crank BB 36T, 170mm)',
  model: '104BCD',
  rawText: 'item id 10050084658370',
  categoryName: 'Volantes',
  brandName: 'Shimano',
  supplierName: 'AliExpress',
  cost: 36684,
);

const _rt56Probe = ProductDuplicateProbe(
  name: 'Rotor de freno Shimano RT56 160mm 6 pernos',
  description:
      'Rotor de freno de disco de bicicleta RT56 MTB, disco de montaña de 6 '
      'pernos M610 M6000, 160MM (160mm 1pcs)',
  model: 'RT56',
  rawText: 'item id 10050037769267',
  categoryName: 'Rotores',
  brandName: 'Shimano',
  supplierName: 'AliExpress',
  cost: 6859,
);

const _valveAdapterProbe = ProductDuplicateProbe(
  name: 'Adaptador Presta a Schrader',
  description:
      'Adaptador Presta a Schrader para bicicleta, adaptador de válvula de '
      'neumático de bicicleta, conectores de válvula de bomba de bicicleta '
      'dorados de cobre, convertidor F/V a A/V (10 pcs)',
  rawText: 'item id 10050094669679',
  categoryName: 'Válvula Tubeless',
  supplierName: 'AliExpress',
  cost: 2365,
);

const _chainToolProbe = ProductDuplicateProbe(
  name: 'Cortacadena RIDERACE',
  description: 'Herramienta cortacadena de bicicleta RIDERACE',
  rawText: 'item id 10050082146375',
  categoryName: 'Herramientas',
  brandName: 'RideRace',
  supplierName: 'AliExpress',
  cost: 6543,
);

ProductDuplicateProbe _wakeStemProbe(String variant, String spanishColor) {
  return ProductDuplicateProbe(
    name: 'Tee WAKE 31.8mm $spanishColor',
    description:
        'WAKE-vástago ligero de aleación de aluminio para bicicleta de '
        'montaña, pieza de manillar corto para bici de carretera, BMX, DH, '
        '31,8mm ($variant)',
    rawText: 'item id 1005007336672891',
    categoryName: 'Tee',
    brandName: 'Wake',
    supplierName: 'AliExpress',
    cost: 7172,
  );
}

/// Runs one candidate through the matcher alone and returns its stated reason
/// for refusing, or `null` when it was not refused.
String? _evaluateAgainst({
  required ProductDuplicateProbe probe,
  required String candidateSku,
  required List<Product> catalog,
  required Map<String, List<String>> ancestry,
}) {
  final product = catalog.firstWhere((p) => p.sku == candidateSku);
  final matcher = ProductIdentityMatcherHarness(ancestry);
  return matcher.objectionFor(probe, product);
}

/// Thin harness so a test can ask the pure matcher about one pair without
/// going through retrieval.
class ProductIdentityMatcherHarness {
  ProductIdentityMatcherHarness(this.ancestry);

  final Map<String, List<String>> ancestry;

  String? objectionFor(ProductDuplicateProbe probe, Product product) {
    final index = ProductCatalogIdentityIndex(
      knownBrands: _knownBrands,
      categoryAncestry: ancestry,
    )..sync(<Product>[product]);
    final probeProfile = ProductIdentityExtractor.extract(
      ProductIdentityInput(
        name: probe.name,
        description: probe.description,
        rawText: probe.rawText,
        brandHint: probe.brandName,
        modelHint: probe.model,
        categoryPath: probe.categoryName,
        knownBrands: _knownBrands,
      ),
    );
    final match = ProductIdentityMatcher(categoryAncestry: ancestry).evaluate(
      probe: probeProfile,
      candidate: index.profileOfProduct(product),
    );
    return match.isRejected ? match.objections.join(' · ') : null;
  }
}

const _knownBrands = <String>[
  'Shimano',
  'Novatec',
  'Wake',
  'RideRace',
  'Deemount',
  'ZTTO',
  'Meroca',
  'MUQZI',
  'IceToolz',
  'Genérico',
  'Eclipse',
  'Hailin',
  'Andes Industrial',
  'Toopre',
  'Mana',
  'Wistio',
  'Cyclami',
];

final _categories = <Category>[
  _category('Tee', 'Componentes / Dirección / Tee', 2),
  _category('Rotores', 'Componentes / Frenos / Rotores', 2),
  _category('Rotor BMX', 'Componentes / Frenos / Rotor BMX', 2),
  _category('Mazas', 'Componentes / Ruedas / Mazas', 2),
  _category('Maza', 'Componentes / Ruedas / Mazas / Maza', 3),
  _category(
    'Válvula Tubeless',
    'Componentes / Ruedas / Tubeless / Válvula Tubeless',
    3,
  ),
  _category('Volantes', 'Componentes / Transmisión / Volantes', 2),
  _category('Volante', 'Componentes / Transmisión / Volantes / Volante', 3),
  _category('Herramientas', 'Herramientas', 0),
  _category('Corta Cadena', 'Herramientas / Corta Cadena', 1),
  // Deliberadamente ambigua: existe en tres ramas distintas en producción.
  _category('Adaptadores', 'Accesorios / Adaptadores', 1),
  _category('Adaptadores', 'Componentes / Frenos / Adaptadores', 2),
  _category('Adaptadores', 'Viñabike / Adaptadores', 1),
];

Category _category(String name, String fullPath, int level) => Category(
      id: fullPath,
      tenantId: 'tenant-test',
      name: name,
      fullPath: fullPath,
      level: level,
    );

Product _product(Map<String, dynamic> json) => Product(
      id: json['sku'] as String,
      tenantId: 'tenant-test',
      sku: (json['sku'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      brand: json['brand'] as String?,
      model: json['model'] as String?,
      categoryName: json['category_name'] as String?,
      supplierCode: json['supplier_code'] as String?,
      supplierName: json['supplier_name'] as String?,
      price: 1000,
      cost: 500,
    );

class _FakeInventoryService implements inv_service.InventoryService {
  @override
  bool isAliExpressSupplierName(String? supplierName) {
    final normalized = (supplierName ?? '').toLowerCase();
    return normalized.contains('aliexpress') ||
        normalized.contains('ali express');
  }

  @override
  Future<void> storeProductImageFingerprint({
    required String productId,
    required Map<String, dynamic> imageFingerprint,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
