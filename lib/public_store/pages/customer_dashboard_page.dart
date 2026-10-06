import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../modules/website/models/website_models.dart';
import 'package:vinabike_public_core/public_store/models/customer_portal_plans.dart';
import 'package:vinabike_public_core/public_store/models/customer_portal_snapshot.dart';

import '../providers/public_store_tenant_provider.dart';
import '../services/customer_account_service.dart';
import '../widgets/customer_bike_card.dart';
import '../widgets/customer_job_row.dart';
import '../widgets/customer_order_row.dart';
import '../widgets/customer_portal_layout.dart';
import '../widgets/customer_portal_style.dart';
import '../widgets/public_store_layout.dart';

export 'package:vinabike_public_core/public_store/models/customer_portal_plans.dart'
    show customerDashboardBandMeta;

class CustomerDashboardPage extends StatefulWidget {
  const CustomerDashboardPage({super.key});

  @override
  State<CustomerDashboardPage> createState() => _CustomerDashboardPageState();
}

class _CustomerDashboardPageState extends State<CustomerDashboardPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final accountService = context.read<CustomerAccountService>();
      final tenantProvider = context.read<PublicStoreTenantProvider>();
      accountService.setTenantId(tenantProvider.tenantId);

      if (accountService.isAuthenticated) {
        accountService.loadOrders();
        accountService.loadAddresses();
        accountService.loadBikes();
        accountService.loadServiceHistory();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final accountService = context.watch<CustomerAccountService>();
    final profile = accountService.customerProfile;
    void navigate(String href) =>
        PublicStoreLayout.navigateToHref(context, href);
    final plan = CustomerDashboardPlan.of(
      profile: profile,
      orders: accountService.orders,
      jobs: accountService.serviceHistory,
    );

    return CustomerPortalLayout(
      title: plan.title,
      prominent: true,
      bandMeta: customerDashboardBandMeta(
        profile: profile,
        bikes: accountService.bikes.length,
        orders: accountService.orders.length,
      ),
      showBackButton: false,
      footer: CustomerDashboardServiceBand(
        profile: profile,
        addressesCount: accountService.addresses.length,
        onNavigate: navigate,
      ),
      child: CustomerDashboardBody(
        profile: profile,
        orders: accountService.orders,
        orderImages: accountService.orderProductImages,
        jobs: accountService.serviceHistory,
        bikes: accountService.bikes,
        addressesCount: accountService.addresses.length,
        onNavigate: navigate,
      ),
    );
  }
}

/// El resumen de la cuenta, sin el marco ni el servicio: recibe los datos y
/// dice adónde ir. Así se prueba y se mira sin una sesión.
///
/// Orden: lo que espera al cliente, en grande («Para ti ahora»); lo que sigue
/// en curso, también en grande, con su avance; sus bicicletas como tarjetas
/// de catálogo junto a la foto del taller; y los últimos pedidos en tabla.
/// Sin baldosas de cifras: un cero no le dice nada a nadie.
class CustomerDashboardBody extends StatelessWidget {
  const CustomerDashboardBody({
    super.key,
    required this.profile,
    required this.orders,
    required this.orderImages,
    required this.jobs,
    required this.bikes,
    required this.addressesCount,
    required this.onNavigate,
  });

  final Map<String, dynamic>? profile;
  final List<OnlineOrder> orders;
  final Map<String, String> orderImages;
  final List<Map<String, dynamic>> jobs;
  final List<Map<String, dynamic>> bikes;
  final int addressesCount;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final plan = CustomerDashboardPlan.of(
      profile: profile,
      orders: orders,
      jobs: jobs,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final compact = width < PortalStyle.compactBreakpoint;

        PortalTileBuilder tile(CustomerCurrentItem item) => (layout) {
              final order = item.order;
              if (order != null) {
                return CustomerOrderTile(
                  order: order,
                  imageUrl: customerOrderImage(order, orderImages),
                  compact: compact,
                  layout: layout,
                  onOpen: () => onNavigate('/pedido/${order.id}'),
                );
              }
              return CustomerJobTile(
                job: item.job!,
                compact: compact,
                layout: layout,
                onOpen: () => showCustomerJobDetail(
                  context,
                  job: item.job!,
                  onNavigate: onNavigate,
                ),
                onNavigate: onNavigate,
              );
            };

        final sections = <Widget>[
          if (plan.firstName == null)
            PortalNotice(
              icon: Icons.badge_outlined,
              message: 'Agrega tu nombre para que el taller sepa quién '
                  'eres cuando escribas o traigas tu bici.',
              actionLabel: 'Completar perfil',
              onAction: () => onNavigate('/cuenta/perfil'),
            ),
          if (plan.forYou.isNotEmpty)
            PortalSection(
              label: 'Para ti ahora',
              count: plan.forYou.length,
              child: PortalTileGrid(
                width: width,
                tiles: [for (final item in plan.forYou) tile(item)],
              ),
            ),
          if (plan.inProgress.isNotEmpty)
            PortalSection(
              label: 'En curso',
              child: PortalTileGrid(
                width: width,
                tiles: [for (final item in plan.inProgress) tile(item)],
              ),
            ),
          if (plan.nothingCurrent)
            PortalSection(
              label: 'En curso',
              child: _NothingInProgress(onNavigate: onNavigate),
            ),
          if (bikes.isNotEmpty)
            PortalSection(
              label: 'Tus bicicletas',
              actionLabel: bikes.length > 2 ? 'Ver todas' : null,
              onAction: () => onNavigate('/cuenta/bicicletas'),
              child: _BikesRow(
                bikes: bikes,
                width: width,
                onNavigate: onNavigate,
              ),
            ),
          if (plan.previousOrders.isNotEmpty)
            PortalSection(
              label: 'Últimos pedidos',
              actionLabel: 'Ver todos',
              onAction: () => onNavigate('/cuenta/pedidos'),
              child: PortalPanel(
                header: width >= customerOrderTableBreakpoint
                    ? const CustomerOrderTableHeader()
                    : null,
                children: [
                  for (final order in plan.previousOrders)
                    CustomerOrderRow(
                      order: order,
                      imageUrl: customerOrderImage(order, orderImages),
                      onTap: () => onNavigate('/pedido/${order.id}'),
                    ),
                ],
              ),
            ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < sections.length; i++) ...[
              if (i > 0) SizedBox(height: compact ? 56 : 88),
              sections[i],
            ],
          ],
        );
      },
    );
  }
}

