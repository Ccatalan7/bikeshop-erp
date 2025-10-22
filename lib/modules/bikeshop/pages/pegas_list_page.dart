import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_widget.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/services/database_service.dart';
import '../../crm/models/crm_models.dart';
import '../../crm/services/customer_service.dart';
import '../services/bikeshop_service.dart';
import '../models/bikeshop_models.dart';

class PegasListPage extends StatefulWidget {
  const PegasListPage({super.key});

  @override
  State<PegasListPage> createState() => _PegasListPageState();
}

class _PegasListPageState extends State<PegasListPage> {
  late BikeshopService _bikeshopService;
  late CustomerService _customerService;

  List<MechanicJob> _jobs = [];
  List<MechanicJob> _filteredJobs = [];
  Map<String, Customer> _customers = {};
  Map<String, Bike> _bikes = {};

  bool _isLoading = true;
  String _searchTerm = '';
  JobStatus? _filterStatus;
  JobPriority? _filterPriority;
  bool _showCompleted = false;
  String _sortBy = 'arrival_date'; // arrival_date, deadline, priority, status

  @override
  void initState() {
    super.initState();
    final db = Provider.of<DatabaseService>(context, listen: false);
    _bikeshopService = BikeshopService(db);
    _customerService = CustomerService(db);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final jobs =
          await _bikeshopService.getJobs(includeCompleted: _showCompleted);
      final customers = await _customerService.getCustomers();
      final bikes = await _bikeshopService.getBikes();

      // Create lookup maps
      final customerMap = <String, Customer>{};
      for (final customer in customers) {
        if (customer.id != null) {
          customerMap[customer.id!] = customer;
        }
      }

      final bikeMap = <String, Bike>{};
      for (final bike in bikes) {
        if (bike.id != null) {
          bikeMap[bike.id!] = bike;
        }
      }

      setState(() {
        _jobs = jobs;
        _filteredJobs = jobs;
        _customers = customerMap;
        _bikes = bikeMap;
        _isLoading = false;
      });

      _applyFiltersAndSort();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando trabajos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onSearchChanged(String searchTerm) {
    setState(() {
      _searchTerm = searchTerm;
      _applyFiltersAndSort();
    });
  }

  void _applyFiltersAndSort() {
    var filtered = _jobs;

    // Apply search
    if (_searchTerm.isNotEmpty) {
      filtered = filtered.where((job) {
        final matchesJobNumber =
            job.jobNumber.toLowerCase().contains(_searchTerm.toLowerCase());
        final matchesRequest = job.clientRequest
                ?.toLowerCase()
                .contains(_searchTerm.toLowerCase()) ??
            false;
        final matchesDiagnosis =
            job.diagnosis?.toLowerCase().contains(_searchTerm.toLowerCase()) ??
                false;

        final customer = _customers[job.customerId];
        final matchesCustomer =
            customer?.name.toLowerCase().contains(_searchTerm.toLowerCase()) ??
                false;

        final bike = _bikes[job.bikeId];
        final matchesBike = bike?.displayName
                .toLowerCase()
                .contains(_searchTerm.toLowerCase()) ??
            false;

        return matchesJobNumber ||
            matchesRequest ||
            matchesDiagnosis ||
            matchesCustomer ||
            matchesBike;
      }).toList();
    }

    // Apply status filter
    if (_filterStatus != null) {
      filtered = filtered.where((job) => job.status == _filterStatus).toList();
    }

    // Apply priority filter
    if (_filterPriority != null) {
      filtered =
          filtered.where((job) => job.priority == _filterPriority).toList();
    }

    // Apply sort
    filtered.sort((a, b) {
      switch (_sortBy) {
        case 'deadline':
          if (a.deadline == null && b.deadline == null) return 0;
          if (a.deadline == null) return 1;
          if (b.deadline == null) return -1;
          return a.deadline!.compareTo(b.deadline!);
        case 'priority':
          return a.priority.index.compareTo(b.priority.index);
        case 'status':
          return a.status.index.compareTo(b.status.index);
        case 'arrival_date':
        default:
          return b.arrivalDate.compareTo(a.arrivalDate);
      }
    });

    setState(() {
      _filteredJobs = filtered;
    });
  }

  Future<void> _updateJobStatus(MechanicJob job, JobStatus newStatus) async {
    try {
      await _bikeshopService.updateJobStatus(job.id!, newStatus);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Estado actualizado a ${newStatus.displayName}'),
            backgroundColor: Colors.green,
          ),
        );
      }
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error actualizando estado: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = _calculateStats();

