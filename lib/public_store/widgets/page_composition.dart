import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../modules/website/models/website_block_catalog.dart';
import '../../modules/website/models/website_editor_drag_payload.dart';
import '../../modules/website/models/website_page_composition.dart';
import '../../modules/website/models/website_responsive_authoring.dart';
import '../../modules/website/models/website_responsive_projection.dart';
import '../../modules/website/providers/website_edit_mode_provider.dart';
import '../../modules/website/widgets/block_spacer_handle.dart';
import '../../modules/website/widgets/deferred_editable_block_renderer.dart';
import '../../modules/website/widgets/website_block_catalog_sheet.dart';
import '../../modules/website/widgets/website_block_renderer.dart';
import '../../modules/website/widgets/website_editor_chrome_geometry.dart';
import '../../shared/models/product.dart';
import 'website_header_overlay_boundary.dart';
import 'website_insertion_host.dart';

typedef WebsitePageAddBlock = void Function(
  String blockType, {
  int? atIndex,
});

typedef WebsitePageSpacingChanged = void Function(
  String blockId,
  double spacing,
);

typedef WebsitePageBlockContentAdapter = Widget Function(
  BuildContext context,
  WebsitePageCompositionBlock block,
  Widget sharedContent,
);

/// The only page-level content composer for Website Builder blocks.
///
/// [WebsitePageComposition] owns visibility, ordering and geometry. This
/// widget owns the single Edit-vs-content renderer switch: Preview and Public
/// both use [WebsiteBlockRenderer], while Edit adds editor chrome through
/// [DeferredEditableBlockRenderer].
class PageComposition extends StatelessWidget {
  const PageComposition({
    super.key,
    required this.composition,
    required this.primaryColor,
    required this.accentColor,
    required this.textColor,
    required this.containerPadding,
    this.featuredProducts = const [],
    this.featuredProductsReady = true,
    this.headingFont,
    this.bodyFont,
    this.headingSize,
    this.bodySize,
    this.tenantId,
    this.onNavigate,
    this.isNavigationEligible,
    this.onAddBlock,
    this.onSpacingChanged,
    this.contentAdapter,
    this.emptyState,
    this.visibleBlockLimit,
  });

  final WebsitePageComposition composition;
  final List<Product> featuredProducts;
  final bool featuredProductsReady;
  final Color primaryColor;
  final Color accentColor;
  final Color textColor;
  final double containerPadding;
  final String? headingFont;
  final String? bodyFont;
  final double? headingSize;
  final double? bodySize;
  final String? tenantId;
  final ValueChanged<String>? onNavigate;
  final bool Function(String href)? isNavigationEligible;
  final WebsitePageAddBlock? onAddBlock;
  final WebsitePageSpacingChanged? onSpacingChanged;
  final WebsitePageBlockContentAdapter? contentAdapter;
  final Widget? emptyState;
  final int? visibleBlockLimit;

  bool get _isEditMode => composition.mode == WebsitePageCompositionMode.edit;

  /// Whether this composition is mounted inside the editor shell.
  ///
  /// [WebsiteEditorChromeScope] has exactly one publisher —
  /// `PersistentEditorShell`, which is always built under the edit provider.
  /// So its presence is also the safe gate for reading that provider: the
  /// public storefront, Preview and any harness that renders blocks without
  /// the shell never take the editor path at all.
  bool _isInsideEditorShell(BuildContext context) =>
      WebsiteEditorChromeScope.maybeOf(context) != null;

  /// Band the contextual dock takes from the bottom of the canvas, or 0.
  ///
  /// Read from the chrome owner, never re-derived here: it is 0 by
  /// construction with a pane, in Preview, and on the public storefront.
  double _contextualDockInset(BuildContext context) =>
      WebsiteEditorChromeScope.maybeOf(context)?.contextualDockHeight ?? 0;

  /// Whether this host edits from a dock and sheets instead of a pane.
  ///
  /// One owner decides it — [WebsiteEditorChromeScope] — and an absent scope
  /// keeps the historical pointer composition, so Preview, the public
  /// storefront and any host that publishes no geometry are untouched.
  bool _usesContextualHost(BuildContext context) =>
      !(WebsiteEditorChromeScope.maybeOf(context)?.usesPane ?? true);

  /// The in-page insert affordance exists only in Edit, only when the page can
  /// actually accept a block, and only on the contextual host. With a pane the
  /// operator drags from the panel onto the drop zones that already exist.
  bool _showsInlineInsert(BuildContext context) =>
      _isEditMode && onAddBlock != null && _usesContextualHost(context);

