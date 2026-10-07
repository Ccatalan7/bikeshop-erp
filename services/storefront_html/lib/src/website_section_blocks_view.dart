import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/models/website_action.dart';
import 'package:vinabike_public_core/modules/website/models/website_image_fields.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_type.dart';
import 'package:vinabike_public_core/modules/website/models/website_section_content.dart';
import 'package:vinabike_public_core/modules/website/theme/website_section_palette.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';

import 'block_composition.dart';
import 'material_icons.dart';
import 'storefront_fonts.dart';
import 'website_blocks_view.dart';

/// The section blocks as Flutter's shared contents draw them since the
/// sections design (2026-10-07): bands of the page on the theme's light, gray
/// or dark tone (`WebsiteSectionPalette`), each with an eyebrow, a title in
/// the heading font and capitals, and its own content in a centered column.
/// Stats (`WebsiteStatsBlockContent`), services, plans, testimonials,
/// gallery, team, questions, the brands strip and the call to action. Their
/// sizes follow the block's width (`WebsiteSectionWidth`) through container
/// queries on the block, as the Flutter contents read their own width.

Map<String, dynamic> _map(Object? raw) =>
    raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};

String _focal(Map<String, dynamic> data) {
  String percent(Object? raw) {
    final number = raw is num ? raw.toDouble() : double.tryParse('$raw');
    final value =
        ((number != null && number.isFinite ? number : 0.5).clamp(0.0, 1.0)) *
        100;
    return value == value.roundToDouble()
        ? '${value.round()}%'
        : '${value.toStringAsFixed(2)}%';
  }

  return '${percent(data['focalPointX'])} ${percent(data['focalPointY'])}';
}

/// A text in a section's style with the editor's formatting: the class
/// gives its size by the block's width, [weight] its weight in [family].
Component _text(
  String tag,
  String classes,
  String text,
  Object? formatting, {
  required String family,
  required int weight,
  required String fallback,
  required double fontSize,
  required double lineHeight,
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
    responsiveSize: true,
  ),
);

/// The band a section is drawn in: its tone and the centered column.
Component _section(
  String classes,
  WebsiteSectionTone tone,
  List<Component> children, {
  Map<String, String> attributes = const {},
}) => section(
  classes: 'sec $classes',
  attributes: {'data-tone': tone.name, ...attributes},
  [div(classes: 'sec-in', children)],
);

/// A section's header: the eyebrow, the title and, beside it (under it on a
/// phone), the note. [ruled] closes it with the heavy line.
Component? _header(
  Map<String, dynamic> data,
  BlockRenderContext context, {
  required String titleClass,
  String noteKey = 'subtitle',
  List<String> noteAliases = const [],
  bool ruled = false,
  bool note = true,
}) {
  final theme = context.theme;
  final eyebrow = websiteSectionText(data, const ['eyebrow']).trim();
  final title = websiteSectionText(data, const ['title']).trim();
  final noteText = note
      ? websiteSectionText(data, [noteKey, ...noteAliases]).trim()
      : '';
  if (eyebrow.isEmpty && title.isEmpty && noteText.isEmpty) return null;
  return div(classes: ['sec-hd', if (ruled) 'ruled'].join(' '), [
    div(classes: 'sec-hd-t', [
      if (eyebrow.isNotEmpty)
        p(classes: 'sec-eye', attributes: context.editText(const ['eyebrow']), [
          .text(eyebrow),
        ]),
      if (title.isNotEmpty)
        _text(
          'h2',
          'sec-t $titleClass',
          title,
          data['titleFormatting'],
          family: theme.headingFont,
          weight: 500,
          fallback: 'var(--head)',
          fontSize: 48,
          lineHeight: 1.05,
          attributes: context.editText(const ['title']),
        ),
    ]),
    if (noteText.isNotEmpty)
      _text(
        'p',
        'sec-note',
        noteText,
        data['${noteKey}Formatting'],
        family: theme.bodyFont,
        weight: 400,
        fallback: 'var(--body)',
        fontSize: 17,
        lineHeight: 1.5,
        attributes: context.editText([noteKey, ...noteAliases]),
      ),
  ]);
}

/// `WebsiteStatsBlockContent`: the header on the dark band, then the
/// figures in a row under a rule, each with its suffix in the accent and
/// what it counts.
class StatsSectionView extends StatelessComponent {
  const StatsSectionView(this.composed, this.context, {super.key});

  final ComposedBlock composed;
  final BlockRenderContext context;

  @override
  Component build(BuildContext _) {
    final data = composed.data;
    final theme = context.theme;
    final metrics = websiteSectionItems(data, 'metrics', const [
      'stats',
      'items',
    ]);
    final tone = WebsiteSectionTone.of(WebsiteBlockType.stats, data);
    return _section('st', tone, [
      ?_header(data, context, titleClass: 'st-t'),
      if (metrics.isNotEmpty)
        div(
          classes: 'st-grid',
          attributes: {
            'style':
                '--cd:${websiteStatsColumns(metrics.length, desktop: true)};'
                '--cm:${websiteStatsColumns(metrics.length, desktop: false)}',
          },
          [
            for (final (index, metric) in metrics)
              if (websiteStatsFigure(metric, setting: context.shell.setting)
                  case final figure)
                div(classes: 'st-m', [
                  div(classes: 'st-v', [
                    _text(
                      'span',
                      'st-num',
                      figure.value,
                      metric['valueFormatting'],
                      family: theme.headingFont,
                      weight: 500,
                      fallback: 'var(--head)',
                      fontSize: 76,
                      lineHeight: 1,
                      // A Google figure is read from the sync, never written
                      // here.
                      attributes: figure.live
                          ? const {}
                          : context.editText(
                              const ['value'],
                              collection: const ['metrics', 'stats', 'items'],
                              index: index,
                            ),
                    ),
                    if (figure.suffix.trim().isNotEmpty)
                      _text(
                        'span',
                        'st-suf',
                        figure.suffix.trim(),
                        metric['suffixFormatting'],
                        family: theme.headingFont,
                        weight: 500,
                        fallback: 'var(--head)',
                        fontSize: 26,
                        lineHeight: 1,
                        attributes: context.editText(
                          const ['suffix'],
                          collection: const ['metrics', 'stats', 'items'],
                          index: index,
                        ),
                      ),
                  ]),
                  if (websiteSectionText(metric, const [
                    'label',
                  ]).trim().isNotEmpty)
                    _text(
                      'p',
                      'st-l',
                      websiteSectionText(metric, const ['label']).trim(),
                      metric['labelFormatting'],
                      family: theme.bodyFont,
                      weight: 500,
                      fallback: 'var(--body)',
                      fontSize: 16,
                      lineHeight: 1.45,
                      attributes: context.editText(
                        const ['label'],
                        collection: const ['metrics', 'stats', 'items'],
                        index: index,
                      ),
                    ),
                ]),
          ],
        ),
    ]);
  }
}

/// `WebsiteServicesBlockContent`: the ruled header, then the services as
/// numbered rows with their detail and price, and the shop's photo beside
/// them on a desktop.
class ServicesSectionView extends StatelessComponent {
  const ServicesSectionView(this.composed, this.context, {super.key});

  final ComposedBlock composed;
  final BlockRenderContext context;

