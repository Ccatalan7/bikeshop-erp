import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';

/// A number from block data, or `null` when it is missing or not finite.
double? numberValue(Object? raw) {
  final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
  return value != null && value.isFinite ? value : null;
}

/// A CSS number: whole numbers without decimals, others with at most four.
String cssNum(double value) => value == value.roundToDouble()
    ? '${value.round()}'
    : value
          .toStringAsFixed(4)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');

String cssPx(double value) => '${cssNum(value)}px';

/// A Flutter text line: the font size times the height, rounded to a whole
/// pixel (SkParagraph's rounding).
String lineHeightPx(double fontSize, double height) =>
    '${(fontSize * height).round()}px';

/// An editor color written as `#RRGGBB` or `#AARRGGBB` (alpha first, as
/// Flutter's `Color`), or [fallback] when it cannot be read.
WebsiteRgba hexColor(Object? raw, WebsiteRgba fallback) {
  var hex = raw?.toString().trim() ?? '';
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return fallback;
  final value = int.tryParse(hex, radix: 16);
  return value == null ? fallback : WebsiteRgba.fromArgb(value);
}

/// Flutter draws a heading font's bold as its regular outline emboldened
/// (only the regular file ships): weight 400 and a stroke, from 600 up.
String headingWeightCss(int weight) =>
    weight >= 600 ? '-webkit-text-stroke:.032em currentColor' : '';