  @override
  Widget build(BuildContext context) {
    final limit = visibleBlockLimit;
    final List<WebsitePageCompositionBlock> blocks =
        limit == null || limit >= composition.blocks.length
            ? composition.blocks
            : composition.blocks
                .take(limit.clamp(0, composition.blocks.length))
                .toList(growable: false);
    final showsInlineInsert = _showsInlineInsert(context);
    if (blocks.isEmpty) {
      return Column(
        children: [
          emptyState ?? const SizedBox.shrink(),
          // An empty page gets exactly ONE affordance: there is no gap to
          // disambiguate and no anchor to be before or after. It still goes
          // through the same host — one operation, one set of guards.
          if (showsInlineInsert)
            _EmptyPageInsertAffordance(onAddBlock: onAddBlock!)
          else if (_isEditMode && onAddBlock != null)
            Padding(
              padding: const EdgeInsets.only(top: 24, bottom: 32),
              child: _AddBlockButtonLarge(
                onAddBlock: onAddBlock!,
              ),
            ),
        ],
      );
    }

    final leadingChromeLink = LayerLink();
    final trailingChromeLink = LayerLink();
    final gapChromeLinks = <String, LayerLink>{
      for (var index = 0; index < blocks.length - 1; index++)
        blocks[index].id: LayerLink(),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final chromeWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final dockInset = _contextualDockInset(context);
        final canvas = Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              children: [
                // NOTHING editor-only is a child of this column.
                //
                // The insertion affordances used to be: one before the first
                // block and one after every block, each 48 tall and always
                // visible. That cost twice. It made the page a striped rail of
                // permanent bands instead of an affordance — and, worse, every
                // one of those bands was real layout, so a block sat `48 * n`
                // lower in Edit than it did in Preview and in Public. The
                // insertion points now live in the chrome layer below, as
                // followers of the seams, and move nothing.
                for (var index = 0; index < blocks.length; index++)
                  _buildBlockEntry(
                    context: context,
                    block: blocks[index],
                    canvasWidth: chromeWidth,
                    isLast: index == blocks.length - 1,
                    leadingChromeLink: index == 0 ? leadingChromeLink : null,
                    gapChromeLink: gapChromeLinks[blocks[index].id],
                    trailingChromeLink:
                        index == blocks.length - 1 ? trailingChromeLink : null,
                  ),
                // The pointer host keeps its large end-of-page button; the
                // contextual host already has a named affordance in every gap,
                // including the last one, so a second entry point there would
                // be two ways to do the same thing.
                if (_isEditMode && onAddBlock != null && !showsInlineInsert)
                  Padding(
                    padding: const EdgeInsets.only(top: 24, bottom: 32),
                    child: _AddBlockButtonLarge(
                      onAddBlock: onAddBlock!,
                    ),
                  ),
                // The contextual dock floats over the bottom of the canvas, so
                // the page has to end above it. Without this band the last
                // block can never be seen whole on a phone, and a block moved
                // to the end is revealed into the space the dock covers — the
                // scroll extent simply has nowhere further to go.
                //
                // The height is the one the shell measured; the dock already
                // consumed the bottom safe area inside it, so nothing is added
                // here on top of that.
                if (dockInset > 0) SizedBox(height: dockInset),
              ],
            ),
            // The reorder handle, INSIDE the scroll view.
            //
            // It is chrome, not block content: a `Stack` child is only
            // touchable within its parent's bounds, so a handle mounted in the
            // block could never be reached on a block shorter than 48 — one
            // line of text, a divider. As a seam follower it is independent of
            // the block's height and changes no geometry.
            //
            // And it stays under the `Scrollable`, which is the whole point:
            // before the long press fires, the finger belongs to the page and
            // the scroll wins the arena. From the root overlay it could not.
            if (showsInlineInsert)
              Positioned.fill(
                child: _ContextualReorderHandleLayer(
                  blocks: blocks,
                  leadingChromeLink: leadingChromeLink,
                  gapChromeLinks: gapChromeLinks,
                  width: chromeWidth,
                ),
              ),
            // Pointer drag/drop chrome. It is untouched on the pane host and
            // absent on the contextual one, where a drop target has no touch
            // equivalent and the affordance above is the accessible path.
            if (_isEditMode && !showsInlineInsert)
              Positioned.fill(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (onAddBlock != null)
                      _LinkedPageChrome(
                        link: leadingChromeLink,
                        width: chromeWidth,
                        child: _InsertBlockDropZone(
                          insertIndex: 0,
                          reorderAnchorBlockId: blocks.first.id,
                          reorderSide: WebsiteBlockInsertSide.before,
                          onInsert: (type) => onAddBlock!(type, atIndex: 0),
                        ),
                      ),
                    if (onAddBlock != null || onSpacingChanged != null)
                      for (var index = 0; index < blocks.length - 1; index++)
                        _buildGapChrome(
                          block: blocks[index],
                          insertIndex: index + 1,
                          link: gapChromeLinks[blocks[index].id]!,
                          width: chromeWidth,
                        ),
                  ],
                ),
              ),
          ],
        );

        if (!showsInlineInsert) return canvas;

        // ONE host. It owns the overlay layer the markers live in, the
        // reentrancy guard, the document guard and the index re-resolution —
        // and it is the only thing that opens the catalog or calls
        // `onAddBlock`.
        // The transient reorder owner sits ABOVE the insertion host, because
        // both the handle and the seam targets live in the host's marker
        // overlay and must read the same flag the handle sets.
        return _BlockReorderDragHost(
          child: WebsiteInsertionHost(
            onAddBlock: onAddBlock!,
            markersBuilder: (overlayContext) => _ContextualInsertMarkers(
              blocks: blocks,
              leadingChromeLink: leadingChromeLink,
              trailingChromeLink: trailingChromeLink,
              gapChromeLinks: gapChromeLinks,
              width: chromeWidth,
            ),
            child: canvas,
          ),
        );
      },
    );
  }

  Widget _buildBlockEntry({
    required BuildContext context,
    required WebsitePageCompositionBlock block,
    required double canvasWidth,
    required bool isLast,
    required LayerLink? leadingChromeLink,
    required LayerLink? gapChromeLink,
    LayerLink? trailingChromeLink,
  }) {
    Widget keyedBlock = KeyedSubtree(
      key: ValueKey<String>('page-composition-block-${block.id}'),
      child: _buildBlock(context, block, canvasWidth: canvasWidth),
    );
    if (_isEditMode && _isInsideEditorShell(context)) {
      keyedBlock = _RevealOnRequest(blockId: block.id, child: keyedBlock);
    }
    final hasGap = !isLast;
    final spacing = block.geometry.spacingAfter;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leadingChromeLink != null)
          CompositedTransformTarget(
            link: leadingChromeLink,
            child: const SizedBox(width: double.infinity),
          ),
        keyedBlock,
        if (gapChromeLink != null)
          CompositedTransformTarget(
            link: gapChromeLink,
            child: const SizedBox(width: double.infinity),
          ),
        if (hasGap)
          SizedBox(
            key: ValueKey<String>('page-composition-gap-${block.id}'),
            height: spacing,
          ),
        // Zero-height seam at the very end of the page, so the trailing
        // insertion point has a real anchor instead of a computed offset.
        if (trailingChromeLink != null)
          CompositedTransformTarget(
            link: trailingChromeLink,
            child: const SizedBox(width: double.infinity),
          ),
      ],
    );
  }

  Widget _buildGapChrome({
    required WebsitePageCompositionBlock block,
    required int insertIndex,
    required LayerLink link,
    required double width,
  }) {
    final canInsert = onAddBlock != null;
    final canResizeGap = onSpacingChanged != null;
    final spacer = canResizeGap
        ? BlockSpacerHandle(
            currentSpacing: block.geometry.spacingAfter,
            minSpacing: WebsitePageComposition.minimumSpacing,
            maxSpacing: WebsitePageComposition.maximumSpacing,
            minimumInteractiveExtent: 24,
            snapIncrement: 4,
            isActive: true,
            onSpacingChanged: (value) => onSpacingChanged!(block.id, value),
            onSpacingChangeEnd: (_) {},
          )
        : SizedBox(height: block.geometry.spacingAfter);
    return _LinkedPageChrome(
      link: link,
      width: width,
      child: canInsert
          ? _InsertBlockDropZone(
              insertIndex: insertIndex,
              reorderAnchorBlockId: block.id,
              reorderSide: WebsiteBlockInsertSide.after,
              onInsert: (type) => onAddBlock?.call(type, atIndex: insertIndex),
              child: spacer,
            )
          : spacer,
    );
  }

  Widget _buildBlock(
    BuildContext context,
    WebsitePageCompositionBlock block, {
    required double canvasWidth,
  }) {
    final sourceData = Map<String, dynamic>.from(block.blockData)
      ..remove('visibility');
    final type = block.type;
    final viewport = WebsiteResponsiveDataCodec.viewportForDocumentWidth(
      sourceData,
      canvasWidth,
    );
    final data = type == null
        ? sourceData
        : WebsiteResponsiveBlockProjection.project(
            type: type,
            data: sourceData,
            viewport: viewport,
          );
    final baseTheme = Theme.of(context);
    final themedText = baseTheme.textTheme.apply(
      bodyColor: textColor,
      displayColor: textColor,
    );
    final horizontalPadding = block.geometry.fullBleed
        ? 0.0
        : containerPadding.clamp(0.0, 200.0).toDouble();

    Widget content;
    if (_isEditMode) {
      // Edit -> Preview -> Public parity: when a page-level contentAdapter
      // exists (static policies), Edit renders the SAME adapted shared
      // content as the other two modes and only layers editor chrome around
      // it. Non-adapted blocks keep the converged shared path.
      Widget? adaptedOverride;
      final adapter = contentAdapter;
      if (adapter != null) {
        final sharedContent = WebsiteBlockRenderer.build(
          context: context,
          blockType: block.blockType,
          data: data,
          effectiveViewport: viewport,
          primaryColor: primaryColor,
          accentColor: accentColor,
          featuredProducts: block.blockType.toLowerCase() == 'products'
              ? featuredProducts
              : null,
          featuredProductsReady: featuredProductsReady,
          previewMode: true,
          headingFont: headingFont,
          bodyFont: bodyFont,
          headingSize: headingSize,
          bodySize: bodySize,
          onNavigate: onNavigate,
          isNavigationEligible: isNavigationEligible,
          tenantId: tenantId,
        );
        final adapted = adapter.call(context, block, sharedContent);
        if (!identical(adapted, sharedContent)) adaptedOverride = adapted;
      }
      content = DeferredEditableBlockRenderer.build(
        context: context,
        blockId: block.id,
        blockType: block.blockType,
        data: data,
        effectiveViewport: viewport,
        primaryColor: primaryColor,
        accentColor: accentColor,
        featuredProducts: block.blockType.toLowerCase() == 'products'
            ? featuredProducts
            : null,
        headingFont: headingFont,
        bodyFont: bodyFont,
        headingSize: headingSize,
        bodySize: bodySize,
        onNavigate: onNavigate,
        isVisible: block.isGloballyVisible,
        tenantId: tenantId,
        contentOverride: adaptedOverride,
      );
    } else {
      final sharedContent = WebsiteBlockRenderer.build(
        context: context,
        blockType: block.blockType,
        data: data,
        effectiveViewport: viewport,
        primaryColor: primaryColor,
        accentColor: accentColor,
        featuredProducts: block.blockType.toLowerCase() == 'products'
            ? featuredProducts
            : null,
        featuredProductsReady: featuredProductsReady,
        previewMode: composition.mode == WebsitePageCompositionMode.preview,
        headingFont: headingFont,
        bodyFont: bodyFont,
        headingSize: headingSize,
        bodySize: bodySize,
        onNavigate: onNavigate,
        isNavigationEligible: isNavigationEligible,
        tenantId: tenantId,
      );
      content =
          contentAdapter?.call(context, block, sharedContent) ?? sharedContent;
    }

    final exactHeight = block.geometry.exactHeight;
    final minimumHeight = block.geometry.minimumHeight;
    if (!_isEditMode && exactHeight != null) {
      content = SizedBox(
        key: ValueKey<String>('page-composition-height-${block.id}'),
        height: exactHeight,
        width: double.infinity,
        child: content,
      );
    } else if (!_isEditMode && minimumHeight != null) {
      content = ConstrainedBox(
        key: ValueKey<String>('page-composition-height-${block.id}'),
        constraints: BoxConstraints(
          minHeight: minimumHeight,
          minWidth: double.infinity,
        ),
        child: content,
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Theme(
        data: baseTheme.copyWith(textTheme: themedText),
        child: content,
      ),
    );
  }
}

