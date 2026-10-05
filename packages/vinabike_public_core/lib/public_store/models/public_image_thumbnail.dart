/// The widths of the smaller copies kept of each public card photo: a phone
/// card is ~160–190 px wide, a desktop card ~250–300 px, at a density of 1 to
/// 3 (2026-10-05).
const publicImageThumbnailWidths = [400, 800];

/// One smaller copy of a photo.
typedef PublicImageVariant = ({int width, int height, String url});

/// The smaller copies of a card photo (`public.public_image_thumbnails`,
/// 20261005130000): `scripts/generate_public_image_thumbnails.dart` writes
/// them and the HTML storefront reads them through
/// `get_public_image_thumbnails_v1`. A photo without a record keeps its own
/// size on the card.
class PublicImageThumbnail {
  const PublicImageThumbnail({
    required this.sourceUrl,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.variants,
  });

  /// A row of the record; `null` when it is not one.
  static PublicImageThumbnail? fromRow(Object? row) {
    if (row is! Map) return null;
    final source = (row['source_url'] ?? '').toString();
    final width = (row['source_width'] as num?)?.toInt() ?? 0;
    final height = (row['source_height'] as num?)?.toInt() ?? 0;
    if (source.isEmpty || width <= 0 || height <= 0) return null;
    final variants = <PublicImageVariant>[
      for (final item in row['variants'] is List ? row['variants'] as List : const [])
        if (item is Map &&
            (item['width'] as num?) != null &&
            (item['height'] as num?) != null &&
            (item['url'] ?? '').toString().startsWith('https://'))
          (
            width: (item['width'] as num).toInt(),
            height: (item['height'] as num).toInt(),
            url: item['url'].toString(),
          ),
    ]..sort((a, b) => a.width.compareTo(b.width));
    return PublicImageThumbnail(
      sourceUrl: source,
      sourceWidth: width,
      sourceHeight: height,
      variants: variants.where((variant) => variant.width < width).toList(),
    );
  }

  /// The rows of `get_public_image_thumbnails_v1`, by photo.
  static Map<String, PublicImageThumbnail> byUrl(Iterable<Object?> rows) {
    final byUrl = <String, PublicImageThumbnail>{};
    for (final row in rows) {
      final thumbnail = fromRow(row);
      if (thumbnail != null) byUrl[thumbnail.sourceUrl] = thumbnail;
    }
    return byUrl;
  }

  final String sourceUrl;
  final int sourceWidth;
  final int sourceHeight;

  /// Narrower than the photo, narrowest first.
  final List<PublicImageVariant> variants;

  /// The smallest copy, for `src`; the photo itself when there is none.
  String get smallestUrl => variants.isEmpty ? sourceUrl : variants.first.url;

  /// Every copy and the photo at its own width, for `srcset`. A comma or a
  /// space would split a candidate, so they are escaped.
  String get srcset => [
    for (final variant in variants) '${_srcsetUrl(variant.url)} ${variant.width}w',
    '${_srcsetUrl(sourceUrl)} ${sourceWidth}w',
  ].join(', ');

  /// The `variants` value the record stores.
  static List<Map<String, Object>> variantsJson(
    Iterable<PublicImageVariant> variants,
  ) => [
    for (final variant in variants)
      {'width': variant.width, 'height': variant.height, 'url': variant.url},
  ];
}

String _srcsetUrl(String url) =>
    url.replaceAll(' ', '%20').replaceAll(',', '%2C');
