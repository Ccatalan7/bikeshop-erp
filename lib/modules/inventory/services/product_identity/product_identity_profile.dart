import 'bike_part_taxonomy.dart';

/// A measurable property of a physical part.
///
/// Every kind listed here was chosen because getting it wrong sells the wrong
/// object across a counter: a 32-spoke hub cannot be laced into a 36-hole rim,
/// a 160 mm rotor does not fit a 180 mm caliper mount, an HG freehub does not
/// accept a MicroSpline cassette. That is why they are *exclusive*: when both
/// sides state one and the values differ, the candidate is eliminated instead
/// of being ranked lower.
enum PartSpecKind {
  /// Spoke holes in a hub or rim (`32H`).
  spokeCount,

  /// Brake rotor diameter in millimetres (`160mm`).
  rotorDiameterMm,

  /// Handlebar clamp diameter of a stem or bar (`31.8mm`).
  clampDiameterMm,

  /// Seatpost / seat tube diameter (`27.2mm`).
  postDiameterMm,

  /// Crank arm length (`170mm`).
  crankLengthMm,

  /// Tooth count of a chainring, cassette cog or pulley (`36T`).
  teeth,

  /// Bolt circle diameter of a chainring interface (`104BCD`).
  boltCircleMm,

  /// Wheel/tyre nominal size (`29`, `27.5`, `700`).
  wheelSize,

  /// Over-locknut / axle width in millimetres (`135`, `148`).
  axleWidthMm,

  /// Axle diameter in millimetres (`10`, `12`, `15`).
  axleDiameterMm,

  /// Freehub driver standard (`hg`, `microspline`, `xd`, `freewheel`).
  freehubStandard,

  /// Valve standard (`presta`, `schrader`).
  valveType,

  /// Which end of the bike the part belongs to (`front`, `rear`).
  position,

  /// Drivetrain speed count (`8`, `12`).
  speeds,

  /// Bottom bracket shell standard (`bsa`, `bb30`, `pressfit`).
  shellStandard,

  /// Brake mount standard (`postmount`, `isbrake`, `flatmount`).
  brakeMount,

  /// Free length in millimetres for valves, stems, posts (`60mm`).
  lengthMm,

  /// Units contained in one sold package (`10 pcs`).
  packCount,

  /// Colour of the physical variant.
  colorVariant,
}

/// Whether a specification, once known on both sides, is decisive.
const Set<PartSpecKind> exclusivePartSpecs = <PartSpecKind>{
  PartSpecKind.spokeCount,
  PartSpecKind.rotorDiameterMm,
  PartSpecKind.clampDiameterMm,
  PartSpecKind.postDiameterMm,
  PartSpecKind.boltCircleMm,
  PartSpecKind.wheelSize,
  PartSpecKind.axleWidthMm,
  PartSpecKind.axleDiameterMm,
  PartSpecKind.freehubStandard,
  PartSpecKind.valveType,
  PartSpecKind.position,
  PartSpecKind.shellStandard,
  PartSpecKind.brakeMount,
  // A 9-speed master link does not close an 11-speed chain, and a 10-speed
  // cassette is not a 12-speed one. The count only eliminates when *both*
  // sides state one, and a listing that offers several leaves it unknown, so
  // an option list can never be read as a decision.
  PartSpecKind.speeds,
};

/// Operator-facing name of a specification. Used verbatim in the explanation
/// the review screen shows, so it is written in the shop's vocabulary and not
/// in engineering shorthand.
String partSpecLabel(PartSpecKind kind) => switch (kind) {
      PartSpecKind.spokeCount => 'agujeros',
      PartSpecKind.rotorDiameterMm => 'diámetro del rotor',
      PartSpecKind.clampDiameterMm => 'diámetro de abrazadera',
      PartSpecKind.postDiameterMm => 'diámetro de tija',
      PartSpecKind.crankLengthMm => 'largo de biela',
      PartSpecKind.teeth => 'dientes',
      PartSpecKind.boltCircleMm => 'BCD',
      PartSpecKind.wheelSize => 'aro',
      PartSpecKind.axleWidthMm => 'ancho de eje',
      PartSpecKind.axleDiameterMm => 'diámetro de eje',
      PartSpecKind.freehubStandard => 'estándar de núcleo',
      PartSpecKind.valveType => 'tipo de válvula',
      PartSpecKind.position => 'posición',
      PartSpecKind.speeds => 'velocidades',
      PartSpecKind.shellStandard => 'estándar de caja',
      PartSpecKind.brakeMount => 'montaje de freno',
      PartSpecKind.lengthMm => 'largo',
      PartSpecKind.packCount => 'unidades por paquete',
      PartSpecKind.colorVariant => 'color',
    };

