import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_type.dart';
import 'package:vinabike_public_core/modules/website/models/website_hero_content.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_color_value.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';
import 'package:vinabike_public_core/public_store/models/public_policy_content.dart';

import 'block_composition.dart';
import 'material_icons.dart';
import 'storefront_shell.dart';

/// Draws the editor's blocks as Flutter's `WebsiteBlockRenderer` does, for
/// the block types the HTML storefront already covers. A block it does not
/// cover yet is left out and named in [BlockRenderContext.uncovered].
class BlockRenderContext {
  BlockRenderContext({
    required this.shell,
    required this.theme,
    required this.storeUrl,
  });

  final StorefrontShell shell;
  final WebsiteThemeRoles theme;
  final String storeUrl;
  final uncovered = <String>{};

  /// A link a visitor may follow, as the public path; `null` hides the
  /// control (`PublicStoreLayout.isHrefPubliclyEligible`).
  String? publicHref(String href) {
    final trimmed = href.trim();
    if (trimmed.isEmpty) return null;
    if (!shell.allowsHref(trimmed, storeUrl: storeUrl)) return null;
    return StorefrontShell.publicPath(trimmed);
  }

  PublicWebsiteContactFacts get siteContact => PublicWebsiteContactFacts(
    phone: shell.setting('contact_phone'),
    email: shell.setting('contact_email'),
    address: shell.setting('contact_address'),
  );
}

/// The wrapper every block gets from `PageComposition`: the theme's side
/// padding unless full-bleed, its exact height, the space after it and the
/// bands it is drawn in. [fill] takes the canvas width (a widget that
/// expands); otherwise the block is as wide as its content and centered.
Component composedBlock(
  ComposedBlock composed, {
  required Component child,
  required bool fill,
}) {
  final geometry = composed.block.geometry;
  return div(
    classes: [
      'blk',
      if (fill) 'fill',
      if (geometry.fullBleed) 'bleed',
    ].join(' '),
    attributes: {
      'data-block': composed.block.blockType,
      if (composed.bands case final bands?) 'data-bands': bands.join(' '),
      if (composed.gapAfter > 0 || geometry.exactHeight != null)
        'style': [
          if (composed.gapAfter > 0) '--gap:${_px(composed.gapAfter)}',
          if (geometry.exactHeight case final height?) 'height:${_px(height)}',
        ].join(';'),
    },
    [child],
  );
}

/// The block types [sharedBlock] draws.
const coveredSharedBlockTypes = {
  WebsiteBlockType.hero,
  WebsiteBlockType.contact,
};

/// A block drawn by its shared renderer, or `null` when the HTML storefront
/// does not cover its type yet.
Component? sharedBlock(ComposedBlock composed, BlockRenderContext context) {
  return switch (composed.block.type) {
    WebsiteBlockType.hero => _HeroBlock(composed, context),
    WebsiteBlockType.contact => _ContactBlock(composed, context),
    _ => null,
  };
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
            h2(classes: 'hero-t', [.text(title.toUpperCase())]),
            if (subtitle.isNotEmpty) p(classes: 'hero-s', [.text(subtitle)]),
            if (action != null && href != null)
              a(classes: 'w-btn on-dark ${action.variant.name}', href: href, [
                .text(action.label.toUpperCase()),
              ]),
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
        h2(classes: 'contact-t', [.text(title)]),
        if (subtitle.isNotEmpty) p(classes: 'contact-s', [.text(subtitle)]),
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
