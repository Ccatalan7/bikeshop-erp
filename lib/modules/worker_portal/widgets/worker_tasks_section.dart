import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/widgets/vb_overlay_surfaces.dart';
import '../services/worker_tasks_service.dart';

/// «Mis tareas» del portal del trabajador.
///
/// Proyección mínima y segura (`get_my_worker_tasks_v1`): trabajo, bicicletas y
/// servicios e instrucciones sin precios, plazo y creador. Acciones acotadas al
/// propio ciclo: Aceptar / Devolver / Iniciar / Bloquear / Desbloquear /
/// Completar, marcar cada servicio hecho y dejar la nota para el siguiente
/// turno. Sin hilo: el principal de portal no es principal de mensajería.
class WorkerTasksSection extends StatefulWidget {
  const WorkerTasksSection(
      {super.key, this.service, this.enableRealtime = true});

  /// Inyectable para pruebas; por defecto habla con las RPC del portal.
  final WorkerTasksService? service;

  /// Las pruebas de widget apagan el canal (no hay Supabase real).
  final bool enableRealtime;

  @override
  State<WorkerTasksSection> createState() => _WorkerTasksSectionState();
}

class _WorkerTasksSectionState extends State<WorkerTasksSection> {
  late final WorkerTasksService _service =
      widget.service ?? WorkerTasksService();
  late Future<List<WorkerTaskView>> _future;
  final Set<String> _busy = {};

  /// Lo que se acaba de marcar, por `tarea|servicio`, mientras el servidor
  /// confirma y la lista se recarga: la casilla responde al toque.
  final Map<String, bool> _optimisticDone = {};
  RealtimeChannel? _channel;
  Timer? _fallbackTimer;

  @override
  void initState() {
    super.initState();
    _future = _service.fetchMyTasks();
    if (widget.enableRealtime) {
      _setupRealtime();
      // Respaldo por si el canal se cae en silencio: la bandeja del taller
      // usa el mismo colchón de 60 s.
      _fallbackTimer = Timer.periodic(
        const Duration(seconds: 60),
        (_) => _reload(),
      );
    }
  }

  /// Una tarea asignada por la manager aparece en vivo: canal sobre las filas
  /// propias (la RLS del asignado limita la entrega a lo suyo).
  void _setupRealtime() {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    _channel = Supabase.instance.client
        .channel('worker-tasks-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'smart_tasks',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'assigned_to',
            value: uid,
          ),
          callback: (_) {
            if (mounted) _reload();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      unawaited(channel.unsubscribe());
    }
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    final next = _service.fetchMyTasks();
    setState(() {
      _future = next;
    });
  }

