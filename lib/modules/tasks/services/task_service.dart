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
    if (tenantId == null) {
      print('⚠️ [TaskService] No tenant ID, skipping fetchTasks');
      return;
    }

    try {
      // Simple query with NO joins — ensures tasks always load
      // even if FK relationships or RLS policies have issues.
      final response = await _supabase
          .from('smart_tasks')
          .select()
          .eq('tenant_id', tenantId)
          .order('created_at', ascending: false);

      final List<TaskModel> loadedTasks = [];
      for (var row in (response as List<dynamic>)) {
        final map = row as Map<String, dynamic>;
        loadedTasks.add(TaskModel.fromJson(map));
      }

      _tasks = loadedTasks;
      notifyListeners();
      print('✅ [TaskService] Loaded ${_tasks.length} tasks');
    } catch (e, stackTrace) {
      print('❌ [TaskService] Error fetching tasks: $e');
      print('❌ [TaskService] Stack: $stackTrace');
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

  // ── Attachments ──

  /// Upload a file to Supabase Storage and attach it to a task.
  Future<void> addAttachment({
    required String taskId,
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null) throw Exception('No tenant ID');

    try {
      // Sanitize filename
      final safeFileName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final storagePath = 'tasks/attachments/$tenantId/$taskId/$safeFileName';

      // Upload to Supabase Storage
      await _supabase.storage.from('vinabike-assets').uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(contentType: mimeType, upsert: true),
          );

      // Get public URL
      final publicUrl =
          _supabase.storage.from('vinabike-assets').getPublicUrl(storagePath);

      // Build attachment metadata
      final attachment = {
        'name': fileName,
        'url': publicUrl,
        'type': mimeType,
        'size': bytes.length,
        'storage_path': storagePath,
        'uploaded_at': DateTime.now().toIso8601String(),
      };

      // Fetch current attachments from DB and append
      final current = await _supabase
          .from('smart_tasks')
          .select('attachments')
          .eq('id', taskId)
          .eq('tenant_id', tenantId)
          .single();

      final existingAttachments =
          List<Map<String, dynamic>>.from(current['attachments'] ?? []);
      existingAttachments.add(attachment);

      await _supabase
          .from('smart_tasks')
          .update({'attachments': existingAttachments})
          .eq('id', taskId)
          .eq('tenant_id', tenantId);

      // Refresh local cache
      await fetchTasks();
      print('✅ [TaskService] Attachment added: $fileName');
    } catch (e) {
      print('❌ [TaskService] Error adding attachment: $e');
      rethrow;
    }
  }

  /// Remove an attachment from a task (deletes from storage + updates JSONB).
  Future<void> removeAttachment({
    required String taskId,
    required String attachmentUrl,
  }) async {
    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null) throw Exception('No tenant ID');

    try {
      // Fetch current attachments
      final current = await _supabase
          .from('smart_tasks')
          .select('attachments')
          .eq('id', taskId)
          .eq('tenant_id', tenantId)
          .single();

      final existingAttachments =
          List<Map<String, dynamic>>.from(current['attachments'] ?? []);

      // Find the attachment to remove
      final toRemove =
          existingAttachments.where((a) => a['url'] == attachmentUrl).toList();

      // Delete from storage if we have the storage_path
      for (final att in toRemove) {
        final storagePath = att['storage_path'] as String?;
        if (storagePath != null) {
          try {
            await _supabase.storage
                .from('vinabike-assets')
                .remove([storagePath]);
          } catch (e) {
            print('⚠️ [TaskService] Could not delete from storage: $e');
          }
        }
      }

      // Update DB
      existingAttachments.removeWhere((a) => a['url'] == attachmentUrl);
      await _supabase
          .from('smart_tasks')
          .update({'attachments': existingAttachments})
          .eq('id', taskId)
          .eq('tenant_id', tenantId);

      // Refresh local cache
      await fetchTasks();
      print('✅ [TaskService] Attachment removed');
    } catch (e) {
      print('❌ [TaskService] Error removing attachment: $e');
      rethrow;
    }
  }
}
