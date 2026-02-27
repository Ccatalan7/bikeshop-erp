import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../tasks/models/task_model.dart';
import '../../tasks/services/task_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/services/user_management_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'task_link_dialog.dart';

class TaskFormDialog extends StatefulWidget {
  final TaskModel? taskToEdit;
  final String? prefillJobId;
  final String? prefillJobNumber;
  final String? prefillPurchaseInvoiceId;
  final String? prefillPurchaseInvoiceNumber;
  final String? prefillSalesInvoiceId;
  final String? prefillSalesInvoiceNumber;
  final String? prefillCustomerId;
  final String? prefillCustomerName;
  final String? prefillSupplierId;
  final String? prefillSupplierName;

  const TaskFormDialog({
    super.key,
    this.taskToEdit,
    this.prefillJobId,
    this.prefillJobNumber,
    this.prefillPurchaseInvoiceId,
    this.prefillPurchaseInvoiceNumber,
    this.prefillSalesInvoiceId,
    this.prefillSalesInvoiceNumber,
    this.prefillCustomerId,
    this.prefillCustomerName,
    this.prefillSupplierId,
    this.prefillSupplierName,
  });

  @override
  State<TaskFormDialog> createState() => _TaskFormDialogState();
}

class _TaskFormDialogState extends State<TaskFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _titleController;
  late TextEditingController _descriptionController;

  TaskPriority _selectedPriority = TaskPriority.normal;
  TaskStatus _selectedStatus = TaskStatus.pending;
  DateTime? _dueDate;

  String? _assignedToId;
  String? _assigneeName;

  // Manual linking state
  String? _linkedJobId;
  String? _linkedJobNumber;
  String? _linkedPurchaseInvoiceId;
  String? _linkedPurchaseInvoiceNumber;
  String? _linkedSalesInvoiceId;
  String? _linkedSalesInvoiceNumber;
  String? _linkedSupplierName;
  String? _linkedCustomerName;

  List<Map<String, dynamic>> _users = [];
  bool _isLoadingUsers = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _titleController =
        TextEditingController(text: widget.taskToEdit?.title ?? '');
    _descriptionController =
        TextEditingController(text: widget.taskToEdit?.description ?? '');

    if (widget.taskToEdit != null) {
      _selectedPriority = widget.taskToEdit!.priority;
      _selectedStatus = widget.taskToEdit!.status;
      _dueDate = widget.taskToEdit!.dueDate;
      _assignedToId = widget.taskToEdit!.assignedTo;
      _assigneeName = widget.taskToEdit!.assigneeName;

      _linkedJobId = widget.taskToEdit!.linkedJobId;
      _linkedJobNumber = widget.taskToEdit!.linkedJobNumber;
      _linkedPurchaseInvoiceId = widget.taskToEdit!.linkedPurchaseInvoiceId;
      _linkedPurchaseInvoiceNumber =
          widget.taskToEdit!.linkedPurchaseInvoiceNumber;
      _linkedSalesInvoiceId = widget.taskToEdit!.linkedSalesInvoiceId;
      _linkedSalesInvoiceNumber = widget.taskToEdit!.linkedSalesInvoiceNumber;
      _linkedCustomerName = widget.taskToEdit!.linkedCustomerName;
      _linkedSupplierName = widget.taskToEdit!.linkedSupplierName;
    } else {
      _linkedJobId = widget.prefillJobId;
      _linkedJobNumber = widget.prefillJobNumber;
      _linkedPurchaseInvoiceId = widget.prefillPurchaseInvoiceId;
      _linkedPurchaseInvoiceNumber = widget.prefillPurchaseInvoiceNumber;
      _linkedSalesInvoiceId = widget.prefillSalesInvoiceId;
      _linkedSalesInvoiceNumber = widget.prefillSalesInvoiceNumber;
      _linkedCustomerName = widget.prefillCustomerName;
      _linkedSupplierName = widget.prefillSupplierName;
    }

    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    try {
      final userService = context.read<UserManagementService>();
      final users = await userService.getTenantUsers();
      if (mounted) {
        setState(() {
          _users = users;
          _isLoadingUsers = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching users: $e');
      if (mounted) {
        setState(() => _isLoadingUsers = false);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final taskService = context.read<TaskService>();
      final activeUser = Supabase.instance.client.auth.currentUser;
      final tenantId = await context.read<TenantService>().getTenantId();

      if (activeUser == null || tenantId == null) {
        throw Exception('Usuario no autenticado o tenant no definido');
      }

      final task = TaskModel(
        id: widget.taskToEdit?.id,
        tenantId: tenantId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        priority: _selectedPriority,
        status: _selectedStatus,
        dueDate: _dueDate,
        assignedTo: _assignedToId,
        createdBy: widget.taskToEdit?.createdBy ?? activeUser.id,

        // Updated links from state (handles prefills or manual selections)
        linkedJobId: _linkedJobId,
        linkedJobNumber: _linkedJobNumber,

        linkedPurchaseInvoiceId: _linkedPurchaseInvoiceId,
        linkedPurchaseInvoiceNumber: _linkedPurchaseInvoiceNumber,

        linkedSalesInvoiceId: _linkedSalesInvoiceId,
        linkedSalesInvoiceNumber: _linkedSalesInvoiceNumber,

        linkedCustomerId: widget.taskToEdit?.linkedCustomerId ??
            widget
                .prefillCustomerId, // Optional: add customer ID to task link result later if needed
        linkedCustomerName: _linkedCustomerName,

        linkedSupplierId:
            widget.taskToEdit?.linkedSupplierId ?? widget.prefillSupplierId,
        linkedSupplierName: _linkedSupplierName,

        assigneeName: _assigneeName,
      );

      if (widget.taskToEdit == null) {
        await taskService.createTask(task);
      } else {
        await taskService.updateTask(task);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar tarea: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Dialog(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Guardando tarea...'),
            ],
          ),
        ),
      );
    }

    final isEditing = widget.taskToEdit != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      isEditing ? Icons.edit_note : Icons.add_task,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isEditing ? 'Editar Tarea' : 'Nueva Tarea',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Context Badges and Linking Area
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        children: [
                          if (_linkedJobNumber != null)
                            Chip(
                              avatar: const Icon(Icons.build, size: 16),
                              label: Text('Pega #$_linkedJobNumber'),
                              backgroundColor:
                                  Colors.blue.withValues(alpha: 0.1),
                              deleteIcon: const Icon(Icons.close, size: 16),
                              onDeleted: () => setState(() {
                                _linkedJobId = null;
                                _linkedJobNumber = null;
                                _linkedCustomerName = null;
                              }),
                            ),
                          if (_linkedPurchaseInvoiceNumber != null)
                            Chip(
                              avatar: const Icon(Icons.receipt, size: 16),
                              label:
                                  Text('Compra #$_linkedPurchaseInvoiceNumber'),
                              backgroundColor:
                                  Colors.orange.withValues(alpha: 0.1),
                              deleteIcon: const Icon(Icons.close, size: 16),
                              onDeleted: () => setState(() {
                                _linkedPurchaseInvoiceId = null;
                                _linkedPurchaseInvoiceNumber = null;
                                _linkedSupplierName = null;
                              }),
                            ),
                          if (_linkedSalesInvoiceNumber != null)
                            Chip(
                              avatar: const Icon(Icons.point_of_sale, size: 16),
                              label: Text('Venta #$_linkedSalesInvoiceNumber'),
                              backgroundColor:
                                  Colors.green.withValues(alpha: 0.1),
                              deleteIcon: const Icon(Icons.close, size: 16),
                              onDeleted: () => setState(() {
                                _linkedSalesInvoiceId = null;
                                _linkedSalesInvoiceNumber = null;
                                _linkedCustomerName = null;
                              }),
                            ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.link, size: 18),
                      label: const Text('Vincular...'),
                      onPressed: () async {
                        final result = await showDialog<TaskLinkResult>(
                          context: context,
                          builder: (context) => const TaskLinkDialog(),
                        );

                        if (result != null && mounted) {
                          setState(() {
                            if (result.type == 'job') {
                              _linkedJobId = result.id;
                              _linkedJobNumber = result.displayId;
                              _linkedCustomerName = result.displayName;
                            } else if (result.type == 'sales_invoice') {
                              _linkedSalesInvoiceId = result.id;
                              _linkedSalesInvoiceNumber = result.displayId;
                              _linkedCustomerName = result.displayName;
                            } else if (result.type == 'purchase_invoice') {
                              _linkedPurchaseInvoiceId = result.id;
                              _linkedPurchaseInvoiceNumber = result.displayId;
                              _linkedSupplierName = result.displayName;
                            }
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Título de la tarea',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v!.isEmpty ? 'Requerido' : null,
                  autofocus: true,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Descripción (Opcional)',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<TaskPriority>(
                        initialValue: _selectedPriority,
                        decoration: const InputDecoration(
                          labelText: 'Prioridad',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: TaskPriority.low, child: Text('Baja')),
                          DropdownMenuItem(
                              value: TaskPriority.normal,
                              child: Text('Normal')),
                          DropdownMenuItem(
                              value: TaskPriority.high, child: Text('Alta')),
                          DropdownMenuItem(
                              value: TaskPriority.urgent,
                              child: Text('Urgente')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedPriority = val);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<TaskStatus>(
                        initialValue: _selectedStatus,
                        decoration: const InputDecoration(
                          labelText: 'Estado',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: TaskStatus.pending,
                              child: Text('Pendiente')),
                          DropdownMenuItem(
                              value: TaskStatus.inProgress,
                              child: Text('En Curso')),
                          DropdownMenuItem(
                              value: TaskStatus.completed,
                              child: Text('Completada')),
                          DropdownMenuItem(
                              value: TaskStatus.cancelled,
                              child: Text('Cancelada')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedStatus = val);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                InkWell(
                  onTap: _selectDueDate,
                  borderRadius: BorderRadius.circular(4),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Fecha de Vencimiento',
                      border: const OutlineInputBorder(),
                      suffixIcon: _dueDate != null
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () => setState(() => _dueDate = null),
                            )
                          : const Icon(Icons.calendar_today),
                    ),
                    child: Text(
                      _dueDate != null
                          ? DateFormat('dd/MM/yyyy').format(_dueDate!)
                          : 'Sin fecha de vencimiento',
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                if (_isLoadingUsers)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else
                  DropdownButtonFormField<String?>(
                    value: _users.any((u) => u['id'] == _assignedToId)
                        ? _assignedToId
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Asignar a',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Sin asignar'),
                      ),
                      ..._users.map((user) {
                        final name = user['full_name'] as String? ??
                            user['email'] as String? ??
                            'Usuario Desconocido';
                        return DropdownMenuItem<String>(
                          value: user['id'] as String,
                          child: Text(name),
                        );
                      }),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _assignedToId = val;
                        if (val != null) {
                          final selectedUser =
                              _users.firstWhere((u) => u['id'] == val);
                          _assigneeName =
                              selectedUser['full_name'] as String? ??
                                  selectedUser['email'] as String?;
                        } else {
                          _assigneeName = null;
                        }
                      });
                    },
                  ),

                const SizedBox(height: 32),

                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 16),
                    FilledButton(
                      onPressed: _save,
                      child: Text(isEditing ? 'Actualizar' : 'Guardar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
