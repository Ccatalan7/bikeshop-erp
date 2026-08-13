/// Explicit resolution states for an OCR line that may represent an existing
/// product. A line cannot be created until the duplicate search completed and
/// the worker explicitly confirmed it as new.
enum OcrProductResolutionState {
  unsearched,
  searching,
  reviewRequired,

  /// Matching stopped safely because identity evidence conflicted or AI could
  /// not decide. This is not evidence that the product is new.
  abstained,
  noCandidates,
  newProduct,
  failed,
}

class OcrProductResolutionSnapshot {
  const OcrProductResolutionSnapshot({
    required this.selected,
    required this.valid,
    required this.requiresDuplicateReview,
    required this.state,
    this.aiCleaning = false,
    this.matchChecking = false,
  });

  final bool selected;
  final bool valid;
  final bool requiresDuplicateReview;
  final OcrProductResolutionState state;
  final bool aiCleaning;
  final bool matchChecking;

  bool get readyToCreate =>
      !requiresDuplicateReview || state == OcrProductResolutionState.newProduct;
}

class OcrProductResolutionPolicy {
  const OcrProductResolutionPolicy._();

  static bool canCreate({
    required Iterable<OcrProductResolutionSnapshot> lines,
    bool globalBusy = false,
  }) {
    if (globalBusy) return false;
    final selected = lines.where((line) => line.selected).toList();
    if (selected.isEmpty) return false;
    return selected.every(
      (line) =>
          line.valid &&
          line.readyToCreate &&
          !line.aiCleaning &&
          !line.matchChecking,
    );
  }
}
