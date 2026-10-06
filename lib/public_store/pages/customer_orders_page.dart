import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vinabike_public_core/public_store/models/customer_portal_plans.dart';
import 'package:vinabike_public_core/public_store/models/customer_portal_snapshot.dart';

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
      subtitle: 'Todo lo que compraste en la tienda, con su estado.',
      headerAction: PortalButton(
        label: 'Ir a la tienda',
        kind: PortalButtonKind.onPhoto,
        arrow: true,
        onPressed: () =>
            PublicStoreLayout.navigateToHref(context, '/productos'),
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

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return PortalEmptyState(
        title: 'Todavía no tienes pedidos.',
        message: 'Cuando compres en la tienda, cada pedido aparecerá aquí '
            'con su estado.',
        actions: [
          PortalLink(
            label: 'Ver productos',
            onTap: () => onNavigate('/productos'),
          ),
        ],
      );
    }

    final plan = CustomerOrdersPlan.of(orders, group: group);

    return LayoutBuilder(
      builder: (context, constraints) {
        final table = constraints.maxWidth >= customerOrderTableBreakpoint;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                PortalFilterChip(
                  label: 'Todos',
                  count: orders.length,
                  selected: plan.group == null,
                  onTap: () => onGroupChanged(null),
                ),
                for (final g in plan.groups)
                  PortalFilterChip(
                    label: CustomerOrdersPlan.labels[g]!,
                    count: plan.counts[g]!,
                    selected: plan.group == g,
                    onTap: () => onGroupChanged(g),
                  ),
              ],
            ),
            const SizedBox(height: 40),
            PortalPanel(
              header: table ? const CustomerOrderTableHeader() : null,
              children: [
                for (final order in plan.visible)
                  CustomerOrderRow(
                    order: order,
                    imageUrl: customerOrderImage(order, orderImages),
                    onTap: () => onNavigate('/pedido/${order.id}'),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
