import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/constants/storage_constants.dart';
import '../../../shared/services/tenant_service.dart';
import '../providers/website_edit_mode_provider.dart';
import '../models/website_page_models.dart';
import '../services/website_backup_service.dart';
import '../services/website_service.dart';
import 'block_resize_handle.dart';

/// Professional side panel editor for website blocks
/// Clean, functional, and elegant interface
class WebsiteEditorPanel extends StatefulWidget {
  final VoidCallback? onSave;
  final VoidCallback? onDiscard;

  const WebsiteEditorPanel({
    super.key,
    this.onSave,
    this.onDiscard,
  });

  @override
  State<WebsiteEditorPanel> createState() => _WebsiteEditorPanelState();
}

class _WebsiteEditorPanelState extends State<WebsiteEditorPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _activeTab = 'edit'; // 'add', 'edit', 'theme'
  String? _previousSelectedBlockId;
  String? _previousActiveElementId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void didUpdateWidget(WebsiteEditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-switch to Editar tab when a block is selected or canvas element changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final editProvider = context.read<WebsiteEditModeProvider>();
      final currentSelection = editProvider.selectedBlockId;

      // Check for Canvas element selection changes
      String? currentActiveElementId;
      if (currentSelection != null) {
        final blockData = editProvider.blocks.firstWhere(
          (b) => b['id'] == currentSelection,
          orElse: () => <String, dynamic>{},
        );
        currentActiveElementId =
            blockData['data']?['activeElementId']?.toString();
      }

      final blockChanged = currentSelection != null &&
          currentSelection != _previousSelectedBlockId;
      final elementChanged = currentActiveElementId != null &&
          currentActiveElementId != _previousActiveElementId;

      if (blockChanged || elementChanged) {
        setState(() {
          _activeTab = 'edit';
        });
      }
      _previousSelectedBlockId = currentSelection;
      _previousActiveElementId = currentActiveElementId;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editProvider = context.watch<WebsiteEditModeProvider>();

    if (!editProvider.isEditMode) {
      return const SizedBox.shrink();
    }

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        border: Border(
          left: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          _buildHeader(editProvider),
          _buildTabBar(),
          Expanded(
            child: _buildTabContent(editProvider),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(WebsiteEditModeProvider editProvider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          // Undo/Redo buttons
          Consumer<WebsiteEditModeProvider>(
            builder: (context, editProvider, _) => _buildIconButton(
              Icons.undo,
              'Deshacer',
              editProvider.canUndo ? () => editProvider.undo() : null,
            ),
          ),
          Consumer<WebsiteEditModeProvider>(
            builder: (context, editProvider, _) => _buildIconButton(
              Icons.redo,
              'Rehacer',
              editProvider.canRedo ? () => editProvider.redo() : null,
            ),
          ),
          // Backup button
          _buildIconButton(Icons.backup, 'Copias de seguridad',
              () => _showBackupsDialog(context)),
          // Preview button
          _buildIconButton(Icons.phone_android, 'Vista móvil', () {}),
          const Spacer(),
          // Discard button
          TextButton(
            onPressed: widget.onDiscard,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white70,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Descartar', style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 6),
          // Save button
          ElevatedButton(
            onPressed: editProvider.hasUnsavedChanges ? widget.onSave : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00A09D),
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  const Color(0xFF00A09D).withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4)),
            ),
            child: const Text('Guardar', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  void _showBackupsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => _BackupsDialog(
        onRestoreComplete: () {
          // Signal that restore happened - caller should reload
          widget.onSave?.call(); // Re-use save callback to trigger reload
        },
      ),
    );
  }

  Widget _buildIconButton(
      IconData icon, String tooltip, VoidCallback? onPressed) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            color: onPressed != null ? Colors.white70 : Colors.white30,
            size: 18,
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          _buildTab('add', '+ Agregar', Icons.add_box_outlined),
          _buildTab('edit', 'Editar', Icons.edit_outlined),
          _buildTab('style', 'Estilo', Icons.brush_outlined),
          _buildTab('theme', 'Tema', Icons.palette_outlined),
        ],
      ),
    );
  }

  Widget _buildTab(String id, String label, IconData icon) {
    final isActive = _activeTab == id;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _activeTab = id),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? const Color(0xFF00A09D) : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive ? const Color(0xFF00A09D) : Colors.white54,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.white54,
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent(WebsiteEditModeProvider editProvider) {
    switch (_activeTab) {
      case 'add':
        return _AddBlocksTab(editProvider: editProvider);
      case 'edit':
        return _EditBlockTab(editProvider: editProvider);
      case 'style':
        return _StyleBlockTab(editProvider: editProvider);
      case 'theme':
        return _ThemeTab();
      default:
        return const SizedBox.shrink();
    }
  }
}

/// Tab for adding new blocks - shows available block types in a grid
class _AddBlocksTab extends StatelessWidget {
  final WebsiteEditModeProvider editProvider;

  const _AddBlocksTab({required this.editProvider});

  @override
  Widget build(BuildContext context) {
    final blocks = editProvider.blocks;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // =========================
          // PAGE STRUCTURE (Wix-like)
          // =========================
          const Text(
            'ESTRUCTURA DE LA PÁGINA',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D2D),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: blocks.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Aún no hay bloques. Agrega uno desde abajo.',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  )
                : ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: blocks.length,
                    onReorder: (oldIndex, newIndex) =>
                        editProvider.reorderBlocks(oldIndex, newIndex),
                    itemBuilder: (context, index) {
                      final block = blocks[index];
                      final id = block['id']?.toString() ?? 'block_$index';
                      final type = (block['block_type'] ?? block['type'] ?? '')
                          .toString();
                      final isVisible = block['is_visible'] ?? true;
                      final isSelected = editProvider.selectedBlockId == id;

                      return Container(
                        key: ValueKey('structure_$id'),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF00A09D).withValues(alpha: 0.12)
                              : Colors.transparent,
                          border: Border(
                            bottom: BorderSide(
                              color: Colors.white.withValues(alpha: 0.06),
                            ),
                          ),
                        ),
                        child: InkWell(
                          onTap: () => editProvider.selectBlock(id),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 10),
                            child: Row(
                              children: [
                                ReorderableDragStartListener(
                                  index: index,
                                  child: const Icon(
                                    Icons.drag_handle,
                                    color: Colors.white38,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  _blockIcon(type),
                                  color: Colors.white70,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _blockLabel(type),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () =>
                                      editProvider.toggleBlockVisibility(id),
                                  icon: Icon(
                                    isVisible
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                    size: 18,
                                    color: isVisible
                                        ? Colors.white54
                                        : Colors.orange.shade300,
                                  ),
                                  tooltip: isVisible ? 'Ocultar' : 'Mostrar',
                                  constraints: const BoxConstraints(
                                      minWidth: 32, minHeight: 32),
                                  padding: EdgeInsets.zero,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 20),

          _buildSection('Estructura', [
            _BlockOption('hero', 'Hero', Icons.view_carousel_rounded),
            _BlockOption('carousel', 'Carrusel', Icons.view_array_rounded),
            _BlockOption('categoryGrid', 'Categorías', Icons.grid_view_rounded),
            _BlockOption(
                'canvas', 'Canvas', Icons.dashboard_customize_outlined),
          ]),
          _buildSection('Elementos', [
            _BlockOption('text', 'Texto', Icons.text_fields_rounded),
            _BlockOption('button', 'Botón', Icons.smart_button_rounded),
            _BlockOption('divider', 'Separador', Icons.horizontal_rule_rounded),
          ]),
          _buildSection('Canvas (arrastrable)', [
            _BlockOption('canvas_el:text', 'Texto', Icons.text_fields_rounded),
            _BlockOption(
                'canvas_el:button', 'Botón', Icons.smart_button_rounded),
            _BlockOption('canvas_el:image', 'Imagen', Icons.image_outlined),
            _BlockOption(
                'canvas_el:product', 'Producto', Icons.inventory_2_outlined),
            _BlockOption('canvas_el:productsGallery', 'Galería productos',
                Icons.grid_view_rounded),
          ]),
          _buildSection('Contenido', [
            _BlockOption('products', 'Productos', Icons.shopping_bag_rounded),
            _BlockOption('about', 'Nosotros', Icons.info_rounded),
            _BlockOption('services', 'Servicios', Icons.build_rounded),
            _BlockOption('features', 'Beneficios', Icons.star_rounded),
          ]),
          _buildSection('Media', [
            _BlockOption('gallery', 'Galería', Icons.photo_library_rounded),
            _BlockOption('videoBanner', 'Video Banner',
                Icons.play_circle_outline_rounded),
            _BlockOption(
                'brandLogos', 'Logos Marcas', Icons.branding_watermark_rounded),
            _BlockOption('partnersBanner', 'Partners', Icons.handshake_rounded),
          ]),
          _buildSection('Social', [
            _BlockOption(
                'testimonials', 'Testimonios', Icons.format_quote_rounded),
            _BlockOption('team', 'Equipo', Icons.groups_rounded),
            _BlockOption('stats', 'Estadísticas', Icons.analytics_rounded),
          ]),
          _buildSection('Conversión', [
            _BlockOption('cta', 'Call to Action', Icons.touch_app_rounded),
            _BlockOption('pricing', 'Precios', Icons.payments_rounded),
            _BlockOption('contact', 'Contacto', Icons.contact_mail_rounded),
            _BlockOption('faq', 'FAQ', Icons.help_outline_rounded),
          ]),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<_BlockOption> options) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 8),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((opt) => _buildBlockCard(opt)).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildBlockCard(_BlockOption option) {
    return Builder(
      builder: (context) => Draggable<String>(
        data: option.type,
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            width: 90,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF00A09D),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(option.icon, color: Colors.white, size: 24),
                const SizedBox(height: 6),
                Text(
                  option.label,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.4,
          child: _buildCardContent(option),
        ),
        onDragEnd: (details) {
          // Block will be added via drop target in main content area
        },
        child: GestureDetector(
          onTap: () {
            if (option.type.startsWith('canvas_el:')) {
              final elementType = option.type.replaceFirst('canvas_el:', '');
              final ok =
                  editProvider.addCanvasElementToSelectedCanvas(elementType);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ok
                      ? 'Elemento "$elementType" agregado al Canvas'
                      : 'Selecciona un bloque Canvas para agregar elementos'),
                  duration: const Duration(seconds: 2),
                  backgroundColor: ok ? const Color(0xFF00A09D) : Colors.orange,
                ),
              );
              return;
            }

            editProvider.addBlock(option.type);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Bloque "${option.label}" agregado'),
                duration: const Duration(seconds: 2),
                backgroundColor: const Color(0xFF00A09D),
              ),
            );
          },
          child: _buildCardContent(option),
        ),
      ),
    );
  }

  Widget _buildCardContent(_BlockOption option) {
    return Container(
      width: 90,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(option.icon, color: Colors.white70, size: 22),
          const SizedBox(height: 8),
          Text(
            option.label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  static IconData _blockIcon(String type) {
    switch (type) {
      case 'hero':
        return Icons.view_carousel_rounded;
      case 'carousel':
        return Icons.view_array_rounded;
      case 'products':
        return Icons.shopping_bag_rounded;
      case 'about':
        return Icons.info_rounded;
      case 'services':
        return Icons.build_rounded;
      case 'features':
        return Icons.star_rounded;
      case 'testimonials':
        return Icons.format_quote_rounded;
      case 'team':
        return Icons.groups_rounded;
      case 'stats':
        return Icons.analytics_rounded;
      case 'faq':
        return Icons.help_outline_rounded;
      case 'pricing':
        return Icons.payments_rounded;
      case 'contact':
        return Icons.contact_mail_rounded;
      case 'cta':
        return Icons.touch_app_rounded;
      case 'gallery':
        return Icons.photo_library_rounded;
      case 'categoryGrid':
        return Icons.grid_view_rounded;
      case 'videoBanner':
        return Icons.play_circle_outline_rounded;
      case 'partnersBanner':
        return Icons.handshake_rounded;
      case 'brandLogos':
        return Icons.branding_watermark_rounded;
      case 'canvas':
        return Icons.dashboard_customize_outlined;
      case 'text':
        return Icons.text_fields_rounded;
      case 'button':
        return Icons.smart_button_rounded;
      case 'divider':
        return Icons.horizontal_rule_rounded;
      default:
        return Icons.widgets_rounded;
    }
  }

  static String _blockLabel(String type) {
    switch (type) {
      case 'hero':
        return 'Hero / Banner';
      case 'carousel':
        return 'Carrusel';
      case 'categoryGrid':
        return 'Categorías';
      case 'canvas':
        return 'Canvas';
      case 'text':
        return 'Texto';
      case 'button':
        return 'Botón';
      case 'divider':
        return 'Separador';
      case 'products':
        return 'Productos';
      case 'about':
        return 'Nosotros';
      case 'services':
        return 'Servicios';
      case 'features':
        return 'Beneficios';
      case 'gallery':
        return 'Galería';
      case 'videoBanner':
        return 'Video Banner';
      case 'brandLogos':
        return 'Logos Marcas';
      case 'partnersBanner':
        return 'Partners';
      case 'testimonials':
        return 'Testimonios';
      case 'team':
        return 'Equipo';
      case 'stats':
        return 'Estadísticas';
      case 'cta':
        return 'Call to Action';
      case 'pricing':
        return 'Precios';
      case 'contact':
        return 'Contacto';
      case 'faq':
        return 'FAQ';
      default:
        return type;
    }
  }
}

class _BlockOption {
  final String type;
  final String label;
  final IconData icon;

  _BlockOption(this.type, this.label, this.icon);
}

/// Tab for editing selected block - shows controls based on block type
/// Also handles special elements: 'header' and 'footer'
class _EditBlockTab extends StatelessWidget {
  final WebsiteEditModeProvider editProvider;

  const _EditBlockTab({required this.editProvider});

  @override
  Widget build(BuildContext context) {
    final selectedId = editProvider.selectedBlockId;

    if (selectedId == null) {
      return _buildNoSelection();
    }

    // Handle special elements (header/footer) - these are not blocks
    // Use ValueKey to preserve state across rebuilds
    if (selectedId == 'header') {
      return _HeaderBlockControls(
          key: const ValueKey('header_controls'), provider: editProvider);
    }
    if (selectedId == 'footer') {
      return _FooterBlockControls(
          key: const ValueKey('footer_controls'), provider: editProvider);
    }

    final block = editProvider.getBlock(selectedId);
    if (block == null) {
      return _buildNoSelection();
    }

    final blockType = block['block_type']?.toString() ?? '';
    final blockData = Map<String, dynamic>.from(block['block_data'] ?? {});
    final isVisible = block['is_visible'] ?? true;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBlockHeader(blockType, isVisible, selectedId),
          const SizedBox(height: 16),
          _BlockHeightControl(
              data: blockData,
              blockId: selectedId,
              blockType: blockType,
              provider: editProvider),
          const SizedBox(height: 16),
          _BlockSpacingControl(
              data: blockData, blockId: selectedId, provider: editProvider),
          const SizedBox(height: 20),
          _buildBlockControls(blockType, blockData, selectedId),
        ],
      ),
    );
  }

  Widget _buildNoSelection() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.touch_app_outlined,
              size: 48,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Selecciona un bloque',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Haz clic en cualquier bloque de la página para editar sus propiedades',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockHeader(String blockType, bool isVisible, String blockId) {
    final typeNames = {
      'hero': 'Hero Banner',
      'carousel': 'Carrusel',
      'products': 'Productos',
      'about': 'Sobre Nosotros',
      'services': 'Servicios',
      'features': 'Características',
      'testimonials': 'Testimonios',
      'stats': 'Estadísticas',
      'team': 'Equipo',
      'faq': 'FAQ',
      'pricing': 'Precios',
      'contact': 'Contacto',
      'cta': 'Call to Action',
      'gallery': 'Galería',
    };

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF00A09D).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            _getBlockIcon(blockType),
            color: const Color(0xFF00A09D),
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                typeNames[blockType] ?? blockType,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                isVisible ? 'Visible' : 'Oculto',
                style: TextStyle(
                  color: isVisible ? const Color(0xFF00A09D) : Colors.orange,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        // Quick actions
        _QuickActionButton(
          icon: isVisible ? Icons.visibility : Icons.visibility_off,
          tooltip: isVisible ? 'Ocultar' : 'Mostrar',
          onPressed: () => editProvider.toggleBlockVisibility(blockId),
        ),
        _QuickActionButton(
          icon: Icons.content_copy,
          tooltip: 'Duplicar',
          onPressed: () => editProvider.duplicateBlock(blockId),
        ),
        _QuickActionButton(
          icon: Icons.delete_outline,
          tooltip: 'Eliminar',
          onPressed: () => editProvider.deleteBlock(blockId),
          isDestructive: true,
        ),
      ],
    );
  }

  IconData _getBlockIcon(String type) {
    return switch (type) {
      'hero' => Icons.view_carousel_rounded,
      'carousel' => Icons.view_array_rounded,
      'canvas' => Icons.dashboard_customize_outlined,
      'text' => Icons.text_fields_rounded,
      'button' => Icons.smart_button_rounded,
      'divider' => Icons.horizontal_rule_rounded,
      'products' => Icons.shopping_bag_rounded,
      'about' => Icons.info_rounded,
      'services' => Icons.build_rounded,
      'features' => Icons.star_rounded,
      'testimonials' => Icons.format_quote_rounded,
      'stats' => Icons.analytics_rounded,
      'team' => Icons.groups_rounded,
      'faq' => Icons.help_outline_rounded,
      'pricing' => Icons.payments_rounded,
      'contact' => Icons.contact_mail_rounded,
      'cta' => Icons.touch_app_rounded,
      'gallery' => Icons.photo_library_rounded,
      'categoryGrid' => Icons.grid_view_rounded,
      'videoBanner' => Icons.play_circle_outline_rounded,
      'partnersBanner' => Icons.handshake_rounded,
      'brandLogos' => Icons.branding_watermark_rounded,
      _ => Icons.widgets_rounded,
    };
  }

  Widget _buildBlockControls(
      String blockType, Map<String, dynamic> data, String blockId) {
    // Build controls based on block type
    switch (blockType) {
      case 'hero':
        return _HeroBlockControls(
            data: data, blockId: blockId, provider: editProvider);
      case 'carousel':
        return _CarouselBlockControls(
            data: data, blockId: blockId, provider: editProvider);
      case 'canvas':
        return _CanvasBlockControls(
            data: data, blockId: blockId, provider: editProvider);
      case 'text':
        return _TextBlockControls(
            data: data, blockId: blockId, provider: editProvider);
      case 'button':
        return _ButtonBlockControls(
            data: data, blockId: blockId, provider: editProvider);
      case 'divider':
        return _DividerBlockControls(
            data: data, blockId: blockId, provider: editProvider);
      case 'products':
        return _ProductsBlockControls(
            data: data, blockId: blockId, provider: editProvider);
      case 'about':
        return _AboutBlockControls(
            data: data, blockId: blockId, provider: editProvider);
      case 'cta':
        return _CtaBlockControls(
            data: data, blockId: blockId, provider: editProvider);
      case 'features':
        return _FeaturesBlockControls(
            data: data, blockId: blockId, provider: editProvider);
      case 'categoryGrid':
        return _CategoryGridBlockControls(
            data: data, blockId: blockId, provider: editProvider);
      case 'videoBanner':
        return _VideoBannerBlockControls(
            data: data, blockId: blockId, provider: editProvider);
      case 'partnersBanner':
        return _PartnersBannerBlockControls(
            data: data, blockId: blockId, provider: editProvider);
      case 'brandLogos':
        return _BrandLogosBlockControls(
            data: data, blockId: blockId, provider: editProvider);
      default:
        return _GenericBlockControls(
            data: data, blockId: blockId, provider: editProvider);
    }
  }
}

/// Block height control with presets and custom input
class _BlockHeightControl extends StatefulWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final String blockType;
  final WebsiteEditModeProvider provider;

  const _BlockHeightControl({
    required this.data,
    required this.blockId,
    required this.blockType,
    required this.provider,
  });

  @override
  State<_BlockHeightControl> createState() => _BlockHeightControlState();
}

class _BlockHeightControlState extends State<_BlockHeightControl> {
  late TextEditingController _customHeightController;
  bool _showCustomInput = false;

  @override
  void initState() {
    super.initState();
    final currentHeight = (widget.data['blockHeight'] as num?)?.toDouble();
    _customHeightController = TextEditingController(
      text: currentHeight?.toStringAsFixed(0) ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant _BlockHeightControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentHeight = (widget.data['blockHeight'] as num?)?.toDouble();
    if (currentHeight?.toStringAsFixed(0) != _customHeightController.text) {
      _customHeightController.text = currentHeight?.toStringAsFixed(0) ?? '';
    }
  }

  @override
  void dispose() {
    _customHeightController.dispose();
    super.dispose();
  }

  double? get _currentHeight =>
      (widget.data['blockHeight'] as num?)?.toDouble();

  void _setHeight(double? height) {
    widget.provider.updateBlockData(widget.blockId, 'blockHeight', height);
    if (height != null) {
      _customHeightController.text = height.toStringAsFixed(0);
    } else {
      _customHeightController.text = '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Altura',
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            if (_currentHeight != null)
              Text(
                '${_currentHeight!.toStringAsFixed(0)}px',
                style: const TextStyle(
                    color: Color(0xFF00A09D),
                    fontSize: 11,
                    fontWeight: FontWeight.w500),
              ),
          ],
        ),
        const SizedBox(height: 8),
        BlockHeightPresetSelector(
          blockType: widget.blockType,
          currentHeight: _currentHeight,
          onHeightChanged: _setHeight,
        ),
        const SizedBox(height: 8),
        // Custom height input toggle
        Row(
          children: [
            GestureDetector(
              onTap: () => setState(() => _showCustomInput = !_showCustomInput),
              child: Row(
                children: [
                  Icon(
                    _showCustomInput
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.white38,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Altura personalizada',
                    style: TextStyle(
                      color: _showCustomInput ? Colors.white70 : Colors.white38,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (_currentHeight != null)
              GestureDetector(
                onTap: () => _setHeight(null),
                child: const Text(
                  'Restablecer',
                  style: TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      decoration: TextDecoration.underline),
                ),
              ),
          ],
        ),
        if (_showCustomInput) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D2D2D),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: TextField(
                    controller: _customHeightController,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: 'ej: 450',
                      hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      isDense: true,
                    ),
                    onSubmitted: (value) {
                      final parsed = double.tryParse(value);
                      if (parsed != null && parsed >= 100) {
                        _setHeight(parsed);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  final parsed = double.tryParse(_customHeightController.text);
                  if (parsed != null && parsed >= 100) {
                    _setHeight(parsed);
                  }
                },
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00A09D),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Center(
                    child: Text(
                      'Aplicar',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'También puedes arrastrar el borde inferior del bloque',
            style: TextStyle(color: Colors.white24, fontSize: 9),
          ),
        ],
      ],
    );
  }
}

/// Control for spacing after a block (gap between blocks)
class _BlockSpacingControl extends StatefulWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _BlockSpacingControl({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  @override
  State<_BlockSpacingControl> createState() => _BlockSpacingControlState();
}

class _BlockSpacingControlState extends State<_BlockSpacingControl> {
  double get _currentSpacing =>
      (widget.data['spacingAfter'] as num?)?.toDouble() ?? 32.0;

  void _setSpacing(double spacing) {
    widget.provider.updateBlockData(widget.blockId, 'spacingAfter', spacing);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.height, color: Colors.white38, size: 14),
            const SizedBox(width: 6),
            const Text(
              'Espaciado inferior',
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Text(
              _currentSpacing == 0 ? '0' : '${_currentSpacing.toInt()}px',
              style: const TextStyle(
                  color: Color(0xFF00A09D),
                  fontSize: 11,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Preset buttons
        Row(
          children: [
            _SpacingPresetButton(
              label: '0',
              isSelected: _currentSpacing == 0,
              onTap: () => _setSpacing(0),
            ),
            const SizedBox(width: 6),
            _SpacingPresetButton(
              label: 'S',
              isSelected: _currentSpacing > 0 && _currentSpacing <= 16,
              onTap: () => _setSpacing(16),
            ),
            const SizedBox(width: 6),
            _SpacingPresetButton(
              label: 'M',
              isSelected: _currentSpacing > 16 && _currentSpacing <= 32,
              onTap: () => _setSpacing(32),
            ),
            const SizedBox(width: 6),
            _SpacingPresetButton(
              label: 'L',
              isSelected: _currentSpacing > 32 && _currentSpacing <= 64,
              onTap: () => _setSpacing(64),
            ),
            const SizedBox(width: 6),
            _SpacingPresetButton(
              label: 'XL',
              isSelected: _currentSpacing > 64,
              onTap: () => _setSpacing(96),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Slider
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: const Color(0xFF00A09D),
            inactiveTrackColor: Colors.white12,
            thumbColor: const Color(0xFF00A09D),
            overlayColor: const Color(0xFF00A09D).withValues(alpha: 0.2),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            trackHeight: 3,
          ),
          child: Slider(
            value: _currentSpacing.clamp(0, 200),
            min: 0,
            max: 200,
            divisions: 50,
            onChanged: (value) => _setSpacing(value.roundToDouble()),
          ),
        ),
        const Text(
          'También puedes arrastrar la línea entre bloques',
          style: TextStyle(color: Colors.white24, fontSize: 9),
        ),
      ],
    );
  }
}

class _SpacingPresetButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SpacingPresetButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 28,
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF00A09D)
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? const Color(0xFF00A09D) : Colors.white12,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isDestructive;

  const _QuickActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            color: isDestructive ? Colors.red.shade300 : Colors.white54,
            size: 18,
          ),
        ),
      ),
    );
  }
}

