import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_type.dart';
import 'package:vinabike_public_core/public_store/models/public_image_thumbnail.dart';

import 'block_composition.dart';
import 'editor_page_model.dart';
import 'guide_page.dart';
import 'guides_index_model.dart';
import 'material_icons.dart';
import 'site_layout.dart';
import 'website_blocks_view.dart';
import 'website_brand_logos_view.dart';
import 'website_canvas_view.dart';
import 'website_carousel_view.dart';
import 'website_products_view.dart';

/// A page the editor creates, as `DynamicWebsitePage` composes it; a page
/// without blocks says it is under construction (`_buildEmptyState`). A
/// guide draws its trail, title and date above its blocks and the other
/// guides after them.
Component editorPageDocument(EditorPageModel model) {
  final drawn = _drawnBlocks(model);
  final guide = model.guide;
  return sitePage(
    context: model.page,
    meta: model.meta,
    content: [
      if (guide != null) guideHeader(guide),
      if (model.blocks.isEmpty && guide == null)
        div(classes: 'pg-empty', [
          RawText(materialIcon(mdWebStoriesOutlined, size: 64)),
          p(classes: 'pg-empty-t', [.text('Esta página está en construcción')]),
          p(classes: 'pg-empty-s', [
            .text('Vuelve pronto para ver el contenido'),
          ]),
        ])
      else if (model.blocks.isNotEmpty)
        div(classes: 'home-page blocks', drawn.blocks),
      if (guide != null) ?guideRelated(guide),
    ],
    afterFooter: drawn.scripts,
  );
}

/// `/guias`: the index page's title and description, the guides, and the
/// page's own blocks after them.
Component guidesIndexDocument(GuidesIndexModel model) {
  final intro = model.intro;
  final drawn = intro == null ? null : _drawnBlocks(intro);
  return sitePage(
    context: model.page,
    meta: model.meta,
    content: [
      guidesIndexHeader(title: model.title, lead: model.lead),
      guidesIndexList(model.cards),
      // The page's own blocks close the list: a call to write, a question.
      if (drawn != null && intro!.blocks.isNotEmpty)
        div(classes: 'home-page blocks', drawn.blocks),
    ],
    afterFooter: drawn?.scripts ?? const [],
  );
}

({List<Component> blocks, List<Component> scripts}) _drawnBlocks(
  EditorPageModel model,
) => windowPageBlocks(
  model.blocks,
  BlockRenderContext(
    shell: model.page.shell,
    theme: model.theme,
    storeUrl: model.page.storeUrl,
    products: model.products,
    productLists: model.productLists,
    thumbnails: PublicImageThumbnail.byUrl(model.thumbnails),
    draft: model.draft,
  ),
  draft: model.draft,
);

/// The blocks of a page composed at the window's width (the home and the
/// editor's pages), and the scripts the drawn ones need. In the editor's
/// [draft] each block names its id, and a block the HTML does not draw yet
/// says so in its place instead of being left out.
({List<Component> blocks, List<Component> scripts}) windowPageBlocks(
  List<ComposedBlock> blocks,
  BlockRenderContext render, {
  bool draft = false,
}) {
  bool draws(WebsiteBlockType type) => blocks.any(
    (composed) =>
        composed.block.type == type &&
        sharedBlockCovers(composed, pageCoveredBlockTypes),
  );
  return (
    blocks: [
      for (final composed in blocks)
        if (sharedBlockCovers(composed, pageCoveredBlockTypes))
          if (sharedBlock(composed, render) case final shared?)
            composedBlock(composed, fill: true, child: shared, draft: draft)
          else if (draft)
            draftMissingBlock(composed)
          else
            ...const <Component>[]
        else if (draft)
          draftMissingBlock(composed),
    ],
    scripts: [
      if (draws(WebsiteBlockType.carousel)) script(content: carouselScript),
      if (draws(WebsiteBlockType.brandLogos)) script(content: brandLogosScript),
      if (blocks.any(
        (composed) =>
            composed.block.type == WebsiteBlockType.products &&
            productsBlockIsCarousel(composed.data) &&
            sharedBlockCovers(composed, pageCoveredBlockTypes),
      ))
        script(content: productsCarouselScript),
      if (blocks.any(
        (composed) =>
            composed.block.type == WebsiteBlockType.canvas &&
            canvasBlockPlaysVideo(composed.block.blockData) &&
            sharedBlockCovers(composed, pageCoveredBlockTypes),
      ))
        script(content: canvasMediaScript),
    ],
  );
}

/// A block of the editor's draft the HTML does not draw yet, in its place:
/// the operator sees it is there and that the HTML view lacks it (the
/// published page still shows it, drawn by Flutter).
Component draftMissingBlock(ComposedBlock composed) {
  final name = draftBlockName(composed);
  return composedBlock(
    composed,
    fill: true,
    draft: true,
    child: div(classes: 'draft-missing', [
      p(classes: 'draft-missing-t', [.text(name)]),
      p([
        .text(
          'La vista HTML todavía no dibuja este bloque; la página publicada '
          'sí lo muestra.',
        ),
      ]),
    ]),
  );
}
