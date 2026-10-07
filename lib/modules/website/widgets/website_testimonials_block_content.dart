import 'package:flutter/material.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_type.dart';
import 'package:vinabike_public_core/modules/website/models/website_section_content.dart';
import 'package:vinabike_public_core/modules/website/theme/website_section_palette.dart';

import 'website_block_content_presenters.dart';
import 'website_section_frame.dart';

/// Shared visitor content for the Website Builder Testimonials block: the
/// store's score in Google (from the reviews sync, never a number written by
/// hand) with its stars and the link to its profile, beside the quotes — the
/// block's own or, when it has none, up to three synced Google reviews with
/// words (`WebsiteTestimonialsContent`). One column under 1024. The HTML
/// storefront draws the same (`TestimonialsSectionView`).
class WebsiteTestimonialsBlockContent extends StatelessWidget {
  const WebsiteTestimonialsBlockContent({
    super.key,
    required this.data,
    required this.primaryColor,
    required this.accentColor,
    this.setting,
    this.mapsUrl = '',
    this.headingFont,
    this.bodyFont,
    this.presenters,
    this.onNavigate,
    this.isNavigationEligible,
    this.padding,
    this.paintSurface = true,
  });

  static const rootKey = ValueKey<String>('website-testimonials-content-root');
  static const scoreKey = ValueKey<String>('website-testimonials-score');
  static const ratingKey = ValueKey<String>('website-testimonials-rating');
  static const collectionKey =
      ValueKey<String>('website-testimonials-collection');

  static ValueKey<String> testimonialKey(int position) =>
      ValueKey<String>('website-testimonial-$position');

  static const _collection = <String>['testimonials', 'items'];

  final Map<String, dynamic> data;
  final Color primaryColor;
  final Color accentColor;

  /// The store's settings (the synced Google reviews); `null` shows none.
  final String Function(String key)? setting;

  /// The business on Google Maps, for «Ver en Google Maps».
  final String mapsUrl;
  final String? headingFont;
  final String? bodyFont;
  final WebsiteBlockContentPresenters? presenters;
  final void Function(String route)? onNavigate;
  final bool Function(String href)? isNavigationEligible;

  /// The padding the operator set; `null` keeps the design's.
  final EdgeInsetsGeometry? padding;
  final bool paintSurface;

