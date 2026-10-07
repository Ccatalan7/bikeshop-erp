import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/models/website_action.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';

import 'block_composition.dart';
import 'material_icons.dart';
import 'website_block_icons.dart';
import 'website_blocks_view.dart';

/// The editor's content blocks as Flutter's shared contents draw them:
/// frequently asked questions (`WebsiteFaqBlockContent`), the call to action
/// (`WebsiteCtaBlockContent`), the features (`WebsiteFeaturesBlockContent`)
/// and «about us» (`WebsiteAboutBlockContent`).

Map<String, dynamic> _map(Object? raw) =>
    raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};

List<Map<String, dynamic>> _items(
  Map<String, dynamic> data,
  String key, [
  List<String> aliases = const [],
]) {
  Object? raw;
  if (data.containsKey(key)) {
    raw = data[key];
  } else {
    for (final alias in aliases) {
      if (data.containsKey(alias)) {
        raw = data[alias];
        break;
      }
    }
  }
  return [
    if (raw is List)
      for (final item in raw)
        if (item is Map) Map<String, dynamic>.from(item),
  ];
}

String _string(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    if (data.containsKey(key)) return data[key]?.toString() ?? '';
  }
  return '';
}

double? _finite(Object? raw) {
  final value = switch (raw) {
    final num number => number.toDouble(),
    final String text => double.tryParse(text.trim()),
    _ => null,
  };
  return value != null && value.isFinite ? value : null;
}

String _focal(Map<String, dynamic> data) {
  String percent(Object? raw) {
    final value = ((_finite(raw) ?? 0.5).clamp(0.0, 1.0)) * 100;
    return value == value.roundToDouble()
        ? '${value.round()}%'
        : '${value.toStringAsFixed(2)}%';
  }

  return '${percent(data['focalPointX'])} ${percent(data['focalPointY'])}';
}

/// One text of a block in its slot's style with the editor's formatting.
Component _slot(
  String tag,
  String classes,
  String text,
  Object? formatting, {
  required String family,
  required int weight,
  required String fallback,
  required double fontSize,
  required double lineHeight,
  bool responsiveSize = false,
  Map<String, String> attributes = const {},
}) => flutterText(
  tag,
  classes: classes,
  text: text,
  attributes: attributes,
  style: textFormattingCss(
    _map(formatting),
    family: family,
    weight: weight,
    fallback: fallback,
    fontSize: fontSize,
    lineHeight: lineHeight,
    responsiveSize: responsiveSize,
  ),
);

/// `WebsiteFaqBlockContent`: the title and subtitle centered, then each
/// question in a card that opens to its answer (`ExpansionTile`).
class FaqBlockView extends StatelessComponent {
  const FaqBlockView(this.composed, this.context, {super.key});

  final ComposedBlock composed;
  final BlockRenderContext context;

  @override
  Component build(BuildContext _) {
    final data = composed.data;
    final theme = context.theme;
    final rawTitle = (data['title'] ?? 'Preguntas frecuentes').toString();
    final title = rawTitle.trim().isEmpty
        ? 'Preguntas frecuentes'
        : rawTitle.trim();
    final subtitle = (data['subtitle'] ?? '').toString();
    final items = _items(data, 'items');
    return section(classes: 'faq-blk', [
      div(classes: 'faq-in', [
        _slot(
          'h2',
          'faq-t',
          title,
          data['titleFormatting'],
          family: theme.headingFont,
          weight: 700,
          fallback: 'var(--head)',
          fontSize: 40,
          lineHeight: 1.15,
          responsiveSize: true,
          attributes: context.editText(const ['title']),
        ),
        if (subtitle.trim().isNotEmpty)
          _slot(
            'p',
            'faq-s',
            subtitle.trim(),
            data['subtitleFormatting'],
            family: theme.bodyFont,
            weight: 400,
            fallback: 'var(--body)',
            fontSize: 17,
            lineHeight: 1.45,
            attributes: context.editText(const ['subtitle']),
          ),
        if (items.isNotEmpty)
          div(classes: 'faq-list', [
            for (final (index, item) in items.indexed)
              details(classes: 'faq-it', [
                summary(classes: 'faq-q', [
                  _slot(
                    'span',
                    'faq-qt',
                    (item['question'] ?? '').toString(),
                    item['questionFormatting'],
                    family: theme.headingFont,
                    weight: 600,
                    fallback: 'var(--head)',
                    fontSize: 16,
                    lineHeight: 1.5,
                    attributes: context.editText(
                      const ['question'],
                      collection: const ['items'],
                      index: index,
                    ),
                  ),
                  RawText(materialIcon(mdExpandMore, classes: 'faq-chev')),
                ]),
                div(classes: 'faq-a', [
                  _slot(
                    'p',
                    'faq-at',
                    (item['answer'] ?? '').toString(),
                    item['answerFormatting'],
                    family: theme.bodyFont,
                    weight: 400,
                    fallback: 'var(--body)',
                    fontSize: theme.bodySize,
                    lineHeight: 1.5,
                    attributes: context.editText(
                      const ['answer'],
                      collection: const ['items'],
                      index: index,
                    ),
                  ),
                ]),
              ]),
          ]),
      ]),
    ]);
  }
}

