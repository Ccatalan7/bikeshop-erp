import 'package:flutter/material.dart';

import 'text_formatting_toolbar.dart';

/// One review that passed the block's own filters, with the rating already
/// read once. Filter and stars therefore agree by construction.
typedef _VisibleReview = ({Map<String, dynamic> data, int rating});

class GoogleReviewsCarousel extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color primaryColor;
  final Color accentColor;
  final String? headingFont;
  final String? bodyFont;
  final bool previewMode;

  const GoogleReviewsCarousel({
    super.key,
    required this.data,
    required this.primaryColor,
    required this.accentColor,
    this.headingFont,
    this.bodyFont,
    this.previewMode = false,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Parse Settings
    final title =
        (data['title'] ?? 'Lo que dicen nuestros clientes').toString();
    final titleFormatting = _resolveFormatting(data['titleFormatting']);
    final backgroundColor = _parseColor(data['backgroundColor']);
    final isDark =
        backgroundColor != null && backgroundColor.computeLuminance() < 0.5;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;

    // 2. Reviews: only what Google really returned, filtered by the block's
    // own settings. An empty source stays empty — no sample people.
    final reviews = _visibleReviews();
    // The aggregate is business truth: an explicit value wins, and the
    // computed fallback reads the COMPLETE real list, so narrowing the cards
    // with `minRating`/`maxItems` cannot inflate the score.
    final displayedRating = _readDouble(data['rating']) ??
        _readDouble(data['google_rating']) ??
        _averageRating(_sourceReviews());
    final totalReviews = _readInt(data['totalReviews']) ??
        _readInt(data['user_ratings_total']) ??
        _readInt(data['reviewsTotal']);

    return Container(
      width: double.infinity,
      color: backgroundColor ?? Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                Text(
                  title.toUpperCase(),
                  style: titleFormatting.applyTo(
                    TextStyle(
                      fontFamily: headingFont,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: textColor,
                      height: 1.2,
                    ),
                  ),
                  // Same alignment semantics as every other block: persisted
                  // formatting wins, and `start` means "not set".
                  textAlign: titleFormatting.textAlign == TextAlign.start
                      ? TextAlign.center
                      : titleFormatting.textAlign,
                ),
                // Without an aggregate there is nothing true to show: a 0,0
                // with five empty stars would be a score the shop never got.
                if (displayedRating != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayedRating.toStringAsFixed(1),
                        style: TextStyle(
                          fontFamily: bodyFont,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        children: List.generate(5, (index) {
                          return Icon(
                            index < displayedRating.round()
                                ? Icons.star
                                : Icons.star_border,
                            color: const Color(0xFFFBBC04),
                            size: 20,
                          );
                        }),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        totalReviews == null
                            ? 'en Google'
                            : 'en Google ($totalReviews reseñas)',
                        style: TextStyle(
                          fontFamily: bodyFont,
                          fontSize: 16,
                          color: subTextColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Scrollable List. The same geometry as always; with nothing real to
          // show it simply does not mount.
          if (reviews.isNotEmpty) ...[
            const SizedBox(height: 48),
            SizedBox(
              height: 280,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                scrollDirection: Axis.horizontal,
                itemCount: reviews.length,
                separatorBuilder: (c, i) => const SizedBox(width: 24),
                itemBuilder: (context, index) {
                  final review = reviews[index];
                  return _ReviewCard(
                    review: review.data,
                    rating: review.rating,
                    bodyFont: bodyFont,
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Every review Google really returned, in the order it returned them.
  ///
  /// The source is never sorted, never mutated and never completed with
  /// samples: an empty or absent list is an empty list.
  List<Map<String, dynamic>> _sourceReviews() {
    final rawList = data['reviews'];
    if (rawList is! List) return const <Map<String, dynamic>>[];
    return rawList
        .whereType<Map>()
        .map((review) => Map<String, dynamic>.from(review))
        .toList(growable: false);
  }

  /// The reviews this block actually shows.
  ///
  /// `minRating` and `maxItems` are the block's own business filters: keep the
  /// reviews that reach the minimum score, in source order, up to the visible
  /// limit. A review whose rating cannot be read is not shown, because nothing
  /// proves it reaches the minimum the shop asked for.
  List<_VisibleReview> _visibleReviews() {
    final minRating = _clampedSetting(
      data['minRating'],
      fallback: 4,
      min: 1,
      max: 5,
    );
    final maxItems = _clampedSetting(
      data['maxItems'],
      fallback: 8,
      min: 1,
      max: 20,
    );

    final visible = <_VisibleReview>[];
    for (final review in _sourceReviews()) {
      final rating = _ratingOf(review);
      if (rating == null || rating < minRating) continue;
      visible.add((data: review, rating: rating));
      if (visible.length == maxItems) break;
    }
    return List<_VisibleReview>.unmodifiable(visible);
  }

  /// Average of the ratings that can be read, over the COMPLETE real list.
  ///
  /// Returns null when there is no readable rating: an average of nothing is
  /// not zero stars.
  double? _averageRating(List<Map<String, dynamic>> reviews) {
    var total = 0;
    var counted = 0;
    for (final review in reviews) {
      final rating = _ratingOf(review);
      if (rating == null) continue;
      total += rating;
      counted++;
    }
    if (counted == 0) return null;
    return total / counted;
  }

  static int _clampedSetting(
    Object? raw, {
    required int fallback,
    required int min,
    required int max,
  }) {
    final value = _readInt(raw) ?? fallback;
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  static TextFormatting _resolveFormatting(Object? raw) {
    if (raw is! Map) return const TextFormatting();
    return TextFormatting.fromJson(Map<String, dynamic>.from(raw));
  }

  static Color? _parseColor(dynamic value) {
    if (value == null) return null;
    final hex = value.toString();
    if (hex.isEmpty) return null;
    final buffer = StringBuffer();
    if (hex.length == 6 || hex.length == 7) buffer.write('ff');
    buffer.write(hex.replaceFirst('#', ''));
    try {
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return null;
    }
  }

  static double? _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  static int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  /// The star rating of ONE review, or null when the payload has none we can
  /// read.
  ///
  /// Both payload shapes are supported — the numeric `rating` and the Google
  /// Business enum `starRating` (`FIVE`…`ONE`). An unrecognised value stays
  /// unknown: promoting it to five stars would publish a score nobody gave.
  static int? _ratingOf(Map<String, dynamic> review) =>
      _parseRating(review['rating'] ?? review['starRating']);

  static int? _parseRating(Object? raw) {
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
}

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;

  /// Already read by the filter, so the stars cannot disagree with the reason
  /// this card is on screen.
  final int rating;
  final String? bodyFont;

  const _ReviewCard({
    required this.review,
    required this.rating,
    this.bodyFont,
  });

  @override
  Widget build(BuildContext context) {
    // Handle both mock format and real Google API format
    // Mock: author_name, photo_url, relative_time, rating, text
    // Google API: reviewer.displayName, reviewer.profilePhotoUrl, createTime, starRating (FIVE/FOUR/etc), comment

    // Extract author name
    final String authorName = review['author_name'] ??
        (review['reviewer'] as Map<String, dynamic>?)?['displayName'] ??
        'Usuario';

    // Extract photo URL (with fallback for missing photos)
    final String? photoUrl = review['photo_url'] ??
        (review['reviewer'] as Map<String, dynamic>?)?['profilePhotoUrl'];

    // Extract relative time or format create time
    String relativeTime = review['relative_time'] ?? '';
    if (relativeTime.isEmpty) {
      final createTime = review['createTime'] ?? review['updateTime'];
      if (createTime != null) {
        try {
          final date = DateTime.parse(createTime);
          final diff = DateTime.now().difference(date);
          if (diff.inDays > 30) {
            relativeTime = 'hace ${diff.inDays ~/ 30} meses';
          } else if (diff.inDays > 0) {
            relativeTime = 'hace ${diff.inDays} días';
          } else {
            relativeTime = 'hace ${diff.inHours} horas';
          }
        } catch (_) {
          relativeTime = '';
        }
      }
    }

    // Extract review text
    final String reviewText =
        (review['text'] ?? review['comment'] ?? '').toString().trim().isNotEmpty
            ? (review['text'] ?? review['comment']).toString().trim()
            : 'Calificación publicada en Google.';

    return Container(
      width: 320,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, 4),
            blurRadius: 12,
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Avatar + Name + G Logo
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundImage:
                    photoUrl != null ? NetworkImage(photoUrl) : null,
                backgroundColor: Colors.grey.shade200,
                child: photoUrl == null
                    ? Text(
                        authorName.isNotEmpty
                            ? authorName[0].toUpperCase()
                            : 'U',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.white),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      authorName,
                      style: TextStyle(
                        fontFamily: bodyFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (relativeTime.isNotEmpty)
                      Text(
                        relativeTime,
                        style: TextStyle(
                          fontFamily: bodyFont,
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
              ),
              // Google G Logo
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                child: Text(
                  'G',
                  style: TextStyle(
                    fontFamily: bodyFont,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    color: const Color(0xFF4285F4), // Google Blue
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Stars
          Row(
            children: List.generate(
              5,
              (index) => Icon(
                Icons.star,
                color: index < rating
                    ? const Color(0xFFFBBC04)
                    : Colors.grey.shade300,
                size: 16,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Text
          Expanded(
            child: Text(
              reviewText,
              style: TextStyle(
                fontFamily: bodyFont,
                fontSize: 14,
                color: Colors.black87,
                height: 1.5,
              ),
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
