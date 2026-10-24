import 'package:flutter/material.dart';
import 'package:vinabike_public_core/modules/website/models/website_google_reviews.dart';

import 'text_formatting_toolbar.dart';

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

  /// The block's own fill when its surface takes the background over
  /// (transparent): the surface paints it, and [surfacePaint] is what it
  /// paints behind the words.
  final Color? backgroundColorOverride;

  /// What the surface that took the background over puts behind the words
  /// (`WebsiteBlockSurfaceStyle.paintedColor`); `null` when it paints none
  /// and the page shows through.
  final Color? surfacePaint;

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
    this.surfacePaint,
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
    // The ink reads on what is really behind the words: the surface's paint
    // when it took the background over (the override is only the block's
    // own fill made transparent), else the block's own color; over the
    // page when either is translucent.
    final behind = backgroundColorOverride == null
        ? authoredBackgroundColor
        : surfacePaint;
    final ink = _inkFor(
      theme,
      behind == null ? null : Color.alphaBlend(behind, scheme.surface),
    );
    final textColor = ink.ink;
    final subTextColor = ink.mutedInk;

    // 2. Reviews: only what Google really returned, filtered by the block's
    // own settings, and the aggregate (`WebsiteGoogleReviewsContent`, shared
    // with the HTML storefront).
    final content = WebsiteGoogleReviewsContent.fromData(data);
    final reviews = content.reviews;
    final displayedRating = content.rating;
    final totalReviews = content.totalReviews;

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
    // Both payloads (the synced Google Business one and the older mock one)
    // are read by the shared owner.
    final authorName = WebsiteGoogleReviewsContent.authorName(review);
    final photoUrl = WebsiteGoogleReviewsContent.photoUrl(review);
    final relativeTime =
        WebsiteGoogleReviewsContent.relativeTime(review, DateTime.now());
    final reviewText = WebsiteGoogleReviewsContent.text(review);

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
