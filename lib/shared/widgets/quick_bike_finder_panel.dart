import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../modules/bikeshop/models/bikeshop_models.dart';
import '../../modules/bikeshop/services/bikeshop_service.dart';
import '../../modules/bikeshop/services/mechanic_job_visibility_policy.dart';
import '../../modules/crm/models/crm_models.dart';
import '../../modules/crm/services/customer_service.dart';
import '../services/workspace_manager.dart';
import '../utils/bike_finder_search.dart';

enum _BikeFinderScope {
  recent,
  activeJobs,
  warranty,
  history,
  archived,
  all,
}

extension on _BikeFinderScope {
  String get label => switch (this) {
        _BikeFinderScope.recent => 'Recientes',
        _BikeFinderScope.activeJobs => 'En taller',
        _BikeFinderScope.warranty => 'En garantía',
        _BikeFinderScope.history => 'Con historial',
        _BikeFinderScope.archived => 'Archivadas',
        _BikeFinderScope.all => 'Todas',
      };

  String get description => switch (this) {
        _BikeFinderScope.recent => 'Última actividad primero',
        _BikeFinderScope.activeJobs => 'Con trabajos en curso',
        _BikeFinderScope.warranty => 'Garantía vigente',
        _BikeFinderScope.history => 'Al menos un trabajo registrado',
        _BikeFinderScope.archived => 'Fuera del registro activo',
        _BikeFinderScope.all => 'Sin filtro de estado',
      };

  IconData get icon => switch (this) {
        _BikeFinderScope.recent => Icons.schedule_rounded,
        _BikeFinderScope.activeJobs => Icons.handyman_outlined,
        _BikeFinderScope.warranty => Icons.verified_user_outlined,
        _BikeFinderScope.history => Icons.history_rounded,
        _BikeFinderScope.archived => Icons.inventory_2_outlined,
        _BikeFinderScope.all => Icons.pedal_bike_outlined,
      };
}

class QuickBikeFinderPanel extends StatefulWidget {
  final VoidCallback? onBikeOpened;

  const QuickBikeFinderPanel({super.key, this.onBikeOpened});

  @override
  State<QuickBikeFinderPanel> createState() => _QuickBikeFinderPanelState();
}

class _QuickBikeFinderPanelState extends State<QuickBikeFinderPanel> {
  static final _dateFormat = DateFormat('dd/MM/yy');

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<Bike> _bikes = const [];
  Map<String, Customer> _customersById = const {};
  Map<String, _BikeFinderMetrics> _metricsByBikeId = const {};

  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isLoadingJobMetrics = false;
  String? _error;

  String _searchTerm = '';
  _BikeFinderScope _scope = _BikeFinderScope.recent;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    _hydrateFromCache();
    unawaited(_loadData());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _hydrateFromCache() {
    final bikeshopService = context.read<BikeshopService>();
    final customerService = context.read<CustomerService>();

    final bikes = List<Bike>.from(bikeshopService.cachedBikes);
    final customers = List<Customer>.from(customerService.cachedListCustomers);
    final jobs = List<MechanicJob>.from(bikeshopService.cachedJobs);

    _bikes = bikes;
    _customersById = {
      for (final customer in customers)
        if (customer.id != null && customer.id!.isNotEmpty)
          customer.id!: customer,
    };
    _metricsByBikeId = _buildMetrics(jobs);
    _isLoading = bikes.isEmpty && _customersById.isEmpty;
  }

