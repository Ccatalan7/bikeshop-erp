import 'dart:ui';

import 'package:flutter/material.dart';

/// Frosted toolbar surface used by the right-side quick panels.
///
/// The fill is intentionally high-alpha: it gives the panel the matte/blurred
/// feel without sacrificing readability on data-dense ERP screens.
class RightToolbarGlassSurface extends StatelessWidget {
  final Widget child;
  final Color? tint;
  final Border? border;
  final double blurSigma;

  const RightToolbarGlassSurface({
    super.key,
    required this.child,
    this.tint,
    this.border,
    this.blurSigma = 22,
  });

  Color _surfaceFill(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final base =
        tint ?? (isDark ? const Color(0xFF23272A) : const Color(0xFFF8FAFC));
    final alpha = base.computeLuminance() < 0.35 ? 0.74 : 0.78;
    return base.withValues(alpha: alpha);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _surfaceFill(theme),
            border: border,
          ),
          child: child,
        ),
      ),
    );
  }
}
