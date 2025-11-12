/// Database backup model
class DatabaseBackup {
  final String id;
  final String tenantId;
  final String backupName;
  final String backupType; // 'manual', 'automatic', 'scheduled'
  final String status; // 'in_progress', 'completed', 'failed', 'restored'
  final Map<String, dynamic>? summary;
  final DateTime createdAt;
  final String? createdBy;
  final DateTime? restoredAt;
  final String? restoredBy;
  final int? backupSizeBytes;
  final String? notes;
  final String? errorMessage;

  DatabaseBackup({
    required this.id,
    required this.tenantId,
    required this.backupName,
    required this.backupType,
    required this.status,
    this.summary,
    required this.createdAt,
    this.createdBy,
    this.restoredAt,
    this.restoredBy,
    this.backupSizeBytes,
    this.notes,
    this.errorMessage,
  });

  factory DatabaseBackup.fromJson(Map<String, dynamic> json) {
    return DatabaseBackup(
      id: json['id'] as String,
      tenantId: json['tenant_id'] as String,
      backupName: json['backup_name'] as String,
      backupType: json['backup_type'] as String,
      status: json['status'] as String,
      summary: json['summary'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['created_at'] as String),
      createdBy: json['created_by'] as String?,
      restoredAt: json['restored_at'] != null
          ? DateTime.parse(json['restored_at'] as String)
          : null,
      restoredBy: json['restored_by'] as String?,
      backupSizeBytes: json['backup_size_bytes'] as int?,
      notes: json['notes'] as String?,
      errorMessage: json['error_message'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'backup_name': backupName,
      'backup_type': backupType,
      'status': status,
      'summary': summary,
      'created_at': createdAt.toIso8601String(),
      'created_by': createdBy,
      'restored_at': restoredAt?.toIso8601String(),
      'restored_by': restoredBy,
      'backup_size_bytes': backupSizeBytes,
      'notes': notes,
      'error_message': errorMessage,
    };
  }

  /// Get human-readable size
  String get sizeMB {
    if (backupSizeBytes == null) return 'N/A';
    return '${(backupSizeBytes! / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  /// Get summary value for a specific key
  int getSummaryCount(String key) {
    if (summary == null) return 0;
    return (summary![key] as num?)?.toInt() ?? 0;
  }
}

/// Backup schedule configuration
class BackupSchedule {
  final String id;
  final String tenantId;
  final bool enabled;
  final String frequency; // 'hourly', 'daily', 'weekly', 'monthly'
  final String? timeOfDay; // HH:MM:SS format
  final int? dayOfWeek; // 0-6 (0 = Sunday)
  final int? dayOfMonth; // 1-31
  final int keepLastNBackups;
  final bool autoDeleteOld;
  final DateTime? lastRunAt;
  final DateTime? nextRunAt;

  BackupSchedule({
    required this.id,
    required this.tenantId,
    required this.enabled,
    required this.frequency,
    this.timeOfDay,
    this.dayOfWeek,
    this.dayOfMonth,
    required this.keepLastNBackups,
    required this.autoDeleteOld,
    this.lastRunAt,
    this.nextRunAt,
  });

  factory BackupSchedule.fromJson(Map<String, dynamic> json) {
    return BackupSchedule(
      id: json['id'] as String,
      tenantId: json['tenant_id'] as String,
      enabled: json['enabled'] as bool,
      frequency: json['frequency'] as String,
      timeOfDay: json['time_of_day'] as String?,
      dayOfWeek: json['day_of_week'] as int?,
      dayOfMonth: json['day_of_month'] as int?,
      keepLastNBackups: json['keep_last_n_backups'] as int,
      autoDeleteOld: json['auto_delete_old'] as bool,
      lastRunAt: json['last_run_at'] != null
          ? DateTime.parse(json['last_run_at'] as String)
          : null,
      nextRunAt: json['next_run_at'] != null
          ? DateTime.parse(json['next_run_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'enabled': enabled,
      'frequency': frequency,
      'time_of_day': timeOfDay,
      'day_of_week': dayOfWeek,
      'day_of_month': dayOfMonth,
      'keep_last_n_backups': keepLastNBackups,
      'auto_delete_old': autoDeleteOld,
      'last_run_at': lastRunAt?.toIso8601String(),
      'next_run_at': nextRunAt?.toIso8601String(),
    };
  }

  BackupSchedule copyWith({
    String? id,
    String? tenantId,
    bool? enabled,
    String? frequency,
    String? timeOfDay,
    int? dayOfWeek,
    int? dayOfMonth,
    int? keepLastNBackups,
    bool? autoDeleteOld,
    DateTime? lastRunAt,
    DateTime? nextRunAt,
  }) {
    return BackupSchedule(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      enabled: enabled ?? this.enabled,
      frequency: frequency ?? this.frequency,
      timeOfDay: timeOfDay ?? this.timeOfDay,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      dayOfMonth: dayOfMonth ?? this.dayOfMonth,
      keepLastNBackups: keepLastNBackups ?? this.keepLastNBackups,
      autoDeleteOld: autoDeleteOld ?? this.autoDeleteOld,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      nextRunAt: nextRunAt ?? this.nextRunAt,
    );
  }
}

/// Result of backup/restore operation
class BackupResult {
  final bool success;
  final String? backupId;
  final Map<String, dynamic>? summary;
  final double? sizeMB;
  final int? tablesRestored;
  final String? error;

  BackupResult({
    required this.success,
    this.backupId,
    this.summary,
    this.sizeMB,
    this.tablesRestored,
    this.error,
  });

  factory BackupResult.fromJson(Map<String, dynamic> json) {
    return BackupResult(
      success: json['success'] as bool,
      backupId: json['backup_id'] as String?,
      summary: json['summary'] as Map<String, dynamic>?,
      sizeMB: (json['size_mb'] as num?)?.toDouble(),
      tablesRestored: json['tables_restored'] as int?,
      error: json['error'] as String?,
    );
  }
}

/// Lightweight backup summary (without full data)
class BackupSummary {
  final String id;
  final String backupName;
  final String backupType;
  final String status;
  final Map<String, dynamic>? summary;
  final double? sizeMB;
  final DateTime createdAt;
  final String? notes;

  BackupSummary({
    required this.id,
    required this.backupName,
    required this.backupType,
    required this.status,
    this.summary,
    this.sizeMB,
    required this.createdAt,
    this.notes,
  });

  factory BackupSummary.fromJson(Map<String, dynamic> json) {
    return BackupSummary(
      id: json['id'] as String,
      backupName: json['backup_name'] as String,
      backupType: json['backup_type'] as String,
      status: json['status'] as String,
      summary: json['summary'] as Map<String, dynamic>?,
      sizeMB: (json['size_mb'] as num?)?.toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
      notes: json['notes'] as String?,
    );
  }

  int getSummaryCount(String key) {
    if (summary == null) return 0;
    return (summary![key] as num?)?.toInt() ?? 0;
  }
}
