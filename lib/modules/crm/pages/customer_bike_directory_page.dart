import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/utils/responsive_viewport.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/vb_button.dart';
import '../../../shared/widgets/vb_segmented.dart';
import '../../bikeshop/models/bikeshop_models.dart';
import '../../bikeshop/services/bike_directory_entries.dart';
import '../../bikeshop/services/bikeshop_service.dart';
import '../../bikeshop/widgets/bike_module_style.dart';
import '../../bikeshop/widgets/bike_silhouette.dart';
import '../models/crm_models.dart';
import '../services/customer_service.dart';

/// Directorio de bicicletas (`/taller/bicicletas`).
///
/// Rediseño aprobado por el dueño el 2026-10-02: «Todas» es la vista por
/// defecto, las más recientes primero; «En el taller» es la segunda, por
/// etapa y con lo que más espera arriba. Cada fila abre la bici en su propia
/// página.
class CustomerBikeDirectoryPage extends StatefulWidget {
  const CustomerBikeDirectoryPage({super.key, this.today});

  /// Para pruebas: la fecha con que se cuentan los días de espera.
  final DateTime? today;

  @override
  State<CustomerBikeDirectoryPage> createState() =>
      _CustomerBikeDirectoryPageState();
}

enum _DirectoryView { all, workshop }

/// Más de dos semanas esperando se marca.
const int _longWaitDays = 14;
const int _pageSize = 40;

final NumberFormat _money =
    NumberFormat.currency(symbol: r'$', decimalDigits: 0);

String _shortDate(DateTime date, DateTime today) =>
    bikeShortDate(date, today: today);

String _waitLabel(int days) => switch (days) {
      0 => 'Hoy',
      1 => '1 día',
      _ => '$days días',
    };

class _CustomerBikeDirectoryPageState extends State<CustomerBikeDirectoryPage> {
  final TextEditingController _searchController = TextEditingController();

  List<Bike> _bikes = const [];
  Map<String, Customer> _customersById = const {};
  List<MechanicJob> _jobs = const [];
  Map<String, List<MechanicJobBike>> _jobBikes = const {};
  List<BikeDirectoryEntry> _rows = const [];

  bool _isLoading = true;
  String? _error;

  /// Sólo publica la carga más reciente (dos «Actualizar» seguidos).
  int _loadGeneration = 0;
  String _query = '';
  _DirectoryView _view = _DirectoryView.all;
  int _visibleCount = _pageSize;

  DateTime get _today => widget.today ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _hydrateFromCache();
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _hydrateFromCache() {
    final bikeshop = context.read<BikeshopService>();
    final customers = context.read<CustomerService>();
    _bikes = List.of(bikeshop.cachedBikes);
    _customersById = _indexCustomers(customers.cachedListCustomers);
    _jobs = List.of(bikeshop.cachedJobs);
    _jobBikes = bikeshop.cachedAllJobBikes;
    _rebuildRows();
    _isLoading = _bikes.isEmpty;
  }

  Map<String, Customer> _indexCustomers(List<Customer> customers) => {
        for (final customer in customers)
          if (customer.id != null && customer.id!.isNotEmpty)
            customer.id!: customer,
      };

  void _rebuildRows() {
    _rows = buildBikeDirectoryEntries(
      bikes: _bikes,
      customersById: _customersById,
      jobs: _jobs,
      jobBikesByJobId: _jobBikes,
    );
  }

