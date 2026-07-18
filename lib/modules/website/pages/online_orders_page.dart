import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../widgets/website_admin_ui.dart';
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

          // Orders List
          Expanded(
            child: websiteService.isLoading
                ? const Center(child: BrandedLoading())
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
                        'Factura',
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
                  child: Text(
                    order.customerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
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
                  ),
                ),
                _buildTableCell(
                  width: widths['payment']!,
                  child: _buildStatusLabel(
                    order.paymentStatusDisplayName,
                    paymentColor,
                    maxWidth: widths['payment']! - 20,
                    compact: true,
                  ),
                ),
                _buildTableCell(
                  width: widths['invoice']!,
                  child: Row(
                    children: [
                      Icon(
                        order.salesInvoiceId == null
                            ? Icons.receipt_long_outlined
                            : Icons.verified_outlined,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          order.salesInvoiceId == null
                              ? 'Pendiente'
                              : 'Emitida',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
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

  Widget _buildOrderTableActions(OnlineOrder order) {
    final websiteService = context.read<WebsiteService>();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<String>(
          tooltip: 'Más acciones',
          onSelected: (value) async {
            switch (value) {
              case 'confirm':
                await _confirmOrder(order, websiteService);
                break;
              case 'confirm_payment':
                await _handlePaymentConfirmation(order, websiteService);
                break;
              case 'create_invoice':
                await _createInvoice(order, websiteService);
                break;
              case 'open_invoice':
                if (order.salesInvoiceId != null && mounted) {
                  context.go('/sales/invoices/${order.salesInvoiceId}');
                }
                break;
              case 'cancel':
                await _handleCancellation(order, websiteService);
                break;
            }
          },
          itemBuilder: (context) => [
            if (order.status == 'pending')
              const PopupMenuItem(
                value: 'confirm',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.check_circle_outline_rounded),
                  title: Text('Confirmar pedido'),
                ),
              ),
            if (order.salesInvoiceId != null &&
                order.status != 'cancelled' &&
                order.paymentStatus != 'paid' &&
                order.paymentStatus != 'refunded' &&
                const {'transfer', 'transferencia', 'bank_transfer'}
                    .contains(order.paymentMethod?.toLowerCase()))
              const PopupMenuItem(
                value: 'confirm_payment',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.account_balance_outlined),
                  title: Text('Confirmar pago'),
                ),
              ),
            if (order.salesInvoiceId == null && order.paymentStatus == 'paid')
              const PopupMenuItem(
                value: 'create_invoice',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.receipt_long_outlined),
                  title: Text('Crear factura'),
                ),
              ),
            if (order.salesInvoiceId != null)
              const PopupMenuItem(
                value: 'open_invoice',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.open_in_new_rounded),
                  title: Text('Abrir factura'),
                ),
              ),
            if (order.status != 'cancelled')
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

  Future<void> _confirmOrder(
    OnlineOrder order,
    WebsiteService websiteService,
  ) async {
    await websiteService.updateOrderStatus(order.id, 'confirmed');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${order.orderNumber} confirmado.')),
    );
  }

  Future<void> _createInvoice(
    OnlineOrder order,
    WebsiteService websiteService,
  ) async {
    try {
      final invoiceId = await websiteService.processOrder(order.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Factura creada: $invoiceId'),
          action: SnackBarAction(
            label: 'Abrir',
            onPressed: () => context.go('/sales/invoices/$invoiceId'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo crear la factura: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
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
                            'Factura',
                            order.salesInvoiceId == null
                                ? 'Pendiente'
                                : 'Emitida',
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
                    if (order.salesInvoiceId != null)
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          context.go(
                            '/sales/invoices/${order.salesInvoiceId}',
                          );
                        },
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('Abrir factura'),
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
  }) {
    final theme = Theme.of(context);
    final palette = _statusChipPalette(color, theme);
    final constrainedMaxWidth = maxWidth.isFinite ? maxWidth : 132.0;
    final minWidthTarget = compact ? 84.0 : 108.0;
    final minWidth = constrainedMaxWidth < minWidthTarget
        ? constrainedMaxWidth
        : minWidthTarget;
    final normalizedLabel =
        label.trim().isEmpty ? 'SIN ESTADO' : label.trim().toUpperCase();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      width: constrainedMaxWidth,
      constraints: BoxConstraints(
        minWidth: minWidth,
        maxWidth: constrainedMaxWidth,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: palette.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.18 : 0.06,
            ),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 5 : 6,
            height: compact ? 5 : 6,
            decoration: BoxDecoration(
              color: palette.dot,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: palette.dot.withValues(alpha: 0.22),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              normalizedLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 10.5 : 11.5,
                fontWeight: FontWeight.w700,
                height: 1.05,
                letterSpacing: 0,
                color: palette.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }

  ({Color background, Color border, Color foreground, Color dot})
      _statusChipPalette(Color accent, ThemeData theme) {
    final hsl = HSLColor.fromColor(accent);
    final isNeutral = hsl.saturation < 0.12;
    final isDark = theme.brightness == Brightness.dark;

    if (isNeutral) {
      return (
        background: isDark
            ? theme.colorScheme.surfaceContainerHigh
            : const Color(0xFFF8FAFC),
        border: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        foreground: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
        dot: const Color(0xFF94A3B8),
      );
    }

    final surface =
        isDark ? theme.colorScheme.surfaceContainerHigh : Colors.white;
    final borderBase =
        isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB);
    final foreground = hsl
        .withSaturation((hsl.saturation * 0.82).clamp(0.42, 0.78).toDouble())
        .withLightness(
          (hsl.lightness * (isDark ? 1.12 : 0.68))
              .clamp(isDark ? 0.62 : 0.34, isDark ? 0.78 : 0.46)
              .toDouble(),
        )
        .toColor();
    return (
      background: Color.alphaBlend(
        accent.withValues(alpha: isDark ? 0.16 : 0.07),
        surface,
      ),
      border: Color.alphaBlend(
        accent.withValues(alpha: isDark ? 0.38 : 0.2),
        borderBase,
      ),
      foreground: foreground,
      dot: accent,
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

class _ManualPaymentConfirmationInput {
  const _ManualPaymentConfirmationInput({
    required this.reference,
    required this.date,
  });

  final String reference;
  final DateTime date;
}
