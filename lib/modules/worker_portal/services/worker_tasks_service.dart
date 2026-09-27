import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Proyección mínima de una tarea para el portal del trabajador
/// (`get_my_worker_tasks_v1`): trabajo, bicicletas y servicios sin precios ni
/// PII, y sin hilo — el principal de portal no es principal de mensajería.
class WorkerTaskView {
  final String id;
  final String title;
  final String? description;
  final String status;
  final String priority;
  final DateTime? dueDate;
  final int version;
  final DateTime? acknowledgedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? blockedReason;
  final DateTime createdAt;
  final String? creatorName;

  /// Quién LE ASIGNÓ la tarea (`assigned_by`). Null en asignaciones legacy.
  final String? assignerName;
  final String? jobId;
  final String? jobNumber;
  final List<String> bikeLabels;

  /// [{job_item_id, item_name, item_instructions, item_type, bike_label,
  /// invalidated?, context_changed?, done_at?, done_by_name?}]
  final List<Map<String, dynamic>> jobItems;

  /// «Dónde quedó»: la nota vigente para quien siga, con quién y cuándo.
  final String? handoffNote;
  final DateTime? handoffNoteAt;
  final String? handoffNoteByName;

  const WorkerTaskView({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    required this.dueDate,
    required this.version,
    required this.acknowledgedAt,
    required this.startedAt,
    required this.completedAt,
    required this.blockedReason,
    required this.createdAt,
    required this.creatorName,
    required this.assignerName,
    required this.jobId,
    required this.jobNumber,
    required this.bikeLabels,
    required this.jobItems,
    this.handoffNote,
    this.handoffNoteAt,
    this.handoffNoteByName,
  });

  factory WorkerTaskView.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) =>
        value == null ? null : DateTime.tryParse(value.toString());
    return WorkerTaskView(
      id: json['id'].toString(),
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      status: json['status']?.toString() ?? 'pending',
      priority: json['priority']?.toString() ?? 'normal',
      dueDate: parseDate(json['due_date']),
      version: (json['version'] as num?)?.toInt() ?? 1,
      acknowledgedAt: parseDate(json['acknowledged_at']),
      startedAt: parseDate(json['started_at']),
      completedAt: parseDate(json['completed_at']),
      blockedReason: json['blocked_reason']?.toString(),
      createdAt: parseDate(json['created_at']) ?? DateTime.now(),
      creatorName: json['creator_name']?.toString(),
      assignerName: json['assigner_name']?.toString(),
      jobId: json['job_id']?.toString(),
      jobNumber: json['job_number']?.toString(),
      bikeLabels: ((json['bike_labels'] as List?) ?? const [])
          .map((label) => label.toString())
          .toList(),
      jobItems: ((json['job_items'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
      handoffNote: (json['handoff_note']?.toString().trim().isEmpty ?? true)
          ? null
          : json['handoff_note'].toString().trim(),
      handoffNoteAt: parseDate(json['handoff_note_at']),
      handoffNoteByName: json['handoff_note_by_name']?.toString(),
    );
  }

  /// Nombre a mostrar como «Asignada por …»: quien asignó; el creador SOLO
  /// como fallback explícito de asignaciones legacy sin `assigned_by`.
  String? get displayAssignerName => assignerName ?? creatorName;

  bool get awaitsAcknowledgement =>
      acknowledgedAt == null && status != 'completed' && status != 'cancelled';
  bool get isBlocked => status == 'blocked';
  bool get isDone => status == 'completed' || status == 'cancelled';

  /// Vencida es cuando su día ya pasó: el plazo es una fecha de calendario
  /// guardada como las 00:00 UTC de ese día, y se lee por sus campos.
  bool isOverdueAt(DateTime now) {
    final due = dueDate;
    if (due == null || isDone) return false;
    return DateTime(due.year, due.month, due.day)
        .isBefore(DateTime(now.year, now.month, now.day));
  }
}

/// Acceso del portal a su bandeja: proyección + comandos acotados
/// (aceptar/devolver/iniciar/bloquear/desbloquear/completar), idempotentes y
/// versionados. La autoridad fina vive en el servidor.
class WorkerTasksService {
  WorkerTasksService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static const _uuid = Uuid();

  Future<List<WorkerTaskView>> fetchMyTasks() async {
    final rows = await _client.rpc('get_my_worker_tasks_v1');
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => WorkerTaskView.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<WorkerTaskView> sendCommand(
    String taskId, {
    required String command,
    int? expectedVersion,
    Map<String, dynamic> payload = const {},
  }) async {
    final result = await _client.rpc('worker_task_command_v1', params: {
      'p_task_id': taskId,
      'p_expected_version': expectedVersion,
      'p_command': command,
      'p_payload': payload,
      'p_idempotency_key': _uuid.v4(),
    });
    final map = Map<String, dynamic>.from(result as Map);
    return WorkerTaskView.fromJson(
        Map<String, dynamic>.from(map['task'] as Map));
  }

  Future<WorkerTaskView> acknowledge(String taskId) =>
      sendCommand(taskId, command: 'acknowledge');
  Future<WorkerTaskView> start(String taskId, {int? expectedVersion}) =>
      sendCommand(taskId, command: 'start', expectedVersion: expectedVersion);
  Future<WorkerTaskView> block(String taskId, String reason,
          {int? expectedVersion}) =>
      sendCommand(taskId,
          command: 'block',
          expectedVersion: expectedVersion,
          payload: {'reason': reason});
  Future<WorkerTaskView> unblock(String taskId, {int? expectedVersion}) =>
      sendCommand(taskId, command: 'unblock', expectedVersion: expectedVersion);
  Future<WorkerTaskView> complete(String taskId, {int? expectedVersion}) =>
      sendCommand(taskId,
          command: 'complete', expectedVersion: expectedVersion);
  Future<WorkerTaskView> returnTask(String taskId, String reason) =>
      sendCommand(taskId, command: 'return', payload: {'reason': reason});

  /// Marca un servicio hecho o pendiente. Sin versión esperada: cada marca
  /// dice su estado final, así que dos toques seguidos no chocan.
  Future<WorkerTaskView> setJobItemDone(String taskId, String jobItemId,
          {required bool done}) =>
      sendCommand(taskId,
          command: 'set_job_item_done',
          payload: {'job_item_id': jobItemId, 'done': done});

  /// Deja (o borra, con texto vacío) la nota para el siguiente turno.
  Future<WorkerTaskView> setHandoffNote(String taskId, String? note) =>
      sendCommand(taskId,
          command: 'set_handoff_note', payload: {'note': note?.trim() ?? ''});
}
