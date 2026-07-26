import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';

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

  // Attachments
  List<Map<String, dynamic>> _existingAttachments = [];
  final List<_PendingAttachment> _pendingAttachments = [];
  bool _isUploading = false;

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

      _existingAttachments = List.from(widget.taskToEdit!.attachments);
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

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
      withData: true,
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() {
        for (final file in result.files) {
          if (file.bytes != null) {
            _pendingAttachments.add(_PendingAttachment(
              name: file.name,
              bytes: file.bytes!,
              mimeType: _guessMimeType(file.name),
              size: file.size,
            ));
          }
        }
      });
    }
  }

  String _guessMimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      default:
        return 'application/octet-stream';
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
        linkedJobId: _linkedJobId,
        linkedJobNumber: _linkedJobNumber,
        linkedPurchaseInvoiceId: _linkedPurchaseInvoiceId,
        linkedPurchaseInvoiceNumber: _linkedPurchaseInvoiceNumber,
        linkedSalesInvoiceId: _linkedSalesInvoiceId,
        linkedSalesInvoiceNumber: _linkedSalesInvoiceNumber,
        linkedCustomerId:
            widget.taskToEdit?.linkedCustomerId ?? widget.prefillCustomerId,
        linkedCustomerName: _linkedCustomerName,
        linkedSupplierId:
            widget.taskToEdit?.linkedSupplierId ?? widget.prefillSupplierId,
        linkedSupplierName: _linkedSupplierName,
        assigneeName: _assigneeName,
        attachments: _existingAttachments,
      );

      TaskModel savedTask;
      if (widget.taskToEdit == null) {
        savedTask = await taskService.createTask(task);
      } else {
        await taskService.updateTask(task);
        savedTask = task;
      }

      // Upload pending attachments after task is saved (need task ID)
      if (_pendingAttachments.isNotEmpty && savedTask.id != null) {
        setState(() => _isUploading = true);
        for (final pending in _pendingAttachments) {
          await taskService.addAttachment(
            taskId: savedTask.id!,
            fileName: pending.name,
            bytes: pending.bytes,
            mimeType: pending.mimeType,
          );
        }
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar tarea: $e')),
        );
        setState(() {
          _isLoading = false;
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _removeExistingAttachment(int index) async {
    final att = _existingAttachments[index];
    final taskId = widget.taskToEdit?.id;
    if (taskId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar adjunto?'),
        content: Text('¿Deseas eliminar "${att['name']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final taskService = context.read<TaskService>();
        await taskService.removeAttachment(
          taskId: taskId,
          attachmentUrl: att['url'] as String,
        );
        setState(() => _existingAttachments.removeAt(index));
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Dialog(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                  _isUploading ? 'Subiendo archivos...' : 'Guardando tarea...'),
            ],
          ),
        ),
      );
    }

    final isEditing = widget.taskToEdit != null;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 700),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 420;
            return Padding(
              padding: EdgeInsets.all(isCompact ? 16 : 24),
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
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
                          Expanded(
                            child: Text(
                              isEditing ? 'Editar Tarea' : 'Nueva Tarea',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Context Badges and Linking Area
                      _buildLinkingArea(isCompact: isCompact),
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

                      _buildPriorityAndStatusFields(isCompact: isCompact),
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
                                    onPressed: () =>
                                        setState(() => _dueDate = null),
                                  )
                                : const Icon(Icons.calendar_today),
                          ),
                          child: Text(
                            _dueDate != null
                                ? DateFormat('dd/MM/yyyy').format(_dueDate!)
                                : 'Sin fecha de vencimiento',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                          isExpanded: true,
                          initialValue:
                              _users.any((u) => u['id'] == _assignedToId)
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

                      const SizedBox(height: 20),

                      // ── Attachments section ──
                      _buildAttachmentsSection(isCompact: isCompact),

                      const SizedBox(height: 24),

                      if (isCompact)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FilledButton(
                              onPressed: _save,
                              child: Text(isEditing ? 'Actualizar' : 'Guardar'),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Cancelar'),
                            ),
                          ],
                        )
                      else
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
            );
          },
        ),
      ),
    );
  }

  Widget _buildLinkingArea({required bool isCompact}) {
    final links = Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        if (_linkedJobNumber != null)
          Chip(
            avatar: const Icon(Icons.build, size: 16),
            label: Text('Trabajo #$_linkedJobNumber'),
            backgroundColor: Colors.blue.withValues(alpha: 0.1),
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
            label: Text('Compra #$_linkedPurchaseInvoiceNumber'),
            backgroundColor: Colors.orange.withValues(alpha: 0.1),
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
            backgroundColor: Colors.green.withValues(alpha: 0.1),
            deleteIcon: const Icon(Icons.close, size: 16),
            onDeleted: () => setState(() {
              _linkedSalesInvoiceId = null;
              _linkedSalesInvoiceNumber = null;
              _linkedCustomerName = null;
            }),
          ),
      ],
    );
    final linkButton = TextButton.icon(
      icon: const Icon(Icons.link, size: 18),
      label: const Text('Vincular...'),
      onPressed: _openTaskLinkDialog,
    );

    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          links,
          Align(alignment: Alignment.centerLeft, child: linkButton),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: links),
        linkButton,
      ],
    );
  }

  Future<void> _openTaskLinkDialog() async {
    final result = await showDialog<TaskLinkResult>(
      context: context,
      builder: (context) => const TaskLinkDialog(),
    );

    if (result == null || !mounted) return;
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

  Widget _buildPriorityAndStatusFields({required bool isCompact}) {
    final priorityField = DropdownButtonFormField<TaskPriority>(
      key: const ValueKey('task-form-priority'),
      isExpanded: true,
      initialValue: _selectedPriority,
      decoration: const InputDecoration(
        labelText: 'Prioridad',
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: TaskPriority.low, child: Text('Baja')),
        DropdownMenuItem(value: TaskPriority.normal, child: Text('Normal')),
        DropdownMenuItem(value: TaskPriority.high, child: Text('Alta')),
        DropdownMenuItem(value: TaskPriority.urgent, child: Text('Urgente')),
      ],
      onChanged: (value) {
        if (value != null) setState(() => _selectedPriority = value);
      },
    );
    final statusField = DropdownButtonFormField<TaskStatus>(
      key: const ValueKey('task-form-status'),
      isExpanded: true,
      initialValue: _selectedStatus,
      decoration: const InputDecoration(
        labelText: 'Estado',
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: TaskStatus.pending, child: Text('Pendiente')),
        DropdownMenuItem(value: TaskStatus.inProgress, child: Text('En Curso')),
        DropdownMenuItem(
            value: TaskStatus.completed, child: Text('Completada')),
        DropdownMenuItem(value: TaskStatus.cancelled, child: Text('Cancelada')),
      ],
      onChanged: (value) {
        if (value != null) setState(() => _selectedStatus = value);
      },
    );

    if (isCompact) {
      return Column(
        children: [
          priorityField,
          const SizedBox(height: 12),
          statusField,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: priorityField),
        const SizedBox(width: 16),
        Expanded(child: statusField),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // ATTACHMENTS UI
  // ══════════════════════════════════════════════════════════════════

  Widget _buildAttachmentsSection({required bool isCompact}) {
    final totalCount = _existingAttachments.length + _pendingAttachments.length;
    final theme = Theme.of(context);
    final title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.attach_file, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          'Adjuntos${totalCount > 0 ? ' ($totalCount)' : ''}',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
    final addButton = OutlinedButton.icon(
      onPressed: _pickFiles,
      icon: const Icon(Icons.upload_file, size: 16),
      label: const Text('Agregar archivo'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        textStyle: const TextStyle(fontSize: 12),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isCompact)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: 8),
              addButton,
            ],
          )
        else
          Row(
            children: [
              title,
              const Spacer(),
              addButton,
            ],
          ),
        const SizedBox(height: 8),
        if (totalCount == 0)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey.shade50,
            ),
            child: Column(
              children: [
                Icon(Icons.cloud_upload_outlined,
                    size: 32, color: Colors.grey.shade400),
                const SizedBox(height: 4),
                Text(
                  'Sin archivos adjuntos',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                // Existing (already uploaded) attachments
                for (var i = 0; i < _existingAttachments.length; i++)
                  _buildAttachmentTile(
                    name:
                        _existingAttachments[i]['name'] as String? ?? 'Archivo',
                    type: _existingAttachments[i]['type'] as String? ?? '',
                    size: _existingAttachments[i]['size'] as int? ?? 0,
                    isUploaded: true,
                    onRemove: () => _removeExistingAttachment(i),
                    isLast: i == _existingAttachments.length - 1 &&
                        _pendingAttachments.isEmpty,
                  ),
                // Pending (not yet uploaded) attachments
                for (var i = 0; i < _pendingAttachments.length; i++)
                  _buildAttachmentTile(
                    name: _pendingAttachments[i].name,
                    type: _pendingAttachments[i].mimeType,
                    size: _pendingAttachments[i].size,
                    isUploaded: false,
                    onRemove: () =>
                        setState(() => _pendingAttachments.removeAt(i)),
                    isLast: i == _pendingAttachments.length - 1,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildAttachmentTile({
    required String name,
    required String type,
    required int size,
    required bool isUploaded,
    required VoidCallback onRemove,
    required bool isLast,
  }) {
    final isImage = type.startsWith('image/');
    final isPdf = type == 'application/pdf';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          // File type icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _fileTypeColor(type).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isImage
                  ? Icons.image_outlined
                  : isPdf
                      ? Icons.picture_as_pdf_outlined
                      : Icons.insert_drive_file_outlined,
              size: 20,
              color: _fileTypeColor(type),
            ),
          ),
          const SizedBox(width: 10),
          // File name and size
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500),
                ),
                Text(
                  _formatFileSize(size),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          // Status badge
          if (!isUploaded)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Text(
                'Pendiente',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.amber.shade800,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          if (isUploaded)
            Icon(Icons.cloud_done, size: 16, color: Colors.green.shade400),
          const SizedBox(width: 8),
          // Remove button
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close, size: 16, color: Colors.grey.shade500),
            ),
          ),
        ],
      ),
    );
  }

  Color _fileTypeColor(String mimeType) {
    if (mimeType.startsWith('image/')) return Colors.blue;
    if (mimeType == 'application/pdf') return Colors.red;
    if (mimeType.contains('spreadsheet') || mimeType.contains('excel')) {
      return Colors.green;
    }
    if (mimeType.contains('word') || mimeType.contains('document')) {
      return Colors.blue.shade800;
    }
    if (mimeType.startsWith('video/')) return Colors.purple;
    return Colors.grey;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Holds a file queued for upload (not yet saved to Supabase Storage).
class _PendingAttachment {
  final String name;
  final Uint8List bytes;
  final String mimeType;
  final int size;

  _PendingAttachment({
    required this.name,
    required this.bytes,
    required this.mimeType,
    required this.size,
  });
}
