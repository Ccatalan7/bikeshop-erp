import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/mechanic_job_task.dart';

/// Service for managing mechanic job tasks (smart to-do list)
/// Tasks are automatically created when parts/services are added to trabajos
/// and sync with trabajo status changes
class MechanicJobTaskService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  List<MechanicJobTask> _tasks = [];
  TaskSummary? _currentSummary;
  bool _isLoading = false;
  String? _error;
  bool _isDisposed = false;

  List<MechanicJobTask> get tasks => _tasks;
  TaskSummary? get currentSummary => _currentSummary;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get mounted => !_isDisposed;

  /// Safe notifyListeners that checks disposed state
  void _safeNotify() {
    if (!_isDisposed) notifyListeners();
  }

  /// Load all tasks for a specific mechanic job
  Future<void> loadTasksForJob(String jobId) async {
    if (_isDisposed) return; // Don't load if disposed

    _isLoading = true;
    _error = null;
    _safeNotify();

    try {
      final response = await _supabase
          .from('mechanic_job_tasks')
          .select()
          .eq('job_id', jobId)
          .order('display_order', ascending: true)
          .order('created_at', ascending: true);

      if (_isDisposed) return; // Check again after async

      _tasks = (response as List)
          .map((json) => MechanicJobTask.fromJson(json as Map<String, dynamic>))
          .toList();

      // Also load summary
      await _loadSummaryForJob(jobId);
    } catch (e) {
      if (_isDisposed) return;
      _error = 'Error al cargar tareas: ${e.toString()}';
      debugPrint('❌ Error loading tasks for job $jobId: $e');
    } finally {
      if (_isDisposed) return;
      _isLoading = false;
      _safeNotify();
    }
  }

  /// Load task summary statistics for a job
  Future<void> _loadSummaryForJob(String jobId) async {
    try {
      final response = await _supabase.rpc('get_job_task_summary', params: {
        'p_job_id': jobId,
      });

      _currentSummary = TaskSummary.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      debugPrint('⚠️ Error loading task summary: $e');
      _currentSummary = TaskSummary.empty();
    }
  }

  /// Get task summary for a job (convenience method)
  Future<TaskSummary> getTaskSummary(String jobId) async {
    try {
      final response = await _supabase.rpc('get_job_task_summary', params: {
        'p_job_id': jobId,
      });

      return TaskSummary.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      debugPrint('⚠️ Error getting task summary: $e');
      return TaskSummary.empty();
    }
  }

  /// Create a new task (manual task, not auto-generated)
  Future<MechanicJobTask?> createTask({
    required String jobId,
    required TaskType taskType,
    required String title,
    String? description,
    TaskPriority priority = TaskPriority.normal,
    String? assignedTo,
    String? assignedTechnicianName,
    int? estimatedDurationMinutes,
  }) async {
    try {
      final data = {
        'job_id': jobId,
        'task_type': taskType.value,
        'title': title,
        if (description != null) 'description': description,
        'status': TaskStatus.pending.value,
        'priority': priority.value,
        if (assignedTo != null) 'assigned_to': assignedTo,
        if (assignedTechnicianName != null)
          'assigned_technician_name': assignedTechnicianName,
        if (estimatedDurationMinutes != null)
          'estimated_duration_minutes': estimatedDurationMinutes,
        'is_auto_generated': false,
        'display_order': _tasks.isEmpty
            ? 0
            : _tasks
                    .map((t) => t.displayOrder)
                    .reduce((a, b) => a > b ? a : b) +
                1,
      };

      final response = await _supabase
          .from('mechanic_job_tasks')
          .insert(data)
          .select()
          .single();

      final newTask = MechanicJobTask.fromJson(response);

      // Add to local list
      _tasks.add(newTask);
      _safeNotify();

      debugPrint('✅ Task created: ${newTask.title}');
      return newTask;
    } catch (e) {
      _error = 'Error al crear tarea: ${e.toString()}';
      debugPrint('❌ Error creating task: $e');
      _safeNotify();
      return null;
    }
  }

  /// Update task status
  Future<bool> updateTaskStatus(
    String taskId,
    TaskStatus newStatus, {
    String? completedByName,
  }) async {
    try {
      final updates = <String, dynamic>{
        'status': newStatus.value,
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Set timestamps based on status
      if (newStatus == TaskStatus.inProgress) {
        updates['started_at'] = DateTime.now().toIso8601String();
      } else if (newStatus == TaskStatus.completed) {
        updates['completed_at'] = DateTime.now().toIso8601String();
        if (completedByName != null) {
          updates['completed_by_name'] = completedByName;
        }
      }

      await _supabase
          .from('mechanic_job_tasks')
          .update(updates)
          .eq('id', taskId);

      // Update local list
      final index = _tasks.indexWhere((t) => t.id == taskId);
      if (index != -1) {
        final task = _tasks[index];
        _tasks[index] = task.copyWith(
          status: newStatus,
          startedAt: newStatus == TaskStatus.inProgress
              ? DateTime.now()
              : task.startedAt,
          completedAt: newStatus == TaskStatus.completed
              ? DateTime.now()
              : task.completedAt,
          completedByName: completedByName ?? task.completedByName,
          updatedAt: DateTime.now(),
        );
        _safeNotify();
      }

      debugPrint('✅ Task status updated: $taskId → ${newStatus.displayName}');
      return true;
    } catch (e) {
      _error = 'Error al actualizar estado: ${e.toString()}';
      debugPrint('❌ Error updating task status: $e');
      _safeNotify();
      return false;
    }
  }

  /// Update task priority
  Future<bool> updateTaskPriority(
      String taskId, TaskPriority newPriority) async {
    try {
      await _supabase.from('mechanic_job_tasks').update({
        'priority': newPriority.value,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', taskId);

      // Update local list
      final index = _tasks.indexWhere((t) => t.id == taskId);
      if (index != -1) {
        _tasks[index] = _tasks[index].copyWith(
          priority: newPriority,
          updatedAt: DateTime.now(),
        );
        _safeNotify();
      }

      debugPrint(
          '✅ Task priority updated: $taskId → ${newPriority.displayName}');
      return true;
    } catch (e) {
      _error = 'Error al actualizar prioridad: ${e.toString()}';
      debugPrint('❌ Error updating task priority: $e');
      _safeNotify();
      return false;
    }
  }

  /// Update task assignment
  Future<bool> assignTask(
    String taskId, {
    String? assignedTo,
    String? technicianName,
  }) async {
    try {
      await _supabase.from('mechanic_job_tasks').update({
        if (assignedTo != null) 'assigned_to': assignedTo,
        if (technicianName != null) 'assigned_technician_name': technicianName,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', taskId);

      // Update local list
      final index = _tasks.indexWhere((t) => t.id == taskId);
      if (index != -1) {
        _tasks[index] = _tasks[index].copyWith(
          assignedTo: assignedTo ?? _tasks[index].assignedTo,
          assignedTechnicianName:
              technicianName ?? _tasks[index].assignedTechnicianName,
          updatedAt: DateTime.now(),
        );
        _safeNotify();
      }

      debugPrint('✅ Task assigned: $taskId → $technicianName');
      return true;
    } catch (e) {
      _error = 'Error al asignar tarea: ${e.toString()}';
      debugPrint('❌ Error assigning task: $e');
      _safeNotify();
      return false;
    }
  }

  /// Update task notes
  Future<bool> updateTaskNotes(String taskId, String notes) async {
    try {
      await _supabase.from('mechanic_job_tasks').update({
        'notes': notes,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', taskId);

      // Update local list
      final index = _tasks.indexWhere((t) => t.id == taskId);
      if (index != -1) {
        _tasks[index] = _tasks[index].copyWith(
          notes: notes,
          updatedAt: DateTime.now(),
        );
        _safeNotify();
      }

      return true;
    } catch (e) {
      _error = 'Error al actualizar notas: ${e.toString()}';
      debugPrint('❌ Error updating task notes: $e');
      _safeNotify();
      return false;
    }
  }

  /// Delete a task (manual tasks only - auto-generated tasks are deleted via cascade)
  Future<bool> deleteTask(String taskId) async {
    try {
      await _supabase.from('mechanic_job_tasks').delete().eq('id', taskId);

      // Remove from local list
      _tasks.removeWhere((t) => t.id == taskId);
      _safeNotify();

      debugPrint('✅ Task deleted: $taskId');
      return true;
    } catch (e) {
      _error = 'Error al eliminar tarea: ${e.toString()}';
      debugPrint('❌ Error deleting task: $e');
      _safeNotify();
      return false;
    }
  }

  /// Reorder tasks (update display_order)
  Future<bool> reorderTasks(List<MechanicJobTask> reorderedTasks) async {
    try {
      // Update display_order for each task
      for (int i = 0; i < reorderedTasks.length; i++) {
        await _supabase
            .from('mechanic_job_tasks')
            .update({'display_order': i}).eq('id', reorderedTasks[i].id);
      }

      // Update local list
      _tasks = reorderedTasks
          .map((t) => t.copyWith(displayOrder: reorderedTasks.indexOf(t)))
          .toList();
      _safeNotify();

      debugPrint('✅ Tasks reordered');
      return true;
    } catch (e) {
      _error = 'Error al reordenar tareas: ${e.toString()}';
      debugPrint('❌ Error reordering tasks: $e');
      _safeNotify();
      return false;
    }
  }

  /// Get tasks filtered by status
  List<MechanicJobTask> getTasksByStatus(TaskStatus status) {
    return _tasks.where((t) => t.status == status).toList();
  }

  /// Get tasks filtered by priority
  List<MechanicJobTask> getTasksByPriority(TaskPriority priority) {
    return _tasks.where((t) => t.priority == priority).toList();
  }

  /// Get pending tasks (not completed/skipped)
  List<MechanicJobTask> get pendingTasks {
    return _tasks
        .where((t) =>
            t.status != TaskStatus.completed && t.status != TaskStatus.skipped)
        .toList();
  }

  /// Get completed tasks
  List<MechanicJobTask> get completedTasks {
    return _tasks.where((t) => t.status == TaskStatus.completed).toList();
  }

  /// Clear current tasks
  void clearTasks() {
    if (_isDisposed) return;
    _tasks = [];
    _currentSummary = null;
    _error = null;
    _safeNotify();
  }

  /// Clear error message
  void clearError() {
    if (_isDisposed) return;
    _error = null;
    _safeNotify();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
