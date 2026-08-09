part of '../website_editor_panel.dart';

/// Dialog for managing website backups
class _BackupsDialog extends StatefulWidget {
  final Future<void> Function()? onRestoreComplete;
  final WebsiteBackupService backupService;
  final bool ownsBackupService;
  final ValueListenable<int> hostProviderRevision;
  final WebsiteEditModeProvider? Function() liveProvider;

  const _BackupsDialog({
    required this.backupService,
    required this.ownsBackupService,
    required this.hostProviderRevision,
    required this.liveProvider,
    this.onRestoreComplete,
  });

  @override
  State<_BackupsDialog> createState() => _BackupsDialogState();
}

class _BackupReadStamp {
  const _BackupReadStamp({
    required this.provider,
    required this.backupService,
    required this.hostRevision,
    required this.entryLeaseGeneration,
    required this.entryLeaseIdentityRevision,
    required this.tenantId,
    required this.fingerprint,
  });

  final WebsiteEditModeProvider provider;
  final WebsiteBackupService backupService;
  final int hostRevision;
  final int entryLeaseGeneration;
  final int entryLeaseIdentityRevision;
  final String tenantId;
  final String fingerprint;
}

class _BackupRemoteScope {
  const _BackupRemoteScope({
    required this.authority,
    required this.provider,
    required this.backupService,
  });

  final WebsiteEditorRemoteWriteAuthority authority;
  final WebsiteEditModeProvider provider;
  final WebsiteBackupService backupService;
}

class _BackupsDialogState extends State<_BackupsDialog> {
  List<WebsiteBackup> _backups = [];
  bool _isLoading = true;
  bool _isCreating = false;
  bool _isRestoring = false;
  bool _isDeleting = false;
  String? _error;
  int _loadGeneration = 0;
  bool _reloadScheduled = false;
  _BackupReadStamp? _loadedStamp;
  WebsiteEditModeProvider? _listenedProvider;

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  WebsiteBackupService get _backupService => widget.backupService;

