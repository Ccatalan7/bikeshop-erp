import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../../modules/website/models/website_block_catalog.dart';
import '../../modules/website/providers/website_edit_mode_provider.dart';
import '../../modules/website/widgets/website_block_catalog_sheet.dart';
import '../../modules/website/widgets/website_editor_chrome_geometry.dart';
import '../../modules/website/widgets/website_editor_contextual_operation_scope.dart';

/// The one page-level insert command, mirrored here so this host does not
/// depend on the composition widget it serves.
typedef WebsiteInsertBlockCommand = void Function(
  String blockType, {
  int? atIndex,
});

/// Where an insertion would land, expressed so it can be re-checked later.
///
/// **Never a frozen index.** The anchor names the *block* and the *side*, plus
/// the document revision it was computed against. The index is derived at
/// commit time from the document as it is then. A `sourceIndex` captured when
/// the marker was drawn is a number about a page that may no longer exist:
/// between the tap and the choice the operator can reorder, delete, undo or
/// change page, and committing that number appends into the wrong seam — or,
/// worse, silently appends at the end.
@immutable
class WebsiteInsertionIntent {
  const WebsiteInsertionIntent({
    required this.blockId,
    required this.side,
    required this.anchorTitle,
    required this.sessionRevision,
    required this.pageId,
    required this.pageSlug,
  });

  /// The anchor block, or null on an empty page — where there is no seam to
  /// be on a side of and the only possible index is 0.
  final String? blockId;
  final WebsiteBlockInsertSide side;
  final String anchorTitle;

  /// Identity of the document this intent was born in.
  final int sessionRevision;
  final String? pageId;
  final String? pageSlug;

  bool matchesDocument(WebsiteEditorDocument document) =>
      document.sessionRevision == sessionRevision &&
      document.pageId == pageId &&
      document.pageSlug == pageSlug;

  @override
  bool operator ==(Object other) =>
      other is WebsiteInsertionIntent &&
      other.blockId == blockId &&
      other.side == side &&
      other.sessionRevision == sessionRevision;

  @override
  int get hashCode => Object.hash(blockId, side, sessionRevision);
}

/// Why an insertion did not happen. Stated, never swallowed.
enum WebsiteInsertionAbort {
  /// The operator cancelled the catalog. A true no-op.
  cancelled,

  /// The document moved under the intent: reorder, delete, undo, page change.
  documentChanged,
}

/// Builds the canonical trailing insertion intent from the live document.
WebsiteInsertionIntent websitePageEndInsertionIntent(
  WebsiteEditModeProvider provider,
) {
  final document = provider.document;
  final blocks = provider.blocks;
  if (blocks.isEmpty) {
    return WebsiteInsertionIntent(
      blockId: null,
      side: WebsiteBlockInsertSide.before,
      anchorTitle: '',
      sessionRevision: document.sessionRevision,
      pageId: document.pageId,
      pageSlug: document.pageSlug,
    );
  }
  final anchor = blocks.last;
  final type = (anchor['block_type'] ?? anchor['type'] ?? '').toString();
  final title = WebsiteBlockCatalog.entries()
          .where((entry) => entry.type.name == type)
          .map((entry) => entry.title)
          .firstOrNull ??
      type;
  return WebsiteInsertionIntent(
    blockId: anchor['id']?.toString(),
    side: WebsiteBlockInsertSide.after,
    anchorTitle: title,
    sessionRevision: document.sessionRevision,
    pageId: document.pageId,
    pageSlug: document.pageSlug,
  );
}

int? _resolveInsertionAnchorIndex(
  WebsiteEditModeProvider provider,
  String? blockId,
) {
  if (blockId == null) return null;
  final index = provider.blocks.indexWhere(
    (block) => block['id']?.toString() == blockId,
  );
  return index < 0 ? null : index;
}

