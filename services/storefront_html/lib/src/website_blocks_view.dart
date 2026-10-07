import 'dart:convert';

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/models/website_action.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_base_definitions.dart';
import 'package:vinabike_public_core/modules/website/models/website_image_fields.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_type.dart';
import 'package:vinabike_public_core/modules/website/models/website_hero_content.dart';
import 'package:vinabike_public_core/modules/website/models/website_destination.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_color_value.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';
import 'package:vinabike_public_core/public_store/models/public_image_thumbnail.dart';
import 'package:vinabike_public_core/public_store/models/public_policy_content.dart';
import 'package:vinabike_public_core/shared/models/product.dart';

import 'block_composition.dart';
import 'block_surface.dart';
import 'material_icons.dart';
import 'storefront_fonts.dart';
import 'storefront_shell.dart';
import 'website_brand_logos_view.dart';
import 'website_canvas_view.dart';
import 'website_carousel_view.dart';
import 'website_category_grid_view.dart';
import 'website_content_blocks_view.dart';
import 'website_products_view.dart';
import 'website_section_blocks_view.dart';
import 'website_reviews_view.dart';
import 'website_video_banner_view.dart';

/// Draws the editor's blocks as Flutter's `WebsiteBlockRenderer` does, for
/// the block types the HTML storefront already covers. A block it does not
/// cover yet is left out and named in [BlockRenderContext.uncovered].
class BlockRenderContext {
  BlockRenderContext({
    required this.shell,
    required this.theme,
    required this.storeUrl,
    this.products = const {},
    this.thumbnails = const {},
    this.draft = false,
  });

  final StorefrontShell shell;
  final WebsiteThemeRoles theme;
  final String storeUrl;

  /// The public, in-stock products the page's blocks pick, by id.
  final Map<String, Product> products;

  /// Smaller copies of product photos, by the photo's URL.
  final Map<String, PublicImageThumbnail> thumbnails;
  final uncovered = <String>{};

  /// The editor's draft ([PageContext.draft]): its texts say which field
  /// they draw ([editText]).
  final bool draft;

  /// For the editor's draft, which field of the block an element draws, so
  /// the operator edits it where it is, as the Flutter canvas's
  /// `WebsiteInlineTextSlot`: the field's [keys] (its own and its aliases)
  /// and, for an item of a list (a slide, a question), the list's
  /// [collection] keys and the item's [index] —
  /// `title`, `subtitle,description`, `question@items#2`. Nothing for a
  /// visitor.
  Map<String, String> editText(
    List<String> keys, {
    List<String> collection = const [],
    int index = 0,
  }) {
    if (!draft) return const {};
    final field = keys.join(',');
    return {
      'data-edit-text': collection.isEmpty
          ? field
          : '$field@${collection.join(',')}#$index',
    };
  }

  /// For the editor's draft, which of the block's buttons an element draws
  /// ([WebsiteButtonFields.spec]: `cta`, `plan#2` for the plan stored at
  /// [index]), so the operator edits its label, destination and look where
  /// it is, as the Flutter canvas's `WebsiteInlineActionSlot`. Nothing for a
  /// visitor.
  Map<String, String> editButton(WebsiteButtonFields fields, {int index = 0}) {
    if (!draft) return const {};
    return {'data-edit-button': fields.spec(index)};
  }

  /// For the editor's draft, which of the block's photos an element draws
  /// ([WebsiteImageFields.spec]: `about`, `gallery#2` for the photo stored
  /// at [index]), so the operator replaces it where it is, as the Flutter
  /// canvas's `WebsiteInlineMediaSlot`. Nothing for a visitor.
  Map<String, String> editImage(WebsiteImageFields fields, {int index = 0}) {
    if (!draft) return const {};
    return {'data-edit-image': fields.spec(index)};
  }

  /// For the editor's draft, which canvas layer an element draws (its
  /// `id`), so a click picks that layer in the panel as on the Flutter
  /// canvas. Nothing for a visitor, or for a layer without an id.
  Map<String, String> editLayer(Object? id) {
    final value = id?.toString().trim() ?? '';
    if (!draft || value.isEmpty) return const {};
    return {'data-layer': value};
  }

