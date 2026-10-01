import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';

import '../../tasks/models/task_assignment_principal.dart';
import '../../tasks/models/task_model.dart';
import '../../tasks/services/task_service.dart';
import '../../messaging/widgets/chat_attachment_viewer.dart';
import '../../../shared/services/global_search/quick_task_draft.dart'
    show quickTaskPeople;
import '../../../shared/services/tenant_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'task_link_dialog.dart';

/// Construcción PURA del modelo que guarda el diálogo, extraída para poder
/// probar el contrato: editar jamás reescribe la identidad (tipo, visibilidad,
/// versión, autor), y nota/privada no cargan responsable ni estado de tarea.
@visibleForTesting
TaskModel buildTaskFormSaveModel({
  required TaskModel? editing,
  required String tenantId,
  required String fallbackCreatorId,
  required String title,
  required String description,
  required TaskPriority priority,
  required TaskStatus selectedStatus,
  required DateTime? dueDate,
  required String? assignedToId,
  String? assignedEmployeeId,
  required String? assigneeName,
  required String? linkedJobId,
  required String? linkedJobNumber,
  required String? linkedPurchaseInvoiceId,
  required String? linkedPurchaseInvoiceNumber,
  required String? linkedSalesInvoiceId,
  required String? linkedSalesInvoiceNumber,
  required String? linkedCustomerId,
  required String? linkedCustomerName,
  required String? linkedSupplierId,
  required String? linkedSupplierName,
  required List<Map<String, dynamic>> attachments,
}) {
  final isNote = editing?.kind == TaskKind.note;
  final isPrivate = editing?.visibility == TaskVisibility.private;
  return TaskModel(
    id: editing?.id,
    tenantId: tenantId,
    title: title,
    description: description,
    priority: priority,
    // smart_task_create_v1 starts every task as pending. Do not promise an
    // initial transition that the create command does not perform.
    status: editing == null
        ? TaskStatus.pending
        : isNote
            ? editing.status
            : selectedStatus,
    dueDate: dueDate,
    assignedTo: (isNote || isPrivate) ? null : assignedToId,
    // La tarea es de la persona: un trabajador se asigna como trabajador.
    assignedEmployeeId: (isNote || isPrivate) ? null : assignedEmployeeId,
    createdBy: editing?.createdBy ?? fallbackCreatorId,
    kind: editing?.kind ?? TaskKind.task,
    visibility: editing?.visibility ?? TaskVisibility.team,
    version: editing?.version ?? 1,
    linkedJobId: isPrivate ? null : linkedJobId,
    linkedJobNumber: linkedJobNumber,
    linkedPurchaseInvoiceId: linkedPurchaseInvoiceId,
    linkedPurchaseInvoiceNumber: linkedPurchaseInvoiceNumber,
    linkedSalesInvoiceId: linkedSalesInvoiceId,
    linkedSalesInvoiceNumber: linkedSalesInvoiceNumber,
    linkedCustomerId: linkedCustomerId,
    linkedCustomerName: linkedCustomerName,
    linkedSupplierId: linkedSupplierId,
    linkedSupplierName: linkedSupplierName,
    assigneeName: assigneeName,
    attachments: attachments,
  );
}

/// El diálogo legado no ofrece «Bloquear» sin pedir motivo. Sin embargo, al
/// editar una tarea ya bloqueada debe conservar el valor actual para que el
/// dropdown sea válido y la tarea pueda corregirse o salir del bloqueo.
@visibleForTesting
List<TaskStatus> taskFormStatusOptions(TaskModel? editing) => editing == null
    ? const [TaskStatus.pending]
    : [
        TaskStatus.pending,
        TaskStatus.inProgress,
        if (editing.status == TaskStatus.blocked) TaskStatus.blocked,
        TaskStatus.completed,
        TaskStatus.cancelled,
      ];

