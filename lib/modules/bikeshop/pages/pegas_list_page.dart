import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_widget.dart';
import '../../../shared/widgets/app_button.dart';
import '../../crm/models/crm_models.dart';
import '../../crm/services/customer_service.dart';
import '../services/bikeshop_service.dart';
import '../models/bikeshop_models.dart';
import '../widgets/pega_detail_view.dart';
import '../widgets/split_new_job_button.dart';

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
  bool _sortAscending = false;

  // Mobile search state
  bool _isSearchExpanded = false;

  // View mode: 'cards' or 'table'
  String _viewMode = 'cards';

  // Table pagination
  int _currentPage = 0;
  int _rowsPerPage = 25;

  // Split-pane state
  MechanicJob? _selectedJob;
  List<MechanicJobItem> _selectedJobItems = [];
  Map<String, String> _productImages = {};
  bool _loadingDetails = false;
  double _listPaneWidth = 500.0;
  static const double _minListPaneWidth = 350.0;
  static const double _maxListPaneWidth = 800.0;

  @override
  void initState() {
    super.initState();
    _bikeshopService = Provider.of<BikeshopService>(context, listen: false);
    _customerService = Provider.of<CustomerService>(context, listen: false);
    _loadPreferences();
    _loadData();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _listPaneWidth = prefs.getDouble('pegas_list_pane_width') ?? 500.0;
      _viewMode = prefs.getString('pegas_view_mode') ?? 'cards';
      _rowsPerPage = prefs.getInt('pegas_rows_per_page') ?? 25;
    });
  }

  Future<void> _saveViewMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pegas_view_mode', mode);
  }

  Future<void> _saveRowsPerPage(int rows) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('pegas_rows_per_page', rows);
  }

  Future<void> _saveListPaneWidth(double width) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('pegas_list_pane_width', width);
  }

  Future<void> _loadData() async {
    // Show cached data immediately if available (instant render)
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
      // Fetch fresh data (will use cache if still valid)
      final jobs =
          await _bikeshopService.getJobs(includeCompleted: _showCompleted);
      final customers = await _customerService.getCustomersForList();
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

      MechanicJob? updatedSelection;
      if (_selectedJob != null) {
        try {
          updatedSelection =
              jobs.firstWhere((job) => job.id == _selectedJob!.id);
        } catch (_) {
          updatedSelection = null;
        }
      }

      if (mounted) {
        setState(() {
          _jobs = jobs;
          _filteredJobs = jobs;
          _customers = customerMap;
          _bikes = bikeMap;
          _isLoading = false;
          if (updatedSelection != null) {
            _selectedJob = updatedSelection;
          }
        });
      }

      _applyFiltersAndSort();

      if (updatedSelection != null) {
        setState(() {
          _loadingDetails = true;
          _selectedJobItems = [];
          _productImages = {};
        });
        await _loadJobDetails(updatedSelection);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando trabajos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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

      if (!mounted) return;
      setState(() {
        _selectedJobItems = items;
        _productImages = productImages;
        _loadingDetails = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingDetails = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cargando detalles: $e'),
          backgroundColor: Colors.red,
        ),
      );
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
        final matchesJobNumber = (job.jobNumber ?? '')
            .toLowerCase()
            .contains(_searchTerm.toLowerCase());
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
      int comparison;
      switch (_sortBy) {
        case 'job_number':
          comparison = (a.jobNumber ?? '').compareTo(b.jobNumber ?? '');
          break;
        case 'customer':
          final customerA = _customers[a.customerId]?.name ?? '';
          final customerB = _customers[b.customerId]?.name ?? '';
          comparison = customerA.compareTo(customerB);
          break;
        case 'deadline':
          if (a.deliveryDeadline == null && b.deliveryDeadline == null) {
            comparison = 0;
          } else if (a.deliveryDeadline == null) {
            comparison = 1;
          } else if (b.deliveryDeadline == null) {
            comparison = -1;
          } else {
            comparison = a.deliveryDeadline!.compareTo(b.deliveryDeadline!);
          }
          break;
        case 'priority':
          comparison = a.priority.index.compareTo(b.priority.index);
          break;
        case 'status':
          comparison = a.status.index.compareTo(b.status.index);
          break;
        case 'arrival_date':
        default:
          comparison = b.arrivalDate.compareTo(a.arrivalDate);
          break;
      }
      return _sortAscending ? comparison : -comparison;
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
    // Use MediaQuery for robust detection, ignoring parent constraints issues
    // FORCE mobile on Android/iOS app to avoid desktop layout on high-res phones/tablets
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 1100 ||
        (!kIsWeb && (Platform.isAndroid || Platform.isIOS));

    return MainLayout(
      // On mobile, let the child Scaffold handle the title/AppBar to avoid double headers
      title: isMobile ? '' : 'Vinabike ERP',
      child: isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
    );
  }

  // ============================================================
  // MOBILE LAYOUT - Compact, content-first design
  // ============================================================
  Widget _buildMobileLayout() {
    final theme = Theme.of(context);

    // If viewing job details, show full-screen detail view
    if (_selectedJob != null) {
      return _buildDetailView(isMobile: true);
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          // ─────────────────────────────────────────────────────
          // COMPACT HEADER (48px) - Title + Search + Actions
          // ─────────────────────────────────────────────────────
          _buildMobileHeader(theme),

          // ─────────────────────────────────────────────────────
          // FILTER TABS (40px) - Horizontal scroll + sort
          // ─────────────────────────────────────────────────────
          _buildMobileFilterTabs(theme),

          // ─────────────────────────────────────────────────────
          // CONTENT - The list itself
          // ─────────────────────────────────────────────────────
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
      // FAB for primary action
      floatingActionButton: FloatingActionButton(
        onPressed: () =>
            context.push('/taller/pegas/nueva').then((_) => _loadData()),
        backgroundColor: theme.colorScheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildMobileHeader(ThemeData theme) {
    final stats = _calculateStats();
    final urgentCount = stats['urgente'] ?? 0;
    final overdueCount = stats['overdue'] ?? 0;

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
                case 'completed':
                  setState(() => _showCompleted = !_showCompleted);
                  _loadData();
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
              PopupMenuItem(
                value: 'completed',
                child: Row(
                  children: [
                    Icon(
                      _showCompleted
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    const Text('Ver completados'),
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
              onChanged: _onSearchChanged,
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
                    ],
                  ),
                ),
              ),

              // Sort dropdown
              Container(
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: theme.dividerColor)),
                ),
                child: PopupMenuButton<String>(
                  icon: Icon(Icons.sort, size: 20, color: theme.hintColor),
                  tooltip: 'Ordenar',
                  onSelected: (value) {
                    setState(() {
                      if (_sortBy == value) {
                        _sortAscending = !_sortAscending;
                      } else {
                        _sortBy = value;
                        _sortAscending = false;
                      }
                      _applyFiltersAndSort();
                    });
                  },
                  itemBuilder: (context) => [
                    _buildSortMenuItem('arrival_date', 'Fecha ingreso'),
                    _buildSortMenuItem('deadline', 'Plazo'),
                    _buildSortMenuItem('priority', 'Prioridad'),
                    _buildSortMenuItem('status', 'Estado'),
                  ],
                ),
              ),

              // Priority filter dropdown
              PopupMenuButton<JobPriority?>(
                icon: Icon(
                  Icons.flag,
                  size: 20,
                  color: _filterPriority != null
                      ? _getPriorityColor(_filterPriority!)
                      : theme.hintColor,
                ),
                tooltip: 'Prioridad',
                onSelected: (value) {
                  setState(() {
                    _filterPriority = value;
                    _applyFiltersAndSort();
                  });
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: null,
                    child: Row(
                      children: [
                        Icon(Icons.flag_outlined, color: theme.hintColor),
                        const SizedBox(width: 8),
                        const Text('Todas'),
                        if (_filterPriority == null) ...[
                          const Spacer(),
                          Icon(Icons.check,
                              size: 18, color: theme.colorScheme.primary),
                        ],
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  ...JobPriority.values.map((p) => PopupMenuItem(
                        value: p,
                        child: Row(
                          children: [
                            Icon(Icons.flag, color: _getPriorityColor(p)),
                            const SizedBox(width: 8),
                            Text(p.displayName),
                            if (_filterPriority == p) ...[
                              const Spacer(),
                              Icon(Icons.check,
                                  size: 18, color: theme.colorScheme.primary),
                            ],
                          ],
                        ),
                      )),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  PopupMenuItem<String> _buildSortMenuItem(String value, String label) {
    final isSelected = _sortBy == value;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Text(label),
          if (isSelected) ...[
            const Spacer(),
            Icon(
              _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMobileFilterChip(String label, JobStatus? status) {
    final isSelected = _filterStatus == status;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _filterStatus = status;
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

  Color _getPriorityColor(JobPriority priority) {
    switch (priority) {
      case JobPriority.urgente:
        return Colors.red;
      case JobPriority.alta:
        return Colors.orange;
      case JobPriority.normal:
        return Colors.blue;
      case JobPriority.baja:
        return Colors.grey;
    }
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
      itemBuilder: (context, index) {
        final job = _filteredJobs[index];
        final customer = _customers[job.customerId];
        final bike = _bikes[job.bikeId];
        return _buildMobileJobCard(job, customer, bike);
      },
    );
  }

  Widget _buildMobileJobCard(MechanicJob job, Customer? customer, Bike? bike) {
    final theme = Theme.of(context);
    final isOverdue = job.isOverdue && job.isActive;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOverdue ? Colors.red.shade300 : theme.dividerColor,
          width: isOverdue ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedJob = job;
            _loadingDetails = true;
            _selectedJobItems = [];
            _productImages = {};
          });
          _loadJobDetails(job);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Job number + Priority + Status
              Row(
                children: [
                  Text(
                    job.jobNumber ?? 'Sin #',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildCompactPriorityBadge(job.priority),
                  const Spacer(),
                  _buildCompactStatusBadge(job.status),
                ],
              ),
              const SizedBox(height: 6),

              // Row 2: Customer name
              if (customer != null)
                Row(
                  children: [
                    Icon(Icons.person_outline,
                        size: 14, color: theme.hintColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        customer.name,
                        style: TextStyle(fontSize: 13, color: theme.hintColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

              // Row 3: Bike
              if (bike != null) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.pedal_bike, size: 14, color: theme.hintColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        bike.displayName,
                        style: TextStyle(fontSize: 12, color: theme.hintColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 8),

              // Row 4: Date + Deadline + Cost
              Row(
                children: [
                  // Arrival date
                  Icon(Icons.calendar_today, size: 12, color: theme.hintColor),
                  const SizedBox(width: 3),
                  Text(
                    _formatDate(job.arrivalDate),
                    style: TextStyle(fontSize: 11, color: theme.hintColor),
                  ),

                  // Deadline
                  if (job.deliveryDeadline != null) ...[
                    const SizedBox(width: 10),
                    Icon(
                      Icons.timer,
                      size: 12,
                      color: isOverdue ? Colors.red : theme.hintColor,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      _formatDate(job.deliveryDeadline!),
                      style: TextStyle(
                        fontSize: 11,
                        color: isOverdue ? Colors.red : theme.hintColor,
                        fontWeight:
                            isOverdue ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],

                  const Spacer(),

                  // Cost
                  if (job.totalCost > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '\$${job.totalCost.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 12,
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

  Widget _buildCompactPriorityBadge(JobPriority priority) {
    if (priority == JobPriority.normal || priority == JobPriority.baja) {
      return const SizedBox.shrink();
    }

    final color = _getPriorityColor(priority);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        priority == JobPriority.urgente ? '🔥' : '⚡',
        style: const TextStyle(fontSize: 10),
      ),
    );
  }

  Widget _buildCompactStatusBadge(JobStatus status) {
    Color bgColor;
    Color textColor;

    switch (status) {
      case JobStatus.pendiente:
        bgColor = Colors.grey.shade100;
        textColor = Colors.grey.shade700;
        break;
      case JobStatus.diagnostico:
        bgColor = Colors.blue.shade50;
        textColor = Colors.blue.shade700;
        break;
      case JobStatus.enCurso:
        bgColor = Colors.green.shade50;
        textColor = Colors.green.shade700;
        break;
      case JobStatus.esperandoRepuestos:
        bgColor = Colors.orange.shade50;
        textColor = Colors.orange.shade700;
        break;
      case JobStatus.finalizado:
        bgColor = Colors.purple.shade50;
        textColor = Colors.purple.shade700;
        break;
      case JobStatus.entregado:
        bgColor = Colors.teal.shade50;
        textColor = Colors.teal.shade700;
        break;
      case JobStatus.cancelado:
        bgColor = Colors.red.shade50;
        textColor = Colors.red.shade700;
        break;
      case JobStatus.esperandoAprobacion:
        bgColor = Colors.amber.shade50;
        textColor = Colors.amber.shade700;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.displayName,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  // ============================================================
  // DESKTOP LAYOUT - Keep existing design
  // ============================================================
  Widget _buildDesktopLayout() {
    final stats = _calculateStats();

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Gestión de Trabajos',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SplitNewJobButton(
                onMainPressed: () {
                  context.push('/taller/pegas/nueva').then((_) => _loadData());
                },
                onTypeSelected: (type) {
                  context
                      .push('/taller/pegas/nueva?type=$type')
                      .then((_) => _loadData());
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
              // Priority filters
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const Text('Prioridad: ', style: TextStyle(fontSize: 13)),
                    _buildFilterChip('Todas', null, isStatus: false),
                    const SizedBox(width: 8),
                    _buildFilterChip('Urgente', JobPriority.urgente,
                        isStatus: false),
                    const SizedBox(width: 8),
                    _buildFilterChip('Alta', JobPriority.alta, isStatus: false),
                    const SizedBox(width: 8),
                    _buildFilterChip('Normal', JobPriority.normal,
                        isStatus: false),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Controls row
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
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
                    FilterChip(
                      label: const Text('Ver completados'),
                      selected: _showCompleted,
                      onSelected: (selected) {
                        setState(() => _showCompleted = selected);
                        _loadData();
                      },
                    ),
                    const SizedBox(width: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                            value: 'cards',
                            icon: Icon(Icons.view_agenda, size: 16),
                            label: Text('Tarjetas')),
                        ButtonSegment(
                            value: 'table',
                            icon: Icon(Icons.table_rows, size: 16),
                            label: Text('Tabla')),
                      ],
                      selected: {_viewMode},
                      onSelectionChanged: (selected) {
                        setState(() {
                          _viewMode = selected.first;
                          _currentPage = 0;
                        });
                        _saveViewMode(_viewMode);
                      },
                      style: const ButtonStyle(
                          visualDensity: VisualDensity.compact),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/taller/calendario'),
                      icon: const Icon(Icons.calendar_month, size: 16),
                      label: const Text('Calendario'),
                      style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact),
                    ),
                  ],
                ),
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
              gradient:
                  LinearGradient(colors: [Colors.blue[50]!, Colors.blue[100]!]),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                    'Total', stats['total'].toString(), Icons.view_list),
                _buildStatItem(
                    'Urgente', stats['urgente'].toString(), Icons.priority_high,
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
              ? const Center(child: BrandedLoading())
              : _selectedJob == null
                  ? _buildFullView()
                  : _buildSplitView(),
        ),
      ],
    );
  }

  Widget _buildFullView() {
    return _viewMode == 'table' ? _buildTableView() : _buildJobsList();
  }

  Widget _buildSplitView() {
    return Row(
      children: [
        // Left pane - Jobs list
        Container(
          width: _listPaneWidth,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              right: BorderSide(color: Colors.grey[300]!, width: 1),
            ),
          ),
          child: _viewMode == 'table' ? _buildTableView() : _buildJobsList(),
        ),

        // Resize handle
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            onHorizontalDragUpdate: (details) {
              setState(() {
                _listPaneWidth = (_listPaneWidth + details.delta.dx)
                    .clamp(_minListPaneWidth, _maxListPaneWidth);
              });
            },
            onHorizontalDragEnd: (_) {
              _saveListPaneWidth(_listPaneWidth);
            },
            child: Container(
              width: 1,
              color: Colors.grey[300],
              child: Center(
                child: Container(
                  width: 8,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ),

        // Right pane - Detail view
        Expanded(
          child: _buildDetailView(isMobile: false),
        ),
      ],
    );
  }

  Widget _buildDetailView({required bool isMobile}) {
    return Stack(
      children: [
        PegaDetailView(
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
          onEdit: () {
            context
                .push('/taller/pegas/${_selectedJob!.id}/edit')
                .then((_) => _loadData());
          },
          onStatusChange: (newStatus) {
            _updateJobStatus(_selectedJob!, newStatus);
          },
          onItemRemoved: (itemId) async {
            try {
              await _bikeshopService.deleteJobItem(itemId);
              if (_selectedJob != null) {
                setState(() => _loadingDetails = true);
                await _loadJobDetails(_selectedJob!);
              }
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Producto o servicio eliminado')),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error eliminando ítem: $e')),
                );
              }
            }
          },
        ),
        if (isMobile)
          Positioned(
            left: 16,
            top: 16,
            child: CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _selectedJob = null;
                  });
                },
              ),
            ),
          ),
        if (_loadingDetails)
          const Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: Align(
                alignment: Alignment.topCenter,
                child: LinearProgressIndicator(minHeight: 2),
              ),
            ),
          ),
      ],
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
                  context.push('/taller/pegas/nueva').then((_) => _loadData());
                },
              ),
            ],
          ],
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1400),
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _filteredJobs.length,
          itemBuilder: (context, index) {
            final job = _filteredJobs[index];
            final customer = _customers[job.customerId];
            final bike = _bikes[job.bikeId];

            return _buildJobCard(job, customer, bike);
          },
        ),
      ),
    );
  }

  Widget _buildJobCard(MechanicJob job, Customer? customer, Bike? bike) {
    final isOverdue = job.deliveryDeadline != null &&
        job.deliveryDeadline!.isBefore(DateTime.now()) &&
        job.status != JobStatus.finalizado;

    return Card(
      margin: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isOverdue ? Colors.red.shade300 : Colors.grey.shade200,
          width: isOverdue ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          print('🔵 DEBUG: Pega card tapped! Job: ${job.jobNumber}');
          setState(() {
            _selectedJob = job;
            _loadingDetails = true;
            _selectedJobItems = [];
            _productImages = {};
            print('🔵 DEBUG: _selectedJob set to: ${_selectedJob?.jobNumber}');
          });
          _loadJobDetails(job);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(20),
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
                              job.jobNumber ?? 'Sin #úmero',
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
                        if (job.deliveryDeadline != null) ...[
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
                                _formatDate(job.deliveryDeadline!),
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
                                const Text(
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
        color: color.withValues(alpha: 0.1),
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
        color: color.withValues(alpha: 0.1),
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

  // ========== TABLE VIEW ==========

  Widget _buildTableView() {
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
                  context.push('/taller/pegas/nueva').then((_) => _loadData());
                },
              ),
            ],
          ],
        ),
      );
    }

    final theme = Theme.of(context);
    final startIndex = _currentPage * _rowsPerPage;
    final endIndex = (startIndex + _rowsPerPage).clamp(0, _filteredJobs.length);
    final pageJobs = _filteredJobs.sublist(startIndex, endIndex);

    return Column(
      children: [
        // Table
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Container(
                constraints: BoxConstraints(
                  minWidth: MediaQuery.of(context).size.width - 32,
                ),
                child: DataTable(
                  headingRowHeight: 56,
                  dataRowMinHeight: 48,
                  dataRowMaxHeight: 64,
                  showCheckboxColumn: false,
                  columnSpacing: 24,
                  headingRowColor: WidgetStateProperty.resolveWith(
                    (states) => theme.colorScheme.surfaceContainerHighest,
                  ),
                  columns: [
                    DataColumn(
                      label: const Text('N°',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _sortBy = 'job_number';
                          _sortAscending = ascending;
                          _applyFiltersAndSort();
                        });
                      },
                    ),
                    DataColumn(
                      label: const Text('Cliente',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _sortBy = 'customer';
                          _sortAscending = ascending;
                          _applyFiltersAndSort();
                        });
                      },
                    ),
                    const DataColumn(
                      label: Text('Bicicleta',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    DataColumn(
                      label: const Text('Estado',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _sortBy = 'status';
                          _sortAscending = ascending;
                          _applyFiltersAndSort();
                        });
                      },
                    ),
                    DataColumn(
                      label: const Text('Prioridad',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      numeric: false,
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _sortBy = 'priority';
                          _sortAscending = ascending;
                          _applyFiltersAndSort();
                        });
                      },
                    ),
                    DataColumn(
                      label: const Text('Ingreso',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _sortBy = 'arrival_date';
                          _sortAscending = ascending;
                          _applyFiltersAndSort();
                        });
                      },
                    ),
                    DataColumn(
                      label: const Text('Plazo',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _sortBy = 'deadline';
                          _sortAscending = ascending;
                          _applyFiltersAndSort();
                        });
                      },
                    ),
                    const DataColumn(
                      label: Text('Acciones',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                  rows: pageJobs.map((job) {
                    final customer = _customers[job.customerId];
                    final bike = _bikes[job.bikeId];
                    final isOverdue = job.deliveryDeadline != null &&
                        job.deliveryDeadline!.isBefore(DateTime.now()) &&
                        job.status != JobStatus.finalizado;

                    return DataRow(
                      color: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.hovered)) {
                          return theme.colorScheme.surfaceContainerHigh;
                        }
                        if (isOverdue) {
                          return Colors.red.shade50;
                        }
                        return null;
                      }),
                      onSelectChanged: (_) {
                        setState(() {
                          _selectedJob = job;
                          _loadingDetails = true;
                          _selectedJobItems = [];
                          _productImages = {};
                        });
                        _loadJobDetails(job);
                      },
                      cells: [
                        DataCell(
                          Text(
                            job.jobNumber ?? 'S/N',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            customer?.name ?? 'Cliente no encontrado',
                            style: TextStyle(
                              color: customer == null ? Colors.grey : null,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            bike != null
                                ? '${bike.brand ?? ''} ${bike.model ?? ''}'
                                    .trim()
                                : 'Sin bicicleta',
                            style: TextStyle(
                              fontSize: 13,
                              color: bike == null ? Colors.grey : null,
                            ),
                          ),
                        ),
                        DataCell(_buildTableStatusChip(job.status)),
                        DataCell(_buildTablePriorityChip(job.priority)),
                        DataCell(
                          Text(_formatDate(job.arrivalDate)),
                        ),
                        DataCell(
                          Row(
                            children: [
                              Text(
                                job.deliveryDeadline != null
                                    ? _formatDate(job.deliveryDeadline!)
                                    : 'Sin plazo',
                                style: TextStyle(
                                  color: isOverdue ? Colors.red : null,
                                  fontWeight:
                                      isOverdue ? FontWeight.bold : null,
                                ),
                              ),
                              if (isOverdue) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.warning,
                                    size: 16, color: Colors.red),
                              ],
                            ],
                          ),
                        ),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.visibility, size: 18),
                                tooltip: 'Ver detalles',
                                onPressed: () {
                                  setState(() {
                                    _selectedJob = job;
                                    _loadingDetails = true;
                                    _selectedJobItems = [];
                                    _productImages = {};
                                  });
                                  _loadJobDetails(job);
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                tooltip: 'Editar',
                                onPressed: () {
                                  context
                                      .push('/taller/pegas/${job.id}/edit')
                                      .then((_) => _loadData());
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
        // Pagination controls
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                  _saveRowsPerPage(value!);
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
        ),
      ],
    );
  }

  Widget _buildTableStatusChip(JobStatus status) {
    Color color;
    switch (status) {
      case JobStatus.pendiente:
        color = Colors.orange;
        break;
      case JobStatus.diagnostico:
        color = Colors.blue;
        break;
      case JobStatus.enCurso:
        color = Colors.green;
        break;
      case JobStatus.esperandoRepuestos:
        color = Colors.purple;
        break;
      case JobStatus.esperandoAprobacion:
        color = Colors.amber;
        break;
      case JobStatus.finalizado:
        color = Colors.grey;
        break;
      case JobStatus.entregado:
        color = Colors.teal;
        break;
      case JobStatus.cancelado:
        color = Colors.red;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        status.displayName,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildTablePriorityChip(JobPriority priority) {
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

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          priority.displayName,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