/// Names the gap the way the operator reads it: a side plus a real block.
///
/// The index comes from [WebsitePageCompositionBlock.sourceIndex], which is the
/// block's position in the page's own order, so a composition that ever filters
/// rows cannot shift where an insert lands. One owner: the chrome layer and any
/// other caller compute the same anchor for the same seam.
WebsiteBlockInsertionAnchor _anchorFor(
  WebsitePageCompositionBlock block,
  WebsiteBlockInsertSide side,
) {
  return WebsiteBlockInsertionAnchor(
    anchorIndex: block.sourceIndex,
    anchorTitle: WebsiteBlockCatalog.entries()
            .where((entry) => entry.type == block.type)
            .map((entry) => entry.title)
            .firstOrNull ??
        block.blockType,
    initialSide: side,
  );
}

/// The markers for the current selection, built inside the host's overlay.
///
/// **What this replaces.** One 48-tall band before the first block and one
/// after every block, all mounted as real children of the content column. They
/// were permanent — a striped rail down a page that has nothing to do with what
/// the operator is doing — and they were *layout*, so the same block sat lower
/// in Edit than in Preview and in Public by 48 per band. An editor affordance
/// may not move published content.
///
/// **The rule now.** The `+` still lives in the seam it inserts into — t11 11a:
/// *«La entrada nace en la posición: el + vive en el hueco, no en una barra
/// global»* — but only the seams that belong to what is selected are drawn:
///
/// * a selected block offers `Antes de` and `Después de` **that** block;
/// * the selected header offers the one point below it, which is `Antes de` the
///   first block — placed clear of the header, never inside it;
/// * with nothing selected the page offers its end, so appending never needs a
///   selection first.
///
/// Each marker is a leaf: it hands an intent to the host and opens nothing.
class _ContextualInsertMarkers extends StatelessWidget {
  const _ContextualInsertMarkers({
    required this.blocks,
    required this.leadingChromeLink,
    required this.trailingChromeLink,
    required this.gapChromeLinks,
    required this.width,
  });

