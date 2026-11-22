part of '../public_store_layout.dart';

/// The phone's menu, as the HTML store draws it (`site_layout.dart`,
/// 2026-10-25): a drawer from the right with the search first, then the
/// menu; an item with children opens its own level over it with «‹ …»
/// back, «Ver todo …» first and its rows with their icons («Navegación»);
/// a level of brands shows their logos in a grid (2026-11-21). The account
/// and the help card close it.
class _MobileMenuDrawer extends StatefulWidget {
  const _MobileMenuDrawer({
    required this.items,
    this.brands = const <String, WebsiteMenuBrand>{},
    required this.canNavigate,
    required this.onNavigate,
    required this.onSearch,
    required this.help,
    required this.isAuthenticated,
    required this.onAccount,
    required this.onSignIn,
    required this.onSignOut,
    required this.onHelp,
    this.onConfigure,
  });

  final List<WebsiteNavigation> items;

  /// The logos of the brands the menu leads to, by brand id.
  final Map<String, WebsiteMenuBrand> brands;
  final bool Function(WebsiteNavigation navigation) canNavigate;
  final ValueChanged<WebsiteNavigation> onNavigate;
  final VoidCallback onSearch;
  final HeaderMenuHelp help;
  final bool isAuthenticated;
  final VoidCallback onAccount;
  final VoidCallback onSignIn;
  final VoidCallback onSignOut;
  final VoidCallback onHelp;

  /// In the editor, an empty menu leads to «Navegación».
  final VoidCallback? onConfigure;

  @override
  State<_MobileMenuDrawer> createState() => _MobileMenuDrawerState();
}

class _MobileMenuDrawerState extends State<_MobileMenuDrawer> {
  final List<WebsiteNavigation> _levels = [];

  List<WebsiteNavigation> _visible(Iterable<WebsiteNavigation> nodes) =>
      nodes.where((item) => item.isVisible && item.showOnMobile).toList()
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