/// Las bicis como tarjetas de catálogo. En ancho, hasta dos bicis y la foto
/// del taller (o tres bicis si tiene más); en teléfono, una fila que se
/// desliza.
class _BikesRow extends StatelessWidget {
  const _BikesRow({
    required this.bikes,
    required this.width,
    required this.onNavigate,
  });

  final List<Map<String, dynamic>> bikes;
  final double width;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    void open(Map<String, dynamic> bike) => showCustomerBikeDetail(
          context,
          bike: bike,
          onNavigate: onNavigate,
        );

    if (width < 760) {
      if (bikes.length == 1) {
        return CustomerBikeCard(
          bike: bikes.first,
          compact: true,
          onTap: () => open(bikes.first),
        );
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < bikes.length; i++) ...[
              if (i > 0) const SizedBox(width: 16),
              SizedBox(
                width: 280,
                child: CustomerBikeCard(
                  bike: bikes[i],
                  compact: true,
                  onTap: () => open(bikes[i]),
                ),
              ),
            ],
          ],
        ),
      );
    }

    final (:shown, :showWorkshop) = customerDashboardBikes(bikes);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 32),
            Expanded(
              child: i < shown.length
                  ? Align(
                      alignment: Alignment.topCenter,
                      child: CustomerBikeCard(
                        bike: shown[i],
                        onTap: () => open(shown[i]),
                      ),
                    )
                  : i == shown.length && showWorkshop
                      ? CustomerWorkshopTile(
                          onTap: () => onNavigate('/servicios'),
                        )
                      : const SizedBox.shrink(),
            ),
          ],
        ],
      ),
    );
  }
}

/// La franja de servicio al pie del resumen: hablar con el taller, la
/// garantía de las bicis y los datos de contacto y envío.
class CustomerDashboardServiceBand extends StatelessWidget {
  const CustomerDashboardServiceBand({
    super.key,
    required this.profile,
    required this.addressesCount,
    required this.onNavigate,
  });

  final Map<String, dynamic>? profile;
  final int addressesCount;
  final ValueChanged<String> onNavigate;

  static const _icons = {
    'chat_bubble_outline': Icons.chat_bubble_outline,
    'verified_user_outlined': Icons.verified_user_outlined,
    'location_on_outlined': Icons.location_on_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return PortalServiceBand(
      items: [
        for (final item in customerServiceBandItems(
          profile: profile,
          addressesCount: addressesCount,
        ))
          PortalServiceItem(
            icon: _icons[item.icon]!,
            title: item.title,
            message: item.message,
            actionLabel: item.actionLabel,
            onTap: () => onNavigate(item.href),
          ),
      ],
    );
  }
}

class _NothingInProgress extends StatelessWidget {
  const _NothingInProgress({required this.onNavigate});

  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    return PortalEmptyState(
      title: 'No tienes pedidos ni bicis en el taller.',
      message: 'Cuando compres o dejes tu bici con nosotros, vas a ver aquí '
          'en qué va.',
      actions: [
        PortalButton(
          label: 'Ver productos',
          arrow: true,
          onPressed: () => onNavigate('/productos'),
        ),
        PortalLink(
          label: 'Hablar con el taller',
          onTap: () => onNavigate('/cuenta/chats'),
        ),
      ],
    );
  }
}
