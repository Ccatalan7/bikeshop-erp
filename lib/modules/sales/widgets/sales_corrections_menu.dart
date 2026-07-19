import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/sales_models.dart';
import '../pages/sales_credit_note_page.dart';
import '../pages/sales_return_page.dart';
import '../services/sales_credit_note_service.dart';
import '../services/sales_invoice_void_service.dart';
import '../services/sales_return_service.dart';

typedef SalesCorrectionCapabilityLoader = Future<bool> Function();
typedef SalesCorrectionPageOpener = Future<void> Function(
  BuildContext context,
  Invoice invoice,
);
typedef SalesCorrectionRefresh = Future<void> Function();
typedef SalesInvoiceVoidExecutor = Future<void> Function({
  required String invoiceId,
  required String reason,
  required String idempotencyKey,
});

/// Canonical entry point for post-sale corrections.
///
/// This widget is intentionally shared by both routed sales invoice surfaces:
/// [InvoiceFormPage] and [SalesInvoiceEditor]. Keeping the feature entry point
/// here prevents one invoice presentation from exposing a different workflow.
class SalesCorrectionsMenu extends StatefulWidget {
  const SalesCorrectionsMenu({
    super.key,
    required this.invoice,
    this.iconOnly = false,
    this.dense = false,
    this.onChanged,
    this.returnCapabilityLoader,
    this.creditNoteCapabilityLoader,
    this.returnPageOpener,
    this.creditNotePageOpener,
    this.voidService,
    this.voidExecutor,
  });

  final Invoice invoice;
  final bool iconOnly;
  final bool dense;
  final SalesCorrectionRefresh? onChanged;
  final SalesCorrectionCapabilityLoader? returnCapabilityLoader;
  final SalesCorrectionCapabilityLoader? creditNoteCapabilityLoader;
  final SalesCorrectionPageOpener? returnPageOpener;
  final SalesCorrectionPageOpener? creditNotePageOpener;
  final SalesInvoiceVoidService? voidService;
  final SalesInvoiceVoidExecutor? voidExecutor;

  @override
  State<SalesCorrectionsMenu> createState() => _SalesCorrectionsMenuState();
}

class _SalesCorrectionsMenuState extends State<SalesCorrectionsMenu> {
  late Future<_CorrectionCapabilities> _capabilities;

  @override
  void initState() {
    super.initState();
    _capabilities = _loadCapabilities();
  }

