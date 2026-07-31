import 'package:flutter/foundation.dart';

import 'website_canvas_editor_binding.dart';

/// Edit-only transient state for the shared Carousel content tree.
///
/// Slide and nested Canvas selection belong to the editor session, not to the
/// persisted `slides` collection. Preview and Public omit this binding.
class WebsiteCarouselEditBinding {
  const WebsiteCarouselEditBinding({
    required this.selectedSlideIndex,
    required this.onSlideSelected,
    required this.canvasBindingForSlide,
  });

  final int selectedSlideIndex;
  final ValueChanged<int> onSlideSelected;
  final WebsiteCanvasEditorBinding Function(int slideIndex)
      canvasBindingForSlide;
}
