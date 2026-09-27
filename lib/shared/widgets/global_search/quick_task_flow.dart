import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../modules/tasks/models/task_assignment_principal.dart';
import '../../../modules/tasks/models/task_model.dart';
import '../../../modules/tasks/services/task_service.dart';
import '../../services/global_search/quick_task_draft.dart';
import '../../services/right_toolbar_service.dart';
import '../../themes/vinabike_theme_roles.dart';
import '../vb_button.dart';
import '../vb_notice.dart';
import '../vb_segmented.dart';
import '../vb_status_badge.dart';
import 'global_search_result_views.dart';

/// `/tarea`: encargarle algo a alguien en cuatro preguntas, sin salir del
/// buscador (dueño, 2026-09-26).
///
/// **Por qué es un recorrido y no un formulario.** El compositor del rail ya
/// tenía todos los campos y nadie lo usaba: cero tareas en 30 días. Un
/// formulario pide decidir todo a la vez; esto pregunta una cosa por vez, en el
/// orden en que se piensa en el mostrador —¿a quién?, ¿sobre qué bici?, ¿qué
/// hay que hacer?— y cada respuesta es una fila que se elige con el teclado o
/// con un clic. Lo elegido queda arriba como migas: un clic vuelve a esa
/// pregunta sin perder lo demás.
///
/// **Por qué parte en los trabajos.** Ahí vive casi todo lo que se encarga. «Otra
/// cosa» abre cliente, proveedor, venta, compra o nada, sin que el camino del
/// taller pague por esa generalidad.
///
/// **Valores.** Es el mismo panel del buscador: filas `S-05` (radio 6,
/// selección y borde de la familia `selectionContainer`/`accentBorder`), alto
/// mínimo `F-06` 48, movimiento `F-05` (`base 200`, `fast 120`, la curva del
/// ERP y sólo opacidad con `reduce-motion`). Los controles son los canónicos:
/// `A-01 VbButton`, `S-04 VbSegmented`, `E-01 VbStatusBadge`, `VbNotice`.
/// Ningún hex entra a este archivo.
class QuickTaskFlow extends StatefulWidget {
  const QuickTaskFlow({
    super.key,
    this.initialQuery = '',
    required this.onExit,
    required this.onClose,
    this.taskService,
    this.now,
  });

  /// Lo escrito después de `/tarea `: empieza buscando a esa persona.
  final String initialQuery;

  /// Volver a la lista de acciones (esc o retroceso en la primera pregunta).
  final VoidCallback onExit;

  /// Cerrar el buscador.
  final VoidCallback onClose;

  /// Para pruebas; en la app se lee del árbol.
  final TaskService? taskService;

  /// Para pruebas: el «hoy» de los plazos.
  final DateTime Function()? now;

  @override
  State<QuickTaskFlow> createState() => _QuickTaskFlowState();
}

enum _Step {
  person,
  subject,
  contextKind,
  contextTarget,
  intent,
  details,
  done
}

class _QuickTaskFlowState extends State<QuickTaskFlow> {
  static const Duration _base = Duration(milliseconds: 200);
  static const Cubic _curve = kGlobalSearchCurve;

  late final TaskService _service =
      widget.taskService ?? context.read<TaskService>();

  // ── Preguntas ────────────────────────────────────────────────────────────
  _Step _step = _Step.person;
  bool _forward = true;
  int _highlight = 0;

  final TextEditingController _query = TextEditingController();
  late final FocusNode _queryFocus = FocusNode(onKeyEvent: _onListKey);
  final ScrollController _scroll = ScrollController();
  final GlobalKey _highlightKey = GlobalKey();

  // ── Datos ────────────────────────────────────────────────────────────────
  List<TaskAssignmentPrincipal>? _people;
  Object? _peopleError;
  List<TaskLinkableJob>? _jobs;
  Map<String, int> _serviceCounts = const {};
  Object? _jobsError;
  List<TaskContextTarget>? _targets;
  Object? _targetsError;
  List<TaskJobWorkItem>? _jobItems;
  Object? _jobItemsError;

  // ── Respuestas ───────────────────────────────────────────────────────────
  TaskAssignmentPrincipal? _person;
  TaskLinkableJob? _job;
  TaskContextKind _contextKind = TaskContextKind.none;
  TaskContextTarget? _target;
  QuickTaskIntent? _intent;
  Set<String> _selectedItems = {};
  final TextEditingController _title = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final FocusNode _titleFocus = FocusNode();

  /// El panel entero: recibe Esc en «Listo», donde no queda un campo.
  final FocusNode _panelFocus = FocusNode(debugLabel: 'quick-task-panel');
  QuickTaskDue _due = QuickTaskDue.none;
  bool _urgent = false;

  // ── Guardado ─────────────────────────────────────────────────────────────
  bool _saving = false;
  String? _saveError;
  TaskOverlapException? _overlap;
  TaskModel? _created;

  bool get _hasJob => _job != null;

  /// Un trabajo del taller se encarga a alguien con ficha de trabajador: el
  /// servidor lo exige (`assignee_not_worker_linked`). Quien no la tiene —la
  /// cuenta de la tienda, un administrador— sólo recibe «otra cosa».
  bool get _personTakesJobs => _person?.employeeId != null;