  @override
  Widget build(BuildContext context) {
    final content = WebsiteTestimonialsContent.resolve(
      data,
      setting: setting ?? (_) => '',
      mapsUrl: mapsUrl,
    );
    return KeyedSubtree(
      key: rootKey,
      child: WebsiteSectionBand(
        tone: WebsiteSectionTone.of(WebsiteBlockType.testimonials, data),
        primaryColor: primaryColor,
        accentColor: accentColor,
        headingFont: headingFont,
        bodyFont: bodyFont,
        padding: padding,
        paintSurface: paintSurface,
        builder: (context, scope) {
          final score = _score(context, scope, content);
          final quotes = content.quotes.isEmpty
              ? null
              : Column(
                  key: collectionKey,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (position, quote) in content.quotes.indexed)
                      _quote(context, scope, quote, position),
                  ],
                );
          if (scope.isDesktop) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 340, child: score),
                const SizedBox(width: 72),
                Expanded(child: quotes ?? const SizedBox.shrink()),
              ],
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              score,
              if (quotes != null) ...[const SizedBox(height: 12), quotes],
            ],
          );
        },
      ),
    );
  }

  Widget _score(
    BuildContext context,
    WebsiteSectionScope scope,
    WebsiteTestimonialsContent content,
  ) {
    final desktop = scope.isDesktop;
    final colors = scope.colors;
    final eyebrow = websiteSectionText(data, const ['eyebrow']);
    final title = websiteSectionText(data, const ['title']);
    final ownNote = websiteSectionText(data, const ['subtitle']);
    final note = content.note(ownNote);
    final rating = content.rating;
    final mapsHref = content.mapsUrl;
    final showLink = rating != null &&
        mapsHref.isNotEmpty &&
        !scope.isPhone &&
        (isNavigationEligible?.call(mapsHref) ?? true);
    final noteWidget = note.isEmpty
        ? null
        : websiteSectionSlot(
            context,
            presenters,
            WebsiteInlineTextSlot(
              id: 'testimonials.subtitle',
              value: ownNote.trim().isEmpty ? note : ownNote,
              valueKeys: const <String>['subtitle'],
              baseStyle: scope.body(
                desktop ? 17 : 15,
                color: colors.muted,
              ),
              formatting: websiteSectionFormatting(data['subtitleFormatting']),
              formattingKeys: const <String>['subtitleFormatting'],
              placeholder: 'Nota',
              displayTransform: (value) => value.trim(),
            ),
          );
    final number = rating == null
        ? null
        : Text(
            websiteRatingLabel(rating),
            key: ratingKey,
            style: scope.heading(
              desktop ? 148 : 96,
              height: 0.9,
              color: colors.mark,
            ),
          );
    final stars = rating == null
        ? null
        : _Stars(
            rating: rating,
            size: desktop ? 26 : 20,
            gap: desktop ? 4 : 3,
            fill: colors.accent,
            empty: colors.rule,
          );
    return Column(
      key: scoreKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow.trim().isNotEmpty) ...[
          WebsiteSectionEyebrow(
            scope: scope,
            text: eyebrow,
            id: 'testimonials.eyebrow',
            presenters: presenters,
          ),
          SizedBox(height: scope.isPhone ? 14 : 18),
        ],
        if (title.trim().isNotEmpty) ...[
          websiteSectionSlot(
            context,
            presenters,
            WebsiteInlineTextSlot(
              id: 'testimonials.title',
              value: title,
              valueKeys: const <String>['title'],
              baseStyle: scope.heading(scope.metrics.titleSize),
              formatting: websiteSectionFormatting(data['titleFormatting']),
              formattingKeys: const <String>['titleFormatting'],
              placeholder: 'Título',
              displayTransform: (value) => value.trim().toUpperCase(),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (number != null && desktop) ...[
          number,
          const SizedBox(height: 22),
          stars!,
          if (noteWidget != null) ...[const SizedBox(height: 14), noteWidget],
        ] else if (number != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              number,
              const SizedBox(width: 16),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: stars!,
                      ),
                      if (noteWidget != null) ...[
                        const SizedBox(height: 8),
                        noteWidget,
                      ],
                    ],
                  ),
                ),
              ),
            ],
          )
        else if (noteWidget != null)
          noteWidget,
        if (showLink) ...[
          const SizedBox(height: 18),
          _MapsLink(
            label: 'Ver en Google Maps',
            style: scope.body(
              15,
              height: 1.2,
              weight: FontWeight.w600,
              color: colors.mark,
              letterSpacing: 15 * 0.04,
            ),
            onPressed: presenters != null || onNavigate == null
                ? null
                : () => onNavigate!(mapsHref),
          ),
        ],
      ],
    );
  }

  Widget _quote(
    BuildContext context,
    WebsiteSectionScope scope,
    WebsiteSectionQuote quote,
    int position,
  ) {
    final desktop = scope.isDesktop;
    final colors = scope.colors;
    final own = quote.index != null;
    final target = own
        ? websiteSectionTarget(
            const <String, dynamic>{},
            index: quote.index!,
            collectionKeys: _collection,
          )
        : null;
    final textStyle = scope.body(
      desktop ? 26 : 20,
      height: 1.4,
      weight: FontWeight.w500,
      letterSpacing: desktop ? -0.13 : null,
    );
    final text = own
        ? websiteSectionSlot(
            context,
            presenters,
            WebsiteInlineTextSlot(
              id: 'testimonials.item.${quote.index}.comment',
              value: quote.text,
              valueKeys: const <String>['comment', 'quote', 'text'],
              baseStyle: textStyle,
              placeholder: 'Lo que dijo el cliente',
              displayTransform: (value) => '“${value.trim()}”',
              repeaterTarget: target,
            ),
          )
        : Text('“${quote.text.trim()}”', style: textStyle);
    final name = own
        ? websiteSectionSlot(
            context,
            presenters,
            WebsiteInlineTextSlot(
              id: 'testimonials.item.${quote.index}.name',
              value: quote.name,
              valueKeys: const <String>['name'],
              baseStyle: scope.body(
                desktop ? 16 : 15,
                height: 1.4,
                weight: FontWeight.w600,
              ),
              placeholder: 'Nombre',
              repeaterTarget: target,
            ),
          )
        : Text(
            quote.name,
            style: scope.body(
              desktop ? 16 : 15,
              height: 1.4,
              weight: FontWeight.w600,
            ),
          );
    final meta = quote.meta.isEmpty
        ? null
        : Text(
            quote.meta,
            style: scope.body(
              desktop ? 15 : 14,
              height: 1.4,
              color: colors.muted,
            ),
          );
    final circle = desktop ? 40.0 : 36.0;
    return Container(
      key: testimonialKey(position),
      margin: EdgeInsets.only(top: desktop ? 0 : 28),
      padding:
          EdgeInsets.only(top: desktop ? 32 : 24, bottom: desktop ? 32 : 0),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.rule)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          text,
          SizedBox(height: desktop ? 20 : 16),
          Row(
            children: [
              Container(
                width: circle,
                height: circle,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.tint,
                  shape: BoxShape.circle,
                ),
                child: ExcludeSemantics(
                  child: Text(
                    quote.initial,
                    style: scope.heading(
                      desktop ? 17 : 15,
                      height: 1,
                      color: colors.mark,
                    ),
                  ),
                ),
              ),
              SizedBox(width: desktop ? 14 : 12),
              Expanded(
                child: desktop
                    ? Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 14,
                        runSpacing: 4,
                        children: [name, if (meta != null) meta],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [name, if (meta != null) meta],
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Five stars, the last one filled by the score's fraction.
class _Stars extends StatelessWidget {
  const _Stars({
    required this.rating,
    required this.size,
    required this.gap,
    required this.fill,
    required this.empty,
  });

  final double rating;
  final double size;
  final double gap;
  final Color fill;
  final Color empty;

  @override
  Widget build(BuildContext context) {
    final value = rating.clamp(0.0, 5.0);
    return Semantics(
      label: '${websiteRatingLabel(value)} de 5 estrellas',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < 5; index++) ...[
            if (index > 0) SizedBox(width: gap),
            SizedBox(
              width: size,
              height: size,
              child: Stack(
                children: [
                  Icon(Icons.star, size: size, color: empty),
                  ClipRect(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: (value - index).clamp(0.0, 1.0),
                      child: Icon(Icons.star, size: size, color: fill),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MapsLink extends StatelessWidget {
  const _MapsLink({
    required this.label,
    required this.style,
    required this.onPressed,
  });

  final String label;
  final TextStyle style;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12.5),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: style.color ?? Colors.black,
                width: 1.5,
              ),
            ),
          ),
          child: Text(label.toUpperCase(), style: style),
        ),
      ),
    );
  }
}
