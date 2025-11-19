import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/bikeshop_models.dart';
import '../services/smart_task_service.dart';
import '../services/bikeshop_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/widgets/product_autocomplete_field.dart';

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
  final Function(MechanicJobLabor)? onLaborAdded;
  final Function(String laborId)? onLaborRemoved;

  const TasksTabView({
    Key? key,
    required this.jobId,
    this.readOnly = false,
    this.onItemAdded,
    this.onItemRemoved,
    this.onLaborAdded,
    this.onLaborRemoved,
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
  List<MechanicJobLabor> _labor = [];
  TaskProgress? _progress;
  bool _isLoading = true;

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
      _loadTasks();
    }
  }

  Future<void> _loadTasks() async {
    if (!mounted || _taskService == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      // Fetch tasks, items, and labor in parallel
      final results = await Future.wait([
        _taskService!.getTasksForJob(widget.jobId),
        _taskService!.getTasksGroupedByParent(widget.jobId),
        _taskService!.calculateProgress(widget.jobId),
        _fetchItems(),
        _fetchLabor(),
      ]);
      
      if (mounted) {
        setState(() {
          _groupedTasks = results[1] as Map<String, List<MechanicJobTask>>;
          _progress = results[2] as TaskProgress?;
          _items = results[3] as List<MechanicJobItem>;
          _labor = results[4] as List<MechanicJobLabor>;
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
      
      return (data as List).map((json) => MechanicJobItem.fromJson(json)).toList();
    } catch (e) {
      debugPrint('❌ Failed to fetch items: $e');
      return [];
    }
  }

  Future<List<MechanicJobLabor>> _fetchLabor() async {
    try {
      final data = await Supabase.instance.client
          .from('mechanic_job_labor')
          .select()
          .eq('job_id', widget.jobId)
          .order('created_at', ascending: true);
      
      return (data as List).map((json) => MechanicJobLabor.fromJson(json)).toList();
    } catch (e) {
      debugPrint('❌ Failed to fetch labor: $e');
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
              icon: const Icon(Icons.inventory_2_outlined),
              tooltip: 'Add Product',
              onPressed: _showAddProductDialog,
              iconSize: 20,
            ),
            IconButton(
              icon: const Icon(Icons.build_outlined),
              tooltip: 'Add Service',
              onPressed: _showAddServiceDialog,
              iconSize: 20,
            ),
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
    if (_items.isEmpty && _labor.isEmpty) {
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
        // Show items (products) - EXCLUDE ad-hoc items auto-created from tasks
        ..._items
            .where((item) => !item.productName.startsWith('Ad-hoc: '))
            .map((item) => _buildItemGroup(item)),
        
        // Show labor (services)
        ..._labor.map((labor) => _buildLaborGroup(labor)),
        
        // Show standalone tasks (if any)
        if (_groupedTasks.containsKey('standalone'))
          _buildStandaloneTasksGroup(_groupedTasks['standalone']!),
      ],
    );
  }

  /// Build item (product) group with parent checkbox and sub-tasks
  Widget _buildItemGroup(MechanicJobItem item) {
    final subTasks = _groupedTasks['item_${item.id}'] ?? [];
    final completionStatus = _getCompletionStatus(subTasks);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: _getGroupBackgroundColor(completionStatus),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Parent item header
          _buildItemHeader(item, subTasks, completionStatus),
          
          // Sub-tasks (if any)
          if (subTasks.isNotEmpty)
            ...subTasks.map((task) => Padding(
              padding: const EdgeInsets.only(left: 32),
              child: _buildTaskItem(task),
            )),
          
          // Add sub-task button
          if (!widget.readOnly)
            Padding(
              padding: const EdgeInsets.only(left: 32, bottom: 8),
              child: _buildAddSubTaskButton('item_${item.id}', 'item'),
            ),
        ],
      ),
    );
  }

  /// Build labor (service) group with parent checkbox and sub-tasks
  Widget _buildLaborGroup(MechanicJobLabor labor) {
    final subTasks = _groupedTasks['labor_${labor.id}'] ?? [];
    final completionStatus = _getCompletionStatus(subTasks);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: _getGroupBackgroundColor(completionStatus),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Parent labor header
          _buildLaborHeader(labor, subTasks, completionStatus),
          
          // Sub-tasks (if any)
          if (subTasks.isNotEmpty)
            ...subTasks.map((task) => Padding(
              padding: const EdgeInsets.only(left: 32),
              child: _buildTaskItem(task),
            )),
          
          // Add sub-task button
          if (!widget.readOnly)
            Padding(
              padding: const EdgeInsets.only(left: 32, bottom: 8),
              child: _buildAddSubTaskButton('labor_${labor.id}', 'labor'),
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
    
    return InkWell(
      onTap: () {
        // TODO: Toggle collapse state
      },
      child: Container(
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
            // Product icon
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.inventory_2, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
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
                    'Qty: ${item.quantity.toStringAsFixed(0)} • \$${item.unitPrice.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
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
      ),
    );
  }

  /// Build labor (service) header with checkbox
  Widget _buildLaborHeader(
    MechanicJobLabor labor,
    List<MechanicJobTask> subTasks,
    ParentCompletionStatus? status,
  ) {
    final completed = subTasks.where((t) => t.isCompleted).length;
    final total = subTasks.length;
    
    return InkWell(
      onTap: () {
        // TODO: Toggle collapse state
      },
      child: Container(
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
            // Service icon
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.build, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    labor.description ?? 'Service/Labor',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${labor.hoursWorked}h • \$${labor.hourlyRate.toStringAsFixed(0)}/h',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
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
                tooltip: 'Remove service',
                onPressed: () => _confirmRemoveLabor(labor),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTaskItem(MechanicJobTask task) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Checkbox
          Checkbox(
            value: task.isCompleted,
            onChanged: widget.readOnly
                ? null
                : (value) => _toggleTaskCompletion(task, value ?? false),
          ),
          const SizedBox(width: 12),
          
          // Task name
          Expanded(
            child: Text(
              task.taskName,
              style: TextStyle(
                fontSize: 14,
                decoration: task.isCompleted
                    ? TextDecoration.lineThrough
                    : null,
                color: task.isCompleted
                    ? Colors.grey.shade600
                    : null,
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
          
          // Delete button
          if (!widget.readOnly)
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

  Widget _buildAddSubTaskButton(String groupKey, String parentType) {
    return TextButton.icon(
      onPressed: () => _showAddSubTaskDialog(groupKey, parentType),
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

  String _getGroupTitle(String groupKey) {
    if (groupKey == 'standalone') return 'Ad-hoc Tasks';
    
    // TODO: Fetch actual product/service name from parent
    if (groupKey.startsWith('item_')) {
      return 'Product Item';
    } else {
      return 'Service/Labor';
    }
  }

  // Actions
  Future<void> _toggleTaskCompletion(MechanicJobTask task, bool isCompleted) async {
    if (_taskService == null) return;
    try {
      await _taskService!.toggleTaskCompletion(task.id!, isCompleted);
      _loadTasks(); // Refresh
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update task: $e')),
        );
      }
    }
  }

  Future<void> _deleteTask(MechanicJobTask task) async {
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

  void _showAddProductDialog() async {
    ProductSelection? selectedProduct;
    double quantity = 1;
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Product'),
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
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Quantity',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  quantity = double.tryParse(value) ?? 1;
                },
                controller: TextEditingController(text: '1'),
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
    
    if (result == true && selectedProduct != null) {
      try {
        if (_tenantService == null || _bikeshopService == null) {
          throw Exception('Services not initialized');
        }
        final tenantId = await _tenantService!.getTenantId();
        if (tenantId == null) throw Exception('No tenant ID');
        
        final product = selectedProduct!.product;
        final item = MechanicJobItem(
          tenantId: tenantId,
          jobId: widget.jobId,
          productId: product?.id,
          productName: selectedProduct!.displayText,
          productSku: product?.sku,
          quantity: quantity,
          unitPrice: product?.price ?? 0,
          totalPrice: (product?.price ?? 0) * quantity,
          notes: selectedProduct!.customDescription,
        );
        
        final created = await _bikeshopService!.createJobItem(item);
        
        if (widget.onItemAdded != null) {
          widget.onItemAdded!(created);
        }
        
        await _loadTasks();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Product added')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error adding product: $e')),
          );
        }
      }
    }
  }

  void _showAddServiceDialog() async {
    final descriptionController = TextEditingController();
    final hoursController = TextEditingController(text: '1');
    final rateController = TextEditingController(text: '10000');
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Service/Labor'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., Brake adjustment, Chain cleaning',
                ),
                autofocus: true,
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: hoursController,
                      decoration: const InputDecoration(
                        labelText: 'Hours',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: rateController,
                      decoration: const InputDecoration(
                        labelText: 'Rate/Hour',
                        border: OutlineInputBorder(),
                        prefixText: '\$',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
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
    
    if (result == true && descriptionController.text.isNotEmpty) {
      try {
        if (_tenantService == null || _bikeshopService == null) {
          throw Exception('Services not initialized');
        }
        final tenantId = await _tenantService!.getTenantId();
        if (tenantId == null) throw Exception('No tenant ID');
        
        final hours = double.tryParse(hoursController.text) ?? 1;
        final rate = double.tryParse(rateController.text) ?? 10000;
        
        final labor = MechanicJobLabor(
          tenantId: tenantId,
          jobId: widget.jobId,
          technicianId: null,
          technicianName: 'Manual Entry',
          description: descriptionController.text,
          hoursWorked: hours,
          hourlyRate: rate,
          totalCost: hours * rate,
          workDate: DateTime.now(),
        );
        
        final created = await _bikeshopService!.createJobLabor(labor);
        
        if (widget.onLaborAdded != null) {
          widget.onLaborAdded!(created);
        }
        
        await _loadTasks();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Service added')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error adding service: $e')),
          );
        }
      }
    }
  }

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

  Future<void> _confirmRemoveLabor(MechanicJobLabor labor) async {
    debugPrint('🗑️ [TasksTabView] _confirmRemoveLabor called for: ${labor.description}');
    if (widget.onLaborRemoved == null) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Service'),
        content: Text('Remove "${labor.description ?? 'service'}" from this job?'),
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
    
    if (confirmed == true && labor.id != null) {
      debugPrint('🗑️ [TasksTabView] User confirmed, calling onLaborRemoved callback');
      widget.onLaborRemoved!(labor.id!);
      debugPrint('🗑️ [TasksTabView] onLaborRemoved callback completed, calling _loadTasks()');
      _loadTasks(); // Refresh view
      debugPrint('🗑️ [TasksTabView] _loadTasks() called');
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
          taskDescription: descriptionController.text.isNotEmpty ? descriptionController.text : null,
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

  void _showAddSubTaskDialog(String groupKey, String parentType) async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final priceController = TextEditingController(text: '0');
    
    // Extract parent ID from groupKey (e.g., "item_abc123" -> "abc123")
    final parentId = groupKey.replaceFirst('${parentType}_', '');
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Sub-Task to ${parentType == 'item' ? 'Product' : 'Service'}'),
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
          taskDescription: descriptionController.text.isNotEmpty ? descriptionController.text : null,
          isStandalone: false,
          parentItemId: parentType == 'item' ? parentId : null,
          parentLaborId: parentType == 'labor' ? parentId : null,
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
}
