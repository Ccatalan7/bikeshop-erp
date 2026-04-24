import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_widget.dart';
import '../../../shared/widgets/app_button.dart';
import '../../crm/models/crm_models.dart';
import '../../crm/services/customer_service.dart';
import '../services/bikeshop_service.dart';
import '../models/bikeshop_models.dart';

enum ClientsViewMode { table, board, calendar }

class BikeshopClientsListPage extends StatefulWidget {
  const BikeshopClientsListPage({super.key});

  @override
  State<BikeshopClientsListPage> createState() =>
      _BikeshopClientsListPageState();
}

class _BikeshopClientsListPageState extends State<BikeshopClientsListPage> {
  late CustomerService _customerService;
  late BikeshopService _bikeshopService;

  List<Customer> _customers = [];
  List<Customer> _filteredCustomers = [];
  Map<String, List<Bike>> _customerBikes = {};
  Map<String, List<MechanicJob>> _customerJobs = {};
  Map<String, MechanicJob?> _latestJobs = {}; // Latest job per customer

  bool _isLoading = true;
  String _searchTerm = '';
  JobStatus? _filterStatus;
  ClientsViewMode _viewMode = ClientsViewMode.table;
  DateTime _focusedMonth = DateTime.now();
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _customerService = Provider.of<CustomerService>(context, listen: false);
    _bikeshopService = Provider.of<BikeshopService>(context, listen: false);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Load customers
      final customers = await _customerService.getCustomersForList();

      // Load all bikes and jobs
      final allBikes = await _bikeshopService.getBikes();
      final allJobs = await _bikeshopService.getJobs(includeCompleted: false);

      // Group bikes by customer
      final bikesByCustomer = <String, List<Bike>>{};
      for (final bike in allBikes) {
        bikesByCustomer.putIfAbsent(bike.customerId, () => []).add(bike);
      }

      // Group jobs by customer and find latest
      final jobsByCustomer = <String, List<MechanicJob>>{};
      final latestJobByCustomer = <String, MechanicJob?>{};

      for (final job in allJobs) {
        jobsByCustomer.putIfAbsent(job.customerId, () => []).add(job);

        // Track latest job per customer
        final current = latestJobByCustomer[job.customerId];
        if (current == null || job.arrivalDate.isAfter(current.arrivalDate)) {
          latestJobByCustomer[job.customerId] = job;
        }
      }

      // Only show customers with bikes or jobs
      final bikeshopCustomers = customers.where((c) {
        final hasBikes = bikesByCustomer[c.id]?.isNotEmpty ?? false;
        final hasJobs = jobsByCustomer[c.id]?.isNotEmpty ?? false;
        return hasBikes || hasJobs;
      }).toList();

