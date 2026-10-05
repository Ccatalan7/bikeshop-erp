import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:vinabike_public_core/public_store/models/public_commerce_product_projection.dart';
import 'package:vinabike_public_core/shared/utils/chilean_utils.dart';

/// A product in a grid, as the Flutter catalog's card shows it: the photo,
/// the brand, the name and the price, all one link to the product page.
class ProductCard extends StatelessComponent {
  const ProductCard({
    required this.commerce,
    required this.path,
    this.eager = false,
    this.first = false,
    super.key,
  });

  final PublicCommerceProductProjection commerce;
  final String path;

  /// The first row of a phone grid loads at once; the rest when they near
  /// the screen, so they do not take bandwidth from the first photo.
  final bool eager;

  /// The grid's first photo, the page's largest paint: fetched first.
  final bool first;

  @override
  Component build(BuildContext context) {
    final image = commerce.imageUrls.isEmpty ? null : commerce.imageUrls.first;
    return li(classes: 'card', [
      a(href: path, [
        div(classes: 'shot', [
          if (image != null)
            img(
              src: image,
              alt: '',
              width: 400,
              height: 400,
              loading: eager ? null : MediaLoading.lazy,
              // Below the first row a photo waits for the ones on screen:
              // on a slow phone they shared the bandwidth with the page's
              // largest paint (2026-10-05).
              attributes: {
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

/// A price as the store writes it, or «Consultar» when it has none.
String publicPrice(double value) =>
    value > 0 ? ChileanUtils.formatCurrency(value) : 'Consultar';

/// The product page's large price, without the space after the sign, as
/// Flutter's `_formatHeroPrice` draws it.
String publicHeroPrice(double value) =>
    publicPrice(value).replaceFirst(r'$ ', r'$');