  Future<void> _run(
    WorkerTaskView task,
    Future<WorkerTaskView> Function() command,
  ) async {
    setState(() => _busy.add(task.id));
    try {
      await command();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo completar la acción: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy.remove(task.id));
        _reload();
      }
    }
  }

  Future<void> _markService(
      WorkerTaskView task, String jobItemId, bool done) async {
    final key = '${task.id}|$jobItemId';
    setState(() => _optimisticDone[key] = done);
    try {
      await _service.setJobItemDone(task.id, jobItemId, done: done);
      if (!mounted) return;
      final next = _service.fetchMyTasks();
      setState(() {
        _future = next;
      });
      await next;
    } catch (error) {
      if (mounted) {
        setState(() => _optimisticDone.remove(key));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo marcar el servicio: $error')),
        );
      }
    }
    // Si salió bien, la marca optimista se retira cuando la lista recargada
    // ya dice lo mismo (ver `build`): retirarla aquí la hacía parpadear un
    // cuadro, porque la lista nueva llega a la pantalla un poco después.
  }

  Future<void> _editHandoffNote(
      BuildContext anchorContext, WorkerTaskView task) async {
    final note = await showVbReasonPrompt(
      anchorContext: anchorContext,
      title: 'Nota para el siguiente turno',
      hint: 'Dónde quedó y qué falta (ej: falta la piola, llega mañana)',
      confirmLabel: 'Guardar nota',
      initialText: task.handoffNote,
    );
    if (note == null) return;
    await _run(task, () => _service.setHandoffNote(task.id, note));
  }

  Future<void> _askReasonAnd(
    BuildContext anchorContext,
    WorkerTaskView task,
    String title,
    String hint,
    Future<WorkerTaskView> Function(String reason) command,
  ) async {
    final reason = await showVbReasonPrompt(
      anchorContext: anchorContext,
      title: title,
      hint: hint,
      confirmLabel: title,
    );
    if (reason == null || reason.isEmpty) return;
    await _run(task, () => command(reason));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<WorkerTaskView>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _MessageCard(
            icon: Icons.error_outline,
            message: 'No se pudieron cargar tus tareas.',
            action: TextButton(
              onPressed: _reload,
              child: const Text('Reintentar'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final tasks = snapshot.data!;
        // Lo que el servidor ya confirmó deja de ser optimista.
        _optimisticDone.removeWhere((key, done) {
          final separator = key.indexOf('|');
          final taskId = key.substring(0, separator);
          final jobItemId = key.substring(separator + 1);
          for (final task in tasks) {
            if (task.id != taskId) continue;
            for (final item in task.jobItems) {
              if (item['job_item_id']?.toString() == jobItemId) {
                return (item['done_at'] != null) == done;
              }
            }
          }
          return false;
        });
        final open = tasks.where((task) => !task.isDone).toList();
        final done = tasks.where((task) => task.isDone).take(10).toList();
        if (tasks.isEmpty) {
          return const _MessageCard(
            icon: Icons.task_alt,
            message: 'No tienes tareas asignadas.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final task in open)
              _WorkerTaskCard(
                task: task,
                busy: _busy.contains(task.id),
                isServiceDone: (jobItemId, persisted) =>
                    _optimisticDone['${task.id}|$jobItemId'] ?? persisted,
                onMarkService: (jobItemId, done) =>
                    _markService(task, jobItemId, done),
                onEditNote: (anchor) => _editHandoffNote(anchor, task),
                onClearNote: () =>
                    _run(task, () => _service.setHandoffNote(task.id, null)),
                onAcknowledge: () =>
                    _run(task, () => _service.acknowledge(task.id)),
                onReturn: (anchor) => _askReasonAnd(
                    anchor,
                    task,
                    'Devolver',
                    '¿Por qué la devuelves?',
                    (r) => _service.returnTask(task.id, r)),
                onStart: () => _run(
                    task,
                    () =>
                        _service.start(task.id, expectedVersion: task.version)),
                onBlock: (anchor) => _askReasonAnd(
                    anchor,
                    task,
                    'Bloquear',
                    '¿Qué te falta? (ej: repuesto)',
                    (r) => _service.block(task.id, r,
                        expectedVersion: task.version)),
                onUnblock: () => _run(
                    task,
                    () => _service.unblock(task.id,
                        expectedVersion: task.version)),
                onComplete: () => _run(
                    task,
                    () => _service.complete(task.id,
                        expectedVersion: task.version)),
              ),
            if (done.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('COMPLETADAS RECIENTES',
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
              const SizedBox(height: 6),
              for (final task in done)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '✓ ${task.title}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _WorkerTaskCard extends StatelessWidget {
  const _WorkerTaskCard({
    required this.task,
    required this.busy,
    required this.isServiceDone,
    required this.onMarkService,
    required this.onEditNote,
    required this.onClearNote,
    required this.onAcknowledge,
    required this.onReturn,
    required this.onStart,
    required this.onBlock,
    required this.onUnblock,
    required this.onComplete,
  });

  final WorkerTaskView task;
  final bool busy;
  final bool Function(String jobItemId, bool persisted) isServiceDone;
  final void Function(String jobItemId, bool done) onMarkService;
  final void Function(BuildContext anchorContext) onEditNote;
  final VoidCallback onClearNote;
  final VoidCallback onAcknowledge;
  final void Function(BuildContext anchorContext) onReturn;
  final VoidCallback onStart;
  final void Function(BuildContext anchorContext) onBlock;
  final VoidCallback onUnblock;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overdue = task.isOverdueAt(DateTime.now());
    String? itemId(Map<String, dynamic> item) =>
        item['job_item_id']?.toString();
    bool done(Map<String, dynamic> item) {
      final id = itemId(item);
      final persisted = item['done_at'] != null;
      return id == null ? persisted : isServiceDone(id, persisted);
    }

    final liveItems =
        task.jobItems.where((item) => item['invalidated'] != true).toList();
    final doneCount = liveItems.where(done).length;
    final allDone = liveItems.isNotEmpty && doneCount == liveItems.length;
    // Se marca mientras la tarea está aceptada y abierta.
    final canMark = !task.isDone && !task.awaitsAcknowledgement;

    final actions = <Widget>[];
    if (task.awaitsAcknowledgement) {
      actions.add(FilledButton(
          onPressed: busy ? null : onAcknowledge,
          child: const Text('Aceptar')));
      actions.add(Builder(
          builder: (buttonContext) => OutlinedButton(
              onPressed: busy ? null : () => onReturn(buttonContext),
              child: const Text('Devolver'))));
    } else if (task.isBlocked) {
      actions.add(FilledButton(
          onPressed: busy ? null : onUnblock,
          child: const Text('Desbloquear')));
      actions.add(OutlinedButton(
          onPressed: busy ? null : onComplete, child: const Text('Completar')));
    } else {
      if (task.status == 'pending') {
        actions.add(FilledButton(
            onPressed: busy ? null : onStart, child: const Text('Iniciar')));
      }
      actions.add(allDone
          ? FilledButton(
              onPressed: busy ? null : onComplete,
              child: const Text('Completar'))
          : FilledButton.tonal(
              onPressed: busy ? null : onComplete,
              child: const Text('Completar')));
      actions.add(Builder(
          builder: (buttonContext) => OutlinedButton(
              onPressed: busy ? null : () => onBlock(buttonContext),
              child: const Text('Bloquear'))));
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: task.isBlocked
              ? theme.colorScheme.error
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(task.title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (task.dueDate != null)
                Text(
                  DateFormat('dd/MM').format(task.dueDate!),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: overdue
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: overdue ? FontWeight.w700 : null,
                  ),
                ),
            ],
          ),
          if (task.isBlocked && task.blockedReason != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Bloqueada: ${task.blockedReason}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error)),
            ),
          if ((task.description ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(task.description!, style: theme.textTheme.bodySmall),
            ),
          if (task.jobNumber != null || task.bikeLabels.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                [
                  if (task.jobNumber != null) 'Trabajo #${task.jobNumber}',
                  if (task.bikeLabels.isNotEmpty) task.bikeLabels.join(' · '),
                ].join(' — '),
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
            ),
          if (liveItems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                allDone
                    ? 'Todos los servicios hechos'
                    : '$doneCount de ${liveItems.length} servicios hechos',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: allDone
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (task.jobItems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in task.jobItems)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (canMark &&
                              itemId(item) != null &&
                              (item['invalidated'] != true || done(item)))
                            InkWell(
                              key: ValueKey(
                                  'worker-task-service-${itemId(item)}'),
                              borderRadius: BorderRadius.circular(6),
                              onTap: () =>
                                  onMarkService(itemId(item)!, !done(item)),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: done(item),
                                    visualDensity: VisualDensity.compact,
                                    onChanged: (value) => onMarkService(
                                        itemId(item)!, value ?? false),
                                  ),
                                  Expanded(
                                    child: Text(
                                      '${item['item_name']}',
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        decoration: item['invalidated'] == true
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Text(
                              '${done(item) ? '✓' : '•'} ${item['item_name']}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                decoration: item['invalidated'] == true
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          if (done(item) && item['done_at'] != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 12, top: 2),
                              child: Text(
                                [
                                  'Hecho',
                                  if (item['done_by_name'] != null)
                                    item['done_by_name'].toString(),
                                  if (DateTime.tryParse(
                                          item['done_at'].toString())
                                      case final at?)
                                    DateFormat('dd/MM HH:mm')
                                        .format(at.toLocal()),
                                ].join(' · '),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          if ((item['item_instructions']
                                  ?.toString()
                                  .trim()
                                  .isNotEmpty ??
                              false))
                            Padding(
                              padding: const EdgeInsets.only(left: 12, top: 2),
                              child: Text(
                                item['item_instructions'].toString().trim(),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  decoration: item['invalidated'] == true
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                          if (item['invalidated'] == true)
                            Padding(
                              padding: const EdgeInsets.only(left: 12, top: 2),
                              child: Text(
                                'Este servicio fue eliminado del trabajo después de asignar la tarea.',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            )
                          else if (item['context_changed'] == true)
                            Padding(
                              padding: const EdgeInsets.only(left: 12, top: 2),
                              child: Text(
                                'El servicio o sus instrucciones cambiaron después de asignar la tarea.',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.tertiary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (task.handoffNote case final note?)
            Container(
              key: const ValueKey('worker-task-handoff-note'),
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('NOTA PARA EL SIGUIENTE TURNO',
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant,
                      )),
                  const SizedBox(height: 4),
                  Text(note, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (task.handoffNoteByName != null)
                        task.handoffNoteByName!,
                      if (task.handoffNoteAt case final at?)
                        DateFormat('dd/MM HH:mm').format(at.toLocal()),
                    ].join(' · '),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  if (canMark)
                    Wrap(
                      spacing: 4,
                      children: [
                        Builder(
                          builder: (buttonContext) => TextButton(
                            onPressed:
                                busy ? null : () => onEditNote(buttonContext),
                            child: const Text('Cambiar'),
                          ),
                        ),
                        TextButton(
                          onPressed: busy ? null : onClearNote,
                          child: const Text('Borrar'),
                        ),
                      ],
                    ),
                ],
              ),
            )
          else if (canMark)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Builder(
                builder: (buttonContext) => TextButton.icon(
                  key: const ValueKey('worker-task-handoff-add'),
                  onPressed: busy ? null : () => onEditNote(buttonContext),
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: const Text('Dejar nota para el siguiente turno'),
                ),
              ),
            ),
          if (task.displayAssignerName != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Asignada por ${task.displayAssignerName}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 8),
          Text(message, style: theme.textTheme.bodyMedium),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}
