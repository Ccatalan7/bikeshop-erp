import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_identity_extractor.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_identity_matcher.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_identity_profile.dart';

void main() {
  group('la variante desempata sin reemplazar la evidencia de línea', () {
    test('la opción separa modelo, variante y origen en la forma ENLEE real',
        () {
      const matcher = ProductIdentityMatcher();
      final probe = _profile(
        name: 'Pedal ENLEE CNC',
        sourceTitle:
            'ENLEE-Pedal de bicicleta de una pieza CNC, aleación de aluminio, sello ultraligero Du Bearing BMX Mtb, accesorios para pedales de bicicleta',
        variantText: 'CR-2 black, CHINA',
      );
      final black = _profile(
        name: 'Pedal ENLEE CR-2 Olivia AluminioCNC Negro Sellado',
      );
      final red = _profile(
        name: 'Pedal ENLEE CR-2 Olivia AluminioCNC Rojo Sellado',
      );
      final generic = _profile(name: 'Pedal genérico CNC aluminio negro');

      expect(probe.primaryModelCodes, isEmpty);
      expect(probe.selectedOptionModelCodes, <String>{'cr2'});
      expect(probe.assertedBrand, 'enlee');
      expect(probe.specs[PartSpecKind.colorVariant], 'negro');
      expect(probe.specs[PartSpecKind.constructionMaterial], 'aluminum');
      expect(black.specs[PartSpecKind.constructionMaterial], 'aluminum');

      final blackMatch = matcher.evaluate(probe: probe, candidate: black);
      final redMatch = matcher.evaluate(probe: probe, candidate: red);
      final genericMatch = matcher.evaluate(probe: probe, candidate: generic);
      expect(blackMatch.verdict, IdentityMatchVerdict.strong);
      expect(blackMatch.matchedModelCodes, <String>{'cr2'});
      expect(blackMatch.score, greaterThan(genericMatch.score));
      expect(redMatch.isRejected, isTrue);
      expect(redMatch.variantMismatch, isTrue);
    });

    test('cantidades, medidas y origen de una opción nunca son modelos', () {
      for (final option in <String>[
        'CHINA',
        '32H',
        '104BCD',
        '160mm',
        '5pair 11S',
      ]) {
        final profile = _profile(
          name: 'Pedal ENLEE',
          variantText: option,
        );
        expect(
          profile.selectedOptionModelCodes,
          isEmpty,
          reason: option,
        );
      }
    });

    test('ZTTO: la misma foto gana al color solo y otro color se descarta', () {
      const matcher = ProductIdentityMatcher();
      final blackProbe = _profile(
        name: 'Portabotella ZTTO aluminio',
        sourceTitle:
            'ZTTO MTB ultralight aluminum alloy bottle cage for bicycle',
        variantText: 'BLACK',
      );
      final ae0275 = _profile(
        name: 'Portabotella ZTTO aluminio',
      );
      final ae0123Black = _profile(
        name: 'Portabotella ZTTO aluminio negro',
      );

      final samePhoto = matcher.evaluate(
        probe: blackProbe,
        candidate: ae0275,
        deterministic: const DeterministicIdentityEvidence(
          sameImageIdentity: true,
        ),
      );
      final colorOnly = matcher.evaluate(
        probe: blackProbe,
        candidate: ae0123Black,
      );

      expect(samePhoto.verdict, isNot(IdentityMatchVerdict.exact));
      expect(
        samePhoto.reasons,
        contains('Misma foto de la publicación; no confirma la variante'),
      );
      expect(samePhoto.lineScore, greaterThan(colorOnly.lineScore));
      expect(samePhoto.score, greaterThan(colorOnly.score));

      for (final selectedColor in <String>['BLUE', 'RED']) {
        final selected = _profile(
          name: 'Portabotella ZTTO aluminio',
          sourceTitle:
              'ZTTO MTB ultralight aluminum alloy bottle cage for bicycle',
          variantText: selectedColor,
        );
        final mismatch = matcher.evaluate(
          probe: selected,
          candidate: ae0123Black,
        );
        expect(mismatch.isRejected, isTrue, reason: selectedColor);
        expect(mismatch.variantMismatch, isTrue, reason: selectedColor);
      }
    });

    test('ODI: el color decide sólo cuando la evidencia de línea empata', () {
      const matcher = ProductIdentityMatcher();
      final probe = _profile(
        name: 'Puños ODI-1 135mm',
        variantText: 'UPGRADE-Black',
      );
      final black = matcher.evaluate(
        probe: probe,
        candidate: _profile(name: 'Puños ODI-1 Negros 135mm'),
      );
      final unknown = matcher.evaluate(
        probe: probe,
        candidate: _profile(name: 'Puños ODI-1 135mm'),
      );

      expect(black.isRejected, isFalse);
      expect(unknown.isRejected, isFalse);
      expect(black.lineScore, unknown.lineScore);
      expect(black.variantAgreement, isTrue);
      expect(unknown.variantAgreement, isFalse);
      expect(black.score, greaterThan(unknown.score));
    });
  });

  group('material de construcción tipado', () {
    test('aluminio y plástico explícitos descartan el objeto distinto', () {
      final match = const ProductIdentityMatcher().evaluate(
        probe: _profile(name: 'Portabotella ZTTO de aluminio'),
        candidate: _profile(name: 'Portabotella ZTTO de plástico'),
      );

      expect(match.isRejected, isTrue);
      expect(
        match.gates.where((gate) => gate.failed).map((gate) => gate.id),
        contains('spec:constructionMaterial'),
      );
      expect(match.objections.join(' '), contains('aluminio ≠ plástico'));
    });

    test('material desconocido o de fitment no elimina; WEST sobrevive', () {
      final westProbe = _profile(
        name: 'Portabotella WEST BIKING',
        sourceTitle:
            'WEST BIKING-soporte de botella de agua para bicicleta, soporte para ciclismo MTB',
      );
      final westPlastic = _profile(
        name: 'Porta Caramagiola WEST BIKING plástico',
      );
      final phoneForAluminumBar = _profile(
        name: 'Soporte celular para manillar de aluminio',
      );
      final plasticPhone = _profile(name: 'Soporte celular plástico');

      expect(
        westProbe.specs[PartSpecKind.constructionMaterial],
        isNull,
        reason: 'la fuente exacta WEST no declara aluminio',
      );
      expect(
        const ProductIdentityMatcher()
            .evaluate(probe: westProbe, candidate: westPlastic)
            .isRejected,
        isFalse,
      );
      expect(
        phoneForAluminumBar.specs[PartSpecKind.constructionMaterial],
        isNull,
        reason: 'el aluminio pertenece al manillar compatible, no al soporte',
      );
      expect(
        const ProductIdentityMatcher()
            .evaluate(probe: phoneForAluminumBar, candidate: plasticPhone)
            .isRejected,
        isFalse,
      );
    });
  });
}

ProductIdentityProfile _profile({
  required String name,
  String? sourceTitle,
  String? variantText,
}) {
  return ProductIdentityExtractor.extract(
    ProductIdentityInput(
      name: name,
      sourceTitle: sourceTitle,
      variantText: variantText,
      knownBrands: const <String>['ZTTO', 'ODI', 'WEST BIKING'],
    ),
  );
}
