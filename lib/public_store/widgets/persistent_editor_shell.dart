import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../modules/website/providers/website_edit_mode_provider.dart';
import '../../modules/website/widgets/deferred_editable_block_renderer.dart';
import '../../modules/website/widgets/deferred_website_editor_panel.dart';
import '../../modules/website/models/website_editor_capability.dart';
import '../../modules/website/services/website_save_coordinator.dart';
import '../../modules/website/services/website_service.dart';
import '../../shared/services/tenant_service.dart';
import '../../shared/widgets/workspace_shell_scope.dart';

/// A persistent shell that keeps the editor panel mounted across route changes.
///
/// This widget wraps the router content and overlays the editor panel when in
/// edit mode. The key insight is that the editor panel is rendered OUTSIDE
/// the router, so it won't be rebuilt when pages change.
class PersistentEditorShell extends StatelessWidget {
  /// Reopens the restored document through the authority-bound editor RPC,
  /// bound to the FULL owner captured BEFORE the first await: exact lease
  /// (fingerprint + authorityEpoch + tenant), provider generation and
  /// identity revision, document session revision + pageId/pageSlug, and
  /// the service identityEpoch + request identity. The context is
  /// re-validated after resolving the tenant, after the public refresh,
  /// after the RPC and immediately before openEditorDocument; ANY mismatch
  /// throws [WebsiteEditorReadSupersededException] without reopening and
  /// without touching the new session. The editor is never reopened from an
  /// empty public fallback or a stale grant.
  @visibleForTesting
  static Future<void> restoreEditorDocumentAfterBackup({
    required WebsiteEditModeProvider editProvider,
    required WebsiteService websiteService,
    required Future<String?> Function() resolveTenantId,
  }) async {
    final lease = editProvider.editorEntryLease;
    if (lease == null || !lease.granted) {
      throw const WebsiteEditorAuthorityException(
        'La restauración requiere una sesión de editor autorizada.',
      );
    }
    final leaseFingerprint = lease.fingerprint;
    final leaseEpoch = lease.authorityEpoch;
    final leaseTenant = lease.storefrontTenantId;
    final generation = editProvider.editorEntryLeaseGeneration;
    final identityRevision = editProvider.editorEntryLeaseIdentityRevision;
    final capturedDocument = editProvider.document;
    final documentRevision = capturedDocument.sessionRevision;
    final pageId = capturedDocument.pageId;
    final pageSlug = capturedDocument.pageSlug;
    final serviceEpoch = websiteService.identityEpoch;
    final requestIdentity = websiteService.editorCapabilityRequestIdentity;

    void requireStable() {
      final currentLease = editProvider.editorEntryLease;
      final currentDocument = editProvider.document;
      if (currentLease == null ||
          !currentLease.granted ||
          currentLease.fingerprint != leaseFingerprint ||
          currentLease.authorityEpoch != leaseEpoch ||
          generation != editProvider.editorEntryLeaseGeneration ||
          identityRevision !=
              editProvider.editorEntryLeaseIdentityRevision ||
          currentDocument.sessionRevision != documentRevision ||
          currentDocument.pageId != pageId ||
          currentDocument.pageSlug != pageSlug ||
          serviceEpoch != websiteService.identityEpoch ||
          requestIdentity !=
              websiteService.editorCapabilityRequestIdentity) {
        throw const WebsiteEditorReadSupersededException(
          'La restauración pertenece a una sesión anterior.',
        );
      }
    }

    final tenantId = await resolveTenantId();
    if (tenantId == null || tenantId.isEmpty) {
      throw Exception('No se pudo identificar el tenant');
    }
    if (tenantId != leaseTenant) {
      throw const WebsiteEditorReadSupersededException(
        'La restauración pertenece a una sesión anterior.',
      );
    }
    requireStable();

    await websiteService.loadPublicStoreDataUnified(
      tenantId,
      forceRefresh: true,
    );
    requireStable();

    final snapshot = await websiteService.loadEditorPageWithBlocks(
      pageSlug ?? '',
      tenantId: tenantId,
    );
    requireStable();
    if (snapshot == null) {
      throw StateError('La página restaurada no existe en el editor.');
    }
    if (pageId == null) {
      // HOME semantics: only the canonical home row may reopen the home
      // document.
      if (!snapshot.page.isHome) {
        throw StateError(
          'La página restaurada no corresponde al documento Home.',
        );
      }
    } else if (snapshot.page.id != pageId) {
      throw StateError(
        'La página restaurada no coincide con el documento abierto.',
      );
    }

    requireStable();
    editProvider.openEditorDocument(
      snapshot.blocks.toList(growable: false),
      websiteService.settings,
      mode: WebsiteEditorMode.edit,
      pageId: pageId,
      // Canonical slug from the authoritative snapshot (null keeps the
      // HOME identity).
      pageSlug: pageId == null ? null : snapshot.page.slug,
    );
  }

