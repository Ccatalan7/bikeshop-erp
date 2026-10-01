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

  /// Lo que dejó la última restauración de este respaldo (null si nunca se
  /// restauró desde que existe el informe).
  final RestoreReport? restoreReport;

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
    this.restoreReport,
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
      restoreReport: RestoreReport.fromJson(json['restore_report']),
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
  final String? message;

  /// El código con que el servidor se negó o falló (p. ej.
  /// `restore_would_lose_uncovered_data`).
  final String? errorCode;
  final String? recoveryMode;

  bool get preservesNewRecords => recoveryPreservesLive(recoveryMode);

  /// Restaurar: los adjuntos y fotos que no volvieron porque su archivo ya no
  /// estaba. Vacía cuando no faltó ninguno.
  final List<OmittedAttachment> omittedAttachments;

  /// Restaurar: lo que el taller perdería y por lo que no se restauró nada.
  final List<UncoveredDependent> uncoveredDependents;

  /// Recuperar (`restore_missing_keep_live`): lo que volvió, lo que no y
  /// los vínculos que volvieron sueltos.
  final List<RestoreCount> restored;
  final List<RestoreHeldBack> heldBack;
  final List<RestoreDroppedLink> droppedLinks;

  BackupResult({
    required this.success,
    this.backupId,
    this.summary,
    this.sizeMB,
    this.tablesRestored,
    this.error,
    this.message,
    this.errorCode,
    this.recoveryMode,
    this.omittedAttachments = const [],
    this.uncoveredDependents = const [],
    this.restored = const [],
    this.heldBack = const [],
    this.droppedLinks = const [],
  });

  factory BackupResult.fromJson(Map<String, dynamic> json) {
    return BackupResult(
      success: json['success'] as bool,
      backupId: json['backup_id'] as String?,
      summary: json['summary'] as Map<String, dynamic>?,
      sizeMB: (json['size_mb'] as num?)?.toDouble(),
      tablesRestored: json['tables_restored'] as int?,
      // Las negativas del servidor traen `message` y no `error`.
      error: (json['error'] ?? json['message']) as String?,
      message: json['message'] as String?,
      errorCode: json['error_code'] as String?,
      recoveryMode: json['recovery_mode'] as String?,
      omittedAttachments: OmittedAttachment.listFrom(
        json['omitted_attachments'],
      ),
      uncoveredDependents: UncoveredDependent.listFrom(
        json['uncovered_dependents'],
      ),
      restored: RestoreCount.listFrom(json['restored']),
      heldBack: RestoreHeldBack.listFrom(json['not_restored']),
      droppedLinks: RestoreDroppedLink.listFrom(json['links_dropped']),
    );
  }
}

/// Los modos que conservan lo que existe hoy: el de 20260930092309 y el de
/// 20260930172000 («vuelve lo que falta; lo que existe hoy manda»).
bool recoveryPreservesLive(String? mode) =>
    mode == 'merge_preserve_live' || mode == 'restore_missing_keep_live';

int _count(Object? value) => (value as num?)?.toInt() ?? 0;

List<String> _strings(Object? value) => [
      if (value is List)
        for (final item in value)
          if (item is String && item.isNotEmpty) item,
    ];

/// Un tipo de registro y cuántos: «líneas de los trabajos · 2», con ejemplos
/// («Trabajo PG-00131»).
class RestoreCount {
  final String table;
  final String label;
  final int rows;
  final List<String> examples;

  const RestoreCount({
    required this.table,
    required this.label,
    required this.rows,
    this.examples = const [],
  });

  factory RestoreCount.fromJson(Map<String, dynamic> json) => RestoreCount(
        table: json['table'] as String? ?? '',
        label: json['label'] as String? ?? '',
        rows: _count(json['rows']),
        examples: _strings(json['examples']),
      );

  static List<RestoreCount> listFrom(Object? value) => [
        if (value is List)
          for (final item in value)
            if (item is Map)
              RestoreCount.fromJson(item.cast<String, dynamic>()),
      ];
}

/// Lo que el respaldo trae y no vuelve, y por qué.
class RestoreHeldBack {
  final String table;
  final String label;
  final int rows;

  /// `root_live`: su trabajo, bici o tarea existe hoy y conserva lo suyo;
  /// `root_not_restored`: su trabajo, bici o tarea no vuelve;
  /// `parent_missing`: falta un registro que necesita;
  /// `conflict`: choca con un registro de hoy.
  final String reason;

  /// «trabajo», «bici» o «tarea».
  final String? rootLabel;
  final List<RestoreCount> parents;
  final List<String> examples;

  const RestoreHeldBack({
    required this.table,
    required this.label,
    required this.rows,
    required this.reason,
    this.rootLabel,
    this.parents = const [],
    this.examples = const [],
  });

  factory RestoreHeldBack.fromJson(Map<String, dynamic> json) =>
      RestoreHeldBack(
        table: json['table'] as String? ?? '',
        label: json['label'] as String? ?? '',
        rows: _count(json['rows']),
        reason: json['reason'] as String? ?? '',
        rootLabel: json['root_label'] as String?,
        parents: RestoreCount.listFrom(json['parents']),
        examples: _strings(json['examples']),
      );