/// The one asynchronous insertion operation for contextual and pane hosts.
///
/// The semantic anchor is re-resolved at commit, while the provider-owned
/// async intent rejects page/source ABA and a result returned to another
/// provider instance. The legacy pane button therefore cannot become a second
/// dialog or a second write owner.
Future<WebsiteInsertionAbort?> commitWebsiteInsertion({
  required BuildContext context,
  required WebsiteInsertionIntent intent,
  required WebsiteInsertBlockCommand onAddBlock,
}) async {
  final openingOwner = context.read<WebsiteEditModeProvider>();
  if (!intent.matchesDocument(openingOwner.document)) {
    return WebsiteInsertionAbort.documentChanged;
  }
  final asyncIntent = openingOwner.captureAsyncIntent(
    blockId: intent.blockId,
    requiresSelection: false,
  );
  if (asyncIntent == null) return WebsiteInsertionAbort.documentChanged;

  final openingIndex = _resolveInsertionAnchorIndex(
    openingOwner,
    intent.blockId,
  );
  if (intent.blockId != null && openingIndex == null) {
    return WebsiteInsertionAbort.documentChanged;
  }

  final selection = await showWebsiteBlockCatalogSheet(
    context: context,
    theme: Theme.of(Navigator.of(context, rootNavigator: true).context),
    presentBlockTypes: <String>[
      for (final block in openingOwner.blocks)
        (block['block_type'] ?? block['type'] ?? '').toString(),
    ],
    anchor: intent.blockId == null
        ? null
        : WebsiteBlockInsertionAnchor(
            anchorIndex: openingIndex!,
            anchorTitle: intent.anchorTitle,
            initialSide: intent.side,
          ),
  );
  if (selection == null) return WebsiteInsertionAbort.cancelled;
  if (!context.mounted) return WebsiteInsertionAbort.documentChanged;

  final live = context.read<WebsiteEditModeProvider>();
  final result = live.commitAsyncIntent(asyncIntent, () {
    if (!intent.matchesDocument(live.document)) {
      return WebsiteInlineMutationResult.rejected;
    }

    final int atIndex;
    if (intent.blockId == null) {
      atIndex = 0;
    } else {
      final anchorIndex = _resolveInsertionAnchorIndex(live, intent.blockId);
      if (anchorIndex == null) return WebsiteInlineMutationResult.rejected;
      atIndex = selection.side == WebsiteBlockInsertSide.before
          ? anchorIndex
          : anchorIndex + 1;
    }
    onAddBlock(selection.type.name, atIndex: atIndex);
    return WebsiteInlineMutationResult.committed;
  });
  return result.changed ? null : WebsiteInsertionAbort.documentChanged;
}

/// The single owner of in-page block insertion on the contextual host.
///
/// **What changed and why.** The markers used to be `CompositedTransformFollower`s
/// that opened the catalog themselves. Two things were wrong with that. A
/// follower has no bounds of its own — it paints where its leader is but is
/// laid out at its parent's origin — so a marker for a seam far down the page
/// was not reliably hit-testable, and one for a seam that was not painted did
/// not exist at all. And each marker opening its own route made every marker a
/// second entry point into the same operation, with no place to put the checks
/// that operation needs.
///
/// Now the follower is a **leaf trigger only**: it reports an intent upward. The
/// markers live inside this host's [OverlayPortal] layer, which is a real box
/// with real bounds and normal hit testing, and exactly one place — [_commit] —
/// opens the catalog and performs the write.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` t11 frame **11a** (the `+` lives in
/// the seam, 48 tall, and the sheet names where it will land) and **11b** (the
/// preservation contract for insert and for cancel).
class WebsiteInsertionHost extends StatefulWidget {
  const WebsiteInsertionHost({
    super.key,
    required this.onAddBlock,
    required this.markersBuilder,
    required this.child,
  });

  /// The one canonical page-level command. This host never touches a provider
  /// to write; it resolves an index and calls this exactly once.
  final WebsiteInsertBlockCommand onAddBlock;

  /// The markers for the current selection, built into the overlay layer.
  ///
  /// They are built HERE, not in the content tree, so they get the overlay's
  /// full bounds and ordinary hit testing. Each one is a leaf trigger: it
  /// reports an intent to this host and opens nothing itself.
  final WidgetBuilder markersBuilder;

