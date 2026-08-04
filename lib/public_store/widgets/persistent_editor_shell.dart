import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../modules/website/providers/website_edit_mode_provider.dart';
import '../../modules/website/widgets/deferred_editable_block_renderer.dart';
import '../../modules/website/widgets/website_editor_chrome_geometry.dart';
import '../../modules/website/widgets/deferred_website_editor_panel.dart';
import '../../modules/website/models/website_editor_capability.dart';
import '../../modules/website/services/website_save_coordinator.dart';
import '../../modules/website/services/website_editor_draft_store.dart';
import '../../modules/website/services/website_service.dart';
import '../../shared/services/tenant_service.dart';
import '../../shared/widgets/workspace_shell_scope.dart';
import '../../modules/website/widgets/website_editor_contextual_dock.dart';
import '../../modules/website/widgets/website_editor_draft_recovery_host.dart';
import '../../modules/website/widgets/website_editor_command_scope.dart';

/// A persistent shell that keeps the editor panel mounted across route changes.
///
/// This widget wraps the router content and overlays the editor panel when in
/// edit mode. The key insight is that the editor panel is rendered OUTSIDE
/// the router, so it won't be rebuilt when pages change.
class PersistentEditorShell extends StatefulWidget {
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
          identityRevision != editProvider.editorEntryLeaseIdentityRevision ||
          currentDocument.sessionRevision != documentRevision ||
          currentDocument.pageId != pageId ||
          currentDocument.pageSlug != pageSlug ||
          serviceEpoch != websiteService.identityEpoch ||
          requestIdentity != websiteService.editorCapabilityRequestIdentity) {
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

  @visibleForTesting
  final WebsiteEditorDraftStore? draftStore;

  /// Geometry has one owner. The literal `380` that used to live here — and in
  /// three other files, each deciding independently — had no Design source;
  /// `O-04 VbSideSheet` puts the pane at 420–540 and caps it at 40% of the
  /// width. See [WebsiteEditorChromeGeometry].
  static const double _editorTopBarHeight =
      WebsiteEditorChromeGeometry.topBarHeight;

  const PersistentEditorShell({
    super.key,
    required this.child,
    @visibleForTesting this.saveCoordinator,
    @visibleForTesting this.tenantIdResolver,
    @visibleForTesting this.draftStore,
  });

  @override
  State<PersistentEditorShell> createState() => _PersistentEditorShellState();
}

