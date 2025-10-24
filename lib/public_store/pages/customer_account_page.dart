import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/customer_account_service.dart';
import '../theme/public_store_theme.dart';
import '../../shared/utils/chilean_utils.dart';

class CustomerAccountPage extends StatelessWidget {
  const CustomerAccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    final accountService = context.watch<CustomerAccountService>();

    if (!accountService.isAuthenticated) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.account_circle_outlined, size: 64),
              const SizedBox(height: 16),
              const Text('Debes iniciar sesión para ver tu cuenta'),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go('/tienda/login'),
                child: const Text('INICIAR SESIÓN'),
              ),
            ],
          ),
        ),
      );
    }

    final profile = accountService.customerProfile;
    final name = profile?['name'] ?? 'Usuario';
    final email = profile?['email'] ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Cuenta'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await accountService.signOut();
              if (context.mounted) {
                context.go('/tienda');
              }
            },
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Container(
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
                              style: TextStyle(
                                color: PublicStoreTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () {
                          context.go('/tienda/cuenta/perfil');
                        },
                        tooltip: 'Editar perfil',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Quick Actions
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1.5,
                children: [
                  _QuickActionCard(
                    icon: Icons.receipt_long_outlined,
                    title: 'Mis Pedidos',
                    subtitle: '${accountService.orders.length} pedidos',
                    onTap: () => context.go('/tienda/cuenta/pedidos'),
                  ),
                  _QuickActionCard(
                    icon: Icons.location_on_outlined,
                    title: 'Direcciones',
                    subtitle: '${accountService.addresses.length} guardadas',
                    onTap: () => context.go('/tienda/cuenta/direcciones'),
                  ),
                  _QuickActionCard(
                    icon: Icons.person_outline,
                    title: 'Perfil',
                    subtitle: 'Datos personales',
                    onTap: () => context.go('/tienda/cuenta/perfil'),
                  ),
                  _QuickActionCard(
                    icon: Icons.lock_outline,
                    title: 'Seguridad',
                    subtitle: 'Contraseña',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Funcionalidad próximamente'),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Recent Orders
              if (accountService.orders.isNotEmpty) ...[
                Text(
                  'Pedidos Recientes',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
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
                      onTap: () {
                        context.go('/tienda/pedido/${order.id}');
                      },
                    ),
                  );
                }).toList(),
                TextButton(
                  onPressed: () => context.go('/tienda/cuenta/pedidos'),
                  child: const Text('VER TODOS LOS PEDIDOS'),
                ),
              ],
            ],
          ),
        ),
      ),
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
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: PublicStoreTheme.primaryBlue),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: PublicStoreTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