    return MainLayout(
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Pegas (Trabajos en Curso)',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                AppButton(
                  text: 'Nueva Pega',
                  icon: Icons.add_circle,
                  onPressed: () {
                    context.push('/taller/pegas/new').then((_) => _loadData());
                  },
                ),
              ],
            ),
          ),

          // Search
          SearchWidget(
            hintText: 'Buscar por trabajo, cliente, o bicicleta...',
            onSearchChanged: _onSearchChanged,
          ),

          // Filters and controls
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                // Status filters
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('Todos', null, isStatus: true),
                      const SizedBox(width: 8),
                      _buildFilterChip('Pendiente', JobStatus.pendiente,
                          isStatus: true),
                      const SizedBox(width: 8),
                      _buildFilterChip('Diagnóstico', JobStatus.diagnostico,
                          isStatus: true),
                      const SizedBox(width: 8),
                      _buildFilterChip('En Curso', JobStatus.enCurso,
                          isStatus: true),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                          'Esperando Repuestos', JobStatus.esperandoRepuestos,
                          isStatus: true),
                      const SizedBox(width: 8),
                      _buildFilterChip('Finalizado', JobStatus.finalizado,
                          isStatus: true),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Priority filters and controls
                Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            const Text('Prioridad: ',
                                style: TextStyle(fontSize: 13)),
                            _buildFilterChip('Todas', null, isStatus: false),
                            const SizedBox(width: 8),
                            _buildFilterChip('Urgente', JobPriority.urgente,
                                isStatus: false),
                            const SizedBox(width: 8),
                            _buildFilterChip('Alta', JobPriority.alta,
                                isStatus: false),
                            const SizedBox(width: 8),
                            _buildFilterChip('Normal', JobPriority.normal,
                                isStatus: false),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Sort dropdown
                    DropdownButton<String>(
                      value: _sortBy,
                      items: const [
                        DropdownMenuItem(
                            value: 'arrival_date',
                            child: Text('Fecha Ingreso')),
                        DropdownMenuItem(
                            value: 'deadline', child: Text('Plazo')),
                        DropdownMenuItem(
                            value: 'priority', child: Text('Prioridad')),
                        DropdownMenuItem(
                            value: 'status', child: Text('Estado')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _sortBy = value!;
                          _applyFiltersAndSort();
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    // Show completed toggle
                    FilterChip(
                      label: Text('Ver completados'),
                      selected: _showCompleted,
                      onSelected: (selected) {
                        setState(() {
                          _showCompleted = selected;
                        });
                        _loadData();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Stats
          if (!_isLoading)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue[50]!, Colors.blue[100]!],
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(
                      'Total', stats['total'].toString(), Icons.view_list),
                  _buildStatItem('Urgente', stats['urgente'].toString(),
                      Icons.priority_high,
                      color: Colors.red),
                  _buildStatItem(
                      'En Curso', stats['en_curso'].toString(), Icons.build,
                      color: Colors.green),
                  _buildStatItem(
                      'Atrasados', stats['overdue'].toString(), Icons.warning,
                      color: Colors.orange),
                  _buildStatItem('Mostrando', _filteredJobs.length.toString(),
                      Icons.filter_list),
                ],
              ),
            ),
          const SizedBox(height: 16),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildJobsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, dynamic value,
      {required bool isStatus}) {
    final isSelected =
        isStatus ? _filterStatus == value : _filterPriority == value;

    Color? chipColor;
    if (isSelected && !isStatus && value is JobPriority) {
      switch (value) {
        case JobPriority.urgente:
          chipColor = Colors.red[100];
          break;
        case JobPriority.alta:
          chipColor = Colors.orange[100];
          break;
        default:
          chipColor = Colors.blue[100];
      }
    }

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          if (isStatus) {
            _filterStatus = selected ? value : null;
          } else {
            _filterPriority = selected ? value : null;
          }
          _applyFiltersAndSort();
        });
      },
      selectedColor: chipColor ?? Colors.blue[100],
      checkmarkColor: Colors.blue[700],
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon,
      {Color? color}) {
    final effectiveColor = color ?? Colors.blue;
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: effectiveColor),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: effectiveColor,
              ),
            ),
          ],
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: effectiveColor,
          ),
        ),
      ],
    );
  }

  Map<String, int> _calculateStats() {
    return {
      'total': _jobs.length,
      'urgente': _jobs.where((j) => j.priority == JobPriority.urgente).length,
      'en_curso': _jobs.where((j) => j.status == JobStatus.enCurso).length,
      'overdue': _jobs.where((j) => j.isOverdue && j.isActive).length,
    };
  }

  Widget _buildJobsList() {
    if (_filteredJobs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.build_circle_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _searchTerm.isEmpty
                  ? 'No hay trabajos registrados'
                  : 'No se encontraron trabajos',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            if (_searchTerm.isEmpty) ...[
              const SizedBox(height: 16),
              AppButton(
                text: 'Crear Primer Trabajo',
                onPressed: () {
                  context.push('/taller/pegas/new').then((_) => _loadData());
                },
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _filteredJobs.length,
      itemBuilder: (context, index) {
        final job = _filteredJobs[index];
        final customer = _customers[job.customerId];
        final bike = _bikes[job.bikeId];

        return _buildJobCard(job, customer, bike);
      },
    );
  }

  Widget _buildJobCard(MechanicJob job, Customer? customer, Bike? bike) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: InkWell(
        onTap: () {
          context.push('/taller/pegas/${job.id}').then((_) => _loadData());
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  // Job number and priority
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              job.jobNumber,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildPriorityBadge(job.priority),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (customer != null)
                          Text(
                            customer.name,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Status badge with quick actions
                  PopupMenuButton<JobStatus>(
                    child: _buildStatusBadge(job.status),
                    onSelected: (newStatus) => _updateJobStatus(job, newStatus),
                    itemBuilder: (context) => JobStatus.values
                        .where((s) => s != job.status)
                        .map((status) => PopupMenuItem(
                              value: status,
                              child: Text(status.displayName),
                            ))
                        .toList(),
                  ),
                ],
              ),

              const Divider(height: 20),

              // Bike info
              if (bike != null)
                Row(
                  children: [
                    Icon(Icons.pedal_bike, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      bike.displayName,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 8),

              // Client request / diagnosis
              if (job.clientRequest != null || job.diagnosis != null)
                Row(
                  children: [
                    Icon(Icons.description, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        job.diagnosis ?? job.clientRequest ?? '',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 12),

              // Bottom row - dates and costs
              Row(
                children: [
                  // Dates
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.login,
                                size: 14, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Text(
                              _formatDate(job.arrivalDate),
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                        if (job.deadline != null) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                job.isOverdue ? Icons.warning : Icons.event,
                                size: 14,
                                color: job.isOverdue
                                    ? Colors.red
                                    : Colors.grey[500],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatDate(job.deadline!),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: job.isOverdue
                                      ? Colors.red
                                      : Colors.grey[600],
                                  fontWeight: job.isOverdue
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              if (job.isOverdue) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '(ATRASADO)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Cost
                  if (job.totalCost > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Text(
                        '\$${job.totalCost.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[700],
                        ),
                      ),
                    ),
                ],
              ),

              // Assigned technician
              if (job.assignedTechnicianName != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.person, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      job.assignedTechnicianName!,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
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
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            status.displayName,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.arrow_drop_down, size: 16, color: color),
        ],
      ),
    );
  }

  Widget _buildPriorityBadge(JobPriority priority) {
    Color color;
    IconData icon;
    switch (priority) {
      case JobPriority.urgente:
        color = Colors.red;
        icon = Icons.priority_high;
        break;
      case JobPriority.alta:
        color = Colors.orange;
        icon = Icons.arrow_upward;
        break;
      case JobPriority.normal:
        color = Colors.blue;
        icon = Icons.remove;
        break;
      case JobPriority.baja:
        color = Colors.grey;
        icon = Icons.arrow_downward;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            priority.displayName,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
