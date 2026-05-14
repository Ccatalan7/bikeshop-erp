import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../tasks/models/task_model.dart';
import '../../tasks/services/task_service.dart';
import '../../../shared/services/user_management_service.dart';
import '../../../shared/services/tenant_service.dart';
import 'task_form_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';

class PegasTasksWidget extends StatefulWidget {
  const PegasTasksWidget({super.key});

  @override
  State<PegasTasksWidget> createState() => _PegasTasksWidgetState();
}

class _PegasTasksWidgetState extends State<PegasTasksWidget> {
  // Filters
  TaskStatus? _statusFilter = TaskStatus.pending;
  TaskPriority? _priorityFilter;
  String _searchQuery = '';

  // Inline editing
  String? _editingTitleTaskId;
  late TextEditingController _titleController;

  // Users cache for assignee menu
  List<Map<String, dynamic>>? _users;
  bool _usersLoading = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _loadUsers();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    if (_usersLoading) return;
    _usersLoading = true;
    try {
      final userService = UserManagementService(
        Provider.of<TenantService>(context, listen: false),
      );
      final users = await userService.getTenantUsers();
      if (mounted) {
        setState(() => _users = users);
      }
    } catch (e) {
      debugPrint('❌ Error loading users for tasks: $e');
    }
    _usersLoading = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<TaskService>(
      builder: (context, taskService, child) {
        final allTasks = taskService.tasks;

        // Filter tasks
        final filteredTasks = allTasks.where((task) {
          if (_statusFilter != null && task.status != _statusFilter) {
            return false;
          }
          if (_priorityFilter != null && task.priority != _priorityFilter) {
            return false;
          }
          if (_searchQuery.isNotEmpty) {
            final q = _searchQuery.toLowerCase();
            return task.title.toLowerCase().contains(q) ||
                (task.description?.toLowerCase().contains(q) ?? false) ||
                (task.linkedJobNumber?.toLowerCase().contains(q) ?? false);
          }
          return true;
        }).toList();

        // Count stats
        final pendingCount =
            allTasks.where((t) => t.status == TaskStatus.pending).length;
        final inProgressCount =
            allTasks.where((t) => t.status == TaskStatus.inProgress).length;
        final completedCount =
            allTasks.where((t) => t.status == TaskStatus.completed).length;
        final overdueCount = allTasks
            .where((t) =>
                t.dueDate != null &&
                t.dueDate!.isBefore(DateTime.now()) &&
                t.status != TaskStatus.completed &&
                t.status != TaskStatus.cancelled)
            .length;

        return Column(
          children: [
            // Stats bar
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                border: Border(
                  bottom: BorderSide(color: theme.dividerColor),
                ),
              ),
              child: Row(
                children: [
                  _buildStatChip(
                    icon: Icons.pending_actions,
                    label: '$pendingCount Pendientes',
                    color: Colors.amber,
                    isActive: _statusFilter == TaskStatus.pending,
                    onTap: () => setState(() => _statusFilter =
                        _statusFilter == TaskStatus.pending
                            ? null
                            : TaskStatus.pending),
                  ),
                  const SizedBox(width: 8),
                  _buildStatChip(
                    icon: Icons.play_circle_outline,
                    label: '$inProgressCount En Curso',
                    color: Colors.blue,
                    isActive: _statusFilter == TaskStatus.inProgress,
                    onTap: () => setState(() => _statusFilter =
                        _statusFilter == TaskStatus.inProgress
                            ? null
                            : TaskStatus.inProgress),
                  ),
                  const SizedBox(width: 8),
                  _buildStatChip(
                    icon: Icons.check_circle_outline,
                    label: '$completedCount Completadas',
                    color: Colors.green,
                    isActive: _statusFilter == TaskStatus.completed,
                    onTap: () => setState(() => _statusFilter =
                        _statusFilter == TaskStatus.completed
                            ? null
                            : TaskStatus.completed),
                  ),
                  if (overdueCount > 0) ...[
                    const SizedBox(width: 8),
                    _buildStatChip(
                      icon: Icons.warning_amber_rounded,
                      label: '$overdueCount Vencidas',
                      color: Colors.red,
                      isActive: false,
                      onTap: null,
                    ),
                  ],
                  const Spacer(),
                  PopupMenuButton<TaskPriority?>(
                    tooltip: 'Filtrar por prioridad',
                    initialValue: _priorityFilter,
                    onSelected: (val) => setState(() => _priorityFilter = val),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                          value: null, child: Text('Todas las prioridades')),
                      const PopupMenuDivider(),
                      ...TaskPriority.values.map((p) => PopupMenuItem(
                            value: p,
                            child: Row(
                              children: [
                                Icon(_priorityIcon(p),
                                    size: 16, color: _priorityColor(p)),
                                const SizedBox(width: 8),
                                Text(_translatePriority(p)),
                              ],
                            ),
                          )),
                    ],
                    child: Chip(
                      avatar: Icon(
                        _priorityFilter != null
                            ? _priorityIcon(_priorityFilter!)
                            : Icons.filter_list,
                        size: 16,
                        color: _priorityFilter != null
                            ? _priorityColor(_priorityFilter!)
                            : null,
                      ),
                      label: Text(
                        _priorityFilter != null
                            ? _translatePriority(_priorityFilter!)
                            : 'Prioridad',
                        style: const TextStyle(fontSize: 12),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),

            // Search + Add
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Buscar tareas...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 0, horizontal: 16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.3),
                        ),
                        onChanged: (val) => setState(() => _searchQuery = val),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => const TaskFormDialog(),
                      );
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Nueva Tarea'),
                  ),
                ],
              ),
            ),

            // Table header
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.3),
                border: Border(
                  top: BorderSide(color: theme.dividerColor),
                  bottom: BorderSide(color: theme.dividerColor),
                ),
              ),
              child: const Row(
                children: [
                  SizedBox(width: 36), // checkbox space
                  Expanded(
                    flex: 4,
                    child: Text('Tarea',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('Estado',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('Prioridad',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('Fecha',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('Asignado',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('Adjuntos',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12)),
                  ),
                  SizedBox(width: 40),
                ],
              ),
            ),

            // Task list
            Expanded(
              child: filteredTasks.isEmpty
                  ? _buildEmptyState()
                  : _buildTasksList(filteredTasks),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required Color color,
    required bool isActive,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color:
                isActive ? color.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive
                  ? color.withValues(alpha: 0.5)
                  : Colors.grey.shade300,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: isActive ? color : Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.task_alt,
              size: 64, color: Colors.grey.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text(
            _statusFilter != null
                ? 'No hay tareas con estado "${_translateStatus(_statusFilter!)}"'
                : 'No hay tareas',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey.shade600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Crea una nueva tarea o ajusta los filtros.',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildTasksList(List<TaskModel> tasks) {
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        final isCompleted = task.status == TaskStatus.completed;
        final isCancelled = task.status == TaskStatus.cancelled;
        final isDimmed = isCompleted || isCancelled;
        final isOverdue = task.dueDate != null &&
            task.dueDate!.isBefore(DateTime.now()) &&
            !isCompleted &&
            !isCancelled;
        final theme = Theme.of(context);
        final isEditingTitle = _editingTitleTaskId == task.id;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          decoration: BoxDecoration(
            color: isDimmed ? theme.colorScheme.surfaceContainerLowest : null,
            border: Border(
              bottom: BorderSide(color: theme.dividerColor),
              left: isOverdue
                  ? BorderSide(color: Colors.red.shade400, width: 3)
                  : BorderSide.none,
            ),
          ),
          child: Row(
            children: [
              // ── Checkbox ──
              GestureDetector(
                onTap: () => _toggleStatus(task),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCompleted ? Colors.green : Colors.transparent,
                    border: Border.all(
                      color: isCompleted ? Colors.green : Colors.grey.shade400,
                      width: 2,
                    ),
                  ),
                  child: isCompleted
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
              ),
              const SizedBox(width: 14),

              // ── Title (click to edit inline) ──
              Expanded(
                flex: 4,
                child: isEditingTitle
                    ? _buildTitleEditor(task)
                    : _buildTitleCell(task, isDimmed, isCompleted),
              ),

              // ── Status badge (click → dropdown) ──
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _buildStatusBadge(task),
                ),
              ),

              // ── Priority badge (click → dropdown) ──
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _buildPriorityBadge(task),
                ),
              ),

              // ── Due date (click → date picker) ──
              Expanded(
                flex: 2,
                child: _buildDateCell(task, isOverdue),
              ),

              // ── Assignee (click → user menu) ──
              Expanded(
                flex: 2,
                child: _buildAssigneeCell(task, theme),
              ),

              // ── Attachments ──
              Expanded(
                flex: 2,
                child: _buildAttachmentCell(task),
              ),

              // ── Actions ──
              SizedBox(
                width: 40,
                child: PopupMenuButton<String>(
                  tooltip: 'Acciones',
                  icon: Icon(Icons.more_vert,
                      size: 18, color: Colors.grey.shade500),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 16),
                          SizedBox(width: 8),
                          Text('Editar'),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline,
                              size: 16, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Eliminar', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (value) => _handleMenuAction(value, task),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // INLINE CELL BUILDERS
  // ══════════════════════════════════════════════════════════════════

  // ── Title cell: click to edit inline ──
  Widget _buildTitleCell(TaskModel task, bool isDimmed, bool isCompleted) {
    return InkWell(
      onTap: () {
        setState(() {
          _editingTitleTaskId = task.id;
          _titleController.text = task.title;
        });
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              decoration: isCompleted ? TextDecoration.lineThrough : null,
              color: isDimmed ? Colors.grey.shade500 : null,
            ),
          ),
          if (task.description != null && task.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                task.description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          if (_hasLinks(task))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  if (task.linkedJobNumber != null)
                    _buildLinkBadge(
                      icon: Icons.build,
                      label: 'Trabajo #${task.linkedJobNumber}',
                      color: Colors.blue,
                      onTap: () => context.go('/taller/pegas'),
                    ),
                  if (task.linkedPurchaseInvoiceNumber != null &&
                      task.linkedPurchaseInvoiceId != null)
                    _buildLinkBadge(
                      icon: Icons.receipt,
                      label: 'Compra #${task.linkedPurchaseInvoiceNumber}',
                      color: Colors.orange,
                      onTap: () => context
                          .go('/purchases/${task.linkedPurchaseInvoiceId}'),
                    ),
                  if (task.linkedSalesInvoiceNumber != null &&
                      task.linkedSalesInvoiceId != null)
                    _buildLinkBadge(
                      icon: Icons.point_of_sale,
                      label: 'Venta #${task.linkedSalesInvoiceNumber}',
                      color: Colors.green,
                      onTap: () => context
                          .go('/sales/invoices/${task.linkedSalesInvoiceId}'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTitleEditor(TaskModel task) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _titleController,
            autofocus: true,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onSubmitted: (value) => _saveTitleEdit(task, value),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.check, size: 18, color: Colors.green),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () => _saveTitleEdit(task, _titleController.text),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 18, color: Colors.grey),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () => setState(() => _editingTitleTaskId = null),
        ),
      ],
    );
  }

  // ── Status badge (click → dropdown menu) ──
  Widget _buildStatusBadge(TaskModel task) {
    final statusColor = _statusColor(task.status);
    final statusName = _translateStatus(task.status);

    return InkWell(
      onTap: () => _showStatusMenu(task),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: statusColor.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                statusName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Priority badge (click → dropdown menu) ──
  Widget _buildPriorityBadge(TaskModel task) {
    final color = _priorityColor(task.priority);
    return InkWell(
      onTap: () => _showPriorityMenu(task),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_priorityIcon(task.priority), size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              _translatePriority(task.priority),
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Date cell (click → date picker) ──
  Widget _buildDateCell(TaskModel task, bool isOverdue) {
    return InkWell(
      onTap: () => _showDatePicker(task),
      borderRadius: BorderRadius.circular(6),
      child: task.dueDate != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isOverdue
                          ? Icons.warning_amber_rounded
                          : Icons.event_outlined,
                      size: 14,
                      color: isOverdue ? Colors.red : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('dd/MM/yy').format(task.dueDate!),
                      style: TextStyle(
                        fontSize: 13,
                        color: isOverdue ? Colors.red : null,
                        fontWeight:
                            isOverdue ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                if (isOverdue)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Vencida',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ),
                  ),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.event_outlined,
                    size: 14, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text(
                  'Sin plazo',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
    );
  }

  // ── Assignee cell (click → user menu) ──
  Widget _buildAssigneeCell(TaskModel task, ThemeData theme) {
    return InkWell(
      onTap: () => _showAssigneeMenu(task),
      borderRadius: BorderRadius.circular(6),
      child: task.assigneeName != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    task.assigneeName!.substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    task.assigneeName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_add_outlined,
                    size: 14, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text(
                  'Sin asignar',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
    );
  }

  // ── Attachment cell: thumbnails + count + add button ──
  Widget _buildAttachmentCell(TaskModel task) {
    final attachments = task.attachments;
    final count = attachments.length;

    if (count == 0) {
      // Empty state: small + button, left-aligned
      return Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: () => _pickFilesForTask(task),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              border: Border.all(
                  color: Colors.grey.shade300, style: BorderStyle.solid),
              borderRadius: BorderRadius.circular(4),
              color: Colors.grey.shade50,
            ),
            child: Center(
              child: Icon(Icons.add, size: 16, color: Colors.grey.shade400),
            ),
          ),
        ),
      );
    }

    final first = attachments.first;
    final firstUrl = first['url'] as String? ?? '';
    final firstType = first['type'] as String? ?? '';
    final isImg = _isImageType(firstType);

    return InkWell(
      onTap: () => _pickFilesForTask(task),
      borderRadius: BorderRadius.circular(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // First attachment thumbnail or icon
          if (isImg)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                firstUrl,
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(Icons.broken_image,
                      size: 16, color: Colors.grey),
                ),
              ),
            )
          else
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Icon(
                _fileIcon(firstType),
                size: 16,
                color: Colors.blueGrey,
              ),
            ),
          // Additional count badge
          if (count > 1) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '+${count - 1}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _isImageType(String mimeType) {
    return mimeType.startsWith('image/');
  }

  IconData _fileIcon(String mimeType) {
    if (mimeType == 'application/pdf') return Icons.picture_as_pdf_outlined;
    if (mimeType.contains('spreadsheet') || mimeType.contains('excel')) {
      return Icons.table_chart_outlined;
    }
    if (mimeType.contains('word') || mimeType.contains('document')) {
      return Icons.description_outlined;
    }
    if (mimeType.startsWith('video/')) return Icons.videocam_outlined;
    return Icons.insert_drive_file_outlined;
  }

  Future<void> _pickFilesForTask(TaskModel task) async {
    if (task.id == null) return;

    final taskService = context.read<TaskService>();
    final messenger = ScaffoldMessenger.of(context);

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    int uploaded = 0;
    for (final file in result.files) {
      if (file.bytes == null) continue;
      try {
        final ext = file.name.split('.').last.toLowerCase();
        String mimeType;
        switch (ext) {
          case 'jpg':
          case 'jpeg':
            mimeType = 'image/jpeg';
            break;
          case 'png':
            mimeType = 'image/png';
            break;
          case 'gif':
            mimeType = 'image/gif';
            break;
          case 'webp':
            mimeType = 'image/webp';
            break;
          case 'pdf':
            mimeType = 'application/pdf';
            break;
          case 'mp4':
            mimeType = 'video/mp4';
            break;
          case 'mov':
            mimeType = 'video/quicktime';
            break;
          default:
            mimeType = 'application/octet-stream';
        }

        await taskService.addAttachment(
          taskId: task.id!,
          fileName: file.name,
          bytes: file.bytes!,
          mimeType: mimeType,
        );
        uploaded++;
      } catch (e) {
        debugPrint('Error uploading ${file.name}: $e');
      }
    }

    if (uploaded > 0 && mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
              '$uploaded archivo${uploaded > 1 ? 's' : ''} subido${uploaded > 1 ? 's' : ''}'),
        ),
      );
    }
  }

  Widget _buildLinkBadge({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: color.withValues(alpha: 0.8)),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: color.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // INLINE EDIT ACTIONS
  // ══════════════════════════════════════════════════════════════════

  void _saveTitleEdit(TaskModel task, String newTitle) async {
    setState(() => _editingTitleTaskId = null);
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty || trimmed == task.title) return;
    await _updateTask(task.copyWith(title: trimmed));
  }

  void _showStatusMenu(TaskModel task) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu<TaskStatus>(
      context: context,
      position: RelativeRect.fromRect(
        button.localToGlobal(Offset.zero) & button.size,
        Offset.zero & overlay.size,
      ),
      items: TaskStatus.values.map((status) {
        final color = _statusColor(status);
        final isSelected = task.status == status;
        return PopupMenuItem<TaskStatus>(
          value: status,
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: Colors.black54, width: 2)
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _translateStatus(status),
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              if (isSelected) ...[
                const Spacer(),
                const Icon(Icons.check, size: 16),
              ],
            ],
          ),
        );
      }).toList(),
    ).then((newStatus) {
      if (newStatus != null && newStatus != task.status) {
        _updateTask(task.copyWith(status: newStatus));
      }
    });
  }

  void _showPriorityMenu(TaskModel task) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu<TaskPriority>(
      context: context,
      position: RelativeRect.fromRect(
        button.localToGlobal(Offset.zero) & button.size,
        Offset.zero & overlay.size,
      ),
      items: TaskPriority.values.map((priority) {
        final color = _priorityColor(priority);
        final isSelected = task.priority == priority;
        return PopupMenuItem<TaskPriority>(
          value: priority,
          child: Row(
            children: [
              Icon(_priorityIcon(priority), size: 16, color: color),
              const SizedBox(width: 10),
              Text(
                _translatePriority(priority),
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              if (isSelected) ...[
                const Spacer(),
                const Icon(Icons.check, size: 16),
              ],
            ],
          ),
        );
      }).toList(),
    ).then((newPriority) {
      if (newPriority != null && newPriority != task.priority) {
        _updateTask(task.copyWith(priority: newPriority));
      }
    });
  }

  void _showDatePicker(TaskModel task) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: task.dueDate ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 3)),
      helpText: 'Fecha de vencimiento',
      cancelText: task.dueDate != null ? 'Quitar fecha' : 'Cancelar',
    );

    // If user presses cancel and there was a date, offer to clear it
    if (picked == null && task.dueDate != null) {
      if (!mounted) return;
      final clear = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿Quitar fecha?'),
          content: const Text(
              '¿Deseas quitar la fecha de vencimiento de esta tarea?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Sí, quitar'),
            ),
          ],
        ),
      );
      if (clear == true) {
        // We need to set dueDate to null — copyWith can't do this by default
        // so we update via the service directly
        await _updateTaskField(task, 'due_date', null);
      }
      return;
    }

    if (picked != null) {
      await _updateTask(task.copyWith(dueDate: picked));
    }
  }

  void _showAssigneeMenu(TaskModel task) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    final items = <PopupMenuEntry<String?>>[];

    // "Unassign" option
    items.add(PopupMenuItem<String?>(
      value: '__none__',
      child: Row(
        children: [
          Icon(Icons.person_off_outlined,
              size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 10),
          Text('Sin asignar',
              style: TextStyle(
                  fontStyle: FontStyle.italic, color: Colors.grey.shade600)),
          if (task.assignedTo == null) ...[
            const Spacer(),
            const Icon(Icons.check, size: 16),
          ],
        ],
      ),
    ));
    items.add(const PopupMenuDivider());

    // User list
    if (_users != null) {
      for (final user in _users!) {
        final userId = user['user_id']?.toString();
        final fullName =
            user['full_name'] as String? ?? user['email'] as String? ?? '?';
        final isSelected = task.assignedTo == userId;
        items.add(PopupMenuItem<String?>(
          value: userId,
          child: Row(
            children: [
              CircleAvatar(
                radius: 10,
                child: Text(fullName.substring(0, 1).toUpperCase(),
                    style: const TextStyle(fontSize: 10)),
              ),
              const SizedBox(width: 10),
              Text(
                fullName,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              if (isSelected) ...[
                const Spacer(),
                const Icon(Icons.check, size: 16),
              ],
            ],
          ),
        ));
      }
    } else {
      items.add(const PopupMenuItem<String?>(
        enabled: false,
        value: null,
        child: Text('Cargando usuarios...'),
      ));
    }

    showMenu<String?>(
      context: context,
      position: RelativeRect.fromRect(
        button.localToGlobal(Offset.zero) & button.size,
        Offset.zero & overlay.size,
      ),
      items: items,
    ).then((selectedUserId) {
      if (selectedUserId == null) return; // dismissed

      if (selectedUserId == '__none__') {
        _updateTaskField(task, 'assigned_to', null);
        return;
      }

      // Find user name
      final user = _users?.firstWhere(
          (u) => u['user_id']?.toString() == selectedUserId,
          orElse: () => {});
      final name =
          user?['full_name'] as String? ?? user?['email'] as String? ?? '';

      _updateTask(
          task.copyWith(assignedTo: selectedUserId, assigneeName: name));
    });
  }

  // ══════════════════════════════════════════════════════════════════
  // ACTIONS
  // ══════════════════════════════════════════════════════════════════

  void _toggleStatus(TaskModel task) {
    final newStatus = task.status == TaskStatus.completed
        ? TaskStatus.pending
        : TaskStatus.completed;
    _updateTask(task.copyWith(status: newStatus));
  }

  Future<void> _updateTask(TaskModel updatedTask) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<TaskService>().updateTask(updatedTask);
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  /// Update a single field directly (for nullable fields like due_date)
  Future<void> _updateTaskField(
      TaskModel task, String field, dynamic value) async {
    final messenger = ScaffoldMessenger.of(context);
    final taskService = context.read<TaskService>();
    try {
      final tenantId = task.tenantId;
      if (task.id == null) return;

      await Supabase.instance.client
          .from('smart_tasks')
          .update({field: value})
          .eq('id', task.id!)
          .eq('tenant_id', tenantId);

      // Refresh from database
      await taskService.fetchTasks();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _handleMenuAction(String value, TaskModel task) async {
    if (value == 'edit') {
      showDialog(
        context: context,
        builder: (context) => TaskFormDialog(taskToEdit: task),
      );
      return;
    }

    if (value == 'delete') {
      final messenger = ScaffoldMessenger.of(context);
      final taskService = context.read<TaskService>();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Eliminar tarea'),
          content: Text('¿Estás seguro de eliminar "${task.title}"?'),
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

      if (confirmed == true && task.id != null) {
        try {
          await taskService.deleteTask(task.id!);
          if (mounted) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Tarea eliminada')),
            );
          }
        } catch (e) {
          if (mounted) {
            messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
          }
        }
      }
    }
  }

  bool _hasLinks(TaskModel task) {
    return task.linkedJobNumber != null ||
        (task.linkedPurchaseInvoiceNumber != null &&
            task.linkedPurchaseInvoiceId != null) ||
        (task.linkedSalesInvoiceNumber != null &&
            task.linkedSalesInvoiceId != null);
  }

  // ══════════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════════

  Color _statusColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return Colors.amber.shade700;
      case TaskStatus.inProgress:
        return Colors.blue;
      case TaskStatus.completed:
        return Colors.green;
      case TaskStatus.cancelled:
        return Colors.grey;
    }
  }

  Color _priorityColor(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.urgent:
        return Colors.red;
      case TaskPriority.high:
        return Colors.orange;
      case TaskPriority.normal:
        return Colors.blue;
      case TaskPriority.low:
        return Colors.grey;
    }
  }

  IconData _priorityIcon(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.urgent:
        return Icons.priority_high;
      case TaskPriority.high:
        return Icons.arrow_upward;
      case TaskPriority.normal:
        return Icons.drag_handle;
      case TaskPriority.low:
        return Icons.arrow_downward;
    }
  }

  String _translateStatus(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return 'Pendiente';
      case TaskStatus.inProgress:
        return 'En Curso';
      case TaskStatus.completed:
        return 'Completada';
      case TaskStatus.cancelled:
        return 'Cancelada';
    }
  }

  String _translatePriority(TaskPriority priority) {
    switch (priority) {
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
