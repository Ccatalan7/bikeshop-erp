import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/mechanic_job_visibility_policy.dart';
import 'package:vinabike_erp/modules/sales/models/sales_models.dart';
import 'package:vinabike_erp/modules/tasks/models/smart_task_event.dart';
import 'package:vinabike_erp/modules/tasks/models/smart_task_job_item.dart';
import 'package:vinabike_erp/modules/tasks/models/task_assignment_principal.dart';
import 'package:vinabike_erp/modules/tasks/models/task_model.dart';
import 'package:vinabike_erp/shared/services/authority_scoped_cache.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

/// Otra tarea activa ya cubre alguno de los servicios pedidos: la UI ofrece
/// colaborar o traspasar, nunca decide sola.
class TaskOverlapException implements Exception {
  TaskOverlapException(this.overlaps);

  /// [{task_id, title, status, assigned_to, job_item_ids}]
  final List<Map<String, dynamic>> overlaps;
}

/// La tarea cambió desde que el cliente la leyó (conflicto optimista):
/// se refresca y se reintenta con la versión vigente.
class TaskVersionConflictException implements Exception {
  TaskVersionConflictException(this.message);
  final String message;
}

/// `mechanic_jobs` también conserva un FK legacy `assigned_to -> customers`.
/// PostgREST exige nombrar el FK del cliente real o rechaza el embed por
/// ambiguo y el selector de trabajos queda vacío.
@visibleForTesting
const taskLinkableJobCustomerEmbed =
    'customers!mechanic_jobs_customer_id_fkey(name)';

class TaskService extends ChangeNotifier {
  final SupabaseClient _supabase;
  final TenantService _tenantService;

  // In-memory cache
  List<TaskModel> _tasks = [];
  Map<String, List<SmartTaskJobItem>> _jobItemsByTask = {};
  Map<String, TaskLinkableJob> _jobHeadersById = {};
  Map<String, Map<String, dynamic>> _userStateByTask = {};
  static const _uuid = Uuid();
  bool _isInit = false;
  bool _isDisposed = false;
  final AuthorityCacheScope _cacheScope = AuthorityCacheScope();
  late final AuthorityScopedLoad<_TaskTrayLoad> _tasksLoad =
      AuthorityScopedLoad<_TaskTrayLoad>(_cacheScope);
  String? _realtimeTenantId;
  RealtimeChannel? _tasksChannel;
  int _realtimeChannelSerial = 0;
  StreamSubscription<AuthState>? _authSubscription;
  Timer? _fallbackRefreshTimer;
  Timer? _realtimeRetryTimer;
  int _realtimeRetryAttempt = 0;

  List<TaskModel> get tasks => _tasks;
  ErpAuthorityScopeKey? get authorityScope => _cacheScope.key;

  /// Servicios del trabajo respaldando cada tarea (snapshot + invalidación).
  List<SmartTaskJobItem> jobItemsOf(String taskId) =>
      _jobItemsByTask[taskId] ?? const [];

  /// Identidad mínima del trabajo para tareas/notas con `linked_job_id` pero
  /// sin servicios vinculados (hidratada aparte, acotada por IDs).
  TaskLinkableJob? jobHeaderOf(TaskModel task) =>
      task.linkedJobId == null ? null : _jobHeadersById[task.linkedJobId];

  /// Estado personal (visto/pin/snooze) de la tarea para el usuario actual.
  Map<String, dynamic>? userStateOf(String taskId) => _userStateByTask[taskId];

  String? get currentUserId => _supabase.auth.currentUser?.id;

