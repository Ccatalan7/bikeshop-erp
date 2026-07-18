import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/constants/storage_constants.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/widgets/safe_layout_builder.dart';
import '../models/website_block_definition.dart';
import '../models/website_block_registry.dart';
import '../models/website_block_type.dart';
import '../models/website_font_registry.dart';
import '../models/website_action.dart';
import '../models/canvas_element_factory.dart';
import '../models/website_editor_drag_payload.dart';
import '../providers/website_edit_mode_provider.dart';
import '../models/website_page_models.dart';
import '../services/website_backup_service.dart';
import '../services/website_background_removal_service.dart';
import '../services/website_media_service.dart';
import '../services/website_service.dart';
import 'block_resize_handle.dart';
import '../services/google_business_service.dart';
import 'focal_point_picker.dart';
import 'text_formatting_toolbar.dart';
import 'website_link_value_editor.dart';
import 'website_action_editor.dart';
import 'website_background_removal_dialog.dart';
import 'website_color_picker.dart';
import 'website_media_picker.dart';
import 'website_workspace_scope.dart';

/// Sanitize filename for Supabase Storage (remove spaces and special chars)
String _sanitizeFileName(String fileName) {
  String sanitized = fileName
      .replaceAll(RegExp(r'[^\w\s\-\.]'), '_') // Replace special chars
      .replaceAll(RegExp(r'\s+'), '_') // Replace spaces with underscore
      .replaceAll(RegExp(r'_+'), '_') // Collapse multiple underscores
      .replaceAll(RegExp(r'^_+|_+$'), ''); // Trim leading/trailing underscores
  if (!sanitized.contains('.')) {
    sanitized = '$sanitized.png';
  }
  return sanitized;
}

/// Professional side panel editor for website blocks
/// Clean, functional, and elegant interface
class WebsiteEditorPanel extends StatefulWidget {
  final Future<void> Function()? onSave;
  final Future<void> Function()? onRestoreComplete;
  final VoidCallback? onDiscard;

  const WebsiteEditorPanel({
    super.key,
    this.onSave,
    this.onRestoreComplete,
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

    final currentActiveElementId = editProvider.selectedCanvasElementId;

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

    // Check selection changes after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkSelection(editProvider);
    });

