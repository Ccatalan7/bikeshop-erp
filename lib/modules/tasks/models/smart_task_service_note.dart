/// La nota vigente de un servicio dentro de una tarea
/// (`smart_task_job_item_notes`, dueño 2026-09-27).
///
/// Cada servicio tiene un hilo: se continúa con una nota nueva o se corrige
/// la propia, y se muestra siempre la última no retirada. La historia completa
/// la da [ServiceTimelineEntry].
class ServiceNote {
  final String jobItemId;
  final String noteId;
  final String body;
  final DateTime createdAt;
  final String? authorName;
  final DateTime? editedAt;

  /// Notas vivas del hilo (la vigente incluida).
  final int count;

  /// La escribió quien mira: puede corregirla o retirarla.
  final bool mine;

  const ServiceNote({
    required this.jobItemId,
    required this.noteId,
    required this.body,
    required this.createdAt,
    required this.authorName,
    required this.editedAt,
    required this.count,
    required this.mine,
  });

  bool get isEdited => editedAt != null;

  /// Fila de `get_smart_task_service_notes_v1` (ERP): `mine` se decide con la
  /// cuenta de quien mira.
  factory ServiceNote.fromErpRow(Map<String, dynamic> row,
      {required String? currentUserId}) {
    return ServiceNote(
      jobItemId: row['job_item_id'].toString(),
      noteId: row['note_id'].toString(),
      body: row['body']?.toString() ?? '',
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.now(),
      authorName: row['author_name']?.toString(),
      editedAt: DateTime.tryParse(row['edited_at']?.toString() ?? ''),
      count: (row['note_count'] as num?)?.toInt() ?? 1,
      mine: currentUserId != null &&
          row['created_by']?.toString() == currentUserId,
    );
  }

  /// El `note` de un servicio en `get_my_worker_tasks_v1` (portal). Null si
  /// el servicio no tiene nota viva.
  static ServiceNote? fromPortalItem(Map<String, dynamic> item) {
    final note = item['note'];
    if (note is! Map) return null;
    final map = Map<String, dynamic>.from(note);
    final body = map['body']?.toString().trim() ?? '';
    if (body.isEmpty || map['id'] == null) return null;
    return ServiceNote(
      jobItemId: item['job_item_id']?.toString() ?? '',
      noteId: map['id'].toString(),
      body: body,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
      authorName: map['author_name']?.toString(),
      editedAt: DateTime.tryParse(map['edited_at']?.toString() ?? ''),
      count: (item['note_count'] as num?)?.toInt() ?? 1,
      mine: map['mine'] == true,
    );
  }
}

/// Qué pasó con un servicio, en su línea de tiempo.
enum ServiceTimelineKind {
  assigned,
  noteWritten,
  noteContinued,
  noteEdited,
  noteWithdrawn,
  done,
  reopened,
  serviceChanged,
  serviceRemoved,
  unknown;

  static ServiceTimelineKind fromWire(String? value) => switch (value) {
        'assigned' => assigned,
        'note_written' => noteWritten,
        'note_continued' => noteContinued,
        'note_edited' => noteEdited,
        'note_withdrawn' => noteWithdrawn,
        'done' => done,
        'reopened' => reopened,
        'service_changed' => serviceChanged,
        'service_removed' => serviceRemoved,
        _ => unknown,
      };
}

/// Una entrada de `get_smart_task_service_timeline_v1`: la sirve el mismo
/// RPC al ERP y al portal, con el nombre y la hora del servidor.
class ServiceTimelineEntry {
  final DateTime occurredAt;
  final ServiceTimelineKind kind;
  final String? actorName;

  /// Lo hizo desde el portal del trabajador. Null si no hay autor (el
  /// taller cambió la línea del trabajo).
  final bool? fromPortal;
  final String? note;

  /// Lo que decía la nota antes de corregirla o retirarla.
  final String? previousNote;
  final String? noteId;

  /// Vino con el encargo, al crear la tarea.
  final bool atCreate;

  /// Trae el texto de la nota vigente.
  final bool isCurrent;

  const ServiceTimelineEntry({
    required this.occurredAt,
    required this.kind,
    this.actorName,
    this.fromPortal,
    this.note,
    this.previousNote,
    this.noteId,
    this.atCreate = false,
    this.isCurrent = false,
  });

  factory ServiceTimelineEntry.fromJson(Map<String, dynamic> row) {
    String? text(dynamic value) {
      final trimmed = value?.toString().trim();
      return trimmed == null || trimmed.isEmpty ? null : trimmed;
    }

    return ServiceTimelineEntry(
      occurredAt: DateTime.tryParse(row['occurred_at']?.toString() ?? '') ??
          DateTime.now(),
      kind: ServiceTimelineKind.fromWire(row['kind']?.toString()),
      actorName: text(row['actor_name']),
      fromPortal: row['from_portal'] as bool?,
      note: text(row['note']),
      previousNote: text(row['previous_note']),
      noteId: row['note_id']?.toString(),
      atCreate: row['at_create'] == true,
      isCurrent: row['is_current'] == true,
    );
  }
}
