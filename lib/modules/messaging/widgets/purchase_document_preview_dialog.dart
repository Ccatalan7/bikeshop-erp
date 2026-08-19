import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../../shared/services/inventory_service.dart';
import '../../../shared/utils/purchase_document_pdf_generator.dart';
import '../../purchases/pages/purchase_invoice_form_page.dart';
import '../../purchases/services/purchase_service.dart';
import '../../settings/services/appearance_service.dart';

/// The document as it stands after an edit, ready to replace what the composer
/// is holding.
class PurchaseDocumentRevision {
  const PurchaseDocumentRevision({
    required this.bytes,
    required this.invoiceNumber,
    required this.fileName,
  });

  final Uint8List bytes;
  final String invoiceNumber;
  final String fileName;
}

/// Shows the purchase document the supplier is about to receive.
///
/// Editing opens the canonical purchase document form — the same one under
/// «Documentos de compra», with its own validation and Guardar — instead of a
/// second editor that would drift from it. On return the PDF is rebuilt from
/// the stored document, so what leaves the chat is always the saved version.
///
/// Returns the rebuilt document when it changed, and null when nothing was
/// edited.
Future<PurchaseDocumentRevision?> showPurchaseDocumentPreviewDialog(
  BuildContext context, {
  required String invoiceId,
  required String invoiceNumber,
  required Uint8List bytes,
  bool canEdit = true,
  String? lockedReason,
}) {
  return showDialog<PurchaseDocumentRevision>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.38),
    builder: (context) => _PurchaseDocumentPreviewDialog(
      invoiceId: invoiceId,
      invoiceNumber: invoiceNumber,
      bytes: bytes,
      canEdit: canEdit,
      lockedReason: lockedReason,
    ),
  );
}

class _PurchaseDocumentPreviewDialog extends StatefulWidget {
  const _PurchaseDocumentPreviewDialog({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.bytes,
    required this.canEdit,
    required this.lockedReason,
  });

  final String invoiceId;
  final String invoiceNumber;
  final Uint8List bytes;
  final bool canEdit;
  final String? lockedReason;

  @override
  State<_PurchaseDocumentPreviewDialog> createState() =>
      _PurchaseDocumentPreviewDialogState();
}

class _PurchaseDocumentPreviewDialogState
    extends State<_PurchaseDocumentPreviewDialog> {
  late Uint8List _bytes = widget.bytes;
  late String _invoiceNumber = widget.invoiceNumber;
  PurchaseDocumentRevision? _revision;
  bool _isRebuilding = false;
  int _renderVersion = 0;

  Future<void> _openEditor() async {
    final messenger = ScaffoldMessenger.of(context);
    final purchaseService = context.read<PurchaseService>();
    final appearanceService = context.read<AppearanceService>();
    final inventoryService = context.read<InventoryService>();

    // A floating block over the chat, not a route: a full-screen page would
    // bury the conversation the operator is in the middle of, and its way back
    // belongs to the document's own surface, not to this one.
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final screen = MediaQuery.sizeOf(dialogContext);
        return Dialog(
          insetPadding: const EdgeInsets.all(24),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: SizedBox(
            // The document's line rows carry name, SKU, code, quantity, price,
            // discount and amount. Anything narrower than this and the product
            // column collapses into two broken words, so the block takes the
            // window minus a margin instead of a tidy fixed size.
            width: (screen.width - 64).clamp(0.0, 2000.0).toDouble(),
            height: (screen.height - 64).clamp(0.0, 1400.0).toDouble(),
            child: PurchaseInvoiceFormPage(
              invoiceId: widget.invoiceId,
              startInEditMode: true,
              onEmbeddedFinished: (saved) =>
                  Navigator.of(dialogContext).pop(saved),
            ),
          ),
        );
      },
    );
    if (!mounted) return;

    setState(() => _isRebuilding = true);
    try {
      final invoice = await purchaseService.getPurchaseInvoice(
        widget.invoiceId,
        refresh: true,
      );
      if (!mounted) return;
      if (invoice == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('El documento ya no está disponible.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final bytes = await PurchaseDocumentPdfGenerator.generateBytes(
        invoice,
        appearanceService: appearanceService,
        inventoryService: inventoryService,
      );
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _invoiceNumber = invoice.invoiceNumber;
        _renderVersion += 1;
        _revision = PurchaseDocumentRevision(
          bytes: bytes,
          invoiceNumber: invoice.invoiceNumber,
          fileName: PurchaseDocumentPdfGenerator.fileNameFor(
            invoice.invoiceNumber,
          ),
        );
      });
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo rehacer el documento: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isRebuilding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screen = MediaQuery.sizeOf(context);
    final dialogWidth = (screen.width - 32).clamp(0.0, 900.0).toDouble();
    final dialogHeight = (screen.height - 32).clamp(0.0, 880.0).toDouble();
    final lockedReason = widget.lockedReason;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Documento de compra N° $_invoiceNumber',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _revision == null
                              ? 'Así lo recibirá el proveedor.'
                              : 'Actualizado. Se enviará esta versión.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(_revision),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: theme.dividerColor),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: PdfPreview(
                      key: ValueKey(_renderVersion),
                      build: (PdfPageFormat _) async => _bytes,
                      useActions: false,
                      allowPrinting: false,
                      allowSharing: false,
                      canChangeOrientation: false,
                      canChangePageFormat: false,
                      canDebug: false,
                      pdfFileName: PurchaseDocumentPdfGenerator.fileNameFor(
                        _invoiceNumber,
                      ),
                      scrollViewDecoration: const BoxDecoration(
                        color: Color(0xFFE8EDF2),
                      ),
                    ),
                  ),
                  if (_isRebuilding)
                    Positioned.fill(
                      child: ColoredBox(
                        color: colorScheme.surface.withValues(alpha: 0.72),
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: theme.dividerColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Row(
                children: [
                  if (lockedReason != null)
                    Expanded(
                      child: Text(
                        lockedReason,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(_revision),
                    child: const Text('Listo'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed:
                        widget.canEdit && !_isRebuilding ? _openEditor : null,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Editar documento'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
