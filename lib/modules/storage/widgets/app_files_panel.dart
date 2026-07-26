import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../../shared/services/workspace_manager.dart';
import '../../../shared/services/ocr_file_handoff_service.dart';
import '../../../shared/services/right_toolbar_service.dart';
import '../../../shared/services/spreadsheet_file_handoff_service.dart';
import '../../../shared/utils/file_download.dart';
import '../../spreadsheets/services/spreadsheet_service.dart';
import '../../spreadsheets/widgets/stored_spreadsheet_runner.dart';
import '../models/app_stored_file.dart';
import '../services/app_file_storage_service.dart';
import 'storage_image_crop_dialog.dart';

enum _StorageSort {
  newest('Recientes primero'),
  oldest('Antiguos primero'),
  nameAsc('Nombre A-Z'),
  sizeDesc('Más pesados');

  const _StorageSort(this.label);

  final String label;
}

enum _StorageCompactTab {
  folders,
  recent,
  screenshots,
}

typedef AppFilesLoader = Future<List<AppStoredFile>> Function({
  required String query,
  required int limit,
});

class AppFilesPanel extends StatefulWidget {
  final bool compact;
  final bool showHeader;
  final bool runnerMode;
  final String? initialFileId;
  final String? initialOpenRequestId;
  final AppFilesLoader? filesLoader;

  const AppFilesPanel({
    super.key,
    this.compact = false,
    this.showHeader = true,
    this.runnerMode = false,
    this.initialFileId,
    this.initialOpenRequestId,
    this.filesLoader,
  });

  @override
  State<AppFilesPanel> createState() => _AppFilesPanelState();
}

class _AppFilesPanelState extends State<AppFilesPanel> {
  AppFileStorageService get _service => AppFileStorageService.instance;
  final _searchController = TextEditingController();
  final _dateFormat = DateFormat('dd/MM HH:mm');