  @override
  Component build(BuildContext _) {
    final data = composed.data;
    final theme = context.theme;
    final services = websiteSectionItems(data, 'services', const ['items']);
    final tone = WebsiteSectionTone.of(WebsiteBlockType.services, data);
    final image = websiteSectionText(data, const ['imageUrl']).trim();
    final caption = websiteSectionText(data, const ['caption']).trim();
    final captionDetail = websiteSectionText(data, const [
      'captionDetail',
    ]).trim();
    const collection = ['services', 'items'];
    return _section('sv', tone, [
      ?_header(data, context, titleClass: 'sv-t', ruled: true),
      div(classes: ['sv-body', if (image.isNotEmpty) 'media'].join(' '), [
        div(classes: 'sv-list', [
          for (final (position, (index, item)) in services.indexed)
            div(classes: 'sv-row', [
              span(classes: 'sv-n', [
                .text((position + 1).toString().padLeft(2, '0')),
              ]),
              div(classes: 'sv-tx', [
                _text(
                  'h3',
                  'sv-name',
                  websiteSectionText(item, const ['title']),
                  item['titleFormatting'],
                  family: theme.bodyFont,
                  weight: 600,
                  fallback: 'var(--body)',
                  fontSize: 19,
                  lineHeight: 1.3,
                  attributes: context.editText(
                    const ['title'],
                    collection: collection,
                    index: index,
                  ),
                ),
                if (websiteSectionText(item, const [
                  'description',
                ]).trim().isNotEmpty)
                  _text(
                    'p',
                    'sv-d',
                    websiteSectionText(item, const ['description']).trim(),
                    item['descriptionFormatting'],
                    family: theme.bodyFont,
                    weight: 400,
                    fallback: 'var(--body)',
                    fontSize: 15,
                    lineHeight: 1.45,
                    attributes: context.editText(
                      const ['description'],
                      collection: collection,
                      index: index,
                    ),
                  ),
              ]),
              if (websiteSectionText(item, const ['price']).trim().isNotEmpty)
                _text(
                  'span',
                  'sv-p',
                  websiteSectionText(item, const ['price']).trim(),
                  item['priceFormatting'],
                  family: theme.headingFont,
                  weight: 500,
                  fallback: 'var(--head)',
                  fontSize: 26,
                  lineHeight: 1,
                  attributes: context.editText(
                    const ['price'],
                    collection: collection,
                    index: index,
                  ),
                )
              else
                span(classes: 'sv-p', const []),
            ]),
        ]),
        if (image.isNotEmpty)
          figure(
            classes: 'sv-fig',
            attributes: context.editImage(WebsiteImageFields.services),
            [
              img(
                src: image,
                alt: websiteSectionText(data, const ['imageAltText']).trim(),
                attributes: {
                  'style': 'object-position:${_focal(data)}',
                  'loading': 'lazy',
                },
              ),
              if (caption.isNotEmpty || captionDetail.isNotEmpty)
                figcaption([
                  span(attributes: context.editText(const ['caption']), [
                    .text(caption),
                  ]),
                  span(attributes: context.editText(const ['captionDetail']), [
                    .text(captionDetail),
                  ]),
                ]),
            ],
          ),
      ]),
    ]);
  }
}

/// `WebsitePricingBlockContent`: the header, then the plans side by side in
/// one card (the highlighted one on the dark tone), or as stacked cards when
/// each would have less than 260 (`websitePlansSideBySide`).
class PricingSectionView extends StatelessComponent {
  const PricingSectionView(this.composed, this.context, {super.key});

  final ComposedBlock composed;
  final BlockRenderContext context;

  @override
  Component build(BuildContext _) {
    final data = composed.data;
    final plans = websiteSectionItems(data, 'plans', const ['items']);
    final tone = WebsiteSectionTone.of(WebsiteBlockType.pricing, data);
    return _section(
      'pr',
      tone,
      [
        ?_header(data, context, titleClass: 'pr-t'),
        if (plans.isNotEmpty)
          div(classes: 'pr-plans', [
            for (final (index, plan) in plans) _plan(plan, index),
          ]),
      ],
      attributes: {'data-n': '${plans.length}'},
    );
  }

  Component _plan(Map<String, dynamic> plan, int index) {
    final theme = context.theme;
    final featured = plan['highlighted'] == true || plan['isFeatured'] == true;
    final tag = websiteSectionText(plan, const ['tag']).trim();
    final badge = websiteSectionText(plan, const ['badge']).trim();
    final note = websiteSectionText(plan, const ['note']).trim();
    final price = websiteSectionText(plan, const ['price']).trim();
    final features = [
      if (plan['features'] case final List raw)
        for (final feature in raw)
          if (feature.toString().trim().isNotEmpty) feature.toString().trim(),
    ];
    final label = websiteSectionText(
      plan,
      WebsiteButtonFields.plan.label,
    ).trim();
    final href = context.publicHref(
      websiteSectionText(plan, WebsiteButtonFields.plan.href),
    );
    const collection = ['plans', 'items'];
    Map<String, String> edit(String key) =>
        context.editText([key], collection: collection, index: index);
    return div(classes: ['pr-plan', if (featured) 'inv'].join(' '), [
      if (featured && badge.isNotEmpty)
        span(classes: 'pr-badge top', attributes: edit('badge'), [
          .text(badge),
        ]),
      div(classes: 'pr-head', [
        _text(
          'h3',
          'pr-name',
          websiteSectionText(plan, const ['name']),
          plan['nameFormatting'],
          family: theme.headingFont,
          weight: 500,
          fallback: 'var(--head)',
          fontSize: 30,
          lineHeight: 1.2,
          attributes: edit('name'),
        ),
        if (featured && badge.isNotEmpty)
          span(classes: 'pr-badge side', [.text(badge)])
        else if (tag.isNotEmpty)
          span(classes: 'pr-tag', attributes: edit('tag'), [.text(tag)]),
        if (price.isNotEmpty) span(classes: 'pr-price small', [.text(price)]),
      ]),
      if (price.isNotEmpty)
        _text(
          'p',
          'pr-price',
          price,
          plan['priceFormatting'],
          family: theme.headingFont,
          weight: 500,
          fallback: 'var(--head)',
          fontSize: 60,
          lineHeight: 1,
          attributes: edit('price'),
        ),
      if (note.isNotEmpty)
        p(classes: 'pr-note', attributes: edit('note'), [.text(note)]),
      if (features.isNotEmpty) ...[
        p(classes: 'pr-inc', [.text('Incluye')]),
        ul(classes: 'pr-feats', [
          for (final feature in features)
            li([
              RawText(materialIcon(mdCheck, size: 20, classes: 'pr-ck')),
              span([.text(feature)]),
            ]),
        ]),
      ],
      if (label.isNotEmpty && href != null)
        div(classes: 'pr-cta', [
          a(
            classes: 'sec-btn ${featured ? 'acc' : 'line'}',
            href: href,
            attributes: context.editButton(
              WebsiteButtonFields.plan,
              index: index,
            ),
            [.text(label)],
          ),
        ]),
    ]);
  }
}

/// `WebsiteTestimonialsBlockContent`: the store's score in Google with its
/// stars and the link to its profile, beside the quotes (the block's own,
/// or the synced Google reviews when it has none).
class TestimonialsSectionView extends StatelessComponent {
  const TestimonialsSectionView(this.composed, this.context, {super.key});

  final ComposedBlock composed;
  final BlockRenderContext context;

  @override
  Component build(BuildContext _) {
    final data = composed.data;
    final theme = context.theme;
    final tone = WebsiteSectionTone.of(WebsiteBlockType.testimonials, data);
    final content = WebsiteTestimonialsContent.resolve(
      data,
      setting: context.shell.setting,
      mapsUrl: context.siteContact.mapsUrl,
    );
    final eyebrow = websiteSectionText(data, const ['eyebrow']).trim();
    final title = websiteSectionText(data, const ['title']).trim();
    final note = content.note(websiteSectionText(data, const ['subtitle']));
    final rating = content.rating;
    final mapsHref = content.mapsUrl.isEmpty
        ? null
        : context.publicHref(content.mapsUrl);
    return _section('ts', tone, [
      div(classes: 'ts-cols', [
        div(classes: 'ts-score', [
          if (eyebrow.isNotEmpty)
            p(
              classes: 'sec-eye',
              attributes: context.editText(const ['eyebrow']),
              [.text(eyebrow)],
            ),
          if (title.isNotEmpty)
            _text(
              'h2',
              'sec-t ts-t',
              title,
              data['titleFormatting'],
              family: theme.headingFont,
              weight: 500,
              fallback: 'var(--head)',
              fontSize: 48,
              lineHeight: 1.05,
              attributes: context.editText(const ['title']),
            ),
          if (rating != null)
            div(classes: 'ts-rate', [
              span(classes: 'ts-num', [.text(websiteRatingLabel(rating))]),
              div(classes: 'ts-rate-s', [
                _stars(rating),
                if (note.isNotEmpty)
                  p(
                    classes: 'ts-note',
                    attributes: context.editText(const ['subtitle']),
                    [.text(note)],
                  ),
              ]),
            ])
          else if (note.isNotEmpty)
            p(
              classes: 'ts-note',
              attributes: context.editText(const ['subtitle']),
              [.text(note)],
            ),
          if (rating != null && mapsHref != null)
            a(classes: 'ts-link', href: mapsHref, [
              .text('Ver en Google Maps'),
            ]),
        ]),
        if (content.quotes.isNotEmpty)
          div(classes: 'ts-quotes', [
            for (final quote in content.quotes) _quote(quote),
          ]),
      ]),
    ]);
  }