      setState(() {
        _customers = bikeshopCustomers;
        _filteredCustomers = bikeshopCustomers;
        _customerBikes = bikesByCustomer;
        _customerJobs = jobsByCustomer;
        _latestJobs = latestJobByCustomer;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando datos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onSearchChanged(String searchTerm) {
    setState(() {
      _searchTerm = searchTerm;
      _applyFilters();
    });
  }

  void _applyFilters() {
    var filtered = _customers;

    // Apply search
    if (_searchTerm.isNotEmpty) {
      filtered = filtered.where((customer) {
        final matchesName =
            customer.name.toLowerCase().contains(_searchTerm.toLowerCase());
        final matchesPhone =
            customer.phone?.toLowerCase().contains(_searchTerm.toLowerCase()) ??
                false;

        // Also search in bike brands/models
        final bikes = _customerBikes[customer.id] ?? [];
        final matchesBike = bikes.any((bike) =>
            (bike.brand
                    ?.toLowerCase()
                    .contains(_searchTerm.toLowerCase()) ??
                false) ||
            (bike.model?.toLowerCase().contains(_searchTerm.toLowerCase()) ??
                false) ||
            (bike.serialNumber
                    ?.toLowerCase()
                    .contains(_searchTerm.toLowerCase()) ??
                false));

        return matchesName || matchesPhone || matchesBike;
      }).toList();
    }

    // Apply status filter
    if (_filterStatus != null) {
      filtered = filtered.where((customer) {
        final jobs = _customerJobs[customer.id] ?? [];
        return jobs.any((job) => job.status == _filterStatus);
      }).toList();
    }

    setState(() {
      _filteredCustomers = filtered;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Column(
        children: [
          // Header with view switchers
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Gestión de clientes',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // View mode switchers
                _buildViewSwitcher(
                  icon: Icons.table_chart,
                  label: 'Table',
                  mode: ClientsViewMode.table,
                ),
                const SizedBox(width: 8),
                _buildViewSwitcher(
                  icon: Icons.view_kanban,
                  label: 'Board',
                  mode: ClientsViewMode.board,
                ),
                const SizedBox(width: 8),
                _buildViewSwitcher(
                  icon: Icons.calendar_month,
                  label: 'Calendar',
                  mode: ClientsViewMode.calendar,
                ),
                const SizedBox(width: 16),
                AppButton(
                  text: 'New',
                  icon: Icons.add,
                  onPressed: () {
                    context
                        .push('/taller/pegas/nueva')
                        .then((_) => _loadData());
                  },
                ),
              ],
            ),
          ),

          // Search
          SearchWidget(
            hintText: 'Buscar por cliente, teléfono, o bicicleta...',
            onSearchChanged: _onSearchChanged,
          ),

          // Filters
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('Todos', null),
                  const SizedBox(width: 8),
                  _buildFilterChip('Pendiente', JobStatus.pendiente),
                  const SizedBox(width: 8),
                  _buildFilterChip('Diagnóstico', JobStatus.diagnostico),
                  const SizedBox(width: 8),
                  _buildFilterChip('En Curso', JobStatus.enCurso),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                      'Esperando Repuestos', JobStatus.esperandoRepuestos),
                ],
              ),
            ),
          ),

          // Stats
          if (!_isLoading && _customers.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[100]!),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(
                      'Clientes', _customers.length.toString(), Icons.people),
                  _buildStatItem(
                    'Bicicletas',
                    _customerBikes.values
                        .expand((bikes) => bikes)
                        .length
                        .toString(),
                    Icons.pedal_bike,
                  ),
                  _buildStatItem(
                    'Trabajos Activos',
                    _customerJobs.values
                        .expand((jobs) => jobs)
                        .length
                        .toString(),
                    Icons.build,
                  ),
                  _buildStatItem(
                    'Mostrando',
                    _filteredCustomers.length.toString(),
                    Icons.filter_list,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),

          // Content - Switch based on view mode
          Expanded(
            child: _isLoading
                ? const Center(child: BrandedLoading())
                : _buildViewContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildViewContent() {
    switch (_viewMode) {
      case ClientsViewMode.table:
        return _buildCustomersList();
      case ClientsViewMode.board:
        return _buildBoardView();
      case ClientsViewMode.calendar:
        return _buildCalendarView();
    }
  }

  Widget _buildViewSwitcher({
    required IconData icon,
    required String label,
    required ClientsViewMode mode,
  }) {
    final isSelected = _viewMode == mode;
    final theme = Theme.of(context);

    return InkWell(
      onTap: () {
        setState(() {
          _viewMode = mode;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? theme.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? theme.primaryColor : theme.dividerColor,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.white : theme.colorScheme.onSurface,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : theme.colorScheme.onSurface,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBoardView() {
    // Group customers by status of their latest job
    final Map<JobStatus?, List<Customer>> customersByStatus = {};

    for (final customer in _filteredCustomers) {
      final latestJob = _latestJobs[customer.id];
      final status = latestJob?.status;
      customersByStatus.putIfAbsent(status, () => []).add(customer);
    }

    final statuses = [
      JobStatus.pendiente,
      JobStatus.diagnostico,
      JobStatus.esperandoAprobacion,
      JobStatus.enCurso,
      JobStatus.esperandoRepuestos,
      JobStatus.finalizado,
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: statuses.map((status) {
          final customers = customersByStatus[status] ?? [];
          return Container(
            width: 300,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _getStatusColor(status).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          status.displayName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _getStatusColor(status),
                          ),
                        ),
                      ),
                      Text(
                        '${customers.length}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _getStatusColor(status),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: customers.length,
                    itemBuilder: (context, index) {
                      final customer = customers[index];
                      final bikes = _customerBikes[customer.id] ?? [];
                      final latestJob = _latestJobs[customer.id];

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () {
                            context.push('/bikeshop/clientes/${customer.id}');
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  customer.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (customer.phone != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    customer.phone!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                                if (bikes.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    '${bikes.first.brand} ${bikes.first.model}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                                if (latestJob != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Pega: ${latestJob.jobNumber}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCalendarView() {
    return Row(
      children: [
        // Calendar grid
        Expanded(
          flex: 7,
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildCalendarHeader(),
                  const SizedBox(height: 16),
                  Expanded(child: _buildCalendarGrid()),
                ],
              ),
            ),
          ),
        ),
        // Selected date details
        Expanded(
          flex: 3,
          child: Card(
            margin: const EdgeInsets.only(top: 16, right: 16, bottom: 16),
            child: _buildSelectedDateJobs(),
          ),
        ),
      ],
    );
  }

  Widget _buildCalendarHeader() {
    final monthFormat = DateFormat('MMMM yyyy', 'es');

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () {
            setState(() {
              _focusedMonth =
                  DateTime(_focusedMonth.year, _focusedMonth.month - 1);
            });
          },
        ),
        Text(
          monthFormat.format(_focusedMonth),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Row(
          children: [
            TextButton(
              onPressed: () {
                setState(() {
                  _focusedMonth = DateTime.now();
                  _selectedDate = DateTime.now();
                });
              },
              child: const Text('Today'),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () {
                setState(() {
                  _focusedMonth =
                      DateTime(_focusedMonth.year, _focusedMonth.month + 1);
                });
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCalendarGrid() {
    final firstDayOfMonth =
        DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final lastDayOfMonth =
        DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    final daysInMonth = lastDayOfMonth.day;
    final firstWeekday = firstDayOfMonth.weekday % 7;

    return Column(
      children: [
        // Weekday headers
        Row(
          children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
              .map((day) => Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 8),
        // Calendar days
        Expanded(
          child: Column(
            children: List.generate((daysInMonth + firstWeekday + 6) ~/ 7,
                (weekIndex) {
              return Expanded(
                child: Row(
                  children: List.generate(7, (dayIndex) {
                    final dayNumber =
                        weekIndex * 7 + dayIndex - firstWeekday + 1;
                    if (dayNumber < 1 || dayNumber > daysInMonth) {
                      return const Expanded(child: SizedBox());
                    }

                    final date = DateTime(
                        _focusedMonth.year, _focusedMonth.month, dayNumber);
                    final isSelected = _selectedDate.year == date.year &&
                        _selectedDate.month == date.month &&
                        _selectedDate.day == date.day;
                    final isToday = DateTime.now().year == date.year &&
                        DateTime.now().month == date.month &&
                        DateTime.now().day == date.day;
                    final jobsOnDay = _getJobsForDate(date);

                    return Expanded(
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedDate = date;
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Theme.of(context)
                                    .primaryColor
                                    .withValues(alpha: 0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: isToday
                                ? Border.all(
                                    color: Theme.of(context).primaryColor,
                                    width: 2,
                                  )
                                : isSelected
                                    ? Border.all(
                                        color: Theme.of(context).primaryColor,
                                        width: 1,
                                      )
                                    : null,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(4),
                                child: Text(
                                  '$dayNumber',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isToday
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? Theme.of(context).primaryColor
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                  ),
                                ),
                              ),
                              // List customer names like Notion
                              if (jobsOnDay.isNotEmpty)
                                Expanded(
                                  child: ListView.builder(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4),
                                    itemCount: jobsOnDay.length > 3
                                        ? 3
                                        : jobsOnDay.length,
                                    itemBuilder: (context, index) {
                                      final job = jobsOnDay[index];
                                      final customerName = _customers
                                          .firstWhere(
                                              (c) => c.id == job.customerId,
                                              orElse: () => Customer(
                                                    name: 'Unknown',
                                                    tenantId: '',
                                                    rut: '',
                                                  ))
                                          .name;

                                      return Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 2),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _getStatusColor(job.status)
                                              .withValues(alpha: 0.2),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          customerName,
                                          style: const TextStyle(fontSize: 10),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              if (jobsOnDay.length > 3)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 2),
                                  child: Text(
                                    '+${jobsOnDay.length - 3} more',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  List<MechanicJob> _getJobsForDate(DateTime date) {
    final allJobs = _customerJobs.values.expand((jobs) => jobs).toList();
    return allJobs.where((job) {
      return job.arrivalDate.year == date.year &&
          job.arrivalDate.month == date.month &&
          job.arrivalDate.day == date.day;
    }).toList();
  }

  Widget _buildSelectedDateJobs() {
    final jobsForDate = _getJobsForDate(_selectedDate);
    final dateFormat = DateFormat('EEEE, MMMM d, yyyy', 'es');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dateFormat.format(_selectedDate),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${jobsForDate.length} trabajo${jobsForDate.length != 1 ? 's' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  color:
                      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: jobsForDate.isEmpty
              ? Center(
                  child: Text(
                    'No hay trabajos para esta fecha',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: jobsForDate.length,
                  itemBuilder: (context, index) {
                    final job = jobsForDate[index];
                    final customer = _customers.firstWhere(
                      (c) => c.id == job.customerId,
                      orElse: () => Customer(
                        name: 'Unknown',
                        tenantId: '',
                        rut: '',
                      ),
                    );
                    final bikes = _customerBikes[job.customerId] ?? [];
                    final bike = bikes.isNotEmpty ? bikes.first : null;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            _getStatusColor(job.status).withValues(alpha: 0.2),
                        child: Icon(
                          Icons.build,
                          color: _getStatusColor(job.status),
                          size: 20,
                        ),
                      ),
                      title: Text(
                        customer.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (bike != null)
                            Text(
                              '${bike.brand} ${bike.model}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          const SizedBox(height: 4),
                          _buildStatusBadge(job.status),
                        ],
                      ),
                      onTap: () {
                        // Navigate to job details
                        context.push('/taller/pegas/${job.id}');
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Color _getStatusColor(JobStatus status) {
    switch (status) {
      case JobStatus.pendiente:
        return Colors.grey;
      case JobStatus.diagnostico:
        return Colors.blue;
      case JobStatus.esperandoAprobacion:
        return Colors.amber;
      case JobStatus.esperandoRepuestos:
        return Colors.orange;
      case JobStatus.enCurso:
        return Colors.green;
      case JobStatus.finalizado:
        return Colors.teal;
      case JobStatus.entregado:
        return Colors.purple;
      case JobStatus.cancelado:
        return Colors.red;
    }
  }

  Widget _buildFilterChip(String label, JobStatus? status) {
    final isSelected = _filterStatus == status;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _filterStatus = selected ? status : null;
          _applyFilters();
        });
      },
      selectedColor: Colors.blue[100],
      checkmarkColor: Colors.blue[700],
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: Colors.blue[700]),
            const SizedBox(width: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ],
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.blue[700],
          ),
        ),
      ],
    );
  }

  Widget _buildCustomersList() {
    if (_filteredCustomers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.pedal_bike,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _searchTerm.isEmpty
                  ? 'No hay clientes con bicicletas o trabajos'
                  : 'No se encontraron clientes',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Crea un cliente en el módulo CRM y luego registra una bicicleta',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _filteredCustomers.length,
      itemBuilder: (context, index) {
        final customer = _filteredCustomers[index];
        final bikes = _customerBikes[customer.id] ?? [];
        final jobs = _customerJobs[customer.id] ?? [];
        final latestJob = _latestJobs[customer.id];

        return _buildCustomerCard(customer, bikes, jobs, latestJob);
      },
    );
  }

  Widget _buildCustomerCard(
    Customer customer,
    List<Bike> bikes,
    List<MechanicJob> jobs,
    MechanicJob? latestJob,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: InkWell(
        onTap: () {
          context.push('/clientes/${customer.id}').then((_) => _loadData());
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Customer header
              Row(
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.blue[100],
                    child: Text(
                      customer.initials,
                      style: TextStyle(
                        color: Colors.blue[700],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Customer info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customer.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (customer.phone != null)
                          Row(
                            children: [
                              Icon(Icons.phone,
                                  size: 14, color: Colors.grey[600]),
                              const SizedBox(width: 4),
                              Text(
                                customer.phone!,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),

                  // Latest job status badge
                  if (latestJob != null) _buildStatusBadge(latestJob.status),
                ],
              ),

              const Divider(height: 24),

              // Bikes summary
              Row(
                children: [
                  Icon(Icons.pedal_bike, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '${bikes.length} bicicleta${bikes.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (bikes.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        bikes.map((b) => b.displayName).join(', '),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),

              // Latest job info
              if (latestJob != null) ...[
                Row(
                  children: [
                    Icon(Icons.build, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        latestJob.clientRequest ??
                            latestJob.diagnosis ??
                            'Sin descripción',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.calendar_today,
                        size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      'Ingreso: ${_formatDate(latestJob.arrivalDate)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (latestJob.deliveryDeadline != null) ...[
                      const SizedBox(width: 12),
                      Icon(
                        latestJob.isOverdue ? Icons.warning : Icons.schedule,
                        size: 14,
                        color:
                            latestJob.isOverdue ? Colors.red : Colors.grey[500],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Plazo: ${_formatDate(latestJob.deliveryDeadline!)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: latestJob.isOverdue
                              ? Colors.red
                              : Colors.grey[600],
                          fontWeight: latestJob.isOverdue
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ],
                ),
              ],

              // Active jobs count
              if (jobs.length > 1) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Text(
                    '+${jobs.length - 1} trabajo${jobs.length - 1 == 1 ? '' : 's'} adicional${jobs.length - 1 == 1 ? '' : 'es'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange[800],
                      fontWeight: FontWeight.w500,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
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

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