  /// A link a visitor may follow, as the public path; `null` hides the
  /// control (`PublicStoreLayout.isHrefPubliclyEligible`).
  String? publicHref(String href) {
    final trimmed = href.trim();
    if (trimmed.isEmpty) return null;
    if (!shell.allowsHref(trimmed, storeUrl: storeUrl)) return null;
    final origin = Uri.tryParse(storeUrl);
    final destination = WebsiteDestination.parse(
      trimmed,
      internalOrigins: [if (origin != null && origin.hasScheme) origin],
    );
    // An e-mail or phone link opens the visitor's own app; otherwise the
    // destination as Flutter navigates to it (`navigateToHref`): only an
    // absolute http(s) URL leaves the store, and anything else, any other
    // scheme included, is a path inside it.
    if (Uri.tryParse(trimmed) case final uri?
        when uri.isScheme('mailto') || uri.isScheme('tel')) {
      return trimmed;
    }
    return shell.categoryHref(destination) ??
        StorefrontShell.publicPath(destination.href);
  }

  PublicWebsiteContactFacts get siteContact => PublicWebsiteContactFacts(
    phone: shell.setting('contact_phone'),
    email: shell.setting('contact_email'),
    address: shell.setting('contact_address'),
    whatsapp: shell.setting('whatsapp'),
    mapsUrl: shell.setting(
      'business_google_maps_url',
      shell.setting('google_maps_url'),
    ),
  );
}

/// The wrapper every block gets from `PageComposition`: the theme's side
/// padding unless full-bleed, its exact or minimum height, the space after
/// it and the bands it is drawn in. [fill] takes the canvas width (a widget that
/// expands); otherwise the block is as wide as its content and centered.
Component composedBlock(
  ComposedBlock composed, {
  required Component child,
  required bool fill,
  bool draft = false,
}) {
  final geometry = composed.block.geometry;
  final exact = geometry.exactHeight;
  // A minimum height lets the block grow and gives it no height of its own:
  // its content lays out as with none, inside at least this much.
  final minimum = exact == null ? geometry.minimumHeight : null;
  final surface = BlockSurface(
    composed.block.type,
    composed.data,
    composed.viewport,
  );
  final style = [
    if (composed.gapAfter > 0) '--gap:${_px(composed.gapAfter)}',
    if (exact != null) 'height:${_px(exact)}',
    if (minimum != null) 'min-height:${_px(minimum)}',
    ...surface.paddingVars,
  ];
  return div(
    classes: [
      'blk',
      if (fill) 'fill',
      if (geometry.fullBleed) 'bleed',
      if (minimum != null) 'minh',
      if (surface.ownsBackground) 'own-bg',
    ].join(' '),
    attributes: {
      'data-block': composed.block.blockType,
      // The editor's draft: which block a click picks, and its name.
      if (draft) 'data-block-id': composed.block.id,
      if (draft) 'data-block-label': draftBlockName(composed),
      if (composed.bands case final bands?) 'data-bands': bands.join(' '),
      if (style.isNotEmpty) 'style': style.join(';'),
    },
    [
      // The block's own surface (`WebsiteBlockSurface`), painted once
      // around its family.
      if (surface.wraps)
        div(
          classes: 'srf',
          attributes: {
            if (surface.wrapperStyle.isNotEmpty) 'style': surface.wrapperStyle,
          },
          [child],
        )
      else
        child,
    ],
  );
}

/// What the editor calls [composed]'s block: its type's name.
String draftBlockName(ComposedBlock composed) {
  final type = composed.block.type;
  return type == null
      ? composed.block.blockType
      : websiteBaseBlockDefinitions[type]?.title ?? composed.block.blockType;
}

/// The block types an information page draws with [sharedBlock].
const coveredSharedBlockTypes = {
  WebsiteBlockType.hero,
  WebsiteBlockType.contact,
};

