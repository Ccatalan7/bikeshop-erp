import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/themes/app_theme.dart';
import '../models/sales_models.dart';
import '../services/sales_service.dart';

class InvoiceDetailPage extends StatefulWidget {
  const InvoiceDetailPage({
    super.key,
    required this.invoiceId,
    this.openPaymentOnLoad = false,
  });

  final String invoiceId;
  final bool openPaymentOnLoad;

  @override
  State<InvoiceDetailPage> createState() => _InvoiceDetailPageState();
}

class _InvoiceDetailPageState extends State<InvoiceDetailPage> {
  bool _isLoading = true;
  bool _didRequestPayments = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadInvoice();
      if (!mounted) return;
      if (widget.openPaymentOnLoad) {
        _openPaymentForm();
      }
    });
  }

  Future<void> _loadInvoice() async {
    final salesService = context.read<SalesService>();
    await salesService.fetchInvoice(widget.invoiceId, refresh: true);
    if (!_didRequestPayments) {
      await salesService.loadPayments(forceRefresh: true);
      _didRequestPayments = true;
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Invoice? _findInvoice(SalesService service) {
    for (final invoice in service.invoices) {
      if (invoice.id == widget.invoiceId) {
        return invoice;
      }
    }
    return null;
  }

  void _closePage() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop();
      } else {
        context.go('/sales/invoices');
      }
    });
  }

  Future<void> _openPaymentForm() async {
    final salesService = context.read<SalesService>();
    final invoice = _findInvoice(salesService);
    if (invoice == null || invoice.balance <= 0) {
      return;
    }

    final didRegisterPayment = await context.push<bool>(
          '/sales/invoices/${invoice.id}/payment',
        ) ??
        false;

    if (didRegisterPayment) {
      await _loadInvoice();
    }
  }

  Future<void> _markAsSent() async {
    try {
      final salesService = context.read<SalesService>();
      await salesService.updateInvoiceStatus(
          widget.invoiceId, InvoiceStatus.sent);
      await _loadInvoice();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Factura marcada como enviada')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('No se pudo actualizar el estado: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _markAsConfirmed() async {
    try {
      final salesService = context.read<SalesService>();
      await salesService.updateInvoiceStatus(
          widget.invoiceId, InvoiceStatus.confirmed);
      await _loadInvoice();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Factura confirmada - contabilizada')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('No se pudo confirmar la factura: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _revertToDraft() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revertir a borrador'),
        content: const Text(
          'Esto eliminará el asiento contable y restaurará el inventario. '
          '¿Está seguro?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revertir'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final salesService = context.read<SalesService>();
      await salesService.updateInvoiceStatus(
          widget.invoiceId, InvoiceStatus.draft);
      await _loadInvoice();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Factura revertida a borrador')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('No se pudo revertir: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _revertToSent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revertir a enviada'),
        content: const Text(
          'Esto eliminará el asiento contable y restaurará el inventario. '
          '¿Está seguro?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revertir'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final salesService = context.read<SalesService>();
      await salesService.updateInvoiceStatus(
          widget.invoiceId, InvoiceStatus.sent);
      await _loadInvoice();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Factura revertida a enviada')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('No se pudo revertir: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _undoLastPayment() async {
    final salesService = context.read<SalesService>();
    final invoice = _findInvoice(salesService);
    if (invoice == null) return;

    // Get the most recent payment for this invoice
    final payments = salesService.payments
        .where((p) => p.invoiceId == invoice.id)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    if (payments.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay pagos para deshacer')),
      );
      return;
    }

    final lastPayment = payments.first;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deshacer pago'),
        content: Text(
          'Se eliminará el pago de ${ChileanUtils.formatCurrency(lastPayment.amount)} '
          'y su asiento contable asociado. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar pago'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await salesService.deletePayment(lastPayment.id!);
      await _loadInvoice();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pago eliminado correctamente'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo eliminar el pago: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showPaymentDetails(Payment payment) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Detalle del pago'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Monto', ChileanUtils.formatCurrency(payment.amount)),
              const SizedBox(height: 12),
              _buildDetailRow('Método', payment.method.displayName),
              const SizedBox(height: 12),
              _buildDetailRow('Fecha', ChileanUtils.formatDate(payment.date)),
              if (payment.reference != null && payment.reference!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildDetailRow('Referencia', payment.reference!),
              ],
              if (payment.notes != null && payment.notes!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildDetailRow('Notas', payment.notes!),
              ],
              if (payment.invoiceReference != null) ...[
                const SizedBox(height: 12),
                _buildDetailRow('Factura', payment.invoiceReference!),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await _confirmDeletePayment(payment);
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Eliminar'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Text(value),
        ),
      ],
    );
  }

  Future<void> _confirmDeletePayment(Payment payment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar pago'),
        content: Text(
          'Se eliminará el pago de ${ChileanUtils.formatCurrency(payment.amount)} '
          'y su asiento contable asociado. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final salesService = context.read<SalesService>();
      await salesService.deletePayment(payment.id!);
      await _loadInvoice();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pago eliminado correctamente'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo eliminar el pago: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final salesService = context.watch<SalesService>();
    final invoice = _findInvoice(salesService);

    return MainLayout(
      child: _isLoading && invoice == null
          ? const Center(child: CircularProgressIndicator())
          : invoice == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.receipt_long, size: 64),
                      const SizedBox(height: 16),
                      const Text('Factura no encontrada'),
                      const SizedBox(height: 16),
                      AppButton(
                        text: 'Volver',
                        onPressed: _closePage,
                      ),
                    ],
                  ),
                )
              : _buildContent(context, invoice, salesService),
    );
  }

  Widget _buildContent(
      BuildContext context, Invoice invoice, SalesService service) {
    final payments = service.getPaymentsForInvoice(invoice.id ?? '');
    return Column(
      children: [
        _buildHeader(invoice),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildSummary(invoice),
                  const SizedBox(height: 16),
                  _buildItems(invoice),
                  const SizedBox(height: 16),
                  _buildPayments(payments),
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(Invoice invoice) {
    final isMobile = AppTheme.isMobile(context);
    
    return Padding(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(onPressed: _closePage, icon: const Icon(Icons.arrow_back)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invoice.invoiceNumber.isNotEmpty
                          ? 'Factura ${invoice.invoiceNumber}'
                          : 'Factura',
                      style: TextStyle(
                        fontSize: isMobile ? 18 : 24,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      invoice.customerName ?? 'Cliente',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isMobile) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (invoice.status == InvoiceStatus.draft)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _markAsSent,
                      icon: const Icon(Icons.send_outlined, size: 18),
                      label: const Text('Marcar como enviada'),
                    ),
                  ),
                if (invoice.status == InvoiceStatus.sent) ...[
                  SizedBox(
                    width: (MediaQuery.of(context).size.width - 52) / 2,
                    child: OutlinedButton.icon(
                      onPressed: _revertToDraft,
                      icon: const Icon(Icons.undo, size: 18),
                      label: const Text('Borrador'),
                    ),
                  ),
                  SizedBox(
                    width: (MediaQuery.of(context).size.width - 52) / 2,
                    child: FilledButton.icon(
                      onPressed: _markAsConfirmed,
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('Confirmar'),
                      style: FilledButton.styleFrom(backgroundColor: Colors.green),
                    ),
                  ),
                ],
                if (invoice.balance > 0 && invoice.status == InvoiceStatus.confirmed)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _openPaymentForm,
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      label: const Text('Pagar factura'),
                    ),
                  ),
                if (invoice.status == InvoiceStatus.confirmed && invoice.balance > 0)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _revertToSent,
                      icon: const Icon(Icons.undo, size: 18),
                      label: const Text('Revertir a Enviada'),
                    ),
                  ),
                if (invoice.status == InvoiceStatus.paid)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _undoLastPayment,
                      icon: const Icon(Icons.undo, size: 18),
                      label: const Text('Deshacer último pago'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      context.push('/sales/invoices/${invoice.id}/edit');
                    },
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Editar'),
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (invoice.balance > 0 && invoice.status == InvoiceStatus.confirmed)
                  OutlinedButton.icon(
                    onPressed: _openPaymentForm,
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Pagar factura'),
                  ),
                OutlinedButton.icon(
                  onPressed: () {
                    context.push('/sales/invoices/${invoice.id}/edit');
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar'),
                ),
                if (invoice.status == InvoiceStatus.draft)
                  FilledButton.icon(
                    onPressed: _markAsSent,
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('Marcar como enviada'),
                  ),
                if (invoice.status == InvoiceStatus.sent) ...[
                  OutlinedButton.icon(
                    onPressed: _revertToDraft,
                    icon: const Icon(Icons.undo),
                    label: const Text('Volver a borrador'),
                  ),
                  FilledButton.icon(
                    onPressed: _markAsConfirmed,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Confirmar'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.green),
                  ),
                ],
                if (invoice.status == InvoiceStatus.confirmed && invoice.balance > 0)
                  OutlinedButton.icon(
                    onPressed: _revertToSent,
                    icon: const Icon(Icons.undo),
                    label: const Text('Volver a enviada'),
                  ),
                if (invoice.status == InvoiceStatus.paid)
                  OutlinedButton.icon(
                    onPressed: _undoLastPayment,
                    icon: const Icon(Icons.undo),
                    label: const Text('Deshacer pago'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummary(Invoice invoice) {
    final theme = Theme.of(context);
    final isMobile = AppTheme.isMobile(context);
    Color statusColor;
    String statusText;

    switch (invoice.status) {
      case InvoiceStatus.draft:
        statusColor = Colors.grey;
        statusText = 'Borrador';
        break;
      case InvoiceStatus.sent:
        statusColor = Colors.blue;
        statusText = 'Enviada';
        break;
      case InvoiceStatus.confirmed:
        statusColor = Colors.purple;
        statusText = 'Confirmada';
        break;
      case InvoiceStatus.paid:
        statusColor = Colors.green;
        statusText = 'Pagada';
        break;
      case InvoiceStatus.overdue:
        statusColor = Colors.red;
        statusText = 'Vencida';
        break;
      case InvoiceStatus.cancelled:
        statusColor = Colors.orange;
        statusText = 'Cancelada';
        break;
    }

    return Card(
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    statusText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Total: ${ChileanUtils.formatCurrency(invoice.total)}',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Pagado: ${ChileanUtils.formatCurrency(invoice.paidAmount)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Saldo: ${ChileanUtils.formatCurrency(invoice.balance)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: invoice.balance <= 0
                              ? Colors.green
                              : Colors.orange[800],
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: isMobile ? 12 : 16),
            Wrap(
              spacing: isMobile ? 8 : 16,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today, size: 16),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Emisión: ${ChileanUtils.formatDate(invoice.date)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (invoice.dueDate != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule, size: 16),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Venc: ${ChileanUtils.formatDate(invoice.dueDate!)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            if (invoice.reference != null && invoice.reference!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Referencia: ${invoice.reference}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildItems(Invoice invoice) {
    if (invoice.items.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('Esta factura no tiene ítems asociados.')),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Detalle de ítems',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: invoice.items.length,
              separatorBuilder: (_, __) => const Divider(height: 16),
              itemBuilder: (context, index) {
                final item = invoice.items[index];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.productName ?? item.productSku ?? 'Producto',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                              '${item.quantity.toStringAsFixed(0)} x ${ChileanUtils.formatCurrency(item.unitPrice)}'),
                        ],
                      ),
                    ),
                    Text(ChileanUtils.formatCurrency(item.lineTotal)),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPayments(List<Payment> payments) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Pagos registrados',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (payments.isNotEmpty)
                  Text('${payments.length} en total',
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 12),
            if (payments.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('Aún no hay pagos asociados.')),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: payments.length,
                separatorBuilder: (_, __) => const Divider(height: 16),
                itemBuilder: (context, index) {
                  final payment = payments[index];
                  return InkWell(
                    onTap: () => _showPaymentDetails(payment),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ChileanUtils.formatCurrency(payment.amount),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                    '${payment.method.displayName} · ${ChileanUtils.formatDate(payment.date)}'),
                                if (payment.reference != null &&
                                    payment.reference!.isNotEmpty)
                                  Text('Ref: ${payment.reference}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
