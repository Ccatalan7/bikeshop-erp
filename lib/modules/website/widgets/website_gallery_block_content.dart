import 'package:flutter/material.dart';

import 'text_formatting_toolbar.dart';
import 'website_block_content_presenters.dart';

typedef WebsiteGalleryImageProviderBuilder = ImageProvider<Object> Function(
  String url,
);

/// Shared visitor content for the Website Builder Gallery block.
///
/// The persisted image list owns every visible tile. Public and Preview never
/// fabricate sample photos or editor guidance; Edit may replace the same media
/// and caption leaves through [presenters].
class WebsiteGalleryBlockContent extends StatelessWidget {
  const WebsiteGalleryBlockContent({
    super.key,
    required this.data,
    this.headingFont,
    this.bodyFont,
    this.presenters,
    this.padding = const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
    this.imageProviderBuilder,
  });

  final Map<String, dynamic> data;
  final String? headingFont;
  final String? bodyFont;
  final WebsiteBlockContentPresenters? presenters;
  final EdgeInsetsGeometry padding;

  /// Allows focused widget tests to exercise media without network access.
  final WebsiteGalleryImageProviderBuilder? imageProviderBuilder;

  static const rootKey = ValueKey<String>('website-gallery-content-root');
  static const frameKey = ValueKey<String>('website-gallery-content-frame');
  static const titleKey = ValueKey<String>('website-gallery-title');
  static const imagesKey = ValueKey<String>('website-gallery-images');

  static ValueKey<String> tileKey(int index) =>
      ValueKey<String>('website-gallery-tile-$index');

  static ValueKey<String> mediaFrameKey(int index) =>
      ValueKey<String>('website-gallery-media-frame-$index');

  static ValueKey<String> imageKey(int index) =>
      ValueKey<String>('website-gallery-image-$index');

  static ValueKey<String> imageFallbackKey(int index) =>
      ValueKey<String>('website-gallery-image-fallback-$index');

  static ValueKey<String> captionKey(int index) =>
      ValueKey<String>('website-gallery-caption-$index');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rawTitle = _firstPresentString(data, const <String>['title']);
    final title = rawTitle.trim().isEmpty ? 'Galería' : rawTitle.trim();
    final layout = _firstPresentString(
      data,
      const <String>['layout'],
    ).trim();
    final images = _mapList(data['images']);
    final titleFormatting = _resolveFormatting(data['titleFormatting']);
    final titleSlot = WebsiteInlineTextSlot(
      id: 'gallery.title',
      value: rawTitle,
      valueKeys: const <String>['title'],
      baseStyle: (theme.textTheme.displaySmall ?? const TextStyle()).copyWith(
        fontFamily: headingFont,
      ),
      formatting: titleFormatting,
      formattingKeys: const <String>['titleFormatting'],
      textAlign: TextAlign.center,
      placeholder: 'Galería',
    );

