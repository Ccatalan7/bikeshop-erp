import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

/// Opens a bundled PDF without leaving the ERP workspace.
Future<void> showAssetPdfPreviewDialog(
  BuildContext context, {
  required String assetPath,
  required String title,
  required String description,
  required String fileName,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.38),
    builder: (context) => _AssetPdfPreviewDialog(
      assetPath: assetPath,
      title: title,
      description: description,
      fileName: fileName,
    ),
  );
}

class _AssetPdfPreviewDialog extends StatefulWidget {
  const _AssetPdfPreviewDialog({
    required this.assetPath,
    required this.title,
    required this.description,
    required this.fileName,
  });

  final String assetPath;
  final String title;
  final String description;
  final String fileName;

  @override
  State<_AssetPdfPreviewDialog> createState() => _AssetPdfPreviewDialogState();
}

class _AssetPdfPreviewDialogState extends State<_AssetPdfPreviewDialog> {
  late Future<Uint8List> _pdfBytes;

  @override
  void initState() {
    super.initState();
    _pdfBytes = _loadPdf();
  }

  Future<Uint8List> _loadPdf() async {
    final data = await rootBundle.load(widget.assetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  void _retry() {
    setState(() => _pdfBytes = _loadPdf());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screen = MediaQuery.sizeOf(context);
    final dialogWidth = (screen.width - 32).clamp(0.0, 1120.0).toDouble();
    final dialogHeight = (screen.height - 32).clamp(0.0, 900.0).toDouble();

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            _ManualPreviewHeader(
              title: widget.title,
              description: widget.description,
              onClose: () => Navigator.of(context).pop(),
            ),
            Divider(height: 1, color: theme.dividerColor),
            Expanded(
              child: FutureBuilder<Uint8List>(
                future: _pdfBytes,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError || snapshot.data == null) {
                    return _ManualPreviewError(onRetry: _retry);
                  }
                  final bytes = snapshot.data!;
                  return PdfPreview(
                    build: (PdfPageFormat _) async => bytes,
                    useActions: false,
                    allowPrinting: false,
                    allowSharing: false,
                    canChangeOrientation: false,
                    canChangePageFormat: false,
                    canDebug: false,
                    pdfFileName: widget.fileName,
                    scrollViewDecoration: const BoxDecoration(
                      color: Color(0xFFE8EDF2),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualPreviewHeader extends StatelessWidget {
  const _ManualPreviewHeader({
    required this.title,
    required this.description,
    required this.onClose,
  });

  final String title;
  final String description;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(20, 13, 10, 13),
      child: Row(
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: 22,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (MediaQuery.sizeOf(context).width >= 560) ...[
                  const SizedBox(height: 2),
                  Text(
                    description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            tooltip: 'Cerrar manual',
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _ManualPreviewError extends StatelessWidget {
  const _ManualPreviewError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.description_outlined,
              size: 38,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'No se pudo abrir el manual',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Vuelve a intentarlo. El archivo se incluye con la aplicación.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