/// Hero block controls
class _HeroBlockControls extends StatelessWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _HeroBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditorTextField(
          label: 'Título',
          value: data['title']?.toString() ?? '',
          onChanged: (v) => provider.updateBlockData(blockId, 'title', v),
        ),
        const SizedBox(height: 16),
        _EditorTextField(
          label: 'Subtítulo',
          value: data['subtitle']?.toString() ?? '',
          onChanged: (v) => provider.updateBlockData(blockId, 'subtitle', v),
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        _EditorTextField(
          label: 'Texto del botón',
          value: data['buttonText']?.toString() ?? '',
          onChanged: (v) => provider.updateBlockData(blockId, 'buttonText', v),
        ),
        const SizedBox(height: 16),
        _LinkPicker(
          label: 'Enlace del botón',
          currentLink: data['buttonLink']?.toString() ?? '',
          onChanged: (v) => provider.updateBlockData(blockId, 'buttonLink', v),
        ),
        const SizedBox(height: 16),
        _EditorToggle(
          label: 'Pantalla Completa',
          value: data['isFullScreen'] == true,
          onChanged: (v) =>
              provider.updateBlockData(blockId, 'isFullScreen', v),
        ),
        const SizedBox(height: 16),
        _EditorDropdown(
          label: 'Alineación',
          value: data['alignment']?.toString() ?? 'center',
          options: const [
            ('left', 'Izquierda'),
            ('center', 'Centro'),
            ('right', 'Derecha'),
          ],
          onChanged: (v) => provider.updateBlockData(blockId, 'alignment', v),
        ),
        const SizedBox(height: 20),
        _SectionHeader('Imagen de fondo'),
        const SizedBox(height: 12),
        _ImagePicker(
          currentUrl: data['backgroundImage']?.toString(),
          onChanged: (url) =>
              provider.updateBlockData(blockId, 'backgroundImage', url),
        ),
      ],
    );
  }
}

/// Carousel block controls with slides management
class _CarouselBlockControls extends StatefulWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _CarouselBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  @override
  State<_CarouselBlockControls> createState() => _CarouselBlockControlsState();
}

class _CarouselBlockControlsState extends State<_CarouselBlockControls> {
  int _selectedSlideIndex = 0;

  List<Map<String, dynamic>> get _slides {
    final rawSlides = widget.data['slides'];
    if (rawSlides is List) {
      return rawSlides.map((s) => Map<String, dynamic>.from(s as Map)).toList();
    }
    return [];
  }

  void _updateSlides(List<Map<String, dynamic>> newSlides) {
    debugPrint(
        '🎠 [CarouselControls] _updateSlides: saving ${newSlides.length} slides to provider');
    debugPrint(
        '🎠 [CarouselControls] First slide data: ${newSlides.isNotEmpty ? newSlides[0] : "empty"}');
    widget.provider.updateBlockData(widget.blockId, 'slides', newSlides);
  }

  void _updateSlide(int index, String key, dynamic value) {
    debugPrint(
        '🎠🎠 [CarouselControls] _updateSlide CALLED: index=$index, key=$key, value=$value');
    final slides = List<Map<String, dynamic>>.from(_slides);
    if (index >= 0 && index < slides.length) {
      slides[index] = {...slides[index], key: value};
      debugPrint(
          '🎠 [CarouselControls] _updateSlide: index=$index, key=$key, value=$value');
      _updateSlides(slides);
    } else {
      debugPrint(
          '🎠⚠️ [CarouselControls] _updateSlide: INVALID INDEX index=$index, slides.length=${slides.length}');
    }
  }

  void _addSlide() {
    final slides = List<Map<String, dynamic>>.from(_slides);
    slides.add({
      'title': 'Nuevo Slide',
      'subtitle': 'Descripción del slide',
      'imageUrl': '',
      'ctaText': 'Ver más',
      'ctaLink': '/tienda/productos',
      'showOverlay': true,
      'overlayOpacity': 0.55,
    });
    _updateSlides(slides);
    setState(() => _selectedSlideIndex = slides.length - 1);
  }

  void _removeSlide(int index) {
    final slides = List<Map<String, dynamic>>.from(_slides);
    if (slides.length > 1 && index >= 0 && index < slides.length) {
      slides.removeAt(index);
      _updateSlides(slides);
      setState(() {
        if (_selectedSlideIndex >= slides.length) {
          _selectedSlideIndex = slides.length - 1;
        }
      });
    }
  }

  /// Build slide fields inline (same pattern as VideoBanner)
  Widget _buildSlideFields(Map<String, dynamic> slide) {
    final showOverlay = slide['showOverlay'] ?? true;
    final overlayOpacity =
        (slide['overlayOpacity'] as num?)?.toDouble() ?? 0.55;
    final hasVideoFile = (slide['videoFileUrl']?.toString() ?? '').isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditorTextField(
          label: 'Título',
          value: slide['title']?.toString() ?? '',
          onChanged: (v) => _updateSlide(_selectedSlideIndex, 'title', v),
        ),
        const SizedBox(height: 12),
        _EditorTextField(
          label: 'Subtítulo',
          value: slide['subtitle']?.toString() ?? '',
          onChanged: (v) => _updateSlide(_selectedSlideIndex, 'subtitle', v),
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        _EditorTextField(
          label: 'Texto del botón',
          value: slide['ctaText']?.toString() ?? '',
          onChanged: (v) => _updateSlide(_selectedSlideIndex, 'ctaText', v),
        ),
        const SizedBox(height: 12),
        _EditorTextField(
          label: 'Link del botón',
          value: slide['ctaLink']?.toString() ?? '',
          onChanged: (v) => _updateSlide(_selectedSlideIndex, 'ctaLink', v),
          hint: '/tienda/productos',
        ),
        const SizedBox(height: 20),

        // Image section
        _SectionHeader('IMAGEN DE FONDO'),
        const SizedBox(height: 8),
        _ImagePicker(
          currentUrl: slide['imageUrl']?.toString(),
          onChanged: (url) =>
              _updateSlide(_selectedSlideIndex, 'imageUrl', url),
        ),

        const SizedBox(height: 20),

        // Video section
        _SectionHeader('VIDEO DE FONDO (OPCIONAL)'),
        const SizedBox(height: 8),
        Text(
          'Si se configura un video, se usará en vez de la imagen',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
        const SizedBox(height: 12),

        // YouTube URL option - use _EditorTextField like the title field
        _EditorTextField(
          label: 'URL de YouTube',
          value: slide['videoUrl']?.toString() ?? '',
          onChanged: (v) {
            debugPrint('🎬 [CarouselSlide] YouTube URL changed: "$v"');
            _updateSlide(_selectedSlideIndex, 'videoUrl', v);
            // Clear file URL if entering YouTube URL
            if (v.isNotEmpty) {
              _updateSlide(_selectedSlideIndex, 'videoFileUrl', '');
            }
          },
          hint: 'https://youtube.com/watch?v=...',
        ),

        const SizedBox(height: 12),

        // Divider with "o"
        Row(
          children: [
            Expanded(child: Divider(color: Colors.white24)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('o',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
            ),
            Expanded(child: Divider(color: Colors.white24)),
          ],
        ),

        const SizedBox(height: 12),

        // Upload video file button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _uploadSlideVideoFile,
            icon: const Icon(Icons.upload_file, size: 18),
            label: const Text('Subir archivo de video'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00A09D),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),

        // Show current video file if exists
        if (hasVideoFile) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Archivo de video cargado',
                    style: TextStyle(color: Colors.green, fontSize: 12),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, size: 16, color: Colors.green),
                  onPressed: () =>
                      _updateSlide(_selectedSlideIndex, 'videoFileUrl', ''),
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),

        // Overlay settings
        _SectionHeader('OVERLAY'),
        const SizedBox(height: 8),
        _EditorToggle(
          label: 'Mostrar overlay oscuro',
          value: showOverlay,
          onChanged: (v) => _updateSlide(_selectedSlideIndex, 'showOverlay', v),
        ),
        if (showOverlay) ...[
          const SizedBox(height: 12),
          _EditorSlider(
            label: 'Opacidad del overlay',
            value: overlayOpacity,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            onChanged: (v) =>
                _updateSlide(_selectedSlideIndex, 'overlayOpacity', v),
          ),
        ],
      ],
    );
  }

  Future<void> _uploadSlideVideoFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error: No se pudo leer el archivo')),
          );
        }
        return;
      }

      // Get tenant ID
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Usuario no autenticado');

      final profileResponse = await Supabase.instance.client
          .from('user_profiles')
          .select('tenant_id')
          .eq('user_id', user.id)
          .single();

      final tenantId = profileResponse['tenant_id'] as String;

      // Upload to Supabase Storage
      final fileName =
          'video_${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final storagePath = '$tenantId/videos/$fileName';

      await Supabase.instance.client.storage
          .from('website-assets')
          .uploadBinary(storagePath, file.bytes!,
              fileOptions: FileOptions(
                contentType: file.extension == 'mp4'
                    ? 'video/mp4'
                    : 'video/${file.extension ?? 'mp4'}',
              ));

      // Get public URL
      final publicUrl = Supabase.instance.client.storage
          .from('website-assets')
          .getPublicUrl(storagePath);

      _updateSlide(_selectedSlideIndex, 'videoFileUrl', publicUrl);
      // Clear the YouTube URL if uploading a file
      _updateSlide(_selectedSlideIndex, 'videoUrl', '');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Video subido correctamente'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('[CarouselSlide] Error uploading video: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al subir video: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final slides = _slides;
    final autoPlay = widget.data['autoPlay'] ?? true;
    final intervalSeconds =
        (widget.data['intervalSeconds'] as num?)?.toInt() ?? 5;
    final showIndicators = widget.data['showIndicators'] ?? true;
    final showArrows = widget.data['showArrows'] ?? true;
    final animation = widget.data['animation']?.toString() ?? 'slide';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Carousel Settings Section
        _SectionHeader('Configuración'),
        const SizedBox(height: 12),
        _EditorToggle(
          label: 'Reproducción automática',
          value: autoPlay,
          onChanged: (v) =>
              widget.provider.updateBlockData(widget.blockId, 'autoPlay', v),
        ),
        const SizedBox(height: 12),
        if (autoPlay) ...[
          _EditorSlider(
            label: 'Intervalo (segundos)',
            value: intervalSeconds.toDouble(),
            min: 2,
            max: 15,
            divisions: 13,
            onChanged: (v) => widget.provider
                .updateBlockData(widget.blockId, 'intervalSeconds', v.toInt()),
          ),
          const SizedBox(height: 12),
        ],
        _EditorDropdown(
          label: 'Animación',
          value: animation,
          options: const [
            ('slide', 'Deslizar'),
            ('fade', 'Desvanecer'),
            ('zoom', 'Zoom'),
          ],
          onChanged: (v) =>
              widget.provider.updateBlockData(widget.blockId, 'animation', v),
        ),
        const SizedBox(height: 12),
        _EditorToggle(
          label: 'Mostrar indicadores',
          value: showIndicators,
          onChanged: (v) => widget.provider
              .updateBlockData(widget.blockId, 'showIndicators', v),
        ),
        const SizedBox(height: 12),
        _EditorToggle(
          label: 'Mostrar flechas',
          value: showArrows,
          onChanged: (v) =>
              widget.provider.updateBlockData(widget.blockId, 'showArrows', v),
        ),

        const SizedBox(height: 24),
        // Slides Section
        Row(
          children: [
            const Expanded(child: _SectionHeader('Slides')),
            InkWell(
              onTap: _addSlide,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00A09D).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 14, color: Color(0xFF00A09D)),
                    SizedBox(width: 4),
                    Text('Agregar',
                        style:
                            TextStyle(color: Color(0xFF00A09D), fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Slide tabs
        if (slides.isNotEmpty) ...[
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: slides.length,
              itemBuilder: (context, index) {
                final isSelected = index == _selectedSlideIndex;
                return GestureDetector(
                  onTap: () => setState(() => _selectedSlideIndex = index),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF00A09D)
                          : Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Slide ${index + 1}',
                          style: TextStyle(
                            color: isSelected ? Colors.white70 : Colors.white70,
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        if (slides.length > 1) ...[
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => _removeSlide(index),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color:
                                  isSelected ? Colors.white70 : Colors.white38,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // Selected slide editor - INLINE fields (not nested StatefulWidget)
          if (_selectedSlideIndex < slides.length)
            _buildSlideFields(slides[_selectedSlideIndex]),
        ] else
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.image_outlined,
                      size: 40, color: Colors.white.withValues(alpha: 0.3)),
                  const SizedBox(height: 12),
                  Text(
                    'No hay slides',
                    style:
                        TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _addSlide,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Agregar slide'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Individual slide editor - now supports video backgrounds
class _SlideEditor extends StatefulWidget {
  final Map<String, dynamic> slide;
  final void Function(String key, dynamic value) onUpdate;

  const _SlideEditor({
    required this.slide,
    required this.onUpdate,
  });

  @override
  State<_SlideEditor> createState() => _SlideEditorState();
}

class _SlideEditorState extends State<_SlideEditor> {
  bool _isUploading = false;

  Future<void> _uploadVideoFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error: No se pudo leer el archivo')),
          );
        }
        return;
      }

      setState(() => _isUploading = true);

      // Get tenant ID
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Usuario no autenticado');

      final profileResponse = await Supabase.instance.client
          .from('user_profiles')
          .select('tenant_id')
          .eq('user_id', user.id)
          .single();

      final tenantId = profileResponse['tenant_id'] as String;

      // Upload to Supabase Storage
      final fileName =
          'carousel_video_${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final storagePath = '$tenantId/videos/$fileName';

      await Supabase.instance.client.storage
          .from('website-assets')
          .uploadBinary(storagePath, file.bytes!,
              fileOptions: FileOptions(
                contentType: file.extension == 'mp4'
                    ? 'video/mp4'
                    : 'video/${file.extension ?? 'mp4'}',
              ));

      // Get public URL
      final publicUrl = Supabase.instance.client.storage
          .from('website-assets')
          .getPublicUrl(storagePath);

      widget.onUpdate('videoFileUrl', publicUrl);
      // Clear the YouTube URL if uploading a file
      widget.onUpdate('videoUrl', '');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Video subido correctamente'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('[SlideEditor] Error uploading video: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al subir video: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final showOverlay = widget.slide['showOverlay'] ?? true;
    final overlayOpacity =
        (widget.slide['overlayOpacity'] as num?)?.toDouble() ?? 0.55;
    final hasVideoFile =
        (widget.slide['videoFileUrl']?.toString() ?? '').isNotEmpty;
    final hasYoutubeUrl =
        (widget.slide['videoUrl']?.toString() ?? '').isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditorTextField(
          label: 'Título',
          value: widget.slide['title']?.toString() ?? '',
          onChanged: (v) => widget.onUpdate('title', v),
        ),
        const SizedBox(height: 12),
        _EditorTextField(
          label: 'Subtítulo',
          value: widget.slide['subtitle']?.toString() ?? '',
          onChanged: (v) => widget.onUpdate('subtitle', v),
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        _SectionHeader('Imagen de fondo'),
        const SizedBox(height: 8),
        _ImagePicker(
          currentUrl: widget.slide['imageUrl']?.toString(),
          onChanged: (url) => widget.onUpdate('imageUrl', url),
        ),

        const SizedBox(height: 20),
        // Video section
        Text('VIDEO DE FONDO (OPCIONAL)',
            style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1)),
        const SizedBox(height: 8),
        Text(
          'Si se configura un video, se usará en vez de la imagen',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
        const SizedBox(height: 12),

        // YouTube URL option
        _EditorTextField(
          label: 'URL de YouTube',
          value: widget.slide['videoUrl']?.toString() ?? '',
          onChanged: (v) {
            debugPrint('🎬 [SlideEditor] YouTube URL onChanged: "$v"');
            widget.onUpdate('videoUrl', v);
            // Clear file URL if entering YouTube URL
            if (v.isNotEmpty) {
              widget.onUpdate('videoFileUrl', '');
            }
          },
          hint: 'https://youtube.com/watch?v=...',
        ),

        const SizedBox(height: 12),

        // Divider with "o" (or)
        Row(
          children: [
            Expanded(child: Divider(color: Colors.white24)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('o',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
            ),
            Expanded(child: Divider(color: Colors.white24)),
          ],
        ),

        const SizedBox(height: 12),

        // Upload video file button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isUploading ? null : _uploadVideoFile,
            icon: _isUploading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.upload_file, size: 18),
            label:
                Text(_isUploading ? 'Subiendo...' : 'Subir archivo de video'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00A09D),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),

        // Show current video file if exists
        if (hasVideoFile) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Archivo de video cargado',
                    style: TextStyle(color: Colors.green, fontSize: 12),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: Colors.red.shade300, size: 18),
                  onPressed: () => widget.onUpdate('videoFileUrl', ''),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Eliminar video',
                ),
              ],
            ),
          ),
        ],

        // Show YouTube status if exists
        if (hasYoutubeUrl && !hasVideoFile) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.play_circle_filled, color: Colors.red, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Video de YouTube configurado',
                    style: TextStyle(color: Colors.red.shade200, fontSize: 12),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: Colors.red.shade300, size: 18),
                  onPressed: () => widget.onUpdate('videoUrl', ''),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Eliminar video',
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),
        _EditorToggle(
          label: 'Mostrar overlay oscuro',
          value: showOverlay,
          onChanged: (v) => widget.onUpdate('showOverlay', v),
        ),
        if (showOverlay) ...[
          const SizedBox(height: 12),
          _EditorSlider(
            label: 'Opacidad del overlay',
            value: overlayOpacity,
            min: 0.1,
            max: 0.9,
            divisions: 8,
            onChanged: (v) => widget.onUpdate('overlayOpacity', v),
          ),
        ],
        const SizedBox(height: 16),
        _SectionHeader('Botón'),
        const SizedBox(height: 8),
        _EditorTextField(
          label: 'Texto del botón',
          value: widget.slide['ctaText']?.toString() ?? '',
          onChanged: (v) => widget.onUpdate('ctaText', v),
        ),
        const SizedBox(height: 12),
        _EditorTextField(
          label: 'Enlace',
          value: widget.slide['ctaLink']?.toString() ?? '',
          onChanged: (v) => widget.onUpdate('ctaLink', v),
          hint: '/tienda/productos',
        ),
      ],
    );
  }
}

/// Products block controls - Enhanced with product selection, layout, and display options
class _ProductsBlockControls extends StatefulWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _ProductsBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  @override
  State<_ProductsBlockControls> createState() => _ProductsBlockControlsState();
}

class _ProductsBlockControlsState extends State<_ProductsBlockControls> {
  List<Map<String, dynamic>> _availableProducts = [];
  List<Map<String, dynamic>> _availableCategories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final supabase = Supabase.instance.client;

      // Load ALL active products (so user can see/deselect old selections)
      // We'll mark unavailable ones in the picker UI
      final productsResponse = await supabase
          .from('products')
          .select(
              'id, name, sku, price, image_url, category_id, is_active, is_published, stock_quantity')
          .eq('is_active', true)
          .order('name', ascending: true);

      var allProducts = List<Map<String, dynamic>>.from(productsResponse);

      // Also load selected products that might be inactive (so we can display/deselect them)
      final selectedIds = _selectedProductIds;
      if (selectedIds.isNotEmpty) {
        final selectedResponse = await supabase
            .from('products')
            .select(
                'id, name, sku, price, image_url, category_id, is_active, is_published, stock_quantity')
            .inFilter('id', selectedIds);

        // Add any selected products not already in the list
        for (final selected in selectedResponse) {
          final exists = allProducts
              .any((p) => p['id'].toString() == selected['id'].toString());
          if (!exists) {
            allProducts.add(Map<String, dynamic>.from(selected));
          }
        }
      }

      // Load categories
      final categoriesResponse = await supabase
          .from('product_categories')
          .select('id, name')
          .order('name', ascending: true);

