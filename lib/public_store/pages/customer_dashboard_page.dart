import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/public_store_tenant_provider.dart';
import '../services/customer_account_service.dart';
import '../widgets/customer_portal_layout.dart';
import '../widgets/public_store_layout.dart';
import '../../shared/utils/chilean_utils.dart';

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
    final fullName = (profile?['name'] ?? 'Cliente').toString();
    final firstName = fullName.trim().isEmpty
        ? 'Cliente'
        : fullName.trim().split(RegExp(r'\s+')).first;
    final activeServices = accountService.serviceHistory
        .where((service) =>
            !['ENTREGADO', 'CANCELADO'].contains(service['status']))
        .toList();

    return CustomerPortalLayout(
      title: 'Mi cuenta',
      showBackButton: false,
      showHeader: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WelcomePanel(firstName: firstName),
          const SizedBox(height: 18),
          const _DashboardHeading(),
          const SizedBox(height: 16),
          _AccountMetrics(
            ordersCount: accountService.orders.length,
            addressesCount: accountService.addresses.length,
            bikesCount: accountService.bikes.length,
            activeServicesCount: activeServices.length,
          ),
          const SizedBox(height: 18),
          _PortalSection(
            title: 'Actividad reciente',
            actionLabel: 'Ver pedidos',
            onAction: () => PublicStoreLayout.navigateToHref(
              context,
              '/cuenta/pedidos',
            ),
            child: _RecentOrdersPreview(orders: accountService.orders),
          ),
          const SizedBox(height: 18),
          _PortalSection(
            title: 'Taller y bicicletas',
            actionLabel: 'Ver taller',
            onAction: () => PublicStoreLayout.navigateToHref(
              context,
              '/cuenta/servicios',
            ),
            child: _WorkshopPreview(
              activeServices: activeServices,
              bikes: accountService.bikes,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardHeading extends StatelessWidget {
  const _DashboardHeading();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mi cuenta',
          style: TextStyle(
            color: Color(0xFF18212F),
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Compra, revisa tus datos y vuelve a lo importante sin fricción.',
          style: TextStyle(
            color: Color(0xFF667085),
            fontSize: 13,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _WelcomePanel extends StatelessWidget {
  final String firstName;

  const _WelcomePanel({required this.firstName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF102A43),
        borderRadius: BorderRadius.circular(10),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hola, $firstName',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tus compras, datos personales, direcciones y bicicletas en un solo lugar.',
                style: TextStyle(
                  color: Color(0xFFD9E2EC),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          );
          return copy;
        },
      ),
    );
  }
}

class _AccountMetrics extends StatelessWidget {
  final int ordersCount;
  final int addressesCount;
  final int bikesCount;
  final int activeServicesCount;

  const _AccountMetrics({
    required this.ordersCount,
    required this.addressesCount,
    required this.bikesCount,
    required this.activeServicesCount,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 620 ? 2 : 4;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: columns,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: columns == 2 ? 1.55 : 1.25,
          children: [
            _MetricTile(
              icon: Icons.receipt_long_outlined,
              value: ordersCount.toString(),
              label: 'Pedidos',
            ),
            _MetricTile(
              icon: Icons.location_on_outlined,
              value: addressesCount.toString(),
              label: 'Direcciones',
            ),
            _MetricTile(
              icon: Icons.pedal_bike_outlined,
              value: bikesCount.toString(),
              label: 'Bicicletas',
            ),
            _MetricTile(
              icon: Icons.build_outlined,
              value: activeServicesCount.toString(),
              label: 'Servicios activos',
            ),
          ],
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _MetricTile({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E4EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: const Color(0xFF102A43), size: 22),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF18212F),
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF667085),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PortalSection extends StatelessWidget {
  final String title;
  final String actionLabel;
  final VoidCallback onAction;
  final Widget child;

  const _PortalSection({
    required this.title,
    required this.actionLabel,
    required this.onAction,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E4EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF18212F),
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              TextButton(
                onPressed: onAction,
                child: Text(actionLabel),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _RecentOrdersPreview extends StatelessWidget {
  final List<dynamic> orders;

  const _RecentOrdersPreview({required this.orders});

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return _EmptyInlineState(
        icon: Icons.receipt_long_outlined,
        title: 'Aún no hay compras',
        message: 'Cuando compres en Viñabike, tus pedidos aparecerán aquí.',
        actionLabel: 'Ver productos',
        onAction: () => PublicStoreLayout.navigateToHref(context, '/productos'),
      );
    }

    return Column(
      children: orders.take(3).map((order) {
        final orderNumber = _read(order, 'orderNumber') ??
            _read(order, 'order_number') ??
            'N/A';
        final total = _read(order, 'total');
        final status = (_read(order, 'paymentStatus') ??
                _read(order, 'payment_status') ??
                'pending')
            .toString();
        return _CompactRow(
          icon: Icons.receipt_long_outlined,
          title: 'Pedido #$orderNumber',
          subtitle: _statusLabel(status),
          trailing: total is num
              ? ChileanUtils.formatCurrency(total.toDouble())
              : null,
        );
      }).toList(),
    );
  }

  static dynamic _read(dynamic object, String key) {
    if (object is Map<String, dynamic>) return object[key];
    try {
      final value = switch (key) {
        'orderNumber' => object.orderNumber,
        'paymentStatus' => object.paymentStatus,
        'total' => object.total,
        _ => null,
      };
      return value;
    } catch (_) {
      return null;
    }
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'approved':
      case 'paid':
        return 'Pago confirmado';
      case 'pending':
        return 'Pago pendiente';
      case 'cancelled':
      case 'rejected':
        return 'Cancelado';
      case 'shipped':
        return 'Enviado';
      case 'delivered':
        return 'Entregado';
      default:
        return status;
    }
  }
}

class _WorkshopPreview extends StatelessWidget {
  final List<dynamic> activeServices;
  final List<dynamic> bikes;

  const _WorkshopPreview({required this.activeServices, required this.bikes});

  @override
  Widget build(BuildContext context) {
    if (activeServices.isEmpty && bikes.isEmpty) {
      return _EmptyInlineState(
        icon: Icons.pedal_bike_outlined,
        title: 'Sin actividad de taller',
        message:
            'Tus bicicletas y servicios aparecerán cuando visites el taller.',
        actionLabel: 'Contactar tienda',
        onAction: () => PublicStoreLayout.navigateToHref(context, '/contacto'),
      );
    }

    return Column(
      children: [
        if (activeServices.isNotEmpty)
          ...activeServices.take(2).map((service) => _CompactRow(
                icon: Icons.build_outlined,
                title:
                    '${service['bike_brand'] ?? ''} ${service['bike_model'] ?? 'Servicio'}'
                        .trim(),
                subtitle: 'Estado: ${service['status'] ?? 'en revisión'}',
              )),
        if (bikes.isNotEmpty)
          ...bikes.take(2).map((bike) => _CompactRow(
                icon: Icons.pedal_bike_outlined,
                title:
                    '${bike['brand'] ?? bike['brand_name'] ?? ''} ${bike['model'] ?? bike['model_name'] ?? 'Bicicleta'}'
                        .trim(),
                subtitle: 'Ficha de bicicleta guardada',
              )),
      ],
    );
  }
}

class _CompactRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? trailing;

  const _CompactRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF102A43), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isEmpty ? 'Registro' : title,
                  style: const TextStyle(
                    color: Color(0xFF18212F),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            Text(
              trailing!,
              style: const TextStyle(
                color: Color(0xFF102A43),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyInlineState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _EmptyInlineState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF102A43), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF18212F),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
