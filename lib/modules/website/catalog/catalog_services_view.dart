import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_price_list.dart';

import '../../../public_store/widgets/catalog_price_list_view.dart';
import '../../../shared/themes/vinabike_theme_roles.dart';
import '../services/website_service.dart';
import 'catalog_item_detail.dart';
import 'catalog_ui_parts.dart';
import 'catalog_web_controller.dart';
import 'catalog_web_models.dart';

/// «Servicios»: the workshop's price list as /servicios shows it, every
/// service with its switch and how its price reads, and the page itself
/// drawn beside it by the store's own price list.
class CatalogServicesView extends StatefulWidget {
  const CatalogServicesView({super.key, required this.controller});

  final CatalogWebController controller;

  @override
  State<CatalogServicesView> createState() => _CatalogServicesViewState();
}

class _CatalogServicesViewState extends State<CatalogServicesView> {
  final _search = TextEditingController();

  CatalogWebController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _run(Future<Object?> Function() action, {String? done}) async {
    try {
      final result = await action();
      if (!mounted) return;
      final message = result is String ? result : done;
      if (message != null) showCatalogMessage(context, message);
    } catch (error) {
      if (mounted) showCatalogMessage(context, catalogErrorMessage(error));
    }
  }

  void _openDetail(CatalogWebItem item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => ListenableBuilder(
        listenable: _c,
        builder: (context, _) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          builder: (context, scroll) => SingleChildScrollView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: CatalogItemDetail(
              item: _c.itemById(item.id) ?? item,
              controller: _c,
            ),
          ),
        ),
      ),
    );
  }

  void _openPreviewPage() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Así se ve /servicios')),
        body: ListenableBuilder(
          listenable: _c,
          builder: (context, _) => SingleChildScrollView(
            child: _ServicesPagePreview(controller: _c),
          ),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1100;
          final compact = constraints.maxWidth < 600;
          final list = _ServiceList(
            controller: _c,
            search: _search,
            compact: compact,
            onOpen: _openDetail,
            onPreview: wide ? null : _openPreviewPage,
            run: _run,
          );
          if (!wide) return list;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 5, child: list),
              VerticalDivider(
                  width: 1,
                  color: Theme.of(context).colorScheme.outlineVariant),
              Expanded(
                flex: 6,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: CatalogStorePreview(
                    title: 'Así se ve /servicios',
                    path: '/servicios',
                    note:
                        'Se actualiza al momento: apaga un servicio o cambia cómo se muestra su precio y míralo aquí.',
                    child: _ServicesPagePreview(controller: _c),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ServiceList extends StatelessWidget {
  const _ServiceList({
    required this.controller,
    required this.search,
    required this.compact,
    required this.onOpen,
    required this.onPreview,
    required this.run,
  });

  final CatalogWebController controller;
  final TextEditingController search;
  final bool compact;
  final ValueChanged<CatalogWebItem> onOpen;
  final VoidCallback? onPreview;
  final Future<void> Function(Future<Object?> Function() action, {String? done})
      run;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final query = search.text.trim().toLowerCase();
    final services = [
      for (final item in controller.services)
        if (query.isEmpty || item.searchText.contains(query)) item,
    ];
    final byCategory = <String, List<CatalogWebItem>>{};
    for (final item in services) {
      byCategory
          .putIfAbsent(item.categoryName ?? 'Sin categoría', () => [])
          .add(item);
    }
    final categories = byCategory.keys.toList()..sort();
    final published = controller.services
        .where((item) => item.state == CatalogItemState.selling)
        .length;
    final side = compact ? 12.0 : 20.0;

    return ListView(
      padding: EdgeInsets.fromLTRB(side, 16, side, 32),
      children: [
        Text('Servicios',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          '$published de ${controller.services.length} publicados en vinabike.cl/servicios. '
          'Un servicio a \$0 no se publica: si el precio depende del caso, márcalo «A cotizar» o «Desde».',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: search,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: 'Buscar servicio',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            if (onPreview != null) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: onPreview,
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('Ver /servicios'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        for (final category in categories) ...[
          _CategoryBlock(
            name: category,
            items: byCategory[category]!
              ..sort((a, b) => a.displayName.compareTo(b.displayName)),
            controller: controller,
            onOpen: onOpen,
            run: run,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _CategoryBlock extends StatelessWidget {
  const _CategoryBlock({
    required this.name,
    required this.items,
    required this.controller,
    required this.onOpen,
    required this.run,
  });

  final String name;
  final List<CatalogWebItem> items;
  final CatalogWebController controller;
  final ValueChanged<CatalogWebItem> onOpen;
  final Future<void> Function(Future<Object?> Function() action, {String? done})
      run;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final published =
        items.where((item) => item.state == CatalogItemState.selling).length;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(name,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                Text('$published de ${items.length} publicados',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          for (final item in items)
            Container(
              decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: roles.hairline))),
              child: InkWell(
                onTap: () => onOpen(item),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.displayName,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: item.webOn
                                      ? null
                                      : scheme.onSurfaceVariant,
                                )),
                            if (item.state != CatalogItemState.selling)
                              Text(item.reason,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color:
                                        item.state == CatalogItemState.blocked
                                            ? roles.warning.accent
                                            : scheme.onSurfaceVariant,
                                  )),
                          ],
                        ),
                      ),
                      _PriceModeMenu(
                        item: item,
                        enabled: !controller.busy,
                        onPick: (mode) => run(
                          () => controller.setPriceMode(item.id, mode),
                          done:
                              '${item.displayName}: ${mode.label.toLowerCase()}.',
                        ),
                      ),
                      Semantics(
                        label: 'Vender ${item.displayName} en la web',
                        child: Switch(
                          value: item.webOn,
                          onChanged: controller.busy || !item.isActive
                              ? null
                              : (on) => run(
                                    () async => (await controller
                                            .setWebSale([item.id], on: on))
                                        .describe(on: on),
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PriceModeMenu extends StatelessWidget {
  const _PriceModeMenu(
      {required this.item, required this.enabled, required this.onPick});

  final CatalogWebItem item;
  final bool enabled;
  final ValueChanged<CatalogPriceMode> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: 'Precio de ${item.displayName}: ${item.priceLabel}',
      child: PopupMenuButton<CatalogPriceMode>(
        enabled: enabled,
        tooltip: 'Cómo se muestra el precio de ${item.displayName}',
        onSelected: onPick,
        itemBuilder: (context) => [
          for (final mode in CatalogPriceMode.values)
            CheckedPopupMenuItem(
              value: mode,
              checked: mode == item.priceMode,
              child: Text(switch (mode) {
                CatalogPriceMode.exact =>
                  'Precio exacto (${catalogMoney(item.webPrice)})',
                CatalogPriceMode.from => 'Desde ${catalogMoney(item.webPrice)}',
                CatalogPriceMode.quote => 'A cotizar',
              }),
            ),
        ],
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 96),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                item.webPrice <= 0 && item.priceMode != CatalogPriceMode.quote
                    ? '\$0'
                    : item.priceLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const Icon(Icons.arrow_drop_down, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// /servicios with the services that the rule publishes right now, drawn by
/// the same price list the store uses.
class _ServicesPagePreview extends StatelessWidget {
  const _ServicesPagePreview({required this.controller});

  final CatalogWebController controller;

  @override
  Widget build(BuildContext context) {
    WebsiteService? website;
    try {
      website = context.read<WebsiteService>();
    } catch (_) {
      website = null;
    }
    final presentation = website?.catalogPresentationRegistry
            .forCatalogRoot(WebsiteCatalogRoot.services) ??
        WebsiteCatalogPresentation.catalogRoot(WebsiteCatalogRoot.services);
    final categories = {for (final c in controller.categories) c.id: c};
    int compareCategories(String a, String b) {
      final byOrder = (categories[a]?.sortOrder ?? 0)
          .compareTo(categories[b]?.sortOrder ?? 0);
      return byOrder != 0
          ? byOrder
          : (categories[a]?.name ?? '').compareTo(categories[b]?.name ?? '');
    }

    final list = CatalogPriceList.build(
      items: [
        for (final item in controller.services)
          if (item.state == CatalogItemState.selling)
            CatalogPriceItem(
              id: item.id,
              name: item.displayName,
              price: item.webPrice,
              categoryId: item.categoryId ?? '',
              description: controller.serviceText(item.id),
              priceMode: item.priceMode.code,
            ),
      ],
      compareCategories: compareCategories,
      categoryLabel: (id) => categories[id]?.name ?? '',
      plansCategoryId: presentation.plansCategoryId,
    );
    final plans = categories[presentation.plansCategoryId];
    return Theme(
      data: catalogStoreTheme(context),
      child: CatalogPriceListView(
        presentation: presentation,
        list: list,
        title: presentation.heroTitle.trim().isNotEmpty
            ? presentation.heroTitle.trim()
            : 'Servicios',
        intro: presentation.heroDescription.trim(),
        heroImageUrl: presentation.heroImageUrl.trim(),
        rootLabel: 'Servicios',
        plansTitle: plans?.name ?? '',
        plansIntro:
            controller.categoryText(presentation.plansCategoryId).trim(),
      ),
    );
  }
}
