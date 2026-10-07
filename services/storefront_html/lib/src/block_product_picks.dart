import 'package:vinabike_public_core/modules/website/models/website_block_base_definitions.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_normalization.dart';
import 'package:vinabike_public_core/modules/website/models/website_canvas_responsive_document.dart';
import 'package:vinabike_public_core/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_public_core/shared/models/product.dart';

import 'website_carousel_view.dart';

/// A list of products a block asks for instead of picking them by hand: the
/// featured ones, the newest or a category's, at most [limit] — the products
/// block's `productSource` as `_loadPublicProductsFromPolicy` reads it
/// (`get_public_featured_products`, or `get_public_products` in stock by
/// newest, or by name for a category).
class BlockProductList {
  const BlockProductList._(this.source, this.categoryId, this.limit);

  /// The list a products block shows, or null when it picks by hand or asks
  /// for a category without naming one (Flutter shows none then).
  static BlockProductList? of(WebsiteProductsBlockContract contract) {
    final limit = contract.maxProducts;
    return switch (contract.productSource) {
      'featured' => BlockProductList._('featured', null, limit),
      'newest' => BlockProductList._('newest', null, limit),
      'category' => switch (contract.categoryId?.trim()) {
        final id? when id.isNotEmpty => BlockProductList._(
          'category',
          id,
          limit,
        ),
        _ => null,
      },
      _ => null,
    };
  }

  /// The newest [limit] public products in stock, as a canvas gallery asks
  /// for them (`CanvasBlock._loadLatestProducts`: 1 to 24).
  static BlockProductList newest(int limit) =>
      BlockProductList._('newest', null, limit.clamp(1, 24));

  /// `featured`, `newest` or `category`.
  final String source;
  final String? categoryId;
  final int limit;

  /// The list's name among the page's lists.
  String get key => '$source:${categoryId ?? ''}:$limit';

  @override
  bool operator ==(Object other) =>
      other is BlockProductList && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// What a page's blocks show of the catalog, read before the page is drawn:
/// the products they pick by hand and the lists they ask for.
class PagePicks {
  const PagePicks({this.ids = const [], this.lists = const []});

  final List<String> ids;
  final List<BlockProductList> lists;

  bool get isEmpty => ids.isEmpty && lists.isEmpty;
}

/// Reads [PagePicks] off a page row, once the page is known.
typedef PagePicker = PagePicks Function(Map<String, dynamic> page);

/// What the blocks of [page] show of the catalog (`PublicHomePage` and its
/// products block): the products blocks' hand-picked ids and the lists the
/// others ask for, and the product layers of its canvases and carousel
/// slides ([canvasDocumentPicks]).
PagePicks pagePicks(Map<String, dynamic> page) {
  final ids = <String>{};
  final lists = <BlockProductList>{};
  void canvas(Map<String, dynamic> document) {
    final picks = canvasDocumentPicks(document);
    ids.addAll(picks.ids);
    lists.addAll(picks.lists);
  }

  for (final block in _rows(page)) {
    final data = Map<String, dynamic>.from(
      block['block_data'] as Map? ?? const {},
    );
    switch (block['block_type']) {
      case 'products':
        final contract = WebsiteProductsBlockContract.fromData(data);
        if (contract.productSource == 'manual') {
          ids.addAll(contract.productIds);
        } else if (BlockProductList.of(contract) case final list?) {
          lists.add(list);
        }
      case 'canvas':
        canvas(data);
      case 'carousel':
        for (final slide in carouselSlides(data)) {
          if (carouselSlideUsesComposition(slide)) {
            canvas(
              WebsiteCanvasResponsiveDocument.carouselAuthoringDocument(
                slide: slide,
                showGrid: false,
              ),
            );
          }
        }
    }
  }
  return PagePicks(
    ids: ids.toList(growable: false),
    lists: lists.toList(growable: false),
  );
}

/// The product a canvas layer shows: a product card's, or the one an image
/// takes its photo from (`imageSource` `product`, the default when it names
/// a product); `null` for the rest.
String? canvasLayerProductId(Map<String, dynamic> layer) {
  final id = (layer['productId'] ?? '').toString().trim();
  if (id.isEmpty) return null;
  return switch (WebsiteCanvasLayerKind.fromRaw(layer['type'])) {
    WebsiteCanvasLayerKind.product => id,
    WebsiteCanvasLayerKind.image
        when (layer['imageSource'] ?? 'product').toString() != 'manual' =>
      id,
    _ => null,
  };
}

/// A canvas layer's product gallery as `CanvasBlock` draws it: the newest
/// products (its default) or the ones picked, at most [maxProducts], in a
/// grid of [columns] cards of 3:4 or a row of cards [cardWidth] wide.
class CanvasProductGallery {
  CanvasProductGallery.of(Map<String, dynamic> layer)
    : maxProducts = switch (layer['maxProducts']) {
        final num value => value.toInt(),
        _ => 6,
      },
      newest = (layer['mode'] ?? 'latest').toString() == 'latest',
      ids = [
        if (layer['productIds'] case final List<Object?> ids)
          for (final id in ids)
            if (id != null && id.toString().isNotEmpty) id.toString(),
      ],
      carousel = (layer['layout'] ?? 'grid').toString() == 'carousel',
      columns = switch (layer['columns']) {
        final num value => value.toInt(),
        _ => 3,
      }.clamp(1, 4),
      cardWidth = switch (layer['cardWidth']) {
        final num value => value.toDouble(),
        _ => 300.0,
      }.clamp(220.0, 380.0);

