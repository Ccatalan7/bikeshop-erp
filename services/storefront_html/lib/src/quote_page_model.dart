import 'package:vinabike_public_core/public_store/models/public_commerce_product_projection.dart';
import 'package:vinabike_public_core/public_store/models/public_image_thumbnail.dart';
import 'package:vinabike_public_core/public_store/models/public_on_order_lead.dart';
import 'package:vinabike_public_core/public_store/models/public_product_brand_names.dart';
import 'package:vinabike_public_core/public_store/utils/product_url.dart';
import 'package:vinabike_public_core/shared/models/product.dart';

import 'cart_page_model.dart';
import 'public_reads.dart';

/// Where the quote page lives and where it asks for its lines.
const quotePagePath = '/cotizacion';
const quoteLinesPath = '/cotizacion/lineas';

/// The most a customer asks for of one product in a quote, as the database
/// takes it (`customer_quote_lines.quantity`, 1 to 99).
const quoteLineMaxQuantity = 99;

/// One product of the quote the visitor is putting together. What is not on
/// the shelf is what a quote is for (20261102041700), but only of what the
/// shop offers without stock (20261103070000): the rest is quoted up to its
/// stock. Whether it comes from the shelf, is ordered or is confirmed is said
/// by the page with the stock and [offer].
class QuoteLine {
  const QuoteLine({
    required this.product,
    required this.commerce,
    required this.quantity,
    this.thumbnail,
    this.offer,
    this.lead,
  });

  final Product product;
  final PublicCommerceProductProjection commerce;
  final int quantity;
  final PublicImageThumbnail? thumbnail;

  /// Beyond its stock: `on_order` (with [lead]), `quote`, or null when the
  /// shop does not offer it without stock.
  final String? offer;
  final PublicOnOrderLead? lead;

  int get stock => product.stockQuantity < 0 ? 0 : product.stockQuantity;
}

/// The visitor's saved quote lines, re-read: a product the site no longer
/// shows, or a service, leaves the list and is named in [gone].
class QuoteLinesModel {
  const QuoteLinesModel._({required this.lines, required this.gone});

  final List<QuoteLine> lines;
  final List<String> gone;

  static QuoteLinesModel build({
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
    final rowsById = {
      for (final row in rows)
        if (row['id'] != null) row['id'].toString(): row,
    };
    final lines = <QuoteLine>[];
    final gone = <String>[];
    for (final line in saved) {
      final product = products[line.id];
      if (product == null || product.isService) {
        gone.add(line.id);
        continue;
      }
      final commerce = PublicCommerceProductProjection.fromProduct(
        product,
        resolvedBrand: brandNames[product.brandId ?? ''],
        categoryPath: product.categoryName,
      );
      if (commerce.price <= 0) {
        gone.add(line.id);
        continue;
      }
      final row = rowsById[line.id] ?? const <String, dynamic>{};
      final offer = switch (row['sold_out_offer']) {
        'on_order' || 'quote' => row['sold_out_offer'] as String,
        _ => null,
      };
      final lead = offer == 'on_order'
          ? PublicOnOrderLead.fromJson(row['on_order'])
          : null;
      lines.add(
        QuoteLine(
          product: product,
          commerce: commerce,
          quantity: line.quantity.clamp(1, quoteLineMaxQuantity),
          thumbnail: commerce.imageUrls.isEmpty
              ? null
              : thumbnails[commerce.imageUrls.first],
          // On order without a usable lead is still quoted, to confirm.
          offer: offer == 'on_order' && lead == null ? 'quote' : offer,
          lead: lead,
        ),
      );
    }
    return QuoteLinesModel._(lines: lines, gone: gone);
  }
}

/// `/cotizacion/lineas`: what the quote page draws for each line, with how it
/// is offered beyond its stock (`offer`: `on_order` with `lead`, `quote`, or
/// `none`, quoted only up to `stock`).
Map<String, Object?> quoteLinesJson(QuoteLinesModel model) => {
  'gone': model.gone,
  'lines': [
    for (final line in model.lines)
      {
        'id': line.product.id,
        'title': line.commerce.title,
        'sku': line.commerce.sku,
        'url': publicProductPath(line.product),
        'img': line.commerce.imageUrls.isEmpty
            ? ''
            : (line.thumbnail?.smallestUrl ?? line.commerce.imageUrls.first),
        'price': line.commerce.price.round(),
        'stock': line.stock,
        'q': line.quantity,
        'offer': line.offer ?? 'none',
        if (line.lead case final lead?) 'lead': lead.toJson(),
      },
  ],
};
