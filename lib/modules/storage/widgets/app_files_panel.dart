import 'dart:async';
import 'dart:convert';
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
import '../../../shared/utils/file_download.dart';
import '../models/app_stored_file.dart';
import '../services/app_file_storage_service.dart';

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
}

class AppFilesPanel extends StatefulWidget {
  final bool compact;
  final bool showHeader;

  const AppFilesPanel({
    super.key,
    this.compact = false,
    this.showHeader = true,
  });

  @override
  State<AppFilesPanel> createState() => _AppFilesPanelState();
}

class _AppFilesPanelState extends State<AppFilesPanel> {
  final _service = AppFileStorageService.instance;
  final _searchController = TextEditingController();
  final _dateFormat = DateFormat('dd/MM HH:mm');

  List<AppStoredFile> _allFiles = const [];
  List<AppStoredFile> _files = const [];
  String _selectedFolderId = 'all';
  final Set<String> _expandedFolderIds = <String>{};
  _StorageSort _sort = _StorageSort.newest;
  _StorageCompactTab _compactTab = _StorageCompactTab.recent;
  Timer? _searchDebounce;
  String _query = '';
  String? _error;
  bool _isLoading = true;
  bool _isUploading = false;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadFiles();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
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
      var files = await _service.listFiles(
        query: _query,
        limit: widget.compact ? 120 : 360,
      );
      files = await _autoTagSupplierDownloads(files);
      if (!mounted) return;
      setState(() {
        _allFiles = files;
        _applyCurrentView();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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

  void _applyCurrentView() {
    final files = _allFiles.where(_matchesSelectedFolder).toList();
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
    final child = Column(
      children: [
        if (widget.showHeader) _buildHeader(context),
        _buildControls(context),
        if (_isLoading) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: _buildBody(context)),
      ],
    );

    return DropTarget(
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
                  visualDensity: VisualDensity.compact,
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
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: 'Actualizar',
                  onPressed: _loadFiles,
                  icon: const Icon(Icons.refresh, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            height: 40,
            child: TextField(
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
          if (!widget.compact || _compactTab == _StorageCompactTab.recent) ...[
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
                DropdownButtonHideUnderline(
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
      height: 34,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          _StorageCompactTabButton(
            selected: _compactTab == _StorageCompactTab.folders,
            glyph: '🗂️',
            label: 'Carpetas',
            theme: theme,
            onTap: () =>
                setState(() => _compactTab = _StorageCompactTab.folders),
          ),
          _StorageCompactTabButton(
            selected: _compactTab == _StorageCompactTab.recent,
            glyph: '🕘',
            label: 'Recientes',
            theme: theme,
            onTap: () =>
                setState(() => _compactTab = _StorageCompactTab.recent),
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
          onPreview: () => StorageFilePreviewDialog.show(context, file),
          onDownload: () => _downloadFile(file),
          onDelete: () => _deleteFile(file),
          onOpenOrigin:
              file.sourceRoute == null ? null : () => _openOrigin(file),
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
  final String glyph;
  final String label;
  final ThemeData theme;
  final VoidCallback onTap;

  const _StorageCompactTabButton({
    required this.selected,
    required this.glyph,
    required this.label,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = theme.colorScheme;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Material(
          color: selected ? colorScheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StorageGlyph(glyph, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: selected
                          ? colorScheme.onSurface
                          : colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
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
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: dense ? 7 : 9,
              vertical: dense ? 6 : 8,
            ),
            child: Row(
              children: [
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

  const _FileListTile({
    required this.file,
    required this.compact,
    required this.dateLabel,
    required this.onPreview,
    required this.onDownload,
    required this.onDelete,
    required this.onOpenOrigin,
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
              if (!compact && onOpenOrigin != null)
                IconButton(
                  tooltip: 'Abrir origen',
                  onPressed: onOpenOrigin,
                  icon: const Icon(Icons.open_in_new, size: 18),
                ),
              IconButton(
                tooltip: 'Vista previa',
                onPressed: onPreview,
                icon: const Icon(Icons.visibility_outlined, size: 18),
              ),
              if (!compact)
                IconButton(
                  tooltip: 'Descargar',
                  onPressed: onDownload,
                  icon: const Icon(Icons.download_outlined, size: 18),
                ),
              PopupMenuButton<String>(
                tooltip: 'Más acciones',
                onSelected: (value) {
                  if (value == 'download') onDownload();
                  if (value == 'origin') onOpenOrigin?.call();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'download',
                    child: Text('Descargar'),
                  ),
                  if (onOpenOrigin != null)
                    const PopupMenuItem(
                      value: 'origin',
                      child: Text('Abrir origen'),
                    ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Eliminar'),
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

  @override
  void initState() {
    super.initState();
    _bytesFuture = _loadBytes();
  }

  Future<Uint8List> _loadBytes() {
    return AppFileStorageService.instance.downloadFile(widget.file);
  }

  Future<void> _download(Uint8List bytes) async {
    await downloadFile(
      bytes: bytes,
      fileName: widget.file.fileName,
      mimeType: widget.file.mimeType,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Archivo descargado.')),
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
                      file: widget.file,
                      isLoading:
                          snapshot.connectionState == ConnectionState.waiting,
                      onRetry: () {
                        setState(() => _bytesFuture = _loadBytes());
                      },
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
    final file = widget.file;

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
  final VoidCallback? onDownload;
  final VoidCallback onClose;

  const _StoragePreviewHeader({
    required this.file,
    required this.isLoading,
    required this.onRetry,
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
  if (sourceType == 'manual') return const Color(0xFF475569);
  return const Color(0xFF64748B);
}
