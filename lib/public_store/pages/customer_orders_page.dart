import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../modules/website/models/website_models.dart';
import '../models/customer_portal_presentation.dart';
import '../services/customer_account_service.dart';
import '../widgets/customer_order_row.dart';
import '../widgets/customer_portal_layout.dart';
import '../widgets/customer_portal_style.dart';
import '../widgets/public_store_layout.dart';

class CustomerOrdersPage extends StatefulWidget {
  const CustomerOrdersPage({super.key});

  @override
  State<CustomerOrdersPage> createState() => _CustomerOrdersPageState();
}

class _CustomerOrdersPageState extends State<CustomerOrdersPage>
    with AutomaticKeepAliveClientMixin {
  CustomerOrderGroup? _group;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final accountService = context.watch<CustomerAccountService>();

    return CustomerPortalLayout(
      title: 'Pedidos',
      headerAction: OutlinedButton.icon(
        onPressed: () =>
            PublicStoreLayout.navigateToHref(context, '/productos'),
        icon: const Icon(Icons.storefront_outlined, size: 18),
        label: const Text('Ir a la tienda'),
        style: PortalStyle.of(context).secondaryButton,
      ),
      child: CustomerOrdersBody(
        orders: accountService.orders,
        orderImages: accountService.orderProductImages,
        group: _group,
        onGroupChanged: (group) => setState(() => _group = group),
        onNavigate: (href) => PublicStoreLayout.navigateToHref(context, href),
      ),
    );
  }
}

/// La lista de pedidos, sin el marco ni el servicio.
///
/// Las pestañas agrupan por lo que pasó con el pedido
/// ([CustomerOrderPresentation]), no por el campo de pago: antes un pedido
/// cancelado salía como «Pago pendiente» y el filtro «Pagados» buscaba un
/// estado que no existe. El detalle es la página del pedido (`/pedido/:id`),
/// la misma que se ve al comprar, con sus datos de pago y de entrega.
class CustomerOrdersBody extends StatelessWidget {
  const CustomerOrdersBody({
    super.key,
    required this.orders,
    required this.orderImages,
    required this.group,
    required this.onGroupChanged,
    required this.onNavigate,
  });

  final List<OnlineOrder> orders;
  final Map<String, String> orderImages;
  final CustomerOrderGroup? group;
  final ValueChanged<CustomerOrderGroup?> onGroupChanged;
  final ValueChanged<String> onNavigate;

  static const _labels = {
    CustomerOrderGroup.inProgress: 'En curso',
    CustomerOrderGroup.delivered: 'Entregados',
    CustomerOrderGroup.cancelled: 'Cancelados',
  };

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    if (orders.isEmpty) {
      return PortalPanel(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Todavía no tienes pedidos.', style: style.rowTitle),
                const SizedBox(height: 4),
                Text(
                  'Cuando compres en la tienda, cada pedido aparecerá aquí '
                  'con su estado.',
                  style: style.rowMeta,
                ),
                const SizedBox(height: 8),
                PortalLink(
                  label: 'Ver productos',
                  onTap: () => onNavigate('/productos'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final counts = <CustomerOrderGroup, int>{};
    for (final order in orders) {
      final g = CustomerOrderPresentation.of(order).group;
      counts[g] = (counts[g] ?? 0) + 1;
    }
    final effectiveGroup =
        group != null && (counts[group] ?? 0) > 0 ? group : null;
    final visible = effectiveGroup == null
        ? orders
        : orders
            .where((order) =>
                CustomerOrderPresentation.of(order).group == effectiveGroup)
            .toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _GroupChip(
                  label: 'Todos',
                  count: orders.length,
                  selected: effectiveGroup == null,
                  onTap: () => onGroupChanged(null),
                ),
                for (final entry in _labels.entries)
                  if ((counts[entry.key] ?? 0) > 0)
                    _GroupChip(
                      label: entry.value,
                      count: counts[entry.key]!,
                      selected: effectiveGroup == entry.key,
                      onTap: () => onGroupChanged(entry.key),
                    ),
              ],
            ),
            const SizedBox(height: 16),
            PortalPanel(
              children: [
                for (final order in visible)
                  CustomerOrderRow(
                    order: order,
                    imageUrl: _firstImage(order),
                    compact: compact,
                    onTap: () => onNavigate('/pedido/${order.id}'),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  String? _firstImage(OnlineOrder order) {
    for (final item in order.items) {
      final url = orderImages[item.productId];
      if (url != null) return url;
    }
    return null;
  }
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({
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
    final style = PortalStyle.of(context);
    final foreground = selected ? style.onAccent : style.ink;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? style.accent : style.panel,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? style.accent : style.line),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: style.rowMeta.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: style.rowMeta.copyWith(
                    color: foreground.withValues(alpha: 0.72),
                    fontFeatures: style.figure.fontFeatures,
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