  Future<void> _load({bool forceRefresh = false}) async {
    final generation = ++_loadGeneration;
    setState(() {
      _error = null;
      if (_bikes.isEmpty) _isLoading = true;
    });
    try {
      final bikeshop = context.read<BikeshopService>();
      final customers = context.read<CustomerService>();
      final results = await Future.wait<Object>([
        bikeshop.getBikes(forceRefresh: forceRefresh),
        customers.getCustomersForList(forceRefresh: forceRefresh),
        bikeshop.getJobs(forceRefresh: forceRefresh),
        bikeshop.getAllJobBikes(
          forceRefresh: forceRefresh,
          rethrowErrors: true,
        ),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _bikes = results[0] as List<Bike>;
        _customersById = _indexCustomers(results[1] as List<Customer>);
        _jobs = results[2] as List<MechanicJob>;
        _jobBikes = results[3] as Map<String, List<MechanicJobBike>>;
        _rebuildRows();
        _isLoading = false;
      });
    } catch (error) {
      debugPrint('Bike directory load failed: $error');
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = 'No pudimos actualizar las bicicletas.';
        _isLoading = false;
      });
    }
  }

  void _setQuery(String value) {
    setState(() {
      _query = value.trim();
      _visibleCount = _pageSize;
    });
  }

  void _clearQuery() {
    _searchController.clear();
    _setQuery('');
  }

  void _openBike(Bike bike) {
    final id = bike.id;
    if (id == null || id.isEmpty) return;
    context.push('/taller/bicicletas/$id');
  }

  void _openOwner(Customer owner) {
    final id = owner.id;
    if (id == null || id.isEmpty) return;
    context.push('/clientes/$id');
  }

  int get _activeCount => _rows.where((row) => row.bike.isActive).length;
  int get _workshopCount => _rows.where((row) => row.inWorkshop).length;

  List<BikeDirectoryEntry> _searchResults(Iterable<BikeDirectoryEntry> rows) {
    final scored = <({BikeDirectoryEntry row, int score})>[];
    for (final row in rows) {
      final score = bikeDirectorySearchScore(row, _query);
      if (score > 0) scored.add((row: row, score: score));
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return (b.row.lastVisitAt ?? DateTime(0))
          .compareTo(a.row.lastVisitAt ?? DateTime(0));
    });
    return [for (final entry in scored) entry.row];
  }

  @override
  Widget build(BuildContext context) {
    final compact = ResponsiveViewport.usesCompactShell(context);
    final summary = _isLoading && _rows.isEmpty
        ? 'Cargando…'
        : '$_activeCount registradas · $_workshopCount en el taller';
    return MainLayout(
      title: 'Bicicletas',
      compactHeader: compact
          ? MainLayoutCompactHeader(
              title: 'Bicicletas',
              contextLine: summary,
              search: MainLayoutCompactSearch(
                controller: _searchController,
                onChanged: _setQuery,
                onClear: _clearQuery,
                hintText: 'Marca, modelo, dueño o color',
              ),
            )
          : null,
      body: BikeModuleTheme(
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child:
              compact ? _buildCompact(context) : _buildWide(context, summary),
        ),
      ),
    );
  }

  Widget _buildWide(BuildContext context, String summary) {
    final theme = Theme.of(context);
    final groups = groupInWorkshop(_rows);
    // Ocupa todo el ancho de la página (dueño, 2026-10-02: «no me gustan esas
    // tablas en desktop que no cubren todo el ancho»).
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text('Bicicletas',
                          style: BikeModuleText.title(context)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      summary,
                      style: TextStyle(
                        fontSize: 15,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              for (final stage in BikeWorkshopStage.values) ...[
                const SizedBox(width: 10),
                _StageCounter(
                  stage: stage,
                  rows: [
                    for (final group in groups)
                      if (group.stage == stage) ...group.rows,
                  ],
                  today: _today,
                  selected: _view == _DirectoryView.workshop,
                  onTap: () => setState(() {
                    _view = _DirectoryView.workshop;
                    _visibleCount = _pageSize;
                  }),
                ),
              ],
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'Actualizar',
                onPressed: () => _load(forceRefresh: true),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _buildSearchField(context)),
              const SizedBox(width: 12),
              // VbSegmented reparte el ancho entre sus segmentos.
              SizedBox(width: 340, child: _buildViewSelector()),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _buildErrorBanner(context),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) =>
                  _buildWideList(context, width: constraints.maxWidth),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: _searchController,
      onChanged: _setQuery,
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 20),
        hintText: 'Marca, modelo, dueño, color o N° de serie',
        filled: true,
        fillColor: theme.colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Limpiar búsqueda',
                onPressed: _clearQuery,
                icon: const Icon(Icons.close, size: 18),
              ),
      ),
    );
  }

  Widget _buildViewSelector() {
    return VbSegmented<_DirectoryView>(
      groupLabel: 'Mostrar',
      density: ResponsiveViewport.usesCompactShell(context)
          ? null
          : VbDensity.comfortable,
      value: _view,
      onChanged: (view) => setState(() {
        _view = view;
        _visibleCount = _pageSize;
      }),
      options: [
        VbSegmentedOption(
          value: _DirectoryView.all,
          label: 'Todas $_activeCount',
        ),
        VbSegmentedOption(
          value: _DirectoryView.workshop,
          label: 'En el taller $_workshopCount',
        ),
      ],
    );
  }

  Widget _buildErrorBanner(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
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
              child: Text(
                _rows.isEmpty
                    ? _error!
                    : '${_error!} Lo que ves puede estar desactualizado.',
                style: TextStyle(color: roles.warning.onContainer),
              ),
            ),
            VbButton(
              label: 'Reintentar',
              variant: VbButtonVariant.text,
              icon: Icons.refresh,
              onPressed: () => _load(forceRefresh: true),
            ),
          ],
        ),
      ),
    );
  }

  // ── Escritorio ─────────────────────────────────────────────────────────

  Widget _buildWideList(BuildContext context, {required double width}) {
    final theme = Theme.of(context);
    if (_isLoading && _rows.isEmpty) {
      return const Center(child: BrandedLoading());
    }
    _WideRow rowFor(BikeDirectoryEntry row, {required bool workshopView}) =>
        _WideRow(
          row: row,
          workshopView: workshopView,
          today: _today,
          onOpen: () => _openBike(row.bike),
          onOpenOwner: row.owner == null ? null : () => _openOwner(row.owner!),
        );
    final children = <Widget>[];
    if (_query.isNotEmpty) {
      final base = _view == _DirectoryView.workshop
          ? _rows.where((row) => row.inWorkshop)
          : _rows;
      final found = _searchResults(base);
      if (found.isEmpty) return _buildNoMatches(context);
      children.addAll(found.take(80).map((row) =>
          rowFor(row, workshopView: _view == _DirectoryView.workshop)));
    } else if (_view == _DirectoryView.workshop) {
      final groups = groupInWorkshop(_rows);
      if (groups.isEmpty) {
        return _buildEmpty(context, 'No hay bicis en el taller ahora.');
      }
      // Con ancho, cada etapa es una columna: el taller se ve de un vistazo.
      if (width >= 1000) {
        return _WorkshopBoard(
          groups: groups,
          today: _today,
          onOpen: _openBike,
        );
      }
      for (final group in groups) {
        children.add(_GroupHeader(
          title: group.stage.label,
          count: group.rows.length,
          hint: group.stage.hint,
        ));
        children
            .addAll(group.rows.map((row) => rowFor(row, workshopView: true)));
      }
    } else {
      final all = sortByRecentVisit(_rows.where((row) => row.bike.isActive));
      if (all.isEmpty) {
        return _buildEmpty(context, 'Todavía no hay bicicletas registradas.');
      }
      children.addAll(all
          .take(_visibleCount)
          .map((row) => rowFor(row, workshopView: false)));
      children.add(
          _buildMoreFooter(context, shown: _visibleCount, total: all.length));
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Column(
          children: [
            _WideHeaderRow(workshopView: _view == _DirectoryView.workshop),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoreFooter(
    BuildContext context, {
    required int shown,
    required int total,
  }) {
    final theme = Theme.of(context);
    final visible = shown < total ? shown : total;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
            top: BorderSide(color: VinabikeThemeRoles.of(context).hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$visible de $total · las más recientes primero',
              style: TextStyle(
                  fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          if (shown < total)
            VbButton(
              label: 'Ver más',
              variant: VbButtonVariant.secondary,
              onPressed: () => setState(() => _visibleCount += _pageSize),
            ),
        ],
      ),
    );
  }

  Widget _buildNoMatches(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Ninguna bici coincide con «$_query».',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 16, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          VbButton(
            label: 'Limpiar búsqueda',
            variant: VbButtonVariant.secondary,
            onPressed: _clearQuery,
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, String message) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style:
            TextStyle(fontSize: 16, color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }

  // ── Teléfono ───────────────────────────────────────────────────────────

  Widget _buildCompact(BuildContext context) {
    if (_isLoading && _rows.isEmpty) {
      return const Center(child: BrandedLoading());
    }
    final sections = <Widget>[];
    if (_query.isNotEmpty) {
      final base = _view == _DirectoryView.workshop
          ? _rows.where((row) => row.inWorkshop)
          : _rows;
      final found = _searchResults(base);
      if (found.isEmpty) {
        sections.add(Padding(
          padding: const EdgeInsets.only(top: 40),
          child: _buildNoMatches(context),
        ));
      } else {
        sections.add(_CompactCard(
          rows: found.take(60).toList(),
          workshopView: _view == _DirectoryView.workshop,
          today: _today,
          onOpen: _openBike,
        ));
      }
    } else if (_view == _DirectoryView.workshop) {
      final groups = groupInWorkshop(_rows);
      if (groups.isEmpty) {
        sections.add(Padding(
          padding: const EdgeInsets.only(top: 40),
          child: _buildEmpty(context, 'No hay bicis en el taller ahora.'),
        ));
      }
      for (final group in groups) {
        sections.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Semantics(
            header: true,
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: group.stage.label,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: '  ${group.rows.length}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ]),
            ),
          ),
        ));
        sections.add(_CompactCard(
          rows: group.rows,
          workshopView: true,
          today: _today,
          onOpen: _openBike,
        ));
        sections.add(const SizedBox(height: 12));
      }
    } else {
      final all = sortByRecentVisit(_rows.where((row) => row.bike.isActive));
      if (all.isEmpty) {
        sections.add(Padding(
          padding: const EdgeInsets.only(top: 40),
          child: _buildEmpty(context, 'Todavía no hay bicicletas registradas.'),
        ));
      } else {
        sections.add(_CompactCard(
          rows: all.take(_visibleCount).toList(),
          workshopView: false,
          today: _today,
          onOpen: _openBike,
          footer: _visibleCount < all.length
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: VbButton(
                    label: 'Ver más',
                    variant: VbButtonVariant.secondary,
                    expand: true,
                    onPressed: () => setState(() => _visibleCount += _pageSize),
                  ),
                )
              : null,
        ));
      }
    }

    return RefreshIndicator(
      onRefresh: () => _load(forceRefresh: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _buildViewSelector(),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _buildErrorBanner(context),
          ],
          const SizedBox(height: 12),
          ...sections,
        ],
      ),
    );
  }
}