/// `WebsiteCtaBlockContent`: the title in capitals, the subtitle and the
/// button over the photo (with its veil) or the primary color's gradient.
class CtaBlockView extends StatelessComponent {
  const CtaBlockView(this.composed, this.context, {super.key});

  final ComposedBlock composed;
  final BlockRenderContext context;

  /// The button: its label as written (empty hides it), its destination
  /// and the outline look unless the block says another.
  static WebsiteActionValue? action(Map<String, dynamic> data) {
    const labelKeys = ['buttonText', 'ctaText', 'label'];
    const hrefKeys = ['buttonLink', 'ctaLink', 'link'];
    final resolved = WebsiteActionValue.resolvePrimary(
      data,
      labelKeys: labelKeys,
      hrefKeys: hrefKeys,
      variantKeys: const ['actionVariant'],
      defaultLabel: '',
      defaultHref: '',
      defaultVariant: WebsiteActionVariant.outline,
    );
    final labelPresent = labelKeys.any(data.containsKey);
    final hrefPresent = hrefKeys.any(data.containsKey);
    final label = labelPresent
        ? _string(data, labelKeys).trim()
        : resolved?.label.trim() ?? '';
    if (label.isEmpty) return null;
    final href = hrefPresent
        ? _string(data, hrefKeys).trim()
        : resolved?.href.trim() ?? '';
    final variant = data.containsKey('actionVariant')
        ? WebsiteActionVariant.fromStorage(
            data['actionVariant']?.toString(),
            fallback: WebsiteActionVariant.outline,
          )
        : resolved?.variant ?? WebsiteActionVariant.outline;
    return WebsiteActionValue(label: label, href: href, variant: variant);
  }

