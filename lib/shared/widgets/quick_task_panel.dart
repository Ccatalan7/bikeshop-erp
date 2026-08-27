import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../modules/tasks/models/smart_task_event.dart';
import '../../modules/tasks/models/smart_task_job_item.dart';
import '../../modules/tasks/models/task_assignment_principal.dart';
import '../../modules/tasks/models/task_model.dart';
import '../../modules/tasks/services/task_service.dart';
import '../services/current_user_profile_service.dart';
import '../services/right_toolbar_service.dart';
import '../services/workspace_manager.dart';
import '../themes/vinabike_theme_roles.dart';
import 'vb_marked_date_picker.dart';
import 'vb_overlay_surfaces.dart';
import 'vb_searchable_select.dart';
import 'vb_segmented.dart';
import 'vb_short_select.dart';
import 'vb_status_badge.dart';

/// Alcances de la bandeja. `inbox` es lo asignado a mí; `team` la
/// coordinación del tenant; `personal` mis tareas privadas.
enum TaskTrayScope { inbox, team, personal }

/// Alcance de una tarea vinculada al taller.
///
/// El trabajo es el primer nivel de la jerarquía. Sólo después de elegirlo se
/// decide si la tarea cubre todo el trabajo o una selección explícita de sus
/// servicios; trabajo y servicio nunca son opciones hermanas del mismo selector.
enum TaskJobScope { wholeJob, selectedServices }

/// Abre el detalle routed del trabajo respetando el contrato de retorno:
/// SIEMPRE `push` (el detalle cierra por `ReturnNavigation.close`, nunca con
/// un `go` a la lista que borra el origen).
Future<void> openWorkshopJobFromTray(BuildContext context, String jobId) async {
  await context.read<WorkspaceManager>().pushActiveWorkspace<void>(
        '/taller/pegas/${Uri.encodeComponent(jobId)}',
      );
}

/// Abre el registro principal vinculado sin reemplazar el origen del panel.
Future<void> openTaskContextFromTray(
  BuildContext context,
  TaskContextTarget target,
) async {
  await context
      .read<WorkspaceManager>()
      .pushActiveWorkspace<void>(target.route);
}

/// Borrador del compositor: vive en el panel (no en la superficie O-02/O-05)
/// para que cerrar el rail o cruzar un breakpoint nunca lo bote.
class TaskComposerDraft {
  TaskKind kind = TaskKind.task;
  String title = '';
  String description = '';
  TaskPriority priority = TaskPriority.normal;
  DateTime? dueDate;
  String? assigneeId;
  TaskContextKind contextKind = TaskContextKind.none;
  TaskContextTarget? contextTarget;
  String? jobId;
  TaskJobScope jobScope = TaskJobScope.wholeJob;
  Set<String> selectedItemIds = {};
  TaskVisibility visibility = TaskVisibility.team;

  bool get isEmpty =>
      title.isEmpty &&
      description.isEmpty &&
      dueDate == null &&
      assigneeId == null &&
      contextKind == TaskContextKind.none &&
      contextTarget == null &&
      jobId == null;

  void reset() {
    kind = TaskKind.task;
    title = '';
    description = '';
    priority = TaskPriority.normal;
    dueDate = null;
    assigneeId = null;
    contextKind = TaskContextKind.none;
    contextTarget = null;
    jobId = null;
    jobScope = TaskJobScope.wholeJob;
    selectedItemIds = {};
    visibility = TaskVisibility.team;
  }
}

/// Estado de vista del panel: sobrevive cerrar/reabrir el rail y el cruce de
/// breakpoint, nunca cruza un cambio de tenant (se valida contra el scope de
/// autoridad del servicio al restaurar).
class QuickTaskPanelSession {
  QuickTaskPanelSession({
    required this.authorityScopeKey,
    required this.scope,
    required this.collapsedSections,
    required this.openTaskId,
    required this.composerOpen,
    required this.draft,
    required this.scrollOffset,
  });

  final String authorityScopeKey;
  final TaskTrayScope scope;
  final Set<String> collapsedSections;
  final String? openTaskId;
  final bool composerOpen;
  final TaskComposerDraft draft;
  final double scrollOffset;
}

/// Bandeja rápida de Tareas del rail derecho.
///
/// Columna: selector de alcance (S-04), lista agrupada (filas T-01) y una
/// barra inferior con «Nueva tarea», que abre el compositor neutral en su host
/// canónico — popover O-02 anclado en escritorio, hoja O-05 en compacto. Un
/// único vínculo opcional revela bajo demanda Cliente, Proveedor, Venta,
/// Compra o, sólo para Taller, trabajo → todos/algunos servicios reales por
/// bicicleta. El detalle reemplaza la lista in-pane con acciones de ciclo de
/// vida según autoridad y el hilo canónico por tarea.
class QuickTaskPanel extends StatefulWidget {
  const QuickTaskPanel({super.key});

  @override
  State<QuickTaskPanel> createState() => _QuickTaskPanelState();
}

class _QuickTaskPanelState extends State<QuickTaskPanel> {
  static const _tool = ToolbarTool.tasks;

  TaskTrayScope _scope = TaskTrayScope.inbox;
  final Set<String> _collapsedSections = {'Completadas'};
  String? _openTaskId;
  final ScrollController _listScroll = ScrollController();

  final TaskComposerDraft _draft = TaskComposerDraft();
  bool _composerVisible = false;

  // Sólo el directorio se carga al abrir. Los contextos de negocio son
  // progresivos: se consultan después de que el operador elige uno.
  List<TaskAssignmentPrincipal> _directory = const [];
  final List<TaskLinkableJob> _linkableJobs = const [];
  Map<String, TaskAssignmentPrincipal> _principalsByUser = const {};

  RightToolbarService? _toolbarService;
  TaskService? _taskServiceRef;
  String _lastAuthorityKey = '';

  TaskService get _tasks => context.read<TaskService>();