class _WideHeaderRow extends StatelessWidget {
  const _WideHeaderRow({required this.workshopView});

  final bool workshopView;

  @override
  Widget build(BuildContext context) {
    final style = BikeModuleText.label(context);
    Text label(String text, {TextAlign align = TextAlign.start}) =>
        Text(text.toUpperCase(), style: style, textAlign: align);
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 13, 24, 13),
        child: _WideGrid(
          tile: const SizedBox.shrink(),
          bike: label('Bicicleta'),
          owner: label('Dueño'),
          job: label(workshopView ? 'Trabajo' : 'Último trabajo'),
          when: label(workshopView ? 'Tiempo' : 'Última visita'),
          last: label(workshopView ? 'Monto' : 'Visitas', align: TextAlign.end),
          trailing: const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// Las mismas columnas para la cabecera y cada fila, repartidas en todo el
/// ancho: lo que crece es el texto (bici, dueño y lo que se pidió).
class _WideGrid extends StatelessWidget {
  const _WideGrid({
    required this.tile,
    required this.bike,
    required this.owner,
    required this.job,
    required this.when,
    required this.last,
    required this.trailing,
  });

  final Widget tile;
  final Widget bike;
  final Widget owner;
  final Widget job;
  final Widget when;
  final Widget last;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 96, child: tile),
        const SizedBox(width: 20),
        Expanded(flex: 20, child: bike),
        const SizedBox(width: 20),
        Expanded(flex: 15, child: owner),
        const SizedBox(width: 20),
        Expanded(flex: 30, child: job),
        const SizedBox(width: 20),
        SizedBox(width: 128, child: when),
        const SizedBox(width: 16),
        SizedBox(width: 84, child: last),
        const SizedBox(width: 12),
        SizedBox(width: 20, child: trailing),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.title,
    required this.count,
    required this.hint,
  });

  final String title;
  final int count;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: roles.hairline)),
      ),
      child: Semantics(
        header: true,
        child: Text.rich(
          TextSpan(children: [
            TextSpan(
              text: title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text: '  $count',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            TextSpan(
              text: '   $hint',
              style: TextStyle(fontSize: 13, color: roles.faintForeground),
            ),
          ]),
        ),
      ),
    );
  }
}

