import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/tasks/models/task_model.dart';
import 'package:vinabike_erp/shared/services/authority_scoped_cache.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

class TaskService extends ChangeNotifier {
  final SupabaseClient _supabase;
  final TenantService _tenantService;

  // In-memory cache
  List<TaskModel> _tasks = [];
  bool _isInit = false;
  bool _isDisposed = false;
  final AuthorityCacheScope _cacheScope = AuthorityCacheScope();
  late final AuthorityScopedLoad<List<TaskModel>> _tasksLoad =
      AuthorityScopedLoad<List<TaskModel>>(_cacheScope);
  String? _realtimeTenantId;
  RealtimeChannel? _tasksChannel;
  int _realtimeChannelSerial = 0;
  StreamSubscription<AuthState>? _authSubscription;
  Timer? _fallbackRefreshTimer;
  Timer? _realtimeRetryTimer;
  int _realtimeRetryAttempt = 0;

  List<TaskModel> get tasks => _tasks;
  ErpAuthorityScopeKey? get authorityScope => _cacheScope.key;

  TaskService(this._supabase, this._tenantService) {
    _authSubscription = _supabase.auth.onAuthStateChange.listen((data) {
      if (_isDisposed) return;

      if (data.event == AuthChangeEvent.signedOut || data.session == null) {
        bindAuthorityScope(userId: null, tenantId: null);
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

  void bindAuthorityScope({
    required String? userId,
    required String? tenantId,
  }) {
    if (!_cacheScope.bind(userId: userId, tenantId: tenantId)) return;
    _clearAuthorityOwnedState();
  }

  AuthorityScopeResolution _resolveAuthorityScope({
    required String? userId,
    required String? tenantId,
  }) {
    final resolution = _cacheScope.resolve(
      userId: userId,
      tenantId: tenantId,
    );
    if (resolution.didChange) _clearAuthorityOwnedState();
    return resolution;
  }

  void _clearAuthorityOwnedState() {
    final hadTasks = _tasks.isNotEmpty;
    _tasksLoad.detach();
    _isInit = false;
    _fallbackRefreshTimer?.cancel();
    _fallbackRefreshTimer = null;
    final oldChannel = _detachTasksRealtime();
    _tasks = [];
    if (oldChannel != null) {
      unawaited(oldChannel.unsubscribe());
    }
    if (hadTasks) _safeNotify();
  }

  Future<void> init({bool forceRefresh = false}) async {
    if (_isDisposed) return;
    if (!_isInit || forceRefresh) {
      AuthorityCacheLease? loadedLease;
      try {
        loadedLease = await _fetchTasksForCurrentAuthority();
      } on AuthorityScopeChangedException {
        return;
      }
      if (_isDisposed ||
          loadedLease == null ||
          !_cacheScope.owns(loadedLease) ||
          _supabase.auth.currentUser?.id != loadedLease.scope.userId) {
        return;
      }
      _isInit = true;
    }
    await _setupTasksRealtime();
    _startFallbackRefresh();
  }

  Future<void> fetchTasks() async {
    await _fetchTasksForCurrentAuthority();
  }

  /// Returns truthful completion evidence for the login preload coordinator.
  ///
  /// Interactive refresh callers keep using [fetchTasks], while preloading
  /// needs to distinguish a successful empty result from an internal failure.
  Future<ErpAuthorityScopeKey?> fetchTasksForPreload() async {
    return (await _fetchTasksForCurrentAuthority())?.scope;
  }

  Future<AuthorityCacheLease?> _fetchTasksForCurrentAuthority() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      _resolveAuthorityScope(userId: null, tenantId: null);
      return null;
    }

    final tenantId = await _tenantService.getTenantId();
    if (_supabase.auth.currentUser?.id != userId) return null;
    if (tenantId == null || tenantId.isEmpty) {
      _resolveAuthorityScope(userId: null, tenantId: null);
      if (kDebugMode) {
        debugPrint('⚠️ [TaskService] No tenant ID, skipping fetchTasks');
      }
      return null;
    }

    final resolution = _resolveAuthorityScope(
      userId: userId,
      tenantId: tenantId,
    );
    if (resolution == AuthorityScopeResolution.rejectedTenantChange) {
      throw const AuthorityScopeChangedException();
    }
    final requestedLease = _cacheScope.capture();
    if (requestedLease == null) return null;

    try {
      await _tasksLoad.run(
        load: (lease) async {
          // Simple query with NO joins — ensures tasks always load
          // even if FK relationships or RLS policies have issues.
          final response = await _supabase
              .from('smart_tasks')
              .select()
              .eq('tenant_id', lease.scope.tenantId)
              .order('created_at', ascending: false);

          final loadedTasks = <TaskModel>[];
          for (final row in (response as List<dynamic>)) {
            final map = row as Map<String, dynamic>;
            if (map['tenant_id']?.toString() != lease.scope.tenantId) {
              throw StateError(
                'Task query returned data outside the authority tenant',
              );
            }
            loadedTasks.add(TaskModel.fromJson(map));
          }
          loadedTasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return loadedTasks;
        },
        publish: (loadedTasks, _) {
          _tasks = loadedTasks;
          _safeNotify();
        },
      );
      if (kDebugMode) {
        debugPrint('✅ [TaskService] Loaded ${_tasks.length} tasks');
      }
      unawaited(_setupTasksRealtime());
      _startFallbackRefresh();
      return _cacheScope.owns(requestedLease) ? requestedLease : null;
    } on AuthorityScopeChangedException {
      // A newer sign-in/tenant generation owns the cache now.
      return null;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ [TaskService] Error fetching tasks: $e');
        debugPrint('❌ [TaskService] Stack: $stackTrace');
      }
      return null;
    }
  }

  Future<TaskModel> createTask(TaskModel task) async {
    final lease = await _requireAuthorityLease();
    final tenantId = lease.scope.tenantId;

    try {
      final data = task.toJson();
      data.remove('id');
      data['tenant_id'] = tenantId;
      data.remove('created_at');
      data.remove('updated_at');

      final response =
          await _supabase.from('smart_tasks').insert(data).select().single();

      final newTask = TaskModel.fromJson(response);
      if (newTask.tenantId != tenantId) {
        throw StateError(
          'Task insert returned data outside the authority tenant',
        );
      }
      if (_cacheScope.owns(lease)) {
        _upsertTask(newTask);
      }
      return newTask;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [TaskService] Error creating task: $e');
      rethrow;
    }
  }

  Future<void> updateTask(TaskModel task) async {
    final lease = await _requireAuthorityLease();
    final tenantId = lease.scope.tenantId;
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

      if (!_cacheScope.owns(lease)) return;

      // Update local cache
      final index = _tasks.indexWhere((t) => t.id == task.id);
      if (index != -1) {
        _tasks[index] = task.tenantId == tenantId
            ? task
            : task.copyWith(tenantId: tenantId);
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
    final lease = await _requireAuthorityLease();
    final tenantId = lease.scope.tenantId;

    try {
      await _supabase
          .from('smart_tasks')
          .delete()
          .eq('id', taskId)
          .eq('tenant_id', tenantId);

      if (!_cacheScope.owns(lease)) return;
      _tasks.removeWhere((t) => t.id == taskId);
      _safeNotify();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [TaskService] Error deleting task: $e');
      rethrow;
    }
  }

  Future<AuthorityCacheLease> _requireAuthorityLease() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      _resolveAuthorityScope(userId: null, tenantId: null);
      throw const AuthorityScopeChangedException();
    }
    final tenantId = await _tenantService.getTenantId();
    if (_supabase.auth.currentUser?.id != userId) {
      throw const AuthorityScopeChangedException();
    }
    if (tenantId == null || tenantId.isEmpty) {
      _resolveAuthorityScope(userId: null, tenantId: null);
      throw const AuthorityScopeChangedException();
    }
    final resolution = _resolveAuthorityScope(
      userId: userId,
      tenantId: tenantId,
    );
    if (resolution == AuthorityScopeResolution.rejectedTenantChange) {
      throw const AuthorityScopeChangedException();
    }
    final lease = _cacheScope.capture();
    if (lease == null) throw const AuthorityScopeChangedException();
    return lease;
  }