      if (mounted) {
        setState(() {
          _availableProducts = allProducts;
          _availableCategories =
              List<Map<String, dynamic>>.from(categoriesResponse);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading products: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _updateField(String field, dynamic value) {
    widget.provider.updateBlockData(widget.blockId, field, value);
  }

  List<String> get _selectedProductIds {
    final raw = widget.data['selectedProducts'];
    if (raw is List) return raw.cast<String>();
    return [];
  }

  String get _productSource =>
      widget.data['productSource']?.toString() ?? 'featured';
  String? get _selectedCategoryId => widget.data['categoryId']?.toString();
  int get _itemsPerRow => (widget.data['itemsPerRow'] as num?)?.toInt() ?? 3;
  int get _maxProducts => (widget.data['maxProducts'] as num?)?.toInt() ?? 8;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditorTextField(
          label: 'Título de sección',
          value: widget.data['title']?.toString() ?? '',
          onChanged: (v) => _updateField('title', v),
        ),
        const SizedBox(height: 12),
        _EditorTextField(
          label: 'Subtítulo',
          value: widget.data['subtitle']?.toString() ?? '',
          onChanged: (v) => _updateField('subtitle', v),
        ),

        const SizedBox(height: 20),
        _SectionHeader('FUENTE DE PRODUCTOS'),
        const SizedBox(height: 12),

        // Product source selector
        _buildSourceSelector(),

        const SizedBox(height: 16),

        // Conditional content based on source
        if (_productSource == 'category') _buildCategorySelector(),
        if (_productSource == 'manual') _buildProductSelector(),

        const SizedBox(height: 20),
        const SizedBox(height: 20),
        _SectionHeader('DISEÑO'),
        const SizedBox(height: 12),
        _EditorDropdown(
          label: 'Diseño',
          value: widget.data['layout']?.toString() ?? 'grid',
          options: const [
            ('grid', 'Cuadrícula'),
            ('carousel', 'Carrusel'),
          ],
          onChanged: (v) => _updateField('layout', v),
        ),
        const SizedBox(height: 12),

        // Items per row
        Text('Productos por fila',
            style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: [2, 3, 4].map((count) {
            final isSelected = _itemsPerRow == count;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => _updateField('itemsPerRow', count),
                child: Container(
                  width: 44,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF00A09D)
                        : const Color(0xFF2D2D2D),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color:
                          isSelected ? const Color(0xFF00A09D) : Colors.white24,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$count',
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 16),
        _EditorSlider(
          label: 'Máximo de productos',
          value: _maxProducts.toDouble(),
          min: 4,
          max: 16,
          divisions: 6,
          onChanged: (v) => _updateField('maxProducts', v.toInt()),
        ),

        const SizedBox(height: 20),
        _SectionHeader('MOSTRAR'),
        const SizedBox(height: 12),

        _EditorToggle(
          label: 'Mostrar precios',
          value: widget.data['showPrice'] ?? true,
          onChanged: (v) => _updateField('showPrice', v),
        ),
        const SizedBox(height: 8),
        _EditorToggle(
          label: 'Mostrar botón "Ver todos"',
          value: widget.data['showViewAll'] ?? true,
          onChanged: (v) => _updateField('showViewAll', v),
        ),
        const SizedBox(height: 8),
        _EditorToggle(
          label: 'Mostrar SKU',
          value: widget.data['showSku'] ?? false,
          onChanged: (v) => _updateField('showSku', v),
        ),
        const SizedBox(height: 8),
        _EditorToggle(
          label: 'Mostrar marca',
          value: widget.data['showBrand'] ?? false,
          onChanged: (v) => _updateField('showBrand', v),
        ),

        // View all link
        if (widget.data['showViewAll'] != false) ...[
          const SizedBox(height: 16),
          _EditorTextField(
            label: 'Link "Ver todos"',
            value:
                widget.data['viewAllLink']?.toString() ?? '/tienda/productos',
            onChanged: (v) => _updateField('viewAllLink', v),
          ),
        ],
      ],
    );
  }

  Widget _buildSourceSelector() {
    final sources = [
      {'id': 'featured', 'label': 'Destacados', 'icon': Icons.star},
      {'id': 'category', 'label': 'Categoría', 'icon': Icons.category},
      {'id': 'manual', 'label': 'Selección manual', 'icon': Icons.checklist},
      {'id': 'newest', 'label': 'Más recientes', 'icon': Icons.schedule},
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: sources.map((source) {
        final isSelected = _productSource == source['id'];
        return GestureDetector(
          onTap: () => _updateField('productSource', source['id']),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF00A09D)
                  : const Color(0xFF2D2D2D),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected ? const Color(0xFF00A09D) : Colors.white24,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  source['icon'] as IconData,
                  size: 14,
                  color: isSelected ? Colors.white : Colors.white54,
                ),
                const SizedBox(width: 6),
                Text(
                  source['label'] as String,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCategorySelector() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text('Seleccionar categoría',
            style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(4),
          ),
          child: MenuAnchor(
            style: MenuStyle(
              backgroundColor: WidgetStateProperty.all(const Color(0xFF2D2D2D)),
              surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
              padding: WidgetStateProperty.all(EdgeInsets.zero),
            ),
            menuChildren: _availableCategories.map((cat) {
              final catId = cat['id'].toString();
              return MenuItemButton(
                onPressed: () => _updateField('categoryId', catId),
                style: ButtonStyle(
                  backgroundColor: _selectedCategoryId == catId
                      ? WidgetStateProperty.all(
                          Colors.white.withValues(alpha: 0.1))
                      : null,
                  foregroundColor: WidgetStateProperty.all(Colors.white),
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 120),
                  child: Text(
                    cat['name']?.toString() ?? 'Sin nombre',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              );
            }).toList(),
            builder: (context, controller, child) {
              final selectedName = _availableCategories
                      .firstWhere(
                        (c) => c['id'].toString() == _selectedCategoryId,
                        orElse: () => {},
                      )['name']
                      ?.toString() ??
                  'Seleccionar...';

              return InkWell(
                onTap: () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          selectedName,
                          style: TextStyle(
                            color: _selectedCategoryId == null
                                ? Colors.white54
                                : Colors.white,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.expand_more,
                          color: Colors.white54, size: 20),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProductSelector() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              'Productos seleccionados (${_selectedProductIds.length})',
              style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => _showProductPicker(context),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF00A09D),
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Agregar', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_selectedProductIds.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D2D),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white12),
            ),
            child: const Center(
              child: Text(
                'No hay productos seleccionados\nToca "Agregar" para elegir productos',
                style: TextStyle(color: Colors.white38, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ...(_selectedProductIds.map((productId) {
            final product = _availableProducts.firstWhere(
              (p) => p['id'].toString() == productId,
              orElse: () => <String, dynamic>{},
            );
            if (product.isEmpty) return const SizedBox.shrink();

            final isActive = product['is_active'] == true;
            final isPublished = product['is_published'] == true;
            final stockQty = (product['inventory_qty'] as num?)?.toInt() ??
                (product['stock_quantity'] as num?)?.toInt() ??
                0;
            final isAvailable = isActive && isPublished && stockQty > 0;
            final statusText = !isActive
                ? 'Inactivo'
                : stockQty <= 0
                    ? 'Sin stock'
                    : !isPublished
                        ? 'No publicado'
                        : null;

            return Opacity(
              opacity: isAvailable ? 1.0 : 0.6,
              child: Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2D2D),
                  borderRadius: BorderRadius.circular(4),
                  border: !isAvailable
                      ? Border.all(color: Colors.red.withValues(alpha: 0.3))
                      : null,
                ),
                child: Row(
                  children: [
                    // Product image
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3D3D3D),
                        borderRadius: BorderRadius.circular(4),
                        image: product['image_url'] != null
                            ? DecorationImage(
                                image: NetworkImage(product['image_url']),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: product['image_url'] == null
                          ? const Icon(Icons.image,
                              size: 16, color: Colors.white24)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  product['name']?.toString() ?? '',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (statusText != null)
                                Container(
                                  margin: const EdgeInsets.only(left: 4),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                  child: Text(
                                    statusText,
                                    style: const TextStyle(
                                        color: Colors.red, fontSize: 8),
                                  ),
                                ),
                            ],
                          ),
                          Text(
                            product['sku']?.toString() ?? '',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      color: Colors.white38,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        final newList = List<String>.from(_selectedProductIds)
                          ..remove(productId);
                        _updateField('selectedProducts', newList);
                      },
                    ),
                  ],
                ),
              ),
            );
          })),
      ],
    );
  }

  void _showProductPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _ProductPickerDialog(
        availableProducts: _availableProducts,
        selectedIds: _selectedProductIds,
        onConfirm: (selectedIds) {
          _updateField('selectedProducts', selectedIds);
        },
      ),
    );
  }
}

class _SelectedProductRow extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onRemove;

  const _SelectedProductRow({
    required this.product,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = product['is_active'] == true;
    final isPublished = product['is_published'] == true;
    final stockQty = (product['inventory_qty'] as num?)?.toInt() ??
        (product['stock_quantity'] as num?)?.toInt() ??
        0;
    final isAvailable = isActive && isPublished && stockQty > 0;
    final statusText = !isActive
        ? 'Inactivo'
        : stockQty <= 0
            ? 'Sin stock'
            : !isPublished
                ? 'No publicado'
                : null;

    return Opacity(
      opacity: isAvailable ? 1.0 : 0.6,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(4),
          border: !isAvailable
              ? Border.all(color: Colors.red.withValues(alpha: 0.3))
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF3D3D3D),
                borderRadius: BorderRadius.circular(4),
                image: product['image_url'] != null
                    ? DecorationImage(
                        image: NetworkImage(product['image_url']),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: product['image_url'] == null
                  ? const Icon(Icons.image, size: 16, color: Colors.white24)
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          product['name']?.toString() ?? '',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (statusText != null)
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(
                            statusText,
                            style:
                                const TextStyle(color: Colors.red, fontSize: 8),
                          ),
                        ),
                    ],
                  ),
                  Text(
                    product['sku']?.toString() ?? '',
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              color: Colors.white38,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

/// Product picker dialog
class _ProductPickerDialog extends StatefulWidget {
  final List<Map<String, dynamic>> availableProducts;
  final List<String> selectedIds;
  final Function(List<String>) onConfirm;

  const _ProductPickerDialog({
    required this.availableProducts,
    required this.selectedIds,
    required this.onConfirm,
  });

  @override
  State<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<_ProductPickerDialog> {
  late Set<String> _selected;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.selectedIds);
  }

  List<Map<String, dynamic>> get _filteredProducts {
    if (_searchQuery.isEmpty) return widget.availableProducts;
    final query = _searchQuery.toLowerCase();
    return widget.availableProducts.where((p) {
      final name = (p['name']?.toString() ?? '').toLowerCase();
      final sku = (p['sku']?.toString() ?? '').toLowerCase();
      return name.contains(query) || sku.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        width: 400,
        height: 500,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Seleccionar productos',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Search field
            TextField(
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o SKU...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                prefixIcon:
                    const Icon(Icons.search, color: Colors.white38, size: 20),
                filled: true,
                fillColor: const Color(0xFF2D2D2D),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '${_selected.length} seleccionados',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const Spacer(),
                Text(
                  '${_filteredProducts.length} productos',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _filteredProducts.length,
                itemBuilder: (context, index) {
                  final product = _filteredProducts[index];
                  final productId = product['id'].toString();
                  final isSelected = _selected.contains(productId);
                  final isPublished = product['is_published'] == true;
                  final stockQty =
                      (product['inventory_qty'] as num?)?.toInt() ??
                          (product['stock_quantity'] as num?)?.toInt() ??
                          0;
                  final isAvailable = isPublished && stockQty > 0;

                  return InkWell(
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selected.remove(productId);
                        } else {
                          _selected.add(productId);
                        }
                      });
                    },
                    child: Opacity(
                      opacity: isAvailable ? 1.0 : 0.5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF00A09D).withValues(alpha: 0.2)
                              : Colors.transparent,
                          border: Border(
                            bottom: BorderSide(
                                color: Colors.white.withValues(alpha: 0.05)),
                          ),
                        ),
                        child: Row(
                          children: [
                            // Checkbox
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF00A09D)
                                    : const Color(0xFF2D2D2D),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF00A09D)
                                      : Colors.white24,
                                ),
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check,
                                      size: 14, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            // Image
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFF3D3D3D),
                                borderRadius: BorderRadius.circular(4),
                                image: product['image_url'] != null
                                    ? DecorationImage(
                                        image:
                                            NetworkImage(product['image_url']),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: product['image_url'] == null
                                  ? const Icon(Icons.image,
                                      size: 20, color: Colors.white24)
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            // Details
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          product['name']?.toString() ?? '',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (!isAvailable)
                                        Container(
                                          margin:
                                              const EdgeInsets.only(left: 4),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 4, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: Colors.red
                                                .withValues(alpha: 0.2),
                                            borderRadius:
                                                BorderRadius.circular(2),
                                          ),
                                          child: Text(
                                            stockQty <= 0
                                                ? 'Sin stock'
                                                : 'No publicado',
                                            style: const TextStyle(
                                                color: Colors.red, fontSize: 9),
                                          ),
                                        ),
                                    ],
                                  ),
                                  Text(
                                    'SKU: ${product['sku'] ?? '-'} · \$${NumberFormat('#,###', 'es_CL').format(product['price'] ?? 0)}',
                                    style: const TextStyle(
                                        color: Colors.white38, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(foregroundColor: Colors.white54),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    widget.onConfirm(_selected.toList());
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00A09D),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Confirmar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// About block controls
class _AboutBlockControls extends StatelessWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _AboutBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditorTextField(
          label: 'Título',
          value: data['title']?.toString() ?? '',
          onChanged: (v) => provider.updateBlockData(blockId, 'title', v),
        ),
        const SizedBox(height: 16),
        _EditorTextField(
          label: 'Descripción',
          value: data['description']?.toString() ?? '',
          onChanged: (v) => provider.updateBlockData(blockId, 'description', v),
          maxLines: 5,
        ),
        const SizedBox(height: 20),
        _SectionHeader('Imagen'),
        const SizedBox(height: 12),
        _ImagePicker(
          currentUrl: data['image']?.toString(),
          onChanged: (url) => provider.updateBlockData(blockId, 'image', url),
        ),
      ],
    );
  }
}

/// CTA block controls
class _CtaBlockControls extends StatelessWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _CtaBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditorTextField(
          label: 'Título',
          value: data['title']?.toString() ?? '',
          onChanged: (v) => provider.updateBlockData(blockId, 'title', v),
        ),
        const SizedBox(height: 16),
        _EditorTextField(
          label: 'Descripción',
          value: data['description']?.toString() ?? '',
          onChanged: (v) => provider.updateBlockData(blockId, 'description', v),
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        _EditorTextField(
          label: 'Texto del botón',
          value: data['buttonText']?.toString() ?? '',
          onChanged: (v) => provider.updateBlockData(blockId, 'buttonText', v),
        ),
        const SizedBox(height: 16),
        _LinkPicker(
          label: 'Enlace',
          currentLink: data['buttonLink']?.toString() ?? '',
          onChanged: (v) => provider.updateBlockData(blockId, 'buttonLink', v),
        ),
      ],
    );
  }
}

/// Features block controls
class _FeaturesBlockControls extends StatelessWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _FeaturesBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    final features =
        (data['features'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditorTextField(
          label: 'Título',
          value: data['title']?.toString() ?? '',
          onChanged: (v) => provider.updateBlockData(blockId, 'title', v),
        ),
        const SizedBox(height: 20),
        _EditorDropdown(
          label: 'Diseño',
          value: data['layout']?.toString() ?? 'grid',
          options: const [
            ('grid', 'Cuadrícula'),
            ('list', 'Lista'),
          ],
          onChanged: (v) => provider.updateBlockData(blockId, 'layout', v),
        ),
        const SizedBox(height: 20),
        _SectionHeader('Características (${features.length})'),
        const SizedBox(height: 12),
        ...features.asMap().entries.map((entry) {
          final i = entry.key;
          final feature = entry.value;
          return _FeatureItem(
            index: i,
            feature: feature,
            onUpdate: (updated) {
              final newFeatures = List<Map<String, dynamic>>.from(features);
              newFeatures[i] = updated;
              provider.updateBlockData(blockId, 'features', newFeatures);
            },
            onDelete: () {
              final newFeatures = List<Map<String, dynamic>>.from(features);
              newFeatures.removeAt(i);
              provider.updateBlockData(blockId, 'features', newFeatures);
            },
          );
        }),
        const SizedBox(height: 12),
        _AddItemButton(
          label: 'Agregar característica',
          onPressed: () {
            final newFeatures = List<Map<String, dynamic>>.from(features);
            newFeatures.add({
              'icon': 'star',
              'title': 'Nueva característica',
              'description': 'Descripción...',
            });
            provider.updateBlockData(blockId, 'features', newFeatures);
          },
        ),
      ],
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final int index;
  final Map<String, dynamic> feature;
  final Function(Map<String, dynamic>) onUpdate;
  final VoidCallback onDelete;

  const _FeatureItem({
    required this.index,
    required this.feature,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                '#${index + 1}',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
              ),
              const Spacer(),
              InkWell(
                onTap: onDelete,
                child: Icon(Icons.close, size: 16, color: Colors.red.shade300),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _MiniTextField(
            value: feature['title']?.toString() ?? '',
            hint: 'Título',
            onChanged: (v) => onUpdate({...feature, 'title': v}),
          ),
          const SizedBox(height: 8),
          _MiniTextField(
            value: feature['description']?.toString() ?? '',
            hint: 'Descripción',
            onChanged: (v) => onUpdate({...feature, 'description': v}),
          ),
        ],
      ),
    );
  }
}

/// Generic block controls for types without specific UI
class _GenericBlockControls extends StatelessWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _GenericBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    // Show title and subtitle if they exist
    final hasTitle = data.containsKey('title');
    final hasSubtitle = data.containsKey('subtitle');
    final hasDescription = data.containsKey('description');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasTitle) ...[
          _EditorTextField(
            label: 'Título',
            value: data['title']?.toString() ?? '',
            onChanged: (v) => provider.updateBlockData(blockId, 'title', v),
          ),
          const SizedBox(height: 16),
        ],
        if (hasSubtitle) ...[
          _EditorTextField(
            label: 'Subtítulo',
            value: data['subtitle']?.toString() ?? '',
            onChanged: (v) => provider.updateBlockData(blockId, 'subtitle', v),
          ),
          const SizedBox(height: 16),
        ],
        if (hasDescription) ...[
          _EditorTextField(
            label: 'Descripción',
            value: data['description']?.toString() ?? '',
            onChanged: (v) =>
                provider.updateBlockData(blockId, 'description', v),
            maxLines: 3,
          ),
        ],
        if (!hasTitle && !hasSubtitle && !hasDescription)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Edición avanzada disponible próximamente',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              ),
            ),
          ),
      ],
    );
  }
}

/// Controls for simple Text block (inline-edit on canvas + fallback editing here).
class _TextBlockControls extends StatelessWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _TextBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    final preset = (data['preset'] ?? 'paragraph').toString();
    final maxWidth = (data['maxWidth'] as num?)?.toDouble() ?? 800.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('Texto'),
        const SizedBox(height: 12),
        _EditorTextField(
          label: 'Texto (también se edita haciendo clic en la página)',
          value: data['text']?.toString() ?? '',
          onChanged: (v) => provider.updateBlockData(blockId, 'text', v),
          maxLines: 4,
        ),
        const SizedBox(height: 16),
        _EditorDropdown(
          label: 'Preset',
          value: preset,
          options: const [
            ('heading', 'Título'),
            ('subheading', 'Subtítulo'),
            ('paragraph', 'Párrafo'),
            ('caption', 'Texto pequeño'),
          ],
          onChanged: (v) => provider.updateBlockData(blockId, 'preset', v),
        ),
        const SizedBox(height: 16),
        _EditorSlider(
          label: 'Ancho máximo',
          value: maxWidth.clamp(200, 1200),
          min: 200,
          max: 1200,
          divisions: 50,
          valueLabel: '${maxWidth.toStringAsFixed(0)}px',
          onChanged: (v) => provider.updateBlockData(blockId, 'maxWidth', v),
        ),
        const SizedBox(height: 8),
        Text(
          'Tip: usa la barra flotante de formato (negrita, color, alineación) sobre el texto.',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
        ),
      ],
    );
  }
}

/// Controls for Button block (inline label + link picker).
class _ButtonBlockControls extends StatelessWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _ButtonBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    final style = (data['style'] ?? 'filled').toString();
    final link = (data['link'] ?? '').toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('Botón'),
        const SizedBox(height: 12),
        _EditorTextField(
          label: 'Texto del botón',
          value: data['label']?.toString() ?? '',
          onChanged: (v) => provider.updateBlockData(blockId, 'label', v),
        ),
        const SizedBox(height: 12),
        _EditorTextField(
          label: 'Enlace',
          value: link,
          onChanged: (v) => provider.updateBlockData(blockId, 'link', v),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickPage(context),
                icon: const Icon(Icons.article_outlined, size: 16),
                label: const Text('Elegir página'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickCommonLink(context),
                icon: const Icon(Icons.link, size: 16),
                label: const Text('Enlaces rápidos'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _EditorDropdown(
          label: 'Estilo',
          value: style,
          options: const [
            ('filled', 'Relleno'),
            ('outline', 'Borde'),
            ('text', 'Texto'),
          ],
          onChanged: (v) => provider.updateBlockData(blockId, 'style', v),
        ),
      ],
    );
  }

  Future<void> _pickPage(BuildContext context) async {
    final websiteService = context.read<WebsiteService>();
    try {
      if (websiteService.pages.isEmpty) {
        await websiteService.loadPages();
      }
    } catch (_) {
      // If load fails (e.g., in public store without ERP auth), we'll still show whatever we have.
    }

    final pages = websiteService.pages;
    if (!context.mounted) return;

    final selected = await showDialog<WebsitePage>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elegir página'),
        content: SizedBox(
          width: 420,
          height: 520,
          child: ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('Inicio'),
                subtitle: const Text('/'),
                onTap: () => Navigator.pop(
                  context,
                  WebsitePage(
                    id: '',
                    tenantId: '',
                    slug: '',
                    title: 'Inicio',
                    isHome: true,
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  ),
                ),
              ),
              const Divider(),
              ...pages.map((page) {
                return ListTile(
                  leading:
                      Icon(page.isHome ? Icons.home : Icons.article_outlined),
                  title: Text(page.title),
                  subtitle: Text(page.isHome ? '/' : '/pagina/${page.slug}'),
                  onTap: () => Navigator.pop(context, page),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

    if (selected == null) return;
    final nextLink = selected.isHome ? '/' : '/pagina/${selected.slug}';
    provider.updateBlockData(blockId, 'link', nextLink);
  }

  Future<void> _pickCommonLink(BuildContext context) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enlaces rápidos'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.shopping_bag_outlined),
                title: const Text('Productos'),
                subtitle: const Text('/productos'),
                onTap: () => Navigator.pop(context, '/productos'),
              ),
              ListTile(
                leading: const Icon(Icons.contact_mail_outlined),
                title: const Text('Contacto'),
                subtitle: const Text('/contacto'),
                onTap: () => Navigator.pop(context, '/contacto'),
              ),
              ListTile(
                leading: const Icon(Icons.shopping_cart_outlined),
                title: const Text('Carrito'),
                subtitle: const Text('/carrito'),
                onTap: () => Navigator.pop(context, '/carrito'),
              ),
              ListTile(
                leading: const Icon(Icons.payment_outlined),
                title: const Text('Checkout'),
                subtitle: const Text('/checkout'),
                onTap: () => Navigator.pop(context, '/checkout'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (selected == null) return;
    provider.updateBlockData(blockId, 'link', selected);
  }
}

/// Controls for Divider / Separator block.
class _DividerBlockControls extends StatelessWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _DividerBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    final thickness = (data['thickness'] as num?)?.toDouble() ?? 1.0;
    final color = (data['color'] ?? '#E0E0E0').toString();
    final widthPct = (data['widthPct'] as num?)?.toDouble() ?? 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('Separador'),
        const SizedBox(height: 12),
        _EditorSlider(
          label: 'Grosor',
          value: thickness.clamp(1, 12),
          min: 1,
          max: 12,
          divisions: 11,
          valueLabel: '${thickness.toStringAsFixed(0)}px',
          onChanged: (v) => provider.updateBlockData(blockId, 'thickness', v),
        ),
        const SizedBox(height: 12),
        _EditorTextField(
          label: 'Color (hex)',
          value: color,
          onChanged: (v) => provider.updateBlockData(blockId, 'color', v),
        ),
        const SizedBox(height: 12),
        _EditorSlider(
          label: 'Ancho',
          value: widthPct.clamp(0.1, 1.0),
          min: 0.1,
          max: 1.0,
          divisions: 9,
          valueLabel: '${(widthPct * 100).toStringAsFixed(0)}%',
          onChanged: (v) => provider.updateBlockData(blockId, 'widthPct', v),
        ),
      ],
    );
  }
}

/// Controls for the free-position Canvas block (Wix-like).
class _CanvasBlockControls extends StatelessWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _CanvasBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  List<Map<String, dynamic>> _elements() {
    final raw = data['elements'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  String? _activeElementId() {
    final raw = data['activeElementId'];
    final id = raw?.toString();
    if (id == null || id.trim().isEmpty) return null;
    return id.trim();
  }

  void _setActive(String? id) {
    provider.updateBlockData(blockId, 'activeElementId', id);
  }

  void _setElements(List<Map<String, dynamic>> elements) {
    provider.updateBlockData(blockId, 'elements', elements);
  }

  void _updateElement(
    String elementId,
    Map<String, dynamic> patch,
  ) {
    final elements = _elements();
    final idx = elements.indexWhere((e) => e['id']?.toString() == elementId);
    if (idx == -1) return;
    elements[idx] = {
      ...elements[idx],
      ...patch,
    };
    _setElements(elements);
  }

  void _deleteElement(String elementId) {
    final elements = _elements()
      ..removeWhere((e) => e['id']?.toString() == elementId);
    _setElements(elements);
    if (_activeElementId() == elementId) {
      _setActive(null);
    }
  }

  void _moveElement(String elementId, int delta) {
    final elements = _elements();
    final idx = elements.indexWhere((e) => e['id']?.toString() == elementId);
    if (idx == -1) return;
    final nextIdx = (idx + delta).clamp(0, elements.length - 1);
    if (nextIdx == idx) return;
    final item = elements.removeAt(idx);
    elements.insert(nextIdx, item);
    _setElements(elements);
  }

  void _addElement(String type) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final id = 'el_$now';
    final elements = _elements();
    final next = <String, dynamic>{
      'id': id,
      'type': type,
      'x': 24.0,
      'y': 24.0,
      'w': type == 'button' ? 220.0 : 360.0,
      'h': type == 'button' ? 56.0 : 72.0,
    };
    if (type == 'button') {
      next.addAll({
        'label': 'Botón',
        'style': 'filled', // filled|outline|text
        'bgColor': '#00A09D',
        'fgColor': '#FFFFFF',
        'radius': 12.0,
        'fontSize': 14.0,
        'link': '/',
      });
    } else {
      next.addAll({
        'text': 'Texto',
        'fontSize': 28.0,
        'fontWeight': 'w700',
        'color': '#111111',
        'align': 'left',
      });
    }
    elements.add(next);
    _setElements(elements);
    _setActive(id);
  }

