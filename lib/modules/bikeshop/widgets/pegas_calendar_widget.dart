import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart'; // For WhatsApp icon
import 'package:uuid/uuid.dart';

import '../services/bikeshop_service.dart';
import '../services/job_status_service.dart';
import '../models/bikeshop_models.dart';
import '../../crm/services/customer_service.dart';
import '../../crm/models/crm_models.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../sales/widgets/sales_invoice_editor.dart'; // Import Invoice Editor
import '../widgets/tasks_tab_view.dart'; // Import Tasks Tab
import 'smart_job_details_editor.dart'; // Import Smart Editor

/// Parent-owned calendar browsing context.
///
/// Jobs keeps this object alive while the operator switches modes or opens an
/// inline workspace, so the selected date and month are not reset to today.
class PegasCalendarSession {
  PegasCalendarSession({
    DateTime? selectedDate,
    DateTime? focusedMonth,
  })  : selectedDate = selectedDate ?? DateTime.now(),
        focusedMonth = focusedMonth ?? selectedDate ?? DateTime.now();

  DateTime selectedDate;
  DateTime focusedMonth;
}

/// Shared calendar widget for displaying mechanic jobs
/// Used by both WorkshopCalendarPage and PegasTablePage calendar tab
class PegasCalendarWidget extends StatefulWidget {
  /// If provided, uses this data instead of loading from service
  final List<MechanicJob>? jobs;
  final Map<String, Customer>? customers;
  final Map<String, Bike>? bikes;

  /// Callback when data needs to be refreshed (for external data mode)
  final VoidCallback? onRefreshNeeded;
  final bool? useCompactLayout;
  final PegasCalendarSession? session;

  const PegasCalendarWidget({
    super.key,
    this.jobs,
    this.customers,
    this.bikes,
    this.onRefreshNeeded,
    this.useCompactLayout,
    this.session,
  });

  @override
  State<PegasCalendarWidget> createState() => _PegasCalendarWidgetState();
}

class _PegasCalendarWidgetState extends State<PegasCalendarWidget> {
  late final PegasCalendarSession _localSession;
  late DateTime _selectedDate;
  late DateTime _focusedMonth;

  PegasCalendarSession get _session => widget.session ?? _localSession;

  // Internal data (used when no external data provided)
  List<MechanicJob> _internalJobs = [];
  Map<String, String> _customerNames = {};
  Map<String, String> _bikeNames = {};
  bool _isLoading = true;

  // Selected job details
  MechanicJob? _selectedJob;
  List<MechanicJobItem> _selectedJobItems = [];
  Map<String, String> _productImages = {};
  Customer?
      _selectedCustomerRel; // Full customer object for details (renamed to avoid confusion if any)
  String? _customerName;
  String? _bikeBrand;
  String? _bikeModel;
  bool _loadingDetails = false;
  int _detailLoadGeneration = 0;

  // Bike details view
  Bike? _selectedBike;
  bool _showingBikeDetails = false;
  bool _editingBike = false;

  bool get _useExternalData => widget.jobs != null;

  List<MechanicJob> get _jobs =>
      _useExternalData ? widget.jobs! : _internalJobs;

  // Controllers for bike editing
  late TextEditingController _bikeBrandController;
  late TextEditingController _bikeModelController;
  late TextEditingController _bikeSerialController;
  late TextEditingController _bikeNotesController;
  late TextEditingController _bikeWheelSizeController;
  late TextEditingController _bikeFrameSizeController;
  DateTime? _bikeWarrantyDate;

  @override
  void initState() {
    super.initState();
    _localSession = PegasCalendarSession();
    _selectedDate = _session.selectedDate;
    _focusedMonth = _session.focusedMonth;
    _bikeBrandController = TextEditingController();
    _bikeModelController = TextEditingController();
    _bikeSerialController = TextEditingController();
    _bikeNotesController = TextEditingController();
    _bikeWheelSizeController = TextEditingController();
    _bikeFrameSizeController = TextEditingController();

    if (!_useExternalData) {
      _loadJobs();
    } else {
      _buildLookupMaps();
      _isLoading = false;
    }
  }

