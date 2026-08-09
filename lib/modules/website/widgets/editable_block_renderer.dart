import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/website_edit_mode_provider.dart';
import '../widgets/inline_editable_text_v2.dart';
import '../widgets/inline_editable_image.dart';
import '../widgets/block_resize_handle.dart';
import '../widgets/block_action_bar.dart';
import '../models/website_font_registry.dart';
import '../models/website_action.dart';
import '../models/website_block_capabilities.dart';
import '../models/website_block_definition.dart';
import '../models/website_block_geometry.dart';
import '../models/website_block_registry.dart';
import '../models/website_block_type.dart';
import '../models/website_canvas_manipulation.dart';
import '../models/website_responsive_authoring.dart';
import 'website_block_content_presenters.dart';
import 'website_block_renderer.dart';
import 'website_editor_chrome_geometry.dart';
import 'website_canvas_editor_binding.dart';
import 'website_carousel_edit_binding.dart';
import 'website_inline_action_editor.dart';
import 'website_media_picker.dart';
import '../services/website_service.dart';
import '../../../shared/models/product.dart';

WebsiteEditorRemoteWriteAuthority? _canvasRemoteWriteAuthority({
  required WebsiteEditModeProvider provider,
  required WebsiteCanvasDocumentTarget documentTarget,
  required WebsiteEditorAsyncIntent expectedIntent,
  required String layerId,
  required WebsiteWriteScope scope,
  required WebsiteViewport viewport,
  required String operation,
  required bool Function() isLiveBinding,
}) {
  final target = WebsiteCanvasLayerTarget(
    document: documentTarget,
    layerId: layerId,
  );
  final tenantId = provider.sessionOwnerTenantId?.trim() ?? '';
  final fingerprint = provider.sessionOwnerLeaseFingerprint;
  if (tenantId.isEmpty || fingerprint == null) return null;
  if (provider.selectedCanvasLayerTarget != target ||
      provider.renderedCanvasViewport(documentTarget) != viewport ||
      provider.writeScope != scope) {
    return null;
  }
  final pageId = provider.currentPageId;
  final pageSlug = provider.currentPageSlug;
  final sessionRevision = provider.documentSessionRevision;
  final documentEpoch = provider.pageDocumentEpoch;
  final entryGeneration = provider.editorEntryLeaseGeneration;
  final entryIdentityRevision = provider.editorEntryLeaseIdentityRevision;

  bool isCurrent() =>
      isLiveBinding() &&
      provider.currentPageId == pageId &&
      provider.currentPageSlug == pageSlug &&
      provider.documentSessionRevision == sessionRevision &&
      provider.pageDocumentEpoch == documentEpoch &&
      provider.editorEntryLeaseGeneration == entryGeneration &&
      provider.editorEntryLeaseIdentityRevision == entryIdentityRevision &&
      provider.sessionOwnerTenantId == tenantId &&
      provider.sessionOwnerLeaseFingerprint == fingerprint &&
      provider.selectedCanvasLayerTarget == target &&
      provider.renderedCanvasViewport(documentTarget) == viewport &&
      provider.writeScope == scope;

  return WebsiteEditorRemoteWriteAuthority(
    tenantId: tenantId,
    operation: operation,
    isCurrent: isCurrent,
    claimOwner: () =>
        provider.commitAsyncIntent(
          expectedIntent,
          () => WebsiteInlineMutationResult.unchanged,
        ) !=
        WebsiteInlineMutationResult.rejected,
  );
}

/// Renders website blocks with inline editing capability when in edit mode.
/// This wraps the standard WebsiteBlockRenderer and adds editable overlays.
class EditableBlockRenderer {
  const EditableBlockRenderer._();

  /// Build a block with editing capability
  static Widget build({
    required BuildContext context,
    required String blockId,
    required String blockType,
    required Map<String, dynamic> data,
    required WebsiteViewport effectiveViewport,
    required Color primaryColor,
    required Color accentColor,
    List<Product>? featuredProducts,
    String? headingFont,
    String? bodyFont,
    double? headingSize,
    double? bodySize,
    void Function(String route)? onNavigate,
    bool isVisible = true,
    String? tenantId,
    Widget? contentOverride,
  }) {
    headingFont = WebsiteFontRegistry.resolveOptionalHeadingFont(headingFont);
    bodyFont = WebsiteFontRegistry.resolveOptionalBodyFont(bodyFont);

    // PageComposition dispatches here only for Edit. This selector therefore
    // owns transient selection, not a second Edit/Preview renderer switch.
    return Selector<WebsiteEditModeProvider, bool>(
      selector: (_, provider) => provider.selectedBlockId == blockId,
      builder: (context, isSelected, child) {
        return _EditableBlockWrapper(
          blockId: blockId,
          blockType: blockType,
          data: data,
          effectiveViewport: effectiveViewport,
          primaryColor: primaryColor,
          accentColor: accentColor,
          featuredProducts: featuredProducts,
          headingFont: headingFont,
          bodyFont: bodyFont,
          headingSize: headingSize,
          bodySize: bodySize,
          onNavigate: onNavigate,
          isSelected: isSelected,
          isVisible: isVisible,
          tenantId: tenantId,
          contentOverride: contentOverride,
        );
      },
    );
  }
}

class _EditableBlockWrapper extends StatefulWidget {
  final String blockId;
  final String blockType;
  final Map<String, dynamic> data;
  final WebsiteViewport effectiveViewport;
  final Color primaryColor;
  final Color accentColor;
  final List<Product>? featuredProducts;
  final String? headingFont;
  final String? bodyFont;
  final double? headingSize;
  final double? bodySize;
  final void Function(String route)? onNavigate;
  final bool isSelected;
  final bool isVisible;
  final String? tenantId;

  /// Shared adapted content that MUST be the block's content subtree in Edit
  /// (identical tree/keys to Preview/Public, e.g. the static-policy adapted
  /// composition). Editor chrome still wraps it; only the inner content
  /// build is overridden so the three modes share one semantics.
  final Widget? contentOverride;