/// Human form of a stored spec value (`27.5`, `hg`, `rear`).
String partSpecValueLabel(PartSpecKind kind, String value) {
  switch (kind) {
    case PartSpecKind.position:
      return switch (value) {
        'front' => 'delantera',
        'rear' => 'trasera',
        _ => value,
      };
    case PartSpecKind.freehubStandard:
      return switch (value) {
        'hg' => 'HG',
        'microspline' => 'MicroSpline',
        'xd' => 'XD',
        'xdr' => 'XDR',
        'freewheel' => 'rueda libre',
        _ => value,
      };
    case PartSpecKind.valveType:
      return switch (value) {
        'presta' => 'francesa',
        'schrader' => 'auto',
        'presta_schrader' => 'francesa a auto',
        _ => value,
      };
    case PartSpecKind.spokeCount:
      return '${value}H';
    case PartSpecKind.teeth:
      return '${value}T';
    case PartSpecKind.boltCircleMm:
      return '${value}BCD';
    case PartSpecKind.rotorDiameterMm:
    case PartSpecKind.clampDiameterMm:
    case PartSpecKind.postDiameterMm:
    case PartSpecKind.crankLengthMm:
    case PartSpecKind.axleWidthMm:
    case PartSpecKind.axleDiameterMm:
    case PartSpecKind.lengthMm:
      return '${value}mm';
    default:
      return value;
  }
}

/// Everything the system claims to know about *what a thing is*, separated
/// from everything it merely knows the thing *works with*.
///
/// The separation is the point. `IXF … Compatible con SHIMANO/SRAM` asserts
/// the manufacturer IXF and mentions two others; a profile that collapses
/// those three into one brand field is how a Shimano crankset became a
/// candidate for an IXF one.
class ProductIdentityProfile {
  const ProductIdentityProfile({
    required this.identityText,
    required this.fitmentText,
    required this.familyId,
    required this.familyCandidates,
    required this.assertedBrand,
    required this.compatibilityBrands,
    required this.modelCodes,
    required this.primaryModelCodes,
    required this.compatibilityModelCodes,
    required this.specs,
    required this.descriptorTokens,
    required this.categoryPath,
    this.visualFamilyId,
    this.visualTerms = const <String>{},
    this.visualConfidence = 0,
  });

  /// The segment that says what the object is.
  final String identityText;

  /// The segment that says what it fits, includes or is compatible with.
  final String fitmentText;

  /// Winning family, or `null` when no head noun was recognized.
  final String? familyId;

  /// Every family whose head noun appeared in the identity segment.
  final Set<String> familyCandidates;

  /// Manufacturer stated as the maker of this object.
  final String? assertedBrand;

  /// Brands named only as compatibility targets. Never identity.
  final Set<String> compatibilityBrands;

  /// Model codes surviving after every typed specification was consumed and
  /// found inside the identity text.
  final Set<String> modelCodes;

  /// Codes printed in the product's own name, or stated in its model field.
  /// Only these may establish a strong duplicate.
  final Set<String> primaryModelCodes;

  /// Codes that appear only in a compatibility clause. Kept so the review can
  /// explain a fitment claim, never used as identity.
  final Set<String> compatibilityModelCodes;

  /// Typed measurable properties.
  final Map<PartSpecKind, String> specs;

  /// Remaining meaningful words, used for lexical corroboration only.
  final Set<String> descriptorTokens;

  /// Category path segments, lowercase and normalized, root first.
  final List<String> categoryPath;

  /// Family recognized from the product photo, when a visual reading ran.
  final String? visualFamilyId;

