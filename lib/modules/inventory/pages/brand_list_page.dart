import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/services/workspace_manager.dart';
import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/utils/responsive_viewport.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/vb_button.dart';
import '../../../shared/widgets/vb_search_field.dart';
import '../../../shared/widgets/vb_segmented.dart';
import '../../../shared/widgets/vb_status_badge.dart';
import '../../../shared/widgets/vb_view_tabs.dart';
import '../../purchases/widgets/brand_mark.dart';
import '../models/brand_directory.dart';
import '../services/brand_directory_service.dart';
import '../widgets/brand_directory_parts.dart';

/// Cómo se ve la lista de marcas: tabla o tarjetas con fotos.
enum BrandListLayout { list, cards }

/// Inventario › Marcas (rediseño del 2026-11-15, lienzo
/// UGbrLwz7St2n7hcP3cBvvf aprobado por el dueño): las marcas con lo que dicen
/// en el taller —productos, stock, lo vendido, quién la trae—, en lista o en
/// tarjetas, con vistas y su conteo en la línea del título. Cada marca abre su
/// página.
///
/// Lo que la lista anterior dejaba hacer sigue: buscar (ahora también por
/// proveedor), crear una marca y editarla, activarla o eliminarla, que pasaron
/// a la página de la marca. El filtro por país y «Solo inactivas» se fueron:
/// 279 de 280 marcas no tienen país y ninguna está inactiva (2026-11-14).
class BrandListPage extends StatefulWidget {
  const BrandListPage({
    super.key,
    this.source,
    this.includeWorkspaceShell = true,
  });

  /// Para pruebas: de dónde lee el directorio.
  final BrandDirectorySource? source;

  /// Para pruebas: la página sin el marco del ERP (menú y encabezado).
  final bool includeWorkspaceShell;

  @override
  State<BrandListPage> createState() => _BrandListPageState();
}

class _BrandListPageState extends State<BrandListPage> {
  static const int _pageSize = 60;

  late final BrandDirectorySource _source =
      widget.source ?? BrandDirectoryService();
  final TextEditingController _search = TextEditingController();

  List<BrandDirectoryEntry> _entries = const [];
  bool _loading = true;
  String? _error;
  int _generation = 0;

