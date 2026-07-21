import 'inventory_models.dart';

enum ProductDuplicateMatchTier {
  /// Deterministic identity evidence: exact SKU/supplier identity, canonical
  /// image URL, or byte-identical image content.
  exact,

  /// Decisive corroborating evidence (for example, an exact normalized model
  /// identifier) that should rank ahead of fuzzy candidates but still needs a
  /// human confirmation.
  strong,

  /// Fuzzy text, semantic, metadata, or perceptual-image evidence only.
  possible,
}

class ProductDuplicateCandidate {
  const ProductDuplicateCandidate({
    required this.product,
    required this.overallScore,
    required this.keywordScore,
    required this.semanticScore,
    required this.imageScore,
    required this.aiTypeScore,
    required this.identityScore,
    required this.metadataScore,
    required this.hasProductImage,
    required this.imageComparisonAvailable,
    required this.hasExactImageMatch,
    required this.hasExactModelMatch,
    required this.matchTier,
    required this.signals,
    this.imageDebugSignals = const [],
  });

  final Product product;
  final double overallScore;
  final double keywordScore;
  final double semanticScore;
  final double imageScore;
  final double aiTypeScore;
  final double identityScore;
  final double metadataScore;
  final bool hasProductImage;
  final bool imageComparisonAvailable;
  final bool hasExactImageMatch;
  final bool hasExactModelMatch;
  final ProductDuplicateMatchTier matchTier;
  final List<String> signals;
  final List<String> imageDebugSignals;

  bool get isExactIdentity => matchTier == ProductDuplicateMatchTier.exact;
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
