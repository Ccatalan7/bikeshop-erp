import 'package:flutter/widgets.dart';

import '../../../shared/utils/responsive_breakpoints.dart';
import '../../../shared/widgets/vb_segmented.dart';
import '../models/website_responsive_authoring.dart';

/// How the editor lays its own tools out for the space it actually has.
enum WebsiteEditorChromeComposition {
  /// A persistent inspector pane beside the canvas.
  pane,

  /// Dock plus contextual sheet; the canvas is never covered by a pane.
  contextual,
}

/// The single owner of the Website Builder chrome geometry.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` t10 (frames 10a, 10b, 10j, 10k) and
/// its `handoff-t10/spec.json`.
///
/// Before this owner the same decision was taken independently in four places
/// (`public_store_layout`, `persistent_editor_shell`, `website_editor_panel`
/// and `deferred_website_editor_panel`), each with its own literal `380`. That
/// width had no Design source at all: `O-04 VbSideSheet` puts a side sheet at
/// **420–540 y máx. 40% del ancho**.
///
/// Two measurements, two different decisions — and the host window decides
/// neither:
///
/// * the **canvas** width drives [WebsiteViewport] and therefore how the block
///   renders;
/// * the **editor** width drives [WebsiteEditorChromeComposition], i.e. whether
///   the tools can afford a pane.
abstract final class WebsiteEditorChromeGeometry {
  /// `O-04` · lower bound of the side-sheet range.
  static const double inspectorWidth = 420;

  /// `O-04` · a side sheet never exceeds 40% of the width.
  static const double inspectorMaxWidthFraction = 0.40;

  /// `T-05` · "el detalle nunca baja de 560 lógicos".
  static const double minimumCanvasWidth = 560;

  /// Derived, not chosen: `O-04` needs `420 / 0.40 = 1050`, `T-05` needs
  /// `560 + 420 = 980`. The binding constraint is the larger one.
  ///
  /// Below it the inspector cannot be a pane on any host, which is also what
  /// keeps tablet from needing a third composition (t10 frame 10j).
  static const double paneMinimumEditorWidth = 1050;

  /// t10 · the editor command bar.
  static const double topBarHeight = 48;

  /// Width the dense command bar needs before it may spread out.
  ///
  /// Derived, not chosen — the same way [paneMinimumEditorWidth] is. The bar
  /// carries two clusters that cannot be compressed: the three authorities
  /// (`S-04` viewport, write scope and the mode button) and the workspace
  /// navigation strip. The strip is a second `O-04`-class cluster standing
  /// beside the pane threshold, so the bar can only afford it at
  /// `paneMinimumEditorWidth + inspectorWidth`.
  ///
  /// Below it the bar keeps every capability but stops spreading: navigation
  /// collapses into its `O-01` menu and the secondary actions move to the
  /// action drawer the compact composition already owns. Above it they come
  /// back inline. Nothing is hidden at any width — only re-housed.
  static const double denseBarInlineExtrasMinimumWidth =
      paneMinimumEditorWidth + inspectorWidth;

  /// Whether the dense bar may keep its secondary actions inline.
  ///
  /// Only where the workspace strip is inline too. The secondary actions have
  /// exactly one other home — the action drawer — and that drawer is mounted
  /// precisely when the navigation collapsed. Letting the extras go inline
  /// while the navigation stayed collapsed would remove the drawer and, with
  /// it, every capability the collapsed `O-01` menu does not carry: `O-01`
  /// holds at most 7 items, so the menu is a shortlist of destinations, never
  /// the whole editor.
  static bool usesInlineBarExtras({
    required double editorWidth,
    required bool showsCanvasAuthorities,
  }) {
    return usesInlineWorkspaceNavigation(
          editorWidth: editorWidth,
          showsCanvasAuthorities: showsCanvasAuthorities,
        ) &&
        editorWidth >= denseBarInlineExtrasMinimumWidth;
  }

  /// Whether the dense bar may keep the workspace destinations inline.
  ///
  /// Only when it has the width AND is not also hosting the canvas
  /// authorities: measured against the shipped typeface, the strip and those
  /// three controls do not fit together at any width this product runs at, so
  /// offering the inline strip there would be offering an overflow.
  static bool usesInlineWorkspaceNavigation({
    required double editorWidth,
    required bool showsCanvasAuthorities,
  }) {
    if (showsCanvasAuthorities) return false;
    return editorWidth >= denseBarInlineExtrasMinimumWidth;
  }

  /// t10 frames 10b/10e · framed device preview widths.
  static const double mobileFrameWidth = 390;
  static const double tabletFrameWidth = 820;

