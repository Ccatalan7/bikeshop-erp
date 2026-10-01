import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/bikeshop_models.dart';
import '../services/bike_product_compatibility_service.dart';
import '../services/smart_task_service.dart';
import '../services/bikeshop_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/widgets/product_autocomplete_field.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/models/product.dart';
import '../../../shared/models/product_compatibility.dart';
import '../../../shared/themes/vinabike_theme_roles.dart';
import 'job_line_instructions.dart';

/// Pestaña Tareas del trabajo: por cada línea, su instrucción y sus tareas.
///
/// - **Instrucción** ([JobLineInstructions]): qué incluye el servicio (su
///   descripción del catálogo, la que ve el cliente) y las indicaciones de este
///   trabajo. Se lee; no tiene casillas.
/// - **Tareas**: lo accionable, con casilla y avance. Las crea una persona, en
///   la línea o sueltas; una con cobro crea su línea (`sync_adhoc_task_to_item`).
///   Desde 2026-09-29 ninguna nace de la descripción (20260929040000).
class TasksTabView extends StatefulWidget {
  final String jobId;
  final bool readOnly;
  final Function(MechanicJobItem)? onItemAdded;
  final Function(String itemId)? onItemRemoved;
  final VoidCallback? onAddItemPressed;
  final List<MechanicJobItem>? externalItems;

  const TasksTabView({
    super.key,
    required this.jobId,
    this.readOnly = false,
    this.onItemAdded,
    this.onItemRemoved,
    this.onAddItemPressed,
    this.externalItems,
  });

  @override
  State<TasksTabView> createState() => _TasksTabViewState();
}

class _TasksTabViewState extends State<TasksTabView> {
  SmartTaskService? _taskService;
  BikeshopService? _bikeshopService;
  TenantService? _tenantService;
  final _bikeProductCompatibilityService = BikeProductCompatibilityService();
  Map<String, List<MechanicJobTask>> _groupedTasks = {};
  List<MechanicJobItem> _items = [];

  /// La descripción del catálogo de cada servicio de las líneas, por id.
  Map<String, String> _catalogDescriptions = {};
  TaskProgress? _progress;
  bool _isLoading = true;
  final Set<String> _collapsedItems = {}; // Track collapsed parent items
  String? _editingTaskId; // Track which task is being edited inline
  Bike? _compatibilityBike;
  BikeProfile? _compatibilityBikeProfile;
  bool _compatibilityContextResolved = false;

  @override
  void initState() {
    super.initState();
    if (widget.externalItems != null) {
      _items = widget.externalItems!;
    }
  }

  @override
  void didUpdateWidget(TasksTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.externalItems != oldWidget.externalItems &&
        widget.externalItems != null) {
      setState(() {
        _items = widget.externalItems!;
        // Re-group tasks since items changed (tasks might need re-linking if logic depended on items, but mainly purely display)
        // Actually, we should probably re-load tasks if items changed significantly, OR assume checking tasks is separate.
        // For now, update items list.
      });
      // Also reload tasks/progress to be safe as they depend on items
      _loadTasks(onlyNonItems: true);
    }

