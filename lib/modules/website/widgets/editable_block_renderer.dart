import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/website_edit_mode_provider.dart';
import '../widgets/inline_edit_toolbar.dart';
import '../widgets/inline_editable_text.dart';
import '../widgets/inline_editable_image.dart';
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

class _EditableBlockWrapper extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final editProvider = context.read<WebsiteEditModeProvider>();
    final blocks = editProvider.blocks;
    final blockIndex = blocks.indexWhere((b) => b['id'] == blockId);
    final isFirst = blockIndex == 0;
    final isLast = blockIndex == blocks.length - 1;

    // Build the editable content based on block type
    Widget blockContent = _buildEditableBlock(context);

    // Wrap with selection and action bar
    return GestureDetector(
      onTap: () => editProvider.selectBlock(blockId),
      child: Stack(
        children: [
          // The block content with visibility opacity
          Opacity(
            opacity: isVisible ? 1.0 : 0.5,
            child: blockContent,
          ),

          // Selection border
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isSelected ? Colors.blue : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
            ),
          ),

          // Hidden indicator
          if (!isVisible)
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
          if (isSelected)
            Positioned(
              top: 8,
              right: 8,
              child: BlockActionBar(
                blockId: blockId,
                blockType: blockType,
                isFirst: isFirst,
                isLast: isLast,
                isVisible: isVisible,
                onMoveUp: () => editProvider.moveBlockUp(blockId),
                onMoveDown: () => editProvider.moveBlockDown(blockId),
                onDuplicate: () => editProvider.duplicateBlock(blockId),
                onDelete: () => _confirmDelete(context, editProvider),
                onToggleVisibility: () => editProvider.toggleBlockVisibility(blockId),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEditableBlock(BuildContext context) {
    // For now, use the standard renderer
    // In a full implementation, each block type would have its own editable version
    switch (blockType) {
      case 'hero':
        return _buildEditableHero(context);
      case 'about':
        return _buildEditableAbout(context);
      case 'cta':
        return _buildEditableCta(context);
      default:
        // Fall back to standard renderer for other types
        return WebsiteBlockRenderer.build(
          context: context,
          blockType: blockType,
          data: data,
          primaryColor: primaryColor,
          accentColor: accentColor,
          featuredProducts: featuredProducts,
          previewMode: true,
          headingFont: headingFont,
          bodyFont: bodyFont,
          headingSize: headingSize,
          bodySize: bodySize,
          onNavigate: onNavigate,
        );
    }
  }

  Widget _buildEditableHero(BuildContext context) {
    final editProvider = context.read<WebsiteEditModeProvider>();
    final theme = Theme.of(context);

    final title = (data['title'] ?? '').toString();
    final subtitle = (data['subtitle'] ?? '').toString();
    final ctaText = (data['buttonText'] ?? data['ctaText'] ?? 'Ver más').toString();
    final imageUrl = data['backgroundImage']?.toString();

    final headingStyle = (theme.textTheme.displayLarge ?? const TextStyle()).copyWith(
      fontFamily: headingFont?.isNotEmpty == true ? headingFont : null,
      fontSize: headingSize ?? 48,
      color: Colors.white,
    );

    final subtitleStyle = (theme.textTheme.headlineSmall ?? const TextStyle()).copyWith(
      fontFamily: bodyFont?.isNotEmpty == true ? bodyFont : null,
      fontSize: bodySize != null ? bodySize! * 1.2 : 20,
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
            onChanged: (url) => editProvider.updateBlockData(blockId, 'backgroundImage', url),
            placeholder: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryColor, accentColor.withValues(alpha: 0.85)],
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
                  // Editable title
                  InlineEditableText(
                    text: title,
                    style: headingStyle,
                    textAlign: TextAlign.center,
                    isEditMode: true,
                    placeholder: 'Título Principal',
                    onChanged: (value) => editProvider.updateBlockData(blockId, 'title', value),
                  ),

                  const SizedBox(height: 16),

                  // Editable subtitle
                  InlineEditableText(
                    text: subtitle,
                    style: subtitleStyle,
                    textAlign: TextAlign.center,
                    isEditMode: true,
                    placeholder: 'Subtítulo descriptivo',
                    onChanged: (value) => editProvider.updateBlockData(blockId, 'subtitle', value),
                  ),

                  const SizedBox(height: 32),

                  // Editable button
                  ElevatedButton(
                    onPressed: () {
                      // Show button edit dialog
                      _showButtonEditDialog(context, editProvider);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(ctaText.isEmpty ? 'Ver más' : ctaText),
                        const SizedBox(width: 8),
                        const Icon(Icons.edit, size: 16),
                      ],
                    ),
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

    final title = (data['title'] ?? '').toString();
    final description = (data['description'] ?? '').toString();
    final imageUrl = data['image']?.toString();

    final headingStyle = theme.textTheme.headlineMedium?.copyWith(
      fontFamily: headingFont?.isNotEmpty == true ? headingFont : null,
      fontWeight: FontWeight.bold,
    );

    final bodyStyle = theme.textTheme.bodyLarge?.copyWith(
      fontFamily: bodyFont?.isNotEmpty == true ? bodyFont : null,
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
              onChanged: (url) => editProvider.updateBlockData(blockId, 'image', url),
            ),
          ),

          const SizedBox(width: 48),

          // Text side
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InlineEditableText(
                  text: title,
                  style: headingStyle,
                  isEditMode: true,
                  placeholder: 'Sobre Nosotros',
                  onChanged: (value) => editProvider.updateBlockData(blockId, 'title', value),
                ),
                const SizedBox(height: 24),
                InlineEditableText(
                  text: description,
                  style: bodyStyle,
                  maxLines: 10,
                  isEditMode: true,
                  placeholder: 'Descripción de tu empresa...',
                  onChanged: (value) => editProvider.updateBlockData(blockId, 'description', value),
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

    final title = (data['title'] ?? '').toString();
    final description = (data['description'] ?? '').toString();
    final buttonText = (data['buttonText'] ?? 'Contactar').toString();

    final headingStyle = theme.textTheme.headlineMedium?.copyWith(
      fontFamily: headingFont?.isNotEmpty == true ? headingFont : null,
      fontWeight: FontWeight.bold,
      color: Colors.white,
    );

    final bodyStyle = theme.textTheme.bodyLarge?.copyWith(
      fontFamily: bodyFont?.isNotEmpty == true ? bodyFont : null,
      color: Colors.white70,
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryColor, accentColor],
        ),
      ),
      child: Column(
        children: [
          InlineEditableText(
            text: title,
            style: headingStyle,
            textAlign: TextAlign.center,
            isEditMode: true,
            placeholder: 'Llamado a la Acción',
            onChanged: (value) => editProvider.updateBlockData(blockId, 'title', value),
          ),
          const SizedBox(height: 16),
          InlineEditableText(
            text: description,
            style: bodyStyle,
            textAlign: TextAlign.center,
            isEditMode: true,
            placeholder: 'Descripción del llamado a la acción',
            onChanged: (value) => editProvider.updateBlockData(blockId, 'description', value),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => _showButtonEditDialog(context, editProvider),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(buttonText),
                const SizedBox(width: 8),
                const Icon(Icons.edit, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showButtonEditDialog(BuildContext context, WebsiteEditModeProvider editProvider) {
    final buttonTextController = TextEditingController(
      text: (data['buttonText'] ?? data['ctaText'] ?? '').toString(),
    );
    final buttonLinkController = TextEditingController(
      text: (data['buttonLink'] ?? data['ctaLink'] ?? '').toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Botón'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: buttonTextController,
              decoration: const InputDecoration(
                labelText: 'Texto del botón',
                hintText: 'Ver más',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: buttonLinkController,
              decoration: const InputDecoration(
                labelText: 'Enlace',
                hintText: '/tienda/productos',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              editProvider.updateBlockData(blockId, 'buttonText', buttonTextController.text);
              editProvider.updateBlockData(blockId, 'ctaText', buttonTextController.text);
              editProvider.updateBlockData(blockId, 'buttonLink', buttonLinkController.text);
              editProvider.updateBlockData(blockId, 'ctaLink', buttonLinkController.text);
              Navigator.pop(context);
            },
            child: const Text('Guardar'),
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
              editProvider.deleteBlock(blockId);
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