  final List<WebsitePageCompositionBlock> blocks;
  final LayerLink leadingChromeLink;
  final LayerLink trailingChromeLink;
  final Map<String, LayerLink> gapChromeLinks;
  final double width;

  @override
  Widget build(BuildContext context) {
    final host = WebsiteInsertionHost.maybeOf(context);
    if (host == null) return const SizedBox.shrink();

    final provider = context.watch<WebsiteEditModeProvider>();
    final selectedId = provider.selectedBlockId;
    final document = provider.document;
    final chrome = WebsiteEditorChromeTarget.forSelection(selectedId);
    final selectedIndex = selectedId == null
        ? -1
        : blocks.indexWhere((block) => block.id == selectedId);

    // The header's insertion point clears the published header instead of
    // landing inside it. `documentInset` is a property of the COMPOSITION, not
    // of the scroll position — a sticky home header still covers the top of the
    // document after it turns solid.
    final headerInset = WebsiteHeaderOverlayBoundary.of(context).documentInset;

    final markers = <Widget>[];

    void addMarker({
      required LayerLink link,
      required WebsitePageCompositionBlock anchorBlock,
      required WebsiteBlockInsertSide side,
      double topOffset = 0,
      bool centredOnSeam = true,
      // The selected block's own two bands share their seam with the reorder
      // handle. They give up their leading strip — paint AND hits — instead of
      // covering it: an affordance the finger cannot reach is not an
      // affordance, and the band stays tappable across the rest of its width.
      bool handleCutout = false,
    }) {
      final anchor = _anchorFor(anchorBlock, side);
      final affordance = WebsiteInsertBlockAffordance(
        anchor: anchor,
        onTap: () => host.requestInsertion(
          WebsiteInsertionIntent(
            blockId: anchorBlock.id,
            side: side,
            anchorTitle: anchor.anchorTitle,
            sessionRevision: document.sessionRevision,
            pageId: document.pageId,
            pageSlug: document.pageSlug,
          ),
        ),
      );
      markers.add(
        _InsertMarkerFollower(
          link: link,
          width: width,
          topOffset: topOffset,
          centredOnSeam: centredOnSeam,
          child: handleCutout
              ? Row(
                  children: [
                    const SizedBox(
                      width: _ContextualReorderHandleLayer.cutout,
                    ),
                    Expanded(child: affordance),
                  ],
                )
              : affordance,
        ),
      );
    }

    if (chrome == WebsiteEditorChromeTarget.header && blocks.isNotEmpty) {
      addMarker(
        link: leadingChromeLink,
        anchorBlock: blocks.first,
        side: WebsiteBlockInsertSide.before,
        // Below the header's bottom edge, not straddling it.
        topOffset: headerInset,
      );
    } else if (selectedIndex >= 0) {
      final selected = blocks[selectedIndex];
      addMarker(
        link: selectedIndex == 0
            ? leadingChromeLink
            : gapChromeLinks[blocks[selectedIndex - 1].id]!,
        anchorBlock: selected,
        side: WebsiteBlockInsertSide.before,
        // Only the first block's leading seam sits under the header.
        topOffset: selectedIndex == 0 ? headerInset : 0,
        handleCutout: true,
      );
      addMarker(
        link: selectedIndex == blocks.length - 1
            ? trailingChromeLink
            : gapChromeLinks[selected.id]!,
        anchorBlock: selected,
        side: WebsiteBlockInsertSide.after,
        // The page's closing seam has no content below it to balance against,
        // so a marker centred on it would hang half off the end of the page.
        centredOnSeam: selectedIndex != blocks.length - 1,
        handleCutout: true,
      );
    } else if (blocks.isNotEmpty) {
      addMarker(
        link: trailingChromeLink,
        anchorBlock: blocks.last,
        side: WebsiteBlockInsertSide.after,
        centredOnSeam: false,
      );
    }

    // Last, so it paints and hit-tests above every marker: while a drag is in
    // flight the seam belongs to the drop, not to «Agregar aquí». It is
    // nothing at all the rest of the time.
    markers.add(
      // Filled, not loose: a Stack of followers under loose constraints sizes
      // itself to zero, and a follower outside its parent's bounds paints but
      // can never be hit — the same trap that kept the handle unreachable.
      Positioned.fill(
        child: _ReorderSeamLayer(
          blocks: blocks,
          leadingChromeLink: leadingChromeLink,
          trailingChromeLink: trailingChromeLink,
          gapChromeLinks: gapChromeLinks,
          width: width,
        ),
      ),
    );

    return Stack(clipBehavior: Clip.none, children: markers);
  }
}

