import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../themes/vinabike_theme_roles.dart';

typedef VbAnchoredPopoverContentTransitionBuilder = Widget Function(
  BuildContext context,
  Animation<double> animation,
  Widget child,
);

/// Anchored popover surface defined by the Viñabike component guide.
///
/// Guide, section S-05 (`Select corto`), verbatim on the two rules that matter:
/// *"Popover anclado al campo, mismo ancho o más, 4 px de gap, se voltea si no
/// cabe"* and *"Jamás un modal centrado"*. Section F-05 fixes the depth ladder
/// (`raised · popover · overlay`) and the motion budget (`base 200` for a
/// popover). The date-picker entry repeats the intent for the whole ERP: *"en
/// desktop el calendario es un popover anclado al campo — el modal centrado con
/// fondo oscuro se elimina"*.
///
/// So this route deliberately has **no scrim**: dimming the app is the centred
/// modal's signature, and the guide removes it. The anchor stays visible and in
/// place, which is the point of anchoring to it.
///
/// Touch is out of scope here — the guide sends compact viewports to a bottom
/// sheet ("la lista es un bottom sheet, no un popover de 200 px"), so callers
/// pick the presentation before reaching this helper.
Future<T?> showVbAnchoredPopover<T>({
  required BuildContext anchorContext,
  required WidgetBuilder builder,
  double gap = 4,
  double minWidth = 0,
  String barrierLabel = 'Cerrar',
  VbAnchoredPopoverContentTransitionBuilder? contentTransitionBuilder,
}) {
  final navigator = Navigator.of(anchorContext, rootNavigator: true);
  final overlayBox =
      navigator.overlay!.context.findRenderObject() as RenderBox?;
  final anchorBox = anchorContext.findRenderObject() as RenderBox?;

  // Without a laid-out anchor there is nothing to anchor TO. Falling back to a
  // centred dialog here would silently reintroduce exactly what the guide
  // removes, so callers get null and can decide.
  if (overlayBox == null || anchorBox == null || !anchorBox.hasSize) {
    return Future<T?>.value();
  }

  // The ERP can render its whole desktop shell through `WindowZoomScope`.
  // Transform BOTH corners into the overlay coordinate system: combining a
  // transformed origin with the render box's untransformed size detaches the
  // popover from its trigger at any scale other than 1.0.
  final topLeft = anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox);
  final bottomRight = anchorBox.localToGlobal(
    anchorBox.size.bottomRight(Offset.zero),
    ancestor: overlayBox,
  );
  final anchorRect = Rect.fromPoints(topLeft, bottomRight);

  return navigator.push<T>(
    _VbAnchoredPopoverRoute<T>(
      anchorRect: anchorRect,
      gap: gap,
      minWidth: math.max(minWidth, anchorRect.width),
      barrierLabel: barrierLabel,
      builder: builder,
      contentTransitionBuilder: contentTransitionBuilder,
    ),
  );
}

class _VbAnchoredPopoverRoute<T> extends PopupRoute<T> {
  _VbAnchoredPopoverRoute({
    required this.anchorRect,
    required this.gap,
    required this.minWidth,
    required this.barrierLabel,
    required this.builder,
    required this.contentTransitionBuilder,
  });

  final Rect anchorRect;
  final double gap;
  final double minWidth;
  final WidgetBuilder builder;
  final VbAnchoredPopoverContentTransitionBuilder? contentTransitionBuilder;

  @override
  final String barrierLabel;

  @override
  bool get barrierDismissible => true;

