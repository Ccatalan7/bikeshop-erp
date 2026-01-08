import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/constants/storage_constants.dart';
import '../../../shared/services/tenant_service.dart';
import '../models/website_block_definition.dart';
import '../models/website_block_registry.dart';
import '../models/website_block_type.dart';
import '../providers/website_edit_mode_provider.dart';
import '../models/website_page_models.dart';
import '../services/website_backup_service.dart';
import '../services/website_service.dart';
import 'block_resize_handle.dart';
import '../services/google_business_service.dart';
import 'focal_point_picker.dart';

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
  int _previousSelectionVersion = -1;
  bool _ignoreNextSelection = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  void _checkSelection(WebsiteEditModeProvider editProvider) {
    if (!mounted) return;
    final currentSelection = editProvider.selectedBlockId;

    // Check for Canvas element selection changes
    String? currentActiveElementId;
    if (currentSelection != null) {
      try {
        final blockData = editProvider.blocks.firstWhere(
          (b) => b['id'] == currentSelection,
        );
        currentActiveElementId =
            (blockData['block_data'] ?? blockData['data'])?['activeElementId']
                ?.toString();
      } catch (_) {}
    }

    final blockChanged = currentSelection != null &&
        (currentSelection != _previousSelectedBlockId ||
            editProvider.selectionVersion != _previousSelectionVersion);

    final elementChanged = currentActiveElementId != null &&
        currentActiveElementId != _previousActiveElementId;

    if (blockChanged || elementChanged) {
      if (!_ignoreNextSelection) {
        setState(() {
          _activeTab = 'edit';
        });
      }
      // Only reset the flag after processing the change
      _ignoreNextSelection = false;
      _previousSelectedBlockId = currentSelection;
      _previousActiveElementId = currentActiveElementId;
      _previousSelectionVersion = editProvider.selectionVersion;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editProvider = context.watch<WebsiteEditModeProvider>();
    debugPrint(
        '🔧 [WebsiteEditorPanel] build called. isEditMode: ${editProvider.isEditMode}');

    // Check selection changes after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkSelection(editProvider);
    });

    if (!editProvider.isEditMode) {
      debugPrint(
          '🔧 [WebsiteEditorPanel] isEditMode is false, returning SizedBox.shrink()');
      return const SizedBox.shrink();
    }

    return Container(
      width: 380,
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
          _buildTab('add', 'Agregar', Icons.add_box_outlined),
          _buildTab('edit', 'Editar', Icons.edit_outlined),
          _buildTab('page', 'Página', Icons.article_outlined),
          _buildTab('theme', 'Tema', Icons.palette_outlined),
          _buildTab('sync', 'Google', Icons.store_mall_directory_outlined),
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
        return _AddBlocksTab(
          editProvider: editProvider,
          onBlockAdded: () {
            _ignoreNextSelection = true;
          },
        );
      case 'edit':
        return _EditBlockTab(editProvider: editProvider);
      case 'page':
        return _PageSettingsTab(editProvider: editProvider);
      case 'theme':
        return _ThemeTab();
      case 'sync':
        return const _SyncTab();
      default:
        return const SizedBox.shrink();
    }
  }
}

/// Tab for adding new blocks - shows available block types in a grid
class _AddBlocksTab extends StatefulWidget {
  final WebsiteEditModeProvider editProvider;
  final VoidCallback onBlockAdded;

  const _AddBlocksTab({
    required this.editProvider,
    required this.onBlockAdded,
  });

  @override
  State<_AddBlocksTab> createState() => _AddBlocksTabState();
}

class _AddBlocksTabState extends State<_AddBlocksTab> {
  // Drag state for block reordering
  String? _draggingBlockId;
  int? _hoveringBlockIndex;

  WebsiteEditModeProvider get editProvider => widget.editProvider;

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
                : Column(
                    children: List.generate(blocks.length, (index) {
                      // Apply visual reordering during drag
                      var displayIndex = index;
                      if (_draggingBlockId != null &&
                          _hoveringBlockIndex != null) {
                        final draggedOriginalIndex = blocks
                            .indexWhere((b) => b['id'] == _draggingBlockId);
                        if (draggedOriginalIndex >= 0) {
                          if (index == _hoveringBlockIndex) {
                            displayIndex = draggedOriginalIndex;
                          } else if (draggedOriginalIndex <
                                  _hoveringBlockIndex! &&
                              index > draggedOriginalIndex &&
                              index <= _hoveringBlockIndex!) {
                            displayIndex = index - 1;
                          } else if (draggedOriginalIndex >
                                  _hoveringBlockIndex! &&
                              index >= _hoveringBlockIndex! &&
                              index < draggedOriginalIndex) {
                            displayIndex = index + 1;
                          }
                        }
                      }
                      displayIndex = displayIndex.clamp(0, blocks.length - 1);

                      final block = blocks[displayIndex];
                      final id = block['id']?.toString() ?? 'block_$index';
                      final type = (block['block_type'] ?? block['type'] ?? '')
                          .toString();
                      final isVisible = block['is_visible'] ?? true;
                      final isSelected = editProvider.selectedBlockId == id;
                      final isDropTarget = _hoveringBlockIndex == index &&
                          _draggingBlockId != null;

                      return DragTarget<String>(
                        key: ValueKey('block_target_$index'),
                        onWillAcceptWithDetails: (details) => true,
                        onMove: (details) {
                          if (_hoveringBlockIndex != index) {
                            setState(() {
                              _hoveringBlockIndex = index;
                            });
                          }
                        },
                        onAcceptWithDetails: (details) {
                          // Compute reordered list
                          final draggedIndex = blocks
                              .indexWhere((b) => b['id'] == _draggingBlockId);
                          if (draggedIndex >= 0 &&
                              _hoveringBlockIndex != null &&
                              draggedIndex != _hoveringBlockIndex) {
                            var newIndex = _hoveringBlockIndex!;
                            // Adjust for ReorderableListView's convention
                            if (newIndex > draggedIndex) newIndex += 1;
                            editProvider.reorderBlocks(draggedIndex, newIndex);
                          }
                          setState(() {
                            _draggingBlockId = null;
                            _hoveringBlockIndex = null;
                          });
                        },
                        builder: (context, candidateData, rejectedData) {
                          return Container(
                            decoration: BoxDecoration(
                              color: isDropTarget
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : isSelected
                                      ? const Color(0xFF00A09D)
                                          .withValues(alpha: 0.12)
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
                                    Draggable<String>(
                                      data: id,
                                      dragAnchorStrategy:
                                          pointerDragAnchorStrategy,
                                      onDragStarted: () {
                                        setState(() {
                                          _draggingBlockId = id;
                                        });
                                      },
                                      onDraggableCanceled: (_, __) {
                                        setState(() {
                                          _draggingBlockId = null;
                                          _hoveringBlockIndex = null;
                                        });
                                      },
                                      feedback: Material(
                                        color: Colors.transparent,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF2D2D2D),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withValues(alpha: 0.4),
                                                blurRadius: 8,
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.drag_handle,
                                                  color: Colors.white54,
                                                  size: 18),
                                              const SizedBox(width: 8),
                                              Icon(_blockIcon(type),
                                                  color: Colors.white70,
                                                  size: 16),
                                              const SizedBox(width: 8),
                                              Text(
                                                _blockLabel(type),
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      childWhenDragging: const Icon(
                                        Icons.drag_handle,
                                        color: Colors.white12,
                                        size: 18,
                                      ),
                                      child: MouseRegion(
                                        cursor: SystemMouseCursors.grab,
                                        child: const Icon(
                                          Icons.drag_handle,
                                          color: Colors.white38,
                                          size: 18,
                                        ),
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
                                      onPressed: () => editProvider
                                          .toggleBlockVisibility(id),
                                      icon: Icon(
                                        isVisible
                                            ? Icons.visibility
                                            : Icons.visibility_off,
                                        size: 18,
                                        color: isVisible
                                            ? Colors.white54
                                            : Colors.orange.shade300,
                                      ),
                                      tooltip:
                                          isVisible ? 'Ocultar' : 'Mostrar',
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
                      );
                    }),
                  ),
          ),
          const SizedBox(height: 20),

          _buildSection('Estructura', [
            const _BlockOption('hero'),
            const _BlockOption('carousel'),
            const _BlockOption('categoryGrid'),
            const _BlockOption('canvas'),
          ]),
          _buildSection('Elementos', [
            const _BlockOption('text'),
            const _BlockOption('button'),
            const _BlockOption('divider'),
          ]),
          _buildSection('Canvas (arrastrable)', [
            const _BlockOption(
              'canvas_el:text',
              labelOverride: 'Texto',
              iconOverride: Icons.text_fields_rounded,
            ),
            const _BlockOption(
              'canvas_el:button',
              labelOverride: 'Botón',
              iconOverride: Icons.smart_button_rounded,
            ),
            const _BlockOption(
              'canvas_el:image',
              labelOverride: 'Imagen',
              iconOverride: Icons.image_outlined,
            ),
            const _BlockOption(
              'canvas_el:product',
              labelOverride: 'Producto',
              iconOverride: Icons.inventory_2_outlined,
            ),
            const _BlockOption(
              'canvas_el:productsGallery',
              labelOverride: 'Galería productos',
              iconOverride: Icons.grid_view_rounded,
            ),
          ]),
          _buildSection('Contenido', [
            const _BlockOption('products'),
            const _BlockOption('about'),
            const _BlockOption('services'),
            const _BlockOption('features'),
          ]),
          _buildSection('Media', [
            const _BlockOption('gallery'),
            const _BlockOption('videoBanner'),
            const _BlockOption('brandLogos'),
            const _BlockOption('partnersBanner'),
          ]),
          _buildSection('Social', [
            const _BlockOption('testimonials'),
            const _BlockOption('googleReviews'),
            const _BlockOption('team'),
            const _BlockOption('stats'),
          ]),
          _buildSection('Conversión', [
            const _BlockOption('cta'),
            const _BlockOption('pricing'),
            const _BlockOption('contact'),
            const _BlockOption('faq'),
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

            widget.onBlockAdded();
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
    final blockType = _tryParseWebsiteBlockType(type);
    return blockType?.icon ?? Icons.widgets_rounded;
  }

  static String _blockLabel(String type) {
    final blockType = _tryParseWebsiteBlockType(type);
    if (blockType == null) return type;
    return WebsiteBlockRegistry.definitionFor(blockType).title;
  }

  static WebsiteBlockType? _tryParseWebsiteBlockType(String raw) {
    final normalised = raw.trim();
    if (normalised.isEmpty) return null;

    // Parse using the shared helper, but only accept it if it actually matched.
    final parsed = parseWebsiteBlockType(
      normalised,
      fallback: WebsiteBlockType.hero,
    );

    if (parsed.name.toLowerCase() == normalised.toLowerCase()) {
      return parsed;
    }

    // If we fell back to hero for a non-hero raw value, treat as unknown.
    if (parsed == WebsiteBlockType.hero && normalised.toLowerCase() != 'hero') {
      return null;
    }
    return parsed;
  }
}

class _SyncTab extends StatefulWidget {
  const _SyncTab();

  @override
  State<_SyncTab> createState() => _SyncTabState();
}

class _SyncTabState extends State<_SyncTab> {
  @override
  Widget build(BuildContext context) {
    // Only verify context types, do not assume they are ready if generic
    final googleService = context.watch<GoogleBusinessService>();
    final websiteService = context.watch<WebsiteService>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'GOOGLE BUSINESS PROFILE',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Sincroniza tu información de negocio directamente desde Google para mejorar tu SEO y mostrar reseñas.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Colors.white54, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Si al conectar ves “Acceso bloqueado (403)”, no es un bug del editor: Google bloquea el acceso porque este sync usa el scope restringido business.manage.\n\nSolución rápida: en el proyecto de Google Cloud del OAuth configurado en Supabase → OAuth consent screen → Test users, agrega tu correo (ej: vinabikechile@gmail.com).\n\nPara uso público: debes completar la verificación de Google para ese scope.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (googleService.error != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      googleService.error!,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          if (Supabase.instance.client.auth.currentSession?.providerToken !=
              null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF4285F4).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF4285F4).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      color: Color(0xFF4285F4), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Conectado correctamente',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                        Text(
                          'Google Business Profile',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh,
                        color: Colors.white54, size: 18),
                    tooltip: 'Reconectar',
                    onPressed: () => googleService.connect(),
                  ),
                ],
              ),
            )
          else if (googleService.isLinked)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.orange, size: 20),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Falta un paso más',
                          style: TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tu cuenta Google está vinculada, pero necesitamos renovar el permiso para acceder a los datos del negocio.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: googleService.isLoading
                          ? null
                          : () => googleService.connect(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.black,
                      ),
                      child: Text(googleService.isLoading
                          ? 'Conectando...'
                          : 'Autorizar Acceso Google'),
                    ),
                  ),
                ],
              ),
            )
          else
            Center(
              child: ElevatedButton.icon(
                onPressed: googleService.isLoading
                    ? null
                    : () => googleService.connect(),
                icon: googleService.isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add_link, size: 18),
                label: Text(googleService.isLoading
                    ? 'Conectando...'
                    : 'Conectar Cuenta Google'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4285F4),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ),
          const SizedBox(height: 32),
          const Divider(color: Colors.white12),
          const SizedBox(height: 24),
          const Text(
            'ACCIONES',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          _ActionCard(
            title: 'Sincronizar Datos',
            description: 'Importar dirección, horario y teléfono.',
            icon: Icons.sync,
            onTap: () async {
              try {
                final locations = await googleService.fetchLocations();
                if (!context.mounted) return;

                if (locations.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('No se encontraron ubicaciones')),
                  );
                } else {
                  _showLocationSelectionDialog(
                      context, locations, websiteService);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.red),
                  );
                }
              }
            },
          ),
          const SizedBox(height: 12),
          _ActionCard(
            title: 'Sincronizar Reseñas',
            description: 'Descargar últimas reseñas de Google.',
            icon: Icons.reviews,
            onTap: () async {
              try {
                // 1. Get location name from settings (saved in previous step)
                final locationName =
                    websiteService.getSetting('business_google_location_id');

                if (locationName.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Primero debes sincronizar los datos del negocio para obtener la ubicación.')),
                  );
                  return;
                }

                // 2. Fetch reviews
                final reviews = await googleService.fetchReviews(locationName);
                if (!context.mounted) return;

                // 3. Save to settings
                if (reviews.isNotEmpty) {
                  await websiteService.saveSetting(
                      'google_reviews_data', jsonEncode(reviews));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Se descargaron ${reviews.length} reseñas correctamente!'),
                      backgroundColor: const Color(0xFF00A09D),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'No se encontraron reseñas para esta ubicación.')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.red),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  void _showLocationSelectionDialog(BuildContext context,
      List<GoogleLocation> locations, WebsiteService websiteService) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Seleccionar Ubicación',
            style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: locations.length,
            itemBuilder: (context, index) {
              final loc = locations[index];
              return ListTile(
                title: Text(loc.title,
                    style: const TextStyle(color: Colors.white)),
                subtitle: Text(loc.addressLine ?? '',
                    style: const TextStyle(color: Colors.white70)),
                onTap: () {
                  websiteService.saveSetting('business_name', loc.title);
                  websiteService.saveSetting('business_google_location_id',
                      loc.name); // Save ID for reviews
                  if (loc.phone != null) {
                    websiteService.saveSetting('business_phone', loc.phone!);
                  }

                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Datos sincronizados correctamente!'),
                      backgroundColor: Color(0xFF00A09D),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final VoidCallback? onTap;

  const _ActionCard({
    required this.title,
    required this.description,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (isEnabled ? const Color(0xFF00A09D) : Colors.grey)
                    .withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon,
                  color: isEnabled ? const Color(0xFF00A09D) : Colors.grey,
                  size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isEnabled ? Colors.white : Colors.white54,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    description,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (isEnabled)
              const Icon(Icons.arrow_forward_ios,
                  color: Colors.white30, size: 14),
          ],
        ),
      ),
    );
  }
}

