import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../messaging/providers/chat_provider.dart';
import '../../../shared/services/deferred_load_failure.dart';
import '../../../shared/services/right_toolbar_service.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/services/notification_service.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/interactive_table_field.dart';
import '../../../shared/widgets/modern_context_menu.dart';
import '../../../shared/widgets/operational_status_badge.dart';
import '../../../shared/services/workspace_manager.dart';
import '../widgets/website_admin_ui.dart';
import '../widgets/online_order_sheet.dart';
import '../widgets/online_order_shipping_label_dialog.dart';
import '../widgets/online_order_shipment_section.dart';
import '../widgets/shipment_receipt_dialog.dart';
import '../widgets/order_evidence_section.dart';
import '../widgets/online_order_correction_dialog.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/utils/shop_time.dart';
import '../../../shared/themes/vinabike_theme_roles.dart';
import '../services/website_service.dart';
import '../models/website_models.dart';
import '../models/online_order_workflow_policy.dart';
// Deferred: the phone's messages screen carries the whole chat (~0.5 MB of
// JavaScript), and this page also runs inside the storefront's editor, whose
// bundle outgrew its budget with it (2026-10-14). It loads the first time
// «WhatsApp» opens a conversation on a phone; in the ERP it is already loaded.
import '../../../shared/widgets/compact_messages_host.dart'
    deferred as messages_host;

/// Page for managing online orders from the website
class OnlineOrdersPage extends StatefulWidget {
  const OnlineOrdersPage({
    super.key,
    this.embedded = false,
    this.initialOrderId,
    this.initialOpenRequestId,
  });

  final bool embedded;
  final String? initialOrderId;
  final String? initialOpenRequestId;

  @override
  State<OnlineOrdersPage> createState() => _OnlineOrdersPageState();
}

class _OnlineOrdersPageState extends State<OnlineOrdersPage> {
  static const double _tableRowHeight = 62;

  static const Map<String, double> _defaultColumnWidths = {
    'order': 150,
    'products': 300,
    'customer': 200,
    'progress': 190,
    'invoice': 110,
    'total': 95,
    'actions': 50,
  };

  final Map<String, double> _columnWidths =
      Map<String, double>.of(_defaultColumnWidths);

