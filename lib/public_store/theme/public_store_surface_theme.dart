import 'package:flutter/material.dart';

import '../../modules/website/theme/website_commerce_theme.dart';
import 'public_store_theme.dart';

/// Theme-derived tokens for commerce surfaces rendered inside the public site.
///
/// Brand colors, surfaces, text, borders and button contrast come from the
/// editor-owned [ThemeData] built by `WebsiteThemeBuilder`. Status colors stay
/// semantic so success and warning meaning does not change with the brand.
@immutable
class PublicStoreSurfaceTheme {
  const PublicStoreSurfaceTheme._({
    required this.theme,
    required this.colors,
    required this.text,
  });

  factory PublicStoreSurfaceTheme.of(BuildContext context) {
    final theme = Theme.of(context);
    return PublicStoreSurfaceTheme._(
      theme: theme,
      colors: theme.colorScheme,
      text: theme.textTheme,
    );
  }

  final ThemeData theme;
  final ColorScheme colors;
  final TextTheme text;

  Color get canvas => theme.scaffoldBackgroundColor;
  Color get surface => colors.surface;
  Color get softSurface => colors.surfaceContainerLow;
  Color get raisedSurface => colors.surfaceContainer;
  Color get line => colors.outlineVariant;
  Color get strongLine => colors.outline;

  Color get primary => colors.primary;
  Color get onPrimary => colors.onPrimary;
  Color get textPrimary => colors.onSurface;
  Color get textSecondary => colors.onSurfaceVariant;
  Color get textMuted => colors.onSurface.withValues(alpha: 0.58);
  Color get disabled => colors.onSurface.withValues(alpha: 0.38);
  Color get error => colors.error;
  Color get onError => colors.onError;

  WebsiteCommerceTheme? get _commerce =>
      theme.extension<WebsiteCommerceTheme>();
  Color get commerceAccent => _commerce?.accent ?? primary;
  Color get onCommerceAccent => _commerce?.onAccent ?? onPrimary;
  Color get commerceTextPrimary => _commerce?.textPrimary ?? textPrimary;
  Color get commerceLine => _commerce?.line ?? line;
  Color get commerceTextSecondary => Color.alphaBlend(
        commerceTextPrimary.withValues(alpha: 0.68),
        surface,
      );
  Color get commerceTextMuted => Color.alphaBlend(
        commerceTextPrimary.withValues(alpha: 0.48),
        surface,
      );

  Color get warning => PublicStoreTheme.warning;
  Color get warningSurface => Color.alphaBlend(
        warning.withValues(alpha: 0.12),
        surface,
      );
  Color get onWarningSurface => _readableForeground(warningSurface);

  Color get success => _ensureContrast(
        PublicStoreTheme.successGreen,
        surface,
        minimumRatio: 4.5,
      );

  /// Foreground for content sitting *on* [success] — a confirmed button, for
  /// instance. Declared here so a feature never has to guess at white.
  Color get onSuccess => _readableForeground(success);

  static Color _ensureContrast(
    Color semantic,
    Color background, {
    required double minimumRatio,
  }) {
    if (_contrastRatio(semantic, background) >= minimumRatio) {
      return semantic;
    }

    final target = _readableForeground(background);
    for (var step = 1; step <= 20; step++) {
      final candidate = Color.lerp(semantic, target, step / 20) ?? semantic;
      if (_contrastRatio(candidate, background) >= minimumRatio) {
        return candidate;
      }
    }
    return target;
  }

  static Color _readableForeground(Color background) {
    final lightRatio = _contrastRatio(Colors.white, background);
    final darkRatio = _contrastRatio(const Color(0xFF17211B), background);
    return lightRatio >= darkRatio ? Colors.white : const Color(0xFF17211B);
  }

  static double _contrastRatio(Color a, Color b) {
    final aLuminance = a.computeLuminance();
    final bLuminance = b.computeLuminance();
    final lighter = aLuminance > bLuminance ? aLuminance : bLuminance;
    final darker = aLuminance > bLuminance ? bLuminance : aLuminance;
    return (lighter + 0.05) / (darker + 0.05);
  }
}