  /// Verdad del badge personal: asignadas a mí sin ver en su versión actual
  /// (o por aceptar), no snoozeadas y no terminadas.
  int get myInboxBadgeCount {
    final uid = currentUserId;
    if (uid == null) return 0;
    final now = DateTime.now();
    return _tasks.where((task) {
      if (task.assignedTo != uid || task.isDone) return false;
      final state = _userStateByTask[task.id];
      final snoozedUntil =
          DateTime.tryParse(state?['snoozed_until']?.toString() ?? '');
      if (snoozedUntil != null && snoozedUntil.isAfter(now)) return false;
      final seenVersion = (state?['seen_version'] as num?)?.toInt();
      final unseen = seenVersion == null || seenVersion < task.version;
      return unseen || task.awaitsAcknowledgement;
    }).length;
  }

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
    _jobItemsByTask = {};
    _jobHeadersById = {};
    _userStateByTask = {};
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
          await _hydrateTaskContexts(lease, loadedTasks);
          loadedTasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));

          final linkRows = await _supabase
              .from('smart_task_job_items')
              .select()
              .eq('tenant_id', lease.scope.tenantId);
          final linksByTask = <String, List<SmartTaskJobItem>>{};
          for (final row in (linkRows as List<dynamic>)) {
            final link = SmartTaskJobItem.fromJson(
                Map<String, dynamic>.from(row as Map));
            linksByTask.putIfAbsent(link.taskId, () => []).add(link);
          }

          // RLS ya limita a las filas propias; el filtro es cinturón.
          final stateRows = await _supabase
              .from('smart_task_user_state')
              .select()
              .eq('user_id', lease.scope.userId);
          final stateByTask = <String, Map<String, dynamic>>{};
          for (final row in (stateRows as List<dynamic>)) {
            final map = Map<String, dynamic>.from(row as Map);
            stateByTask[map['task_id'].toString()] = map;
          }

          // Trabajos vinculados SIN servicios: su identidad no viene en los
          // links; se hidrata en una lectura secundaria acotada por IDs.
          final headerIds = <String>{
            for (final task in loadedTasks)
              if (task.linkedJobId != null &&
                  !(linksByTask[task.id]?.isNotEmpty ?? false))
                task.linkedJobId!,
          };
          final headersById = <String, TaskLinkableJob>{};
          if (headerIds.isNotEmpty) {
            final headerRows = await _supabase
                .from('mechanic_jobs')
                .select('id, job_number, status, client_request, deleted_at, '
                    '$taskLinkableJobCustomerEmbed')
                .inFilter('id', headerIds.toList());
            for (final row in (headerRows as List<dynamic>)) {
              final header = TaskLinkableJob.fromJson(
                  Map<String, dynamic>.from(row as Map));
              headersById[header.id] = header;
            }
          }

          return _TaskTrayLoad(
              loadedTasks, linksByTask, headersById, stateByTask);
        },
        publish: (loaded, _) {
          _tasks = loaded.tasks;
          _jobItemsByTask = loaded.jobItemsByTask;
          _jobHeadersById = loaded.jobHeadersById;
          _userStateByTask = loaded.userStateByTask;
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

  /// Hidrata sólo la identidad visible de los contextos no-Taller. Se mantiene
  /// fuera del SELECT principal para que una relación o RLS defectuosa no deje
  /// la bandeja completa sin tareas.
  Future<void> _hydrateTaskContexts(
    AuthorityCacheLease lease,
    List<TaskModel> tasks,
  ) async {
    final customerIds = <String>{
      for (final task in tasks)
        if (task.linkedCustomerId != null) task.linkedCustomerId!,
    };
    final supplierIds = <String>{
      for (final task in tasks)
        if (task.linkedSupplierId != null) task.linkedSupplierId!,
    };
    final salesIds = <String>{
      for (final task in tasks)
        if (task.linkedSalesInvoiceId != null) task.linkedSalesInvoiceId!,
    };
    final purchaseIds = <String>{
      for (final task in tasks)
        if (task.linkedPurchaseInvoiceId != null) task.linkedPurchaseInvoiceId!,
    };

    final customerNames = <String, String>{};
    final supplierNames = <String, String>{};
    final salesNumbers = <String, String>{};
    final purchaseNumbers = <String, String>{};

    Future<void> collect(
      String table,
      String projection,
      Set<String> ids,
      Map<String, String> target,
      String valueColumn,
    ) async {
      if (ids.isEmpty) return;
      final rows = await _supabase
          .from(table)
          .select('id, tenant_id, $projection')
          .eq('tenant_id', lease.scope.tenantId)
          .inFilter('id', ids.toList());
      _assertOwnedLease(lease);
      for (final row in (rows as List<dynamic>)) {
        final map = Map<String, dynamic>.from(row as Map);
        if (map['tenant_id']?.toString() != lease.scope.tenantId) {
          throw StateError('$table context query crossed the authority tenant');
        }
        final value = map[valueColumn]?.toString().trim();
        if (value != null && value.isNotEmpty) {
          target[map['id'].toString()] = value;
        }
      }
    }

    await collect('customers', 'name', customerIds, customerNames, 'name');
    await collect('suppliers', 'name', supplierIds, supplierNames, 'name');
    await collect('sales_invoices', 'invoice_number', salesIds, salesNumbers,
        'invoice_number');
    await collect('purchase_invoices', 'invoice_number', purchaseIds,
        purchaseNumbers, 'invoice_number');

    for (var index = 0; index < tasks.length; index++) {
      final task = tasks[index];
      tasks[index] = task.copyWith(
        linkedCustomerName: task.linkedCustomerId == null
            ? null
            : customerNames[task.linkedCustomerId],
        linkedSupplierName: task.linkedSupplierId == null
            ? null
            : supplierNames[task.linkedSupplierId],
        linkedSalesInvoiceNumber: task.linkedSalesInvoiceId == null
            ? null
            : salesNumbers[task.linkedSalesInvoiceId],
        linkedPurchaseInvoiceNumber: task.linkedPurchaseInvoiceId == null
            ? null
            : purchaseNumbers[task.linkedPurchaseInvoiceId],
      );
    }
  }

  /// Compatibilidad: los llamadores antiguos entran igual por la RPC, para
  /// que ninguna tarea nazca sin su rastro de eventos.
  Future<TaskModel> createTask(TaskModel task) {
    return createTrayTask(
      title: task.title,
      description: task.description,
      kind: task.kind,
      visibility: task.visibility,
      priority: task.priority,
      dueDate: task.dueDate,
      assignedTo: task.assignedTo,
      linkedJobId: task.linkedJobId,
      linkedCustomerId: task.linkedCustomerId,
      linkedSupplierId: task.linkedSupplierId,
      linkedPurchaseInvoiceId: task.linkedPurchaseInvoiceId,
      linkedSalesInvoiceId: task.linkedSalesInvoiceId,
    );
  }

  /// Puente de compatibilidad: los llamadores antiguos entregan el modelo
  /// completo; aquí se convierte en los comandos RPC equivalentes (diff
  /// contra la caché), para que la autoridad, el versionado, el ledger y las
  /// notificaciones rijan también para la UI legada. Sin comandos que emitir,
  /// no escribe nada.
  Future<void> updateTask(TaskModel task) async {
    final id = task.id;
    if (id == null) throw Exception('Task ID cannot be null for update');
    final current = _tasks.where((cached) => cached.id == id).firstOrNull;

    final details = <String, dynamic>{};
    if (current == null || task.title != current.title) {
      details['title'] = task.title;
    }
    if (current == null || task.description != current.description) {
      details['description'] = task.description ?? '';
    }
    if (current == null || task.priority != current.priority) {
      details['priority'] = taskPriorityWire(task.priority);
    }
    if (current == null || task.dueDate != current.dueDate) {
      details['due_date'] = task.dueDate?.toIso8601String() ?? '';
    }
    if (current != null && task.linkedCustomerId != current.linkedCustomerId) {
      details['linked_customer_id'] = task.linkedCustomerId ?? '';
    }
    if (current != null && task.linkedSupplierId != current.linkedSupplierId) {
      details['linked_supplier_id'] = task.linkedSupplierId ?? '';
    }
    if (current != null &&
        task.linkedPurchaseInvoiceId != current.linkedPurchaseInvoiceId) {
      details['linked_purchase_invoice_id'] =
          task.linkedPurchaseInvoiceId ?? '';
    }
    if (current != null &&
        task.linkedSalesInvoiceId != current.linkedSalesInvoiceId) {
      details['linked_sales_invoice_id'] = task.linkedSalesInvoiceId ?? '';
    }
    if (details.isNotEmpty) {
      await sendCommand(id, command: 'update_details', payload: details);
    }

    if (current != null && task.visibility != current.visibility) {
      await setTaskVisibility(id, task.visibility);
    }

    if (current != null && task.linkedJobId != current.linkedJobId) {
      // La UI legada vincula el trabajo sin elegir servicios.
      await setTaskJobItems(id, jobId: task.linkedJobId);
    }

    if (current != null && task.assignedTo != current.assignedTo) {
      await assignTask(id, task.assignedTo);
    }

    if (current == null || task.status != current.status) {
      final from = current?.status;
      switch (task.status) {
        case TaskStatus.completed:
          await completeTask(id);
          break;
        case TaskStatus.cancelled:
          await cancelTask(id);
          break;
        case TaskStatus.inProgress:
          from == TaskStatus.blocked
              ? await unblockTask(id)
              : await startTask(id);
          break;
        case TaskStatus.blocked:
          await blockTask(id, task.blockedReason ?? 'Bloqueada desde edición');
          break;
        case TaskStatus.pending:
          if (from == TaskStatus.blocked) {
            await unblockTask(id);
          } else if (from == TaskStatus.completed ||
              from == TaskStatus.cancelled) {
            await reopenTask(id);
          }
          // pending→pending o inProgress→pending sin comando dedicado: la
          // vuelta a pendiente desde en-curso no existe como acción de la
          // UI nueva y la legada solo alterna con completada.
          break;
      }
    }
  }

  /// La bandeja cancela, no borra: el DELETE de cliente está revocado en la
  /// base y el ledger bloquea el borrado físico. Contrato explícito para los
  /// llamadores antiguos.
  @Deprecated('La bandeja cancela; usa cancelTask')
  Future<void> deleteTask(String taskId) => cancelTask(taskId);

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

  void _assertOwnedLease(AuthorityCacheLease lease) {
    if (_isDisposed ||
        !_cacheScope.owns(lease) ||
        _supabase.auth.currentUser?.id != lease.scope.userId) {
      throw const AuthorityScopeChangedException();
    }
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
          // Los vínculos a servicios cambian junto con la versión de la
          // tarea; se refrescan por tarea, con el mismo lease.
          final changedId = record['id']?.toString();
          if (changedId != null && changedId.isNotEmpty) {
            unawaited(_refreshTaskLinks(lease, changedId));
            unawaited(_refreshTaskContext(lease, changedId));
          }
          final linkedJobId = record['linked_job_id']?.toString();
          if (linkedJobId != null &&
              linkedJobId.isNotEmpty &&
              !_jobHeadersById.containsKey(linkedJobId)) {
            unawaited(_refreshJobHeader(lease, linkedJobId));
          }
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
          _jobItemsByTask.remove(id);
          _userStateByTask.remove(id);
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

  // ── Bandeja: comandos idempotentes y versionados ────────────────────────
  //
  // Toda mutación de ciclo de vida va por RPC (`smart_task_create_v1` /
  // `smart_task_command_v1`); los updates directos de arriba quedan como
  // compatibilidad legada durante el cutover.

  Future<void> _refreshTaskLinks(
    AuthorityCacheLease lease,
    String taskId,
  ) async {
    try {
      final rows = await _supabase
          .from('smart_task_job_items')
          .select()
          .eq('task_id', taskId);
      if (_isDisposed || !_cacheScope.owns(lease)) return;
      final links = (rows as List<dynamic>)
          .map((row) =>
              SmartTaskJobItem.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList()
        ..sort((a, b) => a.linkedAt.compareTo(b.linkedAt));
      if (links.isEmpty) {
        _jobItemsByTask.remove(taskId);
      } else {
        _jobItemsByTask[taskId] = links;
      }
      _safeNotify();
    } catch (_) {
      // El fallback de 30 s reconcilia.
    }
  }

  Future<void> _refreshTaskContext(
    AuthorityCacheLease lease,
    String taskId,
  ) async {
    try {
      final current = _tasks.where((task) => task.id == taskId).firstOrNull;
      if (current == null) return;
      final expectedVersion = current.version;
      final hydrated = <TaskModel>[current];
      await _hydrateTaskContexts(lease, hydrated);
      if (_isDisposed || !_cacheScope.owns(lease)) return;
      final latest = _tasks.where((task) => task.id == taskId).firstOrNull;
      if (latest == null || latest.version != expectedVersion) return;
      _upsertTask(hydrated.single);
    } catch (_) {
      // El fallback de 30 s reconcilia sin esconder la tarea base.
    }
  }

  Future<void> _refreshJobHeader(
    AuthorityCacheLease lease,
    String jobId,
  ) async {
    try {
      final rows = await _supabase
          .from('mechanic_jobs')
          .select('id, job_number, status, client_request, deleted_at, '
              '$taskLinkableJobCustomerEmbed')
          .eq('id', jobId)
          .limit(1);
      if (_isDisposed || !_cacheScope.owns(lease)) return;
      final list = rows as List<dynamic>;
      if (list.isEmpty) return;
      final header =
          TaskLinkableJob.fromJson(Map<String, dynamic>.from(list.first));
      _jobHeadersById[header.id] = header;
      _safeNotify();
    } catch (_) {
      // El fallback de 30 s reconcilia.
    }
  }

  Never _rethrowCommandError(Object error) {
    if (error is PostgrestException) {
      if (error.code == '40001') {
        throw TaskVersionConflictException(error.message);
      }
      if (error.hint == 'job_items_overlap' && error.details != null) {
        try {
          final decoded = jsonDecode(error.details!.toString());
          if (decoded is List) {
            throw TaskOverlapException(decoded
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList());
          }
        } on FormatException {
          // El detail no era JSON: cae al rethrow genérico.
        }
      }
    }
    throw error; // ignore: only_throw_errors
  }

  Future<TaskModel> _taskFromCommandResult(
    AuthorityCacheLease lease,
    Map<String, dynamic> result,
  ) async {
    _assertOwnedLease(lease);
    final taskJson = Map<String, dynamic>.from(result['task'] as Map);
    final task = TaskModel.fromJson(taskJson);
    _upsertTask(task);
    if (task.id != null) {
      unawaited(_refreshTaskLinks(lease, task.id!));
      unawaited(_refreshTaskContext(lease, task.id!));
    }
    return task;
  }

  /// Crea una tarea de bandeja por RPC. Un [TaskOverlapException] significa
  /// que otros ya cubren esos servicios y la UI debe pedir la decisión
  /// (`overlapDecision`: 'collaborate' | 'transfer').
  Future<TaskModel> createTrayTask({
    required String title,
    String? description,
    TaskKind kind = TaskKind.task,
    TaskVisibility visibility = TaskVisibility.team,
    TaskPriority priority = TaskPriority.normal,
    DateTime? dueDate,
    String? assignedTo,
    String? linkedJobId,
    List<String>? jobItemIds,
    String? overlapDecision,
    String? linkedCustomerId,
    String? linkedSupplierId,
    String? linkedPurchaseInvoiceId,
    String? linkedSalesInvoiceId,
    String? idempotencyKey,
  }) async {
    final lease = await _requireAuthorityLease();
    final payload = <String, dynamic>{
      'title': title,
      if (description != null && description.isNotEmpty)
        'description': description,
      'task_kind': TaskModel.kindToString(kind),
      'visibility': TaskModel.visibilityToString(visibility),
      'priority': taskPriorityWire(priority),
      if (dueDate != null) 'due_date': dueDate.toIso8601String(),
      if (assignedTo != null) 'assigned_to': assignedTo,
      if (linkedJobId != null) 'linked_job_id': linkedJobId,
      if (jobItemIds != null) 'job_item_ids': jobItemIds,
      if (overlapDecision != null) 'overlap_decision': overlapDecision,
      if (linkedCustomerId != null) 'linked_customer_id': linkedCustomerId,
      if (linkedSupplierId != null) 'linked_supplier_id': linkedSupplierId,
      if (linkedPurchaseInvoiceId != null)
        'linked_purchase_invoice_id': linkedPurchaseInvoiceId,
      if (linkedSalesInvoiceId != null)
        'linked_sales_invoice_id': linkedSalesInvoiceId,
    };
    try {
      final result = await _supabase.rpc('smart_task_create_v1', params: {
        'p_payload': payload,
        'p_idempotency_key': idempotencyKey ?? _uuid.v4(),
      });
      return _taskFromCommandResult(
          lease, Map<String, dynamic>.from(result as Map));
    } catch (error) {
      _rethrowCommandError(error);
    }
  }

  /// Comando de ciclo de vida versionado. [expectedVersion] null omite el
  /// chequeo optimista (para acciones idempotentes como acknowledge).
  Future<TaskModel> sendCommand(
    String taskId, {
    required String command,
    int? expectedVersion,
    Map<String, dynamic> payload = const {},
    String? idempotencyKey,
  }) async {
    final lease = await _requireAuthorityLease();
    try {
      final result = await _supabase.rpc('smart_task_command_v1', params: {
        'p_task_id': taskId,
        'p_expected_version': expectedVersion,
        'p_command': command,
        'p_payload': payload,
        'p_idempotency_key': idempotencyKey ?? _uuid.v4(),
      });
      return _taskFromCommandResult(
          lease, Map<String, dynamic>.from(result as Map));
    } catch (error) {
      _rethrowCommandError(error);
    }
  }

  Future<TaskModel> acknowledgeTask(String taskId) =>
      sendCommand(taskId, command: 'acknowledge');
  Future<TaskModel> startTask(String taskId, {int? expectedVersion}) =>
      sendCommand(taskId, command: 'start', expectedVersion: expectedVersion);
  Future<TaskModel> blockTask(String taskId, String reason,
          {int? expectedVersion}) =>
      sendCommand(taskId,
          command: 'block',
          expectedVersion: expectedVersion,
          payload: {'reason': reason});
  Future<TaskModel> unblockTask(String taskId, {int? expectedVersion}) =>
      sendCommand(taskId, command: 'unblock', expectedVersion: expectedVersion);
  Future<TaskModel> completeTask(String taskId, {int? expectedVersion}) =>
      sendCommand(taskId,
          command: 'complete', expectedVersion: expectedVersion);
  Future<TaskModel> reopenTask(String taskId, {int? expectedVersion}) =>
      sendCommand(taskId, command: 'reopen', expectedVersion: expectedVersion);
  Future<TaskModel> cancelTask(String taskId, {int? expectedVersion}) =>
      sendCommand(taskId, command: 'cancel', expectedVersion: expectedVersion);
  Future<TaskModel> returnTask(String taskId, String reason) =>
      sendCommand(taskId, command: 'return', payload: {'reason': reason});
  Future<TaskModel> assignTask(String taskId, String? assigneeUserId,
          {int? expectedVersion}) =>
      sendCommand(taskId,
          command: 'assign',
          expectedVersion: expectedVersion,
          payload: {'assigned_to': assigneeUserId});
  Future<TaskModel> updateTaskDetails(
    String taskId, {
    int? expectedVersion,
    String? title,
    String? description,
    TaskPriority? priority,
    DateTime? dueDate,
    bool clearDueDate = false,
  }) =>
      sendCommand(taskId,
          command: 'update_details',
          expectedVersion: expectedVersion,
          payload: {
            if (title != null) 'title': title,
            if (description != null) 'description': description,
            if (priority != null) 'priority': taskPriorityWire(priority),
            if (dueDate != null)
              'due_date': dueDate.toIso8601String()
            else if (clearDueDate)
              'due_date': '',
          });
  Future<TaskModel> setTaskVisibility(String taskId, TaskVisibility visibility,
          {int? expectedVersion}) =>
      sendCommand(taskId,
          command: 'set_visibility',
          expectedVersion: expectedVersion,
          payload: {'visibility': TaskModel.visibilityToString(visibility)});
  Future<TaskModel> setTaskJobItems(
    String taskId, {
    int? expectedVersion,
    String? jobId,
    List<String>? jobItemIds,
    String? overlapDecision,
  }) =>
      sendCommand(taskId,
          command: 'set_job_items',
          expectedVersion: expectedVersion,
          payload: {
            'job_id': jobId,
            if (jobItemIds != null) 'job_item_ids': jobItemIds,
            if (overlapDecision != null) 'overlap_decision': overlapDecision,
          });

  /// Entidades vinculables de los módulos generales. Se cargan únicamente al
  /// elegir el tipo de vínculo; abrir una tarea neutral no consulta catálogos
  /// completos ni muestra controles de otro flujo.
  Future<List<TaskContextTarget>> fetchLinkTargets(
    TaskContextKind kind,
  ) async {
    if (kind == TaskContextKind.none || kind == TaskContextKind.workshopJob) {
      return const [];
    }
    final lease = await _requireAuthorityLease();
    const pageSize = 500;
    const maxRows = 3000;

    Future<List<Map<String, dynamic>>> collect(
      Future<dynamic> Function(int from, int to) loadPage,
    ) async {
      final result = <Map<String, dynamic>>[];
      for (var from = 0; from < maxRows; from += pageSize) {
        final raw = await loadPage(from, from + pageSize - 1);
        _assertOwnedLease(lease);
        final page = (raw as List<dynamic>)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList(growable: false);
        for (final row in page) {
          if (row['tenant_id']?.toString() != lease.scope.tenantId) {
            throw StateError('Task context query crossed the authority tenant');
          }
        }
        result.addAll(page);
        if (page.length < pageSize) break;
      }
      return result;
    }

    String? compactContext(Iterable<dynamic> values) {
      final parts = values
          .map((value) => value?.toString().trim() ?? '')
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
      return parts.isEmpty ? null : parts.join(' · ');
    }

    switch (kind) {
      case TaskContextKind.customer:
        final rows = await collect((from, to) async => _supabase
            .from('customers')
            .select('id, tenant_id, name, phone, email')
            .eq('tenant_id', lease.scope.tenantId)
            .eq('is_active', true)
            .order('name')
            .range(from, to));
        return rows
            .map((row) => TaskContextTarget(
                  kind: kind,
                  id: row['id'].toString(),
                  label: row['name']?.toString().trim().isNotEmpty == true
                      ? row['name'].toString().trim()
                      : 'Cliente sin nombre',
                  context: compactContext([row['phone'], row['email']]),
                  searchText:
                      compactContext([row['name'], row['phone'], row['email']]),
                  route:
                      '/clientes/${Uri.encodeComponent(row['id'].toString())}',
                ))
            .toList(growable: false);
      case TaskContextKind.supplier:
        final rows = await collect((from, to) async => _supabase
            .from('suppliers')
            .select('id, tenant_id, name, contact_person, phone')
            .eq('tenant_id', lease.scope.tenantId)
            .eq('is_active', true)
            .order('name')
            .range(from, to));
        return rows
            .map((row) => TaskContextTarget(
                  kind: kind,
                  id: row['id'].toString(),
                  label: row['name']?.toString().trim().isNotEmpty == true
                      ? row['name'].toString().trim()
                      : 'Proveedor sin nombre',
                  context:
                      compactContext([row['contact_person'], row['phone']]),
                  searchText: compactContext(
                      [row['name'], row['contact_person'], row['phone']]),
                  route:
                      '/purchases/suppliers/${Uri.encodeComponent(row['id'].toString())}',
                ))
            .toList(growable: false);
      case TaskContextKind.salesInvoice:
        final rows = await collect((from, to) async => _supabase
            .from('sales_invoices')
            .select(
                'id, tenant_id, invoice_number, customer_name, status, date')
            .eq('tenant_id', lease.scope.tenantId)
            .order('updated_at', ascending: false)
            .range(from, to));
        return rows.map((row) {
          final number = row['invoice_number']?.toString().trim();
          final customer = row['customer_name']?.toString().trim();
          return TaskContextTarget(
            kind: kind,
            id: row['id'].toString(),
            label: [
              if (number != null && number.isNotEmpty) '#$number',
              if (customer != null && customer.isNotEmpty) customer,
            ].join(' · ').trim().isEmpty
                ? 'Venta sin número'
                : [
                    if (number != null && number.isNotEmpty) '#$number',
                    if (customer != null && customer.isNotEmpty) customer,
                  ].join(' · '),
            context: compactContext([row['status'], row['date']]),
            searchText:
                compactContext([number, customer, row['status'], row['date']]),
            route:
                '/sales/invoices/${Uri.encodeComponent(row['id'].toString())}',
          );
        }).toList(growable: false);
      case TaskContextKind.purchaseInvoice:
        final rows = await collect((from, to) async => _supabase
            .from('purchase_invoices')
            .select(
                'id, tenant_id, invoice_number, supplier_name, status, date')
            .eq('tenant_id', lease.scope.tenantId)
            .order('updated_at', ascending: false)
            .range(from, to));
        return rows.map((row) {
          final number = row['invoice_number']?.toString().trim();
          final supplier = row['supplier_name']?.toString().trim();
          final label = [
            if (number != null && number.isNotEmpty) '#$number',
            if (supplier != null && supplier.isNotEmpty) supplier,
          ].join(' · ');
          return TaskContextTarget(
            kind: kind,
            id: row['id'].toString(),
            label: label.isEmpty ? 'Compra sin número' : label,
            context: compactContext([row['status'], row['date']]),
            searchText:
                compactContext([number, supplier, row['status'], row['date']]),
            route: '/purchases/${Uri.encodeComponent(row['id'].toString())}',
          );
        }).toList(growable: false);
      case TaskContextKind.none:
      case TaskContextKind.workshopJob:
        return const [];
    }
  }

  /// Trabajos vinculables para el compositor: exactamente el alcance Activos
  /// de la tabla de Trabajos, ordenado por recencia.
  Future<List<TaskLinkableJob>> fetchLinkableJobs({int limit = 120}) async {
    if (limit <= 0) return const [];
    final lease = await _requireAuthorityLease();
    const pageSize = 200;
    final activeJobs = <TaskLinkableJob>[];

    for (var from = 0; activeJobs.length < limit; from += pageSize) {
      final rawRows = await _supabase
          .from('mechanic_jobs')
          .select('''
            id, tenant_id, job_number, customer_id, bike_id,
            job_type, workflow_kind, intake_kind, subject_id, subject_notes,
            warranty_outcome, quotation_status, quotation_valid_until,
            arrival_date, status, status_id, client_request, diagnosis,
            work_performed, notes, total_cost, invoice_id, is_invoiced,
            is_paid, is_warranty_job, created_at, updated_at, deleted_at,
            job_status:job_statuses(*),
            $taskLinkableJobCustomerEmbed,
            bike:bikes!mechanic_jobs_bike_id_fkey(
              brand, model, serial_number
            ),
            invoice:sales_invoices!mechanic_jobs_invoice_id_fkey(
              id, tenant_id, status, total, paid_amount
            )
          ''')
          .eq('tenant_id', lease.scope.tenantId)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false)
          .range(from, from + pageSize - 1);
      _assertOwnedLease(lease);
      final page = (rawRows as List<dynamic>)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(growable: false);

      for (final map in page) {
        if (map['tenant_id']?.toString() != lease.scope.tenantId) {
          throw StateError('Linkable job query crossed the authority tenant');
        }

        final invoiceJson = map['invoice'];
        Invoice? invoice;
        if (invoiceJson is Map) {
          final ownedInvoice = Map<String, dynamic>.from(invoiceJson);
          if (ownedInvoice['tenant_id']?.toString() != lease.scope.tenantId) {
            throw StateError(
              'Linkable job invoice crossed the authority tenant',
            );
          }
          invoice = Invoice.fromJson(ownedInvoice);
        }

        final customer = map['customers'];
        final bike = map['bike'];
        final customerMap = customer is Map ? customer : null;
        final bikeMap = bike is Map ? bike : null;
        final job = MechanicJob.fromJson(map);
        if (!isMechanicJobOperationallyActive(
          job,
          invoice: invoice,
          customerName: customerMap?['name']?.toString(),
          bikeBrand: bikeMap?['brand']?.toString(),
          bikeModel: bikeMap?['model']?.toString(),
          bikeSerialNumber: bikeMap?['serial_number']?.toString(),
        )) {
          continue;
        }

        activeJobs.add(TaskLinkableJob.fromJson(map));
        if (activeJobs.length == limit) break;
      }
      if (page.length < pageSize) break;
    }
    return activeJobs;
  }

  /// Líneas de trabajo reales del trabajo (service/adhoc), con su bicicleta,
  /// para elegir todos o algunos servicios al crear/repartir.
  Future<List<TaskJobWorkItem>> fetchJobWorkItems(String jobId) async {
    final lease = await _requireAuthorityLease();
    final itemRows = await _supabase
        .from('mechanic_job_items')
        .select(
            'id, tenant_id, product_name, description, notes, item_type, job_bike_id')
        .eq('job_id', jobId)
        .eq('tenant_id', lease.scope.tenantId)
        .inFilter('item_type', ['service', 'adhoc']).order('created_at');
    _assertOwnedLease(lease);
    final bikeRows = await _supabase
        .from('mechanic_job_bikes')
        .select('id, tenant_id, bikes(brand, model)')
        .eq('job_id', jobId)
        .eq('tenant_id', lease.scope.tenantId);
    _assertOwnedLease(lease);
    final bikeLabels = <String, String>{};
    for (final row in (bikeRows as List<dynamic>)) {
      final map = Map<String, dynamic>.from(row as Map);
      if (map['tenant_id']?.toString() != lease.scope.tenantId) {
        throw StateError('Job bike query crossed the authority tenant');
      }
      final bike = map['bikes'];
      final label = bike is Map
          ? [bike['brand'], bike['model']]
              .whereType<String>()
              .where((part) => part.trim().isNotEmpty)
              .join(' ')
          : '';
      bikeLabels[map['id'].toString()] = label;
    }
    return (itemRows as List<dynamic>).map((row) {
      final map = Map<String, dynamic>.from(row as Map);
      if (map['tenant_id']?.toString() != lease.scope.tenantId) {
        throw StateError('Job item query crossed the authority tenant');
      }
      final jobBikeId = map['job_bike_id']?.toString();
      final instructions = map['notes']?.toString().trim();
      final name = [map['description'], map['product_name']]
          .map((value) => value?.toString().trim() ?? '')
          .firstWhere((value) => value.isNotEmpty, orElse: () => 'Servicio');
      return TaskJobWorkItem(
        id: map['id'].toString(),
        name: name,
        itemType: map['item_type']?.toString(),
        jobBikeId: jobBikeId,
        bikeLabel: jobBikeId == null
            ? null
            : (bikeLabels[jobBikeId]?.isEmpty ?? true)
                ? null
                : bikeLabels[jobBikeId],
        instructions:
            instructions == null || instructions.isEmpty ? null : instructions,
      );
    }).toList();
  }

  /// Actividad de la tarea desde el ledger.
  Future<List<SmartTaskEvent>> fetchEvents(String taskId,
      {int limit = 50}) async {
    final lease = await _requireAuthorityLease();
    final rows = await _supabase
        .from('smart_task_events')
        .select()
        .eq('task_id', taskId)
        .eq('tenant_id', lease.scope.tenantId)
        .order('created_at', ascending: false)
        .limit(limit);
    _assertOwnedLease(lease);
    return (rows as List<dynamic>).map((row) {
      final map = Map<String, dynamic>.from(row as Map);
      if (map['tenant_id']?.toString() != lease.scope.tenantId) {
        throw StateError('Task event query crossed the authority tenant');
      }
      return SmartTaskEvent.fromJson(map);
    }).toList();
  }

  /// Directorio de asignación honesto (erp / portal / sin acceso).
  Future<List<TaskAssignmentPrincipal>> fetchAssignmentDirectory() async {
    final lease = await _requireAuthorityLease();
    final rows = await _supabase.rpc('get_smart_task_assignment_directory_v1');
    _assertOwnedLease(lease);
    if (rows is! List) {
      throw const FormatException('Invalid assignment directory response');
    }
    final directory = rows
        .whereType<Map>()
        .map((row) =>
            TaskAssignmentPrincipal.fromJson(Map<String, dynamic>.from(row)))
        .toList();
    if (directory
        .any((principal) => principal.tenantId != lease.scope.tenantId)) {
      throw StateError('Assignment directory crossed the authority tenant');
    }
    return directory;
  }

  /// Hilo canónico existente, o null.
  Future<String?> threadOf(String taskId) async {
    final lease = await _requireAuthorityLease();
    final result = await _supabase
        .rpc('smart_task_thread_v1', params: {'p_task_id': taskId});
    _assertOwnedLease(lease);
    final id = result?.toString();
    return (id == null || id.isEmpty) ? null : id;
  }

  /// Get-or-create del hilo (server-owned; participantes exactos).
  Future<({String conversationId, String rootMessageId, bool created})>
      openThread(String taskId) async {
    final lease = await _requireAuthorityLease();
    final result = await _supabase.rpc('smart_task_thread_get_or_create_v1',
        params: {'p_task_id': taskId});
    _assertOwnedLease(lease);
    final map = Map<String, dynamic>.from(result as Map);
    final conversationId = map['conversation_id']?.toString();
    final rootMessageId = map['root_message_id']?.toString();
    if (conversationId == null ||
        conversationId.isEmpty ||
        rootMessageId == null ||
        rootMessageId.isEmpty) {
      throw const FormatException('Invalid task thread descriptor');
    }
    return (
      conversationId: conversationId,
      rootMessageId: rootMessageId,
      created: map['created'] == true,
    );
  }

  /// Marca la versión actual como vista para el usuario actual.
  Future<void> markSeen(TaskModel task) async {
    final lease = await _requireAuthorityLease();
    final taskId = task.id;
    final uid = lease.scope.userId;
    if (taskId == null) return;
    final state = <String, dynamic>{
      'task_id': taskId,
      'user_id': uid,
      'tenant_id': lease.scope.tenantId,
      'seen_at': DateTime.now().toUtc().toIso8601String(),
      'seen_version': task.version,
    };
    await _supabase.from('smart_task_user_state').upsert(state);
    if (_cacheScope.owns(lease)) {
      _userStateByTask[taskId] = {...?_userStateByTask[taskId], ...state};
      _safeNotify();
    }
  }

  Future<void> setPinned(String taskId, bool pinned) async {
    final lease = await _requireAuthorityLease();
    final state = <String, dynamic>{
      'task_id': taskId,
      'user_id': lease.scope.userId,
      'tenant_id': lease.scope.tenantId,
      'pinned_at': pinned ? DateTime.now().toUtc().toIso8601String() : null,
    };
    await _supabase.from('smart_task_user_state').upsert(state);
    if (_cacheScope.owns(lease)) {
      _userStateByTask[taskId] = {...?_userStateByTask[taskId], ...state};
      _safeNotify();
    }
  }

  Future<void> snoozeUntil(String taskId, DateTime? until) async {
    final lease = await _requireAuthorityLease();
    final state = <String, dynamic>{
      'task_id': taskId,
      'user_id': lease.scope.userId,
      'tenant_id': lease.scope.tenantId,
      'snoozed_until': until?.toUtc().toIso8601String(),
    };
    await _supabase.from('smart_task_user_state').upsert(state);
    if (_cacheScope.owns(lease)) {
      _userStateByTask[taskId] = {...?_userStateByTask[taskId], ...state};
      _safeNotify();
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

/// Prioridad al formato de la base ('low'|'normal'|'high'|'urgent').
String taskPriorityWire(TaskPriority priority) {
  switch (priority) {
    case TaskPriority.low:
      return 'low';
    case TaskPriority.normal:
      return 'normal';
    case TaskPriority.high:
      return 'high';
    case TaskPriority.urgent:
      return 'urgent';
  }
}

class _TaskTrayLoad {
  const _TaskTrayLoad(this.tasks, this.jobItemsByTask, this.jobHeadersById,
      this.userStateByTask);
  final List<TaskModel> tasks;
  final Map<String, List<SmartTaskJobItem>> jobItemsByTask;
  final Map<String, TaskLinkableJob> jobHeadersById;
  final Map<String, Map<String, dynamic>> userStateByTask;
}

/// Un trabajo elegible del compositor (proyección liviana, sin hidratar).
class TaskLinkableJob {
  const TaskLinkableJob({
    required this.id,
    required this.jobNumber,
    required this.status,
    required this.customerName,
    required this.clientRequest,
  });

  final String id;
  final String jobNumber;
  final String? status;
  final String? customerName;
  final String? clientRequest;

  factory TaskLinkableJob.fromJson(Map<String, dynamic> json) {
    final customer = json['customers'];
    return TaskLinkableJob(
      id: json['id'].toString(),
      jobNumber: json['job_number']?.toString() ?? '—',
      status: json['status']?.toString(),
      customerName: customer is Map ? customer['name']?.toString() : null,
      clientRequest: json['client_request']?.toString(),
    );
  }
}

/// Una línea de trabajo real, elegible para respaldar la tarea.
class TaskJobWorkItem {
  const TaskJobWorkItem({
    required this.id,
    required this.name,
    required this.itemType,
    required this.jobBikeId,
    required this.bikeLabel,
    this.instructions,
  });

  final String id;
  final String name;
  final String? itemType;
  final String? jobBikeId;
  final String? bikeLabel;
  final String? instructions;
}