  void _handleSearchChanged() {
    if (!mounted) return;
    setState(() {
      _searchTerm = _searchController.text.trim();
    });
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    if (mounted) {
      setState(() {
        _error = null;
        if (_bikes.isEmpty) {
          _isLoading = true;
        } else {
          _isRefreshing = true;
        }
      });
    }

    try {
      final bikeshopService = context.read<BikeshopService>();
      final customerService = context.read<CustomerService>();

      final results = await Future.wait([
        bikeshopService.getBikes(forceRefresh: forceRefresh),
        customerService.getCustomersForList(forceRefresh: forceRefresh),
      ]);

      final bikes = results[0] as List<Bike>;
      final customers = results[1] as List<Customer>;

      if (!mounted) return;

      setState(() {
        _bikes = bikes;
        _customersById = {
          for (final customer in customers)
            if (customer.id != null && customer.id!.isNotEmpty)
              customer.id!: customer,
        };
        _isLoading = false;
        _isRefreshing = false;
      });

      unawaited(_loadJobMetrics(forceRefresh: forceRefresh));
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'No se pudo cargar el buscador de bicicletas: $e';
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  Future<void> _loadJobMetrics({bool forceRefresh = false}) async {
    final bikeshopService = context.read<BikeshopService>();

    if (mounted) {
      setState(() => _isLoadingJobMetrics = true);
    }

    try {
      final jobs = await bikeshopService.getJobs(forceRefresh: forceRefresh);
      if (!mounted) return;

      setState(() {
        _metricsByBikeId = _buildMetrics(jobs);
      });
    } catch (_) {
      // Keep the panel usable even if job metrics fail.
    } finally {
      if (mounted) {
        setState(() => _isLoadingJobMetrics = false);
      }
    }
  }

  Map<String, _BikeFinderMetrics> _buildMetrics(List<MechanicJob> jobs) {
    final metrics = <String, _BikeFinderMetrics>{};
    final bikesById = {
      for (final bike in _bikes)
        if (bike.id != null && bike.id!.isNotEmpty) bike.id!: bike,
    };

    for (final job in jobs) {
      final bikeId = job.bikeId?.trim();
      if (bikeId == null || bikeId.isEmpty) continue;

      final bike = bikesById[bikeId];
      final owner = bike == null ? null : _customersById[bike.customerId];
      if (mechanicJobMatchesTestFixture(
        job,
        customerName: owner?.name,
        bikeName: bike?.displayName,
        bikeBrand: bike?.brand,
        bikeModel: bike?.model,
        bikeSerialNumber: bike?.serialNumber,
      )) {
        continue;
      }
      final isInWorkshop = isMechanicJobBikeInWorkshop(
        job,
      );
      final previous = metrics[bikeId] ?? const _BikeFinderMetrics();
      final lastDeliveredAt = previous.lastDeliveredAt == null
          ? job.deliveredAt
          : _maxDate(previous.lastDeliveredAt, job.deliveredAt);
      final lastArrivalAt = _maxDate(previous.lastArrivalAt, job.arrivalDate);
      final becomesLatestJob = previous.latestJobAt == null ||
          job.arrivalDate.isAfter(previous.latestJobAt!) ||
          (job.arrivalDate.isAtSameMomentAs(previous.latestJobAt!) &&
              job.updatedAt.isAfter(previous.latestJobUpdatedAt!));
      final becomesLatestWorkshopJob = isInWorkshop &&
          (previous.latestWorkshopJobAt == null ||
              job.updatedAt.isAfter(previous.latestWorkshopJobAt!));

      metrics[bikeId] = previous.copyWith(
        totalJobs: previous.totalJobs + 1,
        workshopJobs: previous.workshopJobs + (isInWorkshop ? 1 : 0),
        lastDeliveredAt: lastDeliveredAt,
        lastArrivalAt: lastArrivalAt,
        latestJobId: becomesLatestJob ? job.id : previous.latestJobId,
        latestJobInvoiceId:
            becomesLatestJob ? job.invoiceId : previous.latestJobInvoiceId,
        clearLatestJobInvoiceId:
            becomesLatestJob && (job.invoiceId?.trim().isEmpty ?? true),
        latestJobAt: becomesLatestJob ? job.arrivalDate : previous.latestJobAt,
        latestJobUpdatedAt:
            becomesLatestJob ? job.updatedAt : previous.latestJobUpdatedAt,
        latestWorkshopJobId:
            becomesLatestWorkshopJob ? job.id : previous.latestWorkshopJobId,
        latestWorkshopJobAt: becomesLatestWorkshopJob
            ? job.updatedAt
            : previous.latestWorkshopJobAt,
      );
    }

    return metrics;
  }

  DateTime? _maxDate(DateTime? left, DateTime? right) {
    if (left == null) return right;
    if (right == null) return left;
    return right.isAfter(left) ? right : left;
  }

  List<_BikeFinderResult> _buildResults() {
    final query = normalizeBikeFinderSearch(_searchTerm);
    final results = <_BikeFinderResult>[];

    for (final bike in _bikes) {
      final bikeId = bike.id;
      if (bikeId == null || bikeId.isEmpty) continue;

      final owner = _customersById[bike.customerId];
      final metrics = _metricsByBikeId[bikeId] ?? const _BikeFinderMetrics();

      if (!_matchesScope(bike, metrics, hasQuery: query.isNotEmpty)) continue;

      final score = _scoreBikeResult(
          bike: bike, owner: owner, metrics: metrics, query: query);
      if (query.isNotEmpty && score <= 0) continue;

      results.add(
        _BikeFinderResult(
          bike: bike,
          owner: owner,
          metrics: metrics,
          score: score,
        ),
      );
    }

    results.sort((left, right) {
      if (query.isNotEmpty) {
        final scoreCompare = right.score.compareTo(left.score);
        if (scoreCompare != 0) return scoreCompare;
      }

      final activeCompare =
          right.metrics.workshopJobs.compareTo(left.metrics.workshopJobs);
      if (activeCompare != 0) return activeCompare;

      final historyCompare = (right.metrics.lastActivityAt ?? DateTime(0))
          .compareTo(left.metrics.lastActivityAt ?? DateTime(0));
      if (historyCompare != 0) return historyCompare;

      return right.bike.updatedAt.compareTo(left.bike.updatedAt);
    });

    return results;
  }

  bool _matchesScope(
    Bike bike,
    _BikeFinderMetrics metrics, {
    required bool hasQuery,
  }) {
    return switch (_scope) {
      _BikeFinderScope.recent => hasQuery || bike.isActive,
      _BikeFinderScope.activeJobs => bike.isActive && metrics.workshopJobs > 0,
      _BikeFinderScope.warranty => bike.isActive && bike.isUnderWarranty,
      _BikeFinderScope.history => bike.isActive && metrics.hasHistory,
      _BikeFinderScope.archived => !bike.isActive,
      _BikeFinderScope.all => true,
    };
  }

  List<_BikeFinderResult> _visibleResults(List<_BikeFinderResult> results) {
    final isRecentOverview =
        _scope == _BikeFinderScope.recent && _searchTerm.isEmpty;
    final limit = isRecentOverview ? 18 : 60;
    return results.take(limit).toList(growable: false);
  }

  int _scoreBikeResult({
    required Bike bike,
    required Customer? owner,
    required _BikeFinderMetrics metrics,
    required String query,
  }) {
    if (query.isEmpty) {
      var score = 10;
      if (metrics.workshopJobs > 0) score += 60;
      if (metrics.hasHistory) score += 30;
      if (bike.isUnderWarranty) score += 20;
      return score;
    }

    final matchScore = bikeFinderRelationalSearchScore(
      query: query,
      fields: [
        BikeFinderSearchField(bike.serialNumber, weight: 135),
        BikeFinderSearchField(bike.qrCode, weight: 135),
        BikeFinderSearchField(bike.displayName, weight: 125),
        BikeFinderSearchField(bike.brand, weight: 108),
        BikeFinderSearchField(bike.model, weight: 108),
        BikeFinderSearchField(owner?.name, weight: 120),
        BikeFinderSearchField(owner?.rut, weight: 128),
        BikeFinderSearchField(owner?.phone, weight: 128),
        BikeFinderSearchField(owner?.email, weight: 112),
        BikeFinderSearchField(bike.year?.toString(), weight: 92),
        BikeFinderSearchField(bike.color, weight: 78),
        BikeFinderSearchField(bike.bikeType?.displayName, weight: 72),
        BikeFinderSearchField(bike.notes, weight: 55),
      ],
    );

    if (matchScore == 0) return 0;

    var rankScore = matchScore;
    if (metrics.workshopJobs > 0) rankScore += 16;
    if (metrics.hasHistory) rankScore += 8;

    return rankScore;
  }

  void _openBike(Bike bike) {
    final bikeId = bike.id?.trim();
    final customerId = bike.customerId.trim();
    if (bikeId == null || bikeId.isEmpty || customerId.isEmpty) return;

    final route = Uri(
      path: '/clientes/$customerId',
      queryParameters: {
        'tab': 'bicicletas',
        'bike_id': bikeId,
      },
    ).toString();

    context.read<WorkspaceManager>().navigateActiveWorkspace(route);
    widget.onBikeOpened?.call();
  }

  void _openClient(Bike bike) {
    final customerId = bike.customerId.trim();
    if (customerId.isEmpty) return;

    final route = Uri(
      path: '/clientes/$customerId',
      queryParameters: const {
        'tab': 'bicicletas',
      },
    ).toString();

    context.read<WorkspaceManager>().navigateActiveWorkspace(route);
  }

  void _openDirectory() {
    context
        .read<WorkspaceManager>()
        .navigateActiveWorkspace('/taller/bicicletas');
  }

  void _openNewJob(Bike bike) {
    final bikeId = bike.id?.trim();
    final customerId = bike.customerId.trim();
    if (!bike.isActive ||
        bikeId == null ||
        bikeId.isEmpty ||
        customerId.isEmpty) {
      return;
    }

    final route = Uri(
      path: '/taller/pegas/nueva',
      queryParameters: {
        'customer_id': customerId,
        'bike_id': bikeId,
      },
    ).toString();

    context.read<WorkspaceManager>().navigateActiveWorkspace(route);
  }

  void _openWorkshopJob(_BikeFinderMetrics metrics) {
    final jobId = metrics.latestWorkshopJobId?.trim();
    if (jobId == null || jobId.isEmpty) return;

    context
        .read<WorkspaceManager>()
        .navigateActiveWorkspace('/taller/pegas/$jobId');
  }

  void _openLatestJob(_BikeFinderMetrics metrics) {
    final jobId = metrics.latestJobId?.trim();
    if (jobId == null || jobId.isEmpty) return;

    context
        .read<WorkspaceManager>()
        .navigateActiveWorkspace('/taller/pegas/$jobId');
  }

  void _openLatestInvoice(_BikeFinderMetrics metrics) {
    final invoiceId = metrics.latestJobInvoiceId?.trim();
    if (invoiceId == null || invoiceId.isEmpty) return;

    final route = Uri(
      path: '/sales/invoices',
      queryParameters: {
        'selectedInvoiceId': invoiceId,
        'view': 'split',
      },
    ).toString();
    context.read<WorkspaceManager>().navigateActiveWorkspace(route);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = _buildResults();
    final visibleResults = _visibleResults(results);

    return ColoredBox(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSearchArea(theme, results, visibleResults),
          if (_isRefreshing || _isLoadingJobMetrics)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: KeyedSubtree(
                key: ValueKey(
                  '${_scope.name}|$_searchTerm|${results.length}|$_isLoading',
                ),
                child: _buildContent(theme, results, visibleResults),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchArea(
    ThemeData theme,
    List<_BikeFinderResult> results,
    List<_BikeFinderResult> visibleResults,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) {
              if (results.isNotEmpty) {
                _openBike(results.first.bike);
              }
            },
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Nombre, cliente, teléfono, serie o QR',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _searchTerm.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpiar búsqueda',
                      onPressed: () {
                        _searchController.clear();
                        _searchFocusNode.requestFocus();
                      },
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.55,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: theme.colorScheme.primary.withValues(alpha: 0.72),
                  width: 1.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildScopeMenu(theme),
              ),
              Text(
                _buildSummaryText(results, visibleResults),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 2),
              IconButton(
                tooltip: 'Actualizar',
                onPressed:
                    _isRefreshing ? null : () => _loadData(forceRefresh: true),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.refresh_rounded, size: 19),
              ),
              IconButton(
                tooltip: 'Abrir directorio de bicicletas',
                onPressed: _openDirectory,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.view_list_outlined, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScopeMenu(ThemeData theme) {
    return PopupMenuButton<_BikeFinderScope>(
      tooltip: 'Filtrar bicicletas',
      position: PopupMenuPosition.under,
      onSelected: (scope) => setState(() => _scope = scope),
      itemBuilder: (context) => _BikeFinderScope.values.map((scope) {
        final selected = scope == _scope;
        return PopupMenuItem<_BikeFinderScope>(
          value: scope,
          height: 54,
          child: Row(
            children: [
              Icon(
                scope.icon,
                size: 19,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      scope.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                    Text(
                      scope.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
            ],
          ),
        );
      }).toList(growable: false),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_scope.icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                _scope.label,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 3),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          ],
        ),
      ),
    );
  }

  String _buildSummaryText(
    List<_BikeFinderResult> results,
    List<_BikeFinderResult> visibleResults,
  ) {
    final total = results.length;
    if (visibleResults.length < total) {
      return '${visibleResults.length} de $total';
    }
    return '$total';
  }

  Widget _buildContent(
    ThemeData theme,
    List<_BikeFinderResult> results,
    List<_BikeFinderResult> visibleResults,
  ) {
    if (_isLoading && _bikes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _bikes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 40,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () => _loadData(forceRefresh: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off,
                size: 42,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
              ),
              const SizedBox(height: 12),
              Text(
                'No encontré bicicletas con esos criterios.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Combina bici, cliente, teléfono, serie o QR; también se consideran errores pequeños al escribir.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scrollbar(
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 12),
        itemCount: visibleResults.length +
            (visibleResults.length < results.length ? 1 : 0),
        separatorBuilder: (_, __) => Divider(
          height: 1,
          indent: 64,
          endIndent: 12,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.38),
        ),
        itemBuilder: (context, index) {
          if (index == visibleResults.length) {
            return _buildResultsFooter(
              theme,
              visible: visibleResults.length,
              total: results.length,
            );
          }
          return _buildResultTile(theme, visibleResults[index]);
        },
      ),
    );
  }

