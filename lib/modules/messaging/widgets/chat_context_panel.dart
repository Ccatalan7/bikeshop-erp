import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../bikeshop/services/bikeshop_service.dart';
import '../../bikeshop/models/bikeshop_models.dart';
import '../../sales/services/sales_service.dart';
import '../../sales/models/sales_models.dart';
import '../../website/models/website_models.dart';
import '../../website/services/website_service.dart';

class ChatContextPanel extends StatefulWidget {
  final String contextType;
  final String contextId;

  const ChatContextPanel({
    super.key,
    required this.contextType,
    required this.contextId,
  });

  @override
  State<ChatContextPanel> createState() => _ChatContextPanelState();
}

class _ChatContextPanelState extends State<ChatContextPanel>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  dynamic _data;
  Invoice? _linkedInvoice; // For Job context
  Bike? _bike;
  String? _error;
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant ChatContextPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contextId != widget.contextId ||
        oldWidget.contextType != widget.contextType) {
      _loadData();
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _data = null;
      _bike = null;
      _linkedInvoice = null;
      _tabController?.dispose();
      _tabController = null;
    });

    try {
      if (widget.contextType == 'job') {
        final bikeshopService = context.read<BikeshopService>();
        final job = await bikeshopService.getJobById(widget.contextId);
        if (job != null) {
          _data = job;

          // Fetch Bike
          try {
            if (job.bikeId != null) {
              _bike = await bikeshopService.getBikeById(job.bikeId!);
            }
          } catch (_) {}

          // Fetch Linked Invoice
          if (job.invoiceId != null) {
            _linkedInvoice =
                await context.read<SalesService>().fetchInvoice(job.invoiceId!);
          }

          // Initialize Tabs if we have both
          _tabController = TabController(length: 2, vsync: this);
        } else {
          _error = 'Trabajo no encontrado';
        }
      } else if (widget.contextType == 'invoice') {
        final invoice =
            await context.read<SalesService>().fetchInvoice(widget.contextId);
        if (invoice != null) {
          _data = invoice;
        } else {
          _error = 'Factura no encontrada';
        }
      } else if (widget.contextType == 'order') {
        final order =
            await context.read<WebsiteService>().getOrderById(widget.contextId);
        if (order != null) {
          _data = order;
        } else {
          _error = 'Pedido web no encontrado';
        }
      } else {
        _error = 'Tipo de contexto desconocido';
      }
    } catch (e) {
      _error = 'Error cargando datos';
      debugPrint('Error loading context panel: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
          child: Text(_error!, style: const TextStyle(color: Colors.red)));
    }

    if (_data == null) return const Center(child: Text('Sin datos'));

    if (widget.contextType == 'job') {
      return _buildJobTabs(_data as MechanicJob);
    } else if (widget.contextType == 'invoice') {
      return Container(
          width: 300,
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: Colors.grey[300]!)),
            color: Colors.grey[50],
          ),
          padding: const EdgeInsets.all(16),
          child: _buildInvoiceContent(_data as Invoice));
    } else if (widget.contextType == 'order') {
      return Container(
        width: 320,
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: Colors.grey[300]!)),
          color: Colors.grey[50],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _buildOrderContent(_data as OnlineOrder),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildJobTabs(MechanicJob job) {
    // If we have an invoice, show tabs.
    // Even if no invoice, maybe show 'Presupuesto' tab as 'No invoice'?
    // User requested "Tabs".

    return Container(
      width: 300,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: Colors.grey[300]!)),
        color: Colors.grey[50],
      ),
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: Theme.of(context).primaryColor,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Theme.of(context).primaryColor,
            tabs: const [
              Tab(text: 'Resumen'),
              Tab(text: 'Presupuesto'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _buildJobContent(job),
                ),
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _linkedInvoice != null
                      ? _buildInvoiceContent(_linkedInvoice!)
                      : const Center(child: Text('Sin presupuesto asociado')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJobContent(MechanicJob job) {
    final theme = Theme.of(context);
    final currencyFormat =
        NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.build, size: 20, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'JOB #${job.jobNumber ?? "N/A"}',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildInfoRow('Estado', job.status.displayName,
            color: _getStatusColor(job.status)),
        const Divider(height: 24),
        Text('Solicitud',
            style:
                theme.textTheme.labelSmall?.copyWith(color: Colors.grey[600])),
        const SizedBox(height: 4),
        Text(job.clientRequest ?? job.diagnosis ?? 'Sin descripción',
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        const Divider(height: 24),
        Text('Bicicleta',
            style:
                theme.textTheme.labelSmall?.copyWith(color: Colors.grey[600])),
        const SizedBox(height: 4),
        if (_bike != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_bike!.displayName,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              if (_bike!.color != null)
                Text(_bike!.color!, style: theme.textTheme.bodySmall),
            ],
          )
        else
          Text('ID: ${job.bikeId}', style: theme.textTheme.bodySmall),
        const SizedBox(height: 24),
        _buildInfoRow('Mano de Obra', currencyFormat.format(job.laborCost)),
        _buildInfoRow('Repuestos', currencyFormat.format(job.partsCost)),
        const Divider(),
        _buildInfoRow('Total Estimado', currencyFormat.format(job.totalCost),
            isBold: true),
      ],
    );
  }

  Widget _buildInvoiceContent(Invoice invoice) {
    final theme = Theme.of(context);
    final currencyFormat =
        NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.receipt, size: 20, color: Colors.green),
            const SizedBox(width: 8),
            Text(
              'FACTURA',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        if (invoice.invoiceNumber.isNotEmpty)
          Text('#${invoice.invoiceNumber}', style: theme.textTheme.bodySmall),

        const SizedBox(height: 16),
        // Interactive Status?
        // For now just display
        _buildInfoRow('Estado', invoice.status.name.toUpperCase(),
            color: invoice.status == InvoiceStatus.paid
                ? Colors.green
                : Colors.orange),

        const Divider(height: 24),

        if (invoice.items.isNotEmpty) ...[
          Text('Items (${invoice.items.length})',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: Colors.grey[600])),
          const SizedBox(height: 8),
          // We use Column instead of ListView for inside ScrollView
          Column(
            children: invoice.items.map((item) {
              final desc =
                  item.productName ?? item.description ?? 'Item sin nombre';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(desc, style: theme.textTheme.bodySmall),
                        Text(
                            '${item.quantity} x ${currencyFormat.format(item.unitPrice)}',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontSize: 10, color: Colors.grey)),
                      ],
                    )),
                    Text(currencyFormat.format(item.lineTotal),
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              );
            }).toList(),
          ),
        ] else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('Sin items')),
          ),

        const Divider(),
        _buildInfoRow('Total', currencyFormat.format(invoice.total),
            isBold: true),
        _buildInfoRow('Saldo', currencyFormat.format(invoice.balance),
            color: invoice.balance > 0 ? Colors.red : Colors.green),
      ],
    );
  }

  Widget _buildOrderContent(OnlineOrder order) {
    final theme = Theme.of(context);
    final currencyFormat =
        NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final deliveryLabel =
        order.deliveryType == 'pickup' ? 'Retiro en tienda' : 'Despacho';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.shopping_cart_outlined,
                size: 20, color: Color(0xFF093357)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'PEDIDO WEB',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        Text('#${order.orderNumber}', style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        _buildInfoRow('Estado', order.status.toUpperCase(),
            color: _getOrderStatusColor(order.status)),
        _buildInfoRow('Pago', order.paymentStatus.toUpperCase(),
            color: _getPaymentStatusColor(order.paymentStatus)),
        _buildInfoRow('Entrega', deliveryLabel),
        const Divider(height: 24),
        Text('Cliente',
            style:
                theme.textTheme.labelSmall?.copyWith(color: Colors.grey[600])),
        const SizedBox(height: 6),
        Text(order.customerName,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        if (order.customerEmail.isNotEmpty)
          Text(order.customerEmail, style: theme.textTheme.bodySmall),
        if (order.customerPhone?.isNotEmpty == true)
          Text(order.customerPhone!, style: theme.textTheme.bodySmall),
        const Divider(height: 24),
        if (order.items.isNotEmpty) ...[
          Text('Productos (${order.items.length})',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: Colors.grey[600])),
          const SizedBox(height: 8),
          ...order.items.take(8).map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 28,
                    child: Text('${item.quantity}x',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.productName,
                            style: theme.textTheme.bodySmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        if (item.productSku?.isNotEmpty == true)
                          Text('SKU ${item.productSku}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 10,
                                color: Colors.grey[600],
                              )),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(currencyFormat.format(item.subtotal),
                      style: theme.textTheme.bodySmall),
                ],
              ),
            );
          }),
        ],
        const Divider(height: 24),
        _buildInfoRow('Total', currencyFormat.format(order.total),
            isBold: true),
        if (order.salesInvoiceId?.isNotEmpty == true)
          _buildInfoRow('Factura', 'Generada'),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value,
      {Color? color, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(
            value,
            style: TextStyle(
              color: color ?? Colors.black87,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(JobStatus status) {
    switch (status) {
      case JobStatus.pendiente:
        return Colors.orange;
      case JobStatus.finalizado:
        return Colors.blue;
      case JobStatus.entregado:
        return Colors.green;
      case JobStatus.cancelado:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _getOrderStatusColor(String status) {
    return switch (status) {
      'confirmed' => Colors.blue,
      'shipped' || 'ready_for_pickup' => Colors.indigo,
      'delivered' => Colors.green,
      'cancelled' => Colors.red,
      _ => Colors.orange,
    };
  }

  Color _getPaymentStatusColor(String status) {
    return switch (status) {
      'paid' => Colors.green,
      'failed' || 'refunded' => Colors.red,
      _ => Colors.orange,
    };
  }
}
