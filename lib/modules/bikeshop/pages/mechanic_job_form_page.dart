import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

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
import '../services/bikeshop_service.dart';
import '../services/smart_task_service.dart';
import '../services/job_status_service.dart';
import '../models/bikeshop_models.dart';
import 'bike_form_dialog.dart';

// ============================================================
// Per-Bike Data Container (Multi-bike support)
// ============================================================
class _BikeTabData {
  final String tabId; // Unique ID for this tab
  Bike? bike;
  String? jobBikeId; // Database ID from mechanic_job_bikes (null for new)

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

  _BikeTabData({String? tabId, this.bike, this.jobBikeId})
      : tabId = tabId ?? DateTime.now().microsecondsSinceEpoch.toString();

  void dispose() {
    clientRequestController.dispose();
    diagnosisController.dispose();
    workRequestedController.dispose();
    technicianNotesController.dispose();
  }

  String get displayName => bike?.displayName ?? 'Nueva Bicicleta';

  double get subtotal =>
      partItems.fold(0, (sum, item) => sum + item.quantity * item.unitPrice);
}

class MechanicJobFormPage extends StatefulWidget {
  final String? jobId; // Null for new job, ID for editing
  final String? customerId; // Pre-select customer if provided

  const MechanicJobFormPage({
    super.key,
    this.jobId,
    this.customerId,
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

  /// Currently selected bike tab
  _BikeTabData? get _currentBikeTab =>
      _bikeTabs.isNotEmpty && _selectedBikeTabIndex < _bikeTabs.length
          ? _bikeTabs[_selectedBikeTabIndex]
          : null;

  // Legacy single-bike state (for backward compatibility during migration)
  // TODO: Remove once multi-bike is fully implemented
  final _clientRequestController = TextEditingController();
  final _diagnosisController = TextEditingController();
  final _workSummaryController = TextEditingController();
  final _technicianNotesController = TextEditingController();

  // Form state
  Customer? _selectedCustomer;
  Bike? _selectedBike; // Legacy - now use _bikeTabs
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

  // Parts and services
  final List<_JobPartItem> _partItems = [];
  final List<_JobServiceItem> _serviceItems = [];

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

  // Edit mode
  MechanicJob? _existingJob;

  @override
  void initState() {
    super.initState();
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
    _partAutocompleteFocus.dispose();
    // Dispose all bike tab controllers
    for (final tab in _bikeTabs) {
      tab.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final customerService =
          Provider.of<CustomerService>(context, listen: false);
      final inventoryService =
          Provider.of<InventoryService>(context, listen: false);
      final jobStatusService =
          Provider.of<JobStatusService>(context, listen: false);

      // Load data in parallel to speed up form opening
      final results = await Future.wait([
        customerService.getCustomers(forceRefresh: false),
        inventoryService.getProducts(forceRefresh: false),
        jobStatusService
            .loadStatuses(), // Returns void, but we await completion
      ]);

      final customers = results[0] as List<Customer>;
      final products = results[1] as List<Product>;

      // Compute derived data efficiently
      final serviceProducts = products
          .where((product) => product.productType == ProductType.service)
          .toList();

      final customStatuses = jobStatusService.activeStatuses;
      debugPrint('📋 Loaded ${customStatuses.length} custom statuses');

      if (mounted) {
        setState(() {
          _customers = customers;
          _products = products;
          _serviceProducts = serviceProducts;
          _customStatuses = customStatuses;
          // Set default status to first "todo" phase status if available
          if (_customStatuses.isNotEmpty && _selectedCustomStatus == null) {
            _selectedCustomStatus = _customStatuses.firstWhere(
              (s) => s.phase == StatusPhase.todo,
              orElse: () => _customStatuses.first,
            );
          }
        });
      }

      // If editing, load existing job
      if (widget.jobId != null) {
        await _loadExistingJob();
      }

      // If customer ID provided, pre-select customer
      if (widget.customerId != null && widget.jobId == null) {
        final customer = _customers.firstWhere(
          (c) => c.id == widget.customerId,
          orElse: () => _customers.first,
        );
        await _selectCustomer(customer);
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

      // Load customer and bikes
      final customer = _customers.firstWhere((c) => c.id == job.customerId);
      await _selectCustomer(customer);

      // Load all job items (parts + services)
      final allItems = await bikeshopService.getJobItems(job.id!);

      // Load multi-bike data from mechanic_job_bikes
      final jobBikes = await bikeshopService.getJobBikes(job.id!);
      debugPrint('📦 Loaded ${jobBikes.length} job bikes');

      // Load tax treatment from job
      TaxTreatment loadedTaxTreatment = job.taxTreatment;
      debugPrint('✅ Tax treatment loaded: $loadedTaxTreatment');

      // Helper to find/create product for an item
      Future<Product?> getProductForItem(MechanicJobItem item) async {
        if (item.productId == null) return null;

        try {
          return _products.firstWhere((p) => p.id == item.productId);
        } catch (_) {
          try {
            return await inventoryService.getProductById(item.productId!);
          } catch (e) {
            debugPrint('⚠️ Could not fetch product ${item.productId}: $e');
            return Product(
              id: item.productId!,
              name: item.productName,
              sku: item.productSku ?? 'N/A',
              price: item.unitPrice,
              cost: 0,
              stockQuantity: 0,
              category: ProductCategory.other,
              productType: ProductType.product,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            );
          }
        }
      }

      // Build bike tabs from job bikes data
      final List<_BikeTabData> loadedBikeTabs = [];

      if (jobBikes.isNotEmpty) {
        // Multi-bike job: create tab for each job bike
        for (final jobBike in jobBikes) {
          // Use bike from local cache, or from the joined data loaded by getJobBikes()
          Bike? bike = _bikes.firstWhereOrNull((b) => b.id == jobBike.bikeId);
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
          tab.isWarrantyWork = jobBike.isWarrantyWork;
          tab.requiresApproval = jobBike.requiresApproval;
          tab.approvedByCustomer = jobBike.approvedByCustomer;

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
              quantity: item.quantity.toInt(),
              unitPrice: item.unitPrice,
              notes: item.notes,
            ));
          }

          loadedBikeTabs.add(tab);
          debugPrint(
              '✅ Loaded bike tab: ${bike.displayName} with ${tab.partItems.length} items');
        }
      } else {
        // Legacy single-bike job: create one tab from job data
        final bike = _bikes.firstWhereOrNull((b) => b.id == job.bikeId);
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
              quantity: item.quantity.toInt(),
              unitPrice: item.unitPrice,
              notes: item.notes,
            ));
          }

