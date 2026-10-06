import 'package:vinabike_public_core/modules/website/models/website_block_base_definitions.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_normalization.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';
import 'package:vinabike_public_core/shared/models/product.dart';
import 'package:vinabike_public_core/shared/models/public_product_visibility_policy.dart';

import 'block_composition.dart';
import 'public_reads.dart';
import 'site_layout.dart';
import 'website_blocks_view.dart';
import 'website_carousel_view.dart';
import 'website_page_css.dart';

/// The home's blocks span the window (`PublicHomePage` composes at the
/// window's width), so visibility and data change at the same widths:
/// 640 and 1024.
const homeBands = <WidthBand>[
  WidthBand(
    index: 0,
    minWidth: 0,
    maxWidth: 640,
    sample: 400,
    canvasWidth: 400,
  ),
  WidthBand(
    index: 1,
    minWidth: 640,
    maxWidth: 1024,
    sample: 800,
    canvasWidth: 800,
  ),
  WidthBand(
    index: 2,
    minWidth: 1024,
    maxWidth: null,
    sample: 1440,
    canvasWidth: 1440,
  ),
];

/// The block ids of the products a home block picks by hand, read before the
/// page is drawn (`PublicHomePage` and its products block).
List<String> homeProductIds(Map<String, dynamic> page) => [
  for (final block in _rows(page))
    if (block['block_type'] == 'products')
      ...() {
        final contract = WebsiteProductsBlockContract.fromData(
          Map<String, dynamic>.from(block['block_data'] as Map? ?? const {}),
        );
        return contract.productSource == 'manual'
            ? contract.productIds
            : const <String>[];
      }(),
];

List<Map<String, dynamic>> _rows(Map<String, dynamic>? page) =>
    normalizeWebsiteBlockRows([
      if (page?['website_blocks'] case final List<Object?> blocks)
        for (final block in blocks)
          if (block is Map) Map<String, dynamic>.from(block),
    ]);

/// The photo of the first slide when the page opens with a carousel: the
/// largest paint, fetched before the stylesheet's fonts.
String? _firstSlideImage(List<Map<String, dynamic>> rows) {
  final first = rows
      .where((row) => row['is_visible'] != false)
      .fold<Map<String, dynamic>?>(
        null,
        (best, row) =>
            best == null ||
                ((row['order_index'] as num?) ?? 0) <
                    ((best['order_index'] as num?) ?? 0)
            ? row
            : best,
      );
  if (first == null || first['block_type'] != 'carousel') return null;
  final data = first['block_data'];
  if (data is! Map) return null;
  final slides = carouselSlides(Map<String, dynamic>.from(data));
  if (slides.isEmpty) return null;
  final image = (slides.first['imageUrl'] ?? '').toString().trim();
  return image.isEmpty ? null : image;
}

/// The store's home, as Flutter's `PublicHomePage` composes it.
class HomePageModel {
  HomePageModel._({
    required this.page,
    required this.meta,
    required this.blocks,
    required this.theme,
    required this.products,
    required this.brandRows,
    required this.thumbnails,
  });

  factory HomePageModel.build({
    required PageContext page,
    required HomePageReads reads,
  }) {
    final shell = page.shell;
    final theme = WebsiteThemeRoles.resolve(shell.setting);
    final rows = _rows(reads.page);
    final policy = PublicProductVisibilityPolicy.hasAnySetting(shell.settings)
        ? PublicProductVisibilityPolicy.fromSettings(shell.settings)
        : null;
    final products = {
      for (final row in reads.products)
        if (row is Map)
          ...() {
            final product = Product.fromJson(Map<String, dynamic>.from(row));
            return policy == null || policy.allowsProduct(product)
                ? {product.id: product}
                : const <String, Product>{};
          }(),
    };
    final storeName = shell.storeName;
    final title = shell.setting(
      'seo_meta_title',
      storeName.isEmpty ? 'Tienda' : storeName,
    );
    final description = shell.setting(
      'seo_meta_description',
      shell.setting('meta_description', shell.storeDescription),
    );
    return HomePageModel._(
      page: page,
      meta: PageMeta(
        title: title,
        description: description,
        canonicalUrl: page.storeUrl,
        indexable: true,
        imageUrl: shell.setting('seo_og_image', shell.setting('logo_url')),
        styles: homePageCss(theme),
        overlayHeader: true,
        preloadImage: switch (_firstSlideImage(rows)) {
          final src? => (src: src, srcset: null, sizes: null),
          null => null,
        },
      ),
      blocks: composeBlocks(
        rows: rows,
        bands: homeBands,
        sectionSpacing: theme.sectionSpacing,
      ),
      theme: theme,
      products: products,
      brandRows: reads.brandRows,
      thumbnails: reads.thumbnails,
    );
  }

  final PageContext page;
  final PageMeta meta;
  final List<ComposedBlock> blocks;
  final WebsiteThemeRoles theme;

  /// The hand-picked products that are in stock and public, by id.
  final Map<String, Product> products;
  final List<Object?> brandRows;
  final List<Object?> thumbnails;

  /// The block types on the home the HTML storefront does not draw yet
  /// (`x-storefront-uncovered`): `/` opens only when there is none.
  late final Set<String> uncoveredTypes = {
    for (final composed in blocks)
      if (!sharedBlockCovers(composed, pageCoveredBlockTypes))
        composed.block.blockType,
  };
}