  static List<RestoreHeldBack> listFrom(Object? value) => [
        if (value is List)
          for (final item in value)
            if (item is Map)
              RestoreHeldBack.fromJson(item.cast<String, dynamic>()),
      ];

  /// Por qué, en palabras del taller.
  String get explanation {
    final root = rootLabel ?? 'registro';
    return switch (reason) {
      'root_live' => 'Su $root existe hoy y se queda con lo que tiene hoy.',
      'root_not_restored' => 'Su $root no vuelve.',
      'parent_missing' => parents.isEmpty
          ? 'Falta un registro que necesita.'
          : 'Faltan registros necesarios de '
              '${parents.map((p) => p.label).join(', ')}, que necesita.',
      'conflict' => 'Choca con un registro de hoy (mismo número, código o '
          'correo).',
      _ => 'No vuelve.',
    };
  }
}

/// Registros que vuelven sin un vínculo porque aquello a lo que apuntaban ya
/// no existe (o, en el caso del portal, porque un acceso no se repone).
class RestoreDroppedLink {
  final String table;
  final String label;
  final String parentLabel;
  final int rows;

  const RestoreDroppedLink({
    required this.table,
    required this.label,
    required this.parentLabel,
    required this.rows,
  });

  factory RestoreDroppedLink.fromJson(Map<String, dynamic> json) =>
      RestoreDroppedLink(
        table: json['table'] as String? ?? '',
        label: json['label'] as String? ?? '',
        parentLabel: json['parent_label'] as String? ?? '',
        rows: _count(json['rows']),
      );

  static List<RestoreDroppedLink> listFrom(Object? value) => [
        if (value is List)
          for (final item in value)
            if (item is Map)
              RestoreDroppedLink.fromJson(item.cast<String, dynamic>()),
      ];
}

/// Datos que el respaldo guarda y la recuperación no toca (ventas, compras,
/// contabilidad, inventario, mensajes, sitio, ajustes, productos, personal):
/// cuántos del respaldo ya no existen hoy.
class RestorePreserved {
  final String table;
  final String label;
  final int backedRows;
  final int? missingRows;

  const RestorePreserved({
    required this.table,
    required this.label,
    required this.backedRows,
    this.missingRows,
  });

  factory RestorePreserved.fromJson(Map<String, dynamic> json) =>
      RestorePreserved(
        table: json['table'] as String? ?? '',
        label: json['label'] as String? ?? '',
        backedRows: _count(json['backed_rows']),
        missingRows: (json['missing_rows'] as num?)?.toInt(),
      );

  static List<RestorePreserved> listFrom(Object? value) => [
        if (value is List)
          for (final item in value)
            if (item is Map)
              RestorePreserved.fromJson(item.cast<String, dynamic>()),
      ];
}

/// Un adjunto de un trabajo o una foto de una bici que el respaldo guarda pero
/// cuyo archivo ya no está: la restauración trae el registro sin él.
class OmittedAttachment {
  final String table;
  final String recordId;
  final String label;
  final String field;
  final String url;
  final String reason;

  const OmittedAttachment({
    required this.table,
    required this.recordId,
    required this.label,
    required this.field,
    required this.url,
    required this.reason,
  });

  factory OmittedAttachment.fromJson(Map<String, dynamic> json) {
    return OmittedAttachment(
      table: json['table'] as String? ?? '',
      recordId: json['record_id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      field: json['field'] as String? ?? '',
      url: json['url'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
    );
  }

  static List<OmittedAttachment> listFrom(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is Map)
          OmittedAttachment.fromJson(item.cast<String, dynamic>()),
    ];
  }

  /// Cuántos archivos distintos: la foto principal de una bici suele estar
  /// también en su galería, y son dos referencias a un mismo archivo.
  static int distinctFiles(List<OmittedAttachment> omitted) =>
      {for (final item in omitted) item.url}.length;

  /// «Trabajo RB-50» o «Bici Trek Marlin 5».
  String get recordLabel {
    final kind = table == 'mechanic_jobs' ? 'Trabajo' : 'Bici';
    return label.isEmpty ? kind : '$kind $label';
  }

  /// El nombre del archivo, sin la ruta de Storage.
  String get fileName {
    final path = Uri.tryParse(url)?.pathSegments;
    final last = (path == null || path.isEmpty) ? url : path.last;
    return Uri.decodeComponent(last.isEmpty ? url : last);
  }

  /// «foto principal» para la foto de la bici; «adjunto» o «foto» si no.
  String get fieldLabel {
    if (field == 'image_url') return 'foto principal';
    return table == 'mechanic_jobs' ? 'adjunto' : 'foto';
  }
}

/// Datos del taller que el respaldo no guarda y que restaurar perdería.
class UncoveredDependent {
  final String table;
  final String label;
  final int rows;
  final String effect;