  BrandListView _view = BrandListView.withProducts;
  BrandListLayout _layout = BrandListLayout.list;
  BrandSort _sort = BrandSort.sold;
  bool _descending = true;
  String _query = '';
  int _visible = _pageSize;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _error = null;
      if (_entries.isEmpty) _loading = true;
    });
    try {
      final entries = await _source.directory();
      if (!mounted || generation != _generation) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (error) {
      debugPrint('Brand directory load failed: $error');
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = 'No pudimos leer las marcas.';
        _loading = false;
      });
    }
  }

  // ── Lo que cambia la vista ───────────────────────────────────────────────

  void _setView(BrandListView view) => setState(() {
        _view = view;
        _visible = _pageSize;
      });

  void _setLayout(BrandListLayout layout) => setState(() {
        _layout = layout;
        _visible = _pageSize;
      });

  /// Tocar la columna que ya ordena da vuelta el sentido; otra, empieza por
  /// su sentido natural (las cifras de más a menos, los nombres de la A a la Z).
  void _setSort(BrandSort sort) => setState(() {
        if (_sort == sort) {
          _descending = !_descending;
        } else {
          _sort = sort;
          _descending = sort.descendingFirst;
        }
        _visible = _pageSize;
      });

  void _setQuery(String value) => setState(() {
        _query = value.trim();
        _visible = _pageSize;
      });

  void _clearQuery() {
    _search.clear();
    _setQuery('');
  }

  /// Se empuja por el espacio de trabajo y no con `context.push`: al volver,
  /// la pestaña vuelve a decir «Marcas» (con `context.push` se quedaba en
  /// «Marca»). Al volver se relee por si algo cambió allá.
  Future<void> _push(String route) async {
    WorkspaceManager? workspace;
    try {
      workspace = context.read<WorkspaceManager>();
    } on ProviderNotFoundException {
      workspace = null;
    }
    if (workspace != null) {
      await workspace.pushActiveWorkspace<void>(route);
    } else {
      await context.push<void>(route);
    }
    if (mounted) await _load();
  }

  Future<void> _openBrand(BrandDirectoryEntry entry) =>
      _push('/inventory/brands/${entry.id}');

  Future<void> _newBrand() => _push('/inventory/brands/new');

  // ── Lo que se cuenta ─────────────────────────────────────────────────────

  int _countOf(BrandListView view) =>
      _entries.where((entry) => view.includes(entry)).length;

  ({List<BrandDirectoryEntry> rows, int elsewhere}) _shown() {
    final base = brandDirectoryRows(
      _entries,
      view: _view,
      sort: _sort,
      descending: _descending,
    );
    if (_query.isEmpty) return (rows: base, elsewhere: 0);
    final found = searchBrandDirectory(base, _query);
    final everywhere = _view == BrandListView.all
        ? found.length
        : searchBrandDirectory(_entries, _query).length;
    return (rows: found, elsewhere: everywhere - found.length);
  }

  num get _maxSold => _entries.fold<num>(
      0, (max, entry) => entry.sold12m > max ? entry.sold12m : max);

  String get _summary {
    if (_loading && _entries.isEmpty) return 'Cargando…';
    return '${brandCount(_countOf(BrandListView.withProducts))} con productos · '
        '${brandCount(_entries.length)} en total';
  }

  List<VbViewTab<BrandListView>> get _tabs => [
        for (final view in BrandListView.values)
          VbViewTab(value: view, label: view.label, count: _countOf(view)),
      ];

  // ── Página ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final compact = ResponsiveViewport.usesCompactShell(context);
    final body = ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: compact ? _buildCompact(context) : _buildWide(context),
    );
    if (!widget.includeWorkspaceShell) return Material(child: body);
    return MainLayout(
      title: 'Marcas',
      compactHeader: compact
          ? MainLayoutCompactHeader(
              title: 'Marcas',
              contextLine: _summary,
              search: MainLayoutCompactSearch(
                controller: _search,
                onChanged: _setQuery,
                onClear: _clearQuery,
                hintText: 'Marca o proveedor',
              ),
              actions: [
                IconButton(
                  tooltip: 'Nueva marca',
                  onPressed: _newBrand,
                  icon: const Icon(Icons.add),
                ),
              ],
            )
          : null,
      body: body,
    );
  }

  Widget _buildWide(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WideHeader(
          tabs: _tabs,
          view: _view,
          onView: _setView,
          search: _search,
          onQuery: _setQuery,
          onClear: _clearQuery,
          layout: _layout,
          onLayout: _setLayout,
          onCreate: _newBrand,
        ),
        Divider(height: 1, thickness: 1, color: roles.hairline),
        if (_error != null) _buildErrorBanner(context),
        Expanded(child: _buildWideContent(context)),
      ],
    );
  }

  Widget _buildWideContent(BuildContext context) {
    if (_loading && _entries.isEmpty) {
      return const Center(child: BrandedLoading());
    }
    final shown = _shown();
    final rows = shown.rows;
    if (rows.isEmpty) {
      return _buildEmpty(context, elsewhere: shown.elsewhere);
    }
    final visible = rows.take(_visible).toList(growable: false);
    final footer = _Footer(
      text: _footerText(shown: rows.length),
      elsewhere: shown.elsewhere,
      canShowMore: _visible < rows.length,
      onShowMore: () => setState(() => _visible += _pageSize),
      onShowAll: () => _setView(BrandListView.all),
    );
    if (_layout == BrandListLayout.cards) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        children: [
          _SortStrip(sort: _sort, onSort: _setSort),
          const SizedBox(height: 12),
          _BrandCardGrid(rows: visible, onOpen: _openBrand),
          const SizedBox(height: 8),
          footer,
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _TableColumns(constraints.maxWidth);
        final maxSold = _maxSold;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TableHeader(
              columns: columns,
              sort: _sort,
              descending: _descending,
              onSort: _setSort,
            ),
            Expanded(
              child: ListView.builder(
                itemCount: visible.length + 1,
                itemBuilder: (context, index) {
                  if (index == visible.length) return footer;
                  final entry = visible[index];
                  return _BrandTableRow(
                    entry: entry,
                    columns: columns,
                    maxSold: maxSold,
                    onOpen: () => _openBrand(entry),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  String _footerText({required int shown}) {
    final visible = _visible < shown ? _visible : shown;
    if (_query.isNotEmpty) {
      return '${brandCount(visible)} de ${brandCount(shown)} que coinciden';
    }
    final where = switch (_view) {
      BrandListView.withProducts => 'marcas con productos',
      BrandListView.inStock => 'marcas con stock',
      BrandListView.noLogo => 'marcas sin logo',
      BrandListView.all => 'marcas',
    };
    return '${brandCount(visible)} de ${brandCount(shown)} $where · '
        '${_sort.phrase(descending: _descending)}';
  }

  Widget _buildErrorBanner(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    final message = _entries.isEmpty
        ? _error!
        : '${_error!} Lo que ves puede estar desactualizado.';
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(
          color: roles.warning.container,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: roles.warning.border),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 18, color: roles.warning.onContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: TextStyle(color: roles.warning.onContainer)),
            ),
            VbButton(
              label: 'Reintentar',
              variant: VbButtonVariant.text,
              icon: Icons.refresh,
              onPressed: _load,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, {required int elsewhere}) {
    final scheme = Theme.of(context).colorScheme;
    if (_error != null && _entries.isEmpty) return const SizedBox.shrink();
    final message = _query.isNotEmpty
        ? 'Ninguna marca de esta vista coincide con «$_query».'
        : switch (_view) {
            BrandListView.withProducts =>
              'Todavía no hay marcas con productos.',
            BrandListView.inStock => 'Ninguna marca tiene stock ahora.',
            BrandListView.noLogo => 'Todas las marcas tienen su logo.',
            BrandListView.all => 'Todavía no hay marcas.',
          };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant),
            ),
            if (_query.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (elsewhere > 0)
                    VbButton(
                      label: 'Ver ${brandCount(elsewhere)} en «Todas»',
                      onPressed: () => _setView(BrandListView.all),
                    ),
                  VbButton(
                    label: 'Limpiar búsqueda',
                    variant: VbButtonVariant.secondary,
                    onPressed: _clearQuery,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Teléfono ─────────────────────────────────────────────────────────────

  Widget _buildCompact(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    final scheme = Theme.of(context).colorScheme;
    final shown = _shown();
    final rows = shown.rows;
    final visible = rows.take(_visible).toList(growable: false);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: VbViewTabs<BrandListView>(
              tabs: _tabs,
              value: _view,
              onChanged: _setView,
              spacing: 20,
            ),
          ),
          Divider(height: 1, thickness: 1, color: roles.hairline),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: _SortStrip(sort: _sort, onSort: _setSort, dense: true),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 150,
                  child: VbSegmented<BrandListLayout>(
                    groupLabel: 'Ver como',
                    value: _layout,
                    onChanged: _setLayout,
                    options: const [
                      VbSegmentedOption(
                          value: BrandListLayout.list, label: 'Lista'),
                      VbSegmentedOption(
                          value: BrandListLayout.cards, label: 'Tarjetas'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) _buildErrorBanner(context),
          if (_loading && _entries.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: BrandedLoading()),
            )
          else if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: _buildEmpty(context, elsewhere: shown.elsewhere),
            )
          else if (_layout == BrandListLayout.cards)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: _BrandCardGrid(rows: visible, onOpen: _openBrand),
            )
          else
            for (var index = 0; index < visible.length; index++)
              _BrandCompactRow(
                entry: visible[index],
                divider: index > 0,
                onOpen: () => _openBrand(visible[index]),
              ),
          if (rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _footerText(shown: rows.length),
                    style:
                        TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                  ),
                  if (_visible < rows.length) ...[
                    const SizedBox(height: 10),
                    VbButton(
                      label: 'Ver más',
                      variant: VbButtonVariant.secondary,
                      expand: true,
                      onPressed: () => setState(() => _visible += _pageSize),
                    ),
                  ],
                  if (shown.elsewhere > 0)
                    VbButton(
                      label: '${brandCount(shown.elsewhere)} más en «Todas»',
                      variant: VbButtonVariant.text,
                      expand: true,
                      onPressed: () => _setView(BrandListView.all),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Encabezado ─────────────────────────────────────────────────────────────

/// Una línea: título, vistas con su conteo, y a la derecha el buscador, la
/// forma de ver y «Nueva marca». En un ancho menor, las herramientas bajan a
/// una segunda línea; nunca un bloque de cifras sobre la lista.
class _WideHeader extends StatelessWidget {
  const _WideHeader({
    required this.tabs,
    required this.view,
    required this.onView,
    required this.search,
    required this.onQuery,
    required this.onClear,
    required this.layout,
    required this.onLayout,
    required this.onCreate,
  });

  final List<VbViewTab<BrandListView>> tabs;
  final BrandListView view;
  final ValueChanged<BrandListView> onView;
  final TextEditingController search;
  final ValueChanged<String> onQuery;
  final VoidCallback onClear;
  final BrandListLayout layout;
  final ValueChanged<BrandListLayout> onLayout;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = Semantics(
      header: true,
      child: Text(
        'Marcas',
        style: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: scheme.onSurface,
        ),
      ),
    );
    final viewTabs = VbViewTabs<BrandListView>(
      tabs: tabs,
      value: view,
      onChanged: onView,
    );
    final tools = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 260,
          child: VbSearchField(
            fieldKey: const ValueKey('brand-list-search'),
            controller: search,
            hint: 'Marca o proveedor',
            onChanged: onQuery,
            onClear: onClear,
            semanticLabel: 'Buscar marcas',
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 190,
          child: VbSegmented<BrandListLayout>(
            groupLabel: 'Ver como',
            value: layout,
            onChanged: onLayout,
            options: const [
              VbSegmentedOption(value: BrandListLayout.list, label: 'Lista'),
              VbSegmentedOption(
                  value: BrandListLayout.cards, label: 'Tarjetas'),
            ],
          ),
        ),
        const SizedBox(width: 10),
        VbButton(
          label: 'Nueva marca',
          icon: Icons.add,
          onPressed: onCreate,
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final oneLine = constraints.maxWidth >= 1180;
        if (oneLine) {
          // Las pestañas toman lo que sobra y se deslizan si no caben: con
          // conteos de cuatro cifras o una letra más ancha, la fila no se
          // rompe.
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                title,
                const SizedBox(width: 28),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: viewTabs,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: tools,
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [title, const SizedBox(width: 28), viewTabs],
                ),
              ),
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: tools),
            ],
          ),
        );
      },
    );
  }
}

