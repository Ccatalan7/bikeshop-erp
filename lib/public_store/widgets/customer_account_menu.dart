import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/customer_portal_presentation.dart';
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
      final isLightHeader = effectiveTextColor.computeLuminance() > 0.7;
      final foregroundColor =
          isLightHeader ? Colors.white : PublicStoreTheme.textPrimary;
      final backgroundColor = isLightHeader
          ? Colors.black.withValues(alpha: 0.18)
          : Colors.white.withValues(alpha: 0.92);
      final borderColor = isLightHeader
          ? Colors.white.withValues(alpha: 0.36)
          : PublicStoreTheme.border.withValues(alpha: 0.9);
      final overlayColor = isLightHeader
          ? Colors.white.withValues(alpha: 0.08)
          : PublicStoreTheme.textPrimary.withValues(alpha: 0.05);

      return OutlinedButton.icon(
        onPressed: () {
          PublicStoreLayout.navigateToHref(context, '/tienda/cuenta/login');
        },
        icon: const Icon(Icons.person_outline, size: 17),
        label: const Text('INICIAR SESIÓN'),
        style: OutlinedButton.styleFrom(
          foregroundColor: foregroundColor,
          backgroundColor: backgroundColor,
          side: BorderSide(color: borderColor, width: 1.2),
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 18 : 14,
            vertical: isMobile ? 11 : 9,
          ),
          minimumSize: isMobile ? const Size(double.infinity, 48) : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.15,
          ),
        ).copyWith(
          overlayColor: WidgetStatePropertyAll(overlayColor),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      );
    }

    final profile = accountService.customerProfile;
    // «Usuario» y «Cliente» son relleno guardado: no se saluda con eso.
    final firstName = customerFirstName(profile);
    final userName = firstName ?? 'Mi cuenta';
    final email = (profile?['email'] ?? '').toString().trim();
    final initialSource = firstName ?? email;
    final userInitial = initialSource.isNotEmpty
        ? initialSource.characters.first.toUpperCase()
        : '·';

    if (isMobile) {
      return Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor:
                  PublicStoreTheme.primaryBlue.withValues(alpha: 0.1),
              child: Text(
                userInitial,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(userName,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: email.isEmpty ? null : Text(email),
          ),
          for (final item in _items)
            _buildMobileMenuItem(context, item.icon, item.label, item.path),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Cerrar sesión'),
            onTap: () async {
              await PublicStoreLayout.signOutCustomer(
                context,
                accountService,
              );
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
            radius: 17,
            backgroundColor: textColor?.withValues(alpha: 0.1) ??
                PublicStoreTheme.primaryBlue.withValues(alpha: 0.1),
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
              if (firstName != null)
                Text(
                  'Mi cuenta',
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
        for (final item in _items) ...[
          PopupMenuItem(
            value: item.path,
            child: Row(
              children: [
                Icon(item.icon, size: 18),
                const SizedBox(width: 12),
                Text(item.label),
              ],
            ),
          ),
          if (item.path == '/tienda/cuenta') const PopupMenuDivider(),
        ],
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout, size: 18),
              SizedBox(width: 12),
              Text('Cerrar sesión'),
            ],
          ),
        ),
      ],
      onSelected: (value) async {
        if (value == 'logout') {
          await PublicStoreLayout.signOutCustomer(context, accountService);
          return;
        }
        PublicStoreLayout.navigateToHref(context, value);
      },
    );
  }

  /// Las mismas secciones, con las mismas palabras, que el menú del portal.
  static const _items = [
    (icon: Icons.home_outlined, label: 'Resumen', path: '/tienda/cuenta'),
    (
      icon: Icons.receipt_long_outlined,
      label: 'Pedidos',
      path: '/tienda/cuenta/pedidos'
    ),
    (
      icon: Icons.build_outlined,
      label: 'Taller',
      path: '/tienda/cuenta/servicios'
    ),
    (
      icon: Icons.pedal_bike_outlined,
      label: 'Bicicletas',
      path: '/tienda/cuenta/bicicletas'
    ),
    (
      icon: Icons.chat_bubble_outline,
      label: 'Soporte',
      path: '/tienda/cuenta/chats'
    ),
    (
      icon: Icons.person_outline,
      label: 'Perfil y seguridad',
      path: '/tienda/cuenta/perfil'
    ),
    (
      icon: Icons.location_on_outlined,
      label: 'Direcciones',
      path: '/tienda/cuenta/direcciones'
    ),
  ];

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
