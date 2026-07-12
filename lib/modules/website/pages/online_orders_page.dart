import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/safe_layout_builder.dart';
import '../services/website_service.dart';
import '../models/website_models.dart';

/// Page for managing online orders from the website
class OnlineOrdersPage extends StatefulWidget {
  const OnlineOrdersPage({
    super.key,
    this.embedded = false,
  });

  final bool embedded;

  @override
  State<OnlineOrdersPage> createState() => _OnlineOrdersPageState();
}

class _OnlineOrdersPageState extends State<OnlineOrdersPage> {
  String _selectedStatus = 'all';
  String _selectedPaymentStatus = 'all';

  Future<void> _handleCancellation(
    OnlineOrder order,
    WebsiteService websiteService,
  ) async {
    if (order.paymentStatus == 'paid' || order.paidAt != null) {
      if (!mounted) return;
      final openInvoice = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.account_balance_wallet_outlined),
          title: const Text('Este pedido ya tiene un pago'),
          content: Text(
            order.salesInvoiceId == null
                ? 'No se cancelará ni se marcará un reembolso automáticamente. '
                    'Primero debe existir una factura para registrar la devolución, '
                    'la nota de crédito y el reembolso con trazabilidad.'
                : 'No se cancelará ni se marcará un reembolso automáticamente. '
                    'Abra la factura y use Correcciones para registrar la devolución, '
                    'la nota de crédito y el reembolso sin perder evidencia.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cerrar'),
            ),
            if (order.salesInvoiceId != null)
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.receipt_long),
                label: const Text('Abrir factura'),
              ),
          ],
        ),
      );
      if (openInvoice == true && mounted && order.salesInvoiceId != null) {
        context.go('/sales/invoices/${order.salesInvoiceId}');
      }
      return;
    }

    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.cancel_outlined),
        title: Text('Cancelar pedido ${order.orderNumber}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'La factura vinculada se conservará como cancelada. Si ya había '
              'descontado stock, el sistema lo restaurará y dejará la operación '
              'conectada a sus movimientos y evidencia contable.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Motivo obligatorio',
                hintText: 'Ej.: cliente desistió antes del pago',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Esta acción no registra ni ejecuta un reembolso de dinero.',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () {
              final value = reasonController.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Cancelar pedido'),
          ),
        ],
      ),
    );
    reasonController.dispose();
    if (reason == null || !mounted) return;

    try {
      final result = await websiteService.cancelOrder(
        order.id,
        reason: reason,
        refundAmount: 0,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result?['message']?.toString() ??
                'Pedido cancelado con su evidencia preservada.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo cancelar: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _handlePaymentConfirmation(
    OnlineOrder order,
    WebsiteService websiteService,
  ) async {
    final referenceController = TextEditingController();
    var selectedDate = DateTime.now();
    final input = await showDialog<_ManualPaymentConfirmationInput>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          icon: const Icon(Icons.account_balance_outlined),
          title: Text('Confirmar pago ${order.orderNumber}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Se registrará un pago por ${ChileanUtils.formatCurrency(order.total)} '
                'y la factura descontará el inventario una sola vez.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: referenceController,
                autofocus: true,
                onChanged: (_) => setDialogState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Referencia bancaria obligatoria',
                  hintText: 'Ej.: transferencia BCI 123456',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.tag),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_outlined),
                title: const Text('Fecha efectiva del pago'),
                subtitle: Text(ChileanUtils.formatDate(selectedDate)),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: () async {
                  final today = DateTime.now();
                  final picked = await showDatePicker(
                    context: dialogContext,
                    initialDate: selectedDate,
                    firstDate: DateTime(order.createdAt.year),
                    lastDate: DateTime(today.year, today.month, today.day),
                  );
                  if (picked != null) {
                    setDialogState(() => selectedDate = picked);
                  }
                },
              ),
              Text(
                'Confirme únicamente después de verificar el abono en el banco.',
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Volver'),
            ),
            FilledButton.icon(
              onPressed: referenceController.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(
                        dialogContext,
                        _ManualPaymentConfirmationInput(
                          reference: referenceController.text.trim(),
                          date: selectedDate,
                        ),
                      ),
              icon: const Icon(Icons.verified_outlined),
              label: const Text('Registrar pago'),
            ),
          ],
        ),
      ),
    );
    referenceController.dispose();
    if (input == null || !mounted) return;

    try {
      final paymentId = await websiteService.confirmOrderPayment(
        order.id,
        paymentReference: input.reference,
        paymentDate: input.date,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            paymentId == null
                ? 'El pedido ya estaba pagado; no se duplicó el cobro.'
                : 'Pago registrado con trazabilidad completa.',
          ),
          action: order.salesInvoiceId == null
              ? null
              : SnackBarAction(
                  label: 'Ver factura',
                  onPressed: () =>
                      context.go('/sales/invoices/${order.salesInvoiceId}'),
                ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo confirmar el pago: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    // Lazy load orders when this page opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WebsiteService>().initializeOrders();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final websiteService = context.watch<WebsiteService>();

    final orders = websiteService.orders.where((order) {
      if (_selectedStatus != 'all' && order.status != _selectedStatus) {
        return false;
      }
      if (_selectedPaymentStatus != 'all' &&
          order.paymentStatus != _selectedPaymentStatus) {
        return false;
      }
      return true;
    }).toList();

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (!widget.embedded) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.go('/website'),
                ),
                const SizedBox(width: 8),
              ],
              Text('Pedidos Online',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => websiteService.loadOrders(),
                tooltip: 'Actualizar',
              ),
            ],
          ),
        ),
        // Filters
        Container(
          padding: const EdgeInsets.all(16),
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: ConstraintLayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 600) {
                // Mobile
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _selectedStatus,
                      decoration: const InputDecoration(
                        labelText: 'Estado del Pedido',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('Todos')),
                        DropdownMenuItem(
                            value: 'pending', child: Text('Pendiente')),
                        DropdownMenuItem(
                            value: 'confirmed', child: Text('Confirmado')),
                        DropdownMenuItem(
                            value: 'processing', child: Text('En Proceso')),
                        DropdownMenuItem(
                            value: 'shipped', child: Text('Enviado')),
                        DropdownMenuItem(
                            value: 'delivered', child: Text('Entregado')),
                        DropdownMenuItem(
                            value: 'cancelled', child: Text('Cancelado')),
                      ],
                      onChanged: (value) {
                        setState(() => _selectedStatus = value ?? 'all');
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedPaymentStatus,
                      decoration: const InputDecoration(
                        labelText: 'Estado de Pago',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('Todos')),
                        DropdownMenuItem(
                            value: 'pending', child: Text('Pendiente')),
                        DropdownMenuItem(value: 'paid', child: Text('Pagado')),
                        DropdownMenuItem(
                            value: 'failed', child: Text('Fallido')),
                        DropdownMenuItem(
                            value: 'refunded', child: Text('Reembolsado')),
                      ],
                      onChanged: (value) {
                        setState(() => _selectedPaymentStatus = value ?? 'all');
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${orders.length} pedidos encontrados',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                );
              }

              // Desktop
              return Row(
                children: [
                  const Text('Estado: '),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _selectedStatus,
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('Todos')),
                      DropdownMenuItem(
                          value: 'pending', child: Text('Pendiente')),
                      DropdownMenuItem(
                          value: 'confirmed', child: Text('Confirmado')),
                      DropdownMenuItem(
                          value: 'processing', child: Text('En Proceso')),
                      DropdownMenuItem(
                          value: 'shipped', child: Text('Enviado')),
                      DropdownMenuItem(
                          value: 'delivered', child: Text('Entregado')),
                      DropdownMenuItem(
                          value: 'cancelled', child: Text('Cancelado')),
                    ],
                    onChanged: (value) {
                      setState(() => _selectedStatus = value ?? 'all');
                    },
                  ),
                  const SizedBox(width: 24),
                  const Text('Pago: '),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _selectedPaymentStatus,
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('Todos')),
                      DropdownMenuItem(
                          value: 'pending', child: Text('Pendiente')),
                      DropdownMenuItem(value: 'paid', child: Text('Pagado')),
                      DropdownMenuItem(value: 'failed', child: Text('Fallido')),
                      DropdownMenuItem(
                          value: 'refunded', child: Text('Reembolsado')),
                    ],
                    onChanged: (value) {
                      setState(() => _selectedPaymentStatus = value ?? 'all');
                    },
                  ),
                  const Spacer(),
                  Text(
                    '${orders.length} pedidos',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              );
            },
          ),
        ),

        // Orders List
        Expanded(
          child: websiteService.isLoading
              ? const Center(child: BrandedLoading())
              : orders.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shopping_bag_outlined,
                              size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No hay pedidos online',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: orders.length,
                      itemBuilder: (context, index) {
                        final order = orders[index];
                        return _buildOrderCard(context, order);
                      },
                    ),
        ),
      ],
    );

    if (widget.embedded) return body;

    return MainLayout(child: body);
  }

  Widget _buildOrderCard(BuildContext context, OnlineOrder order) {
    final theme = Theme.of(context);
    final websiteService = context.read<WebsiteService>();

    final statusColor = _getStatusColor(order.status);
    final paymentStatusColor = _getPaymentStatusColor(order.paymentStatus);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.orderNumber,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        order.customerName,
                        style: theme.textTheme.bodyMedium,
                      ),
                      Text(
                        order.customerEmail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: statusColor),
                      ),
                      child: Text(
                        order.statusDisplayName,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: paymentStatusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: paymentStatusColor),
                      ),
                      child: Text(
                        order.paymentStatusDisplayName,
                        style: TextStyle(
                          color: paymentStatusColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const Divider(height: 24),

            // Order Details
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailRow(
                        icon: Icons.calendar_today,
                        label: 'Fecha',
                        value: ChileanUtils.formatDate(order.createdAt),
                      ),
                      if (order.items.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _buildDetailRow(
                          icon: Icons.inventory_2,
                          label: 'Productos',
                          value: '${order.items.length} items',
                        ),
                      ],
                      if (order.trackingNumber != null) ...[
                        const SizedBox(height: 8),
                        _buildDetailRow(
                          icon: Icons.local_shipping,
                          label: 'Seguimiento',
                          value: order.trackingNumber!,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Total',
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      ChileanUtils.formatCurrency(order.total),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            if (order.customerNotes != null &&
                order.customerNotes!.isNotEmpty) ...[
              const Divider(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.comment, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      order.customerNotes!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // Actions
            const SizedBox(height: 16),
            Row(
              children: [
                if (order.status == 'pending')
                  ElevatedButton.icon(
                    onPressed: () async {
                      await websiteService.updateOrderStatus(
                          order.id, 'confirmed');
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Pedido confirmado')),
                        );
                      }
                    },
                    icon: const Icon(Icons.check),
                    label: const Text('Confirmar'),
                  ),
                const SizedBox(width: 8),
                if (order.salesInvoiceId == null &&
                    order.paymentStatus == 'paid')
                  ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        final invoiceId =
                            await websiteService.processOrder(order.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Factura creada: $invoiceId'),
                              action: SnackBarAction(
                                label: 'Ver',
                                onPressed: () {
                                  context.go('/sales/invoices/$invoiceId');
                                },
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.receipt),
                    label: const Text('Crear Factura'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                  ),
                if (order.salesInvoiceId != null &&
                    order.status != 'cancelled' &&
                    order.paymentStatus != 'paid' &&
                    order.paymentStatus != 'refunded' &&
                    const {'transfer', 'transferencia', 'bank_transfer'}
                        .contains(order.paymentMethod?.toLowerCase())) ...[
                  FilledButton.icon(
                    onPressed: () =>
                        _handlePaymentConfirmation(order, websiteService),
                    icon: const Icon(Icons.account_balance),
                    label: const Text('Confirmar pago'),
                  ),
                  const SizedBox(width: 8),
                ],
                if (order.salesInvoiceId != null)
                  OutlinedButton.icon(
                    onPressed: () {
                      context.go('/sales/invoices/${order.salesInvoiceId}');
                    },
                    icon: const Icon(Icons.receipt),
                    label: const Text('Ver Factura'),
                  ),
                const Spacer(),
                if (order.status != 'cancelled')
                  PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'cancel') {
                        await _handleCancellation(order, websiteService);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'cancel',
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.cancel, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              order.paymentStatus == 'paid'
                                  ? 'Gestionar devolución / crédito'
                                  : 'Cancelar pedido',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[600],
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'confirmed':
        return Colors.blue;
      case 'processing':
        return Colors.purple;
      case 'shipped':
        return Colors.indigo;
      case 'delivered':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _getPaymentStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'paid':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'refunded':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }
}

class _ManualPaymentConfirmationInput {
  const _ManualPaymentConfirmationInput({
    required this.reference,
    required this.date,
  });

  final String reference;
  final DateTime date;
}
