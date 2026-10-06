import 'dart:math' as math;

import '../models/website_font_registry.dart';
import '../models/website_page_composition.dart';
import 'website_theme_color_value.dart';

/// A color as Flutter holds it since 3.27: four channels from 0 to 1, so a
/// role mixed here is the very color the Flutter theme mixes, decimals
/// included (CSS draws `rgb(246.075 …)` as Flutter draws it).
class WebsiteRgba {
  const WebsiteRgba(this.a, this.r, this.g, this.b);

  factory WebsiteRgba.fromArgb(int argb) => WebsiteRgba(
    ((argb >> 24) & 0xFF) / 255,
    ((argb >> 16) & 0xFF) / 255,
    ((argb >> 8) & 0xFF) / 255,
    (argb & 0xFF) / 255,
  );

  static const white = WebsiteRgba(1, 1, 1, 1);

  final double a;
  final double r;
  final double g;
  final double b;

  /// `Color.lerp`: every channel, alpha included, moves by [t].
  static WebsiteRgba lerp(WebsiteRgba from, WebsiteRgba to, double t) =>
      WebsiteRgba(
        from.a + (to.a - from.a) * t,
        from.r + (to.r - from.r) * t,
        from.g + (to.g - from.g) * t,
        from.b + (to.b - from.b) * t,
      );

  /// `Color.withValues(alpha:)`.
  WebsiteRgba withAlpha(double alpha) => WebsiteRgba(alpha, r, g, b);

  /// `Color.alphaBlend`: [foreground] painted over [background].
  static WebsiteRgba alphaBlend(
    WebsiteRgba foreground,
    WebsiteRgba background,
  ) {
    final alpha = foreground.a;
    if (alpha == 0) return background;
    final invAlpha = 1 - alpha;
    var backAlpha = background.a;
    if (backAlpha == 1) {
      return WebsiteRgba(
        1,
        alpha * foreground.r + invAlpha * background.r,
        alpha * foreground.g + invAlpha * background.g,
        alpha * foreground.b + invAlpha * background.b,
      );
    }
    backAlpha = backAlpha * invAlpha;
    final outAlpha = alpha + backAlpha;
    return WebsiteRgba(
      outAlpha,
      (foreground.r * alpha + background.r * backAlpha) / outAlpha,
      (foreground.g * alpha + background.g * backAlpha) / outAlpha,
      (foreground.b * alpha + background.b * backAlpha) / outAlpha,
    );
  }

  /// The WCAG contrast ratio between two colors, alpha ignored.
  static double contrast(WebsiteRgba a, WebsiteRgba b) {
    final la = a.luminance;
    final lb = b.luminance;
    final lighter = math.max(la, lb);
    final darker = math.min(la, lb);
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// White or the store's dark ink, whichever reads better on [background]
  /// (`_readableForeground` of the Flutter themes).
  static WebsiteRgba readableOn(WebsiteRgba background) {
    final ink = WebsiteRgba.fromArgb(0xFF17211B);
    return contrast(WebsiteRgba.white, background) >= contrast(ink, background)
        ? WebsiteRgba.white
        : ink;
  }

  /// `Color.computeLuminance`: relative luminance, alpha ignored.
  double get luminance {
    double linear(double c) => c <= 0.03928
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b);
  }

  /// `rgb(r g b / a)` with up to three decimals.
  String get css {
    String channel(double value) => _trim(value * 255);
    final rgb = '${channel(r)} ${channel(g)} ${channel(b)}';
    return a >= 1 ? 'rgb($rgb)' : 'rgb($rgb / ${_trim(a)})';
  }

  static String _trim(double value) {
    final fixed = value.toStringAsFixed(3);
    return fixed.contains('.')
        ? fixed.replaceFirst(RegExp(r'\.?0+$'), '')
        : fixed;
  }
}

/// The editor theme as the public pages draw it: `WebsiteResolvedTheme`
/// (settings read with its defaults and limits) and the color roles
/// `WebsiteThemeBuilder` derives from it. Pure Dart, so the HTML storefront
/// draws the same colors; `test/unit/website_theme_roles_parity_test.dart`
/// holds it to the Flutter theme.
class WebsiteThemeRoles {
  const WebsiteThemeRoles._({
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.onAccent,
    required this.background,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.outline,
    required this.outlineVariant,
    required this.headingFont,
    required this.bodyFont,
    required this.headingSize,
    required this.bodySize,
    required this.sectionSpacing,
    required this.containerPadding,
    required this.buttonStyle,
    required this.buttonSize,
  });

  static const defaultPrimaryColor = 0xFF123F68;
  static const defaultAccentColor = 0xFFFF6F00;
  static const defaultBackgroundColor = 0xFFFFFFFF;
  static const defaultTextColor = 0xFF1E293B;
  static const defaultHeadingSize = 48.0;
  static const defaultBodySize = 16.0;
  static const defaultContainerPadding = 24.0;
  static const minContainerPadding = 16.0;
  static const maxContainerPadding = 64.0;

