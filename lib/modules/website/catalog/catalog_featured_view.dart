import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_button.dart';
import '../widgets/premium_product_card.dart';
import 'catalog_ui_parts.dart';
import 'catalog_web_controller.dart';
import 'catalog_web_models.dart';

/// «Destacados»: the ordered list a products block shows when it picks
/// «Destacados». The store shows the first ones that are on sale, so a
/// featured product that runs out is replaced by the next one by itself.
class CatalogFeaturedView extends StatefulWidget {
  const CatalogFeaturedView({super.key, required this.controller});

  final CatalogWebController controller;

  @override
  State<CatalogFeaturedView> createState() => _CatalogFeaturedViewState();
}

class _CatalogFeaturedViewState extends State<CatalogFeaturedView> {
  List<CatalogFeaturedSuggestion>? _suggestions;
  String? _suggestionsError;
  final _search = TextEditingController();

  CatalogWebController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _loadSuggestions();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    try {
      final suggestions = await _c.featuredSuggestions(limit: 60, minStock: 2);
      if (mounted) setState(() => _suggestions = _varied(suggestions, 16));
    } catch (error) {
      if (mounted) setState(() => _suggestionsError = '$error');
    }
  }

  /// Best sellers first, one per category until every category had its
  /// turn: a home row of three inner tubes sells less than three different
  /// things (2026-10-10, with the real ranking).
  List<CatalogFeaturedSuggestion> _varied(
    List<CatalogFeaturedSuggestion> ranked,
    int take,
  ) {
    final first = <CatalogFeaturedSuggestion>[];
    final later = <CatalogFeaturedSuggestion>[];
    final seen = <String>{};
    for (final suggestion in ranked) {
      final category =
          _c.itemById(suggestion.productId)?.categoryId ?? suggestion.productId;
      (seen.add(category) ? first : later).add(suggestion);
    }
    return [...first, ...later].take(take).toList();
  }

  Future<void> _replace(List<String> ids, String done) async {
    try {
      await _c.replaceFeatured(ids);
      if (mounted) showCatalogMessage(context, done);
    } catch (error) {
      if (mounted) showCatalogMessage(context, catalogErrorMessage(error));
      // What was offered may have stopped selling meanwhile: show today's.
      unawaited(_c.load(quiet: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final theme = Theme.of(context);
          final scheme = theme.colorScheme;
          final roles = VinabikeThemeRoles.of(context);
          final compact = constraints.maxWidth < 700;
          final side = compact ? 12.0 : 20.0;
          final featured = [
            for (final id in _c.featuredIds)
              if (_c.itemById(id) case final item?) item,
          ];
          final onSale = featured
              .where((item) => item.state == CatalogItemState.selling)
              .toList();
          final suggestions = _suggestions;
          final query = _search.text.trim().toLowerCase();
          final candidates = query.isEmpty
              ? const <CatalogWebItem>[]
              : [
                  for (final item in _c.goods)
                    if (item.state == CatalogItemState.selling &&
                        !_c.featuredIds.contains(item.id) &&
                        item.searchText.contains(query))
                      item,
                ].take(8).toList();

          final shownCount = _c.featuredShown;
          return ListView(
            padding: EdgeInsets.fromLTRB(side, 16, side, 32),
            children: [
              Text('Destacados de la portada',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                shownCount == 0
                    ? 'Ningún bloque del sitio usa «Destacados» todavía: en el editor, bloque «Productos» › Fuente › Destacados.'
                    : 'La portada muestra los primeros $shownCount que estén a la venta, en este orden. '
                        'Si uno se agota, entra el siguiente solo.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              _Panel(
                title: 'Sugeridos por ventas',
                subtitle:
                    'Los más vendidos en 12 meses, a la venta con foto y al menos 2 en stock; uno por categoría antes de repetir.',
                trailing: suggestions == null || suggestions.isEmpty
                    ? null
                    : VbButton(
                        label: 'Usar estos ${suggestions.length}',
                        busy: _c.busy,
                        onPressed: () => _replace(
                          [for (final s in suggestions) s.productId],
                          'Destacados actualizados: ${suggestions.length} en orden de ventas.',
                        ),
                      ),
                child: suggestions == null
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: _suggestionsError == null
                            ? const LinearProgressIndicator()
                            : Text(
                                'No se pudieron leer las ventas: $_suggestionsError'),
                      )
                    : Column(
                        children: [
                          for (final (index, s) in suggestions.indexed)
                            _SuggestionRow(index: index, suggestion: s),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              _Panel(
                title: 'Elegidos (${featured.length})',
                subtitle: featured.isEmpty
                    ? 'Todavía no hay ninguno: la portada no muestra destacados.'
                    : shownCount == 0
                        ? '${onSale.length} a la venta; ningún bloque los muestra todavía.'
                        : '${onSale.length} a la venta: la portada muestra ${onSale.length < shownCount ? onSale.length : shownCount}.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, item) in featured.indexed)
                      _FeaturedRow(
                        index: index,
                        item: item,
                        shown: onSale.take(shownCount).contains(item),
                        busy: _c.busy,
                        onUp: index == 0
                            ? null
                            : () {
                                final ids = [..._c.featuredIds]
                                  ..remove(item.id)
                                  ..insert(index - 1, item.id);
                                _replace(ids, 'Orden guardado.');
                              },
                        onRemove: () => _replace(
                          [
                            for (final id in _c.featuredIds)
                              if (id != item.id) id
                          ],
                          '«${item.displayName}» salió de destacados.',
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                      child: TextField(
                        controller: _search,
                        decoration: const InputDecoration(
                          isDense: true,
                          prefixIcon: Icon(Icons.add, size: 20),
                          hintText: 'Agregar uno que esté a la venta',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    for (final item in candidates)
                      ListTile(
                        dense: true,
                        leading: CatalogThumb(item: item, size: 36),
                        title: Text(item.displayName,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            '${catalogMoney(item.webPrice)} · ${item.sellable} en stock'),
                        trailing: const Icon(Icons.add_circle_outline),
                        onTap: () {
                          _search.clear();
                          _replace([..._c.featuredIds, item.id],
                              '«${item.displayName}» agregado.');
                        },
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              CatalogStorePreview(
                title: 'Así se ven en la portada',
                path: '/',
                note: onSale.isEmpty
                    ? 'Sin destacados a la venta, la sección no muestra nada.'
                    : null,
                child: _HomePreview(
                  items: onSale.take(shownCount == 0 ? 8 : shownCount).toList(),
                  roles: roles,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel(
      {required this.title,
      required this.subtitle,
      required this.child,
      this.trailing});

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      Text(subtitle,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.index, required this.suggestion});

  final int index;
  final CatalogFeaturedSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final margin = suggestion.marginPct;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration:
          BoxDecoration(border: Border(top: BorderSide(color: roles.hairline))),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('${index + 1}',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          // Name above its numbers: one line does not fit a phone.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(suggestion.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  '${suggestion.soldTotal12m} vendidos · ${suggestion.available} en stock'
                  '${margin == null ? '' : ' · margen ${margin.round()} %'}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturedRow extends StatelessWidget {
  const _FeaturedRow({
    required this.index,
    required this.item,
    required this.shown,
    required this.busy,
    required this.onUp,
    required this.onRemove,
  });

  final int index;
  final CatalogWebItem item;
  final bool shown;
  final bool busy;
  final VoidCallback? onUp;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
      decoration:
          BoxDecoration(border: Border(top: BorderSide(color: roles.hairline))),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('${index + 1}',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          CatalogThumb(item: item, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.displayName,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  shown
                      ? 'Se muestra · ${item.sellable} en stock'
                      : item.state == CatalogItemState.selling
                          ? 'De reserva: entra si uno se agota'
                          : 'No se muestra: ${item.reason.toLowerCase()}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: shown
                        ? roles.success.accent
                        : item.state == CatalogItemState.selling
                            ? scheme.onSurfaceVariant
                            : roles.warning.accent,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Subir',
            onPressed: busy ? null : onUp,
            icon: const Icon(Icons.arrow_upward),
          ),
          IconButton(
            tooltip: 'Sacar de destacados',
            onPressed: busy ? null : onRemove,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _HomePreview extends StatelessWidget {
  const _HomePreview({required this.items, required this.roles});

  final List<CatalogWebItem> items;
  final VinabikeThemeRoles roles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (items.isEmpty) {
      return Text('Productos Destacados', style: theme.textTheme.titleLarge);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Productos Destacados',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        SizedBox(
          height: 330,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              return SizedBox(
                width: 210,
                child: PremiumProductCard(
                  productId: item.id,
                  productSku: item.sku,
                  productBrand: item.brand,
                  name: item.displayName,
                  price: item.webPrice,
                  imageUrl: item.imageUrl,
                  showBrand: item.brand != null,
                  interactionsEnabled: false,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