class _BlockOption {
  final String type;
  final String? labelOverride;
  final IconData? iconOverride;

  const _BlockOption(
    this.type, {
    this.labelOverride,
    this.iconOverride,
  });

  WebsiteBlockType? get _blockType {
    if (type.startsWith('canvas_el:')) return null;

    final parsed = parseWebsiteBlockType(type, fallback: WebsiteBlockType.hero);
    if (parsed.name.toLowerCase() == type.toLowerCase()) return parsed;
    if (parsed == WebsiteBlockType.hero && type.toLowerCase() != 'hero') {
      return null;
    }
    return parsed;
  }

  String get label {
    if (labelOverride != null) return labelOverride!;
    final blockType = _blockType;
    if (blockType == null) return type;
    return WebsiteBlockRegistry.definitionFor(blockType).title;
  }

  IconData get icon {
    if (iconOverride != null) return iconOverride!;
    final blockType = _blockType;
    return blockType?.icon ?? Icons.widgets_rounded;
  }
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
          const SizedBox(height: 24),
          const Divider(color: Colors.white12),
          const SizedBox(height: 16),
          _BlockStyleControls(
            blockId: selectedId,
            provider: editProvider,
            blockData: block,
          ),
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
    final parsedType = _tryParseWebsiteBlockType(blockType);
    final title = parsedType != null
        ? WebsiteBlockRegistry.definitionFor(parsedType).title
        : blockType;
    final icon = parsedType?.icon ?? Icons.widgets_rounded;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF00A09D).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
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
                title,
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

  WebsiteBlockType? _tryParseWebsiteBlockType(String raw) {
    final normalised = raw.trim();
    if (normalised.isEmpty) return null;

    // Parse using the shared helper, but only accept it if it actually matched.
    final parsed = parseWebsiteBlockType(
      normalised,
      fallback: WebsiteBlockType.hero,
    );

    if (parsed.name.toLowerCase() == normalised.toLowerCase()) {
      return parsed;
    }

    // If we fell back to hero for a non-hero raw value, treat as unknown.
    if (parsed == WebsiteBlockType.hero && normalised.toLowerCase() != 'hero') {
      return null;
    }
    return parsed;
  }

  Widget _buildBlockControls(
      String blockType, Map<String, dynamic> data, String blockId) {
    // Build controls based on block type
    switch (blockType) {
      case 'hero':
      case 'carousel':
        return _CarouselBlockControls(
            data: data, blockId: blockId, provider: editProvider);
      case 'canvas':
        return _CanvasBlockControls(
            data: data, blockId: blockId, provider: editProvider);
      case 'products':
        return _ProductsBlockControls(
            data: data, blockId: blockId, provider: editProvider);
      case 'about':
      case 'categoryGrid':
      case 'partnersBanner':
      case 'brandLogos':
      case 'videoBanner':
        final parsedType = _tryParseWebsiteBlockType(blockType);
        return _GenericBlockControls(
          data: data,
          blockId: blockId,
          provider: editProvider,
          blockType: parsedType,
          rawBlockType: blockType,
        );
      default:
        final parsedType = _tryParseWebsiteBlockType(blockType);
        return _GenericBlockControls(
          data: data,
          blockId: blockId,
          provider: editProvider,
          blockType: parsedType,
          rawBlockType: blockType,
        );
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

  /// Update multiple slide properties atomically
  void _updateSlideMultiple(int index, Map<String, dynamic> updates) {
    final slides = List<Map<String, dynamic>>.from(_slides);
    if (index >= 0 && index < slides.length) {
      slides[index] = {...slides[index], ...updates};
      debugPrint(
          '🎠 [CarouselControls] _updateSlideMultiple: index=$index, keys=${updates.keys.join(", ")}');
      _updateSlides(slides);
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
        const _SectionHeader('IMAGEN DE FONDO'),
        const SizedBox(height: 8),
        _ImagePicker(
          currentUrl: slide['imageUrl']?.toString(),
          onChanged: (url) =>
              _updateSlide(_selectedSlideIndex, 'imageUrl', url),
        ),
        const SizedBox(height: 12),
        // Focal point picker for mobile background alignment
        FocalPointPicker(
          imageUrl: slide['imageUrl']?.toString(),
          focalX: (slide['mobileFocalPointX'] as num?)?.toDouble() ?? 0.5,
          focalY: (slide['mobileFocalPointY'] as num?)?.toDouble() ?? 0.5,
          onChanged: (x, y) {
            // Update both values atomically
            _updateSlideMultiple(_selectedSlideIndex, {
              'mobileFocalPointX': x,
              'mobileFocalPointY': y,
            });
          },
        ),

        const SizedBox(height: 20),

        // Video section
        const _SectionHeader('VIDEO DE FONDO (OPCIONAL)'),
        const SizedBox(height: 8),
        const Text(
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
        const Row(
          children: [
            Expanded(child: Divider(color: Colors.white24)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
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
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Archivo de video cargado',
                    style: TextStyle(color: Colors.green, fontSize: 12),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16, color: Colors.green),
                  onPressed: () =>
                      _updateSlide(_selectedSlideIndex, 'videoFileUrl', ''),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),

        // Overlay settings
        const _SectionHeader('OVERLAY'),
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
        const _SectionHeader('Configuración'),
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
        const _SectionHeader('Imagen de fondo'),
        const SizedBox(height: 8),
        _ImagePicker(
          currentUrl: widget.slide['imageUrl']?.toString(),
          onChanged: (url) => widget.onUpdate('imageUrl', url),
        ),

        const SizedBox(height: 20),
        // Video section
        const Text('VIDEO DE FONDO (OPCIONAL)',
            style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1)),
        const SizedBox(height: 8),
        const Text(
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
        const Row(
          children: [
            Expanded(child: Divider(color: Colors.white24)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
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
                ? const SizedBox(
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
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                const Expanded(
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
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.play_circle_filled,
                    color: Colors.red, size: 16),
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
        const _SectionHeader('Botón'),
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
          .order('name', ascending: true)
          .limit(2000);

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
        const _SectionHeader('FUENTE DE PRODUCTOS'),
        const SizedBox(height: 12),

        // Product source selector
        _buildSourceSelector(),

        const SizedBox(height: 16),

        // Conditional content based on source
        if (_productSource == 'category') _buildCategorySelector(),
        if (_productSource == 'manual') _buildProductSelector(),

        const SizedBox(height: 20),
        const SizedBox(height: 20),
        const _SectionHeader('DISEÑO'),
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
        const Text('Productos por fila',
            style: TextStyle(
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
        const _SectionHeader('MOSTRAR'),
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
        const Text('Seleccionar categoría',
            style: TextStyle(
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
  bool _filterInStock = false;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.selectedIds);
  }

  List<Map<String, dynamic>> get _filteredProducts {
    var list = widget.availableProducts;

    // Filter by stock
    if (_filterInStock) {
      list = list.where((p) {
        final stockQty = (p['inventory_qty'] as num?)?.toInt() ??
            (p['stock_quantity'] as num?)?.toInt() ??
            0;
        return stockQty > 0;
      }).toList();
    }

    if (_searchQuery.isEmpty) return list;

    final query = _searchQuery.toLowerCase();
    return list.where((p) {
      final name = (p['name']?.toString() ?? '').toLowerCase();
      final sku = (p['sku']?.toString() ?? '').toLowerCase();
      // Allow searching by exact ID too
      final id = (p['id']?.toString() ?? '').toLowerCase();
      return name.contains(query) || sku.contains(query) || id == query;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        width: 420,
        height: 560,
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

            // Filters and counts
            Row(
              children: [
                Text(
                  '${_selected.length} seleccionados',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const Spacer(),

                // Minimalistic filter
                InkWell(
                  onTap: () => setState(() => _filterInStock = !_filterInStock),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _filterInStock
                          ? const Color(0xFF00A09D)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _filterInStock
                            ? const Color(0xFF00A09D)
                            : Colors.white24,
                      ),
                    ),
                    child: Text(
                      'Solo con stock',
                      style: TextStyle(
                          color: _filterInStock ? Colors.white : Colors.white54,
                          fontSize: 11,
                          fontWeight: _filterInStock
                              ? FontWeight.w600
                              : FontWeight.normal),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
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

/// CTA block controls
/// Generic block controls for types without specific UI
class _GenericBlockControls extends StatelessWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;
  final WebsiteBlockType? blockType;
  final String? rawBlockType;

  const _GenericBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
    required this.blockType,
    required this.rawBlockType,
  });

  Color _tryParseHexColor(String? value) {
    if (value == null) return Colors.transparent;
    var hex = value.trim();
    if (hex.isEmpty) return Colors.transparent;
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return Colors.transparent;

    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return Colors.transparent;
    return Color(parsed);
  }

  List<String> _toStringList(dynamic value) {
    if (value is List) {
      return value
          .map((e) => e?.toString() ?? '')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (value is String) {
      return value
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  List<Map<String, dynamic>> _toMapList(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    return const [];
  }

  Widget _helpText(String? text) {
    if (text == null || text.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.45),
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildSchemaField({
    required BuildContext context,
    required WebsiteBlockFieldSchema field,
    required Map<String, dynamic> currentData,
    required void Function(dynamic value) setValue,
  }) {
    final raw = currentData[field.key];
    final label = field.label;

    switch (field.type) {
      case WebsiteBlockFieldType.text:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditorTextField(
              label: label,
              value: raw?.toString() ?? (field.defaultValue?.toString() ?? ''),
              onChanged: (v) {
                setValue(v);
                if (field.key == 'videoUrl' && v.trim().isNotEmpty) {
                  // If entering a YouTube URL, clear any uploaded file.
                  if (currentData.containsKey('videoFileUrl')) {
                    provider.updateBlockData(blockId, 'videoFileUrl', '');
                  }
                }
              },
            ),
            _helpText(field.helpText),
          ],
        );
      case WebsiteBlockFieldType.textarea:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditorTextField(
              label: label,
              value: raw?.toString() ?? (field.defaultValue?.toString() ?? ''),
              onChanged: (v) => setValue(v),
              maxLines: 4,
            ),
            _helpText(field.helpText),
          ],
        );
      case WebsiteBlockFieldType.richtext:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditorTextField(
              label: label,
              value: raw?.toString() ?? (field.defaultValue?.toString() ?? ''),
              onChanged: (v) => setValue(v),
              maxLines: 6,
              hint: '<p>...</p>',
            ),
            _helpText(field.helpText ?? 'Acepta HTML.'),
          ],
        );
      case WebsiteBlockFieldType.link:
        final current =
            raw?.toString() ?? (field.defaultValue?.toString() ?? '');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditorTextField(
              label: label,
              value: current,
              onChanged: (v) => setValue(v),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final next = await _pickPageLink(context);
                      if (next != null && next.isNotEmpty) setValue(next);
                    },
                    icon: const Icon(Icons.article_outlined, size: 16),
                    label: const Text('Elegir pgina'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.15)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final next = await _pickCommonLink(context);
                      if (next != null && next.isNotEmpty) setValue(next);
                    },
                    icon: const Icon(Icons.link, size: 16),
                    label: const Text('Enlaces rpidos'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.15)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
            _helpText(field.helpText),
          ],
        );
      case WebsiteBlockFieldType.color:
        final current =
            raw?.toString() ?? (field.defaultValue?.toString() ?? '');
        final preview = _tryParseHexColor(current);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: preview,
                    borderRadius: BorderRadius.circular(6),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _EditorTextField(
                    label: '',
                    value: current,
                    hint: '#RRGGBB',
                    onChanged: (v) => setValue(v),
                  ),
                ),
              ],
            ),
            _helpText(field.helpText),
          ],
        );
      case WebsiteBlockFieldType.image:
        final currentUrl = raw?.toString();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 8),
            _ImagePicker(
              currentUrl: currentUrl,
              onChanged: (url) => setValue(url),
            ),
            _helpText(field.helpText),
          ],
        );
      case WebsiteBlockFieldType.video:
        final currentUrl = raw?.toString();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 8),
            _VideoPicker(
              currentUrl: currentUrl,
              onChanged: (url) {
                setValue(url);
                if (field.key == 'videoFileUrl' && url.trim().isNotEmpty) {
                  // If uploading a file, clear any YouTube URL.
                  provider.updateBlockData(blockId, 'videoUrl', '');
                }
              },
            ),
            _helpText(field.helpText),
          ],
        );
      case WebsiteBlockFieldType.number:
        final min = field.min?.toDouble();
        final max = field.max?.toDouble();
        final step = field.step?.toDouble();
        final currentNum = (raw is num)
            ? raw.toDouble()
            : double.tryParse(raw?.toString() ?? '') ??
                (field.defaultValue is num
                    ? (field.defaultValue as num).toDouble()
                    : 0.0);

        if (min != null && max != null) {
          int? divisions;
          if (step != null && step > 0) {
            final rawDiv = ((max - min) / step).round();
            if (rawDiv > 0 && rawDiv <= 200) divisions = rawDiv;
          }
          final clamped = currentNum.clamp(min, max);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EditorSlider(
                label: label,
                value: clamped,
                min: min,
                max: max,
                divisions: divisions,
                valueLabel: clamped.toStringAsFixed(0),
                onChanged: (v) => setValue(v),
              ),
              _helpText(field.helpText),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditorTextField(
              label: label,
              value: raw?.toString() ?? (field.defaultValue?.toString() ?? ''),
              hint: '0',
              onChanged: (v) {
                final parsed = num.tryParse(v);
                if (parsed != null) setValue(parsed);
              },
            ),
            _helpText(field.helpText),
          ],
        );
      case WebsiteBlockFieldType.toggle:
        final currentBool =
            (raw is bool) ? raw : (raw?.toString().toLowerCase() == 'true');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditorToggle(
              label: label,
              value: currentBool,
              onChanged: (v) => setValue(v),
            ),
            _helpText(field.helpText),
          ],
        );
      case WebsiteBlockFieldType.select:
        final options = field.options
            .map((opt) => (opt.value, opt.label))
            .toList(growable: false);
        final current = raw?.toString() ??
            (field.defaultValue?.toString() ??
                (options.isNotEmpty ? options.first.$1 : ''));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditorDropdown(
              label: label,
              value: current,
              options: options,
              onChanged: (v) => setValue(v),
            ),
            _helpText(field.helpText),
          ],
        );
      case WebsiteBlockFieldType.chips:
        final chips = _toStringList(raw);
        final display = chips.join(', ');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditorTextField(
              label: label,
              value: display,
              hint: 'separado por comas',
              onChanged: (v) {
                final parsed = _toStringList(v);
                setValue(parsed);
              },
              maxLines: 2,
            ),
            _helpText(field.helpText),
          ],
        );
      case WebsiteBlockFieldType.repeater:
        final items = _toMapList(raw);
        final itemLabel = field.itemLabel ?? 'Item';

        Widget buildItemCard(int index) {
          final itemData = items[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
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
                    Text(
                      '$itemLabel #${index + 1}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (index > 0)
                      InkWell(
                        onTap: () {
                          final next = List<Map<String, dynamic>>.from(items);
                          final tmp = next[index - 1];
                          next[index - 1] = next[index];
                          next[index] = tmp;
                          setValue(next);
                        },
                        child: Icon(
                          Icons.arrow_upward,
                          size: 16,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    if (index > 0) const SizedBox(width: 10),
                    if (index < items.length - 1)
                      InkWell(
                        onTap: () {
                          final next = List<Map<String, dynamic>>.from(items);
                          final tmp = next[index + 1];
                          next[index + 1] = next[index];
                          next[index] = tmp;
                          setValue(next);
                        },
                        child: Icon(
                          Icons.arrow_downward,
                          size: 16,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    if (index < items.length - 1) const SizedBox(width: 10),
                    InkWell(
                      onTap: () {
                        final next = List<Map<String, dynamic>>.from(items);
                        next.removeAt(index);
                        setValue(next);
                      },
                      child: Icon(
                        Icons.close,
                        size: 16,
                        color: Colors.red.shade300,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...field.itemFields.map((subField) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildSchemaField(
                      context: context,
                      field: subField,
                      currentData: itemData,
                      setValue: (v) {
                        final nextItems =
                            List<Map<String, dynamic>>.from(items);
                        final nextItem = Map<String, dynamic>.from(itemData);
                        nextItem[subField.key] = v;
                        nextItems[index] = nextItem;
                        setValue(nextItems);
                      },
                    ),
                  );
                }),
              ],
            ),
          );
        }

        final canAdd = field.maxItems == null || items.length < field.maxItems!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 10),
            ...List.generate(items.length, buildItemCard),
            if (canAdd)
              _AddItemButton(
                label: 'Agregar $itemLabel',
                onPressed: () {
                  final next = List<Map<String, dynamic>>.from(items);
                  final seed = <String, dynamic>{};
                  for (final sub in field.itemFields) {
                    seed[sub.key] = sub.defaultValue;
                  }
                  next.add(seed);
                  setValue(next);
                },
              ),
            _helpText(field.helpText),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final parsed = blockType;
    final definition =
        parsed != null ? WebsiteBlockRegistry.definitionFor(parsed) : null;
    final fields = definition?.fields ?? const <WebsiteBlockFieldSchema>[];

    void setFieldValue(String key, dynamic value) {
      provider.updateBlockData(blockId, key, value);

      // Backwards compatibility: historically CTA subtitle lived under
      // 'description'. Keep them in sync so older renderers/data don't drift.
      if (rawBlockType == 'cta' && key == 'subtitle') {
        provider.updateBlockData(blockId, 'description', value);
      }
    }

    if (definition != null && fields.isNotEmpty) {
      final sections = definition.controlSections;
      final fieldByKey = {for (final f in fields) f.key: f};
      final usedKeys = <String>{};

      final sectionWidgets = <Widget>[];
      if (sections.isNotEmpty) {
        for (final section in sections) {
          final sectionFields = section.fieldKeys
              .map((k) => fieldByKey[k])
              .whereType<WebsiteBlockFieldSchema>()
              .toList();

          if (sectionFields.isEmpty) continue;
          usedKeys.addAll(sectionFields.map((f) => f.key));

          sectionWidgets.add(
            _CollapsibleSection(
              title: section.label,
              initiallyExpanded: true,
              children: [
                if (section.description != null &&
                    section.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      section.description!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ...sectionFields.expand((f) sync* {
                  yield _buildSchemaField(
                    context: context,
                    field: f,
                    currentData: data,
                    setValue: (v) => setFieldValue(f.key, v),
                  );
                  yield const SizedBox(height: 16);
                }),
              ],
            ),
          );
          sectionWidgets.add(const SizedBox(height: 12));
        }
      }

      final remainingFields =
          fields.where((f) => !usedKeys.contains(f.key)).toList();
      if (remainingFields.isNotEmpty) {
        sectionWidgets.add(
          _CollapsibleSection(
            title: 'Otros',
            initiallyExpanded: sections.isEmpty,
            children: [
              ...remainingFields.expand((f) sync* {
                yield _buildSchemaField(
                  context: context,
                  field: f,
                  currentData: data,
                  setValue: (v) => setFieldValue(f.key, v),
                );
                yield const SizedBox(height: 16);
              }),
            ],
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...sectionWidgets,
          if (parsed == WebsiteBlockType.hero) ...[
            const SizedBox(height: 12),
            _CollapsibleSection(
              title: 'Foco móvil',
              initiallyExpanded: true,
              children: [
                const _SectionHeader('Imagen de fondo (móvil)'),
                const SizedBox(height: 12),
                FocalPointPicker(
                  imageUrl:
                      (data['imageUrl'] ?? data['backgroundImage'])?.toString(),
                  focalX:
                      (data['mobileFocalPointX'] as num?)?.toDouble() ?? 0.5,
                  focalY:
                      (data['mobileFocalPointY'] as num?)?.toDouble() ?? 0.5,
                  onChanged: (x, y) {
                    provider.updateBlockDataMultiple(
                      blockId,
                      {
                        'mobileFocalPointX': x,
                        'mobileFocalPointY': y,
                      },
                      saveHistory: false,
                    );
                  },
                ),
              ],
            ),
          ],
        ],
      );
    }

    // Legacy fallback: show title/subtitle/description if they exist
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
            onChanged: (v) => setFieldValue('title', v),
          ),
          const SizedBox(height: 16),
        ],
        if (hasSubtitle) ...[
          _EditorTextField(
            label: 'Subtítulo',
            value: data['subtitle']?.toString() ?? '',
            onChanged: (v) => setFieldValue('subtitle', v),
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

  Future<String?> _pickPageLink(BuildContext context) async {
    final websiteService = context.read<WebsiteService>();
    try {
      if (websiteService.pages.isEmpty) {
        await websiteService.loadPages();
      }
    } catch (_) {
      // If load fails (e.g., public store), still show whatever we have.
    }

    final pages = websiteService.pages;
    if (!context.mounted) return null;

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

    if (selected == null) return null;
    return selected.isHome ? '/' : '/pagina/${selected.slug}';
  }

  Future<String?> _pickCommonLink(BuildContext context) async {
    return showDialog<String>(
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
                leading: const Icon(Icons.home_outlined),
                title: const Text('Inicio'),
                subtitle: const Text('/'),
                onTap: () => Navigator.pop(context, '/'),
              ),
              ListTile(
                leading: const Icon(Icons.contact_mail_outlined),
                title: const Text('Contacto'),
                subtitle: const Text('/contacto'),
                onTap: () => Navigator.pop(context, '/contacto'),
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
    // Don't save to history for transient activeElementId changes
    provider.updateBlockData(blockId, 'activeElementId', id,
        saveHistory: false);
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
                      ((active['letterSpacing'] as num?)?.toDouble() ?? 0.0)
                          .toStringAsFixed(1),
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
          .limit(2000);
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
          .limit(2000);

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

/// Page settings tab for page-level SEO (meta title, description)
/// Minimal, clean interface following existing patterns
class _PageSettingsTab extends StatefulWidget {
  final WebsiteEditModeProvider editProvider;

  const _PageSettingsTab({required this.editProvider});

  @override
  State<_PageSettingsTab> createState() => _PageSettingsTabState();
}

class _PageSettingsTabState extends State<_PageSettingsTab> {
  final _metaTitleController = TextEditingController();
  final _metaDescriptionController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasChanges = false;
  WebsitePage? _currentPage;
  String _currentRoute = '';
  bool _isSpecialRoute = false;

  @override
  void initState() {
    super.initState();
    // Use addPostFrameCallback to ensure context is available for router
    WidgetsBinding.instance.addPostFrameCallback((_) => _detectCurrentPage());
  }

  @override
  void dispose() {
    _metaTitleController.dispose();
    _metaDescriptionController.dispose();
    super.dispose();
  }

  Future<void> _detectCurrentPage() async {
    if (!mounted) return;

    // Get current page info from the edit provider (works even outside router context)
    final pageSlug = widget.editProvider.currentPageSlug;
    var newRoute = pageSlug ?? 'inicio';
    if (newRoute.isEmpty) newRoute = 'inicio';

    debugPrint('📄 [PageSettingsTab] Detecting page: $newRoute');

    // Avoid reloading if route hasn't changed
    if (newRoute == _currentRoute && !_isLoading) return;

    setState(() {
      _currentRoute = newRoute;
      _isLoading = true;
    });

    // Check if this is a special route (not a CMS page)
    final specialRoutes = ['productos', 'contacto', 'carrito', 'checkout'];
    _isSpecialRoute = specialRoutes.any((r) => _currentRoute.startsWith(r));

    // Special route check logic preserved, but early return removed.
    // We now attempt to load from DB first for ALL routes.

    await _loadPageData();
  }

  Future<void> _loadPageData() async {
    final pageId = widget.editProvider.currentPageId;
    final pageSlug = widget.editProvider.currentPageSlug ?? _currentRoute;

    // Home page check removed to use standard website_pages table logic

    try {
      final service = context.read<WebsiteService>();
      WebsitePage? page;

      if (pageId != null) {
        page = await service.getPageById(pageId);
      } else {
        page = await service.getPageBySlug(pageSlug);
      }

      if (!mounted) return;

      if (page != null) {
        _currentPage = page;
        _currentRoute = page.slug;
        _metaTitleController.text = page.metaTitle ?? '';
        _metaDescriptionController.text = page.metaDescription ?? '';
        setState(() => _isLoading = false);
      } else {
        // Page not found in DB
        if (_isSpecialRoute) {
          // Fallback: Try loading from legacy website_settings
          final service = context.read<WebsiteService>();
          final routeKey = _currentRoute.split('/').first;
          _metaTitleController.text =
              service.getSetting('seo_${routeKey}_title', '');
          _metaDescriptionController.text =
              service.getSetting('seo_${routeKey}_description', '');
        }
        setState(() {
          // Keep _isSpecialRoute as determined earlier
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading page for SEO: $e');
      if (mounted) {
        setState(() {
          _isSpecialRoute = true;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveSeoSettings() async {
    if (!_hasChanges) return;
    setState(() => _isSaving = true);

    try {
      final service = context.read<WebsiteService>();

      if (_currentPage != null) {
        // DB Page takes precedence (Modern System)
        final updated = _currentPage!.copyWith(
          metaTitle: _metaTitleController.text,
          metaDescription: _metaDescriptionController.text,
        );
        await service.updatePage(updated);
        _currentPage = updated;
      } else if (_isSpecialRoute) {
        // Fallback to legacy settings (Old System)
        final routeKey = _currentRoute.split('/').first;
        await service.saveSettings({
          'seo_${routeKey}_title': _metaTitleController.text,
          'seo_${routeKey}_description': _metaDescriptionController.text,
        });
      }

      if (mounted) {
        setState(() {
          _hasChanges = false;
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SEO guardado'),
            backgroundColor: Color(0xFF00A09D),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _markChanged() {
    if (!_hasChanges) setState(() => _hasChanges = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(color: Color(0xFF00A09D)),
        ),
      );
    }

    final pageName = _currentPage?.slug ?? _currentRoute;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Page header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00A09D).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.article_outlined,
                    color: Color(0xFF00A09D), size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SEO de página',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '/$pageName',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (_hasChanges)
                ElevatedButton(
                  onPressed: _isSaving ? null : _saveSeoSettings,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00A09D),
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Guardar', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: Colors.white12),
          const SizedBox(height: 16),

          // Meta Title
          _buildField(
            label: 'Meta título',
            controller: _metaTitleController,
            hint: 'Título para Google (máx. 60 car.)',
            maxLength: 60,
            helperText: 'Lo que aparece en las búsquedas de Google',
          ),
          const SizedBox(height: 16),

          // Meta Description
          _buildField(
            label: 'Meta descripción',
            controller: _metaDescriptionController,
            hint: 'Descripción para Google (máx. 160 car.)',
            maxLength: 160,
            maxLines: 3,
            helperText: 'Resumen que aparece bajo el título en Google',
          ),
          const SizedBox(height: 24),

          // SEO preview
          _buildSeoPreview(),
        ],
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required String hint,
    int? maxLength,
    int maxLines = 1,
    String? helperText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            if (helperText != null) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: helperText,
                child: Icon(Icons.info_outline,
                    size: 14, color: Colors.white.withValues(alpha: 0.4)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLength: maxLength,
          maxLines: maxLines,
          onChanged: (_) => _markChanged(),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            filled: true,
            fillColor: const Color(0xFF2D2D2D),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            counterStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
          ),
        ),
      ],
    );
  }

  Widget _buildSeoPreview() {
    final title = _metaTitleController.text.isNotEmpty
        ? _metaTitleController.text
        : 'Título de la página';
    final description = _metaDescriptionController.text.isNotEmpty
        ? _metaDescriptionController.text
        : 'Descripción de la página...';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vista previa en Google',
            style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 10,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF1A0DAB),
              fontSize: 16,
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.underline,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            'vinabike.cl › ...',
            style: TextStyle(color: Colors.green.shade700, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Theme tab for global site-wide settings (colors, typography, button styles)
/// Header and Footer are edited via the "Editar" tab when selected
class _ThemeTab extends StatefulWidget {
  @override
  State<_ThemeTab> createState() => _ThemeTabState();
}

class _ThemeTabState extends State<_ThemeTab> {
  // Navigation state
  String? _activeCategory; // null = main menu

  // Colors
  final _primaryColorController = TextEditingController();
  final _accentColorController = TextEditingController();

  // Typography
  String _headingFont = 'Inter';
  String _bodyFont = 'Inter';
  String _headingSize = 'normal';
  String _bodySize = 'normal';

  // Button styles
  String _buttonStyle = 'rounded'; // rounded, sharp, pill
  String _buttonSize = 'medium'; // small, medium, large

  // Page Background
  String _pageBackground = '#FFFFFF';

  bool _loaded = false;
  bool _isSaving = false;

  final _fonts = [
    'Inter',
    'Roboto',
    'Open Sans',
    'Montserrat',
    'Poppins',
    'Lato',
    'Oswald',
    'Raleway',
    'Playfair Display',
    'Merriweather',
  ];

  final _sizes = {
    'small': 'Pequeño',
    'normal': 'Normal',
    'large': 'Grande',
    'xlarge': 'Extra Grande',
  };

  final _buttonSizes = {
    'small': 'Pequeño',
    'medium': 'Mediano',
    'large': 'Grande',
  };

  String _sizeKeyFromStoredValue(
      {required bool isHeading, required String raw}) {
    final parsed = double.tryParse(raw.trim());
    if (parsed == null) return 'normal';

    if (isHeading) {
      if (parsed <= 40) return 'small';
      if (parsed <= 48) return 'normal';
      if (parsed <= 56) return 'large';
      return 'xlarge';
    }

    if (parsed <= 14) return 'small';
    if (parsed <= 16) return 'normal';
    if (parsed <= 18) return 'large';
    return 'xlarge';
  }

  String _storedValueFromSizeKey(
      {required bool isHeading, required String key}) {
    if (isHeading) {
      switch (key) {
        case 'small':
          return '40';
        case 'large':
          return '56';
        case 'xlarge':
          return '64';
        case 'normal':
        default:
          return '48';
      }
    }

    switch (key) {
      case 'small':
        return '14';
      case 'large':
        return '18';
      case 'xlarge':
        return '20';
      case 'normal':
      default:
        return '16';
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadSettings();
      });
      _loaded = true;
    }
  }

  Future<void> _loadSettings() async {
    try {
      final service = context.read<WebsiteService>();
      await service.loadSettings();

      if (mounted) {
        setState(() {
          _primaryColorController.text =
              service.getSetting('theme_primary_color', '#00A09D');
          _accentColorController.text =
              service.getSetting('theme_accent_color', '#FF6D00');
          _headingFont = service.getSetting('theme_heading_font', 'Inter');
          _bodyFont = service.getSetting('theme_body_font', 'Inter');
          _headingSize = _sizeKeyFromStoredValue(
            isHeading: true,
            raw: service.getSetting('theme_heading_size', '48'),
          );
          _bodySize = _sizeKeyFromStoredValue(
            isHeading: false,
            raw: service.getSetting('theme_body_size', '16'),
          );
          _buttonStyle = service.getSetting('button_style', 'rounded');
          _buttonSize = service.getSetting('button_size', 'medium');
          _pageBackground =
              service.getSetting('theme_background_color', '#FFFFFF');
        });
      }
    } catch (e) {
      debugPrint('Error loading theme: $e');
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      final headingSizeValue =
          _storedValueFromSizeKey(isHeading: true, key: _headingSize);
      final bodySizeValue =
          _storedValueFromSizeKey(isHeading: false, key: _bodySize);

      await context.read<WebsiteService>().saveSettings({
        'theme_primary_color': _primaryColorController.text,
        'theme_accent_color': _accentColorController.text,
        'theme_heading_font': _headingFont,
        'theme_body_font': _bodyFont,
        'theme_heading_size': headingSizeValue,
        'theme_body_size': bodySizeValue,
        'theme_background_color': _pageBackground,
        'button_style': _buttonStyle,
        'button_size': _buttonSize,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tema guardado correctamente'),
            backgroundColor: Color(0xFF00A09D),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
    if (_activeCategory != null) {
      return Column(
        children: [
          _buildCategoryHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildCategoryContent(),
            ),
          ),
          _buildSaveFooter(),
        ],
      );
    }

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DISEÑO DEL SITIO',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Personaliza la apariencia global de tu sitio web.',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              _buildMenuItem(
                'Colores',
                'Paleta de colores principal',
                Icons.palette_outlined,
                'colors',
              ),
              _buildMenuItem(
                'Textos',
                'Tipografía y tamaños',
                Icons.text_fields,
                'text',
              ),
              _buildMenuItem(
                'Botones',
                'Estilo de botones',
                Icons.smart_button,
                'buttons',
              ),
              _buildMenuItem(
                'Fondo de página',
                'Color base del sitio',
                Icons.wallpaper,
                'background',
              ),
              _buildMenuItem(
                'Transiciones',
                'Animaciones de página',
                Icons.animation,
                'transitions',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMenuItem(
      String title, String subtitle, IconData icon, String category) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF00A09D)),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: Colors.white24),
        onTap: () => setState(() => _activeCategory = category),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildCategoryHeader() {
    String title = '';
    switch (_activeCategory) {
      case 'colors':
        title = 'Colores';
        break;
      case 'text':
        title = 'Textos';
        break;
      case 'buttons':
        title = 'Botones';
        break;
      case 'background':
        title = 'Fondo';
        break;
      case 'transitions':
        title = 'Transiciones';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => setState(() => _activeCategory = null),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryContent() {
    switch (_activeCategory) {
      case 'colors':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader('COLOR PRINCIPAL'),
            const SizedBox(height: 12),
            _EditorTextField(
              label: 'Color Hex',
              controller: _primaryColorController,
              onChanged: (val) {
                _primaryColorController.text = val;
                context
                    .read<WebsiteEditModeProvider>()
                    .updateThemeSetting('theme_primary_color', val);
              },
              value: _primaryColorController.text,
              hint: '#00A09D',
            ),
            const SizedBox(height: 12),
            _BackgroundColorControl(
              currentValue: _primaryColorController.text,
              onChanged: (val) {
                if (val != null) {
                  setState(() => _primaryColorController.text = val);
                  // Update provider for live preview
                  context
                      .read<WebsiteEditModeProvider>()
                      .updateThemeSetting('theme_primary_color', val);
                }
              },
            ),
            const SizedBox(height: 24),
            const _SectionHeader('COLOR DE ACENTO'),
            const SizedBox(height: 12),
            _EditorTextField(
              label: 'Color Hex',
              controller: _accentColorController,
              onChanged: (val) {
                _accentColorController.text = val;
                context
                    .read<WebsiteEditModeProvider>()
                    .updateThemeSetting('theme_accent_color', val);
              },
              value: _accentColorController.text,
              hint: '#FF6D00',
            ),
            const SizedBox(height: 12),
            _BackgroundColorControl(
              currentValue: _accentColorController.text,
              onChanged: (val) {
                if (val != null) {
                  setState(() => _accentColorController.text = val);
                  // Update provider for live preview
                  context
                      .read<WebsiteEditModeProvider>()
                      .updateThemeSetting('theme_accent_color', val);
                }
              },
            ),
          ],
        );

      case 'text':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader('TÍTULOS'),
            const SizedBox(height: 12),
            _buildDropdown(
              label: 'Fuente',
              value: _headingFont,
              items: _fonts,
              onChanged: (v) {
                if (v == null) return;
                setState(() => _headingFont = v);
                context
                    .read<WebsiteEditModeProvider>()
                    .updateThemeSetting('theme_heading_font', v);
              },
            ),
            const SizedBox(height: 12),
            _buildDropdown(
              label: 'Tamaño Base',
              value: _headingSize,
              items: _sizes.keys.toList(),
              labels: _sizes,
              onChanged: (v) {
                if (v == null) return;
                setState(() => _headingSize = v);
                context.read<WebsiteEditModeProvider>().updateThemeSetting(
                      'theme_heading_size',
                      _storedValueFromSizeKey(isHeading: true, key: v),
                    );
              },
            ),
            const SizedBox(height: 24),
            const _SectionHeader('PARRAFOS'),
            const SizedBox(height: 12),
            _buildDropdown(
              label: 'Fuente',
              value: _bodyFont,
              items: _fonts,
              onChanged: (v) {
                if (v == null) return;
                setState(() => _bodyFont = v);
                context
                    .read<WebsiteEditModeProvider>()
                    .updateThemeSetting('theme_body_font', v);
              },
            ),
            const SizedBox(height: 12),
            _buildDropdown(
              label: 'Tamaño Base',
              value: _bodySize,
              items: _sizes.keys.toList(),
              labels: _sizes,
              onChanged: (v) {
                if (v == null) return;
                setState(() => _bodySize = v);
                context.read<WebsiteEditModeProvider>().updateThemeSetting(
                      'theme_body_size',
                      _storedValueFromSizeKey(isHeading: false, key: v),
                    );
              },
            ),
          ],
        );

      case 'buttons':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader('FORMA'),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildStyleOption('Cuadrado', 'sharp', _buttonStyle == 'sharp'),
                const SizedBox(width: 8),
                _buildStyleOption(
                    'Redondeado', 'rounded', _buttonStyle == 'rounded'),
                const SizedBox(width: 8),
                _buildStyleOption('Píldora', 'pill', _buttonStyle == 'pill'),
              ],
            ),
            const SizedBox(height: 24),
            const _SectionHeader('TAMAÑO'),
            const SizedBox(height: 12),
            _buildDropdown(
              label: 'Tamaño predeterminado',
              value: _buttonSize,
              items: _buttonSizes.keys.toList(),
              labels: _buttonSizes,
              onChanged: (v) => setState(() => _buttonSize = v!),
            ),
          ],
        );

      case 'background':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader('FONDO DEL SITIO'),
            const SizedBox(height: 8),
            const Text(
              'Este color se aplicará al fondo de todas las páginas.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 16),
            _BackgroundColorControl(
              currentValue: _pageBackground,
              onChanged: (val) {
                if (val != null) {
                  setState(() => _pageBackground = val);
                  context
                      .read<WebsiteEditModeProvider>()
                      .updateThemeSetting('theme_background_color', val);
                }
              },
            ),
          ],
        );

      case 'transitions':
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.construction, color: Colors.white24, size: 48),
              SizedBox(height: 16),
              Text(
                'Próximamente',
                style: TextStyle(color: Colors.white54),
              ),
              Text(
                'Configuración de transiciones entre páginas',
                style: TextStyle(color: Colors.white38, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildSaveFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF2D2D2D),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isSaving ? null : _saveSettings,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00A09D),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Guardar cambios'),
        ),
      ),
    );
  }

  Widget _buildStyleOption(String label, String value, bool isSelected) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _buttonStyle = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF00A09D).withValues(alpha: 0.2)
                : const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(
                value == 'pill' ? 20 : (value == 'rounded' ? 8 : 0)),
            border: Border.all(
              color: isSelected ? const Color(0xFF00A09D) : Colors.white12,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF00A09D) : Colors.white70,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    Map<String, String>? labels,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.contains(value) ? value : null,
              isExpanded: true,
              dropdownColor: const Color(0xFF2D2D2D),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              icon: const Icon(Icons.keyboard_arrow_down,
                  color: Colors.white54, size: 20),
              items: items.map((item) {
                return DropdownMenuItem(
                  value: item,
                  child: Text(labels?[item] ?? item),
                );
              }).toList(),
              onChanged: (newValue) {
                debugPrint(
                    '🎛️ [ThemeTab] Dropdown "$label" changed: "$value" -> "${newValue ?? 'null'}"');
                final editProvider = context.read<WebsiteEditModeProvider>();
                debugPrint(
                    '🎨 [ThemeTab] isInEditorContext=${editProvider.isInEditorContext} isEditMode=${editProvider.isEditMode} pendingThemeKeys=${editProvider.pendingThemeSettings.keys.join(', ')}');
                onChanged(newValue);
              },
            ),
          ),
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
      debugPrint('Error uploading logo: $e');
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error subiendo logo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } else {
        _isUploading = false;
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
    final hasLogo = widget.currentUrl != null && widget.currentUrl!.isNotEmpty;

    return Column(
      children: [
        InkWell(
          onTap: _isUploading ? null : _pickAndUploadLogo,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 110,
            width: double.infinity,
            padding: hasLogo && !_isUploading
                ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
                : EdgeInsets.zero,
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D2D),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isUploading
                    ? const Color(0xFF00A09D)
                    : Colors.white.withValues(alpha: 0.1),
                width: _isUploading ? 2 : 1,
              ),
              image: hasLogo && !_isUploading
                  ? DecorationImage(
                      image: NetworkImage(widget.currentUrl!),
                      fit: BoxFit.contain,
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
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF00A09D),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Subiendo logo...',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  )
                : hasLogo
                    ? Align(
                        alignment: Alignment.topRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildActionButton(
                              icon: Icons.edit,
                              tooltip: 'Cambiar logo',
                              onTap: _pickAndUploadLogo,
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
                            'Haz clic para subir logo',
                            style: TextStyle(
                              color: Color(0xFF00A09D),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'JPG, PNG, WebP • Recomendado 500x200',
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

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.8),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
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
          activeThumbColor: Colors.white,
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

class _VideoPicker extends StatefulWidget {
  final String? currentUrl;
  final Function(String) onChanged;

  const _VideoPicker({
    this.currentUrl,
    required this.onChanged,
  });

  @override
  State<_VideoPicker> createState() => _VideoPickerState();
}

class _VideoPickerState extends State<_VideoPicker> {
  bool _isUploading = false;

  bool get _hasVideo =>
      widget.currentUrl != null && widget.currentUrl!.isNotEmpty;

  Future<String> _getTenantId() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) throw Exception('Usuario no autenticado');

    final profileResponse = await Supabase.instance.client
        .from('user_profiles')
        .select('tenant_id')
        .eq('user_id', user.id)
        .single();

    return profileResponse['tenant_id'] as String;
  }

  String _videoContentType(PlatformFile file) {
    final ext = (file.extension ?? '').toLowerCase();
    if (ext == 'mp4') return 'video/mp4';
    if (ext.isNotEmpty) return 'video/$ext';
    return 'video/mp4';
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

      final tenantId = await _getTenantId();

      final fileName =
          'video_${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final storagePath = '$tenantId/videos/$fileName';

      await Supabase.instance.client.storage
          .from('website-assets')
          .uploadBinary(
            storagePath,
            file.bytes!,
            fileOptions: FileOptions(contentType: _videoContentType(file)),
          );

      final publicUrl = Supabase.instance.client.storage
          .from('website-assets')
          .getPublicUrl(storagePath);

      widget.onChanged(publicUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Video subido correctamente'),
            backgroundColor: Color(0xFF00A09D),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('[VideoPicker] Error uploading video: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al subir video: $e'),
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
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isUploading ? null : _uploadVideoFile,
            icon: _isUploading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
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
        if (_hasVideo) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Archivo de video cargado',
                    style: TextStyle(color: Colors.green, fontSize: 12),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: Colors.red.shade300, size: 18),
                  onPressed: () => widget.onChanged(''),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Eliminar video',
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
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
        const Text('Categorías',
            style: TextStyle(
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
          const _SectionHeader('Imagen de categoría'),
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
          const Text('Tamaño',
              style: TextStyle(
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
        const Text('VIDEO DE FONDO',
            style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1)),
        const SizedBox(height: 8),
        const Text(
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
        const Row(
          children: [
            Expanded(child: Divider(color: Colors.white24)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
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
                ? const SizedBox(
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
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                const Expanded(
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
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.play_circle_filled,
                    color: Colors.red, size: 16),
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
              activeThumbColor: Colors.white,
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
        const Text('Opacidad overlay',
            style: TextStyle(
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
        const Text('Elementos de lista',
            style: TextStyle(
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
            child: const Column(
              children: [
                Icon(Icons.branding_watermark_outlined,
                    size: 32, color: Colors.white38),
                SizedBox(height: 8),
                Text(
                  'Sin marcas',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                SizedBox(height: 4),
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
          const _SectionHeader('Logo'),
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
          const _SectionHeader('Estilo del header'),
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
          const _SectionHeader('Links de navegación'),
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
          activeThumbColor: Colors.white,
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
  final _taglineController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _addressController = TextEditingController();
  final _facebookController = TextEditingController();
  final _instagramController = TextEditingController();
  final _twitterController = TextEditingController();
  final _youtubeController = TextEditingController();
  final _tiktokController = TextEditingController();
  bool _loaded = false;

  bool _hasLocalChanges = false;

  String? _selectedFooterSectionId;

  List<String>? _footerSectionOrderOverride;
  final Map<String, List<String>> _footerLinkOrderOverrideBySection = {};

  // Drag state for visual reordering feedback (sections/tabs)
  String? _draggingSectionId;
  int? _hoveringSectionIndex;

  // Drag state for visual reordering feedback (links within a section)
  String? _draggingLinkId;
  int? _hoveringLinkIndex;

  List<WebsiteNavigation> _applyIdOrder(
    List<WebsiteNavigation> items,
    List<String>? orderedIds,
  ) {
    if (orderedIds == null || orderedIds.isEmpty) return items;

    final byId = <String, WebsiteNavigation>{
      for (final i in items) i.id: i,
    };
    final ordered = <WebsiteNavigation>[];
    for (final id in orderedIds) {
      final item = byId[id];
      if (item != null) ordered.add(item);
    }
    for (final item in items) {
      if (!orderedIds.contains(item.id)) {
        ordered.add(item);
      }
    }
    return ordered;
  }

  List<WebsiteNavigation> _getDisplayedFooterSections(WebsiteService service) {
    var sections = List<WebsiteNavigation>.from(service.footerNavigation)
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    sections = _applyIdOrder(sections, _footerSectionOrderOverride);

    // Apply visual reordering during drag
    if (_draggingSectionId != null && _hoveringSectionIndex != null) {
      final draggedIndex =
          sections.indexWhere((s) => s.id == _draggingSectionId);
      if (draggedIndex >= 0 && draggedIndex != _hoveringSectionIndex) {
        final item = sections.removeAt(draggedIndex);
        final insertAt = _hoveringSectionIndex!.clamp(0, sections.length);
        sections.insert(insertAt, item);
      }
    }

    return sections;
  }

  List<WebsiteNavigation> _getDisplayedFooterLinks(WebsiteNavigation section) {
    var links = List<WebsiteNavigation>.from(section.children)
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    links = _applyIdOrder(links, _footerLinkOrderOverrideBySection[section.id]);

    // Apply visual reordering during drag
    if (_draggingLinkId != null && _hoveringLinkIndex != null) {
      final draggedIndex = links.indexWhere((l) => l.id == _draggingLinkId);
      if (draggedIndex >= 0 && draggedIndex != _hoveringLinkIndex) {
        final item = links.removeAt(draggedIndex);
        final insertAt = _hoveringLinkIndex!.clamp(0, links.length);
        links.insert(insertAt, item);
      }
    }

    return links;
  }

  Widget _buildCollapsibleSection({
    required String title,
    required Widget child,
    bool initiallyExpanded = false,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          iconColor: Colors.white70,
          collapsedIconColor: Colors.white54,
          title: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          children: [child],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _taglineController.addListener(_onFieldChanged);
    _emailController.addListener(_onFieldChanged);
    _phoneController.addListener(_onFieldChanged);
    _whatsappController.addListener(_onFieldChanged);
    _addressController.addListener(_onFieldChanged);
    _facebookController.addListener(_onFieldChanged);
    _instagramController.addListener(_onFieldChanged);
    _twitterController.addListener(_onFieldChanged);
    _youtubeController.addListener(_onFieldChanged);
    _tiktokController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (!_loaded) return;
    if (!_hasLocalChanges) _hasLocalChanges = true;
    _syncPendingSettingsToProvider();
  }

  void _syncPendingSettingsToProvider() {
    widget.provider.updateFooterSettings({
      'store_tagline': _taglineController.text,
      'contact_email': _emailController.text,
      'contact_phone': _phoneController.text,
      'whatsapp': _whatsappController.text,
      'contact_address': _addressController.text,
      // Align with public store keys
      'facebook': _facebookController.text,
      'instagram': _instagramController.text,
      'twitter': _twitterController.text,
      'youtube': _youtubeController.text,
      'tiktok': _tiktokController.text,
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
    _taglineController.text = widget.provider.getEffectiveFooterSetting(
      'store_tagline',
      service.getSetting('store_tagline', ''),
    );
    _emailController.text = widget.provider.getEffectiveFooterSetting(
      'contact_email',
      service.getSetting('contact_email', ''),
    );
    _phoneController.text = widget.provider.getEffectiveFooterSetting(
      'contact_phone',
      service.getSetting('contact_phone', ''),
    );
    _whatsappController.text = widget.provider.getEffectiveFooterSetting(
      'whatsapp',
      service.getSetting('whatsapp', ''),
    );
    _addressController.text = widget.provider.getEffectiveFooterSetting(
      'contact_address',
      service.getSetting('contact_address', ''),
    );

    // Backward compatible: prefer new keys used by store, fallback to legacy *_handle.
    _facebookController.text = widget.provider.getEffectiveFooterSetting(
      'facebook',
      service.getSetting('facebook', service.getSetting('facebook_handle', '')),
    );
    _instagramController.text = widget.provider.getEffectiveFooterSetting(
      'instagram',
      service.getSetting(
          'instagram', service.getSetting('instagram_handle', '')),
    );
    _twitterController.text = widget.provider.getEffectiveFooterSetting(
      'twitter',
      service.getSetting('twitter', service.getSetting('twitter_handle', '')),
    );
    _youtubeController.text = widget.provider.getEffectiveFooterSetting(
      'youtube',
      service.getSetting('youtube', service.getSetting('youtube_handle', '')),
    );
    _tiktokController.text = widget.provider.getEffectiveFooterSetting(
      'tiktok',
      service.getSetting('tiktok', service.getSetting('tiktok_handle', '')),
    );
  }

  Future<void> _addFooterSection() async {
    await _showFooterNavDialog(
      title: 'Nueva sección',
      initialIsSection: true,
      onSave: (nav) async {
        final service = context.read<WebsiteService>();
        await service.createNavigation(nav);
      },
    );
  }

  Future<void> _addFooterLink({String? parentId}) async {
    await _showFooterNavDialog(
      title: 'Nuevo enlace',
      initialParentId: parentId,
      initialIsSection: false,
      onSave: (nav) async {
        final service = context.read<WebsiteService>();
        await service.createNavigation(nav);
      },
    );
  }

  Future<void> _editFooterNav(WebsiteNavigation nav) async {
    final isSection = nav.hasChildren && nav.linkType == NavLinkType.action;

    await _showFooterNavDialog(
      title: isSection ? 'Editar sección' : 'Editar enlace',
      existing: nav,
      initialIsSection: isSection,
      initialParentId: nav.parentId,
      onSave: (updated) async {
        final service = context.read<WebsiteService>();
        await service.updateNavigation(updated);
      },
    );
  }

  void _persistFooterSectionOrder(List<String> orderedIds) {
    final editProvider = context.read<WebsiteEditModeProvider>();

    setState(() {
      _footerSectionOrderOverride = orderedIds;
    });

    // Update provider - will be saved when user clicks Guardar
    editProvider.updateFooterSectionOrder(orderedIds);
  }

  void _persistFooterLinkOrder(String parentId, List<String> orderedIds) {
    final editProvider = context.read<WebsiteEditModeProvider>();

    setState(() {
      _footerLinkOrderOverrideBySection[parentId] = orderedIds;
    });

    // Update provider - will be saved when user clicks Guardar
    editProvider.updateFooterLinkOrder(parentId, orderedIds);
  }

  /// Renders the visual content of a footer section tab (for feedback widget).
  /// This does NOT contain a Draggable to avoid infinite recursion.
  Widget _buildFooterSectionTabContent(
    WebsiteNavigation section, {
    required bool isSelected,
    required Color backgroundColor,
  }) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.drag_handle,
              color: Colors.white54,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              section.label,
              style: TextStyle(
                color: section.isVisible ? Colors.white : Colors.orange,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.more_vert, color: Colors.white70, size: 18),
          ],
        ),
      ),
    );
  }

  /// Renders the visual content of a footer link row (for feedback widget).
  /// This does NOT contain a Draggable to avoid infinite recursion.
  Widget _buildFooterLinkRowContent(
    WebsiteNavigation link, {
    required double width,
  }) {
    return Material(
      color: const Color(0xFF2D2D2D),
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      shadowColor: Colors.black54,
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.drag_handle,
              color: Colors.white54,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                link.label,
                style: TextStyle(
                  color: link.isVisible ? Colors.white70 : Colors.orange,
                  fontSize: 13,
                ),
              ),
            ),
            const Icon(Icons.more_vert, color: Colors.white70, size: 18),
          ],
        ),
      ),
    );
  }

  /// Builds a footer link row with Draggable + DragTarget for reordering.
  Widget _buildFooterLinkRow(
    WebsiteNavigation link, {
    required int index,
    required WebsiteNavigation parentSection,
    required double width,
  }) {
    final isDropTarget = _hoveringLinkIndex == index && _draggingLinkId != null;

    return DragTarget<String>(
      key: ValueKey('footer_link_target_$index'),
      onWillAcceptWithDetails: (details) {
        // Always accept - we'll check for actual reordering in onAccept.
        // Note: Can't use `details.data != link.id` because visual reordering
        // moves the dragged item to the hover position, making them equal!
        return true;
      },
      onMove: (details) {
        // Only update if we're at a different index
        // Note: Don't check details.data != link.id because visual reordering
        // makes them equal at the hover position
        if (_hoveringLinkIndex != index) {
          setState(() {
            _hoveringLinkIndex = index;
          });
        }
      },
      onAcceptWithDetails: (details) {
        // Get fresh section from service to avoid stale children
        final service = context.read<WebsiteService>();
        final freshSection = service.footerNavigation.firstWhere(
          (s) => s.id == parentSection.id,
          orElse: () => parentSection,
        );

        // Get base order and apply current drag state
        var orderedLinks = List<WebsiteNavigation>.from(freshSection.children)
          ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
        orderedLinks = _applyIdOrder(
          orderedLinks,
          _footerLinkOrderOverrideBySection[freshSection.id],
        );

        // Apply the visual reorder from drag state
        if (_draggingLinkId != null && _hoveringLinkIndex != null) {
          final draggedIndex =
              orderedLinks.indexWhere((l) => l.id == _draggingLinkId);
          if (draggedIndex >= 0 && draggedIndex != _hoveringLinkIndex) {
            final item = orderedLinks.removeAt(draggedIndex);
            final insertAt = _hoveringLinkIndex!.clamp(0, orderedLinks.length);
            orderedLinks.insert(insertAt, item);
          }
        }

        final currentOrder = orderedLinks.map((l) => l.id).toList();
        _persistFooterLinkOrder(freshSection.id, currentOrder);
        setState(() {
          _draggingLinkId = null;
          _hoveringLinkIndex = null;
        });
      },
      builder: (context, candidateData, rejectedData) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isDropTarget
                ? Colors.white.withValues(alpha: 0.12)
                : const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDropTarget ? Colors.white24 : Colors.white10,
            ),
          ),
          child: Row(
            children: [
              Draggable<String>(
                data: link.id,
                dragAnchorStrategy: pointerDragAnchorStrategy,
                onDragStarted: () {
                  setState(() {
                    _draggingLinkId = link.id;
                  });
                },
                // Note: Don't clear state in onDragEnd - it races with
                // onAcceptWithDetails. Let onAcceptWithDetails handle
                // successful drops, onDraggableCanceled handles failures.
                onDraggableCanceled: (_, __) {
                  setState(() {
                    _draggingLinkId = null;
                    _hoveringLinkIndex = null;
                  });
                },
                feedback: _buildFooterLinkRowContent(link, width: width),
                childWhenDragging: const Icon(
                  Icons.drag_handle,
                  color: Colors.white24,
                  size: 18,
                ),
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: const Icon(
                    Icons.drag_handle,
                    color: Colors.white54,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  link.label,
                  style: TextStyle(
                    color: link.isVisible ? Colors.white70 : Colors.orange,
                    fontSize: 13,
                  ),
                ),
              ),
              _buildFooterItemActionsMenu(link, parent: parentSection),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFooterSectionTab(
    WebsiteNavigation section, {
    required bool isSelected,
    required bool isDropTarget,
  }) {
    final bg = isSelected
        ? const Color(0xFF00A09D).withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.06);

    return Material(
      color: isDropTarget ? Colors.white.withValues(alpha: 0.10) : bg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() {
          _selectedFooterSectionId = section.id;
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle-only drag. Feedback uses non-recursive content builder.
              Draggable<String>(
                data: section.id,
                dragAnchorStrategy: pointerDragAnchorStrategy,
                onDragStarted: () {
                  setState(() {
                    _draggingSectionId = section.id;
                  });
                },
                // Note: Don't clear state in onDragEnd - it races with
                // onAcceptWithDetails. Let onAcceptWithDetails handle
                // successful drops, onDraggableCanceled handles failures.
                onDraggableCanceled: (_, __) {
                  setState(() {
                    _draggingSectionId = null;
                    _hoveringSectionIndex = null;
                  });
                },
                feedback: _buildFooterSectionTabContent(
                  section,
                  isSelected: isSelected,
                  backgroundColor: bg,
                ),
                childWhenDragging: const Icon(
                  Icons.drag_handle,
                  color: Colors.white24,
                  size: 18,
                ),
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: const Icon(
                    Icons.drag_handle,
                    color: Colors.white54,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                section.label,
                style: TextStyle(
                  color: section.isVisible ? Colors.white : Colors.orange,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              _buildFooterItemActionsMenu(section),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooterItemActionsMenu(
    WebsiteNavigation nav, {
    WebsiteNavigation? parent,
  }) {
    return PopupMenuButton<String>(
      tooltip: 'Opciones',
      color: const Color(0xFF2D2D2D),
      icon: const Icon(Icons.more_vert, color: Colors.white70, size: 18),
      onSelected: (value) async {
        switch (value) {
          case 'add_link':
            await _addFooterLink(parentId: nav.id);
            return;
          case 'toggle_visible':
            await _toggleFooterNavVisibility(nav);
            return;
          case 'edit':
            await _editFooterNav(nav);
            return;
          case 'delete':
            await _deleteFooterNav(nav);
            return;
        }
      },
      itemBuilder: (context) {
        final isSection = nav.parentId == null;
        return <PopupMenuEntry<String>>[
          if (isSection)
            const PopupMenuItem(
              value: 'add_link',
              child:
                  Text('Agregar enlace', style: TextStyle(color: Colors.white)),
            ),
          PopupMenuItem(
            value: 'toggle_visible',
            child: Text(
              nav.isVisible ? 'Ocultar' : 'Mostrar',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          const PopupMenuItem(
            value: 'edit',
            child: Text('Editar', style: TextStyle(color: Colors.white)),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'delete',
            child: Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
          ),
        ];
      },
    );
  }

  Future<void> _toggleFooterNavVisibility(WebsiteNavigation nav) async {
    final service = context.read<WebsiteService>();
    await service.updateNavigation(nav.copyWith(isVisible: !nav.isVisible));
  }

  Future<void> _deleteFooterNav(WebsiteNavigation nav) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('Eliminar', style: TextStyle(color: Colors.white)),
        content: Text(
          '¿Eliminar "${nav.label}"?${nav.hasChildren ? "\n\nEsto también eliminará sus enlaces hijos." : ""}',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
                const Text('Cancelar', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final service = context.read<WebsiteService>();
    await service.deleteNavigation(nav.id);
  }

  Future<void> _showFooterNavDialog({
    required String title,
    WebsiteNavigation? existing,
    String? initialParentId,
    required bool initialIsSection,
    required Future<void> Function(WebsiteNavigation nav) onSave,
  }) async {
    final formKey = GlobalKey<FormState>();
    final labelController = TextEditingController(text: existing?.label ?? '');
    final linkValueController =
        TextEditingController(text: existing?.linkValue ?? '');

    var isSection = initialIsSection;
    var isVisible = existing?.isVisible ?? true;
    var showOnDesktop = existing?.showOnDesktop ?? true;
    var showOnMobile = existing?.showOnMobile ?? true;
    var openInNewTab = existing?.openInNewTab ?? false;
    var linkType = existing?.linkType ?? NavLinkType.page;
    var parentId = initialParentId;

    final service = context.read<WebsiteService>();
    final footerParents = service.footerNavigation;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final effectiveIsSection = isSection;

            return AlertDialog(
              backgroundColor: const Color(0xFF2D2D2D),
              title: Text(title, style: const TextStyle(color: Colors.white)),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: labelController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Texto',
                        labelStyle: TextStyle(color: Colors.white60),
                        enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24)),
                        focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF00A09D))),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Requerido';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // Parent selection (optional)
                    DropdownButtonFormField<String?>(
                      value: parentId,
                      dropdownColor: const Color(0xFF2D2D2D),
                      decoration: const InputDecoration(
                        labelText: 'Sección (opcional)',
                        labelStyle: TextStyle(color: Colors.white60),
                        enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24)),
                        focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF00A09D))),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Sin sección',
                              style: TextStyle(color: Colors.white)),
                        ),
                        ...footerParents.map(
                          (p) => DropdownMenuItem<String?>(
                            value: p.id,
                            child: Text(p.label,
                                style: const TextStyle(color: Colors.white)),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() {
                        parentId = v;
                      }),
                    ),
                    const SizedBox(height: 12),

                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Es sección (título)',
                          style: TextStyle(color: Colors.white)),
                      subtitle: const Text(
                        'Una sección es un encabezado con enlaces dentro',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      value: isSection,
                      activeColor: const Color(0xFF00A09D),
                      onChanged: (v) => setState(() {
                        isSection = v;
                        if (isSection) {
                          linkType = NavLinkType.action;
                          linkValueController.text = '';
                        }
                      }),
                    ),
                    const SizedBox(height: 8),

                    if (!effectiveIsSection) ...[
                      DropdownButtonFormField<NavLinkType>(
                        value: linkType,
                        dropdownColor: const Color(0xFF2D2D2D),
                        decoration: const InputDecoration(
                          labelText: 'Tipo',
                          labelStyle: TextStyle(color: Colors.white60),
                          enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white24)),
                          focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFF00A09D))),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: NavLinkType.page,
                              child: Text('Página',
                                  style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(
                              value: NavLinkType.external,
                              child: Text('URL externa',
                                  style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(
                              value: NavLinkType.anchor,
                              child: Text('Ancla (#)',
                                  style: TextStyle(color: Colors.white))),
                        ],
                        onChanged: (v) => setState(() {
                          if (v == null) return;
                          linkType = v;
                        }),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: linkValueController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Destino',
                          labelStyle: const TextStyle(color: Colors.white60),
                          hintText: linkType == NavLinkType.page
                              ? '/productos, /nosotros'
                              : (linkType == NavLinkType.anchor
                                  ? '#seccion'
                                  : 'https://...'),
                          hintStyle: const TextStyle(color: Colors.white38),
                          enabledBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white24)),
                          focusedBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFF00A09D))),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Requerido';
                          }
                          return null;
                        },
                      ),
                      if (linkType == NavLinkType.external)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Abrir en nueva pestaña',
                              style: TextStyle(color: Colors.white)),
                          value: openInNewTab,
                          activeColor: const Color(0xFF00A09D),
                          onChanged: (v) => setState(() => openInNewTab = v),
                        ),
                    ],
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Visible',
                          style: TextStyle(color: Colors.white)),
                      value: isVisible,
                      activeColor: const Color(0xFF00A09D),
                      onChanged: (v) => setState(() => isVisible = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mostrar en escritorio',
                          style: TextStyle(color: Colors.white)),
                      value: showOnDesktop,
                      activeColor: const Color(0xFF00A09D),
                      onChanged: (v) => setState(() => showOnDesktop = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mostrar en móvil',
                          style: TextStyle(color: Colors.white)),
                      value: showOnMobile,
                      activeColor: const Color(0xFF00A09D),
                      onChanged: (v) => setState(() => showOnMobile = v),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar',
                      style: TextStyle(color: Colors.white60)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;

                    final normalizedLinkValue = effectiveIsSection
                        ? ''
                        : linkValueController.text.trim();

                    final nav = WebsiteNavigation(
                      id: existing?.id ?? '',
                      tenantId: existing?.tenantId ?? '',
                      menuLocation: MenuLocation.footer,
                      label: labelController.text.trim(),
                      linkType:
                          effectiveIsSection ? NavLinkType.action : linkType,
                      linkValue: normalizedLinkValue,
                      openInNewTab: (!effectiveIsSection &&
                              linkType == NavLinkType.external)
                          ? openInNewTab
                          : false,
                      parentId: parentId,
                      orderIndex: existing?.orderIndex ?? 0,
                      isVisible: isVisible,
                      showOnDesktop: showOnDesktop,
                      showOnMobile: showOnMobile,
                      createdAt: existing?.createdAt ?? DateTime.now(),
                      updatedAt: DateTime.now(),
                    );

                    await onSave(nav);
                    if (context.mounted) Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00A09D)),
                  child: Text(existing != null ? 'Guardar' : 'Crear'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _taglineController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _whatsappController.dispose();
    _addressController.dispose();
    _facebookController.dispose();
    _instagramController.dispose();
    _twitterController.dispose();
    _youtubeController.dispose();
    _tiktokController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final websiteService = context.watch<WebsiteService>();
    final footerNavItems = websiteService.footerNavigation;

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

          _buildCollapsibleSection(
            title: 'Marca',
            initiallyExpanded: false,
            child: Column(
              children: [
                _EditorTextField(
                  label: 'Eslogan / Tagline',
                  value: _taglineController.text,
                  controller: _taglineController,
                  onChanged: (_) {},
                  hint: 'Todo lo que necesitas para tu bicicleta',
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          _buildCollapsibleSection(
            title: 'Contacto',
            initiallyExpanded: false,
            child: Column(
              children: [
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
              ],
            ),
          ),

          const SizedBox(height: 12),

          _buildCollapsibleSection(
            title: 'Redes sociales',
            initiallyExpanded: false,
            child: Column(
              children: [
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
                const SizedBox(height: 12),
                _EditorTextField(
                  label: 'TikTok',
                  value: _tiktokController.text,
                  controller: _tiktokController,
                  onChanged: (_) {},
                  hint: '@mitienda',
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          _buildCollapsibleSection(
            title: 'Enlaces del footer',
            initiallyExpanded: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Secciones = títulos (columnas) dentro del footer. Se guarda en Navegación (menu_location=footer) y se refleja de inmediato en el preview.',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _AddItemButton(
                        label: 'Agregar sección',
                        onPressed: _addFooterSection,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _AddItemButton(
                        label: 'Agregar enlace',
                        onPressed: () =>
                            _addFooterLink(parentId: _selectedFooterSectionId),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (footerNavItems.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: const Text(
                      'Todavía no hay navegación del footer guardada. Abajo del sitio se ven enlaces “por defecto”.\n\nAgrega una sección/enlace para empezar y quedará guardado acá.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  )
                else
                  Builder(
                    builder: (context) {
                      final sections =
                          _getDisplayedFooterSections(websiteService);

                      final effectiveSelectedId = (_selectedFooterSectionId !=
                                  null &&
                              sections
                                  .any((s) => s.id == _selectedFooterSectionId))
                          ? _selectedFooterSectionId!
                          : sections.first.id;

                      if (effectiveSelectedId != _selectedFooterSectionId) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          setState(() {
                            _selectedFooterSectionId = effectiveSelectedId;
                          });
                        });
                      }

                      final selectedSection = sections.firstWhere(
                        (s) => s.id == effectiveSelectedId,
                        orElse: () => sections.first,
                      );

                      final links = _getDisplayedFooterLinks(selectedSection);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // "Tabs" (sections) as a horizontal reorderable strip
                          SizedBox(
                            height: 40,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children:
                                    List.generate(sections.length, (index) {
                                  final section = sections[index];
                                  final isSelected =
                                      section.id == effectiveSelectedId;

                                  return DragTarget<String>(
                                    onWillAcceptWithDetails: (details) {
                                      return details.data != section.id;
                                    },
                                    onMove: (details) {
                                      if (details.data != section.id &&
                                          _hoveringSectionIndex != index) {
                                        setState(() {
                                          _hoveringSectionIndex = index;
                                        });
                                      }
                                    },
                                    onLeave: (_) {
                                      // Don't clear immediately to avoid flicker
                                    },
                                    onAcceptWithDetails: (details) {
                                      // Get base order from service
                                      var orderedSections =
                                          List<WebsiteNavigation>.from(
                                              websiteService.footerNavigation)
                                            ..sort((a, b) => a.orderIndex
                                                .compareTo(b.orderIndex));
                                      orderedSections = _applyIdOrder(
                                        orderedSections,
                                        _footerSectionOrderOverride,
                                      );

                                      // Apply the visual reorder from drag state
                                      if (_draggingSectionId != null &&
                                          _hoveringSectionIndex != null) {
                                        final draggedIndex =
                                            orderedSections.indexWhere((s) =>
                                                s.id == _draggingSectionId);
                                        if (draggedIndex >= 0 &&
                                            draggedIndex !=
                                                _hoveringSectionIndex) {
                                          final item = orderedSections
                                              .removeAt(draggedIndex);
                                          final insertAt =
                                              _hoveringSectionIndex!.clamp(
                                                  0, orderedSections.length);
                                          orderedSections.insert(
                                              insertAt, item);
                                        }
                                      }

                                      final currentOrder = orderedSections
                                          .map((s) => s.id)
                                          .toList();
                                      _persistFooterSectionOrder(currentOrder);
                                      setState(() {
                                        _draggingSectionId = null;
                                        _hoveringSectionIndex = null;
                                      });
                                    },
                                    builder:
                                        (context, candidateData, rejectedData) {
                                      final isDropTarget =
                                          candidateData.isNotEmpty;
                                      return Container(
                                        margin: const EdgeInsets.only(right: 8),
                                        child: ConstrainedBox(
                                          constraints:
                                              const BoxConstraints.tightFor(
                                                  height: 40),
                                          child: _buildFooterSectionTab(
                                            section,
                                            isSelected: isSelected,
                                            isDropTarget: isDropTarget,
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                }),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Selected section header + quick add
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2D2D2D),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    selectedSection.label,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add,
                                      color: Colors.white70),
                                  tooltip: 'Agregar enlace',
                                  onPressed: () => _addFooterLink(
                                      parentId: selectedSection.id),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          if (links.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: const Text(
                                'Esta sección no tiene enlaces todavía.',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
                            )
                          else
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final listWidth = constraints.maxWidth;
                                return Column(
                                  children:
                                      List.generate(links.length, (index) {
                                    final link = links[index];
                                    return _buildFooterLinkRow(
                                      link,
                                      index: index,
                                      parentSection: selectedSection,
                                      width: listWidth,
                                    );
                                  }),
                                );
                              },
                            ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),

          const SizedBox(height: 24),
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
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
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
                      hintStyle: const TextStyle(color: Colors.white38),
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
                      hintStyle: const TextStyle(color: Colors.white38),
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
                                const Icon(Icons.error_outline,
                                    color: Colors.red, size: 48),
                                const SizedBox(height: 8),
                                const Text(
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
                            ? const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.inventory_2_outlined,
                                        color: Colors.white24, size: 48),
                                    SizedBox(height: 8),
                                    Text(
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
/// New optimized block style controls for inline editing
class _BlockStyleControls extends StatefulWidget {
  final String blockId;
  final WebsiteEditModeProvider provider;
  final Map<String, dynamic> blockData;

  const _BlockStyleControls({
    required this.blockId,
    required this.provider,
    required this.blockData,
  });

  @override
  State<_BlockStyleControls> createState() => _BlockStyleControlsState();
}

class _BlockStyleControlsState extends State<_BlockStyleControls> {
  bool _paddingLinked = true;

  void _updateStyle(String key, dynamic value) {
    final currentData =
        Map<String, dynamic>.from(widget.blockData['block_data'] ?? {});
    final currentStyle = Map<String, dynamic>.from(currentData['style'] ?? {});

    currentStyle[key] = value;
    widget.provider.updateBlockData(widget.blockId, 'style', currentStyle);
  }

  Map<String, dynamic> get _style {
    return widget.blockData['block_data']?['style'] ?? {};
  }

  @override
  Widget build(BuildContext context) {
    return _CollapsibleSection(
      title: 'DISEÑO Y ESTILO',
      icon: Icons.brush_outlined,
      initiallyExpanded: false,
      children: [
        // Background
        const _SectionHeader('Fondo del bloque'),
        const SizedBox(height: 8),
        _BackgroundTypeControl(
          style: _style,
          onChanged: (key, value) => _updateStyle(key, value),
        ),
        const SizedBox(height: 20),

        // Padding
        const _SectionHeader('Relleno (Padding)'),
        const SizedBox(height: 12),
        _FullPaddingControl(
          paddingTop: (_style['paddingTop'] as num?)?.toDouble() ?? 40.0,
          paddingRight: (_style['paddingRight'] as num?)?.toDouble() ?? 20.0,
          paddingBottom: (_style['paddingBottom'] as num?)?.toDouble() ?? 40.0,
          paddingLeft: (_style['paddingLeft'] as num?)?.toDouble() ?? 20.0,
          linked: _paddingLinked,
          onLinkedChanged: (v) => setState(() => _paddingLinked = v),
          onChanged: (top, right, bottom, left) {
            final newStyle = Map<String, dynamic>.from(_style);
            newStyle['paddingTop'] = top;
            newStyle['paddingRight'] = right;
            newStyle['paddingBottom'] = bottom;
            newStyle['paddingLeft'] = left;
            widget.provider.updateBlockData(widget.blockId, 'style', newStyle);
          },
        ),
        const SizedBox(height: 24),

        // Border
        const _SectionHeader('Borde'),
        const SizedBox(height: 12),
        _BorderControl(
          borderWidth: (_style['borderWidth'] as num?)?.toDouble() ?? 0.0,
          borderColor: _style['borderColor']?.toString() ?? '#E0E0E0',
          borderStyle: _style['borderStyle']?.toString() ?? 'solid',
          borderRadius: (_style['borderRadius'] as num?)?.toDouble() ?? 0.0,
          onChanged: (width, color, borderStyle, radius) {
            final newStyle = Map<String, dynamic>.from(_style);
            newStyle['borderWidth'] = width;
            newStyle['borderColor'] = color;
            newStyle['borderStyle'] = borderStyle;
            newStyle['borderRadius'] = radius;
            widget.provider.updateBlockData(widget.blockId, 'style', newStyle);
          },
        ),
        const SizedBox(height: 24),

        // Shadow
        const _SectionHeader('Sombra'),
        const SizedBox(height: 12),
        _BoxShadowControl(
          enabled: _style['shadowEnabled'] == true,
          offsetX: (_style['shadowOffsetX'] as num?)?.toDouble() ?? 0.0,
          offsetY: (_style['shadowOffsetY'] as num?)?.toDouble() ?? 4.0,
          blur: (_style['shadowBlur'] as num?)?.toDouble() ?? 12.0,
          spread: (_style['shadowSpread'] as num?)?.toDouble() ?? 0.0,
          color: _style['shadowColor']?.toString() ?? 'rgba(0,0,0,0.15)',
          onChanged: (enabled, offsetX, offsetY, blur, spread, color) {
            final newStyle = Map<String, dynamic>.from(_style);
            newStyle['shadowEnabled'] = enabled;
            newStyle['shadowOffsetX'] = offsetX;
            newStyle['shadowOffsetY'] = offsetY;
            newStyle['shadowBlur'] = blur;
            newStyle['shadowSpread'] = spread;
            newStyle['shadowColor'] = color;
            widget.provider.updateBlockData(widget.blockId, 'style', newStyle);
          },
        ),
      ],
    );
  }

  // Helper text controls removed as they are built-in now
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
              activeThumbColor: Colors.white,
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
            data: const SliderThemeData(
              activeTrackColor: Color(0xFF00A09D),
              inactiveTrackColor: Colors.white10,
              thumbColor: Colors.white,
              trackHeight: 2,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
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
            data: const SliderThemeData(
              activeTrackColor: Color(0xFF00A09D),
              inactiveTrackColor: Colors.white10,
              thumbColor: Colors.white,
              trackHeight: 2,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
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
            data: const SliderThemeData(
              activeTrackColor: Color(0xFF00A09D),
              inactiveTrackColor: Colors.white10,
              thumbColor: Colors.white,
              trackHeight: 2,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
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
