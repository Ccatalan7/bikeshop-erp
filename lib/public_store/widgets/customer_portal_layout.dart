import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/customer_account_service.dart';
import 'customer_chat_panel.dart';
import 'public_store_layout.dart';

class CustomerPortalLayout extends StatelessWidget {
  final String title;
  final Widget child;
  final bool showBackButton;
  final Widget? headerAction;
  final bool overrideLayout;
  final Widget? rightSidebarContent;
  final bool enableContentScrolling;
  final bool showHeader;
  final String? backPath;

  const CustomerPortalLayout({
    super.key,
    required this.title,
    required this.child,
    this.showBackButton = true,
    this.headerAction,
    this.overrideLayout = false,
    this.backPath,
    this.rightSidebarContent,
    this.enableContentScrolling = true,
    this.showHeader = true,
  });

  @override
  Widget build(BuildContext context) {
    if (overrideLayout) {
      return child;
    }

    final accountService = context.watch<CustomerAccountService>();
    final profile = accountService.customerProfile;
    final fullName = (profile?['name'] ?? 'Mi cuenta').toString();
    final firstName = fullName.trim().isEmpty
        ? 'Cliente'
        : fullName.trim().split(RegExp(r'\s+')).first;
    final email = (profile?['email'] ?? '').toString();
    final initial = firstName.isNotEmpty ? firstName[0].toUpperCase() : 'C';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 980;
        final horizontalPadding = isDesktop ? 32.0 : 16.0;

        final content = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: isDesktop
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 248,
                      child: _PortalNavigation(
                        initial: initial,
                        name: fullName,
                        email: email,
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: _PortalContentSurface(
                        title: title,
                        showBackButton: showBackButton,
                        headerAction: headerAction,
                        backPath: backPath,
                        enableContentScrolling: enableContentScrolling,
                        showHeader: showHeader,
                        child: child,
                      ),
                    ),
                    const SizedBox(width: 24),
                    SizedBox(
                      width: 304,
                      child: rightSidebarContent ??
                          _PortalSupportRail(
                            ordersCount: accountService.orders.length,
                            addressesCount: accountService.addresses.length,
                            bikesCount: accountService.bikes.length,
                          ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MobileAccountHeader(
                      initial: initial,
                      name: fullName,
                      email: email,
                    ),
                    const SizedBox(height: 16),
                    _MobilePortalShortcuts(currentTitle: title),
                    const SizedBox(height: 16),
                    _PortalContentSurface(
                      title: title,
                      showBackButton: showBackButton,
                      headerAction: headerAction,
                      backPath: backPath,
                      enableContentScrolling: enableContentScrolling,
                      showHeader: showHeader,
                      child: child,
                    ),
                  ],
                ),
        );

        return Container(
          width: double.infinity,
          color: const Color(0xFFF6F7F8),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              isDesktop ? 28 : 18,
              horizontalPadding,
              48,
            ),
            child: Center(child: content),
          ),
        );
      },
    );
  }
}

class _PortalContentSurface extends StatelessWidget {
  final String title;
  final Widget child;
  final bool showBackButton;
  final Widget? headerAction;
  final String? backPath;
  final bool enableContentScrolling;
  final bool showHeader;

  const _PortalContentSurface({
    required this.title,
    required this.child,
    required this.showBackButton,
    required this.headerAction,
    required this.backPath,
    required this.enableContentScrolling,
    required this.showHeader,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E4EA)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showHeader)
            Container(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFFE6E9EE)),
                ),
              ),
              child: Row(
                children: [
                  if (showBackButton) ...[
                    IconButton.filledTonal(
                      onPressed: () => _goBack(context, backPath),
                      icon: const Icon(Icons.arrow_back, size: 20),
                      tooltip: 'Volver',
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFF2F4F7),
                        foregroundColor: const Color(0xFF1F2933),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF18212F),
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _subtitleFor(title),
                          style: const TextStyle(
                            color: Color(0xFF667085),
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (headerAction != null) ...[
                    const SizedBox(width: 12),
                    headerAction!,
                  ],
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: child,
          ),
        ],
      ),
    );
  }

  static void _goBack(BuildContext context, String? backPath) {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
      return;
    }
    _navigateWithinPortal(context, backPath ?? '/cuenta');
  }

  static String _subtitleFor(String title) {
    final normalized = title.toLowerCase();
    if (normalized.contains('perfil')) {
      return 'Administra tus datos personales y la seguridad de tu cuenta.';
    }
    if (normalized.contains('direcciones')) {
      return 'Guarda tus direcciones para comprar más rápido.';
    }
    if (normalized.contains('pedido')) {
      return 'Revisa tus compras, pagos y el estado de cada pedido.';
    }
    if (normalized.contains('bicicleta')) {
      return 'Ten tus bicicletas y sus servicios siempre a mano.';
    }
    if (normalized.contains('servicio')) {
      return 'Consulta el historial y avance de tus trabajos de taller.';
    }
    if (normalized.contains('soporte') || normalized.contains('chat')) {
      return 'Habla con el equipo de Viñabike cuando necesites ayuda.';
    }
    return 'Compra, revisa tus datos y vuelve a lo importante sin fricción.';
  }
}

void _navigateWithinPortal(BuildContext context, String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return;

  final target = trimmed.startsWith('/tienda/cuenta')
      ? trimmed.substring('/tienda'.length)
      : trimmed;
  final current = GoRouterState.of(context).uri.toString();
  if (current == target) return;

  context.go(target);
}

class _PortalNavigation extends StatelessWidget {
  final String initial;
  final String name;
  final String email;

