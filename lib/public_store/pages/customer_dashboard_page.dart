import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../modules/website/models/website_models.dart';
import '../models/customer_portal_presentation.dart';
import '../providers/public_store_tenant_provider.dart';
import '../services/customer_account_service.dart';
import '../widgets/customer_job_row.dart';
import '../widgets/customer_portal_layout.dart';
import '../widgets/customer_order_row.dart';
import '../widgets/customer_portal_style.dart';
import '../widgets/public_store_layout.dart';

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

    return CustomerPortalLayout(
      title: 'Resumen',
      showBackButton: false,
      showHeader: false,
      child: CustomerDashboardBody(
        profile: accountService.customerProfile,
        orders: accountService.orders,
        orderImages: accountService.orderProductImages,
        jobs: accountService.serviceHistory,
        bikes: accountService.bikes,
        addressesCount: accountService.addresses.length,
        onNavigate: (href) => PublicStoreLayout.navigateToHref(context, href),
      ),
    );
  }
}

/// El resumen de la cuenta, sin el marco ni el servicio: recibe los datos y
/// dice adónde ir. Así se prueba y se mira sin una sesión.
///
/// Orden: lo que está pasando ahora (pedidos en curso y bicis en el taller,
/// primero lo que espera al cliente), lo anterior, las bicicletas y los datos
/// de la cuenta. Sin baldosas de cifras: un cero no le dice nada a nadie.
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
    final firstName = customerFirstName(profile);
    final since = portalParseDate(profile?['created_at']);

    final current = <_CurrentItem>[
      for (final order in orders)
        if (CustomerOrderPresentation.of(order).group ==
            CustomerOrderGroup.inProgress)
          _CurrentItem.order(order),
      for (final job in jobs)
        if (CustomerWorkshopPresentation.of(job).isActive)
          _CurrentItem.job(job),
    ]..sort((a, b) {
        if (a.needsCustomer != b.needsCustomer) {
          return a.needsCustomer ? -1 : 1;
        }
        return b.date.compareTo(a.date);
      });
    final previous = orders
        .where((order) =>
            CustomerOrderPresentation.of(order).group !=
            CustomerOrderGroup.inProgress)
        .take(3)
        .toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PortalPageHeader(
              title: firstName == null ? 'Tu cuenta' : 'Hola, $firstName',
              subtitle: since == null
                  ? null
                  : 'Cliente desde ${portalMonthYear(since)}',
              compact: compact,
            ),
            if (firstName == null) ...[
              const SizedBox(height: 20),
              PortalNotice(
                icon: Icons.badge_outlined,
                message: 'Agrega tu nombre para que el taller sepa quién '
                    'eres cuando escribas o traigas tu bici.',
                actionLabel: 'Completar perfil',
                onAction: () => onNavigate('/cuenta/perfil'),
              ),
            ],
            SizedBox(height: compact ? 24 : 32),
            PortalSection(
              label: 'En curso',
              child: current.isEmpty
                  ? _NothingInProgress(onNavigate: onNavigate)
                  : PortalPanel(
                      children: [
                        for (final item in current)
                          item.order != null
                              ? CustomerOrderRow(
                                  order: item.order!,
                                  imageUrl: _firstImage(item.order!),
                                  compact: compact,
                                  onTap: () =>
                                      onNavigate('/pedido/${item.order!.id}'),
                                )
                              : CustomerJobRow(
                                  job: item.job!,
                                  compact: compact,
                                  onTap: () => showCustomerJobDetail(
                                    context,
                                    job: item.job!,
                                    onNavigate: onNavigate,
                                  ),
                                ),
                      ],
                    ),
            ),
            if (previous.isNotEmpty) ...[
              const SizedBox(height: 32),
              PortalSection(
                label: 'Pedidos anteriores',
                actionLabel: 'Ver todos',
                onAction: () => onNavigate('/cuenta/pedidos'),
                child: PortalPanel(
                  children: [
                    for (final order in previous)
                      CustomerOrderRow(
                        order: order,
                        imageUrl: _firstImage(order),
                        compact: compact,
                        onTap: () => onNavigate('/pedido/${order.id}'),
                      ),
                  ],
                ),
              ),
            ],
            if (bikes.isNotEmpty) ...[
              const SizedBox(height: 32),
              PortalSection(
                label: 'Tus bicicletas',
                actionLabel: 'Ver todas',
                onAction: () => onNavigate('/cuenta/bicicletas'),
                child: PortalPanel(
                  children: [
                    for (final bike in bikes.take(3))
                      PortalRow(
                        leading: PortalThumb(
                          fallbackIcon: Icons.pedal_bike_outlined,
                          imageUrl: customerBikeImage(bike),
                        ),
                        title: CustomerWorkshopPresentation.bikeTitle(bike),
                        meta: _bikeMeta(bike),
                        onTap: () => onNavigate(
                          '/cuenta/servicios?bike_id=${bike['id']}',
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 32),
            PortalSection(
              label: 'Contacto y envío',
              child: PortalPanel(
                children: [
                  _AccountFact(
                    label: 'Correo',
                    value: (profile?['email'] ?? '').toString(),
                  ),
                  _AccountFact(
                    label: 'Teléfono',
                    value: (profile?['phone'] ?? '').toString(),
                    emptyAction: 'Agregar',
                    onTap: () => onNavigate('/cuenta/perfil'),
                  ),
                  _AccountFact(
                    label: 'Direcciones de envío',
                    value: switch (addressesCount) {
                      0 => '',
                      1 => '1 guardada',
                      _ => '$addressesCount guardadas',
                    },
                    emptyAction: 'Agregar',
                    onTap: () => onNavigate('/cuenta/direcciones'),
                  ),
                ],
              ),
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

  static String _bikeMeta(Map<String, dynamic> bike) =>
      customerBikeServiceSummary(bike);
}

class _CurrentItem {
  _CurrentItem.order(OnlineOrder this.order)
      : job = null,
        needsCustomer = CustomerOrderPresentation.of(order).needsCustomer,
        date = order.createdAt;

  _CurrentItem.job(Map<String, dynamic> this.job)
      : order = null,
        needsCustomer = CustomerWorkshopPresentation.of(job).needsCustomer,
        date = portalParseDate(job['created_at']) ??
            DateTime.fromMillisecondsSinceEpoch(0);

  final OnlineOrder? order;
  final Map<String, dynamic>? job;
  final bool needsCustomer;
  final DateTime date;
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
        PortalLink(
          label: 'Ver productos',
          onTap: () => onNavigate('/productos'),
        ),
        PortalLink(
          label: 'Hablar con el taller',
          onTap: () => onNavigate('/cuenta/chats'),
        ),
      ],
    );
  }
}

class _AccountFact extends StatelessWidget {
  const _AccountFact({
    required this.label,
    required this.value,
    this.emptyAction,
    this.onTap,
  });

  final String label;
  final String value;
  final String? emptyAction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final empty = value.trim().isEmpty;
    return PortalRow(
      title: label,
      trailing: empty && emptyAction != null
          ? Text(emptyAction!, style: style.link)
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(
                empty ? '—' : value,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style.rowMeta.copyWith(color: style.ink),
              ),
            ),
      onTap: onTap,
    );
  }
}
