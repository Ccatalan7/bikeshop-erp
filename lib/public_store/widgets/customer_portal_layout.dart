import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/customer_portal_presentation.dart';
import '../services/customer_account_service.dart';
import 'customer_portal_style.dart';
import 'public_store_layout.dart';

/// Marco del portal de clientes (`/cuenta/**`).
///
/// En ancho: el menú de la cuenta a la izquierda, fijo, y el contenido en una
/// columna que se desplaza sola. Las rutas del portal se montan sin el scroll
/// de página de la tienda (`_buildPageNoScroll`), así el menú no se va con el
/// contenido. En teléfono: una barra con la cuenta y las secciones en
/// pestañas, fija, y el contenido debajo.
///
/// El chat vive en «Soporte» y en el botón flotante de la tienda; el marco ya
/// no lleva un segundo chat ni las cifras repetidas en una columna derecha.
/// Una página que necesita esa columna (el detalle de una conversación) la
/// pasa en [rightSidebarContent].
class CustomerPortalLayout extends StatelessWidget {
  final String title;
  final String? subtitle;
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
    this.subtitle,
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
    final accountService = context.watch<CustomerAccountService>();
    if (!accountService.isAuthenticated) {
      return _CustomerPortalAuthBoundary(accountService: accountService);
    }

    if (overrideLayout) {
      return child;
    }

    final profile = accountService.customerProfile;
    final identity = _PortalIdentity(
      name: customerFirstName(profile) == null
          ? 'Tu cuenta'
          : (profile?['name'] ?? '').toString().trim(),
      email: (profile?['email'] ?? '').toString().trim(),
    );
    final style = PortalStyle.of(context);

    return ColoredBox(
      color: style.canvas,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= PortalStyle.wideBreakpoint;
          final bounded = constraints.hasBoundedHeight;
          final content = _PortalContent(
            title: title,
            subtitle: subtitle,
            showHeader: showHeader,
            headerAction: headerAction,
            showBackButton: showBackButton,
            backPath: backPath,
            compact: !wide,
            child: child,
          );

          if (wide) {
            final scrollingContent = SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(0, 36, 0, 72),
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: PortalStyle.contentMaxWidth,
                  ),
                  child: content,
                ),
              ),
            );
            final row = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: PortalStyle.navWidth,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 36),
                    child: _PortalNavigation(identity: identity),
                  ),
                ),
                const SizedBox(width: 48),
                Expanded(
                  child: bounded
                      ? scrollingContent
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(0, 36, 0, 72),
                          child: content,
                        ),
                ),
                if (rightSidebarContent != null) ...[
                  const SizedBox(width: 32),
                  SizedBox(
                    width: 304,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 36),
                      child: rightSidebarContent,
                    ),
                  ),
                ],
              ],
            );
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: rightSidebarContent == null ? 1120 : 1360,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: row,
                ),
              ),
            );
          }

          final bar = _CompactAccountBar(identity: identity);
          final body = Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 48),
            child: content,
          );
          if (!bounded) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [bar, body],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              bar,
              Expanded(child: SingleChildScrollView(child: body)),
            ],
          );
        },
      ),
    );
  }
}

class _PortalIdentity {
  const _PortalIdentity({required this.name, required this.email});

  final String name;
  final String email;

  String get initial {
    final source = name == 'Tu cuenta' && email.isNotEmpty ? email : name;
    return source.isEmpty ? '·' : source.characters.first.toUpperCase();
  }
}

class _CustomerPortalAuthBoundary extends StatelessWidget {
  const _CustomerPortalAuthBoundary({
    required this.accountService,
  });

  final CustomerAccountService accountService;