  @override
  Widget build(BuildContext context) {
    final height = (data['blockHeight'] as num?)?.toDouble() ?? 420.0;
    final heightMode = (data['heightMode'] ?? 'fixed').toString();
    final vhPct = (data['vhPct'] as num?)?.toDouble() ?? 0.7;
    final fullBleed = (data['fullBleed'] as bool?) ?? false;
    final bg = (data['backgroundColor'] ?? '#FFFFFF').toString();
    final backgroundImageUrl = (data['backgroundImageUrl'] ?? '').toString();
    final backgroundVideoUrl = (data['backgroundVideoUrl'] ?? '').toString();
    final backgroundYoutubeId = (data['backgroundYoutubeId'] ?? '').toString();
    final overlayEnabled = (data['overlayEnabled'] as bool?) ?? false;
    final overlayOpacity = (data['overlayOpacity'] as num?)?.toDouble() ?? 0.35;
    final overlayColor = (data['overlayColor'] ?? '#000000').toString();
    final backgroundFit = (data['backgroundFit'] ?? 'cover').toString();
    final showGrid = (data['showGrid'] as bool?) ?? true;
    final snap = (data['snap'] as bool?) ?? true;
    final gridSize = (data['gridSize'] as num?)?.toDouble() ?? 8.0;
    final snapDistance = (data['snapDistance'] as num?)?.toDouble() ?? 6.0;

    final elements = _elements();
    final activeId = _activeElementId();
    final active = activeId == null
        ? null
        : elements.cast<Map<String, dynamic>?>().firstWhere(
              (e) => e?['id']?.toString() == activeId,
              orElse: () => null,
            );
    final activeType = (active?['type'] ?? '').toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ========== BLOCK SETTINGS ==========
        _CollapsibleSection(
          title: 'Block Settings',
          icon: Icons.settings_rounded,
          initiallyExpanded:
              active == null, // Only expanded when no element selected
          children: [
            _EditorToggle(
              label: 'Full-bleed (sin padding)',
              value: fullBleed,
              onChanged: (v) =>
                  provider.updateBlockData(blockId, 'fullBleed', v),
            ),
            const SizedBox(height: 12),
            _EditorDropdown(
              label: 'Altura',
              value: heightMode,
              options: const [
                ('fixed', 'Fija'),
                ('viewport', 'Viewport (pantalla)'),
              ],
              onChanged: (v) =>
                  provider.updateBlockData(blockId, 'heightMode', v),
            ),
            const SizedBox(height: 12),
            if (heightMode == 'viewport') ...[
              _EditorSlider(
                label: 'Viewport height',
                value: vhPct.clamp(0.2, 1.0),
                min: 0.2,
                max: 1.0,
                divisions: 16,
                valueLabel: '${(vhPct * 100).toStringAsFixed(0)}%',
                onChanged: (v) => provider.updateBlockData(blockId, 'vhPct', v),
              ),
            ] else ...[
              _EditorSlider(
                label: 'Altura del canvas',
                value: height.clamp(220, 1600),
                min: 220,
                max: 1600,
                divisions: 69,
                valueLabel: '${height.toStringAsFixed(0)}px',
                onChanged: (v) =>
                    provider.updateBlockData(blockId, 'blockHeight', v),
              ),
            ],
            const SizedBox(height: 12),
            _EditorTextField(
              label: 'Color de fondo (hex)',
              value: bg,
              onChanged: (v) =>
                  provider.updateBlockData(blockId, 'backgroundColor', v),
            ),
          ],
        ),

        // ========== BACKGROUND & OVERLAY ==========
        _CollapsibleSection(
          title: 'Background & Overlay',
          icon: Icons.image_rounded,
          initiallyExpanded: false, // Always collapsed unless manually opened
          children: [
            _ImagePicker(
              currentUrl: backgroundImageUrl,
              onChanged: (url) =>
                  provider.updateBlockData(blockId, 'backgroundImageUrl', url),
            ),
            const SizedBox(height: 12),
            _EditorTextField(
              label: 'Video URL (mp4/webm) (opcional)',
              value: backgroundVideoUrl,
              onChanged: (v) =>
                  provider.updateBlockData(blockId, 'backgroundVideoUrl', v),
            ),
            const SizedBox(height: 12),
            _EditorTextField(
              label: 'YouTube URL / ID (opcional)',
              value: backgroundYoutubeId,
              onChanged: (v) {
                String id = v;
                // Try to extract ID if it looks like a URL
                if (v.contains('youtube.com') || v.contains('youtu.be')) {
                  final regExp = RegExp(
                    r'^.*((youtu.be\/)|(v\/)|(\/u\/\w\/)|(embed\/)|(watch\?))\??v?=?([^#&?]*).*',
                  );
                  final match = regExp.firstMatch(v);
                  if (match != null && match.groupCount >= 7) {
                    final extracted = match.group(7);
                    if (extracted != null && extracted.isNotEmpty) {
                      id = extracted;
                    }
                  }
                }
                provider.updateBlockData(blockId, 'backgroundYoutubeId', id);
              },
              hint: 'Pegue enlace de YouTube o ID',
            ),
            const SizedBox(height: 12),
            _EditorDropdown(
              label: 'Fit',
              value: backgroundFit,
              options: const [
                ('cover', 'Cover'),
                ('contain', 'Contain'),
              ],
              onChanged: (v) =>
                  provider.updateBlockData(blockId, 'backgroundFit', v),
            ),
            const SizedBox(height: 12),
            _EditorToggle(
              label: 'Overlay',
              value: overlayEnabled,
              onChanged: (v) =>
                  provider.updateBlockData(blockId, 'overlayEnabled', v),
            ),
            if (overlayEnabled) ...[
              const SizedBox(height: 12),
              _EditorTextField(
                label: 'Overlay color (hex)',
                value: overlayColor,
                onChanged: (v) =>
                    provider.updateBlockData(blockId, 'overlayColor', v),
              ),
              const SizedBox(height: 12),
              _EditorSlider(
                label: 'Opacidad overlay',
                value: overlayOpacity.clamp(0.0, 0.9),
                min: 0.0,
                max: 0.9,
                divisions: 18,
                valueLabel: overlayOpacity.toStringAsFixed(2),
                onChanged: (v) =>
                    provider.updateBlockData(blockId, 'overlayOpacity', v),
              ),
            ],
          ],
        ),

        // ========== GRID & SNAPPING ==========
        _CollapsibleSection(
          title: 'Grid & Snapping',
          icon: Icons.grid_on_rounded,
          initiallyExpanded: false, // Always collapsed unless manually opened
          children: [
            _EditorToggle(
              label: 'Mostrar grid',
              value: showGrid,
              onChanged: (v) =>
                  provider.updateBlockData(blockId, 'showGrid', v),
            ),
            const SizedBox(height: 12),
            _EditorToggle(
              label: 'Snapping',
              value: snap,
              onChanged: (v) => provider.updateBlockData(blockId, 'snap', v),
            ),
            const SizedBox(height: 12),
            _EditorSlider(
              label: 'Tamaño grid',
              value: gridSize.clamp(4, 24),
              min: 4,
              max: 24,
              divisions: 20,
              valueLabel: '${gridSize.toStringAsFixed(0)}px',
              onChanged: (v) =>
                  provider.updateBlockData(blockId, 'gridSize', v),
            ),
            const SizedBox(height: 12),
            _EditorSlider(
              label: 'Distancia snap',
              value: snapDistance.clamp(2, 16),
              min: 2,
              max: 16,
              divisions: 14,
              valueLabel: '${snapDistance.toStringAsFixed(0)}px',
              onChanged: (v) =>
                  provider.updateBlockData(blockId, 'snapDistance', v),
            ),
          ],
        ),

        // ========== CANVAS ELEMENTS ==========
        _CollapsibleSection(
          title: 'Canvas Elements (${elements.length})',
          icon: Icons.layers_rounded,
          initiallyExpanded:
              active == null, // Only expanded when no element selected
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _addElement('text'),
                    icon: const Icon(Icons.text_fields_rounded, size: 18),
                    label: const Text('Texto'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _addElement('button'),
                    icon: const Icon(Icons.smart_button_rounded, size: 18),
                    label: const Text('Botón'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (elements.isEmpty)
              Text(
                'Agrega elementos y arrástralos en el canvas.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              )
            else
              Column(
                children: elements.map((e) {
                  final id = e['id']?.toString() ?? '';
                  final type = (e['type'] ?? 'text').toString();
                  final title = type == 'button'
                      ? (e['label'] ?? 'Botón').toString()
                      : (e['text'] ?? 'Texto').toString();
                  final isActive = id == activeId;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isActive
                            ? const Color(0xFF00A09D)
                            : Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        type == 'button'
                            ? Icons.smart_button_rounded
                            : Icons.text_fields_rounded,
                        color: Colors.white70,
                        size: 18,
                      ),
                      title: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13),
                      ),
                      onTap: () => _setActive(id),
                      trailing: IconButton(
                        tooltip: 'Eliminar',
                        icon: const Icon(Icons.delete_outline, size: 18),
                        color: Colors.red.shade300,
                        onPressed: () => _deleteElement(id),
                      ),
                    ),
                  );
                }).toList(),
              ),
            if (active == null) ...[
              const SizedBox(height: 12),
              Text(
                'Selecciona un elemento para editarlo.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              ),
            ],
          ],
        ),

        // ========== ELEMENT EDITOR (when element is selected) ==========
        if (active != null) ...[
          _CollapsibleSection(
            title:
                'Edit: ${activeType == "button" ? (active["label"] ?? "Botón") : (active["text"] ?? "Texto")}',
            icon: activeType == 'button'
                ? Icons.smart_button_rounded
                : Icons.text_fields_rounded,
            initiallyExpanded: true,
            children: [
              if (activeType == 'text') ...[
                _EditorTextField(
                  label: 'Texto',
                  value: active['text']?.toString() ?? '',
                  onChanged: (v) => _updateElement(activeId!, {'text': v}),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                _EditorSlider(
                  label: 'Tamaño fuente',
                  value: ((active['fontSize'] as num?)?.toDouble() ?? 24)
                      .clamp(10, 80),
                  min: 10,
                  max: 80,
                  divisions: 70,
                  valueLabel:
                      '${((active['fontSize'] as num?)?.toDouble() ?? 24).toStringAsFixed(0)}px',
                  onChanged: (v) => _updateElement(activeId!, {'fontSize': v}),
                ),
                const SizedBox(height: 12),
                _EditorDropdown(
                  label: 'Peso',
                  value: (active['fontWeight'] ?? 'w600').toString(),
                  options: const [
                    ('w400', 'Normal'),
                    ('w500', 'Medio'),
                    ('w600', 'Semi-bold'),
                    ('w700', 'Bold'),
                  ],
                  onChanged: (v) =>
                      _updateElement(activeId!, {'fontWeight': v}),
                ),
                const SizedBox(height: 12),
                _EditorDropdown(
                  label: 'Alineación',
                  value: (active['align'] ?? 'left').toString(),
                  options: const [
                    ('left', 'Izquierda'),
                    ('center', 'Centro'),
                    ('right', 'Derecha'),
                  ],
                  onChanged: (v) => _updateElement(activeId!, {'align': v}),
                ),
                const SizedBox(height: 12),
                _EditorTextField(
                  label: 'Color (hex)',
                  value: (active['color'] ?? '#111111').toString(),
                  onChanged: (v) => _updateElement(activeId!, {'color': v}),
                ),
                const SizedBox(height: 12),
                _EditorDropdown(
                  label: 'Animación',
                  value: (active['anim'] ?? 'none').toString(),
                  options: const [
                    ('none', 'Ninguna'),
                    ('fade', 'Fade'),
                    ('fadeUp', 'Fade up'),
                  ],
                  onChanged: (v) => _updateElement(activeId!, {'anim': v}),
                ),
              ] else if (activeType == 'button') ...[
                _EditorTextField(
                  label: 'Texto del botón',
                  value: active['label']?.toString() ?? '',
                  onChanged: (v) => _updateElement(activeId!, {'label': v}),
                ),
                const SizedBox(height: 12),
                _EditorDropdown(
                  label: 'Estilo',
                  value: (active['style'] ?? 'filled').toString(),
                  options: const [
                    ('filled', 'Relleno'),
                    ('outline', 'Borde'),
                    ('text', 'Texto'),
                  ],
                  onChanged: (v) => _updateElement(activeId!, {'style': v}),
                ),
                const SizedBox(height: 12),
                _LinkPicker(
                  label: 'Link',
                  currentLink: (active['link'] ?? '/').toString(),
                  onChanged: (v) => _updateElement(activeId!, {'link': v}),
                ),
                const SizedBox(height: 12),
                _EditorTextField(
                  label: 'Color fondo (hex)',
                  value: (active['bgColor'] ?? '#00A09D').toString(),
                  onChanged: (v) => _updateElement(activeId!, {'bgColor': v}),
                ),
                const SizedBox(height: 12),
                _EditorTextField(
                  label: 'Color texto (hex)',
                  value: (active['fgColor'] ?? '#FFFFFF').toString(),
                  onChanged: (v) => _updateElement(activeId!, {'fgColor': v}),
                ),
                const SizedBox(height: 12),
                _EditorSlider(
                  label: 'Radio',
                  value: ((active['radius'] as num?)?.toDouble() ?? 12)
                      .clamp(0, 32),
                  min: 0,
                  max: 32,
                  divisions: 32,
                  valueLabel:
                      '${((active['radius'] as num?)?.toDouble() ?? 12).toStringAsFixed(0)}px',
                  onChanged: (v) => _updateElement(activeId!, {'radius': v}),
                ),
                const SizedBox(height: 12),
                _EditorToggle(
                  label: 'Sombra',
                  value: (active['shadow'] as bool?) ?? false,
                  onChanged: (v) => _updateElement(activeId!, {'shadow': v}),
                ),
                const SizedBox(height: 12),
                _EditorToggle(
                  label: 'MAYÚSCULAS',
                  value: (active['uppercase'] as bool?) ?? false,
                  onChanged: (v) => _updateElement(activeId!, {'uppercase': v}),
                ),
                const SizedBox(height: 12),
                _EditorSlider(
                  label: 'Letter spacing',
                  value: ((active['letterSpacing'] as num?)?.toDouble() ?? 0.0)
                      .clamp(0, 6),
                  min: 0,
                  max: 6,
                  divisions: 12,
                  valueLabel:
                      '${((active['letterSpacing'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(1)}',
                  onChanged: (v) =>
                      _updateElement(activeId!, {'letterSpacing': v}),
                ),
                const SizedBox(height: 12),
                _EditorDropdown(
                  label: 'Animación',
                  value: (active['anim'] ?? 'none').toString(),
                  options: const [
                    ('none', 'Ninguna'),
                    ('fade', 'Fade'),
                    ('fadeUp', 'Fade up'),
                  ],
                  onChanged: (v) => _updateElement(activeId!, {'anim': v}),
                ),
              ] else if (activeType == 'image') ...[
                _ImagePicker(
                  currentUrl: (active['imageUrl'] ?? '').toString(),
                  onChanged: (url) =>
                      _updateElement(activeId!, {'imageUrl': url}),
                ),
                const SizedBox(height: 12),
                _EditorDropdown(
                  label: 'Fit',
                  value: (active['fit'] ?? 'cover').toString(),
                  options: const [
                    ('cover', 'Cover'),
                    ('contain', 'Contain'),
                  ],
                  onChanged: (v) => _updateElement(activeId!, {'fit': v}),
                ),
                const SizedBox(height: 12),
                _EditorSlider(
                  label: 'Radio',
                  value: ((active['radius'] as num?)?.toDouble() ?? 12)
                      .clamp(0, 32),
                  min: 0,
                  max: 32,
                  divisions: 32,
                  valueLabel:
                      '${((active['radius'] as num?)?.toDouble() ?? 12).toStringAsFixed(0)}px',
                  onChanged: (v) => _updateElement(activeId!, {'radius': v}),
                ),
                const SizedBox(height: 12),
                _EditorDropdown(
                  label: 'Animación',
                  value: (active['anim'] ?? 'none').toString(),
                  options: const [
                    ('none', 'Ninguna'),
                    ('fade', 'Fade'),
                    ('fadeUp', 'Fade up'),
                  ],
                  onChanged: (v) => _updateElement(activeId!, {'anim': v}),
                ),
              ] else if (activeType == 'product') ...[
                _CanvasProductSelector(
                  currentProductId: (active['productId'] ?? '').toString(),
                  onChanged: (id) =>
                      _updateElement(activeId!, {'productId': id}),
                ),
                const SizedBox(height: 12),
                _EditorToggle(
                  label: 'Mostrar precio',
                  value: (active['showPrice'] as bool?) ?? true,
                  onChanged: (v) => _updateElement(activeId!, {'showPrice': v}),
                ),
                const SizedBox(height: 12),
                _EditorDropdown(
                  label: 'Animación',
                  value: (active['anim'] ?? 'none').toString(),
                  options: const [
                    ('none', 'Ninguna'),
                    ('fade', 'Fade'),
                    ('fadeUp', 'Fade up'),
                  ],
                  onChanged: (v) => _updateElement(activeId!, {'anim': v}),
                ),
              ] else if (activeType == 'productsGallery') ...[
                _EditorDropdown(
                  label: 'Modo',
                  value: (active['mode'] ?? 'latest').toString(),
                  options: const [
                    ('latest', 'Últimos publicados'),
                    ('manual', 'Manual (IDs)'),
                  ],
                  onChanged: (v) => _updateElement(activeId!, {'mode': v}),
                ),
                const SizedBox(height: 12),
                _EditorDropdown(
                  label: 'Diseño',
                  value: (active['layout'] ?? 'grid').toString(),
                  options: const [
                    ('grid', 'Cuadrícula'),
                    ('carousel', 'Carrusel'),
                  ],
                  onChanged: (v) => _updateElement(activeId!, {'layout': v}),
                ),
                const SizedBox(height: 12),
                _EditorSlider(
                  label: 'Máx productos',
                  value: ((active['maxProducts'] as num?)?.toDouble() ?? 6)
                      .clamp(1, 24),
                  min: 1,
                  max: 24,
                  divisions: 23,
                  valueLabel: '${(active['maxProducts'] ?? 6)}',
                  onChanged: (v) =>
                      _updateElement(activeId!, {'maxProducts': v.round()}),
                ),
                const SizedBox(height: 12),
                if ((active['layout'] ?? 'grid').toString() == 'grid')
                  _EditorSlider(
                    label: 'Columnas',
                    value: ((active['columns'] as num?)?.toDouble() ?? 3)
                        .clamp(1, 4),
                    min: 1,
                    max: 4,
                    divisions: 3,
                    valueLabel: '${(active['columns'] ?? 3)}',
                    onChanged: (v) =>
                        _updateElement(activeId!, {'columns': v.round()}),
                  )
                else
                  _EditorSlider(
                    label: 'Ancho tarjeta',
                    value: ((active['cardWidth'] as num?)?.toDouble() ?? 300)
                        .clamp(220, 380),
                    min: 220,
                    max: 380,
                    divisions: 32,
                    valueLabel:
                        '${((active['cardWidth'] as num?)?.toDouble() ?? 300).toStringAsFixed(0)}px',
                    onChanged: (v) =>
                        _updateElement(activeId!, {'cardWidth': v}),
                  ),
                const SizedBox(height: 12),
                if ((active['mode'] ?? 'latest').toString() == 'manual') ...[
                  _CanvasProductsMultiSelector(
                    selectedIds: ((active['productIds'] as List?) ?? const [])
                        .map((e) => e.toString())
                        .where((e) => e.isNotEmpty)
                        .toList(),
                    onConfirm: (ids) =>
                        _updateElement(activeId!, {'productIds': ids}),
                  ),
                ],
                const SizedBox(height: 12),
                _EditorDropdown(
                  label: 'Animación',
                  value: (active['anim'] ?? 'none').toString(),
                  options: const [
                    ('none', 'Ninguna'),
                    ('fade', 'Fade'),
                    ('fadeUp', 'Fade up'),
                  ],
                  onChanged: (v) => _updateElement(activeId!, {'anim': v}),
                ),
              ],
              const SizedBox(height: 16),
              const Divider(color: Colors.white12),
              const SizedBox(height: 8),
              const _SectionHeader('Capas'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _moveElement(activeId!, -1),
                      icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                      label: const Text('Enviar atrás'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _moveElement(activeId!, 1),
                      icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                      label: const Text('Traer adelante'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white12),
              const SizedBox(height: 8),
              const _SectionHeader('Tamaño / Posición'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _EditorTextField(
                      label: 'X',
                      value: ((active['x'] as num?)?.toDouble() ?? 0)
                          .toStringAsFixed(0),
                      onChanged: (v) {
                        final parsed = double.tryParse(v);
                        if (parsed == null) return;
                        _updateElement(activeId!, {'x': parsed});
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _EditorTextField(
                      label: 'Y',
                      value: ((active['y'] as num?)?.toDouble() ?? 0)
                          .toStringAsFixed(0),
                      onChanged: (v) {
                        final parsed = double.tryParse(v);
                        if (parsed == null) return;
                        _updateElement(activeId!, {'y': parsed});
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _EditorTextField(
                      label: 'W',
                      value: ((active['w'] as num?)?.toDouble() ?? 200)
                          .toStringAsFixed(0),
                      onChanged: (v) {
                        final parsed = double.tryParse(v);
                        if (parsed == null) return;
                        _updateElement(
                            activeId!, {'w': parsed.clamp(40, 2000)});
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _EditorTextField(
                      label: 'H',
                      value: ((active['h'] as num?)?.toDouble() ?? 56)
                          .toStringAsFixed(0),
                      onChanged: (v) {
                        final parsed = double.tryParse(v);
                        if (parsed == null) return;
                        _updateElement(
                            activeId!, {'h': parsed.clamp(30, 2000)});
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: Colors.white12),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _setActive(null),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Deseleccionar elemento'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade300,
                  side: BorderSide(
                      color: Colors.red.shade300.withValues(alpha: 0.5)),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _CanvasProductSelector extends StatefulWidget {
  final String currentProductId;
  final ValueChanged<String> onChanged;

  const _CanvasProductSelector({
    required this.currentProductId,
    required this.onChanged,
  });

  @override
  State<_CanvasProductSelector> createState() => _CanvasProductSelectorState();
}

class _CanvasProductsMultiSelector extends StatefulWidget {
  final List<String> selectedIds;
  final ValueChanged<List<String>> onConfirm;

  const _CanvasProductsMultiSelector({
    required this.selectedIds,
    required this.onConfirm,
  });

  @override
  State<_CanvasProductsMultiSelector> createState() =>
      _CanvasProductsMultiSelectorState();
}

class _CanvasProductsMultiSelectorState
    extends State<_CanvasProductsMultiSelector> {
  bool _isLoadingProducts = true;
  List<Map<String, dynamic>> _availableProducts = const [];

  Future<String?> _resolveTenantId() async {
    try {
      final service = context.read<TenantService>();
      return await service.getTenantId();
    } catch (_) {
      return await TenantService().getTenantId();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoadingProducts = true);
    try {
      final tenantId = await _resolveTenantId();
      if (tenantId == null) {
        _availableProducts = const [];
        return;
      }
      final supabase = Supabase.instance.client;
      final productsResponse = await supabase
          .from('products')
          .select(
              'id, name, sku, price, image_url, is_active, is_published, stock_quantity, inventory_qty')
          .eq('tenant_id', tenantId)
          .order('name', ascending: true)
          .limit(400);
      _availableProducts = List<Map<String, dynamic>>.from(productsResponse);
    } catch (_) {
      _availableProducts = const [];
    } finally {
      if (mounted) setState(() => _isLoadingProducts = false);
    }
  }

  Future<void> _openPicker() async {
    if (_isLoadingProducts) return;
    if (_availableProducts.isEmpty) {
      await _loadProducts();
      if (!mounted) return;
      if (_availableProducts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudieron cargar los productos')),
        );
        return;
      }
    }

    // ignore: use_build_context_synchronously
    await showDialog(
      context: context,
      builder: (ctx) => _ProductPickerDialog(
        availableProducts: _availableProducts,
        selectedIds: widget.selectedIds,
        onConfirm: (selectedIds) => widget.onConfirm(selectedIds),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedProducts = widget.selectedIds
        .map((id) => _availableProducts.firstWhere(
              (p) => p['id']?.toString() == id,
              orElse: () => <String, dynamic>{},
            ))
        .where((p) => p.isNotEmpty)
        .map((p) => Map<String, dynamic>.from(p))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Productos seleccionados (${widget.selectedIds.length})',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _isLoadingProducts ? null : _openPicker,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Agregar'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (widget.selectedIds.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D2D),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white12),
            ),
            child: const Center(
              child: Text(
                'No hay productos seleccionados\nToca "Agregar" para elegir productos',
                style: TextStyle(color: Colors.white38, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ...selectedProducts.map((p) {
            final id = p['id']?.toString() ?? '';
            return _SelectedProductRow(
              product: p,
              onRemove: () {
                final next = List<String>.from(widget.selectedIds)..remove(id);
                widget.onConfirm(next);
              },
            );
          }),
      ],
    );
  }
}

class _CanvasProductSelectorState extends State<_CanvasProductSelector> {
  final _skuController = TextEditingController();
  bool _isSearchingSku = false;
  bool _isLoadingProducts = true;
  List<Map<String, dynamic>> _availableProducts = const [];
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _skuController.dispose();
    super.dispose();
  }

  Future<String?> _resolveTenantId() async {
    try {
      final service = context.read<TenantService>();
      return await service.getTenantId();
    } catch (_) {
      return await TenantService().getTenantId();
    }
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoadingProducts = true);
    try {
      final tenantId = await _resolveTenantId();
      if (tenantId == null) {
        _availableProducts = const [];
        return;
      }
      final supabase = Supabase.instance.client;

      // Load active products for picker (and also load currently selected, even if inactive)
      final productsResponse = await supabase
          .from('products')
          .select(
              'id, name, sku, price, image_url, is_active, is_published, stock_quantity, inventory_qty')
          .eq('tenant_id', tenantId)
          .order('name', ascending: true)
          .limit(400);

      var allProducts = List<Map<String, dynamic>>.from(productsResponse);

      final selectedId = widget.currentProductId.trim();
      if (selectedId.isNotEmpty) {
        final exists =
            allProducts.any((p) => p['id']?.toString() == selectedId);
        if (!exists) {
          final selectedResponse = await supabase
              .from('products')
              .select(
                  'id, name, sku, price, image_url, is_active, is_published, stock_quantity, inventory_qty')
              .eq('tenant_id', tenantId)
              .inFilter('id', [selectedId]);
          for (final selected in selectedResponse) {
            allProducts.add(Map<String, dynamic>.from(selected));
          }
        }
      }

      _availableProducts = allProducts;
    } catch (_) {
      _availableProducts = const [];
    } finally {
      if (mounted) setState(() => _isLoadingProducts = false);
    }
  }

  Future<void> _pickProduct() async {
    if (_isLoadingProducts) return;
    if (_availableProducts.isEmpty) {
      await _loadProducts();
      if (!mounted) return;
      if (_availableProducts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudieron cargar los productos')),
        );
        return;
      }
    }

    final current = widget.currentProductId.trim();
    final initial = current.isEmpty ? const <String>[] : <String>[current];

    // Reuse the exact same picker dialog used by the Products banner.
    // It is multi-select by design; for single product we just take the first selection.
    // ignore: use_build_context_synchronously
    await showDialog(
      context: context,
      builder: (ctx) => _ProductPickerDialog(
        availableProducts: _availableProducts,
        selectedIds: initial,
        onConfirm: (selectedIds) {
          final next = selectedIds.isNotEmpty ? selectedIds.first : '';
          widget.onChanged(next);
        },
      ),
    );
  }

  Future<void> _findBySku() async {
    final sku = _skuController.text.trim();
    if (sku.isEmpty) return;

    setState(() => _isSearchingSku = true);
    try {
      final tenantId = await _resolveTenantId();
      if (tenantId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo identificar el tenant')),
          );
        }
        return;
      }

      final response = await Supabase.instance.client
          .from('products')
          .select('id, sku, name')
          .eq('tenant_id', tenantId)
          .eq('sku', sku)
          .maybeSingle();

      final id = response?['id']?.toString();
      if (id == null || id.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se encontró producto con SKU "$sku"')),
          );
        }
        return;
      }

      widget.onChanged(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Producto seleccionado: ${response?['name'] ?? sku}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSearchingSku = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = widget.currentProductId.trim();
    final selected = selectedId.isEmpty
        ? null
        : _availableProducts.firstWhere(
            (p) => p['id']?.toString() == selectedId,
            orElse: () => <String, dynamic>{},
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('Producto'),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              selectedId.isEmpty ? 'Ninguno seleccionado' : 'Seleccionado',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: _isLoadingProducts ? null : _pickProduct,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF00A09D),
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                selectedId.isEmpty ? 'Elegir' : 'Cambiar',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (selectedId.isEmpty ||
            (selected is Map<String, dynamic> && selected.isEmpty))
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D2D),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white12),
            ),
            child: const Center(
              child: Text(
                'No hay producto seleccionado\nToca "Elegir" para seleccionar uno',
                style: TextStyle(color: Colors.white38, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          _SelectedProductRow(
            product: Map<String, dynamic>.from(selected as Map),
            onRemove: () => widget.onChanged(''),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            TextButton.icon(
              onPressed: _isSearchingSku
                  ? null
                  : () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) {
                          final controller = TextEditingController();
                          return AlertDialog(
                            title: const Text('Buscar por SKU'),
                            content: TextField(
                              controller: controller,
                              decoration: const InputDecoration(
                                labelText: 'SKU',
                                prefixIcon: Icon(Icons.search),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancelar'),
                              ),
                              FilledButton(
                                onPressed: () {
                                  _skuController.text = controller.text;
                                  Navigator.pop(ctx, true);
                                },
                                child: const Text('Buscar'),
                              ),
                            ],
                          );
                        },
                      );
                      if (ok == true) {
                        // ignore: use_build_context_synchronously
                        await _findBySku();
                      }
                    },
              icon: _isSearchingSku
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search, size: 18),
              label: const Text('Buscar SKU'),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
              child: Text(_showAdvanced ? 'Ocultar avanzado' : 'Avanzado'),
            ),
          ],
        ),
        if (_showAdvanced) ...[
          const SizedBox(height: 8),
          _EditorTextField(
            label: 'Product ID (interno)',
            value: widget.currentProductId,
            onChanged: (v) => widget.onChanged(v.trim()),
          ),
          const SizedBox(height: 6),
          Text(
            'Tip: este campo usa Product ID (UUID). Normalmente selecciona desde “Elegir”.',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
          ),
        ],
      ],
    );
  }
}

// (removed) Canvas-specific picker dialog; Canvas reuses `_ProductPickerDialog` for consistency.

/// Theme tab for global site-wide settings (colors, typography, button styles)
/// Header and Footer are edited via the "Editar" tab when selected
class _ThemeTab extends StatefulWidget {
  @override
  State<_ThemeTab> createState() => _ThemeTabState();
}

class _ThemeTabState extends State<_ThemeTab> {
  // Colors
  final _primaryColorController = TextEditingController();
  final _accentColorController = TextEditingController();

  // Typography
  String _headingFont = 'Inter';
  String _bodyFont = 'Inter';
  String _headingSize = 'normal';
  String _bodySize = 'normal';

  // Button styles
  String _buttonStyle = 'rounded';
  String _buttonSize = 'medium';

  // Background
  String _pageBackground = 'white';

  bool _loaded = false;

  final _fonts = [
    'Inter',
    'Roboto',
    'Open Sans',
    'Montserrat',
    'Poppins',
    'Lato',
    'Oswald',
    'Playfair Display'
  ];
  final _sizes = {'small': 'Pequeño', 'normal': 'Normal', 'large': 'Grande'};
  final _buttonStyles = {
    'rounded': 'Redondeado',
    'square': 'Cuadrado',
    'pill': 'Pill'
  };
  final _buttonSizes = {
    'small': 'Pequeño',
    'medium': 'Mediano',
    'large': 'Grande'
  };
  final _backgrounds = {
    'white': 'Blanco',
    'light': 'Gris claro',
    'dark': 'Oscuro'
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loadSettings();
      _loaded = true;
    }
  }

  void _loadSettings() {
    final service = context.read<WebsiteService>();
    _primaryColorController.text =
        service.getSetting('theme_primary_color', '#1B5E20');
    _accentColorController.text =
        service.getSetting('theme_accent_color', '#FF6D00');
    _headingFont = service.getSetting('heading_font', 'Inter');
    _bodyFont = service.getSetting('body_font', 'Inter');
    _headingSize = service.getSetting('heading_size', 'normal');
    _bodySize = service.getSetting('body_size', 'normal');
    _buttonStyle = service.getSetting('button_style', 'rounded');
    _buttonSize = service.getSetting('button_size', 'medium');
    _pageBackground = service.getSetting('page_background', 'white');
  }

  Future<void> _saveSettings() async {
    final service = context.read<WebsiteService>();
    await service.saveSettings({
      'theme_primary_color': _primaryColorController.text,
      'theme_accent_color': _accentColorController.text,
      'heading_font': _headingFont,
      'body_font': _bodyFont,
      'heading_size': _headingSize,
      'body_size': _bodySize,
      'button_style': _buttonStyle,
      'button_size': _buttonSize,
      'page_background': _pageBackground,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Tema guardado'),
          backgroundColor: Color(0xFF00A09D),
        ),
      );
    }
  }

  @override
  void dispose() {
    _primaryColorController.dispose();
    _accentColorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade300, size: 20),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Para editar el header o footer, haz clic directamente sobre ellos en la página.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ========== COLORS SECTION ==========
          _SectionHeader('Colores'),
          const SizedBox(height: 12),
          _ColorField(
            label: 'Color primario',
            controller: _primaryColorController,
          ),
          const SizedBox(height: 12),
          _ColorField(
            label: 'Color de acento',
            controller: _accentColorController,
          ),

          const SizedBox(height: 24),

          // ========== TYPOGRAPHY SECTION ==========
          _SectionHeader('Tipografía'),
          const SizedBox(height: 12),

          _buildDropdown(
            label: 'Fuente de títulos',
            value: _headingFont,
            items: _fonts,
            onChanged: (v) => setState(() => _headingFont = v!),
          ),
          const SizedBox(height: 12),

          _buildDropdown(
            label: 'Tamaño de títulos',
            value: _headingSize,
            items: _sizes.keys.toList(),
            labels: _sizes,
            onChanged: (v) => setState(() => _headingSize = v!),
          ),
          const SizedBox(height: 16),

          _buildDropdown(
            label: 'Fuente de texto',
            value: _bodyFont,
            items: _fonts,
            onChanged: (v) => setState(() => _bodyFont = v!),
          ),
          const SizedBox(height: 12),

          _buildDropdown(
            label: 'Tamaño de texto',
            value: _bodySize,
            items: _sizes.keys.toList(),
            labels: _sizes,
            onChanged: (v) => setState(() => _bodySize = v!),
          ),

          const SizedBox(height: 24),

          // ========== BUTTON STYLES SECTION ==========
          _SectionHeader('Estilo de botones'),
          const SizedBox(height: 12),

          _buildDropdown(
            label: 'Forma',
            value: _buttonStyle,
            items: _buttonStyles.keys.toList(),
            labels: _buttonStyles,
            onChanged: (v) => setState(() => _buttonStyle = v!),
          ),
          const SizedBox(height: 12),

          _buildDropdown(
            label: 'Tamaño',
            value: _buttonSize,
            items: _buttonSizes.keys.toList(),
            labels: _buttonSizes,
            onChanged: (v) => setState(() => _buttonSize = v!),
          ),

          const SizedBox(height: 24),

          // ========== BACKGROUND SECTION ==========
          _SectionHeader('Fondo de página'),
          const SizedBox(height: 12),

          _buildDropdown(
            label: 'Color de fondo',
            value: _pageBackground,
            items: _backgrounds.keys.toList(),
            labels: _backgrounds,
            onChanged: (v) => setState(() => _pageBackground = v!),
          ),

          const SizedBox(height: 32),

          // Save button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saveSettings,
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Guardar tema'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A09D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    Map<String, String>? labels,
    required void Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 6),
        MenuAnchor(
          style: MenuStyle(
            backgroundColor: WidgetStateProperty.all(const Color(0xFF2D2D2D)),
            surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
            padding: WidgetStateProperty.all(EdgeInsets.zero),
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
            ),
          ),
          menuChildren: items.map((item) {
            final itemLabel = labels?[item] ?? item;
            return MenuItemButton(
              onPressed: () => onChanged(item),
              style: ButtonStyle(
                backgroundColor: item == value
                    ? WidgetStateProperty.all(
                        Colors.white.withValues(alpha: 0.1))
                    : null,
                foregroundColor: WidgetStateProperty.all(Colors.white),
                padding: WidgetStateProperty.all(
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              child: Container(
                constraints: const BoxConstraints(minWidth: 120),
                child: Text(
                  itemLabel,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            );
          }).toList(),
          builder: (context, controller, child) {
            final selectedLabel = labels?[value] ?? value;
            return InkWell(
              onTap: () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2D2D),
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        selectedLabel,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.expand_more,
                        color: Colors.white54, size: 20),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Navigation link tile for the header editor
class _NavLinkTile extends StatelessWidget {
  final String label;
  final String url;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _NavLinkTile({
    super.key,
    required this.label,
    required this.url,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF3D3D3D),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: const Icon(Icons.drag_handle, color: Colors.white38, size: 18),
        title: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
        subtitle: Text(
          url,
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit, color: Colors.white54, size: 16),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete, color: Colors.red, size: 16),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}

/// Logo uploader widget with image preview
class _LogoUploader extends StatefulWidget {
  final String? currentUrl;
  final Function(String) onChanged;

  const _LogoUploader({
    this.currentUrl,
    required this.onChanged,
  });

  @override
  State<_LogoUploader> createState() => _LogoUploaderState();
}

class _LogoUploaderState extends State<_LogoUploader> {
  bool _isUploading = false;

  Future<void> _pickAndUploadLogo() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 500,
        maxHeight: 200,
        imageQuality: 90,
      );

      if (image == null) return;

      setState(() => _isUploading = true);

      final bytes = await image.readAsBytes();
      final fileName =
          'logo_${DateTime.now().millisecondsSinceEpoch}_${image.name}';
      final filePath = 'website-images/$fileName';

      final supabase = Supabase.instance.client;

      await supabase.storage.from(StorageConfig.defaultBucket).uploadBinary(
            filePath,
            bytes,
            fileOptions: FileOptions(
              contentType: _getContentType(image.name),
              upsert: true,
            ),
          );

      final publicUrl = supabase.storage
          .from(StorageConfig.defaultBucket)
          .getPublicUrl(filePath);

      setState(() => _isUploading = false);
      widget.onChanged(publicUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Logo actualizado'),
            backgroundColor: Color(0xFF00A09D),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() => _isUploading = false);
      debugPrint('Error uploading logo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getContentType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'svg':
        return 'image/svg+xml';
      default:
        return 'image/png';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLogo = widget.currentUrl != null && widget.currentUrl!.isNotEmpty;

    return InkWell(
      onTap: _isUploading ? null : _pickAndUploadLogo,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 80,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _isUploading
                ? const Color(0xFF00A09D)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: _isUploading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : hasLogo
                ? Row(
                    children: [
                      const SizedBox(width: 16),
                      Container(
                        height: 50,
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Image.network(
                          widget.currentUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.broken_image,
                            color: Colors.white38,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.edit,
                                color: Colors.white38, size: 18),
                            const SizedBox(height: 4),
                            Text(
                              'Cambiar',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_photo_alternate,
                          color: Colors.white38, size: 28),
                      const SizedBox(height: 6),
                      Text(
                        'Subir logo',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

// ============================================
// REUSABLE EDITOR COMPONENTS
// ============================================

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.5),
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
      ),
    );
  }
}

/// Collapsible section for grouping related controls
class _CollapsibleSection extends StatefulWidget {
  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;
  final IconData? icon;

  const _CollapsibleSection({
    required this.title,
    required this.children,
    this.initiallyExpanded = true,
    this.icon,
  });

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
  }

  @override
  void didUpdateWidget(covariant _CollapsibleSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // React to changes in initiallyExpanded (e.g., when active element changes)
    if (widget.initiallyExpanded != oldWidget.initiallyExpanded) {
      setState(() {
        _isExpanded = widget.initiallyExpanded;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                Icon(
                  _isExpanded
                      ? Icons.expand_more_rounded
                      : Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.7),
                  size: 20,
                ),
                const SizedBox(width: 6),
                if (widget.icon != null) ...[
                  Icon(
                    widget.icon,
                    color: const Color(0xFF00A09D),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    widget.title.toUpperCase(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_isExpanded) ...[
          const SizedBox(height: 12),
          ...widget.children,
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

/// Smart link picker with pages, products, anchors, and external URLs
class _LinkPicker extends StatefulWidget {
  final String label;
  final String currentLink;
  final Function(String) onChanged;

  const _LinkPicker({
    required this.label,
    required this.currentLink,
    required this.onChanged,
  });

  @override
  State<_LinkPicker> createState() => _LinkPickerState();
}

class _LinkPickerState extends State<_LinkPicker> {
  bool _isExpanded = false;
  int _selectedTab = 0; // 0=Pages, 1=Products, 2=Anchor, 3=External

  @override
  Widget build(BuildContext context) {
    final displayText = _getDisplayText(widget.currentLink);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 6),
        // Current link display with edit button
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D2D),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _isExpanded ? const Color(0xFF00A09D) : Colors.white12,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _getLinkIcon(widget.currentLink),
                  size: 16,
                  color: const Color(0xFF00A09D),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    displayText.isEmpty ? 'Sin enlace' : displayText,
                    style: TextStyle(
                      color:
                          displayText.isEmpty ? Colors.white38 : Colors.white,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.white54,
                  size: 18,
                ),
              ],
            ),
          ),
        ),

        // Expanded picker
        if (_isExpanded) ...[
          const SizedBox(height: 8),
          // Tab buttons
          Row(
            children: [
              _buildTabButton(0, 'Páginas', Icons.article_outlined),
              const SizedBox(width: 4),
              _buildTabButton(1, 'Tienda', Icons.shopping_bag_outlined),
              const SizedBox(width: 4),
              _buildTabButton(2, 'Ancla', Icons.tag),
              const SizedBox(width: 4),
              _buildTabButton(3, 'URL', Icons.link),
            ],
          ),
          const SizedBox(height: 8),
          // Tab content
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(6),
            ),
            child: _buildTabContent(),
          ),
        ],
      ],
    );
  }

  Widget _buildTabButton(int index, String label, IconData icon) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF00A09D).withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? const Color(0xFF00A09D) : Colors.transparent,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 14,
                  color: isSelected ? const Color(0xFF00A09D) : Colors.white54),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  color: isSelected ? const Color(0xFF00A09D) : Colors.white54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTab) {
      case 0:
        return _buildPagesTab();
      case 1:
        return _buildProductsTab();
      case 2:
        return _buildAnchorTab();
      case 3:
        return _buildExternalTab();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildPagesTab() {
    return FutureBuilder<List<_PageInfo>>(
      future: _loadPages(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 60,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        final pages = snapshot.data ?? [];
        if (pages.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(8),
            child: Text('No hay páginas',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          );
        }

        return Column(
          children: pages.map((page) {
            final isSelected = widget.currentLink == page.path;
            return InkWell(
              onTap: () {
                widget.onChanged(page.path);
                setState(() => _isExpanded = false);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF00A09D).withValues(alpha: 0.15)
                      : null,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(
                      page.isHome
                          ? Icons.home_outlined
                          : Icons.article_outlined,
                      size: 14,
                      color:
                          isSelected ? const Color(0xFF00A09D) : Colors.white54,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        page.title,
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected
                              ? const Color(0xFF00A09D)
                              : Colors.white,
                        ),
                      ),
                    ),
                    Text(
                      page.path,
                      style:
                          const TextStyle(fontSize: 10, color: Colors.white38),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildProductsTab() {
    final links = [
      ('/tienda/productos', 'Todos los productos', Icons.inventory_2_outlined),
      (
        '/tienda/productos?destacados=true',
        'Productos destacados',
        Icons.star_outline
      ),
      ('/tienda/productos?ofertas=true', 'Ofertas', Icons.local_offer_outlined),
      ('/tienda/categorias', 'Categorías', Icons.category_outlined),
      ('/carrito', 'Carrito', Icons.shopping_cart_outlined),
    ];

    return Column(
      children: links.map((item) {
        final isSelected = widget.currentLink == item.$1;
        return InkWell(
          onTap: () {
            widget.onChanged(item.$1);
            setState(() => _isExpanded = false);
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF00A09D).withValues(alpha: 0.15)
                  : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(item.$3,
                    size: 14,
                    color:
                        isSelected ? const Color(0xFF00A09D) : Colors.white54),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.$2,
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          isSelected ? const Color(0xFF00A09D) : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAnchorTab() {
    return TextFormField(
      initialValue:
          widget.currentLink.startsWith('#') ? widget.currentLink : '',
      style: const TextStyle(color: Colors.white, fontSize: 12),
      decoration: InputDecoration(
        hintText: '#seccion-contacto',
        hintStyle:
            TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12),
        prefixIcon: const Icon(Icons.tag, size: 16, color: Colors.white54),
        filled: true,
        fillColor: const Color(0xFF2D2D2D),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide.none,
        ),
      ),
      onFieldSubmitted: (value) {
        final anchor = value.startsWith('#') ? value : '#$value';
        widget.onChanged(anchor);
        setState(() => _isExpanded = false);
      },
    );
  }

  Widget _buildExternalTab() {
    return TextFormField(
      initialValue:
          widget.currentLink.startsWith('http') ? widget.currentLink : '',
      style: const TextStyle(color: Colors.white, fontSize: 12),
      decoration: InputDecoration(
        hintText: 'https://ejemplo.com',
        hintStyle:
            TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12),
        prefixIcon: const Icon(Icons.link, size: 16, color: Colors.white54),
        filled: true,
        fillColor: const Color(0xFF2D2D2D),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide.none,
        ),
      ),
      onFieldSubmitted: (value) {
        widget.onChanged(value);
        setState(() => _isExpanded = false);
      },
    );
  }

  Future<List<_PageInfo>> _loadPages() async {
    try {
      final service = context.read<WebsiteService>();
      await service.loadPages();
      return service.pages
          .map((p) => _PageInfo(
                title: p.title,
                path: p.fullPath,
                isHome: p.isHome,
              ))
          .toList();
    } catch (e) {
      debugPrint('Error loading pages: $e');
      return [];
    }
  }

  String _getDisplayText(String link) {
    if (link.isEmpty) return '';
    if (link.startsWith('#')) return 'Ancla: $link';
    if (link.startsWith('http')) return link;
    if (link.startsWith('/tienda')) return 'Tienda: ${link.split('/').last}';
    if (link == '/') return 'Inicio';
    return link;
  }

  IconData _getLinkIcon(String link) {
    if (link.isEmpty) return Icons.link_off;
    if (link.startsWith('#')) return Icons.tag;
    if (link.startsWith('http')) return Icons.open_in_new;
    if (link.startsWith('/tienda')) return Icons.shopping_bag_outlined;
    return Icons.article_outlined;
  }
}

class _PageInfo {
  final String title;
  final String path;
  final bool isHome;

  _PageInfo({required this.title, required this.path, required this.isHome});
}

class _EditorTextField extends StatefulWidget {
  final String label;
  final String value;
  final Function(String) onChanged;
  final TextEditingController? controller;
  final int maxLines;
  final String? hint;

  const _EditorTextField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.controller,
    this.maxLines = 1,
    this.hint,
  });

  @override
  State<_EditorTextField> createState() => _EditorTextFieldState();
}

class _EditorTextFieldState extends State<_EditorTextField> {
  TextEditingController? _internalController;

  TextEditingController get _effectiveController {
    return widget.controller ??
        (_internalController ??= TextEditingController(text: widget.value));
  }

  @override
  void initState() {
    super.initState();
    // Only create internal controller if external not provided
    if (widget.controller == null) {
      _internalController = TextEditingController(text: widget.value);
      // Add listener to catch paste events that onChanged might miss on web
      _internalController!.addListener(_onControllerChanged);
    }
  }

  void _onControllerChanged() {
    // This fires on ANY text change including paste
    final text = _effectiveController.text;
    if (text != widget.value) {
      debugPrint(
          '📝 [_EditorTextField] controller listener: label="${widget.label}", value="$text"');
      widget.onChanged(text);
    }
  }

  @override
  void didUpdateWidget(covariant _EditorTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only update internal controller if we own it and value changed externally
    if (widget.controller == null && _internalController != null) {
      if (oldWidget.value != widget.value &&
          _internalController!.text != widget.value) {
        // Remove listener temporarily to avoid triggering onChanged
        _internalController!.removeListener(_onControllerChanged);
        _internalController!.text = widget.value;
        _internalController!.addListener(_onControllerChanged);
      }
    }
  }

  @override
  void dispose() {
    _internalController?.removeListener(_onControllerChanged);
    _internalController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _effectiveController,
          maxLines: widget.maxLines,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            filled: true,
            fillColor: const Color(0xFF2D2D2D),
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
              borderSide: const BorderSide(color: Color(0xFF00A09D)),
            ),
          ),
          onChanged: (v) {
            debugPrint(
                '📝 [_EditorTextField] onChanged: label="${widget.label}", value="$v"');
            widget.onChanged(v);
          },
        ),
      ],
    );
  }
}

