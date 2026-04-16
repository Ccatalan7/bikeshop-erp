import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../modules/ai_assistant/services/ai_service.dart';
import '../../../modules/crm/models/crm_models.dart';
import '../../../modules/sales/models/sales_models.dart';
import '../../../shared/models/product.dart';
import '../../../shared/models/tax_treatment.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/product_autocomplete_field.dart';
import '../../../shared/widgets/smart_product_field.dart';
import '../../../shared/widgets/line_row_wrapper.dart';
import '../../../shared/services/inventory_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/services/whatsapp_service.dart';
import '../../../modules/crm/services/customer_service.dart';
import '../config/brake_canonical_data.dart';
import '../services/bikeshop_service.dart';
import '../services/smart_task_service.dart';
import '../services/service_wizard_service.dart';
import '../widgets/bikeshop_multi_select_picker_field.dart';
import '../widgets/service_wizard_dialog.dart';
import '../../../shared/services/image_service.dart'; // Add ImageService import
import '../services/job_status_service.dart';
import '../models/bikeshop_models.dart';
import '../../messaging/widgets/entity_chat_sidebar.dart';
import 'bike_form_dialog.dart';
import '../widgets/bike_diagram_illustration.dart';
import '../widgets/bike_system_controller.dart';

// ============================================================
// Per-Bike Data Container (Multi-bike support)
// ============================================================
class _BikeTabData {
  final String tabId; // Unique ID for this tab
  Bike? bike;
  String? jobBikeId; // Database ID from mechanic_job_bikes (null for new)
  String? diagnosisSheetKey;
  MechanicJobDiagnosisSheet diagnosisSheet;
  DateTime? diagnosisSheetUpdatedAt;

  // Per-bike text controllers
  final TextEditingController clientRequestController = TextEditingController();
  final TextEditingController diagnosisController = TextEditingController();
  final TextEditingController workRequestedController = TextEditingController();
  final TextEditingController technicianNotesController =
      TextEditingController();

  // Per-bike items
  final List<_JobPartItem> partItems = [];

  // Per-bike flags
  bool isWarrantyWork = false;
  bool requiresApproval = false;
  bool approvedByCustomer = false;

  final bool isGeneralTab;

  _BikeTabData({
    String? tabId,
    this.bike,
    this.jobBikeId,
    this.isGeneralTab = false,
  })  : diagnosisSheet = const MechanicJobDiagnosisSheet(),
        tabId = tabId ?? DateTime.now().microsecondsSinceEpoch.toString();

  void dispose() {
    clientRequestController.dispose();
    diagnosisController.dispose();
    workRequestedController.dispose();
    technicianNotesController.dispose();
  }

  String get displayName {
    if (isGeneralTab) return 'General / Venta';
    return bike?.displayName ?? 'Nueva Bicicleta';
  }

  double get subtotal =>
      partItems.fold(0, (sum, item) => sum + item.quantity * item.unitPrice);
}

enum _JobWorkbenchTab { general, diagnosis, products }

enum _DiagnosisWorkbenchTab { narrative, structured }

enum _NarrativeDraftInsertMode { replace, append }

final List<BikeSystemControllerSpec> _kStructuredDiagnosisEditableSystems =
    kBikeSystemControllerSpecs
        .where((spec) => spec.supportsStructuredDiagnosis)
        .toList(growable: false);

class _StructuredDiagnosisComponentSpec {
  final String systemKey;
  final String componentKey;
  final String label;
  final IconData icon;

  const _StructuredDiagnosisComponentSpec({
    required this.systemKey,
    required this.componentKey,
    required this.label,
    required this.icon,
  });
}

class _DiagnosisComponentSelectorStrip extends StatefulWidget {
  const _DiagnosisComponentSelectorStrip({
    super.key,
    required this.specs,
    required this.selectedComponentKey,
    required this.statusForComponent,
    required this.onSelected,
    required this.colorForStatus,
  });

  final List<_StructuredDiagnosisComponentSpec> specs;
  final String? selectedComponentKey;
  final BikeSystemOverallStatus Function(String componentKey)
      statusForComponent;
  final ValueChanged<String> onSelected;
  final Color Function(BikeSystemOverallStatus status) colorForStatus;

  @override
  State<_DiagnosisComponentSelectorStrip> createState() =>
      _DiagnosisComponentSelectorStripState();
}