  final Widget child;

  static WebsiteInsertionHostState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<WebsiteInsertionHostState>();

  @override
  State<WebsiteInsertionHost> createState() => WebsiteInsertionHostState();
}

class WebsiteInsertionHostState extends State<WebsiteInsertionHost> {
  /// Reentrancy: one catalog at a time, whatever a double tap or two markers
  /// under one finger try to do. `11b` says cancelling is a true no-op, and two
  /// overlapping sheets could not both be a no-op.
  bool _isResolving = false;

  @visibleForTesting
  bool get isResolving => _isResolving;

  /// The last abort, for the gates. Not user-facing state.
  @visibleForTesting
  WebsiteInsertionAbort? lastAbort;

  /// Entry point for every marker. Returns when the operation settled.
  Future<void> requestInsertion(WebsiteInsertionIntent intent) async {
    if (_isResolving) return;
    _isResolving = true;
    try {
      await _commit(intent);
    } finally {
      if (mounted) _isResolving = false;
    }
  }

  Future<void> _commit(WebsiteInsertionIntent intent) async {
    lastAbort = await commitWebsiteInsertion(
      context: context,
      intent: intent,
      onAddBlock: widget.onAddBlock,
    );
  }

  final OverlayPortalController _markers = OverlayPortalController();
  final GlobalKey _contentKey = GlobalKey();
  final Set<ScrollPosition> _ancestorScrollPositions = <ScrollPosition>{};
  Rect? _interactiveViewportRect;
  bool _viewportMeasurementScheduled = false;

  @visibleForTesting
  Rect? get interactiveViewportRect => _interactiveViewportRect;

