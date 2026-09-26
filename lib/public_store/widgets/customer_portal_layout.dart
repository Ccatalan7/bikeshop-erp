import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/customer_portal_presentation.dart';
import '../services/customer_account_service.dart';
import 'customer_job_row.dart';
import 'customer_portal_style.dart';
import 'public_store_layout.dart';

/// Marco del portal de clientes (`/cuenta/**`), dirección «Sendero».
///
/// De arriba abajo: el aviso de lo que espera al cliente (una banda oscura,
/// fuera del resumen, que ya lo muestra en grande), la franja con la foto del
/// portal y el título de la página, las pestañas de la cuenta y el contenido
/// en una columna de hasta [PortalStyle.contentMaxWidth]. Todo se desplaza
/// junto: las rutas del portal se montan sin el scroll de la tienda
/// (`_buildPageNoScroll`) y el marco pone el suyo.
///
/// Una página que maneja su propio alto (el chat abierto,
/// [enableContentScrolling] en `false`) no lleva la franja: recibe el alto que
/// queda bajo las pestañas, con el título en una línea.
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

  /// La franja alta del resumen, con el saludo en grande.
  final bool prominent;

  /// A la derecha del saludo en la franja alta: «Cliente desde…».
  final String? bandMeta;

  /// Lo que va a todo el ancho bajo el contenido (la franja de servicio).
  final Widget? footer;

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
    this.prominent = false,
    this.bandMeta,
    this.footer,
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

    final style = PortalStyle.of(context);
    final location = GoRouterState.of(context).uri.path;
    final onDashboard = _matches(location, '/cuenta');

    return ColoredBox(
      color: style.page,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final wide = width >= PortalStyle.wideBreakpoint;
          final gutter = PortalStyle.gutter(width);
          final bounded = constraints.hasBoundedHeight;
          final fitsViewport = bounded && !enableContentScrolling;
          final showBand = showHeader && !fitsViewport;
          final sidebar = wide ? rightSidebarContent : null;
          final pending = onDashboard
              ? null
              : CustomerPendingAction.first(
                  orders: accountService.orders,
                  jobs: accountService.serviceHistory,
                );

          Widget column(Widget child) => _PortalColumn(
                gutter: gutter,
                extraWidth: sidebar == null ? 0 : 336,
                child: child,
              );

          final top = <Widget>[
            if (pending != null && !fitsViewport)
              _PendingActionStrip(action: pending, gutter: gutter),
            if (showBand)
              PortalBand(
                title: title,
                meta: prominent ? bandMeta : (bandMeta ?? subtitle),
                action: headerAction,
                prominent: prominent,
                gutter: gutter,
                compact: width < PortalStyle.compactBreakpoint,
                onSignOut: wide ? null : () => _signOut(context),
              ),
            _PortalTabs(
              gutter: gutter,
              showSignOut: wide,
              location: location,
            ),
          ];

          Widget body = _PortalContent(
            title: title,
            showTitle: showHeader && !showBand,
            headerAction: showBand ? null : headerAction,
            showBackButton: showBackButton,
            backPath: backPath,
            expandChild: fitsViewport,
            child: child,
          );
          if (sidebar != null) {
            body = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: body),
                const SizedBox(width: 32),
                SizedBox(width: 304, child: sidebar),
              ],
            );
          }

          if (fitsViewport) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...top,
                Expanded(
                  child: column(
                    Padding(
                      padding: EdgeInsets.only(
                        top: showHeader ? (wide ? 28 : 16) : 8,
                        bottom: 16,
                      ),
                      child: body,
                    ),
                  ),
                ),
              ],
            );
          }

          final page = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...top,
              column(
                Padding(
                  padding: EdgeInsets.only(
                    top: wide ? 56 : 32,
                    bottom: footer == null ? 80 : 72,
                  ),
                  child: body,
                ),
              ),
              if (footer != null) footer!,
            ],
          );
          if (!bounded) return page;
          return SingleChildScrollView(child: page);
        },
      ),
    );
  }
}

