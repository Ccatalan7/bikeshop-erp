import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_service.dart';
import 'package:vinabike_erp/modules/inventory/models/category_models.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_category_resolver.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_identity_extractor.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_identity_profile.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_visual_reading.dart';

/// Categorisation is object-first. These cases prove that a relational word —
/// the system a part serves, what it is compatible with, what it sits next to —
/// cannot become the object's identity, and that a system node is never a
/// product's category. They are written as a family of cases on purpose: the
/// owner's `Herradura` filed under `Frenos` was one symptom of both rules
/// missing, not a missing synonym.
void main() {
  late ProductCategoryResolver resolver;

  setUp(() => resolver = ProductCategoryResolver(categories: _tree));

  ProductIdentityProfile profileOf(
    String name, {
    String? description,
    String? visualFamilyId,
    double visualConfidence = 0,
  }) {
    final base = ProductIdentityExtractor.extract(
      ProductIdentityInput(name: name, description: description),
    );
    if (visualFamilyId == null) return base;
    return base.withVisualReading(
      visualFamilyId: visualFamilyId,
      visualConfidence: visualConfidence,
    );
  }

  group('una palabra relacional no secuestra la categoría', () {
    test('una herradura de freno V-Brake es una herradura', () {
      final resolution = resolver.resolve(
        profileOf('HERRADURA FRENO V-BRAKE ALUMINIO HJ-612AD7 DEL/TRA'),
      );
      expect(resolution.category?.fullPath,
          'Componentes / Frenos / V-Brake / Herraduras');
    });

    test('un rotor de freno es un rotor, no «Frenos»', () {
      final resolution = resolver.resolve(
        profileOf('Disco freno Shimano Deore RT56 160MM'),
      );
      expect(resolution.category?.fullPath, 'Componentes / Frenos / Rotores');
    });

    test('una pastilla de freno es una pastilla', () {
      final resolution = resolver.resolve(
        profileOf('Pastillas de freno resina DS01S'),
      );
      expect(resolution.category?.fullPath, 'Componentes / Frenos / Pastillas');
    });

    test('«compatible con freno de disco» no hace de una maza un freno', () {
      final resolution = resolver.resolve(
        profileOf(
          'Maza Trasera Novatec 32H 135x10mm HG D042SB',
          description: 'buje de bicicleta compatible con freno de disco',
        ),
      );
      expect(
          resolution.category?.fullPath, 'Componentes / Ruedas / Mazas / Maza');
    });

    test('un extractor de bielas es herramienta, no transmisión', () {
      final resolution = resolver.resolve(
        profileOf('Extractor de bielas IceToolz para OCTALINK'),
      );
      expect(resolution.category?.fullPath, 'Herramientas / Extractores');
    });

    test('una cinta de llanta no es una llanta', () {
      final resolution = resolver.resolve(
        profileOf('Cinta de llanta 29 tubeless 25mm'),
      );
      expect(resolution.category?.fullPath,
          'Componentes / Ruedas / Cintas de llanta');
    });
  });

  group('un nodo de sistema nunca es la categoría de un producto', () {
    test('«Frenos» tiene hijos y por eso no es asignable', () {
      final frenos = _tree.firstWhere((c) => c.id == 'frenos');
      expect(resolver.isSystemNode(frenos), isTrue);
    });

    test('ninguna resolución devuelve un nodo con hijos', () {
      for (final name in const <String>[
        'HERRADURA FRENO V-BRAKE ALUMINIO',
        'Disco freno Shimano RT56 160MM',
        'Pastillas de freno resina',
        'Corta cadena RiderAce',
        'Maza Trasera Novatec 32H',
      ]) {
        final category = resolver.resolve(profileOf(name)).category;
        if (category == null) continue;
        expect(
          resolver.isSystemNode(category),
          isFalse,
          reason: '$name terminó en un nodo de sistema',
        );
      }
    });
  });

  group('falla cerrado en vez de inventar una hoja plausible', () {
    test('sin objeto reconocido no asigna nada', () {
      final resolution = resolver.resolve(profileOf('Producto XZ-9 negro'));
      expect(resolution.isResolved, isFalse);
      expect(resolution.refusal, ProductCategoryRefusal.unknownObject);
      expect(resolution.reviewReason, contains('a mano'));
    });

    test('una hoja ambigua se manda a revisión', () {
      final resolution = resolver.resolve(
        profileOf('Adaptador de válvula Presta a Schrader'),
      );
      expect(resolution.isResolved, isFalse);
      expect(resolution.refusal, ProductCategoryRefusal.ambiguousLeaf);
      expect(resolution.evidence.join(' '), contains('Accesorios'));
    });

    test('una familia sin hoja en este catálogo se dice, no se aproxima', () {
      final resolution = resolver.resolve(profileOf('Casco MTB Rockbros'));
      expect(resolution.isResolved, isFalse);
      expect(resolution.refusal, ProductCategoryRefusal.noCanonicalLeaf);
      expect(resolution.reviewReason, contains('No existe una categoría'));
    });
  });

  group('la foto y el título se reconcilian, no se ignoran', () {
    test('una foto segura corrige un título que nombró el sistema vecino', () {
      final resolution = resolver.resolve(
        profileOf(
          'Repuesto para caliper de freno aluminio',
          visualFamilyId: 'rim_brake_arm',
          visualConfidence: 0.92,
        ),
      );
      expect(resolution.category?.fullPath,
          'Componentes / Frenos / V-Brake / Herraduras');
      expect(resolution.evidence.first, contains('La foto'));
    });

    test('una foto dudosa que contradice al título manda a revisión', () {
      final resolution = resolver.resolve(
        profileOf(
          'Pastillas de freno resina',
          visualFamilyId: 'hub',
          visualConfidence: 0.45,
        ),
      );
      expect(resolution.isResolved, isFalse);
      expect(resolution.refusal, ProductCategoryRefusal.conflictingEvidence);
      expect(resolution.reviewReason, contains('cosas distintas'));
    });

    test('foto y título de acuerdo no piden revisión', () {
      final profile = profileOf(
        'Pastillas de freno resina',
        visualFamilyId: 'brake_pad',
        visualConfidence: 0.9,
      );
      expect(profile.familyEvidenceConflicts, isFalse);
      expect(profile.requiresIdentityReview, isFalse);
      expect(resolver.resolve(profile).isResolved, isTrue);
    });

    test('una foto floja no manda a revisión una fila sana', () {
      final profile = profileOf(
        'Pastillas de freno resina',
        visualFamilyId: 'hub',
        visualConfidence: 0.2,
      );
      expect(profile.familyEvidenceConflicts, isFalse);
      expect(profile.requiresIdentityReview, isFalse);
      expect(
        resolver.resolve(profile).category?.fullPath,
        'Componentes / Frenos / Pastillas',
      );
    });

    test('el texto no puede suprimir a la visión', () {
      // La regla general: un familyId de texto NO nulo pero equivocado ya no
      // impide que la foto se lea ni que contradiga.
      final wrongText = profileOf(
        'Repuesto para caliper de freno aluminio',
        visualFamilyId: 'rim_brake_arm',
        visualConfidence: 0.92,
      );
      expect(wrongText.familyId, isNotNull);
      expect(wrongText.effectiveFamilyId, 'rim_brake_arm');
    });
  });

  group('la lectura visual se mapea a la taxonomía', () {
    test('un tipo primario visual se resuelve a su familia', () {
      final reading = ProductVisualReadingService.fromAnalysis(
        const AIProductImageAnalysis(
          primaryType: 'herradura v-brake',
          catalogTerms: <String>['herradura', 'freno', 'v-brake'],
          excludedTerms: <String>['rotor'],
          confidence: 0.88,
        ),
      );
      expect(reading.familyId, 'rim_brake_arm');
      expect(reading.confidence, 0.88);
    });

    test('un tipo visual irreconocible no inventa familia', () {
      final reading = ProductVisualReadingService.fromAnalysis(
        const AIProductImageAnalysis(
          primaryType: 'objeto metalico',
          catalogTerms: <String>['metal', 'negro'],
          excludedTerms: <String>[],
          confidence: 0.4,
        ),
      );
      expect(reading.familyId, isNull);
    });
  });
}

