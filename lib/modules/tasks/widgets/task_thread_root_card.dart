import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_status_badge.dart';
import '../models/smart_task_job_item.dart';
import '../models/task_model.dart';

/// La tarea que origina un hilo interno.
///
/// La publicación que representa una tarea dentro de su canal.
/// Las respuestas se abren aparte y conservan esta publicación como contexto,
/// igual que un hilo profesional: responder no crea otro tema en el canal.
class TaskThreadRootCard extends StatelessWidget {
  const TaskThreadRootCard({
    super.key,
    required this.task,
    required this.links,
    required this.replyCount,
    required this.onOpenTask,
    this.onOpenReplies,
    this.jobNumber,
    this.jobSummary,
    this.onOpenJob,
    this.onOpenLinkedContext,
  });

  final TaskModel task;
  final List<SmartTaskJobItem> links;
  final int replyCount;
  final String? jobNumber;
  final String? jobSummary;
  final VoidCallback onOpenTask;
  final VoidCallback? onOpenReplies;
  final VoidCallback? onOpenJob;
  final VoidCallback? onOpenLinkedContext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final linkedContext = task.linkedContextTarget;
    final hasWorkshopContext = task.linkedJobId != null || links.isNotEmpty;

    return Semantics(
      key: const ValueKey<String>('task-thread-root'),
      container: true,
      label:
          'Tarea, ${task.title}, ${_statusLabel(task)}, ${_replyLabel(replyCount)}',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    'TAREA',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                VbStatusBadge(
                  label: _statusLabel(task),
                  tone: _statusTone(task.status),
                  dense: true,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              task.title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if ((task.description ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                task.description!.trim(),
                style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
              ),
            ],
            const SizedBox(height: 7),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (task.priority != TaskPriority.normal)
                  VbStatusBadge(
                    label: _priorityLabel(task.priority),
                    tone: task.priority == TaskPriority.urgent
                        ? VbStatusTone.danger
                        : VbStatusTone.warning,
                    dense: true,
                  ),
                if (task.dueDate != null)
                  Text(
                    'Plazo ${DateFormat('dd/MM').format(task.dueDate!)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if ((task.creatorName ?? '').trim().isNotEmpty)
                  Text(
                    'Creada por ${task.creatorName!.trim()}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                if ((task.assigneeName ?? '').trim().isNotEmpty)
                  Text(
                    'para ${task.assigneeName!.trim()}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            if (task.isBlocked && (task.blockedReason ?? '').trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Text(
                  'Bloqueada: ${task.blockedReason!.trim()}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: roles.danger.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (hasWorkshopContext) ...[
              const SizedBox(height: 10),
              Divider(height: 1, color: roles.hairline),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'TRABAJO #${jobNumber ?? '—'}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  if (onOpenJob != null)
                    TextButton.icon(
                      onPressed: onOpenJob,
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: const Text('Abrir trabajo'),
                    ),
                ],
              ),
              if (links.isEmpty && (jobSummary ?? '').trim().isNotEmpty)
                Text(
                  jobSummary!.trim(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              for (final link in links)
                Padding(
                  key: ValueKey<String>('task-thread-service-${link.id}'),
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        link.isInvalidated
                            ? Icons.link_off
                            : Icons.build_outlined,
                        size: 13,
                        color: link.isInvalidated
                            ? roles.danger.accent
                            : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${link.itemName}'
                              '${link.bikeLabel != null ? ' · ${link.bikeLabel}' : ''}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                decoration: link.isInvalidated
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            if (link.itemInstructions != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                link.itemInstructions!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  decoration: link.isInvalidated
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ],
                            if (link.isInvalidated) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Este servicio fue eliminado del trabajo después de asignar la tarea.',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: roles.danger.accent,
                                ),
                              ),
                            ] else if (link.contextChanged) ...[
                              const SizedBox(height: 2),
                              Text(
                                'El servicio o sus instrucciones cambiaron. Abre el trabajo para revisar la versión actual.',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.tertiary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (linkedContext != null) ...[
              const SizedBox(height: 10),
              Divider(height: 1, color: roles.hairline),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    _contextIcon(linkedContext.kind),
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '${_contextLabel(linkedContext.kind)} · ${linkedContext.label}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (onOpenLinkedContext != null)
                    TextButton(
                      onPressed: onOpenLinkedContext,
                      child: const Text('Abrir'),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Divider(height: 1, color: roles.hairline),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.forum_outlined,
                  size: 15,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: onOpenReplies == null
                      ? Text(
                          _replyLabel(replyCount),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : TextButton(
                          key: const ValueKey<String>(
                            'task-thread-open-replies',
                          ),
                          onPressed: onOpenReplies,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            alignment: Alignment.centerLeft,
                          ),
                          child: Text(_replyLabel(replyCount)),
                        ),
                ),
                TextButton.icon(
                  onPressed: onOpenTask,
                  icon: const Icon(Icons.open_in_new, size: 14),
                  label: const Text('Abrir tarea'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _replyLabel(int count) => switch (count) {
        0 => 'Sin respuestas todavía',
        1 => '1 respuesta',
        _ => '$count respuestas',
      };

  static String _statusLabel(TaskModel task) => switch (task.status) {
        TaskStatus.pending =>
          task.awaitsAcknowledgement ? 'Por aceptar' : 'Pendiente',
        TaskStatus.inProgress => 'En curso',
        TaskStatus.blocked => 'Bloqueada',
        TaskStatus.completed => 'Completada',
        TaskStatus.cancelled => 'Cancelada',
      };

  static VbStatusTone _statusTone(TaskStatus status) => switch (status) {
        TaskStatus.pending || TaskStatus.inProgress => VbStatusTone.info,
        TaskStatus.blocked => VbStatusTone.danger,
        TaskStatus.completed => VbStatusTone.success,
        TaskStatus.cancelled => VbStatusTone.neutral,
      };

  static String _priorityLabel(TaskPriority priority) => switch (priority) {
        TaskPriority.low => 'Prioridad baja',
        TaskPriority.normal => 'Prioridad normal',
        TaskPriority.high => 'Prioridad alta',
        TaskPriority.urgent => 'Prioridad urgente',
      };

  static String _contextLabel(TaskContextKind kind) => switch (kind) {
        TaskContextKind.customer => 'Cliente',
        TaskContextKind.supplier => 'Proveedor',
        TaskContextKind.salesInvoice => 'Venta / factura',
        TaskContextKind.purchaseInvoice => 'Compra / documento',
        TaskContextKind.workshopJob => 'Trabajo',
        TaskContextKind.none => 'Contexto',
      };

  static IconData _contextIcon(TaskContextKind kind) => switch (kind) {
        TaskContextKind.customer => Icons.person_outline,
        TaskContextKind.supplier => Icons.storefront_outlined,
        TaskContextKind.salesInvoice => Icons.receipt_long_outlined,
        TaskContextKind.purchaseInvoice => Icons.inventory_2_outlined,
        TaskContextKind.workshopJob => Icons.build_outlined,
        TaskContextKind.none => Icons.link_outlined,
      };
}

/// Estado transitorio/honesto mientras el contexto de la conversación llega
/// antes que la caché de tareas.
class TaskThreadRootLoadingCard extends StatelessWidget {
  const TaskThreadRootLoadingCard({
    super.key,
    required this.title,
    required this.replyCount,
    required this.onOpenTask,
    this.onOpenReplies,
  });

  final String title;
  final int replyCount;
  final VoidCallback onOpenTask;
  final VoidCallback? onOpenReplies;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey<String>('task-thread-root-loading'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.trim().isEmpty ? 'Tarea vinculada' : title.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  replyCount == 1 ? '1 respuesta' : '$replyCount respuestas',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (onOpenReplies != null)
            TextButton(
              onPressed: onOpenReplies,
              child: const Text('Ver hilo'),
            ),
          TextButton(
            onPressed: onOpenTask,
            child: const Text('Abrir tarea'),
          ),
        ],
      ),
    );
  }
}
