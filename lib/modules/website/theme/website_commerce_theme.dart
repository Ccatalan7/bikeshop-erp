import 'package:flutter/material.dart';

/// Editor-owned visual tokens for product-detail commerce surfaces.
///
/// These values are projected into the public [ThemeData] so Product Detail,
/// Preview and Edit consume the same saved palette without hardcoded renderer
/// colors.
@immutable
class WebsiteCommerceTheme extends ThemeExtension<WebsiteCommerceTheme> {
  const WebsiteCommerceTheme({
    required this.accent,
    required this.onAccent,
    required this.textPrimary,
    required this.line,
  });

  final Color accent;
  final Color onAccent;
  final Color textPrimary;
  final Color line;

  @override
  WebsiteCommerceTheme copyWith({
    Color? accent,
    Color? onAccent,
    Color? textPrimary,
    Color? line,
  }) {
    return WebsiteCommerceTheme(
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      textPrimary: textPrimary ?? this.textPrimary,
      line: line ?? this.line,
    );
  }

  @override
  WebsiteCommerceTheme lerp(
    covariant WebsiteCommerceTheme? other,
    double t,
  ) {
    if (other == null) return this;
    return WebsiteCommerceTheme(
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      onAccent: Color.lerp(onAccent, other.onAccent, t) ?? onAccent,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      line: Color.lerp(line, other.line, t) ?? line,
    );
  }
}
