import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/bikeshop_models.dart';
import '../services/smart_task_service.dart';
import '../services/bikeshop_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/widgets/product_autocomplete_field.dart';
import '../../../shared/models/product.dart';
import '../../../shared/widgets/product_autocomplete_field.dart';
import '../../../shared/models/product.dart';

/// Smart Tasks Tab - Collapsible hierarchical checklist with three-way sync
///
/// Features:
/// - Auto-parsed sub-tasks from product/service descriptions
/// - Ad-hoc tasks with optional pricing
/// - Visual completion states (green/orange/grey)
/// - Collapsible parent items (products/services)
/// - Progress badges and percentage
/// - Three-way sync: Tasks ↔ Pega Items ↔ Invoice
class TasksTabView extends StatefulWidget {
  final String jobId;
  final bool readOnly;
  final Function(MechanicJobItem)? onItemAdded;
  final Function(String itemId)? onItemRemoved;
  final VoidCallback?
      onAddItemPressed; // NEW: Callback to trigger parent's add item dialog

  const TasksTabView({
    Key? key,
    required this.jobId,
    this.readOnly = false,
    this.onItemAdded,
    this.onItemRemoved,
    this.onAddItemPressed, // NEW
  }) : super(key: key);

  @override
  State<TasksTabView> createState() => _TasksTabViewState();
}

class _TasksTabViewState extends State<TasksTabView> {
  SmartTaskService? _taskService;
  BikeshopService? _bikeshopService;
  TenantService? _tenantService;
  Map<String, List<MechanicJobTask>> _groupedTasks = {};
  List<MechanicJobItem> _items = [];
  TaskProgress? _progress;
  bool _isLoading = true;
  final Set<String> _collapsedItems = {}; // Track collapsed parent items
  String? _editingTaskId; // Track which task is being edited inline