class _DiagnosisComponentSelectorStripState
    extends State<_DiagnosisComponentSelectorStrip> {
  static const double _desktopControlWidth = 32;
  static const double _desktopScrollStep = 280;

  final ScrollController _scrollController = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_syncScrollAffordances);
    _scheduleScrollAffordanceSync();
  }

  @override
  void didUpdateWidget(covariant _DiagnosisComponentSelectorStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleScrollAffordanceSync();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_syncScrollAffordances);
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleScrollAffordanceSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncScrollAffordances();
      }
    });
  }

  void _syncScrollAffordances() {
    if (!_scrollController.hasClients) {
      if (_canScrollLeft || _canScrollRight) {
        setState(() {
          _canScrollLeft = false;
          _canScrollRight = false;
        });
      }
      return;
    }

    final position = _scrollController.position;
    final canScrollLeft = position.pixels > 8;
    final canScrollRight = position.maxScrollExtent - position.pixels > 8;

    if (canScrollLeft == _canScrollLeft && canScrollRight == _canScrollRight) {
      return;
    }

    setState(() {
      _canScrollLeft = canScrollLeft;
      _canScrollRight = canScrollRight;
    });
  }

  Future<void> _scrollBy(double delta) async {
    if (!_scrollController.hasClients) return;

    final target = (_scrollController.offset + delta)
        .clamp(0.0, _scrollController.position.maxScrollExtent)
        .toDouble();

    if ((target - _scrollController.offset).abs() < 1) {
      return;
    }

    await _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildDesktopScrollControl(
    ThemeData theme, {
    required bool isLeft,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    final surfaceColor =
        theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.96);
    final fadeStart = theme.colorScheme.surface.withValues(alpha: 0.72);
    final fadeEnd = theme.colorScheme.surface.withValues(alpha: 0.0);

    return Positioned(
      left: isLeft ? 4 : null,
      right: isLeft ? null : 4,
      top: 0,
      bottom: 0,
      child: Container(
        width: _desktopControlWidth,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: isLeft ? Alignment.centerLeft : Alignment.centerRight,
            end: isLeft ? Alignment.centerRight : Alignment.centerLeft,
            colors: [fadeStart, fadeEnd],
          ),
        ),
        child: Tooltip(
          message: tooltip,
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(icon, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            style: IconButton.styleFrom(
              backgroundColor: surfaceColor,
              foregroundColor: theme.colorScheme.onSurfaceVariant,
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
              ),
              shape: const CircleBorder(),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final platform = defaultTargetPlatform;
    final isDesktop = MediaQuery.sizeOf(context).width > 720 &&
        (platform == TargetPlatform.macOS ||
            platform == TargetPlatform.windows ||
            platform == TargetPlatform.linux);

    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _scheduleScrollAffordanceSync();
        return false;
      },
      child: Stack(
        children: [
          ClipRect(
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.hardEdge,
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: widget.specs.map((spec) {
                    final status = widget.statusForComponent(spec.componentKey);
                    final isSelected =
                        spec.componentKey == widget.selectedComponentKey;
                    final tint = widget.colorForStatus(status);

                    return Padding(
                      padding: const EdgeInsets.only(right: 12, bottom: 4),
                      child: InkWell(
                        onTap: () => widget.onSelected(spec.componentKey),
                        borderRadius: BorderRadius.circular(16),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 130,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? theme.colorScheme.primaryContainer
                                    .withValues(alpha: 0.15)
                                : theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outlineVariant
                                      .withValues(alpha: 0.6),
                              width: isSelected ? 2 : 1,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.1),
                                      blurRadius: 10,
                                      spreadRadius: 0,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : [],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                height: 100,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color:
                                      theme.colorScheme.surfaceContainerLowest,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(14),
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(14),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Image.asset(
                                      'assets/images/${spec.componentKey}_icon.png',
                                      fit: BoxFit.contain,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                        return Icon(
                                          spec.icon,
                                          color:
                                              theme.colorScheme.outlineVariant,
                                          size: 36,
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                              const Divider(height: 1, thickness: 1),
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      spec.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style:
                                          theme.textTheme.labelMedium?.copyWith(
                                        fontWeight: isSelected
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        color: isSelected
                                            ? theme.colorScheme.onSurface
                                            : theme
                                                .colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: tint.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        status.displayName,
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: tint,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
          if (isDesktop && _canScrollLeft)
            _buildDesktopScrollControl(
              theme,
              isLeft: true,
              icon: Icons.chevron_left,
              tooltip: 'Ver componentes anteriores',
              onPressed: () => _scrollBy(-_desktopScrollStep),
            ),
          if (isDesktop && _canScrollRight)
            _buildDesktopScrollControl(
              theme,
              isLeft: false,
              icon: Icons.chevron_right,
              tooltip: 'Ver componentes siguientes',
              onPressed: () => _scrollBy(_desktopScrollStep),
            ),
        ],
      ),
    );
  }
}

const List<_StructuredDiagnosisComponentSpec>
    _kStructuredDiagnosisComponentSpecs = [
  _StructuredDiagnosisComponentSpec(
    systemKey: 'front_brake',
    componentKey: 'brake_pad',
    label: 'Pastillas / zapatas',
    icon: Icons.stop_circle_outlined,
  ),
  _StructuredDiagnosisComponentSpec(
    systemKey: 'front_brake',
    componentKey: 'rotor',
    label: 'Rotor',
    icon: Icons.album_outlined,
  ),
  _StructuredDiagnosisComponentSpec(
    systemKey: 'rear_brake',
    componentKey: 'brake_pad',
    label: 'Pastillas / zapatas',
    icon: Icons.stop_circle_outlined,
  ),
  _StructuredDiagnosisComponentSpec(
    systemKey: 'rear_brake',
    componentKey: 'rotor',
    label: 'Rotor',
    icon: Icons.album_outlined,
  ),
  _StructuredDiagnosisComponentSpec(
    systemKey: 'drivetrain',
    componentKey: 'chain',
    label: 'Cadena',
    icon: Icons.link,
  ),
  _StructuredDiagnosisComponentSpec(
    systemKey: 'drivetrain',
    componentKey: 'cassette',
    label: 'Cassette',
    icon: Icons.album_outlined,
  ),
  _StructuredDiagnosisComponentSpec(
    systemKey: 'drivetrain',
    componentKey: 'chainring',
    label: 'Plato',
    icon: Icons.adjust,
  ),
  _StructuredDiagnosisComponentSpec(
    systemKey: 'drivetrain',
    componentKey: 'rear_derailleur',
    label: 'Cambio trasero',
    icon: Icons.alt_route_outlined,
  ),
  _StructuredDiagnosisComponentSpec(
    systemKey: 'drivetrain',
    componentKey: 'front_derailleur',
    label: 'Cambio delantero',
    icon: Icons.call_split_outlined,
  ),
  _StructuredDiagnosisComponentSpec(
    systemKey: 'drivetrain',
    componentKey: 'shifter',
    label: 'Shifter',
    icon: Icons.touch_app_outlined,
  ),
];

const Map<String, String> _kChainLubricationOptions = {
  'ok': 'Lubricada',
  'dry': 'Seca',
  'dirty': 'Suciedad excesiva',
  'contaminated': 'Contaminada',
};

const Map<String, String> _kDrivetrainWearConditionOptions = {
  'ok': 'Correcto',
  'attention': 'Con desgaste',
  'worn': 'Gastado',
  'replace': 'Reemplazar',
};

const Map<String, String> _kDerailleurConditionOptions = {
  'ok': 'Correcto',
  'attention': 'Requiere ajuste',
  'bent': 'Desalineado / doblado',
  'replace': 'Reemplazar',
};

const Map<String, String> _kShifterConditionOptions = {
  'ok': 'Correcto',
  'sticky': 'Pegado / duro',
  'attention': 'Impreciso',
  'replace': 'Reemplazar',
};

final List<ServiceQuestionOption> _kBrakeSymptomOptions =
    serviceQuestionOptionsFromMap(kBrakeSymptomLabels);

typedef _BrakeDiagnosisSheetUpdater = void Function(
  BrakeDiagnosisSheet Function(BrakeDiagnosisSheet current) transform, {
  bool refresh,
});

class _DiagnosisNarrativeSource {
  const _DiagnosisNarrativeSource({
    required this.sections,
    required this.recommendationHints,
    required this.hasCriticalRisk,
  });

  final List<_DiagnosisNarrativeSection> sections;
  final List<String> recommendationHints;
  final bool hasCriticalRisk;

  bool get hasContent => sections.isNotEmpty || recommendationHints.isNotEmpty;
}

class _DiagnosisNarrativeSection {
  const _DiagnosisNarrativeSection({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;
}

class _ServiceWizardDialogConfig {
  final Map<String, dynamic> initialAnswers;
  final Set<String> hiddenQuestionKeys;
  final String? helperText;
  final ServiceWizardContextSummary? contextSummary;
  final Map<String, ServiceWizardQuestionOverride> questionOverrides;
  final Set<String> diagnosisLinkedQuestionKeys;

  const _ServiceWizardDialogConfig({
    required this.initialAnswers,
    required this.hiddenQuestionKeys,
    required this.helperText,
    this.contextSummary,
    this.questionOverrides = const <String, ServiceWizardQuestionOverride>{},
    this.diagnosisLinkedQuestionKeys = const <String>{},
  });
}

class MechanicJobFormPage extends StatefulWidget {
  final String? jobId; // Null for new job, ID for editing
  final String? customerId; // Pre-select customer if provided
  final String?
      initialJobType; // Pre-select type: 'service'|'warranty'|'quotation'|'item_service'
  final bool isEmbedded;
  final VoidCallback? onSaved;
  final VoidCallback? onCanceled;

  const MechanicJobFormPage({
    super.key,
    this.jobId,
    this.customerId,
    this.initialJobType,
    this.isEmbedded = false,
    this.onSaved,
    this.onCanceled,
  });

  @override
  State<MechanicJobFormPage> createState() => _MechanicJobFormPageState();
}

class _MechanicJobFormPageState extends State<MechanicJobFormPage> {
  final _formKey = GlobalKey<FormState>();

  // Column widths for parts table (same as invoice)
  static const double _colIndexWidth = 40.0;
  static const double _colQuantityWidth = 120.0;
  static const double _colPriceWidth = 130.0;
  static const double _colTotalWidth = 130.0;
  static const double _colActionsWidth = 48.0;

  // Column widths for labor table
  static const double _colDateWidth = 120.0;
  static const double _colHoursWidth = 100.0;
  static const double _colRateWidth = 120.0;

  // Form controllers (job-level)
  final _discountController = TextEditingController(text: '0');
  final _estimatedDurationController = TextEditingController();

  // ============================================================
  // MULTI-BIKE STATE
  // ============================================================
  final List<_BikeTabData> _bikeTabs = [];
  int _selectedBikeTabIndex = 0;
  _JobWorkbenchTab _selectedWorkbenchTab = _JobWorkbenchTab.general;
  _DiagnosisWorkbenchTab _selectedDiagnosisWorkbenchTab =
      _DiagnosisWorkbenchTab.structured;
  String? _selectedStructuredDiagnosisSystemKey;
  final Map<String, String> _selectedStructuredDiagnosisComponentKeys = {};

  /// Currently selected bike tab
  _BikeTabData? get _currentBikeTab =>
      _bikeTabs.isNotEmpty && _selectedBikeTabIndex < _bikeTabs.length
          ? _bikeTabs[_selectedBikeTabIndex]
          : null;

  MechanicJobDiagnosisSheet get _currentDiagnosisSheet =>
      _currentBikeTab?.diagnosisSheet ?? const MechanicJobDiagnosisSheet();

  // Legacy single-bike state (for backward compatibility during migration)
  // TODO: Remove once multi-bike is fully implemented
  final _clientRequestController = TextEditingController();
  final _diagnosisController = TextEditingController();
  final _workSummaryController = TextEditingController();
  final _technicianNotesController = TextEditingController();

  // Form state
  Customer? _selectedCustomer;
  Bike? _selectedBike; // Legacy - now use _bikeTabs
  BikeProfile? _selectedBikeProfile;
  JobPriority _selectedPriority = JobPriority.normal;
  JobStatus _selectedStatus = JobStatus.pendiente;
  JobStatusCustom?
      _selectedCustomStatus; // Custom status from job_statuses table
  List<JobStatusCustom> _customStatuses = []; // All available custom statuses
  DateTime? _selectedDeadline;
  DateTime _selectedArrivalDate = DateTime.now(); // Arrival date (editable)
  bool _requiresApproval = false;
  bool _isWarrantyJob = false;
  TaxTreatment _taxTreatment =
      TaxTreatment.noTax; // Default: no tax (matches sales invoice)

  // Job type and subject (for non-bike jobs: warranty, quotation, item_service)
  JobType _jobType = JobType.service;
  JobSubject? _selectedSubject;
  List<JobSubject> _availableSubjects = [];
  final _subjectNotesController = TextEditingController();
  WarrantyOutcome? _warrantyOutcome;
  QuotationStatus? _quotationStatus;
  DateTime? _quotationValidUntil;

  // Parts and services
  final List<_JobPartItem> _partItems = [];
  final List<_JobServiceItem> _serviceItems = [];

  // Service wizard
  final _aiAssistantService = AIAssistantService();
  final _serviceWizardService = ServiceWizardService();
  int? _selectedServiceIndex; // Index into _currentPartItems for sidebar detail

  // Key to reset autocomplete field after adding product
  int _partAutocompleteKey = 0;
  final FocusNode _partAutocompleteFocus = FocusNode();

  // Data
  List<Customer> _customers = [];
  List<Bike> _bikes = [];
  List<Product> _products = [];
  List<Product> _serviceProducts = [];

  // Loading states
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isLoadingSelectedBikeProfile = false;
  String? _generatingNarrativeDraftTabId;

  // Image handling
  List<String> _imageUrls = [];
  final List<({Uint8List bytes, String name})> _newImages = [];
  bool _isUploadingImage = false;
  String? _linkedInvoiceNumber;

  // Edit mode
  MechanicJob? _existingJob;

  @override
  void initState() {
    super.initState();
    // Prevent a blank/partial form from flashing before the async edit load starts.
    // This avoids the "form opens fast, then shows loader again" flicker.
    _isLoading = true;
    // Defer initialization to avoid "setState() or markNeedsBuild() called during build"
    // when services trigger notifyListeners() synchronously
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitialData());
  }

  @override
  void dispose() {
    _clientRequestController.dispose();
    _diagnosisController.dispose();
    _workSummaryController.dispose();
    _technicianNotesController.dispose();
    _discountController.dispose();
    _estimatedDurationController.dispose();
    _subjectNotesController.dispose();
    _partAutocompleteFocus.dispose();
    for (final tab in _bikeTabs) {
      tab.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      final customerService =
          Provider.of<CustomerService>(context, listen: false);
      final inventoryService =
          Provider.of<InventoryService>(context, listen: false);
      final jobStatusService =
          Provider.of<JobStatusService>(context, listen: false);
      final bikeshopService =
          Provider.of<BikeshopService>(context, listen: false);

      if (mounted) {
        setState(() {
          if (customerService.hasCustomersCache && _customers.isEmpty) {
            _customers = List<Customer>.from(customerService.cachedCustomers);
          }
          if (inventoryService.hasLoaded && _products.isEmpty) {
            _products = List<Product>.from(inventoryService.products.take(50));
            _serviceProducts = inventoryService.products
                .where((p) => p.productType == ProductType.service)
                .toList();
          }
        });
      }

      final results = await Future.wait([
        customerService.getCustomers(limit: 50),
        inventoryService.searchProducts('', limit: 50),
        jobStatusService.loadStatuses(),
        bikeshopService.getJobSubjects(),
      ]);

      List<Customer> customers = results[0] as List<Customer>;
      List<Product> products = results[1] as List<Product>;
      final subjects = results[3] as List<JobSubject>;

      final targetCustomerId = widget.customerId;
      if (targetCustomerId != null) {
        final hasCustomer = customers.any((c) => c.id == targetCustomerId);
        if (!hasCustomer) {
          final specificCustomer =
              await customerService.getCustomerById(targetCustomerId);
          if (specificCustomer != null) {
            customers = [specificCustomer, ...customers];
          }
        }
      }

      final serviceProducts = inventoryService.hasLoaded
          ? inventoryService.products
              .where((p) => p.productType == ProductType.service)
              .toList()
          : await inventoryService.getProductsByType(ProductType.service);

      final customStatuses = jobStatusService.activeStatuses;
      debugPrint('📋 Loaded ${customStatuses.length} custom statuses');

      if (mounted) {
        setState(() {
          _customers = customers;
          _products = products;
          _serviceProducts = serviceProducts;
          _customStatuses = customStatuses;
          _availableSubjects = subjects;
          if (_customStatuses.isNotEmpty && _selectedCustomStatus == null) {
            _selectedCustomStatus = _customStatuses.firstWhere(
              (s) => s.phase == StatusPhase.todo,
              orElse: () => _customStatuses.first,
            );
          }
          if (widget.initialJobType != null && widget.jobId == null) {
            _jobType = JobType.fromDbValue(widget.initialJobType!);
          }
        });
      }

      if (widget.jobId != null) {
        await _loadExistingJob();
      }

      if (widget.customerId != null && widget.jobId == null) {
        try {
          final customer = _customers.firstWhere(
            (c) => c.id == widget.customerId,
          );
          await _selectCustomer(customer);
        } catch (_) {
          if (_customers.isNotEmpty) {
            await _selectCustomer(_customers.first);
          }
        }
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar datos: $e')),
        );
      }
    }
  }

  Future<void> _loadExistingJob() async {
    try {
      final bikeshopService =
          Provider.of<BikeshopService>(context, listen: false);
      final inventoryService =
          Provider.of<InventoryService>(context, listen: false);

      debugPrint('🔍 Loading job with ID: ${widget.jobId}');
      final job = await bikeshopService.getJobById(widget.jobId!);

      if (job == null) {
        debugPrint('❌ Job not found: ${widget.jobId}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pega no encontrada')),
          );
          context.pop();
        }
        return;
      }

      debugPrint('✅ Job loaded: ${job.jobNumber}');

      String? linkedInvoiceNumber;
      if (job.invoiceId != null) {
        try {
          final invoiceData =
              await Provider.of<DatabaseService>(context, listen: false)
                  .selectById('sales_invoices', job.invoiceId!);
          linkedInvoiceNumber = invoiceData?['invoice_number']?.toString();
        } catch (e) {
          debugPrint(
              '⚠️ Could not load linked invoice number for ${job.invoiceId}: $e');
        }
      }

      // Load customer and bikes
      // Ensure customer is in our list (might not be in the initial top 50)
      Customer? customer;
      try {
        customer = _customers.firstWhere((c) => c.id == job.customerId);
      } catch (_) {
        customer = await Provider.of<CustomerService>(context, listen: false)
            .getCustomerById(job.customerId);
        if (customer != null && mounted) {
          setState(() {
            _customers = [customer!, ..._customers];
          });
        }
      }

      if (customer != null) {
        await _selectCustomer(customer);
      }

      // Load all related job data in parallel
      final relatedResults = await Future.wait([
        bikeshopService.getJobItems(job.id!),
        bikeshopService.getJobBikes(job.id!),
      ]);

      final allItems = relatedResults[0] as List<MechanicJobItem>;
      final jobBikes = relatedResults[1] as List<MechanicJobBike>;
      debugPrint('📦 Loaded ${jobBikes.length} job bikes');

      // Load tax treatment from job
      TaxTreatment loadedTaxTreatment = job.taxTreatment;
      debugPrint('✅ Tax treatment loaded: $loadedTaxTreatment');

      final Map<String, Product?> productCache = {
        for (final product in _products) product.id: product,
      };

      final missingProductIds = allItems
          .map((item) => item.productId)
          .whereType<String>()
          .where((id) => !productCache.containsKey(id))
          .toSet()
          .toList();

      if (missingProductIds.isNotEmpty) {
        final fetchedProducts = await Future.wait(
          missingProductIds.map((id) async {
            try {
              return MapEntry(id, await inventoryService.getProductById(id));
            } catch (e) {
              debugPrint('⚠️ Could not fetch product $id: $e');
              return MapEntry<String, Product?>(id, null);
            }
          }),
        );

        for (final entry in fetchedProducts) {
          productCache[entry.key] = entry.value;
        }
      }

      // Helper to find/create product for an item
      Future<Product?> getProductForItem(MechanicJobItem item) async {
        if (item.productId == null) return null;

        final cached = productCache[item.productId!];
        if (cached != null) {
          return cached;
        }

        final fallbackProductType =
            item.itemType == 'service' || item.serviceProductId != null
                ? ProductType.service
                : ProductType.product;

        return Product(
          id: item.productId!,
          name: item.productName,
          sku: item.productSku ?? 'N/A',
          price: item.unitPrice,
          cost: 0,
          stockQuantity: 0,
          category: ProductCategory.other,
          productType: fallbackProductType,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
      }

      // Build bike tabs from job bikes data
      final List<_BikeTabData> loadedBikeTabs = [];

      if (jobBikes.isNotEmpty) {
        // Multi-bike job: create tab for each job bike
        for (final jobBike in jobBikes) {
          // Use bike from local cache, or from the joined data loaded by getJobBikes()
          Bike? bike = _findBikeById(jobBike.bikeId);
          bike ??= jobBike.bike; // Fall back to bike loaded from join

          if (bike == null) {
            debugPrint(
                '⚠️ Bike ${jobBike.bikeId} not found for customer or in join data');
            continue;
          }

          // Make sure this bike is in _bikes for UI consistency
          if (!_bikes.any((b) => b.id == bike!.id)) {
            _bikes.add(bike);
          }

          final tab = _BikeTabData(
            bike: bike,
            jobBikeId: jobBike.id,
          );

          // Set per-bike fields
          tab.clientRequestController.text = jobBike.workRequested ?? '';
          tab.diagnosisController.text = jobBike.diagnosis ?? '';
          tab.workRequestedController.text = jobBike.workPerformed ?? '';
          tab.technicianNotesController.text = jobBike.technicianNotes ?? '';
          tab.diagnosisSheetKey = jobBike.diagnosisSheetKey;
          tab.diagnosisSheet = jobBike.diagnosisSheet;
          tab.diagnosisSheetUpdatedAt = jobBike.diagnosisSheetUpdatedAt;
          tab.isWarrantyWork = jobBike.isWarrantyWork;
          tab.requiresApproval = jobBike.requiresApproval;
          tab.approvedByCustomer = jobBike.approvedByCustomer;

          // Load items for this specific bike
          // Load items for this specific bike
          final bikeItems =
              allItems.where((item) => item.jobBikeId == jobBike.id).toList();

          for (final item in bikeItems) {
            final product = await getProductForItem(item);
            tab.partItems.add(_JobPartItem(
              id: item.id,
              product: product,
              name: item.productName,
              isCatalogProduct: item.productId != null,
              isServiceItem: item.itemType == 'service' ||
                  item.serviceProductId != null ||
                  product?.isService == true,
              quantity: item.quantity.toInt(),
              unitPrice: item.unitPrice,
              location: item.location,
              notes: item.notes,
            ));
          }

          loadedBikeTabs.add(tab);
          debugPrint(
              '✅ Loaded bike tab: ${bike.displayName} with ${tab.partItems.length} items');
        }

        // Add General Tab for orphan items
        final generalTab =
            _BikeTabData(isGeneralTab: true, tabId: 'general_tab');
        final orphanItems =
            allItems.where((item) => item.jobBikeId == null).toList();
        for (final item in orphanItems) {
          final product = await getProductForItem(item);
          generalTab.partItems.add(_JobPartItem(
            id: item.id,
            product: product,
            name: item.productName,
            isCatalogProduct: item.productId != null,
            isServiceItem: item.itemType == 'service' ||
                item.serviceProductId != null ||
                product?.isService == true,
            quantity: item.quantity.toInt(),
            unitPrice: item.unitPrice,
            location: item.location,
            notes: item.notes,
          ));
        }
        loadedBikeTabs.add(generalTab);
      } else {
        // Legacy single-bike job: create one tab from job data
        final bike = _findBikeById(job.bikeId);
        if (bike != null) {
          final tab = _BikeTabData(bike: bike);

          // Use job-level fields for the single bike
          tab.clientRequestController.text = job.clientRequest ?? '';
          tab.diagnosisController.text = job.diagnosis ?? '';
          tab.workRequestedController.text = job.workPerformed ?? '';
          tab.technicianNotesController.text = job.notes ?? '';
          tab.isWarrantyWork = job.isWarrantyJob;
          tab.requiresApproval = job.requiresApproval;
          tab.approvedByCustomer = job.approvedByCustomer;

          // Load all items (no jobBikeId filtering for legacy)
          for (final item in allItems) {
            final product = await getProductForItem(item);
            tab.partItems.add(_JobPartItem(
              id: item.id,
              product: product,
              name: item.productName,
              isCatalogProduct: item.productId != null,
              isServiceItem: item.itemType == 'service' ||
                  item.serviceProductId != null ||
                  product?.isService == true,
              quantity: item.quantity.toInt(),
              unitPrice: item.unitPrice,
              location: item.location,
              notes: item.notes,
            ));
          }

          loadedBikeTabs.add(tab);

          // Also load orphan items (job_bike_id = null) into General tab for legacy jobs.
          // These can arrive via invoice sync — ignore them means they get wiped on next save.
          final legacyGeneralTab =
              _BikeTabData(isGeneralTab: true, tabId: 'general_tab');
          final legacyOrphanItems =
              allItems.where((item) => item.jobBikeId == null).toList();
          for (final item in legacyOrphanItems) {
            final product = await getProductForItem(item);
            legacyGeneralTab.partItems.add(_JobPartItem(
              id: item.id,
              product: product,
              name: item.productName,
              isCatalogProduct: item.productId != null,
              isServiceItem: item.itemType == 'service' ||
                  item.serviceProductId != null ||
                  product?.isService == true,
              quantity: item.quantity.toInt(),
              unitPrice: item.unitPrice,
              location: item.location,
              notes: item.notes,
            ));
          }
          loadedBikeTabs.add(legacyGeneralTab);
          debugPrint(
              '✅ Loaded legacy single-bike tab: ${bike.displayName} with ${tab.partItems.length} items, General tab: ${legacyGeneralTab.partItems.length} orphan items');
        }
      }

      if (mounted) {
        setState(() {
          _existingJob = job;
          _selectedCustomer = customer;
          _selectedPriority = job.priority;
          _selectedStatus = job.status;

          // Load custom status
          if (job.customStatus != null) {
            _selectedCustomStatus = job.customStatus;
          } else if (job.statusId != null && _customStatuses.isNotEmpty) {
            final found = _customStatuses.where((s) => s.id == job.statusId);
            if (found.isNotEmpty) {
              _selectedCustomStatus = found.first;
            }
          }

          _selectedDeadline = job.deliveryDeadline;
          _selectedArrivalDate = job.arrivalDate;
          _taxTreatment = loadedTaxTreatment;
          _linkedInvoiceNumber = linkedInvoiceNumber;
          _discountController.text = job.discountAmount.toString();
          _estimatedDurationController.text = '';

          // Set bike tabs (multi-bike or legacy single-bike)
          _bikeTabs.clear();
          _bikeTabs.addAll(loadedBikeTabs);
          _selectedBikeTabIndex = 0;

          // Set legacy fields for backward compat
          if (loadedBikeTabs.isNotEmpty) {
            _selectedBike = loadedBikeTabs.first.bike;
            _clientRequestController.text =
                loadedBikeTabs.first.clientRequestController.text;
            _diagnosisController.text =
                loadedBikeTabs.first.diagnosisController.text;
            _workSummaryController.text =
                loadedBikeTabs.first.workRequestedController.text;
            _technicianNotesController.text =
                loadedBikeTabs.first.technicianNotesController.text;
            _requiresApproval = loadedBikeTabs.first.requiresApproval;
            _isWarrantyJob = loadedBikeTabs.first.isWarrantyWork;
          }

          // Load new job type fields
          _jobType = job.jobType;
          if (job.subjectData != null) {
            _selectedSubject = job.subjectData;
            if (!_availableSubjects.any((s) => s.id == job.subjectData!.id)) {
              _availableSubjects = [job.subjectData!, ..._availableSubjects];
            }
          }
          if (job.subjectNotes != null && job.subjectNotes!.isNotEmpty) {
            _subjectNotesController.text = job.subjectNotes!;
          }
          _warrantyOutcome = job.warrantyOutcome;
          _quotationStatus = job.quotationStatus;
          _quotationValidUntil = job.quotationValidUntil;

          // Clear legacy items (now per-bike)
          _partItems.clear();
          _serviceItems.clear();

          // Image URLs
          _imageUrls = List.from(job.imageUrls);
        });

        unawaited(_loadSelectedBikeProfile(loadedBikeTabs.firstOrNull?.bike));
      }
    } catch (e) {
      debugPrint('❌ Error loading job: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar pega: $e')),
        );
      }
    }
  }

  Future<void> _selectCustomer(Customer customer) async {
    final bikeshopService =
        Provider.of<BikeshopService>(context, listen: false);

    // Load customer bikes
    final bikes = await bikeshopService.getBikes(customerId: customer.id);

    setState(() {
      _selectedCustomer = customer;
      _bikes = bikes;
      _selectedBike = null; // Reset bike selection
      _selectedBikeProfile = null;
    });
  }

  Future<Customer?> _createQuickCustomer(String name) async {
    if (name.trim().isEmpty) return null;
    try {
      final tenantId = await TenantService().getTenantId();
      if (tenantId == null) {
        throw Exception('No se pudo obtener el tenant_id del usuario');
      }

      final customer = Customer(
        tenantId: tenantId,
        name: name.trim(),
        rut: '',
      );

      final customerService =
          Provider.of<CustomerService>(context, listen: false);
      final created = await customerService.createCustomer(customer);

      // Add to cached list
      setState(() {
        _customers.add(created);
      });

      return created;
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al crear cliente: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }
  }

  Future<void> _showCustomerSelector() async {
    final customerService =
        Provider.of<CustomerService>(context, listen: false);

    final selected = await showDialog<Customer>(
      context: context,
      builder: (context) {
        return _CustomerSelector(
          initialCustomers: List<Customer>.from(_customers),
          customerService: customerService,
          onCreateCustomer: _createQuickCustomer,
        );
      },
    );

    if (selected != null && mounted) {
      await _selectCustomer(selected);
      final exists = _customers.any((customer) => customer.id == selected.id);
      if (!exists) {
        setState(() {
          _customers.add(selected);
        });
      }
    }
  }

  // ============================================================
  // BIKE TAB MANAGEMENT
  // ============================================================

  /// Add a bike to the job (creates a new tab)
  void _addBikeTab(Bike bike) {
    // Check if bike already exists in tabs
    if (_bikeTabs.any((tab) => tab.bike?.id == bike.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${bike.displayName} ya está en este trabajo')),
      );
      return;
    }

    setState(() {
      final newTab = _BikeTabData(bike: bike);
      final generalTabIndex = _bikeTabs.indexWhere((t) => t.isGeneralTab);

      if (generalTabIndex != -1) {
        // Insert before general tab
        _bikeTabs.insert(generalTabIndex, newTab);
        _selectedBikeTabIndex = generalTabIndex;
      } else {
        _bikeTabs.add(newTab);
        if (_bikeTabs.length == 1) {
          _bikeTabs.add(_BikeTabData(isGeneralTab: true, tabId: 'general_tab'));
        }
        _selectedBikeTabIndex = _bikeTabs.length - 2;
      }

      // Also set legacy single bike (for backward compat)
      _selectedBike = bike;
    });

    unawaited(_loadSelectedBikeProfile(bike));
  }

  Bike? _findBikeById(String? bikeId) {
    if (bikeId == null) return null;

    for (final bike in _bikes) {
      if (bike.id == bikeId) {
        return bike;
      }
    }

    return null;
  }

  Future<void> _refreshCustomerBikes({String? selectedBikeId}) async {
    final customerId = _selectedCustomer?.id;
    if (customerId == null) return;

    final bikeshopService =
        Provider.of<BikeshopService>(context, listen: false);
    final bikes = await bikeshopService.getBikes(customerId: customerId);

    if (!mounted) return;

    final bikesById = <String, Bike>{
      for (final bike in bikes)
        if (bike.id != null) bike.id!: bike,
    };
    final resolvedSelectedBikeId = selectedBikeId ?? _selectedBike?.id;

    setState(() {
      _bikes = bikes;

      for (final tab in _bikeTabs) {
        final tabBikeId = tab.bike?.id;
        if (tabBikeId != null && bikesById.containsKey(tabBikeId)) {
          tab.bike = bikesById[tabBikeId];
        }
      }

      _selectedBike = resolvedSelectedBikeId != null
          ? bikesById[resolvedSelectedBikeId]
          : null;

      if (_selectedBike == null) {
        _selectedBikeProfile = null;
      }
    });

    if (_selectedBike != null) {
      unawaited(_loadSelectedBikeProfile(_selectedBike));
    }
  }

  Future<Bike?> _openBikeDialog({
    Bike? bike,
    bool selectSavedBike = false,
  }) async {
    final customerId = _selectedCustomer?.id;
    if (customerId == null) return null;

    final result = await showDialog<Bike?>(
      context: context,
      builder: (dialogContext) => BikeFormDialog(
        customerId: customerId,
        bike: bike,
      ),
    );

    if (!mounted) return result;

    if (bike != null || result != null) {
      await _refreshCustomerBikes(
        selectedBikeId:
            selectSavedBike ? (result?.id ?? bike?.id) : _selectedBike?.id,
      );
    }

    if (result?.id == null) {
      return null;
    }

    return _findBikeById(result!.id) ?? result;
  }

  /// Remove a bike tab
  void _removeBikeTab(int index) {
    if (_bikeTabs[index].isGeneralTab) {
      return; // Prevent removing the General tab
    }

    final regularTabsCount = _bikeTabs.where((t) => !t.isGeneralTab).length;
    if (regularTabsCount <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe haber al menos una bicicleta')),
      );
      return;
    }

    setState(() {
      _bikeTabs[index].dispose();
      _bikeTabs.removeAt(index);
      if (_selectedBikeTabIndex >= _bikeTabs.length) {
        _selectedBikeTabIndex = _bikeTabs.length - 1;
      }
      // Update legacy single bike
      _selectedBike = _bikeTabs[_selectedBikeTabIndex].bike;
    });

    unawaited(_loadSelectedBikeProfile(_selectedBike));
  }

  Future<void> _loadSelectedBikeProfile(Bike? bike) async {
    if (!mounted) return;

    if (bike?.id == null) {
      setState(() {
        _selectedBikeProfile = null;
        _isLoadingSelectedBikeProfile = false;
      });
      return;
    }

    setState(() => _isLoadingSelectedBikeProfile = true);

    try {
      final bikeshopService =
          Provider.of<BikeshopService>(context, listen: false);
      final profile = await bikeshopService.getBikeProfile(bike!.id!);

      if (!mounted || _selectedBike?.id != bike.id) {
        return;
      }

      setState(() {
        _selectedBikeProfile = profile;
      });
    } catch (e) {
      debugPrint('⚠️ Error loading selected bike profile: $e');
    } finally {
      if (mounted && _selectedBike?.id == bike?.id) {
        setState(() => _isLoadingSelectedBikeProfile = false);
      }
    }
  }

  Future<void> _openSelectedBikeRecord() async {
    final customerId = _selectedCustomer?.id;
    final bikeId = _selectedBike?.id;
    if (customerId == null || bikeId == null) return;

    final route = Uri(
      path: '/clientes/$customerId',
      queryParameters: {
        'bike_id': bikeId,
      },
    ).toString();

    await context.push(route);

    if (!mounted) return;
    await _refreshCustomerBikes(selectedBikeId: bikeId);
  }

  Widget _buildBikeProfileSummaryCard() {
    if (_selectedBike == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final snapshot = BikeRecordSnapshot.fromBikeAndProfile(
      bike: _selectedBike!,
      profile: _selectedBikeProfile,
    );
    final canOpenProfile =
        _selectedCustomer?.id != null && _selectedBike?.id != null;
    final actionLabel =
        snapshot.hasStructuredProfile ? 'Editar ficha' : 'Completar ficha';
    final highlights = snapshot.summaryHighlights;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.summarize_outlined,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Contexto de la bicicleta',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Tooltip(
                message: 'Ver perfil completo',
                child: IconButton(
                  onPressed: canOpenProfile ? _openSelectedBikeRecord : null,
                  icon: const Icon(Icons.open_in_new_rounded, size: 17),
                  visualDensity: VisualDensity.compact,
                  splashRadius: 18,
                  constraints: const BoxConstraints.tightFor(
                    width: 34,
                    height: 34,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  await _openBikeDialog(
                    bike: _selectedBike,
                    selectSavedBike: true,
                  );
                },
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: Text(actionLabel),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            snapshot.profile?.identityLine ??
                BikeProfileSummaryBuilder.buildIdentityLine(_selectedBike!),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          if (_isLoadingSelectedBikeProfile)
            const LinearProgressIndicator()
          else ...[
            if (!snapshot.hasStructuredProfile)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Aun no hay perfil estructurado guardado para esta bicicleta.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else if (highlights.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Aun no hay resumen disponible para esta bicicleta.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (highlights.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: highlights
                    .map(
                      (line) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: theme.dividerColor.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(line, style: theme.textTheme.bodySmall),
                      ),
                    )
                    .toList(),
              ),
          ],
          if (snapshot.warnings.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...snapshot.warnings.map(
              (warning) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 16, color: theme.colorScheme.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        warning,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (snapshot.lastConfirmedAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Ultima confirmacion: ${DateFormat('dd/MM/yyyy').format(snapshot.lastConfirmedAt!)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Show bike selector to add a bike
  Future<void> _showAddBikeSelector() async {
    if (_selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero seleccione un cliente')),
      );
      return;
    }

    // Get customer bikes that aren't already in tabs
    final availableBikes = _bikes
        .where((bike) => !_bikeTabs.any((tab) => tab.bike?.id == bike.id))
        .toList();

    if (availableBikes.isEmpty) {
      // Show option to create new bike
      final newBike = await _openBikeDialog(selectSavedBike: true);

      if (newBike != null && mounted) {
        _addBikeTab(newBike);
      }
      return;
    }

    // Show bike selection popup
    final selected = await showDialog<Bike?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar Bicicleta'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...availableBikes.map((bike) => ListTile(
                    leading: const Icon(Icons.pedal_bike),
                    title: Text(bike.displayName),
                    subtitle: bike.serialNumber != null
                        ? Text('S/N: ${bike.serialNumber}')
                        : null,
                    onTap: () => Navigator.pop(context, bike),
                  )),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Nueva bicicleta'),
                onTap: () async {
                  Navigator.pop(context); // Close selector
                  final newBike = await _openBikeDialog(selectSavedBike: true);
                  if (newBike != null && mounted) {
                    _addBikeTab(newBike);
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

    if (selected != null && mounted) {
      _addBikeTab(selected);
    }
  }

  /// Get the current part items list (from bike tab or legacy)
  List<_JobPartItem> get _currentPartItems {
    final tab = _currentBikeTab;
    return tab != null ? tab.partItems : _partItems;
  }

  Future<void> _addCatalogPart(Product product) async {
    if (!mounted) return;
    setState(() {
      _currentPartItems.add(_JobPartItem(
        product: product,
        name: product.name,
        isCatalogProduct: true,
        isServiceItem: product.isService,
        quantity: 1,
        unitPrice: product.price,
        notes: null,
      ));
      _partAutocompleteKey++; // Reset autocomplete field
    });
  }

  void _addCustomPart(String description) {
    // Ad-hoc part with no product reference
    setState(() {
      _currentPartItems.add(_JobPartItem(
        product: null,
        name: description,
        isCatalogProduct: false,
        isServiceItem: false,
        quantity: 1,
        unitPrice: 0, // User must enter price manually
        notes: null,
      ));
      _partAutocompleteKey++; // Reset autocomplete field
    });
  }

  void _addEmptyPartLine() {
    // Add an empty line for the user to fill in
    setState(() {
      _currentPartItems.add(_JobPartItem(
        product: null,
        name: '',
        isCatalogProduct: false,
        isServiceItem: false,
        quantity: 1,
        unitPrice: 0,
        notes: null,
      ));
    });
  }

  String _itemTypeForPartItem(_JobPartItem item) {
    if (item.isServiceItem) return 'service';
    return item.isCatalogProduct ? 'product' : 'adhoc';
  }

  String? _serviceProductIdForPartItem(_JobPartItem item) {
    if (!item.isServiceItem) return null;
    return item.product?.id;
  }

  void _addServiceItem() {
    showDialog(
      context: context,
      builder: (context) => _ServiceEntryDialog(
        serviceProducts: _serviceProducts,
        onServiceAdded: (serviceProduct, description, hours, rate, date) {
          setState(() {
            final trimmedDescription = description.trim();
            _serviceItems.add(_JobServiceItem(
              serviceProduct: serviceProduct,
              description: trimmedDescription.isNotEmpty
                  ? trimmedDescription
                  : serviceProduct?.name ?? '',
              hours: hours,
              hourlyRate: rate,
              date: date,
            ));
          });
        },
      ),
    );
  }

  void _focusPartAutocomplete() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusScope.of(context).requestFocus(_partAutocompleteFocus);
    });
  }

  /// Total parts cost across all bikes (multi-bike support)
  double get _partsCost {
    // If using multi-bike tabs, sum from all bike tabs
    if (_bikeTabs.isNotEmpty) {
      return _bikeTabs.fold(0.0, (sum, tab) {
        return sum +
            tab.partItems.fold(0.0,
                (itemSum, item) => itemSum + (item.quantity * item.unitPrice));
      });
    }
    // Legacy single-bike mode
    return _partItems.fold(
        0.0, (sum, item) => sum + (item.quantity * item.unitPrice));
  }

  /// Get subtotal for current bike tab only (for display in chip)
  double get _currentBikeSubtotal {
    final tab = _currentBikeTab;
    if (tab != null) {
      return tab.partItems
          .fold(0.0, (sum, item) => sum + (item.quantity * item.unitPrice));
    }
    return _partItems.fold(
        0.0, (sum, item) => sum + (item.quantity * item.unitPrice));
  }

  double get _serviceCost {
    return _serviceItems.fold(0.0, (sum, item) => sum + item.total);
  }

  double get _subtotal {
    return _partsCost + _serviceCost;
  }

  double get _discountAmount {
    return double.tryParse(_discountController.text) ?? 0.0;
  }

  double get _total {
    // Total is ALWAYS subtotal - discount (customer pays this)
    return _subtotal - _discountAmount;
  }

  /// Maps StatusPhase to JobStatus for legacy compatibility
  JobStatus _mapPhaseToJobStatus(StatusPhase phase) {
    switch (phase) {
      case StatusPhase.todo:
        return JobStatus.pendiente;
      case StatusPhase.inProgress:
        return JobStatus.enCurso;
      case StatusPhase.complete:
        return JobStatus.finalizado;
    }
  }

  int get _debugLocalPersistablePartCount {
    return _bikeTabs.fold<int>(0, (sum, tab) {
      return sum +
          tab.partItems
              .where((item) => item.displayName.trim().isNotEmpty)
              .length;
    });
  }

  int get _debugLocalPersistableServiceCount {
    return _serviceItems
        .where((item) => item.displayName.trim().isNotEmpty)
        .length;
  }

  String _debugSummarizeLabels(Iterable<String> labels) {
    final cleaned = labels
        .map((label) => label.trim())
        .where((label) => label.isNotEmpty)
        .toList();

    if (cleaned.isEmpty) {
      return '-';
    }

    const maxLabels = 5;
    if (cleaned.length <= maxLabels) {
      return cleaned.join(' | ');
    }

    final remaining = cleaned.length - maxLabels;
    return '${cleaned.take(maxLabels).join(' | ')} | +$remaining más';
  }

  Future<void> _debugLogPegaInvoiceSnapshot(
    String stage, {
    required String jobId,
    String? invoiceId,
  }) async {
    if (!kDebugMode) {
      return;
    }

    try {
      final bikeshopService = Provider.of<BikeshopService>(
        context,
        listen: false,
      );
      final databaseService = Provider.of<DatabaseService>(
        context,
        listen: false,
      );

      final savedJob = await bikeshopService.getJobById(jobId);
      final persistedItems = await bikeshopService.getJobItems(jobId);
      final effectiveInvoiceId = invoiceId ?? savedJob?.invoiceId;

      List<dynamic> invoiceItems = const [];
      dynamic invoiceSubtotal;
      dynamic invoiceTotal;

      if (effectiveInvoiceId != null) {
        final invoiceData = await databaseService.selectById(
          'sales_invoices',
          effectiveInvoiceId,
        );
        if (invoiceData != null) {
          final rawItems = invoiceData['items'];
          if (rawItems is List) {
            invoiceItems = rawItems;
          }
          invoiceSubtotal = invoiceData['subtotal'];
          invoiceTotal = invoiceData['total'];
        }
      }

      final localLabels = <String>[
        ..._bikeTabs.expand(
          (tab) => tab.partItems.map((item) => item.displayName),
        ),
        ..._serviceItems.map((item) => item.displayName),
      ];
      final persistedLabels = persistedItems.map((item) => item.productName);
      final invoiceLabels = invoiceItems.map((item) {
        if (item is Map) {
          return (item['product_name'] ?? '').toString();
        }
        return '';
      });

      debugPrint(
        '🧪 [PEGA SAVE][$stage] '
        'job=$jobId '
        'invoice=${effectiveInvoiceId ?? '-'} '
        'local_parts=$_debugLocalPersistablePartCount '
        'local_services=$_debugLocalPersistableServiceCount '
        'persisted_items=${persistedItems.length} '
        'job_total=${savedJob?.totalCost} '
        'invoice_items=${invoiceItems.length} '
        'invoice_subtotal=$invoiceSubtotal '
        'invoice_total=$invoiceTotal',
      );
      debugPrint(
        '🧪 [PEGA SAVE][$stage] local_labels=${_debugSummarizeLabels(localLabels)}',
      );
      debugPrint(
        '🧪 [PEGA SAVE][$stage] persisted_labels=${_debugSummarizeLabels(persistedLabels)}',
      );
      debugPrint(
        '🧪 [PEGA SAVE][$stage] invoice_labels=${_debugSummarizeLabels(invoiceLabels)}',
      );
    } catch (e) {
      debugPrint('🧪 [PEGA SAVE][$stage] debug snapshot failed: $e');
    }
  }

  void _handleCancel() {
    if (widget.isEmbedded) {
      if (widget.onCanceled != null) widget.onCanceled!();
    } else {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/taller/pegas');
      }
    }
  }

  Future<void> _saveJob() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe seleccionar un cliente')),
      );
      return;
    }

    final requiresBike =
        _jobType == JobType.service || _jobType == JobType.warranty;

    // Service and warranty jobs require a bicycle
    if (requiresBike && _bikeTabs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Debe seleccionar al menos una bicicleta')),
      );
      return;
    }

    if (_jobType == JobType.itemService && _selectedSubject == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe seleccionar un componente o ítem del catálogo'),
        ),
      );
      return;
    }

    if (_jobType == JobType.quotation &&
        _subjectNotesController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Describa qué producto o servicio desea cotizar'),
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final bikeshopService =
          Provider.of<BikeshopService>(context, listen: false);

      // Upload new images
      List<String> uploadedUrls = List.from(_imageUrls);

      if (_newImages.isNotEmpty) {
        for (var imageData in _newImages) {
          try {
            final timestamp = DateTime.now().millisecondsSinceEpoch;
            final fileName = 'job_${_selectedCustomer!.id}_$timestamp.jpg';

            final url = await ImageService.uploadBytes(
              bytes: imageData.bytes,
              fileName: fileName,
              bucket: 'vinabike-assets', // Using existing public bucket
              folder: 'mechanic_jobs/${_selectedCustomer!.id!}',
            );

            if (url != null) {
              uploadedUrls.add(url);
            }
          } catch (e) {
            debugPrint('Error uploading image: $e');
            // Continue with other images even if one fails
          }
        }
      }

      final tenantId = await TenantService().getTenantId();
      if (tenantId == null) {
        throw Exception('User does not have a tenant_id. Cannot proceed.');
      }

      // Use first bike as the "primary" bike for legacy compatibility
      final primaryBike = _bikeTabs.isNotEmpty ? _bikeTabs.first.bike : null;
      if (requiresBike && primaryBike?.id == null) {
        throw Exception('La primera bicicleta no tiene ID');
      }

      // Get combined data from first bike tab for job-level fields (legacy)
      final firstTab = _bikeTabs.isNotEmpty ? _bikeTabs.first : null;

      // Create MechanicJob object (job-level data)
      final job = MechanicJob(
        id: widget.jobId,
        tenantId: tenantId,
        jobNumber:
            _existingJob?.jobNumber ?? '', // Will be auto-generated if empty
        customerId: _selectedCustomer!.id!,
        bikeId: primaryBike?.id, // Nullable for non-bike jobs
        jobType: _jobType,
        subjectId:
            _jobType == JobType.itemService ? _selectedSubject?.id : null,
        subjectNotes: _subjectNotesController.text.isNotEmpty
            ? _subjectNotesController.text
            : null,
        warrantyOutcome: _warrantyOutcome,
        quotationStatus: _quotationStatus,
        quotationValidUntil: _quotationValidUntil,
        priority: _selectedPriority,
        status: _selectedStatus,
        statusId: _selectedCustomStatus?.id, // Custom status ID
        arrivalDate: _selectedArrivalDate,
        diagnosticDeadline: _existingJob?.diagnosticDeadline, // ✅ Preserve
        servicePackageId: _existingJob?.servicePackageId, // ✅ Preserve
        warrantyNotes: _existingJob?.warrantyNotes, // ✅ Preserve
        convertedAt: _existingJob?.convertedAt, // ✅ Preserve
        convertedFromId: _existingJob?.convertedFromId, // ✅ Preserve
        assignedTo: _existingJob?.assignedTo, // ✅ Preserve
        assignedTechnicianName:
            _existingJob?.assignedTechnicianName, // ✅ Preserve
        diagnosticSentAt: _existingJob?.diagnosticSentAt, // ✅ Preserve
        startedAt: _existingJob?.startedAt, // ✅ Preserve
        completedAt: _existingJob?.completedAt, // ✅ Preserve
        deliveredAt: _existingJob?.deliveredAt, // ✅ Preserve
        createdAt: _existingJob?.createdAt ?? DateTime.now(),
        // Store first bike's data in legacy fields for backward compat
        clientRequest: firstTab != null &&
                firstTab.clientRequestController.text.trim().isNotEmpty
            ? firstTab.clientRequestController.text.trim()
            : (_clientRequestController.text.trim().isNotEmpty
                ? _clientRequestController.text.trim()
                : null),
        diagnosis: firstTab != null &&
                firstTab.diagnosisController.text.trim().isNotEmpty
            ? firstTab.diagnosisController.text.trim()
            : (_diagnosisController.text.trim().isNotEmpty
                ? _diagnosisController.text.trim()
                : null),
        workPerformed: firstTab != null &&
                firstTab.workRequestedController.text.trim().isNotEmpty
            ? firstTab.workRequestedController.text.trim()
            : (_workSummaryController.text.trim().isNotEmpty
                ? _workSummaryController.text.trim()
                : null),
        notes: firstTab != null &&
                firstTab.technicianNotesController.text.trim().isNotEmpty
            ? firstTab.technicianNotesController.text.trim()
            : (_technicianNotesController.text.trim().isNotEmpty
                ? _technicianNotesController.text.trim()
                : null),
        deliveryDeadline: _selectedDeadline,
        requiresApproval: firstTab?.requiresApproval ?? _requiresApproval,
        isWarrantyJob:
            firstTab?.isWarrantyWork ?? (_jobType == JobType.warranty),
        discountAmount: _discountAmount,
        estimatedCost: 0,
        finalCost: 0,
        partsCost: 0,
        laborCost: 0,
        taxAmount: 0,
        totalCost: 0,
        taxTreatment: _taxTreatment,
        invoiceId: _existingJob?.invoiceId,
        isInvoiced: _existingJob?.isInvoiced ?? false,
        isPaid: _existingJob?.isPaid ?? false,
        imageUrls: uploadedUrls,
      );

      String jobId;

      if (widget.jobId != null) {
        // Update existing job
        await bikeshopService.updateJob(job, syncBikeMemory: false);
        jobId = widget.jobId!;
      } else {
        // Create new job
        final createdJob = await bikeshopService.createJob(job);
        jobId = createdJob.id!;
      }

      // ============================================================
      // MULTI-BIKE: Save each bike tab as MechanicJobBike + its items
      // ============================================================

      // First, delete all existing job items (we'll re-create them)
      if (widget.jobId != null) {
        final existingItems = await bikeshopService.getJobItems(jobId);
        for (final existing in existingItems) {
          if (existing.id != null) {
            await bikeshopService.deleteJobItem(
              existing.id!,
              syncBikeMemory: false,
            );
          }
        }

        // Delete existing job bikes (we'll re-create them)
        final existingJobBikes = await bikeshopService.getJobBikes(jobId);
        for (final existingJB in existingJobBikes) {
          if (existingJB.id != null) {
            await bikeshopService.removeBikeFromJob(
              existingJB.id!,
              syncBikeMemory: false,
            );
          }
        }
      }

      final taskService = Provider.of<SmartTaskService>(context, listen: false);

      // Save each bike tab
      for (int i = 0; i < _bikeTabs.length; i++) {
        final tab = _bikeTabs[i];

        if (tab.isGeneralTab) {
          // Save General tab parts with jobBikeId = null
          for (final item in tab.partItems) {
            if (item.name.isEmpty) continue; // Skip empty rows

            final quantity = item.quantity.toDouble();
            final unitPrice = item.unitPrice;
            final jobItem = MechanicJobItem(
              jobId: jobId,
              jobBikeId: null, // General items have no bike
              tenantId: tenantId,
              productId: item.product?.id,
              serviceProductId: _serviceProductIdForPartItem(item),
              productName: item.name,
              productSku: item.sku ?? '',
              quantity: quantity,
              unitPrice: unitPrice,
              totalPrice: quantity * unitPrice,
              itemType: _itemTypeForPartItem(item),
              location: item.location,
              notes: item.notes,
            );
            final created = await bikeshopService.createJobItem(
              jobItem,
              syncBikeMemory: false,
            );

            // Auto-generate tasks from product description if available
            if (item.product != null &&
                item.product!.description != null &&
                item.product!.description!.isNotEmpty &&
                created.id != null) {
              try {
                await taskService.generateAutoTasksFromDescription(
                  jobId: jobId,
                  parentItemId: created.id!,
                  description: item.product!.description!,
                );
                debugPrint('✅ Auto-tasks generated for ${item.name}');
              } catch (e) {
                debugPrint(
                    '⚠️ Failed to generate auto-tasks for ${item.name}: $e');
              }
            }
          }
          continue; // Skip MechanicJobBike creation
        }

        if (tab.bike?.id == null) {
          debugPrint('⚠️ Skipping bike tab $i - no bike ID');
          continue;
        }

        // Create MechanicJobBike record for this bike
        final jobBike = MechanicJobBike(
          id: null, // Always create new (we deleted old ones)
          tenantId: tenantId,
          jobId: jobId,
          bikeId: tab.bike!.id!,
          orderIndex: i,
          diagnosis: tab.diagnosisController.text.trim().isEmpty
              ? null
              : tab.diagnosisController.text.trim(),
          workRequested: tab.clientRequestController.text.trim().isEmpty
              ? null
              : tab.clientRequestController.text.trim(),
          workPerformed: tab.workRequestedController.text.trim().isEmpty
              ? null
              : tab.workRequestedController.text.trim(),
          technicianNotes: tab.technicianNotesController.text.trim().isEmpty
              ? null
              : tab.technicianNotesController.text.trim(),
          diagnosisSheetKey:
              tab.diagnosisSheetKey ?? tab.diagnosisSheet.templateKey,
          diagnosisSheet: tab.diagnosisSheet,
          diagnosisSheetUpdatedAt: tab.diagnosisSheet.hasMeaningfulData
              ? (tab.diagnosisSheetUpdatedAt ?? DateTime.now())
              : null,
          isWarrantyWork: tab.isWarrantyWork,
          requiresApproval: tab.requiresApproval,
          approvedByCustomer: tab.approvedByCustomer,
        );

        final createdJobBike = await bikeshopService.addBikeToJob(
          jobBike,
          syncBikeMemory: false,
        );
        final jobBikeId = createdJobBike.id;

        debugPrint(
            '✅ Created job bike: ${tab.bike!.displayName} (id: $jobBikeId)');

        // Save this bike's parts/products
        for (final item in tab.partItems) {
          if (item.name.isEmpty) continue; // Skip empty rows

          final quantity = item.quantity.toDouble();
          final unitPrice = item.unitPrice;
          final jobItem = MechanicJobItem(
            jobId: jobId,
            jobBikeId: jobBikeId, // Link to specific bike!
            tenantId: tenantId,
            productId: item.product?.id,
            serviceProductId: _serviceProductIdForPartItem(item),
            productName: item.name,
            productSku: item.sku ?? '',
            quantity: quantity,
            unitPrice: unitPrice,
            totalPrice: quantity * unitPrice,
            itemType: _itemTypeForPartItem(item),
            location: item.location,
            notes: item.notes, // ✅ Save the description!
          );
          final created = await bikeshopService.createJobItem(
            jobItem,
            syncBikeMemory: false,
          );

          // Auto-generate tasks from product description if available
          if (item.product != null &&
              item.product!.description != null &&
              item.product!.description!.isNotEmpty &&
              created.id != null) {
            try {
              await taskService.generateAutoTasksFromDescription(
                jobId: jobId,
                parentItemId: created.id!,
                description: item.product!.description!,
              );
              debugPrint('✅ Auto-tasks generated for ${item.name}');
            } catch (e) {
              debugPrint(
                  '⚠️ Failed to generate auto-tasks for ${item.name}: $e');
            }
          }
        }
      }

      // For non-service jobs (no bike tabs): save items from legacy _partItems
      if (_bikeTabs.isEmpty && _partItems.isNotEmpty) {
        for (final item in _partItems) {
          if (item.name.isEmpty) continue;
          final quantity = item.quantity.toDouble();
          final unitPrice = item.unitPrice;
          final jobItem = MechanicJobItem(
            jobId: jobId,
            jobBikeId: null,
            tenantId: tenantId,
            productId: item.product?.id,
            serviceProductId: _serviceProductIdForPartItem(item),
            productName: item.name,
            productSku: item.sku ?? '',
            quantity: quantity,
            unitPrice: unitPrice,
            totalPrice: quantity * unitPrice,
            itemType: _itemTypeForPartItem(item),
            location: item.location,
            notes: item.notes,
          );
          final created = await bikeshopService.createJobItem(
            jobItem,
            syncBikeMemory: false,
          );
          if (item.product != null &&
              item.product!.description != null &&
              item.product!.description!.isNotEmpty &&
              created.id != null) {
            try {
              await taskService.generateAutoTasksFromDescription(
                jobId: jobId,
                parentItemId: created.id!,
                description: item.product!.description!,
              );
            } catch (e) {
              debugPrint(
                  '⚠️ Failed to generate auto-tasks for ${item.name}: $e');
            }
          }
        }
      }

      // Add services (job-level, not per-bike for now)
      for (final service in _serviceItems) {
        final hoursWorked = service.hours;
        final hourlyRate = service.hourlyRate;
        final serviceProduct = service.serviceProduct;
        final name = service.description.isNotEmpty
            ? service.description
            : serviceProduct?.name ?? 'Servicio';

        final jobServiceItem = MechanicJobItem(
          jobId: jobId,
          tenantId: tenantId,
          productId: serviceProduct?.id,
          serviceProductId: serviceProduct?.id,
          productName: name,
          productSku: serviceProduct?.sku,
          quantity: hoursWorked,
          unitPrice: hourlyRate,
          totalPrice: service.total,
          notes:
              'Labor: ${hoursWorked.toStringAsFixed(1)}h @ \$${hourlyRate.toStringAsFixed(0)}/hr',
        );

        final created = await bikeshopService.createJobItem(
          jobServiceItem,
          syncBikeMemory: false,
        );

        if (serviceProduct != null &&
            serviceProduct.description != null &&
            serviceProduct.description!.isNotEmpty &&
            created.id != null) {
          try {
            await taskService.generateAutoTasksFromDescription(
              jobId: jobId,
              parentItemId: created.id!,
              description: serviceProduct.description!,
            );
            debugPrint('✅ Auto-tasks generated for service $name');
          } catch (e) {
            debugPrint(
                '⚠️ Failed to generate auto-tasks for service $name: $e');
          }
        }
      }

      await bikeshopService.syncBikeMemoryFromJob(jobId);

      await _debugLogPegaInvoiceSnapshot(
        'before_invoice_phase',
        jobId: jobId,
      );

      // Sync invoice AFTER all items are written.
      // For brand new jobs, the DB may already have linked an invoice,
      // so always re-read the saved job before deciding whether to sync or create.
      final savedJob = await bikeshopService.getJobById(jobId);
      final linkedInvoiceId = savedJob?.invoiceId;

      bool shouldInvoice = true;
      if (savedJob != null) {
        if (savedJob.jobType == JobType.quotation) {
          shouldInvoice = false;
        } else if (savedJob.jobType == JobType.warranty &&
            savedJob.warrantyOutcome != WarrantyOutcome.notCovered) {
          shouldInvoice = false;
        }
      }

      if (linkedInvoiceId != null) {
        // If there's an existing invoice, we still sync it just to keep it updated,
        // (unless we want to delete it if it's a quotation now, but we'll assume
        // quotes don't get invoices attached in the first place).
        debugPrint('🔄 Syncing job to invoice: $linkedInvoiceId');
        await bikeshopService.syncJobToInvoice(jobId);
        await _updateInvoiceTaxTreatment(linkedInvoiceId);
        await _debugLogPegaInvoiceSnapshot(
          'after_invoice_sync',
          jobId: jobId,
          invoiceId: linkedInvoiceId,
        );
      } else if (shouldInvoice) {
        debugPrint('🧾 No linked invoice yet, creating one after items save');
        final createdInvoiceId =
            await bikeshopService.createInvoiceFromJob(jobId);
        if (createdInvoiceId != null) {
          await _updateInvoiceTaxTreatment(createdInvoiceId);
        }
        await _debugLogPegaInvoiceSnapshot(
          'after_invoice_create',
          jobId: jobId,
          invoiceId: createdInvoiceId,
        );
      } else {
        debugPrint(
            'ℹ️ Skipping invoice generation for JobType: ${savedJob?.jobType}, outcome: ${savedJob?.warrantyOutcome}');
      }

      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.jobId != null
                ? 'Pega actualizada correctamente'
                : 'Pega creada correctamente'),
            backgroundColor: Colors.green,
          ),
        );
        if (widget.isEmbedded) {
          if (widget.onSaved != null) widget.onSaved!();
        } else {
          if (context.canPop()) {
            context.pop(true);
          } else {
            context.go('/taller/pegas');
          }
        }
      }
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar pega: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _updateInvoiceTaxTreatment(String invoiceId) async {
    try {
      final databaseService =
          Provider.of<DatabaseService>(context, listen: false);

      // Fetch the current invoice
      final invoiceData =
          await databaseService.selectById('sales_invoices', invoiceId);
      if (invoiceData == null) {
        debugPrint('⚠️ Invoice not found: $invoiceId');
        return;
      }

      final invoice = Invoice.fromJson(invoiceData);

      // Check if tax treatment actually changed
      final currentTaxTreatment = invoice.taxTreatment;
      if (currentTaxTreatment == _taxTreatment) {
        debugPrint('✅ Tax treatment unchanged: $_taxTreatment');
        return;
      }

      debugPrint(
          '🔄 Updating invoice tax treatment: $currentTaxTreatment → $_taxTreatment');

      // Recalculate invoice totals based on new tax treatment
      // Note: subtotal stays the same (sum of line items), we only change net_amount and iva_amount
      final subtotal = invoice.subtotal;
      double netAmount;
      double ivaAmount;
      final total =
          subtotal; // Total is always the subtotal (what customer pays)

      if (_taxTreatment == TaxTreatment.noTax) {
        // No tax: net = full subtotal, iva = 0
        netAmount = subtotal;
        ivaAmount = 0;
      } else {
        // Tax included: net = subtotal ÷ 1.19, iva = subtotal - net
        netAmount = subtotal / 1.19;
        ivaAmount = subtotal - netAmount;
      }

      debugPrint(
          '💰 Recalculated: subtotal=$subtotal, net=$netAmount, iva=$ivaAmount, total=$total');

      // Update the invoice
      await databaseService.update(
        'sales_invoices',
        invoiceId,
        {
          'tax_treatment': _taxTreatment.toValue(),
          'net_amount': netAmount,
          'iva_amount': ivaAmount,
          'total': total,
          'balance': total - invoice.paidAmount,
          'updated_at': DateTime.now().toIso8601String(),
        },
      );

      debugPrint('✅ Invoice tax treatment updated successfully');
    } catch (e) {
      debugPrint('❌ Error updating invoice tax treatment: $e');
      // Don't rethrow - this shouldn't block saving the pega
    }
  }

  Future<void> _sendWhatsAppUpdate() async {
    if (_selectedCustomer == null ||
        _selectedBike == null ||
        _existingJob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No hay datos suficientes para enviar mensaje')),
      );
      return;
    }

    // Check if customer has phone number
    if (_selectedCustomer!.phone == null || _selectedCustomer!.phone!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('El cliente no tiene número de teléfono registrado')),
      );
      return;
    }

    try {
      final whatsappService = WhatsAppService();
      final success = await whatsappService.sendJobStatusUpdate(
        context: context,
        customerPhone: _selectedCustomer!.phone!,
        customerName: _selectedCustomer!.name,
        job: _existingJob!,
        bikeBrand: _selectedBike!.brand ?? 'Bicicleta',
        bikeModel: _selectedBike!.model,
      );

      if (success && mounted) {
        final content = switch (whatsappService.lastDeliveryMethod) {
          WhatsAppDeliveryMethod.cloudApi =>
            'Mensaje enviado por WhatsApp Cloud API',
          WhatsAppDeliveryMethod.manualFallback =>
            'WhatsApp abierto con mensaje pre-llenado',
          WhatsAppDeliveryMethod.failed => 'Mensaje procesado',
        };

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(content),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir WhatsApp')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _sendReadyForPickupMessage() async {
    if (_selectedCustomer == null ||
        _selectedBike == null ||
        _existingJob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No hay datos suficientes para enviar mensaje')),
      );
      return;
    }

    // Check if customer has phone number
    if (_selectedCustomer!.phone == null || _selectedCustomer!.phone!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('El cliente no tiene número de teléfono registrado')),
      );
      return;
    }

    try {
      final whatsappService = WhatsAppService();
      final success = await whatsappService.sendReadyForPickup(
        context: context,
        customerPhone: _selectedCustomer!.phone!,
        customerName: _selectedCustomer!.name,
        job: _existingJob!,
        bikeBrand: _selectedBike!.brand ?? 'Bicicleta',
        bikeModel: _selectedBike!.model,
      );

      if (success && mounted) {
        final content = switch (whatsappService.lastDeliveryMethod) {
          WhatsAppDeliveryMethod.cloudApi =>
            'Notificación enviada por WhatsApp Cloud API',
          WhatsAppDeliveryMethod.manualFallback =>
            'WhatsApp abierto - Notifica al cliente que su bici está lista',
          WhatsAppDeliveryMethod.failed => 'Mensaje procesado',
        };

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(content),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir WhatsApp')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _confirmDeleteBike(Bike bike) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text(
          '¿Está seguro de eliminar la bicicleta "${bike.displayName}"?\n\n'
          'Esta acción no se puede deshacer.',
        ),
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

    if (confirmed == true) {
      if (!mounted) return;

      try {
        final bikeshopService =
            Provider.of<BikeshopService>(context, listen: false);
        await bikeshopService.deleteBike(bike.id!);

        await _refreshCustomerBikes();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Bicicleta "${bike.displayName}" eliminada correctamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al eliminar bicicleta: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showBikeManagementDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gestionar Bicicletas'),
        content: SizedBox(
          width: 500,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _bikes.length,
            itemBuilder: (context, index) {
              final bike = _bikes[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.pedal_bike),
                  title: Text(bike.displayName),
                  subtitle: bike.serialNumber != null
                      ? Text('S/N: ${bike.serialNumber}')
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () async {
                          Navigator.pop(context); // Close management dialog

                          await _openBikeDialog(
                            bike: bike,
                            selectSavedBike: _selectedBike?.id == bike.id,
                          );
                        },
                        tooltip: 'Editar',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          Navigator.pop(context); // Close dialog
                          _confirmDeleteBike(bike);
                        },
                        tooltip: 'Eliminar',
                      ),
                    ],
                  ),
                ),
              );
            },
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Form(
      key: _formKey,
      child: Column(
        children: [
          _buildHeader(theme),
          Expanded(
            child: _isLoading
                ? const Center(child: BrandedLoading())
                : _buildForm(theme),
          ),
        ],
      ),
    );

    if (widget.isEmbedded) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: content,
      );
    }

    return MainLayout(child: content);
  }

  Widget _buildHeader(ThemeData theme) {
    final isEditing = widget.jobId != null;
    final title = isEditing ? 'Editar Trabajo' : 'Nuevo Trabajo';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: theme.dividerColor,
                width: 1,
              ),
            ),
          ),
          child: isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        if (isEditing &&
                            _selectedCustomer != null &&
                            _selectedBike != null) ...[
                          if (_jobType == JobType.quotation &&
                              _quotationStatus == QuotationStatus.pending) ...[
                            FilledButton.icon(
                              onPressed: _isSaving
                                  ? null
                                  : () {
                                      setState(() {
                                        _jobType = JobType.service;
                                        _quotationStatus =
                                            QuotationStatus.approved;
                                      });
                                      _saveJob();
                                    },
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('Aprobar Presupuesto'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.orange.shade700,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (_selectedStatus == JobStatus.finalizado ||
                              _selectedStatus == JobStatus.entregado)
                            OutlinedButton.icon(
                              onPressed: () => _sendReadyForPickupMessage(),
                              icon: const Icon(Icons.check_circle,
                                  color: Colors.green),
                              label: const Text('Avisar Cliente'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.green,
                              ),
                            )
                          else
                            OutlinedButton.icon(
                              onPressed: () => _sendWhatsAppUpdate(),
                              icon: const Icon(Icons.message,
                                  color: Colors.green),
                              label: const Text('WhatsApp'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.green,
                              ),
                            ),
                        ],
                        OutlinedButton.icon(
                          onPressed: _isSaving ? null : _handleCancel,
                          icon: const Icon(Icons.close),
                          label: const Text('Cancelar'),
                        ),
                        FilledButton.icon(
                          onPressed: _isSaving ? null : _saveJob,
                          icon: _isSaving
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save),
                          label: const Text('Guardar'),
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (isEditing &&
                        _selectedCustomer != null &&
                        _selectedBike != null) ...[
                      if (_jobType == JobType.quotation &&
                          _quotationStatus == QuotationStatus.pending) ...[
                        FilledButton.icon(
                          onPressed: _isSaving
                              ? null
                              : () {
                                  setState(() {
                                    _jobType = JobType.service;
                                    _quotationStatus = QuotationStatus.approved;
                                  });
                                  _saveJob();
                                },
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('Aprobar Presupuesto'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.orange.shade700,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (_selectedStatus == JobStatus.finalizado ||
                          _selectedStatus == JobStatus.entregado)
                        OutlinedButton.icon(
                          onPressed: () => _sendReadyForPickupMessage(),
                          icon: const Icon(Icons.check_circle,
                              color: Colors.green),
                          label: const Text('Avisar Cliente'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green,
                          ),
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: () => _sendWhatsAppUpdate(),
                          icon: const Icon(Icons.message, color: Colors.green),
                          label: const Text('WhatsApp'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green,
                          ),
                        ),
                      const SizedBox(width: 12),
                    ],
                    OutlinedButton.icon(
                      onPressed: _isSaving ? null : _handleCancel,
                      icon: const Icon(Icons.close),
                      label: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _saveJob,
                      icon: _isSaving
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save),
                      label: const Text('Guardar'),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _pickAttachment() async {
    try {
      setState(() {
        _isUploadingImage = true;
      });

      final result = await ImageService.pickFile();

      setState(() {
        _isUploadingImage = false;
      });

      if (result != null) {
        setState(() {
          _newImages.add((bytes: result.bytes, name: result.name));
        });
      }
    } catch (e) {
      setState(() {
        _isUploadingImage = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al adjuntar archivo: $e')),
        );
      }
    }
  }

  bool _isImage(String name) {
    final ext = name.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'].contains(ext);
  }

  void _removeImage(int index, bool isNew) {
    setState(() {
      if (isNew) {
        _newImages.removeAt(index);
      } else {
        _imageUrls.removeAt(index);
      }
    });
  }

  Widget _buildAttachmentsSection() {
    if (_imageUrls.isEmpty && _newImages.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            onPressed: _isUploadingImage ? null : _pickAttachment,
            icon: _isUploadingImage
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.attach_file),
            label: const Text('Adjuntar archivo'),
          ),
          const SizedBox(height: 8),
          Text(
            'Sin adjuntos',
            style:
                TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            // Calculate item width based on available width
            final crossAxisCount =
                (constraints.maxWidth / 120).floor().clamp(2, 6);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemCount: _imageUrls.length +
                  _newImages.length +
                  1, // +1 for add button
              itemBuilder: (context, index) {
                // Add button is always last
                if (index == _imageUrls.length + _newImages.length) {
                  return InkWell(
                    onTap: _isUploadingImage ? null : _pickAttachment,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey[50], // Sutil background
                      ),
                      child: Center(
                        child: _isUploadingImage
                            ? const CircularProgressIndicator()
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.attach_file,
                                      color: Colors.grey[600]),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Agregar',
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

                // Determine if it's an existing URL or a new local image
                final isNew = index >= _imageUrls.length;
                final relativeIndex = isNew ? index - _imageUrls.length : index;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // Image thumbnail
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: isNew
                          ? (_isImage(_newImages[relativeIndex].name)
                              ? Image.memory(
                                  _newImages[relativeIndex].bytes,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  color: Colors.grey[100],
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.insert_drive_file,
                                          color: Colors.blueGrey, size: 32),
                                      const SizedBox(height: 4),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4),
                                        child: Text(
                                          _newImages[relativeIndex].name,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.black87,
                                          ),
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ))
                          : (_isImage(_imageUrls[relativeIndex])
                              ? Image.network(
                                  _imageUrls[relativeIndex],
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: Colors.grey[200],
                                      child: const Center(
                                        child: Icon(Icons.broken_image,
                                            color: Colors.grey),
                                      ),
                                    );
                                  },
                                )
                              : Container(
                                  color: Colors.grey[100],
                                  child: const Center(
                                    child: Icon(Icons.insert_drive_file,
                                        color: Colors.blueGrey, size: 32),
                                  ),
                                )),
                    ),
                    // Delete button overlay
                    Positioned(
                      top: 4,
                      right: 4,
                      child: InkWell(
                        onTap: () => _removeImage(relativeIndex, isNew),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    // "New" badge for local images
                    if (isNew)
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .primaryColor
                                .withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'NUEVO',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildForm(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 1180;

        if (isWide) {
          // Two-column layout for wide screens (+ chat sidebar for existing jobs)
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // LEFT COLUMN - Work content with bike tabs embedded
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        // Job details with embedded bike tabs
                        _buildJobDetailsSectionCard(
                          theme,
                          icon: Icons.build_outlined,
                          title: 'Detalles del Trabajo',
                          child: _buildWorkbenchContent(theme),
                        ),
                        const SizedBox(height: 16),
                        _buildSectionCard(
                          theme,
                          icon: Icons.attach_file,
                          title: 'Adjuntos',
                          child: _buildAttachmentsSection(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                // RIGHT COLUMN - Customer and Summary (fixed width sidebar)
                SizedBox(
                  width: 360,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildSectionCard(
                          theme,
                          icon: Icons.person_outline,
                          title: 'Cliente',
                          child: _buildCustomerBikeSection(),
                        ),
                        const SizedBox(height: 16),
                        _buildSectionCard(
                          theme,
                          icon: Icons.calculate_outlined,
                          title: 'Resumen de Costos',
                          child: _buildCostSummary(),
                        ),
                        if (_existingJob?.invoiceId != null) ...[
                          const SizedBox(height: 16),
                          _buildSectionCard(
                            theme,
                            icon: Icons.receipt_outlined,
                            title: 'Factura Vinculada',
                            child: _buildInvoiceSection(),
                          ),
                        ],
                        // Service details panel (only when a service is selected)
                        if (_selectedServiceItem != null) ...[
                          const SizedBox(height: 16),
                          _buildSectionCard(
                            theme,
                            icon: Icons.build_circle_outlined,
                            title: 'Detalle de Servicio',
                            child: _buildServiceDetailsPanel(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // CHAT SIDEBAR - Only for existing jobs
                if (widget.jobId != null) ...[
                  const SizedBox(width: 8),
                  EntityChatSidebar(
                    entityType: 'job',
                    entityId: widget.jobId!,
                    entityTitle:
                        'Trabajo #${_existingJob?.jobNumber ?? widget.jobId!.substring(0, 6)}',
                  ),
                ],
              ],
            ),
          );
        } else {
          // Single-column layout for narrow screens
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildSectionCard(
                  theme,
                  icon: Icons.person_outline,
                  title: 'Cliente',
                  child: _buildCustomerBikeSection(),
                ),
                const SizedBox(height: 16),
                // Job details with embedded bike tabs (mobile)
                _buildJobDetailsSectionCard(
                  theme,
                  icon: Icons.build_outlined,
                  title: 'Detalles del Trabajo',
                  child: _buildWorkbenchContent(theme),
                ),
                const SizedBox(height: 16),
                _buildSectionCard(
                  theme,
                  icon: Icons.attach_file,
                  title: 'Adjuntos',
                  child: _buildAttachmentsSection(),
                ),
                const SizedBox(height: 16),
                _buildSectionCard(
                  theme,
                  icon: Icons.calculate_outlined,
                  title: 'Resumen de Costos',
                  child: _buildCostSummary(),
                ),
                if (_existingJob?.invoiceId != null) ...[
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    theme,
                    icon: Icons.receipt_outlined,
                    title: 'Factura Vinculada',
                    child: _buildInvoiceSection(),
                  ),
                ],
                // Service details panel (mobile)
                if (_selectedServiceItem != null) ...[
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    theme,
                    icon: Icons.build_circle_outlined,
                    title: 'Detalle de Servicio',
                    child: _buildServiceDetailsPanel(),
                  ),
                ],
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildSectionCard(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor:
                      theme.colorScheme.primary.withValues(alpha: 0.12),
                  child: Icon(icon, color: theme.colorScheme.primary, size: 18),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }

  /// Special section card with bike tabs embedded in header
  Widget _buildJobDetailsSectionCard(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    final hasBikeTabs = _selectedCustomer != null && _bikeTabs.isNotEmpty;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with icon, title, and bike tabs
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: LayoutBuilder(builder: (context, constraints) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor:
                            theme.colorScheme.primary.withValues(alpha: 0.12),
                        child: Icon(icon,
                            color: theme.colorScheme.primary, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  if (hasBikeTabs) ...[
                    const SizedBox(height: 12),
                    _buildInlineBikeTabs(theme),
                  ],
                ],
              );
            }),
          ),
          const SizedBox(height: 20),
          // Content
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: child,
          ),
        ],
      ),
    );
  }

  /// Full-width bike tab bar — sits below the card title, above content.
  Widget _buildInlineBikeTabs(ThemeData theme) {
    final primary = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurfaceVariant;
    final dividerColor =
        theme.colorScheme.outlineVariant.withValues(alpha: 0.5);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Thin divider above tab bar
        Divider(height: 1, thickness: 1, color: dividerColor),
        // Tab bar row
        Container(
          color: theme.colorScheme.surfaceContainerLowest,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ..._bikeTabs.asMap().entries.map((entry) {
                    final index = entry.key;
                    final tab = entry.value;
                    final isSelected = index == _selectedBikeTabIndex;

                    // Hide the General tab when it has no items
                    if (tab.isGeneralTab && tab.partItems.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    final label = tab.isGeneralTab
                        ? 'General'
                        : (tab.bike?.displayName ?? 'Bici ${index + 1}');
                    final icon = tab.isGeneralTab
                        ? Icons.shopping_bag_outlined
                        : Icons.pedal_bike_outlined;
                    final canClose = !tab.isGeneralTab &&
                        _bikeTabs.where((t) => !t.isGeneralTab).length > 1;

                    return _BikeTabButton(
                      label: label,
                      icon: icon,
                      isSelected: isSelected,
                      canClose: canClose,
                      onTap: () {
                        setState(() {
                          _selectedBikeTabIndex = index;
                          _selectedBike = _bikeTabs[index].bike;
                        });
                        unawaited(_loadSelectedBikeProfile(_selectedBike));
                      },
                      onClose: () => _confirmRemoveBike(index, label),
                      primaryColor: primary,
                      inactiveColor: onSurface,
                    );
                  }),
                  // Add bike button — vertically centered, subtle
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Tooltip(
                      message: 'Agregar bicicleta',
                      child: InkWell(
                        onTap: _showAddBikeSelector,
                        borderRadius: BorderRadius.circular(6),
                        hoverColor: primary.withValues(alpha: 0.08),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                          child: Icon(Icons.add, size: 16, color: primary),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Bottom divider
        Divider(height: 1, thickness: 1, color: dividerColor),
      ],
    );
  }

  // ============================================================
  // CONFIRMATION DIALOGS
  // ============================================================
  void _confirmRemoveBike(int index, String bikeName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover bicicleta'),
        content: Text(
            '¿Estás seguro de que deseas quitar la bicicleta "$bikeName" de este trabajo?\n\nSe perderán los datos ingresados en esta pestaña.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _removeBikeTab(index);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkbenchContent(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildWorkbenchTabs(theme),
        const SizedBox(height: 20),
        if (_selectedWorkbenchTab == _JobWorkbenchTab.general)
          _buildGeneralSection(theme)
        else if (_selectedWorkbenchTab == _JobWorkbenchTab.diagnosis)
          _buildDiagnosisSection(theme)
        else
          _buildPartsSection(),
      ],
    );
  }

  Widget _buildWorkbenchTabs(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildWorkbenchTabButton(
              theme: theme,
              tab: _JobWorkbenchTab.general,
              icon: Icons.tune_outlined,
              label: 'General',
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _buildWorkbenchTabButton(
              theme: theme,
              tab: _JobWorkbenchTab.diagnosis,
              icon: Icons.medical_information_outlined,
              label: 'Diagnóstico',
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _buildWorkbenchTabButton(
              theme: theme,
              tab: _JobWorkbenchTab.products,
              icon: Icons.shopping_basket_outlined,
              label: 'Productos y Servicios',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkbenchTabButton({
    required ThemeData theme,
    required _JobWorkbenchTab tab,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _selectedWorkbenchTab == tab;

    return Material(
      color: isSelected ? theme.colorScheme.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () {
          if (_selectedWorkbenchTab == tab) return;
          setState(() {
            _selectedWorkbenchTab = tab;
          });
        },
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _updateCurrentDiagnosisSheet(
    MechanicJobDiagnosisSheet Function(MechanicJobDiagnosisSheet current)
        transform, {
    bool refresh = true,
  }) {
    final currentTab = _currentBikeTab;
    if (currentTab == null || currentTab.isGeneralTab) return;

    void apply() {
      currentTab.diagnosisSheet = transform(currentTab.diagnosisSheet);
      currentTab.diagnosisSheetKey = currentTab.diagnosisSheet.templateKey;
      currentTab.diagnosisSheetUpdatedAt = DateTime.now();
    }

    if (refresh) {
      setState(apply);
    } else {
      apply();
    }
  }

  double? _parseNullableDouble(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }

  String? _normalizeNullableText(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  BikeMemoryLocation _resolveWizardLocation(
    BikeMemoryLocation currentLocation,
    Map<String, dynamic> answers,
  ) {
    if (currentLocation != BikeMemoryLocation.none) {
      return currentLocation;
    }

    switch (canonicalBrakeWheelValueFromAnswers(answers)) {
      case 'front':
        return BikeMemoryLocation.front;
      case 'rear':
        return BikeMemoryLocation.rear;
      default:
        return currentLocation;
    }
  }

  bool _isBrakeServiceFamily(String? family) {
    return family == 'brake' || family == 'brakes';
  }

  BikeProfile? _bikeProfileForCurrentTab() {
    final currentTab = _currentBikeTab;
    if (currentTab == null || currentTab.isGeneralTab) {
      return null;
    }

    return _selectedBike?.id == currentTab.bike?.id
        ? _selectedBikeProfile
        : null;
  }

  String? _firstMatchingWizardOption(
    ServiceProfileQuestion? question,
    List<String> candidates,
  ) {
    if (question == null) {
      return null;
    }

    final options = question.options.map((option) => option.value).toSet();
    for (final candidate in candidates) {
      if (options.contains(candidate)) {
        return candidate;
      }
    }

    return null;
  }

  String? _wizardLocationAnswer(
    ServiceProfileQuestion? question,
    BikeMemoryLocation location,
  ) {
    switch (location) {
      case BikeMemoryLocation.front:
        return _firstMatchingWizardOption(
            question, const ['front', 'delantero']);
      case BikeMemoryLocation.rear:
        return _firstMatchingWizardOption(question, const ['rear', 'trasero']);
      case BikeMemoryLocation.left:
        return _firstMatchingWizardOption(
            question, const ['left', 'izquierdo']);
      case BikeMemoryLocation.right:
        return _firstMatchingWizardOption(question, const ['right', 'derecho']);
      case BikeMemoryLocation.center:
        return _firstMatchingWizardOption(question, const ['center', 'centro']);
      case BikeMemoryLocation.none:
        return null;
    }
  }

  String? _mappedBrakeTypeWizardAnswer(
    String? rawBrakeType,
    String? rawRimBrakeFamily,
    ServiceProfileQuestion? question,
  ) {
    if (question == null || rawBrakeType == null || rawBrakeType.isEmpty) {
      return null;
    }

    switch (rawBrakeType) {
      case 'hydraulic_disc':
        return _firstMatchingWizardOption(question, const ['hidraulico']);
      case 'mechanical_disc':
        return _firstMatchingWizardOption(question, const ['mecanico']);
      case 'rim':
        final exactFamily = _mappedRimBrakeFamilyWizardAnswer(
          rawRimBrakeFamily,
          question,
        );
        if (exactFamily != null) {
          return exactFamily;
        }
        if (rawRimBrakeFamily == null ||
            rawRimBrakeFamily.isEmpty ||
            rawRimBrakeFamily == 'unknown') {
          final genericRim = _firstMatchingWizardOption(
            question,
            const ['llanta', 'rim'],
          );
          if (genericRim != null) {
            return genericRim;
          }
          return _firstMatchingWizardOption(question, const ['mecanico']);
        }
        return null;
      case 'roller_brake':
        return _firstMatchingWizardOption(question, const ['roller']);
      case 'drum_brake':
        return _firstMatchingWizardOption(question, const ['tambor', 'drum']);
      case 'coaster_brake':
        return _firstMatchingWizardOption(
          question,
          const ['contrapedal', 'coaster'],
        );
      case 'band_brake':
        return _firstMatchingWizardOption(question, const ['banda', 'band']);
      default:
        return null;
    }
  }

  String? _mappedMechanicalBrakeTypeWizardAnswer(
    String? rawBrakeType,
    String? rawRimBrakeFamily,
    ServiceProfileQuestion? question,
  ) {
    if (question == null || rawBrakeType == null || rawBrakeType.isEmpty) {
      return null;
    }

    switch (rawBrakeType) {
      case 'mechanical_disc':
        return _firstMatchingWizardOption(
          question,
          const ['disco_mec', 'mecanico'],
        );
      case 'rim':
        return _mappedRimBrakeFamilyWizardAnswer(
          rawRimBrakeFamily,
          question,
        );
      default:
        return null;
    }
  }

  String? _mappedRimBrakeFamilyWizardAnswer(
    String? rawRimBrakeFamily,
    ServiceProfileQuestion? question,
  ) {
    if (question == null ||
        rawRimBrakeFamily == null ||
        rawRimBrakeFamily.isEmpty) {
      return null;
    }

    final hints = switch (rawRimBrakeFamily) {
      'v_brake' => const ['v-brake', 'v brake', 'vbrake'],
      'cantilever' => const ['cantilever', 'canti'],
      'road_caliper_short_reach' => const [
          'short reach',
          'caliper corto',
          'caliper',
          'ruta'
        ],
      'road_caliper_long_reach' => const [
          'long reach',
          'caliper largo',
          'caliper',
          'ruta'
        ],
      'u_brake' => const ['u-brake', 'u brake', 'ubrake'],
      'rod_brake' => const ['varilla', 'rod brake'],
      _ => const <String>[],
    };

    if (hints.isEmpty) {
      return null;
    }

    return _firstMatchingWizardOption(question, hints);
  }

  bool _needsRimBrakeFamilyConfirmation(
    String? rawBrakeType,
    String? rawRimBrakeFamily,
  ) {
    return rawBrakeType == 'rim' &&
        (rawRimBrakeFamily == null ||
            rawRimBrakeFamily.isEmpty ||
            rawRimBrakeFamily == 'unknown');
  }

  String? _mappedRotorSizeWizardAnswer(
    ServiceProfileQuestion? question,
    Map<String, dynamic> technicalValues,
    BikeMemoryLocation location,
  ) {
    if (question == null) {
      return null;
    }

    final rawValue = switch (location) {
      BikeMemoryLocation.front => technicalValues['frontRotorSizeMm'],
      BikeMemoryLocation.rear => technicalValues['rearRotorSizeMm'],
      _ => null,
    };
    if (rawValue == null) {
      return null;
    }

    final normalized = rawValue.toString().trim();
    return _firstMatchingWizardOption(question, [normalized]);
  }

  List<String>? _mappedDerailleursWizardAnswer(
    String? drivetrainConfig,
    ServiceProfileQuestion? question,
  ) {
    if (question == null || question.questionType != 'multi_select') {
      return null;
    }

    final normalized = drivetrainConfig?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    final options = question.options.map((option) => option.value).toSet();
    if (!(options.contains('front') && options.contains('rear'))) {
      return null;
    }

    if (normalized.startsWith('2x') || normalized.startsWith('3x')) {
      return const ['front', 'rear'];
    }

    return null;
  }

  String? _buildDrivetrainProfileHint(Map<String, dynamic> technicalValues) {
    final config = _normalizeNullableText(
        technicalValues['drivetrainConfig']?.toString() ?? '');
    final speeds = _normalizeNullableText(
        technicalValues['drivetrainSpeeds']?.toString() ?? '');

    final parts = <String>[];
    if (config != null) {
      parts.add(config);
    }
    if (speeds != null) {
      parts.add('${speeds}v');
    }

    if (parts.isEmpty) {
      return null;
    }

    return parts.join(' · ');
  }

  List<BrakeDiagnosisSheet> _brakeDiagnosisSheetsForTargets(
    Set<BikeMemoryLocation> targets,
  ) {
    final currentTab = _currentBikeTab;
    if (currentTab == null || currentTab.isGeneralTab || targets.isEmpty) {
      return const [];
    }

    final diagnosisSheet = currentTab.diagnosisSheet;
    final sheets = <BrakeDiagnosisSheet>[];
    for (final target in targets) {
      switch (target) {
        case BikeMemoryLocation.front:
          sheets.add(diagnosisSheet.frontBrake);
          break;
        case BikeMemoryLocation.rear:
          sheets.add(diagnosisSheet.rearBrake);
          break;
        case BikeMemoryLocation.none:
        case BikeMemoryLocation.left:
        case BikeMemoryLocation.right:
        case BikeMemoryLocation.center:
          break;
      }
    }
    return sheets;
  }

  String? _sharedBrakeStringAnswer(
    List<BrakeDiagnosisSheet> sheets,
    String? Function(BrakeDiagnosisSheet sheet) mapAnswer,
  ) {
    if (sheets.isEmpty) {
      return null;
    }

    String? sharedAnswer;
    for (final sheet in sheets) {
      final answer = mapAnswer(sheet);
      if (answer == null || answer.isEmpty) {
        return null;
      }
      if (sharedAnswer == null) {
        sharedAnswer = answer;
        continue;
      }
      if (sharedAnswer != answer) {
        return null;
      }
    }

    return sharedAnswer;
  }

  bool? _sharedBrakeBoolAnswer(
    List<BrakeDiagnosisSheet> sheets,
    bool? Function(BrakeDiagnosisSheet sheet) mapAnswer,
  ) {
    if (sheets.isEmpty) {
      return null;
    }

    bool? sharedAnswer;
    for (final sheet in sheets) {
      final answer = mapAnswer(sheet);
      if (answer == null) {
        return null;
      }
      if (sharedAnswer == null) {
        sharedAnswer = answer;
        continue;
      }
      if (sharedAnswer != answer) {
        return null;
      }
    }

    return sharedAnswer;
  }

  List<String>? _sharedBrakeListAnswer(
    List<BrakeDiagnosisSheet> sheets,
    List<String>? Function(BrakeDiagnosisSheet sheet) mapAnswer,
  ) {
    if (sheets.isEmpty) {
      return null;
    }

    List<String>? sharedAnswer;
    for (final sheet in sheets) {
      final answer = mapAnswer(sheet);
      if (answer == null || answer.isEmpty) {
        return null;
      }
      if (sharedAnswer == null) {
        sharedAnswer = answer;
        continue;
      }
      if (!listEquals(sharedAnswer, answer)) {
        return null;
      }
    }

    return sharedAnswer;
  }

  int _brakeContaminationRank(String? status) {
    switch (status) {
      case 'ok':
        return 0;
      case 'dirty':
        return 1;
      case 'contaminated':
        return 2;
      case 'replace':
        return 3;
      default:
        return -1;
    }
  }

  String? _mappedPadConditionWizardAnswerFromDiagnosis(
    ServiceProfileQuestion question,
    BrakeDiagnosisSheet sheet,
  ) {
    final optionValues = question.options.map((option) => option.value).toSet();
    if (optionValues.contains('critical')) {
      if (sheet.padContaminationStatus == 'replace') {
        return 'critical';
      }
      final wear = sheet.padWearPercent;
      if (wear == null) {
        return null;
      }
      if (wear >= 75) {
        return 'critical';
      }
      if (wear >= 50) {
        return 'worn';
      }
      return 'ok';
    }

    if (optionValues.contains('contaminadas')) {
      final contamination = sheet.padContaminationStatus;
      if (contamination == 'dirty' ||
          contamination == 'contaminated' ||
          contamination == 'replace') {
        return 'contaminadas';
      }
      final wear = sheet.padWearPercent;
      if (wear == null) {
        return null;
      }
      if (wear >= 50) {
        return 'desgastadas';
      }
      return 'bien';
    }

    return null;
  }

  bool? _mappedPadContaminatedWizardAnswerFromDiagnosis(
    BrakeDiagnosisSheet sheet,
  ) {
    final contamination = sheet.padContaminationStatus;
    if (contamination == null || contamination.isEmpty) {
      return null;
    }

    return contamination != 'ok';
  }

  String? _mappedRotorConditionWizardAnswerFromDiagnosis(
    ServiceProfileQuestion question,
    BrakeDiagnosisSheet sheet,
  ) {
    final optionValues = question.options.map((option) => option.value).toSet();
    final thickness = sheet.rotorThicknessMm;
    final trueness = sheet.rotorTruenessStatus;
    final contamination = sheet.rotorContaminationStatus;

    if (optionValues.contains('warped')) {
      if (thickness != null && thickness <= 1.5) {
        return 'replace';
      }
      if (trueness == 'replace' || contamination == 'replace') {
        return 'replace';
      }
      if (trueness == 'misaligned' || trueness == 'attention') {
        return 'warped';
      }
      if (contamination == 'dirty' || contamination == 'contaminated') {
        return 'glazed';
      }
      if (trueness == 'ok' || contamination == 'ok' || thickness != null) {
        return 'ok';
      }
      return null;
    }

    if (optionValues.contains('torcido')) {
      if (thickness != null && thickness <= 1.7) {
        return 'desgastado';
      }
      if (trueness == 'replace') {
        return 'desgastado';
      }
      if (trueness == 'misaligned' || trueness == 'attention') {
        return 'torcido';
      }
      if (contamination == 'replace' ||
          contamination == 'dirty' ||
          contamination == 'contaminated') {
        return 'contaminado';
      }
      if (trueness == 'ok' || contamination == 'ok' || thickness != null) {
        return 'bien';
      }
    }

    return null;
  }

  String? _mappedRotorSeverityWizardAnswerFromDiagnosis(
    ServiceProfileQuestion question,
    BrakeDiagnosisSheet sheet,
  ) {
    final optionValues = question.options.map((option) => option.value).toSet();
    final thickness = sheet.rotorThicknessMm;
    final trueness = sheet.rotorTruenessStatus;

    String? normalizedSeverity;
    if (thickness != null && thickness <= 1.5 || trueness == 'replace') {
      normalizedSeverity = 'severe';
    } else if (trueness == 'misaligned' ||
        (thickness != null && thickness <= 1.7)) {
      normalizedSeverity = 'moderate';
    } else if (trueness == 'attention') {
      normalizedSeverity = 'minor';
    }

    if (normalizedSeverity == null) {
      return null;
    }

    switch (normalizedSeverity) {
      case 'minor':
        return optionValues.contains('minor')
            ? 'minor'
            : (optionValues.contains('leve') ? 'leve' : null);
      case 'moderate':
        return optionValues.contains('moderate')
            ? 'moderate'
            : (optionValues.contains('moderado') ? 'moderado' : null);
      case 'severe':
        return optionValues.contains('severe')
            ? 'severe'
            : (optionValues.contains('severo') ? 'severo' : null);
    }

    return null;
  }

  String? _mappedBrakeContaminationLevelWizardAnswerFromDiagnosis(
    ServiceProfileQuestion question,
    BrakeDiagnosisSheet sheet,
  ) {
    final optionValues = question.options.map((option) => option.value).toSet();
    final contaminationStatuses = <String>[
      if (sheet.padContaminationStatus != null) sheet.padContaminationStatus!,
      if (sheet.rotorContaminationStatus != null)
        sheet.rotorContaminationStatus!,
    ];
    if (contaminationStatuses.isEmpty) {
      return null;
    }

    contaminationStatuses.sort(
      (left, right) => _brakeContaminationRank(right)
          .compareTo(_brakeContaminationRank(left)),
    );

    final normalized = switch (contaminationStatuses.first) {
      'ok' => 'none',
      'dirty' => 'light',
      'contaminated' => 'moderate',
      'replace' => 'severe',
      _ => null,
    };
    if (normalized == null || !optionValues.contains(normalized)) {
      return null;
    }

    return normalized;
  }

  List<String>? _mappedBrakeSymptomsWizardAnswerFromDiagnosis(
    ServiceProfileQuestion question,
    BrakeDiagnosisSheet sheet,
  ) {
    final orderedValues = canonicalizeBrakeSymptomKeys(sheet.symptomKeys);
    return orderedValues.isEmpty ? null : orderedValues;
  }

  List<String>? _normalizeBrakeSymptomWizardAnswers(dynamic rawValue) {
    final values = (rawValue as List?)
        ?.map((value) => value.toString())
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);
    if (values == null || values.isEmpty) {
      return null;
    }

    final ordered = canonicalizeBrakeSymptomKeys(values);
    return ordered.isEmpty ? null : ordered;
  }

  dynamic _mappedBrakeDiagnosisWizardAnswer(
    ServiceProfileQuestion question,
    List<BrakeDiagnosisSheet> sheets,
  ) {
    switch (question.key) {
      case 'pad_condition':
        return _sharedBrakeStringAnswer(
          sheets,
          (sheet) => _mappedPadConditionWizardAnswerFromDiagnosis(
            question,
            sheet,
          ),
        );
      case 'pad_contaminated':
        return _sharedBrakeBoolAnswer(
          sheets,
          _mappedPadContaminatedWizardAnswerFromDiagnosis,
        );
      case 'rotor_condition':
        return _sharedBrakeStringAnswer(
          sheets,
          (sheet) => _mappedRotorConditionWizardAnswerFromDiagnosis(
            question,
            sheet,
          ),
        );
      case 'damage_level':
        return _sharedBrakeStringAnswer(
          sheets,
          (sheet) => _mappedRotorSeverityWizardAnswerFromDiagnosis(
            question,
            sheet,
          ),
        );
      case 'contamination_level':
        return _sharedBrakeStringAnswer(
          sheets,
          (sheet) => _mappedBrakeContaminationLevelWizardAnswerFromDiagnosis(
            question,
            sheet,
          ),
        );
      case 'symptom':
        return _sharedBrakeListAnswer(
          sheets,
          (sheet) =>
              _mappedBrakeSymptomsWizardAnswerFromDiagnosis(question, sheet),
        );
      default:
        return null;
    }
  }

  bool _areBrakeDiagnosisSheetsEquivalent(
    BrakeDiagnosisSheet left,
    BrakeDiagnosisSheet right,
  ) {
    return left.overallStatus == right.overallStatus &&
        left.padWearPercent == right.padWearPercent &&
        left.padContaminationStatus == right.padContaminationStatus &&
        left.rotorThicknessMm == right.rotorThicknessMm &&
        left.rotorTruenessStatus == right.rotorTruenessStatus &&
        left.rotorContaminationStatus == right.rotorContaminationStatus &&
        listEquals(left.symptomKeys, right.symptomKeys) &&
        left.notes == right.notes;
  }

  BikeSystemOverallStatus _derivedBrakeDiagnosisStatus(
    BrakeDiagnosisSheet sheet,
  ) {
    return _maxSystemStatus([
      _brakeComponentStatus(sheet, 'brake_pad'),
      _brakeComponentStatus(sheet, 'rotor'),
      if (sheet.symptomKeys.isNotEmpty) BikeSystemOverallStatus.attention,
    ]);
  }

  BrakeDiagnosisSheet _applyBrakeWizardAnswersToSheet({
    required BrakeDiagnosisSheet sheet,
    required Map<String, dynamic> answers,
    required Map<String, ServiceProfileQuestion> questionsByKey,
  }) {
    var nextSheet = sheet;

    final padCondition = answers['pad_condition']?.toString();
    if (padCondition != null && padCondition.isNotEmpty) {
      final optionValues = questionsByKey['pad_condition']
              ?.options
              .map((option) => option.value)
              .toSet() ??
          const <String>{};
      if (optionValues.contains('critical')) {
        switch (padCondition) {
          case 'ok':
            nextSheet = nextSheet.copyWith(padWearPercent: 25);
            break;
          case 'worn':
            nextSheet = nextSheet.copyWith(padWearPercent: 60);
            break;
          case 'critical':
            nextSheet = nextSheet.copyWith(padWearPercent: 90);
            break;
        }
      } else if (optionValues.contains('contaminadas')) {
        switch (padCondition) {
          case 'bien':
            nextSheet = nextSheet.copyWith(
              padContaminationStatus: 'ok',
              clearPadContaminationStatus: false,
            );
            break;
          case 'desgastadas':
            nextSheet = nextSheet.copyWith(padWearPercent: 60);
            break;
          case 'contaminadas':
            nextSheet = nextSheet.copyWith(
              padContaminationStatus: 'contaminated',
            );
            break;
        }
      }
    }

    final rawPadContaminated = answers['pad_contaminated'];
    if (rawPadContaminated is bool) {
      nextSheet = nextSheet.copyWith(
        padContaminationStatus: rawPadContaminated ? 'contaminated' : 'ok',
      );
    }

    final rotorCondition = answers['rotor_condition']?.toString();
    if (rotorCondition != null && rotorCondition.isNotEmpty) {
      final optionValues = questionsByKey['rotor_condition']
              ?.options
              .map((option) => option.value)
              .toSet() ??
          const <String>{};
      if (optionValues.contains('warped')) {
        switch (rotorCondition) {
          case 'ok':
            nextSheet = nextSheet.copyWith(
              rotorTruenessStatus: 'ok',
              rotorContaminationStatus: 'ok',
            );
            break;
          case 'glazed':
            nextSheet = nextSheet.copyWith(
              rotorContaminationStatus: 'dirty',
            );
            break;
          case 'warped':
            nextSheet = nextSheet.copyWith(rotorTruenessStatus: 'misaligned');
            break;
          case 'replace':
            nextSheet = nextSheet.copyWith(rotorTruenessStatus: 'replace');
            break;
        }
      } else if (optionValues.contains('torcido')) {
        switch (rotorCondition) {
          case 'bien':
            nextSheet = nextSheet.copyWith(
              rotorTruenessStatus: 'ok',
              rotorContaminationStatus: 'ok',
            );
            break;
          case 'torcido':
            nextSheet = nextSheet.copyWith(rotorTruenessStatus: 'misaligned');
            break;
          case 'contaminado':
            nextSheet = nextSheet.copyWith(
              rotorContaminationStatus: 'contaminated',
            );
            break;
          case 'desgastado':
            nextSheet = nextSheet.copyWith(rotorTruenessStatus: 'replace');
            break;
        }
      }
    }

    final damageLevel = answers['damage_level']?.toString();
    switch (damageLevel) {
      case 'minor':
        nextSheet = nextSheet.copyWith(rotorTruenessStatus: 'attention');
        break;
      case 'moderate':
        nextSheet = nextSheet.copyWith(rotorTruenessStatus: 'misaligned');
        break;
      case 'severe':
        nextSheet = nextSheet.copyWith(rotorTruenessStatus: 'replace');
        break;
    }

    final rawSymptoms = (answers['symptom'] as List?)
        ?.map((value) => value.toString())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (rawSymptoms != null) {
      if (rawSymptoms.contains('desalineado')) {
        nextSheet = nextSheet.copyWith(rotorTruenessStatus: 'misaligned');
      }

      final orderedSymptoms = canonicalizeBrakeSymptomKeys(rawSymptoms);
      nextSheet = nextSheet.copyWith(
        symptomKeys: orderedSymptoms,
        clearSymptomKeys: orderedSymptoms.isEmpty,
      );
    }

    return nextSheet;
  }

  _ServiceWizardDialogConfig _buildServiceWizardDialogConfig(
    ServiceWizardProfile? profile,
    _JobPartItem item,
  ) {
    final currentTab = _currentBikeTab;
    final technicalValues = _bikeProfileForCurrentTab()?.technicalValues ??
        const <String, dynamic>{};
    final questionsByKey = {
      for (final question in profile?.questions ?? <ServiceProfileQuestion>[])
        question.key: question,
    };
    final initialAnswers = ServiceWizardService.normalizeAnswersForProfile(
      profile,
      Map<String, dynamic>.from(
          item.wizardAnswers ?? const <String, dynamic>{}),
    );
    final hiddenQuestionKeys = <String>{};
    final questionOverrides = <String, ServiceWizardQuestionOverride>{};
    final diagnosisLinkedQuestionKeys = <String>{};
    ServiceWizardContextSummary? contextSummary;

    final wheelAnswer =
        _wizardLocationAnswer(questionsByKey['which_wheel'], item.location);
    if (wheelAnswer != null) {
      initialAnswers['which_wheel'] = wheelAnswer;
    }

    String? helperText;
    if (_isBrakeServiceFamily(profile?.serviceFamily)) {
      diagnosisLinkedQuestionKeys
          .addAll(kDiagnosisLinkedBrakeWizardQuestionKeys);
      if (item.location != BikeMemoryLocation.none) {
        hiddenQuestionKeys.add('which_wheel');
      }

      final rawBrakeType = technicalValues['brakeType']?.toString();
      final rawRimBrakeFamily = technicalValues['rimBrakeFamily']?.toString();
      final normalizedSymptomAnswers =
          _normalizeBrakeSymptomWizardAnswers(initialAnswers['symptom']);
      if (normalizedSymptomAnswers == null) {
        initialAnswers.remove('symptom');
      } else {
        initialAnswers['symptom'] = normalizedSymptomAnswers;
      }

      questionOverrides['symptom'] = ServiceWizardQuestionOverride(
        label: 'Síntomas observados',
        helperText:
            'Usa la misma lista del diagnóstico del freno para que ambos lados hablen el mismo idioma.',
        options: _kBrakeSymptomOptions,
      );

      final bikeLabel = currentTab?.displayName ?? 'Bicicleta';
      final bikeTypeLabel = currentTab?.bike?.bikeType?.displayName;
      final targetLabel = switch (item.location) {
        BikeMemoryLocation.front => 'Freno delantero',
        BikeMemoryLocation.rear => 'Freno trasero',
        _ => 'Servicio de freno',
      };
      final needsRimBrakeFamilyConfirmation =
          _needsRimBrakeFamilyConfirmation(rawBrakeType, rawRimBrakeFamily);
      contextSummary = ServiceWizardContextSummary(
        title: bikeLabel,
        subtitle: targetLabel,
        chips: [
          if (bikeTypeLabel != null && bikeTypeLabel.isNotEmpty)
            ServiceWizardContextChip(
              icon: Icons.directions_bike_outlined,
              label: 'Tipo de bici: $bikeTypeLabel',
            ),
          if (rawBrakeType != null && rawBrakeType.isNotEmpty)
            ServiceWizardContextChip(
              icon: Icons.tune_outlined,
              label: needsRimBrakeFamilyConfirmation
                  ? 'Freno confirmado: llanta · falta familia'
                  : 'Freno confirmado: ${_formatBrakeSystemDetail(rawBrakeType, rawRimBrakeFamily)}',
            ),
        ],
      );

      if (needsRimBrakeFamilyConfirmation) {
        final rimFamilyOptions = (questionsByKey['brake_type']?.options ??
                const <ServiceQuestionOption>[])
            .where(
                (option) => kRimBrakeFamilyOptionValues.contains(option.value))
            .toList(growable: false);
        questionOverrides['brake_type'] = ServiceWizardQuestionOverride(
          label: 'Familia de freno de llanta',
          helperText:
              'La plataforma ya viene confirmada desde la ficha de la bici. Aquí solo falta precisar la familia exacta.',
          lockedSelection: const ServiceWizardLockedSelection(
            label: 'Tipo de freno (desde la bicicleta)',
            valueLabel: 'Llanta (rim)',
          ),
          options: rimFamilyOptions,
        );
      }

      final mappedBrakeType = _mappedBrakeTypeWizardAnswer(
        rawBrakeType,
        rawRimBrakeFamily,
        questionsByKey['brake_type'],
      );
      if (mappedBrakeType != null) {
        initialAnswers['brake_type'] = mappedBrakeType;
        if (!needsRimBrakeFamilyConfirmation) {
          hiddenQuestionKeys.add('brake_type');
        }
      }

      final mappedMechanicalBrakeType = _mappedMechanicalBrakeTypeWizardAnswer(
        rawBrakeType,
        rawRimBrakeFamily,
        questionsByKey['brake_type_mech'],
      );
      if (mappedMechanicalBrakeType != null) {
        initialAnswers['brake_type_mech'] = mappedMechanicalBrakeType;
        hiddenQuestionKeys.add('brake_type_mech');
      }

      if (!_isDiscBrakeType(rawBrakeType)) {
        initialAnswers.remove('rotor_size');
        hiddenQuestionKeys.add('rotor_size');
      } else {
        final rotorSize = _mappedRotorSizeWizardAnswer(
          questionsByKey['rotor_size'],
          technicalValues,
          item.location,
        );
        if (rotorSize != null) {
          initialAnswers['rotor_size'] = rotorSize;
          hiddenQuestionKeys.add('rotor_size');
        }
      }

      final diagnosisTargets = _resolveBrakeDiagnosisTargets(
        item.location,
        initialAnswers,
      );
      final diagnosisSheets = _brakeDiagnosisSheetsForTargets(diagnosisTargets);
      if (diagnosisSheets.isNotEmpty) {
        for (final question
            in profile?.questions ?? <ServiceProfileQuestion>[]) {
          final diagnosisAnswer = _mappedBrakeDiagnosisWizardAnswer(
            question,
            diagnosisSheets,
          );
          if (diagnosisAnswer != null) {
            initialAnswers[question.key] = diagnosisAnswer;
          }
        }
      }

      if (item.location == BikeMemoryLocation.front) {
        helperText = 'Se actualizará la ficha del freno delantero.';
      } else if (item.location == BikeMemoryLocation.rear) {
        helperText = 'Se actualizará la ficha del freno trasero.';
      } else {
        helperText =
            'Para dejarlo ligado a una ficha concreta, usa “Aplica a” y marca Del. o Tras.';
      }

      if (rawBrakeType != null && !_isDiscBrakeType(rawBrakeType)) {
        if (needsRimBrakeFamilyConfirmation) {
          helperText =
              '$helperText La bici ya confirma plataforma llanta. Aquí solo falta precisar la familia exacta, y por eso no se muestran rotores.';
        } else {
          final brakeDetail = _formatBrakeSystemDetail(
            rawBrakeType,
            rawRimBrakeFamily,
          );
          helperText =
              '$helperText La bici ya confirma freno $brakeDetail, así que el wizard no repite tipo ni rotores.';
        }
      } else if (rawBrakeType != null && rawBrakeType.isNotEmpty) {
        helperText =
            '$helperText La bici ya confirma freno ${_formatBrakeType(rawBrakeType)}.';
      }

      helperText =
          '$helperText Los campos marcados como “Diagnóstico” comparten la misma base que ves en la ficha del freno.';
    } else if (profile?.serviceFamily == 'drivetrain') {
      final derailleurs = _mappedDerailleursWizardAnswer(
        technicalValues['drivetrainConfig']?.toString(),
        questionsByKey['derailleurs'],
      );
      if (derailleurs != null) {
        initialAnswers['derailleurs'] = derailleurs;
        hiddenQuestionKeys.add('derailleurs');
      }

      final drivetrainHint = _buildDrivetrainProfileHint(technicalValues);
      helperText = drivetrainHint == null
          ? 'Esta configuración puede actualizar la ficha técnica de transmisión de esta bicicleta.'
          : 'Esta configuración puede actualizar la ficha técnica de transmisión de esta bicicleta. El perfil upstream ya marca $drivetrainHint.';
    }

    return _ServiceWizardDialogConfig(
      initialAnswers: initialAnswers,
      hiddenQuestionKeys: hiddenQuestionKeys,
      helperText: helperText,
      contextSummary: contextSummary,
      questionOverrides: questionOverrides,
      diagnosisLinkedQuestionKeys: diagnosisLinkedQuestionKeys,
    );
  }

  String? _serviceWizardSyncFeedback(
    ServiceWizardProfile? profile,
    _JobPartItem item,
    Map<String, dynamic> answers,
  ) {
    if (_isBrakeServiceFamily(profile?.serviceFamily)) {
      final targets = _resolveBrakeDiagnosisTargets(item.location, answers);
      if (targets.isEmpty) {
        return 'Servicio guardado. Para ligarlo a la ficha técnica, define Del./Tras. en “Aplica a”.';
      }
      if (targets.length == 2) {
        return 'Servicio vinculado a la ficha técnica de freno delantero y trasero.';
      }
      if (targets.contains(BikeMemoryLocation.front)) {
        return 'Servicio vinculado a la ficha técnica del freno delantero.';
      }
      if (targets.contains(BikeMemoryLocation.rear)) {
        return 'Servicio vinculado a la ficha técnica del freno trasero.';
      }
    }

    if (profile?.serviceFamily == 'drivetrain') {
      return 'Servicio vinculado a la ficha técnica de transmisión.';
    }

    return null;
  }

  String? _buildPersistedWizardSummary(
    ServiceWizardProfile? profile,
    Map<String, dynamic> answers,
    String fallbackSummary, {
    Set<String> hiddenQuestionKeys = const <String>{},
  }) {
    final normalizedAnswers =
        ServiceWizardService.normalizeAnswersForProfile(profile, answers);
    if (normalizedAnswers.isEmpty) {
      return null;
    }

    if (profile == null) {
      return _normalizeNullableText(fallbackSummary);
    }

    final filteredAnswers = Map<String, dynamic>.from(normalizedAnswers)
      ..remove('which_wheel')
      ..removeWhere((key, _) => hiddenQuestionKeys.contains(key));
    final filteredQuestions = profile.questions
        .where(
          (question) =>
              question.key != 'which_wheel' &&
              !hiddenQuestionKeys.contains(question.key),
        )
        .toList();

    String summary = ServiceWizardService.buildSummary(
      filteredAnswers,
      filteredQuestions,
    );

    final extraNotes =
        _normalizeNullableText(answers['_notes']?.toString() ?? '');
    if (extraNotes != null) {
      summary = summary.isEmpty ? extraNotes : '$summary\n$extraNotes';
    }

    return _normalizeNullableText(summary);
  }

  BikeSystemOverallStatus _mergeDerivedDiagnosisStatus(
    BikeSystemOverallStatus current,
    BikeSystemOverallStatus derived,
  ) {
    if (derived == BikeSystemOverallStatus.unknown) {
      return current;
    }
    if (current == BikeSystemOverallStatus.unknown) {
      return derived;
    }
    return _diagnosisStatusRank(derived) > _diagnosisStatusRank(current)
        ? derived
        : current;
  }

  int _diagnosisStatusRank(BikeSystemOverallStatus status) {
    switch (status) {
      case BikeSystemOverallStatus.unknown:
        return 0;
      case BikeSystemOverallStatus.ok:
        return 1;
      case BikeSystemOverallStatus.attention:
        return 2;
      case BikeSystemOverallStatus.critical:
        return 3;
    }
  }

  String? _upsertGuidedDiagnosisNote(
    String? existingNotes, {
    required String marker,
    required String? content,
  }) {
    final retainedLines = <String>[];
    for (final rawLine in (existingNotes ?? '').split('\n')) {
      final line = rawLine.trimRight();
      if (line.trim().isEmpty) continue;
      if (line.startsWith(marker)) continue;
      retainedLines.add(line);
    }

    final normalizedContent = _normalizeNullableText(content ?? '');
    if (normalizedContent != null) {
      retainedLines.add('$marker $normalizedContent');
    }

    if (retainedLines.isEmpty) {
      return null;
    }

    return retainedLines.join('\n');
  }

  bool _hasGuidedDiagnosisNote(String? notes, String marker) {
    return (notes ?? '').split('\n').any((line) => line.startsWith(marker));
  }

  void _applyWizardAnswersToDiagnosis({
    required _JobPartItem item,
    required ServiceWizardProfile? profile,
    required Map<String, dynamic> answers,
  }) {
    if (profile == null) {
      return;
    }

    switch (profile.serviceFamily) {
      case 'brake':
      case 'brakes':
        _applyBrakeWizardAnswersToDiagnosis(
          item: item,
          profile: profile,
          answers: answers,
        );
        return;
      case 'drivetrain':
        _applyDrivetrainWizardAnswersToDiagnosis(
          profile: profile,
          answers: answers,
        );
        return;
      default:
        return;
    }
  }

  void _applyBrakeWizardAnswersToDiagnosis({
    required _JobPartItem item,
    required ServiceWizardProfile profile,
    required Map<String, dynamic> answers,
  }) {
    final normalizedAnswers =
        ServiceWizardService.normalizeAnswersForProfile(profile, answers);
    final currentTab = _currentBikeTab;
    if (currentTab == null || currentTab.isGeneralTab) {
      return;
    }

    final targets =
        _resolveBrakeDiagnosisTargets(item.location, normalizedAnswers);
    if (targets.isEmpty) {
      return;
    }

    final questionsByKey = {
      for (final question in profile.questions) question.key: question,
    };
    final noteParts = <String>[];
    var derivedStatus = BikeSystemOverallStatus.unknown;

    const diagnosisSyncedKeys = <String>{
      'pad_condition',
      'pad_contaminated',
      'rotor_condition',
      'damage_level',
      'symptom',
    };

    void addSelectAnswer(
      String key,
      Map<String, BikeSystemOverallStatus> statusMap,
    ) {
      final rawValue = normalizedAnswers[key]?.toString();
      if (rawValue == null || rawValue.isEmpty) {
        return;
      }

      final question = questionsByKey[key];
      final resolvedLabel = question != null
          ? ServiceWizardService.resolveLabel(question, rawValue)
          : rawValue;
      noteParts.add('${question?.label ?? key}: $resolvedLabel');

      final candidateStatus =
          statusMap[rawValue] ?? BikeSystemOverallStatus.unknown;
      if (_diagnosisStatusRank(candidateStatus) >
          _diagnosisStatusRank(derivedStatus)) {
        derivedStatus = candidateStatus;
      }
    }

    void addMultiSelectAnswer(
      String key,
      BikeSystemOverallStatus derivedFromAnySelection,
    ) {
      final rawValues = (normalizedAnswers[key] as List?)
          ?.map((value) => value.toString())
          .toList();
      if (rawValues == null || rawValues.isEmpty) {
        return;
      }

      final question = questionsByKey[key];
      final resolvedLabels = rawValues.map((rawValue) {
        return question != null
            ? ServiceWizardService.resolveLabel(question, rawValue)
            : rawValue;
      }).join(', ');
      noteParts.add('${question?.label ?? key}: $resolvedLabels');

      if (_diagnosisStatusRank(derivedFromAnySelection) >
          _diagnosisStatusRank(derivedStatus)) {
        derivedStatus = derivedFromAnySelection;
      }
    }

    void addExecutionOnlyNotePart(ServiceProfileQuestion question) {
      if (diagnosisSyncedKeys.contains(question.key)) {
        return;
      }

      final rawValue = normalizedAnswers[question.key];
      if (rawValue == null) {
        return;
      }

      if (rawValue is bool) {
        noteParts.add('${question.label}: ${rawValue ? 'Sí' : 'No'}');
        return;
      }

      if (rawValue is List) {
        final values = rawValue
            .map((value) => value.toString())
            .where((value) => value.trim().isNotEmpty)
            .toList(growable: false);
        if (values.isEmpty) {
          return;
        }
        final resolvedLabels = values
            .map((raw) => ServiceWizardService.resolveLabel(question, raw))
            .join(', ');
        noteParts.add('${question.label}: $resolvedLabels');
        return;
      }

      final normalized = _normalizeNullableText(rawValue.toString());
      if (normalized == null) {
        return;
      }

      noteParts.add(
        '${question.label}: ${ServiceWizardService.resolveLabel(question, normalized)}',
      );
    }

    addSelectAnswer('pad_condition', {
      'ok': BikeSystemOverallStatus.ok,
      'bien': BikeSystemOverallStatus.ok,
      'worn': BikeSystemOverallStatus.attention,
      'desgastadas': BikeSystemOverallStatus.attention,
      'contaminadas': BikeSystemOverallStatus.attention,
      'critical': BikeSystemOverallStatus.critical,
      'replace': BikeSystemOverallStatus.critical,
    });
    addSelectAnswer('rotor_condition', {
      'ok': BikeSystemOverallStatus.ok,
      'bien': BikeSystemOverallStatus.ok,
      'glazed': BikeSystemOverallStatus.attention,
      'contaminado': BikeSystemOverallStatus.attention,
      'desgastado': BikeSystemOverallStatus.critical,
      'torcido': BikeSystemOverallStatus.critical,
      'warped': BikeSystemOverallStatus.critical,
      'replace': BikeSystemOverallStatus.critical,
    });
    addSelectAnswer('contamination_level', {
      'none': BikeSystemOverallStatus.ok,
      'light': BikeSystemOverallStatus.attention,
      'moderate': BikeSystemOverallStatus.attention,
      'severe': BikeSystemOverallStatus.critical,
    });
    final padContaminated = answers['pad_contaminated'];
    if (padContaminated is bool) {
      final candidateStatus = padContaminated
          ? BikeSystemOverallStatus.attention
          : BikeSystemOverallStatus.ok;
      if (_diagnosisStatusRank(candidateStatus) >
          _diagnosisStatusRank(derivedStatus)) {
        derivedStatus = candidateStatus;
      }
    }
    addSelectAnswer('damage_level', {
      'minor': BikeSystemOverallStatus.attention,
      'moderate': BikeSystemOverallStatus.attention,
      'severe': BikeSystemOverallStatus.critical,
    });
    addMultiSelectAnswer('symptom', BikeSystemOverallStatus.attention);

    for (final question in profile.questions) {
      addExecutionOnlyNotePart(question);
    }

    final freeNotes =
        _normalizeNullableText(normalizedAnswers['_notes']?.toString() ?? '');
    if (freeNotes != null) {
      noteParts.add('Observación: $freeNotes');
    }

    final marker = '[Servicio guiado: ${profile.name}]';
    final noteContent = noteParts.isEmpty ? null : noteParts.join(' · ');
    final updatedSheetsByTarget = <BikeMemoryLocation, BrakeDiagnosisSheet>{
      for (final target in targets)
        target: _applyBrakeWizardAnswersToSheet(
          sheet: target == BikeMemoryLocation.front
              ? currentTab.diagnosisSheet.frontBrake
              : currentTab.diagnosisSheet.rearBrake,
          answers: normalizedAnswers,
          questionsByKey: questionsByKey,
        ),
    };
    final hasSemanticChanges = updatedSheetsByTarget.entries.any((entry) {
      final currentSheet = entry.key == BikeMemoryLocation.front
          ? currentTab.diagnosisSheet.frontBrake
          : currentTab.diagnosisSheet.rearBrake;
      return !_areBrakeDiagnosisSheetsEquivalent(currentSheet, entry.value);
    });

    if (derivedStatus == BikeSystemOverallStatus.unknown &&
        noteContent == null &&
        !hasSemanticChanges) {
      final hasExistingGuidedNote = targets.any((target) {
        final notes = target == BikeMemoryLocation.front
            ? currentTab.diagnosisSheet.frontBrake.notes
            : currentTab.diagnosisSheet.rearBrake.notes;
        return _hasGuidedDiagnosisNote(notes, marker);
      });
      if (!hasExistingGuidedNote) {
        return;
      }
    }

    BrakeDiagnosisSheet applyToSheet(
        BikeMemoryLocation target, BrakeDiagnosisSheet sheet) {
      final nextSheet = updatedSheetsByTarget[target] ?? sheet;
      final mergedNotes = _upsertGuidedDiagnosisNote(
        nextSheet.notes,
        marker: marker,
        content: noteContent,
      );
      return nextSheet.copyWith(
        overallStatus: _mergeDerivedDiagnosisStatus(
          nextSheet.overallStatus,
          _maxSystemStatus([
            derivedStatus,
            _derivedBrakeDiagnosisStatus(nextSheet),
          ]),
        ),
        notes: mergedNotes,
        clearNotes: mergedNotes == null,
      );
    }

    _updateCurrentDiagnosisSheet(
      (current) => current.copyWith(
        frontBrake: targets.contains(BikeMemoryLocation.front)
            ? applyToSheet(BikeMemoryLocation.front, current.frontBrake)
            : current.frontBrake,
        rearBrake: targets.contains(BikeMemoryLocation.rear)
            ? applyToSheet(BikeMemoryLocation.rear, current.rearBrake)
            : current.rearBrake,
      ),
    );
  }

  Set<BikeMemoryLocation> _resolveBrakeDiagnosisTargets(
    BikeMemoryLocation location,
    Map<String, dynamic> answers,
  ) {
    if (location == BikeMemoryLocation.front) {
      return {BikeMemoryLocation.front};
    }
    if (location == BikeMemoryLocation.rear) {
      return {BikeMemoryLocation.rear};
    }

    switch (canonicalBrakeWheelValueFromAnswers(answers)) {
      case 'front':
        return {BikeMemoryLocation.front};
      case 'rear':
        return {BikeMemoryLocation.rear};
      case 'both':
        return {BikeMemoryLocation.front, BikeMemoryLocation.rear};
      default:
        return {};
    }
  }

  void _applyDrivetrainWizardAnswersToDiagnosis({
    required ServiceWizardProfile profile,
    required Map<String, dynamic> answers,
  }) {
    final currentTab = _currentBikeTab;
    if (currentTab == null || currentTab.isGeneralTab) {
      return;
    }

    final questionsByKey = {
      for (final question in profile.questions) question.key: question,
    };
    final noteParts = <String>[];
    var derivedStatus = BikeSystemOverallStatus.unknown;

    void addSelectAnswer(
      String key,
      Map<String, BikeSystemOverallStatus> statusMap,
    ) {
      final rawValue = answers[key]?.toString();
      if (rawValue == null || rawValue.isEmpty) {
        return;
      }

      final question = questionsByKey[key];
      final resolvedLabel = question != null
          ? ServiceWizardService.resolveLabel(question, rawValue)
          : rawValue;
      noteParts.add('${question?.label ?? key}: $resolvedLabel');

      final candidateStatus =
          statusMap[rawValue] ?? BikeSystemOverallStatus.unknown;
      if (_diagnosisStatusRank(candidateStatus) >
          _diagnosisStatusRank(derivedStatus)) {
        derivedStatus = candidateStatus;
      }
    }

    addSelectAnswer('chain_wear', {
      'ok': BikeSystemOverallStatus.ok,
      'worn': BikeSystemOverallStatus.attention,
      'replace': BikeSystemOverallStatus.critical,
    });
    addSelectAnswer('cable_condition', {
      'ok': BikeSystemOverallStatus.ok,
      'frayed': BikeSystemOverallStatus.attention,
      'replace': BikeSystemOverallStatus.ok,
    });

    final freeNotes =
        _normalizeNullableText(answers['_notes']?.toString() ?? '');
    if (freeNotes != null) {
      noteParts.add('Observación: $freeNotes');
    }

    final marker = '[Servicio guiado: ${profile.name}]';
    final noteContent = noteParts.isEmpty ? null : noteParts.join(' · ');
    if (derivedStatus == BikeSystemOverallStatus.unknown &&
        noteContent == null &&
        !_hasGuidedDiagnosisNote(
            currentTab.diagnosisSheet.drivetrain.notes, marker)) {
      return;
    }

    _updateCurrentDiagnosisSheet(
      (current) {
        final mergedNotes = _upsertGuidedDiagnosisNote(
          current.drivetrain.notes,
          marker: marker,
          content: noteContent,
        );
        return current.copyWith(
          drivetrain: current.drivetrain.copyWith(
            overallStatus: _mergeDerivedDiagnosisStatus(
              current.drivetrain.overallStatus,
              derivedStatus,
            ),
            notes: mergedNotes,
            clearNotes: mergedNotes == null,
          ),
        );
      },
    );
  }

  void _insertDiagnosisSnippet(
      TextEditingController controller, String snippet) {
    final value = controller.value;
    final selection = value.selection;
    final text = value.text;
    final start = selection.isValid && selection.start >= 0
        ? selection.start
        : text.length;
    final end =
        selection.isValid && selection.end >= 0 ? selection.end : text.length;
    final selectedText = text.substring(start, end);
    final replacement =
        selectedText.isEmpty ? snippet : '$selectedText$snippet';
    final nextText = text.replaceRange(start, end, replacement);
    final cursor = start + replacement.length;

    controller.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: cursor),
      composing: TextRange.empty,
    );

    if (mounted) {
      setState(() {});
    }
  }

  bool _isGeneratingNarrativeDraftFor(_BikeTabData currentTab) =>
      _generatingNarrativeDraftTabId == currentTab.tabId;

  Future<void> _handleGenerateNarrativeDraft(_BikeTabData currentTab) async {
    final source = _buildDiagnosisNarrativeSource(currentTab);
    if (!source.hasContent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Primero completa hallazgos en el modelo estructurado para redactar un borrador.',
          ),
        ),
      );
      return;
    }

    final insertMode = await _resolveNarrativeDraftInsertMode(
      currentTab.diagnosisController.text,
    );
    if (insertMode == null || !mounted) {
      return;
    }

    setState(() {
      _generatingNarrativeDraftTabId = currentTab.tabId;
    });

    var usedFallback = false;

    try {
      final prompt = _buildDiagnosisNarrativePrompt(currentTab, source);
      String draft;

      try {
        _aiAssistantService.initialize();
        draft = _sanitizeGeneratedNarrativeDraft(
          await _aiAssistantService.generateOneShotText(prompt),
        );
        if (draft.trim().isEmpty) {
          throw StateError('Empty narrative draft');
        }
      } catch (_) {
        usedFallback = true;
        draft = _buildDiagnosisNarrativeFallback(currentTab, source);
      }

      if (!mounted) {
        return;
      }

      final controller = currentTab.diagnosisController;
      final nextText = _mergeNarrativeDraft(
        controller.text,
        draft,
        insertMode,
      );

      setState(() {
        controller.text = nextText;
        controller.selection = TextSelection.collapsed(
          offset: controller.text.length,
        );
        _generatingNarrativeDraftTabId = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            usedFallback
                ? 'Se generó un borrador local desde el modelo estructurado.'
                : 'Borrador generado desde el modelo estructurado.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _generatingNarrativeDraftTabId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar el borrador: $e')),
      );
    }
  }

  Future<_NarrativeDraftInsertMode?> _resolveNarrativeDraftInsertMode(
    String existingText,
  ) async {
    if (existingText.trim().isEmpty) {
      return _NarrativeDraftInsertMode.replace;
    }

    return showDialog<_NarrativeDraftInsertMode>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('La ficha narrativa ya tiene texto'),
          content: const Text(
            '¿Quieres reemplazar el texto actual o agregar el nuevo borrador al final?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                _NarrativeDraftInsertMode.append,
              ),
              child: const Text('Agregar abajo'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                _NarrativeDraftInsertMode.replace,
              ),
              child: const Text('Reemplazar'),
            ),
          ],
        );
      },
    );
  }

  _DiagnosisNarrativeSource _buildDiagnosisNarrativeSource(
    _BikeTabData currentTab,
  ) {
    final sections = <_DiagnosisNarrativeSection>[];
    final recommendations = <String>{};
    var hasCriticalRisk = false;
    final sheet = currentTab.diagnosisSheet;

    final drivetrainNarrative =
        _buildDrivetrainNarrativeFromSheet(sheet.drivetrain);
    if (drivetrainNarrative != null) {
      sections.add(
        _DiagnosisNarrativeSection(
          title: 'Transmisión',
          body: drivetrainNarrative,
        ),
      );
      recommendations.addAll(
        _buildDrivetrainRecommendationHints(sheet.drivetrain),
      );
      hasCriticalRisk =
          hasCriticalRisk || _drivetrainHasCriticalRisk(sheet.drivetrain);
    }

    final frontBrakeNarrative =
        _buildBrakeNarrativeFromSheet('freno delantero', sheet.frontBrake);
    if (frontBrakeNarrative != null) {
      sections.add(
        _DiagnosisNarrativeSection(
          title: 'Freno delantero',
          body: frontBrakeNarrative,
        ),
      );
      recommendations.addAll(
        _buildBrakeRecommendationHints('freno delantero', sheet.frontBrake),
      );
      hasCriticalRisk =
          hasCriticalRisk || _brakeHasCriticalRisk(sheet.frontBrake);
    }

    final rearBrakeNarrative =
        _buildBrakeNarrativeFromSheet('freno trasero', sheet.rearBrake);
    if (rearBrakeNarrative != null) {
      sections.add(
        _DiagnosisNarrativeSection(
          title: 'Freno trasero',
          body: rearBrakeNarrative,
        ),
      );
      recommendations.addAll(
        _buildBrakeRecommendationHints('freno trasero', sheet.rearBrake),
      );
      hasCriticalRisk =
          hasCriticalRisk || _brakeHasCriticalRisk(sheet.rearBrake);
    }

    return _DiagnosisNarrativeSource(
      sections: sections,
      recommendationHints: recommendations.toList(growable: false),
      hasCriticalRisk: hasCriticalRisk,
    );
  }

  String _buildDiagnosisNarrativePrompt(
    _BikeTabData currentTab,
    _DiagnosisNarrativeSource source,
  ) {
    final bikeName = currentTab.bike?.displayName ?? 'Bicicleta del cliente';
    final bikeType = currentTab.bike?.bikeType?.displayName;
    final clientRequest = _normalizeNullableText(
      currentTab.clientRequestController.text,
    );

    final buffer = StringBuffer()
      ..writeln(
        'Redacta un informe de diagnóstico de bicicleta en español claro, humano y profesional para compartir con el cliente.',
      )
      ..writeln('Reglas obligatorias:')
      ..writeln('- Usa solo la información entregada.')
      ..writeln(
          '- No inventes causas, piezas, medidas ni recomendaciones no respaldadas.')
      ..writeln(
        '- No menciones campos faltantes ni expresiones como "sin definir", "desconocido" o "no aplica".',
      )
      ..writeln('- No uses claves técnicas internas ni labels de formulario.')
      ..writeln(
          '- Organiza la respuesta con secciones breves usando markdown simple en formato "### Título".')
      ..writeln(
          '- Usa una sección por componente relevante, por ejemplo "### Freno delantero" o "### Transmisión".')
      ..writeln(
          '- No uses viñetas ni listas; debajo de cada título debe ir un párrafo corto.')
      ..writeln(
          '- Si corresponde, cierra con una sección como "### Recomendación" o "### Siguiente paso".')
      ..writeln('- Entrega como máximo 5 secciones cortas.')
      ..writeln(
          '- Usa un tono sobrio, cercano y profesional, como un taller serio hablando con su cliente.')
      ..writeln('- No seas melodramático, alarmista ni grandilocuente.')
      ..writeln('- No suenes robótico ni enumeres campos uno por uno.')
      ..writeln(
          '- Convierte porcentajes o mediciones técnicas en lenguaje natural cuando sea posible.')
      ..writeln(
          '- Ejemplo: en vez de "desgaste de pastillas de 55%", prefiere "las pastillas muestran desgaste avanzado".')
      ..writeln(
          '- Si hay criticidad o urgencia, exprésala de forma natural y proporcionada.')
      ..writeln()
      ..writeln('Contexto de la visita:')
      ..writeln('- Bicicleta: $bikeName');

    if (bikeType != null && bikeType.trim().isNotEmpty) {
      buffer.writeln('- Tipo: $bikeType');
    }
    if (clientRequest != null) {
      buffer.writeln('- Solicitud del cliente: $clientRequest');
    }
    if (source.hasCriticalRisk) {
      buffer.writeln('- Prioridad percibida: alta');
    }

    buffer
      ..writeln()
      ..writeln('Hallazgos estructurados ya depurados por sección:');

    for (final section in source.sections) {
      buffer.writeln('- ${section.title}: ${section.body}');
    }

    if (source.recommendationHints.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(
            'Recomendaciones sugeridas si corresponden con los hallazgos:');
      for (final recommendation in source.recommendationHints) {
        buffer.writeln('- $recommendation');
      }
    }

    return buffer.toString();
  }

  String _buildDiagnosisNarrativeFallback(
    _BikeTabData currentTab,
    _DiagnosisNarrativeSource source,
  ) {
    final clientRequest = _normalizeNullableText(
      currentTab.clientRequestController.text,
    );
    final sections = <String>[];

    if (clientRequest != null) {
      sections.add(
        _formatNarrativeMarkdownSection(
          'Motivo del ingreso',
          'La revisión se realizó teniendo en cuenta lo que comentó el cliente sobre $clientRequest.',
        ),
      );
    }

    for (final section in source.sections) {
      sections
          .add(_formatNarrativeMarkdownSection(section.title, section.body));
    }

    if (source.recommendationHints.isNotEmpty) {
      sections.add(
        _formatNarrativeMarkdownSection(
          source.hasCriticalRisk
              ? 'Siguiente paso prioritario'
              : 'Recomendación',
          'Con este diagnóstico, lo más razonable es ${_joinNaturalList(source.recommendationHints)}.',
        ),
      );
    }

    return sections.join('\n\n').trim();
  }

  String _formatNarrativeMarkdownSection(String title, String body) {
    return '### $title\n$body';
  }

  String _mergeNarrativeDraft(
    String existingText,
    String draft,
    _NarrativeDraftInsertMode mode,
  ) {
    final cleanedDraft = draft.trim();
    if (existingText.trim().isEmpty ||
        mode == _NarrativeDraftInsertMode.replace) {
      return cleanedDraft;
    }
    return '${existingText.trimRight()}\n\n$cleanedDraft';
  }

  String _sanitizeGeneratedNarrativeDraft(String rawText) {
    var cleaned = rawText.trim();
    cleaned = cleaned.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
    cleaned = cleaned.replaceFirst(RegExp(r'\s*```$'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return cleaned.trim();
  }

  String? _buildDrivetrainNarrativeFromSheet(DrivetrainDiagnosisSheet sheet) {
    if (!sheet.hasMeaningfulData) {
      return null;
    }

    final sentences = <String>[];

    switch (sheet.overallStatus) {
      case BikeSystemOverallStatus.ok:
        sentences.add('La transmisión se encuentra en buen estado general.');
        break;
      case BikeSystemOverallStatus.attention:
        sentences.add('La transmisión presenta detalles que conviene revisar.');
        break;
      case BikeSystemOverallStatus.critical:
        sentences.add(
            'La transmisión muestra un desgaste o una condición que ya merece atención prioritaria.');
        break;
      case BikeSystemOverallStatus.unknown:
        break;
    }

    if (sheet.chainWearPercent != null) {
      final chainWear = _describeChainWearSentence(sheet.chainWearPercent);
      if (chainWear != null) {
        sentences.add(chainWear);
      }
    }

    final chainLube = _describeChainLubricationSentence(
      sheet.chainLubricationStatus,
    );
    if (chainLube != null) {
      sentences.add(chainLube);
    }

    final cassette = _describeDrivetrainComponentSentence(
      'El cassette',
      sheet.cassetteCondition,
    );
    if (cassette != null) {
      sentences.add(cassette);
    }

    final chainring = _describeDrivetrainComponentSentence(
      'El plato',
      sheet.chainringCondition,
    );
    if (chainring != null) {
      sentences.add(chainring);
    }

    final rearDerailleur = _describeDrivetrainComponentSentence(
      'El cambio trasero',
      sheet.rearDerailleurCondition,
    );
    if (rearDerailleur != null) {
      sentences.add(rearDerailleur);
    }

    final frontDerailleur = _describeDrivetrainComponentSentence(
      'El cambio delantero',
      sheet.frontDerailleurCondition,
    );
    if (frontDerailleur != null) {
      sentences.add(frontDerailleur);
    }

    final shifter = _describeDrivetrainComponentSentence(
      'El shifter',
      sheet.shifterCondition,
    );
    if (shifter != null) {
      sentences.add(shifter);
    }

    final notes = _normalizeNullableText(sheet.notes ?? '');
    if (notes != null) {
      sentences.add('Además, en la inspección se consignó: $notes');
    }

    return sentences.isEmpty ? null : sentences.join(' ');
  }

  String? _buildBrakeNarrativeFromSheet(
    String brakeLabel,
    BrakeDiagnosisSheet sheet,
  ) {
    if (!sheet.hasMeaningfulData) {
      return null;
    }

    final sentences = <String>[];

    switch (sheet.overallStatus) {
      case BikeSystemOverallStatus.ok:
        sentences.add('El $brakeLabel se encuentra en buen estado general.');
        break;
      case BikeSystemOverallStatus.attention:
        sentences.add('El $brakeLabel presenta detalles que conviene revisar.');
        break;
      case BikeSystemOverallStatus.critical:
        sentences.add(
            'El $brakeLabel muestra hallazgos importantes que requieren atención pronta.');
        break;
      case BikeSystemOverallStatus.unknown:
        break;
    }

    if (sheet.symptomKeys.isNotEmpty) {
      final symptomLabels = canonicalizeBrakeSymptomKeys(sheet.symptomKeys)
          .map((value) => kBrakeSymptomLabels[value] ?? value)
          .toList(growable: false);
      sentences.add(
        'Durante la prueba se observaron síntomas como ${_joinNaturalList(symptomLabels)}.',
      );
    }

    if (sheet.padWearPercent != null) {
      final padWear = _describeBrakePadWearSentence(
        brakeLabel,
        sheet.padWearPercent,
      );
      if (padWear != null) {
        sentences.add(padWear);
      }
    }

    final padContamination = _describeBrakePadContaminationSentence(
        brakeLabel, sheet.padContaminationStatus);
    if (padContamination != null) {
      sentences.add(padContamination);
    }

    if (sheet.rotorThicknessMm != null) {
      final rotorWear = _describeRotorThicknessSentence(
        brakeLabel,
        sheet.rotorThicknessMm,
      );
      if (rotorWear != null) {
        sentences.add(rotorWear);
      }
    }

    final rotorTrueness =
        _describeRotorTruenessSentence(brakeLabel, sheet.rotorTruenessStatus);
    if (rotorTrueness != null) {
      sentences.add(rotorTrueness);
    }

    final rotorContamination = _describeRotorContaminationSentence(
      brakeLabel,
      sheet.rotorContaminationStatus,
    );
    if (rotorContamination != null) {
      sentences.add(rotorContamination);
    }

    final notes = _normalizeNullableText(sheet.notes ?? '');
    if (notes != null) {
      sentences.add('Además, en la inspección se consignó: $notes');
    }

    return sentences.isEmpty ? null : sentences.join(' ');
  }

  List<String> _buildDrivetrainRecommendationHints(
    DrivetrainDiagnosisSheet sheet,
  ) {
    final recommendations = <String>{};

    if (sheet.chainWearPercent != null) {
      if (sheet.chainWearPercent! >= 75) {
        recommendations.add(
          'reemplazar la cadena y revisar el desgaste asociado en cassette y plato',
        );
      } else if (sheet.chainWearPercent! >= 50) {
        recommendations.add(
          'revisar el desgaste de la cadena y su compatibilidad con cassette y plato',
        );
      }
    }

    if (sheet.chainLubricationStatus == 'dry' ||
        sheet.chainLubricationStatus == 'dirty' ||
        sheet.chainLubricationStatus == 'contaminated') {
      recommendations
          .add('realizar limpieza y lubricación completa de la transmisión');
    }

    if (sheet.cassetteCondition == 'worn' ||
        sheet.cassetteCondition == 'replace') {
      recommendations.add('evaluar cambio de cassette');
    }
    if (sheet.chainringCondition == 'worn' ||
        sheet.chainringCondition == 'replace') {
      recommendations.add('evaluar cambio de plato');
    }
    if (sheet.rearDerailleurCondition == 'attention' ||
        sheet.rearDerailleurCondition == 'bent' ||
        sheet.rearDerailleurCondition == 'replace') {
      recommendations.add('ajustar o reemplazar el cambio trasero');
    }
    if (sheet.frontDerailleurCondition == 'attention' ||
        sheet.frontDerailleurCondition == 'bent' ||
        sheet.frontDerailleurCondition == 'replace') {
      recommendations.add('ajustar o reemplazar el cambio delantero');
    }
    if (sheet.shifterCondition == 'sticky' ||
        sheet.shifterCondition == 'attention' ||
        sheet.shifterCondition == 'replace') {
      recommendations.add('revisar o reemplazar el shifter');
    }

    return recommendations.toList(growable: false);
  }

  List<String> _buildBrakeRecommendationHints(
    String brakeLabel,
    BrakeDiagnosisSheet sheet,
  ) {
    final recommendations = <String>{};

    if (sheet.padWearPercent != null) {
      if (sheet.padWearPercent! >= 75) {
        recommendations.add('reemplazar las pastillas del $brakeLabel');
      } else if (sheet.padWearPercent! >= 50) {
        recommendations.add('evaluar el cambio de pastillas del $brakeLabel');
      }
    }

    if (sheet.padContaminationStatus == 'contaminated') {
      recommendations
          .add('descontaminar o reemplazar las pastillas del $brakeLabel');
    }
    if (sheet.padContaminationStatus == 'replace') {
      recommendations.add('reemplazar las pastillas del $brakeLabel');
    }

    if (sheet.rotorThicknessMm != null) {
      if (sheet.rotorThicknessMm! <= 1.5) {
        recommendations.add('reemplazar el rotor del $brakeLabel');
      } else if (sheet.rotorThicknessMm! <= 1.7) {
        recommendations.add('revisar la vida útil del rotor del $brakeLabel');
      }
    }

    if (sheet.rotorTruenessStatus == 'misaligned') {
      recommendations.add('centrar el rotor del $brakeLabel');
    }
    if (sheet.rotorTruenessStatus == 'replace') {
      recommendations.add('reemplazar el rotor del $brakeLabel');
    }
    if (sheet.rotorContaminationStatus == 'contaminated') {
      recommendations.add('limpiar o descontaminar el rotor del $brakeLabel');
    }
    if (sheet.rotorContaminationStatus == 'replace') {
      recommendations.add('reemplazar el rotor del $brakeLabel');
    }

    if (sheet.symptomKeys.contains('spongy_lever')) {
      recommendations.add(
          'revisar el sistema del $brakeLabel para recuperar firmeza en la maneta');
    }
    if (sheet.symptomKeys.contains('low_power')) {
      recommendations.add(
          'recuperar la potencia de frenado del $brakeLabel mediante ajuste y revisión del conjunto');
    }

    return recommendations.toList(growable: false);
  }

  bool _drivetrainHasCriticalRisk(DrivetrainDiagnosisSheet sheet) {
    return sheet.overallStatus == BikeSystemOverallStatus.critical ||
        (sheet.chainWearPercent != null && sheet.chainWearPercent! >= 75) ||
        sheet.cassetteCondition == 'replace' ||
        sheet.chainringCondition == 'replace' ||
        sheet.rearDerailleurCondition == 'replace' ||
        sheet.frontDerailleurCondition == 'replace' ||
        sheet.shifterCondition == 'replace';
  }

  bool _brakeHasCriticalRisk(BrakeDiagnosisSheet sheet) {
    return sheet.overallStatus == BikeSystemOverallStatus.critical ||
        (sheet.padWearPercent != null && sheet.padWearPercent! >= 75) ||
        (sheet.rotorThicknessMm != null && sheet.rotorThicknessMm! <= 1.5) ||
        sheet.rotorTruenessStatus == 'replace' ||
        sheet.padContaminationStatus == 'replace' ||
        sheet.rotorContaminationStatus == 'replace';
  }

  String? _describeChainLubricationSentence(String? status) {
    switch (status) {
      case 'ok':
        return 'La cadena se encuentra correctamente lubricada.';
      case 'dry':
        return 'La cadena se encuentra seca y requiere lubricación.';
      case 'dirty':
        return 'La cadena presenta suciedad excesiva.';
      case 'contaminated':
        return 'La cadena se encuentra contaminada.';
      default:
        return null;
    }
  }

  String? _describeChainWearSentence(double? wearPercent) {
    if (wearPercent == null) {
      return null;
    }
    if (wearPercent >= 75) {
      return 'La cadena muestra un desgaste muy avanzado y ya está en rango de recambio.';
    }
    if (wearPercent >= 50) {
      return 'La cadena muestra un desgaste avanzado.';
    }
    if (wearPercent >= 25) {
      return 'La cadena ya presenta desgaste visible.';
    }
    return null;
  }

  String? _describeBrakePadWearSentence(
    String brakeLabel,
    double? wearPercent,
  ) {
    if (wearPercent == null) {
      return null;
    }
    if (wearPercent >= 75) {
      return 'Las pastillas del $brakeLabel están muy gastadas y cerca del fin de vida útil.';
    }
    if (wearPercent >= 50) {
      return 'Las pastillas del $brakeLabel muestran un desgaste avanzado.';
    }
    if (wearPercent >= 25) {
      return 'Las pastillas del $brakeLabel ya muestran desgaste y conviene seguirlas de cerca.';
    }
    return null;
  }

  String? _describeRotorThicknessSentence(
    String brakeLabel,
    double? thicknessMm,
  ) {
    if (thicknessMm == null) {
      return null;
    }
    if (thicknessMm <= 1.5) {
      return 'El rotor del $brakeLabel ya está por debajo del mínimo recomendado.';
    }
    if (thicknessMm <= 1.7) {
      return 'El rotor del $brakeLabel se encuentra cerca del límite de desgaste.';
    }
    return null;
  }

  String? _describeDrivetrainComponentSentence(String subject, String? status) {
    switch (status) {
      case 'ok':
        return '$subject se encuentra en buen estado.';
      case 'attention':
        return '$subject requiere atención.';
      case 'worn':
        return '$subject presenta desgaste.';
      case 'bent':
        return '$subject se encuentra desalineado o doblado.';
      case 'sticky':
        return '$subject presenta accionamiento duro o pegado.';
      case 'replace':
        return '$subject requiere reemplazo.';
      default:
        return null;
    }
  }

  String? _describeBrakePadContaminationSentence(
    String brakeLabel,
    String? status,
  ) {
    switch (status) {
      case 'ok':
        return null;
      case 'dirty':
        return 'Las pastillas del $brakeLabel presentan suciedad.';
      case 'contaminated':
        return 'Las pastillas del $brakeLabel están contaminadas.';
      case 'replace':
        return 'Las pastillas del $brakeLabel requieren reemplazo.';
      default:
        return null;
    }
  }

  String? _describeRotorTruenessSentence(String brakeLabel, String? status) {
    switch (status) {
      case 'ok':
        return null;
      case 'attention':
        return 'El rotor del $brakeLabel presenta una leve desalineación.';
      case 'misaligned':
        return 'El rotor del $brakeLabel se encuentra desviado y presenta roce.';
      case 'replace':
        return 'El rotor del $brakeLabel requiere reemplazo.';
      default:
        return null;
    }
  }

  String? _describeRotorContaminationSentence(
    String brakeLabel,
    String? status,
  ) {
    switch (status) {
      case 'ok':
        return null;
      case 'dirty':
        return 'El rotor del $brakeLabel presenta suciedad.';
      case 'contaminated':
        return 'El rotor del $brakeLabel está contaminado.';
      case 'replace':
        return 'El rotor del $brakeLabel requiere reemplazo.';
      default:
        return null;
    }
  }

  String _joinNaturalList(Iterable<String> values) {
    final items = values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);

    if (items.isEmpty) {
      return '';
    }
    if (items.length == 1) {
      return items.first;
    }
    if (items.length == 2) {
      return '${items.first} y ${items.last}';
    }
    return '${items.sublist(0, items.length - 1).join(', ')} y ${items.last}';
  }

  Color _diagnosisStatusColor(ThemeData theme, BikeSystemOverallStatus status) {
    switch (status) {
      case BikeSystemOverallStatus.ok:
        return Colors.green.shade700;
      case BikeSystemOverallStatus.attention:
        return Colors.orange.shade700;
      case BikeSystemOverallStatus.critical:
        return theme.colorScheme.error;
      case BikeSystemOverallStatus.unknown:
        return theme.colorScheme.onSurfaceVariant;
    }
  }

  String _formatDiagnosisSheetTimestamp(DateTime? timestamp) {
    if (timestamp == null) return 'Sin sincronizar';
    return DateFormat('dd/MM HH:mm').format(timestamp);
  }

  Widget _buildDiagnosisWorkspace(
    ThemeData theme,
    _BikeTabData currentTab,
    TextEditingController diagnosisCtrl,
  ) {
    final diagnosisSheet = _currentDiagnosisSheet;
    final statuses = [
      diagnosisSheet.drivetrain.overallStatus,
      diagnosisSheet.frontBrake.overallStatus,
      diagnosisSheet.rearBrake.overallStatus,
    ];
    final trackedSystems = statuses
        .where((status) => status != BikeSystemOverallStatus.unknown)
        .length;
    final criticalSystems = statuses
        .where((status) => status == BikeSystemOverallStatus.critical)
        .length;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7)),
        color: theme.colorScheme.surfaceContainerLowest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Diagnóstico ${currentTab.bike?.displayName ?? ''}'
                                .trim(),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Narrativa técnica y storage model sincronizados por bicicleta.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Sync ${_formatDiagnosisSheetTimestamp(currentTab.diagnosisSheetUpdatedAt)}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _buildDiagnosisSummaryChip(
                      theme,
                      icon: Icons.schema_outlined,
                      label: 'Template ${diagnosisSheet.templateKey}',
                    ),
                    _buildDiagnosisSummaryChip(
                      theme,
                      icon: Icons.tune_outlined,
                      label: '$trackedSystems sistemas revisados',
                    ),
                    _buildDiagnosisSummaryChip(
                      theme,
                      icon: Icons.warning_amber_rounded,
                      label: '$criticalSystems críticos',
                      tint: criticalSystems > 0
                          ? theme.colorScheme.error
                          : theme.colorScheme.tertiary,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: _buildDiagnosisSubtabs(theme),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: _selectedDiagnosisWorkbenchTab ==
                    _DiagnosisWorkbenchTab.narrative
                ? _buildNarrativeDiagnosisPanel(
                    theme, currentTab, diagnosisCtrl)
                : _buildStructuredDiagnosisPanel(theme, currentTab),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosisSection(ThemeData theme) {
    final currentTab = _currentBikeTab;
    final diagnosisCtrl =
        currentTab?.diagnosisController ?? _diagnosisController;

    if (currentTab == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(
              Icons.pedal_bike_outlined,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Agrega una bicicleta para habilitar la pestaña de diagnóstico.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (currentTab.isGeneralTab) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'La pestaña General / Venta no tiene diagnóstico propio. El diagnóstico se registra por bicicleta.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return _buildDiagnosisWorkspace(theme, currentTab, diagnosisCtrl);
  }

  Widget _buildDiagnosisSummaryChip(
    ThemeData theme, {
    required IconData icon,
    required String label,
    Color? tint,
  }) {
    final color = tint ?? theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosisSubtabs(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildDiagnosisSubtabButton(
              theme: theme,
              tab: _DiagnosisWorkbenchTab.structured,
              icon: Icons.account_tree_outlined,
              label: 'Modelo estructurado',
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _buildDiagnosisSubtabButton(
              theme: theme,
              tab: _DiagnosisWorkbenchTab.narrative,
              icon: Icons.edit_note_outlined,
              label: 'Ficha narrativa',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosisSubtabButton({
    required ThemeData theme,
    required _DiagnosisWorkbenchTab tab,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _selectedDiagnosisWorkbenchTab == tab;

    return Material(
      color: isSelected
          ? theme.colorScheme.secondaryContainer
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () {
          if (_selectedDiagnosisWorkbenchTab == tab) return;
          setState(() {
            _selectedDiagnosisWorkbenchTab = tab;
          });
        },
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? theme.colorScheme.onSecondaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? theme.colorScheme.onSecondaryContainer
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNarrativeDiagnosisPanel(
    ThemeData theme,
    _BikeTabData currentTab,
    TextEditingController diagnosisCtrl,
  ) {
    final isGenerating = _isGeneratingNarrativeDraftFor(currentTab);
    final canGenerate = currentTab.diagnosisSheet.hasMeaningfulData;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Diagnosis sheet narrativa',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Editor técnico con atajos para dejar hallazgos, acciones y repuestos en una sola hoja.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: isGenerating || !canGenerate
                    ? null
                    : () => _handleGenerateNarrativeDraft(currentTab),
                icon: isGenerating
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.auto_awesome_outlined, size: 16),
                label: Text(
                  isGenerating ? 'Redactando...' : 'Redactar desde modelo',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            canGenerate
                ? 'Genera un borrador legible para el cliente usando solo los datos definidos del modelo estructurado. El borrador se organiza por componentes y se previsualiza con títulos en negrita.'
                : 'Completa primero el modelo estructurado para generar un borrador narrativo.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildDiagnosisToolbarButton(
                  theme,
                  icon: Icons.format_list_bulleted,
                  label: 'Bullet',
                  onTap: () => _insertDiagnosisSnippet(diagnosisCtrl, '• '),
                ),
                _buildDiagnosisToolbarButton(
                  theme,
                  icon: Icons.title_outlined,
                  label: 'Título',
                  onTap: () => _insertDiagnosisSnippet(
                    diagnosisCtrl,
                    '\n### Título\n',
                  ),
                ),
                _buildDiagnosisToolbarButton(
                  theme,
                  icon: Icons.search_outlined,
                  label: 'Hallazgo',
                  onTap: () => _insertDiagnosisSnippet(
                    diagnosisCtrl,
                    '\nHallazgo:\n',
                  ),
                ),
                _buildDiagnosisToolbarButton(
                  theme,
                  icon: Icons.construction_outlined,
                  label: 'Acción',
                  onTap: () => _insertDiagnosisSnippet(
                    diagnosisCtrl,
                    '\nAcción recomendada:\n',
                  ),
                ),
                _buildDiagnosisToolbarButton(
                  theme,
                  icon: Icons.inventory_2_outlined,
                  label: 'Repuesto',
                  onTap: () => _insertDiagnosisSnippet(
                    diagnosisCtrl,
                    '\nRepuesto sugerido:\n',
                  ),
                ),
                _buildDiagnosisToolbarButton(
                  theme,
                  icon: Icons.priority_high_outlined,
                  label: 'Urgente',
                  onTap: () => _insertDiagnosisSnippet(
                    diagnosisCtrl,
                    '\n[URGENTE] ',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: ValueKey(
              'diagnosis_workspace_${_currentBikeTab?.tabId ?? "legacy"}',
            ),
            controller: diagnosisCtrl,
            decoration: const InputDecoration(
              labelText: 'Ficha de diagnóstico',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
              hintText:
                  'Describe hallazgos, pruebas realizadas, riesgos y acciones recomendadas. Puedes usar títulos markdown como ### Freno delantero.',
            ),
            maxLines: 12,
            minLines: 10,
            onChanged: (_) => setState(() {}),
          ),
          if (diagnosisCtrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildNarrativePreviewCard(theme, diagnosisCtrl.text),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${diagnosisCtrl.text.trim().isEmpty ? 0 : diagnosisCtrl.text.trim().split(RegExp(r'\\s+')).length} palabras',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                'Se guarda en el diagnóstico narrativo de esta bicicleta',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNarrativePreviewCard(ThemeData theme, String markdown) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vista previa formateada',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          MarkdownBody(
            data: markdown,
            selectable: true,
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              h3: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
              p: theme.textTheme.bodyMedium?.copyWith(
                height: 1.45,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosisToolbarButton(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.colorScheme.onSurface,
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }

  Widget _buildStructuredDiagnosisPanel(
    ThemeData theme,
    _BikeTabData currentTab,
  ) {
    final diagnosisSheet = currentTab.diagnosisSheet;

    final activeSystemKey = _resolveStructuredDiagnosisSystemKey(currentTab);
    final activeSpec = bikeSystemControllerSpecFor(activeSystemKey) ??
        _kStructuredDiagnosisEditableSystems.first;
    final profile =
        _selectedBike?.id == currentTab.bike?.id ? _selectedBikeProfile : null;
    final bikeVariant = resolveBikeDiagramVariant(
      bike: currentTab.bike,
    );
    final brakeType = profile?.technicalValues['brakeType']?.toString();

    return LayoutBuilder(
      builder: (context, constraints) {
        final wideLayout = constraints.maxWidth >= 980;
        final diagramPanel = _buildStructuredDiagnosisDiagramPanel(
          theme,
          currentTab: currentTab,
          activeSystemKey: activeSystemKey,
          bikeVariant: bikeVariant,
          brakeType: brakeType,
        );
        final inspectorPanel = _buildStructuredDiagnosisInspectorPanel(
          theme,
          currentTab: currentTab,
          diagnosisSheet: diagnosisSheet,
          activeSpec: activeSpec,
          profile: profile,
          brakeType: brakeType,
        );

        if (wideLayout) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 4, child: diagramPanel),
              const SizedBox(width: 18),
              Expanded(flex: 5, child: inspectorPanel),
            ],
          );
        }

        return Column(
          children: [
            diagramPanel,
            const SizedBox(height: 16),
            inspectorPanel,
          ],
        );
      },
    );
  }

  String _resolveStructuredDiagnosisSystemKey(_BikeTabData currentTab) {
    final preferred = _selectedStructuredDiagnosisSystemKey;
    if (preferred != null && bikeSystemControllerSpecFor(preferred) != null) {
      return preferred;
    }

    String fallbackKey = _kStructuredDiagnosisEditableSystems.first.systemKey;
    var fallbackRank = -1;

    for (final spec in _kStructuredDiagnosisEditableSystems) {
      final status = _structuredDiagnosisStatus(
        currentTab.diagnosisSheet,
        spec.systemKey,
      );
      final hasData = _structuredDiagnosisHasMeaningfulData(
        currentTab.diagnosisSheet,
        spec.systemKey,
      );
      final rank = _structuredDiagnosisStatusRank(status) + (hasData ? 1 : 0);
      if (rank > fallbackRank) {
        fallbackKey = spec.systemKey;
        fallbackRank = rank;
      }
    }

    return fallbackKey;
  }

  int _structuredDiagnosisStatusRank(BikeSystemOverallStatus status) {
    switch (status) {
      case BikeSystemOverallStatus.critical:
        return 3;
      case BikeSystemOverallStatus.attention:
        return 2;
      case BikeSystemOverallStatus.ok:
        return 1;
      case BikeSystemOverallStatus.unknown:
        return 0;
    }
  }

  BikeSystemOverallStatus _structuredDiagnosisStatus(
    MechanicJobDiagnosisSheet sheet,
    String systemKey,
  ) {
    switch (systemKey) {
      case 'cockpit':
      case 'suspension':
      case 'wheels':
        return BikeSystemOverallStatus.unknown;
      case 'front_brake':
        return sheet.frontBrake.overallStatus;
      case 'rear_brake':
        return sheet.rearBrake.overallStatus;
      case 'drivetrain':
      default:
        return sheet.drivetrain.overallStatus;
    }
  }

  bool _structuredDiagnosisHasMeaningfulData(
    MechanicJobDiagnosisSheet sheet,
    String systemKey,
  ) {
    switch (systemKey) {
      case 'cockpit':
      case 'suspension':
      case 'wheels':
        return false;
      case 'front_brake':
        return sheet.frontBrake.hasMeaningfulData;
      case 'rear_brake':
        return sheet.rearBrake.hasMeaningfulData;
      case 'drivetrain':
      default:
        return sheet.drivetrain.hasMeaningfulData;
    }
  }

  List<_StructuredDiagnosisComponentSpec> _structuredDiagnosisComponentSpecs(
    String systemKey,
    BikeProfile? profile,
  ) {
    var specs = _kStructuredDiagnosisComponentSpecs
        .where((spec) => spec.systemKey == systemKey)
        .toList();

    if (systemKey == 'front_brake' || systemKey == 'rear_brake') {
      final brakeType = profile?.technicalValues['brakeType']
          ?.toString()
          .trim()
          .toLowerCase();
      if (!_isDiscBrakeType(brakeType)) {
        specs = specs.where((spec) => spec.componentKey != 'rotor').toList();
      }
      return specs;
    }

    if (systemKey != 'drivetrain') {
      return specs;
    }

    final config = profile?.technicalValues['drivetrainConfig']
        ?.toString()
        .trim()
        .toLowerCase();
    final isSingleSpeed = config == 'singlespeed' ||
        config == 'single_speed' ||
        (config?.contains('fixie') ?? false) ||
        (config?.contains('single') ?? false);
    final usesFrontDerailleur = !isSingleSpeed &&
        !((config?.startsWith('1x') ?? false) || config == '1x');

    specs = specs.where((spec) {
      switch (spec.componentKey) {
        case 'front_derailleur':
          return usesFrontDerailleur;
        case 'rear_derailleur':
        case 'shifter':
          return !isSingleSpeed;
        default:
          return true;
      }
    }).toList();

    return specs;
  }

  String _diagnosisComponentSelectionScopeKey(String tabId, String systemKey) {
    return '$tabId::$systemKey';
  }

  String? _resolveStructuredDiagnosisComponentKey(
    String systemKey,
    BikeProfile? profile, {
    required String selectionScopeKey,
  }) {
    final specs = _structuredDiagnosisComponentSpecs(systemKey, profile);
    if (specs.isEmpty) {
      return null;
    }

    final preferred =
        _selectedStructuredDiagnosisComponentKeys[selectionScopeKey];
    if (preferred != null &&
        specs.any((spec) => spec.componentKey == preferred)) {
      return preferred;
    }

    return specs.first.componentKey;
  }

  BikeSystemOverallStatus _statusFromConditionValue(String? rawValue) {
    switch (rawValue) {
      case 'replace':
      case 'critical':
      case 'bent':
      case 'damaged':
      case 'contaminated':
        return BikeSystemOverallStatus.critical;
      case 'attention':
      case 'worn':
      case 'dry':
      case 'dirty':
      case 'sticky':
        return BikeSystemOverallStatus.attention;
      case 'ok':
        return BikeSystemOverallStatus.ok;
      default:
        return BikeSystemOverallStatus.unknown;
    }
  }

  BikeSystemOverallStatus _drivetrainComponentStatus(
    DrivetrainDiagnosisSheet sheet,
    String componentKey,
  ) {
    switch (componentKey) {
      case 'chain':
        final wear = sheet.chainWearPercent;
        if (wear != null) {
          if (wear >= 75) return BikeSystemOverallStatus.critical;
          if (wear >= 50) return BikeSystemOverallStatus.attention;
          return BikeSystemOverallStatus.ok;
        }
        return _statusFromConditionValue(sheet.chainLubricationStatus);
      case 'cassette':
        return _statusFromConditionValue(sheet.cassetteCondition);
      case 'chainring':
        return _statusFromConditionValue(sheet.chainringCondition);
      case 'rear_derailleur':
        return _statusFromConditionValue(sheet.rearDerailleurCondition);
      case 'front_derailleur':
        return _statusFromConditionValue(sheet.frontDerailleurCondition);
      case 'shifter':
        return _statusFromConditionValue(sheet.shifterCondition);
      default:
        return BikeSystemOverallStatus.unknown;
    }
  }

  BikeSystemOverallStatus _maxSystemStatus(
    Iterable<BikeSystemOverallStatus> values,
  ) {
    if (values.any((value) => value == BikeSystemOverallStatus.critical)) {
      return BikeSystemOverallStatus.critical;
    }
    if (values.any((value) => value == BikeSystemOverallStatus.attention)) {
      return BikeSystemOverallStatus.attention;
    }
    if (values.any((value) => value == BikeSystemOverallStatus.ok)) {
      return BikeSystemOverallStatus.ok;
    }
    return BikeSystemOverallStatus.unknown;
  }

  double _chainWearGaugeValue(double? rawValue) {
    if (rawValue == null) {
      return 0.0;
    }

    final normalized = rawValue > 1 ? rawValue / 100 : rawValue;
    return normalized.clamp(0.0, 1.0);
  }

  double _chainWearPercentFromGauge(double gaugeValue) {
    return (gaugeValue * 100).clamp(0.0, 100.0);
  }

  String _formatChainWearGauge(double? rawValue) {
    if (rawValue == null) {
      return 'Sin medición';
    }
    return _chainWearGaugeValue(rawValue).toStringAsFixed(2);
  }

  Widget _buildStructuredDiagnosisDiagramPanel(
    ThemeData theme, {
    required _BikeTabData currentTab,
    required String activeSystemKey,
    required BikeDiagramVariant bikeVariant,
    required String? brakeType,
  }) {
    final rimBrakeFamily = _selectedBike?.id == currentTab.bike?.id
        ? _selectedBikeProfile?.technicalValues['rimBrakeFamily']?.toString()
        : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mapa técnico interactivo',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Selecciona un sistema sobre la bicicleta para editar el mismo diagnosis sheet de la visita.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          AspectRatio(
            aspectRatio: 1,
            child: BikeSystemController(
              bike: currentTab.bike,
              variant: bikeVariant,
              entries: kBikeSystemControllerSpecs
                  .map(
                    (spec) => BikeSystemControllerEntry(
                      spec: spec,
                      status: _structuredDiagnosisStatus(
                        currentTab.diagnosisSheet,
                        spec.systemKey,
                      ),
                    ),
                  )
                  .toList(growable: false),
              selectedSystemKey: activeSystemKey,
              onSystemSelected: (systemKey) {
                setState(() {
                  _selectedStructuredDiagnosisSystemKey = systemKey;
                });
              },
              onClearSelection: () {
                setState(() {
                  _selectedStructuredDiagnosisSystemKey = null;
                });
              },
              idleHintText: 'Haz clic en un sistema para cambiar la vista.',
              selectedHintText:
                  'Haz clic en otro componente para cambiar la vista.',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildStructuredDiagnosisMetaChip(
                theme,
                icon: Icons.category_outlined,
                label: bikeVariant.displayName,
              ),
              if (brakeType != null && brakeType.isNotEmpty)
                _buildStructuredDiagnosisMetaChip(
                  theme,
                  icon: Icons.disc_full,
                  label:
                      'Freno ${_formatBrakeSystemDetail(brakeType, rimBrakeFamily)}',
                ),
              if (currentTab.bike?.wheelSize?.isNotEmpty == true)
                _buildStructuredDiagnosisMetaChip(
                  theme,
                  icon: Icons.circle_outlined,
                  label: 'Aro ${currentTab.bike!.wheelSize!}',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStructuredDiagnosisMetaChip(
    ThemeData theme, {
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatBrakeType(String rawValue) {
    switch (rawValue) {
      case 'rim':
        return 'llanta';
      case 'mechanical_disc':
        return 'disco mecánico';
      case 'hydraulic_disc':
        return 'disco hidráulico';
      case 'roller_brake':
        return 'roller brake';
      case 'drum_brake':
        return 'tambor';
      case 'coaster_brake':
        return 'contrapedal';
      case 'band_brake':
        return 'banda';
      default:
        return rawValue;
    }
  }

  bool _isDiscBrakeType(String? rawValue) {
    return rawValue == 'mechanical_disc' || rawValue == 'hydraulic_disc';
  }

  String? _formatRimBrakeFamily(String? rawValue) {
    switch (rawValue) {
      case 'v_brake':
        return 'V-Brake';
      case 'cantilever':
        return 'Cantilever';
      case 'road_caliper_short_reach':
        return 'caliper ruta corto';
      case 'road_caliper_long_reach':
        return 'caliper ruta largo';
      case 'u_brake':
        return 'U-Brake';
      case 'rod_brake':
        return 'freno de varilla';
      case 'other':
        return 'otro sistema de llanta';
      case 'unknown':
        return 'familia de llanta no confirmada';
      default:
        return rawValue;
    }
  }

  String _formatBrakeSystemDetail(
    String? rawBrakeType,
    String? rawRimBrakeFamily,
  ) {
    if (rawBrakeType == null || rawBrakeType.isEmpty) {
      return 'desconocido';
    }

    if (rawBrakeType == 'rim') {
      final rimBrakeFamily = _formatRimBrakeFamily(rawRimBrakeFamily);
      if (rimBrakeFamily != null && rimBrakeFamily.isNotEmpty) {
        return 'de llanta ($rimBrakeFamily)';
      }
    }

    return _formatBrakeType(rawBrakeType);
  }

  Widget _buildStructuredDiagnosisInspectorPanel(
    ThemeData theme, {
    required _BikeTabData currentTab,
    required MechanicJobDiagnosisSheet diagnosisSheet,
    required BikeSystemControllerSpec activeSpec,
    required BikeProfile? profile,
    required String? brakeType,
  }) {
    final rimBrakeFamily =
        profile?.technicalValues['rimBrakeFamily']?.toString();
    switch (activeSpec.systemKey) {
      case 'cockpit':
      case 'suspension':
      case 'wheels':
        return _buildUnavailableStructuredDiagnosisSystemCard(
          theme,
          activeSpec: activeSpec,
          profile: profile,
          bike: currentTab.bike,
          templateKey: diagnosisSheet.templateKey,
        );
      case 'front_brake':
        return _buildDiagnosisSystemCard(
          theme,
          title: activeSpec.label,
          subtitle: activeSpec.diagnosisSubtitle,
          status: diagnosisSheet.frontBrake.overallStatus,
          statusTint: _diagnosisStatusColor(
            theme,
            diagnosisSheet.frontBrake.overallStatus,
          ),
          onStatusChanged: (status) => _updateCurrentDiagnosisSheet(
            (current) => current.copyWith(
              frontBrake: current.frontBrake.copyWith(overallStatus: status),
            ),
          ),
          child: _buildBrakeDiagnosisFields(
            currentTab,
            systemKey: 'front_brake',
            profile: profile,
            brakeSheet: diagnosisSheet.frontBrake,
            prefix: 'front',
            title: 'delantero',
            helperText: brakeType != null && !_isDiscBrakeType(brakeType)
                ? 'La ficha técnica upstream marca esta bicicleta como freno ${_formatBrakeSystemDetail(brakeType, rimBrakeFamily)}, por eso no se solicita grosor de rotor.'
                : null,
            update: (transform, {refresh = true}) =>
                _updateCurrentDiagnosisSheet(
              (current) =>
                  current.copyWith(frontBrake: transform(current.frontBrake)),
              refresh: refresh,
            ),
          ),
        );
      case 'rear_brake':
        return _buildDiagnosisSystemCard(
          theme,
          title: activeSpec.label,
          subtitle: activeSpec.diagnosisSubtitle,
          status: diagnosisSheet.rearBrake.overallStatus,
          statusTint: _diagnosisStatusColor(
            theme,
            diagnosisSheet.rearBrake.overallStatus,
          ),
          onStatusChanged: (status) => _updateCurrentDiagnosisSheet(
            (current) => current.copyWith(
              rearBrake: current.rearBrake.copyWith(overallStatus: status),
            ),
          ),
          child: _buildBrakeDiagnosisFields(
            currentTab,
            systemKey: 'rear_brake',
            profile: profile,
            brakeSheet: diagnosisSheet.rearBrake,
            prefix: 'rear',
            title: 'trasero',
            helperText: brakeType != null && !_isDiscBrakeType(brakeType)
                ? 'La ficha técnica upstream marca esta bicicleta como freno ${_formatBrakeSystemDetail(brakeType, rimBrakeFamily)}, por eso no se solicita grosor de rotor.'
                : null,
            update: (transform, {refresh = true}) =>
                _updateCurrentDiagnosisSheet(
              (current) =>
                  current.copyWith(rearBrake: transform(current.rearBrake)),
              refresh: refresh,
            ),
          ),
        );
      case 'drivetrain':
      default:
        return _buildDiagnosisSystemCard(
          theme,
          title: activeSpec.label,
          subtitle: activeSpec.diagnosisSubtitle,
          status: diagnosisSheet.drivetrain.overallStatus,
          statusTint: _diagnosisStatusColor(
            theme,
            diagnosisSheet.drivetrain.overallStatus,
          ),
          onStatusChanged: (status) => _updateCurrentDiagnosisSheet(
            (current) => current.copyWith(
              drivetrain: current.drivetrain.copyWith(overallStatus: status),
            ),
          ),
          child: _buildDrivetrainDiagnosisFields(
            currentTab,
            drivetrainSheet: diagnosisSheet.drivetrain,
            profile: profile,
          ),
        );
    }
  }

  Widget _buildDrivetrainDiagnosisFields(
    _BikeTabData currentTab, {
    required DrivetrainDiagnosisSheet drivetrainSheet,
    required BikeProfile? profile,
  }) {
    final selectionScopeKey = _diagnosisComponentSelectionScopeKey(
      currentTab.tabId,
      'drivetrain',
    );
    final componentSpecs =
        _structuredDiagnosisComponentSpecs('drivetrain', profile);
    final selectedComponentKey = _resolveStructuredDiagnosisComponentKey(
      'drivetrain',
      profile,
      selectionScopeKey: selectionScopeKey,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (componentSpecs.isNotEmpty) ...[
          Text(
            'Componentes del sistema',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          _buildDiagnosisComponentSelector(
            Theme.of(context),
            specs: componentSpecs,
            selectedComponentKey: selectedComponentKey,
            statusForComponent: (componentKey) =>
                _drivetrainComponentStatus(drivetrainSheet, componentKey),
            onSelected: (componentKey) {
              setState(() {
                _selectedStructuredDiagnosisComponentKeys[selectionScopeKey] =
                    componentKey;
              });
            },
          ),
          const SizedBox(height: 16),
        ],
        if (selectedComponentKey != null)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Container(
              key: ValueKey('editor_$selectedComponentKey'),
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.5),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: _buildDrivetrainComponentEditor(
                currentTab,
                drivetrainSheet: drivetrainSheet,
                componentKey: selectedComponentKey,
              ),
            ),
          ),
        const SizedBox(height: 20),
        TextFormField(
          key: ValueKey(
            'diag_drive_notes_${currentTab.tabId}_${drivetrainSheet.notes ?? 'empty'}',
          ),
          initialValue: drivetrainSheet.notes,
          decoration: const InputDecoration(
            labelText: 'Notas transmisión',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          maxLines: 3,
          onChanged: (value) {
            final normalized = _normalizeNullableText(value);
            _updateCurrentDiagnosisSheet(
              (current) => current.copyWith(
                drivetrain: current.drivetrain.copyWith(
                  notes: normalized,
                  clearNotes: normalized == null,
                ),
              ),
              refresh: false,
            );
          },
        ),
      ],
    );
  }

  Widget _buildDiagnosisComponentSelector(
    ThemeData theme, {
    required List<_StructuredDiagnosisComponentSpec> specs,
    required String? selectedComponentKey,
    required BikeSystemOverallStatus Function(String componentKey)
        statusForComponent,
    required ValueChanged<String> onSelected,
  }) {
    return _DiagnosisComponentSelectorStrip(
      key: ValueKey(
          specs.isEmpty ? 'diag_components_empty' : specs.first.systemKey),
      specs: specs,
      selectedComponentKey: selectedComponentKey,
      statusForComponent: statusForComponent,
      onSelected: onSelected,
      colorForStatus: (status) => _diagnosisStatusColor(theme, status),
    );
  }

  Widget _buildDrivetrainComponentEditor(
    _BikeTabData currentTab, {
    required DrivetrainDiagnosisSheet drivetrainSheet,
    required String componentKey,
  }) {
    switch (componentKey) {
      case 'chain':
        return Column(
          children: [
            _buildChainWearField(currentTab, drivetrainSheet),
            const SizedBox(height: 12),
            _buildDiagnosisSelectField(
              keySuffix:
                  'diag_chain_lube_${currentTab.tabId}_${drivetrainSheet.chainLubricationStatus ?? 'empty'}',
              label: 'Lubricación cadena',
              icon: Icons.opacity_outlined,
              value: drivetrainSheet.chainLubricationStatus,
              options: _kChainLubricationOptions,
              onChanged: (value) {
                _updateCurrentDiagnosisSheet(
                  (current) => current.copyWith(
                    drivetrain: current.drivetrain.copyWith(
                      chainLubricationStatus: value,
                      clearChainLubricationStatus: value == null,
                    ),
                  ),
                );
              },
            ),
          ],
        );
      case 'cassette':
        return _buildDiagnosisSelectField(
          keySuffix:
              'diag_cassette_${currentTab.tabId}_${drivetrainSheet.cassetteCondition ?? 'empty'}',
          label: 'Estado cassette',
          icon: Icons.settings_input_component_outlined,
          value: drivetrainSheet.cassetteCondition,
          options: _kDrivetrainWearConditionOptions,
          onChanged: (value) {
            _updateCurrentDiagnosisSheet(
              (current) => current.copyWith(
                drivetrain: current.drivetrain.copyWith(
                  cassetteCondition: value,
                  clearCassetteCondition: value == null,
                ),
              ),
            );
          },
        );
      case 'chainring':
        return _buildDiagnosisSelectField(
          keySuffix:
              'diag_chainring_${currentTab.tabId}_${drivetrainSheet.chainringCondition ?? 'empty'}',
          label: 'Estado plato',
          icon: Icons.adjust,
          value: drivetrainSheet.chainringCondition,
          options: _kDrivetrainWearConditionOptions,
          onChanged: (value) {
            _updateCurrentDiagnosisSheet(
              (current) => current.copyWith(
                drivetrain: current.drivetrain.copyWith(
                  chainringCondition: value,
                  clearChainringCondition: value == null,
                ),
              ),
            );
          },
        );
      case 'rear_derailleur':
        return _buildDiagnosisSelectField(
          keySuffix:
              'diag_rear_derailleur_${currentTab.tabId}_${drivetrainSheet.rearDerailleurCondition ?? 'empty'}',
          label: 'Estado cambio trasero',
          icon: Icons.alt_route_outlined,
          value: drivetrainSheet.rearDerailleurCondition,
          options: _kDerailleurConditionOptions,
          onChanged: (value) {
            _updateCurrentDiagnosisSheet(
              (current) => current.copyWith(
                drivetrain: current.drivetrain.copyWith(
                  rearDerailleurCondition: value,
                  clearRearDerailleurCondition: value == null,
                ),
              ),
            );
          },
        );
      case 'front_derailleur':
        return _buildDiagnosisSelectField(
          keySuffix:
              'diag_front_derailleur_${currentTab.tabId}_${drivetrainSheet.frontDerailleurCondition ?? 'empty'}',
          label: 'Estado cambio delantero',
          icon: Icons.call_split_outlined,
          value: drivetrainSheet.frontDerailleurCondition,
          options: _kDerailleurConditionOptions,
          onChanged: (value) {
            _updateCurrentDiagnosisSheet(
              (current) => current.copyWith(
                drivetrain: current.drivetrain.copyWith(
                  frontDerailleurCondition: value,
                  clearFrontDerailleurCondition: value == null,
                ),
              ),
            );
          },
        );
      case 'shifter':
      default:
        return _buildDiagnosisSelectField(
          keySuffix:
              'diag_shifter_${currentTab.tabId}_${drivetrainSheet.shifterCondition ?? 'empty'}',
          label: 'Estado shifter',
          icon: Icons.touch_app_outlined,
          value: drivetrainSheet.shifterCondition,
          options: _kShifterConditionOptions,
          onChanged: (value) {
            _updateCurrentDiagnosisSheet(
              (current) => current.copyWith(
                drivetrain: current.drivetrain.copyWith(
                  shifterCondition: value,
                  clearShifterCondition: value == null,
                ),
              ),
            );
          },
        );
    }
  }

  Widget _buildChainWearField(
    _BikeTabData currentTab,
    DrivetrainDiagnosisSheet drivetrainSheet,
  ) {
    final gaugeValue = _chainWearGaugeValue(drivetrainSheet.chainWearPercent);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Medición desgaste cadena',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _formatChainWearGauge(drivetrainSheet.chainWearPercent),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            if (drivetrainSheet.chainWearPercent != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  _updateCurrentDiagnosisSheet(
                    (current) => current.copyWith(
                      drivetrain: current.drivetrain.copyWith(
                        clearChainWearPercent: true,
                      ),
                    ),
                  );
                },
                child: const Text('Limpiar'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Usa la medición tipo checker 0.0 a 1.0. El sistema la conserva internamente como porcentaje para compatibilidad con el modelo actual.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        Slider(
          key: ValueKey(
            'diag_chain_slider_${currentTab.tabId}_${drivetrainSheet.chainWearPercent?.toString() ?? 'empty'}',
          ),
          value: gaugeValue,
          min: 0.0,
          max: 1.0,
          divisions: 20,
          label: gaugeValue.toStringAsFixed(2),
          onChanged: (value) {
            _updateCurrentDiagnosisSheet(
              (current) => current.copyWith(
                drivetrain: current.drivetrain.copyWith(
                  chainWearPercent: _chainWearPercentFromGauge(value),
                ),
              ),
            );
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('0.0', style: Theme.of(context).textTheme.bodySmall),
            Text('0.5', style: Theme.of(context).textTheme.bodySmall),
            Text('0.75', style: Theme.of(context).textTheme.bodySmall),
            Text('1.0', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ],
    );
  }

  Widget _buildDiagnosisSelectField({
    required String keySuffix,
    required String label,
    required IconData icon,
    required String? value,
    required Map<String, String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return BikeshopSingleSelectDropdownField(
      key: ValueKey(keySuffix),
      options: serviceQuestionOptionsFromMap(options),
      value: value,
      labelText: label,
      icon: icon,
      includeEmptyOption: true,
      onChanged: onChanged,
    );
  }

  BikeSystemOverallStatus _brakeComponentStatus(
    BrakeDiagnosisSheet brakeSheet,
    String componentKey,
  ) {
    switch (componentKey) {
      case 'brake_pad':
        return _maxSystemStatus([
          _statusFromWearPercentValue(brakeSheet.padWearPercent),
          _statusFromConditionValue(brakeSheet.padContaminationStatus),
        ]);
      case 'rotor':
        return _maxSystemStatus([
          _statusFromRotorThicknessValue(brakeSheet.rotorThicknessMm),
          _statusFromConditionValue(brakeSheet.rotorTruenessStatus),
          _statusFromConditionValue(brakeSheet.rotorContaminationStatus),
        ]);
      default:
        return BikeSystemOverallStatus.unknown;
    }
  }

  BikeSystemOverallStatus _statusFromWearPercentValue(double? value) {
    if (value == null) return BikeSystemOverallStatus.unknown;
    if (value >= 75) return BikeSystemOverallStatus.critical;
    if (value >= 50) return BikeSystemOverallStatus.attention;
    return BikeSystemOverallStatus.ok;
  }

  BikeSystemOverallStatus _statusFromRotorThicknessValue(double? value) {
    if (value == null) return BikeSystemOverallStatus.unknown;
    if (value <= 1.5) return BikeSystemOverallStatus.critical;
    if (value <= 1.7) return BikeSystemOverallStatus.attention;
    return BikeSystemOverallStatus.ok;
  }

  String _formatPercentMeasurement(double? value) {
    if (value == null) return 'Sin medicion';
    return '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)}%';
  }

  String _formatRotorThickness(double? value) {
    if (value == null) return 'Sin medicion';
    return '${value.toStringAsFixed(2)} mm';
  }

  Widget _buildDiagnosisSystemCard(
    ThemeData theme, {
    required String title,
    required String subtitle,
    required BikeSystemOverallStatus status,
    required Color statusTint,
    required ValueChanged<BikeSystemOverallStatus> onStatusChanged,
    required Widget child,
  }) {
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusTint.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status.displayName,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: statusTint,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<BikeSystemOverallStatus>(
            key: ValueKey('diag_status_${title}_${status.dbValue}'),
            initialValue: status,
            decoration: const InputDecoration(
              labelText: 'Estado general',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.monitor_heart_outlined),
            ),
            items: BikeSystemOverallStatus.values.map((value) {
              return DropdownMenuItem(
                value: value,
                child: Text(value.displayName),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                onStatusChanged(value);
              }
            },
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildUnavailableStructuredDiagnosisSystemCard(
    ThemeData theme, {
    required BikeSystemControllerSpec activeSpec,
    required BikeProfile? profile,
    required Bike? bike,
    required String templateKey,
  }) {
    final technicalValues =
        profile?.technicalValues ?? const <String, dynamic>{};
    final contextLines = <String>[];

    switch (activeSpec.systemKey) {
      case 'suspension':
        final suspensionLayout =
            technicalValues['suspensionLayout']?.toString();
        if (suspensionLayout != null && suspensionLayout.isNotEmpty) {
          contextLines.add('Suspensión confirmada: $suspensionLayout');
        }
        break;
      case 'wheels':
        if (bike?.wheelSize?.trim().isNotEmpty == true) {
          contextLines.add('Aro: ${bike!.wheelSize!.trim()}');
        }
        final frontSpokeHoles = technicalValues['frontSpokeHoles']?.toString();
        if (frontSpokeHoles != null && frontSpokeHoles.isNotEmpty) {
          contextLines.add('Rayos rueda delantera: $frontSpokeHoles');
        }
        final rearSpokeHoles = technicalValues['rearSpokeHoles']?.toString();
        if (rearSpokeHoles != null && rearSpokeHoles.isNotEmpty) {
          contextLines.add('Rayos rueda trasera: $rearSpokeHoles');
        }
        final valveType = technicalValues['valveType']?.toString();
        if (valveType != null && valveType.isNotEmpty) {
          contextLines.add('Válvula: $valveType');
        }
        break;
      case 'cockpit':
      case 'front_brake':
      case 'rear_brake':
      case 'drivetrain':
        break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activeSpec.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      activeSpec.diagnosisSubtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Sin ficha estructurada',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Este sistema ya usa el mismo controlador visual compartido del resto del backbone, pero la plantilla $templateKey todavía no modela una ficha estructurada editable para esta visita.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Hoy la verdad estructurada de la visita sigue limitada a transmisión, freno delantero y freno trasero. Cuando este sistema gane soporte, el mismo controlador se reutilizará aquí sin crear otra variante visual.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          if (contextLines.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Contexto upstream disponible',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ...contextLines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.subdirectory_arrow_right,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        line,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBrakeDiagnosisFields(
    _BikeTabData currentTab, {
    required String systemKey,
    required BikeProfile? profile,
    required BrakeDiagnosisSheet brakeSheet,
    required String prefix,
    required String title,
    String? helperText,
    required _BrakeDiagnosisSheetUpdater update,
  }) {
    final selectionScopeKey = _diagnosisComponentSelectionScopeKey(
      currentTab.tabId,
      systemKey,
    );
    final componentSpecs =
        _structuredDiagnosisComponentSpecs(systemKey, profile);
    final selectedComponentKey = _resolveStructuredDiagnosisComponentKey(
      systemKey,
      profile,
      selectionScopeKey: selectionScopeKey,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (componentSpecs.isNotEmpty) ...[
          Text(
            'Componentes del sistema',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          _buildDiagnosisComponentSelector(
            Theme.of(context),
            specs: componentSpecs,
            selectedComponentKey: selectedComponentKey,
            statusForComponent: (componentKey) =>
                _brakeComponentStatus(brakeSheet, componentKey),
            onSelected: (componentKey) {
              setState(() {
                _selectedStructuredDiagnosisComponentKeys[selectionScopeKey] =
                    componentKey;
              });
            },
          ),
          const SizedBox(height: 16),
        ],
        if (selectedComponentKey != null)
          _buildBrakeComponentEditor(
            currentTab,
            brakeSheet: brakeSheet,
            componentKey: selectedComponentKey,
            prefix: prefix,
            title: title,
            update: update,
          ),
        if (helperText != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .secondaryContainer
                  .withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .secondary
                    .withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    helperText,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        _buildBrakeSymptomsSection(
          brakeSheet,
          title: title,
          update: update,
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: ValueKey(
            'diag_${prefix}_notes_${currentTab.tabId}_${brakeSheet.notes ?? 'empty'}',
          ),
          initialValue: brakeSheet.notes,
          decoration: InputDecoration(
            labelText: 'Notas freno $title',
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          maxLines: 3,
          onChanged: (value) {
            final normalized = _normalizeNullableText(value);
            update(
              (current) => current.copyWith(
                notes: normalized,
                clearNotes: normalized == null,
              ),
              refresh: false,
            );
          },
        ),
      ],
    );
  }

  Widget _buildBrakeComponentEditor(
    _BikeTabData currentTab, {
    required BrakeDiagnosisSheet brakeSheet,
    required String componentKey,
    required String prefix,
    required String title,
    required _BrakeDiagnosisSheetUpdater update,
  }) {
    switch (componentKey) {
      case 'rotor':
        return _buildRotorThicknessField(
          currentTab,
          brakeSheet: brakeSheet,
          prefix: prefix,
          title: title,
          update: update,
        );
      case 'brake_pad':
      default:
        return _buildBrakePadWearField(
          currentTab,
          brakeSheet: brakeSheet,
          prefix: prefix,
          title: title,
          update: update,
        );
    }
  }

  Widget _buildDiagnosisLinkedBadge(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.link_outlined,
            size: 12,
            color: theme.colorScheme.secondary,
          ),
          const SizedBox(width: 4),
          Text(
            'Servicio guiado',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.secondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrakePadWearField(
    _BikeTabData currentTab, {
    required BrakeDiagnosisSheet brakeSheet,
    required String prefix,
    required String title,
    required _BrakeDiagnosisSheetUpdater update,
  }) {
    final wearValue = brakeSheet.padWearPercent ?? 0;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Desgaste pastillas $title',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildDiagnosisLinkedBadge(theme),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _formatPercentMeasurement(brakeSheet.padWearPercent),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (brakeSheet.padWearPercent != null) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    update((current) =>
                        current.copyWith(clearPadWearPercent: true));
                  },
                  child: const Text('Limpiar'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Usa el slider para dejar un estado rápido de desgaste sin depender de ingreso manual.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Slider(
            key: ValueKey(
              'diag_${prefix}_pad_slider_${currentTab.tabId}_${brakeSheet.padWearPercent?.toString() ?? 'empty'}',
            ),
            value: wearValue.clamp(0, 100),
            min: 0,
            max: 100,
            divisions: 20,
            label: wearValue.toStringAsFixed(0),
            onChanged: (value) {
              update((current) => current.copyWith(padWearPercent: value));
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0%', style: theme.textTheme.bodySmall),
              Text('50%', style: theme.textTheme.bodySmall),
              Text('75%', style: theme.textTheme.bodySmall),
              Text('100%', style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 12),
          _buildDiagnosisSelectField(
            keySuffix:
                'diag_${prefix}_pad_contamination_${currentTab.tabId}_${brakeSheet.padContaminationStatus ?? 'empty'}',
            label: 'Contaminacion pastillas $title',
            icon: Icons.cleaning_services_outlined,
            value: brakeSheet.padContaminationStatus,
            options: kBrakePadContaminationOptions,
            onChanged: (value) {
              update(
                (current) => current.copyWith(
                  padContaminationStatus: value,
                  clearPadContaminationStatus: value == null,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRotorThicknessField(
    _BikeTabData currentTab, {
    required BrakeDiagnosisSheet brakeSheet,
    required String prefix,
    required String title,
    required _BrakeDiagnosisSheetUpdater update,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Grosor rotor $title',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildDiagnosisLinkedBadge(theme),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _formatRotorThickness(brakeSheet.rotorThicknessMm),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey(
              'diag_${prefix}_rotor_${currentTab.tabId}_${brakeSheet.rotorThicknessMm?.toString() ?? 'empty'}',
            ),
            initialValue: brakeSheet.rotorThicknessMm?.toString(),
            decoration: InputDecoration(
              labelText: 'Medicion rotor $title (mm)',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.straighten_outlined),
              suffixIcon: brakeSheet.rotorThicknessMm != null
                  ? IconButton(
                      onPressed: () {
                        update(
                          (current) =>
                              current.copyWith(clearRotorThicknessMm: true),
                        );
                      },
                      icon: const Icon(Icons.close),
                    )
                  : null,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (value) {
              final parsed = _parseNullableDouble(value);
              update(
                (current) => current.copyWith(
                  rotorThicknessMm: parsed,
                  clearRotorThicknessMm: parsed == null,
                ),
                refresh: false,
              );
            },
          ),
          const SizedBox(height: 12),
          _buildDiagnosisSelectField(
            keySuffix:
                'diag_${prefix}_rotor_trueness_${currentTab.tabId}_${brakeSheet.rotorTruenessStatus ?? 'empty'}',
            label: 'Trueness rotor $title',
            icon: Icons.sync_problem_outlined,
            value: brakeSheet.rotorTruenessStatus,
            options: kBrakeRotorTruenessOptions,
            onChanged: (value) {
              update(
                (current) => current.copyWith(
                  rotorTruenessStatus: value,
                  clearRotorTruenessStatus: value == null,
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildDiagnosisSelectField(
            keySuffix:
                'diag_${prefix}_rotor_contamination_${currentTab.tabId}_${brakeSheet.rotorContaminationStatus ?? 'empty'}',
            label: 'Contaminacion rotor $title',
            icon: Icons.cleaning_services_outlined,
            value: brakeSheet.rotorContaminationStatus,
            options: kBrakeRotorContaminationOptions,
            onChanged: (value) {
              update(
                (current) => current.copyWith(
                  rotorContaminationStatus: value,
                  clearRotorContaminationStatus: value == null,
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Referencia rapida: <= 1.7 mm requiere atencion y <= 1.5 mm se considera critico para esta capa de memoria.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrakeSymptomsSection(
    BrakeDiagnosisSheet brakeSheet, {
    required String title,
    required _BrakeDiagnosisSheetUpdater update,
  }) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sintomas freno $title',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _buildDiagnosisLinkedBadge(theme),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Marca solo lo observado en esta visita. Este bloque queda en la verdad de diagnóstico del freno y lo reutiliza el servicio guiado.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          BikeshopMultiSelectPickerField(
            options: _kBrakeSymptomOptions,
            selectedValues: brakeSheet.symptomKeys,
            dialogTitle: 'Sintomas freno $title',
            onChanged: (nextSymptoms) {
              final orderedSymptoms =
                  canonicalizeBrakeSymptomKeys(nextSymptoms);
              update(
                (current) => current.copyWith(
                  symptomKeys: orderedSymptoms,
                  clearSymptomKeys: orderedSymptoms.isEmpty,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BIKE TAB BAR (Multi-bike support) - Browser-style elegant tabs
  // ============================================================
  Widget _buildBikeTabBar(ThemeData theme) {
    // Browser-style tabs that sit on top of the content area
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
        child: Row(
          children: [
            // Existing bike tabs - browser style
            ..._bikeTabs.asMap().entries.map((entry) {
              final index = entry.key;
              final tab = entry.value;
              final isSelected = index == _selectedBikeTabIndex;
              // Hide General tab chip when empty
              if (tab.isGeneralTab && tab.partItems.isEmpty) {
                return const SizedBox.shrink();
              }

              return _BrowserStyleBikeTab(
                label: tab.displayName,
                isSelected: isSelected,
                onTap: () {
                  setState(() {
                    _selectedBikeTabIndex = index;
                    _selectedBike = _bikeTabs[index].bike;
                  });
                  unawaited(_loadSelectedBikeProfile(_selectedBike));
                },
                onClose: _bikeTabs.length > 1
                    ? () => _confirmRemoveBike(index, tab.displayName)
                    : null,
              );
            }),
            // Add new tab button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: IconButton(
                onPressed: _showAddBikeSelector,
                icon: const Icon(Icons.add, size: 18),
                tooltip: 'Agregar bicicleta',
                style: IconButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                  padding: const EdgeInsets.all(8),
                  minimumSize: const Size(32, 32),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CUSTOMER + BIKE SECTION (original design)
  // ============================================================
  Widget _buildCustomerBikeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Customer selector with quick add
        InkWell(
          onTap: widget.jobId != null
              ? null // Disable editing customer in edit mode
              : _showCustomerSelector,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Cliente *',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.person),
              suffixIcon: widget.jobId == null
                  ? const Icon(Icons.arrow_drop_down)
                  : null,
              errorText:
                  _selectedCustomer == null && _formKey.currentState != null
                      ? 'Seleccione un cliente'
                      : null,
            ),
            child: Text(
              _selectedCustomer?.name ?? 'Seleccione un cliente',
              style: _selectedCustomer != null
                  ? null
                  : TextStyle(color: Colors.grey[600]),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Service and warranty are bike-based workflows.
        if (_jobType == JobType.service || _jobType == JobType.warranty) ...[
          // Custom bike dropdown with action buttons
          if (_selectedCustomer != null)
            PopupMenuButton<String>(
              enabled: widget.jobId == null, // Disable in edit mode
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Bicicleta *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.pedal_bike),
                  suffixIcon: Icon(Icons.arrow_drop_down),
                ),
                child: Text(
                  _selectedBike != null
                      ? '${_selectedBike!.displayName}${_selectedBike!.serialNumber != null ? ' (S/N: ${_selectedBike!.serialNumber})' : ''}'
                      : 'Seleccione una bicicleta',
                  style: _selectedBike != null
                      ? null
                      : TextStyle(color: Colors.grey[600]),
                ),
              ),
              itemBuilder: (context) => [
                // Bike list - add to tabs (not just select)
                ..._bikes.map((bike) {
                  final alreadyInTabs =
                      _bikeTabs.any((tab) => tab.bike?.id == bike.id);
                  return PopupMenuItem<String>(
                    value: 'bike_${bike.id}',
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${bike.displayName}${bike.serialNumber != null ? ' (S/N: ${bike.serialNumber})' : ''}',
                          ),
                        ),
                        if (alreadyInTabs)
                          Icon(Icons.check, size: 16, color: Colors.green[600]),
                      ],
                    ),
                    onTap: () {
                      // Use _addBikeTab to properly add to multi-bike system
                      _addBikeTab(bike);
                    },
                  );
                }),
                // Divider
                if (_bikes.isNotEmpty) const PopupMenuDivider(),
                // Nueva Bici button
                PopupMenuItem<String>(
                  value: 'new_bike',
                  child: const Row(
                    children: [
                      Icon(Icons.add, size: 18),
                      SizedBox(width: 8),
                      Text('Nueva bicicleta'),
                    ],
                  ),
                  onTap: () async {
                    // Delay to let menu close
                    final messenger = ScaffoldMessenger.of(context);
                    await Future.delayed(const Duration(milliseconds: 100));
                    if (!mounted) return;

                    final newBike =
                        await _openBikeDialog(selectSavedBike: true);

                    if (!mounted) return;

                    // Add to multi-bike tabs
                    if (newBike != null && mounted) {
                      _addBikeTab(newBike);

                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                              'Bicicleta "${newBike.displayName}" creada y agregada'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                ),
                // Gestionar Bicis button
                if (_bikes.isNotEmpty)
                  PopupMenuItem<String>(
                    value: 'manage_bikes',
                    child: const Row(
                      children: [
                        Icon(Icons.settings, size: 18),
                        SizedBox(width: 8),
                        Text('Gestionar bicicletas'),
                      ],
                    ),
                    onTap: () async {
                      await Future.delayed(const Duration(milliseconds: 100));
                      if (mounted) {
                        _showBikeManagementDialog();
                      }
                    },
                  ),
              ],
            )
          else
            // Show disabled field when no customer selected
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Bicicleta *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.pedal_bike),
                enabled: false,
              ),
              child: Text(
                'Primero seleccione un cliente',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          if (_selectedBike != null && _selectedBike!.isUnderWarranty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[300]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_user, color: Colors.green[700]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Esta bicicleta está bajo garantía hasta ${DateFormat('dd/MM/yyyy').format(_selectedBike!.warrantyUntil!)}',
                      style: TextStyle(color: Colors.green[900]),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_selectedBike != null) _buildBikeProfileSummaryCard(),
        ] else if (_jobType == JobType.itemService) ...[
          _buildSubjectPicker(),
          const SizedBox(height: 12),
          TextFormField(
            controller: _subjectNotesController,
            decoration: const InputDecoration(
              labelText: 'Notas del ítem',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.notes),
              hintText: 'Ej: Rueda trasera 26", número de serie...',
            ),
            maxLines: 2,
          ),
        ] else if (_jobType == JobType.quotation) ...[
          TextFormField(
            controller: _subjectNotesController,
            decoration: const InputDecoration(
              labelText: 'Producto / servicio a cotizar *',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.request_quote_outlined),
              hintText:
                  'Ej: Shimano Deore 12v, bicicleta gravel talla M, servicio de mantención...',
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 8),
          Text(
            'Usa presupuesto para cotizaciones nuevas, incluso si el producto no existe aún en tu inventario.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ],
    );
  }

  Widget _buildGeneralSection(ThemeData theme) {
    // Get current bike tab (if any)
    final currentTab = _currentBikeTab;

    final workRequestedCtrl =
        currentTab?.workRequestedController ?? _workSummaryController;
    final techNotesCtrl =
        currentTab?.technicianNotesController ?? _technicianNotesController;

    // Checkbox states from current tab
    final isWarranty = currentTab?.isWarrantyWork ?? _isWarrantyJob;
    final requiresApproval = currentTab?.requiresApproval ?? _requiresApproval;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ========== JOB TYPE SELECTOR ==========
        if (widget.jobId == null) ...[
          _buildJobTypeSelector(),
          const SizedBox(height: 16),
        ] else ...[
          _buildJobTypeBadge(),
          const SizedBox(height: 16),
        ],

        // ========== WARRANTY TRACEABILITY BANNER ==========
        if (_existingJob?.convertedAt != null &&
            _existingJob?.warrantyOutcome == WarrantyOutcome.notCovered &&
            _jobType == JobType.service) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              border: Border.all(color: Colors.orange.shade200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.history, color: Colors.orange.shade800),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Esta pega de servicio técnico fue generada a partir de una Garantía No Cubierta.',
                    style: TextStyle(color: Colors.orange.shade900),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ========== JOB-LEVEL FIELDS (same for all bikes) ==========
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<JobPriority>(
                initialValue: _selectedPriority,
                decoration: const InputDecoration(
                  labelText: 'Prioridad',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.flag),
                ),
                items: JobPriority.values.map((priority) {
                  return DropdownMenuItem(
                    value: priority,
                    child: Text(priority.displayName),
                  );
                }).toList(),
                onChanged: (priority) {
                  if (priority != null) {
                    setState(() {
                      _selectedPriority = priority;
                    });
                  }
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _customStatuses.isEmpty
                  // Fallback to enum dropdown if no custom statuses
                  ? DropdownButtonFormField<JobStatus>(
                      initialValue: _selectedStatus,
                      decoration: const InputDecoration(
                        labelText: 'Estado',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.swap_horiz),
                      ),
                      items: JobStatus.values.map((status) {
                        return DropdownMenuItem(
                          value: status,
                          child: Text(status.displayName),
                        );
                      }).toList(),
                      onChanged: (status) {
                        if (status != null) {
                          setState(() {
                            _selectedStatus = status;
                          });
                        }
                      },
                    )
                  // Use custom statuses dropdown
                  : DropdownButtonFormField<JobStatusCustom>(
                      initialValue: _selectedCustomStatus,
                      decoration: const InputDecoration(
                        labelText: 'Estado',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.swap_horiz),
                      ),
                      items: _customStatuses.map((status) {
                        return DropdownMenuItem(
                          value: status,
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: status.colorValue,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              Text(status.name),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (status) {
                        if (status != null) {
                          setState(() {
                            _selectedCustomStatus = status;
                            // Also update the enum status for legacy compatibility
                            _selectedStatus =
                                _mapPhaseToJobStatus(status.phase);
                          });
                        }
                      },
                    ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Arrival Date and Deadline Row
        Row(
          children: [
            // Arrival Date (editable)
            Expanded(
              child: InkWell(
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _selectedArrivalDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 30)),
                  );
                  if (date != null) {
                    setState(() {
                      _selectedArrivalDate = date;
                    });
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Fecha de llegada',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.login),
                  ),
                  child: Text(
                    DateFormat('dd/MM/yyyy').format(_selectedArrivalDate),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Deadline
            Expanded(
              child: InkWell(
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _selectedDeadline ??
                        DateTime.now().add(const Duration(days: 7)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) {
                    setState(() {
                      _selectedDeadline = date;
                    });
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Fecha de entrega',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(
                    _selectedDeadline != null
                        ? DateFormat('dd/MM/yyyy').format(_selectedDeadline!)
                        : 'Seleccionar fecha',
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Estimated Duration
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _estimatedDurationController,
                decoration: const InputDecoration(
                  labelText: 'Duración estimada (horas)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.access_time),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
              ),
            ),
          ],
        ),

        // ========== PER-BIKE FIELDS (from current tab) ==========
        if (currentTab == null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.pedal_bike_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Agrega una bicicleta para habilitar la ficha de diagnóstico y el storage model.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else if (currentTab.isGeneralTab) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'La pestaña General / Venta conserva cargos huérfanos o ventas sueltas. El diagnóstico estructurado se registra por bicicleta.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          // Using keys to force widget recreation when tab changes
          const SizedBox(height: 16),
          TextFormField(
            key: ValueKey('clientRequest_${currentTab.tabId}'),
            controller: currentTab.clientRequestController,
            decoration: const InputDecoration(
              labelText: 'Solicitud del cliente',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.comment),
              hintText: 'Ej: Ruidos en la cadena, frenos suaves...',
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: ValueKey('workRequested_${currentTab.tabId}'),
            controller: workRequestedCtrl,
            decoration: const InputDecoration(
              labelText: 'Trabajos a realizar',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.build),
              hintText:
                  'Ej: Cambio de cadena, ajuste de frenos, lubricación...',
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: ValueKey('techNotes_${currentTab.tabId}'),
            controller: techNotesCtrl,
            decoration: const InputDecoration(
              labelText: 'Notas del técnico',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.notes),
              hintText: 'Notas internas...',
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          Row(
            key: ValueKey('checkboxes_${currentTab.tabId}'),
            children: [
              Expanded(
                child: CheckboxListTile(
                  title: const Text('Requiere aprobación del cliente'),
                  value: requiresApproval,
                  onChanged: (value) {
                    setState(() {
                      currentTab.requiresApproval = value ?? false;
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ),
              Expanded(
                child: _jobType == JobType.warranty
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.18),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.verified_user_outlined,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Este ingreso se tratará como garantía de servicio',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : CheckboxListTile(
                        title: const Text('Trabajo de garantía'),
                        value: isWarranty,
                        onChanged: (value) {
                          setState(() {
                            currentTab.isWarrantyWork = value ?? false;
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
              ),
            ],
          ),
          // ========== END PER-BIKE FIELDS ==========
        ],

        // ========== SPECIAL TYPE FIELDS ==========
        // Warranty outcome
        if (_jobType == JobType.warranty) ...[
          const SizedBox(height: 16),
          _buildWarrantySection(),
        ],
        // Quotation status + validity
        if (_jobType == JobType.quotation) ...[
          const SizedBox(height: 16),
          _buildQuotationSection(),
        ],
      ],
    );
  }

  // ============================================================
  // JOB TYPE UI HELPERS
  // ============================================================

  void _selectJobType(JobType type) {
    setState(() {
      _jobType = type;
      _warrantyOutcome = null;
      _quotationStatus = null;
      _quotationValidUntil = null;

      if (type != JobType.service && type != JobType.warranty) {
        for (final tab in _bikeTabs) {
          tab.dispose();
        }
        _bikeTabs.clear();
        _selectedBike = null;
      }

      if (type != JobType.itemService) {
        _selectedSubject = null;
      }

      if (type != JobType.itemService && type != JobType.quotation) {
        _subjectNotesController.clear();
      }

      final isWarrantyType = type == JobType.warranty;
      _isWarrantyJob = isWarrantyType;
      for (final tab in _bikeTabs) {
        tab.isWarrantyWork = isWarrantyType;
      }
    });
  }

  Widget _buildJobTypeSelector() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tipo de Trabajo',
          style: theme.textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: JobType.values.map((type) {
            final isSelected = _jobType == type;
            final textColor = isSelected
                ? colorScheme.onPrimary
                : colorScheme.onSurfaceVariant;
            final bgColor =
                isSelected ? colorScheme.primary : colorScheme.surface;
            final borderColor =
                isSelected ? colorScheme.primary : colorScheme.outlineVariant;

            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _selectJobType(type),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: borderColor,
                      width: 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                                color:
                                    colorScheme.primary.withValues(alpha: 0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2))
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _jobTypeIcon(type),
                        size: 16,
                        color: textColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        type.displayName,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: textColor,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildJobTypeBadge() {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(_jobTypeIcon(_jobType),
            size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          _jobType.displayName,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  IconData _jobTypeIcon(JobType type) {
    switch (type) {
      case JobType.service:
        return Icons.pedal_bike_outlined;
      case JobType.warranty:
        return Icons.verified_user_outlined;
      case JobType.quotation:
        return Icons.request_quote_outlined;
      case JobType.itemService:
        return Icons.build_circle_outlined;
    }
  }

  IconData _getIconDataFromString(String iconName) {
    switch (iconName) {
      case 'build':
        return Icons.build;
      case 'tire_repair':
        return Icons.tire_repair;
      case 'circle':
        return Icons.circle;
      case 'radio_button_unchecked':
        return Icons.radio_button_unchecked;
      case 'settings':
        return Icons.settings;
      case 'link':
        return Icons.link;
      case 'swap_horiz':
        return Icons.swap_horiz;
      case 'stop_circle':
        return Icons.stop_circle;
      case 'pan_tool':
        return Icons.pan_tool;
      case 'cable':
        return Icons.cable;
      case 'arrow_upward':
        return Icons.arrow_upward;
      case 'compress':
        return Icons.compress;
      case 'accessible':
        return Icons.accessible;
      case 'shopping_cart':
        return Icons.shopping_cart;
      case 'directions_walk':
        return Icons.directions_walk;
      case 'horizontal_rule':
        return Icons.horizontal_rule;
      case 'extension':
        return Icons.extension;
      case 'airline_seat_recline_normal':
        return Icons.airline_seat_recline_normal;
      case 'sports':
        return Icons.sports;
      case 'rectangle':
        return Icons.rectangle;
      default:
        return Icons.build_circle_outlined;
    }
  }

  Widget _buildSubjectPicker() {
    return InkWell(
      onTap: widget.jobId == null ? _showSubjectSearchPicker : null,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Ítem / Componente *',
          border: const OutlineInputBorder(),
          prefixIcon: Icon(_jobTypeIcon(_jobType)),
          suffixIcon: widget.jobId == null ? const Icon(Icons.search) : null,
          helperText: 'Busca en tu catálogo de componentes personalizados.',
        ),
        child: Text(
          _selectedSubject?.name ?? 'Buscar componente...',
          style: _selectedSubject != null
              ? null
              : TextStyle(color: Colors.grey[600]),
        ),
      ),
    );
  }

  Future<void> _showSubjectSearchPicker() async {
    final result = await showDialog<JobSubject>(
      context: context,
      builder: (context) {
        String search = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = _availableSubjects.where((subject) {
              final term = search.toLowerCase();
              return term.isEmpty ||
                  subject.name.toLowerCase().contains(term) ||
                  subject.category.toLowerCase().contains(term) ||
                  (subject.description?.toLowerCase().contains(term) ?? false);
            }).toList()
              ..sort((a, b) {
                final categoryCompare = a.category.compareTo(b.category);
                if (categoryCompare != 0) return categoryCompare;
                return a.sortOrder.compareTo(b.sortOrder);
              });

            String? lastCategory;

            return Dialog(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 560, maxHeight: 620),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Seleccionar componente',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        autofocus: true,
                        onChanged: (value) =>
                            setModalState(() => search = value),
                        decoration: const InputDecoration(
                          hintText: 'Buscar por nombre o categoría...',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Text(
                                  'No se encontraron componentes',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: Colors.grey[600]),
                                ),
                              )
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  final subject = filtered[index];
                                  final showHeader =
                                      lastCategory != subject.category;
                                  lastCategory = subject.category;

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (showHeader) ...[
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              top: 10, bottom: 6),
                                          child: Text(
                                            subject.category.toUpperCase(),
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                  letterSpacing: 0.6,
                                                ),
                                          ),
                                        ),
                                      ],
                                      ListTile(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        leading: CircleAvatar(
                                          radius: 16,
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest,
                                          foregroundColor: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                          child: Icon(
                                            _getIconDataFromString(
                                                subject.icon),
                                            size: 16,
                                          ),
                                        ),
                                        title: Text(subject.name),
                                        subtitle:
                                            subject.description?.isNotEmpty ==
                                                    true
                                                ? Text(subject.description!)
                                                : null,
                                        onTap: () =>
                                            Navigator.of(context).pop(subject),
                                      ),
                                    ],
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (result != null && mounted) {
      setState(() => _selectedSubject = result);
    }
  }

  Widget _buildWarrantySection() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Resultado de Garantía',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<WarrantyOutcome>(
          initialValue: _warrantyOutcome,
          decoration: const InputDecoration(
            labelText: 'Estado de garantía',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.verified_user_outlined),
          ),
          items: [
            const DropdownMenuItem(
              value: null,
              child: Text('Pendiente evaluación'),
            ),
            ...WarrantyOutcome.values.map((o) => DropdownMenuItem(
                  value: o,
                  child: Text(o.displayName),
                )),
          ],
          onChanged: (v) => setState(() => _warrantyOutcome = v),
        ),
      ],
    );
  }

  Widget _buildQuotationSection() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Estado del Presupuesto',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<QuotationStatus>(
                initialValue: _quotationStatus,
                decoration: const InputDecoration(
                  labelText: 'Estado',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.request_quote_outlined),
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Pendiente'),
                  ),
                  ...QuotationStatus.values.map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(s.displayName),
                      )),
                ],
                onChanged: (v) => setState(() => _quotationStatus = v),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: InkWell(
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _quotationValidUntil ??
                        DateTime.now().add(const Duration(days: 30)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) {
                    setState(() => _quotationValidUntil = date);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Válido hasta',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.event_outlined),
                  ),
                  child: Text(
                    _quotationValidUntil != null
                        ? DateFormat('dd/MM/yyyy').format(_quotationValidUntil!)
                        : 'Sin fecha límite',
                    style: _quotationValidUntil != null
                        ? null
                        : TextStyle(color: Colors.grey[600]),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPartsSection() {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Always use table layout with scroll
        const minTableWidth = 800.0;
        final tableWidth = constraints.maxWidth > minTableWidth
            ? constraints.maxWidth
            : minTableWidth;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Table header
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(8)),
                    ),
                    child: Row(
                      children: [
                        // # column
                        Container(
                          width: _colIndexWidth,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(
                                  color: theme.colorScheme.outline
                                      .withValues(alpha: 0.2)),
                            ),
                          ),
                          child: Center(
                            child: Text('#',
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                          ),
                        ),

                        // Repuesto column (flex)
                        Expanded(
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 250),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                right: BorderSide(
                                    color: theme.colorScheme.outline
                                        .withValues(alpha: 0.2)),
                              ),
                            ),
                            child: Text(
                              'PRODUCTO / SERVICIO',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),

                        // Cantidad column
                        Container(
                          width: _colQuantityWidth,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(
                                  color: theme.colorScheme.outline
                                      .withValues(alpha: 0.2)),
                            ),
                          ),
                          child: Center(
                            child: Text('CANTIDAD',
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                          ),
                        ),

                        // Precio column
                        Container(
                          width: _colPriceWidth,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(
                                  color: theme.colorScheme.outline
                                      .withValues(alpha: 0.2)),
                            ),
                          ),
                          child: Center(
                            child: Text('PRECIO UNIT.',
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                          ),
                        ),

                        // Total column
                        Container(
                          width: _colTotalWidth,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Text('TOTAL',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              textAlign: TextAlign.right),
                        ),

                        // Actions column
                        const SizedBox(width: _colActionsWidth),
                      ],
                    ),
                  ),

                  // Header/Content divider
                  Divider(
                      height: 1,
                      thickness: 1,
                      color: theme.colorScheme.outline.withValues(alpha: 0.2)),

                  // Part items, labor items, and add row
                  Column(
                    children: [
                      // Existing part items (from current bike tab or legacy)
                      if (_currentPartItems.isNotEmpty)
                        ..._currentPartItems.asMap().entries.map((entry) =>
                            _buildPartRow(
                                theme, entry.key + 1, entry.value, entry.key)),

                      // Existing service items (displayed after parts)
                      if (_serviceItems.isNotEmpty)
                        ..._serviceItems.asMap().entries.map((entry) =>
                            _buildServiceRow(
                                theme,
                                _currentPartItems.length + entry.key + 1,
                                entry.value,
                                entry.key)),

                      // Add new part row (always show)
                      Container(
                        decoration: BoxDecoration(
                          border: Border(
                            top: _currentPartItems.isNotEmpty
                                ? BorderSide(
                                    color: theme.colorScheme.outline
                                        .withValues(alpha: 0.2))
                                : BorderSide.none,
                          ),
                        ),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Empty # column
                              Container(
                                width: _colIndexWidth,
                                decoration: BoxDecoration(
                                  border: Border(
                                    right: BorderSide(
                                        color: theme.colorScheme.outline
                                            .withValues(alpha: 0.2)),
                                  ),
                                ),
                              ),

                              // Product autocomplete field
                              Expanded(
                                child: Container(
                                  constraints:
                                      const BoxConstraints(minWidth: 250),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      right: BorderSide(
                                          color: theme.colorScheme.outline
                                              .withValues(alpha: 0.2)),
                                    ),
                                  ),
                                  child: ProductAutocompleteField(
                                    key: ValueKey(_partAutocompleteKey),
                                    focusNode: _partAutocompleteFocus,
                                    onProductSelected: (selection) {
                                      if (selection.isCatalogProduct &&
                                          selection.product != null) {
                                        _addCatalogPart(selection.product!);
                                      } else if (!selection.isCatalogProduct) {
                                        _addCustomPart(selection.displayText);
                                      }
                                    },
                                    allowCustomItems: true,
                                    labelText: 'Agregar repuesto o parte',
                                    hintText:
                                        'Buscar en catálogo o escribir personalizado...',
                                  ),
                                ),
                              ),

                              // Empty columns for alignment
                              Container(
                                width: _colQuantityWidth,
                                decoration: BoxDecoration(
                                  border: Border(
                                    right: BorderSide(
                                        color: theme.colorScheme.outline
                                            .withValues(alpha: 0.2)),
                                  ),
                                ),
                              ),
                              Container(
                                width: _colPriceWidth,
                                decoration: BoxDecoration(
                                  border: Border(
                                    right: BorderSide(
                                        color: theme.colorScheme.outline
                                            .withValues(alpha: 0.2)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: _colTotalWidth),
                              const SizedBox(width: _colActionsWidth),
                            ],
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
      },
    );
  }

  Widget _buildPartRow(
      ThemeData theme, int index, _JobPartItem item, int itemIndex) {
    return _PartItemRow(
      key: ValueKey('part_${item.id}'),
      item: item,
      index: index,
      itemIndex: itemIndex,
      isFirst: itemIndex == 0,
      isLast: itemIndex == _currentPartItems.length - 1,
      indexWidth: _colIndexWidth,
      quantityWidth: _colQuantityWidth,
      priceWidth: _colPriceWidth,
      totalWidth: _colTotalWidth,
      actionsWidth: _colActionsWidth,
      onChanged: (newItem) {
        setState(() {
          _currentPartItems[itemIndex] = newItem;
        });
      },
      onRemove: () => setState(() => _currentPartItems.removeAt(itemIndex)),
      onMoveUp: () {
        if (itemIndex > 0) {
          setState(() {
            final temp = _currentPartItems[itemIndex];
            _currentPartItems[itemIndex] = _currentPartItems[itemIndex - 1];
            _currentPartItems[itemIndex - 1] = temp;
          });
        }
      },
      onMoveDown: () {
        if (itemIndex < _currentPartItems.length - 1) {
          setState(() {
            final temp = _currentPartItems[itemIndex];
            _currentPartItems[itemIndex] = _currentPartItems[itemIndex + 1];
            _currentPartItems[itemIndex + 1] = temp;
          });
        }
      },
      onEditWizard: item.isServiceItem && item.product != null
          ? () => _editServiceWizard(itemIndex)
          : null,
      onTap: () {
        if (item.hasWizardAnswers) {
          setState(() => _selectedServiceIndex = itemIndex);
        }
      },
    );
  }

  /// Re-open the service wizard for an existing service line with pre-filled answers
  Future<void> _editServiceWizard(int itemIndex) async {
    final item = _currentPartItems[itemIndex];
    if (item.product == null) return;

    // Use cached profile, or re-fetch if missing
    ServiceWizardProfile? profile = item.wizardProfile;
    profile ??= await _serviceWizardService
        .getProfileForProduct(item.product!.id)
        .catchError((_) => null);
    profile = ServiceWizardService.normalizeProfile(profile);

    if (!mounted) return;

    final wizardDialogConfig = _buildServiceWizardDialogConfig(profile, item);

    final result = await showServiceWizardDialog(
      context,
      productName: item.product!.name,
      productIsService: true,
      profile: profile,
      initialAnswers: wizardDialogConfig.initialAnswers,
      contextSummary: wizardDialogConfig.contextSummary,
      helperText: wizardDialogConfig.helperText,
      hiddenQuestionKeys: wizardDialogConfig.hiddenQuestionKeys,
      questionOverrides: wizardDialogConfig.questionOverrides,
      diagnosisLinkedQuestionKeys:
          wizardDialogConfig.diagnosisLinkedQuestionKeys,
    );

    if (result != null && mounted) {
      final normalizedAnswers = ServiceWizardService.normalizeAnswersForProfile(
          profile, result.answers);
      final normalizedLocation =
          _resolveWizardLocation(item.location, normalizedAnswers);
      final persistedSummary = _buildPersistedWizardSummary(
        profile,
        normalizedAnswers,
        result.summary,
        hiddenQuestionKeys: wizardDialogConfig.hiddenQuestionKeys,
      );
      final updatedItem = item.copyWith(
        notes: persistedSummary,
        wizardAnswers: normalizedAnswers.isNotEmpty ? normalizedAnswers : null,
        wizardProfile: profile,
        location: normalizedLocation,
      );
      final syncFeedback = _serviceWizardSyncFeedback(
        profile,
        updatedItem,
        normalizedAnswers,
      );

      setState(() {
        _currentPartItems[itemIndex] = updatedItem;
        _applyWizardAnswersToDiagnosis(
          item: updatedItem,
          profile: profile,
          answers: normalizedAnswers,
        );
        _selectedServiceIndex = itemIndex;
      });

      if (syncFeedback != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(syncFeedback)),
        );
      }
    }
  }

  Widget _buildLaborSection() {
    final theme = Theme.of(context);

    // If on mobile, show mobile layout (cards)
    // We can detect mobile by screen width context
    final isMobile = MediaQuery.of(context).size.width < 800;

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mano de Obra',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_serviceItems.isNotEmpty)
            ..._serviceItems.asMap().entries.map((entry) =>
                _buildMobileServiceRow(
                    theme, entry.key + 1, entry.value, entry.key)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _addServiceItem,
              icon: const Icon(Icons.add),
              label: const Text('Agregar Mano de Obra'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                alignment: Alignment.centerLeft,
              ),
            ),
          ),
        ],
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mano de Obra',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Responsive grid table (same as parts)
            LayoutBuilder(
              builder: (context, constraints) {
                const minTableWidth = 900.0;
                final tableWidth = constraints.maxWidth > minTableWidth
                    ? constraints.maxWidth
                    : minTableWidth;

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableWidth,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: theme.colorScheme.outline
                                .withValues(alpha: 0.2)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Table header
                          Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.3),
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(8)),
                            ),
                            child: Row(
                              children: [
                                // # column
                                Container(
                                  width: _colIndexWidth,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      right: BorderSide(
                                          color: theme.colorScheme.outline
                                              .withValues(alpha: 0.2)),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text('#',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.w600)),
                                  ),
                                ),

                                // Descripción column (flex)
                                Expanded(
                                  child: Container(
                                    constraints:
                                        const BoxConstraints(minWidth: 250),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        right: BorderSide(
                                            color: theme.colorScheme.outline
                                                .withValues(alpha: 0.2)),
                                      ),
                                    ),
                                    child: Text(
                                      'DESCRIPCIÓN',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ),

                                // Fecha column
                                Container(
                                  width: _colDateWidth,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      right: BorderSide(
                                          color: theme.colorScheme.outline
                                              .withValues(alpha: 0.2)),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text('FECHA',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.w600)),
                                  ),
                                ),

                                // Horas column
                                Container(
                                  width: _colHoursWidth,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      right: BorderSide(
                                          color: theme.colorScheme.outline
                                              .withValues(alpha: 0.2)),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text('HORAS',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.w600)),
                                  ),
                                ),

                                // Tarifa column
                                Container(
                                  width: _colRateWidth,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      right: BorderSide(
                                          color: theme.colorScheme.outline
                                              .withValues(alpha: 0.2)),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text('TARIFA/H',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.w600)),
                                  ),
                                ),

                                // Total column
                                Container(
                                  width: _colTotalWidth,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  child: Text('TOTAL',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600),
                                      textAlign: TextAlign.right),
                                ),

                                // Actions column
                                const SizedBox(width: _colActionsWidth),
                              ],
                            ),
                          ),

                          // Header/Content divider
                          Divider(
                              height: 1,
                              thickness: 1,
                              color: theme.colorScheme.outline
                                  .withValues(alpha: 0.2)),

                          // Labor items
                          Column(
                            children: [
                              // Existing labor items
                              if (_serviceItems.isNotEmpty)
                                ..._serviceItems.asMap().entries.map((entry) =>
                                    _buildServiceRow(theme, entry.key + 1,
                                        entry.value, entry.key)),

                              // Add labor button row (always show)
                              Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: _serviceItems.isNotEmpty
                                        ? BorderSide(
                                            color: theme.colorScheme.outline
                                                .withValues(alpha: 0.2))
                                        : BorderSide.none,
                                  ),
                                ),
                                child: IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      // Empty # column
                                      Container(
                                        width: _colIndexWidth,
                                        decoration: BoxDecoration(
                                          border: Border(
                                            right: BorderSide(
                                                color: theme.colorScheme.outline
                                                    .withValues(alpha: 0.2)),
                                          ),
                                        ),
                                      ),

                                      // Add labor button spanning remaining columns
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          child: FilledButton.icon(
                                            onPressed: _addServiceItem,
                                            icon:
                                                const Icon(Icons.add, size: 18),
                                            label: const Text(
                                                'Agregar Mano de Obra'),
                                            style: FilledButton.styleFrom(
                                              alignment: Alignment.centerLeft,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
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
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a service/labor row using the universal LineRowWrapper.
  /// Provides hover-based reorder arrows and consistent styling.
  Widget _buildMobileServiceRow(
      ThemeData theme, int index, _JobServiceItem item, int itemIndex) {
    return const SizedBox.shrink();
  }

  Widget _buildServiceRow(
      ThemeData theme, int index, _JobServiceItem item, int itemIndex) {
    return LineRowWrapper(
      key: ValueKey('service_${item.hashCode}_$index'),
      index: index,
      canMoveUp: itemIndex > 0,
      canMoveDown: itemIndex < _serviceItems.length - 1,
      onMoveUp: () {
        if (itemIndex > 0) {
          setState(() {
            final temp = _serviceItems[itemIndex];
            _serviceItems[itemIndex] = _serviceItems[itemIndex - 1];
            _serviceItems[itemIndex - 1] = temp;
          });
        }
      },
      onMoveDown: () {
        if (itemIndex < _serviceItems.length - 1) {
          setState(() {
            final temp = _serviceItems[itemIndex];
            _serviceItems[itemIndex] = _serviceItems[itemIndex + 1];
            _serviceItems[itemIndex + 1] = temp;
          });
        }
      },
      onRemove: () => setState(() => _serviceItems.removeAt(itemIndex)),
      canEdit: true,
      indexColumnWidth: _colIndexWidth,
      actionsColumnWidth: _colActionsWidth,
      columns: [
        // Description column
        LineColumn(
          expanded: true,
          minWidth: 250,
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Service icon/image
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: item.serviceProduct?.imageUrl != null
                      ? Image.network(
                          item.serviceProduct!.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.work_outline,
                            color: Colors.blue,
                            size: 24,
                          ),
                        )
                      : const Icon(
                          Icons.work_outline,
                          color: Colors.blue,
                          size: 24,
                        ),
                ),
              ),

              const SizedBox(width: 12),

              // Service name + description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.displayName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    // Custom description only
                    if (item.hasCustomDescription)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          item.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Quantity column (represents hours for services)
        LineColumn(
          width: _colQuantityWidth,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Center(
            child: Text(
              item.hours % 1 == 0
                  ? item.hours.toStringAsFixed(0)
                  : item.hours.toStringAsFixed(2),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),

        // Unit Price column - EDITABLE
        LineColumn(
          width: _colPriceWidth,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: TextFormField(
            initialValue: item.hourlyRate.toStringAsFixed(0),
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3)),
              ),
              prefixText: '\$ ',
              prefixStyle: theme.textTheme.bodyMedium,
            ),
            onChanged: (value) {
              final newPrice = double.tryParse(value) ?? 0;
              setState(() {
                _serviceItems[itemIndex] = _JobServiceItem(
                  serviceProduct: item.serviceProduct,
                  description: item.description,
                  hours: item.hours,
                  hourlyRate: newPrice,
                  date: item.date,
                );
              });
            },
          ),
        ),

        // Total column (no right border - last content column)
        LineColumn(
          width: _colTotalWidth,
          showRightBorder: false,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            NumberFormat.currency(symbol: '\$', decimalDigits: 0)
                .format(item.total),
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildCostSummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCostRow('Subtotal:', _subtotal, true),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Descuento:', style: TextStyle(fontSize: 16)),
            SizedBox(
              width: 150,
              child: TextFormField(
                controller: _discountController,
                decoration: const InputDecoration(
                  prefixText: '\$ ',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(thickness: 2),
        _buildCostRow('TOTAL:', _total, true, fontSize: 20),
      ],
    );
  }

  Widget _buildCostRow(String label, double amount, bool bold,
      {double fontSize = 16}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(amount),
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: bold ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
      ],
    );
  }

  /// The currently selected service item (for sidebar detail)
  _JobPartItem? get _selectedServiceItem {
    if (_selectedServiceIndex == null) return null;
    if (_selectedServiceIndex! < 0 ||
        _selectedServiceIndex! >= _currentPartItems.length) {
      return null;
    }
    final item = _currentPartItems[_selectedServiceIndex!];
    return item.hasWizardAnswers ? item : null;
  }

  Widget _buildServiceDetailsPanel() {
    final theme = Theme.of(context);
    final item = _selectedServiceItem;
    if (item == null) return const SizedBox.shrink();
    return _buildServiceDetailCard(theme, item);
  }

  Widget _buildServiceDetailCard(ThemeData theme, _JobPartItem item) {
    final profile = ServiceWizardService.normalizeProfile(item.wizardProfile);
    final answers = ServiceWizardService.normalizeAnswersForProfile(
      profile,
      Map<String, dynamic>.from(
          item.wizardAnswers ?? const <String, dynamic>{}),
    );
    final questions = profile?.questions ?? [];
    final itemIndex = _currentPartItems.indexOf(item);

    // Build answer key→value pairs
    final answerPairs = <MapEntry<String, String>>[];
    for (final q in questions) {
      final val = answers[q.key];
      if (val == null || val.toString().isEmpty) continue;
      if (q.key == '_notes') continue;

      String displayValue;
      if (val is bool) {
        displayValue = val ? 'Sí' : 'No';
      } else if (val is List) {
        if (val.isEmpty) continue;
        displayValue = val.map((v) {
          return ServiceWizardService.resolveLabel(q, v.toString());
        }).join(', ');
      } else {
        displayValue = ServiceWizardService.resolveLabel(q, val.toString());
      }
      answerPairs.add(MapEntry(q.label, displayValue));
    }

    final notes = answers['_notes'] as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header: service name + edit button
        Row(
          children: [
            Icon(
              Icons.build_circle,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.displayName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (itemIndex >= 0)
              Tooltip(
                message: 'Editar configuración',
                child: InkWell(
                  onTap: () => _editServiceWizard(itemIndex),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.edit_outlined,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
          ],
        ),

        // Answer details
        if (answerPairs.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: answerPairs.map((pair) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(
                          pair.key,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          pair.value,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],

        // Notes
        if (notes != null && notes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.sticky_note_2_outlined,
                size: 13,
                color: theme.colorScheme.tertiary.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  notes,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildInvoiceSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green[50],
        border: Border.all(color: Colors.green[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt, color: Colors.green[700]),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Factura: ${_linkedInvoiceNumber ?? _existingJob?.invoiceId ?? "N/A"}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.green[900],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Estado: Factura creada automáticamente con los repuestos y servicios de esta pega',
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () {
              if (_existingJob?.invoiceId != null) {
                // Pass extra param to indicate we came from a job, so back button works nicely
                context.push(
                    '/sales/invoices/${_existingJob!.invoiceId}/edit?referrer=job&jobId=${_existingJob!.id}');
              }
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Ver Factura'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
            ),
          ),
        ],
      ),
    );
  }
}

// Helper classes for form items

class _PartItemRow extends StatefulWidget {
  final _JobPartItem item;
  final int index;
  final int itemIndex;
  final bool isFirst;
  final bool isLast;
  final ValueChanged<_JobPartItem> onChanged;
  final VoidCallback onRemove;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback? onEditWizard;
  final VoidCallback? onTap;
  final double indexWidth;
  final double quantityWidth;
  final double priceWidth;
  final double totalWidth;
  final double actionsWidth;

  const _PartItemRow({
    super.key,
    required this.item,
    required this.index,
    required this.itemIndex,
    required this.isFirst,
    required this.isLast,
    required this.onChanged,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
    this.onEditWizard,
    this.onTap,
    required this.indexWidth,
    required this.quantityWidth,
    required this.priceWidth,
    required this.totalWidth,
    required this.actionsWidth,
  });

  @override
  State<_PartItemRow> createState() => _PartItemRowState();
}

class _PartItemRowState extends State<_PartItemRow> {
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.item.displayName);
  }

  @override
  void didUpdateWidget(_PartItemRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item.product != oldWidget.item.product ||
        (widget.item.product == null &&
            widget.item.name != oldWidget.item.name &&
            widget.item.name != _nameController.text)) {
      _nameController.text = widget.item.displayName;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.translucent,
      child: LineRowWrapper(
        index: widget.index,
        canMoveUp: !widget.isFirst,
        canMoveDown: !widget.isLast,
        onMoveUp: widget.onMoveUp,
        onMoveDown: widget.onMoveDown,
        onRemove: widget.onRemove,
        canEdit: true,
        indexColumnWidth: widget.indexWidth,
        actionsColumnWidth: widget.actionsWidth,
        showDeleteButton: true,
        columns: [
          // Product Autocomplete Column
          LineColumn(
            expanded: true,
            minWidth: 250,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.isServiceItem) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _ServiceLineBadge(item: item),
                      if (widget.onEditWizard != null)
                        TextButton.icon(
                          onPressed: widget.onEditWizard,
                          icon: Icon(
                            item.hasWizardAnswers
                                ? Icons.edit_outlined
                                : Icons.tune,
                            size: 16,
                          ),
                          label: Text(
                            item.hasWizardAnswers
                                ? 'Editar servicio'
                                : 'Configurar',
                          ),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                SmartProductField(
                  initialData: ProductFieldData(
                    product: item.product,
                    productName: item.displayName,
                    productSku: item.product?.sku,
                    isCatalogProduct: item.isCatalogProduct,
                    description: item.hasWizardAnswers ? null : item.notes,
                  ),
                  hintText: 'Buscar por nombre...',
                  allowCustomItems: true,
                  showCost:
                      false, // Job form usually shows price to customer, not cost
                  onProductChanged: (selection) {
                    if (selection == null) {
                      // Clear product
                      widget.onChanged(item.copyWith(
                        clearProduct: true,
                        clearWizard: true,
                        name: '',
                        isCatalogProduct: true,
                        isServiceItem: false,
                        location: BikeMemoryLocation.none,
                        notes: '',
                      ));
                    } else if (selection.isCatalogProduct &&
                        selection.product != null) {
                      final isSameProduct =
                          item.product?.id == selection.product!.id;
                      final isServiceItem = selection.product!.isService;

                      // Catalog product
                      widget.onChanged(item.copyWith(
                        product: selection.product,
                        name: selection.productName ?? '',
                        isCatalogProduct: true,
                        isServiceItem: isServiceItem,
                        // Only update price if it's a new selection, not a desc update
                        unitPrice: selection.price > 0
                            ? selection.price
                            : item.unitPrice,
                        notes: selection.description ?? '',
                        clearWizard: !isSameProduct,
                        location: isServiceItem && isSameProduct
                            ? item.location
                            : BikeMemoryLocation.none,
                      ));
                    } else {
                      // Ad-hoc item
                      widget.onChanged(item.copyWith(
                        clearProduct: true,
                        clearWizard: true,
                        name: selection.productName ?? '',
                        isCatalogProduct: false,
                        isServiceItem: false,
                        unitPrice: item.unitPrice,
                        location: BikeMemoryLocation.none,
                        notes: selection.description ?? '',
                      ));
                    }
                  },
                ),
                if (item.isServiceItem) ...[
                  const SizedBox(height: 8),
                  _ServiceLocationSelector(
                    value: item.location,
                    onChanged: (location) {
                      widget.onChanged(item.copyWith(location: location));
                    },
                  ),
                ],
              ],
            ),
          ),

          // Quantity Column
          LineColumn(
            width: widget.quantityWidth,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Center(
              child: TextFormField(
                initialValue: item.quantity.toString(),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(),
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (value) {
                  final newQty = int.tryParse(value) ?? 1;
                  widget.onChanged(item.copyWith(quantity: newQty));
                },
              ),
            ),
          ),

          // Price Column
          LineColumn(
            width: widget.priceWidth,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: TextFormField(
              initialValue: item.unitPrice.toStringAsFixed(0),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(),
                prefixText: '\$ ',
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              onChanged: (value) {
                final newPrice = double.tryParse(value) ?? 0;
                widget.onChanged(item.copyWith(unitPrice: newPrice));
              },
            ),
          ),

          // Total Column
          LineColumn(
            width: widget.totalWidth,
            showRightBorder: false,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              NumberFormat.currency(symbol: '\$', decimalDigits: 0)
                  .format(item.quantity * item.unitPrice),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _JobPartItem {
  final String id; // Unique stable ID for widget keys
  Product? product; // Nullable for ad-hoc items
  String name; // For ad-hoc items
  bool isCatalogProduct;
  bool isServiceItem;
  int quantity;
  double unitPrice;
  BikeMemoryLocation location;
  String? notes;

  /// Answers captured from the service wizard (only for service products)
  Map<String, dynamic>? wizardAnswers;

  /// Cached wizard profile for re-editing without re-fetching from DB
  ServiceWizardProfile? wizardProfile;

  _JobPartItem({
    String? id,
    this.product,
    required this.name,
    this.isCatalogProduct = true,
    this.isServiceItem = false,
    required this.quantity,
    required this.unitPrice,
    this.location = BikeMemoryLocation.none,
    this.notes,
    this.wizardAnswers,
    this.wizardProfile,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  String get displayName => product?.name ?? name;
  String? get sku => product?.sku;
  bool get hasWizardAnswers =>
      wizardAnswers != null && wizardAnswers!.isNotEmpty;

  /// Create a copy with the same ID (for preserving widget keys)
  _JobPartItem copyWith({
    Product? product,
    String? name,
    bool? isCatalogProduct,
    bool? isServiceItem,
    int? quantity,
    double? unitPrice,
    BikeMemoryLocation? location,
    String? notes,
    Map<String, dynamic>? wizardAnswers,
    ServiceWizardProfile? wizardProfile,
    bool clearProduct = false,
    bool clearWizard = false,
  }) {
    return _JobPartItem(
      id: id, // Keep same ID!
      product: clearProduct ? null : (product ?? this.product),
      name: name ?? this.name,
      isCatalogProduct: isCatalogProduct ?? this.isCatalogProduct,
      isServiceItem: isServiceItem ?? this.isServiceItem,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      location: location ?? this.location,
      notes: notes ?? this.notes,
      wizardAnswers: clearWizard ? null : (wizardAnswers ?? this.wizardAnswers),
      wizardProfile: clearWizard ? null : (wizardProfile ?? this.wizardProfile),
    );
  }
}

/// Badge shown at the top of a service line item row.
class _ServiceLineBadge extends StatelessWidget {
  final _JobPartItem item;
  const _ServiceLineBadge({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAnswers = item.hasWizardAnswers;
    final color =
        hasAnswers ? theme.colorScheme.primary : theme.colorScheme.secondary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasAnswers ? Icons.build_circle : Icons.build_circle_outlined,
                size: 11,
                color: color,
              ),
              const SizedBox(width: 4),
              Text(
                hasAnswers ? 'Servicio configurado' : 'Servicio',
                style: TextStyle(
                  fontSize: 10.5,
                  color: color,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ServiceLocationSelector extends StatelessWidget {
  final BikeMemoryLocation value;
  final ValueChanged<BikeMemoryLocation> onChanged;

  const _ServiceLocationSelector({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget buildChip(BikeMemoryLocation location, String label) {
      final isSelected = value == location;
      return ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) {
          if (!isSelected) {
            onChanged(location);
          }
        },
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        labelStyle: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: isSelected
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSurface,
        ),
        side: BorderSide(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.4)
              : theme.colorScheme.outline.withValues(alpha: 0.35),
        ),
        backgroundColor: theme.colorScheme.surface,
        selectedColor: theme.colorScheme.primaryContainer,
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Aplica a',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        buildChip(BikeMemoryLocation.none, 'Auto'),
        buildChip(BikeMemoryLocation.front, 'Del.'),
        buildChip(BikeMemoryLocation.rear, 'Tras.'),
      ],
    );
  }
}

class _JobServiceItem {
  final Product? serviceProduct;
  final String description;
  final double hours;
  final double hourlyRate;
  final DateTime date;

  _JobServiceItem({
    this.serviceProduct,
    required this.description,
    required this.hours,
    required this.hourlyRate,
    required this.date,
  });

  String get displayName => serviceProduct?.name ?? description;

  bool get hasCustomDescription =>
      serviceProduct != null &&
      description.isNotEmpty &&
      description != serviceProduct!.name;

  double get total => hours * hourlyRate;
}

// Modern part item dialog with ProductAutocompleteField
class _PartItemDialog extends StatefulWidget {
  final Function(
          ProductSelection selection, int quantity, double price, String? notes)
      onItemAdded;

  const _PartItemDialog({
    required this.onItemAdded,
  });

  @override
  State<_PartItemDialog> createState() => _PartItemDialogState();
}

class _PartItemDialogState extends State<_PartItemDialog> {
  ProductSelection? _selection;
  final _quantityController = TextEditingController(text: '1');
  final _priceController = TextEditingController();
  final _notesController = TextEditingController();
  final _productTextController = TextEditingController();

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    _notesController.dispose();
    _productTextController.dispose();
    super.dispose();
  }

  @override
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return AlertDialog(
      insetPadding: isMobile
          ? const EdgeInsets.all(16)
          : const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0),
      title: const Text('Agregar Repuesto o Parte'),
      content: SizedBox(
        width: isMobile ? double.maxFinite : 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Product autocomplete field
            ProductAutocompleteField(
              controller: _productTextController,
              onProductSelected: (selection) {
                setState(() {
                  _selection = selection;
                  if (selection.isCatalogProduct && selection.product != null) {
                    _priceController.text = selection.product!.price.toString();
                  } else if (!selection.isCatalogProduct) {
                    // For ad-hoc items, set a default price if empty
                    if (_priceController.text.isEmpty) {
                      _priceController.text = '0';
                    }
                  }
                });
              },
              allowCustomItems: true,
              labelText: 'Repuesto o Parte',
              hintText: 'Buscar en catálogo o escribir personalizado...',
            ),
            const SizedBox(height: 16),

            // Notes field
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
                hintText: 'Ej: Cliente pidió color específico...',
                border: OutlineInputBorder(),
                helperText: 'Información adicional sobre esta parte',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),

            // Quantity and price
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _quantityController,
                    decoration: const InputDecoration(
                      labelText: 'Cantidad',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _priceController,
                    decoration: const InputDecoration(
                      labelText: 'Precio Unitario',
                      border: OutlineInputBorder(),
                      prefixText: '\$ ',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                  ),
                ),
              ],
            ),

            // Stock warning for catalog products
            if (_selection?.isCatalogProduct == true &&
                _selection?.product != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _selection!.product!.stockQuantity > 0
                        ? Colors.blue.shade50
                        : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _selection!.product!.stockQuantity > 0
                            ? Icons.inventory
                            : Icons.warning_amber,
                        size: 20,
                        color: _selection!.product!.stockQuantity > 0
                            ? Colors.blue
                            : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Stock disponible: ${_selection!.product!.stockQuantity.toInt()} unidades',
                          style: TextStyle(
                            fontSize: 13,
                            color: _selection!.product!.stockQuantity > 0
                                ? Colors.blue.shade900
                                : Colors.red.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            // If user typed something but didn't select, create ad-hoc selection
            if (_selection == null &&
                _productTextController.text.trim().isNotEmpty) {
              _selection = ProductSelection(
                isCatalogProduct: false,
                displayText: _productTextController.text.trim(),
                customDescription: _productTextController.text.trim(),
              );
              // Set default price if not set
              if (_priceController.text.isEmpty) {
                _priceController.text = '0';
              }
            }

            // Validate all required fields
            String? errorMessage;

            if (_selection == null ||
                _productTextController.text.trim().isEmpty) {
              errorMessage = 'Por favor seleccione o ingrese un producto';
            } else if (_quantityController.text.isEmpty ||
                int.tryParse(_quantityController.text) == null) {
              errorMessage = 'Por favor ingrese una cantidad válida';
            } else if (_priceController.text.isEmpty ||
                double.tryParse(_priceController.text) == null) {
              errorMessage = 'Por favor ingrese un precio válido';
            } else if (int.parse(_quantityController.text) <= 0) {
              errorMessage = 'La cantidad debe ser mayor a 0';
            } else if (double.parse(_priceController.text) < 0) {
              errorMessage = 'El precio no puede ser negativo';
            }

            if (errorMessage != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(errorMessage)),
              );
            } else {
              widget.onItemAdded(
                _selection!,
                int.parse(_quantityController.text),
                double.parse(_priceController.text),
                _notesController.text.trim().isEmpty
                    ? null
                    : _notesController.text.trim(),
              );
              Navigator.of(context).pop();
            }
          },
          child: const Text('Agregar'),
        ),
      ],
    );
  }
}

// Product selector dialog
class _ProductSelectorDialog extends StatefulWidget {
  final List<Product> products;
  final Function(Product product, int quantity, double price) onProductSelected;

  const _ProductSelectorDialog({
    required this.products,
    required this.onProductSelected,
  });

  @override
  State<_ProductSelectorDialog> createState() => _ProductSelectorDialogState();
}

class _ProductSelectorDialogState extends State<_ProductSelectorDialog> {
  Product? _selectedProduct;
  final _quantityController = TextEditingController(text: '1');
  final _priceController = TextEditingController();
  final _searchController = TextEditingController();
  List<Product> _filteredProducts = [];

  @override
  void initState() {
    super.initState();
    _filteredProducts = widget.products;
    _searchController.addListener(_filterProducts);
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _filterProducts() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredProducts = widget.products.where((p) {
        return p.name.toLowerCase().contains(query) ||
            p.sku.toLowerCase().contains(query) ||
            (p.brand?.toLowerCase().contains(query) ?? false);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Seleccionar Producto'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Buscar producto',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<Product>(
              initialValue: _selectedProduct,
              decoration: const InputDecoration(
                labelText: 'Producto',
                border: OutlineInputBorder(),
              ),
              items: _filteredProducts.map((product) {
                return DropdownMenuItem(
                  value: product,
                  child: Text(
                      '${product.name} (${product.sku}) - Stock: ${product.stockQuantity}'),
                );
              }).toList(),
              onChanged: (product) {
                setState(() {
                  _selectedProduct = product;
                  _priceController.text = product?.price.toString() ?? '';
                });
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _quantityController,
                    decoration: const InputDecoration(
                      labelText: 'Cantidad',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _priceController,
                    decoration: const InputDecoration(
                      labelText: 'Precio Unitario',
                      border: OutlineInputBorder(),
                      prefixText: '\$ ',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_selectedProduct != null &&
                _quantityController.text.isNotEmpty &&
                _priceController.text.isNotEmpty) {
              widget.onProductSelected(
                _selectedProduct!,
                int.parse(_quantityController.text),
                double.parse(_priceController.text),
              );
              Navigator.of(context).pop();
            }
          },
          child: const Text('Agregar'),
        ),
      ],
    );
  }
}

// Service entry dialog
class _ServiceEntryDialog extends StatefulWidget {
  final List<Product> serviceProducts;
  final void Function(
    Product? serviceProduct,
    String description,
    double hours,
    double rate,
    DateTime date,
  ) onServiceAdded;

  const _ServiceEntryDialog({
    required this.serviceProducts,
    required this.onServiceAdded,
  });

  @override
  State<_ServiceEntryDialog> createState() => _ServiceEntryDialogState();
}

class _ServiceEntryDialogState extends State<_ServiceEntryDialog> {
  late final TextEditingController _descriptionController;
  late final TextEditingController _hoursController;
  late final TextEditingController _rateController;
  final TextEditingController _searchController = TextEditingController();

  late DateTime _selectedDate;
  late List<Product> _filteredServices;
  Product? _selectedService;
  String? _validationMessage;

  @override
  void initState() {
    super.initState();
    _selectedService = null;

    _descriptionController = TextEditingController();
    _hoursController = TextEditingController(text: '1');
    _rateController = TextEditingController(text: '15000');
    _selectedDate = DateTime.now();

    _filteredServices = List<Product>.from(widget.serviceProducts);
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _hoursController.dispose();
    _rateController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredServices = List<Product>.from(widget.serviceProducts);
      } else {
        _filteredServices = widget.serviceProducts.where((service) {
          final nameMatch = service.name.toLowerCase().contains(query);
          final skuMatch = service.sku.toLowerCase().contains(query);
          return nameMatch || skuMatch;
        }).toList();
      }
    });
  }

  void _selectService(Product service) {
    setState(() {
      _selectedService = service;
      final currentDescription = _descriptionController.text.trim();
      if (currentDescription.isEmpty || currentDescription == service.name) {
        _descriptionController.text = service.name;
      }
      _rateController.text = service.price.toStringAsFixed(0);
      _validationMessage = null;
    });
  }

  void _setValidationMessage(String? message) {
    setState(() {
      _validationMessage = message;
    });
  }

  @override
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = MediaQuery.of(context).size.width < 600;

    return AlertDialog(
      insetPadding: isMobile
          ? const EdgeInsets.all(16)
          : const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0),
      title: const Text('Agregar Mano de Obra'),
      content: SizedBox(
        width: isMobile ? double.maxFinite : 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.serviceProducts.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Seleccionar servicio',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Buscar servicio',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 180,
                child: _filteredServices.isEmpty
                    ? Center(
                        child: Text(
                          'No se encontraron servicios',
                          style: theme.textTheme.bodyMedium,
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _filteredServices.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final service = _filteredServices[index];
                          final isSelected = _selectedService?.id == service.id;
                          return ListTile(
                            leading: const Icon(Icons.design_services_outlined),
                            title: Text(service.name),
                            subtitle: Text(service.sku),
                            trailing: isSelected
                                ? Icon(Icons.check_circle,
                                    color: theme.colorScheme.primary)
                                : null,
                            selected: isSelected,
                            onTap: () => _selectService(service),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Descripción del trabajo',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now(),
                );
                if (date != null) {
                  setState(() {
                    _selectedDate = date;
                  });
                }
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Fecha',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_today),
                ),
                child: Text(DateFormat('dd/MM/yyyy').format(_selectedDate)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _hoursController,
                    decoration: const InputDecoration(
                      labelText: 'Horas',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _rateController,
                    decoration: const InputDecoration(
                      labelText: 'Tarifa/Hora',
                      border: OutlineInputBorder(),
                      prefixText: '\$ ',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                  ),
                ),
              ],
            ),
            if (_validationMessage != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _validationMessage!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            _setValidationMessage(null);
            final parsedHours =
                double.tryParse(_hoursController.text.replaceAll(',', '.'));
            final parsedRate =
                double.tryParse(_rateController.text.replaceAll(',', '.'));
            final trimmedDescription = _descriptionController.text.trim();

            if (parsedHours == null || parsedHours <= 0) {
              _setValidationMessage('Ingrese un número de horas válido.');
              return;
            }
            if (parsedRate == null || parsedRate < 0) {
              _setValidationMessage('Ingrese una tarifa válida.');
              return;
            }
            if (trimmedDescription.isEmpty && _selectedService == null) {
              _setValidationMessage(
                  'Seleccione un servicio o ingrese una descripción.');
              return;
            }

            final description = trimmedDescription.isNotEmpty
                ? trimmedDescription
                : _selectedService?.name ?? '';

            widget.onServiceAdded(
              _selectedService,
              description,
              parsedHours,
              parsedRate,
              _selectedDate,
            );
            Navigator.of(context).pop();
          },
          child: const Text('Agregar'),
        ),
      ],
    );
  }
}

// Customer Selector Widget
class _CustomerSelector extends StatefulWidget {
  final List<Customer> initialCustomers;
  final CustomerService customerService;
  final Future<Customer?> Function(String name) onCreateCustomer;

  const _CustomerSelector({
    required this.initialCustomers,
    required this.customerService,
    required this.onCreateCustomer,
  });

  @override
  State<_CustomerSelector> createState() => _CustomerSelectorState();
}

class _CustomerSelectorState extends State<_CustomerSelector> {
  late List<Customer> _customers = widget.initialCustomers;
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _isSearching = false;
  bool _showCreateForm = false;
  Customer? _editingCustomer;

  // Form controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _rutController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _nameController.dispose();
    _rutController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String term) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _isSearching = true);
      try {
        final results = term.trim().isEmpty
            ? widget.initialCustomers
            : await widget.customerService
                .getCustomers(searchTerm: term, limit: 20);
        if (mounted) {
          setState(() => _customers = results);
        }
      } catch (_) {
        if (mounted) {
          setState(() => _customers = widget.initialCustomers);
        }
      } finally {
        if (mounted) {
          setState(() => _isSearching = false);
        }
      }
    });
  }

  void _populateFormFromCustomer(Customer customer) {
    _nameController.text = customer.name;
    _rutController.text = customer.rut;
    _emailController.text = customer.email ?? '';
    _phoneController.text = customer.phone ?? '';
    _addressController.text = customer.address ?? '';
  }

  void _clearForm() {
    _nameController.clear();
    _rutController.clear();
    _emailController.clear();
    _phoneController.clear();
    _addressController.clear();
  }

  void _startCreateCustomer() {
    setState(() {
      _showCreateForm = true;
      _editingCustomer = null;
      _clearForm();
    });
  }

  void _startEditCustomer(Customer customer) {
    setState(() {
      _showCreateForm = true;
      _editingCustomer = customer;
      _populateFormFromCustomer(customer);
    });
  }

  void _closeForm() {
    setState(() {
      _showCreateForm = false;
      _editingCustomer = null;
      _clearForm();
    });
  }

  Future<void> _handleCreateCustomer() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El nombre es obligatorio'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final customer = await _saveCustomerWithData({
      'name': _nameController.text.trim(),
      'rut': _rutController.text.trim(),
      'email': _emailController.text.trim(),
      'phone': _phoneController.text.trim(),
      'address': _addressController.text.trim(),
    });

    if (customer != null && mounted) {
      Navigator.of(context).pop(customer);
    }
  }

  Future<Customer?> _saveCustomerWithData(Map<String, String> data) async {
    try {
      final tenantId = await TenantService().getTenantId();
      if (tenantId == null || tenantId.isEmpty) {
        throw Exception('No se pudo obtener el tenant_id del usuario');
      }

      final customerService =
          Provider.of<CustomerService>(context, listen: false);
      final isEditing = _editingCustomer != null;

      final normalizedRut = (data['rut'] ?? '').trim();
      final normalizedEmail = (data['email'] ?? '').trim();
      final normalizedPhone = (data['phone'] ?? '').trim();
      final normalizedAddress = (data['address'] ?? '').trim();

      final saved = isEditing
          ? await customerService.updateCustomer(
              _editingCustomer!.copyWith(
                name: data['name']!,
                rut: normalizedRut,
                email: normalizedEmail.isEmpty ? null : normalizedEmail,
                phone: normalizedPhone.isEmpty ? null : normalizedPhone,
                address: normalizedAddress.isEmpty ? null : normalizedAddress,
                updatedAt: DateTime.now(),
              ),
            )
          : await customerService.createCustomer(
              Customer(
                tenantId: tenantId,
                name: data['name']!,
                rut: normalizedRut,
                email: normalizedEmail.isEmpty ? null : normalizedEmail,
                phone: normalizedPhone.isEmpty ? null : normalizedPhone,
                address: normalizedAddress.isEmpty ? null : normalizedAddress,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );

      setState(() {
        final existingIndex =
            _customers.indexWhere((item) => item.id == saved.id);
        if (existingIndex >= 0) {
          _customers[existingIndex] = saved;
        } else {
          _customers.add(saved);
        }
        _customers.sort(
          (left, right) => left.name.toLowerCase().compareTo(
                right.name.toLowerCase(),
              ),
        );
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEditing
                  ? 'Cliente "${saved.name}" actualizado exitosamente'
                  : 'Cliente "${saved.name}" creado exitosamente',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      return saved;
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al crear cliente: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: theme.colorScheme.surface,
      insetPadding: const EdgeInsets.all(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        width: 650,
        // When showing the form vertically, constraint height smoothly
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
          minHeight: 400,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Clean Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _showCreateForm ? Icons.person_add : Icons.people_alt,
                      color: theme.colorScheme.onPrimaryContainer,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _showCreateForm
                          ? (_editingCustomer != null
                              ? 'Editar Cliente'
                              : 'Nuevo Cliente')
                          : 'Seleccionar Cliente',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Cerrar',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Content Area (Switches between List and Form)
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _showCreateForm
                    ? _buildFormView(theme)
                    : _buildListView(theme),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListView(ThemeData theme) {
    return Column(
      key: const ValueKey('list_view'),
      children: [
        // Action Bar (Search + Add Button)
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre, RUT, email...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _startCreateCustomer,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nuevo'),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ],
          ),
        ),

        // Progress Indicator
        if (_isSearching)
          const LinearProgressIndicator(minHeight: 2)
        else
          const Divider(height: 1),

        // Table Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  'Nombre',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'Contacto',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 48), // Space for edit button
            ],
          ),
        ),
        const Divider(height: 1),

        // Table Body
        Expanded(
          child: _customers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_off,
                          size: 48, color: theme.colorScheme.outline),
                      const SizedBox(height: 16),
                      Text(
                        'No se encontraron clientes',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: _customers.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final customer = _customers[index];
                    return InkWell(
                      onTap: () => Navigator.of(context).pop(customer),
                      hoverColor: theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.3),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        child: Row(
                          children: [
                            // Name & Document
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    customer.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500),
                                  ),
                                  if (customer.rut.isNotEmpty)
                                    Text(
                                      customer.rut,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // Contact Info
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (customer.phone?.isNotEmpty == true)
                                    Text(
                                      customer.phone!,
                                      style: theme.textTheme.bodySmall,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  if (customer.email?.isNotEmpty == true)
                                    Text(
                                      customer.email!,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  if (customer.phone?.isEmpty != false &&
                                      customer.email?.isEmpty != false)
                                    Text(
                                      'Sin contacto',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.outline,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // Actions
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              color: theme.colorScheme.outline,
                              tooltip: 'Editar cliente',
                              onPressed: () => _startEditCustomer(customer),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFormView(ThemeData theme) {
    return Column(
      key: const ValueKey('form_view'),
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _nameController,
                        label: 'Nombre Completo *',
                        icon: Icons.person_outline,
                        textCapitalization: TextCapitalization.words,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTextField(
                        controller: _rutController,
                        label: 'RUT o Documento',
                        icon: Icons.badge_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _phoneController,
                        label: 'Teléfono',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTextField(
                        controller: _emailController,
                        label: 'Email',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildTextField(
                  controller: _addressController,
                  label: 'Dirección (Opcional)',
                  icon: Icons.location_on_outlined,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _closeForm,
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _handleCreateCustomer,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Guardar y Seleccionar'),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}

// ============================================================
// BROWSER-STYLE BIKE TAB (Chrome/Edge inspired tab design)
// ============================================================
class _BrowserStyleBikeTab extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  const _BrowserStyleBikeTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.onClose,
  });

  @override
  State<_BrowserStyleBikeTab> createState() => _BrowserStyleBikeTabState();
}

class _BrowserStyleBikeTabState extends State<_BrowserStyleBikeTab> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(right: 1),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? theme.colorScheme.surface
                : theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            border: widget.isSelected
                ? Border(
                    top: BorderSide(color: theme.colorScheme.primary, width: 3),
                    left: BorderSide(
                        color: theme.dividerColor.withValues(alpha: 0.5)),
                    right: BorderSide(
                        color: theme.dividerColor.withValues(alpha: 0.5)),
                  )
                : Border(
                    bottom: BorderSide(
                        color: theme.dividerColor.withValues(alpha: 0.5),
                        width: 1),
                  ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.pedal_bike,
                size: 16,
                color: widget.isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight:
                        widget.isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: widget.isSelected
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (widget.onClose != null &&
                  (_isHovered || widget.isSelected)) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: widget.onClose,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _isHovered
                          ? theme.colorScheme.error.withValues(alpha: 0.1)
                          : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: _isHovered
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ] else if (widget.onClose != null) ...[
                const SizedBox(width: 22), // Placeholder for close button width
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BikeTabButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final bool canClose;
  final VoidCallback onTap;
  final VoidCallback? onClose;
  final Color primaryColor;
  final Color inactiveColor;

  const _BikeTabButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.canClose,
    required this.onTap,
    required this.primaryColor,
    required this.inactiveColor,
    this.onClose,
  });

  @override
  State<_BikeTabButton> createState() => _BikeTabButtonState();
}

class _BikeTabButtonState extends State<_BikeTabButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showClose = widget.canClose &&
        widget.onClose != null &&
        (_isHovered || widget.isSelected);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? widget.primaryColor.withValues(alpha: 0.08)
                  : Colors.transparent,
              border: Border(
                bottom: BorderSide(
                  color: widget.isSelected
                      ? widget.primaryColor
                      : Colors.transparent,
                  width: 2.5,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: 16,
                  color: widget.isSelected
                      ? widget.primaryColor
                      : widget.inactiveColor,
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    widget.label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight:
                          widget.isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: widget.isSelected
                          ? theme.colorScheme.onSurface
                          : widget.inactiveColor,
                    ),
                  ),
                ),
                if (widget.canClose) ...[
                  const SizedBox(width: 8),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 140),
                    opacity: showClose ? 1 : 0,
                    child: IgnorePointer(
                      ignoring: !showClose,
                      child: InkWell(
                        onTap: widget.onClose,
                        borderRadius: BorderRadius.circular(999),
                        hoverColor:
                            theme.colorScheme.error.withValues(alpha: 0.12),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: showClose
                                ? theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.6)
                                : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close,
                            size: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
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
}