/// El dibujo de la bici en su recuadro.
class _BikeTile extends StatelessWidget {
  const _BikeTile(
      {required this.bike, required this.width, required this.height});

  final Bike bike;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.symmetric(horizontal: width * 0.07),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: BikeSilhouette(bikeType: bike.bikeType, colorText: bike.color),
    );
  }
}

String _bikeSubtitle(Bike bike) {
  final parts = <String>[
    if (bike.color?.trim().isNotEmpty == true) _capitalize(bike.color!.trim()),
    if (wheelSizeLabel(bike.wheelSize) case final wheel?) wheel,
    if (!bike.isActive) 'Archivada',
  ];
  if (parts.isEmpty && bike.bikeType != null) {
    parts.add(bike.bikeType!.displayName);
  }
  return parts.join(' · ');
}

String _capitalize(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

Widget _bikeName(BuildContext context, Bike bike, {double size = 15}) {
  final theme = Theme.of(context);
  final brand = bike.brand?.trim() ?? '';
  final model = bike.model?.trim() ?? '';
  if (brand.isEmpty && model.isEmpty) {
    return Text('Bicicleta sin nombre',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: size, fontWeight: FontWeight.w600));
  }
  return Text.rich(
    TextSpan(children: [
      if (brand.isNotEmpty)
        TextSpan(
          text: model.isEmpty ? brand : '$brand ',
          style: TextStyle(
            fontWeight: model.isEmpty ? FontWeight.w600 : FontWeight.w500,
            color: model.isEmpty
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      if (model.isNotEmpty)
        TextSpan(
            text: model, style: const TextStyle(fontWeight: FontWeight.w600)),
    ]),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(fontSize: size, color: theme.colorScheme.onSurface),
  );
}

bool _isClosed(MechanicJob job) =>
    jobStatusPhase(job) == StatusPhase.complete && !_isOpenJob(job);

/// Terminado sigue en el taller; entregado y cancelado ya no piden nada.
bool _isOpenJob(MechanicJob job) {
  final code =
      job.customStatus?.code.trim().toUpperCase() ?? job.status.dbValue;
  return !(code == 'ENTREGADO' ||
      code == 'CANCELADO' ||
      code == 'RETIRO_SIN_SERVICIO' ||
      job.deliveredAt != null);
}

class _WideRow extends StatelessWidget {
  const _WideRow({
    required this.row,
    required this.workshopView,
    required this.today,
    required this.onOpen,
    required this.onOpenOwner,
  });

  final BikeDirectoryEntry row;
  final bool workshopView;
  final DateTime today;
  final VoidCallback onOpen;
  final VoidCallback? onOpenOwner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final job = workshopView ? row.workshopJob : row.latestJob;
    final days = row.waitingDays(today);
    final faint = TextStyle(fontSize: 13, color: roles.faintForeground);

    final Widget whenCell;
    final Widget lastCell;
    if (workshopView && row.inWorkshop) {
      final late = (days ?? 0) >= _longWaitDays;
      whenCell = Text(
        days == null ? '—' : _waitLabel(days),
        style: TextStyle(
          fontSize: 14,
          fontWeight: late ? FontWeight.w700 : FontWeight.w500,
          fontFeatures: const [FontFeature.tabularFigures()],
          color:
              late ? roles.warning.accent : theme.colorScheme.onSurfaceVariant,
        ),
      );
      final amount = row.workshopJob?.totalCost ?? 0;
      lastCell = Text(
        amount > 0 ? _money.format(amount) : '—',
        textAlign: TextAlign.end,
        style: TextStyle(
          fontSize: 14,
          fontWeight: amount > 0 ? FontWeight.w600 : FontWeight.w500,
          fontFeatures: const [FontFeature.tabularFigures()],
          color:
              amount > 0 ? theme.colorScheme.onSurface : roles.faintForeground,
        ),
      );
    } else {
      final last = row.lastVisitAt;
      final ago = last == null ? null : calendarDaysBetween(last, today);
      whenCell = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            last == null ? 'Sin visitas' : _shortDate(last, today),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: last == null
                  ? roles.faintForeground
                  : theme.colorScheme.onSurface,
            ),
          ),
          if (ago != null)
            Text(
              switch (ago) {
                0 => 'hoy',
                1 => 'ayer',
                < 60 => 'hace $ago días',
                < 730 => 'hace ${ago ~/ 30} meses',
                _ => 'hace ${ago ~/ 365} años',
              },
              style: faint,
            ),
        ],
      );
      lastCell = Text(
        row.visits == 0 ? '—' : '${row.visits}',
        textAlign: TextAlign.end,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: row.visits == 0
              ? roles.faintForeground
              : theme.colorScheme.onSurface,
        ),
      );
    }

    final request = job?.clientRequest?.trim();
    final phone = ChileanUtils.formatPhone(row.owner?.phone);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          constraints: const BoxConstraints(minHeight: 78),
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: roles.hairline)),
          ),
          child: _WideGrid(
            tile: _BikeTile(bike: row.bike, width: 96, height: 60),
            bike: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _bikeName(context, row.bike, size: 16),
                if (_bikeSubtitle(row.bike) case final sub when sub.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: faint),
                  ),
              ],
            ),
            owner: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onOpenOwner == null)
                  Text('Sin dueño',
                      style:
                          TextStyle(fontSize: 14, color: roles.faintForeground))
                else
                  _OwnerLink(name: row.owner!.name, onTap: onOpenOwner!),
                if (phone.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Text(
                      phone,
                      maxLines: 1,
                      style: faint.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
              ],
            ),
            job: job == null
                ? Text('Sin trabajos',
                    style:
                        TextStyle(fontSize: 13.5, color: roles.faintForeground))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(job.jobNumber ?? '—',
                              style: BikeModuleText.code(context)),
                          const SizedBox(width: 12),
                          Flexible(
                            child: BikeJobStatusDot(
                              label: jobStatusLabel(job),
                              color: jobStatusColor(job),
                              muted: _isClosed(job),
                            ),
                          ),
                        ],
                      ),
                      if (request != null && request.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            bikeRequestAsSentence(request),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
            when: whenCell,
            last: lastCell,
            trailing: Icon(Icons.chevron_right,
                size: 20, color: roles.faintForeground),
          ),
        ),
      ),
    );
  }
}

