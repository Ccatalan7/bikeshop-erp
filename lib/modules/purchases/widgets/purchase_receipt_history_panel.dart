import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/purchase_receipt.dart';
import '../services/purchase_receiving_service.dart';

typedef PurchaseReceiptHistoryLoader = Future<List<PurchaseReceiptRecord>>
    Function(String invoiceId);
typedef PurchaseReceiptVoider = Future<void> Function({
  required String receiptId,
  required String reason,
  required String idempotencyKey,
});

class PurchaseReceiptHistoryPanel extends StatefulWidget {
  const PurchaseReceiptHistoryPanel({
    super.key,
    required this.invoiceId,
    this.onChanged,
    this.historyLoader,
    this.receiptVoider,
  });

  final String invoiceId;
  final Future<void> Function()? onChanged;
  final PurchaseReceiptHistoryLoader? historyLoader;
  final PurchaseReceiptVoider? receiptVoider;

  @override
  State<PurchaseReceiptHistoryPanel> createState() =>
      _PurchaseReceiptHistoryPanelState();
}

class _PurchaseReceiptHistoryPanelState
    extends State<PurchaseReceiptHistoryPanel> {
  PurchaseReceivingService? _service;
  late Future<List<PurchaseReceiptRecord>> _history;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _history = _load();
  }

  Future<List<PurchaseReceiptRecord>> _load() {
    final loader = widget.historyLoader;
    if (loader != null) return loader(widget.invoiceId);
    return (_service ??= PurchaseReceivingService()).getHistory(
      widget.invoiceId,
    );
  }

  Future<void> _reload() async {
    setState(() => _history = _load());
    await _history;
  }

  Future<void> _void(PurchaseReceiptRecord receipt) async {
    var reasonText = '';
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Anular recepción ${receipt.number}'),
        content: TextField(
          autofocus: true,
          onChanged: (value) => reasonText = value,
          decoration: const InputDecoration(labelText: 'Motivo obligatorio'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, reasonText.trim()),
            child: const Text('Anular con reversión'),
          ),
        ],
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
        if (receipts.isEmpty) {
          return const Text('Aún no hay recepciones físicas registradas.');
        }
        return Column(
          children: receipts
              .map(
                (receipt) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${receipt.number} · ${receipt.acceptedQuantity} aceptadas',
                  ),
                  subtitle: Text(
                    receipt.canVoid
                        ? '${receipt.locationLabel ?? 'Sin ubicación'}'
                            '${receipt.discrepancyQuantity > 0 ? ' · ${receipt.discrepancyQuantity} con diferencia' : ''}'
                        : 'Anulada: ${receipt.voidReason ?? 'sin motivo registrado'}',
                  ),
                  trailing: receipt.canVoid
                      ? OutlinedButton.icon(
                          onPressed: _submitting ? null : () => _void(receipt),
                          icon: const Icon(Icons.undo, size: 18),
                          label: const Text('Anular'),
                        )
                      : const Chip(label: Text('Anulada')),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}
