import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/public_store/models/public_policy_content.dart';

import 'block_composition.dart';
import 'material_icons.dart';
import 'policy_page_model.dart';
import 'site_layout.dart';
import 'website_blocks_view.dart';

/// An information page, laid out like Flutter's `StaticPolicyPage`: the
/// icon, title, summary and the other information pages beside the blocks
/// from 816 px up (a frame of 768), above them below. A block with words to
/// read is drawn as the page's sections (`_PolicyContent`); the rest, such
/// as the hero, by its own renderer.
Component policyPageDocument(PolicyPageModel model) {
  final render = BlockRenderContext(
    shell: model.page.shell,
    theme: model.theme,
    storeUrl: model.page.storeUrl,
  );
  return sitePage(
    context: model.page,
    meta: model.meta,
    content: [
      if (!model.available)
        div(classes: 'pol-page', [
          div(classes: 'pol-missing', [
            RawText(materialIcon(mdInfoOutline, size: 48)),
            h1([.text(model.title)]),
            p([
              .text(
                'Esta página no tiene contenido público disponible en este '
                'momento.',
              ),
            ]),
            a(classes: 'w-btn plain', href: '/productos', [
              .text('Ver productos'),
            ]),
          ]),
        ])
      else
        div(classes: 'pol-page', [
          div(classes: 'pol', [
            div(classes: 'pol-side', [
              span(classes: 'pol-icon', [
                RawText(materialIcon(_icon(model.slug))),
              ]),
              h1([.text(model.title)]),
              p(classes: 'pol-sum', [.text(model.summary)]),
              if (model.navigation.isNotEmpty) _PolicyNav(model),
            ]),
            div(classes: 'pol-main blocks', [
              for (final composed in model.blocks) ?_block(composed, render),
            ]),
          ]),
        ]),
    ],
  );
}

Component? _block(ComposedBlock composed, BlockRenderContext render) {
  // `contentAdapter`: the block's own row, not its projection, as Flutter.
  final sections = extractPublicPolicySections([composed.block.sourceBlock]);
  if (sections.isNotEmpty) {
    return composedBlock(
      composed,
      fill: false,
      child: Component.fragment([for (final s in sections) _section(s)]),
    );
  }
  final shared = sharedBlockCovers(composed, coveredSharedBlockTypes)
      ? sharedBlock(composed, render)
      : null;
  if (shared == null) {
    render.uncovered.add(composed.block.blockType);
    return null;
  }
  return composedBlock(composed, fill: true, child: shared);
}

Component _section(PublicPolicySection section) {
  return div(classes: 'psec', [
    h2([.text(section.title)]),
    for (final paragraph in section.paragraphs) p(_lines(paragraph)),
    if (section.items.isNotEmpty)
      div(classes: 'psec-items', [
        for (final item in section.items)
          div(classes: 'pitem', [
            if (item.title.isNotEmpty) h3([.text(item.title)]),
            if (item.body.isNotEmpty) p(_lines(item.body)),
          ]),
      ]),
  ]);
}

/// A text with its single line breaks kept, as Flutter's `Text` keeps them.
List<Component> _lines(String text) {
  final lines = text.split('\n');
  return [
    for (var index = 0; index < lines.length; index++) ...[
      if (index > 0) const br(),
      .text(lines[index]),
    ],
  ];
}

String _icon(String slug) => switch (slug) {
  'nosotros' => mdStorefrontOutlined,
  'envios' => mdLocalShippingOutlined,
  'devoluciones' => mdAssignmentReturnOutlined,
  'terminos' => mdGavelOutlined,
  'privacidad' => mdShieldOutlined,
  _ => mdInfoOutline,
};

class _PolicyNav extends StatelessComponent {
  const _PolicyNav(this.model);

  final PolicyPageModel model;

  @override
  Component build(BuildContext context) {
    return nav(
      classes: 'pol-nav',
      attributes: {'aria-label': 'Información de la tienda'},
      [
        ul([
          for (final slug in model.navigation)
            li([
              a(
                href: '/$slug',
                attributes: {if (slug == model.slug) 'aria-current': 'page'},
                [
                  RawText(materialIcon(_icon(slug), size: 18)),
                  span([.text(PublicPolicyMeta.forSlug(slug, slug).navLabel)]),
                ],
              ),
            ]),
        ]),
      ],
    );
  }
}
