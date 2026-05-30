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

enum AppFilesFilter {
  all('all', 'Todos'),
  email('email', 'Correo'),
  manual('manual', 'Manual'),
  chat('chat', 'Chat'),
  expense('expense', 'Gastos');

  const AppFilesFilter(this.value, this.label);

  final String value;
  final String label;
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

  List<AppStoredFile> _files = const [];
  AppFilesFilter _filter = AppFilesFilter.all;
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
      final files = await _service.listFiles(
        query: _query,
        sourceType: _filter.value,
        limit: widget.compact ? 80 : 180,
      );
      if (!mounted) return;
      setState(() => _files = files);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Wrap(
                spacing: 6,
                children: [
                  for (final filter in AppFilesFilter.values)
                    ChoiceChip(
                      label: Text(filter.label),
                      selected: _filter == filter,
                      onSelected: (_) {
                        setState(() => _filter = filter);
                        _loadFiles();
                      },
                      labelStyle: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_error != null && _files.isEmpty) {
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
        icon: Icons.folder_open_outlined,
        title: 'Sin archivos guardados',
        subtitle:
            'Arrastra archivos aquí o guarda adjuntos desde el correo para encontrarlos después.',
        actionLabel: 'Subir archivos',
        onAction: _pickFiles,
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
    required this.icon,
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
  if (sourceType == 'manual') return 'Manual';
  return 'Archivo';
}

Color _sourceColor(AppStoredFile file) {
  final sourceType = file.sourceType;
  if (sourceType.startsWith('email')) return const Color(0xFF2563EB);
  if (sourceType.startsWith('chat')) return const Color(0xFF059669);
  if (sourceType.startsWith('expense')) return const Color(0xFFB45309);
  if (sourceType == 'manual') return const Color(0xFF475569);
  return const Color(0xFF64748B);
}
