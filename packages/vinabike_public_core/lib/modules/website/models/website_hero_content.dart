import 'website_action.dart';
import 'website_destination.dart';
import 'website_google_reviews.dart';

/// The hero's button: the visible editor fields (`ctaText`/`buttonText`/
/// `label` and `ctaLink`/`buttonLink`/`link`) when present, otherwise the
/// first navigate action; outlined unless the block says otherwise. `null`
/// when it has no label. Flutter's hero and the HTML storefront read it here.
WebsiteActionValue? resolveWebsiteHeroAction(Map<String, dynamic> data) =>
    _resolveVisibleFieldAction(
      data,
      labelKeys: WebsiteButtonFields.hero.label,
      hrefKeys: WebsiteButtonFields.hero.href,
    );

/// How the hero lays out: its photo behind the text, as it always was, or
/// «Partida» (2026-10-23), the text on a panel of the site's color with the
/// photo beside it. Flutter's hero and the HTML storefront read it here.
enum WebsiteHeroLayout { background, split }

WebsiteHeroLayout websiteHeroLayout(Map<String, dynamic> data) =>
    data['layout']?.toString().trim() == 'split'
    ? WebsiteHeroLayout.split
    : WebsiteHeroLayout.background;

/// The split hero's photo is on the left.
bool websiteHeroImageOnLeft(Map<String, dynamic> data) =>
    data['imageSide']?.toString().trim() == 'left';

/// The split hero's second button (`secondaryCtaText`, `secondaryCtaLink`),
/// outlined; `null` without a label or a link.
WebsiteActionValue? resolveWebsiteHeroSecondaryAction(
  Map<String, dynamic> data,
) {
  final label = (data['secondaryCtaText'] ?? '').toString().trim();
  final href = (data['secondaryCtaLink'] ?? '').toString().trim();
  if (label.isEmpty || href.isEmpty) return null;
  return WebsiteActionValue(
    label: label,
    href: href,
    variant: WebsiteActionVariant.outline,
  );
}

/// The product or service the split hero's card shows: the reference (its
/// SKU, or its id) of `cardLink` when it links to a product page; `null`
/// otherwise. Its name and price are read from the catalog, so the card
/// never says an old price.
String? websiteHeroCardReference(Map<String, dynamic> data) {
  final raw = (data['cardLink'] ?? '').toString().trim();
  if (raw.isEmpty) return null;
  final destination = WebsiteDestination.parse(raw);
  if (destination.kind != WebsiteDestinationKind.product) return null;
  final reference = destination.reference?.trim() ?? '';
  return reference.isEmpty ? null : Uri.decodeComponent(reference);
}

/// The reference is a product id rather than a SKU.
bool websiteHeroCardReferenceIsId(String reference) => RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
).hasMatch(reference);

/// What the split hero's card says about the product or service it links
/// to ([websiteHeroCardReference]): where it is from (a service is «En el
/// taller»; a product, its brand or «En la tienda»), its name and price as
/// the catalog has them now, the block's own sentence (`cardText`) and the
/// words of its link.
class WebsiteHeroCard {
  const WebsiteHeroCard({
    required this.eyebrow,
    required this.name,
    required this.price,
    required this.text,
    required this.linkLabel,
  });

  factory WebsiteHeroCard.of(
    Map<String, dynamic> data, {
    required String name,
    required double price,
    required bool service,
    String? brand,
  }) {
    final trimmedBrand = brand?.trim() ?? '';
    return WebsiteHeroCard(
      eyebrow: service
          ? 'En el taller'
          : trimmedBrand.isNotEmpty
          ? trimmedBrand
          : 'En la tienda',
      name: name.trim(),
      price: price,
      text: (data['cardText'] ?? '').toString().trim(),
      linkLabel: service ? 'Ver qué incluye' : 'Ver el producto',
    );
  }

  final String eyebrow;
  final String name;
  final double price;
  final String text;
  final String linkLabel;
}