  @override
  void didUpdateWidget(covariant SalesCorrectionsMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.invoice.id != widget.invoice.id ||
        oldWidget.returnCapabilityLoader != widget.returnCapabilityLoader ||
        oldWidget.creditNoteCapabilityLoader !=
            widget.creditNoteCapabilityLoader) {
      _capabilities = _loadCapabilities();
    }
  }

  bool get _canCredit =>
      widget.invoice.status == InvoiceStatus.confirmed ||
      widget.invoice.status == InvoiceStatus.paid ||
      widget.invoice.status == InvoiceStatus.overdue;

  bool get _canReturn => widget.invoice.status == InvoiceStatus.paid;

  bool get _canVoid =>
      widget.invoice.source != 'mechanic_job' &&
      (widget.invoice.status == InvoiceStatus.sent ||
          widget.invoice.status == InvoiceStatus.confirmed ||
          widget.invoice.status == InvoiceStatus.overdue);

  Future<_CorrectionCapabilities> _loadCapabilities() async {
    final results = await Future.wait<bool>([
      (widget.returnCapabilityLoader ?? SalesReturnService().isEnabled)(),
      (widget.creditNoteCapabilityLoader ??
          SalesCreditNoteService().isEnabled)(),
    ]);
    return _CorrectionCapabilities(
      returnsEnabled: results[0],
      creditNotesEnabled: results[1],
    );
  }

  Future<void> _open(String action) async {
    var changed = true;
    if (action == 'return') {
      final opener = widget.returnPageOpener ?? _openReturnPage;
      await opener(context, widget.invoice);
    } else if (action == 'credit') {
      final opener = widget.creditNotePageOpener ?? _openCreditNotePage;
      await opener(context, widget.invoice);
    } else if (action == 'void') {
      changed = await _discardInvoice();
    }

    if (!mounted || !changed) return;
    final refresh = widget.onChanged;
    if (refresh != null) await refresh();
  }

  Future<bool> _discardInvoice() async {
    final invoiceId = widget.invoice.id;
    if (invoiceId == null) return false;

    final reason = await showDialog<String>(
      context: context,
      builder: (context) => _DiscardSalesInvoiceDialog(
        invoiceNumber: widget.invoice.invoiceNumber,
      ),
    );
    if (reason == null || !mounted) return false;

    try {
      final idempotencyKey = const Uuid().v4();
      final executor = widget.voidExecutor;
      if (executor != null) {
        await executor(
          invoiceId: invoiceId,
          reason: reason,
          idempotencyKey: idempotencyKey,
        );
      } else {
        await (widget.voidService ?? SalesInvoiceVoidService()).voidInvoice(
          invoiceId: invoiceId,
          reason: reason,
          idempotencyKey: idempotencyKey,
        );
      }
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Factura ${widget.invoice.invoiceNumber} descartada. Stock y contabilidad revertidos.',
          ),
        ),
      );
      return true;
    } on SalesInvoiceVoidException catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return false;
    }
  }

  Future<void> _openReturnPage(
    BuildContext context,
    Invoice invoice,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SalesReturnPage(
          invoice: invoice,
          service: SalesReturnService(),
        ),
      ),
    );
  }

  Future<void> _openCreditNotePage(
    BuildContext context,
    Invoice invoice,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SalesCreditNotePage(
          invoice: invoice,
          service: SalesCreditNoteService(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if ((!_canCredit && !_canReturn && !_canVoid) ||
        widget.invoice.id == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<_CorrectionCapabilities>(
      future: _capabilities,
      builder: (context, snapshot) {
        if (snapshot.hasError && !_canVoid) {
          return Tooltip(
            message: 'No se pudo verificar el módulo de correcciones.',
            child: Icon(
              Icons.warning_amber_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
          );
        }

        final capabilities = snapshot.data;
        final returnsEnabled =
            capabilities?.returnsEnabled == true && _canReturn;
        final creditNotesEnabled =
            capabilities?.creditNotesEnabled == true && _canCredit;
        if (!returnsEnabled && !creditNotesEnabled && !_canVoid) {
          return const SizedBox.shrink();
        }

        return PopupMenuButton<String>(
          tooltip: 'Correcciones y descarte',
          onSelected: _open,
          itemBuilder: (context) => [
            if (_canVoid)
              const PopupMenuItem<String>(
                value: 'void',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_sweep_outlined),
                  title: Text('Descartar factura'),
                  subtitle: Text('Anula y revierte una venta no realizada'),
                ),
              ),
            if (returnsEnabled)
              const PopupMenuItem<String>(
                value: 'return',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.assignment_return_outlined),
                  title: Text('Devolución física'),
                  subtitle: Text('Recepción, inspección o baja'),
                ),
              ),
            if (creditNotesEnabled)
              const PopupMenuItem<String>(
                value: 'credit',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.receipt_long_outlined),
                  title: Text('Nota de crédito'),
                  subtitle: Text('Corrige saldo, IVA e ingresos'),
                ),
              ),
          ],
          icon: widget.iconOnly ? const Icon(Icons.sync_alt) : null,
          child: widget.iconOnly
              ? null
              : Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.dense ? 8 : 12,
                    vertical: widget.dense ? 4 : 9,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sync_alt, size: 18),
                      SizedBox(width: 8),
                      Text('Correcciones'),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _DiscardSalesInvoiceDialog extends StatefulWidget {
  const _DiscardSalesInvoiceDialog({required this.invoiceNumber});

  final String invoiceNumber;

  @override
  State<_DiscardSalesInvoiceDialog> createState() =>
      _DiscardSalesInvoiceDialogState();
}

class _DiscardSalesInvoiceDialogState
    extends State<_DiscardSalesInvoiceDialog> {
  final TextEditingController _reasonController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  void _confirm() {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Indica el motivo del descarte.');
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Descartar factura ${widget.invoiceNumber}'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Usa esta acción cuando la venta nunca ocurrió, por ejemplo una factura de prueba o creada por error.',
            ),
            const SizedBox(height: 12),
            const _DiscardEffectRow(
              icon: Icons.inventory_2_outlined,
              text: 'El stock descontado volverá automáticamente.',
            ),
            const _DiscardEffectRow(
              icon: Icons.account_balance_outlined,
              text: 'El asiento se revertirá conservando su huella.',
            ),
            const _DiscardEffectRow(
              icon: Icons.filter_alt_outlined,
              text: 'La factura quedará en el filtro Anuladas.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reasonController,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Motivo obligatorio',
                hintText: 'Ej.: factura de prueba, la venta no ocurrió',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _confirm(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _confirm,
          icon: const Icon(Icons.delete_sweep_outlined),
          label: const Text('Descartar y revertir'),
        ),
      ],
    );
  }
}

class _DiscardEffectRow extends StatelessWidget {
  const _DiscardEffectRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _CorrectionCapabilities {
  const _CorrectionCapabilities({
    required this.returnsEnabled,
    required this.creditNotesEnabled,
  });

  final bool returnsEnabled;
  final bool creditNotesEnabled;
}
