import 'package:flutter/material.dart';

import '../../../shared/widgets/vb_segmented.dart';
import 'website_editor_chrome_geometry.dart';

/// Publishes the input density for the Website Builder inspector subtree.
///
/// `F-06` forces touch density below 900 logical pixels, including tablet.
/// The decision belongs to the editor host, not to each control and not to the
/// inspector's local width: a 420 px pane on a desktop host is still a pointer
/// surface. [WebsiteEditorChromeScope] therefore wins when it is available;
/// standalone test/embedded hosts fall back to [VbDensity.resolve].
class WebsiteEditorControlDensityScope extends InheritedWidget {
  const WebsiteEditorControlDensityScope({
    super.key,
    required this.density,
    required super.child,
  });

  factory WebsiteEditorControlDensityScope.resolved({
    Key? key,
    required BuildContext context,
    required Widget child,
  }) {
    final inherited = maybeOf(context);
    final density = inherited?.density ??
        WebsiteEditorChromeScope.maybeOf(context)?.density ??
        VbDensity.resolve(context);
    return WebsiteEditorControlDensityScope(
      key: key,
      density: density,
      child: child,
    );
  }

  final VbDensity density;

  bool get isTouch => density.isTouch;

  /// Minimum hit extent contributed by this scope.
  ///
  /// Pointer density contributes no new minimum so the pane keeps its existing
  /// compact geometry. Touch uses the canonical `F-06` control height exposed
  /// by [VbDensity], rather than restating 48 at every consumer.
  double get minimumInteractiveExtent => isTouch ? density.controlHeight : 0;

  /// Resolves a complete target while preserving the control's pointer size.
  double targetExtentFor(double pointerExtent) {
    final minimum = minimumInteractiveExtent;
    return pointerExtent < minimum ? minimum : pointerExtent;
  }

  static WebsiteEditorControlDensityScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<WebsiteEditorControlDensityScope>();
  }

  static WebsiteEditorControlDensityScope of(BuildContext context) {
    final result = maybeOf(context);
    assert(
      result != null,
      'Website editor controls must be mounted under '
      'WebsiteEditorControlDensityScope.',
    );
    return result!;
  }

  @override
  bool updateShouldNotify(WebsiteEditorControlDensityScope oldWidget) =>
      density != oldWidget.density;
}

/// Transparent hit-target adapter shared by O-05 and the pointer pane.
///
/// [child] keeps its visual geometry. The adapter expands only the interactive
/// box when the surrounding density scope requires it, and leaves pointer
/// controls at their existing size. This is intentionally separate from
/// business callbacks and responsive write scope: it owns input geometry only.
class WebsiteEditorControlTarget extends StatelessWidget {
  const WebsiteEditorControlTarget({
    super.key,
    required this.targetKey,
    required this.child,
    required this.onTap,
    this.semanticLabel,
    this.minimumWidth = false,
    this.semanticsButton = true,
    this.selected,
    this.borderRadius = const BorderRadius.all(Radius.circular(4)),
  });

  final Key targetKey;
  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final bool minimumWidth;
  final bool semanticsButton;
  final bool? selected;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final minimumTarget =
        WebsiteEditorControlDensityScope.of(context).minimumInteractiveExtent;
    final target = Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: targetKey,
        onTap: onTap,
        excludeFromSemantics: !semanticsButton,
        borderRadius: borderRadius,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: minimumWidth ? minimumTarget : 0,
            minHeight: minimumTarget,
          ),
          child: Align(
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
    if (!semanticsButton) return target;
    return Semantics(
      button: true,
      enabled: onTap != null,
      selected: selected,
      label: semanticLabel,
      child: target,
    );
  }
}
