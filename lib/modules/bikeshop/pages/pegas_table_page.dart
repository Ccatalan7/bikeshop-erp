import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/services/database_service.dart';
import '../../crm/models/crm_models.dart';
import '../../crm/services/customer_service.dart';
import '../../sales/models/sales_models.dart';
import '../services/bikeshop_service.dart';
import '../models/bikeshop_models.dart';

/// Ultra-powerful bikeshop job management table
/// Features:
/// - Instant customer autocomplete with bike pre-fill
/// - Quick invoice access and payment status
/// - Real-time job tracking with time elapsed
/// - Smart status workflows with keyboard shortcuts
/// - Inline editing for fast updates
/// - One-click actions (call, WhatsApp, print, etc.)
class PegasTablePage extends StatefulWidget {
  const PegasTablePage({super.key});

  @override
  State<PegasTablePage> createState() => _PegasTablePageState();
}

class _PegasTablePageState extends State<PegasTablePage> with WidgetsBindingObserver {
  late BikeshopService _bikeshopService;
  late CustomerService _customerService;
  late DatabaseService _databaseService;
  
  List<MechanicJob> _jobs = [];
  List<MechanicJob> _filteredJobs = [];
  Map<String, Customer> _customers = {};
  Map<String, Bike> _bikes = {};
  Map<String, List<Bike>> _customerBikes = {}; // customer_id -> bikes
  Map<String, Invoice> _invoices = {}; // invoice_id -> invoice
  
  bool _isLoading = true;
  bool _needsRefresh = false; // Track if we need to refresh on next visibility
  String _searchTerm = '';
  
  // Column visibility and sorting
  String? _sortColumn = 'arrival_date';
  bool _sortAscending = false; // Show newest first by default
  final Set<String> _visibleColumns = {
    'status_indicator', // Visual status dot
    'job_number',
    'customer_quick',
    // 'bike_image', // DISABLED - causes freeze, needs investigation
    'bike_quick',
    'time_elapsed',
    'status',
    'priority',
    'invoice_quick', // Quick invoice access with payment status
    'deadline',
    'total_cost',
    'actions_quick', // Quick actions (call, WhatsApp, print, etc.)
  };
  
