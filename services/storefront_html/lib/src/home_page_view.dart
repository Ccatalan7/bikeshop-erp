import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_type.dart';
import 'package:vinabike_public_core/public_store/models/public_image_thumbnail.dart';

import 'block_composition.dart';
import 'home_page_model.dart';
import 'site_layout.dart';
import 'website_blocks_view.dart';
import 'website_brand_logos_view.dart';
import 'website_carousel_view.dart';

/// The store's home, as `PublicHomePage` composes it: the editor's blocks
/// at the window's width, under the header that floats over the first one.
Component homePageDocument(HomePageModel model) {
  final render = BlockRenderContext(
    shell: model.page.shell,
    theme: model.theme,
    storeUrl: model.page.storeUrl,
    products: model.products,
    thumbnails: PublicImageThumbnail.byUrl(model.thumbnails),
  );
  final blocks = [
    for (final composed in model.blocks) ?_block(composed, render),
  ];
  bool draws(WebsiteBlockType type) => model.blocks.any(
    (composed) =>
        composed.block.type == type &&
        sharedBlockCovers(composed, homeCoveredBlockTypes),
  );
  return sitePage(
    context: model.page,
    meta: model.meta,
    content: [div(classes: 'home-page blocks', blocks)],
    afterFooter: [
      if (draws(WebsiteBlockType.carousel)) script(content: carouselScript),
      if (draws(WebsiteBlockType.brandLogos)) script(content: brandLogosScript),
    ],
  );
}

Component? _block(ComposedBlock composed, BlockRenderContext render) {
  if (!sharedBlockCovers(composed, homeCoveredBlockTypes)) return null;
  final shared = sharedBlock(composed, render);
  if (shared == null) return null;
  return composedBlock(composed, fill: true, child: shared);
}