/// The block types a page drawn at the window's width (the home and the
/// editor's own pages) draws with [sharedBlock].
const pageCoveredBlockTypes = {
  WebsiteBlockType.hero,
  WebsiteBlockType.contact,
  WebsiteBlockType.carousel,
  WebsiteBlockType.products,
  WebsiteBlockType.categoryGrid,
  WebsiteBlockType.brandLogos,
  WebsiteBlockType.videoBanner,
  WebsiteBlockType.googleReviews,
  WebsiteBlockType.text,
  WebsiteBlockType.button,
  WebsiteBlockType.divider,
  WebsiteBlockType.faq,
  WebsiteBlockType.cta,
  WebsiteBlockType.features,
  WebsiteBlockType.about,
  WebsiteBlockType.stats,
  WebsiteBlockType.services,
  WebsiteBlockType.pricing,
  WebsiteBlockType.testimonials,
  WebsiteBlockType.gallery,
  WebsiteBlockType.team,
  WebsiteBlockType.partnersBanner,
  WebsiteBlockType.canvas,
};

/// Whether a page that draws [types] draws this block: its type, and what
/// the block holds (a carousel with a video slide is not drawn yet): a block
/// whose saved look the HTML would leave out is not drawn.
bool sharedBlockCovers(ComposedBlock composed, Set<WebsiteBlockType> types) {
  final type = composed.block.type;
  if (type == null || !types.contains(type)) return false;
  // A surface the HTML cannot draw as Flutter does yet is not drawn
  // without it ([BlockSurface.isDrawn]).
  if (!BlockSurface(type, composed.data, composed.viewport).isDrawn) {
    return false;
  }
  return switch (type) {
    WebsiteBlockType.carousel => carouselIsCovered(composed.data),
    WebsiteBlockType.products => productsBlockIsCovered(composed.data),
    WebsiteBlockType.categoryGrid => categoryGridIsCovered(composed.data),
    // A canvas reads its whole document: it resolves its own viewports.
    WebsiteBlockType.canvas => canvasBlockIsCovered(composed.block.blockData),
    _ => true,
  };
}

/// A block drawn by its shared renderer, or `null` when the HTML storefront
/// does not cover its type yet. The page decides which types it draws
/// ([sharedBlockCovers]): each one brings its stylesheet.
Component? sharedBlock(ComposedBlock composed, BlockRenderContext context) {
  return switch (composed.block.type) {
    WebsiteBlockType.hero => _HeroBlock(composed, context),
    WebsiteBlockType.contact => _ContactBlock(composed, context),
    WebsiteBlockType.carousel => CarouselBlockView(composed, context),
    WebsiteBlockType.products => ProductsBlockView(composed, context),
    WebsiteBlockType.categoryGrid => CategoryGridView(composed, context),
    WebsiteBlockType.brandLogos => BrandLogosView(composed, context),
    WebsiteBlockType.videoBanner => VideoBannerView(composed, context),
    WebsiteBlockType.googleReviews => GoogleReviewsView(composed, context),
    WebsiteBlockType.text => _TextBlock(composed, context),
    WebsiteBlockType.button => _ButtonBlock(composed, context),
    WebsiteBlockType.divider => _DividerBlock(composed),
    WebsiteBlockType.faq => FaqSectionView(composed, context),
    WebsiteBlockType.cta => CtaSectionView(composed, context),
    WebsiteBlockType.features => FeaturesBlockView(composed, context),
    WebsiteBlockType.about => AboutBlockView(composed, context),
    WebsiteBlockType.stats => StatsSectionView(composed, context),
    WebsiteBlockType.services => ServicesSectionView(composed, context),
    WebsiteBlockType.pricing => PricingSectionView(composed, context),
    WebsiteBlockType.testimonials => TestimonialsSectionView(composed, context),
    WebsiteBlockType.gallery => GallerySectionView(composed, context),
    WebsiteBlockType.team => TeamSectionView(composed, context),
    WebsiteBlockType.partnersBanner => PartnersStripView(composed, context),
    WebsiteBlockType.canvas => CanvasBlockView(composed, context),
    _ => null,
  };
}

/// `WebsiteTextBlockContent`: the text in the theme's style for its preset
/// (heading, subheading, caption or paragraph) with the editor's
/// formatting, in a column at most `maxWidth` wide and centered.
class _TextBlock extends StatelessComponent {
  const _TextBlock(this.composed, this.context);

  final ComposedBlock composed;
  final BlockRenderContext context;

