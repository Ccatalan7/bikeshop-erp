import 'package:vinabike_public_core/public_store/models/public_commerce_product_projection.dart';
import 'package:vinabike_public_core/public_store/models/public_image_thumbnail.dart';
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
  });

  final Product product;
  final PublicCommerceProductProjection commerce;
  final int quantity;
  final PublicImageThumbnail? thumbnail;

  String get path => publicProductPath(product);
  double get subtotal => commerce.price * quantity;

  /// Flutter's `_buildCartItem`: out of stock, or fewer units than asked.
  bool get short =>
      commerce.availability.merchantValue == 'out_of_stock' ||
      product.availableStockQuantity < quantity;

  /// «+» stops at the stock of a product that keeps one.
  bool get canIncrement =>
      !product.tracksInventory || quantity < product.availableStockQuantity;

  /// The most the cart may hold of it, `null` without a limit.
  int? get limit =>
      product.tracksInventory ? product.availableStockQuantity : null;

  StorefrontTaxLineInput get taxInput => StorefrontTaxLineInput(
    label: commerce.title,
    grossUnitPrice: commerce.price,
    quantity: quantity,
    taxRate: product.taxRate,
  );
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
  });

  factory CartLinesModel.build({
    required List<SavedCartLine> saved,
    required CartReads reads,
    required String tenantId,
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
    final lines = <CartLine>[];
    final gone = <String>[];
    var adjusted = 0;
    for (final line in saved) {
      final product = products[line.id];
      final quantity = product == null ? 0 : _bounded(product, line.quantity);
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
        ),
      );
    }
    return CartLinesModel._(lines: lines, adjusted: adjusted, gone: gone);
  }

  /// `CartProvider._boundedQuantity`.
  static int _bounded(Product product, int requested) {
    if (requested <= 0) return 0;
    if (!product.tracksInventory) return requested;
    final available = product.availableStockQuantity;
    if (available <= 0) return 0;
    return requested > available ? available : requested;
  }

  final List<CartLine> lines;

  /// Saved lines that left or now hold fewer units.
  final int adjusted;

  /// Saved products that left the cart.
  final List<String> gone;

  int get units => lines.fold(0, (sum, line) => sum + line.quantity);

  StorefrontTaxSummary get taxSummary =>
      StorefrontTaxSummary.calculate(lines.map((line) => line.taxInput));

  /// The gross amount, known even when a tax rate is missing (the catalog
  /// prices already include IVA); `null` when it cannot be added safely.
  int? get grossAmount => StorefrontTaxSummary.calculateGrossAmount(
    lines.map((line) => line.taxInput),
  );
}
