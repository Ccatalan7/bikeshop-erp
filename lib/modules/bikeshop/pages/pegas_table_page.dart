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
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';

import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/asset_pdf_preview_dialog.dart';
import '../../../shared/widgets/hover_zoom_image.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/interactive_table_field.dart';
import '../../../shared/widgets/modern_context_menu.dart';
import '../../../shared/widgets/operational_status_badge.dart';
import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_anchored_popover.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/utils/invoice_pdf_generator.dart';
import '../../../shared/utils/responsive_viewport.dart';
import '../../crm/models/crm_models.dart';
import '../../crm/services/customer_service.dart';
import '../../sales/models/sales_models.dart';
import '../../sales/services/sales_service.dart';
import '../../sales/widgets/payment_form.dart';
import '../../sales/widgets/sales_invoice_editor.dart';
import '../../settings/services/appearance_service.dart';

import '../../../shared/services/image_service.dart';
import '../../ai_assistant/services/ai_assistant_context_service.dart';
import '../services/bikeshop_service.dart';
import '../services/job_status_service.dart';
import '../services/mechanic_job_intake_classification_coordinator.dart';
import '../services/mechanic_job_quotation_command_coordinator.dart';
import '../services/mechanic_job_sale_classification_coordinator.dart';
import '../services/mechanic_job_sale_ui_policy.dart';
import '../services/mechanic_job_visibility_policy.dart';
import '../services/mechanic_job_warranty_command_coordinator.dart';
import '../services/workshop_jobs_load_coordinator.dart';
import '../models/bikeshop_models.dart';
import '../widgets/pega_detail_view.dart';
import '../widgets/pegas_calendar_widget.dart';
import '../widgets/deadline_cell.dart';
import '../widgets/job_time_metrics_widget.dart';
import '../widgets/smart_job_details_editor.dart';
import '../widgets/pegas_tasks_widget.dart';
import '../widgets/workshop_board_compact_view.dart';
import '../widgets/workshop_mobile_bike_chooser.dart';
import '../widgets/workshop_mobile_payment_workspace.dart';
import '../widgets/workshop_status_filter_header.dart';
import 'bike_form_dialog.dart';
import 'mechanic_job_form_page.dart';

/// Modern, professional Trabajos management with advanced data table
class PegasTablePage extends StatefulWidget {
  const PegasTablePage({super.key});

  @override
  State<PegasTablePage> createState() => _PegasTablePageState();
}

enum _MobileWorkshopSurface {
  job,
  items,
  bike,
  invoice,
  payment,
  proposalPdf,
}

class _MobileWorkshopWorkspace {
  _MobileWorkshopWorkspace({
    required this.surface,
    required this.job,
    this.bike,
    this.invoice,
    this.proposalPdf,
  }) : childKey = GlobalKey();

  final _MobileWorkshopSurface surface;
  final MechanicJob job;
  final Bike? bike;
  final Invoice? invoice;
  final Future<_WorkshopProposalPdfArtifact>? proposalPdf;
  final GlobalKey childKey;
}

class _WorkshopProposalPdfArtifact {
  const _WorkshopProposalPdfArtifact({
    required this.bytes,
    required this.fileName,
    required this.documentLabel,
  });

  final Uint8List bytes;
  final String fileName;
  final String documentLabel;
}

class _BicycleStatusBreakdownEntry {
  _BicycleStatusBreakdownEntry({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;
  int count = 0;
}

class _JobConversionChoice {
  const _JobConversionChoice({
    required this.targetType,
    this.bikeId,
    this.subjectId,
    this.reason,
    this.createBike = false,
  });

  final JobType targetType;
  final String? bikeId;
  final String? subjectId;
  final String? reason;
  final bool createBike;

  bool matches(_JobConversionChoice other) =>
      targetType == other.targetType &&
      bikeId == other.bikeId &&
      subjectId == other.subjectId &&
      _normalized(reason) == _normalized(other.reason) &&
      createBike == other.createBike;

  static String? _normalized(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

class _JobIntakeClassificationChoice {
  const _JobIntakeClassificationChoice({
    required this.intakeKind,
    this.bikeId,
    this.subjectId,
    this.subjectNotes,
    this.reason,
  });

  final JobIntakeKind intakeKind;
  final String? bikeId;
  final String? subjectId;
  final String? subjectNotes;
  final String? reason;
}

class _PendingWarrantyDecisionAttempt {
  const _PendingWarrantyDecisionAttempt({
    required this.outcome,
    required this.reason,
    required this.operationKey,
  });

  final WarrantyOutcome outcome;
  final String? reason;
  final String operationKey;

  bool matches(WarrantyOutcome nextOutcome, String? nextReason) =>
      outcome == nextOutcome && reason == nextReason;
}

class _PendingJobIntakeClassificationAttempt {
  const _PendingJobIntakeClassificationAttempt({
    required this.choice,
    required this.operationKey,
  });

  final _JobIntakeClassificationChoice choice;
  final String operationKey;
}

class _PendingQuotationTransitionAttempt {
  const _PendingQuotationTransitionAttempt({
    required this.status,
    required this.reason,
    required this.operationKey,
  });

  final QuotationStatus status;
  final String? reason;
  final String operationKey;

  bool matches(QuotationStatus nextStatus, String? nextReason) =>
      status == nextStatus && reason == nextReason;
}

class _PendingQuotationConversionAttempt {
  const _PendingQuotationConversionAttempt({
    required this.choice,
    required this.operationKey,
  });

  final _JobConversionChoice choice;
  final String operationKey;

  bool matches(_JobConversionChoice nextChoice) => choice.matches(nextChoice);
}

class _HoverCardTooltip extends StatefulWidget {
  const _HoverCardTooltip({
    required this.child,
    required this.tooltip,
    this.offset = const Offset(0, 24),
    this.showDelay = const Duration(milliseconds: 650),
  });

  final Widget child;
  final Widget tooltip;
  final Offset offset;
  final Duration showDelay;

  @override
  State<_HoverCardTooltip> createState() => _HoverCardTooltipState();
}

class _HoverCardTooltipState extends State<_HoverCardTooltip> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;
  Timer? _showTimer;

  void _show() {
    if (_entry != null) return;
    _showTimer?.cancel();
    _showTimer = Timer(widget.showDelay, () {
      if (!mounted || _entry != null) return;
      _insertEntry();
    });
  }

  void _insertEntry() {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    _entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: IgnorePointer(
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            offset: widget.offset,
            child: Align(
              alignment: Alignment.topLeft,
              widthFactor: 1,
              heightFactor: 1,
              child: widget.tooltip,
            ),
          ),
        ),
      ),
    );

    overlay.insert(_entry!);
  }

  void _hide() {
    _showTimer?.cancel();
    _showTimer = null;
    _entry?.remove();
    _entry = null;
  }

  @override
  void didUpdateWidget(covariant _HoverCardTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_entry != null && widget.tooltip != oldWidget.tooltip) {
      _entry?.markNeedsBuild();
    }
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        onEnter: (_) => _show(),
        onExit: (_) => _hide(),
        child: widget.child,
      ),
    );
  }
}