  Component _stars(double rating) {
    final value = rating.clamp(0.0, 5.0);
    return span(
      classes: 'ts-stars',
      attributes: {
        'role': 'img',
        'aria-label': '${websiteRatingLabel(value)} de 5 estrellas',
      },
      [
        for (var index = 0; index < 5; index++)
          span(
            classes: 'ts-star',
            attributes: {
              'style':
                  '--fill:${((value - index).clamp(0.0, 1.0) * 100).round()}%',
            },
            [
              RawText(materialIcon(_mdStar, size: 26, classes: 'ts-st-bg')),
              span(classes: 'ts-st-fg', [
                RawText(materialIcon(_mdStar, size: 26)),
              ]),
            ],
          ),
      ],
    );
  }

  Component _quote(WebsiteSectionQuote quote) {
    final theme = context.theme;
    const collection = ['testimonials', 'items'];
    Map<String, String> edit(String key) => quote.index == null
        ? const {}
        : context.editText([key], collection: collection, index: quote.index!);
    return figure(classes: 'ts-q', [
      blockquote([
        _text(
          'p',
          'ts-qt',
          quote.text,
          null,
          family: theme.bodyFont,
          weight: 500,
          fallback: 'var(--body)',
          fontSize: 26,
          lineHeight: 1.4,
          attributes: edit('comment'),
        ),
      ]),
      figcaption([
        span(
          classes: 'ts-ini',
          attributes: {'aria-hidden': 'true'},
          [.text(quote.initial)],
        ),
        span(classes: 'ts-who', [
          span(classes: 'ts-name', attributes: edit('name'), [
            .text(quote.name),
          ]),
          if (quote.meta.isNotEmpty)
            span(classes: 'ts-meta', [.text(quote.meta)]),
        ]),
      ]),
    ]);
  }
}

const _mdStar =
    'M12 17.27 18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 '
    '4.73L5.82 21z';

/// `WebsiteGalleryBlockContent`: the header and the photos in the mosaic
/// (`websiteMosaicSpans`), with the store's address in a dark tile, or in an
/// even grid.
class GallerySectionView extends StatelessComponent {
  const GallerySectionView(this.composed, this.context, {super.key});

  final ComposedBlock composed;
  final BlockRenderContext context;

  @override
  Component build(BuildContext _) {
    final data = composed.data;
    final tone = WebsiteSectionTone.of(WebsiteBlockType.gallery, data);
    // An item without a photo yet: a tinted place in the editor's draft, as
    // the Flutter canvas shows it; left out of a visitor's page.
    final images = [
      for (final (index, item) in websiteSectionItems(data, 'images'))
        if (context.draft ||
            websiteSectionText(item, const ['imageUrl']).trim().isNotEmpty)
          (index, item),
    ];
    final grid = websiteGalleryIsGrid(data);
    final address = websiteAddressLines(context.siteContact.address);
    final tile =
        !grid && data['showAddress'] != false && address.street.isNotEmpty;
    final slot = websiteGalleryAddressSlot(images.length);
    final desktop = websiteMosaicSpans(
      images.length + (tile ? 1 : 0),
      phone: false,
    );
    final phone = websiteMosaicSpans(images.length, phone: true);
    final cells = <Component>[];
    var phoneIndex = 0;
    for (var cell = 0; cell < images.length + (tile ? 1 : 0); cell++) {
      final span = grid ? null : desktop[cell];
      if (tile && cell == slot) {
        cells.add(
          div(
            classes: 'gl-cell gl-addr inv',
            attributes: {
              if (span != null)
                'style': '--dc:${span.columns};--dr:${span.rows}',
            },
            [
              RawText(
                materialIcon(mdLocationOnOutlined, size: 26, classes: 'gl-pin'),
              ),
              div([
                p(classes: 'gl-street', [.text(address.street)]),
                if (address.city.isNotEmpty)
                  p(classes: 'gl-city', [.text(address.city)]),
              ]),
            ],
          ),
        );
        continue;
      }
      final (index, item) = images[cell - (tile && cell > slot ? 1 : 0)];
      final mobile = grid ? null : phone[phoneIndex++];
      final caption = websiteSectionText(item, const ['caption']).trim();
      cells.add(
        figure(
          classes: 'gl-cell',
          attributes: {
            ...context.editImage(WebsiteImageFields.gallery, index: index),
            if (span != null && mobile != null)
              'style':
                  '--dc:${span.columns};--dr:${span.rows};'
                  '--mc:${mobile.columns};--mr:${mobile.rows}',
          },
          [
            if (websiteSectionText(item, const ['imageUrl']).trim()
                case final src when src.isNotEmpty)
              img(
                src: src,
                alt: websiteSectionText(item, const ['altText']).trim(),
                attributes: {
                  'style': 'object-position:${_focal(item)}',
                  'loading': 'lazy',
                },
              )
            else
              RawText(
                materialIcon(mdImageOutlined, size: 24, classes: 'gl-none'),
              ),
            if (caption.isNotEmpty)
              figcaption(
                attributes: context.editText(
                  const ['caption'],
                  collection: const ['images'],
                  index: index,
                ),
                [.text(caption)],
              ),
          ],
        ),
      );
    }
    return _section('gl', tone, [
      ?_header(data, context, titleClass: 'gl-t', note: false),
      if (cells.isNotEmpty) div(classes: grid ? 'gl-grid' : 'gl-mosaic', cells),
    ]);
  }
}

/// `WebsiteTeamBlockContent`: the ruled header with its note, then each
/// member with the portrait (or the person mark) in a tinted circle, the
/// name, the role and the line about them.
class TeamSectionView extends StatelessComponent {
  const TeamSectionView(this.composed, this.context, {super.key});

  final ComposedBlock composed;
  final BlockRenderContext context;

