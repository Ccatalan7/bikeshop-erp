import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../modules/crm/models/crm_models.dart';
import '../../../shared/models/product.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/product_autocomplete_field.dart';
import '../../../shared/services/inventory_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../modules/crm/services/customer_service.dart';
import '../services/bikeshop_service.dart';
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
  DateTime? _selectedDeadline;
  bool _requiresApproval = false;
  bool _isWarrantyJob = false;

  // Parts and labor
  final List<_JobPartItem> _partItems = [];
  final List<_JobLaborItem> _laborItems = [];

  // Key to reset autocomplete field after adding product
  int _partAutocompleteKey = 0;

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

      // Load customers
      final customers = await customerService.getCustomers();

      // Load products
      final products = await inventoryService.getProducts();
      final serviceProducts = products
          .where((product) => product.productType == ProductType.service)
          .toList();

      setState(() {
        _customers = customers.cast<Customer>();
        _products = products;
        _serviceProducts = serviceProducts;
      });

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

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
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

      final job = await bikeshopService.getJobById(widget.jobId!);
      if (job == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pega no encontrada')),
          );
          context.pop();
        }
        return;
      }

      // Load customer and bikes
      final customer = _customers.firstWhere((c) => c.id == job.customerId);
      await _selectCustomer(customer);

      // Select bike
      final bike = _bikes.firstWhere((b) => b.id == job.bikeId);

      // Load parts and labor
      final parts = await bikeshopService.getJobItems(job.id!);
      final labor = await bikeshopService.getJobLabor(job.id!);

      setState(() {
        _existingJob = job;
        _selectedCustomer = customer;
        _selectedBike = bike;
        _selectedPriority = job.priority;
        _selectedStatus = job.status;
        _selectedDeadline = job.deadline;
        _requiresApproval = job.requiresApproval;
        _isWarrantyJob = job.isWarrantyJob;

        _clientRequestController.text = job.clientRequest ?? '';
        _diagnosisController.text = job.diagnosis ?? '';
        _technicianNotesController.text = job.notes ?? '';
        _discountController.text = job.discountAmount.toString();
        _estimatedDurationController.text = '';

        // Convert parts to form items
        _partItems.clear();
        for (final part in parts) {
          final product = _products.firstWhere(
            (p) => p.id == part.productId,
            orElse: () => Product(
              id: part.productId ?? '',
              name: part.productName,
              sku: 'N/A',
              price: part.unitPrice,
              cost: 0,
              stockQuantity: 0,
              category: ProductCategory.other,
              productType: ProductType.product,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
          _partItems.add(_JobPartItem(
            product: part.productId != null ? product : null,
            name: part.productName,
            isCatalogProduct: part.productId != null,
            quantity: part.quantity.toInt(),
            unitPrice: part.unitPrice,
            notes: null, // TODO: Load from database if stored
          ));
        }

        // Convert labor to form items
        _laborItems.clear();
        for (final l in labor) {
          Product? serviceProduct;
          if (l.serviceProductId != null) {
            try {
              serviceProduct = _serviceProducts
                  .firstWhere((p) => p.id == l.serviceProductId);
            } catch (_) {
              serviceProduct = null;
            }
          }
          _laborItems.add(_JobLaborItem(
            serviceProduct: serviceProduct,
            description: l.description ?? serviceProduct?.name ?? '',
            hours: l.hoursWorked,
            hourlyRate: l.hourlyRate,
            date: l.workDate,
          ));
        }
      });
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

  void _addLaborItem() {
    showDialog(
      context: context,
      builder: (context) => _LaborEntryDialog(
        serviceProducts: _serviceProducts,
        onLaborAdded: (serviceProduct, description, hours, rate, date) {
          setState(() {
            final trimmedDescription = description.trim();
            _laborItems.add(_JobLaborItem(
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

  double get _partsCost {
    return _partItems.fold(
        0.0, (sum, item) => sum + (item.quantity * item.unitPrice));
  }

  double get _laborCost {
    return _laborItems.fold(0.0, (sum, item) => sum + item.total);
  }

  double get _subtotal {
    return _partsCost + _laborCost;
  }

  double get _discountAmount {
    return double.tryParse(_discountController.text) ?? 0.0;
  }

  double get _taxAmount {
    return (_subtotal - _discountAmount) * 0.19; // 19% IVA
  }

  double get _total {
    return _subtotal - _discountAmount + _taxAmount;
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
        arrivalDate: DateTime.now(),
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

      // Save parts
      // First, delete existing parts if editing
      if (widget.jobId != null) {
        final existingParts = await bikeshopService.getJobItems(jobId);
        for (final part in existingParts) {
          await bikeshopService.deleteJobItem(part.id!);
        }
      }

      // Add new parts
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
        );
        await bikeshopService.createJobItem(jobItem);
      }

      // Save labor
      // First, delete existing labor if editing
      if (widget.jobId != null) {
        final existingLabor = await bikeshopService.getJobLabor(jobId);
        for (final labor in existingLabor) {
          await bikeshopService.deleteJobLabor(labor.id!);
        }
      }

      // Add new labor
      for (final item in _laborItems) {
        final hoursWorked = item.hours.toDouble();
        final hourlyRate = item.hourlyRate;
        final description = item.description.isNotEmpty
            ? item.description
            : item.serviceProduct?.name;
        final jobLabor = MechanicJobLabor(
          jobId: jobId,
          tenantId: tenantId,
          technicianName: 'Mecánico', // TODO: Get from current user
          description: description,
          hoursWorked: hoursWorked,
          hourlyRate: hourlyRate,
          totalCost: item.total,
          workDate: item.date,
          serviceProductId: item.serviceProduct?.id,
        );
        await bikeshopService.createJobLabor(jobLabor);
      }

      // AFTER all items are updated, sync to invoice if it exists
      if (_existingJob?.invoiceId != null) {
        await bikeshopService.syncJobToInvoice(jobId);
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
        // Navigate to pegas table after successful creation/update
        context.go('/taller/pegas');
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
    return MainLayout(
      title: widget.jobId != null ? 'Editar Pega' : 'Nueva Pega',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCustomerBikeSection(),
                    const SizedBox(height: 24),
                    _buildJobDetailsSection(),
                    const SizedBox(height: 24),
                    // Products/Services and Cost Summary side-by-side
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 7,
                          child: _buildPartsSection(),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          flex: 3,
                          child: _buildCostSummary(),
                        ),
                      ],
                    ),
                    if (_existingJob?.invoiceId != null) ...[
                      const SizedBox(height: 24),
                      _buildInvoiceSection(),
                    ],
                    const SizedBox(height: 32),
                    _buildActionButtons(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildCustomerBikeSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cliente y Bicicleta',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<Customer>(
                    value: _selectedCustomer,
                    decoration: const InputDecoration(
                      labelText: 'Cliente *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                    items: _customers.map((customer) {
                      return DropdownMenuItem(
                        value: customer,
                        child: Text(customer.name),
                      );
                    }).toList(),
                    onChanged: widget.jobId != null
                        ? null // Disable editing customer in edit mode
                        : (customer) {
                            if (customer != null) {
                              _selectCustomer(customer);
                            }
                          },
                    validator: (value) =>
                        value == null ? 'Seleccione un cliente' : null,
                  ),
                ),
                if (_selectedCustomer != null) ...[
                  const SizedBox(width: 16),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final newBike = await showDialog<Bike?>(
                        context: context,
                        builder: (context) => BikeFormDialog(
                          customerId: _selectedCustomer!.id!,
                        ),
                      );

                      // Reload bikes for this customer (handles both creation and any unexpected deletion)
                      final bikeshopService =
                          Provider.of<BikeshopService>(context, listen: false);
                      final bikes = await bikeshopService.getBikes(
                          customerId: _selectedCustomer!.id);

                      setState(() {
                        _bikes = bikes;
                        // Auto-select the newly created bike if it exists
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
                    icon: const Icon(Icons.add),
                    label: const Text('Nueva Bici'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _bikes.isEmpty
                        ? null
                        : () => _showBikeManagementDialog(),
                    icon: const Icon(Icons.settings),
                    label: const Text('Gestionar Bicis'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<Bike>(
              value: _selectedBike,
              decoration: const InputDecoration(
                labelText: 'Bicicleta *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.pedal_bike),
              ),
              items: _bikes.map((bike) {
                return DropdownMenuItem(
                  value: bike,
                  child: Text(
                      '${bike.displayName} ${bike.serialNumber != null ? '(S/N: ${bike.serialNumber})' : ''}'),
                );
              }).toList(),
              onChanged: widget.jobId != null
                  ? null // Disable editing bike in edit mode
                  : (bike) {
                      setState(() {
                        _selectedBike = bike;
                      });
                    },
              validator: (value) =>
                  value == null ? 'Seleccione una bicicleta' : null,
            ),
            if (_selectedBike != null && _selectedBike!.isUnderWarranty) ...[
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
        ),
      ),
    );
  }

  Widget _buildJobDetailsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Detalles de la Pega',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
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
                  child: DropdownButtonFormField<JobStatus>(
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
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
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
                const SizedBox(width: 16),
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
        ),
      ),
    );
  }

  Widget _buildPartsSection() {
    final theme = Theme.of(context);
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Productos y Servicios',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
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
                          
                          // Part items and add row
                          Column(
                            children: [
                              // Existing part items
                              if (_partItems.isNotEmpty)
                                ..._partItems.asMap().entries.map((entry) => 
                                  _buildPartRow(theme, entry.key + 1, entry.value, entry.key)
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
        ),
      ),
    );
  }

  Widget _buildPartRow(ThemeData theme, int index, _JobPartItem item, int itemIndex) {
    final isAdHoc = !item.isCatalogProduct;
    
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // # column
            Container(
              width: _colIndexWidth,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                ),
              ),
              child: Center(
                child: Text(
                  '$index',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            
            // Product details column
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minWidth: 250),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product image
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isAdHoc 
                            ? Colors.orange.shade50 
                            : theme.colorScheme.surfaceVariant.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: theme.colorScheme.outline.withOpacity(0.2),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: item.product?.imageUrl != null
                            ? Image.network(
                                item.product!.imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Icon(
                                  Icons.inventory_2_outlined,
                                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                                  size: 24,
                                ),
                              )
                            : Icon(
                                isAdHoc ? Icons.edit_note : Icons.inventory_2_outlined,
                                color: isAdHoc 
                                    ? Colors.orange 
                                    : theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                                size: 24,
                              ),
                      ),
                    ),
                    
                    const SizedBox(width: 12),
                    
                    // Product name + details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Product name with badge
                          Row(
                            children: [
                              if (isAdHoc)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'PERSONALIZADO',
                                    style: TextStyle(fontSize: 10, color: Colors.orange.shade900, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  item.displayName,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          
                          // SKU + Stock
                          if (!isAdHoc && item.sku != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'SKU: ${item.sku} | Stock: ${item.product!.stockQuantity.toInt()}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          
                          // Notes
                          if (item.notes != null && item.notes!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                item.notes!,
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
            ),
            
            // Cantidad column
            Container(
              width: _colQuantityWidth,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                ),
              ),
              child: Center(
                child: Text(
                  item.quantity.toString(),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
            
            // Precio column
            Container(
              width: _colPriceWidth,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                ),
              ),
              child: Center(
                child: Text(
                  NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(item.unitPrice),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
            
            // Total column
            Container(
              width: _colTotalWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(item.quantity * item.unitPrice),
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.right,
              ),
            ),
            
            // Actions column
            SizedBox(
              width: _colActionsWidth,
              child: Center(
                child: IconButton(
                  icon: Icon(Icons.delete_outline, size: 20, color: theme.colorScheme.error),
                  onPressed: () {
                    setState(() {
                      _partItems.removeAt(itemIndex);
                    });
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
            ),
          ],
        ),
      ),
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
                              if (_laborItems.isNotEmpty)
                                ..._laborItems.asMap().entries.map((entry) => 
                                  _buildLaborRow(theme, entry.key + 1, entry.value, entry.key)
                                ),
                              
                              // Add labor button row (always show)
                              Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: _laborItems.isNotEmpty 
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
                                            onPressed: _addLaborItem,
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

  Widget _buildLaborRow(ThemeData theme, int index, _JobLaborItem item, int itemIndex) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // # column
            Container(
              width: _colIndexWidth,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                ),
              ),
              child: Center(
                child: Text(
                  '$index',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            
            // Description column
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minWidth: 250),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                  ),
                ),
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
                          
                          // Custom description
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
            ),
            
            // Fecha column
            Container(
              width: _colDateWidth,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                ),
              ),
              child: Center(
                child: Text(
                  DateFormat('dd/MM/yyyy').format(item.date),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
            
            // Horas column
            Container(
              width: _colHoursWidth,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                ),
              ),
              child: Center(
                child: Text(
                  item.hours.toStringAsFixed(2),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
            
            // Tarifa column
            Container(
              width: _colRateWidth,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                ),
              ),
              child: Center(
                child: Text(
                  NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(item.hourlyRate),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
            
            // Total column
            Container(
              width: _colTotalWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(item.total),
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.right,
              ),
            ),
            
            // Actions column
            SizedBox(
              width: _colActionsWidth,
              child: Center(
                child: IconButton(
                  icon: Icon(Icons.delete_outline, size: 20, color: theme.colorScheme.error),
                  onPressed: () {
                    setState(() {
                      _laborItems.removeAt(itemIndex);
                    });
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCostSummary() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resumen de Costos',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Column(
              children: [
                _buildCostRow('Repuestos:', _partsCost, false),
                const SizedBox(height: 8),
                _buildCostRow('Mano de obra:', _laborCost, false),
                const Divider(),
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
                const SizedBox(height: 8),
                _buildCostRow('IVA (19%):', _taxAmount, false),
                const Divider(thickness: 2),
                _buildCostRow('TOTAL:', _total, true, fontSize: 20),
              ],
            ),
          ],
        ),
      ),
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
    return Card(
      color: Colors.green[50],
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt, color: Colors.green[700]),
                const SizedBox(width: 12),
                Text(
                  'Factura Vinculada',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green[900],
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green[300]!),
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Factura: ${_existingJob?.invoiceId ?? "N/A"}',
                    style: const TextStyle(fontSize: 14),
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
                            .push('/sales/invoices/${_existingJob!.invoiceId}');
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton(
          onPressed: _isSaving ? null : () => context.pop(),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Text('Cancelar'),
          ),
        ),
        const SizedBox(width: 16),
        ElevatedButton(
          onPressed: _isSaving ? null : _saveJob,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.jobId != null ? 'Actualizar Pega' : 'Crear Pega'),
          ),
        ),
      ],
    );
  }
}

// Helper classes for form items
class _JobPartItem {
  final Product? product; // Nullable for ad-hoc items
  final String name; // For ad-hoc items
  final bool isCatalogProduct;
  final int quantity;
  final double unitPrice;
  final String? notes; // Additional notes for any part

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

class _JobLaborItem {
  final Product? serviceProduct;
  final String description;
  final double hours;
  final double hourlyRate;
  final DateTime date;

  _JobLaborItem({
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

// Labor entry dialog
class _LaborEntryDialog extends StatefulWidget {
  final List<Product> serviceProducts;
  final void Function(
    Product? serviceProduct,
    String description,
    double hours,
    double rate,
    DateTime date,
  ) onLaborAdded;

  const _LaborEntryDialog({
    required this.serviceProducts,
    required this.onLaborAdded,
  });

  @override
  State<_LaborEntryDialog> createState() => _LaborEntryDialogState();
}

class _LaborEntryDialogState extends State<_LaborEntryDialog> {
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

            widget.onLaborAdded(
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
