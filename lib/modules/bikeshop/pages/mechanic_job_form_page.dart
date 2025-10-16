import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../modules/crm/models/crm_models.dart';
import '../../../shared/models/product.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/services/inventory_service.dart';
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
  
  // Data
  List<Customer> _customers = [];
  List<Bike> _bikes = [];
  List<Product> _products = [];
  
  // Loading states
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isLoadingCustomers = true;
  bool _isLoadingProducts = true;
  
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
      final customerService = Provider.of<CustomerService>(context, listen: false);
      final bikeshopService = Provider.of<BikeshopService>(context, listen: false);
      final inventoryService = Provider.of<InventoryService>(context, listen: false);
      
      // Load customers
      final customers = await customerService.getCustomers();
      
      // Load products
      final products = await inventoryService.getProducts();
      
      setState(() {
        _customers = customers.cast<Customer>();
        _products = products;
        _isLoadingCustomers = false;
        _isLoadingProducts = false;
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
      final bikeshopService = Provider.of<BikeshopService>(context, listen: false);
      
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
              name: part.productName ?? 'Producto eliminado',
              sku: 'N/A',
              price: part.unitPrice,
              cost: 0,
              stockQuantity: 0,
              category: ProductCategory.other,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
          _partItems.add(_JobPartItem(
            product: product,
            quantity: part.quantity.toInt(),
            unitPrice: part.unitPrice,
          ));
        }
        
        // Convert labor to form items
        _laborItems.clear();
        for (final l in labor) {
          _laborItems.add(_JobLaborItem(
            description: l.description ?? '',
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
    final bikeshopService = Provider.of<BikeshopService>(context, listen: false);
    
    // Load customer bikes
    final bikes = await bikeshopService.getBikes(customerId: customer.id);
    
    setState(() {
      _selectedCustomer = customer;
      _bikes = bikes;
      _selectedBike = null; // Reset bike selection
    });
  }
  
  void _addPartItem() {
    showDialog(
      context: context,
      builder: (context) => _ProductSelectorDialog(
        products: _products,
        onProductSelected: (product, quantity, price) {
          setState(() {
            _partItems.add(_JobPartItem(
              product: product,
              quantity: quantity,
              unitPrice: price,
            ));
          });
        },
      ),
    );
  }
  
  void _addLaborItem() {
    showDialog(
      context: context,
      builder: (context) => _LaborEntryDialog(
        onLaborAdded: (description, hours, rate, date) {
          setState(() {
            _laborItems.add(_JobLaborItem(
              description: description,
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
    return _partItems.fold(0.0, (sum, item) => sum + (item.quantity * item.unitPrice));
  }
  
  double get _laborCost {
    return _laborItems.fold(0.0, (sum, item) => sum + (item.hours * item.hourlyRate));
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
      final bikeshopService = Provider.of<BikeshopService>(context, listen: false);
      
      // Create MechanicJob object
      final job = MechanicJob(
        id: widget.jobId,
        jobNumber: _existingJob?.jobNumber ?? '', // Will be auto-generated if empty
        customerId: _selectedCustomer!.id!,
        bikeId: _selectedBike!.id!,
        priority: _selectedPriority,
        status: _selectedStatus,
        arrivalDate: DateTime.now(),
        clientRequest: _clientRequestController.text.trim().isEmpty ? null : _clientRequestController.text.trim(),
        diagnosis: _diagnosisController.text.trim().isEmpty ? null : _diagnosisController.text.trim(),
        notes: _technicianNotesController.text.trim().isEmpty ? null : _technicianNotesController.text.trim(),
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
        final jobItem = MechanicJobItem(
          jobId: jobId,
          productId: item.product.id!,
          productName: item.product.name,
          quantity: item.quantity.toDouble(),
          unitPrice: item.unitPrice,
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
        final jobLabor = MechanicJobLabor(
          jobId: jobId,
          technicianName: 'Mecánico', // TODO: Get from current user
          description: item.description,
          hoursWorked: item.hours.toDouble(),
          hourlyRate: item.hourlyRate,
          workDate: item.date,
        );
        await bikeshopService.createJobLabor(jobLabor);
      }

      // Create invoice AFTER items are added (awesome feature!)
      // Only for new jobs to avoid recreating invoices on edits
      if (widget.jobId == null) {
        await bikeshopService.createInvoiceFromJob(jobId);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.jobId != null ? 'Pega actualizada correctamente' : 'Pega creada correctamente'),
            backgroundColor: Colors.green,
          ),
        );
        context.pop();
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
        final bikeshopService = Provider.of<BikeshopService>(context, listen: false);
        await bikeshopService.deleteBike(bike.id!);
        
        // Reload bikes
        final bikes = await bikeshopService.getBikes(customerId: _selectedCustomer!.id);
        
        setState(() {
          _bikes = bikes;
          if (_selectedBike?.id == bike.id) {
            _selectedBike = null; // Clear selection if deleted bike was selected
          }
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Bicicleta "${bike.displayName}" eliminada correctamente'),
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
                          
                          final result = await showDialog<Bike?>(
                            context: context,
                            builder: (context) => BikeFormDialog(
                              customerId: _selectedCustomer!.id!,
                              bike: bike,
                            ),
                          );
                          
                          // Refresh bike list if edited (result != null) or deleted (result == null but dialog was closed after action)
                          // We check if dialog returned (result is not false) to refresh
                          final bikeshopService = Provider.of<BikeshopService>(context, listen: false);
                          final bikes = await bikeshopService.getBikes(customerId: _selectedCustomer!.id);
                          setState(() {
                            _bikes = bikes;
                            // Clear selection if deleted bike was selected
                            if (_selectedBike?.id == bike.id && !bikes.any((b) => b.id == bike.id)) {
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
                    _buildPartsSection(),
                    const SizedBox(height: 24),
                    _buildLaborSection(),
                    const SizedBox(height: 24),
                    _buildCostSummary(),
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
                    validator: (value) => value == null ? 'Seleccione un cliente' : null,
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
                      final bikeshopService = Provider.of<BikeshopService>(context, listen: false);
                      final bikes = await bikeshopService.getBikes(customerId: _selectedCustomer!.id);
                      
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
                            content: Text('Bicicleta "${newBike.displayName}" creada exitosamente'),
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
                    onPressed: _bikes.isEmpty ? null : () => _showBikeManagementDialog(),
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
                  child: Text('${bike.displayName} ${bike.serialNumber != null ? '(S/N: ${bike.serialNumber})' : ''}'),
                );
              }).toList(),
              onChanged: widget.jobId != null
                  ? null // Disable editing bike in edit mode
                  : (bike) {
                      setState(() {
                        _selectedBike = bike;
                      });
                    },
              validator: (value) => value == null ? 'Seleccione una bicicleta' : null,
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
                        initialDate: _selectedDeadline ?? DateTime.now().add(const Duration(days: 7)),
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
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Repuestos y Partes',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                ElevatedButton.icon(
                  onPressed: _addPartItem,
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar Repuesto'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_partItems.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.build_circle_outlined, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No hay repuestos agregados',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              )
            else
              Table(
                border: TableBorder.all(color: Colors.grey[300]!),
                columnWidths: const {
                  0: FlexColumnWidth(3),
                  1: FlexColumnWidth(1),
                  2: FlexColumnWidth(1.5),
                  3: FlexColumnWidth(1.5),
                  4: FixedColumnWidth(60),
                },
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: Colors.grey[200]),
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Producto', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Cant.', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Precio Unit.', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  ..._partItems.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    return TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                              Text(
                                'SKU: ${item.product.sku} | Stock: ${item.product.stockQuantity}',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(item.quantity.toString()),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(item.unitPrice)),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(item.quantity * item.unitPrice),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              setState(() {
                                _partItems.removeAt(index);
                              });
                            },
                            iconSize: 20,
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildLaborSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Mano de Obra',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                ElevatedButton.icon(
                  onPressed: _addLaborItem,
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar Mano de Obra'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_laborItems.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.work_outline, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No hay mano de obra registrada',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              )
            else
              Table(
                border: TableBorder.all(color: Colors.grey[300]!),
                columnWidths: const {
                  0: FlexColumnWidth(3),
                  1: FlexColumnWidth(1.5),
                  2: FlexColumnWidth(1),
                  3: FlexColumnWidth(1.5),
                  4: FlexColumnWidth(1.5),
                  5: FixedColumnWidth(60),
                },
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: Colors.grey[200]),
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Descripción', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Fecha', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Horas', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Tarifa/Hora', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  ..._laborItems.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    return TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(item.description),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(DateFormat('dd/MM/yyyy').format(item.date)),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(item.hours.toStringAsFixed(2)),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(item.hourlyRate)),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(item.hours * item.hourlyRate),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              setState(() {
                                _laborItems.removeAt(index);
                              });
                            },
                            iconSize: 20,
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCostSummary() {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
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
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
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
                          const Text('Descuento:', style: TextStyle(fontSize: 16)),
                          SizedBox(
                            width: 150,
                            child: TextFormField(
                              controller: _discountController,
                              decoration: const InputDecoration(
                                prefixText: '\$ ',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                      const SizedBox(height: 8),
                      _buildCostRow('IVA (19%):', _taxAmount, false),
                      const Divider(thickness: 2),
                      _buildCostRow('TOTAL:', _total, true, fontSize: 20),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCostRow(String label, double amount, bool bold, {double fontSize = 16}) {
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
                        context.push('/sales/invoices/${_existingJob!.invoiceId}');
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
  final Product product;
  final int quantity;
  final double unitPrice;
  
  _JobPartItem({
    required this.product,
    required this.quantity,
    required this.unitPrice,
  });
}

class _JobLaborItem {
  final String description;
  final double hours;
  final double hourlyRate;
  final DateTime date;
  
  _JobLaborItem({
    required this.description,
    required this.hours,
    required this.hourlyRate,
    required this.date,
  });
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
                  child: Text('${product.name} (${product.sku}) - Stock: ${product.stockQuantity}'),
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
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
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
            if (_selectedProduct != null && _quantityController.text.isNotEmpty && _priceController.text.isNotEmpty) {
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
  final Function(String description, double hours, double rate, DateTime date) onLaborAdded;
  
  const _LaborEntryDialog({
    required this.onLaborAdded,
  });
  
  @override
  State<_LaborEntryDialog> createState() => _LaborEntryDialogState();
}

class _LaborEntryDialogState extends State<_LaborEntryDialog> {
  final _descriptionController = TextEditingController();
  final _hoursController = TextEditingController();
  final _rateController = TextEditingController(text: '15000'); // Default rate
  DateTime _selectedDate = DateTime.now();
  
  @override
  void dispose() {
    _descriptionController.dispose();
    _hoursController.dispose();
    _rateController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar Mano de Obra'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
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
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
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
            if (_descriptionController.text.isNotEmpty &&
                _hoursController.text.isNotEmpty &&
                _rateController.text.isNotEmpty) {
              widget.onLaborAdded(
                _descriptionController.text,
                double.parse(_hoursController.text),
                double.parse(_rateController.text),
                _selectedDate,
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