  /// The list on screen; null is «Todos». It opens on what the shop has to
  /// do now.
  OnlineOrderList _list = OnlineOrderList.active;
  bool _showTests = false;
  bool _phoneSearchOpen = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';
  String _sortKey = 'created';
  bool _sortAscending = false;
  String? _lastMarkedAlertOrderId;
  String? _lastOpenedInitialOrderRequestKey;

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
    _markNotificationReadForOrder(widget.initialOrderId);
    // Lazy load orders when this page opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<WebsiteService>().initializeOrders();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant OnlineOrdersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialOrderId == widget.initialOrderId &&
        oldWidget.initialOpenRequestId == widget.initialOpenRequestId) {
      return;
    }
    _markNotificationReadForOrder(widget.initialOrderId);
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

  void _openInitialOrderWhenAvailable(List<OnlineOrder> orders) {
    final orderId = widget.initialOrderId?.trim();
    final requestKey = _currentInitialOrderRequestKey();
    if (orderId == null ||
        orderId.isEmpty ||
        requestKey == _lastOpenedInitialOrderRequestKey) {
      return;
    }

    OnlineOrder? matchingOrder;
    for (final order in orders) {
      if (order.id == orderId) {
        matchingOrder = order;
        break;
      }
    }
    if (matchingOrder == null) return;

    _lastOpenedInitialOrderRequestKey = requestKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _currentInitialOrderRequestKey() != requestKey) return;
      _showOrderInspector(matchingOrder!);
    });
  }

  String _currentInitialOrderRequestKey() {
    return '${widget.initialOrderId?.trim()}:'
        '${widget.initialOpenRequestId?.trim() ?? ''}';
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
    _openInitialOrderWhenAvailable(websiteService.orders);
    final phone = MediaQuery.sizeOf(context).width < 600;

    // Tests stay out of the counters and the lists unless asked for: 77 of
    // the first 78 orders were the shop trying its own store (2026-10-13).
    final testCount =
        websiteService.orders.where((order) => order.isTest).length;
    final visible = websiteService.orders
        .where((order) => _showTests || !order.isTest)
        .toList();
    final counts = {for (final list in OnlineOrderList.values) list: 0};
    for (final order in visible) {
      final queue = _queueOf(order);
      for (final list in OnlineOrderList.values) {
        if (list.includes(queue)) counts.update(list, (count) => count + 1);
      }
    }

    final query = _searchTerm.trim().toLowerCase();
    final orders = visible.where((order) {
      // A search looks through every list: the order asked about may already
      // be closed.
      if (query.isEmpty) return _list.includes(_queueOf(order));
      final searchIndex = [
        order.orderNumber,
        order.customerName,
        order.customerEmail,
        order.customerPhone ?? '',
        order.paymentReference ?? '',
        ...order.items.map((item) => item.productName),
        ...order.items.map((item) => item.productSku ?? ''),
      ].join(' ').toLowerCase();
      return searchIndex.contains(query);
    }).toList()
      ..sort(_compareOrders);

    final searchField = TextField(
      controller: _searchController,
      autofocus: phone,
      onChanged: (value) => setState(() => _searchTerm = value),
      decoration: InputDecoration(
        hintText: 'Buscar pedido, cliente o producto…',
        prefixIcon: const Icon(Icons.search_rounded, size: 19),
        suffixIcon: _searchTerm.isEmpty
            ? null
            : IconButton(
                onPressed: () => setState(() {
                  _searchController.clear();
                  _searchTerm = '';
                }),
                tooltip: 'Borrar búsqueda',
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
        isDense: true,
      ),
    );

    return WebsiteAdminShell(
      embedded: widget.embedded,
      title: 'Pedidos online',
      description: 'Revisa el avance operativo y el estado real de cada pago.',
      actions: [
        if (phone)
          IconButton.outlined(
            icon: Icon(
              _phoneSearchOpen
                  ? Icons.search_off_rounded
                  : Icons.search_rounded,
              size: 19,
            ),
            onPressed: () => setState(() {
              _phoneSearchOpen = !_phoneSearchOpen;
              if (!_phoneSearchOpen) {
                _searchController.clear();
                _searchTerm = '';
              }
            }),
            tooltip: _phoneSearchOpen ? 'Cerrar búsqueda' : 'Buscar pedido',
          ),
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
          // One compact strip: the lists by what the shop has to do, with
          // their counts, and the search. The orders are what this page is
          // for (dueño, 2026-10-13: «lo más importante siempre es la lista»).
          Container(
            width: double.infinity,
            padding:
                EdgeInsets.fromLTRB(phone ? 12 : 20, 8, phone ? 12 : 20, 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: phone
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_phoneSearchOpen) ...[
                        searchField,
                        const SizedBox(height: 8),
                      ],
                      _buildQueueTabs(counts),
                    ],
                  )
                : Row(
                    children: [
                      // The tabs get two thirds of what the tests switch
                      // leaves and the search the rest, up to 260 px: on a
                      // narrow window a fixed search hid all tabs but one.
                      // Their counts are the page's totals, so no separate
                      // «N pedidos» column competes for room.
                      Expanded(
                        flex: 2,
                        child: _buildQueueTabs(counts),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 260),
                            child: searchField,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (testCount > 0) ...[
                        FilterChip(
                          label: Text('Pruebas ($testCount)'),
                          selected: _showTests,
                          onSelected: (value) =>
                              setState(() => _showTests = value),
                          tooltip: _showTests
                              ? 'Ocultar los pedidos de prueba'
                              : 'Mostrar los pedidos de prueba',
                        ),
                        const SizedBox(width: 4),
                      ],
                      IconButton(
                        onPressed: _resetAllColumnWidths,
                        tooltip: 'Restablecer ancho de columnas',
                        icon: const Icon(Icons.view_column_outlined, size: 19),
                      ),
                    ],
                  ),
          ),

          if (websiteService.ordersEnrichmentWarning != null)
            _OrdersLoadNotice(
              message: websiteService.ordersEnrichmentWarning!,
              onRetry: websiteService.loadOrders,
            ),

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
                        ? Column(
                            children: [
                              Expanded(
                                child: WebsiteAdminEmptyState(
                                  icon: Icons.shopping_bag_outlined,
                                  title: query.isNotEmpty
                                      ? 'Ningún pedido coincide'
                                      : _emptyTitle(_list),
                                  description: query.isNotEmpty
                                      ? 'La búsqueda revisa todas las listas: número, cliente, correo, teléfono y productos.'
                                      : 'Cuando entre una compra desde el sitio aparecerá en la lista que le toque, con su siguiente paso.',
                                ),
                              ),
                              if (phone && testCount > 0)
                                _buildTestsToggle(testCount),
                            ],
                          )
                        : _buildOrdersTable(orders, testCount: testCount),
          ),
        ],
      ),
    );
  }

  OnlineOrderQueue _queueOf(OnlineOrder order) =>
      OnlineOrderWorkflowPolicy.queueFor(
        status: order.status,
        paymentStatus: order.operationalPaymentStatus,
        paymentNeedsAttention: order.hasPaymentProcessingAttention,
      );

  String _emptyTitle(OnlineOrderList list) => switch (list) {
        OnlineOrderList.active => 'Ningún pedido activo',
        OnlineOrderList.attend => 'Nada por atender',
        OnlineOrderList.awaitingPayment => 'Ningún pedido esperando pago',
        OnlineOrderList.onTheWay => 'Nada en camino',
        OnlineOrderList.closed => 'Ningún pedido cerrado',
        OnlineOrderList.all => 'Todavía no hay pedidos',
      };

  Widget _buildQueueTabs(Map<OnlineOrderList, int> counts) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final list in OnlineOrderList.values) ...[
            _QueueTab(
              label: list.label,
              count: counts[list] ?? 0,
              selected: _list == list && _searchTerm.trim().isEmpty,
              onTap: () => setState(() => _list = list),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _buildTestsToggle(int testCount) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => setState(() => _showTests = !_showTests),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Icon(
              Icons.science_outlined,
              size: 19,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                testCount == 1
                    ? (_showTests
                        ? '1 pedido de prueba a la vista'
                        : '1 pedido de prueba, oculto')
                    : (_showTests
                        ? '$testCount pedidos de prueba a la vista'
                        : '$testCount pedidos de prueba, ocultos'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              _showTests ? 'Ocultar' : 'Ver',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _compareOrders(OnlineOrder a, OnlineOrder b) {
    String firstProduct(OnlineOrder order) =>
        order.items.isEmpty ? '' : order.items.first.productName;
    int progress(OnlineOrder order) {
      final steps = OnlineOrderWorkflowPolicy.progressSteps(
        status: order.status,
        deliveryType: order.deliveryType,
        paymentStatus: order.operationalPaymentStatus,
      );
      return steps
          .where((step) => step.state == OnlineOrderProgressState.done)
          .length;
    }

    final int comparison = switch (_sortKey) {
      'products' => firstProduct(a).compareTo(firstProduct(b)),
      'customer' => a.customerName.compareTo(b.customerName),
      'progress' => _queueOf(a).index != _queueOf(b).index
          ? _queueOf(a).index.compareTo(_queueOf(b).index)
          : progress(a).compareTo(progress(b)),
      'total' => a.total.compareTo(b.total),
      'invoice' => (a.salesInvoiceId != null ? 1 : 0)
          .compareTo(b.salesInvoiceId != null ? 1 : 0),
      _ => a.createdAt.compareTo(b.createdAt),
    };
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
      'order' => 120,
      'products' => 160,
      'customer' => 120,
      'progress' => 140,
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
          (current + delta).clamp(_minimumColumnWidth(key), 520).toDouble();
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

  Widget _buildOrdersTable(List<OnlineOrder> orders, {required int testCount}) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // A phone gets one scannable row per order, never the desktop table
        // in horizontal scroll (GUI_MOBILE_DESIGN_PRINCIPLES, dueño
        // 2026-10-13: «la UI móvil está tratada como la mierda»).
        if (constraints.maxWidth < 600) {
          return _buildOrdersPhoneList(orders, testCount: testCount);
        }
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
                        sortKey: 'created',
                      ),
                      _buildTableHeader(
                        'Productos',
                        widthOf('products'),
                        columnKey: 'products',
                        sortKey: 'products',
                      ),
                      _buildTableHeader(
                        'Cliente',
                        widthOf('customer'),
                        columnKey: 'customer',
                        sortKey: 'customer',
                      ),
                      _buildTableHeader(
                        'Avance',
                        widthOf('progress'),
                        columnKey: 'progress',
                        sortKey: 'progress',
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

  Widget _buildOrdersPhoneList(
    List<OnlineOrder> orders, {
    required int testCount,
  }) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: ListView.builder(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom + 12,
        ),
        itemCount: orders.length + (testCount > 0 ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == orders.length) return _buildTestsToggle(testCount);
          return DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: _buildOrderPhoneRow(orders[index]),
          );
        },
      ),
    );
  }

  /// One order on a phone, read the way the order sheet reads (dueño,
  /// 2026-10-13, chose «B»): who and how much first, then what was bought,
  /// then where it stands — four small steps, the step in words, how it is
  /// delivered, the number and the day. A tap opens the sheet, where every
  /// action lives.
  Widget _buildOrderPhoneRow(OnlineOrder order) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final pickup = order.deliveryType.toLowerCase() == 'pickup';
    final created = DateFormat("d MMM", 'es')
        .format(shopTime(order.createdAt))
        .replaceAll('.', '');
    final attention = order.hasPaymentProcessingAttention;
    final roles = VinabikeThemeRoles.of(context);

    return InkWell(
      onTap: () => _showOrderInspector(order),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Opacity(
          opacity: order.isTest ? 0.62 : 1,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _OrderThumb(order: order, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // The name takes all the room the total leaves; a
                        // Flexible beside a Spacer got only half of it.
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  order.customerName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (order.isTest) ...[
                                const SizedBox(width: 6),
                                const _TestTag(),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          ChileanUtils.formatCurrency(order.total),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _productsSummary(order),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        _MiniProgress(order: order, width: 52),
                        const SizedBox(width: 8),
                        Icon(
                          pickup
                              ? Icons.storefront_outlined
                              : Icons.local_shipping_outlined,
                          size: 15,
                          color: muted,
                          semanticLabel: pickup ? 'Retiro' : 'Despacho',
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: _stepLabel(order),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: attention
                                        ? roles.warning.accent
                                        : theme.colorScheme.onSurface,
                                  ),
                                ),
                                TextSpan(
                                  text: ' · ${order.orderNumber} · $created',
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                            ),
                          ),
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

  String _productsSummary(OnlineOrder order) {
    if (order.items.isEmpty) return 'Sin productos';
    final first = order.items.first.productName.trim();
    final more = order.items.length - 1;
    return more == 0 ? first : '$first y $more más';
  }

  /// Where the order stands, in the words of the shop.
  String _stepLabel(OnlineOrder order) {
    if (order.isCancelled) return 'Cancelado';
    if (order.hasPaymentProcessingAttention) return 'Falta la venta ERP';
    return switch (order.status) {
      'delivered' => 'Entregado',
      'shipped' => 'Despachado',
      'ready_for_pickup' => 'Listo para retiro',
      _ => switch (order.operationalPaymentStatus) {
          'paid' =>
            order.status == 'processing' ? 'En preparación' : 'Preparar',
          'failed' => 'Pago rechazado',
          'refunded' => 'Reembolsado',
          _ => OnlineOrderWorkflowPolicy.isManualTransfer(order.paymentMethod)
              ? 'Esperando transferencia'
              : 'Esperando pago',
        },
    };
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
    final roles = VinabikeThemeRoles.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
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
    final attention = order.hasPaymentProcessingAttention;
    final hasNotes = [order.customerNotes, order.internalNotes, order.notes]
        .any((note) => note != null && note.trim().isNotEmpty);
    final pickup = order.deliveryType.toLowerCase() == 'pickup';
    final city = order.shippingCity?.trim() ?? '';
    // The step cell carries the step's command: a payment to sort out, a
    // transfer to confirm, or the next status.
    final VoidCallback? progressAction = attention
        ? () => _showPaymentProcessingAction(order)
        : canConfirmManualPayment
            ? () => _handlePaymentConfirmation(
                  order,
                  context.read<WebsiteService>(),
                )
            : legalNextStatuses.isEmpty
                ? null
                : () => _showOrderStatusMenu(order);

    return Material(
      color: theme.colorScheme.surface,
      child: InkWell(
        onTap: () => _showOrderInspector(order),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Opacity(
            opacity: order.isTest ? 0.62 : 1,
            child: SizedBox(
              height: _tableRowHeight,
              child: Row(
                children: [
                  _buildTableCell(
                    width: widths['order']!,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                order.orderNumber,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (hasNotes) ...[
                              const SizedBox(width: 5),
                              Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 13,
                                color: muted,
                                semanticLabel: 'Tiene notas',
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        // The tag sits by the date: beside the number it
                        // cut «WEB-26-000…».
                        Row(
                          children: [
                            Text(
                              ChileanUtils.formatDate(
                                shopTime(order.createdAt),
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: muted,
                              ),
                            ),
                            if (order.isTest) ...[
                              const SizedBox(width: 6),
                              const _TestTag(),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  _buildTableCell(
                    width: widths['products']!,
                    child: Row(
                      children: [
                        _OrderThumb(order: order, size: 38),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _productsSummary(order),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildTableCell(
                    width: widths['customer']!,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InteractiveTableField(
                          onTap: order.customerId == null
                              ? null
                              : () => _openCustomer(order.customerId!),
                          maxWidth: widths['customer']! - 20,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
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
                        Padding(
                          padding: const EdgeInsets.only(left: 6, top: 1),
                          child: Text(
                            pickup
                                ? 'Retiro en tienda'
                                : city.isEmpty
                                    ? 'Despacho'
                                    : 'Despacho · $city',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildTableCell(
                    width: widths['progress']!,
                    child: InteractiveTableField(
                      onTap: progressAction,
                      accentColor: attention ? roles.warning.accent : null,
                      maxWidth: widths['progress']! - 20,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _MiniProgress(order: order, width: 112),
                          const SizedBox(height: 5),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (attention) ...[
                                Icon(
                                  Icons.error_outline_rounded,
                                  size: 14,
                                  color: roles.warning.accent,
                                ),
                                const SizedBox(width: 4),
                              ],
                              Flexible(
                                child: Text(
                                  _stepLabel(order),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: attention
                                        ? roles.warning.accent
                                        : order.isCancelled
                                            ? muted
                                            : theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
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
                        fontFeatures: const [FontFeature.tabularFigures()],
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

    if (newStatus == 'shipped') {
      await _registerShipment(order, websiteService);
      return;
    }

    try {
      final invoiceId = await websiteService.updateOrderStatus(
        order.id,
        newStatus,
        expectedVersion: order.version,
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

  /// The shipment is registered from the carrier's receipt: the dialog reads
  /// it with AI, checks it against the order and, in one step, records it,
  /// moves the order to «Despachado», emails the customer the code and
  /// registers the carrier's cost as an expense.
  Future<void> _registerShipment(
    OnlineOrder order,
    WebsiteService websiteService,
  ) async {
    final shipment = await showShipmentReceiptDialog(
      context,
      order: order,
      customerRut: websiteService.customerRutForOrder(order),
    );
    if (shipment == null || !mounted) return;
    await websiteService.loadOrders();
    if (!mounted) return;
    final notified = order.customerEmail.trim().isNotEmpty;
    final expense = shipment.expenseNumber;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${order.orderNumber} despachado por ${shipment.carrier}'
          '${expense != null ? ', gasto $expense registrado' : ''}'
          '${notified ? '. Le avisamos al cliente con el seguimiento.' : '.'}',
        ),
      ),
    );
  }

  Widget _buildOrderTableActions(
    OnlineOrder order, {
    Color? iconColor,
    VoidCallback? onLeave,
  }) {
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
          iconColor: iconColor,
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
                  onLeave?.call();
                  await _openInvoice(order.salesInvoiceId!);
                }
                break;
              case 'correction':
                await _showOrderCorrection(order);
                break;
              case 'shipping_label':
                await showOnlineOrderShippingLabelDialog(context, order);
                break;
              case 'test_flag':
                await _toggleTestFlag(order);
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
            if (order.deliveryType.toLowerCase() != 'pickup' &&
                !order.isCancelled)
              const PopupMenuItem(
                value: 'shipping_label',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.print_outlined),
                  title: Text('Etiqueta de despacho'),
                ),
              ),
            PopupMenuItem(
              value: 'test_flag',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.science_outlined),
                title: Text(
                  order.isTest ? 'No es una prueba' : 'Marcar como prueba',
                ),
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

  /// Marks or unmarks an order placed to test the store; the snack bar
  /// offers the way back.
  Future<void> _toggleTestFlag(OnlineOrder order) async {
    final websiteService = context.read<WebsiteService>();
    final isTest = !order.isTest;
    try {
      await websiteService.setOrderTestFlag(order, isTest);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isTest
                ? '${order.orderNumber} quedó como pedido de prueba.'
                : '${order.orderNumber} vuelve a las listas.',
          ),
          action: SnackBarAction(
            label: 'Deshacer',
            onPressed: () {
              final current = websiteService.orders.firstWhere(
                (candidate) => candidate.id == order.id,
                orElse: () => order,
              );
              websiteService.setOrderTestFlag(current, !isTest);
            },
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo cambiar la marca de prueba: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
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
    final screen = MediaQuery.sizeOf(context);
    // A phone opens the order full screen: a floating window there cut the
    // total, squeezed the articles and pushed the buttons off (2026-10-13).
    final phone = screen.width < 600;
    final systemInsets =
        phone ? MediaQuery.paddingOf(context) : EdgeInsets.zero;
    final websiteService = context.read<WebsiteService>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        // The order as the service holds it now: a step taken from the bar
        // reloads the orders and the band moves without reopening. The
        // Scaffold shows the page's snack bars over the order.
        final content = Scaffold(
          backgroundColor: Colors.transparent,
          body: ListenableBuilder(
            listenable: websiteService,
            builder: (context, _) => _buildOrderSheet(
              websiteService.orders.firstWhere(
                (candidate) => candidate.id == order.id,
                orElse: () => order,
              ),
              dialogContext,
              phone: phone,
              insets: systemInsets,
            ),
          ),
        );
        if (phone) return Dialog.fullscreen(child: content);
        return Dialog(
          clipBehavior: Clip.antiAlias,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            // A desktop has room for the order: wider and nearly as tall as
            // the screen, one column (dueño, 2026-10-13: «más alto y un poco
            // más ancho», no dos columnas).
            constraints: BoxConstraints(
              maxWidth: 1040,
              maxHeight: (screen.height - 48).clamp(480.0, 1400.0),
            ),
            child: content,
          ),
        );
      },
    );
  }

  Widget _buildOrderSheet(
    OnlineOrder order,
    BuildContext dialogContext, {
    required bool phone,
    required EdgeInsets insets,
  }) {
    final shell = VinabikeThemeRoles.of(context).shell;
    final phoneNumber = order.customerPhone?.trim() ?? '';
    final reachable = phoneNumber.replaceAll(RegExp(r'\D'), '').length >= 8;
    final shipping = order.deliveryType.toLowerCase() != 'pickup';
    final hasAddress = order.shippingAddressLine1?.trim().isNotEmpty == true ||
        order.customerAddress?.trim().isNotEmpty == true;
    void leave() => Navigator.pop(dialogContext);

    return OnlineOrderSheet(
      order: order,
      phone: phone,
      topInset: insets.top,
      bottomInset: insets.bottom,
      onClose: leave,
      moreActions: _buildOrderTableActions(
        order,
        iconColor: shell.foreground,
        onLeave: leave,
      ),
      primaryAction: _nextOrderAction(order),
      waitingLabel: _orderWaitingLabel(order),
      onWhatsApp: reachable
          ? () {
              leave();
              _openCustomerWhatsApp(order);
            }
          : null,
      onCall: reachable ? () => _callCustomer(phoneNumber) : null,
      onOpenMap: shipping && hasAddress ? () => _openOrderMap(order) : null,
      onShippingLabel: shipping && !order.isCancelled
          ? () => showOnlineOrderShippingLabelDialog(context, order)
          : null,
      shipment: shipping &&
              (order.status == 'shipped' ||
                  order.status == 'delivered' ||
                  order.trackingNumber?.trim().isNotEmpty == true ||
                  order.shippingCarrier?.trim().isNotEmpty == true)
          ? OnlineOrderShipmentSection(order: order)
          : null,
      onOpenSale: order.salesInvoiceId == null
          ? null
          : () {
              leave();
              _openInvoice(order.salesInvoiceId!);
            },
      evidence: OrderEvidenceSection(
        orderId: order.id,
        orderVersion: order.version,
        salesInvoiceId: order.salesInvoiceId,
        onOpenOfficialDocument: (document, verifiedUri) {
          leave();
          _openOfficialOrderDocument(
            verifiedUri,
            '${document.displayLabel} · ${order.orderNumber}',
          );
        },
      ),
    );
  }

  /// The one step the order asks of the shop now, for the bar's main button:
  /// a payment to sort out first, then the next legal status. A Mercado Pago
  /// order still unpaid has none: the customer has to pay.
  OnlineOrderSheetAction? _nextOrderAction(OnlineOrder order) {
    final websiteService = context.read<WebsiteService>();
    if (order.isCancelled) return null;
    if (order.hasPaymentProcessingAttention) {
      return OnlineOrderSheetAction(
        label: order.paymentProcessingRequiresRefundReview
            ? 'Conciliar cobro'
            : 'Revisar pago',
        icon: Icons.error_outline_rounded,
        onPressed: () => _showPaymentProcessingAction(order),
      );
    }
    if (OnlineOrderWorkflowPolicy.canConfirmManualPayment(
      orderStatus: order.status,
      paymentStatus: order.paymentStatus,
      paymentMethod: order.paymentMethod,
      hasInvoice: order.salesInvoiceId != null,
    )) {
      return OnlineOrderSheetAction(
        label: 'Confirmar pago',
        icon: Icons.account_balance_outlined,
        onPressed: () => _handlePaymentConfirmation(order, websiteService),
      );
    }
    if (order.salesInvoiceId == null && order.paymentStatus == 'paid') {
      return OnlineOrderSheetAction(
        label: 'Crear venta ERP',
        icon: Icons.receipt_long_outlined,
        onPressed: () => _createInvoice(order, websiteService),
      );
    }
    if (_waitsForProviderPayment(order)) return null;
    final next = OnlineOrderWorkflowPolicy.legalNextStatuses(
      currentStatus: order.status,
      deliveryType: order.deliveryType,
      paymentStatus: order.paymentStatus,
    ).where((status) => status != 'cancelled').firstOrNull;
    if (next == null) return null;
    return OnlineOrderSheetAction(
      label: OnlineOrderWorkflowPolicy.actionLabel(next),
      icon: _statusActionIcon(next),
      onPressed: () => _applyOrderStatusTransition(order, next),
    );
  }

  bool _waitsForProviderPayment(OnlineOrder order) =>
      OnlineOrderWorkflowPolicy.isWebhookOwnedPayment(order.paymentMethod) &&
      order.operationalPaymentStatus == 'pending';

  String? _orderWaitingLabel(OnlineOrder order) {
    if (order.isCancelled) return 'Pedido cancelado';
    if (order.status == 'delivered') {
      return order.deliveredAt == null
          ? 'Pedido entregado'
          : 'Entregado el ${ChileanUtils.formatDate(shopTime(order.deliveredAt!))}';
    }
    if (_waitsForProviderPayment(order)) {
      return 'Esperando que el cliente pague en Mercado Pago';
    }
    return null;
  }

  /// The customer's WhatsApp inside the ERP, where the shop already talks to
  /// customers: the right rail on a desktop, its own screen on a phone.
  Future<void> _openCustomerWhatsApp(OnlineOrder order) async {
    final chat = context.read<ChatProvider>();
    final toolbar = context.read<RightToolbarService>();
    try {
      final conversationId = await chat.openWhatsAppConversationForHandoff(
        phoneNumber: order.customerPhone!.trim(),
        contactName: order.customerName,
        customerId: order.customerId,
      );
      if (!mounted) return;
      toolbar.openConversation(
        tool: ToolbarTool.messages,
        conversationId: conversationId,
      );
      await messages_host.loadLibrary();
      if (!mounted) return;
      messages_host.CompactMessagesHost.ensureOpen(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is StateError
                ? error.message.toString()
                : DeferredLoadFailure.of(error) != null
                    ? 'El chat no se pudo cargar: recarga la página.'
                    : 'No se pudo abrir el chat de WhatsApp: $error',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _callCustomer(String phoneNumber) async {
    final digits = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    final opened = await launchUrl(Uri(scheme: 'tel', path: digits));
    if (opened || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Este equipo no puede llamar. Número: $phoneNumber')),
    );
  }

  Future<void> _openOrderMap(OnlineOrder order) async {
    final opened = await launchUrl(
      Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': order.shippingAddressDisplay,
      }),
      mode: LaunchMode.externalApplication,
    );
    if (opened || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo abrir el mapa.')),
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

/// One list of the orders page, with how many orders it holds.
class _QueueTab extends StatelessWidget {
  const _QueueTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // The inverse roles: a dark pill on the light page and a light one on
    // the dark page; a navy pill vanished on the dark surface.
    final foreground =
        selected ? scheme.onInverseSurface : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $count',
      excludeSemantics: true,
      child: Material(
        color: selected ? scheme.inverseSurface : scheme.surface,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? scheme.inverseSurface : scheme.outlineVariant,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    '$count',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: selected
                          ? scheme.inversePrimary
                          : count == 0
                              ? scheme.onSurfaceVariant
                              : scheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// «Prueba» next to an order placed to test the store.
class _TestTag extends StatelessWidget {
  const _TestTag();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final neutral = VinabikeThemeRoles.of(context).neutral;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: neutral.container,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        child: Text(
          'PRUEBA',
          style: theme.textTheme.labelSmall?.copyWith(
            color: neutral.onContainer,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

/// The first product's photo, or a box when it has none.
class _OrderThumb extends StatelessWidget {
  const _OrderThumb({required this.order, required this.size});

  final OnlineOrder order;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = order.items.isEmpty ? null : order.items.first.productImageUrl;
    final placeholder = Icon(
      Icons.inventory_2_outlined,
      size: size * 0.46,
      color: VinabikeThemeRoles.of(context).faintForeground,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.24),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        color: theme.colorScheme.surfaceContainerHigh,
        child: url == null
            ? placeholder
            : ImageService.buildCachedImage(
                imageUrl: url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholder: placeholder,
                errorWidget: placeholder,
              ),
      ),
    );
  }
}

/// The order sheet's four steps, small enough for a row.
class _MiniProgress extends StatelessWidget {
  const _MiniProgress({required this.order, required this.width});

  final OnlineOrder order;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final steps = OnlineOrderWorkflowPolicy.progressSteps(
      status: order.status,
      deliveryType: order.deliveryType,
      paymentStatus: order.operationalPaymentStatus,
    );
    if (steps.isEmpty) {
      // A cancelled order left the path: one quiet line instead of steps.
      return Container(
        width: width,
        height: 4,
        decoration: BoxDecoration(
          color: theme.colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      );
    }
    return SizedBox(
      width: width,
      child: Row(
        children: [
          for (var index = 0; index < steps.length; index++) ...[
            if (index > 0) const SizedBox(width: 3),
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: switch (steps[index].state) {
                    OnlineOrderProgressState.done => roles.success.accent,
                    OnlineOrderProgressState.current =>
                      theme.colorScheme.primary,
                    OnlineOrderProgressState.upcoming =>
                      theme.colorScheme.outlineVariant,
                  },
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