class _MiniTextField extends StatelessWidget {
  final String value;
  final String hint;
  final Function(String) onChanged;

  const _MiniTextField({
    required this.value,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value,
      style: const TextStyle(color: Colors.white, fontSize: 12),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12),
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: onChanged,
    );
  }
}

class _EditorToggle extends StatelessWidget {
  final String label;
  final bool value;
  final Function(bool) onChanged;

  const _EditorToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          // ON state: bright teal color (highlighted)
          activeColor: Colors.white,
          activeTrackColor: const Color(0xFF00A09D),
          // OFF state: dim/dark (muted)
          inactiveThumbColor: Colors.grey.shade400,
          inactiveTrackColor: Colors.grey.shade700,
        ),
      ],
    );
  }
}

class _EditorSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? valueLabel;
  final Function(double) onChanged;

  const _EditorSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.valueLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                valueLabel ?? value.toInt().toString(),
                style: const TextStyle(color: Color(0xFF00A09D), fontSize: 12),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: const Color(0xFF00A09D),
            inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
            thumbColor: const Color(0xFF00A09D),
            overlayColor: const Color(0xFF00A09D).withValues(alpha: 0.2),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _EditorDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<(String, String)> options; // (value, label)
  final Function(String) onChanged;

  const _EditorDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selectedLabel = options
        .firstWhere(
          (opt) => opt.$1 == value,
          orElse: () => (value, value),
        )
        .$2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 6),
        MenuAnchor(
          style: MenuStyle(
            backgroundColor: WidgetStateProperty.all(const Color(0xFF2D2D2D)),
            surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
            padding: WidgetStateProperty.all(EdgeInsets.zero),
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
            ),
          ),
          menuChildren: options.map((opt) {
            final isSelected = opt.$1 == value;
            return MenuItemButton(
              onPressed: () => onChanged(opt.$1),
              style: ButtonStyle(
                backgroundColor: isSelected
                    ? WidgetStateProperty.all(
                        Colors.white.withValues(alpha: 0.1))
                    : null,
                foregroundColor: WidgetStateProperty.all(Colors.white),
                padding: WidgetStateProperty.all(
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              child: Container(
                constraints: const BoxConstraints(minWidth: 120),
                child: Text(
                  opt.$2,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            );
          }).toList(),
          builder:
              (BuildContext context, MenuController controller, Widget? child) {
            return InkWell(
              onTap: () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2D2D),
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        selectedLabel,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.expand_more,
                        color: Colors.white54, size: 18),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ImagePicker extends StatefulWidget {
  final String? currentUrl;
  final Function(String) onChanged;

  const _ImagePicker({
    this.currentUrl,
    required this.onChanged,
  });

  @override
  State<_ImagePicker> createState() => _ImagePickerState();
}

class _ImagePickerState extends State<_ImagePicker> {
  bool _isUploading = false;

  Future<void> _pickAndUploadImage() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() {
        _isUploading = true;
      });

      // Read file bytes
      final bytes = await image.readAsBytes();
      final fileName =
          'website_${DateTime.now().millisecondsSinceEpoch}_${image.name}';
      final filePath = 'website-images/$fileName';

      // Upload to Supabase Storage
      final supabase = Supabase.instance.client;

      // Use the standard vinabike-assets bucket
      await supabase.storage.from(StorageConfig.defaultBucket).uploadBinary(
            filePath,
            bytes,
            fileOptions: FileOptions(
              contentType: _getContentType(image.name),
              upsert: true,
            ),
          );

      // Get public URL
      final publicUrl = supabase.storage
          .from(StorageConfig.defaultBucket)
          .getPublicUrl(filePath);

      setState(() {
        _isUploading = false;
      });

      widget.onChanged(publicUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Imagen subida correctamente'),
            backgroundColor: Color(0xFF00A09D),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() => _isUploading = false);
      debugPrint('Error uploading image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al subir imagen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getContentType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = widget.currentUrl != null && widget.currentUrl!.isNotEmpty;

    return Column(
      children: [
        // Image preview / upload area
        InkWell(
          onTap: _isUploading ? null : _pickAndUploadImage,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 140,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D2D),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isUploading
                    ? const Color(0xFF00A09D)
                    : Colors.white.withValues(alpha: 0.1),
                width: _isUploading ? 2 : 1,
              ),
              image: hasImage && !_isUploading
                  ? DecorationImage(
                      image: NetworkImage(widget.currentUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: _isUploading
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Color(0xFF00A09D)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Subiendo imagen...',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  )
                : hasImage
                    ? Stack(
                        children: [
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Row(
                              children: [
                                _buildActionButton(
                                  icon: Icons.edit,
                                  tooltip: 'Cambiar imagen',
                                  onTap: _pickAndUploadImage,
                                ),
                                const SizedBox(width: 4),
                                _buildActionButton(
                                  icon: Icons.delete,
                                  tooltip: 'Eliminar',
                                  onTap: () => widget.onChanged(''),
                                  isDestructive: true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00A09D)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(50),
                            ),
                            child: const Icon(
                              Icons.cloud_upload_outlined,
                              color: Color(0xFF00A09D),
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Haz clic para subir imagen',
                            style: TextStyle(
                              color: Color(0xFF00A09D),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'JPG, PNG, WebP • Máx 1920x1080',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isDestructive
                ? Colors.red.shade700.withValues(alpha: 0.9)
                : Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
      ),
    );
  }
}

class _ColorField extends StatelessWidget {
  final String label;
  final TextEditingController controller;

  const _ColorField({
    required this.label,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _parseColor(controller.text),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 4),
              TextFormField(
                controller: controller,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  hintText: '#RRGGBB',
                  hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3), fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF2D2D2D),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (_) {
                  // Trigger rebuild to update color preview
                  (context as Element).markNeedsBuild();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _parseColor(String value) {
    try {
      String hex = value.replaceAll('#', '');
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      }
    } catch (_) {}
    return Colors.grey;
  }
}

// ============================================================================
// CATEGORY GRID BLOCK CONTROLS
// ============================================================================
class _CategoryGridBlockControls extends StatefulWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _CategoryGridBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  @override
  State<_CategoryGridBlockControls> createState() =>
      _CategoryGridBlockControlsState();
}

class _CategoryGridBlockControlsState
    extends State<_CategoryGridBlockControls> {
  int _selectedCategoryIndex = 0;

  List<Map<String, dynamic>> get _categories {
    final raw = widget.data['categories'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  void _updateField(String field, dynamic value) {
    widget.provider.updateBlockData(widget.blockId, field, value);
  }

  void _updateCategory(int index, String field, dynamic value) {
    final categories = List<Map<String, dynamic>>.from(_categories);
    if (index < categories.length) {
      categories[index] = Map<String, dynamic>.from(categories[index]);
      categories[index][field] = value;
      _updateField('categories', categories);
    }
  }

  void _addCategory() {
    final categories = List<Map<String, dynamic>>.from(_categories);
    categories.add({
      'title': 'Nueva Categoría',
      'subtitle': 'Descripción breve',
      'imageUrl': '',
      'ctaText': 'Ver más',
      'ctaLink': '/tienda/productos',
      'size': categories.length < 2 ? 'large' : 'medium',
    });
    _updateField('categories', categories);
    setState(() => _selectedCategoryIndex = categories.length - 1);
  }

  void _removeCategory(int index) {
    final categories = List<Map<String, dynamic>>.from(_categories);
    if (categories.length > 1) {
      categories.removeAt(index);
      _updateField('categories', categories);
      setState(() {
        if (_selectedCategoryIndex >= categories.length) {
          _selectedCategoryIndex = categories.length - 1;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditorTextField(
          label: 'Título de sección',
          value: widget.data['title']?.toString() ?? '',
          onChanged: (v) => _updateField('title', v),
        ),
        const SizedBox(height: 12),
        _EditorTextField(
          label: 'Subtítulo',
          value: widget.data['subtitle']?.toString() ?? '',
          onChanged: (v) => _updateField('subtitle', v),
        ),
        const SizedBox(height: 20),
        Text('Categorías',
            style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1)),
        const SizedBox(height: 8),
        // Category selector chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ..._categories.asMap().entries.map((entry) {
                final index = entry.key;
                final cat = entry.value;
                final isSelected = index == _selectedCategoryIndex;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedCategoryIndex = index),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF00A09D)
                            : const Color(0xFF2D2D2D),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF00A09D)
                              : Colors.white24,
                        ),
                      ),
                      child: Text(
                        cat['title']?.toString() ?? 'Cat ${index + 1}',
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                );
              }),
              GestureDetector(
                onTap: _addCategory,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D2D2D),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                  ),
                  child:
                      const Icon(Icons.add, color: Color(0xFF00A09D), size: 16),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Selected category editor
        if (_categories.isNotEmpty &&
            _selectedCategoryIndex < _categories.length) ...[
          // Image picker for this category
          _SectionHeader('Imagen de categoría'),
          const SizedBox(height: 8),
          _ImagePicker(
            currentUrl:
                _categories[_selectedCategoryIndex]['imageUrl']?.toString(),
            onChanged: (url) =>
                _updateCategory(_selectedCategoryIndex, 'imageUrl', url),
          ),
          const SizedBox(height: 16),
          _EditorTextField(
            label: 'Título categoría',
            value:
                _categories[_selectedCategoryIndex]['title']?.toString() ?? '',
            onChanged: (v) =>
                _updateCategory(_selectedCategoryIndex, 'title', v),
          ),
          const SizedBox(height: 12),
          _EditorTextField(
            label: 'Subtítulo',
            value:
                _categories[_selectedCategoryIndex]['subtitle']?.toString() ??
                    '',
            onChanged: (v) =>
                _updateCategory(_selectedCategoryIndex, 'subtitle', v),
          ),
          const SizedBox(height: 12),
          _EditorTextField(
            label: 'Texto botón',
            value: _categories[_selectedCategoryIndex]['ctaText']?.toString() ??
                '',
            onChanged: (v) =>
                _updateCategory(_selectedCategoryIndex, 'ctaText', v),
          ),
          const SizedBox(height: 12),
          _EditorTextField(
            label: 'Link botón',
            value: _categories[_selectedCategoryIndex]['ctaLink']?.toString() ??
                '',
            onChanged: (v) =>
                _updateCategory(_selectedCategoryIndex, 'ctaLink', v),
          ),
          const SizedBox(height: 12),
          // Size selector
          Text('Tamaño',
              style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1)),
          const SizedBox(height: 8),
          Row(
            children: ['large', 'medium'].map((size) {
              final isSelected =
                  _categories[_selectedCategoryIndex]['size'] == size;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () =>
                      _updateCategory(_selectedCategoryIndex, 'size', size),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF00A09D)
                          : const Color(0xFF2D2D2D),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      size == 'large' ? 'Grande' : 'Mediano',
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          // Delete category button
          if (_categories.length > 1)
            TextButton.icon(
              onPressed: () => _removeCategory(_selectedCategoryIndex),
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Eliminar categoría'),
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade300),
            ),
        ],
      ],
    );
  }
}

// ============================================================================
// VIDEO BANNER BLOCK CONTROLS
// ============================================================================
class _VideoBannerBlockControls extends StatefulWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _VideoBannerBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  @override
  State<_VideoBannerBlockControls> createState() =>
      _VideoBannerBlockControlsState();
}

class _VideoBannerBlockControlsState extends State<_VideoBannerBlockControls> {
  bool _isUploading = false;

  void _updateField(String field, dynamic value) {
    widget.provider.updateBlockData(widget.blockId, field, value);
  }

  Future<void> _uploadVideoFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error: No se pudo leer el archivo')),
          );
        }
        return;
      }

      setState(() => _isUploading = true);

      // Get tenant ID
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Usuario no autenticado');

      final profileResponse = await Supabase.instance.client
          .from('user_profiles')
          .select('tenant_id')
          .eq('user_id', user.id)
          .single();

      final tenantId = profileResponse['tenant_id'] as String;

      // Upload to Supabase Storage
      final fileName =
          'video_${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final storagePath = '$tenantId/videos/$fileName';

      await Supabase.instance.client.storage
          .from('website-assets')
          .uploadBinary(storagePath, file.bytes!,
              fileOptions: FileOptions(
                contentType: file.extension == 'mp4'
                    ? 'video/mp4'
                    : 'video/${file.extension ?? 'mp4'}',
              ));

      // Get public URL
      final publicUrl = Supabase.instance.client.storage
          .from('website-assets')
          .getPublicUrl(storagePath);

      _updateField('videoFileUrl', publicUrl);
      // Clear the YouTube URL if uploading a file
      _updateField('videoUrl', '');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Video subido correctamente'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('[VideoBanner] Error uploading video: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al subir video: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasVideoFile =
        (widget.data['videoFileUrl']?.toString() ?? '').isNotEmpty;
    final hasYoutubeUrl =
        (widget.data['videoUrl']?.toString() ?? '').isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditorTextField(
          label: 'Título',
          value: widget.data['title']?.toString() ?? '',
          onChanged: (v) => _updateField('title', v),
        ),
        const SizedBox(height: 12),
        _EditorTextField(
          label: 'Subtítulo',
          value: widget.data['subtitle']?.toString() ?? '',
          onChanged: (v) => _updateField('subtitle', v),
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        _EditorTextField(
          label: 'URL Imagen de fondo',
          value: widget.data['imageUrl']?.toString() ?? '',
          onChanged: (v) => _updateField('imageUrl', v),
        ),
        const SizedBox(height: 20),

        // Video section header
        Text('VIDEO DE FONDO',
            style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1)),
        const SizedBox(height: 8),
        Text(
          'El video se reproducirá automáticamente, sin sonido, en loop',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
        const SizedBox(height: 12),

        // YouTube URL option
        _EditorTextField(
          label: 'URL de YouTube',
          value: widget.data['videoUrl']?.toString() ?? '',
          onChanged: (v) {
            _updateField('videoUrl', v);
            // Clear file URL if entering YouTube URL
            if (v.isNotEmpty) {
              _updateField('videoFileUrl', '');
            }
          },
          hint: 'https://youtube.com/watch?v=...',
        ),

        const SizedBox(height: 12),

        // Divider with "o" (or)
        Row(
          children: [
            Expanded(child: Divider(color: Colors.white24)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('o',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
            ),
            Expanded(child: Divider(color: Colors.white24)),
          ],
        ),

        const SizedBox(height: 12),

        // Upload video file button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isUploading ? null : _uploadVideoFile,
            icon: _isUploading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.upload_file, size: 18),
            label:
                Text(_isUploading ? 'Subiendo...' : 'Subir archivo de video'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00A09D),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),

        // Show current video file if exists
        if (hasVideoFile) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Archivo de video cargado',
                    style: TextStyle(color: Colors.green, fontSize: 12),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: Colors.red.shade300, size: 18),
                  onPressed: () => _updateField('videoFileUrl', ''),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Eliminar video',
                ),
              ],
            ),
          ),
        ],

        // Show YouTube status if exists
        if (hasYoutubeUrl && !hasVideoFile) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.play_circle_filled, color: Colors.red, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Video de YouTube configurado',
                    style: TextStyle(color: Colors.red.shade200, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),

        // Show CTA toggle
        Row(
          children: [
            const Text('Mostrar botón',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const Spacer(),
            Switch(
              value: widget.data['showCta'] != false,
              onChanged: (v) => _updateField('showCta', v),
              // ON state: bright teal color (highlighted)
              activeColor: Colors.white,
              activeTrackColor: const Color(0xFF00A09D),
              // OFF state: dim/dark (muted)
              inactiveThumbColor: Colors.grey.shade400,
              inactiveTrackColor: Colors.grey.shade700,
            ),
          ],
        ),
        if (widget.data['showCta'] != false) ...[
          const SizedBox(height: 12),
          _EditorTextField(
            label: 'Texto botón',
            value: widget.data['ctaText']?.toString() ?? '',
            onChanged: (v) => _updateField('ctaText', v),
          ),
          const SizedBox(height: 12),
          _EditorTextField(
            label: 'Link botón',
            value: widget.data['ctaLink']?.toString() ?? '',
            onChanged: (v) => _updateField('ctaLink', v),
          ),
        ],
        const SizedBox(height: 16),
        Text('Opacidad overlay',
            style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1)),
        Slider(
          value: (widget.data['overlayOpacity'] as num?)?.toDouble() ?? 0.5,
          min: 0,
          max: 1,
          divisions: 10,
          activeColor: const Color(0xFF00A09D),
          onChanged: (v) => _updateField('overlayOpacity', v),
        ),
      ],
    );
  }
}

