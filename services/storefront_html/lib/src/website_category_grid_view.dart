import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import 'block_composition.dart';
import 'css_values.dart';
import 'storefront_shell.dart';
import 'material_icons.dart';
import 'website_blocks_view.dart';

/// The cards of a category grid the author drew by hand.
List<Map<String, dynamic>> categoryGridCards(Map<String, dynamic> data) => [
  if (data['categories'] case final List<Object?> cards)
    for (final card in cards)
      if (card is Map) Map<String, dynamic>.from(card),
];

/// The cards the grid shows, as `_AutoCategoryGrid._loadCategories`: the
/// author's cards whose category is published, when one of them has a
/// photo; otherwise every published category of the catalog by its order
/// and name, the first two large, each to its products.
List<Map<String, dynamic>> categoryGridShownCards(
  Map<String, dynamic> data,
  StorefrontShell shell,
) {
  final manual = categoryGridCards(data);
  if (manual.any(
    (card) => (card['imageUrl']?.toString().trim() ?? '').isNotEmpty,
  )) {
    return [
      for (final card in manual)
        if (shell.publication.allowsHref(categoryCardHref(card))) card,
    ];
  }
  int order(Map<String, dynamic> row) =>
      (row['sort_order'] as num?)?.toInt() ?? 0;
  final published =
      [
        for (final row in shell.categories.values)
          if (shell.publication.isPublished(row['id']?.toString())) row,
      ]..sort((one, other) {
        final byOrder = order(one).compareTo(order(other));
        return byOrder != 0
            ? byOrder
            : (one['name'] ?? '').toString().compareTo(
                (other['name'] ?? '').toString(),
              );
      });
  return [
    for (final (index, row) in published.indexed)
      {
        'title': (row['name'] ?? '').toString(),
        'subtitle': (row['description'] ?? '').toString(),
        'imageUrl': (row['image_url'] ?? '').toString(),
        'ctaText': 'Ver productos',
        'ctaLink': '/productos?category=${row['id']}',
        'size': index < 2 ? 'large' : 'medium',
      },
  ];
}

/// `_CategoryCard.resolveHref`: `ctaLink` or `link`, the specific one when
/// one of them is the whole catalog, `link` when both are specific.
String categoryCardHref(Map<String, dynamic> card) {
  final cta = (card['ctaLink'] ?? '').toString().trim();
  final link = (card['link'] ?? '').toString().trim();
  if (cta.isEmpty && link.isEmpty) return '/productos';
  if (cta.isEmpty) return link;
  if (link.isEmpty) return cta;
  if (cta == link) return link;
  bool generic(String href) =>
      href == '/productos' || href == '/tienda/productos';
  if (generic(link) && !generic(cta)) return cta;
  if (generic(cta) && !generic(link)) return link;
  return link;
}

/// `_AutoCategoryGrid` ([categoryGridShownCards]): the large ones two to a row
/// (380 px) and the rest four to a row (220 px) with 4 px between them, edge
/// to edge; on a window under 600 px the large ones stacked (300 px) and the
/// rest two to a row. A desktop shows the first two large and first four
/// others, as Flutter.
class CategoryGridView extends StatelessComponent {
  const CategoryGridView(this.composed, this.context, {super.key});

  final ComposedBlock composed;
  final BlockRenderContext context;

  @override
  Component build(BuildContext _) {
    final data = composed.data;
    final cards = categoryGridShownCards(data, context.shell);
    if (cards.isEmpty) return div(const []);
    final large = [
      for (final card in cards)
        if (card['size'] == 'large') card,
    ];
    final others = [
      for (final card in cards)
        if (card['size'] != 'large') card,
    ];
    final title = (data['title'] ?? '').toString().trim();
    final subtitle = (data['subtitle'] ?? '').toString().trim();
    final shownLarge = large.take(2).length;
    final shownOthers = others.take(4).length;
    return section(classes: 'cat-blk', [
      if (title.isNotEmpty) ...[
        h2(
          classes: 'cat-t',
          attributes: {
            ...context.editText(const ['title']),
            ...formattedStyle(
              data['titleFormatting'],
              family: context.theme.headingFont,
              weight: 700,
              fallback: 'var(--head)',
              fontSize: 32,
              lineHeight: 40 / 32,
            ),
          },
          [.text(title)],
        ),
        if (subtitle.isNotEmpty) p(classes: 'cat-s', [.text(subtitle)]),
      ],
      div(
        classes: [
          'cat-grid',
          if (large.isEmpty) 'no-lg',
          if (others.isEmpty) 'only-lg',
        ].join(' '),
        [
          for (var index = 0; index < large.length; index++)
            _card(
              large[index],
              large: true,
              columns: 12 ~/ shownLarge,
              desktop: index < 2,
              firstOthers: false,
            ),
          for (var index = 0; index < others.length; index++)
            _card(
              others[index],
              large: false,
              columns: 12 ~/ shownOthers,
              desktop: index < 4,
              firstOthers: large.isNotEmpty && index < 2,
            ),
        ],
      ),
    ]);
  }

  Component _card(
    Map<String, dynamic> card, {
    required bool large,
    required int columns,
    required bool desktop,
    required bool firstOthers,
  }) {
    final title = (card['title'] ?? 'Categoría').toString();
    final subtitle = (card['subtitle'] ?? '').toString();
    final cta = (card['ctaText'] ?? 'Ver colección').toString();
    final href = context.publicHref(categoryCardHref(card)) ?? '/productos';
    final image = card['imageUrl']?.toString().trim() ?? '';
    final contain = image.isNotEmpty && card['imageFit'] == 'contain';
    final alt = (card['altText'] ?? '').toString().trim();
    final fx = (numberValue(card['focalPointX']) ?? 0.5).clamp(0.0, 1.0);
    final fy = (numberValue(card['focalPointY']) ?? 0.5).clamp(0.0, 1.0);
    final classes = [
      'cat',
      large ? 'lg' : 'sm',
      contain ? 'light' : 'dark',
      if (!desktop) 'xd',
      if (firstOthers) 'fo',
    ].join(' ');
    final style = '--span:$columns';
    if (contain) {
      return a(
        classes: classes,
        href: href,
        attributes: {'style': style},
        [
          span(classes: 'cat-shot', [
            img(
              src: image,
              alt: alt,
              loading: MediaLoading.lazy,
              attributes: {'decoding': 'async'},
            ),
          ]),
          span(classes: 'cat-info', [
            span(classes: 'cat-name', [.text(title.toUpperCase())]),
            if (subtitle.isNotEmpty)
              span(classes: 'cat-sub', [.text(subtitle)]),
            span(classes: 'cat-cta', [
              span([.text(cta.toUpperCase())]),
              RawText(materialIcon(mdArrowForward, size: 14)),
            ]),
          ]),
        ],
      );
    }
    return a(
      classes: classes,
      href: href,
      attributes: {'style': style},
      [
        if (image.isNotEmpty)
          img(
            classes: 'cat-bg',
            src: image,
            alt: '',
            loading: MediaLoading.lazy,
            attributes: {
              'decoding': 'async',
              'style':
                  'object-position:${cssNum(fx * 100)}% ${cssNum(fy * 100)}%',
            },
          ),
        span(classes: 'cat-in', [
          span(classes: 'cat-name', [.text(title.toUpperCase())]),
          if (subtitle.isNotEmpty) span(classes: 'cat-sub', [.text(subtitle)]),
          span(classes: 'cat-btn', [.text(cta.toUpperCase())]),
        ]),
      ],
    );
  }
}
