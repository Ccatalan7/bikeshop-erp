import 'inventory_models.dart';

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
  final List<String> signals;
  final List<String> imageDebugSignals;
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
