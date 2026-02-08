import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
      );

      final result = await _db.insert('job_statuses', status.toJson());
      final created = JobStatusCustom.fromJson(result);

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

      await _db.update('job_statuses', status.id!, status.toJson());

      final index = _statuses.indexWhere((s) => s.id == status.id);
      if (index != -1) {
        _statuses[index] = status;
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

  /// Update job to use a specific status
  Future<bool> updateJobStatus(String jobId, String statusId) async {
    try {
      // Ensure statuses are loaded
      if (_statuses.isEmpty) {
        debugPrint(
            '⚠️ [JobStatusService.updateJobStatus] Statuses not loaded, loading now...');
        await loadStatuses();
      }

      var status = getStatusById(statusId);

      // If still not found, try fetching fresh from DB
      if (status == null) {
        debugPrint(
            '⚠️ [JobStatusService.updateJobStatus] Status $statusId not in cache, reloading...');
        await loadStatuses();
        status = getStatusById(statusId);
      }

      if (status == null) {
        debugPrint(
            '❌ [JobStatusService.updateJobStatus] Status still not found after reload: $statusId');
        debugPrint(
            '   Available statuses: ${_statuses.map((s) => '${s.id}: ${s.name}').join(', ')}');
        throw Exception('Status not found: $statusId');
      }

      debugPrint(
          '🔄 [JobStatusService.updateJobStatus] Updating job $jobId to status: ${status.name} (${status.code})');
      debugPrint('   → status_id: $statusId');
      debugPrint('   → status (legacy): ${status.code}');

      final updates = <String, dynamic>{
        'status_id': statusId,
        'status': status.code, // Keep legacy field in sync
        'updated_at': DateTime.now().toIso8601String(),
      };

      // KPI Triggers Logic
      final now = DateTime.now().toIso8601String();
      if (status.triggersStart) {
        updates['started_at'] = now;
      }
      if (status.triggersCompletion) {
        updates['completed_at'] = now;
      }
      if (status.triggersDelivery) {
        updates['delivered_at'] = now;
      }

      final response = await Supabase.instance.client
          .from('mechanic_jobs')
          .update(updates)
          .eq('id', jobId)
          .select(); // Add select to get the response back

      if ((response as List).isEmpty) {
        debugPrint(
            '⚠️ [JobStatusService.updateJobStatus] Empty response - job may not exist: $jobId');
        return false;
      }

      debugPrint(
          '✅ [JobStatusService.updateJobStatus] DB update successful. Response: ${response.first}');

      return true;
    } catch (e, stackTrace) {
      debugPrint('❌ [JobStatusService.updateJobStatus] Error: $e');
      debugPrint('   Stack: $stackTrace');
      return false;
    }
  }

  @override
  void dispose() {
    _statusesChannel?.unsubscribe();
    super.dispose();
  }
}