class _PersistentEditorShellState extends State<PersistentEditorShell> {
  bool _isSaving = false;
  WebsiteService? _saveCoordinatorOwner;
  WebsiteSaveCoordinator? _saveCoordinator;

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
    return WebsiteEditorCommandScope(
      isSaving: _isSaving,
      onSave: _handleSave,
      onDiscard: _handleDiscard,
      onRestoreComplete: _handleRestoreComplete,
      child: Padding(
        padding: EdgeInsets.only(top: workspaceTopInset),
        child: Transform.translate(
          key: const ValueKey('persistent-editor-workspace-content'),
          offset: Offset.zero,
          // Measured and published UNCONDITIONALLY, in every mode and viewport.
          // A conditional wrapper here is exactly what the editor contract warns
          // about: it can change the internal composition and remount a plain
          // GoRoute even when the content anchor keeps its key. Only the values
          // this scope carries change.
          child: LayoutBuilder(
            key: const ValueKey('persistent-editor-chrome-measure'),
            builder: (context, constraints) {
              final editorWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : MediaQuery.sizeOf(context).width;
              final paneWidth =
                  WebsiteEditorChromeGeometry.paneWidthFor(editorWidth);
              // A pane only exists when the editor can afford one. Below the
              // derived threshold the composition is contextual and the canvas
              // keeps the whole width: never a compressed side panel.
              final mountsPane = showEditorPanel && paneWidth != null;

              return WebsiteEditorChromeScope(
                editorWidth: editorWidth,
                canvasWidth: mountsPane ? editorWidth - paneWidth : editorWidth,
                child: Stack(
                  children: [
                    // Keep router child full-width so the top command bar uses
                    // all space. The whole editor starts below global workspace
                    // chrome; otherwise the two command systems overlap by
                    // exactly the workspace-bar height.
                    Positioned.fill(
                      child: widget.child,
                    ),
                    // Persistent editor pane. The Stack structure is always
                    // present; only this optional sibling comes and goes.
                    if (mountsPane)
                      Positioned(
                        top: PersistentEditorShell._editorTopBarHeight,
                        right: 0,
                        bottom: 0,
                        width: paneWidth,
                        child: _PersistentEditorPanel(
                          editProvider: editProvider,
                          onSave: _handleSave,
                          onRestoreComplete: _handleRestoreComplete,
                          onDiscard: _handleDiscard,
                        ),
                      ),
                    // Contextual host. Below the derived pane threshold the
                    // editor has no inspector column, so editing starts at the
                    // selected block: a dock accompanies the selection and
                    // `Editar` opens the `O-05` sheet over a canvas that stays
                    // mounted. Same slot as the anchor it replaces, so the
                    // canvas geometry does not move.
                    if (showEditorPanel && paneWidth == null)
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: WebsiteEditorContextualDock(
                          key: ValueKey('persistent-editor-contextual-anchor'),
                        ),
                      ),
                    if (editProvider.isInEditorContext)
                      Positioned(
                        top: PersistentEditorShell._editorTopBarHeight + 8,
                        left: 12,
                        right: mountsPane ? paneWidth + 12 : 12,
                        child: WebsiteEditorDraftRecoveryHost(
                          provider: editProvider,
                          store: widget.draftStore,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _handleSave() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final editProvider = context.read<WebsiteEditModeProvider>();
      var coordinator = widget.saveCoordinator;
      if (coordinator == null) {
        final websiteService = context.read<WebsiteService>();
        if (!identical(_saveCoordinatorOwner, websiteService)) {
          _saveCoordinatorOwner = websiteService;
          _saveCoordinator = WebsiteSaveCoordinator.forService(websiteService);
        }
        coordinator = _saveCoordinator!;
      }

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
          _showMessage(
            '✅ Cambios guardados; hay ediciones nuevas sin guardar.',
          );
        } else {
          _showSuccess('✅ Cambios guardados');
        }
      } else {
        _showMessage(
          'La sesión cambió durante el guardado; revisa el estado actual '
          'antes de continuar.',
        );
      }

      if (mounted &&
          result.appliedToActiveDocument &&
          !editProvider.hasUnsavedChanges) {
        editProvider.setMode(WebsiteEditorMode.preview);
      }
    } on WebsiteEditorWriteSupersededException {
      _showMessage('El guardado quedó obsoleto por un cambio de sesión.');
    } catch (error) {
      _showError('Error al guardar: $error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _handleDiscard() {
    final editProvider = context.read<WebsiteEditModeProvider>();
    editProvider.discardPendingChanges();
    editProvider.setMode(WebsiteEditorMode.preview);
  }

  Future<void> _handleRestoreComplete() {
    return PersistentEditorShell.restoreEditorDocumentAfterBackup(
      editProvider: context.read<WebsiteEditModeProvider>(),
      websiteService: context.read<WebsiteService>(),
      resolveTenantId: _resolveTenantId,
    );
  }

  Future<String?> _resolveTenantId() async {
    final tenantIdResolver = widget.tenantIdResolver;
    if (tenantIdResolver != null) return tenantIdResolver();
    return TenantService().getTenantId();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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

/// The editor panel widget, designed to be persistent across page navigations.
class _PersistentEditorPanel extends StatelessWidget {
  final WebsiteEditModeProvider editProvider;
  final Future<void> Function() onSave;
  final Future<void> Function() onRestoreComplete;
  final VoidCallback onDiscard;

  const _PersistentEditorPanel({
    required this.editProvider,
    required this.onSave,
    required this.onRestoreComplete,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    return DeferredWebsiteEditorPanel(
      onSave: onSave,
      onRestoreComplete: onRestoreComplete,
      onDiscard: onDiscard,
    );
  }
}
