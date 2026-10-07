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
      throw const WebsiteEditorWriteSupersededException(
        'La sesión del editor cambió mientras se cargaban las versiones.',
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
              ? 'Guarda o descarta los cambios antes de volver a una versión.'
              : 'La sesión del editor cambió. Vuelve a intentar.',
        ),
      ),
    );
  }

  Future<void> _createBackup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe un nombre para esta versión')),
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
      );
      scope.authority.ensureCurrent();

      _nameController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Versión guardada')),
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
      operation: 'volver a la versión',
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
        title: const Text('¿Volver a esta versión?'),
        content: Text(
          'Las páginas, la marca y los ajustes quedan como en '
          '«${backup.name}» (${_versionDate(backup.createdAt)}). Antes se '
          'guarda sola una versión de cómo están ahora, para poder deshacerlo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Volver a esta'),
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
        throw Exception('No se pudo volver a esa versión');
      }
      scope.authority.ensureCurrent();

      if (mounted) {
        await widget.onRestoreComplete?.call();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('El sitio volvió a «${backup.name}»')),
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
      operation: 'borrar la versión',
      requireCleanDraft: false,
    );
    if (scope == null) {
      _showOwnerChangedMessage();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Borrar esta versión?'),
        content: Text(
          '«${backup.name}» (${_versionDate(backup.createdAt)}) deja de '
          'estar en la lista. El sitio no cambia.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: const Text('Borrar'),
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
        throw Exception('No se pudo borrar la versión');
      }
      scope.authority.ensureCurrent();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Versión borrada')),
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
    final busy = _isCreating || _isRestoring || _isDeleting;
    // The editor's own graphite surface, so it reads as part of the editor
    // in light and in dark.
    return Theme(
      data: WebsiteEditorInspectorTheme.resolveFrom(context),
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final scheme = theme.colorScheme;
          return Dialog(
            key: const ValueKey('website-versions-dialog'),
            backgroundColor: scheme.surface,
            insetPadding: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: 560,
                maxWidth: 560,
                maxHeight: 640,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 8, 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Versiones guardadas',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Cada «Guardar» deja una; quedan las últimas '
                                '30. Las que guardas con nombre no se borran '
                                'solas.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: busy ? null : () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _nameController,
                            enabled: !busy,
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: 'Nombre (ej.: antes del rediseño)',
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _createBackup(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: busy ? null : _createBackup,
                          icon: _isCreating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.bookmark_add_outlined,
                                  size: 18),
                          label: const Text('Guardar con nombre'),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: scheme.outlineVariant),
                  Flexible(child: _buildVersionList(theme, busy)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVersionList(ThemeData theme, bool busy) {
    final scheme = theme.colorScheme;
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No se pudieron leer las versiones.',
              style: TextStyle(color: scheme.error),
            ),
            TextButton(
              onPressed: _loadBackups,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }
    if (_backups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'Todavía no hay versiones: la primera queda al próximo «Guardar».',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }
    // By day, newest first: «Hoy», «Ayer», then the date.
    final rows = <Widget>[];
    String? day;
    for (final backup in _backups) {
      final label = _versionDay(backup.createdAt);
      if (label != day) {
        day = label;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Text(
              label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
      rows.add(
        _BackupListItem(
          backup: backup,
          onRestore: () => _restoreBackup(backup),
          onDelete: () => _deleteBackup(backup),
          isRestoring: _isRestoring,
          isBusy: busy,
        ),
      );
    }
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 12),
      children: rows,
    );
  }
}

String _versionDay(DateTime createdAt) {
  final local = createdAt.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final difference = today.difference(day).inDays;
  if (difference == 0) return 'Hoy';
  if (difference == 1) return 'Ayer';
  const months = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun', //
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}

String _versionDate(DateTime createdAt) =>
    '${_versionDay(createdAt).toLowerCase()}, '
    '${DateFormat('HH:mm').format(createdAt.toLocal())}';

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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final description = backup.description?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 16, 6),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              DateFormat('HH:mm').format(backup.createdAt.toLocal()),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        backup.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (!backup.isAutoBackup) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.bookmark_rounded,
                        size: 14,
                        color: scheme.primary,
                        semanticLabel: 'Con nombre',
                      ),
                    ],
                  ],
                ),
                if (description.isNotEmpty)
                  Text(
                    description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: isBusy ? null : onRestore,
            child: isRestoring
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Tooltip(
                    message: 'Restaurar',
                    child: Text('Volver a esta'),
                  ),
          ),
          IconButton(
            tooltip: 'Borrar',
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            color: scheme.onSurfaceVariant,
            onPressed: isBusy ? null : onDelete,
          ),
        ],
      ),
    );
  }
}
