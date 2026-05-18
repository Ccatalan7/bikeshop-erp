import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../modules/bikeshop/models/bikeshop_models.dart';
import '../../modules/bikeshop/services/bikeshop_service.dart';
import '../../modules/crm/models/crm_models.dart';
import '../../modules/crm/services/customer_service.dart';
import '../services/workspace_manager.dart';

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
  Map<String, int> _bikeCountByCustomerId = const {};

  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isLoadingJobMetrics = false;
  String? _error;

  String _searchTerm = '';
  String? _selectedBrand;
  String? _selectedModel;
  bool _onlyWithHistory = false;
  bool _onlyWarranty = false;
  bool _onlyActiveJobs = false;

  final Set<String> _expandedCustomerIds = <String>{};

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
    _bikeCountByCustomerId = _buildOwnerBikeCounts(bikes);
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
        _bikeCountByCustomerId = _buildOwnerBikeCounts(bikes);
        if (_selectedBrand != null && !_brandOptions.contains(_selectedBrand)) {
          _selectedBrand = null;
        }
        if (_selectedModel != null && !_modelOptions.contains(_selectedModel)) {
          _selectedModel = null;
        }
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

  Map<String, int> _buildOwnerBikeCounts(List<Bike> bikes) {
    final counts = <String, int>{};
    for (final bike in bikes) {
      final customerId = bike.customerId.trim();
      if (customerId.isEmpty) continue;
      counts.update(customerId, (value) => value + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  Map<String, _BikeFinderMetrics> _buildMetrics(List<MechanicJob> jobs) {
    final metrics = <String, _BikeFinderMetrics>{};

    for (final job in jobs) {
      final bikeId = job.bikeId?.trim();
      if (bikeId == null || bikeId.isEmpty) continue;

      final previous = metrics[bikeId] ?? const _BikeFinderMetrics();
      final lastDeliveredAt = previous.lastDeliveredAt == null
          ? job.deliveredAt
          : _maxDate(previous.lastDeliveredAt, job.deliveredAt);
      final lastArrivalAt = _maxDate(previous.lastArrivalAt, job.arrivalDate);

      metrics[bikeId] = previous.copyWith(
        totalJobs: previous.totalJobs + 1,
        activeJobs: previous.activeJobs + (job.isActive ? 1 : 0),
        lastDeliveredAt: lastDeliveredAt,
        lastArrivalAt: lastArrivalAt,
      );
    }

    return metrics;
  }

  DateTime? _maxDate(DateTime? left, DateTime? right) {
    if (left == null) return right;
    if (right == null) return left;
    return right.isAfter(left) ? right : left;
  }

  List<String> get _brandOptions {
    final brands = _bikes
        .map((bike) => bike.brand?.trim() ?? '')
        .where((brand) => brand.isNotEmpty)
        .toSet()
        .toList();
    brands.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return brands;
  }

  List<String> get _modelOptions {
    final models = _bikes
        .where((bike) => _selectedBrand == null || bike.brand == _selectedBrand)
        .map((bike) => bike.model?.trim() ?? '')
        .where((model) => model.isNotEmpty)
        .toSet()
        .toList();
    models.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return models;
  }

  List<_BikeFinderResult> _buildResults() {
    final query = _normalize(_searchTerm);
    final results = <_BikeFinderResult>[];

    for (final bike in _bikes) {
      final bikeId = bike.id;
      if (bikeId == null || bikeId.isEmpty) continue;

      if (_selectedBrand != null && bike.brand != _selectedBrand) continue;
      if (_selectedModel != null && bike.model != _selectedModel) continue;

      final owner = _customersById[bike.customerId];
      final metrics = _metricsByBikeId[bikeId] ?? const _BikeFinderMetrics();

      if (_onlyWithHistory && !metrics.hasHistory) continue;
      if (_onlyWarranty && !bike.isUnderWarranty) continue;
      if (_onlyActiveJobs && metrics.activeJobs == 0) continue;

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
          right.metrics.activeJobs.compareTo(left.metrics.activeJobs);
      if (activeCompare != 0) return activeCompare;

      final historyCompare = (right.metrics.lastDeliveredAt ??
              right.metrics.lastArrivalAt ??
              DateTime(0))
          .compareTo(left.metrics.lastDeliveredAt ??
              left.metrics.lastArrivalAt ??
              DateTime(0));
      if (historyCompare != 0) return historyCompare;

      return right.bike.updatedAt.compareTo(left.bike.updatedAt);
    });

    return results;
  }

  int _scoreBikeResult({
    required Bike bike,
    required Customer? owner,
    required _BikeFinderMetrics metrics,
    required String query,
  }) {
    if (query.isEmpty) {
      var score = 10;
      if (metrics.activeJobs > 0) score += 60;
      if (metrics.hasHistory) score += 30;
      if (bike.isUnderWarranty) score += 20;
      return score;
    }

    var matchScore = 0;

    matchScore += _scoreField(bike.serialNumber, query,
        exact: 240, startsWith: 180, contains: 140);
    matchScore += _scoreField(bike.displayName, query,
        exact: 210, startsWith: 160, contains: 120);
    matchScore +=
        _scoreField(bike.brand, query, exact: 90, startsWith: 72, contains: 54);
    matchScore +=
        _scoreField(bike.model, query, exact: 90, startsWith: 72, contains: 54);
    matchScore +=
        _scoreField(bike.notes, query, exact: 35, startsWith: 24, contains: 18);
    matchScore += _scoreField(bike.bikeType?.displayName, query,
        exact: 30, startsWith: 24, contains: 18);

    matchScore += _scoreField(owner?.name, query,
        exact: 180, startsWith: 150, contains: 110);
    matchScore += _scoreField(owner?.rut, query,
        exact: 170, startsWith: 140, contains: 110);
    matchScore += _scoreField(owner?.phone, query,
        exact: 160, startsWith: 130, contains: 100);
    matchScore += _scoreField(owner?.email, query,
        exact: 150, startsWith: 120, contains: 96);

    if (matchScore == 0) return 0;

    var rankScore = matchScore;
    if (metrics.activeJobs > 0) rankScore += 16;
    if (metrics.hasHistory) rankScore += 8;

    return rankScore;
  }

  int _scoreField(
    String? rawValue,
    String query, {
    required int exact,
    required int startsWith,
    required int contains,
  }) {
    final value = _normalize(rawValue);
    if (value.isEmpty) return 0;
    if (value == query) return exact;
    if (value.startsWith(query)) return startsWith;
    if (value.contains(query)) return contains;
    return 0;
  }

  String _normalize(String? value) {
    return (value ?? '')
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n');
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

  void _toggleOwnerExpansion(String customerId) {
    setState(() {
      if (_expandedCustomerIds.contains(customerId)) {
        _expandedCustomerIds.remove(customerId);
      } else {
        _expandedCustomerIds.add(customerId);
      }
    });
  }

  List<Bike> _otherBikesForCustomer(Bike bike) {
    final customerId = bike.customerId.trim();
    final currentBikeId = bike.id;
    if (customerId.isEmpty) return const [];

    final bikes = _bikes
        .where((candidate) =>
            candidate.customerId == customerId && candidate.id != currentBikeId)
        .toList();

    bikes.sort((left, right) {
      final leftMetrics = left.id != null
          ? (_metricsByBikeId[left.id!] ?? const _BikeFinderMetrics())
          : const _BikeFinderMetrics();
      final rightMetrics = right.id != null
          ? (_metricsByBikeId[right.id!] ?? const _BikeFinderMetrics())
          : const _BikeFinderMetrics();
      return (rightMetrics.lastDeliveredAt ?? right.updatedAt)
          .compareTo(leftMetrics.lastDeliveredAt ?? left.updatedAt);
    });

    return bikes;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = _buildResults();

    return ColoredBox(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSearchArea(theme, results),
          if (_isRefreshing || _isLoadingJobMetrics)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _buildContent(theme, results),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchArea(ThemeData theme, List<_BikeFinderResult> results) {
    final summaryColor = theme.colorScheme.onSurface.withValues(alpha: 0.62);

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) {
              if (results.isNotEmpty) {
                _openBike(results.first.bike);
              }
            },
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Buscar cliente, bici, serie o teléfono',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_searchTerm.isNotEmpty)
                    IconButton(
                      tooltip: 'Limpiar búsqueda',
                      onPressed: () {
                        _searchController.clear();
                        _searchFocusNode.requestFocus();
                      },
                      icon: const Icon(Icons.close),
                    ),
                  IconButton(
                    tooltip: 'Actualizar',
                    onPressed: _isRefreshing
                        ? null
                        : () => _loadData(forceRefresh: true),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildFilterMenu(
                  theme,
                  label: 'Marca',
                  value: _selectedBrand,
                  allLabel: 'Todas',
                  options: _brandOptions,
                  onChanged: (value) {
                    setState(() {
                      _selectedBrand = value;
                      if (_selectedModel != null &&
                          !_modelOptions.contains(_selectedModel)) {
                        _selectedModel = null;
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildFilterMenu(
                  theme,
                  label: 'Modelo',
                  value: _selectedModel,
                  allLabel: 'Todos',
                  options: _modelOptions,
                  onChanged: (value) {
                    setState(() {
                      _selectedModel = value;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildToggleFilter(
                theme,
                icon: Icons.history_rounded,
                label: 'Historial',
                selected: _onlyWithHistory,
                onTap: () =>
                    setState(() => _onlyWithHistory = !_onlyWithHistory),
              ),
              _buildToggleFilter(
                theme,
                icon: Icons.build_circle_outlined,
                label: 'Activas',
                selected: _onlyActiveJobs,
                color: Colors.orange.shade700,
                onTap: () => setState(() => _onlyActiveJobs = !_onlyActiveJobs),
              ),
              _buildToggleFilter(
                theme,
                icon: Icons.verified_user_outlined,
                label: 'Garantía',
                selected: _onlyWarranty,
                color: Colors.green.shade700,
                onTap: () => setState(() => _onlyWarranty = !_onlyWarranty),
              ),
              if (_hasActiveFilters) _buildClearFiltersButton(theme),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  _buildSummaryText(results),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: summaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${results.length}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterMenu(
    ThemeData theme, {
    required String label,
    required String? value,
    required String allLabel,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isDense: true,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: theme.colorScheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: [
        DropdownMenuItem<String>(
          value: null,
          child: Text(allLabel),
        ),
        ...options.map(
          (option) => DropdownMenuItem<String>(
            value: option,
            child: Text(
              option,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }

  Widget _buildToggleFilter(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Color? color,
  }) {
    final accent = color ?? theme.colorScheme.primary;
    return Material(
      color:
          selected ? accent.withValues(alpha: 0.12) : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.55)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.52),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check_rounded : icon,
                size: 15,
                color: selected ? accent : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected ? accent : theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClearFiltersButton(ThemeData theme) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: _clearFilters,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Text(
            'Limpiar',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  void _clearFilters() {
    setState(() {
      _selectedBrand = null;
      _selectedModel = null;
      _onlyWithHistory = false;
      _onlyActiveJobs = false;
      _onlyWarranty = false;
    });
  }

  bool get _hasActiveFilters {
    return _selectedBrand != null ||
        _selectedModel != null ||
        _onlyWithHistory ||
        _onlyActiveJobs ||
        _onlyWarranty;
  }

  String _buildSummaryText(List<_BikeFinderResult> results) {
    final owners = results
        .map((result) => result.owner?.id)
        .whereType<String>()
        .toSet()
        .length;
    final total = results.length;

    if (_searchTerm.isEmpty && !_hasActiveFilters) {
      return 'Acceso rápido a bicicletas recientes, con contexto de servicio y cliente.';
    }

    return '$total bicicleta${total == 1 ? '' : 's'} · $owners cliente${owners == 1 ? '' : 's'}';
  }

  Widget _buildContent(ThemeData theme, List<_BikeFinderResult> results) {
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
                'Prueba buscando por cliente, serie, marca, modelo o quitando filtros.',
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
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        itemCount: results.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) =>
            _buildResultTile(theme, results[index]),
      ),
    );
  }

  Widget _buildResultTile(ThemeData theme, _BikeFinderResult result) {
    final bike = result.bike;
    final owner = result.owner;
    final metrics = result.metrics;
    final customerId = bike.customerId.trim();
    final ownerName = owner?.name.trim().isNotEmpty == true
        ? owner!.name.trim()
        : 'Cliente desconocido';
    final ownerInitials = ownerName
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    final ownerBikeCount = _bikeCountByCustomerId[customerId] ?? 0;
    final isExpanded = _expandedCustomerIds.contains(customerId);
    final otherBikes =
        isExpanded ? _otherBikesForCustomer(bike) : const <Bike>[];
    final accentColor = metrics.activeJobs > 0
        ? Colors.orange.shade700
        : (bike.isUnderWarranty
            ? Colors.green.shade700
            : theme.colorScheme.primary);
    final phone = owner?.phone?.trim();
    final serial = bike.serialNumber?.trim();

    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openBike(bike),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Center(
                      child: Text(
                        ownerInitials.isEmpty ? '?' : ownerInitials,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: accentColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bike.displayName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.person_outline,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                ownerName,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.72),
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if ((phone?.isNotEmpty ?? false) ||
                            (serial?.isNotEmpty ?? false))
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 3,
                              children: [
                                if (phone?.isNotEmpty ?? false)
                                  _buildBikeFact(
                                    theme,
                                    icon: Icons.phone_iphone_outlined,
                                    label: phone!,
                                  ),
                                if (serial?.isNotEmpty ?? false)
                                  _buildBikeFact(
                                    theme,
                                    icon: Icons.qr_code_2_outlined,
                                    label: 'Serie $serial',
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildBikeStatusBadge(theme, bike, metrics, accentColor),
                  IconButton(
                    tooltip: 'Abrir ficha',
                    onPressed: () => _openBike(bike),
                    icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                children: [
                  if ((bike.brand?.trim().isNotEmpty ?? false))
                    _buildBikeFact(
                      theme,
                      label: bike.brand!.trim(),
                      icon: Icons.sell_outlined,
                    ),
                  if ((bike.model?.trim().isNotEmpty ?? false))
                    _buildBikeFact(
                      theme,
                      label: bike.model!.trim(),
                      icon: Icons.category_outlined,
                    ),
                  if (metrics.totalJobs > 0)
                    _buildBikeFact(
                      theme,
                      label:
                          '${metrics.totalJobs} servicio${metrics.totalJobs == 1 ? '' : 's'}',
                      icon: Icons.history,
                    ),
                  if (metrics.activeJobs > 0)
                    _buildBikeFact(
                      theme,
                      label:
                          '${metrics.activeJobs} activo${metrics.activeJobs == 1 ? '' : 's'}',
                      icon: Icons.build_circle_outlined,
                      color: Colors.orange.shade800,
                    ),
                  if (metrics.lastDeliveredAt != null)
                    _buildBikeFact(
                      theme,
                      label:
                          'Últ. ${_dateFormat.format(metrics.lastDeliveredAt!)}',
                      icon: Icons.event_available_outlined,
                    ),
                ],
              ),
              const SizedBox(height: 11),
              Row(
                children: [
                  if (ownerBikeCount > 1)
                    TextButton.icon(
                      onPressed: () => _toggleOwnerExpansion(customerId),
                      icon: Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 18,
                      ),
                      label: Text('$ownerBikeCount bicis'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    )
                  else
                    const Spacer(),
                  if (ownerBikeCount > 1) const Spacer(),
                  _buildFinderActionButton(
                    theme,
                    icon: Icons.pedal_bike_outlined,
                    label: 'Bici',
                    onTap: () => _openBike(bike),
                  ),
                  const SizedBox(width: 8),
                  _buildFinderActionButton(
                    theme,
                    icon: Icons.person_outline,
                    label: 'Cliente',
                    onTap: () => _openClient(bike),
                  ),
                ],
              ),
              if (ownerBikeCount > 1 && isExpanded)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Otras bicicletas de $ownerName',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.62),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (otherBikes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    children: otherBikes
                        .map((otherBike) =>
                            _buildSiblingBikeRow(theme, otherBike))
                        .toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBikeStatusBadge(
    ThemeData theme,
    Bike bike,
    _BikeFinderMetrics metrics,
    Color accentColor,
  ) {
    final label = metrics.activeJobs > 0
        ? '${metrics.activeJobs} activo${metrics.activeJobs == 1 ? '' : 's'}'
        : bike.isUnderWarranty
            ? 'Garantía'
            : metrics.hasHistory
                ? 'Historial'
                : 'Ficha';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: accentColor,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
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

  Widget _buildFinderActionButton(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: const Size(0, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    );
  }

  Widget _buildSiblingBikeRow(ThemeData theme, Bike bike) {
    final metrics = bike.id != null
        ? (_metricsByBikeId[bike.id!] ?? const _BikeFinderMetrics())
        : const _BikeFinderMetrics();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openBike(bike),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.45),
          ),
          child: Row(
            children: [
              const Icon(Icons.pedal_bike_outlined, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  bike.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (metrics.totalJobs > 0)
                Text(
                  '${metrics.totalJobs} svc',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              const SizedBox(width: 6),
              const Icon(Icons.arrow_forward_ios_rounded, size: 14),
            ],
          ),
        ),
      ),
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
  final int activeJobs;
  final DateTime? lastDeliveredAt;
  final DateTime? lastArrivalAt;

  const _BikeFinderMetrics({
    this.totalJobs = 0,
    this.activeJobs = 0,
    this.lastDeliveredAt,
    this.lastArrivalAt,
  });

  bool get hasHistory => totalJobs > 0;

  _BikeFinderMetrics copyWith({
    int? totalJobs,
    int? activeJobs,
    DateTime? lastDeliveredAt,
    DateTime? lastArrivalAt,
  }) {
    return _BikeFinderMetrics(
      totalJobs: totalJobs ?? this.totalJobs,
      activeJobs: activeJobs ?? this.activeJobs,
      lastDeliveredAt: lastDeliveredAt ?? this.lastDeliveredAt,
      lastArrivalAt: lastArrivalAt ?? this.lastArrivalAt,
    );
  }
}
