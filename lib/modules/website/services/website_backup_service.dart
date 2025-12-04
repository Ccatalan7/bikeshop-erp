import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  final _supabase = Supabase.instance.client;
  
  List<WebsiteBackup> _backups = [];
  bool _isLoading = false;
  String? _error;

  List<WebsiteBackup> get backups => _backups;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Load all backups for current tenant
  /// Returns the list of backups for convenience
  Future<List<WebsiteBackup>> loadBackups() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _supabase
          .from('website_backups')
          .select('id, name, description, block_count, is_auto_backup, created_at, created_by')
          .order('created_at', ascending: false);

      _backups = (response as List)
          .map((json) => WebsiteBackup.fromJson(json))
          .toList();
      return _backups;
    } catch (e) {
      _error = 'Error loading backups: $e';
      debugPrint(_error);
      return [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Create a new backup
  Future<String?> createBackup({
    required String name,
    String? description,
    bool isAutoBackup = false,
  }) async {
    try {
      debugPrint('📦 Creating website backup: $name');
      
      final response = await _supabase.rpc(
        'create_website_backup',
        params: {
          'p_name': name,
          'p_description': description,
          'p_is_auto': isAutoBackup,
        },
      );

      final backupId = response as String?;
      debugPrint('✅ Backup created: $backupId');
      
      // Reload backups list
      await loadBackups();
      
      return backupId;
    } catch (e) {
      _error = 'Error creating backup: $e';
      debugPrint(_error);
      notifyListeners();
      return null;
    }
  }

  /// Restore a backup
  Future<bool> restoreBackup(String backupId, {bool createSafetyBackup = true}) async {
    try {
      debugPrint('🔄 Restoring backup: $backupId');
      
      final response = await _supabase.rpc(
        'restore_website_backup',
        params: {
          'p_backup_id': backupId,
          'p_create_safety_backup': createSafetyBackup,
        },
      );

      final success = response as bool? ?? false;
      
      if (success) {
        debugPrint('✅ Backup restored successfully');
        // Reload backups list (will include auto-backup if created)
        await loadBackups();
      }
      
      return success;
    } catch (e) {
      _error = 'Error restoring backup: $e';
      debugPrint(_error);
      notifyListeners();
      return false;
    }
  }

  /// Delete a backup
  Future<bool> deleteBackup(String backupId) async {
    try {
      await _supabase
          .from('website_backups')
          .delete()
          .eq('id', backupId);

      _backups.removeWhere((b) => b.id == backupId);
      notifyListeners();
      
      debugPrint('🗑️ Backup deleted: $backupId');
      return true;
    } catch (e) {
      _error = 'Error deleting backup: $e';
      debugPrint(_error);
      notifyListeners();
      return false;
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
