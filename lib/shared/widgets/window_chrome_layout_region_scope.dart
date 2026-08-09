import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Publishes UIKit's adaptive horizontal margins independently of MediaQuery.
class WindowChromeLayoutRegionScope extends InheritedWidget {
  const WindowChromeLayoutRegionScope({
    required this.margins,
    required super.child,
    super.key,
  });

  final EdgeInsets margins;

  static EdgeInsets marginsOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<WindowChromeLayoutRegionScope>()
          ?.margins ??
      EdgeInsets.zero;

  @override
  bool updateShouldNotify(WindowChromeLayoutRegionScope oldWidget) =>
      margins != oldWidget.margins;
}

/// SafeArea for top-level control rows that also understands iPadOS 26 chrome.
///
/// Each edge is resolved with `max(safe, adapted, design)`, never by adding
/// independent inset families. The adaptive region participates only on the
/// horizontal axis; status bars and keyboards remain MediaQuery's authority.
class WindowChromeSafeArea extends StatelessWidget {
  const WindowChromeSafeArea({
    required this.child,
    this.minimumPadding = EdgeInsets.zero,
    this.left = true,
    this.top = true,
    this.right = true,
    this.bottom = true,
    this.maintainBottomViewPadding = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry minimumPadding;
  final bool left;
  final bool top;
  final bool right;
  final bool bottom;
  final bool maintainBottomViewPadding;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final safe = media.padding;
    final adapted = WindowChromeLayoutRegionScope.marginsOf(context);
    final minimum = minimumPadding.resolve(Directionality.of(context));
    final bottomSafe = maintainBottomViewPadding
        ? math.max(safe.bottom, media.viewPadding.bottom)
        : safe.bottom;

    final resolved = EdgeInsets.fromLTRB(
      left ? math.max(minimum.left, math.max(safe.left, adapted.left)) : 0,
      top ? math.max(minimum.top, safe.top) : 0,
      right ? math.max(minimum.right, math.max(safe.right, adapted.right)) : 0,
      bottom ? math.max(minimum.bottom, bottomSafe) : 0,
    );
    final remainingAdapted = EdgeInsets.fromLTRB(
      left ? 0 : adapted.left,
      adapted.top,
      right ? 0 : adapted.right,
      adapted.bottom,
    );

    return Padding(
      padding: resolved,
      child: MediaQuery.removePadding(
        context: context,
        removeLeft: left,
        removeTop: top,
        removeRight: right,
        removeBottom: bottom,
        child: WindowChromeLayoutRegionScope(
          margins: remainingAdapted,
          child: child,
        ),
      ),
    );
  }
}
