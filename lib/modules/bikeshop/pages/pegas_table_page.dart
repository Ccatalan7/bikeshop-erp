import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';

import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/hover_zoom_image.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../crm/models/crm_models.dart';
import '../../crm/services/customer_service.dart';
import '../../sales/models/sales_models.dart';
import '../../sales/services/sales_service.dart';

import '../../../shared/services/image_service.dart';
import '../services/bikeshop_service.dart';
import '../services/job_status_service.dart';
import '../models/bikeshop_models.dart';
import '../widgets/pega_detail_view.dart';
import '../widgets/pegas_calendar_widget.dart';
import '../widgets/deadline_cell.dart';
import '../widgets/smart_job_details_editor.dart';
import '../widgets/pegas_tasks_widget.dart';
import 'bike_form_dialog.dart';

/// Modern, professional Pegas management with advanced data table
class PegasTablePage extends StatefulWidget {
  const PegasTablePage({super.key});

  @override
  State<PegasTablePage> createState() => _PegasTablePageState();
}

class _PegasTablePageState extends State<PegasTablePage>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  static const String _debugTestCustomerName = 'Test Taller';

  // Keep this page alive to preserve state when navigating away
  @override
  bool get wantKeepAlive => true;

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration d) {
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }

  late BikeshopService _bikeshopService;
  late CustomerService _customerService;
  late DatabaseService _databaseService;
  late JobStatusService _jobStatusService;
  late SalesService _salesService;
  final TenantService _tenantService = TenantService();

  List<MechanicJob> _jobs = [];
  List<MechanicJob> _filteredJobs = [];
  Map<String, Customer> _customers = {};
  Map<String, Bike> _bikes = {};
  Map<String, Invoice> _invoices = {};
  Map<String, String> _productImages = {};
  Map<String, List<MechanicJobBike>> _jobBikesMap = {}; // Multi-bike support

  // Expanded rows (multi-bike display)
  final Set<String> _expandedJobIds = {};
  String? _draggingJobId; // To track which row is being dragged over

  bool _isLoading = true;
  bool _isCreatingDebugJob = false;
  bool _needsRefresh = false;
  Timer? _reloadDebounceTimer;
  String _searchTerm = '';

  // Track when we do local updates to suppress unnecessary reloads
  // Grace period must be > realtime latency (~100-500ms) + debounce time (500ms) + network jitter
  // Using 3000ms to be extra safe
  DateTime? _lastLocalUpdate;
  static const Duration _localUpdateGracePeriod = Duration(milliseconds: 3000);

  // Track number of active local operations (prevents reload while ANY operation is in progress)
  int _activeLocalOperations = 0;

  // Scroll controller for synchronized horizontal scrolling
  final ScrollController _horizontalScrollController = ScrollController();
  bool _isColumnResizing = false;
  double? _lockedHorizontalScrollOffset;

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
  final Set<String> _customStatusFilter =
      {}; // Uses status IDs (UUIDs) not legacy enum
  bool _statusFilterExcludeMode =
      false; // false = "is" (include), true = "is not" (exclude)
  final Set<JobPriority> _priorityFilter = {};
  bool _showOnlyOverdue = false;
  bool _showOnlyUnpaid = false;

  // Pagination
  int _currentPage = 0;
  int _rowsPerPage = 25;

  // Bulk selection
  final Set<String> _selectedJobIds = {};
  bool get _isAnySelected => _selectedJobIds.isNotEmpty;

  // Column visibility panel
  bool _showColumnPanel = false;

  // Column drag state for live preview
  String? _draggingColumnId;
  int? _dragTargetIndex;

  /// Get columns in display order (with live preview during drag)
  List<ColumnConfig> get _displayColumns {
    final visibleColumns = _columns.where((col) => col.visible).toList();
    if (_draggingColumnId != null && _dragTargetIndex != null) {
      final sourceIndex =
          visibleColumns.indexWhere((c) => c.id == _draggingColumnId);
      if (sourceIndex != -1 &&
          _dragTargetIndex! >= 0 &&
          _dragTargetIndex! < visibleColumns.length) {
        final reordered = List<ColumnConfig>.from(visibleColumns);
        final draggedColumn = reordered.removeAt(sourceIndex);
        final insertIndex = _dragTargetIndex!.clamp(0, reordered.length);
        reordered.insert(insertIndex, draggedColumn);
        return reordered;
      }
    }
    return visibleColumns;
  }

  // View mode: 'table', 'board', 'calendar', 'gantt'
  String _viewMode = 'table';

  // Timeline/Gantt state
  String _timelineScale = 'week'; // 'week' or 'month'
  DateTime _timelineViewStart =
      DateTime.now().subtract(const Duration(days: 7));

  // Calendar view state - moved to PegasCalendarWidget (shared widget)

  // MOBILE UI STATE
  bool _isSearchExpanded = false;
  JobStatus? _mobileStatusFilter; // Separate filter for mobile view

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _databaseService = Provider.of<DatabaseService>(context, listen: false);
    _bikeshopService = Provider.of<BikeshopService>(context, listen: false);
    _customerService = Provider.of<CustomerService>(context, listen: false);
    _jobStatusService = Provider.of<JobStatusService>(context, listen: false);
    _salesService = Provider.of<SalesService>(context, listen: false);

    // Listen to BikeshopService changes (realtime updates for jobs AND invoices)
    _bikeshopService.addListener(_onBikeshopServiceChanged);

    _initializeColumns();
    _loadColumnOrder(); // Load saved column order
    _loadListPaneWidth();
    _restoreTableState(); // Restore filters, pagination, sort from service
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadData();
    });
  }

  /// Restore table state from BikeshopService (persists across navigation)
  void _restoreTableState() {
    _currentPage = _bikeshopService.pegasCurrentPage;
    _rowsPerPage = _bikeshopService.pegasRowsPerPage;
    _sortColumn = _bikeshopService.pegasSortColumn;
    _sortAscending = _bikeshopService.pegasSortAscending;
    _statusFilter = _bikeshopService.pegasStatusFilter;
    _customStatusFilter.clear();
    _customStatusFilter.addAll(_bikeshopService.pegasCustomStatusFilter);
    _statusFilterExcludeMode = _bikeshopService.pegasStatusFilterExcludeMode;
    _priorityFilter.clear();
    _priorityFilter.addAll(_bikeshopService.pegasPriorityFilter.map((s) =>
        JobPriority.values
            .firstWhere((p) => p.name == s, orElse: () => JobPriority.normal)));
    _showOnlyOverdue = _bikeshopService.pegasShowOnlyOverdue;
    _showOnlyUnpaid = _bikeshopService.pegasShowOnlyUnpaid;
    _searchTerm = _bikeshopService.pegasSearchTerm;
    _viewMode = _bikeshopService.pegasViewMode;

    if (!kDebugMode && _statusFilter == 'test') {
      _statusFilter = 'active';
    }
  }

  List<ButtonSegment<String>> _buildStatusSegments({
    required bool compact,
  }) {
    final textStyle = compact ? null : const TextStyle(fontSize: 13);

    return [
      ButtonSegment(
        value: 'active',
        label: Text('Activos', style: textStyle),
      ),
      if (kDebugMode)
        ButtonSegment(
          value: 'test',
          label: Text('Tests', style: textStyle),
        ),
      ButtonSegment(
        value: 'completed',
        label: Text('Completados', style: textStyle),
      ),
      ButtonSegment(
        value: 'delivered',
        label: Text('Entregados', style: textStyle),
      ),
      ButtonSegment(
        value: 'warranty_completed',
        label: Text('Garantías', style: textStyle),
      ),
      ButtonSegment(
        value: 'unpaid',
        label: Text('Sin Pagar', style: textStyle),
      ),
      ButtonSegment(
        value: 'all',
        label: Text('Todos', style: textStyle),
      ),
    ];
  }

  /// Save table state to BikeshopService for persistence
  void _saveTableState() {
    _bikeshopService.pegasCurrentPage = _currentPage;
    _bikeshopService.pegasRowsPerPage = _rowsPerPage;
    _bikeshopService.pegasSortColumn = _sortColumn;
    _bikeshopService.pegasSortAscending = _sortAscending;
    _bikeshopService.pegasStatusFilter = _statusFilter;
    _bikeshopService.pegasCustomStatusFilter = Set.from(_customStatusFilter);
    _bikeshopService.pegasStatusFilterExcludeMode = _statusFilterExcludeMode;
    _bikeshopService.pegasPriorityFilter =
        _priorityFilter.map((p) => p.name).toSet();
    _bikeshopService.pegasShowOnlyOverdue = _showOnlyOverdue;
    _bikeshopService.pegasShowOnlyUnpaid = _showOnlyUnpaid;
    _bikeshopService.pegasSearchTerm = _searchTerm;
    _bikeshopService.pegasViewMode = _viewMode;
  }

  /// Called when BikeshopService notifies (e.g., realtime update from another client)
  /// Now uses SURGICAL UPDATE mode: the cache is already updated from realtime payload,
  /// so we just refresh the UI with cached data instead of doing a full database fetch.
  void _onBikeshopServiceChanged() {
    // Skip reload if we have active local operations in progress
    if (_activeLocalOperations > 0) {
      debugPrint(
          '🔇 [PegasTablePage] Skipping reload - $_activeLocalOperations active operation(s) in progress');
      return;
    }

    // Skip reload if we just did a local update (optimistic update already applied)
    if (_lastLocalUpdate != null) {
      final elapsed = DateTime.now().difference(_lastLocalUpdate!);
      if (elapsed < _localUpdateGracePeriod) {
        debugPrint(
            '🔇 [PegasTablePage] Skipping reload - local update ${elapsed.inMilliseconds}ms ago (grace: ${_localUpdateGracePeriod.inMilliseconds}ms)');
        return;
      }
    }

    // SURGICAL UPDATE MODE: Use cached data directly (already updated from realtime payload)
    // This avoids full database refetch and is much lighter weight
    if (_bikeshopService.hasJobsCache) {
      debugPrint(
          '🔧 [PegasTablePage] Surgical update: using cached data (no DB fetch)');
      _refreshFromCache();
      return;
    }

    // Fallback: Full reload only if cache is empty
    debugPrint('🔔 [PegasTablePage] Cache empty, doing full reload...');
    _loadData();
  }

  /// Refresh UI from cached data without database fetch
  void _refreshFromCache() {
    if (!mounted) return;

    MechanicJob? jobToRefresh;

    setState(() {
      _jobs = _bikeshopService.cachedJobs;
      if (_customerService.hasCustomersCache) {
        _customers = _buildCustomerMap(_customerService.cachedCustomers);
      }
      if (_bikeshopService.hasBikesCache) {
        _bikes = _buildBikeMap(_bikeshopService.cachedBikes);
      }
      if (_bikeshopService.hasJobBikesCache) {
        _jobBikesMap = _bikeshopService.cachedAllJobBikes;
      }
      if (_salesService.hasInvoicesCache) {
        _invoices = _buildInvoiceMap(_salesService.cachedInvoices);
      }

      // Update selected job if it exists in the new list (to get fresh totals/status)
      if (_selectedJob != null) {
        try {
          final freshJob = _jobs.firstWhere((j) => j.id == _selectedJob!.id);
          // Always update reference to get latest totals/status
          if (freshJob != _selectedJob) {
            _selectedJob = freshJob;
            jobToRefresh = freshJob;
          }
        } catch (_) {
          // Job no longer in cache - ignore
        }
      }
    });
    _applyFiltersAndSort();

    // If selected job was updated, we MUST refresh its items (details)
    // because invoice changes likely modified the items list too
    if (jobToRefresh != null) {
      _loadJobDetails(jobToRefresh!);
    }
  }

  /// Mark that we're starting a local operation (to suppress unnecessary reloads)
  void _startLocalOperation() {
    _activeLocalOperations++;
    _lastLocalUpdate = DateTime.now();
    debugPrint(
        '📌 [PegasTablePage] Started local operation #$_activeLocalOperations at $_lastLocalUpdate');
  }

  /// Mark that a local operation has completed
  void _endLocalOperation() {
    if (_activeLocalOperations > 0) {
      _activeLocalOperations--;
    }
    _lastLocalUpdate = DateTime.now();
    debugPrint(
        '📌 [PegasTablePage] Ended local operation, $_activeLocalOperations remaining');
  }

  /// Legacy method - calls _startLocalOperation for backward compatibility
  // ignore: unused_element
  void _markLocalUpdate() {
    _lastLocalUpdate = DateTime.now();
    debugPrint('📌 [PegasTablePage] Marked local update at $_lastLocalUpdate');
  }

  @override
  void dispose() {
    _bikeshopService.removeListener(_onBikeshopServiceChanged);
    _reloadDebounceTimer?.cancel();
    _horizontalScrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _initializeColumns() {
    _columns = [
      ColumnConfig(
        id: 'checkbox',
        label: '',
        width: 48,
        minWidth: 48,
        maxWidth: 48,
        visible: true,
        sortable: false,
        resizable: false,
        reorderable: false,
      ),
      ColumnConfig(
        id: 'status',
        label: '',
        width: 40,
        minWidth: 40,
        maxWidth: 40,
        visible: true,
        sortable: false,
        resizable: false,
        reorderable: false,
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
        id: 'kpi',
        label: 'Tiempos',
        width: 100,
        minWidth: 90,
        visible: true,
        sortable: false,
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
        id: 'diagnosis',
        label: 'Detalles',
        width: 280,
        minWidth: 180,
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
        id: 'attachments',
        label: 'Adjuntos',
        width: 60,
        minWidth: 50,
        maxWidth: 70,
        visible: true,
        sortable: false,
        resizable: false,
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
    // Check if we just became the current route
    final route = ModalRoute.of(context);
    if (route?.isCurrent == true) {
      // Check if data was modified (signaled by pop result)
      route?.popped.then((result) {
        if (result == true && mounted) {
          debugPrint('🔄 Data changed signal received, reloading pegas...');
          _loadData();
        }
      });

      // Also handle the old refresh flag
      if (_needsRefresh) {
        _needsRefresh = false;
        _loadData();
      }
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

  Map<String, Customer> _buildCustomerMap(List<Customer> customers) {
    final customerMap = <String, Customer>{};
    for (final customer in customers) {
      final customerId = customer.id;
      if (customerId != null) {
        customerMap[customerId] = customer;
      }
    }
    return customerMap;
  }

  Map<String, Bike> _buildBikeMap(List<Bike> bikes) {
    final bikeMap = <String, Bike>{};
    for (final bike in bikes) {
      final bikeId = bike.id;
      if (bikeId != null) {
        bikeMap[bikeId] = bike;
      }
    }
    return bikeMap;
  }

  Map<String, Invoice> _buildInvoiceMap(List<Invoice> invoices) {
    final invoiceMap = <String, Invoice>{};
    for (final invoice in invoices) {
      final invoiceId = invoice.id;
      if (invoiceId != null) {
        invoiceMap[invoiceId] = invoice;
      }
    }
    return invoiceMap;
  }

  bool _isJobInvoicedEffective(MechanicJob job) {
    return job.invoiceId != null || job.isInvoiced;
  }

  bool _isJobPaidEffective(MechanicJob job, {Invoice? invoice}) {
    final resolvedInvoice =
        invoice ?? (job.invoiceId != null ? _invoices[job.invoiceId] : null);
    if (resolvedInvoice != null) {
      return resolvedInvoice.status == InvoiceStatus.paid;
    }
    return job.isPaid;
  }

  bool get _canUseFreshInstantCache =>
      _bikeshopService.isJobsCacheFresh &&
      _customerService.isCustomersCacheFresh &&
      _bikeshopService.isBikesCacheFresh &&
      _bikeshopService.isJobBikesCacheFresh &&
      _salesService.isInvoicesCacheFresh;

  Future<void> _loadData() async {
    // Only instant-render when all companion caches are still fresh.
    // Rendering from an expired jobs cache causes the stale first frame the user sees
    // before the full fetch corrects customer/bike names and row membership.
    if (_canUseFreshInstantCache && _jobs.isEmpty) {
      setState(() {
        _jobs = _bikeshopService.cachedJobs;
        _filteredJobs = _jobs;
        _customers = _buildCustomerMap(_customerService.cachedCustomers);
        _bikes = _buildBikeMap(_bikeshopService.cachedBikes);
        _jobBikesMap = _bikeshopService.cachedAllJobBikes;
        _invoices = _buildInvoiceMap(_salesService.cachedInvoices);
        _isLoading = false;
      });
      _applyFiltersAndSort();
    } else if (_jobs.isEmpty) {
      setState(() => _isLoading = true);
    }

    try {
      final results = await Future.wait([
        _bikeshopService.getJobs(includeCompleted: true),
        _customerService.getCustomers(),
        _bikeshopService.getBikes(),
        _loadInvoices(),
        _bikeshopService.getAllJobBikes(), // Single query for all job bikes
      ]);

      final jobs = results[0] as List<MechanicJob>;
      final customers = results[1] as List<Customer>;
      final bikes = results[2] as List<Bike>;
      final invoices = results[3] as List<Invoice>;
      final jobBikesMap = results[4] as Map<String, List<MechanicJobBike>>;

      final customerMap = _buildCustomerMap(customers);
      final bikeMap = _buildBikeMap(bikes);

      final invoiceMap = _buildInvoiceMap(invoices);

      if (mounted) {
        setState(() {
          _jobs = jobs;
          _filteredJobs = jobs;
          _customers = customerMap;
          _bikes = bikeMap;
          _invoices = invoiceMap;
          _jobBikesMap = jobBikesMap;
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
      await _salesService.loadInvoices();
      return _salesService.cachedInvoices.toList();
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

  Future<void> _loadColumnOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedOrder = prefs.getStringList('pegas_column_order_v2');
      final savedWidths = prefs.getStringList('pegas_column_widths_v2');
      var appliedSavedWidths = false;

      if (savedWidths != null && savedWidths.isNotEmpty) {
        final widthsById = <String, double>{};
        for (final entry in savedWidths) {
          final separatorIndex = entry.lastIndexOf(':');
          if (separatorIndex <= 0) continue;
          final columnId = entry.substring(0, separatorIndex);
          final width = double.tryParse(entry.substring(separatorIndex + 1));
          if (width != null) widthsById[columnId] = width;
        }

        for (final col in _columns) {
          final width = widthsById[col.id];
          if (width == null || !col.resizable) continue;
          col.width = width.clamp(col.minWidth, col.maxWidth ?? 500).toDouble();
          appliedSavedWidths = true;
        }
      }

      if (savedOrder != null && savedOrder.isNotEmpty && mounted) {
        setState(() {
          // Create a map of current columns by ID for quick lookup
          final columnMap = <String, ColumnConfig>{};
          for (final col in _columns) {
            columnMap[col.id] = col;
          }

          // Rebuild columns list in saved order
          final reorderedColumns = <ColumnConfig>[];
          for (final id in savedOrder) {
            if (columnMap.containsKey(id)) {
              reorderedColumns.add(columnMap[id]!);
              columnMap.remove(id);
            }
          }

          // Add any new columns that weren't in the saved order (at the end)
          reorderedColumns.addAll(columnMap.values);

          _columns = reorderedColumns;
        });
      } else if (appliedSavedWidths && mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error loading column order: $e');
    }
  }

  Future<void> _saveColumnOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final columnIds = _columns.map((col) => col.id).toList();
      await prefs.setStringList('pegas_column_order_v2', columnIds);
    } catch (e) {
      debugPrint('Error saving column order: $e');
    }
  }

  Future<void> _saveColumnWidths() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final columnWidths = _columns
          .where((col) => col.resizable)
          .map((col) => '${col.id}:${col.width.toStringAsFixed(1)}')
          .toList();
      await prefs.setStringList('pegas_column_widths_v2', columnWidths);
    } catch (e) {
      debugPrint('Error saving column widths: $e');
    }
  }

  void _applyFiltersAndSort() {
    final hasCustomStatusFilter = _customStatusFilter.isNotEmpty;

    var filtered = _jobs.where((job) {
      final invoice = job.invoiceId != null ? _invoices[job.invoiceId] : null;
      final isMarkedAsTest = _jobMatchesTestFilter(job);
      final isInvoicedEffective = _isJobInvoicedEffective(job);
      final isPaidEffective = _isJobPaidEffective(job, invoice: invoice);

      final isDelivered = job.deliveredAt != null ||
          job.status == JobStatus.entregado ||
          (job.customStatus?.code.toLowerCase() == 'entregado');

      // Warranty is archived immediately if Delivered + $0, OR if Delivered + Paid
      final isFinishedWarranty = job.isWarrantyJob &&
          isDelivered &&
          (job.totalCost <= 0 || (isInvoicedEffective && isPaidEffective));

      // Get the job's phase from custom status, or infer from legacy status
      final jobPhase =
          job.customStatus?.phase ?? _inferPhaseFromLegacyStatus(job.status);

      if (_statusFilter == 'test') {
        if (!isMarkedAsTest) return false;
      } else if (isMarkedAsTest) {
        return false;
      }

      // Smart filter (Activos, Completados, etc.) - uses phase
      switch (_statusFilter) {
        case 'active':
          // Activos: include Terminados/Finalizados.
          // Filter out only: Cancelados, and Entregados that are already paid.
          if (job.status == JobStatus.cancelado) return false;

          final isDelivered = job.deliveredAt != null ||
              job.status == JobStatus.entregado ||
              (job.customStatus?.code.toLowerCase() == 'entregado');

          if (isDelivered && isInvoicedEffective && isPaidEffective) {
            return false;
          }

          // Also exclude finished warranties from active list
          if (isFinishedWarranty) return false;
          break;
        case 'warranty_completed':
          if (!isFinishedWarranty) return false;
          break;
        case 'completed':
          // Completed = only complete phase with finalizado status
          if (jobPhase != StatusPhase.complete ||
              job.status == JobStatus.entregado ||
              job.status == JobStatus.cancelado) {
            return false;
          }
          break;
        case 'delivered':
          if (job.status != JobStatus.entregado) return false;
          break;
        case 'unpaid':
          if (isPaidEffective || !isInvoicedEffective) return false;
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

      // Custom status filter - now uses status IDs
      // Supports both "is" (include) and "is not" (exclude) modes
      if (hasCustomStatusFilter) {
        final jobStatusId = job.statusId;
        final isInFilter =
            jobStatusId != null && _customStatusFilter.contains(jobStatusId);

        if (_statusFilterExcludeMode) {
          // Exclude mode: hide jobs that ARE in the filter
          if (isInFilter) return false;
        } else {
          // Include mode: only show jobs that ARE in the filter
          if (!isInFilter) return false;
        }
      }

      // Priority filter
      if (_priorityFilter.isNotEmpty &&
          !_priorityFilter.contains(job.priority)) {
        return false;
      }

      // Overdue filter
      if (_showOnlyOverdue && !job.isOverdue) return false;

      // Unpaid filter
      if (_showOnlyUnpaid && (isPaidEffective || !isInvoicedEffective)) {
        return false;
      }

      // MOBILE EXCLUSIVE FILTER
      if (_mobileStatusFilter != null) {
        // Only apply if we are actually in mobile view logic?
        // Ideally we reset this or ignore it on desktop, but for now simple check:
        // Or checking `MediaQuery` here is dirty, better to just apply if set.
        if (job.status != _mobileStatusFilter) return false;
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
          case 'diagnosis':
            comparison = (a.diagnosis ?? '').compareTo(b.diagnosis ?? '');
            break;
          case 'arrival_date':
            comparison = a.arrivalDate.compareTo(b.arrivalDate);
            break;
          case 'deadline':
            comparison = (a.deliveryDeadline ?? DateTime(2100))
                .compareTo(b.deliveryDeadline ?? DateTime(2100));
            break;
          case 'total':
            comparison = a.totalCost.compareTo(b.totalCost);
            break;
        }

        return _sortAscending ? comparison : -comparison;
      });
    }

    setState(() => _filteredJobs = filtered);

    // Validate current page (in case filtered results changed)
    final maxPage = (filtered.length / _rowsPerPage).ceil() - 1;
    if (_currentPage > maxPage.clamp(0, 999999)) {
      _currentPage = maxPage.clamp(0, 999999);
    }

    // Persist state for navigation
    _saveTableState();
  }

  bool _jobMatchesTestFilter(MechanicJob job) {
    final customer = _customers[job.customerId];
    final bike = _bikes[job.bikeId];

    final customerName = customer?.name.trim().toLowerCase() ?? '';
    if (customerName == 'test' || customerName.startsWith('test ')) {
      return true;
    }

    final bikeName = bike?.displayName.trim().toLowerCase() ?? '';
    if (bikeName == 'test' || bikeName.startsWith('test ')) {
      return true;
    }

    final auditText = [
      job.jobNumber,
      job.clientRequest,
      job.diagnosis,
      job.workPerformed,
      job.notes,
      bike?.brand,
      bike?.model,
      bike?.serialNumber,
    ].whereType<String>().join(' ').toLowerCase();

    return auditText.contains('[test') ||
        auditText.contains('test perfil') ||
        auditText.contains('test data') ||
        auditText.contains('sandbox') ||
        auditText.contains('dummy');
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
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    // FORCE mobile on Android/iOS app to avoid desktop layout on high-res phones/tablets
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 1100 ||
        (!kIsWeb && (Platform.isAndroid || Platform.isIOS));

    return MainLayout(
      title: isMobile
          ? ''
          : 'Vinabike ERP', // Hide title on mobile to use compact header
      child: isMobile
          ? _buildMobileLayout()
          : _isLoading
              ? const Center(child: BrandedLoading())
              : _selectedJob != null
                  ? _buildSplitView()
                  : Column(
                      children: [
                        _buildModernHeader(),
                        _buildToolbar(),
                        if (_showColumnPanel) _buildColumnVisibilityPanel(),
                        Expanded(child: _buildViewContent()),
                      ],
                    ),
    );
  }

  // ============================================================
  // MOBILE LAYOUT IMPLEMENTATION
  // ============================================================
  Widget _buildMobileLayout() {
    final theme = Theme.of(context);

    // If viewing job details, show full-screen detail view
    if (_selectedJob != null) {
      return PegaDetailView(
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
          final result =
              await context.push('/taller/pegas/${_selectedJob!.id}');
          if (!mounted) return;
          if (result == true) {
            await _loadData();
            if (_selectedJob != null) {
              await _loadJobDetails(_selectedJob!);
            }
          }
        },
        onStatusChange: (newStatus) async {
          _updateJobStatus(newStatus);
        },
        onItemRemoved: (itemId) async {
          // logic to remove item
          try {
            await _bikeshopService.deleteJobItem(itemId);
            if (_selectedJob != null) {
              await _loadJobDetails(_selectedJob!);
            }
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Producto o servicio eliminado')),
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
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          _buildMobileHeader(theme),
          _buildMobileFilterTabs(theme),
          Expanded(
            child: _isLoading
                ? const Center(child: BrandedLoading())
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: _buildMobileJobsList(),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context
            .push('/taller/pegas/nueva')
            .then((_) => _loadData()), // Note: Route is /nueva in Router
        backgroundColor: theme.colorScheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildMobileHeader(ThemeData theme) {
    // Basic stats for header
    final urgentCount =
        _jobs.where((j) => j.priority == JobPriority.urgente).length;
    final overdueCount = _jobs.where((j) => j.isOverdue && j.isActive).length;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          // Title with count badge
          Expanded(
            child: Row(
              children: [
                Text(
                  'Trabajos',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_filteredJobs.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                // Urgent/Overdue indicator
                if (urgentCount > 0 || overdueCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_amber,
                            size: 12, color: Colors.red[700]),
                        const SizedBox(width: 2),
                        Text(
                          '${overdueCount > 0 ? overdueCount : urgentCount}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.red[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Search button (expandable)
          IconButton(
            icon: Icon(_isSearchExpanded ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearchExpanded = !_isSearchExpanded;
                if (!_isSearchExpanded) {
                  _searchTerm = '';
                  _applyFiltersAndSort();
                }
              });
            },
          ),

          // More options menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'calendar':
                  context.push('/taller/calendario');
                  break;
                case 'refresh':
                  _loadData();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'calendar',
                child: Row(
                  children: [
                    Icon(Icons.calendar_month, size: 20),
                    SizedBox(width: 12),
                    Text('Ver Calendario'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh, size: 20),
                    SizedBox(width: 12),
                    Text('Actualizar'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMobileFilterTabs(ThemeData theme) {
    return Column(
      children: [
        // Expandable search bar
        if (_isSearchExpanded)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: theme.cardColor,
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Buscar trabajo, cliente, bicicleta...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchTerm.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          setState(() {
                            _searchTerm = '';
                            _applyFiltersAndSort();
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.brightness == Brightness.dark
                    ? Colors.grey[800]
                    : Colors.grey[100],
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                isDense: true,
              ),
              onChanged: (val) {
                setState(() => _searchTerm = val);
                _applyFiltersAndSort();
              },
            ),
          ),

        // Filter tabs row
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: theme.cardColor,
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              // Scrollable status filters
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      _buildMobileFilterChip('Todos', null),
                      _buildMobileFilterChip('Pendiente', JobStatus.pendiente),
                      _buildMobileFilterChip(
                          'Diagnóstico', JobStatus.diagnostico),
                      _buildMobileFilterChip('En Curso', JobStatus.enCurso),
                      _buildMobileFilterChip(
                          'Esperando', JobStatus.esperandoRepuestos),
                      _buildMobileFilterChip('Listo', JobStatus.finalizado),
                      _buildMobileFilterChip('Entregado', JobStatus.entregado),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileFilterChip(String label, JobStatus? status) {
    // If status is null, it means 'All' - check if _mobileStatusFilter is null
    final isSelected = _mobileStatusFilter == status;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _mobileStatusFilter = status;
            // IMPORTANT: Clear other filters to avoid conflict?
            // Or keep them consistent. For mobile simplicity, assume this overrides others.
            _applyFiltersAndSort();
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? theme.colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color:
                  isSelected ? theme.colorScheme.primary : theme.dividerColor,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color:
                  isSelected ? Colors.white : theme.textTheme.bodyMedium?.color,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileJobsList() {
    if (_filteredJobs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.build_circle_outlined,
                size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _searchTerm.isEmpty ? 'No hay trabajos' : 'Sin resultados',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 80), // Space for FAB
      itemCount: _filteredJobs.length,
      itemBuilder: (context, index) =>
          _buildMobileJobCard(_filteredJobs[index]),
    );
  }

  // Reuse existing _buildMobileJobCard but ensure it matches the new design
  // (The one in PegasTablePage might be simple card, check lines 1564.
  //  Actually I see it at 1564 in "View File" output, it looks basic.
  //  Let's overwrite it with the "better" card from PegasListPage if needed.
  //  Lines 1564-1599+ show it has selection logic but maybe not the nice badges.
  //  I will leave it for now and verify visual later or let user feedback guide.
  //  Actually, the user liked the "PegasListPage" mobile card. I should probably replace
  //  _buildMobileJobCard in PegasTablePage with the code from PegasListPage.
  //  See separate chunk below.)

  Future<void> _updateJobStatus(JobStatus newStatus) async {
    _startLocalOperation();
    setState(() {
      final index = _jobs.indexWhere((j) => j.id == _selectedJob!.id);
      if (index != -1) {
        final job = _jobs[index];
        _jobs[index] =
            job.copyWith(status: newStatus, updatedAt: DateTime.now());
        _selectedJob = _jobs[index];
      }
      _applyFiltersAndSort();
    });

    try {
      final updatedJob = _selectedJob!.copyWith(status: newStatus);
      await _databaseService.update(
        'mechanic_jobs',
        updatedJob.id!,
        updatedJob.toJson(),
      );
      if (mounted) {
        await _loadJobDetails(_selectedJob!);
      }
    } catch (e) {
      if (mounted) {
        await _loadData();
        if (_selectedJob != null) {
          await _loadJobDetails(_selectedJob!);
        }
      }
    } finally {
      _endLocalOperation();
    }
  }

  Widget _buildSplitView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        if (availableWidth < 800) {
          // Mobile: Show Detail View ONLY (full screen)
          // The list view is handled by the main build method when _selectedJob is null
          return PegaDetailView(
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
              final result =
                  await context.push('/taller/pegas/${_selectedJob!.id}');
              if (!mounted) return;
              if (result == true) {
                await _loadData();
                if (_selectedJob != null) {
                  await _loadJobDetails(_selectedJob!);
                }
              }
            },
            onStatusChange: (newStatus) async {
              // Same logic as desktop...
              _startLocalOperation();
              setState(() {
                final index = _jobs.indexWhere((j) => j.id == _selectedJob!.id);
                if (index != -1) {
                  // ... update job logic
                  final job = _jobs[index];
                  _jobs[index] = job.copyWith(
                      status: newStatus, updatedAt: DateTime.now());
                  _selectedJob = _jobs[index];
                }
                _applyFiltersAndSort();
              });

              try {
                final updatedJob = _selectedJob!.copyWith(status: newStatus);
                await _databaseService.update(
                  'mechanic_jobs',
                  updatedJob.id!,
                  updatedJob.toJson(),
                );
                if (mounted) {
                  await _loadJobDetails(_selectedJob!);
                }
              } catch (e) {
                if (mounted) {
                  await _loadData();
                  if (_selectedJob != null) {
                    await _loadJobDetails(_selectedJob!);
                  }
                }
              } finally {
                _endLocalOperation();
              }
            },
            onItemRemoved: (itemId) async {
              // Same logic...
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
          );
        }

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
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      // Close the detail view when clicking on the table area
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
                          _buildModernHeader(),
                          _buildToolbar(),
                          Expanded(child: _buildViewContent()),
                        ],
                      ),
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
                  final result =
                      await context.push('/taller/pegas/${_selectedJob!.id}');
                  if (!mounted) return;
                  // If job was updated (result == true), refresh the list
                  if (result == true) {
                    await _loadData(); // Full reload after edit is acceptable
                    if (_selectedJob != null) {
                      await _loadJobDetails(_selectedJob!);
                    }
                  }
                },
                onStatusChange: (newStatus) async {
                  // Start local operation to suppress reload from service notification
                  _startLocalOperation();

                  // Optimistic update
                  setState(() {
                    final index =
                        _jobs.indexWhere((j) => j.id == _selectedJob!.id);
                    if (index != -1) {
                      final job = _jobs[index];
                      _jobs[index] = MechanicJob(
                        id: job.id,
                        tenantId: job.tenantId,
                        jobNumber: job.jobNumber,
                        customerId: job.customerId,
                        bikeId: job.bikeId,
                        status: newStatus,
                        priority: job.priority,
                        arrivalDate: job.arrivalDate,
                        diagnosticDeadline: job.diagnosticDeadline,
                        deliveryDeadline: job.deliveryDeadline,
                        diagnosticSentAt: job.diagnosticSentAt,
                        startedAt: job.startedAt,
                        completedAt: job.completedAt,
                        deliveredAt: job.deliveredAt,
                        clientRequest: job.clientRequest,
                        diagnosis: job.diagnosis,
                        workPerformed: job.workPerformed,
                        notes: job.notes,
                        assignedTo: job.assignedTo,
                        assignedTechnicianName: job.assignedTechnicianName,
                        servicePackageId: job.servicePackageId,
                        estimatedCost: job.estimatedCost,
                        finalCost: job.finalCost,
                        partsCost: job.partsCost,
                        laborCost: job.laborCost,
                        discountAmount: job.discountAmount,
                        taxAmount: job.taxAmount,
                        totalCost: job.totalCost,
                        taxTreatment: job.taxTreatment,
                        invoiceId: job.invoiceId,
                        isInvoiced: job.isInvoiced,
                        isPaid: job.isPaid,
                        isWarrantyJob: job.isWarrantyJob,
                        warrantyNotes: job.warrantyNotes,
                        requiresApproval: job.requiresApproval,
                        approvedByCustomer: job.approvedByCustomer,
                        approvedAt: job.approvedAt,
                        imageUrls: job.imageUrls,
                        createdAt: job.createdAt,
                        updatedAt: DateTime.now(),
                        deletedAt: job.deletedAt,
                        deletedBy: job.deletedBy,
                      );
                      _selectedJob = _jobs[index];
                    }
                    _applyFiltersAndSort();
                  });

                  // Save in background
                  try {
                    final updatedJob =
                        _selectedJob!.copyWith(status: newStatus);
                    await _databaseService.update(
                      'mechanic_jobs',
                      updatedJob.id!,
                      updatedJob.toJson(),
                    );
                    if (mounted) {
                      await _loadJobDetails(_selectedJob!);
                    }
                  } catch (e) {
                    // Revert on error
                    if (mounted) {
                      await _loadData();
                      if (_selectedJob != null) {
                        await _loadJobDetails(_selectedJob!);
                      }
                    }
                  } finally {
                    _endLocalOperation();
                  }
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
    final isMobile = MediaQuery.of(context).size.width < 600;

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
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _isAnySelected
                        ? '${_selectedJobIds.length} seleccionado${_selectedJobIds.length != 1 ? 's' : ''}'
                        : 'Gestión de Trabajos',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.5,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_filteredJobs.length} trabajo${_filteredJobs.length != 1 ? 's' : ''}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Bulk action buttons (shown when items selected)
          if (_isAnySelected) ...[
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _selectedJobIds.clear()),
              tooltip: 'Deseleccionar todo',
            ),
            const SizedBox(width: 8),
            if (!isMobile) ...[
              FilledButton.tonalIcon(
                onPressed: _exportSelectedToCSV,
                icon: const Icon(Icons.file_download, size: 20),
                label: const Text('Exportar'),
              ),
              const SizedBox(width: 8),
            ],
            FilledButton.icon(
              onPressed: _bulkUpdateStatus,
              icon: const Icon(Icons.edit, size: 20),
              label: Text(isMobile ? 'Estado' : 'Cambiar Estado'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
            ),
          ] else ...[
            // Regular action buttons
            if (!isMobile) ...[
              IconButton(
                icon: Icon(_showColumnPanel
                    ? Icons.view_column
                    : Icons.view_column_outlined),
                onPressed: () =>
                    setState(() => _showColumnPanel = !_showColumnPanel),
                tooltip: 'Columnas',
                isSelected: _showColumnPanel,
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.file_download),
                onPressed: _exportAllToCSV,
                tooltip: 'Exportar Todo',
              ),
              const SizedBox(width: 8),
            ],
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadData,
              tooltip: 'Actualizar',
            ),
            const SizedBox(width: 8),
            if (kDebugMode) ...[
              _buildDebugQuickJobButton(isMobile: isMobile),
              const SizedBox(width: 8),
            ],
            if (isMobile)
              FilledButton(
                onPressed: () {
                  _markNeedsRefresh();
                  context.push('/taller/pegas/nueva');
                },
                child: const Icon(Icons.add, size: 20),
              )
            else
              _buildNewJobDropdown(),
          ],
        ],
      ),
    );
  }

  Widget _buildNewJobDropdown() {
    return MenuAnchor(
      builder: (context, controller, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.tonalIcon(
              onPressed: () {
                _markNeedsRefresh();
                context.push('/taller/pegas/nueva');
              },
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Nuevo Trabajo'),
              style: FilledButton.styleFrom(
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(8),
                    bottomLeft: Radius.circular(8),
                  ),
                ),
              ),
            ),
            FilledButton.tonal(
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              style: FilledButton.styleFrom(
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(32, 40),
              ),
              child: const Icon(Icons.arrow_drop_down, size: 20),
            ),
          ],
        );
      },
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.build, size: 18),
          child: const Text('Servicio normal'),
          onPressed: () {
            _markNeedsRefresh();
            context.push('/taller/pegas/nueva?type=service');
          },
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.verified_user, size: 18),
          child: const Text('Garantía'),
          onPressed: () {
            _markNeedsRefresh();
            context.push('/taller/pegas/nueva?type=warranty');
          },
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.request_quote, size: 18),
          child: const Text('Presupuesto'),
          onPressed: () {
            _markNeedsRefresh();
            context.push('/taller/pegas/nueva?type=quotation');
          },
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.build_circle, size: 18),
          child: const Text('Ítem / Accesorio'),
          onPressed: () {
            _markNeedsRefresh();
            context.push('/taller/pegas/nueva?type=item_service');
          },
        ),
      ],
    );
  }

  Widget _buildDebugQuickJobButton({required bool isMobile}) {
    final icon = _isCreatingDebugJob
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.science_outlined, size: 20);

    if (isMobile) {
      return IconButton(
        onPressed: _isCreatingDebugJob ? null : _launchDebugQuickJobBuilder,
        tooltip: 'Crear caso de prueba',
        icon: icon,
      );
    }

    return FilledButton.tonalIcon(
      onPressed: _isCreatingDebugJob ? null : _launchDebugQuickJobBuilder,
      icon: icon,
      label: const Text('Prueba rápida'),
    );
  }

  Future<void> _launchDebugQuickJobBuilder() async {
    final request = await _showDebugQuickJobDialog();
    if (request == null || _isCreatingDebugJob) return;

    setState(() => _isCreatingDebugJob = true);

    try {
      final createdJob = await _createDebugQuickJob(request);
      if (!mounted) return;

      setState(() => _statusFilter = 'test');
      _saveTableState();
      _markNeedsRefresh();

      if (createdJob.id != null && createdJob.id!.isNotEmpty) {
        await context.push('/taller/pegas/${createdJob.id}');
      }

      if (!mounted) return;
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo crear el caso de prueba: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isCreatingDebugJob = false);
      }
    }
  }

  Future<_DebugTestJobRequest?> _showDebugQuickJobDialog() {
    var selectedScenario = _debugBikeScenarios.first;
    var selectedStage = _DebugJobLifecycleStage.diagnostic;

    return showDialog<_DebugTestJobRequest>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final fixtureModeText = selectedScenario.reuseBike
                ? 'Reutiliza la bicicleta fixture y vuelve a sembrar la ficha tecnica del escenario.'
                : 'Crea una bicicleta nueva para garantizar un caso sin ficha previa.';

            return AlertDialog(
              title: const Text('Crear caso de prueba'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Genera un trabajo debug con cliente, bici y estado inicial listos para probar sin pasar por el flujo normal.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<_DebugBikeScenario>(
                      initialValue: selectedScenario,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Escenario',
                        border: OutlineInputBorder(),
                      ),
                      items: _debugBikeScenarios
                          .map(
                            (scenario) => DropdownMenuItem<_DebugBikeScenario>(
                              value: scenario,
                              child: Text(scenario.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => selectedScenario = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<_DebugJobLifecycleStage>(
                      initialValue: selectedStage,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Estado inicial del trabajo',
                        border: OutlineInputBorder(),
                      ),
                      items: _DebugJobLifecycleStage.values
                          .map(
                            (stage) =>
                                DropdownMenuItem<_DebugJobLifecycleStage>(
                              value: stage,
                              child: Text(stage.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => selectedStage = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedScenario.description,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            fixtureModeText,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            selectedStage.supportText,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    _DebugTestJobRequest(
                      scenario: selectedScenario,
                      stage: selectedStage,
                    ),
                  ),
                  icon: const Icon(Icons.bolt, size: 18),
                  label: const Text('Crear'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<MechanicJob> _createDebugQuickJob(_DebugTestJobRequest request) async {
    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null || tenantId.isEmpty) {
      throw Exception('No se pudo resolver el tenant actual');
    }

    final customer = await _ensureDebugTestCustomer(tenantId);
    final customerId = customer.id;
    if (customerId == null || customerId.isEmpty) {
      throw Exception('No se pudo crear el cliente de prueba');
    }

    final bike = await _ensureDebugScenarioBike(
      tenantId: tenantId,
      customerId: customerId,
      scenario: request.scenario,
    );
    final bikeId = bike.id;
    if (bikeId == null || bikeId.isEmpty) {
      throw Exception('No se pudo preparar la bicicleta de prueba');
    }

    if (request.scenario.technicalValues.isNotEmpty) {
      await _ensureDebugBikeProfile(
        tenantId: tenantId,
        bike: bike,
        scenario: request.scenario,
      );
    }

    final now = DateTime.now();
    final timing = _debugTimingForStage(request.stage, now);
    final debugTag =
        '[test scenario:${request.scenario.id}][stage:${request.stage.id}]';

    final job = MechanicJob(
      tenantId: tenantId,
      customerId: customerId,
      bikeId: bikeId,
      jobType: JobType.service,
      arrivalDate: timing.arrivalDate,
      diagnosticDeadline: timing.diagnosticDeadline,
      deliveryDeadline: timing.deliveryDeadline,
      startedAt: timing.startedAt,
      completedAt: timing.completedAt,
      deliveredAt: timing.deliveredAt,
      status: request.stage.status,
      priority: JobPriority.normal,
      clientRequest: request.scenario.clientRequest,
      diagnosis:
          request.stage.includesDiagnosis ? request.scenario.diagnosis : null,
      workPerformed: request.stage.includesWorkPerformed
          ? request.scenario.workPerformed
          : null,
      notes: '$debugTag ${request.scenario.description}',
    );

    final createdJob = await _bikeshopService.createJob(job);
    final createdJobId = createdJob.id;
    if (createdJobId == null || createdJobId.isEmpty) {
      throw Exception('No se pudo persistir el trabajo de prueba');
    }

    await _bikeshopService.addBikeToJob(
      MechanicJobBike(
        tenantId: tenantId,
        jobId: createdJobId,
        bikeId: bikeId,
        workRequested: request.scenario.clientRequest,
        diagnosis:
            request.stage.includesDiagnosis ? request.scenario.diagnosis : null,
        workPerformed: request.stage.includesWorkPerformed
            ? request.scenario.workPerformed
            : null,
        technicianNotes: '$debugTag ${request.scenario.description}',
      ),
    );

    return createdJob;
  }

  Future<Customer> _ensureDebugTestCustomer(String tenantId) async {
    final cachedCustomer = _findDebugCustomer(_customers.values);
    if (cachedCustomer != null) return cachedCustomer;

    final customers = await _customerService.getCustomers(forceRefresh: false);
    final existingCustomer = _findDebugCustomer(customers);
    if (existingCustomer != null) return existingCustomer;

    return _customerService.createCustomer(
      Customer(
        tenantId: tenantId,
        name: _debugTestCustomerName,
        rut: '',
        email: 'debug+taller@local.test',
        phone: '+56900000000',
        address: 'Fixture debug [test data]',
        region: 'Valparaiso',
      ),
    );
  }

  Customer? _findDebugCustomer(Iterable<Customer> customers) {
    for (final customer in customers) {
      if (customer.name.trim().toLowerCase() ==
          _debugTestCustomerName.toLowerCase()) {
        return customer;
      }
    }
    return null;
  }

  Future<Bike> _ensureDebugScenarioBike({
    required String tenantId,
    required String customerId,
    required _DebugBikeScenario scenario,
  }) async {
    Bike? existingBike;
    if (scenario.reuseBike) {
      existingBike = _findBikeBySerial(_bikes.values, scenario.fixtureSerial);
      existingBike ??= _findBikeBySerial(
        await _bikeshopService.getBikes(forceRefresh: false),
        scenario.fixtureSerial,
      );
    }

    final serialNumber = scenario.reuseBike
        ? scenario.fixtureSerial
        : '${scenario.fixtureSerial}-${DateTime.now().millisecondsSinceEpoch}';
    final desiredBike = Bike(
      tenantId: tenantId,
      customerId: customerId,
      brand: scenario.brand,
      model: scenario.model,
      year: scenario.year,
      serialNumber: serialNumber,
      color: scenario.color,
      frameSize: scenario.frameSize,
      wheelSize: scenario.wheelSize,
      bikeType: scenario.bikeType,
      notes: '[test fixture:${scenario.id}] ${scenario.description}',
    );

    if (existingBike != null) {
      return _bikeshopService.updateBike(
        existingBike.copyWith(
          customerId: customerId,
          brand: desiredBike.brand,
          model: desiredBike.model,
          year: desiredBike.year,
          serialNumber: desiredBike.serialNumber,
          color: desiredBike.color,
          frameSize: desiredBike.frameSize,
          wheelSize: desiredBike.wheelSize,
          bikeType: desiredBike.bikeType,
          notes: desiredBike.notes,
        ),
      );
    }

    return _bikeshopService.createBike(desiredBike);
  }

  Bike? _findBikeBySerial(Iterable<Bike> bikes, String serialNumber) {
    for (final bike in bikes) {
      if (bike.serialNumber?.trim().toLowerCase() ==
          serialNumber.trim().toLowerCase()) {
        return bike;
      }
    }
    return null;
  }

  Future<void> _ensureDebugBikeProfile({
    required String tenantId,
    required Bike bike,
    required _DebugBikeScenario scenario,
  }) async {
    final bikeId = bike.id;
    if (bikeId == null || bikeId.isEmpty || scenario.technicalValues.isEmpty) {
      return;
    }

    final existingProfile = await _bikeshopService.getBikeProfile(bikeId);
    final mergedValues = {
      ...?existingProfile?.technicalValues,
      ...scenario.technicalValues,
    };
    final mergedSources = {
      ...?existingProfile?.technicalSources,
      for (final key in scenario.technicalValues.keys) key: 'debug_fixture',
    };
    final mergedConfirmed = {
      ...?existingProfile?.technicalConfirmed,
      for (final key in scenario.technicalValues.keys) key: true,
    };

    final profile = (existingProfile ??
            BikeProfile(
              tenantId: tenantId,
              bikeId: bikeId,
            ))
        .copyWith(
      technicalProfile: {
        'values': mergedValues,
        'sources': mergedSources,
        'confirmed': mergedConfirmed,
      },
      summarySnapshot: {
        'identityLine': bike.displayName,
        'technicalHighlights': scenario.technicalHighlights,
        'warnings': const ['Fixture de depuracion'],
      },
      lastConfirmedAt: DateTime.now(),
    );

    await _bikeshopService.upsertBikeProfile(profile);
  }

  _DebugJobTiming _debugTimingForStage(
    _DebugJobLifecycleStage stage,
    DateTime now,
  ) {
    switch (stage) {
      case _DebugJobLifecycleStage.intake:
        return _DebugJobTiming(
          arrivalDate: now.subtract(const Duration(minutes: 20)),
          diagnosticDeadline: now.add(const Duration(days: 1)),
          deliveryDeadline: now.add(const Duration(days: 3)),
        );
      case _DebugJobLifecycleStage.diagnostic:
        return _DebugJobTiming(
          arrivalDate: now.subtract(const Duration(hours: 3)),
          diagnosticDeadline: now.add(const Duration(hours: 12)),
          deliveryDeadline: now.add(const Duration(days: 2)),
          startedAt: now.subtract(const Duration(hours: 2)),
        );
      case _DebugJobLifecycleStage.inProgress:
        return _DebugJobTiming(
          arrivalDate: now.subtract(const Duration(days: 1)),
          diagnosticDeadline: now.subtract(const Duration(hours: 16)),
          deliveryDeadline: now.add(const Duration(days: 1)),
          startedAt: now.subtract(const Duration(hours: 6)),
        );
      case _DebugJobLifecycleStage.completed:
        return _DebugJobTiming(
          arrivalDate: now.subtract(const Duration(days: 2)),
          diagnosticDeadline: now.subtract(const Duration(days: 1, hours: 6)),
          deliveryDeadline: now.add(const Duration(hours: 8)),
          startedAt: now.subtract(const Duration(days: 1)),
          completedAt: now.subtract(const Duration(hours: 1)),
        );
      case _DebugJobLifecycleStage.delivered:
        return _DebugJobTiming(
          arrivalDate: now.subtract(const Duration(days: 4)),
          diagnosticDeadline: now.subtract(const Duration(days: 3)),
          deliveryDeadline: now.subtract(const Duration(days: 1)),
          startedAt: now.subtract(const Duration(days: 3)),
          completedAt: now.subtract(const Duration(days: 1, hours: 8)),
          deliveredAt: now.subtract(const Duration(hours: 3)),
        );
    }
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
          LayoutBuilder(builder: (context, constraints) {
            if (constraints.maxWidth < 900) {
              // Mobile/Tablet Toolbar
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Search first on mobile
                  SizedBox(
                    height: 48,
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Buscar trabajos...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchTerm.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() => _searchTerm = '');
                                  _applyFiltersAndSort();
                                },
                              )
                            : null,
                        isDense: true,
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
                  const SizedBox(height: 12),

                  // Scrollable filters
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        SegmentedButton<String>(
                          segments: _buildStatusSegments(compact: true),
                          selected: <String>{_statusFilter},
                          onSelectionChanged: (selected) {
                            if (selected.isNotEmpty) {
                              setState(() => _statusFilter = selected.first);
                              _applyFiltersAndSort();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // View toggles
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                                value: 'table',
                                icon: Icon(Icons.table_rows, size: 16),
                                label: Text('Tabla')),
                            ButtonSegment(
                                value: 'board',
                                icon: Icon(Icons.view_column, size: 16),
                                label: Text('Tablero')),
                            ButtonSegment(
                                value: 'calendar',
                                icon: Icon(Icons.calendar_month, size: 16),
                                label: Text('Calendario')),
                            ButtonSegment(
                                value: 'gantt',
                                icon: Icon(Icons.view_timeline, size: 16),
                                label: Text('Gantt')),
                            ButtonSegment(
                                value: 'tasks',
                                icon: Icon(Icons.task_alt, size: 16),
                                label: Text('Tareas')),
                          ],
                          selected: <String>{_viewMode},
                          onSelectionChanged: (selected) {
                            if (selected.isNotEmpty) {
                              setState(() => _viewMode = selected.first);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            // Desktop Toolbar
            return Column(
              children: [
                Row(
                  children: [
                    SegmentedButton<String>(
                      segments: _buildStatusSegments(compact: false),
                      selected: <String>{_statusFilter},
                      onSelectionChanged: (selected) {
                        if (selected.isNotEmpty) {
                          setState(() => _statusFilter = selected.first);
                          _applyFiltersAndSort();
                        }
                      },
                    ),
                    const SizedBox(width: 16),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'table',
                          icon: Icon(Icons.table_rows, size: 16),
                          label: Text('Tabla', style: TextStyle(fontSize: 13)),
                        ),
                        ButtonSegment(
                          value: 'board',
                          icon: Icon(Icons.view_column, size: 16),
                          label:
                              Text('Tablero', style: TextStyle(fontSize: 13)),
                        ),
                        ButtonSegment(
                          value: 'calendar',
                          icon: Icon(Icons.calendar_month, size: 16),
                          label: Text('Calendario',
                              style: TextStyle(fontSize: 13)),
                        ),
                        ButtonSegment(
                          value: 'gantt',
                          icon: Icon(Icons.view_timeline, size: 16),
                          label: Text('Gantt', style: TextStyle(fontSize: 13)),
                        ),
                        ButtonSegment(
                          value: 'tasks',
                          icon: Icon(Icons.task_alt, size: 16),
                          label: Text('Tareas', style: TextStyle(fontSize: 13)),
                        ),
                      ],
                      selected: <String>{_viewMode},
                      onSelectionChanged: (selected) {
                        if (selected.isNotEmpty) {
                          setState(() => _viewMode = selected.first);
                        }
                      },
                    ),
                    const SizedBox(width: 16),
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
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
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
              ],
            );
          }),

          // Filters row
          const SizedBox(height: 12),
          Row(
            children: [
              // Quick filters (only overdue and unpaid - not status chips)
              if (_showOnlyOverdue || _showOnlyUnpaid) ...[
                Wrap(
                  spacing: 8,
                  children: [
                    if (_showOnlyOverdue)
                      Chip(
                        label: const Text('Vencidos',
                            style: TextStyle(fontSize: 12)),
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
                        label: const Text('Sin Pagar',
                            style: TextStyle(fontSize: 12)),
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

              // Status filter button
              _buildStatusFilterButton(),

              const SizedBox(width: 4),

              // Filter menu
              PopupMenuButton<String>(
                icon: const Icon(Icons.filter_list),
                tooltip: 'Filtros',
                itemBuilder: (context) => <PopupMenuEntry<String>>[
                  const PopupMenuItem(
                    enabled: false,
                    child: Text('Filtros',
                        style: TextStyle(fontWeight: FontWeight.bold)),
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

              if (_filteredJobs.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(width: 1, height: 24, color: Colors.grey.shade300),
                const SizedBox(width: 16),
                _buildJobTypeCounters(),
              ],

              const Spacer(),

              // Stats - sum invoice totals, paid, and outstanding
              if (_filteredJobs.isNotEmpty)
                Builder(builder: (context) {
                  double totalSum = 0;
                  double paidSum = 0;
                  for (final job in _filteredJobs) {
                    final invoice =
                        job.invoiceId != null ? _invoices[job.invoiceId] : null;
                    totalSum += invoice?.total ?? job.totalCost;
                    paidSum += invoice?.paidAmount ?? 0;
                  }
                  final outstandingSum = totalSum - paidSum;
                  final fmt =
                      NumberFormat.currency(symbol: '\$', decimalDigits: 0);
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Total: ${fmt.format(totalSum)}',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (paidSum > 0) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text('·',
                              style: TextStyle(
                                  color: Colors.grey.shade400, fontSize: 16)),
                        ),
                        Text(
                          'Pagado: ${fmt.format(paidSum)}',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green.shade700,
                                  ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text('·',
                              style: TextStyle(
                                  color: Colors.grey.shade400, fontSize: 16)),
                        ),
                        Text(
                          'Por cobrar: ${fmt.format(outstandingSum)}',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: outstandingSum > 0
                                        ? Colors.orange.shade700
                                        : Colors.green.shade700,
                                  ),
                        ),
                      ],
                    ],
                  );
                }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildJobTypeCounters() {
    // Count total bicycles across all filtered jobs, accounting for multi-bike jobs.
    // Use _jobBikesMap (which has actual per-job bike entries from the DB);
    // fall back to 1 if the job has a bikeId but no entry in the map yet.
    int bicycles = 0;
    for (final j in _filteredJobs) {
      if (j.jobType == JobType.itemService)
        continue; // item/accessory jobs have no bike
      final jobBikes = _jobBikesMap[j.id ?? ''];
      if (jobBikes != null && jobBikes.isNotEmpty) {
        bicycles += jobBikes.length;
      } else if (j.bikeId != null) {
        bicycles += 1; // fallback: primary bike only
      }
    }

    final items = _filteredJobs.where((j) {
      if (j.jobType == JobType.itemService) return true;
      if (j.jobType == JobType.quotation) return false;
      if (j.bikeId != null) return false;
      return j.subjectData != null ||
          j.subjectId != null ||
          (j.subjectNotes?.trim().isNotEmpty ?? false);
    }).length;
    // Only count warranty-type jobs that are still in progress (not completed/finalizado).
    // Warranty jobs in the complete phase (e.g. "Terminado Cubierto") are done
    // and should not count as "active" warranties in the counter.
    final warranties = _filteredJobs.where((j) {
      if (j.jobType != JobType.warranty) return false;
      final phase =
          j.customStatus?.phase ?? _inferPhaseFromLegacyStatus(j.status);
      return phase != StatusPhase.complete;
    }).length;
    final quotations =
        _filteredJobs.where((j) => j.jobType == JobType.quotation).length;

    Widget simpleCount(IconData icon, String label, int count) {
      if (count == 0) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(right: 16.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.grey.shade500),
            const SizedBox(width: 6),
            Text(
              '$label: ',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            Text(
              '$count',
              style: TextStyle(
                color: Colors.grey.shade800,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        simpleCount(Icons.directions_bike, 'Bicicletas', bicycles),
        simpleCount(Icons.build, 'Ítems', items),
        simpleCount(Icons.shield, 'Garantías', warranties),
        simpleCount(Icons.description, 'Cotizaciones', quotations),
      ],
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
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              _searchTerm.isEmpty
                  ? 'No hay trabajos'
                  : 'No se encontraron resultados',
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

    // Calculate pagination
    final startIndex = _currentPage * _rowsPerPage;
    final endIndex = (startIndex + _rowsPerPage).clamp(0, _filteredJobs.length);
    final paginatedJobs = _filteredJobs.sublist(startIndex, endIndex);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Mobile View (Card List)
        if (constraints.maxWidth < 800) {
          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: paginatedJobs.length,
                  itemBuilder: (context, index) =>
                      _buildMobileJobCard(paginatedJobs[index]),
                ),
              ),
              _buildPaginationControls(startIndex, endIndex),
            ],
          );
        }

        // Desktop View (Table)
        // Calculate total width of all visible columns
        final totalColumnsWidth =
            _displayColumns.fold<double>(0, (sum, col) => sum + col.width);

        // Use the larger of constraints.maxWidth or totalColumnsWidth
        final tableWidth = totalColumnsWidth > constraints.maxWidth
            ? totalColumnsWidth
            : constraints.maxWidth;

        // Check if horizontal scrolling is needed
        final needsHorizontalScroll = totalColumnsWidth > constraints.maxWidth;

        return Column(
          children: [
            // Table header and body wrapped in single horizontal scroll
            Expanded(
              child: SingleChildScrollView(
                controller: _horizontalScrollController,
                scrollDirection: Axis.horizontal,
                physics: _isColumnResizing
                    ? const NeverScrollableScrollPhysics()
                    : null,
                child: SizedBox(
                  width: tableWidth,
                  child: Column(
                    children: [
                      // Table header
                      _buildTableHeader(tableWidth),
                      // Table body
                      Expanded(
                        child: ListView.builder(
                          itemCount: paginatedJobs.length,
                          itemBuilder: (context, index) =>
                              _buildTableRow(paginatedJobs[index], tableWidth),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Horizontal scrollbar - always visible when scrolling is needed
            if (needsHorizontalScroll)
              _HoverScrollbar(
                scrollController: _horizontalScrollController,
                contentWidth: totalColumnsWidth,
                viewportWidth: constraints.maxWidth,
              ),
            // Pagination controls
            _buildPaginationControls(startIndex, endIndex),
          ],
        );
      },
    );
  }

  Widget _buildMobileJobCard(MechanicJob job) {
    // Enhanced mobile card from PegasListPage design
    final customer = _customers[job.customerId];
    final bike = _bikes[job.bikeId];

    final isOverdue = job.deliveryDeadline != null &&
        job.deliveryDeadline!.isBefore(DateTime.now()) &&
        job.status != JobStatus.finalizado &&
        job.status != JobStatus.entregado; // Also exclude delivered

    return Card(
      margin: const EdgeInsets.only(bottom: 12, left: 12, right: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isOverdue ? Colors.red.shade300 : Colors.grey.shade200,
          width: isOverdue ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedJob = job;
            _selectedJobItems = [];
            _productImages = {};
          });
          _loadJobDetails(job);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: isOverdue
                ? LinearGradient(
                    colors: [Colors.red.shade50, Colors.white],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row: Job # + Priority + Status
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              job.jobNumber ?? 'Sin #',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildCompactPriorityBadge(job.priority),
                          ],
                        ),
                        if (customer != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            customer.name,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  _buildCompactStatusBadge(job.status),
                ],
              ),

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Bike & Diagnosis
              if (bike != null)
                Row(
                  children: [
                    Icon(Icons.pedal_bike, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 6),
                    Text(
                      bike.displayName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              if (job.diagnosis != null || job.clientRequest != null) ...[
                const SizedBox(height: 4),
                Text(
                  job.diagnosis ?? job.clientRequest ?? '',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              const SizedBox(height: 12),

              // Footer: Date + Cost
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('dd/MM', 'es_CL').format(job.arrivalDate),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  if (job.deliveryDeadline != null) ...[
                    const SizedBox(width: 12),
                    Icon(job.isOverdue ? Icons.warning : Icons.event_available,
                        size: 14,
                        color: isOverdue ? Colors.red : Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('dd/MM', 'es_CL')
                          .format(job.deliveryDeadline!),
                      style: TextStyle(
                          fontSize: 12,
                          color: isOverdue ? Colors.red : Colors.grey[600],
                          fontWeight:
                              isOverdue ? FontWeight.bold : FontWeight.normal),
                    ),
                  ],
                  const Spacer(),
                  if (job.totalCost > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.green[100]!),
                      ),
                      child: Text(
                        NumberFormat.currency(symbol: '\$', decimalDigits: 0)
                            .format(job.totalCost),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[700],
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

  Widget _buildCompactStatusBadge(JobStatus status) {
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
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        status.displayName,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildCompactPriorityBadge(JobPriority priority) {
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

    if (priority == JobPriority.normal || priority == JobPriority.baja) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 2),
          Text(
            priority.displayName,
            style: TextStyle(
                fontSize: 10, color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildStatusChip(MechanicJob job) {
    final hasCustomStatus = job.statusId != null;
    Color color;
    String label;

    if (hasCustomStatus) {
      if (job.customStatus != null) {
        color =
            Color(int.parse(job.customStatus!.color.replaceFirst('#', '0xff')));
        label = job.customStatus!.name;
      } else {
        color = Colors.grey;
        label = 'Desconocido';
      }
    } else {
      // Legacy status fallback
      color = _getStatusColor(job.status);
      label = job.status.name.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildPriorityChip(JobPriority priority) {
    Color color;
    String label;
    switch (priority) {
      case JobPriority.baja:
        color = Colors.green;
        label = 'BAJA';
        break;
      case JobPriority.normal:
        color = Colors.blue;
        label = 'MEDIA';
        break;
      case JobPriority.alta:
        color = Colors.orange;
        label = 'ALTA';
        break;
      case JobPriority.urgente:
        color = Colors.red;
        label = 'URGENTE';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildInfoChip(IconData icon, String label, ThemeData theme,
      {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (color ?? theme.colorScheme.onSurface).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 12, color: color ?? theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color ?? theme.colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationControls(int startIndex, int endIndex) {
    final theme = Theme.of(context);
    final totalPages = (_filteredJobs.length / _rowsPerPage).ceil();

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          Text(
            'Filas por página:',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: _rowsPerPage,
            items: const [
              DropdownMenuItem(value: 10, child: Text('10')),
              DropdownMenuItem(value: 25, child: Text('25')),
              DropdownMenuItem(value: 50, child: Text('50')),
              DropdownMenuItem(value: 100, child: Text('100')),
            ],
            onChanged: (value) {
              setState(() {
                _rowsPerPage = value!;
                _currentPage = 0;
              });
              _saveTableState();
            },
            underline: const SizedBox(),
          ),
          const Spacer(),
          Text(
            '${startIndex + 1}-$endIndex de ${_filteredJobs.length}',
            style: theme.textTheme.bodySmall,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _currentPage > 0
                ? () {
                    setState(() => _currentPage--);
                    _saveTableState();
                  }
                : null,
          ),
          Text(
            'Página ${_currentPage + 1} de $totalPages',
            style: theme.textTheme.bodySmall,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: endIndex < _filteredJobs.length
                ? () {
                    setState(() => _currentPage++);
                    _saveTableState();
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader(double tableWidth) {
    final displayColumns = _displayColumns;

    return Container(
      width: tableWidth,
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: Row(
        children: displayColumns.asMap().entries.map((entry) {
          return _buildHeaderCell(
              entry.value, entry.key, displayColumns.length);
        }).toList(),
      ),
    );
  }

  Widget _buildHeaderCell(
      ColumnConfig col, int displayIndex, int totalColumns) {
    final theme = Theme.of(context);
    Widget content;

    if (col.id == 'checkbox') {
      bool? checkboxValue;
      if (_filteredJobs.isEmpty || _selectedJobIds.isEmpty) {
        checkboxValue = false;
      } else if (_selectedJobIds.length == _filteredJobs.length) {
        checkboxValue = true;
      } else {
        checkboxValue = null;
      }

      content = Checkbox(
        value: checkboxValue,
        onChanged: (checked) {
          setState(() {
            if (checked == true) {
              _selectedJobIds
                ..clear()
                ..addAll(_filteredJobs.map((j) => j.id).whereType<String>());
            } else {
              _selectedJobIds.clear();
            }
          });
        },
        tristate: true,
      );
    } else {
      content = _buildHeaderContent(col);
    }

    // Always wrap content in padding container (interactive area)
    // This container is the visual representation of the column header
    Widget headerWidget = Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.65),
          ),
        ),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: _tableCellHorizontalPadding(col),
        vertical: 12,
      ),
      child: content,
    );

    // Determine if this specific column is being dragged
    final isDragging = _draggingColumnId == col.id;

    // Wrap in Draggable ONLY if allowed, but ALWAYS wrap in DragTarget
    // This allows dropping ONTO non-reorderable columns (like checkbox/status)
    // effectively allowing insertion before/after them.
    Widget draggableCell;
    if (col.reorderable) {
      draggableCell = Draggable<String>(
        data: col.id,
        axis: Axis.horizontal,
        feedback: Material(
          color: Colors.transparent,
          child: Opacity(
            opacity: 0.85,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.drag_indicator,
                      size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    col.label,
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
        onDragStarted: () {
          setState(() {
            _draggingColumnId = col.id;
            _dragTargetIndex = displayIndex;
          });
        },
        onDragEnd: (_) {
          setState(() {
            _draggingColumnId = null;
            _dragTargetIndex = null;
          });
        },
        onDraggableCanceled: (_, __) {
          setState(() {
            _draggingColumnId = null;
            _dragTargetIndex = null;
          });
        },
        child: Opacity(
          opacity: isDragging ? 0.3 : 1.0,
          child: headerWidget,
        ),
      );
    } else {
      draggableCell = headerWidget;
    }

    // UNIVERSAL DROP TARGET
    // Even non-reorderable columns (checkbox, actions) can receive drops
    Widget dropTarget = DragTarget<String>(
      onWillAcceptWithDetails: (details) {
        if (details.data == col.id) return false;
        // Update target index for live preview
        if (_dragTargetIndex != displayIndex) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _draggingColumnId != null) {
              setState(() {
                _dragTargetIndex = displayIndex;
              });
            }
          });
        }
        return true;
      },
      onLeave: (_) {
        // Don't clear target when leaving - it causes flickering
      },
      onAcceptWithDetails: (details) {
        final sourceId = details.data;
        if (_dragTargetIndex != null) {
          _applyColumnReorder(sourceId, _dragTargetIndex!);
        }
        setState(() {
          _draggingColumnId = null;
          _dragTargetIndex = null;
        });
      },
      builder: (context, candidateData, rejectedData) {
        return draggableCell;
      },
    );

    return SizedBox(
      key: ValueKey(col.id),
      width: col.width,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: dropTarget),
          if (col.resizable)
            Positioned(
              top: 0,
              right: -4,
              bottom: 0,
              width: 8,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragStart: (_) => _beginColumnResize(),
                  onHorizontalDragUpdate: (details) =>
                      _resizeColumn(col, details.delta.dx),
                  onHorizontalDragEnd: (_) => _endColumnResize(),
                  onHorizontalDragCancel: _endColumnResize,
                  child: Center(
                    child: Container(
                      width: 2,
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.0),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _beginColumnResize() {
    _lockedHorizontalScrollOffset = _horizontalScrollController.hasClients
        ? _horizontalScrollController.offset
        : null;
    if (!_isColumnResizing) {
      setState(() => _isColumnResizing = true);
    }
  }

  void _resizeColumn(ColumnConfig col, double deltaX) {
    final lockedOffset = _lockedHorizontalScrollOffset;
    setState(() {
      col.width = (col.width + deltaX)
          .clamp(col.minWidth, col.maxWidth ?? 500)
          .toDouble();
    });
    if (lockedOffset != null) {
      _restoreHorizontalScrollOffset(lockedOffset);
    }
  }

  void _endColumnResize() {
    final lockedOffset = _lockedHorizontalScrollOffset;
    _saveColumnWidths();
    if (lockedOffset != null) {
      _restoreHorizontalScrollOffset(lockedOffset);
    }
    if (_isColumnResizing || _lockedHorizontalScrollOffset != null) {
      setState(() {
        _isColumnResizing = false;
        _lockedHorizontalScrollOffset = null;
      });
    }
  }

  void _restoreHorizontalScrollOffset(double offset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_horizontalScrollController.hasClients) return;
      final maxOffset = _horizontalScrollController.position.maxScrollExtent;
      final targetOffset = offset.clamp(0.0, maxOffset).toDouble();
      if ((_horizontalScrollController.offset - targetOffset).abs() > 0.5) {
        _horizontalScrollController.jumpTo(targetOffset);
      }
    });
  }

  Widget _buildHeaderContent(ColumnConfig col) {
    return Row(
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
      ],
    );
  }

  Future<void> _handleDrop(MechanicJob job, DropDoneDetails details) async {
    setState(() {
      _draggingJobId = null;
    });
    if (details.files.isEmpty) return;
    await _uploadFilesForJob(job, details.files);
  }

  Future<void> _pickFileForJob(MechanicJob job) async {
    try {
      final result = await ImageService.pickFile();
      if (result != null) {
        // pickFile returns bytes/name, but we need XFile for _uploadFilesForJob if we want to reuse it directly.
        // However, ImageService.pickFile returns a record.
        // Let's adjust _uploadFilesForJob to take bytes/name or use ImageService.uploadBytes directly here.
        // Actually, let's just implement the upload here reusing logic or make _uploadFilesForJob flexible.
        // Better: standardize on bytes/name for the helper.

        await _uploadFileBytesForJob(job, result.bytes, result.name);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al seleccionar archivo: $e')),
        );
      }
    }
  }

  Future<void> _uploadFilesForJob(MechanicJob job, List<XFile> files) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Subiendo archivos...')),
    );

    final newUrls = <String>[];
    int successCount = 0;

    try {
      for (final file in files) {
        final bytes = await file.readAsBytes();
        final name = file.name;

        final url = await ImageService.uploadBytes(
          bytes: bytes,
          fileName: name,
          bucket: 'vinabike-assets',
          folder: 'mechanic_jobs/${job.customerId}/',
        );

        if (url != null) {
          newUrls.add(url);
          successCount++;
        }
      }

      await _updateJobImages(job, newUrls, successCount);
    } catch (e) {
      _handleUploadError(e);
    }
  }

  Future<void> _uploadFileBytesForJob(
      MechanicJob job, Uint8List bytes, String name) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Subiendo archivo...')),
    );

    try {
      final url = await ImageService.uploadBytes(
        bytes: bytes,
        fileName: name,
        bucket: 'vinabike-assets',
        folder: 'mechanic_jobs/${job.customerId}/',
      );

      if (url != null) {
        await _updateJobImages(job, [url], 1);
      }
    } catch (e) {
      _handleUploadError(e);
    }
  }

  Future<void> _updateJobImages(
      MechanicJob job, List<String> newUrls, int successCount) async {
    if (newUrls.isNotEmpty) {
      final updatedImageUrls = [...job.imageUrls, ...newUrls];

      // Optimistic update
      setState(() {
        final index = _jobs.indexWhere((j) => j.id == job.id);
        if (index != -1) {
          _jobs[index] = job.copyWith(imageUrls: updatedImageUrls);
        }
      });

      await _bikeshopService
          .updateJob(job.copyWith(imageUrls: updatedImageUrls));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('$successCount archivos subidos exitosamente')),
        );
      }
    }
  }

  void _handleUploadError(dynamic e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error al subir archivos: $e'),
            backgroundColor: Colors.red),
      );
    }
    // Revert optimistic update if needed or just reload
    _loadData();
  }

  bool _isImage(String nameOrUrl) {
    final ext = nameOrUrl.split('.').last.split('?').first.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'].contains(ext);
  }

  /// Apply column reorder using display indices (for live preview drag)
  void _applyColumnReorder(String sourceId, int targetDisplayIndex) {
    final visibleColumns = _columns.where((col) => col.visible).toList();
    final sourceDisplayIndex =
        visibleColumns.indexWhere((c) => c.id == sourceId);
    if (sourceDisplayIndex == -1 || sourceDisplayIndex == targetDisplayIndex) {
      return;
    }

    // Get the actual column indices in _columns (not just visible)
    final sourceActualIndex = _columns.indexWhere((c) => c.id == sourceId);
    if (sourceActualIndex == -1) return;

    // Calculate the target actual index based on visible columns
    // We need to find where in _columns the visible column at targetDisplayIndex is
    int targetActualIndex;
    if (targetDisplayIndex >= visibleColumns.length) {
      // Insert at end of visible columns
      final lastVisible = visibleColumns.last;
      targetActualIndex =
          _columns.indexWhere((c) => c.id == lastVisible.id) + 1;
    } else {
      final targetColumn = visibleColumns[targetDisplayIndex];
      targetActualIndex = _columns.indexWhere((c) => c.id == targetColumn.id);
    }

    setState(() {
      final column = _columns.removeAt(sourceActualIndex);
      // Adjust target index if source was before it
      if (sourceActualIndex < targetActualIndex) {
        targetActualIndex -= 1;
      }
      _columns.insert(targetActualIndex.clamp(0, _columns.length), column);
    });

    _saveColumnOrder();
  }

  Widget _buildTableRow(MechanicJob job, double tableWidth) {
    final isSelected = _selectedJob?.id == job.id;
    final customer = _customers[job.customerId];
    final bike = _bikes[job.bikeId];
    final jobBikes = _jobBikesMap[job.id]; // Multi-bike data

    final jobId = job.id;
    final isExpanded = jobId != null && _expandedJobIds.contains(jobId);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
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
                  ? Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.3)
                  : null,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Row(
              children: _displayColumns.map((col) {
                return _buildDataCell(col, job, customer, bike, jobBikes);
              }).toList(),
            ),
          ),
        ),
        if (isExpanded && jobBikes != null && jobBikes.isNotEmpty)
          _buildExpandedJobBikes(
            job: job,
            customer: customer,
            jobBikes: jobBikes,
            tableWidth: tableWidth,
          ),
      ],
    );
  }

  Widget _buildDataCell(ColumnConfig col, MechanicJob job, Customer? customer,
      Bike? bike, List<MechanicJobBike>? jobBikes,
      {MechanicJobBike? jobBike}) {
    final content = _getCellContent(col.id, job, customer, bike, jobBikes,
        jobBike: jobBike);
    final horizontalPadding = _tableCellHorizontalPadding(col);

    return SizedBox(
      width: col.width,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 8,
        ),
        child: content,
      ),
    );
  }

  double _tableCellHorizontalPadding(ColumnConfig col) {
    return switch (col.id) {
      'checkbox' || 'status' || 'attachments' => 4,
      'actions' => 4,
      'state' || 'kpi' || 'priority' || 'invoice' || 'total' => 8,
      _ => 16,
    };
  }

  Widget _getCellContent(String columnId, MechanicJob job, Customer? customer,
      Bike? bike, List<MechanicJobBike>? jobBikes,
      {MechanicJobBike? jobBike}) {
    // Determine if this is a multi-bike summary row (main row for multi-bike job)
    final isMultiBikeSummary =
        jobBikes != null && jobBikes.length > 1 && jobBike == null;
    // Determine if this is showing per-bike detail (expanded row)
    final isPerBikeDetail = jobBike != null;

    switch (columnId) {
      case 'checkbox':
        // Per-bike detail: hide checkbox (selection is at job level)
        if (isPerBikeDetail) {
          return const SizedBox.shrink();
        }
        return Checkbox(
          value: _selectedJobIds.contains(job.id),
          onChanged: (checked) {
            setState(() {
              if (checked == true) {
                _selectedJobIds.add(job.id!);
              } else {
                _selectedJobIds.remove(job.id);
              }
            });
          },
        );

      case 'status':
        // Clickable status indicator with color - uses custom status color
        final statusColor = job.colorValue;
        return InkWell(
          onTap: () => _showStatusMenu(job),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
              border: Border.all(
                color: statusColor.withValues(alpha: 0.5),
                width: 2,
              ),
            ),
          ),
        );

      case 'kpi':
        // Compact KPI indicators with Duration Tooltips
        final now = DateTime.now();

        // 1. Diagnostic Duration
        final diagDone = job.diagnosticSentAt != null;
        String diagMsg;
        Color diagColor;

        if (diagDone) {
          final d = job.diagnosticSentAt!.difference(job.arrivalDate);
          diagMsg =
              'Diagnóstico: ${_formatDuration(d)} (Enviado el ${_formatDate(job.diagnosticSentAt!)})';
          diagColor = Colors.blue;
        } else if (job.diagnosticDeadline != null &&
            job.diagnosticDeadline!.isBefore(now)) {
          final d = now.difference(job.arrivalDate);
          diagMsg = 'Diagnóstico Atrasado: ${_formatDuration(d)} esperando';
          diagColor = Colors.red;
        } else {
          final d = now.difference(job.arrivalDate);
          diagMsg = 'Diagnóstico Pendiente: ${_formatDuration(d)} esperando';
          diagColor = Colors.orange;
        }

        // 2. Shop Duration
        final shopStarted = job.startedAt != null;
        final shopDone = job.completedAt != null;
        String shopMsg;
        Color shopColor;

        if (shopDone && job.startedAt != null) {
          final d = job.completedAt!.difference(job.startedAt!);
          shopMsg = 'Taller: ${_formatDuration(d)} (Completado)';
          shopColor = Colors.green;
        } else if (shopDone) {
          // If completed but skip started, use arrival date as fallback for duration
          final d = job.completedAt!.difference(job.arrivalDate);
          shopMsg = 'Taller: ${_formatDuration(d)} (Completado sin inicio)';
          shopColor = Colors.green;
        } else if (shopStarted) {
          final d = now.difference(job.startedAt!);
          shopMsg = 'Taller En Curso: ${_formatDuration(d)}';
          shopColor = Colors.blue;
        } else {
          shopMsg = 'Taller: No iniciado';
          shopColor = Colors.grey.shade300;
        }

        // 3. Total Duration
        final delivered = job.deliveredAt != null;
        String totalMsg;
        Color totalColor;

        if (delivered) {
          final d = job.deliveredAt!.difference(job.arrivalDate);
          totalMsg = 'Total: ${_formatDuration(d)} (Entregado)';
          totalColor = Colors.purple;
        } else {
          final d = now.difference(job.arrivalDate);
          totalMsg = 'Total Actual: ${_formatDuration(d)}';
          totalColor = Colors.grey.shade300;
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Tooltip(
              message: diagMsg,
              child:
                  Icon(Icons.assignment_turned_in, size: 16, color: diagColor),
            ),
            Tooltip(
              message: shopMsg,
              child: Icon(Icons.build_circle, size: 16, color: shopColor),
            ),
            Tooltip(
              message: totalMsg,
              child: Icon(Icons.timer, size: 16, color: totalColor),
            ),
          ],
        );

      case 'id':
        return const Text('-');

      case 'job_number':
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => context.push('/taller/pegas/${job.id}'),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
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
              ),
            ),
          ),
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
                        decorationColor: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.3),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (customer?.phone != null)
                      Text(
                        customer!.phone!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
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
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.6),
                  ),
                  tooltip: 'Acciones rápidas',
                  padding: EdgeInsets.zero,
                  itemBuilder: (context) => [
                    if (customer.phone != null)
                      PopupMenuItem(
                        value: 'call',
                        child: Row(
                          children: [
                            Icon(Icons.phone,
                                size: 16, color: Colors.green.shade700),
                            const SizedBox(width: 8),
                            const Text('Llamar',
                                style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                    if (customer.email != null)
                      PopupMenuItem(
                        value: 'email',
                        child: Row(
                          children: [
                            Icon(Icons.email,
                                size: 16, color: Colors.blue.shade700),
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
        // Multi-bike modes:
        // 1. isMultiBikeSummary: Main row shows "X Bicicletas" with expand button
        // 2. isPerBikeDetail: Expanded row shows specific bike name
        // 3. Single bike: Normal display

        final jobId = job.id;
        final isExpanded = jobId != null && _expandedJobIds.contains(jobId);

        // Per-bike detail row - show just the specific bike name
        if (isPerBikeDetail) {
          final bikeName = bike?.displayName ?? 'Sin nombre';
          final bikeImageUrl = bike?.imageUrl;

          return Row(
            children: [
              Image.asset(
                'assets/icons/mtb_bike_v3.png',
                width: 35,
                height: 35,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.pedal_bike,
                  size: 35,
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(width: 6),
              if (bikeImageUrl != null) ...[
                GestureDetector(
                  onTap: () => _showBikeImageModal(bikeImageUrl),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      image: DecorationImage(
                        image: NetworkImage(bikeImageUrl),
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
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        }

        // Multi-bike summary row - show count and expand button
        if (isMultiBikeSummary) {
          final bikeCount = jobBikes.length;

          return InkWell(
            onTap: () {
              setState(() {
                if (_expandedJobIds.contains(jobId)) {
                  _expandedJobIds.remove(jobId);
                } else {
                  _expandedJobIds.add(jobId!);
                }
              });
            },
            child: Row(
              children: [
                Image.asset(
                  'assets/icons/mtb_bike_v3.png',
                  width: 35,
                  height: 35,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.pedal_bike,
                    size: 35,
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$bikeCount Bicicletas',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: isExpanded ? 'Contraer' : 'Expandir',
                  icon: Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: () {
                    setState(() {
                      if (_expandedJobIds.contains(jobId)) {
                        _expandedJobIds.remove(jobId);
                      } else {
                        _expandedJobIds.add(jobId!);
                      }
                    });
                  },
                ),
              ],
            ),
          );
        }

        // Non-bike job: show subject/item instead of bike
        if (job.bikeId == null ||
            (job.jobType == JobType.itemService && job.subjectData != null)) {
          final subjectName = job.subjectData?.name ?? job.subjectNotes ?? '—';
          final subjectNotes = (job.subjectData != null &&
                  job.subjectNotes != null &&
                  job.subjectNotes!.isNotEmpty)
              ? job.subjectNotes
              : null;
          final subjectIcon = _jobTypeIcon(job.jobType);
          return Row(
            children: [
              Icon(subjectIcon,
                  size: 28, color: Theme.of(context).colorScheme.secondary),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(subjectName,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis),
                    if (subjectNotes != null)
                      Text(subjectNotes,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                          overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          );
        }

        // Single bike - normal display
        final bikeName = bike?.displayName ?? 'N/A';
        final bikeImageUrl = bike?.imageUrl;

        return InkWell(
          onTap: () => _showBikeSelectorDialog(job, customer),
          child: Row(
            children: [
              Image.asset(
                'assets/icons/mtb_bike_v3.png',
                width: 35,
                height: 35,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.pedal_bike,
                  size: 35,
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(width: 6),
              if (bikeImageUrl != null) ...[
                GestureDetector(
                  onTap: () => _showBikeImageModal(bikeImageUrl),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      image: DecorationImage(
                        image: NetworkImage(bikeImageUrl),
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
                  style: const TextStyle(fontSize: 13),
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
        return DeadlineCell(
          job: job,
          onTap: () => _showDualDeadlineDialog(job),
        );

      case 'state':
        // Per-bike detail: show per-bike status (independent per bike)
        if (isPerBikeDetail) {
          // Use per-bike status if set, otherwise fall back to job status
          final bikeStatus = jobBike.customStatus;
          final statusColor =
              bikeStatus != null ? bikeStatus.colorValue : job.colorValue;
          final statusName = bikeStatus?.name ?? job.statusDisplayName;
          return LayoutBuilder(
            builder: (context, constraints) {
              final chipWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : double.infinity;

              return InkWell(
                onTap: () => _showBikeStatusMenu(job, jobBike),
                child: SizedBox(
                  width: chipWidth,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
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
                        Flexible(
                          child: Text(
                            statusName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        }

        // Single bike job: show job-level status
        final statusColor = job.colorValue;
        final statusName = job.statusDisplayName;
        final statusUpdatedAt = job.statusUpdatedAt;
        return LayoutBuilder(
          builder: (context, constraints) {
            final chipWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : double.infinity;

            return InkWell(
              onTap: () => _showStatusMenu(job),
              child: SizedBox(
                width: chipWidth,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
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
                          Flexible(
                            child: Text(
                              statusName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (statusUpdatedAt != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          _formatStatusTimestamp(statusUpdatedAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9,
                            color: statusColor.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
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
          constraints: const BoxConstraints(maxWidth: 96),
          decoration: BoxDecoration(
            color: priorityColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: priorityColor.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(priorityIcon, size: 14, color: priorityColor),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  job.priority.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: priorityColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );

      case 'diagnosis':
        // Per-bike detail: show per-bike data from MechanicJobBike
        if (isPerBikeDetail) {
          final invoice =
              job.invoiceId != null ? _invoices[job.invoiceId] : null;
          return SmartJobDetailsEditor(
            customerName: customer?.name,
            bikeName: bike?.displayName,
            clientRequest: jobBike.workRequested,
            diagnosis: jobBike.diagnosis,
            workPerformed: jobBike.workPerformed,
            notes: jobBike.technicianNotes,
            job: job,
            invoice: invoice,
            jobBike: jobBike, // Pass the jobBike for per-bike editing
            onSave: ({
              String? clientRequest,
              String? diagnosis,
              String? workPerformed,
              String? notes,
            }) async {
              // Start local operation to suppress reload from service notification
              _startLocalOperation();

              // Helper to get the new value: null means unchanged, empty string means clear
              String? resolveField(String? newValue, String? oldValue) {
                if (newValue == null) return oldValue; // Unchanged
                if (newValue.isEmpty) return null; // Cleared
                return newValue; // New value
              }

              // Create updated MechanicJobBike with new values
              final updatedJobBike = MechanicJobBike(
                id: jobBike.id,
                tenantId: jobBike.tenantId,
                jobId: jobBike.jobId,
                bikeId: jobBike.bikeId,
                orderIndex: jobBike.orderIndex,
                workRequested:
                    resolveField(clientRequest, jobBike.workRequested),
                diagnosis: resolveField(diagnosis, jobBike.diagnosis),
                workPerformed:
                    resolveField(workPerformed, jobBike.workPerformed),
                technicianNotes: resolveField(notes, jobBike.technicianNotes),
                partsCost: jobBike.partsCost,
                laborCost: jobBike.laborCost,
                subtotal: jobBike.subtotal,
                isWarrantyWork: jobBike.isWarrantyWork,
                requiresApproval: jobBike.requiresApproval,
                approvedByCustomer: jobBike.approvedByCustomer,
                approvedAt: jobBike.approvedAt,
                imageUrls: jobBike.imageUrls,
                bike: jobBike.bike,
                createdAt: jobBike.createdAt,
                updatedAt: DateTime.now(),
              );

              // Optimistic update in local cache
              final jobId = job.id;
              if (jobId != null && _jobBikesMap.containsKey(jobId)) {
                final bikes = _jobBikesMap[jobId]!;
                final index = bikes.indexWhere((b) => b.id == jobBike.id);
                if (index != -1) {
                  setState(() {
                    bikes[index] = updatedJobBike;
                  });
                }
              }

              // Save in background
              try {
                await _bikeshopService.updateJobBike(updatedJobBike);
              } catch (e) {
                // Revert on error
                if (mounted) {
                  await _loadData();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error al guardar detalles: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } finally {
                _endLocalOperation();
              }
            },
          );
        }

        // Single bike: show job-level data (existing behavior)
        final invoice = job.invoiceId != null ? _invoices[job.invoiceId] : null;
        return SmartJobDetailsEditor(
          customerName: customer?.name,
          bikeName: bike?.displayName,
          clientRequest: job.clientRequest,
          diagnosis: job.diagnosis,
          workPerformed: job.workPerformed,
          notes: job.notes,
          job: job,
          invoice: invoice,
          onSave: ({
            String? clientRequest,
            String? diagnosis,
            String? workPerformed,
            String? notes,
          }) async {
            // Start local operation to suppress reload from service notification
            _startLocalOperation();

            // Helper to get the new value: null means unchanged, empty string means clear
            String? resolveField(String? newValue, String? oldValue) {
              if (newValue == null) return oldValue; // Unchanged
              if (newValue.isEmpty) return null; // Cleared
              return newValue; // New value
            }

            // Optimistic update - only update fields that were changed
            final updatedJob = MechanicJob(
              id: job.id,
              tenantId: job.tenantId,
              jobNumber: job.jobNumber,
              customerId: job.customerId,
              bikeId: job.bikeId,
              servicePackageId: job.servicePackageId,
              arrivalDate: job.arrivalDate,
              diagnosticDeadline: job.diagnosticDeadline,
              deliveryDeadline: job.deliveryDeadline,
              diagnosticSentAt: job.diagnosticSentAt,
              startedAt: job.startedAt,
              completedAt: job.completedAt,
              deliveredAt: job.deliveredAt,
              status: job.status,
              statusId: job.statusId,
              customStatus: job.customStatus,
              statusUpdatedAt: job.statusUpdatedAt,
              priority: job.priority,
              clientRequest: resolveField(clientRequest, job.clientRequest),
              diagnosis: resolveField(diagnosis, job.diagnosis),
              workPerformed: resolveField(workPerformed, job.workPerformed),
              notes: resolveField(notes, job.notes),
              assignedTo: job.assignedTo,
              assignedTechnicianName: job.assignedTechnicianName,
              estimatedCost: job.estimatedCost,
              finalCost: job.finalCost,
              partsCost: job.partsCost,
              laborCost: job.laborCost,
              discountAmount: job.discountAmount,
              taxAmount: job.taxAmount,
              totalCost: job.totalCost,
              taxTreatment: job.taxTreatment,
              invoiceId: job.invoiceId,
              isInvoiced: job.isInvoiced,
              isPaid: job.isPaid,
              isWarrantyJob: job.isWarrantyJob,
              warrantyNotes: job.warrantyNotes,
              requiresApproval: job.requiresApproval,
              approvedByCustomer: job.approvedByCustomer,
              approvedAt: job.approvedAt,
              imageUrls: job.imageUrls,
              createdAt: job.createdAt,
              updatedAt: DateTime.now(),
              deletedAt: job.deletedAt,
              deletedBy: job.deletedBy,
            );

            setState(() {
              final index = _jobs.indexWhere((j) => j.id == job.id);
              if (index != -1) {
                _jobs[index] = updatedJob;
                _applyFiltersAndSort();
              }
            });

            // Save in background
            try {
              await _bikeshopService.updateJob(updatedJob);
            } catch (e) {
              // Revert on error
              if (mounted) {
                await _loadData();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error al guardar detalles: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            } finally {
              _endLocalOperation();
            }
          },
        );

      case 'total':
        // Per-bike detail: show per-bike subtotal
        if (isPerBikeDetail) {
          return Text(
            NumberFormat.currency(symbol: '\$', decimalDigits: 0)
                .format(jobBike.subtotal),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          );
        }

        // Show invoice total with payment progress bar
        final invoice = job.invoiceId != null ? _invoices[job.invoiceId] : null;
        final displayTotal = invoice?.total ?? job.totalCost;
        final paidAmount = invoice?.paidAmount ?? 0.0;
        final hasPayments = paidAmount > 0 && displayTotal > 0;
        final isFullyPaid = hasPayments && paidAmount >= displayTotal;
        final paymentRatio = displayTotal > 0
            ? (paidAmount / displayTotal).clamp(0.0, 1.0)
            : 0.0;
        final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

        final content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fmt.format(displayTotal),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: isFullyPaid ? Colors.green.shade700 : null,
              ),
            ),
            // Thin payment progress bar
            if (hasPayments)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 4,
                    width: 80,
                    child: LinearProgressIndicator(
                      value: paymentRatio,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isFullyPaid
                            ? Colors.green.shade500
                            : Colors.orange.shade400,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );

        if (!hasPayments) return content;

        // Tooltip with full breakdown
        return Tooltip(
          message: 'Total: ${fmt.format(displayTotal)}\n'
              'Pagado: ${fmt.format(paidAmount)}\n'
              'Saldo: ${fmt.format(displayTotal - paidAmount)}',
          child: content,
        );

      case 'invoice':
        // Clickable invoice with full status display
        if (job.invoiceId == null && !job.isInvoiced) {
          // Warranty job: show green "Garantía" badge instead of "Generar"
          if (job.jobType == JobType.warranty) {
            final outcome = job.warrantyOutcome ?? WarrantyOutcome.pending;
            final Color badgeColor;
            final String badgeLabel;
            switch (outcome) {
              case WarrantyOutcome.covered:
                badgeColor = Colors.green;
                badgeLabel = 'Garantía ✓';
                break;
              case WarrantyOutcome.notCovered:
                badgeColor = Colors.red;
                badgeLabel = 'No cubierto';
                break;
              case WarrantyOutcome.pending:
                badgeColor = Colors.green;
                badgeLabel = 'Garantía';
                break;
            }
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: badgeColor.withValues(alpha: 0.5), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_user, size: 13, color: badgeColor),
                  const SizedBox(width: 4),
                  Text(
                    badgeLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: badgeColor,
                    ),
                  ),
                ],
              ),
            );
          }

          // Quotation job: show quotation status chip
          if (job.jobType == JobType.quotation) {
            final qStatus = job.quotationStatus ?? QuotationStatus.pending;
            final Color badgeColor;
            switch (qStatus) {
              case QuotationStatus.approved:
                badgeColor = Colors.green;
                break;
              case QuotationStatus.rejected:
              case QuotationStatus.expired:
                badgeColor = Colors.red;
                break;
              case QuotationStatus.pending:
                badgeColor = Colors.orange;
                break;
            }
            return InkWell(
              onTap: () => _createInvoiceForJob(job),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: badgeColor.withValues(alpha: 0.4), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.request_quote, size: 13, color: badgeColor),
                    const SizedBox(width: 4),
                    Text(
                      'Presupuesto',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: badgeColor,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

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
        final status = invoice?.status ?? InvoiceStatus.draft;

        // Define colors and labels for each status
        Color bgColor;
        Color borderColor;
        Color textColor;
        IconData icon;
        String label;

        switch (status) {
          case InvoiceStatus.draft:
            bgColor = Colors.grey.shade100;
            borderColor = Colors.grey.shade300;
            textColor = Colors.grey.shade700;
            icon = Icons.edit_note;
            label = 'BORRADOR';
            break;
          case InvoiceStatus.sent:
            bgColor = Colors.blue.shade50;
            borderColor = Colors.blue.shade300;
            textColor = Colors.blue.shade800;
            icon = Icons.send;
            label = 'ENVIADO';
            break;
          case InvoiceStatus.confirmed:
            bgColor = Colors.purple.shade50;
            borderColor = Colors.purple.shade300;
            textColor = Colors.purple.shade800;
            icon = Icons.check_circle_outline;
            label = 'CONFIRMADO';
            break;
          case InvoiceStatus.paid:
            bgColor = Colors.green.shade50;
            borderColor = Colors.green.shade300;
            textColor = Colors.green.shade800;
            icon = Icons.check_circle;
            label = 'PAGADO';
            break;
          case InvoiceStatus.overdue:
            bgColor = Colors.orange.shade50;
            borderColor = Colors.orange.shade300;
            textColor = Colors.orange.shade800;
            icon = Icons.schedule;
            label = 'VENCIDO';
            break;
          case InvoiceStatus.cancelled:
            bgColor = Colors.red.shade50;
            borderColor = Colors.red.shade300;
            textColor = Colors.red.shade800;
            icon = Icons.cancel;
            label = 'CANCELADO';
            break;
        }

        return InkWell(
          onTap:
              job.invoiceId != null ? () => _openInvoice(job.invoiceId!) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            constraints: const BoxConstraints(maxWidth: 110),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: borderColor,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: textColor,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      decoration: job.invoiceId != null
                          ? TextDecoration.underline
                          : null,
                      decorationColor: textColor.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

      case 'attachments':
        final imageUrl = job.imageUrls.isNotEmpty ? job.imageUrls.first : null;
        final count = job.imageUrls.length;
        final isImg = imageUrl != null ? _isImage(imageUrl) : false;
        final isDroppingOnThis = _draggingJobId == job.id;

        return DropTarget(
          onDragDone: (details) => _handleDrop(job, details),
          onDragEntered: (_) => setState(() => _draggingJobId = job.id),
          onDragExited: (_) => setState(() {
            if (_draggingJobId == job.id) _draggingJobId = null;
          }),
          child: InkWell(
            onTap: () => _pickFileForJob(job),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              decoration: isDroppingOnThis
                  ? BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.2),
                      border: Border.all(color: Colors.blue, width: 2),
                      borderRadius: BorderRadius.circular(4),
                    )
                  : null,
              padding: const EdgeInsets.all(2),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 56),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (imageUrl != null) ...[
                      isImg
                          ? HoverZoomImage(imageUrl: imageUrl, size: 32)
                          : Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: const Icon(Icons.insert_drive_file,
                                  size: 16, color: Colors.blueGrey),
                            ),
                      if (count > 1) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '+${count - 1}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ] else
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: Colors.grey.shade300,
                              style: BorderStyle.solid),
                          borderRadius: BorderRadius.circular(4),
                          color: Colors.grey.shade50,
                        ),
                        child: Center(
                          child: Icon(Icons.add,
                              size: 16, color: Colors.grey.shade400),
                        ),
                      ),
                  ],
                ),
              ), // ConstrainedBox
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
                if (job.jobType == JobType.warranty ||
                    job.jobType == JobType.quotation)
                  const PopupMenuItem(
                    value: 'convert',
                    child: Row(
                      children: [
                        Icon(Icons.transform, size: 18),
                        SizedBox(width: 8),
                        Text('Convertir a Normal'),
                      ],
                    ),
                  ),
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
                if (value == 'convert') {
                  _convertToService(job);
                } else if (value == 'complete') {
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

  Widget _buildJobBikeSubRow({
    required MechanicJob job,
    required Customer? customer,
    required MechanicJobBike jb,
    required int index,
    required int total,
    required double tableWidth,
  }) {
    // Get the bike for this job-bike entry
    final bike = jb.bike ?? _bikes[jb.bikeId];
    final isSelected = _selectedJob?.id == job.id;

    // Use the EXACT same row structure as main row but with distinct background
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
          // Slightly different background for expanded sub-rows
          color: isSelected
              ? Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.3)
              : Theme.of(context).colorScheme.surfaceContainerLow,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Row(
          // Use the EXACT same _buildDataCell method but with jobBike for per-bike data
          children: _displayColumns.map((col) {
            return _buildDataCell(col, job, customer, bike, null, jobBike: jb);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildExpandedJobBikes({
    required MechanicJob job,
    required Customer? customer,
    required List<MechanicJobBike> jobBikes,
    required double tableWidth,
  }) {
    // Show ALL bikes as expanded sub-rows (main row is now a summary)
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < jobBikes.length; i++)
          _buildJobBikeSubRow(
            job: job,
            customer: customer,
            jb: jobBikes[i],
            index: i + 1, // Display as "Bici 1", "Bici 2", etc.
            total: jobBikes.length,
            tableWidth: tableWidth,
          ),
      ],
    );
  }

  // ========== STATUS FILTER BUTTON ==========

  // ignore: unused_element
  Color _getStatusColorForFilter(JobStatus status) {
    switch (status) {
      case JobStatus.pendiente:
        return Colors.grey;
      case JobStatus.diagnostico:
        return Colors.blue;
      case JobStatus.esperandoAprobacion:
        return Colors.amber.shade700;
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

  String _getStatusLabel(JobStatus status) {
    switch (status) {
      case JobStatus.pendiente:
        return 'Pendiente';
      case JobStatus.diagnostico:
        return 'Diagnóstico';
      case JobStatus.esperandoAprobacion:
        return 'Esperando Aprob.';
      case JobStatus.esperandoRepuestos:
        return 'Esp. Repuestos';
      case JobStatus.enCurso:
        return 'En Curso';
      case JobStatus.finalizado:
        return 'Finalizado';
      case JobStatus.entregado:
        return 'Entregado';
      case JobStatus.cancelado:
        return 'Cancelado';
    }
  }

  final GlobalKey _statusFilterKey = GlobalKey();

  Widget _buildStatusFilterButton() {
    final hasFilter = _customStatusFilter.isNotEmpty;

    return InkWell(
      key: _statusFilterKey,
      onTap: () => _showStatusFilterMenu(),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).dividerColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.circle_outlined,
              size: 16,
              color: Theme.of(context).iconTheme.color,
            ),
            const SizedBox(width: 6),
            Text(
              hasFilter
                  ? (_statusFilterExcludeMode
                      ? 'Estado ≠ ${_customStatusFilter.length}'
                      : 'Estado (${_customStatusFilter.length})')
                  : 'Estado',
              style: TextStyle(
                fontSize: 13,
                fontWeight: hasFilter ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: Theme.of(context).iconTheme.color,
            ),
          ],
        ),
      ),
    );
  }

  void _showStatusFilterMenu() {
    final RenderBox button =
        _statusFilterKey.currentContext!.findRenderObject() as RenderBox;
    final Offset buttonPosition = button.localToGlobal(Offset.zero);
    final Size buttonSize = button.size;

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return Stack(
              children: [
                // Dismiss on tap outside
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(dialogContext),
                    child: Container(color: Colors.transparent),
                  ),
                ),
                // Menu positioned below the button
                Positioned(
                  left: buttonPosition.dx,
                  top: buttonPosition.dy + buttonSize.height + 4,
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 220,
                      constraints: const BoxConstraints(maxHeight: 400),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Header
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                            child: Row(
                              children: [
                                const Text(
                                  'Filtrar por Estado',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13),
                                ),
                                const Spacer(),
                                if (_customStatusFilter.isNotEmpty)
                                  TextButton(
                                    onPressed: () {
                                      setState(
                                          () => _customStatusFilter.clear());
                                      setDialogState(() {});
                                      _applyFiltersAndSort();
                                    },
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text('Limpiar',
                                        style: TextStyle(fontSize: 12)),
                                  ),
                              ],
                            ),
                          ),
                          // Is / Is Not toggle
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            child: SegmentedButton<bool>(
                              segments: const [
                                ButtonSegment<bool>(
                                  value: false,
                                  label: Text('Es',
                                      style: TextStyle(fontSize: 12)),
                                  icon: Icon(Icons.check_circle_outline,
                                      size: 16),
                                ),
                                ButtonSegment<bool>(
                                  value: true,
                                  label: Text('No es',
                                      style: TextStyle(fontSize: 12)),
                                  icon: Icon(Icons.cancel_outlined, size: 16),
                                ),
                              ],
                              selected: {_statusFilterExcludeMode},
                              onSelectionChanged: (Set<bool> newSelection) {
                                setState(() {
                                  _statusFilterExcludeMode = newSelection.first;
                                });
                                setDialogState(() {});
                                _applyFiltersAndSort();
                              },
                              style: const ButtonStyle(
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                          // Status list - uses custom statuses from JobStatusService
                          Flexible(
                            child: SingleChildScrollView(
                              child: ListenableBuilder(
                                listenable: _jobStatusService,
                                builder: (context, _) {
                                  final customStatuses =
                                      _jobStatusService.activeStatuses;
                                  if (customStatuses.isEmpty) {
                                    // Fallback to legacy enum if no custom statuses
                                    return Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: JobStatus.values.map((status) {
                                        final statusCode =
                                            status.name.toUpperCase();
                                        final isSelected = _customStatusFilter
                                            .contains(statusCode);
                                        final statusColor =
                                            _getLegacyStatusColor(status);

                                        return InkWell(
                                          onTap: () {
                                            setState(() {
                                              if (_customStatusFilter
                                                  .contains(statusCode)) {
                                                _customStatusFilter
                                                    .remove(statusCode);
                                              } else {
                                                _customStatusFilter
                                                    .add(statusCode);
                                              }
                                            });
                                            setDialogState(() {});
                                            _applyFiltersAndSort();
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 16, vertical: 10),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 20,
                                                  height: 20,
                                                  decoration: BoxDecoration(
                                                    color: isSelected
                                                        ? statusColor
                                                        : Colors.transparent,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                    border: Border.all(
                                                      color: isSelected
                                                          ? statusColor
                                                          : Colors
                                                              .grey.shade400,
                                                      width: 1.5,
                                                    ),
                                                  ),
                                                  child: isSelected
                                                      ? const Icon(Icons.check,
                                                          size: 14,
                                                          color: Colors.white)
                                                      : null,
                                                ),
                                                const SizedBox(width: 12),
                                                Container(
                                                  width: 10,
                                                  height: 10,
                                                  decoration: BoxDecoration(
                                                    color: statusColor,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  _getStatusLabel(status),
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: isSelected
                                                        ? FontWeight.w600
                                                        : FontWeight.normal,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    );
                                  }

                                  // Use custom statuses grouped by phase
                                  return Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      for (final phase
                                          in StatusPhase.values) ...[
                                        if (_jobStatusService
                                                .statusesByPhase[phase]
                                                ?.isNotEmpty ??
                                            false) ...[
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 16, vertical: 8),
                                            child: Text(
                                              phase.displayName.toUpperCase(),
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.grey.shade500,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                          ...(_jobStatusService
                                                      .statusesByPhase[phase] ??
                                                  [])
                                              .map((status) {
                                            final isSelected =
                                                _customStatusFilter
                                                    .contains(status.id);
                                            final statusColor =
                                                status.colorValue;

                                            return InkWell(
                                              onTap: () {
                                                setState(() {
                                                  if (_customStatusFilter
                                                      .contains(status.id)) {
                                                    _customStatusFilter
                                                        .remove(status.id);
                                                  } else {
                                                    _customStatusFilter
                                                        .add(status.id!);
                                                  }
                                                });
                                                setDialogState(() {});
                                                _applyFiltersAndSort();
                                              },
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 16,
                                                        vertical: 10),
                                                child: Row(
                                                  children: [
                                                    Container(
                                                      width: 20,
                                                      height: 20,
                                                      decoration: BoxDecoration(
                                                        color: isSelected
                                                            ? statusColor
                                                            : Colors
                                                                .transparent,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(4),
                                                        border: Border.all(
                                                          color: isSelected
                                                              ? statusColor
                                                              : Colors.grey
                                                                  .shade400,
                                                          width: 1.5,
                                                        ),
                                                      ),
                                                      child: isSelected
                                                          ? const Icon(
                                                              Icons.check,
                                                              size: 14,
                                                              color:
                                                                  Colors.white)
                                                          : null,
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Container(
                                                      width: 10,
                                                      height: 10,
                                                      decoration: BoxDecoration(
                                                        color: statusColor,
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      status.name,
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight: isSelected
                                                            ? FontWeight.w600
                                                            : FontWeight.normal,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          }),
                                        ],
                                      ],
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showColumnCustomizer() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
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
                  setDialogState(() {});
                  _saveColumnOrder(); // Save the new column order
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
                    onChanged:
                        col.id == 'job_number' // Always keep job number visible
                            ? null
                            : (value) {
                                setState(() => col.visible = value ?? true);
                                setDialogState(() {});
                                _saveColumnOrder();
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
          );
        },
      ),
    );
  }

  void _createInvoiceForJob(MechanicJob job) {
    context.push(
        '/sales/invoices/new?job_id=${job.id}&customer_id=${job.customerId}');
  }

  Future<void> _convertToService(MechanicJob job) async {
    final typeLabel =
        job.jobType == JobType.warranty ? 'garantía' : 'presupuesto';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.transform, size: 28),
        title: const Text('Convertir a Servicio Cobrable'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${job.jobNumber} dejará de ser un trabajo de $typeLabel y pasará a ser un '
              'servicio normal cobrable al cliente.',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Podrás generar la factura inmediatamente después.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.transform, size: 16),
            label: const Text('Convertir'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      _startLocalOperation();
      try {
        final updated = await _bikeshopService.convertToServiceJob(job.id!);
        if (mounted) {
          // Optimistic update in local list
          setState(() {
            final index = _jobs.indexWhere((j) => j.id == job.id);
            if (index != -1) _jobs[index] = updated;
            _applyFiltersAndSort();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${job.jobNumber} convertido a servicio cobrable'),
              duration: const Duration(seconds: 8),
              backgroundColor: Colors.green.shade700,
              action: SnackBarAction(
                label: 'Generar Factura',
                textColor: Colors.white,
                onPressed: () => context.push(
                  '/sales/invoices/new?job_id=${job.id}&customer_id=${job.customerId}',
                ),
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error al convertir: $e'),
                backgroundColor: Colors.red),
          );
        }
      } finally {
        _endLocalOperation();
      }
    }
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
      // Start local operation to suppress reload from realtime notifications
      _startLocalOperation();

      // Optimistic update
      setState(() {
        final index = _jobs.indexWhere((j) => j.id == job.id);
        if (index != -1) {
          final updatedJob = _jobs[index];
          _jobs[index] = MechanicJob(
            id: updatedJob.id,
            tenantId: updatedJob.tenantId,
            jobNumber: updatedJob.jobNumber,
            customerId: updatedJob.customerId,
            bikeId: updatedJob.bikeId,
            status: JobStatus.finalizado,
            priority: updatedJob.priority,
            arrivalDate: updatedJob.arrivalDate,
            diagnosticDeadline: updatedJob.diagnosticDeadline,
            deliveryDeadline: updatedJob.deliveryDeadline,
            diagnosticSentAt: updatedJob.diagnosticSentAt,
            startedAt: updatedJob.startedAt,
            completedAt: DateTime.now(),
            deliveredAt: updatedJob.deliveredAt,
            clientRequest: updatedJob.clientRequest,
            diagnosis: updatedJob.diagnosis,
            workPerformed: updatedJob.workPerformed,
            notes: updatedJob.notes,
            assignedTo: updatedJob.assignedTo,
            assignedTechnicianName: updatedJob.assignedTechnicianName,
            estimatedCost: updatedJob.estimatedCost,
            finalCost: updatedJob.finalCost,
            partsCost: updatedJob.partsCost,
            laborCost: updatedJob.laborCost,
            discountAmount: updatedJob.discountAmount,
            taxAmount: updatedJob.taxAmount,
            totalCost: updatedJob.totalCost,
            taxTreatment: updatedJob.taxTreatment,
            invoiceId: updatedJob.invoiceId,
            isInvoiced: updatedJob.isInvoiced,
            isPaid: updatedJob.isPaid,
            isWarrantyJob: updatedJob.isWarrantyJob,
            warrantyNotes: updatedJob.warrantyNotes,
            requiresApproval: updatedJob.requiresApproval,
            approvedByCustomer: updatedJob.approvedByCustomer,
            approvedAt: updatedJob.approvedAt,
            imageUrls: updatedJob.imageUrls,
            createdAt: updatedJob.createdAt,
            updatedAt: DateTime.now(),
            deletedAt: updatedJob.deletedAt,
            deletedBy: updatedJob.deletedBy,
          );
        }
        _applyFiltersAndSort();
      });

      try {
        await _bikeshopService.updateJobStatus(job.id!, JobStatus.finalizado);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Trabajo completado'),
                duration: Duration(seconds: 1)),
          );
        }
      } catch (e) {
        // Reload on error
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        _endLocalOperation();
      }
    }
  }

  Future<void> _confirmDelete(MechanicJob job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Trabajo'),
        content: Text(
            '¿Eliminar ${job.jobNumber}? Esta acción no se puede deshacer.'),
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
      // Start local operation to suppress reload from realtime notifications
      _startLocalOperation();

      // Optimistic update - remove from list immediately
      final deletedJob = job;
      setState(() {
        _jobs.removeWhere((j) => j.id == job.id);
        _applyFiltersAndSort();
      });

      try {
        await _bikeshopService.deleteJob(job.id!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Trabajo eliminado'),
                duration: Duration(seconds: 1)),
          );
        }
      } catch (e) {
        // Restore on error
        if (mounted) {
          setState(() {
            _jobs.add(deletedJob);
            _applyFiltersAndSort();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        _endLocalOperation();
      }
    }
  }

  // Interactive cell methods
  void _showStatusMenu(MechanicJob job) {
    showDialog(
      context: context,
      builder: (dialogContext) => _StatusManagerDialog(
        job: job,
        jobStatusService: _jobStatusService,
        onStatusSelected: (status) async {
          Navigator.pop(dialogContext);
          await _updateJobToCustomStatus(job, status);
        },
        onWarrantyOutcomeSelected: (outcome) async {
          Navigator.pop(dialogContext);
          _startLocalOperation();
          try {
            await _bikeshopService.updateWarrantyOutcome(job.id!, outcome);
            if (mounted) {
              setState(() {
                final index = _jobs.indexWhere((j) => j.id == job.id);
                if (index != -1) {
                  _jobs[index] = job.copyWith(
                      warrantyOutcome: outcome, updatedAt: DateTime.now());
                }
                _applyFiltersAndSort();
              });
              // When warranty is rejected, offer to convert to a paid service job
              if (outcome == WarrantyOutcome.notCovered) {
                showDialog<void>(
                  context: context,
                  barrierColor: Colors.transparent,
                  builder: (ctx) => _NotCoveredConvertDialog(
                    jobNumber: job.jobNumber ?? '',
                    onConvert: () {
                      Navigator.pop(ctx);
                      final current = _jobs.firstWhere(
                        (j) => j.id == job.id,
                        orElse: () => job,
                      );
                      _convertToService(current);
                    },
                    onDismiss: () => Navigator.pop(ctx),
                  ),
                );
              }
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Error: $e'), backgroundColor: Colors.red));
            }
          } finally {
            _endLocalOperation();
          }
        },
        onQuotationStatusSelected: (qStatus) async {
          Navigator.pop(dialogContext);
          _startLocalOperation();
          try {
            await _bikeshopService.updateQuotationStatus(job.id!, qStatus);
            if (mounted) {
              setState(() {
                final index = _jobs.indexWhere((j) => j.id == job.id);
                if (index != -1) {
                  _jobs[index] = job.copyWith(
                      quotationStatus: qStatus, updatedAt: DateTime.now());
                }
                _applyFiltersAndSort();
              });
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Error: $e'), backgroundColor: Colors.red));
            }
          } finally {
            _endLocalOperation();
          }
        },
      ),
    );
  }

  Future<void> _updateJobToCustomStatus(
      MechanicJob job, JobStatusCustom newStatus) async {
    // Start local operation to suppress reload from realtime notifications
    _startLocalOperation();

    // Map custom status code to legacy JobStatus for backward compatibility
    final legacyStatus = _mapCodeToLegacyStatus(newStatus.code);
    final oldStatusId = job.statusId;
    final oldStatus = job.status;
    final oldCustomStatus = job.customStatus;

    // Optimistic update
    setState(() {
      final index = _jobs.indexWhere((j) => j.id == job.id);
      if (index != -1) {
        _jobs[index] = job.copyWith(
          statusId: newStatus.id,
          customStatus: newStatus,
          status: legacyStatus,
          updatedAt: DateTime.now(),
        );
      }
      _applyFiltersAndSort();
    });

    // Update in background
    try {
      final success =
          await _jobStatusService.updateJobStatus(job.id!, newStatus.id!);

      if (!success) {
        // Update returned false - revert the optimistic update
        throw Exception('Error al guardar en la base de datos');
      }

      // Also invalidate bikeshop service cache to ensure fresh data on next load
      _bikeshopService.invalidateJobsCache();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Estado actualizado a ${newStatus.name}'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      // Revert on error
      debugPrint(
          '❌ [_updateJobToCustomStatus] Error: $e - reverting optimistic update');
      if (mounted) {
        setState(() {
          final index = _jobs.indexWhere((j) => j.id == job.id);
          if (index != -1) {
            _jobs[index] = job.copyWith(
              statusId: oldStatusId,
              customStatus: oldCustomStatus,
              status: oldStatus,
            );
          }
          _applyFiltersAndSort();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // Always end the local operation, whether success or failure
      _endLocalOperation();
    }
  }

  /// Show status menu for a specific bike in a multi-bike job
  void _showBikeStatusMenu(MechanicJob job, MechanicJobBike jobBike) {
    showDialog(
      context: context,
      builder: (dialogContext) => _StatusManagerDialog(
        job: job,
        jobStatusService: _jobStatusService,
        onStatusSelected: (status) async {
          Navigator.pop(dialogContext);
          await _updateJobBikeToCustomStatus(job, jobBike, status);
        },
      ),
    );
  }

  /// Update the status of a specific bike in a multi-bike job
  Future<void> _updateJobBikeToCustomStatus(MechanicJob job,
      MechanicJobBike jobBike, JobStatusCustom newStatus) async {
    // Start local operation to suppress reload from realtime notifications
    _startLocalOperation();

    final oldStatusId = jobBike.statusId;
    final oldCustomStatus = jobBike.customStatus;

    // Create updated MechanicJobBike with new status
    final updatedJobBike = jobBike.copyWith(
      statusId: newStatus.id,
      customStatus: newStatus,
    );

    // Optimistic update in local cache
    final jobId = job.id;
    if (jobId != null && _jobBikesMap.containsKey(jobId)) {
      final bikes = _jobBikesMap[jobId]!;
      final index = bikes.indexWhere((b) => b.id == jobBike.id);
      if (index != -1) {
        setState(() {
          bikes[index] = updatedJobBike;
        });
      }
    }

    // Save in background
    try {
      await _bikeshopService.updateJobBike(updatedJobBike);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Estado de bicicleta actualizado a ${newStatus.name}'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      // Revert on error
      debugPrint(
          '❌ [_updateJobBikeToCustomStatus] Error: $e - reverting optimistic update');
      if (jobId != null && _jobBikesMap.containsKey(jobId)) {
        final bikes = _jobBikesMap[jobId]!;
        final index = bikes.indexWhere((b) => b.id == jobBike.id);
        if (index != -1) {
          setState(() {
            bikes[index] = jobBike.copyWith(
              statusId: oldStatusId,
              customStatus: oldCustomStatus,
            );
          });
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      _endLocalOperation();
    }
  }

  /// Maps custom status code to legacy JobStatus enum for backward compatibility
  JobStatus _mapCodeToLegacyStatus(String code) {
    switch (code.toLowerCase()) {
      case 'pendiente':
        return JobStatus.pendiente;
      case 'diagnostico':
        return JobStatus.diagnostico;
      case 'esperando_aprobacion':
        return JobStatus.esperandoAprobacion;
      case 'en_curso':
        return JobStatus.enCurso;
      case 'esperando_repuestos':
        return JobStatus.esperandoRepuestos;
      case 'finalizado':
        return JobStatus.finalizado;
      case 'entregado':
        return JobStatus.entregado;
      case 'cancelado':
        return JobStatus.cancelado;
      default:
        return JobStatus.pendiente; // Default fallback
    }
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

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Re-fetch bikes to ensure we have latest data after edits
            final bikes = _bikes.values
                .where((b) => b.customerId == customer.id)
                .toList();

            return AlertDialog(
              title: const Text('Seleccionar Bicicleta'),
              content: SizedBox(
                width: 400,
                child: bikes.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.pedal_bike_outlined,
                                size: 48, color: Colors.grey),
                            SizedBox(height: 16),
                            Text(
                              'Este cliente no tiene bicicletas registradas',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: bikes.map((bike) {
                            final isSelected = bike.id == job.bikeId;
                            final bikeName =
                                '${bike.brand ?? ''} ${bike.model ?? ''}'
                                    .trim();
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
                                  fontWeight:
                                      isSelected ? FontWeight.bold : null,
                                ),
                              ),
                              subtitle: bike.serialNumber != null
                                  ? Text('N° Serie: ${bike.serialNumber}')
                                  : null,
                              trailing: isSelected
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit,
                                              size: 20, color: Colors.blue),
                                          tooltip: 'Editar detalles',
                                          onPressed: () async {
                                            // Edit bike
                                            final updatedBike =
                                                await showDialog<Bike>(
                                              context: context,
                                              builder: (context) =>
                                                  BikeFormDialog(
                                                customerId: customer.id!,
                                                bike: bike,
                                              ),
                                            );

                                            if (updatedBike != null &&
                                                mounted) {
                                              // Update local state
                                              setState(() {
                                                if (updatedBike.id != null) {
                                                  _bikes[updatedBike.id!] =
                                                      updatedBike;
                                                }
                                                // If this was the selected bike, force table refresh
                                                if (isSelected) {
                                                  _applyFiltersAndSort();
                                                }
                                              });
                                              // Refresh dialog state
                                              setDialogState(() {});
                                            }
                                          },
                                        ),
                                        Icon(Icons.check_circle,
                                            color: Colors.green.shade700),
                                      ],
                                    )
                                  : null,
                              selected: isSelected,
                              onTap: isSelected
                                  ? () async {
                                      // Allow editing by tapping the row too (UX convenience)
                                      final updatedBike =
                                          await showDialog<Bike>(
                                        context: context,
                                        builder: (context) => BikeFormDialog(
                                          customerId: customer.id!,
                                          bike: bike,
                                        ),
                                      );

                                      if (updatedBike != null && mounted) {
                                        setState(() {
                                          if (updatedBike.id != null) {
                                            _bikes[updatedBike.id!] =
                                                updatedBike;
                                          }
                                          _applyFiltersAndSort();
                                        });
                                        setDialogState(() {});
                                      }
                                    }
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
                                          diagnosticDeadline:
                                              job.diagnosticDeadline,
                                          deliveryDeadline:
                                              job.deliveryDeadline,
                                          diagnosticSentAt:
                                              job.diagnosticSentAt,
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
                                          // Keep other fields
                                          assignedTo: job.assignedTo,
                                          assignedTechnicianName:
                                              job.assignedTechnicianName,
                                          servicePackageId:
                                              job.servicePackageId,
                                          taxAmount: job.taxAmount,
                                          discountAmount: job.discountAmount,
                                          taxTreatment: job.taxTreatment,
                                          isInvoiced: job.isInvoiced,
                                          isPaid: job.isPaid,
                                          isWarrantyJob: job.isWarrantyJob,
                                          warrantyNotes: job.warrantyNotes,
                                          requiresApproval:
                                              job.requiresApproval,
                                          approvedByCustomer:
                                              job.approvedByCustomer,
                                          approvedAt: job.approvedAt,
                                          imageUrls: job.imageUrls,
                                          deletedAt: job.deletedAt,
                                          deletedBy: job.deletedBy,
                                        );

                                        // Optimistic update
                                        _startLocalOperation();
                                        setState(() {
                                          final index = _jobs.indexWhere(
                                              (j) => j.id == job.id);
                                          if (index != -1) {
                                            _jobs[index] = updatedJob;
                                          }
                                          _bikes[bike.id!] = bike;
                                          _applyFiltersAndSort();
                                        });

                                        // Save in background
                                        try {
                                          await _bikeshopService
                                              .updateJob(updatedJob);
                                          if (mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                    'Bicicleta cambiada a: $bikeName'),
                                                duration:
                                                    const Duration(seconds: 1),
                                              ),
                                            );
                                          }
                                        } catch (e) {
                                          // Revert on error
                                          if (mounted) {
                                            await _loadData();
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text('Error: $e'),
                                                backgroundColor: Colors.red,
                                              ),
                                            );
                                          }
                                        } finally {
                                          _endLocalOperation();
                                        }
                                      } catch (e) {
                                        debugPrint('Error changing bike: $e');
                                      }
                                    },
                            );
                          }).toList(),
                        ),
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    // Create new bike
                    final newBike = await showDialog<Bike>(
                      context: context,
                      builder: (context) => BikeFormDialog(
                        customerId: customer.id!,
                      ),
                    );

                    if (newBike != null && mounted) {
                      setState(() {
                        if (newBike.id != null) {
                          _bikes[newBike.id!] = newBike;
                        }
                      });
                      setDialogState(() {});
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Nueva Bici'),
                ),
              ],
            );
          },
        );
      },
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
                constraints:
                    const BoxConstraints(maxWidth: 600, maxHeight: 600),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
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
                          Icon(Icons.broken_image,
                              size: 64, color: Colors.white54),
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

  /// Shows dialog to edit both diagnostic and delivery deadlines
  Future<void> _showDualDeadlineDialog(MechanicJob job) async {
    DateTime? diagnosticDeadline = job.diagnosticDeadline;
    DateTime? deliveryDeadline = job.deliveryDeadline;

    final result = await showDialog<Map<String, DateTime?>>(
      context: context,
      builder: (ctx) => _DualDeadlineDialog(
        diagnosticDeadline: diagnosticDeadline,
        deliveryDeadline: deliveryDeadline,
      ),
    );

    if (result == null) return;
    if (!mounted) return;

    final newDiagnostic = result['diagnostic'];
    final newDelivery = result['delivery'];

    // Check if anything changed
    if (newDiagnostic == job.diagnosticDeadline &&
        newDelivery == job.deliveryDeadline) {
      return;
    }

    // Start local operation to suppress reload
    _startLocalOperation();

    // Optimistic update
    setState(() {
      final index = _jobs.indexWhere((j) => j.id == job.id);
      if (index != -1) {
        _jobs[index] = job.copyWith(
          diagnosticDeadline: newDiagnostic,
          deliveryDeadline: newDelivery,
          updatedAt: DateTime.now(),
        );
      }
      _applyFiltersAndSort();
    });

    // Save in background
    try {
      final updatedJob = job.copyWith(
        diagnosticDeadline: newDiagnostic,
        deliveryDeadline: newDelivery,
        updatedAt: DateTime.now(),
      );
      await _bikeshopService.updateJob(updatedJob);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Plazos actualizados'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      // Revert on error
      if (mounted) {
        setState(() {
          final index = _jobs.indexWhere((j) => j.id == job.id);
          if (index != -1) {
            _jobs[index] = job;
          }
          _applyFiltersAndSort();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      _endLocalOperation();
    }
  }

  // ignore: unused_element
  void _showInvoiceGenerationDialog(MechanicJob job) {
    _createInvoiceForJob(job);
  }

  /// Infers the phase from a legacy JobStatus enum
  StatusPhase _inferPhaseFromLegacyStatus(JobStatus status) {
    switch (status) {
      case JobStatus.pendiente:
        return StatusPhase.todo;
      case JobStatus.diagnostico:
      case JobStatus.esperandoAprobacion:
      case JobStatus.enCurso:
      case JobStatus.esperandoRepuestos:
        return StatusPhase.inProgress;
      case JobStatus.finalizado:
      case JobStatus.entregado:
      case JobStatus.cancelado:
        return StatusPhase.complete;
    }
  }

  /// Formats a status timestamp into a compact, localized string
  /// Examples: "hace 2h", "hace 3d", "15 ene"
  String _formatStatusTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) {
      return 'ahora';
    } else if (diff.inMinutes < 60) {
      return 'hace ${diff.inMinutes}m';
    } else if (diff.inHours < 24) {
      return 'hace ${diff.inHours}h';
    } else if (diff.inDays < 7) {
      return 'hace ${diff.inDays}d';
    } else {
      // For older dates, show day and month
      final months = [
        'ene',
        'feb',
        'mar',
        'abr',
        'may',
        'jun',
        'jul',
        'ago',
        'sep',
        'oct',
        'nov',
        'dic'
      ];
      return '${timestamp.day} ${months[timestamp.month - 1]}';
    }
  }

  IconData _jobTypeIcon(JobType type) {
    switch (type) {
      case JobType.warranty:
        return Icons.verified_user;
      case JobType.quotation:
        return Icons.request_quote;
      case JobType.itemService:
        return Icons.build_circle;
      case JobType.service:
        return Icons.pedal_bike;
    }
  }

  /// Legacy status color mapping (for backward compatibility)
  /// Colors match the database seeded values in DEPLOY_JOB_STATUSES.sql
  Color _getLegacyStatusColor(JobStatus status) {
    switch (status) {
      case JobStatus.pendiente:
        return const Color(0xFF6B7280); // Gray - matches DB
      case JobStatus.diagnostico:
        return const Color(0xFF3B82F6); // Blue - matches DB
      case JobStatus.esperandoAprobacion:
        return const Color(0xFFF59E0B); // Amber - matches DB
      case JobStatus.esperandoRepuestos:
        return const Color(0xFFF97316); // Orange - matches DB (was purple)
      case JobStatus.enCurso:
        return const Color(0xFF8B5CF6); // Purple - matches DB (was orange)
      case JobStatus.finalizado:
        return const Color(0xFF10B981); // Green - matches DB
      case JobStatus.entregado:
        return const Color(0xFF06B6D4); // Cyan - matches DB
      case JobStatus.cancelado:
        return const Color(0xFFEF4444); // Red - matches DB
    }
  }

  // ignore: unused_element
  Color _getStatusColor(JobStatus status) {
    // Delegate to the corrected legacy color mapping
    return _getLegacyStatusColor(status);
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

  // Column visibility panel
  Widget _buildColumnVisibilityPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _columns
            .where((col) => col.id != 'checkbox' && col.id != 'status')
            .map((col) {
          return FilterChip(
            label: Text(col.label),
            selected: col.visible,
            onSelected: (selected) {
              setState(() {
                col.visible = selected;
              });
            },
          );
        }).toList(),
      ),
    );
  }

  // Export all to CSV
  void _exportAllToCSV() {
    _exportToCSV(_filteredJobs);
  }

  // Export selected to CSV
  void _exportSelectedToCSV() {
    final selectedJobs =
        _filteredJobs.where((job) => _selectedJobIds.contains(job.id)).toList();
    _exportToCSV(selectedJobs);
  }

  void _exportToCSV(List<MechanicJob> jobs) {
    final csv = StringBuffer();
    // Header
    csv.writeln(
        'N° Trabajo,Cliente,Bicicleta,Ingreso,Plazo,Estado,Prioridad,Total');
    // Rows
    for (var job in jobs) {
      final customer = _customers[job.customerId];
      final bike = _bikes[job.bikeId];
      csv.writeln([
        job.jobNumber,
        customer?.name ?? 'Sin cliente',
        bike?.displayName ?? 'Sin bicicleta',
        DateFormat('dd/MM/yyyy').format(job.arrivalDate),
        job.deliveryDeadline != null
            ? DateFormat('dd/MM/yyyy').format(job.deliveryDeadline!)
            : 'Sin plazo',
        job.status.displayName,
        job.priority.displayName,
        '\$${NumberFormat('#,###').format(job.totalCost)}',
      ].join(','));
    }

    // Download logic (copy to clipboard for web)
    Clipboard.setData(ClipboardData(text: csv.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '${jobs.length} trabajos copiados al portapapeles (formato CSV)'),
        action: SnackBarAction(
          label: 'OK',
          onPressed: () {},
        ),
      ),
    );
  }

  // Bulk update status
  Future<void> _bulkUpdateStatus() async {
    final selectedJobs =
        _filteredJobs.where((job) => _selectedJobIds.contains(job.id)).toList();
    if (selectedJobs.isEmpty) return;

    final statusesByPhase = _jobStatusService.statusesByPhase;

    final newCustomStatus = await showDialog<JobStatusCustom>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cambiar Estado'),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Por Hacer section
                if (statusesByPhase[StatusPhase.todo]?.isNotEmpty == true) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, top: 8),
                    child: Text(
                      'Por Hacer',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(dialogContext)
                            .colorScheme
                            .onSurfaceVariant,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  ...statusesByPhase[StatusPhase.todo]!
                      .map((status) => ListTile(
                            dense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            leading: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: status.colorValue,
                                shape: BoxShape.circle,
                              ),
                            ),
                            title: Text(status.name,
                                style: const TextStyle(fontSize: 14)),
                            onTap: () => Navigator.pop(dialogContext, status),
                          )),
                ],
                // En Progreso section
                if (statusesByPhase[StatusPhase.inProgress]?.isNotEmpty ==
                    true) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, top: 12),
                    child: Text(
                      'En Progreso',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(dialogContext)
                            .colorScheme
                            .onSurfaceVariant,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  ...statusesByPhase[StatusPhase.inProgress]!
                      .map((status) => ListTile(
                            dense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            leading: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: status.colorValue,
                                shape: BoxShape.circle,
                              ),
                            ),
                            title: Text(status.name,
                                style: const TextStyle(fontSize: 14)),
                            onTap: () => Navigator.pop(dialogContext, status),
                          )),
                ],
                // Completado section
                if (statusesByPhase[StatusPhase.complete]?.isNotEmpty ==
                    true) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, top: 12),
                    child: Text(
                      'Completado',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(dialogContext)
                            .colorScheme
                            .onSurfaceVariant,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  ...statusesByPhase[StatusPhase.complete]!
                      .map((status) => ListTile(
                            dense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            leading: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: status.colorValue,
                                shape: BoxShape.circle,
                              ),
                            ),
                            title: Text(status.name,
                                style: const TextStyle(fontSize: 14)),
                            onTap: () => Navigator.pop(dialogContext, status),
                          )),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

    if (newCustomStatus == null) return;

    // Map to legacy status for backward compatibility
    final legacyStatus = _mapCodeToLegacyStatus(newCustomStatus.code);

    // Start local operation to suppress reload from realtime notifications
    _startLocalOperation();

    // Optimistic update - update all selected jobs immediately
    setState(() {
      for (var job in selectedJobs) {
        final index = _jobs.indexWhere((j) => j.id == job.id);
        if (index != -1) {
          _jobs[index] = job.copyWith(
            statusId: newCustomStatus.id,
            customStatus: newCustomStatus,
            status: legacyStatus,
            updatedAt: DateTime.now(),
          );
        }
      }
      _selectedJobIds.clear();
      _applyFiltersAndSort();
    });

    // Save in background
    try {
      for (var job in selectedJobs) {
        await _jobStatusService.updateJobStatus(job.id!, newCustomStatus.id!);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${selectedJobs.length} trabajos actualizados a ${newCustomStatus.name}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 1),
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
    } finally {
      _endLocalOperation();
    }
  }

  // ========== VIEW MODE SWITCHER ==========
  Widget _buildViewContent() {
    switch (_viewMode) {
      case 'board':
        return _buildBoardView();
      case 'calendar':
        return _buildCalendarView();
      case 'gantt':
        return _buildGanttView();
      case 'tasks':
        return _buildTasksView();
      case 'table':
      default:
        return _buildDataTable();
    }
  }

  // ========== TASKS VIEW ==========
  Widget _buildTasksView() {
    return const PegasTasksWidget();
  }

  // ========== BOARD VIEW (Kanban) ==========
  Widget _buildBoardView() {
    // Use custom statuses from JobStatusService, grouped by phase
    return ListenableBuilder(
      listenable: _jobStatusService,
      builder: (context, _) {
        final customStatuses = _jobStatusService.activeStatuses;

        if (customStatuses.isEmpty) {
          // Fallback to legacy statuses if no custom statuses
          final legacyStatuses = [
            JobStatus.pendiente,
            JobStatus.diagnostico,
            JobStatus.esperandoRepuestos,
            JobStatus.enCurso,
            JobStatus.finalizado,
            JobStatus.entregado,
          ];

          // Build columns and filter out empty ones
          final columns = <Widget>[];
          for (final status in legacyStatuses) {
            final jobsInStatus =
                _filteredJobs.where((j) => j.status == status).toList();
            // Only show columns with jobs
            if (jobsInStatus.isNotEmpty) {
              columns.add(_buildLegacyBoardColumn(status, jobsInStatus));
            }
          }

          if (columns.isEmpty) {
            return const Center(
              child: Text('No hay trabajos que mostrar',
                  style: TextStyle(color: Colors.grey)),
            );
          }

          return Align(
            alignment: Alignment.topLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: columns,
              ),
            ),
          );
        }

        // Use custom statuses - only show columns with jobs
        final columns = <Widget>[];
        for (final customStatus in customStatuses) {
          final jobsInStatus = _filteredJobs
              .where((j) =>
                  j.statusId == customStatus.id ||
                  (j.statusId == null &&
                      j.status.name.toUpperCase() == customStatus.code))
              .toList();
          // Only show columns with jobs
          if (jobsInStatus.isNotEmpty) {
            columns.add(_buildCustomBoardColumn(customStatus, jobsInStatus));
          }
        }

        if (columns.isEmpty) {
          return const Center(
            child: Text('No hay trabajos que mostrar',
                style: TextStyle(color: Colors.grey)),
          );
        }

        return Align(
          alignment: Alignment.topLeft,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: columns,
            ),
          ),
        );
      },
    );
  }

  /// Board column for custom status
  Widget _buildCustomBoardColumn(
      JobStatusCustom status, List<MechanicJob> jobs) {
    final statusColor = status.colorValue;
    final bgColor = Color.lerp(statusColor, Colors.white, 0.85)!;

    return Container(
      width: 320,
      margin: const EdgeInsets.only(right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Column header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    status.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: statusColor.computeLuminance() > 0.5
                          ? Colors.black87
                          : statusColor,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${jobs.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Cards
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(12)),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: jobs.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Sin trabajos',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: jobs.length,
                      itemBuilder: (context, index) {
                        final job = jobs[index];
                        return _buildBoardCard(job);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// Legacy board column (fallback when no custom statuses)
  Widget _buildLegacyBoardColumn(JobStatus status, List<MechanicJob> jobs) {
    final statusColors = {
      JobStatus.pendiente: Colors.blue[100],
      JobStatus.diagnostico: Colors.orange[100],
      JobStatus.esperandoRepuestos: Colors.purple[100],
      JobStatus.enCurso: Colors.teal[100],
      JobStatus.finalizado: Colors.green[100],
      JobStatus.entregado: Colors.grey[300],
    };

    return Container(
      width: 320,
      margin: const EdgeInsets.only(right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Column header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: statusColors[status],
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    status.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${jobs.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Cards
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(12)),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: jobs.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Sin trabajos',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: jobs.length,
                      itemBuilder: (context, index) {
                        final job = jobs[index];
                        return _buildBoardCard(job);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoardCard(MechanicJob job) {
    final customer = _customers[job.customerId];
    final bike = _bikes[job.bikeId];
    final isOverdue = job.deliveryDeadline != null &&
        job.deliveryDeadline!.isBefore(DateTime.now());

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      child: InkWell(
        onTap: () => context.push('/taller/pegas/${job.id}'),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Job number and priority
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      job.jobNumber ?? 'N/A',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[900],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (job.priority == JobPriority.urgente)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'URGENTE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.red[900],
                        ),
                      ),
                    ),
                  const Spacer(),
                  if (isOverdue)
                    Icon(Icons.warning, size: 16, color: Colors.red[700]),
                ],
              ),
              const SizedBox(height: 8),
              // Customer name
              Text(
                customer?.name ?? 'Cliente N/A',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              // Bike info
              Text(
                bike?.displayName ?? 'Bici N/A',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[700],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (job.deliveryDeadline != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 12,
                      color: isOverdue ? Colors.red[700] : Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('dd/MM/yy').format(job.deliveryDeadline!),
                      style: TextStyle(
                        fontSize: 11,
                        color: isOverdue ? Colors.red[700] : Colors.grey[700],
                        fontWeight:
                            isOverdue ? FontWeight.bold : FontWeight.normal,
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

  // ========== CALENDAR VIEW ==========
  // Uses shared PegasCalendarWidget with external data from this page
  Widget _buildCalendarView() {
    // Convert _customers map to Customer map
    final customersMap = <String, Customer>{};
    for (final entry in _customers.entries) {
      customersMap[entry.key] = entry.value;
    }

    // Convert _bikes map to Bike map
    final bikesMap = <String, Bike>{};
    for (final entry in _bikes.entries) {
      bikesMap[entry.key] = entry.value;
    }

    return PegasCalendarWidget(
      jobs: _filteredJobs,
      customers: customersMap,
      bikes: bikesMap,
      onRefreshNeeded: _loadData,
    );
  }

  // ========== GANTT VIEW (Notion-style Timeline) ==========

  Widget _buildGanttView() {
    final jobsWithDates = _filteredJobs.toList()
      ..sort((a, b) => a.arrivalDate.compareTo(b.arrivalDate));

    if (jobsWithDates.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.view_timeline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No hay trabajos para mostrar',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    // Calculate visible range (infinite scroll simulation)
    final dayWidth = _timelineScale == 'week' ? 120.0 : 40.0;
    final visibleDays =
        _timelineScale == 'week' ? 14 : 60; // 2 weeks or 2 months

    return Column(
      children: [
        // Timeline controls
        _buildTimelineControls(),
        // Timeline content
        Expanded(
          child: _buildTimelineContent(jobsWithDates, dayWidth, visibleDays),
        ),
      ],
    );
  }

  Widget _buildTimelineControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          // Month/Year display
          Text(
            DateFormat('MMMM yyyy', 'es').format(_timelineViewStart),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const Spacer(),
          // Scale toggle
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'week',
                label: Text('Semana', style: TextStyle(fontSize: 12)),
              ),
              ButtonSegment(
                value: 'month',
                label: Text('Mes', style: TextStyle(fontSize: 12)),
              ),
            ],
            selected: {_timelineScale},
            onSelectionChanged: (selected) {
              setState(() => _timelineScale = selected.first);
            },
          ),
          const SizedBox(width: 16),
          // Navigation buttons
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              setState(() {
                _timelineViewStart = _timelineViewStart.subtract(
                  Duration(days: _timelineScale == 'week' ? 7 : 30),
                );
              });
            },
            tooltip: 'Anterior',
          ),
          OutlinedButton(
            onPressed: () {
              setState(() {
                _timelineViewStart =
                    DateTime.now().subtract(const Duration(days: 7));
              });
            },
            child: const Text('Hoy'),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              setState(() {
                _timelineViewStart = _timelineViewStart.add(
                  Duration(days: _timelineScale == 'week' ? 7 : 30),
                );
              });
            },
            tooltip: 'Siguiente',
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineContent(
      List<MechanicJob> jobs, double dayWidth, int visibleDays) {
    final totalWidth = dayWidth * visibleDays;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: totalWidth + 50, // Extra padding
        child: Column(
          children: [
            // Date header
            _buildTimelineDateHeader(dayWidth, visibleDays),
            // Jobs rows
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: jobs
                      .map((job) =>
                          _buildTimelineJobRow(job, dayWidth, visibleDays))
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineDateHeader(double dayWidth, int visibleDays) {
    final dates = List.generate(
      visibleDays,
      (i) => _timelineViewStart.add(Duration(days: i)),
    );

    final today = DateTime.now();

    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: Row(
        children: dates.map((date) {
          final isToday = date.year == today.year &&
              date.month == today.month &&
              date.day == today.day;
          final isWeekend = date.weekday == DateTime.saturday ||
              date.weekday == DateTime.sunday;
          final isFirstOfMonth = date.day == 1;

          return Container(
            width: dayWidth,
            decoration: BoxDecoration(
              color: isWeekend ? Colors.grey[200] : null,
              border: Border(
                left: isFirstOfMonth
                    ? BorderSide(color: Colors.grey[400]!, width: 2)
                    : BorderSide(color: Colors.grey[300]!),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isFirstOfMonth || dates.indexOf(date) == 0)
                  Text(
                    DateFormat('MMM', 'es').format(date).toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                const SizedBox(height: 2),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isToday ? Colors.red : null,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${date.day}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isToday ? FontWeight.bold : FontWeight.normal,
                        color: isToday ? Colors.white : Colors.grey[800],
                      ),
                    ),
                  ),
                ),
                Text(
                  _getWeekdayShort(date.weekday),
                  style: TextStyle(
                    fontSize: 10,
                    color: isWeekend ? Colors.grey[500] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  String _getWeekdayShort(int weekday) {
    const days = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
    return days[weekday - 1];
  }

  Widget _buildTimelineJobRow(
      MechanicJob job, double dayWidth, int visibleDays) {
    final customer = _customers[job.customerId];
    final viewEnd = _timelineViewStart.add(Duration(days: visibleDays));

    // Calculate bar position
    final jobStart = job.arrivalDate;
    final jobEnd =
        job.deliveryDeadline ?? job.arrivalDate.add(const Duration(days: 1));

    // Check if job is visible in current view
    final isVisible =
        jobEnd.isAfter(_timelineViewStart) && jobStart.isBefore(viewEnd);

    if (!isVisible) {
      return const SizedBox.shrink(); // Hide jobs outside view
    }

    // Calculate position relative to view start
    final startDayOffset =
        jobStart.difference(_timelineViewStart).inDays.toDouble();
    final endDayOffset =
        jobEnd.difference(_timelineViewStart).inDays.toDouble() + 1;

    // Clamp to visible area
    final clampedStart = startDayOffset.clamp(0.0, visibleDays.toDouble());
    final clampedEnd = endDayOffset.clamp(0.0, visibleDays.toDouble());

    if (clampedEnd <= clampedStart) {
      return const SizedBox.shrink();
    }

    final barLeft = clampedStart * dayWidth;
    final barWidth = (clampedEnd - clampedStart) * dayWidth;

    // Determine bar color - use custom status color if available
    final isOverdue = job.deliveryDeadline != null &&
        job.deliveryDeadline!.isBefore(DateTime.now());
    final isCompleted =
        job.status == JobStatus.entregado || job.status == JobStatus.finalizado;

    Color barColor;
    if (isCompleted) {
      barColor = Colors.green[400]!;
    } else if (isOverdue) {
      barColor = Colors.red[400]!;
    } else if (job.customStatus != null) {
      // Use custom status color
      barColor = job.customStatus!.colorValue;
    } else {
      // Fallback to legacy status colors
      final statusColors = {
        JobStatus.pendiente: Colors.blue[300]!,
        JobStatus.diagnostico: Colors.orange[300]!,
        JobStatus.esperandoRepuestos: Colors.purple[300]!,
        JobStatus.enCurso: Colors.teal[300]!,
        JobStatus.esperandoAprobacion: Colors.amber[300]!,
      };
      barColor = statusColors[job.status] ?? Colors.grey[400]!;
    }

    return Container(
      height: 36,
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Stack(
        children: [
          // Grid lines (optional background)
          Row(
            children: List.generate(visibleDays, (i) {
              final date = _timelineViewStart.add(Duration(days: i));
              final isWeekend = date.weekday == DateTime.saturday ||
                  date.weekday == DateTime.sunday;
              return Container(
                width: dayWidth,
                decoration: BoxDecoration(
                  color: isWeekend ? Colors.grey[100] : null,
                  border: Border(
                    left: BorderSide(color: Colors.grey[200]!),
                  ),
                ),
              );
            }),
          ),
          // Job bar with customer name
          Positioned(
            left: barLeft,
            width: barWidth,
            top: 4,
            bottom: 4,
            child: Tooltip(
              message: '${customer?.name ?? 'N/A'}\n${job.jobNumber ?? ''}\n'
                  '${DateFormat('dd/MM').format(jobStart)} - ${DateFormat('dd/MM').format(jobEnd)}',
              child: InkWell(
                onTap: () => context.push('/taller/pegas/${job.id}'),
                child: Container(
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    customer?.name ?? 'Sin cliente',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
  final bool reorderable;

  ColumnConfig({
    required this.id,
    required this.label,
    required this.width,
    required this.minWidth,
    this.maxWidth,
    this.visible = true,
    this.sortable = true,
    this.resizable = true,
    this.reorderable = true,
  });
}

/// Inline editable job details cell with popup overlay for all text fields

// ============================================================================
// STATUS MANAGER DIALOG - Inline add/edit/delete/select statuses
// ============================================================================

class _StatusManagerDialog extends StatefulWidget {
  final MechanicJob job;
  final JobStatusService jobStatusService;
  final Function(JobStatusCustom) onStatusSelected;
  final Future<void> Function(WarrantyOutcome)? onWarrantyOutcomeSelected;
  final Future<void> Function(QuotationStatus)? onQuotationStatusSelected;

  const _StatusManagerDialog({
    required this.job,
    required this.jobStatusService,
    required this.onStatusSelected,
    this.onWarrantyOutcomeSelected,
    this.onQuotationStatusSelected,
  });

  @override
  State<_StatusManagerDialog> createState() => _StatusManagerDialogState();
}

class _StatusManagerDialogState extends State<_StatusManagerDialog> {
  bool _isEditMode = false;
  JobStatusCustom? _editingStatus;
  final _nameController = TextEditingController();
  String _selectedColor = '#6B7280';
  StatusPhase _selectedPhase = StatusPhase.inProgress;

  // 18 preset colors
  static const List<String> _colors = [
    '#6B7280',
    '#EF4444',
    '#F97316',
    '#F59E0B',
    '#EAB308',
    '#84CC16',
    '#22C55E',
    '#10B981',
    '#14B8A6',
    '#06B6D4',
    '#0EA5E9',
    '#3B82F6',
    '#6366F1',
    '#8B5CF6',
    '#A855F7',
    '#D946EF',
    '#EC4899',
    '#F43F5E',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _startEditing(JobStatusCustom? status) {
    setState(() {
      _isEditMode = true;
      _editingStatus = status;
      _nameController.text = status?.name ?? '';
      _selectedColor = status?.color ?? '#6B7280';
      _selectedPhase = status?.phase ?? StatusPhase.inProgress;
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditMode = false;
      _editingStatus = null;
      _nameController.clear();
      _selectedColor = '#6B7280';
      _selectedPhase = StatusPhase.inProgress;
    });
  }

  Future<void> _saveStatus() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    try {
      if (_editingStatus != null) {
        // Update existing
        final updated = _editingStatus!.copyWith(
          name: name,
          color: _selectedColor,
          phase: _selectedPhase,
        );
        await widget.jobStatusService.updateStatus(updated);
      } else {
        // Create new
        final code = name
            .toUpperCase()
            .replaceAll(' ', '_')
            .replaceAll(RegExp(r'[^A-Z0-9_]'), '');
        await widget.jobStatusService.createStatus(
          name: name,
          code: code,
          color: _selectedColor,
          phase: _selectedPhase,
        );
      }
      _cancelEditing();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteStatus(JobStatusCustom status) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar estado?'),
        content: Text(
            'Se eliminará "${status.name}". Los trabajos con este estado quedarán sin estado asignado.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.jobStatusService.deleteStatus(status.id!);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return const Color(0xFF6B7280);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.jobStatusService,
      builder: (context, _) {
        final statusesByPhase = widget.jobStatusService.statusesByPhase;
        final currentStatusId =
            widget.job.statusId ?? widget.job.customStatus?.id;

        return AlertDialog(
          title: Row(
            children: [
              Expanded(
                child: Text(_isEditMode
                    ? (_editingStatus != null
                        ? 'Editar Estado'
                        : 'Nuevo Estado')
                    : 'Cambiar Estado'),
              ),
              if (!_isEditMode)
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 22),
                  tooltip: 'Agregar estado',
                  onPressed: () => _startEditing(null),
                ),
            ],
          ),
          content: SizedBox(
            width: 360,
            child: _isEditMode
                ? _buildEditForm()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.job.jobType == JobType.warranty)
                        _buildWarrantyOutcomeSection(),
                      if (widget.job.jobType == JobType.quotation)
                        _buildQuotationStatusSection(),
                      if (widget.job.jobType == JobType.warranty ||
                          widget.job.jobType == JobType.quotation)
                        const Divider(height: 16),
                      Flexible(
                          child: _buildStatusList(
                              statusesByPhase, currentStatusId)),
                    ],
                  ),
          ),
          actions: _isEditMode
              ? [
                  TextButton(
                      onPressed: _cancelEditing, child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: _saveStatus, child: const Text('Guardar')),
                ]
              : [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cerrar')),
                ],
        );
      },
    );
  }

  Widget _buildWarrantyOutcomeSection() {
    final current = widget.job.warrantyOutcome ?? WarrantyOutcome.pending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Resultado de Garantía',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Row(
          children: WarrantyOutcome.values.map((outcome) {
            final isSelected = outcome == current;
            final Color color = switch (outcome) {
              WarrantyOutcome.covered => Colors.green,
              WarrantyOutcome.notCovered => Colors.red,
              WarrantyOutcome.pending => Colors.orange,
            };
            final String label = switch (outcome) {
              WarrantyOutcome.covered => 'Cubierto',
              WarrantyOutcome.notCovered => 'No cubierto',
              WarrantyOutcome.pending => 'Pendiente',
            };
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: widget.onWarrantyOutcomeSelected != null
                      ? () => widget.onWarrantyOutcomeSelected!(outcome)
                      : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? color : Colors.grey.shade300,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 18,
                          color: isSelected ? color : Colors.grey,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected ? color : Colors.grey.shade600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildQuotationStatusSection() {
    final current = widget.job.quotationStatus ?? QuotationStatus.pending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Estado del Presupuesto',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Row(
          children: QuotationStatus.values.map((qStatus) {
            final isSelected = qStatus == current;
            final Color color = switch (qStatus) {
              QuotationStatus.approved => Colors.green,
              QuotationStatus.rejected => Colors.red,
              QuotationStatus.expired => Colors.grey,
              QuotationStatus.pending => Colors.orange,
            };
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: widget.onQuotationStatusSelected != null
                      ? () => widget.onQuotationStatusSelected!(qStatus)
                      : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? color : Colors.grey.shade300,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 16,
                          color: isSelected ? color : Colors.grey,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          qStatus.displayName,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected ? color : Colors.grey.shade600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildEditForm() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name field
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nombre del estado',
              hintText: 'Ej: En Revisión',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _saveStatus(),
          ),
          const SizedBox(height: 16),

          // Phase selector
          const Text('Fase',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          const SizedBox(height: 8),
          SegmentedButton<StatusPhase>(
            segments: const [
              ButtonSegment(value: StatusPhase.todo, label: Text('Por Hacer')),
              ButtonSegment(
                  value: StatusPhase.inProgress, label: Text('En Progreso')),
              ButtonSegment(
                  value: StatusPhase.complete, label: Text('Completado')),
            ],
            selected: {_selectedPhase},
            onSelectionChanged: (selected) =>
                setState(() => _selectedPhase = selected.first),
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(height: 16),

          // Color picker
          const Text('Color',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _colors.map((color) {
              final isSelected = _selectedColor == color;
              final colorValue = _parseColor(color);
              return GestureDetector(
                onTap: () => setState(() => _selectedColor = color),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: colorValue,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.white : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                                color: colorValue.withValues(alpha: 0.5),
                                blurRadius: 8,
                                spreadRadius: 2),
                          ]
                        : null,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 18)
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Preview
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _parseColor(_selectedColor).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: _parseColor(_selectedColor).withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _parseColor(_selectedColor),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _nameController.text.isEmpty
                      ? 'Vista previa'
                      : _nameController.text,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _parseColor(_selectedColor),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusList(
      Map<StatusPhase, List<JobStatusCustom>> statusesByPhase,
      String? currentStatusId) {
    // Build a flat list with phase headers as separators
    // Each item is either a header (non-draggable) or a status (draggable)
    final List<_StatusListItem> items = [];

    // Por Hacer
    if (statusesByPhase[StatusPhase.todo]?.isNotEmpty == true) {
      items.add(_StatusListItem.header('Por Hacer', StatusPhase.todo));
      for (final status in statusesByPhase[StatusPhase.todo]!) {
        items.add(_StatusListItem.status(status));
      }
    }

    // En Progreso
    if (statusesByPhase[StatusPhase.inProgress]?.isNotEmpty == true) {
      items.add(_StatusListItem.header('En Progreso', StatusPhase.inProgress));
      for (final status in statusesByPhase[StatusPhase.inProgress]!) {
        items.add(_StatusListItem.status(status));
      }
    }

    // Completado
    if (statusesByPhase[StatusPhase.complete]?.isNotEmpty == true) {
      items.add(_StatusListItem.header('Completado', StatusPhase.complete));
      for (final status in statusesByPhase[StatusPhase.complete]!) {
        items.add(_StatusListItem.status(status));
      }
    }

    return ReorderableListView.builder(
      shrinkWrap: true,
      buildDefaultDragHandles: false,
      itemCount: items.length,
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final animValue = Curves.easeInOut.transform(animation.value);
            final elevation = lerpDouble(0, 6, animValue)!;
            return Material(
              elevation: elevation,
              borderRadius: BorderRadius.circular(8),
              child: child,
            );
          },
          child: child,
        );
      },
      onReorder: (oldIndex, newIndex) async {
        final item = items[oldIndex];
        if (item.isHeader) return; // Can't drag headers

        // Adjust newIndex
        if (newIndex > oldIndex) newIndex--;
        if (newIndex < 0) newIndex = 0;
        if (newIndex >= items.length) newIndex = items.length - 1;

        // Determine target phase based on where it's dropped
        StatusPhase targetPhase = StatusPhase.todo;
        for (int i = newIndex; i >= 0; i--) {
          if (items[i].isHeader) {
            targetPhase = items[i].phase!;
            break;
          }
        }

        // Calculate new sort order within the target phase
        int newSortOrder = 0;
        int countInPhase = 0;
        for (int i = 0; i < items.length; i++) {
          if (items[i].isHeader && items[i].phase == targetPhase) {
            // Found the target phase header, count items after it until next header or end
            for (int j = i + 1; j < items.length; j++) {
              if (items[j].isHeader) break;
              if (j < newIndex || (j == newIndex && oldIndex > newIndex)) {
                countInPhase++;
              }
            }
            newSortOrder = countInPhase;
            break;
          }
        }

        final status = item.status!;
        final jobStatusService = context.read<JobStatusService>();

        // Update the dragged status with new phase and sort order
        final updatedStatus = status.copyWith(
          phase: targetPhase,
          sortOrder: newSortOrder,
        );
        await jobStatusService.updateStatus(updatedStatus);

        // Reorder other items in the target phase to make room
        final allStatuses = jobStatusService.statuses;
        final targetPhaseStatuses = allStatuses
            .where((s) => s.phase == targetPhase && s.id != status.id)
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

        for (int i = 0; i < targetPhaseStatuses.length; i++) {
          final s = targetPhaseStatuses[i];
          final expectedOrder = i >= newSortOrder ? i + 1 : i;
          if (s.sortOrder != expectedOrder) {
            await jobStatusService
                .updateStatus(s.copyWith(sortOrder: expectedOrder));
          }
        }
      },
      itemBuilder: (context, index) {
        final item = items[index];
        if (item.isHeader) {
          return _buildPhaseHeaderItem(
            key: ValueKey('header_${item.phase}'),
            title: item.title!,
            phase: item.phase!,
          );
        } else {
          return _buildDraggableStatusTile(
            key: ValueKey(item.status!.id),
            status: item.status!,
            currentStatusId: currentStatusId,
            index: index,
          );
        }
      },
    );
  }

  Widget _buildPhaseHeaderItem({
    required Key key,
    required String title,
    required StatusPhase phase,
  }) {
    return Material(
      key: key,
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            // Quick add button for this phase
            IconButton(
              icon: const Icon(Icons.add, size: 16),
              tooltip: 'Agregar en $title',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onPressed: () {
                _selectedPhase = phase;
                _startEditing(null);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDraggableStatusTile({
    required Key key,
    required JobStatusCustom status,
    required String? currentStatusId,
    required int index,
  }) {
    final isSelected = currentStatusId == status.id;
    final statusColor = status.colorValue;

    return Material(
      key: key,
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onStatusSelected(status),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              // Drag handle
              ReorderableDragStartListener(
                index: index,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.drag_indicator,
                      size: 16,
                      color: Colors.grey[400],
                    ),
                  ),
                ),
              ),
              // Color dot
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? statusColor
                        : statusColor.withValues(alpha: 0.5),
                    width: isSelected ? 3 : 1,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Name
              Expanded(
                child: Text(
                  status.name,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? statusColor : null,
                    fontSize: 14,
                  ),
                ),
              ),
              // Edit button
              IconButton(
                icon: Icon(Icons.edit_outlined,
                    size: 16, color: Colors.grey[400]),
                tooltip: 'Editar',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () => _startEditing(status),
              ),
              // Delete button (only for non-system statuses)
              if (!status.isSystem)
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      size: 16, color: Colors.grey[400]),
                  tooltip: 'Eliminar',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () => _deleteStatus(status),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Helper class for unified list items (headers + statuses)
class _StatusListItem {
  final bool isHeader;
  final String? title;
  final StatusPhase? phase;
  final JobStatusCustom? status;

  _StatusListItem._({
    required this.isHeader,
    this.title,
    this.phase,
    this.status,
  });

  factory _StatusListItem.header(String title, StatusPhase phase) {
    return _StatusListItem._(isHeader: true, title: title, phase: phase);
  }

  factory _StatusListItem.status(JobStatusCustom status) {
    return _StatusListItem._(isHeader: false, status: status);
  }
}

/// Custom horizontal scrollbar that appears on hover near the bottom of the table
class _HoverScrollbar extends StatefulWidget {
  final ScrollController scrollController;
  final double contentWidth;
  final double viewportWidth;

  const _HoverScrollbar({
    required this.scrollController,
    required this.contentWidth,
    required this.viewportWidth,
  });

  @override
  State<_HoverScrollbar> createState() => _HoverScrollbarState();
}

class _HoverScrollbarState extends State<_HoverScrollbar> {
  bool _isHovered = false;
  bool _isDragging = false;
  double _scrollPosition = 0;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (mounted) {
      setState(() {
        _scrollPosition = widget.scrollController.offset;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Calculate thumb size and position
    final scrollableWidth = widget.contentWidth - widget.viewportWidth;
    final thumbRatio = widget.viewportWidth / widget.contentWidth;
    final thumbWidth = (widget.viewportWidth * thumbRatio)
        .clamp(40.0, widget.viewportWidth * 0.5);
    final trackWidth = widget.viewportWidth - 32; // 16px padding on each side
    final maxThumbOffset = trackWidth - thumbWidth;
    final thumbOffset = scrollableWidth > 0
        ? (_scrollPosition / scrollableWidth) * maxThumbOffset
        : 0.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) {
        if (!_isDragging) setState(() => _isHovered = false);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: _isHovered || _isDragging ? 14 : 6,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: _isHovered || _isDragging
              ? (isDark ? Colors.grey[800] : Colors.grey[200])
              : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Stack(
          children: [
            // Track (only visible on hover)
            if (_isHovered || _isDragging)
              Positioned.fill(
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[850] : Colors.grey[300],
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            // Thumb
            Positioned(
              left: thumbOffset + 16,
              top: _isHovered || _isDragging ? 2 : 1,
              child: GestureDetector(
                onHorizontalDragStart: (_) =>
                    setState(() => _isDragging = true),
                onHorizontalDragEnd: (_) => setState(() {
                  _isDragging = false;
                  if (!_isHovered) _isHovered = false;
                }),
                onHorizontalDragUpdate: (details) {
                  final newOffset = thumbOffset + details.delta.dx;
                  final scrollRatio = newOffset / maxThumbOffset;
                  final newScrollPosition = (scrollRatio * scrollableWidth)
                      .clamp(0.0, scrollableWidth);
                  widget.scrollController.jumpTo(newScrollPosition);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: thumbWidth,
                  height: _isHovered || _isDragging ? 10 : 4,
                  decoration: BoxDecoration(
                    color: _isDragging
                        ? (isDark ? Colors.grey[400] : Colors.grey[600])
                        : _isHovered
                            ? (isDark ? Colors.grey[500] : Colors.grey[500])
                            : (isDark ? Colors.grey[600] : Colors.grey[400]),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ),
            // Click on track to jump
            if (_isHovered || _isDragging)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapDown: (details) {
                    final tapPosition = details.localPosition.dx - 16;
                    final scrollRatio = tapPosition / trackWidth;
                    final newScrollPosition = (scrollRatio * scrollableWidth)
                        .clamp(0.0, scrollableWidth);
                    widget.scrollController.animateTo(
                      newScrollPosition,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Dialog widget for editing both diagnostic and delivery deadlines
class _DualDeadlineDialog extends StatefulWidget {
  final DateTime? diagnosticDeadline;
  final DateTime? deliveryDeadline;

  const _DualDeadlineDialog({
    this.diagnosticDeadline,
    this.deliveryDeadline,
  });

  @override
  State<_DualDeadlineDialog> createState() => _DualDeadlineDialogState();
}

class _DualDeadlineDialogState extends State<_DualDeadlineDialog> {
  DateTime? _diagnosticDeadline;
  DateTime? _deliveryDeadline;

  @override
  void initState() {
    super.initState();
    _diagnosticDeadline = widget.diagnosticDeadline;
    _deliveryDeadline = widget.deliveryDeadline;
  }

  Future<void> _pickDate({required bool isDiagnostic}) async {
    final current = isDiagnostic ? _diagnosticDeadline : _deliveryDeadline;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: isDiagnostic ? 'Plazo Diagnóstico' : 'Plazo Entrega',
      cancelText: current != null ? 'QUITAR' : 'CANCELAR',
      confirmText: 'ACEPTAR',
    );

    if (picked == null && current != null) {
      // User wants to clear the deadline
      final clear = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(isDiagnostic
              ? '¿Quitar el plazo de diagnóstico?'
              : '¿Quitar el plazo de entrega?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sí, quitar'),
            ),
          ],
        ),
      );
      if (clear == true) {
        setState(() {
          if (isDiagnostic) {
            _diagnosticDeadline = null;
          } else {
            _deliveryDeadline = null;
          }
        });
      }
    } else if (picked != null) {
      setState(() {
        if (isDiagnostic) {
          _diagnosticDeadline = picked;
        } else {
          _deliveryDeadline = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Plazos'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Diagnostic deadline row
          _buildDeadlineRow(
            icon: Icons.search,
            label: 'Diagnóstico',
            color: Colors.blue,
            deadline: _diagnosticDeadline,
            onTap: () => _pickDate(isDiagnostic: true),
          ),
          const SizedBox(height: 16),
          // Delivery deadline row
          _buildDeadlineRow(
            icon: Icons.local_shipping_outlined,
            label: 'Entrega',
            color: Colors.green,
            deadline: _deliveryDeadline,
            onTap: () => _pickDate(isDiagnostic: false),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCELAR'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context, {
              'diagnostic': _diagnosticDeadline,
              'delivery': _deliveryDeadline,
            });
          },
          child: const Text('GUARDAR'),
        ),
      ],
    );
  }

  Widget _buildDeadlineRow({
    required IconData icon,
    required String label,
    required Color color,
    required DateTime? deadline,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: deadline != null
              ? color.withValues(alpha: 0.1)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: deadline != null
                ? color.withValues(alpha: 0.3)
                : Colors.grey.shade300,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: deadline != null ? color : Colors.grey.shade400),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Text(
                    deadline != null
                        ? DateFormat('dd/MM/yyyy').format(deadline)
                        : 'Sin plazo',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: deadline != null ? color : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.edit_calendar,
              size: 20,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Floating block shown after marking a warranty as "not covered"
// ---------------------------------------------------------------------------
class _NotCoveredConvertDialog extends StatelessWidget {
  final String jobNumber;
  final VoidCallback onConvert;
  final VoidCallback onDismiss;

  const _NotCoveredConvertDialog({
    required this.jobNumber,
    required this.onConvert,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 32, left: 24, right: 24),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(16),
          color: theme.colorScheme.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.shield_outlined,
                      color: Colors.red.shade700, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Garantía rechazada — $jobNumber',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '¿Cobrar el servicio al cliente?',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: onDismiss,
                  child: const Text('No'),
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: onConvert,
                  icon: const Icon(Icons.attach_money, size: 16),
                  label: const Text('Cobrar'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _DebugJobLifecycleStage {
  intake,
  diagnostic,
  inProgress,
  completed,
  delivered,
}

extension _DebugJobLifecycleStageX on _DebugJobLifecycleStage {
  String get id {
    switch (this) {
      case _DebugJobLifecycleStage.intake:
        return 'intake';
      case _DebugJobLifecycleStage.diagnostic:
        return 'diagnostic';
      case _DebugJobLifecycleStage.inProgress:
        return 'in_progress';
      case _DebugJobLifecycleStage.completed:
        return 'completed';
      case _DebugJobLifecycleStage.delivered:
        return 'delivered';
    }
  }

  String get label {
    switch (this) {
      case _DebugJobLifecycleStage.intake:
        return 'Ingreso';
      case _DebugJobLifecycleStage.diagnostic:
        return 'Diagnóstico';
      case _DebugJobLifecycleStage.inProgress:
        return 'En curso';
      case _DebugJobLifecycleStage.completed:
        return 'Finalizado';
      case _DebugJobLifecycleStage.delivered:
        return 'Entregado';
    }
  }

  String get supportText {
    switch (this) {
      case _DebugJobLifecycleStage.intake:
        return 'Llega recién al taller, con solicitud del cliente pero sin diagnóstico aún.';
      case _DebugJobLifecycleStage.diagnostic:
        return 'Deja el trabajo listo para probar wizards, diagnósticos y confirmaciones técnicas.';
      case _DebugJobLifecycleStage.inProgress:
        return 'Simula un trabajo ya en ejecución con diagnóstico completo y plazos corridos.';
      case _DebugJobLifecycleStage.completed:
        return 'Prepara el caso como finalizado para probar cierre, cobro y memoria de trabajo.';
      case _DebugJobLifecycleStage.delivered:
        return 'Deja el trabajo como entregado para revisar históricos y estados archivados.';
    }
  }

  JobStatus get status {
    switch (this) {
      case _DebugJobLifecycleStage.intake:
        return JobStatus.pendiente;
      case _DebugJobLifecycleStage.diagnostic:
        return JobStatus.diagnostico;
      case _DebugJobLifecycleStage.inProgress:
        return JobStatus.enCurso;
      case _DebugJobLifecycleStage.completed:
        return JobStatus.finalizado;
      case _DebugJobLifecycleStage.delivered:
        return JobStatus.entregado;
    }
  }

  bool get includesDiagnosis {
    switch (this) {
      case _DebugJobLifecycleStage.intake:
        return false;
      case _DebugJobLifecycleStage.diagnostic:
      case _DebugJobLifecycleStage.inProgress:
      case _DebugJobLifecycleStage.completed:
      case _DebugJobLifecycleStage.delivered:
        return true;
    }
  }

  bool get includesWorkPerformed {
    switch (this) {
      case _DebugJobLifecycleStage.completed:
      case _DebugJobLifecycleStage.delivered:
        return true;
      case _DebugJobLifecycleStage.intake:
      case _DebugJobLifecycleStage.diagnostic:
      case _DebugJobLifecycleStage.inProgress:
        return false;
    }
  }
}

class _DebugBikeScenario {
  final String id;
  final String label;
  final String description;
  final String brand;
  final String model;
  final int year;
  final BikeType bikeType;
  final String wheelSize;
  final String frameSize;
  final String color;
  final String fixtureSerial;
  final bool reuseBike;
  final String clientRequest;
  final String diagnosis;
  final String workPerformed;
  final Map<String, dynamic> technicalValues;
  final List<String> technicalHighlights;

  const _DebugBikeScenario({
    required this.id,
    required this.label,
    required this.description,
    required this.brand,
    required this.model,
    required this.year,
    required this.bikeType,
    required this.wheelSize,
    required this.frameSize,
    required this.color,
    required this.fixtureSerial,
    required this.reuseBike,
    required this.clientRequest,
    required this.diagnosis,
    required this.workPerformed,
    this.technicalValues = const {},
    this.technicalHighlights = const [],
  });
}

class _DebugTestJobRequest {
  final _DebugBikeScenario scenario;
  final _DebugJobLifecycleStage stage;

  const _DebugTestJobRequest({
    required this.scenario,
    required this.stage,
  });
}

class _DebugJobTiming {
  final DateTime arrivalDate;
  final DateTime diagnosticDeadline;
  final DateTime deliveryDeadline;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? deliveredAt;

  const _DebugJobTiming({
    required this.arrivalDate,
    required this.diagnosticDeadline,
    required this.deliveryDeadline,
    this.startedAt,
    this.completedAt,
    this.deliveredAt,
  });
}

const List<_DebugBikeScenario> _debugBikeScenarios = [
  _DebugBikeScenario(
    id: 'drivetrain_no_profile',
    label: 'Drivetrain sin ficha',
    description:
        'Hardtail 1x12 sin bike_profile previa, útil para probar promoción de ficha desde wizards reales.',
    brand: 'Test MTB',
    model: 'Drivetrain Sin Ficha',
    year: 2025,
    bikeType: BikeType.mountainHardtail,
    wheelSize: '29',
    frameSize: 'M',
    color: 'Rojo',
    fixtureSerial: 'DBG-DRIVETRAIN-NO-PROFILE',
    reuseBike: false,
    clientRequest: 'Regular cambios y revisar desgaste de cadena.',
    diagnosis:
        'Transmisión desajustada y sin ficha técnica confirmada para drivetrain.',
    workPerformed: 'Ajuste base de cambios y revisión general de transmisión.',
    technicalHighlights: ['Sin ficha previa', '1x12', 'MTB 29'],
  ),
  _DebugBikeScenario(
    id: 'rim_brake_city',
    label: 'Urbana rim brake 3x7',
    description:
        'Bicicleta urbana con V-Brake y freewheel roscado para probar flujos de freno de llanta y transmisión básica.',
    brand: 'Test City',
    model: 'Rim Brake 3x7',
    year: 2024,
    bikeType: BikeType.paseo,
    wheelSize: '700C',
    frameSize: 'M',
    color: 'Azul',
    fixtureSerial: 'DBG-RIM-BRAKE-CITY',
    reuseBike: true,
    clientRequest: 'Revisar frenos, piolas y ajuste de cambios traseros.',
    diagnosis:
        'Frenos de llanta con mordaza descentrada y transmisión 3x7 con roce leve.',
    workPerformed:
        'Ajuste de frenos V-Brake, centrado y regulación de cambios.',
    technicalValues: {
      'brakeType': 'rim',
      'rimBrakeFamily': 'v_brake',
      'drivetrainConfig': '3x7',
      'drivetrainSpeeds': 7,
      'freehubType': 'threaded_freewheel',
      'valveType': 'schrader',
    },
    technicalHighlights: ['V-Brake', '3x7', 'Freewheel roscado'],
  ),
  _DebugBikeScenario(
    id: 'hydraulic_disc_mtb',
    label: 'MTB disco hidráulico 1x12',
    description:
        'Hardtail moderna con freno hidráulico y transmisión 1x12 para compatibilidad y wizard de frenos/disco.',
    brand: 'Test Trail',
    model: 'Hydraulic Disc 1x12',
    year: 2025,
    bikeType: BikeType.mountainHardtail,
    wheelSize: '29',
    frameSize: 'L',
    color: 'Negro',
    fixtureSerial: 'DBG-HYDRAULIC-DISC-MTB',
    reuseBike: true,
    clientRequest: 'Purgar frenos y revisar transmisión 1x12.',
    diagnosis:
        'Freno delantero esponjoso y transmisión 1x12 con ajuste fino pendiente.',
    workPerformed: 'Purgado, alineación de cáliper y ajuste de cambios.',
    technicalValues: {
      'brakeType': 'hydraulic_disc',
      'drivetrainConfig': '1x12',
      'drivetrainSpeeds': 12,
      'freehubType': 'shimano_hg',
      'bottomBracketFamily': 'bsa_threaded',
      'bbShellWidthMm': 73,
      'spindleInterface': 'hollowtech_24',
    },
    technicalHighlights: [
      'Disco hidráulico',
      '1x12',
      'BSA 73',
      'Hollowtech 24 mm',
    ],
  ),
  _DebugBikeScenario(
    id: 'pressfit_trail_dub',
    label: 'Trail pressfit DUB',
    description:
        'Trail moderna con pedalier pressfit para validar shell width, bore y spindle interface en la ficha upstream.',
    brand: 'Test Carbon',
    model: 'Pressfit DUB 29',
    year: 2025,
    bikeType: BikeType.mountain,
    wheelSize: '29',
    frameSize: 'M',
    color: 'Gris',
    fixtureSerial: 'DBG-PRESSFIT-DUB',
    reuseBike: true,
    clientRequest: 'Revisar ruido en pedalier y juego lateral en bielas.',
    diagnosis:
        'Pedalier pressfit con ruido intermitente y transmisión moderna pendiente de confirmación upstream.',
    workPerformed:
        'Inspección de caja, ajuste de bielas y validación de estándar pressfit.',
    technicalValues: {
      'brakeType': 'hydraulic_disc',
      'drivetrainConfig': '1x12',
      'drivetrainSpeeds': 12,
      'freehubType': 'sram_xd',
      'bottomBracketFamily': 'pressfit',
      'bbShellWidthMm': 92,
      'bbShellDiameterMm': 41,
      'spindleInterface': 'sram_dub',
    },
    technicalHighlights: [
      'Pressfit 92/41',
      'SRAM DUB',
      '1x12',
    ],
  ),
  _DebugBikeScenario(
    id: 'bmx_single_speed',
    label: 'BMX singlespeed',
    description:
        'BMX rígida para probar casos especiales de 1x1, rim brake y driver BMX.',
    brand: 'Test BMX',
    model: 'Street 1x1',
    year: 2023,
    bikeType: BikeType.bmx,
    wheelSize: '20',
    frameSize: '20.5',
    color: 'Blanco',
    fixtureSerial: 'DBG-BMX-SINGLE',
    reuseBike: true,
    clientRequest: 'Ajustar freno trasero y revisar juego en driver.',
    diagnosis:
        'BMX con freno trasero desalineado y transmisión 1x1 con holgura en driver.',
    workPerformed: 'Ajuste de U-Brake y revisión general del driver BMX.',
    technicalValues: {
      'brakeType': 'rim',
      'rimBrakeFamily': 'u_brake',
      'drivetrainConfig': '1x1',
      'drivetrainSpeeds': 1,
      'freehubType': 'bmx_driver',
      'bottomBracketFamily': 'mid',
      'bbShellWidthMm': 68,
      'bbShellDiameterMm': 41.2,
      'spindleInterface': 'bmx_19',
    },
    technicalHighlights: ['BMX', '1x1', 'Mid 68/41.2', 'BMX 19 mm'],
  ),
];
