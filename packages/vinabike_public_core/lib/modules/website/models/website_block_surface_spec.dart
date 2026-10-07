import '../theme/website_theme_roles.dart' show WebsiteRgba;
import 'website_block_type.dart';
import 'website_responsive_authoring.dart';

/// A side of a block's padding.
enum WebsiteSurfaceSide {
  top('Top'),
  right('Right'),
  bottom('Bottom'),
  left('Left');

  const WebsiteSurfaceSide(this.suffix);

  /// `Top` of `paddingTop` (the stored map) and `surfacePaddingTop` (a
  /// viewport's override).
  final String suffix;
}

/// Four sides of a block's padding, in logical pixels.
class WebsiteSurfaceInsets {
  const WebsiteSurfaceInsets({
    required this.top,
    required this.right,
    required this.bottom,
    required this.left,
  });

  const WebsiteSurfaceInsets.symmetric({
    double vertical = 0,
    double horizontal = 0,
  }) : top = vertical,
       bottom = vertical,
       right = horizontal,
       left = horizontal;

  static const zero = WebsiteSurfaceInsets(
    top: 0,
    right: 0,
    bottom: 0,
    left: 0,
  );

  final double top;
  final double right;
  final double bottom;
  final double left;

  List<double> get sides => [top, right, bottom, left];

  @override
  bool operator ==(Object other) =>
      other is WebsiteSurfaceInsets &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom &&
      other.left == left;

  @override
  int get hashCode => Object.hash(top, right, bottom, left);

  @override
  String toString() => 'WebsiteSurfaceInsets($top, $right, $bottom, $left)';
}

/// The content padding each block family had before the surface owner
/// existed, and still uses for a side the operator did not set
/// (`WebsiteBlockSurfaceDefaults` in the app draws with these).
WebsiteSurfaceInsets websiteBlockSurfaceDefaultPadding({
  required WebsiteBlockType blockType,
  required WebsiteViewport viewport,
  required Map<String, dynamic> data,
}) {
  final standardHorizontal = viewport == WebsiteViewport.mobile ? 16.0 : 24.0;
  return switch (blockType) {
    WebsiteBlockType.hero => const WebsiteSurfaceInsets.symmetric(
      horizontal: 24,
    ),
    WebsiteBlockType.carousel ||
    WebsiteBlockType.canvas ||
    WebsiteBlockType.text ||
    WebsiteBlockType.button ||
    WebsiteBlockType.divider ||
    WebsiteBlockType.footer => WebsiteSurfaceInsets.zero,
    WebsiteBlockType.products => WebsiteSurfaceInsets.symmetric(
      vertical: 48,
      horizontal: standardHorizontal,
    ),
    WebsiteBlockType.services => WebsiteSurfaceInsets.symmetric(
      vertical: 56,
      horizontal: standardHorizontal,
    ),
    WebsiteBlockType.about ||
    WebsiteBlockType.testimonials ||
    WebsiteBlockType.features ||
    WebsiteBlockType.gallery ||
    WebsiteBlockType.contact ||
    WebsiteBlockType.faq ||
    WebsiteBlockType.pricing ||
    WebsiteBlockType.team ||
    WebsiteBlockType.stats => WebsiteSurfaceInsets.symmetric(
      vertical: 64,
      horizontal: standardHorizontal,
    ),
    WebsiteBlockType.cta => WebsiteSurfaceInsets.symmetric(
      vertical: _positiveFinite(data['blockHeight']) == null ? 56 : 0,
      horizontal: standardHorizontal,
    ),
    WebsiteBlockType.categoryGrid => const WebsiteSurfaceInsets.symmetric(
      vertical: 48,
    ),
    WebsiteBlockType.videoBanner => const WebsiteSurfaceInsets(
      top: 24,
      right: 24,
      bottom: 24,
      left: 24,
    ),
    WebsiteBlockType.partnersBanner => WebsiteSurfaceInsets.symmetric(
      vertical: 64,
      horizontal: standardHorizontal,
    ),
    WebsiteBlockType.brandLogos => const WebsiteSurfaceInsets.symmetric(
      vertical: 48,
      horizontal: 16,
    ),
    WebsiteBlockType.googleReviews => const WebsiteSurfaceInsets.symmetric(
      vertical: 64,
      horizontal: 24,
    ),
  };
}