  const UncoveredDependent({
    required this.table,
    required this.label,
    required this.rows,
    required this.effect,
  });

  factory UncoveredDependent.fromJson(Map<String, dynamic> json) {
    return UncoveredDependent(
      table: json['table'] as String? ?? '',
      label: json['label'] as String? ?? '',
      rows: (json['rows'] as num?)?.toInt() ?? 0,
      effect: json['effect'] as String? ?? '',
    );
  }

  static List<UncoveredDependent> listFrom(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is Map)
          UncoveredDependent.fromJson(item.cast<String, dynamic>()),
    ];
  }
}

/// La consulta antes de ofrecer Restaurar (`restore_backup_preflight`).
///
/// No se puede restaurar si al respaldo le faltan tablas (es de una versión
/// anterior), si se perderían datos que no devuelve, o si cambiaron los
/// proveedores o las facturas de compra, que el motor exige iguales.
class RestorePreflight {
  final bool canRestore;
  final String? message;
  final String? recoveryMode;
  final int? changedRecords;

  bool get preservesNewRecords => recoveryPreservesLive(recoveryMode);

  /// «Vuelve lo que falta; lo que existe hoy manda» (20260930172000).
  bool get restoresMissingOnly => recoveryMode == 'restore_missing_keep_live';

  final List<RestoreCount> restored;
  final List<RestoreHeldBack> heldBack;
  final List<RestoreDroppedLink> droppedLinks;
  final List<RestorePreserved> preserved;

  /// Registros del respaldo que existen hoy y quedan como están.
  final int existingRecords;

  /// Las tablas que restaurar borraría y el respaldo no trae, en palabras
  /// del taller («mensajes»).
  final List<String> missingTables;
  final List<UncoveredDependent> uncoveredDependents;

  /// Por qué el motor la negaría aunque no se pierda nada («Desde este
  /// respaldo cambiaron los proveedores…»), o null.
  final String? foundationBlocker;
  final List<OmittedAttachment> omittedAttachments;

  const RestorePreflight({
    required this.canRestore,
    this.message,
    this.recoveryMode,
    this.changedRecords,
    this.missingTables = const [],
    this.uncoveredDependents = const [],
    this.foundationBlocker,
    this.omittedAttachments = const [],
    this.restored = const [],
    this.heldBack = const [],
    this.droppedLinks = const [],
    this.preserved = const [],
    this.existingRecords = 0,
  });

  factory RestorePreflight.fromJson(Map<String, dynamic> json) {
    final missing = json['missing_tables'];
    final blocker = json['foundation_blocker'];
    return RestorePreflight(
      canRestore: json['can_restore'] as bool? ?? false,
      message: json['message'] as String?,
      recoveryMode: json['recovery_mode'] as String?,
      changedRecords: (json['changed_rows'] as num?)?.toInt(),
      missingTables: [
        if (missing is List)
          for (final item in missing)
            if (item is Map) '${item['label'] ?? item['table']}',
      ],
      uncoveredDependents: UncoveredDependent.listFrom(
        json['uncovered_dependents'],
      ),
      foundationBlocker: blocker is Map ? blocker['message'] as String? : null,
      omittedAttachments: OmittedAttachment.listFrom(
        json['omitted_attachments'],
      ),
      restored: RestoreCount.listFrom(json['restored']),
      heldBack: RestoreHeldBack.listFrom(json['not_restored']),
      droppedLinks: RestoreDroppedLink.listFrom(json['links_dropped']),
      preserved: RestorePreserved.listFrom(json['preserved']),
      existingRecords: _count(json['existing_rows']),
    );
  }
}

/// El informe de la última restauración, guardado en el respaldo.
class RestoreReport {
  final DateTime? restoredAt;
  final List<OmittedAttachment> omittedAttachments;
  final String? recoveryMode;
  final int updatedRecords;
  final int insertedRecords;

  bool get preservesNewRecords => recoveryPreservesLive(recoveryMode);
  bool get restoresMissingOnly => recoveryMode == 'restore_missing_keep_live';

  const RestoreReport({
    this.restoredAt,
    this.omittedAttachments = const [],
    this.recoveryMode,
    this.updatedRecords = 0,
    this.insertedRecords = 0,
  });

  static RestoreReport? fromJson(Object? value) {
    if (value is! Map) return null;
    final json = value.cast<String, dynamic>();
    final restoredAt = json['restored_at'];
    final changes = json['changed_rows'];
    return RestoreReport(
      restoredAt: restoredAt is String
          ? DateTime.tryParse(restoredAt)?.toLocal()
          : null,
      recoveryMode: json['recovery_mode'] as String?,
      updatedRecords:
          changes is Map ? (changes['updated'] as num?)?.toInt() ?? 0 : 0,
      insertedRecords:
          changes is Map ? (changes['inserted'] as num?)?.toInt() ?? 0 : 0,
      omittedAttachments: OmittedAttachment.listFrom(
        json['omitted_attachments'],
      ),
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
