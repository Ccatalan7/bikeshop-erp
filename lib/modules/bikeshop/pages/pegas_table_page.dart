import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
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

enum PegasViewMode { table, board, calendar }

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

class _PegasTablePageState extends State<PegasTablePage>
    with WidgetsBindingObserver {
  late BikeshopService _bikeshopService;
  late CustomerService _customerService;
  late DatabaseService _databaseService;

  List<MechanicJob> _jobs = [];
  List<MechanicJob> _filteredJobs = [];
  Map<String, Customer> _customers = {};
  Map<String, Bike> _bikes = {};
  Map<String, Invoice> _invoices = {}; // invoice_id -> invoice
  Map<String, String> _productImages = {}; // product_id -> image_url

  bool _isLoading = true;
  bool _needsRefresh = false; // Track if we need to refresh on next visibility
  Timer? _reloadDebounceTimer; // Debounce rapid reload calls
  String _searchTerm = '';
  
  // View mode state
  PegasViewMode _viewMode = PegasViewMode.table;
  DateTime _focusedMonth = DateTime.now();
  DateTime _selectedDate = DateTime.now();
  
  // Selected job for detail view (calendar sidebar)
  MechanicJob? _selectedJob;
  List<MechanicJobItem> _selectedJobItems = [];
  bool _loadingDetails = false;

  // Split-pane state for table view
  static const double _minListPaneWidth = 400.0;
  static const double _minDetailPaneWidth = 300.0; // Minimum for detail view
  static const double _defaultListPaneWidth = 1000.0; // Default: list takes more space, detail narrower
  double _listPaneWidth = _defaultListPaneWidth;

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
  String _filterMode =
      'active'; // active, ready_for_delivery, waiting_payment, delivered, all
  static const double _statusFilterMenuWidth = 240;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _databaseService = Provider.of<DatabaseService>(context, listen: false);
    _bikeshopService = Provider.of<BikeshopService>(context, listen: false);
    _customerService = Provider.of<CustomerService>(context, listen: false);
    _loadListPaneWidth();
    _loadData();
    
    // ✅ REMOVED: BikeshopService listener - was causing unnecessary full reloads
    // Old: _bikeshopService.addListener(_onRealtimeUpdate);
    // Every task/item change → updates job costs → triggers realtime → full reload
    // Now realtime updates handled at widget level (tasks tab updates itself)
  }

  @override
  void dispose() {
    _reloadDebounceTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    // ✅ REMOVED: _bikeshopService.removeListener(_onRealtimeUpdate);
    super.dispose();
  }
  
  void _onRealtimeUpdate() {
    debugPrint('🟠 [PegasTablePage] _onRealtimeUpdate called by BikeshopService');
    // Debounce rapid reload calls (prevent race conditions)
    _reloadDebounceTimer?.cancel();
    _reloadDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        debugPrint('🟠 [PegasTablePage] Debounce timer fired, calling _loadData()');
        _loadData();
      }
    });
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

  Future<void> _openInvoice(String invoiceId) async {
    _markNeedsRefresh();
    // Navigate to invoice form page with returnTo parameter
    await context.push('/sales/invoices/$invoiceId/edit?returnTo=/taller/pegas');
    if (!mounted) return;
    debugPrint('🔄 Reloading data after invoice edit...');
    await _loadData();
    debugPrint('✅ Data reloaded - invoices count: ${_invoices.length}');
  }

  Future<void> _loadData() async {
    debugPrint('🔴 [PegasTablePage] _loadData() started - FULL PAGE RELOAD');
    setState(() => _isLoading = true);
    try {
      // Load all data in parallel for performance
      final results = await Future.wait([
        _bikeshopService.getJobs(includeCompleted: true),
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
      debugPrint('Error loading invoices: $e');
      return [];
    }
  }

  Future<void> _loadJobDetails(MechanicJob job) async {
    try {
      // Load job items (parts/products)
      final items = await _bikeshopService.getJobItems(job.id!);
      
      // Load product images
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
          _loadingDetails = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingDetails = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar detalles: $e')),
        );
      }
    }
  }

  // SharedPreferences for split-pane width persistence
  Future<void> _loadListPaneWidth() async {
    final prefs = await SharedPreferences.getInstance();
    final savedWidth = prefs.getDouble('pegas_list_pane_width');
    if (savedWidth != null && mounted) {
      setState(() {
        // Just use the saved width, will be clamped dynamically in _buildSplitView
        _listPaneWidth = savedWidth;
      });
    }
  }

  Future<void> _saveListPaneWidth(double width) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('pegas_list_pane_width', width);
  }

  void _applyFiltersAndSort() {
    final hasCustomStatusFilter = _statusFilter.isNotEmpty;

    var filtered = _jobs.where((job) {
      // View mode filter
      switch (_filterMode) {
        case 'active':
          if (!hasCustomStatusFilter &&
              (job.status == JobStatus.entregado ||
                  job.status == JobStatus.cancelado)) {
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
        case 'delivered':
          if (job.status != JobStatus.entregado) {
            return false;
          }
          break;
        case 'all':
        default:
          break;
      }

      // Search filter
      if (_searchTerm.isNotEmpty) {
        final searchLower = _searchTerm.toLowerCase();
        final customer = _customers[job.customerId];
        final bike = _bikes[job.bikeId];

        final matchesJob = (job.jobNumber ?? '').toLowerCase().contains(searchLower);
        final matchesCustomer =
            customer?.name.toLowerCase().contains(searchLower) ?? false;
        final matchesPhone =
            customer?.phone?.toLowerCase().contains(searchLower) ?? false;
        final matchesBike =
            bike?.displayName.toLowerCase().contains(searchLower) ?? false;
        final matchesRequest =
            job.clientRequest?.toLowerCase().contains(searchLower) ?? false;

        if (!matchesJob &&
            !matchesCustomer &&
            !matchesPhone &&
            !matchesBike &&
            !matchesRequest) {
          return false;
        }
      }

      // Status filter
      if (hasCustomStatusFilter && !_statusFilter.contains(job.status)) {
        return false;
      }

      // Priority filter
      if (_priorityFilter.isNotEmpty &&
          !_priorityFilter.contains(job.priority)) {
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
            comparison = (a.jobNumber ?? '~')
                .compareTo(b.jobNumber ?? '~');
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
            comparison = a.priority.index.compareTo(b.priority.index);
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
            comparison = (a.deadline ?? DateTime(2100))
                .compareTo(b.deadline ?? DateTime(2100));
            break;
          case 'total_cost':
            comparison = a.totalCost.compareTo(b.totalCost);
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
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _viewMode == PegasViewMode.table && _selectedJob != null
              ? _buildSplitView()
              : _viewMode == PegasViewMode.table
                  ? Column(
                      children: [
                        _buildHeader(),
                        _buildSmartToolbar(),
                        Expanded(
                          child: _buildViewContent(),
                        ),
                      ],
                    )
                  : SingleChildScrollView(
                      child: Column(
                        children: [
                          _buildHeader(),
                          SizedBox(
                            height: MediaQuery.of(context).size.height - 120,
                            child: _buildViewContent(),
                          ),
                        ],
                      ),
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
            // Left: Jobs list with persistent border just like MainLayout
            SizedBox(
              width: clampedListWidth,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        // Close detail pane when clicking anywhere on left pane
                        setState(() {
                          _selectedJob = null;
                          _selectedJobItems = [];
                          _productImages = {};
                        });
                      },
                      child: Container(
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
                            _buildHeader(),
                            _buildSmartToolbar(),
                            Expanded(
                              child: _buildViewContent(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
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
                            final maxWidth = availableWidth - _minDetailPaneWidth - 1;
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

            // Right: Detail view (takes remaining space)
            Expanded(
              child: Container(
                constraints: BoxConstraints(
                  minWidth: _minDetailPaneWidth,
                ),
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
                    // Navigate to form, refresh on return
                    await context.push('/taller/pegas/${_selectedJob!.id}');
                    if (!mounted) return;
                    await _loadData();
                    // Reload detail after edit
                    if (_selectedJob != null) {
                      setState(() => _loadingDetails = true);
                      await _loadJobDetails(_selectedJob!);
                    }
                  },
                  onStatusChange: (newStatus) async {
                    // Update job status
                    final updatedJob = _selectedJob!.copyWith(status: newStatus);
                    await _databaseService.update(
                      'mechanic_jobs',
                      updatedJob.id!,
                      updatedJob.toJson(),
                    );
                    if (!mounted) return;
                    await _loadData();
                    // Reload the selected job with updated data
                    final updated = _jobs.firstWhere((j) => j.id == _selectedJob!.id);
                    setState(() {
                      _selectedJob = updated;
                      _loadingDetails = true;
                    });
                    await _loadJobDetails(updated);
                  },
                  // ✅ Removed onItemAdded - realtime handles updates, prevents tab switch
                  onItemRemoved: (itemId) async {
                    try {
                      await _bikeshopService.deleteJobItem(itemId);
                      // ✅ Removed _loadData() - realtime handles updates automatically
                      // Only reload detail view to update totals
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
            ),
          ],
        );
      },
    );
  }

  Widget _buildViewContent() {
    switch (_viewMode) {
      case PegasViewMode.table:
        return _buildPowerfulTable();
      case PegasViewMode.board:
        return _buildBoardView();
      case PegasViewMode.calendar:
        return _buildCalendarView();
    }
  }

  Widget _buildHeader() {
    final activeCount = _jobs
        .where((j) =>
            j.status != JobStatus.entregado && j.status != JobStatus.cancelado)
        .length;
    final readyCount =
        _jobs.where((j) => j.status == JobStatus.finalizado).length;
    final overdueCount = _jobs.where((j) => j.isOverdue).length;
    final deliveredCount =
        _jobs.where((j) => j.status == JobStatus.entregado).length;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade300,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.construction,
                    size: 32, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Gestión de clientes',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.analytics_outlined,
                        size: 14,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${_filteredJobs.length} trabajos mostrados',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              
              // View mode switchers (Notion-style)
              _buildViewSwitcher(
                icon: Icons.table_chart,
                label: 'Table',
                mode: PegasViewMode.table,
              ),
              const SizedBox(width: 8),
              _buildViewSwitcher(
                icon: Icons.view_kanban,
                label: 'Board',
                mode: PegasViewMode.board,
              ),
              const SizedBox(width: 8),
              _buildViewSwitcher(
                icon: Icons.calendar_month,
                label: 'Calendar',
                mode: PegasViewMode.calendar,
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () => _showQuickCreateDialog(),
                icon: const Icon(Icons.add),
                label: const Text('New'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildQuickStatCard('Activos', activeCount,
                          Icons.pending_actions, Colors.amber),
                      const SizedBox(width: 12),
                      _buildQuickStatCard('Listos', readyCount,
                          Icons.check_circle, Colors.green),
                      const SizedBox(width: 12),
                      _buildQuickStatCard(
                          'Vencidos', overdueCount, Icons.warning, Colors.red),
                      const SizedBox(width: 12),
                      _buildQuickStatCard('Entregadas', deliveredCount,
                          Icons.inventory_2, Colors.teal),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStatCard(
      String label, int count, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300, width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
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
                  color: Colors.grey.shade600,
                  fontSize: 12,
                ),
              ),
              Text(
                count.toString(),
                style: const TextStyle(
                  color: Colors.black87,
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

  ButtonSegment<String> _buildSegmentedButtonSegment({
    required String value,
    required String label,
    required IconData icon,
  }) {
    return ButtonSegment<String>(
      value: value,
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
    );
  }

  Widget _buildSmartToolbar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade300,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Main toolbar
          Row(
            children: [
              // View mode selector
              SegmentedButton<String>(
                selected: {_filterMode},
                onSelectionChanged: (Set<String> selected) {
                  setState(() => _filterMode = selected.first);
                  _applyFiltersAndSort();
                },
                segments: [
                  _buildSegmentedButtonSegment(
                    value: 'active',
                    label: 'Activos',
                    icon: Icons.build,
                  ),
                  _buildSegmentedButtonSegment(
                    value: 'ready_for_delivery',
                    label: 'Listos',
                    icon: Icons.done_all,
                  ),
                  _buildSegmentedButtonSegment(
                    value: 'waiting_payment',
                    label: 'Por Cobrar',
                    icon: Icons.attach_money,
                  ),
                  _buildSegmentedButtonSegment(
                    value: 'delivered',
                    label: 'Entregadas',
                    icon: Icons.inventory_2,
                  ),
                  _buildSegmentedButtonSegment(
                    value: 'all',
                    label: 'Todos',
                    icon: Icons.list,
                  ),
                ],
              ),
              const SizedBox(width: 16),

              // Search with live suggestions
              Expanded(
                flex: 4,
                child: TextField(
                  style: const TextStyle(color: Colors.black87),
                  decoration: InputDecoration(
                    hintText:
                        'Buscar: N° trabajo, cliente, teléfono, bici...',
                    hintStyle: TextStyle(color: Colors.grey.shade500),
                    prefixIcon: Icon(Icons.search, color: Colors.grey.shade600),
                    suffixIcon: _searchTerm.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, color: Colors.grey.shade600),
                            onPressed: () {
                              setState(() => _searchTerm = '');
                              _applyFiltersAndSort();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    isDense: true,
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
                    Icon(Icons.warning,
                        size: 16,
                        color: _showOnlyOverdue ? Colors.white : Colors.red),
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
                    Icon(Icons.money_off,
                        size: 16,
                        color: _showOnlyUnpaid ? Colors.white : Colors.orange),
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
              _buildStatusFilterDropdown(),
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
              _searchTerm.isEmpty
                  ? 'No hay trabajos'
                  : 'No se encontraron resultados',
              style: TextStyle(
                  fontSize: 20,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
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
      'actions_quick': (
        'Acciones',
        300.0,
        false
      ), // Increased to fit all buttons
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
                        _sortAscending
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
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
    }).toList();
  }

  List<DataRow> _buildPowerfulRows() {
    return _filteredJobs.map((job) {
      final customer = _customers[job.customerId];
      final bike = _bikes[job.bikeId];
      final isOverdue = job.isOverdue;
      final daysElapsed = DateTime.now().difference(job.arrivalDate).inDays;
      final isSelected = _selectedJob?.id == job.id;

      return DataRow(
        selected: isSelected,
        color: WidgetStateProperty.resolveWith<Color?>((states) {
          if (isSelected) {
            return Colors.grey.withOpacity(0.2); // Light grey highlight for selected row
          }
          return null; // Default row color
        }),
        onSelectChanged: (_) {
          setState(() {
            _selectedJob = job;
            _loadingDetails = true;
          });
          _loadJobDetails(job);
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
                    color: (_getStatusConfig(job.status)['indicatorColor']
                            as Color)
                        .withOpacity(0.5),
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
              onTap: customer?.id != null
                  ? () => context.push('/clientes/${customer!.id}?tab=pegas')
                  : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.blue[100],
                      child: Text(
                        customer?.name[0].toUpperCase() ?? '?',
                        style: TextStyle(
                          color: Colors.blue[900],
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  customer?.name ?? 'Desconocido',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(Icons.open_in_new,
                                  size: 12, color: Colors.blue[400]),
                            ],
                          ),
                          if (customer?.phone != null)
                            Row(
                              children: [
                                Icon(Icons.phone,
                                    size: 10, color: Colors.grey[600]),
                                const SizedBox(width: 2),
                                Expanded(
                                  child: Text(
                                    customer!.phone!,
                                    style: TextStyle(
                                        fontSize: 10, color: Colors.grey[600]),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                InkWell(
                                  onTap: () => _callCustomer(customer.phone!),
                                  child: Icon(Icons.phone_in_talk,
                                      size: 14, color: Colors.green[600]),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: () =>
                                      _whatsappCustomer(customer.phone!),
                                  child: Icon(Icons.message,
                                      size: 14, color: Colors.green[700]),
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
                          child: Icon(Icons.pedal_bike,
                              color: Colors.grey[600], size: 24),
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
                    child: Icon(Icons.pedal_bike,
                        color: Colors.grey[400], size: 24),
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
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w500),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(Icons.edit,
                                  size: 14, color: Colors.blue[400]),
                            ],
                          ),
                          if (bike?.serialNumber != null)
                            Text(
                              'S/N: ${bike!.serialNumber}',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.grey[600]),
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
          String timeIcon;

          if (job.status == JobStatus.pendiente) {
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
          } else if (job.status == JobStatus.finalizado ||
              job.status == JobStatus.entregado) {
            timeColor = Colors.grey[600]!;
            timeIcon = '✓';
          } else {
            timeColor = Colors.grey[700]!;
            timeIcon = '⏱️';
          }

          return DataCell(
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: timeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(timeIcon, style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 4),
                  Text(
                    '$daysElapsed días',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_today,
                          size: 14, color: Colors.grey[600]),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                            color:
                                isOverdue ? Colors.red[700] : Colors.grey[700],
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
          final formattedAmount =
              NumberFormat.currency(symbol: '\$', decimalDigits: 0)
                  .format(job.totalCost);

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
          border:
              Border.all(color: (config['color'] as Color).withOpacity(0.5)),
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
      itemBuilder: (context) =>
          JobStatus.values.where((s) => s != job.status).map((status) {
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
      }).toList(),
      onSelected: (newStatus) => _quickUpdateStatus(job, newStatus),
    );
  }

  Widget _buildInteractivePriorityBadge(MechanicJob job) {
    final config = _getPriorityConfig(job.priority);
    return PopupMenuButton<JobPriority>(
      tooltip: 'Cambiar prioridad',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: (config['color'] as Color).withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border:
              Border.all(color: (config['color'] as Color).withOpacity(0.3)),
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
      itemBuilder: (context) => JobPriority.values.map((priority) {
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
      }).toList(),
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
    
    // Debug output
    if (job.invoiceId != null && invoice != null) {
      debugPrint('📄 Job ${job.jobNumber}: invoice total=${invoice.total}, balance=${invoice.balance}, status=${invoice.status}');
    } else if (job.invoiceId != null && invoice == null) {
      debugPrint('⚠️ Job ${job.jobNumber}: has invoiceId=${job.invoiceId} but invoice NOT found in map!');
    }
    
    final isPaid = invoice?.status == 'paid' || job.isPaid;
    final balance = invoice?.balance ?? job.totalCost;
    final total = invoice?.total ?? job.totalCost;
    
    // Get invoice status label (Spanish)
    String statusLabel = 'PENDIENTE';
    Color statusColor = Colors.orange[900]!;
    Color bgColor = Colors.orange[100]!;
    Color borderColor = Colors.orange[300]!;
    IconData statusIcon = Icons.attach_money;
    
    if (invoice != null) {
      final status = invoice.status.name.toLowerCase();
      if (status == 'paid' || status == 'pagado' || status == 'pagada') {
        statusLabel = 'PAGADO';
        statusColor = Colors.green[900]!;
        bgColor = Colors.green[100]!;
        borderColor = Colors.green[300]!;
        statusIcon = Icons.check_circle;
      } else if (status == 'confirmed' || status == 'confirmado' || status == 'confirmada') {
        statusLabel = 'CONFIRMADO';
        statusColor = Colors.green[700]!;
        bgColor = Colors.green[50]!;
        borderColor = Colors.green[200]!;
        statusIcon = Icons.verified;
      } else if (status == 'draft' || status == 'borrador') {
        statusLabel = 'BORRADOR';
        statusColor = Colors.grey[700]!;
        bgColor = Colors.grey[100]!;
        borderColor = Colors.grey[300]!;
        statusIcon = Icons.edit_document;
      } else if (status == 'sent' || status == 'enviado' || status == 'enviada' || status == 'emitido' || status == 'emitida' || status == 'issued') {
        statusLabel = 'ENVIADO';
        statusColor = Colors.blue[900]!;
        bgColor = Colors.blue[100]!;
        borderColor = Colors.blue[300]!;
        statusIcon = Icons.send;
      } else if (status == 'overdue' || status == 'vencido' || status == 'vencida') {
        statusLabel = 'VENCIDO';
        statusColor = Colors.red[900]!;
        bgColor = Colors.red[100]!;
        borderColor = Colors.red[300]!;
        statusIcon = Icons.warning;
      } else if (status == 'cancelled' || status == 'cancelado' || status == 'cancelada' || status == 'anulado' || status == 'anulada') {
        statusLabel = 'CANCELADO';
        statusColor = Colors.grey[700]!;
        bgColor = Colors.grey[100]!;
        borderColor = Colors.grey[300]!;
        statusIcon = Icons.cancel;
      }
    }

    return InkWell(
      onTap: () async {
        if (job.invoiceId != null) {
          await _openInvoice(job.invoiceId!);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: borderColor,
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
                  statusIcon,
                  size: 16,
                  color: statusColor,
                ),
                const SizedBox(width: 4),
                Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ],
            ),
            Text(
              NumberFormat.currency(symbol: '\$', decimalDigits: 0)
                  .format(isPaid ? total : balance),
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
              color: job.invoiceId != null
                  ? Colors.green[600]
                  : Colors.orange[600],
            ),
            onPressed: () async {
              if (job.invoiceId != null) {
                await _openInvoice(job.invoiceId!);
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
        if (job.status != JobStatus.finalizado &&
            job.status != JobStatus.entregado)
          Tooltip(
            message: 'Marcar como completado',
            child: IconButton(
              icon: Icon(Icons.check_circle_outline,
                  size: 18, color: Colors.blue[600]),
              onPressed: () => _markJobAsComplete(job),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        if (job.status != JobStatus.finalizado &&
            job.status != JobStatus.entregado)
          const SizedBox(width: 4),

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
                context.push('/taller/pegas/${job.id}');
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
        tenantId: job.tenantId,
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
        // Don't pass cost fields - they're calculated by database triggers
      );

      await _bikeshopService.updateJob(updatedJob);
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Estado actualizado a: ${_getStatusLabel(newStatus)}'),
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

  Future<void> _quickUpdatePriority(
      MechanicJob job, JobPriority newPriority) async {
    try {
      final updatedJob = MechanicJob(
        id: job.id,
        tenantId: job.tenantId,
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
        // Don't pass cost fields - they're calculated by database triggers
      );

      await _bikeshopService.updateJob(updatedJob);
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Prioridad actualizada a: ${_getPriorityLabel(newPriority)}'),
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
    context.push(
        '/sales/invoices/new?job_id=${job.id}&customer_id=${job.customerId}');
  }

  void _printWorkOrder(MechanicJob job) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Imprimiendo orden de trabajo...')),
    );
  }

  void _duplicateJob(MechanicJob job) {
    context.push('/taller/pegas/nueva?duplicate_from=${job.id}');
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
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 32),
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

  Future<void> _showBikeSelectorDialog(
      MechanicJob job, Customer? customer) async {
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
                        Icon(Icons.info_outline,
                            size: 48, color: Colors.grey[400]),
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
                        title: Text(
                          bike.displayName.isNotEmpty
                              ? bike.displayName
                              : 'Sin nombre',
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (bike.serialNumber != null)
                              Text('S/N: ${bike.serialNumber}'),
                            if (bike.color != null)
                              Text('Color: ${bike.color}'),
                          ],
                        ),
                        secondary:
                            bike.imageUrl != null && bike.imageUrl!.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: CachedNetworkImage(
                                      imageUrl: bike.imageUrl!,
                                      width: 60,
                                      height: 40,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(
                                        color: Colors.grey[200],
                                        child: const Center(
                                            child: CircularProgressIndicator()),
                                      ),
                                      errorWidget: (context, url, error) =>
                                          Container(
                                        color: Colors.grey[200],
                                        child: const Icon(Icons.pedal_bike,
                                            color: Colors.grey),
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
                                    child: const Icon(Icons.pedal_bike,
                                        color: Colors.grey),
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
                          final updatedJob =
                              job.copyWith(bikeId: selectedBikeId);
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
        content: Text(
            '¿Eliminar ${job.jobNumber}?\n\nEsta acción no se puede deshacer.'),
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
    context.push('/taller/pegas/nueva');
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

  Widget _buildStatusFilterDropdown() {
    final bool hasCustomSelection = _statusFilter.isNotEmpty;

    return PopupMenuButton<JobStatus?>(
      tooltip: 'Filtrar por estado',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      onSelected: (selection) {
        setState(() {
          if (selection == null) {
            _statusFilter.clear();
          } else {
            if (_statusFilter.isEmpty) {
              _statusFilter.add(selection);
            } else if (_statusFilter.contains(selection)) {
              _statusFilter.remove(selection);
            } else {
              _statusFilter.add(selection);
            }

            if (_statusFilter.length == JobStatus.values.length) {
              _statusFilter.clear();
            }
          }
        });

        _applyFiltersAndSort();
      },
      itemBuilder: (context) {
        final entries = <PopupMenuEntry<JobStatus?>>[
          PopupMenuItem<JobStatus?>(
            value: null,
            child: _buildStatusMenuRow(
              context,
              label: 'Todos',
              checked: _statusFilter.isEmpty,
              indicatorColor: null,
            ),
          ),
          const PopupMenuDivider(),
        ];

        for (final status in JobStatus.values) {
          final config = _getStatusConfig(status);
          final bool isChecked =
              _statusFilter.isEmpty || _statusFilter.contains(status);
          entries.add(
            PopupMenuItem<JobStatus?>(
              value: status,
              child: _buildStatusMenuRow(
                context,
                label: config['label'] as String,
                checked: isChecked,
                indicatorColor: config['indicatorColor'] as Color?,
              ),
            ),
          );
        }

        return entries;
      },
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: hasCustomSelection ? Colors.orange[400]! : Colors.grey[300]!,
          ),
          borderRadius: BorderRadius.circular(8),
          color: hasCustomSelection ? Colors.orange[50] : Colors.white,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.radio_button_checked,
              size: 16,
              color: hasCustomSelection ? Colors.orange[700] : Colors.grey[600],
            ),
            const SizedBox(width: 8),
            Text(
              'Estado',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color:
                    hasCustomSelection ? Colors.orange[700] : Colors.grey[700],
              ),
            ),
            if (hasCustomSelection) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange[400],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _statusFilter.length.toString(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 6),
            Icon(
              Icons.arrow_drop_down,
              size: 20,
              color: hasCustomSelection ? Colors.orange[700] : Colors.grey[500],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusMenuRow(
    BuildContext context, {
    required String label,
    required bool checked,
    Color? indicatorColor,
  }) {
    final Color activeColor =
        indicatorColor ?? Theme.of(context).colorScheme.primary;

    return SizedBox(
      width: _statusFilterMenuWidth,
      child: Row(
        children: [
          Icon(
            checked ? Icons.check_box : Icons.check_box_outline_blank,
            size: 18,
            color: checked ? activeColor : Colors.grey[500],
          ),
          const SizedBox(width: 8),
          if (indicatorColor != null) ...[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: indicatorColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
          ] else
            const SizedBox(width: 4),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
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
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(
              color: selectedValues.isEmpty
                  ? Colors.grey[300]!
                  : Colors.orange[400]!),
          borderRadius: BorderRadius.circular(8),
          color: selectedValues.isEmpty ? Colors.white : Colors.orange[50],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: selectedValues.isEmpty
                    ? Colors.grey[600]
                    : Colors.orange[700]),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: selectedValues.isEmpty
                    ? Colors.grey[700]
                    : Colors.orange[700],
                fontWeight: selectedValues.isEmpty
                    ? FontWeight.normal
                    : FontWeight.w600,
              ),
            ),
            if (selectedValues.isNotEmpty) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange[400],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${selectedValues.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 6),
            Icon(
              Icons.arrow_drop_down,
              size: 20,
              color: selectedValues.isEmpty
                  ? Colors.grey[500]
                  : Colors.orange[700],
            ),
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
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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

  Color _getStatusColorForJob(JobStatus status) {
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

  Widget _buildViewSwitcher({
    required IconData icon,
    required String label,
    required PegasViewMode mode,
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
    // Group jobs by status
    final Map<JobStatus, List<MechanicJob>> jobsByStatus = {};
    
    for (final job in _filteredJobs) {
      jobsByStatus.putIfAbsent(job.status, () => []).add(job);
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
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: statuses.map((status) {
          final jobs = jobsByStatus[status] ?? [];
          final statusConfig = _getStatusConfig(status);
          
          return Container(
            width: 300,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: statusConfig['color'],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          statusConfig['label'],
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: statusConfig['textColor'],
                          ),
                        ),
                      ),
                      Text(
                        '${jobs.length}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: statusConfig['textColor'],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: jobs.length,
                    itemBuilder: (context, index) {
                      final job = jobs[index];
                      final customer = _customers[job.customerId];
                      final bike = _bikes[job.bikeId];
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () {
                            context.push('/taller/pegas/${job.id}').then((_) => _loadData());
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        customer?.name ?? 'Cliente desconocido',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    _buildPriorityIndicator(job.priority),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Pega: ${job.jobNumber}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                  ),
                                ),
                                if (bike != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    '${bike.brand} ${bike.model}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                                if (job.totalCost > 0) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    NumberFormat.currency(locale: 'es_CL', symbol: '\$').format(job.totalCost),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
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

  Widget _buildPriorityIndicator(JobPriority priority) {
    final config = _getPriorityConfig(priority);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (config['color'] as Color).withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        config['label'],
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: config['color'],
        ),
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
              _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
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
                  _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
                });
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCalendarGrid() {
    final firstDayOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final lastDayOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    final daysInMonth = lastDayOfMonth.day;
    // Monday = 1, Sunday = 7 in DateTime.weekday
    // We want Monday = 0, so subtract 1
    final firstWeekday = firstDayOfMonth.weekday - 1;

    return Column(
      children: [
        // Weekday headers - Monday first
        Row(
          children: ['L', 'M', 'M', 'J', 'V', 'S', 'D']
              .map((day) => Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
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
            children: List.generate((daysInMonth + firstWeekday + 6) ~/ 7, (weekIndex) {
              return Expanded(
                child: Row(
                  children: List.generate(7, (dayIndex) {
                    final dayNumber = weekIndex * 7 + dayIndex - firstWeekday + 1;
                    if (dayNumber < 1 || dayNumber > daysInMonth) {
                      return const Expanded(child: SizedBox());
                    }

                    final date = DateTime(_focusedMonth.year, _focusedMonth.month, dayNumber);
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
                                ? Theme.of(context).primaryColor.withOpacity(0.1)
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
                                    fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                                    color: isSelected
                                        ? Theme.of(context).primaryColor
                                        : Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              // List customer names like Notion - CLICKABLE & SCROLLABLE
                              if (jobsOnDay.isNotEmpty)
                                Expanded(
                                  child: ListView.builder(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    itemCount: jobsOnDay.length,
                                    itemBuilder: (context, index) {
                                      final job = jobsOnDay[index];
                                      final customer = _customers[job.customerId];
                                      final customerName = customer?.name ?? 'Unknown';
                                      final statusColor = _getStatusColorForJob(job.status);
                                      
                                      return InkWell(
                                        onTap: () async {
                                          setState(() {
                                            _selectedDate = date;
                                            _selectedJob = job;
                                            _loadingDetails = true;
                                          });
                                          await _loadJobDetails(job);
                                        },
                                        borderRadius: BorderRadius.circular(4),
                                        child: Container(
                                          margin: const EdgeInsets.only(bottom: 2),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: statusColor.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            customerName,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: statusColor.withOpacity(0.9),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      );
                                    },
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
    return _filteredJobs.where((job) {
      // Use deadline as the scheduled date for calendar display
      if (job.deadline == null) return false;
      final jobDate = job.deadline!;
      return jobDate.year == date.year &&
          jobDate.month == date.month &&
          jobDate.day == date.day;
    }).toList();
  }

  Widget _buildSelectedDateJobs() {
    final jobsForDate = _getJobsForDate(_selectedDate);
    final dateFormat = DateFormat('EEEE, d MMMM yyyy', 'es');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (_selectedJob != null)
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _selectedJob = null;
                  });
                },
                tooltip: 'Volver a la lista',
              ),
            Expanded(
              child: Text(
                _selectedJob != null ? 'Detalles de la Pega' : dateFormat.format(_selectedDate),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_selectedJob != null)
          Expanded(child: _buildJobDetails(_selectedJob!))
        else if (jobsForDate.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.event_busy,
                    size: 64,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No hay pegas programadas',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.6),
                        ),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: jobsForDate.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final job = jobsForDate[index];
                return _buildJobCard(job);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildJobCard(MechanicJob job) {
    final customer = _customers[job.customerId];
    final bike = _bikes[job.bikeId];
    final statusColor = _getStatusColorForJob(job.status);
    final customerName = customer?.name ?? 'Cliente';
    final bikeName = bike != null ? '${bike.brand} ${bike.model}' : (job.jobNumber ?? 'Sin #');

    return Card(
      elevation: 2,
      child: InkWell(
        onTap: () async {
          setState(() {
            _selectedJob = job;
            _loadingDetails = true;
          });
          await _loadJobDetails(job);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      bikeName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.4),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                customerName,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.7),
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (job.clientRequest != null) ...[
                const SizedBox(height: 8),
                Text(
                  job.clientRequest!,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (job.deadline != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 14,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.6),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('HH:mm').format(job.deadline!),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.6),
                          ),
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

  Widget _buildJobDetails(MechanicJob job) {
    final statusColor = _getStatusColorForJob(job.status);
    final statusConfig = _getStatusConfig(job.status);
    final statusText = statusConfig['label'] as String;
    final customer = _customers[job.customerId];
    final bike = _bikes[job.bikeId];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Compact header with status and key info
          Row(
            children: [
              // Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor, width: 1.5),
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
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Bicycle Info (compact) - fallback to job number if no bike info
              Text(
                bike != null
                    ? '${bike.brand} ${bike.model}'
                    : job.jobNumber ?? 'Sin #',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Customer Name (prominent)
          if (customer != null) ...[
            Row(
              children: [
                Icon(
                  Icons.person,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    customer.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          
          // Bike Info (compact)
          if (bike != null) ...[
            Row(
              children: [
                Icon(
                  Icons.pedal_bike,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
                const SizedBox(width: 8),
                Text(
                  '${bike.brand} ${bike.model}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          
          // Deadline (compact and prominent) - EDITABLE
          if (job.deadline != null) ...[
            InkWell(
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: job.deadline!,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  locale: const Locale('es', 'CL'),
                );
                
                if (date != null && mounted) {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(job.deadline!),
                  );
                  
                  if (time != null && mounted) {
                    final newDeadline = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      time.hour,
                      time.minute,
                    );
                    
                    try {
                      final updatedJob = job.copyWith(deadline: newDeadline);
                      await _bikeshopService.updateJob(updatedJob);
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Fecha de entrega actualizada')),
                        );
                      }
                      
                      // Reload data to update calendar and detail view
                      await _loadData();
                      
                      // Reload job details
                      setState(() {
                        _selectedJob = updatedJob;
                        _loadingDetails = true;
                      });
                      await _loadJobDetails(updatedJob);
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error al actualizar: $e')),
                        );
                      }
                    }
                  }
                }
              },
              child: Row(
                children: [
                  Icon(
                    Icons.event,
                    size: 18,
                    color: Colors.red.shade700,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Entrega: ${DateFormat('dd/MM/yyyy HH:mm').format(job.deadline!)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.red.shade700,
                          decoration: TextDecoration.underline,
                        ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.edit,
                    size: 14,
                    color: Colors.red.shade700,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          
          // All Items Section (uniform treatment)
          if (_selectedJobItems.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.shopping_cart,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Repuestos y Servicios',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._selectedJobItems.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product image with hover zoom
                  if (item.productId != null && _productImages.containsKey(item.productId))
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _HoverImageWidget(
                        imageUrl: _productImages[item.productId]!,
                        size: 40,
                      ),
                    ),
                  Text(
                    '• ',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.productName,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                        Text(
                          'Cantidad: ${item.quantity.toStringAsFixed(0)} × \$${item.unitPrice.toStringAsFixed(0)} = \$${item.lineTotal.toStringAsFixed(0)}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.6),
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )),
          ],
          
          // Show loading indicator while loading details
          if (_loadingDetails) ...[
            const SizedBox(height: 12),
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            ),
          ],
          
          // Client Request, Diagnosis, Work Performed, Notes
          if (job.clientRequest != null || job.diagnosis != null || 
              job.workPerformed != null || (job.notes != null && job.notes!.isNotEmpty)) ...[
            const Divider(height: 24),
            
            if (job.clientRequest != null) ...[
              _buildDetailRow(
                icon: Icons.description,
                label: 'Solicitud',
                value: job.clientRequest!,
                isMultiline: true,
              ),
              const SizedBox(height: 12),
            ],
            
            if (job.diagnosis != null) ...[
              _buildDetailRow(
                icon: Icons.medical_services,
                label: 'Diagnóstico',
                value: job.diagnosis!,
                isMultiline: true,
              ),
              const SizedBox(height: 12),
            ],
            
            if (job.workPerformed != null) ...[
              _buildDetailRow(
                icon: Icons.build,
                label: 'Trabajo Realizado',
                value: job.workPerformed!,
                isMultiline: true,
              ),
              const SizedBox(height: 12),
            ],
            
            if (job.notes != null && job.notes!.isNotEmpty) ...[
              _buildDetailRow(
                icon: Icons.note,
                label: 'Notas',
                value: job.notes!,
                isMultiline: true,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    bool isMultiline = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.6),
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 24),
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: isMultiline ? null : 1,
            overflow: isMultiline ? null : TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _HoverImageWidget extends StatefulWidget {
  final String imageUrl;
  final double size;

  const _HoverImageWidget({
    required this.imageUrl,
    this.size = 40,
  });

  @override
  State<_HoverImageWidget> createState() => _HoverImageWidgetState();
}

class _HoverImageWidgetState extends State<_HoverImageWidget> {
  bool _isHovered = false;
  OverlayEntry? _overlayEntry;

  void _showZoomedImage(BuildContext context) {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: offset.dx + widget.size + 8,
        top: offset.dy - 75,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!, width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                widget.imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.grey[200],
                  child: const Icon(Icons.broken_image, size: 50),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideZoomedImage() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        _showZoomedImage(context);
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        _hideZoomedImage();
      },
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: _isHovered ? Theme.of(context).colorScheme.primary : Colors.grey[300]!,
            width: _isHovered ? 2 : 1,
          ),
          color: Colors.grey[100],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Image.network(
            widget.imageUrl,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Container(
              color: Colors.grey[200],
              child: const Icon(Icons.image, size: 20, color: Colors.grey),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _hideZoomedImage();
    super.dispose();
  }
}