/// El orden de las tarjetas y del teléfono, a la vista: no hay columnas que
/// tocar, y elegir no abre un menú flotante.
class _SortStrip extends StatelessWidget {
  const _SortStrip({
    required this.sort,
    required this.onSort,
    this.dense = false,
  });

  final BrandSort sort;
  final ValueChanged<BrandSort> onSort;
  final bool dense;

  static const _options = <(BrandSort, String)>[
    (BrandSort.sold, 'Más vendidas'),
    (BrandSort.products, 'Más productos'),
    (BrandSort.stockCost, 'Más stock a costo'),
    (BrandSort.name, 'A–Z'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (!dense) ...[
            Text(
              'ORDENAR',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: roles.faintForeground,
              ),
            ),
            const SizedBox(width: 16),
          ],
          for (final (value, label) in _options) ...[
            Semantics(
              button: true,
              selected: sort == value,
              child: InkWell(
                onTap: () => onSort(value),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 40),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: sort == value
                            ? scheme.onSurface
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          sort == value ? FontWeight.w600 : FontWeight.w400,
                      color: sort == value
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.text,
    required this.elsewhere,
    required this.canShowMore,
    required this.onShowMore,
    required this.onShowAll,
  });

  final String text;
  final int elsewhere;
  final bool canShowMore;
  final VoidCallback onShowMore;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: roles.hairline)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 8,
        children: [
          Text(
            text,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          if (elsewhere > 0)
            VbButton(
              label: '${brandCount(elsewhere)} más en «Todas»',
              variant: VbButtonVariant.text,
              onPressed: onShowAll,
            ),
          if (canShowMore)
            VbButton(
              label: 'Ver más',
              variant: VbButtonVariant.secondary,
              onPressed: onShowMore,
            ),
        ],
      ),
    );
  }
}