/// A color of a block's surface as the editor writes it: `#RRGGBB`,
/// `#AARRGGBB` (alpha first, as Flutter's `Color`) or `rgb(…)`/`rgba(…)`;
/// `null` for anything else.
WebsiteRgba? websiteSurfaceColor(Object? raw) {
  if (raw == null) return null;
  final value = raw.toString().trim();
  if (value.isEmpty) return null;
  final rgba = RegExp(
    r'^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*([\d.]+))?\s*\)$',
  ).firstMatch(value);
  if (rgba != null) {
    final red = int.tryParse(rgba.group(1)!);
    final green = int.tryParse(rgba.group(2)!);
    final blue = int.tryParse(rgba.group(3)!);
    final alpha = double.tryParse(rgba.group(4) ?? '1');
    if (red == null || green == null || blue == null || alpha == null) {
      return null;
    }
    return WebsiteRgba(
      alpha.clamp(0, 1).toDouble(),
      red.clamp(0, 255) / 255,
      green.clamp(0, 255) / 255,
      blue.clamp(0, 255) / 255,
    );
  }
  var hex = value.replaceFirst('#', '');
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  final parsed = int.tryParse(hex, radix: 16);
  return parsed == null ? null : WebsiteRgba.fromArgb(parsed);
}

/// A block's authored surface, read for one viewport: its background
/// (solid, gradient or none), its frame (border, corners, shadow) and its
/// padding.
///
/// The one decoder of the stored values (2026-10-07): the app's
/// `WebsiteBlockSurfaceStyle` paints Flutter with it and the HTML storefront
/// writes CSS with it. Shared values live in the block's `style` map, or in
/// `surfaceStyle` when `style` is a button's scalar variant; padding is the
/// only responsive family, its phone and tablet overrides under
/// `responsive.<viewport>.surfacePadding…`.
class WebsiteBlockSurfaceSpec {
  const WebsiteBlockSurfaceSpec._({
    required this.viewport,
    required this.baseMapKey,
    required this.base,
    required this.paddingTop,
    required this.paddingRight,
    required this.paddingBottom,
    required this.paddingLeft,
  });

  factory WebsiteBlockSurfaceSpec.resolve({
    required Map<String, dynamic> data,
    required WebsiteViewport viewport,
  }) {
    final base = baseMap(data);

    WebsiteResolvedResponsiveValue<double> padding(WebsiteSurfaceSide side) {
      final key = 'surfacePadding${side.suffix}';
      final legacyKey = 'padding${side.suffix}';
      final source = Map<String, dynamic>.from(data);
      if (base.containsKey(legacyKey)) {
        // A read source only: the shared value stays in the stored map.
        source[key] = base[legacyKey];
      } else {
        source.remove(key);
      }
      return WebsiteResponsiveDataCodec.resolve<double>(
        data: source,
        propertyKey: key,
        viewport: viewport,
        decode: _decodeDouble,
      );
    }

    return WebsiteBlockSurfaceSpec._(
      viewport: viewport,
      baseMapKey: baseMapKeyOf(data),
      base: Map<String, dynamic>.unmodifiable(base),
      paddingTop: padding(WebsiteSurfaceSide.top),
      paddingRight: padding(WebsiteSurfaceSide.right),
      paddingBottom: padding(WebsiteSurfaceSide.bottom),
      paddingLeft: padding(WebsiteSurfaceSide.left),
    );
  }

  static const legacyMapKey = 'style';
  static const scalarSafeMapKey = 'surfaceStyle';

  /// Where [data] keeps its shared surface values.
  static String baseMapKeyOf(Map<String, dynamic> data) =>
      data[legacyMapKey] is Map ? legacyMapKey : scalarSafeMapKey;

  /// A copy of [data]'s shared surface values.
  static Map<String, dynamic> baseMap(Map<String, dynamic> data) {
    final raw = data[baseMapKeyOf(data)];
    if (raw is! Map) return <String, dynamic>{};
    return raw.map((key, value) => MapEntry(key.toString(), _deepCopy(value)));
  }

  final WebsiteViewport viewport;
  final String baseMapKey;
  final Map<String, dynamic> base;
  final WebsiteResolvedResponsiveValue<double> paddingTop;
  final WebsiteResolvedResponsiveValue<double> paddingRight;
  final WebsiteResolvedResponsiveValue<double> paddingBottom;
  final WebsiteResolvedResponsiveValue<double> paddingLeft;

  /// [side] as resolved for this viewport.
  WebsiteResolvedResponsiveValue<double> padding(WebsiteSurfaceSide side) =>
      switch (side) {
        WebsiteSurfaceSide.top => paddingTop,
        WebsiteSurfaceSide.right => paddingRight,
        WebsiteSurfaceSide.bottom => paddingBottom,
        WebsiteSurfaceSide.left => paddingLeft,
      };

  bool get hasAuthoredPadding =>
      WebsiteSurfaceSide.values.any(isPaddingAuthored);

  /// Whether [side] has a stored base or an override for this viewport: a
  /// family with spacing of its own gives up only that side.
  bool isPaddingAuthored(WebsiteSurfaceSide side) {
    final resolved = padding(side);
    if (resolved.isOverride) return resolved.value != null;
    return base.containsKey('padding${side.suffix}') && resolved.shared != null;
  }