/// The split hero's proof (`showRating`): the site's Google score and its
/// number of reviews, as the reviews block reads them
/// (`google_reviews_rating`, `google_reviews_total`); `null` when it is off
/// or the site has no score.
({double rating, int? total})? websiteHeroRating(
  Map<String, dynamic> data,
  String Function(String key) setting,
) {
  if (data['showRating'] != true) return null;
  final content = WebsiteGoogleReviewsContent.fromData(
    WebsiteGoogleReviewsContent.withSyncedReviews(const {}, setting),
  );
  final rating = content.rating;
  if (rating == null || rating <= 0) return null;
  return (rating: rating, total: content.totalReviews);
}

/// «4,5», as a Chilean reads a score.
String websiteHeroRatingScore(double rating) =>
    rating.toStringAsFixed(1).replaceAll('.', ',');

/// «en Google · 36 reseñas», after the score.
String websiteHeroRatingSource(int? total) => total == null || total <= 0
    ? 'en Google'
    : 'en Google · $total ${total == 1 ? 'reseña' : 'reseñas'}';

/// A carousel slide's button, by the hero's rule with the slide's fields
/// (`ctaText`/`buttonText` and `ctaLink`/`buttonLink`). Flutter's carousel
/// and the HTML storefront read it here.
WebsiteActionValue? resolveWebsiteCarouselSlideAction(
  Map<String, dynamic> slide,
) => _resolveVisibleFieldAction(
  slide,
  labelKeys: WebsiteButtonFields.slide.label,
  hrefKeys: WebsiteButtonFields.slide.href,
);

WebsiteActionValue? _resolveVisibleFieldAction(
  Map<String, dynamic> data, {
  required List<String> labelKeys,
  required List<String> hrefKeys,
}) {
  ({bool present, String value}) firstPresent(List<String> keys) {
    for (final key in keys) {
      if (data.containsKey(key)) {
        return (present: true, value: data[key]?.toString() ?? '');
      }
    }
    return (present: false, value: '');
  }

  final labelField = firstPresent(labelKeys);
  final hrefField = firstPresent(hrefKeys);
  final resolved = WebsiteActionValue.resolvePrimary(
    data,
    labelKeys: labelKeys,
    hrefKeys: hrefKeys,
    variantKeys: const <String>['actionVariant'],
    defaultLabel: '',
    defaultHref: '',
    defaultVariant: WebsiteActionVariant.outline,
  );
  final label = (labelField.present ? labelField.value : resolved?.label ?? '')
      .trim();
  if (label.isEmpty) return null;
  final href = (hrefField.present ? hrefField.value : resolved?.href ?? '')
      .trim();
  final variant = data.containsKey('actionVariant')
      ? WebsiteActionVariant.fromStorage(
          data['actionVariant']?.toString(),
          fallback: WebsiteActionVariant.outline,
        )
      : resolved?.variant ?? WebsiteActionVariant.outline;
  return WebsiteActionValue(label: label, href: href, variant: variant);
}

/// The YouTube video id in a `youtube.com/watch?v=`, `youtube.com/embed/`,
/// `youtube.com/v/` or `youtu.be/` link, or `null`. Flutter's video banner
/// and carousel and the HTML storefront read it here.
String? websiteYouTubeVideoId(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  if (uri.host.contains('youtube.com')) {
    final videoId = uri.queryParameters['v'];
    if (videoId != null && videoId.isNotEmpty) return videoId;
    final segments = uri.pathSegments;
    if (segments.isNotEmpty) {
      final embed = segments.indexOf('embed');
      final v = segments.indexOf('v');
      if (embed != -1 && embed + 1 < segments.length) {
        return segments[embed + 1];
      }
      if (v != -1 && v + 1 < segments.length) return segments[v + 1];
    }
  }
  if (uri.host.contains('youtu.be')) {
    final segments = uri.pathSegments;
    if (segments.isNotEmpty) return segments.first;
  }
  return null;
}
