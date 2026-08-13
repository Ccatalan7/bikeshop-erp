import '../services/product_identity/product_identity_matcher.dart';
import 'inventory_models.dart';

/// Why a list of candidates was built.
///
/// The row and the picker are not the same question, and answering both from
/// one list is what turned an uncertain row into a dead end. The row must be
/// conservative: one honest recommendation, nothing from another family, no
/// filler. The picker is opened *because* the operator did not accept that
/// recommendation, so hiding everything the engine ruled out leaves only two
/// exits — take the wrong product, or create a duplicate of one that already
/// exists. Creating that duplicate is the exact failure this feature exists to
/// prevent.
///
/// A gate therefore eliminates a candidate from the recommendation, never from
/// the operator's view.
enum ProductDuplicateShortlistScope {
  /// What the row offers on its own: survivors only, above the useful floor.
  recommendation,

  /// What the picker offers when the operator asks: every retrieved product of
  /// the same object family, ranked, each stating its own verdict — including
  /// the ones a gate ruled out and why.
  operatorChoice,
}

enum ProductDuplicateMatchTier {
  /// Deterministic identity evidence: the same catalog SKU, a confirmed
  /// supplier alias, or byte-identical imagery. No judgement involved.
  exact,

  /// Decisive corroboration — the manufacturer model code the invoice names,
  /// or family plus manufacturer plus every stated measurement agreeing.
  strong,

  /// Comparable and worth a look, with its differences stated.
  possible,

  /// The same kind of object, ruled out by a gate that is stated in words.
  /// Only ever offered inside the picker, never as a row's recommendation.
  ruledOut,
}

/// One product the catalog offers as the possible identity of an invoice line.
///
/// The score zoo this class used to expose (`keywordScore`, `semanticScore`,
/// `imageScore`, `metadataScore`, `aiTypeScore`…) is gone deliberately. Those
/// numbers were rendered as `61%` next to a product name, which the GUI guide
/// forbids — *«nunca un número que finge ser una medición»* — and which invited
/// approving a suggestion by threshold. What the operator needs is the reason,
/// and what the code needs is one ordering value that is never displayed.
class ProductDuplicateCandidate {
  const ProductDuplicateCandidate({
    required this.product,
    required this.matchTier,
    required this.confidence,
    required this.reasons,
    required this.objections,
    required this.gates,
    required this.variantMismatch,
    required this.hasProductImage,
    this.matchedModelCodes = const <String>{},
    this.isReviewOnlyFamilyScope = false,
    this.lineConfidence,
    this.variantAgreement = false,
  });

  final Product product;

  final ProductDuplicateMatchTier matchTier;

  /// Ordering strength. Internal: never render it, and never derive a label
  /// from a threshold on it.
  final double confidence;

  /// Why this product is offered, in the shop's own words.
  final List<String> reasons;

  /// What does not line up. An empty list means nothing stated disagrees, not
  /// that the products are identical.
  final List<String> objections;

  /// Every decisive check and its outcome, for the evidence disclosure.
  final List<IdentityGate> gates;

  /// Same product line, different sold variant (colour).
  final bool variantMismatch;

  final bool hasProductImage;

  /// Manufacturer model codes shared with the invoice line.
  final Set<String> matchedModelCodes;

  /// The catalog row had no product family of its own and was admitted only
  /// because it occupies the exact active category leaf selected for the
  /// invoice row. It is manual recall, never automatic identity evidence.
  final bool isReviewOnlyFamilyScope;

  /// Product-line ordering strength before a selected-option tie-break.
  final double? lineConfidence;

  /// Whether the selected supplier option explicitly agrees with this row.
  final bool variantAgreement;

  bool get isExactIdentity => matchTier == ProductDuplicateMatchTier.exact;

  /// A gate ruled this product out. It is shown so the operator can overrule a
  /// misread specification, never as a recommendation.
  bool get isRuledOut => matchTier == ProductDuplicateMatchTier.ruledOut;

  /// The gate that ruled it out, in the shop's words.
  String? get ruledOutReason =>
      !isRuledOut ? null : (objections.isEmpty ? null : objections.first);

  /// The short verbal evidence a compact surface shows.
  List<String> get signals => reasons;
}

class ProductDuplicateReviewRow {
  const ProductDuplicateReviewRow({
    required this.title,
    required this.candidates,
    this.subtitle,
    this.imageUrl,
    this.badges = const [],
    this.footerText,
    this.onCandidateSelected,
  });

  final String title;
  final String? subtitle;
  final String? imageUrl;
  final List<String> badges;
  final String? footerText;
  final List<ProductDuplicateCandidate> candidates;
  final void Function(Product product)? onCandidateSelected;
}