  @override
  Component build(BuildContext _) {
    final data = composed.data;
    final theme = context.theme;
    final members = websiteSectionItems(data, 'members', const [
      'team',
      'items',
    ]);
    final tone = WebsiteSectionTone.of(WebsiteBlockType.team, data);
    const collection = ['members', 'team', 'items'];
    return _section('tm', tone, [
      ?_header(
        data,
        context,
        titleClass: 'tm-t',
        noteKey: 'description',
        noteAliases: const ['subtitle'],
        ruled: true,
      ),
      if (members.isNotEmpty)
        div(
          classes: 'tm-grid',
          attributes: {
            'style': '--cd:${members.length < 3 ? members.length : 3}',
          },
          [
            for (final (index, member) in members)
              div(classes: 'tm-m', [
                _portrait(member, index),
                div(classes: 'tm-tx', [
                  _text(
                    'h3',
                    'tm-name',
                    websiteSectionText(member, const ['name']),
                    member['nameFormatting'],
                    family: theme.headingFont,
                    weight: 500,
                    fallback: 'var(--head)',
                    fontSize: 24,
                    lineHeight: 1.2,
                    attributes: context.editText(
                      const ['name'],
                      collection: collection,
                      index: index,
                    ),
                  ),
                  if (websiteSectionText(member, const [
                    'role',
                  ]).trim().isNotEmpty)
                    p(
                      classes: 'tm-role',
                      attributes: context.editText(
                        const ['role'],
                        collection: collection,
                        index: index,
                      ),
                      [
                        .text(
                          websiteSectionText(member, const ['role']).trim(),
                        ),
                      ],
                    ),
                  if (websiteSectionText(member, const [
                    'bio',
                  ]).trim().isNotEmpty)
                    _text(
                      'p',
                      'tm-bio',
                      websiteSectionText(member, const ['bio']).trim(),
                      member['bioFormatting'],
                      family: theme.bodyFont,
                      weight: 400,
                      fallback: 'var(--body)',
                      fontSize: 16,
                      lineHeight: 1.5,
                      attributes: context.editText(
                        const ['bio'],
                        collection: collection,
                        index: index,
                      ),
                    ),
                  ?_links(member),
                ]),
              ]),
          ],
        ),
    ]);
  }

  Component _portrait(Map<String, dynamic> member, int index) {
    final photo = websiteSectionText(
      member,
      WebsiteImageFields.team.keys,
    ).trim();
    return span(
      classes: 'tm-av',
      attributes: context.editImage(WebsiteImageFields.team, index: index),
      [
        if (photo.isNotEmpty)
          img(
            src: photo,
            alt: websiteSectionText(member, const ['avatarAltText']).trim(),
            attributes: {'loading': 'lazy'},
          )
        else
          RawText(materialIcon(mdPersonOutline, size: 36)),
      ],
    );
  }

  Component? _links(Map<String, dynamic> member) {
    final links = [
      for (final (key, label) in const [
        ('instagram', 'Instagram'),
        ('linkedin', 'LinkedIn'),
      ])
        if (context.publicHref(websiteSectionText(member, [key]))
            case final href?)
          a(href: href, [.text(label)]),
    ];
    return links.isEmpty ? null : div(classes: 'tm-links', links);
  }
}

/// `WebsiteFaqBlockContent`: the title, the note and the invitation to
/// write on one side, the questions on the other (one column on a phone),
/// each opening to its answer with the plus turning into a cross.
class FaqSectionView extends StatelessComponent {
  const FaqSectionView(this.composed, this.context, {super.key});

  final ComposedBlock composed;
  final BlockRenderContext context;

