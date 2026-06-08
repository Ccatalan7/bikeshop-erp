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

    // Preload editor-only deferred code so returning to Home in edit mode
    // doesn't pay the deferred-load cost (which feels like a slowdown).
    if (isEditMode) {
      DeferredEditableBlockRenderer.preload();
    }

    // IMPORTANT: Always use Stack layout to keep widget tree structure stable.
    // Previously, switching from `child` to `Stack(children: [child, panel])`
    // would reparent the child, causing GlobalKey conflicts and framework
    // assertions like "_elements.contains(element) is not true".
    // Use Transform.translate to force a new stacking context on the entire
    // editor shell. This helps isolate the editor UI from the page content's
    // z-index fighting, ensuring the editor (bottom of Stack) always wins.
    return Transform.translate(
      offset: Offset.zero,
      child: Stack(
        children: [
          // Keep router child full-width so the top command bar uses all space.
          // Wrap with RepaintBoundary to allow Eyedropper to read pixels
          Positioned.fill(
            child: child,
          ),
          // Persistent editor panel (fixed width on the right)
          // Only rendered when in edit mode, but Stack structure is always present
          if (isEditMode)
            Positioned(
              top: _editorTopBarHeight,
              right: 0,
              bottom: 0,
              width: _editorPanelWidth,
              child: _PersistentEditorPanel(editProvider: editProvider),
            ),
        ],
      ),
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
      onRestoreComplete: _handleRestoreComplete,
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
        pendingSiteSettings: editProvider.pendingSiteSettings,
        pendingHeaderSettings: editProvider.pendingHeaderSettings,
        pendingFooterSettings: editProvider.pendingFooterSettings,
        pendingThemeSettings: editProvider.pendingThemeSettings,
        pendingFooterNavLabels: editProvider.pendingFooterNavLabels,
        pendingFooterNavLinkTypes: editProvider.pendingFooterNavLinkTypes,
        pendingFooterNavLinkValues: editProvider.pendingFooterNavLinkValues,
        pendingFooterNavOpenInNewTab: editProvider.pendingFooterNavOpenInNewTab,
        pendingFooterNavItems: editProvider.pendingFooterNavItems,
        pendingFooterNavCreates: editProvider.pendingFooterNavCreates,
        pendingFooterNavDeletes: editProvider.pendingFooterNavDeletes,
        pendingPageSeo: editProvider.pendingPageSeo,
        pendingFooterSectionOrder: editProvider.pendingFooterSectionOrder,
        pendingFooterLinkOrder: editProvider.pendingFooterLinkOrder,
        pendingCategoryVisibility: editProvider.pendingCategoryVisibility,
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
      editProvider.clearSiteSettingsChanges();
      editProvider.clearHeaderChanged();
      editProvider.clearFooterChanges();
      editProvider.clearThemeChanges();
      editProvider.clearSeoChanges();
      editProvider.clearCategoryChanges();

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
    widget.editProvider.discardPendingChanges();
    widget.editProvider.switchToPreviewMode();
  }

  Future<void> _handleRestoreComplete() async {
    final websiteService = context.read<WebsiteService>();
    final tenantId = await _resolveTenantId();
    if (tenantId == null) {
      throw Exception('No se pudo identificar el tenant');
    }

    final editProvider = widget.editProvider;
    await websiteService.loadPublicStoreDataUnified(
      tenantId,
      forceRefresh: true,
    );

    final pageId = editProvider.currentPageId;
    final freshBlocks = pageId == null
        ? websiteService.blocks
        : await websiteService.loadBlocksForPage(pageId, tenantId: tenantId);

    editProvider.enterEditMode(
      freshBlocks,
      websiteService.settings,
      pageId: pageId,
      pageSlug: editProvider.currentPageSlug,
    );
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
