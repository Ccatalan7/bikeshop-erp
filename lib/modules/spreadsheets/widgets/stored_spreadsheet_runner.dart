import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/services/spreadsheet_file_handoff_service.dart';
import '../../storage/models/app_stored_file.dart';
import '../../storage/services/app_file_storage_service.dart';
import 'univer_spreadsheet.dart';

abstract interface class _StoredSpreadsheetRunnerControllerDelegate {
  Future<bool> save();
}

/// Lets the surrounding file runner flush the active in-cell edit before Back.
class StoredSpreadsheetRunnerController {
  _StoredSpreadsheetRunnerControllerDelegate? _delegate;

  Future<bool> save() => _delegate?.save() ?? Future<bool>.value(true);

  void _attach(_StoredSpreadsheetRunnerControllerDelegate delegate) {
    _delegate = delegate;
  }

  void _detach(_StoredSpreadsheetRunnerControllerDelegate delegate) {
    if (identical(_delegate, delegate)) _delegate = null;
  }
}

/// Edits an XLSX/CSV file in place with the same packaged Univer engine used
/// by the routed Planillas editor.
class StoredSpreadsheetRunner extends StatefulWidget {
  const StoredSpreadsheetRunner({
    super.key,
    required this.file,
    required this.bytes,
    required this.onFileChanged,
    this.onOpenFullEditor,
    this.controller,
  });

  final AppStoredFile file;
  final Uint8List bytes;
  final ValueChanged<AppStoredFile> onFileChanged;
  final VoidCallback? onOpenFullEditor;
  final StoredSpreadsheetRunnerController? controller;

  @override
  State<StoredSpreadsheetRunner> createState() =>
      _StoredSpreadsheetRunnerState();
}

