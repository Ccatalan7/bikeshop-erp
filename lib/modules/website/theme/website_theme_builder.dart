import 'package:flutter/material.dart';

class WebsiteThemeBuilder {
  const WebsiteThemeBuilder._();

  /// Apply font family via CSS font-family instead of GoogleFonts package
  /// (GoogleFonts adds ~6.5MB to bundle with all font metadata)
  static TextTheme _safeGetTextTheme(String? fontFamily, TextTheme base) {
    final family = fontFamily?.trim();
    if (family == null || family.isEmpty) return base;
    // Apply font family directly - browser loads via CSS @font-face or system fonts
    return base.apply(fontFamily: family);
  }

  static TextStyle? _withFontSize(TextStyle? style, double? fontSize) {
    if (style == null || fontSize == null) return style;
    return style.copyWith(fontSize: fontSize);
  }

  static ThemeData build({
    required ThemeData base,
    required Color primaryColor,
    required Color accentColor,
    required Color backgroundColor,
    String? headingFont,
    String? bodyFont,
    double? headingSize,
    double? bodySize,
  }) {
    final baseTextTheme = base.textTheme;

    // If only one is set, use it for everything.
    final effectiveBodyFont = (bodyFont?.trim().isNotEmpty == true)
        ? bodyFont!.trim()
        : (headingFont?.trim().isNotEmpty == true)
            ? headingFont!.trim()
            : null;
    final effectiveHeadingFont = (headingFont?.trim().isNotEmpty == true)
        ? headingFont!.trim()
        : effectiveBodyFont;

    final headingTextTheme =
        _safeGetTextTheme(effectiveHeadingFont, baseTextTheme);
    final bodyTextTheme = _safeGetTextTheme(effectiveBodyFont, baseTextTheme);

    // Compose a single TextTheme: headings from heading font, body from body font.
    final composedTextTheme = baseTextTheme.copyWith(
      displayLarge: _withFontSize(headingTextTheme.displayLarge, headingSize),
      displayMedium: headingTextTheme.displayMedium,
      displaySmall: headingTextTheme.displaySmall,
      headlineLarge: headingTextTheme.headlineLarge,
      headlineMedium: headingTextTheme.headlineMedium,
      headlineSmall: headingTextTheme.headlineSmall,
      titleLarge: headingTextTheme.titleLarge,
      titleMedium: headingTextTheme.titleMedium,
      titleSmall: headingTextTheme.titleSmall,
      bodyLarge: _withFontSize(bodyTextTheme.bodyLarge,
          bodySize != null ? (bodySize + 2).clamp(10, 40).toDouble() : null),
      bodyMedium: _withFontSize(bodyTextTheme.bodyMedium, bodySize),
      bodySmall: _withFontSize(bodyTextTheme.bodySmall,
          bodySize != null ? (bodySize - 2).clamp(8, 34).toDouble() : null),
      labelLarge: bodyTextTheme.labelLarge,
      labelMedium: bodyTextTheme.labelMedium,
      labelSmall: bodyTextTheme.labelSmall,
    );

    return base.copyWith(
      textTheme: composedTextTheme,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: backgroundColor,
      colorScheme: base.colorScheme.copyWith(
        primary: primaryColor,
        secondary: accentColor,
        surface: backgroundColor,
      ),
    );
  }
}
