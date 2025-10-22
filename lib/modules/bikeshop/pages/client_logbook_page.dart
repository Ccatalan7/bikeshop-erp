import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../modules/crm/models/crm_models.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../modules/crm/services/customer_service.dart';
import '../services/bikeshop_service.dart';
import '../models/bikeshop_models.dart';
import 'bike_form_dialog.dart';

enum JobViewFilter { active, completed, all }

class ClientLogbookPage extends StatefulWidget {
  final String customerId;
  final String? initialTab;

  const ClientLogbookPage({
    super.key,
    required this.customerId,
    this.initialTab,
  });

  @override
  State<ClientLogbookPage> createState() => _ClientLogbookPageState();
}

class _ClientLogbookPageState extends State<ClientLogbookPage> {
  Customer? _customer;
  List<Bike> _bikes = [];
  List<MechanicJob> _jobs = [];
  List<MechanicJobTimeline> _timeline = [];
  Loyalty? _loyalty;
  bool _isLoading = true;
  String? _error;
  late int _initialTabIndex;
  final TextEditingController _bikeSearchController = TextEditingController();
  final TextEditingController _jobSearchController = TextEditingController();
  final TextEditingController _timelineSearchController =
      TextEditingController();
  String _bikeSearchTerm = '';
  String _jobSearchTerm = '';
  String _timelineSearchTerm = '';
  String _bikeSortKey = 'recent';
  String _jobSortKey = 'arrival_desc';
  String _timelineSortKey = 'date_desc';
  JobViewFilter _jobViewFilter = JobViewFilter.active;
  Map<String, Bike> _bikeIndex = {};
  Map<String, List<MechanicJob>> _jobsByBike = {};
  Map<String, MechanicJob> _jobIndex = {};
  Set<TimelineEventType> _timelineTypeFilters =
      TimelineEventType.values.toSet();
  static const Map<String, String> _bikeSortLabels = {
    'recent': 'Más recientes',
    'name': 'Nombre (A-Z)',
    'jobs_desc': 'Más pegas',
    'jobs_asc': 'Menos pegas',
  };
  static const Map<String, String> _jobSortLabels = {
    'arrival_desc': 'Ingresadas recientes',
    'arrival_asc': 'Ingresadas antiguas',
    'cost_desc': 'Mayor costo',
    'cost_asc': 'Menor costo',
  };
  static const Map<String, String> _timelineSortLabels = {
    'date_desc': 'Más recientes',
    'date_asc': 'Más antiguas',
  };

  static const List<String> _tabKeys = [
    'resumen',
    'bicicletas',
    'pegas',
    'historial'
  ];

  @override
  void initState() {
    super.initState();
    _bikeSearchController.addListener(_handleBikeSearchChanged);
    _jobSearchController.addListener(_handleJobSearchChanged);
    _timelineSearchController.addListener(_handleTimelineSearchChanged);
    _initialTabIndex = _resolveInitialTab(widget.initialTab);
    _loadData();
  }

