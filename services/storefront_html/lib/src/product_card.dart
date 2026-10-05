import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_public_core/public_store/models/public_commerce_product_projection.dart';
import 'package:vinabike_public_core/public_store/models/public_image_thumbnail.dart';
import 'package:vinabike_public_core/shared/utils/chilean_utils.dart';

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

  @override
  Component build(BuildContext context) {
    final image = commerce.imageUrls.isEmpty ? null : commerce.imageUrls.first;
    final copies = thumbnail?.sourceUrl == image ? thumbnail : null;
    return li(classes: 'card', [
      a(href: path, [
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
            ),
        ]),
        if (commerce.brand.isNotEmpty) p(classes: 'maker', [.text(commerce.brand)]),
        span(classes: 'name', [.text(commerce.title)]),
        span(classes: 'p', [.text(publicPrice(commerce.price))]),
      ]),
    ]);
  }
}

/// How wide a grid shows each card's photo, for `sizes`: two columns up to
/// 760 px, three up to 1.180 px, then four (three in the editorial grid, five
/// in the compact one) in a page at most 1.560 px wide
/// (`storefront_css.dart`).
String cardImageSizes(WebsiteCatalogGridDensity density) =>
    '(max-width: 760px) 46vw, (max-width: 1180px) 30vw, ${switch (density) {
      WebsiteCatalogGridDensity.compact => 240,
      WebsiteCatalogGridDensity.editorial => 400,
      WebsiteCatalogGridDensity.balanced => 300,
    }}px';

/// A price as the store writes it, or «Consultar» when it has none.
String publicPrice(double value) =>
    value > 0 ? ChileanUtils.formatCurrency(value) : 'Consultar';

/// The product page's large price, without the space after the sign, as
/// Flutter's `_formatHeroPrice` draws it.
String publicHeroPrice(double value) =>
    publicPrice(value).replaceFirst(r'$ ', r'$');
