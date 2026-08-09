import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// How the published header relates to the document underneath it.
///
/// Two independent facts, deliberately not one flag:
///
/// * [overlaysDocument] — the composition floats the header **over** the
///   content, so the first block starts at y=0 underneath it. This is a
///   property of the composition, not of the scroll position: a sticky home
///   header still covers the top of the document after it has turned solid at
///   scroll > 50. Editor chrome that must clear the header reads this one.
/// * [visualOverlay] — the header is currently *painted* transparent over the
///   content. This flips with scroll and only describes appearance.
///
/// Collapsing them is how chrome ends up jumping into the header the moment
/// the operator scrolls past 50: the geometry did not change, only the paint.
@immutable
class WebsiteHeaderOverlayGeometry {
  const WebsiteHeaderOverlayGeometry({
    this.overlaysDocument = false,
    this.visualOverlay = false,
    this.height = 0,
  });

  final bool overlaysDocument;
  final bool visualOverlay;

  /// Measured height of the header as currently composed. A banner that wraps
  /// to two lines changes this, which is why it is measured and not declared.
  final double height;

  /// How much of the document's top the header covers. Zero when the header
  /// occupies flow (inline/solid), because then there is nothing to clear.
  double get documentInset => overlaysDocument ? height : 0;

  @override
  bool operator ==(Object other) =>
      other is WebsiteHeaderOverlayGeometry &&
      other.overlaysDocument == overlaysDocument &&
      other.visualOverlay == visualOverlay &&
      (other.height - height).abs() < 0.5;

  @override
  int get hashCode =>
      Object.hash(overlaysDocument, visualOverlay, height.round());

  @override
  String toString() => 'WebsiteHeaderOverlayGeometry(overlays: '
      '$overlaysDocument, visual: $visualOverlay, h: $height)';
}

/// The measured relationship between the published header and the document.
///
/// **Why this exists.** The storefront composes the header several ways — the
/// transparent home page floats it inside the scroll view, the sticky layout
/// floats it above one, inline and solid put it in flow — and editor chrome
/// that has to sit *below* the header needed to know where that is. Asking
/// each compositor separately produced the usual result: the answer reached
/// one of them and silently missed the others.
///
/// **What it is not.** It is not a spacer and nothing is ever laid out against
/// it. The published geometry is identical in Edit, Preview and Public; this
/// only tells *chrome* where the header ends so chrome can get out of its way.
/// A band inserted into the content column would move every block below it.
class WebsiteHeaderOverlayBoundary
    extends InheritedNotifier<ValueNotifier<WebsiteHeaderOverlayGeometry>> {
  const WebsiteHeaderOverlayBoundary({
    super.key,
    required ValueNotifier<WebsiteHeaderOverlayGeometry> boundary,
    required super.child,
  }) : super(notifier: boundary);

  static WebsiteHeaderOverlayGeometry of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<WebsiteHeaderOverlayBoundary>()
          ?.notifier
          ?.value ??
      const WebsiteHeaderOverlayGeometry();

  static ValueListenable<WebsiteHeaderOverlayGeometry>? listenableOf(
    BuildContext context,
  ) =>
      context
          .dependOnInheritedWidgetOfExactType<WebsiteHeaderOverlayBoundary>()
          ?.notifier;
}

/// Reports the header's composition to the nearest boundary owner.
///
/// Mounted once, at the single site every composition builds the header
/// through, so none of them carries a rule of its own. It adds no size, no
/// padding and no paint: it wraps the header it is given and measures it after
/// layout.
class WebsiteMeasuredOverlayHeader extends StatefulWidget {
  const WebsiteMeasuredOverlayHeader({
    super.key,
    required this.overlaysDocument,
    required this.visualOverlay,
    required this.child,
  });

  /// Whether this composition floats the header over the document.
  final bool overlaysDocument;

  /// Whether the header is painted transparent over the content right now.
  final bool visualOverlay;

  final Widget child;

  @override
  State<WebsiteMeasuredOverlayHeader> createState() =>
      _WebsiteMeasuredOverlayHeaderState();
}

class _WebsiteMeasuredOverlayHeaderState
    extends State<WebsiteMeasuredOverlayHeader> {
  final GlobalKey _measureKey = GlobalKey();
  ValueNotifier<WebsiteHeaderOverlayGeometry>? _boundary;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _boundary = WebsiteHeaderOverlayBoundary.listenableOf(context)
        as ValueNotifier<WebsiteHeaderOverlayGeometry>?;
  }

  void _publish() {
    final boundary = _boundary;
    if (boundary == null) return;
    final box = _measureKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final next = WebsiteHeaderOverlayGeometry(
      overlaysDocument: widget.overlaysDocument,
      visualOverlay: widget.visualOverlay,
      height: box.size.height,
    );
    if (boundary.value == next) return;
    boundary.value = next;
  }

  @override
  Widget build(BuildContext context) {
    // Published after layout, never during it: the value describes the frame
    // that was just laid out, and writing a notifier mid-build would rebuild
    // its listeners inside the same frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _publish();
    });
    return KeyedSubtree(key: _measureKey, child: widget.child);
  }
}
