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
import 'package:vinabike_erp/modules/tasks/models/smart_task_service_note.dart';
import 'package:vinabike_erp/modules/tasks/models/task_assignment_principal.dart';
import 'package:vinabike_erp/modules/tasks/models/task_model.dart';
import 'package:vinabike_erp/modules/tasks/services/task_upload_cleanup_journal.dart';
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
  static const maxAttachmentBytes = 20 * 1024 * 1024;
  final SupabaseClient _supabase;
  final TenantService _tenantService;
  final TaskUploadCleanupJournal _uploadCleanupJournal;
  final String _uploadOwnerSession = _uuid.v4();

  // In-memory cache
  List<TaskModel> _tasks = [];
  Map<String, List<SmartTaskJobItem>> _jobItemsByTask = {};
  Map<String, TaskLinkableJob> _jobHeadersById = {};
  Map<String, Map<String, dynamic>> _userStateByTask = {};
  static const _uuid = Uuid();
  bool _isInit = false;
  bool _isDisposed = false;
  final Set<String> _attachmentCleanupInFlight = {};
  final Set<String> _uploadIntentReconciliationInFlight = {};
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

  TaskService(
    this._supabase,
    this._tenantService, {
    TaskUploadCleanupJournal? uploadCleanupJournal,
  }) : _uploadCleanupJournal =
            uploadCleanupJournal ?? TaskUploadCleanupJournal() {
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
      unawaited(_retryPendingAttachmentCleanup(loadedLease));
      unawaited(_reconcileLinkedUploadIntents(loadedLease));
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
          await _hydratePrivateTaskAttachments(lease, loadedTasks);
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

  /// El vínculo privado vive por archivo. Leerlo aparte impide que un embed
  /// o una URL temporal reemplacen la identidad durable de la tarea.
  Future<void> _hydratePrivateTaskAttachments(
    AuthorityCacheLease lease,
    List<TaskModel> tasks,
  ) async {
    if (tasks.isEmpty) return;
    final byTask = <String, List<Map<String, dynamic>>>{};
    const pageSize = 500;
    for (var offset = 0;; offset += pageSize) {
      final rows = await _supabase
          .from('smart_task_attachments')
          .select('id, tenant_id, task_id, file_name, mime_type, size_bytes, '
              'storage_path, created_at, version')
          .eq('tenant_id', lease.scope.tenantId)
          .order('created_at')
          .order('id')
          .range(offset, offset + pageSize - 1);
      _assertOwnedLease(lease);
      for (final row in (rows as List<dynamic>)) {
        final item = Map<String, dynamic>.from(row as Map);
        if (item['tenant_id']?.toString() != lease.scope.tenantId) {
          throw StateError('Task attachment crossed the authority tenant');
        }
        final taskId = item['task_id']?.toString();
        if (taskId == null) continue;
        byTask.putIfAbsent(taskId, () => []).add({
          'id': item['id'],
          'name': item['file_name'],
          'type': item['mime_type'],
          'size': item['size_bytes'],
          'storage_bucket': 'task-attachments',
          'storage_path': item['storage_path'],
          'uploaded_at': item['created_at'],
          'version': item['version'],
        });
      }
      if (rows.length < pageSize) break;
    }
    for (var index = 0; index < tasks.length; index++) {
      final task = tasks[index];
      final privateFiles = byTask[task.id];
      if (privateFiles == null || privateFiles.isEmpty) continue;
      tasks[index] = task.copyWith(
        attachments: [...task.attachments, ...privateFiles],
      );
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
  Future<TaskModel> createTask(
    TaskModel task, {
    String? idempotencyKey,
  }) {
    return createTrayTask(
      title: task.title,
      description: task.description,
      kind: task.kind,
      visibility: task.visibility,
      priority: task.priority,
      dueDate: task.dueDate,
      // Un trabajador va sólo como trabajador y el servidor deriva su cuenta
      // (mismo contrato que la tarea rápida: mandar ambas choca si la cuenta
      // cambió, `assignee_employee_mismatch`).
      assignedTo: task.assignedEmployeeId != null ? null : task.assignedTo,
      assignedEmployeeId: task.assignedEmployeeId,
      linkedJobId: task.linkedJobId,
      linkedCustomerId: task.linkedCustomerId,
      linkedSupplierId: task.linkedSupplierId,
      linkedPurchaseInvoiceId: task.linkedPurchaseInvoiceId,
      linkedSalesInvoiceId: task.linkedSalesInvoiceId,
      idempotencyKey: idempotencyKey,
    );
  }

  /// Puente de compatibilidad: los llamadores antiguos entregan el modelo
  /// completo; aquí se convierte en los comandos RPC equivalentes (diff
  /// contra la caché), para que la autoridad, el versionado, el ledger y las
  /// notificaciones rijan también para la UI legada. Los adjuntos privados
  /// hidratados son de lectura: este comando nunca reescribe el JSONB legacy.
  /// Sin comandos que emitir, no escribe nada.
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

    // La persona responsable es el trabajador si lo hay, si no la cuenta.
    if (current != null && task.assigneeKey != current.assigneeKey) {
      await sendCommand(id, command: 'assign', payload: {
        if (task.assignedEmployeeId != null)
          'assigned_employee_id': task.assignedEmployeeId
        else
          'assigned_to': task.assignedTo,
      });
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

  /// Private bytes are opened through short-lived URLs, never persisted in a
  /// task row or exposed through the public asset bucket.
  Future<String> createSignedAttachmentUrl(String storagePath) {
    return _supabase.storage
        .from('task-attachments')
        .createSignedUrl(storagePath, 300);
  }

  /// Resume authorized private-file cleanup without reloading the task list.
  /// The login path also runs this operation in the background.
  Future<void> resumePendingAttachmentCleanup() async {
    final lease = await _requireAuthorityLease();
    await _retryPendingAttachmentCleanup(lease);
  }

  /// Retire local upload intents only after the server confirms this uploader's
  /// active or removed link. An absent link never proves Storage bytes are safe
  /// to delete: another session may still be uploading or linking them.
  Future<void> reconcileLinkedUploadIntents() async {
    final lease = await _requireAuthorityLease();
    await _reconcileLinkedUploadIntents(lease);
  }

  Future<void> _reconcileLinkedUploadIntents(
    AuthorityCacheLease lease,
  ) async {
    final key = '${lease.scope.userId}/${lease.scope.tenantId}/'
        '${lease.generation}';
    if (!_uploadIntentReconciliationInFlight.add(key)) return;
    try {
      final intents = await _uploadCleanupJournal.pendingFor(
        lease.scope.tenantId,
        lease.scope.userId,
      );
      for (final intent in intents) {
        _assertOwnedLease(lease);
        Object? state;
        try {
          state = await _supabase.rpc(
            'smart_task_attachment_recovery_status_v1',
            params: {
              'p_tenant_id': intent.tenantId,
              'p_task_id': intent.taskId,
              'p_attachment_id': intent.attachmentId,
            },
          );
        } on PostgrestException catch (error) {
          if (error.code == '42501') {
            // The task or link no longer belongs to this uploader. Keep the
            // intent; another eligible task should still be reconciled.
            continue;
          }
          rethrow;
        }
        _assertOwnedLease(lease);
        if (state == 'absent') continue;
        if (state != 'active' && state != 'removed') {
          throw StateError(
              'El servidor no entregó un estado de adjunto válido');
        }
        await _uploadCleanupJournal.forget(intent);
      }
    } on AuthorityScopeChangedException {
      // Another authority now owns the client; retain the old scoped intents.
    } catch (error) {
      if (kDebugMode) {
        debugPrint('⚠️ [TaskService] Upload intent reconciliation deferred: '
            '$error');
      }
    } finally {
      _uploadIntentReconciliationInFlight.remove(key);
    }
  }

  /// A removal can tombstone its link and then lose the Storage response.
  /// The server exposes only tombstones this principal may manage; a later
  /// login finishes their physical deletion without resurfacing the file.
  Future<void> _retryPendingAttachmentCleanup(
    AuthorityCacheLease lease,
  ) async {
    const batchSize = 25;
    final key = '${lease.scope.userId}/${lease.scope.tenantId}/'
        '${lease.generation}';
    if (!_attachmentCleanupInFlight.add(key)) return;
    try {
      while (true) {
        _assertOwnedLease(lease);
        final response = await _supabase.rpc(
          'smart_task_attachment_pending_cleanup_v2',
          params: {
            'p_tenant_id': lease.scope.tenantId,
            'p_limit': batchSize,
          },
        );
        _assertOwnedLease(lease);
        if (response is! List) {
          throw StateError('El servidor no entregó la cola de limpieza');
        }
        var hadFailure = false;
        for (final raw in response) {
          _assertOwnedLease(lease);
          if (raw is! Map) {
            throw StateError(
                'La cola de limpieza contiene un vínculo inválido');
          }
          final pending = Map<String, dynamic>.from(raw);
          final taskId = pending['task_id']?.toString();
          final attachmentId = pending['id']?.toString();
          final path = pending['storage_path']?.toString();
          if (taskId == null ||
              attachmentId == null ||
              path == null ||
              !path.startsWith(
                  '${lease.scope.tenantId}/$taskId/$attachmentId/')) {
            // An assignee may also see a task in another tenant. Never send
            // that path to Storage, but finish valid rows already in this page.
            // Stop after the page: the same foreign tombstone would otherwise
            // be returned forever until the server scopes its queue.
            hadFailure = true;
            if (kDebugMode) {
              debugPrint('⚠️ [TaskService] Skipped out-of-scope private file '
                  'cleanup row');
            }
            continue;
          }
          try {
            await _deletePrivateTaskObjectAndAck(
              taskId: taskId,
              attachmentId: attachmentId,
              storagePath: path,
              lease: lease,
            );
          } on AuthorityScopeChangedException {
            rethrow;
          } catch (error) {
            hadFailure = true;
            if (kDebugMode) {
              debugPrint('⚠️ [TaskService] Pending private file cleanup: '
                  '$error');
            }
          }
        }
        // The RPC returns the oldest unacknowledged rows. A failed row would
        // appear in the next page, so stop rather than retry it in a loop.
        if (hadFailure || response.length < batchSize) break;
      }
    } on AuthorityScopeChangedException {
      // A different session now owns the client and may resume its own queue.
    } catch (error) {
      if (kDebugMode) {
        debugPrint('⚠️ [TaskService] Private file cleanup deferred: $error');
      }
    } finally {
      _attachmentCleanupInFlight.remove(key);
    }
  }

  Future<void> _deletePrivateTaskObjectAndAck({
    required String taskId,
    required String attachmentId,
    required String storagePath,
    AuthorityCacheLease? lease,
  }) async {
    if (lease != null) _assertOwnedLease(lease);
    await _supabase.storage.from('task-attachments').remove([storagePath]);
    if (lease != null) _assertOwnedLease(lease);
    final receipt = await _supabase.rpc(
      'smart_task_attachment_ack_cleanup_v1',
      params: {'p_task_id': taskId, 'p_attachment_id': attachmentId},
    );
    if (lease != null) _assertOwnedLease(lease);
    if (receipt is! Map ||
        receipt['id']?.toString() != attachmentId ||
        receipt['task_id']?.toString() != taskId ||
        receipt['storage_deleted_at'] == null) {
      throw StateError('El servidor no confirmó la limpieza del archivo');
    }
  }

  /// The operator may leave after a failed upload. Keep only the identities
  /// of attempts started by this service instance so a later session can
  /// distinguish them from uploads still active in another instance.
  Future<void> abandonPendingAttachmentUploads({
    required String taskId,
    required Iterable<String> attachmentIds,
  }) async {
    final ids = attachmentIds.toSet();
    if (ids.isEmpty) return;
    final lease = await _requireAuthorityLease();
    final pending = await _uploadCleanupJournal.pendingFor(
      lease.scope.tenantId,
      lease.scope.userId,
    );
    for (final intent in pending) {
      if (intent.taskId != taskId ||
          intent.ownerSession != _uploadOwnerSession ||
          !ids.contains(intent.attachmentId)) {
        continue;
      }
      _assertOwnedLease(lease);
      await _uploadCleanupJournal
          .remember(intent.abandon(DateTime.now().toUtc()));
    }
  }

  /// Upload a file to Supabase Storage and attach it to a task.
  Future<void> addAttachment({
    required String taskId,
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? attachmentId,
  }) async {
    final lease = await _requireAuthorityLease();
    final tenantId = lease.scope.tenantId;
    final id = attachmentId ?? _uuid.v4();
    final name = fileName.trim();
    if (name.isEmpty ||
        name.length > 255 ||
        mimeType.trim().isEmpty ||
        mimeType.length > 200 ||
        bytes.isEmpty ||
        bytes.length > maxAttachmentBytes) {
      throw ArgumentError('El archivo debe tener nombre y medir hasta 20 MB');
    }

    try {
      final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final storagePath = '$tenantId/$taskId/$id/'
          '${safeName.isEmpty ? 'archivo' : safeName}';
      final actorId = lease.scope.userId;
      final cleanupIntent = TaskUploadCleanupIntent(
        tenantId: tenantId,
        userId: actorId,
        taskId: taskId,
        attachmentId: id,
        ownerSession: _uploadOwnerSession,
        createdAt: DateTime.now().toUtc(),
      );
      // A lost Storage response may leave private bytes without a task link.
      // Persist the identity before the first remote read or upload.
      await _uploadCleanupJournal.remember(cleanupIntent);
      _assertOwnedLease(lease);

      Future<bool> alreadyLinked() async {
        _assertOwnedLease(lease);
        final row = await _supabase
            .from('smart_task_attachments')
            .select('tenant_id, task_id, uploaded_by, storage_path, '
                'file_name, mime_type, size_bytes')
            .eq('id', id)
            .maybeSingle();
        _assertOwnedLease(lease);
        if (row == null) return false;
        if (row['tenant_id']?.toString() != tenantId ||
            row['task_id']?.toString() != taskId ||
            row['uploaded_by']?.toString() != actorId ||
            row['storage_path']?.toString() != storagePath ||
            row['file_name']?.toString() != name ||
            row['mime_type']?.toString() != mimeType.trim() ||
            row['size_bytes']?.toString() != bytes.length.toString()) {
          throw StateError('El ID del adjunto ya pertenece a otro archivo');
        }
        return true;
      }

      Future<bool> storedBytesMatch() async {
        _assertOwnedLease(lease);
        final storedBytes = await _supabase.storage
            .from('task-attachments')
            .download(storagePath);
        _assertOwnedLease(lease);
        return listEquals(storedBytes, bytes);
      }

      if (await alreadyLinked()) {
        if (!await storedBytesMatch()) {
          throw StateError('El archivo pendiente no coincide con los bytes '
              'guardados; quítalo y selecciónalo otra vez');
        }
      } else {
        try {
          await _supabase.storage.from('task-attachments').uploadBinary(
                storagePath,
                bytes,
                fileOptions: FileOptions(contentType: mimeType, upsert: false),
              );
        } catch (uploadError, uploadStackTrace) {
          _assertOwnedLease(lease);
          // A lost upload response and an occupied path look alike. The
          // existing object is usable only when its bytes match this pending
          // file; otherwise a replay could attach false metadata to it.
          bool matches;
          try {
            matches = await storedBytesMatch();
          } catch (_) {
            Error.throwWithStackTrace(uploadError, uploadStackTrace);
          }
          if (!matches) {
            throw StateError('El archivo pendiente no coincide con los bytes '
                'guardados; quítalo y selecciónalo otra vez');
          }
        }
      }
      // A scope switch during Storage must not send a link RPC for the old
      // task. The private object remains discoverable by its journal ID.
      _assertOwnedLease(lease);

      // A SQL rejection rolls back this link command, but an absent link is
      // not proof that another session stopped uploading or linking the same
      // UUID. Keep the object and journal until a server claim excludes that
      // producer; never delete by a point-in-time SELECT here.
      final receipt =
          await _supabase.rpc('smart_task_attachment_add_v1', params: {
        'p_task_id': taskId,
        'p_attachment_id': id,
        'p_file_name': name,
        'p_storage_path': storagePath,
        'p_mime_type': mimeType,
        'p_size_bytes': bytes.length,
        'p_idempotency_key': 'task-file-add:$id',
      });
      if (receipt is! Map ||
          receipt['id']?.toString() != id ||
          receipt['task_id']?.toString() != taskId ||
          receipt['storage_path']?.toString() != storagePath) {
        throw StateError('El servidor no confirmó el vínculo del archivo');
      }
      if (!await alreadyLinked()) {
        // An old idempotency receipt is not proof that a link is still active:
        // another writer may have removed it after the original upload.
        throw StateError(
            'El adjunto ya no está activo; vuelve a seleccionarlo');
      }
      _assertOwnedLease(lease);
      await _uploadCleanupJournal.forget(cleanupIntent);

      // Refresh local cache
      try {
        await fetchTasks();
      } catch (refreshError) {
        // The write was acknowledged. A failed read must not invite a second
        // upload on retry; Realtime/fallback refresh will reconcile the list.
        if (kDebugMode) {
          debugPrint('⚠️ [TaskService] Attachment saved; refresh failed: '
              '$refreshError');
        }
      }
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

  /// Tombstone the link first, then retire its private bytes through Storage.
  /// Returns false when the file is already hidden but physical cleanup must
  /// resume later. The caller must not present it as an active attachment.
  Future<bool> removeAttachment({
    required String taskId,
    required String attachmentId,
  }) async {
    try {
      final lease = await _requireAuthorityLease();
      _assertOwnedLease(lease);
      final receipt = await _supabase.rpc(
        'smart_task_attachment_remove_v1',
        params: {
          'p_task_id': taskId,
          'p_attachment_id': attachmentId,
          'p_idempotency_key': 'task-file-remove:$attachmentId',
        },
      );
      // The RPC may have tombstoned the link while the operator switched
      // authority. Leave its durable cleanup queue for the original scope.
      if (!_cacheScope.owns(lease)) return false;
      if (receipt is! Map ||
          receipt['id']?.toString() != attachmentId ||
          receipt['storage_bucket'] != 'task-attachments') {
        throw StateError('El servidor no confirmó el retiro del archivo');
      }
      final storagePath = receipt['storage_path']?.toString();
      if (storagePath == null || storagePath.isEmpty) {
        throw StateError('Falta la ruta privada del archivo retirado');
      }
      if (!storagePath
          .startsWith('${lease.scope.tenantId}/$taskId/$attachmentId/')) {
        throw StateError('La ruta privada no pertenece a este adjunto');
      }
      var cleanupCompleted = true;
      try {
        await _deletePrivateTaskObjectAndAck(
          taskId: taskId,
          attachmentId: attachmentId,
          storagePath: storagePath,
          lease: lease,
        );
      } catch (cleanupError) {
        cleanupCompleted = false;
        if (kDebugMode) {
          debugPrint('⚠️ [TaskService] Attachment hidden; cleanup pending: '
              '$cleanupError');
        }
      }
      if (!_cacheScope.owns(lease)) return false;

      // The tombstone has succeeded. A failed read must not present the file
      // as active again; Realtime/fallback refresh will reconcile the list.
      try {
        await fetchTasks();
      } catch (refreshError) {
        if (kDebugMode) {
          debugPrint('⚠️ [TaskService] Attachment removed; refresh failed: '
              '$refreshError');
        }
      }
      if (kDebugMode) {
        debugPrint('✅ [TaskService] Attachment hidden; '
            'cleanup completed: $cleanupCompleted');
      }
      return cleanupCompleted;
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
    String? assignedEmployeeId,
    String? linkedJobId,
    List<String>? jobItemIds,

    /// La primera nota de cada servicio elegido, por `job_item_id`.
    Map<String, String>? jobItemNotes,
    String? overlapDecision,
    String? linkedCustomerId,
    String? linkedSupplierId,
    String? linkedPurchaseInvoiceId,
    String? linkedSalesInvoiceId,
    String? idempotencyKey,
  }) async {
    final notes = {
      for (final entry in (jobItemNotes ?? const <String, String>{}).entries)
        if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
    };
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
      if (assignedEmployeeId != null)
        'assigned_employee_id': assignedEmployeeId,
      if (linkedJobId != null) 'linked_job_id': linkedJobId,
      if (jobItemIds != null) 'job_item_ids': jobItemIds,
      if (notes.isNotEmpty) 'job_item_notes': notes,
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

  /// Marca un servicio de la tarea como hecho o pendiente. Sin versión
  /// esperada: cada marca dice su estado final y repetirla no cambia nada, así
  /// que dos toques seguidos no chocan por versión. La acción propia no
  /// enciende el contador de «no vista».
  Future<TaskModel> setJobItemDone(
    TaskModel task,
    String jobItemId, {
    required bool done,
  }) async {
    final updated = await sendCommand(task.id!,
        command: 'set_job_item_done',
        payload: {'job_item_id': jobItemId, 'done': done});
    unawaited(markSeen(updated).catchError((_) {}));
    return updated;
  }

  /// Deja (o borra, con texto vacío) la nota para el siguiente turno.
  Future<TaskModel> setHandoffNote(TaskModel task, String? note) async {
    final updated = await sendCommand(task.id!,
        command: 'set_handoff_note', payload: {'note': note?.trim() ?? ''});
    unawaited(markSeen(updated).catchError((_) {}));
    return updated;
  }

  /// Nota nueva en el hilo de un servicio: la primera, o «continuar». La
  /// anterior queda en la historia y ésta pasa a ser la vigente.
  Future<TaskModel> addJobItemNote(
      TaskModel task, String jobItemId, String note) async {
    final updated = await sendCommand(task.id!,
        command: 'add_job_item_note',
        payload: {'job_item_id': jobItemId, 'note': note.trim()});
    unawaited(markSeen(updated).catchError((_) {}));
    return updated;
  }

  /// Corrige una nota propia; lo que decía queda en la historia.
  Future<TaskModel> editJobItemNote(
      TaskModel task, String noteId, String note) async {
    final updated = await sendCommand(task.id!,
        command: 'edit_job_item_note',
        payload: {'note_id': noteId, 'note': note.trim()});
    unawaited(markSeen(updated).catchError((_) {}));
    return updated;
  }

  /// Retira una nota propia; queda en la historia como retirada.
  Future<TaskModel> withdrawJobItemNote(TaskModel task, String noteId) async {
    final updated = await sendCommand(task.id!,
        command: 'withdraw_job_item_note', payload: {'note_id': noteId});
    unawaited(markSeen(updated).catchError((_) {}));
    return updated;
  }

  /// La nota vigente de cada servicio de la tarea, por `job_item_id`.
  Future<Map<String, ServiceNote>> fetchServiceNotes(String taskId) async {
    final lease = await _requireAuthorityLease();
    final rows = await _supabase
        .rpc('get_smart_task_service_notes_v1', params: {'p_task_id': taskId});
    _assertOwnedLease(lease);
    if (rows is! List) return const {};
    final userId = currentUserId;
    return {
      for (final row in rows.whereType<Map>())
        row['job_item_id'].toString(): ServiceNote.fromErpRow(
            Map<String, dynamic>.from(row),
            currentUserId: userId),
    };
  }

  /// La línea de tiempo de un servicio: encargo, notas (con lo que decían),
  /// hecho / pendiente y lo que cambió el taller. Lo más reciente primero.
  Future<List<ServiceTimelineEntry>> fetchServiceTimeline(
      String taskId, String jobItemId) async {
    final lease = await _requireAuthorityLease();
    final rows = await _supabase.rpc('get_smart_task_service_timeline_v1',
        params: {'p_task_id': taskId, 'p_job_item_id': jobItemId});
    _assertOwnedLease(lease);
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) =>
            ServiceTimelineEntry.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// Reasigna a un responsable del directorio. Un trabajador se asigna como
  /// trabajador (tenga o no cuenta); quien no es trabajador, por su cuenta.
  /// Sin responsable, desasigna.
  Future<TaskModel> assignTaskToPrincipal(
    String taskId,
    TaskAssignmentPrincipal? assignee, {
    int? expectedVersion,
  }) =>
      sendCommand(taskId,
          command: 'assign',
          expectedVersion: expectedVersion,
          payload: {
            if (assignee?.employeeId != null)
              'assigned_employee_id': assignee!.employeeId
            else
              'assigned_to': assignee?.userId,
          });
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
            subject:job_subjects!mechanic_jobs_subject_id_fkey(
              id, tenant_id, name
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

        final subjectJson = map['subject'];
        if (subjectJson is Map &&
            subjectJson['tenant_id']?.toString() != lease.scope.tenantId) {
          throw StateError('Linkable job subject crossed the authority tenant');
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

  /// Cuántos servicios (líneas `service`/`adhoc`) tiene cada trabajo. Un
  /// trabajo sin servicios no aparece en el mapa.
  ///
  /// Se lee por páginas: el servidor corta cada respuesta en 1000 filas
  /// (`max_rows`) sin avisar, y 120 trabajos activos con varios servicios
  /// cada uno pasan ese techo; cortado, el conteo diría menos servicios que
  /// la lista que se abre después.
  Future<Map<String, int>> fetchJobServiceCounts(List<String> jobIds) async {
    if (jobIds.isEmpty) return const {};
    const pageSize = 1000;
    final lease = await _requireAuthorityLease();
    final counts = <String, int>{};
    for (var from = 0;; from += pageSize) {
      final rows = await _supabase
          .from('mechanic_job_items')
          .select('id, job_id, tenant_id')
          .eq('tenant_id', lease.scope.tenantId)
          .inFilter('job_id', jobIds)
          .inFilter('item_type', ['service', 'adhoc'])
          .order('id')
          .range(from, from + pageSize - 1);
      _assertOwnedLease(lease);
      final page = rows as List<dynamic>;
      for (final row in page) {
        final map = Map<String, dynamic>.from(row as Map);
        if (map['tenant_id']?.toString() != lease.scope.tenantId) {
          throw StateError('Job item count crossed the authority tenant');
        }
        final jobId = map['job_id']?.toString();
        if (jobId == null) continue;
        counts[jobId] = (counts[jobId] ?? 0) + 1;
      }
      if (page.length < pageSize) return counts;
    }
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
    this.statusLabel,
    this.bikeLabel,
    this.quotationStatus,
    this.hasInvoice = false,
    this.isPaid = false,
    this.receivedAt,
    this.workFinished = false,
    this.componentLabel,
    this.componentDetail,
  });

  final String id;
  final String jobNumber;
  final String? status;
  final String? customerName;
  final String? clientRequest;

  /// El estado en las palabras del taller (el personalizado si lo hay).
  final String? statusLabel;

  /// Marca y modelo de la bici principal.
  final String? bikeLabel;

  /// Qué se recibió cuando el trabajo es sobre un componente y no una bici
  /// («Rueda trasera»): el mismo nombre que muestra la tabla de trabajos.
  final String? componentLabel;

  /// Lo que se anotó al recibirlo, cuando dice más que el nombre del
  /// catálogo («RUEDA TRASERA BMX»); la tabla lo muestra debajo del nombre.
  final String? componentDetail;

  /// Lo que se recibió, bici o componente.
  String? get objectLabel => bikeLabel ?? componentLabel;

  /// Lo que se recibió con su detalle, para la fila: la bici con su modelo,
  /// el componente con lo que se anotó.
  String? get objectDisplay =>
      bikeLabel ??
      (componentDetail == null
          ? componentLabel
          : '$componentLabel · $componentDetail');

  bool get isComponent => componentLabel != null;

  /// `pending`, `approved` o `rejected`; null si el trabajo no tiene
  /// presupuesto.
  final String? quotationStatus;
  final bool hasInvoice;
  final bool isPaid;

  /// Cuándo entró al taller (`arrival_date`; si falta, cuándo se creó).
  final DateTime? receivedAt;

  /// El trabajo ya está terminado (estado de fase `complete`, como
  /// «Terminado»): puede quedar por cobrar o retirar, pero no por hacer.
  final bool workFinished;

  factory TaskLinkableJob.fromJson(Map<String, dynamic> json) {
    final customer = json['customers'];
    final bike = json['bike'];
    final bikeLabel = bike is Map
        ? [bike['brand'], bike['model']]
            .map((part) => part?.toString().trim() ?? '')
            .where((part) => part.isNotEmpty)
            .join(' ')
        : '';
    String? statusLabel;
    var workFinished = false;
    try {
      final job = MechanicJob.fromJson(json);
      statusLabel = job.statusDisplayName;
      // El estado propio del taller manda; sin él, el estado base.
      workFinished = job.customStatus != null
          ? job.customStatus!.phase == StatusPhase.complete
          : const {
              JobStatus.finalizado,
              JobStatus.entregado,
              JobStatus.cancelado,
            }.contains(job.status);
    } catch (_) {
      statusLabel = null;
    }
    // Un trabajo de componente se nombra como en la tabla de trabajos: el
    // sujeto del catálogo, si no la nota de lo recibido.
    String? componentLabel;
    String? componentDetail;
    if (json['intake_kind']?.toString() == 'component') {
      final subject = json['subject'];
      final subjectName =
          subject is Map ? subject['name']?.toString().trim() : null;
      final notes = json['subject_notes']?.toString().trim();
      final hasName = subjectName?.isNotEmpty ?? false;
      final hasNotes = notes?.isNotEmpty ?? false;
      componentLabel = hasName
          ? subjectName
          : hasNotes
              ? notes
              : 'Componente recibido';
      if (hasName &&
          hasNotes &&
          notes!.toLowerCase() != subjectName!.toLowerCase()) {
        componentDetail = notes;
      }
    }
    final quotation = json['quotation_status']?.toString().trim();
    return TaskLinkableJob(
      id: json['id'].toString(),
      jobNumber: json['job_number']?.toString() ?? '—',
      status: json['status']?.toString(),
      customerName: customer is Map ? customer['name']?.toString() : null,
      clientRequest: json['client_request']?.toString(),
      statusLabel: statusLabel,
      bikeLabel: bikeLabel.isEmpty ? null : bikeLabel,
      quotationStatus:
          quotation == null || quotation.isEmpty ? null : quotation,
      hasInvoice: json['invoice_id'] != null || json['is_invoiced'] == true,
      isPaid: json['is_paid'] == true,
      receivedAt: DateTime.tryParse(json['arrival_date']?.toString() ?? '') ??
          DateTime.tryParse(json['created_at']?.toString() ?? ''),
      workFinished: workFinished,
      componentLabel: componentLabel,
      componentDetail: componentDetail,
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
