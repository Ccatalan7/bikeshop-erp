import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../modules/tasks/models/task_model.dart';
import '../../modules/tasks/services/task_service.dart';
import '../services/tenant_service.dart';
import '../services/user_management_service.dart';

/// A lightweight inline panel for quickly adding tasks from the right toolbar.
class QuickTaskPanel extends StatefulWidget {
  const QuickTaskPanel({super.key});

  @override
  State<QuickTaskPanel> createState() => _QuickTaskPanelState();
}

class _QuickTaskPanelState extends State<QuickTaskPanel> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _titleFocusNode = FocusNode();

  TaskPriority _priority = TaskPriority.normal;
  DateTime? _dueDate;
  String? _assignedToId;
  String? _assigneeName;
  bool _isSaving = false;
  bool _showSuccess = false;

  // ─── In-pane edit state ───────────────────────────────────────────
  TaskModel? _editingTask;
  final _editTitleCtrl = TextEditingController();
  final _editDescCtrl = TextEditingController();
  TaskPriority _editPriority = TaskPriority.normal;
  TaskStatus _editStatus = TaskStatus.pending;
  DateTime? _editDueDate;
  bool _isSavingEdit = false;

  List<Map<String, dynamic>> _users = [];
  bool _isLoadingUsers = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _titleFocusNode.dispose();
    _editTitleCtrl.dispose();
    _editDescCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    try {
      final userService = UserManagementService(
        Provider.of<TenantService>(context, listen: false),
      );
      final users = await userService.getTenantUsers();
      if (mounted) {
        setState(() {
          _users = users;
          _isLoadingUsers = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingUsers = false);
    }
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      final taskService = context.read<TaskService>();
      final activeUser = Supabase.instance.client.auth.currentUser;
      final tenantId = await context.read<TenantService>().getTenantId();

      if (activeUser == null || tenantId == null) {
        throw Exception('Usuario no autenticado');
      }

      final task = TaskModel(
        tenantId: tenantId,
        title: title,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        priority: _priority,
        status: TaskStatus.pending,
        dueDate: _dueDate,
        assignedTo: _assignedToId,
        assigneeName: _assigneeName,
        createdBy: activeUser.id,
      );

      await taskService.createTask(task);

      if (mounted) {
        setState(() {
          _isSaving = false;
          _showSuccess = true;
        });
        // Reset after short delay
        Future.delayed(const Duration(milliseconds: 1200), () {
          if (mounted) {
            setState(() {
              _showSuccess = false;
              _titleController.clear();
              _descriptionController.clear();
              _priority = TaskPriority.normal;
              _dueDate = null;
              _assignedToId = null;
              _assigneeName = null;
            });
            _titleFocusNode.requestFocus();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null && mounted) {
      setState(() => _dueDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      child: _editingTask != null
          ? _buildEditView(theme, isDark)
          : Column(
              children: [
                // Success banner
                if (_showSuccess)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    color: const Color(0xFF388E3C).withOpacity(0.12),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle,
                            size: 18, color: Color(0xFF388E3C)),
                        SizedBox(width: 6),
                        Text(
                          '¡Tarea creada!',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF388E3C),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Recent tasks list
                Expanded(
                  child: Consumer<TaskService>(
                    builder: (context, taskService, _) {
                      final tasks = taskService.tasks
                          .where((t) =>
                              t.status != TaskStatus.completed &&
                              t.status != TaskStatus.cancelled)
                          .toList()
                        ..sort((a, b) {
                          final aDate = a.createdAt ?? DateTime(2000);
                          final bDate = b.createdAt ?? DateTime(2000);
                          return bDate.compareTo(aDate);
                        });

                      if (tasks.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.task_alt,
                                  size: 48,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.15)),
                              const SizedBox(height: 8),
                              Text('No hay tareas pendientes',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.4),
                                  )),
                            ],
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: tasks.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: isDark
                              ? const Color(0xFF2E2E2E)
                              : const Color(0xFFEEEEEE),
                        ),
                        itemBuilder: (ctx, i) =>
                            _buildTaskRow(tasks[i], theme, isDark),
                      );
                    },
                  ),
                ),

                // Quick-add form at the bottom
                _buildQuickAddForm(theme, isDark),
              ],
            ),
    );
  }

  Widget _buildTaskRow(TaskModel task, ThemeData theme, bool isDark) {
    final isOverdue = task.dueDate != null &&
        task.dueDate!.isBefore(DateTime.now()) &&
        task.status != TaskStatus.completed;
    final priorityColor = _priorityColor(task.priority);

    return InkWell(
      onTap: () => _showTaskDetail(task),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Checkbox
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: GestureDetector(
                onTap: () => _toggleTaskStatus(task),
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: task.status == TaskStatus.completed
                          ? Colors.green
                          : Colors.grey.shade400,
                      width: 1.5,
                    ),
                    color: task.status == TaskStatus.completed
                        ? Colors.green
                        : Colors.transparent,
                  ),
                  child: task.status == TaskStatus.completed
                      ? const Icon(Icons.check, size: 12, color: Colors.white)
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      // Priority dot
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: priorityColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (task.dueDate != null) ...[
                        Icon(
                          isOverdue
                              ? Icons.warning_amber
                              : Icons.event_outlined,
                          size: 11,
                          color: isOverdue ? Colors.red : Colors.grey,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          DateFormat('dd/MM').format(task.dueDate!),
                          style: TextStyle(
                            fontSize: 10,
                            color: isOverdue
                                ? Colors.red
                                : theme.colorScheme.onSurface.withOpacity(0.45),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (task.assigneeName != null)
                        Flexible(
                          child: Text(
                            task.assigneeName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.45),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleTaskStatus(TaskModel task) async {
    final taskService = context.read<TaskService>();
    final newStatus = task.status == TaskStatus.completed
        ? TaskStatus.pending
        : TaskStatus.completed;
    try {
      await taskService.updateTask(task.copyWith(status: newStatus));
    } catch (_) {}
  }

  void _showTaskDetail(TaskModel task) {
    setState(() {
      _editingTask = task;
      _editTitleCtrl.text = task.title;
      _editDescCtrl.text = task.description ?? '';
      _editPriority = task.priority;
      _editStatus = task.status;
      _editDueDate = task.dueDate;
      _isSavingEdit = false;
    });
  }

  Future<void> _saveEdit() async {
    final task = _editingTask;
    if (task == null) return;
    final title = _editTitleCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() => _isSavingEdit = true);
    try {
      final taskService = context.read<TaskService>();
      await taskService.updateTask(task.copyWith(
        title: title,
        description: _editDescCtrl.text.trim().isEmpty
            ? null
            : _editDescCtrl.text.trim(),
        priority: _editPriority,
        status: _editStatus,
        dueDate: _editDueDate,
      ));
      if (mounted) setState(() => _editingTask = null);
    } catch (_) {
      if (mounted) setState(() => _isSavingEdit = false);
    }
  }

  Widget _buildEditView(ThemeData theme, bool isDark) {
    final borderCol =
        isDark ? const Color(0xFF2E2E2E) : const Color(0xFFDDE0E4);
    final labelStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurface.withOpacity(0.5),
      letterSpacing: 0.6,
    );

    InputDecoration _fieldDecoration({String? hint}) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withOpacity(0.35)),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: borderCol),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: borderCol),
          ),
        );

    Color priorityColor(TaskPriority p) {
      switch (p) {
        case TaskPriority.urgent:
          return const Color(0xFFE53E3E);
        case TaskPriority.high:
          return const Color(0xFFED8936);
        case TaskPriority.normal:
          return const Color(0xFF4299E1);
        case TaskPriority.low:
          return Colors.grey;
      }
    }

    String priorityLabel(TaskPriority p) {
      switch (p) {
        case TaskPriority.urgent:
          return 'Urgente';
        case TaskPriority.high:
          return 'Alta';
        case TaskPriority.normal:
          return 'Normal';
        case TaskPriority.low:
          return 'Baja';
      }
    }

    String statusLabel(TaskStatus s) {
      switch (s) {
        case TaskStatus.pending:
          return 'Pendiente';
        case TaskStatus.inProgress:
          return 'En progreso';
        case TaskStatus.completed:
          return 'Completada';
        case TaskStatus.cancelled:
          return 'Cancelada';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back,
                    size: 17,
                    color: theme.colorScheme.onSurface.withOpacity(0.7)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'Volver',
                onPressed: () => setState(() => _editingTask = null),
              ),
              const SizedBox(width: 2),
              Text('Editar tarea',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  )),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 17, color: Colors.red.withOpacity(0.65)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'Eliminar',
                onPressed: () async {
                  final task = _editingTask!;
                  setState(() => _editingTask = null);
                  try {
                    await context.read<TaskService>().deleteTask(task.id!);
                  } catch (_) {}
                },
              ),
            ],
          ),
        ),
        Divider(color: borderCol, height: 1),
        // Scrollable fields
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TÍTULO', style: labelStyle),
                const SizedBox(height: 4),
                TextField(
                  controller: _editTitleCtrl,
                  style: TextStyle(
                      fontSize: 13, color: theme.colorScheme.onSurface),
                  decoration: _fieldDecoration(),
                ),
                const SizedBox(height: 12),
                Text('DESCRIPCIÓN', style: labelStyle),
                const SizedBox(height: 4),
                TextField(
                  controller: _editDescCtrl,
                  maxLines: 3,
                  style: TextStyle(
                      fontSize: 13, color: theme.colorScheme.onSurface),
                  decoration: _fieldDecoration(hint: 'Agregar descripción...'),
                ),
                const SizedBox(height: 12),
                // Priority + Status
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('PRIORIDAD', style: labelStyle),
                          const SizedBox(height: 4),
                          DropdownButtonFormField<TaskPriority>(
                            value: _editPriority,
                            isDense: true,
                            style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface),
                            decoration: _fieldDecoration(),
                            items: TaskPriority.values
                                .map((p) => DropdownMenuItem(
                                      value: p,
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                                color: priorityColor(p),
                                                shape: BoxShape.circle),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(priorityLabel(p),
                                              style: const TextStyle(
                                                  fontSize: 12)),
                                        ],
                                      ),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _editPriority = v!),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ESTADO', style: labelStyle),
                          const SizedBox(height: 4),
                          DropdownButtonFormField<TaskStatus>(
                            value: _editStatus,
                            isDense: true,
                            style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface),
                            decoration: _fieldDecoration(),
                            items: TaskStatus.values
                                .map((s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(statusLabel(s),
                                          style: const TextStyle(fontSize: 12)),
                                    ))
                                .toList(),
                            onChanged: (v) => setState(() => _editStatus = v!),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('FECHA LÍMITE', style: labelStyle),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _editDueDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null && mounted)
                      setState(() => _editDueDate = picked);
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: borderCol),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.event_outlined,
                            size: 14,
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.5)),
                        const SizedBox(width: 6),
                        Text(
                          _editDueDate != null
                              ? DateFormat('dd/MM/yyyy').format(_editDueDate!)
                              : 'Sin fecha',
                          style: TextStyle(
                            fontSize: 12,
                            color: _editDueDate != null
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurface.withOpacity(0.4),
                          ),
                        ),
                        const Spacer(),
                        if (_editDueDate != null)
                          GestureDetector(
                            onTap: () => setState(() => _editDueDate = null),
                            child: Icon(Icons.clear,
                                size: 14,
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.4)),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Save button
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              onPressed: _isSavingEdit ? null : _saveEdit,
              child: Text(
                _isSavingEdit ? 'Guardando...' : 'Guardar',
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickAddForm(ThemeData theme, bool isDark) {
    final borderColor =
        isDark ? const Color(0xFF2E2E2E) : const Color(0xFFDDE0E4);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF8F9FA),
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title
          TextField(
            controller: _titleController,
            focusNode: _titleFocusNode,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              hintText: 'Título de la tarea...',
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: borderColor),
              ),
              filled: true,
              fillColor:
                  isDark ? const Color(0xFF252525) : const Color(0xFFF5F6F8),
            ),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 6),

          // Description (optional, smaller)
          TextField(
            controller: _descriptionController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Descripción (opcional)...',
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: borderColor),
              ),
              filled: true,
              fillColor:
                  isDark ? const Color(0xFF252525) : const Color(0xFFF5F6F8),
            ),
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),

          // Quick options row: priority + due date + assignee
          Row(
            children: [
              // Priority selector
              _PriorityChip(
                priority: _priority,
                onChanged: (p) => setState(() => _priority = p),
                theme: theme,
                isDark: isDark,
              ),
              const SizedBox(width: 6),

              // Due date
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_outlined,
                          size: 14,
                          color: _dueDate != null
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface.withOpacity(0.5)),
                      const SizedBox(width: 3),
                      Text(
                        _dueDate != null
                            ? DateFormat('dd/MM').format(_dueDate!)
                            : 'Fecha',
                        style: TextStyle(
                          fontSize: 11,
                          color: _dueDate != null
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                      if (_dueDate != null) ...[
                        const SizedBox(width: 2),
                        GestureDetector(
                          onTap: () => setState(() => _dueDate = null),
                          child: Icon(Icons.close,
                              size: 12,
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.4)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // Assignee
              if (!_isLoadingUsers)
                Flexible(
                  child: PopupMenuButton<String?>(
                    tooltip: 'Asignar',
                    onSelected: (val) {
                      setState(() {
                        _assignedToId = val;
                        if (val != null) {
                          final u = _users.firstWhere((u) => u['id'] == val);
                          _assigneeName = u['full_name'] as String? ??
                              u['email'] as String?;
                        } else {
                          _assigneeName = null;
                        }
                      });
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                          value: null, child: Text('Sin asignar')),
                      const PopupMenuDivider(),
                      ..._users.map((u) => PopupMenuItem<String>(
                            value: u['id'] as String,
                            child: Text(
                              u['full_name'] as String? ??
                                  u['email'] as String? ??
                                  '?',
                              overflow: TextOverflow.ellipsis,
                            ),
                          )),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_outline,
                              size: 14,
                              color: _assigneeName != null
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface
                                      .withOpacity(0.5)),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              _assigneeName ?? 'Asignar',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: _assigneeName != null
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface
                                        .withOpacity(0.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Add button
          SizedBox(
            width: double.infinity,
            height: 38,
            child: ElevatedButton.icon(
              onPressed: _isSaving || _titleController.text.trim().isEmpty
                  ? null
                  : _save,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.add_task, size: 18),
              label: Text(
                _isSaving ? 'Guardando...' : 'Agregar Tarea',
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _priorityColor(TaskPriority p) {
    switch (p) {
      case TaskPriority.low:
        return Colors.blue.shade300;
      case TaskPriority.normal:
        return Colors.amber;
      case TaskPriority.high:
        return Colors.orange;
      case TaskPriority.urgent:
        return Colors.red;
    }
  }
}

// ─── Priority chip selector ────────────────────────────────────────
class _PriorityChip extends StatelessWidget {
  final TaskPriority priority;
  final ValueChanged<TaskPriority> onChanged;
  final ThemeData theme;
  final bool isDark;

  const _PriorityChip({
    required this.priority,
    required this.onChanged,
    required this.theme,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final color = _color(priority);
    final borderColor =
        isDark ? const Color(0xFF2E2E2E) : const Color(0xFFDDE0E4);

    return PopupMenuButton<TaskPriority>(
      tooltip: 'Prioridad',
      onSelected: onChanged,
      itemBuilder: (ctx) => TaskPriority.values.map((p) {
        return PopupMenuItem<TaskPriority>(
          value: p,
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: _color(p), shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(_label(p)),
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderColor),
          color: color.withOpacity(0.08),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text(
              _label(priority),
              style: TextStyle(fontSize: 11, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Color _color(TaskPriority p) {
    switch (p) {
      case TaskPriority.low:
        return Colors.blue.shade300;
      case TaskPriority.normal:
        return Colors.amber.shade700;
      case TaskPriority.high:
        return Colors.orange;
      case TaskPriority.urgent:
        return Colors.red;
    }
  }

  String _label(TaskPriority p) {
    switch (p) {
      case TaskPriority.low:
        return 'Baja';
      case TaskPriority.normal:
        return 'Normal';
      case TaskPriority.high:
        return 'Alta';
      case TaskPriority.urgent:
        return 'Urgente';
    }
  }
}
