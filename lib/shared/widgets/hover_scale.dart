import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class HoverScale extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final double hoverScale;
  final double pressedScale;
  final Duration duration;
  final Curve curve;
  final MouseCursor cursor;

  const HoverScale({
    super.key,
    required this.child,
    this.enabled = true,
    this.hoverScale = 1.02,
    this.pressedScale = 0.98,
    this.duration = const Duration(milliseconds: 140),
    this.curve = Curves.easeOutCubic,
    this.cursor = SystemMouseCursors.click,
  });

  @override
  State<HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<HoverScale> {
  bool _isHovered = false;
  bool _isPressed = false;

  bool get _reduceMotion {
    final mediaQuery = MediaQuery.maybeOf(context);
    return (mediaQuery?.disableAnimations ?? false) ||
        (mediaQuery?.accessibleNavigation ?? false);
  }

  void _setHovered(bool value) {
    if (!mounted) return;
    if (_isHovered == value) return;
    setState(() => _isHovered = value);
  }

  void _setPressed(bool value) {
    if (!mounted) return;
    if (_isPressed == value) return;
    setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || _reduceMotion) {
      return widget.child;
    }

    final bool canHover = kIsWeb ||
        {
          TargetPlatform.macOS,
          TargetPlatform.windows,
          TargetPlatform.linux,
        }.contains(defaultTargetPlatform);

    final double scale = _isPressed
        ? widget.pressedScale
        : (_isHovered ? widget.hoverScale : 1.0);

    Widget result = AnimatedScale(
      scale: scale,
      duration: widget.duration,
      curve: widget.curve,
      child: widget.child,
    );

    result = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: result,
    );

    if (canHover) {
      result = MouseRegion(
        cursor: widget.cursor,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: result,
      );
    }

    return result;
  }
}
