import 'package:flutter/material.dart';

import '../models/website_font_registry.dart';
import '../models/website_page_composition.dart';

typedef WebsiteThemeSettingReader = String Function(
  String key,
  String fallback,
);

/// Canonical, immutable result of resolving Website Builder theme settings.
///
/// The storefront shell resolves this value once from saved settings plus the
/// active editor draft. Renderers consume the published [ThemeExtension]
/// instead of interpreting settings, defaults or legacy color formats again.
@immutable
class WebsiteResolvedTheme extends ThemeExtension<WebsiteResolvedTheme> {
  const WebsiteResolvedTheme({
    required this.primaryColor,
    required this.accentColor,
    required this.backgroundColor,
    required this.textColor,
    required this.headingFont,
    required this.bodyFont,
    required this.headingSize,
    required this.bodySize,
    required this.sectionSpacing,
    required this.containerPadding,
    required this.buttonStyle,
    required this.buttonSize,
    required this.commerceAccentColor,
    required this.commerceTextColor,
    required this.commerceLineColor,
  });

  // Existing storefront/editor defaults, moved here so controls, shell and
  // every renderer share one owner. These are not a new visual direction.
  static const defaultPrimaryColor = Color(0xFF2563EB);
  static const defaultAccentColor = Color(0xFF25D366);
  static const defaultBackgroundColor = Colors.white;
  static const defaultTextColor = Color(0xFF1E293B);
  static const defaultCommerceAccentColor = Color(0xFF123F68);
  static const defaultCommerceTextColor = Color(0xFF1E293B);
  static const defaultCommerceLineColor = Color(0xFFE8E2D8);
  static const defaultHeadingSize = 48.0;
  static const defaultBodySize = 16.0;
  static const defaultContainerPadding = 24.0;
  static const minContainerPadding = 16.0;
  static const maxContainerPadding = 64.0;

  static const fallback = WebsiteResolvedTheme(
    primaryColor: defaultPrimaryColor,
    accentColor: defaultAccentColor,
    backgroundColor: defaultBackgroundColor,
    textColor: defaultTextColor,
    headingFont: WebsiteFontRegistry.headingDefault,
    bodyFont: WebsiteFontRegistry.bodyDefault,
    headingSize: defaultHeadingSize,
    bodySize: defaultBodySize,
    sectionSpacing: WebsitePageComposition.defaultSectionSpacing,
    containerPadding: defaultContainerPadding,
    buttonStyle: 'rounded',
    buttonSize: 'medium',
    commerceAccentColor: defaultCommerceAccentColor,
    commerceTextColor: defaultCommerceTextColor,
    commerceLineColor: defaultCommerceLineColor,
  );

  final Color primaryColor;
  final Color accentColor;
  final Color backgroundColor;
  final Color textColor;
  final String headingFont;
  final String bodyFont;
  final double headingSize;
  final double bodySize;
  final double sectionSpacing;
  final double containerPadding;
  final String buttonStyle;
  final String buttonSize;
  final Color commerceAccentColor;
  final Color commerceTextColor;
  final Color commerceLineColor;

  static WebsiteResolvedTheme of(BuildContext context) {
    return Theme.of(context).extension<WebsiteResolvedTheme>() ?? fallback;
  }

