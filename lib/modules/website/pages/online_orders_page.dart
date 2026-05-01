import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../messaging/providers/chat_provider.dart';
import '../../messaging/services/messaging_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/safe_layout_builder.dart';
import '../models/website_models.dart';
import '../services/website_service.dart';

/// Operational inbox for website orders.
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
  static const Color _accentBlue = Color(0xFF093357);
  static const Color _borderColor = Color(0xFFE5E7EB);
  static const Color _softSurface = Color(0xFFF8FAFC);
  static const double _desktopBreakpoint = 980;

  final TextEditingController _searchController = TextEditingController();

  String _selectedStatus = 'all';
  String _selectedPaymentStatus = 'all';
  String _searchQuery = '';
  String? _selectedOrderId;
  String? _busyOrderId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WebsiteService>().initializeOrders();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final websiteService = context.watch<WebsiteService>();
    final allOrders = websiteService.orders;
    final filteredOrders = _filterOrders(allOrders);
    final selectedOrder = _resolveSelectedOrder(filteredOrders);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context, websiteService, allOrders),
        _buildSummaryStrip(allOrders),
        _buildToolbar(filteredOrders.length),
        Expanded(
          child: websiteService.isLoading && allOrders.isEmpty
              ? const Center(child: BrandedLoading())
              : filteredOrders.isEmpty
                  ? _buildEmptyState()
                  : ConstraintLayoutBuilder(
                      builder: (context, constraints) {
                        final isDesktop =
                            constraints.maxWidth >= _desktopBreakpoint;

                        if (!isDesktop) {
                          return _buildMobileOrdersList(
                            context,
                            websiteService,
                            filteredOrders,
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: 430,
                              child: _buildOrdersList(
                                context,
                                filteredOrders,
                                selectedOrder,
                              ),
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(
                              child: selectedOrder == null
                                  ? _buildNoSelectionState()
                                  : _buildOrderInspector(
                                      context,
                                      websiteService,
                                      selectedOrder,
                                    ),
                            ),
                          ],
                        );
                      },
                    ),
        ),
      ],
    );

    if (widget.embedded) return body;
    return MainLayout(child: body);
  }

  List<OnlineOrder> _filterOrders(List<OnlineOrder> orders) {
    final query = _searchQuery.trim().toLowerCase();

    return orders.where((order) {
      if (_selectedStatus != 'all' && order.status != _selectedStatus) {
        return false;
      }
      if (_selectedPaymentStatus != 'all' &&
          order.paymentStatus != _selectedPaymentStatus) {
        return false;
      }
      if (query.isEmpty) return true;

      return order.orderNumber.toLowerCase().contains(query) ||
          order.customerName.toLowerCase().contains(query) ||
          order.customerEmail.toLowerCase().contains(query) ||
          (order.customerPhone ?? '').toLowerCase().contains(query);
    }).toList();
  }

  OnlineOrder? _resolveSelectedOrder(List<OnlineOrder> orders) {
    if (orders.isEmpty) return null;

    final selectedId = _selectedOrderId;
    if (selectedId != null) {
      for (final order in orders) {
        if (order.id == selectedId) return order;
      }
    }

    return orders.first;
  }

  Widget _buildHeader(
    BuildContext context,
    WebsiteService websiteService,
    List<OnlineOrder> orders,
  ) {
    final theme = Theme.of(context);
    final pendingCount =
        orders.where((order) => order.status == 'pending').length;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Row(
        children: [
          if (!widget.embedded) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Volver',
              onPressed: () => context.go('/website'),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pedidos online',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  pendingCount == 0
                      ? 'Ventas web sincronizadas con facturación e inventario'
                      : '$pendingCount pedido${pendingCount == 1 ? '' : 's'} pendiente${pendingCount == 1 ? '' : 's'} de gestión',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => websiteService.loadOrders(),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Actualizar'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStrip(List<OnlineOrder> orders) {
    final total = orders.length;
    final pending = orders.where((order) => order.status == 'pending').length;
    final paid = orders.where((order) => order.paymentStatus == 'paid').length;
    final missingInvoice = orders
        .where((order) =>
            order.paymentStatus == 'paid' && order.salesInvoiceId == null)
        .length;
    final shipping =
        orders.where((order) => order.deliveryType == 'shipping').length;

    return Container(
      color: _softSurface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _buildMetricPill(
              'Total', total.toString(), Icons.receipt_long_outlined),
          _buildMetricPill(
              'Pendientes', pending.toString(), Icons.pending_actions_outlined),
          _buildMetricPill('Pagados', paid.toString(), Icons.payments_outlined),
          _buildMetricPill(
              'Sin factura', missingInvoice.toString(), Icons.rule_outlined),
          _buildMetricPill(
              'Despacho', shipping.toString(), Icons.local_shipping_outlined),
        ],
      ),
    );
  }

  Widget _buildMetricPill(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.grey[700]),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(int visibleCount) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: ConstraintLayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 760;
          final filters = [
            _buildFilterDropdown(
              label: 'Estado',
              value: _selectedStatus,
              options: const {
                'all': 'Todos',
                'pending': 'Pendiente',
                'confirmed': 'Confirmado',
                'processing': 'Preparación',
                'ready_for_pickup': 'Listo retiro',
                'shipped': 'Enviado',
                'delivered': 'Entregado',
                'cancelled': 'Cancelado',
              },
              onChanged: (value) => setState(() => _selectedStatus = value),
            ),
            _buildFilterDropdown(
              label: 'Pago',
              value: _selectedPaymentStatus,
              options: const {
                'all': 'Todos',
                'pending': 'Pendiente',
                'paid': 'Pagado',
                'failed': 'Fallido',
                'refunded': 'Reembolsado',
              },
              onChanged: (value) =>
                  setState(() => _selectedPaymentStatus = value),
            ),
          ];

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSearchField(),
                const SizedBox(height: 10),
                Wrap(spacing: 10, runSpacing: 10, children: filters),
                const SizedBox(height: 8),
                Text('$visibleCount pedidos visibles', style: _hintStyle),
              ],
            );
          }

          return Row(
            children: [
              SizedBox(width: 320, child: _buildSearchField()),
              const SizedBox(width: 12),
              ...filters.map(
                (filter) => Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: filter,
                ),
              ),
              const Spacer(),
              Text('$visibleCount pedidos visibles', style: _hintStyle),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _searchQuery = value),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Buscar pedido, cliente, email o teléfono',
        prefixIcon: const Icon(Icons.search, size: 18),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required String value,
    required Map<String, String> options,
    required ValueChanged<String> onChanged,
  }) {
    return SizedBox(
      width: 170,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isDense: true,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
        items: options.entries
            .map((entry) => DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value),
                ))
            .toList(),
        onChanged: (next) => onChanged(next ?? 'all'),
      ),
    );
  }

  Widget _buildOrdersList(
    BuildContext context,
    List<OnlineOrder> orders,
    OnlineOrder? selectedOrder,
  ) {
    return Container(
      color: Colors.white,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final order = orders[index];
          return _buildOrderListItem(
            order,
            selected: order.id == selectedOrder?.id,
            onTap: () => setState(() => _selectedOrderId = order.id),
          );
        },
      ),
    );
  }

  Widget _buildMobileOrdersList(
    BuildContext context,
    WebsiteService websiteService,
    List<OnlineOrder> orders,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final order = orders[index];
        return Column(
          children: [
            _buildOrderListItem(
              order,
              selected: _selectedOrderId == order.id,
              onTap: () => setState(() => _selectedOrderId = order.id),
            ),
            if (_selectedOrderId == order.id)
              Container(
                margin: const EdgeInsets.only(top: 8),
                decoration: _panelDecoration,
                child: _buildOrderInspector(context, websiteService, order),
              ),
          ],
        );
      },
    );
  }

  Widget _buildOrderListItem(
    OnlineOrder order, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final statusTone = _getStatusTone(order.status);

    return Material(
      color: selected ? _accentBlue.withValues(alpha: 0.04) : Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? _accentBlue : _borderColor,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      order.orderNumber,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  _buildCompactBadge(order.statusDisplayName, statusTone),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                order.customerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                order.customerEmail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _hintStyle,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.schedule_outlined,
                      size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 5),
                  Text(ChileanUtils.formatDate(order.createdAt),
                      style: _hintStyle),
                  const SizedBox(width: 12),
                  Icon(
                    order.deliveryType == 'pickup'
                        ? Icons.storefront_outlined
                        : Icons.local_shipping_outlined,
                    size: 14,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      order.deliveryDisplayName,
                      overflow: TextOverflow.ellipsis,
                      style: _hintStyle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildCompactBadge(
                    order.paymentStatusDisplayName,
                    _getPaymentTone(order.paymentStatus),
                  ),
                  const Spacer(),
                  Text(
                    ChileanUtils.formatCurrency(order.total),
                    style: const TextStyle(
                      color: _accentBlue,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
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

  Widget _buildOrderInspector(
    BuildContext context,
    WebsiteService websiteService,
    OnlineOrder order,
  ) {
    final theme = Theme.of(context);
    final busy = _busyOrderId == order.id;

    return Container(
      color: _softSurface,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: _panelDecoration,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.orderNumber,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Creado ${ChileanUtils.formatDate(order.createdAt)}',
                            style: _hintStyle,
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _buildCompactBadge(
                          order.statusDisplayName,
                          _getStatusTone(order.status),
                        ),
                        const SizedBox(height: 6),
                        _buildCompactBadge(
                          order.paymentStatusDisplayName,
                          _getPaymentTone(order.paymentStatus),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (order.status == 'pending')
                      FilledButton.icon(
                        onPressed: busy
                            ? null
                            : () =>
                                _confirmOrder(context, websiteService, order),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Confirmar pedido'),
                      ),
                    if (order.customerPhone != null &&
                        order.customerPhone!.trim().isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () => _openOrderMessagingConversation(
                                  context,
                                  order,
                                ),
                        icon: const Icon(Icons.chat_bubble_outline, size: 18),
                        label: const Text('Coordinar entrega'),
                      ),
                    if (order.salesInvoiceId == null &&
                        order.paymentStatus == 'paid')
                      OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () =>
                                _processOrder(context, websiteService, order),
                        icon: const Icon(Icons.receipt_long_outlined, size: 18),
                        label: const Text('Crear factura'),
                      ),
                    if (order.salesInvoiceId != null)
                      OutlinedButton.icon(
                        onPressed: () => context
                            .go('/sales/invoices/${order.salesInvoiceId}'),
                        icon: const Icon(Icons.receipt_long_outlined, size: 18),
                        label: const Text('Ver factura'),
                      ),
                    TextButton.icon(
                      onPressed: busy || order.status == 'cancelled'
                          ? null
                          : () => _cancelOrder(context, websiteService, order),
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text('Cancelar'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red[700],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _buildInfoGrid(order),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildItemsPanel(order),
          const SizedBox(height: 12),
          _buildTotalsPanel(order),
        ],
      ),
    );
  }

  Widget _buildInfoGrid(OnlineOrder order) {
    return SafeLayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 720 ? 2 : 1;
        final cards = [
          _buildInfoPanel(
            title: 'Cliente',
            icon: Icons.person_outline,
            rows: [
              _InfoRow('Nombre', order.customerName),
              _InfoRow('Email', order.customerEmail),
              _InfoRow('Teléfono', order.customerPhone ?? 'Sin teléfono'),
              _InfoRow('Notas', _emptyFallback(order.customerNotes)),
            ],
          ),
          _buildInfoPanel(
            title: 'Entrega',
            icon: Icons.local_shipping_outlined,
            rows: [
              _InfoRow('Tipo', order.deliveryDisplayName),
              _InfoRow('Dirección', order.shippingAddressDisplay),
              _InfoRow('Comuna', order.shippingCity ?? 'Sin comuna'),
              _InfoRow('Región', order.shippingState ?? 'Sin región'),
            ],
          ),
          _buildInfoPanel(
            title: 'Pago',
            icon: Icons.payments_outlined,
            rows: [
              _InfoRow('Método', _formatPaymentMethod(order.paymentMethod)),
              _InfoRow('Estado', order.paymentStatusDisplayName),
              _InfoRow(
                  'Referencia', order.paymentReference ?? 'Sin referencia'),
              _InfoRow(
                'Pagado',
                order.paidAt == null
                    ? 'Sin fecha'
                    : ChileanUtils.formatDate(order.paidAt!),
              ),
            ],
          ),
          _buildInfoPanel(
            title: 'Operación',
            icon: Icons.tune_outlined,
            rows: [
              _InfoRow('Estado', order.statusDisplayName),
              _InfoRow('Factura', order.salesInvoiceId ?? 'Sin factura'),
              _InfoRow('Notas internas', _emptyFallback(order.internalNotes)),
              _InfoRow('Actualizado', ChileanUtils.formatDate(order.updatedAt)),
            ],
          ),
        ];

        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: columns == 2 ? 2.35 : 2.8,
          children: cards,
        );
      },
    );
  }

  Widget _buildInfoPanel({
    required String title,
    required IconData icon,
    required List<_InfoRow> rows,
  }) {
    return Container(
      decoration: _panelDecoration,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: _accentBlue),
              const SizedBox(width: 8),
              Text(
                title,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 78,
                    child: Text(row.label, style: _hintStyle),
                  ),
                  Expanded(
                    child: Text(
                      row.value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsPanel(OnlineOrder order) {
    return Container(
      decoration: _panelDecoration,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Productos',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 10),
          if (order.items.isEmpty)
            Text('Sin items registrados', style: _hintStyle)
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                horizontalMargin: 0,
                columnSpacing: 24,
                headingRowHeight: 34,
                dataRowMinHeight: 38,
                dataRowMaxHeight: 44,
                columns: const [
                  DataColumn(label: Text('Producto')),
                  DataColumn(label: Text('SKU')),
                  DataColumn(numeric: true, label: Text('Cant.')),
                  DataColumn(numeric: true, label: Text('Precio')),
                  DataColumn(numeric: true, label: Text('Subtotal')),
                ],
                rows: order.items
                    .map(
                      (item) => DataRow(
                        cells: [
                          DataCell(SizedBox(
                            width: 240,
                            child: Text(
                              item.productName,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )),
                          DataCell(Text(item.productSku ?? '-')),
                          DataCell(Text('${item.quantity}')),
                          DataCell(Text(
                              ChileanUtils.formatCurrency(item.unitPrice))),
                          DataCell(
                              Text(ChileanUtils.formatCurrency(item.subtotal))),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTotalsPanel(OnlineOrder order) {
    return Container(
      decoration: _panelDecoration,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTotalRow('Subtotal', order.subtotal),
          if (order.discountAmount > 0)
            _buildTotalRow('Descuento', -order.discountAmount),
          if (order.shippingCost > 0)
            _buildTotalRow('Despacho', order.shippingCost),
          if (order.taxAmount > 0) _buildTotalRow('IVA', order.taxAmount),
          const Divider(height: 20),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Total',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              Text(
                ChileanUtils.formatCurrency(order.total),
                style: const TextStyle(
                  color: _accentBlue,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, double value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Expanded(child: Text(label, style: _hintStyle)),
          Text(
            ChileanUtils.formatCurrency(value),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmOrder(
    BuildContext context,
    WebsiteService websiteService,
    OnlineOrder order,
  ) async {
    await _runOrderAction(context, order, () async {
      if (order.paymentStatus == 'paid' && order.salesInvoiceId == null) {
        await websiteService.processOrder(order.id);
      } else {
        await websiteService.updateOrderStatus(order.id, 'confirmed');
      }
      if (context.mounted) _showSnackBar(context, 'Pedido confirmado');
    });
  }

  Future<void> _processOrder(
    BuildContext context,
    WebsiteService websiteService,
    OnlineOrder order,
  ) async {
    await _runOrderAction(context, order, () async {
      final invoiceId = await websiteService.processOrder(order.id);
      if (!context.mounted) return;
      _showSnackBar(
        context,
        invoiceId == null ? 'Factura procesada' : 'Factura creada',
        action: invoiceId == null
            ? null
            : SnackBarAction(
                label: 'Ver',
                onPressed: () => context.go('/sales/invoices/$invoiceId'),
              ),
      );
    });
  }

  Future<void> _cancelOrder(
    BuildContext context,
    WebsiteService websiteService,
    OnlineOrder order,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar pedido'),
        content: Text('¿Cancelar ${order.orderNumber}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancelar pedido'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    await _runOrderAction(context, order, () async {
      await websiteService.updateOrderStatus(order.id, 'cancelled');
      if (context.mounted) _showSnackBar(context, 'Pedido cancelado');
    });
  }

  Future<void> _openOrderMessagingConversation(
    BuildContext context,
    OnlineOrder order,
  ) async {
    final phone = order.customerPhone?.trim();
    if (phone == null || phone.isEmpty) {
      _showSnackBar(context, 'Este pedido no tiene teléfono');
      return;
    }

    await _runOrderAction(context, order, () async {
      final conversationId =
          await MessagingService().openWhatsAppSupportConversation(
        phoneNumber: phone,
        contactName: order.customerName,
        customerId: order.customerId,
        contextType: 'order',
        contextId: order.id,
      );

      if (!context.mounted) return;
      context.read<ChatProvider>().setConversationDraft(
            conversationId,
            _buildOrderWhatsAppDraft(order),
            title: 'Pedido ${order.orderNumber} listo para coordinar',
            subtitle:
                'No se ha enviado ningún mensaje del pedido. Revisa el texto y envíalo desde Mensajería.',
          );
      context.go('/chat?conversation=$conversationId');
    });
  }

  Future<void> _runOrderAction(
    BuildContext context,
    OnlineOrder order,
    Future<void> Function() action,
  ) async {
    if (_busyOrderId != null) return;
    setState(() => _busyOrderId = order.id);
    try {
      await action();
    } catch (error) {
      if (context.mounted) {
        _showSnackBar(context, 'No se pudo completar la acción: $error');
      }
    } finally {
      if (mounted) setState(() => _busyOrderId = null);
    }
  }

  String _buildOrderWhatsAppDraft(OnlineOrder order) {
    final firstName = order.customerName.trim().split(RegExp(r'\s+')).first;
    final itemLines = order.items.take(6).map((item) {
      return '- ${item.quantity} x ${item.productName}';
    }).join('\n');
    final remaining = order.items.length > 6
        ? '\n- y ${order.items.length - 6} producto${order.items.length - 6 == 1 ? '' : 's'} más'
        : '';

    final deliveryText = order.deliveryType == 'pickup'
        ? 'El pedido está marcado para retiro en tienda.'
        : 'El pedido está marcado para despacho a: ${order.shippingAddressDisplay}.';

    return '''Hola $firstName, te escribimos de Viñabike por tu pedido ${order.orderNumber}.

Resumen:
${itemLines.isEmpty ? '- Productos registrados en tu pedido web' : itemLines}$remaining

Total: ${ChileanUtils.formatCurrency(order.total)}
$deliveryText

Para coordinar la entrega, respóndenos con una opción:
1. Retiro en tienda
2. Despacho a domicilio

Si prefieres despacho, confirma dirección, comuna y una franja horaria. Gracias.''';
  }

  void _showSnackBar(
    BuildContext context,
    String message, {
    SnackBarAction? action,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), action: action),
    );
  }

  Widget _buildCompactBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 56, color: Colors.grey[300]),
          const SizedBox(height: 12),
          const Text(
            'No hay pedidos para este filtro',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Ajusta búsqueda, estado o pago para revisar otros pedidos.',
            style: _hintStyle,
          ),
        ],
      ),
    );
  }

  Widget _buildNoSelectionState() {
    return Center(child: Text('Selecciona un pedido', style: _hintStyle));
  }

  Color _getStatusTone(String status) {
    switch (status) {
      case 'pending':
        return const Color(0xFFB45309);
      case 'confirmed':
        return const Color(0xFF1D4ED8);
      case 'processing':
        return const Color(0xFF475569);
      case 'ready_for_pickup':
        return const Color(0xFF047857);
      case 'shipped':
        return const Color(0xFF4338CA);
      case 'delivered':
        return const Color(0xFF15803D);
      case 'cancelled':
        return const Color(0xFFB91C1C);
      default:
        return const Color(0xFF64748B);
    }
  }

  Color _getPaymentTone(String status) {
    switch (status) {
      case 'pending':
        return const Color(0xFFB45309);
      case 'paid':
        return const Color(0xFF15803D);
      case 'failed':
        return const Color(0xFFB91C1C);
      case 'refunded':
        return const Color(0xFF7C3AED);
      default:
        return const Color(0xFF64748B);
    }
  }

  String _formatPaymentMethod(String? method) {
    final value = method?.trim();
    if (value == null || value.isEmpty) return 'Sin método';
    switch (value.toLowerCase()) {
      case 'mercadopago':
      case 'mercado_pago':
        return 'Mercado Pago';
      case 'transfer':
      case 'transferencia':
      case 'bank_transfer':
        return 'Transferencia';
      default:
        return value;
    }
  }

  String _emptyFallback(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return 'Sin notas';
    return trimmed;
  }

  BoxDecoration get _panelDecoration => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderColor),
      );

  static TextStyle get _hintStyle => TextStyle(
        fontSize: 12,
        color: Colors.grey[600],
        fontWeight: FontWeight.w500,
      );
}

class _InfoRow {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;
}
