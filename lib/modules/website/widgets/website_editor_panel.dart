import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/widgets/safe_layout_builder.dart';
import '../models/website_block_definition.dart';
import '../models/website_block_capabilities.dart';
import '../models/website_block_geometry.dart';
import '../models/website_block_registry.dart';
import '../models/website_block_type.dart';
import '../models/website_page_composition.dart';
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

part 'editor_panel/add_blocks_tab.dart';
part 'editor_panel/sync_tab.dart';
part 'editor_panel/edit_block_tab.dart';
part 'editor_panel/carousel_controls.dart';
part 'editor_panel/products_controls.dart';
part 'editor_panel/schema_controls.dart';
part 'editor_panel/canvas_controls.dart';
part 'editor_panel/page_settings_tab.dart';
part 'editor_panel/theme_tab.dart';
part 'editor_panel/shared_field_widgets.dart';
part 'editor_panel/collection_block_controls.dart';
part 'editor_panel/header_footer_controls.dart';
part 'editor_panel/backups_dialog.dart';
part 'editor_panel/style_controls.dart';

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