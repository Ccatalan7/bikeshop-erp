import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../modules/website/providers/website_edit_mode_provider.dart';
import '../../modules/website/widgets/deferred_editable_block_renderer.dart';
import '../../modules/website/widgets/deferred_website_editor_panel.dart';
import '../../modules/website/services/website_service.dart';
import '../../shared/services/tenant_service.dart';

/// A persistent shell that keeps the editor panel mounted across route changes.
///
/// This widget wraps the router content and overlays the editor panel when in
/// edit mode. The key insight is that the editor panel is rendered OUTSIDE
/// the router, so it won't be rebuilt when pages change.
class PersistentEditorShell extends StatelessWidget {
  final Widget child;

  static const double _editorPanelWidth = 380;
  static const double _editorTopBarHeight = 48;

  const PersistentEditorShell({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // Watch edit mode to show/hide the editor panel
    final editProvider = context.watch<WebsiteEditModeProvider>();
    final isEditMode = editProvider.isEditMode;

    // If not in edit mode, just return the child (router content)
    if (!isEditMode) {
      return child;
    }

    // Preload editor-only deferred code so returning to Home in edit mode
    // doesn't pay the deferred-load cost (which feels like a slowdown).
    DeferredEditableBlockRenderer.preload();

    // In edit mode, OVERLAY the editor panel instead of shrinking the widget.
    // This keeps the panel persistent across navigations.
    return Stack(
      children: [
        // Keep router child full-width so the top command bar uses all space.
        Positioned.fill(child: child),
        // Persistent editor panel (fixed width on the right)
        Positioned(
          top: _editorTopBarHeight,
          right: 0,
          bottom: 0,
          width: _editorPanelWidth,
          child: _PersistentEditorPanel(editProvider: editProvider),
        ),
      ],
    );
  }
}

/// The editor panel widget, designed to be persistent across page navigations.
class _PersistentEditorPanel extends StatefulWidget {
  final WebsiteEditModeProvider editProvider;

  const _PersistentEditorPanel({required this.editProvider});

  @override
  State<_PersistentEditorPanel> createState() => _PersistentEditorPanelState();
}

class _PersistentEditorPanelState extends State<_PersistentEditorPanel> {
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    return DeferredWebsiteEditorPanel(
      onSave: _handleSave,
      onDiscard: _handleDiscard,
    );
  }

  Future<void> _handleSave() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      final editProvider = widget.editProvider;
      final websiteService = context.read<WebsiteService>();

      // Resolve tenant ID
      final tenantId = await _resolveTenantId();
      if (tenantId == null) {
        _showError('No se pudo identificar el tenant');
        return;
      }

      _showMessage('Guardando cambios...');

      final result = await websiteService.saveEditorChanges(
        tenantId: tenantId,
        editorBlocks: editProvider.blocks,
        pendingHeaderSettings: editProvider.pendingHeaderSettings,
        pendingFooterSettings: editProvider.pendingFooterSettings,
        pendingThemeSettings: editProvider.pendingThemeSettings,
        pendingFooterSectionOrder: editProvider.pendingFooterSectionOrder,
        pendingFooterLinkOrder: editProvider.pendingFooterLinkOrder,
        pageId: editProvider.currentPageId,
        pageSlug: editProvider.currentPageSlug,
      );

      if (result.pageId != null || (result.pageSlug?.isNotEmpty ?? false)) {
        editProvider.updateCurrentPageContext(
          pageId: result.pageId,
          pageSlug: result.pageSlug,
        );
      }

      editProvider.updateBlocksAfterSave(result.freshBlocks);
      editProvider.markAsSaved();
      editProvider.clearHeaderChanged();
      editProvider.clearFooterChanges();
      editProvider.clearThemeChanges();

      _showSuccess('✅ Cambios guardados');

      // Switch to preview mode
      if (mounted) {
        editProvider.switchToPreviewMode();
      }
    } catch (e) {
      _showError('Error al guardar: $e');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _handleDiscard() {
    widget.editProvider.switchToPreviewMode();
  }

  Future<String?> _resolveTenantId() async {
    // Try TenantService first (authenticated users)
    final tenantService = TenantService();
    return await tenantService.getTenantId();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
}
