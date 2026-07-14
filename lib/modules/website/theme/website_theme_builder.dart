import 'package:flutter/material.dart';

import '../models/website_font_registry.dart';

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
    String buttonStyle = 'rounded',
    String buttonSize = 'medium',
  }) {
    final baseTextTheme = base.textTheme;

    final effectiveHeadingFont =
        WebsiteFontRegistry.resolveHeadingFont(headingFont);
    final effectiveBodyFont = WebsiteFontRegistry.resolveBodyFont(bodyFont);

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

    final buttonRadius = switch (buttonStyle.trim().toLowerCase()) {
      'sharp' => 0.0,
      'pill' => 999.0,
      _ => 8.0,
    };
    final (buttonPadding, buttonMinimumSize) =
        switch (buttonSize.trim().toLowerCase()) {
      'small' => (
          const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          const Size(56, 36),
        ),
      'large' => (
          const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          const Size(80, 52),
        ),
      _ => (
          const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          const Size(64, 44),
        ),
    };
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(buttonRadius),
    );
    final buttonTextStyle = composedTextTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w600,
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
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: buttonPadding,
          minimumSize: buttonMinimumSize,
          shape: buttonShape,
          textStyle: buttonTextStyle,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: buttonPadding,
          minimumSize: buttonMinimumSize,
          shape: buttonShape,
          textStyle: buttonTextStyle,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: buttonPadding,
          minimumSize: buttonMinimumSize,
          shape: buttonShape,
          textStyle: buttonTextStyle,
        ),
      ),
    );
  }
}
