import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/main_layout.dart';
import '../models/spreadsheet_model.dart';
import '../services/spreadsheet_service.dart';
import '../services/univer_workbook_adapter.dart';
import '../widgets/univer_spreadsheet.dart';

/// Route-level handoff used by the spreadsheet [GoRoute.onExit] callback.
///
/// A route guard is required in addition to an in-page back button because
/// sidebar and workspace navigation replace locations with `context.go`.
class SpreadsheetEditorExitGuard {
  const SpreadsheetEditorExitGuard._();

  static final Map<String, _SpreadsheetEditorExitRegistration> _handlers =
      <String, _SpreadsheetEditorExitRegistration>{};

  static void register(
    String spreadsheetId,
    Object owner,
    Future<bool> Function() handler,
  ) {
    _handlers[spreadsheetId] = _SpreadsheetEditorExitRegistration(
      owner: owner,
      handler: handler,
    );
  }

  static void unregister(String spreadsheetId, Object owner) {
    final registration = _handlers[spreadsheetId];
    if (registration == null || !identical(registration.owner, owner)) return;
    _handlers.remove(spreadsheetId);
  }

  static Future<bool> canExit(String spreadsheetId) {
    return _handlers[spreadsheetId]?.handler.call() ?? Future<bool>.value(true);
  }
}

class _SpreadsheetEditorExitRegistration {
  const _SpreadsheetEditorExitRegistration({
    required this.owner,
    required this.handler,
  });

  final Object owner;
  final Future<bool> Function() handler;
}

class SpreadsheetEditorPage extends StatefulWidget {
  const SpreadsheetEditorPage({
    super.key,
    required this.spreadsheetId,
    this.storeOverride,
  });

  final String spreadsheetId;

  /// Test seam for the persistence boundary. Production routes use the
  /// provider-backed [SpreadsheetService].
  final SpreadsheetStore? storeOverride;

  @override
  State<SpreadsheetEditorPage> createState() => _SpreadsheetEditorPageState();
}

