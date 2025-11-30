import 'dart:async';

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

  // Form controllers
  final _clientRequestController = TextEditingController();
  final _diagnosisController = TextEditingController();
  final _technicianNotesController = TextEditingController();
  final _discountController = TextEditingController(text: '0');
  final _estimatedDurationController = TextEditingController();

  // Form state
  Customer? _selectedCustomer;
  Bike? _selectedBike;
  JobPriority _selectedPriority = JobPriority.normal;
  JobStatus _selectedStatus = JobStatus.pendiente;
  JobStatusCustom? _selectedCustomStatus; // Custom status from job_statuses table
  List<JobStatusCustom> _customStatuses = []; // All available custom statuses
  DateTime? _selectedDeadline;
  DateTime _selectedArrivalDate = DateTime.now(); // Arrival date (editable)
  bool _requiresApproval = false;
  bool _isWarrantyJob = false;
  TaxTreatment _taxTreatment = TaxTreatment.noTax; // Default: no tax (matches sales invoice)

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
    _loadInitialData();
  }

  @override
  void dispose() {
    _clientRequestController.dispose();
    _diagnosisController.dispose();
    _technicianNotesController.dispose();
    _discountController.dispose();
    _estimatedDurationController.dispose();
    _partAutocompleteFocus.dispose();
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

      // Load customers
      final customers = await customerService.getCustomers();

      // Load products
      final products = await inventoryService.getProducts();
      final serviceProducts = products
          .where((product) => product.productType == ProductType.service)
          .toList();

      // Load custom statuses (ensure they're loaded)
      await jobStatusService.loadStatuses();
      final customStatuses = jobStatusService.activeStatuses;
      debugPrint('📋 Loaded ${customStatuses.length} custom statuses');

      if (mounted) {
        setState(() {
          _customers = customers.cast<Customer>();
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

      // Select bike
      final bike = _bikes.firstWhere((b) => b.id == job.bikeId);

      // Load items (parts + services)
      final items = await bikeshopService.getJobItems(job.id!);

      // Load tax treatment from job itself (primary source)
      TaxTreatment loadedTaxTreatment = job.taxTreatment;
      debugPrint('✅ Tax treatment loaded from job: $loadedTaxTreatment');

      // Prepare part items outside setState to avoid async operations inside
      final List<_JobPartItem> partItems = [];
      for (final item in items) {
        Product? product;
        if (item.productId != null) {
          try {
            product = _products.firstWhere((p) => p.id == item.productId);
          } catch (_) {
            // Fetch from catalog if missing in local cache
            try {
              product = await inventoryService.getProductById(item.productId!);
            } catch (e) {
              debugPrint('⚠️ Could not fetch product ${item.productId}: $e');
            }
          }

          product ??= Product(
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

        partItems.add(_JobPartItem(
          product: product,
          name: item.productName,
          isCatalogProduct: item.productId != null,
          quantity: item.quantity.toInt(),
          unitPrice: item.unitPrice,
          notes: item.notes,
        ));
      }

      if (mounted) {
        setState(() {
          _existingJob = job;
          _selectedCustomer = customer;
          _selectedBike = bike;
          _selectedPriority = job.priority;
          _selectedStatus = job.status;
          // Load custom status if available
          debugPrint('🔍 Loading custom status: statusId=${job.statusId}, customStatus=${job.customStatus?.name}');
          debugPrint('🔍 Available custom statuses: ${_customStatuses.map((s) => '${s.id}:${s.name}').join(', ')}');
          if (job.customStatus != null) {
            debugPrint('✅ Using job.customStatus: ${job.customStatus!.name}');
            _selectedCustomStatus = job.customStatus;
          } else if (job.statusId != null && _customStatuses.isNotEmpty) {
            // Try to find by ID
            debugPrint('🔍 Looking for status by ID: ${job.statusId}');
            final found = _customStatuses.where((s) => s.id == job.statusId);
            if (found.isNotEmpty) {
              _selectedCustomStatus = found.first;
              debugPrint('✅ Found status by ID: ${_selectedCustomStatus?.name}');
            } else {
              debugPrint('⚠️ Status ID ${job.statusId} not found in custom statuses, keeping default');
            }
          } else {
            debugPrint('⚠️ No statusId or customStatus on job, keeping default: ${_selectedCustomStatus?.name}');
          }
          _selectedDeadline = job.deadline;
          _selectedArrivalDate = job.arrivalDate;
          _requiresApproval = job.requiresApproval;
          _isWarrantyJob = job.isWarrantyJob;
          _taxTreatment = loadedTaxTreatment; // ← Set the loaded tax treatment

          _clientRequestController.text = job.clientRequest ?? '';
          _diagnosisController.text = job.diagnosis ?? '';
          _technicianNotesController.text = job.notes ?? '';
          _discountController.text = job.discountAmount.toString();
          _estimatedDurationController.text = '';

          _partItems
            ..clear()
            ..addAll(partItems);
          _serviceItems.clear();
        });
      }
    } catch (e) {
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

  void _addCatalogPart(Product product) {
    // Always add as new line (allow duplicates on different lines)
    setState(() {
      _partItems.add(_JobPartItem(
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
      _partItems.add(_JobPartItem(
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
      _partItems.add(_JobPartItem(
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
              subtitle: const Text('Busca en catálogo o ingresa uno personalizado'),
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

  double get _partsCost {
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

    if (_selectedBike == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe seleccionar una bicicleta')),
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

      // Create MechanicJob object
      final job = MechanicJob(
        id: widget.jobId,
        tenantId: tenantId,
        jobNumber:
            _existingJob?.jobNumber ?? '', // Will be auto-generated if empty
        customerId: _selectedCustomer!.id!,
        bikeId: _selectedBike!.id!,
        priority: _selectedPriority,
        status: _selectedStatus,
        statusId: _selectedCustomStatus?.id, // Custom status ID
        // Use selected arrival date (editable by user)
        arrivalDate: _selectedArrivalDate,
        // CRITICAL: Preserve original created_at when updating
        createdAt: _existingJob?.createdAt ?? DateTime.now(),
        clientRequest: _clientRequestController.text.trim().isEmpty
            ? null
            : _clientRequestController.text.trim(),
        diagnosis: _diagnosisController.text.trim().isEmpty
            ? null
            : _diagnosisController.text.trim(),
        notes: _technicianNotesController.text.trim().isEmpty
            ? null
            : _technicianNotesController.text.trim(),
        deadline: _selectedDeadline,
        requiresApproval: _requiresApproval,
        isWarrantyJob: _isWarrantyJob,
        discountAmount: _discountAmount,
        estimatedCost: 0,
        finalCost: 0,
        partsCost: 0,
        laborCost: 0,
        taxAmount: 0,
        totalCost: 0,
        taxTreatment: _taxTreatment,  // ← Add tax treatment
        // CRITICAL: Preserve invoice_id and invoice flags when updating!
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

      // Save items (products + services)
      if (widget.jobId != null) {
        final existingItems = await bikeshopService.getJobItems(jobId);
        for (final existing in existingItems) {
          if (existing.id != null) {
            await bikeshopService.deleteJobItem(existing.id!);
          }
        }
      }

      // Add new products/parts
      final taskService = Provider.of<SmartTaskService>(context, listen: false);
      
      for (final item in _partItems) {
        final quantity = item.quantity.toDouble();
        final unitPrice = item.unitPrice;
        final jobItem = MechanicJobItem(
          jobId: jobId,
          tenantId: tenantId,
          productId: item.product?.id, // Nullable for ad-hoc items
          productName: item.name,
          productSku: item.sku ?? '',
          quantity: quantity,
          unitPrice: unitPrice,
          totalPrice: quantity * unitPrice,
          itemType: 'product',
        );
        final created = await bikeshopService.createJobItem(jobItem);
        
        // 🤖 Auto-generate tasks from product description if available
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
            debugPrint('⚠️ Failed to generate auto-tasks for ${item.name}: $e');
          }
        }
      }

      // Add new services (stored as mechanic_job_items)
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
          notes: 'Labor: ${hoursWorked.toStringAsFixed(1)}h @ \$${hourlyRate.toStringAsFixed(0)}/hr',
        );

        final created = await bikeshopService.createJobItem(jobServiceItem);
        
        // 🤖 Auto-generate tasks from service product description if available
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
            debugPrint('✅ Auto-tasks generated for service ${name}');
          } catch (e) {
            debugPrint('⚠️ Failed to generate auto-tasks for service ${name}: $e');
          }
        }
      }

      // AFTER all items are updated, sync to invoice if it exists
      if (_existingJob?.invoiceId != null) {
        debugPrint('🔄 Syncing job to invoice: ${_existingJob!.invoiceId}');
        await bikeshopService.syncJobToInvoice(jobId);
        
        // Also update the invoice's tax treatment to match the pega
        debugPrint('💰 Current tax treatment: $_taxTreatment');
        await _updateInvoiceTaxTreatment(_existingJob!.invoiceId!);
      } else {
        debugPrint('⚠️ No invoice linked to this job');
      }

      // Create invoice AFTER items are added (awesome feature!)
      // Only for new jobs to avoid recreating invoices on edits
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
        // Pop back and force refresh by passing true
        if (context.canPop()) {
          context.pop(true); // Signal that data changed
        } else {
          // Navigate to pegas list if we can't pop
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
      final databaseService = Provider.of<DatabaseService>(context, listen: false);
      
      // Fetch the current invoice
      final invoiceData = await databaseService.selectById('sales_invoices', invoiceId);
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
      
      debugPrint('🔄 Updating invoice tax treatment: $currentTaxTreatment → $_taxTreatment');
      
      // Recalculate invoice totals based on new tax treatment
      // Note: subtotal stays the same (sum of line items), we only change net_amount and iva_amount
      final subtotal = invoice.subtotal;
      double netAmount;
      double ivaAmount;
      final total = subtotal; // Total is always the subtotal (what customer pays)
      
      if (_taxTreatment == TaxTreatment.noTax) {
        // No tax: net = full subtotal, iva = 0
        netAmount = subtotal;
        ivaAmount = 0;
      } else {
        // Tax included: net = subtotal ÷ 1.19, iva = subtotal - net
        netAmount = subtotal / 1.19;
        ivaAmount = subtotal - netAmount;
      }
      
      debugPrint('💰 Recalculated: subtotal=$subtotal, net=$netAmount, iva=$ivaAmount, total=$total');
      
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
    if (_selectedCustomer == null || _selectedBike == null || _existingJob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay datos suficientes para enviar mensaje')),
      );
      return;
    }

    // Check if customer has phone number
    if (_selectedCustomer!.phone == null || _selectedCustomer!.phone!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El cliente no tiene número de teléfono registrado')),
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
    if (_selectedCustomer == null || _selectedBike == null || _existingJob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay datos suficientes para enviar mensaje')),
      );
      return;
    }

    // Check if customer has phone number
    if (_selectedCustomer!.phone == null || _selectedCustomer!.phone!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El cliente no tiene número de teléfono registrado')),
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
            content: Text('WhatsApp abierto - Notifica al cliente que su bici está lista'),
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
                  ? const Center(child: CircularProgressIndicator())
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
          if (isEditing && _selectedCustomer != null && _selectedBike != null) ...[
            // Show "Ready for Pickup" button if job is finished
            if (_selectedStatus == JobStatus.finalizado || _selectedStatus == JobStatus.entregado)
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
                // LEFT COLUMN - Details and Products (main content)
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildSectionCard(
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
                          icon: Icons.pedal_bike,
                          title: 'Cliente y Bicicleta',
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
                  icon: Icons.pedal_bike,
                  title: 'Cliente y Bicicleta',
                  child: _buildCustomerBikeSection(),
                ),
                const SizedBox(height: 16),
                _buildSectionCard(
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
              errorText: _selectedCustomer == null && _formKey.currentState != null
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
              // Bike list
              ..._bikes.map((bike) => PopupMenuItem<String>(
                    value: 'bike_${bike.id}',
                    child: Text(
                      '${bike.displayName}${bike.serialNumber != null ? ' (S/N: ${bike.serialNumber})' : ''}',
                    ),
                    onTap: () {
                      setState(() {
                        _selectedBike = bike;
                      });
                    },
                  )),
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
                    // Auto-select the newly created bike
                    if (newBike != null) {
                      _selectedBike = _bikes.firstWhere(
                        (bike) => bike.id == newBike.id,
                        orElse: () => newBike,
                      );
                    }
                  });

                  if (mounted && newBike != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            'Bicicleta "${newBike.displayName}" creada exitosamente'),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                            _selectedStatus = _mapPhaseToJobStatus(status.phase);
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
                        ? DateFormat('dd/MM/yyyy')
                            .format(_selectedDeadline!)
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
                  FilteringTextInputFormatter.allow(
                      RegExp(r'^\d+\.?\d{0,2}')),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _clientRequestController,
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
          controller: _diagnosisController,
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
          controller: _technicianNotesController,
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
          children: [
            Expanded(
              child: CheckboxListTile(
                title: const Text('Requiere aprobación del cliente'),
                value: _requiresApproval,
                onChanged: (value) {
                  setState(() {
                    _requiresApproval = value ?? false;
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
            Expanded(
              child: CheckboxListTile(
                title: const Text('Trabajo de garantía'),
                value: _isWarrantyJob,
                onChanged: (value) {
                  setState(() {
                    _isWarrantyJob = value ?? false;
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
                        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.2)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Table header
                          Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                            ),
                            child: Row(
                              children: [
                                // # column
                                Container(
                                  width: _colIndexWidth,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text('#', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                                  ),
                                ),
                                
                                // Repuesto column (flex)
                                Expanded(
                                  child: Container(
                                    constraints: const BoxConstraints(minWidth: 250),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                                      ),
                                    ),
                                    child: Text(
                                      'PRODUCTO / SERVICIO',
                                      style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ),
                                
                                // Cantidad column
                                Container(
                                  width: _colQuantityWidth,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text('CANTIDAD', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                                  ),
                                ),
                                
                                // Precio column
                                Container(
                                  width: _colPriceWidth,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text('PRECIO UNIT.', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                                  ),
                                ),
                                
                                // Total column
                                Container(
                                  width: _colTotalWidth,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  child: Text('TOTAL', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600), textAlign: TextAlign.right),
                                ),
                                
                                // Actions column
                                SizedBox(width: _colActionsWidth),
                              ],
                            ),
                          ),
                          
                          // Header/Content divider
                          Divider(height: 1, thickness: 1, color: theme.colorScheme.outline.withOpacity(0.2)),
                          
                          // Part items, labor items, and add row
                          Column(
                            children: [
                              // Existing part items
                              if (_partItems.isNotEmpty)
                                ..._partItems.asMap().entries.map((entry) => 
                                  _buildPartRow(theme, entry.key + 1, entry.value, entry.key)
                                ),
                              
                              // Existing service items (displayed after parts)
                              if (_serviceItems.isNotEmpty)
                                ..._serviceItems.asMap().entries.map((entry) => 
                                  _buildServiceRow(theme, _partItems.length + entry.key + 1, entry.value, entry.key)
                                ),
                              
                              // Add new part row (always show)
                              Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: _partItems.isNotEmpty 
                                        ? BorderSide(color: theme.colorScheme.outline.withOpacity(0.2))
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
                                            right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                                          ),
                                        ),
                                      ),
                                      
                                      // Product autocomplete field
                                      Expanded(
                                        child: Container(
                                          constraints: const BoxConstraints(minWidth: 250),
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            border: Border(
                                              right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                                            ),
                                          ),
                                          child: ProductAutocompleteField(
                                            key: ValueKey(_partAutocompleteKey),
                                            focusNode: _partAutocompleteFocus,
                                            onProductSelected: (selection) {
                                              if (selection.isCatalogProduct && selection.product != null) {
                                                _addCatalogPart(selection.product!);
                                              } else if (!selection.isCatalogProduct) {
                                                _addCustomPart(selection.displayText);
                                              }
                                            },
                                            allowCustomItems: true,
                                            labelText: 'Agregar repuesto o parte',
                                            hintText: 'Buscar en catálogo o escribir personalizado...',
                                          ),
                                        ),
                                      ),
                                      
                                      // Empty columns for alignment
                                      Container(
                                        width: _colQuantityWidth,
                                        decoration: BoxDecoration(
                                          border: Border(
                                            right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                                          ),
                                        ),
                                      ),
                                      Container(
                                        width: _colPriceWidth,
                                        decoration: BoxDecoration(
                                          border: Border(
                                            right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
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
  Widget _buildPartRow(ThemeData theme, int index, _JobPartItem item, int itemIndex) {
    return LineRowWrapper(
      key: ValueKey('part_${item.hashCode}_$index'),
      index: index,
      canMoveUp: itemIndex > 0,
      canMoveDown: itemIndex < _partItems.length - 1,
      onMoveUp: () {
        if (itemIndex > 0) {
          setState(() {
            final temp = _partItems[itemIndex];
            _partItems[itemIndex] = _partItems[itemIndex - 1];
            _partItems[itemIndex - 1] = temp;
          });
        }
      },
      onMoveDown: () {
        if (itemIndex < _partItems.length - 1) {
          setState(() {
            final temp = _partItems[itemIndex];
            _partItems[itemIndex] = _partItems[itemIndex + 1];
            _partItems[itemIndex + 1] = temp;
          });
        }
      },
      onRemove: () => setState(() => _partItems.removeAt(itemIndex)),
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
            key: ValueKey('smart_product_${item.hashCode}'),
            initialData: item.product != null || item.name.isNotEmpty
                ? ProductFieldData(
                    product: item.product,
                    productName: item.displayName.isNotEmpty ? item.displayName : null,
                    productSku: item.sku,
                    isCatalogProduct: item.isCatalogProduct,
                    description: item.notes,
                  )
                : null,
            enabled: true,
            showCost: true, // Pegas use cost, not price
            allowCustomItems: true,
            autoFocus: item.product == null && item.name.isEmpty, // Auto-focus empty rows
            onAutoAddLine: () {
              // Auto-add new line when product is selected
              _addEmptyPartLine();
            },
            onProductChanged: (selection) {
              setState(() {
                if (selection == null) {
                  // Product cleared - reset the item
                  _partItems[itemIndex] = _JobPartItem(
                    product: null,
                    name: '',
                    isCatalogProduct: false,
                    quantity: 1,
                    unitPrice: 0,
                  );
                } else {
                  // Product selected or updated
                  _partItems[itemIndex] = _JobPartItem(
                    product: selection.product,
                    name: selection.productName ?? '',
                    isCatalogProduct: selection.isCatalogProduct,
                    quantity: item.quantity,
                    unitPrice: selection.product?.cost ?? item.unitPrice,
                    notes: selection.description,
                  );
                }
              });
            },
          ),
        ),
        
        // Cantidad column
        LineColumn(
          width: _colQuantityWidth,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Center(
            child: TextFormField(
              initialValue: item.quantity.toString(),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(),
              ),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              onChanged: (value) {
                final newQty = int.tryParse(value) ?? 1;
                setState(() {
                  _partItems[itemIndex] = _JobPartItem(
                    product: item.product,
                    name: item.name,
                    isCatalogProduct: item.isCatalogProduct,
                    quantity: newQty,
                    unitPrice: item.unitPrice,
                    notes: item.notes,
                  );
                });
              },
            ),
          ),
        ),
        
        // Precio column - EDITABLE
        LineColumn(
          width: _colPriceWidth,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: TextFormField(
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
              setState(() {
                _partItems[itemIndex] = _JobPartItem(
                  product: item.product,
                  name: item.name,
                  isCatalogProduct: item.isCatalogProduct,
                  quantity: item.quantity,
                  unitPrice: newPrice,
                  notes: item.notes,
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
            NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(item.quantity * item.unitPrice),
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
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
                        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.2)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Table header
                          Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                            ),
                            child: Row(
                              children: [
                                // # column
                                Container(
                                  width: _colIndexWidth,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text('#', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                                  ),
                                ),
                                
                                // Descripción column (flex)
                                Expanded(
                                  child: Container(
                                    constraints: const BoxConstraints(minWidth: 250),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                                      ),
                                    ),
                                    child: Text(
                                      'DESCRIPCIÓN',
                                      style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ),
                                
                                // Fecha column
                                Container(
                                  width: _colDateWidth,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text('FECHA', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                                  ),
                                ),
                                
                                // Horas column
                                Container(
                                  width: _colHoursWidth,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text('HORAS', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                                  ),
                                ),
                                
                                // Tarifa column
                                Container(
                                  width: _colRateWidth,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text('TARIFA/H', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                                  ),
                                ),
                                
                                // Total column
                                Container(
                                  width: _colTotalWidth,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  child: Text('TOTAL', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600), textAlign: TextAlign.right),
                                ),
                                
                                // Actions column
                                SizedBox(width: _colActionsWidth),
                              ],
                            ),
                          ),
                          
                          // Header/Content divider
                          Divider(height: 1, thickness: 1, color: theme.colorScheme.outline.withOpacity(0.2)),
                          
                          // Labor items
                          Column(
                            children: [
                              // Existing labor items
                              if (_serviceItems.isNotEmpty)
                                ..._serviceItems.asMap().entries.map((entry) => 
                                  _buildServiceRow(theme, entry.key + 1, entry.value, entry.key)
                                ),
                              
                              // Add labor button row (always show)
                              Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: _serviceItems.isNotEmpty 
                                        ? BorderSide(color: theme.colorScheme.outline.withOpacity(0.2))
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
                                            right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                                          ),
                                        ),
                                      ),
                                      
                                      // Add labor button spanning remaining columns
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          child: FilledButton.icon(
                                            onPressed: _addServiceItem,
                                            icon: const Icon(Icons.add, size: 18),
                                            label: const Text('Agregar Mano de Obra'),
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
  Widget _buildServiceRow(ThemeData theme, int index, _JobServiceItem item, int itemIndex) {
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
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: theme.colorScheme.outline.withOpacity(0.3)),
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
            NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(item.total),
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
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
            const Text('Descuento:',
                style: TextStyle(fontSize: 16)),
            SizedBox(
              width: 150,
              child: TextFormField(
                controller: _discountController,
                decoration: const InputDecoration(
                  prefixText: '\$ ',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'^\d+\.?\d{0,2}')),
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
            const Text('Tratamiento de IVA:',
                style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            DropdownButtonFormField<TaxTreatment>(
              value: _taxTreatment,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
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
                context
                    .push('/sales/invoices/${_existingJob!.invoiceId}/edit');
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
  final Product? product; // Nullable for ad-hoc items
  final String name; // For ad-hoc items
  final bool isCatalogProduct;
  final int quantity;
  double unitPrice; // MUTABLE - allow price editing
  String? notes; // MUTABLE - allow notes editing

  _JobPartItem({
    this.product,
    required this.name,
    this.isCatalogProduct = true,
    required this.quantity,
    required this.unitPrice,
    this.notes,
  });

  String get displayName => product?.name ?? name;
  String? get sku => product?.sku;
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
  final Function(ProductSelection selection, int quantity, double price, String? notes) onItemAdded;

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
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                  ),
                ),
              ],
            ),
            
            // Stock warning for catalog products
            if (_selection?.isCatalogProduct == true && _selection?.product != null)
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
            if (_selection == null && _productTextController.text.trim().isNotEmpty) {
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
            
            if (_selection == null || _productTextController.text.trim().isEmpty) {
              errorMessage = 'Por favor seleccione o ingrese un producto';
            } else if (_quantityController.text.isEmpty || int.tryParse(_quantityController.text) == null) {
              errorMessage = 'Por favor ingrese una cantidad válida';
            } else if (_priceController.text.isEmpty || double.tryParse(_priceController.text) == null) {
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
                _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
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
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                icon: Icon(_showCreateForm ? Icons.expand_less : Icons.person_add),
                label: Text(_showCreateForm ? 'Cancelar' : 'Crear cliente nuevo'),
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
                    color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
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
            if (_isSearching) const LinearProgressIndicator(minHeight: 2),
            
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
                    ? const Center(child: Text('No se encontraron clientes'))
                    : ListView.separated(
                        itemCount: _customers.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final customer = _customers[index];
                          return ListTile(
                            title: Text(customer.name),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (customer.rut.isNotEmpty)
                                  Text('RUT: ${customer.rut}'),
                                if ((customer.email ?? '').isNotEmpty)
                                  Text(customer.email!),
                                if ((customer.phone ?? '').isNotEmpty)
                                  Text(customer.phone!),
                              ],
                            ),
                            onTap: () => Navigator.of(context).pop(customer),
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