  @override
  void initState() {
    super.initState();
    // Services will be initialized in didChangeDependencies
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

  Future<void> _loadTasks() async {
    if (!mounted || _taskService == null) return;

    setState(() => _isLoading = true);

    try {
      // Fetch tasks, grouped tasks, progress, and items in parallel
      final results = await Future.wait([
        _taskService!.getTasksForJob(widget.jobId),
        _taskService!.getTasksGroupedByParent(widget.jobId),
        _taskService!.calculateProgress(widget.jobId),
        _fetchItems(),
      ]);

      if (mounted) {
        setState(() {
          _groupedTasks = results[1] as Map<String, List<MechanicJobTask>>;
          _progress = results[2] as TaskProgress?;
          _items = results[3] as List<MechanicJobItem>;
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
      final data = await Supabase.instance.client
          .from('mechanic_job_items')
          .select()
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
              ? const Center(child: CircularProgressIndicator())
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
            'Smart Tasks',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (_progress != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: (_progress!.completedTasks == _progress!.totalTasks)
                    ? Colors.green.shade50
                    : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_progress!.completedTasks}/${_progress!.totalTasks}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: (_progress!.completedTasks == _progress!.totalTasks)
                      ? Colors.green.shade700
                      : Colors.orange.shade700,
                ),
              ),
            ),
          if (!widget.readOnly) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add Item',
              onPressed: _showAddItemDialog,
              iconSize: 20,
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.add_task),
              tooltip: 'Add standalone task',
              onPressed: _showAddStandaloneTaskDialog,
              iconSize: 20,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTaskList() {
    if (_items.isEmpty) {
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
              'No tasks yet',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add products/services to auto-generate tasks',
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
        if (_groupedTasks.containsKey('standalone'))
          _buildStandaloneTasksGroup(_groupedTasks['standalone']!),
      ],
    );
  }

  /// Build item (product) group with parent checkbox and sub-tasks
  Widget _buildItemGroup(MechanicJobItem item) {
    final subTasks = _groupedTasks['item_${item.id}'] ?? [];

    // Sort tasks: auto-generated first, then manual tasks
    final sortedTasks = List<MechanicJobTask>.from(subTasks)
      ..sort((a, b) {
        // Auto-generated tasks come first
        if (a.parsedFromDescription && !b.parsedFromDescription) return -1;
        if (!a.parsedFromDescription && b.parsedFromDescription) return 1;
        // Within each group, sort by displayOrder
        return a.displayOrder.compareTo(b.displayOrder);
      });

    final completionStatus = _getCompletionStatus(sortedTasks);
    final isCollapsed = _collapsedItems.contains('item_${item.id}');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: _getGroupBackgroundColor(completionStatus),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Parent item header
          _buildItemHeader(item, sortedTasks, completionStatus),

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
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.task_alt, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Standalone Tasks',
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
    ParentCompletionStatus? status,
  ) {
    final completed = subTasks.where((t) => t.isCompleted).length;
    final total = subTasks.length;
    final isCollapsed = _collapsedItems.contains('item_${item.id}');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          // Collapse/Expand toggle (only if has subtasks)
          if (total > 0)
            IconButton(
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
            )
          else
            const SizedBox(width: 20),

          const SizedBox(width: 8),

          // Item icon
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withOpacity(0.5),
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
                    'Qty: ${item.quantity.toStringAsFixed(0)} • \$${item.unitPrice.toStringAsFixed(0)} • Total \$${item.totalPrice.toStringAsFixed(0)}',
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
              tooltip: 'Remove product',
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
    final isAutoGenerated = task.parsedFromDescription;

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
              tooltip: 'Cancel',
            ),
          ],
        ),
      );
    }

    // Normal display mode
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      constraints: const BoxConstraints(minHeight: 48),
      decoration: isAutoGenerated
          ? BoxDecoration(
              color: Colors.blue.shade50.withOpacity(0.3),
              border: Border(
                left: BorderSide(
                  color: Colors.blue.shade300,
                  width: 3,
                ),
              ),
            )
          : null,
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

          // Task name (clickable for inline edit if not auto-generated)
          Expanded(
            child: InkWell(
              onTap: widget.readOnly || isAutoGenerated
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
                  fontWeight: isAutoGenerated ? FontWeight.w500 : null,
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

          // Delete button (only for manual tasks)
          if (!widget.readOnly && !isAutoGenerated)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              iconSize: 18,
              tooltip: 'Delete task',
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
      label: const Text('Add sub-task'),
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
                'Overall Progress',
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
              'Ad-hoc total: \$${_progress!.totalAdHocPrice.toStringAsFixed(0)}',
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
      isAllCompleted: completed == total,
      isInProgress: completed > 0 && completed < total,
      isNotStarted: completed == 0,
    );
  }

  Color _getGroupBackgroundColor(ParentCompletionStatus? status) {
    if (status == null) return Colors.white;

    if (status.isAllCompleted) {
      return Colors.green.shade50;
    } else if (status.isInProgress) {
      return Colors.orange.shade50;
    } else {
      return Colors.grey.shade50;
    }
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

    // Otherwise, show our own dialog
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Item'),
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
            labelText: 'Product or Service',
            hintText: 'Buscar en el catálogo por nombre o SKU',
            autoFocus: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
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
      if (product.id == null || product.id!.isEmpty) {
        throw Exception('Product must have an ID to link to catalog');
      }

      debugPrint('📦 Adding catalog item: ${product.name} (ID: ${product.id})');
      debugPrint('📦 FULL PRODUCT DATA:');
      debugPrint('  - ID: ${product.id}');
      debugPrint('  - Name: ${product.name}');
      debugPrint('  - SKU: ${product.sku}');
      debugPrint('  - Description: "${product.description}"');
      debugPrint('  - Description null?: ${product.description == null}');
      debugPrint('  - Description empty?: ${product.description?.isEmpty ?? true}');

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

      // 🤖 Auto-generate tasks from product description if available
      debugPrint('🔍 Product description check:');
      debugPrint('  - Has description: ${product.description != null}');
      debugPrint('  - Description length: ${product.description?.length ?? 0}');
      debugPrint('  - Description content: "${product.description}"');
      debugPrint('  - TaskService available: ${_taskService != null}');
      debugPrint('  - Created item ID: ${created.id}');
      
      if (product.description != null &&
          product.description!.isNotEmpty &&
          _taskService != null &&
          created.id != null) {
        debugPrint('🤖 Generating auto-tasks from product description');
        try {
          final generatedTasks = await _taskService!.generateAutoTasksFromDescription(
            jobId: widget.jobId,
            parentItemId: created.id!,
            description: product.description!,
          );
          debugPrint('✅ Auto-tasks generated successfully: ${generatedTasks.length} tasks');
        } catch (e) {
          debugPrint('⚠️ Failed to generate auto-tasks: $e');
          // Don't fail the whole operation if auto-task generation fails
        }
      } else {
        debugPrint('⚠️ Skipping auto-task generation:');
        if (product.description == null || product.description!.isEmpty) {
          debugPrint('  - Product has no description');
        }
        if (_taskService == null) {
          debugPrint('  - TaskService is null');
        }
        if (created.id == null) {
          debugPrint('  - Created item has no ID');
        }
      }

      if (widget.onItemAdded != null) {
        widget.onItemAdded!(created);
      }

      await _loadTasks();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Added: ${created.productName}'),
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
          SnackBar(content: Text('Failed to update task: $e')),
        );
      }
    }
  }

  Future<void> _deleteTask(MechanicJobTask task) async {
    // Prevent deletion of auto-generated tasks
    if (task.parsedFromDescription) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Cannot delete auto-generated tasks'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task'),
        content: Text('Delete "${task.taskName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
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
            SnackBar(content: Text('Failed to delete task: $e')),
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
        title: const Text('Remove Product'),
        content: Text('Remove "${item.productName}" from this job?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
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
        title: const Text('Add Standalone Task'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Task Name',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., Final inspection, Quality check',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceController,
                decoration: const InputDecoration(
                  labelText: 'Price (optional)',
                  border: OutlineInputBorder(),
                  prefixText: '\$',
                  hintText: 'Leave 0 for no charge',
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
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
            const SnackBar(content: Text('Task added')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error adding task: $e')),
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
        title: const Text('Add Sub-Task'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Task Name',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., Check compatibility, Test functionality',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceController,
                decoration: const InputDecoration(
                  labelText: 'Additional Price (optional)',
                  border: OutlineInputBorder(),
                  prefixText: '\$',
                  hintText: 'Extra charge for this task',
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
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
            const SnackBar(content: Text('Sub-task added')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error adding sub-task: $e')),
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
          .update({'task_name': newName}).eq('id', task.id!);

      await _loadTasks();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update task: $e')),
        );
      }
    }
  }

  void _showEditProductDialog(MechanicJobItem item) async {
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
        title: const Text('Edit Product'),
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
                labelText: 'Product',
                hintText: 'Search or enter custom item',
                autoFocus: true,
                initialValue: item.productName,
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Quantity',
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
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
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
            .eq('id', item.id!);

        await _loadTasks();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Product updated')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update product: $e')),
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
