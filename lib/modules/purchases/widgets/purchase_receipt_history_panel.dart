import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/purchase_receipt.dart';
import '../models/purchase_receipt_resolution.dart';
import '../services/purchase_receipt_resolution_service.dart';
import '../services/purchase_receiving_service.dart';
import 'purchase_receipt_resolution_register.dart';

typedef PurchaseReceiptHistoryLoader = Future<List<PurchaseReceiptRecord>>
    Function(String invoiceId);
typedef PurchaseReceiptVoider = Future<void> Function({
  required String receiptId,
  required String reason,
  required String idempotencyKey,
});
typedef PurchaseReceiptResolutionHistoryLoader
    = Future<List<PurchaseReceiptResolutionCase>> Function(String invoiceId);

class PurchaseReceiptHistoryPanel extends StatefulWidget {
  const PurchaseReceiptHistoryPanel({
    super.key,
    required this.invoiceId,
    this.onChanged,
    this.onReceiptTap,
    this.onResolutionCaseTap,
    this.onResolutionDocumentTap,
    this.historyLoader,
    this.resolutionLoader,
    this.receiptVoider,
  });

  final String invoiceId;
  final Future<void> Function()? onChanged;
  final ValueChanged<PurchaseReceiptRecord>? onReceiptTap;
  final PurchaseReceiptResolutionCaseTap? onResolutionCaseTap;
  final PurchaseReceiptResolutionDocumentTap? onResolutionDocumentTap;
  final PurchaseReceiptHistoryLoader? historyLoader;
  final PurchaseReceiptResolutionHistoryLoader? resolutionLoader;
  final PurchaseReceiptVoider? receiptVoider;

  @override
  State<PurchaseReceiptHistoryPanel> createState() =>
      _PurchaseReceiptHistoryPanelState();
}