/// Una etapa del taller en la cabecera: cuántas bicis hay y cuántas llevan
/// demasiado. Lleva a «En el taller».
class _StageCounter extends StatelessWidget {
  const _StageCounter({
    required this.stage,
    required this.rows,
    required this.today,
    required this.selected,
    required this.onTap,
  });

  final BikeWorkshopStage stage;
  final List<BikeDirectoryEntry> rows;
  final DateTime today;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final late =
        rows.where((row) => (row.waitingDays(today) ?? 0) >= _longWaitDays);
    final lateCount = late.length;
    return Semantics(
      button: true,
      label: '${stage.label}: ${rows.length}'
          '${lateCount > 0 ? ', $lateCount con $_longWaitDays días o más' : ''}',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected
                ? roles.accentBorder
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minWidth: 132, minHeight: 60),
            padding: const EdgeInsets.fromLTRB(14, 8, 16, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${rows.length}',
                  style: BikeModuleText.figure(context, size: 30),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      stage.label,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      lateCount > 0
                          ? '$lateCount con $_longWaitDays+ días'
                          : 'Al día',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight:
                            lateCount > 0 ? FontWeight.w700 : FontWeight.w500,
                        color: lateCount > 0
                            ? roles.warning.accent
                            : roles.faintForeground,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «En el taller» en escritorio: una columna por etapa, como un tablero.
class _WorkshopBoard extends StatelessWidget {
  const _WorkshopBoard({
    required this.groups,
    required this.today,
    required this.onOpen,
  });

  final List<({BikeWorkshopStage stage, List<BikeDirectoryEntry> rows})> groups;
  final DateTime today;
  final void Function(Bike bike) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final stage in BikeWorkshopStage.values) ...[
          if (stage != BikeWorkshopStage.values.first)
            const SizedBox(width: 16),
          Expanded(
            child: Builder(builder: (context) {
              final rows = [
                for (final group in groups)
                  if (group.stage == stage) ...group.rows,
              ];
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: roles.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Semantics(
                        header: true,
                        child: Row(
                          children: [
                            Text(stage.label,
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w700)),
                            const SizedBox(width: 8),
                            Text(
                              '${rows.length}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                stage.hint,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: roles.faintForeground),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: rows.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text('Ninguna por ahora.',
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: roles.faintForeground)),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              itemCount: rows.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) => _BoardCard(
                                row: rows[index],
                                today: today,
                                onOpen: () => onOpen(rows[index].bike),
                              ),
                            ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({
    required this.row,
    required this.today,
    required this.onOpen,
  });

  final BikeDirectoryEntry row;
  final DateTime today;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final job = row.workshopJob!;
    final days = row.waitingDays(today) ?? 0;
    final late = days >= _longWaitDays;
    final request = job.clientRequest?.trim();
    final owner = row.owner?.name.trim();
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: late ? roles.warning.border : theme.colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _BikeTile(bike: row.bike, width: 84, height: 54),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _bikeName(context, row.bike),
                        const SizedBox(height: 2),
                        Text(
                          owner == null || owner.isEmpty ? 'Sin dueño' : owner,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (request != null && request.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  bikeRequestAsSentence(request),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(job.jobNumber ?? '—',
                      style: BikeModuleText.code(context)),
                  const SizedBox(width: 10),
                  Flexible(
                    child: BikeJobStatusDot(
                      label: jobStatusLabel(job),
                      color: jobStatusColor(job),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: late
                          ? roles.warning.container
                          : theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _waitLabel(days),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: late
                            ? roles.warning.onContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
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

class _OwnerLink extends StatelessWidget {
  const _OwnerLink({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: 'Abrir cliente',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Text(
            name.trim().isEmpty ? 'Cliente sin nombre' : name.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface),
          ),
        ),
      ),
    );
  }
}

class _CompactCard extends StatelessWidget {
  const _CompactCard({
    required this.rows,
    required this.workshopView,
    required this.today,
    required this.onOpen,
    this.footer,
  });

  final List<BikeDirectoryEntry> rows;
  final bool workshopView;
  final DateTime today;
  final void Function(Bike bike) onOpen;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Column(
          children: [
            for (var index = 0; index < rows.length; index++)
              _CompactRow(
                row: rows[index],
                workshopView: workshopView,
                today: today,
                divider: index > 0,
                onOpen: () => onOpen(rows[index].bike),
                hairline: roles.hairline,
              ),
            if (footer != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: roles.hairline)),
                ),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

class _CompactRow extends StatelessWidget {
  const _CompactRow({
    required this.row,
    required this.workshopView,
    required this.today,
    required this.divider,
    required this.onOpen,
    required this.hairline,
  });

  final BikeDirectoryEntry row;
  final bool workshopView;
  final DateTime today;
  final bool divider;
  final VoidCallback onOpen;
  final Color hairline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final job = workshopView ? row.workshopJob : row.latestJob;
    final days = row.waitingDays(today);
    final late = workshopView && (days ?? 0) >= _longWaitDays;
    final String detail;
    if (workshopView && days != null) {
      detail = _waitLabel(days);
    } else if (row.lastVisitAt case final last?) {
      detail = _shortDate(last, today);
    } else {
      detail = 'Sin visitas';
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            border: divider ? Border(top: BorderSide(color: hairline)) : null,
          ),
          child: Row(
            children: [
              _BikeTile(bike: row.bike, width: 56, height: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _bikeName(context, row.bike),
                    const SizedBox(height: 2),
                    Text(
                      row.owner?.name.trim().isNotEmpty == true
                          ? row.owner!.name.trim()
                          : 'Sin dueño',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 124),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      detail,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: late ? FontWeight.w700 : FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: late
                            ? roles.warning.accent
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (job != null) ...[
                      const SizedBox(height: 3),
                      BikeJobStatusDot(
                        label: jobStatusLabel(job),
                        color: jobStatusColor(job),
                        muted: _isClosed(job),
                        fontSize: 12.5,
                      ),
                    ],
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
