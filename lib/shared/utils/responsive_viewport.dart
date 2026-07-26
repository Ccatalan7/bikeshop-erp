import 'package:flutter/material.dart';

import '../widgets/window_zoom_scope.dart';
import 'responsive_breakpoints.dart';

/// Canonical responsive boundaries measured in the unzoomed logical viewport.
///
/// [WindowZoomScope] publishes the real root constraints even when it changes
/// the descendant [MediaQuery] to zoom a desktop surface. Compact surfaces
/// therefore keep the same product class and real touch density regardless of
/// the stored desktop zoom preference.
abstract final class ResponsiveViewport {
  static const double phoneMaxExclusive =
      ResponsiveBreakpoints.phoneMaxExclusive;
  static const double desktopMin = ResponsiveBreakpoints.desktopMin;

  static double widthOf(BuildContext context) =>
      WindowViewportMetrics.maybeOf(context)?.unzoomedViewportSize.width ??
      MediaQuery.sizeOf(context).width;

  static bool usesCompactShell(BuildContext context) =>
      widthOf(context) < desktopMin;
}