/// A slice of the real tenant tree, parents included so leaf-ness is real.
final _tree = <Category>[
  _c('componentes', 'Componentes', 'Componentes', 0),
  _c('frenos', 'Frenos', 'Componentes / Frenos', 1, parent: 'componentes'),
  _c('rotores', 'Rotores', 'Componentes / Frenos / Rotores', 2,
      parent: 'frenos'),
  _c('pastillas', 'Pastillas', 'Componentes / Frenos / Pastillas', 2,
      parent: 'frenos'),
  _c('calipers', 'Calipers', 'Componentes / Frenos / Calipers', 2,
      parent: 'frenos'),
  _c('vbrake', 'V-Brake', 'Componentes / Frenos / V-Brake', 2,
      parent: 'frenos'),
  _c('herraduras', 'Herraduras', 'Componentes / Frenos / V-Brake / Herraduras',
      3,
      parent: 'vbrake'),
  _c('gomas', 'Gomas V-Brake', 'Componentes / Frenos / V-Brake / Gomas V-Brake',
      3,
      parent: 'vbrake'),
  _c('frenos-adapt', 'Adaptadores', 'Componentes / Frenos / Adaptadores', 2,
      parent: 'frenos'),
  _c('ruedas', 'Ruedas', 'Componentes / Ruedas', 1, parent: 'componentes'),
  _c('mazas', 'Mazas', 'Componentes / Ruedas / Mazas', 2, parent: 'ruedas'),
  _c('maza', 'Maza', 'Componentes / Ruedas / Mazas / Maza', 3, parent: 'mazas'),
  _c('cintas', 'Cintas de llanta', 'Componentes / Ruedas / Cintas de llanta', 2,
      parent: 'ruedas'),
  _c('accesorios', 'Accesorios', 'Accesorios', 0),
  _c('acc-adapt', 'Adaptadores', 'Accesorios / Adaptadores', 1,
      parent: 'accesorios'),
  _c('herramientas', 'Herramientas', 'Herramientas', 0),
  _c('corta', 'Corta Cadena', 'Herramientas / Corta Cadena', 1,
      parent: 'herramientas'),
  _c('extractores', 'Extractores', 'Herramientas / Extractores', 1,
      parent: 'herramientas'),
];

Category _c(
  String id,
  String name,
  String fullPath,
  int level, {
  String? parent,
}) =>
    Category(
      id: id,
      tenantId: 'tenant-test',
      name: name,
      fullPath: fullPath,
      parentId: parent,
      level: level,
    );
