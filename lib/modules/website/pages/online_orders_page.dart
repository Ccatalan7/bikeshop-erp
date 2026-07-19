import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/interactive_table_field.dart';
import '../../../shared/widgets/modern_context_menu.dart';
import '../../../shared/widgets/operational_status_badge.dart';
import '../../../shared/services/workspace_manager.dart';
import '../widgets/website_admin_ui.dart';
import '../widgets/order_evidence_section.dart';
import '../widgets/online_order_correction_dialog.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/safe_layout_builder.dart';
import '../services/website_service.dart';
import '../models/website_models.dart';
import '../models/online_order_workflow_policy.dart';

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
  static const double _tableRowHeight = 54;

  static const Map<String, double> _defaultColumnWidths = {
    'order': 135,
    'customer': 145,
    'email': 170,
    'created': 95,
    'delivery': 90,
    'items': 55,
    'status': 115,
    'payment': 110,
    'invoice': 100,
    'total': 75,
    'actions': 50,
  };

  final Map<String, double> _columnWidths =
      Map<String, double>.of(_defaultColumnWidths);
  String _selectedStatus = 'all';
  String _selectedPaymentStatus = 'all';
  String _searchTerm = '';
  String _sortKey = 'created';
  bool _sortAscending = false;

  Future<void> _handleCancellation(
    OnlineOrder order,
    WebsiteService websiteService,
  ) async {
    if (order.paymentStatus == 'paid' || order.paidAt != null) {
      await _showOrderCorrection(order, cancelOrder: true);
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
              'La venta ERP vinculada se conservará como cancelada. Si ya había '
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
      await websiteService.updateOrderStatus(
        order.id,
        'cancelled',
        expectedVersion: order.version,
        notes: reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pedido cancelado con su evidencia preservada.'),
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
                'y la venta ERP descontará el inventario una sola vez.',
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
                  label: 'Ver venta ERP',
                  onPressed: () => _openInvoice(order.salesInvoiceId!),
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

  Future<void> _openInvoice(String invoiceId) async {
    await context.push(
      '/sales/invoices/$invoiceId/edit?returnTo=/website/orders',
    );
    if (!mounted) return;
    await context.read<WebsiteService>().loadOrders();
  }

  Future<void> _showOrderCorrection(
    OnlineOrder order, {
    bool cancelOrder = false,
  }) async {
    if (!mounted) return;
    if (order.salesInvoiceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El pago debe estar conciliado con una venta ERP antes de corregirlo.',
          ),
        ),
      );
      return;
    }
    final completed = await showOnlineOrderCorrectionDialog(
      context: context,
      order: order,
      service: context.read<WebsiteService>(),
      cancelOrder: cancelOrder,
    );
    if (completed != true || !mounted) return;
    await context.read<WebsiteService>().loadOrders();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Corrección aplicada con evidencia de dinero, stock y contabilidad.',
        ),
      ),
    );
  }

  Future<void> _openInvoicePreview(OnlineOrder order) async {
    final invoiceId = order.salesInvoiceId;
    if (invoiceId == null || invoiceId.isEmpty) return;
    final uri = Uri(
      path: '/sales/invoices',
      queryParameters: {
        'selectedInvoiceId': invoiceId,
        'view': 'split',
      },
    );
    await context.push(uri.toString());
    if (!mounted) return;
    await context.read<WebsiteService>().loadOrders();
  }

  Future<void> _openCustomer(String customerId) async {
    await context.push('/clientes/$customerId');
  }

  Future<void> _showInvoiceCellContextMenu({
    required TapDownDetails details,
    required OnlineOrder order,
  }) async {
    final invoiceId = order.salesInvoiceId;
    if (invoiceId == null || invoiceId.isEmpty) return;
    final value = await showModernContextMenu<String>(
      context: context,
      globalPosition: details.globalPosition,
      title: 'Venta ERP · ${order.orderNumber}',
      actions: const [
        ModernContextMenuAction(
          value: 'preview',
          icon: Icons.receipt_long_outlined,
          label: 'Abrir vista PDF',
          subtitle: 'Documento interno, panel dividido',
          iconColor: Color(0xFF2563EB),
        ),
        ModernContextMenuAction(
          value: 'edit',
          icon: Icons.edit_outlined,
          label: 'Editar venta ERP',
          subtitle: 'Formulario completo',
          iconColor: Color(0xFF475569),
        ),
      ],
    );
    if (!mounted || value == null) return;
    if (value == 'preview') {
      await _openInvoicePreview(order);
    } else {
      await _openInvoice(invoiceId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final websiteService = context.watch<WebsiteService>();

    final query = _searchTerm.trim().toLowerCase();
    final orders = websiteService.orders.where((order) {
      if (_selectedStatus != 'all' && order.status != _selectedStatus) {
        return false;
      }
      if (_selectedPaymentStatus != 'all' &&
          order.paymentStatus != _selectedPaymentStatus) {
        return false;
      }
      if (query.isNotEmpty) {
        final searchIndex = [
          order.orderNumber,
          order.customerName,
          order.customerEmail,
          order.customerPhone ?? '',
          order.paymentReference ?? '',
          ...order.items.map((item) => item.productName),
          ...order.items.map((item) => item.productSku ?? ''),
        ].join(' ').toLowerCase();
        if (!searchIndex.contains(query)) return false;
      }
      return true;
    }).toList();
    orders.sort(_compareOrders);

    return WebsiteAdminShell(
      embedded: widget.embedded,
      title: 'Pedidos online',
      description: 'Revisa el avance operativo y el estado real de cada pago.',
      actions: [
        IconButton.outlined(
          icon: const Icon(Icons.help_outline_rounded, size: 19),
          onPressed: _showOperationsGuide,
          tooltip: 'Guía operativa',
        ),
        IconButton.outlined(
          icon: const Icon(Icons.refresh_rounded, size: 19),
          onPressed: () => websiteService.loadOrders(),
          tooltip: 'Actualizar pedidos',
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filters
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
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
                            value: 'ready_for_pickup',
                            child: Text('Listo para retiro'),
                          ),
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
                          DropdownMenuItem(
                              value: 'paid', child: Text('Pagado')),
                          DropdownMenuItem(
                              value: 'failed', child: Text('Fallido')),
                          DropdownMenuItem(
                              value: 'refunded', child: Text('Reembolsado')),
                        ],
                        onChanged: (value) {
                          setState(
                              () => _selectedPaymentStatus = value ?? 'all');
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

                return Row(
                  children: [
                    SizedBox(
                      width: 300,
                      child: TextField(
                        onChanged: (value) =>
                            setState(() => _searchTerm = value),
                        decoration: const InputDecoration(
                          hintText: 'Buscar pedido, cliente, email o producto…',
                          prefixIcon: Icon(Icons.search_rounded, size: 19),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 185,
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _selectedStatus,
                        decoration: const InputDecoration(
                          labelText: 'Estado',
                          prefixIcon: Icon(Icons.route_outlined, size: 18),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('Todos')),
                          DropdownMenuItem(
                              value: 'pending', child: Text('Pendiente')),
                          DropdownMenuItem(
                              value: 'confirmed', child: Text('Confirmado')),
                          DropdownMenuItem(
                              value: 'processing', child: Text('En proceso')),
                          DropdownMenuItem(
                            value: 'ready_for_pickup',
                            child: Text('Listo para retiro'),
                          ),
                          DropdownMenuItem(
                              value: 'shipped', child: Text('Enviado')),
                          DropdownMenuItem(
                              value: 'delivered', child: Text('Entregado')),
                          DropdownMenuItem(
                              value: 'cancelled', child: Text('Cancelado')),
                        ],
                        onChanged: (value) => setState(
                          () => _selectedStatus = value ?? 'all',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 185,
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _selectedPaymentStatus,
                        decoration: const InputDecoration(
                          labelText: 'Pago',
                          prefixIcon: Icon(Icons.payments_outlined, size: 18),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('Todos')),
                          DropdownMenuItem(
                              value: 'pending', child: Text('Pendiente')),
                          DropdownMenuItem(
                              value: 'paid', child: Text('Pagado')),
                          DropdownMenuItem(
                              value: 'failed', child: Text('Fallido')),
                          DropdownMenuItem(
                              value: 'refunded', child: Text('Reembolsado')),
                        ],
                        onChanged: (value) => setState(
                          () => _selectedPaymentStatus = value ?? 'all',
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _resetAllColumnWidths,
                      tooltip: 'Restablecer ancho de columnas',
                      icon: const Icon(Icons.view_column_outlined, size: 19),
                    ),
                    const SizedBox(width: 6),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${orders.length} pedidos',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          ChileanUtils.formatCurrency(
                            orders.fold<double>(
                              0,
                              (total, order) => total + order.total,
                            ),
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),

          if (websiteService.ordersEnrichmentWarning != null)
            _OrdersLoadNotice(
              message: websiteService.ordersEnrichmentWarning!,
              onRetry: websiteService.loadOrders,
            ),

          // Orders List
          Expanded(
            child: websiteService.isLoading
                ? const Center(child: BrandedLoading())
                : websiteService.ordersLoadError != null &&
                        websiteService.orders.isEmpty
                    ? WebsiteAdminEmptyState(
                        icon: Icons.error_outline_rounded,
                        title: 'No se pudieron cargar los pedidos',
                        description: websiteService.ordersLoadError!,
                      )
                    : orders.isEmpty
                        ? WebsiteAdminEmptyState(
                            icon: Icons.shopping_bag_outlined,
                            title: 'No hay pedidos en esta vista',
                            description: _selectedStatus == 'all' &&
                                    _selectedPaymentStatus == 'all'
                                ? 'Cuando entre una compra desde el sitio aparecerá aquí con su pago y trazabilidad.'
                                : 'Cambia los filtros para revisar otros estados de pedido o pago.',
                          )
                        : _buildOrdersTable(orders),
          ),
        ],
      ),
    );
  }

  int _compareOrders(OnlineOrder a, OnlineOrder b) {
    int comparison;
    switch (_sortKey) {
      case 'order':
        comparison = a.orderNumber.compareTo(b.orderNumber);
        break;
      case 'customer':
        comparison = a.customerName.compareTo(b.customerName);
        break;
      case 'email':
        comparison = a.customerEmail.compareTo(b.customerEmail);
        break;
      case 'delivery':
        comparison = a.deliveryType.compareTo(b.deliveryType);
        break;
      case 'items':
        final aItems = a.items.fold<int>(
          0,
          (total, item) => total + item.quantity,
        );
        final bItems = b.items.fold<int>(
          0,
          (total, item) => total + item.quantity,
        );
        comparison = aItems.compareTo(bItems);
        break;
      case 'status':
        comparison = a.status.compareTo(b.status);
        break;
      case 'payment':
        comparison = a.paymentStatus.compareTo(b.paymentStatus);
        break;
      case 'total':
        comparison = a.total.compareTo(b.total);
        break;
      case 'invoice':
        comparison = (a.salesInvoiceId != null ? 1 : 0)
            .compareTo(b.salesInvoiceId != null ? 1 : 0);
        break;
      case 'created':
      default:
        comparison = a.createdAt.compareTo(b.createdAt);
        break;
    }
    return _sortAscending ? comparison : -comparison;
  }

  void _changeSort(String key) {
    setState(() {
      if (_sortKey == key) {
        _sortAscending = !_sortAscending;
      } else {
        _sortKey = key;
        _sortAscending = key != 'created';
      }
    });
  }

  double _columnWidth(String key) =>
      _columnWidths[key] ?? _defaultColumnWidths[key] ?? 80;

  double _minimumColumnWidth(String key) {
    return switch (key) {
      'order' => 105,
      'customer' => 100,
      'email' => 125,
      'created' => 88,
      'delivery' => 78,
      'items' => 52,
      'status' => 92,
      'payment' => 88,
      'invoice' => 84,
      'total' => 72,
      'actions' => 46,
      _ => 60,
    };
  }

  void _resizeColumn(String key, double delta) {
    setState(() {
      final current = _columnWidth(key);
      _columnWidths[key] =
          (current + delta).clamp(_minimumColumnWidth(key), 420).toDouble();
    });
  }

  void _resetColumnWidth(String key) {
    setState(() => _columnWidths[key] = _defaultColumnWidths[key]!);
  }

  void _resetAllColumnWidths() {
    setState(() {
      _columnWidths
        ..clear()
        ..addAll(_defaultColumnWidths);
    });
  }

  Widget _buildOrdersTable(List<OnlineOrder> orders) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final rawWidth = _columnWidths.values.fold<double>(
          0,
          (total, width) => total + width,
        );
        final tableWidth =
            constraints.maxWidth > rawWidth ? constraints.maxWidth : rawWidth;
        final stretchableWidth = rawWidth - _columnWidth('actions');
        final extraWidth = tableWidth - rawWidth;
        final effectiveWidths = <String, double>{
          for (final entry in _columnWidths.entries)
            entry.key: entry.key == 'actions' || extraWidth <= 0
                ? entry.value
                : entry.value + extraWidth * (entry.value / stretchableWidth),
        };
        double widthOf(String key) => effectiveWidths[key]!;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            height: constraints.maxHeight,
            child: Column(
              children: [
                Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A3C66),
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.black.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      _buildTableHeader(
                        'Pedido',
                        widthOf('order'),
                        columnKey: 'order',
                        sortKey: 'order',
                      ),
                      _buildTableHeader(
                        'Cliente',
                        widthOf('customer'),
                        columnKey: 'customer',
                        sortKey: 'customer',
                      ),
                      _buildTableHeader(
                        'Email',
                        widthOf('email'),
                        columnKey: 'email',
                        sortKey: 'email',
                      ),
                      _buildTableHeader(
                        'Fecha',
                        widthOf('created'),
                        columnKey: 'created',
                        sortKey: 'created',
                      ),
                      _buildTableHeader(
                        'Entrega',
                        widthOf('delivery'),
                        columnKey: 'delivery',
                        sortKey: 'delivery',
                      ),
                      _buildTableHeader(
                        'Ítems',
                        widthOf('items'),
                        columnKey: 'items',
                        sortKey: 'items',
                      ),
                      _buildTableHeader(
                        'Estado',
                        widthOf('status'),
                        columnKey: 'status',
                        sortKey: 'status',
                      ),
                      _buildTableHeader(
                        'Pago',
                        widthOf('payment'),
                        columnKey: 'payment',
                        sortKey: 'payment',
                      ),
                      _buildTableHeader(
                        'Venta ERP',
                        widthOf('invoice'),
                        columnKey: 'invoice',
                        sortKey: 'invoice',
                      ),
                      _buildTableHeader(
                        'Total',
                        widthOf('total'),
                        columnKey: 'total',
                        sortKey: 'total',
                        alignment: Alignment.centerRight,
                      ),
                      _buildTableHeader(
                        '',
                        widthOf('actions'),
                        columnKey: 'actions',
                        alignment: Alignment.center,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ColoredBox(
                    color: theme.colorScheme.surface,
                    child: ListView.builder(
                      itemCount: orders.length,
                      itemBuilder: (context, index) => _buildOrderTableRow(
                        orders[index],
                        widths: effectiveWidths,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTableHeader(
    String label,
    double width, {
    required String columnKey,
    String? sortKey,
    Alignment alignment = Alignment.centerLeft,
  }) {
    final active = sortKey != null && _sortKey == sortKey;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.15,
          ),
        ),
        if (active) ...[
          const SizedBox(width: 4),
          Icon(
            _sortAscending
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            size: 13,
            color: Colors.white,
          ),
        ],
      ],
    );
    return SizedBox(
      width: width,
      height: 40,
      child: Stack(
        children: [
          Positioned.fill(
            child: InkWell(
              onTap: sortKey == null ? null : () => _changeSort(sortKey),
              hoverColor: Colors.white.withValues(alpha: 0.08),
              child: Align(
                alignment: alignment,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: content,
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (details) =>
                    _resizeColumn(columnKey, details.delta.dx),
                onDoubleTap: () => _resetColumnWidth(columnKey),
                child: SizedBox(
                  width: 8,
                  child: Center(
                    child: Container(
                      width: 1,
                      height: 20,
                      color: Colors.white.withValues(alpha: 0.38),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderTableRow(
    OnlineOrder order, {
    required Map<String, double> widths,
  }) {
    final theme = Theme.of(context);
    final statusColor = _getStatusColor(order.status);
    final paymentColor = _getPaymentStatusColor(order.paymentStatus);
    final legalNextStatuses = OnlineOrderWorkflowPolicy.legalNextStatuses(
      currentStatus: order.status,
      deliveryType: order.deliveryType,
      paymentStatus: order.paymentStatus,
    );
    final canConfirmManualPayment =
        OnlineOrderWorkflowPolicy.canConfirmManualPayment(
      orderStatus: order.status,
      paymentStatus: order.paymentStatus,
      paymentMethod: order.paymentMethod,
      hasInvoice: order.salesInvoiceId != null,
    );
    final webhookOwnsPayment = order.paymentStatus == 'pending' &&
        OnlineOrderWorkflowPolicy.isWebhookOwnedPayment(order.paymentMethod);
    final itemQuantity = order.items.fold<int>(
      0,
      (total, item) => total + item.quantity,
    );
    final hasNotes = [order.customerNotes, order.internalNotes, order.notes]
        .any((note) => note != null && note.trim().isNotEmpty);
    final deliveryLabel = switch (order.deliveryType.toLowerCase()) {
      'pickup' || 'retiro' => 'Retiro',
      _ => 'Despacho',
    };

    return Material(
      color: theme.colorScheme.surface,
      child: InkWell(
        onTap: () => _showOrderInspector(order),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outline.withValues(alpha: 0.48),
              ),
            ),
          ),
          child: SizedBox(
            height: _tableRowHeight,
            child: Row(
              children: [
                _buildTableCell(
                  width: widths['order']!,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          order.orderNumber,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (hasNotes) ...[
                        const SizedBox(width: 5),
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ],
                  ),
                ),
                _buildTableCell(
                  width: widths['customer']!,
                  child: InteractiveTableField(
                    onTap: order.customerId == null
                        ? null
                        : () => _openCustomer(order.customerId!),
                    maxWidth: widths['customer']! - 20,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      order.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: order.customerId == null
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                _buildTableCell(
                  width: widths['email']!,
                  child: Text(
                    order.customerEmail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                _buildTableCell(
                  width: widths['created']!,
                  child: Text(
                    ChileanUtils.formatDate(order.createdAt),
                    maxLines: 1,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                _buildTableCell(
                  width: widths['delivery']!,
                  child: Text(
                    deliveryLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                _buildTableCell(
                  width: widths['items']!,
                  alignment: Alignment.center,
                  child: Text(
                    '$itemQuantity',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _buildTableCell(
                  width: widths['status']!,
                  child: _buildStatusLabel(
                    order.statusDisplayName,
                    statusColor,
                    maxWidth: widths['status']! - 20,
                    compact: true,
                    onTap: legalNextStatuses.isEmpty
                        ? null
                        : () => _showOrderStatusMenu(order),
                  ),
                ),
                _buildTableCell(
                  width: widths['payment']!,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: _buildStatusLabel(
                          order.paymentStatusDisplayName,
                          paymentColor,
                          maxWidth: widths['payment']! -
                              (order.hasPaymentProcessingAttention ? 38 : 20),
                          compact: true,
                          onTap: order.hasPaymentProcessingAttention
                              ? () => _showPaymentProcessingAction(order)
                              : canConfirmManualPayment
                                  ? () => _handlePaymentConfirmation(
                                        order,
                                        context.read<WebsiteService>(),
                                      )
                                  : null,
                          tooltip: order.hasPaymentProcessingAttention
                              ? 'El pago está preservado, pero la venta ERP requiere atención.'
                              : webhookOwnsPayment
                                  ? 'Mercado Pago actualiza este estado automáticamente mediante su webhook.'
                                  : null,
                        ),
                      ),
                      if (order.hasPaymentProcessingAttention) ...[
                        const SizedBox(width: 5),
                        Tooltip(
                          message: order.paymentProcessingRequiresRefundReview
                              ? 'Requiere conciliación del cobro o reembolso.'
                              : 'Requiere completar stock, venta ERP o contabilidad.',
                          child: const Icon(
                            Icons.error_outline_rounded,
                            size: 16,
                            color: Color(0xFF9A6700),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _buildTableCell(
                  width: widths['invoice']!,
                  child: _buildInvoiceTableCell(order, widths['invoice']!),
                ),
                _buildTableCell(
                  width: widths['total']!,
                  alignment: Alignment.centerRight,
                  child: Text(
                    ChileanUtils.formatCurrency(order.total),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                _buildTableCell(
                  width: widths['actions']!,
                  alignment: Alignment.center,
                  horizontalPadding: 0,
                  child: _buildOrderTableActions(order),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTableCell({
    required double width,
    required Widget child,
    Alignment alignment = Alignment.centerLeft,
    double horizontalPadding = 10,
  }) {
    return SizedBox(
      width: width,
      height: _tableRowHeight,
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: child,
        ),
      ),
    );
  }

  Widget _buildInvoiceTableCell(OnlineOrder order, double width) {
    final theme = Theme.of(context);
    final invoiceId = order.salesInvoiceId;
    if (invoiceId != null && invoiceId.isNotEmpty) {
      return Tooltip(
        message: 'Abrir venta ERP · clic secundario para más opciones',
        child: InteractiveTableField(
          onTap: () => _openInvoice(invoiceId),
          onSecondaryTapDown: (details) => _showInvoiceCellContextMenu(
            details: details,
            order: order,
          ),
          accentColor: theme.colorScheme.primary,
          maxWidth: width - 20,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.verified_outlined,
                size: 14,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  'Vinculada',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (order.hasPaymentProcessingAttention) {
      return InteractiveTableField(
        onTap: () => _showPaymentProcessingAction(order),
        accentColor: const Color(0xFF9A6700),
        maxWidth: width - 20,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 14,
              color: Color(0xFF9A6700),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                order.paymentProcessingRequiresRefundReview
                    ? 'Conciliar'
                    : 'Revisar',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF7A5200),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (order.paymentStatus == 'paid' && order.status != 'cancelled') {
      return InteractiveTableField(
        onTap: () => _createInvoice(order, context.read<WebsiteService>()),
        accentColor: theme.colorScheme.primary,
        maxWidth: width - 20,
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_circle_outline_rounded,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  'Generar',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.receipt_long_outlined,
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            'Pendiente',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showOrderStatusMenu(OnlineOrder order) async {
    final nextStatuses = OnlineOrderWorkflowPolicy.legalNextStatuses(
      currentStatus: order.status,
      deliveryType: order.deliveryType,
      paymentStatus: order.paymentStatus,
    );
    if (nextStatuses.isEmpty) return;
    final theme = Theme.of(context);
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Siguiente estado',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${order.orderNumber} · ${order.statusDisplayName}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      tooltip: 'Cerrar',
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
              for (var index = 0; index < nextStatuses.length; index++) ...[
                _buildStatusTransitionRow(
                  dialogContext,
                  nextStatuses[index],
                ),
                if (index < nextStatuses.length - 1)
                  Divider(
                    height: 1,
                    indent: 58,
                    color: theme.colorScheme.outlineVariant,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await _applyOrderStatusTransition(order, selected);
  }

  Widget _buildStatusTransitionRow(
    BuildContext dialogContext,
    String status,
  ) {
    final theme = Theme.of(dialogContext);
    final definition = OnlineOrderWorkflowPolicy.definitionFor(status);
    final destructive = status == 'cancelled';
    final color = destructive
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: () => Navigator.pop(dialogContext, status),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        child: Row(
          children: [
            Icon(_statusActionIcon(status), size: 20, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    OnlineOrderWorkflowPolicy.actionLabel(status),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: destructive ? theme.colorScheme.error : null,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    definition.meaning,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 19,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  IconData _statusActionIcon(String status) {
    return switch (status) {
      'confirmed' => Icons.check_circle_outline_rounded,
      'processing' => Icons.inventory_2_outlined,
      'ready_for_pickup' => Icons.storefront_outlined,
      'shipped' => Icons.local_shipping_outlined,
      'delivered' => Icons.task_alt_rounded,
      'cancelled' => Icons.cancel_outlined,
      _ => Icons.arrow_forward_rounded,
    };
  }

  Future<void> _applyOrderStatusTransition(
    OnlineOrder order,
    String newStatus,
  ) async {
    final websiteService = context.read<WebsiteService>();
    if (newStatus == 'cancelled') {
      await _handleCancellation(order, websiteService);
      return;
    }

    _ShippingTransitionInput? shipping;
    if (newStatus == 'shipped') {
      shipping = await _requestShippingDetails(order);
      if (shipping == null || !mounted) return;
    }

    try {
      final invoiceId = await websiteService.updateOrderStatus(
        order.id,
        newStatus,
        expectedVersion: order.version,
        trackingNumber: shipping?.trackingNumber,
        trackingUrl: shipping?.trackingUrl,
        carrier: shipping?.carrier,
      );
      if (!mounted) return;
      final definition = OnlineOrderWorkflowPolicy.definitionFor(newStatus);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${order.orderNumber} ahora está ${definition.label.toLowerCase()}.',
          ),
          action: invoiceId == null
              ? null
              : SnackBarAction(
                  label: 'ABRIR VENTA',
                  onPressed: () => _openInvoice(invoiceId),
                ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo cambiar el estado: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<_ShippingTransitionInput?> _requestShippingDetails(
    OnlineOrder order,
  ) async {
    final carrierController =
        TextEditingController(text: order.shippingCarrier);
    final trackingController =
        TextEditingController(text: order.trackingNumber);
    final urlController = TextEditingController(text: order.trackingUrl);
    final result = await showDialog<_ShippingTransitionInput>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Registrar despacho · ${order.orderNumber}'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: carrierController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Transportista',
                  hintText: 'Ej.: Chilexpress',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: trackingController,
                decoration: const InputDecoration(
                  labelText: 'Número de seguimiento',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'Enlace de seguimiento',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              _ShippingTransitionInput(
                carrier: _optionalText(carrierController.text),
                trackingNumber: _optionalText(trackingController.text),
                trackingUrl: _optionalText(urlController.text),
              ),
            ),
            child: const Text('Registrar despacho'),
          ),
        ],
      ),
    );
    carrierController.dispose();
    trackingController.dispose();
    urlController.dispose();
    return result;
  }

  String? _optionalText(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  Widget _buildOrderTableActions(OnlineOrder order) {
    final websiteService = context.read<WebsiteService>();
    final legalNextStatuses = OnlineOrderWorkflowPolicy.legalNextStatuses(
      currentStatus: order.status,
      deliveryType: order.deliveryType,
      paymentStatus: order.paymentStatus,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<String>(
          tooltip: 'Más acciones',
          onSelected: (value) async {
            switch (value) {
              case 'confirm_payment':
                await _handlePaymentConfirmation(order, websiteService);
                break;
              case 'create_invoice':
                await _createInvoice(order, websiteService);
                break;
              case 'payment_processing':
                await _showPaymentProcessingAction(order);
                break;
              case 'open_invoice':
                if (order.salesInvoiceId != null && mounted) {
                  await _openInvoice(order.salesInvoiceId!);
                }
                break;
              case 'correction':
                await _showOrderCorrection(order);
                break;
              case 'cancel':
                await _handleCancellation(order, websiteService);
                break;
            }
          },
          itemBuilder: (context) => [
            if (OnlineOrderWorkflowPolicy.canConfirmManualPayment(
              orderStatus: order.status,
              paymentStatus: order.paymentStatus,
              paymentMethod: order.paymentMethod,
              hasInvoice: order.salesInvoiceId != null,
            ))
              const PopupMenuItem(
                value: 'confirm_payment',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.account_balance_outlined),
                  title: Text('Confirmar pago'),
                ),
              ),
            if (order.hasPaymentProcessingAttention)
              PopupMenuItem(
                value: 'payment_processing',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.error_outline_rounded),
                  title: Text(
                    order.paymentProcessingRequiresRefundReview
                        ? 'Conciliar cobro'
                        : 'Revisar procesamiento',
                  ),
                ),
              ),
            if (order.salesInvoiceId == null &&
                order.paymentStatus == 'paid' &&
                !order.hasPaymentProcessingAttention)
              const PopupMenuItem(
                value: 'create_invoice',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.receipt_long_outlined),
                  title: Text('Crear venta ERP'),
                ),
              ),
            if (order.salesInvoiceId != null)
              const PopupMenuItem(
                value: 'open_invoice',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.open_in_new_rounded),
                  title: Text('Abrir venta ERP'),
                ),
              ),
            if (order.salesInvoiceId != null && order.paymentStatus == 'paid')
              const PopupMenuItem(
                value: 'correction',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.assignment_return_outlined),
                  title: Text('Gestionar devolución'),
                ),
              ),
            if (legalNextStatuses.contains('cancelled'))
              PopupMenuItem(
                value: 'cancel',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.cancel_outlined),
                  title: Text(
                    order.paymentStatus == 'paid'
                        ? 'Gestionar devolución'
                        : 'Cancelar pedido',
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _createInvoice(
    OnlineOrder order,
    WebsiteService websiteService,
  ) async {
    if (order.hasPaymentProcessingAttention) {
      await _showPaymentProcessingAction(order);
      return;
    }
    try {
      final invoiceId = await websiteService.processOrder(order.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            invoiceId == null
                ? 'El pedido fue procesado, pero no devolvió una venta ERP para abrir.'
                : 'Venta ERP creada: $invoiceId',
          ),
          action: invoiceId == null
              ? null
              : SnackBarAction(
                  label: 'Abrir',
                  onPressed: () => _openInvoice(invoiceId),
                ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo crear la venta ERP: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _showPaymentProcessingAction(OnlineOrder order) async {
    final eventId = order.paymentProcessingEventId;
    if (eventId == null || !mounted) return;
    final actorCanRetry =
        context.read<WebsiteService>().canRetryOnlineOrderPaymentProcessing;

    final shouldRetry = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final needsReconciliation = order.paymentProcessingRequiresRefundReview;
        final detail = order.paymentProcessingErrorMessage?.trim();
        return AlertDialog(
          icon: Icon(
            needsReconciliation
                ? Icons.account_balance_wallet_outlined
                : Icons.sync_problem_rounded,
            color: const Color(0xFF9A6700),
          ),
          title: Text(
            needsReconciliation
                ? 'Conciliar pago de Mercado Pago'
                : 'Completar procesamiento de la venta',
          ),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.paymentProviderStatus == 'approved'
                      ? 'Mercado Pago confirmó el cobro y esa evidencia está preservada. '
                          'La venta ERP, el stock y la contabilidad son una etapa separada.'
                      : 'Existe una observación de Mercado Pago que requiere revisión antes de continuar.',
                ),
                if (detail != null && detail.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    detail,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  needsReconciliation
                      ? 'No descuentes stock ni crees una venta manual. Revisa el pago en Mercado Pago y gestiona la conciliación o el reembolso; luego conserva el comprobante de esa corrección.'
                      : 'Verifica primero que el stock físico sea suficiente. El reintento es idempotente: si la venta ya quedó completa, no la duplicará.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (order.paymentProcessingAttemptCount > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${order.paymentProcessingAttemptCount} intento${order.paymentProcessingAttemptCount == 1 ? '' : 's'} registrado${order.paymentProcessingAttemptCount == 1 ? '' : 's'}.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (order.canRetryPaymentProcessing && !actorCanRetry) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Tu perfil puede revisar la incidencia, pero el reintento debe realizarlo administración, gerencia o caja.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cerrar'),
            ),
            if (order.canRetryPaymentProcessing && actorCanRetry)
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reintentar procesamiento'),
              ),
          ],
        );
      },
    );

    if (shouldRetry != true || !mounted) return;
    try {
      final result = await context
          .read<WebsiteService>()
          .retryMercadoPagoPaymentProcessing(eventId);
      if (!mounted) return;
      final state = result['processing_state']?.toString();
      final invoiceId = result['invoice_id']?.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            state == 'processed'
                ? 'Pago conciliado: venta, stock y contabilidad quedaron procesados.'
                : 'El pago sigue preservado, pero el procesamiento aún requiere atención.',
          ),
          action:
              state == 'processed' && invoiceId != null && invoiceId.isNotEmpty
                  ? SnackBarAction(
                      label: 'Abrir venta',
                      onPressed: () => _openInvoice(invoiceId),
                    )
                  : null,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo reintentar: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _showOperationsGuide() async {
    final theme = Theme.of(context);
    final lifecycle = OnlineOrderWorkflowPolicy.definitions
        .where((definition) => definition.status != 'cancelled')
        .toList();
    final cancelled = OnlineOrderWorkflowPolicy.definitionFor('cancelled');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860, maxHeight: 760),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                color: const Color(0xFF0A3C66),
                padding: const EdgeInsets.fromLTRB(24, 20, 14, 18),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(
                        Icons.route_outlined,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Guía operativa de pedidos online',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Qué significa cada estado y cuál es la siguiente acción segura.',
                            style: TextStyle(
                              color: Color(0xFFD7E6F3),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      tooltip: 'Cerrar',
                      color: Colors.white,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Flujo operativo',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'El chip Estado ofrece únicamente el siguiente avance válido para ese pedido y su modalidad de entrega.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 14),
                      for (var index = 0;
                          index < lifecycle.length;
                          index++) ...[
                        _buildGuideWorkflowStep(lifecycle[index]),
                        if (index < lifecycle.length - 1)
                          Divider(
                            height: 1,
                            indent: 150,
                            color: theme.colorScheme.outlineVariant,
                          ),
                      ],
                      const SizedBox(height: 20),
                      Text(
                        'Pago, venta ERP y documento fiscal',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildGuideFact(
                        icon: Icons.account_balance_outlined,
                        title: 'Transferencia pendiente',
                        description:
                            'Después de comprobar el abono en el banco, haz clic en el chip Pago y registra referencia y fecha efectiva.',
                      ),
                      _buildGuideFact(
                        icon: Icons.sync_rounded,
                        title: 'Mercado Pago',
                        description:
                            'El webhook valida el pago y actualiza el pedido automáticamente. No confirmes ese pago de forma manual.',
                      ),
                      _buildGuideFact(
                        icon: Icons.sync_problem_rounded,
                        title: 'Pago confirmado con acción pendiente',
                        description:
                            'El cobro no se pierde si falla stock, venta ERP o contabilidad. Abre Revisar y reintenta solo cuando no se solicite conciliación o reembolso; nunca ajustes stock manualmente para ocultar el error.',
                      ),
                      _buildGuideFact(
                        icon: Icons.receipt_long_outlined,
                        title: 'Venta ERP vinculada',
                        description:
                            'Haz clic en Venta ERP para abrir el registro que controla stock y contabilidad. No lo confundas con la boleta de Mercado Pago.',
                      ),
                      _buildGuideFact(
                        icon: Icons.verified_user_outlined,
                        title: 'Boleta o voucher oficial',
                        description:
                            'Un pago aprobado no basta. El sistema solo presenta y envía el comprobante oficial de Mercado Pago como boleta cuando conserva el documento completo y Viña Bike tiene declarado en SII el modelo que le da esa validez. Una transferencia requiere una boleta electrónica separada.',
                      ),
                      _buildGuideFact(
                        icon: Icons.cancel_outlined,
                        title: cancelled.label,
                        description:
                            '${cancelled.meaning} ${cancelled.nextAction}',
                        destructive: true,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuideWorkflowStep(OnlineOrderWorkflowDefinition definition) {
    final theme = Theme.of(context);
    final deliveryNote = switch (definition.deliveryType) {
      'shipping' => ' · Solo despacho',
      'pickup' => ' · Solo retiro',
      _ => '',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: OperationalStatusBadge(
              label: definition.label,
              accentColor: _getStatusColor(definition.status),
              maxWidth: 124,
              compact: true,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  definition.meaning,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Lo cambia: ${definition.owner}$deliveryNote',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  definition.nextAction,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideFact({
    required IconData icon,
    required String title,
    required String description,
    bool destructive = false,
  }) {
    final theme = Theme.of(context);
    final color = destructive
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: destructive ? theme.colorScheme.error : null,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showOrderInspector(OnlineOrder order) async {
    final theme = Theme.of(context);
    final statusColor = _getStatusColor(order.status);
    final paymentColor = _getPaymentStatusColor(order.paymentStatus);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                color: theme.colorScheme.inverseSurface,
                padding: const EdgeInsets.fromLTRB(24, 20, 18, 18),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onInverseSurface
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        Icons.shopping_bag_outlined,
                        color: theme.colorScheme.onInverseSurface,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.orderNumber,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: theme.colorScheme.onInverseSurface,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Creado el ${ChileanUtils.formatDate(order.createdAt)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onInverseSurface
                                  .withValues(alpha: 0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      color: theme.colorScheme.onInverseSurface,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _buildStatusLabel(
                            order.statusDisplayName,
                            statusColor,
                          ),
                          const SizedBox(width: 20),
                          _buildStatusLabel(
                            order.paymentStatusDisplayName,
                            paymentColor,
                          ),
                          const Spacer(),
                          Text(
                            ChileanUtils.formatCurrency(order.total),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      if (order.hasPaymentProcessingAttention) ...[
                        InkWell(
                          onTap: () {
                            Navigator.pop(dialogContext);
                            _showPaymentProcessingAction(order);
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFF8E8),
                              border: Border(
                                left: BorderSide(
                                  color: Color(0xFF9A6700),
                                  width: 3,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  size: 18,
                                  color: Color(0xFF9A6700),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    order.paymentProcessingRequiresRefundReview
                                        ? 'El cobro requiere conciliación o reembolso antes de continuar.'
                                        : 'El pago está confirmado; falta completar la venta ERP, stock o contabilidad.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      Wrap(
                        spacing: 28,
                        runSpacing: 18,
                        children: [
                          _buildInspectorField(
                            theme,
                            'Cliente',
                            order.customerName,
                            Icons.person_outline_rounded,
                          ),
                          _buildInspectorField(
                            theme,
                            'Correo',
                            order.customerEmail,
                            Icons.mail_outline_rounded,
                          ),
                          _buildInspectorField(
                            theme,
                            'Teléfono',
                            order.customerPhone?.trim().isNotEmpty == true
                                ? order.customerPhone!
                                : 'No informado',
                            Icons.phone_outlined,
                          ),
                          _buildInspectorField(
                            theme,
                            'Entrega',
                            order.deliveryType.toLowerCase() == 'pickup'
                                ? 'Retiro en tienda'
                                : 'Despacho',
                            Icons.local_shipping_outlined,
                          ),
                          _buildInspectorField(
                            theme,
                            'Método de pago',
                            order.paymentMethod ?? 'No informado',
                            Icons.account_balance_wallet_outlined,
                          ),
                          _buildInspectorField(
                            theme,
                            'Venta ERP',
                            order.salesInvoiceId == null
                                ? 'Pendiente'
                                : 'Vinculada',
                            Icons.receipt_long_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      Text(
                        'Artículos',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 9,
                              ),
                              child: const Row(
                                children: [
                                  Expanded(child: Text('Producto')),
                                  SizedBox(
                                    width: 70,
                                    child: Text(
                                      'Cant.',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  SizedBox(
                                    width: 110,
                                    child: Text(
                                      'Subtotal',
                                      textAlign: TextAlign.right,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            for (var index = 0;
                                index < order.items.length;
                                index++) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 11,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            order.items[index].productName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          if (order.items[index].productSku
                                                  ?.isNotEmpty ==
                                              true)
                                            Text(
                                              order.items[index].productSku!,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                color: theme.colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: 70,
                                      child: Text(
                                        '${order.items[index].quantity}',
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 110,
                                      child: Text(
                                        ChileanUtils.formatCurrency(
                                          order.items[index].subtotal,
                                        ),
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (index < order.items.length - 1)
                                Divider(
                                  height: 1,
                                  color: theme.colorScheme.outlineVariant,
                                ),
                            ],
                          ],
                        ),
                      ),
                      if (order.customerNotes?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 22),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7E8),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.chat_bubble_outline_rounded,
                                color: Color(0xFFF28C28),
                                size: 19,
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: Text(order.customerNotes!)),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 26),
                      OrderEvidenceSection(
                        orderId: order.id,
                        salesInvoiceId: order.salesInvoiceId,
                        onOpenOfficialDocument: (document, verifiedUri) {
                          Navigator.pop(dialogContext);
                          _openOfficialOrderDocument(
                            verifiedUri,
                            '${document.displayLabel} · ${order.orderNumber}',
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  border: Border(
                    top: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (order.salesInvoiceId != null &&
                        order.paymentStatus == 'paid')
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          _showOrderCorrection(order);
                        },
                        icon: const Icon(Icons.assignment_return_outlined),
                        label: const Text('Gestionar devolución'),
                      ),
                    if (order.salesInvoiceId != null &&
                        order.paymentStatus == 'paid')
                      const SizedBox(width: 8),
                    if (order.salesInvoiceId != null)
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          _openInvoice(order.salesInvoiceId!);
                        },
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('Abrir venta ERP'),
                      ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cerrar'),
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

  void _openOfficialOrderDocument(Uri verifiedUri, String title) {
    try {
      final workspaceId = context.read<WorkspaceManager>().openBrowserWorkspace(
            verifiedUri.toString(),
            title: title,
          );
      if (workspaceId != null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo abrir el documento: cierre una pestaña e inténtelo nuevamente.',
          ),
        ),
      );
    } catch (_) {
      context.go(
        buildBrowserWorkspaceRoute(
          url: verifiedUri.toString(),
          title: title,
        ),
      );
    }
  }

  Widget _buildInspectorField(
    ThemeData theme,
    String label,
    String value,
    IconData icon,
  ) {
    return SizedBox(
      width: 230,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusLabel(
    String label,
    Color color, {
    double maxWidth = 132,
    bool compact = false,
    VoidCallback? onTap,
    String? tooltip,
  }) {
    return OperationalStatusBadge(
      label: label,
      accentColor: color,
      maxWidth: maxWidth,
      compact: compact,
      onTap: onTap,
      tooltip: tooltip,
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return const Color(0xFF9A742F);
      case 'confirmed':
        return const Color(0xFF4B7087);
      case 'processing':
        return const Color(0xFF756A91);
      case 'ready_for_pickup':
        return const Color(0xFF5F7D68);
      case 'shipped':
        return const Color(0xFF526B82);
      case 'delivered':
        return const Color(0xFF5F7D68);
      case 'cancelled':
        return const Color(0xFF985858);
      default:
        return const Color(0xFF737B84);
    }
  }

  Color _getPaymentStatusColor(String status) {
    switch (status) {
      case 'pending':
        return const Color(0xFF9A742F);
      case 'paid':
        return const Color(0xFF5F7D68);
      case 'failed':
        return const Color(0xFF985858);
      case 'refunded':
        return const Color(0xFF756A91);
      default:
        return const Color(0xFF737B84);
    }
  }
}

class _OrdersLoadNotice extends StatelessWidget {
  const _OrdersLoadNotice({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const accent = Color(0xFF9A742F);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        border: Border(
          bottom: BorderSide(color: accent.withValues(alpha: 0.28)),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: accent),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
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

class _ShippingTransitionInput {
  const _ShippingTransitionInput({
    required this.carrier,
    required this.trackingNumber,
    required this.trackingUrl,
  });

  final String? carrier;
  final String? trackingNumber;
  final String? trackingUrl;
}
