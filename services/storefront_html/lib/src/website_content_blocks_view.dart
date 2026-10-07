import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';

import 'block_composition.dart';
import 'material_icons.dart';
import 'website_block_icons.dart';
import 'website_blocks_view.dart';

/// The editor's content blocks as Flutter's shared contents draw them: the
/// features (`WebsiteFeaturesBlockContent`) and «about us»
/// (`WebsiteAboutBlockContent`). The questions and the call to action are
/// sections now (`website_section_blocks_view.dart`).

Map<String, dynamic> _map(Object? raw) =>
    raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};

/// The items of a block's list (its [key], or the first alias it has),
/// each with its place in the stored list: an entry that is not an item is
/// skipped, and the editor addresses an item by where it is stored.
List<(int, Map<String, dynamic>)> _items(
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
      for (final (index, item) in raw.indexed)
        if (item is Map) (index, Map<String, dynamic>.from(item)),
  ];
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
            for (final (index, item) in features)
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
