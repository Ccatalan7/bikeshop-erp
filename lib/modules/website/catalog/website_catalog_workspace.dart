import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../public_store/services/public_inventory_service.dart';
import '../../../shared/services/inventory_service.dart' as shared_inventory;
import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../inventory/pages/hierarchical_category_page.dart';
import '../services/website_service.dart';
import '../widgets/website_admin_ui.dart';
import 'catalog_categories_view.dart';
import 'catalog_featured_view.dart';
import 'catalog_products_view.dart';
import 'catalog_resolve_view.dart';
import 'catalog_rules_sheet.dart';
import 'catalog_services_view.dart';
import 'catalog_ui_parts.dart';
import 'catalog_web_controller.dart';
import 'catalog_web_models.dart';

export 'catalog_categories_view.dart' show CatalogOpenCategoryPage;

/// The tabs of the store catalog.
enum CatalogWorkspaceTab { products, resolve, services, categories, featured }

/// The store catalog: what sells online, why the rest does not, and how
/// each section looks on the real page. One projection
/// (`catalog_web_items_v1`) and one rule (`catalog_product_web_block_v1`)
/// behind every tab, the same the store reads.
class WebsiteCatalogWorkspace extends StatefulWidget {
  const WebsiteCatalogWorkspace({
    super.key,
    this.embedded = false,
    this.tab,
    this.initialTab = CatalogWorkspaceTab.products,
    this.onTabChanged,
    this.onOpenCategoryPage,
    @visibleForTesting this.controller,
  });

  /// Inside the site editor (no admin header of its own).
  final bool embedded;

  /// The tab, when the host keeps it (the editor reopens where it left).
  final CatalogWorkspaceTab? tab;
  final CatalogWorkspaceTab initialTab;
  final ValueChanged<CatalogWorkspaceTab>? onTabChanged;

  /// Opens a category's own page on the editor canvas.
  final CatalogOpenCategoryPage? onOpenCategoryPage;

  /// A controller the test owns; the workspace makes its own otherwise.
  final CatalogWebController? controller;

  @override
  State<WebsiteCatalogWorkspace> createState() =>
      _WebsiteCatalogWorkspaceState();
}

class _WebsiteCatalogWorkspaceState extends State<WebsiteCatalogWorkspace> {
  late final CatalogWebController _controller;
  late CatalogWorkspaceTab _tab = widget.tab ?? widget.initialTab;
  bool _hierarchy = false;

  @override
  void initState() {
    super.initState();
    WebsiteService? website;
    try {
      website = context.read<WebsiteService>();
    } catch (_) {
      // A host without the website owner still reads; rules cannot be saved.
    }
    _controller = widget.controller ??
        CatalogWebController(
          saveSettings: website?.saveSettings,
          afterWrite: _clearCaches,
        );
    _controller.load();
  }