  @override
  Component build(BuildContext _) {
    final data = composed.data;
    final text = (data['text'] ?? '').toString();
    final preset = switch ((data['preset'] ?? 'paragraph').toString()) {
      'heading' => 'heading',
      'subheading' => 'subheading',
      'caption' => 'caption',
      _ => 'paragraph',
    };
    final rawFormatting = data['formatting'];
    final formatting = rawFormatting is Map
        ? Map<String, dynamic>.from(rawFormatting)
        : const <String, dynamic>{};
    final maxWidth = switch (data['maxWidth']) {
      final num value => value.toDouble(),
      final String value => double.tryParse(value.trim()),
      _ => null,
    };
    final width = maxWidth == null || !maxWidth.isFinite
        ? null
        : maxWidth.clamp(200.0, 1200.0);
    final heading = preset == 'heading' || preset == 'subheading';
    final style = <String>[
      if (width != null) 'width:min(${_px(width)},100%)',
      ...textFormattingCss(
        formatting,
        family: heading ? context.theme.headingFont : context.theme.bodyFont,
        weight: switch (preset) {
          'heading' => 700,
          'subheading' => 600,
          _ => 400,
        },
        fallback: heading ? 'var(--head)' : 'var(--body)',
        fontSize: switch (preset) {
          'heading' => context.theme.headingSize,
          'subheading' => 18,
          'caption' => context.theme.bodySize * 0.9,
          _ => context.theme.bodySize,
        },
        lineHeight: switch (preset) {
          'heading' => 36 / 28,
          'subheading' => 28 / 22,
          _ => 1.5,
        },
      ),
    ];
    return flutterText(
      preset == 'heading' ? 'h2' : 'p',
      classes: 'txt $preset',
      text: text,
      style: style,
      attributes: context.editText(const ['text']),
    );
  }
}

/// A Flutter `Text` as an element: written whole, its line breaks as
/// references, so its own spaces and breaks are drawn (`pre-wrap`, class
/// `ft`) and the renderer, which indents every line of a raw string it
/// prints, cannot add any; a last break is one more line, as in Flutter.
Component flutterText(
  String tag, {
  required String classes,
  required String text,
  List<String> style = const [],
  Map<String, String> attributes = const {},
}) {
  final css = style.isEmpty
      ? ''
      : ' style="${_attribute.convert(style.join(';'))}"';
  final extra = [
    for (final MapEntry(:key, :value) in attributes.entries)
      ' $key="${_attribute.convert(value)}"',
  ].join();
  final lines = text.replaceAll('\r\n', '\n');
  final content = _content.convert(lines).replaceAll('\n', '&#10;');
  final last = lines.endsWith('\n') ? ' data-break' : '';
  return RawText('<$tag class="ft $classes"$css$extra$last>$content</$tag>');
}

/// [textFormattingCss] as an element's `style`, only when the editor set
/// something: an unformatted text keeps its class's own rules.
Map<String, String> formattedStyle(
  Object? raw, {
  required String family,
  required int weight,
  required String fallback,
  required double fontSize,
  required double lineHeight,
  bool responsiveSize = false,
}) {
  if (raw is! Map || raw.isEmpty) return const {};
  final rules = textFormattingCss(
    Map<String, dynamic>.from(raw),
    family: family,
    weight: weight,
    fallback: fallback,
    fontSize: fontSize,
    lineHeight: lineHeight,
    responsiveSize: responsiveSize,
  );
  return rules.isEmpty ? const {} : {'style': rules.join(';')};
}