  @override
  Component build(BuildContext _) {
    final data = composed.data;
    final theme = context.theme;
    final items = websiteSectionItems(data, 'items');
    final tone = WebsiteSectionTone.of(WebsiteBlockType.faq, data);
    final eyebrow = websiteSectionText(data, const ['eyebrow']).trim();
    final title = websiteSectionText(data, const ['title']).trim();
    final subtitle = websiteSectionText(data, const ['subtitle']).trim();
    final contact = data['showContact'] == false ? null : _contact();
    return _section('fq', tone, [
      div(classes: 'fq-cols', [
        div(classes: 'fq-side', [
          if (eyebrow.isNotEmpty)
            p(
              classes: 'sec-eye',
              attributes: context.editText(const ['eyebrow']),
              [.text(eyebrow)],
            ),
          if (title.isNotEmpty)
            _text(
              'h2',
              'sec-t fq-t',
              title,
              data['titleFormatting'],
              family: theme.headingFont,
              weight: 500,
              fallback: 'var(--head)',
              fontSize: 48,
              lineHeight: 1.05,
              attributes: context.editText(const ['title']),
            ),
          if (subtitle.isNotEmpty)
            _text(
              'p',
              'fq-s',
              subtitle,
              data['subtitleFormatting'],
              family: theme.bodyFont,
              weight: 400,
              fallback: 'var(--body)',
              fontSize: 17,
              lineHeight: 1.55,
              attributes: context.editText(const ['subtitle']),
            ),
          ?contact,
        ]),
        if (items.isNotEmpty)
          div(classes: 'fq-list', [
            for (final (position, (index, item)) in items.indexed)
              details(classes: 'fq-it', open: position == 0, [
                summary(classes: 'fq-q', [
                  _text(
                    'span',
                    'fq-qt',
                    websiteSectionText(item, const ['question']),
                    item['questionFormatting'],
                    family: theme.bodyFont,
                    weight: 600,
                    fallback: 'var(--body)',
                    fontSize: 20,
                    lineHeight: 1.35,
                    attributes: context.editText(
                      const ['question'],
                      collection: const ['items'],
                      index: index,
                    ),
                  ),
                  RawText(materialIcon(mdAdd, size: 22, classes: 'fq-plus')),
                ]),
                div(classes: 'fq-a', [
                  _text(
                    'p',
                    'fq-at',
                    websiteSectionText(item, const ['answer']),
                    item['answerFormatting'],
                    family: theme.bodyFont,
                    weight: 400,
                    fallback: 'var(--body)',
                    fontSize: 17,
                    lineHeight: 1.55,
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

  /// «¿Otra duda? Escríbenos al … o a ….» with the store's WhatsApp (or
  /// phone) and e-mail; nothing when it has neither.
  Component? _contact() {
    final site = context.siteContact;
    final phone = site.whatsapp.trim().isNotEmpty
        ? site.whatsapp.trim()
        : site.phone.trim();
    final phoneHref = site.whatsappHref.isNotEmpty
        ? site.whatsappHref
        : 'tel:${phone.replaceAll(RegExp(r'[^\d+]'), '')}';
    final email = site.email.trim();
    if (phone.isEmpty && email.isEmpty) return null;
    return p(classes: 'fq-c', [
      .text('¿Otra duda? Escríbenos '),
      if (phone.isNotEmpty) ...[
        .text('al '),
        a(href: phoneHref, [.text(phone)]),
      ],
      if (phone.isNotEmpty && email.isNotEmpty) .text(' o '),
      if (email.isNotEmpty) ...[
        .text('a '),
        a(href: 'mailto:$email', [.text(email)]),
      ],
      .text('.'),
    ]);
  }
}

/// The brands strip (`_buildPartnersBanner`): the label in small capitals
/// and the names in a row in the heading font, on the deepest tone or over
/// the block's photo.
class PartnersStripView extends StatelessComponent {
  const PartnersStripView(this.composed, this.context, {super.key});

  final ComposedBlock composed;
  final BlockRenderContext context;

  @override
  Component build(BuildContext _) {
    final data = composed.data;
    final label = websiteSectionText(data, const ['title']).trim();
    final names = [
      for (final (index, item) in websiteSectionItems(data, 'items'))
        if (websiteSectionText(item, const ['label', 'text']).trim()
            case final name when name.isNotEmpty)
          (index, name),
    ];
    final image = websiteSectionText(data, const ['imageUrl']).trim();
    return section(classes: 'pb', [
      if (image.isNotEmpty)
        img(
          classes: 'pb-img',
          src: image,
          alt: websiteSectionText(data, const ['imageAltText']).trim(),
          attributes: {
            'style': 'object-position:${_focal(data)}',
            'loading': 'lazy',
          },
        ),
      div(classes: 'pb-in', [
        if (label.isNotEmpty)
          _text(
            'p',
            'pb-l',
            label,
            data['titleFormatting'],
            family: context.theme.bodyFont,
            weight: 600,
            fallback: 'var(--body)',
            fontSize: 12,
            lineHeight: 1.5,
            attributes: context.editText(const ['title']),
          ),
        for (final (index, name) in names)
          span(
            classes: 'pb-n',
            attributes: context.editText(
              const ['label'],
              collection: const ['items'],
              index: index,
            ),
            [.text(name)],
          ),
      ]),
    ]);
  }
}

/// `WebsiteCtaBlockContent`: the title and text over the photo (with its
/// veil, the brand's deepest tone unless the block chose a color) or the
/// dark tone, the two buttons, and how to reach the store beside them.
class CtaSectionView extends StatelessComponent {
  const CtaSectionView(this.composed, this.context, {super.key});

  final ComposedBlock composed;
  final BlockRenderContext context;

  @override
  Component build(BuildContext _) {
    final data = composed.data;
    final theme = context.theme;
    final site = context.siteContact;
    final title = websiteSectionText(data, const ['title']).trim();
    final text = websiteSectionText(data, const [
      'subtitle',
      'description',
    ]).trim();
    final image = websiteSectionText(data, const [
      'backgroundImage',
      'imageUrl',
    ]).trim();
    final actions = websiteCtaActions(
      data,
      whatsappHref: site.whatsappHref,
      mapsUrl: site.mapsUrl,
    );
    final primaryHref = actions.primary == null
        ? null
        : context.publicHref(actions.primary!.href);
    final secondaryHref = actions.secondary == null
        ? null
        : context.publicHref(actions.secondary!.href);
    // The main button is the accent unless the operator chose an outline
    // (or text) look for it in the editor.
    final primaryLook = switch (data['actionVariant']
        ?.toString()
        .trim()
        .toLowerCase()) {
      'outline' || 'text' => 'ghost',
      _ => 'acc',
    };
    final opacity = switch (data['overlayOpacity']) {
      final num value => value.toDouble(),
      final String value => double.tryParse(value) ?? 0.8,
      _ => 0.8,
    }.clamp(0.0, 1.0);
    final veil = flutterHexColor(data['overlayColor']?.toString() ?? '');
    final contacts = data['showContact'] == false
        ? const <(String, String)>[]
        : [
            if (site.whatsapp.trim().isNotEmpty)
              ('WhatsApp', site.whatsapp.trim())
            else if (site.phone.trim().isNotEmpty)
              ('Teléfono', site.phone.trim()),
            if (site.email.trim().isNotEmpty) ('Correo', site.email.trim()),
            if (site.address.trim().isNotEmpty)
              ('Dirección', site.address.trim()),
          ];
    final height = switch (data['blockHeight']) {
      final num value when value > 0 => value.toDouble(),
      _ => null,
    };
    return section(
      classes: ['ct', if (height != null) 'fixed'].join(' '),
      attributes: {
        if (height != null)
          'style':
              'height:${height == height.roundToDouble() ? height.round() : height}px',
      },
      [
        if (image.isNotEmpty) ...[
          img(
            classes: 'ct-img',
            src: image,
            alt: websiteSectionText(data, const [
              'backgroundImageAltText',
              'imageAltText',
            ]).trim(),
            attributes: {
              'style': 'object-position:${_focal(data)}',
              'loading': 'lazy',
            },
          ),
          if (opacity > 0)
            div(
              classes: 'ct-ov',
              attributes: {
                'style': veil == null
                    ? 'opacity:${opacity == opacity.roundToDouble() ? opacity.round() : opacity}'
                    : 'background:${veil.withAlpha(opacity).css};opacity:1',
              },
              const [],
            ),
        ],
        div(classes: 'ct-in', [
          div(classes: 'ct-main', [
            _text(
              'h2',
              'ct-t',
              title.isEmpty ? '¿Necesitas ayuda?' : title,
              data['titleFormatting'],
              family: theme.headingFont,
              weight: 500,
              fallback: 'var(--head)',
              fontSize: 72,
              lineHeight: 1,
              attributes: context.editText(const ['title']),
            ),
            if (text.isNotEmpty)
              _text(
                'p',
                'ct-s',
                text,
                data['subtitleFormatting'] ?? data['descriptionFormatting'],
                family: theme.bodyFont,
                weight: 400,
                fallback: 'var(--body)',
                fontSize: 19,
                lineHeight: 1.5,
                attributes: context.editText(const ['subtitle', 'description']),
              ),
            if (primaryHref != null || secondaryHref != null)
              div(classes: 'ct-btns', [
                if (actions.primary case final primary?
                    when primaryHref != null)
                  a(
                    classes: 'sec-btn $primaryLook',
                    href: primaryHref,
                    attributes: context.editButton(WebsiteButtonFields.cta),
                    [
                      if (primary.whatsapp)
                        RawText(
                          materialIcon(mdChatBubbleOutlineRounded, size: 20),
                        ),
                      span([.text(primary.label)]),
                    ],
                  ),
                if (actions.secondary case final secondary?
                    when secondaryHref != null)
                  a(
                    classes: 'sec-btn ghost',
                    href: secondaryHref,
                    attributes: context.editButton(
                      WebsiteButtonFields.ctaSecondary,
                    ),
                    [
                      span([.text(secondary.label)]),
                    ],
                  ),
              ]),
          ]),
          if (contacts.isNotEmpty) ...[
            dl(classes: 'ct-dl', [
              for (final (label, value) in contacts)
                div([
                  dt([.text(label)]),
                  dd([.text(value)]),
                ]),
            ]),
            p(classes: 'ct-line', [
              for (final line in [
                contacts
                    .where((entry) => entry.$1 != 'Dirección')
                    .map((entry) => entry.$2)
                    .join(' · '),
                ...contacts
                    .where((entry) => entry.$1 == 'Dirección')
                    .map((entry) => entry.$2),
              ])
                if (line.isNotEmpty) span([.text(line)]),
            ]),
          ],
        ]),
      ],
    );
  }
}

/// The section blocks' stylesheet: each tone's colors from the theme
/// (`WebsiteSectionPalette`) and the rules every section shares, sized by
/// the block's width.
String sectionBlocksCss(WebsiteThemeRoles theme) {
  WebsiteSectionPalette palette(WebsiteSectionTone tone) =>
      WebsiteSectionPalette.resolve(
        tone: tone,
        primary: theme.primary,
        accent: theme.accent,
        background: theme.background,
        onSurface: theme.onSurface,
      );
  final tones = WebsiteSectionTones.derive(
    primary: theme.primary,
    accent: theme.accent,
    background: theme.background,
  );
  String vars(WebsiteSectionPalette p) =>
      '--s-bg:${p.surface.css};--s-ink:${p.ink.css};--s-mut:${p.muted.css};'
      '--s-soft:${WebsiteRgba.lerp(p.ink, p.surface, 0.15).css};'
      '--s-rule:${p.rule.css};--s-strong:${p.strongRule.css};'
      '--s-eye:${p.eyebrow.css};--s-mark:${p.mark.css};--s-tint:${p.tint.css};'
      '--s-card:${p.card.css};--s-crule:${p.cardRule.css};'
      '--s-acc:${p.accent.css};--s-onacc:${p.onAccent.css}';
  final light = palette(WebsiteSectionTone.light);
  final band = palette(WebsiteSectionTone.band);
  final dark = palette(WebsiteSectionTone.dark);
  final onDeeper = WebsiteRgba.readableOn(tones.deeper);
  // A family Flutter draws only at its regular instance (Oswald's variable
  // file) is drawn at 400 here too, whatever weight the design names.
  final head = storefrontHeadingWeight(theme.headingFont, 500);
  return '''
/* Sections: a band of the page on its tone, the content in a centered
   column. Phone under 600, tablet to 1023, desktop from 1024, measured on
   the block (WebsiteSectionWidth). */
.sec{${vars(light)};background:var(--s-bg);color:var(--s-ink);padding:112px 32px;font-family:var(--body)}
.sec[data-tone=band]{${vars(band)}}
.sec[data-tone=dark],.sec .inv{${vars(dark)};color-scheme:dark}
.sec[data-tone=dark] .inv{--s-bg:${dark.card.css}}
.sec-in{max-width:1136px;margin:0 auto}
:where(.sec) :where(p,h2,h3,figure,blockquote,dl,dd,ul){margin:0}
.sec-hd{display:flex;flex-wrap:wrap;justify-content:space-between;align-items:flex-end;gap:24px 32px}
.sec-hd.ruled{padding-bottom:36px;border-bottom:2px solid var(--s-strong)}
.sec-hd-t{min-width:0;max-width:760px}
.sec-eye{margin:0 0 14px;font:600 13px/1 var(--body);letter-spacing:.18em;text-transform:uppercase;color:var(--s-eye)}
.sec-t{font:$head 48px/${_lh(48, 1.05)} var(--head);text-transform:uppercase;color:var(--s-ink);overflow-wrap:break-word}
.sec-note{max-width:400px;font:400 17px/${_lh(17, 1.5)} var(--body);color:var(--s-mut)}
.sec-btn{display:inline-flex;align-items:center;justify-content:center;gap:10px;min-height:48px;padding:0 24px;border-radius:6px;font:600 15px/1.2 var(--body);letter-spacing:.06em;text-transform:uppercase;text-decoration:none;text-align:center;transition:background-color .15s,border-color .15s,color .15s}
.sec-btn:focus-visible{outline:2px solid var(--s-mark);outline-offset:3px}
.sec-btn.line{border:1.5px solid var(--s-ink);color:var(--s-ink)}
.sec-btn.line:hover{background:var(--s-ink);color:var(--s-bg)}
.sec-btn.acc{background:var(--s-acc);color:var(--s-onacc);font-weight:700}
.sec-btn.acc:hover{background:color-mix(in srgb,var(--s-acc) 88%,#000)}
.sec-btn.ghost{border:1.5px solid rgb(255 255 255 / .8);color:#fff}
.sec-btn.ghost:hover{background:rgb(255 255 255 / .1)}
.sec a:not(.sec-btn){color:var(--s-mark)}
@container (min-width:600px) and (max-width:1023.98px){
.sec{padding:88px 32px}
.sec-t{font-size:42px;line-height:${_lh(42, 1.05)}}
}
@container (max-width:599.98px){
.sec{padding:64px 20px}
.sec-hd{display:block}
.sec-hd.ruled{padding-bottom:22px}
.sec-eye{margin-bottom:12px;font-size:12px}
.sec-t{font-size:36px;line-height:${_lh(36, 1.05)}}
.sec-note{max-width:none;margin-top:14px;font-size:16px;line-height:${_lh(16, 1.5)}}
}

/* Stats: the dark band, the figures under a rule, a line between them. */
.sec.st{padding:104px 32px 96px}
.st-t{font-size:56px;line-height:${_lh(56, 1.04)};max-width:680px}
.sec.st .sec-hd-t{max-width:680px}
.sec.st .sec-eye{margin-bottom:18px}
.st-grid{display:grid;grid-template-columns:repeat(var(--cd),minmax(0,1fr));column-gap:28px;margin-top:64px;border-top:1px solid var(--s-rule)}
.st-m{padding:30px 28px 0 0;border-right:1px solid var(--s-rule);min-width:0}
.st-m:nth-child(4n),.st-m:last-child{border-right:0}
.st-v{display:flex;align-items:baseline;gap:8px;min-width:0}
.st-num{font:$head 76px/76px var(--head);font-variant-numeric:tabular-nums;color:var(--s-ink);overflow-wrap:anywhere}
.st-suf{font:$head 26px/26px var(--head);color:var(--s-eye)}
.st-l{max-width:220px;margin-top:16px;font:500 16px/${_lh(16, 1.45)} var(--body);color:var(--s-mut)}
@container (min-width:600px) and (max-width:1023.98px){
.sec.st{padding:88px 32px 80px}
.st-t{font-size:48px;line-height:${_lh(48, 1.04)}}
.st-grid{grid-template-columns:repeat(var(--cm),minmax(0,1fr));margin-top:48px}
.st-num{font-size:60px;line-height:60px}
.st-suf{font-size:22px;line-height:22px}
}
@container (max-width:1023.98px){
.st-grid{grid-template-columns:repeat(var(--cm),minmax(0,1fr));column-gap:0}
.st-m,.st-m:nth-child(4n),.st-m:last-child{padding:22px 12px 20px 0;border-right:0;border-bottom:1px solid var(--s-rule)}
}
@container (max-width:599.98px){
.sec.st{padding:64px 20px 56px}
.st-t{font-size:38px;line-height:${_lh(38, 1.05)}}
.st-grid{margin-top:36px}
.st-v{gap:6px}
.st-num{font-size:48px;line-height:48px}
.st-suf{font-size:18px;line-height:18px}
.st-l{margin-top:10px;font-size:14px;line-height:${_lh(14, 1.4)}}
}

/* Services: numbered rows with the price to the right, the photo beside. */
.sv-body{display:flex;gap:56px;margin-top:8px}
.sv-list{flex:1 1 0;min-width:0}
.sv-row{display:grid;grid-template-columns:44px minmax(0,1fr) auto;column-gap:20px;align-items:baseline;padding:22px 0;border-bottom:1px solid var(--s-rule)}
.sv-n{font:$head 15px/1 var(--head);letter-spacing:.06em;color:var(--s-mut);font-variant-numeric:tabular-nums}
.sv-name{font:600 19px/${_lh(19, 1.3)} var(--body);color:var(--s-ink)}
.sv-d{margin-top:4px;font:400 15px/${_lh(15, 1.45)} var(--body);color:var(--s-mut)}
.sv-p{font:$head 26px/26px var(--head);font-variant-numeric:tabular-nums;white-space:nowrap;color:var(--s-ink)}
.sv-fig{flex:0 0 420px;margin-top:30px;align-self:flex-start}
.sv-fig img{display:block;width:100%;aspect-ratio:4/5;object-fit:cover;border-radius:6px}
.sv-fig figcaption{display:flex;justify-content:space-between;gap:16px;margin-top:14px;font:400 14px/${_lh(14, 1.4)} var(--body);color:var(--s-mut)}
@container (max-width:1023.98px){.sv-fig{display:none}}
@container (max-width:599.98px){
.sv-row{grid-template-columns:minmax(0,1fr) auto;column-gap:16px;padding:18px 0}
.sv-n{display:none}
.sv-name{font-size:17px;line-height:${_lh(17, 1.3)}}
.sv-d{font-size:14px;line-height:${_lh(14, 1.45)}}
.sv-p{font-size:22px;line-height:22px}
}

/* Plans: side by side in one card, or stacked cards. */
.pr-plans{display:flex;margin-top:48px;background:var(--s-card);border:1px solid var(--s-crule);border-radius:8px;overflow:hidden}
.pr-plan{flex:1 1 0;min-width:0;display:flex;flex-direction:column;padding:40px 36px;background:var(--s-card);color:var(--s-ink);border-right:1px solid var(--s-crule)}
.pr-plan:last-child{border-right:0}
.pr-plan.inv{background:var(--s-bg)}
.pr-head{display:flex;justify-content:space-between;align-items:baseline;gap:12px}
.pr-name{min-width:0;font:$head 30px/${_lh(30, 1.2)} var(--head);text-transform:uppercase;color:var(--s-ink)}
.pr-tag{font:600 12px/1.4 var(--body);letter-spacing:.14em;text-transform:uppercase;color:var(--s-mut);white-space:nowrap}
.pr-badge{padding:6px 10px;border-radius:4px;background:var(--s-acc);color:var(--s-onacc);font:700 12px/1.2 var(--body);letter-spacing:.12em;text-transform:uppercase;white-space:nowrap}
.pr-badge.top,.pr-price.small{display:none}
.pr-price{margin-top:28px;font:$head 60px/60px var(--head);font-variant-numeric:tabular-nums;color:var(--s-ink)}
.pr-note{margin-top:10px;font:400 15px/${_lh(15, 1.45)} var(--body);color:var(--s-mut)}
.pr-inc{margin:28px 0 14px;padding-top:22px;border-top:1px solid var(--s-rule);font:600 12px/1.4 var(--body);letter-spacing:.14em;text-transform:uppercase;color:var(--s-mut)}
.pr-note+.pr-inc{margin-top:22px}
.pr-feats{display:flex;flex-direction:column;gap:12px;padding:0;list-style:none}
.pr-feats li{display:flex;gap:12px;font:400 16px/${_lh(16, 1.45)} var(--body);color:var(--s-ink)}
.pr-ck{flex:none;margin-top:1px;color:var(--s-mark)}
.pr-cta{margin-top:auto;padding-top:36px}
.pr-cta .sec-btn{display:flex;width:100%;box-sizing:border-box}
${_plansStackRules(head)}

/* Testimonials: the score on one side, the quotes on the other. */
.ts-cols{display:flex;gap:72px}
.ts-score{flex:0 0 340px;min-width:0}
.sec.ts .sec-eye{margin-bottom:18px}
.ts-t{margin-bottom:16px}
.ts-num{display:block;font:$head 148px/${_lh(148, 0.9)} var(--head);color:var(--s-mark);font-variant-numeric:tabular-nums}
.ts-stars{display:flex;gap:4px;margin-top:22px;color:var(--s-acc)}
.ts-star{position:relative;display:inline-block;width:26px;height:26px}
.ts-star svg{display:block}
.ts-st-bg{color:var(--s-rule)}
.ts-st-fg{position:absolute;inset:0;width:var(--fill);overflow:hidden}
.ts-note{margin-top:14px;font:400 17px/${_lh(17, 1.5)} var(--body);color:var(--s-mut)}
.ts-link{display:inline-flex;align-items:center;min-height:44px;margin-top:18px;font:600 15px/1.2 var(--body);letter-spacing:.04em;text-transform:uppercase;text-decoration:none;border-bottom:1.5px solid currentColor;box-sizing:border-box}
.ts-quotes{flex:1 1 0;min-width:0}
.ts-q{padding:32px 0;border-top:1px solid var(--s-rule)}
.ts-qt{font:500 26px/${_lh(26, 1.4)} var(--body);letter-spacing:-.005em;color:var(--s-ink)}
.ts-qt::before{content:"\\201C"}.ts-qt::after{content:"\\201D"}
.ts-q figcaption{display:flex;align-items:center;gap:14px;margin-top:20px}
.ts-ini{flex:none;display:grid;place-items:center;width:40px;height:40px;border-radius:50%;background:var(--s-tint);font:$head 17px/1 var(--head);color:var(--s-mark)}
.ts-who{display:flex;flex-wrap:wrap;align-items:baseline;gap:4px 14px}
.ts-name{font:600 16px/1.4 var(--body);color:var(--s-ink)}
.ts-meta{font:400 15px/1.4 var(--body);color:var(--s-mut)}
@container (max-width:1023.98px){
.ts-cols{display:block}
.ts-rate{display:flex;align-items:flex-end;gap:16px}
.ts-rate-s{padding-bottom:6px}
.ts-num{font-size:96px;line-height:${_lh(96, 0.9)}}
.ts-stars{gap:3px;margin-top:0}
.ts-star,.ts-star svg{width:20px;height:20px}
.ts-note{margin-top:8px;font-size:15px;line-height:${_lh(15, 1.5)}}
.ts-quotes{margin-top:12px}
.ts-q{margin-top:28px;padding:24px 0 0}
.ts-qt{font-size:20px;line-height:${_lh(20, 1.4)}}
.ts-q figcaption{gap:12px;margin-top:16px}
.ts-ini{width:36px;height:36px;font-size:15px}
.ts-who{display:block}
.ts-name,.ts-meta{display:block}
.ts-name{font-size:15px}
.ts-meta{font-size:14px}
}
@container (max-width:599.98px){.ts-link{display:none}}

/* Gallery: the mosaic (or an even grid), captions on the photos, the
   address in a dark tile. */
.sec.gl .sec-hd{margin-bottom:40px}
.gl-mosaic{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));grid-auto-rows:230px;gap:12px}
.gl-mosaic .gl-cell{grid-column:span var(--dc,1);grid-row:span var(--dr,1)}
.gl-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px}
.gl-grid .gl-cell{aspect-ratio:4/3}
.gl-cell{position:relative;min-width:0;overflow:hidden;border-radius:6px;background:var(--s-tint)}
.gl-cell img{display:block;width:100%;height:100%;object-fit:cover}
.gl-none{position:absolute;inset:0;margin:auto;color:var(--s-mark)}
.gl-cell figcaption{position:absolute;left:14px;bottom:14px;max-width:calc(100% - 28px);padding:7px 11px;border-radius:4px;background:${tones.deep.withAlpha(0.84).css};font:600 12px/1.3 var(--body);letter-spacing:.12em;text-transform:uppercase;color:#fff;box-sizing:border-box}
.gl-addr{display:flex;flex-direction:column;justify-content:space-between;padding:22px;background:var(--s-bg);color:var(--s-ink)}
.gl-pin{color:var(--s-eye)}
.gl-street{font:$head 24px/${_lh(24, 1.15)} var(--head);text-transform:uppercase;color:var(--s-ink)}
.gl-city{margin-top:6px;font:400 15px/1.4 var(--body);color:var(--s-mut)}
@container (min-width:600px) and (max-width:1023.98px){
.gl-mosaic{grid-auto-rows:170px;gap:10px}
.gl-grid{grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}
.gl-street{font-size:20px;line-height:${_lh(20, 1.15)}}
}
@container (max-width:599.98px){
.sec.gl .sec-hd{margin-bottom:24px}
.gl-mosaic{grid-template-columns:repeat(2,minmax(0,1fr));grid-auto-rows:150px;gap:8px}
.gl-mosaic .gl-cell{grid-column:span var(--mc,1);grid-row:span var(--mr,1)}
.gl-grid{grid-template-columns:repeat(2,minmax(0,1fr));gap:8px}
.gl-cell figcaption,.gl-addr{display:none}
}

/* Team: the ruled header, then each member with the portrait. */
.tm-grid{display:grid;grid-template-columns:repeat(var(--cd),minmax(0,1fr));column-gap:28px}
.tm-m{display:flex;gap:20px;align-items:flex-start;padding:32px 0;min-width:0}
.tm-av{flex:none;display:grid;place-items:center;width:88px;height:88px;border-radius:50%;overflow:hidden;background:var(--s-tint);color:var(--s-mark)}
.tm-av img{width:100%;height:100%;object-fit:cover}
.tm-tx{min-width:0}
.tm-name{font:$head 24px/${_lh(24, 1.2)} var(--head);text-transform:uppercase;color:var(--s-ink)}
.tm-role{margin-top:4px;font:600 13px/1.4 var(--body);letter-spacing:.12em;text-transform:uppercase;color:var(--s-eye)}
.tm-bio{margin-top:12px;font:400 16px/${_lh(16, 1.5)} var(--body);color:var(--s-mut)}
.tm-links{display:flex;gap:16px;margin-top:10px}
.tm-links a{font:600 13px/1.4 var(--body);letter-spacing:.06em;text-transform:uppercase;text-decoration:none}
@container (min-width:600px) and (max-width:1023.98px){.tm-grid{grid-template-columns:repeat(2,minmax(0,1fr))}}
@container (max-width:599.98px){
.tm-grid{display:block}
.tm-m{gap:16px;padding:22px 0;border-bottom:1px solid var(--s-rule)}
.tm-av{width:64px;height:64px}
.tm-av svg{width:28px;height:28px}
.tm-name{font-size:20px;line-height:${_lh(20, 1.2)}}
.tm-role{margin-top:3px;font-size:12px}
.tm-bio{margin-top:8px;font-size:15px;line-height:${_lh(15, 1.5)}}
}

/* Questions: the title on one side, the questions on the other. */
.fq-cols{display:flex;gap:72px}
.fq-side{flex:0 0 360px;min-width:0}
.fq-s,.fq-c{margin-top:22px;font:400 17px/${_lh(17, 1.55)} var(--body);color:var(--s-mut)}
.fq-c a{font-weight:600}
.fq-list{flex:1 1 0;min-width:0;border-top:2px solid var(--s-strong)}
.fq-it{border-bottom:1px solid var(--s-rule)}
.fq-q{display:flex;justify-content:space-between;align-items:center;gap:24px;min-height:76px;list-style:none;cursor:pointer}
.fq-q::-webkit-details-marker{display:none}
.fq-q:focus-visible{outline:2px solid var(--s-mark);outline-offset:2px}
.fq-qt{flex:1;min-width:0;padding-block:12px;font:600 20px/${_lh(20, 1.35)} var(--body);color:var(--s-ink)}
.fq-plus{flex:none;color:var(--s-mark);transition:transform .2s}
.fq-it[open] .fq-plus{transform:rotate(45deg)}
.fq-a{padding:0 56px 26px 0}
.fq-at{font:400 17px/${_lh(17, 1.55)} var(--body);color:var(--s-soft)}
.fq-it::details-content{block-size:0;overflow:hidden;transition:block-size .2s,content-visibility .2s allow-discrete}
.fq-it[open]::details-content{block-size:auto}
@container (max-width:1023.98px){
.fq-cols{display:block}
.fq-t{margin-bottom:0}
.fq-list{margin-top:24px}
}
@container (max-width:599.98px){
.fq-s,.fq-c{font-size:16px;line-height:${_lh(16, 1.55)}}
.fq-q{gap:16px;min-height:64px}
.fq-qt{font-size:17px;line-height:${_lh(17, 1.35)}}
.fq-plus{width:20px;height:20px}
.fq-a{padding:0 28px 20px 0}
.fq-at{font-size:16px;line-height:${_lh(16, 1.55)}}
}
@media (prefers-reduced-motion:reduce){.fq-plus,.fq-it::details-content{transition:none}}

/* Brands strip: the deepest tone, the names in a row. */
.pb{position:relative;overflow:hidden;padding:44px 32px;background:${tones.deeper.css};color:${onDeeper.css}}
.pb-img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;opacity:.24}
.pb-in{position:relative;max-width:1136px;margin:0 auto;display:flex;flex-wrap:wrap;align-items:center;gap:20px 48px}
.pb-l{margin:0;font:600 12px/1.5 var(--body);letter-spacing:.18em;text-transform:uppercase;color:${onDeeper.withAlpha(0.6).css}}
.pb-n{font:$head 24px/1.3 var(--head);letter-spacing:.06em;text-transform:uppercase;color:${onDeeper.withAlpha(0.86).css}}
@container (max-width:599.98px){
.pb{padding:32px 20px}
.pb-in{gap:10px 24px}
.pb-l{flex:0 0 100%;margin-bottom:6px;font-size:11px}
.pb-n{font-size:19px}
}

/* Call to action: the title over the photo and its veil, or the dark tone. */
.ct{position:relative;overflow:hidden;background:${tones.deep.css};color:#fff;font-family:var(--body)}
.ct.fixed{display:flex;flex-direction:column;justify-content:safe center}
.ct-img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
.ct-ov{position:absolute;inset:0;background:${tones.deeper.css};opacity:.8;pointer-events:none}
.ct-in{position:relative;box-sizing:border-box;width:100%;max-width:1200px;margin:0 auto;padding:120px 32px;display:flex;justify-content:space-between;align-items:flex-end;gap:48px}
.ct.fixed .ct-in{padding-block:0}
.ct-main{flex:1 1 0;min-width:0}
.ct-t{margin:0;font:$head 72px/72px var(--head);text-transform:uppercase;color:#fff;overflow-wrap:break-word}
.ct-s{margin:24px 0 0;max-width:520px;font:400 19px/${_lh(19, 1.5)} var(--body);color:rgb(255 255 255 / .8)}
.ct-btns{display:flex;flex-wrap:wrap;gap:14px;margin-top:36px}
.ct-btns .sec-btn{min-height:52px;padding:0 26px}
.ct-btns .sec-btn.acc{--s-acc:${theme.accent.css};--s-onacc:${WebsiteRgba.readableOn(theme.accent).css}}
.ct-btns .sec-btn:focus-visible{outline-color:#fff}
.ct-dl{flex:0 0 340px;margin:0;display:grid;gap:18px;padding-top:24px;border-top:1px solid rgb(255 255 255 / .24)}
.ct-dl dt{font:600 12px/1.4 var(--body);letter-spacing:.16em;text-transform:uppercase;color:rgb(255 255 255 / .6)}
.ct-dl dd{margin:6px 0 0;font:400 18px/1.4 var(--body);font-variant-numeric:tabular-nums;color:#fff;overflow-wrap:anywhere}
.ct-line{display:none;margin:28px 0 0;padding-top:20px;border-top:1px solid rgb(255 255 255 / .24);font:400 15px/${_lh(15, 1.6)} var(--body);color:rgb(255 255 255 / .8)}
.ct-line span{display:block}
@container (min-width:600px) and (max-width:1023.98px){
.ct-in{display:block;padding:96px 32px}
.ct-t{font-size:56px;line-height:56px}
.ct-dl{margin-top:40px;grid-template-columns:repeat(3,minmax(0,1fr));gap:24px}
}
@container (max-width:599.98px){
.ct-in{display:block;padding:72px 20px 64px}
.ct-t{font-size:46px;line-height:46px}
.ct-s{margin-top:18px;font-size:17px;line-height:${_lh(17, 1.5)}}
.ct-btns{flex-direction:column;gap:12px;margin-top:28px}
.ct-dl{display:none}
.ct-line{display:block}
}
@media (prefers-reduced-motion:reduce){.sec-btn{transition:none}}
''';
}

/// The plans side by side while each has 260 (`websitePlansSideBySide`),
/// otherwise stacked: one rule per count of plans, at the block width where
/// its column falls under that (the column less the section's sides).
String _plansStackRules(String head) {
  final rules = StringBuffer();
  for (var count = 1; count <= 8; count++) {
    final narrowSides = 260.0 * count + 40;
    final wideSides = 260.0 * count + 64;
    final below = narrowSides < WebsiteSectionWidth.tabletFrom
        ? narrowSides
        : wideSides;
    final query = below > 1136 + 64
        ? ''
        : '@container (max-width:${(below - 0.02).toStringAsFixed(2)}px)';
    final selector = '.sec.pr[data-n="$count"]';
    final body =
        '$selector .pr-plans{flex-direction:column;gap:12px;background:none;border:0;border-radius:0;overflow:visible}'
        '$selector .pr-plan{padding:26px 22px;border:1px solid var(--s-crule);border-radius:8px}'
        '$selector .pr-plan.inv{border-color:transparent}'
        '$selector .pr-badge.top{display:inline-block;align-self:flex-start;margin-bottom:14px;padding:5px 9px;font-size:11px}'
        '$selector .pr-badge.side,$selector .pr-tag,$selector p.pr-price,$selector .pr-inc{display:none}'
        '$selector .pr-price.small{display:inline;margin:0;font:$head 32px/1.2 var(--head);white-space:nowrap}'
        '$selector .pr-name{font-size:24px;line-height:${_lh(24, 1.2)}}'
        '$selector .pr-note{margin-top:6px;font-size:14px}'
        '$selector .pr-feats{gap:10px;margin-top:16px}'
        '$selector .pr-feats li{gap:10px;font-size:15px;line-height:${_lh(15, 1.45)}}'
        '$selector .pr-ck{width:18px;height:18px;margin-top:2px}'
        '$selector .pr-plan:not(.inv) .pr-cta{display:none}'
        '$selector .pr-cta{padding-top:22px}';
    rules.writeln(query.isEmpty ? body : '$query{$body}');
  }
  return rules.toString();
}

String _lh(double fontSize, double height) =>
    '${(fontSize * height).round()}px';
