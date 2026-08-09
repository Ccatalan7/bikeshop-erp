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
  ///
  /// This is the bar itself and **never** includes the system inset. t10 10e
  /// and t11 11a both draw the phone frame as two stacked bands — a
  /// `safearea_top: 44` of `--shell` and then a `topbar: 48` of `--shell` — so
  /// the status bar has its own band and the bar keeps its full height under
  /// it. Adding the inset into this constant is what produced a 48 bar with
  /// the clock printed across its identity line.
  static const double topBarHeight = 48;

  /// The whole band the editor bar occupies at the top of the screen.
  ///
  /// **One owner for the arithmetic.** The bar, the content anchor below it and
  /// any overlay stacked with them must agree to the pixel, and they used to
  /// agree only by three independent literal `48`s — which was correct exactly
  /// while the top inset was zero. On a device with a status bar the bar was
  /// laid out at 48 with the inset painted *inside* it (identity under the
  /// clock, row compressed) and the canvas began at 48 instead of at
  /// `inset + 48`.
  ///
  /// [topInset] is `MediaQuery.padding.top` at the bar's own position, so an
  /// ancestor that already consumed the inset correctly yields plain
  /// [topBarHeight].
  static double topBandHeightFor(double topInset) => topInset + topBarHeight;

  /// The published phone inset in t10 10e / t11 11a (`safearea_top: 44`).
  ///
  /// Design's own reference figure, kept for the contract tests. The runtime
  /// value always comes from `MediaQuery.padding.top` — a device is the only
  /// authority on its own inset — and this constant exists so a guard can
  /// state that the bar reserves the band instead of painting into it.
  static const double publishedPhoneSafeAreaTop = 44;

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
    this.contextualDockHeight = 0,
    this.topBandHeight = WebsiteEditorChromeGeometry.topBarHeight,
    required super.child,
  });

  final double editorWidth;
  final double canvasWidth;

  /// The whole band the editor bar occupies at the top, inset included.
  ///
  /// Published by the shell, which is the **only** owner allowed to read the
  /// system inset for the editor. Everything stacked with the bar — the bar's
  /// own slot, the canvas below it, the inspector pane, the draft-recovery
  /// notice, any overlay — positions against this one number, so they cannot
  /// disagree the way three independent literal `48`s did.
  ///
  /// It already accounts for the ERP workspace bar: when that bar is above the
  /// editor it has consumed the status area, and the shell removes the top
  /// padding for its subtree so this value collapses back to [topBarHeight].
  /// Reading `MediaQuery.padding.top` again anywhere below would double it.
  final double topBandHeight;

  /// Height the contextual dock currently occupies at the bottom of the
  /// editor, or 0 when no dock is mounted.
  ///
  /// **Measured, never chosen.** t10 frame 10e publishes the dock's row
  /// (`dock_row: 48`) and the bottom safe area (`safearea_bottom: 20`), but the
  /// band the canvas actually loses is the composed widget: identity row plus
  /// action row plus the `SafeArea` the dock already consumes for itself. The
  /// shell measures the real thing and publishes it here so consumers reserve
  /// exactly that and never add a second `SafeArea` on top of it.
  ///
  /// It exists because the canvas is a scroll view and the dock floats over its
  /// bottom: without reserving the band, the last block of a page can never be
  /// fully seen, and a block revealed at the end of the document lands under
  /// the dock instead of in view.
  final double contextualDockHeight;

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
        canvasWidth != oldWidget.canvasWidth ||
        contextualDockHeight != oldWidget.contextualDockHeight ||
        topBandHeight != oldWidget.topBandHeight;
  }
}

/// Publishes the viewport the authoring controls are actually editing.
///
/// [WebsiteEditModeProvider.previewViewport] is the operator's requested
/// device. A compact host may have to shrink that frame, so the rendered page
/// can legitimately be Mobile while the selector still says Desktop. The
/// inspector must resolve and write the same document branch the page renders;
/// keeping requested and effective as separate values also lets chrome explain
/// the clamp without mutating the operator's selection.
///
/// Canvas layers have a stricter, per-document measurement owner. This scope
/// owns the page/block inspector only; Canvas actions continue to use
/// `renderedCanvasViewport(documentTarget)`.
class WebsiteEditorAuthoringViewportScope extends InheritedWidget {
  const WebsiteEditorAuthoringViewportScope({
    super.key,
    required this.requestedViewport,
    required this.effectiveViewport,
    required super.child,
  });

  final WebsiteViewport requestedViewport;
  final WebsiteViewport effectiveViewport;

  static WebsiteEditorAuthoringViewportScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<
        WebsiteEditorAuthoringViewportScope>();
  }

  static WebsiteViewport effectiveOf(
    BuildContext context, {
    required WebsiteViewport fallback,
  }) {
    return maybeOf(context)?.effectiveViewport ?? fallback;
  }

  @override
  bool updateShouldNotify(WebsiteEditorAuthoringViewportScope oldWidget) {
    return requestedViewport != oldWidget.requestedViewport ||
        effectiveViewport != oldWidget.effectiveViewport;
  }
}