class _SpreadsheetEditorPageState extends State<SpreadsheetEditorPage>
    with WidgetsBindingObserver {
  static const Duration _saveDebounce = Duration(milliseconds: 450);

  final UniverSpreadsheetController _univerController =
      UniverSpreadsheetController();

  late SpreadsheetStore _store;
  bool _initialized = false;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isLeaving = false;
  bool _engineReady = false;
  bool _saveBlockedBySchema = false;
  String? _loadError;
  String? _saveError;
  String? _bridgeError;
  SpreadsheetModel? _sheet;

  /// The immutable bootstrap payload for the mounted Univer instance.
  Map<String, dynamic>? _initialSnapshot;

  /// The newest bridge snapshot that has not been acknowledged by storage.
  Map<String, dynamic>? _latestPendingSnapshot;
  int _pendingSnapshotRevision = 0;

  Timer? _saveTimer;
  Future<void>? _saveCycle;
  Future<bool>? _exitGuardCycle;

  bool get _hasUnsavedChanges => _latestPendingSnapshot != null;
  String? get _visibleError => _saveError ?? _bridgeError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _store = widget.storeOverride ?? context.read<SpreadsheetService>();
    SpreadsheetEditorExitGuard.register(
      widget.spreadsheetId,
      this,
      _guardRouteExit,
    );
    unawaited(_loadSpreadsheet());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.inactive &&
        state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached) {
      return;
    }

    if (_engineReady) {
      unawaited(
        _saveNow(
          requestCurrentSnapshot: true,
          showFailureMessage: false,
        ),
      );
    } else if (_hasUnsavedChanges) {
      unawaited(
        _saveNow(
          requestCurrentSnapshot: false,
          showFailureMessage: false,
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SpreadsheetEditorExitGuard.unregister(widget.spreadsheetId, this);
    _saveTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSpreadsheet() async {
    _saveTimer?.cancel();
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
        _bridgeError = null;
      });
    }

    try {
      await _store.fetchSpreadsheets();
      SpreadsheetModel? sheet;
      for (final candidate in _store.spreadsheets) {
        if (candidate.id == widget.spreadsheetId) {
          sheet = candidate;
          break;
        }
      }
      if (sheet == null) {
        throw StateError('Spreadsheet not found');
      }

      final persistedWorkbook = sheet.workbookData;
      final hasPersistedData = persistedWorkbook?.isNotEmpty ?? false;
      final hasPersistedWorkbook =
          UniverWorkbookAdapter.isValidSnapshot(persistedWorkbook);
      final legacyCells = hasPersistedWorkbook
          ? const <CellModel>[]
          : await _store.loadCells(widget.spreadsheetId);
      if (hasPersistedData && !hasPersistedWorkbook && legacyCells.isEmpty) {
        throw const FormatException('Invalid persisted Univer workbook');
      }
      final snapshot = UniverWorkbookAdapter.createSnapshot(
        spreadsheet: sheet,
        legacyCells: legacyCells,
      );

      if (!mounted) return;
      setState(() {
        _sheet = sheet;
        _initialSnapshot = Map<String, dynamic>.from(snapshot);
        _latestPendingSnapshot =
            hasPersistedWorkbook ? null : Map<String, dynamic>.from(snapshot);
        if (!hasPersistedWorkbook) _pendingSnapshotRevision++;
        _saveError = null;
        _bridgeError = null;
        _engineReady = false;
        _isLoading = false;
      });

      // Opening a legacy sparse-cell workbook is its one-way migration into
      // the canonical Univer snapshot. Persist the adapted snapshot even if
      // the user does not make another edit during this visit.
      if (!hasPersistedWorkbook) _scheduleSave();
    } catch (error, stackTrace) {
      debugPrint('Spreadsheet load error: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = switch (error) {
          StateError() => 'Esta planilla ya no existe o no está disponible.',
          FormatException() =>
            'Los datos guardados de esta planilla no tienen un formato válido. No se reemplazaron.',
          _ =>
            'No se pudo cargar la planilla. Revisa la conexión e inténtalo de nuevo.',
        };
      });
    }
  }

  void _handleSnapshotChanged(Map<String, dynamic> snapshot) {
    if (!mounted || _isLeaving) return;
    final shouldAutoSave = !_saveBlockedBySchema;
    setState(() {
      _latestPendingSnapshot = Map<String, dynamic>.from(snapshot);
      _pendingSnapshotRevision++;
      if (shouldAutoSave) _saveError = null;
      _bridgeError = null;
    });
    if (shouldAutoSave) _scheduleSave();
  }

  void _handleEngineReady() {
    if (!mounted) return;
    setState(() {
      _engineReady = true;
      _bridgeError = null;
    });
  }

  void _handleBridgeError(String message) {
    debugPrint('Univer spreadsheet bridge error: $message');
    if (!mounted) return;
    setState(() {
      _bridgeError =
          'No se pudo sincronizar el editor. Reintenta antes de salir.';
    });
  }

  void _scheduleSave() {
    if (_saveBlockedBySchema) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, () {
      unawaited(_saveNow(requestCurrentSnapshot: false));
    });
  }

  Future<bool> _requestCurrentSnapshot() async {
    try {
      // The Univer bridge commits an active in-cell edit before returning the
      // serialized workbook, so manual saves and guarded exits cannot miss it.
      final snapshot = await _univerController.requestSnapshot();
      if (snapshot == null) {
        _handleBridgeError('The bridge returned no workbook snapshot.');
        return false;
      }
      if (!mounted) return false;
      setState(() {
        _latestPendingSnapshot = Map<String, dynamic>.from(snapshot);
        _pendingSnapshotRevision++;
        _saveError = null;
        _bridgeError = null;
      });
      return true;
    } catch (error, stackTrace) {
      debugPrint('Univer snapshot request error: $error\n$stackTrace');
      _handleBridgeError('$error');
      return false;
    }
  }

  Future<bool> _saveNow({
    bool requestCurrentSnapshot = true,
    bool showFailureMessage = true,
  }) async {
    _saveTimer?.cancel();

    var hasCurrentSnapshot = true;
    if (requestCurrentSnapshot) {
      hasCurrentSnapshot = await _requestCurrentSnapshot();
    }

    while (_hasUnsavedChanges) {
      final activeCycle = _saveCycle;
      if (activeCycle != null) {
        await activeCycle;
      } else {
        final cycle = _runSaveCycle(showFailureMessage);
        _saveCycle = cycle;
        await cycle;
        if (identical(_saveCycle, cycle)) _saveCycle = null;
      }

      if (_saveError != null) return false;
    }

    return hasCurrentSnapshot;
  }

  Future<void> _runSaveCycle(bool showFailureMessage) async {
    if (mounted) {
      setState(() {
        _isSaving = true;
        _saveError = null;
        _saveBlockedBySchema = false;
      });
    } else {
      _saveBlockedBySchema = false;
    }

    try {
      while (_latestPendingSnapshot != null) {
        final revision = _pendingSnapshotRevision;
        final snapshot = Map<String, dynamic>.from(
          _latestPendingSnapshot!,
        );

        await _store.saveWorkbookData(widget.spreadsheetId, snapshot);

        void acknowledgeSnapshot() {
          if (_pendingSnapshotRevision == revision) {
            _latestPendingSnapshot = null;
          }
          _sheet = _sheet?.copyWith(workbookData: snapshot);
        }

        if (mounted) {
          setState(acknowledgeSnapshot);
        } else {
          acknowledgeSnapshot();
        }
      }
    } catch (error, stackTrace) {
      debugPrint('Spreadsheet save error: $error\n$stackTrace');
      final isSchemaMismatch = error is SpreadsheetSnapshotSchemaException;
      final message = isSchemaMismatch
          ? 'No se puede guardar: falta actualizar la base de datos de Planillas.'
          : 'No se pudo guardar. Revisa la conexión y reintenta.';
      if (mounted) {
        setState(() {
          _saveError = message;
          _saveBlockedBySchema = isSchemaMismatch;
        });
      } else {
        _saveError = message;
        _saveBlockedBySchema = isSchemaMismatch;
      }
      if (mounted && showFailureMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isSchemaMismatch
                  ? 'La base de datos todavía no admite este formato de Planillas. Tus cambios siguen pendientes.'
                  : 'No se pudo guardar la planilla. Tus cambios siguen pendientes.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      } else {
        _isSaving = false;
      }
    }
  }

  void _leaveEditor() {
    if (_isLeaving) return;
    context.go('/tools/spreadsheets');
  }

  Future<bool> _guardRouteExit() async {
    final activeCycle = _exitGuardCycle;
    if (activeCycle != null) return activeCycle;

    final cycle = _runRouteExitGuard();
    _exitGuardCycle = cycle;
    try {
      return await cycle;
    } finally {
      if (identical(_exitGuardCycle, cycle)) _exitGuardCycle = null;
    }
  }

  Future<bool> _runRouteExitGuard() async {
    if (_loadError != null || _initialSnapshot == null) return true;

    if (mounted) setState(() => _isLeaving = true);
    var saved = await _saveNow();

    // A bridge that never became ready cannot contain an active user edit.
    // Still flush a pending legacy migration so an unsupported surface never
    // traps the user in the route.
    if (!saved && !_engineReady) {
      saved = await _saveNow(requestCurrentSnapshot: false);
    }

    final canExit = saved && !_hasUnsavedChanges && _saveError == null;
    if (mounted && !canExit) setState(() => _isLeaving = false);
    return canExit;
  }

  Future<void> _renameSheet() async {
    final sheet = _sheet;
    if (sheet == null) return;
    final controller = TextEditingController(text: sheet.name);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Renombrar planilla'),
        content: TextField(
          key: const ValueKey('spreadsheet-name-field'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = result?.trim() ?? '';
    if (!mounted || trimmed.isEmpty || trimmed == sheet.name) return;

    try {
      await _store.renameSpreadsheet(widget.spreadsheetId, trimmed);
      if (!mounted) return;
      setState(() => _sheet = sheet.copyWith(name: trimmed));
    } catch (error, stackTrace) {
      debugPrint('Spreadsheet rename error: $error\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo cambiar el nombre.')),
      );
    }
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Volver a planillas',
            onPressed: _isLeaving ? null : _leaveEditor,
            icon: const Icon(Icons.arrow_back, size: 20),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: InkWell(
              key: const ValueKey('spreadsheet-rename-action'),
              onTap: _renameSheet,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        _sheet?.name ?? 'Planilla sin título',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.edit_outlined,
                      size: 15,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          _buildSaveStatus(context),
          const SizedBox(width: 4),
          IconButton(
            key: const ValueKey('spreadsheet-save-action'),
            tooltip: 'Guardar ahora (⌘S)',
            onPressed:
                _isSaving || _isLeaving ? null : () => unawaited(_saveNow()),
            icon: const Icon(Icons.save_outlined, size: 19),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveStatus(BuildContext context) {
    final theme = Theme.of(context);
    if (_isSaving) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 7),
          Text('Guardando…', style: TextStyle(fontSize: 12)),
        ],
      );
    }
    if (_visibleError != null) {
      return TextButton.icon(
        key: const ValueKey('spreadsheet-retry-save'),
        onPressed: () => unawaited(_saveNow()),
        icon: Icon(
          Icons.error_outline,
          size: 16,
          color: theme.colorScheme.error,
        ),
        label: Text(
          _saveBlockedBySchema
              ? 'Base de datos · Reintentar'
              : 'Error · Reintentar',
          style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
        ),
      );
    }
    if (_hasUnsavedChanges) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_upload_outlined,
            size: 16,
            color: theme.colorScheme.tertiary,
          ),
          const SizedBox(width: 6),
          const Text('Cambios pendientes', style: TextStyle(fontSize: 12)),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.cloud_done_outlined, size: 16, color: Colors.green.shade700),
        const SizedBox(width: 6),
        const Text('Guardado', style: TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildLoadError(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 38),
              const SizedBox(height: 12),
              Text(
                _loadError ?? 'No se pudo cargar la planilla.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadSpreadsheet,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditor() {
    final initialSnapshot = _initialSnapshot;
    if (initialSnapshot == null) return const SizedBox.shrink();

    return IgnorePointer(
      ignoring: _isLeaving,
      child: UniverSpreadsheetView(
        key: const ValueKey('univer-spreadsheet-host'),
        controller: _univerController,
        initialSnapshot: initialSnapshot,
        onSnapshotChanged: _handleSnapshotChanged,
        onReady: _handleEngineReady,
        onError: _handleBridgeError,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MainLayout(
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _loadError != null
                      ? _buildLoadError(context)
                      : _buildEditor(),
            ),
            if (_visibleError case final error?)
              MaterialBanner(
                content: Text(error),
                leading: Icon(
                  Icons.error_outline,
                  color: theme.colorScheme.error,
                ),
                actions: [
                  TextButton(
                    onPressed: () => unawaited(_saveNow()),
                    child: Text(
                      _saveBlockedBySchema
                          ? 'COMPROBAR DE NUEVO'
                          : 'REINTENTAR',
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
