import 'dart:convert';

/// One review a reviews block shows, with its rating already read.
typedef WebsiteGoogleReview = ({Map<String, dynamic> data, int rating});

/// What a Google reviews block shows, read once for Flutter's
/// `GoogleReviewsCarousel` and the HTML storefront.
class WebsiteGoogleReviewsContent {
  const WebsiteGoogleReviewsContent({
    required this.reviews,
    required this.rating,
    required this.totalReviews,
  });

  /// The block's data with the store's synced Google reviews put in when it
  /// has none of its own (`google_reviews_data`, `google_reviews_rating`,
  /// `google_reviews_total`), as `WebsiteBlockRenderer` does.
  static Map<String, dynamic> withSyncedReviews(
    Map<String, dynamic> data,
    String Function(String key) setting,
  ) {
    var effective = data;
    final json = setting('google_reviews_data');
    final syncedRating = setting('google_reviews_rating');
    final syncedTotal = setting('google_reviews_total');
    if ((data['reviews'] as List?)?.isEmpty ?? true) {
      if (json.isNotEmpty) {
        try {
          final list = jsonDecode(json) as List;
          effective = Map<String, dynamic>.from(data)
            ..['reviews'] = [
              for (final review in list) Map<String, dynamic>.from(review),
            ];
        } on Object {
          // A setting that is not a list of reviews shows none.
        }
      }
    }
    if (syncedRating.isNotEmpty || syncedTotal.isNotEmpty) {
      effective = Map<String, dynamic>.from(effective);
      if (syncedRating.isNotEmpty && effective['rating'] == null) {
        effective['rating'] = syncedRating;
      }
      if (syncedTotal.isNotEmpty && effective['totalReviews'] == null) {
        effective['totalReviews'] = syncedTotal;
      }
    }
    return effective;
  }

  /// Only what Google really returned, filtered by the block's own
  /// `minRating` (1–5, 4 by default) and `maxItems` (1–20, 8), in source
  /// order. A review whose rating cannot be read is not shown. The aggregate
  /// is an explicit value when there is one, otherwise the average of the
  /// COMPLETE list, so narrowing the cards cannot inflate it.
  factory WebsiteGoogleReviewsContent.fromData(Map<String, dynamic> data) {
    final source = sourceReviews(data);
    final minRating = _clamped(data['minRating'], fallback: 4, min: 1, max: 5);
    final maxItems = _clamped(data['maxItems'], fallback: 8, min: 1, max: 20);
    final visible = <WebsiteGoogleReview>[];
    for (final review in source) {
      final rating = reviewRating(review);
      if (rating == null || rating < minRating) continue;
      visible.add((data: review, rating: rating));
      if (visible.length == maxItems) break;
    }
    return WebsiteGoogleReviewsContent(
      reviews: List.unmodifiable(visible),
      rating:
          _readDouble(data['rating']) ??
          _readDouble(data['google_rating']) ??
          _average(source),
      totalReviews:
          _readInt(data['totalReviews']) ??
          _readInt(data['user_ratings_total']) ??
          _readInt(data['reviewsTotal']),
    );
  }

  final List<WebsiteGoogleReview> reviews;

  /// `null` when there is no score to show: a 0,0 with empty stars would be
  /// a score the shop never got.
  final double? rating;
  final int? totalReviews;

  /// Every review Google returned, in its order, never completed with
  /// samples.
  static List<Map<String, dynamic>> sourceReviews(Map<String, dynamic> data) {
    final raw = data['reviews'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return [
      for (final review in raw)
        if (review is Map) Map<String, dynamic>.from(review),
    ];
  }

  /// One review's stars: the numeric `rating` or Google Business's
  /// `starRating` (`FIVE`…`ONE`); `null` when it cannot be read.
  static int? reviewRating(Map<String, dynamic> review) {
    final raw = review['rating'] ?? review['starRating'];
    if (raw is num) return raw.round();
    if (raw is String) {
      switch (raw.trim().toUpperCase()) {
        case 'FIVE':
          return 5;
        case 'FOUR':
          return 4;
        case 'THREE':
          return 3;
        case 'TWO':
          return 2;
        case 'ONE':
          return 1;
      }
      final numeric = num.tryParse(raw.trim());
      if (numeric != null) return numeric.round();
    }
    return null;
  }

  /// The reviewer's name (`author_name` or `reviewer.displayName`).
  static String authorName(Map<String, dynamic> review) =>
      (review['author_name'] ??
              (review['reviewer'] as Map?)?['displayName'] ??
              'Usuario')
          .toString();

  /// The reviewer's photo (`photo_url` or `reviewer.profilePhotoUrl`).
  static String? photoUrl(Map<String, dynamic> review) =>
      (review['photo_url'] ?? (review['reviewer'] as Map?)?['profilePhotoUrl'])
          ?.toString();

  /// The review's words, or Flutter's line for a rating without them.
  static String text(Map<String, dynamic> review) {
    final words = (review['text'] ?? review['comment'] ?? '').toString().trim();
    return words.isNotEmpty ? words : 'Calificación publicada en Google.';
  }

  /// `relative_time`, or Flutter's own words from `createTime`/`updateTime`
  /// measured against [now].
  static String relativeTime(Map<String, dynamic> review, DateTime now) {
    final given = (review['relative_time'] ?? '').toString();
    if (given.isNotEmpty) return given;
    final created = review['createTime'] ?? review['updateTime'];
    if (created == null) return '';
    try {
      final diff = now.difference(DateTime.parse(created.toString()));
      if (diff.inDays > 30) return 'hace ${diff.inDays ~/ 30} meses';
      if (diff.inDays > 0) return 'hace ${diff.inDays} días';
      return 'hace ${diff.inHours} horas';
    } on Object {
      return '';
    }
  }

  static double? _average(List<Map<String, dynamic>> reviews) {
    var total = 0;
    var counted = 0;
    for (final review in reviews) {
      final rating = reviewRating(review);
      if (rating == null) continue;
      total += rating;
      counted++;
    }
    return counted == 0 ? null : total / counted;
  }

  static int _clamped(
    Object? raw, {
    required int fallback,
    required int min,
    required int max,
  }) {
    final value = _readInt(raw) ?? fallback;
    return value < min ? min : (value > max ? max : value);
  }

  static double? _readDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }
}
