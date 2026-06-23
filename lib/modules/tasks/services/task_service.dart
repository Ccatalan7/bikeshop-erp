import 'dart:async';

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
  bool _isDisposed = false;
  bool _realtimeSetupInFlight = false;
  String? _realtimeTenantId;
  RealtimeChannel? _tasksChannel;
  StreamSubscription<AuthState>? _authSubscription;
  Timer? _fallbackRefreshTimer;
  Timer? _realtimeRetryTimer;
  int _realtimeRetryAttempt = 0;

  List<TaskModel> get tasks => _tasks;

  TaskService(this._supabase, this._tenantService) {
    _authSubscription = _supabase.auth.onAuthStateChange.listen((data) {
      if (_isDisposed) return;

      if (data.event == AuthChangeEvent.signedOut || data.session == null) {
        unawaited(_handleSignedOut());
        return;
      }

      if (data.event == AuthChangeEvent.initialSession ||
          data.event == AuthChangeEvent.signedIn ||
          data.event == AuthChangeEvent.userUpdated) {
        unawaited(init(forceRefresh: true));
      }
    });

    unawaited(init());
  }

  Future<void> init({bool forceRefresh = false}) async {
    if (_isDisposed) return;
    if (!_isInit || forceRefresh) {
      await fetchTasks();
      _isInit = true;
    }
    await _setupTasksRealtime();
    _startFallbackRefresh();
  }

  Future<void> fetchTasks() async {
    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null) {
      if (_tasks.isNotEmpty) {
        _tasks = [];
        _safeNotify();
      }
      if (kDebugMode) {
        debugPrint('⚠️ [TaskService] No tenant ID, skipping fetchTasks');
      }
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
      for (final row in (response as List<dynamic>)) {
        final map = row as Map<String, dynamic>;
        loadedTasks.add(TaskModel.fromJson(map));
      }

      _tasks = loadedTasks;
      _sortTasks();
      _safeNotify();
      if (kDebugMode) {
        debugPrint('✅ [TaskService] Loaded ${_tasks.length} tasks');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ [TaskService] Error fetching tasks: $e');
        debugPrint('❌ [TaskService] Stack: $stackTrace');
      }
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
      _upsertTask(newTask);
      return newTask;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [TaskService] Error creating task: $e');
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
        _sortTasks();
        _safeNotify();
      } else {
        await fetchTasks();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [TaskService] Error updating task: $e');
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
      _safeNotify();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [TaskService] Error deleting task: $e');
      rethrow;
    }
  }

  Future<void> _setupTasksRealtime({bool force = false}) async {
    if (_isDisposed || _realtimeSetupInFlight) return;

    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null || tenantId.isEmpty) {
      _scheduleRealtimeReconnect('tenant context unavailable');
      return;
    }

    if (!force && _tasksChannel != null && _realtimeTenantId == tenantId) {
      return;
    }

    _realtimeSetupInFlight = true;
    try {
      _realtimeRetryTimer?.cancel();
      _realtimeRetryTimer = null;

      await _teardownTasksRealtime(cancelRetry: false);

      late final RealtimeChannel channel;
      channel = _supabase
          .channel('smart-tasks-$tenantId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'smart_tasks',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'tenant_id',
              value: tenantId,
            ),
            callback: _handleTaskRealtimeChange,
          )
          .subscribe((status, error) {
        _handleTasksRealtimeStatus(channel, status, error);
      });

      _tasksChannel = channel;
      _realtimeTenantId = tenantId;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [TaskService] Realtime setup failed: $e');
      }
      _scheduleRealtimeReconnect('setup failed');
    } finally {
      _realtimeSetupInFlight = false;
    }
  }

  void _handleTasksRealtimeStatus(
    RealtimeChannel channel,
    RealtimeSubscribeStatus status,
    Object? error,
  ) {
    if (!identical(channel, _tasksChannel) || _isDisposed) return;

    switch (status) {
      case RealtimeSubscribeStatus.subscribed:
        _realtimeRetryAttempt = 0;
        _realtimeRetryTimer?.cancel();
        _realtimeRetryTimer = null;
        if (kDebugMode) {
          debugPrint(
              '✅ [TaskService] Realtime active for tenant $_realtimeTenantId');
        }
        unawaited(fetchTasks());
        break;
      case RealtimeSubscribeStatus.channelError:
        if (kDebugMode) {
          debugPrint('❌ [TaskService] Realtime channel error: $error');
        }
        _scheduleRealtimeReconnect('channel error');
        break;
      case RealtimeSubscribeStatus.closed:
        if (kDebugMode) {
          debugPrint('⚠️ [TaskService] Realtime channel closed');
        }
        _scheduleRealtimeReconnect('channel closed');
        break;
      case RealtimeSubscribeStatus.timedOut:
        if (kDebugMode) {
          debugPrint('⚠️ [TaskService] Realtime subscription timed out');
        }
        _scheduleRealtimeReconnect('subscribe timeout');
        break;
    }
  }

  void _handleTaskRealtimeChange(PostgresChangePayload payload) {
    if (_isDisposed) return;

    try {
      switch (payload.eventType) {
        case PostgresChangeEvent.insert:
        case PostgresChangeEvent.update:
          final record = payload.newRecord;
          if (record.isEmpty) {
            unawaited(fetchTasks());
            return;
          }
          _upsertTask(TaskModel.fromJson(record));
          break;
        case PostgresChangeEvent.delete:
          final id = payload.oldRecord['id']?.toString();
          if (id == null || id.isEmpty) {
            unawaited(fetchTasks());
            return;
          }
          _tasks.removeWhere((task) => task.id == id);
          _safeNotify();
          break;
        default:
          unawaited(fetchTasks());
          break;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [TaskService] Error applying realtime task change: $e');
      }
      unawaited(fetchTasks());
    }
  }

  void _upsertTask(TaskModel task) {
    if (task.id == null || task.id!.isEmpty) {
      _tasks.insert(0, task);
    } else {
      final index = _tasks.indexWhere((item) => item.id == task.id);
      if (index == -1) {
        _tasks.insert(0, task);
      } else {
        _tasks[index] = task;
      }
    }
    _sortTasks();
    _safeNotify();
  }

  void _sortTasks() {
    _tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  void _startFallbackRefresh() {
    if (_isDisposed ||
        _fallbackRefreshTimer?.isActive == true ||
        _realtimeTenantId == null) {
      return;
    }
    _fallbackRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(fetchTasks()),
    );
  }

  void _scheduleRealtimeReconnect(String reason) {
    if (_isDisposed ||
        _supabase.auth.currentUser == null ||
        (_realtimeRetryTimer?.isActive ?? false)) {
      return;
    }

    const retryDelays = <Duration>[
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
      Duration(seconds: 20),
      Duration(seconds: 30),
    ];
    final nextAttempt = _realtimeRetryAttempt + 1;
    final delayIndex = nextAttempt > retryDelays.length
        ? retryDelays.length - 1
        : nextAttempt - 1;
    final delay = retryDelays[delayIndex];
    _realtimeRetryAttempt = nextAttempt;

    if (kDebugMode) {
      debugPrint(
          '🔁 [TaskService] Realtime reconnect in ${delay.inSeconds}s ($reason)');
    }

    _realtimeRetryTimer = Timer(delay, () {
      _realtimeRetryTimer = null;
      unawaited(_setupTasksRealtime(force: true));
    });
  }

  Future<void> _teardownTasksRealtime({bool cancelRetry = true}) async {
    if (cancelRetry) {
      _realtimeRetryTimer?.cancel();
      _realtimeRetryTimer = null;
      _realtimeRetryAttempt = 0;
    }

    final channel = _tasksChannel;
    _tasksChannel = null;
    _realtimeTenantId = null;
    if (channel != null) {
      await channel.unsubscribe();
    }
  }

  Future<void> _handleSignedOut() async {
    _isInit = false;
    _fallbackRefreshTimer?.cancel();
    _fallbackRefreshTimer = null;
    await _teardownTasksRealtime();
    if (_tasks.isNotEmpty) {
      _tasks = [];
      _safeNotify();
    }
  }

  void _safeNotify() {
    if (!_isDisposed) notifyListeners();
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
      if (kDebugMode) {
        debugPrint('✅ [TaskService] Attachment added: $fileName');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [TaskService] Error adding attachment: $e');
      }
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
            if (kDebugMode) {
              debugPrint('⚠️ [TaskService] Could not delete from storage: $e');
            }
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
      if (kDebugMode) {
        debugPrint('✅ [TaskService] Attachment removed');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [TaskService] Error removing attachment: $e');
      }
      rethrow;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _authSubscription?.cancel();
    _fallbackRefreshTimer?.cancel();
    _realtimeRetryTimer?.cancel();
    unawaited(_tasksChannel?.unsubscribe() ?? Future.value());
    super.dispose();
  }
}
