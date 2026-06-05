import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../storage/models/app_stored_file.dart';
import '../../storage/services/app_file_storage_service.dart';
import '../../../shared/utils/file_download.dart';

class ChatAttachmentViewer extends StatefulWidget {
  final String url;
  final String fileName;
  final String extension;
  final String contentType;
  final bool isImage;
  final AppFileContext? fileContext;

  const ChatAttachmentViewer({
    super.key,
    required this.url,
    required this.fileName,
    required this.extension,
    required this.contentType,
    required this.isImage,
    this.fileContext,
  });

  static Future<void> show(
    BuildContext context, {
    required String url,
    required String fileName,
    required String extension,
    required String contentType,
    required bool isImage,
    AppFileContext? fileContext,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => ChatAttachmentViewer(
        url: url,
        fileName: fileName,
        extension: extension,
        contentType: contentType,
        isImage: isImage,
        fileContext: fileContext,
      ),
    );
  }

  @override
  State<ChatAttachmentViewer> createState() => _ChatAttachmentViewerState();
}

class _ChatAttachmentViewerState extends State<ChatAttachmentViewer> {
  static const double _minZoom = 0.55;
  static const double _maxZoom = 3.0;
  static const double _zoomStep = 0.15;

  late Future<_AttachmentPayload> _payloadFuture;
  final TransformationController _imageTransformController =
      TransformationController();
  Uint8List? _activePdfBytes;
  double _previewZoom = 1.0;
  bool _isPrinting = false;

  String get _normalizedExtension =>
      widget.extension.trim().toLowerCase().replaceAll('.', '');

  bool get _isPdf =>
      _normalizedExtension == 'pdf' ||
      widget.contentType.toLowerCase().contains('application/pdf');

  bool get _isTextPreview {
    const textExtensions = {'txt', 'csv', 'json', 'log', 'xml'};
    return textExtensions.contains(_normalizedExtension) ||
        widget.contentType.toLowerCase().startsWith('text/');
  }

  @override
  void initState() {
    super.initState();
    _payloadFuture = _loadPayload();
  }

  @override
  void dispose() {
    _imageTransformController.dispose();
    super.dispose();
  }

  Future<_AttachmentPayload> _loadPayload() async {
    if (widget.url.startsWith('data:')) {
      return _decodeDataUrl(widget.url);
    }

    final uri = Uri.tryParse(widget.url);
    if (uri == null || !uri.hasScheme) {
      throw const FormatException('URL inválida');
    }

    final response = await http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final contentType = response.headers['content-type'] ??
        (widget.contentType.isNotEmpty
            ? widget.contentType
            : _fallbackMimeType(_normalizedExtension));

    return _AttachmentPayload(
      bytes: response.bodyBytes,
      contentType: contentType,
    );
  }

  _AttachmentPayload _decodeDataUrl(String dataUrl) {
    final comma = dataUrl.indexOf(',');
    if (comma == -1) {
      throw const FormatException('Data URL inválida');
    }

    final header = dataUrl.substring(5, comma);
    final body = dataUrl.substring(comma + 1);
    final contentType = header.split(';').first;
    final bytes = header.contains(';base64')
        ? base64Decode(body)
        : Uint8List.fromList(utf8.encode(Uri.decodeComponent(body)));

    return _AttachmentPayload(
      bytes: bytes,
      contentType: contentType.isNotEmpty
          ? contentType
          : _fallbackMimeType(_normalizedExtension),
    );
  }

