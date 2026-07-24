import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../../shared/services/document_accounting_context_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/utils/file_download.dart';
import '../../../shared/utils/purchase_payment_receipt_pdf_generator.dart';
import '../../../shared/widgets/document_accounting_preview.dart';
import '../models/purchase_invoice.dart';
import '../models/purchase_payment.dart';
import '../services/purchase_service.dart';

class PurchasePaymentDetailView extends StatefulWidget {
  const PurchasePaymentDetailView({
    super.key,
    required this.payment,
    required this.invoice,
    required this.paymentMethodName,
    this.onClose,
    this.onRefresh,
  });

  final PurchasePayment payment;
  final PurchaseInvoice invoice;
  final String paymentMethodName;
  final VoidCallback? onClose;
  final Future<void> Function()? onRefresh;

  @override
  State<PurchasePaymentDetailView> createState() =>
      _PurchasePaymentDetailViewState();
}

class _PurchasePaymentDetailViewState extends State<PurchasePaymentDetailView> {
  late Future<DocumentAccountingContext> _accountingFuture;
  late Future<List<PurchasePaymentEditEvent>> _eventsFuture;
  bool _documentBusy = false;

  @override
  void initState() {
    super.initState();
    _loadEvidence();
  }

  @override
  void didUpdateWidget(covariant PurchasePaymentDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.payment.id != widget.payment.id ||
        oldWidget.payment.updatedAt != widget.payment.updatedAt) {
      _loadEvidence();
    }
  }

  void _loadEvidence() {
    final paymentId = widget.payment.id ?? '';
    _accountingFuture = DocumentAccountingContextService().loadPurchasePayment(
      paymentId: paymentId,
    );
    _eventsFuture = paymentId.isEmpty
        ? Future.value(const [])
        : context
            .read<PurchaseService>()
            .loadPurchasePaymentEditEvents(paymentId);
  }

  Future<void> _refresh() async {
    if (widget.onRefresh != null) await widget.onRefresh!();
    if (!mounted) return;
    setState(_loadEvidence);
  }

  Future<Uint8List> _generatePdf() async {
    final tenant = await context.read<TenantService>().getCurrentTenant();
    final businessName =
        tenant?['name']?.toString() ?? tenant?['business_name']?.toString();
    final document = await PurchasePaymentReceiptPdfGenerator.generate(
      payment: widget.payment,
      invoice: widget.invoice,
      paymentMethodName: widget.paymentMethodName,
      businessName: businessName,
    );
    return document.save();
  }

  Future<void> _withDocumentAction(Future<void> Function() action) async {
    if (_documentBusy) return;
    setState(() => _documentBusy = true);
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo generar el comprobante: $error'),
          backgroundColor: const Color(0xFFB91C1C),
        ),
      );
    } finally {
      if (mounted) setState(() => _documentBusy = false);
    }
  }

  Future<void> _downloadPdf() => _withDocumentAction(() async {
        final bytes = await _generatePdf();
        await downloadFile(
          bytes: bytes,
          fileName: PurchasePaymentReceiptPdfGenerator.fileName(widget.payment),
          mimeType: 'application/pdf',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Comprobante guardado en Descargas.'),
            backgroundColor: Color(0xFF047857),
          ),
        );
      });

  Future<void> _sharePdf() => _withDocumentAction(() async {
        final bytes = await _generatePdf();
        await Printing.sharePdf(
          bytes: bytes,
          filename: PurchasePaymentReceiptPdfGenerator.fileName(widget.payment),
        );
      });

  Future<void> _printPdf() => _withDocumentAction(() async {
        final bytes = await _generatePdf();
        await Printing.layoutPdf(onLayout: (_) async => bytes);
      });

  Future<void> _openEdit() async {
    final id = widget.payment.id;
    if (id == null || id.isEmpty) return;
    await context.push('/purchases/payments/$id/edit');
    if (mounted) await _refresh();
  }

  void _openInvoice() {
    final invoiceId = widget.invoice.id;
    if (invoiceId == null || invoiceId.isEmpty) return;
    context.push('/purchases/$invoiceId');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('purchase-payment-detail-${widget.payment.id}'),
      color: const Color(0xFFF4F6FA),
      child: Column(
        children: [
          _buildHeader(),
          _buildActionBar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 38),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = (constraints.maxWidth - 8)
                        .clamp(360.0, 900.0)
                        .toDouble();
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1080),
                        child: Column(
                          children: [
                            DocumentPaperShell(
                              width: width,
                              status: const DocumentPaperStatus(
                                label: 'REGISTRADO',
                                foreground: Color(0xFF047857),
                                background: Color(0xFFECFDF5),
                                border: Color(0xFFA7F3D0),
                              ),
                              child: _buildReceipt(),
                            ),
                            const SizedBox(height: 30),
                            SizedBox(
                              width: width,
                              child: _buildAccountingEvidence(),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: width,
                              child: _buildHistory(),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(
              Icons.account_balance_wallet_outlined,
              size: 19,
              color: Color(0xFF047857),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _paymentNumber(widget.payment),
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Pago a proveedor · ${widget.invoice.invoiceNumber}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _documentBusy ? null : _refresh,
            icon: const Icon(Icons.refresh, size: 19),
            tooltip: 'Actualizar',
          ),
          if (widget.onClose != null)
            IconButton(
              onPressed: widget.onClose,
              icon: const Icon(Icons.close, size: 20),
              tooltip: 'Cerrar vista previa',
            ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ToolbarButton(
              icon: Icons.edit_outlined,
              label: 'Editar',
              onPressed: _openEdit,
            ),
            _ToolbarButton(
              icon: Icons.share_outlined,
              label: 'Compartir',
              onPressed: _documentBusy ? null : _sharePdf,
            ),
            _ToolbarButton(
              icon: Icons.download_outlined,
              label: 'Descargar PDF',
              onPressed: _documentBusy ? null : _downloadPdf,
            ),
            _ToolbarButton(
              icon: Icons.print_outlined,
              label: 'Imprimir',
              onPressed: _documentBusy ? null : _printPdf,
            ),
            const SizedBox(width: 8),
            Container(width: 1, height: 22, color: const Color(0xFFCBD5E1)),
            const SizedBox(width: 8),
            _ToolbarButton(
              icon: Icons.receipt_long_outlined,
              label: 'Abrir factura',
              onPressed: widget.invoice.id == null ? null : _openInvoice,
            ),
            if (_documentBusy) ...[
              const SizedBox(width: 10),
              const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReceipt() {
    final invoice = widget.invoice;
    final payment = widget.payment;
    final remaining = invoice.balance.clamp(0, invoice.total).toDouble();

    return Padding(
      padding: const EdgeInsets.fromLTRB(42, 52, 42, 42),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'COMPROBANTE INTERNO DE PAGO A PROVEEDOR',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Registro interno de egreso · No constituye factura ni DTE',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _paymentNumber(payment),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ChileanUtils.formatDateTime(payment.date.toLocal()),
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 34),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'IMPORTE PAGADO',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.7,
                    ),
                  ),
                ),
                Text(
                  ChileanUtils.formatCurrency(payment.amount),
                  style: const TextStyle(
                    color: Color(0xFF047857),
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          Wrap(
            spacing: 34,
            runSpacing: 20,
            children: [
              _ReceiptField(
                label: 'Proveedor',
                value: invoice.supplierName ?? 'Proveedor no identificado',
                secondary: invoice.supplierRut?.trim().isNotEmpty == true
                    ? ChileanUtils.formatRut(invoice.supplierRut)
                    : null,
              ),
              _ReceiptField(
                label: 'Factura vinculada',
                value: invoice.invoiceNumber,
                secondary:
                    'Total ${ChileanUtils.formatCurrency(invoice.total)}',
              ),
              _ReceiptField(
                label: 'Documento proveedor',
                value: invoice.supplierInvoiceNumber?.trim().isNotEmpty == true
                    ? invoice.supplierInvoiceNumber!.trim()
                    : 'Sin número informado',
                secondary: invoice.supplierInvoiceDate == null
                    ? null
                    : ChileanUtils.formatDate(invoice.supplierInvoiceDate!),
              ),
              _ReceiptField(
                label: 'Medio de pago',
                value: widget.paymentMethodName,
              ),
              _ReceiptField(
                label: 'Referencia externa',
                value: payment.reference?.trim().isNotEmpty == true
                    ? payment.reference!.trim()
                    : 'Sin referencia',
              ),
              _ReceiptField(
                label: 'Modelo de pago',
                value: invoice.prepaymentModel
                    ? 'Pago anticipado'
                    : 'Pago posterior a recepción',
              ),
              _ReceiptField(
                label: 'Estado de factura',
                value: invoice.status.displayName,
              ),
              _ReceiptField(
                label: 'Saldo actual de factura',
                value: ChileanUtils.formatCurrency(remaining),
              ),
            ],
          ),
          if (payment.notes?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 30),
            const Divider(color: Color(0xFFE2E8F0)),
            const SizedBox(height: 14),
            const Text(
              'NOTAS INTERNAS',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              payment.notes!.trim(),
              style: const TextStyle(
                color: Color(0xFF334155),
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 30),
          const Divider(color: Color(0xFFE2E8F0)),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _MiniMetric(
                  label: 'Total factura',
                  value: ChileanUtils.formatCurrency(invoice.total),
                ),
              ),
              Expanded(
                child: _MiniMetric(
                  label: 'Pagado factura',
                  value: ChileanUtils.formatCurrency(invoice.paidAmount),
                ),
              ),
              Expanded(
                child: _MiniMetric(
                  label: 'Saldo actual',
                  value: ChileanUtils.formatCurrency(remaining),
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              border: Border.all(color: const Color(0xFFFDE68A)),
              borderRadius: BorderRadius.circular(5),
            ),
            child: const Text(
              'La factura de compra conserva el reconocimiento de la obligación '
              'con el proveedor, el IVA recuperable y el valor de inventario. '
              'La recepción profesional conserva la propiedad del movimiento '
              'físico. Este pago solo cancela cuentas por pagar contra caja o '
              'banco y no mueve stock. El comprobante no acredita por sí solo '
              'una transferencia bancaria.',
              style: TextStyle(
                color: Color(0xFF92400E),
                fontSize: 10.8,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountingEvidence() {
    return FutureBuilder<DocumentAccountingContext>(
      future: _accountingFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const DocumentAccountingLoadingStrip();
        }
        if (snapshot.hasError) {
          return const _EvidenceNotice(
            icon: Icons.error_outline,
            message:
                'No se pudo cargar la evidencia contable. El pago permanece '
                'sin cambios; vuelve a intentar la consulta.',
            foreground: Color(0xFFB91C1C),
            background: Color(0xFFFEF2F2),
            border: Color(0xFFFECACA),
          );
        }

        final entries = snapshot.data?.journalEntries ??
            const <DocumentJournalEntryRecord>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DocumentJournalEntriesSection(
              entries: entries,
              documentLabel: 'Pago a proveedor',
              emptyReference: _paymentNumber(widget.payment),
            ),
            if (entries.isEmpty) ...[
              const SizedBox(height: 12),
              const _EvidenceNotice(
                icon: Icons.history_outlined,
                message:
                    'No se encontró un asiento identificado por el UUID de este '
                    'pago. Un registro histórico puede conservar un vínculo '
                    'anterior y requerir revisión contable.',
                foreground: Color(0xFF92400E),
                background: Color(0xFFFFFBEB),
                border: Color(0xFFFDE68A),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildHistory() {
    return FutureBuilder<List<PurchasePaymentEditEvent>>(
      future: _eventsFuture,
      builder: (context, snapshot) {
        final events = snapshot.data ?? const <PurchasePaymentEditEvent>[];
        return Container(
          margin: const EdgeInsets.only(top: 26),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.history_outlined,
                    size: 18,
                    color: Color(0xFF475569),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Historial de correcciones',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const Spacer(),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (snapshot.hasError)
                const Text(
                  'No se pudo cargar la trazabilidad.',
                  style: TextStyle(
                    color: Color(0xFFB91C1C),
                    fontSize: 12,
                  ),
                )
              else if (events.isEmpty)
                const Text(
                  'Este pago no registra correcciones.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12.5,
                  ),
                )
              else
                ...events.map(_buildHistoryRow),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistoryRow(PurchasePaymentEditEvent event) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(
              color: event.financialFieldsChanged
                  ? const Color(0xFFB45309)
                  : const Color(0xFF2563EB),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.reason,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${ChileanUtils.formatDateTime(event.createdAt.toLocal())} · '
                  '${event.financialFieldsChanged ? 'Corrección financiera' : 'Actualización de metadatos'}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _paymentNumber(PurchasePayment payment) {
    return PurchasePaymentReceiptPdfGenerator.paymentNumber(payment);
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF475569),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _ReceiptField extends StatelessWidget {
  const _ReceiptField({
    required this.label,
    required this.value,
    this.secondary,
  });

  final String label;
  final String value;
  final String? secondary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 238,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 9.8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF1E293B),
              fontSize: 12.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (secondary != null) ...[
            const SizedBox(height: 3),
            Text(
              secondary!,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 10.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF334155),
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _EvidenceNotice extends StatelessWidget {
  const _EvidenceNotice({
    required this.icon,
    required this.message,
    required this.foreground,
    required this.background,
    required this.border,
  });

  final IconData icon;
  final String message;
  final Color foreground;
  final Color background;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: foreground,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