    return Padding(
      key: rootKey,
      padding: padding,
      child: Center(
        child: ConstrainedBox(
          key: frameKey,
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              KeyedSubtree(
                key: titleKey,
                child: _presentText(
                  context,
                  slot: titleSlot,
                  publicValue: title,
                ),
              ),
              if (images.isNotEmpty) ...[
                const SizedBox(height: 36),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final usefulWidth = constraints.hasBoundedWidth
                        ? constraints.maxWidth
                        : MediaQuery.sizeOf(context).width;
                    final columns = usefulWidth >= 900
                        ? 3
                        : usefulWidth >= 600
                            ? 2
                            : 1;
                    const gap = 16.0;
                    final tileWidth = columns == 1
                        ? usefulWidth
                        : (usefulWidth - (gap * (columns - 1))) / columns;

                    return Wrap(
                      key: imagesKey,
                      spacing: gap,
                      runSpacing: gap,
                      children: <Widget>[
                        for (var index = 0; index < images.length; index++)
                          _buildTile(
                            context,
                            image: images[index],
                            index: index,
                            width: tileWidth,
                            masonry: layout == 'masonry',
                          ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTile(
    BuildContext context, {
    required Map<String, dynamic> image,
    required int index,
    required double width,
    required bool masonry,
  }) {
    final theme = Theme.of(context);
    final imageUrl =
        _firstPresentString(image, const <String>['imageUrl']).trim();
    final caption =
        _firstPresentString(image, const <String>['caption']).trim();
    final altText =
        _firstPresentString(image, const <String>['altText']).trim();
    final alignment = _resolveFocalAlignment(image);
    final target = _targetFor(image, index);
    final captionFormatting = _resolveFormatting(image['captionFormatting']);
    final aspectRatio = masonry
        ? index % 3 == 0
            ? 1.2
            : index % 3 == 1
                ? 0.8
                : 1.0
        : 1.0;
    final captionSlot = WebsiteInlineTextSlot(
      id: 'gallery.image.$index.caption',
      value: caption,
      valueKeys: const <String>['caption'],
      baseStyle: (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
        fontFamily: bodyFont,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      formatting: captionFormatting,
      formattingKeys: const <String>['captionFormatting'],
      placeholder: 'Leyenda',
      repeaterTarget: target,
    );

    return SizedBox(
      key: tileKey(index),
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AspectRatio(
            key: mediaFrameKey(index),
            aspectRatio: aspectRatio,
            child: _presentMedia(
              context,
              imageUrl: imageUrl,
              altText: altText,
              caption: caption,
              alignment: alignment,
              target: target,
              index: index,
            ),
          ),
          if (caption.isNotEmpty) ...[
            const SizedBox(height: 8),
            KeyedSubtree(
              key: captionKey(index),
              child: _presentText(
                context,
                slot: captionSlot,
                publicValue: caption,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _presentText(
    BuildContext context, {
    required WebsiteInlineTextSlot slot,
    required String publicValue,
  }) {
    final presenter = presenters?.text;
    if (presenter != null) return presenter(context, slot);

    return Text(
      publicValue,
      maxLines: slot.maxLines,
      overflow: TextOverflow.visible,
      textAlign: slot.resolvedTextAlign,
      style: slot.formatting.applyTo(slot.baseStyle),
    );
  }

  Widget _presentMedia(
    BuildContext context, {
    required String imageUrl,
    required String altText,
    required String caption,
    required Alignment alignment,
    required WebsiteInlineRepeaterTarget target,
    required int index,
  }) {
    final semanticLabel = altText.isNotEmpty
        ? altText
        : caption.isNotEmpty
            ? caption
            : 'Imagen de galería';
    final fallback = _GalleryImageFallback(
      key: imageFallbackKey(index),
      semanticLabel: semanticLabel,
      editable: presenters?.media != null,
    );
    final slot = WebsiteInlineMediaSlot(
      id: 'gallery.image.$index.media',
      url: imageUrl.isEmpty ? null : imageUrl,
      valueKeys: const <String>['imageUrl'],
      fit: BoxFit.cover,
      alignment: alignment,
      fallback: fallback,
      borderRadius: BorderRadius.circular(20),
      semanticLabel: semanticLabel,
      repeaterTarget: target,
    );
    final presenter = presenters?.media;
    if (presenter != null) return presenter(context, slot);
    if (imageUrl.isEmpty) return fallback;

    final provider =
        imageProviderBuilder?.call(imageUrl) ?? NetworkImage(imageUrl);
    return Semantics(
      container: true,
      image: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: slot.borderRadius!,
          child: Image(
            key: imageKey(index),
            image: provider,
            width: double.infinity,
            height: double.infinity,
            fit: slot.fit,
            alignment: slot.alignment,
            excludeFromSemantics: true,
            errorBuilder: (_, __, ___) => fallback,
          ),
        ),
      ),
    );
  }

  static WebsiteInlineRepeaterTarget _targetFor(
    Map<String, dynamic> item,
    int index,
  ) {
    final identity = item['id'];
    final hasIdentity =
        identity != null && identity.toString().trim().isNotEmpty;
    return WebsiteInlineRepeaterTarget(
      collectionKeys: const <String>['images'],
      itemIndex: index,
      identityKey: hasIdentity ? 'id' : null,
      identityValue: hasIdentity ? identity : null,
    );
  }

  static Alignment _resolveFocalAlignment(Map<String, dynamic> image) {
    final focalX = _finiteDouble(image['focalPointX']) ?? 0.5;
    final focalY = _finiteDouble(image['focalPointY']) ?? 0.5;
    return Alignment(
      (focalX.clamp(0.0, 1.0) * 2) - 1,
      (focalY.clamp(0.0, 1.0) * 2) - 1,
    );
  }

  static double? _finiteDouble(Object? raw) {
    final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
    return value != null && value.isFinite ? value : null;
  }

  static String _firstPresentString(
    Map<String, dynamic> source,
    List<String> keys,
  ) {
    for (final key in keys) {
      if (source.containsKey(key)) return source[key]?.toString() ?? '';
    }
    return '';
  }

  static List<Map<String, dynamic>> _mapList(Object? raw) {
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  static TextFormatting _resolveFormatting(Object? raw) {
    if (raw is! Map) return const TextFormatting();
    return TextFormatting.fromJson(Map<String, dynamic>.from(raw));
  }
}

class _GalleryImageFallback extends StatelessWidget {
  const _GalleryImageFallback({
    super.key,
    required this.semanticLabel,
    required this.editable,
  });

  final String semanticLabel;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      image: true,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Icon(
            editable
                ? Icons.add_photo_alternate_outlined
                : Icons.image_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
