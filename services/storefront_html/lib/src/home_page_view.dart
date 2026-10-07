import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/public_store/models/public_image_thumbnail.dart';

import 'editor_page_view.dart';
import 'home_page_model.dart';
import 'site_layout.dart';
import 'website_blocks_view.dart';

/// The store's home, as `PublicHomePage` composes it: the editor's blocks
/// at the window's width, under the header that floats over the first one.
Component homePageDocument(HomePageModel model) {
  final render = BlockRenderContext(
    shell: model.page.shell,
    theme: model.theme,
    storeUrl: model.page.storeUrl,
    products: model.products,
    productLists: model.productLists,
    thumbnails: PublicImageThumbnail.byUrl(model.thumbnails),
    draft: model.draft,
  );
  final drawn = windowPageBlocks(model.blocks, render, draft: model.draft);
  return sitePage(
    context: model.page,
    meta: model.meta,
    content: [div(classes: 'home-page blocks', drawn.blocks)],
    afterFooter: drawn.scripts,
  );
}
