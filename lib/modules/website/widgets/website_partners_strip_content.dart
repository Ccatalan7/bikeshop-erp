import 'package:flutter/material.dart';
import 'package:vinabike_public_core/modules/website/models/website_section_content.dart';
import 'package:vinabike_public_core/modules/website/theme/website_section_palette.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';

import 'website_block_content_presenters.dart';
import 'website_section_frame.dart';

/// Shared visitor content for the brands strip (`partnersBanner`): a low
/// band on the brand's deepest tone with the label in small capitals and the
/// names in a row in the heading font; over the block's photo, faded, when
/// it has one. The HTML storefront draws the same (`PartnersStripView`).
/// Without names it shows none: it never fills itself with samples.
class WebsitePartnersStripContent extends StatelessWidget {
  const WebsitePartnersStripContent({
    super.key,
    required this.data,
    required this.primaryColor,
    required this.accentColor,
    this.headingFont,
    this.bodyFont,
    this.presenters,
    this.padding,
    this.paintSurface = true,
    this.imageProviderBuilder,
  });

  static const rootKey = ValueKey<String>('website-partners-strip-root');
  static const labelKey = ValueKey<String>('website-partners-strip-label');

  static ValueKey<String> nameKey(int index) =>
      ValueKey<String>('website-partners-strip-name-$index');

  final Map<String, dynamic> data;
  final Color primaryColor;
  final Color accentColor;
  final String? headingFont;
  final String? bodyFont;
  final WebsiteBlockContentPresenters? presenters;

  /// The padding the operator set; `null` keeps the design's.
  final EdgeInsetsGeometry? padding;
  final bool paintSurface;
  final WebsiteSectionImageProviderBuilder? imageProviderBuilder;

  @override
  Widget build(BuildContext context) {
    final tones = websiteSectionTones(
      context,
      primary: primaryColor,
      accent: accentColor,
    );
    final surface = websiteSectionColor(tones.deeper);
    final ink = websiteSectionColor(WebsiteRgba.readableOn(tones.deeper));
    final label = websiteSectionText(data, const ['title']);
    final names = <(int, String)>[];
    final raw = data['items'];
    if (raw is List) {
      for (final (index, item) in raw.indexed) {
        final name = item is Map
            ? (item['label'] ?? item['text'] ?? '').toString()
            : item?.toString() ?? '';
        if (name.trim().isNotEmpty) names.add((index, name));
      }
    }
    final image = websiteSectionText(data, const ['imageUrl']).trim();
    return LayoutBuilder(
      key: rootKey,
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final phone =
            WebsiteSectionWidth.of(width) == WebsiteSectionWidth.phone;
        final resolved = padding?.resolve(Directionality.of(context)) ??
            (phone
                ? const EdgeInsets.symmetric(vertical: 32, horizontal: 20)
                : const EdgeInsets.symmetric(vertical: 44, horizontal: 32));
        final labelWidget = label.trim().isEmpty
            ? null
            : websiteSectionSlot(
                context,
                presenters,
                WebsiteInlineTextSlot(
                  id: 'partners.title',
                  value: label,
                  valueKeys: const <String>['title'],
                  baseStyle: TextStyle(
                    fontFamily: bodyFont,
                    fontSize: phone ? 11 : 12,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: (phone ? 11 : 12) * 0.18,
                    color: ink.withValues(alpha: 0.6),
                  ),
                  formatting: websiteSectionFormatting(data['titleFormatting']),
                  formattingKeys: const <String>['titleFormatting'],
                  placeholder: 'Etiqueta',
                  displayTransform: (value) => value.trim().toUpperCase(),
                ),
                key: labelKey,
              );
        final nameWidgets = [
          for (final (index, name) in names)
            websiteSectionSlot(
              context,
              presenters,
              WebsiteInlineTextSlot(
                id: 'partners.item.$index.label',
                value: name,
                valueKeys: const <String>['label', 'text'],
                baseStyle: TextStyle(
                  fontFamily: headingFont,
                  fontSize: phone ? 19 : 24,
                  height: 1.3,
                  fontWeight: FontWeight.w500,
                  letterSpacing: (phone ? 19 : 24) * 0.06,
                  color: ink.withValues(alpha: 0.86),
                ),
                placeholder: 'Marca',
                displayTransform: (value) => value.trim().toUpperCase(),
                repeaterTarget: WebsiteInlineRepeaterTarget(
                  collectionKeys: const <String>['items'],
                  itemIndex: index,
                ),
              ),
              key: nameKey(index),
            ),
        ];
        final content = phone
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (labelWidget != null) ...[
                    labelWidget,
                    const SizedBox(height: 16),
                  ],
                  Wrap(spacing: 24, runSpacing: 10, children: nameWidgets),
                ],
              )
            : Wrap(
                spacing: 48,
                runSpacing: 20,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (labelWidget != null) labelWidget,
                  ...nameWidgets
                ],
              );
        return Container(
          width: double.infinity,
          height: constraints.hasBoundedHeight ? constraints.maxHeight : null,
          color: paintSurface ? surface : Colors.transparent,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              if (image.isNotEmpty)
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.24,
                    child: websiteSectionMedia(
                      context,
                      presenters: presenters,
                      id: 'partners.image',
                      url: image,
                      valueKeys: const <String>['imageUrl'],
                      fallback: const SizedBox.shrink(),
                      semanticLabel: websiteSectionText(data, const [
                        'imageAltText',
                      ]).trim(),
                      alignment: websiteSectionFocal(data),
                      imageProviderBuilder: imageProviderBuilder,
                    ),
                  ),
                ),
              Padding(
                padding: resolved,
                child: Align(
                  alignment: constraints.hasBoundedHeight
                      ? Alignment.center
                      : Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: WebsiteSectionMetrics.contentMaxWidth,
                    ),
                    child: SizedBox(width: double.infinity, child: content),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
