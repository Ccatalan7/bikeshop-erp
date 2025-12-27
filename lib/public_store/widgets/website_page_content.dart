import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../modules/website/providers/website_edit_mode_provider.dart';
import '../../modules/website/widgets/deferred_editable_block_renderer.dart';
import '../../modules/website/widgets/inline_edit_toolbar.dart' show AddBlockDialog;
import '../../modules/website/widgets/block_spacer_handle.dart';
import '../../modules/website/widgets/website_block_renderer.dart';
import '../../shared/models/product.dart';
import '../theme/public_store_theme.dart';

/// Unified widget for rendering website page content (blocks).
/// 
/// This replaces the duplicated rendering logic in PublicHomePage and DynamicWebsitePage.
/// It handles:
/// - Block rendering (edit mode and view mode)
/// - Theme application
/// - Featured products for product blocks
/// - Responsive visibility
/// 
/// Design principles:
/// - Single responsibility: Only renders blocks, no data loading
/// - Props over providers: Receives all data via constructor
/// - No lifecycle side effects: Pure rendering based on inputs
class WebsitePageContent extends StatelessWidget {
  /// Blocks to render
  final List<Map<String, dynamic>> blocks;
  
  /// Featured products for products blocks (home page only)
  final List<Product> featuredProducts;
  
  /// Theme settings
  final Color primaryColor;
  final Color accentColor;
  final Color textColor;
  final String headingFont;
  final String bodyFont;
  final double headingSize;
  final double bodySize;
  final double sectionSpacing;
  final double containerPadding;
  
  /// Tenant context
  final String? tenantId;
  
  /// Whether we're still loading
  final bool isLoading;
  
  /// Whether this is the home page (affects empty state message)
  final bool isHomePage;
  
  const WebsitePageContent({
    super.key,
    required this.blocks,
    this.featuredProducts = const [],
    this.primaryColor = PublicStoreTheme.primaryBlue,
    this.accentColor = PublicStoreTheme.accentGreen,
    this.textColor = PublicStoreTheme.textPrimary,
    this.headingFont = '',
    this.bodyFont = '',
    this.headingSize = 48.0,
    this.bodySize = 16.0,
    this.sectionSpacing = 64.0,
    this.containerPadding = 24.0,
    this.tenantId,
    this.isLoading = false,
    this.isHomePage = false,
  });
  
  static const List<String> _responsiveBreakpoints = ['desktop', 'tablet', 'mobile'];

  @override
  Widget build(BuildContext context) {
    // Watch edit provider for edit mode state
    final editProvider = context.watch<WebsiteEditModeProvider>();
    final isEditMode = editProvider.isEditMode;
    final isInEditorContext = editProvider.isInEditorContext;
    
    // Use edit provider blocks if in editor context, otherwise use passed blocks
    final blocksToRender = isInEditorContext ? editProvider.blocks : blocks;
    
    // Still loading - show nothing (layout handles loading UI)
    if (isLoading && blocksToRender.isEmpty) {
      return const SizedBox.shrink();
    }
    
    // Filter blocks by visibility
    final currentBreakpoint = _currentBreakpoint(context);
    final visibleBlocks = _filterVisibleBlocks(blocksToRender, currentBreakpoint, isInEditorContext);
    
    // No blocks
    if (visibleBlocks.isEmpty) {
      return _buildEmptyState(context, isEditMode, editProvider);
    }
    
    // Render blocks
    return _buildBlocksList(context, visibleBlocks, isEditMode, editProvider);
  }
  
