import 'package:flutter/material.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_type.dart';
import 'package:vinabike_public_core/modules/website/models/website_section_content.dart';
import 'package:vinabike_public_core/modules/website/theme/website_section_palette.dart';

import 'website_block_content_presenters.dart';
import 'website_section_frame.dart';

/// Shared visitor content for the Website Builder Services block, the shop's
/// price list: the ruled header, then each service as a numbered row with
/// its detail and its price to the right, and the shop's photo beside them
/// on a desktop. A phone drops the numbers. The HTML storefront draws the
/// same (`ServicesSectionView`).
///
/// `services` is canonical and `items` a persisted alias; Edit replaces the
/// texts and the photo where they are.
class WebsiteServicesBlockContent extends StatelessWidget {
  const WebsiteServicesBlockContent({
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

  static const rootKey = ValueKey<String>('website-services-root');
  static const collectionKey = ValueKey<String>('website-services-collection');
  static const figureKey = ValueKey<String>('website-services-figure');

  static ValueKey<String> rowKey(int index) =>
      ValueKey<String>('website-services-row-$index');

  static ValueKey<String> numberKey(int index) =>
      ValueKey<String>('website-services-number-$index');

  static ValueKey<String> itemTitleKey(int index) =>
      ValueKey<String>('website-services-item-title-$index');

  static ValueKey<String> itemDescriptionKey(int index) =>
      ValueKey<String>('website-services-item-description-$index');

  static ValueKey<String> itemPriceKey(int index) =>
      ValueKey<String>('website-services-item-price-$index');

  static const _collection = <String>['services', 'items'];

  final Map<String, dynamic> data;
  final Color primaryColor;
  final Color accentColor;
  final String? headingFont;
  final String? bodyFont;
  final WebsiteBlockContentPresenters? presenters;

  /// The padding the operator set; `null` keeps the design's.
  final EdgeInsetsGeometry? padding;
  final bool paintSurface;

  /// Allows focused widget tests to exercise media without network access.
  final WebsiteSectionImageProviderBuilder? imageProviderBuilder;

  @override
  Widget build(BuildContext context) {
    final services = websiteSectionItems(data, 'services', const ['items']);
    return KeyedSubtree(
      key: rootKey,
      child: WebsiteSectionBand(
        tone: WebsiteSectionTone.of(WebsiteBlockType.services, data),
        primaryColor: primaryColor,
        accentColor: accentColor,
        headingFont: headingFont,
        bodyFont: bodyFont,
        padding: padding,
        paintSurface: paintSurface,
        builder: (context, scope) {
          final header = WebsiteSectionHeader(
            scope: scope,
            data: data,
            idPrefix: 'services',
            presenters: presenters,
            ruled: true,
          );
          final image = websiteSectionText(data, const ['imageUrl']).trim();
          // Edit, Preview and the store share one geometry: the photo is
          // there when the block has one (it is chosen in the inspector).
          final showFigure = scope.isDesktop && image.isNotEmpty;
          final list = Column(
            key: collectionKey,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (position, (index, item)) in services.indexed)
                _row(context, scope, item, index, position),
            ],
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!header.isEmpty) header,
              const SizedBox(height: 8),
              if (showFigure)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: list),
                    const SizedBox(width: 56),
                    Padding(
                      padding: const EdgeInsets.only(top: 30),
                      child: SizedBox(
                        key: figureKey,
                        width: 420,
                        child: _figure(context, scope, image),
                      ),
                    ),
                  ],
                )
              else
                list,
            ],
          );
        },
      ),
    );
  }

  Widget _row(
    BuildContext context,
    WebsiteSectionScope scope,
    Map<String, dynamic> item,
    int index,
    int position,
  ) {
    final phone = scope.isPhone;
    final target = websiteSectionTarget(
      item,
      index: index,
      collectionKeys: _collection,
    );
    final name = websiteSectionText(item, const ['title']);
    final detail = websiteSectionText(item, const ['description']);
    final price = websiteSectionText(item, const ['price']);
    return Container(
      key: rowKey(index),
      padding: EdgeInsets.symmetric(vertical: phone ? 18 : 22),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scope.colors.rule)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          if (!phone) ...[
            SizedBox(
              width: 44,
              child: Text(
                (position + 1).toString().padLeft(2, '0'),
                key: numberKey(index),
                style: scope.heading(15, height: 1).copyWith(
                      color: scope.colors.muted,
                      letterSpacing: 15 * 0.06,
                    ),
              ),
            ),
            const SizedBox(width: 20),
          ],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                websiteSectionSlot(
                  context,
                  presenters,
                  WebsiteInlineTextSlot(
                    id: 'services.item.$index.title',
                    value: name,
                    valueKeys: const <String>['title'],
                    baseStyle: scope.body(
                      phone ? 17 : 19,
                      height: 1.3,
                      weight: FontWeight.w600,
                    ),
                    formatting: websiteSectionFormatting(
                      item['titleFormatting'],
                    ),
                    formattingKeys: const <String>['titleFormatting'],
                    placeholder: 'Servicio',
                    repeaterTarget: target,
                  ),
                  key: itemTitleKey(index),
                ),
                if (detail.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  websiteSectionSlot(
                    context,
                    presenters,
                    WebsiteInlineTextSlot(
                      id: 'services.item.$index.description',
                      value: detail,
                      valueKeys: const <String>['description'],
                      baseStyle: scope.body(
                        phone ? 14 : 15,
                        height: 1.45,
                        color: scope.colors.muted,
                      ),
                      formatting: websiteSectionFormatting(
                        item['descriptionFormatting'],
                      ),
                      formattingKeys: const <String>['descriptionFormatting'],
                      placeholder: 'Detalle',
                      displayTransform: (value) => value.trim(),
                      repeaterTarget: target,
                    ),
                    key: itemDescriptionKey(index),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: phone ? 16 : 20),
          if (price.trim().isNotEmpty)
            websiteSectionSlot(
              context,
              presenters,
              WebsiteInlineTextSlot(
                id: 'services.item.$index.price',
                value: price,
                valueKeys: const <String>['price'],
                baseStyle: scope.heading(phone ? 22 : 26, height: 1),
                formatting: websiteSectionFormatting(item['priceFormatting']),
                formattingKeys: const <String>['priceFormatting'],
                placeholder: r'$0',
                displayTransform: (value) => value.trim(),
                repeaterTarget: target,
              ),
              key: itemPriceKey(index),
            ),
        ],
      ),
    );
  }

  Widget _figure(
    BuildContext context,
    WebsiteSectionScope scope,
    String image,
  ) {
    final caption = websiteSectionText(data, const ['caption']).trim();
    final captionDetail = websiteSectionText(data, const [
      'captionDetail',
    ]).trim();
    final alt = websiteSectionText(data, const ['imageAltText']).trim();
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        color: scope.colors.tint,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Icon(
          Icons.add_photo_alternate_outlined,
          color: scope.colors.mark,
        ),
      ),
    );
    final style = scope.body(14, height: 1.4, color: scope.colors.muted);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 4 / 5,
          child: websiteSectionMedia(
            context,
            presenters: presenters,
            id: 'services.image',
            url: image,
            valueKeys: const <String>['imageUrl'],
            fallback: fallback,
            semanticLabel: alt.isNotEmpty ? alt : 'Foto del taller',
            alignment: websiteSectionFocal(data),
            borderRadius: BorderRadius.circular(6),
            imageProviderBuilder: imageProviderBuilder,
          ),
        ),
        if (caption.isNotEmpty || captionDetail.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(caption, style: style)),
              const SizedBox(width: 16),
              Text(captionDetail, style: style),
            ],
          ),
        ],
      ],
    );
  }
}
