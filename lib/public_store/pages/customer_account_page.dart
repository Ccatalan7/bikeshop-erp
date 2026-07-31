import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/customer_account_service.dart';
import '../providers/public_store_tenant_provider.dart';
import '../theme/public_store_theme.dart';
import '../widgets/public_store_layout.dart';
import '../../shared/utils/chilean_utils.dart';
import '../../shared/widgets/safe_layout_builder.dart';

class CustomerAccountPage extends StatefulWidget {
  const CustomerAccountPage({super.key});

  @override
  State<CustomerAccountPage> createState() => _CustomerAccountPageState();
}

class _CustomerAccountPageState extends State<CustomerAccountPage>
    with AutomaticKeepAliveClientMixin {
  // Keep this page alive in memory to prevent reloading on navigation
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Load bikes and service history when page loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final accountService = context.read<CustomerAccountService>();
      // CRITICAL: Set tenant_id for multi-tenant queries
      final tenantProvider = context.read<PublicStoreTenantProvider>();
      accountService.setTenantId(tenantProvider.tenantId);

      if (accountService.isAuthenticated) {
        accountService.loadBikes();
        accountService.loadServiceHistory();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final accountService = context.watch<CustomerAccountService>();

    if (!accountService.isAuthenticated) {
      // Not authenticated - no Scaffold (wrapped by layout)
      return Column(
        children: [
          // Header bar
          Container(
            color: Theme.of(context).primaryColor,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top,
              left: 16,
              right: 16,
              bottom: 12,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Mi Cuenta',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Content
          const SizedBox(height: 48),
          const Icon(Icons.account_circle_outlined, size: 64),
          const SizedBox(height: 16),
          const Text('Debes iniciar sesión para ver tu cuenta'),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () =>
                PublicStoreLayout.navigateToHref(context, '/cuenta/login'),
            child: const Text('INICIAR SESIÓN'),
          ),
          const SizedBox(height: 48),
        ],
      );
    }

    final profile = accountService.customerProfile;
    final name = profile?['name'] ?? 'Usuario';
    final email = profile?['email'] ?? '';

    // Authenticated - no Scaffold (wrapped by layout)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header bar
        Container(
          color: Theme.of(context).primaryColor,
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top,
            left: 16,
            right: 8,
            bottom: 12,
          ),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Mi Cuenta',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white),
                onPressed: () async {
                  await PublicStoreLayout.signOutCustomer(
                    context,
                    accountService,
                  );
                },
                tooltip: 'Cerrar sesión',
              ),
            ],
          ),
        ),
        // Content
        Container(
          constraints: const BoxConstraints(maxWidth: 1000),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User Header
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: PublicStoreTheme.primaryBlue,
                        child: Text(
                          name[0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 32,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              email,
                              style: const TextStyle(
                                color: PublicStoreTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => PublicStoreLayout.navigateToHref(
                          context,
                          '/cuenta/perfil',
                        ),
                        tooltip: 'Editar perfil',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Quick Actions - Responsive Grid
              MediaQueryLayoutBuilder(
                builder: (context, constraints) {
                  // 3 columns on desktop, 2 on mobile
                  final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
                  final spacing = constraints.maxWidth > 600 ? 16.0 : 12.0;

                  return GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: spacing,
                    crossAxisSpacing: spacing,
                    childAspectRatio: 1.4, // Slightly wider than tall
                    children: [
                      _QuickActionCard(
                        icon: Icons.receipt_long_outlined,
                        title: 'Mis Pedidos',
                        subtitle: '${accountService.orders.length} pedidos',
                        onTap: () => PublicStoreLayout.navigateToHref(
                          context,
                          '/cuenta/pedidos',
                        ),
                      ),
                      _QuickActionCard(
                        icon: Icons.pedal_bike_outlined,
                        title: 'Mis Bicicletas',
                        subtitle: '${accountService.bikes.length} registradas',
                        onTap: () => PublicStoreLayout.navigateToHref(
                          context,
                          '/cuenta/bicicletas',
                        ),
                      ),
                      _QuickActionCard(
                        icon: Icons.build_outlined,
                        title: 'Servicios',
                        subtitle: accountService.activeServicesCount > 0
                            ? '${accountService.activeServicesCount} activo${accountService.activeServicesCount > 1 ? 's' : ''}'
                            : 'Historial',
                        badge:
                            accountService.servicesAwaitingApproval.isNotEmpty
                                ? accountService.servicesAwaitingApproval.length
                                : null,
                        onTap: () => PublicStoreLayout.navigateToHref(
                          context,
                          '/cuenta/servicios',
                        ),
                      ),
                      _QuickActionCard(
                        icon: Icons.location_on_outlined,
                        title: 'Direcciones',
                        subtitle:
                            '${accountService.addresses.length} guardadas',
                        onTap: () => PublicStoreLayout.navigateToHref(
                          context,
                          '/cuenta/direcciones',
                        ),
                      ),
                      _QuickActionCard(
                        icon: Icons.person_outline,
                        title: 'Perfil',
                        subtitle: 'Datos personales',
                        onTap: () => PublicStoreLayout.navigateToHref(
                          context,
                          '/cuenta/perfil',
                        ),
                      ),
                      _QuickActionCard(
                        icon: Icons.chat_bubble_outline,
                        title: 'Ayuda',
                        subtitle: 'Mensajes y Soporte',
                        onTap: () => PublicStoreLayout.navigateToHref(
                          context,
                          '/tienda/cuenta/chats',
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),

              // Services Awaiting Approval Alert
              if (accountService.servicesAwaitingApproval.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.pending_actions, color: Colors.amber[800]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Tienes ${accountService.servicesAwaitingApproval.length} servicio${accountService.servicesAwaitingApproval.length > 1 ? 's' : ''} esperando tu aprobación',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.amber[900],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonal(
                          onPressed: () => PublicStoreLayout.navigateToHref(
                            context,
                            '/cuenta/servicios',
                          ),
                          child: const Text('VER PRESUPUESTOS'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Active Services Section
              if (accountService.activeServicesCount > 0) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Servicios Activos',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    TextButton(
                      onPressed: () => PublicStoreLayout.navigateToHref(
                        context,
                        '/cuenta/servicios',
                      ),
                      child: const Text('VER TODOS'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...accountService.serviceHistory
                    .where((s) =>
                        !['ENTREGADO', 'CANCELADO'].contains(s['status']))
                    .take(2)
                    .map((service) {
                  final bikeBrand = service['bike_brand'] ?? '';
                  final bikeModel = service['bike_model'] ?? '';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            _getServiceStatusColor(service['status']),
                        child: Icon(
                          _getServiceStatusIcon(service['status']),
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      title: Text('$bikeBrand $bikeModel'.trim()),
                      subtitle: Text(
                        '${service['job_number']} • ${_getServiceStatusText(service['status'])}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => PublicStoreLayout.navigateToHref(
                        context,
                        '/cuenta/servicios',
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 24),
              ],

              // Recent Orders
              if (accountService.orders.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Pedidos Recientes',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    TextButton(
                      onPressed: () => PublicStoreLayout.navigateToHref(
                        context,
                        '/cuenta/pedidos',
                      ),
                      child: const Text('VER TODOS'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...accountService.orders.take(3).map((order) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _getStatusColor(order.status),
                        child: Icon(
                          _getStatusIcon(order.status),
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      title: Text('Pedido #${order.orderNumber}'),
                      subtitle: Text(
                        '${ChileanUtils.formatCurrency(order.total)} • ${_getStatusText(order.status)}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => PublicStoreLayout.navigateToHref(
                        context,
                        '/pedido/${order.id}',
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'delivered':
        return Colors.green;
      case 'shipped':
        return Colors.blue;
      case 'processing':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'delivered':
        return Icons.check_circle;
      case 'shipped':
        return Icons.local_shipping;
      case 'processing':
        return Icons.sync;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.schedule;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Pendiente';
      case 'confirmed':
        return 'Confirmado';
      case 'processing':
        return 'En Proceso';
      case 'shipped':
        return 'Enviado';
      case 'delivered':
        return 'Entregado';
      case 'cancelled':
        return 'Cancelado';
      default:
        return status;
    }
  }

  Color _getServiceStatusColor(String? status) {
    switch (status) {
      case 'FINALIZADO':
        return Colors.green;
      case 'EN_CURSO':
        return Colors.blue;
      case 'ESPERANDO_APROBACION':
        return Colors.amber;
      case 'ESPERANDO_REPUESTOS':
        return Colors.orange;
      case 'DIAGNOSTICO':
        return Colors.purple;
      case 'CANCELADO':
        return Colors.red;
      case 'ENTREGADO':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  IconData _getServiceStatusIcon(String? status) {
    switch (status) {
      case 'FINALIZADO':
        return Icons.check_circle;
      case 'EN_CURSO':
        return Icons.build;
      case 'ESPERANDO_APROBACION':
        return Icons.pending_actions;
      case 'ESPERANDO_REPUESTOS':
        return Icons.inventory_2;
      case 'DIAGNOSTICO':
        return Icons.search;
      case 'CANCELADO':
        return Icons.cancel;
      case 'ENTREGADO':
        return Icons.done_all;
      default:
        return Icons.schedule;
    }
  }

  String _getServiceStatusText(String? status) {
    switch (status) {
      case 'PENDIENTE':
        return 'Pendiente';
      case 'DIAGNOSTICO':
        return 'En diagnóstico';
      case 'ESPERANDO_APROBACION':
        return 'Esperando aprobación';
      case 'ESPERANDO_REPUESTOS':
        return 'Esperando repuestos';
      case 'EN_CURSO':
        return 'En trabajo';
      case 'FINALIZADO':
        return 'Listo para retiro';
      case 'ENTREGADO':
        return 'Entregado';
      case 'CANCELADO':
        return 'Cancelado';
      default:
        return status ?? 'Desconocido';
    }
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final int? badge;

  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color:
                          PublicStoreTheme.primaryBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon,
                        size: 24, color: PublicStoreTheme.primaryBlue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: PublicStoreTheme.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      size: 20, color: Colors.grey.shade400),
                ],
              ),
            ),
            if (badge != null && badge! > 0)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badge.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
