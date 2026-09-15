/// Un evento del ledger append-only de la bandeja (`smart_task_events`).
///
/// La actividad del detalle se lee de aquí, nunca se deduce de `updated_at`.
/// Un payload con `source: 'direct'` marca una escritura del cliente legado
/// auditada por el trigger, no un comando RPC.
class SmartTaskEvent {
  final String id;
  final String taskId;
  final String? actorUserId;
  final String eventType;
  final int taskVersion;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  const SmartTaskEvent({
    required this.id,
    required this.taskId,
    required this.actorUserId,
    required this.eventType,
    required this.taskVersion,
    required this.payload,
    required this.createdAt,
  });

  factory SmartTaskEvent.fromJson(Map<String, dynamic> json) {
    return SmartTaskEvent(
      id: json['id'].toString(),
      taskId: json['task_id'].toString(),
      actorUserId: json['actor_user_id']?.toString(),
      eventType: json['event_type'].toString(),
      taskVersion: (json['task_version'] as num?)?.toInt() ?? 0,
      payload: Map<String, dynamic>.from(
        (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      createdAt: DateTime.parse(json['created_at'].toString()),
    );
  }

  bool get isDirectWrite => payload['source'] == 'direct';
}
