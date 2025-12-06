import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/website_edit_mode_provider.dart';
import '../widgets/inline_edit_toolbar.dart';
import '../widgets/inline_editable_text_v2.dart';
import '../widgets/inline_editable_image.dart';
import '../widgets/block_resize_handle.dart';
import '../widgets/text_formatting_toolbar.dart';
import 'website_block_renderer.dart';
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
  }) {
    final editProvider = context.watch<WebsiteEditModeProvider>();
    final isEditMode = editProvider.isEditMode;
    final isSelected = editProvider.selectedBlockId == blockId;

    // If not in edit mode, render normally
    if (!isEditMode) {
      if (!isVisible) return const SizedBox.shrink();
      
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
  });

  @override
  State<_EditableBlockWrapper> createState() => _EditableBlockWrapperState();
}

class _EditableBlockWrapperState extends State<_EditableBlockWrapper> {
  final GlobalKey _contentKey = GlobalKey();
  double? _measuredHeight;
  double? _localDragHeight; // Local height during drag (avoids Provider rebuilds)
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
    final renderBox = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && mounted) {
      final height = renderBox.size.height;
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

    // Build the editable content based on block type
    Widget blockContent = _buildEditableBlock(context);

    // Wrap with selection and action bar
    // Resize handles are INSIDE the Stack so they don't add extra space
    return GestureDetector(
      onTap: () => editProvider.selectBlock(widget.blockId),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The block content with visibility opacity and height
          // When custom height is set, blocks use LayoutBuilder to fill/center internally
          Opacity(
            opacity: widget.isVisible ? 1.0 : 0.5,
            child: KeyedSubtree(
              key: _contentKey,
              child: displayHeight != null
                  ? SizedBox(
                      height: displayHeight,
                      width: double.infinity,
                      child: blockContent,
                    )
                  : blockContent,
            ),
          ),

          // Selection border
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: widget.isSelected ? const Color(0xFF00A09D) : Colors.transparent,
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
                onToggleVisibility: () => editProvider.toggleBlockVisibility(widget.blockId),
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

  /// Get minimum height for block type
  double _getMinHeight(String type) {
    switch (type) {
      case 'hero':
      case 'carousel':
        return 200;
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
      case 'about':
        return _buildEditableAbout(context);
      case 'cta':
        return _buildEditableCta(context);
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
        );
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
          'ctaLink': '/tienda/productos',
        }
      ];
    }

    // Configuration
    final showIndicators = (widget.data['showIndicators'] ?? true) == true;
    final showArrows = (widget.data['showArrows'] ?? true) == true;

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
      onSlideUpdated: (index, field, value) {
        // Update the slide data in the block
        final updatedSlides = List<Map<String, dynamic>>.from(slides);
        if (index < updatedSlides.length) {
          updatedSlides[index] = Map<String, dynamic>.from(updatedSlides[index]);
          updatedSlides[index][field] = value;
          editProvider.updateBlockData(widget.blockId, 'slides', updatedSlides);
        }
      },
      onNavigate: widget.onNavigate,
    );
  }

  Widget _buildEditableHero(BuildContext context) {
    final editProvider = context.read<WebsiteEditModeProvider>();
    final theme = Theme.of(context);

    final title = (widget.data['title'] ?? '').toString();
    final subtitle = (widget.data['subtitle'] ?? '').toString();
    final ctaText = (widget.data['buttonText'] ?? widget.data['ctaText'] ?? 'Ver más').toString();
    final ctaLink = (widget.data['buttonLink'] ?? widget.data['ctaLink'] ?? '').toString();
    final imageUrl = widget.data['backgroundImage']?.toString();
    
    // Get formatting data if saved
    final titleFormatting = TextFormatting.fromJson(
      widget.data['titleFormatting'] as Map<String, dynamic>?
    );
    final subtitleFormatting = TextFormatting.fromJson(
      widget.data['subtitleFormatting'] as Map<String, dynamic>?
    );

    final headingStyle = (theme.textTheme.displayLarge ?? const TextStyle()).copyWith(
      fontFamily: widget.headingFont?.isNotEmpty == true ? widget.headingFont : null,
      fontSize: widget.headingSize ?? 48,
      color: Colors.white,
    );

    final subtitleStyle = (theme.textTheme.headlineSmall ?? const TextStyle()).copyWith(
      fontFamily: widget.bodyFont?.isNotEmpty == true ? widget.bodyFont : null,
      fontSize: widget.bodySize != null ? widget.bodySize! * 1.2 : 20,
      color: Colors.white70,
    );

    return Container(
      height: 480,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background image (editable)
          InlineEditableImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            isEditMode: true,
            onChanged: (url) => editProvider.updateBlockData(widget.blockId, 'backgroundImage', url),
            placeholder: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [widget.primaryColor, widget.accentColor.withValues(alpha: 0.85)],
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
                    onTextChanged: (value) => editProvider.updateBlockData(widget.blockId, 'title', value),
                    onFormattingChanged: (formatting) => editProvider.updateBlockData(
                      widget.blockId, 'titleFormatting', formatting.toJson(),
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
                    onTextChanged: (value) => editProvider.updateBlockData(widget.blockId, 'subtitle', value),
                    onFormattingChanged: (formatting) => editProvider.updateBlockData(
                      widget.blockId, 'subtitleFormatting', formatting.toJson(),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Editable button with click handler
                  _EditableButton(
                    text: ctaText.isEmpty ? 'Ver más' : ctaText,
                    link: ctaLink,
                    backgroundColor: widget.accentColor,
                    onTextChanged: (value) => editProvider.updateBlockData(widget.blockId, 'buttonText', value),
                    onLinkChanged: (value) => editProvider.updateBlockData(widget.blockId, 'buttonLink', value),
                    onNavigate: ctaLink.isNotEmpty ? () {
                      widget.onNavigate?.call(ctaLink);
                    } : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableAbout(BuildContext context) {
    final editProvider = context.read<WebsiteEditModeProvider>();
    final theme = Theme.of(context);

    final title = (widget.data['title'] ?? '').toString();
    final description = (widget.data['description'] ?? '').toString();
    final imageUrl = widget.data['image']?.toString();

    // Get formatting data if saved
    final titleFormatting = TextFormatting.fromJson(
      widget.data['titleFormatting'] as Map<String, dynamic>?
    );
    final descriptionFormatting = TextFormatting.fromJson(
      widget.data['descriptionFormatting'] as Map<String, dynamic>?
    );

    final headingStyle = (theme.textTheme.headlineMedium ?? const TextStyle()).copyWith(
      fontFamily: widget.headingFont?.isNotEmpty == true ? widget.headingFont : null,
      fontWeight: FontWeight.bold,
    );

    final bodyStyle = (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      fontFamily: widget.bodyFont?.isNotEmpty == true ? widget.bodyFont : null,
      height: 1.6,
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Image side
          Expanded(
            child: InlineEditableImage(
              imageUrl: imageUrl,
              height: 400,
              fit: BoxFit.cover,
              borderRadius: BorderRadius.circular(16),
              isEditMode: true,
              onChanged: (url) => editProvider.updateBlockData(widget.blockId, 'image', url),
            ),
          ),

          const SizedBox(width: 48),

          // Text side
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InlineEditableTextV2(
                  text: title,
                  baseStyle: headingStyle,
                  isEditMode: true,
                  placeholder: 'Sobre Nosotros',
                  formatting: titleFormatting,
                  fieldKey: '${widget.blockId}_about_title',
                  onTextChanged: (value) => editProvider.updateBlockData(widget.blockId, 'title', value),
                  onFormattingChanged: (formatting) => editProvider.updateBlockData(
                    widget.blockId, 'titleFormatting', formatting.toJson(),
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
                  onTextChanged: (value) => editProvider.updateBlockData(widget.blockId, 'description', value),
                  onFormattingChanged: (formatting) => editProvider.updateBlockData(
                    widget.blockId, 'descriptionFormatting', formatting.toJson(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableCta(BuildContext context) {
    final editProvider = context.read<WebsiteEditModeProvider>();
    final theme = Theme.of(context);

    final title = (widget.data['title'] ?? '').toString();
    final description = (widget.data['description'] ?? '').toString();
    final buttonText = (widget.data['buttonText'] ?? 'Contactar').toString();
    final buttonLink = (widget.data['buttonLink'] ?? '').toString();

    // Get formatting data if saved
    final titleFormatting = TextFormatting.fromJson(
      widget.data['titleFormatting'] as Map<String, dynamic>?
    );
    final descriptionFormatting = TextFormatting.fromJson(
      widget.data['descriptionFormatting'] as Map<String, dynamic>?
    );

    final headingStyle = (theme.textTheme.headlineMedium ?? const TextStyle()).copyWith(
      fontFamily: widget.headingFont?.isNotEmpty == true ? widget.headingFont : null,
      fontWeight: FontWeight.bold,
      color: Colors.white,
    );

    final bodyStyle = (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      fontFamily: widget.bodyFont?.isNotEmpty == true ? widget.bodyFont : null,
      color: Colors.white70,
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [widget.primaryColor, widget.accentColor],
        ),
      ),
      child: Column(
        children: [
          InlineEditableTextV2(
            text: title,
            baseStyle: headingStyle,
            textAlign: TextAlign.center,
            isEditMode: true,
            placeholder: 'Llamado a la Acción',
            formatting: titleFormatting,
            fieldKey: '${widget.blockId}_cta_title',
            onTextChanged: (value) => editProvider.updateBlockData(widget.blockId, 'title', value),
            onFormattingChanged: (formatting) => editProvider.updateBlockData(
              widget.blockId, 'titleFormatting', formatting.toJson(),
            ),
          ),
          const SizedBox(height: 16),
          InlineEditableTextV2(
            text: description,
            baseStyle: bodyStyle,
            textAlign: TextAlign.center,
            isEditMode: true,
            placeholder: 'Descripción del llamado a la acción',
            formatting: descriptionFormatting,
            fieldKey: '${widget.blockId}_cta_description',
            onTextChanged: (value) => editProvider.updateBlockData(widget.blockId, 'description', value),
            onFormattingChanged: (formatting) => editProvider.updateBlockData(
              widget.blockId, 'descriptionFormatting', formatting.toJson(),
            ),
          ),
          const SizedBox(height: 32),
          _EditableButton(
            text: buttonText.isEmpty ? 'Contactar' : buttonText,
            link: buttonLink,
            backgroundColor: Colors.white,
            foregroundColor: widget.primaryColor, // Text matches CTA gradient color
            onTextChanged: (value) => editProvider.updateBlockData(widget.blockId, 'buttonText', value),
            onLinkChanged: (value) => editProvider.updateBlockData(widget.blockId, 'buttonLink', value),
            onNavigate: buttonLink.isNotEmpty ? () {
              widget.onNavigate?.call(buttonLink);
            } : null,
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WebsiteEditModeProvider editProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Bloque'),
        content: const Text('¿Estás seguro de que deseas eliminar este bloque?'),
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
  final ValueChanged<String> onTextChanged;
  final ValueChanged<String> onLinkChanged;
  final VoidCallback? onNavigate;

  const _EditableButton({
    required this.text,
    required this.link,
    required this.backgroundColor,
    this.foregroundColor,
    required this.onTextChanged,
    required this.onLinkChanged,
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
  
  Color get _textColor {
    // If foreground color specified, use it; otherwise, compute based on background brightness
    if (widget.foregroundColor != null) return widget.foregroundColor!;
    return widget.backgroundColor.computeLuminance() > 0.5 
        ? Colors.black87 
        : Colors.white;
  }
  
  bool get _isOutlineStyle => widget.backgroundColor == Colors.transparent;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.text);
    _linkController = TextEditingController(text: widget.link);
    
    _textFocus.addListener(_onFocusChange);
    _linkFocus.addListener(_onFocusChange);
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

  void _onFocusChange() {
    if (!_textFocus.hasFocus && !_linkFocus.hasFocus) {
      setState(() {
        _isEditing = false;
        _isSelected = false;
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _linkController.dispose();
    _textFocus.dispose();
    _linkFocus.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (!_isSelected) {
      // First click: select and show editing UI
      setState(() {
        _isSelected = true;
      });
    } else if (_isSelected && !_isEditing) {
      // Second click while selected: start editing
      setState(() {
        _isEditing = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _textFocus.requestFocus();
      });
    }
  }

  void _handleNavigate() {
    if (widget.onNavigate != null && !_isEditing) {
      widget.onNavigate!();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditing) {
      return _buildEditingUI();
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: _handleTap,
        onDoubleTap: _handleNavigate,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _isOutlineStyle ? Colors.transparent : widget.backgroundColor,
            borderRadius: _isOutlineStyle ? BorderRadius.zero : BorderRadius.circular(8),
            border: _isSelected
                ? Border.all(color: Colors.blue, width: 2)
                : _isHovering
                    ? Border.all(color: Colors.blue.withValues(alpha: 0.5), width: 2)
                    : _isOutlineStyle
                        ? Border.all(color: _textColor, width: 1)
                        : null,
            boxShadow: _isSelected
                ? [BoxShadow(color: Colors.blue.withValues(alpha: 0.3), blurRadius: 8)]
                : null,
          ),
          child: Stack(
            children: [
              Padding(
                padding: _isOutlineStyle 
                    ? const EdgeInsets.symmetric(horizontal: 40, vertical: 16)
                    : const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.text.isEmpty ? 'Botón' : (_isOutlineStyle ? widget.text.toUpperCase() : widget.text),
                      style: TextStyle(
                        color: _textColor,
                        fontWeight: FontWeight.w600,
                        fontSize: _isOutlineStyle ? 13 : 16,
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
    );
  }

  Widget _buildEditingUI() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
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
              Icon(Icons.smart_button, color: Colors.blue[600], size: 20),
              const SizedBox(width: 8),
              const Text(
                'Editar Botón',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.black87,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  setState(() {
                    _isEditing = false;
                    _isSelected = false;
                  });
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Text field
          TextField(
            controller: _textController,
            focusNode: _textFocus,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
            decoration: InputDecoration(
              labelText: 'Texto del botón',
              labelStyle: TextStyle(fontSize: 12, color: Colors.grey[600]),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              prefixIcon: const Icon(Icons.text_fields, size: 18),
            ),
            onChanged: widget.onTextChanged,
          ),
          const SizedBox(height: 12),
          
          // Link field
          TextField(
            controller: _linkController,
            focusNode: _linkFocus,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
            decoration: InputDecoration(
              labelText: 'Enlace (URL o ruta)',
              labelStyle: TextStyle(fontSize: 12, color: Colors.grey[600]),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              prefixIcon: const Icon(Icons.link, size: 18),
              hintText: '/tienda/productos',
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
            ),
            onChanged: widget.onLinkChanged,
          ),
          const SizedBox(height: 16),
          
          // Preview and save
          Row(
            children: [
              // Preview
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: widget.backgroundColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _textController.text.isEmpty ? 'Botón' : _textController.text,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _textColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Done button
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _isEditing = false;
                    _isSelected = false;
                  });
                },
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Listo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
  final void Function(int index, String field, dynamic value) onSlideUpdated;
  final void Function(String route)? onNavigate;

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
    required this.onSlideUpdated,
    this.onNavigate,
  });

  @override
  State<_EditableCarouselWidget> createState() => _EditableCarouselWidgetState();
}

class _EditableCarouselWidgetState extends State<_EditableCarouselWidget> {
  int _currentIndex = 0;

  void _nextSlide() {
    setState(() {
      _currentIndex = (_currentIndex + 1) % widget.slides.length;
    });
  }

  void _previousSlide() {
    setState(() {
      _currentIndex = (_currentIndex - 1 + widget.slides.length) % widget.slides.length;
    });
  }

  void _goToSlide(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.slides.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 520,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Current slide
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            child: _buildEditableSlide(context, widget.slides[_currentIndex], _currentIndex),
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

  Widget _buildEditableSlide(BuildContext context, Map<String, dynamic> slide, int index) {
    final theme = Theme.of(context);
    
    final title = (slide['title'] ?? 'Título').toString().trim();
    final subtitle = (slide['subtitle'] ?? '').toString().trim();
    final ctaText = (slide['ctaText'] ?? 'Ver más').toString().trim();
    final ctaLink = (slide['ctaLink'] ?? '/tienda/productos').toString().trim();
    final imageUrl = slide['imageUrl'];
    final showOverlay = (slide['showOverlay'] ?? true) == true;

    double overlayOpacity = 0.55;
    final rawOverlay = slide['overlayOpacity'];
    if (rawOverlay is num) {
      overlayOpacity = rawOverlay.toDouble();
    } else if (rawOverlay is String) {
      overlayOpacity = double.tryParse(rawOverlay) ?? 0.55;
    }
    overlayOpacity = overlayOpacity.clamp(0.0, 1.0);

    final hasImage = imageUrl != null && imageUrl.toString().isNotEmpty;

    // Get formatting data if saved
    final titleFormatting = TextFormatting.fromJson(
      slide['titleFormatting'] as Map<String, dynamic>?
    );
    final subtitleFormatting = TextFormatting.fromJson(
      slide['subtitleFormatting'] as Map<String, dynamic>?
    );

    final headingStyle = (theme.textTheme.displayLarge ?? const TextStyle()).copyWith(
      fontFamily: widget.headingFont?.isNotEmpty == true ? widget.headingFont : null,
      fontSize: widget.headingSize ?? 48,
      color: Colors.white,
      letterSpacing: 3,
      fontWeight: FontWeight.w900,
    );

    final subtitleStyle = (theme.textTheme.headlineSmall ?? const TextStyle()).copyWith(
      fontFamily: widget.bodyFont?.isNotEmpty == true ? widget.bodyFont : null,
      fontSize: widget.bodySize != null ? widget.bodySize! * 1.2 : 20,
      color: Colors.white70,
    );

    return Container(
      key: ValueKey<int>(index),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background image (NOT editable via hover - use corner button instead)
          if (hasImage)
            Image.network(
              imageUrl.toString(),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (context, error, stackTrace) => Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [widget.primaryColor, widget.accentColor.withValues(alpha: 0.85)],
                  ),
                ),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [widget.primaryColor, widget.accentColor.withValues(alpha: 0.85)],
                ),
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

          // Content with editable text
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
                      text: title.isEmpty ? 'Título del Banner' : title.toUpperCase(),
                      baseStyle: headingStyle,
                      textAlign: TextAlign.center,
                      isEditMode: true,
                      placeholder: 'TÍTULO DEL BANNER',
                      formatting: titleFormatting,
                      fieldKey: '${widget.blockId}_slide_${index}_title',
                      onTextChanged: (value) => widget.onSlideUpdated(index, 'title', value),
                      onFormattingChanged: (formatting) => widget.onSlideUpdated(
                        index, 'titleFormatting', formatting.toJson(),
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
                      onTextChanged: (value) => widget.onSlideUpdated(index, 'subtitle', value),
                      onFormattingChanged: (formatting) => widget.onSlideUpdated(
                        index, 'subtitleFormatting', formatting.toJson(),
                      ),
                    ),
                    
                    const SizedBox(height: 40),
                    
                    // Editable button
                    if (ctaText.isNotEmpty)
                      _EditableButton(
                        text: ctaText,
                        link: ctaLink,
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        onTextChanged: (value) => widget.onSlideUpdated(index, 'ctaText', value),
                        onLinkChanged: (value) => widget.onSlideUpdated(index, 'ctaLink', value),
                        onNavigate: ctaLink.isNotEmpty ? () {
                          widget.onNavigate?.call(ctaLink);
                        } : null,
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
              onImageChanged: (url) => widget.onSlideUpdated(index, 'imageUrl', url),
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

  @override
  Widget build(BuildContext context) {
    if (_isEditing) {
      return Container(
        width: 320,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.image, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                const Text(
                  'URL de imagen',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => setState(() => _isEditing = false),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                hintText: 'https://ejemplo.com/imagen.jpg',
                hintStyle: TextStyle(fontSize: 12, color: Colors.grey[400]),
              ),
              onSubmitted: (value) {
                widget.onImageChanged(value);
                setState(() => _isEditing = false);
              },
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => setState(() => _isEditing = false),
                  child: const Text('Cancelar', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    widget.onImageChanged(_urlController.text);
                    setState(() => _isEditing = false);
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  child: const Text('Guardar', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
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