  @override
  void didUpdateWidget(PegasCalendarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_useExternalData) {
      _buildLookupMaps();

      // If we have a selected job, check if it was updated in the new jobs list
      if (_selectedJob != null && widget.jobs != null) {
        try {
          final freshJob =
              widget.jobs!.firstWhere((j) => j.id == _selectedJob!.id);
          if (freshJob != _selectedJob) {
            setState(() {
              _selectedJob = freshJob;
            });
            // Refresh details (items) as they might have changed too
            _loadJobDetails(freshJob);
          }
        } catch (_) {
          // Job might have been removed from the list - ignore
        }
      }
    }
  }

  @override
  void dispose() {
    _bikeBrandController.dispose();
    _bikeModelController.dispose();
    _bikeSerialController.dispose();
    _bikeNotesController.dispose();
    _bikeWheelSizeController.dispose();
    _bikeFrameSizeController.dispose();
    super.dispose();
  }

  void _populateBikeControllers() {
    if (_selectedBike == null) return;

    _bikeBrandController.text = _selectedBike!.brand ?? '';
    _bikeModelController.text = _selectedBike!.model ?? '';
    _bikeSerialController.text = _selectedBike!.serialNumber ?? '';
    _bikeNotesController.text = _selectedBike!.notes ?? '';
    _bikeWheelSizeController.text = _selectedBike!.wheelSize ?? '';
    _bikeFrameSizeController.text = _selectedBike!.frameSize ?? '';
    _bikeWarrantyDate = _selectedBike!.warrantyUntil;
  }

  void _buildLookupMaps() {
    if (widget.customers != null) {
      _customerNames = {};
      for (final entry in widget.customers!.entries) {
        _customerNames[entry.key] = entry.value.name;
      }
    }
    if (widget.bikes != null) {
      _bikeNames = {};
      for (final entry in widget.bikes!.entries) {
        final bike = entry.value;
        final bikeName = '${bike.brand ?? ''} ${bike.model ?? ''}'.trim();
        if (bikeName.isNotEmpty) {
          _bikeNames[entry.key] = bikeName;
        }
      }
    }
  }

  Future<void> _loadJobs() async {
    setState(() => _isLoading = true);
    try {
      final bikeshopService = context.read<BikeshopService>();
      final customerService = context.read<CustomerService>();

      final jobs = await bikeshopService.getJobs();
      final customers = await customerService.getCustomersForList();

      final customerNameMap = <String, String>{};
      for (final customer in customers) {
        if (customer.id != null) {
          customerNameMap[customer.id!] = customer.name;
        }
      }

      final bikeNameMap = <String, String>{};
      final bikes = await bikeshopService.getBikes();
      for (final bike in bikes) {
        if (bike.id != null) {
          final bikeName = '${bike.brand ?? ''} ${bike.model ?? ''}'.trim();
          if (bikeName.isNotEmpty) {
            bikeNameMap[bike.id!] = bikeName;
          }
        }
      }

      setState(() {
        _internalJobs = jobs;
        _customerNames = customerNameMap;
        _bikeNames = bikeNameMap;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar trabajos: $e')),
        );
      }
    }
  }

  Future<void> _loadJobDetails(MechanicJob job) async {
    final loadGeneration = ++_detailLoadGeneration;
    setState(() => _loadingDetails = true);
    try {
      final bikeshopService = context.read<BikeshopService>();
      final customerService = !_useExternalData || widget.customers == null
          ? context.read<CustomerService>()
          : null;

      // Load job items
      final items = await bikeshopService.getJobItems(job.id!);

      // Get customer info
      String? customerName;
      Customer? customerRel;

      if (_useExternalData && widget.customers != null) {
        customerRel = widget.customers![job.customerId];
        customerName = customerRel?.name ?? 'Cliente no encontrado';
      } else {
        try {
          customerRel = await customerService!.getCustomerById(job.customerId);
          customerName = customerRel?.name;
        } catch (e) {
          debugPrint('Error fetching customer: $e');
        }
        customerName ??=
            _customerNames[job.customerId] ?? 'Cliente no encontrado';
      }

      // Get bike info
      String? bikeBrand;
      String? bikeModel;
      Bike? loadedBike;
      if (_useExternalData && widget.bikes != null) {
        loadedBike = widget.bikes![job.bikeId];
        bikeBrand = loadedBike?.brand;
        bikeModel = loadedBike?.model;
      } else {
        try {
          if (job.bikeId != null) {
            loadedBike = await bikeshopService.getBikeById(job.bikeId!);
            bikeBrand = loadedBike?.brand;
            bikeModel = loadedBike?.model;
          } else {
            bikeBrand = job.subjectData?.name ?? job.jobType.displayName;
            bikeModel = '';
          }
        } catch (e) {
          bikeBrand = 'Bici no encontrada';
          bikeModel = '';
        }
      }

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

      // Load fresh job data to get updated invoice_id
      final freshJob = await bikeshopService.getJobById(job.id!);
      if (!mounted ||
          loadGeneration != _detailLoadGeneration ||
          _selectedJob?.id != job.id) {
        return;
      }

      setState(() {
        if (freshJob != null) {
          _selectedJob = freshJob;
        }
        _selectedJobItems = items;
        _selectedCustomerRel = customerRel;
        _customerName = customerName;
        _bikeBrand = bikeBrand;
        _bikeModel = bikeModel;
        _selectedBike = loadedBike;
        _productImages = productImages;
        _loadingDetails = false;
      });
    } catch (e) {
      if (!mounted || loadGeneration != _detailLoadGeneration) return;
      setState(() => _loadingDetails = false);
      if (_selectedJob?.id == job.id) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar detalles: $e')),
        );
      }
    }
  }

  bool _isSameDay(DateTime? a, DateTime b) {
    if (a == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<MechanicJob> _getJobsForDate(DateTime date) {
    return _jobs.where((job) {
      // Calendar capacity only includes physically received workshop objects.
      // A standalone quotation has no object in custody and must not reserve a
      // diagnostic/delivery slot; a service budget does have a received bike.
      if (job.isSaleWorkflow || job.isStandaloneQuotation) return false;
      final matchesDelivery = _isSameDay(job.deliveryDeadline, date);
      final matchesDiagnostic = _isSameDay(job.diagnosticDeadline, date);
      return matchesDelivery || matchesDiagnostic;
    }).toList();
  }

  List<MechanicJob> _getJobsForSelectedDate() {
    return _getJobsForDate(_selectedDate);
  }

  /// Gets color for a job - prefers custom status color, falls back to legacy
  Color _getJobColor(MechanicJob job) {
    if (job.isStandaloneQuotation) return _getProposalStatusColor(job);
    if (job.customStatus != null) {
      return job.customStatus!.colorValue;
    }
    return _getStatusColor(job.status);
  }

  Color _getProposalStatusColor(MechanicJob job) {
    return switch (job.effectiveQuotationStatus) {
      QuotationStatus.pending => Colors.orange,
      QuotationStatus.approved => Colors.green,
      QuotationStatus.rejected => Colors.red,
      QuotationStatus.expired => Colors.grey,
    };
  }

  /// Legacy status color mapping - matches database seeded values
  Color _getStatusColor(JobStatus status) {
    switch (status) {
      case JobStatus.pendiente:
        return const Color(0xFF6B7280); // Gray
      case JobStatus.diagnostico:
        return const Color(0xFF3B82F6); // Blue
      case JobStatus.esperandoAprobacion:
        return const Color(0xFFF59E0B); // Amber
      case JobStatus.esperandoRepuestos:
        return const Color(0xFFF97316); // Orange
      case JobStatus.enCurso:
        return const Color(0xFF8B5CF6); // Purple
      case JobStatus.finalizado:
        return const Color(0xFF10B981); // Green
      case JobStatus.entregado:
        return const Color(0xFF06B6D4); // Cyan
      case JobStatus.cancelado:
        return const Color(0xFFEF4444); // Red
    }
  }

  /// Gets status text - prefers custom status name, falls back to legacy
  String _getJobStatusText(MechanicJob job) {
    if (job.isStandaloneQuotation) return job.proposalStatusDisplayName;
    if (job.customStatus != null) {
      return job.customStatus!.name;
    }
    return _getStatusText(job.status);
  }

  bool _isJobCurrentlyDelivered(MechanicJob job) =>
      job.status == JobStatus.entregado ||
      job.customStatus?.triggersDelivery == true ||
      job.customStatus?.code.trim().toLowerCase() == 'entregado';

  String _getStatusText(JobStatus status) {
    switch (status) {
      case JobStatus.pendiente:
        return 'Pendiente';
      case JobStatus.diagnostico:
        return 'Diagnóstico';
      case JobStatus.esperandoAprobacion:
        return 'Esperando Aprobación';
      case JobStatus.esperandoRepuestos:
        return 'Esperando Repuestos';
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

  /// Formats a status timestamp into a compact, localized string
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: BrandedLoading());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final useCompactLayout =
            widget.useCompactLayout ?? constraints.maxWidth < 900;
        if (useCompactLayout) {
          return _buildCompactCalendar(constraints);
        }
        return _buildDesktopCalendar();
      },
    );
  }

  Widget _buildDesktopCalendar() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        key: const ValueKey('workshop-calendar-desktop-split'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Calendar on the left
          Expanded(
            flex: 2,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildMonthHeader(),
                    const SizedBox(height: 16),
                    Expanded(child: _buildCalendarGrid()),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 24),
          // Jobs list on the right
          Expanded(
            flex: 1,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildJobsList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactCalendar(BoxConstraints constraints) {
    if (_selectedJob != null || _showingBikeDetails) {
      return _buildCompactDetailWorkspace(constraints);
    }

    final hasBoundedHeight = constraints.maxHeight.isFinite;
    final availableHeight = hasBoundedHeight ? constraints.maxHeight : 720.0;
    final calendarHeight = availableHeight >= 720
        ? 400.0
        : (availableHeight * 0.58).clamp(240.0, 360.0).toDouble();
    final colorScheme = Theme.of(context).colorScheme;

    final calendar = Card(
      key: const ValueKey('workshop-calendar-compact-month'),
      margin: EdgeInsets.zero,
      elevation: 1,
      color: colorScheme.surfaceContainerLowest,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            _buildCompactMonthHeader(),
            const SizedBox(height: 10),
            Expanded(child: _buildCalendarGrid(compact: true)),
          ],
        ),
      ),
    );

    final agenda = Card(
      key: const ValueKey('workshop-calendar-compact-agenda'),
      margin: EdgeInsets.zero,
      elevation: 1,
      color: colorScheme.surfaceContainerLowest,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: _buildJobsList(compact: true),
      ),
    );

    final content = Column(
      key: const ValueKey('workshop-calendar-compact-stack'),
      children: [
        SizedBox(height: calendarHeight, child: calendar),
        const SizedBox(height: 12),
        if (hasBoundedHeight)
          Expanded(child: agenda)
        else
          SizedBox(height: 360, child: agenda),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: hasBoundedHeight
          ? content
          : SingleChildScrollView(
              child: SizedBox(
                height: calendarHeight + 372,
                child: content,
              ),
            ),
    );
  }

  Widget _buildCompactDetailWorkspace(BoxConstraints constraints) {
    final hasBoundedHeight = constraints.maxHeight.isFinite;
    final colorScheme = Theme.of(context).colorScheme;
    final workspace = Card(
      key: const ValueKey('workshop-calendar-compact-detail-workspace'),
      margin: EdgeInsets.zero,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      color: colorScheme.surfaceContainerLowest,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: _buildJobsList(compact: true),
      ),
    );

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: hasBoundedHeight
            ? workspace
            : SizedBox(height: 720, child: workspace),
      ),
    );
  }

  Widget _buildCompactMonthHeader() {
    final colorScheme = Theme.of(context).colorScheme;
    final month = DateFormat('MMMM yyyy', 'es').format(_focusedMonth);
    final monthLabel = '${month[0].toUpperCase()}${month.substring(1)}';

    return Material(
      color: colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              color: colorScheme.onSurfaceVariant,
              tooltip: 'Mes anterior',
              onPressed: () {
                setState(() {
                  _focusedMonth =
                      DateTime(_focusedMonth.year, _focusedMonth.month - 1);
                  _session.focusedMonth = _focusedMonth;
                });
              },
            ),
            Expanded(
              child: Text(
                monthLabel,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              color: colorScheme.onSurfaceVariant,
              tooltip: 'Mes siguiente',
              onPressed: () {
                setState(() {
                  _focusedMonth =
                      DateTime(_focusedMonth.year, _focusedMonth.month + 1);
                  _session.focusedMonth = _focusedMonth;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A3A5C), // VinaBike navy blue
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white),
            onPressed: () {
              setState(() {
                _focusedMonth =
                    DateTime(_focusedMonth.year, _focusedMonth.month - 1);
                _session.focusedMonth = _focusedMonth;
              });
            },
          ),
          Text(
            DateFormat('MMMM yyyy', 'es').format(_focusedMonth),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Colors.white),
            onPressed: () {
              setState(() {
                _focusedMonth =
                    DateTime(_focusedMonth.year, _focusedMonth.month + 1);
                _session.focusedMonth = _focusedMonth;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid({bool compact = false}) {
    final firstDayOfMonth =
        DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final lastDayOfMonth =
        DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    final daysInMonth = lastDayOfMonth.day;
    final firstWeekday = firstDayOfMonth.weekday - 1; // Monday = 0

    return Column(
      children: [
        // Weekday headers
        Row(
          children: ['L', 'M', 'M', 'J', 'V', 'S', 'D']
              .map((day) => Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
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
                        key: ValueKey(
                          'workshop-calendar-day-'
                          '${DateFormat('yyyy-MM-dd').format(date)}',
                        ),
                        onTap: () {
                          setState(() {
                            _selectedDate = date;
                            _session.selectedDate = date;
                            _selectedJob = null;
                            _detailLoadGeneration++;
                          });
                        },
                        child: Container(
                          margin: EdgeInsets.all(compact ? 1 : 2),
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
                                    width: 2)
                                : isSelected
                                    ? Border.all(
                                        color: Theme.of(context).primaryColor,
                                        width: 1)
                                    : null,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: EdgeInsets.all(compact ? 2 : 4),
                                child: Text(
                                  '$dayNumber',
                                  style: TextStyle(
                                    fontSize: compact ? 11 : 12,
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
                              // Jobs on this day
                              if (compact && jobsOnDay.isNotEmpty)
                                _buildCompactDayLoad(jobsOnDay)
                              else if (jobsOnDay.isNotEmpty)
                                Expanded(
                                  child: ListView.builder(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4),
                                    itemCount: jobsOnDay.length,
                                    itemBuilder: (context, index) {
                                      final job = jobsOnDay[index];
                                      final customerName =
                                          _customerNames[job.customerId] ??
                                              'Cliente';
                                      final statusColor = _getJobColor(job);

                                      // Determine which deadline matches current cell date
                                      final isDiagnostic = _isSameDay(
                                          job.diagnosticDeadline, date);
                                      // If both match, delivery takes precedence for icon, or we could show both?
                                      // Let's use specific icons.
                                      final icon = isDiagnostic
                                          ? Icons.search
                                          : Icons.local_shipping_outlined;

                                      return InkWell(
                                        onTap: () async {
                                          setState(() {
                                            _selectedDate = date;
                                            _session.selectedDate = date;
                                            _selectedJob = job;
                                            _loadingDetails = true;
                                          });
                                          await _loadJobDetails(job);
                                        },
                                        borderRadius: BorderRadius.circular(4),
                                        child: Container(
                                          margin:
                                              const EdgeInsets.only(bottom: 2),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 4, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: statusColor.withValues(
                                                alpha: 0.2),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(icon,
                                                  size: 10,
                                                  color: statusColor.withValues(
                                                      alpha: 0.9)),
                                              const SizedBox(width: 2),
                                              Expanded(
                                                child: Text(
                                                  customerName,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: statusColor
                                                        .withValues(alpha: 0.9),
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
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

  Widget _buildCompactDayLoad(List<MechanicJob> jobs) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: _getJobColor(jobs.first),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              '${jobs.length}',
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJobsList({bool compact = false}) {
    final jobsForDate = _getJobsForSelectedDate();
    final dateFormat = DateFormat('EEEE, d MMMM yyyy', 'es');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (compact)
          _buildCompactJobsHeader(dateFormat)
        else
          _buildDesktopJobsHeader(dateFormat),
        const SizedBox(height: 16),
        if (_showingBikeDetails && _selectedBike != null)
          Expanded(child: _buildBikeDetails(_selectedBike!))
        else if (_selectedJob != null)
          Expanded(
            child: _buildJobDetails(
              _selectedJob!,
              compact: compact,
            ),
          )
        else if (jobsForDate.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.event_busy,
                    size: compact ? 36 : 64,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.3),
                  ),
                  SizedBox(height: compact ? 8 : 16),
                  Text(
                    'No hay trabajos programados',
                    textAlign: TextAlign.center,
                    maxLines: compact ? 2 : null,
                    overflow: compact ? TextOverflow.ellipsis : null,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
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

  void _returnFromCalendarDetail() {
    setState(() {
      if (_showingBikeDetails) {
        _showingBikeDetails = false;
        _editingBike = false;
      } else {
        _selectedJob = null;
        _detailLoadGeneration++;
      }
    });
  }

  Widget _buildCompactJobsHeader(DateFormat dateFormat) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasDetail = _selectedJob != null || _showingBikeDetails;
    final jobNumber = _selectedJob?.jobNumber;
    final title = _showingBikeDetails
        ? (_selectedBike?.displayName ?? 'Bicicleta')
        : _selectedJob != null
            ? (jobNumber == null ? 'Trabajo' : 'Trabajo $jobNumber')
            : dateFormat.format(_selectedDate);
    final subtitle = _showingBikeDetails
        ? (jobNumber == null
            ? 'Detalle de bicicleta'
            : 'Bicicleta · $jobNumber')
        : _selectedJob != null
            ? DateFormat('d MMM yyyy', 'es').format(_selectedDate)
            : null;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          if (hasDetail)
            SizedBox.square(
              dimension: 48,
              child: IconButton(
                key: const ValueKey('workshop-calendar-compact-back'),
                icon: const Icon(Icons.arrow_back),
                color: colorScheme.onSurfaceVariant,
                onPressed: _returnFromCalendarDetail,
                tooltip: _showingBikeDetails
                    ? 'Volver al trabajo'
                    : 'Volver al calendario',
              ),
            ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  key: const ValueKey(
                    'workshop-calendar-compact-workspace-title',
                  ),
                  maxLines: hasDetail ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
              ],
            ),
          ),
          if (_showingBikeDetails)
            SizedBox.square(
              dimension: 48,
              child: IconButton(
                icon: Icon(_editingBike ? Icons.close : Icons.edit),
                onPressed: () {
                  if (_editingBike) {
                    setState(() => _editingBike = false);
                  } else {
                    _populateBikeControllers();
                    setState(() => _editingBike = true);
                  }
                },
                tooltip: _editingBike ? 'Cancelar edición' : 'Editar bicicleta',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDesktopJobsHeader(DateFormat dateFormat) {
    return Row(
      children: [
        if (_selectedJob != null || _showingBikeDetails)
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _returnFromCalendarDetail,
            tooltip:
                _showingBikeDetails ? 'Volver al trabajo' : 'Volver a la lista',
          ),
        Expanded(
          child: Text(
            _showingBikeDetails
                ? 'Detalles de la Bicicleta'
                : _selectedJob != null
                    ? 'Detalles del Trabajo'
                    : dateFormat.format(_selectedDate),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        if (_showingBikeDetails && !_editingBike)
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              _populateBikeControllers();
              setState(() => _editingBike = true);
            },
            tooltip: 'Editar bicicleta',
          ),
        if (_showingBikeDetails && _editingBike)
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _editingBike = false),
            tooltip: 'Cancelar edición',
          ),
      ],
    );
  }

  Widget _buildJobCard(MechanicJob job) {
    final statusColor = _getJobColor(job);
    final proposalStatusColor = _getProposalStatusColor(job);
    final customerName = _customerNames[job.customerId] ?? 'Cliente';
    final bikeName = _bikeNames[job.bikeId];
    final objectLabel = job.isComponentIntake
        ? (job.subjectDisplayName ?? 'Componente recibido')
        : bikeName ?? job.jobNumber ?? 'Sin #';

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
                      objectLabel,
                      style: const TextStyle(fontWeight: FontWeight.bold),
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
                        .withValues(alpha: 0.4),
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
                          .withValues(alpha: 0.7),
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (job.isServiceBudget) ...[
                const SizedBox(height: 4),
                Text(
                  job.proposalStatusDisplayName,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: proposalStatusColor,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
              if (job.clientRequest != null) ...[
                const SizedBox(height: 8),
                Text(
                  job.clientRequest!,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              // Diagnostic Deadline
              if (job.diagnosticDeadline != null) ...[
                const SizedBox(height: 4),
                _buildDeadlineRow(
                  icon: Icons.search,
                  label: 'Diagnóstico',
                  date: job.diagnosticDeadline!,
                  isHighlighted:
                      _isSameDay(job.diagnosticDeadline, _selectedDate),
                  isOverdue: job.diagnosticDeadline!.isBefore(DateTime.now()) &&
                      job.diagnosticSentAt == null,
                ),
              ],

              // Delivery Deadline
              if (job.deliveryDeadline != null) ...[
                const SizedBox(height: 4),
                _buildDeadlineRow(
                  icon: Icons.local_shipping_outlined,
                  label: 'Entrega',
                  date: job.deliveryDeadline!,
                  isHighlighted:
                      _isSameDay(job.deliveryDeadline, _selectedDate),
                  isOverdue: job.deliveryDeadline!.isBefore(DateTime.now()) &&
                      !_isJobCurrentlyDelivered(job),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeadlineRow({
    required IconData icon,
    required String label,
    required DateTime date,
    required bool isHighlighted,
    required bool isOverdue,
  }) {
    final theme = Theme.of(context);
    final baseColor = isHighlighted
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final color = isOverdue ? Colors.red : baseColor;
    final fontWeight =
        isHighlighted || isOverdue ? FontWeight.bold : FontWeight.normal;

    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            '$label: ${DateFormat('dd/MM HH:mm').format(date)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: fontWeight,
            ),
          ),
        ),
        if (isHighlighted) ...[
          const SizedBox(width: 4),
          Icon(Icons.arrow_back, size: 12, color: color),
        ],
      ],
    );
  }

  Widget _buildJobDetails(
    MechanicJob job, {
    bool compact = false,
  }) {
    // Determine initial index based on what we want to focus on
    // Default to details (0)
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          // SMART HEADER (Always visible)
          _buildSmartHeader(job, compact: compact),

          // TABS
          TabBar(
            labelColor: const Color(0xFF1A3A5C), // VinaBike Navy
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFFE65100), // VinaBike Orange
            tabs: [
              const Tab(text: 'Info', icon: Icon(Icons.info_outline, size: 18)),
              const Tab(text: 'Tareas', icon: Icon(Icons.checklist, size: 18)),
              Tab(
                text: job.isQuotationWorkflow
                    ? job.proposalDocumentLabel
                    : 'Factura',
                icon: Icon(
                  job.isQuotationWorkflow
                      ? Icons.request_quote_outlined
                      : Icons.receipt_long,
                  size: 18,
                ),
              ),
            ],
          ),

          // CONTENT
          Expanded(
            child: TabBarView(
              children: [
                _buildInfoTab(job, compact: compact),
                _buildTasksTab(job),
                job.isQuotationWorkflow
                    ? _buildProposalSummaryTab(job)
                    : _buildInvoiceTab(job),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmartHeader(
    MechanicJob job, {
    bool compact = false,
  }) {
    final statusColor = _getJobColor(job);
    final statusText = _getJobStatusText(job);
    final proposalStatusColor = _getProposalStatusColor(job);
    final serviceWarrantyText = _serviceWarrantyText(job);

    // Determine "Next Action" based on status
    // Logic:
    // Pendiente -> Diagnosticar
    // Diagnostico -> Enviar Presupuesto (Whatsapp)
    // Esperando Aprobacion -> Aprobar (Starts job)
    // En Curso -> Terminar
    // Finalizado -> Entregar

    String actionLabel = '';
    IconData actionIcon = Icons.arrow_forward;
    VoidCallback? onAction;
    Color actionColor = const Color(0xFFE65100); // Default Orange

    // Only records with a physical workshop intake expose operational next
    // actions. A service budget therefore keeps this lifecycle; a standalone
    // quotation does not.
    if (!job.isStandaloneQuotation && !job.isSaleWorkflow) {
      if (job.status == JobStatus.pendiente) {
        actionLabel = 'Comenzar Diagnóstico';
        actionIcon = Icons.search;
        onAction = () => _changeJobStatus(
            job,
            _findStatusByCode('DIAGNOSTICO') ??
                JobStatusCustom(
                    tenantId: '',
                    name: 'Diagnóstico',
                    code: 'DIAGNOSTICO',
                    id: ''));
      } else if (job.status == JobStatus.diagnostico) {
        actionLabel = 'Enviar Presupuesto';
        actionIcon = Icons.send; // WhatsApp icon ideally
        actionColor = const Color(0xFF25D366); // WhatsApp Green
        // Action: Send message (implemented later)
      } else if (job.status == JobStatus.esperandoAprobacion) {
        actionLabel = 'Aprobar y Comenzar';
        actionIcon = Icons.play_arrow;
        actionColor = Colors.green;
        onAction = () => _changeJobStatus(
            job,
            _findStatusByCode('EN_CURSO') ??
                JobStatusCustom(
                    tenantId: '', name: 'En Curso', code: 'EN_CURSO', id: ''));
      } else if (job.status == JobStatus.enCurso) {
        actionLabel = 'Terminar Trabajo';
        actionIcon = Icons.check_circle;
        actionColor = Colors.blue;
        onAction = () => _changeJobStatus(
            job,
            _findStatusByCode('FINALIZADO') ??
                JobStatusCustom(
                    tenantId: '',
                    name: 'Finalizado',
                    code: 'FINALIZADO',
                    id: ''));
      } else if (job.status == JobStatus.finalizado) {
        actionLabel = job.isComponentIntake
            ? 'Entregar Componente'
            : 'Entregar Bicicleta';
        actionIcon = Icons.handshake;
        actionColor = Colors.purple;
        onAction = () => _changeJobStatus(
            job,
            _findStatusByCode('ENTREGADO') ??
                JobStatusCustom(
                    tenantId: '',
                    name: 'Entregado',
                    code: 'ENTREGADO',
                    id: ''));
      }
    }

    if (compact) {
      return _buildCompactSmartHeader(
        job: job,
        statusColor: statusColor,
        statusText: statusText,
        proposalStatusColor: proposalStatusColor,
        serviceWarrantyText: serviceWarrantyText,
        actionLabel: actionLabel,
        actionIcon: actionIcon,
        actionColor: actionColor,
        onAction: onAction,
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        border: Border(
            bottom: BorderSide(color: statusColor.withValues(alpha: 0.3))),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // A standalone quotation has only a commercial lifecycle. A
              // service budget keeps the normal workshop status control below
              // and receives a separate commercial chip beside it.
              if (job.isStandaloneQuotation)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor, width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
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
                      Text(
                        statusText.toUpperCase(),
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                )
              else
                PopupMenuButton<JobStatusCustom>(
                  onSelected: (newStatus) => _changeJobStatus(job, newStatus),
                  itemBuilder: (ctx) {
                    final jobStatusService = ctx.read<JobStatusService>();
                    return jobStatusService.statuses.map((status) {
                      final isSelected = job.statusId == status.id;
                      return PopupMenuItem<JobStatusCustom>(
                        value: status,
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: status.colorValue,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                status.name,
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isSelected ? status.colorValue : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList();
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor, width: 1.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
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
                        Text(
                          statusText.toUpperCase(),
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_drop_down,
                            size: 18, color: statusColor),
                      ],
                    ),
                  ),
                ),
              if (job.isServiceBudget)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: proposalStatusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: proposalStatusColor.withValues(alpha: 0.55),
                      ),
                    ),
                    child: Text(
                      job.proposalStatusDisplayName,
                      style: TextStyle(
                        color: proposalStatusColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              if (serviceWarrantyText != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shield_outlined,
                          size: 12, color: Color(0xFF047857)),
                      const SizedBox(width: 3),
                      Text(
                        serviceWarrantyText,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF047857),
                        ),
                      ),
                    ],
                  ),
                ),
              if (!job.isStandaloneQuotation && job.statusUpdatedAt != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Text(
                    _formatStatusTimestamp(job.statusUpdatedAt!),
                    style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
                  ),
                ),
              const Spacer(),
              // JOB ID
              Text(
                job.jobNumber ?? 'Sin #',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          if (actionLabel.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onAction, // Can be null if implemented later
                icon: Icon(actionIcon, size: 18),
                label: Text(actionLabel),
                style: ElevatedButton.styleFrom(
                  backgroundColor: actionColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactSmartHeader({
    required MechanicJob job,
    required Color statusColor,
    required String statusText,
    required Color proposalStatusColor,
    required String? serviceWarrantyText,
    required String actionLabel,
    required IconData actionIcon,
    required Color actionColor,
    required VoidCallback? onAction,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusLabel = statusText.toUpperCase();
    final statusContent = Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
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
              statusLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
          if (!job.isStandaloneQuotation) ...[
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 18, color: statusColor),
          ],
        ],
      ),
    );

    final statusControl = job.isStandaloneQuotation
        ? statusContent
        : PopupMenuButton<JobStatusCustom>(
            key: const ValueKey('workshop-calendar-compact-status'),
            tooltip: 'Cambiar estado',
            onSelected: (newStatus) => _changeJobStatus(job, newStatus),
            itemBuilder: (ctx) {
              final jobStatusService = ctx.read<JobStatusService>();
              return jobStatusService.statuses.map((status) {
                final isSelected = job.statusId == status.id;
                return PopupMenuItem<JobStatusCustom>(
                  value: status,
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: status.colorValue,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          status.name,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected ? status.colorValue : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList();
            },
            child: statusContent,
          );

    return Container(
      key: const ValueKey('workshop-calendar-compact-job-header'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.06),
        border: Border(
          bottom: BorderSide(
            color: statusColor.withValues(alpha: 0.25),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: statusControl),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  job.jobNumber ?? 'Sin #',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          if (job.isServiceBudget ||
              serviceWarrantyText != null ||
              (!job.isStandaloneQuotation && job.statusUpdatedAt != null)) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (job.isServiceBudget)
                  Text(
                    job.proposalStatusDisplayName,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: proposalStatusColor,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                if (serviceWarrantyText != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        size: 14,
                        color: Color(0xFF047857),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        serviceWarrantyText,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: const Color(0xFF047857),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                if (!job.isStandaloneQuotation && job.statusUpdatedAt != null)
                  Text(
                    _formatStatusTimestamp(job.statusUpdatedAt!),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
              ],
            ),
          ],
          if (actionLabel.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: onAction,
                icon: Icon(actionIcon, size: 18),
                label: Text(
                  actionLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: actionColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String? _serviceWarrantyText(MechanicJob job) {
    final warranty = job.serviceWarranty;
    if (warranty == null || warranty.state == ServiceWarrantyState.notStarted) {
      return null;
    }
    if (warranty.state == ServiceWarrantyState.active) {
      final days = warranty.daysRemaining;
      return days == 0 ? 'Garantía vence hoy' : 'Garantía ${days ?? '-'}d';
    }
    final expiry = warranty.warrantyExpiresAt;
    return expiry == null
        ? 'Garantía vencida'
        : 'Venció ${DateFormat('dd/MM').format(expiry.toLocal())}';
  }

  // Helper to find status by code
  JobStatusCustom? _findStatusByCode(String code) {
    try {
      final jobStatusService = context.read<JobStatusService>();
      return jobStatusService.statuses.firstWhere((s) => s.code == code);
    } catch (e) {
      return null;
    }
  }

  Widget _buildInfoTab(
    MechanicJob job, {
    bool compact = false,
  }) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        compact ? 4 : 16,
        compact ? 12 : 16,
        compact ? 4 : 16,
        16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Received object - bicycle or loose component.
          if (job.isComponentIntake)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.build_outlined,
                      size: 28, color: Colors.blue.shade800),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'COMPONENTE RECIBIDO',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          job.subjectDisplayName ?? 'Componente recibido',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else if (_bikeBrand != null || _bikeModel != null)
            InkWell(
              onTap: () {
                if (_selectedBike != null) {
                  setState(() => _showingBikeDetails = true);
                }
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.pedal_bike,
                        size: 28, color: Colors.blue.shade800),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bicicleta',
                            style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${_bikeBrand ?? ''} ${_bikeModel ?? ''}'.trim(),
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87),
                          ),
                          if (_selectedBike?.serialNumber != null)
                            Text('Serie: ${_selectedBike!.serialNumber}',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.grey),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 16),

          // Customer Card with WhatsApp
          if (_customerName != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.blue.shade100,
                    child: Text(_customerName![0].toUpperCase(),
                        style: TextStyle(color: Colors.blue.shade800)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cliente',
                          style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _customerName!,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87),
                        ),
                        // Phone would go here if available in local map
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const FaIcon(FontAwesomeIcons.whatsapp,
                        size: 20, color: Color(0xFF25D366)),
                    onPressed: () {
                      if (_selectedCustomerRel?.phone != null) {
                        _openWhatsApp(context, _selectedCustomerRel!.phone!);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Sin teléfono registrado')));
                      }
                    },
                    tooltip: 'Contactar por WhatsApp',
                  ),
                ],
              ),
            ),

          const SizedBox(height: 24),

          if (compact)
            Column(
              children: [
                _buildCompactDeadlineAction(
                  key: const ValueKey(
                    'workshop-calendar-compact-diagnostic-deadline',
                  ),
                  icon: Icons.search,
                  label: 'Diagnóstico',
                  date: job.diagnosticDeadline,
                  color: Colors.blue.shade700,
                  onTap: () => _editDeadline(job, isDiagnostic: true),
                ),
                const SizedBox(height: 8),
                _buildCompactDeadlineAction(
                  key: const ValueKey(
                    'workshop-calendar-compact-delivery-deadline',
                  ),
                  icon: Icons.local_shipping_outlined,
                  label: 'Entrega',
                  date: job.deliveryDeadline,
                  color: Colors.red.shade700,
                  onTap: () => _editDeadline(job, isDiagnostic: false),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _editDeadline(job, isDiagnostic: true),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('DIAGNÓSTICO',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade600)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.search,
                                size: 16, color: Colors.blue.shade700),
                            const SizedBox(width: 4),
                            Text(
                              job.diagnosticDeadline != null
                                  ? DateFormat('dd/MM HH:mm')
                                      .format(job.diagnosticDeadline!)
                                  : 'Sin fecha',
                              style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => _editDeadline(job, isDiagnostic: false),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ENTREGA',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade600)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.local_shipping_outlined,
                                size: 16, color: Colors.red.shade700),
                            const SizedBox(width: 4),
                            Text(
                              job.deliveryDeadline != null
                                  ? DateFormat('dd/MM HH:mm')
                                      .format(job.deliveryDeadline!)
                                  : 'Sin fecha',
                              style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

          const Divider(height: 32),

          // Request & Notes
          // SMART EDITOR for Request, Diagnosis, Work, Notes
          if (compact)
            _CompactJobDetailsEditor(
              key: ValueKey('workshop-calendar-compact-editor-${job.id}'),
              job: job,
              readOnly: job.hasFinalProposalDecision,
              onSave: ({clientRequest, diagnosis, workPerformed, notes}) async {
                final saved = await _saveJobDetailFields(
                  job,
                  clientRequest: clientRequest,
                  diagnosis: diagnosis,
                  workPerformed: workPerformed,
                  notes: notes,
                );
                if (saved && mounted) {
                  _returnFromCalendarDetail();
                }
                return saved;
              },
            )
          else
            SmartJobDetailsEditor(
              isInline: true,
              readOnly: job.hasFinalProposalDecision,
              job: job,
              invoice:
                  null, // Calendar doesn't load full invoice usually, or we can fetch it if needed
              customerName: _customerName,
              bikeName: job.isComponentIntake
                  ? (job.subjectDisplayName ?? 'Componente recibido')
                  : '${_bikeBrand ?? ''} ${_bikeModel ?? ''}'.trim(),
              clientRequest: job.clientRequest,
              diagnosis: job.diagnosis,
              workPerformed: job.workPerformed,
              notes: job.notes,
              onSave: ({clientRequest, diagnosis, workPerformed, notes}) async {
                await _saveJobDetailFields(
                  job,
                  clientRequest: clientRequest,
                  diagnosis: diagnosis,
                  workPerformed: workPerformed,
                  notes: notes,
                );
              },
            ),

          SizedBox(height: compact ? 24 : 100),

          // Items Section (ReadOnly Summary)
          if (_selectedJobItems.isNotEmpty) ...[
            const Divider(),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.shopping_cart,
                    size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Repuestos y Servicios (Resumen)',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._selectedJobItems.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      if (item.productId != null &&
                          _productImages.containsKey(item.productId))
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _HoverImageWidget(
                            imageUrl: _productImages[item.productId]!,
                            size: 32,
                          ),
                        ),
                      Expanded(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('• ${item.productName}',
                              style: const TextStyle(fontSize: 13)),
                          if (item.notes != null && item.notes!.isNotEmpty)
                            Text(
                              item.notes!,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      )),
                      Text(
                        '\$${item.totalPrice.toStringAsFixed(0)}',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                )),
          ],

          if (_loadingDetails)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: BrandedLoading(size: 20))),
        ],
      ),
    );
  }

  Widget _buildCompactDeadlineAction({
    required Key key,
    required IconData icon,
    required String label,
    required DateTime? date,
    required Color color,
    required VoidCallback onTap,
  }) {
    final formattedDate =
        date == null ? 'Sin fecha' : DateFormat('dd/MM HH:mm').format(date);

    return Material(
      color: color.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    formattedDate,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.edit_calendar_outlined, size: 18, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _saveJobDetailFields(
    MechanicJob job, {
    String? clientRequest,
    String? diagnosis,
    String? workPerformed,
    String? notes,
  }) async {
    try {
      final updatedJob = job.copyWith(
        clientRequest: clientRequest,
        diagnosis: diagnosis,
        workPerformed: workPerformed,
        notes: notes,
      );

      await context.read<BikeshopService>().updateJob(updatedJob);
      if (!mounted) return false;

      setState(() {
        _selectedJob = updatedJob;
        if (!_useExternalData) {
          final index = _internalJobs.indexWhere((item) => item.id == job.id);
          if (index != -1) {
            _internalJobs[index] = updatedJob;
          }
        }
      });
      widget.onRefreshNeeded?.call();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cambios guardados'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ),
      );
      return true;
    } catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar: $error'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
  }

  // Placeholder for Tasks Tab - we need to import TasksTabView
  Widget _buildTasksTab(MechanicJob job) {
    if (job.id == null) {
      return const Center(child: Text('Error: Job ID is null'));
    }

    // If we are viewing the selected job, pass the already loaded items to avoid re-fetching
    // This also ensures that when an invoice is saved (and _selectedJobItems refreshed), the tasks tab updates immediately.
    final List<MechanicJobItem>? jobItems =
        (job.id == _selectedJob?.id) ? _selectedJobItems : null;
    final proposalIsFinal = job.hasFinalProposalDecision;

    return TasksTabView(
      jobId: job.id!,
      readOnly: proposalIsFinal,
      externalItems: jobItems,
      onItemAdded: proposalIsFinal
          ? null
          : (item) {
              // Refresh items if needed
              if (!_useExternalData) {
                _loadJobDetails(job); // Reload details to update local state
              }
            },
      onItemRemoved: proposalIsFinal
          ? null
          : (itemId) {
              if (!_useExternalData) {
                _loadJobDetails(job);
              }
            },
    );
  }

  // Placeholder for Invoice Tab - we need to import SalesInvoiceEditor
  Widget _buildInvoiceTab(MechanicJob job) {
    if (job.id == null) return const SizedBox.shrink();

    return SalesInvoiceEditor(
      invoiceId: job.invoiceId,
      preselectedJobId: job.id,
      preselectedCustomerId: job.customerId,
      isCompact: true,
      onSaved: () {
        // Refresh job to get the new invoice link
        if (_useExternalData) {
          widget.onRefreshNeeded?.call();
        } else {
          _loadJobs(); // Reloads the calendar list
          // Also reload details to get the invoiceId
          _loadJobDetails(job);
        }
      },
    );
  }

  Widget _buildProposalSummaryTab(MechanicJob job) {
    final statusColor = _getProposalStatusColor(job);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            job.proposalDocumentLabel,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: statusColor.withValues(alpha: 0.4)),
            ),
            child: Text(
              job.proposalStatusDisplayName,
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            NumberFormat.currency(symbol: '\$', decimalDigits: 0)
                .format(job.totalCost),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.w700,
                ),
          ),
          Text(
            job.isServiceBudget ? 'Total presupuestado' : 'Total cotizado',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          Text(
            job.isServiceBudget
                ? 'Este presupuesto aún no ha generado una factura. Apruébalo y factúralo desde la tabla de trabajos para conservar la bicicleta, su ficha, diagnóstico y líneas.'
                : 'Esta cotización aún no ha generado una factura. Gestiónala desde la tabla de trabajos.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Future<void> _editDeadline(MechanicJob job,
      {bool isDiagnostic = false}) async {
    final currentDeadline =
        isDiagnostic ? job.diagnosticDeadline : job.deliveryDeadline;

    final selectedDate = await showDatePicker(
      context: context,
      initialDate: currentDeadline ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('es', 'CL'),
    );
    if (selectedDate == null) return;
    if (!mounted) return;

    final selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(currentDeadline ?? DateTime.now()),
    );
    if (selectedTime == null) return;
    if (!mounted) return;

    final newDeadline = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );

    try {
      final bikeshopService = context.read<BikeshopService>();
      final updatedJob = isDiagnostic
          ? job.copyWith(diagnosticDeadline: newDeadline)
          : job.copyWith(deliveryDeadline: newDeadline);

      await bikeshopService.updateJob(updatedJob);

      // Refresh data
      if (_useExternalData) {
        widget.onRefreshNeeded?.call();
      } else {
        await _loadJobs();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Fecha de ${isDiagnostic ? 'diagnóstico' : 'entrega'} actualizada'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al actualizar: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Callback when a new status is selected from the popup menu
  Future<void> _changeJobStatus(
      MechanicJob job, JobStatusCustom newStatus) async {
    if (newStatus.id == job.statusId) return;

    try {
      await context.read<BikeshopService>().transitionJobStatus(
            job.id!,
            newStatus.id!,
            operationKey: const Uuid().v4(),
          );
      if (_useExternalData) {
        widget.onRefreshNeeded?.call();
      } else {
        await _loadJobs();
      }
      if (mounted) {
        final refreshed = _jobs.where((item) => item.id == job.id).firstOrNull;
        if (refreshed != null) setState(() => _selectedJob = refreshed);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Estado cambiado a ${newStatus.name}'),
            backgroundColor: newStatus.colorValue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cambiar estado: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveBikeChanges() async {
    if (_selectedBike == null) return;

    final bikeshopService = context.read<BikeshopService>();
    final updatedBike = Bike(
      id: _selectedBike!.id,
      tenantId: _selectedBike!.tenantId,
      customerId: _selectedBike!.customerId,
      brand: _bikeBrandController.text,
      model: _bikeModelController.text,
      serialNumber: _bikeSerialController.text.isEmpty
          ? null
          : _bikeSerialController.text,
      notes:
          _bikeNotesController.text.isEmpty ? null : _bikeNotesController.text,
      wheelSize: _bikeWheelSizeController.text.isEmpty
          ? null
          : _bikeWheelSizeController.text,
      frameSize: _bikeFrameSizeController.text.isEmpty
          ? null
          : _bikeFrameSizeController.text,
      warrantyUntil: _bikeWarrantyDate,
      // Preserve other fields
      brandId: _selectedBike!.brandId,
      modelId: _selectedBike!.modelId,
      year: _selectedBike!.year,
      color: _selectedBike!.color,
      bikeType: _selectedBike!.bikeType,
      frontHubSpacingMm: _selectedBike!.frontHubSpacingMm,
      rearHubSpacingMm: _selectedBike!.rearHubSpacingMm,
      spokeCount: _selectedBike!.spokeCount,
      factoryRimId: _selectedBike!.factoryRimId,
      purchaseDate: _selectedBike!.purchaseDate,
      purchasePrice: _selectedBike!.purchasePrice,
      qrCode: _selectedBike!.qrCode,
      imageUrl: _selectedBike!.imageUrl,
      imageUrls: _selectedBike!.imageUrls,
      isActive: _selectedBike!.isActive,
      createdAt: _selectedBike!.createdAt,
      updatedAt: DateTime.now(),
    );

    try {
      // Since updateBike might return void or Bike, we just await it
      // Assuming updateBike exists in BikeshopService based on bike_form_dialog.dart usage
      await bikeshopService.updateBike(updatedBike);

      setState(() {
        _selectedBike = updatedBike;
        _bikeBrand = updatedBike.brand;
        _bikeModel = updatedBike.model;
        _editingBike = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bicicleta actualizada correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Refresh list if needed
      if (!_useExternalData) {
        _loadJobs();
      } else {
        widget.onRefreshNeeded?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar cambios: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildBikeEditForm(Bike bike) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _bikeBrandController,
                  decoration: const InputDecoration(
                    labelText: 'Marca',
                    prefixIcon: Icon(Icons.branding_watermark, size: 20),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _bikeModelController,
                  decoration: const InputDecoration(
                    labelText: 'Modelo',
                    prefixIcon: Icon(Icons.directions_bike, size: 20),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _bikeSerialController,
                  decoration: const InputDecoration(
                    labelText: 'Número de Serie',
                    prefixIcon: Icon(Icons.qr_code, size: 20),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Especificaciones',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _bikeWheelSizeController,
                        decoration: const InputDecoration(
                          labelText: 'Aro',
                          prefixIcon: Icon(Icons.trip_origin, size: 20),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _bikeFrameSizeController,
                        decoration: const InputDecoration(
                          labelText: 'Talla',
                          prefixIcon: Icon(Icons.straighten, size: 20),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Garantía',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _bikeWarrantyDate ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (date != null) {
                setState(() => _bikeWarrantyDate = date);
              }
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outline
                        .withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Vencimiento de garantía',
                            style: Theme.of(context).textTheme.bodySmall),
                        Text(
                          _bikeWarrantyDate != null
                              ? DateFormat('dd/MM/yyyy')
                                  .format(_bikeWarrantyDate!)
                              : 'Sin garantía',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                  if (_bikeWarrantyDate != null)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _bikeWarrantyDate = null),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Notas',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _bikeNotesController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Notas adicionales...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saveBikeChanges,
              icon: const Icon(Icons.save),
              label: const Text('Guardar Cambios'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the bike details view shown in the same panel
  Widget _buildBikeDetails(Bike bike) {
    if (_editingBike) {
      return _buildBikeEditForm(bike);
    }

    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bike header with icon
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.pedal_bike,
                    size: 32,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bike.displayName,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (bike.bikeType != null) ...[
                        const SizedBox(height: 4),
                        Chip(
                          label: Text(bike.bikeType!.displayName),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: theme.colorScheme.secondary
                              .withValues(alpha: 0.2),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Bike brand & model
          _buildBikeDetailItem(
            icon: Icons.branding_watermark,
            label: 'Marca',
            value: (bike.brand?.isNotEmpty ?? false)
                ? bike.brand!
                : 'No especificada',
          ),
          _buildBikeDetailItem(
            icon: Icons.directions_bike,
            label: 'Modelo',
            value: (bike.model?.isNotEmpty ?? false)
                ? bike.model!
                : 'No especificado',
          ),

          // Serial number
          if (bike.serialNumber != null && bike.serialNumber!.isNotEmpty) ...[
            _buildBikeDetailItem(
              icon: Icons.qr_code,
              label: 'Número de serie',
              value: bike.serialNumber!,
            ),
          ],

          // Wheel size
          if (bike.wheelSize != null && bike.wheelSize!.isNotEmpty) ...[
            _buildBikeDetailItem(
              icon: Icons.trip_origin,
              label: 'Tamaño de rueda',
              value: bike.wheelSize!,
            ),
          ],

          // Frame size
          if (bike.frameSize != null && bike.frameSize!.isNotEmpty) ...[
            _buildBikeDetailItem(
              icon: Icons.straighten,
              label: 'Tamaño de cuadro',
              value: bike.frameSize!,
            ),
          ],

          // Warranty status
          if (bike.warrantyUntil != null) ...[
            Builder(builder: (ctx) {
              final isUnderWarranty =
                  bike.warrantyUntil!.isAfter(DateTime.now());
              return Column(
                children: [
                  _buildBikeDetailItem(
                    icon: isUnderWarranty ? Icons.verified_user : Icons.gpp_bad,
                    label: 'Garantía',
                    value:
                        isUnderWarranty ? 'En garantía' : 'Garantía expirada',
                    valueColor: isUnderWarranty ? Colors.green : Colors.grey,
                  ),
                  _buildBikeDetailItem(
                    icon: Icons.calendar_today,
                    label: isUnderWarranty ? 'Vence' : 'Venció',
                    value: DateFormat('dd/MM/yyyy').format(bike.warrantyUntil!),
                  ),
                ],
              );
            }),
          ],

          // Notes
          if (bike.notes != null && bike.notes!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Notas',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                bike.notes!,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBikeDetailItem({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: valueColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openWhatsApp(BuildContext context, String phone) async {
    // Clean phone number
    String cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');

    // Check if it has country code, if not assume Chile (+56)
    // This is a naive assumption, but works for most local cases
    if (!cleanPhone.startsWith('+')) {
      if (cleanPhone.length == 9) {
        cleanPhone = '56$cleanPhone';
      }
    }

    final url = 'https://wa.me/$cleanPhone';

    if (await canLaunchUrlString(url)) {
      await launchUrlString(url, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir WhatsApp: $url')),
        );
      }
    }
  }
}

enum _CompactJobDetailField {
  request,
  diagnosis,
  work,
  notes,
}

class _CompactJobDetailsEditor extends StatefulWidget {
  const _CompactJobDetailsEditor({
    super.key,
    required this.job,
    required this.readOnly,
    required this.onSave,
  });

  final MechanicJob job;
  final bool readOnly;
  final Future<bool> Function({
    String? clientRequest,
    String? diagnosis,
    String? workPerformed,
    String? notes,
  }) onSave;

  @override
  State<_CompactJobDetailsEditor> createState() =>
      _CompactJobDetailsEditorState();
}

class _CompactJobDetailsEditorState extends State<_CompactJobDetailsEditor> {
  final TextEditingController _controller = TextEditingController();
  late Map<_CompactJobDetailField, String> _values;
  late Map<_CompactJobDetailField, String> _originalValues;
  _CompactJobDetailField _selectedField = _CompactJobDetailField.request;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _resetFromJob();
  }

  @override
  void didUpdateWidget(_CompactJobDetailsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.job.id != widget.job.id) {
      _selectedField = _CompactJobDetailField.request;
      _resetFromJob();
    }
  }

  void _resetFromJob() {
    _values = <_CompactJobDetailField, String>{
      _CompactJobDetailField.request: widget.job.clientRequest ?? '',
      _CompactJobDetailField.diagnosis: widget.job.diagnosis ?? '',
      _CompactJobDetailField.work: widget.job.workPerformed ?? '',
      _CompactJobDetailField.notes: widget.job.notes ?? '',
    };
    _originalValues = Map<_CompactJobDetailField, String>.from(_values);
    _controller.text = _values[_selectedField] ?? '';
  }

  void _selectField(_CompactJobDetailField field) {
    _values[_selectedField] = _controller.text;
    setState(() {
      _selectedField = field;
      _controller.text = _values[field] ?? '';
    });
  }

  void _revert() {
    setState(() {
      _values = Map<_CompactJobDetailField, String>.from(_originalValues);
      _controller.text = _values[_selectedField] ?? '';
    });
  }

  Future<void> _save() async {
    _values[_selectedField] = _controller.text;
    setState(() => _saving = true);

    final saved = await widget.onSave(
      clientRequest: _emptyToNull(_values[_CompactJobDetailField.request]),
      diagnosis: _emptyToNull(_values[_CompactJobDetailField.diagnosis]),
      workPerformed: _emptyToNull(_values[_CompactJobDetailField.work]),
      notes: _emptyToNull(_values[_CompactJobDetailField.notes]),
    );
    if (!mounted) return;

    setState(() {
      _saving = false;
      if (saved) {
        _originalValues = Map<_CompactJobDetailField, String>.from(_values);
      }
    });
  }

  String? _emptyToNull(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  String _fieldLabel(_CompactJobDetailField field) {
    return switch (field) {
      _CompactJobDetailField.request => 'Solicitud',
      _CompactJobDetailField.diagnosis => 'Diagnóstico',
      _CompactJobDetailField.work => 'Trabajo realizado',
      _CompactJobDetailField.notes => 'Notas',
    };
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      key: const ValueKey('workshop-calendar-compact-editor'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Registro del trabajo',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<_CompactJobDetailField>(
            key: const ValueKey('workshop-calendar-compact-editor-section'),
            initialValue: _selectedField,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Sección',
              border: OutlineInputBorder(),
            ),
            items: _CompactJobDetailField.values
                .map(
                  (field) => DropdownMenuItem<_CompactJobDetailField>(
                    value: field,
                    child: Text(
                      _fieldLabel(field),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: widget.readOnly
                ? null
                : (field) {
                    if (field != null) _selectField(field);
                  },
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('workshop-calendar-compact-editor-text'),
            controller: _controller,
            readOnly: widget.readOnly,
            minLines: 4,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Escribe ${_fieldLabel(_selectedField).toLowerCase()}',
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
            ),
          ),
          if (widget.readOnly) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Este documento ya tiene una decisión final.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    key: const ValueKey(
                      'workshop-calendar-compact-editor-revert',
                    ),
                    onPressed: widget.readOnly || _saving ? null : _revert,
                    child: const Text(
                      'Revertir',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    key: const ValueKey(
                      'workshop-calendar-compact-editor-save',
                    ),
                    onPressed: widget.readOnly || _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: Text(_saving ? 'Guardando' : 'Guardar'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

// ============================================================
// HOVER IMAGE WIDGET - Shows small thumbnail with zoom on hover
// ============================================================
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
  final LayerLink _layerLink = LayerLink();

  void _showZoomedImage(BuildContext context) {
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: 300,
        height: 300,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(widget.size + 8, -130),
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
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
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
              color: _isHovered
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey[300]!,
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
      ),
    );
  }

  @override
  void dispose() {
    _hideZoomedImage();
    super.dispose();
  }
}
