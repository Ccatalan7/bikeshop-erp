import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/vb_button.dart';
import '../../../shared/widgets/vb_segmented.dart' show VbDensity;
import '../../sales/models/customer_quote.dart';
import '../../sales/services/customer_quote_service.dart';
import '../../sales/widgets/on_order_fulfillment.dart';

/// Pedidos web › una compra directa con algo que llega del proveedor
/// (20261120210000): sus pedidos a proveedores, que nacen como borradores de
/// Compras al pagar, «Revisar si llegó» y «Anular y devolver». Son las mismas
/// piezas que muestra una cotización con su pedido; un pedido de cotización
/// se maneja desde ella.
class OnlineOrderSupplierPanel extends StatefulWidget {
  const OnlineOrderSupplierPanel({
    super.key,
    required this.orderId,
    this.onChanged,
    this.service,
  });

  final String orderId;

  /// El pedido cambió (llegó, se anuló): la lista se relee.
  final VoidCallback? onChanged;
  final CustomerQuoteService? service;

  @override
  State<OnlineOrderSupplierPanel> createState() =>
      _OnlineOrderSupplierPanelState();
}

class _OnlineOrderSupplierPanelState extends State<OnlineOrderSupplierPanel> {
  late final CustomerQuoteService _service =
      widget.service ?? CustomerQuoteService();
  CustomerQuoteOrder? _order;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant OnlineOrderSupplierPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderId != widget.orderId) {
      _order = null;
      _loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    final orderId = widget.orderId;
    try {
      final order = await _service.fetchOnlineOrderOnOrder(orderId);
      if (!mounted || orderId != widget.orderId) return;
      setState(() {
        _order = order;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || orderId != widget.orderId) return;
      setState(() {
        _error = CustomerQuoteService.describeError(error);
        _loading = false;
      });
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Compras es dueño del pedido al proveedor: se abre ahí y, al volver, se
  /// relee (lo enviado cambia su estado).
  Future<void> _open(String route) async {
    await context.push(route);
    if (mounted) await _load();
  }

  Future<void> _checkArrivals() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final found = await _service.checkOnlineOrderArrivals(widget.orderId);
      await _load();
      widget.onChanged?.call();
      _snack(found.message);
    } catch (error) {
      _snack(CustomerQuoteService.describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(CustomerQuoteOrder order) async {
    final sentPurchases =
        order.purchases.where((purchase) => !purchase.isDraft).length;
    final input = await showDialog<OnOrderRefundInput>(
      context: context,
      builder: (context) => OnOrderCancelRefundDialog(
        order: order,
        sentPurchases: sentPurchases,
      ),
    );
    if (input == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final fresh = await _service.cancelOnlineOrderOnOrder(
        widget.orderId,
        operationKey: input.operationKey,
        reason: input.reason,
        refundReference: input.reference,
        refundedAt: input.refundedAt,
      );
      if (!mounted) return;
      setState(() => _order = fresh);
      widget.onChanged?.call();
      _snack(sentPurchases > 0
          ? 'Pedido anulado. Avísale al proveedor: el pedido ya se le había '
              'enviado.'
          : 'Pedido anulado y devolución registrada');
    } catch (error) {
      _snack(CustomerQuoteService.describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (order == null) {
      final error = _error;
      return error == null
          ? const SizedBox.shrink()
          : Text(
              error,
              style: Theme.of(context).textTheme.bodySmall,
            );
    }
    // Antes del pago no hay pedido al proveedor ni nada que devolver: la
    // nota de arriba ya dice que se pide cuando el cliente pague.
    if (!order.isPaid && !order.isCancelled) return const SizedBox.shrink();
    final canCheck = order.isPaid && order.waiting && !order.isCancelled;
    final showOrders =
        order.purchases.isNotEmpty || (order.isPaid && order.missingSupplier > 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showOrders) OnOrderSupplierOrders(order: order, onOpen: _open),
        if (canCheck || order.canCancelAndRefund)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (canCheck)
                VbButton(
                  label: 'Revisar si llegó',
                  icon: Icons.inventory_2_outlined,
                  density: VbDensity.compact,
                  onPressed: _busy ? null : _checkArrivals,
                ),
              if (order.canCancelAndRefund)
                VbButton(
                  label: 'Anular y devolver',
                  variant: VbButtonVariant.text,
                  density: VbDensity.compact,
                  onPressed: _busy ? null : () => _cancel(order),
                ),
            ],
          ),
      ],
    );
  }
}
