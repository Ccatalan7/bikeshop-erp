import 'package:flutter/foundation.dart';

import 'website_responsive_authoring.dart';

/// One exact Canvas document inside the Website Builder draft.
///
/// A standalone Canvas is `{blockId, null}`; a Canvas hosted by a carousel is
/// `{blockId, slideIndex}`. Indices are meaningful only together with their
/// owning block, so they are never passed around as a bare integer.
@immutable
class WebsiteCanvasDocumentTarget {
  const WebsiteCanvasDocumentTarget({
    required this.blockId,
    this.slideIndex,
  })  : assert(blockId != ''),
        assert(slideIndex == null || slideIndex >= 0);

  final String blockId;
  final int? slideIndex;

  @override
  bool operator ==(Object other) =>
      other is WebsiteCanvasDocumentTarget &&
      other.blockId == blockId &&
      other.slideIndex == slideIndex;

  @override
  int get hashCode => Object.hash(blockId, slideIndex);
}

/// The exact layer a direct-manipulation session belongs to.
@immutable
class WebsiteCanvasLayerTarget {
  const WebsiteCanvasLayerTarget({
    required this.document,
    required this.layerId,
  }) : assert(layerId != '');

  final WebsiteCanvasDocumentTarget document;
  final String layerId;

  @override
  bool operator ==(Object other) =>
      other is WebsiteCanvasLayerTarget &&
      other.document == document &&
      other.layerId == layerId;

  @override
  int get hashCode => Object.hash(document, layerId);
}

/// Explicit direct-manipulation modes for a touch/stylus canvas.
///
/// No session means browse: the page Scrollable owns a normal swipe. A mode
/// exists only while it is bound to one [WebsiteCanvasLayerTarget]. Keeping the
/// target in the value prevents an active layer retained in another Canvas or
/// carousel slide from inheriting the operator's command.
enum WebsiteCanvasManipulationMode {
  move,
  resize,
  rotate,
  crop,
}

@immutable
class WebsiteCanvasManipulationSession {
  const WebsiteCanvasManipulationSession({
    required this.target,
    required this.mode,
    required this.viewport,
    required this.generation,
  }) : assert(generation > 0);

  final WebsiteCanvasLayerTarget target;
  final WebsiteCanvasManipulationMode mode;
  final WebsiteViewport viewport;

  /// Monotonic identity of this arm operation.
  ///
  /// Target, mode and viewport are not enough: stop -> re-arm may recreate
  /// the same structural value while a pointer admitted by the old arm is
  /// still down. A generation makes that old pointer observably stale.
  final int generation;

  bool matches({
    required WebsiteCanvasDocumentTarget document,
    required String layerId,
    required WebsiteCanvasManipulationMode mode,
    required WebsiteViewport viewport,
  }) =>
      target.document == document &&
      target.layerId == layerId &&
      this.mode == mode &&
      this.viewport == viewport;

  @override
  bool operator ==(Object other) =>
      other is WebsiteCanvasManipulationSession &&
      other.target == target &&
      other.mode == mode &&
      other.viewport == viewport &&
      other.generation == generation;

  @override
  int get hashCode => Object.hash(target, mode, viewport, generation);
}

/// Why a direct-manipulation request cannot start.
enum WebsiteCanvasManipulationBlockReason {
  editorInactive,
  selectionMismatch,
  canvasNotMeasured,
  viewportMismatch,
  documentMissing,
  layerMissing,
  layerAmbiguous,
  layerHidden,
  layerLocked,
  modeUnsupported,
}

@immutable
class WebsiteCanvasManipulationAvailability {
  const WebsiteCanvasManipulationAvailability.available() : reason = null;

  const WebsiteCanvasManipulationAvailability.blocked(
    WebsiteCanvasManipulationBlockReason blockedReason,
  ) : reason = blockedReason;

  final WebsiteCanvasManipulationBlockReason? reason;

  bool get isAvailable => reason == null;
}