  Future<void> _setupTasksRealtime({bool force = false}) async {
    if (_isDisposed) return;
    final lease = _cacheScope.capture();
    if (lease == null) {
      _scheduleRealtimeReconnect('tenant context unavailable');
      return;
    }
    final tenantId = lease.scope.tenantId;

    if (!force && _tasksChannel != null && _realtimeTenantId == tenantId) {
      return;
    }

    try {
      _realtimeRetryTimer?.cancel();
      _realtimeRetryTimer = null;

      final oldChannel = _detachTasksRealtime(cancelRetry: false);
      if (oldChannel != null) {
        unawaited(oldChannel.unsubscribe());
      }

      late final RealtimeChannel channel;
      channel = _supabase
          .channel(
            'smart-tasks-$tenantId-${lease.generation}-${++_realtimeChannelSerial}',
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'smart_tasks',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'tenant_id',
              value: tenantId,
            ),
            callback: (payload) =>
                _handleTaskRealtimeChange(channel, lease, payload),
          )
          .subscribe((status, error) {
        _handleTasksRealtimeStatus(channel, lease, status, error);
      });

      if (!_cacheScope.owns(lease) || _isDisposed) {
        await channel.unsubscribe();
        return;
      }
      _tasksChannel = channel;
      _realtimeTenantId = tenantId;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [TaskService] Realtime setup failed: $e');
      }
      _scheduleRealtimeReconnect('setup failed');
    }
  }

  void _handleTasksRealtimeStatus(
    RealtimeChannel channel,
    AuthorityCacheLease lease,
    RealtimeSubscribeStatus status,
    Object? error,
  ) {
    if (!identical(channel, _tasksChannel) ||
        !_cacheScope.owns(lease) ||
        _isDisposed) {
      return;
    }

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

  void _handleTaskRealtimeChange(
    RealtimeChannel channel,
    AuthorityCacheLease lease,
    PostgresChangePayload payload,
  ) {
    if (_isDisposed ||
        !_cacheScope.owns(lease) ||
        !identical(channel, _tasksChannel)) {
      return;
    }

    try {
      switch (payload.eventType) {
        case PostgresChangeEvent.insert:
        case PostgresChangeEvent.update:
          final record = payload.newRecord;
          if (record.isEmpty ||
              record['tenant_id']?.toString() != lease.scope.tenantId) {
            unawaited(fetchTasks());
            return;
          }
          _upsertTask(TaskModel.fromJson(record));
          break;
        case PostgresChangeEvent.delete:
          final oldRecord = payload.oldRecord;
          final recordTenantId = oldRecord['tenant_id']?.toString();
          if (recordTenantId != null &&
              recordTenantId.isNotEmpty &&
              recordTenantId != lease.scope.tenantId) {
            return;
          }
          final id = oldRecord['id']?.toString();
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

  RealtimeChannel? _detachTasksRealtime({bool cancelRetry = true}) {
    if (cancelRetry) {
      _realtimeRetryTimer?.cancel();
      _realtimeRetryTimer = null;
      _realtimeRetryAttempt = 0;
    }

    final channel = _tasksChannel;
    _tasksChannel = null;
    _realtimeTenantId = null;
    return channel;
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
    final oldChannel = _detachTasksRealtime();
    if (oldChannel != null) {
      unawaited(oldChannel.unsubscribe());
    }
    super.dispose();
  }
}
