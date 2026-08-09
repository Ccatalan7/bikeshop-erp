import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../bikeshop/models/bikeshop_models.dart';
import '../../bikeshop/services/bikeshop_service.dart';
import '../../purchases/models/purchase_invoice.dart';
import '../../purchases/services/purchase_service.dart';
import '../../sales/models/sales_models.dart';
import '../../sales/services/sales_service.dart';
import '../../website/models/website_models.dart';
import '../../website/services/website_service.dart';
import '../../../shared/models/supplier.dart' as shared_supplier;
import '../../../shared/services/workspace_manager.dart';

/// Read-only operational context for an employee conversation.
///
/// Mutating and outbound messaging actions intentionally remain in
/// [ChatWindow]. This surface explains the linked record and opens its
/// canonical workspace page without creating a second workflow.
class ChatContextPanel extends StatefulWidget {
  final String contextType;
  final String contextId;
  final VoidCallback? onClose;

  const ChatContextPanel({
    super.key,
    required this.contextType,
    required this.contextId,
    this.onClose,
  });

  @override
  State<ChatContextPanel> createState() => _ChatContextPanelState();
}

class _ChatContextPanelState extends State<ChatContextPanel> {
  bool _isLoading = true;
  Object? _data;
  Invoice? _linkedSale;
  Bike? _bike;
  String? _error;

