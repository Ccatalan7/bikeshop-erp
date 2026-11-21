import 'package:vinabike_public_core/public_store/models/cart_suggestions_copy.dart';
import 'package:vinabike_public_core/public_store/models/public_commerce_product_projection.dart';
import 'package:vinabike_public_core/public_store/models/public_image_thumbnail.dart';
import 'package:vinabike_public_core/public_store/models/public_on_order_lead.dart';
import 'package:vinabike_public_core/public_store/models/public_product_brand_names.dart';
import 'package:vinabike_public_core/public_store/models/storefront_tax_summary.dart';
import 'package:vinabike_public_core/public_store/utils/product_url.dart';
import 'package:vinabike_public_core/shared/models/product.dart';

import 'public_reads.dart';

/// One line of the visitor's saved cart: what the browser keeps.
typedef SavedCartLine = ({String id, int quantity});

/// The `l` parameter the cart page sends, `<id>:<q>,<id>:<q>`, read as
/// Flutter reads the saved document (`PersistedCart.fromJson`): a whole
/// quantity of at least 1, and a repeated product keeps its largest
/// quantity, never the sum. Anything else on a line drops that line.
List<SavedCartLine> parseSavedCartLines(String raw) {
  final byId = <String, int>{};
  for (final part in raw.split(',')) {
    final pieces = part.split(':');
    if (pieces.length != 2) continue;
    final id = pieces[0].trim();
    final quantity = int.tryParse(pieces[1].trim());
    if (id.isEmpty || quantity == null || quantity < 1) continue;
    if ((byId[id] ?? 0) < quantity) byId[id] = quantity;
    if (byId.length >= maxSavedCartLines) break;
  }
  return [
    for (final MapEntry(:key, :value) in byId.entries)
      (id: key, quantity: value),
  ];
}

/// More lines than any real basket; a longer request is cut there.
const maxSavedCartLines = 60;

/// A line the cart shows, after re-reading its product.
class CartLine {
  CartLine({
    required this.product,
    required this.commerce,
    required this.quantity,
    required this.thumbnail,
    this.onOrder,
  });

  final Product product;
  final PublicCommerceProductProjection commerce;
  final int quantity;
  final PublicImageThumbnail? thumbnail;

  /// What the supplier can bring of it, with its dispatch time and how many
  /// one purchase may take (`get_public_sold_out_offers_v1`,
  /// 20261120210000); null when it is not sold that way now.
  final PublicOnOrderLead? onOrder;

  String get path => publicProductPath(product);
  double get subtotal => commerce.price * quantity;

  /// The line comes from the supplier: what is free on the shelf does not
  /// cover it, so the whole line is ordered (the database decides it the
  /// same way when the order is created). Its dispatch time, or null.
  PublicOnOrderLead? get dispatch =>
      product.tracksInventory &&
          quantity > product.availableStockQuantity &&
          (onOrder?.buyable ?? false)
      ? onOrder
      : null;

  /// The cart can sell this many: on the shelf, or with a dispatch time.
  bool get purchasable => !product.tracksInventory || quantity <= (limit ?? 0);

  /// Flutter's `_buildCartItem`: fewer units than asked, on the shelf and
  /// from the supplier.
  bool get short => !purchasable;

  /// «+» stops at what can be sold.
  bool get canIncrement => !product.tracksInventory || quantity < (limit ?? 0);

  /// The most the cart may hold of it, `null` without a limit: the free
  /// stock, or what the supplier can bring when that is more.
  int? get limit => product.tracksInventory
      ? cartLineLimit(product.availableStockQuantity, onOrder)
      : null;

  StorefrontTaxLineInput get taxInput => StorefrontTaxLineInput(
    label: commerce.title,
    grossUnitPrice: commerce.price,
    quantity: quantity,
    taxRate: product.taxRate,
  );
}

/// A product that goes with the cart, offered under it.
class CartSuggestion {
  CartSuggestion({
    required this.product,
    required this.commerce,
    required this.max,
    required this.thumbnail,
  });

  final Product product;
  final PublicCommerceProductProjection commerce;

  /// The stock «Agregar» may put in, `0` without a limit.
  final int max;
  final PublicImageThumbnail? thumbnail;

  String get path => publicProductPath(product);
}

/// The saved cart as Flutter restores it (`CartProvider._restoreBaseline`):
/// a product that is gone, or out of stock, leaves; one with less stock than
/// asked keeps what there is; each of those counts as an adjusted line for
/// «Ajustamos N producto(s)…». The browser then saves [lines] in place of
/// what it had.
class CartLinesModel {
  CartLinesModel._({
    required this.lines,
    required this.adjusted,
    required this.gone,
    this.suggestions = const [],
    this.suggestionsKind = '',
  });

