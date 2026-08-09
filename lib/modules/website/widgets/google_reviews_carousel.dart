import 'package:flutter/material.dart';

import 'text_formatting_toolbar.dart';

/// One review that passed the block's own filters, with the rating already
/// read once. Filter and stars therefore agree by construction.
typedef _VisibleReview = ({Map<String, dynamic> data, int rating});

/// The only two colours in this block that are NOT the storefront's.
///
/// They identify Google itself — the star gold and the wordmark blue — so they
/// stay literal on purpose and are named as brand. Everything else (surfaces,
/// ink, borders, shadow) resolves through the storefront theme, which is what
/// `Website Builder Responsive Authoring` t11 requires of every consumer in
/// `lib/modules/website`.
abstract final class _GoogleBrand {
  static const Color star = Color(0xFFFBBC04);
  static const Color wordmark = Color(0xFF4285F4);
}

/// The ink pair legible on the surface this block actually paints.
///
/// The section keeps honouring an authored `backgroundColor`, so when that
/// colour's brightness disagrees with the host theme the scheme's inverse ink
/// is the legible one — by definition, since `inverseSurface` is the opposite
/// brightness. No literal, and no guessing.
({Color ink, Color mutedInk}) _inkFor(
  ThemeData theme,
  Color? authoredSurface,
) {
  final scheme = theme.colorScheme;
  if (authoredSurface == null) {
    return (ink: scheme.onSurface, mutedInk: scheme.onSurfaceVariant);
  }
  final authoredIsDark =
      ThemeData.estimateBrightnessForColor(authoredSurface) == Brightness.dark;
  if (authoredIsDark == (theme.brightness == Brightness.dark)) {
    return (ink: scheme.onSurface, mutedInk: scheme.onSurfaceVariant);
  }
  return (ink: scheme.onInverseSurface, mutedInk: scheme.onInverseSurface);
}

class GoogleReviewsCarousel extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color primaryColor;
  final Color accentColor;
  final String? headingFont;
  final String? bodyFont;
  final bool previewMode;
  final EdgeInsets? padding;
  final Color? backgroundColorOverride;

  const GoogleReviewsCarousel({
    super.key,
    required this.data,
    required this.primaryColor,
    required this.accentColor,
    this.headingFont,
    this.bodyFont,
    this.previewMode = false,
    this.padding,
    this.backgroundColorOverride,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Parse Settings
    final title =
        (data['title'] ?? 'Lo que dicen nuestros clientes').toString();
    final titleFormatting = _resolveFormatting(data['titleFormatting']);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final authoredBackgroundColor = _parseColor(data['backgroundColor']);
    final backgroundColor = backgroundColorOverride ?? authoredBackgroundColor;
    final ink = _inkFor(theme, backgroundColor);
    final textColor = ink.ink;
    final subTextColor = ink.mutedInk;

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
      color: backgroundColor ?? scheme.surface,
      padding: padding ?? const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Header
          Padding(
            padding: padding == null
                ? const EdgeInsets.symmetric(horizontal: 24)
                : EdgeInsets.zero,
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
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Text(
                        displayedRating.toStringAsFixed(1),
                        style: TextStyle(
                          fontFamily: bodyFont,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          // The aggregate is the shop's own headline number:
                          // it wears the storefront's primary, which this
                          // block received and never used.
                          color: primaryColor,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(5, (index) {
                          return Icon(
                            index < displayedRating.round()
                                ? Icons.star
                                : Icons.star_border,
                            color: _GoogleBrand.star,
                            size: 20,
                          );
                        }),
                      ),
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
                padding: padding == null
                    ? const EdgeInsets.symmetric(horizontal: 24)
                    : EdgeInsets.zero,
                scrollDirection: Axis.horizontal,
                itemCount: reviews.length,
                separatorBuilder: (c, i) => const SizedBox(width: 24),
                itemBuilder: (context, index) {
                  final review = reviews[index];
                  return _ReviewCard(
                    review: review.data,
                    rating: review.rating,
                    bodyFont: bodyFont,
                    accentColor: accentColor,
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

  /// The storefront's accent, used for the reviewer's monogram so a card with
  /// no photo still belongs to this shop instead of a grey plate.
  final Color accentColor;

  const _ReviewCard({
    required this.review,
    required this.rating,
    required this.accentColor,
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

    // Same geometry and the same shadow strength as before; only the source of
    // each colour changed, from literal to the storefront's own scheme.
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 320,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.05),
            offset: const Offset(0, 4),
            blurRadius: 12,
          ),
        ],
        border: Border.all(color: scheme.outlineVariant),
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
                backgroundColor: accentColor,
                child: photoUrl == null
                    ? Text(
                        authorName.isNotEmpty
                            ? authorName[0].toUpperCase()
                            : 'U',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: scheme.onSecondary,
                        ),
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
                        color: scheme.onSurface,
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
                          color: scheme.onSurfaceVariant,
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
                    color: _GoogleBrand.wordmark,
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
                color:
                    index < rating ? _GoogleBrand.star : scheme.outlineVariant,
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
                color: scheme.onSurface,
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
