import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';
import 'package:vinabike_erp/modules/tasks/models/task_model.dart';

class TaskService extends ChangeNotifier {
  final SupabaseClient _supabase;
  final TenantService _tenantService;

  // In-memory cache
  List<TaskModel> _tasks = [];
  bool _isInit = false;

  List<TaskModel> get tasks => _tasks;

  TaskService(this._supabase, this._tenantService);

  Future<void> init() async {
    if (_isInit) return;
    await fetchTasks();
    _isInit = true;
  }

  Future<void> fetchTasks() async {
    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null) return;

    try {
      final response = await _supabase.from('smart_tasks').select('''
            *,
            creator:profiles!created_by(full_name),
            assignee:profiles!assigned_to(full_name),
            job:jobs!linked_job_id(job_number),
            purchase_invoice:purchase_invoices!linked_purchase_invoice_id(invoice_number),
            sales_invoice:sales_invoices!linked_sales_invoice_id(invoice_number),
            customer:customers!linked_customer_id(name),
            supplier:suppliers!linked_supplier_id(trade_name)
          ''').eq('tenant_id', tenantId).order('created_at', ascending: false);

      final List<TaskModel> loadedTasks = [];
      for (var row in (response as List<dynamic>)) {
        final map = row as Map<String, dynamic>;

        // Extract joined names for convenience badging
        final creatorName = map['creator']?['full_name'] as String?;
        final assigneeName = map['assignee']?['full_name'] as String?;
        final linkedJobNumber = map['job']?['job_number'] as String?;
        final linkedPurchaseNumber =
            map['purchase_invoice']?['invoice_number'] as String?;
        final linkedSalesNumber =
            map['sales_invoice']?['invoice_number'] as String?;
        final linkedCustomerName = map['customer']?['name'] as String?;
        final linkedSupplierName = map['supplier']?['trade_name'] as String?;

        var task = TaskModel.fromJson(map);
        task = task.copyWith(
          creatorName: creatorName,
          assigneeName: assigneeName,
          linkedJobNumber: linkedJobNumber,
          linkedPurchaseInvoiceNumber: linkedPurchaseNumber,
          linkedSalesInvoiceNumber: linkedSalesNumber,
          linkedCustomerName: linkedCustomerName,
          linkedSupplierName: linkedSupplierName,
        );

        loadedTasks.add(task);
      }

      _tasks = loadedTasks;
      notifyListeners();
      print('✅ [TaskService] Loaded ${_tasks.length} tasks');
    } catch (e) {
      print('❌ [TaskService] Error fetching tasks: $e');
      rethrow;
    }
  }

  Future<TaskModel> createTask(TaskModel task) async {
    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null) throw Exception('No tenant ID');

    try {
      final data = task.toJson();
      data.remove('id');
      data['tenant_id'] = tenantId;
      data.remove('created_at');
      data.remove('updated_at');

      final response =
          await _supabase.from('smart_tasks').insert(data).select().single();

      final newTask = TaskModel.fromJson(response);
      _tasks.insert(0, newTask); // Add to local cache at top
      notifyListeners();
      return newTask;
    } catch (e) {
      print('❌ [TaskService] Error creating task: $e');
      rethrow;
    }
  }

  Future<void> updateTask(TaskModel task) async {
    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null) throw Exception('No tenant ID');
    if (task.id == null) throw Exception('Task ID cannot be null for update');

    try {
      final data = task.toJson();
      data.remove('id');
      data.remove('tenant_id');
      data.remove('created_at');
      data.remove('updated_at');
      data.remove('created_by');

      await _supabase
          .from('smart_tasks')
          .update(data)
          .eq('id', task.id!)
          .eq('tenant_id', tenantId);

      // Update local cache
      final index = _tasks.indexWhere((t) => t.id == task.id);
      if (index != -1) {
        _tasks[index] = task;
        notifyListeners();
      }
    } catch (e) {
      print('❌ [TaskService] Error updating task: $e');
      rethrow;
    }
  }

  Future<void> deleteTask(String taskId) async {
    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null) throw Exception('No tenant ID');

    try {
      await _supabase
          .from('smart_tasks')
          .delete()
          .eq('id', taskId)
          .eq('tenant_id', tenantId);

      _tasks.removeWhere((t) => t.id == taskId);
      notifyListeners();
    } catch (e) {
      print('❌ [TaskService] Error deleting task: $e');
      rethrow;
    }
  }
}