/// [TextFormatting.applyTo] as declarations over a preset's own style
/// ([family] at [weight]): bold, the weight, italic, underline, the size and
/// line height (the preset's height multiplier unless the editor set one),
/// color, letter spacing and family. A family Flutter can only draw at its
/// regular instance (Oswald's variable file) is emboldened from 600 up
/// (`-webkit-text-stroke`, as the hero); any other draws its own weight.
List<String> textFormattingCss(
  Map<String, dynamic> formatting, {
  required String family,
  required int weight,
  required String fallback,
  required double fontSize,
  required double lineHeight,

  /// The preset's size changes with the width (a block title): an authored
  /// height alone is then a multiplier of whichever size is drawn.
  bool responsiveSize = false,
}) {
  double? number(Object? raw) =>
      raw is num && raw.toDouble().isFinite ? raw.toDouble() : null;
  final weightIndex = formatting['fontWeight'];
  final authoredWeight = formatting['bold'] == true
      ? 700
      : weightIndex is int && weightIndex >= 0 && weightIndex < 9
      ? (weightIndex + 1) * 100
      : null;
  final effectiveWeight = authoredWeight ?? weight;
  final size = number(formatting['fontSize']);
  final height = number(formatting['lineHeight']);
  final color = formatting['textColor'];
  final spacing = number(formatting['letterSpacing']);
  final authoredFamily = (formatting['fontFamily'] ?? '').toString().trim();
  final safeFamily =
      authoredFamily.isNotEmpty &&
      !authoredFamily.contains(RegExp(r'[";{}<>\\]'));
  final drawnFamily = safeFamily ? authoredFamily : family;
  final align = switch (formatting['textAlign']) {
    'center' => 'center',
    'end' || 'right' => 'right',
    'justify' => 'justify',
    _ => null,
  };
  return [
    if (align != null) 'text-align:$align',
    if (authoredWeight != null || weight != 400 || safeFamily)
      ...storefrontFontDrawsRegularOnly(drawnFamily)
          ? [
              'font-weight:400',
              if (effectiveWeight >= 600)
                '-webkit-text-stroke:.032em currentColor',
            ]
          : ['font-weight:$effectiveWeight'],
    if (formatting['italic'] == true) 'font-style:italic',
    if (formatting['underline'] == true) 'text-decoration:underline',
    if (size != null && size > 0) 'font-size:${_px(size)}',
    if (size != null && size > 0 || height != null)
      responsiveSize && (size == null || size <= 0)
          ? 'line-height:${_num(height!)}'
          : 'line-height:'
                '${((size != null && size > 0 ? size : fontSize) * (height ?? lineHeight)).round()}px',
    if (color is int) 'color:${WebsiteRgba.fromArgb(color).css}',
    if (spacing != null) 'letter-spacing:${_px(spacing)}',
    if (safeFamily) 'font-family:"$authoredFamily",$fallback',
  ];
}

/// The standalone button (`_buildButton`): the theme's button across the
/// block's width, filled with the accent or drawn in it, and absent when it
/// has no destination a visitor may follow. It grows a little under the
/// pointer (`HoverScale`).
class _ButtonBlock extends StatelessComponent {
  const _ButtonBlock(this.composed, this.context);

  final ComposedBlock composed;
  final BlockRenderContext context;

  @override
  Component build(BuildContext _) {
    final action = WebsiteActionValue.resolvePrimary(
      composed.data,
      labelKeys: WebsiteButtonFields.button.label,
      hrefKeys: WebsiteButtonFields.button.href,
      variantKeys: WebsiteButtonFields.button.variant,
      defaultLabel: 'Botón',
      defaultVariant: WebsiteActionVariant.fromStorage(
        composed.data['style']?.toString(),
      ),
    );
    final href = action == null ? null : context.publicHref(action.href);
    if (action == null || href == null) return Component.fragment(const []);
    return a(
      classes: 'w-btn b-blk ${action.variant.name}',
      href: href,
      attributes: context.editButton(WebsiteButtonFields.button),
      [.text(action.label)],
    );
  }
}

/// `_buildDivider`: a line as thick as the block says (1 to 12), a share of
/// the width (10 % to all of it) and centered, in its color.
class _DividerBlock extends StatelessComponent {
  const _DividerBlock(this.composed);

  final ComposedBlock composed;

  @override
  Component build(BuildContext _) {
    final data = composed.data;
    final thickness = (_number(data['thickness']) ?? 1).clamp(1.0, 12.0);
    final share = (_number(data['widthPct']) ?? 1).clamp(0.1, 1.0);
    final color =
        flutterHexColor((data['color'] ?? '#E0E0E0').toString()) ??
        WebsiteRgba.fromArgb(0xFFE0E0E0);
    return div(
      classes: 'dv',
      attributes: {
        'role': 'separator',
        'style':
            'width:${_num(share * 100)}%;height:${_px(thickness)};'
            'background:${color.css}',
      },
      const [],
    );
  }
}

