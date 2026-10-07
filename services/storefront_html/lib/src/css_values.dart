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

/// A block family's padding, each side the operator set in its place
/// (`--sp-t`, `--sp-r`, `--sp-b`, `--sp-l` from `BlockSurface`).
String surfacePadding(double top, double right, double bottom, double left) =>
    'padding:var(--sp-t,${cssPx(top)}) var(--sp-r,${cssPx(right)}) '
    'var(--sp-b,${cssPx(bottom)}) var(--sp-l,${cssPx(left)})';

/// A family's side padding by the block's width, a side the operator set
/// in its place.
String surfacePaddingInline(double side) =>
    'padding-right:var(--sp-r,${cssPx(side)});'
    'padding-left:var(--sp-l,${cssPx(side)})';

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

/// One Flutter text style, as CSS: its line is the size times the style's
/// height, rounded (SkParagraph); a heading font that ships only its regular
/// file draws 600 and up as that outline emboldened by Skia. SkParagraph puts
/// half of the letter spacing before each glyph (shift a text right by half).
class FlutterTextCss {
  const FlutterTextCss(
    this.family,
    this.size,
    this.height,
    this.weight,
    this.spacing, {
    required this.heading,
  });

  final String family;
  final double size;
  final double height;
  final int weight;
  final double spacing;

  /// The heading font ships only its regular file.
  final bool heading;

  int get line => (size * height).round();

  /// Skia's fake-bold stroke width for [size].
  double get _embolden {
    final ratio = size <= 9
        ? 1 / 24
        : size >= 36
        ? 1 / 32
        : 1 / 24 + (size - 9) / 27 * (1 / 32 - 1 / 24);
    return double.parse((size * ratio).toStringAsFixed(3));
  }

  String get font {
    final drawnWeight = heading ? 400 : weight;
    final stroke = heading && weight >= 600
        ? ';-webkit-text-stroke:${cssPx(_embolden)} currentColor'
        : ';-webkit-text-stroke:0';
    return 'font:$drawnWeight ${cssPx(size)}/${line}px '
        'var(--${heading ? 'head' : 'body'});'
        'letter-spacing:${cssPx(spacing)}$stroke';
  }
}