  @override
  Component build(BuildContext _) {
    final data = composed.data;
    final theme = context.theme;
    final title = _string(data, const ['title']).trim();
    final subtitle = _string(data, const ['subtitle', 'description']);
    final image = _string(data, const ['backgroundImage', 'imageUrl']).trim();
    final alt = _string(data, const [
      'backgroundImageAltText',
      'imageAltText',
    ]).trim();
    final height = _finite(data['blockHeight']);
    final cta = action(data);
    // An empty destination is a disabled button in Flutter; one a visitor
    // may not follow is not drawn.
    final href = cta == null || cta.href.isEmpty
        ? null
        : context.publicHref(cta.href);
    final overlay =
        flutterHexColor(data['overlayColor']?.toString() ?? '') ??
        WebsiteRgba.fromArgb(0xFF000000);
    final opacity = (_finite(data['overlayOpacity']) ?? 0.5).clamp(0.0, 1.0);
    return section(
      classes: ['cta-blk', if (height != null && height > 0) 'fixed'].join(' '),
      attributes: {
        if (image.isEmpty) 'data-diag': '',
        if (height != null && height > 0)
          'style':
              'height:${height.round() == height ? height.round() : height}px',
      },
      [
        if (image.isNotEmpty)
          img(
            classes: 'cta-img',
            src: image,
            alt: alt,
            attributes: {
              'style': 'object-position:${_focal(data)}',
              'loading': 'lazy',
            },
          ),
        if (image.isNotEmpty && opacity > 0)
          div(
            classes: 'cta-ov',
            attributes: {
              'style': 'background:${overlay.withAlpha(opacity).css}',
            },
            const [],
          ),
        div(classes: 'cta-in', [
          _slot(
            'h2',
            'cta-t',
            (title.isEmpty ? '¿Necesitas ayuda?' : title).toUpperCase(),
            data['titleFormatting'],
            family: theme.headingFont,
            weight: 700,
            fallback: 'var(--head)',
            fontSize: 24,
            lineHeight: 1.5,
            attributes: context.editText(const ['title']),
          ),
          if (subtitle.isNotEmpty)
            _slot(
              'p',
              'cta-s',
              subtitle,
              data['subtitleFormatting'] ?? data['descriptionFormatting'],
              family: theme.bodyFont,
              weight: 400,
              fallback: 'var(--body)',
              fontSize: theme.bodySize + 2,
              lineHeight: 1.5,
              attributes: context.editText(const ['subtitle', 'description']),
            ),
          if (cta != null && (cta.href.isEmpty || href != null))
            href == null
                ? button(
                    classes: 'w-btn cta-btn ${cta.variant.name} off',
                    attributes: {'type': 'button', 'disabled': ''},
                    [.text(cta.label.toUpperCase())],
                  )
                : a(classes: 'w-btn cta-btn ${cta.variant.name}', href: href, [
                    .text(cta.label.toUpperCase()),
                  ]),
        ]),
      ],
    );
  }
}

/// `WebsiteFeaturesBlockContent`: the title and the features as cards in a
/// centered wrap of 320 wide (the column's width on a phone) or as a list
/// with the icon in a tinted circle.
class FeaturesBlockView extends StatelessComponent {
  const FeaturesBlockView(this.composed, this.context, {super.key});

  final ComposedBlock composed;
  final BlockRenderContext context;

  @override
  Component build(BuildContext _) {
    final data = composed.data;
    final theme = context.theme;
    final rawTitle = (data['title'] ?? 'Por qué elegirnos').toString();
    final title = rawTitle.trim().isEmpty ? 'Características' : rawTitle.trim();
    final features = _items(data, 'features', const ['items']);
    final list = data['layout']?.toString().trim().toLowerCase() == 'list';
    return section(classes: 'ft-blk', [
      div(classes: 'ft-in', [
        _slot(
          'h2',
          'ft-t',
          title,
          data['titleFormatting'],
          family: theme.headingFont,
          weight: 700,
          fallback: 'var(--head)',
          fontSize: 40,
          lineHeight: 1.15,
          responsiveSize: true,
          attributes: context.editText(const ['title']),
        ),
        if (features.isNotEmpty)
          div(classes: list ? 'ft-list' : 'ft-grid', [
            for (final (index, item) in features.indexed)
              list ? _listItem(item, index, theme) : _card(item, index, theme),
          ]),
      ]),
    ]);
  }

  Component _card(
    Map<String, dynamic> item,
    int index,
    WebsiteThemeRoles theme,
  ) {
    final description = (item['description'] ?? '').toString();
    return div(classes: 'ft-card', [
      RawText(
        materialIcon(
          websiteBlockIcon(item['icon']?.toString()),
          size: 48,
          classes: 'ft-ic',
        ),
      ),
      _slot(
        'h3',
        'ft-ct',
        (item['title'] ?? '').toString(),
        item['titleFormatting'],
        family: theme.headingFont,
        weight: 600,
        fallback: 'var(--head)',
        fontSize: 18,
        lineHeight: 28 / 22,
        attributes: context.editText(
          const ['title'],
          collection: const ['features', 'items'],
          index: index,
        ),
      ),
      if (description.trim().isNotEmpty)
        _slot(
          'p',
          'ft-cd',
          description,
          item['descriptionFormatting'],
          family: theme.bodyFont,
          weight: 400,
          fallback: 'var(--body)',
          fontSize: theme.bodySize,
          lineHeight: 1.5,
          attributes: context.editText(
            const ['description'],
            collection: const ['features', 'items'],
            index: index,
          ),
        ),
    ]);
  }

