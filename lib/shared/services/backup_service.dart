import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/backup.dart';
import 'tenant_service.dart';

/// Service for managing database backups and restores
class BackupService extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;
  final TenantService _tenantService = TenantService();

  List<DatabaseBackup> _backups = [];
  BackupSchedule? _schedule;
  bool _isLoading = false;

  List<DatabaseBackup> get backups => _backups;
  BackupSchedule? get schedule => _schedule;
  bool get isLoading => _isLoading;

  /// Load all backups for current tenant
  Future<void> loadBackups() async {
    _isLoading = true;
    notifyListeners();

    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) throw Exception('No tenant ID found');

      final response = await _client
          .from('database_backups')
          .select()
          .eq('tenant_id', tenantId)
          .order('created_at', ascending: false);

      _backups = (response as List)
          .map((json) => DatabaseBackup.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('❌ Error loading backups: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Create a new manual backup
  Future<BackupResult> createBackup({
    required String backupName,
    String? notes,
  }) async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) throw Exception('No tenant ID found');

      debugPrint('📦 Creating backup: $backupName');

      final response = await _client.rpc('create_backup', params: {
        'p_tenant_id': tenantId,
        'p_backup_name': backupName,
        'p_backup_type': 'manual',
        'p_notes': notes,
      });

      debugPrint('🔍 Backup response type: ${response.runtimeType}');
      debugPrint('🔍 Backup response: $response');

      // Handle different response formats
      Map<String, dynamic> responseData;
      if (response is Map<String, dynamic>) {
        responseData = response;
      } else if (response is List && response.isNotEmpty) {
        responseData = response.first as Map<String, dynamic>;
      } else {
        throw Exception('Unexpected response format: ${response.runtimeType}');
      }

      final result = BackupResult.fromJson(responseData);

      if (result.success) {
        await loadBackups(); // Reload list
        debugPrint('✅ Backup created: ${result.backupId}');
      }

      return result;
    } catch (e) {
      debugPrint('❌ Error creating backup: $e');
      return BackupResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Restore database from backup
  Future<BackupResult> restoreBackup(String backupId) async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) throw Exception('No tenant ID found');

      debugPrint('🔄 Restoring backup: $backupId');

      final response = await _client.rpc('restore_backup', params: {
        'p_backup_id': backupId,
        'p_tenant_id': tenantId,
      });

      debugPrint('🔍 Restore response type: ${response.runtimeType}');
      debugPrint('🔍 Restore response: $response');

      // Handle different response formats
      Map<String, dynamic> responseData;
      if (response is Map<String, dynamic>) {
        responseData = response;
      } else if (response is List && response.isNotEmpty) {
        responseData = response.first as Map<String, dynamic>;
      } else {
        throw Exception('Unexpected response format: ${response.runtimeType}');
      }

      final result = BackupResult.fromJson(responseData);

      if (result.success) {
        await loadBackups(); // Reload list
        debugPrint('✅ Backup restored successfully');
      }

      return result;
    } catch (e) {
      debugPrint('❌ Error restoring backup: $e');
      return BackupResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Delete a backup
  Future<void> deleteBackup(String backupId) async {
    try {
      await _client.from('database_backups').delete().eq('id', backupId);

      _backups.removeWhere((b) => b.id == backupId);
      notifyListeners();

      debugPrint('🗑️ Backup deleted: $backupId');
    } catch (e) {
      debugPrint('❌ Error deleting backup: $e');
      rethrow;
    }
  }

  /// Get backup data for download
  Future<Map<String, dynamic>?> getBackupData(String backupId) async {
    try {
      final response = await _client
          .from('database_backups')
          .select('backup_data, backup_name, created_at, summary')
          .eq('id', backupId)
          .single();

      if (response == null) return null;

      return {
        'backup_name': response['backup_name'],
        'created_at': response['created_at'],
        'summary': response['summary'],
        'data': response['backup_data'],
      };
    } catch (e) {
      debugPrint('❌ Error getting backup data: $e');
      return null;
    }
  }

  /// Convert backup data to downloadable JSON string
  String? backupToJsonString(Map<String, dynamic> backupData) {
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(backupData);
    } catch (e) {
      debugPrint('❌ Error converting backup to JSON: $e');
      return null;
    }
  }

  /// Get backup schedule settings
  Future<void> loadSchedule() async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) throw Exception('No tenant ID found');

      final response = await _client
          .from('backup_schedules')
          .select()
          .eq('tenant_id', tenantId)
          .maybeSingle();

      if (response != null) {
        _schedule = BackupSchedule.fromJson(response);
      } else {
        // Create default schedule if none exists
        _schedule = BackupSchedule(
          id: '',
          tenantId: tenantId,
          enabled: false,
          frequency: 'daily',
          keepLastNBackups: 7,
          autoDeleteOld: true,
        );
      }

      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error loading schedule: $e');
      rethrow;
    }
  }

  /// Update backup schedule settings
  Future<void> updateSchedule(BackupSchedule schedule) async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) throw Exception('No tenant ID found');

      final data = schedule.toJson();
      data['tenant_id'] = tenantId;
      data['updated_at'] = DateTime.now().toIso8601String();

      if (schedule.id.isEmpty) {
        // Insert new schedule
        final response = await _client
            .from('backup_schedules')
            .insert(data)
            .select()
            .single();
        _schedule = BackupSchedule.fromJson(response);
      } else {
        // Update existing schedule
        await _client
            .from('backup_schedules')
            .update(data)
            .eq('id', schedule.id);
        _schedule = schedule;
      }

      notifyListeners();
      debugPrint('✅ Backup schedule updated');
    } catch (e) {
      debugPrint('❌ Error updating schedule: $e');
      rethrow;
    }
  }

  /// Get backup summary (lightweight, doesn't load full data)
  Future<BackupSummary?> getBackupSummary(String backupId) async {
    try {
      final response = await _client.rpc('get_backup_summary', params: {
        'p_backup_id': backupId,
      });

      if (response == null) return null;

      return BackupSummary.fromJson(response);
    } catch (e) {
      debugPrint('❌ Error getting backup summary: $e');
      return null;
    }
  }

  /// Cleanup old backups based on retention policy
  Future<Map<String, dynamic>> cleanupOldBackups() async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) throw Exception('No tenant ID found');

      final response = await _client.rpc('cleanup_old_backups', params: {
        'p_tenant_id': tenantId,
      });

      await loadBackups(); // Reload list

      return response as Map<String, dynamic>;
    } catch (e) {
      debugPrint('❌ Error cleaning up old backups: $e');
      rethrow;
    }
  }
}