  /// Composition for the space the editor actually has.
  ///
  /// [editorWidth] is the width available to the editor as a whole, not the
  /// host window: an ERP-mounted storefront loses the rail and any open global
  /// panel before the editor sees a pixel.
  static WebsiteEditorChromeComposition compositionFor(double editorWidth) {
    return editorWidth >= paneMinimumEditorWidth
        ? WebsiteEditorChromeComposition.pane
        : WebsiteEditorChromeComposition.contextual;
  }

  /// The inspector width for [editorWidth], or null when no pane fits.
  ///
  /// Never wider than [inspectorMaxWidthFraction]; a pane that would squeeze
  /// the canvas below [minimumCanvasWidth] does not exist at all, because
  /// `T-05` requires it to collapse on its own and say so.
  static double? paneWidthFor(double editorWidth) {
    if (compositionFor(editorWidth) != WebsiteEditorChromeComposition.pane) {
      return null;
    }
    return inspectorWidth;
  }

  /// Horizontal space the canvas keeps once the chrome took its share.
  static double canvasWidthFor(double editorWidth) {
    final pane = paneWidthFor(editorWidth);
    return pane == null ? editorWidth : editorWidth - pane;
  }

  /// The width a framed device preview paints at.
  static double frameWidthFor(
    WebsiteViewport viewport, {
    required double availableWidth,
  }) {
    final requested = switch (viewport) {
      WebsiteViewport.mobile => mobileFrameWidth,
      WebsiteViewport.tablet => tabletFrameWidth,
      WebsiteViewport.desktop => availableWidth,
    };
    // A real phone host can be narrower than the canonical 390 frame once
    // SafeArea or ERP chrome is accounted for. A preview frame may shrink to
    // fit its owner; it may never overflow and create a second horizontal
    // scroll surface around the page being edited.
    return requested > availableWidth ? availableWidth : requested;
  }

  /// The viewport class of a canvas that measures [canvasWidth].
  ///
  /// This is the correction of the defect the audit found: the block's
  /// responsive class used to be derived from the host `MediaQuery`, which in
  /// the ERP-mounted editor is the whole window and not the canvas at all.
  static WebsiteViewport viewportForCanvasWidth(double canvasWidth) =>
      WebsiteViewport.fromLogicalWidth(canvasWidth);

  /// `F-06` · below 900 logical px the density is forced to touch.
  static VbDensity densityFor(double hostWidth) {
    return hostWidth < ResponsiveBreakpoints.desktopMin
        ? VbDensity.touch
        : VbDensity.compact;
  }

  /// The host class implied by the available width.
  ///
  /// A pointer host that shrank below the pane threshold is still a pointer
  /// host; only a genuinely compact viewport is a phone.
  static WebsiteAuthoringHostClass hostClassFor(double hostWidth) {
    return hostWidth < ResponsiveBreakpoints.phoneMaxExclusive
        ? WebsiteAuthoringHostClass.phone
        : WebsiteAuthoringHostClass.desktop;
  }
}

/// Publishes the resolved chrome geometry to the editor subtree.
///
/// Consumers read one owner instead of each re-deciding a width. The scope is
/// deliberately thin: it carries measurements, never state.
class WebsiteEditorChromeScope extends InheritedWidget {
  const WebsiteEditorChromeScope({
    super.key,
    required this.editorWidth,
    required this.canvasWidth,
    required super.child,
  });

  final double editorWidth;
  final double canvasWidth;

  WebsiteEditorChromeComposition get composition =>
      WebsiteEditorChromeGeometry.compositionFor(editorWidth);

  double? get paneWidth =>
      WebsiteEditorChromeGeometry.paneWidthFor(editorWidth);

  bool get usesPane => composition == WebsiteEditorChromeComposition.pane;

  WebsiteAuthoringHostClass get hostClass =>
      WebsiteEditorChromeGeometry.hostClassFor(editorWidth);

  VbDensity get density => WebsiteEditorChromeGeometry.densityFor(editorWidth);

  /// The viewport the canvas actually renders as.
  WebsiteViewport get canvasViewport =>
      WebsiteEditorChromeGeometry.viewportForCanvasWidth(canvasWidth);

  static WebsiteEditorChromeScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<WebsiteEditorChromeScope>();
  }

  @override
  bool updateShouldNotify(WebsiteEditorChromeScope oldWidget) {
    return editorWidth != oldWidget.editorWidth ||
        canvasWidth != oldWidget.canvasWidth;
  }
}