  @override
  void initState() {
    super.initState();
    _restoreSession();
    // Una tarea pedida desde afuera (notificación, #TASK en un chat, panel de
    // contexto) llega por el mecanismo pendiente del rail y gana sobre la
    // sesión restaurada. Se entrega una sola vez.
    final pendingTaskId =
        context.read<RightToolbarService?>()?.takePendingConversation(_tool);
    if (pendingTaskId != null) {
      _openTaskId = pendingTaskId;
      _composerVisible = false;
    }
    unawaited(_loadComposerSources());
    if (_composerVisible) {
      // La superficie es un overlay: se reabre después del primer frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openComposerFromBar();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cacheados para poder guardar desde dispose(), donde el context no sirve.
    _toolbarService = context.read<RightToolbarService?>();
    _taskServiceRef = context.read<TaskService?>();
    _lastAuthorityKey = _taskServiceRef?.authorityScope?.toString() ?? '';
  }

  @override
  void dispose() {
    _saveSession();
    _listScroll.dispose();
    super.dispose();
  }

  // ── Sesión de vista ──────────────────────────────────────────────────────

  String get _authorityKey =>
      _taskServiceRef?.authorityScope?.toString() ??
      context.read<TaskService>().authorityScope?.toString() ??
      '';

  void _restoreSession() {
    final toolbar = context.read<RightToolbarService?>();
    if (toolbar == null) return;
    final session = toolbar.panelSession<QuickTaskPanelSession>(_tool);
    if (session == null) return;
    if (session.authorityScopeKey != _authorityKey) {
      toolbar.clearPanelSession(_tool);
      return;
    }
    _scope = session.scope;
    _collapsedSections
      ..clear()
      ..addAll(session.collapsedSections);
    _openTaskId = session.openTaskId;
    _composerVisible = session.composerOpen;
    _draft
      ..kind = session.draft.kind
      ..title = session.draft.title
      ..description = session.draft.description
      ..priority = session.draft.priority
      ..dueDate = session.draft.dueDate
      ..assigneeId = session.draft.assigneeId
      ..contextKind = session.draft.contextKind
      ..contextTarget = session.draft.contextTarget
      ..jobId = session.draft.jobId
      ..jobScope = session.draft.jobScope
      ..selectedItemIds = {...session.draft.selectedItemIds}
      ..visibility = session.draft.visibility;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_listScroll.hasClients) return;
      final max = _listScroll.position.maxScrollExtent;
      _listScroll.jumpTo(session.scrollOffset.clamp(0.0, max));
    });
  }

  void _saveSession() {
    _toolbarService?.savePanelSession(
      _tool,
      QuickTaskPanelSession(
        authorityScopeKey: _lastAuthorityKey,
        scope: _scope,
        collapsedSections: {..._collapsedSections},
        openTaskId: _openTaskId,
        composerOpen: _composerVisible,
        draft: _draft,
        scrollOffset: _listScroll.hasClients ? _listScroll.offset : 0,
      ),
    );
  }

  // ── Datos del compositor ─────────────────────────────────────────────────

  Future<void> _loadComposerSources() async {
    try {
      final directory = await _tasks.fetchAssignmentDirectory();
      if (!mounted) return;
      setState(() {
        _directory = directory;
        _principalsByUser = {
          for (final principal in directory)
            if (principal.userId != null) principal.userId!: principal,
        };
      });
    } catch (error, stackTrace) {
      debugPrint('Task tray assignment directory failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  // ── Acciones ─────────────────────────────────────────────────────────────

  bool get _isManager =>
      context.read<CurrentUserProfileService?>()?.profile?.canManageUsers ==
      true;

  /// Otro responsable ya cubre esos servicios: colaboración o traspaso son
  /// decisiones del operador. O-03 = Dialog de Material tematizado por el
  /// resolver (sin wrapper visual): salida segura primero y con foco,
  /// botones que dicen lo que hacen.
  Future<String?> _askOverlapDecision(TaskOverlapException overlap) {
    final theme = Theme.of(context);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Repartir servicios ya asignados?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Estos servicios ya están en una tarea activa:',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            for (final row in overlap.overlaps.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• ${row['title'] ?? 'Tarea'}'
                  '${_principalsByUser[row['assigned_to']]?.displayName != null ? ' — ${_principalsByUser[row['assigned_to']]!.displayName}' : ''}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Volver'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop('collaborate'),
            child: const Text('Colaborar (compartir)'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('transfer'),
            child: const Text('Traspasar aquí'),
          ),
        ],
      ),
    );
  }

  void _showError(Object error) {
    final message = switch (error) {
      TaskVersionConflictException _ =>
        'La tarea cambió mientras tanto; se recargó. Intenta de nuevo.',
      _ => 'No se pudo completar la acción: $error',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
    ));
  }

  Future<void> _runCommand(Future<TaskModel> Function() command) async {
    try {
      await command();
    } on TaskVersionConflictException {
      if (!mounted) return;
      unawaited(_tasks.fetchTasks());
      _showError(TaskVersionConflictException(''));
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  Future<void> _openThread(TaskModel task) async {
    try {
      final thread = await _tasks.openThread(task.id!);
      if (!mounted) return;
      context.read<RightToolbarService>().openConversation(
            tool: ToolbarTool.messages,
            conversationId: thread.conversationId,
          );
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  // ── Compositor en host canónico O-02/O-05 ───────────────────────────────

  final GlobalKey _newTaskButtonKey = GlobalKey();

  void _openComposerFromBar() {
    final anchorContext = _newTaskButtonKey.currentContext ?? context;
    _composerVisible = true;
    showVbSurface<void>(
      anchorContext: anchorContext,
      title: 'Nueva tarea',
      minWidth: 340,
      maxWidth: 460,
      builder: (surfaceContext) => TaskComposerSurface(
        draft: _draft,
        directory: _directory,
        linkableJobs: _linkableJobs,
        taskService: _tasks,
        askOverlapDecision: _askOverlapDecision,
        onDraftChanged: _saveSession,
        onCreated: () {
          _draft.reset();
          _composerVisible = false;
          _saveSession();
          if (mounted) setState(() {});
        },
      ),
    ).whenComplete(() {
      // Cerrar sin crear conserva el borrador; solo se apaga la marca de
      // «reabrir al restaurar».
      _composerVisible = false;
      _saveSession();
    });
    _saveSession();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final taskService = context.watch<TaskService>();
    final theme = Theme.of(context);

    final openTask = _openTaskId == null
        ? null
        : taskService.tasks.where((task) => task.id == _openTaskId).firstOrNull;
    if (_openTaskId != null && openTask == null) {
      // La tarea abierta ya no existe/ya no es visible: volver a la lista.
      _openTaskId = null;
    }

    return Column(
      children: [
        if (openTask == null) _buildScopeBar(theme),
        Expanded(
          child: openTask != null
              ? _TaskDetailView(
                  key: ValueKey('task-detail-${openTask.id}'),
                  task: openTask,
                  links: taskService.jobItemsOf(openTask.id!),
                  jobHeader: taskService.jobHeaderOf(openTask),
                  principalsByUser: _principalsByUser,
                  isManager: _isManager,
                  currentUserId: taskService.currentUserId,
                  onBack: () => setState(() => _openTaskId = null),
                  onCommand: _runCommand,
                  onOpenThread: () => _openThread(openTask),
                  taskService: taskService,
                )
              : _buildList(theme, taskService),
        ),
        if (openTask == null) _buildBottomBar(theme),
      ],
    );
  }

  Widget _buildScopeBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: VbSegmented<TaskTrayScope>(
        groupLabel: 'Alcance de la bandeja',
        options: const [
          VbSegmentedOption(value: TaskTrayScope.inbox, label: 'Mi bandeja'),
          VbSegmentedOption(value: TaskTrayScope.team, label: 'Equipo'),
          VbSegmentedOption(value: TaskTrayScope.personal, label: 'Personales'),
        ],
        value: _scope,
        onChanged: (scope) => setState(() => _scope = scope),
      ),
    );
  }

  // Secciones por alcance. El orden es fijo y con intención: primero lo que
  // exige decisión (por aceptar, bloqueadas), después el calendario.
  List<_TraySection> _sectionsFor(TaskService service) {
    final uid = service.currentUserId;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    bool isOverdue(TaskModel task) =>
        task.dueDate != null && task.dueDate!.isBefore(today) && !task.isDone;
    bool isToday(TaskModel task) {
      final due = task.dueDate;
      if (due == null) return false;
      final day = DateTime(due.year, due.month, due.day);
      return day == today;
    }

    List<TaskModel> sorted(Iterable<TaskModel> source) {
      final list = source.toList();
      list.sort((a, b) {
        if (a.dueDate != null && b.dueDate != null) {
          return a.dueDate!.compareTo(b.dueDate!);
        }
        if (a.dueDate != null) return -1;
        if (b.dueDate != null) return 1;
        return b.createdAt.compareTo(a.createdAt);
      });
      return list;
    }

    switch (_scope) {
      case TaskTrayScope.inbox:
        final mine = service.tasks.where(
            (task) => task.assignedTo == uid && task.kind == TaskKind.task);
        final open = mine.where((task) => !task.isDone).toList();
        return [
          _TraySection('Por aceptar',
              sorted(open.where((task) => task.awaitsAcknowledgement)),
              emphasis: _SectionEmphasis.action),
          _TraySection(
              'Bloqueadas', sorted(open.where((task) => task.isBlocked)),
              emphasis: _SectionEmphasis.danger),
          _TraySection(
              'Vencidas',
              sorted(open.where((task) =>
                  !task.awaitsAcknowledgement &&
                  !task.isBlocked &&
                  isOverdue(task))),
              emphasis: _SectionEmphasis.danger),
          _TraySection(
              'Hoy',
              sorted(open.where((task) =>
                  !task.awaitsAcknowledgement &&
                  !task.isBlocked &&
                  isToday(task)))),
          _TraySection(
              'Próximas',
              sorted(open.where((task) =>
                  !task.awaitsAcknowledgement &&
                  !task.isBlocked &&
                  task.dueDate != null &&
                  !isOverdue(task) &&
                  !isToday(task) &&
                  !task.dueDate!.isBefore(tomorrow)))),
          _TraySection(
              'Sin fecha',
              sorted(open.where((task) =>
                  !task.awaitsAcknowledgement &&
                  !task.isBlocked &&
                  task.dueDate == null))),
          _TraySection('Completadas',
              sorted(mine.where((task) => task.isDone)).take(20).toList()),
        ];
      case TaskTrayScope.team:
        final teamAll = service.tasks
            .where((task) => task.visibility != TaskVisibility.private);
        final team =
            teamAll.where((task) => task.kind == TaskKind.task).toList();
        final notes =
            teamAll.where((task) => task.kind == TaskKind.note).toList();
        final open = team.where((task) => !task.isDone).toList();
        final unassigned =
            sorted(open.where((task) => task.assignedTo == null));
        final byAssignee = <String, List<TaskModel>>{};
        for (final task in open.where((task) => task.assignedTo != null)) {
          byAssignee.putIfAbsent(task.assignedTo!, () => []).add(task);
        }
        final assigneeSections = byAssignee.entries.map((entry) {
          final name = _principalsByUser[entry.key]?.displayName ??
              (entry.key == service.currentUserId ? 'Yo' : 'Sin nombre');
          return _TraySection(name, sorted(entry.value));
        }).toList()
          ..sort((a, b) => a.label.compareTo(b.label));
        return [
          _TraySection('Sin asignar', unassigned,
              emphasis: _SectionEmphasis.action),
          ...assigneeSections,
          _TraySection('Notas', sorted(notes.where((note) => !note.isDone))),
          _TraySection('Completadas',
              sorted(teamAll.where((task) => task.isDone)).take(20).toList()),
        ];
      case TaskTrayScope.personal:
        final personal = service.tasks.where((task) =>
            task.visibility == TaskVisibility.private && task.createdBy == uid);
        final open = personal.where((task) => !task.isDone).toList();
        return [
          _TraySection('Vencidas', sorted(open.where(isOverdue)),
              emphasis: _SectionEmphasis.danger),
          _TraySection('Hoy', sorted(open.where(isToday))),
          _TraySection('Pendientes',
              sorted(open.where((task) => !isOverdue(task) && !isToday(task)))),
          _TraySection('Completadas',
              sorted(personal.where((task) => task.isDone)).take(20).toList()),
        ];
    }
  }

  Widget _buildList(ThemeData theme, TaskService service) {
    final roles = VinabikeThemeRoles.maybeOf(context);
    final sections =
        _sectionsFor(service).where((section) => section.tasks.isNotEmpty);

    if (sections.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.task_alt,
                size: 44, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 8),
            Text(
              switch (_scope) {
                TaskTrayScope.inbox => 'Nada asignado a ti',
                TaskTrayScope.team => 'Sin tareas de equipo',
                TaskTrayScope.personal => 'Sin tareas personales',
              },
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final rows = <Widget>[];
    for (final section in sections) {
      final collapsed = _collapsedSections.contains(section.label);
      rows.add(_SectionHeaderRow(
        label: section.label,
        count: section.tasks.length,
        collapsed: collapsed,
        emphasis: section.emphasis,
        onTap: () => setState(() {
          collapsed
              ? _collapsedSections.remove(section.label)
              : _collapsedSections.add(section.label);
        }),
      ));
      if (!collapsed) {
        for (final task in section.tasks) {
          rows.add(_TaskRow(
            key: ValueKey('task-row-${task.id}'),
            task: task,
            links: service.jobItemsOf(task.id ?? ''),
            jobHeader: service.jobHeaderOf(task),
            showAssignee: _scope == TaskTrayScope.team,
            assigneeName: task.assignedTo == null
                ? null
                : _principalsByUser[task.assignedTo!]?.displayName,
            unseen: _isUnseen(service, task),
            roles: roles,
            onTap: () {
              setState(() => _openTaskId = task.id);
              if (task.id != null) {
                unawaited(service.markSeen(task));
              }
            },
          ));
        }
      }
    }

    return ListView(
      controller: _listScroll,
      padding: const EdgeInsets.only(bottom: 8),
      children: rows,
    );
  }

  bool _isUnseen(TaskService service, TaskModel task) {
    if (task.id == null || task.assignedTo != service.currentUserId) {
      return false;
    }
    final seen =
        (service.userStateOf(task.id!)?['seen_version'] as num?)?.toInt();
    return seen == null || seen < task.version;
  }

  Widget _buildBottomBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.tonalIcon(
          key: _newTaskButtonKey,
          onPressed: _openComposerFromBar,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Nueva tarea'),
        ),
      ),
    );
  }
}