  List<AppStoredFile> _allFiles = const [];
  List<AppStoredFile> _files = const [];
  String _selectedFolderId = 'all';
  final Set<String> _expandedFolderIds = <String>{};
  _StorageSort _sort = _StorageSort.newest;
  _StorageCompactTab _compactTab = _StorageCompactTab.recent;
  Timer? _searchDebounce;
  StreamSubscription<AppStoredFile>? _savedFilesSubscription;
  String _query = '';
  String? _error;
  bool _isLoading = true;
  bool _isUploading = false;
  bool _isDragging = false;
  final Set<String> _spreadsheetImportIds = <String>{};
  AppStoredFile? _runnerFile;
  String? _handledInitialFileRequestKey;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    if (widget.filesLoader == null) {
      _savedFilesSubscription = _service.savedFiles.listen((_) {
        if (!mounted) return;
        unawaited(_loadFiles());
      });
    }
    _loadFiles();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _savedFilesSubscription?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AppFilesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.compact != widget.compact ||
        oldWidget.filesLoader != widget.filesLoader) {
      unawaited(_loadFiles());
      return;
    }
    if (oldWidget.initialFileId == widget.initialFileId &&
        oldWidget.initialOpenRequestId == widget.initialOpenRequestId) {
      return;
    }
    unawaited(_openInitialFileIfNeeded(_allFiles));
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      final nextQuery = _searchController.text.trim();
      if (nextQuery == _query) return;
      setState(() => _query = nextQuery);
      _loadFiles();
    });
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final limit = widget.compact ? 120 : 360;
      final filesLoader = widget.filesLoader;
      var files = filesLoader == null
          ? await _service.listFiles(query: _query, limit: limit)
          : await filesLoader(query: _query, limit: limit);
      files = await _autoTagSupplierDownloads(files);
      if (!mounted) return;
      setState(() {
        _allFiles = files;
        _applyCurrentView();
      });
      unawaited(_openInitialFileIfNeeded(files));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openInitialFileIfNeeded(List<AppStoredFile> loadedFiles) async {
    final fileId = widget.initialFileId?.trim();
    final requestKey = _currentInitialFileRequestKey();
    if (fileId == null ||
        fileId.isEmpty ||
        requestKey == _handledInitialFileRequestKey ||
        !mounted) {
      return;
    }

    AppStoredFile? file;
    for (final candidate in loadedFiles) {
      if (candidate.id == fileId) {
        file = candidate;
        break;
      }
    }
    try {
      file ??= await _service.getFileById(fileId);
    } catch (_) {
      if (!mounted || _currentInitialFileRequestKey() != requestKey) return;
      _handledInitialFileRequestKey = requestKey;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir ese archivo.')),
      );
      return;
    }
    if (!mounted || _currentInitialFileRequestKey() != requestKey) return;

    _handledInitialFileRequestKey = requestKey;
    if (file == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ese archivo ya no está disponible.')),
      );
      return;
    }

    final selectedFile = file;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _currentInitialFileRequestKey() != requestKey) return;
      StorageFilePreviewDialog.show(context, selectedFile);
    });
  }

  String _currentInitialFileRequestKey() {
    return '${widget.initialFileId?.trim()}:'
        '${widget.initialOpenRequestId?.trim() ?? ''}';
  }

  Future<List<AppStoredFile>> _autoTagSupplierDownloads(
    List<AppStoredFile> files,
  ) async {
    final enriched = <AppStoredFile>[];

    for (final file in files) {
      if (_sourceBucket(file.sourceType) != 'browser' ||
          _supplierId(file) != null) {
        enriched.add(file);
        continue;
      }

      final url = _downloadUrl(file);
      if (url == null) {
        enriched.add(file);
        continue;
      }

      try {
        final match = await _service.matchSupplierForUrl(url);
        if (match == null) {
          enriched.add(file);
          continue;
        }
        enriched.add(
          await _service.attachSupplierContext(
            file: file,
            supplier: match,
          ),
        );
      } catch (_) {
        enriched.add(file);
      }
    }

    return enriched;
  }

  String? _downloadUrl(AppStoredFile file) {
    final metadataUrl = file.metadata['url']?.toString().trim();
    if (metadataUrl != null && metadataUrl.isNotEmpty) return metadataUrl;

    final subtitle = file.contextSubtitle?.trim();
    if (subtitle == null || subtitle.isEmpty) return null;
    final uri = Uri.tryParse(subtitle);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    return uri.toString();
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final files = <_UploadPayload>[];
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) continue;
      files.add(
        _UploadPayload(
          fileName: file.name,
          bytes: bytes,
          mimeType: lookupMimeType(file.name, headerBytes: bytes),
        ),
      );
    }

    await _saveUploads(files);
  }

  Future<void> _handleDroppedFiles(List<XFile> files) async {
    if (files.isEmpty) return;
    setState(() => _isDragging = false);

    final payloads = <_UploadPayload>[];
    for (final file in files) {
      try {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) continue;
        payloads.add(
          _UploadPayload(
            fileName: file.name,
            bytes: bytes,
            mimeType: file.mimeType ?? lookupMimeType(file.name),
          ),
        );
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo preparar ${file.name}: $error'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }

    await _saveUploads(payloads);
  }

  Future<void> _saveUploads(List<_UploadPayload> files) async {
    if (files.isEmpty) return;

    setState(() => _isUploading = true);
    var savedCount = 0;

    try {
      for (final file in files) {
        await _service.saveFile(
          bytes: file.bytes,
          fileName: file.fileName,
          mimeType: file.mimeType,
          context: const AppFileContext(
            sourceType: 'manual',
            contextType: 'manual',
            contextTitle: 'Carga manual',
            sourceRoute: '/storage',
          ),
        );
        savedCount++;
      }
      await _loadFiles();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            savedCount == 1
                ? 'Archivo guardado en Archivos.'
                : '$savedCount archivos guardados en Archivos.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar el archivo: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _selectFolder(String folderId, {bool showRecent = false}) {
    setState(() {
      _selectedFolderId = folderId;
      _applyCurrentView();
      if (showRecent) _compactTab = _StorageCompactTab.recent;
    });
  }

  void _setSort(_StorageSort sort) {
    setState(() {
      _sort = sort;
      _applyCurrentView();
    });
  }

  void _setCompactTab(_StorageCompactTab tab) {
    setState(() {
      _compactTab = tab;
      _applyCurrentView();
    });
  }

  void _applyCurrentView() {
    final files = _allFiles.where((file) {
      if (widget.compact && _compactTab == _StorageCompactTab.screenshots) {
        return _sourceBucket(file.sourceType) == 'screenshot';
      }
      return _matchesSelectedFolder(file);
    }).toList();
    files.sort((a, b) {
      switch (_sort) {
        case _StorageSort.newest:
          return b.createdAt.compareTo(a.createdAt);
        case _StorageSort.oldest:
          return a.createdAt.compareTo(b.createdAt);
        case _StorageSort.nameAsc:
          return a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase());
        case _StorageSort.sizeDesc:
          return b.sizeBytes.compareTo(a.sizeBytes);
      }
    });
    _files = files;
  }

  bool _matchesSelectedFolder(AppStoredFile file) {
    final folderId = _selectedFolderId;
    if (folderId == 'all') return true;
    if (folderId == 'suppliers') return _supplierId(file) != null;
    if (folderId == 'type:pdf') return file.isPdf;
    if (folderId == 'type:image') return file.isImage;
    if (folderId.startsWith('source:')) {
      return _sourceBucket(file.sourceType) == folderId.substring(7);
    }
    if (folderId.startsWith('supplier:')) {
      return _supplierId(file) == folderId.substring(9);
    }
    return true;
  }

  List<_StorageFolder> _folders() {
    final supplierFolders = <String, _SupplierFolderAccumulator>{};
    for (final file in _allFiles) {
      final supplierId = _supplierId(file);
      final supplierName = _supplierName(file);
      if (supplierId == null || supplierName == null) continue;
      final accumulator = supplierFolders.putIfAbsent(
        supplierId,
        () => _SupplierFolderAccumulator(supplierId, supplierName),
      );
      accumulator.count++;
    }

    final suppliers = supplierFolders.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return <_StorageFolder>[
      _StorageFolder(
        id: 'all',
        label: 'Todos',
        subtitle: 'Biblioteca completa',
        glyph: '🗃️',
        color: const Color(0xFF2563EB),
        count: _allFiles.length,
      ),
      _StorageFolder(
        id: 'suppliers',
        label: 'Proveedores',
        subtitle: 'Archivos por proveedor',
        glyph: '🏬',
        color: const Color(0xFFD97706),
        count: _allFiles.where((file) => _supplierId(file) != null).length,
      ),
      for (final supplier in suppliers)
        _StorageFolder(
          id: 'supplier:${supplier.id}',
          label: supplier.name,
          subtitle: 'Proveedor',
          glyph: '📂',
          color: const Color(0xFF4F46E5),
          count: supplier.count,
          parentId: 'suppliers',
          depth: 1,
        ),
      _StorageFolder(
        id: 'source:browser',
        label: 'Navegador',
        subtitle: 'Descargas web',
        glyph: '🌐',
        color: const Color(0xFF0F766E),
        count: _allFiles
            .where((file) => _sourceBucket(file.sourceType) == 'browser')
            .length,
      ),
      _StorageFolder(
        id: 'source:screenshot',
        label: 'Capturas',
        subtitle: 'Screenshots inteligentes',
        glyph: '📸',
        color: const Color(0xFF7C3AED),
        count: _allFiles
            .where((file) => _sourceBucket(file.sourceType) == 'screenshot')
            .length,
      ),
      _StorageFolder(
        id: 'source:email',
        label: 'Correo',
        subtitle: 'Adjuntos guardados',
        glyph: '📧',
        color: const Color(0xFF2563EB),
        count: _allFiles
            .where((file) => _sourceBucket(file.sourceType) == 'email')
            .length,
      ),
      _StorageFolder(
        id: 'source:manual',
        label: 'Manual',
        subtitle: 'Cargas manuales',
        glyph: '📤',
        color: const Color(0xFF475569),
        count: _allFiles
            .where((file) => _sourceBucket(file.sourceType) == 'manual')
            .length,
      ),
      _StorageFolder(
        id: 'source:chat',
        label: 'Chat',
        subtitle: 'Archivos de mensajes',
        glyph: '💬',
        color: const Color(0xFF059669),
        count: _allFiles
            .where((file) => _sourceBucket(file.sourceType) == 'chat')
            .length,
      ),
      _StorageFolder(
        id: 'source:expense',
        label: 'Gastos',
        subtitle: 'Comprobantes y OCR',
        glyph: '🧾',
        color: const Color(0xFFB45309),
        count: _allFiles
            .where((file) => _sourceBucket(file.sourceType) == 'expense')
            .length,
      ),
      _StorageFolder(
        id: 'type:pdf',
        label: 'PDF',
        subtitle: 'Documentos PDF',
        glyph: '📄',
        color: const Color(0xFFDC2626),
        count: _allFiles.where((file) => file.isPdf).length,
      ),
      _StorageFolder(
        id: 'type:image',
        label: 'Imágenes',
        subtitle: 'Fotos y capturas',
        glyph: '🖼️',
        color: const Color(0xFF7C3AED),
        count: _allFiles.where((file) => file.isImage).length,
      ),
    ];
  }

  String _sourceBucket(String sourceType) {
    final source = sourceType.toLowerCase();
    if (source.startsWith('email')) return 'email';
    if (source.startsWith('chat')) return 'chat';
    if (source.startsWith('expense')) return 'expense';
    if (source.startsWith('browser')) return 'browser';
    if (source.startsWith('screenshot')) return 'screenshot';
    if (source == 'manual') return 'manual';
    return source;
  }

  String? _supplierId(AppStoredFile file) {
    if (file.contextType == 'supplier' &&
        file.contextId != null &&
        file.contextId!.trim().isNotEmpty) {
      return file.contextId!.trim();
    }
    final metadataValue = file.metadata['supplier_id']?.toString().trim();
    return metadataValue == null || metadataValue.isEmpty
        ? null
        : metadataValue;
  }

  String? _supplierName(AppStoredFile file) {
    final metadataValue = file.metadata['supplier_name']?.toString().trim();
    if (metadataValue != null && metadataValue.isNotEmpty) {
      return metadataValue;
    }
    if (file.contextType == 'supplier' &&
        file.contextTitle != null &&
        file.contextTitle!.trim().isNotEmpty) {
      return file.contextTitle!.trim();
    }
    return null;
  }

  String? _supplierWebsite(AppStoredFile file) {
    final metadataValue = file.metadata['supplier_website']?.toString().trim();
    return metadataValue == null || metadataValue.isEmpty
        ? null
        : metadataValue;
  }

  Future<void> _deleteFile(AppStoredFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar archivo'),
        content: Text('Se quitará "${file.fileName}" de Archivos.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _service.deleteFile(file);
      await _loadFiles();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo eliminar: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _downloadFile(AppStoredFile file) async {
    try {
      final bytes = await _service.downloadFile(file);
      await downloadFile(
        bytes: bytes,
        fileName: file.fileName,
        mimeType: file.mimeType,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Archivo descargado.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo descargar: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _openInSpreadsheets(AppStoredFile file) async {
    if (_spreadsheetImportIds.contains(file.id)) return;
    final handoff = SpreadsheetFileHandoffService.instance;
    if (!handoff.supports(file)) return;

    setState(() => _spreadsheetImportIds.add(file.id));
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('Importando ${file.fileName} en Planillas...')),
    );

    try {
      final sheet = await handoff.importStoredFile(
        file: file,
        store: context.read<SpreadsheetService>(),
      );
      if (!mounted || sheet.id == null) return;
      messenger.hideCurrentSnackBar();

      final route = '/tools/spreadsheets/${sheet.id}';
      try {
        context.read<WorkspaceManager>().navigateActiveWorkspace(route);
      } catch (_) {
        context.go(route);
      }
      messenger.showSnackBar(
        SnackBar(content: Text('“${file.fileName}” se abrió en Planillas.')),
      );
    } catch (error, stackTrace) {
      debugPrint('Stored spreadsheet import error: $error\n$stackTrace');
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo abrir en Planillas: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _spreadsheetImportIds.remove(file.id));
      }
    }
  }

  bool _canProcessAsQuickExpense(AppStoredFile file) {
    return file.isPdf || file.isImage;
  }

  bool _canProcessAsPurchaseInvoice(AppStoredFile file) {
    return file.isPdf ||
        file.isImage ||
        const {'json', 'html', 'htm'}.contains(file.extension);
  }

  Future<void> _sendFileToOcr(
    AppStoredFile file,
    OcrFileHandoffTarget target,
  ) async {
    final isSupported = target == OcrFileHandoffTarget.quickExpense
        ? _canProcessAsQuickExpense(file)
        : _canProcessAsPurchaseInvoice(file);
    if (!isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este archivo no es compatible con OCR.')),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('Preparando OCR para ${file.fileName}...')),
    );

    try {
      final bytes = await _service.downloadFile(file);
      if (bytes.isEmpty) {
        throw Exception('El archivo está vacío.');
      }
      if (!mounted) return;

      context.read<OcrFileHandoffService>().queue(
            target: target,
            fileName: file.fileName,
            mimeType: file.mimeType,
            bytes: bytes,
            extension: file.extension,
            sourceFileId: file.id,
            sourceLabel: file.contextTitle ?? file.sourceProvider,
            sourceSupplierId: _supplierId(file),
            sourceSupplierName: _supplierName(file),
            sourceSupplierWebsite: _supplierWebsite(file),
          );

      if (target == OcrFileHandoffTarget.quickExpense) {
        context.read<RightToolbarService>().openTool(ToolbarTool.expenses);
        messenger.showSnackBar(
          const SnackBar(content: Text('Archivo enviado a Gastos Rápidos.')),
        );
      } else {
        try {
          context.read<WorkspaceManager>().navigateActiveWorkspace(
                '/purchases/new',
              );
        } catch (_) {
          context.go('/purchases/new');
        }
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Archivo enviado a factura de compra.'),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo preparar OCR: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _openOrigin(AppStoredFile file) {
    final route = file.sourceRoute;
    if (route == null || route.trim().isEmpty) return;

    try {
      context.read<WorkspaceManager>().navigateActiveWorkspace(route);
    } catch (_) {
      context.go(route);
    }
  }

  void _openFullModule() {
    try {
      context.read<WorkspaceManager>().navigateActiveWorkspace('/storage');
    } catch (_) {
      context.go('/storage');
    }
  }

  void _toggleFolderExpansion(String folderId) {
    setState(() {
      if (_expandedFolderIds.contains(folderId)) {
        _expandedFolderIds.remove(folderId);
      } else {
        _expandedFolderIds.add(folderId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedRunnerFile = _runnerFile;
    final child =
        widget.runnerMode && widget.compact && selectedRunnerFile != null
            ? _InlineStorageFileRunner(
                key: ValueKey('file-runner-${selectedRunnerFile.id}'),
                file: selectedRunnerFile,
                onBack: () => setState(() => _runnerFile = null),
                onFileChanged: _replaceRunnerFile,
                onOpenOrigin: selectedRunnerFile.sourceRoute == null
                    ? null
                    : () => _openOrigin(selectedRunnerFile),
                onOpenInSpreadsheets: SpreadsheetFileHandoffService.instance
                        .supports(selectedRunnerFile)
                    ? () => _openInSpreadsheets(selectedRunnerFile)
                    : null,
              )
            : Column(
                children: [
                  if (widget.showHeader) _buildHeader(context),
                  _buildControls(context),
                  if (_isLoading) const LinearProgressIndicator(minHeight: 2),
                  Expanded(child: _buildBody(context)),
                ],
              );

    return DropTarget(
      key: ValueKey(
        widget.compact ? 'app-files-compact' : 'app-files-desktop',
      ),
      enable: !_isUploading,
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) => _handleDroppedFiles(details.files),
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (_isDragging) _buildDropOverlay(context),
        ],
      ),
    );
  }

  void _replaceRunnerFile(AppStoredFile updatedFile) {
    if (!mounted) return;
    setState(() {
      _runnerFile = updatedFile;
      _allFiles = [
        for (final file in _allFiles)
          if (file.id == updatedFile.id) updatedFile else file,
      ];
      _files = [
        for (final file in _files)
          if (file.id == updatedFile.id) updatedFile else file,
      ];
    });
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: EdgeInsets.fromLTRB(16, widget.compact ? 12 : 18, 16, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.folder_open_outlined,
              size: 19,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Archivos',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${_files.length} visibles',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (widget.compact)
            IconButton(
              tooltip: 'Abrir módulo',
              onPressed: _openFullModule,
              icon: const Icon(Icons.open_in_full_outlined),
            ),
          IconButton(
            tooltip: 'Subir archivos',
            onPressed: _isUploading ? null : _pickFiles,
            icon: _isUploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_outlined),
          ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loadFiles,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final folders = _folders();

    return Padding(
      padding: EdgeInsets.fromLTRB(12, widget.compact ? 10 : 14, 12, 10),
      child: Column(
        children: [
          if (!widget.showHeader) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_files.length} visibles',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Abrir módulo',
                  onPressed: _openFullModule,
                  icon: const Icon(Icons.open_in_full_outlined, size: 18),
                  constraints:
                      const BoxConstraints.tightFor(width: 48, height: 48),
                ),
                IconButton(
                  tooltip: 'Subir archivos',
                  onPressed: _isUploading ? null : _pickFiles,
                  icon: _isUploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file_outlined, size: 18),
                  constraints:
                      const BoxConstraints.tightFor(width: 48, height: 48),
                ),
                IconButton(
                  tooltip: 'Actualizar',
                  onPressed: _loadFiles,
                  icon: const Icon(Icons.refresh, size: 18),
                  constraints:
                      const BoxConstraints.tightFor(width: 48, height: 48),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            height: widget.compact ? 48 : 40,
            child: TextField(
              key: const ValueKey('storage-search'),
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: 'Buscar archivo, origen o contexto',
                isDense: true,
                filled: true,
                fillColor:
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: colorScheme.outlineVariant,
                  ),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          if (widget.compact) ...[
            const SizedBox(height: 10),
            _buildCompactTabs(context),
          ],
          if (!widget.compact ||
              _compactTab == _StorageCompactTab.recent ||
              _compactTab == _StorageCompactTab.screenshots) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedFolderLabel(folders),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (widget.compact)
                  SizedBox(
                    key: const ValueKey('storage-sort'),
                    width: 48,
                    height: 48,
                    child: PopupMenuButton<_StorageSort>(
                      tooltip: 'Ordenar archivos',
                      initialValue: _sort,
                      onSelected: _setSort,
                      icon: const Icon(Icons.swap_vert_rounded, size: 20),
                      itemBuilder: (context) => [
                        for (final sort in _StorageSort.values)
                          CheckedPopupMenuItem<_StorageSort>(
                            value: sort,
                            checked: _sort == sort,
                            child: Text(sort.label),
                          ),
                      ],
                    ),
                  )
                else
                  DropdownButtonHideUnderline(
                    key: const ValueKey('storage-sort'),
                    child: DropdownButton<_StorageSort>(
                      value: _sort,
                      isDense: true,
                      borderRadius: BorderRadius.circular(8),
                      items: [
                        for (final sort in _StorageSort.values)
                          DropdownMenuItem(
                            value: sort,
                            child: Text(sort.label),
                          ),
                      ],
                      onChanged: (sort) {
                        if (sort != null) _setSort(sort);
                      },
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactTabs(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      key: const ValueKey('storage-compact-tabs'),
      height: 50,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StorageCompactTabButton(
            selected: _compactTab == _StorageCompactTab.folders,
            label: 'Carpetas',
            theme: theme,
            onTap: () => _setCompactTab(_StorageCompactTab.folders),
          ),
          _StorageCompactTabButton(
            selected: _compactTab == _StorageCompactTab.recent,
            label: 'Recientes',
            theme: theme,
            onTap: () => _setCompactTab(_StorageCompactTab.recent),
          ),
          _StorageCompactTabButton(
            selected: _compactTab == _StorageCompactTab.screenshots,
            label: 'Capturas',
            theme: theme,
            onTap: () => _setCompactTab(_StorageCompactTab.screenshots),
          ),
        ],
      ),
    );
  }

  String _selectedFolderLabel(List<_StorageFolder> folders) {
    _StorageFolder? selected;
    for (final folder in folders) {
      if (folder.id == _selectedFolderId) {
        selected = folder;
        break;
      }
    }
    final label = selected?.label ?? 'Todos';
    return '$label · ${_files.length} visibles';
  }

  Widget _buildBody(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (!widget.compact) {
      return Row(
        children: [
          SizedBox(
            key: const ValueKey('storage-desktop-folder-sidebar'),
            width: 248,
            child: _buildFolderSidebar(context, _folders()),
          ),
          VerticalDivider(
            width: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.65),
          ),
          Expanded(child: _buildFileList(context)),
        ],
      );
    }

    if (_compactTab == _StorageCompactTab.folders) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: _buildCompactFolderTree(context, _folders()),
      );
    }

    return _buildFileList(context);
  }

  Widget _buildFileList(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_error != null && _allFiles.isEmpty) {
      return _StorageEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'No se pudieron cargar los archivos',
        subtitle: _error!,
        actionLabel: 'Reintentar',
        onAction: _loadFiles,
      );
    }

    if (_files.isEmpty && !_isLoading) {
      return _StorageEmptyState(
        title: _allFiles.isEmpty ? 'Sin archivos guardados' : 'Carpeta vacía',
        subtitle: _allFiles.isEmpty
            ? 'Arrastra archivos aquí o guarda adjuntos desde el correo para encontrarlos después.'
            : 'No hay archivos que coincidan con esta carpeta o búsqueda.',
        actionLabel: _allFiles.isEmpty ? 'Subir archivos' : null,
        onAction: _allFiles.isEmpty ? _pickFiles : null,
      );
    }

    return ListView.separated(
      key: const ValueKey('storage-file-list'),
      padding: EdgeInsets.fromLTRB(12, 0, 12, widget.compact ? 12 : 20),
      itemCount: _files.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: colorScheme.outlineVariant.withValues(alpha: 0.55),
      ),
      itemBuilder: (context, index) {
        final file = _files[index];
        return _FileListTile(
          file: file,
          compact: widget.compact,
          dateLabel: _dateFormat.format(file.createdAt.toLocal()),
          onPreview: widget.runnerMode && widget.compact
              ? () => setState(() => _runnerFile = file)
              : () => StorageFilePreviewDialog.show(context, file),
          onDownload: () => _downloadFile(file),
          onDelete: () => _deleteFile(file),
          onOpenOrigin:
              file.sourceRoute == null ? null : () => _openOrigin(file),
          onQuickExpenseOcr: _canProcessAsQuickExpense(file)
              ? () => _sendFileToOcr(file, OcrFileHandoffTarget.quickExpense)
              : null,
          onPurchaseInvoiceOcr: _canProcessAsPurchaseInvoice(file)
              ? () => _sendFileToOcr(file, OcrFileHandoffTarget.purchaseInvoice)
              : null,
          onOpenInSpreadsheets:
              SpreadsheetFileHandoffService.instance.supports(file) &&
                      !_spreadsheetImportIds.contains(file.id)
                  ? () => _openInSpreadsheets(file)
                  : null,
        );
      },
    );
  }

  Widget _buildCompactFolderTree(
    BuildContext context,
    List<_StorageFolder> folders,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final visibleFolders = _visibleFolders(folders);

    return Container(
      key: const ValueKey('storage-compact-folder-tree'),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.78),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            children: [
              for (final folder in visibleFolders)
                Builder(
                  builder: (context) {
                    final expandable = _hasVisibleChildren(folder.id, folders);
                    return _StorageFolderTile(
                      folder: folder,
                      selected: _selectedFolderId == folder.id,
                      dense: true,
                      expandable: expandable,
                      expanded: _expandedFolderIds.contains(folder.id),
                      onTap: expandable
                          ? () => _toggleFolderExpansion(folder.id)
                          : () => _selectFolder(folder.id, showRecent: true),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFolderSidebar(
    BuildContext context,
    List<_StorageFolder> folders,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final visibleFolders = _visibleFolders(folders);

    return Container(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.22),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 18),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Text(
              'Carpetas inteligentes',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          for (final folder in visibleFolders)
            Builder(
              builder: (context) {
                final expandable = _hasVisibleChildren(folder.id, folders);
                return _StorageFolderTile(
                  folder: folder,
                  selected: _selectedFolderId == folder.id,
                  expandable: expandable,
                  expanded: _expandedFolderIds.contains(folder.id),
                  onTap: expandable
                      ? () => _toggleFolderExpansion(folder.id)
                      : () => _selectFolder(folder.id),
                );
              },
            ),
        ],
      ),
    );
  }

  List<_StorageFolder> _visibleFolders(List<_StorageFolder> folders) {
    return folders.where((folder) {
      final parentId = folder.parentId;
      return parentId == null ||
          (_expandedFolderIds.contains(parentId) && folder.count > 0);
    }).toList(growable: false);
  }

  bool _hasVisibleChildren(String folderId, List<_StorageFolder> folders) {
    return folders.any(
      (folder) => folder.parentId == folderId && folder.count > 0,
    );
  }

  Widget _buildDropOverlay(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Positioned.fill(
      child: IgnorePointer(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.72),
                width: 1.5,
              ),
            ),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 320),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.98),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.upload_file_outlined,
                      color: colorScheme.primary,
                      size: 30,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Soltar para guardar',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Los archivos quedarán en la biblioteca interna.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StorageFolder {
  final String id;
  final String label;
  final String subtitle;
  final String glyph;
  final Color color;
  final int count;
  final String? parentId;
  final int depth;

  const _StorageFolder({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.glyph,
    required this.color,
    required this.count,
    this.parentId,
    this.depth = 0,
  });
}

