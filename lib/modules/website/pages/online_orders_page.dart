import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../messaging/providers/chat_provider.dart';
import '../../messaging/services/messaging_service.dart';
import '../../../shared/services/notification_service.dart';
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
    this.initialOrderId,
  });

  final bool embedded;
  final String? initialOrderId;

  @override
  State<OnlineOrdersPage> createState() => _OnlineOrdersPageState();
}

class _OnlineOrdersPageState extends State<OnlineOrdersPage> {
  static const Color _accentBlue = Color(0xFF093357);
  static const Color _borderColor = Color(0xFFE5E7EB);
  static const Color _softSurface = Color(0xFFF8FAFC);
  static const double _desktopBreakpoint = 1180;
  static const int _historicalInvoiceWarningDays = 7;
  static const List<_OrderLane> _lanes = [
    _OrderLane(
      key: 'attention',
      label: 'Atención',
      icon: Icons.priority_high_outlined,
    ),
    _OrderLane(
      key: 'blocked',
      label: 'Bloqueados',
      icon: Icons.report_problem_outlined,
    ),
    _OrderLane(
      key: 'prepare',
      label: 'Preparar',
      icon: Icons.inventory_2_outlined,
    ),
    _OrderLane(
      key: 'coordination',
      label: 'Coordinar',
      icon: Icons.forum_outlined,
    ),
    _OrderLane(
      key: 'pickup',
      label: 'Retiro',
      icon: Icons.storefront_outlined,
    ),
    _OrderLane(
      key: 'shipping',
      label: 'Despacho',
      icon: Icons.local_shipping_outlined,
    ),
    _OrderLane(
      key: 'closed',
      label: 'Cerrados',
      icon: Icons.task_alt_outlined,
    ),
    _OrderLane(
      key: 'all',
      label: 'Todos',
      icon: Icons.view_list_outlined,
    ),
  ];

  final TextEditingController _searchController = TextEditingController();

  String _selectedLane = 'all';
  String _selectedStatus = 'all';
  String _selectedPaymentStatus = 'all';
  String _selectedInspectorSection = 'workflow';
  String _searchQuery = '';
  String? _selectedOrderId;
  String? _busyOrderId;
  String? _lastMarkedAlertOrderId;

