import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/website_edit_mode_provider.dart';
import '../widgets/inline_editable_text_v2.dart';
import '../widgets/inline_editable_image.dart';
import '../widgets/block_resize_handle.dart';
import '../widgets/block_action_bar.dart';
import '../widgets/text_formatting_toolbar.dart';
import '../widgets/canvas_block.dart';
import '../widgets/website_link_value_editor.dart';
import '../models/website_font_registry.dart';
import '../models/website_action.dart';
import 'website_block_renderer.dart';
import '../../../shared/models/product.dart';
import '../../../shared/widgets/safe_layout_builder.dart';

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
  }) {
    headingFont = WebsiteFontRegistry.resolveOptionalHeadingFont(headingFont);
    bodyFont = WebsiteFontRegistry.resolveOptionalBodyFont(bodyFont);

    // Use Selector to only rebuild when edit mode or selection changes for THIS block
    return Selector<WebsiteEditModeProvider,
        ({bool isEditMode, bool isSelected})>(
      selector: (_, provider) => (
        isEditMode: provider.isEditMode,
        isSelected: provider.selectedBlockId == blockId,
      ),
      builder: (context, state, child) {
        final isEditMode = state.isEditMode;
        final isSelected = state.isSelected;

        // If not in edit mode, render normally
        if (!isEditMode) {
          if (!isVisible) return const SizedBox.shrink();

          // Debug: trace preview mode data
          if (blockType == 'hero') {
            debugPrint(
                '🎨 [EditableBlockRenderer] Preview Mode - Hero data.style: ${data['style']}');
          }

          return WebsiteBlockRenderer.build(
            context: context,
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
            tenantId: tenantId,
          );
        }

        // Edit mode - render with editing capability
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

  WebsiteActionValue? _resolvePrimaryNavigateAction(
    Map<String, dynamic> data, {
    required String fallbackLabel,
    required String fallbackTo,
    bool enabled = true,
  }) {
    return WebsiteActionValue.resolvePrimary(
      data,
      labelKeys: const ['ctaText', 'buttonText', 'label'],
      hrefKeys: const ['ctaLink', 'buttonLink', 'link'],
      defaultLabel: fallbackLabel,
      defaultHref: fallbackTo,
      enabled: enabled,
    );
  }

  /// Apply font family via CSS font-family instead of GoogleFonts package
  /// (GoogleFonts adds ~6.5MB to bundle with all font metadata)
  static TextStyle _applyThemeFont(TextStyle base, String? fontFamily) {
    final family = fontFamily?.trim();
    if (family == null || family.isEmpty) return base;
    // Apply font family directly - browser loads via CSS @font-face or system fonts
    return base.copyWith(fontFamily: family);
  }

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
    final displayHeight = _isDragging ? _localDragHeight : providerHeight;
    final minHeight = _getMinHeight(widget.blockType);
    final maxHeight = _getMaxHeight(widget.blockType);

    // Blocks with dynamic content should NOT have maxHeight constrained
    // (their content needs to grow naturally)
    final dynamicContentBlocks = {
      'products',
      'services',
      'features',
      'testimonials',
      'faq',
      'team',
      'pricing',
      'stats',
      'gallery',
      'categoryGrid',
      'brandLogos',
      'partnersBanner',
    };
    final isDynamicContent = dynamicContentBlocks.contains(widget.blockType);

    // Build the editable content based on block type
    Widget blockContent = _buildEditableBlock(context);

    // Apply style decoration (border, shadow, gradient, padding)
    blockContent = _applyStyleDecoration(blockContent);

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
                      // Only apply maxHeight for fixed-height blocks, not dynamic content
                      maxHeight:
                          isDynamicContent ? double.infinity : displayHeight,
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

          // Action bar when selected
          if (widget.isSelected)
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
          if (widget.isSelected)
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
          if (widget.isSelected)
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

  /// Apply style decoration from block's style data
  Widget _applyStyleDecoration(Widget child) {
    final style = Map<String, dynamic>.from(widget.data['style'] ?? {});

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
    // For now, use the standard renderer
    // In a full implementation, each block type would have its own editable version
    switch (widget.blockType) {
      case 'hero':
        return _buildEditableHero(context);
      case 'carousel':
        return _buildEditableCarousel(context);
      case 'canvas':
        return _buildEditableCanvas(context);
      case 'text':
        return _buildEditableText(context);
      case 'button':
        return _buildEditableButton(context);
      case 'divider':
        return _buildEditableDivider(context);
      case 'about':
        return _buildEditableAbout(context);
      case 'cta':
        return _buildEditableCta(context);
      case 'features':
        return _buildEditableFeatures(context);
      case 'faq':
        return _buildEditableFaq(context);
      case 'contact':
        return _buildEditableContact(context);
      case 'services':
        return _buildEditableServices(context);
      case 'pricing':
        return _buildEditablePricing(context);
      case 'testimonials':
        return _buildEditableTestimonials(context);
      case 'stats':
        return _buildEditableStats(context);
      case 'team':
        return _buildEditableTeam(context);
      case 'gallery':
        return _buildEditableGallery(context);
      default:
        // Fall back to standard renderer for other types
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
          tenantId: widget.tenantId,
        );
    }
  }

  Widget _buildEditableCanvas(BuildContext context) {
    final editProvider = context.read<WebsiteEditModeProvider>();
    final currentElements = (() {
      final raw = widget.data['elements'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return <Map<String, dynamic>>[];
    })();

    return CanvasBlock(
      data: <String, dynamic>{
        ...widget.data,
        'activeElementId': editProvider.canvasElementSelection(widget.blockId),
      },
      editable: true,
      accentColor: widget.accentColor,
      onNavigate: widget.onNavigate,
      tenantId: widget.tenantId,
      headingFont: widget.headingFont,
      bodyFont: widget.bodyFont,
      // Don't auto-set designWidth from viewport - use fixed reference width for WYSIWYG consistency
      onBackgroundTap: () {
        // Select this block when tapping the canvas background
        editProvider.selectBlock(widget.blockId);
      },
      onActiveElementChanged: (id) {
        editProvider.selectCanvasElement(widget.blockId, id);
      },
      onElementsChanged: (elements) {
        // Avoid needless writes
        if (elements.length == currentElements.length) {
          // still update (positions changed), this is ok.
        }
        editProvider.updateBlockData(widget.blockId, 'elements', elements);
      },
    );
  }

  Widget _buildEditableText(BuildContext context) {
    final editProvider = context.read<WebsiteEditModeProvider>();
    final text = (widget.data['text'] ?? '').toString();
    final preset = (widget.data['preset'] ?? 'paragraph').toString();
    final maxWidth = (widget.data['maxWidth'] as num?)?.toDouble();
    final formatting = TextFormatting.fromJson(
        widget.data['formatting'] as Map<String, dynamic>?);

    TextStyle base;
    switch (preset) {
      case 'heading':
        base = TextStyle(
          fontSize: widget.headingSize ?? 40,
          fontWeight: FontWeight.w700,
          fontFamily: widget.headingFont,
          color: Colors.black87,
        );
        break;
      case 'subheading':
        base = TextStyle(
          fontSize: (widget.bodySize ?? 16) * 1.25,
          fontWeight: FontWeight.w600,
          fontFamily: widget.headingFont ?? widget.bodyFont,
          color: Colors.black87,
        );
        break;
      case 'caption':
        base = TextStyle(
          fontSize: (widget.bodySize ?? 16) * 0.9,
          fontWeight: FontWeight.w400,
          fontFamily: widget.bodyFont,
          color: Colors.black54,
        );
        break;
      default:
        base = TextStyle(
          fontSize: widget.bodySize ?? 16,
          fontWeight: FontWeight.w400,
          fontFamily: widget.bodyFont,
          color: Colors.black87,
        );
    }

    Widget content = InlineEditableTextV2(
      text: text,
      baseStyle: base,
      textAlign: formatting.textAlign,
      maxLines: null,
      isEditMode: true,
      placeholder: 'Haz clic para escribir',
      formatting: formatting,
      maxWidth: maxWidth,
      onTextChanged: (value) =>
          editProvider.updateBlockData(widget.blockId, 'text', value),
      onFormattingChanged: (fmt) => editProvider.updateBlockData(
        widget.blockId,
        'formatting',
        fmt.toJson(),
      ),
      onWidthChanged: (w) =>
          editProvider.updateBlockData(widget.blockId, 'maxWidth', w),
    );

    if (maxWidth != null) {
      content = Center(child: content);
    }

    return content;
  }

  Widget _buildEditableButton(BuildContext context) {
    final editProvider = context.read<WebsiteEditModeProvider>();
    final action = WebsiteActionValue.resolvePrimary(
          widget.data,
          labelKeys: const ['label', 'text'],
          hrefKeys: const ['link'],
          defaultLabel: 'Botón',
          defaultVariant: WebsiteActionVariant.fromStorage(
            widget.data['style']?.toString(),
          ),
        ) ??
        WebsiteActionValue(
          label: (widget.data['label'] ?? 'Botón').toString(),
          href: (widget.data['link'] ?? '').toString(),
          variant: WebsiteActionVariant.fromStorage(
              widget.data['style']?.toString()),
        );
    final label = action.label;
    final link = action.href;
    final style = action.variant.storageValue;

    VoidCallback? onPressed;
    if (link.isNotEmpty && widget.onNavigate != null) {
      onPressed = () => widget.onNavigate!(link);
    }

    final child = InlineEditableTextV2(
      text: label,
      isEditMode: true,
      baseStyle: const TextStyle(fontWeight: FontWeight.w600),
      placeholder: 'Botón',
      toolbarPreset: TextToolbarPreset.textOnly,
      onTextChanged: (v) => editProvider.updateBlockDataMultiple(
        widget.blockId,
        {
          'label': v,
          'actions': WebsiteActionValue.mergePrimary(
            widget.data['actions'],
            action.copyWith(label: v),
          ),
        },
      ),
    );

    switch (style) {
      case 'outline':
        return OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: widget.accentColor,
            side: BorderSide(color: widget.accentColor),
          ),
          child: child,
        );
      case 'text':
        return TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: widget.accentColor,
          ),
          child: child,
        );
      default:
        return ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.accentColor,
            foregroundColor: Colors.white,
          ),
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: Colors.white),
            child: child,
          ),
        );
    }
  }

  Widget _buildEditableDivider(BuildContext context) {
    final editProvider = context.read<WebsiteEditModeProvider>();
    final thickness = (widget.data['thickness'] as num?)?.toDouble() ?? 1.0;
    final widthPct = (widget.data['widthPct'] as num?)?.toDouble() ?? 1.0;
    final colorRaw = (widget.data['color'] ?? '#E0E0E0').toString();
    final color = _parseHexColor(colorRaw) ?? Colors.grey.shade300;

    return GestureDetector(
      onTap: () => editProvider.selectBlock(widget.blockId),
      child: Center(
        child: FractionallySizedBox(
          widthFactor: widthPct.clamp(0.1, 1.0),
          child: Divider(
            thickness: thickness.clamp(1, 12),
            height: thickness.clamp(1, 12),
            color: color,
          ),
        ),
      ),
    );
  }

  Color? _parseHexColor(String raw) {
    try {
      var hex = raw.trim().replaceAll('#', '');
      if (hex.isEmpty) return null;
      if (hex.length == 6) hex = 'FF$hex';
      if (hex.length != 8) return null;
      return Color(int.parse(hex, radix: 16));
    } catch (_) {
      return null;
    }
  }

  Widget _buildEditableCarousel(BuildContext context) {
    final editProvider = context.read<WebsiteEditModeProvider>();

    // Parse slides from data
    final rawSlides = widget.data['slides'];
    List<Map<String, dynamic>> slides = [];
    if (rawSlides is List) {
      slides = rawSlides
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    // Default slide if empty
    if (slides.isEmpty) {
      slides = [
        {
          'title': 'Título del Banner',
          'subtitle': 'Subtítulo descriptivo',
          'ctaText': 'Ver más',
          'ctaLink': '/productos',
        }
      ];
    }

    // Configuration
    final showIndicators = (widget.data['showIndicators'] ?? true) == true;
    final showArrows = (widget.data['showArrows'] ?? true) == true;
    final rawAnimationDuration =
        widget.data['animationDurationMs'] ?? widget.data['transitionDuration'];
    var animationDurationMs = 600;
    if (rawAnimationDuration is num) {
      animationDurationMs = rawAnimationDuration.toInt();
    } else if (rawAnimationDuration is String) {
      animationDurationMs = int.tryParse(rawAnimationDuration) ?? 600;
    }
    final animationDuration =
        Duration(milliseconds: math.max(1, animationDurationMs));
    final selectedSlideIndex = context.select<WebsiteEditModeProvider, int>(
      (provider) =>
          provider.carouselSlideSelection(widget.blockId, slides.length),
    );

    // Use LayoutBuilder to get live height from parent constraints (for smooth resize)
    return ConstraintLayoutBuilder(
      builder: (context, constraints) {
        final constraintHeight =
            constraints.maxHeight.isFinite ? constraints.maxHeight : null;
        final dataHeight = (widget.data['blockHeight'] as num?)?.toDouble();
        final blockHeight = constraintHeight ?? dataHeight;

        return _EditableCarouselWidget(
          slides: slides,
          showIndicators: showIndicators,
          showArrows: showArrows,
          primaryColor: widget.primaryColor,
          accentColor: widget.accentColor,
          headingFont: widget.headingFont,
          bodyFont: widget.bodyFont,
          headingSize: widget.headingSize,
          bodySize: widget.bodySize,
          blockId: widget.blockId,
          blockHeight: blockHeight,
          animationDuration: animationDuration,
          selectedSlideIndex: selectedSlideIndex,
          onSlideSelected: (index) => editProvider.selectCarouselSlide(
            widget.blockId,
            index,
            slides.length,
          ),
          onSlideUpdated: (index, field, value) {
            debugPrint(
                '🔄 [EditableCarousel] Slide update: index=$index, field=$field');
            // Update the slide data in the block
            final updatedSlides = List<Map<String, dynamic>>.from(slides);
            if (index < updatedSlides.length) {
              updatedSlides[index] =
                  Map<String, dynamic>.from(updatedSlides[index]);
              updatedSlides[index][field] = value;
              editProvider.updateBlockData(
                  widget.blockId, 'slides', updatedSlides);
            }
          },
          onSlideTransientUpdated: (index, field, value) {
            if (field == 'activeElementId') {
              editProvider.selectCanvasElement(
                widget.blockId,
                value?.toString(),
                slideIndex: index,
                slideCount: slides.length,
              );
            }
          },
          onSlideActionUpdated: (index, action) {
            final updatedSlides = List<Map<String, dynamic>>.from(slides);
            if (index >= updatedSlides.length) return;
            final current = Map<String, dynamic>.from(updatedSlides[index]);
            updatedSlides[index] = <String, dynamic>{
              ...current,
              'ctaText': action.label,
              'buttonText': action.label,
              'ctaLink': action.href,
              'buttonLink': action.href,
              'actions': WebsiteActionValue.mergePrimary(
                current['actions'],
                action,
              ),
            };
            editProvider.updateBlockData(
              widget.blockId,
              'slides',
              updatedSlides,
            );
          },
          onNavigate: widget.onNavigate,
          tenantId: widget.tenantId,
        );
      },
    );
  }

  Widget _buildEditableHero(BuildContext context) {
    final editProvider = context.read<WebsiteEditModeProvider>();
    final theme = Theme.of(context);

    final title = (widget.data['title'] ?? '').toString();
    final subtitle = (widget.data['subtitle'] ?? '').toString();
    final ctaText =
        (widget.data['ctaText'] ?? widget.data['buttonText'] ?? 'Ver más')
            .toString();
    final ctaLink =
        (widget.data['ctaLink'] ?? widget.data['buttonLink'] ?? '').toString();
    final heroAction = WebsiteActionValue.resolvePrimary(
          widget.data,
          labelKeys: const ['ctaText', 'buttonText'],
          hrefKeys: const ['ctaLink', 'buttonLink'],
          defaultLabel: 'Ver más',
          defaultHref: ctaLink,
          defaultVariant: WebsiteActionVariant.outline,
        ) ??
        WebsiteActionValue(
          label: ctaText.isEmpty ? 'Ver más' : ctaText,
          href: ctaLink,
          variant: WebsiteActionVariant.outline,
        );
    final imageUrl =
        (widget.data['imageUrl'] ?? widget.data['backgroundImage'])?.toString();

    // Get formatting data if saved
    final titleFormatting = TextFormatting.fromJson(
        widget.data['titleFormatting'] as Map<String, dynamic>?);
    final subtitleFormatting = TextFormatting.fromJson(
        widget.data['subtitleFormatting'] as Map<String, dynamic>?);

    final headingStyle = _applyThemeFont(
      (theme.textTheme.displayLarge ?? const TextStyle()).copyWith(
        fontSize: widget.headingSize ?? 48,
        color: Colors.white,
      ),
      widget.headingFont,
    );

    final subtitleStyle = _applyThemeFont(
      (theme.textTheme.headlineSmall ?? const TextStyle()).copyWith(
        fontSize: widget.bodySize != null ? widget.bodySize! * 1.2 : 20,
        color: Colors.white70,
      ),
      widget.bodyFont,
    );

    // Use LayoutBuilder to get live height from parent constraints (for smooth resize)
    // Fall back to widget.data['blockHeight'] or default 480 if no constraints
    return ConstraintLayoutBuilder(
      builder: (context, constraints) {
        final constraintHeight =
            constraints.maxHeight.isFinite ? constraints.maxHeight : null;
        final dataHeight = (widget.data['blockHeight'] as num?)?.toDouble();
        final blockHeight = constraintHeight ?? dataHeight ?? 480.0;

        // Detect mobile based on available width (for editor preview)
        final isMobile = constraints.maxWidth < 600;

        // Resolve shared desktop/mobile focal point values.
        final desktopFocalX =
            (widget.data['focalPointX'] as num?)?.toDouble() ?? 0.5;
        final desktopFocalY =
            (widget.data['focalPointY'] as num?)?.toDouble() ?? 0.5;
        Alignment bgAlignment = Alignment(
          (desktopFocalX * 2) - 1,
          (desktopFocalY * 2) - 1,
        );
        if (isMobile) {
          final focalX = (widget.data['mobileFocalPointX'] as num?)?.toDouble();
          final focalY = (widget.data['mobileFocalPointY'] as num?)?.toDouble();

          if (focalX != null && focalY != null) {
            // Convert from 0-1 range to -1 to 1 range for Alignment
            bgAlignment = Alignment(
              (focalX * 2) - 1,
              (focalY * 2) - 1,
            );
          } else if (widget.data['mobileBgAlignment'] != null) {
            // Legacy fallback
            switch (widget.data['mobileBgAlignment'].toString()) {
              case 'left':
              case 'centerLeft':
                bgAlignment = Alignment.centerLeft;
                break;
              case 'right':
              case 'centerRight':
                bgAlignment = Alignment.centerRight;
                break;
              case 'top':
              case 'topCenter':
                bgAlignment = Alignment.topCenter;
                break;
              case 'bottom':
              case 'bottomCenter':
                bgAlignment = Alignment.bottomCenter;
                break;
              case 'center':
              default:
                bgAlignment = Alignment.center;
            }
          }
        }

        return SizedBox(
          height: blockHeight,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background image (editable) with alignment
              InlineEditableImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                alignment: bgAlignment,
                isEditMode: true,
                onChanged: (url) => editProvider.updateBlockDataMultiple(
                  widget.blockId,
                  {
                    'imageUrl': url,
                    'backgroundImage': url,
                  },
                ),
                placeholder: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        widget.primaryColor,
                        widget.accentColor.withValues(alpha: 0.85)
                      ],
                    ),
                  ),
                ),
              ),

              // Overlay
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.4),
                      Colors.black.withValues(alpha: 0.6),
                    ],
                  ),
                ),
              ),

              // Content
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Editable title with formatting toolbar
                      InlineEditableTextV2(
                        text: title,
                        baseStyle: headingStyle,
                        textAlign: TextAlign.center,
                        isEditMode: true,
                        placeholder: 'Título Principal',
                        formatting: titleFormatting,
                        fieldKey: '${widget.blockId}_title',
                        onTextChanged: (value) => editProvider.updateBlockData(
                            widget.blockId, 'title', value),
                        onFormattingChanged: (formatting) =>
                            editProvider.updateBlockData(
                          widget.blockId,
                          'titleFormatting',
                          formatting.toJson(),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Editable subtitle with formatting toolbar
                      InlineEditableTextV2(
                        text: subtitle,
                        baseStyle: subtitleStyle,
                        textAlign: TextAlign.center,
                        isEditMode: true,
                        placeholder: 'Subtítulo descriptivo',
                        formatting: subtitleFormatting,
                        fieldKey: '${widget.blockId}_subtitle',
                        onTextChanged: (value) => editProvider.updateBlockData(
                            widget.blockId, 'subtitle', value),
                        onFormattingChanged: (formatting) =>
                            editProvider.updateBlockData(
                          widget.blockId,
                          'subtitleFormatting',
                          formatting.toJson(),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Editable button with click handler
                      _EditableButton(
                        text: heroAction.label,
                        link: heroAction.href,
                        backgroundColor: widget.accentColor,
                        actionVariant: heroAction.variant,
                        onActionChanged: (action) =>
                            editProvider.updateBlockDataMultiple(
                          widget.blockId,
                          {
                            'ctaText': action.label,
                            'buttonText': action.label,
                            'ctaLink': action.href,
                            'buttonLink': action.href,
                            'actions': WebsiteActionValue.mergePrimary(
                              widget.data['actions'],
                              action,
                            ),
                          },
                        ),
                        onNavigate: heroAction.href.isNotEmpty
                            ? () {
                                widget.onNavigate?.call(heroAction.href);
                              }
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEditableAbout(BuildContext context) {
    final editProvider = context.read<WebsiteEditModeProvider>();
    final theme = Theme.of(context);

    final title = (widget.data['title'] ?? '').toString();
    final description =
        (widget.data['content'] ?? widget.data['description'] ?? '').toString();
    final imageUrl =
        (widget.data['imageUrl'] ?? widget.data['image'])?.toString();

    // Get formatting data if saved
    final titleFormatting = TextFormatting.fromJson(
        widget.data['titleFormatting'] as Map<String, dynamic>?);
    final descriptionFormatting = TextFormatting.fromJson(
      (widget.data['contentFormatting'] as Map<String, dynamic>?) ??
          (widget.data['descriptionFormatting'] as Map<String, dynamic>?),
    );

    final headingStyle =
        (theme.textTheme.headlineMedium ?? const TextStyle()).copyWith(
      fontFamily:
          widget.headingFont?.isNotEmpty == true ? widget.headingFont : null,
      fontWeight: FontWeight.bold,
    );

    final bodyStyle = (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      fontFamily: widget.bodyFont?.isNotEmpty == true ? widget.bodyFont : null,
      height: 1.6,
    );

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Image side
        Expanded(
          child: InlineEditableImage(
            imageUrl: imageUrl,
            height: 400,
            fit: BoxFit.cover,
            borderRadius: BorderRadius.circular(16),
            isEditMode: true,
            onChanged: (url) => editProvider.updateBlockDataMultiple(
              widget.blockId,
              {'imageUrl': url, 'image': url},
            ),
          ),
        ),

        const SizedBox(width: 48),

        // Text side
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              InlineEditableTextV2(
                text: title,
                baseStyle: headingStyle,
                isEditMode: true,
                placeholder: 'Sobre Nosotros',
                formatting: titleFormatting,
                fieldKey: '${widget.blockId}_about_title',
                onTextChanged: (value) => editProvider.updateBlockData(
                    widget.blockId, 'title', value),
                onFormattingChanged: (formatting) =>
                    editProvider.updateBlockData(
                  widget.blockId,
                  'titleFormatting',
                  formatting.toJson(),
                ),
              ),
              const SizedBox(height: 24),
              InlineEditableTextV2(
                text: description,
                baseStyle: bodyStyle,
                maxLines: 10,
                isEditMode: true,
                placeholder: 'Descripción de tu empresa...',
                formatting: descriptionFormatting,
                fieldKey: '${widget.blockId}_about_description',
                onTextChanged: (value) => editProvider.updateBlockDataMultiple(
                  widget.blockId,
                  {'content': value, 'description': value},
                ),
                onFormattingChanged: (formatting) =>
                    editProvider.updateBlockDataMultiple(
                  widget.blockId,
                  {
                    'contentFormatting': formatting.toJson(),
                    'descriptionFormatting': formatting.toJson(),
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return ConstraintLayoutBuilder(
      builder: (context, constraints) {
        final hasFixedHeight = constraints.maxHeight.isFinite;

        return Container(
          height: hasFixedHeight ? constraints.maxHeight : null,
          padding: hasFixedHeight
              ? const EdgeInsets.symmetric(horizontal: 24)
              : const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: content,
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditableCta(BuildContext context) {
    final editProvider = context.read<WebsiteEditModeProvider>();
    final theme = Theme.of(context);

    final title = (widget.data['title'] ?? '').toString();
    final subtitle =
        (widget.data['subtitle'] ?? widget.data['description'] ?? '')
            .toString();
    final buttonText = (widget.data['buttonText'] ?? 'Contactar').toString();
    final buttonLink = (widget.data['buttonLink'] ?? '').toString();

    final primaryAction = _resolvePrimaryNavigateAction(
      widget.data,
      fallbackLabel: buttonText,
      fallbackTo: buttonLink,
    );

    final backgroundImage = widget.data['backgroundImage']?.toString();
    final hasBackground =
        backgroundImage != null && backgroundImage.trim().isNotEmpty;

    final overlayColor =
        _parseColor(widget.data['overlayColor']?.toString()) ?? Colors.black;
    final overlayOpacity = ((widget.data['overlayOpacity'] ?? 0.5) as num)
        .toDouble()
        .clamp(0.0, 1.0);
    final blockHeight =
        (widget.data['blockHeight'] as num?)?.toDouble() ?? 420.0;

    final titleFormatting = TextFormatting.fromJson(
      widget.data['titleFormatting'] as Map<String, dynamic>?,
    );
    final subtitleFormatting = TextFormatting.fromJson(
      (widget.data['subtitleFormatting'] as Map<String, dynamic>?) ??
          (widget.data['descriptionFormatting'] as Map<String, dynamic>?),
    );

    final headingStyle =
        (theme.textTheme.headlineMedium ?? const TextStyle()).copyWith(
      fontFamily:
          widget.headingFont?.isNotEmpty == true ? widget.headingFont : null,
      fontWeight: FontWeight.bold,
      color: Colors.white,
    );

    final bodyStyle = (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      fontFamily: widget.bodyFont?.isNotEmpty == true ? widget.bodyFont : null,
      color: Colors.white70,
    );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InlineEditableTextV2(
          text: title,
          baseStyle: headingStyle,
          textAlign: TextAlign.center,
          isEditMode: true,
          placeholder: 'Llamado a la Acción',
          formatting: titleFormatting,
          fieldKey: '${widget.blockId}_cta_title',
          onTextChanged: (value) =>
              editProvider.updateBlockData(widget.blockId, 'title', value),
          onFormattingChanged: (formatting) => editProvider.updateBlockData(
            widget.blockId,
            'titleFormatting',
            formatting.toJson(),
          ),
        ),
        const SizedBox(height: 16),
        InlineEditableTextV2(
          text: subtitle,
          baseStyle: bodyStyle,
          textAlign: TextAlign.center,
          isEditMode: true,
          placeholder: 'Descripción del llamado a la acción',
          formatting: subtitleFormatting,
          fieldKey: '${widget.blockId}_cta_subtitle',
          onTextChanged: (value) {
            editProvider.updateBlockData(widget.blockId, 'subtitle', value);
            editProvider.updateBlockData(widget.blockId, 'description', value);
          },
          onFormattingChanged: (formatting) => editProvider.updateBlockData(
            widget.blockId,
            'subtitleFormatting',
            formatting.toJson(),
          ),
        ),
        const SizedBox(height: 32),
        _EditableButton(
          text: primaryAction?.label ??
              (buttonText.isEmpty ? 'Contactar' : buttonText),
          link: primaryAction?.href ?? buttonLink,
          backgroundColor: Colors.white,
          foregroundColor: widget.primaryColor,
          actionVariant: primaryAction?.variant ?? WebsiteActionVariant.outline,
          onActionChanged: (action) => editProvider.updateBlockDataMultiple(
            widget.blockId,
            {
              'buttonText': action.label,
              'ctaText': action.label,
              'buttonLink': action.href,
              'ctaLink': action.href,
              'actions': WebsiteActionValue.mergePrimary(
                widget.data['actions'],
                action,
              ),
            },
          ),
          onNavigate: (primaryAction?.href ?? buttonLink).isNotEmpty
              ? () {
                  widget.onNavigate?.call(primaryAction?.href ?? buttonLink);
                }
              : null,
        ),
      ],
    );

    return SizedBox(
      height: blockHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasBackground)
            InlineEditableImage(
              imageUrl: backgroundImage,
              isEditMode: true,
              fit: BoxFit.cover,
              alignment: Alignment(
                (((widget.data['focalPointX'] as num?)?.toDouble() ?? 0.5) *
                        2) -
                    1,
                (((widget.data['focalPointY'] as num?)?.toDouble() ?? 0.5) *
                        2) -
                    1,
              ),
              onChanged: (url) => editProvider.updateBlockData(
                widget.blockId,
                'backgroundImage',
                url,
              ),
            )
          else
            Container(color: widget.primaryColor),
          if (hasBackground && overlayOpacity > 0)
            Container(
              color: overlayColor.withValues(alpha: overlayOpacity),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: content,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableFeatures(BuildContext context) {
    final editProvider = context.read<WebsiteEditModeProvider>();
    final theme = Theme.of(context);

    final title = (widget.data['title'] ?? 'Características').toString();
    final subtitle = (widget.data['subtitle'] ?? '').toString();
    final rawFeatures = widget.data['features'] ?? widget.data['items'];

    List<Map<String, dynamic>> features = [];
    if (rawFeatures is List) {
      features = rawFeatures
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (features.isEmpty) {
      features = [
        {
          'icon': 'check_circle',
          'title': 'Característica 1',
          'description': 'Descripción de la característica',
        },
        {
          'icon': 'check_circle',
          'title': 'Característica 2',
          'description': 'Descripción de la característica',
        },
        {
          'icon': 'check_circle',
          'title': 'Característica 3',
          'description': 'Descripción de la característica',
        },
      ];
    }

    void updateFeatures(List<Map<String, dynamic>> updated) {
      editProvider.updateBlockData(widget.blockId, 'features', updated);
      editProvider.updateBlockData(widget.blockId, 'items', updated);
    }

    final headingStyle =
        (theme.textTheme.displaySmall ?? const TextStyle()).copyWith(
      fontFamily: widget.headingFont,
    );

    final bodyStyle = (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      fontFamily: widget.bodyFont,
      color: theme.colorScheme.onSurfaceVariant,
    );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InlineEditableTextV2(
          text: title,
          baseStyle: headingStyle,
          textAlign: TextAlign.center,
          isEditMode: true,
          placeholder: 'Título de características',
          fieldKey: '${widget.blockId}_features_title',
          onTextChanged: (value) =>
              editProvider.updateBlockData(widget.blockId, 'title', value),
        ),
        const SizedBox(height: 12),
        InlineEditableTextV2(
          text: subtitle,
          baseStyle: bodyStyle,
          textAlign: TextAlign.center,
          isEditMode: true,
          placeholder: 'Subtítulo opcional',
          fieldKey: '${widget.blockId}_features_subtitle',
          onTextChanged: (value) =>
              editProvider.updateBlockData(widget.blockId, 'subtitle', value),
        ),
        const SizedBox(height: 48),
        Wrap(
          spacing: 32,
          runSpacing: 32,
          alignment: WrapAlignment.center,
          children: features.asMap().entries.map((entry) {
            final index = entry.key;
            final feature = entry.value;
            return _buildEditableFeatureCard(
              context,
              feature,
              index,
              features,
              editProvider,
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: () {
            final newFeatures = List<Map<String, dynamic>>.from(features);
            newFeatures.add({
              'icon': 'check_circle',
              'title': 'Nueva Característica',
              'description': 'Descripción de la característica',
            });
            updateFeatures(newFeatures);
          },
          icon: const Icon(Icons.add),
          label: const Text('Agregar característica'),
        ),
      ],
    );

    return ConstraintLayoutBuilder(
      builder: (context, constraints) {
        final hasFixedHeight = constraints.maxHeight.isFinite;
        return Container(
          width: double.infinity,
          height: hasFixedHeight ? constraints.maxHeight : null,
          padding: hasFixedHeight
              ? const EdgeInsets.symmetric(horizontal: 24)
              : const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: content,
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditableFeatureCard(
    BuildContext context,
    Map<String, dynamic> feature,
    int index,
    List<Map<String, dynamic>> allFeatures,
    WebsiteEditModeProvider editProvider,
  ) {
    final theme = Theme.of(context);
    final featureTitle = (feature['title'] ?? '').toString();
    final featureDesc = (feature['description'] ?? '').toString();

    return Container(
      width: 300,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: widget.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.check_circle,
                    color: widget.primaryColor, size: 32),
              ),
              const SizedBox(height: 16),
              InlineEditableTextV2(
                text: featureTitle,
                baseStyle: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
                isEditMode: true,
                placeholder: 'Título',
                fieldKey: '${widget.blockId}_feature_${index}_title',
                onTextChanged: (value) {
                  final updated = List<Map<String, dynamic>>.from(allFeatures);
                  updated[index] = Map<String, dynamic>.from(updated[index]);
                  updated[index]['title'] = value;
                  editProvider.updateBlockData(
                      widget.blockId, 'features', updated);
                  editProvider.updateBlockData(
                      widget.blockId, 'items', updated);
                },
              ),
              const SizedBox(height: 8),
              InlineEditableTextV2(
                text: featureDesc,
                baseStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
                isEditMode: true,
                placeholder: 'Descripción',
                fieldKey: '${widget.blockId}_feature_${index}_desc',
                onTextChanged: (value) {
                  final updated = List<Map<String, dynamic>>.from(allFeatures);
                  updated[index] = Map<String, dynamic>.from(updated[index]);
                  updated[index]['description'] = value;
                  editProvider.updateBlockData(
                      widget.blockId, 'features', updated);
                  editProvider.updateBlockData(
                      widget.blockId, 'items', updated);
                },
              ),
            ],
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () {
                final updated = List<Map<String, dynamic>>.from(allFeatures);
                updated.removeAt(index);
                editProvider.updateBlockData(
                    widget.blockId, 'features', updated);
                editProvider.updateBlockData(widget.blockId, 'items', updated);
              },
              tooltip: 'Eliminar',
            ),
          ),
        ],
      ),
    );
  }

  /// Editable FAQ block
  Widget _buildEditableFaq(BuildContext context) {
    final editProvider = context.read<WebsiteEditModeProvider>();
    final theme = Theme.of(context);

    final title = (widget.data['title'] ?? 'Preguntas Frecuentes').toString();
    final subtitle = (widget.data['subtitle'] ?? '').toString();
    final rawItems = widget.data['items'];

    List<Map<String, dynamic>> items = [];
    if (rawItems is List) {
      items = rawItems
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (items.isEmpty) {
      items = [
        {'question': '¿Pregunta de ejemplo?', 'answer': 'Respuesta de ejemplo'},
      ];
    }

    final headingStyle =
        (theme.textTheme.displaySmall ?? const TextStyle()).copyWith(
      fontFamily: widget.headingFont,
    );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InlineEditableTextV2(
          text: title,
          baseStyle: headingStyle,
          textAlign: TextAlign.center,
          isEditMode: true,
          placeholder: 'Título de FAQ',
          fieldKey: '${widget.blockId}_faq_title',
          onTextChanged: (value) =>
              editProvider.updateBlockData(widget.blockId, 'title', value),
        ),
        const SizedBox(height: 12),
        InlineEditableTextV2(
          text: subtitle,
          baseStyle: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
          isEditMode: true,
          placeholder: 'Subtítulo opcional',
          fieldKey: '${widget.blockId}_faq_subtitle',
          onTextChanged: (value) =>
              editProvider.updateBlockData(widget.blockId, 'subtitle', value),
        ),
        const SizedBox(height: 32),
        ...items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          return _buildEditableFaqItem(
              context, item, index, items, editProvider);
        }),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: () {
            final newItems = List<Map<String, dynamic>>.from(items);
            newItems.add({
              'question': 'Nueva pregunta',
              'answer': 'Respuesta a la pregunta',
            });
            editProvider.updateBlockData(widget.blockId, 'items', newItems);
          },
          icon: const Icon(Icons.add),
          label: const Text('Agregar pregunta'),
        ),
      ],
    );

    return ConstraintLayoutBuilder(
      builder: (context, constraints) {
        final hasFixedHeight = constraints.maxHeight.isFinite;
        return Container(
          width: double.infinity,
          height: hasFixedHeight ? constraints.maxHeight : null,
          padding: hasFixedHeight
              ? const EdgeInsets.symmetric(horizontal: 24)
              : const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: content,
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditableFaqItem(
    BuildContext context,
    Map<String, dynamic> item,
    int index,
    List<Map<String, dynamic>> allItems,
    WebsiteEditModeProvider editProvider,
  ) {
    final theme = Theme.of(context);
    final question = (item['question'] ?? '').toString();
    final answer = (item['answer'] ?? '').toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: widget.primaryColor,
          collapsedIconColor: widget.primaryColor,
          initiallyExpanded: true,
          title: Row(
            children: [
              Expanded(
                child: InlineEditableTextV2(
                  text: question,
                  baseStyle: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                  isEditMode: true,
                  placeholder: 'Pregunta',
                  fieldKey: '${widget.blockId}_faq_${index}_question',
                  onTextChanged: (value) {
                    final updated = List<Map<String, dynamic>>.from(allItems);
                    updated[index] = Map<String, dynamic>.from(updated[index]);
                    updated[index]['question'] = value;
                    editProvider.updateBlockData(
                        widget.blockId, 'items', updated);
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  final updated = List<Map<String, dynamic>>.from(allItems);
                  updated.removeAt(index);
                  editProvider.updateBlockData(
                      widget.blockId, 'items', updated);
                },
                tooltip: 'Eliminar',
              ),
            ],
          ),
          childrenPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            InlineEditableTextV2(
              text: answer,
              baseStyle: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              isEditMode: true,
              placeholder: 'Respuesta',
              fieldKey: '${widget.blockId}_faq_${index}_answer',
              onTextChanged: (value) {
                final updated = List<Map<String, dynamic>>.from(allItems);
                updated[index] = Map<String, dynamic>.from(updated[index]);
                updated[index]['answer'] = value;
                editProvider.updateBlockData(widget.blockId, 'items', updated);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Editable Contact block
  Widget _buildEditableContact(BuildContext context) {
    final editProvider = context.read<WebsiteEditModeProvider>();
    final theme = Theme.of(context);

    final title = (widget.data['title'] ?? 'Contáctanos').toString();
    final subtitle = (widget.data['subtitle'] ?? '').toString();
    final buttonText = (widget.data['buttonText'] ?? 'Enviar').toString();

    final headingStyle =
        (theme.textTheme.displaySmall ?? const TextStyle()).copyWith(
      fontFamily: widget.headingFont,
    );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InlineEditableTextV2(
          text: title,
          baseStyle: headingStyle,
          textAlign: TextAlign.center,
          isEditMode: true,
          placeholder: 'Título de contacto',
          fieldKey: '${widget.blockId}_contact_title',
          onTextChanged: (value) =>
              editProvider.updateBlockData(widget.blockId, 'title', value),
        ),
        const SizedBox(height: 12),
        InlineEditableTextV2(
          text: subtitle,
          baseStyle: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
          isEditMode: true,
          placeholder: 'Subtítulo o descripción',
          fieldKey: '${widget.blockId}_contact_subtitle',
          onTextChanged: (value) =>
              editProvider.updateBlockData(widget.blockId, 'subtitle', value),
        ),
        const SizedBox(height: 32),
        // Preview form (non-functional in editor)
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                enabled: false,
                decoration: InputDecoration(
                  labelText: 'Nombre',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                enabled: false,
                decoration: InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                enabled: false,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'Mensaje',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: _EditableButton(
                  text: buttonText,
                  link: '',
                  backgroundColor: widget.primaryColor,
                  foregroundColor: Colors.white,
                  onTextChanged: (value) => editProvider.updateBlockData(
                      widget.blockId, 'buttonText', value),
                  onLinkChanged: (_) {},
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return ConstraintLayoutBuilder(
      builder: (context, constraints) {
        final hasFixedHeight = constraints.maxHeight.isFinite;

        return Container(
          height: hasFixedHeight ? constraints.maxHeight : null,
          padding: hasFixedHeight
              ? const EdgeInsets.symmetric(horizontal: 24)
              : const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
          color: Colors.grey.shade50,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: content,
            ),
          ),
        );
      },
    );
  }

  /// Editable Services block
  Widget _buildEditableServices(BuildContext context) {
    final editProvider = context.read<WebsiteEditModeProvider>();
    final theme = Theme.of(context);

    final title = (widget.data['title'] ?? 'Nuestros Servicios').toString();
    final subtitle = (widget.data['subtitle'] ?? '').toString();
    final rawServices = widget.data['services'] ?? widget.data['items'];

    List<Map<String, dynamic>> services = [];
    if (rawServices is List) {
      services = rawServices
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (services.isEmpty) {
      services = [
        {
          'icon': 'build',
          'title': 'Servicio 1',
          'description': 'Descripción del servicio'
        },
        {
          'icon': 'build',
          'title': 'Servicio 2',
          'description': 'Descripción del servicio'
        },
        {
          'icon': 'build',
          'title': 'Servicio 3',
          'description': 'Descripción del servicio'
        },
      ];
    }

    final headingStyle =
        (theme.textTheme.displaySmall ?? const TextStyle()).copyWith(
      fontFamily: widget.headingFont,
    );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InlineEditableTextV2(
          text: title,
          baseStyle: headingStyle,
          textAlign: TextAlign.center,
          isEditMode: true,
          placeholder: 'Título de servicios',
          fieldKey: '${widget.blockId}_services_title',
          onTextChanged: (value) =>
              editProvider.updateBlockData(widget.blockId, 'title', value),
        ),
        const SizedBox(height: 12),
        InlineEditableTextV2(
          text: subtitle,
          baseStyle: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
          isEditMode: true,
          placeholder: 'Subtítulo opcional',
          fieldKey: '${widget.blockId}_services_subtitle',
          onTextChanged: (value) =>
              editProvider.updateBlockData(widget.blockId, 'subtitle', value),
        ),
        const SizedBox(height: 48),
        Wrap(
          spacing: 24,
          runSpacing: 24,
          alignment: WrapAlignment.center,
          children: services.asMap().entries.map((entry) {
            final index = entry.key;
            final service = entry.value;
            return _buildEditableServiceCard(
                context, service, index, services, editProvider);
          }).toList(),
        ),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: () {
            final newServices = List<Map<String, dynamic>>.from(services);
            newServices.add({
              'icon': 'build',
              'title': 'Nuevo Servicio',
              'description': 'Descripción del servicio',
            });
            editProvider.updateBlockData(
                widget.blockId, 'services', newServices);
          },
          icon: const Icon(Icons.add),
          label: const Text('Agregar servicio'),
        ),
      ],
    );

    // Use LayoutBuilder to center vertically when height is constrained
    return ConstraintLayoutBuilder(
      builder: (context, constraints) {
        final hasFixedHeight = constraints.maxHeight.isFinite;

        return Container(
          width: double.infinity,
          height: hasFixedHeight ? constraints.maxHeight : null,
          padding: hasFixedHeight
              ? const EdgeInsets.symmetric(horizontal: 24)
              : const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: content,
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditableServiceCard(
    BuildContext context,
    Map<String, dynamic> service,
    int index,
    List<Map<String, dynamic>> allServices,
    WebsiteEditModeProvider editProvider,
  ) {
    final theme = Theme.of(context);
    final serviceTitle = (service['title'] ?? '').toString();
    final serviceDesc = (service['description'] ?? '').toString();

    return Container(
      width: 320,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: widget.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.build, color: widget.primaryColor, size: 36),
              ),
              const SizedBox(height: 20),
              InlineEditableTextV2(
                text: serviceTitle,
                baseStyle: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
                isEditMode: true,
                placeholder: 'Nombre del servicio',
                fieldKey: '${widget.blockId}_service_${index}_title',
                onTextChanged: (value) {
                  final updated = List<Map<String, dynamic>>.from(allServices);
                  updated[index] = Map<String, dynamic>.from(updated[index]);
                  updated[index]['title'] = value;
                  editProvider.updateBlockData(
                      widget.blockId, 'services', updated);
                },
              ),
              const SizedBox(height: 12),
              InlineEditableTextV2(
                text: serviceDesc,
                baseStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
                isEditMode: true,
                placeholder: 'Descripción',
                fieldKey: '${widget.blockId}_service_${index}_desc',
                onTextChanged: (value) {
                  final updated = List<Map<String, dynamic>>.from(allServices);
                  updated[index] = Map<String, dynamic>.from(updated[index]);
                  updated[index]['description'] = value;
                  editProvider.updateBlockData(
                      widget.blockId, 'services', updated);
                },
              ),
            ],
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () {
                final updated = List<Map<String, dynamic>>.from(allServices);
                updated.removeAt(index);
                editProvider.updateBlockData(
                    widget.blockId, 'services', updated);
              },
              tooltip: 'Eliminar',
            ),
          ),
        ],
      ),
    );
  }

  /// Editable Pricing block
  Widget _buildEditablePricing(BuildContext context) {
    final editProvider = context.read<WebsiteEditModeProvider>();
    final theme = Theme.of(context);

    final title = (widget.data['title'] ?? 'Precios').toString();
    final subtitle = (widget.data['subtitle'] ?? '').toString();
    final rawPlans = widget.data['plans'] ?? widget.data['items'];

    List<Map<String, dynamic>> plans = [];
    if (rawPlans is List) {
      plans = rawPlans
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (plans.isEmpty) {
      plans = [
        {
          'name': 'Básico',
          'price': '\$9.990',
          'description': 'Ideal para empezar',
          'features': ['Feature 1', 'Feature 2'],
          'ctaText': 'Reservar',
          'ctaLink': '/productos',
        },
        {
          'name': 'Pro',
          'price': '\$19.990',
          'description': 'El más popular',
          'features': ['Feature 1', 'Feature 2', 'Feature 3'],
          'ctaText': 'Reservar',
          'ctaLink': '/productos',
          'highlighted': true
        },
      ];
    }

    final headingStyle =
        (theme.textTheme.displaySmall ?? const TextStyle()).copyWith(
      fontFamily: widget.headingFont,
    );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InlineEditableTextV2(
          text: title,
          baseStyle: headingStyle,
          textAlign: TextAlign.center,
          isEditMode: true,
          placeholder: 'Título de precios',
          fieldKey: '${widget.blockId}_pricing_title',
          onTextChanged: (value) =>
              editProvider.updateBlockData(widget.blockId, 'title', value),
        ),
        const SizedBox(height: 12),
        InlineEditableTextV2(
          text: subtitle,
          baseStyle: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
          isEditMode: true,
          placeholder: 'Subtítulo opcional',
          fieldKey: '${widget.blockId}_pricing_subtitle',
          onTextChanged: (value) =>
              editProvider.updateBlockData(widget.blockId, 'subtitle', value),
        ),
        const SizedBox(height: 48),
        Wrap(
          spacing: 24,
          runSpacing: 24,
          alignment: WrapAlignment.center,
          children: plans.asMap().entries.map((entry) {
            final index = entry.key;
            final plan = entry.value;
            return _buildEditablePricingCard(
                context, plan, index, plans, editProvider);
          }).toList(),
        ),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: () {
            final newPlans = List<Map<String, dynamic>>.from(plans);
            newPlans.add({
              'name': 'Nuevo Plan',
              'price': '\$0',
              'description': 'Descripción del plan',
              'features': ['Característica 1'],
              'ctaText': 'Reservar',
              'ctaLink': '/productos',
            });
            editProvider.updateBlockData(widget.blockId, 'plans', newPlans);
          },
          icon: const Icon(Icons.add),
          label: const Text('Agregar plan'),
        ),
      ],
    );

    return ConstraintLayoutBuilder(
      builder: (context, constraints) {
        final hasFixedHeight = constraints.maxHeight.isFinite;

        return Container(
          height: hasFixedHeight ? constraints.maxHeight : null,
          padding: hasFixedHeight
              ? const EdgeInsets.symmetric(horizontal: 24)
              : const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: content,
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditablePricingCard(
    BuildContext context,
    Map<String, dynamic> plan,
    int index,
    List<Map<String, dynamic>> allPlans,
    WebsiteEditModeProvider editProvider,
  ) {
    final theme = Theme.of(context);
    final name = (plan['name'] ?? '').toString();
    final price = (plan['price'] ?? '').toString();
    final description = (plan['description'] ?? '').toString();
    final isHighlighted = plan['highlighted'] == true;
    final action = WebsiteActionValue.resolvePrimary(
          plan,
          labelKeys: const ['ctaText', 'buttonText'],
          hrefKeys: const ['ctaLink', 'buttonLink'],
          defaultLabel: 'Reservar',
          defaultHref: '/productos',
        ) ??
        const WebsiteActionValue(label: 'Reservar', href: '/productos');

    return Container(
      width: 300,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isHighlighted ? widget.primaryColor : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHighlighted ? widget.primaryColor : Colors.grey.shade200,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isHighlighted ? 0.1 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            children: [
              InlineEditableTextV2(
                text: name,
                baseStyle: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isHighlighted ? Colors.white : null,
                ),
                textAlign: TextAlign.center,
                isEditMode: true,
                placeholder: 'Nombre del plan',
                fieldKey: '${widget.blockId}_plan_${index}_name',
                onTextChanged: (value) {
                  final updated = List<Map<String, dynamic>>.from(allPlans);
                  updated[index] = Map<String, dynamic>.from(updated[index]);
                  updated[index]['name'] = value;
                  editProvider.updateBlockData(
                      widget.blockId, 'plans', updated);
                },
              ),
              const SizedBox(height: 12),
              InlineEditableTextV2(
                text: price,
                baseStyle: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isHighlighted ? Colors.white : widget.primaryColor,
                ),
                textAlign: TextAlign.center,
                isEditMode: true,
                placeholder: '\$0',
                fieldKey: '${widget.blockId}_plan_${index}_price',
                onTextChanged: (value) {
                  final updated = List<Map<String, dynamic>>.from(allPlans);
                  updated[index] = Map<String, dynamic>.from(updated[index]);
                  updated[index]['price'] = value;
                  editProvider.updateBlockData(
                      widget.blockId, 'plans', updated);
                },
              ),
              const SizedBox(height: 8),
              InlineEditableTextV2(
                text: description,
                baseStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: isHighlighted
                      ? Colors.white70
                      : theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
                isEditMode: true,
                placeholder: 'Descripción',
                fieldKey: '${widget.blockId}_plan_${index}_desc',
                onTextChanged: (value) {
                  final updated = List<Map<String, dynamic>>.from(allPlans);
                  updated[index] = Map<String, dynamic>.from(updated[index]);
                  updated[index]['description'] = value;
                  editProvider.updateBlockData(
                      widget.blockId, 'plans', updated);
                },
              ),
              const SizedBox(height: 16),
              _EditableButton(
                text: action.label,
                link: action.href,
                backgroundColor:
                    isHighlighted ? widget.accentColor : widget.primaryColor,
                foregroundColor: Colors.white,
                actionVariant: action.variant,
                onActionChanged: (nextAction) {
                  final updated = List<Map<String, dynamic>>.from(allPlans);
                  updated[index] = {
                    ...Map<String, dynamic>.from(updated[index]),
                    'ctaText': nextAction.label,
                    'buttonText': nextAction.label,
                    'ctaLink': nextAction.href,
                    'buttonLink': nextAction.href,
                    'actionVariant': nextAction.variant.storageValue,
                    'actions': WebsiteActionValue.mergePrimary(
                      plan['actions'],
                      nextAction,
                    ),
                  };
                  editProvider.updateBlockData(
                    widget.blockId,
                    'plans',
                    updated,
                  );
                },
                onNavigate: action.href.isEmpty
                    ? null
                    : () => widget.onNavigate?.call(action.href),
              ),
              const SizedBox(height: 12),
              // Toggle highlight
              TextButton(
                onPressed: () {
                  final updated = List<Map<String, dynamic>>.from(allPlans);
                  updated[index] = Map<String, dynamic>.from(updated[index]);
                  updated[index]['highlighted'] = !isHighlighted;
                  editProvider.updateBlockData(
                      widget.blockId, 'plans', updated);
                },
                child: Text(
                  isHighlighted ? 'Quitar destacado' : 'Destacar plan',
                  style: TextStyle(
                    color: isHighlighted ? Colors.white70 : widget.primaryColor,
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              icon: Icon(Icons.close,
                  size: 18, color: isHighlighted ? Colors.white : null),
              onPressed: () {
                final updated = List<Map<String, dynamic>>.from(allPlans);
                updated.removeAt(index);
                editProvider.updateBlockData(widget.blockId, 'plans', updated);
              },
              tooltip: 'Eliminar',
            ),
          ),
        ],
      ),
    );
  }

  /// Editable Testimonials block
  Widget _buildEditableTestimonials(BuildContext context) {
    final editProvider = context.read<WebsiteEditModeProvider>();
    final theme = Theme.of(context);

    final title =
        (widget.data['title'] ?? 'Lo que dicen nuestros clientes').toString();
    final subtitle = (widget.data['subtitle'] ?? '').toString();
    final rawItems = widget.data['testimonials'] ?? widget.data['items'];

    List<Map<String, dynamic>> items = [];
    if (rawItems is List) {
      items = rawItems
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (items.isEmpty) {
      items = [
        {
          'name': 'Cliente 1',
          'role': 'Cargo',
          'quote': 'Excelente servicio y atención al cliente.'
        },
      ];
    }

    final headingStyle =
        (theme.textTheme.displaySmall ?? const TextStyle()).copyWith(
      fontFamily: widget.headingFont,
    );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InlineEditableTextV2(
          text: title,
          baseStyle: headingStyle,
          textAlign: TextAlign.center,
          isEditMode: true,
          placeholder: 'Título de testimonios',
          fieldKey: '${widget.blockId}_testimonials_title',
          onTextChanged: (value) =>
              editProvider.updateBlockData(widget.blockId, 'title', value),
        ),
        const SizedBox(height: 12),
        InlineEditableTextV2(
          text: subtitle,
          baseStyle: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
          isEditMode: true,
          placeholder: 'Subtítulo opcional',
          fieldKey: '${widget.blockId}_testimonials_subtitle',
          onTextChanged: (value) =>
              editProvider.updateBlockData(widget.blockId, 'subtitle', value),
        ),
        const SizedBox(height: 48),
        Wrap(
          spacing: 24,
          runSpacing: 24,
          alignment: WrapAlignment.center,
          children: items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            return _buildEditableTestimonialCard(
                context, item, index, items, editProvider);
          }).toList(),
        ),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: () {
            final newItems = List<Map<String, dynamic>>.from(items);
            newItems.add({
              'name': 'Nuevo Cliente',
              'role': 'Cargo',
              'quote': 'Su testimonio aquí...',
            });
            editProvider.updateBlockData(
                widget.blockId, 'testimonials', newItems);
          },
          icon: const Icon(Icons.add),
          label: const Text('Agregar testimonio'),
        ),
      ],
    );

    return ConstraintLayoutBuilder(
      builder: (context, constraints) {
        final hasFixedHeight = constraints.maxHeight.isFinite;

        return Container(
          height: hasFixedHeight ? constraints.maxHeight : null,
          padding: hasFixedHeight
              ? const EdgeInsets.symmetric(horizontal: 24)
              : const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
          color: Colors.grey.shade50,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: content,
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditableTestimonialCard(
    BuildContext context,
    Map<String, dynamic> item,
    int index,
    List<Map<String, dynamic>> allItems,
    WebsiteEditModeProvider editProvider,
  ) {
    final theme = Theme.of(context);
    final name = (item['name'] ?? '').toString();
    final role = (item['role'] ?? '').toString();
    final quote = (item['quote'] ?? '').toString();

    return Container(
      width: 350,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            children: [
              Icon(Icons.format_quote, color: widget.primaryColor, size: 36),
              const SizedBox(height: 16),
              InlineEditableTextV2(
                text: quote,
                baseStyle: theme.textTheme.bodyLarge?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
                isEditMode: true,
                placeholder: 'Testimonio del cliente',
                fieldKey: '${widget.blockId}_testimonial_${index}_quote',
                onTextChanged: (value) {
                  final updated = List<Map<String, dynamic>>.from(allItems);
                  updated[index] = Map<String, dynamic>.from(updated[index]);
                  updated[index]['quote'] = value;
                  editProvider.updateBlockData(
                      widget.blockId, 'testimonials', updated);
                },
              ),
              const SizedBox(height: 16),
              InlineEditableTextV2(
                text: name,
                baseStyle: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
                isEditMode: true,
                placeholder: 'Nombre',
                fieldKey: '${widget.blockId}_testimonial_${index}_name',
                onTextChanged: (value) {
                  final updated = List<Map<String, dynamic>>.from(allItems);
                  updated[index] = Map<String, dynamic>.from(updated[index]);
                  updated[index]['name'] = value;
                  editProvider.updateBlockData(
                      widget.blockId, 'testimonials', updated);
                },
              ),
              const SizedBox(height: 4),
              InlineEditableTextV2(
                text: role,
                baseStyle: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
                isEditMode: true,
                placeholder: 'Cargo o título',
                fieldKey: '${widget.blockId}_testimonial_${index}_role',
                onTextChanged: (value) {
                  final updated = List<Map<String, dynamic>>.from(allItems);
                  updated[index] = Map<String, dynamic>.from(updated[index]);
                  updated[index]['role'] = value;
                  editProvider.updateBlockData(
                      widget.blockId, 'testimonials', updated);
                },
              ),
            ],
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () {
                final updated = List<Map<String, dynamic>>.from(allItems);
                updated.removeAt(index);
                editProvider.updateBlockData(
                    widget.blockId, 'testimonials', updated);
              },
              tooltip: 'Eliminar',
            ),
          ),
        ],
      ),
    );
  }

  /// Editable Stats block
  Widget _buildEditableStats(BuildContext context) {
    final editProvider = context.read<WebsiteEditModeProvider>();
    final theme = Theme.of(context);

    final title = (widget.data['title'] ?? '').toString();
    final rawStats = widget.data['stats'] ?? widget.data['items'];

    List<Map<String, dynamic>> stats = [];
    if (rawStats is List) {
      stats = rawStats
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (stats.isEmpty) {
      stats = [
        {'value': '100+', 'label': 'Clientes Satisfechos'},
        {'value': '500+', 'label': 'Proyectos Completados'},
        {'value': '10+', 'label': 'Años de Experiencia'},
      ];
    }

    final headingStyle =
        (theme.textTheme.displaySmall ?? const TextStyle()).copyWith(
      fontFamily: widget.headingFont,
    );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title.isNotEmpty || true)
          InlineEditableTextV2(
            text: title,
            baseStyle: headingStyle.copyWith(color: Colors.white),
            textAlign: TextAlign.center,
            isEditMode: true,
            placeholder: 'Título opcional',
            fieldKey: '${widget.blockId}_stats_title',
            onTextChanged: (value) =>
                editProvider.updateBlockData(widget.blockId, 'title', value),
          ),
        const SizedBox(height: 48),
        Wrap(
          spacing: 48,
          runSpacing: 32,
          alignment: WrapAlignment.center,
          children: stats.asMap().entries.map((entry) {
            final index = entry.key;
            final stat = entry.value;
            return _buildEditableStatItem(
                context, stat, index, stats, editProvider);
          }).toList(),
        ),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: () {
            final newStats = List<Map<String, dynamic>>.from(stats);
            newStats.add({
              'value': '0+',
              'label': 'Nueva Estadística',
            });
            editProvider.updateBlockData(widget.blockId, 'stats', newStats);
          },
          icon: const Icon(Icons.add, color: Colors.white70),
          label: const Text('Agregar estadística',
              style: TextStyle(color: Colors.white70)),
        ),
      ],
    );

    return ConstraintLayoutBuilder(
      builder: (context, constraints) {
        final hasFixedHeight = constraints.maxHeight.isFinite;

        return Container(
          height: hasFixedHeight ? constraints.maxHeight : null,
          padding: hasFixedHeight
              ? const EdgeInsets.symmetric(horizontal: 24)
              : const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
          color: widget.primaryColor,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: content,
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditableStatItem(
    BuildContext context,
    Map<String, dynamic> stat,
    int index,
    List<Map<String, dynamic>> allStats,
    WebsiteEditModeProvider editProvider,
  ) {
    final theme = Theme.of(context);
    final value = (stat['value'] ?? '').toString();
    final label = (stat['label'] ?? '').toString();

    return SizedBox(
      width: 200,
      child: Stack(
        children: [
          Column(
            children: [
              InlineEditableTextV2(
                text: value,
                baseStyle: theme.textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
                isEditMode: true,
                placeholder: '0+',
                fieldKey: '${widget.blockId}_stat_${index}_value',
                onTextChanged: (val) {
                  final updated = List<Map<String, dynamic>>.from(allStats);
                  updated[index] = Map<String, dynamic>.from(updated[index]);
                  updated[index]['value'] = val;
                  editProvider.updateBlockData(
                      widget.blockId, 'stats', updated);
                },
              ),
              const SizedBox(height: 8),
              InlineEditableTextV2(
                text: label,
                baseStyle:
                    theme.textTheme.bodyLarge?.copyWith(color: Colors.white70),
                textAlign: TextAlign.center,
                isEditMode: true,
                placeholder: 'Etiqueta',
                fieldKey: '${widget.blockId}_stat_${index}_label',
                onTextChanged: (val) {
                  final updated = List<Map<String, dynamic>>.from(allStats);
                  updated[index] = Map<String, dynamic>.from(updated[index]);
                  updated[index]['label'] = val;
                  editProvider.updateBlockData(
                      widget.blockId, 'stats', updated);
                },
              ),
            ],
          ),
          Positioned(
            top: -8,
            right: 0,
            child: IconButton(
              icon: const Icon(Icons.close, size: 18, color: Colors.white70),
              onPressed: () {
                final updated = List<Map<String, dynamic>>.from(allStats);
                updated.removeAt(index);
                editProvider.updateBlockData(widget.blockId, 'stats', updated);
              },
              tooltip: 'Eliminar',
            ),
          ),
        ],
      ),
    );
  }

  /// Editable Team block
  Widget _buildEditableTeam(BuildContext context) {
    final editProvider = context.read<WebsiteEditModeProvider>();
    final theme = Theme.of(context);

    final title = (widget.data['title'] ?? 'Nuestro Equipo').toString();
    final subtitle = (widget.data['subtitle'] ?? '').toString();
    final rawMembers =
        widget.data['team'] ?? widget.data['members'] ?? widget.data['items'];

    List<Map<String, dynamic>> members = [];
    if (rawMembers is List) {
      members = rawMembers
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (members.isEmpty) {
      members = [
        {'name': 'Nombre', 'role': 'Cargo', 'image': null},
      ];
    }

    final headingStyle =
        (theme.textTheme.displaySmall ?? const TextStyle()).copyWith(
      fontFamily: widget.headingFont,
    );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InlineEditableTextV2(
          text: title,
          baseStyle: headingStyle,
          textAlign: TextAlign.center,
          isEditMode: true,
          placeholder: 'Título del equipo',
          fieldKey: '${widget.blockId}_team_title',
          onTextChanged: (value) =>
              editProvider.updateBlockData(widget.blockId, 'title', value),
        ),
        const SizedBox(height: 12),
        InlineEditableTextV2(
          text: subtitle,
          baseStyle: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
          isEditMode: true,
          placeholder: 'Subtítulo opcional',
          fieldKey: '${widget.blockId}_team_subtitle',
          onTextChanged: (value) =>
              editProvider.updateBlockData(widget.blockId, 'subtitle', value),
        ),
        const SizedBox(height: 48),
        Wrap(
          spacing: 32,
          runSpacing: 32,
          alignment: WrapAlignment.center,
          children: members.asMap().entries.map((entry) {
            final index = entry.key;
            final member = entry.value;
            return _buildEditableTeamCard(
                context, member, index, members, editProvider);
          }).toList(),
        ),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: () {
            final newMembers = List<Map<String, dynamic>>.from(members);
            newMembers.add({
              'name': 'Nuevo Miembro',
              'role': 'Cargo',
              'image': null,
            });
            editProvider.updateBlockData(widget.blockId, 'team', newMembers);
          },
          icon: const Icon(Icons.add),
          label: const Text('Agregar miembro'),
        ),
      ],
    );

    return ConstraintLayoutBuilder(
      builder: (context, constraints) {
        final hasFixedHeight = constraints.maxHeight.isFinite;

        return Container(
          height: hasFixedHeight ? constraints.maxHeight : null,
          padding: hasFixedHeight
              ? const EdgeInsets.symmetric(horizontal: 24)
              : const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: content,
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditableGallery(BuildContext context) {
    final theme = Theme.of(context);
    final editProvider = context.read<WebsiteEditModeProvider>();

    final title = (widget.data['title'] ?? 'Galería').toString();
    final layout = (widget.data['layout'] ?? 'grid').toString();

    final imagesRaw = widget.data['images'];
    final images = (imagesRaw is List)
        ? imagesRaw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];

    void updateImages(List<Map<String, dynamic>> next) {
      editProvider.updateBlockData(widget.blockId, 'images', next);
    }

    Widget buildImageTile({
      required int index,
      required Map<String, dynamic> img,
      required double tileWidth,
    }) {
      final imageUrl = (img['imageUrl'] ?? '').toString();
      final caption = (img['caption'] ?? '').toString();

      return SizedBox(
        width: tileWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: InlineEditableImage(
                      imageUrl: imageUrl.isNotEmpty ? imageUrl : null,
                      isEditMode: true,
                      tenantId: widget.tenantId,
                      fit: BoxFit.cover,
                      placeholder: Container(
                        color: theme.dividerColor.withValues(alpha: 0.2),
                        child: Center(
                          child: Icon(
                            Icons.image_outlined,
                            color:
                                theme.iconTheme.color?.withValues(alpha: 0.5),
                            size: 32,
                          ),
                        ),
                      ),
                      onChanged: (url) {
                        final next = images
                            .map((e) => Map<String, dynamic>.from(e))
                            .toList();
                        if (index >= 0 && index < next.length) {
                          next[index]['imageUrl'] = url;
                          updateImages(next);
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.35),
                      shape: const CircleBorder(),
                      child: IconButton(
                        iconSize: 16,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(6),
                        icon: const Icon(Icons.close, color: Colors.white),
                        tooltip: 'Eliminar imagen',
                        onPressed: images.length <= 1
                            ? null
                            : () {
                                final next = images
                                    .map((e) => Map<String, dynamic>.from(e))
                                    .toList();
                                if (index >= 0 && index < next.length) {
                                  next.removeAt(index);
                                  updateImages(next);
                                }
                              },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            InlineEditableTextV2(
              text: caption,
              baseStyle: theme.textTheme.bodyMedium,
              textAlign: TextAlign.left,
              isEditMode: true,
              placeholder: 'Leyenda',
              fieldKey: '${widget.blockId}_gallery_${index}_caption',
              onTextChanged: (value) {
                final next =
                    images.map((e) => Map<String, dynamic>.from(e)).toList();
                if (index >= 0 && index < next.length) {
                  next[index]['caption'] = value;
                  updateImages(next);
                }
              },
            ),
          ],
        ),
      );
    }

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InlineEditableTextV2(
          text: title,
          baseStyle: theme.textTheme.headlineMedium,
          textAlign: TextAlign.center,
          isEditMode: true,
          placeholder: 'Galería',
          fieldKey: '${widget.blockId}_title',
          onTextChanged: (value) =>
              editProvider.updateBlockData(widget.blockId, 'title', value),
        ),
        const SizedBox(height: 24),
        ConstraintLayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth;
            final cols = maxWidth >= 1100
                ? 4
                : maxWidth >= 800
                    ? 3
                    : maxWidth >= 520
                        ? 2
                        : 1;
            const gap = 16.0;
            final tileWidth =
                cols == 1 ? maxWidth : (maxWidth - (gap * (cols - 1))) / cols;

            if (images.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.4),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.image_outlined,
                      color: theme.iconTheme.color?.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Agrega imágenes a tu galería',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }

            final tiles = <Widget>[];
            for (var i = 0; i < images.length; i++) {
              tiles.add(
                buildImageTile(index: i, img: images[i], tileWidth: tileWidth),
              );
            }

            // "masonry" currently falls back to a responsive wrap; keep layout simple.
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              alignment: WrapAlignment.center,
              children: tiles,
            );
          },
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.center,
          child: OutlinedButton.icon(
            onPressed: () {
              final next =
                  images.map((e) => Map<String, dynamic>.from(e)).toList();
              next.add({'imageUrl': '', 'caption': ''});
              updateImages(next);
            },
            icon: const Icon(Icons.add),
            label: const Text('Agregar imagen'),
          ),
        ),
        if (layout.isNotEmpty) const SizedBox(height: 0),
      ],
    );

    return ConstraintLayoutBuilder(
      builder: (context, constraints) {
        final hasFixedHeight = constraints.maxHeight.isFinite;
        return Container(
          width: double.infinity,
          height: hasFixedHeight ? constraints.maxHeight : null,
          padding: hasFixedHeight
              ? const EdgeInsets.symmetric(horizontal: 24)
              : const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: content,
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditableTeamCard(
    BuildContext context,
    Map<String, dynamic> member,
    int index,
    List<Map<String, dynamic>> allMembers,
    WebsiteEditModeProvider editProvider,
  ) {
    final theme = Theme.of(context);
    final name = (member['name'] ?? '').toString();
    final role = (member['role'] ?? '').toString();

    return Container(
      width: 250,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            children: [
              CircleAvatar(
                radius: 48,
                backgroundColor: widget.primaryColor.withValues(alpha: 0.1),
                child: Icon(Icons.person, size: 48, color: widget.primaryColor),
              ),
              const SizedBox(height: 16),
              InlineEditableTextV2(
                text: name,
                baseStyle: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
                isEditMode: true,
                placeholder: 'Nombre',
                fieldKey: '${widget.blockId}_team_${index}_name',
                onTextChanged: (value) {
                  final updated = List<Map<String, dynamic>>.from(allMembers);
                  updated[index] = Map<String, dynamic>.from(updated[index]);
                  updated[index]['name'] = value;
                  editProvider.updateBlockData(widget.blockId, 'team', updated);
                },
              ),
              const SizedBox(height: 4),
              InlineEditableTextV2(
                text: role,
                baseStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
                isEditMode: true,
                placeholder: 'Cargo',
                fieldKey: '${widget.blockId}_team_${index}_role',
                onTextChanged: (value) {
                  final updated = List<Map<String, dynamic>>.from(allMembers);
                  updated[index] = Map<String, dynamic>.from(updated[index]);
                  updated[index]['role'] = value;
                  editProvider.updateBlockData(widget.blockId, 'team', updated);
                },
              ),
            ],
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () {
                final updated = List<Map<String, dynamic>>.from(allMembers);
                updated.removeAt(index);
                editProvider.updateBlockData(widget.blockId, 'team', updated);
              },
              tooltip: 'Eliminar',
            ),
          ),
        ],
      ),
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

/// Editable button widget with "first click edits, second click navigates" behavior
class _EditableButton extends StatefulWidget {
  final String text;
  final String link;
  final Color backgroundColor;
  final Color? foregroundColor;
  final ValueChanged<String>? onTextChanged;
  final ValueChanged<String>? onLinkChanged;
  final ValueChanged<WebsiteActionValue>? onActionChanged;
  final WebsiteActionVariant actionVariant;
  final VoidCallback? onNavigate;

  const _EditableButton({
    required this.text,
    required this.link,
    required this.backgroundColor,
    this.foregroundColor,
    this.onTextChanged,
    this.onLinkChanged,
    this.onActionChanged,
    this.actionVariant = WebsiteActionVariant.filled,
    this.onNavigate,
  });

  @override
  State<_EditableButton> createState() => _EditableButtonState();
}

class _EditableButtonState extends State<_EditableButton> {
  bool _isSelected = false;
  bool _isEditing = false;
  bool _isHovering = false;
  late TextEditingController _textController;
  late TextEditingController _linkController;
  final FocusNode _textFocus = FocusNode();
  final FocusNode _linkFocus = FocusNode();

  // Overlay support
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  Color get _textColor {
    // If foreground color specified, use it; otherwise, compute based on background brightness
    if (widget.foregroundColor != null) return widget.foregroundColor!;
    return widget.backgroundColor.computeLuminance() > 0.5
        ? Colors.black87
        : Colors.white;
  }

  bool get _isOutlineStyle =>
      widget.actionVariant == WebsiteActionVariant.outline;

  bool get _isTextStyle => widget.actionVariant == WebsiteActionVariant.text;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.text);
    _linkController = TextEditingController(text: widget.link);
  }

  @override
  void didUpdateWidget(_EditableButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text && !_isEditing) {
      _textController.text = widget.text;
    }
    if (oldWidget.link != widget.link && !_isEditing) {
      _linkController.text = widget.link;
    }
  }

  void _removeOverlay() {
    final entry = _overlayEntry;
    if (entry == null) return;
    _overlayEntry = null;
    if (entry.mounted) {
      entry.remove();
    }
  }

  @override
  void deactivate() {
    // Defensive: during route transitions this widget can be deactivated while
    // still mounted. Ensure any overlay is torn down immediately.
    _removeOverlay();
    super.deactivate();
  }

  void _closeEditing([bool save = false]) {
    if (save) {
      final onActionChanged = widget.onActionChanged;
      if (onActionChanged != null) {
        onActionChanged(
          WebsiteActionValue(
            label: _textController.text,
            href: _linkController.text,
            variant: widget.actionVariant,
          ),
        );
      } else {
        widget.onTextChanged?.call(_textController.text);
        widget.onLinkChanged?.call(_linkController.text);
      }
    }
    _removeOverlay();
    if (mounted) {
      setState(() {
        _isEditing = false;
        _isSelected = false;
      });
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    _textController.dispose();
    _linkController.dispose();
    _textFocus.dispose();
    _linkFocus.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (!_isSelected) {
      // First click: select
      setState(() {
        _isSelected = true;
      });
    } else if (_isSelected && !_isEditing) {
      // Second click: start editing overlay
      setState(() {
        _isEditing = true;
      });
      _showEditorOverlay();
    }
  }

  void _showEditorOverlay() {
    _removeOverlay();

    // Safety check for render object
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      debugPrint('⚠️ [EditableBlock] RenderBox not ready for overlay');
      return;
    }

    final overlay = Overlay.of(context);
    final size = renderObject.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Modal barrier to close on outside click
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _closeEditing(true), // Save on outside click
              child: Container(color: Colors.transparent),
            ),
          ),
          // Floating editor
          Positioned(
            width: 320,
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              // Center the modal relative to the button
              offset: Offset(size.width / 2 - 160, size.height + 10),
              child: Material(
                color: Colors.transparent,
                child: _buildEditingUI(),
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(_overlayEntry!);

    // Auto-focus text field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _textFocus.requestFocus();
    });
  }

  void _handleNavigate() {
    if (widget.onNavigate != null && !_isEditing) {
      widget.onNavigate!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final globalButtonStyle = switch (widget.actionVariant) {
      WebsiteActionVariant.outline => theme.outlinedButtonTheme.style,
      WebsiteActionVariant.text => theme.textButtonTheme.style,
      WebsiteActionVariant.filled => theme.elevatedButtonTheme.style,
    };
    final resolvedShape = globalButtonStyle?.shape?.resolve({});
    final resolvedRadius = resolvedShape is RoundedRectangleBorder
        ? resolvedShape.borderRadius
        : BorderRadius.circular(8);
    final resolvedPadding = globalButtonStyle?.padding?.resolve({}) ??
        const EdgeInsets.symmetric(horizontal: 20, vertical: 12);
    final resolvedTextStyle = globalButtonStyle?.textStyle?.resolve({});

    // Always render the button visuals so layout doesn't jump
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: GestureDetector(
          onTap: _handleTap,
          onDoubleTap: _handleNavigate,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: _isOutlineStyle || _isTextStyle
                  ? Colors.transparent
                  : widget.backgroundColor,
              borderRadius: resolvedRadius,
              border: _isSelected
                  ? Border.all(color: Colors.blue, width: 2)
                  : _isHovering
                      ? Border.all(
                          color: Colors.blue.withValues(alpha: 0.5), width: 2)
                      : _isOutlineStyle
                          ? Border.all(color: _textColor, width: 1)
                          : null,
              boxShadow: _isSelected
                  ? [
                      BoxShadow(
                          color: Colors.blue.withValues(alpha: 0.3),
                          blurRadius: 8)
                    ]
                  : null,
            ),
            child: Stack(
              children: [
                Padding(
                  padding: resolvedPadding,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.text.isEmpty
                            ? 'Botón'
                            : (_isOutlineStyle
                                ? widget.text.toUpperCase()
                                : widget.text),
                        style:
                            (resolvedTextStyle ?? const TextStyle()).copyWith(
                          color: _textColor,
                          fontWeight: FontWeight.w600,
                          letterSpacing: _isOutlineStyle ? 1.5 : 0,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        _isSelected ? Icons.edit : Icons.touch_app,
                        size: 16,
                        color: _textColor.withValues(alpha: 0.7),
                      ),
                    ],
                  ),
                ),
                // Hint text
                if (_isHovering && !_isSelected)
                  Positioned(
                    top: -24,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Clic para editar',
                          style: TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ),
                    ),
                  ),
                if (_isSelected && !_isEditing)
                  Positioned(
                    top: -24,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Clic de nuevo para editar • Doble clic para navegar',
                          style: TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditingUI() {
    const tealAccent = Color(0xFF00A09D);
    const darkBg = Color(0xFF1E1E1E);
    const darkSurface = Color(0xFF2D2D2D);

    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: darkBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tealAccent, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.smart_button, color: tealAccent, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Editar Botón',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () => _closeEditing(true), // Save and close
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 16, color: Colors.white54),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Text field label
          const Text(
            'Texto del botón',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _textController,
            focusNode: _textFocus,
            cursorColor: tealAccent,
            style: const TextStyle(fontSize: 13, color: Colors.white),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: darkSurface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: tealAccent),
              ),
              hintText: 'Ej: Ver catálogo',
              hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3), fontSize: 13),
            ),
            // Update preview locally, sync on close
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),

          WebsiteLinkValueEditor(
            label: 'Enlace del botón',
            value: _linkController.text,
            dense: true,
            darkStyle: true,
            onChanged: (value) {
              _linkController.text = value;
              setState(() {});
            },
          ),
          const SizedBox(height: 16),

          // Preview and save row
          Row(
            children: [
              // Preview
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: widget.backgroundColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _textController.text.isEmpty
                        ? 'Botón'
                        : _textController.text,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _textColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Done button
              GestureDetector(
                onTap: () => _closeEditing(true), // Save and close
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: tealAccent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, size: 16, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        'Listo',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Editable carousel widget with inline text editing for each slide
class _EditableCarouselWidget extends StatefulWidget {
  final List<Map<String, dynamic>> slides;
  final bool showIndicators;
  final bool showArrows;
  final Color primaryColor;
  final Color accentColor;
  final String? headingFont;
  final String? bodyFont;
  final double? headingSize;
  final double? bodySize;
  final String blockId;
  final double? blockHeight; // Custom height from resize handle
  final Duration animationDuration;
  final int selectedSlideIndex;
  final ValueChanged<int> onSlideSelected;
  final void Function(int index, String field, dynamic value) onSlideUpdated;
  final void Function(int index, String field, dynamic value)
      onSlideTransientUpdated;
  final void Function(int index, WebsiteActionValue action)
      onSlideActionUpdated;
  final void Function(String route)? onNavigate;
  final String? tenantId;

  const _EditableCarouselWidget({
    required this.slides,
    required this.showIndicators,
    required this.showArrows,
    required this.primaryColor,
    required this.accentColor,
    this.headingFont,
    this.bodyFont,
    this.headingSize,
    this.bodySize,
    required this.blockId,
    this.blockHeight,
    required this.animationDuration,
    required this.selectedSlideIndex,
    required this.onSlideSelected,
    required this.onSlideUpdated,
    required this.onSlideTransientUpdated,
    required this.onSlideActionUpdated,
    this.onNavigate,
    this.tenantId,
  });

  @override
  State<_EditableCarouselWidget> createState() =>
      _EditableCarouselWidgetState();
}

class _EditableCarouselWidgetState extends State<_EditableCarouselWidget> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.selectedSlideIndex;
  }

  @override
  void didUpdateWidget(covariant _EditableCarouselWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final maxIndex = widget.slides.isEmpty ? 0 : widget.slides.length - 1;
    final selected = widget.selectedSlideIndex.clamp(0, maxIndex).toInt();
    if (_currentIndex != selected) {
      _currentIndex = selected;
    }
  }

  /// Apply font family via CSS font-family instead of GoogleFonts package
  /// (GoogleFonts adds ~6.5MB to bundle with all font metadata)
  static TextStyle _applyThemeFont(TextStyle base, String? fontFamily) {
    final family = fontFamily?.trim();
    if (family == null || family.isEmpty) return base;
    // Apply font family directly - browser loads via CSS @font-face or system fonts
    return base.copyWith(fontFamily: family);
  }

  void _nextSlide() {
    final next = (_currentIndex + 1) % widget.slides.length;
    setState(() => _currentIndex = next);
    widget.onSlideSelected(next);
  }

  void _previousSlide() {
    final previous =
        (_currentIndex - 1 + widget.slides.length) % widget.slides.length;
    setState(() => _currentIndex = previous);
    widget.onSlideSelected(previous);
  }

  void _goToSlide(int index) {
    setState(() => _currentIndex = index);
    widget.onSlideSelected(index);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.slides.isEmpty) {
      return const SizedBox.shrink();
    }

    // Use LayoutBuilder to get width for mobile detection
    return ConstraintLayoutBuilder(
      builder: (context, constraints) {
        // Use custom height if set, otherwise default to 520
        final height = widget.blockHeight ?? 520.0;

        return SizedBox(
          height: height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Current slide
              AnimatedSwitcher(
                duration: widget.animationDuration,
                child: _buildEditableSlide(
                    context,
                    widget.slides[_currentIndex],
                    _currentIndex,
                    constraints.maxWidth),
              ),

              // Indicators
              if (widget.showIndicators && widget.slides.length > 1)
                Positioned(
                  bottom: 32,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(widget.slides.length, (index) {
                      final isActive = index == _currentIndex;
                      return GestureDetector(
                        onTap: () => _goToSlide(index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: isActive
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.4),
                            shape: BoxShape.circle,
                          ),
                        ),
                      );
                    }),
                  ),
                ),

              // Arrows
              if (widget.showArrows && widget.slides.length > 1) ...[
                Positioned(
                  left: 24,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _buildArrowButton(
                      icon: Icons.chevron_left,
                      onTap: _previousSlide,
                    ),
                  ),
                ),
                Positioned(
                  right: 24,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _buildArrowButton(
                      icon: Icons.chevron_right,
                      onTap: _nextSlide,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildArrowButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.black.withValues(alpha: 0.3),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: Colors.white, size: 32),
        ),
      ),
    );
  }

  Widget _buildEditableSlide(BuildContext context, Map<String, dynamic> slide,
      int index, double maxWidth) {
    final theme = Theme.of(context);

    final title = (slide['title'] ?? 'Título').toString().trim();
    final subtitle = (slide['subtitle'] ?? '').toString().trim();
    final action = WebsiteActionValue.resolvePrimary(
          slide,
          labelKeys: const ['ctaText', 'buttonText'],
          hrefKeys: const ['ctaLink', 'buttonLink'],
          defaultLabel: 'Ver más',
          defaultHref: '/productos',
          defaultVariant: WebsiteActionVariant.outline,
        ) ??
        const WebsiteActionValue(
          label: 'Ver más',
          href: '/productos',
          variant: WebsiteActionVariant.outline,
        );
    final imageUrl = slide['imageUrl'];
    final showOverlay = (slide['showOverlay'] ?? true) == true;
    final compositionElements = slide['elements'] is List
        ? (slide['elements'] as List)
            .whereType<Map>()
            .map((element) => Map<String, dynamic>.from(element))
            .toList(growable: false)
        : const <Map<String, dynamic>>[];
    final usesComposition =
        slide['useComposition'] == true || compositionElements.isNotEmpty;

    double overlayOpacity = 0.55;
    final rawOverlay = slide['overlayOpacity'];
    if (rawOverlay is num) {
      overlayOpacity = rawOverlay.toDouble();
    } else if (rawOverlay is String) {
      overlayOpacity = double.tryParse(rawOverlay) ?? 0.55;
    }
    overlayOpacity = overlayOpacity.clamp(0.0, 1.0);

    final hasImage = imageUrl != null && imageUrl.toString().isNotEmpty;

    // Detect mobile and resolve background alignment
    // Priority: focal point values > legacy preset alignment > center default
    final isMobile = maxWidth < 600;
    Alignment bgAlignment = Alignment.center;
    if (isMobile) {
      final focalX = (slide['mobileFocalPointX'] as num?)?.toDouble();
      final focalY = (slide['mobileFocalPointY'] as num?)?.toDouble();

      if (focalX != null && focalY != null) {
        // Convert from 0-1 range to -1 to 1 range for Alignment
        bgAlignment = Alignment(
          (focalX * 2) - 1,
          (focalY * 2) - 1,
        );
      } else if (slide['mobileBgAlignment'] != null) {
        // Legacy fallback
        switch (slide['mobileBgAlignment'].toString()) {
          case 'left':
          case 'centerLeft':
            bgAlignment = Alignment.centerLeft;
            break;
          case 'right':
          case 'centerRight':
            bgAlignment = Alignment.centerRight;
            break;
          case 'top':
          case 'topCenter':
            bgAlignment = Alignment.topCenter;
            break;
          case 'bottom':
          case 'bottomCenter':
            bgAlignment = Alignment.bottomCenter;
            break;
          case 'center':
          default:
            bgAlignment = Alignment.center;
        }
      }
    }

    // Get formatting data if saved
    final titleFormatting = TextFormatting.fromJson(
        slide['titleFormatting'] as Map<String, dynamic>?);
    final subtitleFormatting = TextFormatting.fromJson(
        slide['subtitleFormatting'] as Map<String, dynamic>?);

    final headingStyle = _applyThemeFont(
      (theme.textTheme.displayLarge ?? const TextStyle()).copyWith(
        fontSize: widget.headingSize ?? 48,
        color: Colors.white,
        letterSpacing: 3,
        fontWeight: FontWeight.w900,
      ),
      widget.headingFont,
    );

    final subtitleStyle = _applyThemeFont(
      (theme.textTheme.headlineSmall ?? const TextStyle()).copyWith(
        fontSize: widget.bodySize != null ? widget.bodySize! * 1.2 : 20,
        color: Colors.white70,
      ),
      widget.bodyFont,
    );

    return Container(
      key: ValueKey<int>(index),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background image with alignment (NOT inline-editable; keep selection UX clean)
          DecoratedBox(
            decoration: WebsiteBlockRenderer.resolveBackgroundDecoration(
              data: slide,
              defaultColor: widget.primaryColor,
              imageUrl: hasImage ? imageUrl.toString() : null,
              imageAlignment: bgAlignment,
            ),
          ),

          // Overlay
          if (showOverlay)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: overlayOpacity * 0.4),
                    Colors.black.withValues(alpha: overlayOpacity * 0.7),
                  ],
                ),
              ),
            ),

          // Layered campaigns reuse the same Canvas elements and inspector as
          // standalone Canvas blocks. Legacy slides keep their inline stack.
          if (usesComposition)
            CanvasBlock(
              data: <String, dynamic>{
                'backgroundColor': '#00000000',
                'showGrid': true,
                'snap': true,
                'designWidth':
                    (slide['designWidth'] as num?)?.toDouble() ?? 1200.0,
                'mobileDesignWidth':
                    (slide['mobileDesignWidth'] as num?)?.toDouble() ?? 390.0,
                'constrainElementsToSafeArea':
                    slide['constrainElementsToSafeArea'] != false,
                'blockHeight':
                    (slide['designHeight'] as num?)?.toDouble() ?? 750.0,
                'activeElementId': context
                    .read<WebsiteEditModeProvider>()
                    .canvasElementSelection(widget.blockId, slideIndex: index),
                'elements': compositionElements,
              },
              editable: true,
              accentColor: widget.accentColor,
              onElementsChanged: (elements) =>
                  widget.onSlideUpdated(index, 'elements', elements),
              onActiveElementChanged: (elementId) {
                context.read<WebsiteEditModeProvider>().selectCanvasElement(
                      widget.blockId,
                      elementId,
                      slideIndex: index,
                      slideCount: widget.slides.length,
                    );
              },
              onBackgroundTap: () => context
                  .read<WebsiteEditModeProvider>()
                  .selectBlock(widget.blockId),
              onNavigate: widget.onNavigate,
              tenantId: widget.tenantId,
              headingFont: widget.headingFont,
              bodyFont: widget.bodyFont,
              fillAvailableHeight: true,
              clipContentToBounds: true,
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Editable title
                      InlineEditableTextV2(
                        text: title.isEmpty
                            ? 'Título del Banner'
                            : title.toUpperCase(),
                        baseStyle: headingStyle,
                        textAlign: TextAlign.center,
                        isEditMode: true,
                        placeholder: 'TÍTULO DEL BANNER',
                        formatting: titleFormatting,
                        fieldKey: '${widget.blockId}_slide_${index}_title',
                        onTextChanged: (value) =>
                            widget.onSlideUpdated(index, 'title', value),
                        onFormattingChanged: (formatting) =>
                            widget.onSlideUpdated(
                          index,
                          'titleFormatting',
                          formatting.toJson(),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Editable subtitle
                      InlineEditableTextV2(
                        text: subtitle,
                        baseStyle: subtitleStyle,
                        textAlign: TextAlign.center,
                        isEditMode: true,
                        placeholder: 'Subtítulo descriptivo',
                        formatting: subtitleFormatting,
                        fieldKey: '${widget.blockId}_slide_${index}_subtitle',
                        onTextChanged: (value) =>
                            widget.onSlideUpdated(index, 'subtitle', value),
                        onFormattingChanged: (formatting) =>
                            widget.onSlideUpdated(
                          index,
                          'subtitleFormatting',
                          formatting.toJson(),
                        ),
                      ),

                      const SizedBox(height: 40),

                      // Editable button
                      if (action.label.isNotEmpty)
                        _EditableButton(
                          text: action.label,
                          link: action.href,
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          actionVariant: action.variant,
                          onActionChanged: (value) =>
                              widget.onSlideActionUpdated(index, value),
                          onNavigate: action.href.isNotEmpty
                              ? () {
                                  widget.onNavigate?.call(action.href);
                                }
                              : null,
                        ),
                    ],
                  ),
                ),
              ),
            ),

          // Image edit button (bottom-right corner)
          Positioned(
            right: 16,
            bottom: 60,
            child: _SlideImageEditButton(
              currentImageUrl: hasImage ? imageUrl.toString() : null,
              onImageChanged: (url) =>
                  widget.onSlideUpdated(index, 'imageUrl', url),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small button to edit slide background image
class _SlideImageEditButton extends StatefulWidget {
  final String? currentImageUrl;
  final ValueChanged<String> onImageChanged;

  const _SlideImageEditButton({
    required this.currentImageUrl,
    required this.onImageChanged,
  });

  @override
  State<_SlideImageEditButton> createState() => _SlideImageEditButtonState();
}

class _SlideImageEditButtonState extends State<_SlideImageEditButton> {
  bool _isHovered = false;
  bool _isEditing = false;
  bool _showUrlOption = false;
  String? _urlError;
  final TextEditingController _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _urlController.text = widget.currentImageUrl ?? '';
  }

  @override
  void didUpdateWidget(_SlideImageEditButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentImageUrl != widget.currentImageUrl && !_isEditing) {
      _urlController.text = widget.currentImageUrl ?? '';
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _setImage(String url) {
    final normalized = url.trim();
    _urlController.text = normalized;
    widget.onImageChanged(normalized);
    if (!mounted) return;
    setState(() {
      _showUrlOption = false;
      _urlError = null;
    });
  }

  void _applyUrl() {
    final value = _urlController.text.trim();
    final uri = Uri.tryParse(value);
    if (value.isNotEmpty &&
        (uri == null ||
            !uri.hasScheme ||
            (uri.scheme != 'https' && uri.scheme != 'http') ||
            uri.host.isEmpty)) {
      setState(() {
        _urlError =
            'Ingresa una URL válida que comience con http:// o https://';
      });
      return;
    }
    _setImage(value);
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditing) {
      return Container(
        width: 360,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.photo_library_outlined,
                  size: 18,
                  color: Color(0xFF008A87),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Imagen del slide',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  tooltip: 'Cerrar',
                  onPressed: () => setState(() {
                    _isEditing = false;
                    _showUrlOption = false;
                    _urlError = null;
                  }),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Elige una imagen desde tu equipo. Se subirá y quedará guardada en el editor.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 154,
              width: double.infinity,
              child: InlineEditableImage(
                imageUrl: widget.currentImageUrl,
                width: double.infinity,
                height: 154,
                fit: BoxFit.cover,
                isEditMode: true,
                onChanged: _setImage,
                borderRadius: BorderRadius.circular(8),
                placeholder: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F7F7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.folder_open_outlined,
                        color: Color(0xFF008A87),
                        size: 32,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Elegir imagen',
                        style: TextStyle(
                          color: Color(0xFF006D6A),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'JPG, PNG o WebP',
                        style: TextStyle(color: Colors.black45, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if ((widget.currentImageUrl ?? '').isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _setImage(''),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Quitar'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() {
                    _showUrlOption = !_showUrlOption;
                    _urlError = null;
                  }),
                  icon: const Icon(Icons.link, size: 16),
                  label: Text(
                    _showUrlOption ? 'Ocultar URL' : 'Usar URL (avanzado)',
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.black54,
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
            if (_showUrlOption) ...[
              const SizedBox(height: 6),
              TextField(
                controller: _urlController,
                autofocus: true,
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  hintText: 'https://ejemplo.com/imagen.jpg',
                  hintStyle: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  errorText: _urlError,
                ),
                onSubmitted: (_) => _applyUrl(),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: _applyUrl,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF008A87),
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  ),
                  child: const Text(
                    'Aplicar URL',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () => setState(() => _isEditing = true),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _isHovered
                ? Colors.black.withValues(alpha: 0.7)
                : Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.image,
                size: 16,
                color: _isHovered ? Colors.white : Colors.white70,
              ),
              const SizedBox(width: 6),
              Text(
                'Imagen',
                style: TextStyle(
                  fontSize: 12,
                  color: _isHovered ? Colors.white : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
