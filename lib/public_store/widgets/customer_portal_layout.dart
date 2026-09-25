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
          // Una página que maneja su propio alto (el chat abierto) recibe el
          // espacio que queda bajo el título, sin el scroll del portal.
          final fitsViewport = bounded && !enableContentScrolling;
          final content = _PortalContent(
            title: title,
            subtitle: subtitle,
            showHeader: showHeader,
            headerAction: headerAction,
            showBackButton: showBackButton,
            backPath: backPath,
            compact: !wide,
            expandChild: fitsViewport,
            child: child,
          );

          if (wide) {
            final scrollingContent = fitsViewport
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(0, 36, 0, 24),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: PortalStyle.contentMaxWidth,
                        ),
                        child: content,
                      ),
                    ),
                  )
                : SingleChildScrollView(
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
          if (fitsViewport) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                bar,
                Expanded(
                  child: Padding(
                    padding:
                        EdgeInsets.fromLTRB(16, showHeader ? 20 : 8, 16, 12),
                    child: content,
                  ),
                ),
              ],
            );
          }
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

/// Lo que ve quien entra a `/cuenta/**` sin sesión, o con una sesión que no
/// es cliente de esta tienda. Mismo lenguaje que el portal: el título en la
/// fuente del sitio y el botón en el color de comercio, no el verde del sitio.
class _CustomerPortalAuthBoundary extends StatelessWidget {
  const _CustomerPortalAuthBoundary({
    required this.accountService,
  });

  final CustomerAccountService accountService;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final isLoading = accountService.isCustomerMembershipLoading;
    final hasSession = accountService.hasAuthSession;
    final title = isLoading
        ? 'Preparando tu cuenta…'
        : hasSession
            ? 'No pudimos abrir esta cuenta'
            : 'Entra a tu cuenta';
    final message = isLoading
        ? 'Estamos verificando tu acceso a esta tienda.'
        : hasSession
            ? 'Tu sesión está abierta, pero no está registrada como cliente '
                'de esta tienda.'
            : 'Aquí ves tus pedidos, tu bici en el taller y tus '
                'conversaciones con la tienda.';

    return ColoredBox(
      color: style.canvas,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: style.panel,
                borderRadius: BorderRadius.circular(PortalStyle.panelRadius),
                border: Border.all(color: style.line),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isLoading)
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: style.accent,
                        ),
                      )
                    else
                      PortalThumb(
                        fallbackIcon: hasSession
                            ? Icons.verified_user_outlined
                            : Icons.person_outline,
                        size: 44,
                      ),
                    const SizedBox(height: 20),
                    Semantics(
                      header: true,
                      child: Text(
                        title.toUpperCase(),
                        style: style.pageTitle(compact: true),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(message, style: style.pageSubtitle),
                    if (!isLoading) ...[
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: hasSession
                              ? () => accountService.reloadCustomerMembership()
                              : () => PublicStoreLayout.navigateToHref(
                                    context,
                                    '/cuenta/login',
                                  ),
                          style: portalPrimaryButton(context),
                          child: Text(
                            hasSession ? 'Reintentar' : 'Iniciar sesión',
                          ),
                        ),
                      ),
                      if (hasSession) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () => PublicStoreLayout.signOutCustomer(
                              context,
                              accountService,
                              destination: '/cuenta/login',
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: style.inkSecondary,
                              minimumSize: const Size(0, 44),
                            ),
                            child: const Text('Cerrar esta sesión'),
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 12),
                        Center(
                          child: Text(
                            '¿Primera vez? Puedes crear tu cuenta ahí mismo.',
                            textAlign: TextAlign.center,
                            style: style.rowMeta,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
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
    required this.expandChild,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final bool showHeader;
  final Widget? headerAction;
  final bool showBackButton;
  final String? backPath;
  final bool compact;
  final bool expandChild;
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
        if (expandChild) Expanded(child: child) else child,
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

/// La sección del menú que se marca: una conversación abierta
/// (`/cuenta/chats/:id`) sigue en «Soporte».
bool _inSection(String location, String path) {
  if (_matches(location, path)) return true;
  if (path == '/cuenta') return false;
  return location.startsWith('$path/') || location.startsWith('/tienda$path/');
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
              isSelected: _inSection(location, item.path),
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

class _CompactAccountBar extends StatefulWidget {
  const _CompactAccountBar({required this.identity});

  final _PortalIdentity identity;

  @override
  State<_CompactAccountBar> createState() => _CompactAccountBarState();
}

class _CompactAccountBarState extends State<_CompactAccountBar> {
  final _selectedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _revealSelected();
  }

  @override
  void didUpdateWidget(_CompactAccountBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _revealSelected();
  }

  /// «Soporte» y «Direcciones» quedan fuera del ancho de un teléfono: la
  /// pestaña de la página abierta se trae a la vista.
  void _revealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final selected = _selectedKey.currentContext;
      if (selected == null || !mounted) return;
      Scrollable.ensureVisible(
        selected,
        alignment: 0.5,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final identity = widget.identity;
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
                    key: _inSection(location, item.path) ? _selectedKey : null,
                    label: item.shortLabel,
                    selected: _inSection(location, item.path),
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
    super.key,
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