// ============================================================================
// PARTNERS BANNER BLOCK CONTROLS
// ============================================================================
class _PartnersBannerBlockControls extends StatefulWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _PartnersBannerBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  @override
  State<_PartnersBannerBlockControls> createState() =>
      _PartnersBannerBlockControlsState();
}

class _PartnersBannerBlockControlsState
    extends State<_PartnersBannerBlockControls> {
  List<String> get _items {
    final raw = widget.data['items'];
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    return [];
  }

  void _updateField(String field, dynamic value) {
    widget.provider.updateBlockData(widget.blockId, field, value);
  }

  void _updateItem(int index, String value) {
    final items = List<String>.from(_items);
    if (index < items.length) {
      items[index] = value;
      _updateField('items', items);
    }
  }

  void _addItem() {
    final items = List<String>.from(_items);
    items.add('Nuevo elemento');
    _updateField('items', items);
  }

  void _removeItem(int index) {
    final items = List<String>.from(_items);
    if (items.length > 1) {
      items.removeAt(index);
      _updateField('items', items);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditorTextField(
          label: 'Título superior',
          value: widget.data['title']?.toString() ?? '',
          onChanged: (v) => _updateField('title', v),
        ),
        const SizedBox(height: 12),
        _EditorTextField(
          label: 'URL Imagen de fondo',
          value: widget.data['imageUrl']?.toString() ?? '',
          onChanged: (v) => _updateField('imageUrl', v),
        ),
        const SizedBox(height: 20),
        Text('Elementos de lista',
            style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1)),
        const SizedBox(height: 8),
        ..._items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: _EditorTextField(
                    label: 'Elemento ${index + 1}',
                    value: item,
                    onChanged: (v) => _updateItem(index, v),
                  ),
                ),
                if (_items.length > 1)
                  IconButton(
                    icon: Icon(Icons.remove_circle_outline,
                        color: Colors.red.shade300, size: 20),
                    onPressed: () => _removeItem(index),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          );
        }),
        const SizedBox(height: 8),
        _AddItemButton(
          label: 'Agregar elemento',
          onPressed: _addItem,
        ),
      ],
    );
  }
}

// ============================================================================
// BRAND LOGOS BLOCK CONTROLS
// Editor for brand logos carousel/grid
// ============================================================================
class _BrandLogosBlockControls extends StatefulWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _BrandLogosBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  @override
  State<_BrandLogosBlockControls> createState() =>
      _BrandLogosBlockControlsState();
}

class _BrandLogosBlockControlsState extends State<_BrandLogosBlockControls> {
  int _currentIndex = 0;

  List<Map<String, dynamic>> get _brands {
    final raw = widget.data['brands'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  void _updateField(String field, dynamic value) {
    widget.provider.updateBlockData(widget.blockId, field, value);
  }

  void _updateBrand(int index, String field, String value) {
    final brands = List<Map<String, dynamic>>.from(_brands);
    if (index < brands.length) {
      brands[index] = Map<String, dynamic>.from(brands[index]);
      brands[index][field] = value;
      _updateField('brands', brands);
    }
  }

  void _addBrand() {
    final brands = List<Map<String, dynamic>>.from(_brands);
    brands.add({
      'name': '',
      'imageUrl': '',
      'link': '',
    });
    _updateField('brands', brands);
    // Navigate to the new brand
    setState(() => _currentIndex = brands.length - 1);
  }

  void _removeBrand(int index) {
    final brands = List<Map<String, dynamic>>.from(_brands);
    if (brands.length > 1) {
      brands.removeAt(index);
      _updateField('brands', brands);
      // Adjust current index if needed
      if (_currentIndex >= brands.length) {
        setState(() => _currentIndex = brands.length - 1);
      }
    }
  }

  void _goToPrevious() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
    }
  }

