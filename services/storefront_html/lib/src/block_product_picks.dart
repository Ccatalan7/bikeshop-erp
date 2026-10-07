import 'package:vinabike_public_core/modules/website/models/website_block_base_definitions.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_normalization.dart';
import 'package:vinabike_public_core/shared/models/product.dart';

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

/// What the products blocks of [page] show (`PublicHomePage` and its
/// products block): the hand-picked ids and the lists the others ask for.
PagePicks pagePicks(Map<String, dynamic> page) {
  final ids = <String>[];
  final lists = <BlockProductList>{};
  for (final block in _rows(page)) {
    if (block['block_type'] != 'products') continue;
    final contract = WebsiteProductsBlockContract.fromData(
      Map<String, dynamic>.from(block['block_data'] as Map? ?? const {}),
    );
    if (contract.productSource == 'manual') {
      ids.addAll(contract.productIds);
    } else if (BlockProductList.of(contract) case final list?) {
      lists.add(list);
    }
  }
  return PagePicks(ids: ids, lists: lists.toList(growable: false));
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