class _SupplierFolderAccumulator {
  final String id;
  final String name;
  int count = 0;

  _SupplierFolderAccumulator(this.id, this.name);
}

class _StorageCompactTabButton extends StatelessWidget {
  final bool selected;
  final String label;
  final ThemeData theme;
  final VoidCallback onTap;

  const _StorageCompactTabButton({
    required this.selected,
    required this.label,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = theme.colorScheme;
    return Expanded(
      child: Semantics(
        key: ValueKey('storage-tab-${label.toLowerCase()}'),
        button: true,
        selected: selected,
        label: label,
        child: Material(
          color: selected ? colorScheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: selected
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StorageGlyph extends StatelessWidget {
  final String glyph;
  final double size;

  const _StorageGlyph(this.glyph, {this.size = 17});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: Center(
        child: Text(
          glyph,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: size,
            height: 1,
            fontFamilyFallback: const [
              'Apple Color Emoji',
              'Noto Color Emoji',
              'Segoe UI Emoji',
            ],
          ),
        ),
      ),
    );
  }
}

class _StorageFolderTile extends StatelessWidget {
  final _StorageFolder folder;
  final bool selected;
  final bool dense;
  final bool expandable;
  final bool expanded;
  final VoidCallback onTap;

  const _StorageFolderTile({
    required this.folder,
    required this.selected,
    this.dense = false,
    this.expandable = false,
    this.expanded = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = folder.color;
    final textColor = selected ? accent : colorScheme.onSurface;
    final isChild = folder.depth > 0;

    return Padding(
      padding: EdgeInsets.only(
        left: isChild ? (dense ? 12 : 16) : 0,
        bottom: dense ? 2 : 3,
      ),
      child: Material(
        color: selected ? accent.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: ValueKey('storage-folder-${folder.id}'),
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: dense ? 7 : 9,
              vertical: dense ? 6 : 8,
            ),
            child: Row(
              children: [
                if (dense) const SizedBox(width: 0, height: 36),
                if (isChild) ...[
                  SizedBox(
                    width: 17,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 10,
                        height: 1.4,
                        decoration: BoxDecoration(
                          color: selected
                              ? accent.withValues(alpha: 0.7)
                              : colorScheme.outline.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                ],
                _StorageGlyph(folder.glyph, size: dense ? 18 : 19),
                SizedBox(width: dense ? 7 : 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        folder.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: textColor,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w700,
                          height: dense ? 1.05 : null,
                        ),
                      ),
                      if (!dense || !isChild)
                        Text(
                          folder.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: dense ? 1.1 : null,
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(width: dense ? 6 : 8),
                if (expandable) ...[
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: dense ? 16 : 18,
                    color: selected ? accent : colorScheme.onSurfaceVariant,
                  ),
                  SizedBox(width: dense ? 3 : 4),
                ],
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: dense ? 5 : 6,
                    vertical: dense ? 1 : 2,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? accent.withValues(alpha: 0.14)
                        : colorScheme.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: selected
                          ? accent.withValues(alpha: 0.35)
                          : colorScheme.outlineVariant,
                    ),
                  ),
                  child: Text(
                    '${folder.count}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: selected ? accent : colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FileListTile extends StatelessWidget {
  final AppStoredFile file;
  final bool compact;
  final String dateLabel;
  final VoidCallback onPreview;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final VoidCallback? onOpenOrigin;
  final VoidCallback? onQuickExpenseOcr;
  final VoidCallback? onPurchaseInvoiceOcr;
  final VoidCallback? onOpenInSpreadsheets;

  const _FileListTile({
    required this.file,
    required this.compact,
    required this.dateLabel,
    required this.onPreview,
    required this.onDownload,
    required this.onDelete,
    required this.onOpenOrigin,
    required this.onQuickExpenseOcr,
    required this.onPurchaseInvoiceOcr,
    required this.onOpenInSpreadsheets,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPreview,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 4 : 6,
            vertical: compact ? 10 : 12,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: compact ? 36 : 42,
                height: compact ? 36 : 42,
                decoration: BoxDecoration(
                  color: _sourceColor(file).withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _fileIcon(file),
                  size: compact ? 19 : 22,
                  color: _sourceColor(file),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _SourceChip(file: file),
                        if (_fileSupplierName(file) != null)
                          _SupplierChip(label: _fileSupplierName(file)!),
                        Text(
                          '${file.displaySize} · $dateLabel',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _contextLine(file),
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (!compact && onOpenInSpreadsheets != null)
                IconButton(
                  tooltip: 'Abrir en Planillas',
                  onPressed: onOpenInSpreadsheets,
                  icon: const Icon(Icons.table_view_outlined, size: 18),
                ),
              if (!compact && onOpenOrigin != null)
                IconButton(
                  tooltip: 'Abrir origen',
                  onPressed: onOpenOrigin,
                  icon: const Icon(Icons.open_in_new, size: 18),
                ),
              IconButton(
                key: ValueKey('storage-preview-${file.id}'),
                tooltip: 'Vista previa',
                onPressed: onPreview,
                icon: const Icon(Icons.visibility_outlined, size: 18),
                constraints: compact
                    ? const BoxConstraints.tightFor(width: 48, height: 48)
                    : null,
              ),
              if (!compact)
                IconButton(
                  tooltip: 'Descargar',
                  onPressed: onDownload,
                  icon: const Icon(Icons.download_outlined, size: 18),
                ),
              PopupMenuButton<String>(
                key: ValueKey('storage-more-${file.id}'),
                tooltip: 'Más acciones',
                onSelected: (value) {
                  if (value == 'quick_expense_ocr') onQuickExpenseOcr?.call();
                  if (value == 'purchase_invoice_ocr') {
                    onPurchaseInvoiceOcr?.call();
                  }
                  if (value == 'open_in_spreadsheets') {
                    onOpenInSpreadsheets?.call();
                  }
                  if (value == 'download') onDownload();
                  if (value == 'origin') onOpenOrigin?.call();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (context) => [
                  if (onOpenInSpreadsheets != null)
                    const PopupMenuItem(
                      value: 'open_in_spreadsheets',
                      child: _FileActionMenuItem(
                        icon: Icons.table_view_outlined,
                        label: 'Abrir en Planillas',
                      ),
                    ),
                  if (onOpenInSpreadsheets != null) const PopupMenuDivider(),
                  if (file.extension == 'xls')
                    const PopupMenuItem(
                      enabled: false,
                      child: _FileActionMenuItem(
                        icon: Icons.info_outline,
                        label: 'XLS: convierte a XLSX',
                      ),
                    ),
                  if (file.extension == 'xls') const PopupMenuDivider(),
                  if (onQuickExpenseOcr != null)
                    const PopupMenuItem(
                      value: 'quick_expense_ocr',
                      child: _FileActionMenuItem(
                        icon: Icons.receipt_long_outlined,
                        label: 'OCR como gasto',
                      ),
                    ),
                  if (onPurchaseInvoiceOcr != null)
                    const PopupMenuItem(
                      value: 'purchase_invoice_ocr',
                      child: _FileActionMenuItem(
                        icon: Icons.document_scanner_outlined,
                        label: 'OCR factura compra',
                      ),
                    ),
                  if (onQuickExpenseOcr != null || onPurchaseInvoiceOcr != null)
                    const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'download',
                    child: _FileActionMenuItem(
                      icon: Icons.download_outlined,
                      label: 'Descargar',
                    ),
                  ),
                  if (onOpenOrigin != null)
                    const PopupMenuItem(
                      value: 'origin',
                      child: _FileActionMenuItem(
                        icon: Icons.open_in_new_outlined,
                        label: 'Abrir origen',
                      ),
                    ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'delete',
                    child: _FileActionMenuItem(
                      icon: Icons.delete_outline,
                      label: 'Eliminar',
                    ),
                  ),
                ],
                icon: const Icon(Icons.more_vert, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _contextLine(AppStoredFile file) {
    final title = file.contextTitle?.trim();
    final subtitle = file.contextSubtitle?.trim();
    if (title != null &&
        title.isNotEmpty &&
        subtitle != null &&
        subtitle.isNotEmpty) {
      return '$title · $subtitle';
    }
    if (title != null && title.isNotEmpty) return title;
    if (subtitle != null && subtitle.isNotEmpty) return subtitle;
    return 'Sin contexto asociado';
  }
}

class _SourceChip extends StatelessWidget {
  final AppStoredFile file;

  const _SourceChip({required this.file});

  @override
  Widget build(BuildContext context) {
    final color = _sourceColor(file);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        _sourceLabel(file.sourceType),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
      ),
    );
  }
}

class _SupplierChip extends StatelessWidget {
  final String label;

  const _SupplierChip({required this.label});

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF4F46E5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.storefront_outlined, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
          ),
        ],
      ),
    );
  }
}

class _FileActionMenuItem extends StatelessWidget {
  const _FileActionMenuItem({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}

class _InlineStorageFileRunner extends StatefulWidget {
  const _InlineStorageFileRunner({
    super.key,
    required this.file,
    required this.onBack,
    required this.onFileChanged,
    required this.onOpenOrigin,
    required this.onOpenInSpreadsheets,
  });

  final AppStoredFile file;
  final VoidCallback onBack;
  final ValueChanged<AppStoredFile> onFileChanged;
  final VoidCallback? onOpenOrigin;
  final VoidCallback? onOpenInSpreadsheets;

  @override
  State<_InlineStorageFileRunner> createState() =>
      _InlineStorageFileRunnerState();
}

class _InlineStorageFileRunnerState extends State<_InlineStorageFileRunner> {
  final StoredSpreadsheetRunnerController _spreadsheetController =
      StoredSpreadsheetRunnerController();
  late AppStoredFile _file;
  late Future<Uint8List> _bytesFuture;
  TextEditingController? _textController;
  String _savedText = '';
  bool _textDirty = false;
  bool _isSavingText = false;
  double _pdfZoom = 1;

  bool get _isSpreadsheet =>
      SpreadsheetFileHandoffService.instance.supports(_file);

  @override
  void initState() {
    super.initState();
    _file = widget.file;
    _bytesFuture = _loadBytes();
  }

  @override
  void dispose() {
    _disposeTextController();
    super.dispose();
  }

  Future<Uint8List> _loadBytes() {
    return AppFileStorageService.instance.downloadFile(_file);
  }

  void _reload() {
    _disposeTextController();
    setState(() {
      _pdfZoom = 1;
      _bytesFuture = _loadBytes();
    });
  }

  void _disposeTextController() {
    _textController?.removeListener(_onTextChanged);
    _textController?.dispose();
    _textController = null;
    _savedText = '';
    _textDirty = false;
  }

  TextEditingController _textControllerFor(Uint8List bytes) {
    final existing = _textController;
    if (existing != null) return existing;

    _savedText = utf8.decode(bytes, allowMalformed: true);
    final controller = TextEditingController(text: _savedText);
    controller.addListener(_onTextChanged);
    _textController = controller;
    return controller;
  }

  void _onTextChanged() {
    final dirty = _textController?.text != _savedText;
    if (dirty != _textDirty && mounted) {
      setState(() => _textDirty = dirty);
    }
  }

  Future<void> _download(Uint8List bytes) async {
    await downloadFile(
      bytes: bytes,
      fileName: _file.fileName,
      mimeType: _file.mimeType,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Archivo descargado.')),
    );
  }

  Future<void> _editImage(Uint8List bytes) async {
    final updatedFile = await StorageImageCropDialog.show(
      context,
      file: _file,
      bytes: bytes,
    );
    if (updatedFile == null || !mounted) return;

    _file = updatedFile;
    widget.onFileChanged(updatedFile);
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Imagen recortada y reemplazada.')),
    );
  }

  Future<void> _saveText() async {
    final controller = _textController;
    if (controller == null || !_textDirty || _isSavingText) return;

    setState(() => _isSavingText = true);
    try {
      final bytes = Uint8List.fromList(utf8.encode(controller.text));
      final updatedFile = await AppFileStorageService.instance.replaceFileBytes(
        file: _file,
        bytes: bytes,
        mimeType: _file.mimeType,
        addTags: const ['editado'],
        metadataPatch: {
          'last_edited_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
      if (!mounted) return;

      _file = updatedFile;
      _savedText = controller.text;
      _textDirty = false;
      widget.onFileChanged(updatedFile);
      setState(() => _bytesFuture = Future.value(bytes));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Archivo de texto guardado.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSavingText = false);
    }
  }

  Future<void> _handleBack() async {
    if (_isSpreadsheet) {
      final saved = await _spreadsheetController.save();
      if (!saved || !mounted) return;
    } else if (_textDirty) {
      await _saveText();
      if (!mounted || _textDirty) return;
    }
    widget.onBack();
  }

  void _changePdfZoom(double delta) {
    setState(() => _pdfZoom = (_pdfZoom + delta).clamp(0.5, 3));
  }

  Future<void> _printPdf(Uint8List bytes) async {
    try {
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: _file.fileName,
        dynamicLayout: false,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo imprimir: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return FutureBuilder<Uint8List>(
      future: _bytesFuture,
      builder: (context, snapshot) {
        final bytes = snapshot.data;

        return Column(
          children: [
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Volver a archivos',
                    onPressed: _handleBack,
                    icon: const Icon(Icons.arrow_back, size: 19),
                  ),
                  Icon(
                    _fileIcon(_file),
                    size: 19,
                    color: _sourceColor(_file),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _file.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          _textDirty
                              ? 'Cambios sin guardar'
                              : '${_sourceLabel(_file.sourceType)} · ${_file.displaySize}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: _textDirty
                                ? colorScheme.error
                                : colorScheme.onSurfaceVariant,
                            fontWeight: _textDirty ? FontWeight.w700 : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_file.isTextLike && _textDirty)
                    IconButton(
                      tooltip: 'Guardar cambios',
                      onPressed: _isSavingText ? null : _saveText,
                      icon: _isSavingText
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined, size: 19),
                    ),
                  if (_file.isImage)
                    IconButton(
                      tooltip: 'Recortar imagen',
                      onPressed: bytes == null ? null : () => _editImage(bytes),
                      icon: const Icon(Icons.crop_outlined, size: 19),
                    ),
                  PopupMenuButton<String>(
                    tooltip: 'Acciones del archivo',
                    onSelected: (value) {
                      if (value == 'retry') _reload();
                      if (value == 'download' && bytes != null) {
                        _download(bytes);
                      }
                      if (value == 'origin') widget.onOpenOrigin?.call();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'retry',
                        child: _FileActionMenuItem(
                          icon: Icons.refresh,
                          label: 'Volver a cargar',
                        ),
                      ),
                      PopupMenuItem(
                        value: 'download',
                        enabled: bytes != null,
                        child: const _FileActionMenuItem(
                          icon: Icons.download_outlined,
                          label: 'Descargar',
                        ),
                      ),
                      if (widget.onOpenOrigin != null)
                        const PopupMenuItem(
                          value: 'origin',
                          child: _FileActionMenuItem(
                            icon: Icons.open_in_new_outlined,
                            label: 'Abrir origen',
                          ),
                        ),
                    ],
                    icon: const Icon(Icons.more_vert, size: 19),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildPreview(snapshot)),
          ],
        );
      },
    );
  }

  Widget _buildPreview(AsyncSnapshot<Uint8List> snapshot) {
    final theme = Theme.of(context);

    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (snapshot.hasError || snapshot.data == null) {
      return _StorageEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'No se pudo cargar el archivo',
        subtitle: snapshot.error?.toString() ?? 'Intenta nuevamente.',
        actionLabel: 'Reintentar',
        onAction: _reload,
      );
    }

    final bytes = snapshot.data!;
    if (_isSpreadsheet) {
      return StoredSpreadsheetRunner(
        key: ValueKey<String>('stored-spreadsheet-runner-${_file.id}'),
        file: _file,
        bytes: bytes,
        controller: _spreadsheetController,
        onFileChanged: (updatedFile) {
          _file = updatedFile;
          widget.onFileChanged(updatedFile);
        },
        onOpenFullEditor: widget.onOpenInSpreadsheets,
      );
    }

    if (_file.isImage) {
      return ColoredBox(
        color: const Color(0xFF0F172A),
        child: InteractiveViewer(
          minScale: 0.6,
          maxScale: 5,
          child: Center(
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const _StorageEmptyState(
                icon: Icons.broken_image_outlined,
                title: 'Imagen no compatible',
                subtitle: 'Usa Descargar desde el menú del archivo.',
              ),
            ),
          ),
        ),
      );
    }

    if (_file.isPdf) {
      return _buildPdfPreview(bytes);
    }

    if (_file.isTextLike) {
      return ColoredBox(
        color: theme.colorScheme.surface,
        child: TextField(
          controller: _textControllerFor(bytes),
          expands: true,
          minLines: null,
          maxLines: null,
          textAlignVertical: TextAlignVertical.top,
          keyboardType: TextInputType.multiline,
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            height: 1.45,
          ),
          decoration: const InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.all(14),
          ),
        ),
      );
    }

    return _StorageEmptyState(
      icon: _fileIcon(_file),
      title: 'Archivo disponible',
      subtitle:
          'Este formato no tiene visor interno. Puedes descargarlo o abrir su módulo de origen.',
      actionLabel: 'Descargar',
      onAction: () => _download(bytes),
    );
  }

  Widget _buildPdfPreview(Uint8List bytes) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Alejar',
                onPressed: _pdfZoom <= 0.5 ? null : () => _changePdfZoom(-0.25),
                icon: const Icon(Icons.remove, size: 18),
              ),
              TextButton(
                onPressed: () => setState(() => _pdfZoom = 1),
                child: Text('${(_pdfZoom * 100).round()}%'),
              ),
              IconButton(
                tooltip: 'Acercar',
                onPressed: _pdfZoom >= 3 ? null : () => _changePdfZoom(0.25),
                icon: const Icon(Icons.add, size: 18),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Imprimir PDF',
                onPressed: () => _printPdf(bytes),
                icon: const Icon(Icons.print_outlined, size: 18),
              ),
              IconButton(
                tooltip: 'Descargar PDF',
                onPressed: () => _download(bytes),
                icon: const Icon(Icons.download_outlined, size: 18),
              ),
              IconButton(
                tooltip: 'Volver a cargar',
                onPressed: _reload,
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ],
          ),
        ),
        Expanded(
          child: PdfPreview.builder(
            build: (PdfPageFormat _) async => bytes,
            useActions: false,
            allowPrinting: false,
            allowSharing: false,
            canChangeOrientation: false,
            canChangePageFormat: false,
            canDebug: false,
            dynamicLayout: false,
            pdfFileName: _file.fileName,
            loadingWidget: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            pagesBuilder: (context, pages) => _RunnerPdfPagesCanvas(
              pages: pages,
              zoom: _pdfZoom,
            ),
          ),
        ),
      ],
    );
  }
}

