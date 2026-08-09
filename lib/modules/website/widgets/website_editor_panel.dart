import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/safe_layout_builder.dart';
import '../../../shared/widgets/vb_sub_tabs.dart';
import '../../../shared/widgets/vb_notice.dart';
import '../../../shared/widgets/vb_segmented.dart';
import '../../../shared/widgets/vb_status_badge.dart';
import '../models/website_block_catalog.dart';
import '../models/website_block_definition.dart';
import '../models/website_block_surface_style.dart';
import '../models/website_responsive_authoring.dart';
import '../models/website_block_capabilities.dart';
import '../models/website_block_geometry.dart';
import '../models/website_block_public_visibility.dart';
import '../models/website_block_registry.dart';
import '../models/website_block_type.dart';
import '../models/website_canvas_alignment.dart';
import '../models/website_canvas_responsive_document.dart';
import '../models/website_responsive_field_state.dart';
import '../models/website_page_composition.dart';
import '../models/website_editor_capability.dart';
import '../models/website_font_registry.dart';
import '../models/website_action.dart';
import '../models/website_editor_drag_payload.dart';
import '../providers/website_edit_mode_provider.dart';
import '../models/website_page_models.dart';
import '../services/website_backup_service.dart';
import '../services/website_background_removal_service.dart';
import '../services/website_media_service.dart';
import '../services/website_service.dart';
import '../theme/website_resolved_theme.dart';
import 'block_resize_handle.dart';
import '../services/google_business_service.dart';
import 'focal_point_picker.dart';
import 'responsive_field_shell.dart';
import 'responsive_media_field.dart';
import 'website_canvas_field_binding.dart';
import 'website_responsive_media_binding.dart';
import 'website_responsive_scalar_binding.dart';
import 'text_formatting_toolbar.dart';
import 'website_link_value_editor.dart';
import 'website_action_editor.dart';
import 'website_background_removal_dialog.dart';
import 'website_color_picker.dart';
import 'website_block_edit_section.dart';
import 'website_editor_chrome_geometry.dart';
import 'website_editor_control_density.dart';
import 'website_editor_host_theme.dart';
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
part 'editor_panel/header_footer_controls.dart';
part 'editor_panel/backups_dialog.dart';
part 'editor_panel/style_controls.dart';

/// Professional side panel editor for website blocks
/// Clean, functional, and elegant interface
class WebsiteEditorPanel extends StatefulWidget {
  final Future<void> Function()? onSave;
  final Future<void> Function()? onRestoreComplete;
  final VoidCallback? onDiscard;
  final WebsiteBackupService? backupService;

  const WebsiteEditorPanel({
    super.key,
    this.onSave,
    this.onRestoreComplete,
    this.onDiscard,
    this.backupService,
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
  WebsiteEditModeProvider? _hostProviderIdentity;
  final ValueNotifier<int> _hostProviderRevision = ValueNotifier<int>(0);

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
    _hostProviderRevision.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editProvider = context.watch<WebsiteEditModeProvider>();
    if (!identical(_hostProviderIdentity, editProvider)) {
      _hostProviderIdentity = editProvider;
      _hostProviderRevision.value++;
    }

    // Check selection changes after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkSelection(editProvider);
    });

    if (!editProvider.isEditMode) {
      return const SizedBox.shrink();
    }

