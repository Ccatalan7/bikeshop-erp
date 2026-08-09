import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/tenant_service.dart';
import '../models/website_editor_capability.dart';
import 'website_service.dart';

/// Model for website backup
class WebsiteBackup {
  final String id;
  final String name;
  final String? description;
  final int blockCount;
  final bool isAutoBackup;
  final DateTime createdAt;
  final String? createdBy;

  WebsiteBackup({
    required this.id,
    required this.name,
    this.description,
    required this.blockCount,
    required this.isAutoBackup,
    required this.createdAt,
    this.createdBy,
  });

  factory WebsiteBackup.fromJson(Map<String, dynamic> json) {
    return WebsiteBackup(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      blockCount: json['block_count'] as int? ?? 0,
      isAutoBackup: json['is_auto_backup'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      createdBy: json['created_by'] as String?,
    );
  }
}

/// Service for managing website backups
class WebsiteBackupService extends ChangeNotifier {
  WebsiteBackupService({
    SupabaseClient? supabase,
    TenantService? tenantService,
  })  : _supabase = supabase ?? Supabase.instance.client,
        _tenantService = tenantService ?? TenantService();

  final SupabaseClient _supabase;
  final TenantService _tenantService;

  List<WebsiteBackup> _backups = [];
  bool _isLoading = false;
  String? _error;

  List<WebsiteBackup> get backups => _backups;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> _validateTenant(
    String expectedTenantId,
    WebsiteEditorWriteGuard guard,
  ) async {
    guard();
    final liveTenantId = await _tenantService.getTenantId();
    guard();
    if (liveTenantId != expectedTenantId) {
      throw const WebsiteEditorWriteSupersededException(
        'La sesión del editor cambió antes de completar la copia de seguridad.',
      );
    }
  }

  /// Loads backups only for the exact editor tenant captured by the caller.
  Future<List<WebsiteBackup>> loadBackups({
    required String tenantId,
    required WebsiteEditorWriteGuard readGuard,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _validateTenant(tenantId, readGuard);
      final response = await _supabase
          .from('website_backups')
          .select(
              'id, name, description, block_count, is_auto_backup, created_at, created_by')
          .eq('tenant_id', tenantId)
          .order('created_at', ascending: false);
      readGuard();

      _backups = (response as List)
          .map((json) => WebsiteBackup.fromJson(json))
          .toList();
      return _backups;
    } on WebsiteEditorWriteSupersededException {
      rethrow;
    } catch (e) {
      readGuard();
      _error = 'Error loading backups: $e';
      debugPrint(_error);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Create a new backup
  Future<String?> createBackup({
    required String name,
    required String tenantId,
    required WebsiteEditorWriteGuard writeGuard,
    String? description,
    bool isAutoBackup = false,
  }) async {
    try {
      debugPrint('📦 Creating website backup: $name');

      await _validateTenant(tenantId, writeGuard);
      final response = await _supabase.rpc(
        'create_website_backup',
        params: {
          'p_name': name,
          'p_description': description,
          'p_is_auto': isAutoBackup,
        },
      );
      writeGuard();

      final backupId = response as String?;
      if (backupId == null) {
        throw StateError('The backup RPC returned no backup id.');
      }
      debugPrint('✅ Backup created: $backupId');

      // Reload backups list
      await loadBackups(tenantId: tenantId, readGuard: writeGuard);

      return backupId;
    } on WebsiteEditorWriteSupersededException {
      rethrow;
    } catch (e) {
      _error = 'Error creating backup: $e';
      debugPrint(_error);
      notifyListeners();
      rethrow;
    }
  }

  /// Restore a backup
  Future<bool> restoreBackup(
    String backupId, {
    required String tenantId,
    required WebsiteEditorWriteGuard writeGuard,
    bool createSafetyBackup = true,
  }) async {
    try {
      debugPrint('🔄 Restoring backup: $backupId');

      await _validateTenant(tenantId, writeGuard);
      final response = await _supabase.rpc(
        'restore_website_backup',
        params: {
          'p_backup_id': backupId,
          'p_create_safety_backup': createSafetyBackup,
        },
      );
      writeGuard();

      final success = response as bool? ?? false;

      if (success) {
        debugPrint('✅ Backup restored successfully');
        // Reload backups list (will include auto-backup if created)
        await loadBackups(tenantId: tenantId, readGuard: writeGuard);
      }

      return success;
    } on WebsiteEditorWriteSupersededException {
      rethrow;
    } catch (e) {
      _error = 'Error restoring backup: $e';
      debugPrint(_error);
      notifyListeners();
      rethrow;
    }
  }

  /// Delete a backup
  Future<bool> deleteBackup(
    String backupId, {
    required String tenantId,
    required WebsiteEditorWriteGuard writeGuard,
  }) async {
    try {
      await _validateTenant(tenantId, writeGuard);
      final response = await _supabase
          .from('website_backups')
          .delete()
          .eq('tenant_id', tenantId)
          .eq('id', backupId)
          .select('id');
      writeGuard();
      if ((response as List).isEmpty) return false;

      _backups.removeWhere((b) => b.id == backupId);
      notifyListeners();

      debugPrint('🗑️ Backup deleted: $backupId');
      return true;
    } on WebsiteEditorWriteSupersededException {
      rethrow;
    } catch (e) {
      _error = 'Error deleting backup: $e';
      debugPrint(_error);
      notifyListeners();
      rethrow;
    }
  }

  /// Get backup details (with full snapshot data)
  Future<Map<String, dynamic>?> getBackupDetails(String backupId) async {
    try {
      final response = await _supabase
          .from('website_backups')
          .select()
          .eq('id', backupId)
          .single();

      return response;
    } catch (e) {
      debugPrint('Error getting backup details: $e');
      return null;
    }
  }
}
