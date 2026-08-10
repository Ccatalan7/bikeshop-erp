import '../../models/category_models.dart';
import 'bike_part_taxonomy.dart';
import 'product_identity_extractor.dart';
import 'product_identity_profile.dart';

/// Why a category could not be assigned, in the shop's own words.
enum ProductCategoryRefusal {
  /// No family was established, so there is nothing to place.
  unknownObject,

  /// The photo and the title name different kinds of object.
  conflictingEvidence,

  /// The family is known but this tenant has no leaf for it.
  noCanonicalLeaf,

  /// More than one unrelated leaf fits and nothing decides between them.
  ambiguousLeaf,
}

/// The outcome of placing one product in the tenant's category tree.
class ProductCategoryResolution {
  const ProductCategoryResolution({
    required this.category,
    required this.evidence,
    this.refusal,
    this.refusalDetail,
  });

  /// The chosen leaf, or `null` when the pipeline refused to guess.
  final Category? category;

  /// What justified the choice, or what was weighed before refusing.
  final List<String> evidence;

  final ProductCategoryRefusal? refusal;
  final String? refusalDetail;

  bool get isResolved => category != null;

  /// Operator-facing reason a row still needs a human.
  String? get reviewReason => switch (refusal) {
        null => null,
        ProductCategoryRefusal.unknownObject =>
          'No se pudo reconocer qué pieza es. Elige la categoría a mano.',
        ProductCategoryRefusal.conflictingEvidence =>
          'La foto y el título dicen cosas distintas: $refusalDetail. '
              'Elige la categoría a mano.',
        ProductCategoryRefusal.noCanonicalLeaf =>
          'No existe una categoría para $refusalDetail en este catálogo.',
        ProductCategoryRefusal.ambiguousLeaf =>
          'Hay más de una categoría posible para $refusalDetail: '
              'elige cuál corresponde.',
      };
}

/// Places a product in the tenant's real category tree, from what the object
/// **is** — never from a word that happens to appear next to it.
///
/// The rebuilt pipeline runs in one direction and refuses rather than guesses:
///
/// 1. the object's family, reconciled between the photo and the title's head
///    noun (`ProductIdentityProfile.effectiveFamilyId`);
/// 2. the canonical leaves that family is allowed to occupy;
/// 3. those leaves matched against the tenant's real tree;
/// 4. otherwise, an explicit refusal that sends the row to review.
///
/// Two rules do most of the work, and neither mentions any particular product:
///
/// * **A relational word is not an identity.** `Herradura de freno V-Brake` is
///   a rim-brake arm; `freno` is the system it serves. The word reaches the
///   profile only as a descriptor, never as the head noun, so it cannot pull
///   the object into the braking-system node.
/// * **A parent is never a product's category.** `Componentes / Frenos` has
///   children, so it describes a system, not a thing on a shelf. Assigning it
///   is how a `Herradura` ended up filed as `Frenos`: not a missing synonym, a
///   missing rule.
class ProductCategoryResolver {
  ProductCategoryResolver({required Iterable<Category> categories})
      : _categories = List<Category>.unmodifiable(categories) {
    final parents = <String>{};
    for (final category in _categories) {
      final parentId = category.parentId;
      if (parentId != null && parentId.trim().isNotEmpty) {
        parents.add(parentId);
      }
    }
    _parentIds = Set<String>.unmodifiable(parents);
  }

  final List<Category> _categories;
  late final Set<String> _parentIds;