  String _currentBreakpoint(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 640) return 'mobile';
    if (width < 1024) return 'tablet';
    return 'desktop';
  }
  
  List<Map<String, dynamic>> _filterVisibleBlocks(
    List<Map<String, dynamic>> blocks,
    String breakpoint,
    bool isInEditorContext,
  ) {
    final filtered = blocks.where((block) {
      // In editor context, show all blocks
      if (isInEditorContext) return true;
      
      // Check global visibility
      final isGloballyVisible = block['is_visible'] ?? true;
      if (!isGloballyVisible) return false;
      
      // Check breakpoint visibility
      final data = Map<String, dynamic>.from(block['block_data'] ?? {});
      final visibility = _normalizeBlockVisibility(data['visibility']);
      return visibility[breakpoint] ?? true;
    }).toList();
    
    // Sort by order
    filtered.sort((a, b) {
      final orderA = a['sort_order'] ?? a['order_index'] ?? 0;
      final orderB = b['sort_order'] ?? b['order_index'] ?? 0;
      return (orderA as int).compareTo(orderB as int);
    });
    
    return filtered;
  }
  
  Map<String, bool> _normalizeBlockVisibility(dynamic raw) {
    final visibility = {for (final bp in _responsiveBreakpoints) bp: true};
    
    dynamic source = raw;
    if (source is String) {
      final trimmed = source.trim();
      if (trimmed.isEmpty) {
        source = null;
      } else {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is Map) source = decoded;
        } catch (_) {
          source = null;
        }
      }
    }
    
    if (source is Map) {
      source.forEach((key, value) {
        final keyString = key.toString();
        if (!visibility.containsKey(keyString)) return;
        final parsed = _toBool(value);
        if (parsed != null) visibility[keyString] = parsed;
      });
    }
    
    return visibility;
  }
  
  bool? _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1' || normalized == 'si' || normalized == 'sí') return true;
      if (normalized == 'false' || normalized == '0' || normalized == 'no') return false;
    }
    return null;
  }
  
  Widget _buildBlocksList(
    BuildContext context,
    List<Map<String, dynamic>> visibleBlocks,
    bool isEditMode,
    WebsiteEditModeProvider editProvider,
  ) {
    return Column(
      children: [
        // Drop zone before the first block (drag blocks from the Add tab)
        if (isEditMode)
          _InsertBlockDropZone(
            insertIndex: 0,
            onInsert: (type) => editProvider.addBlock(type, atIndex: 0),
          ),
        for (int i = 0; i < visibleBlocks.length; i++) ...[
          KeyedSubtree(
            key: ValueKey('${visibleBlocks[i]['id']}_${visibleBlocks[i]['block_data']?.toString().hashCode ?? 0}_$tenantId'),
            child: _buildBlock(context, visibleBlocks[i], isEditMode),
          ),
          // Add spacer between blocks (not after the last one)
          if (i < visibleBlocks.length - 1)
            _buildBlockSpacer(
              insertIndex: i + 1,
              blockId: visibleBlocks[i]['id']?.toString() ?? '',
              blockData: Map<String, dynamic>.from(visibleBlocks[i]['block_data'] ?? {}),
              isEditMode: isEditMode,
              editProvider: editProvider,
            ),
        ],
        SizedBox(height: sectionSpacing),
        
        // Add block button at the end in edit mode
        if (isEditMode)
          Padding(
            padding: const EdgeInsets.only(bottom: 32),
            child: _AddBlockButtonLarge(onAdd: (type) => editProvider.addBlock(type)),
          ),
      ],
    );
  }
  
  Widget _buildBlock(BuildContext context, Map<String, dynamic> blockData, bool isEditMode) {
    final blockId = blockData['id']?.toString() ?? '';
    final blockType = (blockData['block_type'] ?? '').toString();
    final data = Map<String, dynamic>.from(blockData['block_data'] ?? {});
    final isVisible = blockData['is_visible'] ?? true;
    
    data.remove('visibility');
    final resolvedHeadingFont = headingFont.isNotEmpty ? headingFont : null;
    final resolvedBodyFont = bodyFont.isNotEmpty ? bodyFont : null;
    
    final baseTheme = Theme.of(context);
    final themedText = baseTheme.textTheme.apply(
      bodyColor: textColor,
      displayColor: textColor,
    );
    
    // Full-width blocks get no horizontal padding
    final fullBleed = _toBool(data['fullBleed']) ?? false;
    final isFullWidthBlock = fullBleed ||
        const [
          'hero',
          'carousel',
          'videobanner',
          'categorygrid',
          'partnersbanner',
        ].contains(blockType.toLowerCase());
    final horizontalPadding = isFullWidthBlock ? 0.0 : containerPadding.clamp(0.0, 200.0);
    
    // Build the block widget
    final blockHeight = (data['blockHeight'] as num?)?.toDouble();
    
    Widget content = isEditMode
        ? DeferredEditableBlockRenderer.build(
            context: context,
            blockId: blockId,
            blockType: blockType,
            data: data,
            primaryColor: primaryColor,
            accentColor: accentColor,
            featuredProducts: blockType == 'products' ? featuredProducts : null,
            headingFont: resolvedHeadingFont,
            bodyFont: resolvedBodyFont,
            headingSize: headingSize,
            bodySize: bodySize,
            onNavigate: (route) => context.go(route),
            isVisible: isVisible,
            tenantId: tenantId,
          )
        : WebsiteBlockRenderer.build(
            context: context,
            blockType: blockType,
            data: data,
            primaryColor: primaryColor,
            accentColor: accentColor,
            featuredProducts: blockType == 'products' ? featuredProducts : null,
            previewMode: false,
            headingFont: resolvedHeadingFont,
            bodyFont: resolvedBodyFont,
            headingSize: headingSize,
            bodySize: bodySize,
            onNavigate: (route) => context.go(route),
            tenantId: tenantId,
          );
    
    // Apply custom block height if set
    if (!isEditMode && blockHeight != null) {
      content = SizedBox(
        height: blockHeight,
        width: double.infinity,
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
  
  Widget _buildBlockSpacer({
    required int insertIndex,
    required String blockId,
    required Map<String, dynamic> blockData,
    required bool isEditMode,
    required WebsiteEditModeProvider editProvider,
  }) {
    final spacingAfter = (blockData['spacingAfter'] as num?)?.toDouble() ?? sectionSpacing;
    
    if (isEditMode) {
      return _InsertBlockDropZone(
        insertIndex: insertIndex,
        onInsert: (type) => editProvider.addBlock(type, atIndex: insertIndex),
        child: BlockSpacerHandle(
          currentSpacing: spacingAfter,
          minSpacing: 0,
          maxSpacing: 200,
          snapIncrement: 4,
          isActive: true,
          onSpacingChanged: (newSpacing) {
            editProvider.updateBlockData(blockId, 'spacingAfter', newSpacing);
          },
          onSpacingChangeEnd: (finalSpacing) {},
        ),
      );
    } else {
      return SizedBox(height: spacingAfter);
    }
  }
  
  Widget _buildEmptyState(BuildContext context, bool isEditMode, WebsiteEditModeProvider editProvider) {
    if (isEditMode) {
      return Container(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.web, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 24),
            Text(
              'Tu sitio web está vacío',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            Text(
              'Agrega bloques para construir tu página',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[500]),
            ),
            const SizedBox(height: 32),
            _AddBlockButtonLarge(onAdd: (type) => editProvider.addBlock(type)),
          ],
        ),
      );
    }
    
    // Coming soon for visitors
    return Container(
      constraints: const BoxConstraints(minHeight: 500),
      padding: const EdgeInsets.all(48),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.storefront, size: 100, color: primaryColor.withValues(alpha: 0.5)),
            const SizedBox(height: 32),
            Text(
              'Próximamente',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Estamos preparando algo increíble para ti',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Drop target used to insert a new block at a specific index when dragging
/// from the "Agregar" tab (which provides Draggable<String>).
class _InsertBlockDropZone extends StatefulWidget {
  final int insertIndex;
  final void Function(String blockType) onInsert;
  final Widget? child;

  const _InsertBlockDropZone({
    required this.insertIndex,
    required this.onInsert,
    this.child,
  });

  @override
  State<_InsertBlockDropZone> createState() => _InsertBlockDropZoneState();
}

class _InsertBlockDropZoneState extends State<_InsertBlockDropZone> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (_) {
        if (!_isHovering) setState(() => _isHovering = true);
        return true;
      },
      onLeave: (_) {
        if (_isHovering) setState(() => _isHovering = false);
      },
      onAcceptWithDetails: (details) {
        setState(() => _isHovering = false);
        widget.onInsert(details.data);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bloque "${details.data}" agregado'),
            duration: const Duration(seconds: 1),
          ),
        );
      },
      builder: (context, candidateData, rejectedData) {
        final showHighlight = _isHovering || candidateData.isNotEmpty;
        return Stack(
          children: [
            if (widget.child != null) widget.child!,
            // Highlight overlay
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
            // If no child, render a thin drop bar
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

/// Large add block button
class _AddBlockButtonLarge extends StatelessWidget {
  final void Function(String blockType) onAdd;

  const _AddBlockButtonLarge({required this.onAdd});

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
                  style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 16),
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