  Widget _buildResultsFooter(
    ThemeData theme, {
    required int visible,
    required int total,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(64, 14, 18, 16),
      child: Text(
        'Mostrando $visible de $total · escribe para afinar la búsqueda',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildResultTile(ThemeData theme, _BikeFinderResult result) {
    final bike = result.bike;
    final owner = result.owner;
    final metrics = result.metrics;
    final ownerName = owner?.name.trim().isNotEmpty == true
        ? owner!.name.trim()
        : 'Cliente desconocido';
    final accentColor = !bike.isActive
        ? theme.colorScheme.onSurfaceVariant
        : metrics.workshopJobs > 0
            ? Colors.orange.shade700
            : (bike.isUnderWarranty
                ? Colors.green.shade700
                : theme.colorScheme.primary);
    final phone = owner?.phone?.trim();
    final serial = bike.serialNumber?.trim();
    final lastActivity = metrics.lastActivityAt;
    final status = _buildBikeStatus(theme, bike, metrics);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openBike(bike),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.pedal_bike_rounded,
                  size: 21,
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bike.displayName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: bike.isActive
                            ? null
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        ownerName,
                        if (phone?.isNotEmpty ?? false) phone!,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if ((serial?.isNotEmpty ?? false) ||
                        metrics.totalJobs > 0 ||
                        lastActivity != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(
                          spacing: 11,
                          runSpacing: 5,
                          children: [
                            if (serial?.isNotEmpty ?? false)
                              _buildBikeFact(
                                theme,
                                icon: Icons.qr_code_2_rounded,
                                label: serial!,
                              ),
                            if (metrics.totalJobs > 0)
                              _buildBikeFact(
                                theme,
                                icon: Icons.history_rounded,
                                label:
                                    '${metrics.totalJobs} trabajo${metrics.totalJobs == 1 ? '' : 's'}',
                              ),
                            if (lastActivity != null)
                              _buildBikeFact(
                                theme,
                                icon: Icons.event_available_outlined,
                                label: _dateFormat.format(lastActivity),
                              ),
                          ],
                        ),
                      ),
                    if (status != null || bike.isActive)
                      Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: Row(
                          children: [
                            if (status != null) status,
                            const Spacer(),
                            _buildRowActions(theme, bike, metrics),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              _buildResultMenu(theme, bike, metrics),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultMenu(
    ThemeData theme,
    Bike bike,
    _BikeFinderMetrics metrics,
  ) {
    final canOpenWorkshopJob =
        metrics.latestWorkshopJobId?.trim().isNotEmpty == true;
    final canOpenLatestJob = metrics.latestJobId?.trim().isNotEmpty == true;
    final canOpenLatestInvoice =
        metrics.latestJobInvoiceId?.trim().isNotEmpty == true;
    return PopupMenuButton<String>(
      tooltip: 'Más acciones',
      position: PopupMenuPosition.under,
      onSelected: (action) {
        switch (action) {
          case 'bike':
            _openBike(bike);
          case 'client':
            _openClient(bike);
          case 'new-job':
            _openNewJob(bike);
          case 'last-job':
            _openLatestJob(metrics);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'bike',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.pedal_bike_outlined),
            title: Text('Abrir ficha'),
          ),
        ),
        const PopupMenuItem(
          value: 'client',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.person_outline_rounded),
            title: Text('Abrir cliente'),
          ),
        ),
        if (!canOpenWorkshopJob && canOpenLatestJob && canOpenLatestInvoice)
          const PopupMenuItem(
            value: 'last-job',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.history_rounded),
              title: Text('Abrir último trabajo'),
            ),
          ),
        if (bike.isActive && canOpenWorkshopJob)
          const PopupMenuItem(
            value: 'new-job',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.add_circle_outline_rounded),
              title: Text('Nuevo trabajo'),
            ),
          ),
      ],
      icon: Icon(
        Icons.more_vert_rounded,
        size: 20,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildRowActions(
    ThemeData theme,
    Bike bike,
    _BikeFinderMetrics metrics,
  ) {
    final canOpenWorkshopJob =
        metrics.latestWorkshopJobId?.trim().isNotEmpty == true;
    if (canOpenWorkshopJob) {
      return _buildWorkAction(
        theme,
        label: 'Abrir trabajo',
        icon: Icons.handyman_outlined,
        color: Colors.orange.shade800,
        tooltip: 'Abrir trabajo actual',
        onTap: () => _openWorkshopJob(metrics),
      );
    }

    final canOpenLatestJob = metrics.latestJobId?.trim().isNotEmpty == true;
    final canOpenLatestInvoice =
        metrics.latestJobInvoiceId?.trim().isNotEmpty == true;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canOpenLatestJob)
          _buildWorkAction(
            theme,
            label: canOpenLatestInvoice ? 'Factura' : 'Último trabajo',
            icon: canOpenLatestInvoice
                ? Icons.receipt_long_outlined
                : Icons.history_rounded,
            color: theme.colorScheme.onSurfaceVariant,
            tooltip: canOpenLatestInvoice
                ? 'Abrir última factura'
                : 'Abrir último trabajo',
            onTap: canOpenLatestInvoice
                ? () => _openLatestInvoice(metrics)
                : () => _openLatestJob(metrics),
          ),
        if (canOpenLatestJob && bike.isActive) const SizedBox(width: 2),
        if (bike.isActive)
          _buildWorkAction(
            theme,
            label: canOpenLatestJob ? 'Nuevo' : 'Nuevo trabajo',
            icon: Icons.add_rounded,
            color: theme.colorScheme.primary,
            tooltip: 'Crear nuevo trabajo',
            onTap: () => _openNewJob(bike),
          ),
      ],
    );
  }

  Widget? _buildBikeStatus(
    ThemeData theme,
    Bike bike,
    _BikeFinderMetrics metrics,
  ) {
    late final IconData icon;
    late final String label;
    late final Color color;

    if (!bike.isActive) {
      icon = Icons.inventory_2_outlined;
      label = 'Archivada';
      color = theme.colorScheme.onSurfaceVariant;
    } else if (metrics.workshopJobs > 0) {
      icon = Icons.circle;
      label = metrics.workshopJobs == 1
          ? 'En taller'
          : '${metrics.workshopJobs} en taller';
      color = Colors.orange.shade800;
    } else if (bike.isUnderWarranty) {
      icon = Icons.verified_user_outlined;
      label = 'Garantía vigente';
      color = Colors.green.shade700;
    } else {
      return null;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: icon == Icons.circle ? 7 : 14, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildWorkAction(
    ThemeData theme, {
    required String label,
    required IconData icon,
    required Color color,
    String? tooltip,
    required VoidCallback onTap,
  }) {
    final button = TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        textStyle: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }

  Widget _buildBikeFact(
    ThemeData theme, {
    required IconData icon,
    required String label,
    Color? color,
  }) {
    final fg = color ?? theme.colorScheme.onSurface.withValues(alpha: 0.66);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: fg),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: fg,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _BikeFinderResult {
  final Bike bike;
  final Customer? owner;
  final _BikeFinderMetrics metrics;
  final int score;

  const _BikeFinderResult({
    required this.bike,
    required this.owner,
    required this.metrics,
    required this.score,
  });
}

class _BikeFinderMetrics {
  final int totalJobs;
  final int workshopJobs;
  final DateTime? lastDeliveredAt;
  final DateTime? lastArrivalAt;
  final String? latestJobId;
  final String? latestJobInvoiceId;
  final DateTime? latestJobAt;
  final DateTime? latestJobUpdatedAt;
  final String? latestWorkshopJobId;
  final DateTime? latestWorkshopJobAt;

  const _BikeFinderMetrics({
    this.totalJobs = 0,
    this.workshopJobs = 0,
    this.lastDeliveredAt,
    this.lastArrivalAt,
    this.latestJobId,
    this.latestJobInvoiceId,
    this.latestJobAt,
    this.latestJobUpdatedAt,
    this.latestWorkshopJobId,
    this.latestWorkshopJobAt,
  });

  bool get hasHistory => totalJobs > 0;
  DateTime? get lastActivityAt {
    if (lastDeliveredAt == null) return lastArrivalAt;
    if (lastArrivalAt == null) return lastDeliveredAt;
    return lastArrivalAt!.isAfter(lastDeliveredAt!)
        ? lastArrivalAt
        : lastDeliveredAt;
  }

  _BikeFinderMetrics copyWith({
    int? totalJobs,
    int? workshopJobs,
    DateTime? lastDeliveredAt,
    DateTime? lastArrivalAt,
    String? latestJobId,
    String? latestJobInvoiceId,
    bool clearLatestJobInvoiceId = false,
    DateTime? latestJobAt,
    DateTime? latestJobUpdatedAt,
    String? latestWorkshopJobId,
    DateTime? latestWorkshopJobAt,
  }) {
    return _BikeFinderMetrics(
      totalJobs: totalJobs ?? this.totalJobs,
      workshopJobs: workshopJobs ?? this.workshopJobs,
      lastDeliveredAt: lastDeliveredAt ?? this.lastDeliveredAt,
      lastArrivalAt: lastArrivalAt ?? this.lastArrivalAt,
      latestJobId: latestJobId ?? this.latestJobId,
      latestJobInvoiceId: clearLatestJobInvoiceId
          ? null
          : (latestJobInvoiceId ?? this.latestJobInvoiceId),
      latestJobAt: latestJobAt ?? this.latestJobAt,
      latestJobUpdatedAt: latestJobUpdatedAt ?? this.latestJobUpdatedAt,
      latestWorkshopJobId: latestWorkshopJobId ?? this.latestWorkshopJobId,
      latestWorkshopJobAt: latestWorkshopJobAt ?? this.latestWorkshopJobAt,
    );
  }
}