  @override
  void initState() {
    super.initState();
    widget.hostProviderRevision.addListener(_handleOwnerChanged);
    _bindProviderListener();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadBackups();
    });
  }

  @override
  void dispose() {
    widget.hostProviderRevision.removeListener(_handleOwnerChanged);
    _listenedProvider?.removeListener(_handleOwnerChanged);
    _nameController.dispose();
    _descriptionController.dispose();
    if (widget.ownsBackupService) _backupService.dispose();
    super.dispose();
  }

  void _bindProviderListener() {
    final provider = widget.liveProvider();
    if (identical(_listenedProvider, provider)) return;
    _listenedProvider?.removeListener(_handleOwnerChanged);
    _listenedProvider = provider;
    provider?.addListener(_handleOwnerChanged);
  }

  void _handleOwnerChanged() {
    if (!mounted) return;
    _bindProviderListener();
    final loaded = _loadedStamp;
    if (loaded != null && _isReadStampCurrent(loaded)) return;
    _loadedStamp = null;
    _nameController.clear();
    _descriptionController.clear();
    _scheduleReload();
  }

  void _scheduleReload() {
    if (!mounted || _reloadScheduled) return;
    _reloadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reloadScheduled = false;
      if (mounted) _loadBackups();
    });
  }

  _BackupReadStamp? _captureReadStamp() {
    final provider = widget.liveProvider();
    final tenantId = provider?.sessionOwnerTenantId?.trim() ?? '';
    final fingerprint = provider?.sessionOwnerLeaseFingerprint;
    if (provider == null || tenantId.isEmpty || fingerprint == null) {
      return null;
    }
    return _BackupReadStamp(
      provider: provider,
      backupService: _backupService,
      hostRevision: widget.hostProviderRevision.value,
      entryLeaseGeneration: provider.editorEntryLeaseGeneration,
      entryLeaseIdentityRevision: provider.editorEntryLeaseIdentityRevision,
      tenantId: tenantId,
      fingerprint: fingerprint,
    );
  }

  bool _isReadStampCurrent(_BackupReadStamp stamp) {
    final provider = widget.liveProvider();
    return mounted &&
        identical(provider, stamp.provider) &&
        identical(_backupService, stamp.backupService) &&
        widget.hostProviderRevision.value == stamp.hostRevision &&
        provider?.editorEntryLeaseGeneration == stamp.entryLeaseGeneration &&
        provider?.editorEntryLeaseIdentityRevision ==
            stamp.entryLeaseIdentityRevision &&
        provider?.sessionOwnerTenantId == stamp.tenantId &&
        provider?.sessionOwnerLeaseFingerprint == stamp.fingerprint;
  }

  void _guardReadStamp(_BackupReadStamp stamp) {
    if (!_isReadStampCurrent(stamp)) {
      throw WebsiteEditorWriteSupersededException(
        'La sesión del editor cambió mientras se cargaban las copias.',
      );
    }
  }

  Future<void> _loadBackups() async {
    final stamp = _captureReadStamp();
    if (stamp == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _backups = const <WebsiteBackup>[];
        _loadedStamp = null;
        _error = 'La sesión del editor cambió. Vuelve a abrir las copias.';
      });
      return;
    }
    final generation = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final backups = await _backupService.loadBackups(
        tenantId: stamp.tenantId,
        readGuard: () => _guardReadStamp(stamp),
      );
      if (mounted &&
          generation == _loadGeneration &&
          _isReadStampCurrent(stamp)) {
        setState(() {
          _backups = backups;
          _loadedStamp = stamp;
          _isLoading = false;
        });
      }
    } on WebsiteEditorWriteSupersededException {
      if (mounted && generation == _loadGeneration) _scheduleReload();
    } catch (e) {
      if (mounted &&
          generation == _loadGeneration &&
          _isReadStampCurrent(stamp)) {
        setState(() {
          _error = e.toString();
          _loadedStamp = stamp;
          _isLoading = false;
        });
      }
    }
  }

  _BackupRemoteScope? _captureRemoteWrite({
    required String operation,
    required bool requireCleanDraft,
  }) {
    final loaded = _loadedStamp;
    final provider = widget.liveProvider();
    if (loaded == null ||
        provider == null ||
        !_isReadStampCurrent(loaded) ||
        (requireCleanDraft && provider.hasUnsavedChanges)) {
      return null;
    }
    final intent = provider.captureAsyncIntent(requiresSelection: false);
    if (intent == null) return null;

    final hostRevision = widget.hostProviderRevision.value;
    final pageId = provider.currentPageId;
    final pageSlug = provider.currentPageSlug;
    final documentSessionRevision = provider.documentSessionRevision;
    final documentEpoch = provider.pageDocumentEpoch;
    final entryLeaseGeneration = provider.editorEntryLeaseGeneration;
    final entryLeaseIdentityRevision =
        provider.editorEntryLeaseIdentityRevision;
    final tenantId = loaded.tenantId;
    final fingerprint = loaded.fingerprint;

    bool isCurrent() {
      final live = widget.liveProvider();
      return mounted &&
          identical(live, provider) &&
          widget.hostProviderRevision.value == hostRevision &&
          live?.currentPageId == pageId &&
          live?.currentPageSlug == pageSlug &&
          live?.documentSessionRevision == documentSessionRevision &&
          live?.pageDocumentEpoch == documentEpoch &&
          live?.editorEntryLeaseGeneration == entryLeaseGeneration &&
          live?.editorEntryLeaseIdentityRevision ==
              entryLeaseIdentityRevision &&
          live?.sessionOwnerTenantId == tenantId &&
          live?.sessionOwnerLeaseFingerprint == fingerprint &&
          (!requireCleanDraft || live?.hasUnsavedChanges == false);
    }

    return _BackupRemoteScope(
      authority: WebsiteEditorRemoteWriteAuthority(
        tenantId: tenantId,
        operation: operation,
        isCurrent: isCurrent,
        claimOwner: () =>
            provider.commitAsyncIntent(
              intent,
              () => WebsiteInlineMutationResult.unchanged,
            ) !=
            WebsiteInlineMutationResult.rejected,
      ),
      provider: provider,
      backupService: _backupService,
    );
  }

  void _showOwnerChangedMessage({bool dirty = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          dirty
              ? 'Guarda o descarta los cambios antes de administrar copias de seguridad.'
              : 'La sesión del editor cambió. Vuelve a intentar.',
        ),
      ),
    );
  }

  Future<void> _createBackup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El nombre es requerido')),
      );
      return;
    }

    final scope = _captureRemoteWrite(
      operation: 'crear la copia de seguridad',
      requireCleanDraft: true,
    );
    if (scope == null) {
      _showOwnerChangedMessage(
        dirty: widget.liveProvider()?.hasUnsavedChanges == true,
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final writeGuard = scope.authority.claimForWrite();
      await scope.backupService.createBackup(
        name: name,
        tenantId: scope.authority.tenantId,
        writeGuard: writeGuard,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      );
      scope.authority.ensureCurrent();

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
    } on WebsiteEditorWriteSupersededException {
      _showOwnerChangedMessage();
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
    final scope = _captureRemoteWrite(
      operation: 'restaurar la copia de seguridad',
      requireCleanDraft: true,
    );
    if (scope == null) {
      _showOwnerChangedMessage(
        dirty: widget.liveProvider()?.hasUnsavedChanges == true,
      );
      return;
    }

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

    try {
      scope.authority.ensureCurrent();
      setState(() => _isRestoring = true);
      final writeGuard = scope.authority.claimForWrite();
      final restored = await scope.backupService.restoreBackup(
        backup.id,
        tenantId: scope.authority.tenantId,
        writeGuard: writeGuard,
      );
      if (!restored) {
        throw Exception('La copia de seguridad no pudo restaurarse');
      }
      scope.authority.ensureCurrent();

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
    } on WebsiteEditorWriteSupersededException {
      _showOwnerChangedMessage();
      if (mounted) setState(() => _isRestoring = false);
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
    final scope = _captureRemoteWrite(
      operation: 'eliminar la copia de seguridad',
      requireCleanDraft: false,
    );
    if (scope == null) {
      _showOwnerChangedMessage();
      return;
    }

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

    setState(() => _isDeleting = true);
    try {
      scope.authority.ensureCurrent();
      final writeGuard = scope.authority.claimForWrite();
      final deleted = await scope.backupService.deleteBackup(
        backup.id,
        tenantId: scope.authority.tenantId,
        writeGuard: writeGuard,
      );
      if (!deleted) {
        throw Exception('La copia de seguridad no pudo eliminarse');
      }
      scope.authority.ensureCurrent();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copia de seguridad eliminada'),
            backgroundColor: Colors.orange,
          ),
        );
        await _loadBackups();
      }
    } on WebsiteEditorWriteSupersededException {
      _showOwnerChangedMessage();
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
      if (mounted) setState(() => _isDeleting = false);
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
                    onPressed: _isCreating || _isRestoring || _isDeleting
                        ? null
                        : () => Navigator.pop(context),
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
                      onPressed: _isCreating || _isRestoring || _isDeleting
                          ? null
                          : _createBackup,
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
                                    isBusy: _isRestoring ||
                                        _isCreating ||
                                        _isDeleting,
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
  final bool isBusy;

  const _BackupListItem({
    required this.backup,
    required this.onRestore,
    required this.onDelete,
    required this.isRestoring,
    required this.isBusy,
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
              onPressed: isBusy ? null : onRestore,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: Colors.red.shade300,
              tooltip: 'Eliminar',
              onPressed: isBusy ? null : onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
