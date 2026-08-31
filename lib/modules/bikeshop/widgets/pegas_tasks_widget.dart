import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../tasks/models/task_model.dart';
import '../../tasks/services/task_service.dart';
import '../../../shared/services/user_management_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/widgets/vb_segmented.dart';
import 'task_form_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';

/// Parent-owned compact task browsing context.
///
/// The workshop host keeps this session alive while another mode or linked
/// record is open, so task filters, search, and scroll resume exactly.
class PegasTasksSession {
  PegasTasksSession({
    this.statusFilter = TaskStatus.pending,
    this.priorityFilter,
    this.searchQuery = '',
    this.trayScope = PegasTasksTrayScope.team,
    this.scrollOffset = 0,
    Set<String>? expandedTaskKeys,
  }) : _expandedTaskKeys = {...?expandedTaskKeys};

  TaskStatus? statusFilter;
  TaskPriority? priorityFilter;
  String searchQuery;
  PegasTasksTrayScope trayScope;
  double scrollOffset;
  Set<String>? _expandedTaskKeys;

  // Null-safe for sessions that survive a development hot reload which added
  // this field after the object had already been created.
  Set<String> get expandedTaskKeys => _expandedTaskKeys ??= <String>{};
}

/// Alcance de bandeja de la vista completa: coordinación (equipo), lo mío,
/// o mis privadas. Mismo vocabulario que el panel rápido.
enum PegasTasksTrayScope { inbox, team, personal }

class PegasTasksWidget extends StatefulWidget {
  const PegasTasksWidget({
    super.key,
    this.useCompactLayout,
    this.session,
  });

  final bool? useCompactLayout;
  final PegasTasksSession? session;

  @override
  State<PegasTasksWidget> createState() => _PegasTasksWidgetState();
}

class _PegasTasksWidgetState extends State<PegasTasksWidget> {
  static const double _compactBreakpoint = 900;
  static const double _desktopMinimumContentWidth = 1200;

  // Filters
  TaskStatus? _statusFilter = TaskStatus.pending;
  TaskPriority? _priorityFilter;
  PegasTasksTrayScope _trayScope = PegasTasksTrayScope.team;
  String _searchQuery = '';
  late final TextEditingController _searchController;
  late final ScrollController _compactScrollController;
  late final PegasTasksSession _localSession;

  PegasTasksSession get _session => widget.session ?? _localSession;

  // Inline editing
  String? _editingTitleTaskId;
  String? _savingTitleTaskId;
  late TextEditingController _titleController;

  // Users cache for assignee menu
  List<Map<String, dynamic>>? _users;
  bool _usersLoading = false;

  // Nombres canónicos por user_id (directorio de asignación): la fila del
  // RPC trae assigned_to sin assignee_name, y sin esto una asignación
  // recién hecha se seguía viendo «Sin asignar».
  Map<String, String> _principalNames = const {};

  String? _assigneeDisplayName(TaskModel task) =>
      task.assigneeName ??
      (task.assignedTo == null ? null : _principalNames[task.assignedTo!]);

  @override
  void initState() {
    super.initState();
    _localSession = PegasTasksSession();
    _statusFilter = _session.statusFilter;
    _priorityFilter = _session.priorityFilter;
    _trayScope = _session.trayScope;
    _searchQuery = _session.searchQuery;
    _searchController = TextEditingController(text: _searchQuery);
    _compactScrollController = ScrollController(
      initialScrollOffset: _session.scrollOffset,
    )..addListener(_rememberCompactScroll);
    _titleController = TextEditingController();
    _loadUsers();
    _loadPrincipalNames();
  }

