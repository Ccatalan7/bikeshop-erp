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

  /// [{item_name, item_instructions, item_type, bike_label, invalidated?,
  /// context_changed?}]
  final List<Map<String, dynamic>> jobItems;

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
    );
  }

  /// Nombre a mostrar como «Asignada por …»: quien asignó; el creador SOLO
  /// como fallback explícito de asignaciones legacy sin `assigned_by`.
  String? get displayAssignerName => assignerName ?? creatorName;

  bool get awaitsAcknowledgement =>
      acknowledgedAt == null && status != 'completed' && status != 'cancelled';
  bool get isBlocked => status == 'blocked';
  bool get isDone => status == 'completed' || status == 'cancelled';
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
}