  const _EditableBlockWrapper({
    required this.blockId,
    required this.blockType,
    required this.data,
    required this.effectiveViewport,
    required this.primaryColor,
    required this.accentColor,
    this.featuredProducts,
    this.headingFont,
    this.bodyFont,
    this.headingSize,
    this.bodySize,
    this.onNavigate,
    required this.isSelected,
    required this.isVisible,
    this.tenantId,
    this.contentOverride,
  });

  @override
  State<_EditableBlockWrapper> createState() => _EditableBlockWrapperState();
}

class _EditableBlockWrapperState extends State<_EditableBlockWrapper> {
  final GlobalKey _contentKey = GlobalKey();
  double? _measuredHeight;
  double?
      _localDragHeight; // Local height during drag (avoids Provider rebuilds)
  bool _isDragging = false;
  WebsiteInlineManipulationLease? _heightLease;
  WebsiteEditModeProvider? _heightProvider;
  bool _viewportReportScheduled = false;
  WebsiteViewport? _pendingViewportReport;
  WebsiteEditModeProvider? _pendingViewportProvider;

  @override
  void initState() {
    super.initState();
    // Measure height after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureHeight());
  }

  @override
  void didUpdateWidget(covariant _EditableBlockWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-measure if block data changed and we don't have a fixed height
    if (widget.data['blockHeight'] == null && !_isDragging) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureHeight());
    }
  }

  void _measureHeight() {
    if (!mounted) return;
    final context = _contentKey.currentContext;
    if (context == null) return;

    final renderObject = context.findRenderObject();
    if (renderObject is RenderBox &&
        renderObject.attached &&
        renderObject.hasSize) {
      final height = renderObject.size.height;
      if (height != _measuredHeight) {
        setState(() => _measuredHeight = height);
      }
    }
  }

  WebsiteInlineManipulationTarget _rootManipulationTarget({
    required WebsiteViewport viewport,
    required Iterable<WebsiteInlineManipulationProperty> properties,
    bool requiresSelection = true,
  }) {
    return WebsiteInlineManipulationTarget(
      blockId: widget.blockId,
      owner: const WebsiteInlineBlockOwner(),
      viewport: viewport,
      properties: properties,
      requiresSelection: requiresSelection,
    );
  }

  /// Arm the exact height transaction before the drag recognizer wins.
  bool _onDragStart(
    double startHeight,
    WebsiteEditModeProvider editProvider,
    WebsiteViewport viewport,
  ) {
    _cancelHeightManipulation(updateLocalState: false);
    final lease = editProvider.beginInlineManipulation(
      _rootManipulationTarget(
        viewport: viewport,
        properties: <WebsiteInlineManipulationProperty>[
          WebsiteInlineManipulationProperty.fromSchema(
            WebsiteBlockMetaFields.blockHeight,
          ),
        ],
      ),
    );
    if (lease == null) return false;
    _heightLease = lease;
    _heightProvider = editProvider;
    setState(() {
      _isDragging = true;
      _localDragHeight = startHeight;
    });
    return true;
  }

  /// Handle drag update (local state only, no Provider rebuild)
  void _onDragUpdate(double newHeight) {
    setState(() {
      _localDragHeight = newHeight;
    });
  }

  /// Handle drag end (commit to Provider)
  void _onDragEnd(double finalHeight, WebsiteEditModeProvider editProvider) {
    final lease = _heightLease;
    _heightLease = null;
    _heightProvider = null;
    setState(() {
      _isDragging = false;
      _localDragHeight = null;
    });
    if (lease == null) return;
    editProvider.commitInlineManipulation(
      lease,
      <String, Object?>{
        WebsiteBlockMetaFields.blockHeight.key: finalHeight,
      },
    );
  }

  /// Handle height reset
  void _onResetHeight(
    WebsiteEditModeProvider editProvider,
    WebsiteViewport viewport,
  ) {
    _cancelHeightManipulation(updateLocalState: false);
    final lease = editProvider.captureInlineMutationLease(
      _rootManipulationTarget(
        viewport: viewport,
        properties: <WebsiteInlineManipulationProperty>[
          WebsiteInlineManipulationProperty.fromSchema(
            WebsiteBlockMetaFields.blockHeight,
          ),
        ],
      ),
    );
    setState(() {
      _isDragging = false;
      _localDragHeight = null;
    });
    if (lease != null) {
      editProvider.commitInlineMutation(
        lease,
        <String, Object?>{WebsiteBlockMetaFields.blockHeight.key: null},
      );
    }
    // Re-measure after reset
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureHeight());
  }

  void _cancelHeightManipulation({bool updateLocalState = true}) {
    final lease = _heightLease;
    final provider = _heightProvider;
    _heightLease = null;
    _heightProvider = null;
    if (lease != null) provider?.cancelInlineManipulation(lease);
    if (!updateLocalState || !mounted) return;
    setState(() {
      _isDragging = false;
      _localDragHeight = null;
    });
  }

  void _scheduleViewportReport(
    WebsiteEditModeProvider provider,
    WebsiteViewport viewport,
  ) {
    if (provider.renderedBlockViewportFor(widget.blockId) == viewport) return;
    _pendingViewportProvider = provider;
    _pendingViewportReport = viewport;
    if (_viewportReportScheduled) return;
    _viewportReportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportReportScheduled = false;
      final pendingProvider = _pendingViewportProvider;
      final pendingViewport = _pendingViewportReport;
      _pendingViewportProvider = null;
      _pendingViewportReport = null;
      if (!mounted || pendingProvider == null || pendingViewport == null) {
        return;
      }
      pendingProvider.reportRenderedBlockViewport(
        widget.blockId,
        pendingViewport,
      );
    });
  }

  @override
  void dispose() {
    _cancelHeightManipulation(updateLocalState: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editProvider = context.read<WebsiteEditModeProvider>();
    final effectiveViewport = widget.effectiveViewport;
    _scheduleViewportReport(editProvider, effectiveViewport);
    final blocks = editProvider.blocks;
    final blockIndex = blocks.indexWhere((b) => b['id'] == widget.blockId);
    final isFirst = blockIndex == 0;
    final isLast = blockIndex == blocks.length - 1;

    // Get block height: use local drag height during drag, otherwise from Provider
    final providerHeight = (widget.data['blockHeight'] as num?)?.toDouble();
    final configuredHeight = _isDragging ? _localDragHeight : providerHeight;
    final minHeight = _getMinHeight(widget.blockType);
    final maxHeight = _getMaxHeight(widget.blockType);
    final blockType = _registeredBlockType(widget.blockType);
    final heightBehavior = blockType == null
        ? WebsitePageBlockHeightBehavior.intrinsic
        : WebsiteBlockCapabilityRegistry.profileFor(blockType).heightBehavior;
    final displayHeight =
        heightBehavior == WebsitePageBlockHeightBehavior.intrinsic
            ? null
            : configuredHeight;

    // Which chrome this block may paint is a composition decision, and it has
    // one owner. With a pane the floating action bar and the drag handles are
    // the pointer affordances they have always been. Below the pane threshold
    // the dock already carries identity, reorder, duplicate, visibility and
    // delete at 48 px, so repeating them in a floating 18 px bar would be a
    // second owner AND a sub-target one; a drag handle sized for a pointer has
    // no touch alternative at all, and `Diseño > Altura` in the sheet is the
    // accessible path to the same value.
    //
    // Absent scope keeps the historical behaviour: a host that publishes no
    // geometry (standalone storefront, isolated widget tests) is treated as
    // the pane composition it has always been.
    final usesPane =
        WebsiteEditorChromeScope.maybeOf(context)?.usesPane ?? true;
    final showsPointerBlockChrome = widget.isSelected && usesPane;

    // Build the editable content based on block type
    Widget blockContent = _buildEditableBlock(context);

    // Wrap with selection and action bar
    // Resize handles are INSIDE the Stack so they don't add extra space

    return Listener(
      behavior: HitTestBehavior.opaque,
      // Pointer-down participates in event propagation instead of the gesture
      // arena, so clicking inline text, a CTA, or a Canvas layer always selects
      // its owning block before the nested editor handles the same pointer.
      onPointerDown: (_) {
        // Nested controls re-emit their precise selection themselves. Calling
        // selectBlock for an already-selected owner is not harmless: it is the
        // explicit boundary that clears a Canvas manipulation session. Only
        // restore the owning block when the pointer truly crossed blocks.
        if (editProvider.selectedBlockId != widget.blockId) {
          editProvider.selectBlock(widget.blockId);
        }
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The block content with visibility and height constraint
          // Fixed-height blocks (hero, carousel, canvas) use both min and max height
          // Dynamic content blocks (products, services, etc.) only use minHeight so content can grow
          // NOTE: Avoid wrapping platform views (HtmlElementView) in Opacity/Clip whenever possible
          // to keep web video previews reliable.
          KeyedSubtree(
            key: _contentKey,
            child: displayHeight != null
                ? ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: displayHeight,
                      maxHeight:
                          heightBehavior == WebsitePageBlockHeightBehavior.exact
                              ? displayHeight
                              : double.infinity,
                      minWidth: double.infinity,
                    ),
                    child: blockContent,
                  )
                : blockContent,
          ),

          // Hidden overlay (instead of Opacity around the whole subtree)
          if (!widget.isVisible)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.35),
                ),
              ),
            ),

          // Selection border
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: widget.isSelected
                        ? const Color(0xFF00A09D)
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),

          // Hidden indicator
          if (!widget.isVisible)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade800,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.visibility_off, color: Colors.white, size: 14),
                    SizedBox(width: 4),
                    Text(
                      'Oculto',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),

          // Action bar when selected (pointer composition only)
          if (showsPointerBlockChrome)
            Positioned(
              top: 8,
              right: 8,
              child: BlockActionBar(
                blockId: widget.blockId,
                blockType: widget.blockType,
                isFirst: isFirst,
                isLast: isLast,
                isVisible: widget.isVisible,
                onMoveUp: () => editProvider.moveBlockUp(widget.blockId),
                onMoveDown: () => editProvider.moveBlockDown(widget.blockId),
                onDuplicate: () => editProvider.duplicateBlock(widget.blockId),
                onDelete: () {
                  _confirmDelete(context, editProvider);
                },
                onToggleVisibility: () =>
                    editProvider.toggleBlockVisibility(widget.blockId),
              ),
            ),

          // The contextual host's reorder handle is NOT here: it belongs to the
          // chrome overlay in `PageComposition`, pinned to the same seam as the
          // insert markers. Inside this Stack it was unreachable — a block
          // shorter than 48 cannot hit-test a 48 child, and the full-width
          // «Agregar aquí» band paints over every block's top corner.

          // Top resize handle - positioned INSIDE the block at top edge
          if (showsPointerBlockChrome &&
              heightBehavior != WebsitePageBlockHeightBehavior.intrinsic)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: BlockResizeHandle(
                currentHeight: displayHeight,
                actualHeight: _measuredHeight,
                minHeight: minHeight,
                maxHeight: maxHeight,
                isActive: true,
                isTopHandle: true,
                snapIncrement: 10,
                onHeightChangeStart: (startHeight) => _onDragStart(
                  startHeight,
                  editProvider,
                  effectiveViewport,
                ),
                onHeightChanged: (newHeight) {
                  if (_isDragging) _onDragUpdate(newHeight);
                },
                onHeightChangeEnd: (finalHeight) {
                  _onDragEnd(finalHeight, editProvider);
                },
                onHeightChangeCancel: _cancelHeightManipulation,
              ),
            ),

          // Bottom resize handle - positioned INSIDE the block at bottom edge
          if (showsPointerBlockChrome &&
              heightBehavior != WebsitePageBlockHeightBehavior.intrinsic)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: BlockResizeHandle(
                currentHeight: displayHeight,
                actualHeight: _measuredHeight,
                minHeight: minHeight,
                maxHeight: maxHeight,
                isActive: true,
                isTopHandle: false,
                snapIncrement: 10,
                onHeightChangeStart: (startHeight) => _onDragStart(
                  startHeight,
                  editProvider,
                  effectiveViewport,
                ),
                onHeightChanged: (newHeight) {
                  if (_isDragging) _onDragUpdate(newHeight);
                },
                onHeightChangeEnd: (finalHeight) {
                  _onDragEnd(finalHeight, editProvider);
                },
                onHeightChangeCancel: _cancelHeightManipulation,
                onResetHeight: () =>
                    _onResetHeight(editProvider, effectiveViewport),
              ),
            ),
        ],
      ),
    );
  }

  WebsiteBlockType? _registeredBlockType(String raw) {
    final normalized = raw.trim().toLowerCase();
    for (final type in WebsiteBlockType.values) {
      if (type.name.toLowerCase() == normalized) return type;
    }
    return null;
  }

  /// Get minimum height for block type
  double _getMinHeight(String type) {
    switch (type) {
      case 'hero':
      case 'carousel':
        return 200;
      case 'canvas':
        return 100;
      case 'products':
        return 250;
      case 'services':
      case 'features':
        return 150;
      case 'testimonials':
        return 200;
      case 'gallery':
        return 200;
      case 'cta':
        return 100;
      default:
        return 100;
    }
  }

  /// Get maximum height for block type
  double _getMaxHeight(String type) {
    switch (type) {
      case 'hero':
      case 'carousel':
        return 1000;
      case 'products':
        return 900;
      case 'canvas':
        return 1600;
      default:
        return 800;
    }
  }

  Widget _buildEditableBlock(BuildContext context) {
    // A shared adapted-content override (contentAdapter surface such as the
    // static-policy composition) IS the canonical content tree in every
    // mode; Edit adds only the surrounding chrome.
    if (widget.contentOverride != null) return widget.contentOverride!;
    for (final type in WebsiteBlockType.values) {
      if (type.name.toLowerCase() == widget.blockType.trim().toLowerCase() &&
          WebsiteBlockCapabilityRegistry.profileFor(type)
              .usesSharedContentRendererInEdit) {
        return _buildSharedContent(context);
      }
    }

    return _buildSharedContent(context);
  }

  Widget _buildSharedContent(BuildContext context) {
    final editProvider = context.read<WebsiteEditModeProvider>();
    final manipulationSession = context
        .select<WebsiteEditModeProvider, WebsiteCanvasManipulationSession?>(
      (provider) {
        final session = provider.canvasManipulationSession;
        return session?.target.document.blockId == widget.blockId
            ? session
            : null;
      },
    );

    WebsiteInlineManipulationOwner manipulationOwnerFor(
      WebsiteInlineRepeaterTarget? target,
    ) {
      if (target == null) return const WebsiteInlineBlockOwner();
      return WebsiteInlineRepeaterOwner(
        collectionKeys: target.collectionKeys,
        itemIndex: target.itemIndex,
        identityKey: target.identityKey,
        identityValue: target.identityValue,
      );
    }

    WebsiteBlockFieldSchema? schemaFieldFor(
      WebsiteInlineRepeaterTarget? target,
      List<String> keys,
    ) {
      final type = _registeredBlockType(widget.blockType);
      if (type == null) return null;
      if (target == null) {
        for (final key in keys) {
          final field = WebsiteBlockRegistry.fieldForPath(type, key);
          if (field != null) return field;
        }
        return null;
      }
      for (final collectionKey in target.collectionKeys) {
        for (final key in keys) {
          final field = WebsiteBlockRegistry.fieldForPath(
            type,
            '$collectionKey.$key',
          );
          if (field != null) return field;
        }
      }
      return null;
    }

    WebsiteInlineManipulationProperty? manipulationPropertyFor(
      WebsiteInlineRepeaterTarget? target,
      List<String> keys, {
      List<String> policyKeys = const <String>[],
      bool mayLackSchema = false,
    }) {
      if (keys.isEmpty) return null;
      final policySource = policyKeys.isEmpty ? keys : policyKeys;
      final field = schemaFieldFor(target, policySource);
      assert(
        _registeredBlockType(widget.blockType) == null ||
            field != null ||
            mayLackSchema,
        'Inline transaction for "${keys.first}" has no schema field on '
        '${widget.blockType}.',
      );
      final canonical =
          policyKeys.isEmpty && field != null ? field.key : keys.first;
      final companions = <String>{
        ...keys,
        if (policyKeys.isEmpty && field != null) ...field.migrationAliases,
      }..remove(canonical);
      return WebsiteInlineManipulationProperty(
        canonicalKey: canonical,
        policy: field?.responsivePolicy ??
            WebsiteResponsivePropertyPolicy.sharedOnly,
        sharedCompanionKeys: companions,
      );
    }

    WebsiteInlineManipulationTarget? discreteTargetFor(
      WebsiteInlineRepeaterTarget? target,
      List<WebsiteInlineManipulationProperty> properties, {
      bool requiresSelection = true,
    }) {
      final viewport = editProvider.renderedBlockViewportFor(widget.blockId);
      if (viewport == null || properties.isEmpty) return null;
      return WebsiteInlineManipulationTarget(
        blockId: widget.blockId,
        owner: manipulationOwnerFor(target),
        viewport: viewport,
        properties: properties,
        requiresSelection: requiresSelection,
      );
    }

    WebsiteInlineManipulationLease? captureDiscreteLease(
      WebsiteInlineManipulationTarget? target,
    ) {
      return target == null
          ? null
          : editProvider.captureInlineMutationLease(target);
    }

    WebsiteAsyncFieldBinding? asyncFieldBindingFor(
      WebsiteInlineManipulationTarget? target, {
      required String kind,
      required String slotId,
    }) {
      if (target == null) return null;
      final owner = switch (target.owner) {
        WebsiteInlineBlockOwner() => <String, Object?>{'kind': 'root'},
        WebsiteInlineRepeaterOwner(
          collectionKeys: final collectionKeys,
          itemIndex: final itemIndex,
          identityKey: final identityKey,
          identityValue: final identityValue,
        ) =>
          <String, Object?>{
            'kind': 'repeater',
            'collections': collectionKeys,
            'index': itemIndex,
            'identityKey': identityKey,
            'identityValue': identityValue,
          },
      };
      return WebsiteAsyncFieldBinding.pageBlock(
        provider: editProvider,
        target: WebsiteAsyncFieldTarget.block(
          blockId: widget.blockId,
          scopeKey: jsonEncode(<String, Object?>{
            'surface': 'inline',
            'kind': kind,
            'slot': slotId,
            'viewport': target.viewport.name,
            'owner': owner,
            'properties': target.properties
                .map(
                  (property) => <String, Object?>{
                    'key': property.canonicalKey,
                    'policy': property.policy.name,
                    'companions': property.sharedCompanionKeys.toList()..sort(),
                  },
                )
                .toList(growable: false),
          }),
        ),
      );
    }

    Map<String, dynamic>? currentRepeaterItem(
      WebsiteInlineRepeaterTarget target,
    ) {
      final currentBlock = editProvider.blocks
          .where((block) => block['id'] == widget.blockId)
          .firstOrNull;
      if (currentBlock == null) return null;
      final rawData = currentBlock['block_data'];
      if (rawData is! Map) return null;

      Object? rawCollection;
      for (final key in target.collectionKeys) {
        if (rawData.containsKey(key)) {
          rawCollection = rawData[key];
          break;
        }
      }
      if (rawCollection is! List) return null;

      var index = target.itemIndex;
      if (target.identityKey != null && target.identityValue != null) {
        final identityIndex = rawCollection.indexWhere(
          (item) =>
              item is Map && item[target.identityKey] == target.identityValue,
        );
        if (identityIndex != -1) index = identityIndex;
      }
      if (index < 0 || index >= rawCollection.length) return null;
      final rawItem = rawCollection[index];
      return rawItem is Map ? Map<String, dynamic>.from(rawItem) : null;
    }

    final contentPresenters = WebsiteBlockContentPresenters(
      text: (presenterContext, slot) {
        final textProperty = manipulationPropertyFor(
          slot.repeaterTarget,
          slot.valueKeys,
        );
        final formattingProperty = manipulationPropertyFor(
          slot.repeaterTarget,
          slot.formattingKeys,
          policyKeys: slot.valueKeys,
        );
        final widthProperty = manipulationPropertyFor(
          slot.repeaterTarget,
          slot.widthKeys,
        );
        final properties = <WebsiteInlineManipulationProperty>[
          if (textProperty != null) textProperty,
          if (formattingProperty != null) formattingProperty,
          if (widthProperty != null) widthProperty,
        ];
        final discreteTarget =
            discreteTargetFor(slot.repeaterTarget, properties);
        var discreteLease = captureDiscreteLease(discreteTarget);

        void writeDiscrete(Map<String, Object?> values) {
          final lease = discreteLease;
          if (lease == null) return;
          final result = editProvider.commitInlineMutation(lease, values);
          discreteLease =
              result.accepted ? captureDiscreteLease(discreteTarget) : null;
        }

        return InlineEditableTextV2(
          key: ValueKey<String>(slot.id == 'standalone-text'
              ? 'website-text-inline-content-${widget.blockId}'
              : 'website-inline-text-${widget.blockId}-${slot.id}'),
          text: slot.value,
          baseStyle: slot.baseStyle,
          textAlign: slot.textAlign,
          maxLines: slot.maxLines,
          isEditMode: true,
          placeholder: slot.placeholder,
          formatting: slot.formatting,
          maxWidth: slot.maxWidth,
          fieldKey: '${widget.blockId}-${slot.id}',
          toolbarPreset: slot.toolbarPreset,
          allowWidthResize: slot.widthKeys.isNotEmpty,
          editorPadding: EdgeInsets.zero,
          displayTransform: slot.displayTransform,
          onSessionStart: () {
            final target = discreteTargetFor(slot.repeaterTarget, properties);
            return target == null
                ? null
                : editProvider.beginInlineManipulation(target);
          },
          onSessionCommit: (session, value) {
            if (session is! WebsiteInlineManipulationLease ||
                textProperty == null) {
              return false;
            }
            return editProvider.commitInlineManipulation(
              session,
              <String, Object?>{
                textProperty.canonicalKey: value.text,
                if (formattingProperty != null)
                  formattingProperty.canonicalKey: value.formatting.toJson(),
                if (widthProperty != null)
                  widthProperty.canonicalKey: value.maxWidth,
              },
            );
          },
          onSessionCancel: (session) {
            if (session is WebsiteInlineManipulationLease) {
              editProvider.cancelInlineManipulation(session);
            }
          },
          onTextChanged: textProperty == null
              ? null
              : (value) => writeDiscrete(
                    <String, Object?>{textProperty.canonicalKey: value},
                  ),
          // Formatting and width are companions of the text property: the
          // registry says which one owns them (`formattingKey`), so they
          // follow ITS policy instead of inventing one.
          onFormattingChanged: slot.formattingKeys.isEmpty
              ? null
              : (formatting) => writeDiscrete(
                    <String, Object?>{
                      formattingProperty!.canonicalKey: formatting.toJson(),
                    },
                  ),
          // Width is a declared property of its own where the schema has one
          // (`Text.maxWidth`), so it resolves — and can be per viewport — by
          // itself.
          onWidthChanged: slot.widthKeys.isEmpty
              ? null
              : (width) => writeDiscrete(
                    <String, Object?>{widthProperty!.canonicalKey: width},
                  ),
        );
      },
      media: (presenterContext, slot) {
        final property = manipulationPropertyFor(
          slot.repeaterTarget,
          slot.valueKeys,
        );
        final target = discreteTargetFor(
          slot.repeaterTarget,
          <WebsiteInlineManipulationProperty>[
            if (property != null) property,
          ],
        );
        var lease = captureDiscreteLease(target);
        return InlineEditableImage(
          key: ValueKey<String>(
            'website-inline-media-${widget.blockId}-${slot.id}',
          ),
          imageUrl: slot.url,
          width: double.infinity,
          height: double.infinity,
          fit: slot.fit,
          alignment: slot.alignment,
          isEditMode: true,
          tenantId: widget.tenantId,
          placeholder: slot.fallback,
          borderRadius: slot.borderRadius,
          editAffordance: slot.editAffordance,
          asyncBinding: asyncFieldBindingFor(
            target,
            kind: 'media',
            slotId: slot.id,
          ),
          onChanged: property == null
              ? null
              : (url) {
                  final current = lease;
                  if (current == null) return;
                  final result = editProvider.commitInlineMutation(
                    current,
                    <String, Object?>{property.canonicalKey: url},
                  );
                  lease = result.accepted ? captureDiscreteLease(target) : null;
                },
        );
      },
      action: (presenterContext, slot) {
        final labelProperty = manipulationPropertyFor(
          slot.repeaterTarget,
          slot.labelKeys,
        );
        final hrefProperty = manipulationPropertyFor(
          slot.repeaterTarget,
          slot.hrefKeys,
        );
        final variantProperty = manipulationPropertyFor(
          slot.repeaterTarget,
          slot.variantKeys,
          mayLackSchema: true,
        );
        final actionsProperty = manipulationPropertyFor(
          slot.repeaterTarget,
          <String>[slot.actionsKey],
          mayLackSchema: true,
        );
        final properties = <WebsiteInlineManipulationProperty>[
          if (labelProperty != null) labelProperty,
          if (hrefProperty != null) hrefProperty,
          if (variantProperty != null) variantProperty,
          if (actionsProperty != null) actionsProperty,
        ];
        final target = discreteTargetFor(slot.repeaterTarget, properties);
        var lease = captureDiscreteLease(target);
        return WebsiteInlineActionEditor(
          key: ValueKey<String>(slot.id == 'standalone-button'
              ? 'website-button-inline-label-${widget.blockId}'
              : 'website-inline-action-${widget.blockId}-${slot.id}'),
          action: slot.action,
          asyncBinding: asyncFieldBindingFor(
            target,
            kind: 'action',
            slotId: slot.id,
          ),
          onChanged: (action) {
            final ownerTarget = slot.repeaterTarget;
            final actionOwner = ownerTarget == null
                ? widget.data
                : currentRepeaterItem(ownerTarget);
            final current = lease;
            if (current == null ||
                labelProperty == null ||
                hrefProperty == null ||
                actionsProperty == null) {
              return WebsiteInlineMutationResult.rejected;
            }
            final result = editProvider.commitInlineMutation(
              current,
              <String, Object?>{
                labelProperty.canonicalKey: action.label,
                hrefProperty.canonicalKey: action.href,
                if (variantProperty != null)
                  variantProperty.canonicalKey: action.variant.storageValue,
                actionsProperty.canonicalKey: WebsiteActionValue.mergePrimary(
                  actionOwner?[slot.actionsKey],
                  action,
                ),
              },
            );
            lease = result.accepted ? captureDiscreteLease(target) : null;
            return result;
          },
          onOpen: widget.onNavigate == null ||
                  widget.blockType == 'hero' ||
                  widget.blockType == 'carousel'
              ? null
              : (href) => widget.onNavigate!(href),
          openOnFirstTap: slot.id == 'standalone-button',
          child: slot.child,
        );
      },
    );
    WebsiteCarouselEditBinding? carouselEditBinding;
    if (widget.blockType == 'carousel') {
      final rawSlides = widget.data['slides'];
      final slides = rawSlides is List
          ? rawSlides
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
          : const <Map<String, dynamic>>[];
      final selectedSlideIndex = context.select<WebsiteEditModeProvider, int>(
        (provider) =>
            provider.carouselSlideSelection(widget.blockId, slides.length),
      );
      final selectedCanvasElement =
          context.select<WebsiteEditModeProvider, String?>(
        (provider) => provider.canvasElementSelection(
          widget.blockId,
          slideIndex: selectedSlideIndex,
        ),
      );
      carouselEditBinding = WebsiteCarouselEditBinding(
        selectedSlideIndex: selectedSlideIndex,
        onSlideSelected: (index) => editProvider.selectCarouselSlide(
          widget.blockId,
          index,
          slides.length,
        ),
        canvasBindingForSlide: (slideIndex) {
          final documentTarget = WebsiteCanvasDocumentTarget(
            blockId: widget.blockId,
            slideIndex: slideIndex,
          );
          final measurementGeneration =
              editProvider.renderedCanvasMeasurementGeneration;
          return WebsiteCanvasEditorBinding(
            documentTarget: documentTarget,
            canvasMeasurementGeneration: measurementGeneration,
            onCanvasSizeChanged: (size) =>
                editProvider.reportRenderedCanvasSize(
              documentTarget,
              size,
              expectedMeasurementGeneration: measurementGeneration,
            ),
            activeElementId: slideIndex == selectedSlideIndex
                ? selectedCanvasElement
                : editProvider.canvasElementSelection(
                    widget.blockId,
                    slideIndex: slideIndex,
                  ),
            manipulationSession: manipulationSession,
            manipulationAvailability: (
              layerId,
              mode, {
              required viewport,
            }) =>
                editProvider.canvasManipulationAvailability(
              mode,
              target: WebsiteCanvasLayerTarget(
                document: documentTarget,
                layerId: layerId,
              ),
              viewport: viewport,
            ),
            requestManipulation: (
              layerId,
              mode, {
              required viewport,
            }) =>
                editProvider.startCanvasManipulation(
              mode,
              target: WebsiteCanvasLayerTarget(
                document: documentTarget,
                layerId: layerId,
              ),
              viewport: viewport,
            ),
            commitManipulation: (
              expected,
              expectedDocument,
              expectedDocumentEpoch,
              values, {
              required scope,
            }) {
              if (expected.target.document != documentTarget) return false;
              return editProvider.commitCanvasManipulation(
                expected,
                expectedDocument,
                expectedDocumentEpoch,
                values,
                scope: scope,
              );
            },
            stopManipulation: (expected) =>
                expected.target.document == documentTarget &&
                editProvider.stopCanvasManipulation(
                  expectedSession: expected,
                ),
            captureAsyncIntent: (
              layerId, {
              required scope,
              required viewport,
            }) {
              final target = WebsiteCanvasLayerTarget(
                document: documentTarget,
                layerId: layerId,
              );
              if (editProvider.selectedCanvasLayerTarget != target ||
                  editProvider.renderedCanvasViewport(documentTarget) !=
                      viewport ||
                  editProvider.writeScope != scope) {
                return null;
              }
              return editProvider.captureAsyncIntent(
                blockId: documentTarget.blockId,
              );
            },
            commitAsyncLayerProperties: (
              expectedIntent,
              layerId,
              values, {
              required scope,
              required viewport,
            }) =>
                editProvider.commitAsyncIntent(expectedIntent, () {
              final target = WebsiteCanvasLayerTarget(
                document: documentTarget,
                layerId: layerId,
              );
              if (editProvider.selectedCanvasLayerTarget != target ||
                  editProvider.renderedCanvasViewport(documentTarget) !=
                      viewport ||
                  editProvider.writeScope != scope) {
                return WebsiteInlineMutationResult.rejected;
              }
              final changed = editProvider.setCanvasLayerProperties(
                documentTarget.blockId,
                layerId,
                values,
                slideIndex: documentTarget.slideIndex,
                scope: scope,
                viewport: viewport,
              );
              return changed
                  ? WebsiteInlineMutationResult.committed
                  : WebsiteInlineMutationResult.unchanged;
            }),
            remoteWriteAuthority: (
              expectedIntent,
              layerId, {
              required scope,
              required viewport,
              required operation,
              required isLiveBinding,
            }) =>
                _canvasRemoteWriteAuthority(
              provider: editProvider,
              documentTarget: documentTarget,
              expectedIntent: expectedIntent,
              layerId: layerId,
              scope: scope,
              viewport: viewport,
              operation: operation,
              isLiveBinding: isLiveBinding,
            ),
            // Read at write time, so changing the attribution between two
            // gestures does not need this binding rebuilt.
            writeScope: () => editProvider.writeScope,
            readDocument: () => editProvider.canvasDocument(
              widget.blockId,
              slideIndex: slideIndex,
            ),
            documentEpoch: () => editProvider.pageDocumentEpoch,
            insertLayer: (layer, {required index}) =>
                editProvider.insertCanvasLayer(
              widget.blockId,
              layer,
              slideIndex: slideIndex,
              index: index,
            ),
            removeLayer: (layerId) => editProvider.removeCanvasLayer(
              widget.blockId,
              layerId,
              slideIndex: slideIndex,
            ),
            duplicateLayer: (layerId, newLayerId) =>
                editProvider.duplicateCanvasLayer(
              widget.blockId,
              layerId,
              newLayerId,
              slideIndex: slideIndex,
            ),
            setRootProperties: (values, {required scope, required viewport}) =>
                editProvider.setCanvasRootProperties(
              widget.blockId,
              values,
              slideIndex: slideIndex,
              scope: scope,
              viewport: viewport,
            ),
            clearRootOverrides: (keys, {required viewport}) =>
                editProvider.clearCanvasRootOverrides(
              widget.blockId,
              keys,
              slideIndex: slideIndex,
              viewport: viewport,
            ),
            setLayerProperties: (
              layerId,
              values, {
              required scope,
              required viewport,
            }) =>
                editProvider.setCanvasLayerProperties(
              widget.blockId,
              layerId,
              values,
              slideIndex: slideIndex,
              scope: scope,
              viewport: viewport,
            ),
            clearLayerOverrides: (layerId, keys, {required viewport}) =>
                editProvider.clearCanvasLayerOverrides(
              widget.blockId,
              layerId,
              keys,
              slideIndex: slideIndex,
              viewport: viewport,
            ),
            reorderLayer: (
              layerId,
              targetIndex, {
              required scope,
              required viewport,
            }) =>
                editProvider.reorderCanvasLayer(
              widget.blockId,
              layerId,
              targetIndex,
              slideIndex: slideIndex,
              scope: scope,
              viewport: viewport,
            ),
            onActiveElementChanged: (elementId) {
              editProvider.selectCanvasElement(
                widget.blockId,
                elementId,
                slideIndex: slideIndex,
                slideCount: slides.length,
              );
            },
            onBackgroundTap: () => editProvider.selectBlock(widget.blockId),
          );
        },
      );
    }
    WebsiteCanvasEditorBinding? canvasEditBinding;
    if (widget.blockType == WebsiteBlockType.canvas.name) {
      final selectedCanvasElement =
          context.select<WebsiteEditModeProvider, String?>(
        (provider) => provider.canvasElementSelection(widget.blockId),
      );
      final documentTarget = WebsiteCanvasDocumentTarget(
        blockId: widget.blockId,
      );
      final measurementGeneration =
          editProvider.renderedCanvasMeasurementGeneration;
      canvasEditBinding = WebsiteCanvasEditorBinding(
        documentTarget: documentTarget,
        canvasMeasurementGeneration: measurementGeneration,
        onCanvasSizeChanged: (size) => editProvider.reportRenderedCanvasSize(
          documentTarget,
          size,
          expectedMeasurementGeneration: measurementGeneration,
        ),
        activeElementId: selectedCanvasElement,
        manipulationSession: manipulationSession,
        manipulationAvailability: (
          layerId,
          mode, {
          required viewport,
        }) =>
            editProvider.canvasManipulationAvailability(
          mode,
          target: WebsiteCanvasLayerTarget(
            document: documentTarget,
            layerId: layerId,
          ),
          viewport: viewport,
        ),
        requestManipulation: (
          layerId,
          mode, {
          required viewport,
        }) =>
            editProvider.startCanvasManipulation(
          mode,
          target: WebsiteCanvasLayerTarget(
            document: documentTarget,
            layerId: layerId,
          ),
          viewport: viewport,
        ),
        commitManipulation: (
          expected,
          expectedDocument,
          expectedDocumentEpoch,
          values, {
          required scope,
        }) {
          if (expected.target.document != documentTarget) return false;
          return editProvider.commitCanvasManipulation(
            expected,
            expectedDocument,
            expectedDocumentEpoch,
            values,
            scope: scope,
          );
        },
        stopManipulation: (expected) =>
            expected.target.document == documentTarget &&
            editProvider.stopCanvasManipulation(
              expectedSession: expected,
            ),
        captureAsyncIntent: (
          layerId, {
          required scope,
          required viewport,
        }) {
          final target = WebsiteCanvasLayerTarget(
            document: documentTarget,
            layerId: layerId,
          );
          if (editProvider.selectedCanvasLayerTarget != target ||
              editProvider.renderedCanvasViewport(documentTarget) != viewport ||
              editProvider.writeScope != scope) {
            return null;
          }
          return editProvider.captureAsyncIntent(
            blockId: documentTarget.blockId,
          );
        },
        commitAsyncLayerProperties: (
          expectedIntent,
          layerId,
          values, {
          required scope,
          required viewport,
        }) =>
            editProvider.commitAsyncIntent(expectedIntent, () {
          final target = WebsiteCanvasLayerTarget(
            document: documentTarget,
            layerId: layerId,
          );
          if (editProvider.selectedCanvasLayerTarget != target ||
              editProvider.renderedCanvasViewport(documentTarget) != viewport ||
              editProvider.writeScope != scope) {
            return WebsiteInlineMutationResult.rejected;
          }
          final changed = editProvider.setCanvasLayerProperties(
            documentTarget.blockId,
            layerId,
            values,
            slideIndex: documentTarget.slideIndex,
            scope: scope,
            viewport: viewport,
          );
          return changed
              ? WebsiteInlineMutationResult.committed
              : WebsiteInlineMutationResult.unchanged;
        }),
        remoteWriteAuthority: (
          expectedIntent,
          layerId, {
          required scope,
          required viewport,
          required operation,
          required isLiveBinding,
        }) =>
            _canvasRemoteWriteAuthority(
          provider: editProvider,
          documentTarget: documentTarget,
          expectedIntent: expectedIntent,
          layerId: layerId,
          scope: scope,
          viewport: viewport,
          operation: operation,
          isLiveBinding: isLiveBinding,
        ),
        // Read at write time, so changing the attribution between two
        // gestures does not need this binding rebuilt.
        writeScope: () => editProvider.writeScope,
        readDocument: () => editProvider.canvasDocument(widget.blockId),
        documentEpoch: () => editProvider.pageDocumentEpoch,
        insertLayer: (layer, {required index}) =>
            editProvider.insertCanvasLayer(
          widget.blockId,
          layer,
          index: index,
        ),
        removeLayer: (layerId) => editProvider.removeCanvasLayer(
          widget.blockId,
          layerId,
        ),
        duplicateLayer: (layerId, newLayerId) =>
            editProvider.duplicateCanvasLayer(
          widget.blockId,
          layerId,
          newLayerId,
        ),
        setRootProperties: (values, {required scope, required viewport}) =>
            editProvider.setCanvasRootProperties(
          widget.blockId,
          values,
          scope: scope,
          viewport: viewport,
        ),
        clearRootOverrides: (keys, {required viewport}) =>
            editProvider.clearCanvasRootOverrides(
          widget.blockId,
          keys,
          viewport: viewport,
        ),
        setLayerProperties: (
          layerId,
          values, {
          required scope,
          required viewport,
        }) =>
            editProvider.setCanvasLayerProperties(
          widget.blockId,
          layerId,
          values,
          scope: scope,
          viewport: viewport,
        ),
        clearLayerOverrides: (layerId, keys, {required viewport}) =>
            editProvider.clearCanvasLayerOverrides(
          widget.blockId,
          layerId,
          keys,
          viewport: viewport,
        ),
        reorderLayer: (
          layerId,
          targetIndex, {
          required scope,
          required viewport,
        }) =>
            editProvider.reorderCanvasLayer(
          widget.blockId,
          layerId,
          targetIndex,
          scope: scope,
          viewport: viewport,
        ),
        onActiveElementChanged: (elementId) {
          editProvider.selectCanvasElement(widget.blockId, elementId);
        },
        onBackgroundTap: () => editProvider.selectBlock(widget.blockId),
      );
    }

    return WebsiteBlockRenderer.build(
      context: context,
      blockType: widget.blockType,
      data: widget.data,
      effectiveViewport: widget.effectiveViewport,
      primaryColor: widget.primaryColor,
      accentColor: widget.accentColor,
      featuredProducts: widget.featuredProducts,
      previewMode: true,
      headingFont: widget.headingFont,
      bodyFont: widget.bodyFont,
      headingSize: widget.headingSize,
      bodySize: widget.bodySize,
      onNavigate: widget.onNavigate,
      contentPresenters: contentPresenters,
      carouselEditBinding: carouselEditBinding,
      canvasEditBinding: canvasEditBinding,
      tenantId: widget.tenantId,
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WebsiteEditModeProvider editProvider,
  ) async {
    final blockId = widget.blockId;
    final intent = editProvider.captureAsyncIntent(blockId: blockId);
    if (intent == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Bloque'),
        content:
            const Text('¿Estás seguro de que deseas eliminar este bloque?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final live = context.read<WebsiteEditModeProvider>();
    live.commitAsyncIntent(intent, () {
      final before = live.blocks.length;
      live.deleteBlock(blockId);
      return live.blocks.length < before
          ? WebsiteInlineMutationResult.committed
          : WebsiteInlineMutationResult.unchanged;
    });
  }
}