/// `#RRGGBB` or `#AARRGGBB` (alpha first), the only colors the blocks' own
/// parsers in Flutter read (`_parseHexColor`, the CTA's `_parseColor`).
WebsiteRgba? flutterHexColor(String raw) {
  var hex = raw.trim().replaceAll('#', '');
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  final value = int.tryParse(hex, radix: 16);
  return value == null ? null : WebsiteRgba.fromArgb(value);
}

/// `website_hero_block_content.dart`: the photo or the dark fallback, the
/// overlay, and the title, subtitle and button centered (or to one side).
class _HeroBlock extends StatelessComponent {
  const _HeroBlock(this.composed, this.context);

  final ComposedBlock composed;
  final BlockRenderContext context;

  @override
  Component build(BuildContext _) {
    final data = composed.data;
    final theme = context.theme;
    final rawTitle = (data['title'] ?? 'Bienvenido').toString();
    final title = rawTitle.trim().isEmpty ? 'Título' : rawTitle.trim();
    final subtitle = (data['subtitle'] ?? '').toString().trim();
    final action = resolveWebsiteHeroAction(data);
    final href = action == null ? null : context.publicHref(action.href);
    final image = _firstString(data, const ['imageUrl', 'backgroundImage']);
    final alt =
        _firstString(data, const [
          'imageAltText',
          'backgroundImageAltText',
          'altText',
        ]) ??
        '';
    final showOverlay = data['showOverlay'] != false;
    final opacity = (_number(data['overlayOpacity']) ?? 0.5).clamp(0.0, 1.0);
    final overlay = WebsiteRgba.fromArgb(
      parseWebsiteThemeColorValue(data['overlayColor']?.toString() ?? '') ??
          0xFF000000,
    );
    final configuredHeight = _number(data['blockHeight']);
    final alignment = switch (data['alignment']
        ?.toString()
        .trim()
        .toLowerCase()) {
      'left' => 'start',
      'right' => 'end',
      _ => 'center',
    };
    final focalX =
        ((_number(data['focalPointX']) ?? 0.5).clamp(0.0, 1.0)) * 100;
    final focalY =
        ((_number(data['focalPointY']) ?? 0.5).clamp(0.0, 1.0)) * 100;

    return section(
      classes: [
        'hero-blk',
        if (configuredHeight == null || configuredHeight <= 0)
          data['isFullScreen'] == true ? 'screen' : 'auto',
      ].join(' '),
      attributes: {
        if (configuredHeight != null && configuredHeight > 0)
          'style': 'height:${_px(configuredHeight)}',
      },
      [
        if (image != null && image.trim().isNotEmpty)
          img(
            classes: 'hero-img',
            src: image.trim(),
            alt: alt,
            attributes: {
              'style': 'object-position:${_num(focalX)}% ${_num(focalY)}%',
              'fetchpriority': 'high',
            },
          )
        else
          div(classes: 'hero-fallback', const []),
        if (showOverlay && opacity > 0)
          div(
            classes: 'hero-ov',
            attributes: {
              'style':
                  'background:linear-gradient('
                  '${overlay.withAlpha(opacity * 0.5).css},'
                  '${overlay.withAlpha(opacity * 0.8).css})',
            },
            const [],
          ),
        div(
          classes: 'hero-in',
          attributes: {'data-align': alignment},
          [
            h2(
              classes: 'hero-t',
              attributes: {
                ...context.editText(const ['title']),
                ...formattedStyle(
                  data['titleFormatting'],
                  family: theme.headingFont,
                  weight: 900,
                  fallback: 'var(--head)',
                  fontSize: theme.headingSize,
                  lineHeight: 1.12,
                  responsiveSize: true,
                ),
              },
              [.text(title.toUpperCase())],
            ),
            if (subtitle.isNotEmpty)
              p(
                classes: 'hero-s',
                attributes: {
                  ...context.editText(const ['subtitle']),
                  ...formattedStyle(
                    data['subtitleFormatting'],
                    family: theme.bodyFont,
                    weight: 600,
                    fallback: 'var(--body)',
                    fontSize: theme.bodySize,
                    lineHeight: 1.33,
                  ),
                },
                [.text(subtitle)],
              ),
            if (action != null && href != null)
              a(
                classes: 'w-btn on-dark ${action.variant.name}',
                href: href,
                attributes: context.editButton(WebsiteButtonFields.hero),
                [.text(action.label.toUpperCase())],
              ),
          ],
        ),
      ],
    );
  }
}

