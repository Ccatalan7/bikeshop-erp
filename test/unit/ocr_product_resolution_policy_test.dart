import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/ocr_product_resolution_policy.dart';

void main() {
  OcrProductResolutionSnapshot line({
    OcrProductResolutionState state = OcrProductResolutionState.newProduct,
    bool valid = true,
    bool selected = true,
    bool aiCleaning = false,
    bool matchChecking = false,
  }) {
    return OcrProductResolutionSnapshot(
      selected: selected,
      valid: valid,
      requiresDuplicateReview: true,
      state: state,
      aiCleaning: aiCleaning,
      matchChecking: matchChecking,
    );
  }

  test('blocks creation until AliExpress duplicate review is resolved', () {
    for (final state in const [
      OcrProductResolutionState.unsearched,
      OcrProductResolutionState.searching,
      OcrProductResolutionState.reviewRequired,
      OcrProductResolutionState.noCandidates,
      OcrProductResolutionState.failed,
    ]) {
      expect(
        OcrProductResolutionPolicy.canCreate(lines: [line(state: state)]),
        isFalse,
        reason: '$state must not permit product creation',
      );
    }

    expect(
      OcrProductResolutionPolicy.canCreate(
        lines: [line(state: OcrProductResolutionState.newProduct)],
      ),
      isTrue,
    );
  });

  test('blocks invalid, cleaning, matching and globally busy batches', () {
    expect(
      OcrProductResolutionPolicy.canCreate(lines: [line(valid: false)]),
      isFalse,
    );
    expect(
      OcrProductResolutionPolicy.canCreate(lines: [line(aiCleaning: true)]),
      isFalse,
    );
    expect(
      OcrProductResolutionPolicy.canCreate(lines: [line(matchChecking: true)]),
      isFalse,
    );
    expect(
      OcrProductResolutionPolicy.canCreate(
        lines: [line()],
        globalBusy: true,
      ),
      isFalse,
    );
  });

  test('unselected local rows do not prevent a valid selected row', () {
    final local = const OcrProductResolutionSnapshot(
      selected: true,
      valid: true,
      requiresDuplicateReview: false,
      state: OcrProductResolutionState.unsearched,
    );
    expect(
      OcrProductResolutionPolicy.canCreate(
        lines: [local, line(selected: false, valid: false)],
      ),
      isTrue,
    );
  });
}
