import 'dart:ui';

import 'package:flutter/material.dart';

/// Frosted toolbar surface used by the right-side quick panels.
///
/// The fill stays translucent so underlying ERP content visibly blurs through,
/// while still keeping enough matte tint for dense controls to remain readable.
class RightToolbarGlassSurface extends StatelessWidget {
  final Widget child;
  final Color? tint;
  final Border? border;
  final double blurSigma;
  final bool blurEnabled;

  const RightToolbarGlassSurface({
    super.key,
    required this.child,
    this.tint,
    this.border,
    this.blurSigma = 34,
    this.blurEnabled = true,
  });

  Color _surfaceFill(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final base =
        tint ?? (isDark ? const Color(0xFF23272A) : const Color(0xFFF8FAFC));
    final alpha = blurEnabled
        ? (base.computeLuminance() < 0.35 ? 0.62 : 0.58)
        : (base.computeLuminance() < 0.35 ? 0.94 : 0.96);
    return base.withValues(alpha: alpha);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: _surfaceFill(theme),
        border: border,
      ),
      child: child,
    );

    if (!blurEnabled) {
      return surface;
    }

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: surface,
      ),
    );
  }
}