  void _goToNext() {
    if (_currentIndex < _brands.length - 1) {
      setState(() => _currentIndex++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brands = _brands;
    // Ensure current index is valid
    if (_currentIndex >= brands.length && brands.isNotEmpty) {
      _currentIndex = brands.length - 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditorTextField(
          label: 'Título de la sección',
          value: widget.data['title']?.toString() ?? 'MARCAS',
          onChanged: (v) => _updateField('title', v),
        ),
        const SizedBox(height: 12),
        _EditorTextField(
          label: 'Color de acento (línea bajo título)',
          value: widget.data['accentColor']?.toString() ?? '',
          onChanged: (v) => _updateField('accentColor', v),
          hint: '#E53935 o dejar vacío',
        ),
        const SizedBox(height: 16),
        // Logo size selector
        const Text(
          'TAMAÑO DE LOGOS',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _LogoSizeOption(
              label: 'S',
              tooltip: 'Pequeño',
              value: 'small',
              currentValue: widget.data['logoSize']?.toString() ?? 'medium',
              onTap: () => _updateField('logoSize', 'small'),
            ),
            const SizedBox(width: 8),
            _LogoSizeOption(
              label: 'M',
              tooltip: 'Mediano',
              value: 'medium',
              currentValue: widget.data['logoSize']?.toString() ?? 'medium',
              onTap: () => _updateField('logoSize', 'medium'),
            ),
            const SizedBox(width: 8),
            _LogoSizeOption(
              label: 'L',
              tooltip: 'Grande',
              value: 'large',
              currentValue: widget.data['logoSize']?.toString() ?? 'medium',
              onTap: () => _updateField('logoSize', 'large'),
            ),
            const SizedBox(width: 8),
            _LogoSizeOption(
              label: 'XL',
              tooltip: 'Extra Grande',
              value: 'xlarge',
              currentValue: widget.data['logoSize']?.toString() ?? 'medium',
              onTap: () => _updateField('logoSize', 'xlarge'),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Horizontal brand navigator
        Row(
          children: [
            const Text(
              'MARCAS',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF00A09D).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${brands.length}',
                style: const TextStyle(
                  color: Color(0xFF00A09D),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            // Add button
            GestureDetector(
              onTap: _addBrand,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00A09D),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 14, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'Nueva',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Navigation arrows + current brand indicator
        if (brands.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Left arrow
              GestureDetector(
                onTap: _currentIndex > 0 ? _goToPrevious : null,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _currentIndex > 0
                        ? const Color(0xFF2D2D2D)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color:
                          _currentIndex > 0 ? Colors.white24 : Colors.white12,
                    ),
                  ),
                  child: Icon(
                    Icons.chevron_left,
                    size: 20,
                    color: _currentIndex > 0 ? Colors.white70 : Colors.white24,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Page indicators
              ...List.generate(brands.length, (index) {
                final isSelected = index == _currentIndex;
                return GestureDetector(
                  onTap: () => setState(() => _currentIndex = index),
                  child: Container(
                    width: isSelected ? 24 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color:
                          isSelected ? const Color(0xFF00A09D) : Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                );
              }),
              const SizedBox(width: 12),
              // Right arrow
              GestureDetector(
                onTap: _currentIndex < brands.length - 1 ? _goToNext : null,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _currentIndex < brands.length - 1
                        ? const Color(0xFF2D2D2D)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _currentIndex < brands.length - 1
                          ? Colors.white24
                          : Colors.white12,
                    ),
                  ),
                  child: Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: _currentIndex < brands.length - 1
                        ? Colors.white70
                        : Colors.white24,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Current brand editor (compact)
          _BrandLogoEditorCompact(
            index: _currentIndex,
            brand: brands[_currentIndex],
            totalBrands: brands.length,
            onUpdateField: (field, value) =>
                _updateBrand(_currentIndex, field, value),
            onRemove:
                brands.length > 1 ? () => _removeBrand(_currentIndex) : null,
          ),
        ] else ...[
          // Empty state
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              children: [
                Icon(Icons.branding_watermark_outlined,
                    size: 32, color: Colors.white38),
                const SizedBox(height: 8),
                Text(
                  'Sin marcas',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  'Agrega logos de marcas que trabajas',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Size selector button for brand logos
class _LogoSizeOption extends StatelessWidget {
  final String label;
  final String tooltip;
  final String value;
  final String currentValue;
  final VoidCallback onTap;

  const _LogoSizeOption({
    required this.label,
    required this.tooltip,
    required this.value,
    required this.currentValue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == currentValue;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 36,
          decoration: BoxDecoration(
            color:
                isSelected ? const Color(0xFF00A09D) : const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? const Color(0xFF00A09D) : Colors.white24,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Individual brand logo editor with image upload (legacy - kept for compatibility)
class _BrandLogoEditor extends StatefulWidget {
  final int index;
  final Map<String, dynamic> brand;
  final int totalBrands;
  final void Function(String field, String value) onUpdateField;
  final VoidCallback onRemove;

  const _BrandLogoEditor({
    required this.index,
    required this.brand,
    required this.totalBrands,
    required this.onUpdateField,
    required this.onRemove,
  });

  @override
  State<_BrandLogoEditor> createState() => _BrandLogoEditorState();
}

class _BrandLogoEditorState extends State<_BrandLogoEditor> {
  bool _isUploading = false;

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();

    try {
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 400,
        maxHeight: 200,
      );

      if (pickedFile == null) return;

      setState(() => _isUploading = true);

      final bytes = await pickedFile.readAsBytes();
      final fileName = pickedFile.name;

      // Upload to Supabase Storage
      final supabase = Supabase.instance.client;
      final uniqueName = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
      final path = 'brand-logos/$uniqueName';

      await supabase.storage.from('vinabike-assets').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: true,
            ),
          );

      final publicUrl =
          supabase.storage.from('vinabike-assets').getPublicUrl(path);

      widget.onUpdateField('imageUrl', publicUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Logo subido correctamente'),
            backgroundColor: Color(0xFF00A09D),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error uploading brand logo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error al subir: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.brand['name']?.toString() ?? '';
    final imageUrl = widget.brand['imageUrl']?.toString() ?? '';
    final link = widget.brand['link']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with reorder buttons and delete
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00A09D).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Marca ${widget.index + 1}',
                  style: const TextStyle(
                    color: Color(0xFF00A09D),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              if (widget.totalBrands > 1)
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      size: 16, color: Colors.red.shade300),
                  onPressed: widget.onRemove,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  tooltip: 'Eliminar',
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Image upload area
          GestureDetector(
            onTap: _isUploading ? null : _pickAndUploadImage,
            child: Container(
              width: double.infinity,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: imageUrl.isNotEmpty
                      ? const Color(0xFF00A09D)
                      : Colors.white.withValues(alpha: 0.2),
                  width: imageUrl.isNotEmpty ? 2 : 1,
                  style:
                      imageUrl.isEmpty ? BorderStyle.solid : BorderStyle.solid,
                ),
              ),
              child: _isUploading
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF00A09D),
                        ),
                      ),
                    )
                  : imageUrl.isNotEmpty
                      ? Stack(
                          children: [
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Image.network(
                                  imageUrl,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(Icons.broken_image,
                                        color: Colors.white38, size: 32);
                                  },
                                ),
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00A09D),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(Icons.edit,
                                    size: 12, color: Colors.white),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.cloud_upload_outlined,
                                size: 28,
                                color: Colors.white.withValues(alpha: 0.4)),
                            const SizedBox(height: 4),
                            Text(
                              'Click para subir logo',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                            Text(
                              'PNG transparente recomendado',
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                            ),
                          ],
                        ),
            ),
          ),
          const SizedBox(height: 12),
          // Name field
          _EditorTextField(
            label: 'Nombre (opcional)',
            value: name,
            onChanged: (v) => widget.onUpdateField('name', v),
            hint: 'Ej: Shimano, SRAM...',
          ),
          const SizedBox(height: 8),
          // Link field (optional)
          _EditorTextField(
            label: 'Enlace (opcional)',
            value: link,
            onChanged: (v) => widget.onUpdateField('link', v),
            hint: 'https://marca.com',
          ),
        ],
      ),
    );
  }
}

/// Compact brand logo editor for horizontal navigation
class _BrandLogoEditorCompact extends StatefulWidget {
  final int index;
  final Map<String, dynamic> brand;
  final int totalBrands;
  final void Function(String field, String value) onUpdateField;
  final VoidCallback? onRemove;

  const _BrandLogoEditorCompact({
    required this.index,
    required this.brand,
    required this.totalBrands,
    required this.onUpdateField,
    this.onRemove,
  });

  @override
  State<_BrandLogoEditorCompact> createState() =>
      _BrandLogoEditorCompactState();
}

class _BrandLogoEditorCompactState extends State<_BrandLogoEditorCompact> {
  bool _isUploading = false;

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();

    try {
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 400,
        maxHeight: 200,
      );

      if (pickedFile == null) return;

      setState(() => _isUploading = true);

      final bytes = await pickedFile.readAsBytes();
      final fileName = pickedFile.name;

      // Upload to Supabase Storage
      final supabase = Supabase.instance.client;
      final uniqueName = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
      final path = 'brand-logos/$uniqueName';

      await supabase.storage.from('vinabike-assets').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: true,
            ),
          );

      final publicUrl =
          supabase.storage.from('vinabike-assets').getPublicUrl(path);

      widget.onUpdateField('imageUrl', publicUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Logo subido correctamente'),
            backgroundColor: Color(0xFF00A09D),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error uploading brand logo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error al subir: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.brand['name']?.toString() ?? '';
    final imageUrl = widget.brand['imageUrl']?.toString() ?? '';
    final link = widget.brand['link']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: const Color(0xFF00A09D).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with brand number and delete
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00A09D),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Marca ${widget.index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              if (widget.onRemove != null)
                GestureDetector(
                  onTap: widget.onRemove,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(Icons.delete_outline,
                        size: 16, color: Colors.red.shade300),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Image upload area
          GestureDetector(
            onTap: _isUploading ? null : _pickAndUploadImage,
            child: Container(
              width: double.infinity,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: imageUrl.isNotEmpty
                      ? const Color(0xFF00A09D)
                      : Colors.white.withValues(alpha: 0.2),
                  width: imageUrl.isNotEmpty ? 2 : 1,
                ),
              ),
              child: _isUploading
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF00A09D),
                        ),
                      ),
                    )
                  : imageUrl.isNotEmpty
                      ? Stack(
                          children: [
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Image.network(
                                  imageUrl,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(Icons.broken_image,
                                        color: Colors.white38, size: 32);
                                  },
                                ),
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00A09D),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(Icons.edit,
                                    size: 12, color: Colors.white),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.cloud_upload_outlined,
                                size: 32,
                                color: Colors.white.withValues(alpha: 0.4)),
                            const SizedBox(height: 6),
                            Text(
                              'Click para subir logo',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                            Text(
                              'PNG transparente recomendado',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                            ),
                          ],
                        ),
            ),
          ),
          const SizedBox(height: 12),

          // Name field
          _EditorTextField(
            label: 'Nombre (opcional)',
            value: name,
            onChanged: (v) => widget.onUpdateField('name', v),
            hint: 'Ej: Shimano, SRAM...',
          ),
          const SizedBox(height: 8),

          // Link field
          _EditorTextField(
            label: 'Enlace (opcional)',
            value: link,
            onChanged: (v) => widget.onUpdateField('link', v),
            hint: 'https://marca.com',
          ),
        ],
      ),
    );
  }
}

/// Controls for editing the site header (special element, not a block)
class _HeaderBlockControls extends StatefulWidget {
  final WebsiteEditModeProvider provider;

  const _HeaderBlockControls({super.key, required this.provider});

  @override
  State<_HeaderBlockControls> createState() => _HeaderBlockControlsState();
}

class _HeaderBlockControlsState extends State<_HeaderBlockControls> {
  final _storeNameController = TextEditingController();
  final _logoUrlController = TextEditingController();
  final _topBannerController = TextEditingController();
  final _headerBgColorController = TextEditingController();

  // Header style options
  String _headerStyle = 'solid';
  String _headerColorMode = 'light';
  bool _showTopBanner = false;
  bool _headerShadow = true;
  List<Map<String, String>> _navLinks = [];

  bool _loaded = false;
  bool _hasLocalChanges = false;

  final _headerStyles = {
    'solid': 'Sólido',
    'transparent': 'Transparente (sobre hero)',
    'sticky': 'Fijo al hacer scroll'
  };
  final _headerColorModes = {
    'light': 'Claro (texto oscuro)',
    'dark': 'Oscuro (texto claro)'
  };

  @override
  void initState() {
    super.initState();
    // Add listeners to detect changes
    _storeNameController.addListener(_onFieldChanged);
    _logoUrlController.addListener(_onFieldChanged);
    _topBannerController.addListener(_onFieldChanged);
    _headerBgColorController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (_loaded && !_hasLocalChanges) {
      _hasLocalChanges = true;
      _syncPendingSettingsToProvider();
    }
  }

  void _markChanged() {
    if (!_hasLocalChanges) {
      _hasLocalChanges = true;
    }
    _syncPendingSettingsToProvider();
  }

  /// Sync current header settings to provider for saving with main button
  void _syncPendingSettingsToProvider() {
    debugPrint(
        '🔧 [HeaderSettings] Syncing to provider: header_show_top_banner = $_showTopBanner');
    widget.provider.updateHeaderSettings({
      'store_name': _storeNameController.text,
      'logo_url': _logoUrlController.text,
      'top_banner_text': _topBannerController.text,
      'header_style': _headerStyle,
      'header_color_mode': _headerColorMode,
      'header_show_top_banner': _showTopBanner.toString(),
      'header_shadow': _headerShadow.toString(),
      'header_bg_color': _headerBgColorController.text,
      'header_nav_links': jsonEncode(_navLinks),
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loadSettings();
      _loaded = true;
    }
  }

  void _loadSettings() {
    final service = context.read<WebsiteService>();
    _storeNameController.text = service.getSetting('store_name', '');
    _logoUrlController.text = service.getSetting('logo_url', '');
    _topBannerController.text =
        service.getSetting('top_banner_text', 'Envíos a todo Chile');
    _headerBgColorController.text =
        service.getSetting('header_bg_color', '#FFFFFF');

    _headerStyle = service.getSetting('header_style', 'solid');
    _headerColorMode = service.getSetting('header_color_mode', 'light');
    final rawBannerValue =
        service.getSetting('header_show_top_banner', 'false');
    _showTopBanner = rawBannerValue == 'true';
    debugPrint(
        '🔧 [HeaderSettings] _loadSettings: rawBannerValue="$rawBannerValue" → _showTopBanner=$_showTopBanner');
    _headerShadow = service.getSetting('header_shadow', 'true') == 'true';

    // Parse nav links from JSON
    final navLinksJson = service.getSetting('header_nav_links', '');
    if (navLinksJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(navLinksJson) as List;
        _navLinks =
            decoded.map((e) => Map<String, String>.from(e as Map)).toList();
      } catch (_) {
        _navLinks = _getDefaultNavLinks();
      }
    } else {
      _navLinks = _getDefaultNavLinks();
    }
  }

  List<Map<String, String>> _getDefaultNavLinks() {
    return [
      {'label': 'Inicio', 'url': '/tienda'},
      {'label': 'Productos', 'url': '/tienda/productos'},
      {'label': 'Contacto', 'url': '/tienda/contacto'},
    ];
  }

  @override
  void dispose() {
    _storeNameController.dispose();
    _logoUrlController.dispose();
    _topBannerController.dispose();
    _headerBgColorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with icon and title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child:
                    const Icon(Icons.web_asset, color: Colors.blue, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Header',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Encabezado del sitio',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Logo section
          _SectionHeader('Logo'),
          const SizedBox(height: 12),
          _LogoUploader(
            currentUrl: _logoUrlController.text,
            onChanged: (url) {
              _logoUrlController.text = url;
              _markChanged();
              setState(() {});
            },
          ),

          const SizedBox(height: 20),

          // Store name
          _EditorTextField(
            label: 'Nombre de la tienda',
            value: _storeNameController.text,
            controller: _storeNameController,
            onChanged: (_) {},
            hint: 'Mi Tienda',
          ),

          const SizedBox(height: 16),

          // Top banner text
          _EditorTextField(
            label: 'Texto del banner superior',
            value: _topBannerController.text,
            controller: _topBannerController,
            onChanged: (_) {},
            hint: 'Envíos gratis en compras sobre \$50.000',
          ),

          const SizedBox(height: 24),

          // ========== HEADER STYLE SECTION ==========
          _SectionHeader('Estilo del header'),
          const SizedBox(height: 12),

          // Header style dropdown
          _buildDropdown(
            label: 'Modo de visualización',
            value: _headerStyle,
            items: _headerStyles.keys.toList(),
            labels: _headerStyles,
            onChanged: (v) {
              setState(() => _headerStyle = v!);
              _markChanged();
            },
          ),
          const SizedBox(height: 12),

          // Color mode dropdown
          _buildDropdown(
            label: 'Modo de color',
            value: _headerColorMode,
            items: _headerColorModes.keys.toList(),
            labels: _headerColorModes,
            onChanged: (v) {
              setState(() => _headerColorMode = v!);
              _markChanged();
            },
          ),
          const SizedBox(height: 12),

          // Background color
          _ColorField(
            label: 'Color de fondo',
            controller: _headerBgColorController,
          ),
          const SizedBox(height: 16),

          // Toggles
          _buildSwitch(
            label: 'Mostrar banner superior',
            value: _showTopBanner,
            onChanged: (v) {
              debugPrint(
                  '🔧 [HeaderSettings] Toggling showTopBanner: $_showTopBanner → $v');
              setState(() {
                _showTopBanner = v;
                _hasLocalChanges = true;
              });
              // Sync AFTER setState completes with new value
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _syncPendingSettingsToProvider();
              });
            },
          ),
          const SizedBox(height: 8),
          _buildSwitch(
            label: 'Mostrar sombra',
            value: _headerShadow,
            onChanged: (v) {
              setState(() {
                _headerShadow = v;
                _hasLocalChanges = true;
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _syncPendingSettingsToProvider();
              });
            },
          ),

          const SizedBox(height: 24),

          // ========== NAVIGATION LINKS SECTION ==========
          _SectionHeader('Links de navegación'),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D2D),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.menu, color: Colors.white70, size: 16),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Menú de navegación',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                    IconButton(
                      onPressed: _addNavLink,
                      icon: const Icon(Icons.add,
                          color: Colors.white70, size: 18),
                      tooltip: 'Agregar link',
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_navLinks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Sin links. Haz clic en + para agregar.',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  )
                else
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _navLinks.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex--;
                        final item = _navLinks.removeAt(oldIndex);
                        _navLinks.insert(newIndex, item);
                      });
                      _markChanged();
                    },
                    itemBuilder: (context, index) {
                      final link = _navLinks[index];
                      return _NavLinkTile(
                        key: ValueKey('nav_$index'),
                        label: link['label'] ?? '',
                        url: link['url'] ?? '',
                        onEdit: () => _editNavLink(index),
                        onDelete: () {
                          setState(() => _navLinks.removeAt(index));
                          _markChanged();
                        },
                      );
                    },
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Info text - changes are saved with main button
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.blue.shade300),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Los cambios se guardarán al presionar "Guardar" en la barra superior.',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    Map<String, String>? labels,
    required void Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 6),
        MenuAnchor(
          style: MenuStyle(
            backgroundColor: WidgetStateProperty.all(const Color(0xFF2D2D2D)),
            surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
            padding: WidgetStateProperty.all(EdgeInsets.zero),
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
            ),
          ),
          menuChildren: items.map((item) {
            final itemLabel = labels?[item] ?? item;
            return MenuItemButton(
              onPressed: () => onChanged(item),
              style: ButtonStyle(
                backgroundColor: item == value
                    ? WidgetStateProperty.all(
                        Colors.white.withValues(alpha: 0.1))
                    : null,
                foregroundColor: WidgetStateProperty.all(Colors.white),
                padding: WidgetStateProperty.all(
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              child: Container(
                constraints: const BoxConstraints(minWidth: 120),
                child: Text(
                  itemLabel,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            );
          }).toList(),
          builder: (context, controller, child) {
            final selectedLabel = labels?[value] ?? value;
            return InkWell(
              onTap: () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2D2D),
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        selectedLabel,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.expand_more,
                        color: Colors.white54, size: 20),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSwitch({
    required String label,
    required bool value,
    required void Function(bool) onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          // ON state: bright teal color (highlighted)
          activeColor: Colors.white,
          activeTrackColor: const Color(0xFF00A09D),
          // OFF state: dim/dark (muted)
          inactiveThumbColor: Colors.grey.shade400,
          inactiveTrackColor: Colors.grey.shade700,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }

  void _addNavLink() {
    _showNavLinkDialog(
      onSave: (label, url) {
        setState(() => _navLinks.add({'label': label, 'url': url}));
        _markChanged();
      },
    );
  }

  void _editNavLink(int index) {
    final link = _navLinks[index];
    _showNavLinkDialog(
      initialLabel: link['label'] ?? '',
      initialUrl: link['url'] ?? '',
      onSave: (label, url) {
        setState(() => _navLinks[index] = {'label': label, 'url': url});
        _markChanged();
      },
    );
  }

  void _showNavLinkDialog({
    String initialLabel = '',
    String initialUrl = '',
    required void Function(String label, String url) onSave,
  }) {
    final labelController = TextEditingController(text: initialLabel);
    final urlController = TextEditingController(text: initialUrl);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('Link de navegación',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Texto del link',
                labelStyle: TextStyle(color: Colors.white60),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF00A09D))),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: urlController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'URL (ej: /tienda/productos)',
                labelStyle: TextStyle(color: Colors.white60),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF00A09D))),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Cancelar', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () {
              if (labelController.text.isNotEmpty &&
                  urlController.text.isNotEmpty) {
                onSave(labelController.text, urlController.text);
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A09D)),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

/// Controls for editing the site footer (special element, not a block)
class _FooterBlockControls extends StatefulWidget {
  final WebsiteEditModeProvider provider;

  const _FooterBlockControls({super.key, required this.provider});

  @override
  State<_FooterBlockControls> createState() => _FooterBlockControlsState();
}