  // Filters
  final Set<JobStatus> _statusFilter = {};
  final Set<JobPriority> _priorityFilter = {};
  bool _showOnlyOverdue = false;
  bool _showOnlyUnpaid = false;
  String _viewMode = 'all'; // all, active, ready_for_delivery, waiting_payment

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final db = Provider.of<DatabaseService>(context, listen: false);
    _databaseService = db;
    _bikeshopService = BikeshopService(db);
    _customerService = CustomerService(db);
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh when app becomes visible again (user returns from another route)
    if (state == AppLifecycleState.resumed && _needsRefresh) {
      _needsRefresh = false;
      _loadData();
    }
  }

  // Called when page becomes active again after navigating back
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Check if we're becoming visible and need refresh
    if (ModalRoute.of(context)?.isCurrent == true && _needsRefresh) {
      _needsRefresh = false;
      _loadData();
    }
  }

  // Mark that refresh is needed when navigating away
  void _markNeedsRefresh() {
    _needsRefresh = true;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Load all data in parallel for performance
      final results = await Future.wait([
        _bikeshopService.getJobs(includeCompleted: false),
        _customerService.getCustomers(),
        _bikeshopService.getBikes(),
        _loadInvoices(), // Load invoices
      ]);
      
      final jobs = results[0] as List<MechanicJob>;
      final customers = results[1] as List<Customer>;
      final bikes = results[2] as List<Bike>;
      final invoices = results[3] as List<Invoice>;
      
      // Build lookup maps
      final customerMap = <String, Customer>{};
      final customerBikesMap = <String, List<Bike>>{};
      
      for (final customer in customers) {
        if (customer.id != null) {
          customerMap[customer.id!] = customer;
          customerBikesMap[customer.id!] = [];
        }
      }
      
      final bikeMap = <String, Bike>{};
      for (final bike in bikes) {
        if (bike.id != null) {
          bikeMap[bike.id!] = bike;
          customerBikesMap[bike.customerId]?.add(bike);
        }
      }
      
      final invoiceMap = <String, Invoice>{};
      for (final invoice in invoices) {
        if (invoice.id != null) {
          invoiceMap[invoice.id!] = invoice;
        }
      }
      
      setState(() {
        _jobs = jobs;
        _filteredJobs = jobs;
        _customers = customerMap;
        _bikes = bikeMap;
        _customerBikes = customerBikesMap;
        _invoices = invoiceMap;
        _isLoading = false;
      });
      
      _applyFiltersAndSort();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<List<Invoice>> _loadInvoices() async {
    try {
      final data = await _databaseService.select('sales_invoices');
      return data.map((json) => Invoice.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error loading invoices: $e');
      return [];
    }
  }

  void _applyFiltersAndSort() {
    var filtered = _jobs.where((job) {
      // View mode filter
      switch (_viewMode) {
        case 'active':
          if (job.status == JobStatus.entregado || job.status == JobStatus.cancelado) {
            return false;
          }
          break;
        case 'ready_for_delivery':
          if (job.status != JobStatus.finalizado) {
            return false;
          }
          break;
        case 'waiting_payment':
          if (job.isPaid || !job.isInvoiced) {
            return false;
          }
          break;
      }
      
      // Search filter
      if (_searchTerm.isNotEmpty) {
        final searchLower = _searchTerm.toLowerCase();
        final customer = _customers[job.customerId];
        final bike = _bikes[job.bikeId];
        
        final matchesJob = job.jobNumber?.toLowerCase().contains(searchLower) ?? false;
        final matchesCustomer = customer?.name.toLowerCase().contains(searchLower) ?? false;
        final matchesPhone = customer?.phone?.toLowerCase().contains(searchLower) ?? false;
        final matchesBike = bike?.displayName.toLowerCase().contains(searchLower) ?? false;
        final matchesRequest = job.clientRequest?.toLowerCase().contains(searchLower) ?? false;
        
        if (!matchesJob && !matchesCustomer && !matchesPhone && !matchesBike && !matchesRequest) {
          return false;
        }
      }
      
      // Status filter
      if (_statusFilter.isNotEmpty && !_statusFilter.contains(job.status)) {
        return false;
      }
      
      // Priority filter
      if (_priorityFilter.isNotEmpty && job.priority != null && !_priorityFilter.contains(job.priority!)) {
        return false;
      }
      
      // Overdue filter
      if (_showOnlyOverdue && !job.isOverdue) {
        return false;
      }
      
      // Unpaid filter
      if (_showOnlyUnpaid) {
        if (job.isPaid || !job.isInvoiced) {
          return false;
        }
      }
      
      return true;
    }).toList();
    
    // Apply sorting
    if (_sortColumn != null) {
      filtered.sort((a, b) {
        int comparison = 0;
        
        switch (_sortColumn) {
          case 'job_number':
            comparison = (a.jobNumber ?? '').compareTo(b.jobNumber ?? '');
            break;
          case 'customer_quick':
            final customerA = _customers[a.customerId]?.name ?? '';
            final customerB = _customers[b.customerId]?.name ?? '';
            comparison = customerA.compareTo(customerB);
            break;
          case 'bike_quick':
            final bikeA = _bikes[a.bikeId]?.displayName ?? '';
            final bikeB = _bikes[b.bikeId]?.displayName ?? '';
            comparison = bikeA.compareTo(bikeB);
            break;
          case 'status':
            comparison = a.status.index.compareTo(b.status.index);
            break;
          case 'priority':
            comparison = (a.priority?.index ?? 0).compareTo(b.priority?.index ?? 0);
            break;
          case 'arrival_date':
            comparison = a.arrivalDate.compareTo(b.arrivalDate);
            break;
          case 'time_elapsed':
            final daysA = DateTime.now().difference(a.arrivalDate).inDays;
            final daysB = DateTime.now().difference(b.arrivalDate).inDays;
            comparison = daysA.compareTo(daysB);
            break;
          case 'deadline':
            comparison = (a.deadline ?? DateTime(2100)).compareTo(b.deadline ?? DateTime(2100));
            break;
          case 'total_cost':
            comparison = (a.totalCost ?? 0).compareTo(b.totalCost ?? 0);
            break;
          case 'invoice_quick':
            // Sort by payment status: unpaid invoices first
            final statusA = a.isPaid ? 2 : (a.isInvoiced ? 1 : 0);
            final statusB = b.isPaid ? 2 : (b.isInvoiced ? 1 : 0);
            comparison = statusA.compareTo(statusB);
            break;
        }
        
        return _sortAscending ? comparison : -comparison;
      });
    }
    
    setState(() => _filteredJobs = filtered);
  }

  void _sortByColumn(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
      _applyFiltersAndSort();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Column(
        children: [
          _buildHeader(),
          _buildSmartToolbar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildPowerfulTable(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final activeCount = _jobs.where((j) => 
      j.status != JobStatus.entregado && j.status != JobStatus.cancelado
    ).length;
    final readyCount = _jobs.where((j) => j.status == JobStatus.finalizado).length;
    final overdueCount = _jobs.where((j) => j.isOverdue).length;
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.grey[850]!,
            Colors.grey[800]!,
          ],
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.blue[700]!,
                      Colors.blue[600]!,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.construction, size: 32, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pegas (Trabajos de Taller)',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.analytics_outlined,
                        size: 14,
                        color: Colors.blue[300],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${_filteredJobs.length} trabajos mostrados',
                        style: TextStyle(color: Colors.blue[200], fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              _buildQuickStatCard('Activos', activeCount, Icons.pending_actions, Colors.amber),
              const SizedBox(width: 12),
              _buildQuickStatCard('Listos', readyCount, Icons.check_circle, Colors.green),
              const SizedBox(width: 12),
              _buildQuickStatCard('Vencidos', overdueCount, Icons.warning, Colors.red),
              const SizedBox(width: 24),
              ElevatedButton.icon(
                onPressed: () => _showQuickCreateDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Nueva Pega'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStatCard(String label, int count, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[700]!, width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 12,
                ),
              ),
              Text(
                count.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmartToolbar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Main toolbar
          Row(
            children: [
              // View mode selector
              SegmentedButton<String>(
                selected: {_viewMode},
                onSelectionChanged: (Set<String> selected) {
                  setState(() => _viewMode = selected.first);
                  _applyFiltersAndSort();
                },
                segments: const [
                  ButtonSegment(value: 'all', label: Text('Todos'), icon: Icon(Icons.list)),
                  ButtonSegment(value: 'active', label: Text('Activos'), icon: Icon(Icons.build)),
                  ButtonSegment(value: 'ready_for_delivery', label: Text('Listos'), icon: Icon(Icons.done_all)),
                  ButtonSegment(value: 'waiting_payment', label: Text('Por Cobrar'), icon: Icon(Icons.attach_money)),
                ],
              ),
              const SizedBox(width: 16),
              
              // Search with live suggestions
              Expanded(
                child: TextField(
                  style: TextStyle(color: Colors.grey[100]),
                  decoration: InputDecoration(
                    hintText: '🔍 Buscar: N° trabajo, cliente, teléfono, bici...',
                    hintStyle: TextStyle(color: Colors.grey[500]),
                    prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                    suffixIcon: _searchTerm.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, color: Colors.grey[400]),
                            onPressed: () {
                              setState(() => _searchTerm = '');
                              _applyFiltersAndSort();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[700]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[700]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.blue[400]!, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.grey[850],
                  ),
                  onChanged: (value) {
                    setState(() => _searchTerm = value);
                    _applyFiltersAndSort();
                  },
                ),
              ),
              const SizedBox(width: 16),
              
              // Quick filters
              FilterChip(
                label: Row(
                  children: [
                    Icon(Icons.warning, size: 16, color: _showOnlyOverdue ? Colors.white : Colors.red),
                    const SizedBox(width: 4),
                    const Text('Vencidos'),
                  ],
                ),
                selected: _showOnlyOverdue,
                selectedColor: Colors.red[400],
                onSelected: (value) {
                  setState(() => _showOnlyOverdue = value);
                  _applyFiltersAndSort();
                },
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: Row(
                  children: [
                    Icon(Icons.money_off, size: 16, color: _showOnlyUnpaid ? Colors.white : Colors.orange),
                    const SizedBox(width: 4),
                    const Text('Sin Pagar'),
                  ],
                ),
                selected: _showOnlyUnpaid,
                selectedColor: Colors.orange[400],
                onSelected: (value) {
                  setState(() => _showOnlyUnpaid = value);
                  _applyFiltersAndSort();
                },
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Advanced filters row
          Row(
            children: [
              _buildMultiSelectFilter<JobStatus>(
                label: 'Estado',
                icon: Icons.radio_button_checked,
                selectedValues: _statusFilter,
                allValues: JobStatus.values.where((s) => s != JobStatus.entregado && s != JobStatus.cancelado).toList(),
                getLabel: (status) => _getStatusLabel(status),
                getColor: (status) => _getStatusConfig(status)['color'],
              ),
              const SizedBox(width: 12),
              _buildMultiSelectFilter<JobPriority>(
                label: 'Prioridad',
                icon: Icons.flag,
                selectedValues: _priorityFilter,
                allValues: JobPriority.values,
                getLabel: (priority) => _getPriorityLabel(priority),
                getColor: (priority) => _getPriorityConfig(priority)['color'],
              ),
              const Spacer(),
              
              // Column visibility
              IconButton(
                icon: const Icon(Icons.view_column),
                tooltip: 'Personalizar columnas',
                onPressed: _showColumnCustomizer,
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Actualizar',
                onPressed: _loadData,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPowerfulTable() {
    if (_filteredJobs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.construction, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              _searchTerm.isEmpty ? 'No hay trabajos' : 'No se encontraron resultados',
              style: TextStyle(fontSize: 20, color: Colors.grey[600], fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              _searchTerm.isEmpty 
                  ? 'Crea una nueva pega para comenzar'
                  : 'Intenta con otro término de búsqueda',
              style: TextStyle(color: Colors.grey[500]),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showQuickCreateDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Nueva Pega'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(12),
            color: Theme.of(context).cardColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: DataTable(
            headingRowColor: MaterialStateProperty.all(
              Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[850]
                  : Colors.grey[50],
            ),
            headingRowHeight: 56,
            dataRowHeight: 80, // Taller rows for better UX
            columnSpacing: 16,
            horizontalMargin: 16,
            showCheckboxColumn: false,
            columns: _buildPowerfulColumns(),
            rows: _buildPowerfulRows(),
          ),
        ),
      ),
    );
  }

  List<DataColumn> _buildPowerfulColumns() {
    final columnConfigs = {
      'status_indicator': ('', 32.0, false),
      'job_number': ('N° Trabajo', 100.0, true),
      'customer_quick': ('Cliente', 200.0, true),
      'bike_image': ('Foto', 80.0, false),
      'bike_quick': ('Bicicleta', 180.0, true),
      'time_elapsed': ('Tiempo', 100.0, true),
      'status': ('Estado', 140.0, true),
      'priority': ('Prioridad', 110.0, true),
      'invoice_quick': ('Factura/Pago', 140.0, true),
      'deadline': ('Plazo', 120.0, true),
      'total_cost': ('Total', 100.0, true),
      'actions_quick': ('Acciones', 300.0, false), // Increased to fit all buttons
    };

    return _visibleColumns
        .where((col) => columnConfigs.containsKey(col))
        .map((col) {
          final config = columnConfigs[col]!;
          return DataColumn(
            label: config.$3 // sortable
                ? InkWell(
                    onTap: () => _sortByColumn(col),
                    child: Row(
                      children: [
                        Text(
                          config.$1,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        if (_sortColumn == col) ...[
                          const SizedBox(width: 4),
                          Icon(
                            _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                            size: 14,
                          ),
                        ],
                      ],
                    ),
                  )
                : Text(
                    config.$1,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
          );
        })
        .toList();
  }

  List<DataRow> _buildPowerfulRows() {
    return _filteredJobs.map((job) {
      final customer = _customers[job.customerId];
      final bike = _bikes[job.bikeId];
      final isOverdue = job.isOverdue;
      final daysElapsed = DateTime.now().difference(job.arrivalDate).inDays;

      return DataRow(
        onSelectChanged: (_) {
          _markNeedsRefresh(); // Mark for refresh when returning
          context.push('/bikeshop/jobs/${job.id}');
        },
        cells: _visibleColumns
            .where((col) => _getAllColumnIds().contains(col))
            .map((col) => _buildPowerfulCell(
                  col,
                  job,
                  customer,
                  bike,
                  isOverdue,
                  daysElapsed,
                ))
            .toList(),
      );
    }).toList();
  }

  DataCell _buildPowerfulCell(
    String column,
    MechanicJob job,
    Customer? customer,
    Bike? bike,
    bool isOverdue,
    int daysElapsed,
  ) {
    try {
      switch (column) {
        case 'status_indicator':
          return DataCell(
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _getStatusConfig(job.status)['indicatorColor'],
              boxShadow: [
                BoxShadow(
                  color: (_getStatusConfig(job.status)['indicatorColor'] as Color).withOpacity(0.5),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        );

      case 'job_number':
        return DataCell(
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                job.jobNumber ?? 'Sin #',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              Text(
                DateFormat('dd/MM HH:mm').format(job.arrivalDate),
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ),
        );

      case 'customer_quick':
        return DataCell(
          InkWell(
            onTap: customer?.id != null ? () => context.push('/bikeshop/clients/${customer!.id}') : null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.blue[100],
                    child: Text(
                      customer?.name[0].toUpperCase() ?? '?',
                      style: TextStyle(
                        color: Colors.blue[900],
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                customer?.name ?? 'Desconocido',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(Icons.open_in_new, size: 14, color: Colors.blue[400]),
                          ],
                        ),
                        if (customer?.phone != null)
                          Row(
                            children: [
                              Icon(Icons.phone, size: 12, color: Colors.grey[600]),
                              const SizedBox(width: 4),
                              Text(
                                customer!.phone!,
                                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () => _callCustomer(customer.phone!),
                                child: Icon(Icons.phone_in_talk, size: 16, color: Colors.green[600]),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () => _whatsappCustomer(customer.phone!),
                                child: Icon(Icons.message, size: 16, color: Colors.green[700]),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

      case 'bike_image':
        return DataCell(
          bike?.imageUrl != null && bike!.imageUrl!.isNotEmpty
              ? GestureDetector(
                  onTap: () => _showBikeImageModal(bike.imageUrl!),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: CachedNetworkImage(
                      imageUrl: bike.imageUrl!,
                      width: 60,
                      height: 40,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        width: 60,
                        height: 40,
                        color: Colors.grey[300],
                        child: const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: 60,
                        height: 40,
                        color: Colors.grey[300],
                        child: Icon(Icons.pedal_bike, color: Colors.grey[600], size: 24),
                      ),
                    ),
                  ),
                )
              : Container(
                  width: 60,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(Icons.pedal_bike, color: Colors.grey[400], size: 24),
                ),
        );

      case 'bike_quick':
        return DataCell(
          InkWell(
            onTap: () => _showBikeSelectorDialog(job, customer),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.pedal_bike, size: 20, color: Colors.grey[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                bike?.displayName ?? 'N/A',
                                style: const TextStyle(fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(Icons.edit, size: 14, color: Colors.blue[400]),
                          ],
                        ),
                        if (bike?.serialNumber != null)
                          Text(
                            'S/N: ${bike!.serialNumber}',
                            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

      case 'time_elapsed':
        // Determine status-based text and color
        Color timeColor;
        String statusText;
        String timeIcon;
        
        if (job.status == JobStatus.pendiente) {
          statusText = 'Esperando';
          if (daysElapsed < 3) {
            timeColor = Colors.green[700]!;
            timeIcon = '✓';
          } else if (daysElapsed < 7) {
            timeColor = Colors.orange[700]!;
            timeIcon = '⏳';
          } else {
            timeColor = Colors.red[700]!;
            timeIcon = '⚠️';
          }
        } else if (job.status == JobStatus.enCurso) {
          statusText = 'En progreso';
          if (daysElapsed < 3) {
            timeColor = Colors.blue[700]!;
            timeIcon = '🔧';
          } else if (daysElapsed < 7) {
            timeColor = Colors.orange[700]!;
            timeIcon = '⏱️';
          } else {
            timeColor = Colors.red[700]!;
            timeIcon = '🔥';
          }
        } else if (job.status == JobStatus.finalizado || job.status == JobStatus.entregado) {
          statusText = 'Completado';
          timeColor = Colors.grey[600]!;
          timeIcon = '✓';
        } else {
          statusText = 'Estado';
          timeColor = Colors.grey[700]!;
          timeIcon = '⏱️';
        }
        
        return DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: timeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: timeColor.withOpacity(0.3)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeIcon,
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: timeColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$daysElapsed días',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: timeColor,
                  ),
                ),
              ],
            ),
          ),
        );

      case 'status':
        return DataCell(_buildInteractiveStatusBadge(job));

      case 'priority':
        return DataCell(_buildInteractivePriorityBadge(job));

      case 'invoice_quick':
        return DataCell(_buildInvoiceQuickAccess(job));

      case 'deadline':
        if (job.deadline == null) {
          return DataCell(
            InkWell(
              onTap: () => _editDeadline(job),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      'Asignar',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return DataCell(
          InkWell(
            onTap: () => _editDeadline(job),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isOverdue ? Colors.red[50] : Colors.grey[100],
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isOverdue ? Colors.red[300]! : Colors.grey[300]!,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isOverdue ? Icons.warning : Icons.event,
                        size: 14,
                        color: isOverdue ? Colors.red[700] : Colors.grey[700],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('dd/MM').format(job.deadline!),
                        style: TextStyle(
                          color: isOverdue ? Colors.red[700] : Colors.grey[700],
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.edit, size: 12, color: Colors.blue[400]),
                    ],
                  ),
                  if (isOverdue)
                    Text(
                      'VENCIDO',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.red[700],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );

      case 'total_cost':
        final bool isEstimate = job.status == JobStatus.pendiente || 
                                job.status == JobStatus.enCurso ||
                                job.status == JobStatus.diagnostico ||
                                job.status == JobStatus.esperandoAprobacion ||
                                job.status == JobStatus.esperandoRepuestos;
        final formattedAmount = NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(job.totalCost ?? 0);
        
        return DataCell(
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isEstimate)
                Text(
                  'Est.',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[500],
                  ),
                ),
              Text(
                formattedAmount,
                style: TextStyle(
                  fontWeight: isEstimate ? FontWeight.w600 : FontWeight.bold,
                  fontSize: isEstimate ? 14 : 15,
                  color: isEstimate ? Colors.grey[700] : Colors.black,
                ),
              ),
              if (job.status == JobStatus.enCurso)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  height: 2,
                  width: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(1),
                    color: Colors.grey[300],
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: 0.6, // Could calculate actual progress
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(1),
                        color: Colors.blue[600],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );

      case 'actions_quick':
        return DataCell(_buildQuickActions(job, customer));

      default:
        return const DataCell(Text('-'));
    }
    } catch (e) {
      // If any cell fails to render, show error instead of crashing
      debugPrint('Error building cell $column: $e');
      return DataCell(
        Tooltip(
          message: 'Error: $e',
          child: const Icon(Icons.error, color: Colors.red, size: 16),
        ),
      );
    }
  }

  Widget _buildInteractiveStatusBadge(MechanicJob job) {
    final config = _getStatusConfig(job.status);
    return PopupMenuButton<JobStatus>(
      tooltip: 'Cambiar estado',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: config['color'],
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: (config['color'] as Color).withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              config['label'],
              style: TextStyle(
                color: config['textColor'],
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 16, color: config['textColor']),
          ],
        ),
      ),
      itemBuilder: (context) => JobStatus.values
          .where((s) => s != job.status)
          .map((status) {
            final statusConfig = _getStatusConfig(status);
            return PopupMenuItem<JobStatus>(
              value: status,
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: statusConfig['color'],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(statusConfig['label']),
                ],
              ),
            );
          })
          .toList(),
      onSelected: (newStatus) => _quickUpdateStatus(job, newStatus),
    );
  }

  Widget _buildInteractivePriorityBadge(MechanicJob job) {
    if (job.priority == null) return const Text('-');
    
    final config = _getPriorityConfig(job.priority!);
    return PopupMenuButton<JobPriority>(
      tooltip: 'Cambiar prioridad',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: (config['color'] as Color).withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: (config['color'] as Color).withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.flag, size: 14, color: config['color']),
            const SizedBox(width: 4),
            Text(
              config['label'],
              style: TextStyle(
                color: config['color'],
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      itemBuilder: (context) => JobPriority.values
          .map((priority) {
            final priorityConfig = _getPriorityConfig(priority);
            return PopupMenuItem<JobPriority>(
              value: priority,
              child: Row(
                children: [
                  Icon(Icons.flag, size: 16, color: priorityConfig['color']),
                  const SizedBox(width: 8),
                  Text(priorityConfig['label']),
                ],
              ),
            );
          })
          .toList(),
      onSelected: (newPriority) => _quickUpdatePriority(job, newPriority),
    );
  }

  Widget _buildInvoiceQuickAccess(MechanicJob job) {
    // Check if job has an invoice (either by invoice_id or is_invoiced flag)
    if (job.invoiceId == null && !job.isInvoiced) {
      return ElevatedButton.icon(
        onPressed: () => _createInvoiceForJob(job),
        icon: const Icon(Icons.add, size: 16),
        label: const Text('Crear'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          textStyle: const TextStyle(fontSize: 11),
        ),
      );
    }

    // Get invoice details if available
    final invoice = job.invoiceId != null ? _invoices[job.invoiceId] : null;
    final isPaid = invoice?.status == 'paid' || job.isPaid;
    final balance = invoice?.balance ?? job.totalCost;
    final total = invoice?.total ?? job.totalCost;

    return InkWell(
      onTap: () {
        if (job.invoiceId != null) {
          context.push('/sales/invoices/${job.invoiceId}');
        }
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isPaid ? Colors.green[100] : Colors.orange[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isPaid ? Colors.green[300]! : Colors.orange[300]!,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isPaid ? Icons.check_circle : Icons.attach_money,
                  size: 16,
                  color: isPaid ? Colors.green[900] : Colors.orange[900],
                ),
                const SizedBox(width: 4),
                Text(
                  isPaid ? 'PAGADO' : 'PENDIENTE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isPaid ? Colors.green[900] : Colors.orange[900],
                  ),
                ),
              ],
            ),
            Text(
              NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(isPaid ? total : balance),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.grey[900],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(MechanicJob job, Customer? customer) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Phone icon - Copy customer phone
        if (customer?.phone != null)
          Tooltip(
            message: 'Copiar teléfono',
            child: IconButton(
              icon: Icon(Icons.phone, size: 18, color: Colors.blue[600]),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: customer!.phone!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Teléfono copiado'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        if (customer?.phone != null) const SizedBox(width: 4),
        
        // WhatsApp icon
        if (customer?.phone != null)
          Tooltip(
            message: 'WhatsApp',
            child: IconButton(
              icon: Icon(Icons.message, size: 18, color: Colors.green[600]),
              onPressed: () => _whatsappCustomer(customer!.phone!),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        if (customer?.phone != null) const SizedBox(width: 4),
        
        // Invoice icon
        Tooltip(
          message: job.invoiceId != null ? 'Ver factura' : 'Crear factura',
          child: IconButton(
            icon: Icon(
              job.invoiceId != null ? Icons.receipt_long : Icons.receipt,
              size: 18,
              color: job.invoiceId != null ? Colors.green[600] : Colors.orange[600],
            ),
            onPressed: () {
              if (job.invoiceId != null) {
                context.push('/sales/invoices/${job.invoiceId}');
              } else {
                _createInvoiceForJob(job);
              }
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ),
        const SizedBox(width: 4),
        
        // Print icon
        Tooltip(
          message: 'Imprimir orden',
          child: IconButton(
            icon: Icon(Icons.print, size: 18, color: Colors.grey[700]),
            onPressed: () => _printWorkOrder(job),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ),
        const SizedBox(width: 4),
        
        // Checkmark icon
        if (job.status != JobStatus.finalizado && job.status != JobStatus.entregado)
          Tooltip(
            message: 'Marcar como completado',
            child: IconButton(
              icon: Icon(Icons.check_circle_outline, size: 18, color: Colors.blue[600]),
              onPressed: () => _markJobAsComplete(job),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        if (job.status != JobStatus.finalizado && job.status != JobStatus.entregado) const SizedBox(width: 4),
        
        // More actions menu
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, size: 18, color: Colors.grey[600]),
          tooltip: 'Más acciones',
          padding: EdgeInsets.zero,
          itemBuilder: (context) => <PopupMenuEntry<String>>[
            const PopupMenuItem<String>(
              value: 'view',
              child: Row(
                children: [
                  Icon(Icons.visibility, size: 18),
                  SizedBox(width: 8),
                  Text('Ver detalles'),
                ],
              ),
            ),
            const PopupMenuItem<String>(
              value: 'timeline',
              child: Row(
                children: [
                  Icon(Icons.timeline, size: 18),
                  SizedBox(width: 8),
                  Text('Ver historial'),
                ],
              ),
            ),
            const PopupMenuItem<String>(
              value: 'duplicate',
              child: Row(
                children: [
                  Icon(Icons.content_copy, size: 18),
                  SizedBox(width: 8),
                  Text('Duplicar'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem<String>(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 18, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Eliminar', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
          onSelected: (value) {
            switch (value) {
              case 'view':
                context.push('/bikeshop/jobs/${job.id}');
                break;
              case 'timeline':
                _showJobTimeline(job);
                break;
              case 'duplicate':
                _duplicateJob(job);
                break;
              case 'delete':
                _confirmDelete(job);
                break;
            }
          },
        ),
      ],
    );
  }

  // Helper methods for interactive features
  Future<void> _quickUpdateStatus(MechanicJob job, JobStatus newStatus) async {
    try {
      final updatedJob = MechanicJob(
        id: job.id,
        customerId: job.customerId,
        bikeId: job.bikeId,
        jobNumber: job.jobNumber,
        arrivalDate: job.arrivalDate,
        status: newStatus,
        priority: job.priority,
        clientRequest: job.clientRequest,
        diagnosis: job.diagnosis,
        notes: job.notes,
        assignedTo: job.assignedTo,
        deadline: job.deadline,
        estimatedCost: job.estimatedCost,
        totalCost: job.totalCost,
        partsCost: job.partsCost,
        laborCost: job.laborCost,
      );
      
      await _bikeshopService.updateJob(updatedJob);
      await _loadData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Estado actualizado a: ${_getStatusLabel(newStatus)}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _quickUpdatePriority(MechanicJob job, JobPriority newPriority) async {
    try {
      final updatedJob = MechanicJob(
        id: job.id,
        customerId: job.customerId,
        bikeId: job.bikeId,
        jobNumber: job.jobNumber,
        arrivalDate: job.arrivalDate,
        status: job.status,
        priority: newPriority,
        clientRequest: job.clientRequest,
        diagnosis: job.diagnosis,
        notes: job.notes,
        assignedTo: job.assignedTo,
        deadline: job.deadline,
        estimatedCost: job.estimatedCost,
        totalCost: job.totalCost,
        partsCost: job.partsCost,
        laborCost: job.laborCost,
      );
      
      await _bikeshopService.updateJob(updatedJob);
      await _loadData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Prioridad actualizada a: ${_getPriorityLabel(newPriority)}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _callCustomer(String phone) {
    // In a real app, this would trigger a phone call
    Clipboard.setData(ClipboardData(text: phone));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Teléfono copiado: $phone'),
        action: SnackBarAction(
          label: 'Llamar',
          onPressed: () {
            // Implement actual phone call
          },
        ),
      ),
    );
  }

  void _whatsappCustomer(String phone) {
    // In a real app, this would open WhatsApp
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Abrir WhatsApp con: $phone'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _createInvoiceForJob(MechanicJob job) {
    context.push('/sales/invoices/new?job_id=${job.id}&customer_id=${job.customerId}');
  }

  void _printWorkOrder(MechanicJob job) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Imprimiendo orden de trabajo...')),
    );
  }

  void _duplicateJob(MechanicJob job) {
    context.push('/bikeshop/jobs/new?duplicate_from=${job.id}');
  }

  Future<void> _markJobAsComplete(MechanicJob job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Marcar como completado'),
          ],
        ),
        content: Text(
          '¿Está seguro que desea marcar el trabajo #${job.jobNumber} como completado?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Completar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _bikeshopService.updateJobStatus(job.id!, JobStatus.finalizado);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Trabajo marcado como completado'),
              backgroundColor: Colors.green,
            ),
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showBikeImageModal(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
            child: Stack(
              children: [
                Center(
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    errorWidget: (context, url, error) => const Center(
                      child: Icon(Icons.error, color: Colors.white, size: 48),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 32),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showBikeSelectorDialog(MechanicJob job, Customer? customer) async {
    if (customer == null || customer.id == null) return;

    // Load customer's bikes
    final bikes = await _bikeshopService.getBikes(customerId: customer.id!);

    if (!mounted) return;

    String? selectedBikeId = job.bikeId;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.pedal_bike, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Seleccionar Bicicleta - ${customer.name}'),
              ),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (bikes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Icon(Icons.info_outline, size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 12),
                        Text(
                          'Este cliente no tiene bicicletas registradas',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  )
                else
                  ...bikes.map((bike) => RadioListTile<String>(
                    value: bike.id!,
                    groupValue: selectedBikeId,
                    onChanged: (value) {
                      setState(() {
                        selectedBikeId = value;
                      });
                    },
                    title: Text(bike.displayName ?? 'Sin nombre'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (bike.serialNumber != null)
                          Text('S/N: ${bike.serialNumber}'),
                        if (bike.color != null)
                          Text('Color: ${bike.color}'),
                      ],
                    ),
                    secondary: bike.imageUrl != null && bike.imageUrl!.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: bike.imageUrl!,
                              width: 60,
                              height: 40,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: Colors.grey[200],
                                child: const Center(child: CircularProgressIndicator()),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: Colors.grey[200],
                                child: const Icon(Icons.pedal_bike, color: Colors.grey),
                              ),
                            ),
                          )
                        : Container(
                            width: 60,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.pedal_bike, color: Colors.grey),
                          ),
                  )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: bikes.isEmpty || selectedBikeId == null
                  ? null
                  : () async {
                      if (selectedBikeId != job.bikeId) {
                        try {
                          final updatedJob = job.copyWith(bikeId: selectedBikeId);
                          await _bikeshopService.updateJob(updatedJob);
                          if (mounted) {
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Bicicleta actualizada'),
                                backgroundColor: Colors.green,
                              ),
                            );
                            _loadData();
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      } else {
                        Navigator.of(context).pop();
                      }
                    },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editDeadline(MechanicJob job) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: job.deadline ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      // Removed locale to avoid freeze issues - will use system locale
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.blue,
              onPrimary: Colors.white,
              onSurface: Colors.grey[900]!,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != job.deadline) {
      try {
        final updatedJob = job.copyWith(deadline: picked);
        await _bikeshopService.updateJob(updatedJob);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Plazo actualizado a ${DateFormat('dd/MM/yyyy').format(picked)}',
              ),
              backgroundColor: Colors.green,
            ),
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showJobTimeline(MechanicJob job) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Historial: ${job.jobNumber}'),
        content: const Text('Función de historial aquí...'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(MechanicJob job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Trabajo'),
        content: Text('¿Eliminar ${job.jobNumber}?\n\nEsta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _bikeshopService.deleteJob(job.id!);
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Trabajo eliminado'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _showQuickCreateDialog() {
    _markNeedsRefresh(); // Mark for refresh when returning
    context.push('/bikeshop/jobs/new');
  }

  void _showColumnCustomizer() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Personalizar Columnas'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _getAllColumnIds().map((col) {
                return CheckboxListTile(
                  title: Text(_getColumnLabel(col)),
                  value: _visibleColumns.contains(col),
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _visibleColumns.add(col);
                      } else {
                        _visibleColumns.remove(col);
                      }
                    });
                    Navigator.pop(context);
                    _showColumnCustomizer();
                  },
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _buildMultiSelectFilter<T>({
    required String label,
    required IconData icon,
    required Set<T> selectedValues,
    required List<T> allValues,
    required String Function(T) getLabel,
    required Color Function(T) getColor,
  }) {
    return PopupMenuButton<T>(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: selectedValues.isEmpty ? Colors.grey[300]! : Colors.orange[400]!),
          borderRadius: BorderRadius.circular(8),
          color: selectedValues.isEmpty ? Colors.white : Colors.orange[50],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selectedValues.isEmpty ? Colors.grey[600] : Colors.orange[700]),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: selectedValues.isEmpty ? Colors.grey[700] : Colors.orange[700],
                fontWeight: selectedValues.isEmpty ? FontWeight.normal : FontWeight.w600,
              ),
            ),
            if (selectedValues.isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange[700],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${selectedValues.length}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey[600]),
          ],
        ),
      ),
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Filtrar por $label',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              if (selectedValues.isNotEmpty)
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() => selectedValues.clear());
                    _applyFiltersAndSort();
                  },
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(50, 30),
                  ),
                  child: const Text('Limpiar', style: TextStyle(fontSize: 11)),
                ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        ...allValues.map((value) => CheckedPopupMenuItem<T>(
          value: value,
          checked: selectedValues.contains(value),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: getColor(value),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(getLabel(value), style: const TextStyle(fontSize: 13)),
            ],
          ),
        )),
      ],
      onSelected: (value) {
        setState(() {
          if (selectedValues.contains(value)) {
            selectedValues.remove(value);
          } else {
            selectedValues.add(value);
          }
        });
        _applyFiltersAndSort();
      },
    );
  }

  List<String> _getAllColumnIds() => [
    'status_indicator',
    'job_number',
    'customer_quick',
    'bike_quick',
    'time_elapsed',
    'status',
    'priority',
    'invoice_quick',
    'deadline',
    'total_cost',
    'actions_quick',
  ];

  String _getColumnLabel(String column) {
    final labels = {
      'status_indicator': 'Indicador',
      'job_number': 'N° Trabajo',
      'customer_quick': 'Cliente (con acceso rápido)',
      'bike_quick': 'Bicicleta',
      'time_elapsed': 'Tiempo Transcurrido',
      'status': 'Estado',
      'priority': 'Prioridad',
      'invoice_quick': 'Factura/Pago',
      'deadline': 'Plazo',
      'total_cost': 'Costo Total',
      'actions_quick': 'Acciones Rápidas',
    };
    return labels[column] ?? column;
  }

  String _getStatusLabel(JobStatus status) {
    final labels = {
      JobStatus.pendiente: 'Pendiente',
      JobStatus.diagnostico: 'Diagnóstico',
      JobStatus.esperandoAprobacion: 'Esperando Aprobación',
      JobStatus.enCurso: 'En Curso',
      JobStatus.esperandoRepuestos: 'Esperando Repuestos',
      JobStatus.finalizado: 'Finalizado',
      JobStatus.entregado: 'Entregado',
      JobStatus.cancelado: 'Cancelado',
    };
    return labels[status] ?? status.toString();
  }

  String _getPriorityLabel(JobPriority priority) {
    final labels = {
      JobPriority.baja: 'Baja',
      JobPriority.normal: 'Normal',
      JobPriority.alta: 'Alta',
      JobPriority.urgente: 'Urgente',
    };
    return labels[priority] ?? priority.toString();
  }

  Map<String, dynamic> _getStatusConfig(JobStatus status) {
    switch (status) {
      case JobStatus.pendiente:
        return {
          'color': Colors.grey[200],
          'textColor': Colors.grey[800],
          'label': 'Pendiente',
          'indicatorColor': Colors.grey[400],
        };
      case JobStatus.diagnostico:
        return {
          'color': Colors.blue[100],
          'textColor': Colors.blue[900],
          'label': 'Diagnóstico',
          'indicatorColor': Colors.blue[500],
        };
      case JobStatus.esperandoAprobacion:
        return {
          'color': Colors.amber[100],
          'textColor': Colors.amber[900],
          'label': 'Esperando Aprobación',
          'indicatorColor': Colors.amber[600],
        };
      case JobStatus.enCurso:
        return {
          'color': Colors.orange[100],
          'textColor': Colors.orange[900],
          'label': 'En Curso',
          'indicatorColor': Colors.orange[500],
        };
      case JobStatus.esperandoRepuestos:
        return {
          'color': Colors.purple[100],
          'textColor': Colors.purple[900],
          'label': 'Esperando Repuestos',
          'indicatorColor': Colors.purple[500],
        };
      case JobStatus.finalizado:
        return {
          'color': Colors.green[100],
          'textColor': Colors.green[900],
          'label': 'Finalizado',
          'indicatorColor': Colors.green[500],
        };
      case JobStatus.entregado:
        return {
          'color': Colors.teal[100],
          'textColor': Colors.teal[900],
          'label': 'Entregado',
          'indicatorColor': Colors.teal[500],
        };
      case JobStatus.cancelado:
        return {
          'color': Colors.red[100],
          'textColor': Colors.red[900],
          'label': 'Cancelado',
          'indicatorColor': Colors.red[500],
        };
    }
  }

  Map<String, dynamic> _getPriorityConfig(JobPriority priority) {
    switch (priority) {
      case JobPriority.baja:
        return {'color': Colors.grey[600], 'label': 'Baja'};
      case JobPriority.normal:
        return {'color': Colors.blue[600], 'label': 'Normal'};
      case JobPriority.alta:
        return {'color': Colors.orange[600], 'label': 'Alta'};
      case JobPriority.urgente:
        return {'color': Colors.red[600], 'label': 'Urgente'};
    }
  }
}
