import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../modules/website/models/website_block_catalog.dart';
import '../../modules/website/models/website_editor_drag_payload.dart';
import '../../modules/website/models/website_page_composition.dart';
import '../../modules/website/models/website_responsive_authoring.dart';
import '../../modules/website/models/website_responsive_projection.dart';
import '../../modules/website/providers/website_edit_mode_provider.dart';
import '../../modules/website/widgets/add_block_dialog.dart';
import '../../modules/website/widgets/block_spacer_handle.dart';
import '../../modules/website/widgets/deferred_editable_block_renderer.dart';
import '../../modules/website/widgets/website_block_catalog_sheet.dart';
import '../../modules/website/widgets/website_block_renderer.dart';
import '../../modules/website/widgets/website_editor_chrome_geometry.dart';
import '../../shared/models/product.dart';

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
          // disambiguate and no anchor to be before or after.
          if (showsInlineInsert)
            WebsiteInsertBlockAffordance(
              anchor: null,
              fallbackIndex: 0,
              presentBlockTypes: const <String>[],
              onAddBlock: onAddBlock!,
            )
          else if (_isEditMode && onAddBlock != null)
            Padding(
              padding: const EdgeInsets.only(top: 24, bottom: 32),
              child: _AddBlockButtonLarge(
                onAdd: (type) => onAddBlock!(type),
              ),
            ),
        ],
      );
    }

    final leadingChromeLink = LayerLink();
    final gapChromeLinks = <String, LayerLink>{
      for (var index = 0; index < blocks.length - 1; index++)
        blocks[index].id: LayerLink(),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final chromeWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final presentBlockTypes = <String>[
          for (final block in composition.blocks) block.blockType,
        ];
        final dockInset = _contextualDockInset(context);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              children: [
                // Start of the page: `Antes de` the first block.
                if (showsInlineInsert)
                  WebsiteInsertBlockAffordance(
                    anchor:
                        _anchorFor(blocks.first, WebsiteBlockInsertSide.before),
                    presentBlockTypes: presentBlockTypes,
                    onAddBlock: onAddBlock!,
                  ),
                for (var index = 0; index < blocks.length; index++) ...[
                  _buildBlockEntry(
                    context: context,
                    block: blocks[index],
                    canvasWidth: chromeWidth,
                    isLast: index == blocks.length - 1,
                    leadingChromeLink: index == 0 ? leadingChromeLink : null,
                    gapChromeLink: gapChromeLinks[blocks[index].id],
                  ),
                  // Between blocks and at the end: `Después de` this block.
                  if (showsInlineInsert)
                    WebsiteInsertBlockAffordance(
                      anchor: _anchorFor(
                          blocks[index], WebsiteBlockInsertSide.after),
                      presentBlockTypes: presentBlockTypes,
                      onAddBlock: onAddBlock!,
                    ),
                ],
                // The pointer host keeps its large end-of-page button; the
                // contextual host already has a named affordance in every gap,
                // including the last one, so a second entry point there would
                // be two ways to do the same thing.
                if (_isEditMode && onAddBlock != null && !showsInlineInsert)
                  Padding(
                    padding: const EdgeInsets.only(top: 24, bottom: 32),
                    child: _AddBlockButtonLarge(
                      onAdd: (type) => onAddBlock!(type),
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
      },
    );
  }

  /// Names the gap the way the operator reads it: a side plus a real block.
  ///
  /// The index comes from [WebsitePageCompositionBlock.sourceIndex], which is
  /// the block's position in the page's own order, so a composition that ever
  /// filters rows cannot shift where an insert lands.
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

  Widget _buildBlockEntry({
    required BuildContext context,
    required WebsitePageCompositionBlock block,
    required double canvasWidth,
    required bool isLast,
    required LayerLink? leadingChromeLink,
    required LayerLink? gapChromeLink,
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
    required this.onInsert,
    this.child,
  });

  final int insertIndex;
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

  @override
  Widget build(BuildContext context) {
    return DragTarget<WebsiteEditorDragPayload>(
      onWillAcceptWithDetails: (details) {
        if (details.data is! NewWebsiteBlockDragPayload) return false;
        if (!_isHovering) setState(() => _isHovering = true);
        return true;
      },
      onLeave: (_) {
        if (_isHovering) setState(() => _isHovering = false);
      },
      onAcceptWithDetails: (details) {
        setState(() => _isHovering = false);
        final payload = details.data;
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
  const _AddBlockButtonLarge({required this.onAdd});

  final ValueChanged<String> onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      child: Material(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () async {
            final blockType = await showDialog<String>(
              context: context,
              builder: (context) => const AddBlockDialog(),
            );
            if (blockType != null) onAdd(blockType);
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