  @override
  void dispose() {
    _persistSession();
    _compactScrollController
      ..removeListener(_rememberCompactScroll)
      ..dispose();
    _searchController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _rememberCompactScroll() {
    if (_compactScrollController.hasClients) {
      _session.scrollOffset = _compactScrollController.offset;
    }
  }

  void _persistSession() {
    _session
      ..statusFilter = _statusFilter
      ..priorityFilter = _priorityFilter
      ..trayScope = _trayScope
      ..searchQuery = _searchQuery;
    _rememberCompactScroll();
  }

  void _updateViewState(VoidCallback mutation) {
    setState(mutation);
    _persistSession();
  }

  Future<void> _loadPrincipalNames() async {
    try {
      final directory =
          await context.read<TaskService>().fetchAssignmentDirectory();
      if (!mounted) return;
      setState(() {
        _principalNames = {
          for (final principal in directory)
            if (principal.userId != null)
              principal.userId!: principal.displayName,
        };
      });
    } catch (_) {
      // El nombre denormalizado sigue siendo el fallback.
    }
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
        final currentUserId = taskService.currentUserId;
        final allTasks = taskService.tasks.where((task) {
          switch (_trayScope) {
            case PegasTasksTrayScope.inbox:
              return task.assignedTo == currentUserId;
            case PegasTasksTrayScope.team:
              return task.visibility != TaskVisibility.private;
            case PegasTasksTrayScope.personal:
              return task.visibility == TaskVisibility.private &&
                  task.createdBy == currentUserId;
          }
        }).toList();

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

        return LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = widget.useCompactLayout ??
                constraints.maxWidth < _compactBreakpoint;
            if (!isCompact) {
              return _buildDesktopWorkspace(
                constraints: constraints,
                theme: theme,
                tasks: filteredTasks,
                hasAnyTasks: allTasks.isNotEmpty,
                pendingCount: pendingCount,
                inProgressCount: inProgressCount,
                completedCount: completedCount,
                overdueCount: overdueCount,
              );
            }

            return Column(
              children: [
                _buildCompactControls(
                  theme: theme,
                  visibleCount: filteredTasks.length,
                  pendingCount: pendingCount,
                  inProgressCount: inProgressCount,
                  completedCount: completedCount,
                  overdueCount: overdueCount,
                ),
                Expanded(
                  child: filteredTasks.isEmpty
                      ? _buildEmptyState(hasAnyTasks: allTasks.isNotEmpty)
                      : _buildCompactTasksList(filteredTasks),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDesktopWorkspace({
    required BoxConstraints constraints,
    required ThemeData theme,
    required List<TaskModel> tasks,
    required bool hasAnyTasks,
    required int pendingCount,
    required int inProgressCount,
    required int completedCount,
    required int overdueCount,
  }) {
    final contentWidth = constraints.maxWidth < _desktopMinimumContentWidth
        ? _desktopMinimumContentWidth
        : constraints.maxWidth;

    return SingleChildScrollView(
      key: const PageStorageKey('workshop-tasks-desktop-horizontal'),
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: contentWidth,
        height: constraints.maxHeight,
        child: Column(
          children: [
            _buildDesktopStatsBar(
              theme: theme,
              pendingCount: pendingCount,
              inProgressCount: inProgressCount,
              completedCount: completedCount,
              overdueCount: overdueCount,
            ),
            _buildDesktopSearchBar(theme),
            _buildDesktopTableHeader(theme),
            Expanded(
              child: tasks.isEmpty
                  ? _buildEmptyState(hasAnyTasks: hasAnyTasks)
                  : _buildTasksList(tasks),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopStatsBar({
    required ThemeData theme,
    required int pendingCount,
    required int inProgressCount,
    required int completedCount,
    required int overdueCount,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          _buildStatChip(
            icon: Icons.pending_actions,
            label: '$pendingCount Pendientes',
            color: _statusColor(TaskStatus.pending),
            isActive: _statusFilter == TaskStatus.pending,
            onTap: () => _updateViewState(() => _statusFilter =
                _statusFilter == TaskStatus.pending
                    ? null
                    : TaskStatus.pending),
          ),
          const SizedBox(width: 8),
          _buildStatChip(
            icon: Icons.play_circle_outline,
            label: '$inProgressCount En Curso',
            color: _statusColor(TaskStatus.inProgress),
            isActive: _statusFilter == TaskStatus.inProgress,
            onTap: () => _updateViewState(() => _statusFilter =
                _statusFilter == TaskStatus.inProgress
                    ? null
                    : TaskStatus.inProgress),
          ),
          const SizedBox(width: 8),
          _buildStatChip(
            icon: Icons.check_circle_outline,
            label: '$completedCount Completadas',
            color: _statusColor(TaskStatus.completed),
            isActive: _statusFilter == TaskStatus.completed,
            onTap: () => _updateViewState(() => _statusFilter =
                _statusFilter == TaskStatus.completed
                    ? null
                    : TaskStatus.completed),
          ),
          if (overdueCount > 0) ...[
            const SizedBox(width: 8),
            _buildStatChip(
              icon: Icons.warning_amber_rounded,
              label: '$overdueCount Vencidas',
              color: theme.colorScheme.error,
              isActive: false,
              onTap: null,
            ),
          ],
          const Spacer(),
          _buildPriorityFilter(),
        ],
      ),
    );
  }

  Widget _buildTrayScopeSelector() {
    return VbSegmented<PegasTasksTrayScope>(
      groupLabel: 'Alcance de la bandeja',
      options: const [
        VbSegmentedOption(
            value: PegasTasksTrayScope.inbox, label: 'Mi bandeja'),
        VbSegmentedOption(value: PegasTasksTrayScope.team, label: 'Equipo'),
        VbSegmentedOption(
            value: PegasTasksTrayScope.personal, label: 'Personales'),
      ],
      value: _trayScope,
      onChanged: (scope) => _updateViewState(() => _trayScope = scope),
    );
  }

  Widget _buildDesktopSearchBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      child: Row(
        children: [
          // Un hijo no-flex de un Row recibe ancho no acotado, y la pista de
          // S-04 usa flex interno: el host debe acotarlo.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: _buildTrayScopeSelector(),
          ),
          const SizedBox(width: 12),
          Expanded(child: _buildSearchField(theme)),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: _showNewTaskDialog,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Nueva Tarea'),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopTableHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          top: BorderSide(color: theme.dividerColor),
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: const Row(
        children: [
          SizedBox(width: 36),
          Expanded(
            flex: 4,
            child: Text(
              'Tarea',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Estado',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Prioridad',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Fecha',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Asignado',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Adjuntos',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
          SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildCompactControls({
    required ThemeData theme,
    required int visibleCount,
    required int pendingCount,
    required int inProgressCount,
    required int completedCount,
    required int overdueCount,
  }) {
    return Container(
      key: const ValueKey('workshop-tasks-compact-controls'),
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTrayScopeSelector(),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildSearchField(theme, compact: true)),
              const SizedBox(width: 8),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  key: const ValueKey('workshop-tasks-compact-new'),
                  onPressed: _showNewTaskDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Nueva'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildCompactStatusFilter(
                  pendingCount: pendingCount,
                  inProgressCount: inProgressCount,
                  completedCount: completedCount,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _buildCompactPriorityFilter()),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 3,
            children: [
              Text(
                '$visibleCount visibles',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                '$pendingCount pendientes',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                '$inProgressCount en curso',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                '$completedCount completadas',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (overdueCount > 0)
                Text(
                  '$overdueCount vencidas',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(
    ThemeData theme, {
    bool compact = false,
  }) {
    final field = TextField(
      key: const ValueKey('workshop-tasks-search'),
      controller: _searchController,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Buscar tareas…',
        prefixIcon: const Icon(Icons.search, size: 20),
        prefixIconConstraints: BoxConstraints(
          minWidth: compact ? 48 : 42,
          minHeight: compact ? 48 : 42,
        ),
        contentPadding: EdgeInsets.symmetric(
          vertical: compact ? 12 : 0,
          horizontal: 12,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      ),
      onChanged: (val) => _updateViewState(() => _searchQuery = val),
    );

    if (!compact) {
      return SizedBox(height: 42, child: field);
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: field,
    );
  }

  void _showNewTaskDialog() {
    showDialog(
      context: context,
      builder: (context) => const TaskFormDialog(),
    );
  }

  Widget _buildPriorityFilter() {
    return PopupMenuButton<String>(
      tooltip: 'Filtrar por prioridad',
      initialValue: _priorityFilter?.name ?? 'all',
      onSelected: _selectPriorityFilter,
      itemBuilder: _buildPriorityFilterItems,
      child: Chip(
        avatar: Icon(
          _priorityFilter != null
              ? _priorityIcon(_priorityFilter!)
              : Icons.filter_list,
          size: 16,
          color:
              _priorityFilter != null ? _priorityColor(_priorityFilter!) : null,
        ),
        label: Text(
          _priorityFilter != null
              ? _translatePriority(_priorityFilter!)
              : 'Prioridad',
          style: const TextStyle(fontSize: 12),
        ),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildPriorityFilterItems(
    BuildContext context,
  ) {
    return [
      const PopupMenuItem(
        value: 'all',
        child: Text('Todas las prioridades'),
      ),
      const PopupMenuDivider(),
      ...TaskPriority.values.map(
        (priority) => PopupMenuItem(
          value: priority.name,
          child: Row(
            children: [
              Icon(
                _priorityIcon(priority),
                size: 16,
                color: _priorityColor(priority),
              ),
              const SizedBox(width: 8),
              Text(_translatePriority(priority)),
            ],
          ),
        ),
      ),
    ];
  }

  void _selectPriorityFilter(String value) {
    _updateViewState(() {
      _priorityFilter = value == 'all'
          ? null
          : TaskPriority.values
              .firstWhere((priority) => priority.name == value);
    });
  }

  Widget _buildCompactStatusFilter({
    required int pendingCount,
    required int inProgressCount,
    required int completedCount,
  }) {
    final selectedLabel =
        _statusFilter == null ? 'Todos' : _translateStatus(_statusFilter!);
    final selectedCount = switch (_statusFilter) {
      TaskStatus.pending => pendingCount,
      TaskStatus.inProgress => inProgressCount,
      TaskStatus.blocked => null,
      TaskStatus.completed => completedCount,
      TaskStatus.cancelled => null,
      null => null,
    };

    return PopupMenuButton<String>(
      key: const ValueKey('workshop-tasks-compact-status-filter'),
      tooltip: 'Filtrar por estado',
      initialValue: _statusFilter?.name ?? 'all',
      onSelected: (value) {
        _updateViewState(() {
          _statusFilter = value == 'all'
              ? null
              : TaskStatus.values.firstWhere((status) => status.name == value);
        });
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'all', child: Text('Todos los estados')),
        const PopupMenuDivider(),
        ...TaskStatus.values.map(
          (status) => PopupMenuItem(
            value: status.name,
            child: Text(_translateStatus(status)),
          ),
        ),
      ],
      child: _buildCompactFilterButton(
        eyebrow: 'Estado',
        value: selectedCount == null
            ? selectedLabel
            : '$selectedLabel · $selectedCount',
      ),
    );
  }

  Widget _buildCompactPriorityFilter() {
    return PopupMenuButton<String>(
      key: const ValueKey('workshop-tasks-compact-priority-filter'),
      tooltip: 'Filtrar por prioridad',
      initialValue: _priorityFilter?.name ?? 'all',
      onSelected: _selectPriorityFilter,
      itemBuilder: _buildPriorityFilterItems,
      child: _buildCompactFilterButton(
        eyebrow: 'Prioridad',
        value: _priorityFilter == null
            ? 'Todas'
            : _translatePriority(_priorityFilter!),
      ),
    );
  }

  Widget _buildCompactFilterButton({
    required String eyebrow,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  eyebrow,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.keyboard_arrow_down, size: 18),
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required Color color,
    required bool isActive,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isActive
                ? theme.colorScheme.secondaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: isActive ? color : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: isActive
                      ? theme.colorScheme.onSecondaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({required bool hasAnyTasks}) {
    final isFilteredEmpty = hasAnyTasks;
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          container: true,
          label: isFilteredEmpty
              ? 'Sin resultados para los filtros de tareas'
              : 'No hay tareas registradas',
          child: Column(
            key: ValueKey(
              isFilteredEmpty
                  ? 'workshop-tasks-filtered-empty'
                  : 'workshop-tasks-empty',
            ),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isFilteredEmpty
                    ? Icons.filter_alt_off_outlined
                    : Icons.task_alt,
                size: 56,
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 16),
              Text(
                isFilteredEmpty
                    ? 'Sin resultados para estos filtros'
                    : 'Aún no hay tareas',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isFilteredEmpty
                    ? 'Cambia la búsqueda, el estado o la prioridad.'
                    : 'Crea la primera tarea para organizar el trabajo del taller.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              if (isFilteredEmpty)
                OutlinedButton(
                  key: const ValueKey('workshop-tasks-clear-filters'),
                  onPressed: _clearTaskFilters,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  child: const Text('Limpiar filtros'),
                )
              else
                FilledButton(
                  key: const ValueKey('workshop-tasks-empty-new'),
                  onPressed: _showNewTaskDialog,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  child: const Text('Nueva tarea'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _clearTaskFilters() {
    _searchController.clear();
    _updateViewState(() {
      _searchQuery = '';
      _statusFilter = null;
      _priorityFilter = null;
    });
  }

  Widget _buildCompactTasksList(List<TaskModel> tasks) {
    return ListView.builder(
      key: const ValueKey('workshop-tasks-compact-list'),
      controller: _compactScrollController,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      itemCount: tasks.length,
      itemBuilder: (context, index) => _buildCompactTaskRow(
        tasks[index],
        isFirst: index == 0,
        isLast: index == tasks.length - 1,
      ),
    );
  }

  Widget _buildCompactTaskRow(
    TaskModel task, {
    required bool isFirst,
    required bool isLast,
  }) {
    final theme = Theme.of(context);
    final isCompleted = task.status == TaskStatus.completed;
    final isCancelled = task.status == TaskStatus.cancelled;
    final isDimmed = isCompleted || isCancelled;
    final isOverdue = task.dueDate != null &&
        task.dueDate!.isBefore(DateTime.now()) &&
        !isCompleted &&
        !isCancelled;
    final isEditingTitle = _editingTitleTaskId == task.id;
    final taskKey = task.id ?? task.title;
    final isExpanded = _session.expandedTaskKeys.contains(taskKey);
    final contextLabel = _compactTaskContext(task);
    final dueLabel = task.dueDate == null
        ? null
        : _compactDueLabel(task.dueDate!, isOverdue: isOverdue);
    final summaryLabel = [
      if (dueLabel != null) dueLabel,
      if (contextLabel.isNotEmpty) contextLabel,
    ].join(' · ');
    final radius = BorderRadius.vertical(
      top: isFirst ? const Radius.circular(14) : Radius.zero,
      bottom: isLast ? const Radius.circular(14) : Radius.zero,
    );

    return Material(
      key: ValueKey('workshop-task-compact-$taskKey'),
      color: isDimmed
          ? theme.colorScheme.surfaceContainerLowest
          : theme.colorScheme.surface,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: isLast
                ? BorderSide.none
                : BorderSide(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.38),
                  ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Semantics(
                  button: true,
                  checked: isCompleted,
                  label: isCompleted
                      ? 'Marcar ${task.title} como pendiente'
                      : 'Marcar ${task.title} como completada',
                  child: InkResponse(
                    key: ValueKey('workshop-task-compact-toggle-$taskKey'),
                    onTap: () => _toggleStatus(task),
                    radius: 24,
                    child: SizedBox(
                      width: 48,
                      height: 64,
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isCompleted
                                ? theme.colorScheme.primary
                                : Colors.transparent,
                            border: Border.all(
                              color: isCompleted
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outline,
                              width: 2,
                            ),
                          ),
                          child: isCompleted
                              ? Icon(
                                  Icons.check,
                                  size: 14,
                                  color: theme.colorScheme.onPrimary,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: isEditingTitle
                      ? Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: _buildCompactTitleEditor(task),
                        )
                      : Semantics(
                          button: true,
                          expanded: isExpanded,
                          label: isExpanded
                              ? 'Ocultar detalles de ${task.title}'
                              : 'Ver detalles de ${task.title}',
                          child: InkWell(
                            key: ValueKey(
                              'workshop-task-compact-disclosure-$taskKey',
                            ),
                            onTap: () => _toggleCompactTaskDisclosure(taskKey),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 64),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(2, 8, 10, 7),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      task.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        decoration: isCompleted
                                            ? TextDecoration.lineThrough
                                            : null,
                                        color: isDimmed
                                            ? theme.colorScheme.onSurfaceVariant
                                            : theme.colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            summaryLabel,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                              color: isOverdue
                                                  ? theme.colorScheme.error
                                                  : theme.colorScheme
                                                      .onSurfaceVariant,
                                              fontWeight: isOverdue
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          isExpanded ? 'Ocultar' : 'Detalles',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            color: theme
                                                .colorScheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Icon(
                                          isExpanded
                                              ? Icons.keyboard_arrow_up
                                              : Icons.keyboard_arrow_down,
                                          size: 18,
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
            if (isExpanded)
              _buildCompactTaskDetails(
                task,
                taskKey: taskKey,
                isOverdue: isOverdue,
              ),
          ],
        ),
      ),
    );
  }

  void _toggleCompactTaskDisclosure(String taskKey) {
    setState(() {
      if (!_session.expandedTaskKeys.remove(taskKey)) {
        _session.expandedTaskKeys.add(taskKey);
      }
    });
    _persistSession();
  }

  String _compactDueLabel(
    DateTime dueDate, {
    required bool isOverdue,
  }) {
    final today = DateUtils.dateOnly(DateTime.now());
    final due = DateUtils.dateOnly(dueDate);
    final days = due.difference(today).inDays;
    if (isOverdue) {
      return 'Vencida · ${DateFormat('dd/MM').format(due)}';
    }
    if (days == 0) return 'Hoy';
    if (days == 1) return 'Mañana';
    return DateFormat('dd/MM').format(due);
  }

  String _compactTaskContext(TaskModel task) {
    final parts = <String>[];
    if (_hasLinkedJob(task)) {
      parts.add('Trabajo ${task.linkedJobNumber}');
    } else if (task.linkedPurchaseInvoiceNumber != null) {
      parts.add('Compra ${task.linkedPurchaseInvoiceNumber}');
    } else if (task.linkedSalesInvoiceNumber != null) {
      parts.add('Venta ${task.linkedSalesInvoiceNumber}');
    }
    if (task.status != TaskStatus.pending) {
      parts.add(_translateStatus(task.status));
    }
    if (task.priority == TaskPriority.high ||
        task.priority == TaskPriority.urgent) {
      parts.add(_translatePriority(task.priority));
    }
    return parts.join(' · ');
  }

  Widget _buildCompactTaskDetails(
    TaskModel task, {
    required String taskKey,
    required bool isOverdue,
  }) {
    final theme = Theme.of(context);
    return Container(
      key: ValueKey('workshop-task-compact-details-$taskKey'),
      color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.58),
      padding: const EdgeInsets.fromLTRB(48, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (task.description?.trim().isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 8, 6),
              child: Text(
                task.description!.trim(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ),
          if (_hasLinks(task))
            Wrap(
              spacing: 14,
              runSpacing: 0,
              children: [
                if (_hasLinkedJob(task))
                  _buildCompactLink(
                    key: ValueKey('workshop-task-linked-job-$taskKey'),
                    label: 'Abrir trabajo ${task.linkedJobNumber}',
                    onTap: () => _openLinkedJob(task),
                  ),
                if (task.linkedPurchaseInvoiceNumber != null &&
                    task.linkedPurchaseInvoiceId != null)
                  _buildCompactLink(
                    key: ValueKey('workshop-task-linked-purchase-$taskKey'),
                    label: 'Abrir compra ${task.linkedPurchaseInvoiceNumber}',
                    onTap: () => context
                        .push('/purchases/${task.linkedPurchaseInvoiceId}'),
                  ),
                if (task.linkedSalesInvoiceNumber != null &&
                    task.linkedSalesInvoiceId != null)
                  _buildCompactLink(
                    key: ValueKey('workshop-task-linked-sale-$taskKey'),
                    label: 'Abrir venta ${task.linkedSalesInvoiceNumber}',
                    onTap: () => context
                        .push('/sales/invoices/${task.linkedSalesInvoiceId}'),
                  ),
              ],
            ),
          _buildCompactActionPair(
            first: Builder(
              builder: (anchorContext) => _buildCompactInfoAction(
                key: ValueKey('workshop-task-compact-status-$taskKey'),
                label: 'Estado',
                value: _translateStatus(task.status),
                indicatorColor: _statusColor(task.status),
                onTap: () => _showStatusMenu(
                  task,
                  anchorContext: anchorContext,
                ),
              ),
            ),
            second: Builder(
              builder: (anchorContext) => _buildCompactInfoAction(
                key: ValueKey('workshop-task-compact-priority-$taskKey'),
                label: 'Prioridad',
                value: _translatePriority(task.priority),
                indicatorColor: _priorityColor(task.priority),
                onTap: () => _showPriorityMenu(
                  task,
                  anchorContext: anchorContext,
                ),
              ),
            ),
          ),
          _buildCompactActionPair(
            first: _buildCompactInfoAction(
              key: ValueKey('workshop-task-compact-date-$taskKey'),
              label: isOverdue ? 'Vencida' : 'Plazo',
              value: task.dueDate == null
                  ? 'Sin fecha'
                  : DateFormat('dd/MM/yy').format(task.dueDate!),
              valueColor: isOverdue ? theme.colorScheme.error : null,
              onTap: () => _showDatePicker(task),
            ),
            second: Builder(
              builder: (anchorContext) => _buildCompactInfoAction(
                key: ValueKey('workshop-task-compact-assignee-$taskKey'),
                label: 'Asignación',
                value: _assigneeDisplayName(task) ?? 'Sin asignar',
                onTap: () => _showAssigneeMenu(
                  task,
                  anchorContext: anchorContext,
                ),
              ),
            ),
          ),
          _buildCompactActionPair(
            first: _buildCompactInfoAction(
              key: ValueKey('workshop-task-compact-attachments-$taskKey'),
              label: 'Adjuntos',
              value: task.attachments.isEmpty
                  ? 'Agregar archivos'
                  : '${task.attachments.length} archivo${task.attachments.length == 1 ? '' : 's'}',
              onTap: () => _pickFilesForTask(task),
            ),
            second: _buildCompactTaskMoreAction(task, taskKey),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactActionPair({
    required Widget first,
    required Widget second,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: 8),
        Expanded(child: second),
      ],
    );
  }

  Widget _buildCompactTaskMoreAction(TaskModel task, String taskKey) {
    final theme = Theme.of(context);
    return PopupMenuButton<String>(
      key: ValueKey('workshop-task-compact-more-$taskKey'),
      tooltip: task.kind == TaskKind.note
          ? 'Editar o archivar nota'
          : 'Editar o cancelar tarea',
      itemBuilder: (context) => _buildTaskActionMenuItems(
        context,
        isNote: task.kind == TaskKind.note,
      ),
      onSelected: (value) => _handleMenuAction(value, task),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Acciones',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      'Editar o eliminar',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.more_horiz,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactTitleEditor(TaskModel task) {
    final isSaving = _savingTitleTaskId == task.id;
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: ValueKey(
                'workshop-task-compact-title-editor-${task.id ?? task.title}'),
            controller: _titleController,
            autofocus: true,
            enabled: !isSaving,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onSubmitted: (value) => _saveTitleEdit(task, value),
          ),
        ),
        SizedBox(
          width: 48,
          height: 48,
          child: IconButton(
            key: ValueKey(
                'workshop-task-compact-title-save-${task.id ?? task.title}'),
            tooltip: 'Guardar título',
            icon: isSaving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check, size: 18),
            onPressed: isSaving
                ? null
                : () => _saveTitleEdit(task, _titleController.text),
          ),
        ),
        SizedBox(
          width: 48,
          height: 48,
          child: IconButton(
            key: ValueKey(
                'workshop-task-compact-title-cancel-${task.id ?? task.title}'),
            tooltip: 'Cancelar edición',
            icon: const Icon(Icons.close, size: 18),
            onPressed: isSaving
                ? null
                : () => setState(() => _editingTitleTaskId = null),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactInfoAction({
    required Key key,
    required String label,
    required String value,
    required VoidCallback onTap,
    Color? indicatorColor,
    Color? valueColor,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  if (indicatorColor != null) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: indicatorColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: valueColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactLink({
    required Key key,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: 'Abrir $label',
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildTaskActionMenuItems(
    BuildContext context, {
    bool isNote = false,
  }) {
    final error = Theme.of(context).colorScheme.error;
    return [
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
      PopupMenuItem(
        value: 'delete',
        child: Row(
          children: [
            Icon(isNote ? Icons.archive_outlined : Icons.delete_outline,
                size: 16, color: error),
            const SizedBox(width: 8),
            Text(isNote ? 'Archivar nota' : 'Cancelar tarea',
                style: TextStyle(color: error)),
          ],
        ),
      ),
    ];
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
                    color: isCompleted
                        ? theme.colorScheme.primary
                        : Colors.transparent,
                    border: Border.all(
                      color: isCompleted
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                      width: 2,
                    ),
                  ),
                  child: isCompleted
                      ? Icon(
                          Icons.check,
                          size: 14,
                          color: theme.colorScheme.onPrimary,
                        )
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
                      size: 18, color: theme.colorScheme.onSurfaceVariant),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  itemBuilder: (context) {
                    final error = Theme.of(context).colorScheme.error;
                    return [
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
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                                task.kind == TaskKind.note
                                    ? Icons.archive_outlined
                                    : Icons.delete_outline,
                                size: 16,
                                color: error),
                            const SizedBox(width: 8),
                            Text(
                                task.kind == TaskKind.note
                                    ? 'Archivar nota'
                                    : 'Cancelar tarea',
                                style: TextStyle(color: error)),
                          ],
                        ),
                      ),
                    ];
                  },
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
                  if (_hasLinkedJob(task))
                    _buildLinkBadge(
                      icon: Icons.build,
                      label: 'Trabajo #${task.linkedJobNumber}',
                      color: Colors.blue,
                      onTap: () => _openLinkedJob(task),
                    ),
                  if (task.linkedPurchaseInvoiceNumber != null &&
                      task.linkedPurchaseInvoiceId != null)
                    _buildLinkBadge(
                      icon: Icons.receipt,
                      label: 'Compra #${task.linkedPurchaseInvoiceNumber}',
                      color: Colors.orange,
                      onTap: () => context
                          .push('/purchases/${task.linkedPurchaseInvoiceId}'),
                    ),
                  if (task.linkedSalesInvoiceNumber != null &&
                      task.linkedSalesInvoiceId != null)
                    _buildLinkBadge(
                      icon: Icons.point_of_sale,
                      label: 'Venta #${task.linkedSalesInvoiceNumber}',
                      color: Colors.green,
                      onTap: () => context
                          .push('/sales/invoices/${task.linkedSalesInvoiceId}'),
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
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
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
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
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
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    final assigneeName = _assigneeDisplayName(task);
    return InkWell(
      onTap: () => _showAssigneeMenu(task),
      borderRadius: BorderRadius.circular(6),
      child: assigneeName != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    assigneeName.substring(0, 1).toUpperCase(),
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
                    assigneeName,
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

  Future<void> _saveTitleEdit(TaskModel task, String newTitle) async {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty || trimmed == task.title) {
      setState(() => _editingTitleTaskId = null);
      return;
    }

    setState(() => _savingTitleTaskId = task.id);
    final saved = await _updateTask(task.copyWith(title: trimmed));
    if (!mounted) return;

    setState(() {
      _savingTitleTaskId = null;
      if (saved) {
        _editingTitleTaskId = null;
      }
    });
  }

  void _showStatusMenu(
    TaskModel task, {
    BuildContext? anchorContext,
  }) {
    final menuContext = anchorContext ?? context;
    final RenderBox button = menuContext.findRenderObject() as RenderBox;
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

  void _showPriorityMenu(
    TaskModel task, {
    BuildContext? anchorContext,
  }) {
    final menuContext = anchorContext ?? context;
    final RenderBox button = menuContext.findRenderObject() as RenderBox;
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
        // Limpiar la fecha va por el mismo comando auditado que el resto.
        if (task.id != null && mounted) {
          final messenger = ScaffoldMessenger.of(context);
          final service = context.read<TaskService>();
          try {
            await service.updateTaskDetails(task.id!, clearDueDate: true);
          } catch (e) {
            if (mounted) {
              messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
            }
          }
        }
      }
      return;
    }

    if (picked != null) {
      await _updateTask(task.copyWith(dueDate: picked));
    }
  }

  void _showAssigneeMenu(
    TaskModel task, {
    BuildContext? anchorContext,
  }) {
    // Una nota no tiene responsable; el servidor lo rechaza y la UI no lo
    // ofrece.
    if (task.kind == TaskKind.note) return;
    final menuContext = anchorContext ?? context;
    final RenderBox button = menuContext.findRenderObject() as RenderBox;
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

    final taskServiceForAssign = context.read<TaskService>();
    final messengerForAssign = ScaffoldMessenger.of(context);
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
        if (task.id != null) {
          taskServiceForAssign.assignTask(task.id!, null).catchError(
            (Object error) {
              if (mounted) {
                messengerForAssign
                    .showSnackBar(SnackBar(content: Text('Error: $error')));
              }
              return task;
            },
          );
        }
        return;
      }

      // Find user name
      final user = _users?.firstWhere(
          (u) => u['user_id']?.toString() == selectedUserId,
          orElse: () => {});
      final name =
          user?['full_name'] as String? ?? user?['email'] as String? ?? '';

      if (task.id != null) {
        final service = taskServiceForAssign;
        final messenger = messengerForAssign;
        service.assignTask(task.id!, selectedUserId).catchError((Object error) {
          if (mounted) {
            messenger.showSnackBar(SnackBar(content: Text('Error: $error')));
          }
          return task.copyWith(assigneeName: name);
        });
      }
    });
  }

  // ══════════════════════════════════════════════════════════════════
  // ACTIONS
  // ══════════════════════════════════════════════════════════════════

  void _toggleStatus(TaskModel task) {
    if (task.id == null) return;
    final service = context.read<TaskService>();
    final messenger = ScaffoldMessenger.of(context);
    // Una nota no se completa: su ida y vuelta es Archivar/Restaurar.
    final future = task.kind == TaskKind.note
        ? (task.isDone
            ? service.reopenTask(task.id!)
            : service.cancelTask(task.id!))
        : task.status == TaskStatus.completed
            ? service.reopenTask(task.id!)
            : service.completeTask(task.id!);
    future.catchError((Object error) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Error: $error')));
      }
      return task;
    });
  }

  Future<bool> _updateTask(TaskModel updatedTask) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<TaskService>().updateTask(updatedTask);
      return true;
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      return false;
    }
  }

  /// Update a single field directly (for nullable fields like due_date)
  void _handleMenuAction(String value, TaskModel task) async {
    if (value == 'edit') {
      showDialog(
        context: context,
        builder: (context) => TaskFormDialog(taskToEdit: task),
      );
      return;
    }

    if (value == 'delete') {
      final isNote = task.kind == TaskKind.note;
      final messenger = ScaffoldMessenger.of(context);
      final taskService = context.read<TaskService>();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(isNote ? 'Archivar nota' : 'Cancelar tarea'),
          content: Text(isNote
              ? '¿Archivar "${task.title}"? Podrás restaurarla cuando '
                  'quieras.'
              : '¿Cancelar "${task.title}"? Su historial se '
                  'conserva y puede reabrirse.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Volver'),
            ),
            FilledButton(
              style: isNote
                  ? null
                  : FilledButton.styleFrom(
                      backgroundColor: Theme.of(ctx).colorScheme.error,
                    ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(isNote ? 'Archivar nota' : 'Cancelar tarea'),
            ),
          ],
        ),
      );

      if (confirmed == true && task.id != null) {
        try {
          await taskService.cancelTask(task.id!);
          if (mounted) {
            messenger.showSnackBar(SnackBar(
                content: Text(isNote ? 'Nota archivada' : 'Tarea cancelada')));
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
    return _hasLinkedJob(task) ||
        (task.linkedPurchaseInvoiceNumber != null &&
            task.linkedPurchaseInvoiceId != null) ||
        (task.linkedSalesInvoiceNumber != null &&
            task.linkedSalesInvoiceId != null);
  }

  bool _hasLinkedJob(TaskModel task) {
    return task.linkedJobNumber != null &&
        task.linkedJobId != null &&
        task.linkedJobId!.trim().isNotEmpty;
  }

  Future<void> _openLinkedJob(TaskModel task) async {
    final jobId = task.linkedJobId?.trim();
    if (jobId == null || jobId.isEmpty) return;
    await context.push('/taller/pegas/${Uri.encodeComponent(jobId)}');
  }

  // ══════════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════════

  Color _statusColor(TaskStatus status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case TaskStatus.pending:
        return scheme.onSurfaceVariant;
      case TaskStatus.inProgress:
        return scheme.primary;
      case TaskStatus.blocked:
        return scheme.error;
      case TaskStatus.completed:
        return scheme.tertiary;
      case TaskStatus.cancelled:
        return scheme.outline;
    }
  }

  Color _priorityColor(TaskPriority priority) {
    final scheme = Theme.of(context).colorScheme;
    switch (priority) {
      case TaskPriority.urgent:
        return scheme.error;
      case TaskPriority.high:
        return scheme.tertiary;
      case TaskPriority.normal:
        return scheme.onSurfaceVariant;
      case TaskPriority.low:
        return scheme.outline;
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
      case TaskStatus.blocked:
        return 'Bloqueada';
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