  @override
  void dispose() {
    _bikeSearchController.removeListener(_handleBikeSearchChanged);
    _jobSearchController.removeListener(_handleJobSearchChanged);
    _timelineSearchController.removeListener(_handleTimelineSearchChanged);
    _bikeSearchController.dispose();
    _jobSearchController.dispose();
    _timelineSearchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ClientLogbookPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab) {
      final newIndex = _resolveInitialTab(widget.initialTab);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final controller = DefaultTabController.maybeOf(context);
        if (controller != null && controller.index != newIndex) {
          controller.animateTo(newIndex);
        }
      });
    }
  }

  int _resolveInitialTab(String? key) {
    if (key == null) return 0;
    final normalized = key.toLowerCase();
    final index = _tabKeys.indexOf(normalized);
    return index >= 0 ? index : 0;
  }

  void _handleBikeSearchChanged() {
    setState(() {
      _bikeSearchTerm = _bikeSearchController.text.trim();
    });
  }

  void _handleJobSearchChanged() {
    setState(() {
      _jobSearchTerm = _jobSearchController.text.trim();
    });
  }

  void _handleTimelineSearchChanged() {
    setState(() {
      _timelineSearchTerm = _timelineSearchController.text.trim();
    });
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final customerService =
          Provider.of<CustomerService>(context, listen: false);
      final bikeshopService =
          Provider.of<BikeshopService>(context, listen: false);

      // Load customer data
      final customer = await customerService.getCustomerById(widget.customerId);
      final loyalty =
          await customerService.getCustomerLoyalty(widget.customerId);

      if (customer == null) {
        setState(() {
          _error = 'Cliente no encontrado';
          _isLoading = false;
        });
        return;
      }

      // Load bikes for this customer
      final bikes =
          await bikeshopService.getBikes(customerId: widget.customerId);
      final bikeIndex = <String, Bike>{
        for (final bike in bikes)
          if (bike.id != null && bike.id!.isNotEmpty) bike.id!: bike,
      };

      // Load all jobs for this customer
      final jobs = await bikeshopService.getJobs(
        customerId: widget.customerId,
        includeCompleted: true,
      );
      final jobsByBike = <String, List<MechanicJob>>{};
      final jobIndex = <String, MechanicJob>{};
      for (final job in jobs) {
        if (job.id != null && job.id!.isNotEmpty) {
          jobIndex[job.id!] = job;
        }
        jobsByBike.putIfAbsent(job.bikeId, () => []).add(job);
      }

      // Load combined timeline from all jobs
      final allTimeline = <MechanicJobTimeline>[];
      for (final job in jobs) {
        final jobTimeline = await bikeshopService.getJobTimeline(job.id!);
        allTimeline.addAll(jobTimeline);
      }

      // Sort timeline by date descending (most recent first)
      allTimeline.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      setState(() {
        _customer = customer;
        _bikes = bikes;
        _jobs = jobs;
        _bikeIndex = bikeIndex;
        _jobsByBike = jobsByBike;
        _jobIndex = jobIndex;
        _timeline = allTimeline;
        _loyalty = loyalty;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error al cargar datos: $e';
        _isLoading = false;
      });
    }
  }

  List<Bike> _getFilteredBikes() {
    final term = _bikeSearchTerm.toLowerCase();
    final filtered = _bikes.where((bike) {
      if (term.isEmpty) return true;
      final candidates = [
        bike.displayName,
        bike.brand,
        bike.model,
        bike.serialNumber,
        bike.color,
        bike.notes,
        bike.bikeType?.displayName,
      ];
      return candidates.any(
        (value) => value != null && value.toLowerCase().contains(term),
      );
    }).toList();

    filtered.sort((a, b) {
      switch (_bikeSortKey) {
        case 'name':
          return a.displayName.toLowerCase().compareTo(
                b.displayName.toLowerCase(),
              );
        case 'jobs_desc':
          final aCount = _totalJobsForBike(a.id);
          final bCount = _totalJobsForBike(b.id);
          return bCount.compareTo(aCount);
        case 'jobs_asc':
          final aCount = _totalJobsForBike(a.id);
          final bCount = _totalJobsForBike(b.id);
          return aCount.compareTo(bCount);
        case 'recent':
        default:
          return b.updatedAt.compareTo(a.updatedAt);
      }
    });

    return filtered;
  }

  List<MechanicJob> _getFilteredJobs() {
    Iterable<MechanicJob> filtered = _jobs;

    switch (_jobViewFilter) {
      case JobViewFilter.active:
        filtered = filtered.where((job) =>
            job.status != JobStatus.entregado &&
            job.status != JobStatus.cancelado);
        break;
      case JobViewFilter.completed:
        filtered = filtered.where((job) => job.status == JobStatus.entregado);
        break;
      case JobViewFilter.all:
        break;
    }

    final term = _jobSearchTerm.toLowerCase();
    if (term.isNotEmpty) {
      filtered = filtered.where((job) {
        final bikeName = _bikeIndex[job.bikeId]?.displayName;
        final candidates = [
          job.jobNumber,
          job.clientRequest,
          job.diagnosis,
          job.workPerformed,
          job.notes,
          job.assignedTechnicianName,
          bikeName,
        ];
        return candidates.any(
          (value) => value != null && value.toLowerCase().contains(term),
        );
      });
    }

    final result = filtered.toList();
    result.sort((a, b) {
      switch (_jobSortKey) {
        case 'arrival_asc':
          return a.arrivalDate.compareTo(b.arrivalDate);
        case 'cost_desc':
          return b.totalCost.compareTo(a.totalCost);
        case 'cost_asc':
          return a.totalCost.compareTo(b.totalCost);
        case 'arrival_desc':
        default:
          return b.arrivalDate.compareTo(a.arrivalDate);
      }
    });

    return result;
  }

  int _totalJobsForBike(String? bikeId) {
    if (bikeId == null) return 0;
    return _jobsByBike[bikeId]?.length ?? 0;
  }

  int _activeJobsForBike(String? bikeId) {
    if (bikeId == null) return 0;
    final jobs = _jobsByBike[bikeId];
    if (jobs == null) return 0;
    return jobs
        .where((job) =>
            job.status != JobStatus.entregado &&
            job.status != JobStatus.cancelado)
        .length;
  }

  String _jobFilterLabel(JobViewFilter filter) {
    switch (filter) {
      case JobViewFilter.active:
        return 'Activas';
      case JobViewFilter.completed:
        return 'Entregadas';
      case JobViewFilter.all:
        return 'Todas';
    }
  }

  Bike _getBikeForJob(MechanicJob job) {
    final bike = _bikeIndex[job.bikeId];
    if (bike != null) return bike;
    return Bike(
      id: job.bikeId,
      customerId: job.customerId,
      brand: 'Bicicleta',
      model: 'sin datos',
      bikeType: BikeType.other,
      createdAt: job.createdAt,
      updatedAt: job.updatedAt,
    );
  }

  List<MechanicJobTimeline> _getFilteredTimeline() {
    Iterable<MechanicJobTimeline> filtered = _timeline;

    if (_timelineTypeFilters.isNotEmpty &&
        _timelineTypeFilters.length < TimelineEventType.values.length) {
      filtered = filtered.where(
        (event) => _timelineTypeFilters.contains(event.eventType),
      );
    }

    final term = _timelineSearchTerm.toLowerCase();
    if (term.isNotEmpty) {
      filtered = filtered.where((event) {
        final job = event.jobId.isNotEmpty ? _jobIndex[event.jobId] : null;
        final bike = job != null ? _bikeIndex[job.bikeId] : null;
        final defaultDescription = _getDefaultDescription(event.eventType);
        final candidates = [
          event.description,
          defaultDescription,
          event.oldValue,
          event.newValue,
          event.createdByName,
          job?.jobNumber,
          bike?.displayName,
        ];
        return candidates.any(
          (value) => value != null && value.toLowerCase().contains(term),
        );
      });
    }

    final result = filtered.toList();
    result.sort((a, b) {
      switch (_timelineSortKey) {
        case 'date_asc':
          return a.createdAt.compareTo(b.createdAt);
        case 'date_desc':
        default:
          return b.createdAt.compareTo(a.createdAt);
      }
    });

    return result;
  }

  String _timelineEventLabel(TimelineEventType type) {
    return type.displayName;
  }

  IconData _timelineIcon(TimelineEventType type) {
    switch (type) {
      case TimelineEventType.created:
        return Icons.add_circle;
      case TimelineEventType.statusChanged:
        return Icons.swap_horiz;
      case TimelineEventType.assigned:
        return Icons.person_add;
      case TimelineEventType.diagnosisAdded:
        return Icons.description;
      case TimelineEventType.partsAdded:
        return Icons.build_circle;
      case TimelineEventType.laborAdded:
        return Icons.work;
      case TimelineEventType.photoAdded:
        return Icons.photo_camera;
      case TimelineEventType.noteAdded:
        return Icons.note;
      case TimelineEventType.approved:
        return Icons.check_circle;
      case TimelineEventType.invoiced:
        return Icons.receipt;
      case TimelineEventType.paid:
        return Icons.attach_money;
      case TimelineEventType.completed:
        return Icons.done_all;
      case TimelineEventType.delivered:
        return Icons.local_shipping;
    }
  }

  Color _timelineColor(TimelineEventType type) {
    switch (type) {
      case TimelineEventType.created:
        return Colors.blue;
      case TimelineEventType.statusChanged:
        return Colors.purple;
      case TimelineEventType.assigned:
        return Colors.teal;
      case TimelineEventType.diagnosisAdded:
        return Colors.orange;
      case TimelineEventType.partsAdded:
        return Colors.amber;
      case TimelineEventType.laborAdded:
        return Colors.indigo;
      case TimelineEventType.photoAdded:
        return Colors.pink;
      case TimelineEventType.noteAdded:
        return Colors.cyan;
      case TimelineEventType.approved:
        return Colors.green;
      case TimelineEventType.invoiced:
        return Colors.deepPurple;
      case TimelineEventType.paid:
        return Colors.green;
      case TimelineEventType.completed:
        return Colors.teal;
      case TimelineEventType.delivered:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: _customer?.name ?? 'Historial del Cliente',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          size: 64, color: Colors.red[300]),
                      const SizedBox(height: 16),
                      Text(_error!, style: const TextStyle(fontSize: 16)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _loadData,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : _customer == null
                  ? const Center(child: Text('Cliente no encontrado'))
                  : _buildContent(),
    );
  }

  Widget _buildContent() {
    final initialIndex = _initialTabIndex.clamp(0, _tabKeys.length - 1);

    return DefaultTabController(
      length: _tabKeys.length,
      initialIndex: initialIndex,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCustomerHeader(),
            const SizedBox(height: 24),
            _buildTabBar(),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                children: [
                  _buildSummaryTab(),
                  _buildBikesTab(),
                  _buildJobsTab(),
                  _buildTimelineTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerHeader() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 40,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                _customer!.name.substring(0, 1).toUpperCase(),
                style: TextStyle(
                  fontSize: 32,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 24),
            // Customer Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _customer!.name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  if (_customer!.phone != null)
                    Row(
                      children: [
                        Icon(Icons.phone, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Text(
                          _customer!.phone!,
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  if (_customer!.email != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.email, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Text(
                          _customer!.email!,
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  ],
                  if (_customer!.rut.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.badge, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Text(
                          'RUT: ${_customer!.rut}',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // Actions
            Column(
              children: [
                ElevatedButton.icon(
                  onPressed: () => context
                      .push('/taller/pegas/nueva?customer_id=${_customer!.id}'),
                  icon: const Icon(Icons.add),
                  label: const Text('Nueva Pega'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () =>
                      context.push('/clientes/${_customer!.id}/editar'),
                  icon: const Icon(Icons.edit),
                  label: const Text('Editar Cliente'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withOpacity(0.3)),
        color: theme.colorScheme.surface,
      ),
      child: TabBar(
        labelColor: theme.colorScheme.primary,
        unselectedLabelColor: theme.textTheme.bodyMedium?.color,
        labelStyle:
            theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: theme.colorScheme.primary.withOpacity(0.12),
        ),
        tabs: const [
          Tab(icon: Icon(Icons.dashboard_outlined), text: 'Resumen'),
          Tab(icon: Icon(Icons.pedal_bike_outlined), text: 'Bicicletas'),
          Tab(icon: Icon(Icons.build_outlined), text: 'Pegas'),
          Tab(icon: Icon(Icons.timeline_outlined), text: 'Historial'),
        ],
      ),
    );
  }

  Widget _buildSummaryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatistics(),
          const SizedBox(height: 24),
          _buildContactCard(),
          if (_loyalty != null) ...[
            const SizedBox(height: 24),
            _buildLoyaltyCard(),
          ],
        ],
      ),
    );
  }

  Widget _buildBikesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: _buildBikesSection(),
    );
  }

  Widget _buildJobsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: _buildJobsSection(),
    );
  }

  Widget _buildTimelineTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: _buildTimelineSection(),
    );
  }

  Widget _buildContactCard() {
    if (_customer == null) return const SizedBox.shrink();

    final entries = <Widget>[];

    if (_customer!.phone != null && _customer!.phone!.isNotEmpty) {
      entries.add(_buildContactRow(Icons.phone, 'Teléfono', _customer!.phone!));
    }
    if (_customer!.email != null && _customer!.email!.isNotEmpty) {
      entries.add(
          _buildContactRow(Icons.email_outlined, 'Email', _customer!.email!));
    }
    if (_customer!.address != null && _customer!.address!.isNotEmpty) {
      entries.add(_buildContactRow(
          Icons.home_outlined, 'Dirección', _customer!.address!));
    }
    if (_customer!.region != null && _customer!.region!.isNotEmpty) {
      entries.add(
          _buildContactRow(Icons.map_outlined, 'Región', _customer!.region!));
    }

    if (entries.isEmpty) {
      entries.add(
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Sin información de contacto registrada'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Información de contacto',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...entries,
          ],
        ),
      ),
    );
  }

  Widget _buildContactRow(IconData icon, String label, String value) {
    final theme = Theme.of(context);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(label,
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
      subtitle: Text(value,
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildLoyaltyCard() {
    final theme = Theme.of(context);
    final color = _getLoyaltyColor(_loyalty!.tier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Icon(_getLoyaltyIcon(_loyalty!.tier),
                      color: color, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getLoyaltyTierName(_loyalty!.tier),
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_loyalty!.points} puntos acumulados',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.primary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showAddPointsDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar puntos'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showRedeemPointsDialog,
                    icon: const Icon(Icons.redeem),
                    label: const Text('Canjear puntos'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getLoyaltyColor(LoyaltyTier tier) {
    switch (tier) {
      case LoyaltyTier.bronze:
        return Colors.brown;
      case LoyaltyTier.silver:
        return Colors.grey;
      case LoyaltyTier.gold:
        return Colors.amber;
      case LoyaltyTier.platinum:
        return Colors.purple;
    }
  }

  IconData _getLoyaltyIcon(LoyaltyTier tier) {
    switch (tier) {
      case LoyaltyTier.bronze:
      case LoyaltyTier.silver:
      case LoyaltyTier.gold:
        return Icons.workspace_premium;
      case LoyaltyTier.platinum:
        return Icons.diamond;
    }
  }

  String _getLoyaltyTierName(LoyaltyTier tier) {
    switch (tier) {
      case LoyaltyTier.bronze:
        return 'Bronce';
      case LoyaltyTier.silver:
        return 'Plata';
      case LoyaltyTier.gold:
        return 'Oro';
      case LoyaltyTier.platinum:
        return 'Platino';
    }
  }

  void _showAddPointsDialog() {
    final controller = TextEditingController();
    final customerService =
        Provider.of<CustomerService>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Agregar Puntos'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Cantidad de puntos',
            hintText: '100',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              final points = int.tryParse(controller.text);
              if (points == null || points <= 0) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Ingresa una cantidad válida de puntos'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              try {
                await customerService.addLoyaltyPoints(
                    widget.customerId, points);
                if (mounted) {
                  Navigator.of(dialogContext).pop();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Puntos agregados exitosamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  await _loadData();
                }
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Error agregando puntos: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  void _showRedeemPointsDialog() {
    final controller = TextEditingController();
    final customerService =
        Provider.of<CustomerService>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final availablePoints = _loyalty?.points ?? 0;

    if (availablePoints <= 0) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('El cliente no tiene puntos disponibles para canjear'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Canjear Puntos'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Puntos disponibles: $availablePoints'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Puntos a canjear',
                hintText: '100',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              final points = int.tryParse(controller.text);
              if (points == null || points <= 0) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Ingresa una cantidad válida de puntos'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              if (points > availablePoints) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('No hay puntos suficientes para canjear'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              try {
                await customerService.redeemLoyaltyPoints(
                    widget.customerId, points);
                if (mounted) {
                  Navigator.of(dialogContext).pop();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Puntos canjeados exitosamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  await _loadData();
                }
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Error canjeando puntos: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Canjear'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  Widget _buildStatistics() {
    final totalJobs = _jobs.length;
    final activeJobs = _jobs
        .where((j) =>
            j.status != JobStatus.entregado && j.status != JobStatus.cancelado)
        .length;
    final completedJobs =
        _jobs.where((j) => j.status == JobStatus.entregado).length;
    final totalSpent = _jobs
        .where((j) => j.status == JobStatus.entregado)
        .fold(0.0, (sum, j) => sum + j.totalCost);

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: Icons.two_wheeler,
            label: 'Bicicletas',
            value: _bikes.length.toString(),
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            icon: Icons.build,
            label: 'Total Pegas',
            value: totalJobs.toString(),
            color: Colors.purple,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            icon: Icons.pending_actions,
            label: 'Activas',
            value: activeJobs.toString(),
            color: Colors.orange,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            icon: Icons.check_circle,
            label: 'Completadas',
            value: completedJobs.toString(),
            color: Colors.green,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            icon: Icons.attach_money,
            label: 'Total Gastado',
            value: NumberFormat.currency(
              symbol: '\$',
              decimalDigits: 0,
            ).format(totalSpent),
            color: Colors.teal,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBikesSection() {
    final filteredBikes = _getFilteredBikes();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Bicicletas Registradas',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final result = await showDialog<bool>(
                  context: context,
                  builder: (context) => BikeFormDialog(
                    customerId: widget.customerId,
                  ),
                );

                if (result == true) {
                  // Reload data after adding bike
                  _loadData();
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Agregar Bicicleta'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildBikeFilters(
          total: _bikes.length,
          filtered: filteredBikes.length,
        ),
        const SizedBox(height: 16),
        if (filteredBikes.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.directions_bike,
                        size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      _bikes.isEmpty
                          ? 'No hay bicicletas registradas'
                          : 'No encontramos bicicletas que coincidan',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1.5,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: filteredBikes.length,
            itemBuilder: (context, index) =>
                _buildBikeCard(filteredBikes[index]),
          ),
      ],
    );
  }

  Widget _buildBikeCard(Bike bike) {
    final jobsForBike = _totalJobsForBike(bike.id);
    final activeJobsForBike = _activeJobsForBike(bike.id);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.pedal_bike,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    bike.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                PopupMenuButton<String>(
                  icon:
                      Icon(Icons.more_vert, color: Colors.grey[600], size: 20),
                  onSelected: (value) {
                    if (value == 'edit') {
                      _editBike(bike);
                    } else if (value == 'delete') {
                      _confirmDeleteBike(bike);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 20),
                          SizedBox(width: 8),
                          Text('Editar'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: 20, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Eliminar', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (bike.serialNumber != null) ...[
              Text(
                'S/N: ${bike.serialNumber}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              bike.bikeType?.displayName ?? 'N/A',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: activeJobsForBike > 0
                        ? Colors.orange[100]
                        : Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$jobsForBike pegas',
                    style: TextStyle(
                      fontSize: 12,
                      color: activeJobsForBike > 0
                          ? Colors.orange[900]
                          : Colors.grey[700],
                    ),
                  ),
                ),
                if (bike.isUnderWarranty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.verified_user,
                            size: 12, color: Colors.green[900]),
                        const SizedBox(width: 4),
                        Text(
                          'Garantía',
                          style:
                              TextStyle(fontSize: 12, color: Colors.green[900]),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBikeFilters({required int total, required int filtered}) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _bikeSearchController,
                    decoration: const InputDecoration(
                      labelText: 'Buscar bicicleta',
                      hintText: 'Marca, modelo o n° de serie',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    value: _bikeSortKey,
                    decoration: const InputDecoration(labelText: 'Ordenar por'),
                    items: _bikeSortLabels.entries
                        .map(
                          (entry) => DropdownMenuItem<String>(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _bikeSortKey = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              filtered == total
                  ? '$total bicicletas registradas'
                  : '$filtered de $total bicicletas coinciden',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobsSection() {
    final filteredJobs = _getFilteredJobs();
    final activeCount = _jobs
        .where((j) =>
            j.status != JobStatus.entregado && j.status != JobStatus.cancelado)
        .length;
    final completedCount =
        _jobs.where((j) => j.status == JobStatus.entregado).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Pegas del Taller',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            Wrap(
              spacing: 8,
              children: [
                _buildJobSummaryChip(
                  label: 'Activas',
                  count: activeCount,
                  color: Colors.orange,
                ),
                _buildJobSummaryChip(
                  label: 'Entregadas',
                  count: completedCount,
                  color: Colors.green,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildJobFilters(
          total: _jobs.length,
          filtered: filteredJobs.length,
        ),
        const SizedBox(height: 16),
        if (filteredJobs.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.auto_fix_high,
                        size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      _jobs.isEmpty
                          ? 'Este cliente aún no tiene pegas registradas'
                          : 'No encontramos pegas que coincidan',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filteredJobs.length,
            itemBuilder: (context, index) => _buildJobCard(filteredJobs[index]),
          ),
      ],
    );
  }

  Widget _buildJobFilters({required int total, required int filtered}) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _jobSearchController,
                    decoration: const InputDecoration(
                      labelText: 'Buscar pega',
                      hintText: 'Número, técnico o nota',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    value: _jobSortKey,
                    decoration: const InputDecoration(labelText: 'Ordenar por'),
                    items: _jobSortLabels.entries
                        .map(
                          (entry) => DropdownMenuItem<String>(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _jobSortKey = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: JobViewFilter.values.map((filter) {
                final selected = _jobViewFilter == filter;
                return ChoiceChip(
                  label: Text(_jobFilterLabel(filter)),
                  selected: selected,
                  onSelected: (value) {
                    if (!value) return;
                    setState(() => _jobViewFilter = filter);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Text(
              filtered == total
                  ? '$total pegas registradas'
                  : '$filtered de $total pegas coinciden',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobSummaryChip({
    required String label,
    required int count,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Chip(
      backgroundColor: color.withOpacity(0.12),
      side: BorderSide(color: color.withOpacity(0.3)),
      label: Text(
        '$label: $count',
        style: theme.textTheme.bodySmall?.copyWith(color: color),
      ),
    );
  }

  Widget _buildTimelineFilters({required int total, required int filtered}) {
    final theme = Theme.of(context);
    final allTypes = TimelineEventType.values;
    final allSelected = _timelineTypeFilters.length == allTypes.length;
    final defaultSort = _timelineSortKey == 'date_desc';
    final hasFiltersApplied =
        _timelineSearchTerm.isNotEmpty || !defaultSort || !allSelected;
    final filterSummary = allSelected
        ? 'Todos los tipos'
        : '${_timelineTypeFilters.length} de ${allTypes.length} tipos seleccionados';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _timelineSearchController,
                    decoration: const InputDecoration(
                      labelText: 'Buscar en historial',
                      hintText: 'Evento, técnico o bicicleta',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    value: _timelineSortKey,
                    decoration:
                        const InputDecoration(labelText: 'Ordenar eventos'),
                    items: _timelineSortLabels.entries
                        .map(
                          (entry) => DropdownMenuItem<String>(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _timelineSortKey = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.filter_list, size: 18, color: theme.hintColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    filterSummary,
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _showTimelineFilterSheet,
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Filtrar por tipo'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  filtered == total
                      ? '$total eventos registrados'
                      : '$filtered de $total eventos coinciden',
                  style: theme.textTheme.bodySmall,
                ),
                if (hasFiltersApplied) ...[
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _timelineSearchController.clear();
                        _timelineSearchTerm = '';
                        _timelineSortKey = 'date_desc';
                        _timelineTypeFilters = allTypes.toSet();
                      });
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Restablecer filtros'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineMetaChip({
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey[700]),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showTimelineFilterSheet() async {
    final allTypes = TimelineEventType.values;
    final selected = Set<TimelineEventType>.from(_timelineTypeFilters);

    final result = await showModalBottomSheet<Set<TimelineEventType>>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: StatefulBuilder(
              builder: (context, setStateModal) {
                void toggle(TimelineEventType type) {
                  setStateModal(() {
                    if (selected.contains(type)) {
                      selected.remove(type);
                    } else {
                      selected.add(type);
                    }
                  });
                }

                void selectAll() {
                  setStateModal(() {
                    selected
                      ..clear()
                      ..addAll(allTypes);
                  });
                }

                void clearAll() {
                  setStateModal(selected.clear);
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Filtrar tipos de evento',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        TextButton(
                          onPressed: selectAll,
                          child: const Text('Seleccionar todo'),
                        ),
                        TextButton(
                          onPressed: clearAll,
                          child: const Text('Limpiar'),
                        ),
                        const Spacer(),
                        Text(
                          selected.length == allTypes.length
                              ? 'Todos seleccionados'
                              : '${selected.length} de ${allTypes.length}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: allTypes.length,
                        itemBuilder: (context, index) {
                          final type = allTypes[index];
                          return CheckboxListTile(
                            value: selected.contains(type),
                            onChanged: (_) => toggle(type),
                            title: Text(_timelineEventLabel(type)),
                            secondary: Icon(
                              _timelineIcon(type),
                              color: _timelineColor(type),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context)
                              .pop(Set<TimelineEventType>.from(selected)),
                          child: const Text('Aplicar filtros'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    if (result != null) {
      setState(() {
        _timelineTypeFilters = result.isEmpty ? <TimelineEventType>{} : result;
      });
    }
  }

  Widget _buildJobCard(MechanicJob job) {
    final bike = _getBikeForJob(job);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => context.push('/taller/pegas/${job.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Job number
                  Text(
                    job.jobNumber.isEmpty ? 'Sin número' : job.jobNumber,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Priority badge
                  _buildPriorityBadge(job.priority),
                  const SizedBox(width: 12),
                  // Status badge
                  _buildStatusBadge(job.status),
                  const Spacer(),
                  // Cost
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.green[300]!),
                    ),
                    child: Text(
                      NumberFormat.currency(symbol: '\$', decimalDigits: 0)
                          .format(job.totalCost),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green[900],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Bike info
              Row(
                children: [
                  Icon(Icons.pedal_bike, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    bike.displayName,
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ],
              ),
              if (job.clientRequest != null) ...[
                const SizedBox(height: 8),
                Text(
                  job.clientRequest!,
                  style: TextStyle(color: Colors.grey[600]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              // Dates
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    'Ingreso: ${DateFormat('dd/MM/yyyy').format(job.arrivalDate)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  if (job.deadline != null) ...[
                    const SizedBox(width: 16),
                    Icon(
                      Icons.event,
                      size: 14,
                      color: job.isOverdue ? Colors.red : Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Entrega: ${DateFormat('dd/MM/yyyy').format(job.deadline!)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: job.isOverdue ? Colors.red : Colors.grey[600],
                        fontWeight:
                            job.isOverdue ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                  if (job.assignedTechnicianName != null) ...[
                    const Spacer(),
                    Icon(Icons.person, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      job.assignedTechnicianName!,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriorityBadge(JobPriority priority) {
    Color color;
    IconData icon;

    switch (priority) {
      case JobPriority.urgente:
        color = Colors.red;
        icon = Icons.warning;
        break;
      case JobPriority.alta:
        color = Colors.orange;
        icon = Icons.priority_high;
        break;
      case JobPriority.normal:
        color = Colors.blue;
        icon = Icons.circle;
        break;
      case JobPriority.baja:
        color = Colors.grey;
        icon = Icons.circle_outlined;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            priority.displayName,
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(JobStatus status) {
    Color color;

    switch (status) {
      case JobStatus.pendiente:
        color = Colors.grey;
        break;
      case JobStatus.diagnostico:
        color = Colors.blue;
        break;
      case JobStatus.esperandoAprobacion:
        color = Colors.amber;
        break;
      case JobStatus.esperandoRepuestos:
        color = Colors.orange;
        break;
      case JobStatus.enCurso:
        color = Colors.green;
        break;
      case JobStatus.finalizado:
        color = Colors.teal;
        break;
      case JobStatus.entregado:
        color = Colors.purple;
        break;
      case JobStatus.cancelado:
        color = Colors.red;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        status.displayName,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildTimelineSection() {
    final filteredTimeline = _getFilteredTimeline();
    final totalEvents = _timeline.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Historial Completo',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 16),
        _buildTimelineFilters(
          total: totalEvents,
          filtered: filteredTimeline.length,
        ),
        const SizedBox(height: 16),
        if (filteredTimeline.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.timeline, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      totalEvents == 0
                          ? 'No hay eventos registrados'
                          : 'No encontramos eventos que coincidan',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filteredTimeline.length,
            itemBuilder: (context, index) =>
                _buildTimelineItem(filteredTimeline[index]),
          ),
      ],
    );
  }

  Widget _buildTimelineItem(MechanicJobTimeline event) {
    final icon = _timelineIcon(event.eventType);
    final color = _timelineColor(event.eventType);
    final job = event.jobId.isNotEmpty ? _jobIndex[event.jobId] : null;
    final bike = job != null ? _bikeIndex[job.bikeId] : null;
    final defaultDescription = _getDefaultDescription(event.eventType);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.description ?? defaultDescription,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        DateFormat('dd/MM/yyyy HH:mm').format(event.createdAt),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      if (event.createdByName != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '• ${event.createdByName}',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ],
                  ),
                  if (event.oldValue != null || event.newValue != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${event.oldValue ?? ''} → ${event.newValue ?? ''}',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                          fontStyle: FontStyle.italic),
                    ),
                  ],
                  if (job != null || bike != null) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        if (job != null)
                          _buildTimelineMetaChip(
                            icon: Icons.build,
                            label: job.jobNumber.isNotEmpty
                                ? 'Pega ${job.jobNumber}'
                                : 'Pega sin número',
                          ),
                        if (bike != null)
                          _buildTimelineMetaChip(
                            icon: Icons.pedal_bike,
                            label: bike.displayName,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getDefaultDescription(TimelineEventType eventType) {
    var description = 'Evento';

    switch (eventType) {
      case TimelineEventType.created:
        description = 'Pega creada';
        break;
      case TimelineEventType.statusChanged:
        description = 'Estado cambiado';
        break;
      case TimelineEventType.assigned:
        description = 'Técnico asignado';
        break;
      case TimelineEventType.diagnosisAdded:
        description = 'Diagnóstico agregado';
        break;
      case TimelineEventType.partsAdded:
        description = 'Repuestos agregados';
        break;
      case TimelineEventType.laborAdded:
        description = 'Mano de obra registrada';
        break;
      case TimelineEventType.photoAdded:
        description = 'Foto agregada';
        break;
      case TimelineEventType.noteAdded:
        description = 'Nota agregada';
        break;
      case TimelineEventType.approved:
        description = 'Trabajo aprobado';
        break;
      case TimelineEventType.invoiced:
        description = 'Factura generada';
        break;
      case TimelineEventType.paid:
        description = 'Pago recibido';
        break;
      case TimelineEventType.completed:
        description = 'Trabajo completado';
        break;
      case TimelineEventType.delivered:
        description = 'Bicicleta entregada';
        break;
    }

    return description;
  }

  // ============================================================
  // BIKE MANAGEMENT
  // ============================================================

  void _editBike(Bike bike) async {
    final result = await showDialog<Bike?>(
      context: context,
      builder: (context) => BikeFormDialog(
        customerId: widget.customerId,
        bike: bike,
      ),
    );

    if (result != null) {
      // Reload data after editing bike
      _loadData();
    }
  }

  Future<void> _confirmDeleteBike(Bike bike) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('¿Está seguro de eliminar esta bicicleta?'),
            const SizedBox(height: 16),
            Text(
              bike.displayName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (bike.serialNumber != null && bike.serialNumber!.isNotEmpty)
              Text('N° Serie: ${bike.serialNumber}'),
            if (bike.bikeType != null)
              Text('Tipo: ${bike.bikeType!.displayName}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true && bike.id != null) {
      try {
        final bikeshopService =
            Provider.of<BikeshopService>(context, listen: false);
        await bikeshopService.deleteBike(bike.id!);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bicicleta eliminada exitosamente'),
              backgroundColor: Colors.green,
            ),
          );

          // Refresh the bike list automatically
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error eliminando bicicleta: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}
