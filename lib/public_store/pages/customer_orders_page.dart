import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/customer_account_service.dart';
import '../theme/public_store_theme.dart';
import '../../shared/utils/chilean_utils.dart';
import '../../modules/website/models/website_models.dart';

class CustomerOrdersPage extends StatefulWidget {
  const CustomerOrdersPage({super.key});

  @override
  State<CustomerOrdersPage> createState() => _CustomerOrdersPageState();
}

class _CustomerOrdersPageState extends State<CustomerOrdersPage> {
  String? _statusFilter;

  @override
  Widget build(BuildContext context) {
    final accountService = context.watch<CustomerAccountService>();

    final filteredOrders = _statusFilter == null
        ? accountService.orders
        : accountService.orders
            .where((o) => o.paymentStatus == _statusFilter)
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Pedidos'),
        actions: [
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filtrar por estado',
            onSelected: (value) => setState(() => _statusFilter = value),
            itemBuilder: (context) => [
              const PopupMenuItem(value: null, child: Text('Todos')),
              const PopupMenuItem(value: 'pending', child: Text('Pendientes')),
              const PopupMenuItem(value: 'approved', child: Text('Pagados')),
              const PopupMenuItem(value: 'cancelled', child: Text('Cancelados')),
            ],
          ),
        ],
      ),
      body: accountService.orders.isEmpty
          ? _buildEmptyState(context)
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filteredOrders.length,
              itemBuilder: (context, index) {
                final order = filteredOrders[index];
                return _OrderCard(order: order);
              },
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_bag_outlined, size: 64),
          SizedBox(height: 16),
          Text('No tienes pedidos aún'),
          SizedBox(height: 8),
          Text('Tus compras aparecerán aquí'),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final OnlineOrder order;

  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final status = order.paymentStatus;
    final statusInfo = _getStatusInfo(status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showOrderDetails(context, order),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(statusInfo['icon'] as IconData, color: statusInfo['color'] as Color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pedido #${order.orderNumber}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          DateFormat('dd/MM/yyyy HH:mm').format(order.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusInfo['color'] as Color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      statusInfo['label'] as String,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Text(
                '${order.items.length} producto${order.items.length != 1 ? 's' : ''}',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total:',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    ChileanUtils.formatCurrency(order.total),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: PublicStoreTheme.primaryBlue,
                    ),
                  ),
                ],
              ),
              if (order.customerAddress != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 16),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        order.customerAddress!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _getStatusInfo(String status) {
    switch (status) {
      case 'approved':
      case 'paid':
        return {
          'label': 'PAGADO',
          'color': PublicStoreTheme.success,
          'icon': Icons.check_circle,
        };
      case 'pending':
        return {
          'label': 'PENDIENTE',
          'color': PublicStoreTheme.warning,
          'icon': Icons.access_time,
        };
      case 'cancelled':
      case 'rejected':
        return {
          'label': 'CANCELADO',
          'color': PublicStoreTheme.error,
          'icon': Icons.cancel,
        };
      case 'processing':
        return {
          'label': 'PROCESANDO',
          'color': Colors.blue,
          'icon': Icons.sync,
        };
      case 'shipped':
        return {
          'label': 'ENVIADO',
          'color': Colors.purple,
          'icon': Icons.local_shipping,
        };
      case 'delivered':
        return {
          'label': 'ENTREGADO',
          'color': PublicStoreTheme.success,
          'icon': Icons.done_all,
        };
      default:
        return {
          'label': status.toUpperCase(),
          'color': Colors.grey,
          'icon': Icons.help_outline,
        };
    }
  }

  void _showOrderDetails(BuildContext context, OnlineOrder order) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: 600,
          constraints: const BoxConstraints(maxHeight: 700),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Pedido #${order.orderNumber}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 16),
              Text(
                'Estado: ${_getStatusInfo(order.paymentStatus)['label']}',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Fecha: ${DateFormat('dd/MM/yyyy HH:mm').format(order.createdAt)}',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              const Text(
                'Productos:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: order.items.length,
                  itemBuilder: (context, index) {
                    final item = order.items[index];
                    return ListTile(
                      leading: const Icon(Icons.shopping_bag_outlined),
                      title: Text(item.productName),
                      subtitle: Text('Cantidad: ${item.quantity}'),
                      trailing: Text(
                        ChileanUtils.formatCurrency(item.unitPrice),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    );
                  },
                ),
              ),
              const Divider(),
              const SizedBox(height: 12),
              if (order.customerAddress != null) ...[
                const Text(
                  'Dirección de envío:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(order.customerAddress!),
                const SizedBox(height: 16),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total:',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    ChileanUtils.formatCurrency(order.total),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: PublicStoreTheme.primaryBlue,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