  static WebsiteResolvedTheme resolve(WebsiteThemeSettingReader read) {
    final primaryColor = _resolveColor(
      read('theme_primary_color', ''),
      defaultPrimaryColor,
    );
    final accentColor = _resolveColor(
      read('theme_accent_color', ''),
      defaultAccentColor,
    );
    final backgroundColor = _resolveColor(
      read('theme_background_color', ''),
      defaultBackgroundColor,
    );
    final explicitTextColor = _tryResolveColor(read('theme_text_color', ''));
    // Preserve every valid editor value byte-for-byte. Only an absent or
    // malformed text setting receives a contrast-safe fallback derived from
    // the already resolved background, so partial legacy themes cannot become
    // dark-on-dark.
    final textColor =
        explicitTextColor ?? _readableTextFallback(backgroundColor);

    return WebsiteResolvedTheme(
      primaryColor: primaryColor,
      accentColor: accentColor,
      backgroundColor: backgroundColor,
      textColor: textColor,
      headingFont: WebsiteFontRegistry.resolveHeadingFont(
        read('theme_heading_font', ''),
      ),
      bodyFont: WebsiteFontRegistry.resolveBodyFont(
        read('theme_body_font', ''),
      ),
      headingSize: _resolveDouble(
        read('theme_heading_size', ''),
        defaultHeadingSize,
        min: 24,
        max: 72,
      ),
      bodySize: _resolveDouble(
        read('theme_body_size', ''),
        defaultBodySize,
        min: 12,
        max: 24,
      ),
      sectionSpacing: WebsitePageComposition.resolveSectionSpacing(
        read('theme_section_spacing', ''),
      ),
      containerPadding: _resolveDouble(
        read('theme_container_padding', ''),
        defaultContainerPadding,
        min: minContainerPadding,
        max: maxContainerPadding,
      ),
      buttonStyle: _resolveButtonStyle(read('button_style', '')),
      buttonSize: _resolveButtonSize(read('button_size', '')),
      commerceAccentColor: _resolveColor(
        read('theme_product_detail_accent_color', ''),
        defaultCommerceAccentColor,
      ),
      commerceTextColor: _resolveColor(
        read('theme_product_detail_text_color', ''),
        defaultCommerceTextColor,
      ),
      commerceLineColor: _resolveColor(
        read('theme_product_detail_line_color', ''),
        defaultCommerceLineColor,
      ),
    );
  }

  static Color _resolveColor(String raw, Color fallback) {
    return _tryResolveColor(raw) ?? fallback;
  }

  static Color? _tryResolveColor(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;

    var cleaned = value.toLowerCase();
    if (cleaned.startsWith('color(') && cleaned.endsWith(')')) {
      cleaned = cleaned.substring(6, cleaned.length - 1).trim();
      final wrapped = int.tryParse(cleaned);
      return wrapped == null ? null : Color(wrapped);
    }

    if (cleaned.startsWith('0x')) {
      final prefixed = int.tryParse(cleaned);
      return prefixed == null ? null : Color(prefixed);
    }

    final explicitlyHex = cleaned.startsWith('#');
    if (explicitlyHex) cleaned = cleaned.substring(1);
    final isHex = RegExp(r'^[0-9a-f]+$').hasMatch(cleaned);
    // Six/eight-character bare values are the legacy RGB/ARGB form even when
    // they contain digits only. Parse them before decimal so `123456` cannot
    // silently become the integer color 0x0001E240.
    final unambiguousBareHex =
        !explicitlyHex && (cleaned.length == 6 || cleaned.length == 8);
    if (isHex && (explicitlyHex || unambiguousBareHex)) {
      final hex = int.tryParse(cleaned, radix: 16);
      if (hex == null) return null;
      return Color(cleaned.length <= 6 ? 0xFF000000 | hex : hex);
    }

    final decimal = int.tryParse(cleaned);
    if (decimal != null) return Color(decimal);

    if (isHex) {
      final hex = int.tryParse(cleaned, radix: 16);
      if (hex != null) {
        return Color(cleaned.length <= 6 ? 0xFF000000 | hex : hex);
      }
    }
    return null;
  }

  static Color _readableTextFallback(Color background) {
    final defaultContrast = _contrastRatio(defaultTextColor, background);
    final whiteContrast = _contrastRatio(Colors.white, background);
    return defaultContrast >= whiteContrast ? defaultTextColor : Colors.white;
  }

