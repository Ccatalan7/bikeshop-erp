import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/services/database_service.dart';
import '../../crm/models/crm_models.dart';
import '../../crm/services/customer_service.dart';
import '../../sales/models/sales_models.dart';
import '../services/bikeshop_service.dart';
import '../services/job_status_service.dart';
import '../models/bikeshop_models.dart';
import '../widgets/pega_detail_view.dart';
import '../widgets/pegas_calendar_widget.dart';

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
  late JobStatusService _jobStatusService;

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
      final sourceIndex = visibleColumns.indexWhere((c) => c.id == _draggingColumnId);
      if (sourceIndex != -1 && _dragTargetIndex! >= 0 && _dragTargetIndex! < visibleColumns.length) {
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
  DateTime _timelineViewStart = DateTime.now().subtract(const Duration(days: 7));

  // Calendar view state - moved to PegasCalendarWidget (shared widget)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _databaseService = Provider.of<DatabaseService>(context, listen: false);
    _bikeshopService = Provider.of<BikeshopService>(context, listen: false);
    _customerService = Provider.of<CustomerService>(context, listen: false);
    _jobStatusService = Provider.of<JobStatusService>(context, listen: false);
    _initializeColumns();
    _loadColumnOrder(); // Load saved column order
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
        id: 'priority',
        label: 'Prioridad',
        width: 110,
        minWidth: 100,
        visible: true,
        sortable: true,
      ),
      ColumnConfig(
        id: 'diagnosis',
        label: 'Diagnóstico',
        width: 250,
        minWidth: 150,
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

  Future<void> _loadData() async {
    // Show cached jobs immediately if available (instant render)
    if (_bikeshopService.hasJobsCache && _jobs.isEmpty) {
      setState(() {
        _jobs = _bikeshopService.cachedJobs;
        _filteredJobs = _jobs;
        _isLoading = false;
      });
      _applyFiltersAndSort();
    } else {
      setState(() => _isLoading = true);
    }
    
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

  Future<void> _loadColumnOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedOrder = prefs.getStringList('pegas_column_order');

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
      }
    } catch (e) {
      debugPrint('Error loading column order: $e');
    }
  }

  Future<void> _saveColumnOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final columnIds = _columns.map((col) => col.id).toList();
      await prefs.setStringList('pegas_column_order', columnIds);
    } catch (e) {
      debugPrint('Error saving column order: $e');
    }
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
          case 'diagnosis':
            comparison = (a.diagnosis ?? '').compareTo(b.diagnosis ?? '');
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
            // Left: Jobs list (tap anywhere to close detail view)
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
                  final result = await context.push('/taller/pegas/${_selectedJob!.id}');
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
                  // Optimistic update
                  setState(() {
                    final index = _jobs.indexWhere((j) => j.id == _selectedJob!.id);
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
                        deadline: job.deadline,
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
                    // Revert on error
                    if (mounted) {
                      await _loadData();
                      if (_selectedJob != null) {
                        await _loadJobDetails(_selectedJob!);
                      }
                    }
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
                  _isAnySelected
                      ? '${_selectedJobIds.length} seleccionado${_selectedJobIds.length != 1 ? 's' : ''}'
                      : 'Gestión de Trabajos',
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

          // Bulk action buttons (shown when items selected)
          if (_isAnySelected) ...[
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _selectedJobIds.clear()),
              tooltip: 'Deseleccionar todo',
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: _exportSelectedToCSV,
              icon: const Icon(Icons.file_download, size: 20),
              label: const Text('Exportar'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _bulkUpdateStatus,
              icon: const Icon(Icons.edit, size: 20),
              label: const Text('Cambiar Estado'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
            ),
          ] else ...[
            // Regular action buttons
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

              // View mode toggle
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
                    label: Text('Tablero', style: TextStyle(fontSize: 13)),
                  ),
                  ButtonSegment(
                    value: 'calendar',
                    icon: Icon(Icons.calendar_month, size: 16),
                    label: Text('Calendario', style: TextStyle(fontSize: 13)),
                  ),
                  ButtonSegment(
                    value: 'gantt',
                    icon: Icon(Icons.view_timeline, size: 16),
                    label: Text('Gantt', style: TextStyle(fontSize: 13)),
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

              const Spacer(),

              // Stats - sum invoice totals, not job costs
              if (_filteredJobs.isNotEmpty)
                Text(
                  'Valor total: ${NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(_filteredJobs.fold<double>(0, (sum, job) {
                    final invoice =
                        job.invoiceId != null ? _invoices[job.invoiceId] : null;
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
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withOpacity(0.3),
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
            // Table header and body wrapped in single horizontal scroll
            Expanded(
              child: SingleChildScrollView(
                controller: _horizontalScrollController,
                scrollDirection: Axis.horizontal,
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
            // Pagination controls
            _buildPaginationControls(startIndex, endIndex),
          ],
        );
      },
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
            .withOpacity(0.3),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: Row(
        children: displayColumns.asMap().entries.map((entry) {
          return _buildHeaderCell(entry.value, entry.key, displayColumns.length);
        }).toList(),
      ),
    );
  }

  Widget _buildHeaderCell(ColumnConfig col, int displayIndex, int totalColumns) {
    final theme = Theme.of(context);

    if (col.id == 'checkbox') {
      bool? checkboxValue;
      if (_filteredJobs.isEmpty || _selectedJobIds.isEmpty) {
        checkboxValue = false;
      } else if (_selectedJobIds.length == _filteredJobs.length) {
        checkboxValue = true;
      } else {
        checkboxValue = null;
      }

      return Container(
        width: col.width,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Checkbox(
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
        ),
      );
    }

    Widget buildContent() => _buildHeaderContent(col);
    Widget baseContent;
    final isDragging = _draggingColumnId == col.id;

    if (col.reorderable) {
      baseContent = DragTarget<String>(
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
          // Apply the reorder using the tracked target index
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
          return Draggable<String>(
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
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.drag_indicator, size: 16, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text(
                        col.label,
                        style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
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
              child: buildContent(),
            ),
          );
        },
      );
    } else {
      baseContent = buildContent();
    }

    if (col.maxWidth != null && col.maxWidth == col.width) {
      return Container(
        width: col.width,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: baseContent,
      );
    } else {
      return Expanded(
        flex: (col.width ~/ 10).clamp(1, 100),
        child: Container(
          constraints: BoxConstraints(minWidth: col.minWidth),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: baseContent,
        ),
      );
    }
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
  }



  /// Apply column reorder using display indices (for live preview drag)
  void _applyColumnReorder(String sourceId, int targetDisplayIndex) {
    final visibleColumns = _columns.where((col) => col.visible).toList();
    final sourceDisplayIndex = visibleColumns.indexWhere((c) => c.id == sourceId);
    if (sourceDisplayIndex == -1 || sourceDisplayIndex == targetDisplayIndex) return;

    // Get the actual column indices in _columns (not just visible)
    final sourceActualIndex = _columns.indexWhere((c) => c.id == sourceId);
    if (sourceActualIndex == -1) return;

    // Calculate the target actual index based on visible columns
    // We need to find where in _columns the visible column at targetDisplayIndex is
    int targetActualIndex;
    if (targetDisplayIndex >= visibleColumns.length) {
      // Insert at end of visible columns
      final lastVisible = visibleColumns.last;
      targetActualIndex = _columns.indexWhere((c) => c.id == lastVisible.id) + 1;
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
          children: _displayColumns.map((col) {
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

  Widget _getCellContent(
      String columnId, MechanicJob job, Customer? customer, Bike? bike) {
    switch (columnId) {
      case 'checkbox':
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
        final statusColor = _getJobStatusColor(job);
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
                color: statusColor.withOpacity(0.5),
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
                        decorationColor: Theme.of(context)
                            .colorScheme
                            .primary
                            .withOpacity(0.3),
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
                    color:
                        Theme.of(context).colorScheme.primary.withOpacity(0.6),
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
        // Clickable bike with optional image preview
        final bikeName = bike?.displayName ?? 'N/A';
        final bikeImageUrl = bike?.imageUrl;
        return InkWell(
          onTap: () => _showBikeSelectorDialog(job, customer),
          child: Row(
            children: [
              // MTB bike icon from local asset
              Image.asset(
                'assets/icons/mtb_bike_v3.png',
                width: 35,
                height: 35,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.pedal_bike,
                  size: 35,
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.7),
                ),
              ),
              const SizedBox(width: 6),
              // Bike image thumbnail if available
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
                color: isOverdue ? Colors.red.shade700 : Colors.grey.shade600,
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
        // Clickable state badge - uses custom status color and name
        final statusColor = _getJobStatusColor(job);
        final statusName = job.statusDisplayName;
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
                  statusName,
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

      case 'diagnosis':
        // Clickable diagnosis cell with inline edit popup
        return _DiagnosisCell(
          diagnosis: job.diagnosis,
          onSave: (newDiagnosis) async {
            // Optimistic update
            final updatedJob = MechanicJob(
              id: job.id,
              tenantId: job.tenantId,
              jobNumber: job.jobNumber,
              customerId: job.customerId,
              bikeId: job.bikeId,
              servicePackageId: job.servicePackageId,
              arrivalDate: job.arrivalDate,
              deadline: job.deadline,
              startedAt: job.startedAt,
              completedAt: job.completedAt,
              deliveredAt: job.deliveredAt,
              status: job.status,
              priority: job.priority,
              clientRequest: job.clientRequest,
              diagnosis: newDiagnosis,
              workPerformed: job.workPerformed,
              notes: job.notes,
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
                    content: Text('Error al guardar diagnóstico: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          },
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
        // Clickable invoice with full status display
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
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: borderColor,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: textColor,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    decoration:
                        job.invoiceId != null ? TextDecoration.underline : null,
                    decorationColor: textColor.withValues(alpha: 0.3),
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

  // ========== STATUS FILTER BUTTON ==========
  
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
              hasFilter ? 'Estado (${_customStatusFilter.length})' : 'Estado',
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
    final RenderBox button = _statusFilterKey.currentContext!.findRenderObject() as RenderBox;
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
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const Spacer(),
                                if (_customStatusFilter.isNotEmpty)
                                  TextButton(
                                    onPressed: () {
                                      setState(() => _customStatusFilter.clear());
                                      setDialogState(() {});
                                      _applyFiltersAndSort();
                                    },
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text('Limpiar', style: TextStyle(fontSize: 12)),
                                  ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          // Status list
                          Flexible(
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: JobStatus.values.map((status) {
                                  final isSelected = _customStatusFilter.contains(status);
                                  final statusColor = _getStatusColorForFilter(status);
                                  
                                  return InkWell(
                                    onTap: () {
                                      setState(() {
                                        if (_customStatusFilter.contains(status)) {
                                          _customStatusFilter.remove(status);
                                        } else {
                                          _customStatusFilter.add(status);
                                        }
                                      });
                                      setDialogState(() {});
                                      _applyFiltersAndSort();
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 20,
                                            height: 20,
                                            decoration: BoxDecoration(
                                              color: isSelected ? statusColor : Colors.transparent,
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(
                                                color: isSelected ? statusColor : Colors.grey.shade400,
                                                width: 1.5,
                                              ),
                                            ),
                                            child: isSelected
                                                ? const Icon(Icons.check, size: 14, color: Colors.white)
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
                                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
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
            deadline: updatedJob.deadline,
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
            const SnackBar(content: Text('Trabajo completado'), duration: Duration(seconds: 1)),
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
            const SnackBar(content: Text('Trabajo eliminado'), duration: Duration(seconds: 1)),
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
      ),
    );
  }

  Future<void> _updateJobToCustomStatus(MechanicJob job, JobStatusCustom newStatus) async {
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
      await _jobStatusService.updateJobStatus(job.id!, newStatus.id!);
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

    // Load customer's bikes
    final bikes =
        _bikes.values.where((b) => b.customerId == customer.id).toList();

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
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: bikes.map((bike) {
                    final isSelected = bike.id == job.bikeId;
                    final bikeName =
                        '${bike.brand ?? ''} ${bike.model ?? ''}'.trim();
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
                          ? Icon(Icons.check_circle,
                              color: Colors.green.shade700)
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
                                
                                // Optimistic update
                                setState(() {
                                  final index = _jobs.indexWhere((j) => j.id == job.id);
                                  if (index != -1) {
                                    _jobs[index] = updatedJob;
                                  }
                                  _bikes[bike.id!] = bike;
                                  _applyFiltersAndSort();
                                });
                                
                                // Save in background
                                try {
                                  await _bikeshopService.updateJob(updatedJob);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Bicicleta cambiada a: $bikeName'),
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  // Revert on error
                                  if (mounted) {
                                    await _loadData();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Error: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
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
                constraints:
                    const BoxConstraints(maxWidth: 600, maxHeight: 600),
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

  Future<void> _editDeadline(MechanicJob job) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: job.deadline ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Seleccionar fecha límite',
    );

    if (picked != null && mounted) {
      // Optimistic update - update UI immediately
      setState(() {
        final index = _jobs.indexWhere((j) => j.id == job.id);
        if (index != -1) {
          _jobs[index] = MechanicJob(
            id: job.id,
            tenantId: job.tenantId,
            jobNumber: job.jobNumber,
            customerId: job.customerId,
            bikeId: job.bikeId,
            arrivalDate: job.arrivalDate,
            deadline: picked, // NEW DEADLINE
            startedAt: job.startedAt,
            completedAt: job.completedAt,
            deliveredAt: job.deliveredAt,
            status: job.status,
            priority: job.priority,
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
        }
        _applyFiltersAndSort(); // Refresh filtered view
      });
      
      // Save in background
      try {
        final updatedJob = MechanicJob(
          id: job.id,
          tenantId: job.tenantId,
          jobNumber: job.jobNumber,
          customerId: job.customerId,
          bikeId: job.bikeId,
          arrivalDate: job.arrivalDate,
          deadline: picked,
          startedAt: job.startedAt,
          completedAt: job.completedAt,
          deliveredAt: job.deliveredAt,
          status: job.status,
          priority: job.priority,
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
        await _bikeshopService.updateJob(updatedJob);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Plazo actualizado: ${DateFormat('dd/MM/yyyy').format(picked)}'),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } catch (e) {
        // Revert on error
        if (mounted) {
          setState(() {
            final index = _jobs.indexWhere((j) => j.id == job.id);
            if (index != -1) {
              _jobs[index] = job; // Restore original
            }
            _applyFiltersAndSort();
          });
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

  /// Gets status color - prefers custom status color, falls back to legacy
  Color _getJobStatusColor(MechanicJob job) {
    // Use custom status color if available
    if (job.customStatus != null) {
      return job.customStatus!.colorValue;
    }
    // Fallback to legacy color mapping
    return _getLegacyStatusColor(job.status);
  }

  /// Legacy status color mapping (for backward compatibility)
  Color _getLegacyStatusColor(JobStatus status) {
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
        job.deadline != null
            ? DateFormat('dd/MM/yyyy').format(job.deadline!)
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
                        color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  ...statusesByPhase[StatusPhase.todo]!.map((status) => ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: status.colorValue,
                        shape: BoxShape.circle,
                      ),
                    ),
                    title: Text(status.name, style: const TextStyle(fontSize: 14)),
                    onTap: () => Navigator.pop(dialogContext, status),
                  )),
                ],
                // En Progreso section
                if (statusesByPhase[StatusPhase.inProgress]?.isNotEmpty == true) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, top: 12),
                    child: Text(
                      'En Progreso',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  ...statusesByPhase[StatusPhase.inProgress]!.map((status) => ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: status.colorValue,
                        shape: BoxShape.circle,
                      ),
                    ),
                    title: Text(status.name, style: const TextStyle(fontSize: 14)),
                    onTap: () => Navigator.pop(dialogContext, status),
                  )),
                ],
                // Completado section
                if (statusesByPhase[StatusPhase.complete]?.isNotEmpty == true) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, top: 12),
                    child: Text(
                      'Completado',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  ...statusesByPhase[StatusPhase.complete]!.map((status) => ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: status.colorValue,
                        shape: BoxShape.circle,
                      ),
                    ),
                    title: Text(status.name, style: const TextStyle(fontSize: 14)),
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
            content: Text('${selectedJobs.length} trabajos actualizados a ${newCustomStatus.name}'),
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
      case 'table':
      default:
        return _buildDataTable();
    }
  }

  // ========== BOARD VIEW (Kanban) ==========
  Widget _buildBoardView() {
    final statuses = [
      JobStatus.pendiente,
      JobStatus.diagnostico,
      JobStatus.esperandoRepuestos,
      JobStatus.enCurso,
      JobStatus.finalizado,
      JobStatus.entregado,
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: statuses.map((status) {
          final jobsInStatus = _filteredJobs.where((j) => j.status == status).toList();
          return _buildBoardColumn(status, jobsInStatus);
        }).toList(),
      ),
    );
  }

  Widget _buildBoardColumn(JobStatus status, List<MechanicJob> jobs) {
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
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
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
    final isOverdue = job.deadline != null && job.deadline!.isBefore(DateTime.now());

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
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
              if (job.deadline != null) ...[
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
                      DateFormat('dd/MM/yy').format(job.deadline!),
                      style: TextStyle(
                        fontSize: 11,
                        color: isOverdue ? Colors.red[700] : Colors.grey[700],
                        fontWeight: isOverdue ? FontWeight.bold : FontWeight.normal,
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
    final visibleDays = _timelineScale == 'week' ? 14 : 60; // 2 weeks or 2 months
    
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
                _timelineViewStart = DateTime.now().subtract(const Duration(days: 7));
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

  Widget _buildTimelineContent(List<MechanicJob> jobs, double dayWidth, int visibleDays) {
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
                  children: jobs.map((job) => 
                    _buildTimelineJobRow(job, dayWidth, visibleDays)
                  ).toList(),
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
                        fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
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

  Widget _buildTimelineJobRow(MechanicJob job, double dayWidth, int visibleDays) {
    final customer = _customers[job.customerId];
    final viewEnd = _timelineViewStart.add(Duration(days: visibleDays));
    
    // Calculate bar position
    final jobStart = job.arrivalDate;
    final jobEnd = job.deadline ?? job.arrivalDate.add(const Duration(days: 1));
    
    // Check if job is visible in current view
    final isVisible = jobEnd.isAfter(_timelineViewStart) && jobStart.isBefore(viewEnd);
    
    if (!isVisible) {
      return const SizedBox.shrink(); // Hide jobs outside view
    }
    
    // Calculate position relative to view start
    final startDayOffset = jobStart.difference(_timelineViewStart).inDays.toDouble();
    final endDayOffset = jobEnd.difference(_timelineViewStart).inDays.toDouble() + 1;
    
    // Clamp to visible area
    final clampedStart = startDayOffset.clamp(0.0, visibleDays.toDouble());
    final clampedEnd = endDayOffset.clamp(0.0, visibleDays.toDouble());
    
    if (clampedEnd <= clampedStart) {
      return const SizedBox.shrink();
    }
    
    final barLeft = clampedStart * dayWidth;
    final barWidth = (clampedEnd - clampedStart) * dayWidth;
    
    // Determine bar color
    final isOverdue = job.deadline != null && job.deadline!.isBefore(DateTime.now());
    final isCompleted = job.status == JobStatus.entregado || job.status == JobStatus.finalizado;
    
    Color barColor;
    if (isCompleted) {
      barColor = Colors.green[400]!;
    } else if (isOverdue) {
      barColor = Colors.red[400]!;
    } else {
      // Color by status
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
                        color: Colors.black.withOpacity(0.1),
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

/// Inline editable diagnosis cell with popup overlay
class _DiagnosisCell extends StatefulWidget {
  final String? diagnosis;
  final Future<void> Function(String?) onSave;

  const _DiagnosisCell({
    required this.diagnosis,
    required this.onSave,
  });

  @override
  State<_DiagnosisCell> createState() => _DiagnosisCellState();
}

class _DiagnosisCellState extends State<_DiagnosisCell> {
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _textController.text = widget.diagnosis ?? '';
  }

  @override
  void didUpdateWidget(_DiagnosisCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.diagnosis != widget.diagnosis && !_isOpen) {
      _textController.text = widget.diagnosis ?? '';
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _showOverlay() {
    if (_isOpen) return;
    
    _textController.text = widget.diagnosis ?? '';
    _isOpen = true;

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Backdrop to close on outside click
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _saveAndClose,
              child: Container(color: Colors.transparent),
            ),
          ),
          // Popup content
          Positioned(
            width: 350,
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: const Offset(0, 30),
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 250),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(7),
                            topRight: Radius.circular(7),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.medical_information_outlined, 
                                 size: 16, color: Colors.grey[600]),
                            const SizedBox(width: 6),
                            Text(
                              'Diagnóstico',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: Colors.grey[700],
                              ),
                            ),
                            const Spacer(),
                            InkWell(
                              onTap: _saveAndClose,
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(Icons.close, 
                                           size: 16, color: Colors.grey[500]),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Text field
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: TextField(
                            controller: _textController,
                            focusNode: _focusNode,
                            maxLines: 6,
                            minLines: 3,
                            autofocus: true,
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Ingresa el diagnóstico...',
                              hintStyle: TextStyle(color: Colors.grey[400]),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(color: Colors.grey[300]!),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 1.5,
                                ),
                              ),
                              contentPadding: const EdgeInsets.all(10),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            onSubmitted: (_) => _saveAndClose(),
                          ),
                        ),
                      ),
                      // Footer hint
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(7),
                            bottomRight: Radius.circular(7),
                          ),
                        ),
                        child: Text(
                          'Click afuera para guardar',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                            fontStyle: FontStyle.italic,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    
    // Focus after a short delay to ensure overlay is rendered
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted && _isOpen) {
        _focusNode.requestFocus();
      }
    });
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isOpen = false;
  }

  void _saveAndClose() {
    final newValue = _textController.text.trim();
    final oldValue = widget.diagnosis?.trim() ?? '';
    
    _removeOverlay();
    
    // Only save if value changed
    if (newValue != oldValue) {
      widget.onSave(newValue.isEmpty ? null : newValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final diagnosis = widget.diagnosis?.trim();
    final isEmpty = diagnosis == null || diagnosis.isEmpty;

    return CompositedTransformTarget(
      link: _layerLink,
      child: InkWell(
        onTap: _showOverlay,
        borderRadius: BorderRadius.circular(4),
        child: Tooltip(
          message: isEmpty ? 'Click para agregar diagnóstico' : diagnosis,
          waitDuration: const Duration(milliseconds: 500),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: Colors.transparent,
            ),
            child: Row(
              children: [
                Expanded(
                  child: isEmpty
                      ? Text(
                          '—',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[400],
                            fontStyle: FontStyle.italic,
                          ),
                        )
                      : Text(
                          diagnosis,
                          style: const TextStyle(fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.edit_outlined,
                  size: 14,
                  color: Colors.grey[400],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// STATUS MANAGER DIALOG - Inline add/edit/delete/select statuses
// ============================================================================

class _StatusManagerDialog extends StatefulWidget {
  final MechanicJob job;
  final JobStatusService jobStatusService;
  final Function(JobStatusCustom) onStatusSelected;

  const _StatusManagerDialog({
    required this.job,
    required this.jobStatusService,
    required this.onStatusSelected,
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
    '#6B7280', '#EF4444', '#F97316', '#F59E0B', '#EAB308', '#84CC16',
    '#22C55E', '#10B981', '#14B8A6', '#06B6D4', '#0EA5E9', '#3B82F6',
    '#6366F1', '#8B5CF6', '#A855F7', '#D946EF', '#EC4899', '#F43F5E',
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
        final code = name.toUpperCase().replaceAll(' ', '_').replaceAll(RegExp(r'[^A-Z0-9_]'), '');
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
        content: Text('Se eliminará "${status.name}". Los trabajos con este estado quedarán sin estado asignado.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
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
        final currentStatusId = widget.job.statusId ?? widget.job.customStatus?.id;

        return AlertDialog(
          title: Row(
            children: [
              Expanded(
                child: Text(_isEditMode 
                  ? (_editingStatus != null ? 'Editar Estado' : 'Nuevo Estado')
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
            child: _isEditMode ? _buildEditForm() : _buildStatusList(statusesByPhase, currentStatusId),
          ),
          actions: _isEditMode
            ? [
                TextButton(onPressed: _cancelEditing, child: const Text('Cancelar')),
                FilledButton(onPressed: _saveStatus, child: const Text('Guardar')),
              ]
            : [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
              ],
        );
      },
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
          const Text('Fase', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          const SizedBox(height: 8),
          SegmentedButton<StatusPhase>(
            segments: const [
              ButtonSegment(value: StatusPhase.todo, label: Text('Por Hacer')),
              ButtonSegment(value: StatusPhase.inProgress, label: Text('En Progreso')),
              ButtonSegment(value: StatusPhase.complete, label: Text('Completado')),
            ],
            selected: {_selectedPhase},
            onSelectionChanged: (selected) => setState(() => _selectedPhase = selected.first),
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(height: 16),

          // Color picker
          const Text('Color', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
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
                    boxShadow: isSelected ? [
                      BoxShadow(color: colorValue.withOpacity(0.5), blurRadius: 8, spreadRadius: 2),
                    ] : null,
                  ),
                  child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Preview
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _parseColor(_selectedColor).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _parseColor(_selectedColor).withOpacity(0.3)),
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
                  _nameController.text.isEmpty ? 'Vista previa' : _nameController.text,
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

  Widget _buildStatusList(Map<StatusPhase, List<JobStatusCustom>> statusesByPhase, String? currentStatusId) {
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
            await jobStatusService.updateStatus(s.copyWith(sortOrder: expectedOrder));
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
                    color: isSelected ? statusColor : statusColor.withOpacity(0.5),
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
                icon: Icon(Icons.edit_outlined, size: 16, color: Colors.grey[400]),
                tooltip: 'Editar',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () => _startEditing(status),
              ),
              // Delete button (only for non-system statuses)
              if (!status.isSystem)
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 16, color: Colors.grey[400]),
                  tooltip: 'Eliminar',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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