  final NumberFormat _currency = NumberFormat.currency(
    locale: 'es_CL',
    symbol: r'$',
    decimalDigits: 0,
  );
  final DateFormat _date = DateFormat('dd/MM/yyyy');

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

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _data = null;
      _bike = null;
      _linkedSale = null;
    });

    try {
      switch (widget.contextType) {
        case 'job':
          final bikeshopService = context.read<BikeshopService>();
          final salesService = context.read<SalesService>();
          final job = await bikeshopService.getJobById(widget.contextId);
          if (job == null) {
            _error = 'No se encontró el trabajo vinculado.';
            break;
          }

          _data = job;
          if (job.bikeId != null) {
            try {
              _bike = await bikeshopService.getBikeById(job.bikeId!);
            } catch (_) {
              // The work remains useful even when its optional bike preview
              // cannot be hydrated.
            }
          }
          if (job.invoiceId != null) {
            try {
              _linkedSale = await salesService.fetchInvoice(job.invoiceId!);
            } catch (_) {
              // Keep the job visible; the canonical sale page can still be
              // opened with the stored relationship.
            }
          }
          break;
        case 'invoice':
          final sale =
              await context.read<SalesService>().fetchInvoice(widget.contextId);
          if (sale == null) {
            _error = 'No se encontró la venta vinculada.';
          } else {
            _data = sale;
          }
          break;
        case 'order':
          final order = await context
              .read<WebsiteService>()
              .getOrderById(widget.contextId);
          if (order == null) {
            _error = 'No se encontró el pedido web vinculado.';
          } else {
            _data = order;
          }
          break;
        case 'purchase_invoice':
          final purchase = await context
              .read<PurchaseService>()
              .fetchPurchaseInvoice(widget.contextId);
          if (purchase == null) {
            _error = 'No se encontró la compra vinculada.';
          } else {
            _data = purchase;
          }
          break;
        case 'supplier':
          final supplier = await context
              .read<PurchaseService>()
              .getSupplier(widget.contextId);
          if (supplier == null) {
            _error = 'No se encontró el proveedor vinculado.';
          } else {
            _data = supplier;
          }
          break;
        default:
          _error = 'Este tipo de contexto todavía no está disponible.';
      }
    } catch (error) {
      _error = 'No fue posible cargar el contexto. Intenta nuevamente.';
      debugPrint('Error loading conversation context: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final preferredWidth = (viewportWidth * 0.24).clamp(320.0, 420.0);

    return SizedBox(
      width: preferredWidth,
      child: Material(
        color: colorScheme.surface,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(theme),
              Expanded(child: _buildBody(theme)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final (title, fallbackSubtitle, icon) = switch (widget.contextType) {
      'job' => ('Trabajo de taller', 'Detalle operativo', Icons.build_outlined),
      'invoice' => ('Venta', 'Registro comercial', Icons.receipt_long_outlined),
      'order' => ('Pedido web', 'Venta online', Icons.shopping_bag_outlined),
      'purchase_invoice' => (
          'Compra',
          'Documento de proveedor',
          Icons.inventory_2_outlined
        ),
      'supplier' => (
          'Proveedor',
          'Ficha de abastecimiento',
          Icons.storefront_outlined
        ),
      _ => ('Contexto', 'Información vinculada', Icons.info_outline),
    };
    final subtitle = _headerSubtitle(fallbackSubtitle);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 10, 15),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colorScheme.primary.withValues(alpha: 0.055),
          colorScheme.surface,
        ),
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (widget.onClose != null)
            IconButton(
              onPressed: widget.onClose,
              tooltip: 'Cerrar contexto',
              icon: const Icon(Icons.close, size: 20),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  String _headerSubtitle(String fallback) {
    final data = _data;
    if (data is MechanicJob) {
      return data.jobNumber?.trim().isNotEmpty == true
          ? data.jobNumber!.trim()
          : fallback;
    }
    if (data is Invoice) {
      return data.invoiceNumber.trim().isNotEmpty
          ? data.invoiceNumber.trim()
          : fallback;
    }
    if (data is OnlineOrder) return data.orderNumber;
    if (data is PurchaseInvoice) {
      return data.invoiceNumber.trim().isNotEmpty
          ? data.invoiceNumber.trim()
          : fallback;
    }
    if (data is shared_supplier.Supplier) return data.displayName;
    return fallback;
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.primary,
          ),
        ),
      );
    }

    if (_error != null) {
      return _buildErrorState(theme, _error!);
    }

    final data = _data;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      child: switch (data) {
        MechanicJob job => _buildJobContent(theme, job),
        Invoice sale => _buildSaleContent(theme, sale),
        OnlineOrder order => _buildOrderContent(theme, order),
        PurchaseInvoice purchase => _buildPurchaseContent(theme, purchase),
        shared_supplier.Supplier supplier =>
          _buildSupplierContent(theme, supplier),
        _ => _buildErrorState(theme, 'No hay información para mostrar.'),
      },
    );
  }

  Widget _buildErrorState(ThemeData theme, String message) {
    final colorScheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.link_off_outlined,
              size: 32,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobContent(ThemeData theme, MechanicJob job) {
    final bike = _bike;
    final request = (job.clientRequest ?? job.diagnosis ?? '').trim();
    final estimatedTotal = job.totalCost > 0
        ? job.totalCost
        : job.estimatedCost > 0
            ? job.estimatedCost
            : job.finalCost;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStatusLead(
          theme,
          label: job.status.displayName,
          color: _jobStatusColor(theme.colorScheme, job.status),
          detail: job.assignedTechnicianName?.trim().isNotEmpty == true
              ? 'Mecánico: ${job.assignedTechnicianName!.trim()}'
              : 'Mecánico por asignar',
        ),
        _section(
          theme,
          title: 'Trabajo',
          icon: Icons.build_outlined,
          children: [
            _detailRow(theme, 'Ingreso', _date.format(job.arrivalDate)),
            _detailRow(theme, 'Tipo', job.jobType.displayName),
            if (job.estimatedDurationHours != null)
              _detailRow(
                theme,
                'Tiempo estimado',
                '${job.estimatedDurationHours!.toStringAsFixed(1)} h',
              ),
          ],
        ),
        if (request.isNotEmpty)
          _textSection(
            theme,
            title: 'Solicitud / diagnóstico',
            text: request,
          ),
        _section(
          theme,
          title: bike != null ? 'Bicicleta' : 'Elemento recibido',
          icon: bike != null
              ? Icons.pedal_bike_outlined
              : Icons.category_outlined,
          children: bike != null
              ? [
                  _detailRow(theme, 'Bicicleta', bike.displayName),
                  if (bike.color?.trim().isNotEmpty == true)
                    _detailRow(theme, 'Color', bike.color!.trim()),
                  if (bike.serialNumber?.trim().isNotEmpty == true)
                    _detailRow(theme, 'Serie', bike.serialNumber!.trim()),
                ]
              : [
                  _detailRow(
                    theme,
                    'Elemento',
                    job.subjectData?.name ?? job.jobType.displayName,
                  ),
                ],
        ),
        _section(
          theme,
          title: job.isQuotationWorkflow
              ? job.proposalDocumentLabel
              : 'Resumen comercial',
          icon: Icons.request_quote_outlined,
          children: [
            if (job.isQuotationWorkflow)
              _detailRow(
                theme,
                'Decisión',
                job.effectiveQuotationStatus.displayName,
                valueColor: _quotationStatusColor(
                  theme.colorScheme,
                  job.effectiveQuotationStatus,
                ),
              ),
            _detailRow(theme, 'Servicios', _currency.format(job.laborCost)),
            _detailRow(
              theme,
              'Repuestos y productos',
              _currency.format(job.partsCost),
            ),
            _detailRow(
              theme,
              'Total estimado',
              _currency.format(estimatedTotal),
              emphasize: true,
            ),
          ],
        ),
        if (job.invoiceId != null)
          _section(
            theme,
            title: 'Venta asociada',
            icon: Icons.receipt_long_outlined,
            children: [
              _detailRow(
                theme,
                'Número',
                _linkedSale?.invoiceNumber.trim().isNotEmpty == true
                    ? _linkedSale!.invoiceNumber.trim()
                    : 'Registro vinculado',
              ),
              if (_linkedSale != null)
                _detailRow(
                  theme,
                  'Estado',
                  _saleStatusLabel(_linkedSale!.status),
                ),
              if (_linkedSale != null)
                _detailRow(
                  theme,
                  'Total',
                  _currency.format(_linkedSale!.total),
                  emphasize: true,
                ),
            ],
          ),
        const SizedBox(height: 18),
        _openButton(
          theme,
          label: 'Abrir trabajo',
          icon: Icons.open_in_new,
          route: '/taller/pegas/${job.id ?? widget.contextId}',
          primary: true,
        ),
        if (job.invoiceId != null) ...[
          const SizedBox(height: 8),
          _openButton(
            theme,
            label: 'Abrir venta asociada',
            icon: Icons.receipt_long_outlined,
            route: '/sales/invoices/${job.invoiceId}',
          ),
        ],
      ],
    );
  }

  Widget _buildSaleContent(ThemeData theme, Invoice sale) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStatusLead(
          theme,
          label: _saleStatusLabel(sale.status),
          color: _saleStatusColor(theme.colorScheme, sale.status),
          detail: sale.customerName?.trim().isNotEmpty == true
              ? sale.customerName!.trim()
              : 'Cliente sin nombre registrado',
        ),
        _section(
          theme,
          title: 'Venta',
          icon: Icons.receipt_long_outlined,
          children: [
            _detailRow(
              theme,
              'Número',
              sale.invoiceNumber.trim().isEmpty
                  ? 'Sin folio'
                  : sale.invoiceNumber.trim(),
            ),
            _detailRow(theme, 'Fecha', _date.format(sale.date)),
            _detailRow(theme, 'Ítems', '${sale.items.length}'),
            if (sale.reference?.trim().isNotEmpty == true)
              _detailRow(theme, 'Referencia', sale.reference!.trim()),
          ],
        ),
        if (sale.items.isNotEmpty)
          _itemSection(
            theme,
            title: 'Detalle',
            items: sale.items.map((item) {
              final name =
                  item.productName ?? item.description ?? 'Ítem sin nombre';
              return _LineItem(
                title: name,
                detail:
                    '${item.quantity} × ${_currency.format(item.unitPrice)}',
                total: _currency.format(item.lineTotal),
              );
            }).toList(),
          ),
        _section(
          theme,
          title: 'Totales',
          icon: Icons.payments_outlined,
          children: [
            _detailRow(theme, 'Neto', _currency.format(sale.netAmount)),
            if (sale.ivaAmount > 0)
              _detailRow(theme, 'IVA', _currency.format(sale.ivaAmount)),
            _detailRow(
              theme,
              'Total',
              _currency.format(sale.total),
              emphasize: true,
            ),
            if (sale.paidAmount > 0)
              _detailRow(theme, 'Pagado', _currency.format(sale.paidAmount)),
            if (sale.balance > 0)
              _detailRow(
                theme,
                'Saldo',
                _currency.format(sale.balance),
                valueColor: theme.colorScheme.tertiary,
              ),
          ],
        ),
        const SizedBox(height: 18),
        _openButton(
          theme,
          label: 'Abrir venta',
          icon: Icons.open_in_new,
          route: '/sales/invoices/${sale.id ?? widget.contextId}',
          primary: true,
        ),
      ],
    );
  }

  Widget _buildOrderContent(ThemeData theme, OnlineOrder order) {
    final deliveryLabel =
        order.deliveryType == 'pickup' ? 'Retiro en tienda' : 'Despacho';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStatusLead(
          theme,
          label: _orderStatusLabel(order.status),
          color: _orderStatusColor(theme.colorScheme, order.status),
          detail:
              '${_paymentStatusLabel(order.paymentStatus)} · $deliveryLabel',
        ),
        _section(
          theme,
          title: 'Cliente y entrega',
          icon: Icons.local_shipping_outlined,
          children: [
            _detailRow(theme, 'Cliente', order.customerName),
            _detailRow(theme, 'Email', order.customerEmail),
            if (order.customerPhone?.trim().isNotEmpty == true)
              _detailRow(theme, 'Teléfono', order.customerPhone!.trim()),
            _detailRow(theme, 'Entrega', deliveryLabel),
            _detailRow(theme, 'Fecha', _date.format(order.createdAt)),
          ],
        ),
        if (order.items.isNotEmpty)
          _itemSection(
            theme,
            title: 'Productos',
            items: order.items
                .map(
                  (item) => _LineItem(
                    title: item.productName,
                    detail:
                        '${item.quantity} × ${_currency.format(item.unitPrice)}',
                    total: _currency.format(item.subtotal),
                  ),
                )
                .toList(),
          ),
        _section(
          theme,
          title: 'Pago',
          icon: Icons.payments_outlined,
          children: [
            _detailRow(
              theme,
              'Estado',
              _paymentStatusLabel(order.paymentStatus),
              valueColor:
                  _paymentStatusColor(theme.colorScheme, order.paymentStatus),
            ),
            if (order.paymentMethod?.trim().isNotEmpty == true)
              _detailRow(theme, 'Medio', order.paymentMethod!.trim()),
            _detailRow(
              theme,
              'Total',
              _currency.format(order.total),
              emphasize: true,
            ),
          ],
        ),
        if (order.salesInvoiceId != null)
          _section(
            theme,
            title: 'Venta / boleta',
            icon: Icons.receipt_long_outlined,
            children: [
              _detailRow(theme, 'Registro', 'Venta generada'),
            ],
          ),
        const SizedBox(height: 18),
        _openButton(
          theme,
          label: 'Abrir pedido',
          icon: Icons.open_in_new,
          route: '/website/orders',
          primary: true,
        ),
        if (order.salesInvoiceId != null) ...[
          const SizedBox(height: 8),
          _openButton(
            theme,
            label: 'Abrir venta / boleta',
            icon: Icons.receipt_long_outlined,
            route: '/sales/invoices/${order.salesInvoiceId}',
          ),
        ],
      ],
    );
  }

  Widget _buildPurchaseContent(ThemeData theme, PurchaseInvoice purchase) {
    final supplierName = purchase.supplierName?.trim();
    final supplierLabel = supplierName?.isNotEmpty == true
        ? supplierName!
        : 'Proveedor sin nombre registrado';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStatusLead(
          theme,
          label: purchase.status.displayName,
          color: _purchaseStatusColor(theme.colorScheme, purchase.status),
          detail: supplierLabel,
        ),
        _section(
          theme,
          title: 'Compra',
          icon: Icons.inventory_2_outlined,
          children: [
            _detailRow(
              theme,
              'Número',
              purchase.invoiceNumber.trim().isEmpty
                  ? 'Sin folio interno'
                  : purchase.invoiceNumber.trim(),
            ),
            _detailRow(theme, 'Fecha', _date.format(purchase.date)),
            if (purchase.dueDate != null)
              _detailRow(
                theme,
                'Vencimiento',
                _date.format(purchase.dueDate!),
              ),
            if (purchase.supplierInvoiceNumber?.trim().isNotEmpty == true)
              _detailRow(
                theme,
                'Documento proveedor',
                purchase.supplierInvoiceNumber!.trim(),
              ),
            if (purchase.reference?.trim().isNotEmpty == true)
              _detailRow(theme, 'Referencia', purchase.reference!.trim()),
          ],
        ),
        if (purchase.items.isNotEmpty)
          _itemSection(
            theme,
            title: 'Detalle',
            items: purchase.items
                .map(
                  (item) => _LineItem(
                    title: item.productName ??
                        item.description ??
                        'Ítem sin nombre',
                    detail:
                        '${item.quantity} × ${_currency.format(item.unitCost)}',
                    total: _currency.format(item.netAmountClamped),
                  ),
                )
                .toList(),
          ),
        _section(
          theme,
          title: 'Pago',
          icon: Icons.payments_outlined,
          children: [
            _detailRow(theme, 'Total', _currency.format(purchase.total),
                emphasize: true),
            if (purchase.paidAmount > 0)
              _detailRow(
                theme,
                'Pagado',
                _currency.format(purchase.paidAmount),
              ),
            if (purchase.balance > 0)
              _detailRow(
                theme,
                'Saldo',
                _currency.format(purchase.balance),
                valueColor: theme.colorScheme.tertiary,
              ),
          ],
        ),
        const SizedBox(height: 18),
        _openButton(
          theme,
          label: 'Abrir compra',
          icon: Icons.open_in_new,
          route: '/purchases/${purchase.id ?? widget.contextId}',
          primary: true,
        ),
        if (purchase.supplierId?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 8),
          _openButton(
            theme,
            label: 'Abrir proveedor',
            icon: Icons.storefront_outlined,
            route: '/purchases/suppliers/${purchase.supplierId}',
          ),
        ],
      ],
    );
  }

  Widget _buildSupplierContent(
    ThemeData theme,
    shared_supplier.Supplier supplier,
  ) {
    final representative = supplier.salesRepName?.trim().isNotEmpty == true
        ? supplier.salesRepName!.trim()
        : supplier.contactPerson?.trim();
    final phone = supplier.salesRepPhone?.trim().isNotEmpty == true
        ? supplier.salesRepPhone!.trim()
        : supplier.phone?.trim();
    final email = supplier.salesRepEmail?.trim().isNotEmpty == true
        ? supplier.salesRepEmail!.trim()
        : supplier.email?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStatusLead(
          theme,
          label: supplier.isActive ? 'Proveedor activo' : 'Proveedor inactivo',
          color: supplier.isActive
              ? theme.colorScheme.secondary
              : theme.colorScheme.error,
          detail: representative?.isNotEmpty == true
              ? 'Contacto: $representative'
              : supplier.type.displayName,
        ),
        _section(
          theme,
          title: 'Identidad',
          icon: Icons.storefront_outlined,
          children: [
            _detailRow(theme, 'Nombre', supplier.displayName),
            if (supplier.legalName?.trim().isNotEmpty == true)
              _detailRow(theme, 'Razón social', supplier.legalName!.trim()),
            if (supplier.rut?.trim().isNotEmpty == true)
              _detailRow(theme, 'RUT', supplier.rut!.trim()),
            _detailRow(theme, 'Tipo', supplier.type.displayName),
          ],
        ),
        if (representative?.isNotEmpty == true ||
            phone?.isNotEmpty == true ||
            email?.isNotEmpty == true)
          _section(
            theme,
            title: 'Contacto',
            icon: Icons.contact_phone_outlined,
            children: [
              if (representative?.isNotEmpty == true)
                _detailRow(theme, 'Persona', representative!),
              if (phone?.isNotEmpty == true)
                _detailRow(theme, 'Teléfono', phone!),
              if (email?.isNotEmpty == true) _detailRow(theme, 'Email', email!),
            ],
          ),
        _section(
          theme,
          title: 'Abastecimiento',
          icon: Icons.local_shipping_outlined,
          children: [
            _detailRow(
              theme,
              'Condición de pago',
              supplier.paymentTerms.displayName,
            ),
            if (supplier.website?.trim().isNotEmpty == true)
              _detailRow(theme, 'Sitio web', supplier.website!.trim()),
          ],
        ),
        const SizedBox(height: 18),
        _openButton(
          theme,
          label: 'Abrir proveedor',
          icon: Icons.open_in_new,
          route: '/purchases/suppliers/${supplier.id}',
          primary: true,
        ),
      ],
    );
  }

  Widget _buildStatusLead(
    ThemeData theme, {
    required String label,
    required Color color,
    required String detail,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 42,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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

  Widget _section(
    ThemeData theme, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeading(theme, title, icon),
          const SizedBox(height: 8),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          ...children,
        ],
      ),
    );
  }

  Widget _textSection(
    ThemeData theme, {
    required String title,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading(theme, title, Icons.notes_outlined),
          const SizedBox(height: 8),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 10),
          Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.42),
          ),
        ],
      ),
    );
  }

  Widget _itemSection(
    ThemeData theme, {
    required String title,
    required List<_LineItem> items,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeading(theme, title, Icons.list_alt_outlined),
          const SizedBox(height: 8),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.detail,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    item.total,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionHeading(ThemeData theme, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 17, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _detailRow(
    ThemeData theme,
    String label,
    String value, {
    bool emphasize = false,
    Color? valueColor,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                color: valueColor ?? theme.colorScheme.onSurface,
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _openButton(
    ThemeData theme, {
    required String label,
    required IconData icon,
    required String route,
    bool primary = false,
  }) {
    void onPressed() {
      context.read<WorkspaceManager>().openRouteInWorkspace(route);
    }

    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(42)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );

    if (primary) {
      return FilledButton.icon(
        onPressed: onPressed,
        style: style,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: style,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  Color _jobStatusColor(ColorScheme scheme, JobStatus status) {
    return switch (status) {
      JobStatus.cancelado => scheme.error,
      JobStatus.entregado || JobStatus.finalizado => scheme.secondary,
      JobStatus.esperandoAprobacion ||
      JobStatus.esperandoRepuestos =>
        scheme.tertiary,
      _ => scheme.primary,
    };
  }

  Color _quotationStatusColor(ColorScheme scheme, QuotationStatus status) {
    return switch (status) {
      QuotationStatus.approved => scheme.secondary,
      QuotationStatus.rejected || QuotationStatus.expired => scheme.error,
      QuotationStatus.pending => scheme.tertiary,
    };
  }

  String _saleStatusLabel(InvoiceStatus status) {
    return switch (status) {
      InvoiceStatus.draft => 'Borrador',
      InvoiceStatus.sent => 'Emitida',
      InvoiceStatus.confirmed => 'Confirmada',
      InvoiceStatus.paid => 'Pagada',
      InvoiceStatus.overdue => 'Vencida',
      InvoiceStatus.cancelled => 'Anulada',
    };
  }

  Color _saleStatusColor(ColorScheme scheme, InvoiceStatus status) {
    return switch (status) {
      InvoiceStatus.cancelled || InvoiceStatus.overdue => scheme.error,
      InvoiceStatus.paid || InvoiceStatus.confirmed => scheme.secondary,
      InvoiceStatus.draft || InvoiceStatus.sent => scheme.tertiary,
    };
  }

  Color _purchaseStatusColor(
    ColorScheme scheme,
    PurchaseInvoiceStatus status,
  ) {
    return switch (status) {
      PurchaseInvoiceStatus.cancelled => scheme.error,
      PurchaseInvoiceStatus.received ||
      PurchaseInvoiceStatus.paid =>
        scheme.secondary,
      PurchaseInvoiceStatus.confirmed => scheme.primary,
      PurchaseInvoiceStatus.draft ||
      PurchaseInvoiceStatus.sent =>
        scheme.tertiary,
    };
  }

  String _orderStatusLabel(String status) {
    return switch (status.toLowerCase()) {
      'confirmed' => 'Confirmado',
      'processing' => 'En preparación',
      'ready_for_pickup' => 'Listo para retiro',
      'shipped' => 'Despachado',
      'delivered' => 'Entregado',
      'cancelled' => 'Cancelado',
      _ => 'Pendiente',
    };
  }

  Color _orderStatusColor(ColorScheme scheme, String status) {
    return switch (status.toLowerCase()) {
      'cancelled' => scheme.error,
      'delivered' => scheme.secondary,
      'ready_for_pickup' || 'shipped' => scheme.primary,
      _ => scheme.tertiary,
    };
  }

  String _paymentStatusLabel(String status) {
    return switch (status.toLowerCase()) {
      'paid' => 'Pagado',
      'authorized' => 'Autorizado',
      'failed' => 'Fallido',
      'refunded' => 'Reembolsado',
      'partially_refunded' => 'Reembolso parcial',
      _ => 'Pendiente',
    };
  }

  Color _paymentStatusColor(ColorScheme scheme, String status) {
    return switch (status.toLowerCase()) {
      'paid' || 'authorized' => scheme.secondary,
      'failed' || 'refunded' => scheme.error,
      _ => scheme.tertiary,
    };
  }
}

class _LineItem {
  final String title;
  final String detail;
  final String total;

  const _LineItem({
    required this.title,
    required this.detail,
    required this.total,
  });
}