  static double _contrastRatio(Color foreground, Color background) {
    final foregroundLuminance = foreground.computeLuminance();
    final backgroundLuminance = background.computeLuminance();
    final lighter = foregroundLuminance > backgroundLuminance
        ? foregroundLuminance
        : backgroundLuminance;
    final darker = foregroundLuminance > backgroundLuminance
        ? backgroundLuminance
        : foregroundLuminance;
    return (lighter + 0.05) / (darker + 0.05);
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

  static String _resolveButtonStyle(String raw) {
    return switch (raw.trim().toLowerCase()) {
      'sharp' => 'sharp',
      'pill' => 'pill',
      _ => 'rounded',
    };
  }

  static String _resolveButtonSize(String raw) {
    return switch (raw.trim().toLowerCase()) {
      'small' => 'small',
      'large' => 'large',
      _ => 'medium',
    };
  }

  @override
  WebsiteResolvedTheme copyWith({
    Color? primaryColor,
    Color? accentColor,
    Color? backgroundColor,
    Color? textColor,
    String? headingFont,
    String? bodyFont,
    double? headingSize,
    double? bodySize,
    double? sectionSpacing,
    double? containerPadding,
    String? buttonStyle,
    String? buttonSize,
    Color? commerceAccentColor,
    Color? commerceTextColor,
    Color? commerceLineColor,
  }) {
    return WebsiteResolvedTheme(
      primaryColor: primaryColor ?? this.primaryColor,
      accentColor: accentColor ?? this.accentColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textColor: textColor ?? this.textColor,
      headingFont: headingFont ?? this.headingFont,
      bodyFont: bodyFont ?? this.bodyFont,
      headingSize: headingSize ?? this.headingSize,
      bodySize: bodySize ?? this.bodySize,
      sectionSpacing: sectionSpacing ?? this.sectionSpacing,
      containerPadding: containerPadding ?? this.containerPadding,
      buttonStyle: buttonStyle ?? this.buttonStyle,
      buttonSize: buttonSize ?? this.buttonSize,
      commerceAccentColor: commerceAccentColor ?? this.commerceAccentColor,
      commerceTextColor: commerceTextColor ?? this.commerceTextColor,
      commerceLineColor: commerceLineColor ?? this.commerceLineColor,
    );
  }

  @override
  WebsiteResolvedTheme lerp(
    covariant WebsiteResolvedTheme? other,
    double t,
  ) {
    if (other == null) return this;
    return WebsiteResolvedTheme(
      primaryColor:
          Color.lerp(primaryColor, other.primaryColor, t) ?? primaryColor,
      accentColor: Color.lerp(accentColor, other.accentColor, t) ?? accentColor,
      backgroundColor: Color.lerp(backgroundColor, other.backgroundColor, t) ??
          backgroundColor,
      textColor: Color.lerp(textColor, other.textColor, t) ?? textColor,
      headingFont: t < 0.5 ? headingFont : other.headingFont,
      bodyFont: t < 0.5 ? bodyFont : other.bodyFont,
      headingSize: _lerpDouble(headingSize, other.headingSize, t),
      bodySize: _lerpDouble(bodySize, other.bodySize, t),
      sectionSpacing: _lerpDouble(sectionSpacing, other.sectionSpacing, t),
      containerPadding:
          _lerpDouble(containerPadding, other.containerPadding, t),
      buttonStyle: t < 0.5 ? buttonStyle : other.buttonStyle,
      buttonSize: t < 0.5 ? buttonSize : other.buttonSize,
      commerceAccentColor:
          Color.lerp(commerceAccentColor, other.commerceAccentColor, t) ??
              commerceAccentColor,
      commerceTextColor:
          Color.lerp(commerceTextColor, other.commerceTextColor, t) ??
              commerceTextColor,
      commerceLineColor:
          Color.lerp(commerceLineColor, other.commerceLineColor, t) ??
              commerceLineColor,
    );
  }

  static double _lerpDouble(double a, double b, double t) {
    return a + (b - a) * t;
  }
}