    if (widget.jobId != oldWidget.jobId) {
      _resetCompatibilityContext();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_taskService == null) {
      _taskService = context.read<SmartTaskService>();
      _bikeshopService = context.read<BikeshopService>();
      _tenantService = context.read<TenantService>();

      // Listen to task service changes for realtime updates
      _taskService!.addListener(_onTasksChanged);

      _loadTasks();
    }
  }

  @override
  void dispose() {
    _taskService?.removeListener(_onTasksChanged);
    super.dispose();
  }

  void _onTasksChanged() {
    // Don't reload on every change - only reload if we need to sync external changes
    // For checkbox toggles, we use optimistic updates instead
  }

  void _resetCompatibilityContext() {
    _compatibilityBike = null;
    _compatibilityBikeProfile = null;
    _compatibilityContextResolved = false;
  }

  Object? get _compatibilityContextKey {
    final bike = _compatibilityBike;
    final profile = _compatibilityBikeProfile;
    if (bike == null || profile == null) {
      return null;
    }

    final technicalValues = profile.technicalValues;
    return [
      profile.bikeId,
      profile.updatedAt.toIso8601String(),
      bike.updatedAt.toIso8601String(),
      bike.bikeType?.dbValue ?? '',
      bike.wheelSize ?? '',
      bike.frontHubSpacingMm?.toString() ?? '',
      bike.rearHubSpacingMm?.toString() ?? '',
      technicalValues['brakeType']?.toString() ?? '',
      technicalValues['rimBrakeFamily']?.toString() ?? '',
      technicalValues['frontRotorSizeMm']?.toString() ?? '',
      technicalValues['rearRotorSizeMm']?.toString() ?? '',
      technicalValues['drivetrainConfig']?.toString() ?? '',
      technicalValues['drivetrainSpeeds']?.toString() ?? '',
      technicalValues['freehubType']?.toString() ?? '',
      technicalValues['frontSpokeHoles']?.toString() ?? '',
      technicalValues['rearSpokeHoles']?.toString() ?? '',
      technicalValues['valveType']?.toString() ?? '',
      technicalValues['bottomBracketFamily']?.toString() ?? '',
    ].join('|');
  }

  Future<void> _ensureCompatibilityContext({bool forceRefresh = false}) async {
    if (_bikeshopService == null) {
      return;
    }
    if (!forceRefresh && _compatibilityContextResolved) {
      return;
    }

    _compatibilityContextResolved = true;

    try {
      final bikeshopService = _bikeshopService!;
      final job = await bikeshopService.getJobById(widget.jobId);

      Bike? bike;
      String? bikeId = job?.bikeId;

      if (bikeId == null || bikeId.isEmpty) {
        final jobBikes = await bikeshopService.getJobBikes(widget.jobId);
        final primaryJobBike = jobBikes.isNotEmpty ? jobBikes.first : null;
        bikeId = primaryJobBike?.bikeId;
        bike = primaryJobBike?.bike;
      }

      if (bikeId == null || bikeId.isEmpty) {
        if (mounted) {
          setState(() {
            _compatibilityBike = null;
            _compatibilityBikeProfile = null;
          });
        }
        return;
      }

      bike ??= await bikeshopService.getBikeById(bikeId);
      final profile = await bikeshopService.getBikeProfile(bikeId);

      if (!mounted) {
        return;
      }

      setState(() {
        _compatibilityBike = bike;
        _compatibilityBikeProfile = profile;
      });
    } catch (e) {
      debugPrint('⚠️ Failed to resolve task-tab compatibility context: $e');
      if (mounted) {
        setState(() {
          _compatibilityBike = null;
          _compatibilityBikeProfile = null;
        });
      }
    }
  }

  Future<Map<String, ProductCompatibilityAssessment>>
      _resolveCurrentBikeCompatibility(List<Product> products) async {
    await _ensureCompatibilityContext();

    final bike = _compatibilityBike;
    final profile = _compatibilityBikeProfile;
    if (bike == null || profile == null) {
      return const {};
    }

    return _bikeProductCompatibilityService.buildAutocompleteAssessments(
      bike: bike,
      profile: profile,
      products: products,
    );
  }

  Future<void> _loadTasks({bool onlyNonItems = false}) async {
    if (!mounted || _taskService == null) return;

    // If we haven't loaded initial items and no external items, show loading
    if (_items.isEmpty && widget.externalItems == null && !onlyNonItems) {
      setState(() => _isLoading = true);
    }

    try {
      // Fetch tasks, grouped tasks, progress
      final results = await Future.wait([
        _taskService!.getTasksForJob(widget.jobId),
        _taskService!.getTasksGroupedByParent(widget.jobId),
        _taskService!.calculateProgress(widget.jobId),
        // Only fetch items if not provided externally
        if (widget.externalItems == null && !onlyNonItems)
          _fetchItems()
        else
          Future.value(<MechanicJobItem>[]),
      ]);

      final items = widget.externalItems == null && !onlyNonItems
          ? results[3] as List<MechanicJobItem>
          : _items;
      final descriptions = await _fetchCatalogDescriptions(items);

      if (mounted) {
        setState(() {
          _groupedTasks = results[1] as Map<String, List<MechanicJobTask>>;
          _progress = results[2] as TaskProgress?;
          if (widget.externalItems == null && !onlyNonItems) {
            _items = items;
          }
          _catalogDescriptions = descriptions;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Failed to load tasks: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<List<MechanicJobItem>> _fetchItems() async {
    try {
      final tenantId = await _tenantService?.getTenantId();
      if (tenantId == null) return [];
      final data = await Supabase.instance.client
          .from('mechanic_job_items')
          .select()
          .eq('tenant_id', tenantId)
          .eq('job_id', widget.jobId)
          .order('created_at', ascending: true);

      return (data as List)
          .map((json) => MechanicJobItem.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('❌ Failed to fetch items: $e');
      return [];
    }
  }

  /// El servicio del catálogo de una línea, si es un servicio.
  static String? _catalogServiceId(MechanicJobItem item) =>
      item.serviceProductId ??
      (item.itemType == 'service' ? item.productId : null);

  /// Las descripciones del catálogo de los servicios de [items]: son la
  /// instrucción de cada línea. Los repuestos no la muestran (su descripción
  /// es de venta: «+ Instalación en $45.000»).
  Future<Map<String, String>> _fetchCatalogDescriptions(
    List<MechanicJobItem> items,
  ) async {
    final ids = {
      for (final item in items)
        if (_catalogServiceId(item) case final id?) id,
    };
    if (ids.isEmpty) return const {};
    try {
      final tenantId = await _tenantService?.getTenantId();
      if (tenantId == null) return const {};
      final data = await Supabase.instance.client
          .from('products')
          .select('id, description')
          .eq('tenant_id', tenantId)
          .inFilter('id', ids.toList());
      return {
        for (final row in data as List)
          if ((row['description'] as String?)?.trim().isNotEmpty == true)
            row['id'] as String: row['description'] as String,
      };
    } catch (e) {
      debugPrint('❌ Failed to fetch catalog descriptions: $e');
      return const {};
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header with progress
        _buildHeader(),

        const Divider(height: 1),

        // Task list
        Expanded(
          child: _isLoading
              ? const Center(child: BrandedLoading())
              : _buildTaskList(),
        ),

        // Footer with overall progress
        if (_progress != null && _progress!.totalTasks > 0)
          _buildProgressFooter(),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.checklist, size: 24),
          const SizedBox(width: 12),
          const Text(
            'Tareas',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (_progress != null && _progress!.totalTasks > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _progressTone(_progress!.isDone).container,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_progress!.completedTasks}/${_progress!.totalTasks}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _progressTone(_progress!.isDone).onContainer,
                ),
              ),
            ),
          if (!widget.readOnly) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Agregar artículo',
              onPressed: _showAddItemDialog,
              iconSize: 20,
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.add_task),
              tooltip: 'Agregar tarea independiente',
              onPressed: _showAddStandaloneTaskDialog,
              iconSize: 20,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTaskList() {
    // Sin líneas, una tarea suelta igual se ve: se puede agregar desde el
    // encabezado (revisión de Codex, 2026-09-29).
    final standalone = _groupedTasks['standalone'] ?? const <MechanicJobTask>[];
    if (_items.isEmpty && standalone.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.checklist_outlined,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'Este trabajo todavía no tiene líneas',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Agrega un servicio para ver qué incluye y anotar sus tareas',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ..._items
            .where((item) => !item.productName.startsWith('Ad-hoc: '))
            .map((item) => _buildItemGroup(item)),
        if (standalone.isNotEmpty) _buildStandaloneTasksGroup(standalone),
      ],
    );
  }

  /// Build item (product) group with parent checkbox and sub-tasks
  Widget _buildItemGroup(MechanicJobItem item) {
    final subTasks = _groupedTasks['item_${item.id}'] ?? [];
    final sortedTasks = List<MechanicJobTask>.from(subTasks)
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    final instructions = JobLineInstructions(
      catalogDescription: switch (_catalogServiceId(item)) {
        final id? => _catalogDescriptions[id],
        null => null,
      },
      notes: item.notes,
    );

    final completionStatus = _getCompletionStatus(sortedTasks);
    final isCollapsed = _collapsedItems.contains('item_${item.id}');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: _getGroupBackgroundColor(completionStatus),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Parent item header
          _buildItemHeader(
            item,
            sortedTasks,
            completionStatus,
            collapsible: sortedTasks.isNotEmpty || !instructions.isEmpty,
          ),

          // La instrucción de la línea: se lee, no se marca.
          if (!instructions.isEmpty && !isCollapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 10, 12, 4),
              child: instructions,
            ),

          // Sub-tasks (if any and not collapsed)
          if (sortedTasks.isNotEmpty && !isCollapsed)
            ...sortedTasks.map((task) => Padding(
                  padding: const EdgeInsets.only(left: 32),
                  child: _buildTaskItem(task),
                )),

          // Add sub-task button
          if (!widget.readOnly && item.id != null && !isCollapsed)
            Padding(
              padding: const EdgeInsets.only(left: 32, bottom: 8),
              child: _buildAddSubTaskButton(
                parentId: item.id!,
              ),
            ),
        ],
      ),
    );
  }

  /// Build standalone tasks group
  Widget _buildStandaloneTasksGroup(List<MechanicJobTask> tasks) {
    if (tasks.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.task_alt, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tareas del trabajo',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...tasks.map((task) => _buildTaskItem(task)),
        ],
      ),
    );
  }

  /// Build item (product) header with checkbox
  Widget _buildItemHeader(
    MechanicJobItem item,
    List<MechanicJobTask> subTasks,
    ParentCompletionStatus? status, {
    required bool collapsible,
  }) {
    final completed = subTasks.where((t) => t.isCompleted).length;
    final total = subTasks.length;
    final isCollapsed = _collapsedItems.contains('item_${item.id}');

    // Determine checkbox state:
    // - No subtasks: unchecked (will create a task when checked)
    // - All subtasks complete: checked
    // - Some subtasks complete: indeterminate (tristate)
    // - No subtasks complete: unchecked
    final bool? checkboxValue;
    if (total == 0) {
      checkboxValue = false; // No subtasks - unchecked by default
    } else if (completed == total) {
      checkboxValue = true; // All done
    } else if (completed > 0) {
      checkboxValue = null; // Some done - indeterminate
    } else {
      checkboxValue = false; // None done
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          // Checkbox for item completion
          Checkbox(
            value: checkboxValue,
            tristate: total > 0, // Only tristate if has subtasks
            onChanged: widget.readOnly
                ? null
                : (value) =>
                    _toggleItemCompletion(item, subTasks, value ?? true),
          ),

          // Plegar la instrucción y las tareas de la línea.
          if (collapsible)
            IconButton(
              tooltip: isCollapsed ? 'Mostrar' : 'Plegar',
              icon: Icon(
                isCollapsed ? Icons.chevron_right : Icons.expand_more,
                size: 20,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                setState(() {
                  if (isCollapsed) {
                    _collapsedItems.remove('item_${item.id}');
                  } else {
                    _collapsedItems.add('item_${item.id}');
                  }
                });
              },
            ),

          const SizedBox(width: 8),

          // Item icon
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.shopping_cart, size: 18),
          ),
          const SizedBox(width: 12),

          // Product name (clickable for inline edit)
          Expanded(
            child: InkWell(
              onTap:
                  widget.readOnly ? null : () => _showEditProductDialog(item),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Cant. ${item.quantity.toStringAsFixed(0)} • \$${item.unitPrice.toStringAsFixed(0)} • Total \$${item.totalPrice.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (total > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getStatusBadgeColor(status),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                status?.isAllCompleted == true
                    ? '\u2713 $completed/$total'
                    : '\u23f3 $completed/$total',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          if (!widget.readOnly) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              tooltip: 'Quitar del trabajo',
              onPressed: () => _confirmRemoveItem(item),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ],
      ),
    );
  }

  /// Build service header with pricing summary
  Widget _buildTaskItem(MechanicJobTask task) {
    final isEditing = _editingTaskId == task.id;

    if (isEditing) {
      // Inline edit mode
      final controller = TextEditingController(text: task.taskName);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Checkbox (disabled during edit)
            Checkbox(
              value: task.isCompleted,
              onChanged: null,
            ),
            const SizedBox(width: 12),

            // Inline text field
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (newName) async {
                  if (newName.trim().isNotEmpty && newName != task.taskName) {
                    await _updateTaskName(task, newName.trim());
                  }
                  setState(() => _editingTaskId = null);
                },
              ),
            ),

            // Cancel button
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() => _editingTaskId = null),
              tooltip: 'Cancelar',
            ),
          ],
        ),
      );
    }

    // Normal display mode
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Checkbox
          Checkbox(
            value: task.isCompleted,
            onChanged: widget.readOnly
                ? null
                : (value) => _toggleTaskCompletion(task, value ?? false),
          ),
          const SizedBox(width: 12),

          // El nombre se edita tocándolo.
          Expanded(
            child: InkWell(
              onTap: widget.readOnly
                  ? null
                  : () {
                      setState(() => _editingTaskId = task.id);
                    },
              child: Text(
                task.taskName,
                style: TextStyle(
                  fontSize: 14,
                  decoration:
                      task.isCompleted ? TextDecoration.lineThrough : null,
                  color: task.isCompleted ? Colors.grey.shade600 : null,
                ),
              ),
            ),
          ),

          // Ad-hoc price badge
          if (task.isAdhoc && task.adhocPrice != null)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '\$${task.adhocPrice!.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue.shade700,
                ),
              ),
            ),

          if (!widget.readOnly)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              iconSize: 18,
              tooltip: 'Eliminar tarea',
              onPressed: () => _deleteTask(task),
            ),
        ],
      ),
    );
  }

  Widget _buildAddSubTaskButton({
    required String parentId,
  }) {
    return TextButton.icon(
      onPressed: () => _showAddSubTaskDialog(
        parentId: parentId,
      ),
      icon: const Icon(Icons.add, size: 16),
      label: const Text('Agregar tarea'),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }

  Widget _buildProgressFooter() {
    final percentage = _progress!.percentage;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Avance de las tareas',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${percentage.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: percentage == 100
                      ? Colors.green.shade700
                      : Colors.orange.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percentage / 100,
              minHeight: 8,
              backgroundColor: Colors.grey.shade300,
              valueColor: AlwaysStoppedAnimation<Color>(
                percentage == 100 ? Colors.green : Colors.orange,
              ),
            ),
          ),
          if (_progress!.totalAdHocPrice > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Tareas con cobro: \$${_progress!.totalAdHocPrice.toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Helper methods
  ParentCompletionStatus _getCompletionStatus(List<MechanicJobTask> tasks) {
    final completed = tasks.where((t) => t.isCompleted).length;
    final total = tasks.length;

    return ParentCompletionStatus(
      totalTasks: total,
      completedTasks: completed,
      // Sin tareas no hay nada hecho: la línea no se pinta como terminada.
      isAllCompleted: total > 0 && completed == total,
      isInProgress: completed > 0 && completed < total,
      isNotStarted: completed == 0,
    );
  }

  /// Terminadas: el tono de éxito; con algo pendiente: el de atención. Por
  /// los roles del tema, para que el oscuro se lea (los `shade50` fijos
  /// pintaban la línea blanca en oscuro).
  VinabikeSemanticTone _progressTone(bool done) {
    final roles = VinabikeThemeRoles.of(context);
    return done ? roles.success : roles.warning;
  }

  Color _getGroupBackgroundColor(ParentCompletionStatus? status) {
    final scheme = Theme.of(context).colorScheme;
    if (status == null || status.isNotStarted) {
      return scheme.surfaceContainerLow;
    }
    return _progressTone(status.isAllCompleted).container;
  }

  Color _getStatusBadgeColor(ParentCompletionStatus? status) {
    if (status == null) return Colors.grey;

    if (status.isAllCompleted) {
      return Colors.green;
    } else if (status.isInProgress) {
      return Colors.orange;
    } else {
      return Colors.grey;
    }
  }

  // Actions
  void _showAddItemDialog() async {
    if (widget.onAddItemPressed != null) {
      // If parent provides a callback, use it
      widget.onAddItemPressed!();
      return;
    }

    await _ensureCompatibilityContext();

    // Otherwise, show our own dialog
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar al trabajo'),
        content: SizedBox(
          width: 500,
          child: ProductAutocompleteField(
            onProductSelected: (selection) async {
              Navigator.pop(context);
              if (!selection.isCatalogProduct || selection.product == null) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Solo se pueden agregar artículos del catálogo desde esta vista'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
                return;
              }

              await _addCatalogItem(selection.product!);
            },
            allowCustomItems: false,
            labelText: 'Servicio o repuesto',
            hintText: 'Buscar en el catálogo por nombre o SKU',
            autoFocus: true,
            compatibilityContextKey: _compatibilityContextKey,
            compatibilityResolver: _compatibilityContextKey == null
                ? null
                : _resolveCurrentBikeCompatibility,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Future<void> _addCatalogItem(Product product) async {
    try {
      if (_tenantService == null || _bikeshopService == null) {
        throw Exception('Services not initialized');
      }
      final tenantId = await _tenantService!.getTenantId();
      if (tenantId == null) throw Exception('No tenant ID');

      // ⚠️ CRITICAL: Verify product has ID
      if (product.id.isEmpty) {
        throw Exception('Product must have an ID to link to catalog');
      }

      debugPrint('📦 Adding catalog item: ${product.name} (ID: ${product.id})');
      debugPrint('📦 FULL PRODUCT DATA:');
      debugPrint('  - ID: ${product.id}');
      debugPrint('  - Name: ${product.name}');
      debugPrint('  - SKU: ${product.sku}');
      debugPrint('  - Description: "${product.description}"');
      debugPrint('  - Description null?: ${product.description == null}');
      debugPrint(
          '  - Description empty?: ${product.description?.isEmpty ?? true}');

      final item = MechanicJobItem(
        tenantId: tenantId,
        jobId: widget.jobId,
        productId: product.id,
        productName: product.name,
        productSku: product.sku,
        quantity: 1,
        unitPrice: product.price,
        totalPrice: product.price,
      );

      final created = await _bikeshopService!.createJobItem(item);

      // La línea nueva no trae tareas: su descripción del catálogo se muestra
      // como instrucción (20260929040000).
      if (widget.onItemAdded != null) {
        widget.onItemAdded!(created);
      }

      await _loadTasks();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Agregado: ${created.productName}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Toggle item completion - handles both items with and without subtasks
  Future<void> _toggleItemCompletion(
    MechanicJobItem item,
    List<MechanicJobTask> subTasks,
    bool markComplete,
  ) async {
    if (_taskService == null || item.id == null) return;

    try {
      if (subTasks.isEmpty) {
        // No subtasks - create a simple completion marker (not a duplicate of the item name)
        final tenantId = await _tenantService?.getTenantId();
        if (tenantId == null) return;

        // Create a completion marker task with a generic name
        final task = MechanicJobTask(
          tenantId: tenantId,
          jobId: widget.jobId,
          parentItemId: item.id!,
          taskName:
              'Completado', // Generic completion marker, not the item name
          isCompleted: markComplete,
          parsedFromDescription: false,
          isAdhoc: false,
        );

        await _taskService!.createTask(task);
        await _loadTasks(); // Reload to show the new task
      } else {
        // Has subtasks - toggle all of them
        // Optimistic update
        setState(() {
          for (var task in subTasks) {
            final index = _groupedTasks['item_${item.id}']
                    ?.indexWhere((t) => t.id == task.id) ??
                -1;
            if (index != -1) {
              _groupedTasks['item_${item.id}']![index] =
                  task.copyWith(isCompleted: markComplete);
            }
          }
        });

        // Update all subtasks in database
        for (var task in subTasks) {
          if (task.id != null && task.isCompleted != markComplete) {
            await _taskService!.toggleTaskCompletion(task.id!, markComplete);
          }
        }
      }

      // Refresh progress
      final progress = await _taskService!.calculateProgress(widget.jobId);
      if (mounted) {
        setState(() {
          _progress = progress;
        });
      }
    } catch (e) {
      // Reload on error to revert
      await _loadTasks();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _toggleTaskCompletion(
      MechanicJobTask task, bool isCompleted) async {
    if (_taskService == null) return;

    // Optimistic update - update UI immediately
    setState(() {
      // Find and update the task in our local state
      for (var group in _groupedTasks.values) {
        final index = group.indexWhere((t) => t.id == task.id);
        if (index != -1) {
          group[index] = task.copyWith(isCompleted: isCompleted);
          break;
        }
      }
    });

    try {
      // Update in database (SmartTaskService will handle notifyListeners)
      await _taskService!.toggleTaskCompletion(task.id!, isCompleted);
    } catch (e) {
      // Revert on error
      setState(() {
        for (var group in _groupedTasks.values) {
          final index = group.indexWhere((t) => t.id == task.id);
          if (index != -1) {
            group[index] = task.copyWith(isCompleted: !isCompleted);
            break;
          }
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo actualizar la tarea: $e')),
        );
      }
    }
  }

  Future<void> _deleteTask(MechanicJobTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar tarea'),
        content: Text('¿Eliminar «${task.taskName}»?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (_taskService == null) return;
      try {
        await _taskService!.deleteTask(task.id!);
        _loadTasks();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo eliminar la tarea: $e')),
          );
        }
      }
    }
  }

  // ============================================================
  // ADD/REMOVE PRODUCTS AND SERVICES
  // ============================================================

  Future<void> _confirmRemoveItem(MechanicJobItem item) async {
    if (widget.onItemRemoved == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quitar del trabajo'),
        content: Text('¿Quitar «${item.productName}» de este trabajo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );

    if (confirmed == true && item.id != null) {
      widget.onItemRemoved!(item.id!);
      _loadTasks(); // Refresh view
    }
  }

  void _showAddStandaloneTaskDialog() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final priceController = TextEditingController(text: '0');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tarea del trabajo'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Qué hay que hacer',
                  border: OutlineInputBorder(),
                  hintText: 'Ej.: prueba de ruta, avisar al cliente',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Detalle (opcional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceController,
                decoration: const InputDecoration(
                  labelText: 'Cobro (opcional)',
                  border: OutlineInputBorder(),
                  prefixText: '\$',
                  hintText: '0 si no se cobra',
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Agregar'),
          ),
        ],
      ),
    );

    if (result == true && nameController.text.isNotEmpty) {
      try {
        if (_tenantService == null || _taskService == null) {
          throw Exception('Services not initialized');
        }
        final tenantId = await _tenantService!.getTenantId();
        if (tenantId == null) throw Exception('No tenant ID');

        final price = double.tryParse(priceController.text) ?? 0;

        final task = MechanicJobTask(
          tenantId: tenantId,
          jobId: widget.jobId,
          taskName: nameController.text,
          taskDescription: descriptionController.text.isNotEmpty
              ? descriptionController.text
              : null,
          isStandalone: true,
          displayOrder: 0,
          isCompleted: false,
          isAdhoc: price > 0,
          adhocPrice: price > 0 ? price : null,
        );

        await _taskService!.createTask(task);
        await _loadTasks();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tarea agregada')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo agregar la tarea: $e')),
          );
        }
      }
    }
  }

  void _showAddSubTaskDialog({
    required String parentId,
  }) async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final priceController = TextEditingController(text: '0');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tarea de esta línea'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Qué hay que hacer',
                  border: OutlineInputBorder(),
                  hintText: 'Ej.: revisar juego del eje',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Detalle (opcional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceController,
                decoration: const InputDecoration(
                  labelText: 'Cobro adicional (opcional)',
                  border: OutlineInputBorder(),
                  prefixText: '\$',
                  hintText: '0 si no se cobra aparte',
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Agregar'),
          ),
        ],
      ),
    );

    if (result == true && nameController.text.isNotEmpty) {
      try {
        if (_tenantService == null || _taskService == null) {
          throw Exception('Services not initialized');
        }
        final tenantId = await _tenantService!.getTenantId();
        if (tenantId == null) throw Exception('No tenant ID');

        final price = double.tryParse(priceController.text) ?? 0;

        final task = MechanicJobTask(
          tenantId: tenantId,
          jobId: widget.jobId,
          taskName: nameController.text,
          taskDescription: descriptionController.text.isNotEmpty
              ? descriptionController.text
              : null,
          isStandalone: false,
          parentItemId: parentId,
          displayOrder: 0,
          isCompleted: false,
          isAdhoc: price > 0,
          adhocPrice: price > 0 ? price : null,
        );

        debugPrint('🔵 [TasksTabView] Creating subtask: ${task.taskName}');
        await _taskService!.createTask(task);
        debugPrint('🔵 [TasksTabView] Subtask created, calling _loadTasks()');
        await _loadTasks();
        debugPrint('🔵 [TasksTabView] _loadTasks() completed');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tarea agregada')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo agregar la tarea: $e')),
          );
        }
      }
    }
  }

  // ============================================================
  // INLINE EDITING
  // ============================================================

  Future<void> _updateTaskName(MechanicJobTask task, String newName) async {
    if (_taskService == null || task.id == null) return;

    try {
      await Supabase.instance.client
          .from('mechanic_job_tasks')
          .update({'task_name': newName})
          .eq('tenant_id', task.tenantId)
          .eq('id', task.id!);

      await _loadTasks();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tarea actualizada')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo actualizar la tarea: $e')),
        );
      }
    }
  }

  void _showEditProductDialog(MechanicJobItem item) async {
    await _ensureCompatibilityContext();

    ProductSelection? selectedProduct = ProductSelection(
      isCatalogProduct: item.productId != null,
      product: null,
      displayText: item.productName,
      customDescription: item.notes,
    );
    double quantity = item.quantity;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cambiar la línea'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ProductAutocompleteField(
                onProductSelected: (selection) {
                  selectedProduct = selection;
                },
                allowCustomItems: true,
                labelText: 'Servicio o repuesto',
                hintText: 'Busca en el catálogo o escribe uno',
                autoFocus: true,
                initialValue: item.productName,
                compatibilityContextKey: _compatibilityContextKey,
                compatibilityResolver: _compatibilityContextKey == null
                    ? null
                    : _resolveCurrentBikeCompatibility,
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Cantidad',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  quantity = double.tryParse(value) ?? item.quantity;
                },
                controller:
                    TextEditingController(text: item.quantity.toString()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result == true && selectedProduct != null && item.id != null) {
      try {
        final product = selectedProduct!.product;
        final updates = {
          'product_id': product?.id,
          'product_name': selectedProduct!.displayText,
          'product_sku': product?.sku,
          'quantity': quantity,
          'unit_price': product?.price ?? item.unitPrice,
          'total_price': (product?.price ?? item.unitPrice) * quantity,
          'notes': selectedProduct!.customDescription,
        };

        await Supabase.instance.client
            .from('mechanic_job_items')
            .update(updates)
            .eq('tenant_id', item.tenantId)
            .eq('id', item.id!);

        await _loadTasks();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Línea actualizada')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo cambiar la línea: $e')),
          );
        }
      }
    }
  }
}

class ParentCompletionStatus {
  final int totalTasks;
  final int completedTasks;
  final bool isAllCompleted;
  final bool isInProgress;
  final bool isNotStarted;

  ParentCompletionStatus({
    required this.totalTasks,
    required this.completedTasks,
    required this.isAllCompleted,
    required this.isInProgress,
    required this.isNotStarted,
  });
}
