import 'package:flutter/foundation.dart';

/// The six alignments a Canvas layer can take against its design surface.
enum WebsiteCanvasAlignment {
  left,
  horizontalCenter,
  right,
  top,
  verticalCenter,
  bottom,
}

/// The result of an alignment: the layer's new origin.
@immutable
class WebsiteCanvasAlignedOrigin {
  const WebsiteCanvasAlignedOrigin({required this.x, required this.y});

  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is WebsiteCanvasAlignedOrigin && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

/// Where a layer lands when it is aligned. Pure, and the only definition.
///
/// **Why this exists.** There were two implementations — `CanvasBlock`'s
/// `_alignElement` and the inspector's `_alignToCanvas`. The arithmetic was the
/// same, but the *surface* they measured against was not: the canvas derived
/// the design size from the rendered width and its scale, while the inspector
/// read the document's own `designWidth`/`designHeight` roots. Two answers to
/// "align this left" is one too many, and the operator meets both — the
/// toolbar on the canvas and the control in the inspector.
///
/// The caller supplies the design surface it is authoritative about; the
/// arithmetic lives here once. A zero or negative surface is treated as
/// unusable and leaves the origin untouched rather than throwing the layer to
/// a negative coordinate.
abstract final class WebsiteCanvasAlignmentMath {
  static WebsiteCanvasAlignedOrigin align({
    required WebsiteCanvasAlignment alignment,
    required double x,
    required double y,
    required double width,
    required double height,
    required double designWidth,
    required double designHeight,
  }) {
    final usableWidth = designWidth > 0 ? designWidth : null;
    final usableHeight = designHeight > 0 ? designHeight : null;

    return switch (alignment) {
      WebsiteCanvasAlignment.left => WebsiteCanvasAlignedOrigin(x: 0, y: y),
      WebsiteCanvasAlignment.horizontalCenter => WebsiteCanvasAlignedOrigin(
          x: usableWidth == null ? x : (usableWidth - width) / 2,
          y: y,
        ),
      WebsiteCanvasAlignment.right => WebsiteCanvasAlignedOrigin(
          x: usableWidth == null ? x : usableWidth - width,
          y: y,
        ),
      WebsiteCanvasAlignment.top => WebsiteCanvasAlignedOrigin(x: x, y: 0),
      WebsiteCanvasAlignment.verticalCenter => WebsiteCanvasAlignedOrigin(
          x: x,
          y: usableHeight == null ? y : (usableHeight - height) / 2,
        ),
      WebsiteCanvasAlignment.bottom => WebsiteCanvasAlignedOrigin(
          x: x,
          y: usableHeight == null ? y : usableHeight - height,
        ),
    };
  }
}