  /// Each side as set, or [fallback]'s.
  WebsiteSurfaceInsets paddingWithFallback(WebsiteSurfaceInsets fallback) =>
      WebsiteSurfaceInsets(
        top: paddingTop.value ?? fallback.top,
        right: paddingRight.value ?? fallback.right,
        bottom: paddingBottom.value ?? fallback.bottom,
        left: paddingLeft.value ?? fallback.left,
      );

  /// `solid`, `gradient` or `transparent`.
  String get backgroundType =>
      switch (_string('backgroundType')?.toLowerCase()) {
        'gradient' => 'gradient',
        'transparent' => 'transparent',
        _ => 'solid',
      };

  WebsiteRgba? get backgroundColor =>
      websiteSurfaceColor(base['backgroundColor']);
  WebsiteRgba? get gradientColor1 =>
      websiteSurfaceColor(base['gradientColor1']);
  WebsiteRgba? get gradientColor2 =>
      websiteSurfaceColor(base['gradientColor2']);

  /// `to-bottom` unless set (`to-top`, `to-right`, `to-bottom-right`…).
  String get gradientDirection => _string('gradientDirection') ?? 'to-bottom';

  double get borderWidth =>
      (_number('borderWidth') ?? 0).clamp(0, 20).toDouble();
  WebsiteRgba? get borderColor => websiteSurfaceColor(base['borderColor']);
  double get borderRadius =>
      (_number('borderRadius') ?? 0).clamp(0, 50).toDouble();

  /// `none` or `solid`: a dashed or dotted border written by an older client
  /// draws solid rather than disappearing.
  String get borderStyle =>
      _string('borderStyle')?.toLowerCase() == 'none' ? 'none' : 'solid';

  bool get paintsBorder => borderWidth > 0 && borderStyle == 'solid';

  bool get shadowEnabled => base['shadowEnabled'] == true;
  double get shadowOffsetX => _number('shadowOffsetX') ?? 0;
  double get shadowOffsetY => _number('shadowOffsetY') ?? 4;
  double get shadowBlur =>
      (_number('shadowBlur') ?? 12).clamp(0, 50).toDouble();
  double get shadowSpread =>
      (_number('shadowSpread') ?? 0).clamp(-20, 20).toDouble();
  WebsiteRgba get shadowColor =>
      websiteSurfaceColor(base['shadowColor']) ??
      const WebsiteRgba(0.13, 12 / 255, 37 / 255, 55 / 255);

  bool get hasAuthoredBackground => const [
    'backgroundType',
    'backgroundColor',
    'gradientColor1',
    'gradientColor2',
    'gradientDirection',
  ].any(base.containsKey);

  bool get hasAuthoredFrame =>
      borderWidth > 0 || borderRadius > 0 || shadowEnabled;

  bool get hasAuthoredDecoration => hasAuthoredBackground || hasAuthoredFrame;

  /// Whether the block paints a background of its own: a solid color, or a
  /// gradient (its colors default to white and grey 100).
  bool get paintsGradient =>
      backgroundType == 'gradient' && hasAuthoredBackground;

  /// The color the block's background puts behind its words, for the ink
  /// they take: the solid color, the middle of the gradient; `null` when it
  /// paints none (transparent, or solid with no color chosen) and the page
  /// shows through.
  WebsiteRgba? get paintedColor {
    if (!hasAuthoredBackground) return null;
    if (paintsGradient) {
      return WebsiteRgba.lerp(
        gradientColor1 ?? WebsiteRgba.white,
        gradientColor2 ?? WebsiteRgba.fromArgb(0xFFF5F5F5),
        0.5,
      );
    }
    if (backgroundType == 'transparent') return null;
    final color = backgroundColor;
    return color == null || color.a == 0 ? null : color;
  }

  String? _string(String key) {
    final raw = base[key];
    if (raw == null) return null;
    final value = raw.toString().trim();
    return value.isEmpty ? null : value;
  }

  double? _number(String key) => _decodeDouble(base[key]);
}

double? _positiveFinite(Object? raw) {
  final value = _decodeDouble(raw);
  return value != null && value > 0 ? value : null;
}

double? _decodeDouble(Object? raw) {
  if (raw is num) {
    final value = raw.toDouble();
    return value.isFinite ? value : null;
  }
  if (raw is String) {
    final value = double.tryParse(raw.trim());
    return value?.isFinite == true ? value : null;
  }
  return null;
}

Object? _deepCopy(Object? value) {
  if (value is Map) {
    return value.map(
      (key, nested) => MapEntry(key.toString(), _deepCopy(nested)),
    );
  }
  if (value is List) return value.map(_deepCopy).toList(growable: false);
  if (value is Set) return value.map(_deepCopy).toSet();
  return value;
}