  @override
  void initState() {
    super.initState();
    _query.text = widget.initialQuery;
    _query.addListener(_onQueryChanged);
    _title.addListener(() => setState(() {}));
    unawaited(_loadPeople());
    unawaited(_loadJobs());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _queryFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _query.dispose();
    _queryFocus.dispose();
    _scroll.dispose();
    _title.dispose();
    _note.dispose();
    _titleFocus.dispose();
    _panelFocus.dispose();
    super.dispose();
  }

  // ── Carga ────────────────────────────────────────────────────────────────

  Future<void> _loadPeople() async {
    try {
      final directory = await _service.fetchAssignmentDirectory();
      if (!mounted) return;
      setState(() {
        _people =
            quickTaskPeople(directory, currentUserId: _service.currentUserId);
        _peopleError = null;
      });
    } catch (error) {
      if (mounted) setState(() => _peopleError = error);
    }
  }

  Future<void> _loadJobs() async {
    try {
      final jobs = await _service.fetchLinkableJobs();
      final counts = await _service
          .fetchJobServiceCounts(jobs.map((job) => job.id).toList());
      if (!mounted) return;
      setState(() {
        _jobs = sortQuickTaskJobs(jobs);
        _serviceCounts = counts;
        _jobsError = null;
      });
    } catch (error) {
      if (mounted) setState(() => _jobsError = error);
    }
  }

  // Cada carga lleva su número: volver al mismo trabajo o al mismo tipo de
  // vínculo lanza otra, y la respuesta vieja no puede pisar a la nueva ni la
  // selección que se hizo mientras tanto.
  int _targetsRequest = 0;
  int _jobItemsRequest = 0;

  Future<void> _loadTargets(TaskContextKind kind) async {
    final request = ++_targetsRequest;
    setState(() {
      _targets = null;
      _targetsError = null;
    });
    try {
      final targets = await _service.fetchLinkTargets(kind);
      if (!mounted || request != _targetsRequest) return;
      setState(() => _targets = targets);
    } catch (error) {
      if (mounted && request == _targetsRequest) {
        setState(() => _targetsError = error);
      }
    }
  }

  Future<void> _loadJobItems(TaskLinkableJob job) async {
    final request = ++_jobItemsRequest;
    setState(() {
      _jobItems = null;
      _jobItemsError = null;
    });
    try {
      final items = await _service.fetchJobWorkItems(job.id);
      if (!mounted || request != _jobItemsRequest) return;
      setState(() {
        _jobItems = items;
        _selectedItems = _intent?.coversServices == true
            ? items.map((item) => item.id).toSet()
            : <String>{};
      });
    } catch (error) {
      if (mounted && request == _jobItemsRequest) {
        setState(() => _jobItemsError = error);
      }
    }
  }

  // ── Navegación entre preguntas ───────────────────────────────────────────

