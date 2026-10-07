import 'package:vinabike_public_core/modules/website/models/website_block_surface_spec.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_type.dart';
import 'package:vinabike_public_core/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';

import 'css_values.dart';

/// A block's authored surface as the HTML storefront draws it, the way
/// `WebsiteBlockSurface` and each family draw it in Flutter
/// (`WebsiteBlockRenderer`):
///
/// - the decoration (background, border, corners, shadow) is painted once,
///   by a wrapper around the family (`.srf`), and a family that paints a
///   background of its own leaves it to the block's (`.own-bg`);
/// - the padding is the family's: a side the operator set replaces the
///   family's own through `--sp-t`, `--sp-r`, `--sp-b` and `--sp-l`, which
///   each family's stylesheet reads with its design as the fallback. A
///   section band takes all four sides once one is set (the others are the
///   surface's defaults, not the band's design), as `WebsiteSectionBand`.
///
/// Canvas and footer have no surface (`paintDecoration: false`).
class BlockSurface {
  BlockSurface(this.type, Map<String, dynamic> data, WebsiteViewport viewport)
    : _data = data,
      spec = WebsiteBlockSurfaceSpec.resolve(data: data, viewport: viewport);

  final WebsiteBlockType? type;
  final WebsiteBlockSurfaceSpec spec;
  final Map<String, dynamic> _data;

  bool get _ignored =>
      type == null ||
      type == WebsiteBlockType.canvas ||
      type == WebsiteBlockType.footer;

  /// The families padded around their content (`_applySurfacePadding`):
  /// the wrapper takes the sides the operator set.
  bool get _padsWrapper => const {
    WebsiteBlockType.carousel,
    WebsiteBlockType.text,
    WebsiteBlockType.button,
    WebsiteBlockType.divider,
  }.contains(type);

  /// The section bands (`WebsiteSectionBand.padding`): all four sides once
  /// one is set.
  bool get _padsWholeBand => const {
    WebsiteBlockType.services,
    WebsiteBlockType.testimonials,
    WebsiteBlockType.pricing,
    WebsiteBlockType.gallery,
    WebsiteBlockType.faq,
    WebsiteBlockType.stats,
    WebsiteBlockType.team,
    WebsiteBlockType.partnersBanner,
  }.contains(type);

  /// Whether the HTML draws this surface as Flutter does. Not yet: padding
  /// set on a category grid or a brand strip (each moves its header or its
  /// row by the sides set), nor on a call to action of a fixed height (its
  /// unset sides take the band's whole design there).
  bool get isDrawn {
    if (_ignored || !spec.hasAuthoredPadding) return true;
    return switch (type) {
      WebsiteBlockType.categoryGrid || WebsiteBlockType.brandLogos => false,
      WebsiteBlockType.cta => _positive(_data['blockHeight']) == null,
      _ => true,
    };
  }

  /// Whether the block gets the wrapper: a decoration, or a padding the
  /// wrapper takes.
  bool get wraps =>
      !_ignored &&
      (spec.hasAuthoredDecoration || (_padsWrapper && spec.hasAuthoredPadding));

  /// Whether the family leaves its own background to the block's.
  bool get ownsBackground => !_ignored && spec.hasAuthoredBackground;

  /// The wrapper's style: its decoration and, for a family padded around
  /// its content, its padding.
  String get wrapperStyle {
    final parts = <String>[];
    if (spec.hasAuthoredBackground) {
      if (spec.paintsGradient) {
        final from = spec.gradientColor1 ?? WebsiteRgba.white;
        final to = spec.gradientColor2 ?? WebsiteRgba.fromArgb(0xFFF5F5F5);
        parts.add(
          'background:linear-gradient(${_direction(spec.gradientDirection)},'
          '${from.css},${to.css})',
        );
      } else if (spec.backgroundType == 'solid') {
        if (spec.backgroundColor case final color?) {
          parts.add('background:${color.css}');
        }
      }
    }
    if (spec.paintsBorder) {
      final color = spec.borderColor ?? WebsiteRgba.fromArgb(0xFF9E9E9E);
      parts.add('border:${cssPx(spec.borderWidth)} solid ${color.css}');
    }
    if (spec.borderRadius > 0) {
      parts.add('border-radius:${cssPx(spec.borderRadius)}');
      // The family is clipped to the corners, except a video banner's.
      if (type != WebsiteBlockType.videoBanner) parts.add('overflow:hidden');
    }
    if (spec.shadowEnabled) {
      // Flutter blurs with sigma = radius × 0.57735 + 0.5; CSS with half
      // the blur it is given.
      final blur = spec.shadowBlur > 0 ? spec.shadowBlur * 1.1547 + 1 : 0.0;
      parts.add(
        'box-shadow:${cssPx(spec.shadowOffsetX)} ${cssPx(spec.shadowOffsetY)} '
        '${_px2(blur)} ${cssPx(spec.shadowSpread)} ${spec.shadowColor.css}',
      );
    }
    if (_padsWrapper) {
      for (final side in WebsiteSurfaceSide.values) {
        if (!spec.isPaddingAuthored(side)) continue;
        parts.add(
          'padding-${side.name}:${cssPx(spec.padding(side).value ?? 0)}',
        );
      }
    }
    return parts.join(';');
  }

  /// The `--sp-*` sides for the family's stylesheet: those the operator set,
  /// or all four for a section band once one is set.
  List<String> get paddingVars {
    if (_ignored || _padsWrapper || !spec.hasAuthoredPadding) return const [];
    final type = this.type!;
    final whole = _padsWholeBand
        ? spec.paddingWithFallback(
            websiteBlockSurfaceDefaultPadding(
              blockType: type,
              viewport: spec.viewport,
              data: _data,
            ),
          )
        : null;
    return [
      for (final side in WebsiteSurfaceSide.values)
        if (whole != null || spec.isPaddingAuthored(side))
          '--sp-${side.name[0]}:${cssPx(whole?.sides[side.index] ?? spec.padding(side).value ?? 0)}',
    ];
  }

  /// What the surface changes in a block's drawing at this viewport, for
  /// telling its versions apart: a phone's padding is not a desktop's.
  Object? get versionKey => _ignored || !spec.hasAuthoredPadding
      ? null
      : paddingVars.isEmpty
      ? wrapperStyle
      : paddingVars;

  static String _direction(String direction) => switch (direction) {
    'to-top' => 'to top',
    'to-top-right' => 'to top right',
    'to-right' => 'to right',
    'to-bottom-right' => 'to bottom right',
    'to-bottom-left' => 'to bottom left',
    'to-left' => 'to left',
    'to-top-left' => 'to top left',
    _ => 'to bottom',
  };

  static String _px2(double value) =>
      cssPx(double.parse(value.toStringAsFixed(2)));

  static double? _positive(Object? raw) {
    final value = switch (raw) {
      final num number => number.toDouble(),
      final String text => double.tryParse(text.trim()),
      _ => null,
    };
    return value != null && value.isFinite && value > 0 ? value : null;
  }
}

/// The wrapper and the families' backgrounds under a block's own.
const blockSurfaceCss = '''
.srf{box-sizing:border-box;width:100%;height:100%}
.blk.minh>.srf{display:flex;flex-direction:column}.blk.minh>.srf>*{flex:1 0 auto}
.own-bg .sec,.own-bg .pb,.own-bg .rv,.own-bg .prod-blk,.own-bg .cat-blk,.own-bg .brands,.own-bg .vb,.own-bg .hero-blk{background:transparent}
.own-bg .hero-fallback{display:none}
.own-bg .car-slide.dflt{background:transparent!important}
''';
