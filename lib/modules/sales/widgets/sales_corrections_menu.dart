import 'package:flutter/material.dart';

import '../models/sales_models.dart';
import '../pages/sales_credit_note_page.dart';
import '../pages/sales_return_page.dart';
import '../services/sales_credit_note_service.dart';
import '../services/sales_return_service.dart';

typedef SalesCorrectionCapabilityLoader = Future<bool> Function();
typedef SalesCorrectionPageOpener = Future<void> Function(
  BuildContext context,
  Invoice invoice,
);
typedef SalesCorrectionRefresh = Future<void> Function();

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
    this.onChanged,
    this.returnCapabilityLoader,
    this.creditNoteCapabilityLoader,
    this.returnPageOpener,
    this.creditNotePageOpener,
  });

  final Invoice invoice;
  final bool iconOnly;
  final SalesCorrectionRefresh? onChanged;
  final SalesCorrectionCapabilityLoader? returnCapabilityLoader;
  final SalesCorrectionCapabilityLoader? creditNoteCapabilityLoader;
  final SalesCorrectionPageOpener? returnPageOpener;
  final SalesCorrectionPageOpener? creditNotePageOpener;

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
    if (action == 'return') {
      final opener = widget.returnPageOpener ?? _openReturnPage;
      await opener(context, widget.invoice);
    } else if (action == 'credit') {
      final opener = widget.creditNotePageOpener ?? _openCreditNotePage;
      await opener(context, widget.invoice);
    }

    if (!mounted) return;
    final refresh = widget.onChanged;
    if (refresh != null) await refresh();
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
    if ((!_canCredit && !_canReturn) || widget.invoice.id == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<_CorrectionCapabilities>(
      future: _capabilities,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
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
        if (!returnsEnabled && !creditNotesEnabled) {
          return const SizedBox.shrink();
        }

        return PopupMenuButton<String>(
          tooltip: 'Devoluciones y notas de crédito',
          onSelected: _open,
          itemBuilder: (context) => [
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sync_alt, size: 20),
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

class _CorrectionCapabilities {
  const _CorrectionCapabilities({
    required this.returnsEnabled,
    required this.creditNotesEnabled,
  });

  final bool returnsEnabled;
  final bool creditNotesEnabled;
}