// ── Tabla ──────────────────────────────────────────────────────────────────

/// Qué columnas caben. La tabla llega a los bordes y, si el ancho no alcanza,
/// suelta primero lo que menos se mira; nunca se vuelve una tabla en miniatura
/// con barra horizontal.
class _TableColumns {
  _TableColumns(double width)
      : showCost = width >= 1080,
        showWeb = width >= 1200;

  final bool showCost;
  final bool showWeb;

  static const double products = 88;
  static const double inStock = 92;
  static const double cost = 120;
  static const double sold = 150;
  static const double lastSale = 100;
  static const double web = 84;
  static const double gap = 16;
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({
    required this.columns,
    required this.sort,
    required this.descending,
    required this.onSort,
  });

  final _TableColumns columns;
  final BrandSort sort;
  final bool descending;
  final ValueChanged<BrandSort> onSort;

  @override
  Widget build(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    Widget cell(BrandSort value, {bool end = false}) => _HeaderCell(
          sort: value,
          active: sort == value,
          descending: descending,
          end: end,
          onTap: () => onSort(value),
        );
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: roles.hairline)),
      ),
      child: Row(
        children: [
          Expanded(flex: 13, child: cell(BrandSort.name)),
          const SizedBox(width: _TableColumns.gap),
          Expanded(flex: 10, child: cell(BrandSort.supplier)),
          const SizedBox(width: _TableColumns.gap),
          SizedBox(
              width: _TableColumns.products,
              child: cell(BrandSort.products, end: true)),
          const SizedBox(width: _TableColumns.gap),
          SizedBox(
              width: _TableColumns.inStock,
              child: cell(BrandSort.inStock, end: true)),
          if (columns.showCost) ...[
            const SizedBox(width: _TableColumns.gap),
            SizedBox(
                width: _TableColumns.cost,
                child: cell(BrandSort.stockCost, end: true)),
          ],
          const SizedBox(width: _TableColumns.gap),
          SizedBox(
              width: _TableColumns.sold,
              child: cell(BrandSort.sold, end: true)),
          const SizedBox(width: _TableColumns.gap),
          SizedBox(
              width: _TableColumns.lastSale,
              child: cell(BrandSort.lastSale, end: true)),
          if (columns.showWeb) ...[
            const SizedBox(width: _TableColumns.gap),
            SizedBox(
                width: _TableColumns.web,
                child: cell(BrandSort.onWeb, end: true)),
          ],
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.sort,
    required this.active,
    required this.descending,
    required this.end,
    required this.onTap,
  });

  final BrandSort sort;
  final bool active;
  final bool descending;
  final bool end;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? scheme.onSurface : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: active,
      label: active
          ? 'Ordenado por ${sort.label.toLowerCase()}, '
              '${descending ? 'de mayor a menor' : 'de menor a mayor'}'
          : 'Ordenar por ${sort.label.toLowerCase()}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Row(
          mainAxisAlignment:
              end ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                sort.label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: color,
                ),
              ),
            ),
            if (active) ...[
              const SizedBox(width: 4),
              Icon(
                descending ? Icons.arrow_downward : Icons.arrow_upward,
                size: 13,
                color: color,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BrandTableRow extends StatelessWidget {
  const _BrandTableRow({
    required this.entry,
    required this.columns,
    required this.maxSold,
    required this.onOpen,
  });

  final BrandDirectoryEntry entry;
  final _TableColumns columns;
  final num maxSold;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    TextStyle figure(num value) => TextStyle(
          fontSize: 14,
          color: value > 0 ? scheme.onSurface : roles.faintForeground,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
    final lastSale = entry.lastSale;
    final lastSaleLabel = lastSale == null ? '—' : brandDayLabel(lastSale);
    return Semantics(
      button: true,
      label: 'Abrir la marca ${entry.name}',
      child: InkWell(
        key: ValueKey('brand-row-${entry.id}'),
        onTap: onOpen,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: roles.hairline)),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 13,
                child: Row(
                  children: [
                    BrandMark(
                      name: entry.name,
                      logoUrl: entry.logoUrl,
                      size: 34,
                      solid: true,
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    if (!entry.isActive) ...[
                      const SizedBox(width: 8),
                      const VbStatusBadge(
                        label: 'Inactiva',
                        tone: VbStatusTone.neutral,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: _TableColumns.gap),
              Expanded(flex: 10, child: BrandSupplierLine(entry: entry)),
              const SizedBox(width: _TableColumns.gap),
              SizedBox(
                width: _TableColumns.products,
                child: Text(brandCount(entry.products),
                    textAlign: TextAlign.right,
                    style: figure(entry.products)),
              ),
              const SizedBox(width: _TableColumns.gap),
              SizedBox(
                width: _TableColumns.inStock,
                child: Text(brandCount(entry.inStock),
                    textAlign: TextAlign.right, style: figure(entry.inStock)),
              ),
              if (columns.showCost) ...[
                const SizedBox(width: _TableColumns.gap),
                SizedBox(
                  width: _TableColumns.cost,
                  child: Text(
                    entry.stockCost > 0 ? brandMoney(entry.stockCost) : '—',
                    textAlign: TextAlign.right,
                    style: figure(entry.stockCost),
                  ),
                ),
              ],
              const SizedBox(width: _TableColumns.gap),
              SizedBox(
                width: _TableColumns.sold,
                child: BrandSoldBar(sold: entry.sold12m, max: maxSold),
              ),
              const SizedBox(width: _TableColumns.gap),
              SizedBox(
                width: _TableColumns.lastSale,
                child: Text(
                  lastSaleLabel,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: lastSaleLabel == 'hoy'
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: lastSale == null
                        ? roles.faintForeground
                        : scheme.onSurface,
                  ),
                ),
              ),
              if (columns.showWeb) ...[
                const SizedBox(width: _TableColumns.gap),
                SizedBox(
                  width: _TableColumns.web,
                  child: Text(brandCount(entry.onWeb),
                      textAlign: TextAlign.right, style: figure(entry.onWeb)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Tarjetas ───────────────────────────────────────────────────────────────

class _BrandCardGrid extends StatelessWidget {
  const _BrandCardGrid({required this.rows, required this.onOpen});

  final List<BrandDirectoryEntry> rows;
  final ValueChanged<BrandDirectoryEntry> onOpen;

  static const double _minWidth = 280;
  static const double _gap = 16;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = ((width + _gap) / (_minWidth + _gap)).floor().clamp(
              1,
              6,
            );
        final cardWidth = (width - _gap * (columns - 1)) / columns;
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final entry in rows)
              SizedBox(
                width: cardWidth,
                child: _BrandCard(entry: entry, onOpen: () => onOpen(entry)),
              ),
          ],
        );
      },
    );
  }
}

class _BrandCard extends StatelessWidget {
  const _BrandCard({required this.entry, required this.onOpen});

  final BrandDirectoryEntry entry;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final lastSale = entry.lastSale;
    final lastLabel = lastSale == null ? null : brandDayLabel(lastSale);
    return Semantics(
      button: true,
      label: 'Abrir la marca ${entry.name}',
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('brand-card-${entry.id}'),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    BrandMark(
                      name: entry.name,
                      logoUrl: entry.logoUrl,
                      size: 44,
                      solid: true,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            brandStockLine(entry),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    for (var index = 0; index < 3; index++) ...[
                      if (index > 0) const SizedBox(width: 8),
                      Expanded(
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: BrandProductPhoto(
                            url: index < entry.images.length
                                ? entry.images[index]
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                // Dos líneas y no una: con ventas de tres cifras, «113
                // vendidas en 12 meses» y «última 10 nov» no caben juntas en
                // la tarjeta más angosta (se pegaban: «mesesúltima»).
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: brandCount(entry.sold12m),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                      const TextSpan(text: ' vendidas en 12 meses'),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  lastLabel == null
                      ? 'Sin ventas registradas'
                      : 'Última venta $lastLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight:
                        lastLabel == 'hoy' ? FontWeight.w600 : FontWeight.w400,
                    color: lastLabel == 'hoy'
                        ? scheme.onSurface
                        : lastLabel == null
                            ? roles.faintForeground
                            : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Divider(height: 1, thickness: 1, color: roles.hairline),
                const SizedBox(height: 12),
                BrandSupplierLine(
                  entry: entry,
                  fontSize: 13,
                  leading: Icon(
                    Icons.local_shipping_outlined,
                    size: 16,
                    color: scheme.onSurfaceVariant,
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

// ── Teléfono ───────────────────────────────────────────────────────────────

/// Una fila del teléfono: la marca, «27 productos · 10 con stock · RBX» en una
/// línea que no se corta, y lo vendido a la derecha.
class _BrandCompactRow extends StatelessWidget {
  const _BrandCompactRow({
    required this.entry,
    required this.divider,
    required this.onOpen,
  });

  final BrandDirectoryEntry entry;
  final bool divider;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final second = [
      brandStockLine(entry),
      if (entry.supplier != null) entry.supplier!.name,
    ].join(' · ');
    return Semantics(
      button: true,
      label: 'Abrir la marca ${entry.name}',
      child: InkWell(
        key: ValueKey('brand-row-${entry.id}'),
        onTap: onOpen,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: divider
                ? Border(top: BorderSide(color: roles.hairline))
                : null,
          ),
          child: Row(
            children: [
              BrandMark(
                name: entry.name,
                logoUrl: entry.logoUrl,
                size: 40,
                solid: true,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      second,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    brandCount(entry.sold12m),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: entry.sold12m > 0
                          ? scheme.onSurface
                          : roles.faintForeground,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    'vendidas',
                    style:
                        TextStyle(fontSize: 11.5, color: roles.faintForeground),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
