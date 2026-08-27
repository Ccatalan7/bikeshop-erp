/// Un servicio real del trabajo respaldando una tarea
/// (`smart_task_job_items`).
///
/// El vínculo conserva snapshot (nombre, instrucciones, trabajo, bicicleta) y
/// sobrevive a la línea: si el taller la borra queda `invalidatedAt`; si la
/// edita, `contextChangedAt`. La UI muestra la marca, nunca esconde la fila.
class SmartTaskJobItem {
  final String id;
  final String taskId;
  final String jobItemId;
  final String jobId;
  final String? jobBikeId;
  final String itemName;
  final String? itemType;
  final String? jobNumber;
  final String? bikeLabel;
  final String? itemInstructions;
  final DateTime linkedAt;
  final DateTime? invalidatedAt;
  final DateTime? contextChangedAt;

  const SmartTaskJobItem({
    required this.id,
    required this.taskId,
    required this.jobItemId,
    required this.jobId,
    required this.jobBikeId,
    required this.itemName,
    required this.itemType,
    required this.jobNumber,
    required this.bikeLabel,
    this.itemInstructions,
    required this.linkedAt,
    required this.invalidatedAt,
    required this.contextChangedAt,
  });

  factory SmartTaskJobItem.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) =>
        value == null ? null : DateTime.tryParse(value.toString());
    final itemInstructions = json['item_instructions']?.toString().trim();
    return SmartTaskJobItem(
      id: json['id'].toString(),
      taskId: json['task_id'].toString(),
      jobItemId: json['job_item_id'].toString(),
      jobId: json['job_id'].toString(),
      jobBikeId: json['job_bike_id']?.toString(),
      itemName: json['item_name']?.toString() ?? '',
      itemType: json['item_type']?.toString(),
      jobNumber: json['job_number']?.toString(),
      bikeLabel: json['bike_label']?.toString(),
      itemInstructions: itemInstructions == null || itemInstructions.isEmpty
          ? null
          : itemInstructions,
      linkedAt: DateTime.tryParse(json['linked_at']?.toString() ?? '') ??
          DateTime.now(),
      invalidatedAt: parseDate(json['invalidated_at']),
      contextChangedAt: parseDate(json['context_changed_at']),
    );
  }

  bool get isInvalidated => invalidatedAt != null;
  bool get contextChanged => contextChangedAt != null;
}
