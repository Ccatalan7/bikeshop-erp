import 'package:flutter/material.dart';

import 'text_formatting_toolbar.dart';
import 'website_block_content_presenters.dart';

/// Shared visitor content for the About block.
///
/// Preview and Public render this widget directly. Edit injects optional
/// [presenters] around the same text and media slots; it does not own a second
/// layout tree.
class WebsiteAboutBlockContent extends StatelessWidget {
  const WebsiteAboutBlockContent({
    super.key,
    required this.data,
    this.headingFont,
    this.bodyFont,
    this.presenters,
    this.padding = const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
  });

  final Map<String, dynamic> data;
  final String? headingFont;
  final String? bodyFont;
  final WebsiteBlockContentPresenters? presenters;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final rawTitle = (data['title'] ?? 'Sobre Nosotros').toString();
    final title = rawTitle.trim().isEmpty ? 'Sobre Nosotros' : rawTitle.trim();
    final content = (data['content'] ?? data['description'] ?? '').toString();
    final imageUrl = _nonEmptyString(data['imageUrl'] ?? data['image']);
    final imageAltText = _nonEmptyString(data['imageAltText']);
    final imageOnLeft = data['imagePosition']?.toString() == 'left';
    // The frame changes shape with the viewport — 4:3, 16:9, 3:2 — so the crop
    // is authored per viewport. The value arrives already resolved by the
    // projection, which is why Edit, Preview and Public frame identically.
    final focalAlignment = _resolveFocalAlignment(data);
    final titleFormatting = _resolveFormatting(data['titleFormatting']);
    final contentFormatting = _resolveFormatting(
      data['contentFormatting'] ?? data['descriptionFormatting'],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final isDesktop = availableWidth >= 900;
        final isMobile = availableWidth < 600;
        final imageAspectRatio = isDesktop
            ? 4 / 3
            : isMobile
                ? 3 / 2
                : 16 / 9;
        final titleSize = isDesktop
            ? 40.0
            : isMobile
                ? 26.0
                : 34.0;
        final bodySize = isDesktop
            ? 17.0
            : isMobile
                ? 16.0
                : 16.5;
        final hasEditableMedia = presenters?.media != null;
        final showMedia = imageUrl != null || hasEditableMedia;

        final titleWidget = _presentText(
          context,
          slot: WebsiteInlineTextSlot(
            id: 'about-title',
            value: title,
            valueKeys: const ['title'],
            baseStyle: TextStyle(
              fontFamily: headingFont,
              fontSize: titleSize,
              fontWeight: FontWeight.w700,
              height: 1.15,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            formatting: titleFormatting,
            formattingKeys: const ['titleFormatting'],
            placeholder: 'Sobre Nosotros',
          ),
          key: const ValueKey<String>('website-about-title'),
        );
        final bodyWidget = _presentText(
          context,
          slot: WebsiteInlineTextSlot(
            id: 'about-content',
            value: content,
            valueKeys: const ['content', 'description'],
            baseStyle: TextStyle(
              fontFamily: bodyFont,
              fontSize: bodySize,
              height: 1.6,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            formatting: contentFormatting,
            formattingKeys: const [
              'contentFormatting',
              'descriptionFormatting',
            ],
            placeholder: 'Descripción de tu empresa...',
          ),
          key: const ValueKey<String>('website-about-content'),
        );
        final textColumn = Column(
          key: const ValueKey<String>('website-about-text-column'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            titleWidget,
            const SizedBox(height: 24),
            bodyWidget,
          ],
        );

        Widget composition;
        if (!showMedia) {
          composition = Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              key: const ValueKey<String>('website-about-no-media-frame'),
              constraints: const BoxConstraints(maxWidth: 700),
              child: textColumn,
            ),
          );
        } else {
          final media = AspectRatio(
            key: const ValueKey<String>('website-about-media-frame'),
            aspectRatio: imageAspectRatio,
            child: _presentMedia(
              context,
              imageUrl: imageUrl,
              imageAltText: imageAltText,
              alignment: focalAlignment,
            ),
          );

          if (isDesktop) {
            final children = <Widget>[
              Expanded(child: imageOnLeft ? media : textColumn),
              const SizedBox(width: 48),
              Expanded(child: imageOnLeft ? textColumn : media),
            ];
            composition = Row(
              key: const ValueKey<String>('website-about-desktop-layout'),
              crossAxisAlignment: CrossAxisAlignment.center,
              children: children,
            );
          } else {
            composition = Column(
              key: const ValueKey<String>('website-about-stacked-layout'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                media,
                SizedBox(height: isMobile ? 24 : 32),
                textColumn,
              ],
            );
          }
        }

        return Padding(
          key: const ValueKey<String>('website-about-content-root'),
          padding: padding,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: composition,
            ),
          ),
        );
      },
    );
  }

  Widget _presentText(
    BuildContext context, {
    required WebsiteInlineTextSlot slot,
    required Key key,
  }) {
    final presenter = presenters?.text;
    if (presenter != null) {
      return KeyedSubtree(key: key, child: presenter(context, slot));
    }
    return Text(
      slot.value,
      key: key,
      maxLines: slot.maxLines,
      overflow: TextOverflow.visible,
      textAlign: slot.textAlign,
      style: slot.formatting.applyTo(slot.baseStyle),
    );
  }

  Widget _presentMedia(
    BuildContext context, {
    required String? imageUrl,
    required String? imageAltText,
    required Alignment alignment,
  }) {
    final fallback = _AboutImageFallback(
      editable: presenters?.media != null,
      semanticLabel: imageAltText,
    );
    final slot = WebsiteInlineMediaSlot(
      id: 'about-image',
      url: imageUrl,
      valueKeys: const ['imageUrl', 'image'],
      fit: BoxFit.cover,
      alignment: alignment,
      fallback: fallback,
      borderRadius: BorderRadius.circular(16),
      semanticLabel: imageAltText,
    );
    final presenter = presenters?.media;
    if (presenter != null) return presenter(context, slot);

    if (imageUrl == null) return fallback;
    return ClipRRect(
      borderRadius: slot.borderRadius!,
      child: Image.network(
        imageUrl,
        key: const ValueKey<String>('website-about-image'),
        width: double.infinity,
        height: double.infinity,
        fit: slot.fit,
        alignment: slot.alignment,
        semanticLabel: slot.semanticLabel,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }

  static TextFormatting _resolveFormatting(Object? raw) {
    if (raw is! Map) return const TextFormatting();
    return TextFormatting.fromJson(Map<String, dynamic>.from(raw));
  }

  /// The authored crop, in the same 0..1 contract every other framed image in
  /// the product uses. An absent value keeps the historical centred crop.
  static Alignment _resolveFocalAlignment(Map<String, dynamic> data) {
    final focalX = _finiteDouble(data['focalPointX']) ?? 0.5;
    final focalY = _finiteDouble(data['focalPointY']) ?? 0.5;
    return Alignment(
      (focalX.clamp(0.0, 1.0) * 2) - 1,
      (focalY.clamp(0.0, 1.0) * 2) - 1,
    );
  }

  static double? _finiteDouble(Object? raw) {
    final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
    return value != null && value.isFinite ? value : null;
  }

  static String? _nonEmptyString(Object? raw) {
    final value = raw?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }
}

class _AboutImageFallback extends StatelessWidget {
  const _AboutImageFallback({
    required this.editable,
    this.semanticLabel,
  });

  final bool editable;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel ?? 'Imagen de Sobre Nosotros no disponible',
      image: true,
      child: DecoratedBox(
        key: const ValueKey<String>('website-about-image-fallback'),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Icon(
            editable
                ? Icons.add_photo_alternate_outlined
                : Icons.image_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
