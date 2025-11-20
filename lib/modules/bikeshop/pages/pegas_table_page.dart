import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/services/database_service.dart';
import '../../crm/models/crm_models.dart';
import '../../crm/services/customer_service.dart';
import '../../sales/models/sales_models.dart';
import '../services/bikeshop_service.dart';
import '../models/bikeshop_models.dart';
import '../widgets/pega_detail_view.dart';

/// Modern, professional Pegas management with advanced data table
class PegasTablePage extends StatefulWidget {
  const PegasTablePage({super.key});

  @override
  State<PegasTablePage> createState() => _PegasTablePageState();
}

class _PegasTablePageState extends State<PegasTablePage>
    with WidgetsBindingObserver {
  late BikeshopService _bikeshopService;
  late CustomerService _customerService;
  late DatabaseService _databaseService;

  List<MechanicJob> _jobs = [];
  List<MechanicJob> _filteredJobs = [];
  Map<String, Customer> _customers = {};
  Map<String, Bike> _bikes = {};
  Map<String, Invoice> _invoices = {};
  Map<String, String> _productImages = {};

  bool _isLoading = true;
  bool _needsRefresh = false;
  Timer? _reloadDebounceTimer;
  String _searchTerm = '';
  
  // Scroll controller for synchronized horizontal scrolling
  final ScrollController _horizontalScrollController = ScrollController();

  // Selected job for detail view
  MechanicJob? _selectedJob;
  List<MechanicJobItem> _selectedJobItems = [];

  // Split-pane state
  static const double _minListPaneWidth = 500.0;
  static const double _minDetailPaneWidth = 400.0;
  static const double _defaultListPaneWidth = 1000.0;
  double _listPaneWidth = _defaultListPaneWidth;

  // Column management
  String? _sortColumn = 'arrival_date';
  bool _sortAscending = false;
  List<ColumnConfig> _columns = [];

  // Filters
  String _statusFilter = 'active';
  final Set<JobStatus> _customStatusFilter = {};
  final Set<JobPriority> _priorityFilter = {};
  bool _showOnlyOverdue = false;
  bool _showOnlyUnpaid = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _databaseService = Provider.of<DatabaseService>(context, listen: false);
    _bikeshopService = Provider.of<BikeshopService>(context, listen: false);
    _customerService = Provider.of<CustomerService>(context, listen: false);
    _initializeColumns();
    _loadListPaneWidth();
    _loadData();
  }

  @override
  void dispose() {
    _reloadDebounceTimer?.cancel();
    _horizontalScrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _initializeColumns() {
    _columns = [
      ColumnConfig(
        id: 'status',
        label: '',
        width: 40,
        minWidth: 40,
        maxWidth: 40,
        visible: true,
        sortable: false,
        resizable: false,
      ),
      ColumnConfig(
        id: 'job_number',
        label: 'N° Trabajo',
        width: 120,
        minWidth: 100,
        visible: true,
        sortable: true,
      ),
      ColumnConfig(
        id: 'customer',
        label: 'Cliente',
        width: 200,
        minWidth: 150,
        visible: true,
        sortable: true,
      ),
      ColumnConfig(
        id: 'bike',
        label: 'Bicicleta',
        width: 180,
        minWidth: 150,
        visible: true,
        sortable: true,
      ),
      ColumnConfig(
        id: 'arrival_date',
        label: 'Ingreso',
        width: 110,
        minWidth: 100,
        visible: true,
        sortable: true,
      ),
      ColumnConfig(
        id: 'deadline',
        label: 'Plazo',
        width: 110,
        minWidth: 100,
        visible: true,
        sortable: true,
      ),
      ColumnConfig(
        id: 'state',
        label: 'Estado',
        width: 140,
        minWidth: 120,
        visible: true,
        sortable: true,
      ),
      ColumnConfig(
        id: 'priority',
        label: 'Prioridad',
        width: 110,
        minWidth: 100,
        visible: true,
        sortable: true,
      ),
      ColumnConfig(
        id: 'total',
        label: 'Total',
        width: 120,
        minWidth: 100,
        visible: true,
        sortable: true,
      ),
      ColumnConfig(
        id: 'invoice',
        label: 'Factura',
        width: 120,
        minWidth: 100,
        visible: true,
        sortable: false,
      ),
      ColumnConfig(
        id: 'actions',
        label: 'Acciones',
        width: 120,
        minWidth: 120,
        maxWidth: 120,
        visible: true,
        sortable: false,
        resizable: false,
      ),
    ];
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _needsRefresh) {
      _needsRefresh = false;
      _loadData();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context)?.isCurrent == true && _needsRefresh) {
      _needsRefresh = false;
      _loadData();
    }
  }

  void _markNeedsRefresh() {
    _needsRefresh = true;
  }

  Future<void> _openInvoice(String invoiceId) async {
    _markNeedsRefresh();
    await context
        .push('/sales/invoices/$invoiceId/edit?returnTo=/taller/pegas');
    if (!mounted) return;
    await _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _bikeshopService.getJobs(includeCompleted: true),
        _customerService.getCustomers(),
        _bikeshopService.getBikes(),
        _loadInvoices(),
      ]);

      final jobs = results[0] as List<MechanicJob>;
      final customers = results[1] as List<Customer>;
      final bikes = results[2] as List<Bike>;
      final invoices = results[3] as List<Invoice>;

      final customerMap = <String, Customer>{};
      for (final customer in customers) {
        if (customer.id != null) customerMap[customer.id!] = customer;
      }

      final bikeMap = <String, Bike>{};
      for (final bike in bikes) {
        if (bike.id != null) bikeMap[bike.id!] = bike;
      }

      final invoiceMap = <String, Invoice>{};
      for (final invoice in invoices) {
        if (invoice.id != null) invoiceMap[invoice.id!] = invoice;
      }

      if (mounted) {
        setState(() {
          _jobs = jobs;
          _filteredJobs = jobs;
          _customers = customerMap;
          _bikes = bikeMap;
          _invoices = invoiceMap;
          _isLoading = false;
        });
        _applyFiltersAndSort();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
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
      return [];
    }
  }

  Future<void> _loadJobDetails(MechanicJob job) async {
    try {
      final items = await _bikeshopService.getJobItems(job.id!);
      final Map<String, String> productImages = {};
      
      try {
        final productIds = items
            .where((item) => item.productId != null)
            .map((item) => item.productId!)
            .toSet();

        if (productIds.isNotEmpty) {
          final response = await Supabase.instance.client
              .from('products')
              .select('id, image_url')
              .inFilter('id', productIds.toList());

          for (final product in response) {
            final id = product['id'] as String;
            final imageUrl = product['image_url'] as String?;
            if (imageUrl != null && imageUrl.isNotEmpty) {
              productImages[id] = imageUrl;
            }
          }
        }
      } catch (e) {
        debugPrint('Error loading product images: $e');
      }

      if (mounted) {
        setState(() {
          _selectedJobItems = items;
          _productImages = productImages;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar detalles: $e')),
        );
      }
    }
  }

  Future<void> _loadListPaneWidth() async {
    final prefs = await SharedPreferences.getInstance();
    final savedWidth = prefs.getDouble('pegas_list_pane_width');
    if (savedWidth != null && mounted) {
      setState(() => _listPaneWidth = savedWidth);
    }
  }

  Future<void> _saveListPaneWidth(double width) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('pegas_list_pane_width', width);
  }

  void _applyFiltersAndSort() {
    final hasCustomStatusFilter = _customStatusFilter.isNotEmpty;

    var filtered = _jobs.where((job) {
      // Status filter
      switch (_statusFilter) {
        case 'active':
          if (!hasCustomStatusFilter &&
              (job.status == JobStatus.entregado ||
                  job.status == JobStatus.cancelado)) {
            return false;
          }
          break;
        case 'completed':
          if (job.status != JobStatus.finalizado) return false;
          break;
        case 'delivered':
          if (job.status != JobStatus.entregado) return false;
          break;
        case 'unpaid':
          if (job.isPaid || !job.isInvoiced) return false;
          break;
      }

      // Search filter
      if (_searchTerm.isNotEmpty) {
        final searchLower = _searchTerm.toLowerCase();
        final customer = _customers[job.customerId];
        final bike = _bikes[job.bikeId];

        final matches =
            (job.jobNumber ?? '').toLowerCase().contains(searchLower) ||
                (customer?.name ?? '').toLowerCase().contains(searchLower) ||
                (customer?.phone ?? '').toLowerCase().contains(searchLower) ||
                (bike?.displayName ?? '').toLowerCase().contains(searchLower) ||
                (job.clientRequest ?? '').toLowerCase().contains(searchLower);

        if (!matches) return false;
      }

      // Custom status filter
      if (hasCustomStatusFilter && !_customStatusFilter.contains(job.status)) {
        return false;
      }

      // Priority filter
      if (_priorityFilter.isNotEmpty &&
          !_priorityFilter.contains(job.priority)) {
        return false;
      }

      // Overdue filter
      if (_showOnlyOverdue && !job.isOverdue) return false;

      // Unpaid filter
      if (_showOnlyUnpaid && (job.isPaid || !job.isInvoiced)) return false;

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
          case 'customer':
            final customerA = _customers[a.customerId]?.name ?? '';
            final customerB = _customers[b.customerId]?.name ?? '';
            comparison = customerA.compareTo(customerB);
            break;
          case 'bike':
            final bikeA = _bikes[a.bikeId]?.displayName ?? '';
            final bikeB = _bikes[b.bikeId]?.displayName ?? '';
            comparison = bikeA.compareTo(bikeB);
            break;
          case 'state':
            comparison = a.status.index.compareTo(b.status.index);
            break;
          case 'priority':
            comparison = a.priority.index.compareTo(b.priority.index);
            break;
          case 'arrival_date':
            comparison = a.arrivalDate.compareTo(b.arrivalDate);
            break;
          case 'deadline':
            comparison = (a.deadline ?? DateTime(2100))
                .compareTo(b.deadline ?? DateTime(2100));
            break;
          case 'total':
            comparison = a.totalCost.compareTo(b.totalCost);
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
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _selectedJob != null
              ? _buildSplitView()
              : Column(
                  children: [
                    _buildModernHeader(),
                    _buildToolbar(),
                    Expanded(child: _buildDataTable()),
                  ],
                ),
    );
  }

  Widget _buildSplitView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final clampedListWidth = _listPaneWidth.clamp(
          _minListPaneWidth,
          availableWidth - _minDetailPaneWidth - 1,
        );

        return Row(
          children: [
            // Left: Jobs list
            SizedBox(
              width: clampedListWidth,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(
                          color: Theme.of(context).dividerColor,
                          width: 1,
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildModernHeader(),
                        _buildToolbar(),
                        Expanded(child: _buildDataTable()),
                      ],
                    ),
                  ),
                  // Resize handle
                  Positioned(
                    right: -6,
                    top: 0,
                    bottom: 0,
                    width: 12,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeColumn,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onHorizontalDragUpdate: (details) {
                          setState(() {
                            final maxWidth =
                                availableWidth - _minDetailPaneWidth - 1;
                            _listPaneWidth = (_listPaneWidth + details.delta.dx)
                                .clamp(_minListPaneWidth, maxWidth);
                          });
                          _saveListPaneWidth(_listPaneWidth);
                        },
                        child: Container(color: Colors.transparent),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Right: Detail view
            Expanded(
              child: PegaDetailView(
                job: _selectedJob!,
                customer: _customers[_selectedJob!.customerId],
                bike: _bikes[_selectedJob!.bikeId],
                items: _selectedJobItems,
                productImages: _productImages,
                onClose: () {
                  setState(() {
                    _selectedJob = null;
                    _selectedJobItems = [];
                    _productImages = {};
                  });
                },
                onEdit: () async {
                  await context.push('/taller/pegas/${_selectedJob!.id}');
                  if (!mounted) return;
                  await _loadData();
                  if (_selectedJob != null) {
                    await _loadJobDetails(_selectedJob!);
                  }
                },
                onStatusChange: (newStatus) async {
                  final updatedJob = _selectedJob!.copyWith(status: newStatus);
                  await _databaseService.update(
                    'mechanic_jobs',
                    updatedJob.id!,
                    updatedJob.toJson(),
                  );
                  if (!mounted) return;
                  await _loadData();
                  final updated =
                      _jobs.firstWhere((j) => j.id == _selectedJob!.id);
                  setState(() {
                    _selectedJob = updated;
                  });
                  await _loadJobDetails(updated);
                },
                onItemRemoved: (itemId) async {
                  try {
                    await _bikeshopService.deleteJobItem(itemId);
                    if (_selectedJob != null) {
                      await _loadJobDetails(_selectedJob!);
                    }
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Product removed')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  }
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildModernHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          // Title section
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gestión de Trabajos',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.5,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_filteredJobs.length} trabajo${_filteredJobs.length != 1 ? 's' : ''}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),

          // Action buttons
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Actualizar',
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: () {
              _markNeedsRefresh();
              context.push('/taller/pegas/nueva');
            },
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Nuevo Trabajo'),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        children: [
          // Main controls row
          Row(
            children: [
              // Status filter
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'active',
                    label: Text('Activos', style: TextStyle(fontSize: 13)),
                  ),
                  ButtonSegment(
                    value: 'completed',
                    label: Text('Completados', style: TextStyle(fontSize: 13)),
                  ),
                  ButtonSegment(
                    value: 'delivered',
                    label: Text('Entregados', style: TextStyle(fontSize: 13)),
                  ),
                  ButtonSegment(
                    value: 'unpaid',
                    label: Text('Sin Pagar', style: TextStyle(fontSize: 13)),
                  ),
                  ButtonSegment(
                    value: 'all',
                    label: Text('Todos', style: TextStyle(fontSize: 13)),
                  ),
                ],
                selected: <String>{_statusFilter},
                onSelectionChanged: (selected) {
                  if (selected.isNotEmpty) {
                    setState(() => _statusFilter = selected.first);
                    _applyFiltersAndSort();
                  }
                },
              ),

              const SizedBox(width: 16),

              // Search
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar trabajos...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchTerm.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                setState(() => _searchTerm = '');
                                _applyFiltersAndSort();
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() => _searchTerm = value);
                      _applyFiltersAndSort();
                    },
                  ),
                ),
              ),
            ],
          ),

          // Filters row
          const SizedBox(height: 12),
          Row(
            children: [
              // Quick filters
              if (_showOnlyOverdue || _showOnlyUnpaid) ...[
                Wrap(
                  spacing: 8,
                  children: [
                    if (_showOnlyOverdue)
                      Chip(
                        label: const Text('Vencidos', style: TextStyle(fontSize: 12)),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () {
                          setState(() => _showOnlyOverdue = false);
                          _applyFiltersAndSort();
                        },
                        backgroundColor: Colors.red.shade50,
                        side: BorderSide(color: Colors.red.shade200),
                      ),
                    if (_showOnlyUnpaid)
                      Chip(
                        label: const Text('Sin Pagar', style: TextStyle(fontSize: 12)),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () {
                          setState(() => _showOnlyUnpaid = false);
                          _applyFiltersAndSort();
                        },
                        backgroundColor: Colors.orange.shade50,
                        side: BorderSide(color: Colors.orange.shade200),
                      ),
                  ],
                ),
                const SizedBox(width: 8),
              ],

              // Filter menu
              PopupMenuButton<String>(
                icon: const Icon(Icons.filter_list),
                tooltip: 'Filtros',
                itemBuilder: (context) => <PopupMenuEntry<String>>[
                  const PopupMenuItem(
                    enabled: false,
                    child: Text('Filtros', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const PopupMenuDivider(),
                  CheckedPopupMenuItem(
                    value: 'overdue',
                    checked: _showOnlyOverdue,
                    child: const Text('Solo vencidos'),
                  ),
                  CheckedPopupMenuItem(
                    value: 'unpaid',
                    checked: _showOnlyUnpaid,
                    child: const Text('Solo sin pagar'),
                  ),
                ],
                onSelected: (value) {
                  setState(() {
                    if (value == 'overdue') {
                      _showOnlyOverdue = !_showOnlyOverdue;
                    } else if (value == 'unpaid') {
                      _showOnlyUnpaid = !_showOnlyUnpaid;
                    }
                  });
                  _applyFiltersAndSort();
                },
              ),

              // Column customizer
              IconButton(
                icon: const Icon(Icons.view_column),
                onPressed: _showColumnCustomizer,
                tooltip: 'Personalizar columnas',
              ),

              const Spacer(),

              // Stats - sum invoice totals, not job costs
              if (_filteredJobs.isNotEmpty)
                Text(
                  'Valor total: ${NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(_filteredJobs.fold<double>(0, (sum, job) {
                    final invoice = job.invoiceId != null ? _invoices[job.invoiceId] : null;
                    return sum + (invoice?.total ?? job.totalCost);
                  }))}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDataTable() {
    if (_filteredJobs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              _searchTerm.isEmpty ? 'No hay trabajos' : 'No se encontraron resultados',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _searchTerm.isEmpty
                  ? 'Crea un nuevo trabajo para comenzar'
                  : 'Intenta con otro término de búsqueda',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate total width of all visible columns
        final totalColumnsWidth = _columns
            .where((col) => col.visible)
            .fold<double>(0, (sum, col) => sum + col.width);
        
        // Use the larger of constraints.maxWidth or totalColumnsWidth
        final tableWidth = totalColumnsWidth > constraints.maxWidth 
            ? totalColumnsWidth 
            : constraints.maxWidth;
        
        return Column(
          children: [
            // Table header
            SingleChildScrollView(
              controller: _horizontalScrollController,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: SizedBox(
                width: tableWidth,
                child: _buildTableHeader(tableWidth),
              ),
            ),
            // Table body
            Expanded(
              child: SingleChildScrollView(
                controller: _horizontalScrollController,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: ListView.builder(
                    itemCount: _filteredJobs.length,
                    itemBuilder: (context, index) => 
                        _buildTableRow(_filteredJobs[index], tableWidth),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTableHeader(double tableWidth) {
    return Container(
      width: tableWidth,
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: Row(
        children: _columns.where((col) => col.visible).map((col) {
          return _buildHeaderCell(col);
        }).toList(),
      ),
    );
  }

  Widget _buildHeaderCell(ColumnConfig col) {
    // Use Expanded for flexible columns, Container with fixed width for non-resizable
    final child = Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: col.sortable ? () => _sortByColumn(col.id) : null,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    col.label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (col.sortable && _sortColumn == col.id) ...[
                  const SizedBox(width: 4),
                  Icon(
                    _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 16,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (col.resizable)
          MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              onHorizontalDragUpdate: (details) {
                setState(() {
                  col.width = (col.width + details.delta.dx)
                      .clamp(col.minWidth, col.maxWidth ?? 500);
                });
              },
              child: Container(
                width: 8,
                color: Colors.transparent,
                child: Center(
                  child: Container(
                    width: 1,
                    height: 20,
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    if (col.maxWidth != null && col.maxWidth == col.width) {
      // Fixed width column
      return Container(
        width: col.width,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: child,
      );
    } else {
      // Flexible column
      return Expanded(
        flex: (col.width ~/ 10).clamp(1, 100), // Use width as flex ratio
        child: Container(
          constraints: BoxConstraints(minWidth: col.minWidth),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: child,
        ),
      );
    }
  }

  Widget _buildTableRow(MechanicJob job, double tableWidth) {
    final isSelected = _selectedJob?.id == job.id;
    final customer = _customers[job.customerId];
    final bike = _bikes[job.bikeId];

    return InkWell(
      onTap: () {
        setState(() {
          _selectedJob = job;
        });
        _loadJobDetails(job);
      },
      child: Container(
        width: tableWidth,
        height: 60,
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
              : null,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor.withOpacity(0.5),
            ),
          ),
        ),
        child: Row(
          children: _columns.where((col) => col.visible).map((col) {
            return _buildDataCell(col, job, customer, bike);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildDataCell(
      ColumnConfig col, MechanicJob job, Customer? customer, Bike? bike) {
    final content = _getCellContent(col.id, job, customer, bike);
    
    if (col.maxWidth != null && col.maxWidth == col.width) {
      // Fixed width column
      return Container(
        width: col.width,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: content,
      );
    } else {
      // Flexible column
      return Expanded(
        flex: (col.width ~/ 10).clamp(1, 100), // Use width as flex ratio
        child: Container(
          constraints: BoxConstraints(minWidth: col.minWidth),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: content,
        ),
      );
    }
  }

  Widget _getCellContent(String columnId, MechanicJob job, Customer? customer, Bike? bike) {
    switch (columnId) {
      case 'status':
        // Clickable status indicator with color
        return InkWell(
          onTap: () => _showStatusMenu(job),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _getStatusColor(job.status),
              border: Border.all(
                color: _getStatusColor(job.status).withOpacity(0.5),
                width: 2,
              ),
            ),
          ),
        );

      case 'job_number':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              job.jobNumber ?? 'Sin #',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            Text(
              DateFormat('dd/MM/yy').format(job.arrivalDate),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        );

      case 'customer':
        // Clickable customer with quick actions
        return InkWell(
          onTap: customer?.id != null
              ? () => context.push('/clientes/${customer!.id}')
              : null,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      customer?.name ?? 'Desconocido',
                      style: TextStyle(
                        fontSize: 13,
                        color: customer?.id != null
                            ? Theme.of(context).colorScheme.primary
                            : null,
                        decoration: customer?.id != null
                            ? TextDecoration.underline
                            : null,
                        decorationColor:
                            Theme.of(context).colorScheme.primary.withOpacity(0.3),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (customer?.phone != null)
                      Text(
                        customer!.phone!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (customer != null &&
                  (customer.phone != null || customer.email != null))
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.6),
                  ),
                  tooltip: 'Acciones rápidas',
                  padding: EdgeInsets.zero,
                  itemBuilder: (context) => [
                    if (customer.phone != null)
                      PopupMenuItem(
                        value: 'call',
                        child: Row(
                          children: [
                            Icon(Icons.phone, size: 16, color: Colors.green.shade700),
                            const SizedBox(width: 8),
                            const Text('Llamar', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                    if (customer.email != null)
                      PopupMenuItem(
                        value: 'email',
                        child: Row(
                          children: [
                            Icon(Icons.email, size: 16, color: Colors.blue.shade700),
                            const SizedBox(width: 8),
                            const Text('Email', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                  ],
                  onSelected: (value) {
                    if (value == 'call' && customer.phone != null) {
                      _callCustomer(customer.phone!);
                    } else if (value == 'email' && customer.email != null) {
                      _emailCustomer(customer.email!);
                    }
                  },
                ),
            ],
          ),
        );

      case 'bike':
        // Clickable bike with optional image preview
        final bikeName = bike?.displayName ?? 'N/A';
        return InkWell(
          onTap: () => _showBikeSelectorDialog(job, customer),
          child: Row(
            children: [
              // Bike icon (always show)
              Icon(
                Icons.pedal_bike_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.primary.withOpacity(0.7),
              ),
              const SizedBox(width: 6),
              // Bike image thumbnail if available
              if (bike?.imageUrl != null) ...[
                GestureDetector(
                  onTap: () => _showBikeImageModal(bike!.imageUrl!),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      image: DecorationImage(
                        image: NetworkImage(bike!.imageUrl!),
                        fit: BoxFit.cover,
                      ),
                      border: Border.all(
                        color: Theme.of(context).dividerColor,
                        width: 1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  bikeName,
                  style: const TextStyle(
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );

      case 'arrival_date':
        final days = DateTime.now().difference(job.arrivalDate).inDays;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              DateFormat('dd/MM').format(job.arrivalDate),
              style: const TextStyle(fontSize: 13),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: days > 14
                    ? Colors.red.shade50
                    : days > 7
                        ? Colors.orange.shade50
                        : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$days día${days != 1 ? 's' : ''}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: days > 14
                      ? Colors.red.shade700
                      : days > 7
                          ? Colors.orange.shade700
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        );

      case 'deadline':
        // Clickable deadline with overdue indicator
        final isOverdue = job.deadline != null &&
            job.deadline!.isBefore(DateTime.now()) &&
            job.status != JobStatus.entregado;
        return InkWell(
          onTap: () => _editDeadline(job),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isOverdue
                    ? Icons.warning_amber_rounded
                    : job.deadline != null
                        ? Icons.calendar_today
                        : Icons.event_busy,
                size: 14,
                color: isOverdue
                    ? Colors.red.shade700
                    : Colors.grey.shade600,
              ),
              const SizedBox(width: 4),
              Text(
                job.deadline != null
                    ? DateFormat('dd/MM/yy').format(job.deadline!)
                    : 'Sin plazo',
                style: TextStyle(
                  fontSize: 13,
                  color: isOverdue ? Colors.red.shade700 : null,
                ),
              ),
            ],
          ),
        );

      case 'state':
        // Clickable state badge
        final statusColor = _getStatusColor(job.status);
        return InkWell(
          onTap: () => _showStatusMenu(job),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: statusColor.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  job.status.displayName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );

      case 'priority':
        // Colored priority with icon
        final priorityColor = _getPriorityColor(job.priority);
        final priorityIcon = job.priority == JobPriority.urgente
            ? Icons.priority_high
            : job.priority == JobPriority.alta
                ? Icons.arrow_upward
                : job.priority == JobPriority.normal
                    ? Icons.drag_handle
                    : Icons.arrow_downward;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: priorityColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: priorityColor.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(priorityIcon, size: 14, color: priorityColor),
              const SizedBox(width: 4),
              Text(
                job.priority.displayName,
                style: TextStyle(
                  fontSize: 12,
                  color: priorityColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );

      case 'total':
        // Show invoice total if exists, otherwise job total cost
        final invoice = job.invoiceId != null ? _invoices[job.invoiceId] : null;
        final displayTotal = invoice?.total ?? job.totalCost;
        return Text(
          NumberFormat.currency(symbol: '\$', decimalDigits: 0)
              .format(displayTotal),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        );

      case 'invoice':
        // Clickable invoice with payment status
        if (job.invoiceId == null && !job.isInvoiced) {
          return InkWell(
            onTap: () => _createInvoiceForJob(job),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Colors.grey.shade300,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_circle_outline,
                      size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    'Generar',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final invoice = job.invoiceId != null ? _invoices[job.invoiceId] : null;
        final isPaid = (invoice != null &&
                invoice.status.toString().toLowerCase() == 'paid') ||
            job.isPaid;
        final isPartial = invoice != null &&
            invoice.status.toString().toLowerCase() == 'partiallypaid';
        return InkWell(
          onTap: job.invoiceId != null ? () => _openInvoice(job.invoiceId!) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isPaid
                  ? Colors.green.shade50
                  : isPartial
                      ? Colors.orange.shade50
                      : Colors.red.shade50.withOpacity(0.5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isPaid
                    ? Colors.green.shade300
                    : isPartial
                        ? Colors.orange.shade300
                        : Colors.red.shade200,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isPaid
                      ? Icons.check_circle
                      : isPartial
                          ? Icons.schedule
                          : Icons.payment,
                  size: 14,
                  color: isPaid
                      ? Colors.green.shade700
                      : isPartial
                          ? Colors.orange.shade700
                          : Colors.red.shade700,
                ),
                const SizedBox(width: 4),
                Text(
                  isPaid
                      ? 'PAGADO'
                      : isPartial
                          ? 'PARCIAL'
                          : 'PENDIENTE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isPaid
                        ? Colors.green.shade800
                        : isPartial
                            ? Colors.orange.shade800
                            : Colors.red.shade800,
                    decoration: job.invoiceId != null
                        ? TextDecoration.underline
                        : null,
                    decorationColor: isPaid
                        ? Colors.green.shade800.withOpacity(0.3)
                        : isPartial
                            ? Colors.orange.shade800.withOpacity(0.3)
                            : Colors.red.shade800.withOpacity(0.3),
                  ),
                ),
              ],
            ),
          ),
        );

      case 'actions':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, size: 16),
              onPressed: () => context.push('/taller/pegas/${job.id}'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: 'Editar',
            ),
            IconButton(
              icon: const Icon(Icons.phone, size: 16),
              onPressed: customer?.phone != null
                  ? () {
                      Clipboard.setData(ClipboardData(text: customer!.phone!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Teléfono copiado')),
                      );
                    }
                  : null,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: 'Teléfono',
            ),
            PopupMenuButton(
              icon: const Icon(Icons.more_vert, size: 16),
              padding: EdgeInsets.zero,
              tooltip: 'Más',
              iconSize: 16,
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'complete',
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, size: 18),
                      SizedBox(width: 8),
                      Text('Completar'),
                    ],
                  ),
                ),
                const PopupMenuItem(
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
                if (value == 'complete') {
                  _markJobAsComplete(job);
                } else if (value == 'delete') {
                  _confirmDelete(job);
                }
              },
            ),
          ],
        );

      default:
        return const Text('-');
    }
  }

  void _showColumnCustomizer() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Personalizar Columnas'),
        content: SizedBox(
          width: 400,
          child: ReorderableListView(
            shrinkWrap: true,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex--;
                final item = _columns.removeAt(oldIndex);
                _columns.insert(newIndex, item);
              });
            },
            children: _columns.map((col) {
              return CheckboxListTile(
                key: ValueKey(col.id),
                title: Row(
                  children: [
                    const Icon(Icons.drag_handle, size: 20),
                    const SizedBox(width: 8),
                    Text(col.label),
                  ],
                ),
                value: col.visible,
                onChanged: col.id == 'job_number' // Always keep job number visible
                    ? null
                    : (value) {
                        setState(() => col.visible = value ?? true);
                        Navigator.pop(context);
                        _showColumnCustomizer();
                      },
              );
            }).toList(),
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

  void _createInvoiceForJob(MechanicJob job) {
    context.push(
        '/sales/invoices/new?job_id=${job.id}&customer_id=${job.customerId}');
  }

  Future<void> _markJobAsComplete(MechanicJob job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Marcar como completado'),
        content: Text('¿Completar el trabajo ${job.jobNumber}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Completar'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _bikeshopService.updateJobStatus(job.id!, JobStatus.finalizado);
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Trabajo completado')),
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

  Future<void> _confirmDelete(MechanicJob job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Trabajo'),
        content: Text('¿Eliminar ${job.jobNumber}? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
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
            const SnackBar(content: Text('Trabajo eliminado')),
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

  // Interactive cell methods
  void _showStatusMenu(MechanicJob job) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cambiar Estado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: JobStatus.values.map((status) {
            final statusColor = _getStatusColor(status);
            final isSelected = job.status == status;
            return ListTile(
              leading: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: statusColor.withOpacity(0.5),
                    width: isSelected ? 3 : 1,
                  ),
                ),
              ),
              title: Text(
                status.displayName,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : null,
                  color: isSelected ? statusColor : null,
                ),
              ),
              onTap: () async {
                Navigator.pop(context);
                try {
                  await _bikeshopService.updateJobStatus(job.id!, status);
                  _loadData();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Estado actualizado a ${status.displayName}'),
                      ),
                    );
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
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  void _callCustomer(String phone) {
    Clipboard.setData(ClipboardData(text: phone));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Teléfono copiado: $phone'),
        action: SnackBarAction(
          label: 'Abrir',
          onPressed: () {
            // Could integrate with url_launcher to open phone dialer
            // For now just copy to clipboard
          },
        ),
      ),
    );
  }

  void _emailCustomer(String email) {
    Clipboard.setData(ClipboardData(text: email));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Email copiado: $email'),
        action: SnackBarAction(
          label: 'Abrir',
          onPressed: () {
            // Could integrate with url_launcher to open email client
            // For now just copy to clipboard
          },
        ),
      ),
    );
  }

  void _showBikeSelectorDialog(MechanicJob job, Customer? customer) async {
    if (customer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cliente no encontrado')),
      );
      return;
    }

    // Load customer's bikes
    final bikes = _bikes.values.where((b) => b.customerId == customer.id).toList();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seleccionar Bicicleta'),
        content: SizedBox(
          width: 400,
          child: bikes.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.pedal_bike_outlined, size: 48, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'Este cliente no tiene bicicletas registradas',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: bikes.map((bike) {
                    final isSelected = bike.id == job.bikeId;
                    final bikeName = '${bike.brand ?? ''} ${bike.model ?? ''}'.trim();
                    return ListTile(
                      leading: bike.imageUrl != null
                          ? Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                image: DecorationImage(
                                  image: NetworkImage(bike.imageUrl!),
                                  fit: BoxFit.cover,
                                ),
                                border: Border.all(
                                  color: Theme.of(context).dividerColor,
                                ),
                              ),
                            )
                          : const Icon(Icons.pedal_bike, size: 40),
                      title: Text(
                        bikeName.isNotEmpty ? bikeName : 'Sin nombre',
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : null,
                        ),
                      ),
                      subtitle: bike.serialNumber != null
                          ? Text('N° Serie: ${bike.serialNumber}')
                          : null,
                      trailing: isSelected
                          ? Icon(Icons.check_circle, color: Colors.green.shade700)
                          : null,
                      selected: isSelected,
                      onTap: isSelected
                          ? null
                          : () async {
                              Navigator.pop(context);
                              try {
                                final updatedJob = MechanicJob(
                                  id: job.id,
                                  tenantId: job.tenantId,
                                  jobNumber: job.jobNumber,
                                  customerId: job.customerId,
                                  bikeId: bike.id!,
                                  arrivalDate: job.arrivalDate,
                                  deadline: job.deadline,
                                  status: job.status,
                                  priority: job.priority,
                                  clientRequest: job.clientRequest,
                                  diagnosis: job.diagnosis,
                                  workPerformed: job.workPerformed,
                                  notes: job.notes,
                                  estimatedCost: job.estimatedCost,
                                  finalCost: job.finalCost,
                                  partsCost: job.partsCost,
                                  laborCost: job.laborCost,
                                  totalCost: job.totalCost,
                                  invoiceId: job.invoiceId,
                                  createdAt: job.createdAt,
                                  updatedAt: DateTime.now(),
                                );
                                await _bikeshopService.updateJob(updatedJob);
                                _loadData();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Bicicleta cambiada a: $bikeName'),
                                    ),
                                  );
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
                            },
                    );
                  }).toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              context.push('/clientes/${customer.id}?tab=bikes');
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Nueva Bici'),
          ),
        ],
      ),
    );
  }

  void _showBikeImageModal(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 600, maxHeight: 600),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Container(
                      padding: const EdgeInsets.all(32),
                      color: Colors.grey.shade800,
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.broken_image, size: 64, color: Colors.white54),
                          SizedBox(height: 16),
                          Text(
                            'Error al cargar imagen',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                ),
                child: const Text('Cerrar'),
              ),
            ],
          ),
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
      helpText: 'Seleccionar fecha límite',
    );

    if (picked != null && mounted) {
      try {
        final updatedJob = MechanicJob(
          id: job.id,
          tenantId: job.tenantId,
          jobNumber: job.jobNumber,
          customerId: job.customerId,
          bikeId: job.bikeId,
          arrivalDate: job.arrivalDate,
          deadline: picked,
          status: job.status,
          priority: job.priority,
          clientRequest: job.clientRequest,
          diagnosis: job.diagnosis,
          workPerformed: job.workPerformed,
          notes: job.notes,
          estimatedCost: job.estimatedCost,
          finalCost: job.finalCost,
          partsCost: job.partsCost,
          laborCost: job.laborCost,
          totalCost: job.totalCost,
          invoiceId: job.invoiceId,
          createdAt: job.createdAt,
          updatedAt: DateTime.now(),
        );
        await _bikeshopService.updateJob(updatedJob);
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Plazo actualizado: ${DateFormat('dd/MM/yyyy').format(picked)}'),
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

  void _showInvoiceGenerationDialog(MechanicJob job) {
    _createInvoiceForJob(job);
  }

  Color _getStatusColor(JobStatus status) {
    switch (status) {
      case JobStatus.pendiente:
        return Colors.grey.shade600;
      case JobStatus.diagnostico:
        return Colors.blue.shade600;
      case JobStatus.esperandoAprobacion:
        return Colors.amber.shade700;
      case JobStatus.enCurso:
        return Colors.orange.shade600;
      case JobStatus.esperandoRepuestos:
        return Colors.purple.shade600;
      case JobStatus.finalizado:
        return Colors.green.shade600;
      case JobStatus.entregado:
        return Colors.teal.shade600;
      case JobStatus.cancelado:
        return Colors.red.shade600;
    }
  }

  Color _getPriorityColor(JobPriority priority) {
    switch (priority) {
      case JobPriority.baja:
        return Colors.grey.shade600;
      case JobPriority.normal:
        return Colors.blue.shade600;
      case JobPriority.alta:
        return Colors.orange.shade600;
      case JobPriority.urgente:
        return Colors.red.shade600;
    }
  }
}

class ColumnConfig {
  final String id;
  final String label;
  double width;
  final double minWidth;
  final double? maxWidth;
  bool visible;
  final bool sortable;
  final bool resizable;

  ColumnConfig({
    required this.id,
    required this.label,
    required this.width,
    required this.minWidth,
    this.maxWidth,
    this.visible = true,
    this.sortable = true,
    this.resizable = true,
  });
}