/// `website_contact_block_content.dart`: the title and subtitle centered,
/// then the contact card (the block's data, or the store's settings), the
/// form and the map, laid out by the width the block has.
class _ContactBlock extends StatelessComponent {
  const _ContactBlock(this.composed, this.context);

  final ComposedBlock composed;
  final BlockRenderContext context;

  @override
  Component build(BuildContext _) {
    final data = composed.data;
    final rawTitle = (data['title'] ?? 'Contáctanos').toString().trim();
    final title = rawTitle.isEmpty ? 'Contáctanos' : rawTitle;
    final subtitle = (data['subtitle'] ?? '').toString().trim();
    final facts = resolveWebsiteContactBlockFacts(
      data,
      site: context.siteContact,
    );
    final showForm = data['showForm'] != false;
    final showMap = data['showMap'] == true;
    final mapUrl = (data['mapUrl'] ?? '').toString().trim();
    final mapHref = showMap ? context.publicHref(mapUrl) : null;
    final cards = <Component>[
      if (facts.hasAny)
        div(classes: 'c-card info', [
          h3([.text('Información de contacto')]),
          if (facts.phone.isNotEmpty)
            _detail(
              mdPhone,
              'Teléfono',
              facts.phone,
              'tel:${_digits(facts.phone)}',
            ),
          if (facts.email.isNotEmpty)
            _detail(
              mdEmailOutlined,
              'Correo',
              facts.email,
              'mailto:${facts.email}',
            ),
          if (facts.address.isNotEmpty)
            _detail(mdLocationOnOutlined, 'Dirección', facts.address, null),
        ]),
      if (showForm)
        div(classes: 'c-card form', [
          h3([.text('Envíanos un mensaje')]),
          for (final name in const ['Nombre', 'Correo electrónico'])
            label(classes: 'c-field', [
              span([.text(name)]),
              const input(disabled: true),
            ]),
          label(classes: 'c-field', [
            span([.text('Mensaje')]),
            const textarea([], rows: 4, disabled: true),
          ]),
          button(
            classes: 'c-send',
            attributes: {'disabled': ''},
            [.text('Enviar consulta')],
          ),
        ]),
      if (showMap)
        div(classes: 'c-card map', [
          h3([.text('Cómo llegar')]),
          div(classes: 'c-map', [
            RawText(materialIcon(mdMapOutlined, size: 64)),
          ]),
          if (mapHref != null)
            a(classes: 'c-map-link', href: mapHref, [
              RawText(materialIcon(mdArrowOutward, size: 18)),
              .text('Abrir mapa'),
            ]),
        ]),
    ];
    return section(classes: 'contact-blk', [
      div(classes: 'contact-in', [
        h2(
          classes: 'contact-t',
          attributes: context.editText(const ['title']),
          [.text(title)],
        ),
        if (subtitle.isNotEmpty)
          p(
            classes: 'contact-s',
            attributes: context.editText(const ['subtitle']),
            [.text(subtitle)],
          ),
        if (cards.isNotEmpty)
          div(
            classes: 'contact-cards',
            attributes: {'data-count': '${cards.length}'},
            cards,
          ),
      ]),
    ]);
  }

  Component _detail(String icon, String label, String value, String? href) {
    return div(classes: 'c-detail', [
      RawText(materialIcon(icon, size: 22)),
      div([
        p(classes: 'c-label', [.text(label)]),
        if (href == null)
          p(classes: 'c-value', [.text(value)])
        else
          p(classes: 'c-value', [
            a(href: href, [.text(value)]),
          ]),
      ]),
    ]);
  }

  static String _digits(String phone) =>
      phone.replaceAll(RegExp(r'[^\d+]'), '');
}

const _content = HtmlEscape(HtmlEscapeMode.element);
const _attribute = HtmlEscape(HtmlEscapeMode.attribute);

String? _firstString(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value != null) return value.toString();
  }
  return null;
}

double? _number(Object? raw) {
  final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
  return value != null && value.isFinite ? value : null;
}

String _num(double value) => value == value.roundToDouble()
    ? '${value.round()}'
    : value.toStringAsFixed(2);

String _px(double value) => '${_num(value)}px';
