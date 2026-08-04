import 'package:flutter/material.dart';

import 'website_commerce_theme.dart';
import 'website_resolved_theme.dart';

class WebsiteThemeBuilder {
  const WebsiteThemeBuilder._();

  static double _contrastRatio(Color a, Color b) {
    final light = a.computeLuminance() > b.computeLuminance() ? a : b;
    final dark = identical(light, a) ? b : a;
    return (light.computeLuminance() + 0.05) / (dark.computeLuminance() + 0.05);
  }

  static Color _readableForeground(Color background) {
    const ink = Color(0xFF17211B);
    const white = Colors.white;
    return _contrastRatio(white, background) >= _contrastRatio(ink, background)
        ? white
        : ink;
  }

  static Color _surfaceTone(
    Color background,
    Color foreground,
    double strength,
  ) {
    return Color.lerp(background, foreground, strength) ?? background;
  }

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
    required WebsiteResolvedTheme resolved,
  }) {
    final primaryColor = resolved.primaryColor;
    final accentColor = resolved.accentColor;
    final backgroundColor = resolved.backgroundColor;
    final headingFont = resolved.headingFont;
    final bodyFont = resolved.bodyFont;
    final headingSize = resolved.headingSize;
    final bodySize = resolved.bodySize;
    final buttonStyle = resolved.buttonStyle;
    final buttonSize = resolved.buttonSize;
    final baseTextTheme = base.textTheme;
    final onPrimary = _readableForeground(primaryColor);
    final onSecondary = _readableForeground(accentColor);
    // `theme_text_color` is an editor-owned value, not metadata: project the
    // exact resolved color into ThemeData and every text role. Background
    // contrast still determines brightness and component tone direction; it
    // never silently replaces the configured text color.
    final onSurface = resolved.textColor;
    final isDark = _readableForeground(backgroundColor) == Colors.white;
    final brightness = isDark ? Brightness.dark : Brightness.light;
    final surfaceContainerLow = _surfaceTone(backgroundColor, onSurface, 0.035);
    final surfaceContainer = _surfaceTone(backgroundColor, onSurface, 0.065);
    final surfaceContainerHigh =
        _surfaceTone(backgroundColor, onSurface, 0.095);
    final outline = _surfaceTone(backgroundColor, onSurface, 0.30);
    final outlineVariant = _surfaceTone(backgroundColor, onSurface, 0.16);
    final onSurfaceVariant = _surfaceTone(onSurface, backgroundColor, 0.24);
    final commerceAccent = resolved.commerceAccentColor;
    final commerceText = resolved.commerceTextColor;
    final commerceLine = resolved.commerceLineColor;
    final primaryContainer =
        Color.alphaBlend(primaryColor.withValues(alpha: 0.14), backgroundColor);
    final secondaryContainer =
        Color.alphaBlend(accentColor.withValues(alpha: 0.14), backgroundColor);

    final headingTextTheme = _safeGetTextTheme(headingFont, baseTextTheme);
    final bodyTextTheme = _safeGetTextTheme(bodyFont, baseTextTheme);

    // Compose a single TextTheme: headings from heading font, body from body font.
    final composedTextTheme = baseTextTheme
        .copyWith(
          displayLarge:
              _withFontSize(headingTextTheme.displayLarge, headingSize),
          displayMedium: headingTextTheme.displayMedium,
          displaySmall: headingTextTheme.displaySmall,
          headlineLarge: headingTextTheme.headlineLarge,
          headlineMedium: headingTextTheme.headlineMedium,
          headlineSmall: headingTextTheme.headlineSmall,
          titleLarge: headingTextTheme.titleLarge,
          titleMedium: headingTextTheme.titleMedium,
          titleSmall: headingTextTheme.titleSmall,
          bodyLarge: _withFontSize(
            bodyTextTheme.bodyLarge,
            (bodySize + 2).clamp(10, 40).toDouble(),
          ),
          bodyMedium: _withFontSize(bodyTextTheme.bodyMedium, bodySize),
          bodySmall: _withFontSize(
            bodyTextTheme.bodySmall,
            (bodySize - 2).clamp(8, 34).toDouble(),
          ),
          labelLarge: bodyTextTheme.labelLarge,
          labelMedium: bodyTextTheme.labelMedium,
          labelSmall: bodyTextTheme.labelSmall,
        )
        .apply(
          bodyColor: onSurface,
          displayColor: onSurface,
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

    final colorScheme = base.colorScheme.copyWith(
      brightness: brightness,
      primary: primaryColor,
      onPrimary: onPrimary,
      primaryContainer: primaryContainer,
      onPrimaryContainer: _readableForeground(primaryContainer),
      secondary: accentColor,
      onSecondary: onSecondary,
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: _readableForeground(secondaryContainer),
      surface: backgroundColor,
      onSurface: onSurface,
      onSurfaceVariant: onSurfaceVariant,
      surfaceTint: primaryColor,
      surfaceContainerLowest: backgroundColor,
      surfaceContainerLow: surfaceContainerLow,
      surfaceContainer: surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh,
      surfaceContainerHighest: _surfaceTone(backgroundColor, onSurface, 0.13),
      outline: outline,
      outlineVariant: outlineVariant,
      inverseSurface: onSurface,
      onInverseSurface: backgroundColor,
      shadow: Colors.black,
      scrim: Colors.black,
    );

    OutlineInputBorder inputBorder(Color color, {double width = 1}) {
      final baseBorder = base.inputDecorationTheme.enabledBorder;
      final radius = baseBorder is OutlineInputBorder
          ? baseBorder.borderRadius
          : BorderRadius.circular(8);
      return OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return base.copyWith(
      brightness: brightness,
      textTheme: composedTextTheme,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: backgroundColor,
      colorScheme: colorScheme,
      extensions: [
        ...base.extensions.values.where((extension) =>
            extension is! WebsiteCommerceTheme &&
            extension is! WebsiteResolvedTheme),
        resolved,
        WebsiteCommerceTheme(
          accent: commerceAccent,
          onAccent: _readableForeground(commerceAccent),
          textPrimary: commerceText,
          line: commerceLine,
        ),
      ],
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: backgroundColor,
        foregroundColor: onSurface,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: onSurface),
        actionsIconTheme: IconThemeData(color: onSurface),
        titleTextStyle: composedTextTheme.titleLarge?.copyWith(
          color: onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: base.cardTheme.copyWith(
        color: surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.14),
      ),
      dividerTheme: base.dividerTheme.copyWith(
        color: outlineVariant,
      ),
      iconTheme: base.iconTheme.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surfaceContainerLow,
        disabledColor: surfaceContainerHigh,
        selectedColor: primaryColor.withValues(alpha: isDark ? 0.28 : 0.14),
        secondarySelectedColor:
            accentColor.withValues(alpha: isDark ? 0.28 : 0.14),
        deleteIconColor: colorScheme.onSurfaceVariant,
        side: BorderSide(color: outlineVariant),
        labelStyle: composedTextTheme.labelMedium?.copyWith(
          color: onSurface,
        ),
        secondaryLabelStyle: composedTextTheme.labelMedium?.copyWith(
          color: onSurface,
        ),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: surfaceContainerLow,
        labelStyle: composedTextTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        hintStyle: composedTextTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        border: inputBorder(outlineVariant),
        enabledBorder: inputBorder(outlineVariant),
        focusedBorder: inputBorder(primaryColor, width: 2),
        errorBorder: inputBorder(colorScheme.error),
        focusedErrorBorder: inputBorder(colorScheme.error, width: 2),
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