  @override
  void initState() {
    super.initState();
    _selectedOrderId = widget.initialOrderId;
    if (widget.initialOrderId != null) {
      _selectedLane = 'all';
    }
    _markNotificationReadForOrder(widget.initialOrderId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WebsiteService>().initializeOrders();
    });
  }

  @override
  void didUpdateWidget(covariant OnlineOrdersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialOrderId != widget.initialOrderId &&
        widget.initialOrderId != null) {
      setState(() => _selectedOrderId = widget.initialOrderId);
      _markNotificationReadForOrder(widget.initialOrderId);
    }
  }

  void _markNotificationReadForOrder(String? orderId) {
    final trimmedOrderId = orderId?.trim();
    if (trimmedOrderId == null ||
        trimmedOrderId.isEmpty ||
        trimmedOrderId == _lastMarkedAlertOrderId) {
      return;
    }
    _lastMarkedAlertOrderId = trimmedOrderId;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService().markOnlineOrderAlertReadForOrder(trimmedOrderId);
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

    final body = SelectionContainer.disabled(
      child: Container(
        color: _softSurface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(
              context,
              websiteService,
              allOrders,
              visibleCount: filteredOrders.length,
            ),
            Expanded(
              child: websiteService.isLoading && allOrders.isEmpty
                  ? const Center(child: BrandedLoading())
                  : ConstraintLayoutBuilder(
                      builder: (context, constraints) {
                        final isDesktop =
                            constraints.maxWidth >= _desktopBreakpoint;

                        if (!isDesktop) {
                          return _buildCompactWorkbench(
                            context,
                            websiteService,
                            allOrders,
                            filteredOrders,
                          );
                        }

                        return _buildDesktopWorkbench(
                          context,
                          websiteService,
                          allOrders,
                          filteredOrders,
                          selectedOrder,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );

    if (widget.embedded) return body;
    return MainLayout(child: body);
  }

  List<OnlineOrder> _filterOrders(List<OnlineOrder> orders) {
    final query = _searchQuery.trim().toLowerCase();

    final filtered = orders.where((order) {
      if (!_matchesLane(order, _selectedLane)) {
        return false;
      }
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
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return filtered;
  }

  OnlineOrder? _resolveSelectedOrder(List<OnlineOrder> orders) {
    final selectedId = _selectedOrderId?.trim();
    if (selectedId == null || selectedId.isEmpty) return null;

    for (final order in orders) {
      if (order.id == selectedId) return order;
    }

    return null;
  }

  Widget _buildHeader(
    BuildContext context,
    WebsiteService websiteService,
    List<OnlineOrder> orders, {
    required int visibleCount,
  }) {
    final theme = Theme.of(context);
    final pendingCount =
        orders.where((order) => order.status == 'pending').length;
    final blockedCount = _laneCount(orders, 'blocked');
    final prepareCount = _laneCount(orders, 'prepare');
    final summary =
        '$visibleCount visibles · $blockedCount bloqueados · $prepareCount para preparar';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: ConstraintLayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 720;
          final titleBlock = Row(
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final refreshButton = OutlinedButton.icon(
            onPressed: () => websiteService.loadOrders(),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Actualizar'),
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                titleBlock,
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _hintStyle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    refreshButton,
                  ],
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: titleBlock),
              const SizedBox(width: 16),
              Text(summary, style: _hintStyle),
              const SizedBox(width: 16),
              refreshButton,
            ],
          );
        },
      ),
    );
  }

  Widget _buildDesktopWorkbench(
    BuildContext context,
    WebsiteService websiteService,
    List<OnlineOrder> allOrders,
    List<OnlineOrder> filteredOrders,
    OnlineOrder? selectedOrder,
  ) {
    return ConstraintLayoutBuilder(
      builder: (context, constraints) {
        final showInspector = selectedOrder != null;
        final inspectorWidth = showInspector
            ? (constraints.maxWidth * 0.44).clamp(460.0, 620.0)
            : 0.0;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildToolbar(
                      allOrders,
                      filteredOrders.length,
                    ),
                    Expanded(
                      child: filteredOrders.isEmpty
                          ? _buildEmptyState()
                          : _buildOrdersDenseList(
                              context,
                              filteredOrders,
                              selectedOrder,
                            ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: inspectorWidth,
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: _borderColor)),
              ),
              child: showInspector
                  ? _buildOrderInspector(
                      context,
                      websiteService,
                      selectedOrder,
                      onClose: () => setState(() => _selectedOrderId = null),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCompactWorkbench(
    BuildContext context,
    WebsiteService websiteService,
    List<OnlineOrder> allOrders,
    List<OnlineOrder> filteredOrders,
  ) {
    return Column(
      children: [
        _buildToolbar(allOrders, filteredOrders.length),
        Expanded(
          child: filteredOrders.isEmpty
              ? _buildEmptyState()
              : _buildMobileOrdersList(
                  context,
                  websiteService,
                  filteredOrders,
                ),
        ),
      ],
    );
  }

  Widget _buildToolbar(
    List<OnlineOrder> orders,
    int visibleCount,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: ConstraintLayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 980;
          final isTight = constraints.maxWidth < 620;
          final filters = _buildToolbarFilters();

          if (isWide) {
            return Row(
              children: [
                Expanded(child: _buildLaneBar(orders)),
                const SizedBox(width: 12),
                Text('$visibleCount visibles', style: _hintStyle),
                const SizedBox(width: 12),
                SizedBox(
                  width: 340,
                  child: _buildSearchField(isDense: true),
                ),
                const SizedBox(width: 10),
                filters,
              ],
            );
          }

          if (isTight) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildLaneBar(orders),
                const SizedBox(height: 10),
                _buildSearchField(isDense: true),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: filters),
                    const SizedBox(width: 10),
                    Text('$visibleCount', style: _hintStyle),
                  ],
                ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildLaneBar(orders),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _buildSearchField(isDense: true)),
                  const SizedBox(width: 10),
                  filters,
                  const SizedBox(width: 10),
                  Text('$visibleCount', style: _hintStyle),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLaneBar(List<OnlineOrder> orders) {
    final currentLane = _lanes.any((lane) => lane.key == _selectedLane)
        ? _selectedLane
        : 'attention';

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _lanes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final lane = _lanes[index];
          final selected = lane.key == currentLane;
          final count = _laneCount(orders, lane.key);

          return OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _selectedLane = lane.key;
                _selectedOrderId = null;
              });
            },
            icon: Icon(lane.icon, size: 16),
            label: Text('${lane.label} $count'),
            style: OutlinedButton.styleFrom(
              foregroundColor: selected ? _accentBlue : const Color(0xFF475569),
              backgroundColor:
                  selected ? _accentBlue.withValues(alpha: 0.06) : null,
              side: BorderSide(
                color: selected ? _accentBlue : _borderColor,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 36),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildToolbarFilters() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildPillMenu(
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
          onSelected: (next) => setState(() => _selectedStatus = next),
        ),
        const SizedBox(width: 8),
        _buildPillMenu(
          label: 'Pago',
          value: _selectedPaymentStatus,
          options: const {
            'all': 'Todos',
            'pending': 'Pendiente',
            'paid': 'Pagado',
            'failed': 'Fallido',
            'refunded': 'Reembolsado',
          },
          onSelected: (next) => setState(() => _selectedPaymentStatus = next),
        ),
      ],
    );
  }

  Widget _buildPillMenu({
    required String label,
    required String value,
    required Map<String, String> options,
    required ValueChanged<String> onSelected,
  }) {
    final selectedLabel = options[value] ?? options['all'] ?? label;

    return PopupMenuButton<String>(
      initialValue: value,
      tooltip: label,
      onSelected: onSelected,
      itemBuilder: (context) => options.entries
          .map(
            (entry) => PopupMenuItem(
              value: entry.key,
              child: Row(
                children: [
                  Icon(
                    entry.key == value ? Icons.check : Icons.circle_outlined,
                    size: 16,
                    color: entry.key == value
                        ? _accentBlue
                        : const Color(0xFF94A3B8),
                  ),
                  const SizedBox(width: 8),
                  Text(entry.value),
                ],
              ),
            ),
          )
          .toList(),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$label: $selectedLabel',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.expand_more, size: 18, color: Color(0xFF475569)),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField({bool isDense = false}) {
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
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            EdgeInsets.symmetric(horizontal: 12, vertical: isDense ? 10 : 12),
      ),
    );
  }

  Widget _buildOrdersDenseList(
    BuildContext context,
    List<OnlineOrder> orders,
    OnlineOrder? selectedOrder,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      itemCount: orders.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: _borderColor),
      itemBuilder: (context, index) {
        final order = orders[index];
        final selected = order.id == selectedOrder?.id;
        return _buildOrderRow(
          order,
          selected: selected,
          onTap: () => setState(() {
            _selectedOrderId = selected ? null : order.id;
          }),
        );
      },
    );
  }

  Widget _buildOrderRow(
    OnlineOrder order, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final statusTone = _getStatusTone(order.status);
    final priorityTone =
        _isFulfillmentBlocked(order) ? const Color(0xFFB91C1C) : statusTone;

    return Material(
      color: selected ? _accentBlue.withValues(alpha: 0.03) : Colors.white,
      child: InkWell(
        onTap: onTap,
        hoverColor: _accentBlue.withValues(alpha: 0.025),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 3,
                height: 46,
                decoration: BoxDecoration(
                  color: priorityTone,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            order.orderNumber,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          ChileanUtils.formatDate(order.createdAt),
                          style: _hintStyle,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            order.customerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          order.deliveryType == 'pickup'
                              ? Icons.storefront_outlined
                              : Icons.local_shipping_outlined,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(
                            order.deliveryDisplayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _hintStyle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _buildAttentionRow(order),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    ChileanUtils.formatCurrency(order.total),
                    style: const TextStyle(
                      color: _accentBlue,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.end,
                    children: [
                      _buildCompactBadge(
                        order.statusDisplayName,
                        statusTone,
                      ),
                      _buildCompactBadge(
                        order.paymentStatusDisplayName,
                        _getPaymentTone(order.paymentStatus),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileOrdersList(
    BuildContext context,
    WebsiteService websiteService,
    List<OnlineOrder> orders,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.only(top: 6, bottom: 16),
      itemCount: orders.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: _borderColor),
      itemBuilder: (context, index) {
        final order = orders[index];
        final selected = _selectedOrderId == order.id;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildOrderRow(
              order,
              selected: selected,
              onTap: () => setState(() {
                _selectedOrderId = selected ? null : order.id;
              }),
            ),
            if (selected)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                decoration: _panelDecoration.copyWith(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _buildOrderInspector(
                  context,
                  websiteService,
                  order,
                  embedded: true,
                ),
              ),
          ],
        );
      },
    );
  }

  // Legacy card-based list item (kept temporarily).
  // ignore: unused_element
  Widget _buildOrderListItem(
    OnlineOrder order, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final statusTone = _getStatusTone(order.status);
    final queueSignals = _buildQueueSignals(order);
    final visibleSignals = queueSignals.take(2).toList();
    final hiddenSignalCount = queueSignals.length - visibleSignals.length;
    final priorityTone =
        _isFulfillmentBlocked(order) ? const Color(0xFFB91C1C) : statusTone;

    return Material(
      color: selected ? _accentBlue.withValues(alpha: 0.035) : Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? _accentBlue : _borderColor,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: priorityTone,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(8),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            order.orderNumber,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          ChileanUtils.formatCurrency(order.total),
                          style: const TextStyle(
                            color: _accentBlue,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      order.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 3),
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
                    const SizedBox(height: 9),
                    _buildAttentionRow(order),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        _buildCompactBadge(order.statusDisplayName, statusTone),
                        const SizedBox(width: 6),
                        _buildCompactBadge(
                          order.paymentStatusDisplayName,
                          _getPaymentTone(order.paymentStatus),
                        ),
                      ],
                    ),
                    if (visibleSignals.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          ...visibleSignals,
                          if (hiddenSignalCount > 0)
                            _buildQueueSignalOverflowChip(hiddenSignalCount),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  // Legacy queue signals (kept temporarily).
  Widget _buildQueueSignalOverflowChip(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF475569).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: const Color(0xFF475569).withValues(alpha: 0.24),
        ),
      ),
      child: Text(
        '+$count más',
        style: const TextStyle(
          color: Color(0xFF475569),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ignore: unused_element
  // Legacy queue signals (kept temporarily).
  List<Widget> _buildQueueSignals(OnlineOrder order) {
    final signals = <Widget>[];

    if (order.paymentStatus == 'paid' && order.salesInvoiceId == null) {
      signals.add(_buildQueueSignalChip(
        _requiresHistoricalInvoiceWarning(order)
            ? 'pago antiguo sin factura'
            : 'pagado sin factura',
        Icons.receipt_long_outlined,
        const Color(0xFFB91C1C),
      ));
    }
    if (order.paymentStatus == 'failed') {
      signals.add(_buildQueueSignalChip(
        'pago fallido',
        Icons.payment_outlined,
        const Color(0xFFB91C1C),
      ));
    }
    if (order.paymentStatus == 'pending' && order.status == 'pending') {
      signals.add(_buildQueueSignalChip(
        'pago pendiente',
        Icons.hourglass_empty_outlined,
        const Color(0xFFB45309),
      ));
    }
    if (!_isTerminalOrder(order) && !_hasCustomerPhone(order)) {
      signals.add(_buildQueueSignalChip(
        'sin teléfono cliente',
        Icons.phone_disabled_outlined,
        const Color(0xFFB91C1C),
      ));
    }
    if (!_isTerminalOrder(order) && order.deliveryType == 'shipping') {
      if (!_hasShippingAddress(order)) {
        signals.add(_buildQueueSignalChip(
          'sin dirección despacho',
          Icons.location_off_outlined,
          const Color(0xFFB91C1C),
        ));
      } else if (order.status == 'shipped' &&
          order.trackingNumber?.trim().isNotEmpty != true) {
        signals.add(_buildQueueSignalChip(
          'sin seguimiento',
          Icons.route_outlined,
          const Color(0xFFB45309),
        ));
      }
    }
    signals.addAll(_buildInventoryQueueSignals(order));
    if (_needsCoordination(order)) {
      signals.add(_buildQueueSignalChip(
        order.deliveryType == 'pickup' ? 'coordinar retiro' : 'coordinar envío',
        Icons.forum_outlined,
        const Color(0xFF475569),
      ));
    }
    if (order.status == 'cancelled' && order.refundAmount > 0) {
      signals.add(_buildQueueSignalChip(
        'reembolso ${ChileanUtils.formatCurrency(order.refundAmount)}',
        Icons.replay_circle_filled_outlined,
        const Color(0xFF7C3AED),
      ));
    }

    return signals;
  }

  // ignore: unused_element
  // Legacy queue signals (kept temporarily).
  List<Widget> _buildInventoryQueueSignals(OnlineOrder order) {
    if (_isTerminalOrder(order)) return const [];

    final readiness = _inventoryReadinessForOrder(order);
    if (order.items.isEmpty) {
      return [
        _buildQueueSignalChip(
          'sin productos',
          Icons.inventory_2_outlined,
          const Color(0xFFB91C1C),
        ),
      ];
    }

    final codes = readiness.items.map((item) => item.code).toSet();
    final chips = <Widget>[];
    if (codes.contains('missing_link') || codes.contains('missing_product')) {
      chips.add(_buildQueueSignalChip(
        'item sin producto',
        Icons.link_off_outlined,
        const Color(0xFFB91C1C),
      ));
    }
    if (codes.contains('inactive_product')) {
      chips.add(_buildQueueSignalChip(
        'producto inactivo',
        Icons.block_outlined,
        const Color(0xFFB91C1C),
      ));
    }
    if (codes.contains('stock_short')) {
      chips.add(_buildQueueSignalChip(
        'stock corto',
        Icons.production_quantity_limits_outlined,
        const Color(0xFFB91C1C),
      ));
    }
    if (codes.contains('stock_unknown') || codes.contains('context_pending')) {
      chips.add(_buildQueueSignalChip(
        'revisar stock',
        Icons.help_outline,
        const Color(0xFFB45309),
      ));
    }
    if (codes.contains('stock_tight')) {
      chips.add(_buildQueueSignalChip(
        'stock justo',
        Icons.info_outline,
        const Color(0xFFB45309),
      ));
    }
    if (codes.contains('unpublished')) {
      chips.add(_buildQueueSignalChip(
        'producto no publicado',
        Icons.visibility_off_outlined,
        const Color(0xFFB45309),
      ));
    }
    return chips;
  }

  // ignore: unused_element
  // Legacy queue signals (kept temporarily).
  Widget _buildQueueSignalChip(String label, IconData icon, Color color) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttentionRow(OnlineOrder order) {
    final tone = _isFulfillmentBlocked(order)
        ? const Color(0xFFB91C1C)
        : _needsCoordination(order)
            ? const Color(0xFFB45309)
            : Colors.grey[700]!;

    return Row(
      children: [
        Icon(_attentionIcon(order), size: 14, color: tone),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            _attentionLabel(order),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tone,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderInspector(
    BuildContext context,
    WebsiteService websiteService,
    OnlineOrder order, {
    VoidCallback? onClose,
    bool embedded = false,
  }) {
    final busy = _busyOrderId == order.id;
    final blockers = _blockerLabels(order);
    final readiness = _inventoryReadinessForOrder(order);

    final inspectorBody = ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      shrinkWrap: embedded,
      primary: !embedded,
      physics: embedded ? const NeverScrollableScrollPhysics() : null,
      children: [
        _buildInspectorIdentityBar(order, onClose: onClose),
        const SizedBox(height: 10),
        _buildFlatActionBar(context, websiteService, order, busy: busy),
        const SizedBox(height: 12),
        _buildInspectorTabs(),
        const SizedBox(height: 12),
        ..._buildInspectorSection(
          context,
          websiteService,
          order,
          blockers,
          readiness,
          busy: busy,
        ),
      ],
    );

    return Container(
      color: embedded ? Colors.transparent : _softSurface,
      child: inspectorBody,
    );
  }

  List<Widget> _buildInspectorSection(
    BuildContext context,
    WebsiteService websiteService,
    OnlineOrder order,
    List<String> blockers,
    _OrderInventoryReadiness readiness, {
    required bool busy,
  }) {
    switch (_selectedInspectorSection) {
      case 'products':
        return [
          _buildItemsPanel(order),
          const SizedBox(height: 8),
          _buildTotalsPanel(order),
        ];
      case 'customer':
        return [
          _buildCompactInfoStrip(order),
        ];
      case 'activity':
        return [
          _buildInlineNotes(context, websiteService, order, busy: busy),
          const SizedBox(height: 12),
          _buildTimelinePanel(order),
        ];
      case 'workflow':
      default:
        return [
          _buildStatusStrip(order, blockers),
          const SizedBox(height: 12),
          _buildCombinedChecklistAndInventory(order, readiness),
        ];
    }
  }

  Widget _buildInspectorIdentityBar(
    OnlineOrder order, {
    VoidCallback? onClose,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderColor),
      ),
      child: ConstraintLayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 620;
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                order.orderNumber,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${order.customerName} · ${ChileanUtils.formatDate(order.createdAt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _hintStyle,
              ),
            ],
          );
          final closeButton = onClose == null
              ? null
              : IconButton(
                  tooltip: 'Cerrar',
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                );
          final badges = Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: isNarrow ? WrapAlignment.start : WrapAlignment.end,
            children: [
              _buildCompactBadge(
                order.statusDisplayName,
                _getStatusTone(order.status),
              ),
              _buildCompactBadge(
                order.paymentStatusDisplayName,
                _getPaymentTone(order.paymentStatus),
              ),
            ],
          );
          final total = Text(
            ChileanUtils.formatCurrency(order.total),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 22,
              color: _accentBlue,
            ),
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: title),
                    if (closeButton != null) closeButton,
                  ],
                ),
                const SizedBox(height: 10),
                badges,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: total),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: title),
                    if (closeButton != null) closeButton,
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  total,
                  const SizedBox(height: 8),
                  badges,
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInspectorTabs() {
    const tabs = [
      _InspectorTab('workflow', 'Operación', Icons.fact_check_outlined),
      _InspectorTab('products', 'Productos', Icons.inventory_2_outlined),
      _InspectorTab('customer', 'Cliente', Icons.person_outline),
      _InspectorTab('activity', 'Actividad', Icons.timeline_outlined),
    ];

    return Container(
      decoration: _panelDecoration,
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final tab in tabs) _buildInspectorTab(tab),
          ],
        ),
      ),
    );
  }

  Widget _buildInspectorTab(_InspectorTab tab) {
    final selected = _selectedInspectorSection == tab.key;
    final color = selected ? _accentBlue : const Color(0xFF475569);

    return Material(
      color: selected ? _accentBlue.withValues(alpha: 0.06) : Colors.white,
      child: InkWell(
        onTap: () => setState(() => _selectedInspectorSection = tab.key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? _accentBlue : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(tab.icon, size: 16, color: color),
              const SizedBox(width: 7),
              Text(
                tab.label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFlatActionBar(
    BuildContext context,
    WebsiteService websiteService,
    OnlineOrder order, {
    required bool busy,
  }) {
    final primary = _buildPrimaryActionButton(
      context,
      websiteService,
      order,
      busy: busy,
    );
    final secondary = _buildSecondaryActionRow(
      context,
      websiteService,
      order,
      busy: busy,
    );
    final blockers = _blockerLabels(order);
    final tone = blockers.isEmpty ? _getStatusTone(order.status) : Colors.red;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_attentionIcon(order), size: 20, color: tone),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Siguiente acción', style: _hintStyle),
                    const SizedBox(height: 2),
                    Text(
                      _nextActionLabel(order),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (blockers.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        blockers.join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.red[700],
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (primary != null) ...[
            const SizedBox(height: 12),
            primary,
          ],
          if (secondary != null) ...[
            const SizedBox(height: 10),
            secondary,
          ],
        ],
      ),
    );
  }

  Widget _buildStatusStrip(OnlineOrder order, List<String> blockers) {
    final cells = [
      _buildBriefCell(
        'Siguiente acción',
        _nextActionLabel(order),
        _attentionIcon(order),
        _isFulfillmentBlocked(order)
            ? const Color(0xFFB91C1C)
            : _getStatusTone(order.status),
      ),
      _buildBriefCell(
        order.deliveryType == 'pickup' ? 'Retiro' : 'Despacho',
        order.deliveryType == 'pickup'
            ? _pickupFulfillmentLabel(order)
            : _shippingFulfillmentLabel(order),
        order.deliveryType == 'pickup'
            ? Icons.storefront_outlined
            : Icons.local_shipping_outlined,
        const Color(0xFF475569),
      ),
      _buildBriefCell(
        'Estado de bloqueos',
        blockers.isEmpty ? 'Sin bloqueos' : blockers.join(' · '),
        blockers.isEmpty
            ? Icons.check_circle_outline
            : Icons.report_problem_outlined,
        blockers.isEmpty ? const Color(0xFF047857) : const Color(0xFFB91C1C),
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderColor),
      ),
      child: ConstraintLayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 720;
          if (isNarrow) {
            return Column(
              children: [
                for (var i = 0; i < cells.length; i++) ...[
                  if (i > 0) const Divider(height: 18),
                  cells[i],
                ],
              ],
            );
          }

          return Row(
            children: [
              for (var i = 0; i < cells.length; i++) ...[
                if (i > 0)
                  Container(
                    width: 1,
                    height: 38,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    color: _borderColor,
                  ),
                Expanded(child: cells[i]),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildCompactInfoStrip(OnlineOrder order) {
    final deliveryRows = order.deliveryType == 'pickup'
        ? [
            _InfoRow('Tipo', order.deliveryDisplayName),
            _InfoRow('Punto', order.shippingAddressDisplay),
          ]
        : [
            _InfoRow('Tipo', order.deliveryDisplayName),
            _InfoRow('Dirección', order.shippingAddressDisplay),
            if (order.shippingCity?.isNotEmpty == true)
              _InfoRow('Comuna', order.shippingCity!),
          ];

    final cards = [
      _buildMiniInfoCard(
        'Cliente',
        Icons.person_outline,
        [
          _InfoRow('Nombre', order.customerName),
          _InfoRow('Email', order.customerEmail),
          _InfoRow('Teléfono', order.customerPhone ?? 'Sin teléfono'),
        ],
      ),
      _buildMiniInfoCard(
        'Entrega',
        Icons.local_shipping_outlined,
        deliveryRows,
      ),
      _buildMiniInfoCard(
        'Pago',
        Icons.payments_outlined,
        [
          _InfoRow('Método', _formatPaymentMethod(order.paymentMethod)),
          _InfoRow('Referencia', order.paymentReference ?? 'Sin referencia'),
          _InfoRow(
            'Pagado',
            order.paidAt == null
                ? 'Sin fecha'
                : ChileanUtils.formatDate(order.paidAt!),
          ),
        ],
      ),
    ];

    return ConstraintLayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                cards[i],
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: cards[i]),
            ],
          ],
        );
      },
    );
  }

  Widget _buildMiniInfoCard(
    String title,
    IconData icon,
    List<_InfoRow> rows,
  ) {
    return Container(
      decoration: _panelDecoration,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: _accentBlue),
              const SizedBox(width: 6),
              Text(
                title,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 60,
                    child: Text(row.label,
                        style: _hintStyle.copyWith(fontSize: 11)),
                  ),
                  Expanded(
                    child: Text(
                      row.value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500),
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

  Widget _buildCombinedChecklistAndInventory(
    OnlineOrder order,
    _OrderInventoryReadiness readiness,
  ) {
    final checkpoints = _buildOrderCheckpoints(order);
    final color = _inventoryReadinessColor(readiness.level);

    return Container(
      decoration: _panelDecoration,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined,
                  size: 15, color: _accentBlue),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'Checklist operativo',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              Icon(readiness.icon, size: 14, color: color),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  'Inventario: ${readiness.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: checkpoints
                .map((cp) => _buildCompactCheckpointChip(cp))
                .toList(),
          ),
          if (readiness.level != _InventoryReadinessLevel.ready &&
              readiness.items.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ...readiness.items.map((r) => _buildInventoryReadinessRow(r)),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactCheckpointChip(_OrderCheckpoint checkpoint) {
    final color = _checkpointColor(checkpoint.level);
    final icon = _checkpointIcon(checkpoint.level);
    return Tooltip(
      message: checkpoint.detail,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              checkpoint.title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineNotes(
    BuildContext context,
    WebsiteService websiteService,
    OnlineOrder order, {
    required bool busy,
  }) {
    final customerNotes = _emptyFallback(order.customerNotes);
    final internalNotes = _emptyFallback(order.internalNotes);

    return Container(
      decoration: _panelDecoration,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sticky_note_2_outlined,
                  size: 15, color: _accentBlue),
              const SizedBox(width: 7),
              const Text(
                'Notas',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () => _editInternalNotes(
                          context,
                          websiteService,
                          order,
                        ),
                icon: const Icon(Icons.edit_note_outlined, size: 16),
                label: const Text('Editar interna'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ConstraintLayoutBuilder(
            builder: (context, constraints) {
              final blocks = [
                _buildNoteBlock('Cliente', customerNotes, Icons.person_outline),
                _buildNoteBlock('Interna', internalNotes, Icons.lock_outline),
              ];
              if (constraints.maxWidth < 620) {
                return Column(
                  children: [
                    blocks[0],
                    const SizedBox(height: 8),
                    blocks[1],
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: blocks[0]),
                  const SizedBox(width: 8),
                  Expanded(child: blocks[1]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget? _buildPrimaryActionButton(
    BuildContext context,
    WebsiteService websiteService,
    OnlineOrder order, {
    required bool busy,
  }) {
    switch (order.status) {
      case 'pending':
        if (_canConfirmPayment(order)) {
          return SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy
                  ? null
                  : () => _confirmOrderPayment(context, websiteService, order),
              icon: const Icon(Icons.payments_outlined, size: 18),
              label: const Text('Confirmar pago'),
            ),
          );
        }
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: busy
                ? null
                : () => _confirmOrder(context, websiteService, order),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Confirmar pedido'),
          ),
        );
      case 'confirmed':
        if (order.salesInvoiceId == null && order.paymentStatus == 'paid') {
          return SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy
                  ? null
                  : () => _processOrder(context, websiteService, order),
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('Crear factura'),
            ),
          );
        }
        if (order.salesInvoiceId != null) {
          return SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy
                  ? null
                  : () => _startPreparing(context, websiteService, order),
              icon: const Icon(Icons.inventory_2_outlined, size: 18),
              label: const Text('Preparar pedido'),
            ),
          );
        }
        return null;
      case 'processing':
        if (order.deliveryType == 'pickup') {
          return SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy
                  ? null
                  : () => _markReadyForPickup(
                        context,
                        websiteService,
                        order,
                      ),
              icon: const Icon(Icons.storefront_outlined, size: 18),
              label: const Text('Listo para retiro'),
            ),
          );
        }
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: busy
                ? null
                : () => _markShipped(context, websiteService, order),
            icon: const Icon(Icons.local_shipping_outlined, size: 18),
            label: const Text('Marcar enviado'),
          ),
        );
      case 'ready_for_pickup':
      case 'shipped':
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: busy
                ? null
                : () => _markDelivered(context, websiteService, order),
            icon: const Icon(Icons.task_alt_outlined, size: 18),
            label: Text(
              order.deliveryType == 'pickup'
                  ? 'Marcar retirado'
                  : 'Marcar entregado',
            ),
          ),
        );
      default:
        return null;
    }
  }

  Widget? _buildSecondaryActionRow(
    BuildContext context,
    WebsiteService websiteService,
    OnlineOrder order, {
    required bool busy,
  }) {
    final hasPhone = _hasCustomerPhone(order);
    final primaryIsInvoice = order.status == 'confirmed' &&
        order.salesInvoiceId == null &&
        order.paymentStatus == 'paid';
    final primaryIsPayment =
        order.status == 'pending' && _canConfirmPayment(order);

    final canMessage = hasPhone && !_isTerminalOrder(order);
    final canViewInvoice = order.salesInvoiceId != null;
    final overflowActions = <_InspectorOverflowAction>[];

    if (order.salesInvoiceId == null &&
        order.paymentStatus == 'paid' &&
        !primaryIsInvoice) {
      overflowActions.add(_InspectorOverflowAction.createInvoice);
    }

    if (_canConfirmPayment(order) && !primaryIsPayment) {
      overflowActions.add(_InspectorOverflowAction.confirmPayment);
    }

    if (!_isTerminalOrder(order)) {
      overflowActions.add(_InspectorOverflowAction.cancelOrder);
    }

    if (!canMessage && !canViewInvoice && overflowActions.isEmpty) {
      return null;
    }

    final iconStyle = IconButton.styleFrom(
      backgroundColor: _accentBlue.withValues(alpha: 0.06),
      foregroundColor: const Color(0xFF334155),
      padding: EdgeInsets.zero,
      minimumSize: const Size(38, 38),
    );

    return Row(
      mainAxisAlignment: (canMessage || canViewInvoice)
          ? MainAxisAlignment.start
          : MainAxisAlignment.end,
      children: [
        if (canMessage)
          IconButton(
            tooltip: 'Mensajería',
            style: iconStyle,
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            onPressed: busy
                ? null
                : () => _openOrderMessagingConversation(
                      context,
                      order,
                    ),
          ),
        if (canMessage && (canViewInvoice || overflowActions.isNotEmpty))
          const SizedBox(width: 8),
        if (canViewInvoice)
          IconButton(
            tooltip: 'Ver factura',
            style: iconStyle,
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            onPressed: busy
                ? null
                : () => context.go('/sales/invoices/${order.salesInvoiceId}'),
          ),
        if ((canMessage || canViewInvoice) && overflowActions.isNotEmpty)
          const Spacer(),
        if (overflowActions.isNotEmpty)
          PopupMenuButton<_InspectorOverflowAction>(
            enabled: !busy,
            tooltip: 'Más acciones',
            onSelected: (action) {
              switch (action) {
                case _InspectorOverflowAction.createInvoice:
                  _processOrder(context, websiteService, order);
                  break;
                case _InspectorOverflowAction.confirmPayment:
                  _confirmOrderPayment(context, websiteService, order);
                  break;
                case _InspectorOverflowAction.cancelOrder:
                  _cancelOrder(context, websiteService, order);
                  break;
              }
            },
            itemBuilder: (context) {
              return overflowActions
                  .map(
                    (action) => PopupMenuItem<_InspectorOverflowAction>(
                      value: action,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          _overflowActionIcon(action),
                          size: 18,
                          color: action == _InspectorOverflowAction.cancelOrder
                              ? Colors.red[700]
                              : const Color(0xFF334155),
                        ),
                        title: Text(
                          _overflowActionLabel(action),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color:
                                action == _InspectorOverflowAction.cancelOrder
                                    ? Colors.red[700]
                                    : const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList();
            },
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _accentBlue.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _borderColor),
              ),
              child: const Icon(
                Icons.more_horiz,
                size: 18,
                color: Color(0xFF334155),
              ),
            ),
          ),
      ],
    );
  }

  IconData _overflowActionIcon(_InspectorOverflowAction action) {
    switch (action) {
      case _InspectorOverflowAction.createInvoice:
        return Icons.receipt_long_outlined;
      case _InspectorOverflowAction.confirmPayment:
        return Icons.payments_outlined;
      case _InspectorOverflowAction.cancelOrder:
        return Icons.cancel_outlined;
    }
  }

  String _overflowActionLabel(_InspectorOverflowAction action) {
    switch (action) {
      case _InspectorOverflowAction.createInvoice:
        return 'Crear factura';
      case _InspectorOverflowAction.confirmPayment:
        return 'Confirmar pago';
      case _InspectorOverflowAction.cancelOrder:
        return 'Cancelar pedido';
    }
  }

  Widget _buildBriefCell(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: _hintStyle),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInventoryReadinessRow(
    _OrderItemReadiness itemReadiness,
  ) {
    final item = itemReadiness.item;
    final color = _inventoryReadinessColor(itemReadiness.level);
    final sku = item.liveProductSku?.trim().isNotEmpty == true
        ? item.liveProductSku!
        : item.productSku?.trim().isNotEmpty == true
            ? item.productSku!
            : 'Sin SKU';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(itemReadiness.icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$sku · Cant. ${item.quantity} · ${_itemStockLabel(item)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _hintStyle,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildInventoryStatusChip(itemReadiness),
        ],
      ),
    );
  }

  Widget _buildInventoryStatusChip(_OrderItemReadiness readiness) {
    final color = _inventoryReadinessColor(readiness.level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(readiness.icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            readiness.title,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelinePanel(OnlineOrder order) {
    final events = _buildOrderTimelineEvents(order);

    return Container(
      decoration: _panelDecoration,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.timeline_outlined, size: 17, color: _accentBlue),
              SizedBox(width: 8),
              Text(
                'Actividad del pedido',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < events.length; index++)
            _buildTimelineEventRow(
              events[index],
              isLast: index == events.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _buildTimelineEventRow(
    _OrderTimelineEvent event, {
    required bool isLast,
  }) {
    final color = _checkpointColor(event.level);
    final dateText = event.date == null
        ? event.fallbackDateLabel
        : ChileanUtils.formatDateTime(event.date!);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.28)),
              ),
              child: Icon(event.icon, size: 14, color: color),
            ),
            if (!isLast)
              Container(
                width: 1,
                height: 34,
                color: _borderColor,
              ),
          ],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        event.title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(dateText, style: _hintStyle),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  event.detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.25,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<_OrderTimelineEvent> _buildOrderTimelineEvents(OnlineOrder order) {
    final events = <_OrderTimelineEvent>[
      _OrderTimelineEvent(
        title: 'Pedido creado',
        detail: 'Recibido desde la tienda online',
        date: order.createdAt,
        level: _CheckpointLevel.done,
        icon: Icons.receipt_long_outlined,
      ),
      _paymentTimelineEvent(order),
      _invoiceTimelineEvent(order),
      _fulfillmentTimelineEvent(order),
    ];

    if (order.status == 'cancelled') {
      events.add(_cancellationTimelineEvent(order));
    }
    if (order.paymentStatus != 'refunded' &&
        (order.refundAmount > 0 || order.refundedAt != null)) {
      events.add(_refundTimelineEvent(order));
    }

    return events;
  }

  _OrderTimelineEvent _paymentTimelineEvent(OnlineOrder order) {
    switch (order.paymentStatus) {
      case 'paid':
        return _OrderTimelineEvent(
          title: 'Pago confirmado',
          detail: _paymentTimelineDetail(order),
          date: order.paidAt,
          fallbackDateLabel: 'Sin fecha',
          level: _CheckpointLevel.done,
          icon: Icons.payments_outlined,
        );
      case 'failed':
        return const _OrderTimelineEvent(
          title: 'Pago fallido',
          detail: 'Resolver el pago antes de preparar o prometer entrega',
          fallbackDateLabel: 'Requiere acción',
          level: _CheckpointLevel.blocked,
          icon: Icons.payment_outlined,
        );
      case 'refunded':
        return _refundTimelineEvent(order);
      default:
        return const _OrderTimelineEvent(
          title: 'Pago pendiente',
          detail: 'Esperando comprobante, validación o captura del pago',
          fallbackDateLabel: 'Pendiente',
          level: _CheckpointLevel.pending,
          icon: Icons.hourglass_empty_outlined,
        );
    }
  }

  String _paymentTimelineDetail(OnlineOrder order) {
    final parts = <String>[_formatPaymentMethod(order.paymentMethod)];
    final reference = order.paymentReference?.trim();
    if (reference != null && reference.isNotEmpty) {
      parts.add('ref. $reference');
    }
    return parts.join(' · ');
  }

  _OrderTimelineEvent _invoiceTimelineEvent(OnlineOrder order) {
    if (order.salesInvoiceId != null) {
      return const _OrderTimelineEvent(
        title: 'Factura vinculada',
        detail: 'Documento de venta conectado al pedido',
        fallbackDateLabel: 'Registrada',
        level: _CheckpointLevel.done,
        icon: Icons.request_quote_outlined,
      );
    }
    if (order.paymentStatus == 'paid') {
      return _OrderTimelineEvent(
        title: 'Factura pendiente',
        detail: _requiresHistoricalInvoiceWarning(order)
            ? 'Pago antiguo: crear factura con fecha original'
            : 'Crear factura antes de preparar o cerrar',
        fallbackDateLabel: 'Bloquea preparación',
        level: _CheckpointLevel.blocked,
        icon: Icons.receipt_long_outlined,
      );
    }
    return const _OrderTimelineEvent(
      title: 'Factura pendiente',
      detail: 'Se emite cuando el pago quede resuelto',
      fallbackDateLabel: 'Pendiente',
      level: _CheckpointLevel.pending,
      icon: Icons.receipt_long_outlined,
    );
  }

  _OrderTimelineEvent _fulfillmentTimelineEvent(OnlineOrder order) {
    switch (order.status) {
      case 'processing':
        return _OrderTimelineEvent(
          title: 'Preparación iniciada',
          detail: 'El pedido está en separación/preparación',
          date: order.updatedAt,
          level: _CheckpointLevel.active,
          icon: Icons.inventory_2_outlined,
        );
      case 'ready_for_pickup':
        return _OrderTimelineEvent(
          title: 'Listo para retiro',
          detail: 'Avisar al cliente desde Mensajería',
          date: order.readyForPickupAt,
          fallbackDateLabel: 'Sin fecha',
          level: _CheckpointLevel.active,
          icon: Icons.storefront_outlined,
        );
      case 'shipped':
        return _OrderTimelineEvent(
          title: 'Despachado',
          detail: order.trackingNumber?.trim().isNotEmpty == true
              ? 'Seguimiento ${order.trackingNumber!.trim()}'
              : 'Sin seguimiento registrado',
          date: order.shippedAt,
          fallbackDateLabel: 'Sin fecha',
          level: _CheckpointLevel.active,
          icon: Icons.local_shipping_outlined,
        );
      case 'delivered':
        return _OrderTimelineEvent(
          title: order.deliveryType == 'pickup' ? 'Retirado' : 'Entregado',
          detail: 'Cumplimiento cerrado',
          date: order.deliveredAt,
          fallbackDateLabel: 'Sin fecha',
          level: _CheckpointLevel.done,
          icon: Icons.task_alt_outlined,
        );
      case 'cancelled':
        return const _OrderTimelineEvent(
          title: 'Cumplimiento detenido',
          detail: 'El pedido fue cancelado antes de cerrar entrega',
          fallbackDateLabel: 'Cancelado',
          level: _CheckpointLevel.blocked,
          icon: Icons.block_outlined,
        );
      case 'confirmed':
        return const _OrderTimelineEvent(
          title: 'Preparación pendiente',
          detail: 'Listo para pasar a preparación cuando no existan bloqueos',
          fallbackDateLabel: 'Pendiente',
          level: _CheckpointLevel.pending,
          icon: Icons.inventory_2_outlined,
        );
      case 'pending':
      default:
        return const _OrderTimelineEvent(
          title: 'Preparación pendiente',
          detail: 'Primero resolver pago y confirmación del pedido',
          fallbackDateLabel: 'Pendiente',
          level: _CheckpointLevel.pending,
          icon: Icons.inventory_2_outlined,
        );
    }
  }

  _OrderTimelineEvent _cancellationTimelineEvent(OnlineOrder order) {
    return _OrderTimelineEvent(
      title: 'Cancelación registrada',
      detail: order.cancelledReason?.trim().isNotEmpty == true
          ? order.cancelledReason!.trim()
          : 'Sin motivo registrado',
      date: order.cancelledAt,
      fallbackDateLabel: 'Sin fecha',
      level: _CheckpointLevel.blocked,
      icon: Icons.cancel_outlined,
    );
  }

  _OrderTimelineEvent _refundTimelineEvent(OnlineOrder order) {
    final amount = order.refundAmount > 0
        ? ChileanUtils.formatCurrency(order.refundAmount)
        : 'Monto no registrado';
    return _OrderTimelineEvent(
      title: 'Reembolso registrado',
      detail: amount,
      date: order.refundedAt,
      fallbackDateLabel: 'Sin fecha',
      level: _CheckpointLevel.done,
      icon: Icons.replay_circle_filled_outlined,
    );
  }

  List<_OrderCheckpoint> _buildOrderCheckpoints(OnlineOrder order) {
    return [
      _paymentCheckpoint(order),
      _invoiceCheckpoint(order),
      _contactCheckpoint(order),
      _preparationCheckpoint(order),
      _fulfillmentCheckpoint(order),
    ];
  }

  _OrderCheckpoint _paymentCheckpoint(OnlineOrder order) {
    switch (order.paymentStatus) {
      case 'paid':
        return _OrderCheckpoint(
          title: 'Pago',
          detail: order.paidAt == null
              ? 'Pago recibido'
              : 'Pagado ${ChileanUtils.formatDate(order.paidAt!)}',
          level: _CheckpointLevel.done,
        );
      case 'failed':
        return const _OrderCheckpoint(
          title: 'Pago',
          detail: 'Pago fallido; no preparar antes de resolver',
          level: _CheckpointLevel.blocked,
        );
      case 'refunded':
        return const _OrderCheckpoint(
          title: 'Pago',
          detail: 'Pago reembolsado; revisar antes de actuar',
          level: _CheckpointLevel.blocked,
        );
      default:
        return const _OrderCheckpoint(
          title: 'Pago',
          detail: 'Esperando confirmación de pago',
          level: _CheckpointLevel.pending,
        );
    }
  }

  _OrderCheckpoint _invoiceCheckpoint(OnlineOrder order) {
    if (order.salesInvoiceId != null) {
      return const _OrderCheckpoint(
        title: 'Factura',
        detail: 'Factura vinculada al pedido',
        level: _CheckpointLevel.done,
      );
    }
    if (order.paymentStatus == 'paid') {
      return const _OrderCheckpoint(
        title: 'Factura',
        detail: 'Crear factura antes de preparar o cerrar',
        level: _CheckpointLevel.blocked,
      );
    }
    return const _OrderCheckpoint(
      title: 'Factura',
      detail: 'Pendiente hasta que el pago esté resuelto',
      level: _CheckpointLevel.pending,
    );
  }

  _OrderCheckpoint _contactCheckpoint(OnlineOrder order) {
    if (_hasCustomerPhone(order)) {
      return _OrderCheckpoint(
        title: 'Contacto',
        detail: order.deliveryType == 'pickup'
            ? 'Teléfono listo para coordinar retiro'
            : 'Teléfono listo para coordinar despacho',
        level: _CheckpointLevel.done,
      );
    }
    return const _OrderCheckpoint(
      title: 'Contacto',
      detail: 'Sin teléfono; completar dato antes de coordinar',
      level: _CheckpointLevel.blocked,
    );
  }

  _OrderCheckpoint _preparationCheckpoint(OnlineOrder order) {
    switch (order.status) {
      case 'pending':
        return const _OrderCheckpoint(
          title: 'Preparación',
          detail: 'Confirmar el pedido antes de preparar',
          level: _CheckpointLevel.pending,
        );
      case 'confirmed':
        return _OrderCheckpoint(
          title: 'Preparación',
          detail: order.salesInvoiceId == null && order.paymentStatus == 'paid'
              ? 'Factura requerida antes de preparar'
              : 'Listo para separar productos',
          level: order.salesInvoiceId == null && order.paymentStatus == 'paid'
              ? _CheckpointLevel.blocked
              : _CheckpointLevel.active,
        );
      case 'processing':
        return const _OrderCheckpoint(
          title: 'Preparación',
          detail: 'Productos en preparación',
          level: _CheckpointLevel.active,
        );
      case 'ready_for_pickup':
      case 'shipped':
      case 'delivered':
        return const _OrderCheckpoint(
          title: 'Preparación',
          detail: 'Preparación completada',
          level: _CheckpointLevel.done,
        );
      case 'cancelled':
        return const _OrderCheckpoint(
          title: 'Preparación',
          detail: 'Pedido cancelado',
          level: _CheckpointLevel.pending,
        );
      default:
        return const _OrderCheckpoint(
          title: 'Preparación',
          detail: 'Revisar estado operativo',
          level: _CheckpointLevel.pending,
        );
    }
  }

  _OrderCheckpoint _fulfillmentCheckpoint(OnlineOrder order) {
    if (order.deliveryType == 'pickup') {
      switch (order.status) {
        case 'ready_for_pickup':
          return const _OrderCheckpoint(
            title: 'Entrega',
            detail: 'Avisar al cliente para retiro',
            level: _CheckpointLevel.active,
          );
        case 'delivered':
          return const _OrderCheckpoint(
            title: 'Entrega',
            detail: 'Pedido retirado en tienda',
            level: _CheckpointLevel.done,
          );
        case 'cancelled':
          return const _OrderCheckpoint(
            title: 'Entrega',
            detail: 'Retiro cancelado',
            level: _CheckpointLevel.pending,
          );
        default:
          return const _OrderCheckpoint(
            title: 'Entrega',
            detail: 'Retiro pendiente de preparación',
            level: _CheckpointLevel.pending,
          );
      }
    }

    if (!_hasShippingAddress(order)) {
      return const _OrderCheckpoint(
        title: 'Entrega',
        detail: 'Sin dirección suficiente para despachar',
        level: _CheckpointLevel.blocked,
      );
    }

    switch (order.status) {
      case 'shipped':
        return _OrderCheckpoint(
          title: 'Entrega',
          detail: order.trackingNumber?.trim().isNotEmpty == true
              ? 'Despachado con seguimiento'
              : 'Despachado sin seguimiento registrado',
          level: _CheckpointLevel.active,
        );
      case 'delivered':
        return const _OrderCheckpoint(
          title: 'Entrega',
          detail: 'Entrega completada',
          level: _CheckpointLevel.done,
        );
      case 'cancelled':
        return const _OrderCheckpoint(
          title: 'Entrega',
          detail: 'Despacho cancelado',
          level: _CheckpointLevel.pending,
        );
      default:
        return const _OrderCheckpoint(
          title: 'Entrega',
          detail: 'Despacho pendiente de preparación',
          level: _CheckpointLevel.pending,
        );
    }
  }

  bool _hasShippingAddress(OnlineOrder order) {
    if (order.deliveryType == 'pickup') return true;
    return order.shippingAddressLine1?.trim().isNotEmpty == true ||
        order.customerAddress?.trim().isNotEmpty == true;
  }

  Color _checkpointColor(_CheckpointLevel level) {
    switch (level) {
      case _CheckpointLevel.done:
        return const Color(0xFF047857);
      case _CheckpointLevel.active:
        return const Color(0xFF1D4ED8);
      case _CheckpointLevel.blocked:
        return const Color(0xFFB91C1C);
      case _CheckpointLevel.pending:
        return const Color(0xFF64748B);
    }
  }

  IconData _checkpointIcon(_CheckpointLevel level) {
    switch (level) {
      case _CheckpointLevel.done:
        return Icons.check_circle_outline;
      case _CheckpointLevel.active:
        return Icons.radio_button_checked;
      case _CheckpointLevel.blocked:
        return Icons.error_outline;
      case _CheckpointLevel.pending:
        return Icons.radio_button_unchecked;
    }
  }

  Widget _buildNoteBlock(String title, String value, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _softSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: Colors.grey[700]),
              const SizedBox(width: 6),
              Text(title, style: _hintStyle),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, height: 1.35),
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
            Column(
              children: [
                for (var index = 0; index < order.items.length; index++)
                  _buildOrderItemRow(
                    order.items[index],
                    isLast: index == order.items.length - 1,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildOrderItemRow(
    OnlineOrderItem item, {
    required bool isLast,
  }) {
    final readiness = _inventoryReadinessForItem(item);
    final sku = item.productSku?.trim().isNotEmpty == true
        ? item.productSku!
        : 'Sin SKU';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: ConstraintLayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 640;
          final product = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.productName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$sku · Cant. ${item.quantity} · Stock ${_itemStockLabel(item)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _hintStyle,
              ),
            ],
          );
          final totals = Column(
            crossAxisAlignment:
                isNarrow ? CrossAxisAlignment.start : CrossAxisAlignment.end,
            children: [
              Text(
                ChileanUtils.formatCurrency(item.subtotal),
                style: const TextStyle(
                  color: _accentBlue,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${ChileanUtils.formatCurrency(item.unitPrice)} c/u',
                style: _hintStyle,
              ),
            ],
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                product,
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildInventoryStatusChip(readiness),
                    totals,
                  ],
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: product),
              const SizedBox(width: 16),
              _buildInventoryStatusChip(readiness),
              const SizedBox(width: 16),
              SizedBox(width: 116, child: totals),
            ],
          );
        },
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
          if (order.refundAmount > 0) ...[
            const Divider(height: 20),
            _buildTotalRow('Reembolso registrado', -order.refundAmount),
          ],
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
    final willCreateInvoice =
        order.paymentStatus == 'paid' && order.salesInvoiceId == null;
    if (willCreateInvoice &&
        !await _confirmHistoricalInvoiceCreationIfNeeded(context, order)) {
      return;
    }
    if (!context.mounted) return;

    await _runOrderAction(context, order, () async {
      if (willCreateInvoice) {
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
    if (!await _confirmHistoricalInvoiceCreationIfNeeded(context, order)) {
      return;
    }
    if (!context.mounted) return;

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

  Future<bool> _confirmHistoricalInvoiceCreationIfNeeded(
    BuildContext context,
    OnlineOrder order,
  ) async {
    if (!_requiresHistoricalInvoiceWarning(order)) return true;

    final referenceDate = order.paidAt ?? order.createdAt;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Crear factura de pago antiguo'),
        content: Text(
          'Este pedido fue pagado el '
          '${ChileanUtils.formatDate(referenceDate)} y todavía no tiene '
          'factura. La factura se creará usando esa fecha para no mover la '
          'contabilidad al día de hoy.\n\n'
          'Continúa solo si es una recuperación real, no un pedido de prueba.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            label: const Text('Crear factura'),
          ),
        ],
      ),
    );

    return confirmed == true;
  }

  bool _requiresHistoricalInvoiceWarning(OnlineOrder order) {
    if (order.paymentStatus != 'paid' || order.salesInvoiceId != null) {
      return false;
    }

    final referenceDate = order.paidAt ?? order.createdAt;
    final age = DateTime.now().difference(referenceDate).inDays;
    return age >= _historicalInvoiceWarningDays;
  }

  Future<void> _startPreparing(
    BuildContext context,
    WebsiteService websiteService,
    OnlineOrder order,
  ) async {
    if (!await _confirmInventoryReadinessForPreparation(context, order)) {
      return;
    }
    if (!context.mounted) return;

    await _updateStatus(
      context,
      websiteService,
      order,
      'processing',
      'Pedido enviado a preparación',
    );
  }

  Future<bool> _confirmInventoryReadinessForPreparation(
    BuildContext context,
    OnlineOrder order,
  ) async {
    final readiness = _inventoryReadinessForOrder(order);
    if (readiness.level == _InventoryReadinessLevel.ready) return true;

    final problemRows = readiness.items
        .where((item) => item.level != _InventoryReadinessLevel.ready)
        .take(6)
        .map((item) => '• ${item.item.productName}: ${item.title}')
        .join('\n');
    final extraCount = readiness.items
            .where((item) => item.level != _InventoryReadinessLevel.ready)
            .length -
        6;
    final details = [
      if (problemRows.isNotEmpty) problemRows,
      if (extraCount > 0)
        '• y $extraCount línea${extraCount == 1 ? '' : 's'} más',
    ].join('\n');

    if (readiness.blocksPreparation) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No se puede preparar todavía'),
          content: Text(
            'Hay problemas de inventario o vínculo de producto que deben '
            'resolverse antes de mover el pedido a preparación.\n\n$details',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return false;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Preparar con advertencias'),
        content: Text(
          'El pedido no tiene bloqueos duros, pero hay señales que conviene '
          'revisar antes de preparar.\n\n$details',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.inventory_2_outlined, size: 18),
            label: const Text('Preparar igual'),
          ),
        ],
      ),
    );

    return confirmed == true;
  }

  Future<void> _markReadyForPickup(
    BuildContext context,
    WebsiteService websiteService,
    OnlineOrder order,
  ) async {
    await _updateStatus(
      context,
      websiteService,
      order,
      'ready_for_pickup',
      'Pedido marcado como listo para retiro',
    );
  }

  Future<void> _markDelivered(
    BuildContext context,
    WebsiteService websiteService,
    OnlineOrder order,
  ) async {
    await _updateStatus(
      context,
      websiteService,
      order,
      'delivered',
      order.deliveryType == 'pickup'
          ? 'Pedido marcado como retirado'
          : 'Pedido marcado como entregado',
    );
  }

  Future<void> _markShipped(
    BuildContext context,
    WebsiteService websiteService,
    OnlineOrder order,
  ) async {
    final details = await _showShippingDialog(context, order);
    if (details == null || !context.mounted) return;

    await _runOrderAction(context, order, () async {
      await websiteService.updateOrderStatus(
        order.id,
        'shipped',
        trackingNumber: details.trackingNumber,
        trackingUrl: details.trackingUrl,
        carrier: details.carrier,
        notes: details.notes,
      );
      if (context.mounted) {
        _showSnackBar(context, 'Pedido marcado como enviado');
      }
    });
  }

  Future<void> _updateStatus(
    BuildContext context,
    WebsiteService websiteService,
    OnlineOrder order,
    String status,
    String successMessage,
  ) async {
    await _runOrderAction(context, order, () async {
      await websiteService.updateOrderStatus(order.id, status);
      if (context.mounted) _showSnackBar(context, successMessage);
    });
  }

  Future<_ShippingDetails?> _showShippingDialog(
    BuildContext context,
    OnlineOrder order,
  ) async {
    final carrierController =
        TextEditingController(text: order.shippingCarrier ?? '');
    final trackingController =
        TextEditingController(text: order.trackingNumber ?? '');
    final trackingUrlController =
        TextEditingController(text: order.trackingUrl ?? '');
    final notesController = TextEditingController();

    try {
      return await showDialog<_ShippingDetails>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Marcar ${order.orderNumber} como enviado'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: carrierController,
                  decoration: const InputDecoration(
                    labelText: 'Transportista',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: trackingController,
                  decoration: const InputDecoration(
                    labelText: 'Número de seguimiento',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: trackingUrlController,
                  decoration: const InputDecoration(
                    labelText: 'URL de seguimiento',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notas internas',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                _ShippingDetails(
                  carrier: _nullIfBlank(carrierController.text),
                  trackingNumber: _nullIfBlank(trackingController.text),
                  trackingUrl: _nullIfBlank(trackingUrlController.text),
                  notes: _nullIfBlank(notesController.text),
                ),
              ),
              child: const Text('Marcar enviado'),
            ),
          ],
        ),
      );
    } finally {
      carrierController.dispose();
      trackingController.dispose();
      trackingUrlController.dispose();
      notesController.dispose();
    }
  }

  Future<void> _editInternalNotes(
    BuildContext context,
    WebsiteService websiteService,
    OnlineOrder order,
  ) async {
    final update = await _showInternalNotesDialog(context, order);
    if (update == null || !context.mounted) return;

    await _runOrderAction(context, order, () async {
      await websiteService.updateOrderNotes(
        order.id,
        internalNotes: update.internalNotes,
      );
      if (context.mounted) _showSnackBar(context, 'Notas actualizadas');
    });
  }

  Future<_InternalNotesUpdate?> _showInternalNotesDialog(
    BuildContext context,
    OnlineOrder order,
  ) async {
    final notesController = TextEditingController(text: order.internalNotes);

    try {
      return await showDialog<_InternalNotesUpdate>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Notas internas ${order.orderNumber}'),
          content: SizedBox(
            width: 520,
            child: TextField(
              controller: notesController,
              minLines: 5,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Notas para el equipo',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(
                context,
                _InternalNotesUpdate(
                  internalNotes: _nullIfBlank(notesController.text),
                ),
              ),
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Guardar'),
            ),
          ],
        ),
      );
    } finally {
      notesController.dispose();
    }
  }

  Future<void> _confirmOrderPayment(
    BuildContext context,
    WebsiteService websiteService,
    OnlineOrder order,
  ) async {
    final confirmation = await _showPaymentConfirmationDialog(context, order);
    if (confirmation == null || !context.mounted) return;

    await _runOrderAction(context, order, () async {
      if (order.salesInvoiceId == null) {
        await websiteService.processOrder(order.id);
      }
      await websiteService.confirmOrderPayment(
        order.id,
        paymentReference: confirmation.reference,
        paymentDate: confirmation.paymentDate,
      );
      if (context.mounted) _showSnackBar(context, 'Pago confirmado');
    });
  }

  Future<_PaymentConfirmation?> _showPaymentConfirmationDialog(
    BuildContext context,
    OnlineOrder order,
  ) async {
    final referenceController =
        TextEditingController(text: order.paymentReference ?? '');
    var paymentDate = order.paidAt ?? DateTime.now();

    try {
      return await showDialog<_PaymentConfirmation>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text('Confirmar pago ${order.orderNumber}'),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Confirma esta acción solo después de revisar el comprobante o la cartola. '
                    'Si el pedido todavía no tiene factura, se creará antes de registrar el pago.',
                    style: _hintStyle,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: referenceController,
                    decoration: const InputDecoration(
                      labelText: 'Referencia / comprobante',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final now = DateTime.now();
                      final pickedDate = await showDatePicker(
                        context: context,
                        initialDate: paymentDate,
                        firstDate: DateTime(now.year - 2),
                        lastDate: DateTime(now.year + 1),
                      );
                      if (pickedDate == null) return;
                      setDialogState(() {
                        paymentDate = DateTime(
                          pickedDate.year,
                          pickedDate.month,
                          pickedDate.day,
                          paymentDate.hour,
                          paymentDate.minute,
                        );
                      });
                    },
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(
                      'Fecha de pago: ${ChileanUtils.formatDate(paymentDate)}',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Volver'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(
                  context,
                  _PaymentConfirmation(
                    reference: _nullIfBlank(referenceController.text),
                    paymentDate: paymentDate,
                  ),
                ),
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: const Text('Confirmar pago'),
              ),
            ],
          ),
        ),
      );
    } finally {
      referenceController.dispose();
    }
  }

  Future<void> _cancelOrder(
    BuildContext context,
    WebsiteService websiteService,
    OnlineOrder order,
  ) async {
    final cancellation = await _showCancelOrderDialog(context, order);
    if (cancellation == null || !context.mounted) return;

    await _runOrderAction(context, order, () async {
      final result = await websiteService.cancelOrder(
        order.id,
        reason: cancellation.reason,
        refundAmount: cancellation.refundAmount,
      );
      final refundAmount = result?['refund_amount'];
      final refundText = refundAmount is num && refundAmount > 0
          ? ' · Reembolso: ${ChileanUtils.formatCurrency(refundAmount.toDouble())}'
          : '';
      if (context.mounted) {
        _showSnackBar(context, 'Pedido cancelado$refundText');
      }
    });
  }

  Future<_OrderCancellation?> _showCancelOrderDialog(
    BuildContext context,
    OnlineOrder order,
  ) async {
    final defaultReason = order.paymentStatus == 'paid'
        ? 'Cancelación solicitada por el cliente'
        : 'Cancelación administrativa';
    final defaultRefund = order.paymentStatus == 'paid' ? order.total : 0.0;
    final reasonController = TextEditingController(text: defaultReason);
    final refundController = TextEditingController(
      text: defaultRefund.round().toString(),
    );
    String? validationMessage;

    try {
      return await showDialog<_OrderCancellation>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text('Cancelar ${order.orderNumber}'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    order.salesInvoiceId == null
                        ? 'El pedido quedará cancelado y se registrará el motivo.'
                        : 'Se cancelará el pedido y la factura vinculada será revertida por el flujo de cancelación.',
                    style: _hintStyle,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: reasonController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Motivo de cancelación',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: refundController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Monto a reembolsar',
                      helperText:
                          'Usa 0 si no corresponde. Máximo ${ChileanUtils.formatCurrency(order.total)}.',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (validationMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      validationMessage!,
                      style: TextStyle(
                        color: Colors.red[700],
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Volver'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red[700],
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  final reason = _nullIfBlank(reasonController.text);
                  final refundAmount = _parseCurrencyAmount(
                    refundController.text,
                  );

                  if (reason == null) {
                    setDialogState(() {
                      validationMessage = 'Ingresa un motivo de cancelación.';
                    });
                    return;
                  }
                  if (refundAmount == null || refundAmount < 0) {
                    setDialogState(() {
                      validationMessage =
                          'Ingresa un monto de reembolso válido.';
                    });
                    return;
                  }
                  if (refundAmount > order.total) {
                    setDialogState(() {
                      validationMessage =
                          'El reembolso no puede superar el total del pedido.';
                    });
                    return;
                  }

                  Navigator.pop(
                    context,
                    _OrderCancellation(
                      reason: reason,
                      refundAmount: refundAmount,
                    ),
                  );
                },
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Cancelar pedido'),
              ),
            ],
          ),
        ),
      );
    } finally {
      reasonController.dispose();
      refundController.dispose();
    }
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
            title: _orderMessagingDraftTitle(order),
            subtitle: _orderMessagingDraftSubtitle(order),
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

    final isPickup = order.deliveryType == 'pickup';
    final paymentText = _buildPaymentCoordinationText(order);
    final deliveryText = _buildDeliveryCoordinationText(order);

    return '''Hola $firstName, te escribimos de Viñabike por tu pedido ${order.orderNumber}.

Resumen:
${itemLines.isEmpty ? '- Productos registrados en tu pedido web' : itemLines}$remaining

Total: ${ChileanUtils.formatCurrency(order.total)}
$paymentText
$deliveryText

${isPickup ? 'Si retirará otra persona, respóndenos con su nombre antes de venir. Gracias.' : 'Gracias.'}''';
  }

  String _orderMessagingDraftTitle(OnlineOrder order) {
    if (order.deliveryType == 'pickup') {
      return order.status == 'ready_for_pickup'
          ? 'Pedido ${order.orderNumber} listo para retiro'
          : 'Coordinar retiro ${order.orderNumber}';
    }

    return order.status == 'shipped'
        ? 'Seguimiento despacho ${order.orderNumber}'
        : 'Coordinar despacho ${order.orderNumber}';
  }

  String _orderMessagingDraftSubtitle(OnlineOrder order) {
    if (order.paymentStatus == 'failed') {
      return 'El pago aparece fallido; revisa y ajusta el texto antes de enviar.';
    }
    if (order.paymentStatus == 'pending') {
      return 'Pide comprobante o confirma el medio de pago antes de prometer preparación.';
    }

    if (order.deliveryType == 'pickup') {
      return order.status == 'ready_for_pickup'
          ? 'Revisa el punto de retiro y envía el aviso desde Mensajería.'
          : 'Confirma quién retira y recuerda que el mensaje no se envía solo.';
    }

    return order.status == 'shipped'
        ? 'Incluye transportista/seguimiento si están disponibles; revisa antes de enviar.'
        : 'Pide confirmación de dirección, comuna y franja horaria antes de despachar.';
  }

  String _buildPaymentCoordinationText(OnlineOrder order) {
    switch (order.paymentStatus) {
      case 'paid':
        return 'El pago figura recibido.';
      case 'failed':
        return 'El pago aparece rechazado o fallido. Para avanzar, necesitamos revisar un nuevo comprobante o confirmar otro medio de pago.';
      case 'refunded':
        return 'El pago figura reembolsado en nuestro sistema.';
      case 'pending':
      default:
        final method = _formatPaymentMethod(order.paymentMethod).toLowerCase();
        if (method.contains('transfer')) {
          return 'Todavía no vemos la transferencia confirmada. Si ya la realizaste, por favor envíanos el comprobante por este chat.';
        }
        return 'El pago todavía aparece pendiente en nuestro sistema.';
    }
  }

  String _buildDeliveryCoordinationText(OnlineOrder order) {
    if (order.deliveryType == 'pickup') {
      if (order.status == 'ready_for_pickup') {
        return '''Tu pedido ya está listo para retiro en tienda.
Punto de retiro: ${order.shippingAddressDisplay}.
Para retirar, trae el número de pedido y el nombre de quien compra.''';
      }

      return '''El pedido quedó marcado para retiro en tienda.
Punto de retiro: ${order.shippingAddressDisplay}.
Te avisaremos por este mismo chat apenas esté listo.''';
    }

    if (!_hasShippingAddress(order)) {
      return '''El pedido está marcado para despacho, pero necesitamos completar la dirección antes de enviarlo.
Por favor respóndenos con dirección, comuna, región y una franja horaria en la que puedas recibir.''';
    }

    if (order.status == 'shipped') {
      final carrier = order.shippingCarrier?.trim();
      final trackingNumber = order.trackingNumber?.trim();
      final trackingUrl = order.trackingUrl?.trim();
      final trackingLines = <String>[
        if (carrier != null && carrier.isNotEmpty) 'Transportista: $carrier',
        if (trackingNumber != null && trackingNumber.isNotEmpty)
          'Seguimiento: $trackingNumber',
        if (trackingUrl != null && trackingUrl.isNotEmpty) trackingUrl,
      ].join('\n');

      return '''Tu pedido fue marcado como despachado.
${trackingLines.isEmpty ? 'Te compartiremos los datos de seguimiento apenas estén disponibles.' : trackingLines}''';
    }

    return '''El pedido está marcado para despacho a:
${order.shippingAddressDisplay}

Para coordinar el despacho, por favor confirma dirección, comuna y una franja horaria en la que puedas recibir.''';
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

  // ignore: unused_element
  Widget _buildNoSelectionState() {
    return Center(child: Text('Selecciona un pedido', style: _hintStyle));
  }

  _OrderInventoryReadiness _inventoryReadinessForOrder(OnlineOrder order) {
    if (order.items.isEmpty) {
      return const _OrderInventoryReadiness(
        level: _InventoryReadinessLevel.blocked,
        title: 'Sin productos',
        detail: 'El pedido no tiene líneas para preparar.',
        icon: Icons.inventory_2_outlined,
        items: [],
      );
    }

    final itemReadiness = order.items.map(_inventoryReadinessForItem).toList();
    final blockedCount = itemReadiness
        .where((item) => item.level == _InventoryReadinessLevel.blocked)
        .length;
    final cautionCount = itemReadiness
        .where((item) => item.level == _InventoryReadinessLevel.caution)
        .length;

    if (blockedCount > 0) {
      return _OrderInventoryReadiness(
        level: _InventoryReadinessLevel.blocked,
        title: 'Bloqueado',
        detail: '$blockedCount línea${blockedCount == 1 ? '' : 's'} con '
            'problemas que impiden preparar el pedido.',
        icon: Icons.report_problem_outlined,
        items: itemReadiness,
      );
    }

    if (cautionCount > 0) {
      return _OrderInventoryReadiness(
        level: _InventoryReadinessLevel.caution,
        title: 'Revisar',
        detail: '$cautionCount línea${cautionCount == 1 ? '' : 's'} requiere '
            'confirmación antes de preparar.',
        icon: Icons.info_outline,
        items: itemReadiness,
      );
    }

    return _OrderInventoryReadiness(
      level: _InventoryReadinessLevel.ready,
      title: 'OK para preparar',
      detail: 'Todos los productos tienen vínculo y stock suficiente.',
      icon: Icons.check_circle_outline,
      items: itemReadiness,
    );
  }

  _OrderItemReadiness _inventoryReadinessForItem(OnlineOrderItem item) {
    final productId = item.productId?.trim();
    if (productId == null || productId.isEmpty) {
      return _OrderItemReadiness(
        item: item,
        level: _InventoryReadinessLevel.blocked,
        code: 'missing_link',
        title: 'Item sin producto',
        detail: 'La línea no tiene product_id; revisar o sustituir antes.',
        icon: Icons.link_off_outlined,
      );
    }

    if (!item.productContextLoaded) {
      return _OrderItemReadiness(
        item: item,
        level: _InventoryReadinessLevel.caution,
        code: 'context_pending',
        title: 'Revisar stock',
        detail: 'No se pudo cargar el contexto de inventario todavía.',
        icon: Icons.sync_problem_outlined,
      );
    }

    if (!item.productExists) {
      return _OrderItemReadiness(
        item: item,
        level: _InventoryReadinessLevel.blocked,
        code: 'missing_product',
        title: 'Producto no encontrado',
        detail: 'El product_id ya no resuelve a una ficha de producto activa.',
        icon: Icons.inventory_2_outlined,
      );
    }

    if (item.productIsActive == false) {
      return _OrderItemReadiness(
        item: item,
        level: _InventoryReadinessLevel.blocked,
        code: 'inactive_product',
        title: 'Producto inactivo',
        detail: 'La ficha existe, pero está inactiva.',
        icon: Icons.block_outlined,
      );
    }

    if (!_itemTracksInventory(item)) {
      return _OrderItemReadiness(
        item: item,
        level: item.productIsPublished == false
            ? _InventoryReadinessLevel.caution
            : _InventoryReadinessLevel.ready,
        code: item.productIsPublished == false ? 'unpublished' : 'non_stock',
        title: item.productIsPublished == false ? 'No publicado' : 'Sin stock',
        detail: item.productIsPublished == false
            ? 'Producto no publicado; confirmar que corresponde al pedido.'
            : 'Esta línea no descuenta inventario.',
        icon: item.productIsPublished == false
            ? Icons.visibility_off_outlined
            : Icons.check_circle_outline,
      );
    }

    final stock = item.productStockQuantity;
    if (stock == null) {
      return _OrderItemReadiness(
        item: item,
        level: _InventoryReadinessLevel.caution,
        code: 'stock_unknown',
        title: 'Stock sin dato',
        detail: 'La ficha no expone stock actual para esta línea.',
        icon: Icons.help_outline,
      );
    }

    if (stock < item.quantity) {
      return _OrderItemReadiness(
        item: item,
        level: _InventoryReadinessLevel.blocked,
        code: 'stock_short',
        title: 'Stock insuficiente',
        detail: 'Disponible $stock de ${item.quantity} requerido(s).',
        icon: Icons.production_quantity_limits_outlined,
      );
    }

    if (stock == item.quantity) {
      return _OrderItemReadiness(
        item: item,
        level: _InventoryReadinessLevel.caution,
        code: 'stock_tight',
        title: 'Stock justo',
        detail: 'Disponible exacto: $stock de ${item.quantity}.',
        icon: Icons.info_outline,
      );
    }

    if (item.productIsPublished == false) {
      return _OrderItemReadiness(
        item: item,
        level: _InventoryReadinessLevel.caution,
        code: 'unpublished',
        title: 'No publicado',
        detail: 'Hay stock, pero la ficha no está publicada en la tienda.',
        icon: Icons.visibility_off_outlined,
      );
    }

    return _OrderItemReadiness(
      item: item,
      level: _InventoryReadinessLevel.ready,
      code: 'ready',
      title: 'Disponible',
      detail: 'Disponible $stock de ${item.quantity} requerido(s).',
      icon: Icons.check_circle_outline,
    );
  }

  bool _itemTracksInventory(OnlineOrderItem item) {
    if (item.productTracksStock != null) return item.productTracksStock!;
    final productType = item.productType?.trim().toLowerCase();
    if (productType == 'service') return false;
    final treatment = item.productPurchaseTreatment?.trim().toLowerCase();
    if (treatment == 'workshop_consumable') return false;
    return true;
  }

  String _itemStockLabel(OnlineOrderItem item) {
    if (item.productId?.trim().isNotEmpty != true) return '-';
    if (!item.productContextLoaded) return 'Revisar';
    if (!item.productExists) return '-';
    if (!_itemTracksInventory(item)) return 'No aplica';
    return item.productStockQuantity?.toString() ?? 'Sin dato';
  }

  Color _inventoryReadinessColor(_InventoryReadinessLevel level) {
    switch (level) {
      case _InventoryReadinessLevel.ready:
        return const Color(0xFF047857);
      case _InventoryReadinessLevel.caution:
        return const Color(0xFFB45309);
      case _InventoryReadinessLevel.blocked:
        return const Color(0xFFB91C1C);
    }
  }

  bool _hasCustomerPhone(OnlineOrder order) {
    return order.customerPhone?.trim().isNotEmpty == true;
  }

  bool _isTerminalOrder(OnlineOrder order) {
    return order.status == 'cancelled' || order.status == 'delivered';
  }

  bool _canConfirmPayment(OnlineOrder order) {
    if (_isTerminalOrder(order)) return false;
    return order.paymentStatus == 'pending' || order.paymentStatus == 'failed';
  }

  int _laneCount(List<OnlineOrder> orders, String lane) {
    return orders.where((order) => _matchesLane(order, lane)).length;
  }

  bool _matchesLane(OnlineOrder order, String lane) {
    switch (lane) {
      case 'attention':
        return !_isTerminalOrder(order) &&
            (_isFulfillmentBlocked(order) ||
                order.status == 'pending' ||
                order.status == 'confirmed' ||
                order.status == 'processing' ||
                order.status == 'ready_for_pickup' ||
                order.status == 'shipped');
      case 'blocked':
        return _isFulfillmentBlocked(order);
      case 'prepare':
        return !_isTerminalOrder(order) &&
            (order.status == 'confirmed' || order.status == 'processing');
      case 'coordination':
        return _needsCoordination(order);
      case 'pickup':
        return order.deliveryType == 'pickup' && !_isTerminalOrder(order);
      case 'shipping':
        return order.deliveryType == 'shipping' && !_isTerminalOrder(order);
      case 'closed':
        return _isTerminalOrder(order);
      case 'all':
      default:
        return true;
    }
  }

  bool _needsCoordination(OnlineOrder order) {
    if (_isTerminalOrder(order) || !_hasCustomerPhone(order)) return false;
    if (order.deliveryType == 'pickup') {
      return order.status == 'pending' ||
          order.status == 'confirmed' ||
          order.status == 'processing' ||
          order.status == 'ready_for_pickup';
    }
    return order.status == 'pending' ||
        order.status == 'confirmed' ||
        order.status == 'processing';
  }

  bool _isFulfillmentBlocked(OnlineOrder order) {
    if (_isTerminalOrder(order)) return false;
    return (order.paymentStatus == 'paid' && order.salesInvoiceId == null) ||
        order.paymentStatus == 'failed' ||
        _requiresHistoricalInvoiceWarning(order) ||
        _inventoryReadinessForOrder(order).blocksPreparation ||
        !_hasCustomerPhone(order) ||
        (order.deliveryType == 'shipping' && !_hasShippingAddress(order));
  }

  List<String> _blockerLabels(OnlineOrder order) {
    final blockers = <String>[];
    if (order.paymentStatus == 'paid' && order.salesInvoiceId == null) {
      blockers.add(_requiresHistoricalInvoiceWarning(order)
          ? 'pago antiguo sin factura'
          : 'pagado sin factura');
    }
    if (order.paymentStatus == 'failed') {
      blockers.add('pago fallido');
    }
    if (!_isTerminalOrder(order) && !_hasCustomerPhone(order)) {
      blockers.add('sin teléfono cliente');
    }
    if (!_isTerminalOrder(order) &&
        order.deliveryType == 'shipping' &&
        !_hasShippingAddress(order)) {
      blockers.add('sin dirección despacho');
    }
    if (!_isTerminalOrder(order)) {
      final readiness = _inventoryReadinessForOrder(order);
      if (readiness.blocksPreparation) {
        final codes = readiness.items.map((item) => item.code).toSet();
        if (order.items.isEmpty) blockers.add('sin productos');
        if (codes.contains('missing_link') ||
            codes.contains('missing_product')) {
          blockers.add('item sin producto');
        }
        if (codes.contains('inactive_product')) {
          blockers.add('producto inactivo');
        }
        if (codes.contains('stock_short')) {
          blockers.add('stock insuficiente');
        }
      }
    }
    if (order.paymentStatus == 'pending' && order.status == 'pending') {
      blockers.add('pago pendiente');
    }
    return blockers;
  }

  IconData _attentionIcon(OnlineOrder order) {
    if (_isFulfillmentBlocked(order)) return Icons.report_problem_outlined;
    switch (order.status) {
      case 'pending':
        return Icons.fiber_new_outlined;
      case 'confirmed':
        return Icons.inventory_2_outlined;
      case 'processing':
        return order.deliveryType == 'pickup'
            ? Icons.storefront_outlined
            : Icons.local_shipping_outlined;
      case 'ready_for_pickup':
        return Icons.notifications_active_outlined;
      case 'shipped':
        return Icons.route_outlined;
      case 'delivered':
        return Icons.task_alt_outlined;
      case 'cancelled':
        return Icons.cancel_outlined;
      default:
        return Icons.receipt_long_outlined;
    }
  }

  String _attentionLabel(OnlineOrder order) {
    final blockers = _blockerLabels(order);
    if (_isFulfillmentBlocked(order) && blockers.isNotEmpty) {
      return 'Bloqueo: ${blockers.join(' · ')}';
    }
    return _nextActionLabel(order);
  }

  String _nextActionLabel(OnlineOrder order) {
    switch (order.status) {
      case 'pending':
        if (order.paymentStatus == 'paid') return 'Confirmar y emitir factura';
        if (_canConfirmPayment(order)) return 'Confirmar pago validado';
        return 'Revisar pago antes de confirmar';
      case 'confirmed':
        if (order.salesInvoiceId != null) {
          return 'Preparar productos del pedido';
        }
        return order.paymentStatus == 'paid'
            ? 'Crear factura antes de preparar'
            : 'Revisar pago antes de facturar';
      case 'processing':
        return order.deliveryType == 'pickup'
            ? 'Dejar listo y avisar retiro'
            : 'Despachar y registrar seguimiento';
      case 'ready_for_pickup':
        return 'Cliente debe retirar en tienda';
      case 'shipped':
        return 'Esperar confirmación de entrega';
      case 'delivered':
        return 'Pedido cerrado';
      case 'cancelled':
        return 'Pedido cancelado';
      default:
        return 'Revisar estado operativo';
    }
  }

  String _pickupFulfillmentLabel(OnlineOrder order) {
    switch (order.status) {
      case 'ready_for_pickup':
        return order.readyForPickupAt == null
            ? 'Listo para retiro'
            : 'Listo desde ${ChileanUtils.formatDate(order.readyForPickupAt!)}';
      case 'delivered':
        return 'Retiro completado';
      case 'cancelled':
        return 'Retiro cancelado';
      default:
        return 'Retiro en tienda pendiente';
    }
  }

  String _shippingFulfillmentLabel(OnlineOrder order) {
    if (order.status == 'delivered') return 'Entrega completada';
    if (order.status == 'cancelled') return 'Despacho cancelado';
    if (order.status == 'shipped') {
      final tracking = order.trackingNumber?.trim();
      return tracking == null || tracking.isEmpty
          ? 'Enviado sin seguimiento'
          : 'Seguimiento $tracking';
    }
    return 'Despacho pendiente';
  }

  static String? _nullIfBlank(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static double? _parseCurrencyAmount(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 0;
    final normalized = trimmed
        .replaceAll(RegExp(r'[^0-9,.-]'), '')
        .replaceAll('.', '')
        .replaceAll(',', '.');
    if (normalized.isEmpty) return 0;
    return double.tryParse(normalized);
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

enum _CheckpointLevel { done, active, blocked, pending }

enum _InventoryReadinessLevel { ready, caution, blocked }

class _OrderInventoryReadiness {
  const _OrderInventoryReadiness({
    required this.level,
    required this.title,
    required this.detail,
    required this.icon,
    required this.items,
  });

  final _InventoryReadinessLevel level;
  final String title;
  final String detail;
  final IconData icon;
  final List<_OrderItemReadiness> items;

  bool get blocksPreparation => level == _InventoryReadinessLevel.blocked;
  bool get requiresConfirmation => level == _InventoryReadinessLevel.caution;
}

class _OrderItemReadiness {
  const _OrderItemReadiness({
    required this.item,
    required this.level,
    required this.code,
    required this.title,
    required this.detail,
    required this.icon,
  });

  final OnlineOrderItem item;
  final _InventoryReadinessLevel level;
  final String code;
  final String title;
  final String detail;
  final IconData icon;
}

class _OrderCheckpoint {
  const _OrderCheckpoint({
    required this.title,
    required this.detail,
    required this.level,
  });

  final String title;
  final String detail;
  final _CheckpointLevel level;
}

class _OrderTimelineEvent {
  const _OrderTimelineEvent({
    required this.title,
    required this.detail,
    required this.level,
    required this.icon,
    this.date,
    this.fallbackDateLabel = 'Sin fecha',
  });

  final String title;
  final String detail;
  final DateTime? date;
  final String fallbackDateLabel;
  final _CheckpointLevel level;
  final IconData icon;
}

enum _InspectorOverflowAction {
  createInvoice,
  confirmPayment,
  cancelOrder,
}

class _InspectorTab {
  const _InspectorTab(this.key, this.label, this.icon);

  final String key;
  final String label;
  final IconData icon;
}

class _OrderLane {
  const _OrderLane({
    required this.key,
    required this.label,
    required this.icon,
  });

  final String key;
  final String label;
  final IconData icon;
}

class _ShippingDetails {
  const _ShippingDetails({
    this.carrier,
    this.trackingNumber,
    this.trackingUrl,
    this.notes,
  });

  final String? carrier;
  final String? trackingNumber;
  final String? trackingUrl;
  final String? notes;
}

class _InternalNotesUpdate {
  const _InternalNotesUpdate({required this.internalNotes});

  final String? internalNotes;
}

class _PaymentConfirmation {
  const _PaymentConfirmation({
    required this.reference,
    required this.paymentDate,
  });

  final String? reference;
  final DateTime paymentDate;
}

class _OrderCancellation {
  const _OrderCancellation({
    required this.reason,
    required this.refundAmount,
  });

  final String reason;
  final double refundAmount;
}
