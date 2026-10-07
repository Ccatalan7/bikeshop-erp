import 'package:flutter/material.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_type.dart';
import 'package:vinabike_public_core/modules/website/models/website_section_content.dart';
import 'package:vinabike_public_core/modules/website/theme/website_section_palette.dart';

import 'website_block_content_presenters.dart';
import 'website_section_frame.dart';

typedef WebsiteGalleryImageProviderBuilder = WebsiteSectionImageProviderBuilder;

/// Shared visitor content for the Website Builder Gallery block: the header
/// and the photos in the mosaic (a big one, a tall one, two small ones and a
/// wide one, in groups that never leave a hole: `websiteMosaicSpans`) with
/// the store's address in a dark tile, or in an even grid. Captions sit on
/// the photos; a phone shows neither them nor the address. The HTML
/// storefront draws the same (`GallerySectionView`).
///
/// The persisted image list owns every visible tile and nothing is ever
/// fabricated; an item without a photo yet is a tinted place for one in the
/// editor (the visitor's HTML page leaves it out). Edit replaces the media
/// and caption leaves through [presenters].
class WebsiteGalleryBlockContent extends StatelessWidget {
  const WebsiteGalleryBlockContent({
    super.key,
    required this.data,
    required this.primaryColor,
    required this.accentColor,
    this.address = '',
    this.headingFont,
    this.bodyFont,
    this.presenters,
    this.padding,
    this.paintSurface = true,
    this.imageProviderBuilder,
  });

  final Map<String, dynamic> data;
  final Color primaryColor;
  final Color accentColor;

  /// The store's address (Configuración → Contacto) for the address tile.
  final String address;
  final String? headingFont;
  final String? bodyFont;
  final WebsiteBlockContentPresenters? presenters;

  /// The padding the operator set; `null` keeps the design's.
  final EdgeInsetsGeometry? padding;
  final bool paintSurface;

  /// Allows focused widget tests to exercise media without network access.
  final WebsiteGalleryImageProviderBuilder? imageProviderBuilder;

  static const rootKey = ValueKey<String>('website-gallery-content-root');
  static const imagesKey = ValueKey<String>('website-gallery-images');
  static const addressKey = ValueKey<String>('website-gallery-address');

  static ValueKey<String> tileKey(int index) =>
      ValueKey<String>('website-gallery-tile-$index');

  static ValueKey<String> imageKey(int index) =>
      ValueKey<String>('website-gallery-image-$index');

  static ValueKey<String> imageFallbackKey(int index) =>
      ValueKey<String>('website-gallery-image-fallback-$index');

  static ValueKey<String> captionKey(int index) =>
      ValueKey<String>('website-gallery-caption-$index');