  final Widget child;
  final WebsiteSaveCoordinator? saveCoordinator;
  final Future<String?> Function()? tenantIdResolver;

  static const double _editorPanelWidth = 380;
  static const double _editorTopBarHeight = 48;

  const PersistentEditorShell({
    super.key,
    required this.child,
    @visibleForTesting this.saveCoordinator,
    @visibleForTesting this.tenantIdResolver,
  });

  @override
  Widget build(BuildContext context) {
    // Watch edit mode to show/hide the editor panel
    final editProvider = context.watch<WebsiteEditModeProvider>();
    final isEditMode = editProvider.isEditMode;
    final showEditorPanel = isEditMode && editProvider.isPageEditorWorkspace;
    final workspaceTopInset = WorkspaceShellScope.topInsetOf(context);

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
    return Padding(
      padding: EdgeInsets.only(top: workspaceTopInset),
      child: Transform.translate(
        key: const ValueKey('persistent-editor-workspace-content'),
        offset: Offset.zero,
        child: Stack(
          children: [
            // Keep router child full-width so the top command bar uses all
            // space. The whole editor starts below global workspace chrome;
            // otherwise the two command systems overlap by exactly the
            // workspace-bar height.
            Positioned.fill(
              child: child,
            ),
            // Persistent editor panel (fixed width on the right)
            // Only rendered when in edit mode, but Stack structure is always
            // present.
            if (showEditorPanel)
              Positioned(
                top: _editorTopBarHeight,
                right: 0,
                bottom: 0,
                width: _editorPanelWidth,
                child: _PersistentEditorPanel(
                  editProvider: editProvider,
                  saveCoordinator: saveCoordinator,
                  tenantIdResolver: tenantIdResolver,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The editor panel widget, designed to be persistent across page navigations.
class _PersistentEditorPanel extends StatefulWidget {
  final WebsiteEditModeProvider editProvider;
  final WebsiteSaveCoordinator? saveCoordinator;
  final Future<String?> Function()? tenantIdResolver;

  const _PersistentEditorPanel({
    required this.editProvider,
    required this.saveCoordinator,
    required this.tenantIdResolver,
  });

  @override
  State<_PersistentEditorPanel> createState() => _PersistentEditorPanelState();
}

class _PersistentEditorPanelState extends State<_PersistentEditorPanel> {
  bool _isSaving = false;
  WebsiteService? _saveCoordinatorOwner;
  WebsiteSaveCoordinator? _saveCoordinator;

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
      var coordinator = widget.saveCoordinator;
      if (coordinator == null) {
        final websiteService = context.read<WebsiteService>();
        if (!identical(_saveCoordinatorOwner, websiteService)) {
          _saveCoordinatorOwner = websiteService;
          _saveCoordinator = WebsiteSaveCoordinator.forService(websiteService);
        }
        coordinator = _saveCoordinator!;
      }

      // Resolve tenant ID
      final tenantId = await _resolveTenantId();
      if (tenantId == null) {
        _showError('No se pudo identificar el tenant');
        return;
      }

      _showMessage('Guardando cambios...');

      final result = await coordinator.save(
        tenantId: tenantId,
        document: editProvider,
      );

      if (result.appliedToActiveDocument) {
        if (editProvider.hasUnsavedChanges) {
          // The save is confirmed, but NEW edits arrived while it ran:
          // never a misleading total success.
          _showMessage(
            '✅ Cambios guardados; hay ediciones nuevas sin guardar.',
          );
        } else {
          _showSuccess('✅ Cambios guardados');
        }
      } else {
        // The session/authority moved while saving: the writes that DID
        // complete are durable, but this editor no longer owns them —
        // never a misleading success.
        _showMessage(
          'La sesión cambió durante el guardado; revisa el estado actual '
          'antes de continuar.',
        );
      }

      // Switch to preview mode
      if (mounted &&
          result.appliedToActiveDocument &&
          !editProvider.hasUnsavedChanges) {
        editProvider.setMode(WebsiteEditorMode.preview);
      }
    } on WebsiteEditorWriteSupersededException {
      // Typed obsolete outcome: the new session is untouched; nothing to
      // celebrate and nothing to alarm about.
      _showMessage('El guardado quedó obsoleto por un cambio de sesión.');
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
    widget.editProvider.setMode(WebsiteEditorMode.preview);
  }

  Future<void> _handleRestoreComplete() {
    return PersistentEditorShell.restoreEditorDocumentAfterBackup(
      editProvider: widget.editProvider,
      websiteService: context.read<WebsiteService>(),
      resolveTenantId: _resolveTenantId,
    );
  }

  Future<String?> _resolveTenantId() async {
    final tenantIdResolver = widget.tenantIdResolver;
    if (tenantIdResolver != null) return tenantIdResolver();

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
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
}