class _StoredSpreadsheetRunnerState extends State<StoredSpreadsheetRunner>
    implements _StoredSpreadsheetRunnerControllerDelegate {
  static const _saveDebounce = Duration(milliseconds: 500);

  final UniverSpreadsheetController _univerController =
      UniverSpreadsheetController();

  late AppStoredFile _file;
  Map<String, dynamic>? _initialSnapshot;
  Map<String, dynamic>? _pendingSnapshot;
  int _pendingRevision = 0;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _engineReady = false;
  String? _loadError;
  String? _saveError;
  Timer? _saveTimer;
  Future<void>? _saveCycle;

  bool get _hasPendingChanges => _pendingSnapshot != null;

  @override
  void initState() {
    super.initState();
    _file = widget.file;
    widget.controller?._attach(this);
    unawaited(_decodeWorkbook());
  }

  @override
  void didUpdateWidget(covariant StoredSpreadsheetRunner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    if (oldWidget.file.id != widget.file.id) {
      _file = widget.file;
      unawaited(_decodeWorkbook());
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _saveTimer?.cancel();
    final pending = _pendingSnapshot;
    if (_saveCycle == null && pending != null) {
      unawaited(_persistAfterDispose(_file, pending));
    }
    super.dispose();
  }

  Future<void> _decodeWorkbook() async {
    _saveTimer?.cancel();
    setState(() {
      _isLoading = true;
      _loadError = null;
      _saveError = null;
      _engineReady = false;
      _initialSnapshot = null;
      _pendingSnapshot = null;
    });
    try {
      final workbook = await SpreadsheetFileHandoffService.instance.decodeBytes(
        bytes: widget.bytes,
        fileName: _file.fileName,
      );
      if (!mounted) return;
      setState(() {
        _initialSnapshot = Map<String, dynamic>.from(workbook.workbookData);
        _isLoading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Stored spreadsheet decode error: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'No se pudo abrir este archivo en el editor de Planillas.';
      });
    }
  }

  void _handleSnapshotChanged(Map<String, dynamic> snapshot) {
    if (!mounted) return;
    setState(() {
      _pendingSnapshot = Map<String, dynamic>.from(snapshot);
      _pendingRevision++;
      _saveError = null;
    });
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, () {
      unawaited(_saveNow(requestCurrentSnapshot: false));
    });
  }

  void _handleEngineReady() {
    if (!mounted) return;
    setState(() => _engineReady = true);
  }

  void _handleEngineError(String message) {
    debugPrint('Stored spreadsheet bridge error: $message');
    if (!mounted) return;
    setState(() {
      _saveError = 'El editor no pudo sincronizar el archivo.';
    });
  }

  @override
  Future<bool> save() => _saveNow();

  Future<bool> _saveNow({bool requestCurrentSnapshot = true}) async {
    _saveTimer?.cancel();
    if (requestCurrentSnapshot && _engineReady) {
      final current = await _univerController.requestSnapshot();
      if (current == null) {
        _handleEngineError('No snapshot returned.');
        return false;
      }
      if (!mounted) return false;
      setState(() {
        _pendingSnapshot = Map<String, dynamic>.from(current);
        _pendingRevision++;
        _saveError = null;
      });
    }

    while (_hasPendingChanges) {
      final active = _saveCycle;
      if (active != null) {
        await active;
      } else {
        final cycle = _runSaveCycle();
        _saveCycle = cycle;
        await cycle;
        if (identical(_saveCycle, cycle)) _saveCycle = null;
      }
      if (_saveError != null) return false;
    }
    return true;
  }

  Future<void> _runSaveCycle() async {
    if (mounted) {
      setState(() {
        _isSaving = true;
        _saveError = null;
      });
    }
    try {
      while (_pendingSnapshot != null) {
        final snapshot = _pendingSnapshot!;
        final revision = _pendingRevision;
        final workbook = Map<String, dynamic>.from(snapshot);
        final bytes = await SpreadsheetFileHandoffService.instance.encodeBytes(
          workbookData: workbook,
          fileName: _file.fileName,
        );
        final updated = await AppFileStorageService.instance.replaceFileBytes(
          file: _file,
          bytes: bytes,
          mimeType: _file.mimeType,
          addTags: const ['editado'],
          metadataPatch: <String, dynamic>{
            'last_edited_at': DateTime.now().toUtc().toIso8601String(),
            'spreadsheet_engine': 'univer',
            'spreadsheet_engine_version': workbook['appVersion'],
          },
        );
        _file = updated;

        void acknowledge() {
          if (_pendingRevision == revision) _pendingSnapshot = null;
          _saveError = null;
        }

        if (mounted) {
          setState(acknowledge);
          widget.onFileChanged(updated);
        } else {
          acknowledge();
        }
      }
    } catch (error, stackTrace) {
      debugPrint('Stored spreadsheet save error: $error\n$stackTrace');
      if (mounted) {
        setState(() {
          _saveError =
              'No se pudo guardar el Excel. Los cambios siguen pendientes.';
        });
      } else {
        _saveError = 'No se pudo guardar el Excel.';
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _persistAfterDispose(
    AppStoredFile file,
    Map<String, dynamic> workbook,
  ) async {
    try {
      final bytes = await SpreadsheetFileHandoffService.instance.encodeBytes(
        workbookData: workbook,
        fileName: file.fileName,
      );
      await AppFileStorageService.instance.replaceFileBytes(
        file: file,
        bytes: bytes,
        mimeType: file.mimeType,
        addTags: const ['editado'],
        metadataPatch: <String, dynamic>{
          'last_edited_at': DateTime.now().toUtc().toIso8601String(),
          'spreadsheet_engine': 'univer',
          'spreadsheet_engine_version': workbook['appVersion'],
        },
      );
    } catch (error, stackTrace) {
      debugPrint('Stored spreadsheet detached save error: $error\n$stackTrace');
    }
  }

  String get _statusLabel {
    if (_isLoading) return 'Abriendo Excel…';
    if (_isSaving) return 'Guardando en el archivo…';
    if (_saveError != null) return 'Error al guardar';
    if (_hasPendingChanges) return 'Cambios pendientes';
    if (!_engineReady) return 'Iniciando editor…';
    return 'Guardado en el archivo';
  }

  IconData get _statusIcon {
    if (_saveError != null) return Icons.error_outline;
    if (_isSaving || _isLoading || !_engineReady) return Icons.sync;
    if (_hasPendingChanges) return Icons.cloud_upload_outlined;
    return Icons.cloud_done_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorColor = theme.colorScheme.error;
    final statusColor = _saveError != null
        ? errorColor
        : _hasPendingChanges
            ? theme.colorScheme.tertiary
            : theme.colorScheme.onSurfaceVariant;
    final initialSnapshot = _initialSnapshot;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            unawaited(_saveNow()),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            unawaited(_saveNow()),
      },
      child: Column(
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.only(left: 10, right: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                Icon(_statusIcon, size: 15, color: statusColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _statusLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.onOpenFullEditor != null)
                  IconButton(
                    tooltip: 'Abrir también en el módulo Planillas',
                    onPressed: widget.onOpenFullEditor,
                    icon: const Icon(Icons.open_in_full, size: 17),
                  ),
                IconButton(
                  tooltip: 'Guardar ahora (⌘S)',
                  onPressed: _isLoading || _isSaving
                      ? null
                      : () => unawaited(_saveNow()),
                  icon: const Icon(Icons.save_outlined, size: 18),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _loadError != null
                    ? _RunnerSpreadsheetError(
                        message: _loadError!,
                        onRetry: _decodeWorkbook,
                      )
                    : initialSnapshot == null
                        ? const SizedBox.shrink()
                        : UniverSpreadsheetView(
                            key: ValueKey<String>(
                              'stored-spreadsheet-engine-${_file.id}',
                            ),
                            controller: _univerController,
                            initialSnapshot: initialSnapshot,
                            onSnapshotChanged: _handleSnapshotChanged,
                            onReady: _handleEngineReady,
                            onError: _handleEngineError,
                          ),
          ),
          if (_saveError case final error?)
            MaterialBanner(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              content: Text(error, style: theme.textTheme.bodySmall),
              leading: Icon(Icons.error_outline, color: errorColor),
              actions: [
                TextButton(
                  onPressed: () => unawaited(_saveNow()),
                  child: const Text('REINTENTAR'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _RunnerSpreadsheetError extends StatelessWidget {
  const _RunnerSpreadsheetError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.table_view_outlined, size: 34),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
