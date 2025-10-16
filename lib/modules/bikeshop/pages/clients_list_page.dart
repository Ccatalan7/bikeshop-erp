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

class BikeshopClientsListPage extends StatefulWidget {
  const BikeshopClientsListPage({super.key});

  @override
  State<BikeshopClientsListPage> createState() => _BikeshopClientsListPageState();
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

  @override
  void initState() {
    super.initState();
    final db = Provider.of<DatabaseService>(context, listen: false);
    _customerService = CustomerService(db);
    _bikeshopService = BikeshopService(db);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Load customers
      final customers = await _customerService.getCustomers();
      
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
        final matchesName = customer.name.toLowerCase().contains(_searchTerm.toLowerCase());
        final matchesPhone = customer.phone?.toLowerCase().contains(_searchTerm.toLowerCase()) ?? false;
        
        // Also search in bike brands/models
        final bikes = _customerBikes[customer.id] ?? [];
        final matchesBike = bikes.any((bike) =>
          (bike.brand?.toLowerCase().contains(_searchTerm.toLowerCase()) ?? false) ||
          (bike.model?.toLowerCase().contains(_searchTerm.toLowerCase()) ?? false) ||
          (bike.serialNumber?.toLowerCase().contains(_searchTerm.toLowerCase()) ?? false)
        );
        
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
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Bikeshop - Clientes',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                AppButton(
                  text: 'Nuevo Trabajo',
                  icon: Icons.add_circle,
                  onPressed: () {
                    context.push('/bikeshop/jobs/new').then((_) => _loadData());
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
                  _buildFilterChip('Esperando Repuestos', JobStatus.esperandoRepuestos),
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
                  _buildStatItem('Clientes', _customers.length.toString(), Icons.people),
                  _buildStatItem(
                    'Bicicletas', 
                    _customerBikes.values.expand((bikes) => bikes).length.toString(),
                    Icons.pedal_bike,
                  ),
                  _buildStatItem(
                    'Trabajos Activos', 
                    _customerJobs.values.expand((jobs) => jobs).length.toString(),
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
          
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildCustomersList(),
          ),
        ],
      ),
    );
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
          context.push('/bikeshop/clients/${customer.id}').then((_) => _loadData());
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
                              Icon(Icons.phone, size: 14, color: Colors.grey[600]),
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
                  if (latestJob != null)
                    _buildStatusBadge(latestJob.status),
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
                        latestJob.clientRequest ?? latestJob.diagnosis ?? 'Sin descripción',
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
                    Icon(Icons.calendar_today, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      'Ingreso: ${_formatDate(latestJob.arrivalDate)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (latestJob.deadline != null) ...[
                      const SizedBox(width: 12),
                      Icon(
                        latestJob.isOverdue ? Icons.warning : Icons.schedule,
                        size: 14,
                        color: latestJob.isOverdue ? Colors.red : Colors.grey[500],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Plazo: ${_formatDate(latestJob.deadline!)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: latestJob.isOverdue ? Colors.red : Colors.grey[600],
                          fontWeight: latestJob.isOverdue ? FontWeight.bold : FontWeight.normal,
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
        color: color.withOpacity(0.1),
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
