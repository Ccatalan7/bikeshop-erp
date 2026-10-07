import 'website_google_reviews.dart';

/// What the section blocks (stats, services, plans, testimonials, gallery,
/// team, questions, call to action) read from their data and the store's
/// settings, decided once for the Flutter canvas and the HTML storefront so
/// both draw the same thing: which quotes a testimonials block shows, how a
/// gallery's mosaic is cut, where a call to action leads.

/// The items of a block's list (its [key], or the first alias it has), each
/// with its place in the stored list: an entry that is not an item is
/// skipped, and the editor addresses an item by where it is stored. An
/// explicit empty list is empty: an alias never revives older samples.
List<(int, Map<String, dynamic>)> websiteSectionItems(
  Map<String, dynamic> data,
  String key, [
  List<String> aliases = const [],
]) {
  Object? raw;
  if (data.containsKey(key)) {
    raw = data[key];
  } else {
    for (final alias in aliases) {
      if (data.containsKey(alias)) {
        raw = data[alias];
        break;
      }
    }
  }
  return [
    if (raw is List)
      for (final (index, item) in raw.indexed)
        if (item is Map) (index, Map<String, dynamic>.from(item)),
  ];
}

/// A text of a block's data, as stored ('' when absent).
String websiteSectionText(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    if (data.containsKey(key)) return data[key]?.toString() ?? '';
  }
  return '';
}

/// A rating as a Chilean reads it: one decimal and a comma (4,4).
String websiteRatingLabel(double rating) =>
    rating.toStringAsFixed(1).replaceFirst('.', ',');

