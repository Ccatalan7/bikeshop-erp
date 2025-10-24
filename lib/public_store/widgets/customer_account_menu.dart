import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/customer_account_service.dart';
import '../theme/public_store_theme.dart';

/// Account menu widget for the public store header
/// Shows login button when not authenticated, or account menu when logged in
class CustomerAccountMenu extends StatelessWidget {
  const CustomerAccountMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final accountService = context.watch<CustomerAccountService>();

    if (!accountService.isAuthenticated) {
      return FilledButton.icon(
        onPressed: () => context.go('/tienda/cuenta/login'),
        icon: const Icon(Icons.person_outline, size: 18),
        label: const Text('INICIAR SESIÓN'),
        style: FilledButton.styleFrom(
          backgroundColor: PublicStoreTheme.primaryBlue,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      );
    }

    final profile = accountService.customerProfile;
    final userName = profile?['name'] as String? ?? 'Usuario';
    final userInitial = userName.isNotEmpty ? userName[0].toUpperCase() : '?';

    return PopupMenuButton<String>(
      offset: const Offset(0, 50),
      tooltip: 'Mi cuenta',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: PublicStoreTheme.primaryBlue.withOpacity(0.1),
            child: Text(
              userInitial,
              style: const TextStyle(
                color: PublicStoreTheme.primaryBlue,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                userName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Text(
                'Mi Cuenta',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'account',
          child: Row(
            children: const [
              Icon(Icons.dashboard_outlined, size: 18),
              SizedBox(width: 12),
              Text('Panel de cuenta'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'orders',
          child: Row(
            children: const [
              Icon(Icons.shopping_bag_outlined, size: 18),
              SizedBox(width: 12),
              Text('Mis pedidos'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'addresses',
          child: Row(
            children: const [
              Icon(Icons.location_on_outlined, size: 18),
              SizedBox(width: 12),
              Text('Mis direcciones'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'profile',
          child: Row(
            children: const [
              Icon(Icons.person_outline, size: 18),
              SizedBox(width: 12),
              Text('Mi perfil'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'logout',
          child: Row(
            children: const [
              Icon(Icons.logout, size: 18, color: Colors.red),
              SizedBox(width: 12),
              Text('Cerrar sesión', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
      onSelected: (value) async {
        switch (value) {
          case 'account':
            context.go('/tienda/cuenta');
            break;
          case 'orders':
            context.go('/tienda/cuenta/pedidos');
            break;
          case 'addresses':
            context.go('/tienda/cuenta/direcciones');
            break;
          case 'profile':
            context.go('/tienda/cuenta/perfil');
            break;
          case 'logout':
            await accountService.signOut();
            if (context.mounted) context.go('/');
            break;
        }
      },
    );
  }
}