// ── Compositor progresivo (contenido del host O-02/O-05) ──────────────────

class TaskComposerSurface extends StatefulWidget {
  const TaskComposerSurface({
    super.key,
    required this.draft,
    required this.directory,
    required this.linkableJobs,
    required this.taskService,
    required this.askOverlapDecision,
    required this.onDraftChanged,
    required this.onCreated,
  });

  final TaskComposerDraft draft;
  final List<TaskAssignmentPrincipal> directory;
  final List<TaskLinkableJob> linkableJobs;
  final TaskService taskService;
  final Future<String?> Function(TaskOverlapException) askOverlapDecision;
  final VoidCallback onDraftChanged;
  final VoidCallback onCreated;

  @override
  State<TaskComposerSurface> createState() => _TaskComposerSurfaceState();
}

class _TaskComposerSurfaceState extends State<TaskComposerSurface> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descriptionCtrl;
  late List<TaskLinkableJob> _workshopJobs;
  bool _workshopJobsLoading = false;
  Object? _workshopJobsError;
  List<TaskContextTarget> _contextTargets = const [];
  bool _contextTargetsLoading = false;
  Object? _contextTargetsError;
  List<TaskJobWorkItem> _jobItems = const [];
  bool _jobItemsLoading = false;
  Object? _jobItemsError;
  bool _saving = false;

  TaskComposerDraft get _draft => widget.draft;

  @override
  void initState() {
    super.initState();
    _workshopJobs = [...widget.linkableJobs];
    _titleCtrl = TextEditingController(text: _draft.title)
      ..addListener(() {
        _draft.title = _titleCtrl.text;
        widget.onDraftChanged();
        if (mounted) setState(() {});
      });
    _descriptionCtrl = TextEditingController(text: _draft.description)
      ..addListener(() {
        _draft.description = _descriptionCtrl.text;
        widget.onDraftChanged();
      });
    if (_draft.jobId != null) {
      _draft.contextKind = TaskContextKind.workshopJob;
    }
    if (_draft.contextKind == TaskContextKind.workshopJob) {
      if (_workshopJobs.isEmpty) unawaited(_loadWorkshopJobs());
      if (_draft.jobId != null) {
        unawaited(_loadJobItems(_draft.jobId!, preserveSelection: true));
      }
    } else if (_draft.contextKind != TaskContextKind.none &&
        _draft.contextKind != TaskContextKind.workshopJob) {
      unawaited(_loadContextTargets(
        _draft.contextKind,
        preserveSelection: true,
      ));
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  void _mutate(VoidCallback fn) {
    setState(fn);
    widget.onDraftChanged();
  }

  Future<void> _loadWorkshopJobs() async {
    if (_workshopJobsLoading) return;
    setState(() {
      _workshopJobsLoading = true;
      _workshopJobsError = null;
    });
    try {
      final jobs = await widget.taskService.fetchLinkableJobs();
      if (!mounted) return;
      setState(() {
        _workshopJobsLoading = false;
        if (_draft.contextKind == TaskContextKind.workshopJob) {
          _workshopJobs = jobs;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _workshopJobsLoading = false;
        if (_draft.contextKind == TaskContextKind.workshopJob) {
          _workshopJobsError = error;
        }
      });
    }
  }

  Future<void> _loadContextTargets(
    TaskContextKind kind, {
    bool preserveSelection = false,
  }) async {
    if (kind == TaskContextKind.none || kind == TaskContextKind.workshopJob) {
      return;
    }
    setState(() {
      _contextTargetsLoading = true;
      _contextTargetsError = null;
      _contextTargets = const [];
    });
    try {
      final targets = await widget.taskService.fetchLinkTargets(kind);
      if (!mounted || _draft.contextKind != kind) return;
      _mutate(() {
        _contextTargets = targets;
        _contextTargetsLoading = false;
        if (preserveSelection && _draft.contextTarget != null) {
          _draft.contextTarget = targets
              .where((target) => target.id == _draft.contextTarget!.id)
              .firstOrNull;
        } else {
          _draft.contextTarget = null;
        }
      });
    } catch (error) {
      if (!mounted || _draft.contextKind != kind) return;
      setState(() {
        _contextTargetsLoading = false;
        _contextTargetsError = error;
      });
    }
  }

  void _selectContextKind(TaskContextKind kind) {
    _mutate(() {
      _draft.contextKind = kind;
      _draft.contextTarget = null;
      _draft.jobId = null;
      _draft.jobScope = TaskJobScope.wholeJob;
      _draft.selectedItemIds = {};
      _jobItems = const [];
      _jobItemsError = null;
      _contextTargets = const [];
      _contextTargetsError = null;
      if (kind == TaskContextKind.workshopJob) {
        _draft.visibility = TaskVisibility.team;
      }
    });
    if (kind == TaskContextKind.workshopJob && _workshopJobs.isEmpty) {
      unawaited(_loadWorkshopJobs());
    } else if (kind != TaskContextKind.none) {
      unawaited(_loadContextTargets(kind));
    }
  }

  Future<void> _loadJobItems(String jobId,
      {bool preserveSelection = false}) async {
    setState(() {
      _jobItemsLoading = true;
      _jobItemsError = null;
      _jobItems = const [];
    });
    try {
      final items = await widget.taskService.fetchJobWorkItems(jobId);
      if (!mounted || _draft.jobId != jobId) return;
      _mutate(() {
        _jobItems = items;
        _jobItemsLoading = false;
        final ids = items.map((item) => item.id).toSet();
        if (_draft.jobScope == TaskJobScope.wholeJob) {
          _draft.selectedItemIds = ids;
        } else if (preserveSelection && _draft.selectedItemIds.isNotEmpty) {
          _draft.selectedItemIds =
              _draft.selectedItemIds.where(ids.contains).toSet();
        } else {
          _draft.selectedItemIds = {};
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _jobItemsLoading = false;
          _jobItemsError = error;
        });
      }
    }
  }

  bool get _workScopeIsValid {
    if (_draft.contextKind != TaskContextKind.workshopJob) return true;
    if (_draft.jobId == null) return false;
    if (_draft.kind == TaskKind.note) return true;
    if (_jobItemsLoading || _jobItemsError != null) return false;
    if (_jobItems.isEmpty || _draft.jobScope == TaskJobScope.wholeJob) {
      return true;
    }
    return _draft.selectedItemIds.isNotEmpty;
  }

  bool get _contextIsValid => switch (_draft.contextKind) {
        TaskContextKind.none => true,
        TaskContextKind.workshopJob => _draft.jobId != null,
        _ => _draft.contextTarget != null &&
            !_contextTargetsLoading &&
            _contextTargetsError == null,
      };

  Future<void> _create({String? overlapDecision}) async {
    final title = _draft.title.trim();
    if (title.isEmpty || _saving || !_contextIsValid || !_workScopeIsValid) {
      return;
    }
    setState(() => _saving = true);
    final personal = _draft.visibility == TaskVisibility.private;
    try {
      final isNote = _draft.kind == TaskKind.note;
      await widget.taskService.createTrayTask(
        title: title,
        description: _draft.description.trim().isEmpty
            ? null
            : _draft.description.trim(),
        kind: _draft.kind,
        visibility: _draft.visibility,
        priority: _draft.priority,
        dueDate: _draft.dueDate,
        assignedTo: personal || isNote ? null : _draft.assigneeId,
        linkedJobId: _draft.contextKind == TaskContextKind.workshopJob
            ? _draft.jobId
            : null,
        jobItemIds: isNote ||
                _draft.contextKind != TaskContextKind.workshopJob ||
                _draft.jobId == null
            ? null
            : (_draft.jobScope == TaskJobScope.wholeJob
                ? _jobItems.map((item) => item.id).toList()
                : _draft.selectedItemIds.toList()),
        linkedCustomerId: _draft.contextKind == TaskContextKind.customer
            ? _draft.contextTarget?.id
            : null,
        linkedSupplierId: _draft.contextKind == TaskContextKind.supplier
            ? _draft.contextTarget?.id
            : null,
        linkedSalesInvoiceId: _draft.contextKind == TaskContextKind.salesInvoice
            ? _draft.contextTarget?.id
            : null,
        linkedPurchaseInvoiceId:
            _draft.contextKind == TaskContextKind.purchaseInvoice
                ? _draft.contextTarget?.id
                : null,
        overlapDecision: overlapDecision,
      );
      if (!mounted) return;
      widget.onCreated();
      Navigator.of(context).pop();
    } on TaskOverlapException catch (overlap) {
      if (!mounted) return;
      setState(() => _saving = false);
      final decision = await widget.askOverlapDecision(overlap);
      if (decision != null) {
        await _create(overlapDecision: decision);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo crear la tarea: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final assignables = widget.directory
        .where((principal) => principal.isAssignable)
        .toList(growable: false);
    final nonAssignables = widget.directory
        .where((principal) => !principal.isAssignable)
        .toList(growable: false);
    final personal = _draft.visibility == TaskVisibility.private;
    final isNote = _draft.kind == TaskKind.note;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tarea = trabajo con responsable y ciclo; Nota = captura general
          // sin asignación ni ejecución, con sus asociaciones útiles.
          VbSegmented<TaskKind>(
            groupLabel: 'Tipo',
            options: const [
              VbSegmentedOption(value: TaskKind.task, label: 'Tarea'),
              VbSegmentedOption(value: TaskKind.note, label: 'Nota'),
            ],
            value: _draft.kind,
            onChanged: (kind) => _mutate(() {
              _draft.kind = kind;
              if (kind == TaskKind.note) {
                _draft.assigneeId = null;
                _draft.jobScope = TaskJobScope.wholeJob;
                _draft.selectedItemIds = {};
              } else if (_draft.jobId != null && _jobItems.isNotEmpty) {
                _draft.selectedItemIds =
                    _jobItems.map((item) => item.id).toSet();
              }
            }),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _titleCtrl,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              hintText: isNote ? 'Título de la nota…' : 'Título de la tarea…',
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descriptionCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: isNote
                  ? 'Contenido (opcional)…'
                  : 'Instrucciones (opcional)…',
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: VbShortSelect<TaskPriority>(
                  value: _draft.priority,
                  label: 'Prioridad',
                  sheetTitle: 'Prioridad',
                  options: const [
                    VbShortSelectOption(value: TaskPriority.low, label: 'Baja'),
                    VbShortSelectOption(
                        value: TaskPriority.normal, label: 'Normal'),
                    VbShortSelectOption(
                        value: TaskPriority.high, label: 'Alta'),
                    VbShortSelectOption(
                        value: TaskPriority.urgent, label: 'Urgente'),
                  ],
                  onChanged: (value) => _mutate(() => _draft.priority = value),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _buildDueDateField(theme)),
            ],
          ),
          const SizedBox(height: 10),
          // Visibilidad con su control canónico (S-05): Equipo o Personal.
          VbShortSelect<TaskVisibility>(
            value: personal ? TaskVisibility.private : TaskVisibility.team,
            label: 'Visibilidad',
            sheetTitle: 'Visibilidad',
            options: const [
              VbShortSelectOption(value: TaskVisibility.team, label: 'Equipo'),
              VbShortSelectOption(
                  value: TaskVisibility.private, label: 'Personal (solo yo)'),
            ],
            onChanged: (_draft.assigneeId != null ||
                    _draft.contextKind == TaskContextKind.workshopJob)
                ? null
                : (value) => _mutate(() => _draft.visibility = value),
          ),
          if (_draft.assigneeId != null ||
              _draft.contextKind == TaskContextKind.workshopJob)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _draft.contextKind == TaskContextKind.workshopJob
                    ? 'Las tareas vinculadas al Taller son del equipo.'
                    : 'Una tarea asignada es del equipo.',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          if (!personal && !isNote) ...[
            const SizedBox(height: 10),
            VbSearchableSelect<String>(
              value: _draft.assigneeId,
              label: 'Trabajador responsable',
              sheetTitle: 'Asignar a',
              placeholder: 'Sin asignar',
              allowClear: true,
              options: [
                for (final principal in assignables)
                  VbSearchableSelectOption(
                    value: principal.userId!,
                    label: principal.displayName,
                    context: principal.assignmentContextLabel,
                  ),
              ],
              onChanged: (value) => _mutate(() => _draft.assigneeId = value),
            ),
            // Los sin cuenta no se esconden: existen, pero no pueden recibir
            // trabajo hasta que se les invite.
            if (nonAssignables.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  nonAssignables.length == 1
                      ? '${nonAssignables.first.displayName} no tiene '
                          'acceso — se invita desde Usuarios'
                      : '${nonAssignables.length} trabajadores sin acceso '
                          '— se invitan desde Usuarios',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
          ],
          const SizedBox(height: 10),
          VbShortSelect<TaskContextKind>(
            value: _draft.contextKind,
            label: 'Vincular a (opcional)',
            sheetTitle: 'Vincular tarea o nota',
            options: const [
              VbShortSelectOption(
                value: TaskContextKind.none,
                label: 'Sin vínculo',
              ),
              VbShortSelectOption(
                value: TaskContextKind.workshopJob,
                label: 'Trabajo del taller',
              ),
              VbShortSelectOption(
                value: TaskContextKind.customer,
                label: 'Cliente',
              ),
              VbShortSelectOption(
                value: TaskContextKind.supplier,
                label: 'Proveedor',
              ),
              VbShortSelectOption(
                value: TaskContextKind.salesInvoice,
                label: 'Venta / factura',
              ),
              VbShortSelectOption(
                value: TaskContextKind.purchaseInvoice,
                label: 'Compra / documento',
              ),
            ],
            onChanged: _selectContextKind,
          ),
          if (_draft.contextKind != TaskContextKind.none) ...[
            const SizedBox(height: 8),
            if (_draft.contextKind == TaskContextKind.workshopJob)
              _buildWorkshopPicker(theme, isNote: isNote)
            else
              _buildEntityContextPicker(theme),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cerrar'),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FilledButton.icon(
                  onPressed: _saving ||
                          _draft.title.trim().isEmpty ||
                          !_contextIsValid ||
                          !_workScopeIsValid
                      ? null
                      : () => unawaited(_create()),
                  icon: _saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          isNote
                              ? Icons.sticky_note_2_outlined
                              : Icons.add_task,
                          size: 18),
                  label: Text(_saving
                      ? 'Guardando…'
                      : isNote
                          ? 'Guardar nota'
                          : 'Crear tarea'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDueDateField(ThemeData theme) {
    final label = _draft.dueDate == null
        ? 'Sin fecha'
        : DateFormat('dd/MM/yyyy').format(_draft.dueDate!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Plazo',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 5),
        Semantics(
          button: true,
          label: 'Plazo, $label',
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              final picked = await showVbMarkedDatePicker(
                context: context,
                initialDate: _draft.dueDate ??
                    DateTime.now().add(const Duration(days: 1)),
                firstDate: DateTime.now().subtract(const Duration(days: 1)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                markers: const {},
              );
              if (picked != null && mounted) {
                _mutate(() => _draft.dueDate = picked);
              }
            },
            child: Container(
              height: VbShortSelect.fieldHeight,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outline),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.event_outlined,
                      size: 15, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall),
                  ),
                  if (_draft.dueDate != null)
                    InkWell(
                      onTap: () => _mutate(() => _draft.dueDate = null),
                      child: Icon(Icons.close,
                          size: 14, color: theme.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWorkshopPicker(ThemeData theme, {required bool isNote}) {
    if (_workshopJobsLoading) {
      return _loadingRow(theme, 'Cargando trabajos activos…');
    }
    if (_workshopJobsError != null) {
      return _loadErrorRow(
        theme,
        'No se pudieron cargar los trabajos.',
        _loadWorkshopJobs,
      );
    }
    if (_workshopJobs.isEmpty) {
      return Text(
        'No hay trabajos activos disponibles para vincular.',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VbSearchableSelect<String>(
          value: _draft.jobId,
          label: '1 · Trabajo',
          semanticLabel: '1 · Trabajo',
          sheetTitle: 'Elige un trabajo del taller',
          placeholder: 'Selecciona un trabajo',
          helperText: _draft.jobId == null
              ? 'Después podrás vincular el trabajo completo o elegir servicios.'
              : null,
          allowClear: true,
          clearLabel: 'Sin trabajo seleccionado',
          options: [
            for (final job in _workshopJobs)
              VbSearchableSelectOption(
                value: job.id,
                label:
                    '#${job.jobNumber}${job.customerName != null ? ' · ${job.customerName}' : ''}',
                searchText:
                    '${job.jobNumber} ${job.customerName ?? ''} ${job.clientRequest ?? ''}',
              ),
          ],
          onChanged: (value) {
            _mutate(() {
              _draft.jobId = value;
              _draft.jobScope = TaskJobScope.wholeJob;
              _jobItems = const [];
              _jobItemsError = null;
              _draft.selectedItemIds = {};
            });
            if (value != null) unawaited(_loadJobItems(value));
          },
        ),
        if (_draft.jobId != null && !isNote) _buildServicePicker(theme),
        if (_draft.jobId != null && isNote)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              'La nota quedará vinculada al trabajo completo.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  Widget _buildEntityContextPicker(ThemeData theme) {
    final kind = _draft.contextKind;
    if (_contextTargetsLoading) {
      return _loadingRow(theme, 'Cargando ${_contextPlural(kind)}…');
    }
    if (_contextTargetsError != null) {
      return _loadErrorRow(
        theme,
        'No se pudieron cargar ${_contextPlural(kind)}.',
        () => _loadContextTargets(kind, preserveSelection: true),
      );
    }
    if (_contextTargets.isEmpty) {
      return Text(
        'No hay ${_contextPlural(kind)} disponibles para vincular.',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }
    return VbSearchableSelect<String>(
      value: _draft.contextTarget?.id,
      label: _contextSingular(kind),
      semanticLabel: _contextSingular(kind),
      sheetTitle: 'Seleccionar ${_contextSingular(kind).toLowerCase()}',
      placeholder: 'Selecciona ${_contextSingular(kind).toLowerCase()}',
      allowClear: true,
      clearLabel: 'Sin selección',
      options: [
        for (final target in _contextTargets)
          VbSearchableSelectOption(
            value: target.id,
            label: target.label,
            context: target.context,
            searchText: target.searchText,
          ),
      ],
      onChanged: (value) => _mutate(() {
        _draft.contextTarget = value == null
            ? null
            : _contextTargets.where((target) => target.id == value).firstOrNull;
      }),
    );
  }

  Widget _loadingRow(ThemeData theme, String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      );

  Widget _loadErrorRow(
    ThemeData theme,
    String label,
    Future<void> Function() retry,
  ) =>
      Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
          TextButton(
            onPressed: () => unawaited(retry()),
            child: const Text('Reintentar'),
          ),
        ],
      );

  String _contextSingular(TaskContextKind kind) => switch (kind) {
        TaskContextKind.customer => 'Cliente',
        TaskContextKind.supplier => 'Proveedor',
        TaskContextKind.salesInvoice => 'Venta / factura',
        TaskContextKind.purchaseInvoice => 'Compra / documento',
        TaskContextKind.workshopJob => 'Trabajo',
        TaskContextKind.none => 'Contexto',
      };

  String _contextPlural(TaskContextKind kind) => switch (kind) {
        TaskContextKind.customer => 'clientes',
        TaskContextKind.supplier => 'proveedores',
        TaskContextKind.salesInvoice => 'ventas',
        TaskContextKind.purchaseInvoice => 'compras',
        TaskContextKind.workshopJob => 'trabajos',
        TaskContextKind.none => 'registros',
      };

  /// Todos o algunos servicios reales del trabajo, agrupados por bicicleta.
  Widget _buildServicePicker(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '2 · Alcance de la tarea',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 5),
          if (_jobItemsLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text('Cargando servicios del trabajo…',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            )
          else if (_jobItemsError != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    'No se pudieron cargar los servicios de este trabajo.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
                TextButton(
                  onPressed: () => unawaited(_loadJobItems(_draft.jobId!)),
                  child: const Text('Reintentar'),
                ),
              ],
            )
          else if (_jobItems.isEmpty)
            Text(
              'Este trabajo aún no tiene servicios cargados. La tarea quedará '
              'vinculada al trabajo completo.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          else ...[
            VbSegmented<TaskJobScope>(
              groupLabel: 'Alcance de la tarea en el trabajo',
              options: const [
                VbSegmentedOption(
                  value: TaskJobScope.wholeJob,
                  label: 'Trabajo completo',
                ),
                VbSegmentedOption(
                  value: TaskJobScope.selectedServices,
                  label: 'Por servicios',
                ),
              ],
              value: _draft.jobScope,
              onChanged: (scope) => _mutate(() {
                _draft.jobScope = scope;
                _draft.selectedItemIds = scope == TaskJobScope.wholeJob
                    ? _jobItems.map((item) => item.id).toSet()
                    : <String>{};
              }),
            ),
            const SizedBox(height: 5),
            if (_draft.jobScope == TaskJobScope.wholeJob)
              Text(
                _jobItems.length == 1
                    ? 'Se incluirá el único servicio de este trabajo.'
                    : 'Se incluirán los ${_jobItems.length} servicios de este trabajo.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            else ...[
              Text(
                'Elige uno o más servicios:',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              for (final entry in _jobItemsByBike.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 2),
                  child: Text(
                    entry.key,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (final item in entry.value)
                  InkWell(
                    onTap: () => _toggleJobItem(item.id),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _draft.selectedItemIds.contains(item.id),
                          onChanged: (_) => _toggleJobItem(item.id),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (item.instructions != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  item.instructions!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
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
              if (_draft.selectedItemIds.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Selecciona al menos un servicio.',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  Map<String, List<TaskJobWorkItem>> get _jobItemsByBike {
    final result = <String, List<TaskJobWorkItem>>{};
    for (final item in _jobItems) {
      result.putIfAbsent(item.bikeLabel ?? 'Sin bicicleta', () => []).add(item);
    }
    return result;
  }

  void _toggleJobItem(String itemId) {
    _mutate(() {
      if (!_draft.selectedItemIds.remove(itemId)) {
        _draft.selectedItemIds.add(itemId);
      }
    });
  }
}

// ── Secciones y filas ──────────────────────────────────────────────────────

enum _SectionEmphasis { normal, action, danger }

class _TraySection {
  const _TraySection(this.label, this.tasks,
      {this.emphasis = _SectionEmphasis.normal});
  final String label;
  final List<TaskModel> tasks;
  final _SectionEmphasis emphasis;
}

class _SectionHeaderRow extends StatelessWidget {
  const _SectionHeaderRow({
    required this.label,
    required this.count,
    required this.collapsed,
    required this.emphasis,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool collapsed;
  final _SectionEmphasis emphasis;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    final color = switch (emphasis) {
      _SectionEmphasis.danger =>
        roles?.danger.accent ?? theme.colorScheme.error,
      _SectionEmphasis.action => theme.colorScheme.primary,
      _SectionEmphasis.normal => theme.colorScheme.onSurfaceVariant,
    };

    return InkWell(
      onTap: onTap,
      child: Semantics(
        header: true,
        label: '$label, $count tareas, '
            '${collapsed ? 'contraída' : 'expandida'}',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 8, 4),
          child: Row(
            children: [
              Text(
                label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: color,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$count',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: color,
                    )),
              ),
              const SizedBox(width: 6),
              Expanded(
                child:
                    Divider(height: 1, color: theme.colorScheme.outlineVariant),
              ),
              Icon(
                collapsed ? Icons.expand_more : Icons.expand_less,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    super.key,
    required this.task,
    required this.links,
    required this.jobHeader,
    required this.showAssignee,
    required this.assigneeName,
    required this.unseen,
    required this.roles,
    required this.onTap,
  });

  final TaskModel task;
  final List<SmartTaskJobItem> links;
  final TaskLinkableJob? jobHeader;
  final bool showAssignee;
  final String? assigneeName;
  final bool unseen;
  final VinabikeThemeRoles? roles;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOverdue = task.dueDate != null &&
        task.dueDate!.isBefore(DateTime.now()) &&
        !task.isDone;
    final liveLinks = links.where((link) => !link.isInvalidated).toList();
    final jobNumber = liveLinks.isNotEmpty
        ? liveLinks.first.jobNumber
        : links.isNotEmpty
            ? links.first.jobNumber
            : jobHeader?.jobNumber;
    final linkedContext = task.linkedContextTarget;

    final isNote = task.kind == TaskKind.note;
    return Opacity(
      opacity: task.isDone ? 0.55 : 1,
      child: InkWell(
        onTap: onTap,
        child: Semantics(
          button: true,
          label: isNote
              ? 'Nota ${task.title}${task.isDone ? ', archivada' : ''}'
              : 'Tarea ${task.title}${task.isBlocked ? ', bloqueada' : ''}'
                  '${unseen ? ', nueva' : ''}',
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Icon(
                    isNote
                        ? (task.isDone
                            ? Icons.archive_outlined
                            : Icons.sticky_note_2_outlined)
                        : task.isDone
                            ? Icons.check_circle
                            : task.isBlocked
                                ? Icons.block
                                : task.status == TaskStatus.inProgress
                                    ? Icons.play_circle_outline
                                    : Icons.radio_button_unchecked,
                    size: 17,
                    color: isNote
                        ? theme.colorScheme.onSurfaceVariant
                        : task.isDone
                            ? (roles?.success.accent ??
                                theme.colorScheme.tertiary)
                            : task.isBlocked
                                ? (roles?.danger.accent ??
                                    theme.colorScheme.error)
                                : task.status == TaskStatus.inProgress
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight:
                              unseen ? FontWeight.w700 : FontWeight.w500,
                          decoration:
                              task.isDone ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (isNote && task.isDone)
                            const VbStatusBadge(
                                label: 'Archivada',
                                tone: VbStatusTone.neutral,
                                dense: true),
                          if (!isNote &&
                              task.awaitsAcknowledgement &&
                              !task.isDone)
                            const VbStatusBadge(
                                label: 'Por aceptar',
                                tone: VbStatusTone.info,
                                dense: true),
                          if (task.isBlocked)
                            const VbStatusBadge(
                                label: 'Bloqueada',
                                tone: VbStatusTone.danger,
                                dense: true),
                          if (task.dueDate != null)
                            Text(
                              DateFormat('dd/MM').format(task.dueDate!),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isOverdue
                                    ? (roles?.danger.accent ??
                                        theme.colorScheme.error)
                                    : theme.colorScheme.onSurfaceVariant,
                                fontWeight: isOverdue ? FontWeight.w700 : null,
                              ),
                            ),
                          if (jobNumber != null)
                            Text(
                              '#$jobNumber'
                              '${liveLinks.isNotEmpty ? ' · ${liveLinks.length} serv.' : ''}',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: theme.colorScheme.primary),
                            ),
                          if (linkedContext != null)
                            Text(
                              '${_taskContextTypeLabel(linkedContext.kind)} · ${linkedContext.label}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: theme.colorScheme.primary),
                            ),
                          if (showAssignee && assigneeName != null)
                            Text(
                              assigneeName!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Detalle in-pane ────────────────────────────────────────────────────────

class _TaskDetailView extends StatefulWidget {
  const _TaskDetailView({
    super.key,
    required this.task,
    required this.links,
    required this.jobHeader,
    required this.principalsByUser,
    required this.isManager,
    required this.currentUserId,
    required this.onBack,
    required this.onCommand,
    required this.onOpenThread,
    required this.taskService,
  });

  final TaskModel task;
  final List<SmartTaskJobItem> links;
  final TaskLinkableJob? jobHeader;
  final Map<String, TaskAssignmentPrincipal> principalsByUser;
  final bool isManager;
  final String? currentUserId;
  final VoidCallback onBack;
  final Future<void> Function(Future<TaskModel> Function()) onCommand;
  final VoidCallback onOpenThread;
  final TaskService taskService;

  @override
  State<_TaskDetailView> createState() => _TaskDetailViewState();
}

class _TaskDetailViewState extends State<_TaskDetailView> {
  late Future<List<SmartTaskEvent>> _events;

  @override
  void initState() {
    super.initState();
    _events = widget.taskService.fetchEvents(widget.task.id!);
  }

  @override
  void didUpdateWidget(covariant _TaskDetailView old) {
    super.didUpdateWidget(old);
    if (old.task.version != widget.task.version) {
      _events = widget.taskService.fetchEvents(widget.task.id!);
    }
  }

  bool get _isAssignee => widget.task.assignedTo == widget.currentUserId;
  bool get _isCreator => widget.task.createdBy == widget.currentUserId;
  bool get _canSupervise => _isCreator || widget.isManager;
  bool get _isNote => widget.task.kind == TaskKind.note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    final task = widget.task;
    final service = widget.taskService;

    final creatorName = widget.principalsByUser[task.createdBy]?.displayName;
    final assigneeName = task.assignedTo == null
        ? null
        : widget.principalsByUser[task.assignedTo!]?.displayName ??
            task.assigneeName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Volver',
                icon: const Icon(Icons.arrow_back, size: 18),
                onPressed: widget.onBack,
              ),
              Expanded(
                child: Text(_isNote ? 'Nota' : 'Tarea',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              // Una nota no conversa: es captura, no trabajo con responsable.
              if (!_isNote)
                IconButton(
                  tooltip: 'Conversar',
                  icon: const Icon(Icons.forum_outlined, size: 18),
                  onPressed: (_isAssignee || _canSupervise)
                      ? widget.onOpenThread
                      : null,
                ),
            ],
          ),
        ),
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            children: [
              Text(task.title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (_isNote)
                    VbStatusBadge(
                      label: task.isDone ? 'Archivada' : 'Nota',
                      tone: VbStatusTone.neutral,
                    )
                  else
                    VbStatusBadge(
                      label: switch (task.status) {
                        TaskStatus.pending => task.awaitsAcknowledgement
                            ? 'Por aceptar'
                            : 'Pendiente',
                        TaskStatus.inProgress => 'En curso',
                        TaskStatus.blocked => 'Bloqueada',
                        TaskStatus.completed => 'Completada',
                        TaskStatus.cancelled => 'Cancelada',
                      },
                      tone: switch (task.status) {
                        TaskStatus.pending => VbStatusTone.info,
                        TaskStatus.inProgress => VbStatusTone.info,
                        TaskStatus.blocked => VbStatusTone.danger,
                        TaskStatus.completed => VbStatusTone.success,
                        TaskStatus.cancelled => VbStatusTone.neutral,
                      },
                    ),
                  if (task.priority != TaskPriority.normal)
                    VbStatusBadge(
                      label: switch (task.priority) {
                        TaskPriority.low => 'Baja',
                        TaskPriority.normal => 'Normal',
                        TaskPriority.high => 'Alta',
                        TaskPriority.urgent => 'Urgente',
                      },
                      tone: task.priority == TaskPriority.urgent
                          ? VbStatusTone.danger
                          : VbStatusTone.warning,
                    ),
                  if (task.dueDate != null)
                    VbStatusBadge(
                      label:
                          'Plazo ${DateFormat('dd/MM').format(task.dueDate!)}',
                      tone: VbStatusTone.neutral,
                    ),
                  if (task.visibility == TaskVisibility.private)
                    const VbStatusBadge(
                        label: 'Personal', tone: VbStatusTone.neutral),
                ],
              ),
              if (task.isBlocked && task.blockedReason != null) ...[
                const SizedBox(height: 8),
                Text('Motivo: ${task.blockedReason}',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            roles?.danger.accent ?? theme.colorScheme.error)),
              ],
              if ((task.description ?? '').isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(task.description!, style: theme.textTheme.bodySmall),
              ],
              const SizedBox(height: 10),
              Text(
                [
                  if (creatorName != null) 'Creada por $creatorName',
                  if (assigneeName != null) 'para $assigneeName',
                ].join(' '),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (widget.links.isNotEmpty ||
                  (widget.jobHeader != null &&
                      widget.task.linkedJobId != null)) ...[
                const SizedBox(height: 14),
                _JobContextCard(
                  links: widget.links,
                  jobHeader: widget.jobHeader,
                  // Contrato de retorno del routed detail: push, y el
                  // detalle cierra con ReturnNavigation.close.
                  onOpenJob: () => openWorkshopJobFromTray(
                      context,
                      widget.links.isNotEmpty
                          ? widget.links.first.jobId
                          : widget.task.linkedJobId!),
                ),
              ],
              if (task.linkedContextTarget case final linkedContext?) ...[
                const SizedBox(height: 14),
                _TaskContextCard(
                  target: linkedContext,
                  onOpen: () => openTaskContextFromTray(context, linkedContext),
                ),
              ],
              const SizedBox(height: 14),
              _buildActions(theme),
              const SizedBox(height: 16),
              Text('ACTIVIDAD',
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
              const SizedBox(height: 6),
              FutureBuilder<List<SmartTaskEvent>>(
                future: _events,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }
                  final events = snapshot.data!;
                  if (events.isEmpty) {
                    return Text('Sin actividad registrada',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant));
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final event in events.take(12))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Text(
                            '${DateFormat('dd/MM HH:mm').format(event.createdAt.toLocal())}'
                            ' · ${_eventLabel(event)}'
                            '${event.actorUserId != null ? ' — ${widget.principalsByUser[event.actorUserId!]?.displayName ?? ''}' : ''}',
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                    ],
                  );
                },
              ),
              // Cancelar vive al final, lejos de las acciones frecuentes.
              if (_canSupervise && !task.isDone && !_isNote) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor:
                          roles?.danger.accent ?? theme.colorScheme.error,
                    ),
                    onPressed: () => widget.onCommand(() => service
                        .cancelTask(task.id!, expectedVersion: task.version)),
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('Cancelar tarea'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _eventLabel(SmartTaskEvent event) {
    final base = switch (event.eventType) {
      'created' => 'Creada',
      'assigned' => 'Asignada',
      'unassigned' => 'Sin responsable',
      'acknowledged' => 'Aceptada',
      'returned' => 'Devuelta',
      'started' => 'Iniciada',
      'blocked' => 'Bloqueada',
      'unblocked' => 'Desbloqueada',
      'completed' => 'Completada',
      'reopened' => 'Reabierta',
      'cancelled' => 'Cancelada',
      'details_updated' => 'Editada',
      'visibility_changed' => 'Visibilidad cambiada',
      'job_items_linked' => 'Servicios vinculados',
      'job_items_unlinked' => 'Servicios desvinculados',
      'conversation_linked' => 'Hilo abierto',
      _ => event.eventType,
    };
    final reason = event.payload['reason']?.toString();
    return reason == null ? base : '$base · $reason';
  }

  Widget _buildActions(ThemeData theme) {
    final task = widget.task;
    final service = widget.taskService;
    final actions = <Widget>[];

    if (_isNote) {
      if (!_canSupervise) return const SizedBox.shrink();
      return Wrap(spacing: 8, runSpacing: 8, children: [
        if (!task.isDone)
          OutlinedButton.icon(
            onPressed: () => widget.onCommand(() =>
                service.cancelTask(task.id!, expectedVersion: task.version)),
            icon: const Icon(Icons.archive_outlined, size: 16),
            label: const Text('Archivar nota'),
          )
        else
          FilledButton.tonalIcon(
            onPressed: () => widget.onCommand(() =>
                service.reopenTask(task.id!, expectedVersion: task.version)),
            icon: const Icon(Icons.unarchive_outlined, size: 16),
            label: const Text('Restaurar nota'),
          ),
      ]);
    }

    void action(String label, IconData icon, Future<TaskModel> Function() run,
        {bool filled = false}) {
      actions.add(filled
          ? FilledButton.icon(
              onPressed: () => widget.onCommand(run),
              icon: Icon(icon, size: 16),
              label: Text(label),
            )
          : OutlinedButton.icon(
              onPressed: () => widget.onCommand(run),
              icon: Icon(icon, size: 16),
              label: Text(label),
            ));
    }

    // Los motivos se capturan en el host contextual canónico (O-02 anclado
    // al botón que lo pide; O-05 en compacto).
    void reasonAction(String label, IconData icon, String hint,
        Future<TaskModel> Function(String reason) run) {
      actions.add(Builder(
        builder: (buttonContext) => OutlinedButton.icon(
          onPressed: () async {
            final reason = await showVbReasonPrompt(
              anchorContext: buttonContext,
              title: label,
              hint: hint,
              confirmLabel: label,
            );
            if (reason == null) return;
            await widget.onCommand(() => run(reason));
          },
          icon: Icon(icon, size: 16),
          label: Text(label),
        ),
      ));
    }

    if (_isAssignee && task.awaitsAcknowledgement) {
      action('Aceptar', Icons.check, () => service.acknowledgeTask(task.id!),
          filled: true);
      reasonAction('Devolver', Icons.undo, '¿Por qué la devuelves?',
          (reason) => service.returnTask(task.id!, reason));
    }
    if ((_isAssignee || widget.isManager) &&
        task.status == TaskStatus.pending &&
        !task.awaitsAcknowledgement) {
      action('Iniciar', Icons.play_arrow,
          () => service.startTask(task.id!, expectedVersion: task.version),
          filled: true);
    }
    if ((_isAssignee || _canSupervise) &&
        (task.status == TaskStatus.pending ||
            task.status == TaskStatus.inProgress)) {
      reasonAction(
          'Bloquear',
          Icons.block,
          '¿Qué la bloquea? (ej: falta repuesto)',
          (reason) => service.blockTask(task.id!, reason,
              expectedVersion: task.version));
      action('Completar', Icons.task_alt,
          () => service.completeTask(task.id!, expectedVersion: task.version),
          filled: task.status == TaskStatus.inProgress);
    }
    if ((_isAssignee || _canSupervise) && task.isBlocked) {
      action('Desbloquear', Icons.lock_open,
          () => service.unblockTask(task.id!, expectedVersion: task.version),
          filled: true);
      action('Completar', Icons.task_alt,
          () => service.completeTask(task.id!, expectedVersion: task.version));
    }
    if (_canSupervise && task.isDone) {
      action('Reabrir', Icons.refresh,
          () => service.reopenTask(task.id!, expectedVersion: task.version));
    }
    if (_canSupervise && !task.isDone) {
      // Elegir persona = S-06 en el host O-02/O-05, anclado a su botón.
      actions.add(Builder(
        builder: (buttonContext) => OutlinedButton.icon(
          onPressed: () => _pickAssignee(buttonContext),
          icon: const Icon(Icons.person_outline, size: 16),
          label: Text(task.assignedTo == null ? 'Asignar' : 'Reasignar'),
        ),
      ));
    }

    if (actions.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: actions);
  }

  Future<void> _pickAssignee(BuildContext anchorContext) async {
    final directory = await widget.taskService.fetchAssignmentDirectory();
    if (!mounted || !anchorContext.mounted) return;
    // El picker es el owner S-06 real (mismo menú O-02 / hoja O-05 del
    // campo). Los sin cuenta no son opciones: su afordancia «Invitar» vive en
    // el compositor y el directorio.
    final selected = await showVbSearchableOptionPicker<String>(
      anchorContext: anchorContext,
      title: 'Asignar a',
      options: [
        for (final principal in directory.where((p) => p.isAssignable))
          VbSearchableSelectOption(
            value: principal.userId!,
            label: principal.displayName,
            context: principal.assignmentContextLabel,
          ),
      ],
    );
    if (selected == null || !mounted) return;
    await widget.onCommand(() => widget.taskService.assignTask(
        widget.task.id!, selected,
        expectedVersion: widget.task.version));
  }
}

class _JobContextCard extends StatelessWidget {
  const _JobContextCard({
    required this.links,
    required this.jobHeader,
    required this.onOpenJob,
  });

  final List<SmartTaskJobItem> links;
  final TaskLinkableJob? jobHeader;
  final VoidCallback onOpenJob;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    final jobNumber =
        links.isNotEmpty ? links.first.jobNumber : jobHeader?.jobNumber;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('TRABAJO #${jobNumber ?? '—'}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    )),
              ),
              TextButton.icon(
                onPressed: onOpenJob,
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text('Abrir trabajo'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (links.isEmpty && jobHeader != null)
            Text(
              [
                if (jobHeader!.customerName != null) jobHeader!.customerName!,
                if ((jobHeader!.clientRequest ?? '').isNotEmpty)
                  jobHeader!.clientRequest!,
                'Trabajo completo (sin servicios elegidos)',
              ].join(' — '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          for (final link in links)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    link.isInvalidated ? Icons.link_off : Icons.build_outlined,
                    size: 13,
                    color: link.isInvalidated
                        ? (roles?.danger.accent ?? theme.colorScheme.error)
                        : theme.colorScheme.onSurfaceVariant,
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
                              color: theme.colorScheme.onSurfaceVariant,
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
                              color: roles?.danger.accent ??
                                  theme.colorScheme.error,
                            ),
                          ),
                        ] else if (link.contextChanged) ...[
                          const SizedBox(height: 2),
                          Text(
                            'El servicio o sus instrucciones cambiaron después de asignar la tarea. Abre el trabajo para revisar la versión actual.',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.tertiary,
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
      ),
    );
  }
}

class _TaskContextCard extends StatelessWidget {
  const _TaskContextCard({required this.target, required this.onOpen});

  final TaskContextTarget target;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeLabel = _taskContextTypeLabel(target.kind);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            _taskContextIcon(target.kind),
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  typeLabel.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  target.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new, size: 14),
            label: const Text('Abrir'),
          ),
        ],
      ),
    );
  }
}

String _taskContextTypeLabel(TaskContextKind kind) => switch (kind) {
      TaskContextKind.customer => 'Cliente',
      TaskContextKind.supplier => 'Proveedor',
      TaskContextKind.salesInvoice => 'Venta',
      TaskContextKind.purchaseInvoice => 'Compra',
      TaskContextKind.workshopJob => 'Trabajo',
      TaskContextKind.none => 'Sin vínculo',
    };

IconData _taskContextIcon(TaskContextKind kind) => switch (kind) {
      TaskContextKind.customer => Icons.person_outline,
      TaskContextKind.supplier => Icons.storefront_outlined,
      TaskContextKind.salesInvoice => Icons.receipt_long_outlined,
      TaskContextKind.purchaseInvoice => Icons.shopping_cart_outlined,
      TaskContextKind.workshopJob => Icons.build_outlined,
      TaskContextKind.none => Icons.link_off,
    };
