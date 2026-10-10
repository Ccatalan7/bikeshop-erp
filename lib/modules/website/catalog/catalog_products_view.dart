import 'package:flutter/material.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_button.dart';
import 'catalog_item_detail.dart';
import 'catalog_ui_parts.dart';
import 'catalog_web_controller.dart';
import 'catalog_web_models.dart';

/// «Productos»: the catalog by where each item stands in the store, with
/// the reason on every row, one switch per product and bulk actions only on
/// what is selected.
class CatalogProductsView extends StatefulWidget {
  const CatalogProductsView({
    super.key,
    required this.controller,
    this.onOpenResolve,
  });

  final CatalogWebController controller;

  /// Opens «Por resolver».
  final VoidCallback? onOpenResolve;

  @override
  State<CatalogProductsView> createState() => _CatalogProductsViewState();
}

class _CatalogProductsViewState extends State<CatalogProductsView> {
  final _search = TextEditingController();
  CatalogItemState _state = CatalogItemState.selling;
  final Set<String> _selected = {};
  String? _openId;

  static const _wide = 1080.0;

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

  List<CatalogWebItem> _rows() {
    final query = _search.text.trim().toLowerCase();
    final rows = [
      for (final item in widget.controller.goods)
        if (item.state == _state &&
            (query.isEmpty || item.searchText.contains(query)))
          item,
    ];
    int byName(CatalogWebItem a, CatalogWebItem b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    switch (_state) {
      case CatalogItemState.selling:
        rows.sort((a, b) {
          final byStock = a.sellable.compareTo(b.sellable);
          return byStock != 0 ? byStock : byName(a, b);
        });
      case CatalogItemState.soldOut:
        rows.sort((a, b) {
          final bySales = b.soldTotal12m.compareTo(a.soldTotal12m);
          return bySales != 0 ? bySales : byName(a, b);
        });
      case CatalogItemState.blocked:
        rows.sort((a, b) {
          final byStock =
              (b.sellable > 0 ? 1 : 0).compareTo(a.sellable > 0 ? 1 : 0);
          if (byStock != 0) return byStock;
          final byValue = b.stockValue.compareTo(a.stockValue);
          return byValue != 0 ? byValue : b.webPrice.compareTo(a.webPrice);
        });
      case CatalogItemState.hidden:
        rows.sort((a, b) {
          final byStock = b.sellable.compareTo(a.sellable);
          return byStock != 0 ? byStock : b.webPrice.compareTo(a.webPrice);
        });
      case CatalogItemState.workshop:
        rows.sort((a, b) {
          final byUse = (b.soldCounter12m + b.usedJobs12m)
              .compareTo(a.soldCounter12m + a.usedJobs12m);
          return byUse != 0 ? byUse : byName(a, b);
        });
    }
    return rows;
  }

  String _order() => switch (_state) {
        CatalogItemState.selling => 'menos stock primero',
        CatalogItemState.soldOut => 'más vendidos en 12 meses',
        CatalogItemState.blocked => 'con stock primero',
        CatalogItemState.hidden => 'con stock primero',
        CatalogItemState.workshop => 'más usados primero',
      };

  void _pickState(CatalogItemState state) => setState(() {
        _state = state;
        _selected.clear();
        _openId = null;
      });

  Future<void> _bulk(bool on) async {
    final ids = _selected.toList();
    try {
      final result = await widget.controller.setWebSale(ids, on: on);
      if (!mounted) return;
      setState(_selected.clear);
      showCatalogMessage(context, result.describe(on: on));
    } catch (error) {
      if (mounted) showCatalogMessage(context, catalogErrorMessage(error));
    }
  }

  void _open(CatalogWebItem item, {required bool wide}) {
    if (wide) {
      setState(() => _openId = _openId == item.id ? null : item.id);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final current = widget.controller.itemById(item.id) ?? item;
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.9,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (context, scroll) => SingleChildScrollView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: CatalogItemDetail(
                item: current,
                controller: widget.controller,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= _wide;
          final compact = constraints.maxWidth < 600;
          final rows = _rows();
          final open =
              _openId == null ? null : widget.controller.itemById(_openId!);
          final list = _List(
            rows: rows,
            compact: compact,
            selected: _selected,
            openId: wide ? _openId : null,
            onToggle: (id) => setState(() {
              if (!_selected.remove(id)) _selected.add(id);
            }),
            onOpen: (item) => _open(item, wide: wide),
            footer:
                '${rows.length} ${rows.length == 1 ? 'producto' : 'productos'} · ${_order()}',
          );
          final body = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                controller: widget.controller,
                state: _state,
                search: _search,
                compact: compact,
                onPick: _pickState,
                onOpenResolve: widget.onOpenResolve,
              ),
              if (_selected.isNotEmpty)
                _SelectionBar(
                  count: _selected.length,
                  workshop: _state == CatalogItemState.workshop,
                  busy: widget.controller.busy,
                  onOn: () => _bulk(true),
                  onOff: () => _bulk(false),
                  onClear: () => setState(_selected.clear),
                ),
              Expanded(child: list),
            ],
          );
          if (!wide || open == null) return body;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: body),
              VerticalDivider(
                  width: 1,
                  color: Theme.of(context).colorScheme.outlineVariant),
              SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: CatalogItemDetail(
                    key: ValueKey(open.id),
                    item: open,
                    controller: widget.controller,
                    onClose: () => setState(() => _openId = null),
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

class _Header extends StatelessWidget {
  const _Header({
    required this.controller,
    required this.state,
    required this.search,
    required this.compact,
    required this.onPick,
    required this.onOpenResolve,
  });

  final CatalogWebController controller;
  final CatalogItemState state;
  final TextEditingController search;
  final bool compact;
  final ValueChanged<CatalogItemState> onPick;
  final VoidCallback? onOpenResolve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final scheme = theme.colorScheme;
    final blockedWithStock = controller.goods
        .where((item) =>
            item.state == CatalogItemState.blocked && item.sellable > 0)
        .toList();
    final pad = EdgeInsets.symmetric(horizontal: compact ? 12 : 20);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        Padding(
          padding: pad,
          child: TextField(
            controller: search,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              hintText: 'Nombre, SKU, código de barras o marca',
              border: const OutlineInputBorder(),
              suffixIcon: search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpiar búsqueda',
                      onPressed: search.clear,
                      icon: const Icon(Icons.close, size: 18),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: pad,
          child: Row(
            children: [
              for (final s in CatalogItemState.values) ...[
                _StateTab(
                  state: s,
                  count: controller.countGoods(s),
                  selected: s == state,
                  onTap: () => onPick(s),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        if (blockedWithStock.isNotEmpty && onOpenResolve != null) ...[
          const SizedBox(height: 10),
          Padding(
            padding: pad,
            child: Material(
              color: roles.warning.container,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onOpenResolve,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Icon(Icons.trending_down,
                            size: 20, color: roles.warning.onContainer),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${blockedWithStock.length} con stock no salen a la venta '
                            '(${catalogMoney(blockedWithStock.fold<double>(0, (sum, item) => sum + item.stockValue))} a precio web)',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: roles.warning.onContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text('Resolver',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: roles.warning.onContainer,
                              fontWeight: FontWeight.w700,
                            )),
                        Icon(Icons.chevron_right,
                            color: roles.warning.onContainer),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        Padding(
          padding: pad.copyWith(top: 10, bottom: 8),
          child: Text(
            state.meaning,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _StateTab extends StatelessWidget {
  const _StateTab({
    required this.state,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final CatalogItemState state;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '${state.pluralLabel}: $count',
      excludeSemantics: true,
      child: Material(
        color: selected ? scheme.surface : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: selected ? scheme.onSurface : scheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: catalogStateDot(context, state),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(state.pluralLabel,
                      style: theme.textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Text(
                    '$count',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
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

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.workshop,
    required this.busy,
    required this.onOn,
    required this.onOff,
    required this.onClear,
  });

  final int count;
  final bool workshop;
  final bool busy;
  final VoidCallback onOn;
  final VoidCallback onOff;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Text(
            count == 1 ? '1 seleccionado' : '$count seleccionados',
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onInverseSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (workshop)
            Text('Los consumibles no se venden online.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onInverseSurface))
          else ...[
            FilledButton.tonal(
              onPressed: busy ? null : onOn,
              child: const Text('Vender en la web'),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.onInverseSurface,
                side: BorderSide(
                    color: scheme.onInverseSurface.withValues(alpha: 0.5)),
              ),
              onPressed: busy ? null : onOff,
              child: const Text('Dejar de vender'),
            ),
          ],
          TextButton(
            style:
                TextButton.styleFrom(foregroundColor: scheme.onInverseSurface),
            onPressed: onClear,
            child: const Text('Quitar selección'),
          ),
        ],
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({
    required this.rows,
    required this.compact,
    required this.selected,
    required this.openId,
    required this.onToggle,
    required this.onOpen,
    required this.footer,
  });

  final List<CatalogWebItem> rows;
  final bool compact;
  final Set<String> selected;
  final String? openId;
  final ValueChanged<String> onToggle;
  final ValueChanged<CatalogWebItem> onOpen;
  final String footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (rows.isEmpty) {
      return const CatalogEmpty(
        title: 'Nada por aquí',
        body: 'Ningún producto está en este estado con esa búsqueda.',
      );
    }
    final itemExtent = compact ? 92.0 : 64.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!compact) const _TableHeader(),
        Expanded(
          child: ListView.builder(
            itemExtent: itemExtent,
            itemCount: rows.length + 1,
            itemBuilder: (context, index) {
              if (index == rows.length) {
                return Center(
                  child: Text(footer,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                );
              }
              final item = rows[index];
              return compact
                  ? _Card(
                      item: item,
                      selected: selected.contains(item.id),
                      onToggle: () => onToggle(item.id),
                      onOpen: () => onOpen(item),
                    )
                  : _Row(
                      item: item,
                      selected: selected.contains(item.id),
                      open: openId == item.id,
                      onToggle: () => onToggle(item.id),
                      onOpen: () => onOpen(item),
                    );
            },
          ),
        ),
      ],
    );
  }
}

const _columns = <int>[3, 2, 0, 0, 0, 2];

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
      decoration: BoxDecoration(
        border:
            Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 44),
          Expanded(flex: _columns[0], child: Text('PRODUCTO', style: style)),
          Expanded(
              flex: _columns[1],
              child: Text('CATEGORÍA · MARCA', style: style)),
          SizedBox(
              width: 72,
              child: Text('STOCK', style: style, textAlign: TextAlign.right)),
          SizedBox(
              width: 100,
              child: Text('PRECIO', style: style, textAlign: TextAlign.right)),
          SizedBox(
              width: 76,
              child: Text('MARGEN', style: style, textAlign: TextAlign.right)),
          const SizedBox(width: 20),
          Expanded(
              flex: _columns[5], child: Text('ESTADO Y MOTIVO', style: style)),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.item,
    required this.selected,
    required this.open,
    required this.onToggle,
    required this.onOpen,
  });

  final CatalogWebItem item;
  final bool selected;
  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final margin = item.marginPct;
    final numbers = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Material(
      color: open ? roles.selectionContainer : Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: open ? scheme.primary : Colors.transparent,
                width: 3,
              ),
              bottom: BorderSide(color: roles.hairline),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Checkbox(
                  value: selected,
                  onChanged: (_) => onToggle(),
                  semanticLabel: 'Seleccionar ${item.displayName}',
                ),
              ),
              Expanded(
                flex: _columns[0],
                child: Row(
                  children: [
                    CatalogThumb(item: item, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          Text(
                            [
                              if (item.sku.isNotEmpty) item.sku,
                              if (item.hasWebName)
                                item.name
                              else if (item.kind.sellsGoods &&
                                  item.state != CatalogItemState.workshop)
                                'sin nombre para la tienda',
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: _columns[1],
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.categoryName ?? 'Sin categoría',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall),
                    Text(item.brand ?? 'Sin marca',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: item.brand == null
                              ? roles.warning.accent
                              : scheme.onSurfaceVariant,
                        )),
                  ],
                ),
              ),
              SizedBox(
                width: 72,
                child: Text(
                  item.kind == CatalogItemKind.consumable
                      ? 'No lleva'
                      : item.available == null
                          ? '—'
                          : '${item.sellable}',
                  textAlign: TextAlign.right,
                  style: numbers?.copyWith(
                    color: item.sellable > 0 ? null : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              SizedBox(
                width: 100,
                child: Text(catalogMoney(item.webPrice),
                    textAlign: TextAlign.right,
                    style: numbers?.copyWith(fontWeight: FontWeight.w600)),
              ),
              SizedBox(
                width: 76,
                child: Text(
                  margin == null ? '—' : '${margin.round()} %',
                  textAlign: TextAlign.right,
                  style: numbers?.copyWith(
                    color: margin != null && margin < 0
                        ? roles.danger.accent
                        : margin == null
                            ? scheme.onSurfaceVariant
                            : null,
                    fontWeight:
                        margin != null && margin < 0 ? FontWeight.w700 : null,
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: _columns[5],
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CatalogStateBadge(item.state, dense: true),
                    const SizedBox(height: 3),
                    Text(
                      item.kind == CatalogItemKind.consumable
                          ? _usage(item)
                          : item.reason,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _usage(CatalogWebItem item) {
  final parts = <String>[
    if (item.usedJobs12m > 0) '${item.usedJobs12m} en trabajos',
    if (item.soldCounter12m > 0) '${item.soldCounter12m} al mesón',
  ];
  return parts.isEmpty ? 'Sin uso en 12 meses' : parts.join(' · ');
}

class _Card extends StatelessWidget {
  const _Card({
    required this.item,
    required this.selected,
    required this.onToggle,
    required this.onOpen,
  });

  final CatalogWebItem item;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final margin = item.marginPct;
    return InkWell(
      onTap: onOpen,
      onLongPress: onToggle,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: selected ? roles.selectionContainer : null,
          border: Border(bottom: BorderSide(color: roles.hairline)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CatalogThumb(item: item, size: 56),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (item.sku.isNotEmpty) item.sku,
                      if (item.kind == CatalogItemKind.consumable)
                        _usage(item)
                      else ...[
                        item.sellable > 0
                            ? '${item.sellable} en stock'
                            : 'sin stock',
                        if (margin != null) 'margen ${margin.round()} %',
                      ],
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      CatalogStateBadge(item.state, dense: true),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.state == CatalogItemState.selling
                              ? ''
                              : item.reason,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(catalogMoney(item.webPrice),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
            if (selected)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child:
                    Icon(Icons.check_circle, size: 20, color: scheme.primary),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shown while the projection loads or when it fails.
class CatalogLoadState extends StatelessWidget {
  const CatalogLoadState({super.key, required this.controller});

  final CatalogWebController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('No se pudo leer el catálogo.',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Text(controller.error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              VbButton(label: 'Reintentar', onPressed: controller.load),
            ],
          ),
        ),
      );
    }
    return const Center(child: CircularProgressIndicator());
  }
}