    final inspectorTheme = WebsiteEditorInspectorTheme.resolveFrom(context);
    final selectedBlockId = editProvider.selectedBlockId;
    final effectiveViewport = (selectedBlockId == null
            ? null
            : editProvider.renderedBlockViewportFor(selectedBlockId)) ??
        WebsiteEditorChromeScope.maybeOf(context)?.canvasViewport ??
        editProvider.previewViewport;
    return WebsiteEditorAuthoringViewportScope(
      requestedViewport: editProvider.previewViewport,
      effectiveViewport: effectiveViewport,
      child: Theme(
        data: inspectorTheme,
        child: Builder(
          builder: (inspectorContext) =>
              WebsiteEditorControlDensityScope.resolved(
            context: inspectorContext,
            child: _buildInspectorFrame(
              inspectorContext,
              editProvider,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInspectorFrame(
    BuildContext context,
    WebsiteEditModeProvider editProvider,
  ) {
    final theme = Theme.of(context);
    return Container(
      // The pane width has one owner. Inside the shell this Container already
      // receives the slot width, so the constraint is a floor for hosts that
      // mount the panel standalone — never a second, independent decision.
      width: WebsiteEditorChromeScope.maybeOf(context)?.paneWidth ??
          WebsiteEditorChromeGeometry.inspectorWidth,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          left: BorderSide(
            color: theme.dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          _buildHeader(context, editProvider),
          _buildTabBar(),
          Expanded(
            child: _buildTabContent(editProvider),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    WebsiteEditModeProvider editProvider,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
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
    final backupService = widget.backupService ?? WebsiteBackupService();
    showDialog(
      context: context,
      builder: (dialogContext) => _BackupsDialog(
        backupService: backupService,
        ownsBackupService: widget.backupService == null,
        hostProviderRevision: _hostProviderRevision,
        liveProvider: () {
          if (!mounted) return null;
          try {
            return this.context.read<WebsiteEditModeProvider>();
          } catch (_) {
            return null;
          }
        },
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

  /// The pane's destinations. `O-01` caps a menu at seven and there are five,
  /// so the overflow drawer can always hold whatever does not fit inline.
  static const List<VbSubTab<String>> _inspectorTabs = <VbSubTab<String>>[
    VbSubTab<String>(value: 'add', label: 'Agregar'),
    VbSubTab<String>(value: 'edit', label: 'Editar'),
    VbSubTab<String>(value: 'page', label: 'Página'),
    VbSubTab<String>(value: 'theme', label: 'Tema'),
    VbSubTab<String>(value: 'sync', label: 'Google'),
  ];

  Widget _buildTabBar() {
    // `T-04` through its canonical owner. Five tabs in five `Expanded`s with an
    // icon each is what overflowed the published 420 pane on every host, in
    // light and in dark. See `InspectorTabBar`.
    return VbSubTabs<String>(
      tabs: _inspectorTabs,
      value: _activeTab,
      onChanged: (id) => setState(() => _activeTab = id),
      overflowTooltip: 'Más secciones del inspector',
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
        return _ThemeTab(provider: editProvider);
      case 'sync':
        return const _SyncTab();
      default:
        return const SizedBox.shrink();
    }
  }
}

// The media/focal binding lives in `website_responsive_media_binding.dart`.
// A 300-line private helper inside this library could not be tested on its
// own, and the binding contracts are exactly what needs regression coverage.

/// The selected block's editing controls, on their own, for a host that is not
/// the desktop pane.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` t10 frames 10f and 10h — the phone
/// sheet shows the properties of the selected block and nothing else.
///
/// It is the SAME `_EditBlockTab` the pane mounts, with three things removed
/// because the contextual host already owns them or must never have them:
///
/// * the pane's identity row — the dock and the sheet header name the block;
/// * the pane's section capsule — the sheet renders `T-04` sub-tabs itself and
///   drives [section] from outside;
/// * the whole panel frame — header, undo/redo, backups, Página/Tema/Google
///   and, decisively, the panel's own `Guardar`. Save has one owner
///   (`WebsiteEditorCommandScope`); a sheet that grew a second one is exactly
///   the defect the command scope exists to prevent.
///
/// It writes through the same provider commands as the pane, so a property
/// edited from the phone and the same property edited from the desktop
/// inspector are one operation with one history step.
class WebsiteBlockEditSurface extends StatelessWidget {
  const WebsiteBlockEditSurface({
    super.key,
    required this.editProvider,
    required this.section,
  });

  final WebsiteEditModeProvider editProvider;
  final WebsiteBlockEditSection section;

  @override
  Widget build(BuildContext context) {
    return WebsiteEditorControlDensityScope.resolved(
      context: context,
      child: _EditBlockTab(
        editProvider: editProvider,
        showBlockHeader: false,
        showSectionNavigation: false,
        section: switch (section) {
          WebsiteBlockEditSection.content => _InspectorSection.content,
          WebsiteBlockEditSection.layout => _InspectorSection.layout,
          WebsiteBlockEditSection.style => _InspectorSection.style,
        },
      ),
    );
  }
}
