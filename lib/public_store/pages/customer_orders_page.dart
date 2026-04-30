import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/customer_account_service.dart';
import '../theme/public_store_theme.dart';
import '../../shared/utils/chilean_utils.dart';
import '../../modules/website/models/website_models.dart';
import '../widgets/customer_portal_layout.dart';
import '../widgets/public_store_layout.dart';

class CustomerOrdersPage extends StatefulWidget {
  const CustomerOrdersPage({super.key});

  @override
  State<CustomerOrdersPage> createState() => _CustomerOrdersPageState();
}

class _CustomerOrdersPageState extends State<CustomerOrdersPage>
    with AutomaticKeepAliveClientMixin {
  String? _statusFilter;

  // Keep this page alive in memory to prevent reloading on navigation
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final accountService = context.watch<CustomerAccountService>();

    final filteredOrders = _statusFilter == null
        ? accountService.orders
        : accountService.orders
            .where((o) => o.paymentStatus == _statusFilter)
            .toList();

    return CustomerPortalLayout(
      title: 'Mis Pedidos',
      headerAction: FilledButton.icon(
        onPressed: () =>
            PublicStoreLayout.navigateToHref(context, '/productos'),
        icon: const Icon(Icons.shopping_bag_outlined, size: 18),
        label: const Text('Comprar'),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF102A43),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSummary(accountService.orders.length, filteredOrders.length),
          const SizedBox(height: 18),
          _buildFilters(),
          const SizedBox(height: 18),
          if (accountService.orders.isEmpty)
            _buildEmptyState(context)
          else if (filteredOrders.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32.0),
              child: Center(child: Text('No hay pedidos con este filtro.')),
            )
          else
            _buildOrdersList(filteredOrders),
        ],
      ),
    );
  }

  Widget _buildSummary(int totalOrders, int visibleOrders) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E4EA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.receipt_long_outlined,
              color: Color(0xFF102A43), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$visibleOrders de $totalOrders pedidos',
                  style: const TextStyle(
                    color: Color(0xFF18212F),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Revisa pagos, productos y el detalle de cada compra.',
                  style: TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    const filters = [
      (label: 'Todos', value: null),
      (label: 'Pendientes', value: 'pending'),
      (label: 'Pagados', value: 'approved'),
      (label: 'Cancelados', value: 'cancelled'),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: filters.map((filter) {
        final selected = _statusFilter == filter.value;
        return ChoiceChip(
          label: Text(filter.label),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => setState(() => _statusFilter = filter.value),
          selectedColor: const Color(0xFF102A43),
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFE0E4EA)),
          labelStyle: TextStyle(
            color: selected ? Colors.white : const Color(0xFF344054),
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        );
      }).toList(),
    );
  }

  Widget _buildOrdersList(List<OnlineOrder> orders) {
    return Column(
      children: orders.map((order) => _OrderCard(order: order)).toList(),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E4EA)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.shopping_bag_outlined,
                size: 48, color: Colors.grey[400]),
          ),
          const SizedBox(height: 16),
          Text(
            'No tienes pedidos aún',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800]),
          ),
          const SizedBox(height: 8),
          Text(
            'Tus compras aparecerán aquí',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: () =>
                PublicStoreLayout.navigateToHref(context, '/productos'),
            icon: const Icon(Icons.shopping_bag_outlined, size: 18),
            label: const Text('Ver productos'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF102A43),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
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

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E4EA)),
      ),
      child: InkWell(
        onTap: () => _showOrderDetails(context, order),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color:
                          (statusInfo['color'] as Color).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(statusInfo['icon'] as IconData,
                        color: statusInfo['color'] as Color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Pedido #${order.orderNumber}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              ChileanUtils.formatCurrency(order.total),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: PublicStoreTheme.primaryBlue,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('dd MMM yyyy, HH:mm')
                              .format(order.createdAt),
                          style:
                              TextStyle(fontSize: 13, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${order.items.length} producto(s)',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color:
                          (statusInfo['color'] as Color).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      statusInfo['label'] as String,
                      style: TextStyle(
                        color: statusInfo['color'] as Color,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
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

  Map<String, dynamic> _getStatusInfo(String status) {
    switch (status) {
      case 'approved':
      case 'paid':
        return {
          'label': 'PAGADO',
          'color': Colors.green, // More vivid green
          'icon': Icons.check_circle_outline,
        };
      case 'pending':
        return {
          'label': 'PENDIENTE',
          'color': Colors.orange,
          'icon': Icons.schedule,
        };
      case 'cancelled':
      case 'rejected':
        return {
          'label': 'CANCELADO',
          'color': Colors.red,
          'icon': Icons.cancel_outlined,
        };
      case 'processing':
        return {
          'label': 'EN PROCESO',
          'color': Colors.blue,
          'icon': Icons.sync,
        };
      case 'shipped':
        return {
          'label': 'ENVIADO',
          'color': Colors.purple,
          'icon': Icons.local_shipping_outlined,
        };
      case 'delivered':
        return {
          'label': 'ENTREGADO',
          'color': Colors.green,
          'icon': Icons.task_alt,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 500,
          constraints: const BoxConstraints(maxHeight: 700),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Pedido #${order.orderNumber}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.separated(
                  itemCount: order.items.length,
                  separatorBuilder: (_, __) => const Divider(height: 24),
                  itemBuilder: (context, index) {
                    final item = order.items[index];
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.shopping_bag_outlined,
                              color: Colors.grey),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.productName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text('Cant: ${item.quantity}',
                                  style: TextStyle(
                                      color: Colors.grey[600], fontSize: 13)),
                            ],
                          ),
                        ),
                        Text(
                          ChileanUtils.formatCurrency(item.unitPrice),
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          ChileanUtils.formatCurrency(order.total),
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: PublicStoreTheme.primaryBlue),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