/// The empty page's single affordance, through the same host.
class _EmptyPageInsertAffordance extends StatelessWidget {
  const _EmptyPageInsertAffordance({required this.onAddBlock});

  final WebsitePageAddBlock onAddBlock;

  @override
  Widget build(BuildContext context) {
    return WebsiteInsertionHost(
      onAddBlock: onAddBlock,
      markersBuilder: (_) => const SizedBox.shrink(),
      child: Builder(
        builder: (hostContext) {
          final document =
              hostContext.watch<WebsiteEditModeProvider>().document;
          return WebsiteInsertBlockAffordance(
            anchor: null,
            onTap: () =>
                WebsiteInsertionHost.maybeOf(hostContext)!.requestInsertion(
              WebsiteInsertionIntent(
                blockId: null,
                side: WebsiteBlockInsertSide.before,
                anchorTitle: '',
                sessionRevision: document.sessionRevision,
                pageId: document.pageId,
                pageSlug: document.pageSlug,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A marker pinned to a seam. It has a size of its own and none in the canvas.
class _InsertMarkerFollower extends StatelessWidget {
  const _InsertMarkerFollower({
    required this.link,
    required this.width,
    required this.topOffset,
    required this.centredOnSeam,
    required this.child,
  });

  final LayerLink link;
  final double width;

  /// Pushes the marker DOWN from the seam. Used to clear an overlaying header.
  final double topOffset;

  /// Whether the marker straddles the seam. False for the page's closing seam,
  /// which has nothing below it: there the marker sits entirely above the edge
  /// so all 48 of it stay on the page and reachable.
  final bool centredOnSeam;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: link,
        showWhenUnlinked: false,
        // Centred on the seam, so the affordance reads as belonging to the gap
        // rather than to the block under it — EXCEPT when it has to clear the
        // header, where sitting half-inside the header is the whole defect.
        offset: Offset(
          0,
          topOffset > 0
              ? topOffset
              : (centredOnSeam
                  ? -WebsiteInsertBlockAffordance.height / 2
                  : -WebsiteInsertBlockAffordance.height),
        ),
        child: SizedBox(width: width, child: child),
      ),
    );
  }
}

/// The canvas side of [WebsiteEditorBlockRevealRequest].
///
/// The provider says WHICH block the operator is owed a look at; this decides
/// HOW the canvas gets there, and it is the only place that does. It drives the
/// scroll position that already exists through [Scrollable.ensureVisible] —
/// no second `ScrollController`, no coordinates, nothing that could disagree
/// with the canvas about where a block is.
///
/// One instance wraps each block, but only the one the request names ever acts:
/// the [Selector] collapses every other block's dependency to `null`, so a
/// reveal neither rebuilds nor moves anything else. Deciding this in `build`
/// rather than in a provider listener is deliberate — a listener runs before
/// the tree rebuilds, when the element at a given position still belongs to
/// the block that was there *before* the reorder, and would scroll to that one.
class _RevealOnRequest extends StatefulWidget {
  const _RevealOnRequest({required this.blockId, required this.child});

  final String blockId;
  final Widget child;

  /// `F-05` motion, from `handoff-t10/spec.json`: `base200` with
  /// `cubic-bezier(.22,1,.36,1)`. A jump would leave the operator to work out
  /// on their own that the page moved.
  static const Duration revealDuration = Duration(milliseconds: 200);
  static const Curve revealCurve = Cubic(0.22, 1, 0.36, 1);

  @override
  State<_RevealOnRequest> createState() => _RevealOnRequestState();
}

class _RevealOnRequestState extends State<_RevealOnRequest> {
  /// Revisions are monotonic for the whole session, so one served value is
  /// enough even though Flutter reuses these elements positionally across a
  /// reorder.
  int? _servedRevision;

  @override
  Widget build(BuildContext context) {
    return Selector<WebsiteEditModeProvider, int?>(
      selector: (_, provider) {
        final request = provider.blockRevealRequest;
        if (request == null || request.blockId != widget.blockId) return null;
        return request.revision;
      },
      builder: (context, revision, child) {
        if (revision != null && revision != _servedRevision) {
          _servedRevision = revision;
          _scheduleReveal();
        }
        return child!;
      },
      child: widget.child,
    );
  }

  void _scheduleReveal() {
    // After layout: the block has just changed position, and its new geometry
    // only exists once this frame is laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (Scrollable.maybeOf(context) == null) return;
      Scrollable.ensureVisible(
        context,
        // Leading edge to leading edge: the operator reads a block from its
        // top, and a long block cannot be framed any other way.
        alignment: 0,
        duration: _RevealOnRequest.revealDuration,
        curve: _RevealOnRequest.revealCurve,
      );
    });
  }
}

class _InsertBlockDropZone extends StatefulWidget {
  const _InsertBlockDropZone({
    required this.insertIndex,
    required this.reorderAnchorBlockId,
    required this.reorderSide,
    required this.onInsert,
    this.child,
  });

  final int insertIndex;
  final String reorderAnchorBlockId;
  final WebsiteBlockInsertSide reorderSide;
  final ValueChanged<String> onInsert;
  final Widget? child;

  @override
  State<_InsertBlockDropZone> createState() => _InsertBlockDropZoneState();
}

class _LinkedPageChrome extends StatelessWidget {
  const _LinkedPageChrome({
    required this.link,
    required this.width,
    required this.child,
  });

  final LayerLink link;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CompositedTransformFollower(
      link: link,
      showWhenUnlinked: false,
      targetAnchor: Alignment.topLeft,
      followerAnchor: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: child,
      ),
    );
  }
}

class _InsertBlockDropZoneState extends State<_InsertBlockDropZone> {
  bool _isHovering = false;