  void _syncAncestorScrollPositions() {
    final next = <ScrollPosition>{};
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        next.add((element.state as ScrollableState).position);
      }
      return true;
    });

    for (final position in _ancestorScrollPositions.difference(next)) {
      position.removeListener(_scheduleViewportMeasurement);
    }
    for (final position in next.difference(_ancestorScrollPositions)) {
      position.addListener(_scheduleViewportMeasurement);
    }
    _ancestorScrollPositions
      ..clear()
      ..addAll(next);
  }

  void _scheduleViewportMeasurement() {
    if (_viewportMeasurementScheduled) return;
    _viewportMeasurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportMeasurementScheduled = false;
      if (!mounted) return;

      // A viewport can move because an OUTER scrollable moved it, without
      // rebuilding this host. Listen to every ancestor ScrollPosition and
      // refresh the set after each layout so replacement controllers are not
      // left behind.
      _syncAncestorScrollPositions();

      final contentBox =
          _contentKey.currentContext?.findRenderObject() as RenderBox?;
      final overlayState = Overlay.of(context, rootOverlay: true);
      final overlayBox = overlayState.context.findRenderObject() as RenderBox?;
      if (contentBox == null ||
          overlayBox == null ||
          !contentBox.hasSize ||
          !overlayBox.hasSize) {
        return;
      }

      // The visible canvas is the INTERSECTION of every ancestor viewport,
      // not merely the nearest one. A nested editor can be wholly visible in
      // its own SingleChildScrollView while an outer workspace viewport has
      // already clipped its top. Measuring all of them in the same root-
      // overlay coordinate space keeps paint and hit testing honest.
      var next = Offset.zero & overlayBox.size;
      var foundViewport = false;
      RenderObject? ancestor = contentBox.parent;
      while (ancestor != null) {
        if (ancestor is RenderAbstractViewport &&
            ancestor is RenderBox &&
            ancestor.attached &&
            (ancestor as RenderBox).hasSize) {
          final viewportBox = ancestor as RenderBox;
          foundViewport = true;
          final topLeft = overlayBox.globalToLocal(
            viewportBox.localToGlobal(Offset.zero),
          );
          final bottomRight = overlayBox.globalToLocal(
            viewportBox.localToGlobal(
              viewportBox.size.bottomRight(Offset.zero),
            ),
          );
          next = next.intersect(Rect.fromPoints(topLeft, bottomRight));
        }
        ancestor = ancestor.parent;
      }
      if (!foundViewport) {
        final topLeft = overlayBox.globalToLocal(
          contentBox.localToGlobal(Offset.zero),
        );
        final bottomRight = overlayBox.globalToLocal(
          contentBox.localToGlobal(contentBox.size.bottomRight(Offset.zero)),
        );
        next = next.intersect(Rect.fromPoints(topLeft, bottomRight));
      }

      // The contextual dock is an overlay sibling, not part of the scroll
      // viewport. Cap the interactive canvas at the dock's real measured top;
      // subtracting its height from the viewport would be wrong when a framed
      // preview already ends above it.
      final dockHeight =
          WebsiteEditorChromeScope.maybeOf(context)?.contextualDockHeight ?? 0;
      final dockTop = overlayBox.size.height - dockHeight;
      if (next.bottom > dockTop) {
        next = Rect.fromLTRB(next.left, next.top, next.right, dockTop);
      }
      if (next.width <= 0 || next.height <= 0) next = Rect.zero;

      final previous = _interactiveViewportRect;
      if (previous != null &&
          (previous.left - next.left).abs() < 0.5 &&
          (previous.top - next.top).abs() < 0.5 &&
          (previous.right - next.right).abs() < 0.5 &&
          (previous.bottom - next.bottom).abs() < 0.5) {
        return;
      }
      setState(() => _interactiveViewportRect = next);
    });
  }

  @override
  void initState() {
    super.initState();
    // The layer is always mounted; the builder decides whether it has anything
    // in it. Toggling the portal with the selection would make the overlay's
    // own identity depend on editor state.
    _markers.show();
  }

  @override
  void dispose() {
    for (final position in _ancestorScrollPositions) {
      position.removeListener(_scheduleViewportMeasurement);
    }
    _ancestorScrollPositions.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleViewportMeasurement();
    final clipRect = _interactiveViewportRect;
    // This portal deliberately paints in the root Overlay so its seam targets
    // stay correctly positioned across nested editor Navigators. That also
    // means its entry can otherwise outlive the page's paint order and appear
    // above a modal route opened by the dock. A page that is not the current
    // route has no actionable inline chrome: remove the markers from paint and
    // hit testing for every sheet/dialog, then restore them when the route is
    // current again. `ModalRoute.of` registers the dependency that rebuilds
    // this host on those transitions.
    final routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    final contextualOperationActive =
        WebsiteEditorContextualOperationScope.isActiveOf(context);
    return OverlayPortal(
      controller: _markers,
      // Measurement, clipping, paint and hit testing must use the SAME
      // coordinate authority. The ERP hosts the editor below nested
      // Navigators; leaving the portal on `nearestOverlay` while measuring the
      // root overlay shifts the clip by the nested route's origin.
      overlayLocation: OverlayChildLocation.rootOverlay,
      // Placed in the Overlay, so this subtree is laid out against the
      // Overlay's constraints: a real box with real bounds, hit-tested like
      // any other widget. That is what the followers lacked when they lived at
      // their parent's origin inside the content stack.
      overlayChildBuilder: (overlayContext) {
        if (contextualOperationActive ||
            !routeIsCurrent ||
            clipRect == null ||
            clipRect.isEmpty) {
          return const SizedBox.shrink();
        }
        return ClipRect(
          key: const ValueKey('website-insertion-viewport-clip'),
          clipper: _WebsiteInsertionViewportClipper(clipRect),
          child: widget.markersBuilder(overlayContext),
        );
      },
      child: KeyedSubtree(key: _contentKey, child: widget.child),
    );
  }
}

class _WebsiteInsertionViewportClipper extends CustomClipper<Rect> {
  const _WebsiteInsertionViewportClipper(this.rect);

  final Rect rect;

  @override
  Rect getClip(Size size) => rect.intersect(Offset.zero & size);

  @override
  bool shouldReclip(_WebsiteInsertionViewportClipper oldClipper) =>
      oldClipper.rect != rect;
}