    if (!editProvider.isEditMode) {
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
          Builder(
            builder: (context) {
              final hasChanges = editProvider.hasUnsavedChanges;
              return ElevatedButton(
                onPressed: hasChanges
                    ? () async {
                        if (widget.onSave != null) {
                          await widget.onSave!();
                        }
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00A09D),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      const Color(0xFF00A09D).withValues(alpha: 0.5),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                ),
                child: const Text('Guardar', style: TextStyle(fontSize: 13)),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showBackupsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => _BackupsDialog(
        onRestoreComplete: widget.onRestoreComplete,
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
  _AddPanelMode _mode = _AddPanelMode.layers;
  String _insertQuery = '';

  WebsiteEditModeProvider get editProvider => widget.editProvider;

  @override
  Widget build(BuildContext context) {
    final blocks = editProvider.blocks;
    const categoryOrder = [
      'Estructura',
      'Elementos',
      'Contenido',
      'Media',
      'Social',
      'Conversión',
    ];
    final blockOptionsByCategory = <String, List<_BlockOption>>{};
    for (final definition in WebsiteBlockRegistry.all()) {
      if (definition.type == WebsiteBlockType.footer) continue;
      final query = _insertQuery.trim().toLowerCase();
      if (query.isNotEmpty &&
          !definition.title.toLowerCase().contains(query) &&
          !definition.type.name.toLowerCase().contains(query) &&
          !definition.type.editorCategory.toLowerCase().contains(query)) {
        continue;
      }
      blockOptionsByCategory
          .putIfAbsent(definition.type.editorCategory, () => [])
          .add(_BlockOption(definition.type.name));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<_AddPanelMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: _AddPanelMode.layers,
                  icon: Icon(Icons.layers_outlined, size: 17),
                  label: Text('Capas'),
                ),
                ButtonSegment(
                  value: _AddPanelMode.insert,
                  icon: Icon(Icons.add_box_outlined, size: 17),
                  label: Text('Insertar'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (value) =>
                  setState(() => _mode = value.first),
            ),
          ),
          const SizedBox(height: 18),
          // =========================
          // PAGE STRUCTURE (Wix-like)
          // =========================
          if (_mode == _AddPanelMode.layers) ...[
            const Text(
              'CAPAS DE LA PÁGINA',
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
                        final type =
                            (block['block_type'] ?? block['type'] ?? '')
                                .toString();
                        final isVisible = block['is_visible'] ?? true;
                        final isSelected = editProvider.selectedBlockId == id;
                        final isDropTarget = _hoveringBlockIndex == index &&
                            _draggingBlockId != null;

                        return DragTarget<WebsiteEditorDragPayload>(
                          key: ValueKey('block_target_$index'),
                          onWillAcceptWithDetails: (details) =>
                              details.data is ExistingWebsiteBlockDragPayload,
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
                              editProvider.reorderBlocks(
                                  draggedIndex, newIndex);
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
                                      Draggable<WebsiteEditorDragPayload>(
                                        data:
                                            ExistingWebsiteBlockDragPayload(id),
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
                                        child: const MouseRegion(
                                          cursor: SystemMouseCursors.grab,
                                          child: Icon(
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
          ],
          if (_mode == _AddPanelMode.insert) ...[
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Buscar bloque o elemento',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _insertQuery = value),
            ),
            const SizedBox(height: 12),
            for (final category in categoryOrder.take(2))
              if (blockOptionsByCategory[category]?.isNotEmpty == true)
                _buildSection(category, blockOptionsByCategory[category]!),
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
                'canvas_el:shape',
                labelOverride: 'Forma',
                iconOverride: Icons.rectangle_outlined,
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
            for (final category in categoryOrder.skip(2))
              if (blockOptionsByCategory[category]?.isNotEmpty == true)
                _buildSection(category, blockOptionsByCategory[category]!),
          ],
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
      builder: (context) => Draggable<WebsiteEditorDragPayload>(
        data: option.type.startsWith('canvas_el:')
            ? CanvasElementDragPayload(
                option.type.replaceFirst('canvas_el:', ''),
              )
            : NewWebsiteBlockDragPayload(option.type),
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

enum _AddPanelMode { layers, insert }

class _SyncTab extends StatefulWidget {
  const _SyncTab();

  @override
  State<_SyncTab> createState() => _SyncTabState();
}

class _SyncTabState extends State<_SyncTab> {
  bool _attemptedProviderTokenEnsure = false;

  @override
  Widget build(BuildContext context) {
    // Only verify context types, do not assume they are ready if generic
    final googleService = context.watch<GoogleBusinessService>();
    final websiteService = context.watch<WebsiteService>();
    final hasProviderToken = googleService.hasProviderToken;
    final hasSavedGoogleBusinessData =
        _hasSavedGoogleBusinessData(websiteService);

    if (!_attemptedProviderTokenEnsure &&
        googleService.isLinked &&
        !hasProviderToken) {
      _attemptedProviderTokenEnsure = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        googleService.ensureProviderToken(timeout: const Duration(seconds: 3));
      });
    }

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
          if (hasProviderToken)
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
          else if (hasSavedGoogleBusinessData)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF00A09D).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF00A09D).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle,
                      color: Color(0xFF00A09D), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Google conectado',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                        Text(
                          'Los datos del negocio siguen guardados. Para actualizar horarios, dirección o reseñas desde Google, renueva el permiso.',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 11,
                              height: 1.35),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh,
                        color: Colors.white54, size: 18),
                    tooltip: 'Renovar acceso',
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
            description: hasProviderToken
                ? 'Importar dirección, horario y teléfono.'
                : 'Renovar permiso para actualizar desde Google.',
            icon: Icons.sync,
            onTap: () async {
              try {
                final hasAccess = await _ensureGoogleApiAccess(
                  context,
                  googleService,
                );
                if (!hasAccess || !context.mounted) return;

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
            description: hasProviderToken
                ? 'Descargar últimas reseñas de Google.'
                : 'Renovar permiso para descargar reseñas.',
            icon: Icons.reviews,
            onTap: () async {
              try {
                final hasAccess = await _ensureGoogleApiAccess(
                  context,
                  googleService,
                );
                if (!hasAccess) return;
                if (!context.mounted) return;

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

  bool _hasSavedGoogleBusinessData(WebsiteService websiteService) {
    const keys = [
      'business_google_location_id',
      'google_maps_place_id',
      'google_business_regular_hours',
      'business_hours_json',
      'business_google_maps_url',
      'seo_google_maps_url',
      'business_google_review_url',
      'google_reviews_data',
    ];

    return keys.any((key) => websiteService.getSetting(key).trim().isNotEmpty);
  }

  Future<bool> _ensureGoogleApiAccess(
    BuildContext context,
    GoogleBusinessService googleService,
  ) async {
    if (googleService.hasProviderToken) return true;

    if (googleService.isLinked) {
      final restored = await googleService.ensureProviderToken(
        timeout: const Duration(seconds: 3),
      );
      if (restored) return true;
    }

    if (!context.mounted) return false;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Los datos guardados siguen conectados. Para refrescarlos desde Google, renueva el permiso.',
        ),
      ),
    );
    await googleService.connect();
    return false;
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
                onTap: () async {
                  final settings = <String, String>{
                    'business_name': loc.title,
                    'business_google_location_id': loc.name,
                  };

                  if (loc.phone != null) {
                    settings['business_phone'] = loc.phone!;
                    settings['contact_phone'] = loc.phone!;
                    settings['seo_phone'] = loc.phone!;
                  }

                  if (loc.addressLine != null) {
                    settings['contact_address'] = loc.addressLine!;
                  }
                  if (loc.addressStreet != null) {
                    settings['seo_address_street'] = loc.addressStreet!;
                  }
                  if (loc.addressCity != null) {
                    settings['seo_address_city'] = loc.addressCity!;
                  }
                  if (loc.addressRegion != null) {
                    settings['seo_address_region'] = loc.addressRegion!;
                  }
                  if (loc.addressPostalCode != null) {
                    settings['seo_address_postal'] = loc.addressPostalCode!;
                  }
                  if (loc.addressCountry != null) {
                    settings['seo_address_country'] = loc.addressCountry!;
                  }

                  if (loc.hours != null && loc.hours!.isNotEmpty) {
                    settings['google_business_regular_hours'] =
                        jsonEncode(loc.hours);
                  }

                  final mapsUrl = loc.mapsUri;
                  if (mapsUrl != null && mapsUrl.trim().isNotEmpty) {
                    settings['business_google_maps_url'] = mapsUrl.trim();
                    settings['seo_google_maps_url'] = mapsUrl.trim();
                  }

                  final reviewUrl = loc.newReviewUri;
                  if (reviewUrl != null && reviewUrl.trim().isNotEmpty) {
                    settings['business_google_review_url'] = reviewUrl.trim();
                  }

                  await websiteService.saveSettings(settings);
                  if (!ctx.mounted || !context.mounted) return;

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

enum _InspectorSection { content, layout, style }

class _CanvasSelectionContext {
  const _CanvasSelectionContext({
    required this.canvasData,
    required this.element,
    this.slideIndex,
  });

  final Map<String, dynamic> canvasData;
  final Map<String, dynamic> element;
  final int? slideIndex;

  String get id => element['id']?.toString() ?? '';
  String get type => (element['type'] ?? 'text').toString();
  String get label => switch (type) {
        'button' => (element['label'] ?? 'Botón').toString(),
        'image' => (element['altText'] ?? 'Imagen').toString().trim().isEmpty
            ? 'Imagen'
            : element['altText'].toString(),
        'shape' => 'Forma',
        'product' => 'Producto',
        'productsGallery' => 'Galería de productos',
        _ => (element['text'] ?? 'Texto').toString(),
      };
  IconData get icon => switch (type) {
        'button' => Icons.smart_button_rounded,
        'image' => Icons.image_outlined,
        'shape' => Icons.rectangle_outlined,
        'product' => Icons.inventory_2_outlined,
        'productsGallery' => Icons.grid_view_rounded,
        _ => Icons.text_fields_rounded,
      };
}

/// Inspector for the selected block.
///
/// Professional editors keep block identity and primary actions stable while
/// separating content, layout and appearance. This also gives every selection
/// a predictable starting point instead of preserving an unrelated scroll
/// position from the previously selected block.
class _EditBlockTab extends StatefulWidget {
  final WebsiteEditModeProvider editProvider;

  const _EditBlockTab({required this.editProvider});

  @override
  State<_EditBlockTab> createState() => _EditBlockTabState();
}

class _EditBlockTabState extends State<_EditBlockTab> {
  final ScrollController _scrollController = ScrollController();
  _InspectorSection _section = _InspectorSection.content;
  String? _lastSelectedId;

  WebsiteEditModeProvider get editProvider => widget.editProvider;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _syncSelection(String? selectedId) {
    if (_lastSelectedId == selectedId) return;
    _lastSelectedId = selectedId;
    _section = _InspectorSection.content;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
    });
  }

  void _selectSection(_InspectorSection value) {
    if (_section == value) return;
    setState(() => _section = value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = editProvider.selectedBlockId;

    if (selectedId == null) {
      _syncSelection(null);
      return _buildNoSelection();
    }

    // Handle special elements (header/footer) - these are not blocks
    // Use ValueKey to preserve state across rebuilds
    if (selectedId == 'header') {
      _syncSelection(selectedId);
      return _HeaderBlockControls(
          key: const ValueKey('header_controls'), provider: editProvider);
    }
    if (selectedId == 'footer') {
      _syncSelection(selectedId);
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
    final canvasSelection = _resolveCanvasSelection(
      blockType: blockType,
      blockData: blockData,
      blockId: selectedId,
    );
    _syncSelection(
      canvasSelection == null
          ? selectedId
          : '$selectedId/${canvasSelection.slideIndex ?? 'root'}/${canvasSelection.id}',
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: _buildBlockHeader(
            blockType,
            isVisible,
            selectedId,
            canvasSelection: canvasSelection,
          ),
        ),
        _buildSectionNavigation(),
        const Divider(height: 1, color: Colors.white12),
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            key: PageStorageKey<String>(
              'website_inspector_${selectedId}_${_section.name}',
            ),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            child: _buildSectionContent(
              blockType: blockType,
              blockData: blockData,
              block: block,
              blockId: selectedId,
              canvasSelection: canvasSelection,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionNavigation() {
    const items = <(_InspectorSection, IconData, String)>[
      (_InspectorSection.content, Icons.edit_note_rounded, 'Contenido'),
      (_InspectorSection.layout, Icons.dashboard_customize_outlined, 'Diseño'),
      (_InspectorSection.style, Icons.palette_outlined, 'Estilo'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Row(
          children: items.map((item) {
            final selected = item.$1 == _section;
            return Expanded(
              child: Semantics(
                button: true,
                selected: selected,
                label: 'Inspector: ${item.$3}',
                child: InkWell(
                  onTap: () => _selectSection(item.$1),
                  borderRadius: BorderRadius.circular(7),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF00A09D).withValues(alpha: 0.18)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF00A09D).withValues(alpha: 0.55)
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          item.$2,
                          size: 15,
                          color: selected
                              ? const Color(0xFF20C5C1)
                              : Colors.white54,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            item.$3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected ? Colors.white : Colors.white54,
                              fontSize: 11.5,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSectionContent({
    required String blockType,
    required Map<String, dynamic> blockData,
    required Map<String, dynamic> block,
    required String blockId,
    _CanvasSelectionContext? canvasSelection,
  }) {
    if (canvasSelection != null) {
      void updateSlideValue(String key, dynamic value) {
        final rawSlides = blockData['slides'];
        if (canvasSelection.slideIndex == null || rawSlides is! List) {
          editProvider.updateBlockData(blockId, key, value);
          return;
        }
        final slides = rawSlides
            .whereType<Map>()
            .map((slide) => Map<String, dynamic>.from(slide))
            .toList();
        final index = canvasSelection.slideIndex!;
        if (index < 0 || index >= slides.length) return;
        slides[index] = {...slides[index], key: value};
        editProvider.updateBlockData(blockId, 'slides', slides);
      }

      return _CanvasBlockControls(
        data: canvasSelection.canvasData,
        blockId: blockId,
        provider: editProvider,
        slideIndex: canvasSelection.slideIndex,
        elementsOnly: true,
        selectedElementOnly: true,
        inspectorSection: _section,
        onElementsChanged: (elements) => updateSlideValue('elements', elements),
        onCanvasSettingChanged: updateSlideValue,
      );
    }

    switch (_section) {
      case _InspectorSection.content:
        return _buildBlockControls(blockType, blockData, blockId);
      case _InspectorSection.layout:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _InspectorIntro(
              title: 'Disposición del bloque',
              description:
                  'Controla el tamaño y el espacio que ocupa este bloque en la página.',
              icon: Icons.dashboard_customize_outlined,
            ),
            const SizedBox(height: 18),
            _BlockHeightControl(
              data: blockData,
              blockId: blockId,
              blockType: blockType,
              provider: editProvider,
            ),
            const SizedBox(height: 18),
            _BlockSpacingControl(
              data: blockData,
              blockId: blockId,
              provider: editProvider,
            ),
            const SizedBox(height: 18),
            _BlockResponsiveVisibilityControl(
              data: blockData,
              blockId: blockId,
              provider: editProvider,
            ),
          ],
        );
      case _InspectorSection.style:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _InspectorIntro(
              title: 'Apariencia del bloque',
              description:
                  'Personaliza fondo, relleno, bordes y sombra sin alterar el contenido.',
              icon: Icons.palette_outlined,
            ),
            const SizedBox(height: 18),
            _BlockStyleControls(
              blockId: blockId,
              provider: editProvider,
              blockData: block,
              collapsible: false,
            ),
          ],
        );
    }
  }

  _CanvasSelectionContext? _resolveCanvasSelection({
    required String blockType,
    required Map<String, dynamic> blockData,
    required String blockId,
  }) {
    int? slideIndex;
    Map<String, dynamic> canvasData = blockData;
    if (blockType == WebsiteBlockType.carousel.name) {
      final rawSlides = blockData['slides'];
      if (rawSlides is! List || rawSlides.isEmpty) return null;
      slideIndex = editProvider.carouselSlideSelection(
        blockId,
        rawSlides.length,
      );
      final slide = rawSlides[slideIndex];
      if (slide is! Map) return null;
      canvasData = Map<String, dynamic>.from(slide);
    } else if (blockType != WebsiteBlockType.canvas.name) {
      return null;
    }

    final elementId = editProvider.canvasElementSelection(
      blockId,
      slideIndex: slideIndex,
    );
    if (elementId == null) return null;
    final rawElements = canvasData['elements'];
    if (rawElements is! List) return null;
    for (final raw in rawElements) {
      if (raw is Map && raw['id']?.toString() == elementId) {
        return _CanvasSelectionContext(
          canvasData: canvasData,
          element: Map<String, dynamic>.from(raw),
          slideIndex: slideIndex,
        );
      }
    }
    return null;
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

  Widget _buildBlockHeader(
    String blockType,
    bool isVisible,
    String blockId, {
    _CanvasSelectionContext? canvasSelection,
  }) {
    final parsedType = _tryParseWebsiteBlockType(blockType);
    final title = parsedType != null
        ? WebsiteBlockRegistry.definitionFor(parsedType).title
        : blockType;
    final icon = parsedType?.icon ?? Icons.widgets_rounded;

    final effectiveTitle = canvasSelection?.label ?? title;
    final effectiveIcon = canvasSelection?.icon ?? icon;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canvasSelection != null) ...[
          Row(
            children: [
              InkWell(
                onTap: () => editProvider.selectCanvasElement(
                  blockId,
                  null,
                  slideIndex: canvasSelection.slideIndex,
                ),
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back_rounded,
                          size: 15, color: Colors.white54),
                      SizedBox(width: 5),
                      Text('Volver al bloque',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 11)),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  canvasSelection.slideIndex == null
                      ? title
                      : '$title > Slide ${canvasSelection.slideIndex! + 1}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white38, fontSize: 10.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF00A09D).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                effectiveIcon,
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
                    effectiveTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    isVisible ? 'Visible' : 'Oculto',
                    style: TextStyle(
                      color:
                          isVisible ? const Color(0xFF00A09D) : Colors.orange,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (canvasSelection == null) ...[
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
          ],
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

class _BlockResponsiveVisibilityControl extends StatelessWidget {
  const _BlockResponsiveVisibilityControl({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  Map<String, bool> get _visibility {
    final result = <String, bool>{
      'desktop': true,
      'tablet': true,
      'mobile': true,
    };
    final raw = data['visibility'];
    if (raw is Map) {
      for (final key in result.keys) {
        final value = raw[key];
        if (value is bool) result[key] = value;
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final visibility = _visibility;
    const options = <(String, String, IconData)>[
      ('desktop', 'Escritorio', Icons.desktop_windows_outlined),
      ('tablet', 'Tablet', Icons.tablet_mac_outlined),
      ('mobile', 'Móvil', Icons.phone_iphone_outlined),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.devices_outlined, color: Color(0xFF00A09D), size: 18),
              SizedBox(width: 8),
              Text(
                'Visibilidad responsive',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'El contenido se conserva; sólo decides en qué tamaños aparece.',
            style: TextStyle(color: Colors.white38, fontSize: 10),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final option in options)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: option.$1 == 'mobile' ? 0 : 6,
                    ),
                    child: Semantics(
                      button: true,
                      selected: visibility[option.$1]!,
                      label:
                          '${option.$2}: ${visibility[option.$1]! ? 'visible' : 'oculto'}',
                      child: InkWell(
                        onTap: () {
                          final updated = Map<String, bool>.from(visibility);
                          updated[option.$1] = !updated[option.$1]!;
                          provider.updateBlockData(
                            blockId,
                            'visibility',
                            updated,
                          );
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: visibility[option.$1]!
                                ? const Color(0xFF00A09D).withValues(alpha: .18)
                                : Colors.white.withValues(alpha: .035),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: visibility[option.$1]!
                                  ? const Color(0xFF00A09D)
                                  : Colors.white12,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                option.$3,
                                size: 18,
                                color: visibility[option.$1]!
                                    ? const Color(0xFF20C5C1)
                                    : Colors.white30,
                              ),
                              const SizedBox(height: 5),
                              Text(
                                option.$2,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: visibility[option.$1]!
                                      ? Colors.white
                                      : Colors.white38,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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
  WebsiteEditModeProvider get editProvider => widget.provider;

  void _selectSlide(int index, {bool rebuild = true}) {
    final count = _slides.length;
    if (count <= 0) return;
    final normalized = index.clamp(0, count - 1).toInt();
    if (rebuild && mounted) {
      setState(() => _selectedSlideIndex = normalized);
    } else {
      _selectedSlideIndex = normalized;
    }
    widget.provider.selectCarouselSlide(widget.blockId, normalized, count);
  }

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

  void _setCompositionEnabled(Map<String, dynamic> slide, bool enabled) {
    if (!enabled) {
      _updateSlide(_selectedSlideIndex, 'useComposition', false);
      return;
    }

    final existing = slide['elements'];
    if (existing is List && existing.isNotEmpty) {
      _updateSlide(_selectedSlideIndex, 'useComposition', true);
      return;
    }

    final title = (slide['title'] ?? 'Título del banner').toString();
    final subtitle = (slide['subtitle'] ?? '').toString();
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
    Map<String, dynamic> textElement({
      required String id,
      required String text,
      required double x,
      required double y,
      required double w,
      required double h,
      required double size,
      required bool mobile,
      String role = 'heading',
      String weight = 'w700',
    }) =>
        {
          'id': id,
          'type': 'text',
          'text': text,
          'x': x,
          'y': y,
          'w': w,
          'h': h,
          'fontSize': size,
          'fontWeight': weight,
          'fontRole': role,
          'color': '#FFFFFF',
          'align': 'left',
          'lineHeight': 1.05,
          'letterSpacing': role == 'heading' ? 1.0 : 0.0,
          'hideOnMobile': !mobile,
          'showOnMobile': mobile,
        };
    Map<String, dynamic> buttonElement({
      required String id,
      required double x,
      required double y,
      required bool mobile,
    }) =>
        {
          'id': id,
          'type': 'button',
          'x': x,
          'y': y,
          'w': 220.0,
          'h': 56.0,
          'label': action.label,
          'link': action.href,
          'style': action.variant.storageValue,
          'inheritTheme': true,
          'actions': WebsiteActionValue.mergePrimary(null, action),
          'hideOnMobile': !mobile,
          'showOnMobile': mobile,
        };

    final elements = <Map<String, dynamic>>[
      textElement(
        id: 'title_desktop',
        text: title,
        x: 120,
        y: 190,
        w: 620,
        h: 130,
        size: 58,
        mobile: false,
      ),
      if (subtitle.isNotEmpty)
        textElement(
          id: 'subtitle_desktop',
          text: subtitle,
          x: 120,
          y: 330,
          w: 560,
          h: 80,
          size: 22,
          mobile: false,
          role: 'body',
          weight: 'w400',
        ),
      buttonElement(id: 'button_desktop', x: 120, y: 430, mobile: false),
      textElement(
        id: 'title_mobile',
        text: title,
        x: 28,
        y: 160,
        w: 334,
        h: 150,
        size: 42,
        mobile: true,
      ),
      if (subtitle.isNotEmpty)
        textElement(
          id: 'subtitle_mobile',
          text: subtitle,
          x: 28,
          y: 320,
          w: 334,
          h: 90,
          size: 18,
          mobile: true,
          role: 'body',
          weight: 'w400',
        ),
      buttonElement(id: 'button_mobile', x: 28, y: 440, mobile: true),
    ];

    _updateSlideMultiple(_selectedSlideIndex, {
      'useComposition': true,
      'designWidth': 1200.0,
      'mobileDesignWidth': 390.0,
      'constrainElementsToSafeArea': true,
      'elements': elements,
    });
  }

  void _addSlide() {
    final slides = List<Map<String, dynamic>>.from(_slides);
    slides.add({
      'title': 'Nuevo Slide',
      'subtitle': 'Descripción del slide',
      'imageUrl': '',
      'ctaText': 'Ver más',
      'ctaLink': '/productos',
      'showOverlay': true,
      'overlayOpacity': 0.55,
    });
    _updateSlides(slides);
    setState(() => _selectedSlideIndex = slides.length - 1);
    widget.provider.selectCarouselSlide(
      widget.blockId,
      _selectedSlideIndex,
      slides.length,
    );
  }

  void _removeSlide(int index) {
    final slides = List<Map<String, dynamic>>.from(_slides);
    if (slides.length > 1 && index >= 0 && index < slides.length) {
      slides.removeAt(index);
      _updateSlides(slides);
      final nextIndex = _selectedSlideIndex >= slides.length
          ? slides.length - 1
          : _selectedSlideIndex;
      setState(() => _selectedSlideIndex = nextIndex);
      widget.provider.selectCarouselSlide(
        widget.blockId,
        nextIndex,
        slides.length,
      );
    }
  }

  /// Build slide fields inline (same pattern as VideoBanner)
  Widget _buildSlideFields(Map<String, dynamic> slide) {
    final showOverlay = slide['showOverlay'] ?? true;
    final overlayOpacity =
        (slide['overlayOpacity'] as num?)?.toDouble() ?? 0.55;
    final hasVideoFile = (slide['videoFileUrl']?.toString() ?? '').isNotEmpty;
    final titleFormatting = TextFormatting.fromJson(
      slide['titleFormatting'] is Map
          ? Map<String, dynamic>.from(slide['titleFormatting'] as Map)
          : null,
    );
    final subtitleFormatting = TextFormatting.fromJson(
      slide['subtitleFormatting'] is Map
          ? Map<String, dynamic>.from(slide['subtitleFormatting'] as Map)
          : null,
    );
    final compositionElements = slide['elements'] is List
        ? (slide['elements'] as List)
            .whereType<Map>()
            .map((element) => Map<String, dynamic>.from(element))
            .toList()
        : <Map<String, dynamic>>[];
    final usesComposition =
        slide['useComposition'] == true || compositionElements.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CollapsibleSection(
          title: 'Contenido del slide',
          icon: Icons.edit_note_rounded,
          initiallyExpanded: true,
          children: [
            _EditorToggle(
              label: 'Diseño avanzado por capas',
              value: usesComposition,
              onChanged: (value) => _setCompositionEnabled(slide, value),
            ),
            const SizedBox(height: 8),
            Text(
              usesComposition
                  ? 'Cada texto, imagen, forma y botón es una capa editable. Arrástrala directamente sobre el slide.'
                  : 'Actívalo para crear campañas con composición libre sin perder los controles del editor.',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            const SizedBox(height: 16),
            if (usesComposition) ...[
              _CanvasBlockControls(
                data: <String, dynamic>{
                  ...slide,
                  'elements': compositionElements,
                  'blockHeight':
                      (slide['designHeight'] as num?)?.toDouble() ?? 750.0,
                },
                blockId: widget.blockId,
                provider: widget.provider,
                slideIndex: _selectedSlideIndex,
                elementsOnly: true,
                onElementsChanged: (elements) =>
                    _updateSlide(_selectedSlideIndex, 'elements', elements),
                onCanvasSettingChanged: (key, value) =>
                    _updateSlide(_selectedSlideIndex, key, value),
                onActiveElementChanged: (elementId) =>
                    widget.provider.selectCanvasElement(
                  widget.blockId,
                  elementId,
                  slideIndex: _selectedSlideIndex,
                  slideCount: _slides.length,
                ),
              ),
              _buildNestedLayers(widget.provider.blocks),
              const SizedBox(height: 20),
            ] else ...[
              _EditorTextField(
                label: 'Título',
                value: slide['title']?.toString() ?? '',
                onChanged: (v) => _updateSlide(_selectedSlideIndex, 'title', v),
              ),
              const SizedBox(height: 8),
              TextFormattingToolbar(
                currentFormatting: titleFormatting,
                preset: TextToolbarPreset.basic,
                showAdvancedOptions: false,
                onFormattingChanged: (value) => _updateSlide(
                  _selectedSlideIndex,
                  'titleFormatting',
                  value.toJson(),
                ),
              ),
              const SizedBox(height: 12),
              _EditorTextField(
                label: 'Subtítulo',
                value: slide['subtitle']?.toString() ?? '',
                onChanged: (v) =>
                    _updateSlide(_selectedSlideIndex, 'subtitle', v),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              TextFormattingToolbar(
                currentFormatting: subtitleFormatting,
                preset: TextToolbarPreset.basic,
                showAdvancedOptions: false,
                onFormattingChanged: (value) => _updateSlide(
                  _selectedSlideIndex,
                  'subtitleFormatting',
                  value.toJson(),
                ),
              ),
              const SizedBox(height: 12),
              WebsiteActionEditor(
                showVariant: true,
                value: WebsiteActionValue.resolvePrimary(
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
                    ),
                onChanged: (action) => _updateSlideMultiple(
                  _selectedSlideIndex,
                  {
                    'ctaText': action.label,
                    'buttonText': action.label,
                    'ctaLink': action.href,
                    'buttonLink': action.href,
                    'actionVariant': action.variant.storageValue,
                    'actions': WebsiteActionValue.mergePrimary(
                      slide['actions'],
                      action,
                    ),
                  },
                ),
              ),
              const SizedBox(height: 4),
            ],
          ],
        ),
        _CollapsibleSection(
          title: 'Imagen y encuadre',
          icon: Icons.image_outlined,
          initiallyExpanded: !usesComposition,
          children: [
            _ImagePicker(
              currentUrl: slide['imageUrl']?.toString(),
              onChanged: (url) =>
                  _updateSlide(_selectedSlideIndex, 'imageUrl', url),
            ),
            const SizedBox(height: 12),
            const _SectionHeader('Foco de imagen'),
            const SizedBox(height: 8),
            FocalPointPicker(
              imageUrl: slide['imageUrl']?.toString(),
              focalX: (slide['focalPointX'] as num?)?.toDouble() ?? 0.5,
              focalY: (slide['focalPointY'] as num?)?.toDouble() ?? 0.5,
              onChanged: (x, y) {
                _updateSlideMultiple(_selectedSlideIndex, {
                  'focalPointX': x,
                  'focalPointY': y,
                });
              },
            ),
            const SizedBox(height: 12),
            const _SectionHeader('Foco móvil'),
            const SizedBox(height: 8),
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
            const SizedBox(height: 12),
            _EditorTextField(
              label: 'Texto alternativo',
              value: slide['altText']?.toString() ?? '',
              onChanged: (value) =>
                  _updateSlide(_selectedSlideIndex, 'altText', value),
            ),
          ],
        ),
        _CollapsibleSection(
          title: 'Video de fondo',
          icon: Icons.play_circle_outline_rounded,
          initiallyExpanded:
              hasVideoFile || (slide['videoUrl']?.toString() ?? '').isNotEmpty,
          children: [
            const Text(
              'Si se configura un video, se usará en vez de la imagen',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 12),

            // Upload/file selection is the primary workflow.
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
                  border:
                      Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle,
                        color: Colors.green, size: 16),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Archivo de video cargado',
                        style: TextStyle(color: Colors.green, fontSize: 12),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          size: 16, color: Colors.green),
                      onPressed: () =>
                          _updateSlide(_selectedSlideIndex, 'videoFileUrl', ''),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            _CollapsibleSection(
              title: 'YouTube / enlace avanzado',
              icon: Icons.link_rounded,
              initiallyExpanded:
                  (slide['videoUrl']?.toString() ?? '').isNotEmpty,
              children: [
                _EditorTextField(
                  label: 'URL de YouTube',
                  value: slide['videoUrl']?.toString() ?? '',
                  onChanged: (v) {
                    _updateSlide(_selectedSlideIndex, 'videoUrl', v);
                    if (v.isNotEmpty) {
                      _updateSlide(_selectedSlideIndex, 'videoFileUrl', '');
                    }
                  },
                  hint: 'https://youtube.com/watch?v=...',
                ),
              ],
            ),
          ],
        ),
        _CollapsibleSection(
          title: 'Overlay',
          icon: Icons.gradient_outlined,
          initiallyExpanded: false,
          children: [
            _EditorToggle(
              label: 'Mostrar overlay oscuro',
              value: showOverlay,
              onChanged: (v) =>
                  _updateSlide(_selectedSlideIndex, 'showOverlay', v),
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
        ),
      ],
    );
  }

  Widget _buildNestedLayers(List<Map<String, dynamic>> blocks) {
    final selectedId = editProvider.selectedBlockId;
    if (selectedId == null) return const SizedBox.shrink();
    final block = blocks.cast<Map<String, dynamic>?>().firstWhere(
          (candidate) => candidate?['id']?.toString() == selectedId,
          orElse: () => null,
        );
    if (block == null) return const SizedBox.shrink();
    final type = (block['block_type'] ?? block['type'] ?? '').toString();
    final data = Map<String, dynamic>.from(
      block['block_data'] as Map? ?? const <String, dynamic>{},
    );
    var slideIndex = 0;
    List<dynamic> rawElements;
    if (type == WebsiteBlockType.carousel.name) {
      final slides = List<dynamic>.from(data['slides'] as List? ?? const []);
      if (slides.isEmpty) return const SizedBox.shrink();
      slideIndex = editProvider.carouselSlideSelection(
        selectedId,
        slides.length,
      );
      final slide = Map<String, dynamic>.from(slides[slideIndex] as Map? ?? {});
      if (slide['useComposition'] != true) return const SizedBox.shrink();
      rawElements = List<dynamic>.from(slide['elements'] as List? ?? const []);
    } else if (type == WebsiteBlockType.canvas.name) {
      rawElements = List<dynamic>.from(data['elements'] as List? ?? const []);
    } else {
      return const SizedBox.shrink();
    }

    final elements = rawElements
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    if (elements.isEmpty) return const SizedBox.shrink();
    final selectedElementId = editProvider.canvasElementSelection(
      selectedId,
      slideIndex: type == WebsiteBlockType.carousel.name ? slideIndex : null,
    );

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF242424),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
            child: Text(
              type == WebsiteBlockType.carousel.name
                  ? 'CAPAS · SLIDE ${slideIndex + 1}'
                  : 'CAPAS DEL CANVAS',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: .8,
              ),
            ),
          ),
          for (var index = elements.length - 1; index >= 0; index--)
            _buildNestedLayerRow(
              blockId: selectedId,
              type: type,
              slideIndex: slideIndex,
              elements: elements,
              index: index,
              selected: elements[index]['id']?.toString() == selectedElementId,
            ),
        ],
      ),
    );
  }

  Widget _buildNestedLayerRow({
    required String blockId,
    required String type,
    required int slideIndex,
    required List<Map<String, dynamic>> elements,
    required int index,
    required bool selected,
  }) {
    final element = elements[index];
    final id = element['id']?.toString() ?? '';
    final elementType = element['type']?.toString() ?? 'element';
    final hidden = element['hidden'] == true;
    final locked = element['locked'] == true;
    final label = (element['name'] ??
            element['text'] ??
            element['label'] ??
            element['title'] ??
            _canvasElementLabel(elementType))
        .toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xFF00A09D).withValues(alpha: .14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
      ),
      child: InkWell(
        onTap: () => editProvider.selectCanvasElement(
          blockId,
          id,
          slideIndex:
              type == WebsiteBlockType.carousel.name ? slideIndex : null,
        ),
        borderRadius: BorderRadius.circular(7),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            children: [
              Icon(_canvasElementIcon(elementType),
                  size: 15,
                  color: selected ? const Color(0xFF00A09D) : Colors.white54),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hidden ? Colors.white30 : Colors.white70,
                    fontSize: 11,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: hidden ? 'Mostrar capa' : 'Ocultar capa',
                onPressed: () => _patchNestedLayer(
                  blockId: blockId,
                  type: type,
                  slideIndex: slideIndex,
                  elements: elements,
                  index: index,
                  key: 'hidden',
                  value: !hidden,
                ),
                icon: Icon(hidden ? Icons.visibility_off : Icons.visibility,
                    size: 15, color: Colors.white38),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: locked ? 'Desbloquear capa' : 'Bloquear capa',
                onPressed: () => _patchNestedLayer(
                  blockId: blockId,
                  type: type,
                  slideIndex: slideIndex,
                  elements: elements,
                  index: index,
                  key: 'locked',
                  value: !locked,
                ),
                icon: Icon(locked ? Icons.lock : Icons.lock_open,
                    size: 15, color: Colors.white38),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _patchNestedLayer({
    required String blockId,
    required String type,
    required int slideIndex,
    required List<Map<String, dynamic>> elements,
    required int index,
    required String key,
    required dynamic value,
  }) {
    final updated =
        elements.map((element) => Map<String, dynamic>.from(element)).toList();
    updated[index][key] = value;
    if (type == WebsiteBlockType.canvas.name) {
      editProvider.updateBlockData(blockId, 'elements', updated);
      return;
    }
    final block = editProvider.blocks.firstWhere(
      (candidate) => candidate['id']?.toString() == blockId,
    );
    final data = Map<String, dynamic>.from(block['block_data'] as Map? ?? {});
    final slides = List<dynamic>.from(data['slides'] as List? ?? const []);
    final slide = Map<String, dynamic>.from(slides[slideIndex] as Map? ?? {});
    slides[slideIndex] = {...slide, 'elements': updated};
    editProvider.updateBlockData(blockId, 'slides', slides);
  }

  static IconData _canvasElementIcon(String type) => switch (type) {
        'text' => Icons.text_fields_rounded,
        'button' => Icons.smart_button_rounded,
        'image' => Icons.image_outlined,
        'shape' => Icons.rectangle_outlined,
        'product' => Icons.inventory_2_outlined,
        'productsGallery' => Icons.grid_view_rounded,
        _ => Icons.layers_outlined,
      };

  static String _canvasElementLabel(String type) => switch (type) {
        'text' => 'Texto',
        'button' => 'Botón',
        'image' => 'Imagen',
        'shape' => 'Forma',
        'product' => 'Producto',
        'productsGallery' => 'Galería de productos',
        _ => 'Elemento',
      };

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
    final sharedSelection =
        widget.provider.carouselSlideSelection(widget.blockId, slides.length);
    if (sharedSelection != _selectedSlideIndex) {
      _selectedSlideIndex = sharedSelection;
    }
    final autoPlay = widget.data['autoPlay'] ?? true;
    final intervalSeconds =
        (widget.data['intervalSeconds'] as num?)?.toInt() ?? 5;
    final showIndicators = widget.data['showIndicators'] ?? true;
    final showArrows = widget.data['showArrows'] ?? true;
    final animation = widget.data['animation']?.toString() ?? 'slide';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CollapsibleSection(
          title: 'Comportamiento del carrusel',
          icon: Icons.motion_photos_auto_outlined,
          initiallyExpanded: false,
          children: [
            _EditorToggle(
              label: 'Reproducción automática',
              value: autoPlay,
              onChanged: (v) => widget.provider
                  .updateBlockData(widget.blockId, 'autoPlay', v),
            ),
            const SizedBox(height: 12),
            if (autoPlay) ...[
              _EditorSlider(
                label: 'Intervalo (segundos)',
                value: intervalSeconds.toDouble(),
                min: 2,
                max: 15,
                divisions: 13,
                onChanged: (v) => widget.provider.updateBlockData(
                    widget.blockId, 'intervalSeconds', v.toInt()),
              ),
              const SizedBox(height: 12),
            ],
            _EditorSlider(
              label: 'Duración animación (ms)',
              value: (widget.data['animationDurationMs'] as num?)?.toDouble() ??
                  600,
              min: 200,
              max: 2000,
              divisions: 18, // (2000-200)/100 = 18 steps of 100ms
              onChanged: (v) => widget.provider.updateBlockDataMultiple(
                widget.blockId,
                {
                  'animationDurationMs': v.toInt(),
                  // Keep legacy field in sync until all persisted data is normalized.
                  'transitionDuration': v.toInt(),
                },
              ),
            ),
            const SizedBox(height: 12),
            _EditorDropdown(
              label: 'Animación',
              value: animation,
              options: const [
                ('slide', 'Deslizar'),
                ('fade', 'Desvanecer'),
                ('zoom', 'Zoom'),
              ],
              onChanged: (v) => widget.provider
                  .updateBlockData(widget.blockId, 'animation', v),
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
              onChanged: (v) => widget.provider
                  .updateBlockData(widget.blockId, 'showArrows', v),
            ),
          ],
        ),
        _CollapsibleSection(
          title: 'Slides (${slides.length})',
          icon: Icons.view_carousel_outlined,
          initiallyExpanded: true,
          children: [
            Row(
              children: [
                const Expanded(child: _SectionHeader('Slides')),
                InkWell(
                  onTap: _addSlide,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                            style: TextStyle(
                                color: Color(0xFF00A09D), fontSize: 12)),
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
                      onTap: () => _selectSlide(index),
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
                                color: isSelected
                                    ? Colors.white70
                                    : Colors.white70,
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
                                  color: isSelected
                                      ? Colors.white70
                                      : Colors.white38,
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
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5)),
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

        // Upload/file selection is the primary workflow.
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
        const SizedBox(height: 12),
        _CollapsibleSection(
          title: 'YouTube / enlace avanzado',
          icon: Icons.link_rounded,
          initiallyExpanded: hasYoutubeUrl,
          children: [
            _EditorTextField(
              label: 'URL de YouTube',
              value: widget.slide['videoUrl']?.toString() ?? '',
              onChanged: (v) {
                widget.onUpdate('videoUrl', v);
                if (v.isNotEmpty) {
                  widget.onUpdate('videoFileUrl', '');
                }
              },
              hint: 'https://youtube.com/watch?v=...',
            ),
          ],
        ),

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
        WebsiteActionEditor(
          showVariant: true,
          value: WebsiteActionValue.resolvePrimary(
                widget.slide,
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
              ),
          onChanged: (action) {
            widget.onUpdate('ctaText', action.label);
            widget.onUpdate('buttonText', action.label);
            widget.onUpdate('ctaLink', action.href);
            widget.onUpdate('buttonLink', action.href);
            widget.onUpdate('actionVariant', action.variant.storageValue);
            widget.onUpdate(
              'actions',
              WebsiteActionValue.mergePrimary(
                widget.slide['actions'],
                action,
              ),
            );
          },
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
        _CollapsibleSection(
          title: 'Contenido y origen',
          icon: Icons.inventory_2_outlined,
          initiallyExpanded: true,
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
            const _SectionHeader('Fuente de productos'),
            const SizedBox(height: 12),

            // Product source selector
            _buildSourceSelector(),

            const SizedBox(height: 16),

            // Conditional content based on source
            if (_productSource == 'category') _buildCategorySelector(),
            if (_productSource == 'manual') _buildProductSelector(),
          ],
        ),
        _CollapsibleSection(
          title: 'Diseño de productos',
          icon: Icons.grid_view_rounded,
          initiallyExpanded: false,
          children: [
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
                          color: isSelected
                              ? const Color(0xFF00A09D)
                              : Colors.white24,
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
          ],
        ),
        _CollapsibleSection(
          title: 'Información visible',
          icon: Icons.visibility_outlined,
          initiallyExpanded: false,
          children: [
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
          ],
        ),
        if (widget.data['showViewAll'] != false)
          _CollapsibleSection(
            title: 'Acción “Ver todos”',
            icon: Icons.call_to_action_outlined,
            initiallyExpanded: false,
            children: [
              WebsiteActionEditor(
                title: 'Botón Ver todos',
                showVariant: true,
                value: WebsiteActionValue.resolvePrimary(
                      widget.data,
                      labelKeys: const ['viewAllText'],
                      hrefKeys: const ['viewAllLink'],
                      defaultLabel: 'Ver todos los productos',
                      defaultHref: '/productos',
                      defaultVariant: WebsiteActionVariant.outline,
                    ) ??
                    const WebsiteActionValue(
                      label: 'Ver todos los productos',
                      href: '/productos',
                      variant: WebsiteActionVariant.outline,
                    ),
                onChanged: (action) {
                  widget.provider.updateBlockDataMultiple(
                    widget.blockId,
                    {
                      'viewAllText': action.label,
                      'viewAllLink': action.href,
                      'actionVariant': action.variant.storageValue,
                      'actions': WebsiteActionValue.mergePrimary(
                        widget.data['actions'],
                        action,
                      ),
                    },
                  );
                },
              ),
            ],
          ),
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
typedef _RepeaterItemEditorBuilder = Widget Function(
  BuildContext context,
  int index,
  Map<String, dynamic> item,
  ValueChanged<Map<String, dynamic>> onChanged,
);

/// Compact, shared inspector for schema-defined collections.
///
/// A collection can contain many rich items (images, focal points, actions,
/// nested collections, and so on). Rendering every item form at once makes the
/// inspector impossible to scan, so this control keeps the collection overview
/// visible while editing exactly one item at a time.
class _SchemaRepeaterEditor extends StatefulWidget {
  const _SchemaRepeaterEditor({
    required this.field,
    required this.items,
    required this.onChanged,
    required this.itemBuilder,
  });

  final WebsiteBlockFieldSchema field;
  final List<Map<String, dynamic>> items;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final _RepeaterItemEditorBuilder itemBuilder;

  @override
  State<_SchemaRepeaterEditor> createState() => _SchemaRepeaterEditorState();
}

class _SchemaRepeaterEditorState extends State<_SchemaRepeaterEditor> {
  int _selectedIndex = 0;

  @override
  void didUpdateWidget(covariant _SchemaRepeaterEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.isEmpty) {
      _selectedIndex = 0;
    } else if (_selectedIndex >= widget.items.length) {
      _selectedIndex = widget.items.length - 1;
    }
  }

  String _itemTitle(Map<String, dynamic> item, int index) {
    const preferredKeys = [
      'title',
      'name',
      'question',
      'label',
      'heading',
      'value',
    ];
    for (final key in preferredKeys) {
      final value = item[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '${widget.field.itemLabel ?? 'Item'} ${index + 1}';
  }

  void _selectAfterChange(int index) {
    setState(() => _selectedIndex = index < 0 ? 0 : index);
  }

  void _addItem() {
    final next = List<Map<String, dynamic>>.from(widget.items);
    final seed = <String, dynamic>{};
    for (final field in widget.field.itemFields) {
      seed[field.key] = field.defaultValue;
    }
    next.add(seed);
    widget.onChanged(next);
    _selectAfterChange(next.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final canAdd =
        widget.field.maxItems == null || items.length < widget.field.maxItems!;
    final safeIndex =
        items.isEmpty ? 0 : _selectedIndex.clamp(0, items.length - 1).toInt();
    const accent = Color(0xFF20C5C1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.field.label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${items.length}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Agregar ${widget.field.itemLabel ?? 'item'}',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              color: accent,
              onPressed: canAdd ? _addItem : null,
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
          ],
        ),
        if (items.isEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.025),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              children: [
                const Text(
                  'Todavía no hay elementos',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                if (canAdd) ...[
                  const SizedBox(height: 8),
                  _AddItemButton(
                    label: 'Agregar ${widget.field.itemLabel ?? 'item'}',
                    onPressed: _addItem,
                  ),
                ],
              ],
            ),
          ),
        ] else ...[
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(items.length, (index) {
                final selected = index == safeIndex;
                return Padding(
                  padding: EdgeInsets.only(
                    right: index == items.length - 1 ? 0 : 6,
                  ),
                  child: Tooltip(
                    message: _itemTitle(items[index], index),
                    child: Material(
                      color: selected
                          ? accent.withValues(alpha: 0.16)
                          : Colors.white.withValues(alpha: 0.045),
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        onTap: () => setState(() => _selectedIndex = index),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: 42,
                            maxWidth: 132,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selected
                                  ? accent.withValues(alpha: 0.65)
                                  : Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Text(
                            '${index + 1}  ${_itemTitle(items[index], index)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected ? Colors.white : Colors.white60,
                              fontSize: 11.5,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            decoration: BoxDecoration(
              color: const Color(0xFF292929),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _itemTitle(items[safeIndex], safeIndex),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Mover hacia arriba',
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      onPressed: safeIndex > 0
                          ? () {
                              final next =
                                  List<Map<String, dynamic>>.from(items);
                              final previous = next[safeIndex - 1];
                              next[safeIndex - 1] = next[safeIndex];
                              next[safeIndex] = previous;
                              widget.onChanged(next);
                              _selectAfterChange(safeIndex - 1);
                            }
                          : null,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    IconButton(
                      tooltip: 'Mover hacia abajo',
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      onPressed: safeIndex < items.length - 1
                          ? () {
                              final next =
                                  List<Map<String, dynamic>>.from(items);
                              final following = next[safeIndex + 1];
                              next[safeIndex + 1] = next[safeIndex];
                              next[safeIndex] = following;
                              widget.onChanged(next);
                              _selectAfterChange(safeIndex + 1);
                            }
                          : null,
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                    IconButton(
                      tooltip: 'Duplicar',
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      onPressed: canAdd
                          ? () {
                              final next =
                                  List<Map<String, dynamic>>.from(items)
                                    ..insert(
                                      safeIndex + 1,
                                      Map<String, dynamic>.from(
                                        items[safeIndex],
                                      ),
                                    );
                              widget.onChanged(next);
                              _selectAfterChange(safeIndex + 1);
                            }
                          : null,
                      icon: const Icon(Icons.copy_outlined),
                    ),
                    IconButton(
                      tooltip: 'Eliminar',
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      color: Colors.red.shade300,
                      onPressed: widget.field.minItems == null ||
                              items.length > widget.field.minItems!
                          ? () {
                              final next =
                                  List<Map<String, dynamic>>.from(items)
                                    ..removeAt(safeIndex);
                              widget.onChanged(next);
                              _selectAfterChange(
                                next.isEmpty
                                    ? 0
                                    : safeIndex.clamp(0, next.length - 1),
                              );
                            }
                          : null,
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
                const Divider(height: 14, color: Colors.white10),
                widget.itemBuilder(
                  context,
                  safeIndex,
                  items[safeIndex],
                  (nextItem) {
                    final next = List<Map<String, dynamic>>.from(items);
                    next[safeIndex] = nextItem;
                    widget.onChanged(next);
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

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
          .map((item) => item is Map
              ? Map<String, dynamic>.from(item)
              : <String, dynamic>{'label': item.toString()})
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

  Widget _buildTextFormattingInspector({
    required WebsiteBlockFieldSchema field,
    required Map<String, dynamic> currentData,
    required void Function(String key, dynamic value) setRelatedValue,
  }) {
    if (!field.supportsFormatting) return const SizedBox.shrink();

    final rawFormatting = currentData[field.resolvedFormattingKey];
    final formatting = TextFormatting.fromJson(
      rawFormatting is Map ? Map<String, dynamic>.from(rawFormatting) : null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        const _SectionHeader('Formato'),
        const SizedBox(height: 8),
        TextFormattingToolbar(
          currentFormatting: formatting,
          preset: TextToolbarPreset.basic,
          showAdvancedOptions: false,
          onFormattingChanged: (value) => setRelatedValue(
            field.resolvedFormattingKey,
            value.toJson(),
          ),
        ),
      ],
    );
  }

  Widget _buildSchemaField({
    required BuildContext context,
    required WebsiteBlockFieldSchema field,
    required Map<String, dynamic> currentData,
    required void Function(dynamic value) setValue,
    required void Function(String key, dynamic value) setRelatedValue,
    required void Function(Map<String, dynamic> values) setRelatedValues,
    WebsiteBlockFieldSchema? actionLabelField,
  }) {
    dynamic raw = currentData[field.key];
    for (final alias in field.migrationAliases) {
      raw ??= currentData[alias];
    }
    final label = field.label;

    switch (field.type) {
      case WebsiteBlockFieldType.text:
        if (field.key == 'videoUrl') {
          final current =
              raw?.toString() ?? (field.defaultValue?.toString() ?? '');
          return _CollapsibleSection(
            title: 'YouTube / enlace avanzado',
            icon: Icons.link_rounded,
            initiallyExpanded: current.trim().isNotEmpty,
            children: [
              _EditorTextField(
                label: label,
                value: current,
                onChanged: (v) {
                  setValue(v);
                  if (v.trim().isNotEmpty &&
                      currentData.containsKey('videoFileUrl')) {
                    provider.updateBlockData(blockId, 'videoFileUrl', '');
                  }
                },
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
              onChanged: (v) => setValue(v),
            ),
            _buildTextFormattingInspector(
              field: field,
              currentData: currentData,
              setRelatedValue: setRelatedValue,
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
            _buildTextFormattingInspector(
              field: field,
              currentData: currentData,
              setRelatedValue: setRelatedValue,
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
        final actionLabelKey = field.actionLabelKey;
        if (actionLabelKey != null) {
          final labelKeys = <String>[
            actionLabelKey,
            ...?actionLabelField?.migrationAliases,
          ];
          final hrefKeys = <String>[field.key, ...field.migrationAliases];
          final label = labelKeys
              .map((key) => currentData[key]?.toString().trim() ?? '')
              .firstWhere((value) => value.isNotEmpty, orElse: () => 'Ver más');
          final variantKey = field.actionVariantKey;
          final fallbackVariant = WebsiteActionVariant.fromStorage(
            variantKey == null ? null : currentData[variantKey]?.toString(),
          );
          final action = WebsiteActionValue.resolvePrimary(
                currentData,
                labelKeys: labelKeys,
                hrefKeys: hrefKeys,
                defaultLabel: label,
                defaultHref: current,
                defaultVariant: fallbackVariant,
              ) ??
              WebsiteActionValue(
                label: label,
                href: current,
                variant: fallbackVariant,
              );

          return WebsiteActionEditor(
            value: action,
            darkStyle: true,
            dense: true,
            showVariant: variantKey != null,
            onChanged: (next) {
              final updates = <String, dynamic>{
                field.key: next.href,
                actionLabelKey: next.label,
              };
              for (final alias in field.migrationAliases) {
                updates[alias] = next.href;
              }
              for (final alias
                  in actionLabelField?.migrationAliases ?? const <String>[]) {
                updates[alias] = next.label;
              }
              if (variantKey != null) {
                updates[variantKey] = next.variant.storageValue;
              }
              updates['actions'] = WebsiteActionValue.mergePrimary(
                currentData['actions'],
                next,
              );
              setRelatedValues(updates);
            },
          );
        }
        return WebsiteLinkValueEditor(
          label: label,
          value: current,
          helpText: field.helpText,
          dense: true,
          darkStyle: true,
          onChanged: (v) => setValue(v),
        );
      case WebsiteBlockFieldType.color:
        final current =
            raw?.toString() ?? (field.defaultValue?.toString() ?? '');
        return WebsiteColorPickerField(
          label: label,
          value: current.isEmpty ? '#000000' : current,
          helperText: field.helpText,
          allowAlpha: true,
          onChanged: (value) => setValue(value),
        );
      case WebsiteBlockFieldType.image:
        final currentUrl = raw?.toString();
        final focalX =
            (currentData[field.focalPointXKey] as num?)?.toDouble() ?? 0.5;
        final focalY =
            (currentData[field.focalPointYKey] as num?)?.toDouble() ?? 0.5;
        final mobileFocalX =
            (currentData[field.mobileFocalPointXKey] as num?)?.toDouble() ??
                focalX;
        final mobileFocalY =
            (currentData[field.mobileFocalPointYKey] as num?)?.toDouble() ??
                focalY;
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
            if (field.hasFocalPointControl &&
                currentUrl?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              const _SectionHeader('Foco de imagen'),
              const SizedBox(height: 8),
              FocalPointPicker(
                imageUrl: currentUrl,
                focalX: focalX,
                focalY: focalY,
                onChanged: (x, y) {
                  setRelatedValue(field.focalPointXKey, x);
                  setRelatedValue(field.focalPointYKey, y);
                },
              ),
              if (field.isCoverMedia) ...[
                const SizedBox(height: 12),
                const _SectionHeader('Foco móvil'),
                const SizedBox(height: 8),
                FocalPointPicker(
                  imageUrl: currentUrl,
                  focalX: mobileFocalX,
                  focalY: mobileFocalY,
                  onChanged: (x, y) {
                    setRelatedValue(field.mobileFocalPointXKey, x);
                    setRelatedValue(field.mobileFocalPointYKey, y);
                  },
                ),
              ],
            ],
            if (field.hasAltTextControl) ...[
              const SizedBox(height: 12),
              _EditorTextField(
                label: 'Texto alternativo',
                value: currentData[field.altTextKey]?.toString() ?? '',
                hint: 'Describe la imagen',
                onChanged: (value) => setRelatedValue(field.altTextKey, value),
              ),
            ],
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
        final actionLabelKeys = field.itemFields
            .where((itemField) => itemField.actionLabelKey != null)
            .map((itemField) => itemField.actionLabelKey!)
            .toSet();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SchemaRepeaterEditor(
              field: field,
              items: items,
              onChanged: (next) => setValue(next),
              itemBuilder: (
                context,
                index,
                itemData,
                onItemChanged,
              ) {
                final visibleFields = field.itemFields
                    .where(
                      (subField) => !actionLabelKeys.contains(subField.key),
                    )
                    .toList();
                final contentFields = <WebsiteBlockFieldSchema>[];
                final mediaFields = <WebsiteBlockFieldSchema>[];
                final actionFields = <WebsiteBlockFieldSchema>[];
                final collectionFields = <WebsiteBlockFieldSchema>[];
                final optionFields = <WebsiteBlockFieldSchema>[];

                for (final subField in visibleFields) {
                  if (subField.type == WebsiteBlockFieldType.image ||
                      subField.type == WebsiteBlockFieldType.video) {
                    mediaFields.add(subField);
                  } else if (subField.type == WebsiteBlockFieldType.link) {
                    actionFields.add(subField);
                  } else if (subField.type == WebsiteBlockFieldType.repeater) {
                    collectionFields.add(subField);
                  } else if (subField.group == 'style' ||
                      subField.group == 'layout' ||
                      subField.type == WebsiteBlockFieldType.color) {
                    optionFields.add(subField);
                  } else {
                    contentFields.add(subField);
                  }
                }

                Widget buildSubField(WebsiteBlockFieldSchema subField) {
                  WebsiteBlockFieldSchema? actionLabelField;
                  final actionLabelKey = subField.actionLabelKey;
                  if (actionLabelKey != null) {
                    for (final candidate in field.itemFields) {
                      if (candidate.key == actionLabelKey) {
                        actionLabelField = candidate;
                        break;
                      }
                    }
                  }

                  void updateValue(dynamic value) {
                    final nextItem = Map<String, dynamic>.from(itemData);
                    nextItem[subField.key] = value;
                    for (final alias in subField.migrationAliases) {
                      nextItem[alias] = value;
                    }
                    onItemChanged(nextItem);
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildSchemaField(
                      context: context,
                      field: subField,
                      currentData: itemData,
                      setValue: updateValue,
                      setRelatedValue: (key, value) {
                        final nextItem = Map<String, dynamic>.from(itemData);
                        nextItem[key] = value;
                        onItemChanged(nextItem);
                      },
                      setRelatedValues: (values) {
                        final nextItem = Map<String, dynamic>.from(itemData)
                          ..addAll(values);
                        onItemChanged(nextItem);
                      },
                      actionLabelField: actionLabelField,
                    ),
                  );
                }

                Widget buildGroup({
                  required String title,
                  required IconData icon,
                  required List<WebsiteBlockFieldSchema> fields,
                  required bool expanded,
                }) {
                  return _CollapsibleSection(
                    title: title,
                    icon: icon,
                    initiallyExpanded: expanded,
                    children: fields.map(buildSubField).toList(),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (contentFields.isNotEmpty)
                      buildGroup(
                        title: 'Texto y datos',
                        icon: Icons.text_fields_rounded,
                        fields: contentFields,
                        expanded: true,
                      ),
                    if (mediaFields.isNotEmpty)
                      buildGroup(
                        title: 'Imagen y medios',
                        icon: Icons.image_outlined,
                        fields: mediaFields,
                        expanded: false,
                      ),
                    if (actionFields.isNotEmpty)
                      buildGroup(
                        title: 'Acción y enlace',
                        icon: Icons.ads_click_rounded,
                        fields: actionFields,
                        expanded: false,
                      ),
                    if (collectionFields.isNotEmpty)
                      buildGroup(
                        title: 'Elementos relacionados',
                        icon: Icons.format_list_bulleted_rounded,
                        fields: collectionFields,
                        expanded: false,
                      ),
                    if (optionFields.isNotEmpty)
                      buildGroup(
                        title: 'Opciones',
                        icon: Icons.tune_rounded,
                        fields: optionFields,
                        expanded: false,
                      ),
                  ],
                );
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

    void setSchemaFieldValue(WebsiteBlockFieldSchema field, dynamic value) {
      setFieldValue(field.key, value);
      for (final alias in field.migrationAliases) {
        setFieldValue(alias, value);
      }
    }

    if (definition != null && fields.isNotEmpty) {
      final sections = definition.controlSections;
      final fieldByKey = {for (final f in fields) f.key: f};
      final actionLabelKeys = fields
          .where((field) => field.actionLabelKey != null)
          .map((field) => field.actionLabelKey!)
          .toSet();
      final usedKeys = <String>{};

      final sectionWidgets = <Widget>[];
      if (sections.isNotEmpty) {
        for (final section in sections) {
          final allSectionFields = section.fieldKeys
              .map((k) => fieldByKey[k])
              .whereType<WebsiteBlockFieldSchema>()
              .toList();
          final sectionFields = allSectionFields
              .where((field) => !actionLabelKeys.contains(field.key))
              .toList();

          if (sectionFields.isEmpty) continue;
          usedKeys.addAll(allSectionFields.map((f) => f.key));
          final isFirstVisibleSection = sectionWidgets.isEmpty;

          sectionWidgets.add(
            _CollapsibleSection(
              title: section.label,
              initiallyExpanded: isFirstVisibleSection,
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
                    setValue: (v) => setSchemaFieldValue(f, v),
                    setRelatedValue: setFieldValue,
                    setRelatedValues: (values) =>
                        provider.updateBlockDataMultiple(blockId, values),
                    actionLabelField: f.actionLabelKey == null
                        ? null
                        : fieldByKey[f.actionLabelKey],
                  );
                  yield const SizedBox(height: 16);
                }),
              ],
            ),
          );
          sectionWidgets.add(const SizedBox(height: 12));
        }
      }

      final remainingFields = fields
          .where((f) => !usedKeys.contains(f.key))
          .where((f) => !actionLabelKeys.contains(f.key))
          .toList();
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
                  setValue: (v) => setSchemaFieldValue(f, v),
                  setRelatedValue: setFieldValue,
                  setRelatedValues: (values) =>
                      provider.updateBlockDataMultiple(blockId, values),
                  actionLabelField: f.actionLabelKey == null
                      ? null
                      : fieldByKey[f.actionLabelKey],
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
}

/// Controls for the free-position Canvas block (Wix-like).
class _CanvasBlockControls extends StatelessWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;
  final int? slideIndex;
  final bool elementsOnly;
  final bool selectedElementOnly;
  final _InspectorSection? inspectorSection;
  final ValueChanged<List<Map<String, dynamic>>>? onElementsChanged;
  final ValueChanged<String?>? onActiveElementChanged;
  final void Function(String key, dynamic value)? onCanvasSettingChanged;

  const _CanvasBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
    this.slideIndex,
    this.elementsOnly = false,
    this.selectedElementOnly = false,
    this.inspectorSection,
    this.onElementsChanged,
    this.onActiveElementChanged,
    this.onCanvasSettingChanged,
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
    final id = provider
        .canvasElementSelection(blockId, slideIndex: slideIndex)
        ?.toString();
    if (id == null || id.trim().isEmpty) return null;
    return id.trim();
  }

  void _setActive(String? id) {
    if (onActiveElementChanged != null) {
      onActiveElementChanged!(id);
      return;
    }
    final block = provider.getBlock(blockId);
    final blockData = Map<String, dynamic>.from(
      block?['block_data'] ?? const <String, dynamic>{},
    );
    final slides = blockData['slides'];
    provider.selectCanvasElement(
      blockId,
      id,
      slideIndex: slideIndex,
      slideCount: slideIndex == null || slides is! List ? null : slides.length,
    );
  }

  void _setElements(List<Map<String, dynamic>> elements) {
    if (onElementsChanged != null) {
      onElementsChanged!(elements);
      return;
    }
    provider.updateBlockData(blockId, 'elements', elements);
  }

  void _setCanvasSetting(String key, dynamic value) {
    if (onCanvasSettingChanged != null) {
      onCanvasSettingChanged!(key, value);
      return;
    }
    provider.updateBlockData(blockId, key, value);
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

  void _moveElementToEdge(String elementId, {required bool front}) {
    final elements = _elements();
    final idx = elements.indexWhere((e) => e['id']?.toString() == elementId);
    if (idx == -1 || elements.length < 2) return;
    final target = front ? elements.length - 1 : 0;
    if (idx == target) return;
    final item = elements.removeAt(idx);
    elements.insert(front ? elements.length : 0, item);
    _setElements(elements);
  }

  void _alignElementToCanvas(String elementId, String alignment) {
    final elements = _elements();
    final idx = elements.indexWhere((e) => e['id']?.toString() == elementId);
    if (idx == -1 || elements[idx]['locked'] == true) return;

    final element = elements[idx];
    final width = (element['w'] as num?)?.toDouble() ?? 200;
    final height = (element['h'] as num?)?.toDouble() ?? 56;
    final designWidth = (data['designWidth'] as num?)?.toDouble() ?? 1200.0;
    final designHeight = (data['designHeight'] as num?)?.toDouble() ??
        (data['blockHeight'] as num?)?.toDouble() ??
        750.0;
    var x = (element['x'] as num?)?.toDouble() ?? 0;
    var y = (element['y'] as num?)?.toDouble() ?? 0;

    switch (alignment) {
      case 'left':
        x = 0;
        break;
      case 'hCenter':
        x = (designWidth - width) / 2;
        break;
      case 'right':
        x = designWidth - width;
        break;
      case 'top':
        y = 0;
        break;
      case 'vCenter':
        y = (designHeight - height) / 2;
        break;
      case 'bottom':
        y = designHeight - height;
        break;
    }
    _updateElement(elementId, {'x': x, 'y': y});
  }

  Widget _inspectorLayoutAction({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    Key? key,
  }) {
    return Expanded(
      child: OutlinedButton.icon(
        key: key,
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10.5),
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 7),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  Widget _buildElementArrangeControls(
    Map<String, dynamic> active,
    List<Map<String, dynamic>> elements,
  ) {
    final activeId = active['id']?.toString() ?? '';
    final index = elements.indexWhere((e) => e['id']?.toString() == activeId);
    final locked = active['locked'] == true;
    final canMoveBackward = index > 0;
    final canMoveForward = index >= 0 && index < elements.length - 1;

    return _CollapsibleSection(
      title: 'Alinear y ordenar',
      icon: Icons.layers_outlined,
      initiallyExpanded: true,
      children: [
        const Text(
          'Las acciones relativas también están siempre visibles en el toolbar del lienzo.',
          style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.3),
        ),
        const SizedBox(height: 14),
        const _SectionHeader('Orden de capas'),
        const SizedBox(height: 8),
        Row(
          children: [
            _inspectorLayoutAction(
              key: const ValueKey('inspector_layer_backward'),
              label: 'Una atrás',
              icon: Icons.flip_to_back_rounded,
              onPressed:
                  canMoveBackward ? () => _moveElement(activeId, -1) : null,
            ),
            const SizedBox(width: 8),
            _inspectorLayoutAction(
              key: const ValueKey('inspector_layer_forward'),
              label: 'Una adelante',
              icon: Icons.flip_to_front_rounded,
              onPressed:
                  canMoveForward ? () => _moveElement(activeId, 1) : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _inspectorLayoutAction(
              label: 'Al fondo',
              icon: Icons.vertical_align_bottom_rounded,
              onPressed: canMoveBackward
                  ? () => _moveElementToEdge(activeId, front: false)
                  : null,
            ),
            const SizedBox(width: 8),
            _inspectorLayoutAction(
              label: 'Al frente',
              icon: Icons.vertical_align_top_rounded,
              onPressed: canMoveForward
                  ? () => _moveElementToEdge(activeId, front: true)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _SectionHeader('Alinear al lienzo'),
        if (locked) ...[
          const SizedBox(height: 6),
          const Text(
            'Desbloquea la capa para cambiar su posición.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            _inspectorLayoutAction(
              label: 'Izquierda',
              icon: Icons.align_horizontal_left_rounded,
              onPressed:
                  locked ? null : () => _alignElementToCanvas(activeId, 'left'),
            ),
            const SizedBox(width: 6),
            _inspectorLayoutAction(
              label: 'Centro',
              icon: Icons.align_horizontal_center_rounded,
              onPressed: locked
                  ? null
                  : () => _alignElementToCanvas(activeId, 'hCenter'),
            ),
            const SizedBox(width: 6),
            _inspectorLayoutAction(
              label: 'Derecha',
              icon: Icons.align_horizontal_right_rounded,
              onPressed: locked
                  ? null
                  : () => _alignElementToCanvas(activeId, 'right'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _inspectorLayoutAction(
              label: 'Arriba',
              icon: Icons.align_vertical_top_rounded,
              onPressed:
                  locked ? null : () => _alignElementToCanvas(activeId, 'top'),
            ),
            const SizedBox(width: 6),
            _inspectorLayoutAction(
              label: 'Medio',
              icon: Icons.align_vertical_center_rounded,
              onPressed: locked
                  ? null
                  : () => _alignElementToCanvas(activeId, 'vCenter'),
            ),
            const SizedBox(width: 6),
            _inspectorLayoutAction(
              label: 'Abajo',
              icon: Icons.align_vertical_bottom_rounded,
              onPressed: locked
                  ? null
                  : () => _alignElementToCanvas(activeId, 'bottom'),
            ),
          ],
        ),
      ],
    );
  }

  void _addElement(String type) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final id = 'el_$now';
    final elements = _elements();
    final next = createCanvasElement(id: id, type: type);
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
    final focalPointX = (data['focalPointX'] as num?)?.toDouble() ?? 0.5;
    final focalPointY = (data['focalPointY'] as num?)?.toDouble() ?? 0.5;
    final mobileFocalPointX =
        (data['mobileFocalPointX'] as num?)?.toDouble() ?? focalPointX;
    final mobileFocalPointY =
        (data['mobileFocalPointY'] as num?)?.toDouble() ?? focalPointY;
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
        if (!elementsOnly) ...[
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
                  onChanged: (v) =>
                      provider.updateBlockData(blockId, 'vhPct', v),
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
              WebsiteColorPickerField(
                label: 'Color de fondo',
                value: bg,
                allowAlpha: true,
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
                onChanged: (url) => provider.updateBlockData(
                    blockId, 'backgroundImageUrl', url),
              ),
              if (backgroundImageUrl.isNotEmpty) ...[
                const SizedBox(height: 12),
                const _SectionHeader('Foco de imagen'),
                const SizedBox(height: 8),
                FocalPointPicker(
                  imageUrl: backgroundImageUrl,
                  focalX: focalPointX,
                  focalY: focalPointY,
                  onChanged: (x, y) => provider.updateBlockDataMultiple(
                    blockId,
                    {'focalPointX': x, 'focalPointY': y},
                  ),
                ),
                const SizedBox(height: 12),
                const _SectionHeader('Foco móvil'),
                const SizedBox(height: 8),
                FocalPointPicker(
                  imageUrl: backgroundImageUrl,
                  focalX: mobileFocalPointX,
                  focalY: mobileFocalPointY,
                  onChanged: (x, y) => provider.updateBlockDataMultiple(
                    blockId,
                    {'mobileFocalPointX': x, 'mobileFocalPointY': y},
                  ),
                ),
                const SizedBox(height: 12),
                _EditorTextField(
                  label: 'Texto alternativo',
                  value: (data['backgroundImageAltText'] ?? '').toString(),
                  onChanged: (value) => provider.updateBlockData(
                    blockId,
                    'backgroundImageAltText',
                    value,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const _SectionHeader('Video de fondo'),
              const SizedBox(height: 8),
              _VideoPicker(
                currentUrl: backgroundVideoUrl,
                onChanged: (url) => provider.updateBlockDataMultiple(
                  blockId,
                  {
                    'backgroundVideoUrl': url,
                    if (url.isNotEmpty) 'backgroundYoutubeId': '',
                  },
                ),
              ),
              const SizedBox(height: 12),
              _CollapsibleSection(
                title: 'Enlaces avanzados',
                icon: Icons.link_rounded,
                initiallyExpanded: false,
                children: [
                  const Text(
                    'Usa estas opciones sólo para recursos ya alojados o videos de YouTube.',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _EditorTextField(
                    label: 'URL directa de video (mp4/webm)',
                    value: backgroundVideoUrl,
                    onChanged: (v) => provider.updateBlockData(
                      blockId,
                      'backgroundVideoUrl',
                      v,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _EditorTextField(
                    label: 'YouTube URL / ID',
                    value: backgroundYoutubeId,
                    onChanged: (v) {
                      String id = v;
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
                      provider.updateBlockData(
                        blockId,
                        'backgroundYoutubeId',
                        id,
                      );
                    },
                    hint: 'Pega el enlace o ID',
                  ),
                ],
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
                WebsiteColorPickerField(
                  label: 'Color del overlay',
                  value: overlayColor,
                  allowAlpha: false,
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
        ],

        // ========== CANVAS-WIDE LAYOUT POLICY ==========
        if (!selectedElementOnly)
          _CollapsibleSection(
            title: 'Reglas del lienzo',
            icon: Icons.crop_free_rounded,
            initiallyExpanded: true,
            children: [
              _EditorToggle(
                label: 'Restringir capas al área segura',
                value: data['constrainElementsToSafeArea'] != false,
                onChanged: (value) => _setCanvasSetting(
                  'constrainElementsToSafeArea',
                  value,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                data['constrainElementsToSafeArea'] == false
                    ? 'Sangrado general activado: cualquier capa puede cruzar la guía. La parte fuera de la diapositiva se recorta en vista previa.'
                    : 'Regla general activa para capas actuales y nuevas. La guía visible conserva la composición entre editor y vista previa.',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ],
          ),

        // ========== CANVAS ELEMENTS ==========
        if (!selectedElementOnly)
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
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _addElement('image'),
                      icon: const Icon(Icons.image_outlined, size: 18),
                      label: const Text('Imagen'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _addElement('shape'),
                      icon: const Icon(Icons.rectangle_outlined, size: 18),
                      label: const Text('Forma'),
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
                    final title = switch (type) {
                      'button' => (e['label'] ?? 'Botón').toString(),
                      'image' =>
                        (e['altText'] ?? 'Imagen').toString().trim().isEmpty
                            ? 'Imagen'
                            : e['altText'].toString(),
                      'shape' => 'Forma',
                      'product' => 'Producto',
                      'productsGallery' => 'Galería de productos',
                      _ => (e['text'] ?? 'Texto').toString(),
                    };
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
                          switch (type) {
                            'button' => Icons.smart_button_rounded,
                            'image' => Icons.image_outlined,
                            'shape' => Icons.rectangle_outlined,
                            'product' => Icons.inventory_2_outlined,
                            'productsGallery' => Icons.grid_view_rounded,
                            _ => Icons.text_fields_rounded,
                          },
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
        if (active != null &&
            (inspectorSection == null ||
                inspectorSection == _InspectorSection.layout)) ...[
          _CollapsibleSection(
            title: 'Posición y tamaño',
            icon: Icons.open_with_rounded,
            initiallyExpanded: true,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _EditorTextField(
                      label: 'X',
                      value: ((active['x'] as num?)?.toDouble() ?? 0)
                          .toStringAsFixed(0),
                      onChanged: (v) {
                        final parsed = double.tryParse(v);
                        if (parsed != null) {
                          _updateElement(activeId!, {'x': parsed});
                        }
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
                        if (parsed != null) {
                          _updateElement(activeId!, {'y': parsed});
                        }
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
                      label: 'Ancho',
                      value: ((active['w'] as num?)?.toDouble() ?? 200)
                          .toStringAsFixed(0),
                      onChanged: (v) {
                        final parsed = double.tryParse(v);
                        if (parsed != null) {
                          _updateElement(
                            activeId!,
                            {'w': parsed.clamp(40, 2000)},
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _EditorTextField(
                      label: 'Alto',
                      value: ((active['h'] as num?)?.toDouble() ?? 56)
                          .toStringAsFixed(0),
                      onChanged: (v) {
                        final parsed = double.tryParse(v);
                        if (parsed != null) {
                          _updateElement(
                            activeId!,
                            {'h': parsed.clamp(30, 2000)},
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _EditorSlider(
                label: 'Rotación',
                value: ((active['rotation'] as num?)?.toDouble() ?? 0)
                    .clamp(-180, 180),
                min: -180,
                max: 180,
                divisions: 360,
                valueLabel:
                    '${((active['rotation'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}°',
                onChanged: (v) => _updateElement(activeId!, {'rotation': v}),
              ),
              if (((active['rotation'] as num?)?.toDouble() ?? 0).abs() > 0.01)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _updateElement(activeId!, {'rotation': 0}),
                    icon: const Icon(Icons.restart_alt_rounded, size: 16),
                    label: const Text('Restablecer rotación'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF20C5C1),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              _EditorToggle(
                label: 'Bloquear ajustes directos',
                value: active['locked'] == true,
                onChanged: (v) => _updateElement(activeId!, {'locked': v}),
              ),
              const SizedBox(height: 5),
              const Text(
                'Evita mover, redimensionar, recortar o rotar accidentalmente desde el lienzo. Los valores precisos siguen disponibles aquí.',
                style:
                    TextStyle(color: Colors.white38, fontSize: 11, height: 1.3),
              ),
              const SizedBox(height: 12),
              _EditorDropdown(
                label: 'Visibilidad adaptable',
                value: active['showOnMobile'] == true
                    ? 'mobile'
                    : active['hideOnMobile'] == true
                        ? 'desktop'
                        : 'all',
                options: const [
                  ('all', 'Escritorio y móvil'),
                  ('desktop', 'Solo escritorio'),
                  ('mobile', 'Solo móvil'),
                ],
                onChanged: (value) => _updateElement(activeId!, {
                  'hideOnMobile': value == 'desktop',
                  'showOnMobile': value == 'mobile',
                }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildElementArrangeControls(active, elements),
        ],
        if (active != null &&
            (inspectorSection == null ||
                inspectorSection == _InspectorSection.content ||
                inspectorSection == _InspectorSection.style)) ...[
          _CollapsibleSection(
            title: inspectorSection == _InspectorSection.content
                ? 'Contenido'
                : inspectorSection == _InspectorSection.style
                    ? 'Apariencia'
                    : 'Contenido y apariencia',
            icon: switch (activeType) {
              'button' => Icons.smart_button_rounded,
              'image' => Icons.image_outlined,
              'shape' => Icons.rectangle_outlined,
              'product' => Icons.inventory_2_outlined,
              'productsGallery' => Icons.grid_view_rounded,
              _ => Icons.text_fields_rounded,
            },
            initiallyExpanded: selectedElementOnly,
            children: [
              if (activeType == 'text') ...[
                if (inspectorSection != _InspectorSection.style) ...[
                  _EditorTextField(
                    label: 'Texto',
                    value: active['text']?.toString() ?? '',
                    onChanged: (v) => _updateElement(activeId!, {'text': v}),
                    maxLines: 3,
                  ),
                ],
                if (inspectorSection != _InspectorSection.content) ...[
                  _EditorSlider(
                    label: 'Tamaño fuente',
                    value: ((active['fontSize'] as num?)?.toDouble() ?? 24)
                        .clamp(10, 80),
                    min: 10,
                    max: 80,
                    divisions: 70,
                    valueLabel:
                        '${((active['fontSize'] as num?)?.toDouble() ?? 24).toStringAsFixed(0)}px',
                    onChanged: (v) =>
                        _updateElement(activeId!, {'fontSize': v}),
                  ),
                  const SizedBox(height: 12),
                  _EditorDropdown(
                    label: 'Tipografía del tema',
                    value: (active['fontRole'] ?? 'heading').toString(),
                    options: const [
                      ('heading', 'Títulos'),
                      ('body', 'Texto general'),
                    ],
                    onChanged: (v) =>
                        _updateElement(activeId!, {'fontRole': v}),
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
                  WebsiteColorPickerField(
                    label: 'Color del texto',
                    value: (active['color'] ?? '#111111').toString(),
                    allowAlpha: true,
                    onChanged: (v) => _updateElement(activeId!, {'color': v}),
                  ),
                  const SizedBox(height: 12),
                  _EditorSlider(
                    label: 'Espaciado de letras',
                    value: ((active['letterSpacing'] as num?)?.toDouble() ?? 0)
                        .clamp(-1, 8),
                    min: -1,
                    max: 8,
                    divisions: 18,
                    valueLabel:
                        ((active['letterSpacing'] as num?)?.toDouble() ?? 0)
                            .toStringAsFixed(1),
                    onChanged: (v) =>
                        _updateElement(activeId!, {'letterSpacing': v}),
                  ),
                  const SizedBox(height: 12),
                  _EditorSlider(
                    label: 'Interlineado',
                    value: ((active['lineHeight'] as num?)?.toDouble() ?? 1.1)
                        .clamp(0.8, 2.0),
                    min: 0.8,
                    max: 2.0,
                    divisions: 12,
                    valueLabel:
                        ((active['lineHeight'] as num?)?.toDouble() ?? 1.1)
                            .toStringAsFixed(1),
                    onChanged: (v) =>
                        _updateElement(activeId!, {'lineHeight': v}),
                  ),
                  const SizedBox(height: 12),
                  _EditorToggle(
                    label: 'MAYÚSCULAS',
                    value: active['uppercase'] == true,
                    onChanged: (v) =>
                        _updateElement(activeId!, {'uppercase': v}),
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
                ],
              ] else if (activeType == 'button') ...[
                if (inspectorSection != _InspectorSection.style) ...[
                  WebsiteActionEditor(
                    showVariant: true,
                    value: WebsiteActionValue.resolvePrimary(
                          active,
                          labelKeys: const ['label'],
                          hrefKeys: const ['link'],
                          defaultLabel: 'Botón',
                          defaultHref: '/',
                          defaultVariant: WebsiteActionVariant.fromStorage(
                            active['style']?.toString(),
                          ),
                        ) ??
                        const WebsiteActionValue(
                          label: 'Botón',
                          href: '/',
                        ),
                    onChanged: (action) => _updateElement(activeId!, {
                      'label': action.label,
                      'link': action.href,
                      'style': action.variant.storageValue,
                      'actions': WebsiteActionValue.mergePrimary(
                        active['actions'],
                        action,
                      ),
                    }),
                  ),
                ],
                if (inspectorSection != _InspectorSection.content) ...[
                  _EditorToggle(
                    label: 'Usar estilo global del tema',
                    value: active['inheritTheme'] != false,
                    onChanged: (v) =>
                        _updateElement(activeId!, {'inheritTheme': v}),
                  ),
                  if (active['inheritTheme'] == false) ...[
                    const SizedBox(height: 12),
                    WebsiteColorPickerField(
                      label: 'Color del botón',
                      value: (active['bgColor'] ?? '#00A09D').toString(),
                      allowAlpha: true,
                      onChanged: (v) =>
                          _updateElement(activeId!, {'bgColor': v}),
                    ),
                    const SizedBox(height: 12),
                    WebsiteColorPickerField(
                      label: 'Color del texto',
                      value: (active['fgColor'] ?? '#FFFFFF').toString(),
                      allowAlpha: true,
                      onChanged: (v) =>
                          _updateElement(activeId!, {'fgColor': v}),
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
                      onChanged: (v) =>
                          _updateElement(activeId!, {'radius': v}),
                    ),
                    const SizedBox(height: 12),
                    _EditorToggle(
                      label: 'Sombra',
                      value: (active['shadow'] as bool?) ?? false,
                      onChanged: (v) =>
                          _updateElement(activeId!, {'shadow': v}),
                    ),
                    const SizedBox(height: 12),
                    _EditorToggle(
                      label: 'MAYÚSCULAS',
                      value: (active['uppercase'] as bool?) ?? false,
                      onChanged: (v) =>
                          _updateElement(activeId!, {'uppercase': v}),
                    ),
                    const SizedBox(height: 12),
                    _EditorSlider(
                      label: 'Letter spacing',
                      value:
                          ((active['letterSpacing'] as num?)?.toDouble() ?? 0.0)
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
              ] else if (activeType == 'image') ...[
                if (inspectorSection != _InspectorSection.style) ...[
                  const _SectionHeader('Producto vinculado (opcional)'),
                  const SizedBox(height: 8),
                  _CanvasProductSelector(
                    currentProductId: (active['productId'] ?? '').toString(),
                    onChanged: (id) => _updateElement(activeId!, {
                      'productId': id,
                      'imageSource': id.isEmpty ? 'manual' : 'product',
                    }),
                  ),
                  if ((active['productId'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _EditorDropdown(
                      label: 'Imagen visible',
                      value: (active['imageSource'] ?? 'product').toString(),
                      options: const [
                        ('product', 'Imagen actual del catálogo'),
                        ('manual', 'Imagen seleccionada / recorte'),
                      ],
                      onChanged: (v) =>
                          _updateElement(activeId!, {'imageSource': v}),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      (active['imageSource'] ?? 'product') == 'manual'
                          ? 'La capa conserva el vínculo comercial, pero muestra el recurso seleccionado abajo. Útil para recortes transparentes y campañas.'
                          : 'La capa sigue automáticamente la imagen principal del producto en el catálogo.',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const _SectionHeader('Imagen seleccionada'),
                  const SizedBox(height: 8),
                  _ImagePicker(
                    currentUrl: (active['imageUrl'] ?? '').toString(),
                    allowProductLink: true,
                    onAssetChanged: (selection) => _updateElement(activeId!, {
                      'imageUrl': selection.publicUrl,
                      if (selection.linksProduct) ...{
                        'productId': selection.productId ?? '',
                        'imageSource': selection.productImageIndex == 0
                            ? 'product'
                            : 'manual',
                      } else ...{
                        if (selection.comesFromProduct) 'productId': '',
                        'imageSource': 'manual',
                      },
                    }),
                  ),
                  const SizedBox(height: 12),
                  _EditorTextField(
                    label: 'Texto alternativo',
                    value: (active['altText'] ?? '').toString(),
                    onChanged: (v) => _updateElement(activeId!, {'altText': v}),
                  ),
                ],
                if (inspectorSection != _InspectorSection.content) ...[
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
                    label: 'Encuadre horizontal',
                    value:
                        (((active['focalPointX'] as num?)?.toDouble() ?? 0.5) *
                                100)
                            .clamp(0, 100),
                    min: 0,
                    max: 100,
                    divisions: 100,
                    valueLabel:
                        '${((((active['focalPointX'] as num?)?.toDouble() ?? 0.5) * 100)).round()}%',
                    onChanged: (v) =>
                        _updateElement(activeId!, {'focalPointX': v / 100}),
                  ),
                  const SizedBox(height: 12),
                  _EditorSlider(
                    label: 'Encuadre vertical',
                    value:
                        (((active['focalPointY'] as num?)?.toDouble() ?? 0.5) *
                                100)
                            .clamp(0, 100),
                    min: 0,
                    max: 100,
                    divisions: 100,
                    valueLabel:
                        '${((((active['focalPointY'] as num?)?.toDouble() ?? 0.5) * 100)).round()}%',
                    onChanged: (v) =>
                        _updateElement(activeId!, {'focalPointY': v / 100}),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _updateElement(activeId!, {
                        'fit': 'cover',
                        'focalPointX': 0.5,
                        'focalPointY': 0.5,
                      }),
                      icon: const Icon(Icons.center_focus_strong_rounded,
                          size: 16),
                      label: const Text('Centrar encuadre'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF20C5C1),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                  const Text(
                    'En el lienzo: doble clic o usa Recortar; arrastra la imagen para reencuadrar y sus ocho bordes para cambiar el marco.',
                    style: TextStyle(
                        color: Colors.white38, fontSize: 11, height: 1.3),
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
                ],
              ] else if (activeType == 'shape') ...[
                if (inspectorSection != _InspectorSection.style) ...[
                  _EditorDropdown(
                    label: 'Forma',
                    value: (active['shape'] ?? 'rectangle').toString(),
                    options: const [
                      ('rectangle', 'Rectángulo'),
                      ('ellipse', 'Elipse'),
                    ],
                    onChanged: (v) => _updateElement(activeId!, {'shape': v}),
                  ),
                ],
                if (inspectorSection != _InspectorSection.content) ...[
                  WebsiteColorPickerField(
                    label: 'Color de relleno',
                    value: (active['fillColor'] ?? '#1F2937').toString(),
                    allowAlpha: true,
                    onChanged: (v) =>
                        _updateElement(activeId!, {'fillColor': v}),
                  ),
                  const SizedBox(height: 12),
                  WebsiteColorPickerField(
                    label: 'Color de borde',
                    value: (active['borderColor'] ?? '#1F2937').toString(),
                    allowAlpha: true,
                    onChanged: (v) =>
                        _updateElement(activeId!, {'borderColor': v}),
                  ),
                  const SizedBox(height: 12),
                  _EditorSlider(
                    label: 'Borde',
                    value: ((active['borderWidth'] as num?)?.toDouble() ?? 0)
                        .clamp(0, 16),
                    min: 0,
                    max: 16,
                    divisions: 16,
                    valueLabel:
                        '${((active['borderWidth'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}px',
                    onChanged: (v) =>
                        _updateElement(activeId!, {'borderWidth': v}),
                  ),
                  const SizedBox(height: 12),
                  if ((active['shape'] ?? 'rectangle') == 'rectangle')
                    _EditorSlider(
                      label: 'Radio',
                      value: ((active['radius'] as num?)?.toDouble() ?? 0)
                          .clamp(0, 80),
                      min: 0,
                      max: 80,
                      divisions: 40,
                      valueLabel:
                          '${((active['radius'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}px',
                      onChanged: (v) =>
                          _updateElement(activeId!, {'radius': v}),
                    ),
                ],
              ] else if (activeType == 'product') ...[
                if (inspectorSection != _InspectorSection.style) ...[
                  _CanvasProductSelector(
                    currentProductId: (active['productId'] ?? '').toString(),
                    onChanged: (id) =>
                        _updateElement(activeId!, {'productId': id}),
                  ),
                  const SizedBox(height: 12),
                  _EditorToggle(
                    label: 'Mostrar precio',
                    value: (active['showPrice'] as bool?) ?? true,
                    onChanged: (v) =>
                        _updateElement(activeId!, {'showPrice': v}),
                  ),
                ],
                if (inspectorSection != _InspectorSection.content) ...[
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
              ] else if (activeType == 'productsGallery') ...[
                if (inspectorSection != _InspectorSection.style) ...[
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
                  _EditorSlider(
                    label: 'Máx productos',
                    value: ((active['maxProducts'] as num?)?.toDouble() ?? 6)
                        .clamp(1, 24),
                    min: 1,
                    max: 24,
                    divisions: 23,
                    valueLabel: '${(active['maxProducts'] ?? 6)}',
                    onChanged: (v) => _updateElement(
                      activeId!,
                      {'maxProducts': v.round()},
                    ),
                  ),
                  if ((active['mode'] ?? 'latest').toString() == 'manual') ...[
                    const SizedBox(height: 12),
                    _CanvasProductsMultiSelector(
                      selectedIds: ((active['productIds'] as List?) ?? const [])
                          .map((e) => e.toString())
                          .where((e) => e.isNotEmpty)
                          .toList(),
                      onConfirm: (ids) =>
                          _updateElement(activeId!, {'productIds': ids}),
                    ),
                  ],
                ],
                if (inspectorSection != _InspectorSection.content) ...[
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
                  if ((active['layout'] ?? 'grid').toString() == 'grid')
                    _EditorSlider(
                      label: 'Columnas',
                      value: ((active['columns'] as num?)?.toDouble() ?? 3)
                          .clamp(1, 4),
                      min: 1,
                      max: 4,
                      divisions: 3,
                      valueLabel: '${(active['columns'] ?? 3)}',
                      onChanged: (v) => _updateElement(
                        activeId!,
                        {'columns': v.round()},
                      ),
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
              ],
              if (inspectorSection == null) ...[
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
  bool _isDetecting = false; // Prevent concurrent detection
  // ignore: unused_field
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
    if (!mounted || _isDetecting) return;
    _isDetecting = true;

    try {
      // Prefer detecting route from actual URL, fallback to provider
      var newRoute = _getSlugFromRoute() ??
          widget.editProvider.currentPageSlug ??
          'inicio';
      if (newRoute.isEmpty) newRoute = 'inicio';

      debugPrint('📄 [PageSettingsTab] Detecting page: $newRoute');

      // Avoid reloading if route hasn't changed
      if (newRoute == _currentRoute && !_isLoading) {
        _isDetecting = false;
        return;
      }

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
    } finally {
      _isDetecting = false;
    }
  }

  /// Detect current slug from URL route (handles /tienda prefix and various patterns)
  String? _getSlugFromRoute() {
    try {
      final uri = GoRouterState.of(context).uri;
      var path = uri.path;

      // Remove /tienda prefix if present
      if (path.startsWith('/tienda')) {
        path = path.substring('/tienda'.length);
      }
      if (path.isEmpty || path == '/') return 'inicio';
      if (!path.startsWith('/')) path = '/$path';

      // Known canonical routes
      const canonicalRoutes = {
        '/productos': 'productos',
        '/contacto': 'contacto',
        '/carrito': 'carrito',
        '/checkout': 'checkout',
        '/cuenta': 'cuenta',
      };
      if (canonicalRoutes.containsKey(path)) {
        return canonicalRoutes[path]!;
      }

      // Policy pages at root level
      const policySlugs = {
        'nosotros',
        'terminos',
        'privacidad',
        'devoluciones',
        'envios'
      };
      final rootSlug = path.substring(1);
      if (policySlugs.contains(rootSlug)) return rootSlug;

      // /pagina/<slug> pattern
      if (path.startsWith('/pagina/')) return path.substring('/pagina/'.length);

      // Simple slug
      if (!rootSlug.contains('/')) return rootSlug;

      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadPageData() async {
    final pageSlug = _currentRoute; // Use the route we detected, not provider

    // Clear old page data first to avoid stale display
    _currentPage = null;

    // Home page check removed to use standard website_pages table logic

    try {
      final service = context.read<WebsiteService>();
      WebsitePage? page;

      // Only use provider's pageId if it matches our current route
      final providerSlug = widget.editProvider.currentPageSlug ?? '';
      final providerPageId = widget.editProvider.currentPageId;

      if (providerPageId != null && providerSlug == pageSlug) {
        page = await service.getPageById(providerPageId);
      } else {
        // Lookup by slug (our detected route)
        page = await service.getPageBySlug(pageSlug);
      }

      if (!mounted) return;

      if (page != null) {
        _currentPage = page;
        // Don't override _currentRoute here - keep what we detected
        final routeKey = _currentRoute.split('/').first;
        final pending = widget.editProvider.getPendingPageSeo(routeKey);
        _metaTitleController.text =
            pending?['meta_title'] ?? page.metaTitle ?? '';
        _metaDescriptionController.text =
            pending?['meta_description'] ?? page.metaDescription ?? '';
        setState(() => _isLoading = false);
      } else {
        // Page not found in DB - use _currentRoute for display
        if (_isSpecialRoute) {
          // Fallback: Try loading from legacy website_settings
          final service = context.read<WebsiteService>();
          final routeKey = _currentRoute.split('/').first;
          final pending = widget.editProvider.getPendingPageSeo(routeKey);
          _metaTitleController.text = pending?['meta_title'] ??
              service.getSetting('seo_${routeKey}_title', '');
          _metaDescriptionController.text = pending?['meta_description'] ??
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

  void _stageSeoChanges() {
    final routeKey = _currentRoute.split('/').first;
    if (routeKey.isEmpty) return;
    widget.editProvider.updatePageSeo(
      routeKey: routeKey,
      metaTitle: _metaTitleController.text,
      metaDescription: _metaDescriptionController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Check if route changed on every build (navigation might not trigger didUpdateWidget)
    final routeSlug = _getSlugFromRoute();
    if (routeSlug != null &&
        routeSlug != _currentRoute &&
        !_isLoading &&
        !_isDetecting) {
      // Schedule re-detection after this build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isDetecting) _detectCurrentPage();
      });
    }

    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(color: Color(0xFF00A09D)),
        ),
      );
    }

    final pageName = _currentRoute; // Always use detected route, not DB page

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
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Los cambios se guardarán al presionar "Guardar" en la barra superior.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 20),
          const Divider(color: Colors.white12),
          const SizedBox(height: 16),

          // Meta Title
          _buildField(
            label: 'Meta título',
            controller: _metaTitleController,
            hint: 'Título para Google',
            helperText: 'Lo que aparece en las búsquedas de Google',
          ),
          const SizedBox(height: 16),

          // Meta Description
          _buildField(
            label: 'Meta descripción',
            controller: _metaDescriptionController,
            hint: 'Descripción para Google',
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
          maxLines: maxLines,
          onChanged: (_) => _stageSeoChanges(),
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
  String _headingFont = WebsiteFontRegistry.headingDefault;
  String _bodyFont = WebsiteFontRegistry.bodyDefault;
  String _headingSize = 'normal';
  String _bodySize = 'normal';

  // Button styles
  String _buttonStyle = 'rounded'; // rounded, sharp, pill
  String _buttonSize = 'medium'; // small, medium, large

  // Page Background
  String _pageBackground = '#FFFFFF';

  bool _loaded = false;

  static const _fonts = WebsiteFontRegistry.supportedFamilies;

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
          _headingFont = WebsiteFontRegistry.resolveHeadingFont(
            service.getSetting(
              'theme_heading_font',
              WebsiteFontRegistry.headingDefault,
            ),
          );
          _bodyFont = WebsiteFontRegistry.resolveBodyFont(
            service.getSetting(
              'theme_body_font',
              WebsiteFontRegistry.bodyDefault,
            ),
          );
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
            WebsiteColorPickerField(
              label: 'Color principal',
              value: _primaryColorController.text,
              allowAlpha: false,
              onChanged: (val) {
                setState(() => _primaryColorController.text = val);
                context
                    .read<WebsiteEditModeProvider>()
                    .updateThemeSetting('theme_primary_color', val);
              },
            ),
            const SizedBox(height: 24),
            const _SectionHeader('COLOR DE ACENTO'),
            const SizedBox(height: 12),
            WebsiteColorPickerField(
              label: 'Color de acento',
              value: _accentColorController.text,
              allowAlpha: false,
              onChanged: (val) {
                setState(() => _accentColorController.text = val);
                context
                    .read<WebsiteEditModeProvider>()
                    .updateThemeSetting('theme_accent_color', val);
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
              labels: WebsiteFontRegistry.labelsByFamily,
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
              labels: WebsiteFontRegistry.labelsByFamily,
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
              onChanged: (v) {
                if (v == null) return;
                setState(() => _buttonSize = v);
                context
                    .read<WebsiteEditModeProvider>()
                    .updateThemeSetting('button_size', v);
              },
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
            WebsiteColorPickerField(
              label: 'Color de fondo',
              value: _pageBackground,
              allowAlpha: false,
              onChanged: (val) {
                setState(() => _pageBackground = val);
                context
                    .read<WebsiteEditModeProvider>()
                    .updateThemeSetting('theme_background_color', val);
              },
            ),
          ],
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStyleOption(String label, String value, bool isSelected) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _buttonStyle = value);
          context
              .read<WebsiteEditModeProvider>()
              .updateThemeSetting('button_style', value);
        },
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
      final sanitizedName = _sanitizeFileName(image.name);
      final fileName =
          'logo_${DateTime.now().millisecondsSinceEpoch}_$sanitizedName';
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

class _InspectorIntro extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;

  const _InspectorIntro({
    required this.title,
    required this.description,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF00A09D).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF00A09D).withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF20C5C1)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Collapsible section for progressive disclosure in the inspector.
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    Icon(
                      widget.icon,
                      color: const Color(0xFF20C5C1),
                      size: 17,
                    ),
                    const SizedBox(width: 9),
                  ],
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.15,
                      ),
                    ),
                  ),
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: Colors.white54,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded) ...[
            const Divider(height: 1, color: Colors.white10),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.children,
              ),
            ),
          ],
        ],
      ),
    );
  }
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
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
        const SizedBox(width: 8),
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
  final ValueChanged<String>? onChanged;
  final ValueChanged<WebsiteMediaAsset>? onAssetChanged;
  final bool allowProductLink;

  const _ImagePicker({
    this.currentUrl,
    this.onChanged,
    this.onAssetChanged,
    this.allowProductLink = false,
  }) : assert(onChanged != null || onAssetChanged != null);

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
  bool _isRemovingBackground = false;

  void _emitAsset(WebsiteMediaAsset asset) {
    final onAssetChanged = widget.onAssetChanged;
    if (onAssetChanged != null) {
      onAssetChanged(asset);
      return;
    }
    widget.onChanged?.call(asset.publicUrl);
  }

  void _emitUrl(String url) {
    _emitAsset(
      WebsiteMediaAsset(
        name: url.isEmpty ? 'Sin imagen' : 'Imagen seleccionada',
        path: url,
        publicUrl: url,
      ),
    );
  }

  Future<String?> _currentTenantId() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;
    final profile = await Supabase.instance.client
        .from('user_profiles')
        .select('tenant_id')
        .eq('user_id', user.id)
        .maybeSingle();
    return profile?['tenant_id']?.toString();
  }

  Future<void> _removeBackground() async {
    final currentUrl = widget.currentUrl?.trim() ?? '';
    if (currentUrl.isEmpty || _isRemovingBackground) return;
    setState(() => _isRemovingBackground = true);
    try {
      final tenantId = await _currentTenantId();
      if (!mounted) return;
      final selection = await showWebsiteBackgroundRemovalDialog(
        context: context,
        imageUrl: currentUrl,
        tenantId: tenantId,
      );
      if (!mounted || selection == null) return;
      final service = WebsiteBackgroundRemovalService();
      final resultUrl = selection.imageUrl ??
          await service.uploadTransparentPng(
            selection.pngBytes!,
            prefix: 'block-no-bg',
          );
      if (!mounted) return;
      _emitUrl(resultUrl);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fondo eliminado y PNG guardado en la biblioteca.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isRemovingBackground = false);
    }
  }

  Future<void> _pickAndUploadImage() async {
    try {
      final selection = await showWebsiteMediaPicker(
        context: context,
        currentUrl: widget.currentUrl,
        allowProductLink: widget.allowProductLink,
      );
      if (selection != null) _emitAsset(selection);
    } catch (e) {
      debugPrint('Error selecting image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al seleccionar imagen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = widget.currentUrl != null && widget.currentUrl!.isNotEmpty;

    return Column(
      children: [
        // Image preview / upload area
        InkWell(
          onTap: _pickAndUploadImage,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 140,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D2D),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
                width: 1,
              ),
              image: hasImage
                  ? DecorationImage(
                      image: NetworkImage(widget.currentUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: hasImage
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
                              icon: _isRemovingBackground
                                  ? Icons.hourglass_top_rounded
                                  : Icons.auto_fix_high_rounded,
                              tooltip: _isRemovingBackground
                                  ? 'Quitando fondo...'
                                  : 'Quitar fondo',
                              onTap: _isRemovingBackground
                                  ? () {}
                                  : _removeBackground,
                            ),
                            const SizedBox(width: 4),
                            _buildActionButton(
                              icon: Icons.delete,
                              tooltip: 'Eliminar',
                              onTap: () => _emitUrl(''),
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
                          color: const Color(0xFF00A09D).withValues(alpha: 0.1),
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
                        'Haz clic para elegir imagen',
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

class _ColorField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final VoidCallback? onChanged;

  const _ColorField({
    required this.label,
    required this.controller,
    this.onChanged,
  });

  @override
  State<_ColorField> createState() => _ColorFieldState();
}

class _ColorFieldState extends State<_ColorField> {
  String _colorToHex(Color color) {
    return serializeWebsiteEditorColor(color, includeAlpha: true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WebsiteColorPickerField(
          label: widget.label,
          value: widget.controller.text.isEmpty
              ? '#FFFFFF'
              : widget.controller.text,
          allowAlpha: true,
          onChanged: (value) {
            widget.controller.text = value;
            widget.onChanged?.call();
            setState(() {});
          },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _activateEyedropper(context),
            icon: const Icon(Icons.colorize, size: 16),
            label: const Text('Tomar color de la página'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF20C5C1),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _activateEyedropper(BuildContext context) async {
    final provider = context.read<WebsiteEditModeProvider>();
    final boundaryKey = provider.previewRepaintKey;

    if (boundaryKey.currentContext == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'No se pudo acceder al área de vista previa. Asegúrate de estar en modo edición.')),
      );
      return;
    }

    OverlayEntry? entry;
    // Create full screen overlay to capture click
    entry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: MouseRegion(
          cursor: SystemMouseCursors.precise, // Crosshair cursor
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              // Capture position and process
              _processColorPick(details.globalPosition, boundaryKey);
              entry?.remove();
              entry = null;
            },
            child: Container(
              color: Colors.transparent, // Transparent hit shield
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(entry!);

    // Optional: visual feedback that picking started
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Toca cualquier punto de la vista previa para copiar el color'),
        duration: Duration(milliseconds: 1500),
      ),
    );
  }

  Future<void> _processColorPick(Offset globalPosition, GlobalKey key) async {
    try {
      final renderBox =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (renderBox == null) return;

      // Convert global tap position to local coordinates of the boundary
      final localPosition = renderBox.globalToLocal(globalPosition);

      // Capture the image of the boundary
      // pixelRatio 1.0 is enough for color picking and faster
      final image = await renderBox.toImage(pixelRatio: 1.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);

      if (byteData != null) {
        final width = image.width;
        final height = image.height;

        // Ensure coordinates are within bounds
        final x = localPosition.dx.round().clamp(0, width - 1);
        final y = localPosition.dy.round().clamp(0, height - 1);

        // RGBA is 4 bytes per pixel
        final offset = (y * width + x) * 4;

        final r = byteData.getUint8(offset);
        final g = byteData.getUint8(offset + 1);
        final b = byteData.getUint8(offset + 2);
        // We ignore alpha for the picked color effectively, forcing full opacity for the background setting
        // or we could read it: final a = byteData.getUint8(offset + 3);

        final color = Color.fromARGB(255, r, g, b);

        if (mounted) {
          widget.controller.text = _colorToHex(color);
          widget.onChanged?.call();
          setState(() {});

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(children: [
                Container(width: 20, height: 20, color: color),
                const SizedBox(width: 8),
                Text('Color copiado: ${_colorToHex(color)}')
              ]),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Eyedropper error: $e');
    }
  }
}

// ============================================================================
// CATEGORY GRID BLOCK CONTROLS
// ============================================================================
// ignore: unused_element
class _CategoryGridBlockControls extends StatelessWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _CategoryGridBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  void _updateField(String field, dynamic value) {
    provider.updateBlockData(blockId, field, value);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info box explaining auto-sync
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF00A09D).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: const Color(0xFF00A09D).withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome,
                  color: Color(0xFF00A09D), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Las categorías se administran desde Catálogo web > Categorías',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _EditorTextField(
          label: 'Título de sección',
          value: data['title']?.toString() ?? '',
          onChanged: (v) => _updateField('title', v),
        ),
        const SizedBox(height: 12),
        _EditorTextField(
          label: 'Subtítulo',
          value: data['subtitle']?.toString() ?? '',
          onChanged: (v) => _updateField('subtitle', v),
        ),
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
        _ImagePicker(
          currentUrl: widget.data['imageUrl']?.toString() ?? '',
          onChanged: (url) => _updateField('imageUrl', url),
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

        // Upload/file selection is the primary workflow.
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
        const SizedBox(height: 12),
        _CollapsibleSection(
          title: 'YouTube / enlace avanzado',
          icon: Icons.link_rounded,
          initiallyExpanded: hasYoutubeUrl,
          children: [
            _EditorTextField(
              label: 'URL de YouTube',
              value: widget.data['videoUrl']?.toString() ?? '',
              onChanged: (v) {
                _updateField('videoUrl', v);
                if (v.isNotEmpty) {
                  _updateField('videoFileUrl', '');
                }
              },
              hint: 'https://youtube.com/watch?v=...',
            ),
          ],
        ),

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
          WebsiteLinkValueEditor(
            label: 'Link botón',
            value: widget.data['ctaLink']?.toString() ?? '',
            onChanged: (v) => _updateField('ctaLink', v),
            dense: true,
            darkStyle: true,
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
        const _SectionHeader('Imagen de fondo'),
        const SizedBox(height: 8),
        _ImagePicker(
          currentUrl: widget.data['imageUrl']?.toString() ?? '',
          onChanged: (url) => _updateField('imageUrl', url),
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
        WebsiteColorPickerField(
          label: 'Color de acento (línea bajo título)',
          value: (widget.data['accentColor']?.toString().isNotEmpty ?? false)
              ? widget.data['accentColor'].toString()
              : '#E53935',
          allowAlpha: true,
          allowTransparent: true,
          helperText:
              'Elige “Sin color” dentro del selector si no quieres mostrar la línea.',
          onChanged: (v) => _updateField('accentColor', v),
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
  String _headerColorMode = 'auto';
  bool _showTopBanner = false;
  bool _headerShadow = true;
  bool _loaded = false;
  bool _hasLocalChanges = false;

  final _headerStyles = {
    'solid': 'Sólido',
    'transparent': 'Transparente (sobre hero)',
    'sticky': 'Fijo al hacer scroll'
  };
  final _headerColorModes = {
    'auto': 'Automático (recomendado)',
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
    _headerColorMode = service.getSetting('header_color_mode', 'auto');
    final rawBannerValue =
        service.getSetting('header_show_top_banner', 'false');
    _showTopBanner = rawBannerValue == 'true';
    debugPrint(
        '🔧 [HeaderSettings] _loadSettings: rawBannerValue="$rawBannerValue" → _showTopBanner=$_showTopBanner');
    _headerShadow = service.getSetting('header_shadow', 'true') == 'true';
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
            label: 'Contraste del contenido',
            value: _headerColorMode,
            items: _headerColorModes.keys.toList(),
            labels: _headerColorModes,
            onChanged: (v) {
              setState(() => _headerColorMode = v!);
              _markChanged();
            },
          ),
          const SizedBox(height: 8),
          Text(
            _headerColorMode == 'auto'
                ? 'El logo, los enlaces y los íconos se adaptan al fondo. Sobre banners se agrega una protección tonal sutil para que ninguna capa los haga desaparecer.'
                : 'Este modo reemplaza el contraste automático en todo el sitio.',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),

          // Background color
          _ColorField(
            label: 'Color de fondo',
            controller: _headerBgColorController,
            onChanged: () => _markChanged(),
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

          // Navigation records belong to website_navigation, not header settings.
          const _SectionHeader('Navegación'),
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
                const Row(
                  children: [
                    Icon(Icons.menu, color: Colors.white70, size: 17),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'El header y el footer usan el menú central del sitio.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      WebsiteWorkspaceScope.maybeOf(context)?.open(
                        WebsiteWorkspacePanel.navigation,
                      );
                    },
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Administrar navegación'),
                  ),
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

  // Inline editor state (Edit happens inside the panel, not a modal)
  String? _editingFooterNavId;
  final _inlineNavLabelController = TextEditingController();
  final _inlineNavLinkValueController = TextEditingController();
  String? _inlineNavParentId;
  NavLinkType _inlineNavLinkType = NavLinkType.page;
  bool _inlineNavIsVisible = true;
  bool _inlineNavShowOnDesktop = true;
  bool _inlineNavShowOnMobile = true;
  bool _inlineNavOpenInNewTab = false;
  bool _isSavingInlineNav = false;

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
    final editProvider = context.read<WebsiteEditModeProvider>();
    var sections = editProvider.getEffectiveFooterNavigation(
      service.footerNavigation,
    )..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
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
        final editProvider = context.read<WebsiteEditModeProvider>();
        editProvider.createFooterNavDraft(nav);
      },
    );
  }

  Future<void> _addFooterLink({String? parentId}) async {
    await _showFooterNavDialog(
      title: 'Nuevo enlace',
      initialParentId: parentId,
      initialIsSection: false,
      onSave: (nav) async {
        final editProvider = context.read<WebsiteEditModeProvider>();
        editProvider.createFooterNavDraft(nav);
      },
    );
  }

  void _beginInlineFooterNavEdit(WebsiteNavigation nav) {
    setState(() {
      _editingFooterNavId = nav.id;

      // Prefill
      _inlineNavLabelController.text = nav.label;
      _inlineNavLinkValueController.text = nav.linkValue ?? '';
      _inlineNavParentId = nav.parentId;
      _inlineNavLinkType = nav.linkType;
      _inlineNavIsVisible = nav.isVisible;
      _inlineNavShowOnDesktop = nav.showOnDesktop;
      _inlineNavShowOnMobile = nav.showOnMobile;
      _inlineNavOpenInNewTab = nav.openInNewTab;

      // If user clicked edit on a section tab, ensure the section is selected.
      if (nav.parentId == null) {
        _selectedFooterSectionId = nav.id;
      }
    });
  }

  void _cancelInlineFooterNavEdit() {
    setState(() {
      _editingFooterNavId = null;
      _isSavingInlineNav = false;
    });
  }

  bool _isEditingNav(WebsiteNavigation nav) => _editingFooterNavId == nav.id;

  bool _isInlineEditingSection(WebsiteNavigation nav) {
    // A footer "section" is a top-level item (parent_id = null).
    // Historically we store it with link_type='action' and blank link_value.
    return nav.parentId == null;
  }

  Widget _buildInlineFooterNavEditor(
    WebsiteNavigation nav, {
    required List<WebsiteNavigation> footerParents,
  }) {
    final isSection = _isInlineEditingSection(nav);

    final visibleParents = footerParents
        .where((p) => p.id != nav.id)
        .map((p) => (p.id, p.label))
        .toList();

    String linkTypeValue(NavLinkType type) => switch (type) {
          NavLinkType.page => 'page',
          NavLinkType.external => 'external',
          NavLinkType.anchor => 'anchor',
          _ => 'page',
        };

    NavLinkType parseLinkTypeValue(String value) => switch (value) {
          'page' => NavLinkType.page,
          'external' => NavLinkType.external,
          'anchor' => NavLinkType.anchor,
          _ => NavLinkType.page,
        };

    String? validate() {
      if (_inlineNavLabelController.text.trim().isEmpty) {
        return 'El texto es requerido.';
      }
      if (!isSection) {
        if (_inlineNavLinkValueController.text.trim().isEmpty) {
          return 'El destino es requerido.';
        }
      }
      return null;
    }

    final errorText = validate();

    final title = isSection ? 'Editar sección' : 'Editar enlace';

    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: _cancelInlineFooterNavEdit,
                child: const Text(
                  'Cerrar',
                  style: TextStyle(color: Colors.white60),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Texto
          _EditorTextField(
            label: 'Texto',
            value: _inlineNavLabelController.text,
            controller: _inlineNavLabelController,
            onChanged: (_) => setState(() {}),
            hint: isSection
                ? 'Ej: Legal, Ayuda, Empresa'
                : 'Ej: Términos y condiciones',
          ),

          if (!isSection) ...[
            const SizedBox(height: 12),
            _EditorDropdown(
              label: 'Sección (opcional)',
              value: _inlineNavParentId ?? '',
              options: <(String, String)>[
                ('', 'Sin sección'),
                ...visibleParents,
              ],
              onChanged: (v) => setState(() {
                _inlineNavParentId = v.isEmpty ? null : v;
              }),
            ),
            const SizedBox(height: 12),
            _EditorDropdown(
              label: 'Tipo',
              value: linkTypeValue(_inlineNavLinkType),
              options: const <(String, String)>[
                ('page', 'Página'),
                ('external', 'URL externa'),
                ('anchor', 'Ancla (#)'),
              ],
              onChanged: (v) => setState(() {
                _inlineNavLinkType = parseLinkTypeValue(v);
                // Reset new tab toggle when leaving external.
                if (_inlineNavLinkType != NavLinkType.external) {
                  _inlineNavOpenInNewTab = false;
                }
              }),
            ),
            const SizedBox(height: 12),
            WebsiteLinkValueEditor(
              label: 'Destino',
              value: _inlineNavLinkValueController.text,
              dense: true,
              darkStyle: true,
              allowInternal: _inlineNavLinkType == NavLinkType.page,
              allowExternal: _inlineNavLinkType == NavLinkType.external,
              allowAnchor: _inlineNavLinkType == NavLinkType.anchor,
              helpText: switch (_inlineNavLinkType) {
                NavLinkType.page =>
                  'Elige una página o ruta del sitio (recomendado).',
                NavLinkType.external => 'Pega un enlace externo (https://...)',
                NavLinkType.anchor =>
                  'Usa un ancla como #seccion (misma página).',
                _ => null,
              },
              onChanged: (v) {
                _inlineNavLinkValueController.text = v;
                setState(() {});
              },
            ),
            if (_inlineNavLinkType == NavLinkType.external) ...[
              const SizedBox(height: 10),
              _EditorToggle(
                label: 'Abrir en nueva pestaña',
                value: _inlineNavOpenInNewTab,
                onChanged: (v) => setState(() => _inlineNavOpenInNewTab = v),
              ),
            ],
          ] else ...[
            const SizedBox(height: 12),
            Text(
              'Las secciones son títulos (columnas). No tienen destino.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12,
              ),
            ),
          ],

          const SizedBox(height: 12),
          _EditorToggle(
            label: 'Visible',
            value: _inlineNavIsVisible,
            onChanged: (v) => setState(() => _inlineNavIsVisible = v),
          ),
          const SizedBox(height: 8),
          _EditorToggle(
            label: 'Mostrar en escritorio',
            value: _inlineNavShowOnDesktop,
            onChanged: (v) => setState(() => _inlineNavShowOnDesktop = v),
          ),
          const SizedBox(height: 8),
          _EditorToggle(
            label: 'Mostrar en móvil',
            value: _inlineNavShowOnMobile,
            onChanged: (v) => setState(() => _inlineNavShowOnMobile = v),
          ),

          if (errorText != null) ...[
            const SizedBox(height: 10),
            Text(
              errorText,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 12,
              ),
            ),
          ],

          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _isSavingInlineNav ? null : _cancelInlineFooterNavEdit,
                  style: OutlinedButton.styleFrom(
                    side:
                        BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                    foregroundColor: Colors.white70,
                  ),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: (errorText != null || _isSavingInlineNav)
                      ? null
                      : () {
                          final editProvider =
                              context.read<WebsiteEditModeProvider>();
                          setState(() => _isSavingInlineNav = true);

                          final updated = WebsiteNavigation(
                            id: nav.id,
                            tenantId: nav.tenantId,
                            menuLocation: MenuLocation.footer,
                            label: _inlineNavLabelController.text.trim(),
                            linkType: isSection
                                ? NavLinkType.action
                                : _inlineNavLinkType,
                            linkValue: isSection
                                ? ''
                                : _inlineNavLinkValueController.text.trim(),
                            openInNewTab: (!isSection &&
                                    _inlineNavLinkType == NavLinkType.external)
                                ? _inlineNavOpenInNewTab
                                : false,
                            parentId: isSection ? null : _inlineNavParentId,
                            orderIndex: nav.orderIndex,
                            isVisible: _inlineNavIsVisible,
                            showOnDesktop: _inlineNavShowOnDesktop,
                            showOnMobile: _inlineNavShowOnMobile,
                            cssClass: nav.cssClass,
                            highlight: nav.highlight,
                            createdAt: nav.createdAt,
                            updatedAt: DateTime.now(),
                            children: nav.children,
                            linkedPage: nav.linkedPage,
                          );

                          editProvider.updateFooterNavItem(updated);

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Cambio aplicado. Presiona Guardar para publicarlo.',
                                ),
                                backgroundColor: Color(0xFF00A09D),
                              ),
                            );
                            setState(() {
                              _isSavingInlineNav = false;
                              _editingFooterNavId = null;
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00A09D),
                    foregroundColor: Colors.white,
                  ),
                  child: _isSavingInlineNav
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Aplicar'),
                ),
              ),
            ],
          ),
        ],
      ),
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

  List<String> _moveIdInOrder(List<String> ids, String id, int delta) {
    final fromIndex = ids.indexOf(id);
    if (fromIndex < 0) return ids;

    final toIndex = (fromIndex + delta).clamp(0, ids.length - 1);
    if (toIndex == fromIndex) return ids;

    final next = List<String>.from(ids);
    final moved = next.removeAt(fromIndex);
    next.insert(toIndex, moved);
    return next;
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
    required int totalCount,
    required List<String> orderedIds,
    required double width,
  }) {
    final isDropTarget = _hoveringLinkIndex == index && _draggingLinkId != null;
    final isEditing = _isEditingNav(link);

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
                : (isEditing
                    ? const Color(0xFF00A09D).withValues(alpha: 0.10)
                    : const Color(0xFF2D2D2D)),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDropTarget
                  ? Colors.white24
                  : (isEditing ? const Color(0xFF00A09D) : Colors.white10),
              width: isEditing ? 1.5 : 1,
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
                child: const MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Icon(
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
              _buildFooterItemActionsMenu(
                link,
                parent: parentSection,
                itemIndex: index,
                totalCount: totalCount,
                orderedIds: orderedIds,
              ),
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
    required int index,
    required int totalCount,
    required List<String> orderedIds,
  }) {
    final isEditing = _isEditingNav(section);
    final bg = isSelected
        ? const Color(0xFF00A09D).withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.06);

    final effectiveBg = isDropTarget
        ? Colors.white.withValues(alpha: 0.10)
        : (isEditing ? const Color(0xFF00A09D).withValues(alpha: 0.12) : bg);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isEditing ? const Color(0xFF00A09D) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Material(
        color: effectiveBg,
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
                  child: const MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Icon(
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
                _buildFooterItemActionsMenu(
                  section,
                  itemIndex: index,
                  totalCount: totalCount,
                  orderedIds: orderedIds,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooterItemActionsMenu(
    WebsiteNavigation nav, {
    WebsiteNavigation? parent,
    int? itemIndex,
    int? totalCount,
    List<String>? orderedIds,
  }) {
    return PopupMenuButton<String>(
      tooltip: 'Opciones',
      color: const Color(0xFF2D2D2D),
      icon: const Icon(Icons.more_vert, color: Colors.white70, size: 18),
      onSelected: (value) async {
        switch (value) {
          case 'move_prev':
          case 'move_next':
          case 'move_up':
          case 'move_down':
            {
              final ids = orderedIds;
              final index = itemIndex;
              final total = totalCount;

              if (ids == null || index == null || total == null) return;

              // Determine movement direction.
              final delta = switch (value) {
                'move_prev' || 'move_up' => -1,
                'move_next' || 'move_down' => 1,
                _ => 0,
              };
              if (delta == 0) return;

              final nextOrder = _moveIdInOrder(ids, nav.id, delta);
              if (nextOrder.length != ids.length) return;

              if (parent == null) {
                _persistFooterSectionOrder(nextOrder);
              } else {
                _persistFooterLinkOrder(parent.id, nextOrder);
              }
              return;
            }
          case 'add_link':
            await _addFooterLink(parentId: nav.id);
            return;
          case 'toggle_visible':
            await _toggleFooterNavVisibility(nav);
            return;
          case 'edit':
            _beginInlineFooterNavEdit(nav);
            return;
          case 'delete':
            await _deleteFooterNav(nav);
            return;
        }
      },
      itemBuilder: (context) {
        final isSection = nav.parentId == null;
        final canReorder = itemIndex != null && totalCount != null;
        final idx = itemIndex ?? -1;
        final total = totalCount ?? 0;
        final canMovePrev = canReorder && idx > 0;
        final canMoveNext = canReorder && idx >= 0 && idx < (total - 1);

        return <PopupMenuEntry<String>>[
          if (canReorder && (canMovePrev || canMoveNext)) ...[
            if (canMovePrev)
              PopupMenuItem(
                value: isSection ? 'move_prev' : 'move_up',
                child: Text(
                  isSection ? 'Mover a la izquierda' : 'Mover arriba',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            if (canMoveNext)
              PopupMenuItem(
                value: isSection ? 'move_next' : 'move_down',
                child: Text(
                  isSection ? 'Mover a la derecha' : 'Mover abajo',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            const PopupMenuDivider(),
          ],
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
    final editProvider = context.read<WebsiteEditModeProvider>();
    final effective = editProvider.getEffectiveFooterNavItem(nav);
    editProvider.updateFooterNavItem(
      effective.copyWith(isVisible: !effective.isVisible),
    );
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
    if (!mounted) return;

    final editProvider = context.read<WebsiteEditModeProvider>();
    editProvider.deleteFooterNavItem(nav);
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
    final editProvider = context.read<WebsiteEditModeProvider>();
    final footerParents = editProvider.getEffectiveFooterNavigation(
      service.footerNavigation,
    );

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final effectiveIsSection = isSection;

            String linkTypeValue(NavLinkType type) => switch (type) {
                  NavLinkType.page => 'page',
                  NavLinkType.external => 'external',
                  NavLinkType.anchor => 'anchor',
                  _ => 'page',
                };

            NavLinkType parseLinkTypeValue(String value) => switch (value) {
                  'page' => NavLinkType.page,
                  'external' => NavLinkType.external,
                  'anchor' => NavLinkType.anchor,
                  _ => NavLinkType.page,
                };

            return AlertDialog(
              backgroundColor: const Color(0xFF2D2D2D),
              title: Text(title, style: const TextStyle(color: Colors.white)),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Texto
                        FormField<String>(
                          initialValue: labelController.text,
                          validator: (v) {
                            final value = (v ?? '').trim();
                            if (value.isEmpty) return 'Requerido';
                            return null;
                          },
                          builder: (state) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _EditorTextField(
                                  label: 'Texto',
                                  value: labelController.text,
                                  controller: labelController,
                                  onChanged: (v) {
                                    state.didChange(v);
                                    setState(() {});
                                  },
                                  hint: effectiveIsSection
                                      ? 'Ej: Legal, Ayuda, Empresa'
                                      : 'Ej: Términos y condiciones',
                                ),
                                if (state.hasError) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    state.errorText ?? '',
                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 12),

                        // Sección (opcional)
                        _EditorDropdown(
                          label: 'Sección (opcional)',
                          value: parentId ?? '',
                          options: <(String, String)>[
                            ('', 'Sin sección'),
                            ...footerParents.map((p) => (p.id, p.label)),
                          ],
                          onChanged: (v) => setState(() {
                            parentId = v.isEmpty ? null : v;
                          }),
                        ),
                        const SizedBox(height: 14),

                        // Es sección (título)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Es sección (título)',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Una sección es un encabezado con enlaces dentro.',
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Switch(
                                value: isSection,
                                onChanged: (v) => setState(() {
                                  isSection = v;
                                  if (isSection) {
                                    linkType = NavLinkType.action;
                                    linkValueController.text = '';
                                  }
                                }),
                                activeThumbColor: Colors.white,
                                activeTrackColor: const Color(0xFF00A09D),
                                inactiveThumbColor: Colors.grey.shade400,
                                inactiveTrackColor: Colors.grey.shade700,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ],
                          ),
                        ),

                        if (!effectiveIsSection) ...[
                          const SizedBox(height: 12),

                          // Tipo
                          _EditorDropdown(
                            label: 'Tipo',
                            value: linkTypeValue(linkType),
                            options: const <(String, String)>[
                              ('page', 'Página'),
                              ('external', 'URL externa'),
                              ('anchor', 'Ancla (#)'),
                            ],
                            onChanged: (v) => setState(() {
                              linkType = parseLinkTypeValue(v);
                            }),
                          ),
                          const SizedBox(height: 12),

                          // Destino
                          FormField<String>(
                            initialValue: linkValueController.text,
                            validator: (v) {
                              final value = (v ?? '').trim();
                              if (value.isEmpty) return 'Requerido';
                              return null;
                            },
                            builder: (state) {
                              final help = switch (linkType) {
                                NavLinkType.page =>
                                  'Elige una página o ruta del sitio (recomendado).',
                                NavLinkType.external =>
                                  'Pega un enlace externo (https://...)',
                                NavLinkType.anchor =>
                                  'Usa un ancla como #seccion (misma página).',
                                _ => null,
                              };

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  WebsiteLinkValueEditor(
                                    label: 'Destino',
                                    value: linkValueController.text,
                                    helpText: help,
                                    dense: true,
                                    darkStyle: true,
                                    allowInternal: linkType == NavLinkType.page,
                                    allowExternal:
                                        linkType == NavLinkType.external,
                                    allowAnchor: linkType == NavLinkType.anchor,
                                    onChanged: (v) {
                                      linkValueController.text = v;
                                      state.didChange(v);
                                      setState(() {});
                                    },
                                  ),
                                  if (state.hasError) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      state.errorText ?? '',
                                      style: const TextStyle(
                                        color: Colors.redAccent,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                          if (linkType == NavLinkType.external) ...[
                            const SizedBox(height: 10),
                            _EditorToggle(
                              label: 'Abrir en nueva pestaña',
                              value: openInNewTab,
                              onChanged: (v) =>
                                  setState(() => openInNewTab = v),
                            ),
                          ],
                        ],

                        const SizedBox(height: 12),
                        _EditorToggle(
                          label: 'Visible',
                          value: isVisible,
                          onChanged: (v) => setState(() => isVisible = v),
                        ),
                        const SizedBox(height: 8),
                        _EditorToggle(
                          label: 'Mostrar en escritorio',
                          value: showOnDesktop,
                          onChanged: (v) => setState(() => showOnDesktop = v),
                        ),
                        const SizedBox(height: 8),
                        _EditorToggle(
                          label: 'Mostrar en móvil',
                          value: showOnMobile,
                          onChanged: (v) => setState(() => showOnMobile = v),
                        ),
                      ],
                    ),
                  ),
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
                  child: Text(existing != null ? 'Aplicar' : 'Agregar'),
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
    _inlineNavLabelController.dispose();
    _inlineNavLinkValueController.dispose();
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
                  label: 'WhatsApp',
                  value: _whatsappController.text,
                  controller: _whatsappController,
                  onChanged: (_) {},
                  hint: '+56912345678',
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

                                  final orderedSectionIds =
                                      sections.map((s) => s.id).toList();

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
                                            index: index,
                                            totalCount: sections.length,
                                            orderedIds: orderedSectionIds,
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
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(6),
                                      onTap: () => _beginInlineFooterNavEdit(
                                          selectedSection),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 6, horizontal: 6),
                                        child: Text(
                                          selectedSection.label,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
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

                          // Inline editor for the selected section (when editing a section)
                          if (_isEditingNav(selectedSection))
                            _buildInlineFooterNavEditor(
                              selectedSection,
                              footerParents: sections,
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
                            ConstraintLayoutBuilder(
                              builder: (context, constraints) {
                                final listWidth = constraints.maxWidth;
                                return Column(
                                  children:
                                      List.generate(links.length, (index) {
                                    final link = links[index];
                                    final orderedLinkIds =
                                        links.map((l) => l.id).toList();
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _buildFooterLinkRow(
                                          link,
                                          index: index,
                                          parentSection: selectedSection,
                                          totalCount: links.length,
                                          orderedIds: orderedLinkIds,
                                          width: listWidth,
                                        ),
                                        if (_isEditingNav(link))
                                          _buildInlineFooterNavEditor(
                                            link,
                                            footerParents: sections,
                                          ),
                                      ],
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
  final Future<void> Function()? onRestoreComplete;

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
      final restored = await _backupService.restoreBackup(backup.id);
      if (!restored) {
        throw Exception('La copia de seguridad no pudo restaurarse');
      }

      if (mounted) {
        await widget.onRestoreComplete?.call();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copia de seguridad restaurada'),
            backgroundColor: Colors.green,
          ),
        );
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
                    maxLines: 2,
                    style: const TextStyle(color: Colors.white),
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
  final bool collapsible;

  const _BlockStyleControls({
    required this.blockId,
    required this.provider,
    required this.blockData,
    this.collapsible = true,
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
    final controls = <Widget>[
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
    ];

    if (!widget.collapsible) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: controls,
      );
    }

    return _CollapsibleSection(
      title: 'Diseño y estilo',
      icon: Icons.brush_outlined,
      initiallyExpanded: false,
      children: controls,
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
  Widget build(BuildContext context) => WebsiteColorPickerField(
        label: 'Color del borde',
        value: currentColor,
        allowAlpha: true,
        onChanged: onChanged,
      );
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
  Widget build(BuildContext context) => WebsiteColorPickerField(
        label: 'Color',
        value: (currentValue == null || currentValue!.isEmpty)
            ? '#00000000'
            : currentValue!,
        allowAlpha: true,
        allowTransparent: true,
        onChanged: (value) {
          final color = parseWebsiteEditorColor(value);
          onChanged(
            websiteEditorColorOpacity(color) == 0 ? null : value,
          );
        },
      );
}