  bool _acceptsMove(
    ExistingWebsiteBlockDragPayload payload,
    WebsiteInsertionIntent destination,
  ) =>
      websiteReorderSeamAccepts(context, payload, destination);

  void _moveExistingBlock(
    ExistingWebsiteBlockDragPayload payload,
    WebsiteInsertionIntent destination,
  ) {
    websiteReorderSeamMove(context, payload, destination);
  }

  @override
  Widget build(BuildContext context) {
    final reorderDestination = websiteReorderIntent(
      context,
      anchorBlockId: widget.reorderAnchorBlockId,
      side: widget.reorderSide,
    );
    return DragTarget<WebsiteEditorDragPayload>(
      onWillAcceptWithDetails: (details) {
        final payload = details.data;
        // The same seam now receives the two things that can land between two
        // blocks: a NEW family from the catalogue, and an EXISTING block being
        // moved. A block dropped on its own edges is not a move.
        if (payload is ExistingWebsiteBlockDragPayload) {
          if (!_acceptsMove(payload, reorderDestination)) return false;
        } else if (payload is! NewWebsiteBlockDragPayload) {
          return false;
        }
        if (!_isHovering) setState(() => _isHovering = true);
        return true;
      },
      onLeave: (_) {
        if (_isHovering) setState(() => _isHovering = false);
      },
      onAcceptWithDetails: (details) {
        setState(() => _isHovering = false);
        final payload = details.data;
        if (payload is ExistingWebsiteBlockDragPayload) {
          _moveExistingBlock(payload, reorderDestination);
          return;
        }
        if (payload is! NewWebsiteBlockDragPayload) return;
        widget.onInsert(payload.blockType);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bloque "${payload.blockType}" agregado'),
            duration: const Duration(seconds: 1),
          ),
        );
      },
      builder: (context, candidateData, rejectedData) {
        final showHighlight = _isHovering || candidateData.isNotEmpty;
        return Stack(
          children: [
            if (widget.child != null) widget.child!,
            if (showHighlight)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF00A09D).withValues(alpha: 0.10),
                      border: Border.all(
                        color: const Color(0xFF00A09D).withValues(alpha: 0.6),
                        width: 2,
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.add_circle,
                        color: Color(0xFF00A09D),
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
            if (widget.child == null)
              Container(
                height: 24,
                alignment: Alignment.center,
                child: Container(
                  height: 3,
                  width: 120,
                  decoration: BoxDecoration(
                    color: showHighlight
                        ? const Color(0xFF00A09D)
                        : const Color(0xFF00A09D).withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AddBlockButtonLarge extends StatelessWidget {
  const _AddBlockButtonLarge({required this.onAddBlock});

  final WebsitePageAddBlock onAddBlock;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      child: Material(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () async {
            final provider = context.read<WebsiteEditModeProvider>();
            await commitWebsiteInsertion(
              context: context,
              intent: websitePageEndInsertionIntent(provider),
              onAddBlock: onAddBlock,
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.blue.withValues(alpha: 0.3),
                width: 2,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: const Icon(Icons.add, color: Colors.blue, size: 32),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Agregar nuevo bloque',
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Haz clic para agregar contenido a tu página',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Key of one reorder seam, by the gap it represents.
///
/// `insertIndex` is the gap BEFORE the block at that index, so a page with n
/// blocks has n+1 seams: leading `0`, internal `1..n-1` and trailing `n`.
Key websiteReorderSeamKey(int insertIndex) =>
    Key('website-reorder-seam-$insertIndex');

/// Captures one destination against the active document.
///
/// The integer seam key is only paint/test identity. The command itself is
/// anchored to a block id + side and is re-resolved when the drop commits, the
/// same contract used by insertion. A frozen index is about a list that may no
/// longer exist after a reorder, undo or page switch.
WebsiteInsertionIntent websiteReorderIntent(
  BuildContext context, {
  required String anchorBlockId,
  required WebsiteBlockInsertSide side,
}) {
  final document = context.read<WebsiteEditModeProvider>().document;
  return WebsiteInsertionIntent(
    blockId: anchorBlockId,
    side: side,
    anchorTitle: '',
    sessionRevision: document.sessionRevision,
    pageId: document.pageId,
    pageSlug: document.pageSlug,
  );
}

int? _websiteReorderInsertIndex(
  WebsiteEditModeProvider provider,
  WebsiteInsertionIntent destination,
) {
  final anchorId = destination.blockId;
  if (anchorId == null) return null;
  final anchorIndex = provider.blocks.indexWhere(
    (block) => block['id']?.toString() == anchorId,
  );
  if (anchorIndex < 0) return null;
  return destination.side == WebsiteBlockInsertSide.before
      ? anchorIndex
      : anchorIndex + 1;
}

/// Whether one leased source can land on one leased destination right now.
bool websiteReorderSeamAccepts(
  BuildContext context,
  ExistingWebsiteBlockDragPayload payload,
  WebsiteInsertionIntent destination,
) {
  final provider = context.read<WebsiteEditModeProvider>();
  final document = provider.document;
  if (!payload.matchesDocument(
        sessionRevision: document.sessionRevision,
        pageId: document.pageId,
        pageSlug: document.pageSlug,
      ) ||
      !destination.matchesDocument(document)) {
    return false;
  }
  final current = provider.blocks.indexWhere(
    (block) => block['id']?.toString() == payload.blockId,
  );
  final insertIndex = _websiteReorderInsertIndex(provider, destination);
  if (current < 0 || insertIndex == null) return false;
  // The two gaps touching the source preserve its order and must not create a
  // history entry.
  return insertIndex != current && insertIndex != current + 1;
}

/// Re-resolves the destination and performs exactly one canonical command.
bool websiteReorderSeamMove(
  BuildContext context,
  ExistingWebsiteBlockDragPayload payload,
  WebsiteInsertionIntent destination,
) {
  if (!websiteReorderSeamAccepts(context, payload, destination)) return false;
  final provider = context.read<WebsiteEditModeProvider>();
  final current = provider.blocks.indexWhere(
    (block) => block['id']?.toString() == payload.blockId,
  );
  final insertIndex = _websiteReorderInsertIndex(provider, destination);
  if (current < 0 || insertIndex == null) return false;
  // `reorderBlocks` consumes the insertion-gap convention and performs its
  // own downward adjustment, history write, reveal and notification.
  provider.reorderBlocks(current, insertIndex);
  return true;
}

/// The transient owner of a block drag.
///
/// It exists so the contextual host can mount drop targets for exactly as long
/// as a drag lasts. Outside a drag there is no target, no hit area and no
/// layout: tap, scroll, CTA, text and Canvas keep every gesture they had, which
/// is why this is a flag and not a permanent rail of bands.
class WebsiteBlockReorderScope extends InheritedWidget {
  const WebsiteBlockReorderScope({
    super.key,
    required this.isDragging,
    required this.setDragging,
    required super.child,
  });

  final bool isDragging;
  final ValueChanged<bool> setDragging;

  static WebsiteBlockReorderScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WebsiteBlockReorderScope>();

  /// Reads the owner WITHOUT subscribing — for a handle that only reports.
  static WebsiteBlockReorderScope? readOf(BuildContext context) => context
      .getElementForInheritedWidgetOfExactType<WebsiteBlockReorderScope>()
      ?.widget as WebsiteBlockReorderScope?;

  @override
  bool updateShouldNotify(WebsiteBlockReorderScope oldWidget) =>
      isDragging != oldWidget.isDragging;
}

class _BlockReorderDragHost extends StatefulWidget {
  const _BlockReorderDragHost({required this.child});

  final Widget child;

  @override
  State<_BlockReorderDragHost> createState() => _BlockReorderDragHostState();
}

class _BlockReorderDragHostState extends State<_BlockReorderDragHost> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return WebsiteBlockReorderScope(
      isDragging: _isDragging,
      setDragging: (value) {
        if (_isDragging == value || !mounted) return;
        setState(() => _isDragging = value);
      },
      child: widget.child,
    );
  }
}

/// One 48 target over a seam, alive only while a drag is.
class _ReorderSeamTarget extends StatefulWidget {
  const _ReorderSeamTarget({
    required this.insertIndex,
    required this.destination,
  });

  /// Paint/test identity only; [destination] owns command semantics.
  final int insertIndex;
  final WebsiteInsertionIntent destination;

  @override
  State<_ReorderSeamTarget> createState() => _ReorderSeamTargetState();
}

class _ReorderSeamTargetState extends State<_ReorderSeamTarget> {
  bool _isOver = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<WebsiteEditorDragPayload>(
      key: websiteReorderSeamKey(widget.insertIndex),
      onWillAcceptWithDetails: (details) {
        final payload = details.data;
        if (payload is! ExistingWebsiteBlockDragPayload) return false;
        if (!websiteReorderSeamAccepts(
          context,
          payload,
          widget.destination,
        )) {
          return false;
        }
        if (!_isOver) setState(() => _isOver = true);
        return true;
      },
      onLeave: (_) {
        if (_isOver) setState(() => _isOver = false);
      },
      onAcceptWithDetails: (details) {
        setState(() => _isOver = false);
        final payload = details.data;
        if (payload is! ExistingWebsiteBlockDragPayload) return;
        websiteReorderSeamMove(context, payload, widget.destination);
      },
      builder: (context, candidate, rejected) {
        // `F-06`: 48 while it exists.
        return SizedBox(
          height: 48,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: _isOver ? 6 : 3,
              decoration: BoxDecoration(
                color: _isOver
                    ? scheme.primary
                    : scheme.primary.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The seam layer, which is nothing at all until a drag begins.
///
/// It reads the transient owner from ITS OWN context, below the host, so the
/// targets appear the moment the handle reports a drag and disappear with it.
class _ReorderSeamLayer extends StatelessWidget {
  const _ReorderSeamLayer({
    required this.blocks,
    required this.leadingChromeLink,
    required this.trailingChromeLink,
    required this.gapChromeLinks,
    required this.width,
  });

  final List<WebsitePageCompositionBlock> blocks;
  final LayerLink leadingChromeLink;
  final LayerLink trailingChromeLink;
  final Map<String, LayerLink> gapChromeLinks;
  final double width;

  @override
  Widget build(BuildContext context) {
    final dragging =
        WebsiteBlockReorderScope.maybeOf(context)?.isDragging ?? false;
    if (!dragging) return const SizedBox.shrink();
    if (blocks.isEmpty) return const SizedBox.shrink();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        _LinkedPageChrome(
          link: leadingChromeLink,
          width: width,
          child: _ReorderSeamTarget(
            insertIndex: 0,
            destination: websiteReorderIntent(
              context,
              anchorBlockId: blocks.first.id,
              side: WebsiteBlockInsertSide.before,
            ),
          ),
        ),
        for (var index = 0; index < blocks.length - 1; index++)
          _LinkedPageChrome(
            link: gapChromeLinks[blocks[index].id]!,
            width: width,
            child: _ReorderSeamTarget(
              insertIndex: index + 1,
              destination: websiteReorderIntent(
                context,
                anchorBlockId: blocks[index].id,
                side: WebsiteBlockInsertSide.after,
              ),
            ),
          ),
        _LinkedPageChrome(
          link: trailingChromeLink,
          width: width,
          child: _ReorderSeamTarget(
            insertIndex: blocks.length,
            destination: websiteReorderIntent(
              context,
              anchorBlockId: blocks.last.id,
              side: WebsiteBlockInsertSide.after,
            ),
          ),
        ),
      ],
    );
  }
}

/// The reorder handle, as a seam follower INSIDE the scrollable canvas.
///
/// Two things make this the only place it can live. It must be under the page's
/// `Scrollable`, so a plain swipe that starts on it is still a swipe — a handle
/// in the root overlay is not on the scrollable's hit-test route and turns its
/// own 48 into a dead patch. And it must not be a child of the block's own
/// `Stack`, which cannot be touched outside its bounds: a block shorter than 48
/// would be undraggable. Anchored to the seam it satisfies both and moves
/// nothing — the document's geometry is identical with it and without it.
class _ContextualReorderHandleLayer extends StatelessWidget {
  const _ContextualReorderHandleLayer({
    required this.blocks,
    required this.leadingChromeLink,
    required this.gapChromeLinks,
    required this.width,
  });

  final List<WebsitePageCompositionBlock> blocks;
  final LayerLink leadingChromeLink;
  final Map<String, LayerLink> gapChromeLinks;
  final double width;

  /// Left margin, handle, right margin — the strip the insert bands leave free.
  static const double cutout =
      websiteReorderHandleInset * 2 + WebsiteContextualReorderHandle.target;

  @override
  Widget build(BuildContext context) {
    final selectedId = context.select<WebsiteEditModeProvider, String?>(
      (provider) => provider.selectedBlockId,
    );
    if (selectedId == null) return const SizedBox.shrink();
    final index = blocks.indexWhere((block) => block.id == selectedId);
    if (index < 0) return const SizedBox.shrink();
    final headerInset = WebsiteHeaderOverlayBoundary.of(context).documentInset;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        _InsertMarkerFollower(
          link: index == 0
              ? leadingChromeLink
              : gapChromeLinks[blocks[index - 1].id]!,
          width: width,
          // Below the band that straddles the same seam, so the two
          // affordances never share a pixel.
          topOffset: (index == 0 ? headerInset : 0) +
              WebsiteInsertBlockAffordance.height / 2,
          centredOnSeam: false,
          child: Row(
            children: [
              const SizedBox(width: websiteReorderHandleInset),
              WebsiteContextualReorderHandle(blockId: selectedId),
            ],
          ),
        ),
      ],
    );
  }
}

/// Margin between the canvas edge and the reorder handle.
const double websiteReorderHandleInset = 8;

/// Key of the contextual host's reorder handle for one block.
Key websiteBlockReorderHandleKey(String blockId) =>
    Key('website-block-reorder-handle-$blockId');

/// The only thing that drags a page block on a phone.
///
/// It carries [ExistingWebsiteBlockDragPayload], which the gaps between blocks
/// already accept, so the drop lands on `PageComposition`'s own seam and the
/// move is performed by the canonical `reorderBlocks` — one mutation, one undo,
/// no second writer.
class WebsiteContextualReorderHandle extends StatelessWidget {
  const WebsiteContextualReorderHandle({super.key, required this.blockId});

  final String blockId;

  /// `F-06`: under 900 the density is forced to touch.
  static const double target = 48;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final documentIdentity = context.select<WebsiteEditModeProvider,
        ({int sessionRevision, String? pageId, String? pageSlug})>(
      (provider) => (
        sessionRevision: provider.documentSessionRevision,
        pageId: provider.currentPageId,
        pageSlug: provider.currentPageSlug,
      ),
    );
    final handle = Container(
      width: target,
      height: target,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.primary),
      ),
      child: Icon(
        Icons.drag_indicator_rounded,
        size: 20,
        color: scheme.onSurface,
      ),
    );

    // The handle only REPORTS the drag; the seams it lands on belong to the
    // composition, and they exist only while this flag is up.
    void report(bool dragging) =>
        WebsiteBlockReorderScope.readOf(context)?.setDragging(dragging);

    return Semantics(
      label: 'Reordenar bloque',
      hint: 'Mantén presionado y arrastra hasta el espacio entre bloques',
      child: LongPressDraggable<WebsiteEditorDragPayload>(
        key: websiteBlockReorderHandleKey(blockId),
        data: ExistingWebsiteBlockDragPayload(
          blockId: blockId,
          sessionRevision: documentIdentity.sessionRevision,
          pageId: documentIdentity.pageId,
          pageSlug: documentIdentity.pageSlug,
        ),
        onDragStarted: () => report(true),
        onDragEnd: (_) => report(false),
        onDraggableCanceled: (_, __) => report(false),
        onDragCompleted: () => report(false),
        feedback: Material(
          color: Colors.transparent,
          child: Opacity(opacity: 0.9, child: handle),
        ),
        childWhenDragging: Opacity(opacity: 0.4, child: handle),
        child: handle,
      ),
    );
  }
}