  factory CartLinesModel.build({
    required List<SavedCartLine> saved,
    required CartReads reads,
    required String tenantId,
    CartFitsReads? fits,
  }) {
    final rows = [
      for (final row in reads.products)
        if (row is Map) Map<String, dynamic>.from(row),
    ];
    final brandNames = canonicalPublicProductBrandNames(
      rows: [
        for (final row in reads.brandRows)
          if (row is Map) Map<String, dynamic>.from(row),
      ],
      tenantId: tenantId,
      requestedBrandIds: [
        for (final row in rows)
          if ((row['brand_id'] ?? '').toString().isNotEmpty)
            row['brand_id'].toString(),
      ],
    );
    final thumbnails = PublicImageThumbnail.byUrl(reads.thumbnails);
    final products = <String, Product>{
      for (final row in rows)
        if (row['id'] != null) row['id'].toString(): Product.fromJson(row),
    };
    // What the supplier can bring, merged into the row by the reads.
    final onOrders = <String, PublicOnOrderLead>{
      for (final row in rows)
        if (row['id'] != null)
          row['id'].toString(): ?PublicOnOrderLead.fromJson(row['on_order']),
    };
    final lines = <CartLine>[];
    final gone = <String>[];
    var adjusted = 0;
    for (final line in saved) {
      final product = products[line.id];
      final onOrder = onOrders[line.id];
      final quantity = product == null
          ? 0
          : _bounded(product, line.quantity, onOrder);
      if (product == null || quantity <= 0) {
        adjusted++;
        gone.add(line.id);
        continue;
      }
      if (quantity < line.quantity) adjusted++;
      final commerce = PublicCommerceProductProjection.fromProduct(
        product,
        resolvedBrand: brandNames[product.brandId ?? ''],
        categoryPath: product.categoryName,
      );
      lines.add(
        CartLine(
          product: product,
          commerce: commerce,
          quantity: quantity,
          thumbnail: commerce.imageUrls.isEmpty
              ? null
              : thumbnails[commerce.imageUrls.first],
          onOrder: onOrder,
        ),
      );
    }
    return CartLinesModel._(
      lines: lines,
      adjusted: adjusted,
      gone: gone,
      suggestions: fits == null
          ? const []
          : _suggestions(
              fits,
              inCart: {for (final l in lines) l.product.id},
              tenantId: tenantId,
            ),
      suggestionsKind: fits?.kind ?? '',
    );
  }

  /// What goes with the cart, at most four, not in it, in the order they
  /// fit, each with the stock «Agregar» may put in.
  static List<CartSuggestion> _suggestions(
    CartFitsReads fits, {
    required Set<String> inCart,
    required String tenantId,
  }) {
    final rows = [
      for (final row in fits.products)
        if (row is Map) Map<String, dynamic>.from(row),
    ];
    final brandNames = canonicalPublicProductBrandNames(
      rows: [
        for (final row in fits.brandRows)
          if (row is Map) Map<String, dynamic>.from(row),
      ],
      tenantId: tenantId,
      requestedBrandIds: [
        for (final row in rows)
          if ((row['brand_id'] ?? '').toString().isNotEmpty)
            row['brand_id'].toString(),
      ],
    );
    final thumbnails = PublicImageThumbnail.byUrl(fits.thumbnails);
    final byId = {
      for (final row in rows)
        if (row['id'] != null) row['id'].toString(): Product.fromJson(row),
    };
    final out = <CartSuggestion>[];
    for (final id in fits.order) {
      final product = byId[id];
      if (product == null || inCart.contains(id) || product.price <= 0) {
        continue;
      }
      final stock = product.tracksInventory
          ? product.availableStockQuantity
          : 0;
      if (product.tracksInventory && stock <= 0) continue;
      final commerce = PublicCommerceProductProjection.fromProduct(
        product,
        resolvedBrand: brandNames[product.brandId ?? ''],
        categoryPath: product.categoryName,
      );
      out.add(
        CartSuggestion(
          product: product,
          commerce: commerce,
          max: stock,
          thumbnail: commerce.imageUrls.isEmpty
              ? null
              : thumbnails[commerce.imageUrls.first],
        ),
      );
      if (out.length == CartSuggestionsCopy.limit) break;
    }
    return out;
  }

  /// `CartProvider._boundedQuantity`, with what the supplier can bring.
  static int _bounded(
    Product product,
    int requested,
    PublicOnOrderLead? onOrder,
  ) {
    if (requested <= 0) return 0;
    if (!product.tracksInventory) return requested;
    final limit = cartLineLimit(product.availableStockQuantity, onOrder);
    if (limit <= 0) return 0;
    return requested > limit ? limit : requested;
  }

  final List<CartLine> lines;

  /// «Te puede faltar» (2026-10-24): what fits the cart's tyres or tubes.
  final List<CartSuggestion> suggestions;

  /// `tubes` or `tyres`, what [suggestions] are.
  final String suggestionsKind;

  /// Saved lines that left or now hold fewer units.
  final int adjusted;

  /// Saved products that left the cart.
  final List<String> gone;

  int get units => lines.fold(0, (sum, line) => sum + line.quantity);

  /// When the whole order can be ready, over the lines the supplier brings:
  /// the longest of their dispatch times; null when everything is on the
  /// shelf.
  PublicOnOrderLead? get dispatch {
    PublicOnOrderLead? longest;
    for (final line in lines) {
      final lead = line.dispatch;
      if (lead == null) continue;
      longest = longest == null
          ? lead
          : PublicOnOrderLead(
              leadDaysMin: lead.leadDaysMin > longest.leadDaysMin
                  ? lead.leadDaysMin
                  : longest.leadDaysMin,
              leadDaysMax: lead.leadDaysMax > longest.leadDaysMax
                  ? lead.leadDaysMax
                  : longest.leadDaysMax,
            );
    }
    return longest;
  }

  StorefrontTaxSummary get taxSummary =>
      StorefrontTaxSummary.calculate(lines.map((line) => line.taxInput));

  /// The gross amount, known even when a tax rate is missing (the catalog
  /// prices already include IVA); `null` when it cannot be added safely.
  int? get grossAmount => StorefrontTaxSummary.calculateGrossAmount(
    lines.map((line) => line.taxInput),
  );
}

/// The most one cart line may hold of a tracked product: its free stock or,
/// when the supplier can bring more, what one purchase may take that way (the
/// whole line then comes from the supplier).
int cartLineLimit(int available, PublicOnOrderLead? onOrder) {
  final shelf = available > 0 ? available : 0;
  final supplier = onOrder?.buyable ?? false ? onOrder!.maxQuantity! : 0;
  return supplier > shelf ? supplier : shelf;
}
