import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../tasks/models/task_model.dart';
import '../../tasks/services/task_service.dart';
import 'task_form_dialog.dart';
import 'package:go_router/go_router.dart';

class PegasTasksWidget extends StatefulWidget {
  const PegasTasksWidget({super.key});

  @override
  State<PegasTasksWidget> createState() => _PegasTasksWidgetState();
}

class _PegasTasksWidgetState extends State<PegasTasksWidget> {
  // Filters
  TaskStatus? _statusFilter;
  TaskPriority? _priorityFilter;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
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

        return Column(
          children: [
            _buildToolbar(),
            const Divider(height: 1),
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

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        children: [
          // Search
          SizedBox(
            width: 300,
            height: 40,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Buscar tareas...',
                prefixIcon: const Icon(Icons.search, size: 20),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
          const SizedBox(width: 16),

          // Status Filter
          DropdownButton<TaskStatus?>(
            value: _statusFilter,
            hint: const Text('Estado'),
            underline: const SizedBox(),
            items: [
              const DropdownMenuItem(
                  value: null, child: Text('Todos los estados')),
              ...TaskStatus.values.map((status) => DropdownMenuItem(
                    value: status,
                    child: Text(_translateStatus(status)),
                  )),
            ],
            onChanged: (val) => setState(() => _statusFilter = val),
          ),
          const SizedBox(width: 16),

          // Priority Filter
          DropdownButton<TaskPriority?>(
            value: _priorityFilter,
            hint: const Text('Prioridad'),
            underline: const SizedBox(),
            items: [
              const DropdownMenuItem(
                  value: null, child: Text('Todas las prioridades')),
              ...TaskPriority.values.map((priority) => DropdownMenuItem(
                    value: priority,
                    child: Text(_translatePriority(priority)),
                  )),
            ],
            onChanged: (val) => setState(() => _priorityFilter = val),
          ),

          const Spacer(),

          // Add Task Button
          FilledButton.icon(
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => const TaskFormDialog(),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('Nueva Tarea'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.task_alt, size: 64, color: Colors.grey.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(
            'No hay tareas',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.grey.shade600,
                ),
          ),
          const SizedBox(height: 8),
          const Text('Crea una nueva tarea o ajusta los filtros.'),
        ],
      ),
    );
  }

  Widget _buildTasksList(List<TaskModel> tasks) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final task = tasks[index];
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => TaskFormDialog(taskToEdit: task),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Checkbox area
                  Padding(
                    padding: const EdgeInsets.only(top: 2.0, right: 12.0),
                    child: InkWell(
                      onTap: () async {
                        final newStatus = task.status == TaskStatus.completed
                            ? TaskStatus.pending
                            : TaskStatus.completed;

                        try {
                          final updatedTask = task.copyWith(status: newStatus);
                          await context
                              .read<TaskService>()
                              .updateTask(updatedTask);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content:
                                      Text('Error al actualizar tarea: $e')),
                            );
                          }
                        }
                      },
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: task.status == TaskStatus.completed
                                ? Colors.green
                                : Colors.grey.shade400,
                            width: 2,
                          ),
                          color: task.status == TaskStatus.completed
                              ? Colors.green
                              : Colors.transparent,
                        ),
                        child: task.status == TaskStatus.completed
                            ? const Icon(Icons.check,
                                size: 16, color: Colors.white)
                            : null,
                      ),
                    ),
                  ),

                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                task.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            _buildPriorityBadge(task.priority),
                          ],
                        ),
                        if (task.description != null &&
                            task.description!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            task.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),

                        // Metadata Row
                        Row(
                          children: [
                            if (task.dueDate != null) ...[
                              Icon(Icons.event,
                                  size: 14, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text(
                                DateFormat('dd MMM yyyy').format(task.dueDate!),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: task.dueDate!
                                              .isBefore(DateTime.now()) &&
                                          task.status != TaskStatus.completed
                                      ? Colors.red
                                      : Colors.grey.shade700,
                                  fontWeight: task.dueDate!
                                              .isBefore(DateTime.now()) &&
                                          task.status != TaskStatus.completed
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              const SizedBox(width: 16),
                            ],

                            // Contextual Links Badges
                            if (task.linkedJobNumber != null)
                              _buildLinkBadge(
                                icon: Icons.build,
                                label: 'Pega #${task.linkedJobNumber}',
                                color: Colors.blue,
                                onTap: () {
                                  // For Jobs, PegasTablePage is usually the main table.
                                  // We can route them there.
                                  context.go('/taller/pegas');
                                },
                              ),
                            if (task.linkedPurchaseInvoiceNumber != null &&
                                task.linkedPurchaseInvoiceId != null)
                              _buildLinkBadge(
                                icon: Icons.receipt,
                                label:
                                    'Compra #${task.linkedPurchaseInvoiceNumber}',
                                color: Colors.orange,
                                onTap: () {
                                  context.go(
                                      '/purchases/${task.linkedPurchaseInvoiceId}');
                                },
                              ),
                            if (task.linkedSalesInvoiceNumber != null &&
                                task.linkedSalesInvoiceId != null)
                              _buildLinkBadge(
                                icon: Icons.point_of_sale,
                                label:
                                    'Venta #${task.linkedSalesInvoiceNumber}',
                                color: Colors.green,
                                onTap: () {
                                  context.go(
                                      '/sales/invoices/${task.linkedSalesInvoiceId}');
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Assignee Avatar
                  if (task.assigneeName != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 16.0),
                      child: Tooltip(
                        message: 'Asignado a: ${task.assigneeName}',
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor:
                              Theme.of(context).colorScheme.primaryContainer,
                          child: Text(
                            task.assigneeName!.substring(0, 1).toUpperCase(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLinkBadge({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: color.withOpacity(0.8)),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: color.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPriorityBadge(TaskPriority priority) {
    Color color;
    String labelText;

    switch (priority) {
      case TaskPriority.urgent:
        color = Colors.red;
        labelText = 'Urgente';
        break;
      case TaskPriority.high:
        color = Colors.orange;
        labelText = 'Alta';
        break;
      case TaskPriority.normal:
        color = Colors.blue;
        labelText = 'Normal';
        break;
      case TaskPriority.low:
        color = Colors.grey;
        labelText = 'Baja';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        labelText,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
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