class _PurchaseReceiptHistoryPanelState
    extends State<PurchaseReceiptHistoryPanel> {
  PurchaseReceivingService? _service;
  PurchaseReceiptResolutionService? _resolutionService;
  late Future<List<PurchaseReceiptRecord>> _history;
  late Future<List<PurchaseReceiptResolutionCase>> _resolutions;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _history = _load();
    _resolutions = _loadResolutions();
  }

  Future<List<PurchaseReceiptRecord>> _load() {
    final loader = widget.historyLoader;
    if (loader != null) return loader(widget.invoiceId);
    return (_service ??= PurchaseReceivingService()).getHistory(
      widget.invoiceId,
    );
  }

  Future<List<PurchaseReceiptResolutionCase>> _loadResolutions() {
    final loader = widget.resolutionLoader;
    if (loader != null) return loader(widget.invoiceId);
    return (_resolutionService ??= PurchaseReceiptResolutionService())
        .getCasesForInvoice(widget.invoiceId);
  }

  Future<void> _reload() async {
    setState(() {
      _history = _load();
      _resolutions = _loadResolutions();
    });
    await Future.wait([_history, _resolutions]);
  }

  void _openResolutionCase(
    PurchaseReceiptResolutionCase resolutionCase,
    List<PurchaseReceiptRecord> receipts,
  ) {
    final resolutionCallback = widget.onResolutionCaseTap;
    if (resolutionCallback != null) {
      resolutionCallback(resolutionCase);
      return;
    }
    final callback = widget.onReceiptTap;
    if (callback == null) return;
    for (final receipt in receipts) {
      if (receipt.id == resolutionCase.purchaseReceiptId) {
        callback(receipt);
        return;
      }
    }
  }

  void _openResolutionDocument(
    PurchaseReceiptResolutionCase resolutionCase,
    PurchaseReceiptResolutionAllocation allocation,
    PurchaseReceiptResolutionDocumentReference document,
    List<PurchaseReceiptRecord> receipts,
  ) {
    final resolutionCallback = widget.onResolutionDocumentTap;
    if (resolutionCallback != null) {
      resolutionCallback(resolutionCase, allocation, document);
      return;
    }
    final targetReceiptId =
        document.kind == PurchaseReceiptResolutionDocumentKind.laterReceipt
            ? allocation.laterPurchaseReceiptId
            : resolutionCase.purchaseReceiptId;
    final callback = widget.onReceiptTap;
    if (callback == null || targetReceiptId == null) return;
    for (final receipt in receipts) {
      if (receipt.id == targetReceiptId) {
        callback(receipt);
        return;
      }
    }
  }

  Future<void> _void(PurchaseReceiptRecord receipt) async {
    var reasonText = '';
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded),
          title: Text('Anular recepción ${receipt.number}'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Esta acción no elimina el registro. Creará una reversa '
                  'auditada y retirará del inventario las unidades aceptadas '
                  'por esta recepción.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Si la recepción ya tiene una devolución, nota de crédito, '
                  'reembolso u otra resolución vinculada, primero debes '
                  'anular esas operaciones dependientes en orden inverso.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 18),
                TextField(
                  autofocus: true,
                  onChanged: (value) {
                    reasonText = value;
                    setDialogState(() {});
                  },
                  decoration: const InputDecoration(
                    labelText: 'Motivo obligatorio',
                    hintText: 'Explica por qué se revierte la recepción',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Conservar recepción'),
            ),
            FilledButton(
              onPressed: reasonText.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, reasonText.trim()),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Crear reversa'),
            ),
          ],
        ),
      ),
    );
    if (reason == null || reason.isEmpty || !mounted) return;

    setState(() => _submitting = true);
    try {
      final voider = widget.receiptVoider ??
          (_service ??= PurchaseReceivingService()).voidReceipt;
      await voider(
        receiptId: receipt.id,
        reason: reason,
        idempotencyKey: const Uuid().v4(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Recepción ${receipt.number} anulada con trazabilidad completa.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
      await _reload();
      await widget.onChanged?.call();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo anular la recepción: $error'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PurchaseReceiptRecord>>(
      future: _history,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Text('No se pudo cargar el historial: ${snapshot.error}');
        }
        final receipts = snapshot.data ?? const [];
        return FutureBuilder<List<PurchaseReceiptResolutionCase>>(
          future: _resolutions,
          builder: (context, resolutionSnapshot) {
            if (resolutionSnapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (resolutionSnapshot.hasError) {
              return Text(
                'No se pudieron cargar las resoluciones: '
                '${resolutionSnapshot.error}',
              );
            }
            final resolutionCases = resolutionSnapshot.data ?? const [];
            if (receipts.isEmpty && resolutionCases.isEmpty) {
              return const Text('Aún no hay recepciones físicas registradas.');
            }
            return Column(
              children: [
                for (final receipt in receipts)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: widget.onReceiptTap == null
                        ? null
                        : () => widget.onReceiptTap!(receipt),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            receipt.number,
                            style: TextStyle(
                              color: widget.onReceiptTap == null
                                  ? null
                                  : Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w700,
                              decoration: widget.onReceiptTap == null
                                  ? null
                                  : TextDecoration.underline,
                            ),
                          ),
                        ),
                        Text(' · ${receipt.acceptedQuantity} aceptadas'),
                      ],
                    ),
                    subtitle: Text(
                      receipt.canVoid
                          ? '${receipt.locationLabel ?? 'Sin ubicación'}'
                              '${receipt.discrepancyQuantity > 0 ? ' · ${receipt.discrepancyQuantity} con diferencia' : ''}'
                          : 'Anulada: ${receipt.voidReason ?? 'sin motivo registrado'}',
                    ),
                    trailing: receipt.canVoid
                        ? OutlinedButton.icon(
                            onPressed:
                                _submitting ? null : () => _void(receipt),
                            icon: const Icon(Icons.undo, size: 18),
                            label: const Text('Anular'),
                          )
                        : const Chip(label: Text('Anulada')),
                  ),
                if (receipts.isNotEmpty && resolutionCases.isNotEmpty)
                  const Divider(height: 24),
                PurchaseReceiptResolutionRegister(
                  cases: resolutionCases,
                  onCaseTap: (resolutionCase) =>
                      _openResolutionCase(resolutionCase, receipts),
                  onDocumentTap: (resolutionCase, allocation, document) =>
                      _openResolutionDocument(
                    resolutionCase,
                    allocation,
                    document,
                    receipts,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
