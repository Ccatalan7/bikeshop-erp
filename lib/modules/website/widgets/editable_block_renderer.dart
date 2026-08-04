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
import '../models/website_block_geometry.dart';
import '../models/website_block_type.dart';
import '../models/website_responsive_authoring.dart';
import 'website_block_content_presenters.dart';
import 'website_responsive_scalar_binding.dart';
import 'website_block_renderer.dart';
import 'website_editor_chrome_geometry.dart';
import 'website_canvas_editor_binding.dart';
import 'website_carousel_edit_binding.dart';
import 'website_inline_action_editor.dart';
import '../../../shared/models/product.dart';

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

  /// Handle drag start
  void _onDragStart(double startHeight) {
    setState(() {
      _isDragging = true;
      _localDragHeight = startHeight;
    });
  }

  /// Handle drag update (local state only, no Provider rebuild)
  void _onDragUpdate(double newHeight) {
    setState(() {
      _localDragHeight = newHeight;
    });
  }

  /// Handle drag end (commit to Provider)
  void _onDragEnd(double finalHeight, WebsiteEditModeProvider editProvider) {
    editProvider.updateBlockData(widget.blockId, 'blockHeight', finalHeight);
    setState(() {
      _isDragging = false;
      _localDragHeight = null;
    });
  }

  /// Handle height reset
  void _onResetHeight(WebsiteEditModeProvider editProvider) {
    editProvider.updateBlockData(widget.blockId, 'blockHeight', null);
    setState(() {
      _isDragging = false;
      _localDragHeight = null;
    });
    // Re-measure after reset
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureHeight());
  }

  @override
  Widget build(BuildContext context) {
    final editProvider = context.read<WebsiteEditModeProvider>();
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

    // Canvas owns its public geometry and background inside the shared content
    // renderer. Applying a second Edit-only style wrapper would make
    // Edit/Preview/Public disagree on size, padding, clipping, and decoration.
    if (widget.blockType != WebsiteBlockType.canvas.name) {
      // A shared adapted-content override already carries its canonical
      // presentation from the common adapter path; re-applying the persisted
      // style decoration ONLY in Edit would diverge from Preview/Public.
      if (widget.contentOverride == null) {
        blockContent = _applyStyleDecoration(blockContent);
      }
    }

    // Wrap with selection and action bar
    // Resize handles are INSIDE the Stack so they don't add extra space

    return Listener(
      behavior: HitTestBehavior.opaque,
      // Pointer-down participates in event propagation instead of the gesture
      // arena, so clicking inline text, a CTA, or a Canvas layer always selects
      // its owning block before the nested editor handles the same pointer.
      onPointerDown: (_) => editProvider.selectBlock(widget.blockId),
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
                onDelete: () => _confirmDelete(context, editProvider),
                onToggleVisibility: () =>
                    editProvider.toggleBlockVisibility(widget.blockId),
              ),
            ),

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
                onHeightChanged: (newHeight) {
                  if (!_isDragging) {
                    _onDragStart(newHeight);
                  } else {
                    _onDragUpdate(newHeight);
                  }
                },
                onHeightChangeEnd: (finalHeight) {
                  _onDragEnd(finalHeight, editProvider);
                },
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
                onHeightChanged: (newHeight) {
                  if (!_isDragging) {
                    _onDragStart(newHeight);
                  } else {
                    _onDragUpdate(newHeight);
                  }
                },
                onHeightChangeEnd: (finalHeight) {
                  _onDragEnd(finalHeight, editProvider);
                },
                onResetHeight: () => _onResetHeight(editProvider),
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

  /// Apply style decoration from block's style data
  Widget _applyStyleDecoration(Widget child) {
    final rawStyle = widget.data['style'];
    // Standalone buttons use the legacy scalar `style` alias for their action
    // variant. Only a map represents block decoration.
    if (rawStyle is! Map) return child;
    final style = Map<String, dynamic>.from(rawStyle);

    // Check if there's any styling to apply
    final hasBackground = style['backgroundColor'] != null ||
        style['backgroundType'] == 'gradient';
    final hasBorder = (style['borderWidth'] as num?)?.toDouble() != null &&
        (style['borderWidth'] as num).toDouble() > 0;
    final hasShadow = style['shadowEnabled'] == true;
    final hasBorderRadius =
        (style['borderRadius'] as num?)?.toDouble() != null &&
            (style['borderRadius'] as num).toDouble() > 0;
    final hasPadding = style['paddingTop'] != null ||
        style['paddingRight'] != null ||
        style['paddingBottom'] != null ||
        style['paddingLeft'] != null;

    // Return child as-is if no styling
    if (!hasBackground &&
        !hasBorder &&
        !hasShadow &&
        !hasBorderRadius &&
        !hasPadding) {
      return child;
    }

    // Parse padding
    final paddingTop = (style['paddingTop'] as num?)?.toDouble() ?? 0.0;
    final paddingRight = (style['paddingRight'] as num?)?.toDouble() ?? 0.0;
    final paddingBottom = (style['paddingBottom'] as num?)?.toDouble() ?? 0.0;
    final paddingLeft = (style['paddingLeft'] as num?)?.toDouble() ?? 0.0;

    // Parse border
    final borderWidth = (style['borderWidth'] as num?)?.toDouble() ?? 0.0;
    final borderColor =
        _parseColor(style['borderColor']?.toString()) ?? Colors.grey;
    final borderRadius = (style['borderRadius'] as num?)?.toDouble() ?? 0.0;
    final borderStyle = style['borderStyle']?.toString() ?? 'solid';

    // Parse shadow
    final shadowOffsetX = (style['shadowOffsetX'] as num?)?.toDouble() ?? 0.0;
    final shadowOffsetY = (style['shadowOffsetY'] as num?)?.toDouble() ?? 4.0;
    final shadowBlur = (style['shadowBlur'] as num?)?.toDouble() ?? 12.0;
    final shadowSpread = (style['shadowSpread'] as num?)?.toDouble() ?? 0.0;
    final shadowColor =
        _parseRgbaColor(style['shadowColor']?.toString()) ?? Colors.black26;

    // Parse background
    final backgroundType = style['backgroundType']?.toString() ?? 'solid';
    Decoration? decoration;

    if (backgroundType == 'gradient') {
      final gradientColor1 =
          _parseColor(style['gradientColor1']?.toString()) ?? Colors.white;
      final gradientColor2 = _parseColor(style['gradientColor2']?.toString()) ??
          Colors.grey.shade100;
      final gradientDirection =
          style['gradientDirection']?.toString() ?? 'to-bottom';

      decoration = BoxDecoration(
        gradient: LinearGradient(
          begin: _getGradientBegin(gradientDirection),
          end: _getGradientEnd(gradientDirection),
          colors: [gradientColor1, gradientColor2],
        ),
        border: hasBorder
            ? Border.all(
                color: borderColor,
                width: borderWidth,
                style: borderStyle == 'dotted' || borderStyle == 'dashed'
                    ? BorderStyle.none
                    : BorderStyle.solid,
              )
            : null,
        borderRadius:
            hasBorderRadius ? BorderRadius.circular(borderRadius) : null,
        boxShadow: hasShadow
            ? [
                BoxShadow(
                  offset: Offset(shadowOffsetX, shadowOffsetY),
                  blurRadius: shadowBlur,
                  spreadRadius: shadowSpread,
                  color: shadowColor,
                ),
              ]
            : null,
      );
    } else {
      final backgroundColor = _parseColor(style['backgroundColor']?.toString());

      decoration = BoxDecoration(
        color: backgroundColor,
        border: hasBorder
            ? Border.all(
                color: borderColor,
                width: borderWidth,
              )
            : null,
        borderRadius:
            hasBorderRadius ? BorderRadius.circular(borderRadius) : null,
        boxShadow: hasShadow
            ? [
                BoxShadow(
                  offset: Offset(shadowOffsetX, shadowOffsetY),
                  blurRadius: shadowBlur,
                  spreadRadius: shadowSpread,
                  color: shadowColor,
                ),
              ]
            : null,
      );
    }

    final typeLower = widget.blockType.trim().toLowerCase();
    final hasVideoFileUrl =
        (widget.data['videoFileUrl']?.toString() ?? '').trim().isNotEmpty;
    final hasVideoUrl =
        (widget.data['videoUrl']?.toString() ?? '').trim().isNotEmpty;

    // Platform views (HtmlElementView) are fragile under clipping on Flutter Web.
    // If this block contains an embedded video, prefer not to clip.
    final avoidClipForPlatformView =
        typeLower == 'videobanner' && (hasVideoFileUrl || hasVideoUrl);

    // Apply ClipRRect for border radius to clip child content
    Widget result = Container(
      decoration: decoration,
      padding: hasPadding
          ? EdgeInsets.only(
              top: paddingTop,
              right: paddingRight,
              bottom: paddingBottom,
              left: paddingLeft,
            )
          : null,
      child: hasBorderRadius && !avoidClipForPlatformView
          ? ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius),
              child: child,
            )
          : child,
    );

    return result;
  }

  /// Parse hex color string to Color
  Color? _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    try {
      final buffer = StringBuffer();
      if (hex.length == 6 || hex.length == 7) buffer.write('ff');
      buffer.write(hex.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return null;
    }
  }

  /// Parse rgba color string to Color
  Color? _parseRgbaColor(String? rgba) {
    if (rgba == null || rgba.isEmpty) return null;
    try {
      // Handle hex colors
      if (rgba.startsWith('#')) return _parseColor(rgba);

      // Handle rgba(r,g,b,a) format
      final match = RegExp(r'rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)')
          .firstMatch(rgba);
      if (match != null) {
        final r = int.parse(match.group(1)!);
        final g = int.parse(match.group(2)!);
        final b = int.parse(match.group(3)!);
        final a = match.group(4) != null ? double.parse(match.group(4)!) : 1.0;
        return Color.fromRGBO(r, g, b, a);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Get gradient start alignment from direction string
  Alignment _getGradientBegin(String direction) {
    switch (direction) {
      case 'to-top':
        return Alignment.bottomCenter;
      case 'to-top-right':
        return Alignment.bottomLeft;
      case 'to-right':
        return Alignment.centerLeft;
      case 'to-bottom-right':
        return Alignment.topLeft;
      case 'to-bottom':
        return Alignment.topCenter;
      case 'to-bottom-left':
        return Alignment.topRight;
      case 'to-left':
        return Alignment.centerRight;
      case 'to-top-left':
        return Alignment.bottomRight;
      default:
        return Alignment.topCenter;
    }
  }

  /// Get gradient end alignment from direction string
  Alignment _getGradientEnd(String direction) {
    switch (direction) {
      case 'to-top':
        return Alignment.topCenter;
      case 'to-top-right':
        return Alignment.topRight;
      case 'to-right':
        return Alignment.centerRight;
      case 'to-bottom-right':
        return Alignment.bottomRight;
      case 'to-bottom':
        return Alignment.bottomCenter;
      case 'to-bottom-left':
        return Alignment.bottomLeft;
      case 'to-left':
        return Alignment.centerLeft;
      case 'to-top-left':
        return Alignment.topLeft;
      default:
        return Alignment.bottomCenter;
    }
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

    // The inline half of the responsive protocol. Every schema-bound gesture
    // below goes through it, so an edit made on a phone canvas lands where the
    // visible scope says it will — instead of always rewriting the base.
    final inlineWriter = WebsiteInlineResponsiveWriter(
      provider: editProvider,
      blockId: widget.blockId,
      blockType: _registeredBlockType(widget.blockType),
      hostClass: WebsiteEditorChromeScope.maybeOf(context)?.hostClass ??
          WebsiteAuthoringHostClass.desktop,
    );

    WebsiteResponsiveFieldOwner ownerFor(WebsiteInlineRepeaterTarget? target) {
      if (target == null) return const WebsiteResponsiveRootField();
      // The item's own identity when it already persists one; otherwise the
      // explicit index. Nothing is invented, and a sibling is never touched.
      return WebsiteResponsiveRepeaterField(
        collectionKeys: target.collectionKeys,
        itemIndex: target.itemIndex,
        identityKey: target.identityKey,
        identityValue: target.identityValue,
      );
    }

    void writeInline(
      WebsiteInlineRepeaterTarget? target,
      List<WebsiteInlinePropertyWrite> writes,
    ) {
      if (writes.isEmpty) return;
      inlineWriter.write(owner: ownerFor(target), writes: writes);
    }

    void updateBoundValue(
      WebsiteInlineRepeaterTarget? target,
      List<String> keys,
      Object? value, {
      List<String> policyKeys = const <String>[],
    }) {
      if (keys.isEmpty) return;
      writeInline(target, <WebsiteInlinePropertyWrite>[
        WebsiteInlinePropertyWrite(
          keys: keys,
          value: value,
          policyKeys: policyKeys,
        ),
      ]);
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
          onTextChanged: (value) => updateBoundValue(
            slot.repeaterTarget,
            slot.valueKeys,
            value,
          ),
          // Formatting and width are companions of the text property: the
          // registry says which one owns them (`formattingKey`), so they
          // follow ITS policy instead of inventing one.
          onFormattingChanged: slot.formattingKeys.isEmpty
              ? null
              : (formatting) => updateBoundValue(
                    slot.repeaterTarget,
                    slot.formattingKeys,
                    formatting.toJson(),
                    policyKeys: slot.valueKeys,
                  ),
          // Width is a declared property of its own where the schema has one
          // (`Text.maxWidth`), so it resolves — and can be per viewport — by
          // itself.
          onWidthChanged: slot.widthKeys.isEmpty
              ? null
              : (width) => updateBoundValue(
                    slot.repeaterTarget,
                    slot.widthKeys,
                    width,
                  ),
        );
      },
      media: (presenterContext, slot) => InlineEditableImage(
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
        onChanged: (url) => updateBoundValue(
          slot.repeaterTarget,
          slot.valueKeys,
          url,
        ),
      ),
      action: (presenterContext, slot) => WebsiteInlineActionEditor(
        key: ValueKey<String>(slot.id == 'standalone-button'
            ? 'website-button-inline-label-${widget.blockId}'
            : 'website-inline-action-${widget.blockId}-${slot.id}'),
        action: slot.action,
        onChanged: (action) {
          final target = slot.repeaterTarget;
          final actionOwner =
              target == null ? widget.data : currentRepeaterItem(target);
          // One gesture, one history entry. Label, destination and variant are
          // three declared properties of the same action: each resolves its
          // own policy — today all shared — and the composite `actions` mirror
          // stays common so the three never drift apart.
          writeInline(target, <WebsiteInlinePropertyWrite>[
            WebsiteInlinePropertyWrite(
              keys: slot.labelKeys,
              value: action.label,
            ),
            WebsiteInlinePropertyWrite(
              keys: slot.hrefKeys,
              value: action.href,
            ),
            if (slot.variantKeys.isNotEmpty)
              WebsiteInlinePropertyWrite(
                keys: slot.variantKeys,
                value: action.variant.storageValue,
                // Presentation of the action, persisted next to it. Where a
                // family declares it as a field it resolves like any other;
                // where it does not, it stays common with the destination it
                // belongs to.
                mayLackSchema: true,
              ),
            WebsiteInlinePropertyWrite(
              keys: <String>[slot.actionsKey],
              value: WebsiteActionValue.mergePrimary(
                actionOwner?[slot.actionsKey],
                action,
              ),
              mayLackSchema: true,
            ),
          ]);
        },
        onOpen: widget.onNavigate == null ||
                widget.blockType == 'hero' ||
                widget.blockType == 'carousel'
            ? null
            : (href) => widget.onNavigate!(href),
        openOnFirstTap: slot.id == 'standalone-button',
        child: slot.child,
      ),
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
        canvasBindingForSlide: (slideIndex) => WebsiteCanvasEditorBinding(
          activeElementId: slideIndex == selectedSlideIndex
              ? selectedCanvasElement
              : editProvider.canvasElementSelection(
                  widget.blockId,
                  slideIndex: slideIndex,
                ),
          // Read at write time, so changing the attribution between two
          // gestures does not need this binding rebuilt.
          writeScope: () => editProvider.writeScope,
          readDocument: () => editProvider.canvasDocument(
            widget.blockId,
            slideIndex: slideIndex,
          ),
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
        ),
      );
    }
    WebsiteCanvasEditorBinding? canvasEditBinding;
    if (widget.blockType == WebsiteBlockType.canvas.name) {
      final selectedCanvasElement =
          context.select<WebsiteEditModeProvider, String?>(
        (provider) => provider.canvasElementSelection(widget.blockId),
      );
      canvasEditBinding = WebsiteCanvasEditorBinding(
        activeElementId: selectedCanvasElement,
        // Read at write time, so changing the attribution between two
        // gestures does not need this binding rebuilt.
        writeScope: () => editProvider.writeScope,
        readDocument: () => editProvider.canvasDocument(widget.blockId),
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

  void _confirmDelete(
      BuildContext context, WebsiteEditModeProvider editProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Bloque'),
        content:
            const Text('¿Estás seguro de que deseas eliminar este bloque?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              editProvider.deleteBlock(widget.blockId);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}
