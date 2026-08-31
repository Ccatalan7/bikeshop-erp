import 'package:flutter/material.dart';

import '../models/purchase_order_summary.dart';
import 'purchase_visual_language.dart';

/// **Los pedidos que ya existen con este proveedor, arriba de todo.**
///
/// Es la respuesta a «lo guardé, ¿y dónde quedó?». La primera versión escribía
/// el pedido en la base y no lo mostraba en ninguna parte: el operador apretaba
/// guardar, salía un folio y el pedido desaparecía. Guardar en un lugar que
/// nadie puede abrir no es guardar.
///
/// Va en la ficha del proveedor, que es donde uno lo buscaría, y se retoma sin
/// salir del bloque: al tocarlo, sus líneas vuelven a la hoja tal como se
/// guardaron.
class SupplierOpenOrdersStrip extends StatelessWidget {
  const SupplierOpenOrdersStrip({
    super.key,
    required this.orders,
    required this.activeOrderId,
    required this.onResume,
  });

  final List<PurchaseOrderSummary> orders;
  final String? activeOrderId;
  final ValueChanged<PurchaseOrderSummary> onResume;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) return const SizedBox.shrink();
    final tokens = PurchaseTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PurchasePanel(
        padded: false,
        child: Column(
          key: const ValueKey('supplier-open-orders'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: tokens.sunken,
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              child: Text(
                orders.length == 1
                    ? 'PEDIDO ABIERTO CON ESTE PROVEEDOR'
                    : '${orders.length} PEDIDOS ABIERTOS CON ESTE PROVEEDOR',
                style: PurchaseType.label.copyWith(color: tokens.inkFaint),
              ),
            ),
            for (final order in orders)
              _OrderRow(
                order: order,
                active: order.orderId == activeOrderId,
                onResume: () => onResume(order),
              ),
          ],
        ),
      ),
    );
  }
}

class _OrderRow extends StatefulWidget {
  const _OrderRow({
    required this.order,
    required this.active,
    required this.onResume,
  });

  final PurchaseOrderSummary order;
  final bool active;
  final VoidCallback onResume;

  @override
  State<_OrderRow> createState() => _OrderRowState();
}

class _OrderRowState extends State<_OrderRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final order = widget.order;
    return Semantics(
      button: true,
      label: widget.active
          ? 'Pedido ${order.orderNumber}, abierto ahora'
          : 'Retomar el pedido ${order.orderNumber}',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.active ? null : widget.onResume,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: widget.active || _hovering
                  ? tokens.selected
                  : Colors.transparent,
              border: Border(top: BorderSide(color: tokens.hair)),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 34,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.orderNumber,
                        style:
                            PurchaseType.rowTitle.copyWith(color: tokens.ink),
                      ),
                      Text(
                        // El estado en palabras: «ordered» no le dice nada a
                        // nadie; lo que importa es si el proveedor ya lo tiene.
                        '${order.statusLabel} · ${order.lineCount} '
                        '${order.lineCount == 1 ? 'línea' : 'líneas'}',
                        style:
                            PurchaseType.meta.copyWith(color: tokens.inkFaint),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        PurchaseMoney.format(order.total, 'CLP'),
                        style: PurchaseType.metricSmall.copyWith(
                          color: tokens.ink,
                          fontFeatures: PurchaseType.tabular,
                        ),
                      ),
                      Text(
                        'IVA incluido',
                        style:
                            PurchaseType.meta.copyWith(color: tokens.inkFaint),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                SizedBox(
                  width: purchaseInlineActionWidth(
                    context,
                    const ['Retomar', 'Abierto'],
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: widget.active
                        ? Text(
                            'Abierto',
                            style: PurchaseType.meta
                                .copyWith(color: tokens.inkFaint),
                          )
                        : PurchaseInlineAction(
                            key: ValueKey('resume-order-${order.orderId}'),
                            label: 'Retomar',
                            onPressed: widget.onResume,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