  /// The leaf names each family may legitimately occupy, in the vocabulary the
  /// shop actually uses for its own tree. Order is preference, most specific
  /// first.
  static const Map<String, List<String>> canonicalLeavesByFamily =
      <String, List<String>>{
    'stem': ['tee'],
    'handlebar': ['manubrios', 'manubrio', 'manillar'],
    'headset': ['direccion', 'juego de direccion'],
    'grip': ['punos', 'puños'],
    'saddle': ['asiento', 'asientos', 'sillin'],
    'seatpost': ['tija', 'tijas'],
    'seat_clamp': ['collarin', 'collarines', 'abrazadera de tija'],
    'crankset': ['volante', 'volantes'],
    'crank_arm': ['biela izquierda', 'bielas'],
    'chainring': ['platos', 'plato', 'coronas'],
    'chainring_guard': ['protectores', 'guias de cadena'],
    'chain_guide': ['guias de cadena', 'guia de cadena'],
    'bottom_bracket': ['motor', 'motores'],
    'pedal': ['pedales', 'pedal'],
    'chain': ['cadenas', 'cadena'],
    'chain_link': ['missinglink', 'eslabon rapido', 'eslabones'],
    'surface_protector': ['stickers', 'sticker', 'protectores de marco'],
    'cassette': ['pinones', 'cassette', 'casete'],
    'cassette_spacer': ['espaciadores', 'espaciador'],
    'derailleur': ['desviador trasero', 'desviador delantero', 'desviadores'],
    'derailleur_hanger': [
      'patillas',
      'patilla de cambio',
      'perchas',
      'postiza'
    ],
    'derailleur_hanger_extender': ['postiza', 'patillas', 'perchas'],
    'pulley': ['poleas', 'polea'],
    'shifter': ['shifters', 'shifter'],
    'brake_rotor': ['rotores', 'rotor'],
    'brake_pad': ['pastillas', 'pastilla'],
    'brake_caliper': ['calipers', 'caliper'],
    'rim_brake_arm': ['herraduras', 'herradura'],
    'brake_lever': ['manillas', 'manilla de freno'],
    'brake_adapter': ['adaptadores'],
    'hub': ['maza', 'mazas'],
    'rim': ['llantas', 'llanta', 'aros'],
    'wheelset': ['ruedas armadas', 'ruedas'],
    'spoke': ['rayos', 'rayo'],
    'rim_tape': ['cintas de llanta', 'fondo de llanta'],
    'tire': ['neumaticos', 'neumatico', 'cubiertas'],
    'tube': ['camaras', 'camara'],
    'tyre_liner': ['protectores', 'protector'],
    'patch': ['parches', 'parche'],
    'sealant': ['sellantes', 'liquido sellante'],
    'tubeless_valve': ['valvula tubeless', 'valvulas tubeless'],
    'valve_core': ['valvula tubeless', 'obus'],
    'valve_adapter': ['adaptadores'],
    'fork': ['horquillas', 'horquilla'],
    'shock': ['amortiguadores', 'amortiguador'],
    'frame': ['cuadros', 'cuadro'],
    'cable_housing': ['fundas y piolas', 'piolas', 'fundas'],
    'light': ['luces', 'luz'],
    'lock': ['candados', 'candado'],
    'bell': ['timbres', 'timbre'],
    'mirror': ['espejos', 'espejo'],
    'bottle_cage': ['porta caramagiola', 'portabidon'],
    'bottle': ['botellas', 'caramagiola', 'bidon'],
    'phone_mount': ['porta celular', 'soporte de celular'],
    'bag': ['bolsos', 'alforjas', 'mochilas'],
    'rack': ['parrillas', 'parrilla', 'portaequipaje'],
    'fender': ['barrofangos', 'guardabarros'],
    'kickstand': ['patas', 'pata de apoyo'],
    'helmet': ['cascos', 'casco'],
    'glove': ['guantes', 'guante'],
    'chain_tool': ['corta cadena', 'cortacadena'],
    'puller_tool': ['extractores', 'extractor'],
    'pump': ['bombines', 'bombin', 'infladores'],
    'tool': ['herramientas', 'herramienta'],
    'lubricant': ['lubricantes', 'aceites', 'grasas'],
    'bearing': ['rodamientos', 'rodamiento'],
    'axle': ['ejes', 'eje'],
    'bolt': ['pernos', 'perno'],
  };

  ProductCategoryResolution resolve(ProductIdentityProfile profile) {
    final evidence = <String>[];

    if (profile.requiresIdentityReview) {
      final textLabel = BikePartTaxonomy.labelOf(profile.familyId);
      final visualLabel = BikePartTaxonomy.labelOf(profile.visualFamilyId);
      return ProductCategoryResolution(
        category: null,
        evidence: <String>[
          'El título dice $textLabel',
          'La foto dice $visualLabel',
        ],
        refusal: ProductCategoryRefusal.conflictingEvidence,
        refusalDetail: '$textLabel contra $visualLabel',
      );
    }

    final familyId = profile.effectiveFamilyId;
    if (familyId == null) {
      return const ProductCategoryResolution(
        category: null,
        evidence: <String>[],
        refusal: ProductCategoryRefusal.unknownObject,
      );
    }

    final label = BikePartTaxonomy.labelOf(familyId);
    evidence.add(
      profile.familyId == familyId
          ? 'El título la nombra: $label'
          : 'La foto la reconoce: $label',
    );

    final aliases = canonicalLeavesByFamily[familyId];
    if (aliases == null || aliases.isEmpty) {
      return ProductCategoryResolution(
        category: null,
        evidence: evidence,
        refusal: ProductCategoryRefusal.noCanonicalLeaf,
        refusalDetail: label.toLowerCase(),
      );
    }

    for (final alias in aliases) {
      final matches = _leavesNamed(alias);
      if (matches.isEmpty) continue;
      if (matches.length > 1) {
        // Two unrelated branches answer to the same leaf name. Picking one is
        // exactly the guess this pipeline exists to refuse.
        return ProductCategoryResolution(
          category: null,
          evidence: <String>[
            ...evidence,
            for (final match in matches) match.fullPath,
          ],
          refusal: ProductCategoryRefusal.ambiguousLeaf,
          refusalDetail: label.toLowerCase(),
        );
      }
      final chosen = matches.single;
      evidence.add('Categoría del catálogo: ${chosen.fullPath}');
      return ProductCategoryResolution(
        category: chosen,
        evidence: List<String>.unmodifiable(evidence),
      );
    }

    return ProductCategoryResolution(
      category: null,
      evidence: List<String>.unmodifiable(evidence),
      refusal: ProductCategoryRefusal.noCanonicalLeaf,
      refusalDetail: label.toLowerCase(),
    );
  }

  /// Categories with that name that are **leaves**.
  ///
  /// A node with children names a system, not an object. `Componentes /
  /// Frenos` is where brakes are organised, never what a product is.
  List<Category> _leavesNamed(String alias) {
    final target = ProductIdentityExtractor.normalize(alias);
    if (target.isEmpty) return const <Category>[];
    return _categories.where((category) {
      final id = category.id;
      if (id == null || id.trim().isEmpty) return false;
      if (!category.isActive) return false;
      if (_parentIds.contains(id)) return false;
      return ProductIdentityExtractor.normalize(category.name) == target;
    }).toList(growable: false);
  }

  /// Whether [category] is a system node rather than a shelf.
  bool isSystemNode(Category category) {
    final id = category.id;
    return id != null && _parentIds.contains(id);
  }
}
