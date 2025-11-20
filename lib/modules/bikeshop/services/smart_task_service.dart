import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../models/bikeshop_models.dart';

/// Smart Task Service - Three-way sync system for tasks, items, and invoices
/// Features:
/// - CRUD operations for tasks
/// - Realtime sync with debouncing
/// - Completion tracking with timestamps
/// - Ad-hoc pricing with auto-sync to items
/// - Hierarchical task structure (parent → sub-tasks)
/// - Visual completion states for UI
class SmartTaskService extends ChangeNotifier {
  final DatabaseService _db;
  final TenantService _tenantService = TenantService();
  
  RealtimeChannel? _tasksChannel;
  Timer? _notifyDebounceTimer;
  bool _isDisposed = false;

  bool get mounted => !_isDisposed;

  SmartTaskService(this._db) {
    // Setup realtime with debouncing
    _setupTasksRealtime();
  }

  void _safeNotify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  void _debouncedNotify() {
    _notifyDebounceTimer?.cancel();
    _notifyDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        _safeNotify();
      }
    });
  }

  Future<void> _setupTasksRealtime() async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) return;

      _tasksChannel = Supabase.instance.client
          .channel('smart_tasks_channel')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'mechanic_job_tasks',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'tenant_id',
              value: tenantId,
            ),
            callback: (payload) {
              if (kDebugMode) {
                print('🔔 [SmartTaskService] Realtime: ${payload.eventType}');
              }
              _debouncedNotify();
            },
          )
          .subscribe();

      if (kDebugMode) {
        print('✅ [SmartTaskService] Realtime subscription active');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ [SmartTaskService] Realtime setup error: $e');
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _notifyDebounceTimer?.cancel();
    _tasksChannel?.unsubscribe();
    super.dispose();
  }

  // ============================================================
  // CRUD OPERATIONS
  // ============================================================

  /// Get all tasks for a job (with optional parent filter)
  Future<List<MechanicJobTask>> getTasksForJob(
    String jobId, {
    String? parentItemId,
    bool? isStandalone,
  }) async {
    try {
      var query = Supabase.instance.client.from('mechanic_job_tasks').select().eq('job_id', jobId);
      
      if (parentItemId != null) {
        query = query.eq('parent_item_id', parentItemId);
      }
      if (isStandalone != null) {
        query = query.eq('is_standalone', isStandalone);
      }      final data = await query.order('display_order', ascending: true);

      return (data as List).map((json) => MechanicJobTask.fromJson(json)).toList();
    } catch (e) {
      if (kDebugMode) print('❌ Error fetching tasks: $e');
      rethrow;
    }
  }

  /// Get tasks grouped by parent (for UI rendering)
  Future<Map<String, List<MechanicJobTask>>> getTasksGroupedByParent(String jobId) async {
    try {
      final allTasks = await getTasksForJob(jobId);
      
      final grouped = <String, List<MechanicJobTask>>{};
      
      for (final task in allTasks) {
        if (task.isStandalone) {
          grouped.putIfAbsent('standalone', () => []).add(task);
        } else if (task.parentItemId != null) {
          grouped.putIfAbsent('item_${task.parentItemId}', () => []).add(task);
        }
      }
      
      return grouped;
    } catch (e) {
      if (kDebugMode) print('❌ Error grouping tasks: $e');
      rethrow;
    }
  }

  /// Create a new task
  Future<MechanicJobTask> createTask(MechanicJobTask task) async {
    try {
      debugPrint('🟢 [SmartTaskService] createTask called: ${task.taskName}');
      final data = await _db.insert('mechanic_job_tasks', task.toJson());
      debugPrint('🟢 [SmartTaskService] Task inserted, calling _safeNotify()');
      _safeNotify();
      debugPrint('🟢 [SmartTaskService] _safeNotify() called');
      return MechanicJobTask.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('❌ Error creating task: $e');
      rethrow;
    }
  }

  /// Update task
  Future<void> updateTask(String taskId, Map<String, dynamic> updates) async {
    try {
      await _db.update(
        'mechanic_job_tasks',
        taskId,
        updates,
      );
      _safeNotify();
    } catch (e) {
      if (kDebugMode) print('❌ Error updating task: $e');
      rethrow;
    }
  }

  /// Toggle task completion
  Future<void> toggleTaskCompletion(String taskId, bool isCompleted) async {
    try {
      await updateTask(taskId, {'is_completed': isCompleted});
    } catch (e) {
      if (kDebugMode) print('❌ Error toggling task: $e');
      rethrow;
    }
  }

  /// Delete task (and associated ad-hoc item if exists)
  Future<void> deleteTask(String taskId) async {
    try {
      debugPrint('🗑️ [SmartTaskService] deleteTask called: $taskId');
      await _db.delete('mechanic_job_tasks', taskId);
      debugPrint('🗑️ [SmartTaskService] Task deleted, calling _safeNotify()');
      _safeNotify();
    } catch (e) {
      if (kDebugMode) print('❌ Error deleting task: $e');
      rethrow;
    }
  }

  /// Reorder tasks (update display_order)
  Future<void> reorderTasks(List<String> taskIds) async {
    try {
      for (var i = 0; i < taskIds.length; i++) {
        await updateTask(taskIds[i], {'display_order': i});
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error reordering tasks: $e');
      rethrow;
    }
  }

  // ============================================================
  // COLLAPSE STATE MANAGEMENT
  // ============================================================

  /// Get user's collapse preferences for a job
  Future<TaskPreferences?> getPreferences(String userId, String jobId) async {
    try {
      final data = await Supabase.instance.client
          .from('mechanic_job_task_preferences')
          .select()
          .eq('user_id', userId)
          .eq('job_id', jobId)
          .maybeSingle();

      if (data == null) return null;
      return TaskPreferences.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('❌ Error fetching preferences: $e');
      return null;
    }
  }

  /// Save collapse state
  Future<void> savePreferences(TaskPreferences prefs) async {
    try {
      await Supabase.instance.client.from('mechanic_job_task_preferences').upsert(prefs.toJson());
    } catch (e) {
      if (kDebugMode) print('❌ Error saving preferences: $e');
      rethrow;
    }
  }

  // ============================================================
  // PROGRESS CALCULATIONS
  // ============================================================

  /// Calculate completion progress for a job
  Future<TaskProgress> calculateProgress(String jobId) async {
    try {
      final tasks = await getTasksForJob(jobId);
      
      final totalTasks = tasks.length;
      final completedTasks = tasks.where((t) => t.isCompleted).length;
      final percentage = totalTasks > 0 ? (completedTasks / totalTasks) * 100 : 0.0;
      
      // Calculate total with ad-hocs
      final totalPrice = tasks
          .where((t) => t.isAdhoc && t.adhocPrice != null)
          .fold(0.0, (sum, task) => sum + task.adhocPrice!);
      
      return TaskProgress(
        totalTasks: totalTasks,
        completedTasks: completedTasks,
        percentage: percentage,
        totalAdHocPrice: totalPrice,
      );
    } catch (e) {
      if (kDebugMode) print('❌ Error calculating progress: $e');
      rethrow;
    }
  }

  /// Get completion status for a parent item/labor
  Future<ParentCompletionStatus> getParentCompletionStatus(
    String jobId,
    String? parentItemId,
  ) async {
    try {
      final tasks = await getTasksForJob(
        jobId,
        parentItemId: parentItemId,
      );
      
      final total = tasks.length;
      final completed = tasks.where((t) => t.isCompleted).length;
      
      return ParentCompletionStatus(
        totalTasks: total,
        completedTasks: completed,
        isAllCompleted: total > 0 && completed == total,
        isInProgress: completed > 0 && completed < total,
        isNotStarted: completed == 0,
      );
    } catch (e) {
      if (kDebugMode) print('❌ Error getting parent status: $e');
      rethrow;
    }
  }
}

// ============================================================
// HELPER CLASSES
// ============================================================

class TaskProgress {
  final int totalTasks;
  final int completedTasks;
  final double percentage;
  final double totalAdHocPrice;

  TaskProgress({
    required this.totalTasks,
    required this.completedTasks,
    required this.percentage,
    required this.totalAdHocPrice,
  });
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