class _RunnerPdfPagesCanvas extends StatelessWidget {
  const _RunnerPdfPagesCanvas({
    required this.pages,
    required this.zoom,
  });

  final List<PdfPreviewPageData> pages;
  final double zoom;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final baseWidth = math.max(260.0, constraints.maxWidth - 32);
        final pageWidth = baseWidth * zoom;
        final canvasWidth = math.max(constraints.maxWidth, pageWidth + 32);
        return ColoredBox(
          color: const Color(0xFFE5E7EB),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: canvasWidth,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
                itemCount: pages.length,
                itemBuilder: (context, index) {
                  final page = pages[index];
                  final pageHeight = pageWidth / page.aspectRatio;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Página ${index + 1} de ${pages.length}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: pageWidth,
                        height: pageHeight,
                        margin: EdgeInsets.only(
                          bottom: index == pages.length - 1 ? 18 : 14,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Image(
                          image: page.image,
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class StorageFilePreviewDialog extends StatefulWidget {
  final AppStoredFile file;

  const StorageFilePreviewDialog({super.key, required this.file});

  static Future<void> show(BuildContext context, AppStoredFile file) {
    return showDialog<void>(
      context: context,
      builder: (_) => StorageFilePreviewDialog(file: file),
    );
  }

  @override
  State<StorageFilePreviewDialog> createState() =>
      _StorageFilePreviewDialogState();
}

class _StorageFilePreviewDialogState extends State<StorageFilePreviewDialog> {
  late Future<Uint8List> _bytesFuture;
  late AppStoredFile _file;

  @override
  void initState() {
    super.initState();
    _file = widget.file;
    _bytesFuture = _loadBytes();
  }

  Future<Uint8List> _loadBytes() {
    return AppFileStorageService.instance.downloadFile(_file);
  }

  Future<void> _download(Uint8List bytes) async {
    await downloadFile(
      bytes: bytes,
      fileName: _file.fileName,
      mimeType: _file.mimeType,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Archivo descargado.')),
    );
  }

  Future<void> _editImage(Uint8List bytes) async {
    final updatedFile = await StorageImageCropDialog.show(
      context,
      file: _file,
      bytes: bytes,
    );
    if (updatedFile == null || !mounted) return;

    setState(() {
      _file = updatedFile;
      _bytesFuture = _loadBytes();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Captura recortada y reemplazada.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final horizontalInset = screenSize.width < 760 ? 12.0 : 42.0;
    final verticalInset = screenSize.height < 720 ? 12.0 : 24.0;
    final dialogWidth = (screenSize.width - horizontalInset * 2).clamp(
      320.0,
      1180.0,
    );

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: verticalInset,
      ),
      backgroundColor: Colors.transparent,
      child: SizedBox(
        width: dialogWidth,
        height: screenSize.height - verticalInset * 2,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            child: FutureBuilder<Uint8List>(
              future: _bytesFuture,
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                return Column(
                  children: [
                    _StoragePreviewHeader(
                      file: _file,
                      isLoading:
                          snapshot.connectionState == ConnectionState.waiting,
                      onRetry: () {
                        setState(() => _bytesFuture = _loadBytes());
                      },
                      onEditImage: bytes == null || !_file.isImage
                          ? null
                          : () => _editImage(bytes),
                      onDownload: bytes == null ? null : () => _download(bytes),
                      onClose: () => Navigator.of(context).maybePop(),
                    ),
                    const Divider(height: 1),
                    Expanded(child: _buildPreview(snapshot)),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(AsyncSnapshot<Uint8List> snapshot) {
    final theme = Theme.of(context);

    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (snapshot.hasError || snapshot.data == null) {
      return _StorageEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'No se pudo cargar el archivo',
        subtitle: snapshot.error?.toString() ?? 'Intenta nuevamente.',
        actionLabel: 'Reintentar',
        onAction: () => setState(() => _bytesFuture = _loadBytes()),
      );
    }

    final bytes = snapshot.data!;
    final file = _file;

    if (file.isImage) {
      return ColoredBox(
        color: const Color(0xFF0F172A),
        child: InteractiveViewer(
          minScale: 0.6,
          maxScale: 5,
          child: Center(
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const _StorageEmptyState(
                icon: Icons.broken_image_outlined,
                title: 'Imagen no compatible',
                subtitle:
                    'Puedes descargar el archivo desde el botón superior.',
              ),
            ),
          ),
        ),
      );
    }

    if (file.isPdf) {
      return PdfPreview(
        build: (PdfPageFormat _) async => bytes,
        useActions: false,
        allowPrinting: false,
        allowSharing: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        pdfFileName: file.fileName,
        scrollViewDecoration: const BoxDecoration(color: Color(0xFFE5E7EB)),
      );
    }

    if (file.isTextLike) {
      final text = utf8.decode(bytes, allowMalformed: true);
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: const Color(0xFFF8FAFC),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: SelectableText(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
              height: 1.45,
              color: const Color(0xFF0F172A),
            ),
          ),
        ),
      );
    }

    return _StorageEmptyState(
      icon: _fileIcon(file),
      title: 'Vista previa no disponible',
      subtitle: '${file.fileName} está listo para descargar.',
      actionLabel: 'Descargar',
      onAction: () => _download(bytes),
    );
  }
}

class _StoragePreviewHeader extends StatelessWidget {
  final AppStoredFile file;
  final bool isLoading;
  final VoidCallback onRetry;
  final VoidCallback? onEditImage;
  final VoidCallback? onDownload;
  final VoidCallback onClose;

  const _StoragePreviewHeader({
    required this.file,
    required this.isLoading,
    required this.onRetry,
    required this.onEditImage,
    required this.onDownload,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: colorScheme.surface,
      child: Row(
        children: [
          Icon(_fileIcon(file), size: 22, color: _sourceColor(file)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${_sourceLabel(file.sourceType)} · ${file.displaySize}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (isLoading)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              tooltip: 'Reintentar',
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
            ),
          if (file.isImage)
            IconButton(
              tooltip: 'Recortar',
              onPressed: onEditImage,
              icon: const Icon(Icons.crop_outlined),
            ),
          IconButton(
            tooltip: 'Descargar',
            onPressed: onDownload,
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _StorageEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _StorageEmptyState({
    this.icon = Icons.folder_open_outlined,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (onAction != null && actionLabel != null) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _UploadPayload {
  final String fileName;
  final Uint8List bytes;
  final String? mimeType;

  const _UploadPayload({
    required this.fileName,
    required this.bytes,
    required this.mimeType,
  });
}

IconData _fileIcon(AppStoredFile file) {
  if (file.sourceType.startsWith('screenshot')) {
    return Icons.screenshot_monitor_outlined;
  }
  if (file.isPdf) return Icons.picture_as_pdf_outlined;
  if (file.isImage) return Icons.image_outlined;
  switch (file.extension) {
    case 'doc':
    case 'docx':
      return Icons.description_outlined;
    case 'xls':
    case 'xlsx':
    case 'csv':
      return Icons.table_chart_outlined;
    case 'zip':
    case 'rar':
    case '7z':
      return Icons.folder_zip_outlined;
    case 'mp4':
    case 'mov':
      return Icons.movie_outlined;
    case 'mp3':
    case 'ogg':
    case 'wav':
      return Icons.audio_file_outlined;
    default:
      return Icons.insert_drive_file_outlined;
  }
}

String _sourceLabel(String sourceType) {
  if (sourceType.startsWith('email')) return 'Correo';
  if (sourceType.startsWith('chat')) return 'Chat';
  if (sourceType.startsWith('expense')) return 'Gastos';
  if (sourceType.startsWith('browser')) return 'Navegador';
  if (sourceType.startsWith('screenshot')) return 'Captura';
  if (sourceType == 'manual') return 'Manual';
  return 'Archivo';
}

String? _fileSupplierName(AppStoredFile file) {
  final metadataValue = file.metadata['supplier_name']?.toString().trim();
  if (metadataValue != null && metadataValue.isNotEmpty) return metadataValue;
  if (file.contextType == 'supplier' &&
      file.contextTitle != null &&
      file.contextTitle!.trim().isNotEmpty) {
    return file.contextTitle!.trim();
  }
  return null;
}

Color _sourceColor(AppStoredFile file) {
  final sourceType = file.sourceType;
  if (sourceType.startsWith('email')) return const Color(0xFF2563EB);
  if (sourceType.startsWith('chat')) return const Color(0xFF059669);
  if (sourceType.startsWith('expense')) return const Color(0xFFB45309);
  if (sourceType.startsWith('browser')) return const Color(0xFF0F766E);
  if (sourceType.startsWith('screenshot')) return const Color(0xFF7C3AED);
  if (sourceType == 'manual') return const Color(0xFF475569);
  return const Color(0xFF64748B);
}