class TaskFormDialog extends StatefulWidget {
  final TaskModel? taskToEdit;
  final bool openAttachments;
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
    this.openAttachments = false,
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
  final _attachmentsSectionKey = GlobalKey();
  final _noticeKey = GlobalKey();
  _FormNotice? _revealedNotice;

  late TextEditingController _titleController;
  late TextEditingController _descriptionController;

  TaskPriority _selectedPriority = TaskPriority.normal;
  TaskStatus _selectedStatus = TaskStatus.pending;
  DateTime? _dueDate;

  String? _assignedToId;
  String? _assignedEmployeeId;
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

  List<TaskAssignmentPrincipal> _people = [];
  bool _isLoadingUsers = true;
  bool _isLoading = false;

  // Lo que el operador debe saber del último intento. Vive dentro del
  // diálogo: un SnackBar queda detrás de su barrera, atenuado y fuera de la
  // semántica (C1 por la app, 2026-09-30).
  _FormNotice? _notice;

  // Attachments
  List<Map<String, dynamic>> _existingAttachments = [];
  final List<_PendingAttachment> _pendingAttachments = [];
  bool _isUploading = false;
  // A failed upload must not turn the next Save into a second task creation.
  TaskModel? _createdTask;
  final String _creationKey = const Uuid().v4();
  bool _hasFailedAttachmentUpload = false;
  bool _closePromptOpen = false;
  bool _allowPop = false;

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
      _assignedEmployeeId = widget.taskToEdit!.assignedEmployeeId;
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