  @override
  Widget build(BuildContext context) {
    final isLoading = accountService.isCustomerMembershipLoading;
    final hasSession = accountService.hasAuthSession;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, minHeight: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                const CircularProgressIndicator()
              else
                Icon(
                  hasSession
                      ? Icons.verified_user_outlined
                      : Icons.lock_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.primary,
                ),
              const SizedBox(height: 18),
              Text(
                isLoading
                    ? 'Preparando tu cuenta…'
                    : hasSession
                        ? 'No pudimos abrir esta cuenta'
                        : 'Inicia sesión para continuar',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              Text(
                isLoading
                    ? 'Estamos verificando tu acceso para esta tienda.'
                    : hasSession
                        ? 'Tu sesión existe, pero no tiene una membresía válida para esta tienda.'
                        : 'Tu información se mostrará sólo después de verificar la membresía de esta tienda.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (!isLoading) ...[
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: hasSession
                      ? () => accountService.reloadCustomerMembership()
                      : () => PublicStoreLayout.navigateToHref(
                            context,
                            '/cuenta/login',
                          ),
                  child: Text(hasSession ? 'REINTENTAR' : 'INICIAR SESIÓN'),
                ),
                if (hasSession) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => PublicStoreLayout.signOutCustomer(
                      context,
                      accountService,
                      destination: '/cuenta/login',
                    ),
                    child: const Text('CERRAR ESTA SESIÓN'),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PortalContent extends StatelessWidget {
  const _PortalContent({
    required this.title,
    required this.subtitle,
    required this.showHeader,
    required this.headerAction,
    required this.showBackButton,
    required this.backPath,
    required this.compact,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final bool showHeader;
  final Widget? headerAction;
  final bool showBackButton;
  final String? backPath;
  final bool compact;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final uri = GoRouterState.of(context).uri;
    // Una sección del menú no lleva «Volver»: el menú ya está a la vista. Sí
    // lo lleva una vista filtrada o de detalle (`?bike_id=`, `backPath`).
    final isTopLevel =
        _PortalDestination.items.any((item) => _matches(uri.path, item.path)) &&
            uri.queryParameters.isEmpty &&
            backPath == null;
    final showBack = showBackButton && !isTopLevel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showBack) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _goBack(context, backPath),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Volver'),
              style: TextButton.styleFrom(
                foregroundColor: style.inkSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (showHeader) ...[
          PortalPageHeader(
            title: title,
            subtitle: subtitle,
            action: headerAction,
            compact: compact,
          ),
          SizedBox(height: compact ? 20 : 28),
        ],
        child,
      ],
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
}

void _navigateWithinPortal(BuildContext context, String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return;

  final target = trimmed.startsWith('/tienda/cuenta')
      ? trimmed.substring('/tienda'.length)
      : trimmed;
  final current = GoRouterState.of(context).uri.toString();
  if (current == target) return;

  PublicStoreLayout.navigateToHref(context, target);
}

bool _matches(String location, String path) {
  if (path == '/cuenta') {
    return location == '/cuenta' || location == '/tienda/cuenta';
  }
  return location == path || location == '/tienda$path';
}

Future<void> _signOut(BuildContext context) async {
  await context.read<CustomerAccountService>().signOut();
  if (context.mounted) {
    PublicStoreLayout.navigateToHref(context, '/');
  }
}

class _PortalAvatar extends StatelessWidget {
  const _PortalAvatar({required this.initial, required this.size});

  final String initial;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: style.accent, shape: BoxShape.circle),
      child: Text(
        initial,
        style: style.rowTitle.copyWith(
          color: style.onAccent,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PortalNavigation extends StatelessWidget {
  const _PortalNavigation({required this.identity});

  final _PortalIdentity identity;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final location = GoRouterState.of(context).uri.path;

    Widget group(String label, List<_PortalDestination> items) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Text(label.toUpperCase(), style: style.sectionLabel),
          ),
          for (final item in items)
            _PortalNavItem(
              item: item,
              isSelected: _matches(location, item.path),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _PortalAvatar(initial: identity.initial, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      identity.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style.rowTitle,
                    ),
                    if (identity.email.isNotEmpty)
                      Text(
                        identity.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style.rowMeta,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        group('Compras y taller', _PortalDestination.activity),
        const SizedBox(height: 20),
        group('Tu cuenta', _PortalDestination.account),
        const SizedBox(height: 20),
        Divider(height: 1, color: style.line),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _signOut(context),
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Cerrar sesión'),
            style: TextButton.styleFrom(
              foregroundColor: style.inkSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
      ],
    );
  }
}

class _PortalNavItem extends StatelessWidget {
  final _PortalDestination item;
  final bool isSelected;

  const _PortalNavItem({required this.item, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final color = isSelected ? style.accent : style.ink;
    return Semantics(
      selected: isSelected,
      button: true,
      child: Material(
        color: isSelected ? style.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _navigateWithinPortal(context, item.path),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  isSelected ? item.selectedIcon : item.icon,
                  size: 20,
                  color: isSelected ? style.accent : style.inkSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    style: style.rowTitle.copyWith(
                      color: color,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
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

class _CompactAccountBar extends StatelessWidget {
  const _CompactAccountBar({required this.identity});

  final _PortalIdentity identity;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final location = GoRouterState.of(context).uri.path;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.panel,
        border: Border(bottom: BorderSide(color: style.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                _PortalAvatar(initial: identity.initial, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    identity.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style.rowTitle,
                  ),
                ),
                TextButton(
                  onPressed: () => _signOut(context),
                  style: TextButton.styleFrom(
                    foregroundColor: style.inkSecondary,
                  ),
                  child: const Text('Salir'),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final item in _PortalDestination.items)
                  _CompactTab(
                    label: item.shortLabel,
                    selected: _matches(location, item.path),
                    onTap: () => _navigateWithinPortal(context, item.path),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactTab extends StatelessWidget {
  const _CompactTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? style.accent : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Text(
            label,
            style: style.rowTitle.copyWith(
              color: selected ? style.accent : style.inkSecondary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _PortalDestination {
  final String label;
  final String shortLabel;
  final String path;
  final IconData icon;
  final IconData selectedIcon;

  const _PortalDestination({
    required this.label,
    required this.shortLabel,
    required this.path,
    required this.icon,
    required this.selectedIcon,
  });

  static const activity = [
    _PortalDestination(
      label: 'Resumen',
      shortLabel: 'Resumen',
      path: '/cuenta',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
    ),
    _PortalDestination(
      label: 'Pedidos',
      shortLabel: 'Pedidos',
      path: '/cuenta/pedidos',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
    ),
    _PortalDestination(
      label: 'Taller',
      shortLabel: 'Taller',
      path: '/cuenta/servicios',
      icon: Icons.build_outlined,
      selectedIcon: Icons.build,
    ),
    _PortalDestination(
      label: 'Bicicletas',
      shortLabel: 'Bicicletas',
      path: '/cuenta/bicicletas',
      icon: Icons.pedal_bike_outlined,
      selectedIcon: Icons.pedal_bike,
    ),
    _PortalDestination(
      label: 'Soporte',
      shortLabel: 'Soporte',
      path: '/cuenta/chats',
      icon: Icons.chat_bubble_outline,
      selectedIcon: Icons.chat_bubble,
    ),
  ];

  static const account = [
    _PortalDestination(
      label: 'Perfil y seguridad',
      shortLabel: 'Perfil',
      path: '/cuenta/perfil',
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
    ),
    _PortalDestination(
      label: 'Direcciones',
      shortLabel: 'Direcciones',
      path: '/cuenta/direcciones',
      icon: Icons.location_on_outlined,
      selectedIcon: Icons.location_on,
    ),
  ];

  static const items = [...activity, ...account];
}