  /// Catalog terms the visual reading produced.
  final Set<String> visualTerms;

  /// How sure the visual reading was about what it saw.
  final double visualConfidence;

  /// Above this the photo is allowed to overrule a head noun that named a
  /// different object. Below it the photo cannot decide on its own.
  static const double visualOverrideConfidence = 0.6;

  /// Below this the photo is not evidence at all — a blurry or generic reading
  /// must not send a perfectly ordinary row to review.
  static const double visualMinimumConfidence = 0.35;

  PartPhysicalClass get physicalClass => BikePartTaxonomy.classOf(familyId);

  PartPhysicalClass get visualPhysicalClass =>
      BikePartTaxonomy.classOf(visualFamilyId);

  String get familyLabel => BikePartTaxonomy.labelOf(familyId);

  bool get hasFamily => familyId != null;

  /// Whether the two independent readings of *what this object is* disagree
  /// about its physical class.
  ///
  /// A disagreement is information, not noise. `Herradura de freno` is a
  /// bracket; the word `freno` next to it is the system it serves. When the
  /// photo says one class and the head noun says a neighbouring one, the row
  /// stops being safe to auto-classify.
  bool get familyEvidenceConflicts {
    if (familyId == null || visualFamilyId == null) return false;
    if (familyId == visualFamilyId) return false;
    // Different *family*, not merely different class. `Calipers` and
    // `Herraduras` are both braking and live in different leaves of this
    // catalog; treating same-class disagreement as agreement is how a
    // rim-brake arm could be filed as a disc caliper.
    return visualConfidence >= visualMinimumConfidence;
  }

  /// The family the matcher should use.
  ///
  /// Text alone used to win whenever it produced *any* answer, which meant a
  /// wrong-but-non-null family — the ordinary result of a relational word —
  /// silently suppressed the photo. The photo is now read for every product
  /// and may overrule a contradicting head noun when it is confident; below
  /// that bar it fills a gap and the disagreement is reported instead.
  String? get effectiveFamilyId {
    if (familyId == null) return visualFamilyId;
    if (visualFamilyId == null) return familyId;
    if (!familyEvidenceConflicts) return familyId;
    return visualConfidence >= visualOverrideConfidence
        ? visualFamilyId
        : familyId;
  }

  PartPhysicalClass get effectivePhysicalClass =>
      BikePartTaxonomy.classOf(effectiveFamilyId);

  /// True when nothing may be auto-assigned from this profile: the two
  /// readings disagree and neither is decisive.
  bool get requiresIdentityReview =>
      familyEvidenceConflicts && visualConfidence < visualOverrideConfidence;

  ProductIdentityProfile withVisualReading({
    String? visualFamilyId,
    Set<String> visualTerms = const <String>{},
    double visualConfidence = 0,
  }) {
    return ProductIdentityProfile(
      identityText: identityText,
      fitmentText: fitmentText,
      familyId: familyId,
      familyCandidates: familyCandidates,
      assertedBrand: assertedBrand,
      compatibilityBrands: compatibilityBrands,
      modelCodes: modelCodes,
      primaryModelCodes: primaryModelCodes,
      compatibilityModelCodes: compatibilityModelCodes,
      specs: specs,
      descriptorTokens: descriptorTokens,
      categoryPath: categoryPath,
      visualFamilyId: visualFamilyId ?? this.visualFamilyId,
      visualTerms: visualTerms.isEmpty ? this.visualTerms : visualTerms,
      visualConfidence:
          visualConfidence == 0 ? this.visualConfidence : visualConfidence,
    );
  }

  @override
  String toString() {
    final parts = <String>[
      'family=${familyId ?? '·'}',
      if (assertedBrand != null) 'brand=$assertedBrand',
      if (compatibilityBrands.isNotEmpty)
        'compat=${compatibilityBrands.join('/')}',
      if (modelCodes.isNotEmpty) 'model=${modelCodes.join('/')}',
      for (final entry in specs.entries) '${entry.key.name}=${entry.value}',
    ];
    return 'ProductIdentityProfile(${parts.join(' ')})';
  }
}