  const _PortalNavigation({
    required this.initial,
    required this.name,
    required this.email,
  });

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE0E4EA)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: const Color(0xFF102A43),
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF18212F),
                          ),
                        ),
                        if (email.isNotEmpty)
                          Text(
                            email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF667085),
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE0E4EA)),
          ),
          child: Column(
            children: _PortalDestination.items
                .map(
                  (item) => _PortalNavItem(
                    item: item,
                    isSelected: _isSelected(location, item.path),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 14),
        _PortalNavTextButton(
          icon: Icons.logout,
          label: 'Cerrar sesión',
          onTap: () async {
            await context.read<CustomerAccountService>().signOut();
            if (context.mounted) {
              PublicStoreLayout.navigateToHref(context, '/');
            }
          },
        ),
      ],
    );
  }

  bool _isSelected(String location, String path) {
    if (path == '/cuenta') {
      return location == '/cuenta' || location == '/tienda/cuenta';
    }
    return location == path || location == '/tienda$path';
  }
}

class _MobileAccountHeader extends StatelessWidget {
  final String initial;
  final String name;
  final String email;

  const _MobileAccountHeader({
    required this.initial,
    required this.name,
    required this.email,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E4EA)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFF102A43),
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF18212F),
                  ),
                ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Menú de cuenta',
            icon: const Icon(Icons.more_horiz),
            onSelected: (value) async {
              if (value == 'logout') {
                await context.read<CustomerAccountService>().signOut();
                if (context.mounted) {
                  PublicStoreLayout.navigateToHref(context, '/');
                }
                return;
              }
              _navigateWithinPortal(context, value);
            },
            itemBuilder: (context) => [
              for (final item in _PortalDestination.items)
                PopupMenuItem(
                  value: item.path,
                  child: Text(item.label),
                ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Text('Cerrar sesión'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MobilePortalShortcuts extends StatelessWidget {
  final String currentTitle;

  const _MobilePortalShortcuts({required this.currentTitle});

  @override
  Widget build(BuildContext context) {
    final currentPath = GoRouterState.of(context).uri.path;
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _PortalDestination.items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = _PortalDestination.items[index];
          final selected = item.path == '/cuenta'
              ? currentPath == '/cuenta' || currentPath == '/tienda/cuenta'
              : currentPath == item.path ||
                  currentPath == '/tienda${item.path}';
          return ChoiceChip(
            label: Text(item.shortLabel),
            avatar: Icon(item.icon, size: 16),
            selected: selected,
            showCheckmark: false,
            onSelected: (_) => _navigateWithinPortal(context, item.path),
            labelStyle: TextStyle(
              color: selected ? Colors.white : const Color(0xFF344054),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
            selectedColor: const Color(0xFF102A43),
            backgroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFFE0E4EA)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          );
        },
      ),
    );
  }
}

class _PortalSupportRail extends StatelessWidget {
  final int ordersCount;
  final int addressesCount;
  final int bikesCount;

  const _PortalSupportRail({
    required this.ordersCount,
    required this.addressesCount,
    required this.bikesCount,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE0E4EA)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tu cuenta al día',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF18212F),
                ),
              ),
              const SizedBox(height: 12),
              _MiniMetric(label: 'Pedidos', value: ordersCount.toString()),
              _MiniMetric(
                label: 'Direcciones',
                value: addressesCount.toString(),
              ),
              _MiniMetric(label: 'Bicicletas', value: bikesCount.toString()),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE0E4EA)),
          ),
          clipBehavior: Clip.antiAlias,
          child: const SizedBox(
            height: 330,
            child: CustomerChatPanel(compactMode: true),
          ),
        ),
      ],
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;

  const _MiniMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF102A43),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF667085)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PortalDestination {
  final String label;
  final String shortLabel;
  final String path;
  final IconData icon;

  const _PortalDestination({
    required this.label,
    required this.shortLabel,
    required this.path,
    required this.icon,
  });

  static const items = [
    _PortalDestination(
      label: 'Resumen',
      shortLabel: 'Resumen',
      path: '/cuenta',
      icon: Icons.dashboard_outlined,
    ),
    _PortalDestination(
      label: 'Perfil y seguridad',
      shortLabel: 'Perfil',
      path: '/cuenta/perfil',
      icon: Icons.person_outline,
    ),
    _PortalDestination(
      label: 'Pedidos',
      shortLabel: 'Pedidos',
      path: '/cuenta/pedidos',
      icon: Icons.receipt_long_outlined,
    ),
    _PortalDestination(
      label: 'Direcciones',
      shortLabel: 'Direcciones',
      path: '/cuenta/direcciones',
      icon: Icons.location_on_outlined,
    ),
    _PortalDestination(
      label: 'Bicicletas',
      shortLabel: 'Bicis',
      path: '/cuenta/bicicletas',
      icon: Icons.pedal_bike_outlined,
    ),
    _PortalDestination(
      label: 'Servicios de taller',
      shortLabel: 'Taller',
      path: '/cuenta/servicios',
      icon: Icons.build_outlined,
    ),
    _PortalDestination(
      label: 'Soporte',
      shortLabel: 'Soporte',
      path: '/cuenta/chats',
      icon: Icons.chat_bubble_outline,
    ),
  ];
}

class _PortalNavItem extends StatelessWidget {
  final _PortalDestination item;
  final bool isSelected;

  const _PortalNavItem({required this.item, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: isSelected ? const Color(0xFFEFF6FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _navigateWithinPortal(context, item.path),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: 20,
                  color: isSelected
                      ? const Color(0xFF102A43)
                      : const Color(0xFF667085),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      color: isSelected
                          ? const Color(0xFF102A43)
                          : const Color(0xFF344054),
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 13,
                    ),
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

class _PortalNavTextButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PortalNavTextButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFFB42318),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