/// El contenido centrado, con sus márgenes.
class _PortalColumn extends StatelessWidget {
  const _PortalColumn({
    required this.gutter,
    required this.child,
    this.extraWidth = 0,
  });

  final double gutter;
  final double extraWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: PortalStyle.contentMaxWidth + extraWidth + gutter * 2,
        ),
        // Todo el ancho disponible: una columna de texto no se encoge y
        // queda centrada, va pegada al margen.
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// La franja de arriba de cada página: la foto del portal (la que el dueño
/// elige en el editor, «Portal de clientes») con el texto abajo a la
/// izquierda. Sin foto, la franja va en el color de texto.
class PortalBand extends StatelessWidget {
  const PortalBand({
    super.key,
    required this.title,
    required this.gutter,
    required this.compact,
    this.eyebrow = 'Mi cuenta',
    this.meta,
    this.action,
    this.prominent = false,
    this.onSignOut,
  });

  final String eyebrow;
  final String title;
  final String? meta;
  final Widget? action;
  final bool prominent;
  final double gutter;
  final bool compact;

  /// En teléfono «Salir» va arriba a la derecha de la franja.
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final image = style.site.customerPortalImage;
    final hasImage = image.isNotEmpty;
    final foreground = hasImage ? Colors.white : style.onBand;
    final background = ColoredBox(color: style.band);
    final minHeight =
        prominent ? (compact ? 240.0 : 300.0) : (compact ? 170.0 : 210.0);

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          semanticsLabel: eyebrow,
          style: style.eyebrow.copyWith(
            color: foreground.withValues(alpha: 0.86),
          ),
        ),
        const SizedBox(height: 10),
        Semantics(
          header: true,
          child: Text(
            title.toUpperCase(),
            semanticsLabel: title,
            style: (prominent
                    ? style.display(compact: compact)
                    : style.pageTitle(compact: compact))
                .copyWith(color: foreground),
          ),
        ),
      ],
    );
    final metaText = meta == null || meta!.trim().isEmpty
        ? null
        : Text(
            meta!,
            textAlign: prominent && !compact ? TextAlign.right : TextAlign.left,
            style: style.body(compact ? 14 : 15,
                color: foreground.withValues(alpha: 0.88), height: 1.55),
          );

    final Widget content;
    if (compact) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading,
          if (metaText != null) ...[const SizedBox(height: 10), metaText],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      );
    } else if (prominent) {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: heading),
          if (metaText != null) ...[
            const SizedBox(width: 24),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: metaText,
            ),
          ],
          if (action != null) ...[const SizedBox(width: 24), action!],
        ],
      );
    } else {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading,
                if (metaText != null) ...[
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: metaText,
                  ),
                ],
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 24), action!],
        ],
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Stack(
        alignment: AlignmentDirectional.bottomStart,
        children: [
          Positioned.fill(
            child: hasImage
                ? Image.network(
                    image,
                    fit: BoxFit.cover,
                    alignment: const Alignment(-0.4, 0.1),
                    errorBuilder: (_, __, ___) => background,
                  )
                : background,
          ),
          if (hasImage)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: compact
                      ? const LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0xD90A0B0B), Color(0x4D0A0B0B)],
                        )
                      : const LinearGradient(
                          colors: [
                            Color(0xCC0A0B0B),
                            Color(0x730A0B0B),
                            Color(0x260A0B0B),
                          ],
                          stops: [0, 0.55, 1],
                        ),
                ),
              ),
            ),
          _PortalColumn(
            gutter: gutter,
            child: Padding(
              padding: EdgeInsets.only(
                top: onSignOut == null ? 48 : 64,
                bottom: compact ? 24 : 40,
              ),
              child: content,
            ),
          ),
          if (onSignOut != null)
            Positioned(
              top: 6,
              right: gutter - 8,
              child: TextButton(
                onPressed: onSignOut,
                style: TextButton.styleFrom(
                  foregroundColor: foreground,
                  shape: PortalStyle.shape,
                  minimumSize: const Size(44, 44),
                  textStyle: style.label.copyWith(fontSize: 12),
                ),
                child: const Text('SALIR', semanticsLabel: 'Cerrar sesión'),
              ),
            ),
        ],
      ),
    );
  }
}