/// An address as two lines for the gallery's address tile: the street (and
/// local) first, the city under it. A trailing country (Chile) is left out;
/// an address of one part is all street.
({String street, String city}) websiteAddressLines(String address) {
  final parts = [
    for (final part in address.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];
  if (parts.length >= 3 && parts.last.toLowerCase() == 'chile') {
    parts.removeLast();
  }
  if (parts.isEmpty) return (street: '', city: '');
  if (parts.length == 1) return (street: parts.single, city: '');
  return (
    street: parts.sublist(0, parts.length - 1).join(', '),
    city: parts.last,
  );
}

/// One cell of a gallery: how many columns and rows of the mosaic it takes.
typedef WebsiteMosaicSpan = ({int columns, int rows});

/// The gallery's mosaic: a big photo, a tall one, two small ones and a wide
/// one, over and over, so [count] cells always fill whole rows and never
/// leave a hole. On a desktop or tablet the grid has 4 columns and a group of
/// five cells fills three rows (2×2, 1×2, 1×1, 1×1, 4×1); on a phone it has
/// 2 and a group of four fills four (2×2, 1×1, 1×1, 2×1). A last group that
/// is not whole is cut so it still fills its rows.
List<WebsiteMosaicSpan> websiteMosaicSpans(int count, {required bool phone}) {
  final spans = <WebsiteMosaicSpan>[];
  final group = phone ? 4 : 5;
  final whole = count ~/ group * group;
  for (var index = 0; index < whole; index++) {
    spans.add(
      phone
          ? const [
              (columns: 2, rows: 2),
              (columns: 1, rows: 1),
              (columns: 1, rows: 1),
              (columns: 2, rows: 1),
            ][index % 4]
          : const [
              (columns: 2, rows: 2),
              (columns: 1, rows: 2),
              (columns: 1, rows: 1),
              (columns: 1, rows: 1),
              (columns: 4, rows: 1),
            ][index % 5],
    );
  }
  final rest = count - whole;
  final tail = phone
      ? switch (rest) {
          1 => const [(columns: 2, rows: 1)],
          2 => const [(columns: 1, rows: 1), (columns: 1, rows: 1)],
          3 => const [
            (columns: 2, rows: 1),
            (columns: 1, rows: 1),
            (columns: 1, rows: 1),
          ],
          _ => const <WebsiteMosaicSpan>[],
        }
      : switch (rest) {
          1 => const [(columns: 4, rows: 1)],
          2 => const [(columns: 2, rows: 1), (columns: 2, rows: 1)],
          3 => const [
            (columns: 2, rows: 1),
            (columns: 1, rows: 1),
            (columns: 1, rows: 1),
          ],
          4 => const [
            (columns: 2, rows: 2),
            (columns: 1, rows: 2),
            (columns: 1, rows: 1),
            (columns: 1, rows: 1),
          ],
          _ => const <WebsiteMosaicSpan>[],
        };
  return [...spans, ...tail];
}

/// Where the gallery's address tile goes among [photos] photos: fourth, as
/// the second small cell of the first group, or last with fewer photos.
int websiteGalleryAddressSlot(int photos) => photos >= 3 ? 3 : photos;

/// A gallery's layout (`layout`): the mosaic (stored `masonry`) unless it
/// says `grid`.
bool websiteGalleryIsGrid(Map<String, dynamic> data) =>
    data['layout']?.toString().trim().toLowerCase() == 'grid';

/// One quote of a testimonials block: the block's own (editable in place, at
/// [index] of its list) or one of the store's synced Google reviews.
class WebsiteSectionQuote {
  const WebsiteSectionQuote({
    required this.text,
    required this.name,
    required this.detail,
    required this.rating,
    this.index,
  });

  final String text;
  final String name;

  /// Beside the name: what the block says of the client, or when the review
  /// was written.
  final String detail;
  final int? rating;

  /// The quote's place in the block's `testimonials`; `null` for a Google
  /// review, which the operator cannot edit.
  final int? index;

  bool get isOwn => index != null;

  /// The circle's letter: the name's first one.
  String get initial {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }

  /// The line beside the name: the detail and the stars in words.
  String get meta {
    final stars = rating == null
        ? ''
        : rating == 1
        ? '1 estrella'
        : '$rating estrellas';
    return [detail.trim(), stars].where((part) => part.isNotEmpty).join(' · ');
  }
}

/// What a testimonials block shows: the store's score in Google (when the
/// block shows it and the sync brought one) and the quotes, its own or, when
/// it has none, up to three of the synced Google reviews with words.
class WebsiteTestimonialsContent {
  const WebsiteTestimonialsContent({
    required this.quotes,
    required this.rating,
    required this.totalReviews,
    required this.mapsUrl,
  });

  factory WebsiteTestimonialsContent.resolve(
    Map<String, dynamic> data, {
    required String Function(String key) setting,
    required String mapsUrl,
    DateTime? now,
  }) {
    final showGoogle = data['showGoogleRating'] != false;
    final own = websiteSectionItems(data, 'testimonials', const ['items']);
    final google = showGoogle
        ? WebsiteGoogleReviewsContent.fromData(
            WebsiteGoogleReviewsContent.withSyncedReviews(
              const <String, dynamic>{},
              setting,
            ),
          )
        : null;
    final quotes = <WebsiteSectionQuote>[
      for (final (index, item) in own)
        WebsiteSectionQuote(
          index: index,
          text: websiteSectionText(item, const ['comment', 'quote', 'text']),
          name: websiteSectionText(item, const ['name']),
          detail: websiteSectionText(item, const ['role']),
          rating: _rating(item['rating']),
        ),
    ];
    if (own.isEmpty && google != null) {
      final clock = now ?? DateTime.now();
      for (final review in google.reviews) {
        final words = (review.data['text'] ?? review.data['comment'] ?? '')
            .toString()
            .trim();
        if (words.isEmpty) continue;
        quotes.add(
          WebsiteSectionQuote(
            text: words,
            name: WebsiteGoogleReviewsContent.authorName(review.data),
            detail: _capitalized(
              WebsiteGoogleReviewsContent.relativeTime(review.data, clock),
            ),
            rating: review.rating,
          ),
        );
        if (quotes.length == 3) break;
      }
    }
    return WebsiteTestimonialsContent(
      quotes: List.unmodifiable(quotes),
      rating: google?.rating,
      totalReviews: google?.totalReviews,
      mapsUrl: showGoogle ? mapsUrl.trim() : '',
    );
  }

  final List<WebsiteSectionQuote> quotes;

  /// The store's score in Google; `null` hides the score column's number.
  final double? rating;
  final int? totalReviews;

  /// The business on Google Maps, for «Ver en Google Maps» ('' hides it).
  final String mapsUrl;

  /// The line under the score: the block's own note, or how many reviews.
  String note(String own) {
    if (own.trim().isNotEmpty) return own.trim();
    final total = totalReviews;
    if (total == null || total <= 0) return '';
    return total == 1 ? '1 reseña en Google.' : '$total reseñas en Google.';
  }

  static int? _rating(Object? raw) {
    final value = raw is num ? raw.round() : int.tryParse('$raw'.trim());
    if (value == null) return null;
    return value.clamp(1, 5);
  }

  static String _capitalized(String text) => text.isEmpty
      ? text
      : '${text.substring(0, 1).toUpperCase()}${text.substring(1)}';
}

/// A link of a call to action: its label, where it goes, and whether that is
/// the store's WhatsApp (drawn with the chat mark).
typedef WebsiteSectionAction = ({String label, String href, bool whatsapp});

/// The call to action's two buttons. The main one empty opens the store's
/// WhatsApp (or its contact page when it has none); the second one empty
/// opens the business's map, and without a map or a label it is not drawn.
({WebsiteSectionAction? primary, WebsiteSectionAction? secondary})
websiteCtaActions(
  Map<String, dynamic> data, {
  required String whatsappHref,
  required String mapsUrl,
}) {
  final primaryLabel = websiteSectionText(data, const [
    'buttonText',
    'ctaText',
    'label',
  ]).trim();
  final storedPrimary = websiteSectionText(data, const [
    'buttonLink',
    'ctaLink',
    'link',
  ]).trim();
  final primaryHref = storedPrimary.isNotEmpty
      ? storedPrimary
      : whatsappHref.isNotEmpty
      ? whatsappHref
      : '/contacto';
  final secondaryLabel = websiteSectionText(data, const [
    'secondaryText',
  ]).trim();
  final storedSecondary = websiteSectionText(data, const [
    'secondaryLink',
  ]).trim();
  final secondaryHref = storedSecondary.isNotEmpty
      ? storedSecondary
      : mapsUrl.trim();
  return (
    primary: primaryLabel.isEmpty
        ? null
        : (
            label: primaryLabel,
            href: primaryHref,
            whatsapp: websiteIsWhatsappHref(primaryHref),
          ),
    secondary: secondaryLabel.isEmpty || secondaryHref.isEmpty
        ? null
        : (
            label: secondaryLabel,
            href: secondaryHref,
            whatsapp: websiteIsWhatsappHref(secondaryHref),
          ),
  );
}

/// Whether [href] opens a WhatsApp chat (`wa.me`, `whatsapp.com` or the
/// `whatsapp:` scheme).
bool websiteIsWhatsappHref(String href) {
  final uri = Uri.tryParse(href.trim());
  if (uri == null) return false;
  if (uri.scheme == 'whatsapp') return true;
  final host = uri.host.toLowerCase();
  return host == 'wa.me' ||
      host == 'whatsapp.com' ||
      host.endsWith('.whatsapp.com');
}

/// Where a figure of a stats block takes its number from (`source`): what
/// the operator wrote, or the store's Google score or review count from the
/// sync, which keeps it current and never claims a number the store does not
/// have.
abstract final class WebsiteStatsSource {
  static const written = 'written';
  static const googleRating = 'google_rating';
  static const googleReviews = 'google_reviews';
}

/// One figure of a stats block as it is drawn: the number, the mark beside
/// it, and whether the number comes from Google ([live]: it is read, not
/// written in place).
typedef WebsiteStatsFigure = ({String value, String suffix, bool live});

/// What [metric] shows. A Google figure the sync has not brought yet shows
/// what is written in it.
WebsiteStatsFigure websiteStatsFigure(
  Map<String, dynamic> metric, {
  required String Function(String key) setting,
}) {
  final written = websiteSectionText(metric, const ['value']);
  final suffix = websiteSectionText(metric, const ['suffix']);
  final source = metric['source']?.toString().trim() ?? '';
  if (source == WebsiteStatsSource.googleRating ||
      source == WebsiteStatsSource.googleReviews) {
    final google = WebsiteGoogleReviewsContent.fromData(
      WebsiteGoogleReviewsContent.withSyncedReviews(
        const <String, dynamic>{},
        setting,
      ),
    );
    final rating = google.rating;
    final total = google.totalReviews;
    if (source == WebsiteStatsSource.googleRating && rating != null) {
      return (value: websiteRatingLabel(rating), suffix: suffix, live: true);
    }
    if (source == WebsiteStatsSource.googleReviews &&
        total != null &&
        total > 0) {
      return (value: websiteCountLabel(total), suffix: suffix, live: true);
    }
  }
  return (value: written, suffix: suffix, live: false);
}

/// A count as a Chilean writes it: thousands with a point (1.234).
String websiteCountLabel(int count) {
  final digits = count.abs().toString();
  final grouped = StringBuffer(count < 0 ? '-' : '');
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) grouped.write('.');
    grouped.write(digits[index]);
  }
  return grouped.toString();
}

/// How many columns a stats block's figures take: up to four in a row on a
/// desktop, two on a tablet or a phone (one when there is only one).
int websiteStatsColumns(int count, {required bool desktop}) {
  if (count <= 1) return 1;
  return desktop ? (count < 4 ? count : 4) : 2;
}

/// Whether a plans block lays its [count] plans side by side in a content
/// column [width] wide: each needs 260, otherwise they are stacked cards.
bool websitePlansSideBySide(int count, double width) =>
    count > 0 && width / count >= 260;