  /// How many it shows.
  final int maxProducts;

  /// Whether it shows the newest products ([list]) instead of [ids].
  final bool newest;

  /// The products picked, in order (shown unless [newest]).
  final List<String> ids;

  final bool carousel;
  final int columns;
  final double cardWidth;

  /// The list the newest come from.
  BlockProductList get list => BlockProductList.newest(maxProducts);

  /// Its height in the document's units, which `CanvasBlock` sets from the
  /// cards it plans (for [maxProducts], 1 to 50) whatever the layer's own:
  /// rows of cards of 3:4 [width] wide in [columns] with 20 between them.
  double height(double width) {
    final rows = (maxProducts.clamp(1, 50) / columns).ceil().clamp(1, 50);
    final card = ((width - (columns - 1) * 20) / columns).clamp(
      10.0,
      double.infinity,
    );
    return rows * card / 0.75 + (rows - 1) * 20;
  }
}

/// What the product layers of a canvas [document] show, in any viewport.
PagePicks canvasDocumentPicks(Map<String, dynamic> document) {
  final ids = <String>{};
  final lists = <BlockProductList>{};
  for (final viewport in WebsiteViewport.values) {
    for (final layer in WebsiteCanvasResponsiveDocument.visibleLayers(
      data: document,
      viewport: viewport,
    )) {
      final data = layer.data;
      if (canvasLayerProductId(data) case final id?) ids.add(id);
      if (WebsiteCanvasLayerKind.fromRaw(data['type']) ==
          WebsiteCanvasLayerKind.productsGallery) {
        final gallery = CanvasProductGallery.of(data);
        if (gallery.newest) {
          lists.add(gallery.list);
        } else {
          ids.addAll(gallery.ids);
        }
      }
    }
  }
  return PagePicks(
    ids: ids.toList(growable: false),
    lists: lists.toList(growable: false),
  );
}

List<Map<String, dynamic>> _rows(Map<String, dynamic>? page) =>
    normalizeWebsiteBlockRows([
      if (page?['website_blocks'] case final List<Object?> blocks)
        for (final block in blocks)
          if (block is Map) Map<String, dynamic>.from(block),
    ]);

/// Each list of [lists] (ids in order, by [BlockProductList.key]) as the
/// page's [products] hold them: a product the visibility rules hide is left
/// out, as from a hand-picked block.
Map<String, List<Product>> blockProductLists(
  Map<String, List<String>> lists,
  Map<String, Product> products,
) => {
  for (final MapEntry(:key, :value) in lists.entries)
    key: [for (final id in value) ?products[id]],
};