/// La banda oscura con lo primero que espera al cliente, en cualquier página
/// de la cuenta que no sea el resumen.
class _PendingActionStrip extends StatelessWidget {
  const _PendingActionStrip({required this.action, required this.gutter});

  final CustomerPendingAction action;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final text = '${action.status} · ${action.subject}';
    void open() {
      final job = action.job;
      if (job != null) {
        showCustomerJobDetail(
          context,
          job: job,
          onNavigate: (href) => PublicStoreLayout.navigateToHref(context, href),
        );
        return;
      }
      final order = action.order;
      if (order != null) {
        PublicStoreLayout.navigateToHref(context, '/pedido/${order.id}');
      }
    }

    return Semantics(
      button: true,
      label: '$text. ${action.actionLabel}',
      excludeSemantics: true,
      child: Material(
        color: style.band,
        child: InkWell(
          onTap: open,
          child: _PortalColumn(
            gutter: gutter,
            child: SizedBox(
              height: 44,
              child: Row(
                children: [
                  Container(width: 8, height: 8, color: style.attention),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style.label.copyWith(
                        color: style.onBand,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.only(bottom: 2),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: style.onBand)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          action.actionLabel.toUpperCase(),
                          style: style.label.copyWith(
                            color: style.onBand,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.arrow_forward,
                            size: 16, color: style.onBand),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lo que ve quien entra a `/cuenta/**` sin sesión, o con una sesión que no
/// es cliente de esta tienda: la franja del portal y una columna corta con
/// qué hay adentro y el botón para entrar.
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
        ? 'Preparando tu cuenta'
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
      color: style.page,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final gutter = PortalStyle.gutter(constraints.maxWidth);
          final page = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PortalBand(
                title: title,
                gutter: gutter,
                compact: constraints.maxWidth < PortalStyle.compactBreakpoint,
              ),
              _PortalColumn(
                gutter: gutter,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(message, style: style.body(17)),
                          const SizedBox(height: 28),
                          if (isLoading)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox.square(
                                dimension: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: style.action,
                                ),
                              ),
                            )
                          else ...[
                            PortalButton(
                              label:
                                  hasSession ? 'Reintentar' : 'Iniciar sesión',
                              arrow: !hasSession,
                              expand: true,
                              onPressed: hasSession
                                  ? () =>
                                      accountService.reloadCustomerMembership()
                                  : () => PublicStoreLayout.navigateToHref(
                                        context,
                                        '/cuenta/login',
                                      ),
                            ),
                            const SizedBox(height: 12),
                            if (hasSession)
                              PortalButton(
                                label: 'Cerrar esta sesión',
                                kind: PortalButtonKind.secondary,
                                expand: true,
                                onPressed: () =>
                                    PublicStoreLayout.signOutCustomer(
                                  context,
                                  accountService,
                                  destination: '/cuenta/login',
                                ),
                              )
                            else
                              Text(
                                '¿Primera vez? Puedes crear tu cuenta ahí '
                                'mismo.',
                                style: style.rowMeta,
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
          if (!constraints.hasBoundedHeight) return page;
          return SingleChildScrollView(child: page);
        },
      ),
    );
  }
}

class _PortalContent extends StatelessWidget {
  const _PortalContent({
    required this.title,
    required this.showTitle,
    required this.headerAction,
    required this.showBackButton,
    required this.backPath,
    required this.expandChild,
    required this.child,
  });

  final String title;
  final bool showTitle;
  final Widget? headerAction;
  final bool showBackButton;
  final String? backPath;
  final bool expandChild;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final uri = GoRouterState.of(context).uri;
    // Una sección de las pestañas no lleva «Volver»: las pestañas ya están a
    // la vista. Sí lo lleva una vista filtrada o de detalle (`?bike_id=`,
    // `backPath`).
    final isTopLevel =
        _PortalDestination.items.any((item) => _matches(uri.path, item.path)) &&
            uri.queryParameters.isEmpty &&
            backPath == null;
    final showBack = showBackButton && !isTopLevel;

    final heading = showTitle
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title.toUpperCase(),
                    semanticsLabel: title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style.sectionTitle(compact: false),
                  ),
                ),
              ),
              if (headerAction != null) ...[
                const SizedBox(width: 16),
                headerAction!,
              ],
            ],
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showBack) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _goBack(context, backPath),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('VOLVER', semanticsLabel: 'Volver'),
              style: TextButton.styleFrom(
                foregroundColor: style.ink,
                shape: PortalStyle.shape,
                textStyle: style.label.copyWith(fontSize: 13),
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
          ),
          SizedBox(height: heading == null ? 12 : 8),
        ],
        if (heading != null) ...[heading, const SizedBox(height: 20)],
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

