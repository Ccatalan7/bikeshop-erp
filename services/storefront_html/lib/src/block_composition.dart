import 'dart:convert';

import 'package:vinabike_public_core/modules/website/models/website_block_public_visibility.dart';
import 'package:vinabike_public_core/modules/website/models/website_page_composition.dart';
import 'package:vinabike_public_core/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_public_core/modules/website/models/website_responsive_projection.dart';

/// A range of window widths in which Flutter makes the same decisions about
/// an editor page: which blocks it shows (by the window's width) and at which
/// viewport it reads their data (by the width of the canvas they are drawn
/// in, which on a policy page is a column narrower than the window).
class WidthBand {
  const WidthBand({
    required this.index,
    required this.minWidth,
    required this.maxWidth,
    required this.sample,
    required this.canvasWidth,
  });

  final int index;
  final double minWidth;

  /// Exclusive; `null` is unbounded.
  final double? maxWidth;

  /// A window width inside the band, at which Flutter is asked.
  final double sample;

  /// The width the blocks are drawn in at [sample].
  final double canvasWidth;

  /// The media query that selects this band, for the CSS.
  String get mediaQuery => [
    if (minWidth > 0) '(min-width:${_px(minWidth)})',
    if (maxWidth case final max?) '(max-width:${_px(max - 0.02)})',
  ].join(' and ');

  static String _px(double value) =>
      value == value.roundToDouble() ? '${value.round()}px' : '${value}px';
}

/// One block as the page draws it in some bands: its composition (order,
/// geometry), its data projected for those bands' viewport, and the space
/// after it (none after the last block of a band).
class ComposedBlock {
  const ComposedBlock({
    required this.block,
    required this.data,
    required this.viewport,
    required this.gapAfter,
    required this.bands,
  });

  final WebsitePageCompositionBlock block;
  final Map<String, dynamic> data;
  final WebsiteViewport viewport;
  final double gapAfter;

  /// The bands where this version is drawn; `null` is all of them.
  final List<int>? bands;
}

/// The page's blocks in Flutter's order, one version per group of bands
/// that draw the block the same way (`WebsitePageComposition` and
/// `WebsiteResponsiveBlockProjection`, as `PageComposition` calls them).
/// A page without responsive settings gets one version of each block.
List<ComposedBlock> composeBlocks({
  required List<Map<String, dynamic>> rows,
  required List<WidthBand> bands,
  required double sectionSpacing,
}) {
  // block id → (version key → version), in first-seen order.
  final versions =
      <String, Map<String, ({ComposedBlock block, List<int> bands})>>{};
  final order = <String>[];
  for (final band in bands) {
    final composition = WebsitePageComposition.project(
      blocks: rows,
      mode: WebsitePageCompositionMode.public,
      breakpoint: websitePublicBreakpointForWidth(band.sample),
      logicalWidth: band.sample,
      sectionSpacing: sectionSpacing,
    );
    final drawn = composition.blocks;
    for (var index = 0; index < drawn.length; index++) {
      final block = drawn[index];
      final source = Map<String, dynamic>.from(block.blockData)
        ..remove('visibility');
      final viewport = WebsiteResponsiveDataCodec.viewportForDocumentWidth(
        source,
        band.canvasWidth,
      );
      final data = block.type == null
          ? source
          : WebsiteResponsiveBlockProjection.project(
              type: block.type!,
              data: source,
              viewport: viewport,
            );
      final gap = index == drawn.length - 1 ? 0.0 : block.geometry.spacingAfter;
      // The viewport itself is not part of the version: what it changes in
      // a drawing (a block's side padding on a phone) the stylesheet decides
      // by the block's width.
      final key = jsonEncode([
        data,
        gap,
        block.geometry.fullBleed,
        block.geometry.blockHeight,
      ]);
      if (!versions.containsKey(block.id)) order.add(block.id);
      final byKey = versions.putIfAbsent(block.id, () => {});
      final existing = byKey[key];
      if (existing != null) {
        existing.bands.add(band.index);
      } else {
        byKey[key] = (
          block: ComposedBlock(
            block: block,
            data: data,
            viewport: viewport,
            gapAfter: gap,
            bands: null,
          ),
          bands: [band.index],
        );
      }
    }
  }

  // Flutter's order is the same in every band (order index, then source
  // position); a block hidden in some bands keeps its place in the others.
  order.sort((left, right) {
    final a = versions[left]!.values.first.block.block;
    final b = versions[right]!.values.first.block.block;
    final byOrder = a.orderIndex.compareTo(b.orderIndex);
    return byOrder != 0 ? byOrder : a.sourceIndex.compareTo(b.sourceIndex);
  });

  return [
    for (final id in order)
      for (final version in versions[id]!.values)
        ComposedBlock(
          block: version.block.block,
          data: version.block.data,
          viewport: version.block.viewport,
          gapAfter: version.block.gapAfter,
          bands: version.bands.length == bands.length ? null : version.bands,
        ),
  ];
}

/// CSS that hides each version outside its bands: `data-bands="0 3"`.
String bandVisibilityCss(List<WidthBand> bands) => [
  for (final band in bands)
    '@media ${band.mediaQuery}{[data-bands]:not([data-bands~="${band.index}"]){display:none!important}}',
].join('\n');
