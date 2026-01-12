import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/customer_account_service.dart';
import '../theme/public_store_theme.dart';
import 'public_store_layout.dart';

/// Account menu widget for the public store header
/// Shows login button when not authenticated, or account menu when logged in
class CustomerAccountMenu extends StatelessWidget {
  final Color? textColor;
  final bool isMobile;

  const CustomerAccountMenu({
    super.key,
    this.textColor,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context) {
    final accountService = context.watch<CustomerAccountService>();
    final effectiveTextColor = textColor ?? Colors.black87;

    if (!accountService.isAuthenticated) {
      return FilledButton.icon(
        onPressed: () {
          PublicStoreLayout.navigateToHref(context, '/tienda/cuenta/login');
        },
        icon: const Icon(Icons.person_outline, size: 18),
        label: const Text('INICIAR SESIÓN'),
        style: FilledButton.styleFrom(
          backgroundColor: PublicStoreTheme.primaryBlue,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          minimumSize: isMobile ? const Size(double.infinity, 48) : null,
        ),
      );
    }

    final profile = accountService.customerProfile;
    final userName = profile?['name'] as String? ?? 'Usuario';
    final userInitial = userName.isNotEmpty ? userName[0].toUpperCase() : '?';

    if (isMobile) {
      return Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: PublicStoreTheme.primaryBlue.withOpacity(0.1),
              child: Text(
                userInitial,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(userName,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Mi Cuenta'),
          ),
          _buildMobileMenuItem(context, Icons.dashboard_outlined,
              'Panel de cuenta', '/tienda/cuenta'),
          _buildMobileMenuItem(context, Icons.shopping_bag_outlined,
              'Mis pedidos', '/tienda/cuenta/pedidos'),
          _buildMobileMenuItem(context, Icons.location_on_outlined,
              'Mis direcciones', '/tienda/cuenta/direcciones'),
          _buildMobileMenuItem(context, Icons.person_outline, 'Mi perfil',
              '/tienda/cuenta/perfil'),
          _buildMobileMenuItem(context, Icons.chat_bubble_outline,
              'Ayuda y Soporte', '/tienda/cuenta/chats'),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Cerrar sesión',
                style: TextStyle(color: Colors.red)),
            onTap: () async {
              await accountService.signOut();
              if (context.mounted) {
                PublicStoreLayout.navigateToHref(context, '/');
              }
            },
          ),
        ],
      );
    }

    return PopupMenuButton<String>(
      offset: const Offset(0, 50),
      tooltip: 'Mi cuenta',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: textColor?.withValues(alpha: 0.1) ??
                PublicStoreTheme.primaryBlue.withOpacity(0.1),
            child: Text(
              userInitial,
              style: TextStyle(
                color: textColor ?? PublicStoreTheme.primaryBlue,
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
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: effectiveTextColor,
                ),
              ),
              Text(
                'Mi Cuenta',
                style: TextStyle(
                  fontSize: 11,
                  color: effectiveTextColor.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          Icon(Icons.arrow_drop_down, color: effectiveTextColor),
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
        PopupMenuItem(
          value: 'chat',
          child: Row(
            children: const [
              Icon(Icons.chat_bubble_outline, size: 18),
              SizedBox(width: 12),
              Text('Ayuda y Soporte'),
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
            PublicStoreLayout.navigateToHref(context, '/tienda/cuenta');
            break;
          case 'orders':
            PublicStoreLayout.navigateToHref(
                context, '/tienda/cuenta/pedidos');
            break;
          case 'addresses':
            PublicStoreLayout.navigateToHref(
                context, '/tienda/cuenta/direcciones');
            break;
          case 'profile':
            PublicStoreLayout.navigateToHref(
                context, '/tienda/cuenta/perfil');
            break;
          case 'chat':
            PublicStoreLayout.navigateToHref(context, '/tienda/cuenta/chats');
            break;
          case 'logout':
            await accountService.signOut();
            if (context.mounted) {
              PublicStoreLayout.navigateToHref(context, '/');
            }
            break;
        }
      },
    );
  }

  Widget _buildMobileMenuItem(
      BuildContext context, IconData icon, String label, String path) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () {
        PublicStoreLayout.navigateToHref(context, path);
      },
    );
  }
}