  @override
  void didUpdateWidget(WebsiteCatalogWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    final tab = widget.tab;
    if (tab != null && tab != _tab) setState(() => _tab = tab);
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  /// The ERP keeps its own copies of products and of the store's lists.
  Future<void> _clearCaches(String tenantId) async {
    if (!mounted) return;
    shared_inventory.InventoryService? inventory;
    PublicInventoryService? public;
    WebsiteService? website;
    try {
      inventory = context.read<shared_inventory.InventoryService>();
    } catch (_) {}
    try {
      public = context.read<PublicInventoryService>();
    } catch (_) {}
    try {
      website = context.read<WebsiteService>();
    } catch (_) {}
    public?.clearProductCache(tenantId: tenantId);
    await Future.wait([
      if (inventory != null) inventory.refresh(),
      if (public != null) public.refreshCategoriesForTenant(tenantId: tenantId),
      if (website != null) website.loadFeaturedProducts(),
    ]);
  }

  void _pick(CatalogWorkspaceTab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    widget.onTabChanged?.call(tab);
  }

  Widget _body() {
    if (!_controller.loaded) return CatalogLoadState(controller: _controller);
    return switch (_tab) {
      CatalogWorkspaceTab.products => CatalogProductsView(
          controller: _controller,
          onOpenResolve: () => _pick(CatalogWorkspaceTab.resolve),
        ),
      CatalogWorkspaceTab.resolve =>
        CatalogResolveView(controller: _controller),
      CatalogWorkspaceTab.services =>
        CatalogServicesView(controller: _controller),
      CatalogWorkspaceTab.categories => _hierarchy
          ? const HierarchicalCategoryPage(embedded: true)
          : CatalogCategoriesView(
              controller: _controller,
              onOpenCategoryPage: widget.onOpenCategoryPage,
            ),
      CatalogWorkspaceTab.featured =>
        CatalogFeaturedView(controller: _controller),
    };
  }

  @override
  Widget build(BuildContext context) {
    final content = ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TabBar(
            controller: _controller,
            tab: _tab,
            hierarchy: _hierarchy,
            onPick: _pick,
            onHierarchy: (value) => setState(() => _hierarchy = value),
          ),
          if (_controller.loading && _controller.loaded)
            const LinearProgressIndicator(minHeight: 2)
          else
            const SizedBox(height: 2),
          Expanded(
            child: KeyedSubtree(
              key: ValueKey('catalog-${_tab.name}-$_hierarchy'),
              child: _body(),
            ),
          ),
        ],
      ),
    );
    if (widget.embedded) return content;
    return WebsiteAdminShell(
      title: 'Catálogo de la tienda',
      description:
          'Qué se vende en vinabike.cl, por qué lo demás no, y cómo se ve en la página real.',
      child: content,
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.controller,
    required this.tab,
    required this.hierarchy,
    required this.onPick,
    required this.onHierarchy,
  });

  final CatalogWebController controller;
  final CatalogWorkspaceTab tab;
  final bool hierarchy;
  final ValueChanged<CatalogWorkspaceTab> onPick;
  final ValueChanged<bool> onHierarchy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final loaded = controller.loaded;
    final selling =
        loaded ? controller.countGoods(CatalogItemState.selling) : null;
    final issues = loaded ? controller.openIssueCount : null;
    final services = loaded
        ? controller.services
            .where((s) => s.state == CatalogItemState.selling)
            .length
        : null;
    final categories =
        loaded ? controller.categories.where((c) => c.visible).length : null;
    final featured = loaded ? controller.featuredIds.length : null;

    final tabs = [
      _TabSpec(CatalogWorkspaceTab.products, 'Productos',
          Icons.inventory_2_outlined, selling),
      _TabSpec(CatalogWorkspaceTab.resolve, 'Por resolver',
          Icons.checklist_rounded, issues,
          attention: (issues ?? 0) > 0),
      _TabSpec(CatalogWorkspaceTab.services, 'Servicios', Icons.build_outlined,
          services),
      _TabSpec(CatalogWorkspaceTab.categories, 'Categorías',
          Icons.category_outlined, categories),
      _TabSpec(CatalogWorkspaceTab.featured, 'Destacados',
          Icons.star_outline_rounded, featured),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final categoryView = tab == CatalogWorkspaceTab.categories
            ? SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: false, label: Text('En la tienda')),
                  ButtonSegment(value: true, label: Text('Jerarquía')),
                ],
                selected: {hierarchy},
                onSelectionChanged: (value) => onHierarchy(value.first),
              )
            : null;
        final actions = [
          if (categoryView != null && !compact)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: categoryView,
            ),
          compact
              ? IconButton(
                  tooltip: 'Reglas de la tienda',
                  onPressed: loaded
                      ? () => showCatalogRules(context, controller)
                      : null,
                  icon: const Icon(Icons.tune_rounded),
                )
              : TextButton.icon(
                  onPressed: loaded
                      ? () => showCatalogRules(context, controller)
                      : null,
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('Reglas'),
                ),
          IconButton(
            tooltip: 'Abrir vinabike.cl',
            onPressed: () => openCatalogStorePath(context, '/productos'),
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ];
        final strip = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
          child: Row(
            children: [
              for (final spec in tabs)
                _Tab(
                    spec: spec,
                    selected: spec.tab == tab,
                    onTap: () => onPick(spec.tab)),
            ],
          ),
        );
        return Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(bottom: BorderSide(color: roles.hairline)),
          ),
          // The host already names the page: tabs and actions share one row,
          // and on a phone the categories' two views get their own below.
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: strip),
                        ...actions,
                        const SizedBox(width: 4),
                      ],
                    ),
                    if (categoryView != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: categoryView,
                        ),
                      ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: strip),
                    ...actions,
                    const SizedBox(width: 8),
                  ],
                ),
        );
      },
    );
  }
}

class _TabSpec {
  const _TabSpec(this.tab, this.label, this.icon, this.count,
      {this.attention = false});

  final CatalogWorkspaceTab tab;
  final String label;
  final IconData icon;
  final int? count;
  final bool attention;
}

class _Tab extends StatefulWidget {
  const _Tab({required this.spec, required this.selected, required this.onTap});

  final _TabSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  @override
  void initState() {
    super.initState();
    if (widget.selected) _reveal();
  }

  @override
  void didUpdateWidget(_Tab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) _reveal();
  }

  /// On a phone the strip scrolls: the chosen tab (also one picked from
  /// «Resolver») comes into view.
  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 200),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final selected = widget.selected;
    final onTap = widget.onTap;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final foreground = selected ? scheme.onSurface : scheme.onSurfaceVariant;
    final count = spec.count;
    return Semantics(
      button: true,
      selected: selected,
      label: count == null ? spec.label : '${spec.label}, $count',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? scheme.primary : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(spec.icon,
                  size: 18, color: selected ? scheme.primary : foreground),
              const SizedBox(width: 8),
              Text(
                spec.label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: foreground,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: spec.attention
                        ? roles.warning.container
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: spec.attention
                          ? roles.warning.onContainer
                          : foreground,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