  void _goTo(_Step step, {bool forward = true, String query = ''}) {
    setState(() {
      _forward = forward;
      _step = step;
      _highlight = 0;
      _overlap = null;
      _saveError = null;
    });
    _query.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // El campo que se va se lleva el foco: si nadie lo pide, Esc y ⌘↵ ya no
      // llegan al flujo. El título lo toma siempre, con el cursor al final
      // —Enter crea, como dice el pie—, y en «Listo» lo toma el panel.
      switch (_step) {
        case _Step.details:
          _title.selection =
              TextSelection.collapsed(offset: _title.text.length);
          _titleFocus.requestFocus();
        case _Step.done:
          _panelFocus.requestFocus();
        default:
          _queryFocus.requestFocus();
      }
    });
  }

  /// Una pregunta atrás; en la primera, de vuelta a las acciones.
  void _back() {
    switch (_step) {
      case _Step.person:
        widget.onExit();
      case _Step.subject:
        _goTo(_Step.person, forward: false);
      case _Step.contextKind:
        _goTo(_Step.subject, forward: false);
      case _Step.contextTarget:
        _goTo(_Step.contextKind, forward: false);
      case _Step.intent:
        // «¿Qué hay que hacer?» sólo se pregunta sobre un trabajo.
        _goTo(_Step.subject, forward: false);
      case _Step.details:
        _goTo(_hasJob ? _Step.intent : _stepBeforeFreeDetails(),
            forward: false);
      case _Step.done:
        widget.onClose();
    }
  }

  _Step _stepBeforeFreeDetails() => _contextKind == TaskContextKind.none
      ? _Step.contextKind
      : _Step.contextTarget;

  void _choosePerson(TaskAssignmentPrincipal person) {
    _person = person;
    // Volver por la miga y elegir a alguien sin ficha suelta el trabajo: no
    // se le puede encargar, y la miga no debe seguir mostrándolo.
    if (!_personTakesJobs && _job != null) {
      _jobItemsRequest++;
      _job = null;
      _contextKind = TaskContextKind.none;
      _jobItems = null;
      _selectedItems = {};
      _intent = null;
    }
    _goTo(_Step.subject);
  }

  void _chooseJob(TaskLinkableJob job) {
    _job = job;
    _contextKind = TaskContextKind.workshopJob;
    _target = null;
    _intent = null;
    _jobItems = null;
    _selectedItems = {};
    unawaited(_loadJobItems(job));
    _goTo(_Step.intent);
  }

  void _chooseSomethingElse() {
    _jobItemsRequest++;
    _job = null;
    _jobItems = null;
    _selectedItems = {};
    _intent = null;
    _goTo(_Step.contextKind);
  }

  void _chooseContextKind(TaskContextKind kind) {
    _contextKind = kind;
    _target = null;
    if (kind == TaskContextKind.none) {
      _intent = QuickTaskIntent.other;
      _title.text = '';
      _goTo(_Step.details);
      return;
    }
    unawaited(_loadTargets(kind));
    _goTo(_Step.contextTarget);
  }

  void _chooseTarget(TaskContextTarget target) {
    _target = target;
    _intent = QuickTaskIntent.other;
    _title.text = _contextKind == TaskContextKind.customer
        ? 'Llamar a ${target.label}'
        : '';
    _goTo(_Step.details);
  }

  void _chooseIntent(QuickTaskIntent intent, {String? typedTitle}) {
    final job = _job;
    _intent = intent;
    _title.text = typedTitle ?? (job == null ? '' : intent.titleFor(job));
    final items = _jobItems;
    if (items != null) {
      _selectedItems = intent.coversServices
          ? items.map((item) => item.id).toSet()
          : <String>{};
    }
    _goTo(_Step.details);
  }

  // ── Teclado de las preguntas con lista ───────────────────────────────────

  KeyEventResult _onListKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final count = _visibleChoices().length;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        if (count > 0) _moveHighlight(1, count);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        if (count > 0) _moveHighlight(-1, count);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _submitList();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        _back();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.backspace:
        if (_query.text.isEmpty && event is KeyDownEvent) {
          _back();
          return KeyEventResult.handled;
        }
    }
    return KeyEventResult.ignored;
  }

  void _moveHighlight(int delta, int count) {
    // `%` de Dart es euclidiano: -1 % n da n - 1, y la lista da la vuelta.
    setState(() => _highlight = (_highlight + delta) % count);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _highlightKey.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          duration: kGlobalSearchFast,
          curve: _curve,
          alignmentPolicy: delta > 0
              ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
              : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        );
      }
    });
  }

  void _submitList() {
    final choices = _visibleChoices();
    // En «¿qué hay que hacer?», escribir y apretar Enter sin elegir una fila
    // es «otra cosa» con ese título: no obliga a pasar por el menú.
    if (_step == _Step.intent &&
        _query.text.trim().isNotEmpty &&
        choices.isEmpty) {
      _chooseIntent(QuickTaskIntent.other, typedTitle: _query.text.trim());
      return;
    }
    if (choices.isEmpty) return;
    choices[_highlight.clamp(0, choices.length - 1)].onChoose();
  }

  void _onQueryChanged() {
    if (_highlight != 0) {
      setState(() => _highlight = 0);
    } else {
      setState(() {});
    }
  }

  // ── Guardar ──────────────────────────────────────────────────────────────

  bool get _canCreate =>
      !_saving &&
      _person != null &&
      _title.text.trim().isNotEmpty &&
      (_contextKind != TaskContextKind.workshopJob || _job != null) &&
      (_contextKind == TaskContextKind.none ||
          _contextKind == TaskContextKind.workshopJob ||
          _target != null);

  Future<void> _create({String? overlapDecision}) async {
    if (!_canCreate) return;
    final person = _person!;
    setState(() {
      _saving = true;
      _saveError = null;
      _overlap = null;
    });
    try {
      final job = _job;
      final note = _note.text.trim();
      final created = await _service.createTrayTask(
        title: _title.text.trim(),
        description: note.isEmpty ? null : note,
        priority: _urgent ? TaskPriority.urgent : TaskPriority.normal,
        dueDate: _due.resolve((widget.now ?? DateTime.now)()),
        assignedTo: person.employeeId == null ? person.userId : null,
        assignedEmployeeId: person.employeeId,
        linkedJobId: job?.id,
        jobItemIds: job == null ? null : _selectedItems.toList(),
        linkedCustomerId:
            _contextKind == TaskContextKind.customer ? _target?.id : null,
        linkedSupplierId:
            _contextKind == TaskContextKind.supplier ? _target?.id : null,
        linkedSalesInvoiceId:
            _contextKind == TaskContextKind.salesInvoice ? _target?.id : null,
        linkedPurchaseInvoiceId: _contextKind == TaskContextKind.purchaseInvoice
            ? _target?.id
            : null,
        overlapDecision: overlapDecision,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _created = created;
      });
      _goTo(_Step.done);
    } on TaskOverlapException catch (overlap) {
      if (mounted) {
        setState(() {
          _saving = false;
          _overlap = overlap;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = _explainError(error);
        });
      }
    }
  }

  String _explainError(Object error) {
    final text = error.toString();
    if (text.contains('assignee_not_worker_linked')) {
      return 'Una tarea del taller es para alguien del equipo del taller: '
          '${_person?.displayName ?? 'esa persona'} no tiene ficha de trabajador.';
    }
    if (text.contains('job_archived') || text.contains('job_not_linkable')) {
      return 'Ese trabajo se archivó mientras tanto. Elige otro.';
    }
    return 'No se pudo crear la tarea. Revisa la conexión e inténtalo de nuevo.';
  }

  void _openCreated() {
    final id = _created?.id;
    widget.onClose();
    if (id == null) return;
    context
        .read<RightToolbarService>()
        .openConversation(tool: ToolbarTool.tasks, conversationId: id);
  }

  void _startAnother() {
    _person = null;
    _job = null;
    _contextKind = TaskContextKind.none;
    _target = null;
    _intent = null;
    _jobItems = null;
    _selectedItems = {};
    _title.clear();
    _note.clear();
    _due = QuickTaskDue.none;
    _urgent = false;
    _created = null;
    _goTo(_Step.person);
  }

  // ── Pantalla ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    final hairline = roles?.hairline ?? theme.dividerColor;

    return Focus(
      // Esc y ⌘↵ fuera de un campo con lista: el detalle y el final.
      focusNode: _panelFocus,
      onKeyEvent: _onPanelKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          AnimatedSize(
            duration: _base,
            curve: _curve,
            alignment: Alignment.topCenter,
            child: _buildTrail(context),
          ),
          Divider(height: 1, thickness: 1, color: hairline),
          Flexible(child: _buildStepBody(context)),
          _buildFooter(context),
        ],
      ),
    );
  }

  KeyEventResult _onPanelKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _back();
      return KeyEventResult.handled;
    }
    if (_step == _Step.details &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        (keyboard.isMetaPressed || keyboard.isControlPressed)) {
      unawaited(_create());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool get _stepHasList => switch (_step) {
        _Step.person ||
        _Step.subject ||
        _Step.contextKind ||
        _Step.contextTarget ||
        _Step.intent =>
          true,
        _ => false,
      };

  ({String title, String hint}) get _question => switch (_step) {
        _Step.person => (
            title: '¿Para quién?',
            hint: 'Escribe un nombre…',
          ),
        _Step.subject => (
            title: '¿Sobre qué trabajo?',
            hint: _personTakesJobs
                ? 'Busca por número, cliente o bici…'
                : 'Presiona Enter para seguir…',
          ),
        _Step.contextKind => (
            title: '¿Sobre qué es?',
            hint: 'Elige a qué queda anexada…',
          ),
        _Step.contextTarget => (
            title: '¿${_contextKindQuestion(_contextKind)}?',
            hint: 'Escribe para buscar…',
          ),
        _Step.intent => (
            title: '¿Qué hay que hacer?',
            hint: 'Elige o escribe la tarea y presiona Enter…',
          ),
        _Step.details => (title: 'Revisa y crea', hint: ''),
        _Step.done => (title: 'Listo', hint: ''),
      };

  int get _stepNumber => switch (_step) {
        _Step.person => 1,
        _Step.subject || _Step.contextKind || _Step.contextTarget => 2,
        _Step.intent => 3,
        _Step.details || _Step.done => 4,
      };

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    final faint = roles?.faintForeground ?? theme.colorScheme.onSurfaceVariant;
    final question = _question;

    return SizedBox(
      height: kGlobalSearchRowHeight + 8,
      child: Row(
        children: [
          const SizedBox(width: 4),
          IconButton(
            key: const ValueKey('quick-task-back'),
            tooltip: _step == _Step.person ? 'Volver a las acciones' : 'Atrás',
            iconSize: 20,
            onPressed: _step == _Step.done ? null : _back,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _stepHasList
                ? TextField(
                    key: const ValueKey('quick-task-query'),
                    controller: _query,
                    focusNode: _queryFocus,
                    style: theme.textTheme.titleMedium,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: question.hint,
                      hintStyle:
                          theme.textTheme.titleMedium?.copyWith(color: faint),
                    ),
                    onSubmitted: (_) => _submitList(),
                  )
                : Text(
                    question.title,
                    style: theme.textTheme.titleMedium,
                  ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GlobalSearchKeyCap(
              label: _step == _Step.done ? 'esc cerrar' : 'esc atrás',
            ),
          ),
        ],
      ),
    );
  }

  /// Lo ya elegido, como migas: un clic vuelve a esa pregunta.
  Widget _buildTrail(BuildContext context) {
    final crumbs = <Widget>[];
    void crumb(String label, _Step step, {IconData? icon}) {
      if (crumbs.isNotEmpty) {
        crumbs.add(Icon(
          Icons.chevron_right_rounded,
          size: 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ));
      }
      crumbs.add(VbButton(
        key: ValueKey('quick-task-crumb-${step.name}'),
        label: label,
        icon: icon,
        variant: VbButtonVariant.text,
        onPressed: _step == _Step.done || _step == step
            ? null
            : () => _goTo(step, forward: false),
        disabledReason: _step == step ? 'Estás en esta pregunta' : 'Ya se creó',
      ));
    }

    final person = _person;
    if (person != null) {
      crumb(_isMe(person) ? 'Para mí' : person.displayName, _Step.person,
          icon: Icons.person_outline_rounded);
    }
    final job = _job;
    if (job != null) {
      crumb(
          job.objectLabel == null
              ? '#${job.jobNumber}'
              : '#${job.jobNumber} · ${job.objectLabel}',
          _Step.subject,
          icon: Icons.build_outlined);
    } else if (_step.index > _Step.contextKind.index &&
        _contextKind != TaskContextKind.workshopJob) {
      final target = _target;
      crumb(
        target?.label ?? _contextKindLabel(_contextKind),
        target == null ? _Step.contextKind : _Step.contextTarget,
        icon: Icons.link_rounded,
      );
    }
    final intent = _intent;
    if (intent != null && _hasJob && _step.index > _Step.intent.index) {
      crumb(intent.label, _Step.intent, icon: intent.icon);
    }

    if (crumbs.isEmpty) return const SizedBox(width: double.infinity);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Wrap(
        spacing: 2,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: crumbs,
      ),
    );
  }

  Widget _buildStepBody(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: _base,
      switchInCurve: _curve,
      switchOutCurve: Curves.easeOutCubic,
      // Sólo la pregunta que entra: aparece deslizándose; la que sale se va en
      // el acto. Con las dos en un `Stack`, el árbol de semántica se cruzaba
      // con la que entra a medio layout y Flutter lo afirma
      // (`!childSemantics.renderObject._needsLayout`), aun excluyendo la que
      // sale. Medido en la prueba del recorrido, 2026-09-26.
      layoutBuilder: (current, previous) => current ?? const SizedBox.shrink(),
      transitionBuilder: (child, animation) {
        final fade = FadeTransition(opacity: animation, child: child);
        if (reduceMotion) return fade;
        final isIncoming = child.key == ValueKey(_step);
        final dx = (_forward ? 0.06 : -0.06) * (isIncoming ? 1 : -1);
        return SlideTransition(
          position: Tween<Offset>(begin: Offset(dx, 0), end: Offset.zero)
              .animate(animation),
          child: fade,
        );
      },
      child: KeyedSubtree(
        key: ValueKey(_step),
        child: switch (_step) {
          _Step.details => _buildDetails(context),
          _Step.done => _buildDone(context),
          _ => _buildChoiceList(context),
        },
      ),
    );
  }

  // ── Listas ───────────────────────────────────────────────────────────────

  List<_Choice> _visibleChoices() {
    switch (_step) {
      case _Step.person:
        final people = _people;
        if (people == null) return const [];
        return [
          for (final person in filterQuickTaskPeople(people, _query.text))
            _Choice(
              key: 'person-${person.assignmentKey}',
              title: _isMe(person) ? 'Para mí' : person.displayName,
              subtitle: _isMe(person)
                  ? person.displayName
                  : person.assignmentContextLabel,
              leading: _Avatar(person: person),
              onChoose: () => _choosePerson(person),
            ),
        ];
      case _Step.subject:
        final jobs = _personTakesJobs ? _jobs : const <TaskLinkableJob>[];
        if (jobs == null) return const [];
        final filtered = filterQuickTaskJobs(jobs, _query.text);
        return [
          for (final job in filtered)
            _Choice(
              key: 'job-${job.id}',
              title: job.objectDisplay == null
                  ? '#${job.jobNumber}'
                  : '#${job.jobNumber} · ${job.objectDisplay}',
              subtitle: [
                job.customerName,
                job.statusLabel,
                if (job.receivedAt case final received?)
                  quickTaskJobDateLabel(received,
                      now: (widget.now ?? DateTime.now)()),
              ]
                  .whereType<String>()
                  .where((part) => part.trim().isNotEmpty)
                  .join(' · '),
              // El mismo ícono que la tabla de trabajos para un componente.
              leading: GlobalSearchChoiceIcon(
                  icon: job.isComponent
                      ? Icons.build_circle_outlined
                      : Icons.pedal_bike_rounded),
              badges: _jobBadges(job),
              onChoose: () => _chooseJob(job),
            ),
          _Choice(
            key: 'job-other',
            title: 'Otra cosa',
            subtitle: 'Un cliente, un proveedor, una venta, una compra o nada',
            leading:
                const GlobalSearchChoiceIcon(icon: Icons.more_horiz_rounded),
            onChoose: _chooseSomethingElse,
          ),
        ];
      case _Step.contextKind:
        final options = <(TaskContextKind, String, String, IconData)>[
          (
            TaskContextKind.none,
            'Nada en particular',
            'Una tarea suelta',
            Icons.check_box_outline_blank_rounded
          ),
          (
            TaskContextKind.customer,
            'Un cliente',
            'Llamarlo, cobrarle, avisarle',
            Icons.person_search_outlined
          ),
          (
            TaskContextKind.supplier,
            'Un proveedor',
            'Pedir, reclamar, pagar',
            Icons.local_shipping_outlined
          ),
          (
            TaskContextKind.salesInvoice,
            'Una venta',
            'Una factura o boleta emitida',
            Icons.receipt_long_outlined
          ),
          (
            TaskContextKind.purchaseInvoice,
            'Una compra',
            'Un documento de un proveedor',
            Icons.inventory_2_outlined
          ),
        ];
        final query = _query.text.trim().toLowerCase();
        return [
          for (final (kind, title, subtitle, icon) in options)
            if (query.isEmpty || title.toLowerCase().contains(query))
              _Choice(
                key: 'kind-${kind.name}',
                title: title,
                subtitle: subtitle,
                leading: GlobalSearchChoiceIcon(icon: icon),
                onChoose: () => _chooseContextKind(kind),
              ),
        ];
      case _Step.contextTarget:
        final targets = _targets;
        if (targets == null) return const [];
        return [
          for (final target
              in filterQuickTaskTargets(targets, _query.text).take(60))
            _Choice(
              key: 'target-${target.id}',
              title: target.label,
              subtitle: target.context,
              leading:
                  GlobalSearchChoiceIcon(icon: _contextKindIcon(_contextKind)),
              onChoose: () => _chooseTarget(target),
            ),
        ];
      case _Step.intent:
        final query = _query.text.trim().toLowerCase();
        final job = _job;
        return [
          for (final intent in QuickTaskIntent.values)
            if (query.isEmpty ||
                intent.label.toLowerCase().contains(query) ||
                intent == QuickTaskIntent.other)
              if (intent != QuickTaskIntent.other || query.isEmpty)
                _Choice(
                  key: 'intent-${intent.name}',
                  title: intent.label,
                  subtitle: intent == QuickTaskIntent.work
                      ? _workSubtitle(job)
                      : intent.description,
                  leading: GlobalSearchChoiceIcon(icon: intent.icon),
                  onChoose: () => _chooseIntent(intent),
                ),
          if (query.isNotEmpty)
            _Choice(
              key: 'intent-typed',
              title: '«${_query.text.trim()}»',
              subtitle: 'Crear la tarea con este título',
              leading: const GlobalSearchChoiceIcon(icon: Icons.edit_outlined),
              onChoose: () => _chooseIntent(QuickTaskIntent.other,
                  typedTitle: _query.text.trim()),
            ),
        ];
      case _Step.details:
      case _Step.done:
        return const [];
    }
  }

  String _workSubtitle(TaskLinkableJob? job) {
    if (job == null) return QuickTaskIntent.work.description;
    final count = _serviceCounts[job.id] ?? 0;
    if (count == 0) return 'Este trabajo todavía no tiene servicios cargados';
    return '${quickTaskServiceCountLabel(count)}, como lista para ir marcando';
  }

  List<Widget> _jobBadges(TaskLinkableJob job) {
    final badges = <Widget>[];
    final quotation = quickTaskQuotationSignal(job);
    if (quotation != null) {
      badges.add(VbStatusBadge(
          label: quotation.label, tone: _tone(quotation.tone), dense: true));
    }
    final invoice = quickTaskInvoiceSignal(job);
    if (invoice != null) {
      badges.add(VbStatusBadge(
          label: invoice.label, tone: _tone(invoice.tone), dense: true));
    }
    badges.add(VbStatusBadge(
      label: quickTaskServiceCountLabel(_serviceCounts[job.id] ?? 0),
      dense: true,
    ));
    return badges;
  }

  VbStatusTone _tone(QuickTaskSignalTone tone) => switch (tone) {
        QuickTaskSignalTone.neutral => VbStatusTone.neutral,
        QuickTaskSignalTone.info => VbStatusTone.info,
        QuickTaskSignalTone.success => VbStatusTone.success,
        QuickTaskSignalTone.warning => VbStatusTone.warning,
        QuickTaskSignalTone.danger => VbStatusTone.danger,
      };

  Widget _buildChoiceList(BuildContext context) {
    final loading = switch (_step) {
      _Step.person => _people == null && _peopleError == null,
      _Step.subject => _personTakesJobs && _jobs == null && _jobsError == null,
      _Step.contextTarget => _targets == null && _targetsError == null,
      _ => false,
    };
    final error = switch (_step) {
      _Step.person => _peopleError,
      _Step.subject => _personTakesJobs ? _jobsError : null,
      _Step.contextTarget => _targetsError,
      _ => null,
    };
    if (error != null) {
      return GlobalSearchMessage(
        icon: Icons.cloud_off_rounded,
        title: 'No se pudo cargar',
        detail: 'Revisa la conexión e inténtalo de nuevo.',
        action: TextButton(
          onPressed: () {
            switch (_step) {
              case _Step.person:
                setState(() => _peopleError = null);
                unawaited(_loadPeople());
              case _Step.subject:
                setState(() => _jobsError = null);
                unawaited(_loadJobs());
              case _Step.contextTarget:
                unawaited(_loadTargets(_contextKind));
              default:
                break;
            }
          },
          child: const Text('Reintentar'),
        ),
      );
    }
    if (loading) {
      return const GlobalSearchMessage(
        icon: Icons.hourglass_empty_rounded,
        title: 'Cargando…',
        detail: 'Un segundo.',
      );
    }

    final choices = _visibleChoices();
    if (choices.isEmpty) {
      return GlobalSearchMessage(
        icon: Icons.search_off_rounded,
        title: 'Nada con «${_query.text.trim()}»',
        detail: _step == _Step.person
            ? 'Revisa el nombre.'
            : 'Prueba con otra palabra.',
      );
    }

    final highlight = _highlight.clamp(0, choices.length - 1);
    return ListView(
      controller: _scroll,
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        GlobalSearchGroupHeader(title: '$_stepNumber · ${_question.title}'),
        if (_step == _Step.subject && !_personTakesJobs)
          _ListNote(
            'Los trabajos del taller se encargan a alguien del equipo: '
            '${_person?.displayName ?? 'esta cuenta'} no tiene ficha de '
            'trabajador.',
          ),
        for (var i = 0; i < choices.length; i++)
          GlobalSearchChoiceRow(
            key: i == highlight ? _highlightKey : ValueKey(choices[i].key),
            title: choices[i].title,
            subtitle: choices[i].subtitle,
            leading: choices[i].leading,
            badges: choices[i].badges,
            highlighted: i == highlight,
            onTap: choices[i].onChoose,
            onHover: () => setState(() => _highlight = i),
          ),
      ],
    );
  }

  // ── Detalle ──────────────────────────────────────────────────────────────

  Widget _buildDetails(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    final faint = roles?.faintForeground ?? theme.colorScheme.onSurfaceVariant;
    final person = _person;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('quick-task-title'),
            controller: _title,
            focusNode: _titleFocus,
            style: theme.textTheme.titleMedium,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Qué hay que hacer',
              isDense: true,
            ),
            onSubmitted: (_) => unawaited(_create()),
          ),
          if (_hasJob) ...[
            const SizedBox(height: 14),
            _buildChecklist(context),
          ],
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('quick-task-note'),
            controller: _note,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Nota para quien la haga (opcional)',
              hintText: 'Lo que tiene que saber: un detalle, un aviso…',
              isDense: true,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _LabeledControl(
                label: 'Plazo',
                child: VbSegmented<QuickTaskDue>(
                  groupLabel: 'Plazo',
                  options: const [
                    VbSegmentedOption(
                        value: QuickTaskDue.none, label: 'Sin plazo'),
                    VbSegmentedOption(value: QuickTaskDue.today, label: 'Hoy'),
                    VbSegmentedOption(
                        value: QuickTaskDue.tomorrow, label: 'Mañana'),
                    VbSegmentedOption(
                        value: QuickTaskDue.week, label: 'Esta semana'),
                  ],
                  value: _due,
                  onChanged: (value) => setState(() => _due = value),
                ),
              ),
              _LabeledControl(
                label: 'Prioridad',
                child: VbSegmented<bool>(
                  groupLabel: 'Prioridad',
                  options: const [
                    VbSegmentedOption(value: false, label: 'Normal'),
                    VbSegmentedOption(value: true, label: 'Urgente'),
                  ],
                  value: _urgent,
                  onChanged: (value) => setState(() => _urgent = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (person != null)
            Text(
              quickTaskDeliveryNote(person,
                  currentUserId: _service.currentUserId),
              style: theme.textTheme.bodySmall?.copyWith(color: faint),
            ),
          if (_overlap != null) ...[
            const SizedBox(height: 10),
            _buildOverlapNotice(context, _overlap!),
          ],
          if (_saveError != null) ...[
            const SizedBox(height: 10),
            VbNotice(
              title: 'No se creó la tarea',
              body: _saveError,
              tone: VbNoticeTone.danger,
            ),
          ],
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: VbButton(
                  label: 'Atrás',
                  variant: VbButtonVariant.text,
                  onPressed: _saving ? null : _back,
                  disabledReason: 'Creando la tarea',
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: VbButton(
                  key: const ValueKey('quick-task-create'),
                  label: 'Crear tarea',
                  icon: Icons.add_task_rounded,
                  busy: _saving,
                  onPressed: _canCreate ? () => unawaited(_create()) : null,
                  disabledReason: _title.text.trim().isEmpty
                      ? 'Escribe qué hay que hacer'
                      : 'Creando la tarea',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChecklist(BuildContext context) {
    final theme = Theme.of(context);
    final items = _jobItems;
    if (_jobItemsError != null) {
      return Text(
        'No se pudieron leer los servicios del trabajo. La tarea igual '
        'queda anexada al trabajo.',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }
    if (items == null) {
      return Text('Leyendo los servicios…',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant));
    }
    if (items.isEmpty) {
      return Text(
        'Este trabajo todavía no tiene servicios cargados: la tarea queda '
        'anexada al trabajo completo.',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }

    final allSelected = _selectedItems.length == items.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _SectionLabel(
                _selectedItems.isEmpty
                    ? 'Servicios (ninguno: la tarea es sobre el trabajo)'
                    : 'Lista para ir marcando · ${_selectedItems.length} de '
                        '${items.length}',
              ),
            ),
            VbButton(
              key: const ValueKey('quick-task-toggle-all'),
              label: allSelected ? 'Ninguno' : 'Todos',
              variant: VbButtonVariant.text,
              onPressed: () => setState(() {
                _selectedItems = allSelected
                    ? <String>{}
                    : items.map((item) => item.id).toSet();
              }),
            ),
          ],
        ),
        for (final item in items)
          _CheckRow(
            key: ValueKey('quick-task-item-${item.id}'),
            item: item,
            checked: _selectedItems.contains(item.id),
            onChanged: (checked) => setState(() {
              final next = {..._selectedItems};
              checked ? next.add(item.id) : next.remove(item.id);
              _selectedItems = next;
            }),
          ),
      ],
    );
  }

  Widget _buildOverlapNotice(
      BuildContext context, TaskOverlapException overlap) {
    final titles = overlap.overlaps
        .take(3)
        .map((row) => '«${row['title'] ?? 'Tarea'}»')
        .join(', ');
    return VbNotice(
      title: 'Algunos servicios ya están en otra tarea',
      body: 'Están en $titles. Puedes compartirlos (los dos los ven y '
          'marcan) o traspasarlos a esta tarea.',
      tone: VbNoticeTone.warning,
      action: Wrap(
        spacing: 8,
        children: [
          VbButton(
            label: 'Compartir',
            variant: VbButtonVariant.secondary,
            onPressed: _saving
                ? null
                : () => unawaited(_create(overlapDecision: 'collaborate')),
            disabledReason: 'Creando la tarea',
          ),
          VbButton(
            label: 'Traspasar aquí',
            onPressed: _saving
                ? null
                : () => unawaited(_create(overlapDecision: 'transfer')),
            disabledReason: 'Creando la tarea',
          ),
        ],
      ),
    );
  }

  // ── Final ────────────────────────────────────────────────────────────────

  Widget _buildDone(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    final person = _person;
    final success = roles?.success.accent ?? theme.colorScheme.primary;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: reduceMotion ? 1 : 0.6, end: 1),
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Icon(Icons.check_circle_rounded, size: 44, color: success),
          ),
          const SizedBox(height: 10),
          Text(
            person == null
                ? 'Tarea creada'
                : _isMe(person)
                    ? 'Tarea creada para ti'
                    : 'Tarea creada para ${person.displayName}',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            _title.text.trim(),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (person != null) ...[
            const SizedBox(height: 8),
            Text(
              quickTaskDeliveryNote(person,
                  currentUserId: _service.currentUserId),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: roles?.faintForeground ??
                      theme.colorScheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              VbButton(
                key: const ValueKey('quick-task-another'),
                label: 'Crear otra',
                variant: VbButtonVariant.secondary,
                icon: Icons.add_rounded,
                onPressed: _startAnother,
              ),
              VbButton(
                key: const ValueKey('quick-task-open'),
                label: 'Ver la tarea',
                icon: Icons.open_in_new_rounded,
                onPressed: _openCreated,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    final ink = roles?.faintForeground ?? theme.colorScheme.onSurfaceVariant;
    final style = theme.textTheme.labelSmall?.copyWith(color: ink);
    final hints = switch (_step) {
      _Step.details => '↵ crear · esc atrás',
      _Step.done => 'esc cerrar',
      _ => '↑ ↓ moverse · ↵ elegir · esc atrás',
    };

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: roles?.hairline ?? theme.dividerColor),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Row(
        children: [
          Expanded(child: Text(hints, style: style)),
          Semantics(
            label: 'Paso $_stepNumber de 4',
            excludeSemantics: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 1; i <= 4; i++)
                  AnimatedContainer(
                    duration: _base,
                    curve: _curve,
                    margin: const EdgeInsets.only(left: 4),
                    width: i == _stepNumber ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i <= _stepNumber
                          ? theme.colorScheme.primary
                          : (roles?.hairline ?? theme.dividerColor),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Palabras ─────────────────────────────────────────────────────────────

  bool _isMe(TaskAssignmentPrincipal person) =>
      person.userId != null && person.userId == _service.currentUserId;

  String _contextKindLabel(TaskContextKind kind) => switch (kind) {
        TaskContextKind.customer => 'Un cliente',
        TaskContextKind.supplier => 'Un proveedor',
        TaskContextKind.salesInvoice => 'Una venta',
        TaskContextKind.purchaseInvoice => 'Una compra',
        TaskContextKind.workshopJob => 'Un trabajo',
        TaskContextKind.none => 'Sin vínculo',
      };

  String _contextKindQuestion(TaskContextKind kind) => switch (kind) {
        TaskContextKind.customer => 'Qué cliente',
        TaskContextKind.supplier => 'Qué proveedor',
        TaskContextKind.salesInvoice => 'Qué venta',
        TaskContextKind.purchaseInvoice => 'Qué compra',
        _ => 'Cuál',
      };

  IconData _contextKindIcon(TaskContextKind kind) => switch (kind) {
        TaskContextKind.customer => Icons.person_search_outlined,
        TaskContextKind.supplier => Icons.local_shipping_outlined,
        TaskContextKind.salesInvoice => Icons.receipt_long_outlined,
        TaskContextKind.purchaseInvoice => Icons.inventory_2_outlined,
        _ => Icons.link_rounded,
      };
}

/// Una respuesta posible a la pregunta en curso.
class _Choice {
  const _Choice({
    required this.key,
    required this.title,
    required this.leading,
    required this.onChoose,
    this.subtitle,
    this.badges = const [],
  });

  final String key;
  final String title;
  final String? subtitle;
  final Widget leading;
  final List<Widget> badges;
  final VoidCallback onChoose;
}

/// Las iniciales de la persona, en uno de los cuatro colores de avatar del
/// tema, siempre el mismo para la misma persona.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.person});

  final TaskAssignmentPrincipal person;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    final pairs = roles == null
        ? [
            (
              theme.colorScheme.secondaryContainer,
              theme.colorScheme.onSecondaryContainer
            )
          ]
        : [
            (roles.avatarA, roles.onAvatarA),
            (roles.avatarB, roles.onAvatarB),
            (roles.avatarC, roles.onAvatarC),
            (roles.avatarD, roles.onAvatarD),
          ];
    final seed = person.assignmentKey.codeUnits.fold<int>(0, (a, b) => a + b);
    final (background, foreground) = pairs[seed % pairs.length];
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Text(
        person.initials,
        style: theme.textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Una línea que explica por qué la lista es más corta de lo esperado.
class _ListNote extends StatelessWidget {
  const _ListNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      child: Text(
        text,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: roles?.faintForeground ?? theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _LabeledControl extends StatelessWidget {
  const _LabeledControl({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

/// Un servicio del trabajo en la lista que el responsable va a ir marcando.
class _CheckRow extends StatelessWidget {
  const _CheckRow({
    super.key,
    required this.item,
    required this.checked,
    required this.onChanged,
  });

  final TaskJobWorkItem item;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = [item.bikeLabel, item.instructions]
        .whereType<String>()
        .where((part) => part.trim().isNotEmpty)
        .join(' · ');
    return InkWell(
      borderRadius: BorderRadius.circular(kGlobalSearchRowRadius),
      onTap: () => onChanged(!checked),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kGlobalSearchRowHeight),
        child: Row(
          children: [
            Checkbox(
              value: checked,
              onChanged: (value) => onChanged(value ?? false),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: kGlobalSearchFast,
                    style: (theme.textTheme.bodyMedium ?? const TextStyle())
                        .copyWith(
                      color: checked
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    child: Text(item.name),
                  ),
                  if (detail.isNotEmpty)
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
