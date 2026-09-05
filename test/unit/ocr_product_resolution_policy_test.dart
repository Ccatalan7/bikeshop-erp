import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/ocr_product_resolution_policy.dart';

void main() {
  test('completed supplier lookup does not keep a restored row comparing', () {
    // The live Aug 12 draft had a supplier receipt with all work flags false,
    // but its pre-reload resolution state was still searching.
    expect(
      OcrProductResolutionPolicy.isReviewBusy(
        state: OcrProductResolutionState.searching,
        hasSupplierResolution: true,
        hasActiveWork: false,
      ),
      isFalse,
    );
  });

  test('a remembered rule does not hide an operation still in flight', () {
    for (final state in [
      OcrProductResolutionState.searching,
      OcrProductResolutionState.reviewRequired,
    ]) {
      expect(
        OcrProductResolutionPolicy.isReviewBusy(
          state: state,
          hasSupplierResolution: true,
          hasActiveWork: true,
        ),
        isTrue,
      );
    }
  });

  test('an unfinished lookup remains busy until it has a result', () {
    expect(
      OcrProductResolutionPolicy.isReviewBusy(
        state: OcrProductResolutionState.searching,
        hasSupplierResolution: false,
        hasActiveWork: false,
      ),
      isTrue,
    );
    expect(
      OcrProductResolutionPolicy.isReviewBusy(
        state: OcrProductResolutionState.reviewRequired,
        hasSupplierResolution: true,
        hasActiveWork: false,
      ),
      isFalse,
    );
  });

  test('a failed or unfinished search cannot confirm a new product', () {
    for (final state in OcrProductResolutionState.values) {
      expect(
          OcrProductResolutionPolicy.canConfirmNew(
              requiresDuplicateReview: true, state: state),
          ![
            OcrProductResolutionState.failed,
            OcrProductResolutionState.unsearched,
            OcrProductResolutionState.searching
          ].contains(state));
    }
  });

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
    const local = OcrProductResolutionSnapshot(
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
