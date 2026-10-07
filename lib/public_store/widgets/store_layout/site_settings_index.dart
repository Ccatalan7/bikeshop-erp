part of '../public_store_layout.dart';

/// One line of the «Ajustes del sitio» index: a page of the hub, or an action
/// (the brand lives in the canvas's «Tema»; the versions are a dialog).
class _SiteSettingsEntry {
  const _SiteSettingsEntry({
    required this.label,
    required this.detail,
    required this.icon,
    this.tab,
    this.action,
  });

  final String label;
  final String detail;
  final IconData icon;
  final _EditorConfigHubTab? tab;
  final _SiteSettingsAction? action;
}

enum _SiteSettingsAction { brand, versions }

class _SiteSettingsGroup {
  const _SiteSettingsGroup(this.label, this.entries);

  final String label;
  final List<_SiteSettingsEntry> entries;
}

/// What is the whole site's, grouped the way the owner looks for it (approved
/// proposal, 2026-10-06: «Marca, Menús, Dominio y Google, Pagos y envíos,
/// Integraciones, Versiones guardadas»).
const List<_SiteSettingsGroup> _siteSettingsIndex = [
  _SiteSettingsGroup('Marca', [
    _SiteSettingsEntry(
      label: 'Colores, letras y botones',
      detail: 'En «Tema», sobre la página',
      icon: Icons.palette_outlined,
      action: _SiteSettingsAction.brand,
    ),
    _SiteSettingsEntry(
      label: 'Tienda y contacto',
      detail: 'Nombre, teléfono, redes, transferencia',
      icon: Icons.storefront_outlined,
      tab: _EditorConfigHubTab.siteSettings,
    ),
  ]),
  _SiteSettingsGroup('Navegación', [
    _SiteSettingsEntry(
      label: 'Menús',
      detail: 'Encabezado y pie de página',
      icon: Icons.menu_rounded,
      tab: _EditorConfigHubTab.siteNavigation,
    ),
    _SiteSettingsEntry(
      label: 'Páginas',
      detail: 'Crear, publicar y ordenar',
      icon: Icons.description_outlined,
      tab: _EditorConfigHubTab.sitePages,
    ),
    _SiteSettingsEntry(
      label: 'Enlaces',
      detail: 'A dónde lleva cada botón',
      icon: Icons.account_tree_outlined,
      tab: _EditorConfigHubTab.siteDestinations,
    ),
  ]),
  _SiteSettingsGroup('Dominio y Google', [
    _SiteSettingsEntry(
      label: 'Dominio',
      detail: 'La dirección de la tienda',
      icon: Icons.link_rounded,
      tab: _EditorConfigHubTab.domain,
    ),
    _SiteSettingsEntry(
      label: 'Buscadores',
      detail: 'Cómo sale en Google',
      icon: Icons.manage_search_rounded,
      tab: _EditorConfigHubTab.seo,
    ),
    _SiteSettingsEntry(
      label: 'Integraciones',
      detail: 'Google, Merchant y feed',
      icon: Icons.extension_outlined,
      tab: _EditorConfigHubTab.integrations,
    ),
    _SiteSettingsEntry(
      label: 'Visitas',
      detail: 'Google Analytics',
      icon: Icons.insights_rounded,
      tab: _EditorConfigHubTab.reportsAnalytics,
    ),
  ]),
  _SiteSettingsGroup('Ventas', [
    _SiteSettingsEntry(
      label: 'Pagos',
      detail: 'Cómo paga el cliente',
      icon: Icons.payments_outlined,
      tab: _EditorConfigHubTab.paymentMethods,
    ),
    _SiteSettingsEntry(
      label: 'Pedidos',
      detail: 'Los pedidos de la tienda',
      icon: Icons.shopping_bag_outlined,
      tab: _EditorConfigHubTab.ecomOrders,
    ),
  ]),
  _SiteSettingsGroup('Historial', [
    _SiteSettingsEntry(
      label: 'Versiones guardadas',
      detail: 'Volver a como estaba',
      icon: Icons.history_rounded,
      action: _SiteSettingsAction.versions,
    ),
    _SiteSettingsEntry(
      label: 'Resumen del sitio',
      detail: 'Estado y accesos',
      icon: Icons.dashboard_outlined,
      tab: _EditorConfigHubTab.siteHub,
    ),
  ]),
];

bool _isSiteSettingsTab(_EditorConfigHubTab tab) =>
    tab != _EditorConfigHubTab.ecomCatalog;

/// The index at the side of «Ajustes del sitio» (a strip on top when narrow).
class _SiteSettingsIndexView extends StatelessWidget {
  const _SiteSettingsIndexView({
    required this.selected,
    required this.onSelect,
    required this.vertical,
    required this.brandOnCanvas,
  });

  final _EditorConfigHubTab selected;
  final ValueChanged<_SiteSettingsEntry> onSelect;
  final bool vertical;

  /// Whether the canvas has the pane whose «Tema» edits the brand. A compact
  /// host has none, so the entry would lead nowhere and is left out.
  final bool brandOnCanvas;

  Iterable<_SiteSettingsEntry> _entries(_SiteSettingsGroup group) =>
      group.entries.where(
        (entry) => brandOnCanvas || entry.action != _SiteSettingsAction.brand,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (!vertical) {
      return SizedBox(
        height: 52,
        child: ListView(
          key: const ValueKey('site-settings-index'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
            for (final group in _siteSettingsIndex)
              for (final entry in _entries(group))
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    key: ValueKey('site-settings-${entry.label}'),
                    avatar: Icon(entry.icon, size: 16),
                    label: Text(entry.label),
                    selected: entry.tab == selected,
                    showCheckmark: false,
                    onSelected: (_) => onSelect(entry),
                  ),
                ),
          ],
        ),
      );
    }
    return Container(
      width: 264,
      color: scheme.surfaceContainerLow,
      child: ListView(
        key: const ValueKey('site-settings-index'),
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 20),
        children: [
          for (final group in _siteSettingsIndex) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 6),
              child: Text(
                group.label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            for (final entry in _entries(group))
              _SiteSettingsIndexRow(
                entry: entry,
                selected: entry.tab == selected,
                onTap: () => onSelect(entry),
              ),
          ],
        ],
      ),
    );
  }
}

class _SiteSettingsIndexRow extends StatelessWidget {
  const _SiteSettingsIndexRow({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final _SiteSettingsEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground =
        selected ? scheme.onSecondaryContainer : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: ValueKey('site-settings-${entry.label}'),
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  Icon(entry.icon, size: 19, color: foreground),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          entry.label,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: foreground,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        Text(
                          entry.detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: selected
                                ? scheme.onSecondaryContainer
                                    .withValues(alpha: 0.8)
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (entry.tab == null)
                    Icon(
                      Icons.north_east_rounded,
                      size: 14,
                      color: scheme.onSurfaceVariant,
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