  /// No dim. See the class doc: the scrim is the centred modal's signature.
  @override
  Color? get barrierColor => null;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 120);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final media = MediaQuery.of(context);
    return CustomSingleChildLayout(
      delegate: _VbAnchoredPopoverLayout(
        anchorRect: anchorRect,
        gap: gap,
        minWidth: minWidth,
        padding: media.padding + const EdgeInsets.all(8),
      ),
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            // Guide: Esc closes without changing the value.
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) => Navigator.of(context).maybePop(),
            ),
          },
          child: FocusScope(
            autofocus: true,
            child: Builder(
              builder: (context) {
                final content = builder(context);
                final transitionBuilder = contentTransitionBuilder;
                return transitionBuilder == null
                    ? content
                    : transitionBuilder(context, animation, content);
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (contentTransitionBuilder != null) return child;
    final curved = CurvedAnimation(
      parent: animation,
      // F-05: cubic-bezier(.22, 1, .36, 1).
      curve: const Cubic(0.22, 1, 0.36, 1),
      reverseCurve: Curves.easeOutCubic,
    );
    // `reduce-motion` must not translate anything, per F-05.
    if (MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(opacity: curved, child: child);
    }
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.02),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

class _VbAnchoredPopoverLayout extends SingleChildLayoutDelegate {
  _VbAnchoredPopoverLayout({
    required this.anchorRect,
    required this.gap,
    required this.minWidth,
    required this.padding,
  });

  final Rect anchorRect;
  final double gap;
  final double minWidth;
  final EdgeInsets padding;

  /// Never open a popover shorter than this; below it, flipping is pointless
  /// and the caller should have used a sheet.
  static const double _minUsableHeight = 160;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final below =
        constraints.maxHeight - anchorRect.bottom - gap - padding.bottom;
    final above = anchorRect.top - gap - padding.top;
    final available = math.max(below, above);
    final maxHeight = available
        .clamp(
          math.min(_minUsableHeight, constraints.maxHeight),
          constraints.maxHeight,
        )
        .toDouble();
    final maxWidth = math.max(constraints.maxWidth - padding.horizontal, 0.0);
    return BoxConstraints(
      minWidth: math.min(minWidth, maxWidth),
      maxWidth: maxWidth,
      maxHeight: math.max(maxHeight, 0.0),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    // Guide: open below with a 4 px gap, flip above when it does not fit.
    final fitsBelow = anchorRect.bottom + gap + childSize.height <=
        size.height - padding.bottom;
    final double y = fitsBelow
        ? anchorRect.bottom + gap
        : anchorRect.top - gap - childSize.height;

    // Leading-aligned when it fits. If it would overflow, align the trailing
    // edges before clamping to the viewport. This preserves the relationship
    // with a trigger near the right edge instead of pinning the menu to an
    // unrelated screen edge.
    final maxX =
        math.max(padding.left, size.width - childSize.width - padding.right);
    final leadingX = anchorRect.left;
    final preferredX = leadingX + childSize.width <= size.width - padding.right
        ? leadingX
        : anchorRect.right - childSize.width;
    final x = preferredX.clamp(padding.left, maxX);

    final maxY =
        math.max(padding.top, size.height - childSize.height - padding.bottom);
    return Offset(x, y.clamp(padding.top, maxY));
  }

  @override
  bool shouldRelayout(_VbAnchoredPopoverLayout oldDelegate) {
    return anchorRect != oldDelegate.anchorRect ||
        gap != oldDelegate.gap ||
        minWidth != oldDelegate.minWidth ||
        padding != oldDelegate.padding;
  }
}

/// The popover's own surface, taken from the component guide's source rather
/// than estimated.
///
/// Guide F-05 publishes the depth ladder as literal CSS:
///
/// ```text
/// raised   0 1px  2px rgba(12,37,55,.06)
/// popover  0 6px 22px rgba(12,37,55,.13)   <- this surface
/// overlay  0 12px 40px rgba(12,37,55,.22)
/// ```
///
/// and O-02 (`VbPopover`) draws the container as `background:#fff · border:1px
/// solid #E2E7ED · border-radius:10px` with that popover shadow.
///
/// Those hexes are NOT copied here: the guide's first rule is "PROHIBIDO EL HEX
/// LITERAL EN CUALQUIER WIDGET — VbTokens es la fuente", so each one is bound to
/// the role that resolves to it (`#FFFFFF` → surface, `#E2E7ED` → divider,
/// `rgba(12,37,55,…)` → the shell canvas, which is exactly `#0C2537`). The
/// surface then follows preset and brightness on its own.
class VbPopoverSurface extends StatelessWidget {
  const VbPopoverSurface({
    super.key,
    required this.child,
    this.width,
  });

  final Widget child;
  final double? width;

  /// `radius.panel`, per O-02.
  static const double _radius = 10;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.maybeOf(context);
    final isDark = theme.brightness == Brightness.dark;

    // The guide tints the shadow with the shell navy, not with black.
    final shadowTint = roles?.shell.canvas ?? const Color(0xFF0C2537);

    // Light alpha is the guide's .13. The dark figure is NOT sourced: the
    // guide's "16 Dark mode" section sits past the 256 KiB the file API
    // returns, so it is an extrapolation — a navy shadow at .13 is invisible
    // on a dark canvas. Replace it once that section can be read.
    final shadowAlpha = isDark ? 0.42 : 0.13;

    Widget surface = Material(
      color: scheme.surface,
      elevation: 0,
      borderRadius: BorderRadius.circular(_radius),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_radius),
          border: Border.all(color: theme.dividerColor),
        ),
        child: child,
      ),
    );
    if (width != null) {
      surface = SizedBox(width: width, child: surface);
    }

    // The shadow lives OUTSIDE the clipping Material. Painting it on a child of
    // a `Clip.antiAlias` Material — the previous shape here — clipped it away
    // entirely, which is why the popover read as a flat slab with no lift.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: [
          BoxShadow(
            color: shadowTint.withValues(alpha: shadowAlpha),
            blurRadius: 22,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: surface,
    );
  }
}
