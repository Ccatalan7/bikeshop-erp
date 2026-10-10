import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_public_core/public_store/models/public_commerce_product_projection.dart';
import 'package:vinabike_public_core/public_store/models/public_image_thumbnail.dart';
import 'package:vinabike_public_core/shared/utils/chilean_utils.dart';

import 'material_icons.dart';

/// A product in a grid, as the Flutter catalog's card shows it: the photo,
/// the brand, the name and the price, all one link to the product page.
class ProductCard extends StatelessComponent {
  const ProductCard({
    required this.commerce,
    required this.path,
    this.thumbnail,
    this.sizes = '',
    this.eager = false,
    this.first = false,
    this.service = false,
    super.key,
  });

  final PublicCommerceProductProjection commerce;
  final String path;

  /// The smaller copies of the photo, when the job has made them: the browser
  /// then picks the one its card needs ([sizes]) instead of the 1.200 px
  /// photo (75–120 KB), which kept `/productos` at ~4,4 s on a slow phone.
  final PublicImageThumbnail? thumbnail;

  /// How wide the card shows its photo (`cardImageSizes`).
  final String sizes;

  /// The first row of a phone grid loads at once; the rest when they near
  /// the screen, so they do not take bandwidth from the first photo.
  final bool eager;

  /// The grid's first photo, the page's largest paint: fetched first.
  final bool first;

  /// A workshop service: it has no stock to show.
  final bool service;

  @override
  Component build(BuildContext context) {
    final image = commerce.imageUrls.isEmpty ? null : commerce.imageUrls.first;
    final copies = thumbnail?.sourceUrl == image ? thumbnail : null;
    final hasBrand = commerce.brand.trim().isNotEmpty;
    final inStock = commerce.availability == PublicCommerceAvailability.inStock;
    // `_CatalogProductCard`: the photo over a fixed 90 px block with the name
    // and price; the brand sits on the photo and, on hover, a bar with the
    // brand and the stock rises from its bottom edge.
    return li(classes: hasBrand ? 'card has-brand' : 'card', [
      a(href: path, attributes: measuredItem(commerce), [
        div(classes: 'shot', [
          if (image != null)
            img(
              src: copies?.smallestUrl ?? image,
              alt: '',
              width: 400,
              height: 400,
              loading: eager ? null : MediaLoading.lazy,
              // Below the first row a photo waits for the ones on screen:
              // on a slow phone they shared the bandwidth with the page's
              // largest paint (2026-10-05).
              attributes: {
                if (copies != null && copies.variants.isNotEmpty) ...{
                  'srcset': copies.srcset,
                  'sizes': sizes,
                },
                'decoding': 'async',
                'fetchpriority': first
                    ? 'high'
                    : eager
                    ? 'auto'
                    : 'low',
              },
            )
          else
            span(classes: 'no-photo', [
              RawText(materialIcon(mdPedalBikeOutlined, size: 48)),
            ]),
          if (hasBrand) span(classes: 'maker', [.text(commerce.brand)]),
          span(
            classes: 'hover-bar',
            attributes: {'aria-hidden': 'true'},
            [
              span([.text(hasBrand ? commerce.brand : '')]),
              span([
                .text(
                  service
                      ? ''
                      : inStock
                      ? 'EN STOCK'
                      : 'AGOTADO',
                ),
              ]),
            ],
          ),
        ]),
        div(classes: 'info', [
          span(classes: 'name', [.text(commerce.title)]),
          span(classes: 'p', [.text(publicPrice(commerce.price))]),
        ]),
      ]),
    ]);
  }
}

/// How wide a card shows its photo, for `sizes`. A phone (under 700 px)
/// gives the grid the width minus 16 px sides, a wider page the width minus
/// the 236 px rail, its 40 px gap and 28 px sides (at most 1228 px); the grid
/// takes 2 columns under 568 px, 3 under 860 (3 also under 988 in the
/// editorial grid), then 4 (5 in the compact one); the photo is the card
/// minus 24 px.
String cardImageSizes(WebsiteCatalogGridDensity density) {
  final wide = switch (density) {
    WebsiteCatalogGridDensity.editorial =>
      '(max-width: 1319px) calc(33vw - 153px), '
          '(max-width: 1559px) calc(25vw - 132px), 257px',
    WebsiteCatalogGridDensity.compact =>
      '(max-width: 1319px) calc(25vw - 128px), '
          '(max-width: 1559px) calc(20vw - 111px), 201px',
    WebsiteCatalogGridDensity.balanced =>
      '(max-width: 1559px) calc(25vw - 128px), 257px',
  };
  return '(max-width: 599px) calc(50vw - 49px), '
      '(max-width: 699px) calc(33vw - 49px), '
      '(max-width: 899px) calc(50vw - 199px), '
      '(max-width: 1191px) calc(33vw - 149px), $wide';
}

/// A price as the store writes it, or «Consultar» when it has none.
String publicPrice(double value) =>
    value > 0 ? ChileanUtils.formatCurrency(value) : 'Consultar';

/// `Icons.pedal_bike_outlined`, the card's placeholder without a photo.

/// What a card tells the store script for Google Analytics (`select_item`,
/// `view_item_list` in its `[data-list-id]`): the item as `view_item` names
/// it, its SKU (its id without one), name and price.
Map<String, String> measuredItem(PublicCommerceProductProjection commerce) => {
  'data-item-id': commerce.sku.isNotEmpty ? commerce.sku : commerce.id,
  'data-item-name': commerce.title,
  'data-price': '${commerce.price.round()}',
};

/// The list a container of cards is for Google Analytics: [id] and the
/// [name] its reports show.
Map<String, String> measuredList(String id, String name) => {
  'data-list-id': id,
  'data-list-name': name,
};