  bool _leads(WebsiteNavigation node) =>
      widget.canNavigate(node) && node.href?.trim().isNotEmpty == true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final level = _levels.isEmpty ? null : _levels.last;
    return Material(
      color: colors.surface,
      elevation: 16,
      child: SafeArea(
        left: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _top(context, level),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.06, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                layoutBuilder: (current, previous) =>
                    current ?? const SizedBox.shrink(),
                child: KeyedSubtree(
                  key: ValueKey<String>('mobile-menu-${level?.id ?? 'root'}'),
                  child:
                      level == null ? _root(context) : _level(context, level),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _top(BuildContext context, WebsiteNavigation? level) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final back =
        _levels.length > 1 ? _levels[_levels.length - 2].label : 'Menú';
    return Container(
      height: 60,
      padding: const EdgeInsets.only(left: 20, right: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          if (level == null)
            Expanded(
              child: Text(
                'Menú',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
            )
          else ...[
            TextButton.icon(
              key: const ValueKey<String>('mobile-menu-back'),
              onPressed: () => setState(_levels.removeLast),
              style: TextButton.styleFrom(
                foregroundColor: colors.primary,
                padding: const EdgeInsets.only(left: 0, right: 10),
                minimumSize: const Size(0, 44),
                textStyle: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              icon: const Icon(Icons.chevron_left_rounded, size: 22),
              label: Text(back),
            ),
            const Spacer(),
          ],
          IconButton(
            tooltip: 'Cerrar el menú',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
            color: colors.onSurface,
          ),
        ],
      ),
    );
  }

  Widget _root(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final items = _visible(widget.items);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Material(
            color: Colors.transparent,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: colors.outlineVariant),
              borderRadius: BorderRadius.circular(10),
            ),
            child: InkWell(
              key: const ValueKey<String>('mobile-menu-search'),
              borderRadius: BorderRadius.circular(10),
              onTap: widget.onSearch,
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    Icon(Icons.search,
                        size: 20, color: colors.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Buscar: cámara 29, pastillas, cassette…',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontSize: 16,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (items.isEmpty && widget.onConfigure != null)
          _row(
            context,
            label: 'Configurar navegación',
            color: colors.primary,
            onTap: widget.onConfigure!,
          ),
        for (final item in items)
          if (_item(context, item, top: true, iconSlot: false) case final row?)
            row,
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed:
                    widget.isAuthenticated ? widget.onAccount : widget.onSignIn,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: Icon(
                  widget.isAuthenticated
                      ? Icons.person_rounded
                      : Icons.person_outline,
                  size: 20,
                ),
                label: Text(
                  widget.isAuthenticated ? 'Mi cuenta' : 'Iniciar sesión',
                ),
              ),
              if (widget.isAuthenticated) ...[
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: widget.onSignOut,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.error,
                    minimumSize: const Size.fromHeight(44),
                  ),
                  icon: const Icon(Icons.logout_rounded, size: 20),
                  label: const Text('Cerrar sesión'),
                ),
              ],
              if (widget.help.show) ...[
                const SizedBox(height: 10),
                Material(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    key: const ValueKey<String>('mobile-menu-help'),
                    borderRadius: BorderRadius.circular(10),
                    onTap: widget.onHelp,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 22,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                text: '${widget.help.title} ',
                                children: [
                                  TextSpan(
                                    text: widget.help.action,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: colors.primary,
                                    ),
                                  ),
                                ],
                              ),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 15,
                                height: 1.35,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _level(BuildContext context, WebsiteNavigation level) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final children = _visible(level.children);
    final icons = children.any(
      (child) => WebsiteMenuIcons.of(child.icon) != null,
    );
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
          child: Text(
            level.label,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontSize: 28,
              height: 1.15,
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
        ),
        if (_leads(level))
          _row(
            context,
            label: 'Ver todo ${level.label}',
            color: colors.primary,
            weight: FontWeight.w600,
            onTap: () => widget.onNavigate(level),
          ),
        if (websiteMenuShowsBrands(children))
          _brandGrid(context, children)
        else
          for (final child in children)
            if (_item(context, child, top: false, iconSlot: icons)
                case final row?)
              row,
      ],
    );
  }

  /// A level of brands, as the HTML store's sheet draws it: two tiles
  /// across, each with the brand's logo on a white badge (its initials when
  /// it has none) beside its name.
  Widget _brandGrid(BuildContext context, List<WebsiteNavigation> items) {
    final shown = [
      for (final item in items)
        if (_leads(item)) item,
    ];
    return Padding(
      key: const ValueKey<String>('mobile-menu-brands'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 8.0;
          final width = (constraints.maxWidth - gap) / 2;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final item in shown)
                SizedBox(
                  width: width,
                  child: _brandTile(context, item),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _brandTile(BuildContext context, WebsiteNavigation item) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final logo = widget.brands[websiteMenuBrandId(item) ?? '']?.logoUrl ?? '';
    return Semantics(
      link: true,
      label: item.label,
      excludeSemantics: true,
      child: Material(
        key: ValueKey<String>('mobile-menu-brand-${item.id}'),
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.8),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => widget.onNavigate(item),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 58),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
              child: Row(
                children: [
                  MenuBrandBadge(
                    label: item.label,
                    logoUrl: logo,
                    width: 58,
                    height: 44,
                    padding: 3,
                    radius: 8,
                    initialsSize: 15,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                        color: colors.onSurface,
                      ),
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

  Widget? _item(
    BuildContext context,
    WebsiteNavigation item, {
    required bool top,
    required bool iconSlot,
  }) {
    final children = _visible(item.children);
    if (children.isEmpty && !_leads(item)) return null;
    return _row(
      context,
      key: ValueKey<String>('mobile-menu-item-${item.id}'),
      label: item.label,
      top: top,
      icon: iconSlot ? item.icon : null,
      iconSlot: iconSlot,
      opens: children.isNotEmpty,
      onTap: children.isNotEmpty
          ? () => setState(() => _levels.add(item))
          : () => widget.onNavigate(item),
    );
  }

  Widget _row(
    BuildContext context, {
    Key? key,
    required String label,
    required VoidCallback onTap,
    bool top = false,
    String? icon,
    bool iconSlot = false,
    bool opens = false,
    Color? color,
    FontWeight? weight,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = color ?? colors.onSurface;
    final style = top
        ? theme.textTheme.titleMedium?.copyWith(
            fontFamily: theme.textTheme.headlineSmall?.fontFamily,
            fontSize: 17,
            height: 1.2,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.85,
            color: foreground,
          )
        : theme.textTheme.bodyLarge?.copyWith(
            fontSize: 16,
            height: 1.25,
            fontWeight: weight ?? FontWeight.w500,
            color: foreground,
          );
    return Material(
      key: key,
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: colors.primary.withValues(alpha: 0.045),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: colors.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
          child: Row(
            children: [
              if (iconSlot) ...[
                WebsiteMenuIconView(icon, size: 22, color: colors.primary),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Text(
                  top ? label.toUpperCase() : label,
                  style: style,
                ),
              ),
              if (opens)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: colors.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