    _fetchPeople();
    if (widget.openAttachments) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final section = _attachmentsSectionKey.currentContext;
        if (!mounted || section == null) return;
        Scrollable.ensureVisible(
          section,
          alignment: 0.15,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      });
    }
  }

  /// El directorio de asignación de la bandeja, que lee cualquier miembro
  /// del taller. `get_tenant_users` es de administración: a un mecánico le
  /// dejaba sólo «Sin asignar» (C1 por la app, 2026-09-30).
  Future<void> _fetchPeople() async {
    try {
      final directory =
          await context.read<TaskService>().fetchAssignmentDirectory();
      final people = quickTaskPeople(
        directory,
        currentUserId: Supabase.instance.client.auth.currentUser?.id,
      );
      if (mounted) {
        setState(() {
          _people = people;
          _isLoadingUsers = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching assignment directory: $e');
      if (mounted) {
        setState(() => _isLoadingUsers = false);
      }
    }
  }

  String? get _assigneeKey => _assignedEmployeeId ?? _assignedToId;

  /// Sobre un trabajo del taller, sólo quien tiene ficha de trabajador: es lo
  /// que acepta el servidor (`assignee_not_worker_linked`), como en el rail.
  List<TaskAssignmentPrincipal> get _assignablePeople => _linkedJobId == null
      ? _people
      : _people.where((person) => person.employeeId != null).toList();

  String get _saveLabel => widget.taskToEdit != null ? 'Actualizar' : 'Guardar';

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

    if (result == null || result.files.isEmpty || !mounted) return;
    setState(() => _notice = null);

    final accepted = <_PendingAttachment>[];
    final rejected = <String>[];
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        rejected.add('${file.name}: no se pudo leer');
      } else if (bytes.length > TaskService.maxAttachmentBytes) {
        rejected.add('${file.name}: supera 20 MB');
      } else {
        accepted.add(_PendingAttachment(
          name: file.name,
          bytes: bytes,
          mimeType: _guessMimeType(file.name),
          size: bytes.length,
        ));
      }
    }
    if (accepted.isNotEmpty) {
      setState(() => _pendingAttachments.addAll(accepted));
    }
    if (rejected.isNotEmpty) {
      final detail = rejected.take(2).join('; ');
      final rest = rejected.length > 2 ? ' y ${rejected.length - 2} más' : '';
      setState(
          () => _notice = _FormNotice.warning('No se adjuntó: $detail$rest.'));
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

  Future<void> _requestClose() async {
    if (_isLoading || _closePromptOpen) return;
    if (!_hasFailedAttachmentUpload || _pendingAttachments.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    _closePromptOpen = true;
    try {
      final pendingCount = _pendingAttachments.length;
      final close = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('La tarea ya quedó guardada'),
          content: Text(
            '${pendingCount == 1 ? 'Queda 1 archivo' : 'Quedan $pendingCount archivos'} '
            'sin adjuntar. Si cierras, tendrás que elegirlos de nuevo desde '
            'la tarea.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Seguir aquí'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Cerrar sin adjuntar'),
            ),
          ],
        ),
      );
      if (close == true && mounted) {
        final taskId = _createdTask?.id ?? widget.taskToEdit?.id;
        if (taskId == null) {
          setState(() => _notice = const _FormNotice.error(
              'No se pudo conservar el estado de los adjuntos. '
              'Sigue aquí e inténtalo de nuevo.'));
          return;
        }
        try {
          await context.read<TaskService>().abandonPendingAttachmentUploads(
                taskId: taskId,
                attachmentIds:
                    _pendingAttachments.map((pending) => pending.id).toList(),
              );
        } catch (_) {
          if (mounted) {
            setState(() => _notice = const _FormNotice.error(
                'No se pudo conservar el estado de los adjuntos. '
                'Sigue aquí e inténtalo de nuevo.'));
          }
          return;
        }
        if (!mounted) return;
        _allowPop = true;
        Navigator.of(context).pop();
      }
    } finally {
      _closePromptOpen = false;
    }
  }

  Widget _guardClose(Widget dialog) => PopScope(
        canPop: _allowPop ||
            (!_isLoading &&
                !(_hasFailedAttachmentUpload &&
                    _pendingAttachments.isNotEmpty)),
        onPopInvokedWithResult: (didPop, _) async {
          if (!didPop && !_isLoading) await _requestClose();
        },
        child: dialog,
      );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _notice = null;
    });
    var taskSaved = false;

    try {
      final taskService = context.read<TaskService>();
      final activeUser = Supabase.instance.client.auth.currentUser;
      final tenantId = await context.read<TenantService>().getTenantId();

      if (activeUser == null || tenantId == null) {
        throw Exception('Usuario no autenticado o tenant no definido');
      }

      final task = buildTaskFormSaveModel(
        editing: widget.taskToEdit ?? _createdTask,
        tenantId: tenantId,
        fallbackCreatorId: activeUser.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        priority: _selectedPriority,
        selectedStatus: _selectedStatus,
        dueDate: _dueDate,
        assignedToId: _assignedToId,
        assignedEmployeeId: _assignedEmployeeId,
        assigneeName: _assigneeName,
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
        // Los vínculos privados sólo viven en smart_task_attachments. Nunca
        // volver a serializarlos en el JSONB heredado al editar la tarea.
        attachments: _existingAttachments
            .where((entry) => entry['storage_bucket'] != 'task-attachments')
            .toList(),
      );

      TaskModel savedTask;
      if (widget.taskToEdit == null && _createdTask == null) {
        savedTask = await taskService.createTask(
          task,
          idempotencyKey: _creationKey,
        );
        _createdTask = savedTask;
      } else {
        await taskService.updateTask(task);
        savedTask = task;
      }
      taskSaved = true;

      // Upload pending attachments after task is saved (need task ID)
      if (_pendingAttachments.isNotEmpty && savedTask.id != null) {
        setState(() => _isUploading = true);
        for (final pending
            in List<_PendingAttachment>.of(_pendingAttachments)) {
          await taskService.addAttachment(
            taskId: savedTask.id!,
            fileName: pending.name,
            bytes: pending.bytes,
            mimeType: pending.mimeType,
            attachmentId: pending.id,
          );
          _pendingAttachments.remove(pending);
          final refreshed = taskService.tasks
              .where((candidate) => candidate.id == savedTask.id)
              .firstOrNull;
          if (refreshed != null && mounted) {
            setState(() => _existingAttachments =
                List<Map<String, dynamic>>.from(refreshed.attachments));
          }
        }
      }

      if (mounted) {
        _allowPop = true;
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      // El detalle técnico va al registro; el operador lee qué pasó y qué
      // hacer, con el nombre del botón que tiene delante.
      debugPrint('TaskFormDialog save failed (saved=$taskSaved): $e');
      if (mounted) {
        final pending = _pendingAttachments.length;
        setState(() {
          if (taskSaved && _isUploading && pending > 0) {
            _hasFailedAttachmentUpload = true;
          }
          _notice = taskSaved && pending > 0
              ? _FormNotice.warning('La tarea quedó guardada, pero '
                  '${pending == 1 ? '1 archivo no se subió' : '$pending archivos no se subieron'}. '
                  'Pulsa $_saveLabel para reintentar.')
              : taskSaved
                  ? const _FormNotice.error(
                      'La tarea quedó guardada, pero no se pudo terminar. '
                      'Revisa la conexión e inténtalo de nuevo.')
                  : const _FormNotice.error('No se pudo guardar la tarea. '
                      'Revisa la conexión e inténtalo de nuevo.');
          _isLoading = false;
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _removeExistingAttachment(int index) async {
    final att = _existingAttachments[index];
    final taskId = widget.taskToEdit?.id ?? _createdTask?.id;
    final attachmentId = att['id']?.toString();
    if (taskId == null ||
        attachmentId == null ||
        att['storage_bucket'] != 'task-attachments') {
      if (mounted) {
        setState(() => _notice = const _FormNotice.warning(
            'Este adjunto antiguo necesita migrarse antes de retirarlo. '
            'No se eliminó ningún archivo.'));
      }
      return;
    }

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
      setState(() => _notice = null);
      try {
        final taskService = context.read<TaskService>();
        final cleanupCompleted = await taskService.removeAttachment(
          taskId: taskId,
          attachmentId: attachmentId,
        );
        if (!mounted) return;
        setState(() {
          _existingAttachments.removeWhere(
            (entry) =>
                entry['storage_bucket'] == 'task-attachments' &&
                entry['id']?.toString() == attachmentId,
          );
          if (!cleanupCompleted) {
            _notice = const _FormNotice.warning(
                'Archivo retirado de la tarea. La limpieza pendiente se '
                'retomará al iniciar sesión.');
          }
        });
      } catch (e) {
        debugPrint('TaskFormDialog remove attachment failed: $e');
        if (mounted) {
          setState(() => _notice = const _FormNotice.error(
              'No se pudo quitar el adjunto. Revisa la conexión e '
              'inténtalo de nuevo.'));
        }
      }
    }
  }

  Future<void> _openExistingAttachment(Map<String, dynamic> attachment) async {
    final name = attachment['name']?.toString() ?? 'Archivo';
    final type = attachment['type']?.toString() ?? '';
    try {
      final privatePath = attachment['storage_bucket'] == 'task-attachments'
          ? attachment['storage_path']?.toString()
          : null;
      final url = privatePath == null
          ? attachment['url']?.toString()
          : await context
              .read<TaskService>()
              .createSignedAttachmentUrl(privatePath);
      if (url == null || url.isEmpty) {
        throw StateError('Este archivo no tiene una ruta disponible');
      }
      if (!mounted) return;
      await ChatAttachmentViewer.show(
        context,
        url: url,
        fileName: name,
        extension: name.contains('.') ? name.split('.').last : '',
        contentType: type,
        isImage: type.startsWith('image/'),
      );
    } catch (error) {
      debugPrint('TaskFormDialog open attachment failed: $error');
      if (!mounted) return;
      setState(() => _notice = _FormNotice.error(
          'No se pudo abrir $name. Revisa la conexión e inténtalo de nuevo.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _guardClose(Dialog(
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
      ));
    }

    final isEditing = widget.taskToEdit != null;

    _revealNewNotice();

    return _guardClose(Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 700),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 420;
            final padding = isCompact ? 16.0 : 24.0;
            final header = _buildHeader(isEditing: isEditing);
            final fields = _buildFields(isCompact: isCompact);
            final actions =
                _buildActions(isEditing: isEditing, isCompact: isCompact);
            // En teléfono el formulario no cabe: el título y las acciones
            // quedan fijos y sólo los campos y adjuntos se desplazan, también
            // con el teclado abierto (el Dialog ya descuenta viewInsets). Con
            // muy poca altura todo vuelve a desplazarse junto, sin desbordar.
            if (constraints.maxHeight < _pinnedChromeMinHeight) {
              return Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(padding),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      header,
                      const SizedBox(height: 24),
                      fields,
                      const SizedBox(height: 24),
                      actions,
                    ],
                  ),
                ),
              );
            }
            return Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(padding, padding, padding, 0),
                    child: header,
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(padding, 24, padding, 16),
                      child: fields,
                    ),
                  ),
                  if (isCompact)
                    Divider(
                      height: 1,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        padding, isCompact ? 12 : 8, padding, padding),
                    child: actions,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ));
  }

  /// Bajo esta altura (teléfono horizontal con teclado) título y acciones
  /// fijos dejarían sin espacio a los campos.
  static const double _pinnedChromeMinHeight = 360;

  /// Un aviso nuevo se muestra aunque el operador haya guardado desde arriba:
  /// «Guardar» ya no está pegado a los adjuntos. Se desplaza lo mínimo.
  void _revealNewNotice() {
    final notice = _notice;
    if (notice == null) {
      _revealedNotice = null;
      return;
    }
    if (identical(notice, _revealedNotice)) return;
    _revealedNotice = notice;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      for (final policy in const [
        ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      ]) {
        final target = _noticeKey.currentContext;
        if (!mounted || target == null) return;
        await Scrollable.ensureVisible(
          target,
          alignmentPolicy: policy,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildHeader({required bool isEditing}) {
    return Row(
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
          tooltip: 'Cerrar',
          icon: const Icon(Icons.close),
          onPressed: _requestClose,
        ),
      ],
    );
  }

  Widget _buildFields({required bool isCompact}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          autofocus: !widget.openAttachments,
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
                      onPressed: () => setState(() => _dueDate = null),
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
        else if (widget.taskToEdit?.kind == TaskKind.note ||
            widget.taskToEdit?.visibility == TaskVisibility.private)
          const InputDecorator(
            decoration: InputDecoration(
              labelText: 'Asignar a',
              border: OutlineInputBorder(),
            ),
            child: Text('No aplica: nota o tarea personal'),
          )
        else
          DropdownButtonFormField<String?>(
            isExpanded: true,
            // Sin la persona en el directorio (no cargó), el
            // campo muestra «Sin asignar» pero guardar conserva
            // la asignación que ya tenía la tarea.
            initialValue: _assignablePeople
                    .any((person) => person.assignmentKey == _assigneeKey)
                ? _assigneeKey
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
              ..._assignablePeople.map(
                (person) => DropdownMenuItem<String>(
                  value: person.assignmentKey,
                  child: Text(
                    person.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: (key) {
              final person = key == null
                  ? null
                  : _assignablePeople.firstWhere(
                      (candidate) => candidate.assignmentKey == key);
              setState(() {
                _assignedEmployeeId = person?.employeeId;
                _assignedToId = person?.userId;
                _assigneeName = person?.displayName;
              });
            },
          ),

        const SizedBox(height: 20),

        // ── Attachments section ──
        KeyedSubtree(
          key: _attachmentsSectionKey,
          child: _buildAttachmentsSection(isCompact: isCompact),
        ),
      ],
    );
  }

  Widget _buildActions({required bool isEditing, required bool isCompact}) {
    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: _save,
            child: Text(isEditing ? 'Actualizar' : 'Guardar'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _requestClose,
            child: const Text('Cancelar'),
          ),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: _requestClose,
          child: const Text('Cancelar'),
        ),
        const SizedBox(width: 16),
        FilledButton(
          onPressed: _save,
          child: Text(isEditing ? 'Actualizar' : 'Guardar'),
        ),
      ],
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
    final isNew = widget.taskToEdit == null;
    final isNote = widget.taskToEdit?.kind == TaskKind.note;
    final Widget statusField = isNew
        ? const InputDecorator(
            decoration: InputDecoration(
              labelText: 'Estado',
              border: OutlineInputBorder(),
            ),
            child: Text('Pendiente al crear. Cámbiala después de guardarla.'),
          )
        : isNote
            ? const InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Estado',
                  border: OutlineInputBorder(),
                ),
                child: Text('Nota — se archiva o restaura desde la lista'),
              )
            : DropdownButtonFormField<TaskStatus>(
                key: const ValueKey('task-form-status'),
                isExpanded: true,
                initialValue: _selectedStatus,
                decoration: const InputDecoration(
                  labelText: 'Estado',
                  border: OutlineInputBorder(),
                ),
                items: taskFormStatusOptions(widget.taskToEdit)
                    .map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(switch (status) {
                          TaskStatus.pending => 'Pendiente',
                          TaskStatus.inProgress => 'En Curso',
                          TaskStatus.blocked => 'Bloqueada',
                          TaskStatus.completed => 'Completada',
                          TaskStatus.cancelled => 'Cancelada',
                        }),
                      ),
                    )
                    .toList(growable: false),
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
        if (_notice != null) ...[
          KeyedSubtree(key: _noticeKey, child: _buildNotice(_notice!)),
          const SizedBox(height: 8),
        ],
        if (totalCount == 0)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
              color: theme.colorScheme.surfaceContainerLow,
            ),
            child: Column(
              children: [
                Icon(Icons.cloud_upload_outlined,
                    size: 32, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(height: 4),
                Text(
                  'Sin archivos adjuntos',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
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
                    onOpen: () => _openExistingAttachment(
                      _existingAttachments[i],
                    ),
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
    VoidCallback? onOpen,
    required VoidCallback onRemove,
    required bool isLast,
  }) {
    final isImage = type.startsWith('image/');
    final isPdf = type == 'application/pdf';
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: colors.outlineVariant)),
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
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // Status badge
          // Advertencia del tema (tertiary): legible en claro y en oscuro.
          if (!isUploaded)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colors.tertiaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Pendiente',
                style: TextStyle(
                  fontSize: 10,
                  color: colors.onTertiaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (isUploaded)
            Icon(Icons.cloud_done, size: 16, color: Colors.green.shade400),
          if (onOpen != null)
            IconButton(
              tooltip: 'Abrir adjunto',
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new),
            ),
          IconButton(
            tooltip: 'Quitar adjunto',
            onPressed: onRemove,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildNotice(_FormNotice notice) {
    final colors = Theme.of(context).colorScheme;
    final background =
        notice.isError ? colors.errorContainer : colors.tertiaryContainer;
    final foreground =
        notice.isError ? colors.onErrorContainer : colors.onTertiaryContainer;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        key: const ValueKey('task-form-notice'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              notice.isError ? Icons.error_outline : Icons.info_outline,
              size: 18,
              color: foreground,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                notice.message,
                style: TextStyle(fontSize: 13, height: 1.35, color: foreground),
              ),
            ),
          ],
        ),
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

/// Un aviso del formulario: advertencia (se puede seguir) o error.
class _FormNotice {
  final String message;
  final bool isError;

  const _FormNotice.warning(this.message) : isError = false;
  const _FormNotice.error(this.message) : isError = true;
}

/// Holds a file queued for upload (not yet saved to Supabase Storage).
class _PendingAttachment {
  final String id;
  final String name;
  final Uint8List bytes;
  final String mimeType;
  final int size;

  _PendingAttachment({
    String? id,
    required this.name,
    required this.bytes,
    required this.mimeType,
    required this.size,
  }) : id = id ?? const Uuid().v4();
}
