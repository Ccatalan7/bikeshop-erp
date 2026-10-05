/// A product photo as a page draws it.
///
/// Every published photo is one optimized JPG of ~1,200 px
/// (`image_url_optimized`, written by the ERP's image pipeline); there are no
/// smaller sizes yet. `srcset` stays empty until there are: generating them
/// is either a paid image service or a change to that pipeline, a decision
/// for the owner (phase 1 measured the main photo first).
class ProductImage {
  const ProductImage(this.src, {this.srcset, this.sizes});

  final String src;
  final String? srcset;
  final String? sizes;
}

/// The gallery of a product page: the projection's photos, in order.
List<ProductImage> productPhotos(
  Map<String, dynamic> row,
  List<String> imageUrls,
) => [for (final url in imageUrls) ProductImage(url)];