          loadedBikeTabs.add(tab);
          debugPrint(
              '✅ Loaded legacy single-bike tab: ${bike.displayName} with ${tab.partItems.length} items');
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

          _selectedDeadline = job.deadline;
          _selectedArrivalDate = job.arrivalDate;
          _taxTreatment = loadedTaxTreatment;
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

          // Clear legacy items (now per-bike)
          _partItems.clear();
          _serviceItems.clear();
        });
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
      _bikeTabs.add(newTab);
      _selectedBikeTabIndex = _bikeTabs.length - 1;

      // Also set legacy single bike (for backward compat)
      _selectedBike = bike;
    });
  }

  /// Remove a bike tab
  void _removeBikeTab(int index) {
    if (_bikeTabs.length <= 1) {
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
      final newBike = await showDialog<Bike?>(
        context: context,
        builder: (context) => BikeFormDialog(
          customerId: _selectedCustomer!.id!,
        ),
      );

      if (newBike != null && mounted) {
        // Reload bikes and add the new one
        final bikeshopService =
            Provider.of<BikeshopService>(context, listen: false);
        final bikes =
            await bikeshopService.getBikes(customerId: _selectedCustomer!.id);
        setState(() {
          _bikes = bikes;
        });
        _addBikeTab(
            bikes.firstWhere((b) => b.id == newBike.id, orElse: () => newBike));
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
                  final newBike = await showDialog<Bike?>(
                    context: this.context,
                    builder: (ctx) => BikeFormDialog(
                      customerId: _selectedCustomer!.id!,
                    ),
                  );
                  if (newBike != null && mounted) {
                    final bikeshopService = Provider.of<BikeshopService>(
                        this.context,
                        listen: false);
                    final bikes = await bikeshopService.getBikes(
                        customerId: _selectedCustomer!.id);
                    setState(() {
                      _bikes = bikes;
                    });
                    _addBikeTab(bikes.firstWhere((b) => b.id == newBike.id,
                        orElse: () => newBike));
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

  void _addCatalogPart(Product product) {
    // Always add as new line (allow duplicates on different lines)
    setState(() {
      _currentPartItems.add(_JobPartItem(
        product: product,
        name: product.name,
        isCatalogProduct: true,
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
        quantity: 1,
        unitPrice: 0,
        notes: null,
      ));
    });
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

  void _showAddItemPicker() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Agregar repuesto o parte'),
              subtitle:
                  const Text('Busca en catálogo o ingresa uno personalizado'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _focusPartAutocomplete();
              },
            ),
            const Divider(height: 0),
            ListTile(
              leading: const Icon(Icons.build_outlined),
              title: const Text('Agregar servicio / mano de obra'),
              subtitle: const Text('Registrar trabajos o paquetes de servicio'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Future.microtask(_addServiceItem);
              },
            ),
          ],
        ),
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

  double get _netAmount {
    final afterDiscount = _subtotal - _discountAmount;
    if (_taxTreatment == TaxTreatment.taxIncluded) {
      // Tax included: net = total ÷ 1.19
      return afterDiscount / 1.19;
    } else {
      // No tax: net = full amount
      return afterDiscount;
    }
  }

  double get _taxAmount {
    if (_taxTreatment == TaxTreatment.noTax) {
      return 0.0;
    }
    // Tax included: iva = total - net
    return (_subtotal - _discountAmount) - _netAmount;
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

    // MULTI-BIKE: Check that we have at least one bike tab
    if (_bikeTabs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Debe seleccionar al menos una bicicleta')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final bikeshopService =
          Provider.of<BikeshopService>(context, listen: false);

      final tenantId = await TenantService().getTenantId();
      if (tenantId == null) {
        throw Exception('User does not have a tenant_id. Cannot proceed.');
      }

      // Use first bike as the "primary" bike for legacy compatibility
      final primaryBike = _bikeTabs.first.bike;
      if (primaryBike?.id == null) {
        throw Exception('La primera bicicleta no tiene ID');
      }

      // Get combined data from first bike tab for job-level fields (legacy)
      final firstTab = _bikeTabs.first;

      // Create MechanicJob object (job-level data)
      final job = MechanicJob(
        id: widget.jobId,
        tenantId: tenantId,
        jobNumber:
            _existingJob?.jobNumber ?? '', // Will be auto-generated if empty
        customerId: _selectedCustomer!.id!,
        bikeId: primaryBike!.id!, // Primary bike for legacy
        priority: _selectedPriority,
        status: _selectedStatus,
        statusId: _selectedCustomStatus?.id, // Custom status ID
        arrivalDate: _selectedArrivalDate,
        createdAt: _existingJob?.createdAt ?? DateTime.now(),
        // Store first bike's data in legacy fields for backward compat
        clientRequest: firstTab.clientRequestController.text.trim().isEmpty
            ? null
            : firstTab.clientRequestController.text.trim(),
        diagnosis: firstTab.diagnosisController.text.trim().isEmpty
            ? null
            : firstTab.diagnosisController.text.trim(),
        workPerformed: firstTab.workRequestedController.text.trim().isEmpty
            ? null
            : firstTab.workRequestedController.text.trim(),
        notes: firstTab.technicianNotesController.text.trim().isEmpty
            ? null
            : firstTab.technicianNotesController.text.trim(),
        deadline: _selectedDeadline,
        requiresApproval: firstTab.requiresApproval,
        isWarrantyJob: firstTab.isWarrantyWork,
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
      );

      String jobId;

      if (widget.jobId != null) {
        // Update existing job
        await bikeshopService.updateJob(job);
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
            await bikeshopService.deleteJobItem(existing.id!);
          }
        }

        // Delete existing job bikes (we'll re-create them)
        final existingJobBikes = await bikeshopService.getJobBikes(jobId);
        for (final existingJB in existingJobBikes) {
          if (existingJB.id != null) {
            await bikeshopService.removeBikeFromJob(existingJB.id!);
          }
        }
      }

      final taskService = Provider.of<SmartTaskService>(context, listen: false);

      // Save each bike tab
      for (int i = 0; i < _bikeTabs.length; i++) {
        final tab = _bikeTabs[i];
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
          isWarrantyWork: tab.isWarrantyWork,
          requiresApproval: tab.requiresApproval,
          approvedByCustomer: tab.approvedByCustomer,
        );

        final createdJobBike = await bikeshopService.addBikeToJob(jobBike);
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
            productName: item.name,
            productSku: item.sku ?? '',
            quantity: quantity,
            unitPrice: unitPrice,
            totalPrice: quantity * unitPrice,
            itemType: 'product',
          );
          final created = await bikeshopService.createJobItem(jobItem);

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

        final created = await bikeshopService.createJobItem(jobServiceItem);

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

      // AFTER all items are updated, sync to invoice if it exists
      if (_existingJob?.invoiceId != null) {
        debugPrint('🔄 Syncing job to invoice: ${_existingJob!.invoiceId}');
        await bikeshopService.syncJobToInvoice(jobId);
        await _updateInvoiceTaxTreatment(_existingJob!.invoiceId!);
      }

      // Create invoice AFTER items are added (only for new jobs)
      if (widget.jobId == null) {
        await bikeshopService.createInvoiceFromJob(jobId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.jobId != null
                ? 'Pega actualizada correctamente'
                : 'Pega creada correctamente'),
            backgroundColor: Colors.green,
          ),
        );
        if (context.canPop()) {
          context.pop(true);
        } else {
          context.go('/taller/pegas');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar pega: $e')),
        );
      }
    } finally {
      setState(() {
        _isSaving = false;
      });
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('WhatsApp abierto con mensaje pre-llenado'),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'WhatsApp abierto - Notifica al cliente que su bici está lista'),
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
      try {
        final bikeshopService =
            Provider.of<BikeshopService>(context, listen: false);
        await bikeshopService.deleteBike(bike.id!);

        // Reload bikes
        final bikes =
            await bikeshopService.getBikes(customerId: _selectedCustomer!.id);

        setState(() {
          _bikes = bikes;
          if (_selectedBike?.id == bike.id) {
            _selectedBike =
                null; // Clear selection if deleted bike was selected
          }
        });

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

                          await showDialog<Bike?>(
                            context: context,
                            builder: (context) => BikeFormDialog(
                              customerId: _selectedCustomer!.id!,
                              bike: bike,
                            ),
                          );

                          // Refresh bike list after edit or delete
                          final bikeshopService = Provider.of<BikeshopService>(
                              context,
                              listen: false);
                          final bikes = await bikeshopService.getBikes(
                              customerId: _selectedCustomer!.id);
                          setState(() {
                            _bikes = bikes;
                            // Clear selection if deleted bike was selected
                            if (_selectedBike?.id == bike.id &&
                                !bikes.any((b) => b.id == bike.id)) {
                              _selectedBike = null;
                            }
                          });
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
    return MainLayout(
      child: Form(
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
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final isEditing = widget.jobId != null;
    final title = isEditing ? 'Editar Trabajo' : 'Nuevo Trabajo';

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
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          // WhatsApp button (only when editing and customer selected)
          if (isEditing &&
              _selectedCustomer != null &&
              _selectedBike != null) ...[
            // Show "Ready for Pickup" button if job is finished
            if (_selectedStatus == JobStatus.finalizado ||
                _selectedStatus == JobStatus.entregado)
              OutlinedButton.icon(
                onPressed: () => _sendReadyForPickupMessage(),
                icon: const Icon(Icons.check_circle, color: Colors.green),
                label: const Text('Avisar Cliente'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.green,
                ),
              )
            else
              // Otherwise show status update button
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
            onPressed: _isSaving ? null : () => context.pop(),
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
  }

  Widget _buildForm(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 1180;

        if (isWide) {
          // Two-column layout for wide screens
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
                          child: _buildJobDetailsSection(),
                        ),
                        const SizedBox(height: 16),
                        _buildSectionCard(
                          theme,
                          icon: Icons.shopping_basket_outlined,
                          title: 'Productos y Servicios',
                          child: _buildPartsSection(),
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
                      ],
                    ),
                  ),
                ),
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
                  child: _buildJobDetailsSection(),
                ),
                const SizedBox(height: 16),
                _buildSectionCard(
                  theme,
                  icon: Icons.shopping_basket_outlined,
                  title: 'Productos y Servicios',
                  child: _buildPartsSection(),
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
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
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
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
                  child: Icon(icon, color: theme.colorScheme.primary, size: 18),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                // Bike tabs on the right side of header
                if (hasBikeTabs) ...[
                  const Spacer(),
                  _buildInlineBikeTabs(theme),
                ],
              ],
            ),
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

  /// Compact inline bike tabs for the card header
  Widget _buildInlineBikeTabs(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ..._bikeTabs.asMap().entries.map((entry) {
            final index = entry.key;
            final tab = entry.value;
            final isSelected = index == _selectedBikeTabIndex;

            return Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Material(
                color:
                    isSelected ? theme.colorScheme.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  onTap: () => setState(() => _selectedBikeTabIndex = index),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.pedal_bike,
                          size: 14,
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          tab.bike?.displayName ?? 'Bici ${index + 1}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w400,
                            color: isSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (_bikeTabs.length > 1) ...[
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () => _removeBikeTab(index),
                            borderRadius: BorderRadius.circular(10),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withOpacity(0.6),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          // Add bike button
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              onTap: _showAddBikeSelector,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.add,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
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

              return _BrowserStyleBikeTab(
                label: tab.displayName,
                isSelected: isSelected,
                onTap: () => setState(() => _selectedBikeTabIndex = index),
                onClose:
                    _bikeTabs.length > 1 ? () => _removeBikeTab(index) : null,
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
                child: Row(
                  children: const [
                    Icon(Icons.add, size: 18),
                    SizedBox(width: 8),
                    Text('Nueva bicicleta'),
                  ],
                ),
                onTap: () async {
                  // Delay to let menu close
                  await Future.delayed(const Duration(milliseconds: 100));
                  if (!mounted) return;

                  final newBike = await showDialog<Bike?>(
                    context: context,
                    builder: (context) => BikeFormDialog(
                      customerId: _selectedCustomer!.id!,
                    ),
                  );

                  if (!mounted) return;

                  // Reload bikes for this customer
                  final bikeshopService =
                      Provider.of<BikeshopService>(context, listen: false);
                  final bikes = await bikeshopService.getBikes(
                      customerId: _selectedCustomer!.id);

                  setState(() {
                    _bikes = bikes;
                  });

                  // Add to multi-bike tabs
                  if (newBike != null && mounted) {
                    final addedBike = _bikes.firstWhere(
                      (bike) => bike.id == newBike.id,
                      orElse: () => newBike,
                    );
                    _addBikeTab(addedBike);

                    ScaffoldMessenger.of(context).showSnackBar(
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
                  child: Row(
                    children: const [
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
      ],
    );
  }

  Widget _buildJobDetailsSection() {
    // Get current bike tab (if any)
    final currentTab = _currentBikeTab;

    // Use tab-specific controllers if available, otherwise fall back to legacy
    final diagnosisCtrl =
        currentTab?.diagnosisController ?? _diagnosisController;
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
        // ========== JOB-LEVEL FIELDS (same for all bikes) ==========
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<JobPriority>(
                value: _selectedPriority,
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
                      value: _selectedStatus,
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
                      value: _selectedCustomStatus,
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
        // Using keys to force widget recreation when tab changes
        const SizedBox(height: 16),
        TextFormField(
          key: ValueKey('clientRequest_${currentTab?.tabId ?? "legacy"}'),
          controller:
              currentTab?.clientRequestController ?? _clientRequestController,
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
          key: ValueKey('diagnosis_${currentTab?.tabId ?? "legacy"}'),
          controller: diagnosisCtrl,
          decoration: const InputDecoration(
            labelText: 'Diagnóstico',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.description),
            hintText: 'Descripción técnica del problema...',
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: ValueKey('workRequested_${currentTab?.tabId ?? "legacy"}'),
          controller: workRequestedCtrl,
          decoration: const InputDecoration(
            labelText: 'Trabajos a realizar',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.build),
            hintText: 'Ej: Cambio de cadena, ajuste de frenos, lubricación...',
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: ValueKey('techNotes_${currentTab?.tabId ?? "legacy"}'),
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
          key: ValueKey('checkboxes_${currentTab?.tabId ?? "legacy"}'),
          children: [
            Expanded(
              child: CheckboxListTile(
                title: const Text('Requiere aprobación del cliente'),
                value: requiresApproval,
                onChanged: (value) {
                  setState(() {
                    if (currentTab != null) {
                      currentTab.requiresApproval = value ?? false;
                    } else {
                      _requiresApproval = value ?? false;
                    }
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
            Expanded(
              child: CheckboxListTile(
                title: const Text('Trabajo de garantía'),
                value: isWarranty,
                onChanged: (value) {
                  setState(() {
                    if (currentTab != null) {
                      currentTab.isWarrantyWork = value ?? false;
                    } else {
                      _isWarrantyJob = value ?? false;
                    }
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPartsSection() {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Responsive grid table (same as sales invoice)
        LayoutBuilder(
          builder: (context, constraints) {
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
                        color: theme.colorScheme.outline.withOpacity(0.2)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Table header
                      Container(
                        decoration: BoxDecoration(
                          color:
                              theme.colorScheme.surfaceVariant.withOpacity(0.3),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(8)),
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
                                          .withOpacity(0.2)),
                                ),
                              ),
                              child: Center(
                                child: Text('#',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                        fontWeight: FontWeight.w600)),
                              ),
                            ),

                            // Repuesto column (flex)
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
                                            .withOpacity(0.2)),
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
                                          .withOpacity(0.2)),
                                ),
                              ),
                              child: Center(
                                child: Text('CANTIDAD',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                        fontWeight: FontWeight.w600)),
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
                                          .withOpacity(0.2)),
                                ),
                              ),
                              child: Center(
                                child: Text('PRECIO UNIT.',
                                    style: theme.textTheme.labelSmall?.copyWith(
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
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                  textAlign: TextAlign.right),
                            ),

                            // Actions column
                            SizedBox(width: _colActionsWidth),
                          ],
                        ),
                      ),

                      // Header/Content divider
                      Divider(
                          height: 1,
                          thickness: 1,
                          color: theme.colorScheme.outline.withOpacity(0.2)),

                      // Part items, labor items, and add row
                      Column(
                        children: [
                          // Existing part items (from current bike tab or legacy)
                          if (_currentPartItems.isNotEmpty)
                            ..._currentPartItems.asMap().entries.map((entry) =>
                                _buildPartRow(theme, entry.key + 1, entry.value,
                                    entry.key)),

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
                                            .withOpacity(0.2))
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
                                                .withOpacity(0.2)),
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
                                                  .withOpacity(0.2)),
                                        ),
                                      ),
                                      child: ProductAutocompleteField(
                                        key: ValueKey(_partAutocompleteKey),
                                        focusNode: _partAutocompleteFocus,
                                        onProductSelected: (selection) {
                                          if (selection.isCatalogProduct &&
                                              selection.product != null) {
                                            _addCatalogPart(selection.product!);
                                          } else if (!selection
                                              .isCatalogProduct) {
                                            _addCustomPart(
                                                selection.displayText);
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
                                                .withOpacity(0.2)),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: _colPriceWidth,
                                    decoration: BoxDecoration(
                                      border: Border(
                                        right: BorderSide(
                                            color: theme.colorScheme.outline
                                                .withOpacity(0.2)),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: _colTotalWidth),
                                  SizedBox(width: _colActionsWidth),
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
    );
  }

  /// Builds a part row using the universal LineRowWrapper.
  /// Provides hover-based reorder arrows and consistent styling.
  Widget _buildPartRow(
      ThemeData theme, int index, _JobPartItem item, int itemIndex) {
    final partItems = _currentPartItems; // Get current bike's items

    return LineRowWrapper(
      key: ValueKey('part_${item.id}'),
      index: index,
      canMoveUp: itemIndex > 0,
      canMoveDown: itemIndex < partItems.length - 1,
      onMoveUp: () {
        if (itemIndex > 0) {
          setState(() {
            final temp = partItems[itemIndex];
            partItems[itemIndex] = partItems[itemIndex - 1];
            partItems[itemIndex - 1] = temp;
          });
        }
      },
      onMoveDown: () {
        if (itemIndex < partItems.length - 1) {
          setState(() {
            final temp = partItems[itemIndex];
            partItems[itemIndex] = partItems[itemIndex + 1];
            partItems[itemIndex + 1] = temp;
          });
        }
      },
      onRemove: () => setState(() => partItems.removeAt(itemIndex)),
      canEdit: true,
      indexColumnWidth: _colIndexWidth,
      actionsColumnWidth: _colActionsWidth,
      showDeleteButton: true,
      columns: [
        // Product details column - uses SmartProductField for consistent behavior
        LineColumn(
          expanded: true,
          minWidth: 250,
          padding: const EdgeInsets.all(12),
          child: SmartProductField(
            key: ValueKey('smart_product_${item.id}'),
            initialData: item.product != null || item.name.isNotEmpty
                ? ProductFieldData(
                    product: item.product,
                    productName:
                        item.displayName.isNotEmpty ? item.displayName : null,
                    productSku: item.sku,
                    isCatalogProduct: item.isCatalogProduct,
                    description: item.notes,
                  )
                : null,
            enabled: true,
            showCost: false, // Pegas bill customers at SALE price, not cost
            allowCustomItems: true,
            autoFocus: item.product == null &&
                item.name.isEmpty, // Auto-focus empty rows
            onAutoAddLine: () {
              // Auto-add new line when product is selected
              _addEmptyPartLine();
            },
            onProductChanged: (selection) {
              if (selection == null) {
                // Product cleared - reset the item but keep same ID
                setState(() {
                  partItems[itemIndex] = item.copyWith(
                    clearProduct: true,
                    name: '',
                    isCatalogProduct: false,
                    quantity: 1,
                    unitPrice: 0,
                    notes: null,
                  );
                });
              } else if (selection.price == 0 &&
                  selection.description != null) {
                // Description-only update - DON'T reset price, just update notes
                // Update in-place without full setState to avoid focus loss
                item.notes = selection.description;
                // No setState needed - description field handles its own state
              } else {
                // Product selected - update with sale price (not cost)
                setState(() {
                  partItems[itemIndex] = item.copyWith(
                    product: selection.product,
                    name: selection.productName ?? '',
                    isCatalogProduct: selection.isCatalogProduct,
                    unitPrice: selection.product?.price ?? item.unitPrice,
                    notes: selection.description,
                  );
                });
              }
            },
          ),
        ),

        // Cantidad column
        LineColumn(
          width: _colQuantityWidth,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Center(
            child: TextFormField(
              key: ValueKey('qty_${item.id}'),
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
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              onChanged: (value) {
                final newQty = int.tryParse(value) ?? 1;
                // Update in-place to avoid focus loss
                item.quantity = newQty;
                // Only setState to update total display
                setState(() {});
              },
            ),
          ),
        ),

        // Precio column - EDITABLE
        LineColumn(
          width: _colPriceWidth,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: TextFormField(
            key: ValueKey('price_${item.id}'),
            initialValue: item.unitPrice.toStringAsFixed(0),
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(),
              prefixText: '\$ ',
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
            ],
            onChanged: (value) {
              final newPrice = double.tryParse(value) ?? 0;
              // Update in-place to avoid focus loss
              item.unitPrice = newPrice;
              // Only setState to update total display
              setState(() {});
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
                .format(item.quantity * item.unitPrice),
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildLaborSection() {
    final theme = Theme.of(context);

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
                            color: theme.colorScheme.outline.withOpacity(0.2)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Table header
                          Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceVariant
                                  .withOpacity(0.3),
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
                                              .withOpacity(0.2)),
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
                                                .withOpacity(0.2)),
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
                                              .withOpacity(0.2)),
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
                                              .withOpacity(0.2)),
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
                                              .withOpacity(0.2)),
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
                                SizedBox(width: _colActionsWidth),
                              ],
                            ),
                          ),

                          // Header/Content divider
                          Divider(
                              height: 1,
                              thickness: 1,
                              color:
                                  theme.colorScheme.outline.withOpacity(0.2)),

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
                                                .withOpacity(0.2))
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
                                                    .withOpacity(0.2)),
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
                    color: theme.colorScheme.outline.withOpacity(0.2),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: item.serviceProduct?.imageUrl != null
                      ? Image.network(
                          item.serviceProduct!.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.work_outline,
                            color: Colors.blue,
                            size: 24,
                          ),
                        )
                      : Icon(
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
                    color: theme.colorScheme.outline.withOpacity(0.3)),
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
        // Tax Treatment Dropdown
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tratamiento de IVA:', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            DropdownButtonFormField<TaxTreatment>(
              value: _taxTreatment,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(
                  value: TaxTreatment.noTax,
                  child: Text('Sin IVA'),
                ),
                DropdownMenuItem(
                  value: TaxTreatment.taxIncluded,
                  child: Text('IVA Incluido (19%)'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _taxTreatment = value);
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_taxTreatment == TaxTreatment.taxIncluded) ...[
          _buildCostRow('Neto:', _netAmount, false),
          const SizedBox(height: 8),
          _buildCostRow('IVA (19%):', _taxAmount, false),
        ],
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
                  'Factura: ${_existingJob?.invoiceId ?? "N/A"}',
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
                context.push('/sales/invoices/${_existingJob!.invoiceId}/edit');
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
class _JobPartItem {
  final String id; // Unique stable ID for widget keys
  Product? product; // Nullable for ad-hoc items
  String name; // For ad-hoc items
  bool isCatalogProduct;
  int quantity;
  double unitPrice;
  String? notes;

  _JobPartItem({
    String? id,
    this.product,
    required this.name,
    this.isCatalogProduct = true,
    required this.quantity,
    required this.unitPrice,
    this.notes,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  String get displayName => product?.name ?? name;
  String? get sku => product?.sku;

  /// Create a copy with the same ID (for preserving widget keys)
  _JobPartItem copyWith({
    Product? product,
    String? name,
    bool? isCatalogProduct,
    int? quantity,
    double? unitPrice,
    String? notes,
    bool clearProduct = false,
  }) {
    return _JobPartItem(
      id: id, // Keep same ID!
      product: clearProduct ? null : (product ?? this.product),
      name: name ?? this.name,
      isCatalogProduct: isCatalogProduct ?? this.isCatalogProduct,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      notes: notes ?? this.notes,
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
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar Repuesto o Parte'),
      content: SizedBox(
        width: 500,
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
              decoration: InputDecoration(
                labelText: 'Notas (opcional)',
                hintText: 'Ej: Cliente pidió color específico...',
                border: const OutlineInputBorder(),
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
              value: _selectedProduct,
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Agregar Mano de Obra'),
      content: SizedBox(
        width: 420,
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
            : await widget.customerService.getCustomers(searchTerm: term);
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

    final customer = await _createCustomerWithData({
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

  Future<Customer?> _createCustomerWithData(Map<String, String> data) async {
    try {
      final tenantId = await TenantService().getTenantId();
      if (tenantId == null) {
        throw Exception('No se pudo obtener el tenant_id del usuario');
      }

      final customer = Customer(
        tenantId: tenantId,
        name: data['name']!,
        rut: data['rut'] ?? '',
        email: data['email']?.isEmpty == true ? null : data['email'],
        phone: data['phone']?.isEmpty == true ? null : data['phone'],
        address: data['address']?.isEmpty == true ? null : data['address'],
      );

      final customerService =
          Provider.of<CustomerService>(context, listen: false);
      final created = await customerService.createCustomer(customer);

      // Add to list
      setState(() {
        _customers.add(created);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cliente "${created.name}" creado exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
      }

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: 600,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.person_search,
                    color: theme.colorScheme.onPrimary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Seleccionar Cliente',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, color: theme.colorScheme.onPrimary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Search field
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        labelText: 'Buscar cliente',
                        hintText: 'Buscar por nombre, RUT, email...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged: _onSearchChanged,
                    ),
                    const SizedBox(height: 16),

                    // Toggle button
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _showCreateForm = !_showCreateForm;
                          if (!_showCreateForm) {
                            // Clear form when collapsing
                            _nameController.clear();
                            _rutController.clear();
                            _emailController.clear();
                            _phoneController.clear();
                            _addressController.clear();
                          }
                        });
                      },
                      icon: Icon(_showCreateForm
                          ? Icons.expand_less
                          : Icons.person_add),
                      label: Text(
                          _showCreateForm ? 'Cancelar' : 'Crear cliente nuevo'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),

                    // Inline create form
                    if (_showCreateForm) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color:
                              theme.colorScheme.surfaceVariant.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.colorScheme.outline.withOpacity(0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Nombre *',
                                hintText: 'Nombre completo',
                                isDense: true,
                              ),
                              textCapitalization: TextCapitalization.words,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _rutController,
                              decoration: const InputDecoration(
                                labelText: 'RUT',
                                hintText: '12.345.678-9',
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _emailController,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                hintText: 'cliente@ejemplo.com',
                                isDense: true,
                              ),
                              keyboardType: TextInputType.emailAddress,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _phoneController,
                              decoration: const InputDecoration(
                                labelText: 'Teléfono',
                                hintText: '+56 9 1234 5678',
                                isDense: true,
                              ),
                              keyboardType: TextInputType.phone,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _addressController,
                              decoration: const InputDecoration(
                                labelText: 'Dirección',
                                hintText: 'Calle, número, comuna',
                                isDense: true,
                              ),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _handleCreateCustomer,
                              icon: const Icon(Icons.check),
                              label: const Text('Crear y Seleccionar'),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                    if (_isSearching)
                      const LinearProgressIndicator(minHeight: 2),

                    // Customer list (only show when not creating)
                    if (!_showCreateForm)
                      Container(
                        height: 400,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: theme.colorScheme.outline.withOpacity(0.2),
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _customers.isEmpty
                            ? const Center(
                                child: Text('No se encontraron clientes'))
                            : ListView.separated(
                                itemCount: _customers.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final customer = _customers[index];
                                  return ListTile(
                                    title: Text(customer.name),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (customer.rut.isNotEmpty)
                                          Text('RUT: ${customer.rut}'),
                                        if ((customer.email ?? '').isNotEmpty)
                                          Text(customer.email!),
                                        if ((customer.phone ?? '').isNotEmpty)
                                          Text(customer.phone!),
                                      ],
                                    ),
                                    onTap: () =>
                                        Navigator.of(context).pop(customer),
                                  );
                                },
                              ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
                : _isHovered
                    ? theme.colorScheme.surfaceContainerHigh
                    : Colors.transparent,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            border: widget.isSelected
                ? Border(
                    left: BorderSide(color: theme.dividerColor, width: 1),
                    top: BorderSide(color: theme.dividerColor, width: 1),
                    right: BorderSide(color: theme.dividerColor, width: 1),
                  )
                : null,
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
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color:
                          theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
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