class _FooterBlockControlsState extends State<_FooterBlockControls> {
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _addressController = TextEditingController();
  final _facebookController = TextEditingController();
  final _instagramController = TextEditingController();
  final _twitterController = TextEditingController();
  final _youtubeController = TextEditingController();
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loadSettings();
      _loaded = true;
    }
  }

  void _loadSettings() {
    final service = context.read<WebsiteService>();
    _emailController.text = service.getSetting('contact_email', '');
    _phoneController.text = service.getSetting('contact_phone', '');
    _whatsappController.text = service.getSetting('whatsapp', '');
    _addressController.text = service.getSetting('contact_address', '');
    _facebookController.text = service.getSetting('facebook_handle', '');
    _instagramController.text = service.getSetting('instagram_handle', '');
    _twitterController.text = service.getSetting('twitter_handle', '');
    _youtubeController.text = service.getSetting('youtube_handle', '');
  }

  Future<void> _saveSettings() async {
    final service = context.read<WebsiteService>();
    await service.saveSettings({
      'contact_email': _emailController.text,
      'contact_phone': _phoneController.text,
      'whatsapp': _whatsappController.text,
      'contact_address': _addressController.text,
      'facebook_handle': _facebookController.text,
      'instagram_handle': _instagramController.text,
      'twitter_handle': _twitterController.text,
      'youtube_handle': _youtubeController.text,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Footer guardado'),
          backgroundColor: Color(0xFF00A09D),
        ),
      );
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _whatsappController.dispose();
    _addressController.dispose();
    _facebookController.dispose();
    _instagramController.dispose();
    _twitterController.dispose();
    _youtubeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with icon and title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.web_asset_off,
                    color: Colors.green, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Footer',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Pie de página del sitio',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Contact section
          _SectionHeader('Contacto'),
          const SizedBox(height: 12),

          _EditorTextField(
            label: 'Email',
            value: _emailController.text,
            controller: _emailController,
            onChanged: (_) {},
            hint: 'contacto@mitienda.cl',
          ),
          const SizedBox(height: 12),

          _EditorTextField(
            label: 'Teléfono',
            value: _phoneController.text,
            controller: _phoneController,
            onChanged: (_) {},
            hint: '+56 2 1234 5678',
          ),
          const SizedBox(height: 12),

          _EditorTextField(
            label: 'WhatsApp',
            value: _whatsappController.text,
            controller: _whatsappController,
            onChanged: (_) {},
            hint: '+56912345678',
          ),
          const SizedBox(height: 12),

          _EditorTextField(
            label: 'Dirección',
            value: _addressController.text,
            controller: _addressController,
            onChanged: (_) {},
            hint: 'Av. Principal 123, Santiago',
          ),

          const SizedBox(height: 20),

          // Social media section
          _SectionHeader('Redes sociales'),
          const SizedBox(height: 12),

          _EditorTextField(
            label: 'Facebook',
            value: _facebookController.text,
            controller: _facebookController,
            onChanged: (_) {},
            hint: 'mitienda',
          ),
          const SizedBox(height: 12),

          _EditorTextField(
            label: 'Instagram',
            value: _instagramController.text,
            controller: _instagramController,
            onChanged: (_) {},
            hint: '@mitienda',
          ),
          const SizedBox(height: 12),

          _EditorTextField(
            label: 'Twitter/X',
            value: _twitterController.text,
            controller: _twitterController,
            onChanged: (_) {},
            hint: '@mitienda',
          ),
          const SizedBox(height: 12),

          _EditorTextField(
            label: 'YouTube',
            value: _youtubeController.text,
            controller: _youtubeController,
            onChanged: (_) {},
            hint: 'mitienda',
          ),

          const SizedBox(height: 24),

          // Save button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saveSettings,
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Guardar footer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A09D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddItemButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _AddItemButton({
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(
            color: const Color(0xFF00A09D).withValues(alpha: 0.5),
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add, color: Color(0xFF00A09D), size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(color: Color(0xFF00A09D), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog for managing website backups
class _BackupsDialog extends StatefulWidget {
  final VoidCallback? onRestoreComplete;

  const _BackupsDialog({this.onRestoreComplete});

  @override
  State<_BackupsDialog> createState() => _BackupsDialogState();
}

class _BackupsDialogState extends State<_BackupsDialog> {
  final WebsiteBackupService _backupService = WebsiteBackupService();
  List<WebsiteBackup> _backups = [];
  bool _isLoading = true;
  bool _isCreating = false;
  bool _isRestoring = false;
  String? _error;

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadBackups() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final backups = await _backupService.loadBackups();
      if (mounted) {
        setState(() {
          _backups = backups;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _createBackup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El nombre es requerido')),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      await _backupService.createBackup(
        name: name,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      );

      _nameController.clear();
      _descriptionController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copia de seguridad creada'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadBackups();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  Future<void> _restoreBackup(WebsiteBackup backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Restaurar copia de seguridad?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Se restaurará: "${backup.name}"'),
            const SizedBox(height: 12),
            const Text(
              'Se creará automáticamente una copia de seguridad del estado actual antes de restaurar.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00A09D),
            ),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isRestoring = true);

    try {
      await _backupService.restoreBackup(backup.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copia de seguridad restaurada'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onRestoreComplete?.call();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isRestoring = false);
      }
    }
  }

  Future<void> _deleteBackup(WebsiteBackup backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar copia de seguridad?'),
        content: Text('Se eliminará: "${backup.name}"'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _backupService.deleteBackup(backup.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copia de seguridad eliminada'),
            backgroundColor: Colors.orange,
          ),
        );
        await _loadBackups();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.backup, color: Color(0xFF00A09D)),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Copias de Seguridad',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Create new backup section
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF2D2D2D),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nueva copia de seguridad',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Nombre (ej: "Antes de rediseño")',
                      hintStyle: TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descriptionController,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Descripción (opcional)',
                      hintStyle: TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isCreating ? null : _createBackup,
                      icon: _isCreating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.add),
                      label: Text(_isCreating
                          ? 'Creando...'
                          : 'Crear copia de seguridad'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00A09D),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Divider
            const Divider(height: 1, color: Colors.white12),

            // Backups list
            Expanded(
              child: Container(
                color: const Color(0xFF1E1E1E),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.error_outline,
                                    color: Colors.red, size: 48),
                                const SizedBox(height: 8),
                                Text(
                                  'Error cargando copias',
                                  style: TextStyle(color: Colors.red),
                                ),
                                TextButton(
                                  onPressed: _loadBackups,
                                  child: const Text('Reintentar'),
                                ),
                              ],
                            ),
                          )
                        : _backups.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.inventory_2_outlined,
                                        color: Colors.white24, size: 48),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'No hay copias de seguridad',
                                      style: TextStyle(color: Colors.white38),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                itemCount: _backups.length,
                                itemBuilder: (context, index) {
                                  final backup = _backups[index];
                                  return _BackupListItem(
                                    backup: backup,
                                    onRestore: () => _restoreBackup(backup),
                                    onDelete: () => _deleteBackup(backup),
                                    isRestoring: _isRestoring,
                                  );
                                },
                              ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackupListItem extends StatelessWidget {
  final WebsiteBackup backup;
  final VoidCallback onRestore;
  final VoidCallback onDelete;
  final bool isRestoring;

  const _BackupListItem({
    required this.backup,
    required this.onRestore,
    required this.onDelete,
    required this.isRestoring,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(8),
        border: backup.isAutoBackup
            ? Border.all(color: Colors.orange.withValues(alpha: 0.3))
            : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: backup.isAutoBackup
              ? Colors.orange.withValues(alpha: 0.2)
              : const Color(0xFF00A09D).withValues(alpha: 0.2),
          child: Icon(
            backup.isAutoBackup ? Icons.autorenew : Icons.backup,
            color:
                backup.isAutoBackup ? Colors.orange : const Color(0xFF00A09D),
            size: 20,
          ),
        ),
        title: Text(
          backup.name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (backup.description != null && backup.description!.isNotEmpty)
              Text(
                backup.description!,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 2),
            Row(
              children: [
                if (backup.isAutoBackup)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'AUTO',
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                Text(
                  dateFormat.format(backup.createdAt.toLocal()),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: isRestoring
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.restore, size: 20),
              color: const Color(0xFF00A09D),
              tooltip: 'Restaurar',
              onPressed: isRestoring ? null : onRestore,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: Colors.red.shade300,
              tooltip: 'Eliminar',
              onPressed: isRestoring ? null : onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// Tab for generic block styling (Background, Spacing, etc.)
class _StyleBlockTab extends StatefulWidget {
  final WebsiteEditModeProvider editProvider;

  const _StyleBlockTab({required this.editProvider});

  @override
  State<_StyleBlockTab> createState() => _StyleBlockTabState();
}

class _StyleBlockTabState extends State<_StyleBlockTab> {
  bool _paddingLinked = true;

  @override
  Widget build(BuildContext context) {
    final selectedId = widget.editProvider.selectedBlockId;

    if (selectedId == null) {
      return _buildNoSelection();
    }

    if (selectedId == 'header' || selectedId == 'footer') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'El estilo de ${selectedId == 'header' ? 'Cabecera' : 'Pie de página'} se gestiona en la pestaña "Editar".',
            style: TextStyle(color: Colors.white54, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final block = widget.editProvider.getBlock(selectedId);
    if (block == null) return _buildNoSelection();

    final blockData = Map<String, dynamic>.from(block['block_data'] ?? {});
    final style = Map<String, dynamic>.from(blockData['style'] ?? {});

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ===== BACKGROUND =====
          _buildSectionHeader('Fondo'),
          const SizedBox(height: 12),
          _BackgroundTypeControl(
            style: style,
            onChanged: (key, value) => _updateStyle(selectedId, key, value),
          ),

          const SizedBox(height: 24),

          // ===== PADDING =====
          _buildSectionHeader('Espaciado Interior'),
          const SizedBox(height: 12),
          _FullPaddingControl(
            paddingTop: (style['paddingTop'] as num?)?.toDouble() ?? 64.0,
            paddingRight: (style['paddingRight'] as num?)?.toDouble() ?? 24.0,
            paddingBottom: (style['paddingBottom'] as num?)?.toDouble() ?? 64.0,
            paddingLeft: (style['paddingLeft'] as num?)?.toDouble() ?? 24.0,
            linked: _paddingLinked,
            onLinkedChanged: (v) => setState(() => _paddingLinked = v),
            onChanged: (top, right, bottom, left) {
              _updateStyle(selectedId, 'paddingTop', top);
              _updateStyle(selectedId, 'paddingRight', right);
              _updateStyle(selectedId, 'paddingBottom', bottom);
              _updateStyle(selectedId, 'paddingLeft', left);
            },
          ),

          const SizedBox(height: 24),

          // ===== BORDER =====
          _buildSectionHeader('Borde'),
          const SizedBox(height: 12),
          _BorderControl(
            borderWidth: (style['borderWidth'] as num?)?.toDouble() ?? 0.0,
            borderColor: style['borderColor']?.toString() ?? '#E0E0E0',
            borderStyle: style['borderStyle']?.toString() ?? 'solid',
            borderRadius: (style['borderRadius'] as num?)?.toDouble() ?? 0.0,
            onChanged: (width, color, borderStyle, radius) {
              _updateStyle(selectedId, 'borderWidth', width);
              _updateStyle(selectedId, 'borderColor', color);
              _updateStyle(selectedId, 'borderStyle', borderStyle);
              _updateStyle(selectedId, 'borderRadius', radius);
            },
          ),

          const SizedBox(height: 24),

          // ===== SHADOW =====
          _buildSectionHeader('Sombra'),
          const SizedBox(height: 12),
          _BoxShadowControl(
            enabled: style['shadowEnabled'] == true,
            offsetX: (style['shadowOffsetX'] as num?)?.toDouble() ?? 0.0,
            offsetY: (style['shadowOffsetY'] as num?)?.toDouble() ?? 4.0,
            blur: (style['shadowBlur'] as num?)?.toDouble() ?? 12.0,
            spread: (style['shadowSpread'] as num?)?.toDouble() ?? 0.0,
            color: style['shadowColor']?.toString() ?? 'rgba(0,0,0,0.15)',
            onChanged: (enabled, offsetX, offsetY, blur, spread, color) {
              _updateStyle(selectedId, 'shadowEnabled', enabled);
              _updateStyle(selectedId, 'shadowOffsetX', offsetX);
              _updateStyle(selectedId, 'shadowOffsetY', offsetY);
              _updateStyle(selectedId, 'shadowBlur', blur);
              _updateStyle(selectedId, 'shadowSpread', spread);
              _updateStyle(selectedId, 'shadowColor', color);
            },
          ),
        ],
      ),
    );
  }

  void _updateStyle(String blockId, String key, dynamic value) {
    final block = widget.editProvider.getBlock(blockId);
    if (block == null) return;

    final currentData = Map<String, dynamic>.from(block['block_data'] ?? {});
    final currentStyle = Map<String, dynamic>.from(currentData['style'] ?? {});

    currentStyle[key] = value;
    widget.editProvider.updateBlockData(blockId, 'style', currentStyle);
  }

  Widget _buildNoSelection() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.brush_outlined,
              size: 48,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Selecciona un bloque',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
      ),
    );
  }
}

/// Background control with solid color or gradient option
class _BackgroundTypeControl extends StatelessWidget {
  final Map<String, dynamic> style;
  final Function(String key, dynamic value) onChanged;

  const _BackgroundTypeControl({
    required this.style,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundType = style['backgroundType']?.toString() ?? 'solid';
    final isSolid = backgroundType != 'gradient';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toggle between solid and gradient
        Row(
          children: [
            _buildTypeButton(
                'Sólido', isSolid, () => onChanged('backgroundType', 'solid')),
            const SizedBox(width: 8),
            _buildTypeButton('Degradado', !isSolid,
                () => onChanged('backgroundType', 'gradient')),
          ],
        ),
        const SizedBox(height: 16),

        if (isSolid) ...[
          _BackgroundColorControl(
            currentValue: style['backgroundColor'],
            onChanged: (val) => onChanged('backgroundColor', val),
          ),
        ] else ...[
          // Gradient controls
          const Text('Color inicial',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 8),
          _BackgroundColorControl(
            currentValue: style['gradientColor1'] ?? '#FFFFFF',
            onChanged: (val) => onChanged('gradientColor1', val),
          ),
          const SizedBox(height: 16),
          const Text('Color final',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 8),
          _BackgroundColorControl(
            currentValue: style['gradientColor2'] ?? '#F0F0F0',
            onChanged: (val) => onChanged('gradientColor2', val),
          ),
          const SizedBox(height: 16),
          const Text('Dirección',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 8),
          _GradientDirectionPicker(
            currentDirection:
                style['gradientDirection']?.toString() ?? 'to-bottom',
            onChanged: (dir) => onChanged('gradientDirection', dir),
          ),
        ],
      ],
    );
  }

  Widget _buildTypeButton(String label, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF00A09D).withValues(alpha: 0.2)
                : const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? const Color(0xFF00A09D) : Colors.white12,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF00A09D) : Colors.white54,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Gradient direction picker with 8 direction options
class _GradientDirectionPicker extends StatelessWidget {
  final String currentDirection;
  final Function(String) onChanged;

  const _GradientDirectionPicker({
    required this.currentDirection,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final directions = [
      ('to-top', Icons.arrow_upward, 'Arriba'),
      ('to-top-right', Icons.north_east, 'Arriba Der.'),
      ('to-right', Icons.arrow_forward, 'Derecha'),
      ('to-bottom-right', Icons.south_east, 'Abajo Der.'),
      ('to-bottom', Icons.arrow_downward, 'Abajo'),
      ('to-bottom-left', Icons.south_west, 'Abajo Izq.'),
      ('to-left', Icons.arrow_back, 'Izquierda'),
      ('to-top-left', Icons.north_west, 'Arriba Izq.'),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: directions.map((d) {
        final isSelected = d.$1 == currentDirection;
        return Tooltip(
          message: d.$3,
          child: GestureDetector(
            onTap: () => onChanged(d.$1),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF00A09D)
                    : const Color(0xFF2D2D2D),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected ? const Color(0xFF00A09D) : Colors.white12,
                ),
              ),
              child: Icon(
                d.$2,
                size: 16,
                color: isSelected ? Colors.white : Colors.white54,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Full padding control with all 4 sides and linked toggle
class _FullPaddingControl extends StatelessWidget {
  final double paddingTop;
  final double paddingRight;
  final double paddingBottom;
  final double paddingLeft;
  final bool linked;
  final Function(bool) onLinkedChanged;
  final Function(double, double, double, double) onChanged;

  const _FullPaddingControl({
    required this.paddingTop,
    required this.paddingRight,
    required this.paddingBottom,
    required this.paddingLeft,
    required this.linked,
    required this.onLinkedChanged,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Linked toggle
        Row(
          children: [
            Icon(
              linked ? Icons.link : Icons.link_off,
              size: 16,
              color: linked ? const Color(0xFF00A09D) : Colors.white38,
            ),
            const SizedBox(width: 8),
            Text(
              linked ? 'Valores vinculados' : 'Valores independientes',
              style: TextStyle(
                color: linked ? const Color(0xFF00A09D) : Colors.white38,
                fontSize: 11,
              ),
            ),
            const Spacer(),
            Switch(
              value: linked,
              onChanged: onLinkedChanged,
              activeColor: Colors.white,
              activeTrackColor: const Color(0xFF00A09D),
              inactiveThumbColor: Colors.grey.shade400,
              inactiveTrackColor: Colors.grey.shade700,
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (linked) ...[
          // Single slider that affects all sides proportionally
          _paddingSlider('Vertical', paddingTop, (val) {
            onChanged(val, paddingRight, val, paddingLeft);
          }),
          const SizedBox(height: 12),
          _paddingSlider('Horizontal', paddingLeft, (val) {
            onChanged(paddingTop, val, paddingBottom, val);
          }),
        ] else ...[
          // Individual sliders for each side
          _paddingSlider('Arriba', paddingTop, (val) {
            onChanged(val, paddingRight, paddingBottom, paddingLeft);
          }),
          const SizedBox(height: 8),
          _paddingSlider('Derecha', paddingRight, (val) {
            onChanged(paddingTop, val, paddingBottom, paddingLeft);
          }),
          const SizedBox(height: 8),
          _paddingSlider('Abajo', paddingBottom, (val) {
            onChanged(paddingTop, paddingRight, val, paddingLeft);
          }),
          const SizedBox(height: 8),
          _paddingSlider('Izquierda', paddingLeft, (val) {
            onChanged(paddingTop, paddingRight, paddingBottom, val);
          }),
        ],
      ],
    );
  }

  Widget _paddingSlider(String label, double value, Function(double) onChange) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: const Color(0xFF00A09D),
              inactiveTrackColor: Colors.white10,
              thumbColor: Colors.white,
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value.clamp(0.0, 200.0),
              min: 0,
              max: 200,
              divisions: 40,
              onChanged: onChange,
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '${value.round()}',
            style: const TextStyle(color: Color(0xFF00A09D), fontSize: 11),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

/// Border control with width, color, style, and radius
class _BorderControl extends StatelessWidget {
  final double borderWidth;
  final String borderColor;
  final String borderStyle;
  final double borderRadius;
  final Function(double, String, String, double) onChanged;

  const _BorderControl({
    required this.borderWidth,
    required this.borderColor,
    required this.borderStyle,
    required this.borderRadius,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasBorder = borderWidth > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Quick presets
        Row(
          children: [
            _buildPreset('Ninguno', borderWidth == 0,
                () => onChanged(0, borderColor, borderStyle, borderRadius)),
            const SizedBox(width: 6),
            _buildPreset('Sutil', borderWidth == 1,
                () => onChanged(1, borderColor, 'solid', borderRadius)),
            const SizedBox(width: 6),
            _buildPreset('Medio', borderWidth == 2,
                () => onChanged(2, borderColor, 'solid', borderRadius)),
            const SizedBox(width: 6),
            _buildPreset('Grueso', borderWidth >= 4,
                () => onChanged(4, borderColor, 'solid', borderRadius)),
          ],
        ),

        if (hasBorder) ...[
          const SizedBox(height: 16),
          // Width slider
          _buildSliderRow('Grosor', borderWidth, 0, 20, (val) {
            onChanged(val, borderColor, borderStyle, borderRadius);
          }),
          const SizedBox(height: 12),
          // Style dropdown
          Row(
            children: [
              const SizedBox(
                width: 70,
                child: Text('Estilo',
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
              ),
              Expanded(
                child: Row(
                  children: [
                    _buildStyleButton(
                        'solid', 'Sólido', borderStyle == 'solid'),
                    const SizedBox(width: 6),
                    _buildStyleButton(
                        'dashed', 'Rayado', borderStyle == 'dashed'),
                    const SizedBox(width: 6),
                    _buildStyleButton(
                        'dotted', 'Puntos', borderStyle == 'dotted'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Color
          const Text('Color',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 8),
          _BorderColorPicker(
            currentColor: borderColor,
            onChanged: (color) =>
                onChanged(borderWidth, color, borderStyle, borderRadius),
          ),
        ],

        const SizedBox(height: 16),
        // Border radius (always show)
        const Text('Esquinas',
            style: TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildRadiusPreset('Ninguna', 0, borderRadius),
            const SizedBox(width: 6),
            _buildRadiusPreset('Sutil', 4, borderRadius),
            const SizedBox(width: 6),
            _buildRadiusPreset('Redondeada', 12, borderRadius),
            const SizedBox(width: 6),
            _buildRadiusPreset('Píldora', 50, borderRadius),
          ],
        ),
        const SizedBox(height: 8),
        _buildSliderRow('Radio', borderRadius, 0, 50, (val) {
          onChanged(borderWidth, borderColor, borderStyle, val);
        }),
      ],
    );
  }

  Widget _buildPreset(String label, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF00A09D).withValues(alpha: 0.2)
                : const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? const Color(0xFF00A09D) : Colors.white12,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF00A09D) : Colors.white54,
                fontSize: 10,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStyleButton(String value, String label, bool isSelected) {
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(borderWidth, borderColor, value, borderRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF00A09D).withValues(alpha: 0.2)
                : const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? const Color(0xFF00A09D) : Colors.white12,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF00A09D) : Colors.white54,
                fontSize: 10,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRadiusPreset(String label, double value, double current) {
    final isSelected = (current - value).abs() < 2;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(borderWidth, borderColor, borderStyle, value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF00A09D).withValues(alpha: 0.2)
                : const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? const Color(0xFF00A09D) : Colors.white12,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF00A09D) : Colors.white54,
                fontSize: 10,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSliderRow(String label, double value, double min, double max,
      Function(double) onChange) {
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: const Color(0xFF00A09D),
              inactiveTrackColor: Colors.white10,
              thumbColor: Colors.white,
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: (max - min).toInt(),
              onChanged: onChange,
            ),
          ),
        ),
        SizedBox(
          width: 30,
          child: Text(
            '${value.round()}',
            style: const TextStyle(color: Color(0xFF00A09D), fontSize: 11),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

/// Border color picker
class _BorderColorPicker extends StatelessWidget {
  final String currentColor;
  final Function(String) onChanged;

  const _BorderColorPicker({
    required this.currentColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = [
      '#E0E0E0', // Light gray
      '#9E9E9E', // Gray
      '#424242', // Dark gray
      '#000000', // Black
      '#00A09D', // Brand teal
      '#FF6D00', // Orange
      '#1976D2', // Blue
      '#D32F2F', // Red
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: colors.map((color) {
        final isSelected = color.toLowerCase() == currentColor.toLowerCase();
        return GestureDetector(
          onTap: () => onChanged(color),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _hexToColor(color),
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.white : Colors.white24,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: isSelected
                ? Icon(Icons.check,
                    size: 14,
                    color: _hexToColor(color).computeLuminance() > 0.5
                        ? Colors.black
                        : Colors.white)
                : null,
          ),
        );
      }).toList(),
    );
  }

  Color _hexToColor(String hex) {
    final buffer = StringBuffer();
    if (hex.length == 6 || hex.length == 7) buffer.write('ff');
    buffer.write(hex.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }
}

/// Box shadow control
class _BoxShadowControl extends StatelessWidget {
  final bool enabled;
  final double offsetX;
  final double offsetY;
  final double blur;
  final double spread;
  final String color;
  final Function(bool, double, double, double, double, String) onChanged;

  const _BoxShadowControl({
    required this.enabled,
    required this.offsetX,
    required this.offsetY,
    required this.blur,
    required this.spread,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Quick presets
        Row(
          children: [
            _buildPreset(
                'Ninguna', !enabled, () => onChanged(false, 0, 0, 0, 0, color)),
            const SizedBox(width: 6),
            _buildPreset('Sutil', enabled && blur <= 8,
                () => onChanged(true, 0, 2, 6, 0, 'rgba(0,0,0,0.1)')),
            const SizedBox(width: 6),
            _buildPreset('Media', enabled && blur > 8 && blur <= 16,
                () => onChanged(true, 0, 4, 12, 0, 'rgba(0,0,0,0.15)')),
            const SizedBox(width: 6),
            _buildPreset('Fuerte', enabled && blur > 16,
                () => onChanged(true, 0, 8, 24, 0, 'rgba(0,0,0,0.2)')),
          ],
        ),

        if (enabled) ...[
          const SizedBox(height: 16),
          _buildSlider('Despl. X', offsetX, -30, 30,
              (val) => onChanged(enabled, val, offsetY, blur, spread, color)),
          const SizedBox(height: 8),
          _buildSlider('Despl. Y', offsetY, -30, 30,
              (val) => onChanged(enabled, offsetX, val, blur, spread, color)),
          const SizedBox(height: 8),
          _buildSlider(
              'Difuminado',
              blur,
              0,
              50,
              (val) =>
                  onChanged(enabled, offsetX, offsetY, val, spread, color)),
          const SizedBox(height: 8),
          _buildSlider('Extensión', spread, -20, 20,
              (val) => onChanged(enabled, offsetX, offsetY, blur, val, color)),
        ],
      ],
    );
  }

  Widget _buildPreset(String label, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF00A09D).withValues(alpha: 0.2)
                : const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? const Color(0xFF00A09D) : Colors.white12,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF00A09D) : Colors.white54,
                fontSize: 10,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlider(String label, double value, double min, double max,
      Function(double) onChange) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: const Color(0xFF00A09D),
              inactiveTrackColor: Colors.white10,
              thumbColor: Colors.white,
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: (max - min).toInt(),
              onChanged: onChange,
            ),
          ),
        ),
        SizedBox(
          width: 30,
          child: Text(
            '${value.round()}',
            style: const TextStyle(color: Color(0xFF00A09D), fontSize: 11),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _BackgroundColorControl extends StatelessWidget {
  final String? currentValue;
  final Function(String?) onChanged;

  const _BackgroundColorControl({this.currentValue, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    // Preset colors maintaining the dark/professional vibe
    final presets = [
      null, // Transparent/None
      '#FFFFFF', // White
      '#F8F9FA', // Light Gray
      '#1A1A1A', // Dark
      '#00A09D', // Brand Primary
      '#2D2D2D', // UI Dark
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: presets.map((color) {
        final isSelected = color == currentValue ||
            (color == null && (currentValue == null || currentValue!.isEmpty));

        if (color == null) {
          return _buildColorOption(
            context,
            color: Colors.transparent,
            isSelected: isSelected,
            isNone: true,
            onTap: () => onChanged(null),
          );
        }

        return _buildColorOption(
          context,
          color: _hexToColor(color),
          isSelected: isSelected,
          onTap: () => onChanged(color),
        );
      }).toList(),
    );
  }

  Color _hexToColor(String hex) {
    final buffer = StringBuffer();
    if (hex.length == 6 || hex.length == 7) buffer.write('ff');
    buffer.write(hex.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  Widget _buildColorOption(
    BuildContext context, {
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
    bool isNone = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? const Color(0xFF00A09D) : Colors.white24,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: isNone
            ? const Icon(Icons.block, size: 16, color: Colors.white54)
            : (isSelected
                ? Icon(
                    Icons.check,
                    size: 16,
                    color: color.computeLuminance() > 0.5
                        ? Colors.black
                        : Colors.white,
                  )
                : null),
      ),
    );
  }
}