  /// [read] returns the saved setting, or '' when there is none.
  factory WebsiteThemeRoles.resolve(String Function(String key) read) {
    final primary = WebsiteRgba.fromArgb(
      parseWebsiteThemeColorValue(read('theme_primary_color')) ??
          defaultPrimaryColor,
    );
    final accent = WebsiteRgba.fromArgb(
      parseWebsiteThemeColorValue(read('theme_accent_color')) ??
          defaultAccentColor,
    );
    final background = WebsiteRgba.fromArgb(
      parseWebsiteThemeColorValue(read('theme_background_color')) ??
          defaultBackgroundColor,
    );
    final explicitText = parseWebsiteThemeColorValue(read('theme_text_color'));
    // A valid editor value is kept as is; only an absent or malformed one
    // gets the contrast-safe fallback for the background.
    final onSurface = explicitText != null
        ? WebsiteRgba.fromArgb(explicitText)
        : _readableTextFallback(background);

    WebsiteRgba tone(WebsiteRgba from, WebsiteRgba to, double t) =>
        WebsiteRgba.lerp(from, to, t);

    return WebsiteThemeRoles._(
      primary: primary,
      onPrimary: _readableForeground(primary),
      accent: accent,
      onAccent: _readableForeground(accent),
      background: background,
      onSurface: onSurface,
      onSurfaceVariant: tone(onSurface, background, 0.24),
      surfaceContainerLow: tone(background, onSurface, 0.035),
      surfaceContainer: tone(background, onSurface, 0.065),
      surfaceContainerHigh: tone(background, onSurface, 0.095),
      outline: tone(background, onSurface, 0.30),
      outlineVariant: tone(background, onSurface, 0.16),
      headingFont: WebsiteFontRegistry.resolveHeadingFont(
        read('theme_heading_font'),
      ),
      bodyFont: WebsiteFontRegistry.resolveBodyFont(read('theme_body_font')),
      headingSize: _resolveDouble(
        read('theme_heading_size'),
        defaultHeadingSize,
        min: 24,
        max: 72,
      ),
      bodySize: _resolveDouble(
        read('theme_body_size'),
        defaultBodySize,
        min: 12,
        max: 24,
      ),
      sectionSpacing: WebsitePageComposition.resolveSectionSpacing(
        read('theme_section_spacing'),
      ),
      containerPadding: _resolveDouble(
        read('theme_container_padding'),
        defaultContainerPadding,
        min: minContainerPadding,
        max: maxContainerPadding,
      ),
      buttonStyle: switch (read('button_style').trim().toLowerCase()) {
        'sharp' => 'sharp',
        'pill' => 'pill',
        _ => 'rounded',
      },
      buttonSize: switch (read('button_size').trim().toLowerCase()) {
        'small' => 'small',
        'large' => 'large',
        _ => 'medium',
      },
    );
  }

  final WebsiteRgba primary;
  final WebsiteRgba onPrimary;
  final WebsiteRgba accent;
  final WebsiteRgba onAccent;
  final WebsiteRgba background;
  final WebsiteRgba onSurface;
  final WebsiteRgba onSurfaceVariant;
  final WebsiteRgba surfaceContainerLow;
  final WebsiteRgba surfaceContainer;
  final WebsiteRgba surfaceContainerHigh;
  final WebsiteRgba outline;
  final WebsiteRgba outlineVariant;
  final String headingFont;
  final String bodyFont;
  final double headingSize;
  final double bodySize;
  final double sectionSpacing;
  final double containerPadding;
  final String buttonStyle;
  final String buttonSize;

  static double _contrast(WebsiteRgba a, WebsiteRgba b) {
    final la = a.luminance;
    final lb = b.luminance;
    final lighter = math.max(la, lb);
    final darker = math.min(la, lb);
    return (lighter + 0.05) / (darker + 0.05);
  }

  static WebsiteRgba _readableForeground(WebsiteRgba background) {
    final ink = WebsiteRgba.fromArgb(0xFF17211B);
    return _contrast(WebsiteRgba.white, background) >=
            _contrast(ink, background)
        ? WebsiteRgba.white
        : ink;
  }

  static WebsiteRgba _readableTextFallback(WebsiteRgba background) {
    final text = WebsiteRgba.fromArgb(defaultTextColor);
    return _contrast(text, background) >=
            _contrast(WebsiteRgba.white, background)
        ? text
        : WebsiteRgba.white;
  }

  static double _resolveDouble(
    String raw,
    double fallback, {
    required double min,
    required double max,
  }) {
    final parsed = double.tryParse(raw.trim());
    if (parsed == null || !parsed.isFinite) return fallback;
    return parsed.clamp(min, max).toDouble();
  }
}