  Future<void> _download(_AttachmentPayload payload) async {
    final safeName = _safeFileName(widget.fileName);
    var savedInFiles = false;
    var downloadedLocalCopy = false;
    Object? internalSaveError;
    Object? localDownloadError;

    if (widget.fileContext != null) {
      try {
        await AppFileStorageService.instance.saveFile(
          bytes: payload.bytes,
          fileName: safeName,
          mimeType: payload.contentType,
          context: widget.fileContext!,
        );
        savedInFiles = true;
      } catch (error) {
        internalSaveError = error;
        debugPrint('💬 Chat attachment file-module save skipped: $error');
      }
    }

    try {
      await downloadFile(
        bytes: payload.bytes,
        fileName: safeName,
        mimeType: payload.contentType,
      );
      downloadedLocalCopy = true;
    } catch (error) {
      localDownloadError = error;
      debugPrint('💬 Chat attachment local download skipped: $error');
    }

    if (!mounted) return;
    if (!savedInFiles && !downloadedLocalCopy) {
      final reason = internalSaveError ?? localDownloadError ?? 'error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar el archivo: $reason')),
      );
      return;
    }

    final message = savedInFiles && downloadedLocalCopy
        ? 'Guardado en Archivos y descargado.'
        : savedInFiles
            ? 'Guardado en Archivos.'
            : 'Archivo descargado. No se pudo guardar en Archivos.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null || !await canLaunchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el archivo externo.')),
      );
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<Uint8List> _buildActivePdfDocument(PdfPageFormat format) async {
    return _activePdfBytes ?? Uint8List(0);
  }

  void _setPreviewZoom(double value) {
    final nextZoom = value.clamp(_minZoom, _maxZoom).toDouble();
    setState(() {
      _previewZoom = nextZoom;
      if (widget.isImage) {
        _imageTransformController.value = Matrix4.diagonal3Values(
          nextZoom,
          nextZoom,
          1,
        );
      }
    });
  }

  void _resetPreviewZoom() {
    _setPreviewZoom(1);
  }

  Future<Uint8List> _buildPrintDocument(
    PdfPageFormat format,
    _AttachmentPayload payload,
  ) async {
    if (_isPdf) return payload.bytes;

    final document = pw.Document();
    document.addPage(
      pw.Page(
        pageFormat: format,
        build: (_) => pw.Center(
          child: pw.Image(
            pw.MemoryImage(payload.bytes),
            fit: pw.BoxFit.contain,
          ),
        ),
      ),
    );
    return document.save();
  }

  Future<void> _printAttachment(_AttachmentPayload payload) async {
    if (_isPrinting) return;

    setState(() => _isPrinting = true);
    try {
      final printed = await Printing.layoutPdf(
        onLayout: (format) => _buildPrintDocument(format, payload),
        name: _safeFileName(widget.fileName),
        dynamicLayout: false,
        usePrinterSettings: true,
      );

      if (!mounted) return;
      if (printed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Documento enviado a impresión.')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo imprimir: $error')),
      );
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.sizeOf(context);
    final horizontalInset = screenSize.width < 720 ? 12.0 : 32.0;
    final verticalInset = screenSize.height < 720 ? 12.0 : 18.0;
    final availableWidth = screenSize.width - (horizontalInset * 2);
    final availableHeight = screenSize.height - (verticalInset * 2);
    final dialogWidth = screenSize.width < 900 || availableWidth < 1540
        ? availableWidth
        : 1540.0;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: verticalInset,
      ),
      backgroundColor: Colors.transparent,
      child: SizedBox(
        width: dialogWidth,
        height: availableHeight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Material(
            color: Colors.white,
            child: FutureBuilder<_AttachmentPayload>(
              future: _payloadFuture,
              builder: (context, snapshot) {
                final payload = snapshot.data;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AttachmentHeader(
                      fileName: widget.fileName,
                      extension: _normalizedExtension,
                      icon: _iconForExtension(_normalizedExtension),
                      isLoading:
                          snapshot.connectionState == ConnectionState.waiting,
                      zoom: _previewZoom,
                      canZoom: payload != null && (widget.isImage || _isPdf),
                      canPrint: payload != null && (_isPdf || widget.isImage),
                      isPrinting: _isPrinting,
                      onZoomOut: () => _setPreviewZoom(
                        _previewZoom - _zoomStep,
                      ),
                      onZoomIn: () => _setPreviewZoom(
                        _previewZoom + _zoomStep,
                      ),
                      onZoomReset: _resetPreviewZoom,
                      onPrint: payload == null || !(_isPdf || widget.isImage)
                          ? null
                          : () => _printAttachment(payload),
                      onClose: () => Navigator.of(context).maybePop(),
                      onOpenExternal: _openExternal,
                      onDownload:
                          payload == null ? null : () => _download(payload),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        child: _buildBody(theme, snapshot),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    ThemeData theme,
    AsyncSnapshot<_AttachmentPayload> snapshot,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const SizedBox.expand(
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (snapshot.hasError || snapshot.data == null) {
      return _AttachmentEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'No se pudo cargar el archivo',
        subtitle:
            'El archivo existe, pero el ERP no pudo obtenerlo para previsualizarlo.',
        primaryIcon: Icons.refresh,
        primaryLabel: 'Reintentar',
        onPrimary: () {
          setState(() {
            _payloadFuture = _loadPayload();
          });
        },
        secondaryIcon: Icons.open_in_new_outlined,
        secondaryLabel: 'Abrir externo',
        onSecondary: _openExternal,
      );
    }

    final payload = snapshot.data!;

    if (widget.isImage) {
      return ColoredBox(
        color: const Color(0xFF0F172A),
        child: InteractiveViewer(
          transformationController: _imageTransformController,
          minScale: 0.6,
          maxScale: 5,
          onInteractionEnd: (_) {
            final scale = _imageTransformController.value.getMaxScaleOnAxis();
            if ((scale - _previewZoom).abs() > 0.01 && mounted) {
              setState(() {
                _previewZoom = scale.clamp(_minZoom, _maxZoom).toDouble();
              });
            }
          },
          child: Center(
            child: Image.memory(
              payload.bytes,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _AttachmentEmptyState(
                icon: Icons.broken_image_outlined,
                title: 'Imagen no compatible',
                subtitle: 'Puedes descargarla o abrirla fuera del ERP.',
                primaryIcon: Icons.download_outlined,
                primaryLabel: 'Descargar',
                onPrimary: () => _download(payload),
                secondaryIcon: Icons.open_in_new_outlined,
                secondaryLabel: 'Abrir externo',
                onSecondary: _openExternal,
              ),
            ),
          ),
        ),
      );
    }

    if (_isPdf) {
      _activePdfBytes = payload.bytes;
      return SizedBox.expand(
        child: PdfPreview.builder(
          build: _buildActivePdfDocument,
          useActions: false,
          allowPrinting: false,
          allowSharing: false,
          canChangeOrientation: false,
          canChangePageFormat: false,
          canDebug: false,
          dynamicLayout: false,
          pdfFileName: _safeFileName(widget.fileName),
          scrollViewDecoration: const BoxDecoration(
            color: Color(0xFFE5E7EB),
          ),
          loadingWidget:
              const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          pagesBuilder: (context, pages) => _PdfPagesCanvas(
            pages: pages,
            zoom: _previewZoom,
          ),
        ),
      );
    }

    if (_isTextPreview) {
      final text = utf8.decode(payload.bytes, allowMalformed: true);
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

    return _AttachmentEmptyState(
      icon: _iconForExtension(_normalizedExtension),
      title: 'Vista previa no disponible',
      subtitle:
          '${widget.fileName} está listo para descargar o abrir con la app correspondiente.',
      meta:
          '${_normalizedExtension.toUpperCase()} · ${_formatBytes(payload.bytes.length)}',
      primaryIcon: Icons.download_outlined,
      primaryLabel: 'Descargar',
      onPrimary: () => _download(payload),
      secondaryIcon: Icons.open_in_new_outlined,
      secondaryLabel: 'Abrir externo',
      onSecondary: _openExternal,
    );
  }

  static String _safeFileName(String value) {
    final cleaned = value
        .trim()
        .split(RegExp(r'[\\/]'))
        .last
        .replaceAll(RegExp(r'[^A-Za-z0-9áéíóúÁÉÍÓÚñÑ._ -]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return cleaned.isEmpty ? 'archivo' : cleaned;
  }

  static String _fallbackMimeType(String extension) {
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'csv':
        return 'text/csv';
      case 'txt':
      case 'log':
        return 'text/plain';
      case 'json':
        return 'application/json';
      default:
        return 'application/octet-stream';
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  static IconData _iconForExtension(String extension) {
    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'doc':
      case 'docx':
        return Icons.description_outlined;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.table_chart_outlined;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return Icons.image_outlined;
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
}

class _AttachmentPayload {
  final Uint8List bytes;
  final String contentType;

  const _AttachmentPayload({
    required this.bytes,
    required this.contentType,
  });
}

class _AttachmentHeader extends StatelessWidget {
  final String fileName;
  final String extension;
  final IconData icon;
  final bool isLoading;
  final double zoom;
  final bool canZoom;
  final bool canPrint;
  final bool isPrinting;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomReset;
  final VoidCallback? onPrint;
  final VoidCallback onClose;
  final VoidCallback onOpenExternal;
  final VoidCallback? onDownload;

  const _AttachmentHeader({
    required this.fileName,
    required this.extension,
    required this.icon,
    required this.isLoading,
    required this.zoom,
    required this.canZoom,
    required this.canPrint,
    required this.isPrinting,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onZoomReset,
    required this.onPrint,
    required this.onClose,
    required this.onOpenExternal,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: const Color(0xFFF8FAFC),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 19, color: const Color(0xFF2563EB)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                Text(
                  isLoading
                      ? 'Cargando vista previa...'
                      : extension.isEmpty
                          ? 'Archivo'
                          : extension.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (canZoom) ...[
            _ZoomToolbar(
              zoom: zoom,
              onZoomOut: onZoomOut,
              onZoomIn: onZoomIn,
              onReset: onZoomReset,
            ),
            const SizedBox(width: 8),
          ],
          if (canPrint) ...[
            IconButton(
              tooltip: 'Imprimir',
              onPressed: isPrinting ? null : onPrint,
              icon: isPrinting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.print_outlined),
            ),
          ],
          IconButton(
            tooltip: 'Guardar en Archivos y descargar',
            onPressed: onDownload,
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: 'Abrir externo',
            onPressed: onOpenExternal,
            icon: const Icon(Icons.open_in_new_outlined),
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

class _ZoomToolbar extends StatelessWidget {
  final double zoom;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onReset;

  const _ZoomToolbar({
    required this.zoom,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final percent = '${(zoom * 100).round()}%';

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _compactIconButton(
            tooltip: 'Alejar',
            icon: Icons.remove,
            onPressed: onZoomOut,
          ),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onReset,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                percent,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF334155),
                ),
              ),
            ),
          ),
          _compactIconButton(
            tooltip: 'Acercar',
            icon: Icons.add,
            onPressed: onZoomIn,
          ),
        ],
      ),
    );
  }

  Widget _compactIconButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        radius: 17,
        onTap: onPressed,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(icon, size: 17, color: const Color(0xFF0F172A)),
        ),
      ),
    );
  }
}

class _PdfPagesCanvas extends StatelessWidget {
  final List<PdfPreviewPageData> pages;
  final double zoom;

  const _PdfPagesCanvas({
    required this.pages,
    required this.zoom,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final baseWidth = math.min(
          980.0,
          math.max(360.0, constraints.maxWidth - 112),
        );
        final pageWidth = baseWidth * zoom;
        final canvasWidth = math.max(constraints.maxWidth, pageWidth + 112);

        return DecoratedBox(
          decoration: const BoxDecoration(color: Color(0xFFE5E7EB)),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: canvasWidth,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 56,
                  vertical: 28,
                ),
                itemCount: pages.length,
                itemBuilder: (context, index) {
                  final page = pages[index];
                  final pageHeight = pageWidth / page.aspectRatio;

                  return Center(
                    child: Container(
                      width: pageWidth,
                      height: pageHeight,
                      margin: EdgeInsets.only(
                        bottom: index == pages.length - 1 ? 28 : 22,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Image(
                        image: page.image,
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
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

class _AttachmentEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? meta;
  final IconData primaryIcon;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final IconData secondaryIcon;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  const _AttachmentEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.meta,
    required this.primaryIcon,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryIcon,
    required this.secondaryLabel,
    required this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox.expand(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(icon, color: const Color(0xFF2563EB), size: 34),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF64748B),
                    height: 1.35,
                  ),
                ),
                if (meta != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    meta!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF94A3B8),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onSecondary,
                      icon: Icon(secondaryIcon, size: 17),
                      label: Text(secondaryLabel),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: onPrimary,
                      icon: Icon(primaryIcon, size: 17),
                      label: Text(primaryLabel),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
