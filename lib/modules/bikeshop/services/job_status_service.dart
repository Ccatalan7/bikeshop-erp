import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../models/bikeshop_models.dart';

/// Service for managing custom job statuses (Notion-style)
class JobStatusService extends ChangeNotifier {
  final DatabaseService _db;
  final TenantService _tenantService = TenantService();

  List<JobStatusCustom> _statuses = [];
  bool _isLoading = false;
  String? _error;

  RealtimeChannel? _statusesChannel;

  JobStatusService(this._db) {
    _setupRealtimeSubscription();
    loadStatuses();
  }

  // Getters
  List<JobStatusCustom> get statuses => List.unmodifiable(_statuses);
  List<JobStatusCustom> get activeStatuses =>
      _statuses.where((s) => s.isActive).toList();
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Get statuses grouped by phase
  Map<StatusPhase, List<JobStatusCustom>> get statusesByPhase {
    final grouped = <StatusPhase, List<JobStatusCustom>>{};
    for (final phase in StatusPhase.values) {
      grouped[phase] = activeStatuses.where((s) => s.phase == phase).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }
    return grouped;
  }

  /// Get status by ID
  JobStatusCustom? getStatusById(String? id) {
    if (id == null) return null;
    try {
      return _statuses.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get status by code (for legacy compatibility)
  JobStatusCustom? getStatusByCode(String? code) {
    if (code == null) return null;
    try {
      return _statuses.firstWhere((s) => s.code == code);
    } catch (_) {
      return null;
    }
  }

  Future<void> _setupRealtimeSubscription() async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) return;

      _statusesChannel =
          Supabase.instance.client.channel('job_statuses_$tenantId');

      _statusesChannel!
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'job_statuses',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'tenant_id',
              value: tenantId,
            ),
            callback: (payload) {
              debugPrint('📊 Job statuses changed: ${payload.eventType}');
              loadStatuses();
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('⚠️ Failed to setup job statuses realtime: $e');
    }
  }

  /// Load all statuses for current tenant
  Future<void> loadStatuses() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _db.select(
        'job_statuses',
        orderBy: 'sort_order',
      );

      _statuses = data.map((json) => JobStatusCustom.fromJson(json)).toList();
      _error = null;

      // Auto-configure triggers for default statuses if they haven't been configured yet
      await _ensureDefaultTriggers();
    } catch (e) {
      _error = e.toString();
      debugPrint('❌ Error loading job statuses: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _ensureDefaultTriggers() async {
    bool changesMade = false;

    // Create a new list to allow updates
    final List<JobStatusCustom> updatedStatuses = List.from(_statuses);

    for (int i = 0; i < updatedStatuses.length; i++) {
      final status = updatedStatuses[i];
      final name = status.name.toLowerCase();
      JobStatusCustom? updatedStatus;

      // "En Curso" -> Triggers Start
      if (name == 'en curso' &&
          !status.triggersStart &&
          !status.triggersCompletion &&
          !status.triggersDelivery) {
        debugPrint(
            '🔧 [JobStatusService] Auto-configuring "En Curso" to trigger Start');
        updatedStatus = status.copyWith(triggersStart: true);
        await _db.update('job_statuses', status.id!, {'triggers_start': true});
      }

      // "Finalizado" -> Triggers Completion
      else if (name == 'finalizado' &&
          !status.triggersCompletion &&
          !status.triggersStart &&
          !status.triggersDelivery) {
        debugPrint(
            '🔧 [JobStatusService] Auto-configuring "Finalizado" to trigger Completion');
        updatedStatus = status.copyWith(triggersCompletion: true);
        await _db
            .update('job_statuses', status.id!, {'triggers_completion': true});
      }

      // "Entregado" -> Triggers Delivery
      else if (name == 'entregado' &&
          !status.triggersDelivery &&
          !status.triggersStart &&
          !status.triggersCompletion) {
        debugPrint(
            '🔧 [JobStatusService] Auto-configuring "Entregado" to trigger Delivery');
        updatedStatus = status.copyWith(triggersDelivery: true);
        await _db
            .update('job_statuses', status.id!, {'triggers_delivery': true});
      }

      if (updatedStatus != null) {
        updatedStatuses[i] = updatedStatus;
        changesMade = true;
      }
    }

    if (changesMade) {
      _statuses = updatedStatuses;
      debugPrint(
          '✅ [JobStatusService] Default statuses auto-configured with KPI triggers');
      notifyListeners();
    }
  }

  /// Create a new custom status
  Future<JobStatusCustom?> createStatus({
    required String name,
    required String code,
    String color = '#6B7280',
    StatusPhase phase = StatusPhase.inProgress,
    int? sortOrder,
    bool triggersStart = false,
    bool triggersCompletion = false,
    bool triggersDelivery = false,
    bool promptsSupplyNeedCapture = false,
  }) async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) throw Exception('Tenant not found');

      // If no sort order provided, put at end of phase
      final effectiveSortOrder = sortOrder ??
          (activeStatuses.where((s) => s.phase == phase).fold<int>(
                  0, (max, s) => s.sortOrder > max ? s.sortOrder : max) +
              1);

      final status = JobStatusCustom(
        tenantId: tenantId,
        name: name,
        code: code.toUpperCase().replaceAll(' ', '_'),
        color: color,
        phase: phase,
        sortOrder: effectiveSortOrder,
        isSystem: false,
        triggersStart: triggersStart,
        triggersCompletion: triggersCompletion,
        triggersDelivery: triggersDelivery,
        promptsSupplyNeedCapture: false,
      );

      final result = await _db.insert('job_statuses', status.toJson());
      var created = JobStatusCustom.fromJson(result);
      if (promptsSupplyNeedCapture) {
        created = await _setSupplyNeedCaptureCapability(created, true);
      }

      _statuses.add(created);
      _statuses.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      notifyListeners();

      return created;
    } catch (e) {
      debugPrint('❌ Error creating job status: $e');
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Update an existing status
  Future<bool> updateStatus(JobStatusCustom status) async {
    try {
      if (status.id == null) throw Exception('Status ID required');

      final current = getStatusById(status.id);
      final requestedCapability = status.promptsSupplyNeedCapture;
      final statusFields = status.toJson()
        ..remove('prompts_supply_need_capture');

      await _db.update('job_statuses', status.id!, statusFields);
      var persisted = status.copyWith(
        promptsSupplyNeedCapture: current?.promptsSupplyNeedCapture ?? false,
      );
      if (current?.promptsSupplyNeedCapture != requestedCapability) {
        persisted = await _setSupplyNeedCaptureCapability(
          persisted,
          requestedCapability,
        );
      }

      final index = _statuses.indexWhere((s) => s.id == status.id);
      if (index != -1) {
        _statuses[index] = persisted;
        _statuses.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        notifyListeners();
      }

      return true;
    } catch (e) {
      debugPrint('❌ Error updating job status: $e');
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<JobStatusCustom> _setSupplyNeedCaptureCapability(
    JobStatusCustom status,
    bool enabled,
  ) async {
    final statusId = status.id;
    if (statusId == null) throw Exception('Status ID required');
    final response = await _db.rpc(
      'set_job_status_supply_need_capability_v1',
      params: {
        'p_status_id': statusId,
        'p_enabled': enabled,
        'p_operation_key': const Uuid().v4(),
      },
    );
    if (response is! Map || response['status'] is! Map) {
      throw const FormatException(
        'El servidor no devolvió la capacidad guardada.',
      );
    }
    return JobStatusCustom.fromJson(
      Map<String, dynamic>.from(response['status'] as Map),
    );
  }

  /// Delete a custom status (only non-system statuses)
  Future<bool> deleteStatus(String statusId) async {
    try {
      final status = getStatusById(statusId);
      if (status == null) throw Exception('Status not found');
      if (status.isSystem) throw Exception('Cannot delete system status');

      await _db.delete('job_statuses', statusId);

      _statuses.removeWhere((s) => s.id == statusId);
      notifyListeners();

      return true;
    } catch (e) {
      debugPrint('❌ Error deleting job status: $e');
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Reorder statuses within a phase
  Future<bool> reorderStatuses(List<JobStatusCustom> orderedStatuses) async {
    try {
      for (int i = 0; i < orderedStatuses.length; i++) {
        final status = orderedStatuses[i];
        if (status.sortOrder != i) {
          await _db.update('job_statuses', status.id!, {
            'sort_order': i,
          });
        }
      }

      await loadStatuses();
      return true;
    } catch (e) {
      debugPrint('❌ Error reordering job statuses: $e');
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _statusesChannel?.unsubscribe();
    super.dispose();
  }
}