  Component _listItem(
    Map<String, dynamic> item,
    int index,
    WebsiteThemeRoles theme,
  ) {
    final description = (item['description'] ?? '').toString();
    return div(classes: 'ft-row', [
      span(classes: 'ft-dot', [
        RawText(
          materialIcon(websiteBlockIcon(item['icon']?.toString()), size: 28),
        ),
      ]),
      div(classes: 'ft-rtx', [
        _slot(
          'h3',
          'ft-rt',
          (item['title'] ?? '').toString(),
          item['titleFormatting'],
          family: theme.headingFont,
          weight: 700,
          fallback: 'var(--head)',
          fontSize: 18,
          lineHeight: 1.5,
          attributes: context.editText(
            const ['title'],
            collection: const ['features', 'items'],
            index: index,
          ),
        ),
        if (description.trim().isNotEmpty)
          _slot(
            'p',
            'ft-rd',
            description,
            item['descriptionFormatting'],
            family: theme.bodyFont,
            weight: 400,
            fallback: 'var(--body)',
            fontSize: 15,
            lineHeight: 1.5,
            attributes: context.editText(
              const ['description'],
              collection: const ['features', 'items'],
              index: index,
            ),
          ),
      ]),
    ]);
  }
}

/// `WebsiteAboutBlockContent`: the title and text beside the photo from
/// 900 wide (the photo on the side the block says), above it below that,
/// or a centered column without one.
class AboutBlockView extends StatelessComponent {
  const AboutBlockView(this.composed, this.context, {super.key});

  final ComposedBlock composed;
  final BlockRenderContext context;

  @override
  Component build(BuildContext _) {
    final data = composed.data;
    final theme = context.theme;
    final rawTitle = (data['title'] ?? 'Sobre Nosotros').toString();
    final title = rawTitle.trim().isEmpty ? 'Sobre Nosotros' : rawTitle.trim();
    final content = (data['content'] ?? data['description'] ?? '').toString();
    final image = (data['imageUrl'] ?? data['image'] ?? '').toString().trim();
    final alt = (data['imageAltText'] ?? '').toString().trim();
    final left = data['imagePosition']?.toString() == 'left';
    final text = div(classes: 'ab-tx', [
      _slot(
        'h2',
        'ab-t',
        title,
        data['titleFormatting'],
        family: theme.headingFont,
        weight: 700,
        fallback: 'var(--head)',
        fontSize: 40,
        lineHeight: 1.15,
        responsiveSize: true,
        attributes: context.editText(const ['title']),
      ),
      _slot(
        'p',
        'ab-c',
        content,
        data['contentFormatting'] ?? data['descriptionFormatting'],
        family: theme.bodyFont,
        weight: 400,
        fallback: 'var(--body)',
        fontSize: 17,
        lineHeight: 1.6,
        responsiveSize: true,
        attributes: context.editText(const ['content', 'description']),
      ),
    ]);
    return section(
      classes: 'ab-blk',
      attributes: {if (image.isNotEmpty) 'data-media': left ? 'left' : 'right'},
      [
        div(classes: 'ab-in', [
          if (image.isNotEmpty)
            div(classes: 'ab-media', [
              img(
                src: image,
                alt: alt,
                attributes: {
                  'style': 'object-position:${_focal(data)}',
                  'loading': 'lazy',
                },
              ),
            ]),
          text,
        ]),
      ],
    );
  }
}

/// Flutter's gradient from the top-left to the bottom-right corner runs
/// along the diagonal, whatever the box's shape; CSS's «to bottom right»
/// does only for a square. This gives each `[data-diag]` box the angle of its
/// own diagonal (`--diag`), kept as it resizes.
const ctaDiagonalScript =
    '(()=>{const s=e=>{const r=e.getBoundingClientRect();'
    'if(r.width&&r.height)e.style.setProperty("--diag",'
    '(180-Math.atan2(r.width,r.height)*180/Math.PI).toFixed(3)+"deg")};'
    'const b=document.querySelectorAll("[data-diag]");b.forEach(s);'
    'if(window.ResizeObserver){const o=new ResizeObserver(l=>l.forEach(x=>s(x.target)));'
    'b.forEach(e=>o.observe(e))}})()';