  @override
  Widget build(BuildContext context) {
    // Edit and Preview share one geometry: an item without a photo yet is
    // a tinted place for one (Edit puts the photo there). The HTML draft
    // shows it the same; only the visitor's page leaves it out.
    final images = websiteSectionItems(data, 'images');
    return KeyedSubtree(
      key: rootKey,
      child: WebsiteSectionBand(
        tone: WebsiteSectionTone.of(WebsiteBlockType.gallery, data),
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
            idPrefix: 'gallery',
            presenters: presenters,
            showNote: false,
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!header.isEmpty) ...[
                header,
                SizedBox(height: scope.isPhone ? 24 : 40),
              ],
              _cells(context, scope, images),
            ],
          );
        },
      ),
    );
  }

  Widget _cells(
    BuildContext context,
    WebsiteSectionScope scope,
    List<(int, Map<String, dynamic>)> images,
  ) {
    final phone = scope.isPhone;
    final grid = websiteGalleryIsGrid(data);
    final lines = websiteAddressLines(address);
    final tile = !grid &&
        !phone &&
        data['showAddress'] != false &&
        lines.street.isNotEmpty;
    final slot = websiteGalleryAddressSlot(images.length);
    final count = images.length + (tile ? 1 : 0);
    final columns = grid ? (scope.isDesktop ? 3 : 2) : (phone ? 2 : 4);
    final gap = phone ? 8.0 : (scope.isDesktop ? 12.0 : 10.0);
    final width = scope.contentWidth;
    final columnWidth = (width - gap * (columns - 1)) / columns;
    final rowHeight = grid
        ? columnWidth * 3 / 4
        : phone
            ? 150.0
            : scope.isDesktop
                ? 230.0
                : 170.0;
    final spans = grid
        ? List<WebsiteMosaicSpan>.filled(count, (columns: 1, rows: 1))
        : websiteMosaicSpans(count, phone: phone);
    // Without photos the address alone fills a row, as the HTML draws it.
    if (count == 0) return const SizedBox.shrink();
    final placed = _place(spans, columns);
    final rows = placed.fold<int>(
      0,
      (most, cell) =>
          cell.row + cell.span.rows > most ? cell.row + cell.span.rows : most,
    );
    final height = rows == 0 ? 0.0 : rows * rowHeight + (rows - 1) * gap;
    final children = <Widget>[];
    for (var cell = 0; cell < count; cell++) {
      final place = placed[cell];
      final left = place.column * (columnWidth + gap);
      final top = place.row * (rowHeight + gap);
      final cellWidth =
          place.span.columns * columnWidth + (place.span.columns - 1) * gap;
      final cellHeight =
          place.span.rows * rowHeight + (place.span.rows - 1) * gap;
      final Widget child;
      if (tile && cell == slot) {
        child = _addressTile(scope, lines);
      } else {
        final (index, item) = images[cell - (tile && cell > slot ? 1 : 0)];
        child = _photo(context, scope, item, index, captions: !phone);
      }
      children.add(
        Positioned(
          left: left,
          top: top,
          width: cellWidth,
          height: cellHeight,
          child: child,
        ),
      );
    }
    return SizedBox(
      key: imagesKey,
      width: width,
      height: height,
      child: Stack(children: children),
    );
  }

  /// CSS grid's sparse auto-placement: each cell at the first place, from
  /// where the previous one went, where it fits.
  static List<({int row, int column, WebsiteMosaicSpan span})> _place(
    List<WebsiteMosaicSpan> spans,
    int columns,
  ) {
    final taken = <(int, int)>{};
    final placed = <({int row, int column, WebsiteMosaicSpan span})>[];
    var row = 0;
    var column = 0;
    for (final span in spans) {
      final wide = span.columns > columns ? columns : span.columns;
      while (true) {
        if (column + wide > columns) {
          row++;
          column = 0;
          continue;
        }
        var fits = true;
        for (var r = row; r < row + span.rows && fits; r++) {
          for (var c = column; c < column + wide; c++) {
            if (taken.contains((r, c))) {
              fits = false;
              break;
            }
          }
        }
        if (fits) break;
        column++;
      }
      for (var r = row; r < row + span.rows; r++) {
        for (var c = column; c < column + wide; c++) {
          taken.add((r, c));
        }
      }
      placed.add((
        row: row,
        column: column,
        span: (columns: wide, rows: span.rows),
      ));
      column += wide;
    }
    return placed;
  }

  Widget _photo(
    BuildContext context,
    WebsiteSectionScope scope,
    Map<String, dynamic> item,
    int index, {
    required bool captions,
  }) {
    final url = websiteSectionText(item, const ['imageUrl']).trim();
    final caption = websiteSectionText(item, const ['caption']);
    final alt = websiteSectionText(item, const ['altText']).trim();
    final target = websiteSectionTarget(
      item,
      index: index,
      collectionKeys: const ['images'],
    );
    final semanticLabel = alt.isNotEmpty
        ? alt
        : caption.trim().isNotEmpty
            ? caption.trim()
            : 'Imagen de galería';
    final fallback = DecoratedBox(
      key: imageFallbackKey(index),
      decoration: BoxDecoration(
        color: scope.colors.tint,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Icon(
          presenters?.media != null
              ? Icons.add_photo_alternate_outlined
              : Icons.image_outlined,
          color: scope.colors.mark,
          semanticLabel: semanticLabel,
        ),
      ),
    );
    final tones = websiteSectionTones(
      context,
      primary: primaryColor,
      accent: accentColor,
    );
    return Stack(
      key: tileKey(index),
      fit: StackFit.expand,
      children: [
        websiteSectionMedia(
          context,
          presenters: presenters,
          id: 'gallery.image.$index.media',
          url: url,
          valueKeys: const <String>['imageUrl'],
          fallback: fallback,
          semanticLabel: semanticLabel,
          alignment: websiteSectionFocal(item),
          borderRadius: BorderRadius.circular(6),
          repeaterTarget: target,
          imageProviderBuilder: imageProviderBuilder,
          imageKey: imageKey(index),
        ),
        if (captions && caption.trim().isNotEmpty)
          Positioned(
            left: 14,
            bottom: 14,
            right: 14,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: websiteSectionColor(tones.deep.withAlpha(0.84)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  child: websiteSectionSlot(
                    context,
                    presenters,
                    WebsiteInlineTextSlot(
                      id: 'gallery.image.$index.caption',
                      value: caption,
                      valueKeys: const <String>['caption'],
                      baseStyle: scope
                          .caps(12, tracking: 0.12, color: Colors.white)
                          .copyWith(height: 1.3),
                      placeholder: 'Leyenda',
                      displayTransform: (value) => value.trim().toUpperCase(),
                      repeaterTarget: target,
                    ),
                    key: captionKey(index),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _addressTile(
    WebsiteSectionScope scope,
    ({String street, String city}) lines,
  ) {
    final colors = scope.inverse;
    return Container(
      key: addressKey,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.location_on_outlined, size: 26, color: colors.eyebrow),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                lines.street.toUpperCase(),
                style: scope.heading(
                  scope.isDesktop ? 24 : 20,
                  height: 1.15,
                  color: colors.ink,
                ),
              ),
              if (lines.city.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  lines.city,
                  style: scope.body(15, height: 1.4, color: colors.muted),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