class _PegasTablePageState extends State<PegasTablePage>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  static const double _mobileJobsTabletGridMinWidth = 720;

  static const String _debugTestCustomerName = 'Test Taller';
  static const Color _workshopCommandColor = Color(0xFF12324A);
  static const Color _workshopSettledColor = Color(0xFF1F6F78);

  // Keep this page alive to preserve state when navigating away
  @override
  bool get wantKeepAlive => true;

  late BikeshopService _bikeshopService;
  late CustomerService _customerService;
  late JobStatusService _jobStatusService;
  late SalesService _salesService;
  late AIAssistantContextService _aiAssistantContextService;
  final TenantService _tenantService = TenantService();

  List<MechanicJob> _jobs = [];
  List<MechanicJob> _filteredJobs = [];
  Map<String, Customer> _customers = {};
  final Set<String> _generatingQuotationPdfIds = <String>{};
  final Map<String, _PendingJobIntakeClassificationAttempt>
      _pendingIntakeClassificationAttempts = {};
  final Map<String, _PendingWarrantyDecisionAttempt>
      _pendingWarrantyDecisionAttempts = {};
  final Map<String, _PendingQuotationTransitionAttempt>
      _pendingQuotationTransitionAttempts = {};
  final Map<String, _PendingQuotationConversionAttempt>
      _pendingQuotationConversionAttempts = {};
  Map<String, Bike> _bikes = {};
  Map<String, Invoice> _invoices = {};
  Map<String, List<MechanicJobItem>> _jobItemsMap = {};
  Map<String, String> _productImages = {};
  Map<String, List<MechanicJobBike>> _jobBikesMap = {}; // Multi-bike support

  // Expanded rows (multi-bike display)
  final Set<String> _expandedJobIds = {};
  String? _draggingJobId; // To track which row is being dragged over

  bool _isLoading = true;
  bool _isCreatingDebugJob = false;
  bool _needsRefresh = false;

  /// Who is allowed to publish a load. See [WorkshopJobsLoadCoordinator].
  final WorkshopJobsLoadCoordinator _jobsLoadCoordinator =
      WorkshopJobsLoadCoordinator();
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
  final ScrollController _mobileJobsScrollController = ScrollController();
  final TextEditingController _mobileSearchController = TextEditingController();
  bool _isColumnResizing = false;
  double? _lockedHorizontalScrollOffset;

  // Selected job for detail view
  MechanicJob? _selectedJob;
  List<MechanicJobItem> _selectedJobItems = [];

  // Split-pane state
  static const String _splitPaneEnabledPrefsKey = 'pegas_split_pane_enabled';
  static const double _minListPaneWidth = 500.0;
  static const double _minDetailPaneWidth = 400.0;
  static const double _defaultListPaneWidth = 1000.0;
  bool _isSplitPaneEnabled = false;
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
      false; // false = include selected, true = exclude selected
  final Set<JobPriority> _priorityFilter = {};
  bool _showOnlyOverdue = false;
  bool _showOnlyUnpaid = false;
  final WorkshopBoardCompactSession _compactBoardSession =
      WorkshopBoardCompactSession();
  final PegasCalendarSession _calendarSession = PegasCalendarSession();
  final PegasTasksSession _tasksSession = PegasTasksSession();

  void _toggleCustomStatusFilter(String statusKey) {
    if (!_customStatusFilter.add(statusKey)) {
      _customStatusFilter.remove(statusKey);
    }
    if (_customStatusFilter.isEmpty) {
      _statusFilterExcludeMode = false;
    }
  }

  // Pagination
  int _currentPage = 0;
  int _rowsPerPage = 25;

  // Bulk selection
  final Set<String> _selectedJobIds = {};
  bool get _isAnySelected => _selectedJobIds.isNotEmpty;

  // Column drag state for live preview
  String? _draggingColumnId;
  int? _dragTargetIndex;

  /// Get columns in display order (with live preview during drag)
  List<ColumnConfig> get _displayColumns {
    final visibleColumns =
        _columns.where((col) => col.visible && col.id != 'status').toList();
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
  final ScrollController _ganttHorizontalScrollController = ScrollController();
  final ScrollController _ganttVerticalScrollController = ScrollController();
  double _ganttHorizontalOffset = 0;
  double _ganttVerticalOffset = 0;
  bool _ganttRestoreScheduled = false;

  // Calendar view state - moved to PegasCalendarWidget (shared widget)

  // MOBILE UI STATE
  bool _isSearchExpanded = false;
  final Set<String> _expandedMobileJobKeys = <String>{};
  _MobileWorkshopWorkspace? _mobileWorkshopWorkspace;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bikeshopService = Provider.of<BikeshopService>(context, listen: false);
    _customerService = Provider.of<CustomerService>(context, listen: false);
    _jobStatusService = Provider.of<JobStatusService>(context, listen: false);
    _salesService = Provider.of<SalesService>(context, listen: false);
    _aiAssistantContextService =
        Provider.of<AIAssistantContextService>(context, listen: false);
    _ganttHorizontalScrollController.addListener(_rememberGanttScroll);
    _ganttVerticalScrollController.addListener(_rememberGanttScroll);
    debugPrint(
      '[AI_CTX][PegasTable.init] contextId=${identityHashCode(_aiAssistantContextService)} '
      'bikeshopServiceId=${identityHashCode(_bikeshopService)}',
    );

    // Listen to BikeshopService changes (realtime updates for jobs AND invoices)
    _bikeshopService.addListener(_onBikeshopServiceChanged);

    _initializeColumns();
    _loadColumnOrder(); // Load saved column order
    _loadSplitPanePreference();
    _loadListPaneWidth();
    _restoreTableState(); // Restore filters, pagination, sort from service
    _mobileSearchController.text = _searchTerm;
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

  List<String> _statusFilterOptions() => [
        'active',
        if (kDebugMode) 'test',
        'completed',
        'delivered',
        'service_warranty_active',
        'warranty_completed',
        'quotations_closed',
        'unpaid',
        'deleted',
        'all',
      ];

  String _statusFilterLabel(String value) {
    switch (value) {
      case 'active':
        return 'Activos';
      case 'test':
        return 'Tests';
      case 'completed':
        return 'Completados';
      case 'delivered':
        return 'Entregados';
      case 'service_warranty_active':
        return 'Garantía vigente';
      case 'warranty_completed':
        return 'Garantías cerradas';
      case 'quotations_closed':
        return 'Cotizaciones cerradas';
      case 'unpaid':
        return 'Sin pagar';
      case 'deleted':
        return 'Eliminados';
      case 'all':
        return 'Todos';
      default:
        return 'Activos';
    }
  }

  String _aiAssistantJobsScopeLabel() {
    switch (_statusFilter) {
      case 'active':
        return 'trabajos activos';
      case 'completed':
        return 'trabajos completados';
      case 'delivered':
        return 'trabajos entregados';
      case 'service_warranty_active':
        return 'trabajos con garantía de servicio vigente';
      case 'warranty_completed':
        return 'trabajos de garantía completados';
      case 'quotations_closed':
        return 'cotizaciones cerradas';
      case 'unpaid':
        return 'trabajos sin pagar';
      case 'test':
        return 'trabajos de prueba';
      case 'deleted':
        return 'trabajos eliminados';
      case 'all':
      default:
        return 'trabajos visibles';
    }
  }

  String _debugAiJobNumbers(List<MechanicJob> jobs) {
    final numbers = jobs
        .take(12)
        .map((job) => job.jobNumber ?? job.id ?? 'sin-numero')
        .join(', ');
    if (jobs.length <= 12) {
      return numbers;
    }
    return '$numbers, ... +${jobs.length - 12}';
  }

  bool _isJobCurrentlyDelivered(MechanicJob job) {
    return isMechanicJobCurrentlyDelivered(job);
  }

  Color _statusFilterColor(String value) {
    switch (value) {
      case 'active':
        return const Color(0xFF2563EB);
      case 'test':
        return const Color(0xFF7C3AED);
      case 'completed':
        return const Color(0xFF0F766E);
      case 'delivered':
        return const Color(0xFF0891B2);
      case 'service_warranty_active':
        return const Color(0xFF059669);
      case 'warranty_completed':
        return const Color(0xFF9333EA);
      case 'quotations_closed':
        return const Color(0xFF64748B);
      case 'unpaid':
        return const Color(0xFFEA580C);
      case 'deleted':
        return const Color(0xFFB91C1C);
      case 'all':
        return const Color(0xFF64748B);
      default:
        return _workshopCommandColor;
    }
  }

  String _statusFilterGlyph(String value) {
    switch (value) {
      case 'active':
        return '⚡';
      case 'test':
        return '🧪';
      case 'completed':
        return '✅';
      case 'delivered':
        return '📦';
      case 'service_warranty_active':
        return '🛡️';
      case 'warranty_completed':
        return '🛡️';
      case 'quotations_closed':
        return '📄';
      case 'unpaid':
        return '💵';
      case 'deleted':
        return '🗑️';
      case 'all':
        return '🗃️';
      default:
        return '⚡';
    }
  }

  String _viewModeLabel(String value) {
    switch (value) {
      case 'table':
        return 'Tabla';
      case 'board':
        return 'Tablero';
      case 'calendar':
        return 'Calendario';
      case 'gantt':
        return 'Gantt';
      case 'tasks':
        return 'Tareas';
      default:
        return 'Tabla';
    }
  }

  Color _viewModeColor(String value) {
    switch (value) {
      case 'table':
        return const Color(0xFF2563EB);
      case 'board':
        return const Color(0xFF4F46E5);
      case 'calendar':
        return const Color(0xFFB45309);
      case 'gantt':
        return const Color(0xFF7C3AED);
      case 'tasks':
        return const Color(0xFF0F766E);
      default:
        return _workshopCommandColor;
    }
  }

  String _viewModeGlyph(String value) {
    switch (value) {
      case 'table':
        return '📋';
      case 'board':
        return '🗂️';
      case 'calendar':
        return '📅';
      case 'gantt':
        return '📊';
      case 'tasks':
        return '✅';
      default:
        return '📋';
    }
  }

  Widget _buildDropdownGlyph(String glyph) {
    return SizedBox(
      width: 24,
      height: 24,
      child: Center(
        child: Text(
          glyph,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 17,
            height: 1,
            fontFamilyFallback: [
              'Apple Color Emoji',
              'Noto Color Emoji',
              'Segoe UI Emoji',
            ],
          ),
        ),
      ),
    );
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
    debugPrint(
      '[AI_CTX][PegasTable.dispose] contextId=${identityHashCode(_aiAssistantContextService)} '
      'lastFiltered=${_filteredJobs.length}',
    );
    _aiAssistantContextService.clearVisibleJobsContext();
    _bikeshopService.removeListener(_onBikeshopServiceChanged);
    // A response that arrives after the page is gone owns nothing.
    _jobsLoadCoordinator.dispose();
    _reloadDebounceTimer?.cancel();
    _horizontalScrollController.dispose();
    _mobileJobsScrollController.dispose();
    _mobileSearchController.dispose();
    _ganttHorizontalScrollController
      ..removeListener(_rememberGanttScroll)
      ..dispose();
    _ganttVerticalScrollController
      ..removeListener(_rememberGanttScroll)
      ..dispose();
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
        label: 'Flujo',
        width: 132,
        minWidth: 120,
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
          debugPrint('🔄 Data changed signal received, reloading trabajos...');
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
    // Route-level ScaffoldMessenger state survives navigation. Workshop
    // proposal feedback is no longer relevant once the linked invoice opens.
    _clearQuotationSnackBars();
    _markNeedsRefresh();
    await context
        .push('/sales/invoices/$invoiceId/edit?returnTo=/taller/pegas');
    if (!mounted) return;
    await _loadData();
  }

  Future<bool> _openInvoicePayment(String invoiceId) async {
    final didRegisterPayment =
        await context.push<bool>('/sales/invoices/$invoiceId/payment') ?? false;
    return mounted && didRegisterPayment;
  }

  Future<void> _registerInvoicePayment(String invoiceId) async {
    final didRegisterPayment = await _openInvoicePayment(invoiceId);
    if (!didRegisterPayment || !mounted) return;
    await _loadData(forceInvoiceRefresh: true);
  }

  Future<void> _openInvoicePreview(
    String invoiceId, {
    Invoice? invoice,
  }) async {
    _markNeedsRefresh();
    final invoiceNumber = invoice?.invoiceNumber.trim();
    final uri = Uri(
      path: '/sales/invoices',
      queryParameters: {
        'selectedInvoiceId': invoiceId,
        if (invoiceNumber != null && invoiceNumber.isNotEmpty)
          'selectedInvoiceNumber': invoiceNumber,
        'view': 'split',
      },
    );
    await context.push(uri.toString());
    if (!mounted) return;
    await _loadData();
  }

  Future<void> _showInvoiceChipContextMenu({
    required TapDownDetails details,
    required MechanicJob job,
    required Invoice? invoice,
  }) async {
    final invoiceId = job.invoiceId;
    if (invoiceId == null || invoiceId.isEmpty) return;

    final invoiceNumber = invoice?.invoiceNumber.trim().isNotEmpty == true
        ? invoice!.invoiceNumber.trim()
        : 'Factura';
    final value = await showModernContextMenu<String>(
      context: context,
      globalPosition: details.globalPosition,
      title: invoiceNumber,
      actions: const [
        ModernContextMenuAction(
          value: 'preview',
          icon: Icons.receipt_long_outlined,
          label: 'Abrir vista PDF',
          subtitle: 'Lista de facturas, panel dividido',
          iconColor: Color(0xFF2563EB),
        ),
        ModernContextMenuAction(
          value: 'edit',
          icon: Icons.edit_outlined,
          label: 'Editar factura',
          subtitle: 'Formulario completo',
          iconColor: Color(0xFF475569),
        ),
      ],
    );

    if (!mounted || value == null) return;
    if (value == 'preview') {
      await _openInvoicePreview(invoiceId, invoice: invoice);
    } else if (value == 'edit') {
      await _openInvoice(invoiceId);
    }
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

  bool _isSaleFullyPaid(MechanicJob job, {Invoice? invoice}) {
    final resolvedInvoice =
        invoice ?? (job.invoiceId != null ? _invoices[job.invoiceId] : null);
    return isMechanicJobSaleFullyPaid(job, resolvedInvoice);
  }

  bool _hasWarrantyPaymentEvidence(MechanicJob job) {
    final invoice = job.invoiceId == null ? null : _invoices[job.invoiceId];
    return job.isPaid ||
        invoice?.status == InvoiceStatus.paid ||
        (invoice?.paidAmount ?? 0) > 0.01;
  }

  bool get _canUseFreshInstantCache =>
      _bikeshopService.isJobsCacheFresh &&
      _customerService.isCustomersCacheFresh &&
      _bikeshopService.isBikesCacheFresh &&
      _bikeshopService.isJobBikesCacheFresh &&
      _salesService.isInvoicesCacheFresh;

  /// Loads the table from the services. Only the MOST RECENT call may publish
  /// or complain.
  ///
  /// Its triggers are the ones that really need a full read: first build, app
  /// resume, returning from a route, pull to refresh, and the fallback when
  /// the cache is empty. A realtime notification does NOT come through here —
  /// `_onBikeshopServiceChanged` repaints from the cache with
  /// `_refreshFromCache`, with no database fetch — and this correction leaves
  /// that surgical path exactly as it was.
  ///
  /// Each call takes a ticket first. An older load that finishes later cannot
  /// paint over a newer one, and an older load that fails cannot raise a
  /// banner about a state the operator has already left behind.
  Future<void> _loadData({
    bool surfaceErrors = true,
    bool rethrowErrors = false,
    bool forceInvoiceRefresh = false,
  }) async {
    final ticket = _jobsLoadCoordinator.start();

    // Only instant-render when all companion caches are still fresh.
    // Rendering from an expired jobs cache causes the stale first frame the user sees
    // before the full fetch corrects customer/bike names and row membership.
    if (_statusFilter != 'deleted' &&
        _canUseFreshInstantCache &&
        _jobs.isEmpty) {
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
        _bikeshopService.getJobs(
          includeCompleted: true,
          includeDeleted: _statusFilter == 'deleted',
          forceRefresh: _statusFilter == 'deleted',
        ),
        _customerService.getCustomers(),
        _bikeshopService.getBikes(),
        _loadInvoices(
          forceRefresh: forceInvoiceRefresh,
          throwOnError: rethrowErrors && forceInvoiceRefresh,
        ),
        _bikeshopService.getAllJobBikes(), // Single query for all job bikes
      ]);

      final jobs = results[0] as List<MechanicJob>;
      final customers = results[1] as List<Customer>;
      final bikes = results[2] as List<Bike>;
      final invoices = results[3] as List<Invoice>;
      final jobBikesMap = results[4] as Map<String, List<MechanicJobBike>>;
      Map<String, List<MechanicJobItem>> jobItemsMap = const {};
      try {
        jobItemsMap = await _bikeshopService.getJobItemsForJobs(
          jobs
              .where((job) =>
                  job.isSaleWorkflow ||
                  job.isQuotationWorkflow ||
                  job.modeNeedsReview)
              .map((job) => job.id)
              .whereType<String>(),
        );
      } catch (error) {
        debugPrint('Could not load compact job item summaries: $error');
      }

      final customerMap = _buildCustomerMap(customers);
      final bikeMap = _buildBikeMap(bikes);

      final invoiceMap = _buildInvoiceMap(invoices);

      // A successful OLD response is still a stale one: dropping it is what
      // keeps a newer table from being overwritten by the rows it replaced.
      if (ticket.isSuperseded) return;

      if (mounted) {
        setState(() {
          _jobs = jobs;
          _filteredJobs = jobs;
          _customers = customerMap;
          _bikes = bikeMap;
          _invoices = invoiceMap;
          _jobBikesMap = jobBikesMap;
          _jobItemsMap = jobItemsMap;
          _isLoading = false;
        });
        _applyFiltersAndSort();
      }
    } catch (e) {
      // A STALE load says nothing — not to the screen and not to its caller.
      // Its operation was already replaced by a newer one, so turning its
      // failure into an error would report a refresh that nobody is waiting
      // for any more.
      if (ticket.isSuperseded) return;

      // The typed authority outcome is separated BEFORE the generic branch.
      // `AuthorityScopeChangedException` means this read belonged to an
      // authority that is no longer current — the cache refusing to publish
      // across users or tenants, which is the guarantee we want. It is a
      // cancellation, not a failure, so it is neither shown NOR rethrown:
      // rethrowing it only moved the same internal sentence into another
      // caller's `catch`, where it came back as an orange "no se pudo
      // actualizar la tabla".
      if (WorkshopJobsLoadCoordinator.isSupersededError(e)) {
        // The data already on screen stays; only the spinner ends.
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      if (mounted) {
        setState(() => _isLoading = false);
        if (surfaceErrors) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
      // A real failure of the CURRENT load keeps its explicit outcome for a
      // caller that awaited it to verify its own operation.
      if (rethrowErrors) rethrow;
    }
  }

  Future<List<Invoice>> _loadInvoices({
    bool forceRefresh = false,
    bool throwOnError = false,
  }) async {
    try {
      await _salesService.loadInvoices(forceRefresh: forceRefresh);
      final error = _salesService.invoiceError;
      if (throwOnError && error != null) {
        throw StateError(error);
      }
      return _salesService.cachedInvoices.toList();
    } catch (_) {
      if (throwOnError) rethrow;
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

  Future<void> _loadSplitPanePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_splitPaneEnabledPrefsKey) ?? false;
    if (mounted) {
      setState(() => _isSplitPaneEnabled = enabled);
    }
  }

  Future<void> _saveSplitPanePreference(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_splitPaneEnabledPrefsKey, enabled);
  }

  void _toggleSplitPane() {
    final enabled = !_isSplitPaneEnabled;
    setState(() {
      _isSplitPaneEnabled = enabled;
      if (!enabled) {
        _selectedJob = null;
        _selectedJobItems = [];
        _productImages = {};
      }
    });
    unawaited(_saveSplitPanePreference(enabled));
  }

  Future<void> _openJobEditor(MechanicJob job) async {
    await _openJobEditorAt(job);
  }

  Future<void> _openJobEditorAt(
    MechanicJob job, {
    String? initialTab,
  }) async {
    final jobId = job.id;
    if (jobId == null || jobId.isEmpty) return;

    _markNeedsRefresh();
    final route = Uri(
      path: '/taller/pegas/$jobId',
      queryParameters:
          initialTab == null ? null : <String, String>{'tab': initialTab},
    ).toString();
    final result = await context.push(route);
    if (!mounted) return;
    if (result == true) {
      await _loadData();
    }
  }

  Future<void> _openJobProductsAndServices(MechanicJob job) {
    return _openJobEditorAt(job, initialTab: 'products');
  }

  void _openMobileInlineSurface(
    MechanicJob job,
    _MobileWorkshopSurface surface, {
    Bike? bike,
  }) {
    final jobId = job.id?.trim();
    if (jobId == null || jobId.isEmpty) return;

    setState(() {
      _mobileWorkshopWorkspace = _MobileWorkshopWorkspace(
        surface: surface,
        job: job,
        bike: bike,
        proposalPdf: surface == _MobileWorkshopSurface.proposalPdf
            ? _buildQuotationPdfArtifact(job)
            : null,
      );
    });
  }

  void _closeMobileInlineSurface() {
    if (_mobileWorkshopWorkspace == null || !mounted) return;
    setState(() => _mobileWorkshopWorkspace = null);
  }

  void _handleMobileInlineSave() {
    if (!mounted) return;
    setState(() => _mobileWorkshopWorkspace = null);
    unawaited(_loadData(forceInvoiceRefresh: true));
  }

  void _handleMobileBikeSave(Bike bike) {
    if (!mounted) return;
    setState(() {
      final bikeId = bike.id;
      if (bikeId != null && bikeId.isNotEmpty) {
        _bikes[bikeId] = bike;
      }
      _mobileWorkshopWorkspace = null;
    });
    unawaited(_loadData());
  }

  Future<void> _handleMobileInlinePaymentRequested(Invoice invoice) async {
    final invoiceId = invoice.id?.trim();
    if (invoiceId == null || invoiceId.isEmpty) return;
    final workspace = _mobileWorkshopWorkspace;
    if (workspace == null || !mounted) return;

    setState(() {
      _mobileWorkshopWorkspace = _MobileWorkshopWorkspace(
        surface: _MobileWorkshopSurface.payment,
        job: _currentMobileWorkspaceJob(workspace),
        invoice: invoice,
      );
    });
  }

  void _returnMobilePaymentToInvoice() {
    final workspace = _mobileWorkshopWorkspace;
    if (workspace == null || !mounted) return;

    setState(() {
      _mobileWorkshopWorkspace = _MobileWorkshopWorkspace(
        surface: _MobileWorkshopSurface.invoice,
        job: _currentMobileWorkspaceJob(workspace),
      );
    });
  }

  void _handleMobilePaymentCompleted() {
    if (!mounted) return;
    setState(() => _mobileWorkshopWorkspace = null);
    unawaited(_loadData(forceInvoiceRefresh: true));
  }

  List<Bike> _linkedBikesForJob(MechanicJob job) {
    final bikesById = <String, Bike>{};
    final jobId = job.id?.trim();
    final links = jobId == null
        ? <MechanicJobBike>[]
        : List<MechanicJobBike>.from(
            _jobBikesMap[jobId] ?? const <MechanicJobBike>[],
          );
    links.sort((a, b) {
      final order = a.orderIndex.compareTo(b.orderIndex);
      return order != 0 ? order : a.bikeId.compareTo(b.bikeId);
    });

    for (final link in links) {
      final bike = _bikes[link.bikeId] ?? link.bike;
      final bikeId = bike?.id?.trim();
      if (bike == null || bikeId == null || bikeId.isEmpty) continue;
      bikesById[bikeId] = bike;
    }

    final primaryBikeId = job.bikeId?.trim();
    if (primaryBikeId != null && primaryBikeId.isNotEmpty) {
      final primaryBike = _bikes[primaryBikeId];
      if (primaryBike != null) {
        bikesById.putIfAbsent(primaryBikeId, () => primaryBike);
      }
    }

    return bikesById.values.toList(growable: false);
  }

  Future<Bike?> _showMobileBikeChooser(
    MechanicJob job,
    List<Bike> bikes,
    int linkedBikeCount,
  ) {
    final jobLabel = job.jobNumber?.trim().isNotEmpty == true
        ? job.jobNumber!.trim()
        : 'este trabajo';

    return showModalBottomSheet<Bike>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => WorkshopMobileBikeChooser(
        jobLabel: jobLabel,
        linkedBikeCount: linkedBikeCount,
        bikes: bikes,
        onSelected: (bike) => Navigator.of(sheetContext).pop(bike),
        onClose: () => Navigator.of(sheetContext).pop(),
      ),
    );
  }

  Future<void> _openMobileJobBike(
    MechanicJob job,
    Customer? customer,
  ) async {
    final customerId = customer?.id?.trim();
    if (customerId == null || customerId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cliente no encontrado')),
      );
      return;
    }

    final bikes = _linkedBikesForJob(job);
    if (bikes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bicicleta no encontrada')),
      );
      return;
    }

    final linkedBikeCount = _jobBikesMap[job.id]?.length ?? bikes.length;
    final selectedBike = linkedBikeCount > 1
        ? await _showMobileBikeChooser(job, bikes, linkedBikeCount)
        : bikes.first;
    if (!mounted || selectedBike == null) return;

    _openMobileInlineSurface(
      job,
      _MobileWorkshopSurface.bike,
      bike: selectedBike,
    );
  }

  MechanicJob _currentMobileWorkspaceJob(_MobileWorkshopWorkspace workspace) {
    final jobId = workspace.job.id;
    if (jobId == null) return workspace.job;
    return _jobs.where((job) => job.id == jobId).firstOrNull ?? workspace.job;
  }

  Bike? _currentMobileWorkspaceBike(_MobileWorkshopWorkspace workspace) {
    final bike = workspace.bike;
    final bikeId = bike?.id?.trim();
    if (bikeId == null || bikeId.isEmpty) return bike;
    return _bikes[bikeId] ?? bike;
  }

  bool _canRegisterPaymentForJob(MechanicJob job) {
    final invoiceId = job.invoiceId;
    if (invoiceId == null || invoiceId.isEmpty) return false;
    final invoice = _invoices[invoiceId];
    if (invoice == null ||
        invoice.status == InvoiceStatus.paid ||
        invoice.status == InvoiceStatus.cancelled) {
      return false;
    }
    return invoice.total - invoice.paidAmount > 0.01;
  }

  void _openJobFromTable(MechanicJob job) {
    if (ResponsiveViewport.usesCompactShell(context)) {
      _openMobileInlineSurface(job, _MobileWorkshopSurface.job);
      return;
    }

    final useSplitPane = _isSplitPaneEnabled;
    if (useSplitPane) {
      setState(() {
        _selectedJob = job;
        _selectedJobItems = [];
        _productImages = {};
      });
      unawaited(_loadJobDetails(job));
      return;
    }

    unawaited(_openJobEditor(job));
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
    debugPrint(
      '[AI_CTX][PegasTable.apply.start] jobs=${_jobs.length} '
      'filteredBefore=${_filteredJobs.length} statusFilter=$_statusFilter '
      'search="$_searchTerm" hasContextService=${identityHashCode(_aiAssistantContextService)}',
    );
    final hasCustomStatusFilter = _customStatusFilter.isNotEmpty;

    var filtered = _jobs.where((job) {
      if (_statusFilter == 'deleted') {
        if (job.deletedAt == null) return false;
      } else if (job.deletedAt != null) {
        return false;
      }

      final invoice = job.invoiceId != null ? _invoices[job.invoiceId] : null;
      final isMarkedAsTest = _jobMatchesTestFilter(job);
      final isInvoicedEffective = _isJobInvoicedEffective(job);
      final isPaidEffective = _isJobPaidEffective(job, invoice: invoice);

      final isDelivered = _isJobCurrentlyDelivered(job);

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
          if (job.isSaleWorkflow) {
            if (!isMechanicJobSaleActive(job, invoice)) return false;
            break;
          }
          if (job.isStandaloneQuotation &&
              (job.effectiveQuotationStatus == QuotationStatus.rejected ||
                  job.effectiveQuotationStatus == QuotationStatus.expired)) {
            return false;
          }
          // Activos: include Terminados/Finalizados.
          // Filter out only: Cancelados, and Entregados that are already paid.
          if (job.status == JobStatus.cancelado) return false;

          if (isDelivered && isInvoicedEffective && isPaidEffective) {
            return false;
          }

          // Also exclude finished warranties from active list
          if (isFinishedWarranty) return false;
          break;
        case 'warranty_completed':
          if (!isFinishedWarranty) return false;
          break;
        case 'quotations_closed':
          if (!job.isStandaloneQuotation ||
              (job.effectiveQuotationStatus != QuotationStatus.rejected &&
                  job.effectiveQuotationStatus != QuotationStatus.expired)) {
            return false;
          }
          break;
        case 'completed':
          // Completed = only complete phase with finalizado status
          if (jobPhase != StatusPhase.complete ||
              isDelivered ||
              job.status == JobStatus.cancelado) {
            return false;
          }
          break;
        case 'delivered':
          if (!isDelivered) return false;
          break;
        case 'service_warranty_active':
          if (job.serviceWarranty?.state != ServiceWarrantyState.active) {
            return false;
          }
          break;
        case 'unpaid':
          if (isPaidEffective || !isInvoicedEffective) return false;
          break;
        case 'deleted':
          break;
      }

      // Search filter
      if (_searchTerm.isNotEmpty) {
        final searchLower = _searchTerm.toLowerCase();
        final customer = _customers[job.customerId];
        final bike = _bikes[job.bikeId];
        final itemText =
            _jobItemsMap[job.id]?.map((item) => item.productName).join(' ') ??
                '';

        final matches =
            (job.jobNumber ?? '').toLowerCase().contains(searchLower) ||
                (customer?.name ?? '').toLowerCase().contains(searchLower) ||
                (customer?.phone ?? '').toLowerCase().contains(searchLower) ||
                (bike?.displayName ?? '').toLowerCase().contains(searchLower) ||
                (job.clientRequest ?? '').toLowerCase().contains(searchLower) ||
                (job.subjectNotes ?? '').toLowerCase().contains(searchLower) ||
                itemText.toLowerCase().contains(searchLower);

        if (!matches) return false;
      }

      // Custom status filter - now uses status IDs
      // Supports both "is" (include) and "is not" (exclude) modes
      if (hasCustomStatusFilter) {
        final jobStatusId = job.statusId;
        final legacyStatusCode = job.status.name.toUpperCase();
        final isInFilter = (jobStatusId != null &&
                _customStatusFilter.contains(jobStatusId)) ||
            _customStatusFilter.contains(legacyStatusCode);

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
    debugPrint(
      '[AI_CTX][PegasTable.publish] contextId=${identityHashCode(_aiAssistantContextService)} '
      'filtered=${filtered.length} '
      'allJobs=${_jobs.length} statusFilter=$_statusFilter '
      'scope="${_aiAssistantJobsScopeLabel()}" search="$_searchTerm" '
      'customFilter=${_customStatusFilter.length} '
      'priorityFilter=${_priorityFilter.length} '
      'overdue=$_showOnlyOverdue unpaid=$_showOnlyUnpaid '
      'jobs=[${_debugAiJobNumbers(filtered)}]',
    );
    _aiAssistantContextService.setVisibleJobsContext(
      jobs: filtered,
      scopeLabel: _aiAssistantJobsScopeLabel(),
    );
  }

  bool _jobMatchesTestFilter(MechanicJob job) {
    final customer = _customers[job.customerId];
    final bike = _bikes[job.bikeId];

    return mechanicJobMatchesTestFixture(
      job,
      customerName: customer?.name,
      bikeName: bike?.displayName,
      bikeBrand: bike?.brand,
      bikeModel: bike?.model,
      bikeSerialNumber: bike?.serialNumber,
    );
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
    final screenWidth = ResponsiveViewport.widthOf(context);

    return MainLayout(
      title: 'Vinabike ERP',
      compactHeader: screenWidth < ResponsiveViewport.desktopMin
          ? _buildMobileMainLayoutHeader()
          : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useCompactWorkspace =
              screenWidth < ResponsiveViewport.desktopMin;
          if (useCompactWorkspace || _mobileWorkshopWorkspace != null) {
            return _buildMobileLayout();
          }
          if (_isLoading) {
            return const Center(child: BrandedLoading());
          }
          if (_selectedJob != null && _isSplitPaneEnabled) {
            return _buildSplitView();
          }
          return Column(
            children: [
              _buildModernHeader(),
              _buildToolbar(),
              Expanded(child: _buildViewContent()),
            ],
          );
        },
      ),
    );
  }

  // ============================================================
  // MOBILE LAYOUT IMPLEMENTATION
  // ============================================================
  Widget _buildMobileLayout() {
    final theme = Theme.of(context);
    final workspace = _mobileWorkshopWorkspace;

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      body: SafeArea(
        key: const ValueKey('workshop-mobile-bottom-safe-area'),
        left: false,
        top: false,
        right: false,
        maintainBottomViewPadding: true,
        child: workspace != null
            ? KeyedSubtree(
                key: const ValueKey('workshop-mobile-inline-host'),
                child: _buildMobileInlineWorkspace(workspace),
              )
            : Column(
                children: [
                  if (_viewMode != 'tasks') _buildMobileFilterTabs(theme),
                  Expanded(
                    child: _isLoading
                        ? const Center(child: BrandedLoading())
                        : _viewMode == 'table'
                            ? RefreshIndicator(
                                onRefresh: _loadData,
                                child: _buildMobileJobsList(),
                              )
                            : _buildViewContent(),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildMobileInlineWorkspace(_MobileWorkshopWorkspace workspace) {
    final job = _currentMobileWorkspaceJob(workspace);
    final jobId = job.id;
    if (jobId == null || jobId.isEmpty) {
      return _buildMobileInlineUnavailable();
    }

    return switch (workspace.surface) {
      _MobileWorkshopSurface.job => KeyedSubtree(
          key: const ValueKey('workshop-mobile-inline-job'),
          child: MechanicJobFormPage(
            key: workspace.childKey,
            jobId: jobId,
            initialTab: 'general',
            isEmbedded: true,
            isInlineWorkspace: true,
            onSaved: _handleMobileInlineSave,
            onCanceled: _closeMobileInlineSurface,
          ),
        ),
      _MobileWorkshopSurface.items => KeyedSubtree(
          key: const ValueKey('workshop-mobile-inline-items'),
          child: MechanicJobFormPage(
            key: workspace.childKey,
            jobId: jobId,
            initialTab: 'products',
            isEmbedded: true,
            isInlineWorkspace: true,
            onSaved: _handleMobileInlineSave,
            onCanceled: _closeMobileInlineSurface,
          ),
        ),
      _MobileWorkshopSurface.bike => _buildMobileBikeWorkspace(workspace, job),
      _MobileWorkshopSurface.invoice => KeyedSubtree(
          key: const ValueKey('workshop-mobile-inline-invoice'),
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: SalesInvoiceEditor(
              key: workspace.childKey,
              invoiceId: job.invoiceId,
              preselectedJobId: jobId,
              preselectedCustomerId: job.customerId,
              isCompact: true,
              allowFullScreenExpansion: false,
              onCloseRequested: _closeMobileInlineSurface,
              onRegisterPaymentRequested: _handleMobileInlinePaymentRequested,
              onSaved: _handleMobileInlineSave,
            ),
          ),
        ),
      _MobileWorkshopSurface.payment =>
        _buildMobilePaymentWorkspace(workspace, job),
      _MobileWorkshopSurface.proposalPdf =>
        _buildMobileProposalPdfWorkspace(workspace, job),
    };
  }

  Widget _buildMobileBikeWorkspace(
    _MobileWorkshopWorkspace workspace,
    MechanicJob job,
  ) {
    final bike = _currentMobileWorkspaceBike(workspace);
    final customerId = job.customerId.trim();
    if (bike == null || customerId.isEmpty) {
      return _buildMobileInlineUnavailable(
        message: 'No fue posible abrir esta bicicleta.',
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _closeMobileInlineSurface();
      },
      child: ColoredBox(
        key: const ValueKey('workshop-mobile-inline-bike'),
        color: Theme.of(context).colorScheme.surface,
        child: BikeFormDialog(
          key: ValueKey('workshop-mobile-bike-editor-${bike.id}'),
          customerId: customerId,
          bike: bike,
          isEmbedded: true,
          onSaved: _handleMobileBikeSave,
          onCanceled: _closeMobileInlineSurface,
        ),
      ),
    );
  }

  Widget _buildMobilePaymentWorkspace(
    _MobileWorkshopWorkspace workspace,
    MechanicJob job,
  ) {
    final invoiceId = job.invoiceId?.trim();
    final invoice = workspace.invoice ??
        (invoiceId == null || invoiceId.isEmpty ? null : _invoices[invoiceId]);
    if (invoice == null) {
      return _buildMobileInlineUnavailable(
        message: 'No fue posible abrir el registro de abono.',
      );
    }

    return KeyedSubtree(
      key: const ValueKey('workshop-mobile-inline-payment'),
      child: WorkshopMobilePaymentWorkspace(
        invoice: invoice,
        onBack: _returnMobilePaymentToInvoice,
        paymentForm: PaymentForm(
          invoice: invoice,
          dismissOnSubmit: false,
          onCompleted: _handleMobilePaymentCompleted,
        ),
      ),
    );
  }

  Widget _buildMobileInlineUnavailable({
    String message = 'Este trabajo ya no está disponible.',
  }) {
    final theme = Theme.of(context);
    return Center(
      key: const ValueKey('workshop-mobile-inline-error'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sync_problem_outlined,
              color: theme.colorScheme.error,
              size: 38,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _closeMobileInlineSurface,
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Volver a trabajos'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileProposalPdfWorkspace(
    _MobileWorkshopWorkspace workspace,
    MechanicJob job,
  ) {
    final theme = Theme.of(context);
    final pdfFuture = workspace.proposalPdf;
    final jobLabel = job.jobNumber?.trim().isNotEmpty == true
        ? job.jobNumber!.trim()
        : 'Trabajo';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _closeMobileInlineSurface();
      },
      child: ColoredBox(
        key: const ValueKey('workshop-mobile-inline-pdf'),
        color: theme.colorScheme.surface,
        child: Column(
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 58),
              padding: const EdgeInsets.fromLTRB(4, 5, 8, 5),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color:
                        theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey('workshop-mobile-inline-back'),
                    tooltip: 'Volver a trabajos',
                    onPressed: _closeMobileInlineSurface,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          job.proposalDocumentLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          jobLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (pdfFuture != null)
                    FutureBuilder<_WorkshopProposalPdfArtifact>(
                      future: pdfFuture,
                      builder: (context, snapshot) => IconButton(
                        tooltip: 'Compartir o guardar PDF',
                        onPressed: snapshot.hasData
                            ? () => unawaited(
                                  _exportQuotationPdfArtifact(snapshot.data!),
                                )
                            : null,
                        icon: const Icon(Icons.ios_share_rounded),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: pdfFuture == null
                  ? _buildMobileProposalPdfError(job)
                  : FutureBuilder<_WorkshopProposalPdfArtifact>(
                      future: pdfFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                            key: ValueKey('workshop-mobile-inline-loading'),
                            child: BrandedLoading(),
                          );
                        }
                        if (snapshot.hasError || snapshot.data == null) {
                          return _buildMobileProposalPdfError(
                            job,
                            error: snapshot.error,
                          );
                        }
                        final artifact = snapshot.data!;
                        return PdfPreview(
                          build: (_) async => artifact.bytes,
                          pdfFileName: artifact.fileName,
                          useActions: false,
                          allowPrinting: false,
                          allowSharing: false,
                          canChangeOrientation: false,
                          canChangePageFormat: false,
                          canDebug: false,
                          scrollViewDecoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerLow,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileProposalPdfError(
    MechanicJob job, {
    Object? error,
  }) {
    final theme = Theme.of(context);
    return Center(
      key: const ValueKey('workshop-mobile-inline-error'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.picture_as_pdf_outlined,
              size: 40,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              'No se pudo preparar ${job.proposalDocumentLabelLower}.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (error != null) ...[
              const SizedBox(height: 6),
              Text(
                '$error',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => _retryMobileProposalPdf(job),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  void _retryMobileProposalPdf(MechanicJob job) {
    if (!mounted) return;
    setState(() {
      _mobileWorkshopWorkspace = _MobileWorkshopWorkspace(
        surface: _MobileWorkshopSurface.proposalPdf,
        job: job,
        proposalPdf: _buildQuotationPdfArtifact(job),
      );
    });
  }

  MainLayoutCompactHeader _buildMobileMainLayoutHeader() {
    final overdueCount = _filteredJobs.where((job) => job.isOverdue).length;

    if (_viewMode == 'tasks') {
      return MainLayoutCompactHeader(
        title: 'Tareas',
        contextLine: 'Planificación operativa',
        actions: [
          IconButton(
            key: const ValueKey('workshop-mobile-tasks-view'),
            onPressed: _showMobileViewPicker,
            icon: const Icon(Icons.view_compact_alt_outlined),
            tooltip: 'Cambiar vista del taller',
          ),
        ],
      );
    }

    if (_isSearchExpanded) {
      return MainLayoutCompactHeader(
        title: 'Trabajos',
        search: MainLayoutCompactSearch(
          fieldKey: const ValueKey('workshop-mobile-search-field'),
          controller: _mobileSearchController,
          autofocus: true,
          textInputAction: TextInputAction.search,
          hintText: 'Buscar trabajos…',
          onClear: _searchTerm.isEmpty ? null : _clearMobileSearch,
          onChanged: _updateMobileSearch,
        ),
        actions: [
          IconButton(
            key: const ValueKey('workshop-mobile-search-close'),
            onPressed: () => setState(() => _isSearchExpanded = false),
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Cerrar búsqueda',
          ),
        ],
      );
    }

    if (_mobileSearchController.text != _searchTerm) {
      _mobileSearchController.value = TextEditingValue(
        text: _searchTerm,
        selection: TextSelection.collapsed(offset: _searchTerm.length),
      );
    }

    final contextParts = <String>[
      _statusFilterLabel(_statusFilter),
      '${_filteredJobs.length}',
      if (_searchTerm.isNotEmpty) 'búsqueda',
      if (overdueCount > 0)
        '$overdueCount ${overdueCount == 1 ? 'vencido' : 'vencidos'}',
    ];
    return MainLayoutCompactHeader(
      title: 'Trabajos',
      contextLine: contextParts.join(' · '),
      actions: [
        TextButton.icon(
          key: const ValueKey('workshop-mobile-new-job'),
          onPressed: () =>
              context.push('/taller/pegas/nueva').then((_) => _loadData()),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Nuevo'),
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          key: const ValueKey('workshop-mobile-search'),
          icon: const Icon(Icons.search_rounded),
          onPressed: () => setState(() => _isSearchExpanded = true),
          tooltip: 'Buscar trabajos',
        ),
        PopupMenuButton<String>(
          key: const ValueKey('workshop-mobile-overflow'),
          icon: const Icon(Icons.more_vert),
          tooltip: 'Más acciones',
          onSelected: (value) {
            switch (value) {
              case 'manual':
                _openJobsTableManual();
                break;
              case 'refresh':
                _loadData();
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'manual',
              child: Text('Manual de uso'),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'refresh',
              child: Text('Actualizar'),
            ),
          ],
        ),
      ],
    );
  }

  void _updateMobileSearch(String value) {
    _searchTerm = value;
    _applyFiltersAndSort();
  }

  void _clearMobileSearch() {
    _mobileSearchController.clear();
    _updateMobileSearch('');
  }

  Widget _buildMobileFilterTabs(ThemeData theme) {
    return Container(
      key: const ValueKey('workshop-mobile-command-strip'),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
      color: theme.colorScheme.surfaceContainerLow,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(
                theme.colorScheme.primary.withValues(alpha: 0.06),
                theme.colorScheme.surface,
              ),
              theme.colorScheme.surface,
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: theme.brightness == Brightness.dark ? 0.14 : 0.045,
              ),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              flex: 9,
              child: _buildMobileControlField(
                key: const ValueKey('workshop-mobile-scope'),
                eyebrow: 'Ámbito',
                value: _statusFilterLabel(_statusFilter),
                onTap: _showMobileScopePicker,
              ),
            ),
            _buildMobileCommandDivider(theme),
            Expanded(
              flex: 12,
              child: _buildMobileControlField(
                key: const ValueKey('workshop-mobile-view'),
                eyebrow: 'Vista',
                value: _mobileViewModeLabel(_viewMode),
                onTap: _showMobileViewPicker,
              ),
            ),
            _buildMobileCommandDivider(theme),
            Expanded(
              flex: 9,
              child: _buildMobileWorkloadSummary(theme),
            ),
            _buildMobileCommandDivider(theme),
            Expanded(
              flex: 10,
              child: _buildMobileFiltersButton(theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileCommandDivider(ThemeData theme) => Container(
        width: 1,
        height: 28,
        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.42),
      );

  Widget _buildMobileControlField({
    required Key key,
    required String eyebrow,
    required String value,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '$eyebrow: $value',
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _mobileViewModeLabel(String value) =>
      value == 'table' ? 'Lista' : _viewModeLabel(value);

  int get _mobileAppliedFilterCount =>
      _customStatusFilter.length +
      _priorityFilter.length +
      (_showOnlyOverdue ? 1 : 0) +
      (_showOnlyUnpaid ? 1 : 0);

  Widget _buildMobileFiltersButton(ThemeData theme) {
    final count = _mobileAppliedFilterCount;
    return Semantics(
      button: true,
      label: count == 0 ? 'Abrir filtros' : 'Abrir filtros, $count aplicados',
      child: InkWell(
        key: const ValueKey('workshop-mobile-filters'),
        onTap: _showMobileFilters,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: count == 0
                ? Colors.transparent
                : theme.colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: Text(
            count == 0 ? 'Filtros' : 'Filtros · $count',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: count == 0
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileWorkloadSummary(ThemeData theme) {
    final bicycleCount = _buildBicycleStatusBreakdown()
        .fold<int>(0, (sum, status) => sum + status.count);
    final details = <String>[
      '${_filteredJobs.length} en alcance',
      if (bicycleCount > 0) '$bicycleCount bicis',
      if (_filteredJobs.where((job) => job.isServiceBudget).isNotEmpty)
        '${_filteredJobs.where((job) => job.isServiceBudget).length} pres.',
      if (_filteredJobs.where((job) => job.isStandaloneQuotation).isNotEmpty)
        '${_filteredJobs.where((job) => job.isStandaloneQuotation).length} cotiz.',
    ];
    final summary = details.join(' · ');
    final compactLabel = bicycleCount > 0
        ? '$bicycleCount bicis'
        : '${_filteredJobs.length} trab.';

    return Semantics(
      button: true,
      label: 'Resumen de carga: $summary',
      child: InkWell(
        key: const ValueKey('workshop-mobile-workload-summary'),
        onTap: _showMobileWorkloadSummary,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(9)),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  compactLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMobileScopePicker() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.78,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Qué trabajos mostrar',
                  style: Theme.of(sheetContext)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              for (final option in _statusFilterOptions())
                ListTile(
                  key: ValueKey('workshop-mobile-scope-$option'),
                  title: Text(_statusFilterLabel(option)),
                  trailing: option == _statusFilter
                      ? const Icon(Icons.check_rounded, size: 20)
                      : null,
                  onTap: () => Navigator.pop(sheetContext, option),
                ),
            ],
          ),
        );
      },
    );
    if (!mounted || selected == null || selected == _statusFilter) return;
    await _selectJobsScope(selected);
  }

  Future<void> _showMobileViewPicker() async {
    const options = ['table', 'board', 'calendar', 'gantt', 'tasks'];
    const descriptions = <String, String>{
      'table': 'Lectura rápida y acciones por trabajo',
      'board': 'Columnas por estado operativo',
      'calendar': 'Ingresos y plazos por fecha',
      'gantt': 'Planificación temporal del taller',
      'tasks': 'Tareas operativas pendientes',
    };
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Cambiar vista',
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            for (final option in options)
              ListTile(
                key: ValueKey('workshop-mobile-view-$option'),
                title: Text(_mobileViewModeLabel(option)),
                subtitle: Text(descriptions[option]!),
                trailing: option == _viewMode
                    ? const Icon(Icons.check_rounded, size: 20)
                    : null,
                onTap: () => Navigator.pop(sheetContext, option),
              ),
          ],
        );
      },
    );
    if (!mounted || selected == null || selected == _viewMode) return;
    _selectJobsView(selected);
  }

  Future<void> _showMobileFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            void apply(VoidCallback mutation) {
              mutation();
              setSheetState(() {});
              _applyFiltersAndSort();
            }

            final customStatuses = _jobStatusService.activeStatuses;
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.88,
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Filtros',
                            style: Theme.of(sheetContext)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (_mobileAppliedFilterCount > 0)
                          TextButton(
                            onPressed: () => apply(() {
                              _customStatusFilter.clear();
                              _priorityFilter.clear();
                              _statusFilterExcludeMode = false;
                              _showOnlyOverdue = false;
                              _showOnlyUnpaid = false;
                            }),
                            child: const Text('Limpiar'),
                          ),
                        TextButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text('Listo'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 20),
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
                          child: Text(
                            'ATENCIÓN',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        SwitchListTile(
                          key: const ValueKey(
                            'workshop-mobile-filter-overdue',
                          ),
                          title: const Text('Solo trabajos vencidos'),
                          value: _showOnlyOverdue,
                          onChanged: (value) =>
                              apply(() => _showOnlyOverdue = value),
                        ),
                        SwitchListTile(
                          key: const ValueKey(
                            'workshop-mobile-filter-unpaid',
                          ),
                          title: const Text('Solo trabajos sin pagar'),
                          value: _showOnlyUnpaid,
                          onChanged: (value) =>
                              apply(() => _showOnlyUnpaid = value),
                        ),
                        const Divider(height: 24),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
                          child: Text(
                            'PRIORIDAD',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        for (final priority in JobPriority.values)
                          CheckboxListTile(
                            key: ValueKey(
                              'workshop-mobile-filter-priority-${priority.name}',
                            ),
                            title: Text(priority.displayName),
                            value: _priorityFilter.contains(priority),
                            onChanged: (_) => apply(() {
                              if (!_priorityFilter.add(priority)) {
                                _priorityFilter.remove(priority);
                              }
                            }),
                          ),
                        const Divider(height: 24),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                          child: WorkshopStatusFilterHeader(
                            excludeMode: _statusFilterExcludeMode,
                            canClear: _customStatusFilter.isNotEmpty,
                            onExcludeModeChanged: (value) => apply(
                              () => _statusFilterExcludeMode = value,
                            ),
                            onClear: () => apply(() {
                              _customStatusFilter.clear();
                              _statusFilterExcludeMode = false;
                            }),
                          ),
                        ),
                        if (customStatuses.isEmpty)
                          for (final status in JobStatus.values)
                            CheckboxListTile(
                              key: ValueKey(
                                'workshop-mobile-filter-status-${status.name}',
                              ),
                              secondary: Container(
                                width: 4,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: _getLegacyStatusColor(status),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              title: Text(_getStatusLabel(status)),
                              value: _customStatusFilter
                                  .contains(status.name.toUpperCase()),
                              onChanged: (_) => apply(() {
                                _toggleCustomStatusFilter(
                                  status.name.toUpperCase(),
                                );
                              }),
                            )
                        else
                          for (final phase in StatusPhase.values) ...[
                            if ((_jobStatusService.statusesByPhase[phase] ??
                                    const <JobStatusCustom>[])
                                .isNotEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 12, 20, 2),
                                child: Text(
                                  phase.displayName,
                                  style: Theme.of(sheetContext)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                        color: Theme.of(sheetContext)
                                            .colorScheme
                                            .onSurfaceVariant,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            for (final status
                                in _jobStatusService.statusesByPhase[phase] ??
                                    const <JobStatusCustom>[])
                              if (status.id != null)
                                CheckboxListTile(
                                  key: ValueKey(
                                    'workshop-mobile-filter-status-${status.id}',
                                  ),
                                  secondary: Container(
                                    width: 4,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: status.colorValue,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  title: Text(status.name),
                                  value:
                                      _customStatusFilter.contains(status.id),
                                  onChanged: (_) => apply(() {
                                    _toggleCustomStatusFilter(status.id!);
                                  }),
                                ),
                          ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showMobileWorkloadSummary() {
    final bicycleBreakdown = _buildBicycleStatusBreakdown();
    final bicycles =
        bicycleBreakdown.fold<int>(0, (sum, status) => sum + status.count);
    final components = _filteredJobs
        .where((job) =>
            job.workflowKind != JobWorkflowKind.quotation &&
            job.intakeKind == JobIntakeKind.component)
        .length;
    final warranties = _filteredJobs.where((job) {
      if (!job.isWarrantyJob) return false;
      final phase =
          job.customStatus?.phase ?? _inferPhaseFromLegacyStatus(job.status);
      return phase != StatusPhase.complete;
    }).length;
    final budgets = _filteredJobs.where((job) => job.isServiceBudget).length;
    final quotations =
        _filteredJobs.where((job) => job.isStandaloneQuotation).length;
    final sales = _filteredJobs.where((job) => job.isSaleWorkflow).length;
    final finances = _financialSummaryForJobs(_filteredJobs);
    final money = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        Widget countRow(String label, Object value) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Expanded(child: Text(label)),
                Text(
                  '$value',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          );
        }

        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '${_statusFilterLabel(_statusFilter)} · carga visible',
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            countRow('Trabajos', _filteredJobs.length),
            countRow('Bicicletas vinculadas', bicycles),
            if (components > 0) countRow('Componentes', components),
            if (warranties > 0) countRow('Garantías en curso', warranties),
            if (budgets > 0) countRow('Presupuestos', budgets),
            if (quotations > 0) countRow('Cotizaciones', quotations),
            if (sales > 0) countRow('Ventas / cobros', sales),
            if (bicycleBreakdown.isNotEmpty) ...[
              const Divider(height: 24),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  'BICICLETAS POR ESTADO',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              for (final status in bicycleBreakdown)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 20,
                        decoration: BoxDecoration(
                          color: status.color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(status.label)),
                      Text(
                        '${status.count}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
            ],
            if (finances.total > 0 ||
                finances.budgets > 0 ||
                finances.quotations > 0) ...[
              const Divider(height: 24),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  'FINANZAS DEL ALCANCE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (finances.total > 0)
                countRow('Total facturable', money.format(finances.total)),
              if (finances.paid > 0)
                countRow('Pagado', money.format(finances.paid)),
              if (finances.outstanding > 0)
                countRow('Por cobrar', money.format(finances.outstanding)),
              if (finances.budgets > 0)
                countRow('Presupuestado', money.format(finances.budgets)),
              if (finances.quotations > 0)
                countRow('Cotizado', money.format(finances.quotations)),
            ],
          ],
        );
      },
    );
  }

  Widget _buildMobileJobsList() {
    final jobs = _filteredJobs;
    if (jobs.isEmpty) {
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final usesTabletGrid =
            constraints.maxWidth >= _mobileJobsTabletGridMinWidth;
        return ListView.builder(
          key: const PageStorageKey('workshop-jobs-mobile'),
          controller: _mobileJobsScrollController,
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 24),
          itemCount: usesTabletGrid ? (jobs.length / 2).ceil() : jobs.length,
          itemBuilder: (context, index) {
            if (!usesTabletGrid) {
              return _buildMobileJobCard(jobs[index]);
            }

            final firstIndex = index * 2;
            final secondIndex = firstIndex + 1;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildMobileJobCard(jobs[firstIndex])),
                if (secondIndex < jobs.length)
                  Expanded(child: _buildMobileJobCard(jobs[secondIndex]))
                else
                  const Expanded(child: SizedBox.shrink()),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _updateJobStatus(JobStatus newStatus) async {
    final job = _selectedJob;
    if (job?.id == null) return;
    _startLocalOperation();
    try {
      await _bikeshopService.transitionJobStatusByLegacyStatus(
        job!.id!,
        newStatus,
        operationKey: const Uuid().v4(),
      );
      await _loadData();
      if (mounted) {
        final refreshed = _jobs.where((item) => item.id == job.id).firstOrNull;
        if (refreshed != null) {
          await _loadJobDetails(refreshed);
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Estado actualizado a ${newStatus.displayName}')),
        );
      }
    } catch (e) {
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo confirmar el estado: $e')),
        );
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
            onProposalDocumentPressed: () {
              final job = _selectedJob;
              if (job != null) unawaited(_downloadQuotationPdf(job));
            },
            onProposalStatusPressed: () {
              final job = _selectedJob;
              if (job != null) _showStatusMenu(job);
            },
            onProposalConvertPressed: () {
              final job = _selectedJob;
              if (job != null) unawaited(_convertToService(job));
            },
            onStatusPressed: _selectedJob!.isSaleWorkflow
                ? null
                : () => _showStatusMenu(_selectedJob!),
            onProductsAndServicesPressed: () =>
                unawaited(_openJobProductsAndServices(_selectedJob!)),
            onInvoicePressed: _selectedJob!.invoiceId?.isNotEmpty == true
                ? () => unawaited(_openInvoice(_selectedJob!.invoiceId!))
                : null,
            onPaymentPressed: _canRegisterPaymentForJob(_selectedJob!)
                ? () => unawaited(
                      _registerInvoicePayment(_selectedJob!.invoiceId!),
                    )
                : null,
            onBikePressed: _selectedJob!.bikeId != null &&
                    _customers[_selectedJob!.customerId] != null
                ? () => _showBikeProfileDialog(
                      _selectedJob!,
                      _customers[_selectedJob!.customerId],
                    )
                : null,
            onCustomerPressed:
                _customers[_selectedJob!.customerId]?.id?.isNotEmpty == true
                    ? () => context.push(
                          '/clientes/${_customers[_selectedJob!.customerId]!.id}',
                        )
                    : null,
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
            onStatusChange: _updateJobStatus,
            onItemRemoved: (itemId) async {
              // Same logic...
              final messenger = ScaffoldMessenger.maybeOf(context);
              try {
                await _bikeshopService.deleteJobItem(itemId);
                if (_selectedJob != null) {
                  await _loadJobDetails(_selectedJob!);
                }
                if (mounted) {
                  messenger?.showSnackBar(
                    const SnackBar(content: Text('Product removed')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  messenger?.showSnackBar(
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
                onProposalDocumentPressed: () {
                  final job = _selectedJob;
                  if (job != null) unawaited(_downloadQuotationPdf(job));
                },
                onProposalStatusPressed: () {
                  final job = _selectedJob;
                  if (job != null) _showStatusMenu(job);
                },
                onProposalConvertPressed: () {
                  final job = _selectedJob;
                  if (job != null) unawaited(_convertToService(job));
                },
                onStatusPressed: _selectedJob!.isSaleWorkflow
                    ? null
                    : () => _showStatusMenu(_selectedJob!),
                onProductsAndServicesPressed: () =>
                    unawaited(_openJobProductsAndServices(_selectedJob!)),
                onInvoicePressed: _selectedJob!.invoiceId?.isNotEmpty == true
                    ? () => unawaited(_openInvoice(_selectedJob!.invoiceId!))
                    : null,
                onPaymentPressed: _canRegisterPaymentForJob(_selectedJob!)
                    ? () => unawaited(
                          _registerInvoicePayment(_selectedJob!.invoiceId!),
                        )
                    : null,
                onBikePressed: _selectedJob!.bikeId != null &&
                        _customers[_selectedJob!.customerId] != null
                    ? () => _showBikeProfileDialog(
                          _selectedJob!,
                          _customers[_selectedJob!.customerId],
                        )
                    : null,
                onCustomerPressed:
                    _customers[_selectedJob!.customerId]?.id?.isNotEmpty == true
                        ? () => context.push(
                              '/clientes/${_customers[_selectedJob!.customerId]!.id}',
                            )
                        : null,
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
                onStatusChange: _updateJobStatus,
                onItemRemoved: (itemId) async {
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  try {
                    await _bikeshopService.deleteJobItem(itemId);
                    if (_selectedJob != null) {
                      await _loadJobDetails(_selectedJob!);
                    }
                    if (mounted) {
                      messenger?.showSnackBar(
                        const SnackBar(content: Text('Product removed')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      messenger?.showSnackBar(
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

  Future<void> _openJobsTableManual() {
    return showAssetPdfPreviewDialog(
      context,
      assetPath: 'assets/manuals/manual_jobs_table.pdf',
      title: 'Manual de Jobs Table',
      description:
          'Creación, estados, presupuestos, cobros y control de tiempos.',
      fileName: 'manual_jobs_table.pdf',
    );
  }

  Widget _buildModernHeader() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final theme = Theme.of(context);
    final topBarColor = theme.brightness == Brightness.dark
        ? theme.colorScheme.surfaceContainerHighest
        : const Color(0xFFF3F4F6);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: topBarColor,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
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
                icon: Icon(_isSplitPaneEnabled
                    ? Icons.vertical_split
                    : Icons.vertical_split_outlined),
                onPressed: _toggleSplitPane,
                tooltip: _isSplitPaneEnabled
                    ? 'Panel de detalles activado'
                    : 'Panel de detalles desactivado',
                isSelected: _isSplitPaneEnabled,
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
              icon: const Icon(Icons.help_outline_rounded),
              onPressed: _openJobsTableManual,
              tooltip: 'Manual de Jobs Table',
            ),
            const SizedBox(width: 8),
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
        // A split button is ONE control drawn as two halves, so the two halves
        // have to agree on height and touch each other.
        //
        // They did neither. Material gives every button an invisible padded
        // tap target that is larger than its paint box, which is what pushed
        // the halves apart; and only the right half pinned a height, so the
        // left one followed the theme's density instead. Hence the notch.
        //
        // `shrinkWrap` makes each layout box equal its paint box, and
        // IntrinsicHeight + stretch makes both halves adopt the taller one —
        // so the seam stays closed if the label ever grows.
        const splitHeight = 40.0;
        // The fill was a frozen navy (#12324A), so in dark mode the primary
        // action of the screen sat as a dark slab on a dark canvas and never
        // followed the palette. A primary CTA is an action accent: 100% of the
        // preset, per the tint budget. The scheme pair also guarantees the
        // label's contrast in both brightnesses, which `Colors.white` did not.
        final splitScheme = Theme.of(context).colorScheme;
        return IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: () {
                  _markNeedsRefresh();
                  context.push('/taller/pegas/nueva');
                },
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Nuevo Trabajo'),
                style: FilledButton.styleFrom(
                  backgroundColor: splitScheme.primary,
                  foregroundColor: splitScheme.onPrimary,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.standard,
                  minimumSize: const Size(0, splitHeight),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(8),
                      bottomLeft: Radius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 1),
              FilledButton(
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
                style: FilledButton.styleFrom(
                  backgroundColor: splitScheme.primary,
                  foregroundColor: splitScheme.onPrimary,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.standard,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(32, splitHeight),
                ),
                child: const Icon(Icons.arrow_drop_down, size: 20),
              ),
            ],
          ),
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
          child: const Text('Cotización'),
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
        MenuItemButton(
          leadingIcon: const Icon(Icons.shopping_bag_outlined, size: 18),
          child: const Text('Venta / cobro'),
          onPressed: () {
            _markNeedsRefresh();
            context.push('/taller/pegas/nueva?type=sale');
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

    return OutlinedButton.icon(
      onPressed: _isCreatingDebugJob ? null : _launchDebugQuickJobBuilder,
      icon: icon,
      label: const Text('Prueba rápida'),
      style: OutlinedButton.styleFrom(
        foregroundColor: _workshopCommandColor,
        side: BorderSide(
          color: _workshopCommandColor.withValues(alpha: 0.35),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
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

    BikeAggregate? existingAggregate;
    if (existingBike?.id != null) {
      existingAggregate =
          await _bikeshopService.getBikeAggregate(existingBike!.id!);
      existingBike = existingAggregate.bike;
    }

    final serialNumber = scenario.reuseBike
        ? scenario.fixtureSerial
        : '${scenario.fixtureSerial}-${DateTime.now().millisecondsSinceEpoch}';
    final desiredBike = Bike(
      id: existingBike?.id ?? const Uuid().v4(),
      tenantId: tenantId,
      customerId: customerId,
      brandId: existingBike?.brandId,
      modelId: existingBike?.modelId,
      brand: scenario.brand,
      model: scenario.model,
      year: scenario.year,
      serialNumber: serialNumber,
      color: scenario.color,
      frameSize: scenario.frameSize,
      wheelSize: scenario.wheelSize,
      bikeType: scenario.bikeType,
      frontHubSpacingMm: existingBike?.frontHubSpacingMm,
      rearHubSpacingMm: existingBike?.rearHubSpacingMm,
      spokeCount: existingBike?.spokeCount,
      factoryRimId: existingBike?.factoryRimId,
      purchaseDate: existingBike?.purchaseDate,
      purchasePrice: existingBike?.purchasePrice,
      warrantyUntil: existingBike?.warrantyUntil,
      qrCode: existingBike?.qrCode,
      notes: '[test fixture:${scenario.id}] ${scenario.description}',
      imageUrl: existingBike?.imageUrl,
      imageUrls: existingBike?.imageUrls ?? const [],
      isActive: existingBike?.isActive ?? true,
      createdAt: existingBike?.createdAt,
      updatedAt: existingBike?.updatedAt,
    );

    BikeProfile? desiredProfile;
    if (scenario.technicalValues.isNotEmpty) {
      final existingProfile = existingAggregate?.profile;
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
      final technicalProfile = Map<String, dynamic>.from(
        existingProfile?.technicalProfile ?? const {},
      )
        ..['values'] = mergedValues
        ..['sources'] = mergedSources
        ..['confirmed'] = mergedConfirmed;
      final summarySnapshot = Map<String, dynamic>.from(
        existingProfile?.summarySnapshot ?? const {},
      )
        ..['identityLine'] = desiredBike.displayName
        ..['technicalHighlights'] = scenario.technicalHighlights
        ..['warnings'] = const ['Fixture de depuracion'];

      desiredProfile = BikeProfile(
        id: existingProfile?.id,
        tenantId: tenantId,
        bikeId: desiredBike.id!,
        catalogBikeId: existingProfile?.catalogBikeId,
        intakeProfile: existingProfile?.intakeProfile ?? const {},
        technicalProfile: technicalProfile,
        summarySnapshot: summarySnapshot,
        lastConfirmedAt: DateTime.now(),
        createdAt: existingProfile?.createdAt,
        updatedAt: existingProfile?.updatedAt,
      );
    }

    final operationVersion = existingAggregate?.bike.updatedAt
            .toUtc()
            .microsecondsSinceEpoch
            .toString() ??
        'create';
    final operationKey =
        'debug-bike:${scenario.id}:${desiredBike.id}:$operationVersion';
    BikeAggregateSaveResult? result;
    try {
      result = await _bikeshopService.saveBikeAggregate(
        bike: desiredBike,
        profile: desiredProfile,
        operationKey: operationKey,
        expectedBikeUpdatedAt: existingAggregate?.bike.updatedAt,
        expectedProfileUpdatedAt: existingAggregate?.profile?.updatedAt,
      );
    } catch (error) {
      final isServerRejection = error is PostgrestException &&
          error.code != null &&
          error.code!.isNotEmpty;
      if (isServerRejection) rethrow;
      result = await _bikeshopService.getBikeAggregateSaveOperation(
        operationKey,
      );
      if (result == null) rethrow;
    }
    return result.bike;
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

  Widget _buildToolbarDropdown({
    required String prefix,
    required String value,
    required List<String> options,
    required String Function(String value) labelFor,
    required Color Function(String value) colorFor,
    required String Function(String value) glyphFor,
    required ValueChanged<String> onSelected,
    required double minWidth,
    bool compact = false,
  }) {
    final theme = Theme.of(context);
    final selectedLabel = labelFor(value);

    return MenuAnchor(
      menuChildren: [
        for (final option in options)
          Builder(builder: (context) {
            final optionColor = colorFor(option);
            return MenuItemButton(
              leadingIcon: _buildDropdownGlyph(glyphFor(option)),
              trailingIcon: option == value
                  ? Icon(Icons.check, size: 18, color: optionColor)
                  : null,
              onPressed: () => onSelected(option),
              child: Text(labelFor(option)),
            );
          }),
      ],
      builder: (context, controller, child) {
        return ConstrainedBox(
          constraints: BoxConstraints(minWidth: minWidth),
          child: OutlinedButton(
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurface,
              backgroundColor: theme.colorScheme.surface,
              side: BorderSide(color: theme.dividerColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 12,
                vertical: 11,
              ),
              minimumSize: Size(minWidth, 40),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDropdownGlyph(glyphFor(value)),
                SizedBox(width: compact ? 6 : 8),
                Flexible(
                  child: Text(
                    compact ? selectedLabel : '$prefix: $selectedLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 12 : 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _selectJobsScope(String selected) async {
    if (selected == _statusFilter) return;
    final requiresReload = selected == 'deleted' || _statusFilter == 'deleted';
    setState(() {
      _statusFilter = selected;
      _currentPage = 0;
    });
    if (requiresReload) {
      await _loadData();
    } else {
      _applyFiltersAndSort();
    }
  }

  void _selectJobsView(String selected) {
    if (selected == _viewMode) return;
    setState(() => _viewMode = selected);
    _saveTableState();
  }

  Widget _buildStatusFilterDropdown({required bool compact}) {
    return _buildToolbarDropdown(
      prefix: 'Trabajos',
      value: _statusFilter,
      options: _statusFilterOptions(),
      labelFor: _statusFilterLabel,
      colorFor: _statusFilterColor,
      glyphFor: _statusFilterGlyph,
      minWidth: compact ? 0 : 188,
      compact: compact,
      onSelected: (selected) => unawaited(_selectJobsScope(selected)),
    );
  }

  Widget _buildViewModeDropdown({required bool compact}) {
    const options = ['table', 'board', 'calendar', 'gantt', 'tasks'];
    return _buildToolbarDropdown(
      prefix: 'Vista',
      value: _viewMode,
      options: options,
      labelFor: _viewModeLabel,
      colorFor: _viewModeColor,
      glyphFor: _viewModeGlyph,
      minWidth: compact ? 0 : 168,
      compact: compact,
      onSelected: _selectJobsView,
    );
  }

  Widget _buildAppliedFilterToken({
    required String label,
    required Color color,
    required VoidCallback onDeleted,
  }) {
    final theme = Theme.of(context);
    return Container(
      height: 32,
      padding: const EdgeInsets.only(left: 10, right: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            onPressed: onDeleted,
            icon: const Icon(Icons.close, size: 14),
            tooltip: 'Quitar filtro',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 24, height: 24),
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
          LayoutBuilder(builder: (context, constraints) {
            if (constraints.maxWidth < ResponsiveViewport.desktopMin) {
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

                  Row(
                    children: [
                      Expanded(
                        child: _buildStatusFilterDropdown(compact: true),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildViewModeDropdown(compact: true),
                      ),
                    ],
                  ),
                ],
              );
            }

            // Desktop Toolbar
            return Column(
              children: [
                Row(
                  children: [
                    _buildStatusFilterDropdown(compact: false),
                    const SizedBox(width: 12),
                    _buildViewModeDropdown(compact: false),
                    const SizedBox(width: 12),
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
                      _buildAppliedFilterToken(
                        label: 'Vencidos',
                        color: Colors.red.shade700,
                        onDeleted: () {
                          setState(() => _showOnlyOverdue = false);
                          _applyFiltersAndSort();
                        },
                      ),
                    if (_showOnlyUnpaid)
                      _buildAppliedFilterToken(
                        label: 'Sin pagar',
                        color: Colors.orange.shade700,
                        onDeleted: () {
                          setState(() => _showOnlyUnpaid = false);
                          _applyFiltersAndSort();
                        },
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

              // Stats - sum invoice totals, paid, and outstanding
              if (_filteredJobs.isNotEmpty)
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Builder(builder: (context) {
                        final summary = _financialSummaryForJobs(_filteredJobs);
                        final totalSum = summary.total;
                        final paidSum = summary.paid;
                        final outstandingSum = summary.outstanding;
                        final budgetSum = summary.budgets;
                        final quotationSum = summary.quotations;
                        final fmt = NumberFormat.currency(
                            symbol: '\$', decimalDigits: 0);
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
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Text('·',
                                    style: TextStyle(
                                        color: Colors.grey.shade400,
                                        fontSize: 16)),
                              ),
                              Text(
                                'Pagado: ${fmt.format(paidSum)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: _workshopSettledColor,
                                    ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Text('·',
                                    style: TextStyle(
                                        color: Colors.grey.shade400,
                                        fontSize: 16)),
                              ),
                              Text(
                                'Por cobrar: ${fmt.format(outstandingSum)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: outstandingSum > 0
                                          ? Colors.orange.shade700
                                          : _workshopSettledColor,
                                    ),
                              ),
                            ],
                            if (budgetSum > 0) ...[
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Text('·',
                                    style: TextStyle(
                                        color: Colors.grey.shade400,
                                        fontSize: 16)),
                              ),
                              Text(
                                'Presupuestado: ${fmt.format(budgetSum)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.orange.shade700,
                                    ),
                              ),
                            ],
                            if (quotationSum > 0) ...[
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Text('·',
                                    style: TextStyle(
                                        color: Colors.grey.shade400,
                                        fontSize: 16)),
                              ),
                              Text(
                                'Cotizado: ${fmt.format(quotationSum)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.orange.shade700,
                                    ),
                              ),
                            ],
                          ],
                        );
                      }),
                    ),
                  ),
                )
              else
                const Spacer(),
            ],
          ),
        ],
      ),
    );
  }

  ({
    double total,
    double paid,
    double outstanding,
    double budgets,
    double quotations,
  }) _financialSummaryForJobs(Iterable<MechanicJob> jobs) {
    var total = 0.0;
    var paid = 0.0;
    var budgets = 0.0;
    var quotations = 0.0;
    for (final job in jobs) {
      if (job.workflowKind == JobWorkflowKind.quotation) {
        if (job.isServiceBudget) {
          budgets += job.totalCost;
        } else {
          quotations += job.totalCost;
        }
        continue;
      }
      final invoice = job.invoiceId == null ? null : _invoices[job.invoiceId];
      total += invoice?.total ?? job.totalCost;
      paid += invoice?.paidAmount ?? 0;
    }
    return (
      total: total,
      paid: paid,
      outstanding: (total - paid).clamp(0.0, double.infinity).toDouble(),
      budgets: budgets,
      quotations: quotations,
    );
  }

  Widget _buildJobTypeCounters() {
    final sidebarPalette = context.watch<AppearanceService>().sidebarPalette;
    final bicycleStatusBreakdown = _buildBicycleStatusBreakdown();
    final bicycles = bicycleStatusBreakdown.fold<int>(
      0,
      (sum, status) => sum + status.count,
    );

    final items = _filteredJobs
        .where((job) =>
            job.workflowKind != JobWorkflowKind.quotation &&
            job.intakeKind == JobIntakeKind.component)
        .length;
    // Only count warranty-type jobs that are still in progress (not completed/finalizado).
    // Warranty jobs in the complete phase (e.g. "Terminado Cubierto") are done
    // and should not count as "active" warranties in the counter.
    final warranties = _filteredJobs.where((j) {
      if (j.workflowKind != JobWorkflowKind.warranty) return false;
      final phase =
          j.customStatus?.phase ?? _inferPhaseFromLegacyStatus(j.status);
      return phase != StatusPhase.complete;
    }).length;
    final quotations =
        _filteredJobs.where((job) => job.isStandaloneQuotation).length;
    final budgets = _filteredJobs.where((job) => job.isServiceBudget).length;
    final sales = _filteredJobs.where((job) => job.isSaleWorkflow).length;

    Widget simpleCount(
      IconData icon,
      String label,
      int count, {
      Widget? hoverCard,
    }) {
      if (count == 0) return const SizedBox.shrink();
      final content = Padding(
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
      if (hoverCard == null) return content;
      return _HoverCardTooltip(
        offset: const Offset(0, 22),
        showDelay: const Duration(milliseconds: 650),
        tooltip: hoverCard,
        child: content,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        simpleCount(
          Icons.directions_bike,
          'Bicicletas',
          bicycles,
          hoverCard: _buildBicycleStatusBreakdownCard(
            bicycleStatusBreakdown,
            sidebarPalette,
          ),
        ),
        simpleCount(Icons.build, 'Ítems', items),
        simpleCount(Icons.shield, 'Garantías', warranties),
        simpleCount(Icons.request_quote_outlined, 'Presupuestos', budgets),
        simpleCount(Icons.description, 'Cotizaciones', quotations),
        simpleCount(Icons.shopping_bag_outlined, 'Ventas / cobros', sales),
      ],
    );
  }

  Widget _buildBicycleStatusBreakdownCard(
    List<_BicycleStatusBreakdownEntry> statuses,
    SidebarPaletteOption sidebarPalette,
  ) {
    final total = statuses.fold<int>(0, (sum, status) => sum + status.count);
    final background = sidebarPalette.background;
    final border = sidebarPalette.border.withValues(alpha: 0.82);
    final foreground = sidebarPalette.foreground;
    final muted = sidebarPalette.mutedForeground;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 292,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.directions_bike_rounded,
                  size: 15,
                  color: sidebarPalette.accent,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Bicicletas por estado',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: sidebarPalette.accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$total',
                    style: TextStyle(
                      color: sidebarPalette.onAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(
              height: 1,
              thickness: 1,
              color: border.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 10),
            if (statuses.isEmpty)
              Text(
                'Sin bicicletas visibles',
                style: TextStyle(
                  color: muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              ...statuses.map(
                (status) => Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    children: [
                      _buildStatusBadge(
                        label: status.label,
                        accentColor: status.color,
                        maxWidth: 178,
                        compact: true,
                      ),
                      const SizedBox(width: 9),
                      Container(
                        constraints: const BoxConstraints(minWidth: 30),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Color.alphaBlend(
                            sidebarPalette.accent.withValues(alpha: 0.16),
                            sidebarPalette.backgroundAlt,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color:
                                sidebarPalette.accent.withValues(alpha: 0.26),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${status.count}',
                          style: TextStyle(
                            color: foreground,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (statuses.isNotEmpty) const SizedBox(height: 1),
            Text(
              'Según los trabajos filtrados en la tabla',
              style: TextStyle(
                color: muted,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_BicycleStatusBreakdownEntry> _buildBicycleStatusBreakdown() {
    final breakdown = <String, _BicycleStatusBreakdownEntry>{};

    void countStatus(String statusName, Color statusColor) {
      final label =
          statusName.trim().isEmpty ? 'Sin estado' : statusName.trim();
      final key = label.toLowerCase();
      final entry = breakdown.putIfAbsent(
        key,
        () => _BicycleStatusBreakdownEntry(
          label: label,
          color: statusColor,
        ),
      );
      entry.count += 1;
    }

    for (final job in _filteredJobs) {
      if (job.intakeKind != JobIntakeKind.bike) {
        continue;
      }

      final jobBikes = _jobBikesMap[job.id ?? ''] ?? const [];
      for (final jobBike in jobBikes) {
        countStatus(
          jobBike.customStatus?.name ?? job.statusDisplayName,
          jobBike.customStatus?.colorValue ?? _operationalStatusColor(job),
        );
      }
    }

    return breakdown.values.toList()
      ..sort((a, b) {
        final countComparison = b.count.compareTo(a.count);
        if (countComparison != 0) return countComparison;
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
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
        // Compact product classes never reach this owner; they use the
        // dedicated Jobs list above. Desktop keeps its real table even when
        // sidebar/zoom reduce the remaining content width, relying on the
        // table's deliberate horizontal scroll instead of a hybrid card view.
        // Calculate total width of all visible columns
        final totalColumnsWidth =
            _displayColumns.fold<double>(0, (sum, col) => sum + col.width);

        // Use the larger of constraints.maxWidth or totalColumnsWidth
        final tableWidth = totalColumnsWidth > constraints.maxWidth
            ? totalColumnsWidth
            : constraints.maxWidth;

        // Check if horizontal scrolling is needed
        final needsHorizontalScroll = totalColumnsWidth > constraints.maxWidth;
        final tableBodyColor = Theme.of(context).colorScheme.surface;

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
                        child: Container(
                          color: tableBodyColor,
                          child: ListView.builder(
                            itemCount: paginatedJobs.length,
                            itemBuilder: (context, index) => _buildTableRow(
                                paginatedJobs[index], tableWidth),
                          ),
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
    final theme = Theme.of(context);
    final customer = _customers[job.customerId];
    final bike = _bikes[job.bikeId];
    final invoice = job.invoiceId == null ? null : _invoices[job.invoiceId];
    final displayTotal = invoice?.total ?? job.totalCost;
    final paidAmount = invoice?.paidAmount ?? (job.isPaid ? displayTotal : 0.0);
    final outstanding =
        (displayTotal - paidAmount).clamp(0.0, double.infinity).toDouble();
    final jobKey = job.id ?? job.jobNumber ?? 'sin-id';
    final isOverdue = job.isOverdue;
    final request =
        (job.isStandaloneQuotation ? job.subjectNotes : job.clientRequest)
            ?.trim();
    final diagnosis = job.diagnosis?.trim();
    final isExpanded = _expandedMobileJobKeys.contains(jobKey);

    return Container(
      key: ValueKey('workshop-job-card-$jobKey'),
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              theme.colorScheme.primary.withValues(alpha: 0.025),
              theme.colorScheme.surface,
            ),
            theme.colorScheme.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.2 : 0.075,
            ),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 3,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.primary.withValues(alpha: 0.24),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.58, 1],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 10, 5),
              color: Colors.transparent,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isOverdue) ...[
                    Container(
                      width: 3,
                      height: 42,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 9),
                  ],
                  Expanded(
                    child: Semantics(
                      button: customer?.id?.isNotEmpty == true,
                      label: customer == null
                          ? job.jobNumber ?? 'Trabajo sin número'
                          : 'Abrir cliente ${customer.name}',
                      child: InkWell(
                        key: ValueKey('workshop-job-customer-$jobKey'),
                        onTap: customer?.id?.isNotEmpty == true
                            ? () => context.push('/clientes/${customer!.id}')
                            : null,
                        borderRadius: BorderRadius.circular(6),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        job.jobNumber ?? 'Sin número',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    if (job.priority == JobPriority.urgente ||
                                        job.priority == JobPriority.alta) ...[
                                      const SizedBox(width: 7),
                                      Text(
                                        job.priority.displayName,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: job.priority ==
                                                  JobPriority.urgente
                                              ? theme.colorScheme.error
                                              : theme
                                                  .colorScheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (customer != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    customer.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: customer.id?.isNotEmpty == true
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildMobileStatusAction(
                    job: job,
                    invoice: invoice,
                    jobKey: jobKey,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 3, 12, 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildMobileJobObject(
                          job: job,
                          customer: customer,
                          bike: bike,
                          jobKey: jobKey,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Container(
                        width: 1,
                        height: 34,
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.38),
                      ),
                      const SizedBox(width: 7),
                      SizedBox(
                        width: 126,
                        child: _buildMobileJobDisclosure(
                          job: job,
                          jobKey: jobKey,
                          displayTotal: displayTotal,
                          paidAmount: paidAmount,
                          outstanding: outstanding,
                          isExpanded: isExpanded,
                        ),
                      ),
                    ],
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: isExpanded
                        ? _buildMobileExpandedJobDetails(
                            job: job,
                            invoice: invoice,
                            request: request,
                            diagnosis: diagnosis,
                            displayTotal: displayTotal,
                            paidAmount: paidAmount,
                            outstanding: outstanding,
                            isOverdue: isOverdue,
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.38),
                  ),
                ),
              ),
              child: _buildMobileJobActionBar(
                job: job,
                customer: customer,
                invoice: invoice,
                jobKey: jobKey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileJobObject({
    required MechanicJob job,
    required Customer? customer,
    required Bike? bike,
    required String jobKey,
  }) {
    final theme = Theme.of(context);
    final linkedBikes = _linkedBikesForJob(job);
    final persistedBikeCount = _jobBikesMap[job.id]?.length ?? 0;
    final linkedBikeCount = persistedBikeCount > linkedBikes.length
        ? persistedBikeCount
        : linkedBikes.length;
    final displayedBike = linkedBikes.firstOrNull ?? bike;
    late final String eyebrow;
    late final String label;
    late final IconData icon;
    VoidCallback? onTap;

    if (job.isSaleWorkflow) {
      eyebrow = 'Operación';
      label = 'Venta / cobro · Sin objeto recibido';
      icon = Icons.shopping_bag_outlined;
    } else if (job.isStandaloneQuotation) {
      eyebrow = 'Operación';
      label = 'Cotización · Sin objeto recibido';
      icon = Icons.description_outlined;
    } else if (job.isComponentIntake) {
      eyebrow = 'Componente';
      label = _componentObjectLabel(job);
      icon = Icons.build_outlined;
    } else if (displayedBike != null) {
      eyebrow = linkedBikeCount > 1 ? 'Bicicletas' : 'Bicicleta';
      label = linkedBikeCount > 1
          ? '$linkedBikeCount vinculadas'
          : displayedBike.displayName;
      icon = Icons.pedal_bike_outlined;
      if (customer != null) {
        onTap = () => unawaited(_openMobileJobBike(job, customer));
      }
    } else {
      eyebrow = 'Recepción';
      label = 'Sin objeto registrado';
      icon = Icons.inventory_2_outlined;
    }

    return Semantics(
      button: onTap != null,
      label: onTap == null ? '$eyebrow: $label' : 'Abrir $eyebrow: $label',
      child: InkWell(
        key: ValueKey('workshop-job-bike-$jobKey'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 17,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileStatusAction({
    required MechanicJob job,
    required Invoice? invoice,
    required String jobKey,
  }) {
    late final String label;
    late final Color color;
    String? metaText;
    VoidCallback? onTap;

    if (job.deletedAt != null) {
      label = 'Eliminado';
      color = const Color(0xFFB91C1C);
      metaText = job.archiveReason;
    } else if (job.isSaleWorkflow) {
      label = mechanicJobSalePaymentLabel(job, invoice);
      color = _isSaleFullyPaid(job, invoice: invoice)
          ? Colors.green
          : Colors.orange;
      final invoiceId = job.invoiceId;
      if (invoiceId != null && invoiceId.isNotEmpty) {
        onTap = () => _openMobileInlineSurface(
              job,
              _MobileWorkshopSurface.invoice,
            );
      }
    } else if (job.isStandaloneQuotation) {
      label = job.statusDisplayName;
      color = _proposalStatusColor(job);
      onTap = () => _showStatusMenu(job);
    } else {
      label = job.statusDisplayName;
      color = _operationalStatusColor(job);
      metaText = job.isServiceBudget
          ? job.proposalStatusDisplayName
          : _serviceWarrantyMeta(job);
      onTap = () => _showStatusMenu(job);
    }

    final normalizedLabel =
        toBeginningOfSentenceCase(label.trim().toLowerCase());
    final age = job.isStandaloneQuotation
        ? null
        : _formatMobileRelativeTime(job.statusUpdatedAt);
    final theme = Theme.of(context);

    return Semantics(
      button: onTap != null,
      label: onTap == null
          ? normalizedLabel
          : 'Cambiar o abrir estado: $normalizedLabel',
      child: InkWell(
        key: ValueKey('workshop-job-status-$jobKey'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, maxWidth: 142),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                color.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.15 : 0.075,
                ),
                theme.colorScheme.surface,
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: color.withValues(alpha: 0.16),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        normalizedLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (onTap != null) ...[
                      const SizedBox(width: 2),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),
                if (age != null || metaText != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    metaText ?? age!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileFinancialSummary({
    required MechanicJob job,
    required Invoice? invoice,
    required double displayTotal,
    required double paidAmount,
    required double outstanding,
  }) {
    final isProposal = job.isQuotationWorkflow;
    final theme = Theme.of(context);
    final money = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 158),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${isProposal ? (job.isServiceBudget ? 'Presup.' : 'Cotiz.') : 'Total'} ${money.format(displayTotal)}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (!isProposal && invoice != null) ...[
            const SizedBox(height: 2),
            Text(
              outstanding > 0.01
                  ? 'Pagado ${money.format(paidAmount)} · Saldo ${money.format(outstanding)}'
                  : 'Pagado completo',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10.5,
                color: outstanding > 0.01
                    ? theme.colorScheme.onSurfaceVariant
                    : _workshopSettledColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMobileJobDisclosure({
    required MechanicJob job,
    required String jobKey,
    required double displayTotal,
    required double paidAmount,
    required double outstanding,
    required bool isExpanded,
  }) {
    final theme = Theme.of(context);
    final compactFinancial = _mobileCompactFinancialLabel(
      job: job,
      displayTotal: displayTotal,
      paidAmount: paidAmount,
      outstanding: outstanding,
    );

    return Semantics(
      button: true,
      expanded: isExpanded,
      label: isExpanded
          ? 'Ocultar información operativa'
          : 'Mostrar información operativa',
      child: InkWell(
        key: ValueKey('workshop-job-expand-$jobKey'),
        onTap: () {
          setState(() {
            if (isExpanded) {
              _expandedMobileJobKeys.remove(jobKey);
            } else {
              _expandedMobileJobKeys.add(jobKey);
            }
          });
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              theme.colorScheme.primary.withValues(alpha: 0.045),
              theme.colorScheme.surface,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ingreso ${DateFormat('dd/MM', 'es_CL').format(job.arrivalDate)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (compactFinancial != null)
                      Text(
                        compactFinancial,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 3),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.11),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 17,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _mobileCompactFinancialLabel({
    required MechanicJob job,
    required double displayTotal,
    required double paidAmount,
    required double outstanding,
  }) {
    if (displayTotal <= 0) return null;
    final money = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    if (job.isQuotationWorkflow) {
      final label = job.isServiceBudget ? 'Presup.' : 'Cotiz.';
      return '$label ${money.format(displayTotal)}';
    }
    if (outstanding > 0.01) {
      return 'Saldo ${money.format(outstanding)}';
    }
    if (paidAmount > 0.01) {
      return 'Pagado ${money.format(paidAmount)}';
    }
    return 'Total ${money.format(displayTotal)}';
  }

  Widget _buildMobileExpandedJobDetails({
    required MechanicJob job,
    required Invoice? invoice,
    required String? request,
    required String? diagnosis,
    required double displayTotal,
    required double paidAmount,
    required double outstanding,
    required bool isOverdue,
  }) {
    final theme = Theme.of(context);
    final deadline = job.deliveryDeadline;

    return Container(
      key: ValueKey(
        'workshop-job-expanded-${job.id ?? job.jobNumber ?? 'sin-id'}',
      ),
      margin: const EdgeInsets.only(top: 7),
      padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (job.isSaleWorkflow) ...[
            _buildSaleProductSummary(job),
            const SizedBox(height: 7),
          ],
          if (request != null && request.isNotEmpty) ...[
            Text(
              'Solicitud',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              request,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.3),
            ),
          ],
          if (diagnosis != null && diagnosis.isNotEmpty) ...[
            if (request != null && request.isNotEmpty)
              const SizedBox(height: 7),
            Text(
              'Diagnóstico',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              diagnosis,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.3),
            ),
          ],
          _buildMobileTimeSummary(job),
          if (deadline != null || displayTotal > 0) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (deadline != null)
                  Expanded(
                    child: Text(
                      '${isOverdue ? 'Vencido' : 'Plazo'} ${DateFormat('dd/MM', 'es_CL').format(deadline)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isOverdue
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight:
                            isOverdue ? FontWeight.w700 : FontWeight.normal,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                if (displayTotal > 0)
                  _buildMobileFinancialSummary(
                    job: job,
                    invoice: invoice,
                    displayTotal: displayTotal,
                    paidAmount: paidAmount,
                    outstanding: outstanding,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMobileJobActionBar({
    required MechanicJob job,
    required Customer? customer,
    required Invoice? invoice,
    required String jobKey,
  }) {
    final actions = <Widget>[];
    final isArchived = job.deletedAt != null;
    final invoiceId = job.invoiceId;
    if (!isArchived) {
      actions.add(
        _buildMobileCardAction(
          key: ValueKey('workshop-job-open-$jobKey'),
          label: 'Trabajo',
          semanticsLabel: 'Abrir trabajo',
          primary: true,
          onTap: () => _openMobileInlineSurface(
            job,
            _MobileWorkshopSurface.job,
          ),
        ),
      );
      actions.add(
        _buildMobileCardAction(
          key: ValueKey('workshop-job-items-$jobKey'),
          label: 'Ítems',
          semanticsLabel: 'Abrir productos y servicios del trabajo',
          onTap: () => _openMobileInlineSurface(
            job,
            _MobileWorkshopSurface.items,
          ),
        ),
      );
    }
    if (invoiceId != null && invoiceId.isNotEmpty) {
      actions.add(
        _buildMobileCardAction(
          key: ValueKey('workshop-job-invoice-$jobKey'),
          label: 'Factura',
          semanticsLabel: 'Abrir factura del trabajo',
          onTap: () => _openMobileInlineSurface(
            job,
            _MobileWorkshopSurface.invoice,
          ),
        ),
      );
    } else if (job.isQuotationWorkflow) {
      actions.add(
        _buildMobileCardAction(
          key: ValueKey('workshop-job-proposal-pdf-$jobKey'),
          label: 'PDF',
          semanticsLabel: 'Abrir ${job.proposalDocumentLabelLower} en PDF',
          onTap: () => _openMobileInlineSurface(
            job,
            _MobileWorkshopSurface.proposalPdf,
          ),
        ),
      );
    } else if (!isArchived) {
      actions.add(
        _buildMobileCardAction(
          key: ValueKey('workshop-job-create-invoice-$jobKey'),
          label: 'Factura',
          semanticsLabel: 'Preparar factura del trabajo',
          onTap: () => _openMobileInlineSurface(
            job,
            _MobileWorkshopSurface.invoice,
          ),
        ),
      );
    }
    actions.add(
      _buildMobileCardAction(
        key: ValueKey('workshop-job-more-$jobKey'),
        label: 'Más',
        semanticsLabel: 'Ver más acciones del trabajo',
        onTap: () => unawaited(
          _showMobileJobActions(
            job,
            customer: customer,
            invoice: invoice,
          ),
        ),
      ),
    );

    return Row(
      children: actions,
    );
  }

  Widget _buildMobileCardAction({
    required Key key,
    required String label,
    required String semanticsLabel,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    final theme = Theme.of(context);
    return Expanded(
      child: Semantics(
        button: true,
        label: semanticsLabel,
        child: InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            height: 48,
            margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            decoration: BoxDecoration(
              color: primary
                  ? theme.colorScheme.primary.withValues(alpha: 0.09)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: primary
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: primary ? FontWeight.w800 : FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileTimeSummary(MechanicJob job) {
    final metrics = job.timeMetrics;
    if (metrics == null || !_usesOperationalLifecycle(job)) {
      return const SizedBox.shrink();
    }

    final now = DateTime.now();
    final terminal = metrics.currentIsCompleted || metrics.currentIsDelivered;
    final waitOrigin = metrics.approvalDecision == 'approved' &&
            metrics.approvalDecisionAt != null
        ? metrics.approvalDecisionAt!
        : job.arrivalDate;
    final waitEnd = metrics.startedAt ?? (terminal ? null : now);
    final executionEnd = metrics.completedAt ??
        (metrics.startedAt != null && !metrics.currentIsCompleted ? now : null);
    final cycleEnd =
        metrics.firstDeliveredAt ?? (metrics.currentIsDelivered ? null : now);
    final entries = <String>[
      'Espera ${_formatMobileDuration(waitEnd?.difference(waitOrigin))}',
      'Ejecución ${metrics.startedAt == null ? '—' : _formatMobileDuration(executionEnd?.difference(metrics.startedAt!))}',
      'Ciclo ${_formatMobileDuration(cycleEnd?.difference(job.arrivalDate))}',
    ];
    final theme = Theme.of(context);

    return Container(
      key: ValueKey(
        'workshop-job-time-${job.id ?? job.jobNumber ?? 'sin-id'}',
      ),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        entries.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _formatMobileDuration(Duration? duration) {
    if (duration == null || duration.isNegative) return '—';
    if (duration.inDays > 0) {
      return '${duration.inDays}d ${duration.inHours.remainder(24)}h';
    }
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    }
    return '${duration.inMinutes.clamp(0, 59)}m';
  }

  String? _formatMobileRelativeTime(DateTime? timestamp) {
    if (timestamp == null) return null;
    final difference = DateTime.now().difference(timestamp);
    if (difference.isNegative) return null;
    if (difference.inMinutes < 1) return 'ahora';
    if (difference.inMinutes < 60) return 'hace ${difference.inMinutes}m';
    if (difference.inHours < 24) return 'hace ${difference.inHours}h';
    if (difference.inDays < 7) return 'hace ${difference.inDays}d';
    return DateFormat('dd/MM', 'es_CL').format(timestamp);
  }

  Future<void> _showMobileJobActions(
    MechanicJob job, {
    required Customer? customer,
    required Invoice? invoice,
  }) async {
    final jobKey = job.id ?? job.jobNumber ?? 'sin-id';
    final isArchived = job.deletedAt != null;
    final invoiceId = job.invoiceId;
    final selection = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        Widget actionTile(
          String value,
          IconData icon,
          String label, {
          String? subtitle,
          Color? color,
        }) {
          final theme = Theme.of(sheetContext);
          return ListTile(
            key: ValueKey('workshop-job-more-$value-$jobKey'),
            leading: Icon(
              icon,
              color: color ?? theme.colorScheme.onSurfaceVariant,
            ),
            title: Text(label, style: TextStyle(color: color)),
            subtitle: subtitle == null ? null : Text(subtitle),
            minVerticalPadding: 10,
            onTap: () => Navigator.pop(sheetContext, value),
          );
        }

        Widget sectionLabel(String label) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
            child: Text(
              label.toUpperCase(),
              style: Theme.of(sheetContext).textTheme.labelSmall?.copyWith(
                    color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
            ),
          );
        }

        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.78,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  '${job.jobNumber ?? 'Trabajo'} · Acciones',
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              if (customer?.phone?.isNotEmpty == true ||
                  customer?.email?.isNotEmpty == true) ...[
                sectionLabel('Contacto'),
                if (customer?.phone?.isNotEmpty == true)
                  actionTile(
                    'call',
                    Icons.phone_outlined,
                    'Copiar teléfono',
                  ),
                if (customer?.email?.isNotEmpty == true)
                  actionTile(
                    'email',
                    Icons.email_outlined,
                    'Copiar email',
                  ),
              ],
              if ((invoiceId != null && invoiceId.isNotEmpty) ||
                  (!isArchived &&
                      job.isQuotationWorkflow &&
                      job.effectiveQuotationStatus ==
                          QuotationStatus.approved)) ...[
                sectionLabel('Documento y cobro'),
              ],
              if (invoiceId != null && invoiceId.isNotEmpty)
                actionTile(
                  'invoice_preview',
                  Icons.picture_as_pdf_outlined,
                  'Vista PDF de factura',
                ),
              if (!isArchived && _canRegisterPaymentForJob(job))
                actionTile(
                  'payment',
                  Icons.payments_outlined,
                  'Registrar abono',
                ),
              if (!isArchived &&
                  job.isQuotationWorkflow &&
                  job.effectiveQuotationStatus == QuotationStatus.approved)
                actionTile(
                  'convert',
                  Icons.transform,
                  job.isServiceBudget
                      ? 'Facturar presupuesto'
                      : 'Convertir cotización',
                ),
              if (!isArchived &&
                  (job.modeNeedsReview || _usesOperationalLifecycle(job))) ...[
                sectionLabel('Operación'),
                if (job.modeNeedsReview)
                  actionTile(
                    'classify',
                    Icons.rule_folder_outlined,
                    'Clasificar recepción',
                  ),
                if (_usesOperationalLifecycle(job))
                  actionTile(
                    'complete',
                    Icons.check_circle_outline,
                    'Marcar como terminado',
                  ),
              ],
              const Divider(height: 24),
              if (isArchived)
                actionTile(
                  'restore',
                  Icons.restore,
                  'Restaurar trabajo',
                )
              else
                actionTile(
                  'delete',
                  Icons.delete_outline,
                  'Eliminar de la operación',
                  subtitle: 'Archiva el trabajo con motivo y auditoría',
                  color: Colors.red.shade700,
                ),
            ],
          ),
        );
      },
    );

    if (!mounted || selection == null) return;
    switch (selection) {
      case 'call':
        _callCustomer(customer!.phone!);
        break;
      case 'email':
        _emailCustomer(customer!.email!);
        break;
      case 'invoice_preview':
        await _openInvoicePreview(invoiceId!, invoice: invoice);
        break;
      case 'payment':
        await _registerInvoicePayment(invoiceId!);
        break;
      case 'convert':
        await _convertToService(job);
        break;
      case 'classify':
        await _classifyJobIntake(job);
        break;
      case 'complete':
        await _markJobAsComplete(job);
        break;
      case 'delete':
        await Future<void>.delayed(Duration.zero);
        if (mounted) await _confirmDelete(job);
        break;
      case 'restore':
        await Future<void>.delayed(Duration.zero);
        if (mounted) await _confirmRestore(job);
        break;
    }
  }

  Color _proposalStatusColor(MechanicJob job) {
    return switch (job.effectiveQuotationStatus) {
      QuotationStatus.pending => Colors.orange,
      QuotationStatus.approved => Colors.green,
      QuotationStatus.rejected => Colors.red,
      QuotationStatus.expired => Colors.grey,
    };
  }

  Color _operationalStatusColor(MechanicJob job) =>
      job.customStatus?.colorValue ?? _getStatusColor(job.status);

  bool _usesOperationalLifecycle(MechanicJob job) =>
      !job.isSaleWorkflow && !job.isStandaloneQuotation;

  String _componentObjectLabel(MechanicJob job) {
    final subjectName = job.subjectData?.name.trim();
    if (subjectName != null && subjectName.isNotEmpty) return subjectName;
    final notes = job.subjectNotes?.trim();
    if (notes != null && notes.isNotEmpty) return notes;
    return 'Componente recibido';
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

    return _buildStatusBadge(
      label: label,
      accentColor: color,
      maxWidth: 132,
      compact: true,
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

  Widget _buildStatusBadge({
    required String label,
    required Color accentColor,
    DateTime? timestamp,
    String? metaText,
    IconData metaIcon = Icons.access_time_rounded,
    VoidCallback? onTap,
    double maxWidth = 132,
    bool compact = false,
  }) {
    return OperationalStatusBadge(
      label: label,
      accentColor: accentColor,
      timestamp: timestamp,
      metaText: metaText,
      metaIcon: metaIcon,
      onTap: onTap,
      maxWidth: maxWidth,
      compact: compact,
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
    final theme = Theme.of(context);

    return Container(
      width: tableWidth,
      height: 48,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor,
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
    final theme = Theme.of(context);
    final isSelected = _selectedJob?.id == job.id;
    final customer = _customers[job.customerId];
    final bike = _bikes[job.bikeId];
    final jobBikes = _jobBikesMap[job.id]; // Multi-bike data

    final jobId = job.id;
    final isExpanded = jobId != null && _expandedJobIds.contains(jobId);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: tableWidth,
          // 60 is a FLOOR, not a height. A fixed height clipped any row whose
          // status badge carries both a wrapped label and a timestamp — that
          // is the "BOTTOM OVERFLOWED BY 4.0 PIXELS" stripe on PRESUPUESTO.
          // With a minimum the row still renders exactly 60 for ordinary
          // content and grows on its own when the content asks for more.
          constraints: const BoxConstraints(minHeight: 60),
          decoration: BoxDecoration(
            color: isSelected
                ? Color.alphaBlend(
                    theme.colorScheme.primary.withValues(alpha: 0.08),
                    theme.colorScheme.surface,
                  )
                : theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.5),
              ),
            ),
          ),
          child: Row(
            children: _displayColumns.map((col) {
              return _buildDataCell(col, job, customer, bike, jobBikes);
            }).toList(),
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
          vertical: 4,
        ),
        child: content,
      ),
    );
  }

  double _tableCellHorizontalPadding(ColumnConfig col) {
    return switch (col.id) {
      'checkbox' || 'attachments' => 4,
      'actions' => 4,
      'deadline' || 'state' || 'kpi' || 'priority' || 'invoice' || 'total' => 8,
      _ => 16,
    };
  }

  Widget _buildInteractiveTableField({
    required Widget child,
    required VoidCallback? onTap,
    Color? accentColor,
    EdgeInsetsGeometry padding =
        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    BorderRadius? borderRadius,
    double? maxWidth,
    GestureTapDownCallback? onSecondaryTapDown,
  }) {
    return InteractiveTableField(
      onTap: onTap,
      accentColor: accentColor,
      padding: padding,
      borderRadius: borderRadius ?? BorderRadius.circular(7),
      maxWidth: maxWidth,
      onSecondaryTapDown: onSecondaryTapDown,
      child: child,
    );
  }

  void _toggleExpandedJobBikes(String? jobId) {
    if (jobId == null) return;
    setState(() {
      if (_expandedJobIds.contains(jobId)) {
        _expandedJobIds.remove(jobId);
      } else {
        _expandedJobIds.add(jobId);
      }
    });
  }

  Widget _buildBikeGlyph({double size = 35}) {
    // The asset is a 99.9% pure-black silhouette, so it painted black on a
    // black row: an image obeys no theme. Tinting recolours it without
    // touching its shape. It stays on the muted CONTENT role rather than the
    // preset accent because a subject glyph is description, not an action —
    // only actions spend the accent budget.
    //
    // The fallback icon was already theme-aware while the real artwork was
    // not, which is why the bug only ever showed when the asset loaded.
    final glyphColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Image.asset(
      'assets/icons/mtb_bike_v3.png',
      width: size,
      height: size,
      color: glyphColor,
      errorBuilder: (context, error, stackTrace) => Icon(
        Icons.pedal_bike,
        size: size,
        color: glyphColor,
      ),
    );
  }

  Widget _buildBikePhotoButton(String imageUrl) {
    return _buildInteractiveTableField(
      onTap: () => _showBikeImageModal(imageUrl),
      padding: const EdgeInsets.all(2),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          image: DecorationImage(
            image: NetworkImage(imageUrl),
            fit: BoxFit.cover,
          ),
          border: Border.all(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
    );
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

      case 'kpi':
        return CompactJobTimeMetrics(job: job);

      case 'id':
        return const Text('-');

      case 'job_number':
        return _buildInteractiveTableField(
          onTap: () => _openJobFromTable(job),
          maxWidth: 104,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                job.jobNumber ?? 'Sin #',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface,
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
        );

      case 'customer':
        // Clickable customer with quick actions
        return LayoutBuilder(
          builder: (context, constraints) {
            final hasQuickActions = customer != null &&
                (customer.phone != null || customer.email != null);
            final contentMaxWidth =
                (constraints.maxWidth - (hasQuickActions ? 28 : 0))
                    .clamp(72.0, constraints.maxWidth)
                    .toDouble();

            final customerContent = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  customer?.name ?? 'Desconocido',
                  style: TextStyle(
                    fontSize: 13,
                    color: customer?.id != null
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface,
                    fontWeight: customer?.id != null
                        ? FontWeight.w600
                        : FontWeight.w400,
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
            );

            return Row(
              children: [
                Flexible(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _buildInteractiveTableField(
                      onTap: customer?.id != null
                          ? () => context.push('/clientes/${customer!.id}')
                          : null,
                      maxWidth: contentMaxWidth,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      child: customerContent,
                    ),
                  ),
                ),
                if (hasQuickActions)
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      size: 16,
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.7),
                    ),
                    tooltip: '',
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
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
                              const Text('Email',
                                  style: TextStyle(fontSize: 13)),
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
            );
          },
        );

      case 'bike':
        // Multi-bike modes:
        // 1. isMultiBikeSummary: Main row shows "X Bicicletas" with expand button
        // 2. isPerBikeDetail: Expanded row shows specific bike name
        // 3. Single bike: Normal display

        final jobId = job.id;
        final isExpanded = jobId != null && _expandedJobIds.contains(jobId);

        if (job.isSaleWorkflow) {
          return Row(
            children: [
              Icon(
                Icons.shopping_bag_outlined,
                size: 26,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 7),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Venta / cobro',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Sin objeto recibido',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        // Per-bike detail row - show just the specific bike name
        if (isPerBikeDetail) {
          final bikeName = bike?.displayName ?? 'Sin nombre';
          final bikeImageUrl = bike?.imageUrl;

          return LayoutBuilder(
            builder: (context, constraints) {
              return Row(
                children: [
                  if (bikeImageUrl != null) ...[
                    _buildBikePhotoButton(bikeImageUrl),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _buildInteractiveTableField(
                        onTap: () => _showBikeProfileDialog(
                          job,
                          customer,
                          initialBike: bike,
                        ),
                        maxWidth: constraints.maxWidth,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildBikeGlyph(size: 30),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                bikeName,
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis,
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
        }

        // Multi-bike summary row - show count and expand button
        if (isMultiBikeSummary) {
          final bikeCount = jobBikes.length;

          return LayoutBuilder(
            builder: (context, constraints) {
              return Align(
                alignment: Alignment.centerLeft,
                child: _buildInteractiveTableField(
                  onTap: () => _toggleExpandedJobBikes(jobId),
                  maxWidth: constraints.maxWidth,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildBikeGlyph(size: 30),
                      const SizedBox(width: 6),
                      Flexible(
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
                      const SizedBox(width: 2),
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        }

        // Non-bike job: show subject/item instead of bike
        if (job.isComponentIntake ||
            job.bikeId == null ||
            (job.jobType == JobType.itemService && job.subjectData != null)) {
          final subjectName = job.isStandaloneQuotation
              ? 'Cotización · Sin objeto recibido'
              : job.isComponentIntake
                  ? _componentObjectLabel(job)
                  : job.subjectData?.name ??
                      (job.subjectNotes?.trim().isNotEmpty == true
                          ? job.subjectNotes!.trim()
                          : job.modeNeedsReview
                              ? 'Clasificación pendiente'
                              : 'Sin detalle de recepción');
          final subjectNotes = job.isStandaloneQuotation
              ? (job.subjectNotes?.trim().isNotEmpty == true
                  ? job.subjectNotes!.trim()
                  : null)
              : job.isComponentIntake
                  ? (job.subjectData != null &&
                          job.subjectNotes?.trim().isNotEmpty == true
                      ? job.subjectNotes!.trim()
                      : null)
                  : (job.subjectData != null &&
                          job.subjectNotes != null &&
                          job.subjectNotes!.isNotEmpty)
                      ? job.subjectNotes
                      : job.modeNeedsReview
                          ? job.modeReviewReason
                          : null;
          final subjectIcon = job.modeNeedsReview
              ? Icons.warning_amber_rounded
              : job.isStandaloneQuotation
                  ? Icons.request_quote_outlined
                  : job.isComponentIntake
                      ? Icons.build_circle_outlined
                      : _jobTypeIcon(job.jobType);
          final subjectColor = job.modeNeedsReview
              ? Colors.orange.shade700
              : Theme.of(context).colorScheme.secondary;
          return Row(
            children: [
              Tooltip(
                message: job.modeNeedsReview
                    ? (job.modeReviewReason ??
                        'Este registro histórico necesita completar su clasificación.')
                    : job.isQuotationWorkflow
                        ? job.proposalDocumentLabel
                        : job.jobType.displayName,
                child: Icon(subjectIcon, size: 28, color: subjectColor),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      subjectName,
                      style: TextStyle(
                        fontSize: 13,
                        color: job.modeNeedsReview ? subjectColor : null,
                        fontWeight: job.modeNeedsReview
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
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

        return LayoutBuilder(
          builder: (context, constraints) {
            return Row(
              children: [
                if (bikeImageUrl != null) ...[
                  _buildBikePhotoButton(bikeImageUrl),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _buildInteractiveTableField(
                      onTap: () => _showBikeProfileDialog(job, customer),
                      maxWidth: constraints.maxWidth,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildBikeGlyph(size: 30),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              bikeName,
                              style: const TextStyle(fontSize: 13),
                              overflow: TextOverflow.ellipsis,
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

      case 'arrival_date':
        final days = DateTime.now().difference(job.arrivalDate).inDays;
        // How long a bike has been sitting is a severity, so it reads from the
        // same three tones as every other state in the table instead of its
        // own pastel scale — which stayed light-mode pale on a dark row.
        final ageRoles = VinabikeThemeRoles.of(context);
        final ageTone = days > 14
            ? ageRoles.danger
            : days > 7
                ? ageRoles.warning
                : ageRoles.neutral;
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
                color: ageTone.container,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$days día${days != 1 ? 's' : ''}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: ageTone.onContainer,
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
        if (job.deletedAt != null) {
          return LayoutBuilder(
            builder: (context, constraints) => Align(
              alignment: Alignment.centerLeft,
              child: _buildStatusBadge(
                label: 'ELIMINADO',
                accentColor: const Color(0xFFB91C1C),
                timestamp: job.deletedAt,
                metaText: job.archiveReason,
                metaIcon: Icons.delete_outline,
                onTap: null,
                maxWidth:
                    constraints.maxWidth.isFinite ? constraints.maxWidth : 132,
              ),
            ),
          );
        }

        // Per-bike detail: show per-bike status (independent per bike)
        if (isPerBikeDetail) {
          // Use per-bike status if set, otherwise fall back to job status
          final bikeStatus = jobBike.customStatus;
          final statusColor = bikeStatus != null
              ? bikeStatus.colorValue
              : _operationalStatusColor(job);
          final statusName = bikeStatus?.name ?? job.statusDisplayName;
          final proposalMeta =
              job.isServiceBudget ? job.proposalStatusDisplayName : null;
          return LayoutBuilder(
            builder: (context, constraints) {
              final chipWidth =
                  constraints.maxWidth.isFinite ? constraints.maxWidth : 132.0;

              return Align(
                alignment: Alignment.centerLeft,
                child: _buildStatusBadge(
                  label: statusName,
                  accentColor: statusColor,
                  timestamp: jobBike.updatedAt,
                  metaText: proposalMeta ?? _serviceWarrantyMeta(job),
                  metaIcon: proposalMeta == null
                      ? Icons.shield_outlined
                      : Icons.request_quote_outlined,
                  onTap: () => _showBikeStatusMenu(job, jobBike),
                  maxWidth: chipWidth,
                ),
              );
            },
          );
        }

        // Single bike job: show job-level status
        final statusColor = job.isStandaloneQuotation
            ? _proposalStatusColor(job)
            : _operationalStatusColor(job);
        final statusName = job.statusDisplayName;
        final statusUpdatedAt = job.statusUpdatedAt;
        final proposalMeta =
            job.isServiceBudget ? job.proposalStatusDisplayName : null;
        return LayoutBuilder(
          builder: (context, constraints) {
            final chipWidth =
                constraints.maxWidth.isFinite ? constraints.maxWidth : 132.0;

            return Align(
              alignment: Alignment.centerLeft,
              // The Builder exists so the chip has a BuildContext of its OWN.
              // The popover anchors to the trigger's rect, and the surrounding
              // cell context would resolve to the whole column instead.
              child: Builder(
                builder: (chipContext) => _buildStatusBadge(
                  label: statusName,
                  accentColor: statusColor,
                  timestamp: job.isStandaloneQuotation ? null : statusUpdatedAt,
                  metaText: proposalMeta ?? _serviceWarrantyMeta(job),
                  metaIcon: proposalMeta == null
                      ? Icons.shield_outlined
                      : Icons.request_quote_outlined,
                  onTap: job.isSaleWorkflow
                      ? null
                      : () => _showStatusMenu(job, anchorContext: chipContext),
                  maxWidth: chipWidth,
                ),
              ),
            );
          },
        );

      case 'priority':
        // Colored priority with icon
        final priorityColor = _getPriorityColor(job.priority);
        final priorityIcon = _priorityIcon(job.priority);
        return Builder(
          builder: (cellContext) {
            return _buildInteractiveTableField(
              onTap: () => _showPriorityMenu(cellContext, job),
              accentColor: priorityColor,
              padding: EdgeInsets.zero,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                constraints: const BoxConstraints(maxWidth: 96),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Theme.of(context).dividerColor,
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
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.expand_more,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            );
          },
        );

      case 'diagnosis':
        if (job.isSaleWorkflow) {
          return _buildSaleProductSummary(job);
        }
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
              final messenger = ScaffoldMessenger.maybeOf(context);
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
                  messenger?.showSnackBar(
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
            final messenger = ScaffoldMessenger.maybeOf(context);
            // Start local operation to suppress reload from service notification
            _startLocalOperation();

            // Optimistic update - only update fields that were changed
            final updatedJob = job.copyWith(
              clientRequest: clientRequest,
              clearClientRequest: clientRequest?.isEmpty ?? false,
              diagnosis: diagnosis,
              clearDiagnosis: diagnosis?.isEmpty ?? false,
              workPerformed: workPerformed,
              clearWorkPerformed: workPerformed?.isEmpty ?? false,
              notes: notes,
              clearNotes: notes?.isEmpty ?? false,
              updatedAt: DateTime.now(),
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
                messenger?.showSnackBar(
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
          final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
          return Tooltip(
            message: 'Subtotal bicicleta: ${fmt.format(jobBike.subtotal)}',
            waitDuration: const Duration(milliseconds: 350),
            child: Text(
              fmt.format(jobBike.subtotal),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          );
        }

        if (job.isQuotationWorkflow) {
          final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
          final totalLabel =
              job.isServiceBudget ? 'Total presupuestado' : 'Total cotizado';
          return Tooltip(
            message:
                '$totalLabel: ${fmt.format(job.totalCost)}\nDocumento no facturado; no es una cuenta por cobrar.',
            waitDuration: const Duration(milliseconds: 350),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fmt.format(job.totalCost),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.orange.shade800,
                  ),
                ),
                Text(
                  job.isServiceBudget ? 'Presupuestado' : 'Cotizado',
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
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
        final dueAmount =
            (displayTotal - paidAmount).clamp(0.0, double.infinity);
        final tooltip = [
          'Total: ${fmt.format(displayTotal)}',
          'Pagado: ${fmt.format(paidAmount)}',
          'Por cobrar: ${fmt.format(dueAmount)}',
        ].join('\n');

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

        return Tooltip(
          message: tooltip,
          waitDuration: const Duration(milliseconds: 350),
          child: content,
        );

      case 'invoice':
        // Clickable invoice with full status display
        if (job.jobType == JobType.warranty &&
            job.warrantyOutcome == WarrantyOutcome.covered &&
            job.invoiceId != null) {
          return Tooltip(
            message:
                'Documento interno: respalda inventario y costo de garantía; '
                'no es una factura para el cliente.',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF059669).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFF059669).withValues(alpha: 0.35),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_outlined,
                      size: 14, color: Color(0xFF047857)),
                  SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      'RESPALDO INTERNO',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF047857),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (job.workflowKind == JobWorkflowKind.warranty) {
          final outcome = job.warrantyOutcome ?? WarrantyOutcome.pending;

          // A normal pending claim has no customer invoice. If historical
          // financial evidence does exist, it is never hidden: the generic
          // invoice chip below remains authoritative and opens the document.
          if (outcome == WarrantyOutcome.pending &&
              job.invoiceId == null &&
              !job.isInvoiced) {
            return Tooltip(
              message:
                  'La garantía sigue en evaluación. Todavía no existe un cobro para el cliente.',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.35),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.manage_search_outlined,
                        size: 13, color: Colors.orange),
                    SizedBox(width: 4),
                    Text(
                      'EN EVALUACIÓN',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // A covered claim must be backed by the internal zero-customer-value
          // document created by the warranty command. Never offer the generic
          // customer-invoice path when that invariant is missing.
          if (outcome == WarrantyOutcome.covered && job.invoiceId == null) {
            return Tooltip(
              message:
                  'Falta el respaldo interno de esta garantía. Abre el trabajo para revisar la decisión.',
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => _openJobEditor(job),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 13, color: Colors.red),
                      SizedBox(width: 4),
                      Text(
                        'REVISAR RESPALDO',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          // A rejected claim is billable. If a historical row has no invoice,
          // the only repair exposed here is the guarded workshop RPC below.
          if (outcome == WarrantyOutcome.notCovered &&
              job.invoiceId == null &&
              !job.isInvoiced) {
            return _buildInteractiveTableField(
              onTap: () => _createInvoiceForJob(job),
              accentColor: Colors.red.shade700,
              padding: EdgeInsets.zero,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.red.withValues(alpha: 0.35),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long_outlined,
                        size: 13, color: Colors.red),
                    SizedBox(width: 4),
                    Text(
                      'GENERAR COBRO',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        }

        if (job.invoiceId == null && !job.isInvoiced) {
          if (job.modeNeedsReview) {
            return _buildInteractiveTableField(
              onTap: () => _classifyJobIntake(job),
              accentColor: Colors.orange.shade800,
              padding: EdgeInsets.zero,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.35),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.rule_folder_outlined,
                        size: 13, color: Colors.orange),
                    SizedBox(width: 4),
                    Text(
                      'REVISAR MODO',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // Warranty job: show its operational meaning instead of a generic
          // invoice action. The pending/covered branches above handle the
          // normal cases; this fallback is only for legacy incomplete rows.
          if (job.workflowKind == JobWorkflowKind.warranty) {
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

          // Non-posting proposal: its document noun depends on whether a
          // bicycle is already in workshop custody.
          if (job.isQuotationWorkflow) {
            final badgeColor = _proposalStatusColor(job);
            final isGenerating =
                job.id != null && _generatingQuotationPdfIds.contains(job.id);
            final isConverting = job.id != null &&
                _pendingQuotationConversionAttempts.containsKey(job.id);
            final canConvertApprovedProposal =
                job.effectiveQuotationStatus == QuotationStatus.approved;
            final isBusy = isGenerating || isConverting;
            final proposalChip = SizedBox(
              width: 84,
              height: 24,
              child: Container(
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: badgeColor.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          button: true,
                          excludeSemantics: true,
                          label:
                              'Ver productos y servicios de ${job.proposalDocumentLabelLower}',
                          child: Tooltip(
                            excludeFromSemantics: true,
                            message:
                                'Ver productos y servicios de ${job.proposalDocumentLabelLower}',
                            child: InkWell(
                              onTap: isBusy
                                  ? null
                                  : () => unawaited(
                                        _openJobProductsAndServices(job),
                                      ),
                              borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(5),
                              ),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: isBusy
                                    ? Center(
                                        child: SizedBox(
                                          width: 13,
                                          height: 13,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.8,
                                            color: badgeColor,
                                          ),
                                        ),
                                      )
                                    : FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          job.proposalDocumentLabel,
                                          maxLines: 1,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: badgeColor,
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 20,
                        color: badgeColor.withValues(alpha: 0.24),
                      ),
                      Semantics(
                        button: true,
                        excludeSemantics: true,
                        label:
                            'Descargar o ver más acciones de ${job.proposalDocumentLabelLower}',
                        child: Tooltip(
                          excludeFromSemantics: true,
                          message: 'Descargar / más',
                          waitDuration: const Duration(milliseconds: 800),
                          preferBelow: false,
                          child: PopupMenuButton<String>(
                            enabled: !isBusy,
                            tooltip: '',
                            position: PopupMenuPosition.under,
                            padding: EdgeInsets.zero,
                            onSelected: (action) {
                              switch (action) {
                                case 'download_proposal':
                                  unawaited(_downloadQuotationPdf(job));
                                  break;
                                case 'convert_proposal':
                                  unawaited(_convertToService(job));
                                  break;
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'download_proposal',
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.picture_as_pdf_outlined,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Descargar ${job.proposalDocumentLabelLower}',
                                    ),
                                  ],
                                ),
                              ),
                              if (canConvertApprovedProposal)
                                PopupMenuItem(
                                  value: 'convert_proposal',
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.receipt_long_outlined,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        job.isServiceBudget
                                            ? 'Facturar presupuesto'
                                            : 'Facturar o convertir cotización',
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                            child: SizedBox(
                              width: 22,
                              height: 24,
                              child: Center(
                                child: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 18,
                                  color: isBusy
                                      ? badgeColor.withValues(alpha: 0.45)
                                      : badgeColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            return proposalChip;
          }

          return _buildInteractiveTableField(
            onTap: () => _createInvoiceForJob(job),
            accentColor: Theme.of(context).colorScheme.primary,
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.circular(6),
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
        final status = invoice?.status ??
            (job.isPaid ? InvoiceStatus.paid : InvoiceStatus.draft);

        // An invoice status is a MEANING, not a colour. Asking the theme for
        // the tone is what makes the chip invert between light and dark
        // (pale fill + dark ink → dark fill + light ink) instead of keeping a
        // light-mode pastel glowing on a dark table.
        //
        // The six states stay tellable apart without borrowing the preset
        // accent — which must never recolour a semantic chip — by pairing five
        // tones with one emphasis step: `paid` is the only filled chip,
        // because it is the only terminal good outcome.
        final roles = VinabikeThemeRoles.of(context);
        final VinabikeSemanticTone tone;
        final bool filled;
        IconData icon;
        String label;

        switch (status) {
          case InvoiceStatus.draft:
            tone = roles.neutral;
            filled = false;
            icon = Icons.edit_note;
            label = 'BORRADOR';
            break;
          case InvoiceStatus.sent:
            tone = roles.info;
            filled = false;
            icon = Icons.send;
            label = 'ENVIADO';
            break;
          case InvoiceStatus.confirmed:
            tone = roles.success;
            filled = false;
            icon = Icons.check_circle_outline;
            label = 'CONFIRMADO';
            break;
          case InvoiceStatus.paid:
            tone = roles.success;
            filled = true;
            icon = Icons.check_circle;
            label = 'PAGADO';
            break;
          case InvoiceStatus.overdue:
            tone = roles.warning;
            filled = false;
            icon = Icons.schedule;
            label = 'VENCIDO';
            break;
          case InvoiceStatus.cancelled:
            tone = roles.danger;
            filled = false;
            icon = Icons.cancel;
            label = 'CANCELADO';
            break;
        }

        final Color bgColor = filled ? tone.accent : tone.container;
        final Color borderColor = filled ? tone.accent : tone.border;
        final Color textColor = filled ? tone.onAccent : tone.onContainer;

        final canOpenInvoice =
            job.invoiceId != null && job.invoiceId!.isNotEmpty;

        return _buildInteractiveTableField(
          onTap: canOpenInvoice ? () => _openInvoice(job.invoiceId!) : null,
          accentColor: textColor,
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(7),
          onSecondaryTapDown: canOpenInvoice
              ? (details) => _showInvoiceChipContextMenu(
                    details: details,
                    job: job,
                    invoice: invoice,
                  )
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            constraints: const BoxConstraints(maxWidth: 110),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(7),
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
        // Every slot here used a fixed grey ramp, so the empty "+" tile stayed
        // near-white on a dark row. The neutral tone carries its own pair per
        // brightness, and the drop highlight uses the preset accent instead of
        // a literal blue that ignored the palette.
        final attachRoles = VinabikeThemeRoles.of(context);
        final attachTone = attachRoles.neutral;
        final dropAccent = Theme.of(context).colorScheme.primary;

        return DropTarget(
          onDragDone: (details) => _handleDrop(job, details),
          onDragEntered: (_) => setState(() => _draggingJobId = job.id),
          onDragExited: (_) => setState(() {
            if (_draggingJobId == job.id) _draggingJobId = null;
          }),
          child: _buildInteractiveTableField(
            onTap: () => _pickFileForJob(job),
            padding: const EdgeInsets.all(2),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              decoration: isDroppingOnThis
                  ? BoxDecoration(
                      color: dropAccent.withValues(alpha: 0.2),
                      border: Border.all(color: dropAccent, width: 2),
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
                                color: attachTone.container,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: attachTone.border),
                              ),
                              child: Icon(Icons.insert_drive_file,
                                  size: 16, color: attachTone.onContainer),
                            ),
                      if (count > 1) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: attachTone.container,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '+${count - 1}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: attachTone.onContainer,
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
                              color: attachTone.border,
                              style: BorderStyle.solid),
                          borderRadius: BorderRadius.circular(4),
                          color: attachTone.container,
                        ),
                        child: Center(
                          child: Icon(Icons.add,
                              size: 16,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              ), // ConstrainedBox
            ),
          ),
        );

      case 'actions':
        if (job.deletedAt != null) {
          return PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 16),
            padding: EdgeInsets.zero,
            tooltip: '',
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'restore',
                child: Row(
                  children: [
                    Icon(Icons.restore, size: 18),
                    SizedBox(width: 8),
                    Text('Restaurar'),
                  ],
                ),
              ),
            ],
            onSelected: (value) async {
              if (value != 'restore') return;
              await Future<void>.delayed(Duration.zero);
              if (mounted) await _confirmRestore(job);
            },
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, size: 16),
              onPressed: () => _openJobEditor(job),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
            ),
            PopupMenuButton(
              icon: const Icon(Icons.more_vert, size: 16),
              padding: EdgeInsets.zero,
              tooltip: '',
              iconSize: 16,
              itemBuilder: (context) => [
                if (job.modeNeedsReview)
                  const PopupMenuItem(
                    value: 'classify_intake',
                    child: Row(
                      children: [
                        Icon(Icons.rule_folder_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Clasificar recepción'),
                      ],
                    ),
                  ),
                if (job.isQuotationWorkflow)
                  PopupMenuItem(
                    value: 'quotation_pdf',
                    child: Row(
                      children: [
                        const Icon(Icons.picture_as_pdf_outlined, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Descargar ${job.proposalDocumentLabelLower}',
                        ),
                      ],
                    ),
                  ),
                if (job.isQuotationWorkflow)
                  PopupMenuItem(
                    value: 'quotation_status',
                    child: Row(
                      children: [
                        const Icon(Icons.fact_check_outlined, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            job.effectiveQuotationStatus ==
                                    QuotationStatus.pending
                                ? 'Aprobar o rechazar ${job.proposalDocumentLabelLower}'
                                : 'Gestionar ${job.proposalDocumentLabelLower}',
                          ),
                        ),
                      ],
                    ),
                  ),
                if (job.isQuotationWorkflow &&
                    job.effectiveQuotationStatus == QuotationStatus.approved)
                  PopupMenuItem(
                    value: 'convert',
                    child: Row(
                      children: [
                        const Icon(Icons.transform, size: 18),
                        const SizedBox(width: 8),
                        Text(job.isServiceBudget
                            ? 'Facturar presupuesto'
                            : 'Convertir cotización'),
                      ],
                    ),
                  ),
                if (job.isSaleWorkflow &&
                    job.invoiceId != null &&
                    !_isSaleFullyPaid(job))
                  const PopupMenuItem(
                    value: 'register_payment',
                    child: Row(
                      children: [
                        Icon(Icons.payments_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Registrar abono'),
                      ],
                    ),
                  ),
                if (job.isSaleWorkflow && job.invoiceId != null)
                  const PopupMenuItem(
                    value: 'view_invoice',
                    child: Row(
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Ver factura'),
                      ],
                    ),
                  ),
                if (_usesOperationalLifecycle(job))
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
              onSelected: (value) async {
                if (value == 'classify_intake') {
                  _classifyJobIntake(job);
                } else if (value == 'quotation_pdf') {
                  _downloadQuotationPdf(job);
                } else if (value == 'quotation_status') {
                  _showStatusMenu(job);
                } else if (value == 'convert') {
                  _convertToService(job);
                } else if (value == 'register_payment' &&
                    job.invoiceId != null) {
                  _registerInvoicePayment(job.invoiceId!);
                } else if (value == 'view_invoice' && job.invoiceId != null) {
                  _openInvoice(job.invoiceId!);
                } else if (value == 'complete') {
                  _markJobAsComplete(job);
                } else if (value == 'delete') {
                  await Future<void>.delayed(Duration.zero);
                  if (mounted) await _confirmDelete(job);
                }
              },
            ),
          ],
        );

      default:
        return const Text('-');
    }
  }

  Widget _buildSaleProductSummary(MechanicJob job) {
    final items = _jobItemsMap[job.id] ?? const <MechanicJobItem>[];
    if (items.isEmpty) {
      return Text(
        'Productos no disponibles',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        overflow: TextOverflow.ellipsis,
      );
    }
    final first = items.first;
    final quantity = first.quantity == first.quantity.roundToDouble()
        ? first.quantity.toStringAsFixed(0)
        : first.quantity.toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '${first.productName} ×$quantity${items.length > 1 ? '  +${items.length - 1}' : ''}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (job.notes?.trim().isNotEmpty == true)
          Text(
            job.notes!.trim(),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  Widget _buildJobBikeSubRow({
    required MechanicJob job,
    required Customer? customer,
    required MechanicJobBike jb,
    required int index,
    required int total,
    required double tableWidth,
  }) {
    final theme = Theme.of(context);
    // Get the bike for this job-bike entry
    final bike = _bikes[jb.bikeId] ?? jb.bike;
    final isSelected = _selectedJob?.id == job.id;

    // Use the EXACT same row structure as main row but with distinct background
    return Container(
      width: tableWidth,
      height: 60,
      decoration: BoxDecoration(
        color: isSelected
            ? Color.alphaBlend(
                theme.colorScheme.primary.withValues(alpha: 0.08),
                theme.colorScheme.surface,
              )
            : theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        // Use the EXACT same _buildDataCell method but with jobBike for per-bike data
        children: _displayColumns.map((col) {
          return _buildDataCell(col, job, customer, bike, null, jobBike: jb);
        }).toList(),
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
                      ? 'Estado · ${_customStatusFilter.length} excluidos'
                      : 'Estado · ${_customStatusFilter.length} elegidos')
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
                      width: 320,
                      constraints: const BoxConstraints(maxHeight: 400),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                            child: WorkshopStatusFilterHeader(
                              excludeMode: _statusFilterExcludeMode,
                              canClear: _customStatusFilter.isNotEmpty,
                              onExcludeModeChanged: (value) {
                                setState(
                                  () => _statusFilterExcludeMode = value,
                                );
                                setDialogState(() {});
                                _applyFiltersAndSort();
                              },
                              onClear: () {
                                setState(() {
                                  _customStatusFilter.clear();
                                  _statusFilterExcludeMode = false;
                                });
                                setDialogState(() {});
                                _applyFiltersAndSort();
                              },
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
                                              _toggleCustomStatusFilter(
                                                statusCode,
                                              );
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
                                                  _toggleCustomStatusFilter(
                                                    status.id!,
                                                  );
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

  Future<void> _classifyJobIntake(MechanicJob job) async {
    final jobId = job.id?.trim();
    if (jobId == null || jobId.isEmpty) return;

    final pendingAttempt = _pendingIntakeClassificationAttempts[jobId];
    if (pendingAttempt != null) {
      await _submitJobIntakeClassification(job, pendingAttempt);
      return;
    }

    List<JobSubject> subjects = const [];
    String? subjectCatalogError;
    try {
      subjects = (await _bikeshopService.getJobSubjects())
          .where(
            (subject) =>
                subject.isActive &&
                subject.id != null &&
                subject.id!.trim().isNotEmpty,
          )
          .toList(growable: false);
    } catch (error) {
      subjectCatalogError =
          'No se pudo cargar el catálogo. Aún puedes describir el componente manualmente.';
      debugPrint('Error loading intake subjects: $error');
    }
    if (!mounted) return;

    final customerBikes = _bikes.values
        .where(
          (bike) =>
              bike.id != null &&
              bike.isActive &&
              bike.customerId == job.customerId,
        )
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final customerBikeIds = customerBikes.map((bike) => bike.id).toSet();
    final activeSubjectIds = subjects.map((subject) => subject.id).toSet();

    var intakeKind = job.intakeKind == JobIntakeKind.component ||
            (job.subjectId != null && job.bikeId == null)
        ? JobIntakeKind.component
        : JobIntakeKind.bike;
    String? selectedBikeId =
        customerBikeIds.contains(job.bikeId) ? job.bikeId : null;
    String? selectedSubjectId =
        activeSubjectIds.contains(job.subjectId) ? job.subjectId : null;
    const descriptionSubjectValue = '__description__';
    var subjectSelection = selectedSubjectId ?? descriptionSubjectValue;
    String? validationMessage;
    final subjectNotesController = TextEditingController(
      text: job.subjectNotes?.trim() ?? '',
    );
    final reasonController = TextEditingController();

    final choice = await showDialog<_JobIntakeClassificationChoice>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: const Icon(Icons.rule_folder_outlined, size: 26),
          title: const Text('Clasificar recepción'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Confirma qué dejó físicamente el cliente en ${job.jobNumber ?? 'este trabajo'}. Esto no cambia precios, productos ni estado.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (job.modeReviewReason?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.30),
                        ),
                      ),
                      child: Text(
                        job.modeReviewReason!.trim(),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SegmentedButton<JobIntakeKind>(
                    segments: const [
                      ButtonSegment(
                        value: JobIntakeKind.bike,
                        icon: Icon(Icons.pedal_bike_outlined),
                        label: Text('Bicicleta completa'),
                      ),
                      ButtonSegment(
                        value: JobIntakeKind.component,
                        icon: Icon(Icons.build_circle_outlined),
                        label: Text('Solo componente'),
                      ),
                      ButtonSegment(
                        value: JobIntakeKind.none,
                        icon: Icon(Icons.shopping_bag_outlined),
                        label: Text('Venta / cobro'),
                      ),
                    ],
                    selected: {intakeKind},
                    onSelectionChanged: (selection) => setDialogState(() {
                      intakeKind = selection.first;
                      validationMessage = null;
                    }),
                  ),
                  const SizedBox(height: 16),
                  if (intakeKind == JobIntakeKind.bike) ...[
                    DropdownButtonFormField<String>(
                      initialValue: selectedBikeId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Bicicleta recibida *',
                        border: OutlineInputBorder(),
                      ),
                      hint: const Text('Selecciona una bicicleta del cliente'),
                      items: customerBikes
                          .map(
                            (bike) => DropdownMenuItem<String>(
                              value: bike.id!,
                              child: Text(
                                bike.displayName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: customerBikes.isEmpty
                          ? null
                          : (value) => setDialogState(() {
                                selectedBikeId = value;
                                validationMessage = null;
                              }),
                    ),
                    if (customerBikes.isEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Este cliente no tiene bicicletas activas cargadas. Cambia a “Solo componente” o crea la bicicleta desde su ficha antes de clasificar.',
                        style: TextStyle(
                          color: Colors.orange.shade900,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ] else if (intakeKind == JobIntakeKind.component) ...[
                    if (subjectCatalogError != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.30),
                          ),
                        ),
                        child: Text(
                          subjectCatalogError,
                          style: TextStyle(
                            color: Colors.orange.shade900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    DropdownButtonFormField<String>(
                      initialValue: subjectSelection,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de componente',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: descriptionSubjectValue,
                          child: Text('Otro / describir manualmente'),
                        ),
                        ...subjects.map(
                          (subject) => DropdownMenuItem<String>(
                            value: subject.id!,
                            child: Text(
                              subject.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) => setDialogState(() {
                        subjectSelection = value ?? descriptionSubjectValue;
                        selectedSubjectId =
                            value == descriptionSubjectValue ? null : value;
                        validationMessage = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: subjectNotesController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: selectedSubjectId == null
                            ? 'Descripción clara del componente *'
                            : 'Detalle adicional (opcional)',
                        hintText: selectedSubjectId == null
                            ? 'Ej.: rueda trasera 29” con maza Shimano'
                            : 'Ej.: rueda trasera, color negro',
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {
                        validationMessage = null;
                      }),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:
                            Theme.of(context).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Clasifica este registro como una venta de productos '
                        'sin bicicleta ni componente recibido. Sus productos, '
                        'precios y pagos no se modificarán.',
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Motivo de clasificación (opcional)',
                      hintText: 'Ej.: confirmado con el cliente',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (validationMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      validationMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
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
            FilledButton(
              onPressed: () {
                final subjectNotes = subjectNotesController.text.trim();
                if (intakeKind == JobIntakeKind.bike &&
                    selectedBikeId == null) {
                  setDialogState(() {
                    validationMessage =
                        'Selecciona la bicicleta completa que quedó en el taller.';
                  });
                  return;
                }
                if (intakeKind == JobIntakeKind.component &&
                    selectedSubjectId == null &&
                    subjectNotes.isEmpty) {
                  setDialogState(() {
                    validationMessage =
                        'Selecciona un componente o escribe una descripción clara.';
                  });
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  _JobIntakeClassificationChoice(
                    intakeKind: intakeKind,
                    bikeId: intakeKind == JobIntakeKind.bike
                        ? selectedBikeId
                        : null,
                    subjectId: intakeKind == JobIntakeKind.component
                        ? selectedSubjectId
                        : null,
                    subjectNotes: intakeKind == JobIntakeKind.component &&
                            subjectNotes.isNotEmpty
                        ? subjectNotes
                        : null,
                    reason: reasonController.text.trim().isEmpty
                        ? null
                        : reasonController.text.trim(),
                  ),
                );
              },
              child: const Text('Guardar clasificación'),
            ),
          ],
        ),
      ),
    );
    subjectNotesController.dispose();
    reasonController.dispose();

    if (!mounted || choice == null) return;
    final attempt = _PendingJobIntakeClassificationAttempt(
      choice: choice,
      operationKey: const Uuid().v4(),
    );
    _pendingIntakeClassificationAttempts[jobId] = attempt;
    await _submitJobIntakeClassification(job, attempt);
  }

  Future<void> _submitJobIntakeClassification(
    MechanicJob job,
    _PendingJobIntakeClassificationAttempt attempt,
  ) async {
    final jobId = job.id?.trim();
    if (jobId == null || jobId.isEmpty) return;
    final choice = attempt.choice;

    _startLocalOperation();
    try {
      final bool resultNeedsRefresh;
      if (choice.intakeKind == JobIntakeKind.none) {
        final result = await _bikeshopService.classifyMechanicJobAsSale(
          jobId,
          operationKey: attempt.operationKey,
          reason: choice.reason,
        );
        resultNeedsRefresh = result.needsRefresh;
      } else {
        final result = await _bikeshopService.classifyMechanicJobIntake(
          jobId,
          intakeKind: choice.intakeKind,
          operationKey: attempt.operationKey,
          bikeId: choice.bikeId,
          subjectId: choice.subjectId,
          subjectNotes: choice.subjectNotes,
          reason: choice.reason,
        );
        resultNeedsRefresh = result.needsRefresh;
      }
      _pendingIntakeClassificationAttempts.remove(jobId);

      Object? refreshError;
      try {
        await _loadData(
          surfaceErrors: false,
          rethrowErrors: true,
        );
      } catch (error) {
        refreshError = error;
        debugPrint(
          'Classification was confirmed but the jobs table did not refresh: $error',
        );
      }
      if (!mounted) return;
      final classificationLabel = switch (choice.intakeKind) {
        JobIntakeKind.bike => 'bicicleta completa',
        JobIntakeKind.component => 'solo componente',
        JobIntakeKind.none => 'venta / cobro',
        JobIntakeKind.unspecified => 'clasificación pendiente',
      };
      final refreshPending = resultNeedsRefresh || refreshError != null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            refreshPending
                ? 'El servidor confirmó ${job.jobNumber ?? 'el trabajo'} como $classificationLabel, pero la tabla no pudo actualizarse. Usa Actualizar para leer el resultado guardado.'
                : '${job.jobNumber ?? 'Trabajo'} clasificado como $classificationLabel.',
          ),
          backgroundColor:
              refreshPending ? Colors.orange.shade800 : Colors.green.shade700,
          duration: Duration(seconds: refreshPending ? 9 : 4),
          action: refreshPending
              ? SnackBarAction(
                  label: 'ACTUALIZAR',
                  textColor: Colors.white,
                  onPressed: () => unawaited(_loadData()),
                )
              : null,
        ),
      );
    } on MechanicJobIntakeClassificationOutcomeUnknown catch (error) {
      debugPrint(
        'Classification outcome remains unknown for $jobId with operation '
        '${attempt.operationKey}: command=${error.commandError}; '
        'readback=${error.readbackError}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'No se pudo confirmar el resultado. La clasificación puede haberse guardado; Reintentar reutiliza exactamente la misma operación y no crea otra.',
            ),
            backgroundColor: Colors.orange.shade900,
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'REINTENTAR',
              textColor: Colors.white,
              onPressed: () => unawaited(
                _submitJobIntakeClassification(job, attempt),
              ),
            ),
          ),
        );
      }
    } on MechanicJobSaleClassificationOutcomeUnknown catch (error) {
      debugPrint(
        'Sale classification outcome remains unknown for $jobId with operation '
        '${attempt.operationKey}: command=${error.commandError}; '
        'readback=${error.readbackError}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'No se pudo confirmar el resultado. La venta puede haberse guardado; Reintentar reutiliza exactamente la misma operación y no crea otra.',
            ),
            backgroundColor: Colors.orange.shade900,
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'REINTENTAR',
              textColor: Colors.white,
              onPressed: () => unawaited(
                _submitJobIntakeClassification(job, attempt),
              ),
            ),
          ),
        );
      }
    } catch (error) {
      _pendingIntakeClassificationAttempts.remove(jobId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'El servidor no aceptó la clasificación. Revisa los datos e inténtalo nuevamente: $error',
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      _endLocalOperation();
    }
  }

  Future<void> _createInvoiceForJob(MechanicJob job) async {
    final jobId = job.id;
    if (jobId == null || jobId.isEmpty) return;
    if (job.isQuotationWorkflow) {
      final action = job.isServiceBudget
          ? 'aprueba y usa “Facturar presupuesto”'
          : 'aprueba y usa “Convertir cotización”';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${job.proposalDocumentLabel} todavía no es una factura: $action.',
          ),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      return;
    }

    _startLocalOperation();
    try {
      // This server-side entrypoint owns the job/invoice link and refuses
      // quotations, unresolved intake and undecided warranties. Opening the
      // generic invoice editor here would allow those domain guards to be
      // bypassed.
      final invoiceId = await _bikeshopService.createInvoiceFromJob(jobId);
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Factura del trabajo creada correctamente'),
          backgroundColor: Colors.green.shade700,
          action: SnackBarAction(
            label: 'Abrir factura',
            textColor: Colors.white,
            onPressed: () => _openInvoice(invoiceId),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo generar la factura: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      _endLocalOperation();
    }
  }

  Future<void> _downloadQuotationPdf(MechanicJob job) async {
    final jobId = job.id;
    if (jobId == null ||
        jobId.isEmpty ||
        !job.isQuotationWorkflow ||
        _generatingQuotationPdfIds.contains(jobId)) {
      return;
    }

    setState(() => _generatingQuotationPdfIds.add(jobId));
    try {
      final artifact = await _buildQuotationPdfArtifact(job);
      await _exportQuotationPdfArtifact(artifact);
    } catch (error) {
      if (mounted) {
        final article = job.isServiceBudget ? 'el' : 'la';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se pudo generar $article ${job.proposalDocumentLabelLower} en PDF: $error',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _generatingQuotationPdfIds.remove(jobId));
      }
    }
  }

  Future<_WorkshopProposalPdfArtifact> _buildQuotationPdfArtifact(
    MechanicJob job,
  ) async {
    final jobId = job.id;
    if (jobId == null || jobId.isEmpty || !job.isQuotationWorkflow) {
      throw StateError('El trabajo no tiene un documento de propuesta.');
    }

    final pdfContext = context;
    final customer = _customers[job.customerId];
    final jobItems = await _bikeshopService.getJobItems(jobId);
    if (!pdfContext.mounted) {
      throw StateError('La vista de trabajos ya no está disponible.');
    }
    final invoiceItems = jobItems
        .map(
          (item) => InvoiceItem(
            id: item.id,
            productId: item.productId ?? item.serviceProductId,
            productName: item.productName,
            productSku: item.productSku,
            description: item.notes,
            isCatalogProduct:
                item.productId != null || item.serviceProductId != null,
            quantity: item.quantity,
            unitPrice: item.unitPrice,
            lineTotal: item.totalPrice,
            isService: item.itemType == 'service',
            jobBikeId: item.jobBikeId,
          ),
        )
        .toList(growable: false);
    final gross = invoiceItems.fold<double>(
      0,
      (sum, item) => sum + item.lineTotal,
    );
    final total = (gross - job.discountAmount).clamp(0, double.infinity);
    final documentNumber = (job.jobNumber?.trim().isNotEmpty ?? false)
        ? job.jobNumber!.trim()
        : jobId;
    final proposal = Invoice(
      tenantId: job.tenantId,
      customerId: customer?.id,
      invoiceNumber: documentNumber,
      customerName: customer?.name ?? 'Cliente',
      customerRut: customer?.rut,
      date: job.createdAt,
      dueDate: job.quotationValidUntil,
      reference: job.subjectDisplayName,
      subtotal: gross,
      total: total.toDouble(),
      balance: 0,
      bikeId: job.isServiceBudget ? job.bikeId : null,
      items: invoiceItems,
      invoiceType: job.isServiceBudget ? 'service_budget' : 'quotation',
      jobNumber: job.jobNumber,
      entryDate: job.arrivalDate,
      workDescription: job.subjectDisplayName,
      source: null,
    );
    final resolvedBikeNames = <String, String>{};
    if (job.isServiceBudget) {
      final jobBikes = _jobBikesMap[jobId] ?? const <MechanicJobBike>[];
      for (final jobBike in jobBikes) {
        final bike = jobBike.bike ?? _bikes[jobBike.bikeId];
        final jobBikeId = jobBike.id?.trim();
        if (bike != null && jobBikeId != null && jobBikeId.isNotEmpty) {
          resolvedBikeNames[jobBikeId] = bike.displayName;
        }
      }
      final primaryBike = job.bikeId == null ? null : _bikes[job.bikeId];
      if (primaryBike != null) {
        resolvedBikeNames['single'] = primaryBike.displayName;
      }
    }
    if (!pdfContext.mounted) {
      throw StateError('La vista de trabajos ya no está disponible.');
    }

    final pdfFuture = job.isServiceBudget
        ? InvoicePdfGenerator.generateServiceBudgetPDF(
            pdfContext,
            proposal,
            resolvedBikeNames,
            validUntil: job.quotationValidUntil,
            discountAmount: job.discountAmount,
          )
        : InvoicePdfGenerator.generateQuotationPDF(
            pdfContext,
            proposal,
            const <String, String>{},
            validUntil: job.quotationValidUntil,
            discountAmount: job.discountAmount,
          );
    final pdf = await pdfFuture;
    final bytes = await pdf.save();
    final fileName = job.isServiceBudget
        ? InvoicePdfGenerator.serviceBudgetFileNameFor(documentNumber)
        : InvoicePdfGenerator.quotationFileNameFor(documentNumber);

    return _WorkshopProposalPdfArtifact(
      bytes: bytes,
      fileName: fileName,
      documentLabel: job.proposalDocumentLabel,
    );
  }

  Future<void> _exportQuotationPdfArtifact(
    _WorkshopProposalPdfArtifact artifact,
  ) async {
    if (!kIsWeb &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      final outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar ${artifact.documentLabel} PDF',
        fileName: artifact.fileName,
        initialDirectory:
            await InvoicePdfGenerator.resolveDefaultSaveDirectory(),
        allowedExtensions: const ['pdf'],
        type: FileType.custom,
      );
      if (outputFile != null) {
        await File(outputFile).writeAsBytes(artifact.bytes);
      }
    } else {
      await Printing.sharePdf(
        bytes: artifact.bytes,
        filename: artifact.fileName,
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${artifact.documentLabel} PDF generado correctamente',
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _convertToService(MechanicJob job) async {
    final jobId = job.id;
    if (jobId == null || jobId.isEmpty) return;
    _clearQuotationSnackBars();

    if (job.isQuotationWorkflow &&
        job.effectiveQuotationStatus != QuotationStatus.approved) {
      final article = job.isServiceBudget ? 'el' : 'la';
      _showReplacingQuotationSnackBar(
        SnackBar(
          content: Text(
            'Primero aprueba $article ${job.proposalDocumentLabelLower} desde la acción de estado.',
          ),
        ),
      );
      return;
    }

    if (job.isServiceBudget) {
      await _confirmServiceBudgetConversion(job);
      return;
    }

    List<MechanicJobItem> conversionItems =
        _jobItemsMap[jobId] ?? const <MechanicJobItem>[];
    if (conversionItems.isEmpty) {
      try {
        conversionItems = await _bikeshopService.getJobItems(jobId);
      } catch (error) {
        debugPrint('Error loading quotation items for conversion: $error');
      }
    }
    final canConvertAsSale = conversionItems.isNotEmpty &&
        conversionItems.every(
          (item) => item.itemType == 'product' && item.productId != null,
        );

    List<JobSubject> subjects = const [];
    String? subjectCatalogError;
    try {
      subjects = (await _bikeshopService.getJobSubjects())
          .where(
            (subject) =>
                subject.isActive &&
                subject.id != null &&
                subject.id!.trim().isNotEmpty,
          )
          .toList(growable: false)
        ..sort((a, b) => a.name.compareTo(b.name));
    } catch (error) {
      subjectCatalogError =
          'No se pudo cargar el catálogo de componentes. Puedes continuar con una bicicleta o con la descripción manual ya guardada en la cotización; de lo contrario, cancela y vuelve a intentar.';
      debugPrint('Error loading conversion subjects: $error');
    }
    if (!mounted) return;
    final customerBikes = _bikes.values
        .where(
          (bike) =>
              bike.customerId == job.customerId &&
              bike.isActive &&
              bike.id != null &&
              bike.id!.trim().isNotEmpty,
        )
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final customerBikeIds = customerBikes.map((bike) => bike.id).toSet();
    final activeSubjectIds = subjects.map((subject) => subject.id).toSet();
    final existingSubjectDescription = job.subjectNotes?.trim();
    final hasExistingSubjectDescription =
        job.subjectId == null && existingSubjectDescription?.isNotEmpty == true;
    const existingDescriptionSubjectValue = '__existing_description__';
    String? selectedBikeId =
        customerBikeIds.contains(job.bikeId) ? job.bikeId : null;
    String? selectedSubjectId =
        activeSubjectIds.contains(job.subjectId) ? job.subjectId : null;
    String? subjectSelection = selectedSubjectId ??
        (hasExistingSubjectDescription
            ? existingDescriptionSubjectValue
            : null);
    var targetType = canConvertAsSale
        ? JobType.sale
        : selectedSubjectId != null || hasExistingSubjectDescription
            ? JobType.itemService
            : JobType.service;
    String? validationMessage;
    final reasonController = TextEditingController();
    const sourceLabel = 'cotización';

    final choice = await showDialog<_JobConversionChoice>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: const Icon(Icons.transform, size: 28),
          title: const Text('Convertir a trabajo cobrable'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${job.jobNumber} conservará el historial del $sourceLabel y generará una sola factura en la misma operación.',
                  ),
                  if (subjectCatalogError != null &&
                      targetType != JobType.sale) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.30),
                        ),
                      ),
                      child: Text(
                        subjectCatalogError,
                        style: TextStyle(
                          color: Colors.orange.shade900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text('¿Cómo continúa la cotización aprobada?',
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  SegmentedButton<JobType>(
                    segments: [
                      ButtonSegment(
                        value: JobType.sale,
                        icon: const Icon(Icons.shopping_bag_outlined),
                        label: const Text('Venta'),
                        enabled: canConvertAsSale,
                      ),
                      const ButtonSegment(
                        value: JobType.service,
                        icon: Icon(Icons.pedal_bike_outlined),
                        label: Text('Bicicleta'),
                      ),
                      const ButtonSegment(
                        value: JobType.itemService,
                        icon: Icon(Icons.build_circle_outlined),
                        label: Text('Componente'),
                      ),
                    ],
                    selected: {targetType},
                    onSelectionChanged: (selection) => setDialogState(() {
                      targetType = selection.first;
                      validationMessage = null;
                    }),
                  ),
                  if (!canConvertAsSale) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Venta se habilita cuando todas las líneas son productos de catálogo y no hay servicios.',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (targetType == JobType.sale) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF047857).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color:
                              const Color(0xFF047857).withValues(alpha: 0.25),
                        ),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 18,
                            color: Color(0xFF047857),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'No se recibirá bicicleta ni componente. Los productos pasarán a una factura de venta vinculada y la factura será la única dueña del inventario, impuestos y contabilidad.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (targetType == JobType.service) ...[
                    DropdownButtonFormField<String>(
                      key: ValueKey('conversion-bike-$selectedBikeId'),
                      initialValue: selectedBikeId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Bicicleta recibida *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.pedal_bike_outlined),
                      ),
                      items: customerBikes
                          .map((bike) => DropdownMenuItem(
                                value: bike.id!,
                                child: Text(
                                  bike.displayName,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: customerBikes.isEmpty
                          ? null
                          : (value) => setDialogState(() {
                                selectedBikeId = value;
                                validationMessage = null;
                              }),
                    ),
                    if (customerBikes.isEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Este cliente no tiene bicicletas activas disponibles. Crea una nueva bicicleta o elige Componente.',
                        style: TextStyle(
                          color: Colors.orange.shade900,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => Navigator.pop(
                          dialogContext,
                          const _JobConversionChoice(
                            targetType: JobType.service,
                            createBike: true,
                          ),
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('Crear nueva bicicleta'),
                      ),
                    ),
                  ] else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<String>(
                          key: ValueKey(
                            'conversion-subject-$subjectSelection',
                          ),
                          initialValue: subjectSelection,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Componente recibido *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.build_circle_outlined),
                          ),
                          hint: const Text('Selecciona un componente'),
                          items: [
                            if (hasExistingSubjectDescription)
                              DropdownMenuItem(
                                value: existingDescriptionSubjectValue,
                                child: Text(
                                  'Usar descripción: $existingSubjectDescription',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ...subjects.map(
                              (subject) => DropdownMenuItem<String>(
                                value: subject.id!,
                                child: Text(
                                  subject.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: subjects.isEmpty &&
                                  !hasExistingSubjectDescription
                              ? null
                              : (value) => setDialogState(() {
                                    subjectSelection = value;
                                    selectedSubjectId =
                                        value == existingDescriptionSubjectValue
                                            ? null
                                            : value;
                                    validationMessage = null;
                                  }),
                        ),
                        if (subjects.isEmpty &&
                            !hasExistingSubjectDescription) ...[
                          const SizedBox(height: 8),
                          Text(
                            subjectCatalogError != null
                                ? 'No es seguro convertir como componente sin catálogo ni una descripción ya guardada.'
                                : 'No hay componentes activos disponibles y esta cotización no tiene una descripción manual utilizable.',
                            style: TextStyle(
                              color: Colors.orange.shade900,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  if (job.jobType == JobType.warranty ||
                      job.effectiveQuotationStatus ==
                          QuotationStatus.rejected ||
                      job.effectiveQuotationStatus ==
                          QuotationStatus.expired) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: reasonController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Motivo de la conversión *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  if (validationMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      validationMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.verified_outlined,
                          size: 16, color: Color(0xFF047857)),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          targetType == JobType.sale
                              ? 'La venta, su evento de auditoría y la factura vinculada se guardan juntos. Si algo falla, no se aplica nada.'
                              : 'La conversión, el vínculo físico, el evento de auditoría y la factura se guardan juntos. Si algo falla, no se aplica nada.',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () {
                final needsReason = job.jobType == JobType.warranty ||
                    job.effectiveQuotationStatus == QuotationStatus.rejected ||
                    job.effectiveQuotationStatus == QuotationStatus.expired;
                if (targetType == JobType.service && selectedBikeId == null) {
                  setDialogState(() => validationMessage =
                      'Selecciona o crea la bicicleta que quedó en el taller.');
                  return;
                }
                if (targetType == JobType.itemService &&
                    selectedSubjectId == null &&
                    !(subjectSelection == existingDescriptionSubjectValue &&
                        hasExistingSubjectDescription)) {
                  setDialogState(() => validationMessage =
                      'Selecciona un componente activo o usa la descripción ya guardada.');
                  return;
                }
                if (needsReason && reasonController.text.trim().isEmpty) {
                  setDialogState(() => validationMessage =
                      'Esta conversión requiere una justificación.');
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  _JobConversionChoice(
                    targetType: targetType,
                    bikeId:
                        targetType == JobType.service ? selectedBikeId : null,
                    subjectId: targetType == JobType.itemService
                        ? selectedSubjectId
                        : null,
                    reason: reasonController.text.trim().isEmpty
                        ? null
                        : reasonController.text.trim(),
                  ),
                );
              },
              icon: Icon(
                targetType == JobType.sale
                    ? Icons.receipt_long_outlined
                    : Icons.transform,
                size: 16,
              ),
              label: Text(
                targetType == JobType.sale
                    ? 'Facturar como venta'
                    : 'Convertir y facturar',
              ),
            ),
          ],
        ),
      ),
    );
    reasonController.dispose();

    if (!mounted || choice == null) return;
    if (choice.createBike) {
      final createdBike = await showDialog<Bike>(
        context: context,
        builder: (context) => BikeFormDialog(customerId: job.customerId),
      );
      if (!mounted || createdBike == null) return;
      if (createdBike.id != null) {
        setState(() => _bikes[createdBike.id!] = createdBike);
      }
      await _convertToService(job);
      return;
    }

    await _startQuotationConversion(job, choice);
  }

  Future<void> _confirmServiceBudgetConversion(MechanicJob job) async {
    final jobId = job.id?.trim();
    if (jobId == null || jobId.isEmpty) return;

    final persistedJobBikes = _jobBikesMap[jobId] ?? const <MechanicJobBike>[];
    final persistedBikeIds = <String>{
      for (final jobBike in persistedJobBikes)
        if (jobBike.bikeId.trim().isNotEmpty) jobBike.bikeId.trim(),
      if (job.bikeId?.trim().isNotEmpty == true) job.bikeId!.trim(),
    };
    if (persistedBikeIds.isEmpty) {
      if (!mounted) return;
      _showReplacingQuotationSnackBar(
        SnackBar(
          content: const Text(
            'Este presupuesto no conserva una bicicleta recibida válida. Actualiza la tabla y revisa el trabajo antes de facturar.',
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    final bikeNames = <String>[];
    for (final bikeId in persistedBikeIds) {
      final jobBike = persistedJobBikes
          .where((candidate) => candidate.bikeId == bikeId)
          .firstOrNull;
      final name = (jobBike?.bike ?? _bikes[bikeId])?.displayName.trim();
      bikeNames.add(
        name == null || name.isEmpty ? 'Bicicleta registrada' : name,
      );
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.receipt_long_outlined, size: 28),
        title: const Text('Facturar presupuesto'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${job.jobNumber ?? 'Este trabajo'} conservará su ficha, diagnóstico y líneas, y creará una sola factura.',
              ),
              const SizedBox(height: 16),
              Text(
                bikeNames.length == 1
                    ? 'Bicicleta recibida'
                    : 'Bicicletas recibidas',
                style: Theme.of(dialogContext).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              ...bikeNames.map(
                (name) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.pedal_bike_outlined, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(name)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'No se cambiará ni se volverá a seleccionar la recepción física.',
                style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                      color:
                          Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Crear factura'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // `bikeId: null` is intentional for this exact canonical source mode: the
    // server preserves every persisted mechanic_job_bikes row and attribution.
    await _startQuotationConversion(
      job,
      const _JobConversionChoice(targetType: JobType.service),
    );
  }

  Future<void> _startQuotationConversion(
    MechanicJob job,
    _JobConversionChoice choice,
  ) async {
    final jobId = job.id?.trim();
    if (jobId == null || jobId.isEmpty) return;
    final existingAttempt = _pendingQuotationConversionAttempts[jobId];
    final attempt = existingAttempt != null && existingAttempt.matches(choice)
        ? existingAttempt
        : _PendingQuotationConversionAttempt(
            choice: choice,
            operationKey: const Uuid().v4(),
          );
    _pendingQuotationConversionAttempts[jobId] = attempt;
    await _submitQuotationConversion(job, attempt);
  }

  Future<void> _submitQuotationConversion(
    MechanicJob job,
    _PendingQuotationConversionAttempt attempt,
  ) async {
    final jobId = job.id?.trim();
    if (jobId == null || jobId.isEmpty) return;
    // A snackbar from an earlier uncertain choice can remain visible after the
    // worker has submitted a different bicycle/component. Never let that stale
    // closure replay the superseded operation and win the conversion race.
    if (!identical(_pendingQuotationConversionAttempts[jobId], attempt)) {
      return;
    }
    final choice = attempt.choice;

    _startLocalOperation();
    try {
      final result = await _bikeshopService.convertToBillableJob(
        jobId,
        targetType: choice.targetType,
        reason: choice.reason,
        bikeId: choice.bikeId,
        subjectId: choice.subjectId,
        operationKey: attempt.operationKey,
      );
      final receiptInvoiceId = result.invoiceId;
      final isSaleConversion = choice.targetType == JobType.sale;
      final convertedBikeId = choice.targetType == JobType.service
          ? job.isServiceBudget
              ? job.bikeId
              : choice.bikeId
          : null;
      var updated = job.copyWith(
        jobType: choice.targetType,
        workflowKind:
            isSaleConversion ? JobWorkflowKind.sale : JobWorkflowKind.service,
        intakeKind: isSaleConversion
            ? JobIntakeKind.none
            : choice.targetType == JobType.itemService
                ? JobIntakeKind.component
                : JobIntakeKind.bike,
        bikeId: convertedBikeId,
        subjectId:
            choice.targetType == JobType.itemService ? choice.subjectId : null,
        quotationStatus: null,
        convertedAt: DateTime.now(),
        modeNeedsReview: false,
        modeReviewReason: null,
        warrantyOutcome: null,
        invoiceId: receiptInvoiceId,
        isInvoiced: receiptInvoiceId == null ? null : true,
        isWarrantyJob: false,
        updatedAt: DateTime.now(),
      );
      if (mounted) {
        setState(() {
          final index = _jobs.indexWhere((candidate) => candidate.id == jobId);
          if (index != -1) _jobs[index] = updated;
          if (_selectedJob?.id == jobId) _selectedJob = updated;
          _applyFiltersAndSort();
        });
      }
      if (identical(
        _pendingQuotationConversionAttempts[jobId],
        attempt,
      )) {
        _pendingQuotationConversionAttempts.remove(jobId);
      }

      Object? refreshError;
      try {
        await _loadData(
          surfaceErrors: false,
          rethrowErrors: true,
          forceInvoiceRefresh: true,
        );
        updated = _jobs.cast<MechanicJob?>().firstWhere(
                  (candidate) => candidate?.id == jobId,
                  orElse: () => updated,
                ) ??
            updated;
      } catch (error) {
        // Conversion, invoice creation and the audit event were already
        // confirmed by one exact receipt. A failed list refresh is only a
        // projection problem and must not be shown as a rejected conversion.
        refreshError = error;
        debugPrint(
          'Quotation conversion ${attempt.operationKey} was confirmed, '
          'but table refresh failed: $error',
        );
      }
      if (!mounted) return;

      final refreshSuffix = refreshError == null
          ? ''
          : ' No se pudo refrescar la tabla; usa Actualizar para releer el cambio guardado.';
      final invoiceId = result.invoiceId ?? updated.invoiceId;
      final successMessage = job.isServiceBudget
          ? '${job.jobNumber} fue facturado conservando su recepción, ficha, diagnóstico y líneas en una sola factura.'
          : isSaleConversion
              ? '${job.jobNumber} se facturó como venta de productos, sin recepción de bicicleta o componente.'
              : '${job.jobNumber} se convirtió a ${choice.targetType == JobType.itemService ? 'componente cobrable' : 'servicio de bicicleta'} con una sola factura.';
      _showReplacingQuotationSnackBar(
        SnackBar(
          content: Text(
            '$successMessage$refreshSuffix',
          ),
          duration: const Duration(seconds: 8),
          backgroundColor: refreshError == null
              ? Colors.green.shade700
              : Colors.orange.shade800,
          action: invoiceId == null
              ? null
              : SnackBarAction(
                  label: 'Abrir factura',
                  textColor: Colors.white,
                  onPressed: () => _openInvoice(invoiceId),
                ),
        ),
      );
    } on MechanicJobQuotationCommandOutcomeUnknown catch (error) {
      debugPrint(
        'Quotation conversion outcome remains unknown for $jobId with '
        'operation ${attempt.operationKey}: $error',
      );
      if (!mounted) return;
      _showReplacingQuotationSnackBar(
        SnackBar(
          content: const Text(
            'No se pudo confirmar la conversión. Puede haberse guardado; Reintentar reutiliza exactamente la misma operación y no crea otra factura.',
          ),
          backgroundColor: Colors.orange.shade900,
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: 'REINTENTAR',
            textColor: Colors.white,
            onPressed: () => unawaited(
              _submitQuotationConversion(job, attempt),
            ),
          ),
        ),
      );
    } catch (error) {
      if (identical(
        _pendingQuotationConversionAttempts[jobId],
        attempt,
      )) {
        _pendingQuotationConversionAttempts.remove(jobId);
      }
      if (!mounted) return;
      _showReplacingQuotationSnackBar(
        SnackBar(
          content: Text(
            'El servidor rechazó la conversión; no se confirmó ningún cambio: $error',
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      _endLocalOperation();
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
      _startLocalOperation();
      try {
        await _bikeshopService.transitionJobStatusByLegacyStatus(
          job.id!,
          JobStatus.finalizado,
          operationKey: const Uuid().v4(),
        );
        await _loadData();
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
    final reason = await _requestArchiveReason(
      job: job,
      restoring: false,
    );
    if (reason == null || !mounted) return;

    _startLocalOperation();
    try {
      await _bikeshopService.softDeleteJob(
        job.id!,
        reason: reason,
        operationKey: const Uuid().v4(),
      );
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${job.jobNumber} se movió a Eliminados con su historial intacto.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      await _loadData(surfaceErrors: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo eliminar el trabajo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      _endLocalOperation();
    }
  }

  Future<void> _confirmRestore(MechanicJob job) async {
    final reason = await _requestArchiveReason(
      job: job,
      restoring: true,
    );
    if (reason == null || !mounted) return;

    _startLocalOperation();
    try {
      await _bikeshopService.restoreJob(
        job.id!,
        reason: reason,
        operationKey: const Uuid().v4(),
      );
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${job.jobNumber} fue restaurado.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      await _loadData(surfaceErrors: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo restaurar el trabajo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      _endLocalOperation();
    }
  }

  Future<String?> _requestArchiveReason({
    required MechanicJob job,
    required bool restoring,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            restoring ? 'Restaurar trabajo' : 'Mover trabajo a eliminados',
          ),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  restoring
                      ? '${job.jobNumber} volverá a los trabajos activos.'
                      : job.invoiceId == null
                          ? '${job.jobNumber} dejará de aparecer entre los trabajos activos. Sus presupuestos, elementos y eventos se conservarán.'
                          : '${job.jobNumber} dejará de aparecer entre los trabajos activos. La factura, pagos, stock y asientos vinculados no serán alterados.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 3,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    labelText: restoring
                        ? 'Motivo de restauración *'
                        : 'Motivo de eliminación *',
                    hintText: restoring
                        ? 'Ej.: Se eliminó por error'
                        : 'Ej.: Trabajo creado para una prueba',
                    border: const OutlineInputBorder(),
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
            FilledButton(
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(
                        dialogContext,
                        controller.text.trim(),
                      ),
              style: restoring
                  ? null
                  : FilledButton.styleFrom(backgroundColor: Colors.red),
              child: Text(restoring ? 'Restaurar' : 'Mover a eliminados'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  // Interactive cell methods
  IconData _priorityIcon(JobPriority priority) {
    return switch (priority) {
      JobPriority.urgente => Icons.priority_high,
      JobPriority.alta => Icons.arrow_upward,
      JobPriority.normal => Icons.drag_handle,
      JobPriority.baja => Icons.arrow_downward,
    };
  }

  Future<void> _showPriorityMenu(
    BuildContext anchorContext,
    MechanicJob job,
  ) async {
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox?;
    final anchor = anchorContext.findRenderObject() as RenderBox?;
    if (overlay == null || anchor == null) return;

    final offset = anchor.localToGlobal(Offset.zero, ancestor: overlay);
    final selectedPriority = await showMenu<JobPriority>(
      context: context,
      position: RelativeRect.fromRect(
        offset & anchor.size,
        Offset.zero & overlay.size,
      ),
      items: JobPriority.values.map((priority) {
        final color = _getPriorityColor(priority);
        return PopupMenuItem<JobPriority>(
          value: priority,
          child: Row(
            children: [
              Icon(_priorityIcon(priority), size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(priority.displayName)),
              if (priority == job.priority)
                Icon(Icons.check, size: 16, color: color),
            ],
          ),
        );
      }).toList(),
    );

    if (!mounted ||
        selectedPriority == null ||
        selectedPriority == job.priority) {
      return;
    }

    await _updateJobPriority(job, selectedPriority);
  }

  Future<void> _updateJobPriority(
    MechanicJob job,
    JobPriority newPriority,
  ) async {
    final jobId = job.id;
    if (jobId == null || jobId.isEmpty) return;

    _startLocalOperation();

    MechanicJob? previousJob;
    late MechanicJob optimisticJob;
    setState(() {
      final index = _jobs.indexWhere((j) => j.id == jobId);
      previousJob = index == -1 ? job : _jobs[index];
      optimisticJob = previousJob!.copyWith(
        priority: newPriority,
        updatedAt: DateTime.now(),
      );

      if (index != -1) {
        _jobs[index] = optimisticJob;
      }
      if (_selectedJob?.id == jobId) {
        _selectedJob = optimisticJob;
      }
      _applyFiltersAndSort();
    });

    try {
      final savedJob = await _bikeshopService.updateJob(optimisticJob);
      if (!mounted) return;
      setState(() {
        final index = _jobs.indexWhere((j) => j.id == jobId);
        if (index != -1) {
          _jobs[index] = savedJob;
        }
        if (_selectedJob?.id == jobId) {
          _selectedJob = savedJob;
        }
        _applyFiltersAndSort();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final index = _jobs.indexWhere((j) => j.id == jobId);
        if (index != -1 && previousJob != null) {
          _jobs[index] = previousJob!;
        }
        if (_selectedJob?.id == jobId) {
          _selectedJob = previousJob;
        }
        _applyFiltersAndSort();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo cambiar la prioridad: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      _endLocalOperation();
    }
  }

  void _showStatusMenu(MechanicJob job, {BuildContext? anchorContext}) {
    if (job.isSaleWorkflow) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La venta se gestiona por el estado y los pagos de su factura; no tiene estado operativo de taller.',
          ),
        ),
      );
      return;
    }

    // Guide S-05: anchored popover, never a centred modal. Only the paths that
    // actually have a trigger widget can anchor; the compact shell is excluded
    // on purpose because the guide routes touch to a bottom sheet, not to a
    // popover ("la lista es un bottom sheet, no un popover de 200 px").
    final canAnchor = anchorContext != null &&
        anchorContext.mounted &&
        !ResponsiveViewport.usesCompactShell(context);

    if (canAnchor) {
      showVbAnchoredPopover<void>(
        anchorContext: anchorContext,
        builder: (popoverContext) => _buildStatusManager(
          job,
          popoverContext,
          asPopover: true,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => _buildStatusManager(job, dialogContext),
    );
  }

  Widget _buildStatusManager(
    MechanicJob job,
    BuildContext hostContext, {
    bool asPopover = false,
  }) {
    final dialogContext = hostContext;
    return _StatusManagerDialog(
      asPopover: asPopover,
      job: job,
      jobStatusService: _jobStatusService,
      warrantyPaymentReviewRequired: _hasWarrantyPaymentEvidence(job),
      onStatusSelected: (status) async {
        Navigator.pop(dialogContext);
        await _updateJobToCustomStatus(job, status);
      },
      onWarrantyOutcomeSelected: (outcome) async {
        Navigator.pop(dialogContext);
        final currentOutcome = job.warrantyOutcome ?? WarrantyOutcome.pending;
        if (outcome == currentOutcome) return;
        if (outcome == WarrantyOutcome.covered &&
            _hasWarrantyPaymentEvidence(job)) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Esta garantía tiene pagos vigentes. Primero revisa, revierte o reembolsa el pago desde la factura; el historial financiero no se modificará desde este estado.',
              ),
              backgroundColor: Colors.orange.shade900,
              duration: const Duration(seconds: 10),
              action: job.invoiceId == null
                  ? null
                  : SnackBarAction(
                      label: 'ABRIR FACTURA',
                      textColor: Colors.white,
                      onPressed: () => _openInvoice(job.invoiceId!),
                    ),
            ),
          );
          return;
        }
        final reason = await _requestWarrantyDecisionReason(job, outcome);
        if (reason == null) return;
        final normalizedReason = reason.trim().isEmpty ? null : reason.trim();
        final existingAttempt = _pendingWarrantyDecisionAttempts[job.id!];
        final attempt = existingAttempt != null &&
                existingAttempt.matches(outcome, normalizedReason)
            ? existingAttempt
            : _PendingWarrantyDecisionAttempt(
                outcome: outcome,
                reason: normalizedReason,
                operationKey: const Uuid().v4(),
              );
        _pendingWarrantyDecisionAttempts[job.id!] = attempt;
        _startLocalOperation();
        try {
          final receipt = await _bikeshopService.decideWarrantyClaim(
            warrantyJobId: job.id!,
            outcome: outcome,
            reason: normalizedReason,
            operationKey: attempt.operationKey,
          );
          if (mounted) {
            final receiptInvoiceId = receipt['invoice_id']?.toString();
            var updated = job.copyWith(
              warrantyOutcome: outcome,
              invoiceId: receiptInvoiceId,
              isInvoiced: receiptInvoiceId == null ? null : true,
              updatedAt: DateTime.now(),
            );
            setState(() {
              final index =
                  _jobs.indexWhere((candidate) => candidate.id == job.id);
              if (index != -1) _jobs[index] = updated;
              if (_selectedJob?.id == job.id) _selectedJob = updated;
              _applyFiltersAndSort();
            });
            if (identical(
              _pendingWarrantyDecisionAttempts[job.id!],
              attempt,
            )) {
              _pendingWarrantyDecisionAttempts.remove(job.id!);
            }
            Object? refreshError;
            try {
              await _loadData(
                surfaceErrors: false,
                rethrowErrors: true,
                forceInvoiceRefresh: true,
              );
              updated = _jobs.cast<MechanicJob?>().firstWhere(
                        (candidate) => candidate?.id == job.id,
                        orElse: () => updated,
                      ) ??
                  updated;
            } catch (error) {
              // The command already returned an exact receipt. A projection
              // refresh failure must not be reported as a rejected decision
              // or trigger a second command with a new operation key.
              refreshError = error;
              debugPrint(
                'Warranty decision ${attempt.operationKey} was confirmed, '
                'but table refresh failed: $error',
              );
            }
            if (!mounted) return;
            final confirmedMessage = switch (outcome) {
              WarrantyOutcome.covered =>
                'Garantía cubierta: respaldo interno actualizado.',
              WarrantyOutcome.notCovered
                  when _hasWarrantyPaymentEvidence(job) =>
                'Garantía no cubierta registrada: la factura pagada se conservó sin cambios.',
              WarrantyOutcome.notCovered =>
                'Garantía no cubierta: factura cobrable creada.',
              WarrantyOutcome.pending => 'Garantía devuelta a evaluación.',
            };
            final message = refreshError == null
                ? confirmedMessage
                : '$confirmedMessage No se pudo refrescar la tabla; usa Actualizar para releerla.';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                backgroundColor: outcome == WarrantyOutcome.notCovered
                    ? Colors.red.shade700
                    : Colors.green.shade700,
                action: updated.invoiceId == null
                    ? null
                    : SnackBarAction(
                        label: outcome == WarrantyOutcome.covered
                            ? 'Abrir respaldo'
                            : 'Abrir factura',
                        textColor: Colors.white,
                        onPressed: () => _openInvoice(updated.invoiceId!),
                      ),
              ),
            );
          }
        } on MechanicJobWarrantyCommandOutcomeUnknown catch (error) {
          debugPrint(
            'Warranty decision outcome remains unknown for ${job.id} with '
            'operation ${attempt.operationKey}: $error',
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'No se pudo confirmar el resultado. La decisión puede haberse guardado; vuelve a elegir exactamente la misma opción y motivo para reutilizar la misma operación.',
                ),
                backgroundColor: Colors.orange.shade900,
                duration: const Duration(seconds: 10),
              ),
            );
          }
        } catch (error) {
          if (identical(
            _pendingWarrantyDecisionAttempts[job.id!],
            attempt,
          )) {
            _pendingWarrantyDecisionAttempts.remove(job.id!);
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'El servidor rechazó la decisión; no se confirmó ningún cambio: $error',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
        } finally {
          _endLocalOperation();
        }
      },
      onQuotationStatusSelected: (qStatus) async {
        Navigator.pop(dialogContext);
        final reason = await _requestQuotationStatusReason(job, qStatus);
        if (reason == null) return;
        final normalizedReason = reason.trim().isEmpty ? null : reason.trim();
        final existingAttempt = _pendingQuotationTransitionAttempts[job.id!];
        final attempt = existingAttempt != null &&
                existingAttempt.matches(qStatus, normalizedReason)
            ? existingAttempt
            : _PendingQuotationTransitionAttempt(
                status: qStatus,
                reason: normalizedReason,
                operationKey: const Uuid().v4(),
              );
        _pendingQuotationTransitionAttempts[job.id!] = attempt;
        await _submitQuotationTransition(job, attempt);
      },
    );
  }

  Future<void> _submitQuotationTransition(
    MechanicJob job,
    _PendingQuotationTransitionAttempt attempt,
  ) async {
    final jobId = job.id?.trim();
    if (jobId == null || jobId.isEmpty) return;
    // Only the latest semantic status/reason choice may reach the server. An
    // older uncertain snackbar must not revert a newer worker decision.
    if (!identical(_pendingQuotationTransitionAttempts[jobId], attempt)) {
      return;
    }

    _startLocalOperation();
    try {
      await _bikeshopService.updateQuotationStatus(
        jobId,
        attempt.status,
        reason: attempt.reason,
        operationKey: attempt.operationKey,
      );

      var updated = job.copyWith(
        quotationStatus: attempt.status,
        updatedAt: DateTime.now(),
      );
      if (mounted) {
        setState(() {
          final index = _jobs.indexWhere((candidate) => candidate.id == jobId);
          if (index != -1) _jobs[index] = updated;
          if (_selectedJob?.id == jobId) _selectedJob = updated;
          _applyFiltersAndSort();
        });
      }
      if (identical(
        _pendingQuotationTransitionAttempts[jobId],
        attempt,
      )) {
        _pendingQuotationTransitionAttempts.remove(jobId);
      }

      Object? refreshError;
      try {
        await _loadData(
          surfaceErrors: false,
          rethrowErrors: true,
        );
        updated = _jobs.cast<MechanicJob?>().firstWhere(
                  (candidate) => candidate?.id == jobId,
                  orElse: () => updated,
                ) ??
            updated;
      } catch (error) {
        // The command receipt already confirmed this transition. Projection
        // refresh is a separate read and must never turn success into a red
        // rejection or trigger a fresh operation key.
        refreshError = error;
        debugPrint(
          'Quotation transition ${attempt.operationKey} was confirmed, '
          'but table refresh failed: $error',
        );
      }
      if (!mounted) return;

      final refreshSuffix = refreshError == null
          ? ''
          : ' No se pudo refrescar la tabla; usa Actualizar para releer el cambio guardado.';
      if (attempt.status == QuotationStatus.approved) {
        final approvedMessage = job.isServiceBudget
            ? 'Presupuesto aprobado. Puedes facturarlo conservando la recepción y sus fichas ya guardadas.'
            : 'Cotización aprobada. Conviértela cuando recibas la bicicleta o componente.';
        _showReplacingQuotationSnackBar(
          SnackBar(
            content: Text(
              '$approvedMessage$refreshSuffix',
            ),
            duration: const Duration(seconds: 8),
            backgroundColor: refreshError == null
                ? Colors.green.shade700
                : Colors.orange.shade800,
            action: SnackBarAction(
              label: job.isServiceBudget ? 'Facturar ahora' : 'Convertir ahora',
              textColor: Colors.white,
              onPressed: () => _convertToService(updated),
            ),
          ),
        );
      } else {
        final stateOwner =
            job.isServiceBudget ? 'del presupuesto' : 'de la cotización';
        _showReplacingQuotationSnackBar(
          SnackBar(
            content: Text(
              'Estado $stateOwner actualizado.$refreshSuffix',
            ),
            backgroundColor: refreshError == null
                ? Colors.green.shade700
                : Colors.orange.shade800,
          ),
        );
      }
    } on MechanicJobQuotationCommandOutcomeUnknown catch (error) {
      debugPrint(
        'Quotation transition outcome remains unknown for $jobId with '
        'operation ${attempt.operationKey}: $error',
      );
      if (!mounted) return;
      _showReplacingQuotationSnackBar(
        SnackBar(
          content: const Text(
            'No se pudo confirmar el cambio. Puede haberse guardado; Reintentar reutiliza exactamente la misma operación.',
          ),
          backgroundColor: Colors.orange.shade900,
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: 'REINTENTAR',
            textColor: Colors.white,
            onPressed: () => unawaited(
              _submitQuotationTransition(job, attempt),
            ),
          ),
        ),
      );
    } catch (error) {
      if (identical(
        _pendingQuotationTransitionAttempts[jobId],
        attempt,
      )) {
        _pendingQuotationTransitionAttempts.remove(jobId);
      }
      if (!mounted) return;
      _showReplacingQuotationSnackBar(
        SnackBar(
          content: Text(
            'El servidor rechazó el cambio de ${job.proposalDocumentLabelLower}; no se confirmó ningún cambio: $error',
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      _endLocalOperation();
    }
  }

  void _showReplacingQuotationSnackBar(SnackBar snackBar) {
    _clearQuotationSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  void _clearQuotationSnackBars() {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // ScaffoldMessenger otherwise queues status messages and carries them
    // across routes. A previous "approved" action must never remain visible
    // after the same proposal has already been reopened as pending.
    messenger.clearSnackBars();
    messenger.removeCurrentSnackBar();
  }

  Future<String?> _requestQuotationStatusReason(
    MechanicJob job,
    QuotationStatus status,
  ) async {
    final now = DateTime.now();
    final isLateApproval = status == QuotationStatus.approved &&
        job.isQuotationPastValidityAt(now);
    final isReopening = status == QuotationStatus.pending &&
        job.quotationStatus != QuotationStatus.pending;
    final isEarlyExpiry = status == QuotationStatus.expired &&
        !job.isQuotationPastValidityAt(now);
    final requiresReason = status == QuotationStatus.rejected ||
        isLateApproval ||
        isReopening ||
        isEarlyExpiry;
    if (!requiresReason) return '';

    final proposalNoun = job.proposalDocumentLabelLower;
    final title = switch (status) {
      QuotationStatus.rejected => 'Rechazar $proposalNoun',
      QuotationStatus.approved => job.isServiceBudget
          ? 'Aprobar presupuesto vencido'
          : 'Aprobar cotización vencida',
      QuotationStatus.pending => 'Reabrir $proposalNoun',
      QuotationStatus.expired => 'Vencer $proposalNoun anticipadamente',
    };
    final hint = switch (status) {
      QuotationStatus.rejected =>
        'Ej: Cliente no aprobó el valor o cambió de opción',
      QuotationStatus.approved =>
        'Ej: Se mantiene el precio anterior por acuerdo con el cliente',
      QuotationStatus.pending =>
        'Ej: Se actualizarán productos o valores antes de reenviarlo',
      QuotationStatus.expired =>
        'Ej: Cambió el precio o dejó de estar disponible un producto',
    };
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(status == QuotationStatus.approved
            ? Icons.verified_outlined
            : Icons.edit_note_outlined),
        title: Text(title),
        content: SizedBox(
          width: 440,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Motivo *',
              hintText: hint,
              border: const OutlineInputBorder(),
              helperText:
                  'Quedará guardado en el historial de ${job.jobNumber}.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Guardar cambio'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<String?> _requestWarrantyDecisionReason(
    MechanicJob job,
    WarrantyOutcome outcome,
  ) async {
    if (outcome == WarrantyOutcome.pending) return '';

    MechanicJobWarrantyClaim? claim;
    try {
      claim = await _bikeshopService.getWarrantyClaim(job.id!);
    } catch (_) {
      // The database command remains the final validator. Keep the interaction
      // usable if a projection refresh is temporarily unavailable.
    }

    final requiresReason = outcome == WarrantyOutcome.notCovered ||
        claim?.eligibility != WarrantyEligibility.withinWindow;
    if (!requiresReason) return '';
    if (!mounted) return null;

    final controller = TextEditingController(text: claim?.reason ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(outcome == WarrantyOutcome.covered
            ? 'Justificar excepción de garantía'
            : 'Motivo de garantía no cubierta'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: outcome == WarrantyOutcome.covered
                ? 'Por qué se acepta fuera de plazo o sin fecha confiable'
                : 'Hallazgo técnico o condición que no está cubierta',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) return;
              Navigator.pop(dialogContext, value);
            },
            child: const Text('Guardar decisión'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _updateJobToCustomStatus(
      MechanicJob job, JobStatusCustom newStatus) async {
    if (job.id == null ||
        newStatus.id == null ||
        newStatus.id == job.statusId) {
      return;
    }
    _startLocalOperation();
    try {
      await _bikeshopService.transitionJobStatus(
        job.id!,
        newStatus.id!,
        operationKey: const Uuid().v4(),
      );
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Estado actualizado a ${newStatus.name}'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      await _loadData();
      if (mounted) {
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

  void _showBikeProfileDialog(
    MechanicJob job,
    Customer? customer, {
    Bike? initialBike,
  }) async {
    if (customer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cliente no encontrado')),
      );
      return;
    }

    final customerId = customer.id;
    if (customerId == null || customerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cliente sin identificador')),
      );
      return;
    }

    if (!mounted) return;

    var activeJob = _jobs.firstWhere(
      (j) => j.id == job.id,
      orElse: () => job,
    );
    var activeBike = initialBike ??
        (activeJob.bikeId == null ? null : _bikes[activeJob.bikeId!]);

    if (activeBike == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bicicleta no encontrada')),
      );
      return;
    }

    while (mounted && activeBike != null) {
      final pickerOptions = _customerBikesForPicker(customerId, activeBike);
      final openedBikeId = activeBike.id;

      final result = await showDialog<Bike>(
        context: context,
        builder: (context) => BikeFormDialog(
          customerId: customerId,
          bike: activeBike,
          bikePickerOptions: pickerOptions,
          onBikePickerSelected: (selectedBike) async {
            final updatedJob = await _changeBikeForJob(activeJob, selectedBike);
            if (updatedJob == null) return false;
            activeJob = updatedJob;
            return true;
          },
        ),
      );

      if (!mounted || result == null) break;

      if (result.id != null) {
        setState(() {
          _bikes[result.id!] = result;
          _applyFiltersAndSort();
        });
      }

      if (result.id != null &&
          result.id != openedBikeId &&
          result.customerId == customerId) {
        activeBike = _bikes[result.id!] ?? result;
        continue;
      }

      break;
    }
  }

  List<Bike> _customerBikesForPicker(String customerId, Bike activeBike) {
    final bikesById = <String, Bike>{};
    if (activeBike.id != null && activeBike.id!.isNotEmpty) {
      bikesById[activeBike.id!] = activeBike;
    }
    for (final bike in _bikes.values) {
      if (bike.customerId != customerId || bike.id == null) continue;
      bikesById[bike.id!] = bike;
    }
    return bikesById.values.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  Future<MechanicJob?> _changeBikeForJob(
    MechanicJob job,
    Bike selectedBike,
  ) async {
    final jobId = job.id;
    final selectedBikeId = selectedBike.id;
    if (jobId == null || jobId.isEmpty || selectedBikeId == null) {
      return null;
    }
    if (job.bikeId == selectedBikeId) return job;

    final updatedJob = job.copyWith(
      bikeId: selectedBikeId,
      updatedAt: DateTime.now(),
    );
    final existingJobBikes = _jobBikesMap[jobId];
    final updatedJobBike = existingJobBikes?.length == 1
        ? existingJobBikes!.first.copyWith(
            bikeId: selectedBikeId,
            bike: selectedBike,
          )
        : null;

    _startLocalOperation();
    setState(() {
      final index = _jobs.indexWhere((j) => j.id == jobId);
      if (index != -1) {
        _jobs[index] = updatedJob;
      }
      _bikes[selectedBikeId] = selectedBike;
      if (updatedJobBike != null) {
        _jobBikesMap[jobId] = [updatedJobBike];
      }
      _applyFiltersAndSort();
    });

    try {
      final savedJob = await _bikeshopService.updateJob(
        updatedJob,
        syncBikeMemory: updatedJobBike == null,
      );
      if (updatedJobBike != null) {
        await _bikeshopService.updateJobBike(updatedJobBike);
      }
      if (mounted) {
        setState(() {
          final index = _jobs.indexWhere((j) => j.id == jobId);
          if (index != -1) {
            _jobs[index] = savedJob;
          }
          _applyFiltersAndSort();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bicicleta cambiada a: ${selectedBike.displayName}'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
      return savedJob;
    } catch (e) {
      if (mounted) {
        await _loadData();
        if (!mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cambiar bicicleta: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    } finally {
      _endLocalOperation();
    }
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

  String? _serviceWarrantyMeta(MechanicJob job) {
    final warranty = job.serviceWarranty;
    if (warranty == null || warranty.state == ServiceWarrantyState.notStarted) {
      return null;
    }

    if (warranty.state == ServiceWarrantyState.active) {
      final days = warranty.daysRemaining;
      if (days == null) return 'Garantía vigente';
      if (days == 0) return 'Garantía vence hoy';
      return 'Garantía ${days}d';
    }

    final expiry = warranty.warrantyExpiresAt;
    return expiry == null
        ? 'Garantía vencida'
        : 'Venció ${DateFormat('dd/MM').format(expiry.toLocal())}';
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
      case JobType.sale:
        return Icons.shopping_bag_outlined;
    }
  }

  /// Legacy status color mapping (for backward compatibility)
  /// Colors match the canonical database-seeded legacy status values.
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
    final requestedJobs =
        _filteredJobs.where((job) => _selectedJobIds.contains(job.id)).toList();
    if (requestedJobs.isEmpty) return;

    // Standalone quotations and sales have commercial/payment state rather
    // than a workshop lifecycle. A mixed bulk selection updates only the
    // physical workshop rows and reports exactly what was skipped.
    final selectedJobs =
        requestedJobs.where(_usesOperationalLifecycle).toList();
    final skippedCommercialRows = requestedJobs.length - selectedJobs.length;
    if (selectedJobs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La selección solo contiene cotizaciones o ventas, que no tienen estado operativo de taller.',
          ),
        ),
      );
      return;
    }

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

    _startLocalOperation();
    var succeeded = 0;
    final failures = <String>[];
    try {
      for (var job in selectedJobs) {
        try {
          await _bikeshopService.transitionJobStatus(
            job.id!,
            newCustomStatus.id!,
            operationKey: const Uuid().v4(),
          );
          succeeded++;
        } catch (error) {
          failures.add('${job.jobNumber ?? job.id}: $error');
        }
      }
      await _loadData();
      if (mounted) {
        setState(_selectedJobIds.clear);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${failures.isEmpty ? '$succeeded trabajos actualizados a ${newCustomStatus.name}' : '$succeeded de ${selectedJobs.length} trabajos actualizados. La tabla fue recargada; ${failures.length} cambios no se confirmaron.'}'
              '${skippedCommercialRows == 0 ? '' : ' Se omitieron $skippedCommercialRows cotizaciones o ventas sin estado operativo.'}',
            ),
            backgroundColor: failures.isEmpty ? Colors.green : Colors.orange,
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
    return PegasTasksWidget(
      useCompactLayout: ResponsiveViewport.usesCompactShell(context),
      session: _tasksSession,
    );
  }

  // ========== BOARD VIEW (Kanban) ==========
  Widget _buildBoardView() {
    // Use custom statuses from JobStatusService, grouped by phase
    return ListenableBuilder(
      listenable: _jobStatusService,
      builder: (context, _) {
        final customStatuses = _jobStatusService.activeStatuses;
        final operationalJobs =
            _filteredJobs.where(_usesOperationalLifecycle).toList();

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
          final compactGroups = <WorkshopBoardCompactGroup>[];
          for (final status in legacyStatuses) {
            final jobsInStatus =
                operationalJobs.where((j) => j.status == status).toList();
            // Only show columns with jobs
            if (jobsInStatus.isNotEmpty) {
              columns.add(_buildLegacyBoardColumn(status, jobsInStatus));
              compactGroups.add(
                WorkshopBoardCompactGroup(
                  id: status.name,
                  label: status.displayName,
                  color: _legacyBoardStatusColor(status),
                  children: jobsInStatus
                      .map(
                        (job) => _buildCompactBoardCard(
                          job,
                          statusColor: _legacyBoardStatusColor(status),
                        ),
                      )
                      .toList(),
                ),
              );
            }
          }

          if (columns.isEmpty) {
            return const Center(
              child: Text('No hay trabajos que mostrar',
                  style: TextStyle(color: Colors.grey)),
            );
          }

          if (ResponsiveViewport.usesCompactShell(context)) {
            return WorkshopBoardCompactView(
              groups: compactGroups,
              session: _compactBoardSession,
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
        final compactGroups = <WorkshopBoardCompactGroup>[];
        for (final customStatus in customStatuses) {
          final jobsInStatus = operationalJobs
              .where((j) =>
                  j.statusId == customStatus.id ||
                  (j.statusId == null &&
                      j.status.name.toUpperCase() == customStatus.code))
              .toList();
          // Only show columns with jobs
          if (jobsInStatus.isNotEmpty) {
            columns.add(_buildCustomBoardColumn(customStatus, jobsInStatus));
            compactGroups.add(
              WorkshopBoardCompactGroup(
                id: customStatus.id ?? customStatus.code,
                label: customStatus.name,
                color: customStatus.colorValue,
                children: jobsInStatus
                    .map(
                      (job) => _buildCompactBoardCard(
                        job,
                        statusColor: customStatus.colorValue,
                      ),
                    )
                    .toList(),
              ),
            );
          }
        }

        if (columns.isEmpty) {
          return const Center(
            child: Text('No hay trabajos que mostrar',
                style: TextStyle(color: Colors.grey)),
          );
        }

        if (ResponsiveViewport.usesCompactShell(context)) {
          return WorkshopBoardCompactView(
            groups: compactGroups,
            session: _compactBoardSession,
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

  Color _legacyBoardStatusColor(JobStatus status) {
    return switch (status) {
      JobStatus.pendiente => Colors.blue.shade600,
      JobStatus.diagnostico => Colors.orange.shade700,
      JobStatus.esperandoRepuestos => Colors.purple.shade600,
      JobStatus.enCurso => Colors.teal.shade600,
      JobStatus.finalizado => Colors.green.shade700,
      JobStatus.entregado => Colors.grey.shade600,
      _ => Theme.of(context).colorScheme.primary,
    };
  }

  Widget _buildCompactBoardCard(
    MechanicJob job, {
    required Color statusColor,
  }) {
    final theme = Theme.of(context);
    final customer = _customers[job.customerId];
    final bike = _bikes[job.bikeId];
    final objectLabel = job.isComponentIntake
        ? _componentObjectLabel(job)
        : bike?.displayName ??
            (job.modeNeedsReview
                ? 'Clasificación pendiente'
                : 'Sin objeto identificado');
    final isOverdue = job.deliveryDeadline != null &&
        job.deliveryDeadline!.isBefore(DateTime.now());
    final exceptionLabel = job.priority == JobPriority.urgente
        ? 'Urgente'
        : isOverdue
            ? 'Plazo vencido'
            : job.isServiceBudget
                ? job.proposalStatusDisplayName
                : null;
    final openLabel = [
      'Abrir trabajo ${job.jobNumber ?? 'sin número'}',
      customer?.name ?? 'Cliente sin identificar',
      objectLabel,
      if (exceptionLabel != null) exceptionLabel,
    ].join(', ');

    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 3,
            child: ColoredBox(color: statusColor),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  button: true,
                  label: openLabel,
                  excludeSemantics: true,
                  onTap: () => _openJobFromTable(job),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _openJobFromTable(job),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 76),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          job.jobNumber ?? 'Sin número',
                                          style: theme.textTheme.labelLarge
                                              ?.copyWith(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        if (exceptionLabel != null) ...[
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              exceptionLabel,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.end,
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                color: isOverdue ||
                                                        job.priority ==
                                                            JobPriority.urgente
                                                    ? theme.colorScheme.error
                                                    : _proposalStatusColor(job),
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      customer?.name ??
                                          'Cliente sin identificar',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      objectLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const SizedBox(
                                width: 40,
                                height: 48,
                                child: Icon(Icons.chevron_right_rounded),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant,
                ),
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Text(
                            job.deliveryDeadline == null
                                ? 'Sin plazo comprometido'
                                : 'Plazo ${DateFormat('dd/MM').format(job.deliveryDeadline!)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: isOverdue
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _showStatusMenu(job),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(112, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: const Text('Cambiar estado'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
    final objectLabel = job.isComponentIntake
        ? _componentObjectLabel(job)
        : bike?.displayName ??
            (job.modeNeedsReview
                ? 'Clasificación pendiente'
                : 'Sin objeto identificado');
    final isOverdue = job.deliveryDeadline != null &&
        job.deliveryDeadline!.isBefore(DateTime.now());

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      child: InkWell(
        onTap: () => _openJobFromTable(job),
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
                objectLabel,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[700],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (job.isServiceBudget) ...[
                const SizedBox(height: 4),
                Text(
                  job.proposalStatusDisplayName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _proposalStatusColor(job),
                  ),
                ),
              ],
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
      useCompactLayout: ResponsiveViewport.usesCompactShell(context),
      session: _calendarSession,
    );
  }

  // ========== GANTT VIEW (Notion-style Timeline) ==========

  Widget _buildGanttView() {
    final jobsWithDates = _filteredJobs
        .where(
          (job) => !job.isSaleWorkflow && !job.isStandaloneQuotation,
        )
        .toList()
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

    final visibleDays =
        _timelineScale == 'week' ? 14 : 60; // 2 weeks or 2 months

    return LayoutBuilder(
      builder: (context, _) {
        final compact = ResponsiveViewport.usesCompactShell(context);
        final dayWidth =
            _timelineScale == 'week' ? (compact ? 76.0 : 120.0) : 40.0;
        return Column(
          children: [
            _buildTimelineControls(),
            Expanded(
              child: _buildTimelineContent(
                jobsWithDates,
                dayWidth,
                visibleDays,
                compact: compact,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTimelineControls() {
    final theme = Theme.of(context);
    final periodLabel =
        DateFormat('MMMM yyyy', 'es').format(_timelineViewStart);

    return LayoutBuilder(
      builder: (context, _) {
        final compact = ResponsiveViewport.usesCompactShell(context);
        return Container(
          key: compact
              ? const ValueKey('workshop-gantt-compact-controls')
              : null,
          padding: compact
              ? const EdgeInsets.fromLTRB(12, 8, 12, 10)
              : const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: compact
              ? Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            periodLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          constraints: const BoxConstraints.tightFor(
                            width: 48,
                            height: 48,
                          ),
                          icon: const Icon(Icons.chevron_left_rounded),
                          onPressed: () => _moveTimeline(-1),
                          tooltip: 'Anterior',
                        ),
                        TextButton(
                          onPressed: _resetTimelineToToday,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          child: const Text('Hoy'),
                        ),
                        IconButton(
                          constraints: const BoxConstraints.tightFor(
                            width: 48,
                            height: 48,
                          ),
                          icon: const Icon(Icons.chevron_right_rounded),
                          onPressed: () => _moveTimeline(1),
                          tooltip: 'Siguiente',
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: _buildTimelineScaleSelector(expanded: true),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Text(
                      periodLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const Spacer(),
                    _buildTimelineScaleSelector(),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _moveTimeline(-1),
                      tooltip: 'Anterior',
                    ),
                    OutlinedButton(
                      onPressed: _resetTimelineToToday,
                      child: const Text('Hoy'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => _moveTimeline(1),
                      tooltip: 'Siguiente',
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildTimelineScaleSelector({bool expanded = false}) {
    return SegmentedButton<String>(
      style: const ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(48, 48)),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
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
      showSelectedIcon: false,
      expandedInsets: expanded ? EdgeInsets.zero : null,
      onSelectionChanged: (selected) {
        setState(() {
          _timelineScale = selected.first;
          _resetGanttScrollOffsets();
        });
      },
    );
  }

  void _moveTimeline(int direction) {
    setState(() {
      _timelineViewStart = _timelineViewStart.add(
        Duration(
          days: direction * (_timelineScale == 'week' ? 7 : 30),
        ),
      );
      _resetGanttScrollOffsets();
    });
  }

  void _resetTimelineToToday() {
    setState(() {
      _timelineViewStart = DateTime.now().subtract(
        const Duration(days: 7),
      );
      _resetGanttScrollOffsets();
    });
  }

  void _rememberGanttScroll() {
    if (_ganttHorizontalScrollController.hasClients) {
      _ganttHorizontalOffset = _ganttHorizontalScrollController.offset;
    }
    if (_ganttVerticalScrollController.hasClients) {
      _ganttVerticalOffset = _ganttVerticalScrollController.offset;
    }
  }

  void _resetGanttScrollOffsets() {
    _ganttHorizontalOffset = 0;
    _ganttVerticalOffset = 0;
    if (_ganttHorizontalScrollController.hasClients) {
      _ganttHorizontalScrollController.jumpTo(0);
    }
    if (_ganttVerticalScrollController.hasClients) {
      _ganttVerticalScrollController.jumpTo(0);
    }
  }

  void _scheduleGanttScrollRestore() {
    if (_ganttRestoreScheduled) return;
    _ganttRestoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ganttRestoreScheduled = false;
      if (!mounted || _viewMode != 'gantt') return;
      _restoreGanttController(
        _ganttHorizontalScrollController,
        _ganttHorizontalOffset,
      );
      _restoreGanttController(
        _ganttVerticalScrollController,
        _ganttVerticalOffset,
      );
    });
  }

  void _restoreGanttController(
    ScrollController controller,
    double offset,
  ) {
    if (!controller.hasClients) return;
    final target = offset.clamp(
      controller.position.minScrollExtent,
      controller.position.maxScrollExtent,
    );
    if ((controller.offset - target).abs() > 0.5) {
      controller.jumpTo(target);
    }
  }

  Widget _buildTimelineContent(
    List<MechanicJob> jobs,
    double dayWidth,
    int visibleDays, {
    required bool compact,
  }) {
    final totalWidth = dayWidth * visibleDays;
    _scheduleGanttScrollRestore();

    return SingleChildScrollView(
      key: const ValueKey('workshop-gantt-horizontal-scroll'),
      controller: _ganttHorizontalScrollController,
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
                controller: _ganttVerticalScrollController,
                child: Column(
                  children: jobs
                      .map(
                        (job) => _buildTimelineJobRow(
                          job,
                          dayWidth,
                          visibleDays,
                          compact: compact,
                        ),
                      )
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
    MechanicJob job,
    double dayWidth,
    int visibleDays, {
    required bool compact,
  }) {
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
      height: compact ? 52 : 36,
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
            top: compact ? 2 : 4,
            bottom: compact ? 2 : 4,
            child: Tooltip(
              message: '${customer?.name ?? 'N/A'}\n${job.jobNumber ?? ''}\n'
                  '${DateFormat('dd/MM').format(jobStart)} - ${DateFormat('dd/MM').format(jobEnd)}',
              child: InkWell(
                onTap: () => _openJobFromTable(job),
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
  final bool warrantyPaymentReviewRequired;

  /// Render as an anchored popover surface instead of a centred dialog.
  /// Set by callers that have a trigger to anchor to; see guide S-05.
  final bool asPopover;

  const _StatusManagerDialog({
    required this.job,
    required this.jobStatusService,
    required this.onStatusSelected,
    this.onWarrantyOutcomeSelected,
    this.onQuotationStatusSelected,
    this.warrantyPaymentReviewRequired = false,
    this.asPopover = false,
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
        final usesCompactLayout = ResponsiveViewport.usesCompactShell(context);

        final dialogTitle = Row(
          children: [
            Expanded(
              child: Text(_isEditMode
                  ? (_editingStatus != null ? 'Editar Estado' : 'Nuevo Estado')
                  : widget.job.isStandaloneQuotation
                      ? 'Gestionar ${widget.job.proposalDocumentLabelLower}'
                      : widget.job.isServiceBudget
                          ? 'Estado operativo y presupuesto'
                          : 'Cambiar Estado'),
            ),
            if (!_isEditMode && !widget.job.isStandaloneQuotation)
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 22),
                tooltip: 'Agregar estado',
                constraints: BoxConstraints.tight(const Size(48, 48)),
                onPressed: () => _startEditing(null),
              ),
          ],
        );

        final dialogContent = SizedBox(
          width: usesCompactLayout ? double.maxFinite : 360,
          child: _isEditMode
              ? _buildEditForm()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.job.jobType == JobType.warranty)
                      _buildWarrantyOutcomeSection(),
                    if (widget.job.isQuotationWorkflow)
                      _buildQuotationStatusSection(),
                    if (widget.job.jobType == JobType.warranty ||
                        widget.job.isServiceBudget)
                      const Divider(height: 16),
                    if (!widget.job.isStandaloneQuotation)
                      Flexible(
                          child: _buildStatusList(
                              statusesByPhase, currentStatusId)),
                  ],
                ),
        );

        final dialogActions = _isEditMode
            ? [
                TextButton(
                  onPressed: _cancelEditing,
                  style: usesCompactLayout
                      ? TextButton.styleFrom(
                          minimumSize: const Size(88, 48),
                        )
                      : null,
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: _saveStatus,
                  style: usesCompactLayout
                      ? FilledButton.styleFrom(
                          minimumSize: const Size(96, 48),
                        )
                      : null,
                  child: const Text('Guardar'),
                ),
              ]
            : [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: usesCompactLayout
                        ? TextButton.styleFrom(
                            minimumSize: const Size(72, 48),
                          )
                        : null,
                    child: const Text('Cerrar')),
              ];

        // Guide S-05: a select opens as a popover anchored to its trigger, and
        // "jamás un modal centrado". The centred AlertDialog stays only for the
        // paths that have no anchor to attach to (bulk toolbar, compact shell,
        // where the guide asks for a sheet instead).
        if (widget.asPopover) {
          return VbPopoverSurface(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: DefaultTextStyle(
                    style: Theme.of(context).textTheme.titleSmall ??
                        const TextStyle(fontWeight: FontWeight.w600),
                    child: dialogTitle,
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: dialogContent,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: dialogActions,
                  ),
                ),
              ],
            ),
          );
        }

        return AlertDialog(
          key: const ValueKey('workshop-status-manager-dialog'),
          insetPadding: usesCompactLayout
              ? const EdgeInsets.all(8)
              : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          titlePadding: usesCompactLayout
              ? const EdgeInsets.fromLTRB(20, 14, 10, 8)
              : null,
          contentPadding: usesCompactLayout
              ? const EdgeInsets.symmetric(horizontal: 16)
              : null,
          actionsPadding: usesCompactLayout
              ? const EdgeInsets.fromLTRB(12, 4, 12, 8)
              : null,
          title: dialogTitle,
          content: dialogContent,
          actions: dialogActions,
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
        if (widget.warrantyPaymentReviewRequired)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              border: Border.all(color: Colors.orange.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Hay pagos vigentes. Para aceptar la garantía como cubierta, primero revisa el pago desde la factura.',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.orange.shade900,
              ),
            ),
          ),
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
            final isBlockedByPayment = widget.warrantyPaymentReviewRequired &&
                outcome == WarrantyOutcome.covered;
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
                      ? (isSelected || isBlockedByPayment
                          ? null
                          : () => widget.onWarrantyOutcomeSelected!(outcome))
                      : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.withValues(alpha: 0.15)
                          : isBlockedByPayment
                              ? Colors.grey.shade100
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
                          color: isSelected
                              ? color
                              : isBlockedByPayment
                                  ? Colors.grey.shade400
                                  : Colors.grey,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? color
                                : isBlockedByPayment
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade600,
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
    final stored = widget.job.quotationStatus ?? QuotationStatus.pending;
    final current = widget.job.effectiveQuotationStatus;
    final isExpiredByDate =
        stored == QuotationStatus.pending && current == QuotationStatus.expired;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            widget.job.isServiceBudget
                ? 'Estado del Presupuesto'
                : 'Estado de la Cotización',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
        ),
        if (isExpiredByDate) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Text(
              'La propuesta venció por fecha, pero sigue guardada como Pendiente. Para reactivarla, abre la ficha y extiende “Válido hasta”; no se registrará una transición ficticia.',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontSize: 11,
                height: 1.25,
              ),
            ),
          ),
        ],
        Row(
          children: QuotationStatus.values.map((qStatus) {
            final isSelected = qStatus == current;
            final isDisabled = qStatus == stored || qStatus == current;
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
                  onTap: widget.onQuotationStatusSelected != null && !isDisabled
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
                          color: isSelected
                              ? color
                              : isDisabled
                                  ? Colors.grey.shade300
                                  : Colors.grey,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          qStatus.displayName,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? color
                                : isDisabled
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade600,
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
    final usesCompactLayout = ResponsiveViewport.usesCompactShell(context);

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
            style: ButtonStyle(
              visualDensity: usesCompactLayout
                  ? VisualDensity.standard
                  : VisualDensity.compact,
              tapTargetSize: usesCompactLayout
                  ? MaterialTapTargetSize.padded
                  : MaterialTapTargetSize.shrinkWrap,
              minimumSize: usesCompactLayout
                  ? const WidgetStatePropertyAll(Size(0, 48))
                  : null,
            ),
          ),
          const SizedBox(height: 16),

          // Color picker
          const Text('Color',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: usesCompactLayout ? 0 : 8,
            runSpacing: usesCompactLayout ? 0 : 8,
            children: _colors.indexed.map((entry) {
              final colorIndex = entry.$1;
              final color = entry.$2;
              final isSelected = _selectedColor == color;
              final colorValue = _parseColor(color);
              return Semantics(
                button: true,
                selected: isSelected,
                label: 'Seleccionar color ${colorIndex + 1}',
                child: InkResponse(
                  onTap: () => setState(() => _selectedColor = color),
                  radius: 24,
                  child: SizedBox(
                    width: usesCompactLayout ? 48 : 32,
                    height: usesCompactLayout ? 48 : 32,
                    child: Center(
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: colorValue,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                isSelected ? Colors.white : Colors.transparent,
                            width: 3,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: colorValue.withValues(alpha: 0.5),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : null,
                        ),
                        child: isSelected
                            ? const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 18,
                              )
                            : null,
                      ),
                    ),
                  ),
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

    Widget buildItem(BuildContext context, int index) {
      final item = items[index];
      if (item.isHeader) {
        return _buildPhaseHeaderItem(
          key: ValueKey('header_${item.phase}'),
          title: item.title!,
          phase: item.phase!,
        );
      }
      return _buildDraggableStatusTile(
        key: ValueKey(item.status!.id),
        status: item.status!,
        currentStatusId: currentStatusId,
        index: index,
      );
    }

    if (ResponsiveViewport.usesCompactShell(context)) {
      return ListView.builder(
        key: const ValueKey('workshop-status-compact-list'),
        itemCount: items.length,
        itemBuilder: buildItem,
      );
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
      itemBuilder: buildItem,
    );
  }

  Widget _buildPhaseHeaderItem({
    required Key key,
    required String title,
    required StatusPhase phase,
  }) {
    final usesCompactLayout = ResponsiveViewport.usesCompactShell(context);

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
              constraints: BoxConstraints.tight(
                Size.square(usesCompactLayout ? 48 : 24),
              ),
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
    final usesCompactLayout = ResponsiveViewport.usesCompactShell(context);

    if (usesCompactLayout) {
      return Material(
        key: key,
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  selected: isSelected,
                  label: 'Cambiar estado a ${status.name}',
                  child: InkWell(
                    onTap: () => widget.onStatusSelected(status),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
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
                          Expanded(
                            child: Text(
                              status.name,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: isSelected ? statusColor : null,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          if (isSelected)
                            Icon(
                              Icons.check_rounded,
                              size: 20,
                              color: statusColor,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                key: ValueKey('workshop-status-actions-${status.id}'),
                tooltip: 'Gestionar ${status.name}',
                constraints: const BoxConstraints(
                  minWidth: 220,
                  maxWidth: 300,
                ),
                onSelected: (action) {
                  if (action == 'edit') {
                    _startEditing(status);
                  } else if (action == 'delete') {
                    _deleteStatus(status);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    height: 56,
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined),
                        SizedBox(width: 12),
                        Expanded(child: Text('Editar estado')),
                      ],
                    ),
                  ),
                  if (!status.isSystem)
                    PopupMenuItem(
                      value: 'delete',
                      height: 56,
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Eliminar estado',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                child: const SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(Icons.more_horiz),
                ),
              ),
            ],
          ),
        ),
      );
    }

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

    if (!mounted) return;
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