/// La pestaña que se marca: una conversación abierta (`/cuenta/chats/:id`)
/// sigue en «Soporte».
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

/// Las secciones de la cuenta en una fila de pestañas en mayúsculas, con la
/// abierta subrayada en el color de acción. Si no caben, se desplazan y la
/// abierta se trae a la vista.
class _PortalTabs extends StatefulWidget {
  const _PortalTabs({
    required this.gutter,
    required this.showSignOut,
    required this.location,
  });

  final double gutter;
  final bool showSignOut;
  final String location;

  @override
  State<_PortalTabs> createState() => _PortalTabsState();
}

class _PortalTabsState extends State<_PortalTabs> {
  final _selectedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _revealSelected();
  }

  @override
  void didUpdateWidget(_PortalTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) _revealSelected();
  }

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
    final tabs = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final item in _PortalDestination.items)
            _PortalTab(
              key: _inSection(widget.location, item.path) ? _selectedKey : null,
              label: item.label,
              selected: _inSection(widget.location, item.path),
              onTap: () => _navigateWithinPortal(context, item.path),
            ),
        ],
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.page,
        border: Border(bottom: BorderSide(color: style.line)),
      ),
      child: SizedBox(
        height: 60,
        child: _PortalColumn(
          gutter: widget.gutter < 32 ? 0 : widget.gutter,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: widget.gutter < 32 ? 4 : 0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tabs),
                if (widget.showSignOut) ...[
                  const SizedBox(width: 24),
                  TextButton(
                    onPressed: () => _signOut(context),
                    style: TextButton.styleFrom(
                      foregroundColor: style.inkSecondary,
                      shape: PortalStyle.shape,
                      textStyle: style.label.copyWith(fontSize: 12),
                    ),
                    child: const Text(
                      'CERRAR SESIÓN',
                      semanticsLabel: 'Cerrar sesión',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PortalTab extends StatelessWidget {
  const _PortalTab({
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
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? style.action : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              label.toUpperCase(),
              style: style.label.copyWith(
                color: selected ? style.ink : style.inkSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PortalDestination {
  final String label;
  final String path;

  const _PortalDestination({required this.label, required this.path});

  static const items = [
    _PortalDestination(label: 'Resumen', path: '/cuenta'),
    _PortalDestination(label: 'Pedidos', path: '/cuenta/pedidos'),
    _PortalDestination(label: 'Taller', path: '/cuenta/servicios'),
    _PortalDestination(label: 'Bicicletas', path: '/cuenta/bicicletas'),
    _PortalDestination(label: 'Soporte', path: '/cuenta/chats'),
    _PortalDestination(label: 'Perfil', path: '/cuenta/perfil'),
    _PortalDestination(label: 'Direcciones', path: '/cuenta/direcciones'),
  ];
}
