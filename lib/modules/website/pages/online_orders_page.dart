import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../services/website_service.dart';
import '../models/website_models.dart';

/// Page for managing online orders from the website
class OnlineOrdersPage extends StatefulWidget {
  const OnlineOrdersPage({super.key});

  @override
  State<OnlineOrdersPage> createState() => _OnlineOrdersPageState();
}

class _OnlineOrdersPageState extends State<OnlineOrdersPage> {
  String _selectedStatus = 'all';
  String _selectedPaymentStatus = 'all';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final websiteService = context.watch<WebsiteService>();

    final orders = websiteService.orders.where((order) {
      if (_selectedStatus != 'all' && order.status != _selectedStatus) {
        return false;
      }
      if (_selectedPaymentStatus != 'all' && order.paymentStatus != _selectedPaymentStatus) {
        return false;
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Pedidos Online'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => websiteService.loadOrders(),
            tooltip: 'Actualizar',
          ),
        ],
      ),
        body: Column(
          children: [
            // Filters
            Container(
              padding: const EdgeInsets.all(16),
              color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
              child: Row(
                children: [
                  const Text('Estado: '),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _selectedStatus,
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('Todos')),
                      DropdownMenuItem(value: 'pending', child: Text('Pendiente')),
                      DropdownMenuItem(value: 'confirmed', child: Text('Confirmado')),
                      DropdownMenuItem(value: 'processing', child: Text('En Proceso')),
                      DropdownMenuItem(value: 'shipped', child: Text('Enviado')),
                      DropdownMenuItem(value: 'delivered', child: Text('Entregado')),
                      DropdownMenuItem(value: 'cancelled', child: Text('Cancelado')),
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
                      DropdownMenuItem(value: 'pending', child: Text('Pendiente')),
                      DropdownMenuItem(value: 'paid', child: Text('Pagado')),
                      DropdownMenuItem(value: 'failed', child: Text('Fallido')),
                      DropdownMenuItem(value: 'refunded', child: Text('Reembolsado')),
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
              ),
            ),

            // Orders List
            Expanded(
              child: websiteService.isLoading
                  ? const Center(child: CircularProgressIndicator())
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
        ),
    );
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
                        color: statusColor.withOpacity(0.1),
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
                        color: paymentStatusColor.withOpacity(0.1),
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

            if (order.customerNotes != null && order.customerNotes!.isNotEmpty) ...[
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
                      await websiteService.updateOrderStatus(order.id, 'confirmed');
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
                        final invoiceId = await websiteService.processOrder(order.id);
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
                if (order.salesInvoiceId != null)
                  OutlinedButton.icon(
                    onPressed: () {
                      context.go('/sales/invoices/${order.salesInvoiceId}');
                    },
                    icon: const Icon(Icons.receipt),
                    label: const Text('Ver Factura'),
                  ),
                const Spacer(),
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'cancel') {
                      await websiteService.updateOrderStatus(order.id, 'cancelled');
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'cancel',
                      child: Row(
                        children: [
                          Icon(Icons.cancel, size: 16),
                          SizedBox(width: 8),
                          Text('Cancelar Pedido'),
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
